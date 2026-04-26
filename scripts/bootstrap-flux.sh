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

  # D-11 + CR-02: load .env keys as DATA, not as shell. The parser only ever runs
  # `grep -E '^KEY=' .env` against the three expected keys; it never sources or
  # runs the file as shell. A malicious .env with extra shell statements between keys
  # cannot trigger execution because no line is ever passed to the shell as code.
  # Strips at most one pair of surrounding single OR double quotes from the value.
  load_env_key() {
    local key="$1" raw val
    if [[ ! -f "${REPO_ROOT}/.env" ]]; then
      fail "${REPO_ROOT}/.env missing — preflight PRE-09 should have caught this; rerun: scripts/preflight.sh"
      exit 1
    fi
    raw="$(grep -E "^${key}=" "${REPO_ROOT}/.env" | tail -n1 | cut -d= -f2-)"
    # Strip at most one pair of matching surrounding quotes (single or double).
    val="${raw}"
    if [[ "${val}" == \"*\" || "${val}" == \'*\' ]]; then
      val="${val:1:${#val}-2}"
    fi
    if [[ -z "${val}" ]]; then
      fail "${key} missing or empty in ${REPO_ROOT}/.env — fix the value and rerun. (Preflight PRE-09 covers presence; an empty value bypasses that gate.)"
      exit 1
    fi
    printf -v "${key}" '%s' "${val}"
    export "${key?}"
  }

  load_env_key GITHUB_OWNER
  load_env_key GITHUB_REPO
  load_env_key GITHUB_TOKEN

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

# ---------- Section 4: Post-bootstrap verification (D-09, D-10) ----------
# Runs on BOTH code paths (skip-if-healthy AND fresh-bootstrap) to close the loop:
# the skip path re-proves health; the fresh path proves bootstrap succeeded.
section "Post-bootstrap verification"

# D-09 gate 1: flux check
if ! flux --context "${KUBE_CTX}" check >/dev/null 2>&1; then
  fail "flux check failed post-bootstrap.
     Debug: flux --context ${KUBE_CTX} check
     Logs:  flux --context ${KUBE_CTX} logs"
  exit 1
fi
pass "flux check: ok"

# D-09 gate 2 + Pitfall 4: assert 4 deployments exist BEFORE kubectl wait --all
# (wait --all on an empty set trivially returns 0 — would mask a total bootstrap failure).
deploy_count="$(kubectl --context "${KUBE_CTX}" -n "${FLUX_NS}" get deploy --no-headers 2>/dev/null | wc -l)"
if [[ "${deploy_count}" -ne 4 ]]; then
  fail "expected 4 flux controllers in ${FLUX_NS}, found ${deploy_count}.
     Fix: kubectl --context ${KUBE_CTX} -n ${FLUX_NS} get deploy,pod"
  exit 1
fi
# D-10: idiomatic 120s wait — not a custom bash poll.
if ! kubectl --context "${KUBE_CTX}" -n "${FLUX_NS}" wait \
       --for=condition=Available deploy --all --timeout=120s >/dev/null 2>&1; then
  fail "flux controllers did not reach Ready in 120s.
     Inspect: kubectl --context ${KUBE_CTX} -n ${FLUX_NS} get deploy,pod
     Logs:    flux --context ${KUBE_CTX} logs"
  exit 1
fi
pass "4 flux controllers Available within 120s"

# D-09 gate 3: flux-system Kustomization Ready=True.
# Use kubectl jsonpath (not `flux get ... | awk`) — avoids Pitfall 5 (grep Ready matching
# NotReady substring) AND avoids the column-index fragility of `flux get` table output.
ks_ready="$(kubectl --context "${KUBE_CTX}" -n "${FLUX_NS}" get kustomization "${FLUX_NS}" \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
if [[ "${ks_ready}" != "True" ]]; then
  fail "flux-system Kustomization not Ready=True (got: ${ks_ready:-unknown}).
     Inspect: flux --context ${KUBE_CTX} get kustomizations ${FLUX_NS}
     Logs:    flux --context ${KUBE_CTX} logs --kind=Kustomization"
  exit 1
fi
pass "Kustomization ${FLUX_NS}: Ready=True"

# ---------- Section 5: Patch-surface marker (D-13) ----------
section "Patch-surface marker"

# CR-01 fix: flux bootstrap github writes manifests through a temporary git worktree
# and pushes to GitHub — it does NOT update THIS local checkout. If KUST_FILE is
# absent locally, the bootstrap manifests are on the remote `main` branch but not
# here. Sync via fast-forward pull, gated on a clean worktree under ${FLUX_PATH} so
# we never clobber local work.
if [[ ! -f "${KUST_FILE}" ]]; then
  info "local checkout missing ${FLUX_PATH}/${FLUX_NS}/kustomization.yaml — bootstrap pushed manifests remotely; attempting fast-forward sync"
  # Refuse the sync if the developer has uncommitted changes ANYWHERE under FLUX_PATH.
  # Scope the dirty-check to FLUX_PATH only (not the whole repo) so unrelated WIP elsewhere
  # in the tree does not block bootstrap completion.
  if ! git -C "${REPO_ROOT}" diff --quiet -- "${FLUX_PATH}" 2>/dev/null \
     || ! git -C "${REPO_ROOT}" diff --cached --quiet -- "${FLUX_PATH}" 2>/dev/null; then
    fail "uncommitted changes detected under ${FLUX_PATH}/ in this checkout — refusing to fast-forward.
   Inspect: git -C ${REPO_ROOT} status -- ${FLUX_PATH}
   Fix:     commit or stash those changes, then rerun: bash scripts/bootstrap-flux.sh
   (git -C ${REPO_ROOT} stash push -- ${FLUX_PATH} OR git -C ${REPO_ROOT} add ${FLUX_PATH} && git commit)"
    exit 1
  fi
  # Fetch the remote main branch and fast-forward this checkout. --ff-only refuses any
  # divergence (e.g. a force-push, a different bootstrap path) and surfaces it loudly.
  if ! git -C "${REPO_ROOT}" pull --ff-only origin main; then
    fail "git pull --ff-only origin main failed after flux bootstrap pushed manifests.
   Possible causes: branch divergence (someone else pushed), wrong remote (\"origin\"
   does not point to ${GITHUB_OWNER}/${GITHUB_REPO}), or no network connectivity.
   Inspect: git -C ${REPO_ROOT} remote -v && git -C ${REPO_ROOT} log -3 origin/main
   Fix:     reconcile manually, then rerun: bash scripts/bootstrap-flux.sh"
    exit 1
  fi
  pass "fast-forward sync complete (${FLUX_PATH} now contains bootstrap manifests)"
fi

if [[ ! -f "${KUST_FILE}" ]]; then
  fail "expected ${KUST_FILE} missing AFTER sync — flux bootstrap did not commit it, or origin/main does not contain the bootstrap commit.
   Inspect: ls -la ${REPO_ROOT}/${FLUX_PATH}/${FLUX_NS}/
            git -C ${REPO_ROOT} log --oneline -10 origin/main -- ${FLUX_PATH}/${FLUX_NS}/
   Fix:     verify --path clusters/hub-flux is correct and the bootstrap commit is on origin/main; rerun bootstrap if needed."
  exit 1
fi

if grep -qF '# FLUX PATCH SURFACE' "${KUST_FILE}"; then
  info "already done, skipping: patch-surface marker present"
else
  tmp="$(mktemp)"
  {
    cat <<'EOF'
# ──────────────────────────────────────────────────────────────────────────
# FLUX PATCH SURFACE
#
# This file IS the supported patch surface for the hub-flux bootstrap.
# Edits here SURVIVE re-bootstrap — add `patches:`, `configMapGenerator:`,
# `images:` etc. here to customize the 4 core controllers.
#
# Peer files in this directory — gotk-components.yaml, gotk-sync.yaml —
# are bootstrap-managed and WILL be overwritten by `flux bootstrap`.
# Do NOT hand-edit them.
#
# See: docs/flux-hub-spoke.md
# ──────────────────────────────────────────────────────────────────────────
EOF
    cat "${KUST_FILE}"
  } > "${tmp}"
  mv "${tmp}" "${KUST_FILE}"
  pass "applied: patch-surface marker prepended to ${FLUX_PATH}/${FLUX_NS}/kustomization.yaml"
fi

# Developer-flow hint (codex HIGH-3): the marker prepend is a LOCAL edit. flux bootstrap
# already pushed the bootstrap files to GitHub; for the marker to be part of the GitOps
# tree Flux reconciles, the developer must commit + push this local diff. The script
# intentionally does NOT auto-push (matches the broader "no automated git mutations"
# posture). Distinguish two cases by comparing the working-tree file to its HEAD blob:
#   - diverging  → tell the developer to commit + push
#   - clean      → in HEAD already, no action needed
if git -C "${REPO_ROOT}" diff --quiet -- "${FLUX_PATH}/${FLUX_NS}/kustomization.yaml" 2>/dev/null; then
  info "patch-surface marker already in HEAD — no commit needed"
else
  info "patch-surface marker added to ${FLUX_PATH}/${FLUX_NS}/kustomization.yaml — commit and push so Flux reconciles a tree containing the marker: git add ${FLUX_PATH}/${FLUX_NS}/kustomization.yaml && git commit -m 'docs(03): add patch-surface marker' && git push"
fi

# ---------- Summary ----------
section "Summary"
printf "  %s%d passed%s, %s%d warnings%s, %s%d failed%s\n" \
  "${C_GREEN}" "${PASS}" "${C_RESET}" "${C_YELLOW}" "${WARN}" "${C_RESET}" "${C_RED}" "${FAIL}" "${C_RESET}"
if (( FAIL > 0 )); then exit 1; fi
printf "\n%sflux hub bootstrap complete — k3d-hub-flux is now GitOps-managed from %s/%s (%s).%s\n" \
  "${C_GREEN}" "${GITHUB_OWNER:-<owner>}" "${GITHUB_REPO:-<repo>}" "${FLUX_PATH}" "${C_RESET}"
