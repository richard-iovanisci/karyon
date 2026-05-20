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

  # Direct-apiserver probe materials for the apiserver-RBAC-ceiling tests below.
  # The PO kubeconfig minted by issue-platform-owner-kubeconfig.sh routes through
  # capsule-proxy:30443, which DOES surface nodes to authenticated tenants as a
  # documented Capsule feature. To assert the Tier-2 ceiling at the apiserver-RBAC
  # layer (where the audience-facing demo Forbidden actually originates), the
  # node-read denial probe must hit the apiserver directly. The certificatesigningrequests
  # probe stays through the proxy because the proxy passes that through and the
  # apiserver Forbidden surfaces verbatim.
  PO_SA_TOKEN_DIRECT=$(kubectl --context=k3d-spoke-capsule -n capsule-system create token platform-owner --duration=30m 2>/dev/null || true)
  export PO_SA_TOKEN_DIRECT
  PO_DIRECT_SERVER=$(kubectl config view --minify --context=k3d-spoke-capsule -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null || true)
  export PO_DIRECT_SERVER
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

@test "DEMO-06 (Tier-2 ceiling): platform-owner cannot read nodes -o yaml (apiserver RBAC)" {
  # Asserted against the apiserver directly (not capsule-proxy:30443). capsule-proxy
  # surfaces a filtered nodes view to authenticated tenants as a documented Capsule
  # feature; the Tier-2 RBAC ceiling we are demoing lives at the apiserver and is the
  # one a future graduation to direct-apiserver kubeconfigs would expose. See
  # capsule-platform-owner ClusterRole — it intentionally lacks nodes verbs.
  [ -n "${PO_SA_TOKEN_DIRECT:-}" ] || skip "platform-owner SA token not minted (setup_file failed)"
  [ -n "${PO_DIRECT_SERVER:-}" ] || skip "apiserver URL not discovered (setup_file failed)"
  run env KUBECONFIG=/dev/null kubectl \
    --server="$PO_DIRECT_SERVER" \
    --token="$PO_SA_TOKEN_DIRECT" \
    --insecure-skip-tls-verify \
    get nodes -o yaml
  [ "$status" -ne 0 ]
  echo "$output" | grep -qE 'Forbidden|forbidden'
}

@test "DEMO-06 (Tier-2 ceiling): platform-owner cannot list certificatesigningrequests" {
  run kubectl --kubeconfig="$PO_KUBECONFIG" get certificatesigningrequests
  [ "$status" -ne 0 ]
  echo "$output" | grep -qE 'Forbidden|forbidden'
}
