#!/usr/bin/env bats
# tests/bats/negative-rbac-02-escalation.bats
# Phase 11 / Wave 0 (D-11-06 partition: N4 ClusterRoleBinding escalation).
# RED until Plan 11-03 turns this GREEN. Real-CRUD probe (D-11-05); mint-once kubeconfig (D-11-07).
# REVISED 2026-05-05: Pitfall 11-P6 strict-mode env var.

load 'test_helper'

_strict_skip() {
  local msg="$1"
  if [[ "${KARYON_PHASE11_STRICT_LIVE:-}" == "1" ]]; then
    echo "STRICT_LIVE: ${msg}" >&2
    return 1
  else
    skip "${msg}"
  fi
}

setup_file() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    if [[ "${KARYON_PHASE11_STRICT_LIVE:-}" == "1" ]]; then
      echo "STRICT_LIVE: k3d-spoke-capsule cluster not reachable" >&2
      return 1
    else
      skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
    fi
  fi
  export KARYON_BATS_TMPDIR="${TMPDIR:-/tmp}/karyon-tenants/bats-${BATS_RUN_TMPDIR##*/}"
  mkdir -p "$KARYON_BATS_TMPDIR"
  bash "${REPO_ROOT}/scripts/poc/capsule/issue-tenant-kubeconfig.sh" alpha gitops-reconciler \
    --duration=2h --write-to "${KARYON_BATS_TMPDIR}/alpha.kubeconfig" >/dev/null 2>&1
  export ALPHA_KUBECONFIG="${KARYON_BATS_TMPDIR}/alpha.kubeconfig"
}

teardown_file() {
  rm -rf "$KARYON_BATS_TMPDIR"
}

setup() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    _strict_skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
}

@test "N4 -- ClusterRoleBinding escalation denied (cluster-scope rights are not granted)" {
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" create clusterrolebinding evil-alpha \
    --clusterrole=cluster-admin --user=alpha
  [ "$status" -ne 0 ]
  echo "$output" | grep -qE "(forbidden|Forbidden|cannot create resource)"
  # Defensive cleanup if it somehow succeeded
  kubectl --context=k3d-spoke-capsule delete clusterrolebinding evil-alpha --ignore-not-found >/dev/null 2>&1 || true
}
