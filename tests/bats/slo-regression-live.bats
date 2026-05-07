#!/usr/bin/env bats
# tests/bats/slo-regression-live.bats
# Phase 11 / VAL-04 -- task rebuild SLO regression test (3 @tests):
#   a -- task rebuild < 230s (health-check is invoked internally by rebuild per
#        scripts/rebuild.sh L78-79; rebuild's own status==0 covers health-check)
#   b -- k3d-spoke-capsule-server-0 container ID unchanged
#   d -- Phase 7 P31 lint inheritance (verbatim re-run of poc-isolation-01-static.bats per D-11-16)
# Live-skip gating: setup_file SKIPS if spoke-capsule not running (BEFORE_CID="MISSING" trap).
# Pitfall 11-P5 mitigation:
#   (a) optional CI skip via KARYON_RUN_SLO_IN_CI=1 override (CI environment too variable);
#   (b) setup_file() exports KARYON_REBUILD_APPROVED=yes so @test 1 can invoke
#       `task rebuild` non-interactively (closes Plan 11-04 VAL-04 @test 1 RED;
#       Plan 11-07 G-06 closure; 11-VERIFICATION.md Carryover item 5).
# REVISED 2026-05-05 per reviewer HIGH #1 / Pitfall 11-P6: KARYON_PHASE11_STRICT_LIVE strict-mode.
#
# REVISION NOTE (RESEARCH.md Open Questions Q4 RESOLVED): @test c (task health-check exit 0)
# was REMOVED in revision pass -- task rebuild already runs health-check internally, so a
# separate @test c was a redundant ~30s wall-clock penalty measuring the same effect.

load 'test_helper'

setup_file() {
  if [[ -n "${CI:-}" ]] && [[ -z "${KARYON_RUN_SLO_IN_CI:-}" ]]; then
    if [[ "${KARYON_PHASE11_STRICT_LIVE:-}" == "1" ]]; then
      echo "STRICT_LIVE: VAL-04 SLO regression skipped in CI; set KARYON_RUN_SLO_IN_CI=1" >&2
      return 1
    else
      skip "VAL-04 SLO regression: CI environment is too variable for accurate measurement; set KARYON_RUN_SLO_IN_CI=1 to override"
    fi
  fi
  export BEFORE_CID=$(docker inspect -f '{{.Id}}' k3d-spoke-capsule-server-0 2>/dev/null || echo "MISSING")
  if [[ "$BEFORE_CID" == "MISSING" ]]; then
    if [[ "${KARYON_PHASE11_STRICT_LIVE:-}" == "1" ]]; then
      echo "STRICT_LIVE: spoke-capsule not running -- VAL-04 requires live spoke-capsule" >&2
      return 1
    else
      skip "spoke-capsule not running -- VAL-04 requires live spoke-capsule for CID stability assertion"
    fi
  fi
  # G-06 / Pitfall 11-P5 closure (Plan 11-07; 2026-05-06):
  # Bypass scripts/rebuild.sh L30-41 confirmation gate so @test 1 can actually
  # invoke task rebuild non-interactively. Without this export, rebuild aborts
  # at the prompt with status 201 and /tmp/karyon-rebuild.log is 0 bytes (the
  # exact RED state observed in 11-VERIFICATION.md VAL-04 @test 1).
  # scripts/rebuild.sh:30-41 -- if KARYON_REBUILD_APPROVED=yes, the prompt is
  # skipped; otherwise the script reads stdin for confirmation.
  export KARYON_REBUILD_APPROVED=yes
}

@test "VAL-04 a -- task rebuild completes < 230s (covers health-check via internal invocation)" {
  cd "$REPO_ROOT"
  local start_s=$(date +%s)
  run task rebuild
  local end_s=$(date +%s)
  local elapsed=$((end_s - start_s))
  [[ "$status" -eq 0 ]] || { echo "task rebuild failed (status=$status; rebuild includes health-check internally per scripts/rebuild.sh L78-79)"; return 1; }
  [[ "$elapsed" -lt 230 ]] || { echo "task rebuild took ${elapsed}s (>= 230s SLO ceiling)"; return 1; }
  echo "rebuild elapsed: ${elapsed}s (budget: 230s)"
}

@test "VAL-04 b -- k3d-spoke-capsule-server-0 container ID unchanged across rebuild" {
  local AFTER_CID=$(docker inspect -f '{{.Id}}' k3d-spoke-capsule-server-0)
  [[ "$BEFORE_CID" == "$AFTER_CID" ]] || { echo "spoke-capsule CID changed: $BEFORE_CID -> $AFTER_CID"; return 1; }
}

@test "VAL-04 d -- P31 static lint via Phase 7 inheritance" {
  cd "$REPO_ROOT"
  run bats tests/bats/poc-isolation-01-static.bats
  [[ "$status" -eq 0 ]]
}
