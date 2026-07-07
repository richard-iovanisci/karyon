#!/usr/bin/env bats
# tests/bats/keycloak-03-live.bats
# Keycloak IdP POC — live health falsifiers against k3d-spoke-capsule.
# Auto-skips when the cluster is unreachable (live-suite convention) or when
# the POC has not been reconciled + secret-bootstrapped yet.

load 'test_helper'

setup() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
  if ! kubectl --context=k3d-spoke-capsule get namespace keycloak >/dev/null 2>&1; then
    skip "keycloak namespace absent; reconcile poc-keycloak-* + run scripts/poc/keycloak/create-secrets.sh first"
  fi
}

@test "keycloak-live: tenant keycloak Active with 1 namespace claimed" {
  run kubectl --context=k3d-spoke-capsule get tenant keycloak \
    -o jsonpath='{.status.state} {.status.size}'
  [ "$status" -eq 0 ]
  [ "$output" = "Active 1" ]
}

@test "keycloak-live: keycloak-db-secret present (imperative bootstrap done)" {
  run kubectl --context=k3d-spoke-capsule -n keycloak get secret keycloak-db-secret
  [ "$status" -eq 0 ]
}

@test "keycloak-live: operator Deployment Available" {
  run kubectl --context=k3d-spoke-capsule -n keycloak get deployment keycloak-operator \
    -o jsonpath='{.status.conditions[?(@.type=="Available")].status}'
  [ "$status" -eq 0 ]
  [ "$output" = "True" ]
}

@test "keycloak-live: postgres StatefulSet 1/1 ready" {
  run kubectl --context=k3d-spoke-capsule -n keycloak get statefulset postgresql-db \
    -o jsonpath='{.status.readyReplicas}'
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "keycloak-live: Keycloak CR reports Ready=True (operator has provisioned the server)" {
  local i cond
  for i in $(seq 1 30); do
    cond=$(kubectl --context=k3d-spoke-capsule -n keycloak get keycloak keycloak \
      -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
    [[ "$cond" == "True" ]] && return 0
    sleep 10
  done
  echo "Keycloak CR never reached Ready=True (last: '${cond}')"
  return 1
}

@test "keycloak-live: initial admin Secret auto-created by the operator" {
  run kubectl --context=k3d-spoke-capsule -n keycloak get secret keycloak-initial-admin
  [ "$status" -eq 0 ]
}

@test "keycloak-live: karyon realm import Done" {
  run kubectl --context=k3d-spoke-capsule -n keycloak get keycloakrealmimport karyon-realm \
    -o jsonpath='{.status.conditions[?(@.type=="Done")].status}'
  [ "$status" -eq 0 ]
  [ "$output" = "True" ]
}

@test "keycloak-live: karyon realm OIDC discovery served (in-cluster round-trip)" {
  # curl from a throwaway pod would need tenant admission; use the service
  # endpoint via the apiserver proxy instead (read-only, no pod creation).
  run kubectl --context=k3d-spoke-capsule -n keycloak get --raw \
    "/api/v1/namespaces/keycloak/services/keycloak-service:8080/proxy/realms/karyon/.well-known/openid-configuration"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF '"issuer"'
  echo "$output" | grep -qF '/realms/karyon'
}

@test "keycloak-live: GTR hello-world seeded into the keycloak tenant namespace (expected match-all side effect)" {
  run kubectl --context=k3d-spoke-capsule -n keycloak get deployment hello-world
  [ "$status" -eq 0 ]
}

@test "keycloak-live: third-tenant isolation — alpha's proxy-filtered view must NOT include keycloak" {
  # Mint a short-lived alpha tenant kubeconfig (TokenRequest via capsule-proxy;
  # same pattern as the demo live suites).
  local tmpd out
  tmpd="${TMPDIR:-/tmp}/karyon-tenants/bats-kc3-${BATS_RUN_TMPDIR##*/}"
  mkdir -p "$tmpd"
  bash "${REPO_ROOT}/scripts/poc/capsule/issue-tenant-kubeconfig.sh" alpha human-tenant-owner \
    --duration=10m --write-to "${tmpd}/alpha.kubeconfig" >/dev/null 2>&1
  [ -f "${tmpd}/alpha.kubeconfig" ]
  out=$(kubectl --kubeconfig="${tmpd}/alpha.kubeconfig" get namespaces -o name 2>&1)
  [ $? -eq 0 ]
  echo "$out" | grep -qF 'namespace/tenant-alpha'
  ! echo "$out" | grep -qF 'namespace/keycloak'
  out=$(kubectl --kubeconfig="${tmpd}/alpha.kubeconfig" get tenants \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>&1)
  ! echo "$out" | grep -qx 'keycloak'
  rm -rf "$tmpd"
}
