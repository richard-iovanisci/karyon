#!/usr/bin/env bats
# tests/bats/tenants-12-live-health-check.bats
# Phase 9 / Wave 0 (D-09-08 Nyquist gate)
# v0.18 regression gate — `task health-check` exits 0 post-lockdown.
# Plans 09-03 (lockdown) + 09-04 (verifier) land the yaml that turns these GREEN.
#
# Verifies (per CONTEXT D-09-09 + RESEARCH §Gap 11 belt-and-suspenders):
#   - `task health-check` exits 0 (full v0.18 health-check still passes after lockdown)
#   - spoke-apps Kustomization Ready=True (cross-cluster lockdown impact regression)
#   - spoke-ml Kustomization Ready=True (cross-cluster lockdown impact regression)
#
# Cluster-info gate: full v0.18 baseline (hub-flux + spoke-apps + spoke-ml).
# Skips when ANY of the 3 v0.18 clusters are unreachable. spoke-capsule is NOT
# part of the v0.18 health-check (per Phase 7 P31 isolation contract — POC
# stays out of `task rebuild` until graduation ADR-008).

load 'test_helper'

setup() {
  if ! kubectl --context=k3d-hub-flux cluster-info >/dev/null 2>&1; then
    skip "k3d-hub-flux cluster not reachable; skipping live bats"
  fi
  if ! kubectl --context=k3d-spoke-apps cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-apps cluster not reachable; skipping live bats"
  fi
  if ! kubectl --context=k3d-spoke-ml cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-ml cluster not reachable; skipping live bats"
  fi
}

@test "v0.18 regression: task health-check exits 0 (D-09-09 + RESEARCH Gap 11 belt-and-suspenders)" {
  run bash -c "cd '${REPO_ROOT}' && task health-check"
  [ "$status" -eq 0 ]
}

@test "RESEARCH Gap 11: spoke-apps Kustomization Ready=True (cross-cluster lockdown impact regression)" {
  local ready
  ready=$(kubectl --context=k3d-hub-flux -n flux-system get kustomization spoke-apps -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
  [[ "$ready" == "True" ]]
}

@test "RESEARCH Gap 11: spoke-ml Kustomization Ready=True (cross-cluster lockdown impact regression)" {
  local ready
  ready=$(kubectl --context=k3d-hub-flux -n flux-system get kustomization spoke-ml -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
  [[ "$ready" == "True" ]]
}
