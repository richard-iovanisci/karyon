#!/usr/bin/env bash
# scripts/poc/capsule/fail-capsule-webhook.sh
#
# Scales capsule-controller-manager Deployment to N replicas (test-only failure simulation).
# `task fail-capsule-webhook -- 0` -> apiserver returns "no endpoints available" for capsule webhooks;
#                                    with failurePolicy: Fail this blocks tenant pod create (fail-closed proof).
# `task fail-capsule-webhook -- 1` -> recovery: scale to 1, polls rollout-status to Ready (90s timeout);
#                                    applies succeed again post-recovery.
#
# Surfaces as `task fail-capsule-webhook -- 0|1`. Idempotent -- re-running with the same
# replica count is a no-op (kubectl scale is declarative).
#
# Standalone POC helper for the persistent spoke-capsule cluster; never invoked by task rebuild
# (enforced by tests/bats/poc-isolation-01-static.bats).
# Hub-only Flux control plane: NO Flux on spoke-capsule -- this script talks to spoke-capsule
# directly via kubectl context (see docs/adr/0004-hub-only-flux-control-plane.md).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# shellcheck source=../../lib/preflight-lib.sh
# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/lib/preflight-lib.sh"

# ---------- Section 0: Arg validation ----------
REPLICAS="${1:-}"
if [[ -z "$REPLICAS" ]] || ! [[ "$REPLICAS" =~ ^[01]$ ]]; then
  fail "Usage: task fail-capsule-webhook -- 0|1"
  exit 1
fi

# ---------- Section 1: Tool gate ----------
section "Tool gate"
if ! have kubectl; then
  fail "kubectl not found.
       Fix: install project tools with asdf, then rerun: task fail-capsule-webhook -- ${REPLICAS}"
  exit 1
fi
pass "required commands present"

# ---------- Section 2: Scale capsule-controller-manager ----------
section "Scaling capsule-controller-manager to ${REPLICAS} replicas (test-only failure simulation)"
kubectl --context=k3d-spoke-capsule scale deploy capsule-controller-manager \
  -n capsule-system --replicas="${REPLICAS}"
pass "scaled capsule-controller-manager to ${REPLICAS}"

# ---------- Section 3: Rollout status (recovery path only) ----------
if [[ "$REPLICAS" == "1" ]]; then
  section "Rollout status (recovery path; 90s timeout)"
  kubectl --context=k3d-spoke-capsule rollout status deploy/capsule-controller-manager \
    -n capsule-system --timeout=90s
  pass "capsule-controller-manager Ready"
fi

# ---------- Section 4: Summary ----------
section "Summary"
printf "  %s%d passed%s, %s%d warnings%s, %s%d failed%s\n" \
  "${C_GREEN}" "${PASS}" "${C_RESET}" "${C_YELLOW}" "${WARN}" "${C_RESET}" "${C_RED}" "${FAIL}" "${C_RESET}"
if (( FAIL > 0 )); then exit 1; fi
printf "\n%scapsule-controller-manager scaled to ${REPLICAS}.%s\n" "${C_GREEN}" "${C_RESET}"
