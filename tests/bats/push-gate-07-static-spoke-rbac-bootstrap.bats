#!/usr/bin/env bats
# tests/bats/push-gate-07-static-spoke-rbac-bootstrap.bats
# Phase 11 G-06 gap-close (2026-05-06; codex review §2 MEDIUM #3) -- static assertions
# for the new poc-capsule-spoke-rbac top-level Flux Kustomization.
#
# Why this exists: codex review §2 MEDIUM #3 noted that "rbac/ first" inside
# pocs/capsule/spoke/kustomization.yaml only orders apply WITHIN that K. The
# HelmReleases come from the separate poc-capsule (hub-targeted) Kustomization
# and helm-controller can pick them up BEFORE poc-capsule-spoke applies rbac.
# Plan 11-07 fixes this by splitting rbac into its own outer K
# (clusters/hub-flux/pocs/capsule-spoke-rbac.yaml) with NO dependsOn on poc-capsule
# so it always reconciles first.
#
# This bats locks the load-bearing structure of capsule-spoke-rbac.yaml so a future
# edit can't accidentally regress the deterministic ordering.

load 'test_helper'

setup() {
  RBAC_K="${REPO_ROOT}/clusters/hub-flux/pocs/capsule-spoke-rbac.yaml"
  POCS_K="${REPO_ROOT}/clusters/hub-flux/pocs/kustomization.yaml"
}

@test "spoke-rbac-K: file exists" {
  [ -f "$RBAC_K" ]
}

@test "spoke-rbac-K: kind is Kustomization (Flux v1)" {
  run yq eval '.kind' "$RBAC_K"
  [ "$status" -eq 0 ]
  [ "$output" = "Kustomization" ]
  run yq eval '.apiVersion' "$RBAC_K"
  [ "$status" -eq 0 ]
  [ "$output" = "kustomize.toolkit.fluxcd.io/v1" ]
}

@test "spoke-rbac-K: metadata.name = poc-capsule-spoke-rbac" {
  run yq eval '.metadata.name' "$RBAC_K"
  [ "$status" -eq 0 ]
  [ "$output" = "poc-capsule-spoke-rbac" ]
}

@test "spoke-rbac-K: spec.path is ./pocs/capsule/spoke/rbac (narrow scope)" {
  run yq eval '.spec.path' "$RBAC_K"
  [ "$status" -eq 0 ]
  [ "$output" = "./pocs/capsule/spoke/rbac" ]
}

@test "spoke-rbac-K: spec.serviceAccountName is flux-reconciler (codex HIGH #2)" {
  run yq eval '.spec.serviceAccountName' "$RBAC_K"
  [ "$status" -eq 0 ]
  [ "$output" = "flux-reconciler" ]
}

@test "spoke-rbac-K: spec.kubeConfig.secretRef.name is spoke-capsule-kubeconfig (P18 invariant)" {
  run yq eval '.spec.kubeConfig.secretRef.name' "$RBAC_K"
  [ "$status" -eq 0 ]
  [ "$output" = "spoke-capsule-kubeconfig" ]
  run yq eval '.spec.kubeConfig.secretRef.key' "$RBAC_K"
  [ "$status" -eq 0 ]
  [ "$output" = "value.yaml" ]
}

@test "spoke-rbac-K: NO dependsOn (must be empty/null/absent) -- codex MEDIUM #3 deterministic ordering" {
  # The whole point of this K is it has no dependsOn so it's always reconciled
  # before poc-capsule (which would otherwise be a circular/competing dependency).
  run yq eval '.spec.dependsOn // [] | length' "$RBAC_K"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "spoke-rbac-K: included in clusters/hub-flux/pocs/kustomization.yaml resources" {
  [ -f "$POCS_K" ]
  run yq eval '.resources[]' "$POCS_K"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx 'capsule-spoke-rbac.yaml'
}
