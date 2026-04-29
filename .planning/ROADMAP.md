# Roadmap: karyon

## Milestones

- ✅ **v0.18 — karyon Lab v1** — Phases 1-6 (shipped 2026-04-29)
- 📋 **v0.19+** — TBD (run `/gsd-new-milestone` to scope the next cycle)

## Phases

<details>
<summary>✅ v0.18 — karyon Lab v1 (Phases 1-6) — SHIPPED 2026-04-29</summary>

- [x] Phase 1: Host Foundation (9/9 plans) — completed 2026-04-23
- [x] Phase 2: Cluster Layer (7/7 plans) — completed 2026-04-24
- [x] Phase 3: Flux Hub Bootstrap (6/6 plans) — completed 2026-04-27
- [x] Phase 4: Spoke Registration (5/5 plans) — completed 2026-04-28
- [x] Phase 5: Workloads + Health + Rebuild (6/6 plans) — completed 2026-04-28
- [x] Phase 6: Repo Hygiene + Docs + ADRs (8/8 plans) — completed 2026-04-29

**Total:** 6 phases, 41 plans, 90 tasks. Full archive: `.planning/milestones/v0.18-ROADMAP.md`. Audit: `.planning/milestones/v0.18-MILESTONE-AUDIT.md` (status: tech_debt — all 81 requirements satisfied; 4 code-review warnings auto-fixed in commits `ea30765`, `fa0424a`, `ab82c59`, `90e2906`; first-push CI verification deferred as user follow-up).

</details>

### 📋 v0.19+ — TBD

Run `/gsd-new-milestone` to scope the next cycle. Candidates surfaced during v0.18:

- Phase 1-5 shellcheck warning cleanup (SC2034 / SC2155 in destroy/rebuild/deploy-examples/fix-coredns/delete-clusters scripts) — would let the CI shellcheck severity gate drop from `error` back to `warning`
- Stale frontmatter reconciliation (3 phases' VALIDATION.md `nyquist_compliant`/`wave_0_complete` flags + missing SUMMARY `requirements-completed` in 3 Phase 6 plans + REQUIREMENTS.md traceability table)
- 06-07 first-push CI verification + GitHub branch-protection setup (deferred at user request from v0.18)
- Real secret management (Vault/SOPS/age) — explicitly out of scope for v0.18

## Progress

| Phase | Milestone | Plans | Status | Completed |
|-------|-----------|-------|--------|-----------|
| 1. Host Foundation | v0.18 | 9/9 | Complete | 2026-04-23 |
| 2. Cluster Layer | v0.18 | 7/7 | Complete | 2026-04-24 |
| 3. Flux Hub Bootstrap | v0.18 | 6/6 | Complete | 2026-04-27 |
| 4. Spoke Registration | v0.18 | 5/5 | Complete | 2026-04-28 |
| 5. Workloads + Health + Rebuild | v0.18 | 6/6 | Complete | 2026-04-28 |
| 6. Repo Hygiene + Docs + ADRs | v0.18 | 8/8 | Complete | 2026-04-29 |

---

*See `.planning/MILESTONES.md` for shipped-milestone summary index. Per-milestone full ROADMAP/REQUIREMENTS/AUDIT archives live under `.planning/milestones/`.*
