#!/usr/bin/env bats
# tests/bats/create-clusters-02-hub-flux.bats
# L3 live-gated: kubectl --context k3d-hub-flux get nodes --no-headers | grep -c Ready == 1 (CLU-02).
# Wave 0 stub — body filled by Plan 02-05.

load 'test_helper'

setup() {
  require_live
}

teardown() {
  :
}

@test "CLU-02: hub-flux cluster reports 1 Ready node" {
  run bash -c "kubectl --context k3d-hub-flux get nodes --no-headers 2>/dev/null | grep -c Ready"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}
