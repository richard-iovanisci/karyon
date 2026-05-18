# Phase 9: Tenants + Flux Multi-Tenancy Lockdown — Pattern Map

**Mapped:** 2026-04-29
**Files analyzed:** 31 (24 NEW + 7 MODIFIED)
**Analogs found:** 27 / 31 (4 net-new shapes — Capsule Tenant CR + CapsuleConfiguration CR + Kustomize `patches:` block + Flux `serviceAccountName` impersonation field — have NO existing repo analog; planner uses RESEARCH.md §"Code Examples" + §"Gap 4/5/2/3" verbatim)

---

## File Classification

### NEW files (24)

| New File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `pocs/capsule/spoke/config/kustomization.yaml` | Kustomize aggregator (subdir) | declarative; resolved by parent kustomize-build | `pocs/capsule/operator/kustomization.yaml` | exact (peer aggregator) |
| `pocs/capsule/spoke/config/capsuleconfig.yaml` | Capsule CR (CapsuleConfiguration/default singleton) | spoke apply via `poc-capsule-spoke` outer K's kubeConfig | none in repo — RESEARCH §Gap 5 | no-analog (greenfield Capsule CR) |
| `pocs/capsule/spoke/tenants/kustomization.yaml` | Kustomize aggregator (subdir) | declarative | `clusters/hub-flux/spokes/kustomization.yaml` | exact (peer aggregator with subdir refs) |
| `pocs/capsule/spoke/tenants/alpha/kustomization.yaml` | Kustomize aggregator (per-tenant subdir) | declarative | `clusters/spoke-apps/kustomization.yaml` | exact (3-resource per-area aggregator) |
| `pocs/capsule/spoke/tenants/alpha/namespace.yaml` | Namespace (tenant home on spoke) | declarative; spoke apply | `clusters/spoke-apps/namespace.yaml` | exact (Namespace seed) |
| `pocs/capsule/spoke/tenants/alpha/sa.yaml` | ServiceAccount (Flux impersonation principal) | declarative; spoke apply | none in repo — RESEARCH §"Code Examples" lines 855-871 | partial (Namespace pattern transfers; SA shape is canonical k8s) |
| `pocs/capsule/spoke/tenants/alpha/tenant.yaml` | Capsule CR (Tenant alpha) | spoke apply via `poc-capsule-spoke` | none in repo — RESEARCH §Gap 4 | no-analog (greenfield Capsule CR) |
| `pocs/capsule/spoke/tenants/bravo/kustomization.yaml` | Kustomize aggregator (mirror) | declarative | mirror of `alpha/kustomization.yaml` | exact (alpha→bravo substitution) |
| `pocs/capsule/spoke/tenants/bravo/namespace.yaml` | Namespace (mirror) | declarative | mirror of `alpha/namespace.yaml` | exact |
| `pocs/capsule/spoke/tenants/bravo/sa.yaml` | ServiceAccount (mirror) | declarative | mirror of `alpha/sa.yaml` | exact |
| `pocs/capsule/spoke/tenants/bravo/tenant.yaml` | Capsule CR Tenant bravo | spoke apply | mirror of `alpha/tenant.yaml` | exact (alpha→bravo substitution) |
| `pocs/capsule/tenants/kustomization.yaml` | Kustomize aggregator (hub-side tenants) | declarative | `clusters/hub-flux/spokes/kustomization.yaml` | exact (multi-resource aggregator) |
| `pocs/capsule/tenants/alpha.yaml` | Multi-doc YAML: Namespace + GitRepository v1 + Kustomization v1 (with `kubeConfig` + `serviceAccountName` + `dependsOn`) | hub apply (per-tenant namespace) → spoke apply (via inner K's kubeConfig) | `clusters/hub-flux/pocs/capsule-spoke.yaml` (Kustomization with kubeConfig) + `clusters/spoke-apps/namespace.yaml` (Namespace) | role-match (cross-cluster K with kubeConfig); `serviceAccountName` is no-analog |
| `pocs/capsule/tenants/bravo.yaml` | Multi-doc mirror | mirror of alpha.yaml | mirror of `alpha.yaml` | exact (alpha→bravo) |
| `pocs/capsule/tenants/alpha-app/kustomization.yaml` | Pitfall-7 placeholder (`resources: []`) | declarative; resolved by inner K | `pocs/capsule/spoke/kustomization.yaml` (Phase 8 placeholder) | exact (pitfall-7 placeholder pattern) |
| `pocs/capsule/tenants/bravo-app/kustomization.yaml` | Pitfall-7 placeholder mirror | declarative | mirror of `alpha-app/kustomization.yaml` | exact |
| `tests/bats/tenants-01-static-tenant-cr.bats` | Static contract bats (TEN-01 — yq on Tenant CR shape) | yq-eval on committed YAML | `tests/bats/capsule-install-01-static-helmrelease.bats` | exact (yq HelmRelease shape → Tenant CR shape) |
| `tests/bats/tenants-02-static-p27.bats` | Static contract bats (TEN-04 P27 LOAD-BEARING — yq `serviceAccountName` non-null) | yq-eval + bash loop over multi-doc YAML | `tests/bats/capsule-install-04-static-no-umbrella.bats` (yq path + multi-line bats body) | role-match (yq pattern + multi-doc loop is novel) |
| `tests/bats/tenants-03-static-lockdown.bats` | Static contract bats (TEN-05 — patches block + escape hatch) | grep -F + yq on `patches:` block | `tests/bats/poc-mount-01-static.bats` (sentinel grep + yq aggregator) | role-match (patches block is novel) |
| `tests/bats/tenants-04-static-dependson.bats` | Static contract bats (TEN-06 — dependsOn chain) | yq on `dependsOn[0]` + `wait: true` (top-level) | `tests/bats/capsule-install-01-static-helmrelease.bats` lines 70-75 (HR dependsOn pattern) | exact (Kustomization.dependsOn mirrors HR.dependsOn) |
| `tests/bats/tenants-05-static-split-path.bats` | Static contract bats (D-08-12 inheritance regression) | yq on `kubeConfig` presence/absence | `tests/bats/poc-mount-01-static.bats` lines 59-76 (split-path verification) | exact (carryover gate; same yq pattern) |
| `tests/bats/tenants-06-live-tenant-cr.bats` | Live integration bats (TEN-01) | `kubectl --context=k3d-spoke-capsule get tenants ... -o jsonpath` | `tests/bats/capsule-install-06-live-helm.bats` (jsonpath retry pattern) | exact (3×30s retry + jsonpath) |
| `tests/bats/tenants-07-live-impersonate.bats` | Live integration bats (TEN-02 — `kubectl --as=alpha`) | `kubectl --context --as=alpha create namespace` | none in repo — RESEARCH §"Bats Coverage" + Gap 7 | partial (live `--as` impersonation is novel; setup gate transfers) |
| `tests/bats/tenants-08-live-quota-limit.bats` | Live integration bats (TEN-03 — auto-materialization) | `kubectl get resourcequota,limitrange -n` | `tests/bats/capsule-install-07-live-crds.bats` (kubectl get list pattern) | role-match |
| `tests/bats/tenants-09-live-inner-k-ready.bats` | Live integration bats (TEN-04 reconcile) | `kubectl get kustomization -n tenant-alpha -o jsonpath` Ready=True OR pre-push skip | `tests/bats/capsule-install-10-live-flux-observable.bats` (Ready=True + skip-pre-push) | exact (folded carryover skip pattern) |
| `tests/bats/tenants-10-live-lockdown.bats` | Live integration bats (TEN-05 — Deployment args + flux-system K Ready) | `kubectl get deployment -o jsonpath='{.spec.template.spec.containers[0].args}'` | `tests/bats/capsule-install-06-live-helm.bats` (jsonpath retry) | role-match (Deployment args parsing is novel) |
| `tests/bats/tenants-11-live-dependson.bats` | Live integration bats (TEN-06 live) | `kubectl get kustomization -o jsonpath dependsOn[0].name` | `tests/bats/capsule-install-06-live-helm.bats` | exact (jsonpath retry pattern) |
| `tests/bats/tenants-12-live-health-check.bats` | Live integration bats (v0.18 health-check regression gate) | `cd "$REPO_ROOT" && task health-check` exit 0 | `tests/bats/health-check-01-static.bats` (static probe) + RESEARCH §Gap 11 | partial (live `task health-check` invocation is novel; `task` invocation pattern transfers) |
| `scripts/register-poc-cluster.sh` (extension) | Imperative shell script extension — Secret-mirror step for `spoke-capsule-kubeconfig` into `tenant-{alpha,bravo}` namespaces on hub | side-effect: `kubectl apply` Secret to per-tenant ns | `scripts/register-poc-cluster.sh` lines 187-196 (`apply_hub_secret` function) | exact (clone the pattern; add per-tenant loop) |

### MODIFIED files (5)

| Modified File | Role | Data Flow | Modification Type | Notes |
|---|---|---|---|---|
| `clusters/hub-flux/flux-system/kustomization.yaml` | Bootstrap-managed FLUX PATCH SURFACE | declarative; reconciled by hub kustomize-controller (self-applied via `flux-system` K) | ADD `patches:` block (4 patches: 3 Deployment patches + 1 flux-system K patch) | Sentinel-guarded; preserve HEAD comment + `# KARYON SPOKES MOUNT` + `# KARYON POC MOUNT` verbatim |
| `clusters/hub-flux/pocs/capsule.yaml` | Hub-targeted Flux Kustomization (Phase 8 D-08-12) | hub apply | ADD `spec.serviceAccountName: kustomize-controller` (escape hatch under lockdown) | Preserve Phase 8 D-08-12 comment block; append Phase 9 D-09-05a note |
| `clusters/hub-flux/pocs/capsule-spoke.yaml` | Spoke-targeted Flux Kustomization (Phase 8 D-08-12) | spoke apply via kubeConfig | ADD top-level `spec.wait: true`, `spec.timeout: 10m`, `spec.dependsOn: [{name: poc-capsule}]`, `spec.serviceAccountName: kustomize-controller` | RESEARCH correction: `wait: true` is TOP-LEVEL, NOT inside dependsOn entry |
| `pocs/capsule/kustomization.yaml` | Top-level Kustomize aggregator (Phase 8 head comment + `resources: [operator/, proxy/]`) | declarative | ADD `- tenants/` to resources list | Preserve Phase 7+8 head comment block; append Phase 9 update note |
| `pocs/capsule/spoke/kustomization.yaml` | Phase 8 Pitfall-7 placeholder (`resources: []`) | declarative | REWRITE to `resources: [config/, tenants/]` | Preserve Phase 8 head comment; append Phase 9 D-09-01 update note |

**Match quality legend:**
- **exact** — same role + same data flow; copy pattern verbatim with substitutions
- **role-match** — same role; data flow differs slightly (e.g., live vs static, multi-doc vs single-doc); adapt setup/imports
- **partial** — only structural skeleton transfers; core logic per RESEARCH
- **no-analog** — greenfield in repo; planner uses RESEARCH.md §"Code Examples" or §"Gap N" verbatim

---

## Pattern Assignments

### `pocs/capsule/spoke/config/kustomization.yaml` (Kustomize aggregator, subdir)

**Analog:** `pocs/capsule/operator/kustomization.yaml` (lines 1-13).

**Imports/header pattern (exact head-comment style, with Phase 9 substitution):**
```yaml
# pocs/capsule/operator/kustomization.yaml
# Local Kustomize aggregator for the operator subdir — resolved by the parent
# pocs/capsule/kustomization.yaml (which Plan 08-02 rewrites to resources: [operator/, proxy/]).
#
# D-08-01 / D-08-05 — operator subdir under pocs/capsule/.
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: capsule-system
resources:
  - ocirepository.yaml
  - helmrelease.yaml
```

**Substitutions for Phase 9 config subdir:**
- Drop `namespace: capsule-system` line (CapsuleConfiguration is cluster-scoped; no namespace needed)
- Replace `resources` list with `[capsuleconfig.yaml]`
- Update head comment to cite D-09-01 / D-09-04 (config subdir under `pocs/capsule/spoke/`)

**Target shape (RESEARCH §"Code Examples" lines 826-837 verbatim):**
```yaml
# pocs/capsule/spoke/config/kustomization.yaml
# Local Kustomize aggregator for the spoke-side config subdir.
#
# D-09-01 / D-09-04 — config subdir under pocs/capsule/spoke/.
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - capsuleconfig.yaml
```

---

### `pocs/capsule/spoke/config/capsuleconfig.yaml` (Capsule CR — CapsuleConfiguration/default singleton)

**Analog:** **None in repo.** Phase 9 introduces the first CapsuleConfiguration CR.

**Pattern source:** RESEARCH §"Gap 5" (lines 408-453) — verified against v0.12.4 raw CRD schema.

**Critical schema corrections vs CONTEXT.md D-09-04:**
- REQUIRED field `enableTLSReconciler: false` (CONTEXT.md missed this; CRD enforces it)
- `forceTenantPrefix` is at TOP-LEVEL `spec.forceTenantPrefix` ✅ correct
- `userGroups` DEPRECATED in v1beta2 but kept for chart-default compatibility

**Target shape (RESEARCH §Gap 5 lines 408-453 verbatim):**
```yaml
apiVersion: capsule.clastix.io/v1beta2
kind: CapsuleConfiguration
metadata:
  name: default
spec:
  enableTLSReconciler: false        # REQUIRED — RESEARCH §Gap 5 correction
  forceTenantPrefix: true            # TEN-01 contract
  allowServiceAccountPromotion: true
  userGroups:
    - capsule.clastix.io
  protectedNamespaceRegex: ^kube-.*$
  nodeMetadata:
    forbiddenAnnotations: {}
    forbiddenLabels: {}
```

**Critical invariants (verify in static bats):**
- `apiVersion: capsule.clastix.io/v1beta2`
- `kind: CapsuleConfiguration`
- `metadata.name: default` (singleton)
- `spec.enableTLSReconciler: false` (REQUIRED by CRD)
- `spec.forceTenantPrefix: true` (TEN-01 load-bearing)

---

### `pocs/capsule/spoke/tenants/alpha/namespace.yaml` (Namespace — tenant home on spoke)

**Analog:** `clusters/spoke-apps/namespace.yaml` (lines 1-7) — exact Namespace seed pattern.

**Analog excerpt (verbatim, with Phase 9 substitution):**
```yaml
# clusters/spoke-apps/namespace.yaml
# REQ-SPOKE-05 seed - distinct per spoke, falsifiable for the cross-cluster
# negative-proof (this Namespace exists ONLY on k3d-spoke-apps).
apiVersion: v1
kind: Namespace
metadata:
  name: karyon-spoke-apps
```

**Substitutions for Phase 9 tenant-alpha namespace:**
- Replace head comment with TEN-01 attribution per RESEARCH §"Code Examples" lines 842-848
- Replace `metadata.name: karyon-spoke-apps` → `metadata.name: tenant-alpha`

**Target shape (RESEARCH §"Code Examples" lines 841-853 verbatim):**
```yaml
# pocs/capsule/spoke/tenants/alpha/namespace.yaml
# TEN-01 — the tenant home namespace on spoke-capsule. Holds the gitops-reconciler
# SA that the Tenant CR registers as ServiceAccount owner.
#
# D-09-02 — tenant home namespace name pattern: tenant-<tenant-name>.
apiVersion: v1
kind: Namespace
metadata:
  name: tenant-alpha
```

---

### `pocs/capsule/spoke/tenants/alpha/sa.yaml` (ServiceAccount — Flux impersonation principal)

**Analog:** **None in repo for ServiceAccount.** Closest pattern: `clusters/spoke-apps/namespace.yaml` (head comment + minimal apiVersion/kind/metadata pattern).

**Target shape (RESEARCH §"Code Examples" lines 858-871 verbatim):**
```yaml
# pocs/capsule/spoke/tenants/alpha/sa.yaml
# TEN-01 — the per-tenant ServiceAccount registered as Tenant owner via the
# combined name format `system:serviceaccount:tenant-alpha:gitops-reconciler` in
# tenant.yaml's spec.owners[].
#
# D-09-02 — gitops-reconciler SA. Capsule's auto-injected RoleBindings on owners
# (default clusterRoles: [admin, capsule-namespace-deleter]) give this SA full
# control inside any tenant-managed namespace; no additional RoleBinding needed.
apiVersion: v1
kind: ServiceAccount
metadata:
  name: gitops-reconciler
  namespace: tenant-alpha
```

---

### `pocs/capsule/spoke/tenants/alpha/tenant.yaml` (Capsule CR — Tenant alpha)

**Analog:** **None in repo.** Phase 9 introduces the first Tenant CR.

**Pattern source:** RESEARCH §"Gap 4" (lines 311-372) — verified against v0.12.4 raw CRD schema.

**Critical schema corrections vs CONTEXT.md D-09-02:**
1. `forceTenantPrefix` is at TOP-LEVEL `spec.forceTenantPrefix`, NOT under `spec.namespaceOptions`
2. `spec.owners[]` does NOT have a `namespace` field
3. ServiceAccount owners use combined-name format: `name: system:serviceaccount:<ns>:<sa-name>`

**Target shape (RESEARCH §Gap 4 lines 313-372 verbatim — copy with `alpha → bravo` substitution for bravo):**
```yaml
apiVersion: capsule.clastix.io/v1beta2
kind: Tenant
metadata:
  name: alpha
spec:
  forceTenantPrefix: true   # TOP-LEVEL — RESEARCH §Gap 4 correction
  owners:
    - kind: ServiceAccount
      name: system:serviceaccount:tenant-alpha:gitops-reconciler   # combined-name
    - kind: User
      name: alpha
  resourceQuotas:
    items:
      - hard:
          cpu: "4"
          memory: 8Gi
          pods: "20"
  limitRanges:
    items:
      - limits:
          - type: Container
            default:
              cpu: 100m
              memory: 128Mi
            defaultRequest:
              cpu: 50m
              memory: 64Mi
```

**Critical invariants (verify in static bats):**
- `apiVersion: capsule.clastix.io/v1beta2`
- `kind: Tenant`
- `metadata.name: alpha` (or `bravo`)
- `spec.forceTenantPrefix: true` (TOP-LEVEL)
- `spec.owners[]` contains `{kind: ServiceAccount, name: system:serviceaccount:tenant-alpha:gitops-reconciler}` (combined-name format)
- `spec.owners[]` contains `{kind: User, name: alpha}`
- `spec.resourceQuotas.items[0].hard` non-empty (TEN-03 shape)
- `spec.limitRanges.items[0].limits` non-empty (TEN-03 shape)

---

### `pocs/capsule/spoke/tenants/alpha/kustomization.yaml` (Kustomize aggregator — per-tenant 3-resource subdir)

**Analog:** `clusters/spoke-apps/kustomization.yaml` (lines 1-6) — exact 3-resource per-area aggregator pattern.

**Analog excerpt:**
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- namespace.yaml
- configmap.yaml
- ../../examples/podinfo
```

**Substitutions for Phase 9 alpha tenant subdir:**
- Replace `resources` list with `[namespace.yaml, sa.yaml, tenant.yaml]`
- Add head comment per RESEARCH §"Code Examples" lines 879-891

**Target shape:**
```yaml
# pocs/capsule/spoke/tenants/alpha/kustomization.yaml
# D-09-01 — alpha subdir under pocs/capsule/spoke/tenants/. Mirror exists at
# pocs/capsule/spoke/tenants/bravo/.
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - sa.yaml
  - tenant.yaml
```

---

### `pocs/capsule/spoke/tenants/kustomization.yaml` (Kustomize aggregator — multi-subdir)

**Analog:** `clusters/hub-flux/spokes/kustomization.yaml` (lines 1-5) — exact multi-resource aggregator pattern.

**Analog excerpt:**
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- spoke-ml.yaml
- spoke-apps.yaml
```

**Substitutions:**
- Resources are subdirs (trailing slash) instead of files: `[alpha/, bravo/]`

**Target shape (RESEARCH §"Code Examples" lines 895-903):**
```yaml
# pocs/capsule/spoke/tenants/kustomization.yaml
# Aggregator for both tenant subdirs.
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - alpha/
  - bravo/
```

---

### `pocs/capsule/tenants/alpha.yaml` (Multi-doc YAML: Namespace + GitRepository v1 + Kustomization v1 with kubeConfig + serviceAccountName + dependsOn)

**Analogs (composite — multi-doc YAML has no single repo analog):**
- **Namespace doc:** `clusters/spoke-apps/namespace.yaml` (lines 1-7) — Namespace shape
- **GitRepository doc:** No karyon analog for hand-written GitRepository (the bootstrap GitRepository `flux-system` is auto-generated). Use RESEARCH §Gap 10 lines 618-642 verbatim.
- **Kustomization doc with kubeConfig:** `clusters/hub-flux/pocs/capsule-spoke.yaml` (lines 23-39) — spoke-targeted Kustomization with full kubeConfig block

**Analog excerpt — Kustomization with kubeConfig (`clusters/hub-flux/pocs/capsule-spoke.yaml` lines 23-39):**
```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: poc-capsule-spoke
  namespace: flux-system
spec:
  interval: 5m
  path: ./pocs/capsule/spoke
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  kubeConfig:
    secretRef:
      name: spoke-capsule-kubeconfig
      key: value.yaml
```

**Phase 9 Kustomization substitutions vs analog:**
- `metadata.name: poc-capsule-spoke` → `metadata.name: tenant-alpha-app`
- `metadata.namespace: flux-system` → `metadata.namespace: tenant-alpha` (RESEARCH §Gap 1 — same-namespace constraint for `kubeConfig.secretRef`)
- `spec.path: ./pocs/capsule/spoke` → `spec.path: ./pocs/capsule/tenants/alpha-app`
- `spec.sourceRef.name: flux-system` → `spec.sourceRef.name: tenant-alpha-source` (per-tenant GitRepository in same namespace — survives `--no-cross-namespace-refs`)
- ADD `spec.serviceAccountName: gitops-reconciler` (P27 LOAD-BEARING DEFENSE — RESEARCH §Gap 3)
- ADD `spec.dependsOn: [{name: poc-capsule, namespace: flux-system}]` (TEN-06 P32)
- ADD `spec.wait: true`, `spec.timeout: 5m`

**Target shape (RESEARCH §"Code Examples" lines 925-1002 verbatim — single multi-doc file):**
```yaml
# Doc 1: Namespace
apiVersion: v1
kind: Namespace
metadata:
  name: tenant-alpha
---
# Doc 2: GitRepository (per-tenant source)
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: tenant-alpha-source
  namespace: tenant-alpha
spec:
  interval: 5m
  url: https://github.com/richard-iovanisci/karyon
  ref:
    branch: main
---
# Doc 3: Kustomization (per-tenant inner K)
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: tenant-alpha-app
  namespace: tenant-alpha
spec:
  interval: 5m
  path: ./pocs/capsule/tenants/alpha-app
  prune: true
  wait: true
  timeout: 5m
  sourceRef:
    kind: GitRepository
    name: tenant-alpha-source
  kubeConfig:
    secretRef:
      name: spoke-capsule-kubeconfig
      key: value.yaml
  serviceAccountName: gitops-reconciler   # P27 LOAD-BEARING DEFENSE
  dependsOn:
    - name: poc-capsule
      namespace: flux-system
```

**Critical invariants (verify in static bats):**
- 3 docs in single file (separated by `---`); count must equal 3
- All 3 docs have `metadata.namespace: tenant-alpha` (RESEARCH §Gap 1 same-namespace)
- Kustomization doc has `spec.serviceAccountName: gitops-reconciler` non-null (P27)
- Kustomization doc has `spec.kubeConfig.secretRef.name: spoke-capsule-kubeconfig` AND `key: value.yaml` (P40/P18)
- Kustomization doc has `spec.dependsOn[0].name: poc-capsule` AND `namespace: flux-system` (P32)
- Kustomization doc has `spec.wait: true` (TOP-LEVEL — RESEARCH correction; NOT inside dependsOn)

---

### `pocs/capsule/tenants/alpha-app/kustomization.yaml` (Pitfall-7 placeholder)

**Analog:** `pocs/capsule/spoke/kustomization.yaml` (Phase 8 placeholder, lines 1-13) — exact Pitfall-7 placeholder pattern.

**Analog excerpt (verbatim):**
```yaml
# pocs/capsule/spoke/kustomization.yaml
# D-08-12 (gap-close 2026-04-29) — Pitfall-7 placeholder so the spoke-targeted outer Flux
# Kustomization (clusters/hub-flux/pocs/capsule-spoke.yaml, spec.path: ./pocs/capsule/spoke)
# reconciles successfully against an empty resource list. Without this file, the outer K
# would report Ready=False with "path not found" against the GitRepository revision.
#
# Phase 9 forward-pointer: this directory will hold spoke-targeted CRs starting with
# Phase 9 (TEN-01..06): the two Tenant CRs (alpha + bravo) AND the tenant inner Flux
# Kustomizations under tenants/<name>/ (which themselves carry the P27 invariant
# spec.serviceAccountName explicit-set). Until Phase 9 lands, resources is empty.
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources: []
```

**Substitutions for Phase 9 tenant-app placeholder:**
- Drop forward-pointer paragraph; replace with reference to RESEARCH §"Code Examples" lines 1006-1016
- `resources: []` preserved verbatim

**Target shape (RESEARCH §"Code Examples" lines 1006-1016 verbatim):**
```yaml
# pocs/capsule/tenants/alpha-app/kustomization.yaml
# D-09-01 / Pitfall-7 placeholder — empty resource list so the inner Flux
# Kustomization (tenant-alpha-app, defined in pocs/capsule/tenants/alpha.yaml)
# reconciles successfully against an empty resource set.
#
# Mirrors Phase 7 D-06 / Phase 8 D-08-12 spoke/ placeholder pattern.
# Phase 11 (workload demonstration) may populate.
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources: []
```

---

### `pocs/capsule/kustomization.yaml` (MODIFY — add `tenants/`)

**Analog:** `pocs/capsule/kustomization.yaml` (existing Phase 8 file, lines 1-19) — modify in-place.

**Existing file (verbatim):**
```yaml
# pocs/capsule/kustomization.yaml
# Phase 7 placeholder so the outer Flux Kustomization
# (clusters/hub-flux/pocs/capsule.yaml, spec.path: ./pocs/capsule) reconciles
# successfully against an empty resource list. Phase 8 will replace `resources: []`
# with `[operator, proxy, config]` once the HelmReleases land.
#
# REQ-CAPCLU-02 (Pitfall 7 — without this file the outer Kustomization reports
# Ready=False; path not found).
#
# Phase 8 update (D-08-05): operator/ and proxy/ subdir refs added — the outer
# poc-capsule Flux Kustomization now reconciles operator HelmRelease + proxy
# HelmRelease + their per-chart OCIRepositories under capsule-system on
# spoke-capsule via spoke-capsule-kubeconfig. Phase 9 will append config/ + tenants/.
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- operator/
- proxy/
```

**Substitutions per D-09-01:**
- PRESERVE Phase 7 + Phase 8 head comment block verbatim
- APPEND Phase 9 update note (config/ landed via spoke-targeted path; tenants/ added here for hub-targeted inner Ks)
- ADD `- tenants/` resource line after `- proxy/`

**Target shape:**
```yaml
# pocs/capsule/kustomization.yaml
# Phase 7 placeholder so the outer Flux Kustomization
# (clusters/hub-flux/pocs/capsule.yaml, spec.path: ./pocs/capsule) reconciles
# successfully against an empty resource list. Phase 8 will replace `resources: []`
# with `[operator, proxy, config]` once the HelmReleases land.
#
# REQ-CAPCLU-02 (Pitfall 7 — without this file the outer Kustomization reports
# Ready=False; path not found).
#
# Phase 8 update (D-08-05): operator/ and proxy/ subdir refs added.
#
# Phase 9 update (D-09-01): tenants/ subdir added — hub-targeted per-tenant
# inner Flux Kustomization CRs + per-tenant Namespaces + per-tenant GitRepositories.
# CapsuleConfiguration + Tenant CRs land via the spoke-targeted poc-capsule-spoke
# outer K (path ./pocs/capsule/spoke).
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- operator/
- proxy/
- tenants/
```

---

### `pocs/capsule/spoke/kustomization.yaml` (REWRITE — populate placeholder)

**Analog:** `pocs/capsule/spoke/kustomization.yaml` (existing Phase 8 placeholder, lines 1-13) — rewrite in-place.

**Existing file (verbatim — see above under `pocs/capsule/tenants/alpha-app/kustomization.yaml`'s analog section).**

**Substitutions per D-09-01:**
- PRESERVE Phase 8 D-08-12 head comment (lines 1-10)
- APPEND Phase 9 update note (no longer a Pitfall-7 placeholder)
- Replace `resources: []` with `resources: [config/, tenants/]`

**Target shape (RESEARCH §"Code Examples" lines 905-921):**
```yaml
# pocs/capsule/spoke/kustomization.yaml
# Phase 8 D-08-12 (gap-close 2026-04-29) — Pitfall-7 placeholder; Phase 9 D-09-01
# populates with config/ + tenants/ subdirs. Spoke-targeted: parent
# clusters/hub-flux/pocs/capsule-spoke.yaml's spec.path: ./pocs/capsule/spoke
# + kubeConfig: spoke-capsule-kubeconfig routes these resources to spoke-capsule
# via kustomize-controller's cross-cluster reconcile (D-08-12 split-path invariant).
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - config/
  - tenants/
```

---

### `clusters/hub-flux/flux-system/kustomization.yaml` (MODIFY — add `patches:` block)

**Analog:** `clusters/hub-flux/flux-system/kustomization.yaml` (existing Phase 7 + 8 file, lines 1-22) — modify in-place.

**Existing file (verbatim):**
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

**Substitutions per D-09-05 + RESEARCH §Gap 2:**
- PRESERVE the FLUX PATCH SURFACE head comment block (lines 1-13) verbatim
- PRESERVE `# KARYON SPOKES MOUNT` and `# KARYON POC MOUNT` sentinels verbatim
- APPEND `# KARYON FLUX LOCKDOWN PATCHES (D-09-05 / TEN-05)` sentinel + `patches:` block

**Target shape (RESEARCH §"Code Examples" lines 1047-1128 verbatim — extends CONTEXT.md narrowing per Gap 2):**

The `patches:` block contains 4 patches:
1. **kustomize-controller** Deployment patch — adds 3 args: `--no-cross-namespace-refs=true`, `--no-remote-bases=true`, `--default-service-account=default`
2. **helm-controller** Deployment patch — adds 2 args: `--no-cross-namespace-refs=true`, `--default-service-account=default` (RESEARCH §Gap 2 extends CONTEXT.md narrowing — `--default-service-account` ALSO accepted by helm-controller)
3. **notification-controller** Deployment patch — adds 1 arg: `--no-cross-namespace-refs=true`
4. **flux-system Kustomization** CR patch (LOAD-BEARING ESCAPE HATCH) — adds `spec.serviceAccountName: kustomize-controller`

**Critical invariants (verify in static bats):**
- HEAD comment block (lines 1-13) preserved verbatim
- `# KARYON SPOKES MOUNT` and `# KARYON POC MOUNT` sentinels both present
- `patches:` block exists at top level
- `patches:` block contains all 3 lockdown flags as literal strings
- `patches:` block contains a Deployment-targeted patch for `kustomize-controller`, `helm-controller`, `notification-controller`
- `patches:` block contains a Kustomization-targeted patch for `flux-system` setting `serviceAccountName: kustomize-controller`

---

### `clusters/hub-flux/pocs/capsule.yaml` (MODIFY — add escape hatch)

**Analog:** `clusters/hub-flux/pocs/capsule.yaml` (existing Phase 8 file, lines 1-32) — modify in-place.

**Existing file (key lines 21-32, verbatim):**
```yaml
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
```

**Substitutions per D-09-05a:**
- PRESERVE Phase 8 D-08-12 head comment block (lines 1-20) verbatim
- APPEND Phase 9 D-09-05a note (escape hatch under lockdown)
- ADD `serviceAccountName: kustomize-controller` to spec block

**Target shape (RESEARCH §"Code Examples" lines 1132-1155):**
```yaml
spec:
  interval: 5m
  path: ./pocs/capsule
  prune: true
  serviceAccountName: kustomize-controller   # D-09-05a — escape hatch under lockdown
  sourceRef:
    kind: GitRepository
    name: flux-system
```

**Critical invariants:**
- NO `spec.kubeConfig` (D-08-12 split-path invariant — hub-targeted MUST NOT have kubeConfig)
- `spec.serviceAccountName: kustomize-controller` (D-09-05a escape hatch)

---

### `clusters/hub-flux/pocs/capsule-spoke.yaml` (MODIFY — add dependsOn + top-level wait)

**Analog:** `clusters/hub-flux/pocs/capsule-spoke.yaml` (existing Phase 8 file, lines 1-39) — modify in-place.

**Existing file (key lines 28-38, verbatim):**
```yaml
spec:
  interval: 5m
  path: ./pocs/capsule/spoke
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  kubeConfig:
    secretRef:
      name: spoke-capsule-kubeconfig
      key: value.yaml
```

**Substitutions per D-09-06 + RESEARCH §"Code Examples" lines 1157-1203 (RESEARCH correction — `wait: true` is TOP-LEVEL, NOT inside dependsOn entry):**
- PRESERVE Phase 8 head comment block; APPEND Phase 9 D-09-06 note
- ADD top-level `spec.wait: true`, `spec.timeout: 10m`
- ADD `spec.dependsOn: [{name: poc-capsule}]` (no namespace needed — same flux-system namespace)
- ADD `spec.serviceAccountName: kustomize-controller` (D-09-05 explicit clarity)
- PRESERVE existing `spec.kubeConfig.secretRef` block verbatim (P40/P18 inheritance)

**Target shape (RESEARCH §"Code Examples" lines 1177-1203 verbatim):**
```yaml
spec:
  interval: 5m
  path: ./pocs/capsule/spoke
  prune: true
  serviceAccountName: kustomize-controller   # D-09-05 — explicit clarity
  dependsOn:
    - name: poc-capsule   # D-09-06 — P32 dependsOn chain
  wait: true                # TOP-LEVEL (RESEARCH correction; NOT inside dependsOn entry)
  timeout: 10m
  sourceRef:
    kind: GitRepository
    name: flux-system
  kubeConfig:
    secretRef:
      name: spoke-capsule-kubeconfig
      key: value.yaml
```

**Critical invariants:**
- `spec.kubeConfig.secretRef.name: spoke-capsule-kubeconfig` AND `key: value.yaml` (P40/P18 — preserved from Phase 8)
- `spec.dependsOn[0].name: poc-capsule` (P32)
- `spec.wait: true` (TOP-LEVEL — RESEARCH correction)
- `spec.timeout: 10m`

---

### `scripts/register-poc-cluster.sh` (EXTENSION — Secret-mirror step per RESEARCH Gap 1)

**Analog:** `scripts/register-poc-cluster.sh` lines 187-196 (`apply_hub_secret` function) — exact imperative-apply pattern.

**Analog excerpt (verbatim):**
```bash
# ---------- apply_hub_secret: D-11 token-safe imperative apply ----------
# --from-file=value.yaml=/dev/stdin only — NEVER --from-literal (would expose
# token in argv / shell history / process listings). NEVER tee. NEVER echo.
apply_hub_secret() {
  local spoke="$1" payload="$2"
  printf '%s\n' "${payload}" |
    kubectl --context "${HUB_CTX}" -n "${FLUX_NS}" create secret generic "${spoke}-kubeconfig" \
      --from-file=value.yaml=/dev/stdin --dry-run=client -o yaml |
    kubectl --context "${HUB_CTX}" -n "${FLUX_NS}" apply -f -
}
```

**Phase 9 extension shape (RESEARCH §"Gap 1" lines 164-176 verbatim — adapted to function form):**
```bash
# ---------- mirror_kubeconfig_to_tenant_namespaces: RESEARCH §Gap 1 ----------
# Mirror spoke-capsule-kubeconfig Secret into per-tenant namespaces on hub-flux.
# Required because Flux's kubeConfig.secretRef has UNCONDITIONAL same-namespace
# constraint (RESEARCH §Gap 1 — Flux v2.8 docs + Go API source citation). The
# tenant namespaces tenant-alpha + tenant-bravo host the per-tenant inner
# Kustomization CRs (defined in pocs/capsule/tenants/<name>.yaml), which
# reference this Secret. Without the mirror, those CRs reach Ready=False with
# `secret "spoke-capsule-kubeconfig" not found`.
mirror_kubeconfig_to_tenant_namespaces() {
  for tenant in alpha bravo; do
    kubectl --context="${HUB_CTX}" create namespace "tenant-${tenant}" \
      --dry-run=client -o yaml | kubectl --context="${HUB_CTX}" apply -f -
    kubectl --context="${HUB_CTX}" -n "${FLUX_NS}" get secret spoke-capsule-kubeconfig -o yaml \
      | yq eval '.metadata.namespace = "tenant-'"${tenant}"'"
                 | del(.metadata.resourceVersion, .metadata.uid, .metadata.creationTimestamp)' - \
      | kubectl --context="${HUB_CTX}" apply -f -
  done
}
```

**Substitutions vs analog `apply_hub_secret`:**
- Per-tenant loop wrapping the apply (`for tenant in alpha bravo`)
- Read-then-rewrite pattern: `kubectl get secret -o yaml | yq | kubectl apply` (NOT `--from-file` since we're mirroring an existing Secret, not creating from raw payload)
- yq strip pattern: `del(.metadata.resourceVersion, .metadata.uid, .metadata.creationTimestamp)` — required to make the Secret apply-clean in the new namespace
- Idempotent via `apply -f -` (matches analog `apply -f -` pattern)

**Critical invariants:**
- Per-tenant namespace creation BEFORE Secret apply (Secret apply requires existing namespace)
- yq strip of `resourceVersion`, `uid`, `creationTimestamp` (otherwise apply rejects with conflict)
- Use `--context="${HUB_CTX}"` (k3d-hub-flux) — Secret lives on hub, not spoke
- Idempotent (re-run safe; matches Phase 7 register-poc-cluster.sh pattern)

---

### Bats Tests — 12 Phase 9 bats files

**Analog:** Phase 8 capsule-install-*.bats files (10 files; 5 static + 5 live). Phase 9 mirrors the naming and structural pattern.

#### `tests/bats/tenants-01-static-tenant-cr.bats` (TEN-01 static)

**Analog:** `tests/bats/capsule-install-01-static-helmrelease.bats` (lines 1-76) — exact yq-based Flux/CR shape verification.

**`load + setup` pattern (lines 1-13):**
```bash
#!/usr/bin/env bats
# tests/bats/capsule-install-01-static-helmrelease.bats
# Phase 8 / Wave 0 (D-08-09 Nyquist gate)

load 'test_helper'

setup() {
  OPERATOR_HR="${REPO_ROOT}/pocs/capsule/operator/helmrelease.yaml"
  PROXY_HR="${REPO_ROOT}/pocs/capsule/proxy/helmrelease.yaml"
}
```

**`yq eval` pattern for compound assertion (lines 14-19):**
```bash
@test "CAP-01 / D-08-06: operator HelmRelease has apiVersion ... interval 5m" {
  [ -f "$OPERATOR_HR" ]
  run yq eval '.apiVersion == "helm.toolkit.fluxcd.io/v2" and .kind == "HelmRelease" and .metadata.name == "capsule" and .metadata.namespace == "capsule-system" and .spec.interval == "5m"' "$OPERATOR_HR"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}
```

**Substitutions for Phase 9 TEN-01 Tenant CR shape:**
- `OPERATOR_HR` → `ALPHA_TENANT="${REPO_ROOT}/pocs/capsule/spoke/tenants/alpha/tenant.yaml"`, `BRAVO_TENANT` similar
- yq path `.apiVersion == "helm.toolkit.fluxcd.io/v2"` → `.apiVersion == "capsule.clastix.io/v1beta2"`
- yq path `.kind == "HelmRelease"` → `.kind == "Tenant"`
- ADD assertions per RESEARCH §"Bats Coverage" lines 1215-1225:
  - `.spec.forceTenantPrefix == true` (TOP-LEVEL — RESEARCH §Gap 4 correction)
  - `.spec.owners | map(select(.kind == "ServiceAccount" and .name == "system:serviceaccount:tenant-alpha:gitops-reconciler")) | length == 1`
  - `.spec.owners | map(select(.kind == "User" and .name == "alpha")) | length == 1`
  - `.spec.resourceQuotas.items[0].hard | length > 0`
  - `.spec.limitRanges.items[0].limits | length > 0`
- Mirror tests for bravo (substitute `alpha → bravo`)

---

#### `tests/bats/tenants-02-static-p27.bats` (TEN-04 P27 LOAD-BEARING)

**Analog:** `tests/bats/capsule-install-04-static-no-umbrella.bats` (lines 1-70) — yq path negative assertions + multi-line bats body.

**Anti-pattern lint with yq pattern (lines 22-29) — adapted for multi-doc YAML:**
```bash
@test "Anti-umbrella ... operator HelmRelease has NO values.proxy.enabled=true at any depth" {
  [ -f "$OPERATOR_HR" ]
  # WR-01 fix: yq path negative assertion with `..` recursive descent + any_c reducer
  run yq eval '[.. | select(has("proxy")) | .proxy.enabled] | any_c(. == true)' "$OPERATOR_HR"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}
```

**Substitutions for Phase 9 P27 LOAD-BEARING (RESEARCH §"Bats Coverage" lines 1227-1242 verbatim):**
- For every yaml document in `pocs/capsule/tenants/*.yaml` that is a `Kustomization` AND `kustomize.toolkit.fluxcd.io/v1`: assert `spec.serviceAccountName` is non-null
- Use multi-doc yq splitting pattern:
  ```bash
  for f in "$REPO_ROOT/pocs/capsule/tenants/"*.yaml; do
    while IFS= read -r doc; do
      if echo "$doc" | yq eval '.kind == "Kustomization" and .apiVersion == "kustomize.toolkit.fluxcd.io/v1"' - 2>/dev/null | grep -qx "true"; then
        sa=$(echo "$doc" | yq eval '.spec.serviceAccountName' -)
        [ "$sa" != "null" ] && [ -n "$sa" ]
      fi
    done < <(yq eval '. as $doc ireduce ([];  . + [$doc])' "$f" | yq eval '.[] | split_doc' -)
  done
  ```
- Negative falsifier: a synthetic broken Kustomization fixture WITHOUT `serviceAccountName` MUST fail this lint (planner adds fixture under `tests/fixtures/p27-broken/`)

---

#### `tests/bats/tenants-03-static-lockdown.bats` (TEN-05 — patches block + escape hatch)

**Analog:** `tests/bats/poc-mount-01-static.bats` (lines 17-44) — sentinel grep + structural yq.

**Sentinel-existence pattern (lines 17-44):**
```bash
@test "POC-01 / D-09: # KARYON POC MOUNT sentinel exists in clusters/hub-flux/flux-system/kustomization.yaml" {
  [ -f "$HUB_FS_KUST" ]
  run grep -F -- '# KARYON POC MOUNT' "$HUB_FS_KUST"
  [ "$status" -eq 0 ]
}

@test "POC-01 / D-09: # KARYON SPOKES MOUNT (Phase 4 D-13 inheritance) is preserved unchanged" {
  [ -f "$HUB_FS_KUST" ]
  run grep -F -- '# KARYON SPOKES MOUNT' "$HUB_FS_KUST"
  [ "$status" -eq 0 ]
  run grep -F -- '- ../spokes' "$HUB_FS_KUST"
  [ "$status" -eq 0 ]
}
```

**Substitutions for Phase 9 lockdown patches (RESEARCH §"Bats Coverage" lines 1244-1253):**
- `HUB_FS_KUST` reused (same file)
- ASSERT FLUX PATCH SURFACE comment block preserved verbatim (grep `-F` on `'FLUX PATCH SURFACE'` and `'Edits here SURVIVE re-bootstrap'`)
- ASSERT `# KARYON SPOKES MOUNT` and `# KARYON POC MOUNT` sentinels both present (regression gate)
- ASSERT `patches:` block exists at top level: `yq eval '.patches | length > 0' "$HUB_FS_KUST"` returns true
- ASSERT all 3 lockdown flags as literal strings via `grep -F`:
  - `--no-cross-namespace-refs=true`
  - `--no-remote-bases=true`
  - `--default-service-account=default`
- ASSERT each Deployment-targeted patch exists via yq: `yq eval '.patches | map(select(.target.kind == "Deployment" and .target.name == "kustomize-controller")) | length == 1'`
- ASSERT flux-system Kustomization-targeted patch exists with `serviceAccountName: kustomize-controller`

---

#### `tests/bats/tenants-04-static-dependson.bats` (TEN-06 — dependsOn chain)

**Analog:** `tests/bats/capsule-install-01-static-helmrelease.bats` (lines 70-75) — dependsOn yq pattern.

**Analog excerpt (lines 70-75):**
```bash
@test "CAP-02 / D-08-07: proxy HelmRelease dependsOn[0] names operator capsule in capsule-system" {
  [ -f "$PROXY_HR" ]
  run yq eval '.spec.dependsOn[0].name == "capsule" and .spec.dependsOn[0].namespace == "capsule-system"' "$PROXY_HR"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}
```

**Substitutions for Phase 9 TEN-06 (RESEARCH §"Bats Coverage" lines 1255-1261):**
- `PROXY_HR` → `CAPSULE_SPOKE="${REPO_ROOT}/clusters/hub-flux/pocs/capsule-spoke.yaml"` for `poc-capsule-spoke` checks
- For `poc-capsule-spoke`: assert `spec.dependsOn[0].name == "poc-capsule"` AND `spec.wait == true` (TOP-LEVEL — RESEARCH correction) AND `spec.serviceAccountName == "kustomize-controller"`
- For per-tenant inner Ks in `pocs/capsule/tenants/*.yaml`: assert each `kind: Kustomization` doc has `spec.dependsOn[0].name == "poc-capsule"` AND `spec.dependsOn[0].namespace == "flux-system"`

---

#### `tests/bats/tenants-05-static-split-path.bats` (D-08-12 inheritance regression)

**Analog:** `tests/bats/poc-mount-01-static.bats` (lines 59-76) — exact split-path verification pattern.

**Analog excerpt (lines 59-76):**
```bash
@test "POC-01 / D-08-12: clusters/hub-flux/pocs/capsule.yaml is hub-targeted (path ./pocs/capsule, NO spec.kubeConfig — applies HR/OCIRepo to hub)" {
  [ -f "$POCS_CAPSULE" ]
  run yq eval '.apiVersion == "kustomize.toolkit.fluxcd.io/v1" and .kind == "Kustomization" and .metadata.name == "poc-capsule" and .metadata.namespace == "flux-system" and .spec.path == "./pocs/capsule" and .spec.prune == true and (.spec.kubeConfig == null)' "$POCS_CAPSULE"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "POC-01 / D-11 / P40 / D-08-12: clusters/hub-flux/pocs/capsule-spoke.yaml is spoke-targeted (path ./pocs/capsule/spoke, full spec.kubeConfig.secretRef.name + key value.yaml)" {
  [ -f "$POCS_CAPSULE_SPOKE" ]
  run yq eval '.apiVersion == "kustomize.toolkit.fluxcd.io/v1" and .kind == "Kustomization" and .metadata.name == "poc-capsule-spoke" and .metadata.namespace == "flux-system" and .spec.path == "./pocs/capsule/spoke" and .spec.kubeConfig.secretRef.name == "spoke-capsule-kubeconfig" and .spec.kubeConfig.secretRef.key == "value.yaml" and .spec.prune == true' "$POCS_CAPSULE_SPOKE"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}
```

**Substitutions for Phase 9 (RESEARCH §"Bats Coverage" lines 1263-1269):**
- ADD assertion for `capsule.yaml`: `.spec.serviceAccountName == "kustomize-controller"` (D-09-05a escape hatch)
- KEEP existing assertions verbatim (regression gate — Phase 8 D-08-12 invariant must still hold)

---

#### `tests/bats/tenants-06-live-tenant-cr.bats` (TEN-01 live)

**Analog:** `tests/bats/capsule-install-06-live-helm.bats` (lines 1-52) — exact 3×30s retry + jsonpath pattern.

**`load + setup` pattern with cluster-info gate (lines 1-17):**
```bash
#!/usr/bin/env bats
# tests/bats/capsule-install-06-live-helm.bats
# Cluster-info gate per RESEARCH §"Pattern 4" — auto-skips when k3d clusters unreachable

load 'test_helper'

setup() {
  if ! kubectl --context=k3d-hub-flux cluster-info >/dev/null 2>&1; then
    skip "k3d-hub-flux cluster not reachable; skipping live bats"
  fi
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
}
```

**3×30s retry + jsonpath pattern (lines 19-33):**
```bash
@test "CAP-01 live (WR-03 fix): HelmRelease capsule reports Ready=True (3 attempts x 30s sleep, jsonpath column-anchored)" {
  local i ready
  for i in 1 2 3; do
    ready=$(kubectl --context=k3d-hub-flux -n capsule-system get helmrelease capsule \
      -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
    [[ "$ready" == "True" ]] && return 0
    [[ $i -lt 3 ]] && sleep 30
  done
  echo "Last observed Ready condition: '$ready'"
  return 1
}
```

**Substitutions for Phase 9 TEN-01 live (RESEARCH §"Bats Coverage" lines 1273-1278):**
- Cluster-info gate: only `k3d-spoke-capsule` (Tenant CRs land on spoke)
- Retry pattern verbatim, with jsonpath swap:
  - `kubectl --context=k3d-spoke-capsule get tenants alpha bravo -o jsonpath='{.items[*].spec.forceTenantPrefix}'` returns `true true`
  - `kubectl --context=k3d-spoke-capsule get sa -n tenant-alpha gitops-reconciler` exit 0 (mirror for bravo)

---

#### `tests/bats/tenants-07-live-impersonate.bats` (TEN-02 — `kubectl --as=alpha`)

**Analog:** No exact in-repo analog for `kubectl --as` impersonation. Setup gate transfers from Phase 8 capsule-install-06; body per RESEARCH §"Bats Coverage" lines 1280-1283.

**Pattern source (RESEARCH §"Bats Coverage" lines 1280-1283 + §Gap 7):**
```bash
load 'test_helper'

setup() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
}

@test "TEN-02 live: kubectl --as=alpha can create namespace alpha-app1 (idempotent)" {
  # Idempotent: ignore "AlreadyExists" — re-runs leave the namespace in place per D-09-07
  kubectl --context=k3d-spoke-capsule --as=alpha create namespace alpha-app1 \
    --dry-run=client -o yaml 2>/dev/null | \
    kubectl --context=k3d-spoke-capsule --as=alpha apply -f -
  # Auto-stamping verification
  local label
  label=$(kubectl --context=k3d-spoke-capsule get namespace alpha-app1 \
    -o jsonpath='{.metadata.labels.capsule\.clastix\.io/tenant}' 2>/dev/null || true)
  [[ "$label" == "alpha" ]]
}
```

**Substitutions vs Phase 8 jsonpath pattern:**
- 3×30s retry inherited from Phase 8 capsule-install-06 pattern
- Mirror test for bravo (substitute `alpha → bravo`)

---

#### `tests/bats/tenants-08-live-quota-limit.bats` (TEN-03 — auto-materialization)

**Analog:** `tests/bats/capsule-install-07-live-crds.bats` (lines 1-28) — kubectl get list + grep count pattern.

**Analog excerpt (lines 22-28):**
```bash
@test "CAP-03 live: each of the 7 expected CRD names is present" {
  for crd in tenants capsuleconfigurations globaltenantresources tenantresources \
             resourcepools resourcepoolclaims tenantowners; do
    run kubectl --context=k3d-spoke-capsule get crd "${crd}.capsule.clastix.io"
    [ "$status" -eq 0 ]
  done
}
```

**Substitutions for Phase 9 TEN-03 (RESEARCH §"Bats Coverage" lines 1285-1289):**
- `kubectl --context=k3d-spoke-capsule -n alpha-app1 get resourcequota -o jsonpath='{.items[*].metadata.name}'` matches `capsule-alpha-*` (regex)
- Mirror for limitrange + bravo
- Polls within 10s of namespace creation (depends on tenants-07 having run first; planner sequences via bats setup or test ordering)

---

#### `tests/bats/tenants-09-live-inner-k-ready.bats` (TEN-04 reconcile)

**Analog:** `tests/bats/capsule-install-10-live-flux-observable.bats` (lines 30-50) — exact pre-push skip pattern.

**Analog excerpt (lines 30-40):**
```bash
@test "FOLDED CARRYOVER: post-Phase-7 push gate — git log origin/main..main is empty" {
  if ! git -C "${REPO_ROOT}" rev-parse origin/main >/dev/null 2>&1; then
    skip "origin/main not tracked locally; skipping push-gate (deferred to Phase 11 VAL-05)"
  fi
  run bash -c "cd '${REPO_ROOT}' && git log origin/main..main --oneline"
  [ "$status" -eq 0 ]
  if [ -n "$output" ]; then
    skip "Local commits not pushed to origin/main yet; deferred-to-VAL-05"
  fi
}
```

**Substitutions for Phase 9 TEN-04 reconcile (RESEARCH §"Bats Coverage" lines 1291-1293):**
- Skip if GitRepository `tenant-alpha-source` is `Ready=False with reason=ArtifactFailed` (pre-push state) — same `skip` pattern as analog
- Otherwise: `kubectl --context=k3d-hub-flux -n tenant-alpha get kustomization tenant-alpha-app -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'` returns `True`
- 3×30s retry pattern from Phase 8 capsule-install-06

---

#### `tests/bats/tenants-10-live-lockdown.bats` (TEN-05 live)

**Analog:** `tests/bats/capsule-install-06-live-helm.bats` (lines 19-46) — jsonpath retry pattern.

**Substitutions for Phase 9 TEN-05 live (RESEARCH §"Bats Coverage" lines 1295-1301):**
- `kubectl --context=k3d-hub-flux -n flux-system get deployment kustomize-controller -o jsonpath='{.spec.template.spec.containers[0].args}'` contains all 3 lockdown flags
- helm-controller args contain `--no-cross-namespace-refs=true` AND `--default-service-account=default` (RESEARCH §Gap 2 extends CONTEXT.md)
- notification-controller args contain `--no-cross-namespace-refs=true`
- All 3 controllers' `availableReplicas` matches `replicas` (proves no CrashLoopBackOff from misapplied flag — RESEARCH §Gap 2 line 235-236)
- `flux-system` Kustomization Ready=True (escape hatch validation per D-09-05a)
- Polls for 2 minutes total post-patch (catches controller restart window — RESEARCH §Gap 2 line 235-236)

---

#### `tests/bats/tenants-11-live-dependson.bats` (TEN-06 live)

**Analog:** `tests/bats/capsule-install-06-live-helm.bats` — jsonpath retry pattern.

**Substitutions for Phase 9 TEN-06 live (RESEARCH §"Bats Coverage" lines 1303-1306):**
- `kubectl --context=k3d-hub-flux -n flux-system get kustomization poc-capsule-spoke -o jsonpath='{.spec.dependsOn[0].name}'` returns `poc-capsule`
- `kubectl --context=k3d-hub-flux -n flux-system get kustomization poc-capsule-spoke -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'` returns `True`
- 3×30s retry pattern

---

#### `tests/bats/tenants-12-live-health-check.bats` (v0.18 regression gate)

**Analog:** `tests/bats/health-check-01-static.bats` (static pattern only) + `task health-check` invocation per CONTEXT D-09-09 / RESEARCH §Gap 11.

**Pattern source (RESEARCH §"Bats Coverage" lines 1308-1310):**
```bash
@test "v0.18 regression gate: task health-check exit 0 post-lockdown" {
  cd "$REPO_ROOT"
  run task health-check
  [ "$status" -eq 0 ]
}
```

**Substitutions:**
- Cluster-info gate: BOTH `k3d-hub-flux` AND all v0.18 spoke clusters (`k3d-spoke-ml`, `k3d-spoke-apps`) must be reachable; skip otherwise
- `task health-check` runs the v0.18 health-check.sh; per RESEARCH §Gap 11, this includes spoke-apps Available + spoke-ml Available + flux-system Ready

---

## Shared Patterns

### Authentication / kubeConfig pattern (P40 / P18 inheritance)

**Source:** `clusters/hub-flux/pocs/capsule-spoke.yaml` lines 35-38

**Apply to:**
- `pocs/capsule/tenants/alpha.yaml` (Kustomization doc — both alpha and bravo)
- `clusters/hub-flux/pocs/capsule-spoke.yaml` (preserve existing block)

**Pattern:**
```yaml
  kubeConfig:
    secretRef:
      name: spoke-capsule-kubeconfig
      key: value.yaml
```

**Why:** Without explicit `key: value.yaml`, Flux v2 silently falls back to default key behavior, which can result in in-cluster reconciliation (P18 silent-misroute). Phase 7's outer Kustomization already has this; Phase 8 HelmReleases match; Phase 9 inner Ks MUST also match. **RESEARCH §Gap 1 corollary:** the Secret MUST live in the same namespace as the Kustomization (Flux v2.8 unconditional same-namespace constraint), so Phase 9's per-tenant inner Ks live in `tenant-{alpha,bravo}` ns AND the Secret is mirrored there imperatively.

---

### P27 LOAD-BEARING DEFENSE — `serviceAccountName` non-null on every cross-cluster K

**Source:** RESEARCH §"Gap 3" lines 246-282 (Go API source comment). No karyon analog (Phase 9 introduces).

**Apply to:**
- Every Kustomization CR in `pocs/capsule/tenants/*.yaml` (per-tenant inner Ks): `spec.serviceAccountName: gitops-reconciler`
- `clusters/hub-flux/pocs/capsule.yaml` (hub-targeted; D-09-05a escape hatch): `spec.serviceAccountName: kustomize-controller`
- `clusters/hub-flux/pocs/capsule-spoke.yaml` (spoke-targeted; D-09-05 explicit clarity): `spec.serviceAccountName: kustomize-controller`

**Why:** Without explicit `serviceAccountName`, kustomize-controller falls through to `--default-service-account` flag's value (`default` SA on TARGET cluster). With the spoke-capsule-kubeconfig embedded cluster-admin token (Phase 7 Pattern 3), if BOTH `serviceAccountName` AND the flag fallback fail, the K applies as cluster-admin on spoke, BYPASSING Capsule's webhooks (which deliberately exempt cluster-admin / kube-system identities). Hence: explicit serviceAccountName is the primary structural defense; the `--default-service-account` flag is belt-and-suspenders.

---

### Bats `load + setup` pattern (Phase 7+8 inheritance)

**Source:** `tests/bats/capsule-install-01-static-helmrelease.bats` lines 1-13, `tests/bats/test_helper.bash` line 22 (`REPO_ROOT` resolution)

**Apply to:** All 12 new Phase 9 bats files

**Pattern (static):**
```bash
#!/usr/bin/env bats
# tests/bats/tenants-NN-static-<topic>.bats
load 'test_helper'

setup() {
  ALPHA_TENANT="${REPO_ROOT}/pocs/capsule/spoke/tenants/alpha/tenant.yaml"
  # ... other path vars
}
```

**Pattern (live, with cluster-info gate):**
```bash
load 'test_helper'

setup() {
  if ! kubectl --context=k3d-hub-flux cluster-info >/dev/null 2>&1; then
    skip "k3d-hub-flux cluster not reachable; skipping live bats"
  fi
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
}
```

**Why:** `load 'test_helper'` resolves to `tests/bats/test_helper.bash`, which provides `REPO_ROOT` (line 22). RESEARCH §"Pattern 4" specifies `cluster-info` gating instead of `require_live` — auto-skips on unreachable cluster without requiring `KARYON_LIVE_TESTS=1` env var. Matches CONTEXT D-08-09 (Phase 8) and D-09-08 (Phase 9 reuses).

---

### `yq eval` compound assertion + `[ "$output" = "true" ]` final check (Phase 7+8 inheritance)

**Source:** `tests/bats/capsule-install-01-static-helmrelease.bats` lines 14-19, `tests/bats/poc-mount-01-static.bats` lines 50-76

**Apply to:** All 5 static Phase 9 bats files (tenants-01 through tenants-05)

**Pattern:**
```bash
@test "TEN-01: alpha tenant CR has apiVersion + kind + name + forceTenantPrefix=true" {
  [ -f "$ALPHA_TENANT" ]
  run yq eval '.apiVersion == "capsule.clastix.io/v1beta2" and .kind == "Tenant" and .metadata.name == "alpha" and .spec.forceTenantPrefix == true' "$ALPHA_TENANT"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}
```

**Why:** `yq eval` returns `true`/`false` as stdout when given a boolean expression. Compound `and`/`or` allows multi-field assertions in one test. The `[ "$output" = "true" ]` check distinguishes "expression is true" (PASS) from "expression is false" (FAIL) — bats's `run` would silently swallow this distinction otherwise.

---

### Multi-doc YAML splitting for P27 lint (Phase 8 WR-01..04 hardening direction)

**Source:** RESEARCH §"Bats Coverage" lines 1233-1242 (no in-repo analog for multi-doc lint).

**Apply to:** `tests/bats/tenants-02-static-p27.bats`

**Pattern:**
```bash
for f in "$REPO_ROOT/pocs/capsule/tenants/"*.yaml; do
  while IFS= read -r doc; do
    if echo "$doc" | yq eval '.kind == "Kustomization" and .apiVersion == "kustomize.toolkit.fluxcd.io/v1"' - 2>/dev/null | grep -qx "true"; then
      sa=$(echo "$doc" | yq eval '.spec.serviceAccountName' -)
      [ "$sa" != "null" ] && [ -n "$sa" ]
    fi
  done < <(yq eval '. as $doc ireduce ([];  . + [$doc])' "$f" | yq eval '.[] | split_doc' -)
done
```

**Why:** `pocs/capsule/tenants/alpha.yaml` is a multi-doc YAML (Namespace + GitRepository + Kustomization separated by `---`). Phase 8's single-doc yq pattern doesn't cover this; the loop splits documents and checks only the Kustomization docs.

---

### Sentinel-guarded patch surface (Phase 7 D-09 / Phase 9 D-09-05)

**Source:** `clusters/hub-flux/flux-system/kustomization.yaml` lines 1-13 (FLUX PATCH SURFACE comment) + lines 19-22 (`# KARYON SPOKES MOUNT` + `# KARYON POC MOUNT`)

**Apply to:** `clusters/hub-flux/flux-system/kustomization.yaml` (modified) — Phase 9 ADDS `# KARYON FLUX LOCKDOWN PATCHES (D-09-05 / TEN-05)` sentinel above the new `patches:` block.

**Pattern (existing — preserved):**
```yaml
# ──────────────────────────────────────────────────────────────────────────
# FLUX PATCH SURFACE
# ...
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
# KARYON FLUX LOCKDOWN PATCHES (D-09-05 / TEN-05)   ← NEW Phase 9 sentinel
patches:
  - ...
```

**Why:** The FLUX PATCH SURFACE is the documented supported edit point per the file's own header comment block ("Edits here SURVIVE re-bootstrap"). The 3 sentinels (SPOKES MOUNT, POC MOUNT, FLUX LOCKDOWN PATCHES) are static-bats grep targets — verifier asserts each appears EXACTLY ONCE (idempotency / P30 sentinel-uniqueness contract).

---

### Cross-namespace `kubectl --context=k3d-{cluster}` invocation (Phase 7+8 inheritance)

**Source:** `tests/bats/capsule-install-06-live-helm.bats` lines 26-30, `tests/bats/capsule-install-09-live-adr-004.bats` lines 22-31

**Apply to:** All 7 live Phase 9 bats files (tenants-06 through tenants-12)

**Pattern (Claude's Discretion default per CONTEXT D-09-08 — explicit context, NEVER reads ambient KUBECONFIG):**
```bash
ready=$(kubectl --context=k3d-hub-flux -n capsule-system get helmrelease capsule \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
[[ "$ready" == "True" ]] && return 0
```

**Why:** Explicit `--context=k3d-{cluster}` form — clean failure mode if context is missing; never reads ambient KUBECONFIG. Matches Phase 7+8 + CONTEXT D-09-08 default.

---

### 3-attempt × 30s sleep retry (WR-03 jsonpath-anchored from Phase 8)

**Source:** `tests/bats/capsule-install-06-live-helm.bats` lines 19-33 (WR-03 fix replaces fragile flux-get regex with kubectl jsonpath)

**Apply to:** `tenants-06`, `tenants-09`, `tenants-11` (live Ready=True checks); also `tenants-10` (with 2-minute total polling)

**Pattern:**
```bash
@test "TEN-NN live: <resource> reports Ready=True (3 attempts × 30s sleep)" {
  local i ready
  for i in 1 2 3; do
    ready=$(kubectl --context=<ctx> -n <ns> get <kind> <name> \
      -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
    [[ "$ready" == "True" ]] && return 0
    [[ $i -lt 3 ]] && sleep 30
  done
  echo "Last observed Ready condition: '$ready'"
  return 1
}
```

**Why:** WR-03 fix from Phase 8 review (08-REVIEW.md): replaces `flux get | grep -qE 'name[[:space:]]+.*True'` (admits false positives if MESSAGE column contains "True" substring) with kubectl jsonpath against the explicit Ready condition status field. Unambiguous parsing. Matches Phase 8 capsule-install-06 verbatim.

---

### Imperative kubectl apply with idempotent dry-run pattern (Phase 7 inheritance)

**Source:** `scripts/register-poc-cluster.sh` lines 187-196 (`apply_hub_secret`)

**Apply to:** `scripts/register-poc-cluster.sh` extension (`mirror_kubeconfig_to_tenant_namespaces` function)

**Pattern:**
```bash
kubectl --context "${HUB_CTX}" -n "${FLUX_NS}" create secret generic "${spoke}-kubeconfig" \
  --from-file=value.yaml=/dev/stdin --dry-run=client -o yaml |
  kubectl --context "${HUB_CTX}" -n "${FLUX_NS}" apply -f -
```

**Why:** `create ... --dry-run=client -o yaml | kubectl apply -f -` is the canonical idempotent-create pattern. Re-running the script is safe (re-applies the same Secret). Phase 9's mirror function adapts this with a yq pipe to strip `resourceVersion`/`uid`/`creationTimestamp` from a read-then-rewrite source.

---

## No Analog Found

Files with no close match in the codebase (planner uses RESEARCH.md patterns instead):

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `pocs/capsule/spoke/config/capsuleconfig.yaml` | Capsule CR | spoke apply | Phase 9 introduces the FIRST CapsuleConfiguration in karyon. Use RESEARCH §"Gap 5" lines 408-453 verbatim. |
| `pocs/capsule/spoke/tenants/{alpha,bravo}/tenant.yaml` | Capsule CR | spoke apply | Phase 9 introduces the FIRST Tenant in karyon. Use RESEARCH §"Gap 4" lines 313-372 verbatim with `alpha → bravo` substitution for bravo. |
| `pocs/capsule/spoke/tenants/{alpha,bravo}/sa.yaml` | k8s ServiceAccount | spoke apply | No karyon analog for ServiceAccount yaml (v0.18 uses imperative ServiceAccount creation in scripts). Use RESEARCH §"Code Examples" lines 858-871 verbatim. Shape is canonical k8s. |
| `pocs/capsule/tenants/{alpha,bravo}.yaml` (multi-doc Namespace + GitRepository + Kustomization with `kubeConfig` + `serviceAccountName` + `dependsOn`) | Multi-doc Flux Kustomization with cross-cluster impersonation | hub apply (per-tenant ns + GitRepository) → spoke apply (via inner K's kubeConfig + impersonation) | Phase 9 introduces the FIRST cross-cluster-impersonation Kustomization (`spec.serviceAccountName` on a Kustomization with `spec.kubeConfig`). Phase 8's `clusters/hub-flux/pocs/capsule-spoke.yaml` is the closest (kubeConfig present), but lacks `serviceAccountName`. Use RESEARCH §"Code Examples" lines 925-1002 verbatim with `alpha → bravo` substitution. |
| `clusters/hub-flux/flux-system/kustomization.yaml` `patches:` block | Kustomize `patches:` block targeting Deployments + Kustomization CRs | declarative; resolved by hub kustomize-controller (self-applied via `flux-system` K) | Phase 9 introduces the FIRST Kustomize `patches:` block in karyon. Use RESEARCH §"Code Examples" lines 1086-1127 verbatim (extends CONTEXT.md narrowing per RESEARCH §Gap 2). |
| `tests/bats/tenants-07-live-impersonate.bats` (`kubectl --as=alpha`) | Live `kubectl --as` impersonation bats | Apiserver impersonation + Capsule webhook authorization | No existing `kubectl --as`-based bats in repo. Use RESEARCH §"Bats Coverage" lines 1280-1283 + §Gap 7 verbatim. The setup() cluster-info gate matches Phase 8 Pattern 4. |
| `tests/bats/tenants-12-live-health-check.bats` (`task health-check` invocation) | Live `task` invocation bats | bats wrapping a v0.18 health-check shell flow | No existing `task`-invocation bats in repo (`health-check-01-static.bats` only checks the script's static shape, not invocation). Use RESEARCH §"Bats Coverage" lines 1308-1310 + §Gap 11 verbatim. |

**Net-new shape recovery:** Even though Capsule CRs + Kustomize `patches:` block + Flux `serviceAccountName` impersonation have no in-repo analog, RESEARCH.md provides verified-against-CRD-schema reference shapes (Gap 4 + Gap 5) and verified-against-fluxcd/flux2-multi-tenancy upstream reference shapes (Gap 2). The `kubeConfig.secretRef` block within each Phase 9 inner Kustomization IS analog'd (from `clusters/hub-flux/pocs/capsule-spoke.yaml` lines 35-38 — see Shared Patterns above).

---

## Regression Reruns (Phase 7+8 bats — UNCHANGED, must stay GREEN)

These existing bats files are NOT modified in Phase 9 but Plan 09-04 verifier MUST re-run them as regression gates per CONTEXT D-09-08:

| File | Why Re-run |
|------|------------|
| `tests/bats/poc-isolation-01-static.bats` | P31 / D-12 — confirms Phase 9's new files under `pocs/capsule/{tenants,spoke}/...` did NOT introduce `spoke-capsule` mentions in v0.18 scripts (none of the new files match the lint's grep set; `register-poc-cluster.sh` extension lives in P31-allowed POC scripts). |
| `tests/bats/poc-mount-01-static.bats` | P40 / P18 + D-08-12 split-path — confirms `clusters/hub-flux/pocs/capsule.yaml` still has NO kubeConfig AND `capsule-spoke.yaml` still has full `secretRef.name + key` block (Phase 9 modifies BOTH files but split-path invariant must still hold). Phase 9 ADDS `serviceAccountName` to both; this test asserts the existing fields are still present. |
| `tests/bats/capsule-install-{01..05}-static-*.bats` | Phase 8 contract — Phase 9 must NOT modify any Phase 8 file (`pocs/capsule/{operator,proxy}/*`). Verifier asserts these stay GREEN. |
| `tests/bats/capsule-install-{06..10}-live-*.bats` | Phase 8 invariants (CAP-01..03 + ADR-004 + outer K Ready=True). Phase 9 lockdown patches MUST NOT regress these. **Critical for Plan 09-03 mid-plan checkpoint** — re-run immediately after lockdown patches reconcile. |
| **`task health-check` (NOT a bats file but the v0.18 regression gate)** | RESEARCH §Gap 11 — Phase 9's lockdown patches touch v0.18 Flux bootstrap surface; the v0.18 health-check is the dominant regression gate. Plan 09-03 mid-plan checkpoint AND Plan 09-04 verifier both re-run. |

---

## Metadata

**Analog search scope:**
- `clusters/hub-flux/` (Flux state files; primary hub-targeted analogs)
- `clusters/spoke-{apps,ml}/` (Namespace + Kustomize aggregator analogs)
- `pocs/capsule/` (Phase 7+8 manifests; analog for subdir layout + multi-resource aggregators)
- `tests/bats/` (50+ existing bats files; identified capsule-install-*, poc-mount-01, poc-isolation-01, fix-coredns-01 as primary analogs)
- `scripts/register-poc-cluster.sh` (imperative kubectl Secret apply pattern)
- `scripts/lib/preflight-lib.sh` (output helpers, sourced via `test_helper.bash`)

**Files scanned:** ~30 (Flux yaml + bats + register-poc-cluster.sh + research/context/Phase-8-PATTERNS inputs)

**Pattern extraction date:** 2026-04-29

**RESEARCH.md sections used as no-analog fallback:**
- §"Gap 1: kubeConfig.secretRef under --no-cross-namespace-refs" lines 137-182 (Secret-mirror requirement → register-poc-cluster.sh extension)
- §"Gap 2: Per-controller flag acceptance for Flux v2.8.6" lines 186-238 (lockdown patches block — extends CONTEXT D-09-05 narrowing)
- §"Gap 3: --default-service-account flag scope" lines 242-285 (P27 root cause; comment-block-ready text for tenant.yaml)
- §"Gap 4: Tenant CR full shape (TEN-01..03)" lines 289-384 (verified against v0.12.4 raw CRD schema)
- §"Gap 5: CapsuleConfiguration shape" lines 388-455 (verified against v0.12.4 raw CRD schema; surfaced REQUIRED `enableTLSReconciler` field)
- §"Gap 7: kubectl --as=alpha impersonation prerequisites" lines 499-532 (no extra ClusterRoleBinding needed — k3d default kubeconfig has system:masters)
- §"Gap 10: Per-tenant GitRepository" lines 605-677 (GitRepository v1 shape; recommended Option A — hard-code `richard-iovanisci`)
- §"Gap 11: v0.18 health-check assertion subset" lines 681-724 (concrete subset Phase 9 verifier MUST confirm passing)
- §"Code Examples" lines 818-1205 (annotated yaml examples for every new file)
- §"Bats Test Coverage Recommendations" lines 1209-1316 (12 bats file specifications)

**Shared pattern attributions:**
- P40/P18 `kubeConfig.secretRef.key: value.yaml` — `clusters/hub-flux/pocs/capsule-spoke.yaml:35-38`
- P27 `serviceAccountName` non-null — RESEARCH §Gap 3:264-282 (no in-repo analog)
- Bats `load + setup` static — `tests/bats/capsule-install-01-static-helmrelease.bats:1-13` + `tests/bats/test_helper.bash:22`
- Bats `load + setup` live (cluster-info gate) — `tests/bats/capsule-install-06-live-helm.bats:1-17`
- `yq eval` compound assertion — `tests/bats/capsule-install-01-static-helmrelease.bats:14-19`
- 3×30s retry + jsonpath (WR-03) — `tests/bats/capsule-install-06-live-helm.bats:19-33`
- Sentinel-guarded patch surface — `clusters/hub-flux/flux-system/kustomization.yaml:1-22`
- Multi-doc YAML lint pattern — RESEARCH §"Bats Coverage":1233-1242 (no in-repo analog)
- Imperative kubectl apply (idempotent dry-run) — `scripts/register-poc-cluster.sh:187-196`
- Pre-push skip pattern — `tests/bats/capsule-install-10-live-flux-observable.bats:30-50`

## PATTERN MAPPING COMPLETE
