#!/usr/bin/env bats
# tests/bats/seed-03-live-fresh-tenant.bats
# Phase 13 / Wave 0 (D-13-15 Nyquist gate)
# SEED-02 — fresh-tenant propagation <=60s falsifier.
# Uses new-tenant.sh phase13-fresh to create a brand-new Tenant + Namespace; asserts
# hello-world Pod Ready=True within 60s of namespace creation (the SEED-02 SLO).
# RED until Plans 13-02 (new-tenant.sh + platform-owner kubeconfig) + 13-03 (GTR) land.

load 'test_helper'

setup_file() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
  export KARYON_BATS_TMPDIR="${TMPDIR:-/tmp}/karyon-tenants/bats-${BATS_RUN_TMPDIR##*/}"
  mkdir -p "$KARYON_BATS_TMPDIR"
  # Mint platform-owner kubeconfig (RED if script not yet present)
  bash "${REPO_ROOT}/scripts/poc/capsule/issue-platform-owner-kubeconfig.sh" \
    --duration=2h --write-to "${KARYON_BATS_TMPDIR}/po.kubeconfig" >/dev/null 2>&1
  export PO_KUBECONFIG="${KARYON_BATS_TMPDIR}/po.kubeconfig"
  # Idempotent precondition: ensure phase13-fresh does not pre-exist
  kubectl --context=k3d-spoke-capsule delete tenant phase13-fresh \
    --ignore-not-found --wait=false >/dev/null 2>&1 || true
  kubectl --context=k3d-spoke-capsule wait --for=delete namespace tenant-phase13-fresh \
    --timeout=30s >/dev/null 2>&1 || true

  # Provision the fresh tenant; this is the falsifier seed (RED if script absent)
  if [ -f "${PO_KUBECONFIG}" ] && [ -x "${REPO_ROOT}/scripts/poc/capsule/new-tenant.sh" ]; then
    bash "${REPO_ROOT}/scripts/poc/capsule/new-tenant.sh" phase13-fresh \
      --kubeconfig="$PO_KUBECONFIG" >/dev/null 2>&1 || true
    # Pitfall 13-P2: wait for Tenant.Status.Namespaces to be non-empty before asserting
    # propagation (controller hasn't materialized child ns yet)
    for i in 1 2 3 4 5 6; do
      local sz
      sz=$(kubectl --context=k3d-spoke-capsule get tenant phase13-fresh \
        -o jsonpath='{.status.namespaces}' 2>/dev/null || true)
      [ -n "$sz" ] && [ "$sz" != "[]" ] && break
      sleep 5
    done
  fi
}

teardown_file() {
  # Idempotent cleanup — best-effort
  if [ -f "${PO_KUBECONFIG:-/dev/null}" ]; then
    kubectl --kubeconfig="$PO_KUBECONFIG" delete tenant phase13-fresh \
      --ignore-not-found --wait=false >/dev/null 2>&1 || true
  fi
  kubectl --context=k3d-spoke-capsule delete tenant phase13-fresh \
    --ignore-not-found --wait=false >/dev/null 2>&1 || true
  # Pitfall 13-P6: pruningOnDelete unmaterialization wait
  kubectl --context=k3d-spoke-capsule wait --for=delete namespace tenant-phase13-fresh \
    --timeout=30s >/dev/null 2>&1 || true
  rm -rf "$KARYON_BATS_TMPDIR"
}

setup() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
}

@test "SEED-02 / D-13-08 + D-13-11 (fresh tenant): hello-world Pod Ready in tenant-phase13-fresh within 60s" {
  run kubectl --context=k3d-spoke-capsule wait pod/hello-world \
    --for=condition=Ready -n tenant-phase13-fresh --timeout=60s
  [ "$status" -eq 0 ]
}
