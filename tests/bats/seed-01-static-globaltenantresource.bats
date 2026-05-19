#!/usr/bin/env bats
# tests/bats/seed-01-static-globaltenantresource.bats
# Phase 13 / Wave 0 (D-13-15 Nyquist gate)
# SEED-01 — GlobalTenantResource + Pod + Service inline shape:
#   - apiVersion: capsule.clastix.io/v1beta2, kind: GlobalTenantResource
#   - tenantSelector.matchLabels: {} (match-all per RESEARCH Pattern 1)
#   - Pod + Service in rawItems[] with FQCI image (Pitfall 13-P1)
#   - karyon.io/managed-by: capsule-global-tenant-resource provenance label
# SEED-03 boundary: NO Deployment / NO ReplicaSet in rawItems[].
# RED until Plan 13-03 lands hello-world.yaml + kustomization.yaml.

load 'test_helper'

setup() {
  F="${REPO_ROOT}/pocs/capsule/spoke/global-resources/hello-world.yaml"
  KUST="${REPO_ROOT}/pocs/capsule/spoke/global-resources/kustomization.yaml"
  PARENT_KUST="${REPO_ROOT}/pocs/capsule/spoke/kustomization.yaml"
}

@test "SEED-01 / D-13-11: hello-world.yaml exists at pocs/capsule/spoke/global-resources/" {
  [ -f "$F" ]
}

@test "SEED-01 / D-13-11: global-resources/kustomization.yaml exists" {
  [ -f "$KUST" ]
}

@test "SEED-01 / D-13-11: contains apiVersion: capsule.clastix.io/v1beta2" {
  [ -f "$F" ]
  run grep -F -- 'apiVersion: capsule.clastix.io/v1beta2' "$F"
  [ "$status" -eq 0 ]
}

@test "SEED-01 / D-13-11: contains kind: GlobalTenantResource" {
  [ -f "$F" ]
  run grep -F -- 'kind: GlobalTenantResource' "$F"
  [ "$status" -eq 0 ]
}

@test "SEED-01 / RESEARCH-Pattern-1: contains match-all tenantSelector (matchLabels: {})" {
  [ -f "$F" ]
  run grep -F -- 'matchLabels: {}' "$F"
  [ "$status" -eq 0 ]
}

@test "SEED-01 / provenance: contains karyon.io/managed-by: capsule-global-tenant-resource label" {
  [ -f "$F" ]
  run grep -F -- 'karyon.io/managed-by: capsule-global-tenant-resource' "$F"
  [ "$status" -eq 0 ]
}

@test "SEED-01 / Pitfall 13-P1 (FQCI): contains image: docker.io/library/nginx:alpine" {
  [ -f "$F" ]
  run grep -F -- 'image: docker.io/library/nginx:alpine' "$F"
  [ "$status" -eq 0 ]
}

@test "SEED-01 / D-13-12 (Pod shape): rawItems[] contains kind: Pod" {
  [ -f "$F" ]
  run yq eval-all '[.spec.resources[].rawItems[].kind // .spec.resources[].rawItems[]?.kind] | flatten | any_c(. == "Pod")' "$F"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "SEED-01 / D-13-12 (Service shape): rawItems[] contains kind: Service" {
  [ -f "$F" ]
  run yq eval-all '[.spec.resources[].rawItems[].kind // .spec.resources[].rawItems[]?.kind] | flatten | any_c(. == "Service")' "$F"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "SEED-03 / D-13-02 (boundary): NO kind: Deployment in hello-world.yaml" {
  [ -f "$F" ]
  # Filter comments first so this bats's own comments are not counted.
  run bash -c "grep -v '^[[:space:]]*#' '$F' | grep -F 'kind: Deployment'"
  [ "$status" -ne 0 ]
}

@test "SEED-03 / D-13-02 (boundary): NO kind: ReplicaSet in hello-world.yaml" {
  [ -f "$F" ]
  run bash -c "grep -v '^[[:space:]]*#' '$F' | grep -F 'kind: ReplicaSet'"
  [ "$status" -ne 0 ]
}

@test "SEED-03 / D-13-02 (boundary): NO kind: ConfigMap in rawItems[]" {
  [ -f "$F" ]
  # ConfigMap is denied; if present in rawItems[], any_c == ConfigMap returns true.
  run yq eval-all '[.spec.resources[].rawItems[].kind // .spec.resources[].rawItems[]?.kind] | flatten | any_c(. == "ConfigMap")' "$F"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "SEED-01 / DELIVERY-01: parent spoke kustomization.yaml resources[] includes global-resources/" {
  [ -f "$PARENT_KUST" ]
  run yq eval '.resources[]' "$PARENT_KUST"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx 'global-resources/'
}
