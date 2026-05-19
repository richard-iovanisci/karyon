#!/usr/bin/env bats
# tests/bats/rbac-03-static-tenant-co-ownership.bats
# Phase 13 / Wave 0 (D-13-15 Nyquist gate)
# D-13-05 + D-13-07 — owner additions to alpha + bravo:
#   - Existing entries preserved verbatim (flux-reconciler SA, gitops-reconciler SA, User)
#   - NEW: human-tenant-owner SA with explicit clusterRoles: [tenant-workload-editor]
#   - NEW: Group capsule-platform-owners + SA platform-owner@capsule-system (no explicit clusterRoles)
#   - NEW: containerRegistries.allowed contains docker.io (Pitfall 13-P1 FQCI requirement)
# Pitfall 13-P8 guard: NO owner entry with empty clusterRoles: [].
# RED until Plan 13-01..13-02 land additive edits to alpha.yaml + bravo.yaml.

load 'test_helper'

setup() {
  ALPHA="${REPO_ROOT}/pocs/capsule/spoke/tenant-crs/alpha.yaml"
  BRAVO="${REPO_ROOT}/pocs/capsule/spoke/tenant-crs/bravo.yaml"
}

@test "RBAC-03 / D-13-05: alpha.yaml exists at pocs/capsule/spoke/tenant-crs/" {
  [ -f "$ALPHA" ]
}

@test "RBAC-03 / D-13-05: bravo.yaml exists at pocs/capsule/spoke/tenant-crs/" {
  [ -f "$BRAVO" ]
}

@test "RBAC-03 (preserved alpha): spec.owners[] contains flux-reconciler SA" {
  [ -f "$ALPHA" ]
  run yq eval '[.spec.owners[] | select(.name == "system:serviceaccount:flux-system:flux-reconciler")] | length' "$ALPHA"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "RBAC-03 (preserved alpha): spec.owners[] contains tenant-alpha:gitops-reconciler SA" {
  [ -f "$ALPHA" ]
  run yq eval '[.spec.owners[] | select(.name == "system:serviceaccount:tenant-alpha:gitops-reconciler")] | length' "$ALPHA"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "RBAC-03 (preserved alpha): spec.owners[] contains User alpha" {
  [ -f "$ALPHA" ]
  run yq eval '[.spec.owners[] | select(.kind == "User" and .name == "alpha")] | length' "$ALPHA"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "RBAC-03 / D-13-05 (NEW alpha): spec.owners[] contains human-tenant-owner SA with clusterRoles: [tenant-workload-editor]" {
  [ -f "$ALPHA" ]
  run yq eval '[.spec.owners[] | select(.name == "system:serviceaccount:tenant-alpha:human-tenant-owner")] | length' "$ALPHA"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
  run yq eval '[.spec.owners[] | select(.name == "system:serviceaccount:tenant-alpha:human-tenant-owner") | .clusterRoles] | flatten | any_c(. == "tenant-workload-editor")' "$ALPHA"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "RBAC-03 / D-13-07 (NEW alpha): spec.owners[] contains Group capsule-platform-owners" {
  [ -f "$ALPHA" ]
  run yq eval '[.spec.owners[] | select(.kind == "Group" and .name == "capsule-platform-owners")] | length' "$ALPHA"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "RBAC-03 / D-13-07 (NEW alpha): spec.owners[] contains SA platform-owner@capsule-system" {
  [ -f "$ALPHA" ]
  run yq eval '[.spec.owners[] | select(.name == "system:serviceaccount:capsule-system:platform-owner")] | length' "$ALPHA"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "RBAC-03 / Pitfall 13-P1 (alpha): containerRegistries.allowed contains docker.io" {
  [ -f "$ALPHA" ]
  run yq eval '[.spec.containerRegistries.allowed // []] | flatten | any_c(. == "docker.io")' "$ALPHA"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "RBAC-03 / Pitfall 13-P8 (alpha): NO owner entry has empty clusterRoles: []" {
  [ -f "$ALPHA" ]
  run yq eval '[.spec.owners[] | select(has("clusterRoles") and (.clusterRoles | length == 0))] | length' "$ALPHA"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

# ---- bravo (mirror alpha) ----

@test "RBAC-03 (preserved bravo): spec.owners[] contains flux-reconciler SA" {
  [ -f "$BRAVO" ]
  run yq eval '[.spec.owners[] | select(.name == "system:serviceaccount:flux-system:flux-reconciler")] | length' "$BRAVO"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "RBAC-03 (preserved bravo): spec.owners[] contains tenant-bravo:gitops-reconciler SA" {
  [ -f "$BRAVO" ]
  run yq eval '[.spec.owners[] | select(.name == "system:serviceaccount:tenant-bravo:gitops-reconciler")] | length' "$BRAVO"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "RBAC-03 (preserved bravo): spec.owners[] contains User bravo" {
  [ -f "$BRAVO" ]
  run yq eval '[.spec.owners[] | select(.kind == "User" and .name == "bravo")] | length' "$BRAVO"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "RBAC-03 / D-13-05 (NEW bravo): spec.owners[] contains human-tenant-owner SA with clusterRoles: [tenant-workload-editor]" {
  [ -f "$BRAVO" ]
  run yq eval '[.spec.owners[] | select(.name == "system:serviceaccount:tenant-bravo:human-tenant-owner")] | length' "$BRAVO"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
  run yq eval '[.spec.owners[] | select(.name == "system:serviceaccount:tenant-bravo:human-tenant-owner") | .clusterRoles] | flatten | any_c(. == "tenant-workload-editor")' "$BRAVO"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "RBAC-03 / D-13-07 (NEW bravo): spec.owners[] contains Group capsule-platform-owners" {
  [ -f "$BRAVO" ]
  run yq eval '[.spec.owners[] | select(.kind == "Group" and .name == "capsule-platform-owners")] | length' "$BRAVO"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "RBAC-03 / D-13-07 (NEW bravo): spec.owners[] contains SA platform-owner@capsule-system" {
  [ -f "$BRAVO" ]
  run yq eval '[.spec.owners[] | select(.name == "system:serviceaccount:capsule-system:platform-owner")] | length' "$BRAVO"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "RBAC-03 / Pitfall 13-P1 (bravo): containerRegistries.allowed contains docker.io" {
  [ -f "$BRAVO" ]
  run yq eval '[.spec.containerRegistries.allowed // []] | flatten | any_c(. == "docker.io")' "$BRAVO"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "RBAC-03 / Pitfall 13-P8 (bravo): NO owner entry has empty clusterRoles: []" {
  [ -f "$BRAVO" ]
  run yq eval '[.spec.owners[] | select(has("clusterRoles") and (.clusterRoles | length == 0))] | length' "$BRAVO"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}
