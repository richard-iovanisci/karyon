#!/usr/bin/env bats
# tests/bats/deploy-examples-02-kustomize-build.bats
# Build-time proof that spoke trees can load ../../examples/* with kubectl kustomize.

load 'test_helper'

setup() {
  SPOKE_APPS_KUST="${REPO_ROOT}/clusters/spoke-apps/kustomization.yaml"
  SPOKE_ML_KUST="${REPO_ROOT}/clusters/spoke-ml/kustomization.yaml"
  PODINFO_KUST="${REPO_ROOT}/examples/podinfo/kustomization.yaml"
  GPU_SMOKE_KUST="${REPO_ROOT}/examples/gpu-smoke-test/kustomization.yaml"

  if [[ ! -f "$SPOKE_APPS_KUST" || ! -f "$SPOKE_ML_KUST" || ! -f "$PODINFO_KUST" || ! -f "$GPU_SMOKE_KUST" ]]; then
    skip "manifests not landed yet; run after Plan 05-02 Task 2"
  fi
}

@test "spoke-apps kustomize build succeeds" {
  run kubectl kustomize "${REPO_ROOT}/clusters/spoke-apps"
  [ "$status" -eq 0 ]
  [[ "$output" == *"kind: Deployment"* ]]
  [[ "$output" == *"name: podinfo"* ]]
}

@test "spoke-ml kustomize build succeeds" {
  run kubectl kustomize "${REPO_ROOT}/clusters/spoke-ml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"kind: Job"* ]]
  [[ "$output" == *"name: nvidia-smi"* ]]
}
