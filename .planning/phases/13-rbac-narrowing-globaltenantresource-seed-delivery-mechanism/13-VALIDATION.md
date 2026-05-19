---
phase: 13
slug: rbac-narrowing-globaltenantresource-seed-delivery-mechanism
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-05-19
wave_0_committed: 2026-05-19
---

# Phase 13 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution. Sourced from `13-RESEARCH.md` §"Validation Architecture".

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bats-core 1.11.0 |
| **Config file** | none — `tests/bats/test_helper` provides shared loader pinning `REPO_ROOT` |
| **Quick run command** | `bats tests/bats/rbac-*-static-*.bats tests/bats/seed-*-static-*.bats tests/bats/delivery-*-static-*.bats -x` |
| **Full suite command** | `bats tests/bats/ -r` |
| **Estimated runtime** | static subset: sub-second; full suite ~10 minutes (live tests gated on `kubectl --context=k3d-spoke-capsule cluster-info` probe) |

---

## Sampling Rate

- **After every task commit:** Run `bats tests/bats/{rbac,seed,delivery}-*-static-*.bats` (sub-second; static contracts only)
- **After every plan wave:** Run `bats tests/bats/{rbac,seed,delivery}-*.bats` (static + live, live tests skip without cluster probe)
- **Before `/gsd-verify-work`:** Full suite must be green: `bats tests/bats/ -r` (includes Phase 7+8+9+10+11 regression gates)
- **Max feedback latency:** ~5 seconds (static); ~10 minutes (full live)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 13-00-* | 00 | 0 | All REQs | T-13-01..T-13-07 | Wave 0 RED bats scaffold lands first | static | `bats tests/bats/{rbac,seed,delivery}-*-static-*.bats` | ❌ W0 | ⬜ pending |
| 13-01-01 | 01 | 1 | RBAC-01 | T-13-04 (RBAC least-priv) | ClusterRole narrower than `edit` (no Secret CUD, no RoleBinding, no ResourceQuota, no LimitRange) | static | `bats tests/bats/rbac-01-static-tenant-workload-editor.bats` | ❌ W0 | ⬜ pending |
| 13-01-02 | 01 | 1 | RBAC-01 | T-13-04 | Grant matrix via `kubectl auth can-i` | live | `bats tests/bats/rbac-05-live-tenant-owner-grant-matrix.bats` | ❌ W0 | ⬜ pending |
| 13-01-03 | 01 | 1 | RBAC-02 | T-13-02 (token leak) | Tenant-owner kubeconfig binds to tenant-workload-editor; `auth can-i '*' '*'` → no | live | `bats tests/bats/rbac-06-live-tenant-kubeconfig.bats` | ❌ W0 | ⬜ pending |
| 13-01-04 | 01 | 1 | RBAC-03 | T-13-05 (Flux SA regression) | Existing `gitops-reconciler` SA + `clusterRoles: [admin]` preserved | live | `bats tests/bats/rbac-07-live-flux-sa-preservation.bats` | ❌ W0 | ⬜ pending |
| 13-01-05 | 01 | 1 | RBAC-04 | T-13-03 (platform-owner ceiling) | `auth can-i '*' '*'` → no; nodes/csr/clusterrolebinding Forbidden | live | `bats tests/bats/rbac-08-live-platform-owner-grant-matrix.bats` | ❌ W0 | ⬜ pending |
| 13-02-01 | 02 | 1 | RBAC-04 | T-13-03 | Platform-owner identity = SA in `capsule-system` + dual-subject CRB | static | `bats tests/bats/rbac-02-static-platform-owner-sa.bats` | ❌ W0 | ⬜ pending |
| 13-02-02 | 02 | 1 | RBAC-05 | T-13-03 | Platform-owner Tenant CR CRUD via minted kubeconfig | live | `bats tests/bats/rbac-10-live-tenant-crud.bats` | ❌ W0 | ⬜ pending |
| 13-02-03 | 02 | 1 | RBAC-06 | T-13-03 | Platform-owner co-owner LIST/GET/EXEC into tenant ns | live | `bats tests/bats/rbac-09-live-platform-owner-kubeconfig.bats` | ❌ W0 | ⬜ pending |
| 13-02-04 | 02 | 1 | RBAC-06 | T-13-03 | Tenant CR additive co-ownership (Group + SA both in spec.owners[]) | static | `bats tests/bats/rbac-03-static-tenant-co-ownership.bats` | ❌ W0 | ⬜ pending |
| 13-03-01 | 03 | 2 | SEED-01 | T-13-06 (workload propagation) | GTR propagates to alpha + bravo namespaces | live | `bats tests/bats/seed-02-live-existing-tenants.bats` | ❌ W0 | ⬜ pending |
| 13-03-02 | 03 | 2 | SEED-02 | T-13-06 | Fresh-namespace propagation ≤ 60s | live | `bats tests/bats/seed-03-live-fresh-tenant.bats` | ❌ W0 | ⬜ pending |
| 13-03-03 | 03 | 2 | SEED-03 | T-13-06 | Pod + Service only (no Deployment/RS/extra ConfigMap) | live | `bats tests/bats/seed-04-live-shape.bats` | ❌ W0 | ⬜ pending |
| 13-03-04 | 03 | 2 | SEED-01 | T-13-06 | GTR CR + nginx Pod + Service inline shape | static | `bats tests/bats/seed-01-static-globaltenantresource.bats` | ❌ W0 | ⬜ pending |
| 13-04-01 | 04 | 3 | DELIVERY-01 | T-13-07 (P31 isolation) | New artifacts under `pocs/capsule/spoke/` + KARYON POC MOUNT preserved | static | `bats tests/bats/delivery-02-static-paths.bats` + `bats tests/bats/delivery-01-static-mount-sentinel.bats` | ❌ W0 | ⬜ pending |
| 13-04-02 | 04 | 3 | DELIVERY-02 | T-13-07 | P31 preserved (zero new spoke-capsule mentions in v0.18 scripts) | static | `bats tests/bats/poc-isolation-01-static.bats` | ✓ Phase 7 | ⬜ pending |
| 13-04-03 | 04 | 3 | DELIVERY-02 | T-13-07 | `task rebuild` SLO < 230s (gated KARYON_REBUILD_APPROVED) | live | `bats tests/bats/delivery-05-live-slo-regression.bats` | ❌ W0 | ⬜ pending |
| 13-04-04 | 04 | 3 | DELIVERY-03 | T-13-05 | Tenant CR additive-only diff (no `spec.owners[]` removals) | live | `bats tests/bats/delivery-03-live-additive-only.bats` | ❌ W0 | ⬜ pending |
| 13-04-05 | 04 | 3 | DELIVERY-03 | T-13-05 | Existing `poc-capsule-spoke` + `poc-capsule-spoke-rbac` + `poc-capsule-spoke-tenants` Flux Ks Ready=True | live | `bats tests/bats/delivery-04-live-flux-reconcile.bats` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

*Threat refs T-13-01..T-13-07 are placeholders; populated by `<threat_model>` block in each PLAN.md (per workflow §5.55 security enforcement gate).*

---

## Wave 0 Requirements

**New bats files (19 — all RED end-of-Plan-13-00 except regression-gate tests that probe pre-existing state):**

- [x] `tests/bats/rbac-01-static-tenant-workload-editor.bats` — RBAC-01 ClusterRole shape (positive grants + 4 denial categories)
- [x] `tests/bats/rbac-02-static-platform-owner-sa.bats` — D-13-06 SA file shape + dual-subject CRB
- [x] `tests/bats/rbac-03-static-tenant-co-ownership.bats` — D-13-05 + D-13-07 owner additions to alpha + bravo
- [x] `tests/bats/rbac-04-static-human-owner-sa.bats` — human-tenant-owner SA file shape per tenant
- [x] `tests/bats/rbac-05-live-tenant-owner-grant-matrix.bats` — `kubectl auth can-i` matrix per D-13-04 (RBAC-01)
- [x] `tests/bats/rbac-06-live-tenant-kubeconfig.bats` — live tenant kubeconfig RBAC-02 verification
- [x] `tests/bats/rbac-07-live-flux-sa-preservation.bats` — RBAC-03 Flux SA owner pattern regression gate
- [x] `tests/bats/rbac-08-live-platform-owner-grant-matrix.bats` — platform-owner `auth can-i` matrix (RBAC-04)
- [x] `tests/bats/rbac-09-live-platform-owner-kubeconfig.bats` — live platform-owner kubeconfig LIST + RBAC-06 co-owner
- [x] `tests/bats/rbac-10-live-tenant-crud.bats` — RBAC-05 Tenant CRUD via platform-owner kubeconfig
- [x] `tests/bats/seed-01-static-globaltenantresource.bats` — GTR CR + inline Pod + Service shape
- [x] `tests/bats/seed-02-live-existing-tenants.bats` — SEED-01 propagation to alpha + bravo namespaces
- [x] `tests/bats/seed-03-live-fresh-tenant.bats` — SEED-02 fresh-namespace propagation ≤ 60s falsifier
- [x] `tests/bats/seed-04-live-shape.bats` — SEED-03 (Pod + Service only; no Deployment/RS/extra ConfigMap)
- [x] `tests/bats/delivery-01-static-mount-sentinel.bats` — KARYON POC MOUNT sentinel preservation
- [x] `tests/bats/delivery-02-static-paths.bats` — D-13-13 file layout + DELIVERY-01
- [x] `tests/bats/delivery-03-live-additive-only.bats` — DELIVERY-03 additive-only Tenant CR diff
- [x] `tests/bats/delivery-04-live-flux-reconcile.bats` — Flux Kustomizations Ready=True after Phase 13
- [x] `tests/bats/delivery-05-live-slo-regression.bats` — DELIVERY-02 SLO regression (KARYON_REBUILD_APPROVED gated)

**Inherited bats files (re-run by Plan 13-04 verifier; NOT modified):**

- [x] `tests/bats/poc-isolation-01-static.bats` — Phase 7 P31 contract (regression gate)
- [x] `tests/bats/proxy-04-live-issue.bats` — Phase 10 PROXY-01 regression (issue-tenant-kubeconfig.sh EDITS must not regress)
- [x] `tests/bats/capsule-install-09-live-adr-004.bats` — Phase 8 ADR-004 regression (no Flux on spoke-capsule)
- [x] `tests/bats/tenants-04-static-dependson.bats` — Phase 9 P32 dependsOn chain regression
- [x] `tests/bats/push-gate-02-static-capsuleconfig.bats` — Phase 11 D-11-02 userGroups regression
- [x] `tests/bats/push-gate-03-static-tenant-ns-label.bats` — Phase 11 D-11-03 tenant ns label regression

**Framework dependencies:** bats-core 1.11.0 already installed and verified (no Wave 0 install).

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| `task rebuild` SLO < 230s regression | DELIVERY-02 | Requires KARYON_REBUILD_APPROVED=1 env (Phase 11 carryover); destructive and slow (~3 min) | Set env, run `KARYON_REBUILD_APPROVED=1 task rebuild`; assert wall-clock < 230s; `bats tests/bats/delivery-05-live-slo-regression.bats` is the automated wrapper but the gate is opt-in |
| Demo runbook executable cold in ≤ 15 min by teammate (RUNBOOK-04 — Phase 14 concern) | (Phase 14) | UAT requires a human reader | Phase 14 owns; not in Phase 13 scope |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references (19 new bats files — one more than originally planned 18; delivery-02 + delivery-05 split-out for clarity)
- [x] No watch-mode flags
- [x] Feedback latency < 5s (static) / < 10min (full live)
- [x] `nyquist_compliant: true` set in frontmatter (Plan 13-00 landed all RED bats files at commit bb51bec on 2026-05-19)
- [x] `wave_0_complete: true` set in frontmatter (Plan 13-00 commit bb51bec)

**Approval:** Wave 0 complete — Plan 13-00 commit `bb51bec` lands 19 RED bats files. Plan 13-04 verifier confirms inheritance regressions (if any) and dispositions.
