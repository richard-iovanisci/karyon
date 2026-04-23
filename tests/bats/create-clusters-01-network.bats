#!/usr/bin/env bats
# tests/bats/create-clusters-01-network.bats
# Static-grep check (no bats-mock — see 02-PATTERNS.md §Shared Patterns "No bats-mock framework yet"; planning context confirms bats-mock is NOT installed) that scripts/create-clusters.sh declares K8S_NET_SUBNET="172.30.0.0/16" and K8S_NET_DRIVER="bridge" (CLU-01 / D-11).
# Wave 0 stub — body filled by Plan 02-05.

load 'test_helper'

setup() {
  SCRIPT="${REPO_ROOT}/scripts/create-clusters.sh"
}

teardown() {
  :
}

@test "CLU-01: scripts/create-clusters.sh declares k8s-net subnet 172.30.0.0/16 and driver bridge" {
  skip "awaiting implementation in plan 02-05 (scripts/create-clusters.sh created)"
  # run grep -E '^readonly K8S_NET_SUBNET="172\.30\.0\.0/16"' "$SCRIPT"
  # [ "$status" -eq 0 ]
  # run grep -E '^readonly K8S_NET_DRIVER="bridge"' "$SCRIPT"
  # [ "$status" -eq 0 ]
}
