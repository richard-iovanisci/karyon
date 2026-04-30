#!/usr/bin/env bats
# tests/bats/tenants-03-static-lockdown.bats
# Phase 9 / Wave 0 (D-09-08 Nyquist gate)
# TEN-05 — Hub Flux multi-tenancy lockdown patches in clusters/hub-flux/flux-system/kustomization.yaml
# Plans 09-01..09-03 land the yaml that turns these GREEN.
#
# Verifies (per RESEARCH §Gap 2 + §Gap 9 + CONTEXT D-09-05 / D-09-05a):
#   - FLUX PATCH SURFACE comment block preserved verbatim (regression gate against accidental edit)
#   - KARYON SPOKES MOUNT + KARYON POC MOUNT sentinels preserved
#   - NEW # KARYON FLUX LOCKDOWN PATCHES sentinel added (D-09-05)
#   - patches: block exists at top level
#   - 3 lockdown flag literals present:
#       --no-cross-namespace-refs=true
#       --no-remote-bases=true
#       --default-service-account=default
#   - 4 Strategic Merge Patch targets (per RESEARCH §Gap 2 canonical):
#       Deployment kustomize-controller (3 flags)
#       Deployment helm-controller (extends CONTEXT.md narrowing per RESEARCH Gap 2)
#       Deployment notification-controller
#       Kustomization flux-system (D-09-05a LOAD-BEARING escape hatch — without
#         spec.serviceAccountName: kustomize-controller the lockdown bricks Flux's
#         own bootstrap reconcile)

load 'test_helper'

setup() {
  HUB_FS_KUST="${REPO_ROOT}/clusters/hub-flux/flux-system/kustomization.yaml"
}

# ---- Comment block + sentinel preservation (regression gate) ----

@test "TEN-05 / regression gate: FLUX PATCH SURFACE comment block preserved verbatim" {
  [ -f "$HUB_FS_KUST" ]
  run grep -F -- 'FLUX PATCH SURFACE' "$HUB_FS_KUST"
  [ "$status" -eq 0 ]
  run grep -F -- 'Edits here SURVIVE re-bootstrap' "$HUB_FS_KUST"
  [ "$status" -eq 0 ]
  run grep -F -- 'See: docs/flux-hub-spoke.md' "$HUB_FS_KUST"
  [ "$status" -eq 0 ]
}

@test "TEN-05 / regression gate: KARYON SPOKES MOUNT sentinel + ../spokes resource preserved" {
  [ -f "$HUB_FS_KUST" ]
  run grep -F -- '# KARYON SPOKES MOUNT' "$HUB_FS_KUST"
  [ "$status" -eq 0 ]
  run grep -F -- '- ../spokes' "$HUB_FS_KUST"
  [ "$status" -eq 0 ]
}

@test "TEN-05 / regression gate: KARYON POC MOUNT sentinel + ../pocs resource preserved" {
  [ -f "$HUB_FS_KUST" ]
  run grep -F -- '# KARYON POC MOUNT' "$HUB_FS_KUST"
  [ "$status" -eq 0 ]
  run grep -F -- '- ../pocs' "$HUB_FS_KUST"
  [ "$status" -eq 0 ]
}

@test "TEN-05 / D-09-05: # KARYON FLUX LOCKDOWN PATCHES sentinel exists (NEW per Phase 9)" {
  [ -f "$HUB_FS_KUST" ]
  run grep -F -- '# KARYON FLUX LOCKDOWN PATCHES' "$HUB_FS_KUST"
  [ "$status" -eq 0 ]
}

# ---- patches: block + flag literals ----

@test "TEN-05 / D-09-05: patches: block exists at top level (length > 0)" {
  [ -f "$HUB_FS_KUST" ]
  run yq eval '.patches | length > 0' "$HUB_FS_KUST"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "TEN-05 / D-09-05: --no-cross-namespace-refs=true literal flag present" {
  [ -f "$HUB_FS_KUST" ]
  run grep -F -- '--no-cross-namespace-refs=true' "$HUB_FS_KUST"
  [ "$status" -eq 0 ]
}

@test "TEN-05 / D-09-05: --no-remote-bases=true literal flag present" {
  [ -f "$HUB_FS_KUST" ]
  run grep -F -- '--no-remote-bases=true' "$HUB_FS_KUST"
  [ "$status" -eq 0 ]
}

@test "TEN-05 / D-09-05: --default-service-account=default literal flag present" {
  [ -f "$HUB_FS_KUST" ]
  run grep -F -- '--default-service-account=default' "$HUB_FS_KUST"
  [ "$status" -eq 0 ]
}

# ---- 4 Strategic Merge Patch targets ----

@test "TEN-05 / D-09-05 / RESEARCH Gap 2: kustomize-controller Deployment patch exists" {
  [ -f "$HUB_FS_KUST" ]
  run yq eval '.patches | map(select(.target.kind == "Deployment" and .target.name == "kustomize-controller")) | length == 1' "$HUB_FS_KUST"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "TEN-05 / RESEARCH Gap 2: helm-controller Deployment patch exists (extends CONTEXT.md narrowing per upstream canonical)" {
  [ -f "$HUB_FS_KUST" ]
  run yq eval '.patches | map(select(.target.kind == "Deployment" and .target.name == "helm-controller")) | length == 1' "$HUB_FS_KUST"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "TEN-05 / D-09-05: notification-controller Deployment patch exists" {
  [ -f "$HUB_FS_KUST" ]
  run yq eval '.patches | map(select(.target.kind == "Deployment" and .target.name == "notification-controller")) | length == 1' "$HUB_FS_KUST"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "TEN-05 / D-09-05a LOAD-BEARING: flux-system Kustomization patch exists (escape hatch for kustomize-controller SA)" {
  [ -f "$HUB_FS_KUST" ]
  run yq eval '.patches | map(select(.target.kind == "Kustomization" and .target.name == "flux-system")) | length == 1' "$HUB_FS_KUST"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}
