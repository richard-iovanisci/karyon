# Feature Research — v0.19 Capsule Multi-Tenancy POC

**Domain:** Capsule (CNCF Sandbox) multi-tenancy on a Karyon-managed POC k3d spoke (`spoke-capsule`), reconciled hub-only via Flux from `hub-flux`
**Milestone:** v0.19 — Capsule Multi-Tenancy POC (subsequent milestone, additive to validated v1 lab)
**Researched:** 2026-04-29
**Confidence:** HIGH (Context7 `/projectcapsule/capsule` 267 snippets benchmark 89.6, official Capsule + Flux docs cross-verified, multiple production case studies)

---

## Executive Summary

Capsule's job is to layer a `Tenant` CRD over a flat namespace plane. The Tenant says "this `User` / `Group` / `ServiceAccount` owns these (label-stamped) namespaces, must stay inside these `ResourceQuota` / `LimitRange` / `ingressOptions` / `storageClasses` / `nodeSelector` / `registry` boundaries, and gets these `additionalRoleBindings` automatically materialized in every owned namespace." Two cooperating components enforce that:

1. **`capsule-controller-manager`** — the operator. Reconciles Tenants. Installs **9 admission webhooks** (`/cordoning`, `/ingresses`, `/namespaces`, `/networkpolicies`, `/nodes`, `/pods`, `/persistentvolumeclaims`, `/services`, `/tenants`) — most default `failurePolicy: Fail` per the Helm chart values. The webhook is the **policy decision point**: a tenant-side `kubectl create namespace foo` that doesn't satisfy `forceTenantPrefix` or that exceeds `namespaceOptions.quota` is rejected at admission, not after a reconcile loop.
2. **`capsule-proxy`** — a separate add-on (`projectcapsule/capsule-proxy`, default port `9001`). It exists because **Kubernetes RBAC cannot filter cluster-scoped LIST**: there is no native way to give Alice "list namespaces, but only tenant-A's." `capsule-proxy` is a reverse proxy that intercepts kube-api calls and rewrites LIST responses for `Namespaces`, `Nodes`, `IngressClasses`, `StorageClasses`, `PriorityClasses`, `RuntimeClasses`, and `PersistentVolumes` so the tenant only sees what their Tenant CRD says they own. It supports **BearerToken, X509 client cert, and OIDC** (`authPreferredTypes: BearerToken,TLSCertificate`). Tenant kubeconfigs point at `https://<proxy>:9001`, not the apiserver directly.

For a **learning-lab POC whose only deliverable is a graduation ADR (adopt / defer / reject / another POC)**, the discriminating question is **"does the security boundary actually hold against a hostile tenant owner kubeconfig, and does Flux reconcile cleanly through Capsule?"** Everything else (ResourcePool, Gateway API restrictions, GlobalTenantResource, OIDC, PriorityClass mutation, ingress collision scope) is interesting but **not necessary** to answer that question and would inflate POC scope past its purpose.

**The shape of this milestone is therefore:**

- **Table stakes (12 features)** — must validate or the POC cannot graduate. Includes Tenant CRD apply, ≥2 tenants with disjoint owners, capsule-proxy reachable, **positive RBAC** (alice creates `oil-prod` namespace), **negative RBAC** (alice cannot touch `gas-prod`, cannot escalate to cluster-admin, cannot list bob's nodes through the proxy), Flux tenant Kustomization with `serviceAccountName` reconciling, webhook-down failure observation, `kubectl delete tenant` clean teardown.
- **Differentiators (8 features)** — nice-to-validate; informs the adopt-vs-defer decision but absence does not block graduation. Includes ResourceQuota aggregation across namespaces, ingressOptions hostname collision, capsule-proxy OIDC path, multi-spoke Flux fan-out via `kubeConfig` Secret, GlobalTenantResource pattern, `forceTenantPrefix`, `cordoned` field, `preventDeletion`.
- **Anti-features (10 features)** — explicitly avoid. OIDC issuer + dex/keycloak, real ingress + cert-manager + TLS, capsule on hub-flux itself, multi-spoke tenant federation, ResourcePool, Gateway API tenancy, runtime classes, full PSA + admission policy stack, real network policy baseline, "Capsule replaces all RBAC."

**The single most important POC outcome** is whether `kubectl --kubeconfig=alice.kubeconfig auth can-i '*' '*' --all-namespaces` returns `no` for everything outside Alice's tenant *and* whether `kubectl --kubeconfig=alice.kubeconfig get pods -n gas-prod` is rejected. That single observable falsifies most "I configured Capsule" misconfigurations.

**The single most important Flux outcome** is whether the platform-admin hub Kustomization can apply tenant Flux objects (Kustomization / HelmRelease in tenant namespace) using `--default-service-account` impersonation — without needing to grant Flux's controller SAs cluster-admin on the tenant — and whether `--no-cross-namespace-refs=true` actually breaks a malicious tenant that tries to point its `sourceRef` at another tenant's GitRepository.

---

## Tenant Mental Model

### Tenant CRD — One-Paragraph Mental Model

A `Tenant` is a cluster-scoped CRD (`capsule.clastix.io/v1beta2`) that declares **(a) who owns it** — one or more `owners` of `kind: User | Group | ServiceAccount`; **(b) what they can create** — a label-stamped set of `namespaces` capped by `namespaceOptions.quota`, automatically labeled `capsule.clastix.io/tenant: <name>`, optionally prefix-enforced via `forceTenantPrefix: true`; and **(c) the policy box around them** — `resourceQuotas` aggregated across all tenant namespaces, `limitRanges` auto-materialized into each tenant namespace, allow-lists for `storageClasses`, `ingressOptions.allowedClasses`/`allowedHostnames`, `serviceOptions.allowedTypes`, container `registries`, `nodeSelector` placement, and `additionalRoleBindings` (e.g., a `view` ClusterRole bound to an `auditor` Group in every owned namespace). The Capsule controller reconciles these into real `ResourceQuota`, `LimitRange`, `RoleBinding`, and `NetworkPolicy` objects inside each tenant namespace, and the 9 admission webhooks block tenant-driven attempts to step outside the box at admission time.

### ASCII Diagram — `oil` Tenant Owned by Alice + `gas` Tenant Owned by Bob

```
                         hub-flux (clusters/hub-flux/)
                         ├── Flux: --default-service-account=gitops-reconciler
                         ├──        --no-cross-namespace-refs=true
                         └──        --no-remote-bases=true
                                         │ kubeConfig Secret: spoke-capsule-kubeconfig
                                         │ (spec.kubeConfig in every Kustomization)
                                         ▼
   ┌─────────────────────────────────── spoke-capsule ──────────────────────────────────┐
   │                                                                                    │
   │   ┌────────────────────────────┐         ┌───────────────────────────────────┐     │
   │   │ capsule-controller-manager │         │ capsule-proxy  (Service:9001)     │     │
   │   │ (capsule-system ns)        │         │ (capsule-system ns)               │     │
   │   │                            │         │                                   │     │
   │   │ Watches Tenants            │         │ - Filters LIST of cluster-scoped: │     │
   │   │ Reconciles into NS:        │         │     namespaces, nodes,            │     │
   │   │   - ResourceQuota          │         │     ingressclasses,               │     │
   │   │   - LimitRange             │         │     storageclasses, pv,           │     │
   │   │   - RoleBindings           │         │     priorityclasses,              │     │
   │   │ 9 admission webhooks:      │         │     runtimeclasses                │     │
   │   │   /tenants /namespaces     │         │ - TokenReview against kube-api    │     │
   │   │   /pods /services /pvc     │         │ - Authn: BearerToken | TLS | OIDC │     │
   │   │   /ingresses /networkpols  │         │ - Tenant kubeconfig --server →    │     │
   │   │   /nodes /cordoning        │         │   https://<proxy>:9001            │     │
   │   │ (default failurePolicy:    │         └───────────────────────────────────┘     │
   │   │  Fail)                     │                                                   │
   │   └─────────────┬──────────────┘                                                   │
   │                 │ reconciles                                                       │
   │                 ▼                                                                  │
   │   ┌──────────── Tenant: oil ─────────────┐    ┌────────── Tenant: gas ──────────┐  │
   │   │ owners: [alice (User)]               │    │ owners: [bob (User)]            │  │
   │   │ namespaceOptions.quota: 5            │    │ namespaceOptions.quota: 3       │  │
   │   │ resourceQuotas: cpu=4, mem=8Gi       │    │ resourceQuotas: cpu=2, mem=4Gi  │  │
   │   │ ingressOptions.allowedClasses: nginx │    │ storageClasses: standard        │  │
   │   │ forceTenantPrefix: true              │    │ additionalRoleBindings: view→…  │  │
   │   └──────┬───────────────────────────────┘    └──────┬──────────────────────────┘  │
   │          │ owns labelled NS                          │                             │
   │          ▼                                           ▼                             │
   │   ┌─────────────────┐  ┌─────────────────┐   ┌────────────────┐                    │
   │   │ oil-prod        │  │ oil-staging     │   │ gas-prod       │                    │
   │   │ labels:         │  │ labels:         │   │ labels:        │                    │
   │   │  capsule.clas-  │  │  capsule.clas-  │   │  capsule.clas- │                    │
   │   │  tix.io/tenant: │  │  tix.io/tenant: │   │  tix.io/tenant:│                    │
   │   │  oil            │  │  oil            │   │  gas           │                    │
   │   │ ResourceQuota+  │  │ ResourceQuota+  │   │ ResourceQuota+ │                    │
   │   │ LimitRange      │  │ LimitRange      │   │ LimitRange     │                    │
   │   │ RoleBindings    │  │ RoleBindings    │   │ RoleBindings   │                    │
   │   └─────────────────┘  └─────────────────┘   └────────────────┘                    │
   │                                                                                    │
   │   ┌─── alice.kubeconfig ──────┐         ┌─── bob.kubeconfig ───────────┐           │
   │   │ server: https://<proxy>:  │         │ server: https://<proxy>:9001 │           │
   │   │   9001                    │         │ token: <bob bearer token>    │           │
   │   │ token: <alice bearer tkn> │         └──────────────────────────────┘           │
   │   └───────────────────────────┘                                                    │
   └────────────────────────────────────────────────────────────────────────────────────┘
```

**Key invariants the diagram encodes (each becomes a falsifier in the POC):**

- A tenant kubeconfig **always** points at `capsule-proxy` `:9001`, never the apiserver `:6443`. Going direct leaks cluster-scoped LIST.
- Namespaces are bound to a tenant by **label** (`capsule.clastix.io/tenant: <name>`), not by being "in" the tenant CRD's spec. The controller stamps the label.
- Cross-tenant reads (alice → `gas-prod`) MUST be RBAC-denied by stock Kubernetes RBAC because Capsule's `additionalRoleBindings` only target owned namespaces. Capsule does not "create" the security boundary — it **automates the RBAC that creates it**.
- The 9 webhooks plus capsule-proxy are the **two layers of the boundary**: webhooks block writes to disallowed cluster-state; proxy filters reads of cluster-scoped resources.

### Tenant Ownership: How Owners Self-Serve

Owners can be `User`, `Group`, or `ServiceAccount` (the v1beta2 `spec.owners[].kind`). On every owned namespace, Capsule materializes a `RoleBinding` granting the owner `cluster-admin` **scoped to that namespace** — so within their namespaces they can do anything Kubernetes RBAC allows, but they cannot reach across to another tenant's namespaces, and they cannot create cluster-scoped resources they aren't allowed (e.g., `ClusterRole`, `Node`, `PersistentVolume`).

To create a new namespace, the owner runs (in test/dev — production uses real auth):

```bash
# As the user, impersonating "alice" in the projectcapsule.dev group
kubectl create namespace oil-staging --as=alice --as-group=projectcapsule.dev
```

Capsule's `/namespaces` validating webhook checks:
- Is the requesting subject a `spec.owners[]` of any Tenant?
- If `forceTenantPrefix: true`, does the namespace name start with `<tenant>-`?
- Has `namespaceOptions.quota` been hit?

If all checks pass, the controller stamps `capsule.clastix.io/tenant: <name>` on the namespace and reconciles `ResourceQuota` / `LimitRange` / `RoleBindings` into it. If any fails, the request is rejected at admission with a clear error.

The `manager.options.users` field of `CapsuleConfiguration` (default `projectcapsule.dev`) lists the **groups** Capsule treats as candidate tenant users — i.e., the group an owner must be in for the proxy to serve them and for the webhook to evaluate ownership.

---

## Capsule-Proxy: Why It Exists

Kubernetes RBAC has a hard limitation: **`list` on cluster-scoped resources is all-or-nothing**. There is no native way to express "list namespaces, but only those labeled `tenant: oil`." Either Alice has `list namespaces` cluster-wide, in which case `kubectl get namespaces` returns everyone's namespaces (including `gas-prod`, `kube-system`, `flux-system`), or she does not, in which case `kubectl get namespaces` returns `Forbidden` and her tooling breaks.

`capsule-proxy` is a reverse proxy that sits in front of the apiserver and rewrites that single dimension:

| Request through proxy | What proxy does |
|---|---|
| `GET /api/v1/namespaces` | Calls upstream apiserver as the proxy's SA, then **filters response** to only namespaces where the request subject is an owner. |
| `GET /api/v1/nodes` | Filters to nodes matching the requesting tenant's `nodeSelector` (relevant when `nodes` webhook is enabled). |
| `GET /api/storage.k8s.io/v1/storageclasses` | Filters to those listed in `Tenant.spec.storageClasses.allowed`. |
| `GET /api/networking.k8s.io/v1/ingressclasses` | Filters to `Tenant.spec.ingressOptions.allowedClasses`. |
| `GET /api/v1/persistentvolumes` | Filters to PVs owned by the tenant. |
| Any namespaced read (`GET /api/v1/namespaces/oil-prod/pods`) | Passed through transparently — RBAC at the namespaced layer is sufficient. |

**Authentication modes** (`capsule-proxy` Helm `authPreferredTypes`):
- **`BearerToken`** — proxy does a `TokenReview` against kube-api to identify the user. Default and simplest.
- **`TLSCertificate`** — client presents an X509 cert; proxy reads the CN/O.
- **OIDC** — through `oidcUsernameClaim` (default `preferred_username`); requires an OIDC issuer be configured at kube-api.

**Tenant kubeconfig (token-based, default)** — the canonical shape:

```yaml
apiVersion: v1
kind: Config
clusters:
- cluster:
    server: https://capsule-proxy.capsule-system:9001
    certificate-authority-data: <proxy CA, base64>
  name: spoke-capsule-via-proxy
contexts:
- context:
    cluster: spoke-capsule-via-proxy
    user: alice
  name: alice@oil
current-context: alice@oil
users:
- name: alice
  user:
    token: <alice bearer token, 24h+ JWT>
```

The proxy validates the bearer token via `TokenReview` (so the token must be one kube-api accepts — typically a `ServiceAccount` token). The Capsule community provides a `proxy-kubeconfig-generator` utility and a `hack/create-user.sh` script for cert-based onboarding; for the POC, **bearer-token via SA tokens is the path of least resistance** and avoids OIDC scope.

---

## Resource Isolation: Automatic vs Opt-in

| Mechanism | Auto-injected per tenant namespace? | Source of truth |
|---|---|---|
| `ResourceQuota` (aggregated across tenant NS) | **Yes** | `Tenant.spec.resourceQuotas.items[]`. Controller materializes one `ResourceQuota` object per item, per namespace, with names like `capsule-<tenant>-<index>`. |
| `LimitRange` per tenant namespace | **Yes** | `Tenant.spec.limitRanges.items[]`. One `LimitRange` per item, per namespace. |
| `RoleBinding` for tenant owner (cluster-admin in NS) | **Yes** | Implicit in `spec.owners[]`. |
| `RoleBinding` from `additionalRoleBindings` (e.g., `view` for auditors) | **Yes** | `Tenant.spec.additionalRoleBindings[]`. |
| `NetworkPolicy` | **No, opt-in** | Two paths: (a) the operator's `/networkpolicies` validating webhook can prevent tenants from deleting policies, but does not create them; (b) `GlobalTenantResource` with a `tenantSelector` + raw `NetworkPolicy` resources is the recommended way to fan out network policy to all matching tenants. |
| Default `PriorityClass` / `RuntimeClass` / `IngressClass` / `StorageClass` mutation | **Yes (mutating webhook)** | `Tenant.spec.{priorityClasses,runtimeClasses,ingressOptions.allowedClasses,storageClasses}.default`. |
| Ingress hostname collision detection | **Yes (validating webhook)** | `Tenant.spec.ingressOptions.hostnameCollisionScope: Tenant\|Cluster\|Namespace\|Disabled`. |
| `forceTenantPrefix` | **No, opt-in** | When set, namespace name must start with `<tenant>-`. |

---

## Multi-Tenant Flux Reconciliation

### What Changes for a Tenant-Scoped Kustomization

A standard cluster-admin Flux `Kustomization` looks like:

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: my-app
  namespace: flux-system
spec:
  interval: 5m
  sourceRef:
    kind: GitRepository
    name: my-app
  path: ./deploy
  prune: true
  # No serviceAccountName → runs as kustomize-controller's SA = cluster-admin
```

A **tenant-scoped** one differs in three ways:

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: oil-app
  namespace: oil-prod                              # (1) lives IN the tenant namespace
spec:
  interval: 5m
  sourceRef:
    kind: GitRepository
    name: oil-git
    namespace: oil-prod                            # (2) sourceRef stays IN the tenant ns
                                                   # (--no-cross-namespace-refs=true denies otherwise)
  path: ./deploy
  prune: true
  serviceAccountName: gitops-reconciler            # (3) impersonates the tenant SA
                                                   # gitops-reconciler is registered as
                                                   # spec.owners[].kind=ServiceAccount on Tenant
```

The flags on the Flux **controllers** that make the difference (set at bootstrap, in `flux-system/kustomization.yaml`):

| Flag | Applied to | What it enforces |
|---|---|---|
| `--default-service-account=gitops-reconciler` | kustomize-controller, helm-controller | Any tenant Kustomization without explicit `serviceAccountName` impersonates `gitops-reconciler` in its own namespace — never the controller's cluster-admin SA. |
| `--no-cross-namespace-refs=true` | kustomize-controller, helm-controller, notification-controller, image-reflector-controller, image-automation-controller | A `sourceRef` / `secretRef` / `decryption.secretRef` cannot cross namespaces. Kills "Alice points at Bob's GitRepository." |
| `--no-remote-bases=true` | kustomize-controller | Kustomize cannot pull `bases:` from remote URLs. Forces all source to come from a `GitRepository` Flux already vouched for. |

Source: [Flux multi-tenancy lockdown](https://fluxcd.io/flux/installation/configuration/multitenancy/).

### Three Patterns for Multi-Tenant Flux

| Pattern | Repo layout | Who owns the tenant Kustomization | Best for |
|---|---|---|---|
| **Hub-managed tenant** (single repo, platform-admin authors everything) | One repo: `clusters/`, `tenants/`, `infrastructure/`. Platform admin commits all tenant Kustomizations. | Platform admin. | Small orgs, POCs, where tenants don't have their own git workflows. **POC choice.** |
| **Tenant self-served** (tenant owns their own GitRepository) | Two repos. Platform admin commits a `Kustomization` that points at `tenants/oil/` which contains a `GitRepository` for the oil team. The tenant team commits to *their* repo; Flux sees changes through the platform-admin-owned `GitRepository` resource. | Platform admin owns RBAC/quota; tenant owns workload manifests. | Real production multi-team setups. |
| **Hybrid (clastix/flux2-capsule-multi-tenancy)** | Like self-served, but the tenant's `Kustomization` runs through capsule-proxy via a `kubeConfig` Secret containing a kubeconfig that points to `https://capsule-proxy:9001` with the tenant SA's token. Flux thus reconciles the tenant's content as the tenant, end-to-end. | Tenant SA. | The most isolated, hardest to set up. **Not recommended for POC.** |

Sources: [`fluxcd/flux2-multi-tenancy`](https://github.com/fluxcd/flux2-multi-tenancy), [`projectcapsule/capsule` Flux guide](https://projectcapsule.dev/docs/guides/use-fluxcd/), [`clastix/flux2-capsule-multi-tenancy`](https://github.com/clastix/flux2-capsule-multi-tenancy).

### POC Recommendation: Hub-Managed Tenant

The POC should adopt **hub-managed tenant**. Reasons:

1. The Karyon hub-only Flux invariant (ADR-004) already places Flux on `hub-flux` reconciling to `spoke-capsule` via `spec.kubeConfig`. The tenant Kustomization fits naturally into that flow.
2. The flag patches (`--default-service-account` / `--no-cross-namespace-refs` / `--no-remote-bases`) are a single bootstrap kustomize patch — already a familiar pattern from v0.18 phase 3.
3. The hybrid pattern's `proxy-kubeconfig-generator` adds a third moving part (proxy-kubeconfig Secret rotation) without answering the graduation question better.
4. It still demonstrates real isolation: a tenant Kustomization in `oil-prod` with `serviceAccountName: gitops-reconciler` cannot reach `gas-prod` and cannot escalate.

---

## Webhook Surface — What Capsule Installs

Per the patch reference in `DEVELOPMENT.md`, Capsule installs **9 webhook endpoints**, each as a separate webhook in the `ValidatingWebhookConfiguration` and/or `MutatingWebhookConfiguration`:

| Webhook | Kind | Default failurePolicy | What it enforces |
|---|---|---|---|
| `/tenants` | Validating | `Fail` | Validity of `Tenant` CR itself (no orphaned namespaces, ownership rules). |
| `/namespaces` | Validating | `Fail` | Tenant ownership of namespace creates; `forceTenantPrefix`; `namespaceOptions.quota`; required/forbidden labels & annotations. |
| `/pods` | Validating + Mutating | `Fail` | Pod conforms to allowed `priorityClasses`, `runtimeClasses`, `nodeSelector`, `imagePullPolicy`, registry rules. Mutating injects defaults + `podOptions` labels. |
| `/services` | Validating | `Fail` | `serviceOptions.allowedTypes` (block NodePort/LoadBalancer/ExternalName by default), `externalIPs` allow-list. |
| `/persistentvolumeclaims` | Validating + Mutating | `Fail` | PVC `storageClassName` is in `Tenant.spec.storageClasses.allowed`. Mutating injects default storage class. |
| `/ingresses` | Validating + Mutating | `Fail` | `ingressClassName` allowed; hostnames in `allowedHostnames`; `hostnameCollisionScope`; wildcard rule. Mutating injects default ingressClass. |
| `/networkpolicies` | Validating | `Fail` | Prevents tenants from **deleting** the operator-managed NetworkPolicies. |
| `/nodes` | Validating | `Fail` (off by default) | When enabled, restricts node-label tampering (relevant only if tenants get node access). |
| `/cordoning` | Validating | `Fail` | When `Tenant.spec.cordoned: true`, blocks all CREATE/UPDATE/DELETE of namespaced resources in tenant namespaces — used to "freeze" a tenant for incident response. |

**`failurePolicy: Fail` semantics — what happens when capsule-controller is down:**

- New namespace creates from a tenant owner: **rejected** (the `/namespaces` webhook is unreachable, request fails at admission).
- New pod creates in a tenant namespace: **rejected** (the `/pods` webhook is unreachable). This is exactly the behavior reported in [`projectcapsule/capsule#143`](https://github.com/projectcapsule/capsule/issues/143).
- New `Tenant` CR: **rejected**.
- **Cluster-admin operations on system namespaces** (e.g., `kube-system`, `flux-system`): **also rejected** if the webhook's `namespaceSelector` matches. This is mitigated by `manager.options.ignoreUserWithGroups: [system:masters]` and by webhook `namespaceSelector` carving out the `capsule.clastix.io/tenant: Exists` filter — but it is a real foot-gun. The Karyon POC must verify cluster admin can still recover the cluster when capsule-controller is down.

The POC must **observe** this on purpose: scale capsule-controller to 0, attempt a tenant pod create, observe the rejection, scale back up, observe recovery. Anything else risks shipping a graduation ADR that says "adopt" without understanding the failure mode.

---

## Tenant Teardown Semantics

`kubectl delete tenant oil` does — per the docs — cascade-delete all owned namespaces and the resources inside them. This is **destructive and irreversible** unless `Tenant.spec.preventDeletion: true` is set.

What gets cleaned up automatically:
- All namespaces labeled `capsule.clastix.io/tenant: oil` (cascade via owner refs).
- `ResourceQuota`, `LimitRange`, `RoleBinding` objects inside those namespaces (deleted with the namespace).
- The Tenant CR itself.

**What can get stranded** — the POC should specifically check:
- **`PersistentVolumes`** previously bound to PVCs in tenant namespaces. PVs are cluster-scoped and outlive their PVCs depending on `reclaimPolicy: Retain` vs `Delete`. Capsule does not garbage-collect cluster-scoped PVs.
- **`ClusterRole`/`ClusterRoleBinding`** that platform admin manually created scoped to the tenant. Capsule only manages what it materialized; admin-created cluster-scoped resources persist.
- **`GlobalTenantResource`** outputs (e.g., NetworkPolicies pruned by `pruningOnDelete: true` if set; otherwise orphan).
- **Flux `GitRepository` / `Kustomization` resources** in tenant namespaces — deleted with the namespace, but their Flux inventory of *applied resources outside the tenant namespace* (if any leaked through `--no-cross-namespace-refs=false` misconfig) would persist as orphans.
- **External cloud resources** (volumes, load balancers from `Service type: LoadBalancer`) — Kubernetes garbage-collects per the cloud controller; a local k3d POC won't have any.

The POC delete observable: after `kubectl delete tenant oil`, run `kubectl get all -A -l capsule.clastix.io/tenant=oil` and verify the result is empty.

---

## Negative RBAC Tests (Required Falsifiers)

These are the tests that must pass for the POC to graduate to "adopt." Each is observable via a one-liner `kubectl auth can-i` or a real CRUD attempt; bats tests can wrap each.

| # | Attack / Falsifier | Concrete test | Expected result |
|---|---|---|---|
| N1 | Tenant owner reads cross-tenant pods | `kubectl --kubeconfig=alice.kubeconfig get pods -n gas-prod` | `Forbidden` (RBAC denial in upstream apiserver, since `additionalRoleBindings` only target oil-* namespaces). |
| N2 | Tenant owner LIST cluster-wide | `kubectl --kubeconfig=alice.kubeconfig get pods --all-namespaces` | Returns only oil-* namespace pods. Tests both proxy filtering (for namespace LIST) and downstream RBAC. |
| N3 | Tenant owner reads other tenant's secrets | `kubectl --kubeconfig=alice.kubeconfig get secret -n gas-prod` | `Forbidden`. |
| N4 | Tenant owner gets cluster-admin escalation via ClusterRoleBinding | `kubectl --kubeconfig=alice.kubeconfig create clusterrolebinding evil --clusterrole=cluster-admin --user=alice` | `Forbidden` (alice has no rights at cluster scope to create CRBs). |
| N5 | Tenant owner creates namespace outside tenant prefix (with `forceTenantPrefix: true`) | `kubectl --kubeconfig=alice.kubeconfig create namespace evil` | Rejected by `/namespaces` validating webhook with prefix violation. |
| N6 | Tenant owner exceeds namespace quota | Create `oil-1`..`oil-N+1` where N is `namespaceOptions.quota` | The N+1th rejected by webhook with quota violation. |
| N7 | Tenant pod uses disallowed registry | `kubectl --kubeconfig=alice.kubeconfig run x --image=docker.io/library/nginx -n oil-prod` (when `rules[].enforce.registries` allow-lists `harbor.example.io/.*` only) | Rejected by `/pods` validating webhook. |
| N8 | Tenant owner LIST nodes via direct apiserver (bypass proxy) | `kubectl --kubeconfig=alice-direct.kubeconfig get nodes` (kubeconfig points at `:6443` directly) | `Forbidden` if the user's only ClusterRoleBindings are `additionalRoleBindings` (namespace-scoped). Verifies that going around the proxy doesn't grant *more* than the proxy filtered — proxy is for filtering not authorizing. |
| N9 | Tenant owner gets nodes through proxy | `kubectl --kubeconfig=alice.kubeconfig get nodes` | Returns only nodes matching `Tenant.spec.nodeSelector` (or empty if none — depends on `nodes` webhook + proxy filter config). |
| N10 | Tenant Kustomization sourceRef points at another tenant's GitRepository | Author `Kustomization` in `oil-prod` with `sourceRef: { name: gas-git, namespace: gas-prod }`, push, observe Flux | Reconciliation fails with cross-namespace-refs denied (`--no-cross-namespace-refs=true`). |
| N11 | Tenant Kustomization without `serviceAccountName` | Author `Kustomization` in `oil-prod` without `spec.serviceAccountName`, with manifests that need permissions outside tenant | Reconciliation impersonates `gitops-reconciler` (the `--default-service-account`), and the apply fails with RBAC denial — never silently uses kustomize-controller's privileges. |
| N12 | Webhook-down recovery | `kubectl scale deploy capsule-controller-manager -n capsule-system --replicas=0`; attempt tenant pod create; observe rejection; scale back to 1; verify recovery | First create returns admission-webhook-error; second succeeds after pod ready. |

---

## Table Stakes (with Observable Success Signals)

Twelve features. Each MUST validate during the POC. Failure on any single one means the POC cannot graduate to "adopt" without follow-up work.

| # | Feature | Complexity | Depends on | Observable success signal |
|---|---|---|---|---|
| TS-01 | **`spoke-capsule` k3d cluster created and persistent (NOT in `task rebuild`)** | S | `KARYON POC MOUNT` sentinel-guarded patch surface from milestone; preflight + create-clusters extensions | `k3d cluster list` shows `spoke-capsule`; `task rebuild` output does not include `spoke-capsule` create/destroy; cluster persists across `task rebuild`. |
| TS-02 | **Capsule operator installed via Flux HelmRelease on `hub-flux`, reconciling to `spoke-capsule`** | M | TS-01; existing hub-only Flux (ADR-004) | `kubectl --context=k3d-hub-flux get helmrelease -n flux-system capsule -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'` returns `True`; `kubectl --context=k3d-spoke-capsule get pods -n capsule-system -l app.kubernetes.io/name=capsule` shows `Running`. |
| TS-03 | **`capsule-proxy` installed and reachable** | M | TS-02 | `kubectl --context=k3d-spoke-capsule get svc -n capsule-system capsule-proxy` shows `:9001` ClusterIP; `kubectl port-forward svc/capsule-proxy 9001:9001 -n capsule-system` then `curl -k https://localhost:9001/healthz` returns 200. |
| TS-04 | **Two Tenant CRs (`oil`, `gas`) with distinct owners** | S | TS-02 | `kubectl get tenants` shows `oil` and `gas`; `kubectl get tenant oil -o jsonpath='{.spec.owners[0].name}'` returns `alice`; `gas`'s returns `bob`. |
| TS-05 | **Tenant owner can self-serve namespaces inside tenant** | S | TS-04 | `kubectl create namespace oil-prod --as=alice --as-group=projectcapsule.dev` succeeds; `kubectl get namespace oil-prod -o jsonpath='{.metadata.labels.capsule\.clastix\.io/tenant}'` returns `oil`. |
| TS-06 | **ResourceQuota and LimitRange auto-materialized in tenant namespace** | S | TS-05 | `kubectl get resourcequota -n oil-prod` shows a `capsule-oil-*` quota object reflecting the `Tenant.spec.resourceQuotas.items[0]`; same for `kubectl get limitrange -n oil-prod`. |
| TS-07 | **Positive RBAC: tenant owner can do legitimate ops in own namespace** | S | TS-05 | `kubectl auth can-i create pods -n oil-prod --as=alice --as-group=projectcapsule.dev` returns `yes`; `kubectl run smoke --image=nginx -n oil-prod --as=alice` succeeds. |
| TS-08 | **Negative RBAC: cross-tenant access denied** | S | TS-04, TS-05 | All of N1, N2, N3, N4 from the negative-RBAC table return the expected `Forbidden`. Bats wraps `kubectl auth can-i ... --as=alice` against gas-* namespaces. |
| TS-09 | **Tenant kubeconfig routes through capsule-proxy (NOT direct apiserver)** | M | TS-03, TS-04 | `cat alice.kubeconfig \| yq '.clusters[0].cluster.server'` returns `https://...:9001` (proxy port), not `:6443`; `kubectl --kubeconfig=alice.kubeconfig get namespaces` returns ONLY `oil-*` namespaces (proves proxy filtered LIST). |
| TS-10 | **Flux tenant-scoped Kustomization reconciles as tenant SA** | L | TS-02, TS-04, ADR-004 (hub-only Flux); requires `--default-service-account`/`--no-cross-namespace-refs` patches | A test `Kustomization` in `oil-prod` with `serviceAccountName: gitops-reconciler` reaches `Ready=True`; same Kustomization with cross-tenant `sourceRef` reaches `Ready=False` with cross-namespace-refs error (proves N10). |
| TS-11 | **Capsule webhook failure observed and recoverable** | M | TS-02 | Test N12 from the negative-RBAC table: scale capsule-controller to 0 → tenant pod create rejected with admission-webhook error → scale to 1 → tenant pod create succeeds. Bats captures both states. |
| TS-12 | **`kubectl delete tenant <name>` clean teardown verified** | S | TS-04, TS-05 | After `kubectl delete tenant oil`, `kubectl get namespace -l capsule.clastix.io/tenant=oil` returns empty; `kubectl get all -A -l capsule.clastix.io/tenant=oil` returns empty. PV stranding (if any in POC) explicitly noted in graduation ADR. |

---

## Differentiators (Inform Adopt-vs-Defer; Not Required)

Eight features. Each is valuable for the graduation ADR signal but absence does not block "adopt." Validate as time permits.

| # | Feature | Value Proposition | Complexity | Notes / Success signal |
|---|---|---|---|---|
| DF-01 | **Aggregated `ResourceQuota` across multiple tenant namespaces** | Proves Capsule's promise that quota is per-tenant, not per-namespace. Big distinguisher vs vanilla namespace + RoleBinding. | M | Create `oil-prod` and `oil-staging`; the tenant's CPU quota is 4 cores. Run a 3-core pod in `oil-prod`, then a 2-core pod in `oil-staging` — second is rejected by quota. |
| DF-02 | **`ingressOptions.allowedHostnames` + `hostnameCollisionScope: Tenant`** | Validates Capsule's "fair share" of an external hostname like `*.lab.example.com`. Demonstrates real-world ingress isolation. | M | Tenant `oil` allows `oil.example.com`; Bob attempts an Ingress with `host: oil.example.com` in `gas-prod` → rejected by `/ingresses` webhook. |
| DF-03 | **`forceTenantPrefix: true` and `preventDeletion: true`** | Operational hygiene knobs that protect tenant integrity in production-flavored ops. Cheap to test. | S | Alice `kubectl create namespace evil` rejected when prefix forced; admin `kubectl delete tenant oil` rejected when `preventDeletion: true`. |
| DF-04 | **`Tenant.spec.cordoned: true` (admin freeze of a tenant)** | Useful incident-response knob. Proves Capsule is not just about onboarding but full lifecycle. | S | After `kubectl patch tenant oil --type=merge -p '{"spec":{"cordoned":true}}'`, alice's `kubectl run` in oil-prod is rejected by `/cordoning` webhook. |
| DF-05 | **`GlobalTenantResource` for fan-out (e.g., default deny NetworkPolicy)** | Demonstrates platform-admin pattern for cluster-wide policy without per-tenant duplication. | M | A `GlobalTenantResource` with `tenantSelector: {requires-network-policy: "true"}` creates a `default-deny-egress` NetworkPolicy in all matching tenants' namespaces; `pruningOnDelete: true` removes it on tenant unlabel. |
| DF-06 | **`additionalRoleBindings` with non-owner role (e.g., `view` for auditor group)** | Shows multi-role tenancy. Useful for "PM has view, devs have edit" pattern. | S | Tenant CR adds `additionalRoleBindings: [{clusterRoleName: view, subjects: [{kind: Group, name: auditors}]}]`; `kubectl auth can-i list pods -n oil-prod --as=audit-bot --as-group=auditors` returns `yes`; create returns `no`. |
| DF-07 | **Multi-spoke Flux fan-out via `kubeConfig` Secret (existing Karyon pattern)** | Validates that the v0.18 hub→spoke `spec.kubeConfig` invariant survives Capsule. Reuse, not new tech. | S | `Kustomization` on hub-flux with `spec.kubeConfig.secretRef.name: spoke-capsule-kubeconfig` reconciling Capsule HelmRelease into spoke-capsule already proves this. |
| DF-08 | **Capsule-proxy bearer-token auth via ServiceAccount tokens** | Avoids OIDC; demonstrates the simplest possible tenant onboarding for the lab. | S | A SA `alice-sa` in `oil-system` is added to `Tenant.spec.owners[].kind=ServiceAccount`; the SA's token (24h+ projected token) is embedded in `alice.kubeconfig`; `kubectl --kubeconfig=alice.kubeconfig get ns` returns only `oil-*`. |

---

## Anti-Features (Out of Scope for v0.19 POC)

Ten features. Each is genuinely valuable in production Capsule but **out of scope** for this POC. Mirrors the v0.19 "Out of Scope" list in `PROJECT.md` plus Capsule-specific traps.

| Anti-feature | Why Tempting | Why Wrong For This POC | What To Do Instead |
|---|---|---|---|
| **OIDC issuer (Dex / Keycloak) for tenant auth** | "Real" auth feels more credible. | OIDC issuer adds a whole identity service to install + a chart of CRDs; doubles the milestone scope. The POC's auth question is "does the boundary hold for *some* identity," not "is OIDC integration smooth." | Use `ServiceAccount` tokens. The OIDC integration question can be a **future POC**. (Already deferred in `PROJECT.md`.) |
| **Production ingress + cert-manager + real TLS** | Tenants "should" have real ingress hostnames. | The POC validates `ingressOptions` admission-policy enforcement, not actual traffic flow. cert-manager + a real DNS hostname on a local k3d lab is wasted complexity. | Port-forward / NodePort. (Already deferred in `PROJECT.md`.) |
| **Capsule installed on `hub-flux` itself** | "Make the lab self-tenant." | Couples the POC graduation question to the entire control-plane invariant. ADR-004 (hub-only Flux) becomes harder to reason about. | Capsule on `spoke-capsule` only. Hub-flux Capsule is a separate future POC. (Already deferred in `PROJECT.md`.) |
| **Multi-spoke tenant federation (one tenant spans `spoke-apps` + `spoke-ml` + `spoke-capsule`)** | "Tenants should be cluster-aware." | Capsule has no native cross-cluster Tenant. Doing this is custom work and tests something Capsule doesn't claim. | Single-spoke tenants. (Already deferred in `PROJECT.md`.) |
| **`ResourcePool` + `ResourcePoolClaim`** | "Cluster-wide quota with dynamic allocation" sounds powerful. | A separate CRD model with its own webhook (`/resourcepools/claims`); orthogonal to baseline tenant isolation. Adds 2-3 plans of complexity. | Plain `Tenant.spec.resourceQuotas`. ResourcePool can be a future POC if quota fairness across tenants becomes a real need. |
| **Gateway API tenancy (`gatewayOptions.allowedClasses`)** | Looks modern. | Requires a Gateway API CRD set + an implementation (Istio / Contour) installed on the spoke; massively expands scope. | Stick to `ingressOptions`; Gateway API is adjacent and can be a future POC. |
| **`runtimeClasses: [gvisor, kata]` enforcement** | Pod sandboxing is appealing. | gVisor / Kata require the underlying container runtime to support them; k3d/k3s on WSL2 doesn't ship those runtimes; nothing to test. | Skip. |
| **Full Pod Security Admission (PSA) + admission-policy stack** | "Make the cluster secure." | Capsule already provides admission-policy; layering PSA, OPA Gatekeeper, or Kyverno on top is a separate v0 line. | The POC is "is Capsule sufficient," not "is Capsule + Kyverno better." Defer. |
| **Real network-policy baseline (default-deny + per-tenant overlays)** | "Tenant traffic should be isolated." | NetworkPolicy in k3d/k3s requires the network plugin to enforce it (k3s ships a CNI that does, but verifying actual traffic isolation is a network-plumbing task, not a Capsule task). | Validate that `GlobalTenantResource` *can* fan out a NetworkPolicy (DF-05) without verifying actual packet drop. Real packet-level enforcement is a future POC. |
| **"Capsule replaces all RBAC"** | Easy mental shortcut. | Capsule **layers on top of** Kubernetes RBAC; it doesn't replace it. Misunderstanding this leaks tenants into each other or convinces graduates the POC tested something it didn't. The POC must be explicit: native RBAC denies cross-tenant; Capsule automates the boundary. | Document this in the graduation ADR's "What we proved / what we did not prove." |

---

## Feature Dependencies

```
TS-01 (spoke-capsule cluster)
   └── TS-02 (Capsule operator HelmRelease)
          ├── TS-03 (capsule-proxy)
          ├── TS-04 (Tenant CRs)
          │      ├── TS-05 (owner self-serves NS)
          │      │      ├── TS-06 (ResourceQuota auto-injection)
          │      │      ├── TS-07 (positive RBAC)
          │      │      └── TS-08 (negative RBAC)  ←-- depends on TS-04 + TS-05
          │      ├── TS-09 (proxy-routed kubeconfig)  ←-- depends on TS-03
          │      ├── TS-10 (Flux tenant Kustomization)  ←-- depends on TS-02 + flux flag patches
          │      └── TS-12 (delete tenant teardown)
          └── TS-11 (webhook failure obs)

DF-01 ── enhances ── TS-06   (ResourceQuota aggregated across NS)
DF-02 ── enhances ── TS-04   (ingressOptions hostname collision)
DF-03 ── enhances ── TS-04, TS-12   (forceTenantPrefix, preventDeletion)
DF-04 ── enhances ── TS-04   (cordoned)
DF-05 ── enhances ── TS-06   (GlobalTenantResource fan-out)
DF-06 ── enhances ── TS-08   (additionalRoleBindings non-owner)
DF-07 ── reuses ──── ADR-004 (multi-spoke Flux fan-out via kubeConfig)
DF-08 ── enhances ── TS-09   (SA token auth)

KARYON POC MOUNT ── precedes ── TS-01
                              (sentinel-guarded patch surface for ALL POCs, not just Capsule)

Flux flag patches (--default-service-account, --no-cross-namespace-refs, --no-remote-bases)
   └── precedes ── TS-10
   └── may impact ── existing v0.18 root Kustomization (carefully scoped to tenant namespaces only,
                     OR applied cluster-wide with verification that v0.18 root still reconciles)
```

### Dependency Notes

- **`KARYON POC MOUNT` precedes everything else.** This is the generic external-POC sentinel-guarded patch surface (mirror of `KARYON SPOKES MOUNT` from v0.18). It must be designed first because it is *not* Capsule-specific — it is the seam any future POC (e.g., a Knative POC, an Istio POC) will hook into. Designing it inside-out from Capsule risks coupling the seam to Capsule shape.
- **TS-10 (Flux tenant Kustomization) is the highest-risk single requirement** because it touches the v0.18 Flux bootstrap surface. The flag patches must be applied carefully: `--no-cross-namespace-refs=true` cluster-wide could break a v0.18 cross-namespace ref the team didn't notice. Mitigation: scope the flag patches to a tenant-aware operator-side `CapsuleConfiguration` if available, or apply cluster-wide and rerun the v0.18 health-check as a regression gate.
- **TS-11 (webhook failure observation) is non-optional but easy to skip mentally.** The `failurePolicy: Fail` semantics turn the cluster brittle when capsule-controller is down. Any "adopt" recommendation that does not include observed recovery is incomplete.
- **TS-12 (tenant teardown) is the cheapest test of the boundary.** A clean delete proves Capsule's owner refs are wired correctly; stranded resources flag misconfigurations early.

---

## MVP Definition (Mapped to Phases)

The features map naturally onto a 4-phase POC. Each phase ends with a verifiable artifact.

### Phase 1 — POC Onboarding Seam (`KARYON POC MOUNT` + `spoke-capsule`)

- [x] TS-01 — `spoke-capsule` cluster, persistent, NOT in `task rebuild`
- [ ] (precedes TS-01) — `KARYON POC MOUNT` sentinel-guarded patch surface in `Taskfile.yml` + `scripts/`
- [ ] preflight extensions for the new cluster (port 6446 free, registered apiserver SAN, etc.)

**Phase artifact:** `task pocs:capsule-up` creates `spoke-capsule` and registers it as a Flux spoke, idempotently, without affecting `task rebuild`.

### Phase 2 — Capsule + Capsule-Proxy Install via Flux

- [ ] TS-02 — Capsule HelmRelease reconciling on hub-flux into spoke-capsule
- [ ] TS-03 — capsule-proxy reachable (port 9001)
- [ ] DF-07 — confirms ADR-004 invariant survives

**Phase artifact:** `kubectl get pods -n capsule-system` on spoke-capsule shows `capsule-controller-manager` and `capsule-proxy` Running; `kubectl get helmrelease capsule -n flux-system` on hub-flux shows `Ready=True`.

### Phase 3 — Tenants, Owners, Positive + Negative RBAC, Proxy Kubeconfigs

- [ ] TS-04 — two tenants `oil` and `gas`
- [ ] TS-05 — owners self-serve namespaces
- [ ] TS-06 — ResourceQuota / LimitRange auto-injection
- [ ] TS-07 — positive RBAC
- [ ] TS-08 — negative RBAC (N1-N9 from the negative table)
- [ ] TS-09 — tenant kubeconfigs route through capsule-proxy
- [ ] DF-08 — SA-token auth (concrete auth path)
- [ ] DF-03 — forceTenantPrefix + preventDeletion (cheap, validate while here)

**Phase artifact:** `tests/capsule/negative-rbac.bats` runs N1-N9 against alice and bob and is fully green; `cat alice.kubeconfig | yq '.clusters[0].cluster.server'` shows port `9001`.

### Phase 4 — Flux Tenant Reconciliation, Webhook Failure, Teardown, Graduation ADR

- [ ] TS-10 — Flux tenant-scoped Kustomization with `serviceAccountName` and the three flag patches
- [ ] N10, N11 — cross-tenant sourceRef denied; default-SA impersonation honored
- [ ] TS-11 — webhook failure observed and recovered
- [ ] TS-12 — `kubectl delete tenant` clean teardown
- [ ] **Graduation ADR** — adopt / defer / reject / another POC, citing each TS-* result

**Phase artifact:** `docs/adr/ADR-006-capsule-graduation.md` — Nygard 4-section, Status: Accepted, with explicit references to bats results and a "what we did not prove" section listing the anti-features.

### Add After Validation (Future POCs / Milestones)

If graduation is "adopt":
- [ ] OIDC issuer + tenant auth (separate POC milestone)
- [ ] Real ingress + cert-manager + tenant TLS (separate milestone)
- [ ] Capsule on hub-flux itself (extension milestone)
- [ ] ResourcePool / ResourcePoolClaim (a quota-fairness milestone)
- [ ] NetworkPolicy fan-out + actual packet-level isolation tests (a network-isolation milestone)

If graduation is "defer" or "reject":
- [ ] ADR documents the reasons; no follow-up scheduled.

---

## Feature Prioritization Matrix

| Feature | User Value (lab-internal: clarity of POC signal) | Implementation Cost | Priority |
|---|---|---|---|
| TS-01 spoke-capsule | HIGH | LOW | P1 |
| TS-02 Capsule HelmRelease | HIGH | MEDIUM | P1 |
| TS-03 capsule-proxy | HIGH | MEDIUM | P1 |
| TS-04 Tenants | HIGH | LOW | P1 |
| TS-05 NS self-serve | HIGH | LOW | P1 |
| TS-06 Quota + LimitRange auto | HIGH | LOW | P1 |
| TS-07 Positive RBAC | HIGH | LOW | P1 |
| TS-08 Negative RBAC | HIGH | LOW | P1 |
| TS-09 Proxy-routed kubeconfig | HIGH | MEDIUM | P1 |
| TS-10 Flux tenant Kustomization | HIGH | HIGH | P1 |
| TS-11 Webhook failure obs | HIGH | MEDIUM | P1 |
| TS-12 Teardown clean | HIGH | LOW | P1 |
| DF-01 Quota aggregation | MEDIUM | MEDIUM | P2 |
| DF-02 Hostname collision | MEDIUM | MEDIUM | P2 |
| DF-03 forceTenantPrefix + preventDeletion | MEDIUM | LOW | P2 |
| DF-04 cordoned | MEDIUM | LOW | P2 |
| DF-05 GlobalTenantResource | MEDIUM | MEDIUM | P2 |
| DF-06 additionalRoleBindings non-owner | MEDIUM | LOW | P2 |
| DF-07 Multi-spoke Flux fan-out (reused) | LOW | LOW | P2 (already proven by v0.18) |
| DF-08 SA-token auth | MEDIUM | LOW | P2 (concrete auth path for the POC) |

---

## Competitor / Alternative Feature Analysis

| Feature | vNamespace Operator | Hierarchical Namespace Controller (HNC) | Capsule (this POC) |
|---|---|---|---|
| Tenant CRD | No (raw NS only) | Sub-namespace CRD (`SubnamespaceAnchor`) | `Tenant` (cluster-scoped) |
| Owner model | RBAC RoleBinding only | Inherits via parent NS | `User`/`Group`/`ServiceAccount` first-class |
| Cluster-scoped LIST filtering | No | No | **`capsule-proxy` (yes)** |
| ResourceQuota across NS | No | Inherits (per-NS) | **Aggregated (yes)** |
| Admission-policy enforcement | No | No | **9 webhooks (yes)** |
| GitOps story | n/a | n/a | **`flux2-capsule-multi-tenancy`, hub-managed pattern documented (yes)** |
| CNCF status | None | CNCF (Sandbox) | **CNCF (Sandbox)** |
| Active development | Variable | Active | **Active** |

The competitor signal is that **Capsule is the most complete CNCF multi-tenancy operator** for the "I have a single cluster and want to share it" use case. HNC is the closest but solves a slightly different problem (namespace hierarchy / inheritance). vNamespace and similar operators stop at namespace lifecycle. The POC question "is Capsule worth adopting" is therefore *not* "Capsule vs alternative operator" but "Capsule vs no operator (raw RBAC + ResourceQuota + manual admission policies)."

---

## Sources

### Authoritative — Context7 `/projectcapsule/capsule` (HIGH confidence)
- [Capsule project README](https://github.com/projectcapsule/capsule)
- [Capsule Helm chart README — webhook configuration, install values](https://github.com/projectcapsule/capsule/blob/main/charts/capsule/README.md)
- [Capsule SELF_ASSESSMENT.md — design rationale, capsule-proxy purpose](https://github.com/projectcapsule/capsule/blob/main/SELF_ASSESSMENT.md)
- [Capsule DEVELOPMENT.md — webhook list (`/cordoning /ingresses /namespaces /networkpolicies /nodes /pods /persistentvolumeclaims /services /tenants`)](https://github.com/projectcapsule/capsule/blob/main/DEVELOPMENT.md)
- [Capsule SECURITY.md — cosign signature verification](https://github.com/projectcapsule/capsule/blob/main/SECURITY.md)

### Authoritative — Capsule project site (HIGH confidence)
- [projectcapsule.dev — landing page (CNCF Sandbox status, framework overview)](https://projectcapsule.dev/)
- [Capsule + Flux integration guide](https://projectcapsule.dev/docs/guides/use-fluxcd/)
- [Capsule tenant enforcement webhooks](https://projectcapsule.dev/docs/tenants/enforcement/)
- [Capsule operating: authentication](https://projectcapsule.dev/docs/operating/authentication/)
- [Capsule proxy docs](https://projectcapsule.dev/docs/proxy/)

### Authoritative — Flux multi-tenancy (HIGH confidence)
- [Flux multi-tenancy lockdown (`--no-cross-namespace-refs`, `--no-remote-bases`, `--default-service-account`)](https://fluxcd.io/flux/installation/configuration/multitenancy/)
- [Flux security best practices — auditing default service account configuration](https://fluxcd.io/flux/security/best-practices)
- [Flux Kustomization — enforcing impersonation](https://fluxcd.io/flux/components/kustomize/kustomizations)
- [`fluxcd/flux2-multi-tenancy` reference repo](https://github.com/fluxcd/flux2-multi-tenancy)

### Authoritative — Hybrid Flux + Capsule pattern (HIGH confidence)
- [`clastix/flux2-capsule-multi-tenancy` — proxy-routed tenant Flux (hybrid pattern)](https://github.com/clastix/flux2-capsule-multi-tenancy)
- [Architecture doc for the hybrid pattern](https://github.com/clastix/flux2-capsule-multi-tenancy/blob/main/docs/ARCHITECTURE.md)

### Real-world / case study (MEDIUM confidence)
- [TomTom Engineering Blog — Kubernetes multi-tenancy with Capsule](https://engineering.tomtom.com/capsule-kubernetes-multitenancy/)
- [pet2cattle — How to make Kubernetes multi-tenant with Capsule (kubeconfig + can-i tests)](https://pet2cattle.com/2025/02/kubernetes-multi-tenant-capsule)
- [DZone — Implementing EKS Multi-Tenancy Using Capsule (Part 1)](https://dzone.com/articles/implementing-eks-multi-tenancy-using-capsule)

### Webhook-down behavior (MEDIUM confidence — corroborates `failurePolicy: Fail` semantics)
- [`projectcapsule/capsule#143` — Capsule pods occasionally become unresponsive](https://github.com/projectcapsule/capsule/issues/143)
- [`gardener/gardener#2779` — Mutating webhook doesn't abide by failurePolicy of Ignore](https://github.com/gardener/gardener/issues/2779)
- [`kubernetes/kubernetes#128162` — Pod admission can fail due to webhooks + context deadline exceeded](https://github.com/kubernetes/kubernetes/issues/128162)

### Karyon project context
- [`/home/rich/code/gsd/karyon/.planning/PROJECT.md` — v0.19 milestone scope, deferred items, ADR-004 hub-only Flux invariant](file:///home/rich/code/gsd/karyon/.planning/PROJECT.md)
- [`/home/rich/code/gsd/karyon/.planning/MILESTONES.md` — v0.18 shipped accomplishments, baseline platform features](file:///home/rich/code/gsd/karyon/.planning/MILESTONES.md)

---

*Feature research for: Capsule multi-tenancy POC (v0.19) — single-spoke isolated POC reconciled hub-only via Flux.*
*Researched: 2026-04-29*
*Confidence: HIGH — Context7 authoritative + Flux + Capsule official docs + multiple production case studies. Two MEDIUM-confidence claims (webhook-down precise behavior under multi-replica capsule-controller HA, and capsule-proxy filter behavior on `nodes` when `nodes` webhook is disabled by default) flagged inline as POC-level falsifiers.*
