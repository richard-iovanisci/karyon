# Roadmap: karyon

## Milestones

- [x] **v0.18 — karyon Lab v1** — Phases 1-6 (shipped 2026-04-29)
- [x] **v0.19 — Capsule Multi-Tenancy POC** — Phases 7-12 (shipped 2026-05-18)
- [ ] **v0.20 — Capsule POC Demo & RBAC Polish** — Phases 13-15 (active)

## Phases

<details>
<summary>v0.18 — karyon Lab v1 (Phases 1-6) — SHIPPED 2026-04-29</summary>

- [x] Phase 1: Host Foundation (9/9 plans) — completed 2026-04-23
- [x] Phase 2: Cluster Layer (7/7 plans) — completed 2026-04-24
- [x] Phase 3: Flux Hub Bootstrap (6/6 plans) — completed 2026-04-27
- [x] Phase 4: Spoke Registration (5/5 plans) — completed 2026-04-28
- [x] Phase 5: Workloads + Health + Rebuild (6/6 plans) — completed 2026-04-28
- [x] Phase 6: Repo Hygiene + Docs + ADRs (8/8 plans) — completed 2026-04-29

**Total:** 6 phases, 41 plans, 90 tasks. Full archive: `.planning/milestones/v0.18-ROADMAP.md`. Audit: `.planning/milestones/v0.18-MILESTONE-AUDIT.md` (status: tech_debt — all 81 requirements satisfied; 4 code-review warnings auto-fixed in commits `ea30765`, `fa0424a`, `ab82c59`, `90e2906`; first-push CI verification deferred as user follow-up).

</details>

<details>
<summary>v0.19 — Capsule Multi-Tenancy POC (Phases 7-12) — SHIPPED 2026-05-18</summary>

- [x] Phase 7: Foundation — POC Seam + spoke-capsule Cluster + EKS Capsule Doc (6/6 plans) — completed 2026-04-29
- [x] Phase 8: Capsule + capsule-proxy Bare-Minimum Install (5/5 plans) — completed 2026-04-30
- [x] Phase 9: Tenants + Flux Multi-Tenancy Lockdown (5/5 plans) — completed 2026-04-30
- [x] Phase 10: Tenant Owner Kubeconfigs + Capsule-Proxy Round-trip (3/3 plans) — completed 2026-05-05
- [x] Phase 11: Validation + Graduation ADR-008 (8/8 plans) — completed 2026-05-07
- [x] Phase 12: v0.19 Close-out Reconciliation (7/7 plans) — completed 2026-05-13

**Total:** 6 phases, 34 plans, 76 tasks. Full archive: `.planning/milestones/v0.19-ROADMAP.md`. Requirements archive: `.planning/milestones/v0.19-REQUIREMENTS.md` (27/27 v0.19 mandatory satisfied; ADDON-01/02 deferred to v0.20). Audit: `.planning/milestones/v0.19-MILESTONE-AUDIT.md` (status: passed; 5/5 Nyquist compliant; zero tech_debt). Graduation outcome: ADR-008 = **DEFER** (HARD-GATE 1 RED on Phase 8 G-04 cascade originally, closed via Plan 11-07 D-11-01 relocation + namespace seed); Capsule re-evaluation deferred to a future milestone.

</details>

### v0.20 — Capsule POC Demo & RBAC Polish (Phases 13-15) — ACTIVE

**Goal:** Take the v0.19 Capsule POC from "shipped + technically correct" to **"demo-ready and least-privilege-aligned"** — land the artifacts + runbook needed to walk a Mixed Eng + Cloud Ops team through a falsifiable **three-tier permission model** end-to-end, with a strict no-admin posture for every human-exercised role.

**Phase numbering:** Continues from v0.19 (Phase 12 → Phase 13). Lean / additive milestone: 2 working phases (RBAC narrowing + GlobalTenantResource seed + delivery; then two-perspective demo + runbook) plus close-out (Phase 15). No 4th phase permitted by milestone anti-scope guard — deferred-backlog items stay deferred.

**Three-tier permission model (the load-bearing architectural addition this milestone validates):**

- **Tier 1 — Cloud Ops / EKS cluster owners:** Out of scope here. Talk-track only in RUNBOOK-01 act 1 + RUNBOOK-03 production-translation cross-link to `docs/capsule-on-eks.md`.
- **Tier 2 — Karyon Platform Team (platform-owner role):** Does NOT have k8s cluster-admin. CAN add/remove Tenant CRs. IS a co-owner on every tenant (LIST/WATCH/GET/LOGS/EXEC across all tenant namespaces, bounded by a Capsule-scoped role broader than `tenant-workload-editor` but narrower than cluster-admin). Falsified by RBAC-04 (`kubectl auth can-i '*' '*'` → no), RBAC-05 (Tenant CR CRUD works), RBAC-06 (co-owner LIST/EXEC works), DEMO-06 (Forbidden actions visible).
- **Tier 3 — Tenant Developers (tenant-owner role):** Access ONLY to own tenant's namespaces. Narrower than k8s `edit`. Falsified by RBAC-02 (`kubectl auth can-i '*' '*'` → no), DEMO-02 (own-tenant-only LIST), DEMO-04 (`kubectl create secret` rejected), DEMO-05 (cross-tenant rejected).

**Load-bearing invariants every phase respects (regression gates):**

- **ADR-004** — no Flux controllers run on `spoke-capsule` (hub-only Flux)
- **P27** — every tenant Flux Kustomization MUST set `spec.serviceAccountName` explicitly
- **P29** — tenant kubeconfigs MUST NOT land in git (`.gitleaks.toml` kubeconfig-bearer-token rule + `.gitignore` globs intact)
- **P31** — `spoke-capsule` MUST NOT enter `task rebuild`; all v0.20 work under `pocs/capsule/` and `scripts/poc/capsule/` namespaces
- **KARYON POC MOUNT** sentinel stays in `clusters/hub-flux/flux-system/kustomization.yaml` — not moved or duplicated
- **`task rebuild` SLO < 230s** preserved (v0.18 baseline carried through v0.19 VAL-04)
- **Existing alpha + bravo Tenant CRs** — additive co-ownership only (RBAC-06 adds `capsule-platform-owners` group to `spec.owners[]`); existing Flux SA owner pattern (RBAC-03) preserved

**Open Questions (deferred to discuss-phase — NOT resolved at roadmap level):**

- **OQ-1** TLS noise treatment (capsule-controller `tls: bad certificate` 1Hz chatter) — owned by Phase 14 (affects RUNBOOK-03)
- **OQ-2** `tenant-workload-editor` Secrets policy (read-only / no-access / upstream-edit-equivalent) — owned by Phase 13 (affects RBAC-01)
- **OQ-3** Hello-world workload shape (Pod+Service / ConfigMap-only / Deployment+Service+ConfigMap) — owned by Phase 13 (affects SEED-03)
- **OQ-4** Delivery path (GitOps `pocs/capsule/` vs `task seed-capsule-demo`) — owned by Phase 13 (affects DELIVERY-01)
- **OQ-5** New-tenant name + provision-live vs pre-staged dance — owned by Phase 14 (affects RUNBOOK-05 + RBAC-05 demo verification)

#### Phase Summary

- [x] **Phase 13: RBAC Narrowing + GlobalTenantResource Seed + Delivery Mechanism** — Custom `tenant-workload-editor` ClusterRole replaces `admin` for humans (Tier 3); platform-owner identity + co-ownership on alpha/bravo Tenant CRs land (Tier 2); `GlobalTenantResource` auto-propagates a hello-world workload into every tenant namespace within 60s; OQ-2/3/4 resolved in discuss-phase; delivery path lands via OQ-4-chosen mechanism (GitOps or Taskfile). Wave 0 RED bats scaffolds for ClusterRole grant matrix + GlobalTenantResource propagation + platform-owner co-owner LIST/EXEC. (completed 2026-05-19)
- [ ] **Phase 14: Two-Perspective Demo Verification + 6-Act Runbook + TLS-Noise Resolution** — Verifies platform-owner (sees all tenants + co-owner access) vs tenant-owner (own-tenant-only via capsule-proxy NodePort 30443) using 2 distinct live kubeconfigs; writes `docs/poc-capsule-demo.md` 6-act walkthrough with pre-demo checklist + known-noise notes; resolves OQ-1 TLS noise treatment; resolves OQ-5 new-tenant name + live-provisioning style.
- [ ] **Phase 15: v0.20 Milestone Close-out + Retrospective** — Pattern-mirrors v0.19 Phase 12 close-out at smaller scale: flips REQ checkboxes against live evidence, updates STATE.md, runs `/gsd-audit-milestone v0.20`, writes RETROSPECTIVE-v0.20.md, prepares milestone for clean archival.

## Phase Details

### Phase 13: RBAC Narrowing + GlobalTenantResource Seed + Delivery Mechanism
**Goal**: Platform-owner (Tier 2) and tenant-owner (Tier 3) identities exist with falsifiable least-privilege ceilings; a `GlobalTenantResource` CR auto-propagates a hello-world workload into every tenant namespace within 60s; the new demo artifacts land via the OQ-4-resolved delivery mechanism without touching existing alpha/bravo Tenant CRs destructively
**Depends on**: v0.19 baseline (alpha + bravo Tenant CRs with `clusterRoles: [admin]` Flux SA owner pattern; capsule-proxy reachable on NodePort 30443; ADR-008 = DEFER stands)
**Requirements**: RBAC-01, RBAC-02, RBAC-03, RBAC-04, RBAC-05, RBAC-06, SEED-01, SEED-02, SEED-03, DELIVERY-01, DELIVERY-02, DELIVERY-03
**Open Questions to resolve in discuss-phase**: OQ-2 (`tenant-workload-editor` Secrets policy), OQ-3 (hello-world workload shape), OQ-4 (delivery path — GitOps vs Taskfile)
**Success Criteria** (what must be TRUE):
  1. **Tier 3 boundary falsifiable** — A `tenant-workload-editor` ClusterRole exists (narrower than upstream k8s `edit`: no Secret create/edit per OQ-2 resolution, no RoleBinding, no ResourceQuota, no LimitRange). Human-exercised tenant-owner kubeconfigs minted via `issue-tenant-kubeconfig.sh` bind to this ClusterRole — `kubectl auth can-i '*' '*'` returns `no` for the tenant-owner identity. Existing Flux SA owner pattern preserved (alpha + bravo Tenant CRs still carry `clusterRoles: [admin]` for their per-tenant Flux ServiceAccount; v0.19 Flux reconciliation continues unbroken).
  2. **Tier 2 boundary falsifiable** — Platform-owner identity (`capsule-platform-owners` group) demonstrably lacks cluster-admin: `kubectl auth can-i '*' '*'` returns `no` under the platform-owner kubeconfig. Platform-owner CAN perform the full Tenant CR lifecycle (`kubectl create/get/patch/delete tenant` succeeds). Platform-owner IS listed as co-owner in `spec.owners[]` on alpha + bravo Tenant CRs (additive — Flux SA owner preserved), and the new-tenant provisioning template/script defaults to including `capsule-platform-owners` in every newly-created Tenant CR's `spec.owners[]`.
  3. **GlobalTenantResource auto-propagation works within 60s** — A `GlobalTenantResource` CR (OQ-3-resolved hello-world workload shape) is reconciled into `spoke-capsule` and auto-propagates the workload into every existing tenant namespace (alpha-app1, tenant-alpha, bravo-app1, tenant-bravo). Propagation latency ≤ 60s verified via `kubectl wait --for=condition=Ready` on a fresh-namespace falsifier; bats assertion locks the contract.
  4. **Delivery mechanism is additive and P31-safe** — New demo resources (ClusterRole, GlobalTenantResource, hello-world manifest) land via the OQ-4-resolved single canonical path (GitOps `pocs/capsule/` OR `task seed-capsule-demo`). Zero new `spoke-capsule` mentions in any v0.18 default-path script (anything outside `scripts/poc/`); existing alpha + bravo Tenant CR YAML diffs are additive-only (no destructive edits to `spec.owners[]` beyond appending `capsule-platform-owners`); `task rebuild` exits 0 in < 230s post-deployment with v0.18 health-check unchanged.
  5. **Wave 0 RED bats scaffold locked before implementation** — Pre-implementation RED bats files exist covering: (a) `tenant-workload-editor` ClusterRole grant matrix (positive grants + 4 explicit denials: Secret create/edit, RoleBinding, ResourceQuota, LimitRange), (b) GlobalTenantResource propagation latency falsifier with a fresh-namespace flow, (c) platform-owner `cluster-admin` Forbidden assertions + Tenant CR CRUD positive controls, (d) P27/P29/P31 + ADR-004 regression greps. Nyquist gate held (no implementation lands without a pre-existing RED bats falsifier).
**Plans**: 5 plans

Plans:
- [x] 13-00-PLAN.md — Wave 0 RED bats scaffold (19 NEW bats files: RBAC + SEED + DELIVERY contracts locked pre-implementation; preflight verifies Phase 11 D-11-02 inheritance)
- [x] 13-01-PLAN.md — tenant-workload-editor ClusterRole + per-tenant human-tenant-owner SAs + Tenant CR additive owners[] (RBAC-01 + RBAC-02 + RBAC-03 GREEN)
- [x] 13-02-PLAN.md — platform-owner SA + dual-subject CRB + co-ownership + issue-platform-owner-kubeconfig.sh + new-tenant.sh (RBAC-04 + RBAC-05 + RBAC-06 GREEN)
- [x] 13-03-PLAN.md — GlobalTenantResource CR + hello-world Pod + Service propagation (SEED-01 + SEED-02 + SEED-03 GREEN; FQCI docker.io/library/nginx:alpine per Pitfall 13-P1)
- [x] 13-04-PLAN.md — Verifier + docs/poc-capsule.md platform-owner H2 append + 13-VALIDATION.md final (DELIVERY-01 + DELIVERY-02 + DELIVERY-03; Phase 13 close)

### Phase 14: Two-Perspective Demo Verification + 6-Act Runbook + TLS-Noise Resolution
**Goal**: Two distinct live kubeconfigs (platform-owner + tenant-owner) demonstrably enforce the three-tier permission model end-to-end; `docs/poc-capsule-demo.md` ships as a polished 6-act walkthrough executable cold in ≤ 15 minutes by a teammate; controller TLS chatter is resolved per OQ-1 (document-only recommended default)
**Depends on**: Phase 13 (ClusterRole + GlobalTenantResource + delivery mechanism + platform-owner co-ownership all live on `spoke-capsule`)
**Requirements**: DEMO-01, DEMO-02, DEMO-03, DEMO-04, DEMO-05, DEMO-06, RUNBOOK-01, RUNBOOK-02, RUNBOOK-03, RUNBOOK-04, RUNBOOK-05
**Open Questions to resolve in discuss-phase**: OQ-1 (TLS noise treatment — fix / document-only / defer), OQ-5 (new-tenant name + provision-live vs pre-staged dance)
**Success Criteria** (what must be TRUE):
  1. **Tier 2 perspective demonstrably broad** — Platform-owner kubeconfig provides cluster-scoped Tenant CR visibility (`kubectl get tenants` returns alpha + bravo + any newly-provisioned tenant) AND co-owner LIST/WATCH/GET/LOGS/EXEC across every tenant namespace through capsule-proxy (`kubectl get namespaces`, `kubectl get pods -A`, `kubectl logs`, `kubectl exec` succeed against any tenant namespace). Bats-asserted live against both kubeconfigs.
  2. **Tier 3 perspective demonstrably narrow** — Tenant-owner kubeconfig (routed through capsule-proxy on NodePort 30443) sees ONLY their own tenant's namespaces — verified for both alpha-owner and bravo-owner. `kubectl create secret` returns Forbidden under tenant-owner (RBAC-01 boundary enforcement, scriptable for the demo runbook); cross-tenant access (alpha-owner attempting bravo namespaces, and vice versa) returns Forbidden; positive control passes (tenant-owner can `kubectl get/logs/exec` on the SEED-01 hello-world workload in their own namespaces).
  3. **Tier 2 ceiling demonstrably bounded** — Platform-owner is REJECTED on at least 2 cluster-admin-only actions surfaced in the demo: `kubectl get nodes -o yaml` (or equivalent) returns Forbidden / 403; `kubectl get csr` returns Forbidden; `kubectl create clusterrolebinding ...` returns Forbidden. At least one Forbidden action lands in RUNBOOK-01 act 2 so the audience sees the ceiling in the live walkthrough.
  4. **6-act runbook ships end-to-end executable** — `docs/poc-capsule-demo.md` exists as the 6-act walkthrough (1: architecture + three-tier model articulation; 2: platform-owner role + Forbidden cluster-admin action; 3: provision new tenant live, name per OQ-5; 4: GlobalTenantResource auto-seed observation ≤ 60s; 5: two perspectives + scoped LIST + Forbidden create-secret + cross-tenant rejection + platform-owner co-owner LIST/EXEC into the same tenant; 6: cleanup — platform-owner deletes new tenant, observe Capsule unmaterialization). Includes executable pre-demo checklist (cluster reachable, fix-dns if needed, kubeconfigs staged) and known-noise notes (OQ-1 resolution for `tls: bad certificate` chatter, cross-link to ADR-008, cross-link to `docs/capsule-on-eks.md` for production-translation forward-pointer with three-tier-on-EKS mapping). UAT-verified executable in ≤ 15 minutes cold.
  5. **Runbook-driven demo is cohesive and reproducible** — The new-tenant name selected per OQ-5 appears verbatim in act-3 and across the delivery mechanism + any scripted helpers (single canonical name across runbook + scripts + bats). Every act has a concrete `kubectl` / `task` step + expected output. Pre-demo checklist is executable (not narrative).
**Plans**: 4 plans

Plans:
**Wave 1**
- [ ] 14-00-PLAN.md — Wave 0 RED bats scaffold (11 NEW bats files: DEMO-01..06 live + RUNBOOK-01/02/03/05 static; Nyquist gate; Phase 13 inheritance preflight)
- [ ] 14-01-PLAN.md — docs/poc-capsule-demo.md 6-act runbook + docs/capsule-on-eks.md three-tier append (RUNBOOK-01 + RUNBOOK-02 + RUNBOOK-03 + RUNBOOK-05 GREEN)

**Wave 2** *(blocked on Wave 1 completion)*
- [ ] 14-02-PLAN.md — DEMO-01..06 live bats GREEN against spoke-capsule + full-suite regression-clean + Tier-2 ceiling human-verify

**Wave 3** *(blocked on Wave 2 completion)*
- [ ] 14-03-PLAN.md — Milestone-owner UAT cold-read ≤ 15 min + 14-VALIDATION.md final (RUNBOOK-04; Phase 14 close)

### Phase 15: v0.20 Milestone Close-out + Retrospective
**Goal**: Reconcile v0.20 milestone artifacts to match implementation reality, flip all REQ checkboxes against live evidence, run the milestone audit, capture lessons learned, and prepare the milestone for clean archival via `/gsd-complete-milestone`. Pattern-mirrors v0.19 Phase 12 close-out at smaller scale.
**Depends on**: Phase 14 (demo runbook UAT-passed; both kubeconfigs verified live; OQ-1 TLS noise treatment documented or fixed)
**Requirements**: No new REQ-IDs (book-keeping phase). Closes the 23 v0.20 mandatory `[ ]` checkboxes for RBAC-01..06 + SEED-01..03 + DEMO-01..06 + RUNBOOK-01..05 + DELIVERY-01..03 (= 6+3+6+5+3 = 23) against the live evidence from Phases 13 + 14.
**Open Questions to resolve in discuss-phase**: None (all 5 OQs resolved in Phase 13 + Phase 14 discuss-phases by the time Phase 15 opens).
**Success Criteria** (what must be TRUE):
  1. **REQUIREMENTS.md fully reconciled** — All 23 v0.20 mandatory `[ ]` checkboxes flipped to `[x]` with phase/plan citations; Traceability table reflects final phase mapping; any spec deviations from Phase 13/14 implementation captured inline (mirrors v0.19 TEN-01 `forceTenantPrefix: false` deviation pattern from Plan 12-01).
  2. **STATE.md and ROADMAP.md consistent** — STATE.md `last_activity` advanced past Phase 14 close-out; STATE.md Performance Metrics By-Phase table reflects actual plan counts for Phases 13/14/15; ROADMAP.md Progress table refreshed (no within-document contradictions); milestone Phase Summary checkboxes all marked complete.
  3. **Three-tier model regression-verified** — Full Phase 13 + Phase 14 bats suite re-run GREEN against the live `spoke-capsule` cluster; `kubectl auth can-i '*' '*'` returns `no` for both platform-owner and tenant-workload-editor identities; existing alpha + bravo Flux reconciliation continues unbroken (RBAC-03 + DELIVERY-03 regression gates); v0.18 `task rebuild` SLO < 230s preserved (DELIVERY-02 regression gate, full live rerun).
  4. **Milestone audit passes** — `/gsd-audit-milestone v0.20` returns `passed` (zero `tech_debt`, all 23 REQs satisfied, all Nyquist VALIDATION ledgers closed for Phases 13/14 with `status: final` + `nyquist_compliant: true` + `wave_0_complete: true`).
  5. **Retrospective captured** — `RETROSPECTIVE-v0.20.md` (or equivalent) documents: lessons from the lean / additive milestone framing, OQ-1..5 resolutions and outcomes, any deviations from the original briefing, items added to or cleared from the carry-forward parking lot, suggested patterns for future lean milestones. Milestone is `ready_to_archive`.
**Plans**: TBD

## Progress

| Phase | Milestone | Plans | Status | Completed |
|-------|-----------|-------|--------|-----------|
| 1. Host Foundation | v0.18 | 9/9 | Complete | 2026-04-23 |
| 2. Cluster Layer | v0.18 | 7/7 | Complete | 2026-04-24 |
| 3. Flux Hub Bootstrap | v0.18 | 6/6 | Complete | 2026-04-27 |
| 4. Spoke Registration | v0.18 | 5/5 | Complete | 2026-04-28 |
| 5. Workloads + Health + Rebuild | v0.18 | 6/6 | Complete | 2026-04-28 |
| 6. Repo Hygiene + Docs + ADRs | v0.18 | 8/8 | Complete | 2026-04-29 |
| 7. Foundation: POC Seam + spoke-capsule + EKS Doc | v0.19 | 6/6 | Complete | 2026-04-29 |
| 8. Capsule + capsule-proxy Install | v0.19 | 5/5 | Complete | 2026-04-30 |
| 9. Tenants + Flux Multi-Tenancy Lockdown | v0.19 | 5/5 | Complete | 2026-04-30 |
| 10. Tenant Kubeconfigs + Proxy Round-trip | v0.19 | 3/3 | Complete | 2026-05-05 |
| 11. Validation + Graduation ADR-008 | v0.19 | 8/8 | Complete | 2026-05-07 |
| 12. v0.19 Close-out Reconciliation | v0.19 | 7/7 | Complete | 2026-05-13 |
| 13. RBAC Narrowing + GlobalTenantResource Seed + Delivery | v0.20 | 5/5 | Complete    | 2026-05-19 |
| 14. Two-Perspective Demo + 6-Act Runbook + TLS-Noise | v0.20 | 0/4 | Not started | - |
| 15. v0.20 Close-out + Retrospective | v0.20 | 0/TBD | Not started | - |

---

*See `.planning/MILESTONES.md` for shipped-milestone summary index. Per-milestone full ROADMAP/REQUIREMENTS/AUDIT archives live under `.planning/milestones/`.*

To start the next milestone, run `/gsd-new-milestone`.
