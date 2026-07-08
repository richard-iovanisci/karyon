#!/usr/bin/env bats
# tests/bats/delivery-02-static-paths.bats
# File layout + POC isolation:
#   - All NEW POC artifacts live under pocs/capsule/spoke/ or scripts/poc/capsule/
#   - Taskfile.yml has ZERO POC task entries (no Taskfile edits for the POC)
#   - v0.18 default-path scripts have ZERO mentions of the POC literals (superset of
#     poc-isolation-01-static.bats which already catches spoke-capsule/register-poc-cluster/scripts/poc/)
# Forbidden-literal greps strip comments via `grep -v '^[[:space:]]*#'` so a mere
# comment mention cannot trip the gate (self-invalidating grep-gate anti-pattern).

load 'test_helper'

setup() {
  V018_SCRIPTS=(
    "${REPO_ROOT}/scripts/preflight.sh"
    "${REPO_ROOT}/scripts/create-clusters.sh"
    "${REPO_ROOT}/scripts/register-spokes-for-flux.sh"
    "${REPO_ROOT}/scripts/health-check.sh"
    "${REPO_ROOT}/scripts/destroy.sh"
    "${REPO_ROOT}/scripts/delete-clusters.sh"
    "${REPO_ROOT}/scripts/rebuild.sh"
  )
  PHASE13_FORBIDDEN=(
    'tenant-workload-editor'
    'platform-owner'
    'human-tenant-owner'
    'GlobalTenantResource'
    'hello-world'
    'scripts/poc/capsule/issue-platform-owner-kubeconfig'
    'scripts/poc/capsule/new-tenant'
  )
  TASKFILE_FORBIDDEN=(
    'seed-capsule-demo'
    'issue-platform-owner-kubeconfig'
    'new-tenant'
  )
  PHASE13_ARTIFACTS=(
    "${REPO_ROOT}/pocs/capsule/spoke/rbac/tenant-workload-editor.yaml"
    "${REPO_ROOT}/pocs/capsule/spoke/rbac/platform-owner-sa.yaml"
    "${REPO_ROOT}/pocs/capsule/spoke/tenants/alpha/human-owner-sa.yaml"
    "${REPO_ROOT}/pocs/capsule/spoke/tenants/bravo/human-owner-sa.yaml"
    "${REPO_ROOT}/pocs/capsule/spoke/global-resources/hello-world.yaml"
    "${REPO_ROOT}/pocs/capsule/spoke/global-resources/kustomization.yaml"
    "${REPO_ROOT}/scripts/poc/capsule/issue-platform-owner-kubeconfig.sh"
    "${REPO_ROOT}/scripts/poc/capsule/new-tenant.sh"
  )
}

@test "DELIVERY-01 / D-13-13: all Phase 13 NEW artifacts exist under pocs/capsule/spoke/ or scripts/poc/capsule/" {
  for f in "${PHASE13_ARTIFACTS[@]}"; do
    [ -f "$f" ] || { echo "MISSING: $f"; return 1; }
  done
}

@test "DELIVERY-02 / D-13-14: Taskfile.yml exists and has NO new Phase 13 task entries (comments excluded)" {
  [ -f "${REPO_ROOT}/Taskfile.yml" ]
  for literal in "${TASKFILE_FORBIDDEN[@]}"; do
    run bash -c "grep -v '^[[:space:]]*#' '${REPO_ROOT}/Taskfile.yml' | grep -F -- '${literal}'"
    [ "$status" -ne 0 ] || { echo "FORBIDDEN literal '$literal' present in Taskfile.yml"; return 1; }
  done
}

@test "DELIVERY-02 / P31: v0.18 default-path scripts have ZERO Phase 13 literal mentions (comments excluded)" {
  for f in "${V018_SCRIPTS[@]}"; do
    [ -f "$f" ] || { echo "MISSING (v0.18 script): $f"; return 1; }
    for literal in "${PHASE13_FORBIDDEN[@]}"; do
      run bash -c "grep -v '^[[:space:]]*#' '$f' | grep -F -- '${literal}'"
      [ "$status" -ne 0 ] || { echo "P31 violation: '$literal' in $f"; return 1; }
    done
  done
}
