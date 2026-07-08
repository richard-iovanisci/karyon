#!/usr/bin/env bats
# tests/bats/push-gate-02-static-capsuleconfig.bats
# CapsuleConfiguration spec.userGroups extended to a 3-group list
# so capsule-proxy LIST recognizes SA-token-authenticated identities as Capsule-owned.
# This file is the GitOps source for a change that was first patched live.

load 'test_helper'

setup() {
  CC="${REPO_ROOT}/pocs/capsule/spoke/config/capsuleconfig.yaml"
}

# AMENDED 2026-07-06 (keycloak-idp-poc): 4 OIDC group-scope entries appended
# for the Keycloak realm (Group-kind Tenant owners must be in userGroups).
@test "D-11-02 + keycloak-idp: capsuleconfig.yaml spec.userGroups contains the 3 canonical + 4 OIDC groups" {
  [ -f "$CC" ]
  run yq eval '(.spec.userGroups | length) == 7 and (.spec.userGroups | contains(["capsule.clastix.io"])) and (.spec.userGroups | contains(["system:serviceaccounts"])) and (.spec.userGroups | contains(["system:authenticated"])) and (.spec.userGroups | contains(["capsule-users"])) and (.spec.userGroups | contains(["capsule-platform-owners"])) and (.spec.userGroups | contains(["tenant-alpha-devs"])) and (.spec.userGroups | contains(["tenant-bravo-devs"]))' "$CC"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}
