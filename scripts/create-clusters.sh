#!/usr/bin/env bash
# scripts/create-clusters.sh
#
# Idempotently creates the k8s-net Docker bridge network and the three k3d clusters
# (hub-flux, spoke-ml, spoke-apps) on a pinned shared network.
#
# Idempotency model: skip if exists + verify expected config.
# Error recovery: no auto-cleanup; set -euo pipefail exits on failure;
#                 user fixes and reruns — succeeded clusters skip, failed retries.
#
# Usage:  bash scripts/create-clusters.sh
# Pre-req: scripts/preflight.sh exits 0.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/preflight-lib.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/preflight-lib.sh"

# ---------- Constants ----------
readonly K8S_NET_NAME="k8s-net"
readonly K8S_NET_SUBNET="172.30.0.0/16"
readonly K8S_NET_DRIVER="bridge"
readonly K3S_STOCK_IMAGE="rancher/k3s:v1.34.6-k3s1"
CUDA_IMAGE_TAG="$("${REPO_ROOT}/images/image-tag.sh")"
readonly CUDA_IMAGE_TAG

# ---------- Section 0: Preflight gate ----------
section "Preflight gate"
if ! bash "${SCRIPT_DIR}/preflight.sh" > /tmp/preflight-$$.log 2>&1; then
  fail "preflight has blockers — run scripts/preflight.sh and fix before creating clusters.
     Log: /tmp/preflight-$$.log"
  exit 1
fi
pass "preflight green"
rm -f /tmp/preflight-$$.log

# ---------- Section 1: k8s-net network ----------
section "k8s-net network"
if docker network inspect "$K8S_NET_NAME" >/dev/null 2>&1; then
  current_subnet="$(docker network inspect "$K8S_NET_NAME" -f '{{(index .IPAM.Config 0).Subnet}}' 2>/dev/null || echo "")"
  current_driver="$(docker network inspect "$K8S_NET_NAME" -f '{{.Driver}}' 2>/dev/null || echo "")"
  if [[ "$current_subnet" == "$K8S_NET_SUBNET" && "$current_driver" == "$K8S_NET_DRIVER" ]]; then
    info "already done, skipping: ${K8S_NET_NAME} (subnet=${current_subnet}, driver=${current_driver})"
  else
    fail "${K8S_NET_NAME} exists with drift (subnet=${current_subnet:-?}, driver=${current_driver:-?}; expected subnet=${K8S_NET_SUBNET}, driver=${K8S_NET_DRIVER}).
       Fix: scripts/delete-clusters.sh && scripts/create-clusters.sh"
    exit 1
  fi
else
  docker network create --driver "$K8S_NET_DRIVER" --subnet "$K8S_NET_SUBNET" "$K8S_NET_NAME" >/dev/null
  pass "creating: ${K8S_NET_NAME} (subnet=${K8S_NET_SUBNET}, driver=${K8S_NET_DRIVER})"
fi

# ---------- Section 2: CUDA image presence (dep of spoke-ml) ----------
section "CUDA image"
if docker images "$CUDA_IMAGE_TAG" --format '{{.Repository}}:{{.Tag}}' | grep -qx "$CUDA_IMAGE_TAG"; then
  info "already done, skipping: ${CUDA_IMAGE_TAG} present"
else
  if [[ -x "${SCRIPT_DIR}/build-image.sh" ]]; then
    info "building: ${CUDA_IMAGE_TAG} (calling scripts/build-image.sh)"
    "${SCRIPT_DIR}/build-image.sh"
    pass "built: ${CUDA_IMAGE_TAG}"
  else
    fail "${CUDA_IMAGE_TAG} missing and scripts/build-image.sh not found.
       Fix: run scripts/build-image.sh (or: docker build -f images/Dockerfile.k3s-cuda -t \"${CUDA_IMAGE_TAG}\" .)"
    exit 1
  fi
fi

# ---------- helper: create_cluster name port [extra k3d args ...] ----------
create_cluster() {
  local name="$1" port="$2"
  shift 2
  local extra_args=("$@")

  section "${name} cluster"

  # Idempotency check — must verify IMAGE, NETWORK, API PORT, and GPU (spoke-ml only)
  if k3d cluster list --no-headers 2>/dev/null | awk '{print $1}' | grep -qx "$name"; then
    local srv_container="k3d-${name}-server-0"
    local lb_container="k3d-${name}-serverlb"
    local actual_image actual_network actual_ports
    actual_image="$(docker inspect "$srv_container" -f '{{.Config.Image}}' 2>/dev/null || echo "")"
    actual_network="$(docker inspect "$srv_container" -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' 2>/dev/null || echo "")"
    actual_ports="$(docker inspect "$lb_container" -f '{{range $k, $v := .NetworkSettings.Ports}}{{$k}}={{range $v}}{{.HostPort}}{{end}} {{end}}' 2>/dev/null || echo "")"

    # Resolve expected image from extra_args, defaulting to stock
    local expected_image="$K3S_STOCK_IMAGE"
    local i gpu_requested=0
    for ((i=0; i<${#extra_args[@]}; i++)); do
      if [[ "${extra_args[$i]}" == "--image" ]]; then
        expected_image="${extra_args[$((i+1))]}"
      fi
      if [[ "${extra_args[$i]}" == "--gpus" ]]; then
        gpu_requested=1
      fi
    done

    # (a) IMAGE drift
    if [[ "$actual_image" != "$expected_image" ]]; then
      fail "cluster ${name} IMAGE drift (actual=${actual_image:-?}, expected=${expected_image}).
         Fix: scripts/delete-clusters.sh && scripts/create-clusters.sh"
      exit 1
    fi

    # (b) NETWORK drift
    if [[ "$actual_network" != *"$K8S_NET_NAME"* ]]; then
      fail "cluster ${name} NETWORK drift (actual=${actual_network:-?}, expected includes=${K8S_NET_NAME}).
         Fix: scripts/delete-clusters.sh && scripts/create-clusters.sh"
      exit 1
    fi

    # (c) API PORT drift (serverlb always exposes container port 6443; host port varies per cluster)
    if ! echo "$actual_ports" | grep -qE "6443/tcp=${port}"; then
      fail "cluster ${name} API PORT drift (serverlb ports=${actual_ports:-?}, expected=6443/tcp=${port}).
         Fix: scripts/delete-clusters.sh && scripts/create-clusters.sh"
      exit 1
    fi

    # (d) GPU drift on spoke-ml only (DeviceRequests capability from GPU pass-through)
    if [[ "$gpu_requested" -eq 1 ]]; then
      local gpu_cap
      gpu_cap="$(docker inspect "$srv_container" --format '{{json .HostConfig.DeviceRequests}}' 2>/dev/null \
                 | jq -r 'if . == null then "" else (.[0].Capabilities[0][0] // "") end' 2>/dev/null || echo "")"
      if [[ "$gpu_cap" != "gpu" ]]; then
        fail "cluster ${name} GPU drift (DeviceRequests capability=${gpu_cap:-missing}, expected=gpu — GPU pass-through no longer wired).
           Fix: scripts/delete-clusters.sh && scripts/create-clusters.sh"
        exit 1
      fi
    fi

    info "already done, skipping: cluster ${name} (image=${actual_image}, network=${K8S_NET_NAME}, port=${port})"
  else
    info "creating: cluster ${name} on :${port} (network=${K8S_NET_NAME})"
    k3d cluster create "$name" \
      --api-port "$port" \
      --network "$K8S_NET_NAME" \
      --k3s-arg "--tls-san=k3d-${name}-server-0@server:*" \
      "${extra_args[@]}"
    pass "created: cluster ${name}"
  fi

  # ---------- SAN verification (bounded retry: 10 attempts × 3s = 30s cap) ----------
  local expected_san="k3d-${name}-server-0"
  local san_ok=0
  for i in $(seq 1 10); do
    if openssl s_client -connect "127.0.0.1:${port}" -servername "$expected_san" </dev/null 2>/dev/null \
         | openssl x509 -noout -text 2>/dev/null \
         | grep -qE "DNS:${expected_san}"; then
      san_ok=1
      break
    fi
    sleep 3
  done
  if [[ "$san_ok" -eq 1 ]]; then
    pass "SAN verified: cluster ${name} cert includes DNS:${expected_san}"
  else
    warn "deleting broken cluster ${name} (SAN missing after 10 retries / 30s)"
    k3d cluster delete "$name" >/dev/null 2>&1 || true
    fail "cluster ${name} apiserver cert missing SAN DNS:${expected_san} after 30s (k3d issue #1613 may be firing).
       Fix: confirm the create_cluster helper still uses the wildcard SAN nodefilter (see k3d issue #1613);
            the cluster has been deleted — rerun scripts/create-clusters.sh"
    exit 1
  fi
}

# ---------- Section 3-5: three clusters (created serially) ----------
create_cluster hub-flux   6443 --image "$K3S_STOCK_IMAGE"
create_cluster spoke-ml   6444 --image "$CUDA_IMAGE_TAG" --gpus all
create_cluster spoke-apps 6445 --image "$K3S_STOCK_IMAGE"

# ---------- Summary ----------
section "Summary"
printf "  %s%d passed%s, %s%d warnings%s, %s%d failed%s\n" \
  "$C_GREEN" "$PASS" "$C_RESET" "$C_YELLOW" "$WARN" "$C_RESET" "$C_RED" "$FAIL" "$C_RESET"
if (( FAIL > 0 )); then exit 1; fi
printf "\n%sAll three clusters ready on ${K8S_NET_NAME}.%s\n" "$C_GREEN" "$C_RESET"
printf "  kubectl contexts: k3d-hub-flux, k3d-spoke-ml, k3d-spoke-apps\n"
