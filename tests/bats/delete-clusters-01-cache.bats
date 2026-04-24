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

@test "CLU-06: delete-clusters.sh carries the D-14 INTENTIONALLY NOT calling blocking comment" {
  run grep -c 'INTENTIONALLY NOT calling' "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}

# WARNING: This live test runs scripts/delete-clusters.sh, destroying any active
# clusters. Requires BOTH KARYON_LIVE_TESTS=1 AND KARYON_LIVE_TESTS_DESTRUCTIVE=1.
# Re-run scripts/create-clusters.sh afterward if you need clusters present.
@test "CLU-06 (live/destructive): karyon/k3s-cuda image survives delete-clusters.sh" {
  require_live_destructive
  bash "${REPO_ROOT}/scripts/delete-clusters.sh" >/dev/null 2>&1 || true
  run bash -c "docker images karyon/k3s-cuda --format '{{.Repository}}' | grep -c '^karyon/k3s-cuda$'"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}
