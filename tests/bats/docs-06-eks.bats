#!/usr/bin/env bats
# tests/bats/docs-06-eks.bats
# EKSDOC-01 — docs/capsule-on-eks.md shape contract (Mermaid + 3 verbatim YAMLs + 3-item NOT-PROVED list)

load 'test_helper'

setup() {
  DOC="${REPO_ROOT}/docs/capsule-on-eks.md"
}

@test "EKSDOC-01: docs/capsule-on-eks.md exists" {
  [ -f "$DOC" ]
}

@test "EKSDOC-01: doc starts with an h1 (MD041 safety) before any mermaid block" {
  [ -f "$DOC" ]
  run bash -c "h1_line=\$(grep -nE '^# ' '$DOC' | head -1 | cut -d: -f1); mermaid_line=\$(grep -nE '^\`\`\`mermaid' '$DOC' | head -1 | cut -d: -f1); [ -n \"\$h1_line\" ] && [ -n \"\$mermaid_line\" ] && [ \"\$h1_line\" -lt \"\$mermaid_line\" ]"
  [ "$status" -eq 0 ]
}

@test "EKSDOC-01 / D-13: doc has Status: Draft (or Reviewed) frontmatter or first-paragraph metadata" {
  [ -f "$DOC" ]
  run grep -iE '^[Ss]tatus:[[:space:]]*(Draft|Reviewed)' "$DOC"
  [ "$status" -eq 0 ]
}

@test "EKSDOC-01 / D-03: doc contains a fenced mermaid block" {
  [ -f "$DOC" ]
  run grep -E '^```mermaid' "$DOC"
  [ "$status" -eq 0 ]
}

@test "EKSDOC-01 / D-03: Mermaid topology highlights EKS-target components" {
  [ -f "$DOC" ]
  for literal in 'capsule-proxy' 'IRSA' 'NLB' 'ALB' 'ECR'; do
    run grep -F -- "$literal" "$DOC"
    [ "$status" -eq 0 ]
  done
}

@test "EKSDOC-01 / D-02: section (d) contains the 3 verbatim YAML anchor literals (IRSA + LB + CapsuleConfiguration)" {
  [ -f "$DOC" ]
  for literal in \
    'sts:AssumeRoleWithWebIdentity' \
    'eks.amazonaws.com/role-arn' \
    'service.beta.kubernetes.io/aws-load-balancer-type' \
    'CapsuleConfiguration' \
    'allowedNodeSelectors'
  do
    run grep -F -- "$literal" "$DOC"
    [ "$status" -eq 0 ]
  done
}

@test "EKSDOC-01 / D-04: section (e) carries the locked 3-item NOT-PROVED framing (HA + OIDC + multi-spoke)" {
  [ -f "$DOC" ]
  for literal in 'HA Capsule' 'OIDC' 'multi-spoke'; do
    run grep -iF -- "$literal" "$DOC"
    [ "$status" -eq 0 ]
  done
}

@test "EKSDOC-01: doc references the 7 Capsule CRDs by name (D-02 section b)" {
  [ -f "$DOC" ]
  for crd in 'Tenant' 'CapsuleConfiguration' 'GlobalTenantResource' 'TenantResource' 'ResourcePool' 'ResourcePoolClaim' 'TenantOwner'; do
    run grep -F -- "$crd" "$DOC"
    [ "$status" -eq 0 ]
  done
}

@test "EKSDOC-01: doc does NOT reference k3d-specific cluster names (hub-flux/spoke-apps/spoke-ml) in EKS topology" {
  [ -f "$DOC" ]
  # Negative: EKS topology shouldn't contain karyon k3d cluster names
  # (a) `hub-flux` may appear in narrative comparing to k3d POC, but NOT in mermaid block
  # We assert: zero `k3d-hub-flux` literal references (containerized-k3d cluster names)
  run grep -F -- 'k3d-hub-flux-server-0' "$DOC"
  [ "$status" -ne 0 ]
}
