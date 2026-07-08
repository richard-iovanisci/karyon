#!/usr/bin/env bats
# tests/bats/poc-mount-01-static.bats
# Sentinel + pocs/ aggregator + capsule.yaml outer Kustomization + placeholder shape

load 'test_helper'

setup() {
  HUB_FS_KUST="${REPO_ROOT}/clusters/hub-flux/flux-system/kustomization.yaml"
  HUB_PEER_KUST="${REPO_ROOT}/clusters/hub-flux/kustomization.yaml"
  POCS_INDEX="${REPO_ROOT}/clusters/hub-flux/pocs/kustomization.yaml"
  POCS_CAPSULE="${REPO_ROOT}/clusters/hub-flux/pocs/capsule.yaml"
  POCS_CAPSULE_SPOKE="${REPO_ROOT}/clusters/hub-flux/pocs/capsule-spoke.yaml"
  POCS_PLACEHOLDER="${REPO_ROOT}/pocs/capsule/kustomization.yaml"
  POCS_SPOKE_PLACEHOLDER="${REPO_ROOT}/pocs/capsule/spoke/kustomization.yaml"
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

# RECONCILED 2026-07-06: originally asserted exactly [capsule.yaml, capsule-spoke.yaml].
# Later work added capsule-spoke-rbac.yaml and capsule-spoke-tenants.yaml; the
# Keycloak IdP POC added keycloak-{tenant,spoke,app}.yaml; the tenant-UI OIDC
# work added headlamp.yaml — 8 entries total.
@test "POC-01 / D-06 / D-08-12 / G-06 / D-11-07 / keycloak-idp / tenant-ui: clusters/hub-flux/pocs/kustomization.yaml aggregates the 8-Kustomization POC set" {
  [ -f "$POCS_INDEX" ]
  run yq eval '.apiVersion == "kustomize.config.k8s.io/v1beta1" and .kind == "Kustomization" and (.resources | length) == 8 and (.resources | contains(["capsule-spoke-rbac.yaml"])) and (.resources | contains(["capsule.yaml"])) and (.resources | contains(["capsule-spoke-tenants.yaml"])) and (.resources | contains(["capsule-spoke.yaml"])) and (.resources | contains(["keycloak-tenant.yaml"])) and (.resources | contains(["keycloak-spoke.yaml"])) and (.resources | contains(["keycloak-app.yaml"])) and (.resources | contains(["headlamp.yaml"]))' "$POCS_INDEX"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "POC-01 / D-08-12: clusters/hub-flux/pocs/capsule.yaml is hub-targeted (path ./pocs/capsule, NO spec.kubeConfig — applies HR/OCIRepo to hub)" {
  [ -f "$POCS_CAPSULE" ]
  # Architectural seam: the hub-targeted K must NOT carry spec.kubeConfig (otherwise
  # kustomize-controller would route HR/OCIRepo CRs to the spoke, which has no Flux CRDs —
  # see docs/adr/0004-hub-only-flux-control-plane.md).
  run yq eval '.apiVersion == "kustomize.toolkit.fluxcd.io/v1" and .kind == "Kustomization" and .metadata.name == "poc-capsule" and .metadata.namespace == "flux-system" and .spec.path == "./pocs/capsule" and .spec.prune == true and (.spec.kubeConfig == null)' "$POCS_CAPSULE"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "POC-01 / D-11 / P40 / D-08-12: clusters/hub-flux/pocs/capsule-spoke.yaml is spoke-targeted (path ./pocs/capsule/spoke, full spec.kubeConfig.secretRef.name + key value.yaml)" {
  [ -f "$POCS_CAPSULE_SPOKE" ]
  # Split-path pattern: the spoke-targeted K MUST carry the full spec.kubeConfig block
  # (silent-misroute defense: without it Flux applies the spoke yaml to the hub while
  # reporting Ready). The kustomize-controller impersonates the spoke via the
  # spoke-capsule-kubeconfig Secret to apply pocs/capsule/spoke/* (the Tenant CRs).
  run yq eval '.apiVersion == "kustomize.toolkit.fluxcd.io/v1" and .kind == "Kustomization" and .metadata.name == "poc-capsule-spoke" and .metadata.namespace == "flux-system" and .spec.path == "./pocs/capsule/spoke" and .spec.kubeConfig.secretRef.name == "spoke-capsule-kubeconfig" and .spec.kubeConfig.secretRef.key == "value.yaml" and .spec.prune == true' "$POCS_CAPSULE_SPOKE"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

# RECONCILED 2026-07-06: the "empty placeholder" era ended once the spoke tree was
# populated (rbac/, config/, tenants/, then global-resources/ LAST — FIFO ordering is
# load-bearing: global-resources must apply after the Tenant CRs exist).
@test "POC-01 / Pitfall 7 / D-08-12 / D-13-13: pocs/capsule/spoke/kustomization.yaml lists rbac/, config/, tenants/, global-resources/ in FIFO order" {
  [ -f "$POCS_SPOKE_PLACEHOLDER" ]
  run yq eval '.apiVersion == "kustomize.config.k8s.io/v1beta1" and .kind == "Kustomization" and (.resources | length) == 4 and .resources[0] == "rbac/" and .resources[1] == "config/" and .resources[2] == "tenants/" and .resources[3] == "global-resources/"' "$POCS_SPOKE_PLACEHOLDER"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "POC-01 / Pitfall 7: pocs/capsule/kustomization.yaml exists with valid Kustomize shape (resources may be empty)" {
  [ -f "$POCS_PLACEHOLDER" ]
  run yq eval '.apiVersion == "kustomize.config.k8s.io/v1beta1" and .kind == "Kustomization" and (has("resources"))' "$POCS_PLACEHOLDER"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}
