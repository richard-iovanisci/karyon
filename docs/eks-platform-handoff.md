# Handoff: replicating the karyon pattern on a single-cluster EKS platform

status: Active (2026-07-07)
audience: an agent (or engineer) building a multi-tenant EKS platform —
Capsule + capsule-proxy + Keycloak + Headlamp — using this repo as the
reference implementation. This repo is public; every manifest, script, and
bats contract referenced below is readable.
companion: `architecture-flux-capsule-keycloak.md` (the pattern),
`capsule-on-eks.md` (earlier EKS translation notes), `tenant-access.md`
(user-facing runbook to adapt), `diagrams/eks-platform-sketch.drawio`
(customer-facing diagram of the target).

## Target environment (assumptions this doc is written against)

Single EKS cluster. Flux already installed and owned by a cloud-ops team
(Tier 1, full cluster-admin). Capsule + capsule-proxy installed in
collaboration between platform team (Tier 2) and cloud ops. Keycloak to be
self-hosted in-cluster with **RDS PostgreSQL** as the database (no in-cluster
persistent storage). Git host is GitLab (cosmetic difference — Flux
`GitRepository` sources work the same). Dev teams are the tenants. In
progress: capsule-proxy ↔ apiserver auth on EKS, and RDS provisioning.

## What dissolves, what transfers

karyon is hub-and-spoke; the target is single-cluster. That DELETES a whole
layer of karyon's complexity — do not carry it over:

| karyon machinery | Single-cluster verdict |
|---|---|
| Per-spoke kubeconfig Secrets, P18 `spec.kubeConfig` invariant, register scripts | **Gone.** Flux reconciles its own cluster natively |
| Split-path pattern (HelmReleases on hub, redirected installs — D-08-12) | **Gone.** HelmReleases apply directly |
| Kubeconfig Secret mirroring across namespaces | **Gone** |
| Socat forwarder / localhost issuer / hostNetwork Headlamp | **Gone.** Real DNS + TLS replace every lab networking hack (see §Headlamp) |
| Tenant Kustomizations impersonating a tenant-scoped SA (karyon's P27) | **Transfers, simplified**: same-cluster Flux Kustomization in the tenant namespace with `spec.serviceAccountName: <tenant-reconciler>` — the core of "tenants deploy through GitOps" |
| The tenancy contract (Tenant CRs, three tiers, group mapping, webhooks) | **Transfers ~verbatim** — this is the valuable part |

## Tier mapping

| Tier | karyon | Target |
|---|---|---|
| 1 | Talk-track only (no real cloud ops) | **Real**: cloud-ops team owns Flux + cluster-admin. Everything Tier 2 needs from them should be a one-time grant (Capsule install, OIDC association, ingress) — after that, tenant lifecycle must not require Tier 1 |
| 2 | `capsule-platform-owners` Group + `platform-owner` SA; full Tenant CRUD, `auth can-i '*' '*'` = no | Identical shape. The karyon `capsule-platform-owner` ClusterRole (`pocs/capsule/spoke/rbac/platform-owner.yaml`) is the reference ceiling |
| 3 | `tenant-<x>-devs` groups → Tenant `Group` owners with `tenant-workload-editor` (narrower than `edit`: secrets/PVCs read-only, no RBAC objects) | Identical. `pocs/capsule/spoke/rbac/tenant-workload-editor.yaml` is the reference |

## The five components — what to keep from karyon

### Capsule (tenancy engine)

- Reference Tenant CRs: `pocs/capsule/spoke/tenant-crs/{alpha,bravo}.yaml` —
  multi-owner shape (GitOps reconciler SA + human/OIDC owners + platform
  Group), quotas, LimitRanges, `containerRegistries` allowlists.
- **Webhook lesson (hard-won, twice)**: keep the `namespaces` webhook at the
  chart-default `failurePolicy: Fail`. karyon weakened it to `Ignore` and got
  an unrecoverable labeled-but-unowned namespace deadlock on cold bootstrap
  (ADR-008 addendum 2026-05-27). A second instance of the same class: any
  `Ignore` webhook silently skips its mutation while the controller is down —
  karyon lost `managed-by` labels on pods during a node restart, emptying the
  platform view through the proxy. On EKS with managed control plane this is
  less likely but the class is real: after any Capsule outage, workloads
  created during the gap may be missing Capsule's mutations.
- **GlobalTenantResource**: seed **controller-owned shapes only** (Deployment,
  StatefulSet) — never bare Pods/Jobs. Pod specs are immutable on update;
  GTR has no update-skip; a bare-Pod seed puts the controller into a
  permanent error loop (ADR-008 addendum 2026-07-06). Images must be
  fully-qualified when `containerRegistries` is set.
- `forceTenantPrefix` + owner-created labeled namespaces: on karyon, NOTHING
  (including cluster-admin) can create a namespace outside a tenant. Decide
  deliberately whether the platform wants that posture; it forced karyon to
  model even Keycloak as a platform tenant.

### capsule-proxy (the tenant front door)

- Its single load-bearing job: filter cluster-scoped LIST per tenant. It does
  NOT authenticate — it TokenReviews bearer tokens against the apiserver.
  **Consequence: the "capsule-proxy setup" work item is really an "apiserver
  OIDC" work item** (§EKS OIDC below). The proxy itself needed zero OIDC
  config in karyon (`authPreferredTypes: BearerToken,TLSCertificate`).
- Values reference: `pocs/capsule/proxy/helmrelease.yaml` (separate chart —
  NOT the operator umbrella `proxy.enabled`, which pins a stale proxy).
- Serve it behind ingress/NLB with a real certificate. karyon gotcha that
  generalizes: know exactly which Secret/CA the proxy serves — clients pin
  it. (In karyon the proxy CA lived in secret `capsule-proxy` key `ca`;
  a nearby `capsule-tls` secret was Capsule's *webhook* cert. Do not guess.)
- kubectl clients that carry a client certificate from another context will
  be REJECTED by the proxy TLS layer before bearer auth — give tenants a
  dedicated kubeconfig (see `scripts/poc/keycloak/setup-oidc-kubectl.sh`).

### Keycloak (identity)

- The realm design transfers **verbatim** and is the highest-value artifact:
  `pocs/keycloak/app/realm-karyon.yaml`. Invariants that make it glue-free:
  - Groups are FLAT; the client's Group Membership mapper has **Full group
    path OFF** (default ON emits `/group` and silently breaks Capsule's
    exact-string owner match). #1 silent breaker.
  - Every Group promoted to a Tenant owner must also be in
    `CapsuleConfiguration.spec.userGroups`.
  - Public PKCE client for kubectl/Headlamp (kubelogin redirects
    `http://localhost:8000` + `:18000`; Headlamp `<url>/oidc-callback`).
  - Keycloak 26 default user profile: users need **lastName + emailVerified**
    or logins fail with "Account is not fully set up".
- Realm import is **import-once** — day-2 users/groups/clients go through the
  admin console or `kcadm` (stateless exec pattern with in-pod bootstrap-admin
  env: `tenant-access.md` §3). Replace the bootstrap admin with a permanent
  one early.
- New-tenant identity contract (automate it in the tenant-provisioning path):
  Keycloak group `tenant-<x>-devs` + `userGroups` append + Tenant CR
  `{kind: Group, name: tenant-<x>-devs, clusterRoles: [tenant-workload-editor]}`.

### Keycloak operator (lifecycle)

- Official raw manifests, version-pinned and vendored if GitLab-side policy
  forbids remote bases (karyon vendored 26.6.4:
  `pocs/keycloak/spoke/operator/vendored/`). Operator watches only its own
  namespace; the CR, realm imports, and DB Secret must co-locate.
- **RDS is the operator's expected posture** — it never manages databases.
  karyon's in-cluster Postgres was a stand-in. Target shape in the
  `Keycloak` CR: `db.vendor: postgres`, `db.host: <rds-endpoint>`,
  `usernameSecret`/`passwordSecret` → a Secret sourced from your secret
  manager (ESO/Secrets Manager — karyon's "imperative script" pattern is the
  lab stand-in for that). Multi-AZ RDS also unlocks `instances: 2+` (karyon
  ran 1). TLS to RDS: set the JDBC params via `additionalOptions`
  (`db-url-properties: "?ssl=true&sslmode=require"` or the AWS RDS CA
  bundle in a truststore) — decide with your DBA posture.
- Keycloak itself behind ingress with a **pinned hostname**
  (`spec.hostname.hostname: https://sso.<domain>`) — the issuer string is
  load-bearing everywhere (next section).

### Headlamp (tenant UI)

- kubernetes-sigs; the official successor to the archived
  kubernetes/dashboard, and Capsule documents this exact integration.
  Reference Deployment: `pocs/headlamp/headlamp.yaml`, minus the lab hacks:
  - **Keep**: zero-RBAC ServiceAccount (`automountServiceAccountToken:
    false` + projected token volume), endpoint override
    `KUBERNETES_SERVICE_HOST=capsule-proxy.capsule-system.svc` /
    `KUBERNETES_SERVICE_PORT=9001`, proxy CA projected as the pod's
    `ca.crt`, `-oidc-use-pkce=true` with the shared public client (token
    `aud` stays the one the apiserver trusts — no audience gymnastics).
  - **Drop**: `hostNetwork` + `ClusterFirstWithHostNet` + `SSL_CERT_FILE`
    CA ConfigMap — those existed ONLY because the lab issuer lived on node
    loopback. With a real https issuer, a plain pod works. `strategy:
    Recreate` was a single-node/hostNetwork fix — unnecessary on EKS.
  - Serve behind ingress; register `https://headlamp.<domain>/oidc-callback`
    on the client; forward `X-Forwarded-Proto` or the callback scheme breaks.

## EKS OIDC — the one genuinely different piece

karyon set six `kube-apiserver` flags via a k3s config retrofit. **EKS has no
apiserver flags.** The equivalent is the EKS *OIDC identity provider
association* (one per cluster, coexists with IAM auth):

```bash
aws eks associate-identity-provider-config --cluster-name <cluster> \
  --oidc identityProviderConfigName=keycloak,\
issuerUrl=https://sso.<domain>/realms/<realm>,clientId=kubectl,\
usernameClaim=preferred_username,groupsClaim=groups
```

Hard requirements to design for NOW:

1. **Issuer must be public-CA https and reachable by the EKS control plane**
   — a real certificate (ACM/Let's Encrypt) on the Keycloak ingress; no
   self-signed/custom CA. This is the work-side twin of karyon's
   "issuer must be one byte-stable URL" lesson.
2. **Prefixes**: leave `usernamePrefix`/`groupsPrefix` EMPTY to preserve the
   byte-for-byte group ↔ Tenant-owner match. If org policy mandates prefixes
   (common to avoid IAM collisions), mirror the prefix in every Tenant owner
   name and in `userGroups` — pick once, it's painful to change.
3. Association takes tens of minutes to apply and cannot be edited in place
   (disassociate → re-associate). Get claims right the first time; test with
   `kubectl --token=<jwt> auth whoami` against the apiserver before wiring
   the proxy story.
4. Once the association is live, capsule-proxy works with zero changes —
   TokenReview resolves OIDC users/groups and Capsule matches owners. That
   is the full remaining scope of "capsule-proxy / apiserver setup".

## Flux add-on for Capsule (`capsule-addon-fluxcd`) — fresh call needed

karyon evaluated it and **passed** (ADR-008 addendum 2026-07-06) — but the
decisive blocker was hub-and-spoke topology: the addon generates tenant
kubeconfig Secrets consumable only by a *same-cluster* Flux. **On a single
EKS cluster that blocker does not exist** — the addon's design case is
exactly this topology (it automates per-tenant SA/token/kubeconfig creation
and routes tenant reconciliation *through capsule-proxy*).

Weigh fresh, with karyon's secondary findings intact: built against the
Capsule 0.7.2 Go API (verify against your Capsule version), ~1 release/year,
and a known chart bug (#118: default proxy-CA secretKey wrong → crashloop —
override the value). The no-addon alternative also works natively
single-cluster: per-tenant Flux Kustomization + `serviceAccountName`
impersonation (karyon's pattern minus the cross-cluster machinery). Addon
buys automation + proxy-scoped reconcile tokens; costs a young dependency in
the credential path and makes the proxy reconcile-load-bearing.

## Suggested build order (maps to the in-flight work)

1. RDS PostgreSQL + Keycloak operator + `Keycloak` CR + realm import
   (groups/client/mappers from `realm-karyon.yaml`, org-adjusted).
2. Keycloak ingress with real TLS → freeze the issuer URL.
3. EKS OIDC association (claims contract above) → verify with a raw JWT.
4. capsule-proxy ingress + tenant kubeconfig (kubelogin) → verify scoped
   LIST per group. karyon's headless proof pattern is reusable:
   `scripts/poc/keycloak/e2e-oidc-test.sh` (password-grant test client with
   an `aud` mapper — never enable direct grants on the production client).
5. Headlamp (EKS shape above) → the customer-visible win.
6. Tenant onboarding automation: Tenant CR + Keycloak group + `userGroups`
   in one pipeline (karyon's `new-tenant.sh` + identity triple as the spec).
7. Decide the addon question once 1–5 are stable.

## Executable contracts worth porting

karyon guards every load-bearing setting with bats (`tests/bats/keycloak-*`,
`capsule-install-*`, `tenants-*`, `rbac-*`, `proxy-*`, `seed-*`). Port the
*assertions* (mapper `full.path=false`, webhook `Fail`, owner shapes, GTR
no-bare-Pods, proxy LIST filtering) into whatever test harness the platform
uses — every one of them exists because its absence shipped a real defect
here.
