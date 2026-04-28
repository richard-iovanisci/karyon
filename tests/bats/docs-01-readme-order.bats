#!/usr/bin/env bats
# tests/bats/docs-01-readme-order.bats
# Phase 6 Wave 0 static contract for DOCS-01: README.md walks fresh-clone path
# in locked order across 10 sections; links to all v1 docs and 5 ADRs; carries
# a 60-second TL;DR ahead of any installation step.

load 'test_helper'

setup() {
  README="${REPO_ROOT}/README.md"
}

@test "DOCS-01: README.md exists and starts with an h1 (MD041)" {
  [ -f "$README" ]
  run bash -c "head -1 '$README' | grep -E '^# '"
  [ "$status" -eq 0 ]
}

@test "DOCS-01 (D-01): README walks the locked fresh-clone path in order" {
  [ -f "$README" ]
  previous=0
  for literal in \
    'Windows prereqs' \
    'WSL config' \
    'Docker install' \
    'NVIDIA setup' \
    'tools install' \
    'cluster creation' \
    'Flux bootstrap' \
    'spoke registration' \
    'example deploy' \
    'teardown'
  do
    line="$(grep -niF -- "$literal" "$README" | head -1 | cut -d: -f1)"
    [ -n "$line" ]
    [ "$line" -gt "$previous" ]
    previous="$line"
  done
}

@test "DOCS-01: README links to all v1 docs (architecture, gpu-notes, rebuild-runbook, flux-hub-spoke, wsl-networking) and the 5 ADRs" {
  [ -f "$README" ]
  for literal in \
    'docs/architecture.md' \
    'docs/gpu-notes.md' \
    'docs/rebuild-runbook.md' \
    'docs/flux-hub-spoke.md' \
    'docs/wsl-networking.md' \
    'docs/adr/0001-single-wsl2-shared-docker-network.md' \
    'docs/adr/0002-k3d-over-kind.md' \
    'docs/adr/0003-flux-over-argocd.md' \
    'docs/adr/0004-hub-only-flux-control-plane.md' \
    'docs/adr/0005-kubernetes-version-pin.md'
  do
    run grep -F -- "$literal" "$README"
    [ "$status" -eq 0 ]
  done
}

@test "DOCS-01: README contains a 60-second TL;DR ahead of any installation step" {
  [ -f "$README" ]
  run bash -c "tldr_line=\$(grep -niE '(tl;dr|quick ?start|60.second)' '$README' | head -1 | cut -d: -f1); first_install=\$(grep -niE '(windows prereqs|wsl config)' '$README' | head -1 | cut -d: -f1); [ -n \"\$tldr_line\" ] && [ -n \"\$first_install\" ] && [ \"\$tldr_line\" -lt \"\$first_install\" ]"
  [ "$status" -eq 0 ]
}
