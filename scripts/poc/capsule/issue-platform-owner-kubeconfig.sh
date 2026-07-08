#!/usr/bin/env bash
# scripts/poc/capsule/issue-platform-owner-kubeconfig.sh
# Mints a TokenRequest-backed kubeconfig for the platform-owner SA (Tier 2 Karyon
# Platform Team identity), routing through capsule-proxy NodePort 30443.
#
# Standalone POC helper for the persistent spoke-capsule cluster; never invoked by task rebuild
# (enforced by tests/bats/poc-isolation-01-static.bats).
# Hub-only Flux control plane: this script reads from spoke-capsule directly -- no Flux runs
# on the spoke (see docs/adr/0004-hub-only-flux-control-plane.md).
#
# Identity: system:serviceaccount:capsule-system:platform-owner
# Binds via the dual-subject capsule-platform-owner ClusterRoleBinding (Tier 2 ceiling:
# no wildcards, no nodes, no csr, no clusterrolebinding writes). Tenant CR co-ownership
# on alpha + bravo (and templates produced by new-tenant.sh) grants per-tenant LIST/EXEC
# scope via Capsule-injected RoleBindings + capsule-proxy owner-set filter.
#
# Idempotency: each invocation produces a fresh TokenRequest token (no state mutation).
#
# Stdout/stderr contract: stdout = pure YAML kubeconfig; stderr =
# preflight-lib log lines. Mechanism: shadow each preflight-lib helper (section/pass/
# info/warn/fail) with a printf-to-stderr equivalent below.
#
# CA gotcha: capsule-proxy Secret has tls.crt + tls.key keys ONLY (no ca.crt). The
# chart's kube-webhook-certgen Job runs with --cert-name=tls.crt --key-name=tls.key
# and self-signs; tls.crt IS the CA root. Script reads tls.crt directly via jsonpath
# '{.data.tls\.crt}'. Kept verbatim with issue-tenant-kubeconfig.sh for
# consistency (a future refactor pass can switch both scripts at once).
#
# Duration gotcha: k3s on this pin does NOT clamp at 24h. --duration is honored exactly
# (verified live for up to 720h). The info-warn at >24h is a portability note for
# distros that DO clamp via --service-account-max-token-expiration.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# shellcheck source=../../lib/preflight-lib.sh
# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/lib/preflight-lib.sh"

# Stderr-redirect: shadow preflight-lib helpers with printf-to-stderr
# equivalents. preflight-lib helpers write to stdout by default; stdout in THIS script
# is the kubeconfig YAML payload, so log lines on stdout would corrupt it. Replace each
# helper with a printf-to-stderr function. Every subsequent call site emits to stderr
# without per-call-site `>&2`. The original ANSI-colored helpers from preflight-lib are
# intentionally NOT called here -- this script does not emit stdout summary lines.
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
readonly SA_NAME="platform-owner"
readonly SA_NAMESPACE="capsule-system"
readonly CRB_NAME="capsule-platform-owner"

# ---------- Usage ----------
usage() {
  cat <<USAGE_EOF >&2
Usage: $(basename "$0") [--duration <d>] [--write-to <path>]

Mints a platform-owner kubeconfig that routes through capsule-proxy NodePort 30443.

Identity (pinned, no positional args):
  Subject: ServiceAccount ${SA_NAME} in namespace ${SA_NAMESPACE}.
  Bound via the dual-subject ClusterRoleBinding ${CRB_NAME} (Tier 2 ceiling).

Flags:
  --duration <d>  TokenRequest duration (default: ${DEFAULT_DURATION}). Valid: golang
                  time.Duration string (e.g., 1h, 24h, 168h). k3s on this pin does NOT
                  clamp; --duration is honored exactly. Info-warn if > 24h.
  --write-to <p>  Write kubeconfig to <p> instead of stdout. <p> MUST resolve under
                  ${TENANT_TMPDIR}/. If <p> is an existing directory, the kubeconfig
                  is written to <p>/platform-owner.kubeconfig. Symlink escape rejected
                  via realpath -m prefix check.
  --help          This help.

Examples:
  bash scripts/poc/capsule/issue-platform-owner-kubeconfig.sh 2>/dev/null > /tmp/po.kc
  bash scripts/poc/capsule/issue-platform-owner-kubeconfig.sh --duration 24h \\
       --write-to ${TENANT_TMPDIR}/platform-owner.kubeconfig

Notes:
  Token is minted via the TokenRequest API for the pinned platform-owner SA.
  Standalone POC helper: never invoked by task rebuild (tests/bats/poc-isolation-01-static.bats).
  Hub-only Flux: NO Flux runs on spoke-capsule (see docs/adr/0004-hub-only-flux-control-plane.md).
USAGE_EOF
  exit "${1:-0}"
}

# ---------- Argument parsing ----------
DURATION="${DEFAULT_DURATION}"
WRITE_TO=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --duration=*) DURATION="${1#--duration=}"; shift ;;
    --duration) DURATION="${2:?--duration requires a value}"; shift 2 ;;
    --write-to=*) WRITE_TO="${1#--write-to=}"; shift ;;
    --write-to) WRITE_TO="${2:?--write-to requires a value}"; shift 2 ;;
    --help|-h)  usage 0 ;;
    --*)        fail "unknown flag: $1"; usage 1 ;;
    *)          fail "unexpected positional arg: $1 (this script has no positional args; SA target is pinned)"; usage 1 ;;
  esac
done

# ---------- Section 1: Tool gate ----------
section "Tool gate"
for cmd in kubectl jq realpath; do
  if ! have "$cmd"; then
    fail "required command missing: $cmd.
       Fix: install project tools with asdf, then rerun: bash scripts/poc/capsule/issue-platform-owner-kubeconfig.sh"
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

# ---------- Section 3: platform-owner SA exists ----------
section "platform-owner SA check"
if ! kubectl --context="${POC_CTX}" -n "${SA_NAMESPACE}" get sa "${SA_NAME}" >/dev/null 2>&1; then
  fail "ServiceAccount '${SA_NAME}' not found in namespace ${SA_NAMESPACE} on ${POC_CTX}.
       Inspect: kubectl --context=${POC_CTX} -n ${SA_NAMESPACE} get sa
       Fix:     platform-owner SA missing. Reconcile the spoke RBAC from the hub:
                flux --context=k3d-hub-flux reconcile kustomization poc-capsule-spoke-rbac --with-source
       Hint:    the SA lands via pocs/capsule/spoke/rbac/platform-owner-sa.yaml."
  exit 1
fi
pass "SA '${SA_NAME}' exists in ${SA_NAMESPACE}"

# ---------- Section 4: ClusterRoleBinding exists ----------
section "ClusterRoleBinding check"
if ! kubectl --context="${POC_CTX}" get clusterrolebinding "${CRB_NAME}" >/dev/null 2>&1; then
  fail "ClusterRoleBinding '${CRB_NAME}' not found.
       Inspect: kubectl --context=${POC_CTX} get clusterrolebinding ${CRB_NAME}
       Fix:     reconcile the spoke RBAC from the hub:
                flux --context=k3d-hub-flux reconcile kustomization poc-capsule-spoke-rbac --with-source"
  exit 1
fi
pass "ClusterRoleBinding '${CRB_NAME}' exists"

# ---------- Section 5: CRB subjects[] include the SA ----------
section "CRB subjects[] dual-subject check"
CRB_SA_NAME=$(kubectl --context="${POC_CTX}" get clusterrolebinding "${CRB_NAME}" \
  -o jsonpath='{.subjects[?(@.kind=="ServiceAccount")].name}' 2>/dev/null || true)
if [[ "${CRB_SA_NAME}" != *"${SA_NAME}"* ]]; then
  fail "ClusterRoleBinding '${CRB_NAME}' subjects[] does NOT include SA '${SA_NAME}@${SA_NAMESPACE}'.
       Got SA subjects: '${CRB_SA_NAME}'.
       Hint: verify pocs/capsule/spoke/rbac/platform-owner.yaml subjects[] block has 2 entries
             (Group capsule-platform-owners + ServiceAccount ${SA_NAME}@${SA_NAMESPACE})."
  exit 1
fi
pass "CRB subjects[] includes SA '${SA_NAME}@${SA_NAMESPACE}'"

# ---------- Section 6: --write-to validation ----------
if [[ -n "$WRITE_TO" ]]; then
  section "--write-to validation"
  # Tighten umask so the kubeconfig (containing a live bearer token) is
  # owner-private on creation.
  umask 0077
  # Defeat symlink pre-placement attack on ${TENANT_TMPDIR}.
  if [[ -L "${TENANT_TMPDIR}" ]]; then
    fail "${TENANT_TMPDIR} is a symlink -- refusing to write platform-owner kubeconfig.
       Hint: an attacker may have pre-placed this symlink to redirect the bearer-token
             kubeconfig to a chosen path. Inspect: ls -ld ${TENANT_TMPDIR}
             Fix:     rm -f ${TENANT_TMPDIR} && bash $(basename "$0")"
    exit 1
  fi
  install -d -m 0700 "${TENANT_TMPDIR}"
  # If --write-to is an existing directory, default filename to platform-owner.kubeconfig.
  if [[ -d "$WRITE_TO" ]]; then
    WRITE_TO="${WRITE_TO%/}/platform-owner.kubeconfig"
    info "directory target detected; defaulting filename to platform-owner.kubeconfig (${WRITE_TO})"
  fi
  RESOLVED=$(realpath -m "$WRITE_TO")
  TMPDIR_RESOLVED=$(realpath -m "${TENANT_TMPDIR}")
  if [[ "$RESOLVED" != "${TMPDIR_RESOLVED}/"* ]]; then
    fail "--write-to '${WRITE_TO}' is outside ${TENANT_TMPDIR}/.
       Hint: platform-owner kubeconfigs MUST live under the tmpdir so live bearer tokens
             never land in the repo or a home directory.
       Try: --write-to ${TENANT_TMPDIR}/platform-owner.kubeconfig"
    exit 1
  fi
  mkdir -p "$(dirname "$RESOLVED")"
  # Defense in depth: after mkdir, verify the resolved parent dir is NOT a symlink.
  PARENT_REAL=$(realpath -e "$(dirname "$RESOLVED")")
  if [[ "$PARENT_REAL" != "${TMPDIR_RESOLVED}"* ]]; then
    fail "parent dir of '${RESOLVED}' resolves outside ${TENANT_TMPDIR}/ after canonicalization.
       Hint: TOCTOU symlink swap detected. Inspect: ls -ld $(dirname "$RESOLVED")"
    exit 1
  fi
  pass "write target '${RESOLVED}' inside ${TENANT_TMPDIR}/"
fi

# ---------- Section 7: Duration portability info-warn ----------
# Convert <int><unit> duration to hours. Supports kubectl's accepted units (s/m/h/d).
duration_to_hours() {
  local d="$1"
  if [[ "$d" =~ ^([0-9]+)([smhd]) ]]; then
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

# ---------- Section 8: Mint TokenRequest token ----------
section "Mint TokenRequest token"
TOKEN=$(kubectl --context="${POC_CTX}" create token "${SA_NAME}" -n "${SA_NAMESPACE}" --duration="${DURATION}")
pass "token issued for ${SA_NAME}@${SA_NAMESPACE} (duration ${DURATION})"

# ---------- Section 9: Read CA cert (tls.crt only, no ca.crt) ----------
# Capture stderr to a tmpfile + exit code via direct subshell return so we can
# distinguish three failure modes (Secret-NotFound vs apiserver-unreachable vs empty key).
section "Read proxy CA cert (tls.crt only; Secret has no ca.crt)"
CA_STDERR=$(mktemp -t karyon-ca-stderr-XXXX)
trap 'rm -f "$CA_STDERR"' EXIT
read_capsule_proxy_tls_crt() {
  : > "$CA_STDERR"
  kubectl --context="${POC_CTX}" -n capsule-system \
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

# ---------- Section 10: Emit kubeconfig (heredoc with parameterized values) ----------
# Context name pinned to platform-owner-via-proxy. User name = platform-owner.
# Context.namespace UNSET (platform-owner ops are cluster-scoped — do not pin to one ns).
section "Emit kubeconfig"

emit_kubeconfig() {
  cat <<KUBECONFIG_EOF
apiVersion: v1
kind: Config
clusters:
  - name: capsule-proxy-127.0.0.1
    cluster:
      server: https://127.0.0.1:${POC_NODEPORT}
      certificate-authority-data: ${CA_B64}
users:
  - name: ${SA_NAME}
    user:
      token: ${TOKEN}
contexts:
  - name: platform-owner-via-proxy
    context:
      cluster: capsule-proxy-127.0.0.1
      user: ${SA_NAME}
      # NO namespace pin (platform-owner ops are cluster-scoped)
current-context: platform-owner-via-proxy
KUBECONFIG_EOF
}

if [[ -n "$WRITE_TO" ]]; then
  emit_kubeconfig > "$RESOLVED"
  # Belt-and-braces -- chmod 0600 ensures owner-private mode regardless of umask.
  chmod 0600 "$RESOLVED"
  pass "kubeconfig written to ${RESOLVED} (mode 0600)"
else
  emit_kubeconfig
  pass "kubeconfig emitted to stdout (proxy: https://127.0.0.1:${POC_NODEPORT}; SA: ${SA_NAME}@${SA_NAMESPACE}; no ns pin)"
fi
