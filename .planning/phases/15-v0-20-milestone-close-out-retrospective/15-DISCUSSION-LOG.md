# Phase 15: v0.20 Milestone Close-out + Retrospective - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in 15-CONTEXT.md — this log preserves the alternatives considered and how auto-mode resolved each.

**Date:** 2026-05-20
**Phase:** 15-v0-20-milestone-close-out-retrospective
**Mode:** `--auto` — all gray areas auto-selected; recommended defaults chosen for every question without user interaction.
**Areas discussed:** Plan decomposition + wave shape, Live regression rerun scope, Spec deviation capture pattern, Retrospective shape, Carry-forward parking lot reconciliation, Audit gate failure handling, Nyquist / Wave 0 RED bats applicability.

---

## Plan Decomposition + Wave Shape

| Option | Description | Selected |
|--------|-------------|----------|
| A: 5 plans / 2 waves (compressed) | Wave 1: 4 file-disjoint parallel plans (REQUIREMENTS / STATE / ROADMAP / live regression). Wave 2: 1 sequential audit + retrospective + verifier plan. | ✓ |
| B: 7 plans / 2 waves (mirror Phase 12 exactly) | Direct copy of v0.19 Phase 12's shape, including VERIFICATION supersedure plan. | |
| C: 3 plans / 1 wave (maximum compression) | All metadata reconciliation in one plan, live regression second, audit + retrospective third. | |
| D: Single linear sequence | One plan per task, sequential, no parallelism. | |

**Auto-selected:** A — Phase 12 had heavier supersedure work (Plan 12-03 superseded Phase 11 VERIFICATION). Phase 15 has none of that since Phase 13 + Phase 14 already have `status: final`. B is overshoot; C bundles unrelated artifact families and loses Wave 1 parallelism; D loses parallelism entirely.

**Result:** D-15-01 in CONTEXT.md.

---

## Live Regression Rerun Scope (Success Criterion 3)

| Option | Description | Selected |
|--------|-------------|----------|
| A: Phase 13 + 14 live bats subset + single `task rebuild` | Targeted scope matching ROADMAP success criterion 3 literal text. | ✓ |
| B: Full project bats suite + full `task rebuild` | Re-litigates v0.18 + v0.19 ground; adds noise without signal. | |
| C: Static-only (no live cluster needed) | Fastest but fails the "live evidence" framing of the success criterion. | |

**Auto-selected:** A — ROADMAP success criterion 3 explicitly scopes to "Full Phase 13 + Phase 14 bats suite" + "v0.18 `task rebuild` SLO < 230s preserved". Don't add scope.

**Result:** D-15-02 in CONTEXT.md.

---

## Spec Deviation Capture Pattern (Success Criterion 1)

| Option | Description | Selected |
|--------|-------------|----------|
| A: Inline REQUIREMENTS.md amend (mirrors v0.19 TEN-01) | Deviations land next to the REQ they affect; single audit trail location. | ✓ |
| B: Separate deviations doc | New file; fragments audit trail. | |
| C: Capture in retrospective only | Loses REQ-line traceability. | |

**Auto-selected:** A — ROADMAP success criterion 1 explicitly cites the v0.19 TEN-01 `forceTenantPrefix: false` pattern as the reference.

**Result:** D-15-03 in CONTEXT.md.

---

## Retrospective Shape (Success Criterion 5)

| Option | Description | Selected |
|--------|-------------|----------|
| A: Append to `.planning/RETROSPECTIVE.md` (living doc) | Continues v0.18 + v0.19 pattern; existing file's header explicitly says "living document". | ✓ |
| B: Standalone `.planning/RETROSPECTIVE-v0.20.md` | Matches the literal ROADMAP text; file proliferation. | |
| C: Both | Duplication. | |

**Auto-selected:** A — ROADMAP success criterion 5 says "`RETROSPECTIVE-v0.20.md` (or equivalent)" — the "or equivalent" clause permits the living-doc pattern. v0.18 + v0.19 set the precedent.

**Result:** D-15-04 in CONTEXT.md.

---

## Carry-forward Parking Lot Reconciliation

| Option | Description | Selected |
|--------|-------------|----------|
| A: Reconcile inline in `.planning/PROJECT.md` | Canonical home for the parking lot; `/gsd-new-milestone v0.21` reads from PROJECT.md. | ✓ |
| B: New v0.21-carryover doc | Fragments; v0.21 briefing has to reconcile two sources. | |
| C: Defer to v0.21 milestone briefing entirely | Loses Phase 13/14-surfaced deferral context. | |

**Auto-selected:** A — PROJECT.md is already canonical (v0.18 → v0.19 → v0.20 transitions all touched this section).

**Result:** D-15-05 in CONTEXT.md.

---

## Audit Gate Failure Handling

| Option | Description | Selected |
|--------|-------------|----------|
| A: Hard block + remediate + rerun (no `ready_to_archive` until `passed`) | Mirrors v0.19 Phase 12 Plan 12-07 audit gate precedent. | ✓ |
| B: Accept failure as carry-forward | Defeats the audit gate's purpose. | |
| C: Soft block with manual override | Adds an unstructured override path. | |

**Auto-selected:** A — Phase 12 set this precedent (Plan 12-07 was Wave 2 / sequential / last because of this). Shipping a partially-audited milestone undermines the gate.

**Result:** D-15-06 in CONTEXT.md.

---

## Nyquist / Wave 0 RED Bats Applicability

| Option | Description | Selected |
|--------|-------------|----------|
| A: No Wave 0 RED bats — book-keeping phase; Nyquist satisfied vacuously | Zero new implementation = zero falsifiers required; VALIDATION.md documents the rationale explicitly. | ✓ |
| B: Synthetic Wave 0 plan to satisfy the gate ceremonially | Performative; produces no real falsifier. | |
| C: Skip VALIDATION.md entirely | Breaks the Nyquist ledger contract used by `/gsd-audit-milestone`. | |

**Auto-selected:** A — v0.19 Phase 12 used the same pattern (book-keeping phase with `wave_0_complete: true` documented explicitly).

**Result:** D-15-07 in CONTEXT.md.

---

## Claude's Discretion

The following items were left to planner discretion (called out in CONTEXT.md under "Claude's Discretion"):

- Exact plan boundaries within Wave 1 (may merge 15-02 + 15-03 if change surface is trivial; may split 15-04 if cluster state demands sequencing).
- Whether Plan 15-04 needs a fresh `task fix-dns-poc-capsule` invocation before bats run.
- Naming of `15-VERIFICATION.md` sections.
- Evidence-log file format (recommendation: plain `.log` matching Phase 14 precedent).
- Whether to invoke `/gsd-stats` or `/gsd-progress` mid-phase for Performance Metrics By-Phase sanity checks.
- Retrospective sub-section depth.

---

## Deferred Ideas

Captured in CONTEXT.md `<deferred>` section. Summary:

- Fixing `tls: bad certificate` capsule-controller chatter at the cert-rotation layer → parking lot.
- `task demo-capsule` Taskfile wrapper → parking lot (P31 isolation concern).
- `capsule-addon-fluxcd` Trial (ADDON-01/02) → stays on parking lot (inherited from v0.19).
- G-04 architectural decision / split-Kustomization refactor → stays on parking lot (inherited from v0.19).
- v0.21 milestone briefing + planning → runs after `/gsd-complete-milestone v0.20`.
- Markdownlint / shellcheck / secret management → inherited v0.18 carryover.
- Demo runbook content edits surfaced by Plan 15-04 live rerun → Phase 14 patch (`/gsd-insert-phase 14.1`) if material, not Phase 15.
- MILESTONES.md v0.20 entry → written by `/gsd-complete-milestone v0.20` post-Phase 15.

---

*Auto-mode discussion completed in a single pass per `workflows/discuss-phase/modes/auto.md` pass-cap discipline. No follow-up passes.*
