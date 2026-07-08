#!/usr/bin/env bats
# tests/bats/poc-isolation-01-static.bats
# POC isolation — v0.18 scripts must have ZERO spoke-capsule and ZERO register-poc-cluster mentions

load 'test_helper'

setup() {
  V018_SCRIPTS=(
    "${REPO_ROOT}/scripts/create-clusters.sh"
    "${REPO_ROOT}/scripts/register-spokes-for-flux.sh"
    "${REPO_ROOT}/scripts/health-check.sh"
    "${REPO_ROOT}/scripts/destroy.sh"
    "${REPO_ROOT}/scripts/delete-clusters.sh"
    "${REPO_ROOT}/scripts/rebuild.sh"
  )
}

@test "P31 / D-12: v0.18 scripts have ZERO spoke-capsule mentions (comments excluded)" {
  for f in "${V018_SCRIPTS[@]}"; do
    [ -f "$f" ]
    run bash -c "grep -v '^[[:space:]]*#' '$f' | grep -F -- 'spoke-capsule'"
    [ "$status" -ne 0 ]
  done
}

@test "P31 / D-12: v0.18 scripts have ZERO register-poc-cluster mentions" {
  for f in "${V018_SCRIPTS[@]}"; do
    [ -f "$f" ]
    run bash -c "grep -v '^[[:space:]]*#' '$f' | grep -F -- 'register-poc-cluster'"
    [ "$status" -ne 0 ]
  done
}

@test "P31 / D-12: v0.18 scripts have ZERO scripts/poc/ path mentions" {
  for f in "${V018_SCRIPTS[@]}"; do
    [ -f "$f" ]
    run bash -c "grep -v '^[[:space:]]*#' '$f' | grep -F -- 'scripts/poc/'"
    [ "$status" -ne 0 ]
  done
}
