#!/usr/bin/env bats
# tests/bats/runbook-01-static-acts.bats
# Phase 14 / Wave 0 (D-14-08 + D-13-15 Nyquist gate)
# RUNBOOK-01 — docs/poc-capsule-demo.md exists with h1, status:Active frontmatter, 6 ordered ## Act N — sections, >=6 ### Expected output blocks (D-14-04 + D-14-06).
# RED until Plan 14-01 lands the 6-act demo runbook.

load 'test_helper'

setup() {
  DOC="${REPO_ROOT}/docs/poc-capsule-demo.md"
}

@test "RUNBOOK-01: docs/poc-capsule-demo.md exists and starts with an h1" {
  [ -f "$DOC" ]
  run bash -c "head -20 '$DOC' | grep -E '^# '"
  [ "$status" -eq 0 ]
}

@test "RUNBOOK-01 / D-14-04: doc carries 'status: Active' frontmatter" {
  [ -f "$DOC" ]
  run grep -iE '^status:[[:space:]]*Active' "$DOC"
  [ "$status" -eq 0 ]
}

@test "RUNBOOK-01 / D-14-04: doc lists 6 acts in strict order" {
  [ -f "$DOC" ]
  previous=0
  for literal in \
    '## Act 1 — ' \
    '## Act 2 — ' \
    '## Act 3 — ' \
    '## Act 4 — ' \
    '## Act 5 — ' \
    '## Act 6 — '
  do
    line="$(grep -nF -- "$literal" "$DOC" | head -1 | cut -d: -f1)"
    [ -n "$line" ]
    [ "$line" -gt "$previous" ]
    previous="$line"
  done
}

@test "RUNBOOK-01 / D-14-06: every act has an 'Expected output' subsection" {
  [ -f "$DOC" ]
  count="$(grep -cE '^### Expected output' "$DOC")"
  [ "$count" -ge 6 ]
}
