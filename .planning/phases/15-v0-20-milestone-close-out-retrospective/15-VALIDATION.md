---
phase: 15
slug: v0-20-milestone-close-out-retrospective
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-05-20
---

# Phase 15 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
>
> **Phase 15 is a book-keeping / close-out phase.** Per CONTEXT.md D-15-07 (and Phase 12 precedent), there is no Wave 0 RED bats scaffold — zero new behavior means zero new falsifiers to author. The Nyquist gate is satisfied **vacuously** for the no-new-behavior axis, and **non-vacuously** by the live regression rerun in Plan 15-04, which acts as the falsifier for Success Criterion 3 (three-tier-model regression). See `## Validation Architecture` in `15-RESEARCH.md` for the full rationale.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bats (Bash Automated Testing System) — inherited from v0.18 Phase 5 + extended through Phases 7–14 |
| **Config file** | none — bats binary discovered on PATH; test files live under `tests/bats/` |
| **Quick run command** | `bats tests/bats/rbac-{08,09,10,11}-live-*.bats tests/bats/seed-{02,03}-live-*.bats tests/bats/demo-*.bats tests/bats/negative-rbac-*.bats` (Phase 13 + Phase 14 live subset; ~minutes against live `spoke-capsule`) |
| **Full suite command** | `bats tests/bats/` (full project suite — NOT used by Phase 15 per D-15-02; documented for reference only) |
| **Estimated runtime** | ~3-5 minutes for the Phase 13 + Phase 14 live subset against a healthy `spoke-capsule`; +~200s for `task rebuild` SLO check |

---

## Sampling Rate

- **After every task commit (Plan 15-01..03 metadata plans):** No bats — these touch `.planning/*.md` only. Validation is grep + read-back of the edited file (acceptance_criteria on each task).
- **After every task commit (Plan 15-04 live regression plan):** Run the **Quick run command** subset incrementally as tasks progress (preflight → rbac live → seed live → demo live → runbook live → `task rebuild` SLO → kubeconfig denials).
- **After every plan wave:**
  - **End of Wave 1:** All 4 Wave 1 plans (15-01..04) must have GREEN evidence (REQ checkboxes flipped + STATE consistent + ROADMAP consistent + live bats GREEN + `task rebuild` SLO < 230s captured).
  - **End of Wave 2:** Plan 15-05 audit gate (`/gsd-audit-milestone v0.20`) must return `passed`; if not, Wave 2 hard-blocks per D-15-06 and remediation lands as a new plan or insert-phase.
- **Before `/gsd-verify-work` / `/gsd-audit-milestone v0.20`:** Quick run command + `task rebuild` SLO check must be GREEN; evidence committed to `15-04-live-rerun-evidence.log`.
- **Max feedback latency:** ~5 minutes for the live subset; ~200s for `task rebuild`.

---

## Per-Task Verification Map

> Phase 15 plans operate on `.planning/*.md` (Plans 15-01..03 + 15-05) and on the live `spoke-capsule` cluster (Plan 15-04). The "automated command" column shows the grep / kubectl / bats invocation each task's acceptance criteria check against. Final plan-level task IDs are planner-decided; this table is illustrative of the verification surface.

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 15-01-XX | 01 | 1 | DEMO-01..06 + RUNBOOK-01..05 (11 flips) | — | N/A (book-keeping) | grep | `grep -c '^- \[x\] \*\*\(DEMO\|RUNBOOK\)-' .planning/REQUIREMENTS.md` returns 11 | ✅ exists | ⬜ pending |
| 15-01-XX | 01 | 1 | spec deviation amends (per 15-RESEARCH §OQ table) | — | N/A | grep | inline-amend acceptance: cited Phase/D-code present in REQ text | ✅ exists | ⬜ pending |
| 15-02-XX | 02 | 1 | N/A — STATE.md | — | N/A | grep | `grep 'last_activity:' .planning/STATE.md` contains "Phase 15"; Performance Metrics table has Phase 13/14/15 rows | ✅ exists | ⬜ pending |
| 15-03-XX | 03 | 1 | N/A — ROADMAP.md | — | N/A | grep | `grep 'Phase 14.*Complete' .planning/ROADMAP.md` matches; `grep '\\| 15\\..*Complete' .planning/ROADMAP.md` matches; zero "Not started" rows remain for v0.20 phases | ✅ exists | ⬜ pending |
| 15-04-XX | 04 | 1 | RBAC-03, RBAC-04, DELIVERY-02, DELIVERY-03 (regression gates) | — | platform-owner + tenant-workload-editor identities lack cluster-admin; alpha + bravo Flux reconciliation unbroken; `task rebuild` SLO < 230s preserved | live bats | `bats tests/bats/rbac-{08,09,10,11}-live-*.bats tests/bats/seed-{02,03}-live-*.bats tests/bats/demo-*.bats tests/bats/negative-rbac-*.bats` → exits 0 | ✅ exists (Phase 13 + 14 bats) | ⬜ pending |
| 15-04-XX | 04 | 1 | RBAC-04 ceiling assert | — | platform-owner cannot wildcard | live | `kubectl --kubeconfig=$PO_KC auth can-i '*' '*'` → `no` | ✅ live | ⬜ pending |
| 15-04-XX | 04 | 1 | RBAC-02 ceiling assert | — | tenant-workload-editor cannot wildcard | live | `kubectl --kubeconfig=$TO_ALPHA_KC auth can-i '*' '*'` → `no` AND `kubectl --kubeconfig=$TO_BRAVO_KC auth can-i '*' '*'` → `no` | ✅ live | ⬜ pending |
| 15-04-XX | 04 | 1 | DELIVERY-02 SLO gate | — | `task rebuild` exits 0 in <230s post-deployment | live | `time task rebuild` then `task health-check` exit 0 | ✅ live | ⬜ pending |
| 15-05-XX | 05 | 2 | audit gate (success criterion 4) | — | N/A | gsd-cli | `/gsd-audit-milestone v0.20` returns `passed` | ✅ exists | ⬜ pending |
| 15-05-XX | 05 | 2 | retrospective (success criterion 5) | — | N/A | grep | `grep '^## Milestone: v0.20' .planning/RETROSPECTIVE.md` matches; subsections What Was Built / What Worked / What Was Inefficient / Patterns Established / OQ Resolutions / Carry-forward updates present | ✅ exists | ⬜ pending |
| 15-05-XX | 05 | 2 | parking lot reconciliation | — | N/A | grep | PROJECT.md "Carry-forward parking lot" section contains TLS-fix-at-cert-layer entry and any Phase 13/14-surfaced deferrals; no closed items remain | ✅ exists | ⬜ pending |
| 15-05-XX | 05 | 2 | VALIDATION ledger close | — | N/A | grep | `15-VALIDATION.md` frontmatter has `status: final`, `nyquist_compliant: true`, `wave_0_complete: true` | ✅ exists (this file) | ⬜ pending |
| 15-05-XX | 05 | 2 | VERIFICATION written | — | N/A | grep | `15-VERIFICATION.md` exists with `passed` status; cites Plan 15-01..05 evidence | ⬜ Wave 0 | ⬜ pending |
| 15-05-XX | 05 | 2 | milestone `ready_to_archive` | — | N/A | grep | STATE.md milestone status flipped to `ready_to_archive` (or equivalent) per `/gsd-complete-milestone v0.20` precondition contract | ✅ exists | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

**None.** Phase 15 is a book-keeping / close-out phase with no new behavior to falsify. Per CONTEXT.md D-15-07 and Phase 12 precedent (`.planning/milestones/v0.19-phases/12-v0-19-close-out-reconciliation/12-VALIDATION.md`), the Nyquist gate is satisfied vacuously for the no-new-behavior axis.

The "active falsifier" for Phase 15's regression-gate claim (Success Criterion 3: three-tier model regression-verified) is the Plan 15-04 live regression rerun:

- Pre-existing Phase 13 + Phase 14 live bats (`rbac-{08,09,10,11}-live-*.bats`, `seed-{02,03}-live-*.bats`, `demo-*.bats`, `negative-rbac-*.bats`) — these are the RED falsifiers, authored as Wave 0 scaffolds during Phases 13 + 14, that Phase 15 re-runs verbatim to assert the regression gate holds.
- `kubectl auth can-i '*' '*'` denials for both platform-owner and tenant-workload-editor identities — directly falsifies the Tier 2 + Tier 3 ceiling claims (RBAC-02 + RBAC-04).
- `task rebuild` SLO < 230s — directly falsifies the DELIVERY-02 + DELIVERY-03 regression claims (additive-only delivery preserved v0.18 SLO).

**Wave 0 sign-off:** declared satisfied at Phase 15 open. `wave_0_complete: true` will be set in frontmatter at Plan 15-05's VALIDATION-ledger close step.

*"Existing infrastructure covers all phase requirements" — confirmed: Phase 13 + Phase 14 bats inheritance + live `spoke-capsule` cluster + minted kubeconfigs + `task rebuild` chain.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Retrospective narrative quality (lessons / patterns / OQ resolutions documented coherently in `.planning/RETROSPECTIVE.md`) | Success Criterion 5 | Subjective — "captures lessons from the lean / additive milestone framing" is a quality judgment, not a grep | Reviewer reads the appended v0.20 section; sub-sections present per D-15-04 cadence (What Was Built / What Worked / What Was Inefficient / Patterns Established / OQ Resolutions / Carry-forward updates); cross-links to ADR-008 + Phase 14 D-14-01 + Phase 13 D-13-* present where relevant |
| Carry-forward parking lot completeness (no Phase 13/14-surfaced deferrals dropped) | D-15-05 | Reviewer must read Phase 13 `deferred-items.md` + Phase 14 `<deferred>` section and verify each non-trivial item is reflected in PROJECT.md's updated section | Spot-check: TLS-fix-at-cert-layer present; `task demo-capsule` wrapper present (or explicitly omitted with rationale); ADDON-01/02 + G-04 + Phase 1-5 shellcheck + markdownlint + secret management entries preserved |
| Pre-existing live cluster reachability for Plan 15-04 | D-15-02, Plan 15-04 preflight | `spoke-capsule` cluster state at execution time is operator-controlled (may need `task fix-dns-poc-capsule` invocation; may need `flux resume kustomization poc-capsule-spoke{,-rbac,-tenants}` per 15-RESEARCH §Pitfall — Phase 14 destroy-poc left them SUSPENDED) | Plan 15-04 task 1 = preflight that runs `task health-check` + `kubectl --context k3d-spoke-capsule get nodes` + checks Flux Kustomization SUSPENDED flag; if any fail, halt and surface the operator action needed |
| Operator `git push origin main` to retire `origin/main@49e264a2` lag identified in Phase 14 14-03 evidence log | D-15-02, Plan 15-04 preflight | Some bats falsifiers depend on `origin/main` being current; cannot be automated by Claude (operator credential) | Plan 15-04 preflight checks `git rev-list HEAD..origin/main --count` returns 0; if not, halts with operator-action prompt |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify (grep, bats, kubectl, gsd-cli) or are documented in Manual-Only Verifications above
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify (auto-met because Plans 15-01..03 are each a single-artifact edit with grep verification per task; Plan 15-04 has bats / kubectl per step; Plan 15-05 has gsd-cli + grep per step)
- [ ] Wave 0 covers all MISSING references — N/A (no Wave 0 per D-15-07; pre-existing Phase 13 + Phase 14 falsifiers cover the regression-gate claim)
- [ ] No watch-mode flags (book-keeping phase; one-shot bats invocation only)
- [ ] Feedback latency < ~5 min for bats subset; < ~5 min for `task rebuild` SLO check
- [ ] `nyquist_compliant: true` set in frontmatter (will be flipped at Plan 15-05's VALIDATION-ledger close step)

**Approval:** pending — finalized at Plan 15-05 close (sets `status: final`, `nyquist_compliant: true`, `wave_0_complete: true`).
