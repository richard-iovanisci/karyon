#!/usr/bin/env bats
# tests/bats/create-clusters-02-hub-flux.bats
# L3 live-gated: kubectl --context k3d-hub-flux get nodes --no-headers has exactly one Ready node.

load 'test_helper'

setup() {
  require_live
}

teardown() {
  :
}

@test "CLU-02: hub-flux cluster reports 1 Ready node" {
  run bash -c "kubectl --context k3d-hub-flux get nodes --no-headers 2>/dev/null | awk '\$2 == \"Ready\" { count++ } END { print count + 0 }'"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}
