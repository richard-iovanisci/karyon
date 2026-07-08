#!/usr/bin/env bats
# tests/bats/capsule-install-03-static-values.bats
# Chart values literals — per-hook key paths verified against the upstream chart docs.

load 'test_helper'

setup() {
  OPERATOR_HR="${REPO_ROOT}/pocs/capsule/operator/helmrelease.yaml"
  PROXY_HR="${REPO_ROOT}/pocs/capsule/proxy/helmrelease.yaml"
}

@test "CAP-01 / D-08-04: operator values.tls.enableController=true (built-in certgen)" {
  [ -f "$OPERATOR_HR" ]
  run yq eval '.spec.values.tls.enableController == true' "$OPERATOR_HR"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "CAP-01 / anti-pattern: operator values.certManager.generateCertificates=false (NO cert-manager dep)" {
  [ -f "$OPERATOR_HR" ]
  run yq eval '.spec.values.certManager.generateCertificates == false' "$OPERATOR_HR"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "CAP-01 / D-08-03: operator values.webhooks.hooks.tenants.failurePolicy=Ignore (per-hook key path — RESEARCH-verified)" {
  [ -f "$OPERATOR_HR" ]
  run yq eval '.spec.values.webhooks.hooks.tenants.failurePolicy == "Ignore"' "$OPERATOR_HR"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

# INVERTED 2026-07-06: the namespaces hook is the ONE hook that MUST stay at the
# chart-default `Fail`. The original blanket-Ignore created a cold-bootstrap
# race: a tenant-labeled Namespace admitted while capsule-webhook-service is not yet
# Ready skips the ownerReference mutation, then the companion validating webhook
# deadlocks all UPDATE/DELETE on the labeled-but-unowned namespace (unrecoverable
# without scaling the controller to 0). Root cause + fix: commit c89f1b2 +
# docs/rca/capsule-namespace-webhook-deadlock.md + docs/adr/0008 addendum (2026-05-27).
@test "CAP-01 / c89f1b2 regression guard: operator values.webhooks.hooks.namespaces.failurePolicy=Fail (chart default; NEVER revert to Ignore)" {
  [ -f "$OPERATOR_HR" ]
  run yq eval '.spec.values.webhooks.hooks.namespaces.failurePolicy == "Fail"' "$OPERATOR_HR"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "CAP-01 / D-08-03: operator values.webhooks.hooks.pods.failurePolicy=Ignore" {
  [ -f "$OPERATOR_HR" ]
  run yq eval '.spec.values.webhooks.hooks.pods.failurePolicy == "Ignore"' "$OPERATOR_HR"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "CAP-01: operator replicaCount=1 (POC simplification per ADR-008 framing)" {
  [ -f "$OPERATOR_HR" ]
  run yq eval '.spec.values.replicaCount == 1' "$OPERATOR_HR"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "CAP-01 / anti-umbrella explicit: operator values.proxy.enabled=false" {
  [ -f "$OPERATOR_HR" ]
  run yq eval '.spec.values.proxy.enabled == false' "$OPERATOR_HR"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "CAP-02: proxy values.service.type=NodePort" {
  [ -f "$PROXY_HR" ]
  run yq eval '.spec.values.service.type == "NodePort"' "$PROXY_HR"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "CAP-02 / D-10 / Phase 7 inheritance: proxy values.service.nodePort=30443" {
  [ -f "$PROXY_HR" ]
  run yq eval '.spec.values.service.nodePort == 30443' "$PROXY_HR"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "CAP-02 / P33: proxy values.options.additionalSANs contains 127.0.0.1 AND localhost (RESEARCH-verified key path: options.additionalSANs, NOT tls.additionalSANs)" {
  [ -f "$PROXY_HR" ]
  run yq eval '(.spec.values.options.additionalSANs | contains(["127.0.0.1"])) == true and (.spec.values.options.additionalSANs | contains(["localhost"])) == true' "$PROXY_HR"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}
