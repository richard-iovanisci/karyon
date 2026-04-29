# Stack Research — v0.19 Capsule Multi-Tenancy POC (additions only)

**Domain:** Multi-tenancy operator + RBAC reverse proxy + Flux 2 multi-tenancy lockdown for a dedicated `spoke-capsule` k3d cluster, reconciled by hub-only Flux GitOps from `clusters/hub-flux/`.
**Researched:** 2026-04-29
**Confidence:** HIGH (all chart pins verified against upstream GitHub release API on 2026-04-29; Flux multi-tenancy flags verified against official fluxcd.io docs; CRD list verified against the v0.12.4 git tree).
**Predecessor:** This document supersedes the v0.18 STACK.md (kept in milestone archive). Everything from v0.18 stack — k3s, k3d, Flux, kubectl, helm, asdf, etc. — is **carried forward unchanged**. Only Capsule-specific additions are listed here.

---

## TL;DR — New pins for v0.19

| Component | Pin | Source/registry |
|---|---|---|
| Capsule operator (Helm chart) | **0.12.4** | `oci://ghcr.io/projectcapsule/charts/capsule:0.12.4` |
| capsule-proxy (Helm chart) | **0.12.0** | `oci://ghcr.io/projectcapsule/charts/capsule-proxy:0.12.0` |
| capsule-addon-fluxcd (Helm chart, Phase B only) | **0.2.3** | `oci://ghcr.io/projectcapsule/charts/capsule-addon-fluxcd:0.2.3` |
| `hack/create-user.sh` (vendored) | tag **`v0.12.4`** | `https://raw.githubusercontent.com/projectcapsule/capsule/v0.12.4/hack/create-user.sh` |

No new entries in `.tool-versions`. No new system packages. No upgrade required to k3s, k3d, Flux, or any v0.18 tool.

---

## Summary

Three OCI Helm charts (Capsule operator, capsule-proxy, capsule-addon-fluxcd) plus one vendored shell helper (`hack/create-user.sh`, pinned to tag `v0.12.4`) layer on top of the existing v0.18 stack. The integration point is a new **KARYON POC MOUNT** sentinel in `clusters/hub-flux/flux-system/kustomization.yaml`, mirroring the existing **KARYON SPOKES MOUNT** that already mounts `../spokes` (lines 16-20 today). The new mount points at `../poc` (or equivalent), which then conditionally includes a `capsule/` subtree only when the POC spoke exists.

Capsule and capsule-proxy install as Flux `HelmRelease` objects on **hub-flux** with `spec.kubeConfig.secretRef.name: spoke-capsule-kubeconfig` and `key: value.yaml` — the same P18 silent-misroute defense pattern that v0.18 spoke `Kustomization` objects already use (Plan 04-04 / ADR-004). The HelmRelease just swaps `kustomize.toolkit.fluxcd.io/v1` for `helm.toolkit.fluxcd.io/v2`; everything else carries over.

**Three things to keep in mind throughout:**

1. **k8s ≥ 1.34.0 is the floor for both Capsule v0.12.x and capsule-proxy v0.12.0.** Karyon already pins `rancher/k3s:v1.34.6-k3s1` (ADR-005), so the floor is satisfied with 6 patches of margin. If Capsule is ever upgraded ahead of a k3s bump, this pin is the constraint to re-verify.
2. **Install Capsule and capsule-proxy as two separate `HelmRelease` objects, not the umbrella chart with `proxy.enabled=true`.** The umbrella chart `charts/capsule/Chart.yaml` (v0.12.4) pins its `capsule-proxy` sub-dependency at **0.10.0**, two minors behind today's standalone 0.12.0. Standalone install is the only way to track the current proxy line.
3. **Flux 2.x already supports tenant lockdown natively via three controller flags** (`--no-cross-namespace-refs`, `--no-remote-bases`, `--default-service-account`). No new Flux components — only a Kustomize patch to the existing FLUX PATCH SURFACE in `clusters/hub-flux/flux-system/kustomization.yaml` (which already documents itself as the supported patch surface in lines 1-13).

---

## Charts and Versions

### Core charts (new in v0.19)

| Chart | Chart Version | App Version | OCI URL | Purpose | Why Recommended |
|---|---|---|---|---|---|
| `capsule` | **0.12.4** | 0.12.4 | `oci://ghcr.io/projectcapsule/charts/capsule` | Capsule operator: tenant CRDs, validating/mutating webhooks, RBAC for tenant owners | Newest stable in the 0.12 line, published 2025-12-19 (≈ 4 months old at research time). Project supports only the latest minor of K8s; v0.12 → k8s ≥ 1.34. |
| `capsule-proxy` | **0.12.0** | 0.12.0 | `oci://ghcr.io/projectcapsule/charts/capsule-proxy` | Reverse proxy in front of kube-api that filters list/watch responses by tenant ownership | Newest stable, published 2026-04-14 (≈ 2 weeks old at research time). v0.12.0 explicitly tracks Capsule v0.12.4 — release notes show `update module github.com/projectcapsule/capsule to v0.12.4`. |
| `capsule-addon-fluxcd` | **0.2.3** | 0.2.3 | `oci://ghcr.io/projectcapsule/charts/capsule-addon-fluxcd` | Auto-generates RBAC + kubeconfig Secrets for tenant-owner ServiceAccounts so tenant Flux Kustomizations reconcile through SA impersonation under multi-tenancy lockdown | The official solution to "Flux multi-tenancy lockdown + Capsule" — published 2025-11-20 by the same maintainer team. **Optional** in Phase A (Capsule + 2 tenants + proxy round-trip); **recommended** for Phase B (Flux tenant reconciliation investigation). |

### Why two HelmReleases, not the umbrella `proxy.enabled=true`

The Capsule umbrella chart `charts/capsule/Chart.yaml` (at tag `v0.12.4`) declares:

```yaml
dependencies:
- name: capsule-proxy
  version: 0.10.0                                             # <-- two minors stale
  repository: "oci://ghcr.io/projectcapsule/charts"
  condition: proxy.enabled
  alias: proxy
```

That dependency is **two minors behind** the standalone capsule-proxy 0.12.0 (which itself was published 4 months after Capsule v0.12.4). Installing via `proxy.enabled=true` pins the proxy at 0.10.0 with no override path short of forking the chart. Splitting into two `HelmRelease` objects is the supported way to keep both on their own release cadence and is the path documented at `projectcapsule.dev/docs/proxy/installation/`.

### Flux HelmRelease shape (canonical, hub-installed, reconciled to spoke)

Each chart becomes one `OCIRepository` (in `flux-system` on the hub) plus one `HelmRelease` (also on the hub) that targets the spoke via `spec.kubeConfig`:

```yaml
# clusters/hub-flux/poc/capsule/source.yaml
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: OCIRepository
metadata:
  name: capsule
  namespace: flux-system
spec:
  interval: 12h
  url: oci://ghcr.io/projectcapsule/charts/capsule
  ref:
    tag: "0.12.4"
---
# clusters/hub-flux/poc/capsule/release.yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: capsule
  namespace: flux-system          # HelmRelease object lives on the HUB
spec:
  interval: 5m
  releaseName: capsule
  targetNamespace: capsule-system
  storageNamespace: capsule-system
  install:
    createNamespace: true
  chartRef:
    kind: OCIRepository
    name: capsule
  kubeConfig:                     # PROJECT INVARIANT — see ADR-004 + Plan 04-04
    secretRef:
      name: spoke-capsule-kubeconfig
      key: value.yaml
  values:
    crds:
      install: true
    tls:
      enableController: true       # Capsule-managed webhook certs; NO cert-manager (out of scope)
    manager:
      replicas: 1                  # POC; bump to 2 only if HA is added later
      options:
        forceTenantPrefix: false
```

Notes on the shape:
- `chartRef:` (the v2 short form, no separate `HelmChart` object) is the current Flux 2.x recommendation for OCI sources.
- `spec.kubeConfig.secretRef` with `key: value.yaml` mirrors the v0.18 silent-misroute defense from Plan 04-04 / ADR-004 verbatim. **Omitting `spec.kubeConfig` would silently install Capsule on the hub** — the same P18 trap that ADR-004 was written for.
- `install.createNamespace: true` plus `targetNamespace: capsule-system` removes the need for a separate `Namespace` manifest; `storageNamespace` co-locates the Helm release Secret with the operator.
- `tls.enableController: true` keeps webhook certs internal — no cert-manager dependency (out of scope; see "What NOT to Add").

A second `HelmRelease` in `clusters/hub-flux/poc/capsule/proxy.yaml` mirrors this for `capsule-proxy:0.12.0` with `targetNamespace: capsule-system` and `service.type: NodePort` in values (see "ServiceType options for k3d local lab" below).

### Kubernetes version compatibility

| Component | Floor | Karyon current pin | Margin |
|---|---|---|---|
| Capsule v0.12.4 | k8s ≥ 1.34.0 | k3s v1.34.6-k3s1 (k8s v1.34.6) | 6 patches above floor — comfortable |
| capsule-proxy v0.12.0 | k8s ≥ 1.34.0 | k3s v1.34.6-k3s1 | 6 patches above floor — comfortable |
| capsule-addon-fluxcd v0.2.3 | unspecified — depends on Capsule v0.12.x + Flux v2 (`helm.toolkit.fluxcd.io/v2`) | both present | OK |

**Compatibility note:** The Capsule project explicitly states "support only for the latest minor version of Kubernetes" (release notes for both v0.12.4 and capsule-proxy v0.12.0 contain identical compatibility tables). If k3s is later upgraded to 1.35, Capsule must be re-verified before the lab is rebuilt.

---

## CRDs Introduced

Capsule v0.12.4 ships **7 CRDs** in `charts/capsule/crds/` (verified against the git tree at tag `v0.12.4`):

| CRD (Kind) | API Group | Scope | One-line role |
|---|---|---|---|
| `Tenant` | `capsule.clastix.io/v1beta2` | Cluster-scoped | Primary unit of multi-tenancy: owns a list of namespaces, defines owners (User/Group/SA), quotas, network policies, allowed nodeSelectors, ingress hostnames, etc. |
| `CapsuleConfiguration` | `capsule.clastix.io/v1beta2` | Cluster-scoped (singleton, default name `default`) | Operator-wide config: which Kubernetes groups are tenant groups, force-tenant-prefix, ignored groups (e.g. `system:masters`), HA settings. capsule-proxy reads `capsuleConfigurationName` (default `default`) at startup to discover tenant groups. |
| `GlobalTenantResource` | `capsule.clastix.io/v1beta2` | Cluster-scoped | Replicates a resource (Secret, ConfigMap, NetworkPolicy template, etc.) from a source namespace into every namespace owned by selected tenants. Used by `capsule-addon-fluxcd` to distribute the kubeconfig Secret across tenant namespaces when `kubeconfig-global=true`. |
| `TenantResource` | `capsule.clastix.io/v1beta2` | Namespace-scoped | Same as GlobalTenantResource but scoped to a single tenant — replicates resources across that tenant's namespaces only. |
| `ResourcePool` | `capsule.clastix.io/v1beta2` | Cluster-scoped | Multi-tenant cousin of ResourceQuota: a pool of CPU/memory/storage that multiple tenants can claim from. Newer feature (post-0.10). |
| `ResourcePoolClaim` | `capsule.clastix.io/v1beta2` | Namespace-scoped | Tenant's claim against a ResourcePool — allocates a slice for that namespace. |
| `TenantOwner` | `capsule.clastix.io/v1beta2` | Cluster-scoped | Decouples Tenant ownership into a separate object (newer pattern, alternative to inline `spec.owners[]` on Tenant). Allows transferring ownership without editing the Tenant resource. |

**capsule-proxy adds 0 CRDs** to the cluster — it is a stateless reverse proxy that *reads* Capsule CRDs to make filtering decisions. It does, however, recognise an optional `ProxySetting` (per-tenant proxy config) and `GlobalProxySettings` (cluster-wide proxy config). These are part of the proxy's chart values and are **not strictly required** for the POC; the chart defaults are sufficient.

**capsule-addon-fluxcd adds 0 CRDs.** It is a controller that reconciles existing objects (annotated ServiceAccounts in tenant namespaces) and produces RBAC + Secret artefacts. It uses `GlobalTenantResource` (a Capsule CRD) for the optional `kubeconfig-global` flow.

For the v0.19 POC, the only CRDs the milestone authors will hand-write are:
- `CapsuleConfiguration/default` (one cluster-scoped singleton — explicit override only if the default `userGroups: ["projectcapsule.dev"]` needs changing).
- `Tenant/<name>` × 2 — REQ "≥ 2 tenants with separate owners" — one per tenant.

The remaining CRDs are validated by their **non-use**: a tenant owner attempting to apply a `TenantResource` outside their tenant's namespaces should be rejected by the validating webhook (covered by the negative-RBAC bats suite).

---

## Flux Multi-Tenancy Knobs

Flux 2.x supports tenant-scoped reconciliation natively via three flags on the controller deployments. **No new Flux components are added** — only patches to the existing 4 controllers (kustomize, helm, source, notification, plus optional image-* if installed) via the FLUX PATCH SURFACE in `clusters/hub-flux/flux-system/kustomization.yaml`.

### The three flags (per fluxcd.io official docs)

| Flag | Controllers | What it does | Apply when |
|---|---|---|---|
| `--no-cross-namespace-refs=true` | kustomize, helm, notification, image-reflector, image-automation | Forbids a Kustomization/HelmRelease in namespace A from referencing a Source/Provider/Alert in namespace B. Closes the "tenant uses another tenant's GitRepo" hole. | **Phase B** (Flux tenant reconciliation investigation). Apply to all 5 controllers. |
| `--no-remote-bases=true` | kustomize | Forbids `kustomization.yaml` from referencing remote bases (URLs to other repos). Forces all manifests to be local files in the source repo. | **Phase B**. Apply to kustomize-controller only. |
| `--default-service-account=default` | kustomize, helm | A Kustomization/HelmRelease without an explicit `spec.serviceAccountName` falls back to the namespace's `default` SA (which has no permissions), forcing tenants to declare what they impersonate. | **Phase B**. Apply to kustomize and helm controllers. |

### Patch shape (additive to existing FLUX PATCH SURFACE)

The existing `clusters/hub-flux/flux-system/kustomization.yaml` (lines 1-13) already documents itself as the supported patch surface that survives re-bootstrap. Phase B adds a `patches:` block:

```yaml
# clusters/hub-flux/flux-system/kustomization.yaml — Phase B addition
patches:
  - target:
      kind: Deployment
      name: "(kustomize-controller|helm-controller|notification-controller|image-reflector-controller|image-automation-controller)"
      labelSelector: app.kubernetes.io/part-of=flux
    patch: |
      - op: add
        path: /spec/template/spec/containers/0/args/-
        value: --no-cross-namespace-refs=true
  - target:
      kind: Deployment
      name: kustomize-controller
    patch: |
      - op: add
        path: /spec/template/spec/containers/0/args/-
        value: --no-remote-bases=true
  - target:
      kind: Deployment
      name: "(kustomize-controller|helm-controller)"
    patch: |
      - op: add
        path: /spec/template/spec/containers/0/args/-
        value: --default-service-account=default
```

Plus the `flux-system` Kustomization itself must declare an explicit `spec.serviceAccountName: kustomize-controller` (cluster-admin SA) so platform-level reconciliation continues to work after `--default-service-account` is enabled. This is the "platform-admin escape hatch" pattern documented at fluxcd.io.

### The capsule-addon-fluxcd flow

`capsule-addon-fluxcd:0.2.3` is the official answer to "how do tenants own Flux resources without breaking lockdown":

1. Platform admin creates a ServiceAccount in a tenant namespace with annotation `capsule.addon.fluxcd/enabled: "true"`.
2. Adds that SA to the Tenant's `spec.owners[]` (with `kind: ServiceAccount`).
3. Addon controller produces:
   - A Role/RoleBinding granting the SA tenant-scoped Flux permissions.
   - A kubeconfig `Secret` impersonating that SA.
4. Tenant authors a `Kustomization` referencing both the Secret (`spec.kubeConfig`) and the SA (`spec.serviceAccountName`).
5. Reconciliation runs as the SA; lockdown flags above prevent escape.

**Recommendation:** Phase A (initial Capsule + 2 tenants + capsule-proxy round-trip) does **not** need the addon — keep scope tight and validate the simpler picture first. Phase B (Flux tenant reconciliation investigation) installs it as a third HelmRelease and adds the lockdown flags.

---

## ServiceType, Tenant Discovery, and Tenant Kubeconfigs

### capsule-proxy ServiceType for the k3d local lab

capsule-proxy chart 0.12.0 supports `ClusterIP` (default), `NodePort`, and `LoadBalancer` (verified in `values.yaml` comment: *"Specifies the service type should be created (ClusterIP, NodePort or LoadBalancer)"*). Default listen port is **9001**.

**Recommendation for k3d single-host POC: `NodePort`** with an explicit `nodePort:` value, optionally combined with `kubectl port-forward` for ad-hoc local testing.

| Option | When to use | Pros | Cons |
|---|---|---|---|
| **`NodePort`** | **Default for the POC** — stable URL, repeatable test scripts | Stable `https://<spoke-capsule-host>:<nodePort>` reachable from WSL, scriptable in bats | Requires k3d cluster to expose the nodePort (which `--api-port` already does for 6443; needs `--port "30443:30443@server:0"` or similar) |
| `kubectl port-forward` | Ad-hoc local tests, when you don't want to re-create the cluster | Zero cluster-config change | Per-shell process, dies on disconnect, not scriptable for bats live tests |
| `LoadBalancer` | Production / public ingress | Real LB, real DNS | Not relevant — out of scope for POC |
| Plain `ClusterIP` | Reach via `kubectl exec`-into-cluster only | Simplest | Cannot be reached from outside the cluster — fails the "tenant kubeconfig routes via proxy" requirement |

The k3d `cluster create` flag for the new spoke-capsule needs to expose the nodePort: e.g. `--port "30443:30443@server:0"`. This pairs with chart values `service.type: NodePort` + `service.nodePort: 30443`. The tenant kubeconfig then has `server: https://k3d-spoke-capsule-server-0:30443` (in-WSL reach via the existing `k8s-net` Docker network, mirroring the v0.18 hub-spoke wire-up) or `https://localhost:30443` (host-bound).

### Tenant discovery (how capsule-proxy finds tenants)

capsule-proxy is **stateless re: tenants** — at startup it reads `CapsuleConfiguration/<name>` (default name `default`, override via Helm value `capsuleConfigurationName`). That config tells the proxy:
- Which Kubernetes groups are "tenants" (default `["projectcapsule.dev"]`)
- Which groups are admins (default `["system:masters"]`)

At request time, the proxy:
1. Authenticates the inbound request (cert/token) — same as kube-api would.
2. Reads the user's groups from the auth result.
3. If the user's groups intersect the tenant groups, the proxy reads `Tenant` CRs from the cluster, finds Tenants where the user is an owner (via `spec.owners[].name + .kind`), and filters list/watch responses to that tenant's namespaces only.

This means **no additional configuration is needed for tenant discovery beyond installing the Capsule operator + creating Tenant CRs** — the proxy is plumbed automatically.

Feature gates worth knowing (all default-correct for the POC; documented at `projectcapsule.dev/docs/proxy/options/`):
- `ProxyAllNamespaced` — default `true`. Proxy filters all namespaced object lists.
- `ProxyClusterScoped` — default `false`. Set true (via ProxySettings) to also filter cluster-scoped objects per-tenant. **Skip for Phase A**; revisit only if the negative-RBAC tests need it.
- `SkipImpersonationReview` — default `false`. **DO NOT enable** — bypasses authorization for impersonation headers; documented as dangerous.

### Tenant kubeconfig generation (no kubectl plugin)

There is **no `kubectl-capsule` plugin and no `capsule-cli` binary** in the projectcapsule org as of 2026-04-29 (verified by enumerating the org's repos via the GitHub API — repo list: `capsule`, `capsule-proxy`, `capsule-community`, `charts`, `capsule-addon-fluxcd`, `website`, `playgrounds`, `watchdog`, `apimachinery`, `examples`). The canonical local-lab approach is the upstream helper script:

| Tool | Source | Pin | Purpose |
|---|---|---|---|
| `hack/create-user.sh` | `https://raw.githubusercontent.com/projectcapsule/capsule/v0.12.4/hack/create-user.sh` | tag `v0.12.4` | Generates an x509-cert-based tenant-owner kubeconfig via Kubernetes CSR API. Inputs: USER, TENANT, optional GROUP (default `projectcapsule.dev`). Outputs: `${USER}-${TENANT}.{key,crt,kubeconfig}`. Dependencies: `openssl`, `kubectl`, `jq` — all already present per Phase 1 preflight. |

**Install pattern for karyon:** Vendor the script under `scripts/poc/capsule/create-user.sh` (committed at the SHA from tag `v0.12.4`) rather than `curl`-piping it at runtime. This:

1. Keeps the lab reproducible across re-runs (no GitHub fetch in `task` flow).
2. Lets v0.19 add a karyon-style header block matching the rest of `scripts/` (idempotency guard, `set -euo pipefail`, source `preflight-lib.sh` for ANSI helpers).
3. Allows Wave 0 bats tests to assert the script's existence and dependencies without depending on the network.

Then post-process the generated kubeconfig: rewrite `clusters[0].cluster.server:` to point at capsule-proxy's NodePort (e.g. `https://k3d-spoke-capsule-server-0:30443`) instead of the raw apiserver. This is what makes the kubeconfig "route through the proxy" per REQ "kube-api access through capsule-proxy".

For the ServiceAccount-based path used by capsule-addon-fluxcd in Phase B, the addon **generates the kubeconfig Secret automatically** — no script needed.

---

## Test Tooling

The repo already has bats-core 1.11.0 + 169 tests + `tests/bats/test_helper.bash` with `require_live` / `require_live_destructive` skip-gates. **No new test framework is needed.** Three small additions make the v0.19 POC bats-friendly:

### New helpers to add to `tests/bats/test_helper.bash`

| Helper | Purpose | Sketch |
|---|---|---|
| `with_kubeconfig <path>` | Run a kubectl command with a specific kubeconfig (tenant or admin), restoring KUBECONFIG on exit | Wrapper that exports KUBECONFIG, runs `"$@"`, captures rc, restores. Used in tenant round-trip tests. |
| `assert_can <verb> <resource> [-n <ns>]` | Asserts `kubectl auth can-i <verb> <resource>` returns "yes" exit 0 — works with `--as` / `--as-group` for impersonation tests | Wraps `kubectl auth can-i` so failure messages name the verb/resource being asserted. |
| `assert_cannot <verb> <resource> [-n <ns>]` | Negative — asserts "no" / non-zero exit | Same shape, inverted assertion. The canonical RBAC-test idiom (per multiple community RBAC-bats references). |
| `require_live_capsule` | Like `require_live` but additionally requires `KARYON_LIVE_CAPSULE_TESTS=1` AND a reachable `k3d-spoke-capsule` cluster | Skips by default; enables tier-3 live tests only when the POC spoke is up. Mirrors `require_live` skip-gate pattern. |

### New bats suites for v0.19 (Wave 0 contracts before any implementation)

Following the v0.18 Wave 0 Nyquist gate pattern (RETROSPECTIVE.md key lesson #2):

| Suite | What it asserts | Live? |
|---|---|---|
| `tests/bats/poc-capsule-01-static.bats` | Manifest existence: `clusters/hub-flux/poc/capsule/source.yaml`, `release.yaml`, `proxy.yaml`. KARYON POC MOUNT sentinel comment present in `clusters/hub-flux/flux-system/kustomization.yaml`. | No (static) |
| `tests/bats/poc-capsule-02-helmrelease.bats` | Each HelmRelease declares `spec.kubeConfig.secretRef.name: spoke-capsule-kubeconfig` and `key: value.yaml` (P18 silent-misroute defense per ADR-004). Chart pin matches the documented version. | No (static, yq-driven) |
| `tests/bats/poc-capsule-03-tenants-static.bats` | ≥ 2 `Tenant` objects in `clusters/spoke-capsule/tenants/`, each with distinct `metadata.name` and distinct `spec.owners[].name`. | No (static) |
| `tests/bats/poc-capsule-04-live-rbac.bats` | (`require_live_capsule`) Tenant A's owner can `kubectl get pods -n <tenant-a-ns>` (yes); cannot `kubectl get pods -n <tenant-b-ns>` (no); cannot escalate via `kubectl get nodes` (no, list-cluster-scoped). | Yes |
| `tests/bats/poc-capsule-05-live-proxy.bats` | (`require_live_capsule`) Tenant kubeconfig with proxy-rewritten `server:` returns the same Tenant A namespaces as the addon-generated SA path; raw apiserver bypass returns more namespaces (proves the proxy is filtering, not just network-routing). | Yes |
| `tests/bats/poc-capsule-06-webhook-failure.bats` | (`require_live_capsule`) Disable Capsule's mutating webhook (or scale operator to 0) and assert tenant namespace creation fails in the "expected" way (validating webhook `failurePolicy: Fail` leaves the cluster safe; configuration webhook `failurePolicy: Ignore` is the documented exception). Restore on teardown. | Yes (destructive-ish — only if the operator was scaled) |

**Wave 0 invariant:** all 6 suites land *parse-clean and either passing-on-static or skip-with-reason* before any HelmRelease YAML is committed. Static tests RED-fail until manifests appear; live tests skip until `KARYON_LIVE_CAPSULE_TESTS=1` is set after spoke-capsule is up.

### Existing tests to extend (not replace)

| Existing suite | Extend? | What |
|---|---|---|
| `tests/bats/preflight-pre*.bats` | No — preflight already covers `kubectl`, `jq`, `openssl` | Leave untouched. |
| `tests/bats/create-clusters-*.bats` | **Yes** — add `create-clusters-06-spoke-capsule.bats` if `task create-poc-spoke` is added; gated by `require_live` | Mirrors `create-clusters-04-spoke-apps.bats`. |
| `tests/bats/register-spokes-01-static.bats` | **Yes** — add a parallel `register-poc-spoke-01-static.bats` if a separate registration script lands | Mirrors register-spokes pattern; same SA + kubeconfig Secret shape. |
| `tests/bats/destroy-rebuild-01-static.bats` | **Yes** — assert that `task rebuild` does **NOT** touch spoke-capsule (it's persistent for the POC, not in the v1 topology). The rebuild script's grep-able log markers must not include any spoke-capsule step. | Static, runs under existing CI matrix. |

---

## What NOT to Add

These are tempting near-neighbours that an implementer might pull in if they don't read this section. Each is **explicitly out of scope per PROJECT.md v0.19 boundaries**:

| Avoid | Why it's tempting | Why we don't need it (v0.19) | Add later if/when |
|---|---|---|---|
| **cert-manager** | Capsule's `tls.create=false` + `certManager.generateCertificates=true` is a documented install path. capsule-proxy 0.12.0 also has `secretTemplate` for cert-manager-issued certs. | `tls.enableController: true` (chart default) makes Capsule generate its own webhook certs. capsule-proxy NodePort over self-signed TLS is acceptable for a token/cert-auth POC. PROJECT.md v0.19 explicitly defers "Production ingress / TLS for capsule-proxy". | A "production hardening" milestone — pair with real ingress. |
| **dex / keycloak / OIDC issuer** | Capsule docs lean OIDC-first; capsule-proxy supports OIDC bearer tokens. | PROJECT.md v0.19 explicitly defers "OIDC tenant authentication — token-based for the Capsule POC". `hack/create-user.sh` x509-cert kubeconfigs satisfy "tenant kubeconfigs routing through capsule-proxy" without an external IdP. | Future "tenant identity" milestone. |
| **ingress-nginx / traefik HelmRelease** | Tenant access via HTTPS hostnames feels natural; Capsule has `IngressOptions` on Tenant. | k3d ships traefik in spoke-capsule by default (k3s-builtin); POC reachability is via NodePort on capsule-proxy, not ingress. PROJECT.md defers "Production ingress". | Same milestone as cert-manager. |
| **oauth2-proxy** (front of capsule-proxy) | Pattern for browser-based OIDC sessions in front of K8s. | Tenant clients are `kubectl` users with kubeconfigs, not browsers. | Only relevant if a dashboard milestone is added. |
| **HashiCorp Vault / SOPS / age** | Tenant kubeconfigs contain bearer tokens / private keys. | PROJECT.md v0.18 already defers "Real secret management" (gitignored `.env` only). v0.19 follows the same posture: tenant kubeconfigs are local artefacts, never committed; `.gitignore` already excludes `*.kubeconfig`. | When the broader "secret management" milestone lands. |
| **Capsule installed on hub-flux itself** | Self-bootstrap multi-tenancy (so the hub becomes a tenant boundary). | PROJECT.md v0.19 explicitly defers "Capsule installed on hub-flux itself — POC validates spoke-side multi-tenancy first". | Phase B+1 or a subsequent milestone after the graduation ADR. |
| **Crossplane / Cluster API / cluster factory** | "Spawn spoke clusters on demand" is a natural extension of `KARYON POC MOUNT`. | PROJECT.md v0.19 explicitly defers "Generic ephemeral cluster factory". `task create-poc-spoke` for spoke-capsule is a one-shot script, not a parameterised factory. | Future milestone after v0.19 graduation. |
| **OPA Gatekeeper / Kyverno** | Policy frameworks layered on top of multi-tenancy are common in production. | Capsule already covers tenant-scoped policy via `Tenant.spec` (resource quotas, network policies, allowed nodeSelectors, allowed image registries). Adding a separate policy engine is duplicative for the POC. | Production hardening milestone. |
| **A separate `KARYON CAPSULE MOUNT` sentinel** | Naming consistency with KARYON SPOKES MOUNT. | PROJECT.md v0.19 calls for a **generic** `KARYON POC MOUNT` so the seam is reusable for future POCs (Crossplane, Linkerd, etc.). A Capsule-specific sentinel would need to be renamed later. | Never — the generic naming is the point. |
| **Flux installed on spoke-capsule** | "It's its own cluster, give it its own Flux." | ADR-004 explicit invariant: hub-only Flux. Spoke-capsule reconciles via hub-flux + `spec.kubeConfig` like any other spoke. | Never (would require an ADR-004 amendment). |
| **Adding spoke-capsule to `task rebuild`** | Convenience — one command to recreate everything. | PROJECT.md v0.19 explicitly defers "Default platform adoption of Capsule — Capsule stays outside `task rebuild` until a graduation ADR explicitly adopts it". | The graduation ADR may flip this. |
| **NVIDIA device plugin / GPU on spoke-capsule** | Pattern symmetry with spoke-ml. | The POC validates multi-tenancy mechanics, not GPU sharing across tenants. PROJECT.md v0.19 defers "Multi-spoke tenant federation". | If a future milestone explores GPU multi-tenancy. |

---

## Installation (additions over v0.18 stack)

No system-level installs — everything runs in-cluster via Flux HelmReleases. Three artefacts to **fetch-and-pin** at known tags:

```bash
# ---------------------------------------------------------------
# 1. Pin and vendor the upstream tenant-kubeconfig helper script
#    (this is the only out-of-cluster artefact)
# ---------------------------------------------------------------
mkdir -p scripts/poc/capsule
curl -fsSL \
  "https://raw.githubusercontent.com/projectcapsule/capsule/v0.12.4/hack/create-user.sh" \
  -o scripts/poc/capsule/create-user.sh
chmod +x scripts/poc/capsule/create-user.sh
# Then add a karyon-style header (set -euo pipefail audit, source preflight-lib.sh)
# and commit at SHA matching v0.12.4. Subsequent runs DO NOT re-fetch.

# ---------------------------------------------------------------
# 2. Charts are pulled by Flux at reconcile time from OCI:
#    oci://ghcr.io/projectcapsule/charts/capsule:0.12.4
#    oci://ghcr.io/projectcapsule/charts/capsule-proxy:0.12.0
#    oci://ghcr.io/projectcapsule/charts/capsule-addon-fluxcd:0.2.3   (Phase B only)
#    No `helm repo add` is required — OCIRepository is the Flux source.
# ---------------------------------------------------------------

# ---------------------------------------------------------------
# 3. asdf .tool-versions: NO new entries needed.
#    Existing pins for kubectl, helm, k3d, flux all cover v0.19.
# ---------------------------------------------------------------
```

Anticipated `task` namespace additions (Phase 1 of the milestone):

```yaml
# Taskfile.yml additions (Phase 1)
  create-poc-spoke:
    desc: Create the spoke-capsule POC cluster on k8s-net (persistent; NOT in `task rebuild`)
    cmds:
      - bash scripts/poc/capsule/create-spoke-capsule.sh

  register-poc-spoke:
    desc: Register spoke-capsule with hub-flux for HelmRelease + Kustomization reconciliation
    cmds:
      - bash scripts/poc/capsule/register-spoke-capsule.sh

  create-tenant-kubeconfig:
    desc: Generate an x509 tenant-owner kubeconfig routed via capsule-proxy
    cmds:
      - bash scripts/poc/capsule/create-tenant-kubeconfig.sh "{{.USER}}" "{{.TENANT}}"

  destroy-poc-spoke:
    desc: Destroy spoke-capsule (manual; NOT chained from `task destroy`)
    cmds:
      - bash scripts/poc/capsule/destroy-spoke-capsule.sh
```

Note `task rebuild` is **unchanged** — the POC spoke is intentionally outside that flow per PROJECT.md.

---

## Alternatives Considered

| Recommended | Alternative | When to use the alternative |
|---|---|---|
| Capsule | **vcluster** (loft.sh) | When isolation needs full kube-api separation per tenant (separate apiserver, etcd, controller-manager). Capsule shares one apiserver and uses RBAC + webhooks; vcluster spawns nested apiservers. vcluster is heavier and overshoots POC needs. |
| Capsule | **HNC** (Hierarchical Namespaces, kubernetes-sigs) | When tenancy is *namespace tree* shaped (parent inherits to children) rather than *user/group* shaped. Capsule's owner-per-tenant model is a better fit for "≥ 2 tenants with separate owners". |
| Capsule | **Native RBAC + ResourceQuota only** | When tenancy is purely operator-administered (no self-service). Capsule's value is letting tenant owners create their own namespaces within their tenant — the "Namespace-as-a-Service" pattern that the POC validates. |
| capsule-proxy | **Plain kube-api with tenant RBAC** | When you don't need to hide other tenants' cluster-scoped resources from list/watch. Required to drop capsule-proxy: tenants must never run `kubectl get ns` and see other tenants' namespaces. The POC explicitly tests the proxy round-trip, so the proxy is in scope. |
| capsule-proxy | **kube-rbac-proxy** | Generic RBAC-aware proxy; not capsule-aware — doesn't understand `Tenant` ownership. Wrong tool for this job. |
| `hack/create-user.sh` (vendored) | **`kubectl create token` for tenant SA + kubeconfig stitching** | When using SA-based ownership (Phase B with capsule-addon-fluxcd). The addon generates these automatically. For Phase A user-based ownership we want x509 certs (long-lived, no token renewal scripts). |
| `hack/create-user.sh` | **Hand-rolled CSR + `kubectl certificate approve`** | Educational, but reinvents the wheel. The upstream script is the recommended path per `projectcapsule.dev/docs/tenants/quickstart`. |
| Two separate HelmReleases (capsule + capsule-proxy) | **Umbrella `helm install capsule … --set proxy.enabled=true`** | Never recommended for v0.19 — pins capsule-proxy to 0.10.0 (two minors stale). Only acceptable if a future milestone explicitly chooses to slow the proxy line to match the umbrella. |
| Flux 2.x native multi-tenancy flags | **External admission controller (e.g., Kyverno) policing Flux objects** | When the lockdown flags can't express the constraint (e.g., "tenant A may use kustomize but not helm"). Out of scope for v0.19. |
| capsule-addon-fluxcd | **Hand-rolled tenant ServiceAccount + RoleBinding + kubeconfig Secret** | If only one tenant ever needs Flux. The addon's value is automation that scales with tenant count. For Phase B (≥ 2 tenants), the addon wins. For Phase A (Capsule-only, no tenant Flux), neither is needed. |

---

## Version Compatibility (additive matrix for v0.19)

| Component A | Component B | Compatibility |
|---|---|---|
| Capsule v0.12.4 | k8s/k3s 1.34.x | Required floor — verified in v0.12.4 release notes table. |
| Capsule v0.12.4 | k8s/k3s 1.33.x | **Unsupported** — project supports only the latest minor. |
| capsule-proxy v0.12.0 | Capsule v0.12.4 | Verified — release notes show `update module github.com/projectcapsule/capsule to v0.12.4`. |
| capsule-proxy v0.12.0 | Capsule v0.10.x | **Mismatched** — proxy v0.12.0 needs the v0.12 CRD shape. The umbrella chart's pinned proxy 0.10.0 sidesteps this internally, but the standalone-pair must move together. |
| capsule-addon-fluxcd v0.2.3 | Flux v2 (helm.toolkit.fluxcd.io/v2) | Confirmed via README — uses `helm.toolkit.fluxcd.io/v2` and `kustomize.toolkit.fluxcd.io/v1` shapes. |
| capsule-addon-fluxcd v0.2.3 | Capsule v0.12.4 | Compatible by date proximity (addon released 2025-11-20, Capsule v0.12.0 released 2025-12-05 — addon was likely tested on the late-0.11 line; needs Phase B verification on v0.12.4 specifically). |
| Flux 2.x `--default-service-account=default` | Capsule Tenant SA owners | Compatible — the addon's annotated SAs become Tenant owners and Flux runs as them. The "default" SA fallback is the lockdown constraint, the addon's annotated SA is the explicit override. |
| k3d cluster `--port "30443:30443@server:0"` | capsule-proxy `service.type: NodePort` + `service.nodePort: 30443` | Standard k3d pattern — proven in v0.18 for apiserver port 6443. |

---

## Sources

### Authoritative — verified 2026-04-29

- **GitHub API: Capsule operator releases** — `https://api.github.com/repos/projectcapsule/capsule/releases` — confirmed v0.12.4 published 2025-12-19 is the current stable. (HIGH)
- **GitHub API: capsule-proxy releases** — `https://api.github.com/repos/projectcapsule/capsule-proxy/releases` — confirmed v0.12.0 published 2026-04-14 is the current stable. (HIGH)
- **GitHub API: capsule-addon-fluxcd releases** — `https://api.github.com/repos/projectcapsule/capsule-addon-fluxcd/releases` — confirmed v0.2.3 published 2025-11-20 is the current stable. (HIGH)
- **GitHub: Capsule v0.12.4 git tree** — `https://api.github.com/repos/projectcapsule/capsule/git/trees/v0.12.4?recursive=1` — confirmed CRD list in `charts/capsule/crds/`. (HIGH)
- **GitHub: Capsule umbrella chart Chart.yaml at v0.12.4** — `https://github.com/projectcapsule/capsule/blob/v0.12.4/charts/capsule/Chart.yaml` — confirmed the umbrella chart pins `capsule-proxy: 0.10.0` as a dependency, justifying the standalone-install recommendation. (HIGH)
- **Capsule v0.12.4 release notes** — `https://github.com/projectcapsule/capsule/releases/tag/v0.12.4` — confirmed `Kubernetes >= 1.34.0` floor. (HIGH)
- **capsule-proxy v0.12.0 release notes** — `https://github.com/projectcapsule/capsule-proxy/releases/tag/v0.12.0` — confirmed `>= 1.34.0` floor and `update module github.com/projectcapsule/capsule to v0.12.4`. (HIGH)
- **Flux multi-tenancy docs** — `https://fluxcd.io/flux/installation/configuration/multitenancy/` — confirmed the three flags (`--no-cross-namespace-refs`, `--no-remote-bases`, `--default-service-account`) and the platform-admin SA escape hatch. (HIGH)
- **Flux HelmRelease docs** — `https://fluxcd.io/flux/components/helm/helmreleases/` — confirmed `chartRef:` short form for OCI sources, `spec.kubeConfig.secretRef`, `spec.values` / `spec.valuesFrom`. (HIGH)

### Project documentation — current

- **projectcapsule.dev — quickstart** — `https://projectcapsule.dev/docs/tenants/quickstart/` — confirmed `hack/create-user.sh` is the canonical local-lab tenant kubeconfig path. (HIGH)
- **projectcapsule.dev — proxy installation** — `https://projectcapsule.dev/docs/proxy/installation/` — confirmed Helm-only installation; NodePort/LoadBalancer/Ingress exposure options. (HIGH)
- **projectcapsule.dev — proxy options + feature gates** — `https://projectcapsule.dev/docs/proxy/options/` — confirmed `ProxyAllNamespaced` (default true), `ProxyClusterScoped` (default false), `SkipImpersonationReview` (default false). (HIGH)
- **Capsule chart values.yaml at v0.12.4** — `https://github.com/projectcapsule/capsule/blob/v0.12.4/charts/capsule/values.yaml` — confirmed `tls.enableController: true` default, `crds.install: true`, `proxy.enabled: false`, webhook failurePolicies (most `Fail`, configuration `Ignore`). (HIGH)
- **capsule-proxy chart values.yaml at v0.12.0** — `https://github.com/projectcapsule/capsule-proxy/blob/v0.12.0/charts/capsule-proxy/values.yaml` — confirmed `service.type` ClusterIP/NodePort/LoadBalancer, `listeningPort: 9001`, `capsuleConfigurationName: default`. (HIGH)
- **capsule-addon-fluxcd README at v0.2.3** — `https://github.com/projectcapsule/capsule-addon-fluxcd/blob/v0.2.3/README.md` — confirmed addon flow: SA annotation → Tenant owner → addon generates RBAC + kubeconfig Secret → tenant Kustomization references both. (HIGH)
- **Capsule authentication doc** — `https://projectcapsule.dev/docs/operating/authentication/` — confirmed any K8s authentication strategy is acceptable; tenant group default `projectcapsule.dev`. (HIGH)

### Context7 (verification cross-check)

- **/projectcapsule/capsule** — Context7 library — verified Helm install patterns, Tenant CR shape, namespace impersonation patterns, and `apiVersion: capsule.clastix.io/v1beta2`. (HIGH)
- **kubectl-capsule plugin** — Confirmed by enumerating `https://api.github.com/orgs/projectcapsule/repos` that there is **no** `kubectl-capsule` or `capsule-cli` repo. Repo list: `capsule`, `capsule-proxy`, `capsule-community`, `charts`, `capsule-addon-fluxcd`, `website`, `playgrounds`, `watchdog`, `apimachinery`, `examples`. (HIGH — by absence)

### Repo-internal cross-references (consumed)

- `.planning/PROJECT.md` — v0.19 milestone scope and out-of-scope boundaries; ADR-004 hub-only Flux invariant; ADR-005 k3s pin. (HIGH)
- `.planning/RETROSPECTIVE.md` — Wave 0 Nyquist gate pattern (lesson 2); P18 silent-misroute trap from Plan 04-04; cwd-discipline for worktrees (lesson 1). (HIGH)
- `clusters/hub-flux/flux-system/kustomization.yaml` — existing `# KARYON SPOKES MOUNT` sentinel (line 19) + FLUX PATCH SURFACE comment block (lines 1-13) — the integration point that `# KARYON POC MOUNT` mirrors. (HIGH)
- `clusters/hub-flux/spokes/spoke-apps.yaml` and `spoke-ml.yaml` — existing pattern for `spec.kubeConfig.secretRef.name` + `key: value.yaml` defense-in-depth — directly inherited by the new HelmReleases. (HIGH)
- `tests/bats/test_helper.bash` — existing `require_live` / `require_live_destructive` skip-gate pattern that `require_live_capsule` extends. (HIGH)

### Confidence summary

- **Chart versions, OCI URLs, k8s floor:** HIGH — verified via GitHub release API + release notes within hours of writing.
- **CRD list:** HIGH — verified via git tree at the exact tag `v0.12.4`.
- **Flux multi-tenancy flags:** HIGH — verified on official fluxcd.io docs.
- **HelmRelease shape with `kubeConfig`:** HIGH — verified on official fluxcd.io docs.
- **No kubectl-capsule plugin exists:** HIGH (by enumeration of the org's repos).
- **capsule-addon-fluxcd ↔ Capsule v0.12.4 specific compatibility:** MEDIUM — date proximity and shared maintainer team strongly imply compatibility; the addon README does not declare an explicit Capsule-version range. **Phase B should re-verify via a smoke test before adoption** (suggested as a Phase B research flag).
- **k3d NodePort exposure pattern for capsule-proxy:** HIGH — same `--port "X:X@server:0"` pattern karyon already uses for apiserver 6443.

---

*Stack research for: v0.19 Capsule multi-tenancy POC — additions over karyon Lab v1.*
*Researched: 2026-04-29.*
*Confidence: HIGH — all chart pins re-verified against upstream release API the day of writing; Flux multi-tenancy flags verified against official fluxcd.io docs.*
