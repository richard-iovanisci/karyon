---
slug: keycloak-idp-poc
date: 2026-07-06
type: quick
status: complete
---

# Quick Task: capsule-addon-fluxcd evaluation (PASS) + Keycloak IdP POC

## Origin

User request (2026-07-06): (a) evaluate whether capsule-addon-fluxcd helps the
"platform team controls tenants; tenants deploy in their tenant spaces through
Flux" goal — implement if good, pass if not; (b) install Keycloak somewhere in
the lab for users/realms/identity in front of capsule-proxy; (c) manage
Keycloak objects with GitOps via the Keycloak operator. Decision authority
delegated; industry best practices requested.

## Research (4-agent workflow, 2026-07-06)

1. **Addon**: source-level evaluation → same-cluster kubeconfig factory;
   no remote mode; output unreachable by hub Flux under ADR-004; Capsule 0.7.2
   API baseline; chart crashloops on defaults (issue #118). → **PASS**
   (ADR-008 addendum; parking-lot ADDON item resolved).
2. **Keycloak operator**: 26.6.4 current; 3 vendorable manifests
   (keycloak-k8s-resources tag 26.6.4); external DB mandatory; initial admin
   Secret `<cr>-initial-admin`; RealmImport = import-once.
3. **Repo wiring**: Capsule's namespaces webhook denies ALL non-tenant
   namespace creation (even cluster-admin — dry-run falsified the "plain
   namespace" plan) → keycloak must be a tenant-shaped POC; poc-mount-01 +
   push-gate-02 bats need amending; no new host ports without cluster recreate
   → UI via port-forward; headroom ample (~51Gi free).
4. **OIDC integration**: apiserver validates tokens (proxy TokenReviews);
   flat groups + full.path OFF mandatory for Capsule exact-match; k3s flags
   retrofittable via config.yaml + container restart; issuer must be one
   https URL (host.k3d.internal plan).

## Decisions

- D-KC-01: addon = PASS (see ADR-008 addendum 2026-07-06 §addon evaluation).
- D-KC-02: Keycloak on spoke-capsule as third tenant-shaped POC (`keycloak`
  Tenant, unconstrained), NOT hub (rebuild-SLO) and NOT a new spoke (lifecycle
  surface).
- D-KC-03: vendored official operator manifests @26.6.4 (no Helm; no remote
  bases), 3-K DAG keycloak-tenant → keycloak-spoke → keycloak-app, all
  spoke-targeted (P18 kubeConfig + P27 SA).
- D-KC-04: http-only + port-forward for the POC; TLS + pinned issuer deferred
  to the OIDC follow-up (no certs/secrets in git).
- D-KC-05: realm `karyon` future-proofed for Capsule OIDC: flat groups
  (capsule-users, capsule-platform-owners, tenant-alpha-devs,
  tenant-bravo-devs), groups mapper full.path OFF, public PKCE `kubectl`
  client, users seeded without credentials; CapsuleConfiguration userGroups
  extended 3→7 (push-gate-02 amended).
- D-KC-06: keycloak-db-secret imperative + non-rotating
  (scripts/poc/keycloak/create-secrets.sh); accepted side effects documented
  (GTR hello-world seeds into keycloak ns; destroy-poc 90s cascade warn;
  third row in Act 2 tenant list — runbook updated).
