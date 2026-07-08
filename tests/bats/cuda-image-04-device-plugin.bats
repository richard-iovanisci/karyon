#!/usr/bin/env bats
# tests/bats/cuda-image-04-device-plugin.bats
# Static + L2 check that images/device-plugin-daemonset.yaml pins
# nvcr.io/nvidia/k8s-device-plugin:v0.17.4 (DEVICE_PLUGIN_VERSION lock; v0.17.4 is the
# approved current-stable pin — bump it deliberately, not as a drive-by edit).

load 'test_helper'

setup() {
  MANIFEST="${IMAGES_DIR}/device-plugin-daemonset.yaml"
}

teardown() {
  :
}

@test "IMG-04: device-plugin manifest pins image v0.17.4" {
  run grep -F 'image: nvcr.io/nvidia/k8s-device-plugin:v0.17.4' "$MANIFEST"
  [ "$status" -eq 0 ]
}
