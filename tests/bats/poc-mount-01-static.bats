#!/usr/bin/env bats
# tests/bats/poc-mount-01-static.bats
# POC-01 — sentinel + pocs/ aggregator + capsule.yaml outer Kustomization + placeholder shape

load 'test_helper'

setup() {
  HUB_FS_KUST="${REPO_ROOT}/clusters/hub-flux/flux-system/kustomization.yaml"
  HUB_PEER_KUST="${REPO_ROOT}/clusters/hub-flux/kustomization.yaml"
  POCS_INDEX="${REPO_ROOT}/clusters/hub-flux/pocs/kustomization.yaml"
  POCS_CAPSULE="${REPO_ROOT}/clusters/hub-flux/pocs/capsule.yaml"
  POCS_PLACEHOLDER="${REPO_ROOT}/pocs/capsule/kustomization.yaml"
}

@test "POC-01 / D-09: # KARYON POC MOUNT sentinel exists in clusters/hub-flux/flux-system/kustomization.yaml" {
  [ -f "$HUB_FS_KUST" ]
  run grep -F -- '# KARYON POC MOUNT' "$HUB_FS_KUST"
  [ "$status" -eq 0 ]
}

@test "POC-01 / D-09: # KARYON SPOKES MOUNT (Phase 4 D-13 inheritance) is preserved unchanged" {
  [ -f "$HUB_FS_KUST" ]
  run grep -F -- '# KARYON SPOKES MOUNT' "$HUB_FS_KUST"
  [ "$status" -eq 0 ]
  run grep -F -- '- ../spokes' "$HUB_FS_KUST"
  [ "$status" -eq 0 ]
}

@test "POC-01: - ../pocs resource line follows # KARYON POC MOUNT sentinel" {
  [ -f "$HUB_FS_KUST" ]
  run grep -F -- '- ../pocs' "$HUB_FS_KUST"
  [ "$status" -eq 0 ]
}

@test "POC-01 / P30: # KARYON POC MOUNT sentinel appears EXACTLY ONCE (idempotency)" {
  [ -f "$HUB_FS_KUST" ]
  count=$(grep -v '^[[:space:]]*#' "$HUB_FS_KUST" | grep -cF -- '# KARYON POC MOUNT' || true)
  # Note: filter comments above is incorrect for sentinel-line counting (sentinel IS a comment).
  # Use a direct line count on the literal text:
  count=$(grep -cF -- '# KARYON POC MOUNT' "$HUB_FS_KUST")
  [ "$count" -eq 1 ]
}

@test "POC-01 / D-09 (anti-pattern guard): # KARYON POC MOUNT MUST NOT exist in peer kustomization.yaml" {
  [ -f "$HUB_PEER_KUST" ]
  run grep -F -- '# KARYON POC MOUNT' "$HUB_PEER_KUST"
  [ "$status" -ne 0 ]
}

@test "POC-01 / D-06: clusters/hub-flux/pocs/kustomization.yaml is a kustomize aggregator referencing capsule.yaml" {
  [ -f "$POCS_INDEX" ]
  run yq eval '.apiVersion == "kustomize.config.k8s.io/v1beta1" and .kind == "Kustomization" and (.resources | length) == 1 and .resources[0] == "capsule.yaml"' "$POCS_INDEX"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "POC-01 / D-11 / P40: clusters/hub-flux/pocs/capsule.yaml carries spec.kubeConfig.secretRef.name and key value.yaml" {
  [ -f "$POCS_CAPSULE" ]
  run yq eval '.apiVersion == "kustomize.toolkit.fluxcd.io/v1" and .kind == "Kustomization" and .metadata.name == "poc-capsule" and .metadata.namespace == "flux-system" and .spec.path == "./pocs/capsule" and .spec.kubeConfig.secretRef.name == "spoke-capsule-kubeconfig" and .spec.kubeConfig.secretRef.key == "value.yaml" and .spec.prune == true' "$POCS_CAPSULE"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "POC-01 / Pitfall 7: pocs/capsule/kustomization.yaml exists with valid Kustomize shape (resources may be empty)" {
  [ -f "$POCS_PLACEHOLDER" ]
  run yq eval '.apiVersion == "kustomize.config.k8s.io/v1beta1" and .kind == "Kustomization" and (has("resources"))' "$POCS_PLACEHOLDER"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}
