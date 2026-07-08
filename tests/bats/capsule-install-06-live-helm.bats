#!/usr/bin/env bats
# tests/bats/capsule-install-06-live-helm.bats
# Live HelmRelease Ready=True observation on hub-flux + capsule-controller-manager pod Running on spoke-capsule.
# Cluster-info gate — auto-skips when the k3d clusters are unreachable
# (a reachability probe, deliberately NOT the KARYON_LIVE_TESTS env var).

load 'test_helper'

setup() {
  if ! kubectl --context=k3d-hub-flux cluster-info >/dev/null 2>&1; then
    skip "k3d-hub-flux cluster not reachable; skipping live bats"
  fi
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
}

@test "CAP-01 live (WR-03 fix): HelmRelease capsule reports Ready=True (3 attempts x 30s sleep, jsonpath column-anchored)" {
  # The prior `flux get | grep -qE 'capsule[[:space:]]+.*True'` regex
  # admits false positives if the MESSAGE column contains the substring 'True' (e.g.
  # "Release reconciliation failed: TruncatedError"). Replace with kubectl jsonpath against
  # the explicit Ready condition status field for unambiguous parsing.
  local i ready
  for i in 1 2 3; do
    ready=$(kubectl --context=k3d-hub-flux -n capsule-system get helmrelease capsule \
      -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
    [[ "$ready" == "True" ]] && return 0
    [[ $i -lt 3 ]] && sleep 30
  done
  echo "Last observed Ready condition: '$ready'"
  return 1
}

@test "CAP-02 live (WR-03 fix): HelmRelease capsule-proxy reports Ready=True (3 attempts x 30s sleep, jsonpath column-anchored)" {
  # Same rationale as the operator HR test: kubectl jsonpath instead of fragile flux-get regex.
  local i ready
  for i in 1 2 3; do
    ready=$(kubectl --context=k3d-hub-flux -n capsule-system get helmrelease capsule-proxy \
      -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
    [[ "$ready" == "True" ]] && return 0
    [[ $i -lt 3 ]] && sleep 30
  done
  echo "Last observed Ready condition: '$ready'"
  return 1
}

@test "CAP-01 live: capsule-controller-manager pod is Running on spoke-capsule" {
  run kubectl --context=k3d-spoke-capsule -n capsule-system get pod -l app.kubernetes.io/name=capsule -o jsonpath='{.items[*].status.phase}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Running"* ]]
}
