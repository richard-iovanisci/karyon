#!/usr/bin/env bats
# tests/bats/demo-01-live-platform-owner-list.bats
# Phase 14 / Wave 0 (D-14-08 + D-13-15 Nyquist gate)
# DEMO-01 — platform-owner kubeconfig sees alpha + bravo tenants + tenant-alpha/tenant-bravo namespaces + pods -A across tenants.
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

@test "DEMO-01 (Tier-2 platform-owner): kubectl get tenants returns alpha + bravo" {
  run kubectl --kubeconfig="$PO_KUBECONFIG" get tenants.capsule.clastix.io \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx 'alpha'
  echo "$output" | grep -qx 'bravo'
}

@test "DEMO-01 (Tier-2 platform-owner): kubectl get namespaces sees tenant-alpha + tenant-bravo" {
  run kubectl --kubeconfig="$PO_KUBECONFIG" get namespaces \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx 'tenant-alpha'
  echo "$output" | grep -qx 'tenant-bravo'
}

@test "DEMO-01 (Tier-2 platform-owner): kubectl get pods -A across tenant namespaces succeeds" {
  run kubectl --kubeconfig="$PO_KUBECONFIG" get pods --all-namespaces
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF 'hello-world'
}
