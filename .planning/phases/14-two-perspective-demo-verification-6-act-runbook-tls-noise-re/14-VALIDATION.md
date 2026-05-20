---
phase: 14
slug: two-perspective-demo-verification-6-act-runbook-tls-noise-re
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-05-19
---

# Phase 14 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bats-core (live cluster bats, pattern from Phase 13 `rbac-08..10`) |
| **Config file** | `tests/bats/test_helper.bash` (existing) |
| **Quick run command** | `bats tests/bats/demo-*.bats tests/bats/runbook-*.bats --duration` |
| **Full suite command** | `bats tests/bats/ --duration` (full suite — RBAC + SEED + DEMO + RUNBOOK + regression) |
| **Estimated runtime** | ~60–120 seconds (live bats against `spoke-capsule`; longest is SEED-02 fresh-tenant ≤ 60s wait) |

---

## Sampling Rate

- **After every task commit:** Run the bats files touched by that task (e.g., `bats tests/bats/demo-01-*.bats`)
- **After every plan wave:** Run `bats tests/bats/demo-*.bats tests/bats/runbook-*.bats` (Phase 14 bats subset)
- **Before `/gsd-verify-work`:** Full suite (`bats tests/bats/`) must be green against live `spoke-capsule`
- **Max feedback latency:** 120 seconds (SEED-02 ≤ 60s wait is the longest single assertion)

---

## Per-Task Verification Map

> Filled by the planner. Each `<task>` references one or more rows below; status flips during execute-phase.

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 14-00-* | 00 | 0 | DEMO-01..06 + RUNBOOK-01/02/03/05 | — | RED bats scaffold (no implementation) | live-bats (RED) | `bats tests/bats/demo-*.bats tests/bats/runbook-*.bats` | ❌ W0 | ⬜ pending |
| 14-01-* | 01 | 1 | RUNBOOK-01, RUNBOOK-02, RUNBOOK-05 | — | `docs/poc-capsule-demo.md` exists; 6 acts present; pre-demo checklist executable; `charlie` verbatim | live-bats GREEN | `bats tests/bats/runbook-01-*.bats tests/bats/runbook-02-*.bats tests/bats/runbook-05-*.bats` | ❌ W0 | ⬜ pending |
| 14-02-* | 02 | 2 | DEMO-01..06 | — | Two-kubeconfig two-perspective assertions against live `spoke-capsule` | live-bats GREEN | `bats tests/bats/demo-*.bats` | ❌ W0 | ⬜ pending |
| 14-03-* | 03 | 2 | RUNBOOK-03 | — | TLS-noise documented; ADR-008 cross-link present; `docs/capsule-on-eks.md` cross-link present (+ three-tier append if gap) | static-bats GREEN | `bats tests/bats/runbook-03-*.bats` | ❌ W0 | ⬜ pending |
| 14-04-* | 04 | 3 | RUNBOOK-04 | — | Milestone-owner cold-read ≤ 15 min against live cluster; results captured in `14-VALIDATION.md` (this file) frontmatter `status: final` | manual UAT | stopwatched cold-read; results recorded | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Wave 0 (RED bats scaffold) lands all new test files BEFORE implementation. Falsifiable contracts locked first; implementation chases GREEN.

Anticipated Wave 0 files (planner picks final names + count):

- [ ] `tests/bats/demo-01-live-platform-owner-tenants-list.bats` — DEMO-01 platform-owner `kubectl get tenants` + `kubectl get namespaces` + `kubectl get pods -A` succeed across all tenants
- [ ] `tests/bats/demo-02-live-tenant-owner-scoped-list.bats` — DEMO-02 tenant-owner via capsule-proxy NodePort 30443 sees ONLY own tenant namespaces (alpha + bravo, two `@test` groups)
- [ ] `tests/bats/demo-03-live-pod-ops.bats` — DEMO-03 positive control: `kubectl get/logs/exec` on SEED-01 hello-world Pod under tenant-owner (own ns) + platform-owner (all ns)
- [ ] `tests/bats/demo-04-live-tenant-secret-forbidden.bats` — DEMO-04 `kubectl create secret` Forbidden under tenant-owner (alpha + bravo)
- [ ] `tests/bats/demo-05-live-cross-tenant-rejection.bats` — DEMO-05 alpha-owner cannot read bravo namespaces; bravo-owner cannot read alpha namespaces
- [ ] `tests/bats/demo-06-live-platform-owner-cluster-admin-denials.bats` — DEMO-06 platform-owner Forbidden on all 3: `get nodes -o yaml`, `get csr`, `create clusterrolebinding`
- [ ] `tests/bats/runbook-01-static-six-acts.bats` — RUNBOOK-01 `docs/poc-capsule-demo.md` exists; contains `## Act 1` through `## Act 6` headings; each act has at least one fenced code block
- [ ] `tests/bats/runbook-02-static-pre-demo-checklist.bats` — RUNBOOK-02 pre-demo checklist exists; contains executable snippets (`bash` or `kubectl` or `task` fenced blocks); not just narrative bullets
- [ ] `tests/bats/runbook-03-static-tls-noise-and-cross-links.bats` — RUNBOOK-03 "Known noise" section exists with `tls: bad certificate` literal; ADR-008 cross-link present; `docs/capsule-on-eks.md` cross-link present
- [ ] `tests/bats/runbook-05-static-marquee-tenant-name.bats` — RUNBOOK-05 `charlie` appears verbatim in `docs/poc-capsule-demo.md` act 3 + act 6
- [ ] `tests/bats/test_helper.bash` — only if planner needs new shared fixtures (likely reuses existing helper)

*If none: "Existing infrastructure covers all phase requirements."* — N/A; Phase 14 adds 10–11 new bats files.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Cold-read UAT ≤ 15 min by milestone owner | RUNBOOK-04 | Stopwatch-bounded human read; tests reading-comprehension + executability under real-time pressure | (1) Reset cluster: `task fix-dns-poc-capsule` if needed + `kubectl delete tenant charlie --ignore-not-found --kubeconfig=$PO_KC`; (2) Start stopwatch; (3) Open `docs/poc-capsule-demo.md` cold (no prior context); (4) Execute all 6 acts in order, copying commands verbatim; (5) Stop stopwatch on act 6 completion; (6) Record duration + any rough edges in this file's frontmatter `status: final` block. PASS = duration ≤ 15:00 + zero unexplained failures + all expected outputs match. |
| Audience-facing demo dry-run (optional) | RUNBOOK-01..05 holistic | Real audience interaction surfaces talk-track gaps the runbook prose can't catch | Not required for Phase 14 close; future practice run before any internal demo. |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references (the 10–11 anticipated bats files above)
- [ ] No watch-mode flags (bats has no watch mode; runs are single-pass)
- [ ] Feedback latency < 120s (SEED-02 ≤ 60s wait is the longest single assertion)
- [ ] `nyquist_compliant: true` set in frontmatter after Wave 0 lands GREEN bats scaffold
- [ ] `wave_0_complete: true` set in frontmatter after Wave 0 plan commits
- [ ] RUNBOOK-04 UAT result recorded in Manual-Only Verifications table after cold-read pass

**Approval:** pending (planner fills the Per-Task Verification Map; executor flips status; verifier sets `status: final`)
