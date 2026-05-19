#!/usr/bin/env bats
# tests/bats/rbac-02-static-platform-owner-sa.bats
# Phase 13 / Wave 0 (D-13-15 Nyquist gate)
# D-13-06 — platform-owner SA file shape + dual-subject ClusterRoleBinding.
# RED until Plan 13-02 lands platform-owner-sa.yaml + edits platform-owner.yaml CRB subjects[].

load 'test_helper'

setup() {
  SA_YAML="${REPO_ROOT}/pocs/capsule/spoke/rbac/platform-owner-sa.yaml"
  CRB_YAML="${REPO_ROOT}/pocs/capsule/spoke/rbac/platform-owner.yaml"
  KUST_YAML="${REPO_ROOT}/pocs/capsule/spoke/rbac/kustomization.yaml"
}

@test "RBAC-02 / D-13-06: platform-owner-sa.yaml exists at pocs/capsule/spoke/rbac/" {
  [ -f "$SA_YAML" ]
}

@test "RBAC-02 / D-13-06: SA file kind == ServiceAccount + name + namespace literals" {
  [ -f "$SA_YAML" ]
  for literal in 'kind: ServiceAccount' 'name: platform-owner' 'namespace: capsule-system'; do
    run grep -F -- "$literal" "$SA_YAML"
    [ "$status" -eq 0 ]
  done
}

@test "RBAC-02 / D-13-06: existing platform-owner.yaml ClusterRoleBinding file still exists" {
  [ -f "$CRB_YAML" ]
}

@test "RBAC-02 / D-13-06 (preserved): CRB subjects[] contains Group capsule-platform-owners (RBAC-03 regression gate)" {
  [ -f "$CRB_YAML" ]
  run yq eval-all 'select(.kind == "ClusterRoleBinding") | [.subjects[] | select(.kind == "Group" and .name == "capsule-platform-owners")] | length' "$CRB_YAML"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "RBAC-02 / D-13-06 (NEW): CRB subjects[] contains ServiceAccount platform-owner@capsule-system" {
  [ -f "$CRB_YAML" ]
  run yq eval-all 'select(.kind == "ClusterRoleBinding") | [.subjects[] | select(.kind == "ServiceAccount" and .name == "platform-owner" and .namespace == "capsule-system")] | length' "$CRB_YAML"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "RBAC-02 / D-13-06: rbac/kustomization.yaml resources[] includes platform-owner-sa.yaml" {
  [ -f "$KUST_YAML" ]
  run yq eval '.resources[]' "$KUST_YAML"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx 'platform-owner-sa.yaml'
}
