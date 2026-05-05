#!/usr/bin/env bash
# scripts/poc/capsule/issue-tenant-kubeconfig.sh
# Mints a tenant owner kubeconfig that routes through capsule-proxy NodePort 30443.
#
# REQs: PROXY-01 / PROXY-02 / PROXY-03.
# Decisions: D-10-01 (TokenRequest API), D-10-03 (<owner> = existing SA), D-10-06 (TLS embed via tls.crt).
# Isolation: P31 (POC isolation -- script lives under scripts/poc/capsule/, never invoked by task rebuild).
# ADR-004: hub-only Flux -- this script reads from spoke-capsule directly (no Flux on spoke per ADR-004).
#
# Idempotency: each invocation produces a fresh TokenRequest token (no state mutation). Operator
# re-runs to refresh tokens; running twice produces two valid kubeconfigs (different iat claims).
#
# Stdout/stderr contract (Pitfall 10-P7): stdout = pure YAML kubeconfig; stderr = preflight-lib
# log lines. Mechanism: preflight-lib helpers are intercepted at function-definition time via
# local override functions (see overrides below). Every log line goes to stderr automatically.
# This is the function-override mechanism endorsed by RESEARCH §Pitfall 10-P7; per-call-site
# `>&2` redirect is equivalent and explicitly NOT used here. The chosen approach avoids ~50
# per-call-site redirects throughout the script.
#
# Pitfall 10-P1: capsule-proxy Secret has tls.crt + tls.key keys ONLY (no ca.crt). The chart's
# kube-webhook-certgen Job runs with --cert-name=tls.crt --key-name=tls.key and self-signs;
# tls.crt IS the CA root. Script reads tls.crt directly via jsonpath '{.data.tls\.crt}'.
#
# Pitfall 10-P2: k3s on this pin does NOT clamp at 24h. --duration is honored exactly (verified
# live for up to 720h). The info-warn at >24h is a portability note for distros that DO clamp via
# --service-account-max-token-expiration.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# shellcheck source=../../lib/preflight-lib.sh
# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/lib/preflight-lib.sh"

# Pitfall 10-P7 stderr-redirect mechanism: function-override at definition time.
# preflight-lib helpers write to stdout by default. Stdout in THIS script is the kubeconfig YAML
# payload -- log lines on stdout would corrupt it. We override each helper with a local function
# that internally redirects to >&2. Every subsequent call site emits to stderr automatically; no
# per-call-site `>&2` annotation needed. This is the recommended approach per RESEARCH §Pitfall
# 10-P7 (per-call-site `>&2` is equivalent and explicitly not used). Cleanest blast radius:
# leave create-cluster.sh / fix-dns.sh untouched (they emit human-readable summaries on stdout,
# which is the right behavior for those scripts -- they don't need this override).
section() { command section "$@" >&2 2>/dev/null || printf '== %s ==\n' "$*" >&2; }
pass() { command pass "$@" >&2 2>/dev/null || printf '  ok  %s\n' "$*" >&2; }
info() { command info "$@" >&2 2>/dev/null || printf '  --  %s\n' "$*" >&2; }
warn() { command warn "$@" >&2 2>/dev/null || printf '  !!  %s\n' "$*" >&2; }
fail() { command fail "$@" >&2 2>/dev/null || printf '  xx  %s\n' "$*" >&2; }

# D-10 pins (LOCKED -- bats grep-asserts these literals):
readonly POC_CTX="k3d-spoke-capsule"
readonly POC_NODEPORT="30443"
readonly DEFAULT_DURATION="1h"
readonly TMPDIR_DEFAULT="${TMPDIR:-/tmp}"
readonly TENANT_TMPDIR="${TMPDIR_DEFAULT}/karyon-tenants"

# ---------- Usage ----------
usage() {
  cat <<USAGE_EOF >&2
Usage: $(basename "$0") <tenant> <owner> [--duration <d>] [--write-to <path>]

Mints a tenant-owner kubeconfig that routes through capsule-proxy NodePort 30443.

Args:
  <tenant>        Tenant name (e.g., alpha, bravo). MUST match existing Tenant CR on spoke-capsule.
  <owner>         ServiceAccount name in tenant-<tenant> namespace (currently: gitops-reconciler).

Flags:
  --duration <d>  TokenRequest duration (default: ${DEFAULT_DURATION}). Valid: golang time.Duration string (e.g., 1h, 24h, 7d).
                  k3s on this pin does NOT clamp; --duration is honored exactly. Other distros may
                  clamp at --service-account-max-token-expiration. Info-warn if > 24h.
  --write-to <p>  Write kubeconfig to <p> instead of stdout. <p> MUST resolve under ${TENANT_TMPDIR}/.
                  Symlink escape (e.g., ../../etc/passwd) is rejected via realpath -m prefix check.
  --help          This help.

Examples:
  bash scripts/poc/capsule/issue-tenant-kubeconfig.sh alpha gitops-reconciler 2>/dev/null > /tmp/alpha.kc
  bash scripts/poc/capsule/issue-tenant-kubeconfig.sh alpha gitops-reconciler --duration 24h \\
       --write-to ${TENANT_TMPDIR}/alpha.kubeconfig

References:
  Phase 10 PROXY-01..03 + D-10-01 (TokenRequest) + D-10-03 (<owner> = SA) + D-10-06 (TLS embed)
  Phase 7 P31 (POC isolation: this script lives under scripts/poc/capsule/, never invoked by task rebuild)
  ADR-004 (hub-only Flux: NO Flux on spoke-capsule)
USAGE_EOF
  exit "${1:-0}"
}

# ---------- Argument parsing ----------
TENANT=""
OWNER=""
DURATION="${DEFAULT_DURATION}"
WRITE_TO=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --duration) DURATION="${2:?--duration requires a value}"; shift 2 ;;
    --write-to) WRITE_TO="${2:?--write-to requires a value}"; shift 2 ;;
    --help|-h)  usage 0 ;;
    --*)        fail "unknown flag: $1"; usage 1 ;;
    *)          if [[ -z "$TENANT" ]]; then TENANT="$1"; shift
                elif [[ -z "$OWNER" ]]; then OWNER="$1"; shift
                else fail "unexpected positional arg: $1"; usage 1
                fi ;;
  esac
done

[[ -z "$TENANT" ]] && { fail "missing positional <tenant>"; usage 1; }
[[ -z "$OWNER"  ]] && { fail "missing positional <owner>"; usage 1; }

# ---------- Section 1: Tool gate ----------
section "Tool gate"
for cmd in kubectl jq realpath; do
  if ! have "$cmd"; then
    fail "required command missing: $cmd.
       Fix: install project tools with asdf, then rerun: bash scripts/poc/capsule/issue-tenant-kubeconfig.sh ${TENANT} ${OWNER}"
    exit 1
  fi
done
pass "required commands present (kubectl, jq, realpath)"

# ---------- Section 2: kubeconfig context exists ----------
section "Context check"
if ! kubectl config get-contexts "${POC_CTX}" -o name >/dev/null 2>&1; then
  fail "kubeconfig context '${POC_CTX}' not found.
       Inspect: kubectl config get-contexts
       Fix:     k3d kubeconfig get spoke-capsule | tee -a \$HOME/.kube/config
       Or rerun: bash scripts/poc/capsule/create-cluster.sh"
  exit 1
fi
pass "context '${POC_CTX}' present"

# ---------- Section 3: Tenant CR exists ----------
section "Tenant CR check"
if ! kubectl --context="${POC_CTX}" get tenant "${TENANT}" >/dev/null 2>&1; then
  fail "Tenant CR '${TENANT}' not found on ${POC_CTX}.
       Inspect: kubectl --context=${POC_CTX} get tenants
       Fix:     run /gsd-execute-phase 9 first if Phase 9 has not landed yet."
  exit 1
fi
pass "Tenant CR '${TENANT}' exists"

# ---------- Section 4: Owner SA exists ----------
section "Owner SA check (D-10-03)"
if ! kubectl --context="${POC_CTX}" -n "tenant-${TENANT}" get sa "${OWNER}" >/dev/null 2>&1; then
  AVAILABLE_SAS=$(kubectl --context="${POC_CTX}" -n "tenant-${TENANT}" get sa -o name 2>/dev/null \
      | sed 's|serviceaccount/||g' | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g')
  fail "Owner '${OWNER}' SA not found in namespace tenant-${TENANT}.
       Available SAs in this tenant: ${AVAILABLE_SAS:-<none>}.
       Hint: run /gsd-execute-phase 9 first if Phase 9 has not landed yet,
             or pass a known SA name (currently only 'gitops-reconciler')."
  exit 1
fi
pass "owner SA '${OWNER}' exists in tenant-${TENANT}"

# ---------- Section 5: --write-to validation ----------
if [[ -n "$WRITE_TO" ]]; then
  section "--write-to validation (T-10-02 mitigation)"
  RESOLVED=$(realpath -m "$WRITE_TO")
  TMPDIR_RESOLVED=$(realpath -m "${TENANT_TMPDIR}")
  if [[ "$RESOLVED" != "${TMPDIR_RESOLVED}/"* ]]; then
    fail "--write-to '${WRITE_TO}' is outside ${TENANT_TMPDIR}/.
       Hint: tenant kubeconfigs MUST live in tmpdir per Phase 10 PROXY-03 + Phase 7 P29 invariant.
       Try: --write-to ${TENANT_TMPDIR}/${TENANT}.kubeconfig"
    exit 1
  fi
  mkdir -p "$(dirname "$RESOLVED")"
  pass "write target '${RESOLVED}' inside ${TENANT_TMPDIR}/"
fi

# ---------- Section 6: Duration portability info-warn ----------
DURATION_HOURS=$(echo "$DURATION" | sed -E 's/^([0-9]+)h.*$/\1/' | grep -E '^[0-9]+$' || echo "0")
if [[ "$DURATION_HOURS" -gt 24 ]]; then
  info "duration ${DURATION} is honored exactly on this k3s pin (no apiserver clamp). Other k8s distros may clamp at --service-account-max-token-expiration; verify before relying on durations >24h in production."
fi

# ---------- Section 7: Mint TokenRequest token ----------
section "Mint TokenRequest token (D-10-01)"
TOKEN=$(kubectl --context=k3d-spoke-capsule create token "${OWNER}" -n "tenant-${TENANT}" --duration="${DURATION}")
pass "token issued (duration ${DURATION})"

# ---------- Section 8: Read CA cert (Pitfall 10-P1: tls.crt only, no ca.crt) ----------
section "Read proxy CA cert (D-10-06 / Pitfall 10-P1: tls.crt only)"
CA_B64=$(kubectl --context=k3d-spoke-capsule -n capsule-system \
    get secret capsule-proxy -o jsonpath='{.data.tls\.crt}' 2>/dev/null || true)
if [[ -z "$CA_B64" ]]; then
  warn "capsule-proxy Secret tls.crt is empty (chart cert rotation in flight?). Retrying once after 5s..."
  sleep 5
  CA_B64=$(kubectl --context=k3d-spoke-capsule -n capsule-system \
      get secret capsule-proxy -o jsonpath='{.data.tls\.crt}' 2>/dev/null || true)
fi
if [[ -z "$CA_B64" ]]; then
  fail "capsule-proxy Secret tls.crt is empty after retry.
       Inspect: kubectl --context=${POC_CTX} -n capsule-system get secret capsule-proxy -o jsonpath='{.data}' | jq 'keys'
       Hint:    capsule-proxy may not yet be installed on spoke-capsule (Phase 8 D-08-13 push-gate deferred to Phase 11 VAL-05)."
  exit 1
fi
pass "tls.crt read (chart-self-signed CA root)"

# ---------- Section 9: Emit kubeconfig (D-10-07: heredoc with parameterized values) ----------
section "Emit kubeconfig"

emit_kubeconfig() {
  cat <<KUBECONFIG_EOF
apiVersion: v1
kind: Config
clusters:
  - name: capsule-proxy-127.0.0.1
    cluster:
      server: https://127.0.0.1:30443
      certificate-authority-data: ${CA_B64}
users:
  - name: ${OWNER}
    user:
      token: ${TOKEN}
contexts:
  - name: tenant-${TENANT}-via-proxy
    context:
      cluster: capsule-proxy-127.0.0.1
      user: ${OWNER}
      namespace: tenant-${TENANT}
current-context: tenant-${TENANT}-via-proxy
KUBECONFIG_EOF
}

if [[ -n "$WRITE_TO" ]]; then
  emit_kubeconfig > "$RESOLVED"
  pass "kubeconfig written to ${RESOLVED}"
else
  emit_kubeconfig
  pass "kubeconfig emitted to stdout (proxy: https://127.0.0.1:30443; default ns: tenant-${TENANT})"
fi
