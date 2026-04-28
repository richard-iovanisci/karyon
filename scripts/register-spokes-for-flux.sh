#!/usr/bin/env bash
# scripts/register-spokes-for-flux.sh
#
# Creates per-spoke RBAC (SA + cluster-admin CRB + legacy SA-token Secret),
# builds a credential from each spoke's Secret, and lands it on k3d-hub-flux
# as flux-system/<spoke>-kubeconfig (key: value.yaml).
#
# Wires the hub-side Flux Kustomizations under clusters/hub-flux/spokes/ and
# patches the FLUX PATCH SURFACE to add `- ../spokes`.
#
# Requirements satisfied: SPOKE-01..06
# Decisions honored:      D-01..D-16
#
# D-11 safety: set -euo pipefail INTENTIONALLY omits trace mode. Bearer data is
# never written to logs, helper output, committed files, tee, or --from-literal.
# The hub Secret is applied imperatively from stdin; it is not git-tracked.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/preflight-lib.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/preflight-lib.sh"

readonly HUB_CTX="k3d-hub-flux"
readonly FLUX_NS="flux-system"
readonly HUB_KUST_FILE="${REPO_ROOT}/clusters/hub-flux/flux-system/kustomization.yaml"
readonly SPOKES_DIR="${REPO_ROOT}/clusters/hub-flux/spokes"
readonly SPOKES_SENTINEL="# KARYON SPOKES MOUNT"
readonly CREDENTIAL_WAIT_SECONDS=10
readonly EXPECTED_FORBIDDEN_NODE="k3d-hub-flux-server-0"
readonly RECONCILER_SA="flux-reconciler"
readonly RECONCILER_BINDING="flux-reconciler-cluster-admin"
readonly RECONCILER_SECRET="flux-reconciler-token"
readonly OPENSSL_PROBE_IMAGE="karyon/k3s-cuda:v1.34.6-k3s1-cuda12.8.1"

expected_server() {
  local spoke="$1"
  printf 'https://k3d-%s-server-0:6443\n' "${spoke}"
}

decode_b64() {
  local encoded="$1"
  base64 -d <<< "${encoded}"
}

hub_secret_value() {
  local spoke="$1"
  kubectl --context "${HUB_CTX}" -n "${FLUX_NS}" \
    get secret "${spoke}-kubeconfig" -o jsonpath='{.data.value\.yaml}' 2>/dev/null || true
}

spoke_rbac_healthy() {
  local spoke="$1"
  local ctx="k3d-${spoke}"
  local role_ref="" secret_kind="" secret_anno="" secret_part="" cert_part=""

  kubectl --context "${ctx}" -n "${FLUX_NS}" get serviceaccount "${RECONCILER_SA}" >/dev/null 2>&1 || return 1
  role_ref="$(kubectl --context "${ctx}" get clusterrolebinding "${RECONCILER_BINDING}" \
    -o jsonpath='{.roleRef.kind}:{.roleRef.name}' 2>/dev/null || true)"
  [[ "${role_ref}" == "ClusterRole:cluster-admin" ]] || return 1
  secret_kind="$(kubectl --context "${ctx}" -n "${FLUX_NS}" get secret "${RECONCILER_SECRET}" \
    -o jsonpath='{.type}' 2>/dev/null || true)"
  secret_anno="$(kubectl --context "${ctx}" -n "${FLUX_NS}" get secret "${RECONCILER_SECRET}" \
    -o jsonpath='{.metadata.annotations.kubernetes\.io/service-account\.name}' 2>/dev/null || true)"
  secret_part="$(kubectl --context "${ctx}" -n "${FLUX_NS}" get secret "${RECONCILER_SECRET}" \
    -o jsonpath='{.data.token}' 2>/dev/null || true)"
  cert_part="$(kubectl --context "${ctx}" -n "${FLUX_NS}" get secret "${RECONCILER_SECRET}" \
    -o jsonpath='{.data.ca\.crt}' 2>/dev/null || true)"

  [[ "${secret_kind}" == "kubernetes.io/service-account-token" ]] || return 1
  [[ "${secret_anno}" == "${RECONCILER_SA}" ]] || return 1
  [[ -n "${secret_part}" && -n "${cert_part}" ]]
}

decoded_hub_credential() {
  local spoke="$1"
  local value_b64
  value_b64="$(hub_secret_value "${spoke}")"
  [[ -n "${value_b64}" ]] || return 1
  decode_b64 "${value_b64}"
}

hub_secret_healthy() {
  local spoke="$1"
  local expected actual bearer cert_part value_yaml
  expected="$(expected_server "${spoke}")"
  value_yaml="$(decoded_hub_credential "${spoke}")" || return 1
  actual="$(yq eval '.clusters[0].cluster.server // ""' - <<< "${value_yaml}" 2>/dev/null || true)"
  bearer="$(yq eval '.users[0].user.token // ""' - <<< "${value_yaml}" 2>/dev/null || true)"
  cert_part="$(yq eval '.clusters[0].cluster.certificate-authority-data // ""' - <<< "${value_yaml}" 2>/dev/null || true)"
  [[ "${actual}" == "${expected}" ]] || return 1
  [[ -n "${bearer}" && -n "${cert_part}" ]] || return 1
  decode_b64 "${cert_part}" >/dev/null 2>&1
}

credential_bearer_from_hub() {
  local spoke="$1"
  local value_yaml
  value_yaml="$(decoded_hub_credential "${spoke}")" || return 1
  yq eval '.users[0].user.token // ""' - <<< "${value_yaml}"
}

kustomize_controller_has_openssl() {
  kubectl --context "${HUB_CTX}" -n "${FLUX_NS}" exec deploy/kustomize-controller -- \
    /bin/sh -c 'command -v openssl >/dev/null 2>&1' >/dev/null 2>&1
}

cleanup_openssl_probe_pod() {
  local pod="$1"
  kubectl --context "${HUB_CTX}" -n "${FLUX_NS}" delete pod "${pod}" \
    --ignore-not-found --grace-period=0 --force --wait=true >/dev/null 2>&1 || true
}

ensure_openssl_probe_pod() {
  local pod="$1"

  cleanup_openssl_probe_pod "${pod}"
  kubectl --context "${HUB_CTX}" -n "${FLUX_NS}" run "${pod}" \
    --image="${OPENSSL_PROBE_IMAGE}" \
    --image-pull-policy=Never \
    --restart=Never \
    --command -- sleep 3600 >/dev/null

  if kubectl --context "${HUB_CTX}" -n "${FLUX_NS}" wait \
      --for=condition=Ready "pod/${pod}" --timeout=20s >/dev/null 2>&1; then
    return 0
  fi

  kubectl --context "${HUB_CTX}" -n "${FLUX_NS}" delete pod "${pod}" \
    --ignore-not-found --grace-period=0 --force --wait=true >/dev/null 2>&1 || true
  if ! docker image inspect "${OPENSSL_PROBE_IMAGE}" >/dev/null 2>&1; then
    fail "OpenSSL probe image ${OPENSSL_PROBE_IMAGE} is not present locally.
       Fix: task build-image && bash scripts/register-spokes-for-flux.sh"
    return 1
  fi
  k3d image import -c hub-flux "${OPENSSL_PROBE_IMAGE}" >/dev/null
  kubectl --context "${HUB_CTX}" -n "${FLUX_NS}" run "${pod}" \
    --image="${OPENSSL_PROBE_IMAGE}" \
    --image-pull-policy=Never \
    --restart=Never \
    --command -- sleep 3600 >/dev/null
  if ! kubectl --context "${HUB_CTX}" -n "${FLUX_NS}" wait \
      --for=condition=Ready "pod/${pod}" --timeout=60s >/dev/null; then
    cleanup_openssl_probe_pod "${pod}"
    fail "OpenSSL probe pod ${pod} did not become Ready.
       Fix: task build-image && bash scripts/register-spokes-for-flux.sh"
    return 1
  fi
}

openssl_https_request() {
  local spoke="$1" bearer="$2" path="$3" cert_part="$4"
  local cert_tmp="/tmp/karyon-${spoke}-apiserver-ca.pem"
  local host="k3d-${spoke}-server-0"
  local target="deploy/kustomize-controller"
  local pod="" output rc

  if [[ "${path}" != /* ]]; then
    return 1
  fi

  if ! kustomize_controller_has_openssl; then
    pod="karyon-openssl-probe-${spoke}-$$"
    info "kustomize-controller lacks openssl; using temporary ${OPENSSL_PROBE_IMAGE} verifier pod"
    ensure_openssl_probe_pod "${pod}" || return 1
    target="${pod}"
  fi

  if ! decode_b64 "${cert_part}" |
      kubectl --context "${HUB_CTX}" -n "${FLUX_NS}" exec -i "${target}" -- \
        /bin/sh -c "cat > '${cert_tmp}'"; then
    [[ -n "${pod}" ]] && cleanup_openssl_probe_pod "${pod}"
    return 1
  fi

  if output="$(
    printf 'GET %s HTTP/1.1\r\nHost: %s\r\nAuthorization: Bearer %s\r\nConnection: close\r\n\r\n' \
      "${path}" "${host}" "${bearer}" |
      kubectl --context "${HUB_CTX}" -n "${FLUX_NS}" exec -i "${target}" -- \
        /bin/sh -c "openssl s_client -quiet -verify_return_error -verify_hostname '${host}' -CAfile '${cert_tmp}' -connect '${host}:6443' 2>/dev/null"
  )"; then
    rc=0
  else
    rc=$?
  fi

  kubectl --context "${HUB_CTX}" -n "${FLUX_NS}" exec "${target}" -- \
    /bin/sh -c "rm -f '${cert_tmp}'" >/dev/null 2>&1 || true
  [[ -n "${pod}" ]] && cleanup_openssl_probe_pod "${pod}"

  printf '%s\n' "${output}"
  return "${rc}"
}

verify_tls_with_openssl() {
  local spoke="$1" cert_part="$2"
  local cert_tmp="/tmp/karyon-${spoke}-apiserver-ca.pem"
  local pod="karyon-openssl-probe-${spoke}-$$"
  local tls_ok=0

  if kustomize_controller_has_openssl; then
    decode_b64 "${cert_part}" |
      kubectl --context "${HUB_CTX}" -n "${FLUX_NS}" exec -i deploy/kustomize-controller -- \
        /bin/sh -c "cat > '${cert_tmp}'"
    for _ in 1 2; do
      if kubectl --context "${HUB_CTX}" -n "${FLUX_NS}" exec deploy/kustomize-controller -- \
          /bin/sh -c "openssl s_client -brief -verify_return_error -verify_hostname k3d-${spoke}-server-0 -CAfile '${cert_tmp}' -connect k3d-${spoke}-server-0:6443 </dev/null >/tmp/karyon-${spoke}-tls.out 2>&1"; then
        kubectl --context "${HUB_CTX}" -n "${FLUX_NS}" exec deploy/kustomize-controller -- \
          /bin/sh -c "rm -f '${cert_tmp}' /tmp/karyon-${spoke}-tls.out" >/dev/null 2>&1 || true
        return 0
      fi
      sleep 1
    done
    kubectl --context "${HUB_CTX}" -n "${FLUX_NS}" exec deploy/kustomize-controller -- \
      /bin/sh -c "rm -f '${cert_tmp}' /tmp/karyon-${spoke}-tls.out" >/dev/null 2>&1 || true
    return 1
  fi

  info "kustomize-controller lacks openssl; using temporary ${OPENSSL_PROBE_IMAGE} verifier pod"
  ensure_openssl_probe_pod "${pod}" || return 1
  if ! decode_b64 "${cert_part}" |
      kubectl --context "${HUB_CTX}" -n "${FLUX_NS}" exec -i "${pod}" -- \
        /bin/sh -c "cat > '${cert_tmp}'"; then
    cleanup_openssl_probe_pod "${pod}"
    return 1
  fi
  for _ in 1 2; do
    if kubectl --context "${HUB_CTX}" -n "${FLUX_NS}" exec "${pod}" -- \
        /bin/sh -c "openssl s_client -brief -verify_return_error -verify_hostname k3d-${spoke}-server-0 -CAfile '${cert_tmp}' -connect k3d-${spoke}-server-0:6443 </dev/null >/tmp/karyon-${spoke}-tls.out 2>&1"; then
      tls_ok=1
      break
    fi
    sleep 1
  done
  if [[ "${tls_ok}" -ne 1 ]]; then
    cleanup_openssl_probe_pod "${pod}"
    return 1
  fi
  kubectl --context "${HUB_CTX}" -n "${FLUX_NS}" exec "${pod}" -- \
    /bin/sh -c "rm -f '${cert_tmp}' /tmp/karyon-${spoke}-tls.out" >/dev/null 2>&1 || true
  cleanup_openssl_probe_pod "${pod}"
}

auth_roundtrip_healthy() {
  local spoke="$1" value_yaml bearer cert_part ready
  value_yaml="$(decoded_hub_credential "${spoke}" 2>/dev/null || true)"
  [[ -n "${value_yaml}" ]] || return 1
  bearer="$(yq eval '.users[0].user.token // ""' - <<< "${value_yaml}" 2>/dev/null || true)"
  cert_part="$(yq eval '.clusters[0].cluster.certificate-authority-data // ""' - <<< "${value_yaml}" 2>/dev/null || true)"
  [[ -n "${bearer}" && -n "${cert_part}" ]] || return 1
  ready="$(openssl_https_request "${spoke}" "${bearer}" "/readyz" "${cert_part}" 2>/dev/null || true)"
  printf '%s\n' "${ready}" | tr -d '\r' | grep -qx 'ok'
}

node_route_healthy() {
  local spoke="$1" value_yaml bearer cert_part nodes expected_node
  value_yaml="$(decoded_hub_credential "${spoke}" 2>/dev/null || true)"
  [[ -n "${value_yaml}" ]] || return 1
  bearer="$(yq eval '.users[0].user.token // ""' - <<< "${value_yaml}" 2>/dev/null || true)"
  cert_part="$(yq eval '.clusters[0].cluster.certificate-authority-data // ""' - <<< "${value_yaml}" 2>/dev/null || true)"
  [[ -n "${bearer}" && -n "${cert_part}" ]] || return 1
  expected_node="k3d-${spoke}-server-0"
  nodes="$(openssl_https_request "${spoke}" "${bearer}" "/api/v1/nodes" "${cert_part}" 2>/dev/null || true)"
  [[ "${nodes}" == *"${expected_node}"* && "${nodes}" != *"${EXPECTED_FORBIDDEN_NODE}"* ]]
}

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
       Fix: rerun: bash scripts/register-spokes-for-flux.sh"
    exit 1
  fi

  TOKEN_DECODED="$(decode_b64 "${secret_part}")"
  CA_B64="${cert_part}"
}

build_kubeconfig() {
  local spoke="$1" bearer="$2" cert_part="$3"
  local server
  server="$(expected_server "${spoke}")"
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

apply_hub_secret() {
  local spoke="$1" payload="$2"
  printf '%s\n' "${payload}" |
    kubectl --context "${HUB_CTX}" -n "${FLUX_NS}" create secret generic "${spoke}-kubeconfig" \
      --from-file=value.yaml=/dev/stdin --dry-run=client -o yaml |
    kubectl --context "${HUB_CTX}" -n "${FLUX_NS}" apply -f -
}

repair_file_if_needed() {
  local target="$1" tmp="$2" label="$3"
  if [[ -f "${target}" ]] && cmp -s "${tmp}" "${target}"; then
    info "already done, skipping: ${label}"
    rm -f "${tmp}"
  else
    mkdir -p "$(dirname "${target}")"
    mv "${tmp}" "${target}"
    pass "repaired: ${label}"
  fi
}

ensure_hub_kustomization() {
  local spoke="$1" tmp target
  target="${SPOKES_DIR}/${spoke}.yaml"
  tmp="$(mktemp)"
  cat > "${tmp}" <<EOF
# clusters/hub-flux/spokes/${spoke}.yaml
# Flux v1 Kustomization - hub-flux's kustomize-controller reconciles
# clusters/${spoke}/ into k3d-${spoke} via the ${spoke}-kubeconfig Secret
# (applied imperatively by scripts/register-spokes-for-flux.sh; never committed
# because it contains a bearer token).
#
# REQ-SPOKE-05 (this file's existence + secretRef shape).
# REQ-SPOKE-04 (key: value.yaml explicit - RESEARCH.md Pitfall 2 reframe:
#   the silent-misroute fault is \`spec.kubeConfig\` ENTIRELY ABSENT, which would
#   make the controller fall back to its in-cluster SA and reconcile to HUB.
#   ALWAYS include the entire spec.kubeConfig block; explicit \`key: value.yaml\`
#   is belt-and-suspenders against future Flux default-key behavior changes.)
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: ${spoke}
  namespace: flux-system
spec:
  interval: 5m
  path: ./clusters/${spoke}
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  kubeConfig:
    secretRef:
      name: ${spoke}-kubeconfig
      key: value.yaml
EOF
  repair_file_if_needed "${target}" "${tmp}" "clusters/hub-flux/spokes/${spoke}.yaml"
}

ensure_spokes_index() {
  local tmp
  tmp="$(mktemp)"
  cat > "${tmp}" <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- spoke-ml.yaml
- spoke-apps.yaml
EOF
  repair_file_if_needed "${SPOKES_DIR}/kustomization.yaml" "${tmp}" "clusters/hub-flux/spokes/kustomization.yaml"
}

ensure_spoke_seed() {
  local spoke="$1" ns tmp dir example_resource="" existing_resources=()
  ns="karyon-${spoke}"
  dir="${REPO_ROOT}/clusters/${spoke}"

  case "${spoke}" in
    spoke-apps)
      if [[ -d "${REPO_ROOT}/examples/podinfo" ]]; then
        example_resource="../../examples/podinfo"
      fi
      ;;
    spoke-ml)
      if [[ -d "${REPO_ROOT}/examples/gpu-smoke-test" ]]; then
        example_resource="../../examples/gpu-smoke-test"
      fi
      ;;
  esac

  if [[ -f "${dir}/kustomization.yaml" ]]; then
    mapfile -t existing_resources < <(
      yq eval '.resources[]?' "${dir}/kustomization.yaml"
    )
  fi

  append_resource_once() {
    local candidate="$1" existing
    for existing in "${existing_resources[@]}"; do
      if [[ "${existing}" == "${candidate}" ]]; then
        return
      fi
    done
    existing_resources+=("${candidate}")
  }

  append_resource_once "namespace.yaml"
  append_resource_once "configmap.yaml"
  if [[ -n "${example_resource}" ]]; then
    append_resource_once "${example_resource}"
  fi

  tmp="$(mktemp)"
  cat > "${tmp}" <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
EOF
  printf -- '- %s\n' "${existing_resources[@]}" >> "${tmp}"
  repair_file_if_needed "${dir}/kustomization.yaml" "${tmp}" "clusters/${spoke}/kustomization.yaml"

  tmp="$(mktemp)"
  cat > "${tmp}" <<EOF
# clusters/${spoke}/namespace.yaml
# REQ-SPOKE-05 seed - distinct per spoke, falsifiable for the cross-cluster
# negative-proof (this Namespace exists ONLY on k3d-${spoke}).
apiVersion: v1
kind: Namespace
metadata:
  name: ${ns}
EOF
  repair_file_if_needed "${dir}/namespace.yaml" "${tmp}" "clusters/${spoke}/namespace.yaml"

  tmp="$(mktemp)"
  cat > "${tmp}" <<EOF
# clusters/${spoke}/configmap.yaml
# REQ-SPOKE-05 seed - ConfigMap NAME is karyon-spoke-id (same on both spokes;
# the namespace and data.spoke value differ - that is the cross-cluster
# falsifier per ROADMAP success #5 / Phase 4 D-03 / RESEARCH.md Pitfall 2).
apiVersion: v1
kind: ConfigMap
metadata:
  name: karyon-spoke-id
  namespace: ${ns}
data:
  spoke: ${spoke}
EOF
  repair_file_if_needed "${dir}/configmap.yaml" "${tmp}" "clusters/${spoke}/configmap.yaml"
}

ensure_hub_spokes_mount() {
  local tmp tmp_with_sentinel

  if [[ ! -f "${HUB_KUST_FILE}" ]]; then
    fail "${HUB_KUST_FILE} missing.
       Fix: bash scripts/bootstrap-flux.sh && bash scripts/register-spokes-for-flux.sh"
    exit 1
  fi

  tmp="$(mktemp)"
  # shellcheck disable=SC2016 # yq expression intentionally uses single quotes.
  if ! yq eval '(.resources // []) as $r | .resources = ($r + ["../spokes"] | unique)' \
      "${HUB_KUST_FILE}" > "${tmp}"; then
    rm -f "${tmp}"
    fail "${HUB_KUST_FILE} is not valid YAML.
       Fix: repair the Flux patch surface, then rerun bash scripts/register-spokes-for-flux.sh"
    exit 1
  fi

  if ! yq eval -e '.resources[] == "../spokes"' "${tmp}" >/dev/null; then
    rm -f "${tmp}"
    fail "${HUB_KUST_FILE} could not be repaired with ../spokes.
       Fix: inspect ${HUB_KUST_FILE}, then rerun bash scripts/register-spokes-for-flux.sh"
    exit 1
  fi

  tmp_with_sentinel="$(mktemp)"
  awk -v sentinel="${SPOKES_SENTINEL}" '
    $0 ~ /^[[:space:]]*-[[:space:]]+\.\.\/spokes[[:space:]]*$/ && !inserted {
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

  if ! yq eval -e '.resources[] == "../spokes"' "${tmp_with_sentinel}" >/dev/null; then
    rm -f "${tmp_with_sentinel}"
    fail "${HUB_KUST_FILE} repair validation failed.
       Fix: inspect ${HUB_KUST_FILE}, then rerun bash scripts/register-spokes-for-flux.sh"
    exit 1
  fi

  if cmp -s "${tmp_with_sentinel}" "${HUB_KUST_FILE}"; then
    rm -f "${tmp_with_sentinel}"
    info "already done, skipping: spokes mount resource present in ${HUB_KUST_FILE}"
  else
    mv "${tmp_with_sentinel}" "${HUB_KUST_FILE}"
    pass "repaired: ../spokes resource under resources in ${HUB_KUST_FILE}"
  fi
}

verify_spoke_credential_layer() {
  local spoke="$1" value_b64 value_yaml expected actual bearer cert_part spoke_cert_part ready nodes expected_node
  expected="$(expected_server "${spoke}")"
  value_b64="$(hub_secret_value "${spoke}")"
  if [[ -z "${value_b64}" ]]; then
    fail "${spoke} hub Secret missing data.value.yaml.
       Fix: bash scripts/register-spokes-for-flux.sh"
    exit 1
  fi
  pass "presence ok: ${spoke} hub Secret data.value.yaml populated"

  value_yaml="$(decode_b64 "${value_b64}")"
  actual="$(yq eval '.clusters[0].cluster.server // ""' - <<< "${value_yaml}" 2>/dev/null || true)"
  bearer="$(yq eval '.users[0].user.token // ""' - <<< "${value_yaml}" 2>/dev/null || true)"
  cert_part="$(yq eval '.clusters[0].cluster.certificate-authority-data // ""' - <<< "${value_yaml}" 2>/dev/null || true)"
  if [[ "${actual}" != "${expected}" || -z "${bearer}" || -z "${cert_part}" ]]; then
    fail "${spoke} credential decode failed or server drifted (expected ${expected}).
       Inspect: kubectl --context ${HUB_CTX} -n ${FLUX_NS} get secret ${spoke}-kubeconfig -o go-template='{{.metadata.name}}{{\" data.value.yaml present=\"}}{{if index .data \"value.yaml\"}}yes{{else}}no{{end}}{{\"\\n\"}}'
       Fix: bash scripts/register-spokes-for-flux.sh"
    exit 1
  fi
  if ! decode_b64 "${cert_part}" >/dev/null 2>&1; then
    fail "${spoke} certificate data is not base64-decodable.
       Fix: bash scripts/register-spokes-for-flux.sh"
    exit 1
  fi
  spoke_cert_part="$(kubectl --context "k3d-${spoke}" -n "${FLUX_NS}" get secret "${RECONCILER_SECRET}" \
    -o jsonpath='{.data.ca\.crt}' 2>/dev/null || true)"
  if [[ "${cert_part}" != "${spoke_cert_part}" ]]; then
    fail "${spoke} certificate data does not match spoke credential source.
       Fix: bash scripts/register-spokes-for-flux.sh"
    exit 1
  fi
  pass "decode ok: ${spoke} server + bearer + CA equality verified"

  if ! verify_tls_with_openssl "${spoke}" "${cert_part}"; then
    fail "${spoke} TLS proof failed from the hub cluster.
       Inspect: kubectl --context ${HUB_CTX} -n ${FLUX_NS} get pods -l run=karyon-openssl-probe-${spoke}
       Fix: rerun cluster creation if the spoke apiserver cert SAN is wrong; then rerun this script."
    exit 1
  fi
  pass "tls ok: ${spoke} certificate validates k3d-${spoke}-server-0"

  ready="$(openssl_https_request "${spoke}" "${bearer}" "/readyz" "${cert_part}" || true)"
  if ! printf '%s\n' "${ready}" | tr -d '\r' | grep -qx 'ok'; then
    fail "${spoke} /readyz auth roundtrip failed.
       Repro: rerun bash scripts/register-spokes-for-flux.sh and inspect the verified openssl HTTPS probe.
       Fix: bash scripts/register-spokes-for-flux.sh"
    exit 1
  fi
  pass "auth roundtrip ok: ${spoke} /readyz returned ok"

  expected_node="k3d-${spoke}-server-0"
  nodes="$(openssl_https_request "${spoke}" "${bearer}" "/api/v1/nodes" "${cert_part}" || true)"
  if [[ "${nodes}" != *"${expected_node}"* || "${nodes}" == *"${EXPECTED_FORBIDDEN_NODE}"* ]]; then
    fail "P18 SILENT MISROUTE warning for ${spoke}: expected ${expected_node} and not ${EXPECTED_FORBIDDEN_NODE}.
       Inspect: kubectl --context ${HUB_CTX} -n ${FLUX_NS} get secret ${spoke}-kubeconfig -o go-template='{{.metadata.name}}{{\" data.value.yaml present=\"}}{{if index .data \"value.yaml\"}}yes{{else}}no{{end}}{{\"\\n\"}}'
       Fix: do NOT push current state; rerun bash scripts/register-spokes-for-flux.sh"
    exit 1
  fi
  pass "node-name proof ok: ${spoke} routes to ${expected_node}"
}

register_spoke() {
  local spoke="$1" mutation_needed=1 kubeconfig_yaml

  section "${spoke}"

  if spoke_rbac_healthy "${spoke}" && hub_secret_healthy "${spoke}" \
      && auth_roundtrip_healthy "${spoke}" && node_route_healthy "${spoke}"; then
    info "already done, skipping: ${spoke} runtime mutation (RBAC present, Secret decodes, auth ok, routing ok)"
    mutation_needed=0
  fi

  if [[ "${mutation_needed}" -eq 1 ]]; then
    apply_spoke_rbac "${spoke}"
    pass "applied: ${spoke} RBAC in ${FLUX_NS}"

    wait_for_token_secret "${spoke}"
    pass "credential data populated for ${spoke}"

    kubeconfig_yaml="$(build_kubeconfig "${spoke}" "${TOKEN_DECODED}" "${CA_B64}")"
    apply_hub_secret "${spoke}" "${kubeconfig_yaml}"
    pass "applied: ${spoke} hub Secret"
  fi

  ensure_hub_kustomization "${spoke}"
  ensure_spoke_seed "${spoke}"
  verify_spoke_credential_layer "${spoke}"
}

# ---------- Section 1: Preflight gate ----------
section "Preflight gate"
PREFLIGHT_LOG="$(mktemp -t karyon-preflight.XXXXXX.log)"
if ! bash "${SCRIPT_DIR}/preflight.sh" > "${PREFLIGHT_LOG}" 2>&1; then
  fail "preflight has blockers before registering spokes.
     Fix: bash scripts/preflight.sh
     Log: ${PREFLIGHT_LOG}"
  exit 1
fi
pass "preflight green"
rm -f "${PREFLIGHT_LOG}"

# ---------- Section 2: Context check ----------
section "Context check"
ctx="$(kubectl config current-context 2>/dev/null || true)"
if [[ "${ctx}" != "${HUB_CTX}" ]]; then
  fail "kubectl context is ${ctx:-unset}, expected ${HUB_CTX}.
     Fix: kubectl config use-context ${HUB_CTX}"
  exit 1
fi
pass "kubectl context: ${HUB_CTX}"

# ---------- Sections 3 and 4: per-spoke registration ----------
register_spoke spoke-ml
register_spoke spoke-apps

# ---------- Section 5: Hub-side Kustomization wire-up ----------
section "Hub-side Kustomization wire-up"
ensure_spokes_index
ensure_hub_spokes_mount

# ---------- Summary ----------
section "Summary"
printf "  %s%d passed%s, %s%d warnings%s, %s%d failed%s\n" \
  "${C_GREEN}" "${PASS}" "${C_RESET}" "${C_YELLOW}" "${WARN}" "${C_RESET}" "${C_RED}" "${FAIL}" "${C_RESET}"
if (( FAIL > 0 )); then exit 1; fi

info "Next: commit + push the new files so Flux reconciles them."
info "  git add clusters/hub-flux/spokes clusters/hub-flux/flux-system/kustomization.yaml \\"
info "          clusters/spoke-ml clusters/spoke-apps Taskfile.yml docs/flux-hub-spoke.md \\"
info "          scripts/register-spokes-for-flux.sh tests/bats/register-spokes-*.bats"
info "  git commit -m 'feat(04): register spokes for Flux reconciliation (SPOKE-01..06)'"
info "  git push"
info "  flux --context k3d-hub-flux reconcile source git flux-system"
printf "\n%sSpoke registration complete. k3d-hub-flux can now reconcile to spoke-ml and spoke-apps.%s\n" \
  "${C_GREEN}" "${C_RESET}"
