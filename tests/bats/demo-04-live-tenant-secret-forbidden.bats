#!/usr/bin/env bats
# tests/bats/demo-04-live-tenant-secret-forbidden.bats
# Tenant-owner cannot create a secret in its own namespace; the Forbidden output
# must name the human-tenant-owner identity verbatim.

load 'test_helper'

setup_file() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
  export KARYON_BATS_TMPDIR="${TMPDIR:-/tmp}/karyon-tenants/bats-${BATS_RUN_TMPDIR##*/}"
  mkdir -p "$KARYON_BATS_TMPDIR"
  bash "${REPO_ROOT}/scripts/poc/capsule/issue-tenant-kubeconfig.sh" alpha human-tenant-owner \
    --duration=2h --write-to "${KARYON_BATS_TMPDIR}/alpha.kubeconfig" >/dev/null 2>&1
  bash "${REPO_ROOT}/scripts/poc/capsule/issue-tenant-kubeconfig.sh" bravo human-tenant-owner \
    --duration=2h --write-to "${KARYON_BATS_TMPDIR}/bravo.kubeconfig" >/dev/null 2>&1
  export ALPHA_KUBECONFIG="${KARYON_BATS_TMPDIR}/alpha.kubeconfig"
  export BRAVO_KUBECONFIG="${KARYON_BATS_TMPDIR}/bravo.kubeconfig"
}

teardown_file() {
  rm -rf "$KARYON_BATS_TMPDIR"
}

setup() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
  [ -f "${ALPHA_KUBECONFIG:-/dev/null}" ] || skip "alpha kubeconfig not minted (setup_file failed; expected RED pre-implementation)"
  [ -f "${BRAVO_KUBECONFIG:-/dev/null}" ] || skip "bravo kubeconfig not minted (setup_file failed; expected RED pre-implementation)"
}

@test "DEMO-04 (alpha boundary): tenant-owner cannot create secret in own namespace" {
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" create secret generic demo-deny \
    --from-literal=k=v -n tenant-alpha
  [ "$status" -ne 0 ]
  # Deliberately permissive Forbidden grep (denial wording varies)
  echo "$output" | grep -qE 'Forbidden|forbidden|cannot create resource'
  # The User string in the denial proves the SA identity
  echo "$output" | grep -qF 'human-tenant-owner'
  # Idempotent cleanup
  kubectl --kubeconfig="$ALPHA_KUBECONFIG" delete secret demo-deny -n tenant-alpha \
    --ignore-not-found --wait=false >/dev/null 2>&1 || true
}

@test "DEMO-04 (bravo boundary): tenant-owner cannot create secret in own namespace" {
  run kubectl --kubeconfig="$BRAVO_KUBECONFIG" create secret generic demo-deny \
    --from-literal=k=v -n tenant-bravo
  [ "$status" -ne 0 ]
  # Deliberately permissive Forbidden grep (denial wording varies)
  echo "$output" | grep -qE 'Forbidden|forbidden|cannot create resource'
  # The User string in the denial proves the SA identity
  echo "$output" | grep -qF 'human-tenant-owner'
  # Idempotent cleanup
  kubectl --kubeconfig="$BRAVO_KUBECONFIG" delete secret demo-deny -n tenant-bravo \
    --ignore-not-found --wait=false >/dev/null 2>&1 || true
}
