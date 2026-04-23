#!/usr/bin/env bats
# tests/bats/cuda-image-02-args.bats
# Pure-static check that ARG K3S_TAG default is v1.34.6-k3s1 (IMG-02 / D-03).
# Wave 0 stub — body filled by Plan 02-02 (or 02-03 for the manifest tests).

load 'test_helper'

setup() {
  DOCKERFILE="${IMAGES_DIR}/Dockerfile.k3s-cuda"
}

teardown() {
  :
}

@test "IMG-02: ARG K3S_TAG default is v1.34.6-k3s1" {
  run grep -E '^ARG K3S_TAG=v1\.34\.6-k3s1$' "$DOCKERFILE"
  [ "$status" -eq 0 ]
}
