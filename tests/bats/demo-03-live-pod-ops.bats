#!/usr/bin/env bats
# tests/bats/demo-03-live-pod-ops.bats
# Positive control: tenant-owner + platform-owner exec/logs against the seeded hello-world workload (alpha + bravo symmetric mirror).
# AMENDED (ADR 0008 addendum 2026-07-06): GTR seeds a Deployment now, so exec/logs
# target deploy/hello-world (kubectl resolves to a ready child pod) instead of a
# fixed pod name — Deployment pods carry a -<hash> suffix.

load 'test_helper'

setup_file() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
  export KARYON_BATS_TMPDIR="${TMPDIR:-/tmp}/karyon-tenants/bats-${BATS_RUN_TMPDIR##*/}"
  mkdir -p "$KARYON_BATS_TMPDIR"
  bash "${REPO_ROOT}/scripts/poc/capsule/issue-platform-owner-kubeconfig.sh" \
    --duration=2h --write-to "${KARYON_BATS_TMPDIR}/po.kubeconfig" >/dev/null 2>&1
  bash "${REPO_ROOT}/scripts/poc/capsule/issue-tenant-kubeconfig.sh" alpha human-tenant-owner \
    --duration=2h --write-to "${KARYON_BATS_TMPDIR}/alpha.kubeconfig" >/dev/null 2>&1
  bash "${REPO_ROOT}/scripts/poc/capsule/issue-tenant-kubeconfig.sh" bravo human-tenant-owner \
    --duration=2h --write-to "${KARYON_BATS_TMPDIR}/bravo.kubeconfig" >/dev/null 2>&1
  export PO_KUBECONFIG="${KARYON_BATS_TMPDIR}/po.kubeconfig"
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
  [ -f "${PO_KUBECONFIG:-/dev/null}" ] || skip "platform-owner kubeconfig not minted (setup_file failed; expected RED pre-implementation)"
  [ -f "${ALPHA_KUBECONFIG:-/dev/null}" ] || skip "alpha kubeconfig not minted (setup_file failed; expected RED pre-implementation)"
  [ -f "${BRAVO_KUBECONFIG:-/dev/null}" ] || skip "bravo kubeconfig not minted (setup_file failed; expected RED pre-implementation)"
}

@test "DEMO-03 (tenant-owner alpha exec): kubectl exec deploy/hello-world -- sh -c 'echo ok-from-shell'" {
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" -n tenant-alpha exec deploy/hello-world \
    -- sh -c "echo ok-from-shell"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "ok-from-shell"
}

@test "DEMO-03 (tenant-owner bravo exec): kubectl exec deploy/hello-world -- sh -c 'echo ok-from-shell'" {
  run kubectl --kubeconfig="$BRAVO_KUBECONFIG" -n tenant-bravo exec deploy/hello-world \
    -- sh -c "echo ok-from-shell"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "ok-from-shell"
}

@test "DEMO-03 (tenant-owner alpha logs): kubectl logs deploy/hello-world --tail=3 contains 'worker process'" {
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" -n tenant-alpha logs deploy/hello-world --tail=3
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "worker process"
}

@test "DEMO-03 (tenant-owner bravo logs): kubectl logs deploy/hello-world --tail=3 contains 'worker process'" {
  run kubectl --kubeconfig="$BRAVO_KUBECONFIG" -n tenant-bravo logs deploy/hello-world --tail=3
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "worker process"
}

@test "DEMO-03 (platform-owner cross-tenant exec into tenant-alpha): succeeds (RBAC-06 co-owner)" {
  run kubectl --kubeconfig="$PO_KUBECONFIG" -n tenant-alpha exec deploy/hello-world \
    -- sh -c "echo ok-from-shell"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "ok-from-shell"
}

@test "DEMO-03 (platform-owner cross-tenant logs against tenant-bravo): succeeds" {
  run kubectl --kubeconfig="$PO_KUBECONFIG" -n tenant-bravo logs deploy/hello-world --tail=3
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "worker process"
}
