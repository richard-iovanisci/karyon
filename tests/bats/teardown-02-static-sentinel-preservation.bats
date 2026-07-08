#!/usr/bin/env bats
# tests/bats/teardown-02-static-sentinel-preservation.bats
# Sentinel preservation guarantee -- the # KARYON POC MOUNT sentinel
# and ../pocs mount line in clusters/hub-flux/flux-system/kustomization.yaml MUST stay
# verbatim regardless of teardown. This fails only if the sentinel was removed;
# it stays GREEN as long as the load-bearing v0.19 invariant holds.

load 'test_helper'

setup() {
  HUB_FS_KUST="${REPO_ROOT}/clusters/hub-flux/flux-system/kustomization.yaml"
}

@test "D-11-10 sentinel: clusters/hub-flux/flux-system/kustomization.yaml retains '# KARYON POC MOUNT' + '- ../pocs'" {
  [ -f "$HUB_FS_KUST" ]
  run grep -F -- '# KARYON POC MOUNT' "$HUB_FS_KUST"
  [ "$status" -eq 0 ]
  run grep -F -- '- ../pocs' "$HUB_FS_KUST"
  [ "$status" -eq 0 ]
}
