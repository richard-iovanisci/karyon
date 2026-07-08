#!/usr/bin/env bats
# tests/bats/phase5-02-live.bats
# Live state checker for an externally completed rebuild run.

load 'test_helper'

setup() {
  require_live_destructive
  LOG_FILE="/tmp/karyon-rebuild.log"
}

@test "rebuild log exists and contains elapsed seconds" {
  [ -f "$LOG_FILE" ]
  run grep -E '^rebuild elapsed seconds: [0-9]+' "$LOG_FILE"
  [ "$status" -eq 0 ]
}

@test "elapsed seconds <= 1200" {
  [ -f "$LOG_FILE" ]
  elapsed="$(grep -E '^rebuild elapsed seconds: [0-9]+' "$LOG_FILE" | awk '{print $4}' | tail -1)"
  [ -n "$elapsed" ]
  [ "$elapsed" -le 1200 ]
}

@test "strict chain step markers appear in order" {
  [ -f "$LOG_FILE" ]
  previous=0
  for literal in \
    '>>> step preflight' \
    '>>> step destroy' \
    '>>> step create-clusters' \
    '>>> step bootstrap-flux' \
    '>>> step register-spokes' \
    '>>> step deploy-examples' \
    '>>> step health-check'
  do
    line="$(grep -nF -- "$literal" "$LOG_FILE" | head -1 | cut -d: -f1)"
    [ -n "$line" ]
    [ "$line" -gt "$previous" ]
    previous="$line"
  done
}

@test "kubeconfig contexts exist after rebuild" {
  run kubectl config get-contexts -o name
  [ "$status" -eq 0 ]
  [[ "$output" == *"k3d-hub-flux"* ]]
  [[ "$output" == *"k3d-spoke-ml"* ]]
  [[ "$output" == *"k3d-spoke-apps"* ]]
}

@test "podinfo Available=True on spoke-apps" {
  run kubectl --context k3d-spoke-apps -n podinfo get deploy podinfo -o jsonpath='{.status.conditions[?(@.type=="Available")].status}'
  [ "$status" -eq 0 ]
  [ "$output" = "True" ]
}

@test "GPU job logs contain NVIDIA-SMI on spoke-ml" {
  run kubectl --context k3d-spoke-ml -n gpu-smoke logs job/nvidia-smi
  [ "$status" -eq 0 ]
  [[ "$output" == *"NVIDIA-SMI"* ]]
}

@test "state checker source omits destructive invocations" {
  for forbidden in \
    "task re""build" \
    "task de""stroy" \
    "bash scripts/rebuild"".sh" \
    "bash scripts/destroy"".sh" \
    "bash scripts/delete-clusters"".sh" \
    "k3d cluster de""lete"
  do
    run grep -F -- "$forbidden" "$BATS_TEST_FILENAME"
    [ "$status" -ne 0 ]
  done
}
