#!/usr/bin/env bats
# tests/bats/seed-02-live-existing-tenants.bats
# Phase 13 / Wave 0 (D-13-15 Nyquist gate)
# SEED-01 — GlobalTenantResource propagation to existing tenant namespaces:
#   - alpha-app1, tenant-alpha, bravo-app1, tenant-bravo
# Each namespace must carry hello-world Pod Ready=True + karyon.io/managed-by label
# + hello-world Service with port 80.
# RED until Plan 13-03 lands GTR + Flux reconciles propagation.

load 'test_helper'

setup() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
}

# ---- tenant-alpha ----

@test "SEED-01 (tenant-alpha): hello-world Pod Ready=True within 30s (3x10s poll)" {
  local i status_val
  for i in 1 2 3; do
    status_val=$(kubectl --context=k3d-spoke-capsule -n tenant-alpha get pod hello-world \
      -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
    [[ "$status_val" == "True" ]] && return 0
    [[ $i -lt 3 ]] && sleep 10
  done
  echo "Last observed Pod Ready status in tenant-alpha: '$status_val'"
  return 1
}

@test "SEED-01 (tenant-alpha): hello-world Pod carries karyon.io/managed-by=capsule-global-tenant-resource label" {
  local val
  val=$(kubectl --context=k3d-spoke-capsule -n tenant-alpha get pod hello-world \
    -o jsonpath='{.metadata.labels.karyon\.io/managed-by}' 2>/dev/null || true)
  [ "$val" = "capsule-global-tenant-resource" ]
}

@test "SEED-01 (tenant-alpha): hello-world Service exists with port 80" {
  local port
  port=$(kubectl --context=k3d-spoke-capsule -n tenant-alpha get svc hello-world \
    -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || true)
  [ "$port" = "80" ]
}

# ---- alpha-app1 ----

@test "SEED-01 (alpha-app1): hello-world Pod Ready=True within 30s (3x10s poll)" {
  local i status_val
  for i in 1 2 3; do
    status_val=$(kubectl --context=k3d-spoke-capsule -n alpha-app1 get pod hello-world \
      -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
    [[ "$status_val" == "True" ]] && return 0
    [[ $i -lt 3 ]] && sleep 10
  done
  echo "Last observed Pod Ready status in alpha-app1: '$status_val'"
  return 1
}

@test "SEED-01 (alpha-app1): hello-world Pod carries karyon.io/managed-by=capsule-global-tenant-resource label" {
  local val
  val=$(kubectl --context=k3d-spoke-capsule -n alpha-app1 get pod hello-world \
    -o jsonpath='{.metadata.labels.karyon\.io/managed-by}' 2>/dev/null || true)
  [ "$val" = "capsule-global-tenant-resource" ]
}

@test "SEED-01 (alpha-app1): hello-world Service exists with port 80" {
  local port
  port=$(kubectl --context=k3d-spoke-capsule -n alpha-app1 get svc hello-world \
    -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || true)
  [ "$port" = "80" ]
}

# ---- tenant-bravo ----

@test "SEED-01 (tenant-bravo): hello-world Pod Ready=True within 30s (3x10s poll)" {
  local i status_val
  for i in 1 2 3; do
    status_val=$(kubectl --context=k3d-spoke-capsule -n tenant-bravo get pod hello-world \
      -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
    [[ "$status_val" == "True" ]] && return 0
    [[ $i -lt 3 ]] && sleep 10
  done
  echo "Last observed Pod Ready status in tenant-bravo: '$status_val'"
  return 1
}

@test "SEED-01 (tenant-bravo): hello-world Pod carries karyon.io/managed-by=capsule-global-tenant-resource label" {
  local val
  val=$(kubectl --context=k3d-spoke-capsule -n tenant-bravo get pod hello-world \
    -o jsonpath='{.metadata.labels.karyon\.io/managed-by}' 2>/dev/null || true)
  [ "$val" = "capsule-global-tenant-resource" ]
}

@test "SEED-01 (tenant-bravo): hello-world Service exists with port 80" {
  local port
  port=$(kubectl --context=k3d-spoke-capsule -n tenant-bravo get svc hello-world \
    -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || true)
  [ "$port" = "80" ]
}

# ---- bravo-app1 ----

@test "SEED-01 (bravo-app1): hello-world Pod Ready=True within 30s (3x10s poll)" {
  local i status_val
  for i in 1 2 3; do
    status_val=$(kubectl --context=k3d-spoke-capsule -n bravo-app1 get pod hello-world \
      -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
    [[ "$status_val" == "True" ]] && return 0
    [[ $i -lt 3 ]] && sleep 10
  done
  echo "Last observed Pod Ready status in bravo-app1: '$status_val'"
  return 1
}

@test "SEED-01 (bravo-app1): hello-world Pod carries karyon.io/managed-by=capsule-global-tenant-resource label" {
  local val
  val=$(kubectl --context=k3d-spoke-capsule -n bravo-app1 get pod hello-world \
    -o jsonpath='{.metadata.labels.karyon\.io/managed-by}' 2>/dev/null || true)
  [ "$val" = "capsule-global-tenant-resource" ]
}

@test "SEED-01 (bravo-app1): hello-world Service exists with port 80" {
  local port
  port=$(kubectl --context=k3d-spoke-capsule -n bravo-app1 get svc hello-world \
    -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || true)
  [ "$port" = "80" ]
}
