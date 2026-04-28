#!/usr/bin/env bats
# tests/bats/docs-05-runbook.bats
# Phase 6 Wave 0 static contract for DOCS-05: docs/rebuild-runbook.md starts
# with an h1; lists the 7 step markers in strict order; references the Phase 5
# 190-second baseline; carries a Common failures appendix with key failure-mode
# keywords (fix-dns, nvidia.com/gpu, tls-san).

load 'test_helper'

setup() {
  DOC="${REPO_ROOT}/docs/rebuild-runbook.md"
}

@test "DOCS-05: docs/rebuild-runbook.md exists and starts with an h1" {
  [ -f "$DOC" ]
  run bash -c "head -1 '$DOC' | grep -E '^# '"
  [ "$status" -eq 0 ]
}

@test "DOCS-05 (D-04): rebuild runbook lists the 7 step names in strict order" {
  [ -f "$DOC" ]
  previous=0
  for literal in \
    '>>> step preflight' \
    '>>> step destroy' \
    '>>> step create-clusters' \
    '>>> step bootstrap-flux' \
    '>>> step register-spokes' \
    '>>> step deploy-examples' \
    '>>> step health-check'
  do
    line="$(grep -nF -- "$literal" "$DOC" | head -1 | cut -d: -f1)"
    [ -n "$line" ]
    [ "$line" -gt "$previous" ]
    previous="$line"
  done
}

@test "DOCS-05 (specifics): rebuild runbook references the Phase 5 190-second baseline" {
  [ -f "$DOC" ]
  run grep -E '\b190\b' "$DOC"
  [ "$status" -eq 0 ]
  run grep -iE '(seconds|s\b)' "$DOC"
  [ "$status" -eq 0 ]
}

@test "DOCS-05 (D-04): rebuild runbook has a Common failures appendix" {
  [ -f "$DOC" ]
  run grep -iE '^## (common failures|failure modes)' "$DOC"
  [ "$status" -eq 0 ]
  for literal in \
    'fix-dns' \
    'nvidia.com/gpu' \
    'tls-san'
  do
    run grep -iF -- "$literal" "$DOC"
    [ "$status" -eq 0 ]
  done
}
