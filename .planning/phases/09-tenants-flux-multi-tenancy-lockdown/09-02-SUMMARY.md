---
phase: 09-tenants-flux-multi-tenancy-lockdown
plan: 02
subsystem: infra
tags: [capsule, multi-tenancy, flux, kustomize, kubernetes, hub-targeted, kubeconfig-mirror, gitops, register-poc-cluster, p27, ten-04, ten-06]

# Dependency graph
requires:
  - phase: 09-tenants-flux-multi-tenancy-lockdown
    provides: Plan 09-01 — capsule-spoke.yaml has dependsOn:[poc-capsule] + spec.wait:true TOP-LEVEL + serviceAccountName:kustomize-controller; per-tenant gitops-reconciler SAs landed under pocs/capsule/spoke/tenants/{alpha,bravo}/sa.yaml
  - phase: 08-capsule-capsule-proxy-bare-minimum-install
    provides: D-08-12 split-path layout (clusters/hub-flux/pocs/{capsule,capsule-spoke}.yaml + pocs/capsule/spoke/ Pitfall-7 placeholder); P40/P18 spec.kubeConfig.secretRef.key=value.yaml invariant
  - phase: 07-poc-onboarding-and-spoke-capsule
    provides: scripts/register-poc-cluster.sh (POC registration script — Plan 09-02 extends with Secret-mirror function); spoke-capsule-kubeconfig Secret in flux-system on hub
provides:
  - "Per-tenant Namespace tenant-alpha + GitRepository tenant-alpha-source + Kustomization tenant-alpha-app on hub-flux (multi-doc YAML at pocs/capsule/tenants/alpha.yaml)"
  - "Per-tenant Namespace tenant-bravo + GitRepository tenant-bravo-source + Kustomization tenant-bravo-app on hub-flux (multi-doc YAML at pocs/capsule/tenants/bravo.yaml)"
  - "Pitfall-7 placeholder dirs alpha-app/ + bravo-app/ (resources: []; Phase 11 may populate)"
  - "tenants/ aggregator (resources: [alpha.yaml, bravo.yaml, alpha-app/, bravo-app/])"
  - "pocs/capsule/kustomization.yaml updated to add tenants/ to resources (preserves Phase 7+8 head comment + appends Phase 9 update note)"
  - "scripts/register-poc-cluster.sh extended with mirror_kubeconfig_to_tenant_namespaces function — imperatively mirrors spoke-capsule-kubeconfig Secret into tenant-{alpha,bravo} ns on hub-flux per RESEARCH §Gap 1 mitigation (Flux v2.8 hard same-namespace constraint)"
  - "TEN-04 P27 LOAD-BEARING DEFENSE in place: every tenant inner Kustomization has spec.serviceAccountName=gitops-reconciler explicit-set"
  - "TEN-06 P32 dependsOn chain extended to per-tenant inner Ks: dependsOn=[{name:poc-capsule, namespace:flux-system}] + spec.wait:true TOP-LEVEL"
affects:
  - "Plan 09-03 (lockdown patches + flux-system K escape hatch — high regression risk, full v0.18 task health-check rerun required as gate)"
  - "Plan 09-04 (Phase 9 verifier observes full reconcile chain: live Secret-mirror via re-running register-poc-cluster.sh + tenant inner K Ready=True against empty placeholder paths)"
  - "Phase 10 PROXY-02 (will modify per-tenant inner K's kubeConfig source from spoke-capsule-kubeconfig to per-tenant proxy-kubeconfigs minted by issue-tenant-kubeconfig.sh)"
  - "Phase 11 VAL-01..06 (negative RBAC + push-gate + ADR-008 graduation; first push lands real GitRepository fetches making Ready=True observable)"

# Tech tracking
tech-stack:
  added:
    - "Flux v2.8.x source.toolkit.fluxcd.io/v1 GitRepository CR (per-tenant; HTTPS public repo url; no auth secretRef per Phase 6 REPO-01..04)"
    - "yq strip pattern for Secret-mirror idempotency: del(.metadata.resourceVersion, .metadata.uid, .metadata.creationTimestamp) — required to re-apply Secret across namespaces without 'field is immutable' rejection"
  patterns:
    - "Multi-doc YAML per-tenant pattern: 1 file = 3 docs (Namespace + GitRepository + Kustomization), all in tenant-<name> ns (RESEARCH §Gap 1 same-namespace constraint enforcement)"
    - "Imperative Secret-mirror via register-poc-cluster.sh extension — sibling pattern to apply_hub_secret() (D-11 token safety: kubectl get|yq|kubectl apply pattern; token never logged, never tee'd, never argv'd)"
    - "RESEARCH-driven schema corrections honored verbatim (Gap 1 same-namespace + Gap 9 wait TOP-LEVEL + Gap 10 hard-coded GitHub owner)"
    - "Per-doc lint pattern via 'yq eval' (NOT 'yq eval-all') for multi-doc YAML — auto-fix Rule 1 applied to tenants-02 + tenants-04 bats lint helpers"

key-files:
  created:
    - "pocs/capsule/tenants/alpha.yaml — multi-doc YAML: Namespace tenant-alpha + GitRepository tenant-alpha-source + Kustomization tenant-alpha-app (with kubeConfig + serviceAccountName=gitops-reconciler [P27] + dependsOn=poc-capsule [P32] + wait:true TOP-LEVEL)"
    - "pocs/capsule/tenants/bravo.yaml — mirror of alpha (alpha → bravo throughout)"
    - "pocs/capsule/tenants/alpha-app/kustomization.yaml — Pitfall-7 placeholder (resources: [])"
    - "pocs/capsule/tenants/bravo-app/kustomization.yaml — Pitfall-7 placeholder mirror"
    - "pocs/capsule/tenants/kustomization.yaml — aggregator: [alpha.yaml, bravo.yaml, alpha-app/, bravo-app/]"
  modified:
    - "pocs/capsule/kustomization.yaml — added 'tenants/' to resources list (preserved Phase 7+8 head comment + appended Phase 9 update note per D-09-01)"
    - "scripts/register-poc-cluster.sh — added mirror_kubeconfig_to_tenant_namespaces function + invocation in main flow between apply_hub_secret and ensure_hub_pocs_mount sections"
    - "tests/bats/tenants-02-static-p27.bats — [Rule 1 - Bug] Auto-fixed lint helper: 'yq eval-all' → 'yq eval' (per-doc) so multi-doc YAML iterates correctly; P27 negative falsifier still fails as expected"
    - "tests/bats/tenants-04-static-dependson.bats — [Rule 1 - Bug] Same auto-fix applied to both lint helpers (dependsOn + wait_top_level)"

key-decisions:
  - "RESEARCH §Gap 1 mitigation applied: scripts/register-poc-cluster.sh extension imperatively mirrors spoke-capsule-kubeconfig from flux-system into tenant-{alpha,bravo} on hub-flux. Flux v2.8 contract is unconditional same-namespace constraint for kubeConfig.secretRef regardless of --no-cross-namespace-refs flag scope (citation: Flux v2.8 docs + kustomize-controller v1 API api/v1/kustomization_types.go KubeConfig field comment)."
  - "RESEARCH §Gap 9 correction applied: spec.wait:true is TOP-LEVEL Kustomization spec field on per-tenant inner Ks — NOT inside dependsOn[] entries. This mirrors the same correction Plan 09-01 applied to capsule-spoke.yaml."
  - "RESEARCH §Gap 10 Option A applied: GitHub owner hard-coded to richard-iovanisci in per-tenant GitRepository CRs. Postpones cross-namespace ConfigMap mirror complexity that Option B (postBuild substituteFrom) would require. Until Phase 11 VAL-05 first push, GitRepositories will Ready=False with 'failed to fetch: revision main doesn't exist on remote' — acceptable per Phase 9 scope."
  - "P27 LOAD-BEARING DEFENSE comment block included verbatim in alpha.yaml + bravo.yaml Kustomization doc per RESEARCH §Gap 3 root cause analysis. The defense is structural (explicit serviceAccountName per inner K), not flag-based (--default-service-account is belt-and-suspenders)."
  - "Per-task atomic commits over plan's Task 3 single-commit approach (matches Plan 09-01 precedent): Task 1 (b5a76ae) bundles 5 new yaml + 1 modified yaml + 2 modified bats (the auto-fix); Task 2 (9682dae) bundles 1 modified shell script. Task 3 is verification-only (its <files> clause says 'no files modified — verification only'); no Task 3 commit needed."
  - "Bats lint helper 'yq eval-all' bug auto-fixed per Rule 1 — affected tenants-02 + tenants-04 from Plan 09-00 Wave 0. 'yq eval-all' collapses all YAML docs in a multi-doc file into a SINGLE flattened TSV row, defeating the per-doc lint loop. Without this fix, Plan 09-02 success criteria (tenants-02 GREEN; tenants-04 FULLY GREEN) would be unreachable. Negative P27 falsifier still FAILS the lint as expected (broken-fixture has no serviceAccountName)."

patterns-established:
  - "Pattern: Per-tenant multi-doc YAML at pocs/capsule/tenants/<name>.yaml with 3 docs (Namespace + GitRepository + Kustomization) — RESEARCH §Gap 1 same-namespace constraint enforced by metadata.namespace=tenant-<name> on every doc that takes a namespace"
  - "Pattern: Imperative Secret-mirror in register-poc-cluster.sh — kubectl get -o yaml | yq strip immutable metadata fields | kubectl apply; idempotent re-run safe; sibling to existing apply_hub_secret() function; D-11 token-safety conventions preserved"
  - "Pattern: per-doc bats lint via 'yq eval' (NOT 'yq eval-all') for multi-doc YAML lint loops — `while IFS=$'\\t' read -r ...; do ... done < <(yq eval ... | @tsv ...)` correctly emits one TSV row per doc"
  - "Pattern: P27 LOAD-BEARING DEFENSE comment block (verbatim from RESEARCH §Gap 3) attached to every tenant inner Kustomization doc — onboarding signal for any future modifier that the explicit serviceAccountName is the primary structural defense, not the --default-service-account flag"

requirements-completed: [TEN-04, TEN-06]

# Metrics
duration: 6min
completed: 2026-04-30
---

# Phase 09 Plan 02: Hub-Side Per-Tenant Inner Kustomizations + Secret-Mirror Extension Summary

**5 new yaml files (per-tenant Namespace + GitRepository + Kustomization multi-doc + 2 Pitfall-7 placeholders + tenants/ aggregator) + outer pocs/capsule/kustomization.yaml updated with tenants/ + scripts/register-poc-cluster.sh extended with mirror_kubeconfig_to_tenant_namespaces function — completes the hub-side TEN-04 P27 + TEN-06 P32 contracts and mitigates RESEARCH §Gap 1 (Flux's hard same-namespace constraint for kubeConfig.secretRef).**

## Performance

- **Duration:** ~6 min
- **Started:** 2026-04-30T04:12:01Z
- **Completed:** 2026-04-30T04:18:11Z
- **Tasks:** 3 (Tasks 1-2 file modifications; Task 3 verification-only)
- **Files modified:** 9 (5 new yaml + 1 modified yaml + 1 modified shell script + 2 modified bats — auto-fix)

## Accomplishments

- Created 5 new yaml files under `pocs/capsule/tenants/` materializing the hub-targeted control plane:
  - `alpha.yaml` + `bravo.yaml`: 3-doc multi-doc YAML (Namespace + GitRepository + Kustomization) per tenant with all RESEARCH-corrected fields verbatim
  - `alpha-app/kustomization.yaml` + `bravo-app/kustomization.yaml`: Pitfall-7 placeholders (resources: [])
  - `kustomization.yaml`: aggregator referencing all 4 above
- Modified `pocs/capsule/kustomization.yaml` to add `tenants/` to resources, preserving the Phase 7+8 head comment block and appending a Phase 9 update note per D-09-01
- Extended `scripts/register-poc-cluster.sh` with `mirror_kubeconfig_to_tenant_namespaces` function + invocation in main flow — mitigates RESEARCH §Gap 1 (Flux v2.8 unconditional same-namespace constraint for `kubeConfig.secretRef`)
- Auto-fixed `yq eval-all` → `yq eval` lint bug in `tenants-02-static-p27.bats` + `tenants-04-static-dependson.bats` (Plan 09-00 Wave 0 RED scaffold) so the bats correctly walk multi-doc YAML; P27 negative falsifier still fails the lint as expected (broken-fixture remains broken)
- All 3 RESEARCH-driven corrections honored verbatim:
  - **Gap 1:** Per-tenant Secret-mirror in register-poc-cluster.sh + every yaml doc that takes a namespace lives in matching tenant-<name> ns
  - **Gap 9:** `spec.wait: true` is TOP-LEVEL (not nested inside dependsOn entries)
  - **Gap 10 Option A:** GitHub owner hard-coded to `richard-iovanisci` (avoids cross-namespace ConfigMap mirror complexity)
- `kubectl kustomize pocs/capsule/tenants/` resolves to 6 CRs (2 Namespace + 2 GitRepository + 2 Kustomization)
- `kubectl kustomize pocs/capsule/` resolves to 10 CRs (above 6 + 2 OCIRepository + 2 HelmRelease from operator/ + proxy/)
- 11/11 bats GREEN (tenants-02 + tenants-04 + poc-isolation-01)

## Task Commits

Each task was committed atomically (per executor protocol; matches Plan 09-01 precedent):

1. **Task 1: 5 new tenant yaml files + outer kustomization update + bats auto-fix** — `b5a76ae` (feat)
   - 8 files: 5 new yaml + 1 modified outer kustomization yaml + 2 modified bats files (auto-fix)
2. **Task 2: register-poc-cluster.sh mirror_kubeconfig_to_tenant_namespaces extension** — `9682dae` (feat)
   - 1 file modified: scripts/register-poc-cluster.sh
3. **Task 3: Verification-only (no commit)** — verification-only per `<files>` clause; no files modified beyond Tasks 1-2

## Files Created/Modified

### Created (5 files)

- `pocs/capsule/tenants/alpha.yaml` — multi-doc: `kind: Namespace` (tenant-alpha) + `kind: GitRepository` (tenant-alpha-source in tenant-alpha ns; URL `https://github.com/richard-iovanisci/karyon`) + `kind: Kustomization` (tenant-alpha-app in tenant-alpha ns; spec.path=`./pocs/capsule/tenants/alpha-app`; spec.serviceAccountName=`gitops-reconciler` [P27 LOAD-BEARING]; spec.kubeConfig.secretRef.{name=spoke-capsule-kubeconfig, key=value.yaml} [P40/P18]; spec.dependsOn=[{name:poc-capsule, namespace:flux-system}] [P32]; spec.wait=true TOP-LEVEL [Gap 9]; spec.timeout=5m)
- `pocs/capsule/tenants/bravo.yaml` — mirror of alpha (alpha → bravo substitution throughout including all comment blocks)
- `pocs/capsule/tenants/alpha-app/kustomization.yaml` — `apiVersion: kustomize.config.k8s.io/v1beta1; kind: Kustomization; resources: []` (Pitfall-7 placeholder)
- `pocs/capsule/tenants/bravo-app/kustomization.yaml` — mirror
- `pocs/capsule/tenants/kustomization.yaml` — aggregator: `resources: [alpha.yaml, bravo.yaml, alpha-app/, bravo-app/]`

### Modified (4 files)

- `pocs/capsule/kustomization.yaml` — added `- tenants/` to resources (after `- proxy/`); appended Phase 9 update note (D-09-01) preserving Phase 7+8 head comment block verbatim
- `scripts/register-poc-cluster.sh` — added `mirror_kubeconfig_to_tenant_namespaces()` function (40-line block between `apply_hub_secret` and `ensure_hub_pocs_mount`) + invocation in main flow (between `pass "applied: ${POC_CLUSTER} hub Secret"` and `section "Hub-side FLUX PATCH SURFACE patch"`); per-tenant for-loop creates ns + mirrors Secret with `kubectl get -o yaml | yq strip metadata.{resourceVersion,uid,creationTimestamp} | kubectl apply` pattern; D-11 token-safety conventions preserved
- `tests/bats/tenants-02-static-p27.bats` — [Rule 1 - Bug] flipped `yq eval-all` → `yq eval` (per-doc) in lint_kustomization_sa_dir helper; added explanatory comment naming Plan 09-02 + Rule 1
- `tests/bats/tenants-04-static-dependson.bats` — [Rule 1 - Bug] same auto-fix applied in both helper functions (assert_inner_k_dependson_poc_capsule + assert_inner_k_wait_top_level); added explanatory comments

## Decisions Made

- **All 3 RESEARCH-driven schema corrections honored verbatim** — Gap 1 (Secret mirror), Gap 9 (top-level spec.wait), Gap 10 Option A (hard-coded owner). Each correction is ground-truth-cited in the file head comments so future modifiers don't accidentally revert them.
- **Per-task atomic commits over plan's Task 3 single-commit approach** — matches Plan 09-01 precedent (and executor protocol mandate). The plan's Task 3 step describing a single bundling commit was effectively superseded by Tasks 1-2 already committing atomically.
- **Phase 7+8 head comment in `pocs/capsule/kustomization.yaml` preserved verbatim** + appended Phase 9 update note per PATTERNS.md guidance. The head comment is part of the inheritance chain documentation; preserving it is mandatory per D-09-01.
- **D-11 token-safety conventions preserved in mirror function** — `kubectl get | yq | kubectl apply` pattern keeps token bytes flowing through stdin only (never argv, never tee, never logged); idempotent via apply + yq strip pattern.
- **Bats lint auto-fix scope:** the `yq eval-all` → `yq eval` fix is **directly required** for Plan 09-02 success criteria (tenants-02 + tenants-04 GREEN). Without it, the plan cannot meet its own automated verify clause. Bug pre-existed Plan 09-02 (introduced in Plan 09-00 Wave 0 RED scaffold), but only manifested when multi-doc YAML landed (Plan 09-02 work). Single-doc YAML (e.g., the broken-fixture file) was unaffected; this is why P27 negative falsifier passed even before the auto-fix.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Bats lint helper used `yq eval-all` instead of `yq eval` for multi-doc YAML iteration**

- **Found during:** Task 1 (verifying tenants-02 + tenants-04 turn GREEN after creating alpha.yaml + bravo.yaml)
- **Issue:** `yq eval-all` collapses all docs in a multi-doc YAML file into a SINGLE flattened TSV row (tab-joining fields across docs into one row), so the lint's `while IFS=$'\t' read -r ...` loop iterates ONCE per file with garbled column alignment instead of ONCE per YAML doc. With multi-doc alpha.yaml (Namespace + GitRepository + Kustomization), the read loop saw `kind="Namespace" apiv="v1" sa=""` (the first 3 fields of the flattened row), skipped it (not a Kustomization), and exited with `found_any=0` — so the lint reported "no Flux Kustomization docs found" even though both files contained one each. This is a Plan 09-00 Wave 0 RED scaffold bug that only manifested when Plan 09-02 multi-doc YAML landed.
- **Fix:** Flipped `yq eval-all` → `yq eval` (per-doc) in 3 helper-function call sites across 2 bats files. Added explanatory comments naming Plan 09-02 + Rule 1 so the change is traceable. Verified the negative P27 falsifier (single-doc broken fixture) still FAILS the lint as expected.
- **Files modified:** `tests/bats/tenants-02-static-p27.bats` (1 site); `tests/bats/tenants-04-static-dependson.bats` (2 sites)
- **Verification:** All 8 tenants-02/04 bats GREEN post-fix; P27 negative falsifier (broken-fixture with missing `spec.serviceAccountName`) still triggers lint failure correctly. Direct yq evidence: `yq eval` on alpha.yaml emits 3 TSV rows (Namespace, GitRepository, Kustomization); `yq eval-all` emits 1 flattened row.
- **Committed in:** `b5a76ae` (Task 1 commit — bundled with the new tenant yaml files since the bats fix is directly required to verify those new files)

---

**Total deviations:** 1 auto-fixed (Rule 1 — bats lint logic bug)
**Impact on plan:** Auto-fix is essential for Plan 09-02 success criteria attainment ("tenants-02 + tenants-04 GREEN after Plan 09-02 commit"). No scope creep — the fix is in 2 bats files explicitly listed in Plan 09-02 success criteria as expected-GREEN gates. The bug was a Plan 09-00 Wave 0 scaffold artifact that only manifested when multi-doc YAML landed in Plan 09-02 work.

## Issues Encountered

- **`kustomize` standalone binary not on PATH; used `kubectl kustomize` instead** — same as Plan 09-01. The asdf shim set has `yq`, `bats`, `kubectl` but not standalone `kustomize`. The bundled `kubectl kustomize` (Kustomize Version: v5.7.1) is functionally identical for the build-and-emit verification. The plan's `<verify>` clauses call `kustomize build` literally; the equivalent `kubectl kustomize` invocation produced the expected 6 CRs from `pocs/capsule/tenants/` and 10 CRs from `pocs/capsule/`.
- **`grep -c -F 'mirror_kubeconfig_to_tenant_namespaces'` returns 3 hits, not the plan's expected 2** — the new function block includes a `# ---------- mirror_kubeconfig_to_tenant_namespaces: ... ----------` section header (mirroring the existing analog `# ---------- apply_hub_secret: ... ----------`). The plan's expected count of 2 (definition + invocation) was a minor planning oversight — the section-header convention is structural and matches sibling analog patterns. The plan's intent ("function exists + invocation exists") is satisfied.
- **Pre-existing shellcheck SC2034 warnings on lines 47/49/51/304 of register-poc-cluster.sh** — explicitly tracked under "Phase 1-5 shellcheck warning cleanup (SC2034 / SC2155)" deferred-items list; not introduced by Plan 09-02. My new function block has 0 new shellcheck warnings (the SC2016 single-quote yq expression is suppressed by inline `# shellcheck disable=SC2016` per analog pattern).

## User Setup Required

None — no external service configuration required. Per `<success_criteria>`: NO push to origin/main per D-08-13 (push-gate deferred to Phase 11 VAL-05).

## Next Phase Readiness

**Wave 2 hub-side state ready for downstream waves:**

- **Plan 09-03 (Wave 3)** — will land Flux multi-tenancy lockdown patches (`--no-cross-namespace-refs`, `--no-remote-bases`, `--default-service-account=default` on kustomize-controller; subset on helm-controller and notification-controller per RESEARCH §Gap 2 verbatim) + flux-system Kustomization escape hatch (`spec.serviceAccountName: kustomize-controller`). Plan 09-03 also adds `spec.serviceAccountName: kustomize-controller` to `clusters/hub-flux/pocs/capsule.yaml` (D-09-05 sub-decision for the hub-targeted K). **Highest regression risk in Phase 9** per STATE.md — full v0.18 `task health-check` rerun required as immediate gate.
- **Plan 09-04 (Wave 4)** — verifier observes full chain: live re-run of `bash scripts/register-poc-cluster.sh spoke-capsule` exercises the new mirror function; per-tenant inner Ks reach Ready=True against empty placeholder paths (or skip on pre-push GitRepository state per Gap 10 Option A acceptance).
- **Phase 10 PROXY-02** — will swap per-tenant inner K's `spec.kubeConfig.secretRef.name` from `spoke-capsule-kubeconfig` to per-tenant proxy-kubeconfigs (`<tenant>-proxy-kubeconfig`) minted by `scripts/poc/capsule/issue-tenant-kubeconfig.sh`. The Plan 09-02 same-namespace mirror lookup will continue to work because the per-tenant proxy-kubeconfigs will be applied directly to tenant-<name> ns (no mirror needed for already-tenant-namespaced Secrets).
- **Phase 11 VAL-05** — first push to origin/main lands the per-tenant GitRepository fetches; tenant inner Ks reach Ready=True; full reconcile chain observable end-to-end.

**No blockers.** All RESEARCH-corrected fields applied verbatim; no user inputs needed; no architectural surprises. The bats lint auto-fix (Rule 1) was the only deviation and is directly required for plan success criteria attainment.

## Self-Check: PASSED

Verification of claimed files and commits:

- `pocs/capsule/tenants/alpha.yaml` — FOUND
- `pocs/capsule/tenants/bravo.yaml` — FOUND
- `pocs/capsule/tenants/alpha-app/kustomization.yaml` — FOUND
- `pocs/capsule/tenants/bravo-app/kustomization.yaml` — FOUND
- `pocs/capsule/tenants/kustomization.yaml` — FOUND
- `pocs/capsule/kustomization.yaml` — FOUND (modified; tenants/ in resources)
- `scripts/register-poc-cluster.sh` — FOUND (modified; mirror_kubeconfig_to_tenant_namespaces present 3x)
- `tests/bats/tenants-02-static-p27.bats` — FOUND (modified; yq eval per-doc)
- `tests/bats/tenants-04-static-dependson.bats` — FOUND (modified; yq eval per-doc)
- Commit `b5a76ae` (Task 1: 8 files) — FOUND
- Commit `9682dae` (Task 2: register-poc-cluster.sh) — FOUND
- bats GREEN: 11/11 across tenants-02 + tenants-04 + poc-isolation-01 — VERIFIED
- kubectl kustomize: 10 CRs from `pocs/capsule/`, 6 CRs from `pocs/capsule/tenants/` — VERIFIED

---
*Phase: 09-tenants-flux-multi-tenancy-lockdown*
*Completed: 2026-04-30*
