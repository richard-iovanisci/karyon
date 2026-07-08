#!/usr/bin/env bats
# tests/bats/preflight-pre15.bats
# scripts/preflight.sh has check_port_strict 30443 fail-fast

load 'test_helper'

setup() {
  PREFLIGHT="${REPO_ROOT}/scripts/preflight.sh"
}

@test "PRE-15: scripts/preflight.sh defines check_port_strict() helper" {
  [ -f "$PREFLIGHT" ]
  run grep -F -- 'check_port_strict()' "$PREFLIGHT"
  [ "$status" -eq 0 ]
}

@test "PRE-15 / D-15 / POC-04: scripts/preflight.sh invokes check_port_strict 30443" {
  [ -f "$PREFLIGHT" ]
  run grep -F -- 'check_port_strict 30443' "$PREFLIGHT"
  [ "$status" -eq 0 ]
}

@test "PRE-15: existing v0.18 check_port (warn-only) function name preserved" {
  [ -f "$PREFLIGHT" ]
  run grep -F -- 'check_port()' "$PREFLIGHT"
  [ "$status" -eq 0 ]
}

@test "PRE-15: v0.18 warn-loop over 6443 6444 6445 8080 8081 8082 unchanged (uses check_port not check_port_strict)" {
  [ -f "$PREFLIGHT" ]
  run grep -F -- 'for p in 6443 6444 6445 8080 8081 8082' "$PREFLIGHT"
  [ "$status" -eq 0 ]
}

@test "PRE-15 / D-15: check_port_strict body uses fail (not warn)" {
  [ -f "$PREFLIGHT" ]
  # Greedy multi-line awk: between check_port_strict() { and the closing }
  run bash -c "awk '/^check_port_strict\\(\\)/{flag=1} flag; /^}/{if(flag){flag=0; exit}}' '$PREFLIGHT' | grep -F -- 'fail '"
  [ "$status" -eq 0 ]
}

@test "PRE-15: Phase 7 PRE-15 section header present (greppable section marker)" {
  [ -f "$PREFLIGHT" ]
  run grep -F -- 'PRE-15' "$PREFLIGHT"
  [ "$status" -eq 0 ]
}
