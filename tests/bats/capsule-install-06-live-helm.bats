#!/usr/bin/env bats
# tests/bats/capsule-install-06-live-helm.bats
# Phase 8 / Wave 0 (D-08-09 Nyquist gate)
# CAP-01 + CAP-02 — live HelmRelease Ready=True observation on hub-flux + capsule-controller-manager pod Running on spoke-capsule.
# Cluster-info gate per RESEARCH §"Pattern 4" — auto-skips when k3d clusters unreachable
# (NOT KARYON_LIVE_TESTS env var, per CONTEXT D-08-09).

load 'test_helper'

setup() {
  if ! kubectl --context=k3d-hub-flux cluster-info >/dev/null 2>&1; then
    skip "k3d-hub-flux cluster not reachable; skipping live bats"
  fi
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
}

@test "CAP-01 live: HelmRelease capsule reports Ready=True (3 attempts × 30s sleep)" {
  local i
  for i in 1 2 3; do
    run flux get helmrelease capsule -n capsule-system --context k3d-hub-flux
    if [[ "$status" -eq 0 ]] && echo "$output" | grep -qE 'capsule[[:space:]]+.*True'; then
      return 0
    fi
    [[ $i -lt 3 ]] && sleep 30
  done
  echo "$output"
  return 1
}

@test "CAP-02 live: HelmRelease capsule-proxy reports Ready=True (3 attempts × 30s sleep)" {
  local i
  for i in 1 2 3; do
    run flux get helmrelease capsule-proxy -n capsule-system --context k3d-hub-flux
    if [[ "$status" -eq 0 ]] && echo "$output" | grep -qE 'capsule-proxy[[:space:]]+.*True'; then
      return 0
    fi
    [[ $i -lt 3 ]] && sleep 30
  done
  echo "$output"
  return 1
}

@test "CAP-01 live: capsule-controller-manager pod is Running on spoke-capsule" {
  run kubectl --context=k3d-spoke-capsule -n capsule-system get pod -l app.kubernetes.io/name=capsule -o jsonpath='{.items[*].status.phase}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Running"* ]]
}
