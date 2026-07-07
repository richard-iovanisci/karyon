#!/usr/bin/env bats
# tests/bats/keycloak-01-static-outer-ks.bats
# Keycloak IdP POC (quick task keycloak-idp-poc, 2026-07-06) — outer Flux
# Kustomization contract. Pins the load-bearing shape of the three hub-side
# Kustomizations (P18 kubeConfig block, P27 serviceAccountName, DAG direction
# keycloak→capsule) — the same class of guard as push-gate-06/07 for capsule.

load 'test_helper'

setup() {
  KC_TENANT="${REPO_ROOT}/clusters/hub-flux/pocs/keycloak-tenant.yaml"
  KC_SPOKE="${REPO_ROOT}/clusters/hub-flux/pocs/keycloak-spoke.yaml"
  KC_APP="${REPO_ROOT}/clusters/hub-flux/pocs/keycloak-app.yaml"
}

@test "keycloak outer Ks: poc-keycloak-tenant is spoke-targeted with full kubeConfig block (P18) + flux-reconciler SA (P27)" {
  [ -f "$KC_TENANT" ]
  run yq eval '.apiVersion == "kustomize.toolkit.fluxcd.io/v1" and .kind == "Kustomization" and .metadata.name == "poc-keycloak-tenant" and .metadata.namespace == "flux-system" and .spec.path == "./pocs/keycloak/tenant-crs" and .spec.prune == true and .spec.kubeConfig.secretRef.name == "spoke-capsule-kubeconfig" and .spec.kubeConfig.secretRef.key == "value.yaml" and .spec.serviceAccountName == "flux-reconciler"' "$KC_TENANT"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "keycloak outer Ks: poc-keycloak-tenant dependsOn poc-capsule-spoke (keycloak depends on capsule, NEVER the reverse)" {
  [ -f "$KC_TENANT" ]
  run yq eval '(.spec.dependsOn | length) == 1 and .spec.dependsOn[0].name == "poc-capsule-spoke"' "$KC_TENANT"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "keycloak outer Ks: poc-keycloak-spoke shape (kubeConfig + SA + wait:true + dependsOn tenant — D-11-07 Tenant-before-labeled-ns)" {
  [ -f "$KC_SPOKE" ]
  run yq eval '.metadata.name == "poc-keycloak-spoke" and .spec.path == "./pocs/keycloak/spoke" and .spec.prune == true and .spec.wait == true and .spec.kubeConfig.secretRef.name == "spoke-capsule-kubeconfig" and .spec.kubeConfig.secretRef.key == "value.yaml" and .spec.serviceAccountName == "flux-reconciler" and (.spec.dependsOn | length) == 1 and .spec.dependsOn[0].name == "poc-keycloak-tenant"' "$KC_SPOKE"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "keycloak outer Ks: poc-keycloak-app shape (kubeConfig + SA + dependsOn spoke; wait:false by design)" {
  [ -f "$KC_APP" ]
  run yq eval '.metadata.name == "poc-keycloak-app" and .spec.path == "./pocs/keycloak/app" and .spec.prune == true and .spec.wait == false and .spec.kubeConfig.secretRef.name == "spoke-capsule-kubeconfig" and .spec.kubeConfig.secretRef.key == "value.yaml" and .spec.serviceAccountName == "flux-reconciler" and (.spec.dependsOn | length) == 1 and .spec.dependsOn[0].name == "poc-keycloak-spoke"' "$KC_APP"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "keycloak outer Ks: capsule DAG untouched — no capsule-*.yaml dependsOn references keycloak" {
  run bash -c "grep -l 'keycloak' ${REPO_ROOT}/clusters/hub-flux/pocs/capsule*.yaml"
  [ "$status" -ne 0 ]
}
