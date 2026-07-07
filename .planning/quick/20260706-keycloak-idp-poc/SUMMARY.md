---
slug: keycloak-idp-poc
date: 2026-07-06
type: quick
status: complete
---

# Summary: capsule-addon-fluxcd PASS + Keycloak IdP POC live

Both objectives shipped and live-verified on 2026-07-06 (commits `ef50314` +
`0b8052d` + records commit).

## (a) capsule-addon-fluxcd → PASS

Settled permanently in the ADR-008 addendum (2026-07-06); the v0.19
ADDON-01/02 parking-lot item is resolved. Decisive: the addon is a
same-cluster kubeconfig factory; hub-only Flux (ADR-004) can never consume its
output, and the P27 impersonation pattern already delivers "tenants deploy via
Flux into their tenant spaces." Also corrected ADR-008's mischaracterization
of the addon.

## (b)+(c) Keycloak 26.6.4 + operator + Postgres, GitOps end-to-end

Delivered as a third tenant-shaped POC on spoke-capsule (`keycloak` Tenant —
the only namespace-creation path Capsule's webhook admits; dry-run verified).
Vendored official operator manifests @26.6.4; 3-K DAG (tenant → spoke → app);
imperative non-rotating `keycloak-db-secret` via
`scripts/poc/keycloak/create-secrets.sh`; realm `karyon` pre-shaped for the
OIDC follow-up (flat groups, full.path OFF, PKCE `kubectl` client, users
alice/bob without credentials); CapsuleConfiguration userGroups 3→7.

## Live verification evidence (2026-07-06)

- Convergence chain: postgres Ready → `poc-keycloak-spoke` Ready=True →
  `poc-keycloak-app` applied → Keycloak CR Ready=True →
  `keycloak-initial-admin` Secret auto-created → `karyon` realm import Done.
- `tests/bats/keycloak-03-live.bats`: 9/9 GREEN, including the OIDC discovery
  round-trip (`/realms/karyon/.well-known/openid-configuration` serves with
  `code_challenge_methods_supported: [plain, S256]`) and the expected GTR
  hello-world seed in the keycloak namespace.
- Live `userGroups` = the full 7-entry list (git → live propagation works).
- No perturbation: all 12 hub Flux Kustomizations Ready; tenants
  alpha/bravo/keycloak all Active; demo-01 + demo-02 live suites 7/7 GREEN
  (platform-owner sees all, tenant-owners still see ONLY their own tenant
  through capsule-proxy with the third tenant present).
- Static gates: 48/48 static bats suites green (2 new keycloak suites);
  markdownlint 0 errors; gitleaks clean.

## Residual (parked in PROJECT.md)

- OIDC wiring in front of capsule-proxy (TLS + pinned issuer + retrofittable
  apiserver flags) — fully designed in `docs/poc-keycloak.md` §Follow-up.
- Realm day-2 lifecycle (import-once semantics).
- Accepted side effects documented in `docs/poc-keycloak.md` §Known side
  effects (GTR seed in keycloak ns; destroy-poc 90s cascade warn; third row
  in the demo Act 2 tenant list — runbook updated).
