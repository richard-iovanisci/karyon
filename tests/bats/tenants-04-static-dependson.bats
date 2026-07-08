#!/usr/bin/env bats
# tests/bats/tenants-04-static-dependson.bats
# dependsOn chain: poc-capsule-spoke depends on poc-capsule;
# per-tenant inner Ks depend on poc-capsule. Plus spec.wait at TOP LEVEL
# (wait is a top-level Kustomization spec field, NOT inside a dependsOn entry).
#
# Verifies:
#   capsule-spoke.yaml (clusters/hub-flux/pocs/):
#     - spec.dependsOn[0].name == poc-capsule
#     - spec.wait == true (TOP-LEVEL)
#     - spec.timeout == 10m
#     - spec.serviceAccountName explicit (flux-reconciler — see note above that @test)
#   per-tenant inner Ks (pocs/capsule/tenants/*.yaml):
#     - every Kustomization doc has spec.dependsOn[0].name == poc-capsule
#       AND spec.dependsOn[0].namespace == flux-system (cross-namespace OK because
#       --no-cross-namespace-refs only restricts sourceRef/secretRef, not dependsOn)
#     - every Kustomization doc has spec.wait == true (TOP-LEVEL)

load 'test_helper'

# Multi-doc lint helpers — see tenants-02-static-p27.bats for the same adapter
# pattern. Each helper iterates Flux v1 Kustomization docs only.

assert_inner_k_dependson_poc_capsule() {
  local dir="$1"
  local found_any=0
  shopt -s nullglob
  for f in "${dir}"/*.yaml "${dir}"/*.yml; do
    [ -f "$f" ] || continue
    # `yq eval` (per-doc) emits one TSV row per YAML document — required for
    # multi-doc files (alpha.yaml + bravo.yaml). `yq eval-all` would collapse
    # all docs into a single flattened TSV row — hence `eval`, not `eval-all`.
    while IFS=$'\t' read -r kind apiv dep_name dep_ns; do
      [ "$kind" = "Kustomization" ] && [ "$apiv" = "kustomize.toolkit.fluxcd.io/v1" ] || continue
      found_any=1
      if [ "$dep_name" != "poc-capsule" ] || [ "$dep_ns" != "flux-system" ]; then
        echo "TEN-06 dependsOn violation in ${f}: dependsOn[0].name='${dep_name}' namespace='${dep_ns}' (expected name=poc-capsule namespace=flux-system)"
        return 1
      fi
    done < <(yq eval '[.kind // "", .apiVersion // "", .spec.dependsOn[0].name // "", .spec.dependsOn[0].namespace // ""] | @tsv' "$f" 2>/dev/null || true)
  done
  if [ "$found_any" -eq 0 ]; then
    echo "TEN-06 dependsOn lint found NO Flux Kustomization docs under ${dir}"
    return 1
  fi
  return 0
}

assert_inner_k_wait_top_level() {
  local dir="$1"
  local found_any=0
  shopt -s nullglob
  for f in "${dir}"/*.yaml "${dir}"/*.yml; do
    [ -f "$f" ] || continue
    # `yq eval` (per-doc) emits one TSV row per YAML document — required for
    # multi-doc files (alpha.yaml + bravo.yaml). `yq eval-all` would collapse
    # all docs into a single flattened TSV row — hence `eval`, not `eval-all`.
    while IFS=$'\t' read -r kind apiv wait_field; do
      [ "$kind" = "Kustomization" ] && [ "$apiv" = "kustomize.toolkit.fluxcd.io/v1" ] || continue
      found_any=1
      if [ "$wait_field" != "true" ]; then
        echo "TEN-06 wait violation in ${f}: spec.wait='${wait_field}' (expected true at TOP LEVEL)"
        return 1
      fi
    done < <(yq eval '[.kind // "", .apiVersion // "", .spec.wait // ""] | @tsv' "$f" 2>/dev/null || true)
  done
  if [ "$found_any" -eq 0 ]; then
    echo "TEN-06 wait lint found NO Flux Kustomization docs under ${dir}"
    return 1
  fi
  return 0
}

setup() {
  CAPSULE_SPOKE="${REPO_ROOT}/clusters/hub-flux/pocs/capsule-spoke.yaml"
  TENANTS_DIR="${REPO_ROOT}/pocs/capsule/tenants"
  export -f assert_inner_k_dependson_poc_capsule 2>/dev/null || true
  export -f assert_inner_k_wait_top_level 2>/dev/null || true
}

# ---- capsule-spoke.yaml (outer K) ----

# RECONCILED 2026-07-06: originally asserted dependsOn[0] == poc-capsule only.
# Later changes (2026-05-06) prepended poc-capsule-spoke-rbac and appended
# poc-capsule-spoke-tenants — the full 3-entry chain is intentional.
@test "TEN-06 / D-09-06 / G-06 / D-11-07: capsule-spoke.yaml dependsOn == [poc-capsule-spoke-rbac, poc-capsule, poc-capsule-spoke-tenants]" {
  [ -f "$CAPSULE_SPOKE" ]
  run yq eval '(.spec.dependsOn | length) == 3 and .spec.dependsOn[0].name == "poc-capsule-spoke-rbac" and .spec.dependsOn[1].name == "poc-capsule" and .spec.dependsOn[2].name == "poc-capsule-spoke-tenants"' "$CAPSULE_SPOKE"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "TEN-06 / RESEARCH Gap 9: capsule-spoke.yaml spec.wait == true (TOP-LEVEL, NOT inside dependsOn entry)" {
  [ -f "$CAPSULE_SPOKE" ]
  run yq eval '.spec.wait == true' "$CAPSULE_SPOKE"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "TEN-06 / D-09-06: capsule-spoke.yaml spec.timeout == 10m" {
  [ -f "$CAPSULE_SPOKE" ]
  run yq eval '.spec.timeout == "10m"' "$CAPSULE_SPOKE"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

# RECONCILED 2026-07-06: an early draft guessed kustomize-controller; the real
# spoke-side SA is flux-reconciler (lesson: verify live identifiers before naming
# them — the register scripts create flux-reconciler, not kustomize-controller,
# on the target cluster).
@test "TEN-06 / D-09-05 (Plan 09-03 attempt-3 correction): capsule-spoke.yaml spec.serviceAccountName == flux-reconciler" {
  [ -f "$CAPSULE_SPOKE" ]
  run yq eval '.spec.serviceAccountName == "flux-reconciler"' "$CAPSULE_SPOKE"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

# ---- per-tenant inner Ks (pocs/capsule/tenants/) ----

@test "TEN-06 / D-09-06: every Kustomization in pocs/capsule/tenants/*.yaml has dependsOn[0].name=poc-capsule + namespace=flux-system" {
  [ -d "$TENANTS_DIR" ]
  run assert_inner_k_dependson_poc_capsule "$TENANTS_DIR"
  [ "$status" -eq 0 ]
}

@test "TEN-06 / RESEARCH Gap 9: every Kustomization in pocs/capsule/tenants/*.yaml has spec.wait == true (TOP-LEVEL)" {
  [ -d "$TENANTS_DIR" ]
  run assert_inner_k_wait_top_level "$TENANTS_DIR"
  [ "$status" -eq 0 ]
}
