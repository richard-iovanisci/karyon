#!/usr/bin/env bats
# tests/bats/rbac-07-live-flux-sa-preservation.bats
# Phase 13 / Wave 0 (D-13-15 Nyquist gate)
# RBAC-03 — Flux SA owner pattern regression gate.
# Existing alpha/bravo Tenant CR owners (flux-reconciler + gitops-reconciler SAs)
# MUST be preserved verbatim. poc-capsule-spoke-tenants Flux Kustomization Ready=True.
# Currently GREEN-by-design (regression gate); becomes a falsifier if Plan 13-01..13-02
# accidentally removes owners.

load 'test_helper'

setup() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
}

@test "RBAC-03 (alpha): existing gitops-reconciler SA owner preserved verbatim" {
  local owner
  owner=$(kubectl --context=k3d-spoke-capsule get tenant alpha \
    -o jsonpath='{.spec.owners[?(@.name=="system:serviceaccount:tenant-alpha:gitops-reconciler")].name}' 2>&1 || true)
  if echo "$owner" | grep -qF 'NotFound'; then
    return 1
  fi
  [ "$owner" = "system:serviceaccount:tenant-alpha:gitops-reconciler" ]
}

@test "RBAC-03 (alpha): existing flux-reconciler SA owner preserved verbatim" {
  local owner
  owner=$(kubectl --context=k3d-spoke-capsule get tenant alpha \
    -o jsonpath='{.spec.owners[?(@.name=="system:serviceaccount:flux-system:flux-reconciler")].name}' 2>&1 || true)
  if echo "$owner" | grep -qF 'NotFound'; then
    return 1
  fi
  [ "$owner" = "system:serviceaccount:flux-system:flux-reconciler" ]
}

@test "RBAC-03 (bravo): existing gitops-reconciler SA owner preserved verbatim" {
  local owner
  owner=$(kubectl --context=k3d-spoke-capsule get tenant bravo \
    -o jsonpath='{.spec.owners[?(@.name=="system:serviceaccount:tenant-bravo:gitops-reconciler")].name}' 2>&1 || true)
  if echo "$owner" | grep -qF 'NotFound'; then
    return 1
  fi
  [ "$owner" = "system:serviceaccount:tenant-bravo:gitops-reconciler" ]
}

@test "RBAC-03 (bravo): existing flux-reconciler SA owner preserved verbatim" {
  local owner
  owner=$(kubectl --context=k3d-spoke-capsule get tenant bravo \
    -o jsonpath='{.spec.owners[?(@.name=="system:serviceaccount:flux-system:flux-reconciler")].name}' 2>&1 || true)
  if echo "$owner" | grep -qF 'NotFound'; then
    return 1
  fi
  [ "$owner" = "system:serviceaccount:flux-system:flux-reconciler" ]
}

@test "RBAC-03 (Flux): poc-capsule-spoke-tenants Kustomization Ready=True on hub-flux" {
  local status_val
  status_val=$(kubectl --context=k3d-hub-flux get kustomization poc-capsule-spoke-tenants \
    -n flux-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>&1 || true)
  if echo "$status_val" | grep -qF 'NotFound'; then
    return 1
  fi
  [ "$status_val" = "True" ]
}
