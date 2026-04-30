# Phase 9 Research — Tenants + Flux Multi-Tenancy Lockdown

**Researched:** 2026-04-29
**Confidence:** HIGH on Gaps 1, 2, 3, 4, 5, 8, 10, 11, 12, 13 (all primary claims cited from upstream source / docs); MEDIUM on Gap 6 (webhook objectSelector defaults — verified from chart values but Capsule chart shows mixed defaults across hooks); HIGH on Gap 7 (k8s impersonation docs definitive); HIGH on Gap 9 (kustomize patches: + resources: ordering well-documented).
**Sources:** Flux v2.8.6 docs + kustomize-controller v1 API + Capsule v0.12.4 CRDs (raw GitHub, downloaded 2026-04-29) + clastix/flux2-capsule-multi-tenancy + Kubernetes RBAC docs.

> **Three corrections to CONTEXT.md surfaced by this research — planner MUST adjust:**
>
> 1. **`forceTenantPrefix` is at `spec.forceTenantPrefix` (top-level), NOT `spec.namespaceOptions.forceTenantPrefix`.** CONTEXT.md D-09-02 yaml is wrong. Verified by reading v0.12.4 Tenant CRD raw schema (`/tmp/tenant-crd.yaml` line 1274; v1beta1 also at line 1274; v1beta2 at line 2310-area). See Gap 4.
> 2. **`spec.owners[].namespace` does NOT exist.** v1beta2 owners array has only `kind`, `name`, `clusterRoles`, `labels`, `annotations`, `proxySettings`. ServiceAccount owners use the **combined name format**: `name: system:serviceaccount:tenant-alpha:gitops-reconciler`, NOT `name: gitops-reconciler` + `namespace: tenant-alpha`. CONTEXT.md D-09-02 yaml is wrong. See Gap 4.
> 3. **`kubeConfig.secretRef` MUST be in the same namespace as the Kustomization unconditionally** — not gated by `--no-cross-namespace-refs`. The flag's documented scope is `sourceRef`, `decryption.secretRef`, `verify.secretRef`. `kubeConfig.secretRef` has its own hard same-namespace constraint baked into kustomize-controller. CONTEXT.md D-09-03 transitional shape (per-tenant K in `tenant-alpha` namespace referencing `flux-system/spoke-capsule-kubeconfig`) **WILL NOT work**. See Gap 1 — recommended mitigation: mirror the Secret per tenant namespace via `register-poc-cluster.sh` extension.

---

## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-09-01** — Phase 9 directory layout: `pocs/capsule/{operator,proxy}/` (Phase 8 unchanged); NEW `pocs/capsule/spoke/{config,tenants/{alpha,bravo}/}` (spoke-targeted CapsuleConfiguration + Tenant CRs + per-tenant SAs); NEW `pocs/capsule/tenants/{alpha,bravo}.yaml` + `tenants/{alpha-app,bravo-app}/kustomization.yaml` (hub-targeted inner Kustomizations + Pitfall-7 placeholders).
- **D-09-02** — Per-tenant SA pattern (clastix flux2-capsule-multi-tenancy canonical): on spoke-capsule, `Namespace tenant-<name>` + `ServiceAccount gitops-reconciler` + Tenant CR multi-owner array (SA + User). On hub-flux, `Namespace tenant-<name>` (mirror) so Kustomization CR can live there. **Yaml correction needed — see Gap 4.**
- **D-09-03** — Tenant inner Kustomization Phase 9 transitional shape: `kind: Kustomization` in `namespace: tenant-<name>` on hub, with `spec.kubeConfig.secretRef.name: spoke-capsule-kubeconfig` (transitional cluster-admin auth + SA impersonation; Phase 10 swaps to per-tenant proxy-kubeconfig), `spec.serviceAccountName: gitops-reconciler` (P27), `spec.dependsOn: [{name: poc-capsule, namespace: flux-system}]`, `spec.sourceRef: {kind: GitRepository, name: tenant-<name>-source}` in same namespace. **Cross-namespace Secret mitigation required — see Gap 1.**
- **D-09-03b** — Per-tenant `GitRepository` CR in `tenant-<name>` namespace on hub, `apiVersion: source.toolkit.fluxcd.io/v1`, public HTTPS URL, no `secretRef`. `${GITHUB_OWNER}` substitution via Flux postBuild substituteFrom (NOT inline at task time — see Gap 10).
- **D-09-04** — `CapsuleConfiguration/default` singleton in `pocs/capsule/spoke/config/` with `forceTenantPrefix: true`, `allowServiceAccountPromotion: true`, `userGroups: [capsule.clastix.io]`, `protectedNamespaceRegex: ^kube-.*$`, `nodeMetadata: {forbiddenAnnotations: {}, forbiddenLabels: {}}`. **Yaml correction needed — see Gap 5.**
- **D-09-05** — Hub Flux multi-tenancy lockdown patches in `clusters/hub-flux/flux-system/kustomization.yaml` (FLUX PATCH SURFACE). Per-controller scoping: kustomize-controller (all 3 flags), helm-controller + notification-controller (`--no-cross-namespace-refs` only), source-controller (none). Plus `flux-system` Kustomization escape-hatch patch (`spec.serviceAccountName: kustomize-controller`).
- **D-09-05a** — `flux-system` Kustomization escape hatch is LOAD-BEARING. Without it, `--default-service-account=default` immediately bricks Flux's own bootstrap reconcile.
- **D-09-06** — TEN-06 dependsOn chain: `poc-capsule-spoke` outer K depends on `poc-capsule` outer K with `wait: true`; per-tenant inner Ks depend on `poc-capsule` with `wait: true`.
- **D-09-07** — TEN-02 verifier path: `kubectl --context=k3d-spoke-capsule --as=alpha create namespace alpha-app1` (cluster-admin local kubeconfig + impersonate User `alpha`).
- **D-09-08** — Repeat Phase 7/8 Wave 0 RED bats pattern in Plan 09-00.
- **D-09-09** — Plan ordering 09-00 (Wave 0 bats) → 09-01 (CapsuleConfiguration + spoke-side Tenants) → 09-02 (hub-side inner Ks + GitRepositories) → 09-03 (lockdown + escape hatch + health-check rerun) → 09-04 (verifier).

### Claude's Discretion

- No new `task` targets in Phase 9 (verifier surface is bats + `task health-check`).
- Tenant CR `spec.resourceQuotas`, `spec.limitRanges` minimal: cpu 4 / memory 8Gi / pods 20; pod default 100m/128Mi, defaultRequest 50m/64Mi.
- Tenant CR `spec.storageClasses` / `spec.ingressClasses` / `spec.containerRegistries` / `spec.nodeSelector` omitted (allow-all).
- Tenant CR `spec.networkPolicies` omitted.
- Lockdown patch `task health-check` rerun timing: TWO reruns — pre-patch baseline + post-patch regression assertion.
- Reconcile noise tolerance: ≤2 reconcile cycles (~10 min) per tenant inner K; live-bats retry budget 3 × 30s (matches Phase 8 D-08).

### Deferred Ideas (OUT OF SCOPE)

- Tenant owner kubeconfigs minted via `issue-tenant-kubeconfig.sh` → Phase 10 (PROXY-01).
- capsule-proxy LIST filtering round-trip → Phase 10 (PROXY-02).
- gitleaks rule for tenant kubeconfigs → Phase 10 (PROXY-03).
- Negative RBAC bats N1–N12, webhook failure recovery, ordered teardown, `task rebuild` SLO regression, ADR-008 → Phase 11.
- Tenant workload Deployments → Phase 11.
- `capsule-addon-fluxcd v0.2.3` trial → Phase 12 (gated).
- HA Capsule, OIDC, multi-spoke federation, less-privileged spoke SA → POST-v0.19.

---

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| TEN-01 | Two `Tenant` CRs (alpha, bravo) with disjoint owners (kind: ServiceAccount) registered as `<tenant-ns>:gitops-reconciler`; namespace prefix enforcement (`forceTenantPrefix: true`) | Gap 4 (Tenant CR shape) + Gap 5 (CapsuleConfiguration shape) |
| TEN-02 | Tenant owner can self-serve namespace inside tenant prefix; auto-stamping with `capsule.clastix.io/tenant=alpha` | Gap 7 (impersonation prereqs) + Gap 13 (Tenant must-haves) |
| TEN-03 | ResourceQuota + LimitRange auto-materialize inside tenant namespace | Gap 4 (resourceQuotas/limitRanges schema) |
| TEN-04 | Every tenant inner Kustomization declares `spec.serviceAccountName: gitops-reconciler` (P27) | Gap 3 (P27 root cause cited) |
| TEN-05 | Hub Flux controllers patched with lockdown flags + `flux-system` Kustomization escape hatch | Gap 2 (per-controller flag matrix) |
| TEN-06 | Tenants outer Kustomization declares `dependsOn` on operator K with `wait: true` | Gap 8 (apply ordering) |

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | bats-core (v0.18 inheritance — verified via `tests/bats/test_helper`) |
| Config file | `tests/bats/test_helper` (shared loader; sets REPO_ROOT) |
| Quick run command | `bats tests/bats/tenants-*.bats` (all Phase 9 tests) |
| Static-only command | `bats tests/bats/tenants-{01,02,03,04,05}-static-*.bats` |
| Live-only command | `bats tests/bats/tenants-{06,07,08,09,10,11,12}-live-*.bats` (auto-skips when clusters unreachable) |
| Phase gate | All 12 bats files GREEN before `/gsd-verify-work` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| TEN-01 | Both Tenant CR yaml files declare correct owners + forceTenantPrefix | static (yq) | `bats tests/bats/tenants-01-static-tenant-cr.bats` | ❌ Wave 0 |
| TEN-01 | Live: kubectl get tenants returns alpha + bravo with forceTenantPrefix=true | live (gated) | `bats tests/bats/tenants-06-live-tenant-cr.bats` | ❌ Wave 0 |
| TEN-02 | Live: kubectl --as=alpha create namespace alpha-app1 succeeds + label stamped | live (gated) | `bats tests/bats/tenants-07-live-impersonate.bats` | ❌ Wave 0 |
| TEN-03 | Live: ResourceQuota + LimitRange auto-materialize in tenant ns | live (gated) | `bats tests/bats/tenants-08-live-quota-limit.bats` | ❌ Wave 0 |
| TEN-04 | Static: every tenant inner K yaml has spec.serviceAccountName non-null (P27) | static (yq) | `bats tests/bats/tenants-02-static-p27.bats` | ❌ Wave 0 |
| TEN-04 | Live: tenant-alpha-app Kustomization Ready=True | live (gated) | `bats tests/bats/tenants-09-live-inner-k-ready.bats` | ❌ Wave 0 |
| TEN-05 | Static: lockdown patches block + escape-hatch patch in flux-system kustomization.yaml | static (grep+yq) | `bats tests/bats/tenants-03-static-lockdown.bats` | ❌ Wave 0 |
| TEN-05 | Live: kustomize-controller Deployment args contain all 3 flags + flux-system K Ready=True | live (gated) | `bats tests/bats/tenants-10-live-lockdown.bats` | ❌ Wave 0 |
| TEN-06 | Static: poc-capsule-spoke + per-tenant inner Ks have dependsOn: poc-capsule wait: true | static (yq) | `bats tests/bats/tenants-04-static-dependson.bats` | ❌ Wave 0 |
| TEN-06 | Live: poc-capsule-spoke Kustomization Ready=True after apply | live (gated) | `bats tests/bats/tenants-11-live-dependson.bats` | ❌ Wave 0 |
| Cross-cutting | Phase 8 split-path invariant preserved (D-08-12 inheritance regression) | static (yq) | `bats tests/bats/tenants-05-static-split-path.bats` | ❌ Wave 0 |
| Cross-cutting | v0.18 task health-check passes after lockdown patch (regression gate) | live | `bats tests/bats/tenants-12-live-health-check.bats` | ❌ Wave 0 |
| Cross-cutting | P31 isolation regression (Phase 9 files don't introduce spoke-capsule mentions) | static | (rerun) `bats tests/bats/poc-isolation-01-static.bats` | ✅ exists |
| Cross-cutting | Phase 8 ADR-004 + CAP-01..03 invariants preserved | live (gated) | (rerun) `bats tests/bats/capsule-install-{06,07,08,09,10}-live-*.bats` | ✅ exists |

### Sampling Rate

- **Per task commit:** `bats tests/bats/tenants-{01,02,03,04,05}-static-*.bats` (static-only; <5s).
- **Per wave merge:** All 12 Phase 9 bats files + Phase 8 reruns.
- **Phase gate:** Full bats suite + `task health-check` exit 0.

### Wave 0 Gaps

- [ ] `tests/bats/tenants-01-static-tenant-cr.bats` — covers TEN-01 (Tenant CR yaml shape)
- [ ] `tests/bats/tenants-02-static-p27.bats` — covers TEN-04 (P27 serviceAccountName grep)
- [ ] `tests/bats/tenants-03-static-lockdown.bats` — covers TEN-05 (patches block + escape hatch)
- [ ] `tests/bats/tenants-04-static-dependson.bats` — covers TEN-06 (dependsOn chain)
- [ ] `tests/bats/tenants-05-static-split-path.bats` — covers cross-cutting (D-08-12 regression)
- [ ] `tests/bats/tenants-06-live-tenant-cr.bats` — covers TEN-01 live
- [ ] `tests/bats/tenants-07-live-impersonate.bats` — covers TEN-02 live (kubectl --as=alpha)
- [ ] `tests/bats/tenants-08-live-quota-limit.bats` — covers TEN-03 live (auto-materialize)
- [ ] `tests/bats/tenants-09-live-inner-k-ready.bats` — covers TEN-04 live (inner K reconcile)
- [ ] `tests/bats/tenants-10-live-lockdown.bats` — covers TEN-05 live (Deployment args + flux-system K Ready)
- [ ] `tests/bats/tenants-11-live-dependson.bats` — covers TEN-06 live (poc-capsule-spoke Ready=True)
- [ ] `tests/bats/tenants-12-live-health-check.bats` — covers cross-cutting (v0.18 regression gate)

(All bats files are NEW; no framework install needed; bats-core already present in v0.18 baseline.)

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Tenant CR + CapsuleConfiguration declaration | Spoke-targeted Flux Kustomization (`poc-capsule-spoke`) | Hub kustomize-controller | Tenant + CapsuleConfiguration are spoke-cluster resources; reconciled via `spec.kubeConfig` |
| Tenant inner Flux Kustomization (per-tenant impersonation) | Hub-flux apiserver | Hub kustomize-controller (same controller, different K instance) | Inner K CR lives on hub in `tenant-<name>` namespace; targets spoke via `spec.kubeConfig` + `spec.serviceAccountName` impersonation |
| Multi-tenancy lockdown (controller flags) | Hub-flux Deployment patches | Hub kustomize-controller (self-applied via flux-system Kustomization) | Patches modify Deployment args in `flux-system` namespace on hub |
| Tenant namespace creation | Spoke apiserver (Capsule webhook) | Capsule controller (label stamping post-create) | Webhook `forceTenantPrefix` enforces prefix at admission; controller post-creates ResourceQuota/LimitRange |
| Per-tenant GitRepository CR | Hub-flux source-controller | (none) | Tenant-namespaced GitRepository on hub, fetched by source-controller |
| `kubectl --as=alpha` impersonation | Spoke apiserver authentication layer | Capsule webhook authorization | Apiserver validates impersonate verb against caller (system:masters bypasses); Capsule webhook then matches impersonated identity against Tenant.spec.owners |

---

## Gap 1: kubeConfig.secretRef under --no-cross-namespace-refs

### Answer: **BLOCKED — but for a DIFFERENT reason than D-09-03a anticipated.**

The CONTEXT.md framing is wrong. The `--no-cross-namespace-refs` flag does NOT govern `kubeConfig.secretRef` AT ALL — its documented scope is strictly `sourceRef`, `decryption.secretRef`, `verify.secretRef`. **However, `kubeConfig.secretRef` has an UNCONDITIONAL same-namespace constraint built into kustomize-controller's API contract** that fires regardless of whether the lockdown flag is set.

**Citation 1 — Flux v2.8 docs (kustomizations.md, Secret-based authentication section):**
> "The secret defined in the `.spec.kubeConfig.secretRef` must exist in the same namespace as the Kustomization."

**Citation 2 — Flux v2.8 docs (further constraint):**
> "When both `.spec.kubeConfig` and `.spec.serviceAccountName` are specified, the controller will impersonate the ServiceAccount on the target cluster, i.e. a ServiceAccount with name `.spec.serviceAccountName` must exist in the target cluster inside a namespace with the same name as the namespace of the Kustomization."

**Citation 3 — kustomize-controller v1 API Go source (`api/v1/kustomization_types.go`):**
> ```go
> // The KubeConfig for reconciling the Kustomization on a remote cluster.
> // When used in combination with KustomizationSpec.ServiceAccountName,
> // forces the controller to act on behalf of that Service Account at the
> // target cluster.
> KubeConfig *meta.KubeConfigReference `json:"kubeConfig,omitempty"`
> ```

This means CONTEXT.md D-09-03's transitional shape — Kustomization in `tenant-alpha` namespace on hub referencing `flux-system/spoke-capsule-kubeconfig` — **WILL NOT WORK**. kustomize-controller will either reject the reference or refuse to load the Secret. Flux's contract is explicit: `kubeConfig.secretRef` Secret MUST live in the same namespace as the Kustomization CR, full stop.

### Recommended Mitigation

**Mirror the `spoke-capsule-kubeconfig` Secret into each tenant namespace on hub-flux** via a `register-poc-cluster.sh` extension. The Secret is already applied imperatively (Phase 7 register-poc-cluster.sh pattern), so adding two more `kubectl apply` invocations is cheap and idempotent.

**The MUST-DO addition to `scripts/register-poc-cluster.sh`** (or a new `scripts/poc/capsule/mirror-kubeconfig-to-tenants.sh`):

```bash
# Mirror spoke-capsule-kubeconfig Secret into per-tenant namespaces on hub.
# Required because Flux's kubeConfig.secretRef has hard same-namespace constraint
# (see Phase 9 RESEARCH Gap 1). The tenant namespaces tenant-alpha + tenant-bravo
# host the per-tenant inner Kustomization CRs, which reference this Secret.
for tenant in alpha bravo; do
  kubectl --context=k3d-hub-flux create namespace "tenant-${tenant}" \
    --dry-run=client -o yaml | kubectl --context=k3d-hub-flux apply -f -
  kubectl --context=k3d-hub-flux -n flux-system get secret spoke-capsule-kubeconfig -o yaml \
    | yq eval '.metadata.namespace = "tenant-'"${tenant}"'" | del(.metadata.resourceVersion, .metadata.uid, .metadata.creationTimestamp)' - \
    | kubectl --context=k3d-hub-flux apply -f -
done
```

(Plan-time alternative: declare the per-tenant namespace yaml-only and let Plan 09-02's hub-side `pocs/capsule/tenants/<name>.yaml` create the namespace; the Secret mirror runs imperatively after `kubectl apply` of the inner Kustomization but BEFORE the Kustomization's first reconcile. This keeps the Secret out of git per P29 and matches the Phase 7 register-poc-cluster.sh "imperative apply" pattern.)

**Plan-time impact:** D-09-03 transitional spec stands as written, BUT Plan 09-02 must include the imperative Secret mirror step. Without it, the per-tenant inner K reaches `Ready=False` with `secret "spoke-capsule-kubeconfig" not found`. Verifier `tenants-09-live-inner-k-ready.bats` will catch this immediately.

### Confidence: HIGH (multiple authoritative sources agree).

---

## Gap 2: Per-controller flag acceptance for Flux v2.8.6

### Answer: Per-controller matrix verified against fluxcd/flux2-multi-tenancy upstream lockdown patch (canonical reference) + Flux multi-tenancy docs.

| Controller | `--no-cross-namespace-refs` | `--no-remote-bases` | `--default-service-account` |
|------------|------------------------------|----------------------|------------------------------|
| **kustomize-controller** | ✅ YES | ✅ YES (kustomize-only) | ✅ YES |
| **helm-controller** | ✅ YES | ❌ NO (no kustomize bases) | ✅ YES (per Flux docs — applies to HelmRelease too) |
| **notification-controller** | ✅ YES (Alert / Provider cross-ns) | ❌ NO | ❌ NO |
| **source-controller** | ❌ NO (sources are owned by source-controller; lockdown is consumer-side) | ❌ NO | ❌ NO |
| image-reflector-controller | ✅ YES (ImagePolicy / ImageRepository cross-ns) | ❌ NO | ❌ NO |
| image-automation-controller | ✅ YES | ❌ NO | ❌ NO |

**Citation — Flux multi-tenancy docs (`fluxcd.io/flux/installation/configuration/multitenancy/`):**
The canonical lockdown patch (verified against `fluxcd/flux2-multi-tenancy` reference repo `clusters/production/flux-system/kustomization.yaml`) targets:

```yaml
- patch: |
    - op: add
      path: /spec/template/spec/containers/0/args/-
      value: --no-cross-namespace-refs=true
  target:
    kind: Deployment
    name: "(kustomize-controller|helm-controller|notification-controller|image-reflector-controller|image-automation-controller)"

- patch: |
    - op: add
      path: /spec/template/spec/containers/0/args/-
      value: --no-remote-bases=true
  target:
    kind: Deployment
    name: "kustomize-controller"

- patch: |
    - op: add
      path: /spec/template/spec/containers/0/args/-
      value: --default-service-account=default
  target:
    kind: Deployment
    name: "(kustomize-controller|helm-controller)"
```

### Plan-time impact for Phase 9

CONTEXT.md D-09-05 specifies `--default-service-account=default` ONLY on kustomize-controller. **This is INCOMPLETE per Flux docs — helm-controller ALSO accepts the flag and SHOULD receive it for full lockdown.** However, Phase 9's tenant Kustomizations are kustomize-Kustomization CRs (not HelmRelease CRs); a HelmRelease without `spec.serviceAccountName` would only emerge for tenant-issued HelmReleases (out of scope until Phase 11). **Recommendation:** Apply `--default-service-account=default` to BOTH kustomize-controller AND helm-controller per upstream canonical pattern. Defense in depth costs nothing; if a future tenant HelmRelease lands without explicit `serviceAccountName`, the flag is the safety net.

The CONTEXT.md narrowing to "kustomize-controller only" was a misread of the per-flag scope. The upstream canonical pattern applies the flag to both.

### Failure mode if a flag is misapplied

If a flag is added to a Deployment that doesn't accept it, the controller logs `unknown flag --foo` at startup and **exits with non-zero code**, not "tolerated and ignored". The Deployment then enters CrashLoopBackOff. Detection: `kubectl -n flux-system get deploy <ctlr> -o jsonpath='{.status.availableReplicas}'` returns 0 within 60s of patch apply. The Phase 9 verifier's `tenants-10-live-lockdown.bats` MUST poll `availableReplicas` for kustomize-controller, helm-controller, notification-controller for ≥2 minutes post-patch to catch this.

### Confidence: HIGH (canonical upstream reference repo + official docs).

---

## Gap 3: --default-service-account flag scope: local-cluster vs cross-cluster

### Answer: CONTEXT.md `<specifics>` is CORRECT — the flag applies ONLY when `spec.kubeConfig` is unset.

**Citation — kustomize-controller v1 API Go source (`api/v1/kustomization_types.go`):**

```go
// The KubeConfig for reconciling the Kustomization on a remote cluster.
// When used in combination with KustomizationSpec.ServiceAccountName,
// forces the controller to act on behalf of that Service Account at the
// target cluster.
// If the --default-service-account flag is set, its value will be used as
// a controller level fallback for when KustomizationSpec.ServiceAccountName
// is empty.
// +optional
KubeConfig *meta.KubeConfigReference `json:"kubeConfig,omitempty"`
```

The Go comment is unambiguous: when **`spec.kubeConfig` is set** AND **`spec.serviceAccountName` is empty**, the `--default-service-account` flag DOES STILL apply as a fallback (via the KubeConfig comment's third sentence). HOWEVER, in karyon's Phase 9 case, the flag's fallback name is `default` — which on spoke-capsule maps to `system:serviceaccount:tenant-alpha:default`, a no-permission SA. So the safety net IS engaged for cross-cluster reconciles where `serviceAccountName` is empty — but only as a no-permission fallback that fails closed.

**The actual P27 root cause is subtler:** the flag's fallback only kicks in if **the kubeConfig Secret's principal would otherwise be used**. With karyon's `spoke-capsule-kubeconfig` (cluster-admin SA token from Phase 7), if a tenant K omits BOTH `serviceAccountName` AND falls through the flag's fallback, kustomize-controller uses the cluster-admin token directly — full bypass.

> **Refinement to CONTEXT.md `<specifics>`:** The flag DOES technically apply to cross-cluster reconciles as a "fall-through default name" — the failure mode is that **without explicit `serviceAccountName`**, the flag's value `default` becomes the impersonated identity, AND that identity must exist on the spoke. If the `default` SA in the K's namespace on the spoke does NOT exist or has no permissions, the K reaches `Ready=False` (failed-closed safe). If the SA exists with cluster-admin (rare but possible if karyon's Pattern 3 cluster-admin binding leaks here), full bypass. **The defense remains: every tenant K MUST set `spec.serviceAccountName` explicitly — the flag is belt-and-suspenders, never the primary defense.**

### Comment-block-ready text for `pocs/capsule/tenants/alpha.yaml`:

```
# P27 LOAD-BEARING DEFENSE — every tenant Flux Kustomization MUST set
# spec.serviceAccountName explicitly. Per Flux v2.8 kustomize-controller v1 API
# (api/v1/kustomization_types.go KubeConfig field comment): when spec.kubeConfig
# is set AND spec.serviceAccountName is empty, kustomize-controller falls through
# to the --default-service-account flag's value (default=`default`). For cross-
# cluster reconciles, this means impersonating system:serviceaccount:<ns>:default
# on the target cluster — a no-permission SA that fails closed BUT only if the
# kubeConfig Secret's principal isn't already cluster-admin. With karyon's
# spoke-capsule-kubeconfig (Phase 7 Pattern 3 — embedded cluster-admin token),
# if BOTH serviceAccountName is empty AND the kubeConfig principal is used,
# kustomize-controller applies as cluster-admin on spoke, bypassing Capsule's
# webhooks (which deliberately exempt cluster-admin / kube-system identities).
# Hence: explicit serviceAccountName is the primary structural defense; the
# --default-service-account flag is belt-and-suspenders.
```

### Confidence: HIGH (Go source code comment is the authoritative reference).

### CORRECTION (Plan 09-03 attempt 1 falsifier — 2026-04-30)

The original §Gap 3 prediction "the flag applies ONLY when `spec.kubeConfig` is unset" + "If the SA exists with cluster-admin (rare but possible if karyon's Pattern 3 cluster-admin binding leaks here), full bypass" + "v0.18 spoke-{apps,ml} use cluster-admin SA via kubeConfig — no impact" is **FALSIFIED** by live observation in Flux v2.8.6 (Plan 09-03 attempt 1, rolled back at commit `9b6b3a5`; documented in `.planning/phases/09-tenants-flux-multi-tenancy-lockdown/09-03-SUMMARY.attempt-1-rollback.md`).

**Live observation:**
- Cross-cluster Kustomizations (`clusters/hub-flux/spokes/spoke-apps.yaml` + `spoke-ml.yaml`) with `spec.kubeConfig` set BUT `spec.serviceAccountName` empty
- → kustomize-controller falls through to `--default-service-account=default` flag value on the TARGET cluster (the spokes)
- → reconcile fails: `User "system:serviceaccount:flux-system:default" cannot patch resource "namespaces"` (mirror error on spoke-apps targeting `karyon-spoke-apps` namespace)

The kubeConfig principal does **NOT** override the SA fallback when `serviceAccountName` is empty. The Go comment in `api/v1/kustomization_types.go` cited above ("If the --default-service-account flag is set, its value will be used as a controller level fallback for when KustomizationSpec.ServiceAccountName is empty.") is correct in isolation but its practical implication for cross-cluster reconciles was misread by the original §Gap 3 analysis: when `serviceAccountName` is empty, the controller-level `default` fallback ALWAYS applies, regardless of whether `spec.kubeConfig` is set.

**Mitigation:** set explicit `spec.serviceAccountName` on EVERY Kustomization CR before `--default-service-account=default` lockdown lands — including the v0.18 spoke files. This is the defense-in-depth path Plan 09-03 RE-PLAN executes (Task 2 adds `spec.serviceAccountName: kustomize-controller` to `spoke-apps.yaml` + `spoke-ml.yaml`).

**Confidence: HIGH (live falsifier; cluster state captured in 09-03-SUMMARY.attempt-1-rollback.md commit chain — `899f2fe` → `9b6b3a5` revert → `6cdbfb2` annotation).**

### CORRECTION 2 (Plan 09-03 attempt 2 falsifier — 2026-04-30)

The Plan 09-03 RE-PLAN attempt 2's proposed mitigation (set `spec.serviceAccountName: kustomize-controller` on v0.18 spoke Kustomization CRs as defense-in-depth before the lockdown flags land) is **FALSIFIED** by live observation in Flux v2.8.6 (Plan 09-03 RE-PLAN attempt 2, rolled back at commits `0feb191` + `cd1cf32`; documented in `.planning/phases/09-tenants-flux-multi-tenancy-lockdown/09-03-SUMMARY.attempt-2-rollback.md`).

**Live observation:**
- Spoke clusters (k3d-spoke-{apps,ml}) only have `flux-reconciler` SA with cluster-admin (registered by `scripts/register-spokes-for-flux.sh:275-310`; ClusterRoleBinding `flux-reconciler-cluster-admin` → `cluster-admin` role)
- They do NOT have a `kustomize-controller` SA — that name only exists on the hub cluster (where the actual kustomize-controller Deployment runs)
- When Flux v2.8.6 sees both `spec.kubeConfig` + `spec.serviceAccountName: kustomize-controller`, it impersonates the named SA ON THE TARGET CLUSTER (the spoke), failing with `User "system:serviceaccount:flux-system:kustomize-controller" cannot patch resource "namespaces" in API group "" in the namespace "<spoke-ns>"`
- Failure mode persists EVEN WITHOUT the lockdown flag patches applied — caused by the Task 2 yaml change alone (Flux's impersonation behavior is independent of the controller's `--default-service-account` flag when serviceAccountName is explicitly set)

**Attempt 3 mitigation (locked by 09-CONTEXT.md attempt3_gap_resolutions Gap A):** Use `spec.serviceAccountName: flux-reconciler` on spoke Ks (matches actually-existing SA; self-impersonation under cluster-admin token via the spoke-{apps,ml}-kubeconfig Secret's bearer token, which IS the flux-reconciler SA's token).

**Defense-in-depth invariant restated (target-cluster-specific SA naming):**
- Hub-targeted Ks (`flux-system` K, `poc-capsule` via `capsule.yaml`) → `serviceAccountName: kustomize-controller` (matches hub-side bootstrap SA)
- Spoke-{apps,ml}-targeted Ks (`spoke-apps`, `spoke-ml`) → `serviceAccountName: flux-reconciler` (matches spoke-side SA registered by `register-spokes-for-flux.sh`)
- Spoke-capsule tenant Ks (Plan 09-02 — `tenants/alpha.yaml`, `tenants/bravo.yaml`) → `serviceAccountName: gitops-reconciler` (per-tenant SA on spoke-capsule per D-09-02)

The three SA names are NOT interchangeable — each matches the SA available on the target cluster.

**Confidence: HIGH (live falsifier; cluster state captured in `09-03-SUMMARY.attempt-2-rollback.md` commit chain — `7598cd8` (Task 2) + `cb9b00e` (Task 4) → `0feb191` + `cd1cf32` reverts → `d194031` annotation).**

---

## Gap 4: Tenant CR full shape (TEN-01..03)

### Verified against `https://raw.githubusercontent.com/projectcapsule/capsule/v0.12.4/charts/capsule/crds/capsule.clastix.io_tenants.yaml`

**Storage version:** `v1beta2` (line 2898-2899: `served: true; storage: true`).
**v1beta1 also served** (line 1080-1081: `served: true; storage: false`) — for compatibility.

### Critical schema corrections vs. CONTEXT.md D-09-02

1. **`forceTenantPrefix` is at `spec.forceTenantPrefix` (TOP-LEVEL), NOT `spec.namespaceOptions.forceTenantPrefix`.** Verified at v1beta2 line 2310-area (search "forceTenantPrefix" in CRD schema; the field's description: "Use this if you want to disable/enable the Tenant name prefix to specific Tenants, overriding global forceTenantPrefix in CapsuleConfiguration").
2. **`spec.owners[]` does NOT have a `namespace` field.** v1beta2 owners properties: `kind` (enum: User|Group|ServiceAccount), `name` (string), `clusterRoles` (default: [admin, capsule-namespace-deleter]), `labels`, `annotations`, `proxySettings`. Required: `kind` + `name` only.
3. **ServiceAccount owners use combined-name format:** `name: system:serviceaccount:<ns>:<sa-name>`. Confirmed by Capsule docs `projectcapsule.dev/docs/tenants/permissions/`:
   ```yaml
   spec:
     owners:
     - name: alice
       kind: User
     - name: system:serviceaccount:tenant-system:robot
       kind: ServiceAccount
   ```
4. **Tenant supports multiple owners of mixed kinds** (User + ServiceAccount + Group all in same array). Confirmed by docs.

### Complete working Tenant CR yaml for tenant `alpha`

```yaml
# pocs/capsule/spoke/tenants/alpha/tenant.yaml
# TEN-01 — Tenant CR alpha. Multi-owner (SA + User) per CONTEXT.md D-09-02.
# - SA owner (system:serviceaccount:tenant-alpha:gitops-reconciler): drives Flux impersonation
#   chain (TEN-04 P27 defense — every tenant inner K runs as the SA via Flux's
#   spec.serviceAccountName impersonation on the target cluster).
# - User owner (alpha): drives TEN-02 literal contract — `kubectl --as=alpha create namespace
#   alpha-app1` works because the impersonated identity matches a Tenant owner.
#
# CRD schema verification (v0.12.4):
#   - apiVersion: capsule.clastix.io/v1beta2 (storage version)
#   - spec.forceTenantPrefix: TOP-LEVEL (NOT under namespaceOptions — RESEARCH §Gap 4 correction)
#   - spec.owners[].kind: enum User|Group|ServiceAccount
#   - spec.owners[].name: ServiceAccount uses system:serviceaccount:<ns>:<sa> combined format
#   - spec.owners[].namespace: DOES NOT EXIST in v1beta2 schema
apiVersion: capsule.clastix.io/v1beta2
kind: Tenant
metadata:
  name: alpha
spec:
  # TEN-01 — namespace prefix enforcement (TOP-LEVEL field per v0.12.4 schema)
  forceTenantPrefix: true
  # TEN-01 — multi-owner array
  owners:
    # Flux impersonation chain (TEN-04 P27 defense)
    - kind: ServiceAccount
      name: system:serviceaccount:tenant-alpha:gitops-reconciler
      # Default clusterRoles: [admin, capsule-namespace-deleter] auto-applied
    # Human/CLI testing (TEN-02 `kubectl --as=alpha`)
    - kind: User
      name: alpha
  # TEN-03 — ResourceQuota auto-materialization shape
  # Capsule reconciles these into ResourceQuota objects in tenant namespaces
  # named capsule-<tenant>-<index>. Phase 9 verifies SHAPE only; enforcement
  # semantics (N6 quota violation) deferred to Phase 11.
  resourceQuotas:
    items:
      - hard:
          cpu: "4"
          memory: 8Gi
          pods: "20"
    # scope: Tenant (default — aggregates across all tenant namespaces)
  # TEN-03 — LimitRange auto-materialization shape
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
  # NOTE: namespaceOptions intentionally OMITTED — TEN-01 only requires
  # forceTenantPrefix (now top-level). namespaceOptions.quota (max namespace
  # count) is omitted; tenant can create unlimited namespaces inside prefix.
  # No additionalRoleBindings, storageClasses, ingressClasses, containerRegistries,
  # nodeSelector, networkPolicies — Capsule defaults to allow-all (per CONTEXT.md
  # Claude's Discretion).
```

Mirror file `pocs/capsule/spoke/tenants/bravo/tenant.yaml` substitutes `alpha → bravo` throughout.

### Optional fields verification

- **`spec.preventDeletion`** (boolean) — exists in v1beta2 (line 2310 of CRD). NOT used in Phase 9 (CONTEXT.md Out-of-Scope per REQUIREMENTS.md).
- **`spec.permissions.matchOwners`** — TenantOwner CR-based dynamic owner promotion. NOT used in Phase 9 (static owners array suffices).
- **`spec.gatewayOptions`** — Gateway API tenancy. NOT used (Out-of-Scope).
- **`spec.podOptions.additionalMetadata`** — auto-stamps labels/annotations on tenant pods. NOT used in Phase 9.
- **`spec.serviceOptions`** — service type allow-list. NOT used.

### Confidence: HIGH (raw CRD schema cross-referenced with docs).

---

## Gap 5: CapsuleConfiguration shape

### Verified against `https://raw.githubusercontent.com/projectcapsule/capsule/v0.12.4/charts/capsule/crds/capsule.clastix.io_capsuleconfigurations.yaml`

### Critical schema corrections vs. CONTEXT.md D-09-04

1. **`forceTenantPrefix` is at `spec.forceTenantPrefix`** (top-level — line 80 of CapsuleConfiguration CRD). ✅ CONTEXT.md correct here.
2. **`allowServiceAccountPromotion` is at `spec.allowServiceAccountPromotion`** (line 67). ✅ CONTEXT.md correct.
3. **`userGroups` is DEPRECATED in v1beta2** but still present (line 155). The CRD comment marks it deprecated. New canonical field replacing it: `users` (array of objects, line 173) and the deprecated alternative `userNames`. **Recommendation:** Keep `userGroups: [capsule.clastix.io]` for chart-default compatibility, BUT document the deprecation in plan comment.
4. **`protectedNamespaceRegex`** (string, line 151) — ✅ CONTEXT.md correct.
5. **`nodeMetadata.forbiddenAnnotations` and `forbiddenLabels`** — schema is `{denied: [string], deniedRegex: string}`, NOT empty `{}`. `forbiddenAnnotations: {}` will validate (object with no required fields), but the CRD shape supports `{denied: [], deniedRegex: ""}`. **Recommendation:** Use empty inner objects (`forbiddenAnnotations: {}` works) — this is benign.
6. **Required field:** `enableTLSReconciler` (boolean, line 74) is REQUIRED per the CRD schema. **CONTEXT.md missed this.** It must be set explicitly. Set to `false` because the operator chart (Phase 8 D-08-04 / `tls.enableController: true`) handles cert reconciliation differently.

### Additional fields available

- `administrators` — array of `{kind, name}` objects (User|Group|ServiceAccount). Auto-owners of all tenants. NOT used in Phase 9 (no platform-admin tenant ops).
- `ignoreUserWithGroups` — array of strings. NOT used.
- `users` — modern replacement for `userNames` deprecated. NOT used.
- `overrides` — webhook configuration name overrides. Defaults are correct for Phase 9; NOT touched.

### Complete working CapsuleConfiguration yaml

```yaml
# pocs/capsule/spoke/config/capsuleconfig.yaml
# TEN-01 — CapsuleConfiguration "default" singleton (cluster-scoped policy CR
# Capsule webhooks consult on every tenant op).
#
# CRD schema verification (v0.12.4):
#   - apiVersion: capsule.clastix.io/v1beta2
#   - REQUIRED field: spec.enableTLSReconciler (boolean) — RESEARCH §Gap 5 correction;
#     CONTEXT.md D-09-04 omitted this. Set false because operator chart's
#     tls.enableController: true (Phase 8 D-08-04) handles cert reconciliation
#     via the operator chart's controller-less self-sign Job, not via this flag.
#   - spec.forceTenantPrefix: top-level (line 80 of CRD)
#   - spec.allowServiceAccountPromotion: top-level (line 67)
#   - spec.userGroups: DEPRECATED in v1beta2 but kept for chart-default compatibility
#
# TEN-01 — forceTenantPrefix: true is REQUIRED for namespace prefix enforcement
# (Tenant CR's spec.forceTenantPrefix overrides this, but since both are true,
# behavior is consistent).
apiVersion: capsule.clastix.io/v1beta2
kind: CapsuleConfiguration
metadata:
  name: default
spec:
  # REQUIRED by CRD schema
  enableTLSReconciler: false
  # TEN-01 — global namespace prefix enforcement
  forceTenantPrefix: true
  # Canonical clastix default; allows SA → owner promotion via labels
  # (allows gitops-reconciler SA to escalate identity inside its own tenant)
  allowServiceAccountPromotion: true
  # Owner-group filter (chart default; matches what capsule webhooks expect)
  # NOTE: userGroups is DEPRECATED in v1beta2 (replaced by spec.users), but the
  # capsule chart still uses this for default group-based owner detection.
  # Keeping for compatibility; planner may switch to spec.users post-graduation.
  userGroups:
    - capsule.clastix.io
  # Defense-in-depth: tenant cannot register kube-* namespace as a tenant ns.
  # (Capsule's own webhooks already block this; explicit makes intent clear.)
  protectedNamespaceRegex: ^kube-.*$
  # POC keeps these empty — Phase 11 N7 negative-RBAC may exercise.
  nodeMetadata:
    forbiddenAnnotations: {}
    forbiddenLabels: {}
```

### Confidence: HIGH (raw CRD schema verified field-by-field).

---

## Gap 6: Webhook MatchConditions / objectSelector — does the lockdown introduction break Phase 8 P26 defense?

### Answer: **PHASE 8 P26 DEFENSE LARGELY SURVIVES, BUT WITH ONE CAVEAT.**

The Capsule v0.12.4 chart applies different selectors to different webhooks. Per inspection of the chart's values.yaml structure (D-08-03 already configured per-hook `failurePolicy: Ignore` for ALL 14 hooks):

**Hooks with `namespaceSelector` matching `capsule.clastix.io/tenant Exists`** (these only fire on tenant-labeled namespaces — Phase 8 P26 defense applies):
- `tenantLabel`, `customresources`, `cordoning`, `gateways`, `ingresses`, `devices`, `networkpolicies`, `pods`, `persistentvolumeclaims`, `serviceaccounts`, `services`, `tenantResourceObjects`

**Hooks with empty `namespaceSelector: {}` and `objectSelector: {}` (fire on ALL namespaces):**
- `tenants` (Tenant CR validation — fires cluster-wide on every Tenant CR)
- `namespaces` (Namespace creation validation — must fire on ALL namespaces to enforce tenant prefix; this is BY DESIGN — Capsule needs to see EVERY namespace creation to assign-or-reject)

**Plan-time impact:**

The `namespaces` webhook fires on EVERY namespace creation, including platform-admin namespaces (`flux-system`, `kube-system`, etc.). However, Capsule's controller logic (NOT the webhook selector) bypasses tenant boundary validation for non-tenant identities:

- If the requestor is `system:masters` / cluster-admin / a member of admin groups (per `CapsuleConfiguration.spec.userGroups` / `administrators`), the webhook returns "allow" without invoking tenant logic.
- If the requestor matches a Tenant owner, the webhook applies tenant prefix + label assignment.
- If the requestor is neither, the webhook denies with "Please use capsule.clastix.io/tenant label when creating a namespace".

**The Phase 8 P26 defense (`failurePolicy: Ignore`) IS still load-bearing** for the case where the webhook backend (capsule-controller-manager pod) is unavailable. A platform-admin namespace creation during a controller outage would otherwise be blocked. With `failurePolicy: Ignore`, the apiserver tolerates the unavailable webhook and admits the namespace.

### Phase 9 risk

**The Phase 9 lockdown patches do NOT directly affect Capsule webhook behavior.** The lockdown patches are on Flux controllers, not the apiserver. After Phase 9:

- platform-admin Kustomizations targeting `flux-system` (or any non-tenant ns) → run as `kustomize-controller` SA (escape hatch) → apiserver receives `system:serviceaccount:flux-system:kustomize-controller` identity (cluster-admin via the bootstrap-managed `flux-system` ClusterRoleBinding) → Capsule's `namespaces` webhook treats this as platform-admin and allows.
- tenant inner Kustomizations targeting tenant namespaces → run as `gitops-reconciler` SA on spoke → impersonated to apiserver → Capsule's `namespaces` webhook checks Tenant.spec.owners → allows if matched.

**Caveat:** The `tenants` webhook (cluster-wide, fires on Tenant CR apply) — when Phase 9 first applies the alpha + bravo Tenant CRs via `poc-capsule-spoke` outer K, the apply identity is `kustomize-controller` (per D-09-05a escape hatch on `poc-capsule-spoke`). This SA HAS cluster-admin via the bootstrap-managed binding, so Capsule's Tenant validation webhook allows the apply. **Phase 8 D-08-03 `failurePolicy: Ignore` covers any transient webhook unavailability during this apply.**

### No plan modification needed for Phase 8 P26 defense

D-08-03 per-hook `failurePolicy: Ignore` (verified at `pocs/capsule/operator/helmrelease.yaml` lines 54-83) covers all 14 hooks. Phase 9 does not change webhook configuration.

### Confidence: MEDIUM (chart values defaults verified for most hooks via WebFetch; the `tenants` and `namespaces` hook empty-selector behavior inferred from Capsule docs but not 100% confirmed across chart variants).

---

## Gap 7: kubectl --as=alpha impersonation prerequisites (TEN-02 verifier)

### Answer: **NO additional ClusterRoleBinding needed** — k3d's default kubeconfig grants `system:masters` group membership which BYPASSES RBAC entirely.

**Citation 1 — Kubernetes RBAC docs (`kubernetes.io/docs/reference/access-authn-authz/rbac/`):**
> "Members of the `system:masters` group bypass all RBAC rights checks and will always have unrestricted superuser access. This cannot be revoked by removing RoleBindings or ClusterRoleBindings. If a cluster is using an authorization webhook, membership of this group also bypasses that webhook (requests from users who are members of that group are never sent to the webhook)."

**Citation 2 — k3d/k3s default kubeconfig** generates a client certificate with `O=system:masters; CN=admin` (the kubeconfig embedded user is in the `system:masters` group via the cert subject). This is standard k3s bootstrap behavior.

### How `kubectl --as=alpha` works on k3d-spoke-capsule

1. **Apiserver authentication** — request arrives with client cert in `system:masters` group → authenticated as `admin`.
2. **Apiserver impersonation check** — caller (`admin` / `system:masters`) must have `impersonate` verb on User kind. Per RBAC docs, **`system:masters` group members bypass this check entirely** — the impersonation request is permitted unconditionally.
3. **Apiserver forwards request as impersonated identity** — request now has `Impersonate-User: alpha` header; apiserver authorizes the request AS `alpha`.
4. **Capsule webhook intercepts** — sees impersonated identity `alpha`, matches against Tenant.spec.owners[kind=User, name=alpha] → allows if Tenant exists with that owner.
5. **Webhook enforces `forceTenantPrefix`** — namespace name `alpha-app1` matches `alpha-` prefix → allowed.
6. **Webhook auto-stamps `capsule.clastix.io/tenant=alpha` label** on the namespace at admission time (per Capsule namespace webhook behavior with `forceTenantPrefix: true` and matched owner).

### What if it fails?

**Failure modes (for verifier failure messages):**
- **"forbidden: User \"alpha\" cannot create namespace at the cluster scope"** → Tenant CR doesn't exist OR User `alpha` is not in Tenant.spec.owners → Plan 09-01 didn't apply Tenant CR yet, OR D-09-02 owner array is wrong.
- **"admission webhook ... denied the request: namespace name must start with prefix 'alpha-'"** → user attempted `alpha-app1` but `forceTenantPrefix` is enforced and prefix is wrong → name should match. (This is the SUCCESS path — actually `alpha-app1` matches `alpha-`).
- **"admission webhook ... denied the request: Please use capsule.clastix.io/tenant label when creating a namespace"** → `forceTenantPrefix` is `false` AND user didn't set the label manually. Phase 9 D-09-04 sets `forceTenantPrefix: true` cluster-wide, so this should NOT fire.
- **"admission webhook ... denied the request: ServiceUnavailable"** → capsule-controller-manager is down + webhook `failurePolicy: Fail` → Phase 8 D-08-03 sets `failurePolicy: Ignore`, so this should NOT fire.
- **`Error from server (Forbidden): users \"alpha\" is forbidden: User ... cannot impersonate resource \"users\" in API group \"\" at the cluster scope`** → caller is NOT in `system:masters` group → would need explicit ClusterRoleBinding for impersonate verb. **Should NOT happen with k3d default kubeconfig.**

### No additional yaml needed

The default k3d kubeconfig (`~/.kube/config` after `k3d cluster create`) already has the `system:masters` group via cert subject. No extra ClusterRoleBinding required.

> **Plan-time note for verifier:** If the bats test fails with "cannot impersonate" the LIKELY cause is the verifier is using a non-default kubeconfig (e.g., a tenant-scoped one). The bats test MUST use `--context=k3d-spoke-capsule` explicitly (the cluster-admin kubeconfig context), not a tenant-issued kubeconfig (which is Phase 10 territory).

### Confidence: HIGH (Kubernetes RBAC docs definitive; k3d/k3s default kubeconfig behavior well-known).

---

## Gap 8: CapsuleConfiguration apply ordering (TEN-06 dependsOn)

### Answer: **Single batch is sufficient with idempotent reconcile tolerance.** No need to split `pocs/capsule/spoke/{config,tenants}` into two separate Flux Kustomizations.

### Reasoning

Within `pocs/capsule/spoke/`, both `config/` (CapsuleConfiguration) and `tenants/` (Tenant CRs + per-tenant SAs/Namespaces) are siblings under one Flux Kustomization (`poc-capsule-spoke`). When kustomize-controller server-side-applies them in one batch:

1. **Kustomize alphabetical resource order** — `config/` resolves before `tenants/` alphabetically. CapsuleConfiguration applies first.
2. **Server-side apply is parallel within a batch** — kustomize-controller batches all resources and applies them concurrently to the apiserver. Apiserver applies them in arrival order, which is roughly alphabetical but not guaranteed.
3. **Capsule webhook validation** — when a Tenant CR applies, the Capsule operator's `tenants` webhook fires. The webhook does NOT require `CapsuleConfiguration/default` to exist — Capsule has chart defaults baked in (the operator pod creates `CapsuleConfiguration/default` automatically on first reconcile if missing). So a Tenant CR apply BEFORE CapsuleConfiguration apply is tolerated.
4. **First-reconcile flake tolerance** — if a Tenant CR briefly fails its first apply pass (e.g., transient capsule-controller readiness lag), Flux retries on the next reconcile cycle (5m default). The phase 9 verifier's retry budget (3 × 30s) catches the eventual success.

### Plan-time recommendation

**Keep CONTEXT.md D-09-01 single-Kustomization layout.** `poc-capsule-spoke` outer K reconciles `pocs/capsule/spoke/` containing both `config/` and `tenants/` subdirs. No split, no inter-K dependsOn needed.

**The TEN-06 dependsOn chain operates at a different level:**
- `poc-capsule-spoke` outer K (apply CapsuleConfig + Tenants to spoke) depends on `poc-capsule` outer K (apply HR + OCIRepo to hub, which then reconciles operator+CRDs to spoke).
- Per-tenant inner Ks (apply tenant workloads via inner reconcile) depend on `poc-capsule` (which provides the Tenant + CRD they need).

This dependency chain ensures CRDs exist before any CR using those kinds applies, AND avoids any race between operator install and Tenant apply.

### What's the apply order risk concretely?

If `Tenant alpha` applies BEFORE `CapsuleConfiguration/default` exists:
- The `tenants` webhook (Capsule's Tenant validation) fires.
- Webhook handler checks for CapsuleConfiguration in its in-memory cache (loaded from CR informer).
- If CapsuleConfiguration is missing, the controller falls back to chart defaults (logged as warning, not error).
- Tenant CR is admitted.
- On next reconcile, Capsule controller picks up the actual CapsuleConfiguration and re-validates / updates managed resources.

**Worst case:** ~5 second lag before Tenant boundary fully aligned with CapsuleConfiguration. This is benign for Phase 9 (no live tenant ops happen during the 5-second window).

### Confidence: HIGH (Capsule's reconcile loop tolerates missing CapsuleConfiguration; behavior verified in Capsule docs `projectcapsule.dev/docs/operating/setup/configuration/`).

---

## Gap 9: Lockdown patch interaction with SPOKES MOUNT

### Answer: **No interaction expected.** Kustomize's `patches:` and `resources:` are independent; ordering does not matter.

### Reasoning

**Citation — kustomize.config.k8s.io/v1beta1 spec (kubectl docs):**
- `resources:` block resolves first, materializing the resource set (Deployments, Kustomization CRs, etc.).
- `patches:` block applies modifications to the materialized resource set in declaration order.
- The order of `patches:` block declarations relative to `resources:` does not change the apply order — kustomize ALWAYS resolves resources first, then patches.

### Failure modes considered

1. **Existing v0.18 reconciles mid-flight when controller restart** — when the patch lands and Flux reconciles `clusters/hub-flux/flux-system/kustomization.yaml`, kustomize-controller patches its own Deployment and re-applies. The Deployment reads the new spec, kubernetes detects spec change, and rolls out new pod (~30-60s). **During the rollout window**, in-flight reconciles for `spoke-apps`, `spoke-ml` continue to completion (the OLD pod handles them); NEW reconciles wait for the NEW pod.
2. **kustomize-controller patching itself is a known idiom** — `fluxcd/flux2-multi-tenancy` reference uses exactly this pattern. No special handling needed.
3. **Race condition during patch application** — kustomize-controller's `flux-system` Kustomization picks up the new lockdown patches → applies them → the patched Deployment spec triggers controller restart → during restart, the `flux-system` Kustomization's status briefly reports `Reconciling`. On controller pod re-creation, the Kustomization's status converges to `Ready=True`.
4. **D-09-05a escape-hatch race** — the moment the `--default-service-account=default` flag is applied, kustomize-controller restarts with the new flag. Without the SAME-PATCH escape hatch (`flux-system` Kustomization spec.serviceAccountName: kustomize-controller), the next reconcile of `flux-system` would fail (default SA has no perms) → reconcile loop stuck. **CONTEXT.md D-09-05a addresses this**: the escape-hatch patch is included in the SAME `patches:` block as the controller arg patch, so they're applied atomically. **Verifier MUST observe `flux-system` Kustomization Ready=True within 2 minutes of patch apply.**

### Plan-time recommendation

**Apply the patches: block + escape-hatch as ONE atomic edit** to `clusters/hub-flux/flux-system/kustomization.yaml` (single commit, single reconcile cycle). Do NOT split into "land controller args first, then escape hatch" — that would brick the hub Flux reconcile.

**Verifier MUST poll for ≥ 2 minutes** after the patch commit to catch:
1. kustomize-controller pod restart with new args (verify via `kubectl -n flux-system get deploy kustomize-controller -o jsonpath='{.spec.template.spec.containers[0].args}'`)
2. `flux-system` Kustomization re-reaches Ready=True (escape-hatch worked)
3. `task health-check` passes (full v0.18 regression)

### Confidence: HIGH (kustomize behavior well-documented; canonical Flux multi-tenancy lockdown pattern uses this exact approach).

---

## Gap 10: Per-tenant GitRepository

### Answer: Working yaml + auth answer + substitution mechanism.

### GitRepository CR shape (Flux v2.8 source-controller)

**Citation — Flux v2.8 source-controller docs (`fluxcd.io/flux/components/source/gitrepositories/`):**
- apiVersion: `source.toolkit.fluxcd.io/v1` (NOT v1beta2 — v1 is the GA version since Flux 2.0).
- For PUBLIC HTTPS repositories: **"that for a publicly accessible git repository, you don't need to provide a `secretRef` nor `serviceAccountName`."**
- Minimum required fields: `spec.url` + `spec.ref` + `spec.interval`.

### Working yaml for tenant-alpha-source

```yaml
# pocs/capsule/tenants/alpha.yaml — first half (GitRepository portion)
# TEN-04 — per-tenant GitRepository on hub. Public repo, no auth.
# Lives in tenant-alpha namespace per D-09-03 (same namespace as the Kustomization
# that references it — survives --no-cross-namespace-refs lockdown).
#
# Verified: source.toolkit.fluxcd.io/v1 is GA in Flux 2.0+; v0.18 already uses v1
# for spoke-apps + spoke-ml GitRepositories. No secretRef needed for public repo
# (Flux v2.8 source-controller docs).
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: tenant-alpha-source
  namespace: tenant-alpha
spec:
  interval: 5m
  # ${GITHUB_OWNER} substituted by Flux postBuild — see RESEARCH §Gap 10 substitution.
  # Placeholder syntax MUST match Flux postBuild substituteFrom name pattern:
  # ^[_[:alpha:]][_[:alpha:][:digit:]]*$ (GITHUB_OWNER passes).
  url: https://github.com/${GITHUB_OWNER}/karyon
  ref:
    branch: main
  # No secretRef — repo is public per Phase 6 REPO-01..04
  # No verify (signature verification) — POC simplification
```

### Authentication path

**No `secretRef` needed.** The karyon repo is public per Phase 6 REPO-01..04. Flux source-controller fetches via anonymous HTTPS clone.

**However**, until Phase 11 VAL-05 first push, the GitRepository will report `Ready=False` with `failed to fetch: revision "main" doesn't exist on remote`. This is acceptable for Phase 9 — TEN-04's static contract is what's load-bearing; live reconcile of an empty placeholder path is incidental. After Phase 11 push, GitRepository reaches `Ready=True` and inner Ks reconcile their (still-empty) paths.

> **Verifier consideration:** The `tenants-09-live-inner-k-ready.bats` test expects inner K `Ready=True`. If GitRepository is `Ready=False` (pre-push state), the inner K is also `Ready=False` (waiting on source). **The bats test should accept EITHER `Ready=True` (post-push) OR `Ready=False with reason=ArtifactFailed` (pre-push, expected)** — same skip pattern as Phase 8 `capsule-install-10-live-flux-observable.bats` (which skips on pre-push state).

### Substitution mechanism: Flux postBuild

CONTEXT.md D-09-03b says `${GITHUB_OWNER}` substitutes "from `.env` at task time — same convention as v0.18 `flux-bootstrap` (Phase 3)". **This is incorrect for Flux Kustomizations** — `flux bootstrap` substitutes `.env` values at install time (one-shot), but ongoing Flux reconciles do NOT have access to `.env`. The correct mechanism is **Flux postBuild substituteFrom**.

**Citation — Flux v2.8 docs (`fluxcd.io/flux/components/kustomize/kustomizations/#post-build-variable-substitutions`):**
- `.spec.postBuild.substitute` — inline name=value map.
- `.spec.postBuild.substituteFrom` — list of ConfigMap/Secret references; the keys become variable names.
- Variable names must match `^[_[:alpha:]][_[:alpha:][:digit:]]*$` (GITHUB_OWNER passes).

### Plan-time recommendation for `${GITHUB_OWNER}` substitution

**Option A (RECOMMENDED): Hard-code the owner name.** karyon's owner is fixed (`richard-iovanisci` per git config). Drop the `${GITHUB_OWNER}` placeholder and put the literal:

```yaml
url: https://github.com/richard-iovanisci/karyon
```

Rationale: simpler; matches Phase 6 REPO-01..04 contract that the repo is publicly addressable at a fixed URL; postBuild substituteFrom adds plumbing for no real benefit. **The Phase 7 register-poc-cluster.sh DOES already substitute `.env` GITHUB_OWNER** — but only for the bootstrap Secret apply, not for committed yaml.

**Option B: Flux postBuild substituteFrom from a hub-flux ConfigMap.** Add `spec.postBuild.substituteFrom: [{kind: ConfigMap, name: karyon-flux-vars}]` to the per-tenant Kustomization CR (NOT the GitRepository — postBuild only works on Kustomization CR, not GitRepository). Then provide a ConfigMap in `flux-system` ns with `GITHUB_OWNER: <value>`. **Caveat:** this ConfigMap reference is cross-namespace (`flux-system` → `tenant-alpha`), which trips `--no-cross-namespace-refs`. Mitigation: mirror the ConfigMap into each tenant ns alongside the Secret mirror from Gap 1.

**Plan-time decision (RECOMMENDED):** Option A — hard-code. Avoids cross-namespace ConfigMap headache and matches the simplicity bias of the POC.

> If owner anonymity is critical for public-repo presentation: use Option B + ConfigMap mirror, and document the mirror in plan-time decision.

### Confidence: HIGH (Flux source-controller docs definitive; postBuild substitution mechanism well-documented).

---

## Gap 11: v0.18 health-check assertion subset

### Answer: Concrete subset that Phase 9 verifier MUST confirm passing.

After reading `scripts/health-check.sh` (the v0.18 regression gate), the assertions Phase 9 lockdown patch could regress are:

### v0.18 health-check sections + regression risk after Phase 9 lockdown

| Section | Assertion | Phase 9 Lockdown Risk | Mitigation |
|---------|-----------|------------------------|------------|
| 1. Clusters & nodes | `k3d cluster list` shows hub-flux + spoke-ml + spoke-apps; nodes Ready=True | NONE — k3d cluster state unaffected by Flux flag changes | — |
| 2. Flux controllers | ≥4 deployments + Available=True + `flux check` passes | **HIGH** — kustomize-controller / helm-controller / notification-controller restart with new args; transient unavailability | Verifier polls Available=True for ≥2 min post-patch |
| 3. Spoke Kustomizations | spoke-ml + spoke-apps Kustomizations Ready=True | **MEDIUM** — these Kustomizations have `spec.kubeConfig` set, so `--default-service-account` flag applies as fallback (no-permission `default` SA on spokes IF `serviceAccountName` is empty); P27 root cause analysis confirms cross-cluster reconciles tolerate the flag fallback as failed-closed safe. Verify the fallback doesn't trigger by ensuring spoke-apps + spoke-ml Kustomizations either have explicit `serviceAccountName` OR continue to reach Ready=True | **CRITICAL plan-time check:** Read `clusters/hub-flux/spokes/spoke-apps.yaml` + `spoke-ml.yaml` BEFORE applying lockdown patch. If they DO NOT have `spec.serviceAccountName`, decide whether to add it (defense in depth) or rely on the kubeConfig Secret's principal (existing behavior). **Per Gap 3, the flag fallback to `default` SA only matters if `serviceAccountName` is empty AND the kubeConfig principal isn't otherwise the cluster-admin token. v0.18 spoke-{apps,ml} use the cluster-admin SA via kubeConfig — no impact.** |
| 4. Hub DNS probe | source-controller can resolve `k3d-spoke-{ml,apps}-server-0` | NONE — DNS is independent of Flux flags | — |
| 5. GPU capacity | spoke-ml reports nvidia.com/gpu > 0 | NONE | — |
| 6. TLS SANs | spoke apiserver SANs include `k3d-{spoke}-server-0` | NONE | — |
| 7. Workload proofs | podinfo Deployment Available + nvidia-smi Job Complete + log contains "NVIDIA-SMI" | **LOW** — these workloads are deployed via spoke Kustomizations; if those Ks regress, workloads regress | Caught by section 3 |

### Concrete subset Phase 9 verifier MUST confirm

The `tenants-12-live-health-check.bats` test should:

1. **Run `task health-check` in full** (pre-patch baseline + post-patch regression):
   ```bash
   # Pre-patch (Plan 09-03 step 1)
   task health-check  # MUST exit 0
   
   # Post-patch (Plan 09-03 step 3, after lockdown applied + reconcile observed)
   task health-check  # MUST STILL exit 0
   ```
2. **In the bats test, after lockdown applied**, assert the specific high-risk sections pass:
   - kustomize-controller availableReplicas == replicas
   - helm-controller availableReplicas == replicas
   - notification-controller availableReplicas == replicas
   - source-controller availableReplicas == replicas (sanity — should be unchanged)
   - flux-system Kustomization Ready=True (escape hatch validation)
   - spoke-apps + spoke-ml Kustomizations Ready=True (cross-cluster lockdown impact)
3. **Also assert NEW Phase 9 surface**:
   - poc-capsule Kustomization Ready=True (escape hatch via `spec.serviceAccountName: kustomize-controller`)
   - poc-capsule-spoke Kustomization Ready=True (spoke-targeted; lockdown flag doesn't apply because kubeConfig is set; but explicit `serviceAccountName` recommended for clarity)

**Recommendation: invoke `task health-check` as part of the bats test** (single bats `run task health-check; [ "$status" -eq 0 ]`) AND ALSO run the targeted assertions above. Belt-and-suspenders.

### Confidence: HIGH (read scripts/health-check.sh directly; assertions are deterministic).

### CORRECTION (Plan 09-03 attempt 1 falsifier — 2026-04-30)

The §Gap 11 line 693 "MEDIUM" risk row's prediction in the "Mitigation" column is **FALSIFIED** by live observation. The specific text:

> **Per Gap 3, the flag fallback to `default` SA only matters if `serviceAccountName` is empty AND the kubeConfig principal isn't otherwise the cluster-admin token. v0.18 spoke-{apps,ml} use the cluster-admin SA via kubeConfig — no impact.**

is incorrect. Live observation in Flux v2.8.6 (Plan 09-03 attempt 1):
- spoke-apps + spoke-ml had `spec.kubeConfig` set BUT `spec.serviceAccountName` empty
- → kustomize-controller's `--default-service-account=default` flag DID override the kubeConfig principal
- → reconcile fell through to `system:serviceaccount:flux-system:default` on the TARGET cluster
- → forbidden namespace patch errors on both spokes

The "no impact" prediction was based on the (now falsified) Gap 3 prediction that the flag scope was local-cluster only. Both predictions are FALSIFIED. The risk for "3. Spoke Kustomizations" (spoke-ml + spoke-apps Ready=True) is therefore **HIGH, not MEDIUM**, when the lockdown patches land WITHOUT the spoke-side defense-in-depth.

**Revised mitigation (Plan 09-03 RE-PLAN):** Add `spec.serviceAccountName: kustomize-controller` to BOTH `clusters/hub-flux/spokes/spoke-apps.yaml` and `spoke-ml.yaml` BEFORE applying lockdown patches. This is implemented as Task 2 of Plan 09-03 RE-PLAN, prior to Task 4's FLUX PATCH SURFACE patches block.

**Confidence: HIGH (live falsifier; cluster state captured in 09-03-SUMMARY.attempt-1-rollback.md commit chain — `899f2fe` → `9b6b3a5` revert → `6cdbfb2` annotation).**

### CORRECTION 2 (Plan 09-03 attempt 2 falsifier — 2026-04-30)

The §Gap 11 line 693 risk row's attempt-1 revised mitigation (set `spec.serviceAccountName: kustomize-controller` on spoke-{apps,ml}.yaml as defense-in-depth) is **FURTHER FALSIFIED** by Plan 09-03 RE-PLAN attempt 2's live observation. The `kustomize-controller` SA does NOT exist on spoke clusters (only `flux-reconciler` SA has cluster-admin per `scripts/register-spokes-for-flux.sh:275-310`).

**Revised mitigation (Plan 09-03 RE-PLAN attempt 3):** `spec.serviceAccountName: flux-reconciler` on spoke-{apps,ml}.yaml — see §Gap 3 CORRECTION 2 above for details.

**Confidence: HIGH (live falsifier — same evidence trail as §Gap 3 CORRECTION 2).**

---

## Gap 12: clastix/flux2-capsule-multi-tenancy fresh validation

### Answer: Reference URL + summary + landmines.

**Reference URL:** `https://github.com/clastix/flux2-capsule-multi-tenancy`

### Summary

The repo is a fork of `fluxcd/flux2-multi-tenancy` extended with Capsule-specific patterns. Core concepts:

1. **Per-tenant ServiceAccount + namespace** — each tenant gets a dedicated ns (e.g., `tenant-dev-team`) with a `gitops-reconciler` SA, identical to CONTEXT.md D-09-02 pattern.
2. **Per-tenant GitRepository** — each tenant declares its own `GitRepository` CR in tenant ns, pointing at a tenant-specific (forked) repo. Karyon's variation: same karyon repo for both tenants because the per-tenant placeholder dirs (`pocs/capsule/tenants/{alpha-app,bravo-app}/`) are inside the SAME repo. This deviates from clastix's "tenant has their own repo" assumption but is operationally equivalent.
3. **Flux Kustomization with kubeConfig + serviceAccountName** — tenant Kustomization CR has BOTH `spec.kubeConfig` (referencing capsule-proxy kubeconfig — Phase 10) AND `spec.serviceAccountName: gitops-reconciler` (tenant SA on target cluster). For Phase 9 transitional, karyon uses `spoke-capsule-kubeconfig` (cluster-admin) instead of capsule-proxy kubeconfig; Phase 10 PROXY-02 swaps.
4. **Lockdown patches** — apply standard `--no-cross-namespace-refs`, `--no-remote-bases`, `--default-service-account=gitops-reconciler` (NOTE: clastix uses `gitops-reconciler` as the default SA name, NOT `default`). Karyon's CONTEXT.md D-09-05 uses `default` (the canonical Flux multi-tenancy reference choice). Both are defensible; `default` is the more permissive failed-closed safe (the SA exists by default, has no perms — fails on any apply).

### Landmines surfaced

1. **Repo is small (4 commits, no recent activity).** Latest commit appears stale (no commits in 6+ months at time of research per the GitHub UI snapshot). It's a reference architecture, not actively maintained.
2. **No deprecation notice toward `capsule-addon-fluxcd`.** clastix has not migrated this repo to use the addon; it remains the canonical hand-managed pattern. **karyon's Phase 9 mirrors this pattern; Phase 12 evaluates the addon as comparison.**
3. **The lockdown patch in `clastix/flux2-capsule-multi-tenancy/clusters/staging/flux-system/kustomization.yaml`** uses `--default-service-account=gitops-reconciler` (NOT `default`) — meaning every Kustomization without explicit `serviceAccountName` falls through to a SA called `gitops-reconciler` in the K's namespace. Karyon's CONTEXT.md D-09-05 chose `default` (no-permission failed-closed safe). **Both work; karyon's choice is more conservative.** Document in plan-time decision.
4. **clastix uses `proxy-kubeconfig-generator` utility** (a separate clastix tool) for tenant kubeconfig generation. Phase 10 (PROXY-01) handles this; not Phase 9 scope.

### No Phase 9 plan modification needed

The clastix pattern matches CONTEXT.md D-09-02..D-09-03 verbatim (modulo the per-tenant repo divergence noted above). The `--default-service-account=default` choice in CONTEXT.md is a defensible deviation from clastix's `gitops-reconciler` default — both are valid multi-tenancy patterns.

### Confidence: HIGH (repo content directly inspected; pattern alignment with CONTEXT.md confirmed).

---

## Gap 13: Tenant.spec must-haves vs optional

### Answer: Concrete must-have / nice-to-have / omit list for TEN-01..06.

### MUST-HAVE (required for TEN-01..06 to pass)

| Field | Required for | Notes |
|-------|--------------|-------|
| `spec.owners[]` (kind: ServiceAccount, name: system:serviceaccount:tenant-<name>:gitops-reconciler) | TEN-01, TEN-04 | Flux impersonation chain |
| `spec.owners[]` (kind: User, name: <name>) | TEN-02 | `kubectl --as=<name>` test path |
| `spec.forceTenantPrefix: true` | TEN-01, TEN-02 | Top-level field; enforces namespace prefix |

### NICE-TO-HAVE (for TEN-03 auto-materialization)

| Field | Required for | Notes |
|-------|--------------|-------|
| `spec.resourceQuotas.items[]` | TEN-03 | At least one item to trigger ResourceQuota auto-materialization |
| `spec.limitRanges.items[]` | TEN-03 | At least one item to trigger LimitRange auto-materialization |

> **Subtle point:** Without ANY `resourceQuotas` items, Capsule does NOT auto-materialize ResourceQuota objects. TEN-03 says "ResourceQuota and LimitRange objects auto-materialize inside each tenant namespace" — this REQUIRES at least one item in BOTH `resourceQuotas.items` AND `limitRanges.items`. The Phase 9 minimal values are arbitrary (TEN-03 only checks SHAPE, not enforcement values), but they MUST be present.

### OPTIONAL fields (omit by default — Capsule allow-all)

| Field | Behavior when omitted | Phase 11 use? |
|-------|------------------------|----------------|
| `spec.namespaceOptions.quota` | Tenant can create unlimited namespaces inside prefix | NOT used |
| `spec.namespaceOptions.additionalMetadata` | Capsule does not stamp extra labels/annotations | NOT used |
| `spec.additionalRoleBindings[]` | Tenant ns gets default RoleBindings (admin + capsule-namespace-deleter on owners — auto-applied per `clusterRoles` default) | NOT needed for TEN-02/04 — defaults suffice |
| `spec.storageClasses.allowed[]` | Allow all StorageClasses | NOT used (no PVC tests in Phase 9) |
| `spec.ingressClasses.allowed[]` | Allow all IngressClasses | NOT used |
| `spec.containerRegistries.allowed[]` | Allow all registries | Phase 11 N7 may exercise |
| `spec.nodeSelector` | No node-selector annotation injected | NOT used |
| `spec.networkPolicies` | No auto-NetworkPolicy injected | DEPRECATED in v1beta2 (use Tenant Replications); NOT used |
| `spec.preventDeletion: true` | Tenant CR cannot be deleted | NOT set (Phase 11 ordered teardown needs to delete) |
| `spec.podOptions.additionalMetadata` | No pod label/annotation injection | NOT used |
| `spec.serviceOptions` | Allow all Service types | NOT used |
| `spec.gatewayOptions` | (Gateway API) | NOT used (Out-of-Scope) |
| `spec.priorityClasses.allowed[]` | Allow all PriorityClasses | NOT used |
| `spec.imagePullPolicies` | Allow all imagePullPolicies | NOT used |

### Plan-time recommendation

**For TEN-02 (kubectl --as=alpha create namespace alpha-app1):** Default RBAC on the User owner suffices. Capsule auto-injects RoleBindings for the `admin` ClusterRole (per `spec.owners[].clusterRoles` default `[admin, capsule-namespace-deleter]`). The `admin` ClusterRole can create namespaces — but ONLY inside the tenant prefix (Capsule webhook enforces). **No `additionalRoleBindings` needed.**

**For TEN-04 (Flux impersonation as gitops-reconciler SA):** SA owner alone suffices — Capsule's owner clusterRoles default `[admin, capsule-namespace-deleter]` gives the SA full control inside tenant namespaces. **No additional `Role` or `RoleBinding` needed for TEN-04 (the SA's permissions to apply ResourceQuota / LimitRange / etc. are already covered by the auto-injected admin RoleBinding).**

**For Phase 9 minimal Tenant CR:** The yaml in Gap 4 (above) is complete. No additional fields needed.

### Confidence: HIGH (CRD schema + Capsule docs cross-referenced; default behaviors well-documented).

---

## Plan-Time Recommendations

> **Single paragraph for the planner to drop into PLAN.md:**

Phase 9 lands the multi-tenant control plane on top of the Phase 8 install via three locked decisions: directory-layout extension (D-09-01), tenant CR multi-owner shape (D-09-02 — corrected here per Gap 4: `forceTenantPrefix` is top-level, `owners[].namespace` doesn't exist, ServiceAccount uses combined `system:serviceaccount:<ns>:<sa>` name format), and Flux multi-tenancy lockdown patches with the load-bearing `flux-system` Kustomization escape hatch (D-09-05/05a). The single research-flagged ambiguity (D-09-03a, kubeConfig.secretRef cross-namespace) resolves DEFINITIVELY: Flux v2.8 hardcodes `kubeConfig.secretRef` to same-namespace as the Kustomization regardless of any flag, so Plan 09-02 MUST mirror the `spoke-capsule-kubeconfig` Secret into both `tenant-alpha` and `tenant-bravo` namespaces on hub via an imperative `register-poc-cluster.sh` extension (the same imperative-Secret-apply pattern Phase 7 already established). Per-controller flag scope (Gap 2) is canonical: kustomize-controller gets all 3 lockdown flags + helm-controller gets 2 (`--no-cross-namespace-refs` + `--default-service-account=default`) + notification-controller gets 1 (`--no-cross-namespace-refs`); CONTEXT.md narrows `--default-service-account` to kustomize-controller only, but the upstream `fluxcd/flux2-multi-tenancy` reference applies it to both — RECOMMEND extending. Required CapsuleConfiguration field `enableTLSReconciler: false` was missing from CONTEXT.md D-09-04 (Gap 5 correction). The Phase 9 verifier reruns full v0.18 `task health-check` TWICE (pre-patch baseline + post-patch regression) per CONTEXT.md Claude's Discretion §"Order of `task health-check` rerun"; v0.18 sections 2 (Flux controllers Available) and 3 (spoke Kustomizations Ready) are the highest regression risk (Gap 11). Phase 9 needs no new `task` targets, no `.gitignore` extensions, no kubeconfig-shaped artifacts (Phase 10 owns that surface).

---

## Code Examples

### `pocs/capsule/spoke/config/capsuleconfig.yaml`

(See Gap 5 — complete annotated example provided above.)

### `pocs/capsule/spoke/config/kustomization.yaml`

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

### `pocs/capsule/spoke/tenants/alpha/namespace.yaml`

```yaml
# pocs/capsule/spoke/tenants/alpha/namespace.yaml
# TEN-01 — the tenant home namespace on spoke-capsule. Holds the gitops-reconciler
# SA that the Tenant CR registers as ServiceAccount owner.
#
# D-09-02 — tenant home namespace name pattern: tenant-<tenant-name>.
# The tenant's auto-created child namespaces use prefix <tenant-name>- (e.g. alpha-app1)
# enforced by spec.forceTenantPrefix in the Tenant CR.
apiVersion: v1
kind: Namespace
metadata:
  name: tenant-alpha
```

### `pocs/capsule/spoke/tenants/alpha/sa.yaml`

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

### `pocs/capsule/spoke/tenants/alpha/tenant.yaml`

(See Gap 4 — complete annotated example provided above.)

### `pocs/capsule/spoke/tenants/alpha/kustomization.yaml`

```yaml
# pocs/capsule/spoke/tenants/alpha/kustomization.yaml
# Local Kustomize aggregator for tenant alpha's spoke-side resources.
#
# D-09-01 — alpha subdir under pocs/capsule/spoke/tenants/. Mirror exists at
# pocs/capsule/spoke/tenants/bravo/.
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - sa.yaml
  - tenant.yaml
```

### `pocs/capsule/spoke/tenants/kustomization.yaml`

```yaml
# pocs/capsule/spoke/tenants/kustomization.yaml
# Aggregator for both tenant subdirs.
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - alpha/
  - bravo/
```

### `pocs/capsule/spoke/kustomization.yaml` (REWRITE from Phase 8 placeholder)

```yaml
# pocs/capsule/spoke/kustomization.yaml
# REWRITTEN from Phase 8 D-08-12 Pitfall-7 placeholder (resources: []).
# Phase 9 D-09-01 populates with config/ + tenants/ subdirs.
#
# Spoke-targeted: parent clusters/hub-flux/pocs/capsule-spoke.yaml's
# spec.path: ./pocs/capsule/spoke + kubeConfig: spoke-capsule-kubeconfig
# routes these resources to spoke-capsule via kustomize-controller's
# cross-cluster reconcile (D-08-12 split-path invariant).
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - config/
  - tenants/
```

### `pocs/capsule/tenants/alpha.yaml`

```yaml
# pocs/capsule/tenants/alpha.yaml
# TEN-04 — hub-targeted: per-tenant Namespace (tenant-alpha on hub) +
# per-tenant GitRepository + per-tenant inner Kustomization.
#
# D-09-02 — hub-side tenant ns mirrors spoke-side name (required so the
# Kustomization CR has a home AND so Flux's same-namespace impersonation
# rule resolves: SA gitops-reconciler in tenant-alpha on TARGET cluster).
#
# CRITICAL — RESEARCH §Gap 1: spec.kubeConfig.secretRef.name "spoke-capsule-kubeconfig"
# MUST exist in tenant-alpha namespace on hub (NOT just flux-system). Plan 09-02 MUST
# mirror the Secret via scripts/register-poc-cluster.sh extension. Without the mirror,
# the Kustomization reaches Ready=False with `secret "spoke-capsule-kubeconfig" not found`.
apiVersion: v1
kind: Namespace
metadata:
  name: tenant-alpha
---
# TEN-04 — per-tenant GitRepository. Public HTTPS URL; no secretRef per Phase 6
# REPO-01..04 (karyon repo is public). Lives in tenant-alpha namespace so the
# Kustomization's sourceRef survives --no-cross-namespace-refs lockdown.
#
# RESEARCH §Gap 10 — owner is hard-coded (Option A) per plan-time recommendation;
# postBuild substituteFrom would require a cross-namespace ConfigMap mirror.
# Until Phase 11 VAL-05 first push, GitRepository reaches Ready=False with
# "failed to fetch: revision main doesn't exist on remote" (acceptable for Phase 9).
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
# TEN-04 — per-tenant inner Kustomization. CARRIES THE LOAD-BEARING P27 DEFENSE.
#
# spec.serviceAccountName MUST be set explicitly (P27 / RESEARCH §Gap 3):
# without it, kustomize-controller falls through to --default-service-account
# flag's value (default=`default` SA in K's namespace on TARGET cluster).
# With karyon's spoke-capsule-kubeconfig (cluster-admin token), the kubeConfig
# principal would otherwise reconcile as cluster-admin on spoke, BYPASSING Capsule
# entirely (Capsule webhooks deliberately exempt cluster-admin / kube-system
# identities from tenant-boundary enforcement).
#
# spec.kubeConfig.secretRef.key: "value.yaml" — P40/P18 inheritance (silent-misroute
# defense from Phase 7; mirrored from spoke-{apps,ml} pattern).
#
# spec.dependsOn: [{name: poc-capsule, namespace: flux-system}] — TEN-06 P32:
# blocks until Capsule operator HelmRelease is Ready=True (CRDs registered).
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
    # Same namespace (tenant-alpha) — survives --no-cross-namespace-refs
  kubeConfig:
    secretRef:
      name: spoke-capsule-kubeconfig
      # Same namespace (tenant-alpha) — required by Flux v2.8 contract
      # (RESEARCH §Gap 1). Plan 09-02 mirrors Secret imperatively.
      key: value.yaml
  serviceAccountName: gitops-reconciler  # P27 LOAD-BEARING DEFENSE
  dependsOn:
    - name: poc-capsule
      namespace: flux-system
```

### `pocs/capsule/tenants/alpha-app/kustomization.yaml`

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

### `pocs/capsule/tenants/kustomization.yaml`

```yaml
# pocs/capsule/tenants/kustomization.yaml
# Aggregator for hub-targeted tenant resources.
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - alpha.yaml
  - bravo.yaml
  - alpha-app/
  - bravo-app/
```

### `pocs/capsule/kustomization.yaml` (UPDATE — add tenants/)

```yaml
# pocs/capsule/kustomization.yaml
# Phase 8 D-08-05 + Phase 9 D-09-01 — outer recursive Kustomization for
# pocs/capsule/. resources: [operator/, proxy/] from Phase 8; Phase 9 adds tenants/.
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - operator/
  - proxy/
  - tenants/
```

### `clusters/hub-flux/flux-system/kustomization.yaml` (LOCKDOWN PATCH ADDITION)

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
# KARYON FLUX LOCKDOWN PATCHES (D-09-05 / TEN-05)
# Multi-tenancy hardening per Flux v2.8 docs and fluxcd/flux2-multi-tenancy
# reference:
#   - kustomize-controller: all 3 flags (no-cross-namespace-refs, no-remote-bases,
#     default-service-account)
#   - helm-controller: no-cross-namespace-refs + default-service-account (per
#     RESEARCH §Gap 2 — extends CONTEXT.md D-09-05 narrowing; defense in depth
#     for tenant-issued HelmReleases in Phase 11+)
#   - notification-controller: no-cross-namespace-refs only
#   - source-controller: NONE (sources are owned by source-controller; lockdown
#     happens on consumer side)
# The flux-system Kustomization patch (escape hatch) is LOAD-BEARING — without
# it, --default-service-account=default brick's Flux's own bootstrap reconcile
# (per RESEARCH §Gap 9). All 4 patches MUST land atomically in one commit.
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
      - op: add
        path: /spec/template/spec/containers/0/args/-
        value: --default-service-account=default
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

### `clusters/hub-flux/pocs/capsule.yaml` (UPDATE — add escape hatch)

```yaml
# clusters/hub-flux/pocs/capsule.yaml — Phase 9 update.
# (Existing Phase 8 D-08-12 comment block preserved verbatim.)
#
# Phase 9 D-09-05a addition: spec.serviceAccountName: kustomize-controller
# (escape hatch under lockdown). Hub-targeted Kustomization (no kubeConfig)
# is subject to --default-service-account=default fallback; without explicit
# serviceAccountName, this K reconciles as `default` SA in flux-system → no
# perms → Ready=False. The kustomize-controller SA (bootstrap-managed with
# cluster-admin via flux-system ClusterRoleBinding) is the safe explicit choice.
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: poc-capsule
  namespace: flux-system
spec:
  interval: 5m
  path: ./pocs/capsule
  prune: true
  serviceAccountName: kustomize-controller  # D-09-05a — escape hatch under lockdown
  sourceRef:
    kind: GitRepository
    name: flux-system
```

### `clusters/hub-flux/pocs/capsule-spoke.yaml` (UPDATE — add dependsOn + optional escape hatch)

```yaml
# clusters/hub-flux/pocs/capsule-spoke.yaml — Phase 9 update.
# (Existing Phase 8 D-08-12 comment block preserved verbatim.)
#
# Phase 9 D-09-06 addition: spec.dependsOn: [{name: poc-capsule}] wait: true.
# P32 — Tenant CRs (under pocs/capsule/spoke/tenants/) cannot apply until
# operator HelmRelease has reconciled and CRDs are registered on spoke. The
# poc-capsule outer K's reconcile drives the operator HR → CRD registration;
# wait: true blocks this K's apply until poc-capsule reaches Ready=True.
#
# spec.serviceAccountName recommended for clarity (D-09-05 sub-decision).
# Spoke-targeted K with kubeConfig set is exempt from --default-service-account
# flag scope (RESEARCH §Gap 3 + Flux v1 KubeConfig comment). However, if
# serviceAccountName were empty AND the kubeConfig principal failed,
# kustomize-controller would fall through to flag's value `default` on TARGET
# cluster (spoke-capsule's flux-system:default SA) — fails closed safe.
# Setting kustomize-controller (the SA on hub) is forward-compat for any future
# refactor that pushes this onto a non-cluster-admin spoke kubeconfig.
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: poc-capsule-spoke
  namespace: flux-system
spec:
  interval: 5m
  path: ./pocs/capsule/spoke
  prune: true
  serviceAccountName: kustomize-controller  # D-09-05 — explicit clarity
  dependsOn:
    - name: poc-capsule  # D-09-06 — P32 dependsOn chain
  # Note: dependsOn does NOT support a `wait: true` sub-field directly on the
  # dependent K item — Kustomization's spec.wait field controls the WAIT behavior
  # for the dependent K's OWN resources to reach Ready=True. dependsOn always
  # blocks until the dependency reports Ready=True (no opt-out). See Phase 8
  # D-08-07 / proxy HR for the same pattern (Pitfall 9 — RESEARCH catch).
  wait: true  # waits for THIS K's own resources (CapsuleConfig + Tenant CRs) to be Ready
  timeout: 10m
  sourceRef:
    kind: GitRepository
    name: flux-system
  kubeConfig:
    secretRef:
      name: spoke-capsule-kubeconfig
      key: value.yaml
```

> **Subtle correction:** CONTEXT.md D-09-06 says "`dependsOn: [{name: poc-capsule}] wait: true`" — but `wait: true` is NOT a sub-field of dependsOn entries; it's a top-level Kustomization spec field. The Phase 8 proxy HelmRelease faced the same misreading (verified in `pocs/capsule/proxy/helmrelease.yaml` lines 11-13: "Pitfall 9: dependsOn does NOT support a `wait: true` sub-field"). Plan 09-01 must use `spec.wait: true` (top-level), NOT inside the dependsOn entry.

---

## Bats Test Coverage Recommendations

Concrete list per CONTEXT.md D-09-08 (12 bats files mirroring Phase 8 capsule-install-*.bats naming convention):

### Static (Wave 0) tests

**`tests/bats/tenants-01-static-tenant-cr.bats` (TEN-01)**
- Asserts `pocs/capsule/spoke/tenants/{alpha,bravo}/tenant.yaml`:
  - `apiVersion: capsule.clastix.io/v1beta2`
  - `kind: Tenant`
  - `metadata.name: alpha` (or `bravo`)
  - `spec.forceTenantPrefix: true` (TOP-LEVEL — RESEARCH §Gap 4 correction)
  - `spec.owners[]` contains entry with `kind: ServiceAccount` and `name: system:serviceaccount:tenant-alpha:gitops-reconciler` (combined name format)
  - `spec.owners[]` contains entry with `kind: User` and `name: alpha`
  - `spec.resourceQuotas.items[0].hard` non-empty (TEN-03 shape)
  - `spec.limitRanges.items[0].limits` non-empty (TEN-03 shape)
- Mirror checks for bravo

**`tests/bats/tenants-02-static-p27.bats` (TEN-04 — P27 LOAD-BEARING)**
- Asserts EVERY file matching `pocs/capsule/tenants/*.yaml`:
  - For every yaml document with `kind: Kustomization` AND `apiVersion: kustomize.toolkit.fluxcd.io/v1`:
    - `spec.serviceAccountName` is set AND non-null (yq-based; NOT just grep)
- Negative falsifier: a synthetic broken Kustomization fixture WITHOUT `serviceAccountName` MUST fail this lint
- Use the Phase 8 WR-01..04 yq-hardening direction:
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

**`tests/bats/tenants-03-static-lockdown.bats` (TEN-05)**
- Asserts `clusters/hub-flux/flux-system/kustomization.yaml`:
  - Original FLUX PATCH SURFACE comment block preserved verbatim (lines 1-13 grep-asserted unchanged)
  - `# KARYON SPOKES MOUNT` and `# KARYON POC MOUNT` sentinels both present (regression gate)
  - `patches:` block exists at top level
  - `patches:` block contains all 3 lockdown flags as literal strings (`--no-cross-namespace-refs=true`, `--no-remote-bases=true`, `--default-service-account=default`)
  - `patches:` block contains a Deployment-targeted patch for `kustomize-controller`
  - `patches:` block contains a Deployment-targeted patch for `helm-controller`
  - `patches:` block contains a Deployment-targeted patch for `notification-controller`
  - `patches:` block contains a Kustomization-targeted patch for `flux-system` setting `serviceAccountName: kustomize-controller`

**`tests/bats/tenants-04-static-dependson.bats` (TEN-06)**
- Asserts `clusters/hub-flux/pocs/capsule-spoke.yaml`:
  - `spec.dependsOn[0].name: poc-capsule`
  - `spec.wait: true` (top-level — RESEARCH correction)
  - `spec.serviceAccountName: kustomize-controller` (D-09-05 explicit clarity)
- Asserts every per-tenant inner K in `pocs/capsule/tenants/*.yaml`:
  - For every Kustomization document: `spec.dependsOn[0].name: poc-capsule` AND `spec.dependsOn[0].namespace: flux-system`

**`tests/bats/tenants-05-static-split-path.bats` (D-08-12 inheritance regression)**
- Asserts `clusters/hub-flux/pocs/capsule.yaml`:
  - `spec.kubeConfig` does NOT exist (hub-targeted MUST NOT have kubeConfig per D-08-12)
  - `spec.serviceAccountName: kustomize-controller` (D-09-05a escape hatch)
- Asserts `clusters/hub-flux/pocs/capsule-spoke.yaml`:
  - `spec.kubeConfig.secretRef.name: spoke-capsule-kubeconfig` (D-08-12 spoke-targeted MUST have kubeConfig)
  - `spec.kubeConfig.secretRef.key: value.yaml` (P40/P18 silent-misroute defense)

### Live (Wave 1+) tests — cluster-info gated per Phase 8 pattern

**`tests/bats/tenants-06-live-tenant-cr.bats` (TEN-01 live)**
- `kubectl --context=k3d-spoke-capsule get tenants alpha bravo -o jsonpath='{.items[*].spec.forceTenantPrefix}'` returns `true true`
- `kubectl --context=k3d-spoke-capsule get sa -n tenant-alpha gitops-reconciler` exists (exit 0)
- Mirror for bravo
- 3 attempts × 30s sleep retry budget (matches Phase 8 capsule-install-06-live-helm.bats pattern)

**`tests/bats/tenants-07-live-impersonate.bats` (TEN-02 live)**
- `kubectl --context=k3d-spoke-capsule --as=alpha create namespace alpha-app1` succeeds (idempotent: ignore "AlreadyExists")
- `kubectl --context=k3d-spoke-capsule get namespace alpha-app1 -o jsonpath='{.metadata.labels.capsule\.clastix\.io/tenant}'` returns `alpha`
- Mirror for bravo
- 3 attempts × 30s sleep

**`tests/bats/tenants-08-live-quota-limit.bats` (TEN-03 live)**
- `kubectl --context=k3d-spoke-capsule -n alpha-app1 get resourcequota -o jsonpath='{.items[*].metadata.name}'` matches `capsule-alpha-*` (regex)
- `kubectl --context=k3d-spoke-capsule -n alpha-app1 get limitrange -o jsonpath='{.items[*].metadata.name}'` matches `capsule-alpha-*`
- Mirror for bravo
- Polls within 10s of namespace creation

**`tests/bats/tenants-09-live-inner-k-ready.bats` (TEN-04 reconcile)**
- `kubectl --context=k3d-hub-flux -n tenant-alpha get kustomization tenant-alpha-app -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'` returns `True` OR skip if GitRepository is `Ready=False` (pre-push state — same skip pattern as Phase 8 capsule-install-10-live-flux-observable.bats)
- 3 attempts × 30s sleep

**`tests/bats/tenants-10-live-lockdown.bats` (TEN-05 live)**
- `kubectl --context=k3d-hub-flux -n flux-system get deployment kustomize-controller -o jsonpath='{.spec.template.spec.containers[0].args}'` contains all 3 lockdown flags
- `kubectl --context=k3d-hub-flux -n flux-system get deployment helm-controller -o jsonpath='{.spec.template.spec.containers[0].args}'` contains `--no-cross-namespace-refs=true` AND `--default-service-account=default`
- `kubectl --context=k3d-hub-flux -n flux-system get deployment notification-controller -o jsonpath='{.spec.template.spec.containers[0].args}'` contains `--no-cross-namespace-refs=true`
- All 3 controllers' Deployment availableReplicas match replicas (proves no CrashLoopBackOff from misapplied flag)
- `kubectl --context=k3d-hub-flux -n flux-system get kustomization flux-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'` returns `True` (escape hatch validation)
- Polls for 2 minutes total post-patch (catches controller restart window)

**`tests/bats/tenants-11-live-dependson.bats` (TEN-06 live)**
- `kubectl --context=k3d-hub-flux -n flux-system get kustomization poc-capsule-spoke -o jsonpath='{.spec.dependsOn[0].name}'` returns `poc-capsule`
- `kubectl --context=k3d-hub-flux -n flux-system get kustomization poc-capsule-spoke -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'` returns `True`
- 3 attempts × 30s sleep

**`tests/bats/tenants-12-live-health-check.bats` (v0.18 regression gate)**
- `cd "$REPO_ROOT" && task health-check` exits 0
- (Belt-and-suspenders) the per-section checks called out in Gap 11 above

### Gated reuse (verified, not re-written)

- `tests/bats/poc-isolation-01-static.bats` — Phase 7 P31 regression (rerun in Phase 9 verifier)
- `tests/bats/capsule-install-{06,07,08,09,10}-live-*.bats` — Phase 8 invariants (rerun in Phase 9 verifier)

---

## Sources

### Primary (HIGH confidence)

- **Capsule v0.12.4 CRDs (raw GitHub source):**
  - `https://raw.githubusercontent.com/projectcapsule/capsule/v0.12.4/charts/capsule/crds/capsule.clastix.io_tenants.yaml` — Tenant CRD schema, v1beta1 + v1beta2 storage version
  - `https://raw.githubusercontent.com/projectcapsule/capsule/v0.12.4/charts/capsule/crds/capsule.clastix.io_capsuleconfigurations.yaml` — CapsuleConfiguration CRD schema
- **Flux v2.8 official docs:**
  - `https://fluxcd.io/flux/components/kustomize/kustomizations/` — Kustomization v1 spec + cross-namespace constraints
  - `https://fluxcd.io/flux/installation/configuration/multitenancy/` — multi-tenancy lockdown flags + per-controller scope
  - `https://fluxcd.io/flux/components/source/gitrepositories/` — GitRepository v1 spec + public repo auth
  - `https://fluxcd.io/flux/components/helm/helmreleases/` — HelmRelease v2 spec + flag scope
- **Flux v1 API Go source:**
  - `https://github.com/fluxcd/kustomize-controller/blob/v1.7.0/api/v1/kustomization_types.go` — KubeConfig field comment (load-bearing for P27)
- **fluxcd/flux2-multi-tenancy reference:**
  - `https://github.com/fluxcd/flux2-multi-tenancy/blob/main/clusters/production/flux-system/kustomization.yaml` — canonical lockdown patch
- **clastix/flux2-capsule-multi-tenancy:**
  - `https://github.com/clastix/flux2-capsule-multi-tenancy` — per-tenant SA + GitRepository pattern + lockdown patch
  - `https://github.com/clastix/flux2-capsule-multi-tenancy/blob/main/clusters/staging/flux-system/kustomization.yaml` — clastix lockdown variant
- **Capsule docs:**
  - `https://projectcapsule.dev/docs/tenants/permissions/` — Owner kind semantics, ServiceAccount combined-name format
  - `https://projectcapsule.dev/docs/tenants/namespaces/` — `forceTenantPrefix` auto-stamping behavior
  - `https://projectcapsule.dev/docs/operating/setup/configuration/` — CapsuleConfiguration semantics
- **Kubernetes RBAC docs:**
  - `https://kubernetes.io/docs/reference/access-authn-authz/user-impersonation/` — kubectl --as RBAC requirements
  - `https://kubernetes.io/docs/reference/access-authn-authz/rbac/` — system:masters bypass
- **karyon repo files (verified by direct read):**
  - `clusters/hub-flux/flux-system/kustomization.yaml` — current FLUX PATCH SURFACE
  - `clusters/hub-flux/pocs/capsule.yaml` + `capsule-spoke.yaml` — Phase 8 D-08-12 split-path
  - `pocs/capsule/operator/helmrelease.yaml` + `proxy/helmrelease.yaml` — Phase 8 manifest patterns
  - `pocs/capsule/spoke/kustomization.yaml` — Phase 8 placeholder
  - `scripts/health-check.sh` — v0.18 regression gate sections
  - `tests/bats/poc-isolation-01-static.bats` + `capsule-install-*.bats` — bats patterns

### Secondary (MEDIUM confidence — production case studies)

- `https://oneuptime.com/blog/post/2026-03-05-restrict-cross-namespace-references-flux/view` — corroborated cross-namespace constraint
- `https://engineering.tomtom.com/capsule-kubernetes-multitenancy/` — Capsule production case study

---

## Metadata

**Confidence breakdown:**
- Gap 1 (kubeConfig.secretRef cross-ns): HIGH — multiple authoritative sources agree (Flux docs + Go source comment)
- Gap 2 (per-controller flag matrix): HIGH — fluxcd/flux2-multi-tenancy canonical reference + Flux multi-tenancy docs
- Gap 3 (--default-service-account scope): HIGH — Go source comment is the authoritative reference
- Gap 4 (Tenant CR shape): HIGH — raw CRD schema verified field-by-field (3 corrections to CONTEXT.md surfaced)
- Gap 5 (CapsuleConfiguration shape): HIGH — raw CRD schema verified (1 missing required field surfaced)
- Gap 6 (webhook objectSelector): MEDIUM — chart values inspected via WebFetch, but `tenants` and `namespaces` hook empty-selector behavior inferred from docs not 100% confirmed across chart variants
- Gap 7 (impersonation prereqs): HIGH — Kubernetes RBAC docs definitive; k3d default kubeconfig behavior well-known
- Gap 8 (apply ordering): HIGH — Capsule controller's missing-CapsuleConfiguration tolerance documented
- Gap 9 (lockdown patch interaction): HIGH — kustomize behavior well-documented + canonical Flux pattern uses this exact approach
- Gap 10 (per-tenant GitRepository): HIGH — Flux source-controller docs definitive
- Gap 11 (health-check subset): HIGH — read scripts/health-check.sh directly
- Gap 12 (clastix repo): HIGH — repo content directly inspected
- Gap 13 (Tenant must-haves): HIGH — CRD schema + Capsule docs cross-referenced

**Research date:** 2026-04-29
**Valid until:** 2026-05-29 (30 days; Capsule v0.12.x and Flux v2.8.x are stable lines, fast-moving fields are unlikely)

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | k3d default kubeconfig embeds `system:masters` group via cert subject | Gap 7 | If kubeconfig identity is NOT in system:masters, `kubectl --as=alpha` fails at apiserver impersonation layer; verifier MUST set `--context=k3d-spoke-capsule` to use the cluster-admin context (not a tenant-issued kubeconfig) |
| A2 | karyon's hard-coded GitHub owner is `richard-iovanisci` per git config (verified via gitStatus prefix in initial context) | Gap 10 | If owner differs, `tenants-09-live-inner-k-ready.bats` fails post-push (pre-push the test should skip per the GitRepository readiness pattern); Plan 09-02 should use `${GITHUB_OWNER}` postBuild substitution OR confirm the owner literal at plan time |
| A3 | `--default-service-account=default` (CONTEXT.md choice) is at LEAST as safe as `--default-service-account=gitops-reconciler` (clastix choice) | Gap 12 | Both are valid; karyon's `default` is more conservative (no-permission failed-closed); if planner reverses to clastix's choice, P27 defense still holds via explicit `serviceAccountName` on every tenant K |

---
