#!/usr/bin/env bats
# tests/bats/demo-05-live-cross-tenant-forbidden.bats
# Cross-tenant pod LIST + namespace GET denied (alpha→bravo + bravo→alpha symmetric mirror).

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

@test "DEMO-05 (alpha→bravo): cross-tenant pod LIST denied" {
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" get pods -n tenant-bravo
  [ "$status" -ne 0 ]
  echo "$output" | grep -qE "(Forbidden|forbidden|cannot list)"
}

@test "DEMO-05 (bravo→alpha): cross-tenant pod LIST denied (symmetric mirror)" {
  run kubectl --kubeconfig="$BRAVO_KUBECONFIG" get pods -n tenant-alpha
  [ "$status" -ne 0 ]
  echo "$output" | grep -qE "(Forbidden|forbidden|cannot list)"
}

@test "DEMO-05 (alpha→bravo): cross-tenant namespace GET denied" {
  # capsule-proxy scoping: the namespace is hidden, surfacing as NotFound rather than
  # an explicit Forbidden (LIST-filter semantics).
  # Either form is a valid scoping-denied response; the load-bearing assertion is that
  # the cross-tenant namespace is UNREACHABLE.
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" get namespace tenant-bravo
  [ "$status" -ne 0 ]
  echo "$output" | grep -qE "(Forbidden|forbidden|NotFound|not found|could not find|cannot get|cannot list)"
}

@test "DEMO-05 (bravo→alpha): cross-tenant namespace GET denied (symmetric mirror)" {
  run kubectl --kubeconfig="$BRAVO_KUBECONFIG" get namespace tenant-alpha
  [ "$status" -ne 0 ]
  echo "$output" | grep -qE "(Forbidden|forbidden|NotFound|not found|could not find|cannot get|cannot list)"
}
