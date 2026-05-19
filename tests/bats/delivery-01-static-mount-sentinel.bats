#!/usr/bin/env bats
# tests/bats/delivery-01-static-mount-sentinel.bats
# Phase 13 / Wave 0 (D-13-15 Nyquist gate)
# DELIVERY-01 — KARYON POC MOUNT sentinel preservation in flux-system kustomization.
# The sentinel is a COMMENT line `# KARYON POC MOUNT` in
# clusters/hub-flux/flux-system/kustomization.yaml followed by `- ../pocs` resource.
# Comment-stripping is intentionally NOT used here — the sentinel itself is a comment.
# GREEN-by-design (this is a regression gate against accidental sentinel removal).

load 'test_helper'

setup() {
  F="${REPO_ROOT}/clusters/hub-flux/flux-system/kustomization.yaml"
}

@test "DELIVERY-01 / KARYON POC MOUNT: target file exists at clusters/hub-flux/flux-system/kustomization.yaml" {
  [ -f "$F" ]
}

@test "DELIVERY-01 / KARYON POC MOUNT: sentinel present (>= 1 occurrence)" {
  [ -f "$F" ]
  run grep -F 'KARYON POC MOUNT' "$F"
  [ "$status" -eq 0 ]
}

@test "DELIVERY-01 / KARYON POC MOUNT: sentinel appears exactly 1 time (anti-duplicate)" {
  [ -f "$F" ]
  # NOTE on filter strategy: the sentinel itself is a comment line `# KARYON POC MOUNT`,
  # so stripping comments first would yield zero — wrong direction. We do NOT strip
  # comments here. We DO assert exactly 1 occurrence to catch accidental duplication.
  local n
  n=$(grep -c 'KARYON POC MOUNT' "$F")
  [ "$n" -eq 1 ]
}

@test "DELIVERY-01 / KARYON POC MOUNT: resource line ../pocs is present in resources[]" {
  [ -f "$F" ]
  run grep -F -- '../pocs' "$F"
  [ "$status" -eq 0 ]
}
