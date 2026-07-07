#!/usr/bin/env bash
# scripts/poc/keycloak/start-oidc-forwarder.sh
# Host-side forwarder making the pinned OIDC issuer https://localhost:31443
# reachable from the WSL host AND the Windows browser (mirrored networking
# shares localhost). Inside the cluster, the apiserver + hostNetwork pods use
# kube-proxy's localhost-NodePort path instead — no forwarder involved.
#
# Why a container and not the k3d serverlb: the serverlb publishes host ports
# only at cluster-create time (recreate required). This socat container joins
# k8s-net and targets the node by docker-DNS NAME, so node-IP shuffle after
# reboots cannot break it. --restart=unless-stopped survives host reboots.
# Idempotent: recreates the forwarder if present.
set -euo pipefail

readonly FWD_NAME="karyon-oidc-fwd"
readonly SOCAT_IMAGE="alpine/socat:1.8.1.3"
readonly NET="k8s-net"
readonly PORT="31443"
readonly TARGET="k3d-spoke-capsule-server-0"

C_GREEN=$'\033[0;32m'; C_RED=$'\033[0;31m'; C_DIM=$'\033[2m'; C_RESET=$'\033[0m'
pass() { printf '%s  ok%s %s\n' "${C_GREEN}" "${C_RESET}" "$*" >&2; }
fail() { printf '%s  xx%s %s\n' "${C_RED}" "${C_RESET}" "$*" >&2; }
info() { printf '%s  ..%s %s\n' "${C_DIM}" "${C_RESET}" "$*" >&2; }

command -v docker >/dev/null 2>&1 || { fail "docker missing"; exit 1; }
docker network inspect "${NET}" >/dev/null 2>&1 || { fail "docker network ${NET} missing"; exit 1; }

if docker ps -a --format '{{.Names}}' | grep -qx "${FWD_NAME}"; then
  info "recreating existing ${FWD_NAME}"
  docker rm -f "${FWD_NAME}" >/dev/null
fi

docker run -d --name "${FWD_NAME}" --restart=unless-stopped \
  --network "${NET}" -p "${PORT}:${PORT}" "${SOCAT_IMAGE}" \
  "tcp-listen:${PORT},fork,reuseaddr" "tcp-connect:${TARGET}:${PORT}" >/dev/null
pass "forwarder ${FWD_NAME} up: host 0.0.0.0:${PORT} → ${TARGET}:${PORT} (${SOCAT_IMAGE})"

info "verifying issuer reachability from the host (CA: ~/.karyon/oidc-pki/ca.crt)"
for i in $(seq 1 12); do
  issuer=$(curl -s --max-time 3 --cacert "${HOME}/.karyon/oidc-pki/ca.crt" \
    "https://localhost:${PORT}/realms/karyon/.well-known/openid-configuration" 2>/dev/null |
    sed -n 's/.*"issuer":"\([^"]*\)".*/\1/p') || true
  [[ -n "${issuer:-}" ]] && break
  sleep 5
done
if [[ "${issuer:-}" == "https://localhost:${PORT}/realms/karyon" ]]; then
  pass "issuer verified: ${issuer}"
else
  fail "issuer not verified yet (got: '${issuer:-<none>}'). If Keycloak is still rolling out TLS, rerun this script."
  exit 1
fi
