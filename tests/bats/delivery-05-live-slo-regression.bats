#!/usr/bin/env bats
# tests/bats/delivery-05-live-slo-regression.bats
# `task rebuild` SLO regression gate <=230s (v0.18 baseline preserved).
# Env-gated destructive test: requires KARYON_REBUILD_APPROVED=1 to run.
# Reads /tmp/karyon-rebuild.log produced by a prior `task rebuild` invocation
# (the test does NOT itself invoke rebuild — that is the responsibility of the
# orchestrating script that opts into this gate).
# Mirrors phase5-02-live.bats env-gated rebuild log assertion pattern.

load 'test_helper'

setup() {
  if [[ "${KARYON_REBUILD_APPROVED:-}" != "1" ]]; then
    skip "DELIVERY-02 SLO regression — set KARYON_REBUILD_APPROVED=1 to run (destructive: requires a fresh task rebuild log)"
  fi
  LOG_FILE="/tmp/karyon-rebuild.log"
}

@test "DELIVERY-02 / Phase 13 SLO: rebuild log exists and contains elapsed seconds" {
  [ -f "$LOG_FILE" ]
  run grep -E '^rebuild elapsed seconds: [0-9]+' "$LOG_FILE"
  [ "$status" -eq 0 ]
}

@test "DELIVERY-02 / Phase 13 SLO: rebuild elapsed seconds <= 230 (v0.18 baseline preserved)" {
  [ -f "$LOG_FILE" ]
  local elapsed
  elapsed="$(grep -E '^rebuild elapsed seconds: [0-9]+' "$LOG_FILE" | awk '{print $4}' | tail -1)"
  [ -n "$elapsed" ]
  [ "$elapsed" -le 230 ]
}
