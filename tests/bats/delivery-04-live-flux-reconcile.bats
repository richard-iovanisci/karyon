#!/usr/bin/env bats
# tests/bats/delivery-04-live-flux-reconcile.bats
# Phase 13 / Wave 0 (D-13-15 Nyquist gate)
# DELIVERY-03 — existing Flux Kustomizations on hub-flux remain Ready=True after Phase 13
# implementation lands (regression gate; no architectural disruption).
# Loop covers: poc-capsule-spoke, poc-capsule-spoke-rbac, poc-capsule-spoke-tenants.
# GREEN-by-design pre-implementation (these Ks are already Ready=True per Phase 11/12);
# becomes a falsifier if Plan 13-01..13-03 accidentally breaks one.

load 'test_helper'

setup() {
  if ! kubectl --context=k3d-hub-flux cluster-info >/dev/null 2>&1; then
    skip "k3d-hub-flux cluster not reachable; skipping live bats"
  fi
}

@test "DELIVERY-03 (Flux Ks): poc-capsule-spoke Ready=True on hub-flux" {
  local status_val
  status_val=$(kubectl --context=k3d-hub-flux get kustomization poc-capsule-spoke \
    -n flux-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>&1 || true)
  if echo "$status_val" | grep -qF 'NotFound'; then
    echo "poc-capsule-spoke Kustomization NotFound on hub-flux"
    return 1
  fi
  [ "$status_val" = "True" ]
}

@test "DELIVERY-03 (Flux Ks): poc-capsule-spoke-rbac Ready=True on hub-flux" {
  local status_val
  status_val=$(kubectl --context=k3d-hub-flux get kustomization poc-capsule-spoke-rbac \
    -n flux-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>&1 || true)
  if echo "$status_val" | grep -qF 'NotFound'; then
    echo "poc-capsule-spoke-rbac Kustomization NotFound on hub-flux"
    return 1
  fi
  [ "$status_val" = "True" ]
}

@test "DELIVERY-03 (Flux Ks): poc-capsule-spoke-tenants Ready=True on hub-flux" {
  local status_val
  status_val=$(kubectl --context=k3d-hub-flux get kustomization poc-capsule-spoke-tenants \
    -n flux-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>&1 || true)
  if echo "$status_val" | grep -qF 'NotFound'; then
    echo "poc-capsule-spoke-tenants Kustomization NotFound on hub-flux"
    return 1
  fi
  [ "$status_val" = "True" ]
}
