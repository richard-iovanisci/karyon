#!/usr/bin/env bats
# tests/bats/poc-cluster-01-static.bats
# CAPCLU-01/02/03/04 — create-cluster.sh + fix-dns.sh + clusters/hub-flux/pocs/capsule.yaml + Taskfile + docs/poc-capsule.md

load 'test_helper'

setup() {
  CREATE_SCRIPT="${REPO_ROOT}/scripts/poc/capsule/create-cluster.sh"
  FIX_DNS_SCRIPT="${REPO_ROOT}/scripts/poc/capsule/fix-dns.sh"
  CAPSULE_KS="${REPO_ROOT}/clusters/hub-flux/pocs/capsule.yaml"
  CAPSULE_SPOKE_KS="${REPO_ROOT}/clusters/hub-flux/pocs/capsule-spoke.yaml"
  TASKFILE="${REPO_ROOT}/Taskfile.yml"
  POC_DOC="${REPO_ROOT}/docs/poc-capsule.md"
}

@test "CAPCLU-01: scripts/poc/capsule/create-cluster.sh exists, strict-mode, sources preflight-lib" {
  [ -f "$CREATE_SCRIPT" ]
  run grep -E '^set -euo pipefail' "$CREATE_SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- 'preflight-lib.sh' "$CREATE_SCRIPT"
  [ "$status" -eq 0 ]
}

@test "CAPCLU-01 / D-10: create-cluster.sh pins POC_CLUSTER=spoke-capsule, port 6446, NodePort 30443, k8s-net" {
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

@test "CAPCLU-01 / D-10: create-cluster.sh invokes k3d cluster create with --tls-san k3d-spoke-capsule-server-0 and --port 30443:30443@loadbalancer" {
  [ -f "$CREATE_SCRIPT" ]
  run grep -F -- 'k3d-spoke-capsule-server-0' "$CREATE_SCRIPT"
  [ "$status" -eq 0 ]
  # Per RESEARCH.md §"Open Questions (RESOLVED)" #1: lock @loadbalancer so the host port lives on
  # the serverlb container (matching v0.18's drift-verify pattern which inspects serverlb only).
  run grep -F -- '30443:30443@loadbalancer' "$CREATE_SCRIPT"
  [ "$status" -eq 0 ]
}

@test "CAPCLU-01: create-cluster.sh idempotency — drift verify on image, network, ports" {
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

@test "CAPCLU-01: create-cluster.sh invokes preflight as gate" {
  [ -f "$CREATE_SCRIPT" ]
  run grep -F -- 'preflight.sh' "$CREATE_SCRIPT"
  [ "$status" -eq 0 ]
}

@test "CAPCLU-02 / D-08-12: clusters/hub-flux/pocs/capsule.yaml is hub-targeted (path=./pocs/capsule, NO spec.kubeConfig)" {
  # D-08-12 (gap-close 2026-04-29) evolved Phase 7 P40/P18 — see poc-mount-01-static.bats for
  # the canonical dual-K split assertions. Hub-targeted K must NOT carry spec.kubeConfig
  # (otherwise kustomize-controller routes HR/OCIRepo CRs to spoke, which has no Flux CRDs
  # per ADR-004; verified by server-side dry-run in 08-VERIFICATION.md G-04).
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

@test "CAPCLU-02 / D-11 / P40 / D-08-12: clusters/hub-flux/pocs/capsule-spoke.yaml is spoke-targeted (secretRef.name=spoke-capsule-kubeconfig + key=value.yaml + path=./pocs/capsule/spoke)" {
  # D-08-12 split-path pattern: P40/P18 invariant lives on the spoke-targeted K
  # (capsule-spoke.yaml), NOT on the hub-targeted K (capsule.yaml). The kustomize-controller
  # impersonates spoke via spoke-capsule-kubeconfig to apply pocs/capsule/spoke/* (Phase 9 Tenants).
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

@test "CAPCLU-03: scripts/poc/capsule/fix-dns.sh exists, strict-mode, sources preflight-lib" {
  [ -f "$FIX_DNS_SCRIPT" ]
  run grep -E '^set -euo pipefail' "$FIX_DNS_SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- 'preflight-lib.sh' "$FIX_DNS_SCRIPT"
  [ "$status" -eq 0 ]
}

@test "CAPCLU-03 / D-16: fix-dns.sh stops/starts ONLY spoke-capsule (zero hub-flux/spoke-ml/spoke-apps cluster commands)" {
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

@test "CAPCLU-03 / D-17 / ADR-004: fix-dns.sh has ZERO flux check or flux reconcile invocations on spoke-capsule" {
  [ -f "$FIX_DNS_SCRIPT" ]
  run bash -c "grep -v '^[[:space:]]*#' '$FIX_DNS_SCRIPT' | grep -E 'flux[[:space:]]+(check|reconcile)'"
  [ "$status" -ne 0 ]
}

@test "CAPCLU-03: Taskfile.yml carries fix-dns-poc-capsule task wired to scripts/poc/capsule/fix-dns.sh" {
  [ -f "$TASKFILE" ]
  run grep -F -- 'fix-dns-poc-capsule:' "$TASKFILE"
  [ "$status" -eq 0 ]
  run grep -F -- 'bash scripts/poc/capsule/fix-dns.sh' "$TASKFILE"
  [ "$status" -eq 0 ]
}

@test "CAPCLU-04: docs/poc-capsule.md exists with Host restart recovery + Troubleshooting sections" {
  [ -f "$POC_DOC" ]
  run grep -iE '^#+[[:space:]]+Host restart recovery' "$POC_DOC"
  [ "$status" -eq 0 ]
  run grep -iE '^#+[[:space:]]+Troubleshooting' "$POC_DOC"
  [ "$status" -eq 0 ]
  run grep -F -- 'task fix-dns-poc-capsule' "$POC_DOC"
  [ "$status" -eq 0 ]
  run grep -F -- '30443' "$POC_DOC"
  [ "$status" -eq 0 ]
}
