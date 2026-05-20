#!/usr/bin/env bats
# tests/bats/runbook-03-static-tls-noise.bats
# Phase 14 / Wave 0 (D-14-08 + D-13-15 Nyquist gate)
# RUNBOOK-03 + D-14-01 — TLS-noise appendix verbatim 'tls: bad certificate' literal + ADR-008 cross-link + appears AFTER Act 6 + capsule-controller-manager literal.
# RED until Plan 14-01 lands the 6-act demo runbook.

load 'test_helper'

setup() {
  DOC="${REPO_ROOT}/docs/poc-capsule-demo.md"
}

@test "RUNBOOK-03 / D-14-01: doc contains verbatim 'tls: bad certificate' string" {
  [ -f "$DOC" ]
  run grep -F -- 'tls: bad certificate' "$DOC"
  [ "$status" -eq 0 ]
}

@test "RUNBOOK-03 / D-14-01: TLS noise section cross-links ADR-008" {
  [ -f "$DOC" ]
  run grep -iE '(adr/0008|ADR-008)' "$DOC"
  [ "$status" -eq 0 ]
}

@test "RUNBOOK-03 / D-14-01: 'Known noise' appendix appears AFTER Act 6 (not inline)" {
  [ -f "$DOC" ]
  act6_line="$(grep -nE '^## Act 6 —' "$DOC" | head -1 | cut -d: -f1)"
  noise_line="$(grep -nE '^## Known noise' "$DOC" | head -1 | cut -d: -f1)"
  [ -n "$act6_line" ]
  [ -n "$noise_line" ]
  [ "$noise_line" -gt "$act6_line" ]
}

@test "RUNBOOK-03 / D-14-01: noise section labels chatter as capsule-controller-manager" {
  [ -f "$DOC" ]
  run grep -iF -- 'capsule-controller-manager' "$DOC"
  [ "$status" -eq 0 ]
}
