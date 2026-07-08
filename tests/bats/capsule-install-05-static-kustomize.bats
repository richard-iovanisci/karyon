#!/usr/bin/env bats
# tests/bats/capsule-install-05-static-kustomize.bats
# Inner kustomization contract for the pocs/capsule/ tree: aggregator shapes,
# resource lists, and the load-bearing head comments in
# pocs/capsule/kustomization.yaml.

load 'test_helper'

setup() {
  POCS_CAPSULE_KUST="${REPO_ROOT}/pocs/capsule/kustomization.yaml"
  OPERATOR_KUST="${REPO_ROOT}/pocs/capsule/operator/kustomization.yaml"
  PROXY_KUST="${REPO_ROOT}/pocs/capsule/proxy/kustomization.yaml"
}

# RECONCILED 2026-07-06: originally asserted exactly [operator/, proxy/].
# namespace.yaml (capsule-system on hub) and tenants/ were added later — both
# intentional; the guard was never updated.
@test "static: pocs/capsule/kustomization.yaml resources=[namespace.yaml, operator/, proxy/, tenants/]" {
  [ -f "$POCS_CAPSULE_KUST" ]
  run yq eval '(.resources | length) == 4 and .resources[0] == "namespace.yaml" and .resources[1] == "operator/" and .resources[2] == "proxy/" and .resources[3] == "tenants/"' "$POCS_CAPSULE_KUST"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "static: pocs/capsule/kustomization.yaml apiVersion + kind preserved" {
  [ -f "$POCS_CAPSULE_KUST" ]
  run yq eval '.apiVersion == "kustomize.config.k8s.io/v1beta1" and .kind == "Kustomization"' "$POCS_CAPSULE_KUST"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "static: pocs/capsule/kustomization.yaml head comment keeps the separate-chart (anti-umbrella) warning" {
  [ -f "$POCS_CAPSULE_KUST" ]
  run grep -F -- 'SEPARATE charts' "$POCS_CAPSULE_KUST"
  [ "$status" -eq 0 ]
  run grep -F -- 'umbrella' "$POCS_CAPSULE_KUST"
  [ "$status" -eq 0 ]
}

@test "static: pocs/capsule/kustomization.yaml head comment keeps the missing-file failure mode" {
  [ -f "$POCS_CAPSULE_KUST" ]
  run grep -F -- 'path not found' "$POCS_CAPSULE_KUST"
  [ "$status" -eq 0 ]
}

@test "static: pocs/capsule/operator/kustomization.yaml is a Kustomize aggregator referencing both operator yamls" {
  [ -f "$OPERATOR_KUST" ]
  run yq eval '.apiVersion == "kustomize.config.k8s.io/v1beta1" and .kind == "Kustomization" and (.resources | length) == 2 and (.resources | contains(["ocirepository.yaml"])) and (.resources | contains(["helmrelease.yaml"]))' "$OPERATOR_KUST"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "static: pocs/capsule/proxy/kustomization.yaml is a Kustomize aggregator referencing both proxy yamls" {
  [ -f "$PROXY_KUST" ]
  run yq eval '.apiVersion == "kustomize.config.k8s.io/v1beta1" and .kind == "Kustomization" and (.resources | length) == 2 and (.resources | contains(["ocirepository.yaml"])) and (.resources | contains(["helmrelease.yaml"]))' "$PROXY_KUST"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}
