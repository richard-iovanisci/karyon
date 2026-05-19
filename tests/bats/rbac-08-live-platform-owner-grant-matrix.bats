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
  run kubectl --kubeconfig="$PO_KUBECONFIG" auth can-i create tenants.capsule.clastix.io
  [ "$output" = "yes" ]
}

@test "RBAC-04 / D-13-06 (positive): platform-owner can list tenants.capsule.clastix.io" {
  run kubectl --kubeconfig="$PO_KUBECONFIG" auth can-i list tenants.capsule.clastix.io
  [ "$output" = "yes" ]
}

@test "RBAC-04 / D-13-06 (positive): platform-owner can get tenants.capsule.clastix.io" {
  run kubectl --kubeconfig="$PO_KUBECONFIG" auth can-i get tenants.capsule.clastix.io
  [ "$output" = "yes" ]
}

@test "RBAC-04 / D-13-06 (positive): platform-owner can list namespaces (Tier-2 visibility)" {
  run kubectl --kubeconfig="$PO_KUBECONFIG" auth can-i list namespaces
  [ "$output" = "yes" ]
}

@test "RBAC-04 / D-13-06 (positive): platform-owner can get customresourcedefinitions" {
  run kubectl --kubeconfig="$PO_KUBECONFIG" auth can-i get customresourcedefinitions
  [ "$output" = "yes" ]
}

# ---- denial: Tier-1 ceiling enforcement ----

@test "RBAC-04 / D-13-06 (ceiling): platform-owner auth can-i '*' '*' returns no" {
  run kubectl --kubeconfig="$PO_KUBECONFIG" auth can-i '*' '*'
  [ "$output" = "no" ]
}

@test "RBAC-04 / D-13-06 (ceiling): platform-owner cannot get nodes" {
  run kubectl --kubeconfig="$PO_KUBECONFIG" auth can-i get nodes
  [ "$output" = "no" ]
}

@test "RBAC-04 / D-13-06 (ceiling): platform-owner cannot get csr" {
  run kubectl --kubeconfig="$PO_KUBECONFIG" auth can-i get certificatesigningrequests
  [ "$output" = "no" ]
}

@test "RBAC-04 / D-13-06 (ceiling): platform-owner cannot create clusterrolebinding" {
  run kubectl --kubeconfig="$PO_KUBECONFIG" auth can-i create clusterrolebinding
  [ "$output" = "no" ]
}

@test "RBAC-04 / D-13-06 (ceiling): platform-owner cannot create namespaces (cluster-scoped)" {
  run kubectl --kubeconfig="$PO_KUBECONFIG" auth can-i create namespaces
  [ "$output" = "no" ]
}
