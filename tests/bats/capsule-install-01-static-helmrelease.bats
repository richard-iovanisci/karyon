#!/usr/bin/env bats
# tests/bats/capsule-install-01-static-helmrelease.bats
# HelmRelease v2 shape contract for BOTH operator and proxy.

load 'test_helper'

setup() {
  OPERATOR_HR="${REPO_ROOT}/pocs/capsule/operator/helmrelease.yaml"
  PROXY_HR="${REPO_ROOT}/pocs/capsule/proxy/helmrelease.yaml"
}

@test "CAP-01 / D-08-06: operator HelmRelease has apiVersion helm.toolkit.fluxcd.io/v2, kind HelmRelease, name capsule, namespace capsule-system, interval 5m" {
  [ -f "$OPERATOR_HR" ]
  run yq eval '.apiVersion == "helm.toolkit.fluxcd.io/v2" and .kind == "HelmRelease" and .metadata.name == "capsule" and .metadata.namespace == "capsule-system" and .spec.interval == "5m"' "$OPERATOR_HR"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "CAP-01 / D-08-02: operator HelmRelease chartRef points at OCIRepository capsule (post-2024 modern shape — NOT spec.chart.spec.chart)" {
  [ -f "$OPERATOR_HR" ]
  run yq eval '.spec.chartRef.kind == "OCIRepository" and .spec.chartRef.name == "capsule"' "$OPERATOR_HR"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "CAP-01 / P18 / P40: operator HelmRelease has spec.kubeConfig.secretRef.name=spoke-capsule-kubeconfig AND key=value.yaml" {
  [ -f "$OPERATOR_HR" ]
  run yq eval '.spec.kubeConfig.secretRef.name == "spoke-capsule-kubeconfig" and .spec.kubeConfig.secretRef.key == "value.yaml"' "$OPERATOR_HR"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "CAP-01: operator HelmRelease has targetNamespace=capsule-system AND install.createNamespace=true" {
  [ -f "$OPERATOR_HR" ]
  run yq eval '.spec.targetNamespace == "capsule-system" and .spec.install.createNamespace == true' "$OPERATOR_HR"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "CAP-01: operator HelmRelease has install.crds=CreateReplace AND upgrade.crds=CreateReplace" {
  [ -f "$OPERATOR_HR" ]
  run yq eval '.spec.install.crds == "CreateReplace" and .spec.upgrade.crds == "CreateReplace"' "$OPERATOR_HR"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "CAP-02 / D-08-06: proxy HelmRelease has apiVersion helm.toolkit.fluxcd.io/v2, kind HelmRelease, name capsule-proxy, namespace capsule-system, interval 5m" {
  [ -f "$PROXY_HR" ]
  run yq eval '.apiVersion == "helm.toolkit.fluxcd.io/v2" and .kind == "HelmRelease" and .metadata.name == "capsule-proxy" and .metadata.namespace == "capsule-system" and .spec.interval == "5m"' "$PROXY_HR"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "CAP-02 / D-08-02: proxy HelmRelease chartRef points at OCIRepository capsule-proxy" {
  [ -f "$PROXY_HR" ]
  run yq eval '.spec.chartRef.kind == "OCIRepository" and .spec.chartRef.name == "capsule-proxy"' "$PROXY_HR"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "CAP-02 / P18 / P40: proxy HelmRelease has spec.kubeConfig.secretRef.name=spoke-capsule-kubeconfig AND key=value.yaml" {
  [ -f "$PROXY_HR" ]
  run yq eval '.spec.kubeConfig.secretRef.name == "spoke-capsule-kubeconfig" and .spec.kubeConfig.secretRef.key == "value.yaml"' "$PROXY_HR"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "CAP-02 / D-08-07: proxy HelmRelease dependsOn[0] names operator capsule in capsule-system" {
  [ -f "$PROXY_HR" ]
  run yq eval '.spec.dependsOn[0].name == "capsule" and .spec.dependsOn[0].namespace == "capsule-system"' "$PROXY_HR"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}
