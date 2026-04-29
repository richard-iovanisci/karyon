#!/usr/bin/env bats
# tests/bats/capsule-install-10-live-flux-observable.bats
# Phase 8 / Wave 0 (D-08-09 Nyquist gate) — FOLDED CARRYOVER from Phase 7 verification item 1b.
# Outer poc-capsule Kustomization Ready=True against post-Phase-7 source revision.
# The post-push gate (origin/main..main empty) is NOT a Phase 8 fail condition — failure
# surfaces as 'deferred-to-VAL-05' (Phase 11 owns one-shot history scan + first-push gate).
# Cluster-info gate per RESEARCH §"Pattern 4".

load 'test_helper'

setup() {
  if ! kubectl --context=k3d-hub-flux cluster-info >/dev/null 2>&1; then
    skip "k3d-hub-flux cluster not reachable; skipping live bats"
  fi
}

@test "FOLDED CARRYOVER: outer poc-capsule Kustomization reports Ready=True (3 attempts × 30s sleep)" {
  local i
  for i in 1 2 3; do
    run flux get kustomization poc-capsule -n flux-system --context k3d-hub-flux
    if [[ "$status" -eq 0 ]] && echo "$output" | grep -qE 'poc-capsule[[:space:]]+.*True'; then
      return 0
    fi
    [[ $i -lt 3 ]] && sleep 30
  done
  echo "$output"
  return 1
}

@test "FOLDED CARRYOVER: post-Phase-7 push gate — git log origin/main..main is empty (precondition; failure surfaces as 'deferred-to-VAL-05' rather than Phase 8 fail)" {
  # Skip if the branch isn't tracking origin (e.g., fresh local clone)
  if ! git -C "${REPO_ROOT}" rev-parse origin/main >/dev/null 2>&1; then
    skip "origin/main not tracked locally; skipping push-gate (deferred to Phase 11 VAL-05)"
  fi
  run bash -c "cd '${REPO_ROOT}' && git log origin/main..main --oneline"
  [ "$status" -eq 0 ]
  if [ -n "$output" ]; then
    skip "Local commits not pushed to origin/main yet; deferred-to-VAL-05 (Phase 11 owns one-shot history scan + first-push gate). Phase 8 verifier surfaces this as 'carryover-deferred' not 'install-defect'."
  fi
}

@test "FOLDED CARRYOVER: hub-flux GitRepository revision is past Phase 7 close-out commit 1f2da1d3" {
  run flux get sources git flux-system --context k3d-hub-flux 2>&1
  [ "$status" -eq 0 ]
  # The revision string includes a sha; assert it is NOT 1f2da1d3 (Phase 7 close-out).
  # If output contains exactly 1f2da1d3, the post-Phase-7 push has not yet been ingested by hub-flux.
  if echo "$output" | grep -qF '1f2da1d3'; then
    skip "hub-flux GitRepository still on Phase 7 close-out revision 1f2da1d3; first-push gate not satisfied (Phase 11 VAL-05 owns)"
  fi
}
