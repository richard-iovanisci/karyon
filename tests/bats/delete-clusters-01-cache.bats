#!/usr/bin/env bats
# tests/bats/delete-clusters-01-cache.bats
# Two-part check (CLU-06 / IMG-06 / D-14): static-grep that scripts/delete-clusters.sh carries the "INTENTIONALLY NOT calling" blocking comment AND L3 live-gated assertion that karyon/k3s-cuda image survives a teardown run.
# Wave 0 stub — body filled by Plan 02-06.

load 'test_helper'

setup() {
  SCRIPT="${REPO_ROOT}/scripts/delete-clusters.sh"
}

teardown() {
  :
}

@test "CLU-06: delete-clusters.sh preserves karyon/k3s-cuda image and carries the D-14 blocking comment" {
  skip "awaiting implementation in plan 02-06 (scripts/delete-clusters.sh created)"
  # run grep -c 'INTENTIONALLY NOT calling' "$SCRIPT"
  # [ "$status" -eq 0 ]
  # [ "$output" -eq 1 ]
}

@test "CLU-06 (live): karyon/k3s-cuda image survives delete-clusters.sh" {
  require_live
  skip "awaiting implementation in plans 02-04 (image built) and 02-06 (delete script)"
  # bash "${REPO_ROOT}/scripts/delete-clusters.sh" >/dev/null 2>&1 || true
  # run bash -c "docker images karyon/k3s-cuda --format '{{.Repository}}' | grep -c '^karyon/k3s-cuda$'"
  # [ "$status" -eq 0 ]
  # [ "$output" -ge 1 ]
}
