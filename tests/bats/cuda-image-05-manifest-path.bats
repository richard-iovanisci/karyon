#!/usr/bin/env bats
# tests/bats/cuda-image-05-manifest-path.bats
# L2: docker run the built image and assert /var/lib/rancher/k3s/server/manifests/nvidia-device-plugin-daemonset.yaml exists.

load 'test_helper'

setup() {
  require_live
  TAG="$(cuda_image_tag)"
}

teardown() {
  :
}

@test "IMG-05: device-plugin manifest baked at k3s auto-apply path /var/lib/rancher/k3s/server/manifests/nvidia-device-plugin-daemonset.yaml" {
  run docker run --rm --entrypoint test "$TAG" -f /var/lib/rancher/k3s/server/manifests/nvidia-device-plugin-daemonset.yaml
  [ "$status" -eq 0 ]
}
