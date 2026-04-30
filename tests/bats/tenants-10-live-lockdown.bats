#!/usr/bin/env bats
# tests/bats/tenants-10-live-lockdown.bats
# Phase 9 / Wave 0 (D-09-08 Nyquist gate)
# TEN-05 live — Hub Flux multi-tenancy lockdown observed on hub-flux Deployments.
# Plans 09-03 (lockdown) + 09-04 (verifier) land the yaml that turns these GREEN.
#
# Verifies (per RESEARCH §Gap 2 controller-restart caveat + D-09-05 / D-09-05a):
#   - kustomize-controller args contain --no-cross-namespace-refs=true
#   - kustomize-controller args contain --no-remote-bases=true
#   - kustomize-controller args contain --default-service-account=default
#   - helm-controller args contain --no-cross-namespace-refs=true AND
#     --default-service-account=default (RESEARCH §Gap 2: extends CONTEXT.md
#     narrowing to match upstream canonical lockdown — defense in depth)
#   - notification-controller args contain --no-cross-namespace-refs=true
#   - All 3 controllers' availableReplicas == replicas (catches CrashLoopBackOff
#     from misapplied flag — RESEARCH §Gap 2: controllers exit non-zero on
#     unknown flag; 4×30s poll = 2-minute window for new pod to come up)
#   - flux-system Kustomization Ready=True (D-09-05a LOAD-BEARING escape hatch
#     validation — without spec.serviceAccountName: kustomize-controller the
#     lockdown bricks Flux's own bootstrap reconcile)

load 'test_helper'

setup() {
  if ! kubectl --context=k3d-hub-flux cluster-info >/dev/null 2>&1; then
    skip "k3d-hub-flux cluster not reachable; skipping live bats"
  fi
}

# ---- kustomize-controller flags ----

@test "TEN-05 / D-09-05: kustomize-controller args contain --no-cross-namespace-refs=true" {
  run bash -c "kubectl --context=k3d-hub-flux -n flux-system get deployment kustomize-controller -o jsonpath='{.spec.template.spec.containers[0].args}' | grep -F -- '--no-cross-namespace-refs=true'"
  [ "$status" -eq 0 ]
}

@test "TEN-05 / D-09-05: kustomize-controller args contain --no-remote-bases=true" {
  run bash -c "kubectl --context=k3d-hub-flux -n flux-system get deployment kustomize-controller -o jsonpath='{.spec.template.spec.containers[0].args}' | grep -F -- '--no-remote-bases=true'"
  [ "$status" -eq 0 ]
}

@test "TEN-05 / D-09-05: kustomize-controller args contain --default-service-account=default" {
  run bash -c "kubectl --context=k3d-hub-flux -n flux-system get deployment kustomize-controller -o jsonpath='{.spec.template.spec.containers[0].args}' | grep -F -- '--default-service-account=default'"
  [ "$status" -eq 0 ]
}

# ---- helm-controller flags (RESEARCH Gap 2 extension) ----

@test "TEN-05 / RESEARCH Gap 2: helm-controller args contain --no-cross-namespace-refs=true (defense in depth)" {
  run bash -c "kubectl --context=k3d-hub-flux -n flux-system get deployment helm-controller -o jsonpath='{.spec.template.spec.containers[0].args}' | grep -F -- '--no-cross-namespace-refs=true'"
  [ "$status" -eq 0 ]
}

@test "TEN-05 / RESEARCH Gap 2: helm-controller args contain --default-service-account=default (defense in depth)" {
  run bash -c "kubectl --context=k3d-hub-flux -n flux-system get deployment helm-controller -o jsonpath='{.spec.template.spec.containers[0].args}' | grep -F -- '--default-service-account=default'"
  [ "$status" -eq 0 ]
}

# ---- notification-controller flag ----

@test "TEN-05 / D-09-05: notification-controller args contain --no-cross-namespace-refs=true" {
  run bash -c "kubectl --context=k3d-hub-flux -n flux-system get deployment notification-controller -o jsonpath='{.spec.template.spec.containers[0].args}' | grep -F -- '--no-cross-namespace-refs=true'"
  [ "$status" -eq 0 ]
}

# ---- 3 controllers no CrashLoopBackOff (availableReplicas == replicas) ----

@test "TEN-05 / RESEARCH Gap 2 (no CrashLoopBackOff): kustomize-controller availableReplicas == replicas (4×30s = 2 min poll)" {
  local i avail desired
  for i in 1 2 3 4; do
    avail=$(kubectl --context=k3d-hub-flux -n flux-system get deployment kustomize-controller -o jsonpath='{.status.availableReplicas}' 2>/dev/null || echo 0)
    desired=$(kubectl --context=k3d-hub-flux -n flux-system get deployment kustomize-controller -o jsonpath='{.spec.replicas}' 2>/dev/null || echo 1)
    [ -z "$avail" ] && avail=0
    [ -z "$desired" ] && desired=1
    if [[ "$avail" == "$desired" ]] && [[ "$avail" -gt 0 ]]; then
      return 0
    fi
    [[ $i -lt 4 ]] && sleep 30
  done
  echo "Last observed kustomize-controller availableReplicas=$avail desired=$desired"
  return 1
}

@test "TEN-05 / RESEARCH Gap 2 (no CrashLoopBackOff): helm-controller availableReplicas == replicas (4×30s = 2 min poll)" {
  local i avail desired
  for i in 1 2 3 4; do
    avail=$(kubectl --context=k3d-hub-flux -n flux-system get deployment helm-controller -o jsonpath='{.status.availableReplicas}' 2>/dev/null || echo 0)
    desired=$(kubectl --context=k3d-hub-flux -n flux-system get deployment helm-controller -o jsonpath='{.spec.replicas}' 2>/dev/null || echo 1)
    [ -z "$avail" ] && avail=0
    [ -z "$desired" ] && desired=1
    if [[ "$avail" == "$desired" ]] && [[ "$avail" -gt 0 ]]; then
      return 0
    fi
    [[ $i -lt 4 ]] && sleep 30
  done
  echo "Last observed helm-controller availableReplicas=$avail desired=$desired"
  return 1
}

@test "TEN-05 / RESEARCH Gap 2 (no CrashLoopBackOff): notification-controller availableReplicas == replicas (4×30s = 2 min poll)" {
  local i avail desired
  for i in 1 2 3 4; do
    avail=$(kubectl --context=k3d-hub-flux -n flux-system get deployment notification-controller -o jsonpath='{.status.availableReplicas}' 2>/dev/null || echo 0)
    desired=$(kubectl --context=k3d-hub-flux -n flux-system get deployment notification-controller -o jsonpath='{.spec.replicas}' 2>/dev/null || echo 1)
    [ -z "$avail" ] && avail=0
    [ -z "$desired" ] && desired=1
    if [[ "$avail" == "$desired" ]] && [[ "$avail" -gt 0 ]]; then
      return 0
    fi
    [[ $i -lt 4 ]] && sleep 30
  done
  echo "Last observed notification-controller availableReplicas=$avail desired=$desired"
  return 1
}

# ---- D-09-05a escape hatch ----

@test "TEN-05 / D-09-05a LOAD-BEARING: flux-system Kustomization reports Ready=True (escape hatch validation, 3×30s retry)" {
  local i ready
  for i in 1 2 3; do
    ready=$(kubectl --context=k3d-hub-flux -n flux-system get kustomization flux-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
    [[ "$ready" == "True" ]] && return 0
    [[ $i -lt 3 ]] && sleep 30
  done
  echo "Last observed flux-system Kustomization Ready: '$ready'"
  return 1
}
