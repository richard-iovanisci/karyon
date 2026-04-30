# Phase 9: Tenants + Flux Multi-Tenancy Lockdown - Context

**Gathered:** 2026-04-29
**Status:** Ready for planning
**Mode:** `--auto` (Claude selected recommended defaults across all gray areas; no interactive questions)

<domain>
## Phase Boundary

Land the v0.19 multi-tenant control plane on top of the Phase 8 install. Phase 9 succeeds when:

1. **TEN-01** — Two `Tenant` CRs (`alpha`, `bravo`) exist on spoke-capsule with disjoint `owners` arrays and `spec.namespaceOptions.forceTenantPrefix: true`. Each tenant has a per-tenant ServiceAccount registered as a `kind: ServiceAccount` Tenant owner under its tenant home namespace (`tenant-alpha:gitops-reconciler`, `tenant-bravo:gitops-reconciler`).
2. **TEN-02** — A tenant owner can self-serve a namespace inside its tenant prefix: `kubectl --as=alpha --context=k3d-spoke-capsule create namespace alpha-app1` succeeds and the namespace is auto-stamped with `capsule.clastix.io/tenant=alpha`. Mirror for bravo.
3. **TEN-03** — Capsule auto-materializes `ResourceQuota` and `LimitRange` objects inside each tenant-managed namespace (`kubectl get resourcequota,limitrange -n alpha-app1` shows `capsule-alpha-*` objects without manual creation).
4. **TEN-04 (P27 — load-bearing)** — Every tenant inner Flux Kustomization that lands under `pocs/capsule/tenants/<name>/` declares `spec.serviceAccountName: gitops-reconciler` explicitly. Static bats grep-asserts every tenant Kustomization has a non-null `serviceAccountName`. Inner K reconciles `Ready=True` against an empty placeholder path (Pitfall-7 defense).
5. **TEN-05 (lockdown patches — high regression risk)** — Hub Flux controllers run with multi-tenancy lockdown flags (`--no-cross-namespace-refs=true`, `--no-remote-bases=true`, `--default-service-account=default` on kustomize-controller; `--no-cross-namespace-refs=true` propagated to controllers that accept it per Flux v2.8.x docs). The `flux-system` Kustomization CR sets `spec.serviceAccountName: kustomize-controller` (platform-admin escape hatch — without it the lockdown self-blocks Flux's own bootstrap reconcile). v0.18 `task health-check` regression gate passes after the patch.
6. **TEN-06 (P32)** — The tenants outer Kustomization declares `dependsOn` on the operator/install Kustomization (`poc-capsule`) with `wait: true` so Tenant CR apply blocks until Capsule CRDs exist on spoke.
7. **CapsuleConfiguration default singleton** (deferred from Phase 8 D-08-08) — `CapsuleConfiguration/default` lands on spoke with `forceTenantPrefix: true` + `allowServiceAccountPromotion: true`. This is the cluster-scoped policy CR Capsule's webhooks consult on every tenant op.
8. **Phase 8 invariants preserved** — `kubectl --context=k3d-spoke-capsule get pods -n flux-system` returns no Flux controllers (ADR-004); D-08-12 split-path invariant still holds (hub-targeted K = no kubeConfig; spoke-targeted K = full kubeConfig with `key: value.yaml`); D-08-13 push-gate deferral remains in force (Phase 11 VAL-05 owns first push).

**Phase 9 ships tenant control plane + lockdown ONLY.** The following are explicitly **out of scope** for Phase 9 (each owned by a later phase):

- Tenant owner kubeconfigs minted via `scripts/poc/capsule/issue-tenant-kubeconfig.sh` + capsule-proxy round-trip + LIST visibility filtering → **Phase 10** (PROXY-01..03).
- Tenant inner Kustomizations re-pointed at per-tenant proxy-kubeconfigs (so each tenant impersonates **through** capsule-proxy LIST filtering, not via cluster-admin spoke-capsule-kubeconfig) → **Phase 10** (PROXY-02 contract). Phase 9 ships inner Ks using the existing `spoke-capsule-kubeconfig` Secret with `serviceAccountName` impersonation; Phase 10 swaps the kubeConfig source.
- Negative RBAC bats N1–N12 (cross-tenant pod read denied, ClusterRoleBinding escalation denied, etc.), webhook failure recovery, ordered teardown, `task rebuild` SLO regression, ADR-008 → **Phase 11** (VAL-01..06).
- Tenant workload Deployments (e.g., `alpha-app1`'s actual nginx/podinfo pod) → **Phase 11** (workload presence is incidental to negative-RBAC tests; Phase 9 only proves the control-plane shape).
- `capsule-addon-fluxcd v0.2.3` automation → **Phase 12** (OPTIONAL — gated on ADR-008 outcome).

> **Calibration vs. research SUMMARY.md "Phase 10":** Research bundles the tenant control plane (Tenants + Flux multi-tenancy lockdown + tenant inner Kustomizations using `<tenant>-proxy-kubeconfig`) into one phase. The v0.19 ROADMAP / REQUIREMENTS un-bundled: Phase 9 = Tenants + lockdown using the existing cluster-admin kubeconfig with SA impersonation; Phase 10 = swap to per-tenant proxy-kubeconfigs. This split keeps the high-regression-risk lockdown patch (TEN-05) in its own phase with full v0.18 health-check rerun as the gate, before the kubeconfig generator surface lands.

</domain>

<decisions>
## Implementation Decisions

### Directory layout — split-path inheritance (D-09-01)

- **D-09-01:** Phase 9 extends the Phase 8 split-path layout (D-08-12) with three new content directories. Final shape after Phase 9:
  ```
  pocs/capsule/
  ├── kustomization.yaml              # CHANGE: resources: [operator/, proxy/, tenants/]
  ├── operator/                       # Phase 8 (unchanged)
  ├── proxy/                          # Phase 8 (unchanged)
  ├── tenants/                        # NEW — hub-targeted: tenant inner Kustomization CRs + their hub namespaces
  │   ├── kustomization.yaml          # resources: [alpha.yaml, bravo.yaml, alpha-app/, bravo-app/]
  │   ├── alpha.yaml                  # Namespace tenant-alpha + Kustomization tenant-alpha-app + GitRepository tenant-alpha-source
  │   ├── bravo.yaml                  # mirror
  │   ├── alpha-app/
  │   │   └── kustomization.yaml      # resources: []  (Pitfall-7 placeholder; Phase 10/11 populates)
  │   └── bravo-app/
  │       └── kustomization.yaml      # resources: []  (Pitfall-7 placeholder)
  └── spoke/
      ├── kustomization.yaml          # CHANGE: resources: [config/, tenants/]   (was: resources: [])
      ├── config/                     # NEW — spoke-targeted: CapsuleConfiguration/default
      │   ├── kustomization.yaml      # resources: [capsuleconfig.yaml]
      │   └── capsuleconfig.yaml      # CapsuleConfiguration/default singleton
      └── tenants/                    # NEW — spoke-targeted: Tenant CRs + per-tenant home namespaces + per-tenant SAs
          ├── kustomization.yaml      # resources: [alpha/, bravo/]
          ├── alpha/
          │   ├── kustomization.yaml  # resources: [namespace.yaml, sa.yaml, tenant.yaml]
          │   ├── namespace.yaml      # Namespace tenant-alpha (the SA's home on spoke)
          │   ├── sa.yaml             # ServiceAccount gitops-reconciler in tenant-alpha
          │   └── tenant.yaml         # Tenant CR alpha (owners include the SA + User alpha)
          └── bravo/                  # mirror
  ```
  - **Rationale:** Mirrors the D-08-01 two-subdir convention (each functional area gets its own subdirectory with self-contained `kustomization.yaml` + manifests). Preserves D-08-12 split-path invariant: `pocs/capsule/tenants/` is **hub-targeted** (the inner Kustomization CRs land on hub-flux's apiserver where kustomize-controller can pick them up); `pocs/capsule/spoke/tenants/` is **spoke-targeted** (the Tenant CRs and per-tenant SAs land on spoke-capsule). The Pitfall-7 `resources: []` placeholder pattern from Phase 7 D-06 / Phase 8 spoke/ is reused for the tenant-app placeholders so each per-tenant inner K reconciles `Ready=True` against an empty path during Phase 9 (tenant workloads are out of scope).

### Tenant namespace + SA + Owner identity (D-09-02)

- **D-09-02:** Per-tenant namespace + SA pattern (clastix flux2-capsule-multi-tenancy canonical). Each Tenant gets:
  - **On spoke-capsule:** Namespace `tenant-<name>` (e.g., `tenant-alpha`), ServiceAccount `gitops-reconciler` inside it, and the Tenant CR registers that SA as a `kind: ServiceAccount` Owner via `<tenant-ns>:gitops-reconciler`.
  - **On hub-flux:** Namespace `tenant-<name>` (mirror name; required so the per-tenant Kustomization CR has somewhere to live and so kustomize-controller's impersonation lookup finds the SA on spoke in the matching namespace per Flux's same-namespace-impersonation rule).
  - **Tenant CR owners array (multi-owner — for both Flux and human/CLI testing):**
    ```yaml
    spec:
      owners:
        - kind: ServiceAccount
          name: gitops-reconciler
          namespace: tenant-alpha
        - kind: User
          name: alpha
      namespaceOptions:
        forceTenantPrefix: true
    ```
    The **SA owner** is for Flux impersonation (TEN-04 P27 defense — every tenant inner K runs as `system:serviceaccount:tenant-alpha:gitops-reconciler` via kustomize-controller impersonation). The **User owner** is for TEN-02's literal contract `kubectl --as=alpha create namespace alpha-app1` (impersonating the User identity from the human's k3d cluster-admin kubeconfig). Both owners point at the same Tenant; Capsule allows operations from either identity.
  - **Rationale:** TEN-01 literal phrasing locks the per-tenant SA pattern (`<tenant-ns>:gitops-reconciler`) over a shared `flux-system:gitops-reconciler` simplification. TEN-02 literal phrasing locks the `--as=alpha` User-impersonation form. The multi-owner combo satisfies both contracts in one Tenant CR. Capsule's webhooks check the Subject (impersonated identity) against `spec.owners[]`; if the impersonated identity matches any owner, the operation is allowed within the tenant's namespace prefix. **Critical: the User-as-alpha test from the human's k3d kubeconfig works because the kubeconfig has `system:masters` group / cluster-admin which can `--as=` impersonate any User. Without cluster-admin, `--as=alpha` would be denied at the apiserver impersonation layer (separate from Capsule).**

### Tenant inner Kustomization (per-tenant) — Phase 9 transitional shape (D-09-03)

- **D-09-03:** Tenant inner Kustomization CR shape for Phase 9 (Phase 10 will modify the `kubeConfig` source after PROXY-01 mints per-tenant proxy-kubeconfigs):
  ```yaml
  apiVersion: kustomize.toolkit.fluxcd.io/v1
  kind: Kustomization
  metadata:
    name: tenant-alpha-app
    namespace: tenant-alpha             # per-tenant ns on hub (D-09-02); enables same-ns sourceRef under lockdown
  spec:
    interval: 5m                        # matches D-08-06 cadence
    path: ./pocs/capsule/tenants/alpha-app   # placeholder dir (resources: []; Phase 10/11 populates)
    prune: true
    wait: true
    timeout: 5m
    sourceRef:
      kind: GitRepository
      name: tenant-alpha-source         # in same namespace (tenant-alpha) — survives `--no-cross-namespace-refs`
    kubeConfig:
      secretRef:
        name: spoke-capsule-kubeconfig  # Phase 9 transitional — uses cluster-admin spoke-capsule-kubeconfig with SA impersonation
        key: value.yaml                 # P40 / P18 inheritance
    serviceAccountName: gitops-reconciler  # P27 LOAD-BEARING DEFENSE — without this, the K runs as cluster-admin on spoke and bypasses Capsule entirely
    dependsOn:
      - name: poc-capsule               # outer hub-targeted K that lands the operator HR + CRDs
        namespace: flux-system
  ```
  - **Cross-namespace SecretRef caveat (sub-decision D-09-03a):** `spec.kubeConfig.secretRef.name: spoke-capsule-kubeconfig` lives in `flux-system` namespace on hub (applied imperatively by `scripts/register-poc-cluster.sh`). With `--no-cross-namespace-refs=true` on kustomize-controller, the controller refuses cross-namespace Secret references. **Mitigation:** the `--no-cross-namespace-refs` flag has **subtle exemptions** — Flux 2.x docs note `kubeConfig.secretRef` is governed by a separate flag (`--insecure-allow-objects`, present-only) and the cross-namespace-refs check applies to `sourceRef`, `decryption.secretRef`, and `verify.secretRef` but NOT historically to `kubeConfig.secretRef`. **Researcher MUST verify this against Flux v2.8.6 kustomize-controller source / docs during Plan 09-RESEARCH.** If Flux does block cross-namespace `kubeConfig.secretRef`: mirror the spoke-capsule-kubeconfig Secret into each tenant namespace on hub (apply imperatively in `scripts/register-poc-cluster.sh` extension). If Flux exempts kubeConfig.secretRef: leave the spec as written. **D-09-03a is the only research-flagged ambiguity in Phase 9; it does NOT block planning.**

  - **Per-tenant GitRepository (sub-decision D-09-03b):** Each tenant namespace on hub gets its own `GitRepository` CR pointing at the same karyon git URL (HTTPS, no auth — karyon is public per Phase 6 REPO-01..04). Without per-tenant sources the K's sourceRef would be cross-namespace → blocked by the lockdown. Concretely:
    ```yaml
    apiVersion: source.toolkit.fluxcd.io/v1
    kind: GitRepository
    metadata:
      name: tenant-alpha-source
      namespace: tenant-alpha
    spec:
      interval: 5m
      url: https://github.com/${GITHUB_OWNER}/karyon   # public; no secretRef needed
      ref:
        branch: main
    ```
    The `${GITHUB_OWNER}` placeholder substitutes from `.env` at `task` time — same convention as v0.18 `flux-bootstrap` (Phase 3). For local-only dev (no push yet), the GitRepository will report `failed to fetch` until Phase 11 VAL-05 first push lands. This is acceptable for Phase 9 because TEN-04's static contract is what matters; live reconcile of an empty placeholder path is incidental. After Phase 11 push, the per-tenant GitRepositories will reach `Ready=True` and tenant inner Ks will reconcile their (still-empty) paths.

  - **Rationale:** Per-tenant SA + per-tenant K-namespace + per-tenant GitRepository is the canonical clastix flux2-capsule-multi-tenancy pattern that survives the lockdown. P27 defense is structural (`spec.serviceAccountName` set explicitly); the live reconciliation requires no cross-namespace refs (everything in tenant-alpha references tenant-alpha resources). Phase 10 PROXY-02 modifies `spec.kubeConfig.secretRef.name` to per-tenant proxy-kubeconfigs without restructuring the layout.

### CapsuleConfiguration/default singleton (D-09-04)

- **D-09-04:** Land `CapsuleConfiguration/default` on spoke via `pocs/capsule/spoke/config/`:
  ```yaml
  apiVersion: capsule.clastix.io/v1beta2
  kind: CapsuleConfiguration
  metadata:
    name: default
  spec:
    forceTenantPrefix: true               # TEN-01 contract
    allowServiceAccountPromotion: true    # canonical clastix default; permits SA → User upgrade for tenant ops
    userGroups:
      - capsule.clastix.io                # default owner-group filter (chart default; documented for clarity)
    protectedNamespaceRegex: ^kube-.*$    # belt-and-suspenders against tenant attempting to register kube-system as a tenant ns
    nodeMetadata:
      forbiddenAnnotations: {}
      forbiddenLabels: {}                 # POC keeps these empty; Phase 11 may exercise via N7 negative-RBAC
  ```
  - **Rationale:** `forceTenantPrefix: true` is REQUIRED by TEN-01 and is the load-bearing toggle that makes `kubectl --as=alpha create namespace alpha-app1` succeed (because `alpha-app1` matches the prefix `alpha`). `allowServiceAccountPromotion: true` is the canonical clastix default that allows the gitops-reconciler SA to escalate identity inside its own tenant boundary (needed for Flux impersonation chain to work cleanly). `protectedNamespaceRegex` for `kube-*` is a defense-in-depth (a tenant cannot create `kube-foo` even if they tried; covered by Capsule's own webhooks but explicit in the singleton). The singleton lands as part of `poc-capsule-spoke` outer reconcile (D-08-12 spoke-targeted).

### Hub Flux multi-tenancy lockdown patches (D-09-05 — TEN-05)

- **D-09-05:** **Patch surface — `clusters/hub-flux/flux-system/kustomization.yaml` (FLUX PATCH SURFACE, the SAME file that holds `# KARYON SPOKES MOUNT` and `# KARYON POC MOUNT` sentinels).** Add a `patches:` block applying lockdown flags to kustomize-controller (the ONLY controller that accepts all 3 flags per Flux v2.8.x docs) and `--no-cross-namespace-refs=true` to helm-controller + notification-controller (the controllers that ALSO accept that single flag). source-controller does NOT accept these flags (sources are owned cross-namespace by their own controller; lockdown happens on consumer side).

  Final shape of `clusters/hub-flux/flux-system/kustomization.yaml` after Phase 9:
  ```yaml
  apiVersion: kustomize.config.k8s.io/v1beta1
  kind: Kustomization
  resources:
    - gotk-components.yaml
    - gotk-sync.yaml
    # KARYON SPOKES MOUNT
    - ../spokes
    # KARYON POC MOUNT
    - ../pocs
  # KARYON FLUX LOCKDOWN PATCHES (D-09-05 / TEN-05)
  # Multi-tenancy hardening: kustomize-controller refuses cross-namespace refs,
  # remote bases, and reconciles as `default` SA when spec.serviceAccountName is unset
  # (the bypass-trap closing P27). flux-system Kustomization sets serviceAccountName
  # explicitly (escape hatch — without it the lockdown self-blocks Flux's own bootstrap reconcile).
  patches:
    - target:
        kind: Deployment
        name: kustomize-controller
        namespace: flux-system
      patch: |
        - op: add
          path: /spec/template/spec/containers/0/args/-
          value: --no-cross-namespace-refs=true
        - op: add
          path: /spec/template/spec/containers/0/args/-
          value: --no-remote-bases=true
        - op: add
          path: /spec/template/spec/containers/0/args/-
          value: --default-service-account=default
    - target:
        kind: Deployment
        name: helm-controller
        namespace: flux-system
      patch: |
        - op: add
          path: /spec/template/spec/containers/0/args/-
          value: --no-cross-namespace-refs=true
    - target:
        kind: Deployment
        name: notification-controller
        namespace: flux-system
      patch: |
        - op: add
          path: /spec/template/spec/containers/0/args/-
          value: --no-cross-namespace-refs=true
    - target:
        kind: Kustomization
        name: flux-system
        namespace: flux-system
      patch: |
        - op: add
          path: /spec/serviceAccountName
          value: kustomize-controller
  ```
  - **Rationale:** The FLUX PATCH SURFACE is the documented supported edit point per the file's own header comment block ("Edits here SURVIVE re-bootstrap"). Per-controller scoping mirrors Flux v2.8 docs:
    - **kustomize-controller** accepts all 3 flags (canonical lockdown set).
    - **helm-controller** accepts `--no-cross-namespace-refs` (HelmRelease can reference HelmRepository / OCIRepository cross-namespace; lockdown blocks).
    - **notification-controller** accepts `--no-cross-namespace-refs` (Alert / Provider cross-namespace blocked).
    - **source-controller** does NOT accept these flags — sources are owned by source-controller; access control is enforced when consumers (kustomize/helm) reference them.
  - **flux-system Kustomization escape hatch (sub-decision D-09-05a):** The `--default-service-account=default` flag on kustomize-controller means any Kustomization CR without `spec.serviceAccountName` reconciles as `system:serviceaccount:<ns>:default` — a no-permission SA. This BLOCKS Flux's own `flux-system` Kustomization from reconciling because the bootstrap-managed `flux-system` Kustomization CR does NOT set `serviceAccountName`. **Mitigation: patch the `flux-system` Kustomization CR to set `spec.serviceAccountName: kustomize-controller`** (the actual SA that runs kustomize-controller; pre-existing with cluster-admin via `flux-system` ClusterRoleBinding). The patch is included in the same `patches:` block. Without this escape hatch, applying TEN-05 immediately bricks the hub Flux reconcile (verified-shape regression).
  - **Hub-targeted Ks (other than flux-system) escape hatch:** `poc-capsule`, `poc-capsule-spoke` are hub-targeted Kustomizations that ALSO need `spec.serviceAccountName` after the lockdown lands. Update both files in Phase 9 to set `spec.serviceAccountName: kustomize-controller`. Spoke-targeted Ks (`poc-capsule-spoke`) is a special case — it has `spec.kubeConfig` set, which means kustomize-controller's `--default-service-account` flag does NOT apply to it (the flag only applies to LOCAL-cluster reconcile per Flux docs / P27 root cause). So `poc-capsule-spoke` does NOT strictly need `spec.serviceAccountName`, but explicit-set is still safer for clarity. **Recommendation:** Set `spec.serviceAccountName: kustomize-controller` on `poc-capsule` (hub-targeted; affected by `--default-service-account`) and OPTIONALLY on `poc-capsule-spoke` (spoke-targeted; unaffected but explicit is clearer). Document in PLAN.
  - **Hub spoke-side Kustomizations (`spoke-apps`, `spoke-ml`):** These are existing v0.18 Kustomizations with `spec.kubeConfig` set, reconciling to spoke-apps and spoke-ml. Per the same kustomize-controller `--default-service-account` flag scope (LOCAL-cluster only), these are NOT affected by the lockdown. **Recommendation:** Do NOT modify `clusters/hub-flux/spokes/spoke-apps.yaml` or `spoke-ml.yaml` in Phase 9 (would unnecessarily expand scope; v0.18 `task health-check` regression gate covers any unintended interaction). Verifier confirms spoke-apps + spoke-ml still reconcile post-patch.
  - **Health-check regression timing:** Re-run full v0.18 `task health-check` immediately after Wave 1 (lockdown patch lands and reconciles). If health-check fails, gap-close immediately (revert the patch, investigate, re-apply with corrections). This is the dominant Phase 9 blocker per STATE.md.

### Tenants outer Kustomization — dependsOn chain (D-09-06 — TEN-06)

- **D-09-06:** Update `clusters/hub-flux/pocs/capsule.yaml` (the existing hub-targeted outer K from Phase 8, `spec.path: ./pocs/capsule`) to add `dependsOn` on its OWN cycle... wait, `poc-capsule` is the outer K that lands the operator HR + tenant inner K CRs. The dependsOn for TEN-06 must be applied to the per-tenant inner K's `dependsOn: [{name: poc-capsule, namespace: flux-system}]` (which is already in D-09-03). And the `poc-capsule-spoke` outer K (which applies CapsuleConfiguration + Tenant CRs to spoke) also needs `dependsOn: [{name: poc-capsule, namespace: flux-system}]` with `wait: true` so Tenant CR apply blocks until operator CRDs exist on spoke.

  Concretely, the TEN-06 dependsOn chain has TWO arms:
  1. **`poc-capsule-spoke` (outer K, spoke-targeted) depends on `poc-capsule` (outer K, hub-targeted)** — adds `dependsOn: [{name: poc-capsule}] wait: true` to `clusters/hub-flux/pocs/capsule-spoke.yaml`. Without this, kustomize-controller may try to apply the Tenant CRs (under `pocs/capsule/spoke/tenants/`) to spoke before the operator HelmRelease has reconciled and CRDs are registered → `no matches for kind "Tenant"` (P32).
  2. **Per-tenant inner K depends on `poc-capsule`** — already captured in D-09-03 (each tenant inner K has `dependsOn: [{name: poc-capsule, namespace: flux-system}]`).
  - **Rationale:** P32 — Capsule CRDs (`Tenant`, `CapsuleConfiguration`) must be registered on spoke BEFORE any CR using those kinds is applied. The outer `poc-capsule` K's HelmRelease reconcile is what registers the CRDs (per chart's `crds: install: true`). `wait: true` on the dependsOn means the dependent K does not start applying until the dependency reports `Ready=True` (HR Ready=True implies chart applied implies CRDs registered). Phase 8 D-08-07 already established this pattern at the HelmRelease level (`capsule-proxy` HR depends on `capsule` HR with wait); Phase 9 escalates to the Kustomization level (cross-K dependency).

### TEN-02 / TEN-03 verifier — `kubectl --as=alpha` test path (D-09-07)

- **D-09-07:** TEN-02 acceptance test runs from the LOCAL human kubeconfig (k3d-spoke-capsule cluster-admin context):
  ```bash
  kubectl --context=k3d-spoke-capsule --as=alpha create namespace alpha-app1
  kubectl --context=k3d-spoke-capsule get namespace alpha-app1 -o jsonpath='{.metadata.labels.capsule\.clastix\.io/tenant}'
  # expects: alpha
  ```
  TEN-03 follows immediately:
  ```bash
  kubectl --context=k3d-spoke-capsule -n alpha-app1 get resourcequota -o jsonpath='{.items[*].metadata.name}'
  # expects: capsule-alpha-* (auto-materialized)
  kubectl --context=k3d-spoke-capsule -n alpha-app1 get limitrange -o jsonpath='{.items[*].metadata.name}'
  # expects: capsule-alpha-* (auto-materialized)
  ```
  Mirror tests for bravo. Phase 9 verifier creates the namespaces; teardown leaves them in place (Phase 11 `task destroy-poc capsule` ordered teardown owns cleanup).
  - **Rationale:** `kubectl --as=` impersonation requires the CLIENT identity to have `system:masters` / cluster-admin RBAC for `impersonate` verb on User kind. The default k3d kubeconfig provides this. The impersonated identity (User `alpha`) is matched against Tenant CR `owners` by Capsule's webhook → owner of tenant alpha → allowed to create namespaces matching `alpha-*` prefix. Capsule's controller stamps the `capsule.clastix.io/tenant=alpha` label automatically. The auto-materialized ResourceQuota + LimitRange come from Capsule reconciling the Tenant CR (post-namespace-create event triggers tenant reconcile). Verifier polls with retries — auto-materialization is observed within ~5–10s on a healthy operator.

### Test scaffolding pattern — repeat Phase 7/8 Wave 0 RED bats (D-09-08)

- **D-09-08:** **Repeat the Phase 7/8 Wave 0 pattern.** Plan 09-00 lands ALL Phase 9 bats (every static contract + every live observation, gated) BEFORE any tenant YAML lands. Subsequent plans make the bats green by landing the actual yaml. Live-only bats (`flux get`, `kubectl get tenants`, `kubectl --as=alpha`) are gated by a runtime probe so they auto-skip when the cluster is not yet up — same gating pattern as Phase 7 / Phase 8.
  - **Concrete Phase 9 bats coverage** (planner expands; this is the floor):
    - **Static (Wave 0) — TEN-01:** Tenant CR shape — both `pocs/capsule/spoke/tenants/alpha/tenant.yaml` and `bravo/tenant.yaml` MUST grep-assert `forceTenantPrefix: true` AND `kind: ServiceAccount` AND `name: gitops-reconciler` AND `kind: User` AND `name: alpha` (or `bravo`).
    - **Static (Wave 0) — TEN-04 (P27 LOAD-BEARING):** Every tenant inner Kustomization at `pocs/capsule/tenants/<name>.yaml` (alpha.yaml, bravo.yaml) MUST grep-assert `serviceAccountName: gitops-reconciler` is present and non-null. yq-based assertion preferred (matches D-08-11 / WR-01..04 hardening direction). Add a yq-based negative falsifier: a synthetic broken Kustomization fixture with `serviceAccountName: null` MUST fail the bats lint.
    - **Static (Wave 0) — TEN-05 (lockdown):** `clusters/hub-flux/flux-system/kustomization.yaml` MUST have `patches:` block grep-asserted with literal flag values (`--no-cross-namespace-refs=true`, `--no-remote-bases=true`, `--default-service-account=default`); MUST have a Kustomization-CR patch setting `spec.serviceAccountName: kustomize-controller` for the `flux-system` Kustomization. The PATCH SURFACE comment block is preserved verbatim (regression gate against accidental hand-edit removing it).
    - **Static (Wave 0) — TEN-06 (P32 dependsOn):** `clusters/hub-flux/pocs/capsule-spoke.yaml` MUST have `dependsOn: [{name: poc-capsule}] wait: true`; per-tenant inner Ks MUST have `dependsOn: [{name: poc-capsule, namespace: flux-system}]`.
    - **Static (Wave 0) — split-path invariant (D-08-12 inheritance):** `clusters/hub-flux/pocs/capsule.yaml` MUST NOT have `spec.kubeConfig`; `clusters/hub-flux/pocs/capsule-spoke.yaml` MUST have `spec.kubeConfig.secretRef.name: spoke-capsule-kubeconfig` AND `key: value.yaml`. (Inherited from Phase 8; Phase 9 verifier reruns.)
    - **Static (Wave 0) — POC isolation (Phase 7 P31 inheritance):** Re-run Phase 7's `tests/bats/poc-isolation-01-static.bats`. Phase 9's new files under `pocs/capsule/{tenants,spoke}/...` MUST NOT introduce `spoke-capsule` mentions in v0.18 scripts.
    - **Live (Wave 1+) — TEN-01:** `kubectl --context=k3d-spoke-capsule get tenants alpha bravo -o jsonpath='{.items[*].spec.namespaceOptions.forceTenantPrefix}'` returns `true true`. `kubectl get sa -n tenant-alpha gitops-reconciler` exists. Mirror for bravo.
    - **Live (Wave 1+) — TEN-02:** `kubectl --context=k3d-spoke-capsule --as=alpha create namespace alpha-app1` succeeds (and idempotently re-runs). `kubectl get namespace alpha-app1 -o jsonpath='{.metadata.labels.capsule\.clastix\.io/tenant}'` returns `alpha`. Mirror for bravo.
    - **Live (Wave 1+) — TEN-03:** `kubectl get resourcequota -n alpha-app1` returns `capsule-alpha-*` named objects within 10s of namespace creation. Mirror for bravo.
    - **Live (Wave 1+) — TEN-04 reconcile:** `flux get kustomization tenant-alpha-app -n tenant-alpha --context=k3d-hub-flux Ready=True` (against an empty placeholder path; must reach Ready quickly).
    - **Live (Wave 1+) — TEN-05 lockdown:** `kubectl --context=k3d-hub-flux -n flux-system get deployment kustomize-controller -o jsonpath='{.spec.template.spec.containers[0].args}'` contains all 3 flags. `flux get kustomization flux-system -n flux-system --context=k3d-hub-flux` reports `Ready=True` (proves SA escape hatch works). Phase 9 verifier ALSO reruns full v0.18 `task health-check` and asserts exit code 0 (regression gate).
    - **Live (Wave 1+) — TEN-06 dependsOn:** `kubectl --context=k3d-hub-flux -n flux-system get kustomization poc-capsule-spoke -o jsonpath='{.spec.dependsOn[0].name}'` returns `poc-capsule`. `flux get kustomization poc-capsule-spoke` reports `Ready=True`.
    - **Live (Wave 1+) — Phase 8 invariant preservation:** Re-run Phase 8's CAP-01..03 + ADR-004 live bats verbatim. Phase 9 must not regress Phase 8.
  - **Rationale:** Nyquist gate worked in Phase 7 + 8. No "implement and test in same plan" anti-pattern. Already-validated pattern.

### Plan ordering inside Phase 9 (D-09-09)

- **D-09-09:** Recommended plan ordering (planner may reshape into 4–6 plans without re-asking):
  - **Plan 09-00 — Wave 0 RED bats scaffold.** Land all D-09-08 bats files (static + live, live gated by cluster-info probe). All bats RED at end of plan. Mirrors 07-00 / 08-00.
  - **Plan 09-01 — CapsuleConfiguration singleton + spoke-side per-tenant SA + Tenant CRs.** Lands `pocs/capsule/spoke/config/capsuleconfig.yaml`, `pocs/capsule/spoke/tenants/{alpha,bravo}/{namespace,sa,tenant}.yaml`, plus `pocs/capsule/spoke/kustomization.yaml` rewrite (resources: [config/, tenants/]) and `pocs/capsule/spoke/tenants/kustomization.yaml` (resources: [alpha/, bravo/]). Updates `clusters/hub-flux/pocs/capsule-spoke.yaml` to add `dependsOn: [{name: poc-capsule}] wait: true`. **Reconcile blocked until Wave 1 verifier observes tenant CRs land on spoke.**
  - **Plan 09-02 — Hub-side per-tenant inner Kustomizations + their hub namespaces + per-tenant GitRepositories.** Lands `pocs/capsule/tenants/{alpha,bravo}.yaml` (each containing Namespace + GitRepository + Kustomization), placeholder `pocs/capsule/tenants/{alpha-app,bravo-app}/kustomization.yaml` (resources: []), plus `pocs/capsule/tenants/kustomization.yaml` resource list, plus `pocs/capsule/kustomization.yaml` rewrite (add tenants/).
  - **Plan 09-03 — Hub Flux multi-tenancy lockdown + escape hatch.** Modifies `clusters/hub-flux/flux-system/kustomization.yaml` (FLUX PATCH SURFACE) to add the `patches:` block per D-09-05. Modifies `clusters/hub-flux/pocs/capsule.yaml` to add `spec.serviceAccountName: kustomize-controller`. **High regression risk; full v0.18 `task health-check` rerun is the immediate gate. If health-check fails, plan 09-03 is rolled back atomically and re-planned.** This is the dominant Phase 9 risk per STATE.md.
  - **Plan 09-04 — Verifier.** Live bats observation per D-09-08 live coverage. Reruns Phase 7 P31 isolation bats + Phase 8 CAP-01..03 + ADR-004 invariant bats. Reruns full v0.18 `task health-check`. Closes folded carryover (none folded for Phase 9 — see `<deferred>` below).
  - Planner may merge 09-01 + 09-02 (both are tenant-side, lower regression risk) or split 09-03 (lockdown vs escape-hatch can be sequenced separately) without re-asking.

### Folded Todos

No todos were folded into Phase 9 scope. The two pending todos (`2026-04-29-phase-7-gitleaks-planning-doc-allowlist.md` resolves_phase: 11; `2026-04-29-phase-7-hub-flux-observable-reconcile.md` resolves_phase: 8) explicitly route elsewhere via their `resolves_phase` markers. See `<deferred>` "Reviewed Todos" subsection.

### Claude's Discretion

The following gray areas are intentionally NOT specified — planner/researcher should default to v0.18 + Phase 7/8 patterns and note the chosen approach in PLAN.md without re-asking:

- **`task` surface extensions** — recommended default: **none**. Phase 9 lands no new top-level `task ...` targets. The install path is Flux-driven (commit yaml → hub-flux reconciles); verifiers run as bats + the existing `task health-check` regression gate. Phase 11 owns `task destroy-poc capsule` and `task fail-capsule-webhook`.
- **HelmRelease values shape — values inline vs ConfigMap** — recommended default: **values inline** (matches D-08 inline default; Phase 9 does not modify operator/proxy values).
- **Tenant CR `spec.resourceQuotas` and `spec.limitRanges`** — recommended default: **minimal**. ResourceQuotas: `cpu: 4, memory: 8Gi, pods: 20` per tenant (aggregated across tenant namespaces). LimitRanges: pod `default: {cpu: 100m, memory: 128Mi}` + `defaultRequest: {cpu: 50m, memory: 64Mi}`. The actual limit values are NOT load-bearing for the POC — TEN-03 only verifies AUTO-MATERIALIZATION shape, not enforcement semantics. Phase 11's N6 negative-RBAC test validates enforcement.
- **Tenant CR `spec.storageClasses`, `ingressClasses`, `containerRegistries`, `nodeSelectors`** — recommended default: **omit (empty allow-lists)** for Phase 9. Capsule defaults to allow-all when these fields are absent. POC simplification; Phase 11 N7 (denied registry pull) may exercise `containerRegistries.allowed: ["ghcr.io"]` if explicitly added in plan 09-01 — planner discretion.
- **`spec.networkPolicies` on Tenant CR** — recommended default: **omit**. Capsule's default behavior (no auto-NetworkPolicy) is fine for the POC; Phase 11 may exercise via N4-adjacent negative tests if needed. Avoids P43 ambiguity (NetworkPolicy too-permissive vs too-restrictive).
- **Per-tenant proxy-kubeconfig Secret name pattern** — Phase 9 doesn't mint these; Phase 10 PROXY-01 owns. Forward-pointer documentation only: `<tenant>-proxy-kubeconfig` Secret in `flux-system` namespace, applied imperatively by `scripts/poc/capsule/issue-tenant-kubeconfig.sh`. Phase 9 D-09-03 uses the existing `spoke-capsule-kubeconfig` for transitional purpose; Phase 10 swaps the `secretRef.name` field per tenant.
- **Phase 9 verifier script wrapper** — recommended default: **bats-only verifier (no `scripts/poc/capsule/verify-tenants.sh` wrapper)**. Live bats handle assertions directly. Mirrors Phase 8 D-08 "task surface extensions" recommendation.
- **Order of `task health-check` rerun within Plan 09-03** — recommended default: **TWO reruns**: (1) BEFORE applying the lockdown patches (baseline assertion: v0.18 health-check passes pre-patch, asserting Phase 8 close-out state); (2) AFTER applying the lockdown patches (regression assertion: v0.18 health-check still passes, asserting lockdown didn't regress). Failure on (2) → roll back patch atomically.
- **Reconcile loop noise tolerance window** — recommended default: same as D-08 reconcile-tolerance — ≤2 reconcile cycles (≤10 min) for tenant inner Ks to reach `Ready=True`. After lockdown patch lands, allow ≤1 additional cycle for Flux controllers to restart with new args. Live-bats retry budget: 3 attempts with 30s sleep between.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project planning artifacts (REQUIRED reading)

- `.planning/REQUIREMENTS.md` — TEN-01..06 contracts; load-bearing P27/P29/P31 invariants; ADR-004 inheritance; KARYON POC MOUNT location lock; v0.19 inheritance from v0.18 ADRs. **Phase 9 owns TEN-01 through TEN-06.**
- `.planning/ROADMAP.md` (Phase 9 section + Phase 10/11 boundary call-outs for un-bundling rationale) — phase goal, ordered success criteria, dependency declarations, scope-tightening rationale (Phase 9 = Tenants + lockdown using existing kubeconfig with SA impersonation; Phase 10 = swap to per-tenant proxy-kubeconfigs).
- `.planning/PROJECT.md` — v0.19 out-of-scope items (cert-manager, OIDC, prod ingress, multi-spoke federation, hub-side Capsule, default platform adoption); ADR-004 hub-only invariant; public-repo secrets contract; carried-forward v0.18 follow-ups (shellcheck cleanup, first-push CI verification).
- `.planning/STATE.md` — milestone-open decisions: 6-phase split rationale, two-HelmRelease decision, P27/P29/P31 invariants; **Phase 9 blockers/concerns subsection** (lockdown flag patches touch v0.18 Flux bootstrap surface — high regression risk; full `task health-check` rerun as Phase 9 acceptance gate). Phase 8 close-out (`passed_with_overrides` 10/10 must-haves).

### Phase 7 + 8 artifacts — REQUIRED context (Phase 9 inherits everything Phase 7+8 shipped)

- `.planning/phases/07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc/07-CONTEXT.md` — D-05 through D-17 (POC seam shape, spoke-capsule pins, P18 inheritance on outer Kustomization, P31 isolation contract, ADR-004 preservation invariant).
- `.planning/phases/07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc/07-SUMMARY.md` (07-00..07-05) — what Phase 7 plans shipped.
- `.planning/phases/07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc/07-VERIFICATION.md` — Phase 7 verification status.
- `.planning/phases/08-capsule-capsule-proxy-bare-minimum-install/08-CONTEXT.md` — D-08-01 through D-08-13. **Especially D-08-08 (CapsuleConfiguration deferral, owned by Phase 9), D-08-12 (split-path architectural seam — load-bearing for Phase 9 directory layout), D-08-13 (push-gate deferral to Phase 11 VAL-05).**
- `.planning/phases/08-capsule-capsule-proxy-bare-minimum-install/08-SUMMARY.md` (08-00..08-04) — what Phase 8 plans shipped (HelmRelease shapes, OCIRepository pattern, gap-close split-path implementation).
- `.planning/phases/08-capsule-capsule-proxy-bare-minimum-install/08-VERIFICATION.md` — Phase 8 verification status (`passed_with_overrides`).
- `.planning/phases/08-capsule-capsule-proxy-bare-minimum-install/08-PATTERNS.md` — Phase 8 plan-side patterns analog mapping (relevant analogs Phase 9 inherits).

### Architecture Decision Records (load-bearing for Phase 9)

- `docs/adr/0001-single-wsl2-shared-docker-network.md` — k8s-net shared bridge.
- `docs/adr/0002-k3d-over-kind.md` — k3d cluster runtime.
- `docs/adr/0003-flux-over-argocd.md` — Flux 2 as GitOps tool; HelmController + KustomizeController consumer.
- `docs/adr/0004-hub-only-flux-control-plane.md` — **load-bearing**: NO Flux controllers run on spoke-capsule. Phase 9 verifier MUST re-grep-assert `kubectl --context=k3d-spoke-capsule get pods -n flux-system` returns no flux controllers (ADR-004 regression gate, inherited from Phase 8 D-08-09 live bats).
- `docs/adr/0005-kubernetes-version-pin.md` — k3s `v1.34.6-k3s1` clears Capsule v0.12.x's k8s ≥1.34.0 floor.

### Milestone-level research (REQUIRED for planning)

- `.planning/research/SUMMARY.md` §"Mental Model" + §"Recommended Phase Split → Phase 10 (Two Tenants + Tenant Flux Inner Reconcile)" + §"P27 Tenant Escape via Flux" + §"Phase 9 (Capsule install)" research-flag note + §"Phase 10 (Tenants + lockdown) HIGH-risk single requirement" — phase boundary, tenant directory layout reference (`pocs/capsule/tenants/alpha/`), per-tenant SA pattern, lockdown patch shape, full v0.18 `task health-check` regression gate.
- `.planning/research/STACK.md` — Capsule v0.12.4, capsule-proxy v0.12.0 pins, k8s ≥1.34 floor, Flux v2.8.6 (lockdown flag support).
- `.planning/research/ARCHITECTURE.md` §"Mental Model" + §"Phase 10 outer + inner reconcile" + §"Tenant inner Kustomization shape" — outer + inner reconcile pattern, per-tenant K layout, P27 explicit `serviceAccountName` invariant.
- `.planning/research/PITFALLS.md` — P26-P43 catalogue. **Phase 9 directly addresses:**
  - **P27** (load-bearing — every tenant Kustomization MUST set `spec.serviceAccountName`; static bats falsifier in plan 09-00; live impersonation tested in TEN-04 / TEN-06 reconcile)
  - **P32** (CRDs not present when Tenants apply — TEN-06 `dependsOn: poc-capsule wait: true` chain in BOTH `poc-capsule-spoke` and per-tenant inner Ks)
  - **P40** (P18 `key: value.yaml` invariant — `poc-capsule-spoke` outer K kubeConfig; spoke-capsule-kubeconfig usage in tenant inner Ks)
  - **Inherited from Phase 8:** P26 (failurePolicy already Ignore), P28 (proxy NodePort already locked Phase 7), P31 (POC isolation — verifier reruns Phase 7 static bats), P33 (proxy SANs already in chart values), P34 (built-in certgen already locked D-08-04).
- `.planning/research/FEATURES.md` §"Capsule CRDs" + §"Tenant CR shape" + §"CapsuleConfiguration default singleton" — Tenant CR shape, owners array semantics, `forceTenantPrefix`, `allowServiceAccountPromotion`.

### v0.18 + Phase 7/8 reference implementations (analogs to mirror in Phase 9)

- **`clusters/hub-flux/flux-system/kustomization.yaml`** — FLUX PATCH SURFACE. **Phase 9 modifies this file directly per D-09-05** (adds `patches:` block for lockdown flags + flux-system Kustomization escape hatch). The existing `# KARYON SPOKES MOUNT` and `# KARYON POC MOUNT` sentinels are preserved verbatim. Note: this is the SUPPORTED hand-edit surface per the file's own header comment block ("Edits here SURVIVE re-bootstrap").
- **`clusters/hub-flux/pocs/capsule.yaml`** — hub-targeted outer K (Phase 8 D-08-12). **Phase 9 modifies** to add `spec.serviceAccountName: kustomize-controller` (escape hatch under lockdown). The `spec.path: ./pocs/capsule` reference unchanged. Comment block updated to reference D-09-05.
- **`clusters/hub-flux/pocs/capsule-spoke.yaml`** — spoke-targeted outer K (Phase 8 D-08-12). **Phase 9 modifies** to add `dependsOn: [{name: poc-capsule}] wait: true` per D-09-06. The `spec.kubeConfig.secretRef` block (P40 / P18) unchanged.
- **`clusters/hub-flux/pocs/kustomization.yaml`** — pocs aggregator (Phase 8). Phase 9 does NOT modify (resources: [capsule.yaml, capsule-spoke.yaml] is correct).
- **`pocs/capsule/kustomization.yaml`** — outer recursive Kustomization (Phase 8 D-08-05). **Phase 9 modifies** to add `tenants/` subdir reference: `resources: [operator/, proxy/, tenants/]`. Phase 8 head-comment block preserved with appended Phase 9 update note.
- **`pocs/capsule/spoke/kustomization.yaml`** — spoke-side recursive Kustomization (Phase 8 D-08-12 placeholder). **Phase 9 modifies** to populate: `resources: [config/, tenants/]`. Phase 8 head-comment block preserved with Phase 9 update note (no longer a Pitfall-7 placeholder).
- **Phase 8 manifest patterns** (`pocs/capsule/operator/{helmrelease,ocirepository,kustomization}.yaml`, `pocs/capsule/proxy/...`) — TEMPLATE for Phase 9's per-tenant subdirectory shape (each subdir has `kustomization.yaml` + content YAMLs + Phase 8-style head comment block citing the load-bearing decision + REQ-IDs).
- **Phase 7 + 8 bats files** — Phase 9 reuses pattern (`<area>-<NN>-{static|live}-<topic>.bats`, `setup() { REPO_ROOT=...; }`, `grep -F --` for literal text matches, yq-based assertions per WR-01..04 hardening direction). **Phase 9 reuses verbatim:**
  - `tests/bats/poc-isolation-01-static.bats` — Phase 9's new files MUST NOT introduce `spoke-capsule` mentions in v0.18 scripts (P31 regression gate).
  - `tests/bats/capsule-install-09-live-adr-004.bats` — Phase 9 verifier reruns to confirm ADR-004 unchanged.
  - `tests/bats/capsule-install-{06,07,08,10}-live-*.bats` — Phase 9 verifier reruns to confirm Phase 8 CAP-01..03 + outer K Ready=True still hold.
- **`scripts/lib/preflight-lib.sh`** — output helpers; if any Phase 9 verifier script is added (NOT recommended per Claude's Discretion), source this.
- **`scripts/register-poc-cluster.sh`** — established pattern for imperative kubeconfig Secret apply on hub. **Phase 9 may extend** if D-09-03a research determines spoke-capsule-kubeconfig must be mirrored into per-tenant namespaces (planner-time decision; defaults to no mirror per D-09-03a primary assumption).
- **v0.18 `task health-check` (`scripts/health-check.sh`)** — full health-check is Phase 9's load-bearing regression gate (Plan 09-03 mid-plan checkpoint and Plan 09-04 verifier).
- **`Taskfile.yml`** — top-level task naming pattern. **Phase 9 expected to add NO new tasks** (per Claude's Discretion §"task surface extensions").

### Existing patches/lockdown research (informational)

- **Flux v2.8.6 kustomize-controller flags reference** — `https://fluxcd.io/flux/components/kustomize/kustomization/#multi-tenancy` — canonical lockdown flag set + per-controller scope.
- **Flux multi-tenancy reference repo** — `https://github.com/fluxcd/flux2-multi-tenancy` — canonical lockdown pattern (the POC mirror is `clastix/flux2-capsule-multi-tenancy`).
- **clastix/flux2-capsule-multi-tenancy** — `https://github.com/clastix/flux2-capsule-multi-tenancy` — per-tenant SA + tenant-namespace + GitRepository pattern. **Researcher SHOULD `git clone` this during Plan 09-RESEARCH** for fresh-from-source verification of D-09-02 (per-tenant SA pattern), D-09-03 (tenant inner K shape), D-09-05 (lockdown flag set).
- **Capsule v0.12.4 Tenant CRD reference** — `https://capsule.clastix.io/docs/tenants/configuration/` — `spec.owners` semantics (User vs ServiceAccount kinds; co-owner combo); `spec.namespaceOptions.forceTenantPrefix` semantics.
- **Capsule v0.12.4 CapsuleConfiguration reference** — `https://capsule.clastix.io/docs/configuration/` — `default` singleton semantics; `allowServiceAccountPromotion`; `protectedNamespaceRegex`.

### Open research questions (D-09-03a)

- **Cross-namespace `kubeConfig.secretRef` under `--no-cross-namespace-refs`** — Flux v2.8.6 docs are AMBIGUOUS on whether `kubeConfig.secretRef` is governed by `--no-cross-namespace-refs` (the flag's documented scope is `sourceRef`, `decryption.secretRef`, `verify.secretRef`; `kubeConfig.secretRef` is NOT in the documented list). **Researcher MUST verify in Plan 09-RESEARCH** by grepping kustomize-controller v2.8.x source (`internal/controller/kustomization_decryptor.go` + `kustomization_dependency.go` + `kustomization_decryptor.go` + impersonation.go around line 88-120). If Flux blocks: D-09-03 fallback is to mirror `spoke-capsule-kubeconfig` Secret into each tenant namespace via `scripts/register-poc-cluster.sh` extension. If Flux exempts: D-09-03 spec stands. **This is the only research-flagged ambiguity in Phase 9; it does NOT block planning** (the static defense is unaffected; the question is purely about the runtime reconcile path).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- **`clusters/hub-flux/flux-system/kustomization.yaml`** — FLUX PATCH SURFACE. Phase 9 modifies in-place (D-09-05 patches block). The file's header comment block documenting the patch surface contract is preserved verbatim (regression gate).
- **`clusters/hub-flux/pocs/capsule.yaml`** + **`clusters/hub-flux/pocs/capsule-spoke.yaml`** — Phase 8 split-path outer Ks (D-08-12). Phase 9 modifies both: `capsule.yaml` adds `spec.serviceAccountName: kustomize-controller` (escape hatch under lockdown); `capsule-spoke.yaml` adds `dependsOn: [{name: poc-capsule}] wait: true` (P32 chain).
- **`pocs/capsule/kustomization.yaml`** — Phase 8 outer recursive Kustomization (`resources: [operator/, proxy/]`). Phase 9 rewrites to add `tenants/`.
- **`pocs/capsule/spoke/kustomization.yaml`** — Phase 8 placeholder (`resources: []`). Phase 9 rewrites to populate (`resources: [config/, tenants/]`).
- **`scripts/register-poc-cluster.sh`** — Phase 7 imperative kubeconfig Secret apply pattern. Phase 9 may extend if D-09-03a research dictates Secret mirroring (planner-time decision).
- **`scripts/lib/preflight-lib.sh`** — output helpers. Phase 9 has no new scripts but the helper is available if planner reverses Claude's Discretion §"verifier script wrapper".
- **`tests/bats/test_helper`** — shared bats loader. Phase 9 reuses without modification.
- **`tests/bats/poc-isolation-01-static.bats`** — Phase 7 P31 regression gate. Phase 9 reuses verbatim (no `spoke-capsule` mentions added to v0.18 scripts).
- **`tests/bats/capsule-install-{06,07,08,09,10}-live-*.bats`** — Phase 8 live verifier bats. Phase 9 reuses to confirm Phase 8 contracts unaffected post-lockdown.
- **HelmController + SourceController in `clusters/hub-flux/flux-system/gotk-components.yaml`** — bootstrap-managed. Phase 9 does NOT touch the components file directly but the lockdown patches in `kustomization.yaml` flow into the Deployments via Strategic Merge Patch (kustomize patches: target). After Phase 9 reconcile, the Deployments themselves carry the new args; gotk-components.yaml is unchanged.
- **`scripts/health-check.sh`** + **`task health-check`** — v0.18 regression gate. Phase 9 reuses as the dominant Plan 09-03 mid-plan checkpoint and Plan 09-04 verifier.

### Established Patterns

- **Sentinel-guarded patch surface** (Phase 7 D-05 / D-09; `# KARYON SPOKES MOUNT` + `# KARYON POC MOUNT`). Phase 9 ADDS a NEW comment marker `# KARYON FLUX LOCKDOWN PATCHES` to delineate the lockdown patches block from the existing resources block. Static bats grep-asserts the new sentinel is present and the patches block follows.
- **Split-path Flux outer Kustomization pattern** (Phase 8 D-08-12). Phase 9 inherits: hub-targeted Ks have NO `spec.kubeConfig`; spoke-targeted Ks have full `spec.kubeConfig` block with P40/P18 `key: value.yaml`. Phase 9's per-tenant inner Ks are spoke-targeted (have `kubeConfig`) and live in per-tenant namespaces on hub (D-09-03).
- **Per-chart / per-area subdirectory layout** (Phase 8 D-08-01 — `pocs/capsule/operator/`, `pocs/capsule/proxy/`). Phase 9 extends: `pocs/capsule/spoke/config/`, `pocs/capsule/spoke/tenants/{alpha,bravo}/`, `pocs/capsule/tenants/{alpha-app,bravo-app}/`. Each subdirectory has its own `kustomization.yaml` + content YAMLs + head comment block citing decision + REQ-ID.
- **HelmRelease `dependsOn` + `wait: true`** (Phase 8 D-08-07 — `capsule-proxy` HR depends on `capsule` HR). Phase 9 escalates to Kustomization-CR level (D-09-06): `poc-capsule-spoke` outer K depends on `poc-capsule` outer K; per-tenant inner Ks depend on `poc-capsule` outer K. Same `wait: true` semantics (dependent does not start applying until dependency `Ready=True`).
- **Pitfall-7 placeholder pattern** (Phase 7 D-06 / Phase 8 spoke/). Phase 9 reuses for `pocs/capsule/tenants/{alpha-app,bravo-app}/kustomization.yaml` (`resources: []`).
- **Wave 0 RED bats scaffold** (Phase 7 Plan 07-00 / Phase 8 D-08-09). Phase 9 reuses Plan 09-00.
- **Bash strict-mode + `REPO_ROOT`/`SCRIPT_DIR` pinning** — Phase 9 has no new scripts (per Claude's Discretion); pattern reused only if planner reverses default.
- **Bats static-contract test naming `<area>-<NN>-<static|live>-<topic>.bats`** — Phase 9 suggested names (planner reshapes file partition):
  - `tenants-01-static-tenant-cr.bats` (TEN-01)
  - `tenants-02-static-p27.bats` (TEN-04 — P27 yq-based grep)
  - `tenants-03-static-lockdown.bats` (TEN-05 — patches block + escape hatch)
  - `tenants-04-static-dependson.bats` (TEN-06 — dependsOn chain)
  - `tenants-05-static-split-path.bats` (D-08-12 inheritance regression)
  - `tenants-06-live-tenant-cr.bats` (TEN-01)
  - `tenants-07-live-impersonate.bats` (TEN-02 — kubectl --as)
  - `tenants-08-live-quota-limit.bats` (TEN-03 — auto-materialization)
  - `tenants-09-live-inner-k-ready.bats` (TEN-04 reconcile)
  - `tenants-10-live-lockdown.bats` (TEN-05 — Deployment args + flux-system K Ready)
  - `tenants-11-live-dependson.bats` (TEN-06)
  - `tenants-12-live-health-check.bats` (v0.18 regression gate)
- **POC isolation regression** (Phase 7 P31 contract; Phase 8 verifier rerun). Phase 9 verifier reruns `tests/bats/poc-isolation-01-static.bats` to confirm new files under `pocs/capsule/{tenants,spoke}/...` did NOT introduce `spoke-capsule` mentions in v0.18 scripts.

### Integration Points

- **`clusters/hub-flux/flux-system/kustomization.yaml`** — FLUX PATCH SURFACE direct edit (NEW patches block per D-09-05). The lockdown patches modify kustomize-controller / helm-controller / notification-controller Deployments + the `flux-system` Kustomization CR's `serviceAccountName`. After Flux reconciles, the Deployments restart with new args (~30–60s).
- **`clusters/hub-flux/pocs/capsule.yaml`** — modified to add `spec.serviceAccountName: kustomize-controller` (escape hatch).
- **`clusters/hub-flux/pocs/capsule-spoke.yaml`** — modified to add `dependsOn` block (D-09-06).
- **`pocs/capsule/kustomization.yaml`** — modified to add `tenants/` resource line (D-09-01).
- **`pocs/capsule/tenants/`** (NEW directory) — hub-targeted: per-tenant Namespace + GitRepository + Kustomization + alpha-app/ + bravo-app/ placeholder dirs.
- **`pocs/capsule/spoke/kustomization.yaml`** — modified to populate `resources: [config/, tenants/]`.
- **`pocs/capsule/spoke/config/`** (NEW directory) — spoke-targeted: CapsuleConfiguration/default singleton.
- **`pocs/capsule/spoke/tenants/`** (NEW directory) — spoke-targeted: per-tenant {namespace, sa, tenant} CRs.
- **No `task` surface extensions in Phase 9** (per Claude's Discretion). Verifier surface is bats + `task health-check` rerun.
- **No `task preflight` extensions in Phase 9.** Phase 7 already locked NodePort 30443 reservation. No new ports.
- **No `.gitignore` / `.gitleaks.toml` extensions in Phase 9.** Phase 7 closed the kubeconfig leak surface; Phase 9 has no kubeconfig-shaped artifacts (Tenant CRs do not contain bearer tokens). Phase 10 PROXY-03 re-exercises gitleaks via tenant kubeconfig issuance synthetic fixtures.
- **`docs/poc-capsule.md`** — Phase 7 doc gains a Phase 9 "Tenants" subsection — two Tenants alpha + bravo, gitops-reconciler SAs, lockdown flag set, escape hatch on flux-system Kustomization. Planner decides cross-link depth.

### Risks (carried from STATE.md Blockers/Concerns)

- **Phase 9 lockdown flag patches touch v0.18 Flux bootstrap surface — high regression risk.** Mitigation per D-09-05a / Plan 09-03 plan structure: rerun full v0.18 `task health-check` immediately AFTER applying the lockdown patches. If health-check fails, roll back the patch atomically and re-plan. The escape hatch on flux-system Kustomization (`spec.serviceAccountName: kustomize-controller`) is the load-bearing defense against lockdown self-blocking Flux's own bootstrap reconcile. Without the escape hatch, applying TEN-05 immediately bricks the hub Flux reconcile.

</code_context>

<specifics>
## Specific Ideas

- **Per-tenant SA pattern is canonical clastix/flux2-capsule-multi-tenancy** — verbatim mirror, not a karyon invention. The pattern: tenant home namespace on spoke, gitops-reconciler SA in that namespace, Tenant CR registers `<tenant-ns>:gitops-reconciler` as a `kind: ServiceAccount` Owner. Per-tenant hub-side namespace mirrors the same name so the Kustomization CR can live there and Flux's same-namespace impersonation rule resolves correctly.

- **Multi-owner Tenant CR (SA + User)** — necessary for both contracts:
  - SA owner (`<tenant-ns>:gitops-reconciler`) → Flux impersonation (TEN-04 P27 defense).
  - User owner (`alpha`) → human/CLI testing (TEN-02 `kubectl --as=alpha`).
  - Capsule webhook treats either matched identity as a tenant owner. No conflict.

- **Lockdown flag patch surface is `clusters/hub-flux/flux-system/kustomization.yaml`** — the SAME file as `# KARYON SPOKES MOUNT` and `# KARYON POC MOUNT` sentinels. **NOT a new file.** This is the documented FLUX PATCH SURFACE (file's own header comment block). Adding the patches block here means it survives `flux bootstrap` re-runs.

- **Per-controller flag scoping per Flux v2.8 docs:**
  - kustomize-controller: ALL 3 flags (`--no-cross-namespace-refs`, `--no-remote-bases`, `--default-service-account=default`).
  - helm-controller: `--no-cross-namespace-refs` only.
  - notification-controller: `--no-cross-namespace-refs` only.
  - source-controller: NONE (sources are owned by source-controller; lockdown happens on consumer side).

- **`flux-system` Kustomization CR escape hatch is LOAD-BEARING.** Without `spec.serviceAccountName: kustomize-controller` on the bootstrap-managed `flux-system` Kustomization CR, applying the `--default-service-account=default` flag immediately bricks Flux's own reconcile (because the bootstrap-managed flux-system K does NOT set serviceAccountName, so kustomize-controller treats it as needing default SA → no-permission → Ready=False → hub reconcile stops). The patch on the K (NOT on the controller Deployment) is what the lockdown SAFELY tolerates.

- **`spec.kubeConfig` skips the `--default-service-account` flag scope** — per Flux kustomize-controller v2.8.x source, the `--default-service-account` flag applies ONLY to local-cluster reconciles (where `spec.kubeConfig` is unset). Cross-cluster reconciles (`spec.kubeConfig` set) are NOT subject to the flag — they use the kubeConfig Secret's principal directly, OR if `spec.serviceAccountName` is also set, they impersonate. **This is the EXACT root cause of P27** (load-bearing security invariant). Hub-targeted Ks under lockdown need `serviceAccountName: kustomize-controller` (the platform-admin escape hatch); spoke-targeted Ks (`poc-capsule-spoke`, per-tenant inner Ks) do NOT (they have `kubeConfig`, are exempt from the flag), but explicit `spec.serviceAccountName` is still required for tenant inner Ks per P27 (different defense chain — the `default-service-account` flag is the LOCAL safety net; tenant-K explicit-set is the CROSS-CLUSTER defense).

- **Tenant inner K placeholder path** — `pocs/capsule/tenants/alpha-app/kustomization.yaml` ships with `resources: []` (Pitfall-7 defense, mirrors Phase 7 D-06 + Phase 8 D-08-12 spoke/ pattern). Phase 9 lives reconcile of this empty placeholder is the proxy for "the K's RBAC chain works"; actual workload deployment is deferred (Phase 11 Phase 11 negative-RBAC tests + tenant workload Deployments).

- **D-09-03a research item — `kubeConfig.secretRef` under `--no-cross-namespace-refs`** — per Flux v2.8 docs the flag's documented scope is `sourceRef`, `decryption.secretRef`, `verify.secretRef`. `kubeConfig.secretRef` is NOT in the documented list. Researcher must verify against kustomize-controller v2.8.x source. Fallback (mirror Secret per tenant ns) does not change Phase 9's directory layout, only adds a `register-poc-cluster.sh` extension. Default assumption: Flux exempts; spec stands as written.

- **`kubectl --as=` impersonation requires cluster-admin** — the LOCAL human kubeconfig (k3d default) has cluster-admin via the bootstrap k3d service account. `kubectl --as=alpha` is impersonating User `alpha` from a cluster-admin principal → allowed at apiserver impersonation layer → forwarded to Capsule webhook → matched against Tenant alpha owners → allowed within tenant prefix. Without cluster-admin (e.g., from a tenant-owner kubeconfig) the impersonation would itself be denied at the apiserver layer (not by Capsule). This subtlety is documented for the verifier so it's clear WHY `--as=alpha` works from the human's CLI but a tenant-issued kubeconfig doing `--as=alpha-other-user` would fail.

</specifics>

<deferred>
## Deferred Ideas

True deferrals to later phases (already locked at milestone-open or by ROADMAP / REQUIREMENTS un-bundling, restated for plan-side awareness):

- **Tenant owner kubeconfigs (PROXY-01) — `scripts/poc/capsule/issue-tenant-kubeconfig.sh <tenant> <owner>`** → **Phase 10**. Phase 9 D-09-03 uses the existing `spoke-capsule-kubeconfig` for transitional tenant-K reconcile (cluster-admin auth + SA impersonation); Phase 10 swaps `spec.kubeConfig.secretRef.name` to per-tenant proxy-kubeconfigs (PROXY-02 contract).
- **Capsule-proxy round-trip + LIST visibility filtering (PROXY-02)** → **Phase 10**. Phase 9 does NOT exercise the proxy LIST filter; the existing direct-apiserver flow on `:6446` (unfiltered) is what verifier uses for TEN-02 / TEN-03 observation.
- **gitleaks rule + synthetic-fixture bats for tenant kubeconfigs (PROXY-03)** → **Phase 10**. Phase 9 has no kubeconfig-shaped artifacts; the gitleaks rule from Phase 7 D-14 is sufficient.
- **Negative RBAC bats N1–N12** → **Phase 11** (VAL-01). Phase 9 verifier asserts only POSITIVE-direction shape (TEN-01..06 contracts). Negative-direction tests (cross-tenant denials, escalation denials, missing serviceAccountName denial, etc.) are Phase 11 scope.
- **Capsule webhook failure / recoverable mode (`task fail-capsule-webhook`)** → **Phase 11** (VAL-02).
- **Clean teardown (`task destroy-poc capsule` ordered teardown)** → **Phase 11** (VAL-03). Phase 9 verifier leaves alpha-app1 + bravo-app1 namespaces in place.
- **`task rebuild` SLO regression test (< 230s with spoke-capsule alive)** → **Phase 11** (VAL-04). Phase 9 P31 isolation gate (static bats) is sufficient for Phase 9.
- **One-shot history gitleaks scan post-Phase-10 first push** → **Phase 11** (VAL-05) — Phase 8 D-08-13 push-gate deferral remains in force; Phase 9 commits remain local-only (no push).
- **Graduation ADR-008** → **Phase 11** (VAL-06).
- **`capsule-addon-fluxcd v0.2.3` trial** → **Phase 12** (OPTIONAL — gated on ADR-008 outcome ∈ {adopt, defer}).
- **Tenant workload Deployments (e.g., `alpha-app1` running an actual pod)** → **Phase 11** workload demonstration. Phase 9's tenant inner K placeholder paths (`alpha-app/`, `bravo-app/`) ship with `resources: []`; Phase 11 may populate.
- **HA Capsule (multi-replica + leader election), OIDC, multi-spoke federation** → POST-v0.19 milestones (REQUIREMENTS.md "Future Requirements" + PROJECT.md Out-of-Scope).
- **Less-privileged `flux-reconciler` SA on spoke (replacing v0.18 cluster-admin Pattern 3)** → POST-v0.19 (REQUIREMENTS.md "Future Requirements"). Phase 9 retains the v0.18 cluster-admin spoke-capsule-kubeconfig with SA impersonation as the chokepoint.

### Reviewed Todos (not folded)

- **`2026-04-29-phase-7-gitleaks-planning-doc-allowlist.md` (`resolves_phase: 11`)** — Auto-mode score 0.6 met the relevance threshold for Phase 9 (keyword match on "phase, spoke, capsule"), but the explicit `resolves_phase: 11` marker overrides — this todo is owned by Phase 11 (VAL-05 explicitly owns the one-shot history gitleaks scan post-Phase-10 first push). Phase 9 does NOT touch `.gitleaks.toml`, `.planning/phases/07-*` planning docs, or any of the named files. Phase 9 has no kubeconfig-shaped artifacts (no synthetic-fixture bats added to `tests/fixtures/gitleaks/`). Reviewing for awareness only. Todo will auto-close when `/gsd-execute-phase 11` runs.
- **`2026-04-29-phase-7-hub-flux-observable-reconcile.md` (`resolves_phase: 8`)** — Auto-mode score 0.6 met the relevance threshold for Phase 9 (keyword match on "phase, hub, flux, capsule, kustomization"), but the explicit `resolves_phase: 8` marker overrides — this todo was carried forward to Phase 8 verifier (folded into 08-CONTEXT D-08-09 live-bats fold). Phase 8 verification reported `passed_with_overrides` 2026-04-30 (`Applied revision: main@sha1:32e0b2fa`); the "fragile pass" caveat (masked by empty inventory pre-Phase-8 push) lifts in Phase 9 because Phase 9 commits add tenant CRs, populated config/, etc. — outer `poc-capsule-spoke` will reconcile with non-empty inventory after first push (Phase 11 VAL-05). Phase 9 verifier MAY re-observe the carryover as a side effect (TEN-06 dependsOn chain reconcile), but the todo's primary owner is Phase 8 close-out (already complete). Todo will auto-close on Phase 11 push (per `resolves_phase: 8` re-firing on first observable post-Phase-9 reconcile, OR via manual close-out gate during Phase 11 VAL-05 push event).

### Out-of-band ideas surfaced during analysis (NOT in current scope)

- None — analysis stayed within Phase 9 scope. The split between Phase 9 (tenant control plane + lockdown using existing kubeconfig + SA impersonation) and Phase 10 (per-tenant proxy-kubeconfigs swap + capsule-proxy round-trip) is a deliberate ROADMAP / REQUIREMENTS un-bundling, not a deferral discovered during this discussion.

</deferred>

---

*Phase: 09-tenants-flux-multi-tenancy-lockdown*
*Context gathered: 2026-04-29*
*Mode: --auto (recommended defaults across all 9 gray areas; no interactive questions)*
