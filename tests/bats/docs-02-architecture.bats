#!/usr/bin/env bats
# tests/bats/docs-02-architecture.bats
# Phase 6 Wave 0 static contract for DOCS-02: docs/architecture.md starts with
# an h1 before the Mermaid block (MD041), contains a fenced mermaid block, and
# documents the 3-cluster topology with required nodes (clusters, ports, network,
# spec.kubeConfig, and the 4 flux-system controllers).

load 'test_helper'

setup() {
  DOC="${REPO_ROOT}/docs/architecture.md"
}

@test "DOCS-02 (Pitfall 4): docs/architecture.md starts with an h1 before the Mermaid block (MD041 safety)" {
  [ -f "$DOC" ]
  run bash -c "h1_line=\$(grep -nE '^# ' '$DOC' | head -1 | cut -d: -f1); mermaid_line=\$(grep -nE '^\`\`\`mermaid' '$DOC' | head -1 | cut -d: -f1); [ -n \"\$h1_line\" ] && [ -n \"\$mermaid_line\" ] && [ \"\$h1_line\" -lt \"\$mermaid_line\" ]"
  [ "$status" -eq 0 ]
}

@test "DOCS-02 (D-03): docs/architecture.md contains a fenced mermaid block" {
  [ -f "$DOC" ]
  run grep -E '^```mermaid' "$DOC"
  [ "$status" -eq 0 ]
}

@test "DOCS-02 (D-03): Mermaid topology contains all 3 clusters with API ports" {
  [ -f "$DOC" ]
  for literal in \
    'hub-flux' \
    'spoke-ml' \
    'spoke-apps' \
    '6443' \
    '6444' \
    '6445'
  do
    run grep -F -- "$literal" "$DOC"
    [ "$status" -eq 0 ]
  done
}

@test "DOCS-02 (D-03): Mermaid topology contains the k8s-net 172.30.0.0/16 network and spec.kubeConfig arrows" {
  [ -f "$DOC" ]
  for literal in \
    'k8s-net' \
    '172.30.0.0/16' \
    'spec.kubeConfig'
  do
    run grep -F -- "$literal" "$DOC"
    [ "$status" -eq 0 ]
  done
}

@test "DOCS-02 (D-03): Mermaid topology lists the four flux-system controllers" {
  [ -f "$DOC" ]
  for literal in \
    'source-controller' \
    'kustomize-controller' \
    'helm-controller' \
    'notification-controller'
  do
    run grep -F -- "$literal" "$DOC"
    [ "$status" -eq 0 ]
  done
}
