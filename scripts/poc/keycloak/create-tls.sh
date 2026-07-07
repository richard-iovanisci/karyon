#!/usr/bin/env bash
# scripts/poc/keycloak/create-tls.sh
# Imperative TLS bootstrap for the pinned OIDC issuer https://localhost:31443
# (tenant-ui-oidc quick task, 2026-07-06). Certs NEVER land in git.
#
# Creates (idempotent, non-rotating):
#   ~/.karyon/oidc-pki/{ca.key,ca.crt,keycloak.key,keycloak.crt}  (0600 keys)
#   Secret keycloak/keycloak-tls (kubernetes.io/tls) on k3d-spoke-capsule
#
# The CA (ca.crt) is later: docker-cp'd into the spoke node for the apiserver
# (apiserver-oidc.sh), mounted into Headlamp (setup-headlamp.sh), passed to
# kubelogin (--certificate-authority), and optionally imported into the
# Windows Trusted Root store for a warning-free browser.
# SANs cover: localhost + 127.0.0.1 (the issuer) and the in-cluster service
# names (future in-cluster https consumers).
set -euo pipefail

readonly SPOKE_CTX="k3d-spoke-capsule"
readonly NS="keycloak"
readonly SECRET="keycloak-tls"
readonly PKI="${HOME}/.karyon/oidc-pki"

C_GREEN=$'\033[0;32m'; C_RED=$'\033[0;31m'; C_DIM=$'\033[2m'; C_RESET=$'\033[0m'
info() { printf '%s  ..%s %s\n' "${C_DIM}" "${C_RESET}" "$*" >&2; }
pass() { printf '%s  ok%s %s\n' "${C_GREEN}" "${C_RESET}" "$*" >&2; }
fail() { printf '%s  xx%s %s\n' "${C_RED}" "${C_RESET}" "$*" >&2; }

for cmd in kubectl openssl; do
  command -v "${cmd}" >/dev/null 2>&1 || { fail "required command missing: ${cmd}"; exit 1; }
done
kubectl --context "${SPOKE_CTX}" cluster-info >/dev/null 2>&1 || { fail "cluster ${SPOKE_CTX} unreachable"; exit 1; }

umask 077
mkdir -p "${PKI}"

if [[ -f "${PKI}/ca.crt" && -f "${PKI}/keycloak.crt" ]]; then
  pass "already done, skipping: PKI exists at ${PKI} (NOT rotated — the CA is pinned into the apiserver/Headlamp/kubelogin trust chain)"
else
  info "generating karyon OIDC CA + Keycloak server cert in ${PKI}"
  openssl genrsa -out "${PKI}/ca.key" 4096 2>/dev/null
  openssl req -x509 -new -key "${PKI}/ca.key" -sha256 -days 3650 \
    -subj "/CN=karyon-oidc-ca" -out "${PKI}/ca.crt"
  openssl genrsa -out "${PKI}/keycloak.key" 2048 2>/dev/null
  cat > "${PKI}/san.cnf" <<'EOF'
[req]
distinguished_name = dn
req_extensions = v3_req
prompt = no
[dn]
CN = localhost
[v3_req]
subjectAltName = @alt
[alt]
DNS.1 = localhost
DNS.2 = keycloak-service.keycloak.svc.cluster.local
DNS.3 = keycloak-service.keycloak.svc
DNS.4 = keycloak-oidc.keycloak.svc.cluster.local
DNS.5 = keycloak-oidc.keycloak.svc
IP.1  = 127.0.0.1
EOF
  openssl req -new -key "${PKI}/keycloak.key" -config "${PKI}/san.cnf" -out "${PKI}/keycloak.csr"
  openssl x509 -req -in "${PKI}/keycloak.csr" -CA "${PKI}/ca.crt" -CAkey "${PKI}/ca.key" \
    -CAcreateserial -days 825 -sha256 -extensions v3_req -extfile "${PKI}/san.cnf" \
    -out "${PKI}/keycloak.crt" 2>/dev/null
  chmod 600 "${PKI}/ca.key" "${PKI}/keycloak.key"
  pass "PKI generated (CA valid 10y, server cert 825d)"
fi

if kubectl --context "${SPOKE_CTX}" -n "${NS}" get secret "${SECRET}" >/dev/null 2>&1; then
  pass "already done, skipping: Secret ${SECRET} exists in ${NS}"
else
  kubectl --context "${SPOKE_CTX}" -n "${NS}" create secret tls "${SECRET}" \
    --cert="${PKI}/keycloak.crt" --key="${PKI}/keycloak.key"
  pass "applied: Secret ${SECRET} in ${NS} on ${SPOKE_CTX}"
fi

printf '\n%sTLS in place.%s Next: push/reconcile the Keycloak CR change (poc-keycloak-app), then start-oidc-forwarder.sh.\n' "${C_GREEN}" "${C_RESET}" >&2
