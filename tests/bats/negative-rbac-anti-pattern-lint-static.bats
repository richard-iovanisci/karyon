#!/usr/bin/env bats
# tests/bats/negative-rbac-anti-pattern-lint-static.bats
# D-11-05 enforcement -- negative-rbac-*.bats source files MUST NOT contain
# `kubectl auth can-i` (Pitfall P37: SAR cache 5min/30s TTLs return stale results).

load 'test_helper'

setup() {
  NEGATIVE_RBAC_BATS=(
    "${REPO_ROOT}/tests/bats/negative-rbac-01-cross-tenant-list.bats"
    "${REPO_ROOT}/tests/bats/negative-rbac-02-escalation.bats"
    "${REPO_ROOT}/tests/bats/negative-rbac-03-webhook-policy.bats"
    "${REPO_ROOT}/tests/bats/negative-rbac-04-bypass-and-flux.bats"
    "${REPO_ROOT}/tests/bats/negative-rbac-05-webhook-down.bats"
  )
}

@test "D-11-05 / P37: negative-rbac-*.bats files have ZERO 'kubectl auth can-i' (SAR cache anti-pattern)" {
  for f in "${NEGATIVE_RBAC_BATS[@]}"; do
    [ -f "$f" ]
    run bash -c "grep -v '^[[:space:]]*#' '$f' | grep -F -- 'kubectl auth can-i'"
    [ "$status" -ne 0 ]
  done
}
