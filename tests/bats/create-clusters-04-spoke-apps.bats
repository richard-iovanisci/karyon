#!/usr/bin/env bats
# tests/bats/create-clusters-04-spoke-apps.bats
# L3 live-gated: kubectl --context k3d-spoke-apps get nodes --no-headers has exactly one Ready node (CLU-04).
# Wave 0 stub — body filled by Plan 02-05.

load 'test_helper'

setup() {
  require_live
}

teardown() {
  :
}

@test "CLU-04: spoke-apps cluster reports 1 Ready node" {
  run bash -c "kubectl --context k3d-spoke-apps get nodes --no-headers 2>/dev/null | awk '\$2 == \"Ready\" { count++ } END { print count + 0 }'"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}
