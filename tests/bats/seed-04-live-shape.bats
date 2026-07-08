#!/usr/bin/env bats
# tests/bats/seed-04-live-shape.bats
# Deployment + Service only (AMENDED per the ADR 0008 addendum 2026-07-06,
# which supersedes the original "Pod + Service" shape):
#   - Exactly 1 GTR-labeled Deployment hello-world per tenant ns (was: zero —
#     the bare-Pod design put the Capsule controller in a permanent resync
#     error loop because Pod specs are immutable on update)
#   - Exactly 1 running hello-world pod (via app=hello-world template label;
#     Deployment pods carry a -<hash> suffix)
#   - Exactly 1 Service hello-world per tenant ns
#   - Still ZERO extra ConfigMaps labeled by the GTR
#   - ReplicaSets exist as Deployment children but do NOT carry the GTR
#     provenance label (it is not part of the pod template)

load 'test_helper'

setup() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
}

# alpha-app1 is a fixture namespace created by the tenants quota live
# suites, not by GitOps — skip its block when absent so this suite is honest
# standalone (the pre-2026-07-06 suite failed spuriously in that state).
require_ns() {
  kubectl --context=k3d-spoke-capsule get namespace "$1" >/dev/null 2>&1 \
    || skip "fixture namespace $1 absent; run the tenants quota live suite first"
}

# ---- tenant-alpha ----

@test "SEED-03 (tenant-alpha): exactly 1 Deployment labeled karyon.io/managed-by=capsule-global-tenant-resource" {
  local n
  n=$(kubectl --context=k3d-spoke-capsule get deployment -n tenant-alpha \
    -l karyon.io/managed-by=capsule-global-tenant-resource --no-headers 2>/dev/null | wc -l)
  [ "$n" -eq 1 ]
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

@test "SEED-03 (tenant-alpha): exactly 1 hello-world pod (app=hello-world) materialized via the seeded Deployment" {
  local n
  n=$(kubectl --context=k3d-spoke-capsule get pods -n tenant-alpha \
    -l app=hello-world --no-headers 2>/dev/null | wc -l)
  [ "$n" -eq 1 ]
}

@test "SEED-03 (tenant-alpha): exactly 1 Service hello-world materialized by GTR" {
  run kubectl --context=k3d-spoke-capsule get svc hello-world -n tenant-alpha
  [ "$status" -eq 0 ]
}

# ---- alpha-app1 ----

@test "SEED-03 (alpha-app1): exactly 1 Deployment labeled karyon.io/managed-by=capsule-global-tenant-resource" {
  require_ns alpha-app1
  local n
  n=$(kubectl --context=k3d-spoke-capsule get deployment -n alpha-app1 \
    -l karyon.io/managed-by=capsule-global-tenant-resource --no-headers 2>/dev/null | wc -l)
  [ "$n" -eq 1 ]
}

@test "SEED-03 (alpha-app1): zero ReplicaSets labeled karyon.io/managed-by=capsule-global-tenant-resource" {
  require_ns alpha-app1
  local n
  n=$(kubectl --context=k3d-spoke-capsule get replicaset -n alpha-app1 \
    -l karyon.io/managed-by=capsule-global-tenant-resource --no-headers 2>/dev/null | wc -l)
  [ "$n" -eq 0 ]
}

@test "SEED-03 (alpha-app1): zero extra ConfigMaps labeled karyon.io/managed-by=capsule-global-tenant-resource" {
  require_ns alpha-app1
  local n
  n=$(kubectl --context=k3d-spoke-capsule get configmap -n alpha-app1 \
    -l karyon.io/managed-by=capsule-global-tenant-resource --no-headers 2>/dev/null | wc -l)
  [ "$n" -eq 0 ]
}

@test "SEED-03 (alpha-app1): exactly 1 hello-world pod (app=hello-world) materialized via the seeded Deployment" {
  require_ns alpha-app1
  local n
  n=$(kubectl --context=k3d-spoke-capsule get pods -n alpha-app1 \
    -l app=hello-world --no-headers 2>/dev/null | wc -l)
  [ "$n" -eq 1 ]
}

@test "SEED-03 (alpha-app1): exactly 1 Service hello-world materialized by GTR" {
  require_ns alpha-app1
  run kubectl --context=k3d-spoke-capsule get svc hello-world -n alpha-app1
  [ "$status" -eq 0 ]
}
