#!/usr/bin/env bats
# tests/bats/bootstrap-flux-02-docs.bats
# Static-grep check (FLUX-05 / DOCS-03 / D-14 / D-15 / D-16):
# docs/flux-hub-spoke.md carries the 3 patch-surface rules, the D-15 kustomize-controller
# patch example, the D-16 skip-message reference, and the D-14 Phase-4 HTML-comment stub.

load 'test_helper'

setup() {
  DOC="${REPO_ROOT}/docs/flux-hub-spoke.md"
}

teardown() {
  :
}

@test "FLUX-05 / DOCS-03: docs/flux-hub-spoke.md documents the 3 patch-surface rules" {
  [ -f "$DOC" ]
  # Rule 1: gotk-*.yaml are bootstrap-managed
  run grep -F -- 'gotk-components.yaml' "$DOC"
  [ "$status" -eq 0 ]
  run grep -F -- 'gotk-sync.yaml' "$DOC"
  [ "$status" -eq 0 ]
  run grep -F -- 'bootstrap-managed' "$DOC"
  [ "$status" -eq 0 ]
  # Rule 2: kustomization.yaml IS the patch surface (case-insensitive - docs prose)
  run grep -iE 'patch surface' "$DOC"
  [ "$status" -eq 0 ]
  # Rule 3: --path is effectively immutable after first run
  run grep -F -- '--path' "$DOC"
  [ "$status" -eq 0 ]
  run grep -iF -- 'immutable' "$DOC"
  [ "$status" -eq 0 ]
}

@test "D-15: docs/flux-hub-spoke.md contains the kustomize-controller memory patch example" {
  [ -f "$DOC" ]
  run grep -F -- 'kustomize-controller' "$DOC"
  [ "$status" -eq 0 ]
  run grep -F -- '/spec/template/spec/containers/0/resources/limits/memory' "$DOC"
  [ "$status" -eq 0 ]
  run grep -F -- '1Gi' "$DOC"
  [ "$status" -eq 0 ]
}

@test "D-16: docs/flux-hub-spoke.md references the bootstrap-flux.sh skip-message contract" {
  [ -f "$DOC" ]
  # The exact skip-message literal the script emits (ties doc to observable script behavior).
  run grep -F -- 'already done, skipping: flux bootstrap' "$DOC"
  [ "$status" -eq 0 ]
}

@test "D-14: docs/flux-hub-spoke.md contains the Phase 4 HTML-comment stub" {
  [ -f "$DOC" ]
  # HTML comment placeholder for the Phase 4 hub-spoke reconciliation section.
  run grep -F -- '<!-- Phase 4:' "$DOC"
  [ "$status" -eq 0 ]
}
