# Agent brief: adopting the Keycloak → Capsule → apiserver identity chain on EKS

Audience: an agent (or engineer) with access to the target EKS cluster, its
AWS/EKS configuration, and this repository. This brief explains how the
identity chain works in the karyon lab, exactly what changes on EKS, and the
order to build it in. The component-by-component detail lives in
[`eks-platform-handoff.md`](eks-platform-handoff.md); this doc is the
trust-model narrative plus the adoption sequence.

## 1. The trust model in one page

There is **no shared secret and no registration of the cluster inside
Keycloak**. Trust is unidirectional and anchored entirely in the apiserver's
OIDC configuration:

1. The kube-apiserver is told six things (lab reference:
   [`scripts/poc/keycloak/apiserver-oidc.sh`](../scripts/poc/keycloak/apiserver-oidc.sh)):
   the **issuer URL**, the expected **client id** (token `aud`), the
   **username claim** (`preferred_username`), the username **prefix**
   (disabled in the lab with `-`), the **groups claim** (`groups`), and a
   **CA** to TLS-verify the issuer.
2. The apiserver fetches `<issuer>/.well-known/openid-configuration` and the
   issuer's **JWKS** (public signing keys) over verified TLS.
3. Every request carrying `Authorization: Bearer <ID-token>` is validated
   **offline**: JWT signature against the JWKS, `iss` byte-equal to the
   configured issuer URL, `aud` contains the client id, token not expired.
   On success the apiserver maps `preferred_username` → username and the
   `groups` claim array → group strings. Keycloak is never called per
   request, and Keycloak never knows the cluster exists.

Authorization is a **separate layer** on top of that identity mapping:

- **Capsule** owns tenancy. Each `Tenant` CR names owners — in this pattern,
  OIDC **Group** owners (lab reference:
  [`pocs/capsule/spoke/tenant-crs/alpha.yaml`](../pocs/capsule/spoke/tenant-crs/alpha.yaml)):
  `capsule-platform-owners` (Capsule-default owner roles) and
  `tenant-alpha-devs` (explicit narrow `clusterRoles:
  [tenant-workload-editor]`). Capsule stamps the owner RBAC into tenant
  namespaces and its webhooks police namespace creation/labeling.
  `CapsuleConfiguration.spec.userGroups` must list every group that should
  be treated as a Capsule user (lab:
  [`pocs/capsule/spoke/config/capsuleconfig.yaml`](../pocs/capsule/spoke/config/capsuleconfig.yaml)).
- **capsule-proxy** is the tenant front door. Clients send their bearer
  token to the proxy, not the apiserver. The proxy resolves the caller with
  a TokenReview against the apiserver (which applies its OIDC
  authenticator), **filters cluster-scoped LISTs** (namespaces, tenants,
  ingress/storage classes…) down to what the caller's tenants own, and
  proxies everything else upstream under the same identity, where normal
  RBAC + Capsule webhooks enforce. Without the proxy, OIDC users still
  authenticate fine — they just cannot meaningfully `kubectl get namespaces`
  (cluster-scoped LIST is all-or-nothing in vanilla RBAC).

The two layers meet at exactly one seam — **the group string**. It must be
byte-identical in three places:

| Place | Lab value |
|---|---|
| Keycloak group (flat, no path) | `tenant-alpha-devs` |
| `groups` claim in the ID token | `tenant-alpha-devs` |
| Tenant CR owner + `userGroups` entry | `tenant-alpha-devs` |

The #1 silent breaker is Keycloak's Group Membership mapper defaulting
`full.path` to true, which emits `/tenant-alpha-devs` and breaks the match —
the lab pins `full.path: "false"` in the realm import
([`pocs/keycloak/app/realm-karyon.yaml`](../pocs/keycloak/app/realm-karyon.yaml)).

Client-side, everything shares one **public PKCE client** (`kubectl`):
kubectl via the kubelogin exec plugin
([`scripts/poc/keycloak/setup-oidc-kubectl.sh`](../scripts/poc/keycloak/setup-oidc-kubectl.sh))
and Headlamp (`-oidc-use-pkce=true`, endpoint overridden to capsule-proxy —
[`pocs/headlamp/headlamp.yaml`](../pocs/headlamp/headlamp.yaml)). Public +
PKCE means no client secret to manage anywhere.

## 2. What is different on EKS

You cannot set apiserver flags on EKS. The **only** genuinely different
piece is how the six values reach the apiserver — everything else in §1
transfers verbatim:

| Concern | karyon lab | EKS |
|---|---|---|
| Apiserver OIDC config | k3s `config.yaml` + container restart | one-shot `aws eks associate-identity-provider-config` (see [`eks-platform-handoff.md`](eks-platform-handoff.md) §"EKS OIDC") |
| Issuer URL | `https://localhost:31443/realms/karyon` (loopback trick) | one canonical public HTTPS URL, e.g. `https://sso.<domain>/realms/<realm>` — used identically by the association, kubelogin, Headlamp, and Keycloak's `hostname` |
| Issuer TLS | private CA + `oidc-ca-file` | **public CA required** (ACM/Let's Encrypt at the Keycloak ingress); there is no custom-CA option on the association |
| Change management | rerun the script | association is **slow (tens of minutes) and immutable** — disassociate + re-associate to change anything; one OIDC association per cluster |
| Username/groups prefixes | disabled (`oidc-username-prefix=-`) | leave `usernamePrefix`/`groupsPrefix` **empty** to preserve the byte-match, or mirror the prefix into every Tenant owner + `userGroups` entry — decide once |
| Admin/break-glass access | k3d admin kubeconfig | IAM authenticator / access entries coexist untouched — Tier 1 (cloud ops) stays on IAM; OIDC is for humans in Tiers 2–3 |
| Keycloak persistence | in-cluster Postgres (lab stand-in) | **RDS MySQL** via the operator's `db` settings (gotchas in the handoff §Keycloak operator) |
| capsule-proxy exposure | NodePort 30443 | NLB Service or ALB Ingress (YAML in the handoff appendix) |
| Headlamp shape | hostNetwork + Recreate (loopback-issuer hacks) | plain Deployment + ingress; keep the two transferable ideas — endpoint override to capsule-proxy and the projected proxy-CA volume |

## 3. Adoption sequence

Each step names its lab reference — read it before implementing.

1. **Keycloak reachable at its permanent public issuer URL** (operator +
   RDS MySQL + ACM-certified ingress). The issuer URL in the token `iss` is
   byte-compared by the apiserver: get the hostname settled **before** the
   association. Lab realm content to replicate:
   [`pocs/keycloak/app/realm-karyon.yaml`](../pocs/keycloak/app/realm-karyon.yaml)
   — flat groups, `groups` mapper with `full.path: "false"`, audience mapper
   `aud=kubectl`, public PKCE client with kubelogin redirect URIs
   (`http://localhost:8000`, `:18000`) plus Headlamp's callback.
   Keycloak 26 requires users to have `lastName` + `emailVerified: true` or
   logins fail with "Account is not fully set up".
2. **Associate the identity provider** (command + hard requirements:
   handoff §"EKS OIDC"). Verify with a raw token before touching anything
   else: get an ID token via a password grant against a test client (lab
   pattern: [`scripts/poc/keycloak/e2e-oidc-test.sh`](../scripts/poc/keycloak/e2e-oidc-test.sh)),
   then `kubectl --token=<jwt> auth whoami` — expect your
   `preferred_username` and the `groups` list back.
3. **Wire the group seam**: add the OIDC groups to
   `CapsuleConfiguration.spec.userGroups` and as `kind: Group` owners on the
   Tenant CRs. Never set `clusterRoles: []` on an owner — omit the field for
   Capsule defaults, or set an explicit narrow role (the lab's
   `tenant-workload-editor`:
   [`pocs/capsule/spoke/rbac/tenant-workload-editor.yaml`](../pocs/capsule/spoke/rbac/tenant-workload-editor.yaml)).
4. **Expose capsule-proxy** behind NLB/ALB and point tenant kubeconfigs at
   it (server = proxy URL, user = kubelogin exec plugin). The proxy needs
   zero OIDC-specific configuration — TokenReview does the work.
5. **Headlamp**: deploy with `KUBERNETES_SERVICE_HOST/PORT` overridden to
   the capsule-proxy Service, the proxy's serving CA projected over the
   pod's `ca.crt`, and the shared PKCE client. Lab manifest:
   [`pocs/headlamp/headlamp.yaml`](../pocs/headlamp/headlamp.yaml) — drop
   the hostNetwork/Recreate parts (loopback-issuer workarounds only).
6. **Prove the chain headlessly** before inviting users: port
   [`scripts/poc/keycloak/e2e-oidc-test.sh`](../scripts/poc/keycloak/e2e-oidc-test.sh)
   — token → proxy LIST → assert the platform-owner sees all tenants and a
   tenant dev sees only their own.

## 4. Gotcha checklist (each cost the lab real debugging time)

- `full.path` ON in the groups mapper → `/prefixed` groups → silent
  authorization failure (authentication still succeeds).
- Prefix drift between the association and the Tenant owners → same symptom.
- capsule-proxy's serving CA is the secret `capsule-proxy`, key `ca` — NOT
  `capsule-tls` (that is Capsule's webhook cert). Wrong secret → TLS errors
  at every proxy consumer.
- kubectl merges the active context's client certificate into requests even
  when `--token` is set — test with a clean kubeconfig (`KUBECONFIG=/dev/null`
  plus explicit `--server/--token/--certificate-authority`).
- Capsule's `namespaces` mutating webhook must keep `failurePolicy: Fail` —
  root cause and evidence:
  [`rca/capsule-namespace-webhook-deadlock.md`](rca/capsule-namespace-webhook-deadlock.md).
- Never seed bare Pods via `GlobalTenantResource` (permanent reconcile
  loop): [`adr/0008-capsule-multi-tenancy-graduation.md`](adr/0008-capsule-multi-tenancy-graduation.md).

## 5. Related reading in this repo

- [`eks-platform-handoff.md`](eks-platform-handoff.md) — the full work-environment
  translation (tier mapping, per-component keep-lists, RDS MySQL, build order,
  EKS wiring appendix).
- [`architecture-flux-capsule-keycloak.md`](architecture-flux-capsule-keycloak.md)
  — the whole-pattern architecture with trust boundaries and persona journeys.
- [`tenant-access.md`](tenant-access.md) — the user-facing access runbook
  (kubelogin, Headlamp, Keycloak admin recipes).
- [`poc-keycloak.md`](poc-keycloak.md) — why the Keycloak install looks the
  way it does.
