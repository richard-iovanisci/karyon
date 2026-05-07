#!/usr/bin/env bats
# tests/bats/push-gate-06-static-helmrelease-sa.bats
# Phase 11 G-06 gap-close (2026-05-06; codex review §2 HIGH #1, HIGH #2, MEDIUM #3) --
# static assertions for the G-06 fix surface.
#
# Without spec.serviceAccountName on the HRs, helm-controller's cross-cluster
# impersonation defaults to system:serviceaccount:capsule-system:default on
# spoke-capsule which has zero RBAC; flux reconcile times out with
# `context deadline exceeded`. Per RESEARCH.md line 971 (Flux Service Account
# Impersonation -- oneuptime article verified).
#
# The corresponding NS + SA + CRB live on spoke-capsule under
# pocs/capsule/spoke/rbac/ (asserted in @tests 3-5).
#
# Live reconcile observation (Plan 11-07 Task 5 human-verify checkpoint):
#   flux reconcile helmrelease capsule -n capsule-system  # should NOT timeout
#   flux reconcile helmrelease capsule-proxy -n capsule-system  # should NOT timeout

load 'test_helper'

setup() {
  OPERATOR_HR="${REPO_ROOT}/pocs/capsule/operator/helmrelease.yaml"
  PROXY_HR="${REPO_ROOT}/pocs/capsule/proxy/helmrelease.yaml"
  SPOKE_NS="${REPO_ROOT}/pocs/capsule/spoke/rbac/namespace.yaml"
  SPOKE_RBAC="${REPO_ROOT}/pocs/capsule/spoke/rbac/helm-controller-sa.yaml"
  SPOKE_RBAC_K="${REPO_ROOT}/pocs/capsule/spoke/rbac/kustomization.yaml"
  SPOKE_K="${REPO_ROOT}/pocs/capsule/spoke/kustomization.yaml"
  SPOKE_OUTER_K="${REPO_ROOT}/clusters/hub-flux/pocs/capsule-spoke.yaml"
}

@test "G-06: operator HelmRelease declares spec.serviceAccountName: helm-controller" {
  [ -f "$OPERATOR_HR" ]
  run yq eval '.spec.serviceAccountName' "$OPERATOR_HR"
  [ "$status" -eq 0 ]
  [ "$output" = "helm-controller" ]
}

@test "G-06: proxy HelmRelease declares spec.serviceAccountName: helm-controller" {
  [ -f "$PROXY_HR" ]
  run yq eval '.spec.serviceAccountName' "$PROXY_HR"
  [ "$status" -eq 0 ]
  [ "$output" = "helm-controller" ]
}

@test "G-06: spoke rbac/namespace.yaml provisions capsule-system Namespace (codex HIGH #1 fix)" {
  [ -f "$SPOKE_NS" ]
  run yq eval '.kind' "$SPOKE_NS"
  [ "$status" -eq 0 ]
  [ "$output" = "Namespace" ]
  run yq eval '.metadata.name' "$SPOKE_NS"
  [ "$status" -eq 0 ]
  [ "$output" = "capsule-system" ]
}

@test "G-06: spoke rbac/helm-controller-sa.yaml provisions ServiceAccount + ClusterRoleBinding (cluster-admin)" {
  [ -f "$SPOKE_RBAC" ]
  # Document is multi-doc YAML; assert SA AND CRB both present with correct fields.
  run yq eval-all 'select(.kind == "ServiceAccount") | .metadata.name + ":" + .metadata.namespace' "$SPOKE_RBAC"
  [ "$status" -eq 0 ]
  [ "$output" = "helm-controller:capsule-system" ]

  run yq eval-all 'select(.kind == "ClusterRoleBinding") | .roleRef.name' "$SPOKE_RBAC"
  [ "$status" -eq 0 ]
  [ "$output" = "cluster-admin" ]

  run yq eval-all 'select(.kind == "ClusterRoleBinding") | .subjects[0].name + ":" + .subjects[0].namespace' "$SPOKE_RBAC"
  [ "$status" -eq 0 ]
  [ "$output" = "helm-controller:capsule-system" ]
}

@test "G-06: pocs/capsule/spoke/rbac/kustomization.yaml lists namespace.yaml FIRST (codex HIGH #1)" {
  [ -f "$SPOKE_RBAC_K" ]
  run yq eval '.resources[0]' "$SPOKE_RBAC_K"
  [ "$status" -eq 0 ]
  [ "$output" = "namespace.yaml" ]
  run yq eval '.resources[1]' "$SPOKE_RBAC_K"
  [ "$status" -eq 0 ]
  [ "$output" = "helm-controller-sa.yaml" ]
}

@test "G-06: pocs/capsule/spoke/kustomization.yaml lists rbac/ FIRST (intra-K defense in depth)" {
  [ -f "$SPOKE_K" ]
  # First non-comment resources entry must be `- rbac/`.
  run yq eval '.resources[0]' "$SPOKE_K"
  [ "$status" -eq 0 ]
  [ "$output" = "rbac/" ]
}

@test "G-06: capsule-spoke.yaml outer K uses serviceAccountName: flux-reconciler (codex HIGH #2 fix)" {
  [ -f "$SPOKE_OUTER_K" ]
  run yq eval '.spec.serviceAccountName' "$SPOKE_OUTER_K"
  [ "$status" -eq 0 ]
  [ "$output" = "flux-reconciler" ]
}

@test "G-06: capsule-spoke.yaml outer K dependsOn includes poc-capsule-spoke-rbac (codex MEDIUM #3 fix)" {
  [ -f "$SPOKE_OUTER_K" ]
  # dependsOn must contain BOTH poc-capsule-spoke-rbac AND poc-capsule.
  run yq eval '.spec.dependsOn[].name' "$SPOKE_OUTER_K"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx 'poc-capsule-spoke-rbac'
  echo "$output" | grep -qx 'poc-capsule'
}
