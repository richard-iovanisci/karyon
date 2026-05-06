#!/usr/bin/env bats
# tests/bats/push-gate-01-static-rbac-postbuild.bats
# Phase 11 D-11-01 -- Flux PostBuild patch on clusters/hub-flux/pocs/capsule.yaml extends
# the chart-rendered Role capsule-proxy:capsule-proxy in capsule-system with secrets RBAC
# (so kube-webhook-certgen Job can write its output Secret on initial Flux reconcile).
# RED until Plan 11-01 lands the patch. See Pitfall 11-P1 for alternative target file.
#
# IMPORTANT (reviewer HIGH #2): This static GREEN does NOT prove patch propagation.
# Plan 11-04 Task 3 runs a discriminating jq check against the LIVE chart-rendered Role
# (kubectl get role capsule-proxy:capsule-proxy -o json | jq -e '.rules[] | select(.resources contains ["secrets"]) | select(.verbs contains ["create"])');
# if RED, disposition is downgraded to passed_with_overrides at best.

load 'test_helper'

setup() {
  POC_CAPSULE="${REPO_ROOT}/clusters/hub-flux/pocs/capsule.yaml"
}

@test "D-11-01: capsule.yaml has spec.patches block targeting Role capsule-proxy:capsule-proxy in capsule-system" {
  [ -f "$POC_CAPSULE" ]
  run yq eval '(.spec.patches // []) | map(select(.target.kind == "Role" and .target.name == "capsule-proxy:capsule-proxy" and .target.namespace == "capsule-system")) | length >= 1' "$POC_CAPSULE"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "D-11-01: capsule.yaml patch literal includes secrets verb 'create' (so certgen Job can write Secret)" {
  [ -f "$POC_CAPSULE" ]
  run grep -F -- '"create"' "$POC_CAPSULE"
  [ "$status" -eq 0 ]
}
