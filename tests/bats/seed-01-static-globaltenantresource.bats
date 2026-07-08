#!/usr/bin/env bats
# tests/bats/seed-01-static-globaltenantresource.bats
# GlobalTenantResource + Deployment + Service inline shape:
#   - apiVersion: capsule.clastix.io/v1beta2, kind: GlobalTenantResource
#   - Deployment + Service in rawItems[] with a fully-qualified container image
#     (the registry-allowlist webhook matches fully-qualified references)
#   - tenantSelector.matchLabels: {} (match-all)
#   - karyon.io/managed-by: capsule-global-tenant-resource provenance label
# Boundary (AMENDED per the ADR 0008 addendum 2026-07-06 — see
# docs/adr/0008-capsule-multi-tenancy-graduation.md):
#   NO bare Pod (immutable spec → permanent GTR resync error loop) and NO extra
#   ConfigMap in rawItems[]. The original "Pod + Service ONLY / no Deployment"
#   boundary is inverted: bare Pods are now the forbidden shape.

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

@test "SEED-01 / ADR-008 addendum 2026-07-06 (Deployment shape): rawItems[] contains kind: Deployment" {
  [ -f "$F" ]
  run yq eval-all '[.spec.resources[].rawItems[].kind // .spec.resources[].rawItems[]?.kind] | flatten | any_c(. == "Deployment")' "$F"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "SEED-01 / D-13-12 (Service shape): rawItems[] contains kind: Service" {
  [ -f "$F" ]
  run yq eval-all '[.spec.resources[].rawItems[].kind // .spec.resources[].rawItems[]?.kind] | flatten | any_c(. == "Service")' "$F"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

# INVERTED (ADR 0008 addendum 2026-07-06): bare Pods in GTR rawItems[] are the
# forbidden shape — Pod spec is immutable, so every GTR resync UPDATE fails and
# capsule-controller-manager sits in a permanent exponential-backoff error loop
# that masks real replication failures. Same class of failure applies to Jobs.
@test "SEED-03 / ADR-008 addendum (boundary): NO bare kind: Pod in rawItems[]" {
  [ -f "$F" ]
  run yq eval-all '[.spec.resources[].rawItems[].kind // .spec.resources[].rawItems[]?.kind] | flatten | any_c(. == "Pod")' "$F"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "SEED-03 / ADR-008 addendum (boundary): NO kind: Job in rawItems[] (spec also immutable)" {
  [ -f "$F" ]
  run yq eval-all '[.spec.resources[].rawItems[].kind // .spec.resources[].rawItems[]?.kind] | flatten | any_c(. == "Job")' "$F"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
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
