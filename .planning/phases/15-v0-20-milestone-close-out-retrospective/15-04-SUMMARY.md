---
phase: 15-v0-20-milestone-close-out-retrospective
plan: 04
subsystem: testing
tags: [bookkeeping, live-regression, bats, slo, close-out, v0.20, preflight-halt, origin-main-drift]

# Dependency graph
requires:
  - phase: 13-rbac-narrowing-globaltenantresource-seed-delivery-mechanism
    provides: "Phase 13 RBAC + SEED + DELIVERY bats inventory targeted by Plan 15-04 live regression rerun"
  - phase: 14-two-perspective-demo-verification-6-act-runbook-tls-noise-re
    provides: "Phase 14 DEMO + RUNBOOK bats inventory + 14-02-full-suite-evidence.log shape inherited; UAT auto-attested-with-carry-forward (Plan 14-03) targeted for retirement by Plan 15-04 GREEN"
provides:
  - "Evidence log artifact (PREFLIGHT_HALT disposition; live regression NOT EXECUTED — origin/main drift gates Tasks 2-6)"
  - "Reproduction of Phase 14 Plan 14-03 disposition (auto-attested-with-carry-forward; same root cause: origin/main lags HEAD)"
  - "Operator-action prompt: `git push origin main` is the only blocker between current state and Plan 15-04 GREEN rerun"
affects: [15-05-audit-gate, milestone-close, v0.20-ready-to-archive]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "PREFLIGHT_HALT disposition pattern — when Task 1 Check 1 (origin/main currency) fails operationally, evidence log captures HALT verbatim, downstream tasks deferred, SUMMARY surfaces blocker + remediation pathway"

key-files:
  created:
    - .planning/phases/15-v0-20-milestone-close-out-retrospective/15-04-live-rerun-evidence.log
    - .planning/phases/15-v0-20-milestone-close-out-retrospective/15-04-SUMMARY.md
  modified: []

key-decisions:
  - "PREFLIGHT_HALT on Task 1 Check 1: origin/main is 65 commits BEHIND HEAD; live cluster reconciles from origin/main, so bats subset against the cluster would assert against state that doesn't exist on the cluster (false-negative REDs)"
  - "Plan 15-04 does NOT push (Git Safety Protocol per orchestrator instructions); operator (or separately authorized agent) must `git push origin main` to advance origin/main at-or-past HEAD before Plan 15-04 can produce trustworthy evidence"
  - "Pitfall 15-P8 literal PASS condition (LAG = HEAD..origin/main count == 0) is MET; operational intent of the check (origin/main at-or-past HEAD) is NOT MET because the reverse lag is 65"
  - "Tasks 2-6 NOT EXECUTED (bats subset, denial assertions, task rebuild SLO, summary table) — deferred behind PREFLIGHT_HALT; would yield false-negative REDs"

patterns-established:
  - "PREFLIGHT_HALT — Plan 15-04 Task 1 surfaces operator action and halts BEFORE running any destructive or expensive verification; mirrors Phase 14 Plan 14-03 carry-forward UAT disposition pattern"

requirements-completed: []  # No new REQ-IDs marked complete by Plan 15-04; targeted regression gates [RBAC-02, RBAC-03, RBAC-04, DELIVERY-02, DELIVERY-03] remain unverified-by-this-rerun (already validated by Phase 13/14)

regression-gates-verified: []  # PREFLIGHT_HALT — no regression gates verified by this run; all five (RBAC-02, RBAC-03, RBAC-04, DELIVERY-02, DELIVERY-03) deferred to next 15-04 rerun

# Metrics
duration: 2min
completed: 2026-05-20
---

# Phase 15 Plan 04: Live Regression Rerun — PREFLIGHT_HALT (origin/main drift)

**Plan 15-04 halted at Task 1 Check 1 — origin/main is 65 commits BEHIND local HEAD; live cluster reconciles from origin/main so bats rerun would yield false-negative REDs; operator must `git push origin main` before Plan 15-04 can produce trustworthy live regression evidence.**

## Performance

- **Duration:** ~2 min (pre-flight Check 1 only; Tasks 2-6 NOT EXECUTED)
- **Started:** 2026-05-20T10:18:49Z
- **Completed:** 2026-05-20T10:19:46Z
- **Tasks completed:** 0 of 6 (Task 1 halted with operator-action prompt)
- **Files created:** 2 (evidence log + this SUMMARY)

## Accomplishments

- Wrote evidence log header per Phase 14 14-02 shape (=== Plan 15-04 Live Regression Rerun Evidence Log === banner; UTC timestamp; operator; branch; HEAD + origin/main shas; cluster context; bats runner version)
- Ran Task 1 Check 1 (origin/main currency) verbatim; captured HEAD..origin/main count = 0 and origin/main..HEAD count = 65
- Documented full PREFLIGHT_HALT rationale in evidence log: literal PASS condition met but operational intent unmet; downstream impact on bats subset; carry-forward inheritance from Plan 14-03

## Task Commits

Plan 15-04 modified only the evidence log + this SUMMARY (no per-task code commits expected by plan design):

1. **Task 1 (partial — PREFLIGHT_HALT at Check 1):** evidence log created with header + Check 1 output + HALT documentation — see final commit below.
2-6. **NOT EXECUTED** — deferred behind PREFLIGHT_HALT (see Issues Encountered).

**Plan metadata commit:** captures `15-04-live-rerun-evidence.log` + `15-04-SUMMARY.md` (committed atomically as the plan's sole artifact-producing commit).

## Files Created/Modified

- `.planning/phases/15-v0-20-milestone-close-out-retrospective/15-04-live-rerun-evidence.log` — Header + Task 1 Check 1 verbatim output + PREFLIGHT_HALT documentation (Tasks 2-6 evidence NOT captured)
- `.planning/phases/15-v0-20-milestone-close-out-retrospective/15-04-SUMMARY.md` — This file

## Decisions Made

- **PREFLIGHT_HALT at Task 1 Check 1.** The plan's literal PASS condition is `HEAD..origin/main count == 0`. This is MET (HEAD..origin/main = 0; we are not behind origin/main). HOWEVER, the operational intent of Pitfall 15-P8 is that origin/main is AT-OR-PAST HEAD, so Flux on the live cluster reconciles from a revision that contains the artifacts the bats subset asserts against. With `origin/main..HEAD = 65`, origin/main is 65 commits behind HEAD; the live cluster reconciles from `49e264a docs(v0.20): add milestone briefing` while Phase 13/14 artifacts (RBAC narrowing, GlobalTenantResource seed, two-perspective demo, runbook, TLS-noise fix) all landed in those 65 commits and are absent from the cluster's reconciled state.
- **Honor Git Safety Protocol.** Plan 15-04 does NOT push (per orchestrator instructions + global Git Safety Protocol "DO NOT push to the remote repository unless the user explicitly asks"). The operator (or a separately authorized agent) must `git push origin main` to resolve the HALT.
- **Defer Tasks 2-6 rather than run them against drifted cluster state.** Running the bats subset right now would produce REDs that are NOT Phase 13/14 regressions — they would be artifact-absent false negatives. This pollutes the evidence log and makes Plan 15-05 audit gate harder, not easier. Better to halt with a clean evidence log showing exactly which preflight check failed and why.

## Deviations from Plan

None in the strict sense — the plan explicitly documents PREFLIGHT_HALT as a valid disposition (Task 1 Check 1 HALT clause: "HALT: origin/main lags HEAD by $LAG commits; operator must `git push origin main` before Plan 15-04 proceeds"). The orchestrator instructions also explicitly call out: "If any preflight halt-condition triggers, capture the failure verbatim in the evidence log AND in your SUMMARY's deviations section, then return early with a clear 'PREFLIGHT_HALT' marker in the checkpoint return."

### Plan-spec discrepancy worth noting (no code change needed)

**1. [Spec ambiguity, not a bug] Check 1 literal condition does not match Pitfall 15-P8 operational intent**
- **Found during:** Task 1 Check 1 evaluation
- **Discrepancy:** Plan's literal check `test "$LAG" -eq 0` (where `LAG = git rev-list HEAD..origin/main --count`) only catches the case where origin/main is AHEAD of HEAD. It does NOT catch the case where origin/main LAGS HEAD (the case Plan 14-03 actually hit and the case we hit here). To catch the operational scenario, the literal check should be `test "$LAG_REVERSE" -eq 0` (where `LAG_REVERSE = git rev-list origin/main..HEAD --count`) OR a combined `git diff origin/main..HEAD --quiet` check.
- **Action:** Documented in evidence log + this SUMMARY; flagged for Plan 15-05 audit gate. Plan 15-04 itself does NOT amend the check (the plan is not modifying its own contract mid-execution); a future remediation plan or Plan 15-05 audit can decide whether to amend the literal or accept that the operational intent is the binding contract.
- **Files modified:** None
- **Verification:** Evidence log captures both `HEAD..origin/main count: 0` and `origin/main..HEAD count: 65` so reviewer has full picture.
- **Committed in:** (this plan's metadata commit)

---

**Total deviations:** 0 code-affecting deviations; 1 spec-discrepancy flagged for Plan 15-05 audit consideration
**Impact on plan:** Plan 15-04 produces only header + Check 1 evidence; downstream tasks deferred behind operator action.

## Issues Encountered

### PREFLIGHT_HALT — origin/main drift (the blocker)

- **Problem:** Local HEAD `e989979 docs(15): create phase plan` is 65 commits ahead of `origin/main` `49e264a docs(v0.20): add milestone briefing`. The live spoke-capsule cluster reconciles from origin/main via Flux. All Phase 13 + Phase 14 artifacts that the bats subset asserts against were landed in those 65 commits, so the cluster does NOT have:
  - Phase 13: RBAC narrowing (`tenant-workload-editor` ClusterRole, narrower-than-`edit`), GlobalTenantResource auto-seed (hello-world Pod + Service across every tenant namespace), additive delivery path under `pocs/capsule/`
  - Phase 14: two-perspective demo verification, 6-act runbook, TLS-noise resolution
  - Phase 15: any close-out planning artifacts
- **Resolution pathway:**
  1. Operator (or separately authorized agent) runs `git push origin main` from the canonical working copy.
  2. Wait for Flux on hub-flux to reconcile the spoke-capsule Kustomizations (`poc-capsule-spoke{,-rbac,-tenants}`) at the new origin/main revision (~30-60s typical).
  3. Re-run Plan 15-04 cold from Task 1 (the evidence log is overwritten by the new header; no state to clean up).
  4. With origin/main current, Task 1 Check 1 passes (both literal AND operational); Checks 2-6 proceed; Tasks 2-6 execute; Plan 15-04 lands GREEN.
- **Carry-forward inheritance from Plan 14-03:** This is the SAME root-cause blocker that Plan 14-03 hit (per its commit `1a5b204 docs(14-03): finalize 14-VALIDATION.md — status: final; nyquist_compliant + wave_0_complete: true; UAT auto-attested-with-carry-forward`). Plan 14-03's "auto-attested-with-carry-forward" disposition was created precisely for this scenario; Plan 15-04 inherits it until the underlying push gate clears.

### Other observations (non-blocking)

- Cluster IS reachable (`kubectl --context k3d-spoke-capsule get nodes` returned the control-plane node STATUS Ready in 20d) — Check 2 would have passed.
- Flux Kustomizations state per STATE.md note ("3 Flux Kustomizations currently SUSPENDED on hub-flux: `poc-capsule-spoke` + `poc-capsule-spoke-rbac` + `poc-capsule-spoke-tenants`; self-heals once origin/main advances past 49e264a and Flux is resumed") — would have been caught by Check 3 anyway; resolves on push + resume.

## User Setup Required

**External operator action required.** No USER-SETUP.md needed — the action is a single git command:

```bash
# From the canonical working copy (NOT this worktree):
git push origin main

# After push, optionally resume any SUSPENDED Flux Kustomizations:
flux --context k3d-hub-flux resume kustomization poc-capsule-spoke
flux --context k3d-hub-flux resume kustomization poc-capsule-spoke-rbac
flux --context k3d-hub-flux resume kustomization poc-capsule-spoke-tenants

# Verify origin/main matches HEAD (or is ahead):
git fetch origin
test "$(git rev-list origin/main..HEAD --count)" -eq 0 && echo "origin/main at-or-past HEAD"

# Then re-run Plan 15-04 cold (overwrites evidence log):
# (orchestrator should respawn the executor agent for Plan 15-04)
```

## Next Phase Readiness

- **Plan 15-04 NOT GREEN** — re-run required after `git push origin main` lands.
- **Plan 15-05 audit gate IS BLOCKED on Plan 15-04 GREEN.** Per the plan: "If ANY of the [verification greps] fail, the live regression has surfaced a Phase 13/14 regression. Per D-15-02 + D-15-06 the milestone is NOT ready_to_archive." This PREFLIGHT_HALT is NOT a Phase 13/14 regression (it's an out-of-band push gap), so the recommended orchestrator remediation pathway is:
  1. Operator pushes origin/main.
  2. Orchestrator respawns Plan 15-04 (overwrites evidence log; re-runs all 6 tasks).
  3. If Plan 15-04 re-run lands GREEN: proceed to Plan 15-05.
  4. If Plan 15-04 re-run surfaces actual Phase 13/14 regressions: orchestrator inserts remediation plan per D-15-02 (e.g., `/gsd-insert-phase 14.1`).

## Self-Check

Verifying claims before returning:

```
[FOUND] .planning/phases/15-v0-20-milestone-close-out-retrospective/15-04-live-rerun-evidence.log
[FOUND] .planning/phases/15-v0-20-milestone-close-out-retrospective/15-04-SUMMARY.md
[FOUND] Evidence log contains '=== Plan 15-04 Live Regression Rerun Evidence Log ===' header
[FOUND] Evidence log contains 'HEAD..origin/main count: 0'
[FOUND] Evidence log contains 'origin/main..HEAD count: 65'
[FOUND] Evidence log contains 'HALT: origin/main lags HEAD by 65 commits'
[FOUND] Evidence log contains 'Plan 15-04 status: PREFLIGHT_HALT (Check 1 — origin/main currency)'
```

## Self-Check: PASSED

---
*Phase: 15-v0-20-milestone-close-out-retrospective*
*Plan: 04*
*Completed: 2026-05-20 (with PREFLIGHT_HALT disposition; re-run pending operator `git push origin main`)*
