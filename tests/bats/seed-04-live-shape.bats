#!/usr/bin/env bats
# tests/bats/seed-04-live-shape.bats
# Phase 13 / Wave 0 (D-13-15 Nyquist gate)
# SEED-03 — Pod + Service only:
#   - NO Deployment / NO ReplicaSet / NO extra ConfigMap labeled by GTR
#   - Exactly 1 Pod hello-world per tenant ns
#   - Exactly 1 Service hello-world per tenant ns
# RED until Plan 13-03 lands the GTR + workload.

load 'test_helper'

setup() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
}

# ---- tenant-alpha ----

@test "SEED-03 (tenant-alpha): zero Deployments labeled karyon.io/managed-by=capsule-global-tenant-resource" {
  local n
  n=$(kubectl --context=k3d-spoke-capsule get deployment -n tenant-alpha \
    -l karyon.io/managed-by=capsule-global-tenant-resource --no-headers 2>/dev/null | wc -l)
  [ "$n" -eq 0 ]
}

@test "SEED-03 (tenant-alpha): zero ReplicaSets labeled karyon.io/managed-by=capsule-global-tenant-resource" {
  local n
  n=$(kubectl --context=k3d-spoke-capsule get replicaset -n tenant-alpha \
    -l karyon.io/managed-by=capsule-global-tenant-resource --no-headers 2>/dev/null | wc -l)
  [ "$n" -eq 0 ]
}

@test "SEED-03 (tenant-alpha): zero extra ConfigMaps labeled karyon.io/managed-by=capsule-global-tenant-resource" {
  local n
  n=$(kubectl --context=k3d-spoke-capsule get configmap -n tenant-alpha \
    -l karyon.io/managed-by=capsule-global-tenant-resource --no-headers 2>/dev/null | wc -l)
  [ "$n" -eq 0 ]
}

@test "SEED-03 (tenant-alpha): exactly 1 Pod hello-world materialized by GTR" {
  run kubectl --context=k3d-spoke-capsule get pod hello-world -n tenant-alpha
  [ "$status" -eq 0 ]
}

@test "SEED-03 (tenant-alpha): exactly 1 Service hello-world materialized by GTR" {
  run kubectl --context=k3d-spoke-capsule get svc hello-world -n tenant-alpha
  [ "$status" -eq 0 ]
}

# ---- alpha-app1 ----

@test "SEED-03 (alpha-app1): zero Deployments labeled karyon.io/managed-by=capsule-global-tenant-resource" {
  local n
  n=$(kubectl --context=k3d-spoke-capsule get deployment -n alpha-app1 \
    -l karyon.io/managed-by=capsule-global-tenant-resource --no-headers 2>/dev/null | wc -l)
  [ "$n" -eq 0 ]
}

@test "SEED-03 (alpha-app1): zero ReplicaSets labeled karyon.io/managed-by=capsule-global-tenant-resource" {
  local n
  n=$(kubectl --context=k3d-spoke-capsule get replicaset -n alpha-app1 \
    -l karyon.io/managed-by=capsule-global-tenant-resource --no-headers 2>/dev/null | wc -l)
  [ "$n" -eq 0 ]
}

@test "SEED-03 (alpha-app1): zero extra ConfigMaps labeled karyon.io/managed-by=capsule-global-tenant-resource" {
  local n
  n=$(kubectl --context=k3d-spoke-capsule get configmap -n alpha-app1 \
    -l karyon.io/managed-by=capsule-global-tenant-resource --no-headers 2>/dev/null | wc -l)
  [ "$n" -eq 0 ]
}

@test "SEED-03 (alpha-app1): exactly 1 Pod hello-world materialized by GTR" {
  run kubectl --context=k3d-spoke-capsule get pod hello-world -n alpha-app1
  [ "$status" -eq 0 ]
}

@test "SEED-03 (alpha-app1): exactly 1 Service hello-world materialized by GTR" {
  run kubectl --context=k3d-spoke-capsule get svc hello-world -n alpha-app1
  [ "$status" -eq 0 ]
}
