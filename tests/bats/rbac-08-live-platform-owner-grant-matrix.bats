#!/usr/bin/env bats
# tests/bats/rbac-08-live-platform-owner-grant-matrix.bats
# Phase 13 / Wave 0 (D-13-15 Nyquist gate)
# RBAC-04 — platform-owner ceiling:
#   - auth can-i '*' '*' returns no
#   - nodes / csr / clusterrolebinding return no (Tier-1 surface)
#   - positive Tenant CR + namespace LIST grants
# RED until Plan 13-02 lands issue-platform-owner-kubeconfig.sh + SA + dual-subject CRB.

load 'test_helper'

setup_file() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
  export KARYON_BATS_TMPDIR="${TMPDIR:-/tmp}/karyon-tenants/bats-${BATS_RUN_TMPDIR##*/}"
  mkdir -p "$KARYON_BATS_TMPDIR"
  bash "${REPO_ROOT}/scripts/poc/capsule/issue-platform-owner-kubeconfig.sh" \
    --duration=2h --write-to "${KARYON_BATS_TMPDIR}/po.kubeconfig" >/dev/null 2>&1
  export PO_KUBECONFIG="${KARYON_BATS_TMPDIR}/po.kubeconfig"
}

teardown_file() {
  rm -rf "$KARYON_BATS_TMPDIR"
}

setup() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
  [ -f "${PO_KUBECONFIG:-/dev/null}" ] || skip "platform-owner kubeconfig not minted (setup_file failed; expected RED pre-implementation)"
}

# ---- positive: Tier-2 platform-owner grants ----

@test "RBAC-04 / D-13-06 (positive): platform-owner can create tenants.capsule.clastix.io" {
  run bash -c "kubectl --kubeconfig=\"$PO_KUBECONFIG\" auth can-i create tenants.capsule.clastix.io 2>/dev/null"
  [ "$output" = "yes" ]
}

@test "RBAC-04 / D-13-06 (positive): platform-owner can list tenants.capsule.clastix.io" {
  run bash -c "kubectl --kubeconfig=\"$PO_KUBECONFIG\" auth can-i list tenants.capsule.clastix.io 2>/dev/null"
  [ "$output" = "yes" ]
}

@test "RBAC-04 / D-13-06 (positive): platform-owner can get tenants.capsule.clastix.io" {
  run bash -c "kubectl --kubeconfig=\"$PO_KUBECONFIG\" auth can-i get tenants.capsule.clastix.io 2>/dev/null"
  [ "$output" = "yes" ]
}

@test "RBAC-04 / D-13-06 (positive): platform-owner can list namespaces (Tier-2 visibility)" {
  run bash -c "kubectl --kubeconfig=\"$PO_KUBECONFIG\" auth can-i list namespaces 2>/dev/null"
  [ "$output" = "yes" ]
}

@test "RBAC-04 / D-13-06 (positive): platform-owner can get customresourcedefinitions" {
  run bash -c "kubectl --kubeconfig=\"$PO_KUBECONFIG\" auth can-i get customresourcedefinitions 2>/dev/null"
  [ "$output" = "yes" ]
}

# ---- denial: Tier-1 ceiling enforcement ----

@test "RBAC-04 / D-13-06 (ceiling): platform-owner auth can-i '*' '*' returns no" {
  run bash -c "kubectl --kubeconfig=\"$PO_KUBECONFIG\" auth can-i '*' '*' 2>/dev/null"
  [ "$output" = "no" ]
}

@test "RBAC-04 / D-13-06 (ceiling): platform-owner cannot get nodes" {
  run bash -c "kubectl --kubeconfig=\"$PO_KUBECONFIG\" auth can-i get nodes 2>/dev/null"
  [ "$output" = "no" ]
}

@test "RBAC-04 / D-13-06 (ceiling): platform-owner cannot get csr" {
  run bash -c "kubectl --kubeconfig=\"$PO_KUBECONFIG\" auth can-i get certificatesigningrequests 2>/dev/null"
  [ "$output" = "no" ]
}

@test "RBAC-04 / D-13-06 (ceiling): platform-owner cannot create clusterrolebinding" {
  run bash -c "kubectl --kubeconfig=\"$PO_KUBECONFIG\" auth can-i create clusterrolebinding 2>/dev/null"
  [ "$output" = "no" ]
}

@test "RBAC-04 / D-13-06 (ceiling): platform-owner create namespaces is RBAC-allowed but webhook-gated" {
  # Capsule's standard install ClusterRoleBinding 'capsule-namespace-provisioner' binds
  # ClusterRole capsule-namespace-provisioner (verbs: create namespaces) to ALL
  # system:authenticated + system:serviceaccounts groups. So the k8s RBAC layer
  # returns 'yes' for any authenticated subject. The actual ceiling is enforced by
  # Capsule's MUTATING webhook, which rejects namespace creates not assigned to a
  # tenant the caller owns. This test documents the RBAC-layer answer (yes); the
  # tenant-ownership semantic is exercised by rbac-09-live (namespace LIST filter
  # through capsule-proxy) and rbac-10-live (Tenant CRUD via new-tenant.sh).
  run bash -c "kubectl --kubeconfig=\"$PO_KUBECONFIG\" auth can-i create namespaces 2>/dev/null"
  [ "$output" = "yes" ]
}
