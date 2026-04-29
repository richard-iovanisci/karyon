#!/usr/bin/env bats
# tests/bats/capsule-install-05-static-kustomize.bats
# Phase 8 / Wave 0 (D-08-09 Nyquist gate)
# D-08-05 — Inner kustomization rewrite contract for pocs/capsule/ tree.
# Plans 08-01 and 08-02 land the kustomization.yaml files that turn these GREEN.

load 'test_helper'

setup() {
  POCS_CAPSULE_KUST="${REPO_ROOT}/pocs/capsule/kustomization.yaml"
  OPERATOR_KUST="${REPO_ROOT}/pocs/capsule/operator/kustomization.yaml"
  PROXY_KUST="${REPO_ROOT}/pocs/capsule/proxy/kustomization.yaml"
}

@test "D-08-05: pocs/capsule/kustomization.yaml resources length=2 AND resources=[operator/, proxy/]" {
  [ -f "$POCS_CAPSULE_KUST" ]
  run yq eval '(.resources | length) == 2 and .resources[0] == "operator/" and .resources[1] == "proxy/"' "$POCS_CAPSULE_KUST"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "D-08-05: pocs/capsule/kustomization.yaml apiVersion + kind preserved (Phase 7 inheritance)" {
  [ -f "$POCS_CAPSULE_KUST" ]
  run yq eval '.apiVersion == "kustomize.config.k8s.io/v1beta1" and .kind == "Kustomization"' "$POCS_CAPSULE_KUST"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "D-08-05: pocs/capsule/kustomization.yaml head comment block preserves REQ-CAPCLU-02 attribution" {
  [ -f "$POCS_CAPSULE_KUST" ]
  run grep -F -- 'REQ-CAPCLU-02' "$POCS_CAPSULE_KUST"
  [ "$status" -eq 0 ]
}

@test "D-08-05: pocs/capsule/kustomization.yaml head comment block preserves Pitfall 7 attribution" {
  [ -f "$POCS_CAPSULE_KUST" ]
  run grep -F -- 'Pitfall 7' "$POCS_CAPSULE_KUST"
  [ "$status" -eq 0 ]
}

@test "D-08-05: pocs/capsule/operator/kustomization.yaml is a Kustomize aggregator referencing both operator yamls" {
  [ -f "$OPERATOR_KUST" ]
  run yq eval '.apiVersion == "kustomize.config.k8s.io/v1beta1" and .kind == "Kustomization" and (.resources | length) == 2 and (.resources | contains(["ocirepository.yaml"])) and (.resources | contains(["helmrelease.yaml"]))' "$OPERATOR_KUST"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "D-08-05: pocs/capsule/proxy/kustomization.yaml is a Kustomize aggregator referencing both proxy yamls" {
  [ -f "$PROXY_KUST" ]
  run yq eval '.apiVersion == "kustomize.config.k8s.io/v1beta1" and .kind == "Kustomization" and (.resources | length) == 2 and (.resources | contains(["ocirepository.yaml"])) and (.resources | contains(["helmrelease.yaml"]))' "$PROXY_KUST"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}
