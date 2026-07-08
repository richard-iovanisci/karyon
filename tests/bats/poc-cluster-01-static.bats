#!/usr/bin/env bats
# tests/bats/poc-cluster-01-static.bats
# Static contract for create-cluster.sh + fix-dns.sh + clusters/hub-flux/pocs/capsule*.yaml + Taskfile

load 'test_helper'

setup() {
  CREATE_SCRIPT="${REPO_ROOT}/scripts/poc/capsule/create-cluster.sh"
  FIX_DNS_SCRIPT="${REPO_ROOT}/scripts/poc/capsule/fix-dns.sh"
  CAPSULE_KS="${REPO_ROOT}/clusters/hub-flux/pocs/capsule.yaml"
  CAPSULE_SPOKE_KS="${REPO_ROOT}/clusters/hub-flux/pocs/capsule-spoke.yaml"
  TASKFILE="${REPO_ROOT}/Taskfile.yml"
}

@test "scripts/poc/capsule/create-cluster.sh exists, strict-mode, sources preflight-lib" {
  [ -f "$CREATE_SCRIPT" ]
  run grep -E '^set -euo pipefail' "$CREATE_SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- 'preflight-lib.sh' "$CREATE_SCRIPT"
  [ "$status" -eq 0 ]
}

@test "create-cluster.sh pins POC_CLUSTER=spoke-capsule, port 6446, NodePort 30443, k8s-net" {
  [ -f "$CREATE_SCRIPT" ]
  run grep -F -- 'POC_CLUSTER="spoke-capsule"' "$CREATE_SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- 'POC_API_PORT="6446"' "$CREATE_SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- 'POC_NODEPORT="30443"' "$CREATE_SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- 'K8S_NET_NAME="k8s-net"' "$CREATE_SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- 'rancher/k3s:v1.34.6-k3s1' "$CREATE_SCRIPT"
  [ "$status" -eq 0 ]
}

@test "create-cluster.sh invokes k3d cluster create with --tls-san k3d-spoke-capsule-server-0 and --port 30443:30443@loadbalancer" {
  [ -f "$CREATE_SCRIPT" ]
  run grep -F -- 'k3d-spoke-capsule-server-0' "$CREATE_SCRIPT"
  [ "$status" -eq 0 ]
  # @loadbalancer is locked so the host port lives on the serverlb container
  # (matching v0.18's drift-verify pattern which inspects serverlb only).
  run grep -F -- '30443:30443@loadbalancer' "$CREATE_SCRIPT"
  [ "$status" -eq 0 ]
}

@test "create-cluster.sh idempotency — drift verify on image, network, ports" {
  [ -f "$CREATE_SCRIPT" ]
  run grep -F -- 'actual_image' "$CREATE_SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- 'actual_network' "$CREATE_SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- 'actual_ports' "$CREATE_SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- 'already done, skipping' "$CREATE_SCRIPT"
  [ "$status" -eq 0 ]
}

@test "create-cluster.sh invokes preflight as gate" {
  [ -f "$CREATE_SCRIPT" ]
  run grep -F -- 'preflight.sh' "$CREATE_SCRIPT"
  [ "$status" -eq 0 ]
}

@test "clusters/hub-flux/pocs/capsule.yaml is hub-targeted (path=./pocs/capsule, NO spec.kubeConfig)" {
  # Split-path pattern (see poc-mount-01-static.bats for the canonical dual-K split
  # assertions): the hub-targeted K must NOT carry spec.kubeConfig — otherwise
  # kustomize-controller routes the HR/OCIRepo CRs to the spoke, which has no Flux CRDs
  # (hub-only Flux control plane; see docs/adr/0004-hub-only-flux-control-plane.md).
  [ -f "$CAPSULE_KS" ]
  run yq eval '.spec.kubeConfig == null' "$CAPSULE_KS"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
  run yq eval '.spec.path == "./pocs/capsule"' "$CAPSULE_KS"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
  run yq eval '.metadata.name == "poc-capsule"' "$CAPSULE_KS"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "clusters/hub-flux/pocs/capsule-spoke.yaml is spoke-targeted (secretRef.name=spoke-capsule-kubeconfig + key=value.yaml + path=./pocs/capsule/spoke)" {
  # Split-path pattern: the spoke-targeted K (capsule-spoke.yaml), NOT the hub-targeted K
  # (capsule.yaml), must carry the full spec.kubeConfig block with an explicit
  # secretRef key (value.yaml) — otherwise Flux silently reconciles the spoke payload
  # into the hub while reporting Ready. The kustomize-controller impersonates the spoke
  # via spoke-capsule-kubeconfig to apply pocs/capsule/spoke/*.
  [ -f "$CAPSULE_SPOKE_KS" ]
  run yq eval '.spec.kubeConfig.secretRef.name == "spoke-capsule-kubeconfig"' "$CAPSULE_SPOKE_KS"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
  run yq eval '.spec.kubeConfig.secretRef.key == "value.yaml"' "$CAPSULE_SPOKE_KS"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
  run yq eval '.spec.path == "./pocs/capsule/spoke"' "$CAPSULE_SPOKE_KS"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
  run yq eval '.metadata.name == "poc-capsule-spoke"' "$CAPSULE_SPOKE_KS"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "scripts/poc/capsule/fix-dns.sh exists, strict-mode, sources preflight-lib" {
  [ -f "$FIX_DNS_SCRIPT" ]
  run grep -E '^set -euo pipefail' "$FIX_DNS_SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- 'preflight-lib.sh' "$FIX_DNS_SCRIPT"
  [ "$status" -eq 0 ]
}

@test "fix-dns.sh stops/starts ONLY spoke-capsule (zero hub-flux/spoke-ml/spoke-apps cluster commands)" {
  [ -f "$FIX_DNS_SCRIPT" ]
  run grep -F -- 'k3d cluster stop "${POC_CLUSTER}"' "$FIX_DNS_SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- 'k3d cluster start "${POC_CLUSTER}"' "$FIX_DNS_SCRIPT"
  [ "$status" -eq 0 ]
  for cluster in hub-flux spoke-ml spoke-apps; do
    run bash -c "grep -v '^[[:space:]]*#' '$FIX_DNS_SCRIPT' | grep -F -- 'k3d cluster stop ${cluster}'"
    [ "$status" -ne 0 ]
    run bash -c "grep -v '^[[:space:]]*#' '$FIX_DNS_SCRIPT' | grep -F -- 'k3d cluster start ${cluster}'"
    [ "$status" -ne 0 ]
  done
}

@test "fix-dns.sh has ZERO flux check or flux reconcile invocations on spoke-capsule (hub-only Flux)" {
  [ -f "$FIX_DNS_SCRIPT" ]
  run bash -c "grep -v '^[[:space:]]*#' '$FIX_DNS_SCRIPT' | grep -E 'flux[[:space:]]+(check|reconcile)'"
  [ "$status" -ne 0 ]
}

@test "Taskfile.yml carries fix-dns-poc-capsule task wired to scripts/poc/capsule/fix-dns.sh" {
  [ -f "$TASKFILE" ]
  run grep -F -- 'fix-dns-poc-capsule:' "$TASKFILE"
  [ "$status" -eq 0 ]
  run grep -F -- 'bash scripts/poc/capsule/fix-dns.sh' "$TASKFILE"
  [ "$status" -eq 0 ]
}
