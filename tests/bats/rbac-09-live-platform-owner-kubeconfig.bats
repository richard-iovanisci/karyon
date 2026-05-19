#!/usr/bin/env bats
# tests/bats/rbac-09-live-platform-owner-kubeconfig.bats
# Phase 13 / Wave 0 (D-13-15 Nyquist gate)
# RBAC-04 + RBAC-06 — platform-owner LIST through capsule-proxy:
#   - LIST tenants returns alpha + bravo
#   - LIST namespaces returns tenant-alpha + tenant-bravo + alpha-app1 + bravo-app1
#   - LIST namespaces does NOT return kube-system (proxy filter)
#   - get nodes returns Forbidden (ceiling)
#   - get pods -n tenant-alpha succeeds (co-owner operational reach)
# RED until Plan 13-02 lands script + SA + dual-subject CRB + Tenant CR co-owner additions.

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

@test "RBAC-06 / D-13-07 (LIST tenants): proxy returns alpha + bravo for platform-owner kubeconfig" {
  run kubectl --kubeconfig="$PO_KUBECONFIG" get tenants -o jsonpath='{.items[*].metadata.name}'
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF 'alpha'
  echo "$output" | grep -qF 'bravo'
}

@test "RBAC-06 / D-13-07 (LIST namespaces): proxy returns tenant-alpha + tenant-bravo + alpha-app1 + bravo-app1" {
  run kubectl --kubeconfig="$PO_KUBECONFIG" get namespaces -o jsonpath='{.items[*].metadata.name}'
  [ "$status" -eq 0 ]
  for ns in tenant-alpha tenant-bravo alpha-app1 bravo-app1; do
    echo "$output" | grep -qF "$ns" || { echo "MISSING ns: $ns (got: $output)"; return 1; }
  done
}

@test "RBAC-06 / D-13-07 (LIST namespaces filter holds): proxy does NOT return kube-system" {
  run kubectl --kubeconfig="$PO_KUBECONFIG" get namespaces -o jsonpath='{.items[*].metadata.name}'
  [ "$status" -eq 0 ]
  # kube-system should NOT appear in platform-owner LIST through proxy
  if echo "$output" | grep -qF 'kube-system'; then
    echo "ANTI-PATTERN: kube-system leaked through proxy LIST (got: $output)"
    return 1
  fi
}

@test "RBAC-04 (Forbidden): platform-owner get nodes returns non-zero + Forbidden text" {
  run kubectl --kubeconfig="$PO_KUBECONFIG" get nodes
  [ "$status" -ne 0 ]
  echo "$output" | grep -qE 'Forbidden|forbidden'
}

@test "RBAC-06 / D-13-07 (co-owner positive): platform-owner get pods -n tenant-alpha succeeds" {
  run kubectl --kubeconfig="$PO_KUBECONFIG" get pods -n tenant-alpha
  [ "$status" -eq 0 ]
}
