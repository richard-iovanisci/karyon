#!/usr/bin/env bats
# tests/bats/cuda-image-01-base.bats
# Asserts images/Dockerfile.k3s-cuda uses FROM nvidia/cuda:12.8.1-base-ubuntu22.04 (IMG-01) and the k3s build stage is FROM rancher/k3s.
# Wave 0 stub — body filled by Plan 02-02 (or 02-03 for the manifest tests).

load 'test_helper'

setup() {
  DOCKERFILE="${IMAGES_DIR}/Dockerfile.k3s-cuda"
}

teardown() {
  :
}

@test "IMG-01: Dockerfile.k3s-cuda uses nvidia/cuda base + rancher/k3s build stage" {
  skip "awaiting implementation in plan 02-02 (Dockerfile created)"
  # run grep -E '^FROM nvidia/cuda:12\.8\.1-base-ubuntu22\.04' "$DOCKERFILE"
  # [ "$status" -eq 0 ]
}
