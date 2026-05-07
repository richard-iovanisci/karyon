#!/usr/bin/env bats
# tests/bats/tenants-01-static-tenant-cr.bats
# Phase 9 / Wave 0 (D-09-08 Nyquist gate)
# TEN-01 — Tenant CR yaml shape contract for alpha + bravo on spoke-capsule.
# Plans 09-01..09-03 land the yaml that turns these GREEN.
#
# Verifies (per RESEARCH §Gap 4 corrections to CONTEXT.md):
#   - apiVersion: capsule.clastix.io/v1beta2 + kind: Tenant + name alpha|bravo
#   - spec.forceTenantPrefix: false (TOP-LEVEL — NOT spec.namespaceOptions.forceTenantPrefix)
#   - spec.owners[] contains kind: ServiceAccount with combined-name format
#     name: system:serviceaccount:tenant-<name>:gitops-reconciler
#     (spec.owners[].namespace does NOT exist in v1beta2 schema — RESEARCH §Gap 4 #2)
#   - spec.owners[] contains kind: User + name: alpha|bravo (TEN-02 contract)
#   - spec.resourceQuotas.items[0].hard non-empty (TEN-03 auto-materialization shape)
#   - spec.limitRanges.items[0].limits non-empty (TEN-03 auto-materialization shape)

load 'test_helper'

setup() {
  ALPHA_TENANT="${REPO_ROOT}/pocs/capsule/spoke/tenant-crs/alpha.yaml"
  BRAVO_TENANT="${REPO_ROOT}/pocs/capsule/spoke/tenant-crs/bravo.yaml"
}

# ---- alpha ----

@test "TEN-01 / D-11-07 (alpha): apiVersion v1beta2 + kind Tenant + name alpha + forceTenantPrefix TOP-LEVEL=false" {
  [ -f "$ALPHA_TENANT" ]
  run yq eval '.apiVersion == "capsule.clastix.io/v1beta2" and .kind == "Tenant" and .metadata.name == "alpha" and .spec.forceTenantPrefix == false' "$ALPHA_TENANT"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "TEN-01 / RESEARCH Gap 4 (alpha): owners[] contains kind=ServiceAccount + name=system:serviceaccount:tenant-alpha:gitops-reconciler (combined-name format)" {
  [ -f "$ALPHA_TENANT" ]
  run yq eval '.spec.owners | map(select(.kind == "ServiceAccount" and .name == "system:serviceaccount:tenant-alpha:gitops-reconciler")) | length == 1' "$ALPHA_TENANT"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "TEN-01 / D-11-07 (alpha): owners[] contains bootstrap flux-reconciler SA" {
  [ -f "$ALPHA_TENANT" ]
  run yq eval '.spec.owners | map(select(.kind == "ServiceAccount" and .name == "system:serviceaccount:flux-system:flux-reconciler")) | length == 1' "$ALPHA_TENANT"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "TEN-01 / D-09-02 (alpha): owners[] contains kind=User + name=alpha (TEN-02 contract)" {
  [ -f "$ALPHA_TENANT" ]
  run yq eval '.spec.owners | map(select(.kind == "User" and .name == "alpha")) | length == 1' "$ALPHA_TENANT"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "TEN-03 / D-09-02 (alpha): resourceQuotas.items[0].hard non-empty AND limitRanges.items[0].limits non-empty (auto-materialization shape)" {
  [ -f "$ALPHA_TENANT" ]
  run yq eval '(.spec.resourceQuotas.items[0].hard | length) > 0 and (.spec.limitRanges.items[0].limits | length) > 0' "$ALPHA_TENANT"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

# ---- bravo ----

@test "TEN-01 / D-11-07 (bravo): apiVersion v1beta2 + kind Tenant + name bravo + forceTenantPrefix TOP-LEVEL=false" {
  [ -f "$BRAVO_TENANT" ]
  run yq eval '.apiVersion == "capsule.clastix.io/v1beta2" and .kind == "Tenant" and .metadata.name == "bravo" and .spec.forceTenantPrefix == false' "$BRAVO_TENANT"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "TEN-01 / RESEARCH Gap 4 (bravo): owners[] contains kind=ServiceAccount + name=system:serviceaccount:tenant-bravo:gitops-reconciler (combined-name format)" {
  [ -f "$BRAVO_TENANT" ]
  run yq eval '.spec.owners | map(select(.kind == "ServiceAccount" and .name == "system:serviceaccount:tenant-bravo:gitops-reconciler")) | length == 1' "$BRAVO_TENANT"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "TEN-01 / D-11-07 (bravo): owners[] contains bootstrap flux-reconciler SA" {
  [ -f "$BRAVO_TENANT" ]
  run yq eval '.spec.owners | map(select(.kind == "ServiceAccount" and .name == "system:serviceaccount:flux-system:flux-reconciler")) | length == 1' "$BRAVO_TENANT"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "TEN-01 / D-09-02 (bravo): owners[] contains kind=User + name=bravo (TEN-02 contract)" {
  [ -f "$BRAVO_TENANT" ]
  run yq eval '.spec.owners | map(select(.kind == "User" and .name == "bravo")) | length == 1' "$BRAVO_TENANT"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "TEN-03 / D-09-02 (bravo): resourceQuotas.items[0].hard non-empty AND limitRanges.items[0].limits non-empty (auto-materialization shape)" {
  [ -f "$BRAVO_TENANT" ]
  run yq eval '(.spec.resourceQuotas.items[0].hard | length) > 0 and (.spec.limitRanges.items[0].limits | length) > 0' "$BRAVO_TENANT"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}
