#!/usr/bin/env bats
# tests/bats/tenants-07-live-impersonate.bats
# Phase 9 / Wave 0 (D-09-08 Nyquist gate)
# TEN-02 — kubectl --as=alpha impersonation creates tenant namespace.
# Plans 09-01..09-03 land the yaml that turns these GREEN.
#
# Verifies (per CONTEXT D-09-07 + RESEARCH §Gap 7 impersonation prereqs):
#   - kubectl --as=alpha can create namespace alpha-app1 (idempotent — apply, NOT create)
#     Idempotent because subsequent runs would otherwise fail with AlreadyExists;
#     we use kubectl create --dry-run | kubectl apply pipeline so re-runs are safe.
#   - namespace alpha-app1 has capsule.clastix.io/tenant=alpha label (3×30s retry —
#     auto-stamped by Capsule webhook on namespace admission)
#   - mirror for bravo
#
# Cluster-info gate auto-skips when k3d-spoke-capsule unreachable. The --as=
# impersonation requires the local kubeconfig to have system:masters / cluster-admin
# RBAC for the impersonate verb on User kind — k3d's default kubeconfig provides this.

load 'test_helper'

setup() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
}

# ---- alpha ----

@test "TEN-02 / D-09-07 (alpha): kubectl --as=alpha can create namespace alpha-app1 (idempotent — apply pipe)" {
  # Idempotent: pipe via apply -f - so re-runs don't fail with AlreadyExists.
  # The dry-run renders the namespace yaml; the apply is what Capsule's webhook
  # validates against the alpha User owner.
  run bash -c "kubectl --context=k3d-spoke-capsule --as=alpha create namespace alpha-app1 --dry-run=client -o yaml | kubectl --context=k3d-spoke-capsule --as=alpha apply -f -"
  [ "$status" -eq 0 ]
}

@test "TEN-02 / D-09-07 (alpha): namespace alpha-app1 has capsule.clastix.io/tenant=alpha label (auto-stamped, 3×30s retry)" {
  local i label
  for i in 1 2 3; do
    label=$(kubectl --context=k3d-spoke-capsule get namespace alpha-app1 -o jsonpath='{.metadata.labels.capsule\.clastix\.io/tenant}' 2>/dev/null || true)
    [[ "$label" == "alpha" ]] && return 0
    [[ $i -lt 3 ]] && sleep 30
  done
  echo "Last observed label: '$label'"
  return 1
}

# ---- bravo ----

@test "TEN-02 / D-09-07 (bravo): kubectl --as=bravo can create namespace bravo-app1 (idempotent — apply pipe)" {
  run bash -c "kubectl --context=k3d-spoke-capsule --as=bravo create namespace bravo-app1 --dry-run=client -o yaml | kubectl --context=k3d-spoke-capsule --as=bravo apply -f -"
  [ "$status" -eq 0 ]
}

@test "TEN-02 / D-09-07 (bravo): namespace bravo-app1 has capsule.clastix.io/tenant=bravo label (auto-stamped, 3×30s retry)" {
  local i label
  for i in 1 2 3; do
    label=$(kubectl --context=k3d-spoke-capsule get namespace bravo-app1 -o jsonpath='{.metadata.labels.capsule\.clastix\.io/tenant}' 2>/dev/null || true)
    [[ "$label" == "bravo" ]] && return 0
    [[ $i -lt 3 ]] && sleep 30
  done
  echo "Last observed label: '$label'"
  return 1
}
