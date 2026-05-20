#!/usr/bin/env bats
# tests/bats/demo-06-live-platform-owner-cluster-admin-denials.bats
# Phase 14 / Wave 0 (D-14-08 + D-13-15 Nyquist gate)
# DEMO-06 — platform-owner 3-action cluster-admin denial matrix (CRB + nodes -o yaml + csr) with verbatim RESEARCH Q6 CRB Forbidden string.
# RED until Plan 14-02 lands DEMO bats GREEN against the live cluster.

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

@test "DEMO-06 (Tier-2 ceiling): platform-owner cannot create ClusterRoleBinding (headline)" {
  run kubectl --kubeconfig="$PO_KUBECONFIG" create clusterrolebinding po-cluster-admin-attempt \
    --clusterrole=cluster-admin --user=platform-owner
  [ "$status" -ne 0 ]
  # Q6 RESEARCH verbatim Forbidden string
  echo "$output" | grep -qF "clusterrolebindings.rbac.authorization.k8s.io is forbidden"
  echo "$output" | grep -qF "system:serviceaccount:capsule-system:platform-owner"
}

@test "DEMO-06 (Tier-2 ceiling): platform-owner cannot read nodes -o yaml" {
  run kubectl --kubeconfig="$PO_KUBECONFIG" get nodes -o yaml
  [ "$status" -ne 0 ]
  echo "$output" | grep -qE 'Forbidden|forbidden'
}

@test "DEMO-06 (Tier-2 ceiling): platform-owner cannot list certificatesigningrequests" {
  run kubectl --kubeconfig="$PO_KUBECONFIG" get certificatesigningrequests
  [ "$status" -ne 0 ]
  echo "$output" | grep -qE 'Forbidden|forbidden'
}
