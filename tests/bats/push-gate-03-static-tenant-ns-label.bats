#!/usr/bin/env bats
# tests/bats/push-gate-03-static-tenant-ns-label.bats
# Phase 11 D-11-03 -- tenant home namespace YAML carries capsule.clastix.io/tenant=<name> label.
# RED until Plan 11-01 lands the edits (Plan 10-02 used --as=alpha/bravo impersonation; this
# is the GitOps source so first push reconciles cleanly).

load 'test_helper'

setup() {
  NS_ALPHA="${REPO_ROOT}/pocs/capsule/spoke/tenants/alpha/namespace.yaml"
  NS_BRAVO="${REPO_ROOT}/pocs/capsule/spoke/tenants/bravo/namespace.yaml"
  K_ALPHA="${REPO_ROOT}/pocs/capsule/spoke/tenants/alpha/kustomization.yaml"
  K_BRAVO="${REPO_ROOT}/pocs/capsule/spoke/tenants/bravo/kustomization.yaml"
  TENANT_CRS_K="${REPO_ROOT}/pocs/capsule/spoke/tenant-crs/kustomization.yaml"
  SPOKE_OUTER_K="${REPO_ROOT}/clusters/hub-flux/pocs/capsule-spoke.yaml"
  TENANT_CRS_OUTER_K="${REPO_ROOT}/clusters/hub-flux/pocs/capsule-spoke-tenants.yaml"
}

@test "D-11-03: tenant home namespaces carry capsule.clastix.io/tenant labels" {
  [ -f "$NS_ALPHA" ]
  [ -f "$NS_BRAVO" ]
  run yq eval '.metadata.labels."capsule.clastix.io/tenant" == "alpha"' "$NS_ALPHA"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
  run yq eval '.metadata.labels."capsule.clastix.io/tenant" == "bravo"' "$NS_BRAVO"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "D-11-07: tenant home kustomizations contain only labeled namespace then owner SA" {
  [ -f "$K_ALPHA" ]
  [ -f "$K_BRAVO" ]
  run yq eval '(.resources | length) == 2 and .resources[0] == "namespace.yaml" and .resources[1] == "sa.yaml"' "$K_ALPHA"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
  run yq eval '(.resources | length) == 2 and .resources[0] == "namespace.yaml" and .resources[1] == "sa.yaml"' "$K_BRAVO"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "D-11-07: Tenant CRs have their own spoke-targeted bootstrap K" {
  [ -f "$TENANT_CRS_K" ]
  [ -f "$TENANT_CRS_OUTER_K" ]
  run yq eval '(.resources | length) == 2 and .resources[0] == "alpha.yaml" and .resources[1] == "bravo.yaml"' "$TENANT_CRS_K"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
  run yq eval '.metadata.name == "poc-capsule-spoke-tenants" and .spec.path == "./pocs/capsule/spoke/tenant-crs" and .spec.serviceAccountName == "flux-reconciler" and .spec.kubeConfig.secretRef.name == "spoke-capsule-kubeconfig"' "$TENANT_CRS_OUTER_K"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "D-11-07: poc-capsule-spoke depends on Tenant CR bootstrap before home namespace apply" {
  [ -f "$SPOKE_OUTER_K" ]
  run yq eval '.spec.dependsOn[].name' "$SPOKE_OUTER_K"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx 'poc-capsule-spoke-tenants'
}
