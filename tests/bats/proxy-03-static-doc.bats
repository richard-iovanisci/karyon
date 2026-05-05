#!/usr/bin/env bats
# tests/bats/proxy-03-static-doc.bats
# Phase 10 / Wave 0 (D-10-09 Nyquist gate)
# Static doc-shape contract for docs/poc-capsule.md (PROXY-03 H2 section + cross-link literals).
# RED until Plan 10-01 appends the 'Tenant kubeconfig delivery contract' H2 section.

load 'test_helper'

setup() {
  DOC="${REPO_ROOT}/docs/poc-capsule.md"
}

@test "PROXY-03 / D-10-09: docs/poc-capsule.md exists" {
  [ -f "$DOC" ]
}

@test "PROXY-03 / D-10-09: docs/poc-capsule.md has '## Tenant kubeconfig delivery contract' H2 section" {
  [ -f "$DOC" ]
  run grep -F -- '## Tenant kubeconfig delivery contract' "$DOC"
  [ "$status" -eq 0 ]
}

@test "PROXY-03 / D-10-09: H2 section has 'Status: Active. Phase 10' badge" {
  [ -f "$DOC" ]
  run grep -F -- 'Status:** Active. Phase 10' "$DOC"
  [ "$status" -eq 0 ]
}

@test "PROXY-03 / D-10-09: H2 section has Quickstart subsection with bash example invocation" {
  [ -f "$DOC" ]
  for literal in \
    '### Quickstart' \
    'bash scripts/poc/capsule/issue-tenant-kubeconfig.sh alpha gitops-reconciler' \
    '/tmp/alpha.kubeconfig' ; do
    run grep -F -- "$literal" "$DOC"
    [ "$status" -eq 0 ]
  done
}

@test "PROXY-03 / D-10-09: H2 section has Contract table with output channel + URL + auth + TLS rows" {
  [ -f "$DOC" ]
  for literal in \
    '### Contract' \
    'stdout' \
    'tenant-<tenant>-via-proxy' \
    'https://127.0.0.1:30443' \
    'kubectl create token' \
    'TokenRequest API' \
    'certificate-authority-data' ; do
    run grep -F -- "$literal" "$DOC"
    [ "$status" -eq 0 ]
  done
}

@test "PROXY-03 / D-10-09: H2 section has Mandatory invariants subsection (P29 leak defense)" {
  [ -f "$DOC" ]
  for literal in \
    '### Mandatory invariants' \
    'P29' \
    '${TMPDIR:-/tmp}/karyon-tenants/' \
    'realpath -m' \
    'kubeconfig-bearer-token' \
    'kind: Config' ; do
    run grep -F -- "$literal" "$DOC"
    [ "$status" -eq 0 ]
  done
}

@test "PROXY-03 / D-10-09: H2 section has Cross-references subsection — Phase 7/8/9 + capsule-on-eks.md" {
  [ -f "$DOC" ]
  for literal in \
    '### Cross-references' \
    'Phase 7' \
    'Phase 8' \
    'Phase 9' \
    'capsule-on-eks.md' \
    'IRSA' \
    'NodePort' \
    'gitops-reconciler' ; do
    run grep -F -- "$literal" "$DOC"
    [ "$status" -eq 0 ]
  done
}

@test "PROXY-03 / D-10-09: doc frontmatter scope: line removes the 'Phases 10/11 will add' Phase 10 forward-pointer" {
  [ -f "$DOC" ]
  # POSITIVE: scope: line acknowledges Phase 10 added the section
  run grep -F -- 'tenant kubeconfig delivery contract' "$DOC"
  [ "$status" -eq 0 ]
  # NEGATIVE: no longer says "Phases 10/11 will add" (forward-pointer phrasing removed)
  run grep -F -- 'Phases 10/11 will add' "$DOC"
  [ "$status" -ne 0 ]
}
