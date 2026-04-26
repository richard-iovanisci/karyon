#!/usr/bin/env bash
# scripts/bootstrap-flux.sh
# Runs `flux bootstrap github` on k3d-hub-flux with --path locked to
# clusters/hub-flux (REQ-FLUX-02 — effectively immutable after first run).
# Sources GITHUB_OWNER / GITHUB_REPO / GITHUB_TOKEN from the gitignored .env
# (REQ-FLUX-03). The token is never echoed to stdout.
#
# Requirements satisfied: FLUX-01, FLUX-02, FLUX-03, FLUX-04
# Decisions honored:      D-01..D-16
#
# D-11 token-safety: set -euo pipefail INTENTIONALLY omits -x (no trace of
# GITHUB_TOKEN on stdout/stderr; strict-mode only, no debug tracing).
#
# Structure:
#   Section 1: Preflight gate + gitleaks advisory (D-05, Phase-6 hand-off)
#   Section 2: Context + idempotency checks       (D-06, D-07)
#   Section 3: flux bootstrap                     (D-01..D-04, D-08, D-11)
#   Section 4: Post-bootstrap verification        (D-09, D-10)
#   Section 5: Patch-surface marker               (D-13)
#
# Usage:   bash scripts/bootstrap-flux.sh
# Pre-req: scripts/preflight.sh exits 0 (port 6443 already bound by hub-flux
#          post-Phase-2 produces a warn, not a fail — preflight tolerates it);
#          kubectl context is k3d-hub-flux;
#          .env has GITHUB_OWNER / GITHUB_REPO / GITHUB_TOKEN non-empty.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/preflight-lib.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/preflight-lib.sh"

# Constants — --path is hard-coded per FLUX-02 / D-decisions; do NOT parameterize.
readonly FLUX_PATH="clusters/hub-flux"
readonly KUBE_CTX="k3d-hub-flux"
readonly FLUX_NS="flux-system"
# shellcheck disable=SC2034  # Used by Section 5, appended by Task 2.
readonly KUST_FILE="${REPO_ROOT}/${FLUX_PATH}/${FLUX_NS}/kustomization.yaml"

# ---------- Section 1: Preflight gate + gitleaks advisory (D-05, Phase-6 hand-off) ----------
section "Preflight gate"
PREFLIGHT_LOG="/tmp/preflight-$$.log"
# Note (codex HIGH-2): scripts/preflight.sh emits port-in-use and existing-k3d-cluster
# checks as WARN (not FAIL). After Phase 2 ran, port 6443 is bound by k3d-hub-flux's
# load-balancer container — preflight warns but exits 0. This script tolerates that
# state. If a future preflight rewrite turns these warns into fails, this gate will
# block and the developer must update preflight or split bootstrap-specific gating.
if ! bash "${SCRIPT_DIR}/preflight.sh" > "${PREFLIGHT_LOG}" 2>&1; then
  fail "preflight has blockers — run scripts/preflight.sh and fix before bootstrapping flux.
     Log: ${PREFLIGHT_LOG}"
  exit 1
fi
pass "preflight green"
rm -f "${PREFLIGHT_LOG}"

# Phase-6 gitleaks pre-commit advisory (codex MEDIUM-4 / RESEARCH.md Q10).
# CONTEXT.md "Claude's Discretion" recommended warn-only — Phase 6 REPO-04 lands the
# actual hook. This is a belt-and-suspenders advisory: PAT in .env is gitignored, so
# pre-commit gitleaks is defense-in-depth, not the primary control. Non-fatal.
section "Gitleaks pre-commit advisory"
if [ -f .git/hooks/pre-commit ] && grep -qF gitleaks .git/hooks/pre-commit; then
  pass "gitleaks pre-commit hook present"
else
  warn "gitleaks pre-commit hook not detected — Phase 6 (REPO-04) lands gitleaks before first 'git push'. PAT in .env is gitignored; this is a belt-and-suspenders advisory."
fi

# ---------- Section 2: Context + idempotency checks (D-06, D-07) ----------
section "Context + idempotency checks"

# D-06: kubectl context gate — read-only assertion; NEVER auto-switch.
ctx="$(kubectl config current-context 2>/dev/null || true)"
if [[ "${ctx}" != "${KUBE_CTX}" ]]; then
  fail "kubectl context is ${ctx:-unset}, expected ${KUBE_CTX}.
     Fix: kubectl config use-context ${KUBE_CTX}"
  exit 1
fi
pass "kubectl context: ${KUBE_CTX}"

# D-07: three-part idempotency AND (ns exists AND flux check AND 4 controllers Available).
# Pitfall 4 guard: count deployments BEFORE kubectl wait --all (empty set trivially passes).
ns_ok=0; check_ok=0; ctrl_ok=0

if kubectl --context "${KUBE_CTX}" get ns "${FLUX_NS}" >/dev/null 2>&1; then
  ns_ok=1
fi

if flux --context "${KUBE_CTX}" check >/dev/null 2>&1; then
  check_ok=1
fi

# Count controllers whose Available condition is True.
ctrl_ready="$(kubectl --context "${KUBE_CTX}" -n "${FLUX_NS}" get deploy \
  -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Available")].status}{"\n"}{end}' 2>/dev/null \
  | grep -cx "True" || true)"
if [[ "${ctrl_ready}" -eq 4 ]]; then
  ctrl_ok=1
fi

SKIP_BOOTSTRAP=0
if [[ ${ns_ok} -eq 1 && ${check_ok} -eq 1 && ${ctrl_ok} -eq 1 ]]; then
  info "already done, skipping: flux bootstrap (ns=present, flux check=ok, 4 controllers Available)"
  SKIP_BOOTSTRAP=1
fi

# ---------- Section 3: flux bootstrap github (D-01..D-04, D-08, D-11) ----------
if [[ ${SKIP_BOOTSTRAP} -eq 0 ]]; then
  section "flux bootstrap"

  # D-11: load .env into environment (NOT stdout). Preflight PRE-09 already verified
  # presence + non-emptiness of the 3 keys; we trust that gate and simply source.
  set -a
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/.env"
  set +a

  # D-01..D-04 flag surface; D-11 token passing.
  # GITHUB_TOKEN is re-exported explicitly into the flux process environment.
  # It does NOT appear in `ps auxww` (argv only shows --owner / --repository / etc.).
  # --token-auth is a boolean toggle; flux reads GITHUB_TOKEN from env.
  #
  # --network-policy=false (codex LOW-1): this is a single-user lab with no adversarial namespace
  # boundary; we disable Flux's default deny-all NetworkPolicy on flux-system to
  # reduce debug surface. Note: k3s ships an embedded kube-router netpol controller, so the
  # NP would actually be enforced (RESEARCH.md Pitfall 6 corrects CONTEXT.md D-03's
  # "flannel does not enforce NetworkPolicies" claim). The flag value is unchanged; this
  # comment exists so a maintainer reading the script sees the corrected rationale at the
  # call site rather than only in the plan threat-model. See docs/flux-hub-spoke.md Rule 3
  # footnote and 03-02-PLAN.md threat model T-3-05 for the full correction trail.
  GITHUB_TOKEN="${GITHUB_TOKEN}" flux bootstrap github \
    --owner "${GITHUB_OWNER}" \
    --repository "${GITHUB_REPO}" \
    --path "${FLUX_PATH}" \
    --personal \
    --private=false \
    --network-policy=false \
    --token-auth \
    --branch main
  pass "flux bootstrap complete"
fi
