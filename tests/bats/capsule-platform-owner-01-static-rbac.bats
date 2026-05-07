#!/usr/bin/env bats
# tests/bats/capsule-platform-owner-01-static-rbac.bats
# Static contract for the Capsule platform-owner RBAC spike.

load 'test_helper'

setup() {
  RBAC="${REPO_ROOT}/pocs/capsule/spoke/rbac/platform-owner.yaml"
  RBAC_K="${REPO_ROOT}/pocs/capsule/spoke/rbac/kustomization.yaml"
}

@test "platform-owner: manifest is included in spoke rbac kustomization" {
  [ -f "$RBAC" ]
  run yq eval '.resources[]' "$RBAC_K"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx 'platform-owner.yaml'
}

@test "platform-owner: ClusterRole and ClusterRoleBinding use capsule-platform-owner name" {
  run yq eval-all 'select(.kind == "ClusterRole") | .metadata.name' "$RBAC"
  [ "$status" -eq 0 ]
  [ "$output" = "capsule-platform-owner" ]

  run yq eval-all 'select(.kind == "ClusterRoleBinding") | .metadata.name' "$RBAC"
  [ "$status" -eq 0 ]
  [ "$output" = "capsule-platform-owner" ]

  run yq eval-all 'select(.kind == "ClusterRoleBinding") | .roleRef.name' "$RBAC"
  [ "$status" -eq 0 ]
  [ "$output" = "capsule-platform-owner" ]
}

@test "platform-owner: binding targets capsule-platform-owners group" {
  run yq eval-all 'select(.kind == "ClusterRoleBinding") | .subjects[0].kind + ":" + .subjects[0].name' "$RBAC"
  [ "$status" -eq 0 ]
  [ "$output" = "Group:capsule-platform-owners" ]
}

@test "platform-owner: role can read all capsule.clastix.io resources" {
  run yq eval-all 'select(.kind == "ClusterRole") | .rules[] | select((.apiGroups[] == "capsule.clastix.io") and (.resources[] == "*")) | .verbs[]' "$RBAC"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx 'get'
  echo "$output" | grep -qx 'list'
  echo "$output" | grep -qx 'watch'
}

@test "platform-owner: role can create/update/patch/delete Tenant CRs" {
  run yq eval-all 'select(.kind == "ClusterRole") | .rules[] | select((.apiGroups[] == "capsule.clastix.io") and (.resources[] == "tenants")) | .verbs[]' "$RBAC"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx 'create'
  echo "$output" | grep -qx 'update'
  echo "$output" | grep -qx 'patch'
  echo "$output" | grep -qx 'delete'
}

@test "platform-owner: role can inspect namespaces and CRDs but is not cluster-admin" {
  run yq eval-all 'select(.kind == "ClusterRole") | .rules[] | select((.apiGroups[] == "") and (.resources[] == "namespaces")) | .verbs[]' "$RBAC"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx 'get'
  echo "$output" | grep -qx 'list'
  echo "$output" | grep -qx 'watch'

  run yq eval-all 'select(.kind == "ClusterRoleBinding") | .roleRef.name' "$RBAC"
  [ "$status" -eq 0 ]
  [ "$output" != "cluster-admin" ]
}
