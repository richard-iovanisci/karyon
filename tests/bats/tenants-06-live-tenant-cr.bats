#!/usr/bin/env bats
# tests/bats/tenants-06-live-tenant-cr.bats
# Live — Tenant CRs alpha + bravo on spoke-capsule.
#
# Verifies (forceTenantPrefix is TOP-LEVEL in the v1beta2 schema):
#   - kubectl get tenant alpha reports spec.forceTenantPrefix=false (3×30s retry)
#   - kubectl get tenant bravo reports spec.forceTenantPrefix=false (3×30s retry)
#   - tenant-{alpha,bravo} namespace exists on spoke-capsule
#   - gitops-reconciler ServiceAccount exists in tenant-{alpha,bravo} namespace
#
# Cluster-info gate — auto-skips when k3d-spoke-capsule is unreachable
# (a reachability probe, deliberately NOT the KARYON_LIVE_TESTS env var).

load 'test_helper'

setup() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
}

# ---- alpha ----

@test "TEN-01 / D-11-07 (alpha): kubectl get tenant alpha reports forceTenantPrefix=false (TOP-LEVEL, 3×30s retry)" {
  local i ftp
  for i in 1 2 3; do
    ftp=$(kubectl --context=k3d-spoke-capsule get tenant alpha -o jsonpath='{.spec.forceTenantPrefix}' 2>/dev/null || true)
    [[ "$ftp" == "false" ]] && return 0
    [[ $i -lt 3 ]] && sleep 30
  done
  echo "Last observed forceTenantPrefix: '$ftp'"
  return 1
}

@test "TEN-01 / D-09-02 (alpha): tenant-alpha namespace exists on spoke-capsule" {
  run kubectl --context=k3d-spoke-capsule get namespace tenant-alpha
  [ "$status" -eq 0 ]
}

@test "TEN-01 / D-09-02 (alpha): gitops-reconciler ServiceAccount exists in tenant-alpha namespace" {
  run kubectl --context=k3d-spoke-capsule -n tenant-alpha get sa gitops-reconciler
  [ "$status" -eq 0 ]
}

# ---- bravo ----

@test "TEN-01 / D-11-07 (bravo): kubectl get tenant bravo reports forceTenantPrefix=false (TOP-LEVEL, 3×30s retry)" {
  local i ftp
  for i in 1 2 3; do
    ftp=$(kubectl --context=k3d-spoke-capsule get tenant bravo -o jsonpath='{.spec.forceTenantPrefix}' 2>/dev/null || true)
    [[ "$ftp" == "false" ]] && return 0
    [[ $i -lt 3 ]] && sleep 30
  done
  echo "Last observed forceTenantPrefix: '$ftp'"
  return 1
}

@test "TEN-01 / D-09-02 (bravo): tenant-bravo namespace exists on spoke-capsule" {
  run kubectl --context=k3d-spoke-capsule get namespace tenant-bravo
  [ "$status" -eq 0 ]
}

@test "TEN-01 / D-09-02 (bravo): gitops-reconciler ServiceAccount exists in tenant-bravo namespace" {
  run kubectl --context=k3d-spoke-capsule -n tenant-bravo get sa gitops-reconciler
  [ "$status" -eq 0 ]
}
