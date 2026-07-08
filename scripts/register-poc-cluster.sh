#!/usr/bin/env bash
# scripts/register-poc-cluster.sh
#
# Provisions the per-cluster RBAC + token Secret on the POC spoke + applies the
# kubeconfig Secret to hub-flux + patches the FLUX PATCH SURFACE with the
# # KARYON POC MOUNT sentinel + ../pocs resource line + verifies the
# silent-misroute defense (node-name proof against the spoke's apiserver).
#
# Single-cluster mirror of scripts/register-spokes-for-flux.sh — that script's
# per-spoke for-loop body is ported here as the main flow against the single
# positional <cluster-name>. Helper bodies are bug-for-bug compatible.
#
# Usage: bash scripts/register-poc-cluster.sh <cluster-name>
# Effect:
#   1. Provisions flux-reconciler SA + cluster-admin CRB + legacy SA-token
#      Secret on k3d-${name}.
#   2. Builds kubeconfig payload from the SA token + apiserver cert.
#   3. Applies kubeconfig as Secret flux-system/${name}-kubeconfig on
#      k3d-hub-flux (--from-file=value.yaml=/dev/stdin; token-safe — the
#      payload never appears in argv).
#   4. Patches FLUX PATCH SURFACE with # KARYON POC MOUNT sentinel +
#      ../pocs (idempotent via cmp-then-mv; distinct insertion function
#      from ensure_hub_spokes_mount so the two sentinels never collide).
#   5. Verifies the silent-misroute defense (node-name proof: spoke node IS in
#      /api/v1/nodes; hub-flux node is NOT).
#
# Idempotent. NEVER invoked by `task rebuild`. NOT chained from anywhere —
# the core lab scripts have ZERO mentions of this script (isolation contract
# enforced by tests/bats/poc-isolation-01-static.bats).
#
# Token safety: set -euo pipefail INTENTIONALLY omits trace mode. Bearer data
# is never written to logs, helper output, committed files, tee, or
# --from-literal. The hub Secret is applied imperatively from stdin; it is
# not git-tracked.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/preflight-lib.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/preflight-lib.sh"

# ---------- Constants ----------
readonly HUB_CTX="k3d-hub-flux"
readonly FLUX_NS="flux-system"
readonly HUB_KUST_FILE="${REPO_ROOT}/clusters/hub-flux/flux-system/kustomization.yaml"
readonly POCS_DIR="${REPO_ROOT}/clusters/hub-flux/pocs"
readonly POCS_SENTINEL="# KARYON POC MOUNT"
readonly POCS_RESOURCE="../pocs"
readonly RECONCILER_SA="flux-reconciler"
readonly RECONCILER_BINDING="flux-reconciler-cluster-admin"
readonly RECONCILER_SECRET="flux-reconciler-token"
readonly CREDENTIAL_WAIT_SECONDS=10
# Misroute negative-proof literal — verify_credential_layer() asserts
# this node-name does NOT appear in the spoke's /api/v1/nodes response.
readonly EXPECTED_FORBIDDEN_NODE="k3d-hub-flux-server-0"
# The POC runs on a single cluster (spoke-capsule). The host-published
# apiserver port for spoke-capsule is 6446. verify_credential_layer
# uses this port for the openssl s_client TLS probe from the WSL host.
readonly POC_HOST_PORT="6446"

# ---------- Single positional arg validation ----------
if [[ "$#" -ne 1 ]]; then
  fail "usage: bash scripts/register-poc-cluster.sh <cluster-name>"
  exit 1
fi
readonly POC_CLUSTER="$1"
readonly POC_CTX="k3d-${POC_CLUSTER}"

# Validate implicit context exists (fail fast)
if ! kubectl config get-contexts -o name 2>/dev/null | grep -qx "${POC_CTX}"; then
  fail "kubectl context ${POC_CTX} not found.
     Fix: bash scripts/poc/${POC_CLUSTER}/create-cluster.sh"
  exit 1
fi

# ---------- Helper: expected_server (in-cluster URL for the kubeconfig payload) ----------
# Returns https://k3d-${POC_CLUSTER}-server-0:6443 — the in-cluster docker-network
# DNS name + standard k3s container port. NOT the host-published 6446 — that port
# is only reachable from the WSL host, not from kustomize-controller's pod which
# lives on the same k8s-net docker network as the spoke server-0 container.
expected_server() {
  printf 'https://k3d-%s-server-0:6443\n' "${POC_CLUSTER}"
}

# ---------- Helper: decode_b64 ----------
decode_b64() {
  local encoded="$1"
  base64 -d <<< "${encoded}"
}

# ---------- apply_spoke_rbac: SA + cluster-admin CRB + legacy SA-token Secret ----------
# Mirrors register-spokes-for-flux.sh apply_spoke_rbac() verbatim.
apply_spoke_rbac() {
  local spoke="$1"
  kubectl --context "k3d-${spoke}" apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: flux-system
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: flux-reconciler
  namespace: flux-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: flux-reconciler-cluster-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: flux-reconciler
  namespace: flux-system
---
apiVersion: v1
kind: Secret
metadata:
  name: flux-reconciler-token
  namespace: flux-system
  annotations:
    kubernetes.io/service-account.name: flux-reconciler
type: kubernetes.io/service-account-token
EOF
}

# ---------- wait_for_token_secret: bounded retry until SA-token populated ----------
# Sets globals TOKEN_DECODED + CA_B64 on success. Mirrors the
# register-spokes-for-flux.sh analog.
wait_for_token_secret() {
  local spoke="$1"
  local ctx="k3d-${spoke}"
  local secret_part="" cert_part=""

  for _ in $(seq 1 "${CREDENTIAL_WAIT_SECONDS}"); do
    secret_part="$(kubectl --context "${ctx}" -n "${FLUX_NS}" get secret "${RECONCILER_SECRET}" \
      -o jsonpath='{.data.token}' 2>/dev/null || true)"
    cert_part="$(kubectl --context "${ctx}" -n "${FLUX_NS}" get secret "${RECONCILER_SECRET}" \
      -o jsonpath='{.data.ca\.crt}' 2>/dev/null || true)"
    [[ -n "${secret_part}" && -n "${cert_part}" ]] && break
    sleep 1
  done

  if [[ -z "${secret_part}" || -z "${cert_part}" ]]; then
    fail "credential Secret data was not populated on ${spoke} after ${CREDENTIAL_WAIT_SECONDS}s.
       Inspect: kubectl --context k3d-${spoke} -n ${FLUX_NS} describe secret/${RECONCILER_SECRET}
       Fix: rerun: bash scripts/register-poc-cluster.sh ${spoke}"
    exit 1
  fi

  TOKEN_DECODED="$(decode_b64 "${secret_part}")"
  CA_B64="${cert_part}"
}

# ---------- build_kubeconfig: emit kind: Config payload ----------
# Server URL is the in-cluster k3d-${POC_CLUSTER}-server-0:6443 form (NOT the
# host-published :6446). Mirrors the register-spokes-for-flux.sh analog verbatim.
build_kubeconfig() {
  local spoke="$1" bearer="$2" cert_part="$3"
  local server
  server="$(expected_server)"
  cat <<EOF
apiVersion: v1
kind: Config
clusters:
- name: ${spoke}
  cluster:
    server: ${server}
    certificate-authority-data: ${cert_part}
users:
- name: ${RECONCILER_SA}
  user:
    token: ${bearer}
contexts:
- name: ${spoke}
  context:
    cluster: ${spoke}
    user: ${RECONCILER_SA}
current-context: ${spoke}
EOF
}

# ---------- apply_hub_secret: token-safe imperative apply ----------
# --from-file=value.yaml=/dev/stdin only — NEVER --from-literal (would expose
# token in argv / shell history / process listings). NEVER tee. NEVER echo.
apply_hub_secret() {
  local spoke="$1" payload="$2"
  printf '%s\n' "${payload}" |
    kubectl --context "${HUB_CTX}" -n "${FLUX_NS}" create secret generic "${spoke}-kubeconfig" \
      --from-file=value.yaml=/dev/stdin --dry-run=client -o yaml |
    kubectl --context "${HUB_CTX}" -n "${FLUX_NS}" apply -f -
}

# ---------- mirror_kubeconfig_to_tenant_namespaces ----------
# Mirror spoke-capsule-kubeconfig Secret into per-tenant namespaces on hub-flux.
# Required because Flux's kubeConfig.secretRef has an UNCONDITIONAL
# same-namespace constraint (secretRef has no namespace field — Flux v2.8 docs
# + Go API source). The tenant namespaces tenant-alpha + tenant-bravo host the
# per-tenant inner Kustomization CRs (defined in pocs/capsule/tenants/<name>.yaml),
# which reference this Secret. Without the mirror, those CRs reach Ready=False
# with `secret "spoke-capsule-kubeconfig" not found`.
#
# Idempotent: re-run safe (kubectl apply + dry-run client + yq strip metadata).
# yq strip is required: a Secret applied verbatim from another ns rejects with
# "field is immutable" on resourceVersion / uid / creationTimestamp conflict.
#
# Operates only on tenant-{alpha,bravo} on k3d-hub-flux. Does NOT touch spoke
# clusters, and the `task rebuild` time budget is unaffected because this
# function is only called by register-poc-cluster.sh, which task rebuild never
# invokes (verified by tests/bats/poc-isolation-01-static.bats).
mirror_kubeconfig_to_tenant_namespaces() {
  local tenant
  for tenant in alpha bravo; do
    # Ensure the per-tenant namespace exists on hub-flux (the namespace is
    # committed as part of pocs/capsule/tenants/<name>.yaml, but Flux's
    # reconcile of that file may not have happened yet at register-time).
    kubectl --context="${HUB_CTX}" create namespace "tenant-${tenant}" \
      --dry-run=client -o yaml | kubectl --context="${HUB_CTX}" apply -f -
    # Mirror the spoke-capsule-kubeconfig Secret from flux-system into the
    # per-tenant namespace. yq strip metadata fields that cause conflict on apply.
    # shellcheck disable=SC2016 # yq expression intentionally uses single quotes
    kubectl --context="${HUB_CTX}" -n "${FLUX_NS}" get secret spoke-capsule-kubeconfig -o yaml \
      | yq eval '.metadata.namespace = "tenant-'"${tenant}"'"
                 | del(.metadata.resourceVersion, .metadata.uid, .metadata.creationTimestamp)' - \
      | kubectl --context="${HUB_CTX}" apply -f -
  done
}

# ---------- mirror_kubeconfig_to_capsule_system_namespace ----------
# Mirror spoke-capsule-kubeconfig into the capsule-system namespace on hub-flux.
# Required because the split-path layout places the capsule operator HR
# and capsule-proxy HR in capsule-system (NOT flux-system), and Flux's
# kubeConfig.secretRef has an UNCONDITIONAL same-namespace constraint
# (secretRef has no namespace field — Flux v2.8 docs + Go API source).
#
# Without this mirror, both HRs reach Ready=False with
# `could not get KubeConfig secret 'capsule-system/spoke-capsule-kubeconfig': not found`
# once their parent poc-capsule Kustomization is Ready (the committed
# capsule-system Namespace manifest unblocked the CR apply path; this mirror
# unblocks the helm install).
#
# The capsule-system namespace itself is reconciled onto hub by
# pocs/capsule/namespace.yaml, but Flux may not have applied it
# yet at register-time, so create it imperatively first (idempotent).
mirror_kubeconfig_to_capsule_system_namespace() {
  kubectl --context="${HUB_CTX}" create namespace capsule-system \
    --dry-run=client -o yaml | kubectl --context="${HUB_CTX}" apply -f -
  # shellcheck disable=SC2016 # yq expression intentionally uses single quotes
  kubectl --context="${HUB_CTX}" -n "${FLUX_NS}" get secret spoke-capsule-kubeconfig -o yaml \
    | yq eval '.metadata.namespace = "capsule-system"
               | del(.metadata.resourceVersion, .metadata.uid, .metadata.creationTimestamp)' - \
    | kubectl --context="${HUB_CTX}" apply -f -
}

# ---------- mirror_git_auth_to_tenant_namespaces: 2026-07-06 private-repo fix ----------
# Mirror the flux bootstrap git credential (Secret flux-system/flux-system,
# username/password shape from `flux bootstrap github --token-auth`) into
# tenant-alpha + tenant-bravo as `karyon-git-auth`, referenced by the per-tenant
# GitRepository secretRef in pocs/capsule/tenants/{alpha,bravo}.yaml.
#
# WHY: the tenant GitRepositories were designed for anonymous HTTPS clone while
# the repo was public, but the repo later went private —
# tenant-{alpha,bravo}-source sat Ready=False ("authentication required") and
# the tenant GitOps delivery path was dead.
# Same-namespace mirror pattern as mirror_kubeconfig_to_tenant_namespaces above
# (Flux secretRef has no namespace field). The no-committed-secrets rule is a
# git-commit hygiene rule and does not prohibit in-cluster mirroring; the hub
# tenant namespaces are operator-only (tenants only ever reach spoke-capsule
# via capsule-proxy).
#
# LEAST-PRIVILEGE NOTE: this mirrors the repo-write PAT that bootstrap created.
# A read-only fine-grained PAT (or deploy key) in its place is the better
# long-term posture — tracked in docs/backlog.md.
mirror_git_auth_to_tenant_namespaces() {
  local tenant
  for tenant in alpha bravo; do
    kubectl --context="${HUB_CTX}" create namespace "tenant-${tenant}" \
      --dry-run=client -o yaml | kubectl --context="${HUB_CTX}" apply -f -
    # shellcheck disable=SC2016 # yq expression intentionally uses single quotes
    kubectl --context="${HUB_CTX}" -n "${FLUX_NS}" get secret flux-system -o yaml \
      | yq eval '.metadata.name = "karyon-git-auth"
                 | .metadata.namespace = "tenant-'"${tenant}"'"
                 | del(.metadata.resourceVersion, .metadata.uid, .metadata.creationTimestamp)' - \
      | kubectl --context="${HUB_CTX}" apply -f -
  done
}

# ---------- ensure_hub_pocs_mount: INDEPENDENT sentinel insertion ----------
# Distinct function from ensure_hub_spokes_mount() in register-spokes-for-flux.sh
# (sentinel uniqueness requires DEDICATED functions for the SPOKES vs POC
# mounts; preserves the cmp-then-mv idempotency pattern from the analog,
# with sentinel + path swap to # KARYON POC MOUNT + ../pocs).
ensure_hub_pocs_mount() {
  local tmp tmp_with_sentinel

  if [[ ! -f "${HUB_KUST_FILE}" ]]; then
    fail "${HUB_KUST_FILE} missing.
       Fix: bash scripts/bootstrap-flux.sh && bash scripts/register-poc-cluster.sh ${POC_CLUSTER}"
    exit 1
  fi

  tmp="$(mktemp)"
  # shellcheck disable=SC2016 # yq expression intentionally uses single quotes.
  if ! yq eval '(.resources // []) as $r | .resources = ($r + ["../pocs"] | unique)' \
      "${HUB_KUST_FILE}" > "${tmp}"; then
    rm -f "${tmp}"
    fail "${HUB_KUST_FILE} is not valid YAML.
       Fix: repair the Flux patch surface, then rerun bash scripts/register-poc-cluster.sh ${POC_CLUSTER}"
    exit 1
  fi

  if ! yq eval -e '.resources[] == "../pocs"' "${tmp}" >/dev/null; then
    rm -f "${tmp}"
    fail "${HUB_KUST_FILE} could not be repaired with ../pocs.
       Fix: inspect ${HUB_KUST_FILE}, then rerun bash scripts/register-poc-cluster.sh ${POC_CLUSTER}"
    exit 1
  fi

  tmp_with_sentinel="$(mktemp)"
  awk -v sentinel="${POCS_SENTINEL}" '
    $0 ~ /^[[:space:]]*-[[:space:]]+\.\.\/pocs[[:space:]]*$/ && !inserted {
      if (!seen_sentinel) {
        match($0, /^[[:space:]]*/)
        print substr($0, RSTART, RLENGTH) sentinel
      }
      inserted=1
    }
    index($0, sentinel) { seen_sentinel=1 }
    { print }
  ' "${tmp}" > "${tmp_with_sentinel}"
  rm -f "${tmp}"

  if ! yq eval -e '.resources[] == "../pocs"' "${tmp_with_sentinel}" >/dev/null; then
    rm -f "${tmp_with_sentinel}"
    fail "${HUB_KUST_FILE} repair validation failed.
       Fix: inspect ${HUB_KUST_FILE}, then rerun bash scripts/register-poc-cluster.sh ${POC_CLUSTER}"
    exit 1
  fi

  if cmp -s "${tmp_with_sentinel}" "${HUB_KUST_FILE}"; then
    rm -f "${tmp_with_sentinel}"
    info "already done, skipping: pocs mount resource present in ${HUB_KUST_FILE}"
  else
    mv "${tmp_with_sentinel}" "${HUB_KUST_FILE}"
    pass "repaired: ../pocs resource under resources in ${HUB_KUST_FILE}"
  fi
}

# ---------- verify_credential_layer: silent-misroute falsifier ----------
# Live TLS proof + /readyz + /api/v1/nodes node-name proof.
# - openssl s_client to 127.0.0.1:6446 (host-published port) verifies
#   the spoke apiserver is reachable AND its certificate validates the
#   k3d-${spoke}-server-0 SAN.
# - HTTPS GET /readyz with the bearer token confirms the credential layer end-to-end.
# - HTTPS GET /api/v1/nodes asserts the spoke's k3d-${spoke}-server-0 IS present
#   AND k3d-hub-flux-server-0 is NOT (silent-misroute negative proof).
verify_credential_layer() {
  local spoke="$1"
  local value_b64 value_yaml expected actual bearer cert_part cert_tmp ready nodes expected_node http_status
  expected="$(expected_server)"

  # 1. Pull the hub Secret payload (just-applied)
  value_b64="$(kubectl --context "${HUB_CTX}" -n "${FLUX_NS}" \
    get secret "${spoke}-kubeconfig" -o jsonpath='{.data.value\.yaml}' 2>/dev/null || true)"
  if [[ -z "${value_b64}" ]]; then
    fail "${spoke} hub Secret missing data.value.yaml.
       Fix: bash scripts/register-poc-cluster.sh ${spoke}"
    exit 1
  fi
  pass "presence ok: ${spoke} hub Secret data.value.yaml populated"

  # 2. Decode + extract server / bearer / certificate-authority-data
  value_yaml="$(decode_b64 "${value_b64}")"
  actual="$(yq eval '.clusters[0].cluster.server // ""' - <<< "${value_yaml}" 2>/dev/null || true)"
  bearer="$(yq eval '.users[0].user.token // ""' - <<< "${value_yaml}" 2>/dev/null || true)"
  cert_part="$(yq eval '.clusters[0].cluster.certificate-authority-data // ""' - <<< "${value_yaml}" 2>/dev/null || true)"
  if [[ "${actual}" != "${expected}" || -z "${bearer}" || -z "${cert_part}" ]]; then
    fail "${spoke} credential decode failed or server drifted (expected ${expected}, got ${actual:-empty}).
       Fix: bash scripts/register-poc-cluster.sh ${spoke}"
    exit 1
  fi
  if ! decode_b64 "${cert_part}" >/dev/null 2>&1; then
    fail "${spoke} certificate data is not base64-decodable.
       Fix: bash scripts/register-poc-cluster.sh ${spoke}"
    exit 1
  fi
  pass "decode ok: ${spoke} server + bearer + CA equality verified"

  # 3. Write CA bundle to a host-side tmp file (used by openssl + curl)
  cert_tmp="$(mktemp -t "karyon-${spoke}-apiserver-ca.XXXXXX.pem")"
  decode_b64 "${cert_part}" > "${cert_tmp}"

  # 4. TLS probe via openssl s_client against 127.0.0.1:6446 (host-published port).
  # The spoke's cert SAN is k3d-${spoke}-server-0; when the SAN matches the cert
  # presented by 127.0.0.1:6446, that is the ground truth that the host port lands
  # on the correct serverlb container. -verify_hostname forces the cert SAN check.
  local tls_ok=0
  for _ in 1 2 3; do
    if openssl s_client \
        -connect "127.0.0.1:${POC_HOST_PORT}" \
        -servername "k3d-${spoke}-server-0" \
        -verify_hostname "k3d-${spoke}-server-0" \
        -CAfile "${cert_tmp}" \
        -verify_return_error \
        -brief </dev/null >/dev/null 2>&1; then
      tls_ok=1
      break
    fi
    sleep 1
  done
  if [[ "${tls_ok}" -ne 1 ]]; then
    rm -f "${cert_tmp}"
    fail "${spoke} TLS proof failed against 127.0.0.1:${POC_HOST_PORT} (cert SAN k3d-${spoke}-server-0 not validated).
       Inspect: openssl s_client -connect 127.0.0.1:${POC_HOST_PORT} -servername k3d-${spoke}-server-0
       Fix: rerun cluster creation if the spoke apiserver cert SAN is wrong; then rerun this script."
    exit 1
  fi
  pass "tls ok: ${spoke} certificate validates k3d-${spoke}-server-0 at 127.0.0.1:${POC_HOST_PORT}"

  # 5. /readyz auth roundtrip (curl + bearer token; CA-pinned to ${cert_tmp}).
  # Use --resolve to force the SNI/Host header to k3d-${spoke}-server-0 while
  # still hitting 127.0.0.1:6446 (matches the openssl probe and the hub-side
  # in-cluster server: URL).
  ready="$(curl -sS --max-time 10 \
    --cacert "${cert_tmp}" \
    --resolve "k3d-${spoke}-server-0:${POC_HOST_PORT}:127.0.0.1" \
    -H "Authorization: Bearer ${bearer}" \
    "https://k3d-${spoke}-server-0:${POC_HOST_PORT}/readyz" 2>/dev/null || true)"
  if ! printf '%s\n' "${ready}" | tr -d '\r' | grep -qx 'ok'; then
    rm -f "${cert_tmp}"
    fail "${spoke} /readyz auth roundtrip failed (got: ${ready:-empty}).
       Repro: curl --cacert <ca> --resolve k3d-${spoke}-server-0:${POC_HOST_PORT}:127.0.0.1 -H 'Authorization: Bearer <t>' https://k3d-${spoke}-server-0:${POC_HOST_PORT}/readyz
       Fix: bash scripts/register-poc-cluster.sh ${spoke}"
    exit 1
  fi
  pass "auth roundtrip ok: ${spoke} /readyz returned ok"

  # 6. Misroute falsifier — /api/v1/nodes proves we routed to ${spoke}, NOT to hub-flux.
  expected_node="k3d-${spoke}-server-0"
  nodes="$(curl -sS --max-time 10 \
    --cacert "${cert_tmp}" \
    --resolve "k3d-${spoke}-server-0:${POC_HOST_PORT}:127.0.0.1" \
    -H "Authorization: Bearer ${bearer}" \
    "https://k3d-${spoke}-server-0:${POC_HOST_PORT}/api/v1/nodes" 2>/dev/null || true)"
  rm -f "${cert_tmp}"
  if [[ -z "${nodes}" ]]; then
    fail "${spoke} /api/v1/nodes returned empty body — apiserver unreachable or token rejected.
       Fix: bash scripts/register-poc-cluster.sh ${spoke}"
    exit 1
  fi

  # Misroute proof:
  #   POSITIVE proof: spoke-capsule's k3d-spoke-capsule-server-0 IS in /api/v1/nodes
  #   NEGATIVE proof: hub-flux's k3d-hub-flux-server-0 is NOT in /api/v1/nodes
  # If the negative proof fires, the credential is silently misrouted to hub.
  if [[ "${nodes}" != *"${expected_node}"* || "${nodes}" == *"${EXPECTED_FORBIDDEN_NODE}"* ]]; then
    fail "SILENT-MISROUTE warning for ${spoke}: expected ${expected_node} in /api/v1/nodes and not ${EXPECTED_FORBIDDEN_NODE}.
       Inspect: kubectl --context ${HUB_CTX} -n ${FLUX_NS} get secret ${spoke}-kubeconfig -o yaml
       Fix: do NOT push current state; rerun bash scripts/register-poc-cluster.sh ${spoke}"
    exit 1
  fi
  pass "node-name proof ok: ${spoke} routes to ${expected_node} (k3d-hub-flux-server-0 absent)"
}

# ---------- Section 1: POC cluster registration ----------
section "POC cluster registration: ${POC_CLUSTER}"

# Tool gate
for cmd in kubectl yq awk openssl curl jq; do
  if ! have "$cmd"; then
    fail "required command missing: $cmd.
       Fix: install project tools with asdf, then rerun: bash scripts/register-poc-cluster.sh ${POC_CLUSTER}"
    exit 1
  fi
done
pass "required commands present"

# Apply RBAC + token Secret on spoke
apply_spoke_rbac "${POC_CLUSTER}"
pass "applied: ${POC_CLUSTER} RBAC in ${FLUX_NS}"

# Wait for SA-token to populate (sets TOKEN_DECODED + CA_B64)
wait_for_token_secret "${POC_CLUSTER}"
pass "credential data populated for ${POC_CLUSTER}"

# Build kubeconfig payload (server URL: in-cluster k3d-${POC_CLUSTER}-server-0:6443)
kubeconfig_yaml="$(build_kubeconfig "${POC_CLUSTER}" "${TOKEN_DECODED}" "${CA_B64}")"

# Apply hub Secret (token-safe path — never echoed, never tee'd, never argv'd)
apply_hub_secret "${POC_CLUSTER}" "${kubeconfig_yaml}"
pass "applied: ${POC_CLUSTER} hub Secret"

# Mirror spoke-capsule-kubeconfig into per-tenant namespaces on hub-flux
# (Flux's kubeConfig.secretRef has an UNCONDITIONAL same-namespace constraint).
# Without this mirror, the per-tenant inner Kustomizations fail
# with `secret "spoke-capsule-kubeconfig" not found`.
section "Mirror spoke-capsule-kubeconfig to per-tenant namespaces"
mirror_kubeconfig_to_tenant_namespaces
pass "mirrored: spoke-capsule-kubeconfig → tenant-alpha + tenant-bravo on ${HUB_CTX}"

# Mirror spoke-capsule-kubeconfig into capsule-system on hub-flux.
# Capsule operator + capsule-proxy HRs live in capsule-system (split-path layout);
# their helm install on spoke requires the kubeconfig secret in the HR's own namespace
# (Flux secretRef has no namespace field). The committed manifest creates the namespace;
# this mirror creates the secret. Without both, the capsule operator HR fails with
# `secrets "spoke-capsule-kubeconfig" not found` and capsule-proxy is blocked by dependsOn.
section "Mirror spoke-capsule-kubeconfig to capsule-system namespace"
mirror_kubeconfig_to_capsule_system_namespace
pass "mirrored: spoke-capsule-kubeconfig → capsule-system on ${HUB_CTX}"

# Mirror the bootstrap git credential into per-tenant namespaces (2026-07-06
# private-repo fix). The per-tenant GitRepositories reference karyon-git-auth;
# without this mirror they sit Ready=False ("authentication required") against
# the private repo and tenant-{alpha,bravo}-app never receive an artifact.
section "Mirror git credential to per-tenant namespaces (private-repo fix)"
mirror_git_auth_to_tenant_namespaces
pass "mirrored: flux-system git credential → karyon-git-auth in tenant-alpha + tenant-bravo on ${HUB_CTX}"

# Patch FLUX PATCH SURFACE with # KARYON POC MOUNT sentinel + ../pocs (idempotent)
section "Hub-side FLUX PATCH SURFACE patch"
ensure_hub_pocs_mount

# Verify the silent-misroute defense (node-name falsifier)
section "Silent-misroute falsifier"
verify_credential_layer "${POC_CLUSTER}"

# ---------- Section 2: Summary ----------
section "Summary"
printf "  %s%d passed%s, %s%d warnings%s, %s%d failed%s\n" \
  "${C_GREEN}" "${PASS}" "${C_RESET}" "${C_YELLOW}" "${WARN}" "${C_RESET}" "${C_RED}" "${FAIL}" "${C_RESET}"
if (( FAIL > 0 )); then exit 1; fi
printf "\n%sPOC cluster ${POC_CLUSTER} registered with hub-flux.%s\n" "${C_GREEN}" "${C_RESET}"
printf "%sNext step: monitor with 'flux get kustomization poc-capsule -n flux-system'%s\n" "${C_DIM}" "${C_RESET}"
