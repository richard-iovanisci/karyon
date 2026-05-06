#!/usr/bin/env bats
# tests/bats/negative-rbac-05-webhook-down.bats
# Phase 11 / Wave 0 (D-11-06 partition: N11 webhook-down rejects, N12 recovery succeeds).
# RED until Plan 11-02 lands fail-capsule-webhook.sh + Taskfile entry, then Plan 11-03 turns GREEN.
# D-11-09 mechanism: scale Deployment 0/1; rollout-status with 90s timeout on recovery.
# REVISED 2026-05-05 per reviewer MEDIUM #8: replace `sleep 5` with deterministic poll-loop
# on Deployment readyReplicas + Service endpoints (30s budget). Pitfall 11-P6 strict-mode.

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

setup_file() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    if [[ "${KARYON_PHASE11_STRICT_LIVE:-}" == "1" ]]; then
      echo "STRICT_LIVE: k3d-spoke-capsule cluster not reachable" >&2
      return 1
    else
      skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
    fi
  fi
  # Idempotent precondition: ensure capsule-controller-manager is Ready=1
  kubectl --context=k3d-spoke-capsule scale deploy capsule-controller-manager \
    -n capsule-system --replicas=1 >/dev/null 2>&1 || true
  kubectl --context=k3d-spoke-capsule rollout status deploy/capsule-controller-manager \
    -n capsule-system --timeout=90s >/dev/null 2>&1 || true
  export KARYON_BATS_TMPDIR="${TMPDIR:-/tmp}/karyon-tenants/bats-${BATS_RUN_TMPDIR##*/}"
  mkdir -p "$KARYON_BATS_TMPDIR"
  bash "${REPO_ROOT}/scripts/poc/capsule/issue-tenant-kubeconfig.sh" alpha gitops-reconciler \
    --duration=2h --write-to "${KARYON_BATS_TMPDIR}/alpha.kubeconfig" >/dev/null 2>&1
  export ALPHA_KUBECONFIG="${KARYON_BATS_TMPDIR}/alpha.kubeconfig"
}

teardown_file() {
  # Cleanup safety net: ensure controller is back up
  kubectl --context=k3d-spoke-capsule scale deploy capsule-controller-manager \
    -n capsule-system --replicas=1 >/dev/null 2>&1 || true
  kubectl --context=k3d-spoke-capsule rollout status deploy/capsule-controller-manager \
    -n capsule-system --timeout=90s >/dev/null 2>&1 || true
  rm -rf "$KARYON_BATS_TMPDIR"
}

setup() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    _strict_skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
}

@test "N11 -- workload create rejected when capsule-controller is down (failurePolicy: Fail); REVISED poll-loop" {
  cd "$REPO_ROOT"
  run task fail-capsule-webhook -- 0
  [ "$status" -eq 0 ]

  # REVISED 2026-05-05 per reviewer MEDIUM #8: replace `sleep 5` with deterministic
  # poll-loop. After scale-to-zero, wait for Deployment readyReplicas to reach 0 AND
  # for the Service endpoints subset to drain (or the webhook lookup to start failing).
  # 30s budget total: 6 iterations x 5s sleep.
  for i in 1 2 3 4 5 6; do
    READY=$(kubectl --context=k3d-spoke-capsule get deploy capsule-controller-manager \
      -n capsule-system -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [[ "$READY" == "0" || -z "$READY" ]]; then
      break
    fi
    [[ $i -lt 6 ]] && sleep 5
  done
  # Additional verification: the Service endpoints subset is empty (no ready pods backing it)
  for i in 1 2 3 4 5 6; do
    EP_READY=$(kubectl --context=k3d-spoke-capsule get endpoints capsule-controller-manager \
      -n capsule-system -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || true)
    if [[ -z "$EP_READY" ]]; then
      break
    fi
    [[ $i -lt 6 ]] && sleep 5
  done

  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" run probe-n11 \
    --image=registry.example.io/probe -n alpha-app1
  [ "$status" -ne 0 ]
  echo "$output" | grep -qE "(failed calling webhook|no endpoints available|x509|connection refused)"
  # Do NOT recover here -- N12 owns recovery
}

@test "N12 -- workload create succeeds again after capsule-controller recovers" {
  cd "$REPO_ROOT"
  run task fail-capsule-webhook -- 1
  [ "$status" -eq 0 ]
  # The script polls rollout-status to Ready (90s timeout) before returning
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" run probe-n12 \
    --image=registry.example.io/probe -n alpha-app1
  [ "$status" -eq 0 ]
  kubectl --kubeconfig="$ALPHA_KUBECONFIG" delete pod probe-n12 -n alpha-app1 --ignore-not-found --wait=false >/dev/null 2>&1 || true
}
