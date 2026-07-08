#!/usr/bin/env bash
# scripts/poc/capsule/fix-dns.sh
#
# Refreshes stale k3d CoreDNS NodeHosts entries on the spoke-capsule cluster
# alone by stop/starting it, then proves the spoke node is healthy.
#
# Surfaces as `task fix-dns-poc-capsule`. DISTINCT from `task fix-dns` (which
# calls scripts/fix-coredns.sh for hub-flux only). The two tasks are SIBLINGS
# (NOT a parent/child env-var dispatch), so this script MUST NOT touch the
# default `task fix-dns` surface (zero hub-flux cluster commands).
#
# Hub-only Flux control plane: NO Flux runs on spoke-capsule, so there is no
# `flux check` invocation here (see docs/adr/0004-hub-only-flux-control-plane.md).
# Standalone POC helper for the persistent spoke-capsule cluster; never invoked by task rebuild
# (enforced by tests/bats/poc-isolation-01-static.bats).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# shellcheck source=../../lib/preflight-lib.sh
# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/lib/preflight-lib.sh"

readonly POC_CLUSTER="spoke-capsule"
readonly POC_CTX="k3d-${POC_CLUSTER}"

# ---------- Section 1: Tool gate ----------
section "Tool gate"
for cmd in k3d kubectl; do
  if ! have "$cmd"; then
    fail "required command missing: $cmd.
       Fix: install project tools with asdf, then rerun: bash scripts/poc/capsule/fix-dns.sh"
    exit 1
  fi
done
pass "required commands present"

# ---------- Section 2: ${POC_CLUSTER} stop/start ----------
section "${POC_CLUSTER} stop/start"
if ! k3d cluster stop "${POC_CLUSTER}"; then
  fail "failed to stop ${POC_CLUSTER}.
     Inspect: k3d cluster list
     Fix:     bash scripts/poc/capsule/create-cluster.sh && bash scripts/poc/capsule/fix-dns.sh"
  exit 1
fi
pass "stopped: ${POC_CLUSTER}"

if ! k3d cluster start "${POC_CLUSTER}" --wait --timeout 120s; then
  fail "failed to start ${POC_CLUSTER} within 120s.
     Inspect: k3d cluster list && kubectl --context ${POC_CTX} get node
     Fix:     bash scripts/poc/capsule/fix-dns.sh"
  exit 1
fi
pass "started: ${POC_CLUSTER}"

# ---------- Section 3: ${POC_CLUSTER} node readiness ----------
section "${POC_CLUSTER} node readiness"
if ! kubectl --context "${POC_CTX}" wait --for=condition=Ready node --all --timeout=120s; then
  fail "${POC_CLUSTER} node did not become Ready within 120s.
     Inspect: kubectl --context ${POC_CTX} get node -o wide
     Fix:     bash scripts/poc/capsule/fix-dns.sh"
  exit 1
fi
pass "${POC_CLUSTER} node Ready=True"

# NO `flux check` invocation against spoke-capsule (no Flux runs there -- hub-only Flux control plane).
# NO hub-flux interaction (default task fix-dns covers that surface).

# ---------- Section 4: Summary ----------
section "Summary"
printf "  %s%d passed%s, %s%d warnings%s, %s%d failed%s\n" \
  "${C_GREEN}" "${PASS}" "${C_RESET}" "${C_YELLOW}" "${WARN}" "${C_RESET}" "${C_RED}" "${FAIL}" "${C_RESET}"
if (( FAIL > 0 )); then exit 1; fi
printf "\n%sCoreDNS NodeHosts refresh complete for %s.%s\n" "${C_GREEN}" "${POC_CLUSTER}" "${C_RESET}"
