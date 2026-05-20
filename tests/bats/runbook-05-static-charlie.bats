#!/usr/bin/env bats
# tests/bats/runbook-05-static-charlie.bats
# Phase 14 / Wave 0 (D-14-08 + D-13-15 Nyquist gate)
# RUNBOOK-05 + D-14-02 + D-14-03 — marquee tenant name appears in Act 3 + Act 6 + new-tenant.sh provisioning literal + namespace literal.
# RED until Plan 14-01 lands the 6-act demo runbook with charlie references.

load 'test_helper'

setup() {
  DOC="${REPO_ROOT}/docs/poc-capsule-demo.md"
}

@test "RUNBOOK-05 / D-14-02: marquee tenant referenced in Act 3 (live provisioning)" {
  [ -f "$DOC" ]
  # Locate Act 3 boundary; assert marquee tenant appears between Act 3 and Act 4
  act3_line="$(grep -nE '^## Act 3 —' "$DOC" | head -1 | cut -d: -f1)"
  act4_line="$(grep -nE '^## Act 4 —' "$DOC" | head -1 | cut -d: -f1)"
  [ -n "$act3_line" ] && [ -n "$act4_line" ]
  run bash -c "sed -n \"${act3_line},${act4_line}p\" '$DOC' | grep -F 'charlie'"
  [ "$status" -eq 0 ]
}

@test "RUNBOOK-05 / D-14-02: marquee tenant referenced in Act 6 (cleanup)" {
  [ -f "$DOC" ]
  act6_line="$(grep -nE '^## Act 6 —' "$DOC" | head -1 | cut -d: -f1)"
  [ -n "$act6_line" ]
  run bash -c "tail -n +${act6_line} '$DOC' | grep -F 'charlie'"
  [ "$status" -eq 0 ]
}

@test "RUNBOOK-05 / D-14-03: Act 3 invokes 'new-tenant.sh charlie' live" {
  [ -f "$DOC" ]
  run grep -F -- 'new-tenant.sh charlie' "$DOC"
  [ "$status" -eq 0 ]
}

@test "RUNBOOK-05 / D-14-02: Act 4 watches tenant-charlie namespace for SEED-02 propagation" {
  [ -f "$DOC" ]
  run grep -F -- 'tenant-charlie' "$DOC"
  [ "$status" -eq 0 ]
}
