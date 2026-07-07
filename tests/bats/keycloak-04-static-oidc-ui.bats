#!/usr/bin/env bats
# tests/bats/keycloak-04-static-oidc-ui.bats
# tenant-ui-oidc quick task (2026-07-06) — static pins for the OIDC wiring +
# Headlamp tenant UI. Guards the load-bearing invariants the 2026-07-06
# research established (pinned issuer, PKCE client reuse, proxy-CA projection,
# hostNetwork issuer reachability, Tier-3 OIDC group owners).

load 'test_helper'

setup() {
  KC_CR="${REPO_ROOT}/pocs/keycloak/app/keycloak.yaml"
  NODEPORT="${REPO_ROOT}/pocs/keycloak/app/oidc-nodeport.yaml"
  HL="${REPO_ROOT}/pocs/headlamp/headlamp.yaml"
  HL_K="${REPO_ROOT}/clusters/hub-flux/pocs/headlamp.yaml"
  ALPHA="${REPO_ROOT}/pocs/capsule/spoke/tenant-crs/alpha.yaml"
  BRAVO="${REPO_ROOT}/pocs/capsule/spoke/tenant-crs/bravo.yaml"
  NEWTENANT="${REPO_ROOT}/scripts/poc/capsule/new-tenant.sh"
}

@test "oidc: Keycloak CR pins issuer https://localhost:31443 + tlsSecret keycloak-tls (imperative cert) + keeps http for in-cluster" {
  [ -f "$KC_CR" ]
  run yq eval '.spec.hostname.hostname == "https://localhost:31443" and .spec.http.tlsSecret == "keycloak-tls" and .spec.http.httpEnabled == true' "$KC_CR"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "oidc: keycloak-oidc NodePort is 31443 → 8443 and never touches the operator-managed keycloak-service" {
  [ -f "$NODEPORT" ]
  run yq eval '.kind == "Service" and .metadata.name == "keycloak-oidc" and .spec.type == "NodePort" and .spec.ports[0].nodePort == 31443 and .spec.ports[0].targetPort == 8443' "$NODEPORT"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "headlamp: image pinned v0.43.0, in-cluster endpoint overridden to capsule-proxy" {
  [ -f "$HL" ]
  run grep -F -- 'image: ghcr.io/headlamp-k8s/headlamp:v0.43.0' "$HL"
  [ "$status" -eq 0 ]
  run yq eval-all 'select(.kind == "Deployment") | [.spec.template.spec.containers[0].env[] | select(.name == "KUBERNETES_SERVICE_HOST") | .value] | .[0] == "capsule-proxy.capsule-system.svc"' "$HL"
  [ "$output" = "true" ]
}

@test "headlamp: OIDC via the PUBLIC kubectl client with PKCE against the pinned issuer" {
  [ -f "$HL" ]
  run grep -F -- '-oidc-client-id=kubectl' "$HL"
  [ "$status" -eq 0 ]
  run grep -F -- '-oidc-use-pkce=true' "$HL"
  [ "$status" -eq 0 ]
  run grep -F -- '-oidc-idp-issuer-url=https://localhost:31443/realms/karyon' "$HL"
  [ "$status" -eq 0 ]
}

@test "headlamp: hostNetwork + ClusterFirstWithHostNet (issuer reachable ONLY via node-loopback NodePort)" {
  [ -f "$HL" ]
  run yq eval-all 'select(.kind == "Deployment") | .spec.template.spec.hostNetwork' "$HL"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
  run yq eval-all 'select(.kind == "Deployment") | .spec.template.spec.dnsPolicy' "$HL"
  [ "$output" = "ClusterFirstWithHostNet" ]
}

@test "headlamp: projected SA volume swaps in the capsule-proxy CA (secret capsule-proxy, key ca — NOT capsule-tls, the webhook cert)" {
  [ -f "$HL" ]
  run yq eval-all 'select(.kind == "Deployment") | [.spec.template.spec.volumes[] | select(.name == "proxy-ca-sa") | .projected.sources[] | select(.secret) | .secret.name] | .[0]' "$HL"
  [ "$status" -eq 0 ]
  [ "$output" = "capsule-proxy" ]
  run yq eval-all 'select(.kind == "Deployment") | [.spec.template.spec.volumes[] | select(.name == "proxy-ca-sa") | .projected.sources[] | select(.secret) | .secret.items[0].key + ":" + .secret.items[0].path] | .[0]' "$HL"
  [ "$output" = "ca:ca.crt" ]
}

@test "headlamp: zero-RBAC ServiceAccount (authorization is the USER's token through Capsule)" {
  [ -f "$HL" ]
  run bash -c "grep -E 'kind: (ClusterRole|Role|ClusterRoleBinding|RoleBinding)' '$HL'"
  [ "$status" -ne 0 ]
  run yq eval-all 'select(.kind == "ServiceAccount") | .automountServiceAccountToken == false' "$HL"
  [ "$output" = "true" ]
}

@test "headlamp outer K: P18 kubeConfig + P27 SA + dependsOn capsule DAG" {
  [ -f "$HL_K" ]
  run yq eval '.metadata.name == "poc-headlamp" and .spec.path == "./pocs/headlamp" and .spec.kubeConfig.secretRef.name == "spoke-capsule-kubeconfig" and .spec.serviceAccountName == "flux-reconciler" and .spec.dependsOn[0].name == "poc-capsule-spoke"' "$HL_K"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "tenancy: alpha + bravo carry Tier-3 OIDC Group owners (tenant-<x>-devs, clusterRoles tenant-workload-editor)" {
  for f in "$ALPHA" "$BRAVO"; do
    t=$(yq eval '.metadata.name' "$f")
    run yq eval "[.spec.owners[] | select(.kind == \"Group\" and .name == \"tenant-${t}-devs\") | .clusterRoles] | flatten | any_c(. == \"tenant-workload-editor\")" "$f"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
  done
}

@test "tenancy: new-tenant.sh template renders the tenant-<name>-devs Group owner" {
  [ -f "$NEWTENANT" ]
  run bash -c "grep -A3 'name: tenant-\${NAME}-devs' '$NEWTENANT' | grep -F 'tenant-workload-editor'"
  [ "$status" -eq 0 ]
}
