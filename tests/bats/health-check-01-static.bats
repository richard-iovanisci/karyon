#!/usr/bin/env bats
# tests/bats/health-check-01-static.bats
# Phase 5 static contract for the read-only health-check task.

load 'test_helper'

setup() {
  SCRIPT="${REPO_ROOT}/scripts/health-check.sh"
  TASKFILE="${REPO_ROOT}/Taskfile.yml"
}

@test "HEALTH-02: health-check script exists, is strict, and sources preflight helpers" {
  [ -f "$SCRIPT" ]
  run grep -E '^set -euo pipefail' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- 'preflight-lib.sh' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "HEALTH-02..07: health-check sections appear in required order" {
  [ -f "$SCRIPT" ]
  previous=0
  for literal in \
    'Clusters and nodes' \
    'Flux controllers' \
    'Spoke Kustomizations' \
    'Hub DNS probe' \
    'GPU capacity' \
    'TLS SANs' \
    'Workload proofs'
  do
    line="$(grep -nF -- "$literal" "$SCRIPT" | head -1 | cut -d: -f1)"
    [ -n "$line" ]
    [ "$line" -gt "$previous" ]
    previous="$line"
  done
}

@test "HEALTH-02: health-check gives cluster Ready waits a 180s timeout" {
  [ -f "$SCRIPT" ]
  run grep -F -- '--timeout=180s' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "HEALTH-04: stale DNS failure path points to task fix-dns" {
  [ -f "$SCRIPT" ]
  run grep -F -- 'task fix-dns' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "HEALTH-05/HEALTH-07: health-check verifies GPU capacity and GPU smoke logs" {
  [ -f "$SCRIPT" ]
  run grep -F -- 'nvidia.com/gpu' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- 'logs job/nvidia-smi' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "HIGH-2: hub DNS probe uses source-controller exec for spoke-ml" {
  [ -f "$SCRIPT" ]
  run grep -F -- 'kubectl --context k3d-hub-flux -n flux-system exec deploy/source-controller -- getent hosts k3d-spoke-ml-server-0' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "HIGH-2: hub DNS probe uses source-controller exec for spoke-apps" {
  [ -f "$SCRIPT" ]
  run grep -F -- 'kubectl --context k3d-hub-flux -n flux-system exec deploy/source-controller -- getent hosts k3d-spoke-apps-server-0' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "MED-3: health-check counts Flux deployments before waiting on all controllers" {
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

@test "MED-3: health-check requires at least four Flux controller deployments" {
  [ -f "$SCRIPT" ]
  run bash -c "grep -v '^[[:space:]]*#' '$SCRIPT' | grep -E -- '(-ge|-eq)[[:space:]]+4|4[[:space:]]+-(ge|eq)'"
  [ "$status" -eq 0 ]
}

@test "D-09: health-check does not stop clusters" {
  [ -f "$SCRIPT" ]
  run bash -c "grep -v '^[[:space:]]*#' '$SCRIPT' | grep -F -- 'k3d cluster stop'"
  [ "$status" -ne 0 ]
}

@test "D-09: health-check does not start clusters" {
  [ -f "$SCRIPT" ]
  run bash -c "grep -v '^[[:space:]]*#' '$SCRIPT' | grep -F -- 'k3d cluster start'"
  [ "$status" -ne 0 ]
}

@test "D-09: health-check does not delete resources" {
  [ -f "$SCRIPT" ]
  run bash -c "grep -v '^[[:space:]]*#' '$SCRIPT' | grep -F -- 'kubectl delete'"
  [ "$status" -ne 0 ]
}

@test "D-09: health-check does not apply resources" {
  [ -f "$SCRIPT" ]
  run bash -c "grep -v '^[[:space:]]*#' '$SCRIPT' | grep -F -- 'kubectl apply'"
  [ "$status" -ne 0 ]
}

@test "HIGH-2: health-check does not create temporary probe pods" {
  [ -f "$SCRIPT" ]
  run bash -c "grep -v '^[[:space:]]*#' '$SCRIPT' | grep -F -- 'kubectl run'"
  [ "$status" -ne 0 ]
}

@test "REPO-05: Taskfile wires health-check to the script" {
  [ -f "$TASKFILE" ]
  run grep -F -- 'health-check:' "$TASKFILE"
  [ "$status" -eq 0 ]
  run grep -F -- 'bash scripts/health-check.sh' "$TASKFILE"
  [ "$status" -eq 0 ]
}
