#!/usr/bin/env bats
# tests/bats/seed-02-live-existing-tenants.bats
# Phase 13 / Wave 0 (D-13-15 Nyquist gate)
# SEED-01 — GlobalTenantResource propagation to existing tenant namespaces:
#   - alpha-app1, tenant-alpha, bravo-app1, tenant-bravo
# Each namespace must carry a Ready hello-world workload pod + a hello-world
# Deployment with the karyon.io/managed-by label + hello-world Service port 80.
#
# AMENDED (ADR-008 addendum 2026-07-06, supersedes D-13-12): the GTR now seeds a
# 1-replica Deployment instead of a bare Pod (immutable Pod spec put the Capsule
# controller in a permanent resync error loop). Pods are located via the
# app=hello-world template label (Deployment pods carry a -<hash> suffix); the
# karyon.io/managed-by provenance label is asserted on the Deployment — the
# object the GTR actually replicates — not on its child pods.

load 'test_helper'

setup() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
}

# alpha-app1 / bravo-app1 are Phase 13 fixture namespaces created by the tenants
# quota live suites, not by GitOps — skip their blocks when absent so this suite
# is honest standalone.
require_ns() {
  kubectl --context=k3d-spoke-capsule get namespace "$1" >/dev/null 2>&1 \
    || skip "fixture namespace $1 absent; run the tenants quota live suite first"
}

# Poll (3x10s) for a Ready pod selected by app=hello-world in the namespace.
assert_hello_world_pod_ready() {
  local ns="$1" i status_val
  for i in 1 2 3; do
    status_val=$(kubectl --context=k3d-spoke-capsule -n "$ns" get pods -l app=hello-world \
      -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
    [[ "$status_val" == "True" ]] && return 0
    [[ $i -lt 3 ]] && sleep 10
  done
  echo "Last observed hello-world pod Ready status in ${ns}: '${status_val}'"
  return 1
}

# Assert the replicated Deployment carries the GTR provenance label.
assert_hello_world_deploy_label() {
  local ns="$1" val
  val=$(kubectl --context=k3d-spoke-capsule -n "$ns" get deployment hello-world \
    -o jsonpath='{.metadata.labels.karyon\.io/managed-by}' 2>/dev/null || true)
  [ "$val" = "capsule-global-tenant-resource" ]
}

# Assert the replicated Service exists with port 80.
assert_hello_world_service() {
  local ns="$1" port
  port=$(kubectl --context=k3d-spoke-capsule -n "$ns" get svc hello-world \
    -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || true)
  [ "$port" = "80" ]
}

# ---- tenant-alpha ----

@test "SEED-01 (tenant-alpha): hello-world pod Ready=True within 30s (3x10s poll)" {
  assert_hello_world_pod_ready tenant-alpha
}

@test "SEED-01 (tenant-alpha): hello-world Deployment carries karyon.io/managed-by=capsule-global-tenant-resource label" {
  assert_hello_world_deploy_label tenant-alpha
}

@test "SEED-01 (tenant-alpha): hello-world Service exists with port 80" {
  assert_hello_world_service tenant-alpha
}

# ---- alpha-app1 ----

@test "SEED-01 (alpha-app1): hello-world pod Ready=True within 30s (3x10s poll)" {
  require_ns alpha-app1
  assert_hello_world_pod_ready alpha-app1
}

@test "SEED-01 (alpha-app1): hello-world Deployment carries karyon.io/managed-by=capsule-global-tenant-resource label" {
  require_ns alpha-app1
  assert_hello_world_deploy_label alpha-app1
}

@test "SEED-01 (alpha-app1): hello-world Service exists with port 80" {
  require_ns alpha-app1
  assert_hello_world_service alpha-app1
}

# ---- tenant-bravo ----

@test "SEED-01 (tenant-bravo): hello-world pod Ready=True within 30s (3x10s poll)" {
  assert_hello_world_pod_ready tenant-bravo
}

@test "SEED-01 (tenant-bravo): hello-world Deployment carries karyon.io/managed-by=capsule-global-tenant-resource label" {
  assert_hello_world_deploy_label tenant-bravo
}

@test "SEED-01 (tenant-bravo): hello-world Service exists with port 80" {
  assert_hello_world_service tenant-bravo
}

# ---- bravo-app1 ----

@test "SEED-01 (bravo-app1): hello-world pod Ready=True within 30s (3x10s poll)" {
  require_ns bravo-app1
  assert_hello_world_pod_ready bravo-app1
}

@test "SEED-01 (bravo-app1): hello-world Deployment carries karyon.io/managed-by=capsule-global-tenant-resource label" {
  require_ns bravo-app1
  assert_hello_world_deploy_label bravo-app1
}

@test "SEED-01 (bravo-app1): hello-world Service exists with port 80" {
  require_ns bravo-app1
  assert_hello_world_service bravo-app1
}
