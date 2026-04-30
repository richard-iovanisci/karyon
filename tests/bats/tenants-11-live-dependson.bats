#!/usr/bin/env bats
# tests/bats/tenants-11-live-dependson.bats
# Phase 9 / Wave 0 (D-09-08 Nyquist gate)
# TEN-06 live — poc-capsule-spoke dependsOn poc-capsule + Ready=True post-lockdown.
# Plans 09-01..09-03 land the yaml that turns these GREEN.
#
# Verifies (per CONTEXT D-09-06 + RESEARCH §Gap 9):
#   - poc-capsule-spoke Kustomization has dependsOn[0].name == poc-capsule
#   - poc-capsule-spoke Kustomization has spec.wait == true (TOP-LEVEL)
#   - poc-capsule-spoke Kustomization Ready=True (3×30s retry)
#
# Cluster-info gate: hub-only (Kustomization CRs live on hub).

load 'test_helper'

setup() {
  if ! kubectl --context=k3d-hub-flux cluster-info >/dev/null 2>&1; then
    skip "k3d-hub-flux cluster not reachable; skipping live bats"
  fi
}

@test "TEN-06 / D-09-06: poc-capsule-spoke Kustomization has dependsOn[0].name == poc-capsule" {
  run kubectl --context=k3d-hub-flux -n flux-system get kustomization poc-capsule-spoke -o jsonpath='{.spec.dependsOn[0].name}'
  [ "$status" -eq 0 ]
  [ "$output" = "poc-capsule" ]
}

@test "TEN-06 / RESEARCH Gap 9: poc-capsule-spoke Kustomization has spec.wait == true (TOP-LEVEL)" {
  run kubectl --context=k3d-hub-flux -n flux-system get kustomization poc-capsule-spoke -o jsonpath='{.spec.wait}'
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "TEN-06 / D-09-06: poc-capsule-spoke Kustomization Ready=True (3×30s retry)" {
  local i ready
  for i in 1 2 3; do
    ready=$(kubectl --context=k3d-hub-flux -n flux-system get kustomization poc-capsule-spoke -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
    [[ "$ready" == "True" ]] && return 0
    [[ $i -lt 3 ]] && sleep 30
  done
  echo "Last observed poc-capsule-spoke Ready: '$ready'"
  return 1
}
