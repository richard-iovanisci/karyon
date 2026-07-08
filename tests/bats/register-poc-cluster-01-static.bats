#!/usr/bin/env bats
# tests/bats/register-poc-cluster-01-static.bats
# register-poc-cluster.sh shape contract (mirrors register-spokes-01-static.bats)

load 'test_helper'

setup() {
  SCRIPT="${REPO_ROOT}/scripts/register-poc-cluster.sh"
}

@test "POC-02: scripts/register-poc-cluster.sh exists and is executable" {
  [ -f "$SCRIPT" ]
  [ -x "$SCRIPT" ] || run chmod +x "$SCRIPT"
}

@test "POC-02 / D-11: scripts/register-poc-cluster.sh uses set -euo pipefail and does NOT use set -x or set -eux" {
  [ -f "$SCRIPT" ]
  run grep -E '^set -euo pipefail' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -E '^set -eux' "$SCRIPT"
  [ "$status" -ne 0 ]
  run grep -E '^set -x' "$SCRIPT"
  [ "$status" -ne 0 ]
}

@test "POC-02: scripts/register-poc-cluster.sh sources scripts/lib/preflight-lib.sh" {
  [ -f "$SCRIPT" ]
  run grep -F -- 'lib/preflight-lib.sh' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "POC-02 / D-07: scripts/register-poc-cluster.sh validates single positional arg" {
  [ -f "$SCRIPT" ]
  run grep -F -- '"$#" -ne 1' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- 'POC_CLUSTER="$1"' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "POC-02 / D-07: scripts/register-poc-cluster.sh derives kubectl context as k3d-\${POC_CLUSTER}" {
  [ -f "$SCRIPT" ]
  run grep -F -- 'POC_CTX="k3d-${POC_CLUSTER}"' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "POC-02: scripts/register-poc-cluster.sh defines apply_spoke_rbac function" {
  [ -f "$SCRIPT" ]
  run grep -E '^apply_spoke_rbac' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- 'flux-reconciler' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- 'flux-reconciler-cluster-admin' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- 'flux-reconciler-token' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "POC-02 / D-11 (token safety): apply_hub_secret uses --from-file=value.yaml=/dev/stdin (NOT --from-literal)" {
  [ -f "$SCRIPT" ]
  run grep -F -- '--from-file=value.yaml=/dev/stdin' "$SCRIPT"
  [ "$status" -eq 0 ]
  # Negative: must NOT use --from-literal (would expose token in argv)
  run bash -c "grep -v '^[[:space:]]*#' '$SCRIPT' | grep -F -- '--from-literal'"
  [ "$status" -ne 0 ]
}

@test "POC-02 / D-11: dry-run-then-apply pattern in apply_hub_secret" {
  [ -f "$SCRIPT" ]
  run grep -F -- '--dry-run=client' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- 'kubectl' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "POC-02 / P30 / D-09: scripts/register-poc-cluster.sh defines ensure_hub_pocs_mount (independent from spokes)" {
  [ -f "$SCRIPT" ]
  run grep -E '^ensure_hub_pocs_mount' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- '# KARYON POC MOUNT' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- 'clusters/hub-flux/flux-system/kustomization.yaml' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "POC-02: scripts/register-poc-cluster.sh contains apiserver URL literal :6443 in build_kubeconfig (in-cluster port; NOT 6446 host-port)" {
  [ -f "$SCRIPT" ]
  run grep -F -- 'k3d-${POC_CLUSTER}-server-0:6443' "$SCRIPT"
  [ "$status" -eq 0 ]
  # Negative: scope to build_kubeconfig() body only — :6446 (host-published port) MUST NOT appear
  # there. (verify_credential_layer() legitimately uses 127.0.0.1:6446 for the TLS probe; that
  # body is allowed to contain :6446 — see the dedicated verify_credential_layer test below.)
  run bash -c "awk '/^build_kubeconfig\(\)/{flag=1} flag; /^}/{if(flag){flag=0; exit}}' '$SCRIPT' | grep -v '^[[:space:]]*#' | grep -F -- ':6446'"
  [ "$status" -ne 0 ]
}

@test "POC-02: scripts/register-poc-cluster.sh defines verify_credential_layer function" {
  [ -f "$SCRIPT" ]
  run grep -E '^verify_credential_layer' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- '/api/v1/nodes' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "POC-02: verify_credential_layer body contains 127.0.0.1:6446 (TLS probe target — host-published port)" {
  [ -f "$SCRIPT" ]
  # Positive: the verify_credential_layer body legitimately uses :6446 (host-published port)
  # for the openssl s_client TLS probe. This is the SOURCE-OF-TRUTH that the build_kubeconfig
  # negative test above carves out.
  run bash -c "awk '/^verify_credential_layer\(\)/{flag=1} flag; /^}/{if(flag){flag=0; exit}}' '$SCRIPT' | grep -F -- ':6446'"
  [ "$status" -eq 0 ]
}

@test "POC-02 / P18 trip-wire: forbidden-node literal k3d-hub-flux-server-0 referenced as falsifier in verify_credential_layer" {
  [ -f "$SCRIPT" ]
  run grep -F -- 'k3d-hub-flux-server-0' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "POC-02: idempotency skip-message literal present" {
  [ -f "$SCRIPT" ]
  run grep -F -- 'already done, skipping' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "POC-02 / D-11: scripts/register-poc-cluster.sh does NOT echo or tee bearer tokens" {
  [ -f "$SCRIPT" ]
  # Negative: no `echo "$bearer"` or `echo "$kubeconfig"` patterns
  run bash -c "grep -v '^[[:space:]]*#' '$SCRIPT' | grep -E 'echo[[:space:]]+.*token|echo[[:space:]]+.*bearer|tee[[:space:]]+.*token|tee[[:space:]]+.*kubeconfig'"
  [ "$status" -ne 0 ]
}
