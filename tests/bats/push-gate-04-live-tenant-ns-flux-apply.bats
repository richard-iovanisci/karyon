#!/usr/bin/env bats
# tests/bats/push-gate-04-live-tenant-ns-flux-apply.bats
# Live falsifier: after push,
# Flux reconciles the labeled namespace.yaml; assert the label survives the cluster-admin
# Flux apply (assumption: system:masters / cluster-admin bypasses the Capsule prefix webhook).
# KARYON_PHASE11_STRICT_LIVE=1 converts skips to FAIL.

load 'test_helper'

_strict_skip() {
  local msg="$1"
  if [[ "${KARYON_PHASE11_STRICT_LIVE:-}" == "1" ]]; then
    echo "STRICT_LIVE: ${msg}" >&2
    return 1
  else
    skip "${msg}"
  fi
}

setup() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    _strict_skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
}

@test "D-11-03 live (post-first-push): tenant-alpha namespace has capsule.clastix.io/tenant=alpha label (3x30s retry for Flux reconcile)" {
  local i label
  for i in 1 2 3; do
    label=$(kubectl --context=k3d-spoke-capsule get namespace tenant-alpha \
      -o jsonpath='{.metadata.labels.capsule\.clastix\.io/tenant}' 2>/dev/null || true)
    [[ "$label" == "alpha" ]] && return 0
    [[ $i -lt 3 ]] && sleep 30
  done
  echo "Last observed label: '$label'"
  return 1
}

@test "D-11-03 live (post-first-push): tenant-bravo namespace has capsule.clastix.io/tenant=bravo label (3x30s retry for Flux reconcile)" {
  local i label
  for i in 1 2 3; do
    label=$(kubectl --context=k3d-spoke-capsule get namespace tenant-bravo \
      -o jsonpath='{.metadata.labels.capsule\.clastix\.io/tenant}' 2>/dev/null || true)
    [[ "$label" == "bravo" ]] && return 0
    [[ $i -lt 3 ]] && sleep 30
  done
  echo "Last observed label: '$label'"
  return 1
}
