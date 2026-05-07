#!/usr/bin/env bats
# tests/bats/push-gate-03-static-tenant-ns-label.bats
# Phase 11 D-11-03 -- tenant home namespace YAML carries capsule.clastix.io/tenant=<name> label.
# RED until Plan 11-01 lands the edits (Plan 10-02 used --as=alpha/bravo impersonation; this
# is the GitOps source so first push reconciles cleanly).

load 'test_helper'

setup() {
  NS_ALPHA="${REPO_ROOT}/pocs/capsule/spoke/tenants/alpha/namespace.yaml"
  NS_BRAVO="${REPO_ROOT}/pocs/capsule/spoke/tenants/bravo/namespace.yaml"
  K_ALPHA="${REPO_ROOT}/pocs/capsule/spoke/tenants/alpha/kustomization.yaml"
  K_BRAVO="${REPO_ROOT}/pocs/capsule/spoke/tenants/bravo/kustomization.yaml"
}

@test "D-11-03: alpha/namespace.yaml has metadata.labels.capsule.clastix.io/tenant=alpha" {
  [ -f "$NS_ALPHA" ]
  run yq eval '.metadata.labels."capsule.clastix.io/tenant" == "alpha"' "$NS_ALPHA"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "D-11-03: bravo/namespace.yaml has metadata.labels.capsule.clastix.io/tenant=bravo" {
  [ -f "$NS_BRAVO" ]
  run yq eval '.metadata.labels."capsule.clastix.io/tenant" == "bravo"' "$NS_BRAVO"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "D-11-07: tenant kustomizations list tenant.yaml before labeled namespace.yaml" {
  [ -f "$K_ALPHA" ]
  [ -f "$K_BRAVO" ]
  run yq eval '.resources[0] == "tenant.yaml" and .resources[1] == "namespace.yaml" and .resources[2] == "sa.yaml"' "$K_ALPHA"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
  run yq eval '.resources[0] == "tenant.yaml" and .resources[1] == "namespace.yaml" and .resources[2] == "sa.yaml"' "$K_BRAVO"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "D-11-07: rendered spoke kustomization emits Tenant CRs before labeled Namespaces" {
  run bash -c '
    set -euo pipefail
    if command -v kustomize >/dev/null 2>&1; then
      kustomize build "$1"
    else
      kubectl kustomize "$1"
    fi \
      | yq eval ".kind + \"/\" + .metadata.name" - \
      | sed "/^---$/d" \
      | awk "
          \$0 == \"Tenant/alpha\" { alpha_tenant = NR }
          \$0 == \"Namespace/tenant-alpha\" { alpha_ns = NR }
          \$0 == \"Tenant/bravo\" { bravo_tenant = NR }
          \$0 == \"Namespace/tenant-bravo\" { bravo_ns = NR }
          END { exit !(alpha_tenant && alpha_ns && bravo_tenant && bravo_ns && alpha_tenant < alpha_ns && bravo_tenant < bravo_ns) }
        "
  ' _ "${REPO_ROOT}/pocs/capsule/spoke"
  [ "$status" -eq 0 ]
}
