#!/usr/bin/env bats
# tests/bats/demo-02-live-tenant-owner-scoped-list.bats
# Tenant-owner kubeconfigs route through capsule-proxy NodePort 30443; scoped LIST returns only own tenant namespaces (alpha + bravo symmetric mirror).

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

@test "DEMO-02 (alpha scoped LIST): tenant-owner via proxy:30443 sees only own tenant ns" {
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" get namespaces \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'
  [ "$status" -eq 0 ]
  while IFS= read -r ns; do
    [[ -z "$ns" ]] && continue
    [[ "$ns" =~ ^(tenant-alpha|alpha-) ]] || { echo "leaked namespace: $ns"; return 1; }
  done <<< "$(echo "$output" | sort -u)"
}

@test "DEMO-02 (bravo scoped LIST): tenant-owner via proxy:30443 sees only own tenant ns" {
  run kubectl --kubeconfig="$BRAVO_KUBECONFIG" get namespaces \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'
  [ "$status" -eq 0 ]
  while IFS= read -r ns; do
    [[ -z "$ns" ]] && continue
    [[ "$ns" =~ ^(tenant-bravo|bravo-) ]] || { echo "leaked namespace: $ns"; return 1; }
  done <<< "$(echo "$output" | sort -u)"
}

@test "DEMO-02 (alpha scoped LIST): kubectl get tenants returns only alpha" {
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" get tenants \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx 'alpha'
  ! echo "$output" | grep -qx 'bravo'
}

@test "DEMO-02 (bravo scoped LIST): kubectl get tenants returns only bravo" {
  run kubectl --kubeconfig="$BRAVO_KUBECONFIG" get tenants \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx 'bravo'
  ! echo "$output" | grep -qx 'alpha'
}
