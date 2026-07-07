#!/usr/bin/env bats
# tests/bats/keycloak-02-static-content.bats
# Keycloak IdP POC (quick task keycloak-idp-poc, 2026-07-06) — content pins for
# the pocs/keycloak/ tree: vendored operator version, tenant shape, namespace
# claim, DB secret indirection, and the OIDC-future-proofing invariants from
# the 2026-07-06 research (flat groups, full.path OFF, PKCE public client).

load 'test_helper'

setup() {
  TENANT="${REPO_ROOT}/pocs/keycloak/tenant-crs/keycloak-tenant.yaml"
  NS="${REPO_ROOT}/pocs/keycloak/spoke/namespace.yaml"
  OPERATOR_K="${REPO_ROOT}/pocs/keycloak/spoke/operator/kustomization.yaml"
  VENDORED="${REPO_ROOT}/pocs/keycloak/spoke/operator/vendored/kubernetes.yml"
  POSTGRES="${REPO_ROOT}/pocs/keycloak/spoke/postgres/postgres.yaml"
  KC_CR="${REPO_ROOT}/pocs/keycloak/app/keycloak.yaml"
  REALM="${REPO_ROOT}/pocs/keycloak/app/realm-karyon.yaml"
  CC="${REPO_ROOT}/pocs/capsule/spoke/config/capsuleconfig.yaml"
}

@test "keycloak Tenant: owned by flux-reconciler SA + capsule-platform-owners Group, forceTenantPrefix false" {
  [ -f "$TENANT" ]
  run yq eval '.kind == "Tenant" and .metadata.name == "keycloak" and .spec.forceTenantPrefix == false and (.spec.owners | length) == 2 and .spec.owners[0].kind == "ServiceAccount" and .spec.owners[0].name == "system:serviceaccount:flux-system:flux-reconciler" and .spec.owners[1].kind == "Group" and .spec.owners[1].name == "capsule-platform-owners"' "$TENANT"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "keycloak Tenant: UNCONSTRAINED — no resourceQuotas / limitRanges / containerRegistries (quay.io must pull)" {
  [ -f "$TENANT" ]
  run yq eval '(.spec.resourceQuotas == null) and (.spec.limitRanges == null) and (.spec.containerRegistries == null)' "$TENANT"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "keycloak namespace: tenant-labeled (the ONLY namespace-creation path Capsule admits) + SSA IfNotPresent" {
  [ -f "$NS" ]
  run yq eval '.kind == "Namespace" and .metadata.name == "keycloak" and .metadata.labels["capsule.clastix.io/tenant"] == "keycloak" and .metadata.annotations["kustomize.toolkit.fluxcd.io/ssa"] == "IfNotPresent"' "$NS"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "vendored operator: image pinned to quay.io/keycloak/keycloak-operator:26.6.4 (bump alongside the vendored CRDs)" {
  [ -f "$VENDORED" ]
  run grep -F -- 'image: quay.io/keycloak/keycloak-operator:26.6.4' "$VENDORED"
  [ "$status" -eq 0 ]
  run grep -F -- 'RELATED_IMAGE_KEYCLOAK' "$VENDORED"
  [ "$status" -eq 0 ]
}

@test "operator kustomization: namespace keycloak + all three vendored files referenced" {
  [ -f "$OPERATOR_K" ]
  run yq eval '.namespace == "keycloak" and (.resources | length) == 3 and (.resources | contains(["vendored/keycloaks.k8s.keycloak.org-v1.yml"])) and (.resources | contains(["vendored/keycloakrealmimports.k8s.keycloak.org-v1.yml"])) and (.resources | contains(["vendored/kubernetes.yml"]))' "$OPERATOR_K"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "postgres + Keycloak CR: credentials ONLY via keycloak-db-secret (imperative; never in git)" {
  [ -f "$POSTGRES" ] && [ -f "$KC_CR" ]
  run bash -c "grep -c 'keycloak-db-secret' '$POSTGRES'"
  [ "$output" -ge 2 ]
  run yq eval '.spec.db.usernameSecret.name == "keycloak-db-secret" and .spec.db.passwordSecret.name == "keycloak-db-secret" and .spec.db.vendor == "postgres" and .spec.db.host == "postgres-db"' "$KC_CR"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
  # No inline credential values anywhere in the tree
  run bash -c "grep -riE 'password:.*[a-z0-9]{8}' ${REPO_ROOT}/pocs/keycloak/ | grep -v 'passwordSecret\|POSTGRES_PASSWORD\|password$'"
  [ "$status" -ne 0 ]
}

@test "realm import: groups mapper full.path=false (the #1 silent Capsule breaker — bare names, never /paths)" {
  [ -f "$REALM" ]
  run yq eval '[.spec.realm.clients[0].protocolMappers[] | select(.name == "groups") | .config["full.path"]] | .[0] == "false"' "$REALM"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "realm import: kubectl client is public + PKCE S256 + kubelogin redirect ports, direct grants off" {
  [ -f "$REALM" ]
  run yq eval '.spec.realm.clients[0].clientId == "kubectl" and .spec.realm.clients[0].publicClient == true and .spec.realm.clients[0].standardFlowEnabled == true and .spec.realm.clients[0].directAccessGrantsEnabled == false and .spec.realm.clients[0].attributes["pkce.code.challenge.method"] == "S256" and (.spec.realm.clients[0].redirectUris | contains(["http://localhost:8000"])) and (.spec.realm.clients[0].redirectUris | contains(["http://localhost:18000"]))' "$REALM"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "realm import: flat groups match CapsuleConfiguration userGroups byte-for-byte" {
  [ -f "$REALM" ] && [ -f "$CC" ]
  for g in capsule-users capsule-platform-owners tenant-alpha-devs tenant-bravo-devs; do
    run yq eval "[.spec.realm.groups[].name] | contains([\"$g\"])" "$REALM"
    [ "$output" = "true" ]
    run yq eval ".spec.userGroups | contains([\"$g\"])" "$CC"
    [ "$output" = "true" ]
  done
}

@test "realm import: seeded users carry NO credentials (passwords are set in the admin UI, never in git)" {
  [ -f "$REALM" ]
  run yq eval '[.spec.realm.users[] | has("credentials")] | any' "$REALM"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}
