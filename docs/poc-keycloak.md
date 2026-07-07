# POC: Keycloak IdP on spoke-capsule

status: Active (quick task keycloak-idp-poc, 2026-07-06)
scope: Keycloak 26.6.4 + official operator + Postgres, GitOps-delivered onto
k3d-spoke-capsule as a third tenant-shaped POC. Provides realms/users/groups
management for the Capsule multi-tenancy POC. OIDC wiring (apiserver +
capsule-proxy + Headlamp tenant UI) is LIVE as of 2026-07-06 — see
§OIDC below and docs/tenant-access.md for the user-facing runbook.

## Why it looks the way it does

- **Placement — spoke-capsule, not the hub or a new spoke.** Co-located with
  its consumer (capsule-proxy), outside `task rebuild`'s scorched-earth path
  (P31 isolation → no rebuild-SLO impact), and reuses the existing
  `spoke-capsule-kubeconfig` delivery machinery. A dedicated IdP spoke was
  considered and rejected: a whole new cluster lifecycle surface for a POC.
- **A `keycloak` Tenant, not a plain namespace.** Capsule's namespaces
  mutating webhook (failurePolicy `Fail`, no namespaceSelector) plus global
  `forceTenantPrefix: true` denies namespace creation for EVERY identity —
  including cluster-admin (dry-run verified 2026-07-06). The only sanctioned
  path is a tenant owner creating a `capsule.clastix.io/tenant`-labeled
  namespace. So the IdP is an **unconstrained platform tenant**: no quotas, no
  limitRanges, no containerRegistries (quay.io images must pull).
- **Vendored operator manifests, not Helm.** The official operator ships as
  raw manifests; the hub's kustomize-controller runs `--no-remote-bases=true`,
  so the three upstream files are vendored verbatim under
  `pocs/keycloak/spoke/operator/vendored/` pinned to tag **26.6.4**.
- **Three outer Kustomizations** (mirrors the capsule DAG lessons):
  `poc-keycloak-tenant` (Tenant CR; D-11-07: Tenant before labeled namespace)
  → `poc-keycloak-spoke` (namespace + CRDs + operator + Postgres; wait: true)
  → `poc-keycloak-app` (Keycloak CR + realm import; never races CRD
  establishment). All spoke-targeted with the full P18 kubeConfig block +
  P27 `serviceAccountName: flux-reconciler`. Keycloak depends on capsule,
  never the reverse.
- **Secrets are imperative** (repo policy: secrets never in git):
  `scripts/poc/keycloak/create-secrets.sh` creates `keycloak-db-secret` after
  Flux has created the namespace (the script cannot create it — see webhook
  note above). The operator auto-generates the admin login Secret.

## Install / bootstrap

```bash
# 1. Push to main; hub Flux picks it up (or force it):
flux --context k3d-hub-flux reconcile kustomization flux-system --with-source

# 2. Watch the three outer Ks (spoke stays not-ready until step 3 — expected):
flux --context k3d-hub-flux get kustomization -n flux-system | grep keycloak

# 3. Bootstrap the DB credential (idempotent, non-rotating):
bash scripts/poc/keycloak/create-secrets.sh

# 4. Wait for Keycloak (operator startupProbe allows ~10 min cold boot):
kubectl --context k3d-spoke-capsule -n keycloak get keycloak keycloak -w
```

## Access the admin UI

```bash
# Admin credentials (operator-generated):
kubectl --context k3d-spoke-capsule -n keycloak get secret keycloak-initial-admin \
  -o jsonpath='{.data.username}' | base64 -d; echo
kubectl --context k3d-spoke-capsule -n keycloak get secret keycloak-initial-admin \
  -o jsonpath='{.data.password}' | base64 -d; echo

# UI — port-forward (spoke-capsule's k3d LB has no free published host port;
# 30443 belongs to capsule-proxy and new host ports need a cluster recreate):
kubectl --context k3d-spoke-capsule -n keycloak port-forward svc/keycloak-service 8080:8080
# → http://localhost:8080  (realm "karyon" is pre-imported)
```

## What the `karyon` realm ships

| Object | Value | Why |
|---|---|---|
| Groups | `capsule-users`, `capsule-platform-owners`, `tenant-alpha-devs`, `tenant-bravo-devs` | Flat names; `capsule-platform-owners` matches the existing Group owner on Tenants alpha/bravo/keycloak byte-for-byte; all four are in CapsuleConfiguration `userGroups` |
| Client `kubectl` | public, PKCE S256, redirect `http://localhost:8000` + `:18000` | kubelogin (`kubectl oidc-login`) contract |
| Mapper `groups` | Group Membership, claim `groups`, **full path OFF** | Default (ON) emits `/capsule-platform-owners` and silently breaks Capsule's exact-string owner match |
| Mapper `audience-kubectl` | aud `kubectl` | Needed if apiserver OIDC later uses structured AuthenticationConfiguration audiences |
| Users | `alice` (platform owner), `bob` (alpha dev) — **no credentials** | Set passwords in the admin UI; credentials never land in git |

Realm import is **import-once**: the operator creates the realm if absent and
never updates/deletes it. Day-2 realm changes happen in the admin UI (or
delete + recreate the realm — destructive: wipes its users/sessions).

## Known side effects (accepted)

- The match-all `GlobalTenantResource hello-world-seeded` seeds its
  Deployment + Service into the `keycloak` namespace too — harmless, and a
  live demo of D-13-11. `keycloak-03-live.bats` pins it as expected behavior.
- `kubectl get tenants` (platform-owner view, demo Act 2) now shows a third
  row: `keycloak`. The runbook's expected output includes it.
- `scripts/poc/capsule/destroy-poc.sh` (tenant-cascade path) deletes only
  tenants alpha/bravo but polls ALL tenant-labeled namespaces — the keycloak
  namespace makes that poll exhaust its 90s wait with a warning (non-fatal).
  At the poll's 60s mark it also force-clears PVC finalizers in every
  surviving tenant-labeled namespace, which touches the live postgres PVC
  here (the pvc-protection finalizer is controller-restored, so effectively
  harmless — but be aware if you run the capsule teardown with Keycloak up).
  `--full` teardown deletes the whole cluster, keycloak included.
- `scripts/preflight.sh` POC-04 strict check fails while the POC cluster is
  up (its own serverlb legitimately binds host port 30443, and the check
  cannot tell it from a squatter) — this blocks `task deploy-examples` /
  full preflight runs during POC coexistence. Pre-existing lab defect,
  tracked in the PROJECT.md parking lot; not keycloak-specific.

## OIDC in front of capsule-proxy — WIRED (2026-07-06, tenant-ui-oidc quick task)

The wiring is LIVE: issuer `https://localhost:31443/realms/karyon` (pinned;
`host.k3d.internal` turned out to be NXDOMAIN in this lab — the plan below was
amended by live verification), apiserver OIDC flags applied via the k3s
config.yaml retrofit, Headlamp serving tenant-scoped views, and the whole
chain proven headlessly by `scripts/poc/keycloak/e2e-oidc-test.sh` (alice sees
all tenants; bob sees only alpha). User-facing instructions:
`docs/tenant-access.md`. Guards: `tests/bats/keycloak-04-static-oidc-ui.bats`
and `keycloak-05-live-oidc.bats`. The original design notes (amended):

1. **TLS + pinned issuer** — `create-tls.sh` (CA at `~/.karyon/oidc-pki`),
   Keycloak CR `http.tlsSecret` + `hostname: https://localhost:31443`, the
   `keycloak-oidc` NodePort 31443, and the socat forwarder
   (`start-oidc-forwarder.sh`) for the host leg. The apiserver +
   hostNetwork pods reach the same URL via kube-proxy's localhost-NodePort
   path (live-verified; breaks under nftables kube-proxy — guard check is in
   `apiserver-oidc.sh`).
2. **Apiserver flags without recreate** — `apiserver-oidc.sh`: CA into the
   volume-backed `/var/lib/rancher/k3s/server/oidc/`, config.yaml into
   `/etc/rancher/k3s/`, `docker restart` (~60-90s spoke outage), flag
   verification via the k3s `Running kube-apiserver` log line. Both files
   die with `k3d cluster delete` — rerun after any recreate.
3. **capsule-proxy needs nothing.** It already sets
   `authPreferredTypes: BearerToken,...`; it TokenReviews bearer tokens against
   the apiserver, which resolves OIDC users/groups. Capsule then exact-matches
   Tenant owners — which is why the realm groups above are flat and already in
   `userGroups`.
4. **kubectl UX** — `setup-oidc-kubectl.sh` installs kubelogin v1.36.2 and
   writes `~/.karyon/oidc.kubeconfig` (server = capsule-proxy
   `https://127.0.0.1:30443`; the proxy CA is secret `capsule-proxy` key
   `ca` — NOT `capsule-tls`, which is Capsule's webhook cert).
5. **Tenant web UI** — Headlamp v0.43.0 in capsule-system (`pocs/headlamp/`),
   zero-RBAC, user-token passthrough to capsule-proxy, public PKCE client
   reuse. See `docs/tenant-access.md` §1.

## Related decisions

- `capsule-addon-fluxcd` evaluated 2026-07-06 → **PASS** (ADR-008 addendum):
  its kubeconfig-factory output lands on the Capsule cluster and is only
  consumable by a same-cluster Flux, which ADR-004 forbids; karyon's P27
  pattern already delivers tenant GitOps deploys.
- Cross-references: `docs/adr/0004-hub-only-flux-control-plane.md`,
  `docs/adr/0008-capsule-multi-tenancy-graduation.md`,
  `docs/poc-capsule.md`, `docs/capsule-portable-setup-guide.md`.
