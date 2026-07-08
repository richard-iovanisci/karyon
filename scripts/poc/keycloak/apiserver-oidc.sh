#!/usr/bin/env bash
# scripts/poc/keycloak/apiserver-oidc.sh
# Retrofit OIDC validation onto the spoke-capsule apiserver — NO cluster
# recreate (2026-07-06; design in docs/poc-keycloak.md §OIDC).
#
# Safe because the node's CLI args are ONLY `server --tls-san=...` (verified):
# k3s merges /etc/rancher/k3s/config.yaml with nothing to clobber.
# ⚠ BLAST RADIUS: k3s = apiserver+kubelet+containerd in ONE container —
# `docker restart` restarts EVERY pod on spoke-capsule (~30-90s; Keycloak
# slowest). Hub Flux is unaffected and re-reconciles.
#
# Persistence: /var/lib/rancher/k3s is a docker VOLUME (CA survives restarts +
# k3d stop/start); /etc/rancher/k3s is container rw-layer (survives restarts).
# BOTH die with `k3d cluster delete` — rerun this script after any recreate.
#
# Idempotent: overwrites config.yaml + CA and restarts; safe to rerun.
# Rollback: overwrite config.yaml with an empty file + docker restart
# (docker cp cannot delete; empty yaml parses fine).
set -euo pipefail

readonly NODE="k3d-spoke-capsule-server-0"
readonly SPOKE_CTX="k3d-spoke-capsule"
readonly PKI="${HOME}/.karyon/oidc-pki"
readonly ISSUER="https://localhost:31443/realms/karyon"

C_GREEN=$'\033[0;32m'; C_RED=$'\033[0;31m'; C_DIM=$'\033[2m'; C_RESET=$'\033[0m'
pass() { printf '%s  ok%s %s\n' "${C_GREEN}" "${C_RESET}" "$*" >&2; }
fail() { printf '%s  xx%s %s\n' "${C_RED}" "${C_RESET}" "$*" >&2; }
info() { printf '%s  ..%s %s\n' "${C_DIM}" "${C_RESET}" "$*" >&2; }

command -v docker >/dev/null 2>&1 || { fail "docker missing"; exit 1; }
[[ -f "${PKI}/ca.crt" ]] || { fail "OIDC CA missing at ${PKI}/ca.crt — run create-tls.sh first"; exit 1; }
docker inspect "${NODE}" >/dev/null 2>&1 || { fail "node container ${NODE} missing"; exit 1; }

# Guard: the issuer must be reachable from the NODE loopback (kube-proxy
# localhost-NodePort path — breaks under nftables kube-proxy). A plaintext
# probe answered by the TLS listener returns HTTP 400: that IS the proof.
if ! docker exec "${NODE}" sh -c 'wget -T3 -q -O- http://127.0.0.1:31443/ 2>&1 | grep -q .' \
   && ! docker exec "${NODE}" sh -c 'wget -T3 -O- http://127.0.0.1:31443/ 2>&1 | grep -qE "400|error"'; then
  fail "node cannot reach 127.0.0.1:31443 (keycloak-oidc NodePort). Is the Service applied + kube-proxy in iptables mode?"
  exit 1
fi
pass "node-loopback NodePort path confirmed (127.0.0.1:31443 answers)"

info "placing OIDC CA into the volume-backed k3s dir"
docker exec "${NODE}" mkdir -p /var/lib/rancher/k3s/server/oidc
docker cp "${PKI}/ca.crt" "${NODE}:/var/lib/rancher/k3s/server/oidc/ca.crt"

info "writing /etc/rancher/k3s/config.yaml"
tmp="$(mktemp)"
cat > "${tmp}" <<EOF
kube-apiserver-arg:
  - oidc-issuer-url=${ISSUER}
  - oidc-client-id=kubectl
  - oidc-username-claim=preferred_username
  - oidc-username-prefix=-
  - oidc-groups-claim=groups
  - oidc-ca-file=/var/lib/rancher/k3s/server/oidc/ca.crt
EOF
docker cp "${tmp}" "${NODE}:/etc/rancher/k3s/config.yaml"
rm -f "${tmp}"

info "restarting ${NODE} (all pods on the spoke restart; ~30-90s)"
docker restart "${NODE}" >/dev/null

info "waiting for apiserver readyz"
for i in $(seq 1 30); do
  kubectl --context "${SPOKE_CTX}" get --raw /readyz >/dev/null 2>&1 && break
  sleep 5
done
kubectl --context "${SPOKE_CTX}" get --raw /readyz >/dev/null 2>&1 || { fail "apiserver not ready after restart — diagnose: docker logs --tail 50 ${NODE}"; exit 1; }
pass "apiserver ready"

# Verify flags: k3s embeds kube-apiserver in-process — flags appear ONLY in
# the 'Running kube-apiserver' log line (ps is useless).
n=$(docker logs "${NODE}" 2>&1 | grep 'Running kube-apiserver' | tail -1 | tr ' ' '\n' | grep -c 'oidc' || true)
if [[ "${n}" -eq 6 ]]; then
  pass "all 6 oidc flags active on the apiserver"
else
  fail "expected 6 oidc flags in the apiserver invocation, found ${n} — inspect: docker logs ${NODE} | grep 'Running kube-apiserver'"
  exit 1
fi

printf '\n%sApiserver OIDC live.%s Issuer: %s\n' "${C_GREEN}" "${C_RESET}" "${ISSUER}" >&2
