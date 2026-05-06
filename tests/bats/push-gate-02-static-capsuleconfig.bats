#!/usr/bin/env bats
# tests/bats/push-gate-02-static-capsuleconfig.bats
# Phase 11 D-11-02 -- CapsuleConfiguration spec.userGroups extended to 3-group list
# so capsule-proxy LIST recognizes SA-token-authenticated identities as Capsule-owned.
# RED until Plan 11-01 lands the edit (Plan 10-02 patched live; this is the GitOps source).

load 'test_helper'

setup() {
  CC="${REPO_ROOT}/pocs/capsule/spoke/config/capsuleconfig.yaml"
}

@test "D-11-02: capsuleconfig.yaml spec.userGroups contains 3 canonical groups" {
  [ -f "$CC" ]
  run yq eval '(.spec.userGroups | length) == 3 and (.spec.userGroups | contains(["capsule.clastix.io"])) and (.spec.userGroups | contains(["system:serviceaccounts"])) and (.spec.userGroups | contains(["system:authenticated"]))' "$CC"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}
