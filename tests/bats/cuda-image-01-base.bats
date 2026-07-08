#!/usr/bin/env bats
# tests/bats/cuda-image-01-base.bats
# Asserts images/Dockerfile.k3s-cuda uses FROM nvidia/cuda:12.8.1-base-ubuntu22.04 and the k3s build stage is FROM rancher/k3s.

load 'test_helper'

setup() {
  DOCKERFILE="${IMAGES_DIR}/Dockerfile.k3s-cuda"
}

teardown() {
  :
}

@test "IMG-01: Dockerfile.k3s-cuda uses nvidia/cuda base + rancher/k3s build stage" {
  run grep -E '^FROM nvidia/cuda:\$\{CUDA_TAG\}' "$DOCKERFILE"
  [ "$status" -eq 0 ]
  run grep -E '^FROM rancher/k3s:\$\{K3S_TAG\} AS k3s' "$DOCKERFILE"
  [ "$status" -eq 0 ]
}
