#!/usr/bin/env bats
# tests/bats/tenants-09-live-inner-k-ready.bats
# Live reconcile — tenant inner Ks Ready=True against empty placeholder paths.
#
# Verifies:
#   - spoke-capsule-kubeconfig Secret mirrored to tenant-{alpha,bravo} ns on hub
#     (Flux's kubeConfig.secretRef has a hard same-namespace constraint; the
#     Secret MUST be mirrored from flux-system into each tenant ns by
#     register-poc-cluster.sh)
#   - tenant-alpha-app + tenant-bravo-app Kustomizations Ready=True against empty
#     placeholder paths (empty resources: [] is valid kustomize input — no
#     objects applied, so the placeholder reaches Ready quickly)
#   - Skip if pre-push GitRepository ArtifactFailed (while origin/main..main has
#     unpushed commits, the GitRepository for tenant-{alpha,bravo}-source can't
#     fetch the revision)
#
# Cluster-info gate: hub-only, because tenant inner K CRs live on hub.

load 'test_helper'

setup() {
  if ! kubectl --context=k3d-hub-flux cluster-info >/dev/null 2>&1; then
    skip "k3d-hub-flux cluster not reachable; skipping live bats"
  fi
}

# ---- Secret-mirror assertions ----

@test "RESEARCH Gap 1 / D-09-03a (alpha): spoke-capsule-kubeconfig Secret mirrored to tenant-alpha namespace on hub" {
  run kubectl --context=k3d-hub-flux -n tenant-alpha get secret spoke-capsule-kubeconfig
  [ "$status" -eq 0 ]
}

@test "RESEARCH Gap 1 / D-09-03a (bravo): spoke-capsule-kubeconfig Secret mirrored to tenant-bravo namespace on hub" {
  run kubectl --context=k3d-hub-flux -n tenant-bravo get secret spoke-capsule-kubeconfig
  [ "$status" -eq 0 ]
}

# ---- Inner K Ready=True (with pre-push skip) ----

@test "TEN-04 / D-09-03 (alpha): tenant-alpha-app Kustomization Ready=True (skip if GitRepository pre-push ArtifactFailed)" {
  # Pre-push skip: if GitRepository tenant-alpha-source is ArtifactFailed (revision main
  # missing because local commits are unpushed), skip rather than fail.
  local gr_reason
  gr_reason=$(kubectl --context=k3d-hub-flux -n tenant-alpha get gitrepository tenant-alpha-source -o jsonpath='{.status.conditions[?(@.type=="Ready")].reason}' 2>/dev/null || true)
  if [[ "$gr_reason" == "ArtifactFailed" || "$gr_reason" == "GitOperationFailed" ]]; then
    skip "pre-push state: tenant-alpha-source GitRepository is $gr_reason (deferred to Phase 11 VAL-05)"
  fi
  local i ready
  for i in 1 2 3; do
    ready=$(kubectl --context=k3d-hub-flux -n tenant-alpha get kustomization tenant-alpha-app -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
    [[ "$ready" == "True" ]] && return 0
    [[ $i -lt 3 ]] && sleep 30
  done
  echo "Last observed Ready: '$ready'"
  return 1
}

@test "TEN-04 / D-09-03 (bravo): tenant-bravo-app Kustomization Ready=True (skip if GitRepository pre-push ArtifactFailed)" {
  local gr_reason
  gr_reason=$(kubectl --context=k3d-hub-flux -n tenant-bravo get gitrepository tenant-bravo-source -o jsonpath='{.status.conditions[?(@.type=="Ready")].reason}' 2>/dev/null || true)
  if [[ "$gr_reason" == "ArtifactFailed" || "$gr_reason" == "GitOperationFailed" ]]; then
    skip "pre-push state: tenant-bravo-source GitRepository is $gr_reason (deferred to Phase 11 VAL-05)"
  fi
  local i ready
  for i in 1 2 3; do
    ready=$(kubectl --context=k3d-hub-flux -n tenant-bravo get kustomization tenant-bravo-app -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
    [[ "$ready" == "True" ]] && return 0
    [[ $i -lt 3 ]] && sleep 30
  done
  echo "Last observed Ready: '$ready'"
  return 1
}
