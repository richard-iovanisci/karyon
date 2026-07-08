#!/usr/bin/env bash
# scripts/poc/capsule/create-cluster.sh
# Creates the persistent spoke-capsule k3d cluster on k8s-net.
#
# Idempotent: skip-if-exists with image/network/api-port/NodePort drift verify
# (mirrors create_cluster() in scripts/create-clusters.sh).
#
# Standalone POC helper for the persistent spoke-capsule cluster; never invoked by task rebuild
# (enforced by tests/bats/poc-isolation-01-static.bats).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# shellcheck source=../../lib/preflight-lib.sh
# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/lib/preflight-lib.sh"

# Pinned literals (LOCKED -- bats suites grep-assert these):
readonly POC_CLUSTER="spoke-capsule"
readonly POC_API_PORT="6446"
readonly POC_NODEPORT="30443"
readonly K8S_NET_NAME="k8s-net"
readonly K3S_STOCK_IMAGE="rancher/k3s:v1.34.6-k3s1"
readonly EXPECTED_SAN="k3d-${POC_CLUSTER}-server-0"

# ---------- Section 1: Preflight gate ----------
section "Preflight gate (includes NodePort 30443 fail-fast)"
if ! bash "${REPO_ROOT}/scripts/preflight.sh" >/tmp/preflight-poc-$$.log 2>&1; then
  fail "preflight has blockers -- likely 30443 in use.
     Inspect: cat /tmp/preflight-poc-$$.log
     Fix:     free port 30443 (kill the listener) and rerun bash scripts/poc/capsule/create-cluster.sh"
  exit 1
fi
pass "preflight green"
rm -f /tmp/preflight-poc-$$.log

# ---------- Section 2: Cluster create or drift-verify ----------
section "${POC_CLUSTER} cluster"
if k3d cluster list --no-headers 2>/dev/null | awk '{print $1}' | grep -qx "${POC_CLUSTER}"; then
  # Existing cluster -- verify image / network / api-port / NodePort match expectations
  srv_container="k3d-${POC_CLUSTER}-server-0"
  lb_container="k3d-${POC_CLUSTER}-serverlb"

  actual_image="$(docker inspect "$srv_container" -f '{{.Config.Image}}' 2>/dev/null || echo "")"
  actual_network="$(docker inspect "$srv_container" -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' 2>/dev/null || echo "")"
  actual_ports="$(docker inspect "$lb_container" -f '{{range $k, $v := .NetworkSettings.Ports}}{{$k}}={{range $v}}{{.HostPort}}{{end}} {{end}}' 2>/dev/null || echo "")"

  # (a) IMAGE drift
  if [[ "$actual_image" != "${K3S_STOCK_IMAGE}" ]]; then
    fail "cluster ${POC_CLUSTER} IMAGE drift (actual=${actual_image:-?}, expected=${K3S_STOCK_IMAGE}).
       Fix: k3d cluster delete ${POC_CLUSTER} && bash scripts/poc/capsule/create-cluster.sh"
    exit 1
  fi

  # (b) NETWORK drift
  if [[ "$actual_network" != *"${K8S_NET_NAME}"* ]]; then
    fail "cluster ${POC_CLUSTER} NETWORK drift (actual=${actual_network:-?}, expected includes=${K8S_NET_NAME}).
       Fix: k3d cluster delete ${POC_CLUSTER} && bash scripts/poc/capsule/create-cluster.sh"
    exit 1
  fi

  # (c) API PORT drift (serverlb maps host POC_API_PORT to container 6443)
  if ! echo "$actual_ports" | grep -qE "6443/tcp=${POC_API_PORT}"; then
    fail "cluster ${POC_CLUSTER} API PORT drift (serverlb ports=${actual_ports:-?}, expected includes=6443/tcp=${POC_API_PORT}).
       Fix: k3d cluster delete ${POC_CLUSTER} && bash scripts/poc/capsule/create-cluster.sh"
    exit 1
  fi

  # (d) NodePort drift (POC-reserved 30443)
  if ! echo "$actual_ports" | grep -qE "${POC_NODEPORT}/tcp=${POC_NODEPORT}"; then
    fail "cluster ${POC_CLUSTER} NODEPORT drift (expected ${POC_NODEPORT} published; actual ports=${actual_ports:-?}).
       Fix: k3d cluster delete ${POC_CLUSTER} && bash scripts/poc/capsule/create-cluster.sh"
    exit 1
  fi
  info "already done, skipping: cluster ${POC_CLUSTER} (image=${actual_image}, network=${K8S_NET_NAME}, api=${POC_API_PORT}, nodeport=${POC_NODEPORT})"
else
  info "creating: cluster ${POC_CLUSTER} on :${POC_API_PORT} + NodePort ${POC_NODEPORT} (network=${K8S_NET_NAME})"
  # @loadbalancer publishes the host port on the serverlb container -- matches the v0.18
  # drift-verify pattern (which inspects serverlb only). The capsule-proxy NodePort Service
  # is routed via serverlb -> server-0 transparently (k3d's serverlb is just an HAProxy frontend).
  # The pinned literals are inlined here (bats grep-asserts the exact strings; expansion-via-vars
  # would let a single-character typo silently drift the published port or SAN nodefilter).
  k3d cluster create "${POC_CLUSTER}" \
    --image "${K3S_STOCK_IMAGE}" \
    --api-port "${POC_API_PORT}" \
    --network "${K8S_NET_NAME}" \
    --port "30443:30443@loadbalancer" \
    --k3s-arg "--tls-san=k3d-spoke-capsule-server-0@server:*"
  pass "created: cluster ${POC_CLUSTER}"
fi

# ---------- Section 3: SAN verification (bounded retry: 10 × 3s = 30s) ----------
section "${POC_CLUSTER} TLS SAN verification"
san_ok=0
for i in $(seq 1 10); do
  if openssl s_client -connect "127.0.0.1:${POC_API_PORT}" -servername "${EXPECTED_SAN}" </dev/null 2>/dev/null \
      | openssl x509 -noout -text 2>/dev/null \
      | grep -qE "DNS:${EXPECTED_SAN}"; then
    san_ok=1
    break
  fi
  sleep 3
done
if [[ "$san_ok" -eq 1 ]]; then
  pass "SAN verified: cluster ${POC_CLUSTER} cert includes DNS:${EXPECTED_SAN}"
else
  warn "deleting broken cluster ${POC_CLUSTER} (SAN missing after 10 retries / 30s)"
  k3d cluster delete "${POC_CLUSTER}" >/dev/null 2>&1 || true
  fail "cluster ${POC_CLUSTER} apiserver cert missing SAN DNS:${EXPECTED_SAN} after 30s (k3d issue #1613 may be firing).
     Fix: confirm the create-cluster helper still uses the wildcard SAN nodefilter (k3d issue #1613);
          the cluster has been deleted -- rerun bash scripts/poc/capsule/create-cluster.sh"
  exit 1
fi

# ---------- Section 4: Summary ----------
section "Summary"
printf "  %s%d passed%s, %s%d warnings%s, %s%d failed%s\n" \
  "${C_GREEN}" "${PASS}" "${C_RESET}" "${C_YELLOW}" "${WARN}" "${C_RESET}" "${C_RED}" "${FAIL}" "${C_RESET}"
if (( FAIL > 0 )); then exit 1; fi
printf "\n%scluster ${POC_CLUSTER} ready (api :${POC_API_PORT}, NodePort :${POC_NODEPORT}).%s\n" "${C_GREEN}" "${C_RESET}"
printf "%sNext step: bash scripts/register-poc-cluster.sh ${POC_CLUSTER}%s\n" "${C_DIM}" "${C_RESET}"
