#!/usr/bin/env bats
# tests/bats/negative-rbac-01-cross-tenant-list.bats
# Cross-tenant list/secret denial probes.
# Real-CRUD probe shape -- NOT kubectl auth can-i (the SAR cache's 5min/30s TTLs
# return stale results and flake).
# Mint-once kubeconfig via setup_file -- TmpDir-rooted, so no tenant kubeconfig
# ever lands in the working tree.
# Strict-mode env var: KARYON_PHASE11_STRICT_LIVE=1 converts skips to FAIL for
# gate-deciding runs.

load 'test_helper'

# Skip vs FAIL based on the strict-mode env var
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
      echo "STRICT_LIVE: k3d-spoke-capsule cluster not reachable; skipping live bats" >&2
      return 1
    else
      skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
    fi
  fi
  export KARYON_BATS_TMPDIR="${TMPDIR:-/tmp}/karyon-tenants/bats-${BATS_RUN_TMPDIR##*/}"
  mkdir -p "$KARYON_BATS_TMPDIR"
  bash "${REPO_ROOT}/scripts/poc/capsule/issue-tenant-kubeconfig.sh" alpha gitops-reconciler \
    --duration=2h --write-to "${KARYON_BATS_TMPDIR}/alpha.kubeconfig" >/dev/null 2>&1
  bash "${REPO_ROOT}/scripts/poc/capsule/issue-tenant-kubeconfig.sh" bravo gitops-reconciler \
    --duration=2h --write-to "${KARYON_BATS_TMPDIR}/bravo.kubeconfig" >/dev/null 2>&1
  export ALPHA_KUBECONFIG="${KARYON_BATS_TMPDIR}/alpha.kubeconfig"
  export BRAVO_KUBECONFIG="${KARYON_BATS_TMPDIR}/bravo.kubeconfig"
}

teardown_file() {
  rm -rf "$KARYON_BATS_TMPDIR"
}

setup() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    _strict_skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
}

@test "N1 -- cross-tenant pod LIST denied (alpha kubeconfig probing tenant-bravo)" {
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" get pods -n tenant-bravo
  [ "$status" -ne 0 ]
  echo "$output" | grep -qE "(Forbidden|forbidden|cannot list)"
}

@test "N2 -- cluster-wide LIST filtered to alpha-owned namespaces (proxy LIST filter)" {
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" get pods --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{"\n"}{end}'
  [ "$status" -eq 0 ]
  # Every returned namespace must start with alpha- or be tenant-alpha; no cross-tenant leakage.
  while IFS= read -r ns; do
    [[ -z "$ns" ]] && continue
    [[ "$ns" =~ ^(tenant-alpha|alpha-) ]] || { echo "leaked namespace: $ns"; return 1; }
  done <<< "$(echo "$output" | sort -u)"
}

@test "N3 -- cross-tenant secret read denied (alpha kubeconfig probing tenant-bravo secrets)" {
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" get secret -n tenant-bravo
  [ "$status" -ne 0 ]
  echo "$output" | grep -qE "(Forbidden|forbidden|cannot list)"
}
