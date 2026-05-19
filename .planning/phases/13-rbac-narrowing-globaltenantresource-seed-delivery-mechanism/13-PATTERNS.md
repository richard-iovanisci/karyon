# Phase 13: RBAC Narrowing + GlobalTenantResource Seed + Delivery Mechanism - Pattern Map

**Mapped:** 2026-05-19
**Files analyzed:** 33 (NEW + EDITED YAML + scripts + bats + docs)
**Analogs found:** 33 / 33 — every Phase 13 artifact has an existing in-repo analog

## File Classification

### NEW YAML resources (under `pocs/capsule/spoke/`)

| New File | Role | Data Flow | Closest Analog | Match Quality |
|----------|------|-----------|----------------|---------------|
| `pocs/capsule/spoke/rbac/tenant-workload-editor.yaml` | resource YAML (ClusterRole) | Flux reconcile path | `pocs/capsule/spoke/rbac/platform-owner.yaml` (lines 20-64) | exact (ClusterRole shape, label set, head-comment pattern) |
| `pocs/capsule/spoke/rbac/platform-owner-sa.yaml` | resource YAML (ServiceAccount in `capsule-system`) | Flux reconcile path | `pocs/capsule/spoke/rbac/helm-controller-sa.yaml` (lines 36-40) | exact (SA in `capsule-system` ns shape) |
| `pocs/capsule/spoke/tenants/alpha/human-owner-sa.yaml` | resource YAML (ServiceAccount in `tenant-alpha`) | Flux reconcile path | `pocs/capsule/spoke/tenants/alpha/sa.yaml` (lines 9-13) | exact (per-tenant SA shape; just different name + head comment) |
| `pocs/capsule/spoke/tenants/bravo/human-owner-sa.yaml` | resource YAML (ServiceAccount in `tenant-bravo`) | Flux reconcile path | `pocs/capsule/spoke/tenants/alpha/sa.yaml` (s/alpha/bravo) | exact (alpha sibling — verbatim mirror) |
| `pocs/capsule/spoke/global-resources/hello-world.yaml` | resource YAML (GlobalTenantResource CR + embedded Pod + Service) | Flux reconcile path → Capsule controller materialization | `pocs/capsule/spoke/config/capsuleconfig.yaml` (lines 18-22 for Capsule CR cluster-scoped shape) + RESEARCH §"Pattern 1" for GTR `rawItems` body | role-match (cluster-scoped Capsule CR; GTR schema verified live + downloaded from v0.12.4 chart) |
| `pocs/capsule/spoke/global-resources/kustomization.yaml` | aggregator | Kustomize build | `pocs/capsule/spoke/config/kustomization.yaml` (lines 7-10) | exact (single-file aggregator shape) |

### EDITED YAML resources (additive only)

| Edited File | Role | Data Flow | Closest Analog | Match Quality |
|-------------|------|-----------|----------------|---------------|
| `pocs/capsule/spoke/rbac/platform-owner.yaml` | resource YAML (CRB subjects[] extension) | Flux reconcile path | self (lines 73-80) | exact (extend existing `subjects[]` array additively) |
| `pocs/capsule/spoke/rbac/kustomization.yaml` | aggregator | Kustomize build | self (lines 14-19) | exact (append 2 lines to `resources:` list, preserving sortOptions/fifo ordering) |
| `pocs/capsule/spoke/tenant-crs/alpha.yaml` | resource YAML (Tenant CR `spec.owners[]` + `containerRegistries.allowed` additions) | Flux reconcile path | self (lines 24-38 owners[]; lines 72-74 containerRegistries) | exact (append-only) |
| `pocs/capsule/spoke/tenant-crs/bravo.yaml` | resource YAML | Flux reconcile path | self (mirror of alpha) | exact |
| `pocs/capsule/spoke/tenants/alpha/kustomization.yaml` | aggregator | Kustomize build | self (lines 14-16) | exact (append `human-owner-sa.yaml` to `resources:`) |
| `pocs/capsule/spoke/tenants/bravo/kustomization.yaml` | aggregator | Kustomize build | self | exact |
| `pocs/capsule/spoke/kustomization.yaml` | aggregator | Kustomize build | self (lines 24-32) | exact (append `global-resources/` to `resources:`) |

### NEW bash scripts (under `scripts/poc/capsule/`)

| New File | Role | Data Flow | Closest Analog | Match Quality |
|----------|------|-----------|----------------|---------------|
| `scripts/poc/capsule/issue-platform-owner-kubeconfig.sh` | bash script (kubeconfig minter) | TokenRequest → stdout YAML / `--write-to` tmpdir | `scripts/poc/capsule/issue-tenant-kubeconfig.sh` (full file) | exact (verbatim shape; rename TENANT→none, OWNER→platform-owner pinned, context name `platform-owner-via-proxy`, namespace `capsule-system`) |
| `scripts/poc/capsule/new-tenant.sh` | bash script (Tenant CR + Namespace + SA provisioner) | template substitution → `kubectl --kubeconfig=$po_kc apply -f -` | `scripts/poc/capsule/create-cluster.sh` (lines 14-20 for preamble; lines 30-39 for preflight pattern) + `issue-tenant-kubeconfig.sh` lines 119-133 (RFC 1123 regex) | role-match (different action but same script scaffolding: REPO_ROOT pinning, preflight-lib, fail-fast pattern, regex name validation) |
| `scripts/poc/capsule/templates/new-tenant.yaml.tmpl` (OPTIONAL — planner discretion) | YAML template | sed/envsubst → kubectl apply | `pocs/capsule/spoke/tenant-crs/alpha.yaml` (entire file) | role-match (use as Tenant CR shape; substitute `<TENANT_NAME>` placeholder) |

### EDITED bash scripts

| Edited File | Role | Data Flow | Closest Analog | Match Quality |
|-------------|------|-----------|----------------|---------------|
| `scripts/poc/capsule/issue-tenant-kubeconfig.sh` | bash script | (existing) | self (lines 167-178) | exact (expand fail-fast SA enumeration to include `human-tenant-owner` alongside existing `gitops-reconciler`) |

### NEW bats test files (Wave 0 RED scaffold — 18 files)

| New File | Role | Data Flow | Closest Analog | Match Quality |
|----------|------|-----------|----------------|---------------|
| `tests/bats/rbac-01-static-tenant-workload-editor.bats` | bats test (static YAML grep) | static test | `tests/bats/capsule-install-04-static-no-umbrella.bats` (lines 26-29 yq path) + `tests/bats/proxy-02-static-leak-defenses.bats` (lines 16-22 grep-F pattern) | exact (yq + grep-F mixed) |
| `tests/bats/rbac-02-static-platform-owner-sa.bats` | bats test (static YAML grep) | static test | `tests/bats/proxy-02-static-leak-defenses.bats` (lines 16-22) | exact |
| `tests/bats/rbac-03-static-tenant-co-ownership.bats` | bats test (static YAML yq path + grep) | static test | `tests/bats/capsule-install-04-static-no-umbrella.bats` (lines 26-29 yq array walk) | exact |
| `tests/bats/rbac-04-static-human-owner-sa.bats` | bats test (static YAML grep) | static test | `tests/bats/proxy-02-static-leak-defenses.bats` | exact |
| `tests/bats/rbac-05-live-tenant-owner-grant-matrix.bats` | bats test (live kubectl auth can-i) | live test (gated on cluster-info) | `tests/bats/negative-rbac-03-webhook-policy.bats` (lines 30-34 setup_file mints kubeconfig; lines 60-64 setup gate; lines 66-71 `kubectl auth can-i` style negative test) | exact |
| `tests/bats/rbac-06-live-tenant-kubeconfig.bats` | bats test (live kubeconfig + can-i) | live test | `tests/bats/negative-rbac-03-webhook-policy.bats` (full file; uses `bash scripts/poc/capsule/issue-tenant-kubeconfig.sh` setup) | exact |
| `tests/bats/rbac-07-live-flux-sa-preservation.bats` | bats test (live jsonpath query) | live test | `tests/bats/capsule-install-09-live-adr-004.bats` (lines 22-31 jsonpath state probe) | exact |
| `tests/bats/rbac-08-live-platform-owner-grant-matrix.bats` | bats test (live can-i matrix) | live test | `tests/bats/negative-rbac-03-webhook-policy.bats` (setup pattern) + RESEARCH "kubectl auth can-i" loop | exact |
| `tests/bats/rbac-09-live-platform-owner-kubeconfig.bats` | bats test (live kubeconfig LIST through proxy) | live test | `tests/bats/negative-rbac-03-webhook-policy.bats` + RESEARCH §"capsule-proxy LIST filter test" | exact |
| `tests/bats/rbac-10-live-tenant-crud.bats` | bats test (live CRUD via kubectl --kubeconfig) | live test | `tests/bats/negative-rbac-03-webhook-policy.bats` (lines 66-103 create + assert + delete pattern) | exact |
| `tests/bats/seed-01-static-globaltenantresource.bats` | bats test (static YAML grep + yq) | static test | `tests/bats/capsule-install-04-static-no-umbrella.bats` (yq) + `tests/bats/proxy-02-static-leak-defenses.bats` (grep-F) | exact |
| `tests/bats/seed-02-live-existing-tenants.bats` | bats test (live wait for Pod Ready in tenant ns) | live test | `tests/bats/tenants-08-live-quota-limit.bats` (lines 26-36 jsonpath poll with sleep loop) | exact |
| `tests/bats/seed-03-live-fresh-tenant.bats` | bats test (live new-tenant + wait Pod Ready ≤60s + teardown) | live test | `tests/bats/tenants-08-live-quota-limit.bats` (poll pattern) + `tests/bats/negative-rbac-03-webhook-policy.bats` (lines 99-103 idempotent cleanup) | exact |
| `tests/bats/seed-04-live-shape.bats` | bats test (live no-Deployment / no-ReplicaSet assertion) | live test | `tests/bats/capsule-install-09-live-adr-004.bats` (zero-count assertion pattern) | role-match |
| `tests/bats/delivery-01-static-mount-sentinel.bats` | bats test (static file grep) | static test | `tests/bats/proxy-02-static-leak-defenses.bats` (grep-F pattern verbatim) | exact |
| `tests/bats/delivery-02-static-paths.bats` | bats test (static file existence + grep) | static test | `tests/bats/proxy-02-static-leak-defenses.bats` (file-existence + content) + `tests/bats/phase5-02-live.bats` (lines 65-75 negative-grep "forbidden" pattern) | exact |
| `tests/bats/delivery-03-live-additive-only.bats` | bats test (git diff against Phase 12 base SHA) | live test (git inspection) | `tests/bats/phase5-02-live.bats` (negative-grep guard pattern at lines 65-75; planner adapts to `git diff`) | role-match (no existing `git diff` bats; phase5-02 anti-pattern guard is closest shape) |
| `tests/bats/delivery-04-live-flux-reconcile.bats` | bats test (Flux Kustomization Ready=True) | live test | `tests/bats/capsule-install-09-live-adr-004.bats` (lines 10-14 cluster-info gate; lines 22-31 jsonpath state assertion) | exact (substitute `flux-system` for tenant ns; assert `Ready=True` on multiple Ks) |
| `tests/bats/delivery-05-live-slo-regression.bats` | bats test (KARYON_REBUILD_APPROVED env-gated rebuild + elapsed≤230s) | live test (destructive) | `tests/bats/phase5-02-live.bats` (lines 7-22 env-gated rebuild log + elapsed assertion) | exact (rename env var KARYON_LIVE_TESTS_DESTRUCTIVE → KARYON_REBUILD_APPROVED; assert ≤230s instead of ≤1200s) |

### DOCS EDIT

| Edited File | Role | Data Flow | Closest Analog | Match Quality |
|-------------|------|-----------|----------------|---------------|
| `docs/poc-capsule.md` (APPEND "Platform-owner kubeconfig" H2 subsection) | markdown documentation | docs-only | self (lines 146-189 — "Tenant kubeconfig delivery contract" H2 section pattern) | exact (mirror H2 + Status callout + Quickstart + Contract table + cross-references) |

## Pattern Assignments

### `pocs/capsule/spoke/rbac/tenant-workload-editor.yaml` (NEW; ClusterRole; Flux reconcile path)

**Analog:** `pocs/capsule/spoke/rbac/platform-owner.yaml` lines 1-65

**Conventions to mirror:**
- Single `apiVersion: rbac.authorization.k8s.io/v1` + `kind: ClusterRole` document (NO ClusterRoleBinding inside this file; binding happens via Tenant CR `spec.owners[].clusterRoles`)
- Head comment includes: file path one-liner, REQ tag (RBAC-01), decision tag (D-13-04), threat-model note, Local POC usage example, Production translation note
- `metadata.labels: { karyon.io/poc: capsule, karyon.io/role: capsule-tenant-workload-editor }` (matches existing platform-owner labelset)
- `rules[]` grouped by `apiGroups` block; each block comments the intent ("workload management", "service exposure", "workload configuration", etc.)
- **CRITICAL anti-pattern (Pitfall 13-P3):** DO NOT add any `rbac.authorization.k8s.io/aggregate-to-edit: "true"` label — bats RBAC-01 static greps for `! grep -F "aggregate-to-" tenant-workload-editor.yaml`

**Pattern excerpt** (from `pocs/capsule/spoke/rbac/platform-owner.yaml` lines 20-46):
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: capsule-platform-owner
  labels:
    karyon.io/poc: capsule
    karyon.io/role: capsule-platform-owner
rules:
  # See all Capsule API resources, including future v0.12.x CRDs/subresources.
  - apiGroups:
      - capsule.clastix.io
    resources:
      - "*"
    verbs:
      - get
      - list
      - watch
  # Manage the lower-level tenant definitions. Status updates remain controller-owned.
  - apiGroups:
      - capsule.clastix.io
    resources:
      - tenants
    verbs:
      - create
      - update
      - patch
      - delete
```

---

### `pocs/capsule/spoke/rbac/platform-owner-sa.yaml` (NEW; ServiceAccount in `capsule-system`)

**Analog:** `pocs/capsule/spoke/rbac/helm-controller-sa.yaml` lines 36-40

**Conventions to mirror:**
- Single `apiVersion: v1` + `kind: ServiceAccount` document (NO ClusterRoleBinding — binding is in the SEPARATE `platform-owner.yaml` edit which extends existing CRB `subjects[]`)
- Head comment: file path, REQ/decision tags (D-13-06), short rationale (why a real SA exists alongside the Group subject)
- Labels: `{ karyon.io/poc: capsule, karyon.io/role: capsule-platform-owner }` (matches Tier 2 role grouping)
- Namespace: MUST be `capsule-system` (exists via `pocs/capsule/spoke/rbac/namespace.yaml`)

**Pattern excerpt** (from `pocs/capsule/spoke/rbac/helm-controller-sa.yaml` lines 36-40):
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: helm-controller
  namespace: capsule-system
```

---

### `pocs/capsule/spoke/tenants/{alpha,bravo}/human-owner-sa.yaml` (NEW; per-tenant SA)

**Analog:** `pocs/capsule/spoke/tenants/alpha/sa.yaml` (full file, 13 lines)

**Conventions to mirror:**
- Single SA document with `metadata.name: human-tenant-owner` and `metadata.namespace: tenant-<tenant>`
- Head comment: file path, REQ tag (RBAC-01 / RBAC-02), decision tag (D-13-05), brief contrast vs sibling `sa.yaml` ("gitops-reconciler is the Flux SA owner; human-tenant-owner is the operator-bound SA")
- Same per-tenant namespace pattern as existing `sa.yaml`

**Pattern excerpt** (from `pocs/capsule/spoke/tenants/alpha/sa.yaml` lines 1-13):
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

### `pocs/capsule/spoke/global-resources/hello-world.yaml` (NEW; GlobalTenantResource CR)

**Analog:** `pocs/capsule/spoke/config/capsuleconfig.yaml` lines 18-22 (Capsule CR cluster-scoped shape; CRD apiVersion + metadata) + RESEARCH §"Pattern 1: GlobalTenantResource with rawItems" lines 296-343

**Conventions to mirror:**
- `apiVersion: capsule.clastix.io/v1beta2` (verified live storage version; see RESEARCH finding #1)
- `kind: GlobalTenantResource` (verified from `kubectl get crd globaltenantresources.capsule.clastix.io`)
- Cluster-scoped resource — NO `metadata.namespace`
- Head comment: file path, REQ tag (SEED-01..03), decision tag (D-13-11/12), explicit FQCI note (Pitfall 13-P1: image MUST be `docker.io/library/nginx:alpine`, NOT `nginx:alpine`)
- `spec.tenantSelector.matchLabels: {}` (empty map = match-all per RESEARCH §"Match-all tenant selector")
- `spec.resyncPeriod: 60s` (explicit for SEED-02 SLO clarity)
- `spec.resources[].additionalMetadata.labels.karyon.io/managed-by: capsule-global-tenant-resource` (provenance label for bats grep-assertions)
- `spec.resources[].rawItems[]` array with Pod + Service inline manifests

**Pattern excerpt — Capsule CR shape** (from `pocs/capsule/spoke/config/capsuleconfig.yaml` lines 18-22):
```yaml
apiVersion: capsule.clastix.io/v1beta2
kind: CapsuleConfiguration
metadata:
  name: default
spec:
  # ...
```

**Pattern excerpt — GTR body** (from RESEARCH.md lines 297-343, verified against v0.12.4 CRD):
```yaml
apiVersion: capsule.clastix.io/v1beta2
kind: GlobalTenantResource
metadata:
  name: hello-world-seeded
spec:
  tenantSelector:
    matchLabels: {}                 # match-all
  resyncPeriod: 60s
  resources:
    - additionalMetadata:
        labels:
          karyon.io/managed-by: capsule-global-tenant-resource
          karyon.io/poc: capsule
      rawItems:
        - apiVersion: v1
          kind: Pod
          metadata:
            name: hello-world
            labels:
              app: hello-world
          spec:
            containers:
              - name: nginx
                image: docker.io/library/nginx:alpine   # FQCI required
                ports:
                  - containerPort: 80
                    name: http
                resources:
                  requests: {cpu: 50m, memory: 64Mi}
                  limits: {cpu: 100m, memory: 128Mi}
```

---

### `pocs/capsule/spoke/global-resources/kustomization.yaml` (NEW; aggregator)

**Analog:** `pocs/capsule/spoke/config/kustomization.yaml` lines 1-10

**Conventions to mirror:**
- `apiVersion: kustomize.config.k8s.io/v1beta1` + `kind: Kustomization`
- Single-file `resources:` list
- Head comment: file path, role ("local Kustomize aggregator"), reference to parent K
- NO `sortOptions` required for single-file aggregator (config/kustomization.yaml omits it)

**Pattern excerpt** (from `pocs/capsule/spoke/config/kustomization.yaml` lines 1-10):
```yaml
# pocs/capsule/spoke/config/kustomization.yaml
# Local Kustomize aggregator for the spoke-side config subdir. Resolved by parent
# pocs/capsule/spoke/kustomization.yaml (Plan 09-01 rewrites to resources: [config/, tenants/]).
#
# D-09-01 / D-09-04 — config subdir under pocs/capsule/spoke/. Spoke-targeted
# (CapsuleConfiguration applies to spoke-capsule via poc-capsule-spoke outer K's kubeConfig).
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - capsuleconfig.yaml
```

---

### `pocs/capsule/spoke/rbac/platform-owner.yaml` (EDITED; CRB subjects[] extension)

**Analog:** self lines 65-80 (existing ClusterRoleBinding shape)

**Conventions to mirror:**
- **ADDITIVE ONLY:** Append the SA subject AFTER the existing Group subject. DO NOT remove, reorder, or modify the existing Group entry.
- Add comment annotations on each subject explaining its role (existing Group = impersonation path; NEW SA = TokenRequest kubeconfig path)
- Preserve existing labels, roleRef, metadata.name verbatim

**Pattern excerpt** (current file lines 65-80, showing the diff target):
```yaml
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: capsule-platform-owner
  labels:
    karyon.io/poc: capsule
    karyon.io/role: capsule-platform-owner
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: capsule-platform-owner
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: Group
    name: capsule-platform-owners
  # NEW (Phase 13 D-13-06 — additive): TokenRequest-backed SA kubeconfig path
  - kind: ServiceAccount
    name: platform-owner
    namespace: capsule-system
```

---

### `pocs/capsule/spoke/rbac/kustomization.yaml` (EDITED; add 2 entries to resources list)

**Analog:** self lines 14-19

**Conventions to mirror:**
- Preserve `namespace.yaml` FIRST (codex §2 HIGH #1 — capsule-system Namespace lands before SAs)
- Append `platform-owner-sa.yaml` after `helm-controller-sa.yaml` (both target `capsule-system` ns; alphabetical order or grouped-by-role both acceptable)
- Append `tenant-workload-editor.yaml` after `platform-owner.yaml` (groups all ClusterRoles together)
- Preserve head comment intent (the existing comment describes ordering rationale; planner appends new line items without rewriting the rationale)

**Pattern excerpt** (current file lines 14-19, showing append targets):
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - helm-controller-sa.yaml
  - platform-owner.yaml
  # NEW (Phase 13):
  - platform-owner-sa.yaml          # D-13-06
  - tenant-workload-editor.yaml     # D-13-04
```

---

### `pocs/capsule/spoke/tenant-crs/{alpha,bravo}.yaml` (EDITED; additive owners[] + containerRegistries)

**Analog:** self (alpha.yaml lines 24-38 owners[]; lines 72-74 containerRegistries)

**Conventions to mirror:**
- **ADDITIVE ONLY** to `spec.owners[]` — APPEND new entries; DO NOT remove/reorder existing entries (RBAC-03 regression gate via `delivery-03-live-additive-only.bats`)
- **ADDITIVE ONLY** to `spec.containerRegistries.allowed` — APPEND `docker.io` after existing `registry.example.io` (DELIVERY-03 + Pitfall 13-P1)
- New owner entries use the existing comment-block-then-entry style (see existing flux-reconciler + gitops-reconciler comments)
- For the new `human-tenant-owner` entry: USE `clusterRoles: [tenant-workload-editor]` (explicit override). For Group + SA platform-owner entries: OMIT `clusterRoles:` (Capsule default applies; Pitfall 13-P8 — never set `clusterRoles: []`)
- Mirror alpha.yaml → bravo.yaml verbatim with s/alpha/bravo/g

**Pattern excerpt — existing owners[]** (from `pocs/capsule/spoke/tenant-crs/alpha.yaml` lines 24-38):
```yaml
  # TEN-01 — multi-owner array
  owners:
    # Bootstrap Flux path (D-11-07): poc-capsule-spoke applies tenant-alpha
    # Namespace as flux-system/flux-reconciler. Capsule requires namespace
    # assignment to be performed by a Tenant owner, even when Kubernetes RBAC is
    # cluster-admin.
    - kind: ServiceAccount
      name: system:serviceaccount:flux-system:flux-reconciler
    # Flux impersonation chain (TEN-04 P27 defense)
    - kind: ServiceAccount
      name: system:serviceaccount:tenant-alpha:gitops-reconciler
      # Default clusterRoles: [admin, capsule-namespace-deleter] auto-applied
    # Human/CLI testing (TEN-02 `kubectl --as=alpha`)
    - kind: User
      name: alpha
```

**Pattern excerpt — existing containerRegistries** (from `pocs/capsule/spoke/tenant-crs/alpha.yaml` lines 66-74):
```yaml
  # N7 fixture (Phase 11 -- VAL-01 N7 registry-violation falsifier):
  # bats N7 runs `kubectl run x --image=docker.io/library/nginx -n alpha-app1` and asserts
  # webhook rejects with registry-violation error (only registry.example.io is allowed).
  # NOTE: ContainerRegistries field is marked deprecated in v0.12.4 (use Enforcement.Registries)
  # but the deprecated form still works for POC purposes.
  containerRegistries:
    allowed:
      - registry.example.io
      # NEW (Phase 13 D-13-12 + Pitfall 13-P1): required for FQCI nginx Pod propagation by GTR
      - docker.io
```

---

### `pocs/capsule/spoke/tenants/{alpha,bravo}/kustomization.yaml` (EDITED; add human-owner-sa.yaml)

**Analog:** self lines 14-16

**Conventions to mirror:**
- Preserve `sortOptions.order: fifo` if present
- Append `human-owner-sa.yaml` after `sa.yaml` (groups all SAs together; FIFO order means it lands after the existing SA in apply order — harmless because both are independent SAs in the same ns)

**Pattern excerpt** (current file lines 10-16):
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
sortOptions:
  order: fifo
resources:
  - namespace.yaml
  - sa.yaml
  # NEW (Phase 13 D-13-05): human-tenant-owner SA (RBAC-01 binding target)
  - human-owner-sa.yaml
```

---

### `pocs/capsule/spoke/kustomization.yaml` (EDITED; add global-resources/)

**Analog:** self lines 24-32

**Conventions to mirror:**
- Preserve `sortOptions.order: fifo` (defense-in-depth ordering)
- Append `global-resources/` at the END of `resources:` (after `tenants/`) — per CONTEXT D-13-13 sequencing note: tenant home namespaces exist BEFORE GTR applies, so GTR has a non-empty `Tenant.Status.Namespaces` to materialize into
- Preserve existing head comment; add 1-line annotation for the new subdir

**Pattern excerpt** (current file lines 24-32):
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
sortOptions:
  order: fifo
resources:
  - rbac/
  - config/
  - tenants/
  # NEW (Phase 13 D-13-13): GTR + Pod + Service propagation. Lands LAST so
  # Tenant.Status.Namespaces is non-empty when controller first reconciles.
  - global-resources/
```

---

### `scripts/poc/capsule/issue-platform-owner-kubeconfig.sh` (NEW; mirrors tenant kubeconfig minter)

**Analog:** `scripts/poc/capsule/issue-tenant-kubeconfig.sh` (full file, 344 lines)

**Conventions to mirror — REPLICATE VERBATIM:**
1. **Shebang + comment block + REQ/decision tags** (lines 1-27): `#!/usr/bin/env bash` + file path + REQ tag (RBAC-04..06 + DELIVERY-01) + decision tags (D-13-09/10) + Idempotency note + Stdout/stderr contract (Pitfall 10-P7) + Pitfall references (10-P1, 10-P2)
2. **`set -euo pipefail`** (line 29)
3. **REPO_ROOT/SCRIPT_DIR pinning + preflight-lib source** (lines 31-35)
4. **Stderr-redirect helper shadows** (lines 47-51): `section()`, `pass()`, `info()`, `warn()`, `fail()` — all print to `>&2` so stdout is reserved for the YAML kubeconfig payload
5. **Locked pin constants** (lines 53-58): `POC_CTX="k3d-spoke-capsule"`, `POC_NODEPORT="30443"`, `DEFAULT_DURATION="1h"`, `TMPDIR_DEFAULT`, `TENANT_TMPDIR` (rename: `PLATFORM_OWNER_TMPDIR` or reuse `TENANT_TMPDIR`)
6. **Usage block + `--duration` / `--write-to` parsing** (lines 61-114): WR-05 accept both space and equals forms
7. **RFC 1123 regex on positional args** (lines 119-133) — but platform-owner has NO positional args (SA name is pinned). Skip OR validate `--duration` value format only.
8. **Tool gate** (lines 136-144): `kubectl`, `jq`, `realpath`
9. **Context check** (lines 147-155): `k3d-spoke-capsule`
10. **SA exists check** (lines 167-178) — adapted: `kubectl --context=k3d-spoke-capsule -n capsule-system get sa platform-owner` (per D-13-09 preflight check #1)
11. **CRB exists + subjects check** (NEW for platform-owner; D-13-09 preflight checks #2-#3): assert `capsule-platform-owner` CRB exists AND `subjects[]` includes `ServiceAccount/platform-owner@capsule-system` via `kubectl ... get crb capsule-platform-owner -o jsonpath`
12. **`--write-to` validation** (lines 181-221): BL-01 symlink-TOCTOU defense + BL-02 umask 0077
13. **Duration portability info-warn** (lines 228-249): `duration_to_hours()` helper, info-warn at >24h
14. **TokenRequest** (lines 252-254): `kubectl create token platform-owner -n capsule-system --duration="${DURATION}"`
15. **Read tls.crt** (lines 264-306): WR-09 stderr capture + 3 failure modes (NotFound, empty, transient) + 1-retry after 5s sleep (Pitfall 10-P1: use `tls.crt` not `ca` per RESEARCH finding #7)
16. **Emit kubeconfig heredoc** (lines 308-343): adapt context name to `platform-owner-via-proxy`, user name to `platform-owner`, OMIT `namespace:` line (platform-owner ops are cluster-scoped per D-13-09)

**Pattern excerpt — Stderr-redirect helper shadows** (from `issue-tenant-kubeconfig.sh` lines 37-51):
```bash
# Pitfall 10-P7 stderr-redirect: shadow preflight-lib helpers with printf-to-stderr equivalents.
# preflight-lib helpers write to stdout by default; stdout in THIS script is the kubeconfig YAML
# payload, so log lines on stdout would corrupt it.
section() { printf '== %s ==\n' "$*" >&2; }
pass()    { printf '  ok  %s\n' "$*" >&2; }
info()    { printf '  --  %s\n' "$*" >&2; }
warn()    { printf '  !!  %s\n' "$*" >&2; }
fail()    { printf '  xx  %s\n' "$*" >&2; }
```

**Pattern excerpt — TokenRequest mint** (from `issue-tenant-kubeconfig.sh` lines 251-254):
```bash
section "Mint TokenRequest token (D-10-01)"
TOKEN=$(kubectl --context=k3d-spoke-capsule create token "${OWNER}" -n "tenant-${TENANT}" --duration="${DURATION}")
pass "token issued (duration ${DURATION})"
```

Adapted for platform-owner:
```bash
section "Mint TokenRequest token (D-13-09)"
TOKEN=$(kubectl --context=k3d-spoke-capsule create token platform-owner -n capsule-system --duration="${DURATION}")
pass "token issued (duration ${DURATION})"
```

**Pattern excerpt — Kubeconfig heredoc** (from `issue-tenant-kubeconfig.sh` lines 311-332):
```bash
emit_kubeconfig() {
  cat <<KUBECONFIG_EOF
apiVersion: v1
kind: Config
clusters:
  - name: capsule-proxy-127.0.0.1
    cluster:
      server: https://127.0.0.1:30443
      certificate-authority-data: ${CA_B64}
users:
  - name: ${OWNER}
    user:
      token: ${TOKEN}
contexts:
  - name: tenant-${TENANT}-via-proxy
    context:
      cluster: capsule-proxy-127.0.0.1
      user: ${OWNER}
      namespace: tenant-${TENANT}
current-context: tenant-${TENANT}-via-proxy
KUBECONFIG_EOF
}
```

Adapted for platform-owner (NOTE: no `namespace:` line; cluster name is the same per D-13-09):
```bash
emit_kubeconfig() {
  cat <<KUBECONFIG_EOF
apiVersion: v1
kind: Config
clusters:
  - name: capsule-proxy-127.0.0.1
    cluster:
      server: https://127.0.0.1:30443
      certificate-authority-data: ${CA_B64}
users:
  - name: platform-owner
    user:
      token: ${TOKEN}
contexts:
  - name: platform-owner-via-proxy
    context:
      cluster: capsule-proxy-127.0.0.1
      user: platform-owner
      # No namespace pin — platform-owner ops are cluster-scoped (D-13-09)
current-context: platform-owner-via-proxy
KUBECONFIG_EOF
}
```

---

### `scripts/poc/capsule/new-tenant.sh` (NEW; Tenant CR + Namespace + SA provisioner)

**Analogs:** `scripts/poc/capsule/create-cluster.sh` (lines 14-39 for preamble + preflight pattern) + `scripts/poc/capsule/issue-tenant-kubeconfig.sh` (lines 119-133 for RFC 1123 regex validation; lines 31-35 for REPO_ROOT pinning; lines 60-114 for arg parsing) + `pocs/capsule/spoke/tenant-crs/alpha.yaml` (for Tenant CR shape)

**Conventions to mirror:**
1. **Shebang + comment block + REQ/decision tags** (RBAC-05 + D-13-08)
2. **`set -euo pipefail` + REPO_ROOT pinning + preflight-lib source** — same shape as `create-cluster.sh` lines 14-20
3. **Use full preflight-lib helpers (NOT shadowed)** — `new-tenant.sh` stdout is informational ("created tenant phase13-fresh"), NOT a YAML payload, so the standard ANSI-colored `section/pass/warn/fail/info` helpers from preflight-lib are appropriate
4. **Positional arg `<name>` + flags `--dry-run` + `--kubeconfig <path>`** (D-13-08)
5. **Regex validation on `<name>`:** `^[a-z][a-z0-9-]{1,30}$` (D-13-08; stricter than the generic RFC 1123 because Capsule namespace prefix constraints)
6. **Default `--kubeconfig` resolution:** Read `${TMPDIR:-/tmp}/karyon-tenants/platform-owner.kubeconfig` if present, else fallback to `~/.kube/config` (D-13-08 + Pitfall 13-P5)
7. **Template rendering:** Either (a) inline heredoc with `${NAME}` substitution OR (b) `sed 's/<TENANT_NAME>/${NAME}/g' templates/new-tenant.yaml.tmpl` — planner discretion per CONTEXT D-13-08
8. **`--dry-run` path:** `cat` the rendered YAML to stdout WITHOUT applying; `kubectl --dry-run=client -f -` for additional validation
9. **Apply path:** `kubectl --kubeconfig="${KC}" apply -f -` with rendered YAML piped in
10. **Fail-fast pattern:** preflight-lib's `fail` + `exit 1` with FIX hint (mirrors `create-cluster.sh` lines 33-36)

**Pattern excerpt — Script preamble + preflight-lib source** (from `create-cluster.sh` lines 14-20):
```bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# shellcheck source=../../lib/preflight-lib.sh
# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/lib/preflight-lib.sh"
```

**Pattern excerpt — Fail-fast with FIX hint** (from `create-cluster.sh` lines 30-39):
```bash
section "Preflight gate (POC-04 includes 30443 fail-fast)"
if ! bash "${REPO_ROOT}/scripts/preflight.sh" >/tmp/preflight-poc-$$.log 2>&1; then
  fail "preflight has blockers -- likely 30443 in use (POC-04 fail-fast).
     Inspect: cat /tmp/preflight-poc-$$.log
     Fix:     free port 30443 (kill the listener) and rerun bash scripts/poc/capsule/create-cluster.sh"
  exit 1
fi
pass "preflight green"
```

**Pattern excerpt — Regex name validation** (from `issue-tenant-kubeconfig.sh` lines 125-129; adapt regex to D-13-08):
```bash
NAME_RE='^[a-z][a-z0-9-]{1,30}$'    # D-13-08 — stricter than generic RFC 1123
[[ "$NAME" =~ $NAME_RE ]] || {
  fail "<name> '${NAME}' is not a valid tenant name (lowercase a-z, 0-9, -; must start with letter; max 31 chars).
     Fix: use a tenant name matching ${NAME_RE}, e.g., 'phase13-fresh' or 'charlie'."
  exit 1
}
```

**Pattern excerpt — Tenant CR template body** (from `pocs/capsule/spoke/tenant-crs/alpha.yaml` lines 15-38; substitute `<TENANT_NAME>` placeholder):
```yaml
apiVersion: capsule.clastix.io/v1beta2
kind: Tenant
metadata:
  name: <TENANT_NAME>
spec:
  forceTenantPrefix: false
  owners:
    - kind: ServiceAccount
      name: system:serviceaccount:flux-system:flux-reconciler
    - kind: Group
      name: capsule-platform-owners
    - kind: ServiceAccount
      name: system:serviceaccount:capsule-system:platform-owner
    - kind: ServiceAccount
      name: system:serviceaccount:tenant-<TENANT_NAME>:human-tenant-owner
      clusterRoles:
        - tenant-workload-editor
  # D-13-08: minimal Tenant; planner researcher verified Capsule v0.12.4 accepts
  # minimal shape (no quotas, no limit ranges, no containerRegistries — defaults).
  # If webhook rejects, add: namespaceOptions, resourceQuotas, limitRanges,
  # containerRegistries.allowed: [docker.io] for GTR propagation.
```

---

### `scripts/poc/capsule/issue-tenant-kubeconfig.sh` (EDITED; expand <owner> enum)

**Analog:** self lines 167-178 (existing SA-exists check + available-SAs error hint)

**Conventions to mirror:**
- DO NOT modify any other section. The script's stdout/stderr contract, TLS read, TokenRequest mint, heredoc, and `--write-to` validation are ALL inherited verbatim (RBAC-02 regression).
- The ONLY edit is the help-text and the available-SAs error hint: explicitly list both `gitops-reconciler` AND `human-tenant-owner` as valid `<owner>` arg values (line 175 hint).
- The SA-exists check already works for any owner name — no new code path needed; just docs/hint update.

**Pattern excerpt — existing SA check + error hint** (from `issue-tenant-kubeconfig.sh` lines 167-178):
```bash
# ---------- Section 4: Owner SA exists ----------
section "Owner SA check (D-10-03)"
if ! kubectl --context="${POC_CTX}" -n "tenant-${TENANT}" get sa "${OWNER}" >/dev/null 2>&1; then
  AVAILABLE_SAS=$(kubectl --context="${POC_CTX}" -n "tenant-${TENANT}" get sa -o name 2>/dev/null \
      | sed 's|serviceaccount/||g' | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g')
  fail "Owner '${OWNER}' SA not found in namespace tenant-${TENANT}.
       Available SAs in this tenant: ${AVAILABLE_SAS:-<none>}.
       Hint: run /gsd-execute-phase 9 first if Phase 9 has not landed yet,
             or pass a known SA name (currently only 'gitops-reconciler')."   # <-- EDIT HERE
  exit 1
fi
pass "owner SA '${OWNER}' exists in tenant-${TENANT}"
```

Edit the hint to: `or pass a known SA name (currently 'gitops-reconciler' or 'human-tenant-owner').` and add a similar mention in the Usage block (lines 67-69).

---

### `tests/bats/rbac-01-static-tenant-workload-editor.bats` (NEW; static ClusterRole grep)

**Analogs:** `tests/bats/capsule-install-04-static-no-umbrella.bats` (lines 16-29 for `yq` path negative assertion) + `tests/bats/proxy-02-static-leak-defenses.bats` (lines 16-22 for `grep -F` literal assertion)

**Conventions to mirror:**
1. `#!/usr/bin/env bats` shebang
2. `load 'test_helper'` (provides `REPO_ROOT`, `pass/warn/fail/info/have`)
3. `setup()` block that sets file path vars (NOT cluster gate — static tests don't need cluster)
4. `@test` description format: `"<REQ-ID> / <decision-tag>: <human-readable assertion>"`
5. Mix of `grep -F` literal asserts (positive verbs present) and `yq eval` path asserts (denial categories absent)
6. Anti-pattern guard: `! grep -F "aggregate-to-"` (Pitfall 13-P3)

**Pattern excerpt — setup + file path vars + grep-F assertion** (from `proxy-02-static-leak-defenses.bats` lines 9-22):
```bash
load 'test_helper'

setup() {
  GITIGNORE="${REPO_ROOT}/.gitignore"
  GITLEAKS_TOML="${REPO_ROOT}/.gitleaks.toml"
  POSITIVE_FIXTURE="${REPO_ROOT}/tests/fixtures/gitleaks/synthetic-kubeconfig.yaml"
}

@test "PROXY-03 / D-10-09 (Phase 7 D-14 inheritance): .gitignore includes tenant-kubeconfig globs" {
  [ -f "$GITIGNORE" ]
  for literal in 'karyon-tenants/' '*.tenant.kubeconfig' 'tenants/**/access.yaml' 'tenants/**/admin.yaml'; do
    run grep -F -- "$literal" "$GITIGNORE"
    [ "$status" -eq 0 ]
  done
}
```

**Pattern excerpt — yq path assertion (negative)** (from `capsule-install-04-static-no-umbrella.bats` lines 26-29):
```bash
run yq eval '[.. | select(has("proxy")) | .proxy.enabled] | any_c(. == true)' "$OPERATOR_HR"
[ "$status" -eq 0 ]
[ "$output" = "false" ]
```

Adapted for RBAC-01 denial check:
```bash
# Denial 1: NO secrets create verb (must NOT match)
run yq eval '[.rules[] | select(.resources | contains(["secrets"])) | .verbs] | flatten | any_c(. == "create")' "$REPO_ROOT/pocs/capsule/spoke/rbac/tenant-workload-editor.yaml"
[ "$status" -eq 0 ]
[ "$output" = "false" ]

# Anti-pattern: NO aggregate-to-* labels (Pitfall 13-P3)
run grep -F -- 'aggregate-to-' "$REPO_ROOT/pocs/capsule/spoke/rbac/tenant-workload-editor.yaml"
[ "$status" -ne 0 ]
```

---

### `tests/bats/rbac-02-static-platform-owner-sa.bats` (NEW; static SA + CRB subjects grep)

**Analog:** `tests/bats/proxy-02-static-leak-defenses.bats` (lines 16-22 grep-F loop)

**Conventions to mirror:**
- `grep -F` for literal SA file shape: `kind: ServiceAccount`, `name: platform-owner`, `namespace: capsule-system`
- `grep -F` for CRB `subjects[]` containing both `kind: Group` + `name: capsule-platform-owners` AND `kind: ServiceAccount` + `name: platform-owner` + `namespace: capsule-system`
- File-existence first: `[ -f "$SA_YAML" ]`

**Pattern excerpt** — see `proxy-02-static-leak-defenses.bats` lines 16-22 above.

---

### `tests/bats/rbac-03-static-tenant-co-ownership.bats` (NEW; static Tenant CR owners[] yq)

**Analog:** `tests/bats/capsule-install-04-static-no-umbrella.bats` (lines 26-29 yq array walk)

**Conventions to mirror:**
- `yq eval '.spec.owners[] | select(.name == "...")'` to assert specific entries exist
- Assert existing entries (flux-reconciler SA, gitops-reconciler SA, User) preserved character-for-character (use `grep -F` for the exact name strings)
- Assert NEW entries present (human-tenant-owner SA with `clusterRoles: [tenant-workload-editor]`; Group capsule-platform-owners; platform-owner SA)
- Mirror alpha + bravo

---

### `tests/bats/rbac-04-static-human-owner-sa.bats` (NEW; static SA file shape)

**Analog:** `tests/bats/proxy-02-static-leak-defenses.bats` (grep-F pattern)

**Conventions to mirror:** Same as rbac-02; assert SA file exists with `kind: ServiceAccount`, `name: human-tenant-owner`, `namespace: tenant-<tenant>`. Mirror alpha + bravo.

---

### `tests/bats/rbac-05-live-tenant-owner-grant-matrix.bats` (NEW; live kubectl auth can-i matrix)

**Analog:** `tests/bats/negative-rbac-03-webhook-policy.bats` (lines 21-54 setup_file + setup + kubeconfig mint pattern; full file for kubectl-against-mintedkubeconfig pattern)

**Conventions to mirror:**
1. **Cluster gate in setup()** (lines 60-64): `if ! kubectl --context=k3d-spoke-capsule cluster-info; then skip; fi`
2. **setup_file kubeconfig mint** (lines 21-34): mint alpha/bravo kubeconfigs via `bash scripts/poc/capsule/issue-tenant-kubeconfig.sh alpha human-tenant-owner --duration=2h --write-to "${KARYON_BATS_TMPDIR}/alpha.kubeconfig"`
3. **teardown_file cleanup** (lines 56-58): `rm -rf "$KARYON_BATS_TMPDIR"`
4. **`kubectl auth can-i` loop pattern:** for positive verbs (pods, deployments, services CRUD), assert `[ "$status" -eq 0 ]` AND `[ "$output" = "yes" ]`; for denial verbs (secrets create, rolebindings *, resourcequotas *, limitranges *), assert `[ "$output" = "no" ]`

**Pattern excerpt — setup_file with kubeconfig mint** (from `negative-rbac-03-webhook-policy.bats` lines 21-34):
```bash
setup_file() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
  export KARYON_BATS_TMPDIR="${TMPDIR:-/tmp}/karyon-tenants/bats-${BATS_RUN_TMPDIR##*/}"
  mkdir -p "$KARYON_BATS_TMPDIR"
  bash "${REPO_ROOT}/scripts/poc/capsule/issue-tenant-kubeconfig.sh" alpha gitops-reconciler \
    --duration=2h --write-to "${KARYON_BATS_TMPDIR}/alpha.kubeconfig" >/dev/null 2>&1
  export ALPHA_KUBECONFIG="${KARYON_BATS_TMPDIR}/alpha.kubeconfig"
}
```

Adapted for RBAC-05 — mint with `human-tenant-owner` SA name:
```bash
setup_file() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
  export KARYON_BATS_TMPDIR="${TMPDIR:-/tmp}/karyon-tenants/bats-${BATS_RUN_TMPDIR##*/}"
  mkdir -p "$KARYON_BATS_TMPDIR"
  bash "${REPO_ROOT}/scripts/poc/capsule/issue-tenant-kubeconfig.sh" alpha human-tenant-owner \
    --duration=2h --write-to "${KARYON_BATS_TMPDIR}/alpha.kubeconfig" >/dev/null 2>&1
  export ALPHA_KUBECONFIG="${KARYON_BATS_TMPDIR}/alpha.kubeconfig"
}

@test "RBAC-01 / D-13-04 (positive): can create pods in tenant-alpha" {
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" auth can-i create pods -n tenant-alpha
  [ "$status" -eq 0 ]
  [ "$output" = "yes" ]
}

@test "RBAC-01 / D-13-01 (denial): cannot create secrets in tenant-alpha" {
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" auth can-i create secrets -n tenant-alpha
  [ "$output" = "no" ]
}
```

---

### `tests/bats/rbac-06-live-tenant-kubeconfig.bats` (NEW; live kubeconfig + auth can-i '*' '*' no)

**Analog:** `tests/bats/negative-rbac-03-webhook-policy.bats` (full file)

**Conventions to mirror:** Same setup_file + kubeconfig mint + `kubectl auth can-i '*' '*'` returns `no`; positive get pods works; create secret returns Forbidden.

---

### `tests/bats/rbac-07-live-flux-sa-preservation.bats` (NEW; live jsonpath state probe)

**Analog:** `tests/bats/capsule-install-09-live-adr-004.bats` (lines 22-31)

**Conventions to mirror:**
- Cluster gate in `setup()` (NOT `setup_file` — no shared state needed)
- `kubectl get tenant alpha -o jsonpath='{.spec.owners[?(@.name=="...")]}'` to assert existing entry preserved
- Distinguish "NotFound" from transient errors (WR-04 fix pattern from analog)

**Pattern excerpt** (from `capsule-install-09-live-adr-004.bats` lines 16-31):
```bash
@test "ADR-004 / domain-boundary-#4 (WR-04 fix): spoke-capsule flux-system ns has zero controllers (distinguishes NotFound from transient errors)" {
  local ns_check
  ns_check=$(kubectl --context=k3d-spoke-capsule get ns flux-system -o jsonpath='{.status.phase}' 2>&1 || true)
  if echo "$ns_check" | grep -qF 'NotFound'; then
    # ADR-004 invariant: namespace doesn't exist on spoke at all
    return 0
  fi
  # Namespace exists; assert zero pods
  local pod_count
  pod_count=$(kubectl --context=k3d-spoke-capsule get pods -n flux-system --no-headers 2>/dev/null | wc -l)
  [[ "$pod_count" -eq 0 ]]
}
```

---

### `tests/bats/rbac-08-live-platform-owner-grant-matrix.bats` (NEW; live can-i platform-owner SA)

**Analog:** `tests/bats/negative-rbac-03-webhook-policy.bats` (setup_file + kubeconfig pattern)

**Conventions to mirror:** Same setup as RBAC-05 but mint via `bash scripts/poc/capsule/issue-platform-owner-kubeconfig.sh > $tmpfile`. Use `kubectl --kubeconfig=$po_kc auth can-i`:
- positive: `create tenants`, `list namespaces`, `get customresourcedefinitions`
- denial: `'*' '*'`, `get nodes`, `get csr`, `create clusterrolebinding`

---

### `tests/bats/rbac-09-live-platform-owner-kubeconfig.bats` (NEW; live LIST through proxy)

**Analog:** `tests/bats/negative-rbac-03-webhook-policy.bats` + RESEARCH §"Capsule-proxy LIST filter test" lines 577-587

**Conventions to mirror:**
1. Mint platform-owner kubeconfig in `setup_file`
2. `kubectl --kubeconfig=$po_kc get tenants` → returns alpha + bravo
3. `kubectl --kubeconfig=$po_kc get namespaces` → returns tenant-alpha + tenant-bravo + alpha-app1 + bravo-app1, NOT kube-system
4. `kubectl --kubeconfig=$po_kc get nodes` → Forbidden (RBAC-04 ceiling)
5. `kubectl --kubeconfig=$po_kc get pods -n tenant-alpha` → succeeds (RBAC-06 co-owner)

---

### `tests/bats/rbac-10-live-tenant-crud.bats` (NEW; platform-owner Tenant CRUD)

**Analog:** `tests/bats/negative-rbac-03-webhook-policy.bats` (lines 66-103 create + assert + delete pattern)

**Conventions to mirror:**
1. Use `bash scripts/poc/capsule/new-tenant.sh phase13-fresh --kubeconfig $po_kc` to create
2. Assert `kubectl --kubeconfig=$po_kc get tenant phase13-fresh` succeeds
3. `kubectl --kubeconfig=$po_kc patch tenant phase13-fresh ...` succeeds
4. `kubectl --kubeconfig=$po_kc delete tenant phase13-fresh` succeeds
5. Idempotent cleanup in `teardown()` and `teardown_file()`

**Pattern excerpt — idempotent cleanup pattern** (from `negative-rbac-03-webhook-policy.bats` lines 99-103):
```bash
  # Idempotent cleanup
  kubectl --kubeconfig="$ALPHA_KUBECONFIG" delete namespace alpha-app2 --ignore-not-found --wait=false >/dev/null 2>&1 || true
  kubectl --kubeconfig="$ALPHA_KUBECONFIG" delete namespace alpha-app3 --ignore-not-found --wait=false >/dev/null 2>&1 || true
```

---

### `tests/bats/seed-01-static-globaltenantresource.bats` (NEW; static GTR shape grep)

**Analogs:** `tests/bats/capsule-install-04-static-no-umbrella.bats` (yq path) + `tests/bats/proxy-02-static-leak-defenses.bats` (grep-F literal)

**Conventions to mirror:**
- `grep -F` for `kind: GlobalTenantResource`, `apiVersion: capsule.clastix.io/v1beta2`, `matchLabels: {}`, `karyon.io/managed-by: capsule-global-tenant-resource`, `image: docker.io/library/nginx:alpine` (FQCI)
- `yq` for embedded Pod + Service shape (asserts both present in `rawItems[]`)
- Anti-pattern: NO `kind: Deployment`, NO `kind: ReplicaSet`, NO `kind: ConfigMap` in `rawItems[]` (SEED-03 boundary)

---

### `tests/bats/seed-02-live-existing-tenants.bats` (NEW; live wait for Pod Ready in alpha + bravo ns)

**Analog:** `tests/bats/tenants-08-live-quota-limit.bats` (lines 27-47 poll loop pattern)

**Conventions to mirror:**
- Cluster gate in `setup()`
- 3×10s poll for `kubectl get pod hello-world -n alpha-app1 -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'` → `True`
- Mirror for tenant-alpha, alpha-app1, bravo-app1, tenant-bravo (4 namespaces)
- Assert `karyon.io/managed-by: capsule-global-tenant-resource` label present on each Pod

**Pattern excerpt — 3×10s poll** (from `tenants-08-live-quota-limit.bats` lines 27-36):
```bash
@test "TEN-03 / D-09-04 (alpha): ResourceQuota auto-materializes in alpha-app1 namespace (capsule-alpha-* name, 3×10s poll)" {
  local i names
  for i in 1 2 3; do
    names=$(kubectl --context=k3d-spoke-capsule -n alpha-app1 get resourcequota -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)
    [[ "$names" == capsule-alpha-* ]] && return 0
    [[ $i -lt 3 ]] && sleep 10
  done
  echo "Last observed resourcequota names: '$names'"
  return 1
}
```

Adapted for SEED-02 (Pod Ready):
```bash
@test "SEED-01 (alpha-app1): hello-world Pod Ready=True within 30s (GTR auto-propagated)" {
  local i status
  for i in 1 2 3; do
    status=$(kubectl --context=k3d-spoke-capsule -n alpha-app1 get pod hello-world \
      -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
    [[ "$status" == "True" ]] && return 0
    [[ $i -lt 3 ]] && sleep 10
  done
  echo "Last observed Pod Ready status: '$status'"
  return 1
}
```

---

### `tests/bats/seed-03-live-fresh-tenant.bats` (NEW; new-tenant + ≤60s SEED-02 latency)

**Analogs:** `tests/bats/tenants-08-live-quota-limit.bats` (poll pattern) + `tests/bats/negative-rbac-03-webhook-policy.bats` (cleanup pattern)

**Conventions to mirror:**
1. `setup_file`: mint platform-owner kubeconfig
2. `setup`: run `bash scripts/poc/capsule/new-tenant.sh phase13-fresh --kubeconfig $po_kc` (creates Tenant + Namespace + SA)
3. Wait for `Tenant.Status.Namespaces` to be non-empty (Pitfall 13-P2 — controller hasn't materialized child ns yet)
4. `kubectl wait pod/hello-world --for=condition=Ready -n tenant-phase13-fresh --timeout=60s` — the wait IS the SEED-02 ≤60s assertion
5. `teardown_file`: `kubectl --kubeconfig=$po_kc delete tenant phase13-fresh; kubectl wait --for=delete namespace tenant-phase13-fresh --timeout=30s` (Pitfall 13-P6)

---

### `tests/bats/seed-04-live-shape.bats` (NEW; assert Pod + Service ONLY, no Deployment)

**Analog:** `tests/bats/capsule-install-09-live-adr-004.bats` (zero-count assertion pattern)

**Conventions to mirror:**
- `kubectl get deployment -n tenant-alpha --no-headers | wc -l` → `0` (no Deployment created by GTR)
- Same for `replicaset`, `configmap` (SEED-03 boundary)
- `kubectl get pod -n tenant-alpha hello-world` succeeds
- `kubectl get svc -n tenant-alpha hello-world` succeeds

---

### `tests/bats/delivery-01-static-mount-sentinel.bats` (NEW; static grep for KARYON POC MOUNT)

**Analog:** `tests/bats/proxy-02-static-leak-defenses.bats` (lines 16-22 grep-F pattern verbatim)

**Conventions to mirror:**
- File path: `clusters/hub-flux/flux-system/kustomization.yaml`
- `grep -F 'KARYON POC MOUNT'` → exactly 1 match (asserts sentinel present + not duplicated)
- `grep -F '../pocs'` → succeeds (resource line present)
- Anti-duplicate: `grep -c 'KARYON POC MOUNT' [target] = 1`

**Pattern excerpt** (from `proxy-02-static-leak-defenses.bats` lines 16-22):
```bash
@test "<REQ-ID>: <file> contains <literal>" {
  [ -f "$TARGET" ]
  for literal in 'literal1' 'literal2'; do
    run grep -F -- "$literal" "$TARGET"
    [ "$status" -eq 0 ]
  done
}
```

---

### `tests/bats/delivery-02-static-paths.bats` (NEW; assert all new files under correct dirs)

**Analogs:** `tests/bats/proxy-02-static-leak-defenses.bats` (file-existence) + `tests/bats/phase5-02-live.bats` (lines 65-75 forbidden-literals pattern)

**Conventions to mirror:**
- File-existence loop for all new files under `pocs/capsule/spoke/` and `scripts/poc/capsule/`
- Negative-grep: `! grep -F 'spoke-capsule' Taskfile.yml` (D-13-14 + P31)
- Negative-grep: `! grep -F 'spoke-capsule' scripts/preflight.sh` and other v0.18 default-path scripts (P31)

**Pattern excerpt — forbidden literals loop** (from `phase5-02-live.bats` lines 64-75):
```bash
@test "state checker source omits destructive invocations" {
  for forbidden in \
    "task re""build" \
    "task de""stroy" \
    "bash scripts/rebuild"".sh" \
    "bash scripts/destroy"".sh" \
    "bash scripts/delete-clusters"".sh" \
    "k3d cluster de""lete"
  do
    run grep -F -- "$forbidden" "$BATS_TEST_FILENAME"
    [ "$status" -ne 0 ]
  done
}
```

Adapted for delivery-02:
```bash
@test "DELIVERY-01 / D-13-14: Taskfile.yml is NOT modified by Phase 13 (no new spoke-capsule entries)" {
  [ -f "${REPO_ROOT}/Taskfile.yml" ]
  for forbidden in 'seed-capsule-demo' 'issue-platform-owner-kubeconfig' 'new-tenant'; do
    run grep -F -- "$forbidden" "${REPO_ROOT}/Taskfile.yml"
    [ "$status" -ne 0 ]
  done
}
```

---

### `tests/bats/delivery-03-live-additive-only.bats` (NEW; git diff against Phase 12 base)

**Analog:** No exact analog (no existing bats does git-diff inspection). Closest shape: `tests/bats/phase5-02-live.bats` lines 65-75 (negative-grep anti-pattern guard).

**Conventions to mirror:**
- Compute base SHA: planner picks Phase 12 last-commit SHA OR reads from `.planning/STATE.md` / git tag
- `git diff <base-sha> -- pocs/capsule/spoke/tenant-crs/alpha.yaml | grep -E '^\-[^-]'` → empty (no deletions; only `^\-\-\-` separator and `^\-` additions allowed; pure additive diff means `^-` lines are only diff headers `---`)
- Better: parse the diff with `yq` or count `^-` non-header lines

**Pattern excerpt (sketched; no direct analog):**
```bash
@test "DELIVERY-03 (alpha): Tenant CR spec.owners[] additions only (no removals from Phase 12 base)" {
  local base_sha
  base_sha=$(git rev-parse HEAD~10)   # planner verifies the right base
  local removals
  removals=$(git diff "$base_sha" -- pocs/capsule/spoke/tenant-crs/alpha.yaml \
    | grep -E '^-[^-]' | wc -l)
  [ "$removals" -eq 0 ]
}
```

---

### `tests/bats/delivery-04-live-flux-reconcile.bats` (NEW; assert Flux Ks Ready=True)

**Analog:** `tests/bats/capsule-install-09-live-adr-004.bats` (lines 10-14 cluster-info gate; lines 22-31 jsonpath state assertion)

**Conventions to mirror:**
- Cluster gate
- `kubectl --context=k3d-hub-flux get kustomization poc-capsule-spoke -n flux-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'` → `True`
- Loop over: `poc-capsule-spoke`, `poc-capsule-spoke-rbac`, `poc-capsule-spoke-tenants`

---

### `tests/bats/delivery-05-live-slo-regression.bats` (NEW; KARYON_REBUILD_APPROVED env-gated rebuild)

**Analog:** `tests/bats/phase5-02-live.bats` (lines 7-22 env-gated rebuild + elapsed assertion via `LOG_FILE`)

**Conventions to mirror:**
1. **Gate via env var:** `setup()` calls `require_live_destructive` OR equivalent that checks `KARYON_REBUILD_APPROVED=1` (Phase 13 uses this name per CONTEXT.md)
2. **Read `/tmp/karyon-rebuild.log`** for `rebuild elapsed seconds: <N>` pattern
3. **Assert `<N> -le 230`** (DELIVERY-02 SLO)
4. Skipped without the env var gate

**Pattern excerpt — env-gated rebuild log assertion** (from `phase5-02-live.bats` lines 7-23):
```bash
setup() {
  require_live_destructive
  LOG_FILE="/tmp/karyon-rebuild.log"
}

@test "rebuild log exists and contains elapsed seconds" {
  [ -f "$LOG_FILE" ]
  run grep -E '^rebuild elapsed seconds: [0-9]+' "$LOG_FILE"
  [ "$status" -eq 0 ]
}

@test "elapsed seconds <= 1200" {
  [ -f "$LOG_FILE" ]
  elapsed="$(grep -E '^rebuild elapsed seconds: [0-9]+' "$LOG_FILE" | awk '{print $4}' | tail -1)"
  [ -n "$elapsed" ]
  [ "$elapsed" -le 1200 ]
}
```

Adapted for DELIVERY-05 (rename gate var; assert ≤230s instead of ≤1200s):
```bash
setup() {
  if [[ "${KARYON_REBUILD_APPROVED:-}" != "1" ]]; then
    skip "DELIVERY-02 SLO regression — set KARYON_REBUILD_APPROVED=1 to run (destructive: rebuilds clusters)"
  fi
  LOG_FILE="/tmp/karyon-rebuild.log"
}

@test "DELIVERY-02 / Phase 13 SLO: rebuild elapsed seconds <= 230 (v0.18 baseline preserved)" {
  [ -f "$LOG_FILE" ]
  elapsed="$(grep -E '^rebuild elapsed seconds: [0-9]+' "$LOG_FILE" | awk '{print $4}' | tail -1)"
  [ -n "$elapsed" ]
  [ "$elapsed" -le 230 ]
}
```

---

### `docs/poc-capsule.md` (EDITED; APPEND "Platform-owner kubeconfig" H2 subsection)

**Analog:** self lines 146-189 — existing "Tenant kubeconfig delivery contract" H2 section

**Conventions to mirror:**
1. **H2 heading + Status callout:** `## Platform-owner kubeconfig delivery contract` + `> **Status:** Active. Phase 13 — RBAC-04..06.`
2. **1-paragraph intro:** "The `scripts/poc/capsule/issue-platform-owner-kubeconfig.sh` script mints..." (mirrors line 150)
3. **`### Platform-owner kubeconfig quickstart` H3** with a fenced bash block (mirrors lines 153-160)
4. **`### Platform-owner kubeconfig contract` H3** with a Markdown table (mirrors lines 162-172)
5. **`### Mandatory invariants` H3** referencing the same P29 leak defenses (the same `.gitignore` globs + `.gitleaks.toml` rule cover platform-owner kubeconfig because they live under the same `karyon-tenants/` tmpdir)
6. **`### Cross-references` H3** with Phase 13 RBAC-04..06, D-13-09/10, and the same EKS-translation forward-pointer

**Pattern excerpt — full H2 section to mirror** (from `docs/poc-capsule.md` lines 146-189):
```markdown
## Tenant kubeconfig delivery contract

> **Status:** Active. Phase 10 — PROXY-01..03.

The `scripts/poc/capsule/issue-tenant-kubeconfig.sh` script mints a short-lived,
tenant-owner kubeconfig that routes through capsule-proxy on NodePort 30443.

### Tenant kubeconfig quickstart

```bash
bash scripts/poc/capsule/issue-tenant-kubeconfig.sh alpha gitops-reconciler 2>/dev/null > /tmp/alpha.kubeconfig
KUBECONFIG=/tmp/alpha.kubeconfig kubectl get namespaces
# alpha-app1
# tenant-alpha
```

### Tenant kubeconfig contract

| Property | Value |
|---|---|
| Output channel default | stdout (pure YAML kubeconfig); `preflight-lib` log lines on stderr (clean redirect contract) |
| Optional file output | `--write-to <path>` — `<path>` MUST resolve under `${TMPDIR:-/tmp}/karyon-tenants/` (validated via `realpath -m` prefix check) |
| Server URL | `https://127.0.0.1:30443` (capsule-proxy NodePort; k3d serverlb host-publish) |
| Authentication | Bound SA token via `kubectl create token` (TokenRequest API); default `--duration=1h` |
| TLS trust | `certificate-authority-data` embedded in cluster block (read live from `capsule-proxy` Secret on spoke-capsule) |
| Default namespace in context | `tenant-<tenant>` (operator can override with `kubectl -n alpha-app1 ...`) |
| Issued context name | `tenant-<tenant>-via-proxy` (unambiguous when multiple tenant kubeconfigs are merged) |
```

Adapted for platform-owner (key delta: no positional `<tenant>` arg; `--duration=1h` default same; context name `platform-owner-via-proxy`; NO default namespace in context — cluster-scoped ops):
```markdown
## Platform-owner kubeconfig delivery contract

> **Status:** Active. Phase 13 — RBAC-04..06.

The `scripts/poc/capsule/issue-platform-owner-kubeconfig.sh` script mints a short-lived,
platform-owner kubeconfig that routes through capsule-proxy on NodePort 30443. The
identity is the `ServiceAccount/platform-owner` in the `capsule-system` namespace
(D-13-06), bound to the existing `capsule-platform-owner` ClusterRole via the dual-
subject ClusterRoleBinding.

### Platform-owner kubeconfig quickstart

```bash
bash scripts/poc/capsule/issue-platform-owner-kubeconfig.sh 2>/dev/null > /tmp/po.kubeconfig
KUBECONFIG=/tmp/po.kubeconfig kubectl get tenants
# alpha
# bravo
```
```

---

## Shared Patterns

### Cluster gate in live bats `setup()`

**Source:** `tests/bats/capsule-install-09-live-adr-004.bats` lines 10-14

**Apply to:** All NEW live bats files (rbac-05..10, seed-02..04, delivery-03..05)

```bash
load 'test_helper'

setup() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
}
```

---

### `setup_file` + `teardown_file` for kubeconfig minting

**Source:** `tests/bats/negative-rbac-03-webhook-policy.bats` lines 21-58

**Apply to:** `rbac-05`, `rbac-06`, `rbac-08`, `rbac-09`, `rbac-10`, `seed-03` (any test requiring a minted kubeconfig)

```bash
setup_file() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
  export KARYON_BATS_TMPDIR="${TMPDIR:-/tmp}/karyon-tenants/bats-${BATS_RUN_TMPDIR##*/}"
  mkdir -p "$KARYON_BATS_TMPDIR"
  bash "${REPO_ROOT}/scripts/poc/capsule/issue-tenant-kubeconfig.sh" alpha human-tenant-owner \
    --duration=2h --write-to "${KARYON_BATS_TMPDIR}/alpha.kubeconfig" >/dev/null 2>&1
  export ALPHA_KUBECONFIG="${KARYON_BATS_TMPDIR}/alpha.kubeconfig"
}

teardown_file() {
  rm -rf "$KARYON_BATS_TMPDIR"
}
```

---

### REPO_ROOT pinning + preflight-lib source (script preamble)

**Source:** `scripts/poc/capsule/create-cluster.sh` lines 14-20 (and same in every script under `scripts/poc/capsule/`)

**Apply to:** `new-tenant.sh`, `issue-platform-owner-kubeconfig.sh`

```bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# shellcheck source=../../lib/preflight-lib.sh
# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/lib/preflight-lib.sh"
```

---

### Fail-fast with FIX hint pattern

**Source:** `scripts/poc/capsule/create-cluster.sh` lines 33-37; `issue-tenant-kubeconfig.sh` lines 149-153

**Apply to:** All new scripts (`new-tenant.sh`, `issue-platform-owner-kubeconfig.sh`)

```bash
fail "<problem>.
   Inspect: <command to show state>
   Fix:     <command or step to resolve>"
exit 1
```

---

### Idempotent cleanup in bats teardown

**Source:** `tests/bats/negative-rbac-03-webhook-policy.bats` lines 101-103

**Apply to:** `rbac-10` (tenant CRUD), `seed-03` (fresh tenant), any test that creates Kubernetes resources

```bash
kubectl --kubeconfig="$KC" delete <resource> <name> --ignore-not-found --wait=false >/dev/null 2>&1 || true
```

For namespace deletion (Pitfall 13-P6 — wait for cascade):
```bash
kubectl --kubeconfig="$KC" delete tenant phase13-fresh --ignore-not-found >/dev/null 2>&1 || true
kubectl wait --for=delete namespace tenant-phase13-fresh --timeout=30s >/dev/null 2>&1 || true
```

---

### Head comment block (file-path + REQ tag + decision tag)

**Source:** Every existing file under `pocs/capsule/spoke/` has this shape. Best example: `pocs/capsule/spoke/rbac/platform-owner.yaml` lines 1-19

**Apply to:** All NEW YAML files (`tenant-workload-editor.yaml`, `platform-owner-sa.yaml`, `human-owner-sa.yaml`, `hello-world.yaml`, `global-resources/kustomization.yaml`) and all NEW bash scripts

```yaml
# pocs/capsule/spoke/rbac/<file>.yaml
# <one-line purpose>
#
# REQ: <RBAC-XX | SEED-XX | DELIVERY-XX>
# Decision: D-13-XX (<short rationale>)
# Pitfall: 13-PX (<if applicable>)
#
# <Brief contrast with sibling files, if any>
# <Production translation note, if applicable>
```

---

### Tenant CR additive owners[] entry shape

**Source:** RESEARCH §"Pattern 2" lines 351-383 (verified against Capsule v0.12.4 CRD); current `pocs/capsule/spoke/tenant-crs/alpha.yaml` lines 24-38

**Apply to:** `pocs/capsule/spoke/tenant-crs/{alpha,bravo}.yaml` edits + `scripts/poc/capsule/templates/new-tenant.yaml.tmpl` (or inline heredoc)

```yaml
# Implicit-default clusterRoles (Capsule applies [admin, capsule-namespace-deleter])
- kind: ServiceAccount
  name: system:serviceaccount:<ns>:<sa>

# Explicit-override clusterRoles (single ClusterRole only)
- kind: ServiceAccount
  name: system:serviceaccount:tenant-<tenant>:human-tenant-owner
  clusterRoles:                            # EXPLICIT — overrides default
    - tenant-workload-editor              # ONLY this role bound

# Group subject (impersonation path)
- kind: Group
  name: capsule-platform-owners
  # clusterRoles unset → Capsule default
```

**Pitfall 13-P8:** NEVER use `clusterRoles: []` (empty array) — strips ALL bindings instead of applying default.

---

### TokenRequest mint + tls.crt CA read + heredoc kubeconfig

**Source:** `scripts/poc/capsule/issue-tenant-kubeconfig.sh` lines 251-332 (full mint + CA + heredoc flow)

**Apply to:** `scripts/poc/capsule/issue-platform-owner-kubeconfig.sh` (full body inheritance with SA name + context name + namespace-pin delta)

See "Pattern excerpts — TokenRequest mint" and "Kubeconfig heredoc" under issue-platform-owner-kubeconfig.sh assignment above.

---

### Cluster-info gate fork (WR-04 fix — distinguish NotFound from transient)

**Source:** `tests/bats/capsule-install-09-live-adr-004.bats` lines 22-31

**Apply to:** Live bats that probe cluster state and need to disambiguate "absence" from "transient error" — particularly `rbac-07-live-flux-sa-preservation.bats` and `delivery-04-live-flux-reconcile.bats`

```bash
local probe
probe=$(kubectl --context=... get <resource> <name> -o jsonpath='...' 2>&1 || true)
if echo "$probe" | grep -qF 'NotFound'; then
  # Invariant satisfied via absence
  return 0   # OR return 1 depending on REQ
fi
# Resource exists; assert state
[[ "<expected>" == "$probe" ]]
```

---

## No Analog Found

| File | Role | Data Flow | Reason | Mitigation |
|------|------|-----------|--------|-----------|
| `tests/bats/delivery-03-live-additive-only.bats` | bats (git diff inspection) | live (git) | No existing bats does `git diff` parsing. | Use Phase 5 anti-pattern-guard shape (`grep -E '^-[^-]'` to count non-header removal lines); planner verifies the right Phase 12 base SHA (suggest reading from `.planning/STATE.md` or `git log --oneline | grep 'milestone v0.20'`) |

All other 32 Phase 13 files have a clear in-repo analog.

## Metadata

**Analog search scope:**
- `pocs/capsule/spoke/{rbac,tenants,tenant-crs,config,global-resources}/`
- `scripts/poc/capsule/`
- `scripts/lib/preflight-lib.sh`
- `tests/bats/` (focused on capsule-install-*, tenants-*, negative-rbac-*, proxy-*, phase5-*)
- `docs/poc-capsule.md`

**Files scanned (read directly):** 20
- 10 existing YAML files under `pocs/capsule/spoke/`
- 2 bash scripts under `scripts/poc/capsule/`
- 1 preflight-lib + 1 test_helper
- 6 bats test files (the closest analogs)
- 1 docs/poc-capsule.md (PROXY-03 H2 section)

**CONTEXT.md decisions covered:** D-13-01 through D-13-16 (16 decisions; all file types accounted for)

**RESEARCH.md Code Examples used:**
- §"Pattern 1: GlobalTenantResource with rawItems" (Pattern 1, lines 296-343)
- §"Pattern 2: Per-tenant Tenant CR owners with explicit clusterRoles override" (lines 351-383)
- §"Pattern 3: Dual-subject ClusterRoleBinding" (lines 391-410)
- §"Match-all tenant selector" (line 506-510)
- §"Reading capsule-proxy TLS cert" (line 514-525)
- §"Minting platform-owner TokenRequest token" (line 530-534)
- §"Issued kubeconfig YAML" (line 538-557)
- §"kubectl auth can-i grant matrix verification" (line 560-573)
- §"Capsule-proxy LIST filter test" (line 577-587)

**Pattern extraction date:** 2026-05-19
