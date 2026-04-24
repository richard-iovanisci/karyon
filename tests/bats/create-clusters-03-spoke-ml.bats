#!/usr/bin/env bats
# tests/bats/create-clusters-03-spoke-ml.bats
# L3 live-gated: spoke-ml Ready AND advertises nvidia.com/gpu capacity >= 1 (CLU-03 / IMG-04 / IMG-05). Verifies all three legs of the 3-part k3d GPU contract end-to-end.
# Wave 0 stub — body filled by Plan 02-05.

load 'test_helper'

setup() {
  require_live
}

teardown() {
  :
}

@test "CLU-03: spoke-ml advertises nvidia.com/gpu capacity >= 1" {
  run bash -c "kubectl --context k3d-spoke-ml get nodes -o jsonpath='{.items[*].status.capacity.nvidia\.com/gpu}'"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  [ "$output" -ge 1 ]
}
