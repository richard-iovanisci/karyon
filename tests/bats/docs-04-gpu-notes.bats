#!/usr/bin/env bats
# tests/bats/docs-04-gpu-notes.bats
# Phase 6 Wave 0 static contract for DOCS-04: docs/gpu-notes.md starts with an
# h1; covers the 3-part k3d GPU contract (default-runtime + nvidia/cuda +
# config.toml.tmpl) and the RTX 5090 / sm_120 / CUDA 12.8+ floor.

load 'test_helper'

setup() {
  DOC="${REPO_ROOT}/docs/gpu-notes.md"
}

@test "DOCS-04: docs/gpu-notes.md exists and starts with an h1" {
  [ -f "$DOC" ]
  run bash -c "head -1 '$DOC' | grep -E '^# '"
  [ "$status" -eq 0 ]
}

@test "DOCS-04: gpu-notes covers the 3-part k3d GPU contract" {
  [ -f "$DOC" ]
  for literal in \
    'default-runtime' \
    'nvidia/cuda' \
    'config.toml.tmpl'
  do
    run grep -F -- "$literal" "$DOC"
    [ "$status" -eq 0 ]
  done
}

@test "DOCS-04: gpu-notes covers the RTX 5090 / sm_120 / CUDA 12.8+ floor" {
  [ -f "$DOC" ]
  for literal in \
    'RTX 5090' \
    'sm_120' \
    '12.8'
  do
    run grep -F -- "$literal" "$DOC"
    [ "$status" -eq 0 ]
  done
}
