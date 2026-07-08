#!/usr/bin/env bash
# scripts/poc/keycloak/setup-headlamp.sh
# Imperative half of the Headlamp tenant UI:
#   1. ConfigMap capsule-system/karyon-oidc-ca from ~/.karyon/oidc-pki/ca.crt
#      (public cert; kept imperative because it is per-install PKI state).
#   2. Day-2 Keycloak client update: append Headlamp's redirect URI + web
#      origin to the public `kubectl` client (realm import is import-once, so
#      client changes MUST go through the admin API — kcadm via kubectl exec;
#      the bootstrap admin credential never leaves the cluster: kcadm reads
#      the pod's own KC_BOOTSTRAP_ADMIN_* env).
# Idempotent: CA configmap is apply'd; redirect list is merged (no dupes).
set -euo pipefail

readonly SPOKE_CTX="k3d-spoke-capsule"
readonly PKI="${HOME}/.karyon/oidc-pki"
readonly HL_REDIRECT="http://localhost:4466/oidc-callback"
readonly HL_ORIGIN="http://localhost:4466"

C_GREEN=$'\033[0;32m'; C_RED=$'\033[0;31m'; C_DIM=$'\033[2m'; C_RESET=$'\033[0m'
pass() { printf '%s  ok%s %s\n' "${C_GREEN}" "${C_RESET}" "$*" >&2; }
fail() { printf '%s  xx%s %s\n' "${C_RED}" "${C_RESET}" "$*" >&2; }
info() { printf '%s  ..%s %s\n' "${C_DIM}" "${C_RESET}" "$*" >&2; }

[[ -f "${PKI}/ca.crt" ]] || { fail "OIDC CA missing — run create-tls.sh first"; exit 1; }
kubectl --context "${SPOKE_CTX}" get ns capsule-system >/dev/null 2>&1 || { fail "capsule-system missing on ${SPOKE_CTX}"; exit 1; }

kubectl --context "${SPOKE_CTX}" -n capsule-system create configmap karyon-oidc-ca \
  --from-file=ca.crt="${PKI}/ca.crt" --dry-run=client -o yaml |
  kubectl --context "${SPOKE_CTX}" apply -f -
pass "applied: ConfigMap capsule-system/karyon-oidc-ca"

# kcadm wrapper: stateless per-invocation auth inside the pod (verified
# pattern; credentials never leave the cluster, never enter argv here).
kcadm() {
  kubectl --context "${SPOKE_CTX}" exec -n keycloak keycloak-0 -- bash -c \
    '/opt/keycloak/bin/kcadm.sh "$@" --no-config --server http://localhost:8080 --realm master --user "$KC_BOOTSTRAP_ADMIN_USERNAME" --password "$KC_BOOTSTRAP_ADMIN_PASSWORD" 2>/dev/null' -- "$@"
}

info "resolving kubectl client UUID in realm karyon"
cid=$(kcadm get clients -r karyon -q clientId=kubectl --fields id | sed -n 's/.*"id" : "\([^"]*\)".*/\1/p' | head -1)
[[ -n "${cid}" ]] || { fail "kubectl client not found in realm karyon"; exit 1; }
pass "kubectl client: ${cid}"

redirects=$(kcadm get "clients/${cid}" -r karyon --fields redirectUris)
if grep -qF "${HL_REDIRECT}" <<<"${redirects}"; then
  pass "already done, skipping: Headlamp redirect URI registered"
else
  kcadm update "clients/${cid}" -r karyon \
    -s "redirectUris=[\"http://localhost:8000\",\"http://localhost:18000\",\"${HL_REDIRECT}\"]" \
    -s "webOrigins=[\"${HL_ORIGIN}\"]"
  pass "updated kubectl client: +redirect ${HL_REDIRECT}, +webOrigin ${HL_ORIGIN}"
fi

printf '\n%sHeadlamp prerequisites in place.%s Reconcile poc-headlamp, then:\n' "${C_GREEN}" "${C_RESET}" >&2
printf '%s  kubectl --context %s -n capsule-system port-forward svc/headlamp 4466:80%s\n' "${C_DIM}" "${SPOKE_CTX}" "${C_RESET}" >&2
printf '%s  → http://localhost:4466 → "Sign in" → Keycloak login%s\n' "${C_DIM}" "${C_RESET}" >&2
