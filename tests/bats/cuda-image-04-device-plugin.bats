#!/usr/bin/env bats
# tests/bats/cuda-image-04-device-plugin.bats
# Static + L2 check that images/device-plugin-daemonset.yaml pins nvcr.io/nvidia/k8s-device-plugin:v0.17.4 (IMG-04 / DEVICE_PLUGIN_VERSION lock per planning context note: REQ-IMG-04 text says "v0.19.0+" but the user has approved v0.17.4 as the current-stable interpretation; do NOT amend REQUIREMENTS.md here — that's a docs change owned by Phase 6).
# Wave 0 stub — body filled by Plan 02-02 (or 02-03 for the manifest tests).

load 'test_helper'

setup() {
  MANIFEST="${IMAGES_DIR}/device-plugin-daemonset.yaml"
}

teardown() {
  :
}

@test "IMG-04: device-plugin manifest pins image v0.17.4" {
  skip "awaiting implementation in plan 02-03 (device-plugin-daemonset.yaml created)"
  # run grep -F 'image: nvcr.io/nvidia/k8s-device-plugin:v0.17.4' "$MANIFEST"
  # [ "$status" -eq 0 ]
}
