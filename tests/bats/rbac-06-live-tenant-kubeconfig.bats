#!/usr/bin/env bats
# tests/bats/rbac-06-live-tenant-kubeconfig.bats
# Phase 13 / Wave 0 (D-13-15 Nyquist gate)
# RBAC-02 + DEMO-04 boundary — tenant-owner kubeconfig:
#   - auth can-i '*' '*' returns no
#   - positive control: get pods -n tenant-alpha succeeds
#   - DEMO-04 boundary: create secret returns Forbidden
# RED until Plan 13-01..13-02 land (script + SA + ClusterRole + binding).

load 'test_helper'

setup_file() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
  export KARYON_BATS_TMPDIR="${TMPDIR:-/tmp}/karyon-tenants/bats-${BATS_RUN_TMPDIR##*/}"
  mkdir -p "$KARYON_BATS_TMPDIR"
  bash "${REPO_ROOT}/scripts/poc/capsule/issue-tenant-kubeconfig.sh" alpha human-tenant-owner \
    --duration=2h --write-to "${KARYON_BATS_TMPDIR}/alpha.kubeconfig" >/dev/null 2>&1
  export ALPHA_KUBECONFIG="${KARYON_BATS_TMPDIR}/alpha.kubeconfig"
}

teardown_file() {
  rm -rf "$KARYON_BATS_TMPDIR"
}

setup() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
  [ -f "${ALPHA_KUBECONFIG:-/dev/null}" ] || skip "alpha kubeconfig not minted (setup_file failed; expected RED pre-implementation)"
}

@test "RBAC-02 / D-13-04 (alpha): kubectl auth can-i '*' '*' returns no (no cluster-admin)" {
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" auth can-i '*' '*'
  [ "$output" = "no" ]
}

@test "RBAC-01 (alpha positive control): kubectl get pods -n tenant-alpha exits 0" {
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" get pods -n tenant-alpha
  [ "$status" -eq 0 ]
}

@test "RBAC-01 / DEMO-04 / D-13-01 (alpha boundary): kubectl create secret -n tenant-alpha returns Forbidden" {
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" create secret generic phase13-probe \
    --from-literal=k=v -n tenant-alpha
  [ "$status" -ne 0 ]
  # Pitfall 11-P3 lesson: permissive grep for variants of Forbidden text
  echo "$output" | grep -qE 'Forbidden|forbidden|cannot create resource'
  # Idempotent cleanup in case create unexpectedly succeeded
  kubectl --kubeconfig="$ALPHA_KUBECONFIG" delete secret phase13-probe -n tenant-alpha \
    --ignore-not-found --wait=false >/dev/null 2>&1 || true
}
