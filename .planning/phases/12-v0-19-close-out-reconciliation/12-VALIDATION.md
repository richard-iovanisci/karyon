---
phase: 12
slug: v0-19-close-out-reconciliation
status: final
nyquist_compliant: true
wave_0_complete: true
created: 2026-05-11
finalized: 2026-05-11
finalized_evidence: "Phase 12 is a book-keeping reconciliation phase with no own Wave-0 scaffold (per 12-VALIDATION.md §Wave 0 Requirements `None`; mutates only `.planning/*.md` files; verification surface IS file content). Phase gate `/gsd-audit-milestone v0.19` returns `passed` per 12-07-SUMMARY.md (audit re-run 2026-05-11). nyquist_compliant set true because every Wave-1 plan's `<acceptance_criteria>` is grep-verifiable and was verified during execution; wave_0_complete set true because no Wave 0 was required per the phase character (book-keeping; T-5 in 12-07 plan)."
---

# Phase 12 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
>
> **Note:** Phase 12 is a book-keeping reconciliation phase. It mutates only
> `.planning/` artifacts (REQUIREMENTS.md, ROADMAP.md, STATE.md, VERIFICATION
> supersedure, VALIDATION ledger frontmatter, stale todo). It introduces NO
> new code paths, NO new tests, and NO Nyquist test scaffold of its own. Per
> `~/.claude/get-shit-done/workflows/validate-phase.md` Step 4, a phase that
> only mutates `.planning/` files is not subject to test-coverage Nyquist
> requirements — file content IS the verification surface.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | None applicable for Phase 12 own work. The repo-wide hygiene tools (`gitleaks`, `markdownlint-cli2`) are pre-existing and cited only as live-evidence gates for success criterion 4. |
| **Config file** | `.gitleaks.toml` (existing, Plan 11-07 commit `384f859`) |
| **Quick run command** | `gitleaks detect --no-git --config .gitleaks.toml` |
| **Full suite command** | `gitleaks detect --no-git --config .gitleaks.toml && npx markdownlint-cli2 README.md docs/capsule-on-eks.md docs/poc-capsule.md` |
| **Estimated runtime** | ~10 seconds (gitleaks ~2s, markdownlint ~5s) |

---

## Sampling Rate

- **After every task commit:** n/a — Phase 12 tasks are file edits, not code changes. Verification is by file content (grep-checkable acceptance criteria in each task).
- **After every plan wave:** Spot-check by running the audit (`/gsd-audit-milestone v0.19`) after each cluster completes to detect regressions.
- **Before `/gsd-verify-work`:** Phase gate = `/gsd-audit-milestone v0.19` returns `passed` (success criterion 7) AND the two hygiene commands above return 0.
- **Max feedback latency:** ~10 seconds (hygiene checks) + audit re-run (~few seconds).

---

## Per-Task Verification Map

Phase 12 has NO new REQ-IDs. The 15 stale REQ-IDs it flips (POC-01..04, CAPCLU-01..04, EKSDOC-01, CAP-01..03, TEN-01..06) already have test coverage in prior phases' Wave-0 bats scaffolds. No new tests required. The table is intentionally minimal — per-task verification lives in each PLAN.md's `<acceptance_criteria>` blocks (grep-verifiable).

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| (n/a — book-keeping phase; tasks verified by grep on file contents) | — | — | — | — | — | — | — | — | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- None. Phase 12 has no Wave-0 scaffold requirement — no new tests are introduced and the existing repo-wide hygiene tools (`gitleaks`, `markdownlint-cli2`) are already installed and configured.

*Existing infrastructure covers all phase requirements.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| `/gsd-audit-milestone v0.19` returns `passed` | Success criterion 7 | Audit re-run is the canonical phase gate; no automated bats equivalent | Run `/gsd-audit-milestone v0.19` after all clusters complete; verify output reports `passed` and lists zero `tech_debt` items. |
| 4 VALIDATION.md frontmatter ledgers show `status: final` + `nyquist_compliant: true` + `wave_0_complete: true` for phases 7, 8, 10, 11 (and phase 9 per research recommendation) | Success criterion 6 | Frontmatter is YAML — grep + visual inspection is sufficient; no executable test needed | `grep -A 5 "^---$" .planning/phases/{07,08,09,10,11}-*/[01]*-VALIDATION.md \| head -60` and confirm each file's frontmatter |

---

## Validation Sign-Off

- [ ] All tasks have grep-verifiable `<acceptance_criteria>` (sampling-by-file-content is the verification surface for this phase)
- [ ] Sampling continuity: n/a — book-keeping phase
- [ ] Wave 0 covers all MISSING references: n/a — no Wave 0 needed
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s (hygiene checks + audit)
- [ ] `nyquist_compliant: true` set in frontmatter at phase close (manual flip — pair with phase-12 self-close task)

**Approval:** pending
