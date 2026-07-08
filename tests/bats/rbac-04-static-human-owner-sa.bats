#!/usr/bin/env bats
# tests/bats/rbac-04-static-human-owner-sa.bats
# Per-tenant human-tenant-owner SA file shape
# (tenants/{alpha,bravo}/human-owner-sa.yaml).

load 'test_helper'

setup() {
  ALPHA_SA="${REPO_ROOT}/pocs/capsule/spoke/tenants/alpha/human-owner-sa.yaml"
  BRAVO_SA="${REPO_ROOT}/pocs/capsule/spoke/tenants/bravo/human-owner-sa.yaml"
  ALPHA_KUST="${REPO_ROOT}/pocs/capsule/spoke/tenants/alpha/kustomization.yaml"
  BRAVO_KUST="${REPO_ROOT}/pocs/capsule/spoke/tenants/bravo/kustomization.yaml"
}

@test "RBAC-04 / D-13-05: alpha/human-owner-sa.yaml exists" {
  [ -f "$ALPHA_SA" ]
}

@test "RBAC-04 / D-13-05: bravo/human-owner-sa.yaml exists" {
  [ -f "$BRAVO_SA" ]
}

@test "RBAC-04 / D-13-05 (alpha): SA file kind == ServiceAccount + name + namespace literals" {
  [ -f "$ALPHA_SA" ]
  for literal in 'kind: ServiceAccount' 'name: human-tenant-owner' 'namespace: tenant-alpha'; do
    run grep -F -- "$literal" "$ALPHA_SA"
    [ "$status" -eq 0 ]
  done
}

@test "RBAC-04 / D-13-05 (bravo): SA file kind == ServiceAccount + name + namespace literals" {
  [ -f "$BRAVO_SA" ]
  for literal in 'kind: ServiceAccount' 'name: human-tenant-owner' 'namespace: tenant-bravo'; do
    run grep -F -- "$literal" "$BRAVO_SA"
    [ "$status" -eq 0 ]
  done
}

@test "RBAC-04 / D-13-05 (alpha): kustomization.yaml resources[] includes human-owner-sa.yaml" {
  [ -f "$ALPHA_KUST" ]
  run yq eval '.resources[]' "$ALPHA_KUST"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx 'human-owner-sa.yaml'
}

@test "RBAC-04 / D-13-05 (bravo): kustomization.yaml resources[] includes human-owner-sa.yaml" {
  [ -f "$BRAVO_KUST" ]
  run yq eval '.resources[]' "$BRAVO_KUST"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx 'human-owner-sa.yaml'
}
