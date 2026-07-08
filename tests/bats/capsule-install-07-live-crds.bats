#!/usr/bin/env bats
# tests/bats/capsule-install-07-live-crds.bats
# Live: ≥7 capsule.clastix.io CRDs registered on spoke-capsule.
# Cluster-info gate — auto-skips when the cluster is unreachable.

load 'test_helper'

setup() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
}

@test "CAP-03 live: ≥7 capsule.clastix.io CRDs registered" {
  local count
  count=$(kubectl --context=k3d-spoke-capsule get crds 2>/dev/null \
    | grep -c '.capsule.clastix.io' || true)
  [[ "$count" -ge 7 ]]
}

@test "CAP-03 live: each of the 7 expected CRD names is present" {
  for crd in tenants capsuleconfigurations globaltenantresources tenantresources \
             resourcepools resourcepoolclaims tenantowners; do
    run kubectl --context=k3d-spoke-capsule get crd "${crd}.capsule.clastix.io"
    [ "$status" -eq 0 ]
  done
}
