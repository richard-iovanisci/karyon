# Capsule Multi-Tenancy + Two-Perspective Demo — Portable Setup Guide

> **Audience:** a coding agent setting up Capsule in a fresh environment.
> **Goal:** stand up a three-tier multi-tenancy model on a Kubernetes cluster and demo it end-to-end
> (provision a tenant → auto-seed a workload → show two privilege perspectives → tear down) **without
> any human identity ever holding `cluster-admin`**.
>
> This describes the *structures and ideas* that worked, not exact file paths. Adapt naming, directory
> layout, and delivery mechanism (GitOps vs. `helm`/`kubectl apply`) to the target env. The pieces and
> their relationships are what matter. Manifests below are trimmed to the load-bearing fields.

---

## 1. What you're building (the mental model)

Three privilege tiers, each a strictly-lower carrier than the one above:

| Tier | Who | Identity | Bound to | Can | Cannot |
|------|-----|----------|----------|-----|--------|
| **1 — Cloud Ops** | infra admins | raw cluster-admin kubeconfig (cloud IAM admin on managed k8s) | `cluster-admin` | everything | — *(out of scope; the point is the tiers below don't inherit this)* |
| **2 — Platform Team** | the team running multi-tenancy | a ServiceAccount (`platform-owner`) + a group (`platform-owners`) | a **narrow** custom ClusterRole | full Tenant lifecycle (create/delete tenants); co-owner break-glass into any tenant namespace | NOT `cluster-admin` — no nodes, CSRs, or ClusterRoleBindings |
| **3 — Tenant Devs** | a tenant's developers | per-tenant SA (`human-tenant-owner`) | a **narrowed** workload-editor ClusterRole | CRUD workloads in own namespaces; exec/logs; read secrets | NO secret writes, NO cross-tenant access, NO RBAC editing |

The demo proves the whole tenant lifecycle (**create → seed → use → delete**) runs entirely from **Tier 2**.

**Two enforcement mechanisms do the work** — keep them distinct, because they're tested differently:
- **Kubernetes RBAC** (ClusterRoles + Capsule-injected per-namespace RoleBindings): enforces *namespaced*
  permissions — what you can do inside a namespace you own, and the hard "no" on namespaces you don't.
- **capsule-proxy** (a reverse proxy tenants route through): enforces *cluster-scoped LIST filtering* —
  turns a forbidden cluster-wide `kubectl get namespaces` into a curated list of only the tenant's own
  namespaces. This is the one thing vanilla RBAC **cannot** express, and the sole reason the proxy exists.

---

## 2. Prerequisites / assumptions

- A working cluster + a cluster-admin kubeconfig for the initial install (Tier 1).
- A way to apply manifests — GitOps (Flux/Argo) or direct `helm install` + `kubectl apply`. The POC used
  GitOps (Flux, hub-spoke: the controller runs on a hub cluster and reconciles onto the target via
  `kubeConfig`), but nothing here requires that topology.
- Two Helm charts from the Capsule project (OCI registry `ghcr.io/projectcapsule/charts`):
  - `capsule` (operator) — CRDs, controller, admission webhooks. POC pinned `0.12.4`.
  - `capsule-proxy` (separate chart, NOT the operator's bundled `proxy.enabled`). POC pinned `0.12.0`.
- `kubectl` with `auth whoami` support, `jq`.

Pick the chart pins to match the cluster's Kubernetes version:

| Kubernetes | Capsule operator | capsule-proxy | Verify with |
|---|---|---|---|
| 1.34+ | `0.12.4` | `0.12.0` | `helm show chart oci://ghcr.io/projectcapsule/charts/capsule --version 0.12.4` |
| 1.33 | latest `0.11.x` | latest `0.11.x` | same `helm show chart` against the 0.11 pin |
| ≤ 1.32 | not supported by current Capsule | — | use Capsule 0.10.x (community-best-effort only) |

The chart's `kubeVersion` field is the source of truth — pin to whatever satisfies it for your cluster's
exact patch version (and then pin by digest — see §5 #2).

---

## 3. Build it, component by component

### 3a. Install the operator (Helm)

Install the `capsule` chart into a `capsule-system` namespace. Load-bearing values (from the POC):

```yaml
# capsule operator — Helm values
tls:
  enableController: true       # built-in self-signed certgen — no cert-manager dependency for a POC
  create: true
certManager:
  generateCertificates: false
crds:
  install: true
replicaCount: 1                # single replica fine for a POC
proxy:
  enabled: false               # capsule-proxy is a SEPARATE release (see 3b)

# ⚠️ THE LOAD-BEARING SETTING — see §5 "Critical gotchas" #1
webhooks:
  hooks:
    namespaces:
      failurePolicy: Fail      # MUST be Fail. Chart default is Fail; do NOT weaken to Ignore.
    # Other hooks MAY be Ignore if you want a POC to tolerate webhook-down on non-critical paths
    # (the POC sets ~13 of them to Ignore as belt-and-suspenders). But `namespaces` specifically
    # must fail-closed, or you get the unrecoverable bootstrap deadlock in §5 #1.
```

**Pin the chart by digest, not just a tag** (see §5 #2).

### 3b. Install capsule-proxy (separate Helm release)

The proxy authenticates a caller's bearer token, looks up which Tenants they own, and **rewrites/filters
cluster-scoped LIST requests** before forwarding to the apiserver. Tenant *and* platform-owner kubeconfigs
point their `server:` at this proxy, not at the apiserver.

```yaml
# capsule-proxy — Helm values (POC)
service:
  type: NodePort          # or LoadBalancer / ClusterIP+Ingress depending on env
  port: 9001
  nodePort: 30443         # the port tenant/platform kubeconfigs target
options:
  listeningPort: 9001
  enableSSL: true
  generateCertificates: true   # controller-less self-signing certgen Job → produces the proxy TLS Secret
  capsuleConfigurationName: default
  additionalSANs:              # serving cert MUST be valid for however clients reach the proxy
    - 127.0.0.1
    - localhost                # for remote access, add the real hostname / LB DNS here
  authPreferredTypes: "BearerToken,TLSCertificate"
certManager:
  generateCertificates: false  # do NOT render cert-manager Issuer/Certificate CRs (no controller in POC)
replicaCount: 1
```

> **Cert gotcha (cost us real time):** `certManager.generateCertificates: true` renders cert-manager
> `Issuer`/`Certificate` CRs that need the **cert-manager controller** to reconcile into the proxy's TLS
> Secret. If you only installed cert-manager *CRDs* (not the controller), those CRs sit forever
> unreconciled and the proxy never gets its cert. Use the chart's controller-less certgen Job instead
> (`options.generateCertificates: true` + `certManager.generateCertificates: false`).
>
> **Cert Secret RBAC gotcha:** the certgen Job needs to *write* the proxy's TLS Secret. The POC had to
> extend the chart's `capsule-proxy` Role with `secrets: [get, create, update, patch]` (via a Helm
> post-render patch) so the Job could create that Secret on a clean install. Check whether your chart
> version already grants this; if the proxy pod is stuck waiting on its TLS volume, this is why.

### 3c. CapsuleConfiguration (singleton)

```yaml
apiVersion: capsule.clastix.io/v1beta2
kind: CapsuleConfiguration
metadata:
  name: default
spec:
  enableTLSReconciler: false
  forceTenantPrefix: true            # cluster-wide default; per-Tenant override nuance in §5 #4
  allowServiceAccountPromotion: true # lets an SA be promoted to tenant owner via labels (GitOps path)
  userGroups:                        # identities Capsule treats as "tenant users" to police + proxy-filter
    - capsule.clastix.io
    - system:serviceaccounts
    - system:authenticated
  protectedNamespaceRegex: "^kube-.*$"
```

> `userGroups` is technically deprecated in v1beta2 (superseded by `spec.users`), but the chart still
> uses it for default group-based owner detection — keep it for compatibility. The three groups above are
> what let SA-token-authenticated identities be recognized as Capsule-owned for proxy LIST behavior.

### 3d. Tier-2 ClusterRole + binding (the Platform Team ceiling)

A **narrow** ClusterRole — enough to run the tenant lifecycle, deliberately missing everything that would
equal cluster-admin:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata: { name: capsule-platform-owner }
rules:
  - apiGroups: ["capsule.clastix.io"]
    resources: ["*"]
    verbs: ["get","list","watch"]
  - apiGroups: ["capsule.clastix.io"]
    resources: ["tenants"]
    verbs: ["create","update","patch","delete"]      # full Tenant lifecycle
  - apiGroups: [""]
    resources: ["namespaces"]
    verbs: ["get","list","watch"]
  - apiGroups: ["apiextensions.k8s.io"]
    resources: ["customresourcedefinitions"]
    verbs: ["get","list","watch"]
  # NO nodes, NO certificatesigningrequests, NO clusterrolebindings, NO "*"/"*"
```

Bind it **dual-subject** — to both the group (impersonation path: `kubectl --as=... --as-group=...`) and
the SA (TokenRequest kubeconfig path) — so either identity carries Tier-2 powers under one ceiling:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata: { name: capsule-platform-owner }
roleRef: { apiGroup: rbac.authorization.k8s.io, kind: ClusterRole, name: capsule-platform-owner }
subjects:
  - { apiGroup: rbac.authorization.k8s.io, kind: Group, name: capsule-platform-owners }
  - { kind: ServiceAccount, name: platform-owner, namespace: capsule-system }
```

(Plus the `platform-owner` ServiceAccount itself in `capsule-system`.)

> **Why a narrow ClusterRole rather than just making the platform group an owner of every Tenant:**
> tenant ownership grants workload-admin powers *inside* tenant namespaces, so using it as the platform
> team's baseline access would blur platform administration with tenant workload administration. The
> narrow ClusterRole keeps the day-to-day Tier-2 surface at "manage Tenant CRs + read Capsule state,"
> and the per-tenant co-ownership in §3f stays a deliberate break-glass add-on rather than the default
> path. (Reusing `cluster-admin` was rejected outright — it defeats the isolation goal and hides the
> real permission set you'd need to reproduce elsewhere.)

### 3e. Tier-3 ClusterRole (the tenant workload-editor)

Narrower than upstream k8s `edit`. The narrowing is **on the verbs**, not wholesale resource removal:
tenants get full CRUD on workloads, but **secrets and PVCs are read-only** and RBAC/quota objects are
absent entirely.

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata: { name: tenant-workload-editor }
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get","list","watch","create","update","patch","delete","deletecollection"]
  - apiGroups: [""]
    resources: ["pods/log"]
    verbs: ["get","list","watch"]
  - apiGroups: [""]
    resources: ["pods/exec","pods/portforward"]
    verbs: ["create"]
  - apiGroups: ["apps"]
    resources: ["deployments","replicasets","statefulsets","daemonsets"]
    verbs: ["get","list","watch","create","update","patch","delete","deletecollection"]
  - apiGroups: ["batch"]
    resources: ["jobs","cronjobs"]
    verbs: ["get","list","watch","create","update","patch","delete","deletecollection"]
  - apiGroups: [""]
    resources: ["services","endpoints"]
    verbs: ["get","list","watch","create","update","patch","delete","deletecollection"]
  - apiGroups: ["discovery.k8s.io"]
    resources: ["endpointslices"]
    verbs: ["get","list","watch","create","update","patch","delete","deletecollection"]
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get","list","watch","create","update","patch","delete","deletecollection"]
  - apiGroups: [""]
    resources: ["persistentvolumeclaims"]
    verbs: ["get","list","watch"]                 # READ-ONLY (PVC creation = platform-team concern)
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get","list","watch"]                 # READ-ONLY ONLY — the key narrowing
  - apiGroups: [""]
    resources: ["events"]
    verbs: ["get","list","watch"]
  # DELIBERATELY ABSENT ENTIRELY: roles/rolebindings, resourcequotas, limitranges,
  # and any write verb on secrets. No path for a tenant to grant itself more.
```

> **Don't omit `secrets` entirely** — tenants legitimately need to *read* secrets their pods mount.
> Omit the **write verbs**. The demo's "create secret → Forbidden" works because `create` is absent here,
> not because the resource is.

This ClusterRole is **not bound directly** — Capsule binds it per-namespace via the Tenant's
`owners[].clusterRoles` field (next section). That's how "narrow but functional, scoped to the tenant's
own namespaces" happens without any cluster-wide binding.

### 3f. Tenant CRs (the ownership model — the heart of it)

A Tenant CR declares who owns it and *what role each owner gets inside the tenant's namespaces*. Capsule
watches this and auto-creates the matching RoleBindings in every tenant namespace.

```yaml
apiVersion: capsule.clastix.io/v1beta2
kind: Tenant
metadata:
  name: alpha
spec:
  forceTenantPrefix: false      # see §5 #4 — controls tenant namespace naming
  owners:
    # GitOps/automation owner — broad, so reconciliation can manage the tenant.
    # Omitting clusterRoles → Capsule applies its defaults [admin, capsule-namespace-deleter].
    - kind: ServiceAccount
      name: system:serviceaccount:<gitops-ns>:<reconciler-sa>

    # Tier-3 HUMAN tenant dev — narrowed to workload-editor
    - kind: ServiceAccount
      name: system:serviceaccount:tenant-alpha:human-tenant-owner
      clusterRoles:
        - tenant-workload-editor          # binds the narrow role, per-namespace, automatically

    # Tier-2 platform team as CO-OWNER — break-glass into this tenant without cluster-admin.
    # clusterRoles OMITTED → Capsule defaults (admin + capsule-namespace-deleter) INSIDE the tenant's
    # namespaces — broader than tenant-workload-editor, but still capped by the narrow cluster-level
    # Tier-2 ClusterRole (§3d). Co-ownership inside tenants ≠ cluster-admin.
    - kind: Group
      name: capsule-platform-owners
    - kind: ServiceAccount
      name: system:serviceaccount:capsule-system:platform-owner

  # Optional per-tenant guardrails Capsule materializes automatically:
  resourceQuotas:
    items:
      - hard: { cpu: "4", memory: 8Gi, pods: "20" }
  limitRanges:
    items:
      - limits:
          - type: Container
            default:        { cpu: 100m, memory: 128Mi }
            defaultRequest: { cpu: 50m,  memory: 64Mi }
  namespaceOptions:
    quota: 3                  # max namespaces this tenant may own
  containerRegistries:
    allowed:
      - docker.io            # MUST include the registry of any GlobalTenantResource seed image (§3g)
      - registry.example.io
```

**Three Tenant-owner rules that all bit the POC:**
- **One Tenant CR carries multiple owners at different privilege levels.** Tier-3 dev →
  `tenant-workload-editor`; Tier-2 platform team → default admin co-ownership for break-glass.
- **Never set `clusterRoles: []` (empty list).** Empty list removes ALL bindings for that owner. To get
  Capsule's defaults, **omit the field**; to set specific roles, list them. `[]` is a silent footgun.
- **The GitOps reconciler must itself be a Tenant owner.** Capsule requires the *namespace assignment* to
  be performed by a Tenant owner — even when the applier already has cluster-admin RBAC. So whatever
  identity your GitOps engine reconciles as (e.g. a `flux-reconciler` SA) must appear in `owners[]`, or
  Capsule rejects the tenant namespace. This is why the POC lists the bootstrap reconciler SA alongside
  the human + platform identities.

Each tenant also needs: its home namespace (e.g. `tenant-alpha`) carrying label
`capsule.clastix.io/tenant: alpha`, and the per-tenant `human-tenant-owner` ServiceAccount.

### 3g. GlobalTenantResource (auto-seed workloads into every tenant)

Cluster-scoped CR; Capsule replicates the items into every namespace whose tenant matches the selector,
within `resyncPeriod`. Great for baseline fixtures (here: a hello-world Deployment + Service).

**Watch the schema shape** — items live under `spec.resources[].rawItems`, *not* a top-level `rawItems`.
Each `resources[]` entry can attach `additionalMetadata` to everything it stamps out:

```yaml
apiVersion: capsule.clastix.io/v1beta2
kind: GlobalTenantResource
metadata: { name: hello-world-seeded }
spec:
  tenantSelector:
    matchLabels: {}              # {} = match ALL tenants. Use real matchLabels to target a subset.
  resyncPeriod: 60s             # propagation SLA window
  pruningOnDelete: true         # delete this CR → remove what it stamped out
  resources:
    - additionalMetadata:
        labels: { your-org/managed-by: capsule-global-tenant-resource }
      rawItems:
        - apiVersion: apps/v1
          kind: Deployment
          metadata: { name: hello-world, labels: { app: hello-world } }
          spec:
            replicas: 1
            selector:
              matchLabels: { app: hello-world }
            template:
              metadata:
                labels: { app: hello-world }
              spec:
                containers:
                  - name: nginx
                    image: docker.io/library/nginx:alpine   # fully-qualified image ref
                    ports: [{ containerPort: 80, name: http }]
                    resources:
                      requests: { cpu: 50m, memory: 64Mi }
                      limits:   { cpu: 100m, memory: 128Mi }
        - apiVersion: v1
          kind: Service
          metadata: { name: hello-world, labels: { app: hello-world } }
          spec:
            type: ClusterIP
            selector: { app: hello-world }
            ports: [{ port: 80, targetPort: http }]
```

> **Immutable-shape gotcha (learned the hard way):** never put a bare `Pod` (or `Job`) in `rawItems`.
> Pod specs are immutable on update, GlobalTenantResource has NO update-skip option, and on every
> resync the controller re-sends the sparse rawItem spec as a full UPDATE — the apiserver rejects it
> (`pod updates may not change fields other than spec.containers[*].image...`) and the controller sits
> in a **permanent exponential-backoff error loop** (up to ~16 min between retries) that masks real
> replication failures and breaks the resync cadence. The workloads still run, so nothing looks broken
> unless you read the controller logs. Seed controller-owned shapes with mutable specs (Deployment,
> StatefulSet, DaemonSet) instead. The karyon POC shipped a bare-Pod seed and only caught the loop in a
> post-ship audit (ADR-008 addendum 2026-07-06).
>
> **Registry allowlist gotcha:** if your Tenant CRs restrict `containerRegistries.allowed`, the seed
> image's registry MUST be on that list or the propagated workload is webhook-rejected. The POC had to
> add `docker.io` for the nginx seed.

When a **new** tenant is provisioned, the seed auto-propagates into it within the resync window — the
"watch a workload appear in a brand-new tenant in <60s" demo moment. (Live-run caveat: if the tenant has
already existed for minutes, `kubectl wait` returns instantly because the pod is already there — to *show*
the live timing, provision and `time kubectl wait` back-to-back.)

### 3h. Identity delivery (kubeconfig minting)

You need a repeatable way to hand out scoped kubeconfigs. Pattern that worked — one small script per
identity type, each producing a kubeconfig whose `server:` is the **capsule-proxy** endpoint and whose CA
is the **proxy's** serving cert:

- **Platform-owner kubeconfig:** `TokenRequest` a token for the `platform-owner` SA → emit a kubeconfig
  pointed at `https://<host>:30443` (the proxy). Identity =
  `system:serviceaccount:capsule-system:platform-owner`.
- **Tenant-owner kubeconfig:** same, for the per-tenant `human-tenant-owner` SA. Also routes through the
  proxy `:30443` so the LIST-filter applies.
- **New-tenant provisioning:** a script run *as the platform-owner kubeconfig* that applies a new Tenant
  CR + its namespace + its `human-tenant-owner` SA, then waits for Capsule to inject the RoleBindings.
  This is the "provision a tenant live" demo action — and it must succeed using only Tier-2 privileges,
  proving the platform team can add tenants without cluster-admin.

> **Proxy cert detail:** the POC's proxy chart writes a TLS Secret with `tls.crt`/`tls.key` keys only (no
> separate `ca.crt`) — the self-signed `tls.crt` *is* the CA root. The mint scripts read `tls.crt` and
> embed it as the kubeconfig's `certificate-authority-data`. Adjust if your proxy uses a real CA chain.

Write minted kubeconfigs to a tmp dir at `0600`; never commit them (add a secret-scan rule for bearer
tokens). Mint **token-only** kubeconfigs (no client cert) — see §5 #3.

---

## 4. Verify it (the 6-act demo)

| Act | Command (as the right identity) | Expect | Proves |
|-----|--------------------------------|--------|--------|
| 2 | `kubectl --kubeconfig=$PO get tenants` | all tenants | Tier-2 oversight |
| 2 | `kubectl --kubeconfig=$PO create clusterrolebinding x --clusterrole=cluster-admin --user=platform-owner` | **Forbidden** | Tier-2 ceiling (can't self-escalate) |
| 3 | provision a new tenant via the platform-owner kubeconfig | tenant + namespace materialize; RoleBindings injected | Tier-2 lifecycle authority |
| 4 | `kubectl -n <new-tenant> wait deployment/hello-world --for=condition=Available --timeout=60s` | Available | GlobalTenantResource auto-seed |
| 5a | `kubectl --kubeconfig=$TENANT get namespaces` | **only that tenant's ns** | capsule-proxy LIST filter |
| 5b | `kubectl --kubeconfig=$TENANT -n <own-ns> exec/logs ...` | works | narrow but functional |
| 5c | `kubectl --kubeconfig=$TENANT -n <own-ns> create secret ...` | **Forbidden** | secret writes dropped |
| 5d | `kubectl --kubeconfig=$TENANT get pods -n <other-tenant>` | **Forbidden** | cross-tenant isolation |
| 5e | `kubectl --kubeconfig=$PO -n <tenant-ns> exec ...` | works | Tier-2 break-glass |
| 6 | `kubectl --kubeconfig=$PO delete tenant <new>` | namespace unmaterializes; others untouched | Tier-2 teardown |

**Which acts test what** (don't conflate them):
- **5a is the ONLY act that tests capsule-proxy.** `namespaces` is cluster-scoped; vanilla RBAC can't do
  "list *some* namespaces." Prove it with an A/B using the **same tenant kubeconfig**, changing only the
  server: through the proxy (`:30443`) it returns a filtered list; pointed straight at the apiserver
  (`--server=https://<apiserver>:<port>`) the same identity gets `Forbidden ... at the cluster scope`.
- **5b–5e are plain RBAC** (Capsule-injected RoleBindings + the narrow ClusterRoles). The proxy is a
  transparent pass-through for them; they'd behave identically against the apiserver directly. (A `get
  pods -A` *would* additionally exercise the proxy's namespaced filter — but the explicit `-n <other>`
  form in 5d trips RBAC first.)

---

## 5. Critical gotchas (hard-won — read before you ship)

**1. The `namespaces` webhook MUST be `failurePolicy: Fail`.**
Capsule's `namespaces.tenants.projectcapsule.dev` *mutating* webhook adds the `ownerReference` that claims
a tenant-labeled namespace for its Tenant CR. If it's `Ignore` and the webhook is briefly unreachable
during cold bootstrap (controller pod still starting / Endpoint not Ready), the apiserver **silently
admits the namespace without the ownerRef**. Result: a labeled-but-unowned namespace → Capsule never
claims it (`Tenant.status.size` stays 0, no RoleBindings, tenant LIST returns empty) → and the companion
*validating* webhook then **blocks all UPDATE/DELETE** on it (label-vs-ownerRef mismatch) → unrecoverable
without bypassing the webhook. `Fail` makes the apiserver reject the premature CREATE so the GitOps engine
retries until the webhook is serving — self-healing. The chart default is `Fail`; **do not weaken this
hook.** *(This is the exact bug we hit. The value key is `webhooks.hooks.namespaces.failurePolicy` —
verify against `helm show values` for your chart version; a sibling key like `namespacePatch` is a no-op.)*
*(Recovery if you hit the deadlock: scale the capsule controller to 0 to disable the webhooks, delete the
orphaned tenant namespaces, scale back up, re-reconcile.)*

**2. Pin Helm charts by digest, not just tag.**
Tags are mutable. Pin the chart ref by `sha256:` digest so a cold rebuild is reproducible and an upstream
re-tag can't silently change webhook config under you.

**3. An empty `--kubeconfig` value silently falls back to admin.**
`kubectl --kubeconfig=$VAR ...` where `$VAR` is unset/empty expands to `--kubeconfig=`, which kubectl
treats as "not provided" → it uses your default admin kubeconfig. Every "should be Forbidden" test then
**false-passes** (runs as cluster-admin). This is the #1 way a demo lies to you. **Guard every scoped
command** — before any "should fail" step, assert the identity:

```bash
kubectl --kubeconfig=$PO auth whoami | grep -q 'platform-owner' \
  && echo "✓ scoped" || echo "✗ admin fallback — fix \$PO"
```

Related: if a tenant kubeconfig carries a client **certificate** (not just a token), the cert
authenticates the TLS connection before the token is read — so it silently runs as whoever the cert is.
Mint **token-only** kubeconfigs for tenants.

**4. `forceTenantPrefix` controls tenant namespace naming.**
With `forceTenantPrefix: true` (a common default), Capsule expects tenant child namespaces named
`<tenant>-<namespace>`. If you want a fixed home-namespace name like `tenant-<name>`, set
`forceTenantPrefix: false` on the **Tenant CR** (it overrides the CapsuleConfiguration default).
Mismatches cause Capsule to reject your namespace assignments. Pick one convention and keep the
CapsuleConfiguration default, the Tenant CRs, and the namespaces you create consistent.

**5. Operator and proxy are two separate charts.**
Don't use the operator chart's bundled `proxy.enabled: true` if you want a specific proxy version /
NodePort / SANs / cert config — install `capsule-proxy` as its own release. Set its serving-cert SANs to
match however clients actually reach it (`127.0.0.1`/`localhost` for local; the real hostname/LB DNS
otherwise), or kubeconfigs fail TLS verification. See the cert + cert-Secret-RBAC gotchas in §3b.

**6. Bootstrap ordering.**
The operator (CRDs + webhooks + controller) must be healthy **before** Tenant CRs and tenant namespaces
are applied. With GitOps, express this as a dependency (the tenant layer depends on the operator layer).
Combined with #1, this is what makes cold bootstrap reliable.

**7. Owners create namespaces with `kubectl create namespace`, not declarative `kubectl apply`.**
`kubectl apply` of a Namespace manifest preflights a cluster-scoped `get` on `namespaces` before it
sends anything — apply needs the live object to compute its merge patch. Capsule's owner model grants
namespace *creation* through admission, not cluster-scoped namespace reads, so for a tenant or platform
owner the preflight fails `Forbidden` and the CREATE is never submitted. The imperative
`kubectl create namespace <name>` issues a bare CREATE, which goes straight through Capsule's admission
webhook and gets assigned to the caller's Tenant. Same manifest content, different request pattern,
opposite outcomes — script provisioning paths with `create`, not `apply`, for namespaces.

---

## 6. Production translation (what a real cut would add)

This is a POC posture. For production (e.g. EKS), the tiers map to: Tier 1 = cloud IAM admin, Tier 2 = an
IRSA-bound role holding the platform-owner ClusterRole, Tier 3 = per-tenant IRSA-bound roles holding
`tenant-workload-editor`. Beyond that you'd want: proper cert management (cert-manager / managed certs)
instead of built-in certgen; HA replicas for controller and proxy; a webhook readiness gate; and real
secret management for the minted kubeconfigs. The cold-bootstrap webhook race (#1) is exactly the class
of edge case a hardened cert + readiness setup removes.
