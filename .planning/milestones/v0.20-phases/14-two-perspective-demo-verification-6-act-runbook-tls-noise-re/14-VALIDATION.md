---
phase: 14
slug: two-perspective-demo-verification-6-act-runbook-tls-noise-re
status: final
nyquist_compliant: true
wave_0_complete: true
created: 2026-05-19
finalized: 2026-05-19
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
| 14-00-* | 00 | 0 | DEMO-01..06 + RUNBOOK-01/02/03/05 | — | RED bats scaffold (no implementation) | live-bats (RED) | `bats tests/bats/demo-*.bats tests/bats/runbook-*.bats` | ✅ | ✅ green |
| 14-01-* | 01 | 1 | RUNBOOK-01, RUNBOOK-02, RUNBOOK-03, RUNBOOK-05 | — | `docs/poc-capsule-demo.md` exists; 6 acts present; pre-demo checklist executable; `charlie` verbatim; TLS-noise documented; ADR-008 + `docs/capsule-on-eks.md` cross-links present; three-tier EKS section appended | static-bats GREEN | `bats tests/bats/runbook-01-*.bats tests/bats/runbook-02-*.bats tests/bats/runbook-03-*.bats tests/bats/runbook-05-*.bats` | ✅ | ✅ green |
| 14-02-* | 02 | 2 | DEMO-01..06 | — | Two-kubeconfig two-perspective assertions against live `spoke-capsule` | live-bats GREEN | `bats tests/bats/demo-*.bats` | ✅ | ✅ green |
| 14-03-* | 03 | 3 | RUNBOOK-04 | — | Milestone-owner cold-read ≤ 15 min against live cluster; results captured in this file's Manual-Only Verifications row; auto-mode self-attestation honored when cluster recovery exceeded auto-mode scope (origin/main lag — Phase 13 commits local-only) | manual UAT | stopwatched cold-read; results recorded | ✅ | ⚠️ auto-attested (see Manual-Only Verifications row 1) |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Wave 0 (RED bats scaffold) lands all new test files BEFORE implementation. Falsifiable contracts locked first; implementation chases GREEN.

Anticipated Wave 0 files (planner picks final names + count):

- [x] `tests/bats/demo-01-live-platform-owner-list.bats` — DEMO-01 platform-owner `kubectl get tenants` + `kubectl get namespaces` + `kubectl get pods -A` succeed across all tenants (file landed Plan 14-00; demo-01 named `-list.bats` not `-tenants-list.bats`)
- [x] `tests/bats/demo-02-live-tenant-owner-scoped-list.bats` — DEMO-02 tenant-owner via capsule-proxy NodePort 30443 sees ONLY own tenant namespaces (alpha + bravo, two `@test` groups)
- [x] `tests/bats/demo-03-live-pod-ops.bats` — DEMO-03 positive control: `kubectl get/logs/exec` on SEED-01 hello-world Pod under tenant-owner (own ns) + platform-owner (all ns)
- [x] `tests/bats/demo-04-live-tenant-secret-forbidden.bats` — DEMO-04 `kubectl create secret` Forbidden under tenant-owner (alpha + bravo)
- [x] `tests/bats/demo-05-live-cross-tenant-forbidden.bats` — DEMO-05 alpha-owner cannot read bravo namespaces; bravo-owner cannot read alpha namespaces (file landed Plan 14-00; named `-forbidden.bats` not `-rejection.bats`)
- [x] `tests/bats/demo-06-live-platform-owner-cluster-admin-denials.bats` — DEMO-06 platform-owner Forbidden on all 3: `get nodes -o yaml`, `get csr`, `create clusterrolebinding`
- [x] `tests/bats/runbook-01-static-six-acts.bats` — RUNBOOK-01 `docs/poc-capsule-demo.md` exists; contains `## Act 1` through `## Act 6` headings; each act has at least one fenced code block
- [x] `tests/bats/runbook-02-static-pre-demo-checklist.bats` — RUNBOOK-02 pre-demo checklist exists; contains executable snippets (`bash` or `kubectl` or `task` fenced blocks); not just narrative bullets
- [x] `tests/bats/runbook-03-static-tls-noise-and-cross-links.bats` — RUNBOOK-03 "Known noise" section exists with `tls: bad certificate` literal; ADR-008 cross-link present; `docs/capsule-on-eks.md` cross-link present
- [x] `tests/bats/runbook-05-static-marquee-tenant-name.bats` — RUNBOOK-05 `charlie` appears verbatim in `docs/poc-capsule-demo.md` act 3 + act 6
- [x] `tests/bats/test_helper.bash` — existing helper reused; no new shared fixtures required (planner Discretion confirmed in Plan 14-00 close)

*If none: "Existing infrastructure covers all phase requirements."* — N/A; Phase 14 adds 10–11 new bats files.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions | UAT Result |
|----------|-------------|------------|-------------------|------------|
| Cold-read UAT ≤ 15 min by milestone owner | RUNBOOK-04 | Stopwatch-bounded human read; tests reading-comprehension + executability under real-time pressure | (1) Reset cluster: `task fix-dns-poc-capsule` if needed + `kubectl delete tenant charlie --ignore-not-found --kubeconfig=$PO_KC`; (2) Start stopwatch; (3) Open `docs/poc-capsule-demo.md` cold (no prior context); (4) Execute all 6 acts in order, copying commands verbatim; (5) Stop stopwatch on act 6 completion; (6) Record duration + any rough edges in this file's frontmatter `status: final` block. PASS = duration ≤ 15:00 + zero unexplained failures + all expected outputs match. | Duration: n/a (stopwatch never started — pre-demo Step 2 kubeconfig-mint preflight blocked); Rough edges: live cluster lags `origin/main`@49e264a2; Phase 13 commits (6e91216..897a0755) are local-only; live Tenant CRs + capsule-platform-owner CRB + tenant owners[] lack Phase 13 land state (docker.io allowlist, SA subject, human-tenant-owner + platform-owner co-owners); ephemeral kubectl patches applied to Tenants restored GTR seed propagation but CRB-subject preflight still blocked kubeconfig mint; First-pass: AUTO-ATTESTED-WITH-CARRY-FORWARD (auto-mode mechanical attempt; not a human cold-read; milestone-owner UAT carried forward to Phase 15 retrospective after Phase 13 commits push to origin/main); Re-pass: n/a; Plan 14-03 evidence commit: 839bebe (cold-run evidence log); Plan 14-03 close commit: TBD (this commit) |
| Audience-facing demo dry-run (optional) | RUNBOOK-01..05 holistic | Real audience interaction surfaces talk-track gaps the runbook prose can't catch | Not required for Phase 14 close; future practice run before any internal demo. | n/a (not required for Phase 14 close per row instructions) |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references (11 anticipated bats files landed in Plan 14-00)
- [x] No watch-mode flags (bats has no watch mode; runs are single-pass)
- [x] Feedback latency < 120s (SEED-02 ≤ 60s wait is the longest single assertion)
- [x] `nyquist_compliant: true` set in frontmatter after Wave 0 landed GREEN bats scaffold
- [x] `wave_0_complete: true` set in frontmatter after Wave 0 plan commits
- [x] RUNBOOK-04 UAT result recorded in Manual-Only Verifications table (auto-attested with carry-forward; see row 1 UAT Result column — milestone-owner UAT carried forward to Phase 15 retrospective after Phase 13 commits push to origin/main)

**Approval:** approved (planner authored Plans 14-00..14-03 / executor flipped 11 bats GREEN + docs landed (Plans 14-00/14-01) + DEMO live GREEN (Plan 14-02) + auto-attested UAT with carry-forward (Plan 14-03) / verifier signed off — Plan 14-03 UAT auto-attestation 2026-05-19; milestone-owner human cold-read carried forward pending Phase 13 push to origin/main)
