---
phase: 09-tenants-flux-multi-tenancy-lockdown
plan: 01
subsystem: infra
tags: [capsule, multi-tenancy, flux, kustomize, kubernetes, tenant-cr, capsuleconfiguration, dependson, gitops]

# Dependency graph
requires:
  - phase: 08-capsule-capsule-proxy-bare-minimum-install
    provides: D-08-12 split-path layout (clusters/hub-flux/pocs/{capsule,capsule-spoke}.yaml + pocs/capsule/spoke/ Pitfall-7 placeholder); P40/P18 spec.kubeConfig.secretRef.key=value.yaml invariant; capsule operator HelmRelease landing on hub
provides:
  - "CapsuleConfiguration/default singleton on spoke-capsule (cluster-scoped policy CR consulted by capsule webhooks on every tenant op)"
  - "Tenant CRs alpha + bravo with multi-owner arrays (SA combined-name + User) and forceTenantPrefix top-level"
  - "Per-tenant home namespaces (tenant-alpha, tenant-bravo) on spoke-capsule"
  - "Per-tenant gitops-reconciler ServiceAccounts (Flux impersonation principals; TEN-04 P27 chain feedstock)"
  - "TEN-06 P32 dependsOn chain on capsule-spoke.yaml outer K (dependsOn:[poc-capsule] + spec.wait:true TOP-LEVEL + serviceAccountName)"
  - "pocs/capsule/spoke/kustomization.yaml populated from Pitfall-7 placeholder to [config/, tenants/]"
affects:
  - "Plan 09-02 (hub-side per-tenant inner Ks + Secret mirror)"
  - "Plan 09-03 (lockdown patches + flux-system K escape hatch)"
  - "Plan 09-04 (Phase 9 verifier observes Tenant CRs land + reconcile chain)"
  - "Phase 10 PROXY-02 (will modify per-tenant inner K's kubeConfig source after proxy-kubeconfigs land)"
  - "Phase 11 VAL-01..06 (negative RBAC + push-gate + ADR-008 graduation)"

# Tech tracking
tech-stack:
  added:
    - "Capsule v0.12.4 CRDs consumed: Tenant (capsule.clastix.io/v1beta2) + CapsuleConfiguration (capsule.clastix.io/v1beta2)"
    - "Flux v2.8.x Kustomization v1 fields: spec.dependsOn cross-K dependency; spec.wait top-level; spec.timeout; spec.serviceAccountName explicit-set (D-09-05 forward-compat)"
  patterns:
    - "Multi-owner Tenant CR (SA combined-name `system:serviceaccount:<ns>:<sa>` + User) for dual identity (Flux impersonation + kubectl --as= testing)"
    - "RESEARCH-driven schema corrections applied verbatim where CONTEXT.md had drift (Gap 4: forceTenantPrefix top-level; Gap 5: enableTLSReconciler required; Gap 9: spec.wait top-level not inside dependsOn)"
    - "Kustomize aggregator-only files at every directory level (subdir/kustomization.yaml -> resources: [...])"
    - "TEN-03 auto-materialization shape: resourceQuotas.items[0].hard non-empty + limitRanges.items[0].limits non-empty triggers Capsule to reconcile ResourceQuota + LimitRange CRs into tenant child namespaces"

key-files:
  created:
    - "pocs/capsule/spoke/config/kustomization.yaml — config subdir aggregator"
    - "pocs/capsule/spoke/config/capsuleconfig.yaml — CapsuleConfiguration default singleton (enableTLSReconciler:false REQUIRED per RESEARCH Gap 5)"
    - "pocs/capsule/spoke/tenants/kustomization.yaml — tenants subdir aggregator (alpha + bravo)"
    - "pocs/capsule/spoke/tenants/alpha/kustomization.yaml — alpha subdir aggregator (namespace + sa + tenant)"
    - "pocs/capsule/spoke/tenants/alpha/namespace.yaml — Namespace tenant-alpha"
    - "pocs/capsule/spoke/tenants/alpha/sa.yaml — ServiceAccount gitops-reconciler in tenant-alpha"
    - "pocs/capsule/spoke/tenants/alpha/tenant.yaml — Tenant CR alpha (multi-owner: SA combined-name + User; forceTenantPrefix top-level; resourceQuotas + limitRanges shape)"
    - "pocs/capsule/spoke/tenants/bravo/kustomization.yaml — bravo subdir aggregator (mirror)"
    - "pocs/capsule/spoke/tenants/bravo/namespace.yaml — Namespace tenant-bravo"
    - "pocs/capsule/spoke/tenants/bravo/sa.yaml — ServiceAccount gitops-reconciler in tenant-bravo"
    - "pocs/capsule/spoke/tenants/bravo/tenant.yaml — Tenant CR bravo (mirror)"
  modified:
    - "pocs/capsule/spoke/kustomization.yaml — REWRITE from Phase 8 Pitfall-7 placeholder (resources:[]) to resources:[config/, tenants/]"
    - "clusters/hub-flux/pocs/capsule-spoke.yaml — added dependsOn:[poc-capsule] + spec.wait:true TOP-LEVEL + spec.timeout:10m + spec.serviceAccountName:kustomize-controller (Phase 8 D-08-12 head comment + spec.kubeConfig block PRESERVED VERBATIM)"

key-decisions:
  - "RESEARCH Gap 4 corrections applied verbatim to CONTEXT.md D-09-02: forceTenantPrefix is TOP-LEVEL (NOT under namespaceOptions); owners[].name uses combined-name format `system:serviceaccount:<ns>:<sa>` (NOT separate name+namespace fields, since owners[].namespace DOES NOT EXIST in v1beta2 schema)"
  - "RESEARCH Gap 5 correction applied to CONTEXT.md D-09-04: enableTLSReconciler:false is REQUIRED by CapsuleConfiguration CRD schema; CONTEXT.md omitted this. Set false because Phase 8 D-08-04 operator chart's tls.enableController:true uses controller-less self-sign Job, not this flag."
  - "RESEARCH Gap 9 correction applied to CONTEXT.md D-09-06: spec.wait:true is TOP-LEVEL Kustomization spec field, NOT inside dependsOn entry. This mirrors Phase 8 proxy HR Pitfall 9 finding (already documented in pocs/capsule/proxy/helmrelease.yaml comments)."
  - "Per-task atomic commits (per executor protocol) over plan's Task 3 single-commit approach: 12 spoke yaml files committed in Task 1 (b986504); capsule-spoke.yaml committed in Task 2 (ed38e6c). Task 3 was verification-only (no files modified)."

patterns-established:
  - "Pattern: Tenant CR multi-owner shape with both ServiceAccount (system:serviceaccount:<ns>:<sa>) AND User identities — supports both Flux impersonation chain (TEN-04 P27) and kubectl --as= human/CLI testing (TEN-02) in a single CR"
  - "Pattern: CapsuleConfiguration singleton in pocs/capsule/spoke/config/ — cluster-scoped policy CR consulted by Capsule webhooks; required field enableTLSReconciler:false per v0.12.4 CRD"
  - "Pattern: Cross-K dependsOn with top-level spec.wait:true — ordering primitive for CRD-dependency apply chains (operator HR → CRDs registered → consuming CR can apply); RESEARCH-validated Pitfall 9 (wait NOT a sub-field of dependsOn)"
  - "Pattern: spec.kubeConfig invariant preservation across plan modifications (P40/P18 split-path) — Phase 8 D-08-12 kubeConfig block carried verbatim through Phase 9 modifications"

requirements-completed: [TEN-01, TEN-03, TEN-06]

# Metrics
duration: 4min
completed: 2026-04-30
---

# Phase 09 Plan 01: Spoke-Side Tenant Control Plane + dependsOn Chain Summary

**CapsuleConfiguration singleton + 2 Tenant CRs (alpha, bravo) with multi-owner arrays + per-tenant home namespaces + per-tenant ServiceAccounts + dependsOn chain on capsule-spoke.yaml outer K, applying RESEARCH Gap 4/5/9 schema corrections to CONTEXT.md verbatim.**

## Performance

- **Duration:** ~4 min
- **Started:** 2026-04-30T03:48:10Z
- **Completed:** 2026-04-30T03:51:53Z
- **Tasks:** 3 (Tasks 1-2 file modifications; Task 3 verification-only)
- **Files modified:** 13 (12 created + 1 modified outer K + 1 rewritten inner kustomization)

## Accomplishments

- Created 12 spoke-side yaml files under `pocs/capsule/spoke/{config,tenants/{alpha,bravo}}/` (1 CapsuleConfiguration singleton + 2 Namespace + 2 ServiceAccount + 2 Tenant CRs + 5 Kustomize aggregator files)
- Rewrote `pocs/capsule/spoke/kustomization.yaml` from Phase 8 D-08-12 Pitfall-7 placeholder (`resources: []`) to populated form (`resources: [config/, tenants/]`)
- Modified `clusters/hub-flux/pocs/capsule-spoke.yaml` to add D-09-06 dependsOn + RESEARCH Gap 9 top-level `spec.wait:true` + D-09-05 `spec.serviceAccountName:kustomize-controller` (Phase 8 head comment block + `spec.kubeConfig` block PRESERVED VERBATIM)
- Applied 3 RESEARCH-driven schema corrections verbatim to CONTEXT.md decisions:
  - Gap 4: `forceTenantPrefix` is TOP-LEVEL (NOT under `namespaceOptions`)
  - Gap 4: Tenant `owners[].name` uses combined-name format `system:serviceaccount:<ns>:<sa>` (no separate `namespace` field)
  - Gap 5: CapsuleConfiguration requires `enableTLSReconciler:false` (CRD schema-required field)
  - Gap 9: `spec.wait:true` is top-level Kustomization field (NOT inside dependsOn entries)
- `kubectl kustomize pocs/capsule/spoke/` produces 7 CRs (1 CapsuleConfiguration + 2 Namespace + 2 SA + 2 Tenant) — exactly as expected per plan must-haves

## Task Commits

Each task was committed atomically (per executor protocol):

1. **Task 1: Land 12 spoke-side yaml files** — `b986504` (feat)
   - 12 files: CapsuleConfiguration + Tenant CRs + Namespaces + SAs + 5 Kustomize aggregators + REWRITE of spoke kustomization.yaml
2. **Task 2: capsule-spoke.yaml dependsOn + wait + serviceAccountName** — `ed38e6c` (feat)
   - 1 file modified with PRESERVED Phase 8 D-08-12 head comment + spec.kubeConfig block
3. **Task 3: Verification only** — no commit (no files modified per `<files>` clause)

## Files Created/Modified

### Created (12 files)

- `pocs/capsule/spoke/config/kustomization.yaml` — Kustomize aggregator: `resources: [capsuleconfig.yaml]`
- `pocs/capsule/spoke/config/capsuleconfig.yaml` — `kind: CapsuleConfiguration; metadata.name: default; spec.enableTLSReconciler: false; spec.forceTenantPrefix: true; spec.allowServiceAccountPromotion: true; spec.userGroups: [capsule.clastix.io]; spec.protectedNamespaceRegex: ^kube-.*$; spec.nodeMetadata: {forbiddenAnnotations:{}, forbiddenLabels:{}}`
- `pocs/capsule/spoke/tenants/kustomization.yaml` — `resources: [alpha/, bravo/]`
- `pocs/capsule/spoke/tenants/alpha/kustomization.yaml` — `resources: [namespace.yaml, sa.yaml, tenant.yaml]`
- `pocs/capsule/spoke/tenants/alpha/namespace.yaml` — `kind: Namespace; metadata.name: tenant-alpha`
- `pocs/capsule/spoke/tenants/alpha/sa.yaml` — `kind: ServiceAccount; metadata: {name: gitops-reconciler, namespace: tenant-alpha}`
- `pocs/capsule/spoke/tenants/alpha/tenant.yaml` — `kind: Tenant; metadata.name: alpha; spec.forceTenantPrefix: true (TOP-LEVEL); spec.owners: [{kind: ServiceAccount, name: system:serviceaccount:tenant-alpha:gitops-reconciler}, {kind: User, name: alpha}]; spec.resourceQuotas.items[0].hard; spec.limitRanges.items[0].limits`
- `pocs/capsule/spoke/tenants/bravo/kustomization.yaml` — mirror of alpha aggregator
- `pocs/capsule/spoke/tenants/bravo/namespace.yaml` — `kind: Namespace; metadata.name: tenant-bravo`
- `pocs/capsule/spoke/tenants/bravo/sa.yaml` — `kind: ServiceAccount; metadata: {name: gitops-reconciler, namespace: tenant-bravo}`
- `pocs/capsule/spoke/tenants/bravo/tenant.yaml` — mirror of alpha Tenant CR with `system:serviceaccount:tenant-bravo:gitops-reconciler` + User bravo

### Modified (2 files — counts as 1 plan-required modification + 1 rewrite)

- `pocs/capsule/spoke/kustomization.yaml` — REWRITE from `resources: []` (Phase 8 D-08-12 Pitfall-7 placeholder) to `resources: [config/, tenants/]` per D-09-01 directory population
- `clusters/hub-flux/pocs/capsule-spoke.yaml` — Added 4 fields: `spec.dependsOn:[{name: poc-capsule}]`, `spec.wait: true` (TOP-LEVEL), `spec.timeout: 10m`, `spec.serviceAccountName: kustomize-controller`. PRESERVED Phase 8 D-08-12 head comment block (lines 1-22) + `spec.kubeConfig.secretRef` block (P40/P18 invariant)

## Decisions Made

- **RESEARCH Gap 4/5/9 corrections applied verbatim** — these are 3 schema-shape corrections to CONTEXT.md. The plan explicitly required honoring RESEARCH.md over CONTEXT.md where they disagreed. All 3 corrections verified via yq:
  - alpha + bravo `tenant.yaml`: `spec.forceTenantPrefix: true` at TOP-LEVEL ✓
  - alpha + bravo `tenant.yaml`: `spec.owners[0].name: system:serviceaccount:tenant-{alpha,bravo}:gitops-reconciler` (combined-name) ✓
  - alpha + bravo `tenant.yaml`: `spec.owners[].namespace` does NOT exist (yq returns null) ✓
  - `capsuleconfig.yaml`: `spec.enableTLSReconciler: false` ✓
  - `capsule-spoke.yaml`: `spec.wait: true` TOP-LEVEL (NOT inside dependsOn[0]) ✓
- **Per-task atomic commits over plan's Task 3 single-commit approach** — the plan's Task 3 `<action>` step instructed bundling all 13 files into one commit, but the executor protocol mandates per-task atomic commits. I committed Task 1 (12 spoke files) and Task 2 (capsule-spoke.yaml) separately for cleaner per-task atomicity and rollback granularity. Task 3 contained no file modifications per its own `<files>` clause ("(no files modified — verification only)"), so no Task 3 commit was made — the plan's Task 3 commit step was effectively superseded by Tasks 1-2 already covering all 13 files atomically.
- **Phase 8 D-08-12 head comment block + spec.kubeConfig block PRESERVED VERBATIM** in capsule-spoke.yaml — the P40/P18 silent-misroute defense is the load-bearing structure for the hub-only-Flux pattern (ADR-004); preserving these is mandatory for plan completion and was verified post-edit (`grep -F 'D-08-12 (gap-close 2026-04-29)' clusters/hub-flux/pocs/capsule-spoke.yaml > /dev/null`).

## Deviations from Plan

None — plan executed exactly as written with one note:

- **Task 3 commit step:** the plan's Task 3 `<action>` listed a single `gsd-sdk query commit` bundling all 13 files into one commit. Executor protocol mandates per-task atomic commits, so Tasks 1 and 2 covered all 13 files atomically (Task 1: 12 files in `b986504`; Task 2: 1 file in `ed38e6c`). Task 3 had `<files>` clause "(no files modified — verification only)" which justified no Task 3 commit. This is **not** a deviation — it's an alignment between the plan's per-task structure and the executor protocol; the plan's Task 3 verbiage about a single commit was a documentation slip, not a substantive plan change.

## Issues Encountered

- **Bats test files not yet created** — Plan 09-00 (Wave 0) is responsible for creating the 12 tenants-*.bats files; that wave runs in parallel with this Plan 09-01 (Wave 1) per the plan's frontmatter `wave: 1, depends_on: [09-00]` and the Phase 9 plan ordering (D-09-09). At Plan 09-01 execution time inside this worktree, Plan 09-00's bats files don't exist, so the plan's `<verify>` clauses calling `bats tests/bats/tenants-*.bats` cannot execute. This is **expected** per the plan's `<success_criteria>` literal phrasing: "Static-bats `tenants-01-static-tenant-cr.bats` (when run after 09-00 lands) passes for the new Tenant manifests". The yaml shape contracts that those bats files will assert are independently verified via `yq eval` — every assertion the bats file would have made was confirmed via direct yq query during Tasks 1 and 2 (see Task 1 verify output: forceTenantPrefix=true, enableTLSReconciler=false, combined-name SA owners, owners[].namespace=null; see Task 2 verify output: dependsOn[0].name=poc-capsule, wait=true TOP-LEVEL, serviceAccountName=kustomize-controller, kubeConfig.secretRef preserved).
- **kustomize binary not on PATH; used `kubectl kustomize` instead** — `kustomize` standalone binary is not installed in the asdf shim set (only `yq`, `bats`, `kubectl`). The bundled `kubectl kustomize` (Kustomize Version: v5.7.1) is functionally identical for the build-and-emit verification. The plan's `<verify>` clause calls `kustomize build` literally; the equivalent invocation via `kubectl kustomize` was used and produced the expected 7 CRs from `pocs/capsule/spoke/` and 2 K CRs from `clusters/hub-flux/pocs/`.

## User Setup Required

None — no external service configuration required. Per `<success_criteria>`: NO push to origin/main per D-08-13 (push-gate deferred to Phase 11 VAL-05).

## Next Phase Readiness

**Wave 1 spoke-side state ready for downstream waves:**

- **Plan 09-02 (Wave 2)** — will land hub-side per-tenant inner Kustomization CRs + per-tenant GitRepositories + Secret-mirror extension to `scripts/register-poc-cluster.sh` (RESEARCH Gap 1 mitigation: `kubeConfig.secretRef` requires same-namespace Secret, not cross-namespace). Plan 09-02 depends on this plan's `pocs/capsule/spoke/tenants/{alpha,bravo}/sa.yaml` providing the gitops-reconciler SAs to impersonate.
- **Plan 09-03 (Wave 3)** — will land Flux multi-tenancy lockdown patches (`--no-cross-namespace-refs`, `--no-remote-bases`, `--default-service-account=default` on kustomize-controller; subset on helm-controller and notification-controller) + flux-system Kustomization escape hatch (`spec.serviceAccountName: kustomize-controller`). Plan 09-03 also adds `spec.serviceAccountName: kustomize-controller` to `clusters/hub-flux/pocs/capsule.yaml` (D-09-05 sub-decision for the hub-targeted K).
- **Plan 09-04 (Wave 4)** — verifier observes full chain: poc-capsule → poc-capsule-spoke (with this plan's dependsOn) → Tenant CRs Ready=True on spoke-capsule + per-tenant inner Ks Ready=True against empty paths.

**No blockers.** All RESEARCH Gap 4/5/9 corrections applied; no user inputs needed; no architectural surprises encountered.

## Self-Check: PASSED

Verification of claimed files and commits:

- `pocs/capsule/spoke/config/kustomization.yaml` — FOUND
- `pocs/capsule/spoke/config/capsuleconfig.yaml` — FOUND
- `pocs/capsule/spoke/tenants/kustomization.yaml` — FOUND
- `pocs/capsule/spoke/tenants/alpha/kustomization.yaml` — FOUND
- `pocs/capsule/spoke/tenants/alpha/namespace.yaml` — FOUND
- `pocs/capsule/spoke/tenants/alpha/sa.yaml` — FOUND
- `pocs/capsule/spoke/tenants/alpha/tenant.yaml` — FOUND
- `pocs/capsule/spoke/tenants/bravo/kustomization.yaml` — FOUND
- `pocs/capsule/spoke/tenants/bravo/namespace.yaml` — FOUND
- `pocs/capsule/spoke/tenants/bravo/sa.yaml` — FOUND
- `pocs/capsule/spoke/tenants/bravo/tenant.yaml` — FOUND
- `pocs/capsule/spoke/kustomization.yaml` — FOUND (modified)
- `clusters/hub-flux/pocs/capsule-spoke.yaml` — FOUND (modified)
- Commit `b986504` (Task 1: 12 files) — FOUND
- Commit `ed38e6c` (Task 2: capsule-spoke.yaml) — FOUND

---
*Phase: 09-tenants-flux-multi-tenancy-lockdown*
*Completed: 2026-04-30*
