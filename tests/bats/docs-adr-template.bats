#!/usr/bin/env bats
# tests/bats/docs-adr-template.bats
# Phase 6 Wave 0 static contract for DOCS-06..10: each of the 5 ADR files exists
# with locked slug + 4 Nygard sections (Status/Context/Decision/Consequences) +
# `Status: Accepted` in the first 10 lines + per-ADR semantic keywords.

load 'test_helper'

setup() {
  ADR_DIR="${REPO_ROOT}/docs/adr"
  ADRS=(
    "0001-single-wsl2-shared-docker-network.md"
    "0002-k3d-over-kind.md"
    "0003-flux-over-argocd.md"
    "0004-hub-only-flux-control-plane.md"
    "0005-kubernetes-version-pin.md"
    "0008-capsule-multi-tenancy-graduation.md"
  )
}

@test "DOCS-06..10 (D-02): all five ADR files exist with locked slugs" {
  for slug in "${ADRS[@]}"; do
    [ -f "${ADR_DIR}/${slug}" ]
  done
}

@test "DOCS-06..10 (D-02): each ADR contains the 4 Nygard sections in order" {
  for slug in "${ADRS[@]}"; do
    f="${ADR_DIR}/${slug}"
    [ -f "$f" ]
    previous=0
    for literal in \
      '## Status' \
      '## Context' \
      '## Decision' \
      '## Consequences'
    do
      line="$(grep -nF -- "$literal" "$f" | head -1 | cut -d: -f1)"
      [ -n "$line" ]
      [ "$line" -gt "$previous" ]
      previous="$line"
    done
  done
}

@test "DOCS-06..10 (D-02): each ADR has Status: Accepted in the first 10 lines" {
  for slug in "${ADRS[@]}"; do
    f="${ADR_DIR}/${slug}"
    [ -f "$f" ]
    run bash -c "head -n 10 '$f' | grep -F 'Accepted'"
    [ "$status" -eq 0 ]
  done
}

@test "DOCS-06: ADR-001 captures single-WSL2 + shared k8s-net Docker network" {
  f="${ADR_DIR}/0001-single-wsl2-shared-docker-network.md"
  [ -f "$f" ]
  for keyword in \
    'WSL2' \
    'k8s-net' \
    'Docker'
  do
    run grep -iF -- "$keyword" "$f"
    [ "$status" -eq 0 ]
  done
}

@test "DOCS-07: ADR-002 captures k3d-over-Kind decision" {
  f="${ADR_DIR}/0002-k3d-over-kind.md"
  [ -f "$f" ]
  for keyword in \
    'k3d' \
    'Kind' \
    '--gpus all'
  do
    run grep -iF -- "$keyword" "$f"
    [ "$status" -eq 0 ]
  done
}

@test "DOCS-08: ADR-003 captures Flux-over-ArgoCD with ApplicationSet trade-off + migration note" {
  f="${ADR_DIR}/0003-flux-over-argocd.md"
  [ -f "$f" ]
  for keyword in \
    'Flux' \
    'ArgoCD' \
    'ApplicationSet' \
    'migration'
  do
    run grep -iF -- "$keyword" "$f"
    [ "$status" -eq 0 ]
  done
}

@test "DOCS-09: ADR-004 captures hub-only Flux control plane" {
  f="${ADR_DIR}/0004-hub-only-flux-control-plane.md"
  [ -f "$f" ]
  for keyword in \
    'hub' \
    'spec.kubeConfig' \
    'controller'
  do
    run grep -iF -- "$keyword" "$f"
    [ "$status" -eq 0 ]
  done
}

@test "DOCS-10 (specifics): ADR-005 pins k3s v1.34.6-k3s1 and CUDA 12.8+, notes current line + RTX 5090 sm_120 floor" {
  f="${ADR_DIR}/0005-kubernetes-version-pin.md"
  [ -f "$f" ]
  for literal in \
    'v1.34.6-k3s1' \
    '12.8' \
    'RTX 5090' \
    'sm_120' \
    'current line'
  do
    run grep -iF -- "$literal" "$f"
    [ "$status" -eq 0 ]
  done
}

@test "VAL-06 (D-11-14): ADR-008 captures Capsule graduation with ADR-004 cross-reference" {
  f="${ADR_DIR}/0008-capsule-multi-tenancy-graduation.md"
  [ -f "$f" ]
  for keyword in \
    'Capsule' \
    'tenant' \
    'graduation' \
    'ADR-004' \
    'D-11-14' ; do
    run grep -iF -- "$keyword" "$f"
    [ "$status" -eq 0 ]
  done
}
