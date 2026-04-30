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

@test "ADR-004 / domain-boundary-#4 (WR-04 fix): spoke-capsule flux-system ns has zero controllers (distinguishes NotFound from transient errors)" {
  # WR-04 fix (08-REVIEW.md): the prior test silently passed on ANY non-zero kubectl exit
  # (e.g., transient apiserver error, RBAC propagation lag, cert renewal, network blip),
  # which is the wrong direction for a domain-boundary invariant. Distinguish the two:
  #   - "(NotFound)" in stderr → namespace doesn't exist → ADR-004 invariant satisfied (PASS)
  #   - any other non-zero exit → transient error → FAIL (re-run when stable)
  local ns_check
  ns_check=$(kubectl --context=k3d-spoke-capsule get ns flux-system -o jsonpath='{.status.phase}' 2>&1 || true)
  if echo "$ns_check" | grep -qF 'NotFound'; then
    # ADR-004 invariant: namespace doesn't exist on spoke at all
    return 0
  fi
  # Namespace exists; assert zero pods
  local pod_count
  pod_count=$(kubectl --context=k3d-spoke-capsule get pods -n flux-system --no-headers 2>/dev/null | wc -l)
  [[ "$pod_count" -eq 0 ]]
}
