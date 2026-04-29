# Architecture Research — v0.19 Capsule Multi-Tenancy POC Integration

**Domain:** Local Kubernetes lab (k3d + WSL2 + Flux GitOps) — adding a multi-tenancy POC spoke to a 3-cluster hub-and-spoke topology
**Researched:** 2026-04-29
**Confidence:** HIGH (existing topology fully verified by reading committed files; Capsule + Flux integration verified against `clastix/flux2-capsule-multi-tenancy` reference + `projectcapsule.dev` docs via Context7 + WebFetch)

---

## Summary

The Capsule POC integrates as **a fourth k3d cluster (`spoke-capsule`)** that the existing hub-only Flux control plane reconciles into via the same `spec.kubeConfig.secretRef` pattern already used for `spoke-apps` and `spoke-ml`. ADR-004 (hub-only Flux) is preserved verbatim — Flux controllers run only on `hub-flux` and reach `spoke-capsule` over `https://k3d-spoke-capsule-server-0:6443`.

Three things are genuinely new:

1. **A second sentinel-guarded mount seam in the FLUX PATCH SURFACE.** The existing `# KARYON SPOKES MOUNT` lives in `clusters/hub-flux/flux-system/kustomization.yaml` (NOT `clusters/hub-flux/kustomization.yaml` as the prompt suggested — the bootstrap path is `clusters/hub-flux` and the patch surface that gets reconciled by Flux is the file inside `flux-system/`). v0.19 adds a parallel `# KARYON POC MOUNT` block in the same file that attaches `../pocs` so any future external POC drops in under `pocs/<poc-name>/` without touching the spokes mount.

2. **Outer reconciliation = identical to spokes.** `clusters/hub-flux/pocs/capsule.yaml` is a hub-side `Kustomization` with `spec.kubeConfig.secretRef.name: spoke-capsule-kubeconfig` pointing at `pocs/capsule/` in git. This is mechanically the same shape as `clusters/hub-flux/spokes/spoke-apps.yaml` (the proven SPOKE-04..06 contract).

3. **Inner reconciliation = hub-managed with tenant SA impersonation.** Two tenant Kustomizations live under `pocs/capsule/tenants/<tenant>/` on the hub. They use **both** `spec.kubeConfig.secretRef` (to reach `spoke-capsule` through `capsule-proxy`) **and** `spec.serviceAccountName` (to impersonate a tenant-owned ServiceAccount that Capsule has accepted as a Tenant Owner). This is the official `clastix/flux2-capsule-multi-tenancy` pattern; **option (c) from the question — selected over (a)** because (a) leaks cluster-admin to every tenant by reusing the spoke's `flux-reconciler` SA. Option (b) is rejected outright because it requires Flux on `spoke-capsule` and breaks ADR-004.

Cluster registration is a deliberately **separate** path: `scripts/register-poc-cluster.sh` mirrors `register-spokes-for-flux.sh` but is invoked manually and is **never** chained into `task rebuild`. `task rebuild` continues to terminate at the v1 health gate untouched. `task health-check` gains an opt-in `KARYON_POC_CHECK=capsule` env-flag path that adds `spoke-capsule` to its existing assertions; without the flag the script is byte-for-byte the same v1 contract.

The graduation ADR (suggested ADR-008 below) is the only path by which `spoke-capsule` can ever migrate into the default rebuild chain.

---

## Topology Diagram

```
                  ┌───────────────────────────────────────────────────────────┐
                  │                Single WSL2 Ubuntu 24.04                    │
                  │                Docker network: k8s-net                     │
                  │                                                            │
                  │  ┌────────────────────────────────────────────────────┐    │
                  │  │  k3d-hub-flux  (port 6443) — FLUX HUB ONLY         │    │
                  │  │  ┌─────────────────────────────────────────────┐   │    │
                  │  │  │ flux-system: source / kustomize / helm /    │   │    │
                  │  │  │ notification controllers                    │   │    │
                  │  │  │                                             │   │    │
                  │  │  │ Kustomizations (all hub-side):              │   │    │
                  │  │  │   spoke-apps           → spec.kubeConfig    │───┼────┼─→ k3d-spoke-apps  (6445)
                  │  │  │   spoke-ml             → spec.kubeConfig    │───┼────┼─→ k3d-spoke-ml    (6444, GPU)
                  │  │  │                                             │   │    │
                  │  │  │   poc-capsule          → spec.kubeConfig    │───┼──┐ │
                  │  │  │   tenant-alpha   → kubeConfig+SA impersonate│───┼──┤ │
                  │  │  │   tenant-bravo   → kubeConfig+SA impersonate│───┼──┤ │
                  │  │  └─────────────────────────────────────────────┘   │  │ │
                  │  │  Secrets (flux-system, NOT in git):                │  │ │
                  │  │    spoke-apps-kubeconfig                           │  │ │
                  │  │    spoke-ml-kubeconfig                             │  │ │
                  │  │    spoke-capsule-kubeconfig    (direct apiserver)  │  │ │
                  │  │    tenant-alpha-kubeconfig     (via capsule-proxy) │  │ │
                  │  │    tenant-bravo-kubeconfig     (via capsule-proxy) │  │ │
                  │  └────────────────────────────────────────────────────┘  │ │
                  │                                                          │ │
                  │  ┌────────────────────────────────────────────────────┐  │ │
                  │  │  k3d-spoke-capsule  (port 6446) — POC SPOKE        │  │ │
                  │  │  Persistent for the POC; NOT in `task rebuild`     │←─┼─┘ │
                  │  │                                                    │  │   │
                  │  │  capsule-system/                                   │  │   │
                  │  │    capsule-controller-manager      (HelmRelease)   │  │   │
                  │  │    capsule-proxy           :9001   (HelmRelease)   │  │   │
                  │  │    CapsuleConfiguration "default"                  │  │   │
                  │  │                                                    │  │   │
                  │  │  Tenants (capsule.clastix.io/v1beta2):             │  │   │
                  │  │    Tenant alpha  → owners[serviceaccount:tenant-   │  │   │
                  │  │                     alpha:gitops-reconciler]       │  │   │
                  │  │    Tenant bravo  → owners[serviceaccount:tenant-   │  │   │
                  │  │                     bravo:gitops-reconciler]       │  │   │
                  │  │                                                    │  │   │
                  │  │  Tenant namespaces (created by Capsule webhooks    │  │   │
                  │  │  when reconciler creates them):                    │  │   │
                  │  │    alpha-app1                                      │  │   │
                  │  │    bravo-app1                                      │  │   │
                  │  │                                                    │  │   │
                  │  │  flux-reconciler SA  (cluster-admin) — used for    │  │   │
                  │  │  the OUTER reconcile (Capsule install + Tenants)   │  │   │
                  │  └────────────────────────────────────────────────────┘  │   │
                  │                                                            │
                  │  ┌─────────────┐         ┌─────────────┐                   │
                  │  │k3d-spoke-ml │         │k3d-spoke-   │                   │
                  │  │  (6444)     │         │  apps (6445)│                   │
                  │  │  +GPU       │         │             │                   │
                  │  └─────────────┘         └─────────────┘                   │
                  └───────────────────────────────────────────────────────────┘

   Author's laptop (out-of-band, NOT through Flux):
      tenant-alpha-kubeconfig.yaml  (→ capsule-proxy NodePort, exec via kubectl)
      tenant-bravo-kubeconfig.yaml  (→ capsule-proxy NodePort, exec via kubectl)
```

**Key invariants:**

- **No Flux controllers on `spoke-capsule`.** ADR-004 unchanged.
- **Two reconciliation hops:** OUTER = hub Flux → spoke-capsule apiserver directly (cluster-admin via `flux-reconciler` SA, identical shape to existing spokes). INNER = hub Flux → capsule-proxy → tenant-scoped impersonated SA (the new pattern).
- **`spoke-capsule` is on `k8s-net`.** Same shared Docker bridge, same TLS-SAN trick (`k3d-spoke-capsule-server-0`), so the hub's `kustomize-controller` reaches it without DNS workarounds beyond the existing `task fix-dns`.

---

## KARYON POC MOUNT Shape

The existing `# KARYON SPOKES MOUNT` sentinel lives in `clusters/hub-flux/flux-system/kustomization.yaml` (the FLUX PATCH SURFACE), inserted by `scripts/register-spokes-for-flux.sh` via `ensure_hub_spokes_mount()`. v0.19 adds a parallel sentinel in the same file. The new mount points at `../pocs`, a sibling directory of `../spokes`.

**Final shape of `clusters/hub-flux/flux-system/kustomization.yaml` after v0.19:**

```yaml
# ──────────────────────────────────────────────────────────────────────────
# FLUX PATCH SURFACE
#
# This file IS the supported patch surface for the hub-flux bootstrap.
# Edits here SURVIVE re-bootstrap — add `patches:`, `configMapGenerator:`,
# `images:` etc. here to customize the 4 core controllers.
#
# Peer files in this directory — gotk-components.yaml, gotk-sync.yaml —
# are bootstrap-managed and WILL be overwritten by `flux bootstrap`.
# Do NOT hand-edit them.
#
# See: docs/flux-hub-spoke.md
# ──────────────────────────────────────────────────────────────────────────
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - gotk-components.yaml
  - gotk-sync.yaml
  # KARYON SPOKES MOUNT
  - ../spokes
  # KARYON POC MOUNT
  - ../pocs
```

**Why TWO sentinels not one:**

- `../spokes` is part of the v1 contract — every cluster created by `task create-clusters` registers through it. It must be present in the v1 default rebuild path.
- `../pocs` exists only when at least one POC is registered. It is *opt-in*. Putting POC mounts under `../spokes` would force every `task rebuild` to validate POC kustomizations, defeating the whole isolation goal.
- Two distinct sentinels also make it trivial to grep-audit which mount is being patched and which script owns it (`register-spokes-for-flux.sh` owns `# KARYON SPOKES MOUNT`; `register-poc-cluster.sh` owns `# KARYON POC MOUNT`).

**Sentinel-insertion algorithm** (port the `ensure_hub_spokes_mount()` awk pattern verbatim with the new sentinel and resource string):

```bash
# scripts/register-poc-cluster.sh — abridged
readonly POCS_SENTINEL="# KARYON POC MOUNT"
readonly POCS_RESOURCE="../pocs"
readonly HUB_KUST_FILE="${REPO_ROOT}/clusters/hub-flux/flux-system/kustomization.yaml"

# Same idempotent yq-then-awk pass as ensure_hub_spokes_mount(), but with
# POCS_SENTINEL/POCS_RESOURCE substituted. Re-runs are no-ops once the
# block is present.
```

**`clusters/hub-flux/pocs/kustomization.yaml`** (created on first POC registration):

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - capsule.yaml
```

**`clusters/hub-flux/pocs/capsule.yaml`** (the OUTER hub-side Kustomization — mechanically identical to `clusters/hub-flux/spokes/spoke-apps.yaml`):

```yaml
# clusters/hub-flux/pocs/capsule.yaml
# Flux v1 Kustomization — hub-flux's kustomize-controller reconciles
# pocs/capsule/ into k3d-spoke-capsule via the spoke-capsule-kubeconfig
# Secret (applied imperatively by scripts/register-poc-cluster.sh; never
# committed because it contains a bearer token).
#
# This is the OUTER reconcile: cluster-admin SA on spoke-capsule, used to
# install Capsule operator + capsule-proxy + Tenants + tenant SAs. The
# INNER reconcile (per-tenant Kustomizations under pocs/capsule/tenants/)
# uses spec.serviceAccountName impersonation instead.
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: poc-capsule
  namespace: flux-system
spec:
  interval: 5m
  path: ./pocs/capsule
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  kubeConfig:
    secretRef:
      name: spoke-capsule-kubeconfig
      key: value.yaml
```

---

## Repo Layout for `pocs/capsule/`

The hub reconciles `./pocs/capsule/` into `spoke-capsule` (one directory under git, three logical layers):

```
pocs/
└── capsule/
    ├── kustomization.yaml            # top-level — pulls in operator/ proxy/ config/ tenants/
    │
    ├── operator/                     # Capsule controller-manager (HelmRelease + repo)
    │   ├── kustomization.yaml
    │   ├── namespace.yaml            #   capsule-system
    │   ├── repository.yaml           #   HelmRepository projectcapsule
    │   └── release.yaml              #   HelmRelease capsule, chart capsule, version pinned
    │
    ├── proxy/                        # capsule-proxy (HelmRelease)
    │   ├── kustomization.yaml
    │   ├── repository.yaml           #   HelmRepository projectcapsule (or shared)
    │   ├── release.yaml              #   HelmRelease capsule-proxy
    │   │                             #     values: service.type=NodePort, nodePort=30443
    │   │                             #     (POC: no ingress; reachable via k3d host port)
    │   └── service-loadbalancer.yaml #   (optional) k3d port-publish for proxy
    │
    ├── config/                       # cluster-wide CapsuleConfiguration
    │   ├── kustomization.yaml
    │   └── capsuleconfiguration.yaml #   forceTenantPrefix=true, allowSAPromotion=true,
    │                                 #   userGroups=[capsule.clastix.io,
    │                                 #     system:serviceaccounts:tenant-alpha,
    │                                 #     system:serviceaccounts:tenant-bravo]
    │
    └── tenants/
        ├── kustomization.yaml        # pulls in alpha/ + bravo/
        │
        ├── alpha/
        │   ├── kustomization.yaml
        │   ├── namespace.yaml        #   tenant-alpha (the tenant's HOME ns; lives outside
        │   │                         #   Capsule-managed namespaces; holds the SA + GitRepo)
        │   ├── serviceaccount.yaml   #   gitops-reconciler SA in tenant-alpha
        │   ├── rbac.yaml             #   self-impersonation Role + RoleBinding (per
        │   │                         #   clastix/flux2-capsule-multi-tenancy reference)
        │   ├── tenant.yaml           #   capsule.clastix.io/v1beta2 Tenant
        │   │                         #     owners[ServiceAccount: tenant-alpha:
        │   │                         #     gitops-reconciler]
        │   ├── source.yaml           #   GitRepository in tenant-alpha namespace
        │   │                         #   (POC: same monorepo; tenant-owned repos future)
        │   └── kustomization-app.yaml#   Kustomization in tenant-alpha namespace, with
        │                             #   spec.kubeConfig (proxy) + spec.serviceAccountName
        │                             #   = gitops-reconciler. Path = ./pocs/capsule/
        │                             #   tenants/alpha/workload/
        │
        ├── alpha-workload/           # tenant alpha's actual app payload
        │   ├── kustomization.yaml
        │   ├── namespace.yaml        #   alpha-app1 (Capsule webhook validates: must
        │   │                         #   carry capsule.clastix.io/tenant=alpha label and
        │   │                         #   match forceTenantPrefix)
        │   └── deployment.yaml       #   trivial podinfo-equivalent
        │
        ├── bravo/                    # mirror of alpha/
        │   └── (same files, tenant-bravo)
        │
        └── bravo-workload/
            └── (same files, bravo-app1)
```

**Layout rationale:**

- **`operator/`, `proxy/`, `config/` are reconciled by the OUTER hub→spoke-capsule path** (cluster-admin SA), because Capsule install requires cluster-scoped CRD + webhook + ClusterRoleBinding ops that no tenant SA can do.
- **`tenants/<name>/` (the tenant control objects) are reconciled by the OUTER path too**, because creating a `Tenant` CR + a tenant-home Namespace + the tenant's `gitops-reconciler` SA requires admin authority on the cluster.
- **`tenants/<name>-workload/` (the app payload) is reconciled by the INNER tenant Kustomization** with `spec.serviceAccountName: gitops-reconciler` impersonation. This is where the multi-tenancy contract is actually exercised — the workload Kustomization can ONLY succeed if the tenant's Capsule-enforced RBAC allows it.
- **Tenant kubeconfigs for HUMAN owners are out-of-band entirely** (see Public-repo / secrets section). They are not produced by Flux; they are produced by `scripts/issue-tenant-kubeconfig.sh capsule alpha` and printed to stdout / written outside the repo.

**Concrete `tenants/alpha/kustomization-app.yaml`** (the INNER reconciliation — option (c)):

```yaml
# pocs/capsule/tenants/alpha/kustomization-app.yaml
# INNER reconciliation: hub-flux's kustomize-controller reconciles
# pocs/capsule/tenants/alpha-workload/ INTO spoke-capsule, but routed through
# capsule-proxy and impersonating the tenant-alpha gitops-reconciler SA.
# This is the official clastix/flux2-capsule-multi-tenancy pattern.
#
# spec.kubeConfig points at a Secret that contains a kubeconfig for
# https://capsule-proxy.capsule-system.svc:9001 (NOT the apiserver direct),
# bearer token = tenant-alpha:gitops-reconciler SA token.
#
# spec.serviceAccountName is the SAME SA — Flux impersonates the tenant SA
# while authenticated AS that same SA, the self-impersonation pattern that
# prevents privilege escalation back into hub-flux's reconciler identity.
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: tenant-alpha-app
  namespace: tenant-alpha            # NOTE: in tenant-home ns, NOT flux-system
spec:
  interval: 5m
  path: ./pocs/capsule/tenants/alpha-workload
  prune: true
  sourceRef:
    kind: GitRepository
    name: tenant-alpha               # also in tenant-alpha ns
  serviceAccountName: gitops-reconciler  # ← KEY FIELD: impersonation
  kubeConfig:                            # ← KEY FIELD: proxy not apiserver
    secretRef:
      name: tenant-alpha-proxy-kubeconfig
      key: value.yaml
```

**Why the INNER Kustomization itself lives in `tenant-alpha` namespace (not `flux-system`):** Flux's `spec.serviceAccountName` cannot cross-namespace reference. The Kustomization, the SA, the GitRepository, and the impersonation target ALL must live in the tenant's home namespace. This is the documented `flux2-multi-tenancy` lockdown contract and is exactly what makes tenants unable to escalate.

The OUTER Kustomization (`pocs/capsule/kustomization.yaml` reconciled by hub-flux) does the work of *creating* the tenant-alpha namespace + the SA + the GitRepository + the inner Kustomization itself. Once the inner Kustomization exists, hub-flux's `kustomize-controller` picks it up and starts the impersonated reconcile loop independently.

---

## Reconciliation Pattern Decision

**Selected: Option (c) — Hub-managed, tenant-impersonated**

The question listed three options. Here is the explicit evaluation:

| Option | Verdict | Reason |
|--------|---------|--------|
| (a) Hub-managed with tenant-scoped impersonation SA, but the SA itself reused from `flux-reconciler` | **REJECTED** | The existing `flux-reconciler` SA on every spoke is `cluster-admin`. Reusing it for tenants means tenants can `kubectl create clusterrolebinding ...`, defeating Capsule. |
| (b) Tenant-self-served with Flux on `spoke-capsule` | **REJECTED** | Direct ADR-004 violation. Out of scope. |
| (c) Hub-managed, tenant-impersonated via per-tenant SA + capsule-proxy | **SELECTED** | Matches the official `clastix/flux2-capsule-multi-tenancy` reference; preserves ADR-004; exercises the whole point of the POC (does Capsule actually contain a misbehaving tenant Kustomization?). |

**Justification for (c):**

1. **Hub-only Flux is the explicit ADR-004 invariant.** Option (b) is dismissed without further analysis.

2. **Option (a) is what's *easy* and what's *wrong*.** Reusing the existing `flux-reconciler` SA from the spoke registration script means every tenant Kustomization runs as cluster-admin on `spoke-capsule`. Capsule's webhooks would still validate Tenant CRs at admission, but the tenant's *workload* Kustomization (paths, namespaces, etc.) would have full cluster privilege. The whole POC question — "does Capsule actually isolate tenants?" — is unanswerable.

3. **Option (c) exercises the real failure mode.** The tenant Kustomization is constrained at three independent layers:
   - **Network/auth layer:** The kubeConfig points at `capsule-proxy:9001`, which (a) injects label-selector filtering on cluster-scoped LIST/GET calls so the tenant cannot enumerate other tenants' namespaces, and (b) terminates connections that don't carry a tenant-owned bearer token.
   - **Identity layer:** `spec.serviceAccountName: gitops-reconciler` makes Flux's apiserver calls execute AS that SA. Capsule's `CapsuleConfiguration.spec.userGroups` includes `system:serviceaccounts:tenant-alpha`, so the SA is recognized as a tenant member.
   - **Authorization layer:** Capsule's mutating + validating webhooks enforce tenant boundaries (forceTenantPrefix=true, namespace cap, allowed image registries, etc.). Anything the tenant Kustomization tries that violates the Tenant CR is rejected at webhook time.

4. **Multiple negative falsifiers fall out of (c) for free.** The v0.18 SPOKE-04 P18 silent-misroute pattern translates: a tenant Kustomization that *omits* `spec.serviceAccountName` would fall back to the default unprivileged SA Flux is configured with (`--default-service-account=gitops-reconciler` controller flag — see Build Order Phase 2), and Capsule's userGroups check would deny the request. A tenant Kustomization that points at the apiserver directly (bypassing capsule-proxy) cannot list cluster-scoped resources and visibly breaks. Both become first-class bats tests.

5. **Authoritative reference confirms the shape.** [`clastix/flux2-capsule-multi-tenancy/docs/ARCHITECTURE.md`](https://github.com/clastix/flux2-capsule-multi-tenancy/blob/main/docs/ARCHITECTURE.md) shows literally this pattern: GitRepository in tenant ns, Kustomization in tenant ns, `spec.kubeConfig` → `gitops-reconciler-kubeconfig` Secret pointing at capsule-proxy, `spec.serviceAccountName: gitops-reconciler`, and the tenant SA registered as a Tenant Owner with `kind: ServiceAccount`.

**One known sharp edge with (c):** Flux's `kustomize-controller` on `hub-flux` needs a working route to `https://capsule-proxy.capsule-system.svc:9001` from the *hub's* perspective. The capsule-proxy Service lives on `spoke-capsule`. Two possibilities, in order of POC preference:

- **(c1) NodePort + k3d host-port-publish.** capsule-proxy's Service is `type: NodePort`. k3d publishes that NodePort from `k3d-spoke-capsule-server-0` on `k8s-net`. The tenant kubeconfig's `server:` is `https://k3d-spoke-capsule-server-0:<nodePort>`. Same cross-cluster trick as the apiserver itself — known-working on `k8s-net`. **This is the recommended POC path.**

- **(c2) capsule-proxy on hub-flux instead.** Possible per Capsule docs, but (i) the milestone Out-of-Scope explicitly defers "Capsule installed on hub-flux itself", and (ii) it splits the POC across two clusters. Reject for v0.19.

---

## Tenant Onboarding Sequence

End-to-end "PR opens" → "tenant owner can `kubectl get pods`" — explicitly partitioned by who/what triggers each step.

| # | Event | Driver | Where |
|---|-------|--------|-------|
| 1 | Operator opens a PR adding `pocs/capsule/tenants/alpha/` (Tenant CR, SA, GitRepository, inner Kustomization) and `pocs/capsule/tenants/alpha-workload/` (initial app skeleton) | **Manual** (human authoring) | Local checkout, pushed to remote |
| 2 | PR merges to main | **Manual** (human review) | GitHub |
| 3 | hub-flux's `source-controller` polls the `flux-system` GitRepository (5m interval) and fetches the new commit | **Git-driven (Flux)** | hub-flux/flux-system |
| 4 | hub-flux's `kustomize-controller` reconciles the `flux-system` Kustomization, pulls in `clusters/hub-flux/pocs` via the KARYON POC MOUNT, and reconciles the `poc-capsule` Kustomization | **Git-driven (Flux)** | hub-flux/flux-system |
| 5 | The `poc-capsule` Kustomization (OUTER, with `spec.kubeConfig=spoke-capsule-kubeconfig`) reconciles `pocs/capsule/` against `spoke-capsule`, applying Capsule operator (already present, idempotent), capsule-proxy (already present), `CapsuleConfiguration` (already present), AND the new `tenant-alpha` namespace + SA + RBAC + Tenant CR + tenant GitRepository + inner Kustomization | **Git-driven (Flux)** | hub-flux → spoke-capsule (cluster-admin) |
| 6 | Capsule's controller observes the new `Tenant alpha` and registers the SA as a Tenant Owner | **In-cluster (Capsule controller)** | spoke-capsule |
| 7 | hub-flux's `kustomize-controller` discovers the new `Kustomization tenant-alpha-app` (in `tenant-alpha` ns on spoke-capsule) and starts reconciling it. spec.kubeConfig routes through capsule-proxy NodePort; spec.serviceAccountName impersonates `tenant-alpha:gitops-reconciler` | **Git-driven (Flux, INNER reconcile)** | hub-flux → capsule-proxy → spoke-capsule (impersonated) |
| 8 | The INNER reconcile applies `pocs/capsule/tenants/alpha-workload/` — creates `alpha-app1` namespace (validated by Capsule webhook: must carry tenant label, must satisfy forceTenantPrefix), then the workload deployment | **Git-driven (Flux)** | hub-flux → spoke-capsule (impersonated as tenant) |
| 9 | Tenant workload pods become Ready | **In-cluster (Kubernetes scheduler)** | spoke-capsule |
| 10 | Operator runs `bash scripts/issue-tenant-kubeconfig.sh capsule alpha > ~/.kube/karyon-tenant-alpha.yaml`. The script reads the `gitops-reconciler` SA token Secret from `tenant-alpha` ns on spoke-capsule, reads the capsule-proxy CA cert, builds a kubeconfig with `server: https://k3d-spoke-capsule-server-0:<proxy-nodePort>` and the bearer token | **Manual + Out-of-band** | Author's laptop |
| 11 | Operator hands the kubeconfig file to the tenant owner via `.env`-style out-of-band channel (NOT via git) | **Manual** | Out-of-band |
| 12 | Tenant owner runs `KUBECONFIG=~/.kube/karyon-tenant-alpha.yaml kubectl get pods -n alpha-app1` — request hits capsule-proxy:9001, capsule-proxy verifies the bearer token, applies labelSelector filtering, forwards to spoke-capsule apiserver, and returns only pods the tenant is authorized to see | **Live request (tenant)** | Tenant laptop / shell |

**Partition summary:**

- **Git-driven (Flux reconciles): 3, 4, 5, 7, 8.** Once the PR is merged, these happen without operator intervention.
- **In-cluster (Capsule + Kubernetes): 6, 9.** Background work; observable through `kubectl describe tenant alpha` and `kubectl get pods`.
- **Out-of-band (kubeconfig handoff): 10, 11.** The operator handing a tenant kubeconfig is deliberately *not* a Flux operation — it would require committing a bearer token to git or using an external secrets system, both deferred per milestone Out-of-Scope.
- **Manual (human actions): 1, 2, 10, 11, 12.** Authoring, review, kubeconfig issuance, kubeconfig delivery, tenant usage.

---

## Build Order

Phase-granular ordering with explicit "what becomes possible after" for each phase. This feeds directly into the v0.19 roadmap.

### Phase 1 — POC mount seam + spoke-capsule cluster + registration

**Lands:**
- `# KARYON POC MOUNT` sentinel + `../pocs` resource added to `clusters/hub-flux/flux-system/kustomization.yaml`
- Empty `clusters/hub-flux/pocs/kustomization.yaml` (just `resources: []`)
- `scripts/register-poc-cluster.sh` (sibling of `register-spokes-for-flux.sh`):
  - Creates `k3d-spoke-capsule` on port 6446, attached to `k8s-net`, with the same TLS-SAN nodefilter
  - Provisions `flux-reconciler` SA + cluster-admin CRB + legacy SA-token Secret on `spoke-capsule`
  - Builds the kubeconfig payload, applies it as Secret `flux-system/spoke-capsule-kubeconfig` on `hub-flux`
  - Writes `clusters/hub-flux/pocs/capsule.yaml` (OUTER Kustomization stub, path: `./pocs/capsule`)
  - Patches `pocs/kustomization.yaml` to reference `capsule.yaml`
  - Verifies the credential layer end-to-end (P18 silent-misroute proof: spoke-capsule node name appears, hub-flux node name does NOT)
- `scripts/destroy-poc-cluster.sh` (graceful teardown — must NOT delete the karyon CUDA image cache)
- bats tests: `tests/bats/poc-cluster-01-static.bats` (sentinel present, file shapes correct), `tests/bats/poc-cluster-02-live.bats` (P18 falsifier per spoke-capsule)

**Quality gate:** Running `bash scripts/register-poc-cluster.sh` is idempotent. Running `task rebuild` afterward leaves `spoke-capsule` and `pocs/capsule.yaml` UNTOUCHED — the rebuild chain destroys hub-flux + spoke-apps + spoke-ml only. (Verifiable: pre-rebuild `k3d cluster list | grep spoke-capsule` and post-rebuild same command must both succeed with the same container ID.)

**After this phase becomes possible:**
- The hub can reconcile arbitrary YAML at `pocs/capsule/` into `spoke-capsule`. The seam is open; the rest of the POC is "what do you put in `pocs/capsule/`?".
- `task health-check` can be flagged with `KARYON_POC_CHECK=capsule` to assert spoke-capsule is healthy without affecting default health.

### Phase 2 — Capsule operator + capsule-proxy + multi-tenancy lockdown

**Lands:**
- `pocs/capsule/operator/` HelmRelease for `projectcapsule/capsule` chart, pinned version
- `pocs/capsule/proxy/` HelmRelease for `capsule-proxy` chart, with `service.type: NodePort` and `nodePort: 30443` so k3d publishes it on `k3d-spoke-capsule-server-0:30443`
- `pocs/capsule/config/capsuleconfiguration.yaml` (`forceTenantPrefix: true`, `allowServiceAccountPromotion: true`, `userGroups` will be appended in Phase 3 per tenant)
- **Hub-flux multi-tenancy lockdown patch** in `clusters/hub-flux/flux-system/kustomization.yaml`:
  ```yaml
  patches:
  - patch: |
      - op: add
        path: /spec/template/spec/containers/0/args/-
        value: --no-cross-namespace-refs=true
      - op: add
        path: /spec/template/spec/containers/0/args/-
        value: --default-service-account=default
    target:
      kind: Deployment
      name: "(kustomize-controller|helm-controller)"
  ```
  This is the [Flux multi-tenancy documented lockdown pattern](https://fluxcd.io/flux/installation/configuration/multitenancy/). **Important:** this patch affects ALL of hub-flux, not just the POC. The default service account name is set to `default` so v1 spoke Kustomizations (which DO have `spec.kubeConfig` and execute against the spoke's cluster-admin SA) are unaffected; tenant Kustomizations that omit `spec.serviceAccountName` would fall back to `default` (no permissions) and visibly fail.
- bats tests: capsule-system pods Ready, capsule-proxy NodePort reachable from a temp pod on hub-flux (mirrors the existing `openssl_https_request` helper).

**After this phase becomes possible:**
- Tenants are creatable. Capsule's webhooks are live. Multi-tenancy lockdown is on.
- ADR-004 is preserved (still no Flux on spoke-capsule).

### Phase 3 — Two tenants with isolated namespaces

**Lands:**
- `pocs/capsule/tenants/alpha/` and `pocs/capsule/tenants/bravo/` per the layout above
- Each tenant: home namespace, `gitops-reconciler` SA, self-impersonation Role+RoleBinding, Tenant CR with `owners[ServiceAccount: <ns>:gitops-reconciler]`, GitRepository pointing at the karyon repo (POC: same monorepo), inner Kustomization with `spec.serviceAccountName + spec.kubeConfig`
- `pocs/capsule/tenants/alpha-workload/` + `bravo-workload/` with a trivial Deployment each
- `scripts/issue-tenant-kubeconfig.sh capsule <tenant>` (out-of-band kubeconfig minting tool — reads the SA token secret + the capsule-proxy CA, prints a kubeconfig)
- `pocs/capsule/proxy-kubeconfig-secrets/` — per-tenant kubeconfig Secrets for the *Flux INNER reconcile* (not for humans). Generated imperatively by `register-poc-cluster.sh` in Phase 3 mode, applied to tenant-alpha / tenant-bravo namespaces on spoke-capsule. Bearer tokens are NOT committed.
- bats tests: positive RBAC (alpha owner CAN create Pod in alpha-app1), negative RBAC (alpha owner CANNOT exec in bravo-app1), Capsule webhook denies an alpha-prefixed namespace from a bravo-impersonated request.

**After this phase becomes possible:**
- The first answerable question of the milestone: "does Capsule + Flux actually contain a misbehaving tenant Kustomization?" — answer driven by bats falsifiers.

### Phase 4 — Negative RBAC + capsule-proxy validation

**Lands:**
- bats: tenant-alpha kubeconfig listing all namespaces returns ONLY `tenant-alpha` + `alpha-app1` + (whatever Capsule allows globally — e.g., system namespaces are filtered too)
- bats: tenant-alpha kubeconfig attempting `kubectl create clusterrolebinding` returns Forbidden
- bats: tenant-alpha kubeconfig attempting to read a Secret in `bravo-app1` returns Forbidden (or NotFound — capsule-proxy filters)
- bats: tenant-alpha Kustomization containing a `clusterrolebinding.yaml` reconcile-fails at the impersonated apply step (NOT silently passes)

**After this phase becomes possible:**
- Documented evidence the POC actually isolates tenants. This is the empirical input to the graduation ADR.

### Phase 5 — Capsule webhook failure / teardown validation

**Lands:**
- `task fail-capsule-webhook` (test-only) that scales `capsule-controller-manager` to zero and verifies a tenant-prefix-violating Namespace is REJECTED at the apiserver (proves the webhook fail-policy)
- `task destroy-poc capsule` — uses `scripts/destroy-poc-cluster.sh` to tear down cluster + remove `clusters/hub-flux/pocs/capsule.yaml` from git. Importantly: leaves `# KARYON POC MOUNT` and `../pocs` mount in place so future POCs onboard cleanly.
- bats: post-`task destroy-poc capsule` health-check confirms hub-flux + spoke-apps + spoke-ml are still green.

**After this phase becomes possible:**
- Confidence the POC is *actually* removable without scarring the v1 lab. Reversibility is a graduation ADR input.

### Phase 6 — Graduation ADR + retro

**Lands:**
- ADR-008 (graduation): adopt Capsule into v0.20+ as default platform / defer / reject / pivot to another POC
- Decision codes for the milestone (D-17..D-N) recorded in PROJECT.md

**After this phase becomes possible:**
- Either v0.20 incorporates Capsule into `task rebuild` (and the POC mount is collapsed into a real default), or v0.20 picks the next experiment.

### Phase ordering rationale

```
Phase 1 ── must precede ──→ Phase 2  (no place to install Capsule until pocs/capsule/ is reconciled)
Phase 2 ── must precede ──→ Phase 3  (no Tenant CRD / no proxy until operator + proxy are running)
Phase 3 ── must precede ──→ Phase 4  (no tenants to test isolation against)
Phase 4 ── must precede ──→ Phase 5  (no point validating teardown until isolation is proven)
Phase 5 ── must precede ──→ Phase 6  (graduation cannot be informed without teardown evidence)
```

Phase 1 is the foundational gate — until the seam is in place AND `spoke-capsule` is registered AND the OUTER reconcile path is proven with the same P18 falsifier the spokes already use, nothing downstream is meaningful.

---

## Boundary with Existing System

For each existing v1 script, explicit awareness / non-awareness of `spoke-capsule`.

| Script / Task | Aware of `spoke-capsule`? | Modification required | Rationale |
|---------------|---------------------------|----------------------|-----------|
| `task preflight` / `scripts/preflight.sh` | **NO** (default) | None for default. Optional: PRE-15 reservation of port 6446 if `KARYON_POC_PRECHECK=capsule` is set. | Preflight is a fresh-host check; POC clusters are persistent and a fresh host won't have one yet. Adding port 6446 to the always-checked free-port list would cause spurious failures when the POC cluster IS running, which is the normal post-Phase-1 state. |
| `task create-clusters` / `scripts/create-clusters.sh` | **NO** | None | The whole point: `task rebuild` (which calls create-clusters) MUST NOT touch the POC cluster. POC creation is a separate manual `bash scripts/register-poc-cluster.sh capsule` invocation. |
| `task delete-clusters` / `scripts/delete-clusters.sh` | **NO** (default), explicit-opt-in | Add `KARYON_DELETE_POC=capsule` opt-in path that ALSO deletes spoke-capsule | A default destroy must NEVER tear down a POC — the operator might be mid-investigation. But a hard-reset path is desirable, off by default. |
| `task bootstrap-flux` / `scripts/bootstrap-flux.sh` | **NO** | None | Flux bootstrap is hub-only and runs once; it doesn't know spokes exist, let alone POC clusters. |
| `task register-spokes` / `scripts/register-spokes-for-flux.sh` | **NO** | None | Hardcoded list `register_spoke spoke-ml; register_spoke spoke-apps` stays as-is. POC registration is via `register-poc-cluster.sh`. |
| `task deploy-examples` / `scripts/deploy-examples.sh` | **NO** | None | Deploys the v1 examples (podinfo, gpu-smoke). POC examples are reconciled by Flux through the POC mount; no script trigger needed. |
| `task fix-dns` / `scripts/fix-coredns.sh` | **NO** (currently) — but should | Append `spoke-capsule` to the cluster list IF `KARYON_POC_FIXDNS=capsule` is set | k3d CoreDNS staleness affects ALL clusters on `k8s-net`. POC users will hit it. Opt-in flag only — default fix-dns continues to stop/start hub only. |
| `task health-check` / `scripts/health-check.sh` | **OPT-IN YES** | Wrap each spoke-capsule assertion in `if [[ "${KARYON_POC_CHECK:-}" == *capsule* ]]; then ...` | Default health-check is the v1 contract (3 clusters). Setting `KARYON_POC_CHECK=capsule` adds: spoke-capsule cluster exists; capsule-system pods Ready; capsule-proxy NodePort reachable; tenant-alpha + tenant-bravo Tenants both Ready; alpha-app1 + bravo-app1 namespaces exist with correct labels. |
| `task destroy` / `scripts/destroy.sh` | **NO** | None | destroy.sh wraps delete-clusters.sh which is hardcoded to the 3 v1 clusters. Forwarding `KARYON_DELETE_POC` is fine — but the default `task destroy` still deletes only v1 clusters. |
| `task rebuild` / `scripts/rebuild.sh` | **NO** — explicit invariant | None | This is the single hardest invariant. `task rebuild` must remain byte-for-byte equivalent to v1. The 190-second SLO is the v1 SLO; adding a Capsule install would balloon it. POC rebuild is a SEPARATE `bash scripts/destroy-poc-cluster.sh capsule && bash scripts/register-poc-cluster.sh capsule` invocation. |

**The single-line summary:** every entry in the table above has `register-spokes` and `register-poc-cluster` as siblings — never one calling the other.

**Public contract bats:** A new test `tests/bats/destroy-rebuild-poc-isolation.bats` verifies that:

1. After `bash scripts/register-poc-cluster.sh capsule`, `k3d cluster list` shows 4 clusters.
2. After `KARYON_REBUILD_APPROVED=yes bash scripts/rebuild.sh`, `k3d cluster list` shows 4 clusters and the pre-rebuild `docker inspect k3d-spoke-capsule-server-0 -f '{{.Id}}'` matches the post-rebuild value.

This is the empirical statement of "rebuild does NOT touch the POC".

---

## Public-repo / Secrets Layer

What lives where, post-v0.19:

| Artifact | Location | Public-repo? | Rationale |
|----------|----------|--------------|-----------|
| `clusters/hub-flux/pocs/capsule.yaml` (OUTER Kustomization with `secretRef.name: spoke-capsule-kubeconfig`) | git | **YES** | Same shape as `clusters/hub-flux/spokes/spoke-apps.yaml` — references a Secret name, doesn't contain the Secret. |
| `pocs/capsule/operator/release.yaml`, `proxy/release.yaml`, `config/capsuleconfiguration.yaml` | git | **YES** | Static manifests; no secret material. |
| `pocs/capsule/tenants/<name>/tenant.yaml` (Tenant CR), `serviceaccount.yaml`, `rbac.yaml`, `source.yaml` (GitRepository), `kustomization-app.yaml` (inner Kustomization) | git | **YES** | All declarative tenant infrastructure. |
| `pocs/capsule/tenants/<name>-workload/*.yaml` | git | **YES** | Tenant payload — POC examples committed. |
| `Secret flux-system/spoke-capsule-kubeconfig` (cluster-admin token for OUTER reconcile) | spoke-capsule cluster (applied imperatively by `register-poc-cluster.sh`) | **NO** — never committed | Same model as `spoke-apps-kubeconfig`. Bearer token never enters git. |
| `Secret tenant-<n>/tenant-<n>-proxy-kubeconfig` (tenant SA token + proxy server URL, for INNER reconcile) | spoke-capsule cluster (applied imperatively by `register-poc-cluster.sh` in Phase 3 mode) | **NO** — never committed | Bearer token + proxy CA. Generated from the SA's auto-rotated token Secret on spoke-capsule. |
| Tenant-owner kubeconfig file (for HUMAN tenant owner, i.e. `karyon-tenant-alpha.yaml`) | Author's laptop, then handed to tenant out-of-band | **NO** — never committed; never even produced by Flux | Generated by `scripts/issue-tenant-kubeconfig.sh capsule alpha`. The script reads the SA token from spoke-capsule, builds the kubeconfig, writes to stdout. The operator handles delivery (encrypted email, signed message, etc.). |
| Capsule version pin / proxy chart version | `.tool-versions` or values files | **YES** | Same model as k3s + CUDA pins. Reproducible. |
| `.env` keys for the POC (e.g., `KARYON_POC_CAPSULE_PROXY_NODEPORT=30443`) | gitignored `.env`; `.env.example` lists keys | **NO** for `.env`, **YES** for `.env.example` | Same contract as the existing GITHUB_OWNER / GITHUB_REPO / GITHUB_TOKEN. |

**Gitleaks behavior:** the existing `.gitleaks.toml` allowlist + native pre-commit hook + post-push CI scan apply unchanged. Adding `pocs/capsule/**/*.yaml` to the lint surface is automatic. New scripts that mint kubeconfigs (`issue-tenant-kubeconfig.sh`, `register-poc-cluster.sh` Phase 3 mode) follow the existing register-spokes convention: bearer tokens are passed via stdin to `kubectl create secret generic --dry-run=client | kubectl apply -f -`, never written to `--from-literal`, never tee'd to log files.

**One open contract decision (for the milestone team):** does `scripts/issue-tenant-kubeconfig.sh` emit to stdout only, or also write to a gitignored path like `.kubeconfigs/karyon-tenant-<name>.yaml`? Stdout-only is the safer default (operator pipes to their preferred location). Recommend stdout-only with a usage example in `docs/capsule-poc.md`.

---

## Suggested ADRs

The v0.19 milestone is expected to lock at least three architectural decisions. ADR numbering picks up where v0.18 ended (ADR-005).

| ADR | Title | Status at milestone open | Status at milestone close |
|-----|-------|--------------------------|---------------------------|
| **ADR-006** | POC mount pattern (`# KARYON POC MOUNT` sentinel + `pocs/<name>/` layout + `register-poc-cluster.sh` separate from `register-spokes-for-flux.sh`) | Proposed (Phase 1) | Accepted (Phase 1 closes) |
| **ADR-007** | Capsule POC cluster topology (spoke-capsule on k8s-net port 6446, hub-only Flux preserved, OUTER+INNER reconcile pattern with `spec.kubeConfig`+`spec.serviceAccountName`, capsule-proxy NodePort exposure) | Proposed (Phase 2) | Accepted (Phase 2 closes) |
| **ADR-008** | Capsule graduation decision (adopt as default platform, defer for v0.20, reject in favor of another approach, or pivot to a different multi-tenancy POC) | TBD (depends on Phase 4-5 evidence) | Accepted (Phase 6 closes the milestone) |

**Optional / conditional ADRs** (lock only if the underlying decision is contested during the milestone):

- **ADR-006a** *(if the "two sentinels" choice is debated):* "Two sentinels not one" — why `# KARYON SPOKES MOUNT` and `# KARYON POC MOUNT` are kept separate rather than collapsed.
- **ADR-007a** *(if the kubeconfig generator path is contested):* "Tenant kubeconfig minting via `issue-tenant-kubeconfig.sh` rather than the upstream `proxy-kubeconfig-generator` utility" — likely just a vendoring decision.
- **ADR-007b** *(if Phase 4 negative RBAC reveals gaps):* "Multi-tenancy lockdown patches on hub-flux: `--no-cross-namespace-refs=true` + `--default-service-account` and their compatibility with v1 spoke Kustomizations."

**ADR template:** Nygard 4-section (Status / Context / Decision / Consequences), per existing 0001-0005 ADRs. Status: Proposed → Accepted on the milestone-close commit.

---

## Sources

### Authoritative (HIGH confidence)

- Existing karyon repo files read directly:
  - `/home/rich/code/gsd/karyon/clusters/hub-flux/flux-system/kustomization.yaml` — contains `# KARYON SPOKES MOUNT` and the FLUX PATCH SURFACE comment block
  - `/home/rich/code/gsd/karyon/clusters/hub-flux/spokes/spoke-apps.yaml` — proven `spec.kubeConfig.secretRef` shape with `key: value.yaml`
  - `/home/rich/code/gsd/karyon/scripts/register-spokes-for-flux.sh` — `ensure_hub_spokes_mount()` + `apply_hub_secret()` patterns for sentinel insertion and imperative kubeconfig Secret creation
  - `/home/rich/code/gsd/karyon/scripts/create-clusters.sh` — k3d port + TLS-SAN nodefilter + GPU drift-check pattern
  - `/home/rich/code/gsd/karyon/scripts/rebuild.sh` — exact 7-step destructive chain
  - `/home/rich/code/gsd/karyon/docs/adr/0004-hub-only-flux-control-plane.md` — ADR-004 invariant and P18 silent-misroute documentation
- [Capsule Tenant CRD (v1beta2)](https://context7.com/projectcapsule/capsule/llms.txt) via Context7 (HIGH — official upstream)
- [Capsule + Flux multi-tenancy reference architecture (`clastix/flux2-capsule-multi-tenancy`)](https://github.com/clastix/flux2-capsule-multi-tenancy/blob/main/docs/ARCHITECTURE.md) — explicit `spec.kubeConfig` (proxy) + `spec.serviceAccountName` impersonation pattern (HIGH — official Capsule repo, this is the `clastix` namespace)
- [Capsule Helm install reference (`projectcapsule/capsule` chart)](https://github.com/projectcapsule/capsule/blob/main/charts/capsule/README.md) (HIGH — upstream chart README)
- [Flux multi-tenancy lockdown documentation](https://fluxcd.io/flux/installation/configuration/multitenancy/) — `--no-cross-namespace-refs=true` + `--default-service-account` controller flags (HIGH — Flux official docs)
- [Flux Kustomization API reference](https://fluxcd.io/flux/components/kustomize/kustomizations/) — `spec.serviceAccountName` semantics (HIGH — Flux official docs)
- [`projectcapsule/capsule-proxy` Helm chart README](https://github.com/projectcapsule/capsule-proxy/blob/main/charts/capsule-proxy/README.md) — NodePort + service exposure (HIGH — upstream chart)

### Cross-referenced (MEDIUM confidence)

- [`fluxcd/flux2-multi-tenancy`](https://github.com/fluxcd/flux2-multi-tenancy) — Flux's own multi-tenancy reference, complements the Capsule integration but doesn't include Capsule
- [`projectcapsule/capsule-addon-fluxcd`](https://github.com/projectcapsule/capsule-addon-fluxcd) — Capsule's Flux integration tooling
- [`projectcapsule.dev` Capsule docs](https://projectcapsule.dev/docs/guides/use-fluxcd/) — narrative explanation of self-impersonation and capsule-proxy in the kubeConfig

### Lower-confidence / illustrative

- [oneuptime.com walkthrough on Capsule + Flux](https://oneuptime.com/blog/post/2026-03-05-capsule-flux-cd-multi-tenancy/view) — used only as cross-check; not authoritative

---

*Architecture research for: v0.19 Capsule Multi-Tenancy POC integration with the existing 3-cluster k3d + hub-only Flux topology*
*Researched: 2026-04-29*
