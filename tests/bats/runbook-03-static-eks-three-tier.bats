#!/usr/bin/env bats
# tests/bats/runbook-03-static-eks-three-tier.bats
# Phase 14 / Wave 0 (D-14-08 + D-13-15 Nyquist gate)
# RUNBOOK-03 / Q1 — docs/capsule-on-eks.md explicit Tier 1/2/3 labels + IRSA + tenant-workload-editor + capsule-platform-owner cross-mapping.
# RED until Plan 14-01 appends the Three-tier permission model on EKS section to docs/capsule-on-eks.md.

load 'test_helper'

setup() {
  DOC="${REPO_ROOT}/docs/capsule-on-eks.md"
}

@test "RUNBOOK-03 / Q1: docs/capsule-on-eks.md exists" {
  [ -f "$DOC" ]
}

@test "RUNBOOK-03 / Q1: doc contains 'Three-tier permission model' section" {
  [ -f "$DOC" ]
  run grep -iE '^## Three-tier permission model' "$DOC"
  [ "$status" -eq 0 ]
}

@test "RUNBOOK-03 / Q1: doc labels Tier 1 / Tier 2 / Tier 3 explicitly" {
  [ -f "$DOC" ]
  for literal in 'Tier 1' 'Tier 2' 'Tier 3'; do
    run grep -F -- "$literal" "$DOC"
    [ "$status" -eq 0 ]
  done
}

@test "RUNBOOK-03 / Q1: doc maps tiers to IRSA + tenant-workload-editor + capsule-platform-owner" {
  [ -f "$DOC" ]
  for literal in 'IRSA' 'tenant-workload-editor' 'capsule-platform-owner'; do
    run grep -F -- "$literal" "$DOC"
    [ "$status" -eq 0 ]
  done
}
