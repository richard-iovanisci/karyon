#!/usr/bin/env bats
# tests/bats/fix-coredns-01-static.bats
# Phase 5 static contract for the hub-only CoreDNS/NodeHosts repair task.

load 'test_helper'

setup() {
  SCRIPT="${REPO_ROOT}/scripts/fix-coredns.sh"
  TASKFILE="${REPO_ROOT}/Taskfile.yml"
}

@test "HEALTH-01: fix-coredns script exists, is strict, and sources preflight helpers" {
  [ -f "$SCRIPT" ]
  run grep -E '^set -euo pipefail' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- 'preflight-lib.sh' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "D-10: fix-coredns stops only hub-flux" {
  [ -f "$SCRIPT" ]
  run grep -F -- 'k3d cluster stop hub-flux' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "D-10: fix-coredns starts only hub-flux" {
  [ -f "$SCRIPT" ]
  run grep -F -- 'k3d cluster start hub-flux' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "HEALTH-01: fix-coredns verifies Flux after hub restart" {
  [ -f "$SCRIPT" ]
  run grep -F -- 'flux --context k3d-hub-flux check' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "MED-2: fix-coredns does not stop spoke-ml" {
  [ -f "$SCRIPT" ]
  run bash -c "grep -v '^[[:space:]]*#' '$SCRIPT' | grep -F -- 'k3d cluster stop spoke-ml'"
  [ "$status" -ne 0 ]
}

@test "MED-2: fix-coredns does not start spoke-ml" {
  [ -f "$SCRIPT" ]
  run bash -c "grep -v '^[[:space:]]*#' '$SCRIPT' | grep -F -- 'k3d cluster start spoke-ml'"
  [ "$status" -ne 0 ]
}

@test "MED-2: fix-coredns does not restart spoke-ml" {
  [ -f "$SCRIPT" ]
  run bash -c "grep -v '^[[:space:]]*#' '$SCRIPT' | grep -F -- 'k3d cluster restart spoke-ml'"
  [ "$status" -ne 0 ]
}

@test "MED-2: fix-coredns does not stop spoke-apps" {
  [ -f "$SCRIPT" ]
  run bash -c "grep -v '^[[:space:]]*#' '$SCRIPT' | grep -F -- 'k3d cluster stop spoke-apps'"
  [ "$status" -ne 0 ]
}

@test "MED-2: fix-coredns does not start spoke-apps" {
  [ -f "$SCRIPT" ]
  run bash -c "grep -v '^[[:space:]]*#' '$SCRIPT' | grep -F -- 'k3d cluster start spoke-apps'"
  [ "$status" -ne 0 ]
}

@test "MED-2: fix-coredns does not restart spoke-apps" {
  [ -f "$SCRIPT" ]
  run bash -c "grep -v '^[[:space:]]*#' '$SCRIPT' | grep -F -- 'k3d cluster restart spoke-apps'"
  [ "$status" -ne 0 ]
}

@test "D-10: fix-coredns does not edit CoreDNS directly" {
  [ -f "$SCRIPT" ]
  run bash -c "grep -v '^[[:space:]]*#' '$SCRIPT' | grep -F -- 'kubectl -n kube-system edit'"
  [ "$status" -ne 0 ]
}

@test "D-10: fix-coredns does not delete CoreDNS pods" {
  [ -f "$SCRIPT" ]
  run bash -c "grep -v '^[[:space:]]*#' '$SCRIPT' | grep -F -- 'kubectl delete pod -n kube-system'"
  [ "$status" -ne 0 ]
}

@test "MED-3: fix-coredns counts Flux deployments before waiting on all controllers" {
  [ -f "$SCRIPT" ]
  run grep -F -- 'get deploy --no-headers' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- 'wc -l' "$SCRIPT"
  [ "$status" -eq 0 ]
  count_line="$(grep -nF -- 'get deploy --no-headers' "$SCRIPT" | head -1 | cut -d: -f1)"
  wait_line="$(grep -nE 'kubectl .*wait .*--for=condition=Available deploy --all' "$SCRIPT" | head -1 | cut -d: -f1)"
  [ -n "$count_line" ]
  [ -n "$wait_line" ]
  [ "$count_line" -lt "$wait_line" ]
}

@test "MED-3: fix-coredns requires at least four Flux controller deployments" {
  [ -f "$SCRIPT" ]
  run bash -c "grep -v '^[[:space:]]*#' '$SCRIPT' | grep -E -- '(-ge|-eq)[[:space:]]+4|4[[:space:]]+-(ge|eq)'"
  [ "$status" -eq 0 ]
}

@test "HEALTH-07: fix-coredns proves spoke DNS and fails if probes still fail" {
  [ -f "$SCRIPT" ]
  run grep -F -- 'getent hosts "k3d-${spoke}-server-0"' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- 'dns_ok=1' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- 'dns_ok=0' "$SCRIPT"
  [ "$status" -eq 0 ]
  run bash -c "grep -A 12 'Post-restart spoke DNS probe' '$SCRIPT' | grep -F -- 'fail \"spoke DNS still failing'"
  [ "$status" -eq 0 ]
}

@test "REPO-05: Taskfile wires fix-dns to fix-coredns script" {
  [ -f "$TASKFILE" ]
  run grep -F -- 'fix-dns:' "$TASKFILE"
  [ "$status" -eq 0 ]
  run grep -F -- 'bash scripts/fix-coredns.sh' "$TASKFILE"
  [ "$status" -eq 0 ]
}
