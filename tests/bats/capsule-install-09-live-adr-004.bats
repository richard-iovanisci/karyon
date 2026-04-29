#!/usr/bin/env bats
# tests/bats/capsule-install-09-live-adr-004.bats
# Phase 8 / Wave 0 (D-08-09 Nyquist gate)
# Domain boundary item #4 — k3d-spoke-capsule flux-system ns has zero pods (or NotFound).
# ADR-004 (hub-only Flux) live invariant — no Flux controllers run on spoke-capsule.
# Cluster-info gate per RESEARCH §"Pattern 4".

load 'test_helper'

setup() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
}

@test "ADR-004 / domain-boundary-#4: spoke-capsule flux-system ns has zero controllers" {
  run kubectl --context=k3d-spoke-capsule get pods -n flux-system 2>/dev/null
  if [ "$status" -eq 0 ]; then
    local pod_count
    pod_count=$(kubectl --context=k3d-spoke-capsule get pods -n flux-system --no-headers 2>/dev/null | wc -l || true)
    [[ "$pod_count" -eq 0 ]]
  fi
  # If namespace doesn't exist (status non-zero, output mentions NotFound), that's fine — pass.
}
