#!/usr/bin/env bats
# tests/bats/capsule-install-02-static-ocirepo.bats
# OCIRepository v1 shape contract for BOTH operator and proxy.

load 'test_helper'

setup() {
  OPERATOR_OCIREPO="${REPO_ROOT}/pocs/capsule/operator/ocirepository.yaml"
  PROXY_OCIREPO="${REPO_ROOT}/pocs/capsule/proxy/ocirepository.yaml"
}

@test "CAP-01 / D-08-02: operator OCIRepository has apiVersion source.toolkit.fluxcd.io/v1, kind OCIRepository, name capsule, namespace capsule-system" {
  [ -f "$OPERATOR_OCIREPO" ]
  run yq eval '.apiVersion == "source.toolkit.fluxcd.io/v1" and .kind == "OCIRepository" and .metadata.name == "capsule" and .metadata.namespace == "capsule-system"' "$OPERATOR_OCIREPO"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "CAP-01: operator OCIRepository url is oci://ghcr.io/projectcapsule/charts/capsule AND ref.tag is 0.12.4 (literal pin)" {
  [ -f "$OPERATOR_OCIREPO" ]
  run yq eval '.spec.url == "oci://ghcr.io/projectcapsule/charts/capsule" and .spec.ref.tag == "0.12.4"' "$OPERATOR_OCIREPO"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "CAP-01: operator OCIRepository layerSelector.mediaType is the canonical Helm chart layer" {
  [ -f "$OPERATOR_OCIREPO" ]
  run yq eval '.spec.layerSelector.mediaType == "application/vnd.cncf.helm.chart.content.v1.tar+gzip"' "$OPERATOR_OCIREPO"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "CAP-02 / D-08-02: proxy OCIRepository has apiVersion source.toolkit.fluxcd.io/v1, kind OCIRepository, name capsule-proxy, namespace capsule-system" {
  [ -f "$PROXY_OCIREPO" ]
  run yq eval '.apiVersion == "source.toolkit.fluxcd.io/v1" and .kind == "OCIRepository" and .metadata.name == "capsule-proxy" and .metadata.namespace == "capsule-system"' "$PROXY_OCIREPO"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "CAP-02: proxy OCIRepository url is oci://ghcr.io/projectcapsule/charts/capsule-proxy AND ref.tag is 0.12.0 (literal pin)" {
  [ -f "$PROXY_OCIREPO" ]
  run yq eval '.spec.url == "oci://ghcr.io/projectcapsule/charts/capsule-proxy" and .spec.ref.tag == "0.12.0"' "$PROXY_OCIREPO"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "CAP-02: proxy OCIRepository layerSelector.mediaType is the canonical Helm chart layer" {
  [ -f "$PROXY_OCIREPO" ]
  run yq eval '.spec.layerSelector.mediaType == "application/vnd.cncf.helm.chart.content.v1.tar+gzip"' "$PROXY_OCIREPO"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "Public ghcr.io: operator OCIRepository declares NO secretRef and NO serviceAccountName" {
  [ -f "$OPERATOR_OCIREPO" ]
  run yq eval '(.spec | has("secretRef")) == false and (.spec | has("serviceAccountName")) == false' "$OPERATOR_OCIREPO"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "Public ghcr.io: proxy OCIRepository declares NO secretRef and NO serviceAccountName" {
  [ -f "$PROXY_OCIREPO" ]
  run yq eval '(.spec | has("secretRef")) == false and (.spec | has("serviceAccountName")) == false' "$PROXY_OCIREPO"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}
