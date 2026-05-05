#!/usr/bin/env bats
# tests/bats/proxy-07-live-regression.bats
# Phase 10 / Wave 0 (D-10-09 Nyquist gate)
# Multi-cluster regression-rerun: Phase 7 P31 isolation + Phase 8 CAP-01..03 + Phase 9 TEN-01..06 + ADR-004
# Phase 10's script-only landing must NOT regress any prior-phase invariant.
# Multi-cluster cluster-info gate (k3d-hub-flux + k3d-spoke-capsule + k3d-spoke-apps + k3d-spoke-ml).

load 'test_helper'

setup() {
  for ctx in k3d-hub-flux k3d-spoke-apps k3d-spoke-ml k3d-spoke-capsule; do
    if ! kubectl --context="$ctx" cluster-info >/dev/null 2>&1; then
      skip "${ctx} cluster not reachable; skipping live regression"
    fi
  done
}

@test "Phase 7 P31 inheritance: task health-check exits 0 (v0.18 baseline)" {
  run bash -c "cd '${REPO_ROOT}' && task health-check"
  [ "$status" -eq 0 ]
}

@test "Phase 7 P31 inheritance: v0.18 scripts (excluding scripts/poc/) have ZERO 'spoke-capsule' mentions" {
  cd "${REPO_ROOT}"
  for script in scripts/create-clusters.sh scripts/register-spokes-for-flux.sh scripts/health-check.sh scripts/destroy.sh scripts/delete-clusters.sh scripts/rebuild.sh; do
    [ -f "$script" ]
    run grep -F -- 'spoke-capsule' "$script"
    [ "$status" -ne 0 ]
  done
}

@test "Phase 8 CAP-01 inheritance: HelmRelease capsule Ready=True on hub-flux" {
  ready=$(kubectl --context=k3d-hub-flux -n capsule-system get helmrelease capsule -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
  [ "$ready" = "True" ]
}

@test "Phase 8 CAP-03 inheritance: ≥7 capsule.clastix.io CRDs visible on spoke-capsule" {
  crd_count=$(kubectl --context=k3d-spoke-capsule get crds 2>/dev/null | grep -c 'capsule\.clastix\.io' || true)
  [ "$crd_count" -ge 7 ]
}

@test "ADR-004 inheritance: spoke-capsule flux-system has zero Flux controllers (NotFound or empty)" {
  ns_check=$(kubectl --context=k3d-spoke-capsule get ns flux-system -o jsonpath='{.status.phase}' 2>&1 || true)
  if echo "$ns_check" | grep -qF 'NotFound'; then return 0; fi
  pod_count=$(kubectl --context=k3d-spoke-capsule get pods -n flux-system --no-headers 2>/dev/null | wc -l)
  [ "$pod_count" -eq 0 ]
}

@test "Phase 9 TEN-01 inheritance: Tenant CRs alpha + bravo report forceTenantPrefix=true" {
  ftp_alpha=$(kubectl --context=k3d-spoke-capsule get tenant alpha -o jsonpath='{.spec.forceTenantPrefix}' 2>/dev/null || true)
  ftp_bravo=$(kubectl --context=k3d-spoke-capsule get tenant bravo -o jsonpath='{.spec.forceTenantPrefix}' 2>/dev/null || true)
  [ "$ftp_alpha" = "true" ]
  [ "$ftp_bravo" = "true" ]
}

@test "Phase 9 D-09-02 inheritance: gitops-reconciler SA exists in tenant-{alpha,bravo} namespaces" {
  for tenant in alpha bravo; do
    run kubectl --context=k3d-spoke-capsule -n "tenant-${tenant}" get sa gitops-reconciler -o name
    [ "$status" -eq 0 ]
  done
}

@test "Phase 9 TEN-04/P27 inheritance: every pocs/capsule/tenants/*.yaml has spec.serviceAccountName" {
  cd "${REPO_ROOT}"
  for tenant_k in pocs/capsule/tenants/alpha.yaml pocs/capsule/tenants/bravo.yaml; do
    [ -f "$tenant_k" ]
    sa_name=$(yq eval '.spec.serviceAccountName' "$tenant_k")
    [ -n "$sa_name" ]
    [ "$sa_name" != "null" ]
  done
}
