---
phase: 9
slug: tenants-flux-multi-tenancy-lockdown
status: final
nyquist_compliant: true
wave_0_complete: true
created: 2026-04-29
finalized: 2026-05-11
finalized_evidence: "Plan 09-00 Wave 0 RED bats scaffold (12 bats files: 5 static + 7 live; P27 negative falsifier fixture covering TEN-01..06 contracts under D-09-08 Nyquist gate) became GREEN over Plans 09-01..09-04. 09-VERIFICATION.md reports status: passed_with_overrides with 8/8 must-haves verified; Plan 09-03 lockdown landed on attempt 3 after two atomic rollbacks (Gap A spoke SA name correction). Post-fix evidence: TEN-04 + TEN-06 push-gate-deferred items resolved by Plan 11-07 closeout at HEAD 8415ab66 (per 11-07-SUMMARY.md). Phase 9 had nyquist_compliant: true + wave_0_complete: true set by commit fe7d98b (2026-04-29 Wave 0 close); status flipped to final 2026-05-11 per Phase 12 close-out reconciliation. T-3 rationale: included in Cluster E per researcher Open Q 1 recommendation."
---

# Phase 9 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Aligns with RESEARCH.md §"Validation Architecture" — every TEN-01..06 requirement maps to a falsifier name + observable signal + bats file target.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bats-core 1.x (mirrors v0.18 + Phase 7/8 conventions) |
| **Config file** | none — bats runs from `tests/bats/` directory |
| **Quick run command** | `bats tests/bats/tenants-*.bats` |
| **Full suite command** | `bats tests/bats/` |
| **Estimated runtime** | ~30s static + ~60s live (cluster-info-gated; auto-skip when cluster down) |

---

## Sampling Rate

- **After every task commit:** Run `bats tests/bats/tenants-*.bats` (subset matching modified file)
- **After every plan wave:** Run `bats tests/bats/tenants-*.bats` (full Phase 9 suite)
- **Before `/gsd-verify-work`:** Full suite (`bats tests/bats/`) must be green; v0.18 `task health-check` must exit 0
- **Max feedback latency:** ~90 seconds (60s live + 30s buffer)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 09-00-01 | 00 | 0 | TEN-01 (static contract) | — | Tenant CR yaml shape grep-asserted | static-bats | `bats tests/bats/tenants-01-static-tenant-cr.bats` | ❌ W0 | ⬜ pending |
| 09-00-02 | 00 | 0 | TEN-04 (P27 LOAD-BEARING) | T-9-P27 | Every tenant inner K has non-null `serviceAccountName` | static-bats | `bats tests/bats/tenants-02-static-p27.bats` | ❌ W0 | ⬜ pending |
| 09-00-03 | 00 | 0 | TEN-05 (lockdown) | — | `clusters/hub-flux/flux-system/kustomization.yaml` `patches:` block has 3 flags + flux-system K SA escape hatch | static-bats | `bats tests/bats/tenants-03-static-lockdown.bats` | ❌ W0 | ⬜ pending |
| 09-00-04 | 00 | 0 | TEN-06 (P32 dependsOn) | — | dependsOn chain on `poc-capsule-spoke` + per-tenant inner Ks | static-bats | `bats tests/bats/tenants-04-static-dependson.bats` | ❌ W0 | ⬜ pending |
| 09-00-05 | 00 | 0 | D-08-12 inheritance | — | `capsule.yaml` no kubeConfig; `capsule-spoke.yaml` full kubeConfig + `key: value.yaml` | static-bats | `bats tests/bats/tenants-05-static-split-path.bats` | ❌ W0 | ⬜ pending |
| 09-00-06 | 00 | 0 | TEN-01 (live) | — | `kubectl get tenants alpha bravo` — both Ready; forceTenantPrefix=true | live-bats | `bats tests/bats/tenants-06-live-tenant-cr.bats` | ❌ W0 | ⬜ pending |
| 09-00-07 | 00 | 0 | TEN-02 (impersonation) | — | `kubectl --as=alpha create namespace alpha-app1` succeeds; capsule label stamped | live-bats | `bats tests/bats/tenants-07-live-impersonate.bats` | ❌ W0 | ⬜ pending |
| 09-00-08 | 00 | 0 | TEN-03 (auto-quota) | — | ResourceQuota + LimitRange auto-materialize within 10s | live-bats | `bats tests/bats/tenants-08-live-quota-limit.bats` | ❌ W0 | ⬜ pending |
| 09-00-09 | 00 | 0 | TEN-04 (live reconcile) | T-9-P27 | tenant inner K Ready=True against empty placeholder path | live-bats | `bats tests/bats/tenants-09-live-inner-k-ready.bats` | ❌ W0 | ⬜ pending |
| 09-00-10 | 00 | 0 | TEN-05 (live lockdown) | — | kustomize-controller Deployment has 3 flag args; flux-system K Ready=True | live-bats | `bats tests/bats/tenants-10-live-lockdown.bats` | ❌ W0 | ⬜ pending |
| 09-00-11 | 00 | 0 | TEN-06 (live dependsOn) | — | poc-capsule-spoke dependsOn poc-capsule; both Ready=True | live-bats | `bats tests/bats/tenants-11-live-dependson.bats` | ❌ W0 | ⬜ pending |
| 09-00-12 | 00 | 0 | v0.18 regression | — | `task health-check` exits 0 post-lockdown | live-bats | `bats tests/bats/tenants-12-live-health-check.bats` | ❌ W0 | ⬜ pending |
| 09-01-01 | 01 | 1 | TEN-01, TEN-03 | — | CapsuleConfiguration applied; Tenant CRs alpha+bravo on spoke | live-bats | tenants-01 + tenants-06 (rerun) | — | ⬜ pending |
| 09-01-02 | 01 | 1 | TEN-02 | — | `kubectl --as=alpha` creates ns successfully | live-bats | tenants-07 (rerun) | — | ⬜ pending |
| 09-02-01 | 02 | 2 | TEN-04 (structural) | T-9-P27 | per-tenant hub Ks land with `spec.serviceAccountName: gitops-reconciler` | static+live | tenants-02 + tenants-09 | — | ⬜ pending |
| 09-02-02 | 02 | 2 | D-09-03a Secret mirror | — | `spoke-capsule-kubeconfig` Secret present in `tenant-alpha` + `tenant-bravo` ns on hub | live-bats | tenants-09 (Secret presence assertion) | — | ⬜ pending |
| 09-03-01 | 03 | 3 | TEN-05 | — | lockdown patches apply; controllers restart with 3 flags | static+live | tenants-03 + tenants-10 | — | ⬜ pending |
| 09-03-02 | 03 | 3 | v0.18 regression | — | `task health-check` post-lockdown exits 0 | live-bats | tenants-12 | — | ⬜ pending |
| 09-03-03 | 03 | 3 | escape hatch | — | flux-system Kustomization has `spec.serviceAccountName: kustomize-controller` | static+live | tenants-03 + tenants-10 | — | ⬜ pending |
| 09-04-01 | 04 | 4 | full Phase 9 verifier | — | All TEN-01..06 + Phase 7/8 regression bats GREEN | full bats run + health-check | `bats tests/bats/ && task health-check` | — | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [x] `tests/bats/tenants-01-static-tenant-cr.bats` — TEN-01 Tenant CR yaml shape (forceTenantPrefix, owners[SA + User], two-Tenant disjoint owners)
- [x] `tests/bats/tenants-02-static-p27.bats` — TEN-04 P27 yq-based grep: `for f in pocs/capsule/tenants/{alpha,bravo}.yaml; do yq '.spec.serviceAccountName' "$f" | grep -qv '^null$'; done` + synthetic broken-fixture negative falsifier
- [x] `tests/bats/tenants-03-static-lockdown.bats` — TEN-05 patches block grep (3 flag literals + Kustomization-CR patch for `spec.serviceAccountName: kustomize-controller`); FLUX PATCH SURFACE comment block preserved verbatim
- [x] `tests/bats/tenants-04-static-dependson.bats` — TEN-06 capsule-spoke.yaml has `dependsOn: [{name: poc-capsule}] wait: true` (top-level spec.wait per RESEARCH Gap 9 correction); per-tenant inner Ks have dependsOn
- [x] `tests/bats/tenants-05-static-split-path.bats` — D-08-12 inheritance regression: `capsule.yaml` no kubeConfig; `capsule-spoke.yaml` full kubeConfig + `key: value.yaml`
- [x] `tests/bats/tenants-06-live-tenant-cr.bats` — TEN-01 live: `kubectl get tenants alpha bravo` reports both with `forceTenantPrefix=true` (top-level per RESEARCH Gap 4 correction); each gitops-reconciler SA exists in tenant-{alpha,bravo} ns
- [x] `tests/bats/tenants-07-live-impersonate.bats` — TEN-02 live: `kubectl --as=alpha create namespace alpha-app1` succeeds + label stamped (idempotent re-run safe); mirror for bravo
- [x] `tests/bats/tenants-08-live-quota-limit.bats` — TEN-03 live: ResourceQuota + LimitRange auto-materialize in alpha-app1 + bravo-app1 within 10s (poll loop)
- [x] `tests/bats/tenants-09-live-inner-k-ready.bats` — TEN-04 live reconcile: tenant inner Ks reach Ready=True against empty placeholder paths; `spoke-capsule-kubeconfig` Secret exists in tenant-{alpha,bravo} ns on hub (D-09-03a Secret-mirror per RESEARCH Gap 1 correction)
- [x] `tests/bats/tenants-10-live-lockdown.bats` — TEN-05 live: kustomize-controller Deployment args contain 3 flags; flux-system K Ready=True; poc-capsule + poc-capsule-spoke Ready=True post-lockdown
- [x] `tests/bats/tenants-11-live-dependson.bats` — TEN-06 live: poc-capsule-spoke dependsOn chain Ready=True; verifier observes Ready ordering (poc-capsule → poc-capsule-spoke → tenant inner Ks)
- [x] `tests/bats/tenants-12-live-health-check.bats` — v0.18 regression: `task health-check` exits 0 post-lockdown (full v0.18 suite covering hub-flux + spoke-apps + spoke-ml reconciles still green)
- [x] **Reuse verbatim** — `tests/bats/poc-isolation-01-static.bats` (Phase 7 P31 contract); `tests/bats/capsule-install-{06,07,08,09,10}-live-*.bats` (Phase 8 invariants)

*All 12 new bats files are RED at end of Plan 09-00 (Wave 0). Plans 01..04 make them GREEN by landing tenant content + lockdown patches.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| `task rebuild` SLO regression with spoke-capsule alive (<230s) | implicit (Phase 11 VAL-04 owns; Phase 9 inheritance) | Destructive teardown; not safe in CI loop | Phase 11 owns; Phase 9 inherits via `tests/bats/poc-isolation-01-static.bats` static check (no spoke-capsule mentions in v0.18 scripts) |
| First push to origin/main of Phase 9 commits | implicit (D-08-13 deferral; Phase 11 VAL-05 owns) | Push-gate deferred to Phase 11 | Phase 9 commits remain local-only; no manual push during Phase 9 |
| Webhook failure recovery observation | Phase 11 VAL-02 | Destructive operator scale-down/up | Phase 11 owns; Phase 9 inherits via bats-12 health-check passing |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies (12 new bats files in Wave 0)
- [x] Sampling continuity: no 3 consecutive tasks without automated verify (every plan has bats coverage)
- [x] Wave 0 covers all MISSING references (12 RED bats files at end of Plan 09-00)
- [x] No watch-mode flags
- [x] Feedback latency < 90s
- [x] `nyquist_compliant: true` set in frontmatter (post-Wave-0 Plan 09-00 commit)

**Approval:** Wave 0 complete (Plan 09-00); 13 files committed locally; nyquist_compliant + wave_0_complete flipped to true; static bats RED (target manifests absent — Plans 09-01..09-03 own); live bats parse + auto-skip on cluster-info gate. NO push per D-08-13 (push-gate deferred to Phase 11 VAL-05).
