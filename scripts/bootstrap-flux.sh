#!/usr/bin/env bash
# scripts/bootstrap-flux.sh
# Runs `flux bootstrap github` on k3d-hub-flux with --path locked to
# clusters/hub-flux (effectively immutable after first run).
# Sources GITHUB_OWNER / GITHUB_REPO / GITHUB_TOKEN from the gitignored .env.
# The token is never echoed to stdout.
#
# Token safety: set -euo pipefail INTENTIONALLY omits -x (no trace of
# GITHUB_TOKEN on stdout/stderr; strict-mode only, no debug tracing).
#
# Structure:
#   Section 1: Preflight gate + gitleaks advisory
#   Section 2: Context + idempotency checks
#   Section 3: flux bootstrap
#   Section 4: Post-bootstrap verification
#   Section 5: Patch-surface marker
#
# Usage:   bash scripts/bootstrap-flux.sh
# Pre-req: scripts/preflight.sh exits 0 (port 6443 already bound by an existing
#          hub-flux cluster produces a warn, not a fail — preflight tolerates it);
#          kubectl context is k3d-hub-flux;
#          .env has GITHUB_OWNER / GITHUB_REPO / GITHUB_TOKEN non-empty.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/preflight-lib.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/preflight-lib.sh"

# Constants — --path is intentionally hard-coded; do NOT parameterize.
readonly FLUX_PATH="clusters/hub-flux"
readonly KUBE_CTX="k3d-hub-flux"
readonly FLUX_NS="flux-system"
readonly KUST_FILE="${REPO_ROOT}/${FLUX_PATH}/${FLUX_NS}/kustomization.yaml"
ENV_KEYS_LOADED=0

load_env_key() {
  local key="$1" raw val first last
  if [[ ! -f "${REPO_ROOT}/.env" ]]; then
    fail "${REPO_ROOT}/.env missing — the preflight .env check should have caught this; rerun: scripts/preflight.sh"
    exit 1
  fi
  raw="$(grep -E "^${key}=" "${REPO_ROOT}/.env" | tail -n1 | cut -d= -f2-)"
  val="${raw}"
  if [[ ${#val} -ge 2 ]]; then
    first="${val:0:1}"
    last="${val: -1}"
    if [[ "${first}" == "${last}" && ( "${first}" == "'" || "${first}" == '"' ) ]]; then
      val="${val:1:${#val}-2}"
    elif [[ "${first}" == "'" || "${first}" == '"' ]]; then
      fail "${key} has an unmatched leading quote in ${REPO_ROOT}/.env — fix the value and rerun."
      exit 1
    fi
  elif [[ "${val}" == "'" || "${val}" == '"' ]]; then
    fail "${key} has an unmatched quote in ${REPO_ROOT}/.env — fix the value and rerun."
    exit 1
  fi
  if [[ -z "${val}" ]]; then
    fail "${key} missing or empty in ${REPO_ROOT}/.env — fix the value and rerun. (Preflight covers key presence; an empty value bypasses that gate.)"
    exit 1
  fi
  printf -v "${key}" '%s' "${val}"
  export "${key?}"
}

load_github_env() {
  if [[ "${ENV_KEYS_LOADED}" -eq 1 ]]; then
    return 0
  fi
  load_env_key GITHUB_OWNER
  load_env_key GITHUB_REPO
  load_env_key GITHUB_TOKEN
  ENV_KEYS_LOADED=1
}

origin_matches_env_repo() {
  local url expected_slug
  expected_slug="${GITHUB_OWNER}/${GITHUB_REPO}"
  url="$(git -C "${REPO_ROOT}" remote get-url origin 2>/dev/null || true)"
  case "${url}" in
    "git@github.com:${expected_slug}.git"|"https://github.com/${expected_slug}.git"|"https://github.com/${expected_slug}")
      return 0
      ;;
  esac
  fail "git origin does not match GITHUB_OWNER/GITHUB_REPO from .env; refusing to bootstrap before mutating GitHub.
     Fix: set origin to github.com/${expected_slug}.git or update .env to match this checkout."
  exit 1
}

check_flux_path_clean_for_sync() {
  local untracked
  if ! git -C "${REPO_ROOT}" diff --quiet -- "${FLUX_PATH}" 2>/dev/null \
     || ! git -C "${REPO_ROOT}" diff --cached --quiet -- "${FLUX_PATH}" 2>/dev/null; then
    fail "uncommitted changes detected under ${FLUX_PATH}/ in this checkout — refusing bootstrap sync.
     Inspect: git -C ${REPO_ROOT} status -- ${FLUX_PATH}
     Fix:     commit or stash those changes, then rerun: bash scripts/bootstrap-flux.sh"
    exit 1
  fi
  untracked="$(git -C "${REPO_ROOT}" ls-files --others --exclude-standard -- "${FLUX_PATH}" 2>/dev/null || true)"
  if [[ -n "${untracked}" ]]; then
    printf "%s\n" "${untracked}" >&2
    fail "untracked files detected under ${FLUX_PATH}/ in this checkout — refusing bootstrap sync.
     Fix: commit, stash, or remove those files, then rerun: bash scripts/bootstrap-flux.sh"
    exit 1
  fi
}

check_origin_main_fast_forwardable() {
  if ! git -C "${REPO_ROOT}" fetch origin main >/dev/null 2>&1; then
    fail "could not fetch origin/main before bootstrap.
     Inspect: git -C ${REPO_ROOT} remote -v
     Fix:     verify network access and that origin points to the GitHub repo in .env, then rerun: bash scripts/bootstrap-flux.sh"
    exit 1
  fi
  if ! git -C "${REPO_ROOT}" merge-base --is-ancestor HEAD origin/main; then
    fail "local main has commits that are not on origin/main; first bootstrap cannot finish with git pull --ff-only after Flux pushes manifests.
     Fix: push local main first, or merge/rebase origin/main locally, then rerun: bash scripts/bootstrap-flux.sh"
    exit 1
  fi
}

# ---------- Section 1: Preflight gate + gitleaks advisory ----------
section "Preflight gate"
PREFLIGHT_LOG="$(mktemp -t karyon-preflight.XXXXXX.log)"
# Note: scripts/preflight.sh emits port-in-use and existing-k3d-cluster checks
# as WARN (not FAIL). Once clusters exist, port 6443 is bound by k3d-hub-flux's
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
load_github_env

# Gitleaks pre-commit advisory (warn-only — the actual hook is wired by
# scripts/install-tools.sh via core.hooksPath). This is a belt-and-suspenders
# advisory: PAT in .env is gitignored, so pre-commit gitleaks is
# defense-in-depth, not the primary control. Non-fatal.
section "Gitleaks pre-commit advisory"
GITLEAKS_HOOK="${REPO_ROOT}/.git/hooks/pre-commit"
if [ -f "${GITLEAKS_HOOK}" ] && grep -qF gitleaks "${GITLEAKS_HOOK}"; then
  pass "gitleaks pre-commit hook present"
else
  warn "gitleaks pre-commit hook not detected — run 'bash scripts/install-tools.sh' to wire it before your first 'git push'. PAT in .env is gitignored; this is a belt-and-suspenders advisory."
fi

# ---------- Section 2: Context + idempotency checks ----------
section "Context + idempotency checks"

# kubectl context gate — read-only assertion; NEVER auto-switch.
ctx="$(kubectl config current-context 2>/dev/null || true)"
if [[ "${ctx}" != "${KUBE_CTX}" ]]; then
  fail "kubectl context is ${ctx:-unset}, expected ${KUBE_CTX}.
     Fix: kubectl config use-context ${KUBE_CTX}"
  exit 1
fi
pass "kubectl context: ${KUBE_CTX}"

# Three-part idempotency gate: ns exists AND flux check AND 4 controllers Available.
# Count deployments BEFORE kubectl wait --all (an empty set trivially passes the wait).
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

# If bootstrap has to create manifests remotely and this checkout does not have
# them yet, prove before the remote write that the post-bootstrap sync can finish.
# This blocks the known local-ahead/diverged branch state that would otherwise let
# `flux bootstrap github` mutate origin/main before `git pull --ff-only` fails.
if [[ ${SKIP_BOOTSTRAP} -eq 0 ]]; then
  check_flux_path_clean_for_sync
  load_github_env
  origin_matches_env_repo
  if [[ ! -f "${KUST_FILE}" ]]; then
    check_origin_main_fast_forwardable
  fi
fi

# ---------- Section 3: flux bootstrap github ----------
if [[ ${SKIP_BOOTSTRAP} -eq 0 ]]; then
  section "flux bootstrap"

  # Load .env keys as DATA, not as shell. The parser only ever runs
  # `grep -E '^KEY=' .env` against the three expected keys; it never sources or
  # runs the file as shell. A malicious .env with extra shell statements between keys
  # cannot trigger execution because no line is ever passed to the shell as code.
  load_github_env

  # GITHUB_TOKEN is re-exported explicitly into the flux process environment.
  # It does NOT appear in `ps auxww` (argv only shows --owner / --repository / etc.).
  # --token-auth is a boolean toggle; flux reads GITHUB_TOKEN from env.
  #
  # --network-policy=false: this is a single-user lab with no adversarial namespace
  # boundary; we disable Flux's default deny-all NetworkPolicy on flux-system to
  # reduce debug surface. Note: k3s ships an embedded kube-router netpol controller,
  # so the NetworkPolicy WOULD actually be enforced — the common claim that
  # flannel-based k3s cannot enforce NetworkPolicies is wrong. See the
  # docs/flux-hub-spoke.md Rule 3 footnote.
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

# ---------- Section 4: Post-bootstrap verification ----------
# Runs on BOTH code paths (skip-if-healthy AND fresh-bootstrap) to close the loop:
# the skip path re-proves health; the fresh path proves bootstrap succeeded.
section "Post-bootstrap verification"

# Gate 1: flux check
if ! flux --context "${KUBE_CTX}" check >/dev/null 2>&1; then
  fail "flux check failed post-bootstrap.
     Debug: flux --context ${KUBE_CTX} check
     Logs:  flux --context ${KUBE_CTX} logs"
  exit 1
fi
pass "flux check: ok"

# Gate 2: assert 4 deployments exist BEFORE kubectl wait --all
# (wait --all on an empty set trivially returns 0 — would mask a total bootstrap failure).
deploy_count="$(kubectl --context "${KUBE_CTX}" -n "${FLUX_NS}" get deploy --no-headers 2>/dev/null | wc -l)"
if [[ "${deploy_count}" -ne 4 ]]; then
  fail "expected 4 flux controllers in ${FLUX_NS}, found ${deploy_count}.
     Fix: kubectl --context ${KUBE_CTX} -n ${FLUX_NS} get deploy,pod"
  exit 1
fi
# Idiomatic 120s wait — not a custom bash poll.
if ! kubectl --context "${KUBE_CTX}" -n "${FLUX_NS}" wait \
       --for=condition=Available deploy --all --timeout=120s >/dev/null 2>&1; then
  fail "flux controllers did not reach Ready in 120s.
     Inspect: kubectl --context ${KUBE_CTX} -n ${FLUX_NS} get deploy,pod
     Logs:    flux --context ${KUBE_CTX} logs"
  exit 1
fi
pass "4 flux controllers Available within 120s"

# Gate 3: flux-system Kustomization Ready=True.
# Use kubectl jsonpath (not `flux get ... | awk`) — a bare `grep Ready` would match
# the NotReady substring, and `flux get` table output has fragile column indexes.
ks_ready="$(kubectl --context "${KUBE_CTX}" -n "${FLUX_NS}" get kustomization "${FLUX_NS}" \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
if [[ "${ks_ready}" != "True" ]]; then
  fail "flux-system Kustomization not Ready=True (got: ${ks_ready:-unknown}).
     Inspect: flux --context ${KUBE_CTX} get kustomizations ${FLUX_NS}
     Logs:    flux --context ${KUBE_CTX} logs --kind=Kustomization"
  exit 1
fi
pass "Kustomization ${FLUX_NS}: Ready=True"

# ---------- Section 5: Patch-surface marker ----------
section "Patch-surface marker"

# flux bootstrap github writes manifests through a temporary git worktree
# and pushes to GitHub — it does NOT update THIS local checkout. If KUST_FILE is
# absent locally, the bootstrap manifests are on the remote `main` branch but not
# here. Sync via fast-forward pull, gated on a clean worktree under ${FLUX_PATH} so
# we never clobber local work.
if [[ ! -f "${KUST_FILE}" ]]; then
  info "local checkout missing ${FLUX_PATH}/${FLUX_NS}/kustomization.yaml — bootstrap pushed manifests remotely; attempting fast-forward sync"
  check_flux_path_clean_for_sync
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

# Developer-flow hint: the marker prepend is a LOCAL edit. flux bootstrap
# already pushed the bootstrap files to GitHub; for the marker to be part of the GitOps
# tree Flux reconciles, the developer must commit + push this local diff. The script
# intentionally does NOT auto-push (matches the broader "no automated git mutations"
# posture). Distinguish two cases by comparing the working-tree file to its HEAD blob:
#   - diverging  → tell the developer to commit + push
#   - clean      → in HEAD already, no action needed
if git -C "${REPO_ROOT}" diff --quiet -- "${FLUX_PATH}/${FLUX_NS}/kustomization.yaml" 2>/dev/null; then
  info "patch-surface marker already in HEAD — no commit needed"
else
  info "patch-surface marker added to ${FLUX_PATH}/${FLUX_NS}/kustomization.yaml — commit and push so Flux reconciles a tree containing the marker: git add ${FLUX_PATH}/${FLUX_NS}/kustomization.yaml && git commit -m 'docs: add patch-surface marker' && git push"
fi

if git -C "${REPO_ROOT}" fetch origin main >/dev/null 2>&1; then
  if ! git -C "${REPO_ROOT}" diff --quiet origin/main -- "${FLUX_PATH}/${FLUX_NS}/kustomization.yaml" 2>/dev/null; then
    warn "local ${FLUX_PATH}/${FLUX_NS}/kustomization.yaml differs from origin/main — push local main so Flux reconciles the marker/patches"
  fi
else
  warn "could not fetch origin/main to compare patch-surface marker state; verify GitHub contains ${FLUX_PATH}/${FLUX_NS}/kustomization.yaml before relying on reconciliation"
fi

# ---------- Summary ----------
section "Summary"
printf "  %s%d passed%s, %s%d warnings%s, %s%d failed%s\n" \
  "${C_GREEN}" "${PASS}" "${C_RESET}" "${C_YELLOW}" "${WARN}" "${C_RESET}" "${C_RED}" "${FAIL}" "${C_RESET}"
if (( FAIL > 0 )); then exit 1; fi
printf "\n%sflux hub bootstrap complete — k3d-hub-flux is now GitOps-managed from %s/%s (%s).%s\n" \
  "${C_GREEN}" "${GITHUB_OWNER:-<owner>}" "${GITHUB_REPO:-<repo>}" "${FLUX_PATH}" "${C_RESET}"
