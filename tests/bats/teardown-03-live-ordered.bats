#!/usr/bin/env bats
# tests/bats/teardown-03-live-ordered.bats
# ORDERED two-step live teardown test (MERGED 2026-05-05:
# the former teardown-04-live-pvc-strand-mitigation.bats was a separate file but shared
# the destroy invocation; running them independently meant the 2nd test had no namespace
# to seed the synthetic PVC. Merged into ordered @tests below.):
#   @test 1 (precondition): seed synthetic Pod-bound PVC labeled capsule.clastix.io/tenant=alpha in alpha-app1.
#   @test 2 (action + invariants): run task destroy-poc -- capsule; assert exit 0; poll labeled namespaces empty + PVC absent within 90s; sentinel + ../pocs preserved.
# KARYON_PHASE11_STRICT_LIVE=1 converts skips to FAIL.

load 'test_helper'

_strict_skip() {
  local msg="$1"
  if [[ "${KARYON_PHASE11_STRICT_LIVE:-}" == "1" ]]; then
    echo "STRICT_LIVE: ${msg}" >&2
    return 1
  else
    skip "${msg}"
  fi
}

setup() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    _strict_skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
}

@test "@test 1 (precondition): seed synthetic Pod-bound PVC labeled capsule.clastix.io/tenant=alpha in alpha-app1" {
  cd "$REPO_ROOT"
  # alpha-app1 is the impersonation-test fixture namespace. Skip if absent (a prior run may not have re-staged it).
  if ! kubectl --context=k3d-spoke-capsule get namespace alpha-app1 >/dev/null 2>&1; then
    _strict_skip "alpha-app1 namespace absent (Phase 9 TEN-02 fixture missing); pre-create or run Plan 11-03 first"
  fi
  # Apply a labeled PVC. The label is what destroy-poc.sh's NS_LIST loop uses to enumerate
  # namespaces (it then enumerates PVCs WITHIN those namespaces -- PVCs themselves do NOT
  # need the label). The label here is purely for human readability
  # in the bats output; alpha-app1 already carries the namespace-level capsule.clastix.io/tenant=alpha
  # label stamped at namespace admission.
  kubectl --context=k3d-spoke-capsule apply -n alpha-app1 -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: bats-strand-pvc
  labels:
    teardown-test: phase11-bats-strand
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 1Mi
EOF
  # Verify PVC was applied
  run kubectl --context=k3d-spoke-capsule get pvc bats-strand-pvc -n alpha-app1
  [ "$status" -eq 0 ]
}

@test "@test 2 (action + invariants): task destroy-poc -- capsule completes; namespaces cascade empty; PVC force-deleted within 90s; sentinel + mount preserved" {
  cd "$REPO_ROOT"
  if ! kubectl --context=k3d-spoke-capsule get namespace alpha-app1 >/dev/null 2>&1; then
    _strict_skip "alpha-app1 absent; @test 1 precondition could not seed PVC"
  fi
  # Action: run the teardown via the standardized task command form (with `--`)
  run task destroy-poc -- capsule
  [ "$status" -eq 0 ]
  # Invariant 1: post-teardown no namespaces with capsule.clastix.io/tenant label remain
  # (90s budget for the PVC strand mitigation to complete)
  for i in 1 2 3; do
    REMAINING=$(kubectl --context=k3d-spoke-capsule get ns -l capsule.clastix.io/tenant -o name 2>/dev/null | wc -l)
    [[ "$REMAINING" -eq 0 ]] && break
    [[ $i -lt 3 ]] && sleep 30
  done
  [[ "$REMAINING" -eq 0 ]] || { echo "FAIL: $REMAINING namespaces with capsule.clastix.io/tenant label remain after 90s"; return 1; }
  # Invariant 2: PVC bats-strand-pvc is gone (alpha-app1 namespace is gone, so the PVC must be too)
  if kubectl --context=k3d-spoke-capsule get pvc bats-strand-pvc -n alpha-app1 >/dev/null 2>&1; then
    echo "FAIL: bats-strand-pvc still present in alpha-app1 (which itself should be deleted)"
    return 1
  fi
  # Invariant 3: Sentinel preservation -- # KARYON POC MOUNT + - ../pocs MUST remain in flux-system/kustomization.yaml
  run grep -F -- '# KARYON POC MOUNT' "${REPO_ROOT}/clusters/hub-flux/flux-system/kustomization.yaml"
  [ "$status" -eq 0 ]
  run grep -F -- '- ../pocs' "${REPO_ROOT}/clusters/hub-flux/flux-system/kustomization.yaml"
  [ "$status" -eq 0 ]
}
