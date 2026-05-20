#!/usr/bin/env bats
# tests/bats/runbook-02-static-checklist.bats
# Phase 14 / Wave 0 (D-14-08 + D-13-15 Nyquist gate)
# RUNBOOK-02 — pre-demo checklist executable snippets (D-14-05): fix-dns, kubeconfig minting, charlie reset.
# RED until Plan 14-01 lands the 6-act demo runbook.

load 'test_helper'

setup() {
  DOC="${REPO_ROOT}/docs/poc-capsule-demo.md"
}

@test "RUNBOOK-02 / D-14-05: pre-demo checklist section exists" {
  [ -f "$DOC" ]
  run grep -iE '^## Pre-demo checklist' "$DOC"
  [ "$status" -eq 0 ]
}

@test "RUNBOOK-02 / D-14-05: checklist references task fix-dns-poc-capsule" {
  [ -f "$DOC" ]
  run grep -F -- 'task fix-dns-poc-capsule' "$DOC"
  [ "$status" -eq 0 ]
}

@test "RUNBOOK-02 / D-14-05: checklist mints platform-owner kubeconfig" {
  [ -f "$DOC" ]
  run grep -F -- 'issue-platform-owner-kubeconfig.sh' "$DOC"
  [ "$status" -eq 0 ]
}

@test "RUNBOOK-02 / D-14-05: checklist mints tenant-owner kubeconfigs (alpha + bravo)" {
  [ -f "$DOC" ]
  for literal in \
    'issue-tenant-kubeconfig.sh alpha human-tenant-owner' \
    'issue-tenant-kubeconfig.sh bravo human-tenant-owner'
  do
    run grep -F -- "$literal" "$DOC"
    [ "$status" -eq 0 ]
  done
}

@test "RUNBOOK-02 / D-14-03 idempotency: checklist resets charlie tenant" {
  [ -f "$DOC" ]
  run grep -F -- 'delete tenant charlie --ignore-not-found' "$DOC"
  [ "$status" -eq 0 ]
}
