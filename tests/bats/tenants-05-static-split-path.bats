#!/usr/bin/env bats
# tests/bats/tenants-05-static-split-path.bats
# Phase 9 / Wave 0 (D-09-08 Nyquist gate)
# D-08-12 split-path inheritance regression — Phase 8 invariant must still hold under Phase 9.
# Plans 09-01..09-03 land the yaml that turns these GREEN.
#
# Verifies:
#   capsule.yaml (hub-targeted outer K):
#     - spec.kubeConfig == null (Phase 8 D-08-12 invariant — applies HR/OCIRepo to HUB)
#     - spec.serviceAccountName == kustomize-controller (Phase 9 D-09-05a escape hatch
#       under lockdown — without it the hub-targeted K reconcile gets default SA which
#       has no perms after --default-service-account=default lands)
#   capsule-spoke.yaml (spoke-targeted outer K):
#     - spec.kubeConfig.secretRef.name == spoke-capsule-kubeconfig (Phase 7 P40/P18)
#     - spec.kubeConfig.secretRef.key == value.yaml (P18 LOAD-BEARING — silent-misroute
#       defense; without explicit key=value.yaml Flux silently falls back to in-cluster
#       config, applying spoke yaml to the WRONG cluster)

load 'test_helper'

setup() {
  POCS_CAPSULE="${REPO_ROOT}/clusters/hub-flux/pocs/capsule.yaml"
  POCS_CAPSULE_SPOKE="${REPO_ROOT}/clusters/hub-flux/pocs/capsule-spoke.yaml"
}

# ---- capsule.yaml (hub-targeted) ----

@test "D-08-12 / hub-targeted: capsule.yaml has NO spec.kubeConfig (Phase 8 split-path invariant)" {
  [ -f "$POCS_CAPSULE" ]
  run yq eval '.spec.kubeConfig == null' "$POCS_CAPSULE"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "D-09-05a / hub-targeted: capsule.yaml has spec.serviceAccountName == kustomize-controller (escape hatch under lockdown)" {
  [ -f "$POCS_CAPSULE" ]
  run yq eval '.spec.serviceAccountName == "kustomize-controller"' "$POCS_CAPSULE"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

# ---- capsule-spoke.yaml (spoke-targeted) ----

@test "D-08-12 / spoke-targeted: capsule-spoke.yaml has spec.kubeConfig.secretRef.name == spoke-capsule-kubeconfig (Phase 7 P40/P18)" {
  [ -f "$POCS_CAPSULE_SPOKE" ]
  run yq eval '.spec.kubeConfig.secretRef.name == "spoke-capsule-kubeconfig"' "$POCS_CAPSULE_SPOKE"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "P40/P18 LOAD-BEARING: capsule-spoke.yaml has spec.kubeConfig.secretRef.key == value.yaml (silent-misroute defense)" {
  [ -f "$POCS_CAPSULE_SPOKE" ]
  run yq eval '.spec.kubeConfig.secretRef.key == "value.yaml"' "$POCS_CAPSULE_SPOKE"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}
