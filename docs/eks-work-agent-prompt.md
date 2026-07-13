# Work-agent handoff prompt: Keycloak → Capsule → Headlamp OIDC tenancy on EKS

status: Active (2026-07-13)
audience: a work-environment agent (or engineer) executing the EKS build-out.
This document IS the handoff prompt — point the agent at this file verbatim,
or paste its contents as the task prompt.
companion: `eks-identity-adoption-brief.md` (trust model + adoption sequence),
`eks-platform-handoff.md` (component-by-component EKS translation),
`capsule-portable-setup-guide.md` (production tenant/RBAC model).

## Objective

Translate the `karyon` k3d proof of concept into a production EKS deployment:

1. A human logs into Headlamp via Keycloak OIDC (Authorization Code + PKCE).
2. Headlamp sends the user's token to capsule-proxy, not the API server.
3. capsule-proxy authenticates the token via Kubernetes TokenReview.
4. The EKS API server validates it against its associated Keycloak OIDC
   provider.
5. Capsule Tenant ownership + RBAC + proxy filtering restrict each user to
   their tenants' resources.
6. IAM authentication remains available for platform/cloud operations.

karyon is the reference implementation, not a production blueprint: preserve
the identity and tenancy behavior; deliberately replace lab networking,
certificates, storage, bootstrap, and GitOps choices.

Repo access: this document lives in the karyon repo, and all paths below are
relative to its root. If the executing agent does not have the repo, clone it
first.

Reference flow (lab-verified):

```text
Browser → Keycloak auth endpoint → Headlamp /oidc-callback
→ Headlamp attaches the user's token as bearer to capsule-proxy
→ capsule-proxy TokenReviews it against kube-apiserver
→ apiserver validates the Keycloak JWT offline (JWKS)
→ proxy forwards namespaced requests / filters cluster-scoped LISTs
```

Headlamp's in-cluster endpoint is redirected to capsule-proxy via
`KUBERNETES_SERVICE_HOST`/`KUBERNETES_SERVICE_PORT`; its service-account CA
volume is replaced with the CA that validates capsule-proxy. capsule-proxy has
zero OIDC config of its own. Keycloak participates only in login, refresh,
discovery, and key rotation — never per-request.

## Authorization model

Do not reduce this to "RBAC controls what users do; the proxy controls what
they see." Behavior is route-dependent:

- Ordinary proxied requests run under the user's identity; RBAC is
  authoritative.
- Some intercepted cluster-scoped reads execute under capsule-proxy's OWN
  privileged service account and are filtered afterward — for those routes,
  the proxy's permissions, Tenant selectors, and filter logic ARE the
  authorization boundary.
- Direct API-server and proxied access can therefore differ. Enumerate and
  test every intercepted route in the pinned proxy version.

## Read first, in order

1. `docs/eks-identity-adoption-brief.md` — the initial EKS handoff
2. `docs/eks-platform-handoff.md` — component-by-component translation
3. `docs/capsule-portable-setup-guide.md` — production tenant/RBAC model
4. `pocs/keycloak/` — operator CR, realm import, Postgres reference;
   `pocs/keycloak/app/realm-karyon.yaml` is authoritative for
   realm/client/mappers
5. `pocs/capsule/` and `pocs/headlamp/` — Capsule config, Tenants, proxy
   values, Headlamp wiring
6. `scripts/poc/keycloak/e2e-oidc-test.sh` — executable spec of the chain; do
   NOT run unchanged (it creates a direct-grant client and writes credentials)
7. `docs/tenant-access.md` — operator runbook and personas
8. Upstream docs + source for the exact pinned Capsule and capsule-proxy
   versions

PRECEDENCE: where this document differs from the karyon EKS docs — notably
`usernamePrefix` — this document supersedes them (the repo docs conflate
username and groups prefix defaults).

## Phase 0: freeze the identity contract

```text
keycloakBaseUrl     = https://sso.<domain>          # Keycloak CR spec.hostname.hostname
issuerUrl           = ${keycloakBaseUrl}/realms/<realm>   # what tokens carry as iss
eksClientId         = <client-id>
headlampCallbackUrl = https://headlamp.<domain>/oidc-callback
```

The CR hostname is the BASE URL, not the issuer; Keycloak derives `iss` per
realm. The issuer must be byte-identical in: token `iss`, the EKS
association's `issuerUrl`, Headlamp `-oidc-idp-issuer-url`, kubelogin
`--oidc-issuer-url`. Do not create the EKS association until DNS, TLS,
hostname, and issuer are settled — changing it means disassociate +
re-associate.

## OIDC client

Initial design (document any deviation):

- One shared PUBLIC client for kubectl and Headlamp (lab ID: `kubectl`; choose
  and freeze the production ID). Authorization Code enabled, PKCE S256
  required, no client secret, Direct Access Grants disabled.
- Register the exact Headlamp redirect URI and production web origins.
- The token presented to EKS must carry `eksClientId` in `aud`. Confirm
  whether the pinned Headlamp version forwards the ID token or access token,
  and configure/test the audience for THAT token type (access-token `aud`
  typically needs an explicit audience mapper).
- A separate Headlamp client is allowed only if documented and its forwarded
  token still carries the EKS client ID in `aud`.

## Claims and prefixes

Groups mapper: `oidc-group-membership-mapper`, `claim.name=groups`,
`full.path=false`. Groups are flat, top-level. (`full.path=true` emits
`/tenant-a`, which never equals `tenant-a` — Capsule matching is
exact-string.)

EKS association claims:

```text
usernameClaim  = preferred_username
usernamePrefix = -            # the explicit disable value; do NOT omit —
                              # omitted + non-email claim defaults to issuerurl#
groupsClaim    = groups
groupsPrefix   = omitted/empty  # do NOT use "-" here; groups have no special
                                # dash handling and would be prefixed with "-"
```

If a prefix is deliberately introduced, mirror the exact resulting strings
into every Tenant owner and Capsule group-scope entry.

Onboarding a tenant group requires coordinated updates (verify field names
against the pinned Capsule release; don't carry deprecated fields forward):

1. the Keycloak group;
2. `CapsuleConfiguration.spec.userGroups` (or its successor);
3. the matching `Tenant.spec.owners[]` entry.

A Group owner missing from the Capsule user scope is silently inert.

## Versions

Pin exact versions/digests for Keycloak + operator, Capsule, capsule-proxy,
Headlamp, cert-manager, and all charts. Treat karyon's pins as behavioral
evidence, not automatic choices; if you change one, document the behavioral
and security deltas and rerun the full authorization matrix. Render every
chart and retain the rendered RBAC for review.

## EKS identity-provider association

```text
aws eks associate-identity-provider-config
  issuerUrl=<issuer> clientId=<eksClientId>
  usernameClaim=preferred_username usernamePrefix=-
  groupsClaim=groups   # groupsPrefix omitted
```

Constraints: issuer must be public-CA HTTPS (the lab's private-CA design
cannot be carried over); association/disassociation are slow — wait for
ACTIVE; one OIDC association per cluster; IAM coexists — keep break-glass
access on EKS access entries.

Immediately after ACTIVE: decode a real token and inspect
`iss`/`aud`/`preferred_username`/`groups`/`exp`, then
`kubectl --token=<jwt> auth whoami` and confirm the expected bare username and
groups.

## Keycloak deployment

- `spec.hostname.hostname` = full external base URL. When behind an ALB,
  configure forwarded-header handling (`spec.proxy.headers: xforwarded` on
  Keycloak 26-era operators — verify the field against the pinned CRD); ensure
  the ingress OVERWRITES client-supplied `X-Forwarded-*` and that the proxy
  can't be bypassed. `hostname.strict` adds little once a full fixed hostname
  URL is set.
- HTTP listener: enable only if TLS intentionally terminates at the LB and the
  internal hop is designed as HTTP. kcadm does not strictly require it — but
  the lab's in-pod recipe (`tenant-access.md` §3, `setup-headlamp.sh`)
  hardcodes `http://localhost:8080`; if HTTP is disabled, adapt it to the
  HTTPS listener with a truststore.
- Resolve and document: replica count; Infinispan/JGroups distributed cache
  when replicas ≥ 2 (karyon ran 1 and has ZERO cache guidance); DB engine, TLS
  verification, pooling, backup/failover; `/admin` restriction; access-token
  lifetime; SSO session idle/max; refresh policy; group-change propagation;
  key rotation and JWKS caching; login/refresh availability requirements. The
  lab sets NO token/session lifetimes — Keycloak defaults silently govern
  kubelogin cache validity and Headlamp sessions. Set them deliberately.
- RDS MySQL, if selected: RDS CA bundle + server-cert verification
  (`--db-tls-mode=verify-server`); pool max-lifetime < `wait_timeout`;
  `sql_generate_invisible_primary_key=OFF` where applicable.
- Realm import is import-once, not reconciliation. Include known production
  redirect URIs and mappers in the initial import. Do not keep the bootstrap
  admin as the day-two identity — define a least-privileged, auditable,
  idempotent Admin API process for later client/group/mapper changes.

## Capsule

Preserve: exact group→owner matching; generated per-namespace RoleBindings;
separate platform-owner vs tenant-developer personas; explicit namespace
ownership; explicit handling of cluster-scoped resources.

- Keep the namespaces webhook `failurePolicy: Fail` (see
  `docs/rca/capsule-namespace-webhook-deadlock.md` — the fail-open variant
  produces labeled-but-unowned namespaces that wedge unrecoverably).
- The lab leaves the other ~13 hooks at Ignore, i.e. pod admission FAILS OPEN
  when the controller is down (observed twice). Choose and document the
  availability-vs-enforcement posture for every webhook.
- Reconcile Tenant CRs before the namespaces that depend on them.
- Do not reproduce the k3d hub→spoke Flux topology (kubeconfig Secrets, mirror
  scripts); adapt reconciliation ownership, service accounts, and ordering to
  the target GitOps topology (single-cluster: per-tenant `serviceAccountName`
  impersonation).

## capsule-proxy

- In-cluster Headlamp path: proxy serves TLS on its Service DNS name with a
  ROTATING cert (cert-manager or equivalent); Headlamp gets the matching CA
  bundle; rotation of both must be reconciled safely. Do not copy the lab
  chart's non-rotating certgen Job.
- External exposure (if kubectl users need it): choose NLB/ALB deliberately
  and document where TLS terminates. An ACM cert on the LB does not solve the
  in-cluster pod-serving TLS path.

## Headlamp

Keep: `KUBERNETES_SERVICE_HOST`/`KUBERNETES_SERVICE_PORT` override to
capsule-proxy; projected volume replacing the SA CA with the proxy CA;
zero-RBAC service account; `automountServiceAccountToken: false`. The pod must
hold no credential that can bypass the user's identity.

Drop (k3d-only workarounds) unless independently justified: `hostNetwork`,
`ClusterFirstWithHostNet`, custom `SSL_CERT_FILE`, `strategy: Recreate`.

## Token-only kubeconfigs

User kubeconfigs pointed at the proxy must use bearer/exec auth only — no
`client-certificate-data`/`client-key-data`. The proxy's TLS layer may
evaluate client certs at the handshake before the bearer is read: an untrusted
cert can fail the handshake despite a valid token, and a cert trusted by the
proxy's client CA interacts with `authPreferredTypes`. Test with a clean
token-only kubeconfig; separately test and document the proxy's `clientAuth` /
`authPreferredTypes` behavior. Do not assume every client cert is rejected.

## Mandatory capsule-proxy security review

In the reference pin (0.12.0), `GET /api/v1/nodes` is fetched under the
proxy's OWN privileged SA and filtered by Tenant node selectors — an empty
selector can match all nodes, exposing node data to users whose direct RBAC
denies nodes.

Before exposing the proxy: pin the version; render and review its ClusterRole;
inspect the source for ALL intercepted paths; classify each as user-identity
vs proxy-SA; determine empty/missing/overlapping selector behavior; exercise
real requests (chart inspection alone is insufficient); document a disposition
for every unacceptable route (narrow the proxy's permissions, configure/patch,
upgrade, add external authz, or don't expose it). Apply this to every
intercepted cluster-scoped resource, not just nodes. `auth can-i` is not
sufficient where the proxy substitutes its own identity — the actual request
result is authoritative.

## Verification harness

Port the ASSERTIONS of `scripts/poc/keycloak/e2e-oidc-test.sh`, not its
bootstrap: no direct-grant client, no password grant, no permanent test
passwords without a documented exception, no tokens/secrets/kubeconfigs in
git, no full JWTs in logs. The harness must fail closed: an unexpected success
is a failure.

Personas (karyon's reference tenants are alpha/bravo; substitute yours):
platform owner; tenant-A dev; tenant-B dev; authenticated user with no tenant;
invalid, expired, and wrong-audience tokens.

Test at minimum:

- Identity contract: `iss` byte-equal to the association; `aud` contains the
  client ID; bare unprefixed username and flat groups; `auth whoami` matches.
- Browser flow: real Headlamp PKCE login over HTTPS; no client secret;
  requests run as the user, not the SA; login/refresh/logout/expiry.
- Direct vs proxied, per persona: namespace visibility (tenant users see only
  their tenants; platform owner sees authorized tenants but not `kube-system`
  unless intended; ownerless user sees nothing; no discovery via alternate API
  forms, field selectors, watches, pagination, or raw endpoints).
- RBAC verbs independently: get/list/watch/create/update/patch/delete plus
  `pods/log` and `pods/exec` — do not infer mutation safety from filtered
  LISTs.
- Cluster-scoped matrix: every intercepted path from the proxy review, through
  both the direct API and the proxy (for nodes: both `auth can-i` and a real
  `get nodes`, both routes).
- Operational: watches, logs, exec; token refresh; group changes taking effect
  on the next token; proxy and Keycloak outages; cert and signing-key
  rotation.

## Deliverables

1. Decision record: canonical URLs; version/digest pins; client design and
   forwarded-token type; TLS termination per hop; Keycloak replica/cache and
   DB design; token/session lifetimes; GitOps ownership and ordering; proxy
   exposure model and intercepted-route/privilege analysis; webhook postures;
   rollback strategy.
2. Keycloak deployment: operator install, production CR, DB + TLS integration,
   realm import with production clients/mappers/redirect URIs, ingress, admin
   restrictions, day-two admin process. No secrets in git.
3. Capsule + capsule-proxy + Headlamp: Capsule config, Tenant CRs and RBAC,
   webhook config and ordering, proxy values with reviewed rendered RBAC,
   rotating proxy cert + CA distribution, Headlamp OIDC config and endpoint
   override, zero-RBAC tokenless SA, LB config if externally exposed.
4. The verification harness above, repeatable.
5. Runbooks: tenant onboarding/offboarding; group changes and token
   propagation; OIDC association replacement; Keycloak key rotation; proxy
   cert/CA rotation; Keycloak/proxy outage handling; break-glass IAM;
   rollback.

## Definition of done

- Browser PKCE login works with no client secret; Headlamp reaches Kubernetes
  only through capsule-proxy.
- EKS reports the expected bare username and flat groups.
- Tenant users can mutate only what RBAC permits and discover only what the
  proxy authorization review explicitly approved; direct and proxied behavior
  both tested; the nodes behavior has an explicit, verified disposition.
- No bootstrap admin, password-grant client, static test password, private
  key, kubeconfig, or bearer token is committed.
- All pins, open decisions, security assumptions, and rollback procedures are
  documented.
