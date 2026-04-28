#!/usr/bin/env bash
# scripts/fix-coredns.sh
#
# Refreshes stale k3d CoreDNS NodeHosts entries by stop/starting only the
# hub-flux cluster, then proves the hub node and Flux controllers are healthy.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=scripts/lib/preflight-lib.sh
# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/lib/preflight-lib.sh"

readonly HUB_CLUSTER="hub-flux"
readonly HUB_CTX="k3d-hub-flux"
readonly FLUX_NS="flux-system"

require_command() {
  local cmd="$1"
  if ! have "${cmd}"; then
    fail "required command missing: ${cmd}.
       Fix: install project tools with asdf, then rerun: bash scripts/fix-coredns.sh"
    exit 1
  fi
}

# ---------- Section 1: Tool gate ----------
section "Tool gate"
require_command k3d
require_command kubectl
require_command flux
pass "required commands present"

# ---------- Section 2: hub-flux stop/start ----------
section "hub-flux stop/start"
if ! k3d cluster stop hub-flux; then
  fail "failed to stop ${HUB_CLUSTER}.
     Inspect: k3d cluster list
     Fix:     bash scripts/create-clusters.sh && bash scripts/fix-coredns.sh"
  exit 1
fi
pass "stopped: ${HUB_CLUSTER}"

if ! k3d cluster start hub-flux --wait --timeout 120s; then
  fail "failed to start ${HUB_CLUSTER} within 120s.
     Inspect: k3d cluster list && kubectl --context ${HUB_CTX} get node
     Fix:     bash scripts/fix-coredns.sh"
  exit 1
fi
pass "started: ${HUB_CLUSTER}"

# ---------- Section 3: Hub node readiness ----------
section "Hub node readiness"
if ! kubectl --context k3d-hub-flux wait --for=condition=Ready node --all --timeout=120s; then
  fail "hub node did not become Ready within 120s.
     Inspect: kubectl --context ${HUB_CTX} get node -o wide
     Fix:     bash scripts/fix-coredns.sh"
  exit 1
fi
pass "hub node Ready=True"

# ---------- Section 4: Flux readiness ----------
section "Flux readiness"
# MED-3: count deployments BEFORE kubectl wait --all to prevent empty-set
# trivial pass. Pattern matches scripts/bootstrap-flux.sh lines 256-263.
deploy_count="$(kubectl --context k3d-hub-flux -n flux-system get deploy --no-headers 2>/dev/null | wc -l | tr -d '[:space:]')"
if [[ "${deploy_count}" -ge 4 ]]; then
  pass "Flux controller deployment count ok: ${deploy_count}"
else
  fail "expected >= 4 flux controllers in flux-system, found ${deploy_count}.
     Inspect: kubectl --context k3d-hub-flux -n flux-system get deploy,pod
     Fix:     bash scripts/bootstrap-flux.sh && bash scripts/fix-coredns.sh"
  exit 1
fi

if ! kubectl --context k3d-hub-flux -n flux-system wait --for=condition=Available deploy --all --timeout=180s; then
  fail "Flux controllers did not become Available within 180s.
     Inspect: kubectl --context k3d-hub-flux -n flux-system get deploy,pod
     Logs:    flux --context k3d-hub-flux logs
     Fix:     bash scripts/bootstrap-flux.sh && bash scripts/fix-coredns.sh"
  exit 1
fi
pass "Flux controller deployments Available=True"

if ! flux --context k3d-hub-flux check; then
  fail "flux check failed after hub-flux stop/start.
     Inspect: flux --context k3d-hub-flux check
     Logs:    flux --context k3d-hub-flux logs
     Fix:     bash scripts/bootstrap-flux.sh && bash scripts/fix-coredns.sh"
  exit 1
fi
pass "flux check: ok"

# ---------- Section 5: Post-restart spoke DNS probe ----------
section "Post-restart spoke DNS probe"
# MED-2: prove the workaround actually fixed spoke DNS resolution.
# Read-only probe via kubectl exec into existing source-controller pod
# (no resource creation, no deletion).
for spoke in spoke-ml spoke-apps; do
  if kubectl --context k3d-hub-flux -n flux-system exec deploy/source-controller -- \
       getent hosts "k3d-${spoke}-server-0" >/dev/null 2>&1; then
    pass "spoke DNS ok: hub can resolve k3d-${spoke}-server-0"
  else
    warn "spoke DNS still failing for k3d-${spoke}-server-0 after hub-flux stop/start.
       The k3d CoreDNS NodeHosts workaround did not fully resolve. Inspect:
         kubectl --context k3d-hub-flux -n kube-system get cm coredns -o yaml
       Fix: rerun: bash scripts/fix-coredns.sh"
  fi
done

# ---------- Summary ----------
section "Summary"
printf "  %s%d passed%s, %s%d warnings%s, %s%d failed%s\n" \
  "${C_GREEN}" "${PASS}" "${C_RESET}" "${C_YELLOW}" "${WARN}" "${C_RESET}" "${C_RED}" "${FAIL}" "${C_RESET}"
if (( FAIL > 0 )); then exit 1; fi
printf "\n%sCoreDNS NodeHosts refresh complete for hub-flux.%s\n" "${C_GREEN}" "${C_RESET}"
