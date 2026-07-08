#!/usr/bin/env bash
# scripts/poc/capsule/issue-tenant-kubeconfig.sh
# Mints a tenant owner kubeconfig that routes through capsule-proxy NodePort 30443.
#
# The token is minted via the TokenRequest API (kubectl create token); <owner> must be an
# EXISTING ServiceAccount in the tenant-<tenant> namespace (this script never creates
# identities). TLS trust is embedded from the capsule-proxy Secret's tls.crt.
# Standalone POC helper for the persistent spoke-capsule cluster; never invoked by task rebuild
# (enforced by tests/bats/poc-isolation-01-static.bats).
# Hub-only Flux control plane: this script reads from spoke-capsule directly -- no Flux runs
# on the spoke (see docs/adr/0004-hub-only-flux-control-plane.md).
#
# Idempotency: each invocation produces a fresh TokenRequest token (no state mutation). Operator
# re-runs to refresh tokens; running twice produces two valid kubeconfigs (different iat claims).
#
# Stdout/stderr contract: stdout = pure YAML kubeconfig; stderr = preflight-lib
# log lines. Mechanism: shadow each preflight-lib helper (section/pass/info/warn/fail) with a
# printf-to-stderr equivalent defined below. Every subsequent call site emits to stderr without
# per-call-site `>&2`. The original ANSI-colored helpers from preflight-lib are unused here --
# this script does not emit stdout summary lines (stdout is reserved for the kubeconfig YAML
# payload). Per-call-site `>&2` would be equivalent but is explicitly NOT
# used (it would require ~50 redirects throughout the script). The chosen approach avoids that.
#
# CA gotcha: capsule-proxy Secret has tls.crt + tls.key keys ONLY (no ca.crt). The chart's
# kube-webhook-certgen Job runs with --cert-name=tls.crt --key-name=tls.key and self-signs;
# tls.crt IS the CA root. Script reads tls.crt directly via jsonpath '{.data.tls\.crt}'.
#
# Duration gotcha: k3s on this pin does NOT clamp at 24h. --duration is honored exactly (verified
# live for up to 720h). The info-warn at >24h is a portability note for distros that DO clamp via
# --service-account-max-token-expiration.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# shellcheck source=../../lib/preflight-lib.sh
# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/lib/preflight-lib.sh"

# Stderr-redirect: shadow preflight-lib helpers with printf-to-stderr equivalents.
# preflight-lib helpers write to stdout by default; stdout in THIS script is the kubeconfig YAML
# payload, so log lines on stdout would corrupt it. We replace each helper with a printf-to-stderr
# function. Every subsequent call site emits to stderr without per-call-site `>&2`. The original
# ANSI-colored helpers from preflight-lib (section/pass/info/warn/fail at lines 21-25 of
# preflight-lib.sh) are intentionally NOT called here -- this script does not emit stdout summary
# lines. The PASS/WARN/FAIL counters maintained by the originals are also unused; this script
# fail-fasts via `exit 1` after a `fail` call and does not summarize counts at end-of-run.
# Cleanest blast radius: leave create-cluster.sh / fix-dns.sh untouched (they emit human-readable
# summaries on stdout, which is the right behavior for those scripts -- they don't need this).
section() { printf '== %s ==\n' "$*" >&2; }
pass()    { printf '  ok  %s\n' "$*" >&2; }
info()    { printf '  --  %s\n' "$*" >&2; }
warn()    { printf '  !!  %s\n' "$*" >&2; }
fail()    { printf '  xx  %s\n' "$*" >&2; }

# Pinned literals (LOCKED -- bats suites grep-assert these):
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
  <owner>         ServiceAccount name in tenant-<tenant> namespace; one of:
                    - gitops-reconciler  (Flux automation identity)
                    - human-tenant-owner (human-exercised tenant-owner identity)

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

Notes:
  Token is minted via the TokenRequest API; <owner> must be an existing ServiceAccount.
  Standalone POC helper: never invoked by task rebuild (tests/bats/poc-isolation-01-static.bats).
  Hub-only Flux: NO Flux runs on spoke-capsule (see docs/adr/0004-hub-only-flux-control-plane.md).
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
    # Accept both space form (`--duration 24h`) and equals form (`--duration=24h`).
    # `kubectl create token --duration=…` itself uses equals form; operators who copy
    # that style onto this script's surface previously hit "unknown flag: --duration=24h".
    --duration=*) DURATION="${1#--duration=}"; shift ;;
    --duration) DURATION="${2:?--duration requires a value}"; shift 2 ;;
    --write-to=*) WRITE_TO="${1#--write-to=}"; shift ;;
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

# Strict-format validator -- TENANT and OWNER must be valid RFC 1123 labels
# (lowercase alphanumeric + dashes, max 63 chars). Matches Tenant CR / SA / Namespace
# name validity in apiserver. Without this gate, whitespace/tab/shell-special chars
# (e.g. backticks, `$()`) flow into kubectl invocations + the unquoted KUBECONFIG_EOF
# heredoc, enabling YAML-injection if a future automation wrapper takes user-supplied
# input into TENANT/OWNER.
K8S_NAME_RE='^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$'
[[ "$TENANT" =~ $K8S_NAME_RE ]] || {
  fail "<tenant> '${TENANT}' is not a valid RFC 1123 label (lowercase a-z, 0-9, -; max 63 chars; must start and end alphanumeric)"
  exit 1
}
[[ "$OWNER" =~ $K8S_NAME_RE ]] || {
  fail "<owner> '${OWNER}' is not a valid RFC 1123 label (lowercase a-z, 0-9, -; max 63 chars; must start and end alphanumeric)"
  exit 1
}

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
       Fix:     reconcile the Tenant CRs from the hub:
                flux --context=k3d-hub-flux reconcile kustomization poc-capsule-spoke-tenants --with-source"
  exit 1
fi
pass "Tenant CR '${TENANT}' exists"

# ---------- Section 4: Owner SA exists ----------
section "Owner SA check"
if ! kubectl --context="${POC_CTX}" -n "tenant-${TENANT}" get sa "${OWNER}" >/dev/null 2>&1; then
  AVAILABLE_SAS=$(kubectl --context="${POC_CTX}" -n "tenant-${TENANT}" get sa -o name 2>/dev/null \
      | sed 's|serviceaccount/||g' | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g')
  fail "Owner '${OWNER}' SA not found in namespace tenant-${TENANT}.
       Available SAs in this tenant: ${AVAILABLE_SAS:-<none>}.
       Hint: reconcile the tenant resources from the hub:
               flux --context=k3d-hub-flux reconcile kustomization poc-capsule-spoke --with-source
             or pass a known SA name (currently 'gitops-reconciler' or 'human-tenant-owner')."
  exit 1
fi
pass "owner SA '${OWNER}' exists in tenant-${TENANT}"

# ---------- Section 5: --write-to validation ----------
if [[ -n "$WRITE_TO" ]]; then
  section "--write-to validation"
  # Tighten umask so the kubeconfig (containing a live bearer token) is
  # owner-private on creation. Default umask 0022 produces mode 0644 (world-readable);
  # 0077 produces mode 0600 (owner-only). Applied here so it covers both the
  # subsequent install -d (tmpdir 0700) and the > "$RESOLVED" redirect later.
  umask 0077
  # Defeat symlink pre-placement attack on ${TENANT_TMPDIR}.
  # If an attacker pre-places ${TENANT_TMPDIR} as a symlink to /etc (or any chosen dir),
  # `realpath -m` on both sides resolves through the symlink and the prefix check
  # passes -- but `> "$RESOLVED"` follows the symlink at write-time, landing the
  # bearer-token kubeconfig in the attacker's chosen path. Refuse on -L; create the
  # tmpdir owner-private (0700) if absent so subsequent prefix checks are meaningful.
  if [[ -L "${TENANT_TMPDIR}" ]]; then
    fail "${TENANT_TMPDIR} is a symlink -- refusing to write tenant kubeconfig.
       Hint: an attacker may have pre-placed this symlink to redirect the bearer-token
             kubeconfig to a chosen path. Inspect: ls -ld ${TENANT_TMPDIR}
             Fix:     rm -f ${TENANT_TMPDIR} && bash $(basename "$0") ${TENANT} ${OWNER}"
    exit 1
  fi
  install -d -m 0700 "${TENANT_TMPDIR}"
  RESOLVED=$(realpath -m "$WRITE_TO")
  TMPDIR_RESOLVED=$(realpath -m "${TENANT_TMPDIR}")
  if [[ "$RESOLVED" != "${TMPDIR_RESOLVED}/"* ]]; then
    fail "--write-to '${WRITE_TO}' is outside ${TENANT_TMPDIR}/.
       Hint: tenant kubeconfigs MUST live under the tmpdir so live bearer tokens never
             land in the repo or a home directory.
       Try: --write-to ${TENANT_TMPDIR}/${TENANT}.kubeconfig"
    exit 1
  fi
  mkdir -p "$(dirname "$RESOLVED")"
  # Defense in depth: after mkdir, verify the resolved parent dir is NOT a symlink.
  # Catches the secondary TOCTOU where an attacker swaps a real component of RESOLVED
  # for a symlink between the prefix check above and the redirect at end-of-script.
  PARENT_REAL=$(realpath -e "$(dirname "$RESOLVED")")
  if [[ "$PARENT_REAL" != "${TMPDIR_RESOLVED}"* ]]; then
    fail "parent dir of '${RESOLVED}' resolves outside ${TENANT_TMPDIR}/ after canonicalization.
       Hint: TOCTOU symlink swap detected. Inspect: ls -ld $(dirname "$RESOLVED")"
    exit 1
  fi
  pass "write target '${RESOLVED}' inside ${TENANT_TMPDIR}/"
fi

# ---------- Section 6: Duration portability info-warn ----------
# Convert <int><unit> duration to hours. Supports kubectl's accepted units (s/m/h/d).
# Compound forms (e.g. 1h30m) collapse to the leading numeric+unit segment, which is acceptable
# for the >24h portability heuristic -- the leading segment dominates for the values operators
# actually pass. Returns 0 for unparseable input (no false-positive warns).
duration_to_hours() {
  local d="$1"
  # Strip any trailing compound (e.g. 1h30m -> 1h) by matching only the first <int><unit>.
  local match
  if [[ "$d" =~ ^([0-9]+)([smhd]) ]]; then
    match="${BASH_REMATCH[0]}"
    local n="${BASH_REMATCH[1]}"
    local u="${BASH_REMATCH[2]}"
    case "$u" in
      s) echo $(( n / 3600 )) ;;
      m) echo $(( n / 60 ))   ;;
      h) echo "$n"             ;;
      d) echo $(( n * 24 ))   ;;
    esac
  else
    echo "0"
  fi
}
DURATION_HOURS=$(duration_to_hours "$DURATION")
if [[ "$DURATION_HOURS" -gt 24 ]]; then
  info "duration ${DURATION} is honored exactly on this k3s pin (no apiserver clamp). Other k8s distros may clamp at --service-account-max-token-expiration; verify before relying on durations >24h in production."
fi

# ---------- Section 7: Mint TokenRequest token ----------
section "Mint TokenRequest token"
TOKEN=$(kubectl --context=k3d-spoke-capsule create token "${OWNER}" -n "tenant-${TENANT}" --duration="${DURATION}")
pass "token issued (duration ${DURATION})"

# ---------- Section 8: Read CA cert (tls.crt only, no ca.crt) ----------
# Capture stderr to a tmpfile + exit code via direct subshell return so we can
# distinguish three failure modes (was previously collapsed by `2>/dev/null || true`):
#   (a) Secret exists but tls.crt key is empty (CA_B64="", RC=0 -> chart-rotation retry)
#   (b) Secret NotFound (RC!=0, stderr contains "NotFound" -> install hint)
#   (c) apiserver unreachable (RC!=0, stderr contains "connection refused"/"i/o timeout")
# Note: the obvious printf '%s\0%s' helper trick fails here because bash command
# substitution strips null bytes (warning: "ignored null byte in input"); use a tmpfile.
section "Read proxy CA cert (tls.crt only; Secret has no ca.crt)"
CA_STDERR=$(mktemp -t karyon-ca-stderr-XXXX)
trap 'rm -f "$CA_STDERR"' EXIT
read_capsule_proxy_tls_crt() {
  : > "$CA_STDERR"
  kubectl --context=k3d-spoke-capsule -n capsule-system \
      get secret capsule-proxy -o jsonpath='{.data.tls\.crt}' 2>"$CA_STDERR"
}
CA_RC=0
CA_B64=$(read_capsule_proxy_tls_crt) || CA_RC=$?
if [[ "$CA_RC" -ne 0 ]]; then
  CA_ERR=$(cat "$CA_STDERR" 2>/dev/null || true)
  if echo "$CA_ERR" | grep -qF NotFound; then
    fail "capsule-proxy Secret not found in namespace capsule-system on ${POC_CTX}.
       Inspect: kubectl --context=${POC_CTX} -n capsule-system get secret
       Hint:    capsule-proxy may not yet be installed on spoke-capsule. Reconcile from the hub:
                flux --context=k3d-hub-flux reconcile kustomization poc-capsule --with-source"
    exit 1
  fi
  warn "kubectl call failed (RC=${CA_RC}): ${CA_ERR}. Retrying once after 5s (likely transient apiserver/network)..."
  sleep 5
  CA_RC=0
  CA_B64=$(read_capsule_proxy_tls_crt) || CA_RC=$?
  if [[ "$CA_RC" -ne 0 ]]; then
    CA_ERR=$(cat "$CA_STDERR" 2>/dev/null || true)
    fail "kubectl call failed after retry (RC=${CA_RC}): ${CA_ERR}.
       Hint: apiserver may be unreachable. Inspect: kubectl --context=${POC_CTX} cluster-info"
    exit 1
  fi
fi
if [[ -z "$CA_B64" ]]; then
  warn "capsule-proxy Secret tls.crt key is empty (chart cert rotation in flight?). Retrying once after 5s..."
  sleep 5
  CA_RC=0
  CA_B64=$(read_capsule_proxy_tls_crt) || CA_RC=$?
  [[ "$CA_RC" -eq 0 ]] || CA_B64=""
fi
if [[ -z "$CA_B64" ]]; then
  fail "capsule-proxy Secret tls.crt is empty after retry.
       Inspect: kubectl --context=${POC_CTX} -n capsule-system get secret capsule-proxy -o jsonpath='{.data}' | jq 'keys'
       Hint:    capsule-proxy may not yet be installed on spoke-capsule. Reconcile from the hub:
                flux --context=k3d-hub-flux reconcile kustomization poc-capsule --with-source"
  exit 1
fi
pass "tls.crt read (chart-self-signed CA root)"

# ---------- Section 9: Emit kubeconfig (heredoc with parameterized values) ----------
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
  # Belt-and-braces -- if a future maintainer overrides umask before this
  # block, chmod 0600 here ensures the file mode is owner-private regardless.
  chmod 0600 "$RESOLVED"
  pass "kubeconfig written to ${RESOLVED} (mode 0600)"
else
  emit_kubeconfig
  pass "kubeconfig emitted to stdout (proxy: https://127.0.0.1:30443; default ns: tenant-${TENANT})"
fi
