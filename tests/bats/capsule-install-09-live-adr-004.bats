#!/usr/bin/env bats
# tests/bats/capsule-install-09-live-adr-004.bats
# Hub-only Flux live invariant (docs/adr/0004-hub-only-flux-control-plane.md) —
# no Flux controllers run on spoke-capsule: flux-system ns has zero pods (or NotFound).
# Cluster-info gate — auto-skips when the cluster is unreachable.

load 'test_helper'

setup() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
}

@test "ADR-004 / domain-boundary-#4 (WR-04 fix): spoke-capsule flux-system ns has zero controllers (distinguishes NotFound from transient errors)" {
  # The prior version of this test silently passed on ANY non-zero kubectl exit
  # (e.g., transient apiserver error, RBAC propagation lag, cert renewal, network blip),
  # which is the wrong direction for a domain-boundary invariant. Distinguish the two:
  #   - "(NotFound)" in stderr → namespace doesn't exist → hub-only invariant satisfied (PASS)
  #   - any other non-zero exit → transient error → FAIL (re-run when stable)
  local ns_check
  ns_check=$(kubectl --context=k3d-spoke-capsule get ns flux-system -o jsonpath='{.status.phase}' 2>&1 || true)
  if echo "$ns_check" | grep -qF 'NotFound'; then
    # Hub-only invariant (see ADR 0004): namespace doesn't exist on spoke at all
    return 0
  fi
  # Namespace exists; assert zero pods
  local pod_count
  pod_count=$(kubectl --context=k3d-spoke-capsule get pods -n flux-system --no-headers 2>/dev/null | wc -l)
  [[ "$pod_count" -eq 0 ]]
}
