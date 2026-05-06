#!/usr/bin/env bats
# tests/bats/push-gate-03-static-tenant-ns-label.bats
# Phase 11 D-11-03 -- tenant home namespace YAML carries capsule.clastix.io/tenant=<name> label.
# RED until Plan 11-01 lands the edits (Plan 10-02 used --as=alpha/bravo impersonation; this
# is the GitOps source so first push reconciles cleanly).

load 'test_helper'

setup() {
  NS_ALPHA="${REPO_ROOT}/pocs/capsule/spoke/tenants/alpha/namespace.yaml"
  NS_BRAVO="${REPO_ROOT}/pocs/capsule/spoke/tenants/bravo/namespace.yaml"
}

@test "D-11-03: alpha/namespace.yaml has metadata.labels.capsule.clastix.io/tenant=alpha" {
  [ -f "$NS_ALPHA" ]
  run yq eval '.metadata.labels."capsule.clastix.io/tenant" == "alpha"' "$NS_ALPHA"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "D-11-03: bravo/namespace.yaml has metadata.labels.capsule.clastix.io/tenant=bravo" {
  [ -f "$NS_BRAVO" ]
  run yq eval '.metadata.labels."capsule.clastix.io/tenant" == "bravo"' "$NS_BRAVO"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}
