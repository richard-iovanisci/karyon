# Roadmap: karyon

## Milestones

- [x] **v0.18 — karyon Lab v1** — Phases 1-6 (shipped 2026-04-29)
- [x] **v0.19 — Capsule Multi-Tenancy POC** — Phases 7-12 (shipped 2026-05-18)
- [x] **v0.20 — Capsule POC Demo & RBAC Polish** — Phases 13-15 (shipped 2026-05-29)

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

<details>
<summary>v0.20 — Capsule POC Demo & RBAC Polish (Phases 13-15) — SHIPPED 2026-05-29</summary>

- [x] Phase 13: RBAC Narrowing + GlobalTenantResource Seed + Delivery Mechanism (5/5 plans) — completed 2026-05-19
- [x] Phase 14: Two-Perspective Demo Verification + 6-Act Runbook + TLS-Noise Resolution (4/4 plans) — completed 2026-05-19
- [x] Phase 15: v0.20 Milestone Close-out + Retrospective (5/5 plans) — completed 2026-05-20

**Total:** 3 phases, 14 plans, 27 tasks. Full archive: `.planning/milestones/v0.20-ROADMAP.md`. Requirements archive: `.planning/milestones/v0.20-REQUIREMENTS.md` (23/23 v0.20 mandatory satisfied — RBAC-01..06 + SEED-01..03 + DEMO-01..06 + RUNBOOK-01..05 + DELIVERY-01..03). Audit: `.planning/milestones/v0.20-MILESTONE-AUDIT.md` (status: passed; 1 operator-accepted tech_debt — DELIVERY-02 live `task rebuild` SLO re-attestation carried forward to v0.21 per architectural rebuild-vs-worktree conflict). Delivered: a demoable three-tier Kubernetes multi-tenancy POC (Capsule) where the platform team runs the full tenant lifecycle without ever holding cluster-admin; `docs/poc-capsule-demo.md` 6-act runbook verified live end-to-end. Post-ship: namespaces-webhook `failurePolicy: Ignore→Fail` regression found + fixed (`.planning/debug/capsule-tenant-ns-claim.md`); portable setup guide written (`docs/capsule-portable-setup-guide.md`).

</details>

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
| 13. RBAC Narrowing + GlobalTenantResource Seed + Delivery | v0.20 | 5/5 | Complete | 2026-05-19 |
| 14. Two-Perspective Demo + 6-Act Runbook + TLS-Noise | v0.20 | 4/4 | Complete | 2026-05-19 |
| 15. v0.20 Close-out + Retrospective | v0.20 | 5/5 | Complete | 2026-05-20 |

---

*See `.planning/MILESTONES.md` for shipped-milestone summary index. Per-milestone full ROADMAP/REQUIREMENTS/AUDIT archives live under `.planning/milestones/`.*

To start the next milestone, run `/gsd-new-milestone`.
