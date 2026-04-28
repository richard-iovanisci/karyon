#!/usr/bin/env bats
# tests/bats/deploy-examples-01-static.bats
# Phase 5 Wave 0 static contract for GitOps-only example workload deployment.

load 'test_helper'

setup() {
  SCRIPT="${REPO_ROOT}/scripts/deploy-examples.sh"
  SPOKE_APPS_KUST="${REPO_ROOT}/clusters/spoke-apps/kustomization.yaml"
  SPOKE_ML_KUST="${REPO_ROOT}/clusters/spoke-ml/kustomization.yaml"
  PODINFO_DIR="${REPO_ROOT}/examples/podinfo"
  GPU_SMOKE_DIR="${REPO_ROOT}/examples/gpu-smoke-test"
  TASKFILE="${REPO_ROOT}/Taskfile.yml"
}

@test "DEP-01: podinfo example manifests exist" {
  [ -f "${PODINFO_DIR}/kustomization.yaml" ]
  [ -f "${PODINFO_DIR}/namespace.yaml" ]
  [ -f "${PODINFO_DIR}/deployment.yaml" ]
  [ -f "${PODINFO_DIR}/service.yaml" ]
}

@test "DEP-02: GPU smoke example manifests exist" {
  [ -f "${GPU_SMOKE_DIR}/kustomization.yaml" ]
  [ -f "${GPU_SMOKE_DIR}/namespace.yaml" ]
  [ -f "${GPU_SMOKE_DIR}/job.yaml" ]
}

@test "DEP-01: podinfo image is pinned" {
  [ -f "${PODINFO_DIR}/deployment.yaml" ]
  run grep -F -- 'ghcr.io/stefanprodan/podinfo:6.7.1' "${PODINFO_DIR}/deployment.yaml"
  [ "$status" -eq 0 ]
}

@test "DEP-02: GPU smoke image is pinned" {
  [ -f "${GPU_SMOKE_DIR}/job.yaml" ]
  run grep -F -- 'nvcr.io/nvidia/cuda:12.8.0-base-ubuntu22.04' "${GPU_SMOKE_DIR}/job.yaml"
  [ "$status" -eq 0 ]
}

@test "DEP-03: spoke-apps references the canonical podinfo example" {
  [ -f "$SPOKE_APPS_KUST" ]
  run grep -F -- '../../examples/podinfo' "$SPOKE_APPS_KUST"
  [ "$status" -eq 0 ]
}

@test "DEP-03: spoke-ml references the canonical GPU smoke example" {
  [ -f "$SPOKE_ML_KUST" ]
  run grep -F -- '../../examples/gpu-smoke-test' "$SPOKE_ML_KUST"
  [ "$status" -eq 0 ]
}

@test "DEP-04: deploy-examples script exists, is strict, and sources preflight helpers" {
  [ -f "$SCRIPT" ]
  run grep -E '^set -euo pipefail' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- 'scripts/lib/preflight-lib.sh' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "D-02/D-03: deploy-examples reconciles hub source and both spoke Kustomizations" {
  [ -f "$SCRIPT" ]
  run grep -F -- 'flux --context k3d-hub-flux reconcile source git flux-system --with-source' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- 'flux --context k3d-hub-flux reconcile kustomization spoke-apps --with-source' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- 'flux --context k3d-hub-flux reconcile kustomization spoke-ml --with-source' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "D-08: deploy-examples only deletes the stable GPU smoke Job for a fresh run" {
  [ -f "$SCRIPT" ]
  run grep -F -- 'kubectl --context k3d-spoke-ml -n gpu-smoke delete job nvidia-smi --ignore-not-found' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "D-08: deploy-examples fails if the old GPU smoke Job cannot be deleted" {
  [ -f "$SCRIPT" ]
  run grep -F -- 'get namespace gpu-smoke' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- '--ignore-not-found -o name' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- 'failed to check gpu-smoke namespace before rerun' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- 'failed to delete old gpu-smoke/nvidia-smi Job before rerun' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- 'resolve the Kubernetes delete error' "$SCRIPT"
  [ "$status" -eq 0 ]
  run bash -c "grep -v '^[[:space:]]*#' '$SCRIPT' | grep -F -- 'delete job nvidia-smi' | grep -F -- '|| true'"
  [ "$status" -ne 0 ]
}

@test "D-02: deploy-examples does not directly apply workloads to spokes" {
  [ -f "$SCRIPT" ]
  run bash -c "grep -v '^[[:space:]]*#' '$SCRIPT' | grep -F -- 'kubectl --context k3d-spoke-apps apply'"
  [ "$status" -ne 0 ]
  run bash -c "grep -v '^[[:space:]]*#' '$SCRIPT' | grep -F -- 'kubectl --context k3d-spoke-ml apply'"
  [ "$status" -ne 0 ]
}

@test "DEP-01/DEP-02: deploy-examples uses bounded waits for podinfo and GPU smoke" {
  [ -f "$SCRIPT" ]
  run grep -F -- '--for=condition=Available deployment/podinfo' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- '--timeout=180s' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- '--for=condition=Complete job/nvidia-smi' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- '--timeout=300s' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "D-02: source Git reconcile happens before spoke-ml Kustomization reconcile" {
  [ -f "$SCRIPT" ]
  source_line="$(grep -nF -- 'flux --context k3d-hub-flux reconcile source git flux-system --with-source' "$SCRIPT" | head -1 | cut -d: -f1)"
  spoke_ml_line="$(grep -nF -- 'flux --context k3d-hub-flux reconcile kustomization spoke-ml --with-source' "$SCRIPT" | head -1 | cut -d: -f1)"
  [ -n "$source_line" ]
  [ -n "$spoke_ml_line" ]
  [ "$source_line" -lt "$spoke_ml_line" ]
}

@test "HIGH-3: deploy-examples checks working-tree dirtiness before Flux reconcile" {
  [ -f "$SCRIPT" ]
  run grep -F -- 'git status --short' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "HIGH-3: deploy-examples compares local HEAD with origin/main before Flux reconcile" {
  [ -f "$SCRIPT" ]
  run grep -F -- 'git rev-parse HEAD' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- 'git rev-parse origin/main' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "HIGH-3: Git visibility failure text includes exact remediation commands" {
  [ -f "$SCRIPT" ]
  run grep -F -- 'git status' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- 'git push' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "HIGH-3: Git visibility gate appears before first Flux reconcile" {
  [ -f "$SCRIPT" ]
  gate_line="$(grep -nF -- 'git status --short' "$SCRIPT" | head -1 | cut -d: -f1)"
  flux_line="$(grep -nF -- 'flux --context k3d-hub-flux reconcile' "$SCRIPT" | head -1 | cut -d: -f1)"
  [ -n "$gate_line" ]
  [ -n "$flux_line" ]
  [ "$gate_line" -lt "$flux_line" ]
}

@test "REPO-05: Taskfile wires deploy-examples to the script" {
  [ -f "$TASKFILE" ]
  run grep -F -- 'deploy-examples:' "$TASKFILE"
  [ "$status" -eq 0 ]
  run grep -F -- 'bash scripts/deploy-examples.sh' "$TASKFILE"
  [ "$status" -eq 0 ]
}
