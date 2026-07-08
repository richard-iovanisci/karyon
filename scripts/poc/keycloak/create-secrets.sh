#!/usr/bin/env bash
# scripts/poc/keycloak/create-secrets.sh
# Imperative Secret bootstrap for the Keycloak IdP POC on k3d-spoke-capsule.
#
# WHY IMPERATIVE: secrets never land in git (repo policy; the repo
# was designed public-safe). GitOps applies everything EXCEPT credentials; this
# script supplies the one Secret the manifests reference:
#   keycloak/keycloak-db-secret  (keys: username, password) — consumed by both
#   the postgresql-db StatefulSet and the Keycloak CR (spec.db.*Secret).
#
# ORDERING: this script CANNOT create the keycloak namespace itself — Capsule's
# namespaces webhook denies namespace creation for every identity except a
# tenant owner (verified 2026-07-06). The namespace is created by the
# poc-keycloak-spoke Flux Kustomization (flux-reconciler impersonation), so we
# poll for it first. Until this script runs, postgres sits in
# CreateContainerConfigError and poc-keycloak-spoke shows not-ready — both
# self-heal within a reconcile interval after the Secret lands.
#
# IDEMPOTENT + NON-ROTATING: if the Secret already exists we leave it alone —
# Postgres initializes its data directory with the first password; rotating the
# Secret without resetting the PVC would break the database. (To rotate: delete
# the Secret AND the postgres PVC, then rerun.)
#
# Token safety: secret material never appears in argv, logs, or files;
# generated in-process and piped via process substitution (/dev/fd). No trace
# mode. Mirrors scripts/register-poc-cluster.sh conventions.
set -euo pipefail

readonly SPOKE_CTX="k3d-spoke-capsule"
readonly NS="keycloak"
readonly SECRET="keycloak-db-secret"
readonly NS_WAIT_SECS=600

C_GREEN=$'\033[0;32m'; C_RED=$'\033[0;31m'; C_DIM=$'\033[2m'; C_RESET=$'\033[0m'
info() { printf '%s  ..%s %s\n' "${C_DIM}" "${C_RESET}" "$*" >&2; }
pass() { printf '%s  ok%s %s\n' "${C_GREEN}" "${C_RESET}" "$*" >&2; }
fail() { printf '%s  xx%s %s\n' "${C_RED}" "${C_RESET}" "$*" >&2; }

# ---------- preflight ----------
for cmd in kubectl openssl; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    fail "required command missing: ${cmd}"
    exit 1
  fi
done

if ! kubectl --context "${SPOKE_CTX}" cluster-info >/dev/null 2>&1; then
  fail "cluster ${SPOKE_CTX} unreachable.
       Fix: create/start the POC cluster, then rerun this script."
  exit 1
fi
pass "cluster ${SPOKE_CTX} reachable"

# ---------- wait for the tenant-claimed namespace ----------
info "waiting up to ${NS_WAIT_SECS}s for namespace ${NS} (created by poc-keycloak-spoke via Flux)"
deadline=$(( $(date +%s) + NS_WAIT_SECS ))
until kubectl --context "${SPOKE_CTX}" get namespace "${NS}" >/dev/null 2>&1; do
  if (( $(date +%s) >= deadline )); then
    fail "namespace ${NS} did not appear within ${NS_WAIT_SECS}s.
       Fix: check 'flux --context k3d-hub-flux get kustomization poc-keycloak-tenant poc-keycloak-spoke -n flux-system'
       (the namespace is GitOps-created; this script cannot create it — Capsule's
       namespaces webhook denies non-tenant-owner namespace creation)."
    exit 1
  fi
  sleep 5
done
pass "namespace ${NS} present"

# ---------- keycloak-db-secret (idempotent, non-rotating) ----------
if kubectl --context "${SPOKE_CTX}" -n "${NS}" get secret "${SECRET}" >/dev/null 2>&1; then
  pass "already done, skipping: ${SECRET} exists (NOT rotated — postgres data is keyed to it)"
else
  # Password generated in-process; reaches kubectl only via /dev/fd (never argv).
  db_password="$(openssl rand -base64 24)"
  kubectl --context "${SPOKE_CTX}" -n "${NS}" create secret generic "${SECRET}" \
    --from-file=username=<(printf '%s' "keycloak") \
    --from-file=password=<(printf '%s' "${db_password}") \
    --dry-run=client -o yaml |
    kubectl --context "${SPOKE_CTX}" -n "${NS}" apply -f -
  unset db_password
  pass "applied: ${SECRET} in ${NS} on ${SPOKE_CTX}"
fi

printf '\n%sKeycloak POC secrets in place.%s\n' "${C_GREEN}" "${C_RESET}" >&2
printf '%sNext: watch "flux --context k3d-hub-flux get kustomization poc-keycloak-spoke poc-keycloak-app -n flux-system";%s\n' "${C_DIM}" "${C_RESET}" >&2
printf '%sadmin login: kubectl --context %s -n %s get secret keycloak-initial-admin (created by the operator once Keycloak starts).%s\n' "${C_DIM}" "${SPOKE_CTX}" "${NS}" "${C_RESET}" >&2
