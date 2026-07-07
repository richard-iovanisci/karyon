---
slug: tenant-ui-oidc
date: 2026-07-06
type: quick
status: complete
---

# Summary: Architecture docs + OIDC wiring + Headlamp tenant UI — live

All three asks delivered and live-verified.

## (a) Architecture doc + diagram

- `docs/architecture-flux-capsule-keycloak.md` — the three-layer pattern
  (GitOps / tenancy / identity) with inline mermaid, trust-boundary and port
  tables.
- `docs/diagrams/karyon-architecture.drawio` — 56-cell editable diagram with
  embedded official logos (CNCF artwork: Flux, Capsule, Keycloak, Headlamp,
  Kubernetes, PostgreSQL), self-contained (base64 SVGs), imports directly
  into app.diagrams.net / draw.io desktop / VS Code extension.

## (b) Access + administration runbook

`docs/tenant-access.md`: bootstrap sequence, Headlamp UI access, kubectl
OIDC (kubelogin), Keycloak 26 admin click-paths (users/groups/clients/PKCE/
mapper locations), kcadm scriptable patterns, the new-tenant identity triple,
code-server pattern (documented, parked), troubleshooting table.

## (c) Tenant UI + OIDC — LIVE

- Headlamp v0.43.0 (kubernetes-sigs; official successor to the archived
  kubernetes/dashboard) at `pocs/headlamp/`, zero-RBAC, endpoint overridden
  to capsule-proxy, `auth_type: oidc` verified live via the service proxy.
- OIDC chain wired end-to-end: pinned issuer https://localhost:31443
  (live-verified from host + node loopback), Keycloak TLS (imperative CA),
  socat forwarder, k3s apiserver flags (config.yaml retrofit, all 6 verified
  in the k3s log line), kubelogin v1.36.2 + ~/.karyon/oidc.kubeconfig.
- **Headless e2e proof** (`scripts/poc/keycloak/e2e-oidc-test.sh`): alice
  (capsule-platform-owners) lists namespaces through capsule-proxy with a
  real OIDC JWT → sees keycloak + tenant-alpha + tenant-bravo and NOT
  kube-system; bob (tenant-alpha-devs) → sees exactly tenant-alpha.
- Tier-3 OIDC Group owners added to alpha/bravo Tenant CRs + new-tenant.sh.
- Guards: keycloak-04-static (10 pins) + keycloak-05-live (6 checks, all
  green incl. the e2e chain); poc-mount index 7→8; all static suites green.

## Live-debug findings (fixed + guarded, recorded in PLAN.md)

Keycloak 26 profile requirements (lastName/emailVerified) → realm amended;
capsule-proxy CA secret identity (capsule-proxy/ca, NOT capsule-tls) → three
consumers fixed + bats pin; kubectl client-cert leakage into flag-driven
calls → dedicated kubeconfig + KUBECONFIG=/dev/null in the test.

## Residuals (parked in PROJECT.md)

Permanent Keycloak admin to replace the bootstrap one; Windows Trusted Root
import (manual); nftables kube-proxy would break the localhost-NodePort
issuer leg (guarded in apiserver-oidc.sh); imperative layer re-run after
cluster recreate; per-tenant code-server when actually needed.
