#!/usr/bin/env bash
# scripts/register-poc-cluster.sh
#
# Provisions the per-cluster RBAC + token Secret on the POC spoke + applies the
# kubeconfig Secret to hub-flux + patches the FLUX PATCH SURFACE with the
# # KARYON POC MOUNT sentinel + ../pocs resource line + verifies the P18
# silent-misroute defense (node-name proof against the spoke's apiserver).
#
# Single-cluster mirror of scripts/register-spokes-for-flux.sh per D-07 — that
# script's per-spoke for-loop body is ported here as the main flow against the
# single positional <cluster-name>. Helper bodies are bug-for-bug compatible.
#
# Usage: bash scripts/register-poc-cluster.sh <cluster-name>
# Effect:
#   1. Provisions flux-reconciler SA + cluster-admin CRB + legacy SA-token
#      Secret on k3d-${name}.
#   2. Builds kubeconfig payload from the SA token + apiserver cert.
#   3. Applies kubeconfig as Secret flux-system/${name}-kubeconfig on
#      k3d-hub-flux (--from-file=value.yaml=/dev/stdin; D-11 token safety).
#   4. Patches FLUX PATCH SURFACE (D-09) with # KARYON POC MOUNT sentinel +
#      ../pocs (idempotent via cmp-then-mv; P30 — distinct insertion function
#      from ensure_hub_spokes_mount).
#   5. Verifies P18 silent-misroute defense (node-name proof: spoke node IS in
#      /api/v1/nodes; hub-flux node is NOT).
#
# Idempotent. NEVER invoked by `task rebuild`. NOT chained from anywhere
# (D-12 / P31 isolation contract; v0.18 scripts have ZERO mentions of this
# script; tests/bats/poc-isolation-01-static.bats enforces).
#
# D-11 safety: set -euo pipefail INTENTIONALLY omits trace mode. Bearer data
# is never written to logs, helper output, committed files, tee, or
# --from-literal. The hub Secret is applied imperatively from stdin; it is
# not git-tracked.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/preflight-lib.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/preflight-lib.sh"

# ---------- Constants (D-07 / D-09 / D-11 invariants) ----------
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
# P18 falsifier negative-proof literal — verify_credential_layer() asserts
# this node-name does NOT appear in the spoke's /api/v1/nodes response.
readonly EXPECTED_FORBIDDEN_NODE="k3d-hub-flux-server-0"
# Phase 7 lives on a single POC cluster (spoke-capsule). The host-published
# apiserver port for spoke-capsule is 6446 (D-10). verify_credential_layer
# uses this port for the openssl s_client TLS probe from the WSL host.
readonly POC_HOST_PORT="6446"

# ---------- Single positional arg validation (D-07) ----------
if [[ "$#" -ne 1 ]]; then
  fail "usage: bash scripts/register-poc-cluster.sh <cluster-name>"
  exit 1
fi
readonly POC_CLUSTER="$1"
readonly POC_CTX="k3d-${POC_CLUSTER}"

# Validate implicit context exists (D-07 fails fast)
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
# Mirrors register-spokes-for-flux.sh apply_spoke_rbac() lines 275-311 verbatim.
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
# Sets globals TOKEN_DECODED + CA_B64 on success. Mirrors analog lines 313-336.
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
# host-published :6446). Mirrors analog lines 338-361 verbatim.
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

# ---------- apply_hub_secret: D-11 token-safe imperative apply ----------
# --from-file=value.yaml=/dev/stdin only — NEVER --from-literal (would expose
# token in argv / shell history / process listings). NEVER tee. NEVER echo.
apply_hub_secret() {
  local spoke="$1" payload="$2"
  printf '%s\n' "${payload}" |
    kubectl --context "${HUB_CTX}" -n "${FLUX_NS}" create secret generic "${spoke}-kubeconfig" \
      --from-file=value.yaml=/dev/stdin --dry-run=client -o yaml |
    kubectl --context "${HUB_CTX}" -n "${FLUX_NS}" apply -f -
}

# ---------- ensure_hub_pocs_mount: P30 INDEPENDENT sentinel insertion ----------
# Distinct function from ensure_hub_spokes_mount() in register-spokes-for-flux.sh
# (P30 sentinel-uniqueness contract requires DEDICATED functions for SPOKES vs
# POC mounts; preserves the cmp-then-mv idempotency pattern from the analog
# lines 525-579, with sentinel + path swap to # KARYON POC MOUNT + ../pocs).
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

# ---------- verify_credential_layer: P18 silent-misroute falsifier ----------
# Live TLS proof + /readyz + /api/v1/nodes node-name P18 falsifier.
# - openssl s_client to 127.0.0.1:6446 (host-published port; D-10) verifies
#   the spoke apiserver is reachable AND its certificate validates the
#   k3d-${spoke}-server-0 SAN.
# - HTTPS GET /readyz with the bearer token confirms the credential layer end-to-end.
# - HTTPS GET /api/v1/nodes asserts the spoke's k3d-${spoke}-server-0 IS present
#   AND k3d-hub-flux-server-0 is NOT (P18 silent-misroute negative proof).
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

  # 6. P18 falsifier — /api/v1/nodes proves we routed to ${spoke}, NOT to hub-flux.
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

  # P18 falsifier:
  #   POSITIVE proof: spoke-capsule's k3d-spoke-capsule-server-0 IS in /api/v1/nodes
  #   NEGATIVE proof: hub-flux's k3d-hub-flux-server-0 is NOT in /api/v1/nodes
  # If the negative proof fires, the credential is silent-misrouted to hub.
  if [[ "${nodes}" != *"${expected_node}"* || "${nodes}" == *"${EXPECTED_FORBIDDEN_NODE}"* ]]; then
    fail "P18 SILENT MISROUTE warning for ${spoke}: expected ${expected_node} and not ${EXPECTED_FORBIDDEN_NODE}.
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

# Apply hub Secret (D-11 token-safe path — never echoed, never tee'd, never argv'd)
apply_hub_secret "${POC_CLUSTER}" "${kubeconfig_yaml}"
pass "applied: ${POC_CLUSTER} hub Secret"

# Patch FLUX PATCH SURFACE with # KARYON POC MOUNT sentinel + ../pocs (idempotent)
section "Hub-side FLUX PATCH SURFACE patch"
ensure_hub_pocs_mount

# Verify P18 silent-misroute defense (node-name falsifier)
section "P18 silent-misroute falsifier"
verify_credential_layer "${POC_CLUSTER}"

# ---------- Section 2: Summary ----------
section "Summary"
printf "  %s%d passed%s, %s%d warnings%s, %s%d failed%s\n" \
  "${C_GREEN}" "${PASS}" "${C_RESET}" "${C_YELLOW}" "${WARN}" "${C_RESET}" "${C_RED}" "${FAIL}" "${C_RESET}"
if (( FAIL > 0 )); then exit 1; fi
printf "\n%sPOC cluster ${POC_CLUSTER} registered with hub-flux.%s\n" "${C_GREEN}" "${C_RESET}"
printf "%sNext step: monitor with 'flux get kustomization poc-capsule -n flux-system'%s\n" "${C_DIM}" "${C_RESET}"
