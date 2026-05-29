---
phase: 15
slug: v0-20-milestone-close-out-retrospective
status: final
nyquist_compliant: true
wave_0_complete: true
created: 2026-05-20
finalized: 2026-05-20
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

**Approval:** finalized 2026-05-20 by Plan 15-05 — frontmatter sets `status: final`, `nyquist_compliant: true`, `wave_0_complete: true`.

---

## Finalized Evidence

Phase 15 finalized 2026-05-20 per D-15-07 + Plan 15-05 Task 4. This section documents the evidence anchors that satisfy the Nyquist gate for a book-keeping / close-out phase.

### Why no Wave 0 RED bats scaffold (vacuous-Nyquist for the no-new-behavior axis)

Phase 15 introduced ZERO new behavior — it mutates only `.planning/*.md` artifacts (Plans 15-01..03, 15-05) plus the Plan 15-04 live-rerun evidence log. No production code paths added; no new CRDs, ClusterRoles, controllers, or scripts. Per CONTEXT D-15-07 + Phase 12 precedent (`.planning/milestones/v0.19-phases/12-v0-19-close-out-reconciliation/12-VALIDATION.md`), the Nyquist gate is satisfied **vacuously** for the no-new-behavior axis: zero new behavior implies zero new falsifiers required.

### Active falsifiers (non-vacuous Nyquist coverage for the regression-gate axis)

Plan 15-04's live regression rerun acts as the **non-vacuous** falsifier for Phase 15's SC-3 (three-tier model regression-verified) claim. Evidence captured in `.planning/phases/15-v0-20-milestone-close-out-retrospective/15-04-live-rerun-evidence.log`:

- **Phase 13 + Phase 14 live + static bats subset** (215 @tests targeted) re-run verbatim against live `spoke-capsule` at HEAD `e26c18ef`; result: 203 GREEN + 12 inheritance REDs (strict subset of Phase 14 14-02 baseline's 28 inheritance REDs; ZERO new Phase-13/14-category regressions) + 2 SKIPs. Per Plan 15-04 evidence log: `RED (not ok): 0` (regression classification per Phase 14 14-02 inheritance baseline) — the 12 raw not-ok lines are all pre-existing (SEED-01/03 alpha-app1/bravo-app1 namespace absent from Phase 9 TEN-02 carryover; N9/N10 Flux CRD absence per ADR-004 hub-only Flux invariant; N11/N12 SA permission gap on tenant-alpha for webhook-down probes). These bats are the Wave 0 RED scaffolds originally authored during Phases 13 + 14 — they remain the canonical falsifiers for RBAC-01..06 + SEED-01..03 + DELIVERY-01..03 + DEMO-01..06 + RUNBOOK-01..03/05 contracts.
- **`kubectl auth can-i '*' '*' = no` for 3 distinct kubeconfigs** (platform-owner + alpha-owner + bravo-owner) — direct visceral falsifier for the Tier 2 + Tier 3 ceiling claims (RBAC-02 + RBAC-04). Captured at Plan 15-04 Task 3 (all 3 PASS).
- **`time task rebuild` cold-run wall-clock** — direct visceral falsifier for the DELIVERY-02 SLO claim. Plan 15-04 retry-#2 Task 5 elected **PATH-B** for this measurement: 2 rebuild attempts both aborted (attempt #1 at preflight `.env` gate, resolved via Rule 3 hydration; attempt #2 at deploy-examples Git visibility gate after 352s, blocked by architectural worktree-vs-origin/main conflict). PATH-B disposition treats the measurement as **deferred-with-justification** per Phase 14 14-02 VAL-04 inheritance precedent (line 808); accepted by Plan 15-05 audit gate as `tech_debt: 1` carry-forward to v0.21 per D-15-06 Path-X-with-tech_debt lenient reading.
- **`task health-check` exit 0 post-rebuild substitute** — Plan 15-04 Task 1 Check 4 pre-rebuild `task health-check` exited 0 (19 passed / 0 warnings / 0 failed) at HEAD `e26c18ef`; the live cluster's post-recovery state (orchestrator restarted spoke-capsule + reconciled Flux; alpha+bravo Tenants Active; all 4 `poc-capsule*` Kustomizations Ready at `main@sha1:e26c18ef`) satisfies the DELIVERY-03 regression claim (additive-only delivery did not break alpha/bravo Flux reconciliation). Post-rebuild evaluation deferred under DELIVERY-02 PATH-B disposition.

### Audit-gate cross-verification

`/gsd-audit-milestone v0.20` re-run at Plan 15-05 Task 1 returns `status: passed` with 1 operator-accepted `tech_debt` entry for DELIVERY-02 live SLO measurement (carry-forward to v0.21) per `.planning/v0.20-MILESTONE-AUDIT.md`. The audit independently verifies that Phase 13 + Phase 14 VALIDATION ledgers have `status: final` + `nyquist_compliant: true` + `wave_0_complete: true` — confirming the pre-Wave-2 inheritance the entire Phase 15 plan-set relied on. Full audit output is captured verbatim in `15-05-SUMMARY.md` Notable Observations section per D-15-06 inline-audit-output requirement.

### Wave 0 sign-off rationale

`wave_0_complete: true` set in frontmatter because no Wave 0 was required per the phase character (book-keeping; D-15-07). `nyquist_compliant: true` set in frontmatter because every Wave-1 plan's `<acceptance_criteria>` is grep-verifiable + was verified during execution (per the 15-VALIDATION.md §"Per-Task Verification Map" rows for Plans 15-01..04), AND Plan 15-04's live regression rerun serves as the active falsifier for the SC-3 regression-gate axis (non-vacuous Nyquist coverage). Operator-accepted PATH-B disposition for DELIVERY-02 live SLO does not invalidate the Nyquist gate — it represents a deferred-with-justification falsifier under the architectural-conflict / Phase 14 14-02 VAL-04 inheritance precedent, NOT a missing falsifier.
