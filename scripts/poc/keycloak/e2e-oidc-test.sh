#!/usr/bin/env bash
# scripts/poc/keycloak/e2e-oidc-test.sh
# Headless end-to-end falsifier for the OIDC → capsule-proxy → Capsule chain
# (tenant-ui-oidc quick task). Proves, without a browser:
#   Keycloak password grant → real OIDC JWT (groups claim, aud=kubectl)
#   → bearer to capsule-proxy → apiserver OIDC validation (TokenReview)
#   → Capsule owner matching → tenant-scoped LIST.
#
# Uses a dedicated CONFIDENTIAL client `karyon-e2e` with Direct Access Grants
# (password grant) — created day-2 via kcadm, NEVER the production `kubectl`
# client (which keeps direct grants OFF). An audience mapper stamps
# aud=kubectl so the apiserver's --oidc-client-id accepts the token.
# Sets PERMANENT passwords for alice + bob on first run (random; written to
# ~/.karyon/demo-credentials.txt, 0600 — rotate/delete at will).
# Idempotent; exits non-zero on any failed expectation.
set -euo pipefail

readonly SPOKE_CTX="k3d-spoke-capsule"
readonly ISSUER="https://localhost:31443/realms/karyon"
readonly CA="${HOME}/.karyon/oidc-pki/ca.crt"
readonly CRED_FILE="${HOME}/.karyon/demo-credentials.txt"
readonly E2E_CLIENT="karyon-e2e"

C_GREEN=$'\033[0;32m'; C_RED=$'\033[0;31m'; C_DIM=$'\033[2m'; C_RESET=$'\033[0m'
pass() { printf '%s  ok%s %s\n' "${C_GREEN}" "${C_RESET}" "$*" >&2; }
fail() { printf '%s  xx%s %s\n' "${C_RED}" "${C_RESET}" "$*" >&2; exit 1; }
info() { printf '%s  ..%s %s\n' "${C_DIM}" "${C_RESET}" "$*" >&2; }

[[ -f "${CA}" ]] || fail "OIDC CA missing — run create-tls.sh first"

kcadm() {
  kubectl --context "${SPOKE_CTX}" exec -n keycloak keycloak-0 -- bash -c \
    '/opt/keycloak/bin/kcadm.sh "$@" --no-config --server http://localhost:8080 --realm master --user "$KC_BOOTSTRAP_ADMIN_USERNAME" --password "$KC_BOOTSTRAP_ADMIN_PASSWORD" 2>/dev/null' -- "$@"
}

# ---------- demo user passwords (permanent; generated once) ----------
umask 077
mkdir -p "$(dirname "${CRED_FILE}")"
declare -A PW
if [[ -f "${CRED_FILE}" ]]; then
  while IFS=: read -r u p; do PW["$u"]="$p"; done < "${CRED_FILE}"
  pass "already done, skipping: demo credentials exist at ${CRED_FILE}"
else
  for u in alice bob; do PW["$u"]="$(openssl rand -base64 18)"; done
  { printf 'alice:%s\n' "${PW[alice]}"; printf 'bob:%s\n' "${PW[bob]}"; } > "${CRED_FILE}"
  pass "generated demo credentials → ${CRED_FILE} (0600)"
fi
for u in alice bob; do
  uid=$(kcadm get users -r karyon -q username="$u" -q exact=true --fields id | sed -n 's/.*"id" : "\([^"]*\)".*/\1/p' | head -1)
  [[ -n "${uid}" ]] || fail "user $u not found in realm karyon"
  kubectl --context "${SPOKE_CTX}" exec -i -n keycloak keycloak-0 -- bash -c \
    'read -r pw; /opt/keycloak/bin/kcadm.sh set-password -r karyon --userid '"${uid}"' --new-password "$pw" --no-config --server http://localhost:8080 --realm master --user "$KC_BOOTSTRAP_ADMIN_USERNAME" --password "$KC_BOOTSTRAP_ADMIN_PASSWORD" 2>/dev/null' \
    <<<"${PW[$u]}"
  pass "password set (permanent): $u"
done

# ---------- e2e confidential client ----------
cid=$(kcadm get clients -r karyon -q clientId="${E2E_CLIENT}" --fields id | sed -n 's/.*"id" : "\([^"]*\)".*/\1/p' | head -1)
if [[ -z "${cid}" ]]; then
  info "creating confidential e2e client ${E2E_CLIENT}"
  kcadm create clients -r karyon -s clientId="${E2E_CLIENT}" -s enabled=true \
    -s publicClient=false -s standardFlowEnabled=false -s directAccessGrantsEnabled=true \
    -s 'description=Headless e2e falsifier for the OIDC->capsule-proxy chain (scripts/poc/keycloak/e2e-oidc-test.sh)'
  cid=$(kcadm get clients -r karyon -q clientId="${E2E_CLIENT}" --fields id | sed -n 's/.*"id" : "\([^"]*\)".*/\1/p' | head -1)
  kcadm create "clients/${cid}/protocol-mappers/models" -r karyon \
    -s name=groups -s protocol=openid-connect -s protocolMapper=oidc-group-membership-mapper \
    -s 'config."claim.name"=groups' -s 'config."full.path"=false' \
    -s 'config."id.token.claim"=true' -s 'config."access.token.claim"=true'
  kcadm create "clients/${cid}/protocol-mappers/models" -r karyon \
    -s name=audience-kubectl -s protocol=openid-connect -s protocolMapper=oidc-audience-mapper \
    -s 'config."included.client.audience"=kubectl' -s 'config."access.token.claim"=true' -s 'config."id.token.claim"=true'
  pass "created ${E2E_CLIENT} (+groups +aud=kubectl mappers)"
else
  pass "already done, skipping: client ${E2E_CLIENT} exists"
fi
secret=$(kcadm get "clients/${cid}/client-secret" -r karyon | sed -n 's/.*"value" : "\([^"]*\)".*/\1/p' | head -1)
[[ -n "${secret}" ]] || fail "could not read ${E2E_CLIENT} client secret"

# ---------- token → proxy round-trips ----------
get_token() { # user
  curl -s --cacert "${CA}" "${ISSUER}/protocol/openid-connect/token" \
    -d grant_type=password -d client_id="${E2E_CLIENT}" \
    --data-urlencode client_secret="${secret}" \
    -d username="$1" --data-urlencode password="${PW[$1]}" \
    -d scope="openid profile" |
    sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p'
}

# capsule-proxy's serving CA lives in secret capsule-proxy key `ca` (NOT
# capsule-tls — that is Capsule's webhook cert!). kubectl reads the CA file
# more than once, so use a real temp file, never process substitution.
PROXY_CA="$(mktemp)"
trap 'rm -f "${PROXY_CA}"' EXIT
kubectl --context "${SPOKE_CTX}" -n capsule-system get secret capsule-proxy \
  -o jsonpath='{.data.ca}' | base64 -d > "${PROXY_CA}"

proxy_ns_list() { # token
  # KUBECONFIG=/dev/null: without it kubectl merges the CURRENT context's
  # admin CLIENT CERT into the handshake and capsule-proxy (which prefers
  # TLSCertificate auth) rejects it with 'unknown certificate authority'.
  KUBECONFIG=/dev/null kubectl --server https://127.0.0.1:30443 \
    --certificate-authority "${PROXY_CA}" \
    --token "$1" get namespaces -o name 2>&1
}

info "alice (capsule-platform-owners) → expect ALL tenant namespaces"
tok=$(get_token alice); [[ -n "${tok}" ]] || fail "no token for alice"
out=$(proxy_ns_list "${tok}") || fail "alice proxy LIST failed: ${out}"
grep -qF 'namespace/tenant-alpha' <<<"${out}" || fail "alice missing tenant-alpha: ${out}"
grep -qF 'namespace/tenant-bravo' <<<"${out}" || fail "alice missing tenant-bravo"
grep -qF 'namespace/keycloak'     <<<"${out}" || fail "alice missing keycloak ns"
grep -qF 'namespace/kube-system'  <<<"${out}" && fail "alice sees kube-system (filter broken!)"
pass "alice scoped LIST correct: $(tr '\n' ' ' <<<"${out}")"

info "bob (tenant-alpha-devs) → expect ONLY tenant-alpha"
tok=$(get_token bob); [[ -n "${tok}" ]] || fail "no token for bob"
out=$(proxy_ns_list "${tok}") || fail "bob proxy LIST failed: ${out}"
grep -qF 'namespace/tenant-alpha' <<<"${out}" || fail "bob missing tenant-alpha: ${out}"
grep -qF 'namespace/tenant-bravo' <<<"${out}" && fail "bob sees tenant-bravo (isolation broken!)"
grep -qF 'namespace/keycloak'     <<<"${out}" && fail "bob sees keycloak ns (isolation broken!)"
pass "bob scoped LIST correct: $(tr '\n' ' ' <<<"${out}")"

printf '\n%sOIDC → capsule-proxy → Capsule chain VERIFIED end-to-end.%s\n' "${C_GREEN}" "${C_RESET}" >&2
