#!/usr/bin/env bats
# tests/bats/seed-03-live-fresh-tenant.bats
# Fresh-tenant propagation <=60s falsifier.
# Uses new-tenant.sh phase13-fresh to create a brand-new Tenant + Namespace; asserts
# hello-world Deployment Available within 60s of namespace creation (the propagation
# SLO; shape amended from bare Pod by the ADR 0008 addendum 2026-07-06).

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
    # Wait for Tenant.Status.Namespaces to be non-empty before asserting
    # propagation (the controller may not have materialized the child ns yet)
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
  # pruningOnDelete unmaterialization wait — the namespace lingers briefly after tenant delete
  kubectl --context=k3d-spoke-capsule wait --for=delete namespace tenant-phase13-fresh \
    --timeout=30s >/dev/null 2>&1 || true
  rm -rf "$KARYON_BATS_TMPDIR"
}

setup() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
}

# AMENDED (ADR 0008 addendum 2026-07-06): GTR seeds a Deployment now; the ≤60s
# SLO is asserted as Deployment Available (equivalent readiness signal, and the
# fresh-tenant path still rides the Tenant-CREATE watch event).
# Explicit poll instead of `kubectl wait` because the Deployment may not exist
# yet when the test starts (wait on a missing named resource errors immediately).
@test "SEED-02 / D-13-08 + D-13-11 (fresh tenant): hello-world Deployment Available in tenant-phase13-fresh within 60s" {
  local i cond
  for i in $(seq 1 12); do
    cond=$(kubectl --context=k3d-spoke-capsule -n tenant-phase13-fresh get deployment hello-world \
      -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || true)
    [[ "$cond" == "True" ]] && return 0
    sleep 5
  done
  echo "hello-world Deployment never reached Available in tenant-phase13-fresh (last: '${cond}')"
  return 1
}
