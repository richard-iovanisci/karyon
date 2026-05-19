#!/usr/bin/env bats
# tests/bats/rbac-10-live-tenant-crud.bats
# Phase 13 / Wave 0 (D-13-15 Nyquist gate)
# RBAC-05 — Tenant CRUD via platform-owner kubeconfig (create/get/patch/delete).
# Uses scripts/poc/capsule/new-tenant.sh phase13-fresh for the create path.
# RED until Plan 13-02 lands new-tenant.sh + platform-owner kubeconfig minter.

load 'test_helper'

TEST_TENANT="phase13-fresh"

setup_file() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
  export KARYON_BATS_TMPDIR="${TMPDIR:-/tmp}/karyon-tenants/bats-${BATS_RUN_TMPDIR##*/}"
  mkdir -p "$KARYON_BATS_TMPDIR"
  bash "${REPO_ROOT}/scripts/poc/capsule/issue-platform-owner-kubeconfig.sh" \
    --duration=2h --write-to "${KARYON_BATS_TMPDIR}/po.kubeconfig" >/dev/null 2>&1
  export PO_KUBECONFIG="${KARYON_BATS_TMPDIR}/po.kubeconfig"
  # Idempotent precondition: ensure phase13-fresh does not pre-exist
  kubectl --context=k3d-spoke-capsule delete tenant phase13-fresh \
    --ignore-not-found --wait=false >/dev/null 2>&1 || true
}

teardown_file() {
  # Idempotent cleanup — best-effort; never fail the suite on cleanup error
  kubectl --context=k3d-spoke-capsule delete tenant phase13-fresh \
    --ignore-not-found --wait=false >/dev/null 2>&1 || true
  kubectl --context=k3d-spoke-capsule wait --for=delete namespace tenant-phase13-fresh \
    --timeout=30s >/dev/null 2>&1 || true
  rm -rf "$KARYON_BATS_TMPDIR"
}

setup() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
  [ -f "${PO_KUBECONFIG:-/dev/null}" ] || skip "platform-owner kubeconfig not minted (setup_file failed; expected RED pre-implementation)"
}

@test "RBAC-05 / D-13-08 (create): new-tenant.sh phase13-fresh exits 0 via platform-owner kubeconfig" {
  run bash "${REPO_ROOT}/scripts/poc/capsule/new-tenant.sh" phase13-fresh \
    --kubeconfig="$PO_KUBECONFIG"
  [ "$status" -eq 0 ]
}

@test "RBAC-05 / D-13-08 (get): kubectl get tenant phase13-fresh succeeds" {
  run kubectl --kubeconfig="$PO_KUBECONFIG" get tenant phase13-fresh
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "RBAC-05 / D-13-08 (patch): kubectl patch tenant phase13-fresh succeeds" {
  run kubectl --kubeconfig="$PO_KUBECONFIG" patch tenant phase13-fresh \
    --type=merge -p '{"metadata":{"labels":{"karyon.io/phase13-rbac-05":"probed"}}}'
  [ "$status" -eq 0 ]
}

@test "RBAC-05 / D-13-08 (delete): kubectl delete tenant phase13-fresh succeeds" {
  run kubectl --kubeconfig="$PO_KUBECONFIG" delete tenant phase13-fresh --wait=false
  [ "$status" -eq 0 ]
}
