#!/usr/bin/env bash
# scripts/poc/capsule/new-tenant.sh
# Provisions a new Capsule Tenant via the platform-owner kubeconfig (Phase 13).
#
# REQ: RBAC-05 (platform-owner Tenant CR lifecycle).
# Decision: D-13-08 (inline-heredoc template + --kubeconfig flag + name regex
#           ^[a-z][a-z0-9-]{1,30}$).
# Isolation: P31 (POC isolation — under scripts/poc/capsule/, never invoked by
#            task rebuild).
# ADR-004: hub-only Flux — this script applies directly via kubectl, not via Flux reconcile.
#
# Stdout/stderr contract: stdout = informational summary; NO YAML on stdout in
# non-dry-run mode (apply consumes the YAML via stdin). In --dry-run mode the
# rendered YAML IS emitted on stdout (so operators can pipe / capture).
# Uses STANDARD preflight-lib helpers (NOT shadowed — stdout is informational).
#
# Usage:
#   bash scripts/poc/capsule/new-tenant.sh <name> [--kubeconfig <path>] [--dry-run]
#
# Examples:
#   bash scripts/poc/capsule/new-tenant.sh phase13-fresh   # uses platform-owner kc
#   bash scripts/poc/capsule/new-tenant.sh charlie --kubeconfig /tmp/po.kc
#   bash scripts/poc/capsule/new-tenant.sh demo --dry-run > /tmp/demo-tenant.yaml

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# shellcheck source=../../lib/preflight-lib.sh
# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/lib/preflight-lib.sh"

# D-13 pins (LOCKED -- bats grep-asserts these literals):
readonly POC_CTX="k3d-spoke-capsule"
readonly TMPDIR_DEFAULT="${TMPDIR:-/tmp}"
readonly DEFAULT_PO_KC="${TMPDIR_DEFAULT}/karyon-tenants/platform-owner.kubeconfig"
readonly NAME_RE='^[a-z][a-z0-9-]{1,30}$'

# ---------- Usage ----------
usage() {
  cat <<USAGE_EOF >&2
Usage: $(basename "$0") <name> [--kubeconfig <path>] [--dry-run]

Provisions a new Capsule Tenant + home namespace + human-tenant-owner SA.

Arguments:
  <name>       Tenant name. Must match ${NAME_RE}.
               (Examples: phase13-fresh, charlie, demo, team-foo.)

Flags:
  --kubeconfig <path>   Override platform-owner kubeconfig path.
                        Default: ${DEFAULT_PO_KC}
                        (falls back to \$HOME/.kube/config if not found — Pitfall 13-P5).
  --dry-run             Print rendered YAML to stdout WITHOUT applying.
  --help                Show this help.

Behavior:
  Renders Tenant CR + Namespace + ServiceAccount with default co-ownership:
    - Group capsule-platform-owners
    - SA platform-owner@capsule-system
    - SA flux-reconciler@flux-system (belt-and-suspenders for future Flux reconcile)
    - SA human-tenant-owner@tenant-<name> with clusterRoles: [tenant-workload-editor]
  Applies via 'kubectl --kubeconfig=\$KC apply -f -'.

Threat-model: T-13-03 mitigation — Tenant CR CRUD via platform-owner identity
(NOT cluster-admin), so RBAC-05 is exercised, not bypassed.
USAGE_EOF
  exit "${1:-0}"
}

# ---------- Arg parse ----------
NAME=""
KC=""
DRY_RUN="false"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --kubeconfig)   KC="${2:?--kubeconfig requires a value}"; shift 2 ;;
    --kubeconfig=*) KC="${1#--kubeconfig=}"; shift ;;
    --dry-run)      DRY_RUN="true"; shift ;;
    --help|-h)      usage 0 ;;
    --*)            fail "unknown flag: $1"; usage 1 ;;
    *)
      if [[ -z "$NAME" ]]; then
        NAME="$1"; shift
      else
        fail "unexpected positional arg: $1"; usage 1
      fi
      ;;
  esac
done

if [[ -z "$NAME" ]]; then
  fail "<name> is required"
  usage 1
fi

# ---------- Validate name ----------
section "Validate tenant name"
if [[ ! "$NAME" =~ $NAME_RE ]]; then
  fail "Tenant name '${NAME}' is invalid (must match ${NAME_RE}).
       Lowercase letters/digits/hyphens, start with a letter, max 31 chars.
       Hint: try 'phase13-fresh' for the RBAC-05 test or 'charlie' for the demo."
  exit 1
fi
pass "name '${NAME}' matches ${NAME_RE}"

# ---------- Tool gate ----------
section "Tool gate"
if ! have kubectl; then
  fail "kubectl not on PATH.
       Fix: install project tools with asdf, then rerun."
  exit 1
fi
pass "kubectl present"

# ---------- Resolve kubeconfig ----------
section "Resolve --kubeconfig"
if [[ -z "$KC" ]]; then
  if [[ -f "$DEFAULT_PO_KC" ]]; then
    KC="$DEFAULT_PO_KC"
    pass "using default platform-owner kubeconfig: ${KC}"
  else
    warn "platform-owner kubeconfig not found at ${DEFAULT_PO_KC}; falling back to \$HOME/.kube/config (cluster-admin)"
    warn "  Pitfall 13-P5: cluster-admin works but RBAC-05 demo intent is to exercise platform-owner identity. Hint: mint via"
    warn "    bash scripts/poc/capsule/issue-platform-owner-kubeconfig.sh --write-to ${DEFAULT_PO_KC}"
    KC="${HOME}/.kube/config"
  fi
elif [[ ! -f "$KC" ]]; then
  fail "--kubeconfig path '${KC}' does not exist"
  exit 1
fi
if [[ ! -s "$KC" ]]; then
  fail "kubeconfig '${KC}' is empty or unreadable"
  exit 1
fi

# ---------- Cluster reachable ----------
section "Cluster reachable"
# Use `kubectl version` rather than `cluster-info`: cluster-info requires
# `list services -n kube-system` which the platform-owner SA does NOT have
# (T-13-03 ceiling: no kube-system reads). `version` calls the discovery
# endpoint which is granted to system:authenticated by default.
if ! kubectl --kubeconfig="$KC" version --request-timeout=5s >/dev/null 2>&1; then
  if ! kubectl --kubeconfig="$KC" --context="$POC_CTX" version --request-timeout=5s >/dev/null 2>&1; then
    fail "Cannot reach cluster via kubeconfig '${KC}'.
       Inspect: kubectl --kubeconfig=${KC} version
       Hint:    if using ${DEFAULT_PO_KC}, ensure capsule-proxy NodePort 30443 is reachable."
    exit 1
  fi
fi
pass "cluster reachable via ${KC}"

# ---------- Pre-check: tenant does NOT already exist ----------
section "Tenant existence check"
if kubectl --kubeconfig="$KC" get tenant "$NAME" >/dev/null 2>&1; then
  fail "Tenant '${NAME}' already exists.
       Hint: kubectl --kubeconfig=${KC} delete tenant ${NAME}"
  exit 1
fi
pass "tenant '${NAME}' does not exist"

# ---------- Render YAML ----------
# Three stages: Tenant CR, Namespace, ServiceAccount.
# Capsule's controller reconciles spec.owners[] after the Tenant CR lands and
# injects per-namespace RoleBindings. We MUST apply the Tenant first and wait
# for the namespace to be Active before applying the human-tenant-owner SA —
# otherwise the platform-owner SA's apply request for the SA hits Forbidden
# (no RoleBinding yet in the brand-new tenant ns).
render_tenant_cr() {
  cat <<TENANT_EOF
# NEW Tenant ${NAME} — D-13-08 template (Phase 13)
# Provisioned by scripts/poc/capsule/new-tenant.sh via platform-owner kubeconfig.
# spec.owners[] carries default co-ownership shape:
#   - SA flux-reconciler@flux-system           (Tier 1 future-Flux reconcile belt-and-suspenders)
#   - Group capsule-platform-owners            (Tier 2 impersonation path)
#   - SA platform-owner@capsule-system         (Tier 2 TokenRequest path)
#   - SA human-tenant-owner@tenant-${NAME}     (Tier 3 human workload editor)
#   - Group tenant-${NAME}-devs                 (Tier 3 OIDC dev group — inert until
#     the Keycloak group exists AND is appended to CapsuleConfiguration userGroups;
#     see docs/tenant-access.md §New tenant identity contract)
# forceTenantPrefix: false matches Phase 11 D-11-07 — home ns is tenant-<NAME>,
# NOT <NAME>-tenant-<NAME>.
apiVersion: capsule.clastix.io/v1beta2
kind: Tenant
metadata:
  name: ${NAME}
  labels:
    karyon.io/poc: capsule
    karyon.io/provisioned-by: new-tenant.sh
spec:
  forceTenantPrefix: false
  owners:
    - kind: ServiceAccount
      name: system:serviceaccount:flux-system:flux-reconciler
    - kind: Group
      name: capsule-platform-owners
    - kind: ServiceAccount
      name: system:serviceaccount:capsule-system:platform-owner
    - kind: ServiceAccount
      name: system:serviceaccount:tenant-${NAME}:human-tenant-owner
      clusterRoles:
        - tenant-workload-editor
    - kind: Group
      name: tenant-${NAME}-devs
      clusterRoles:
        - tenant-workload-editor
  containerRegistries:
    allowed:
      - docker.io
TENANT_EOF
}

render_namespace() {
  cat <<NS_EOF
apiVersion: v1
kind: Namespace
metadata:
  name: tenant-${NAME}
  labels:
    capsule.clastix.io/tenant: ${NAME}
    karyon.io/poc: capsule
    karyon.io/provisioned-by: new-tenant.sh
NS_EOF
}

render_sa() {
  cat <<SA_EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: human-tenant-owner
  namespace: tenant-${NAME}
  labels:
    karyon.io/poc: capsule
    karyon.io/role: capsule-tenant-workload-editor
    karyon.io/provisioned-by: new-tenant.sh
SA_EOF
}

render_yaml() {
  render_tenant_cr
  echo "---"
  render_namespace
  echo "---"
  render_sa
}

if [[ "$DRY_RUN" == "true" ]]; then
  info "DRY RUN — printing rendered YAML to stdout"
  render_yaml
  exit 0
fi

# ---------- Stage 1: Apply Tenant CR ----------
section "Stage 1: apply Tenant ${NAME} CR"
if ! render_tenant_cr | kubectl --kubeconfig="$KC" apply -f - >/dev/null; then
  fail "kubectl apply Tenant CR failed. Inspect output above.
       Hint: re-run with --dry-run and inspect rendered YAML; check Capsule webhook
             admission (e.g. forbidden owner, registry policy)."
  exit 1
fi
pass "Tenant CR ${NAME} applied"

# ---------- Stage 2: Apply Namespace ----------
section "Stage 2: apply Namespace tenant-${NAME}"
if ! render_namespace | kubectl --kubeconfig="$KC" apply -f - >/dev/null; then
  fail "kubectl apply Namespace failed. Inspect output above."
  exit 1
fi
pass "Namespace tenant-${NAME} applied"

# Wait for namespace to be Active + Capsule to inject platform-owner RoleBinding.
# Without this wait, the next stage (SA apply) hits Forbidden because no
# RoleBinding grants platform-owner SA `create serviceaccounts` in this ns yet.
section "Stage 2b: wait for Capsule per-namespace RoleBinding injection"
WAIT_DEADLINE=$(( $(date +%s) + 30 ))
while [[ $(date +%s) -lt $WAIT_DEADLINE ]]; do
  # Capsule injects RoleBindings whose subjects include
  #   { kind: ServiceAccount, name: platform-owner, namespace: capsule-system }
  # (the canonical Kubernetes RoleBinding subject shape — namespace as a
  # separate field, NOT a "system:serviceaccount:" prefix in name). Match
  # on the kind+name+namespace tuple via jsonpath.
  PO_BINDING_FOUND=$(kubectl --kubeconfig="$KC" -n "tenant-${NAME}" get rolebindings \
    -o jsonpath='{range .items[*]}{range .subjects[?(@.kind=="ServiceAccount")]}{.name}@{.namespace}{"\n"}{end}{end}' \
    2>/dev/null | grep -c '^platform-owner@capsule-system$' || true)
  if [[ "$PO_BINDING_FOUND" -gt 0 ]]; then
    pass "platform-owner RoleBinding injected in tenant-${NAME} (${PO_BINDING_FOUND} bindings)"
    break
  fi
  sleep 1
done
if [[ $(date +%s) -ge $WAIT_DEADLINE ]]; then
  warn "30s timeout waiting for Capsule RoleBinding injection in tenant-${NAME}; proceeding anyway (SA apply may fail with Forbidden)"
fi

# ---------- Stage 3: Apply ServiceAccount ----------
section "Stage 3: apply ServiceAccount human-tenant-owner in tenant-${NAME}"
if ! render_sa | kubectl --kubeconfig="$KC" apply -f - >/dev/null; then
  fail "kubectl apply ServiceAccount failed. Inspect output above.
       Hint: Capsule RoleBinding injection may have lagged; retry in a few seconds."
  exit 1
fi
pass "ServiceAccount human-tenant-owner applied in tenant-${NAME}"

info "Next: provision tenant-owner kubeconfig with:"
info "  bash scripts/poc/capsule/issue-tenant-kubeconfig.sh ${NAME} human-tenant-owner"
