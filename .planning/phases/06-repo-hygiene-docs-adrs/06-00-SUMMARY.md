---
phase: 06-repo-hygiene-docs-adrs
plan: 00
subsystem: testing
tags:
  - phase-6
  - wave-0
  - bats
  - validation-scaffold

# Dependency graph
requires:
  - phase: 05-workloads-health-rebuild
    provides: existing tests/bats/destroy-rebuild-01-static.bats analog (lines 13-44, 46-63, 129-146, 175-181, 202-208) plus tests/bats/health-check-01-static.bats analog (lines 20-37) plus tests/bats/bootstrap-flux-02-docs.bats analog (lines 17-34)
provides:
  - 8 NEW parse-clean bats test scaffolds encoding the static contracts for REPO-02/03/04/05/07 and DOCS-01/02/04/05/06..10 BEFORE any implementation lands
  - per-test grep idioms (existence + literal / negative-grep / ordered-literal) inherited verbatim from the Phase 5 analog suites
  - Nyquist gate: every executor task in Phase 6 Waves 1-3 has a pre-existing <automated> test command
affects:
  - 06-01 (gitleaks pre-commit hook) — repo-hygiene-01-static.bats `REPO-04` tests
  - 06-02 (Taskfile thin-wrapper audit + .gitignore D-16 + .env.example verify) — repo-hygiene-01-static.bats `REPO-02/03` + repo-hygiene-02-taskfile.bats `REPO-05`
  - 06-03 (.markdownlint.json + 5 ADRs + docs/architecture.md) — docs-02-architecture.bats `DOCS-02` + docs-adr-template.bats `DOCS-06..10`
  - 06-04 (docs/gpu-notes.md + docs/rebuild-runbook.md) — docs-04-gpu-notes.bats `DOCS-04` + docs-05-runbook.bats `DOCS-05`
  - 06-05 (README.md rewrite) — docs-01-readme-order.bats `DOCS-01`
  - 06-06 (.github/workflows/ci.yml) — repo-hygiene-03-ci.bats `REPO-07`
  - 06-07 (one-shot gitleaks history scan + branch protection) — repo-hygiene-03-ci.bats `REPO-07 (T-06-CI-01)`

# Tech tracking
tech-stack:
  added: []  # No new dependencies — uses existing bats-core 1.11.0 and tests/bats/test_helper.bash
  patterns:
    - "Phase 6 Wave 0 bats scaffold: 8 parse-clean test files encoding all REPO/DOCS static contracts before implementation lands"
    - "Nyquist-compliant validation: every executor task has a pre-existing <automated> verify command via the bats scaffold"

key-files:
  created:
    - tests/bats/repo-hygiene-01-static.bats — REPO-02 (.gitignore D-16) / REPO-03 (.env.example) / REPO-04 (hooks/pre-commit + .gitleaks.toml) static contract (6 tests, 90 lines)
    - tests/bats/repo-hygiene-02-taskfile.bats — REPO-05 thin-wrapper + Phase 1-5 task list assertions (3 tests, 43 lines)
    - tests/bats/repo-hygiene-03-ci.bats — REPO-07 .github/workflows/ci.yml structure: 5 jobs + fetch-depth: 0 + datreeio CRDs catalog + 40-char SHA pin (6 tests, 63 lines)
    - tests/bats/docs-01-readme-order.bats — DOCS-01 README.md fresh-clone-path order + v1 doc + ADR links + 60-second TL;DR (4 tests, 64 lines)
    - tests/bats/docs-02-architecture.bats — DOCS-02 Mermaid topology: clusters / ports / k8s-net / spec.kubeConfig / 4 controllers (5 tests, 64 lines)
    - tests/bats/docs-04-gpu-notes.bats — DOCS-04 3-part GPU contract + RTX 5090 / sm_120 / 12.8 (3 tests, 41 lines)
    - tests/bats/docs-05-runbook.bats — DOCS-05 7 step markers in order + 190-second baseline + Common failures appendix (4 tests, 59 lines)
    - tests/bats/docs-adr-template.bats — DOCS-06..10 5 ADR existence + 4 Nygard sections + Status: Accepted + per-ADR keywords (8 tests, 120 lines)
  modified: []

key-decisions:
  - "Wave 0 uses three grep idioms verbatim from the Phase 5 analogs: existence + literal-presence (`destroy-rebuild-01-static.bats:13-24`), negative-grep with comment-filter (`destroy-rebuild-01-static.bats:175-181`), ordered-literal grep (`destroy-rebuild-01-static.bats:46-63` and `health-check-01-static.bats:20-37`)."
  - "All 8 bats files load `test_helper` (which provides REPO_ROOT) and root every file path under ${REPO_ROOT}, matching the existing project convention."
  - "Tests are expected to RED-FAIL until Waves 1-3 ship the implementation artifacts; this is the Nyquist gate, not a bug."

patterns-established:
  - "Phase 6 Wave 0 scaffold pattern: every observable contract gets a parse-clean bats file BEFORE implementation; downstream plans flip them green by shipping the artifacts."
  - "Per-test naming convention: `@test \"<REQ-ID> (<decision-or-note>): <plain English assertion>\"` so a downstream verifier can grep `-F 'REPO-NN'` or `-F 'DOCS-NN'` to filter by requirement."

requirements-completed: []  # Plan frontmatter requirements: [] — Wave 0 is pure scaffold, no PROJECT.md requirements close.

# Metrics
duration: 5min
completed: 2026-04-28
---

# Phase 6 Plan 00: Wave 0 Validation Scaffold Summary

**8 parse-clean bats test scaffolds (39 tests total) encoding every REPO-02/03/04/05/07 and DOCS-01/02/04/05/06..10 static contract before any implementation lands — Nyquist gate satisfied for Phase 6 Waves 1-3.**

## Performance

- **Duration:** 5 min
- **Started:** 2026-04-28T20:03:38Z
- **Completed:** 2026-04-28T20:09:37Z
- **Tasks:** 2
- **Files created:** 8
- **Files modified:** 0
- **Total test count:** 39 (15 in Task 1 + 24 in Task 2)

## Accomplishments

- Authored 3 repo-hygiene bats files (15 tests) covering REPO-02 (.gitignore D-16 expansion), REPO-03 (.env.example placeholders), REPO-04 (hooks/pre-commit + .gitleaks.toml allow-rules), REPO-05 (Taskfile.yml thin-wrapper assertion + Phase 1-5 task list), REPO-07 (.github/workflows/ci.yml 5-job structure + fetch-depth: 0 + datreeio CRDs catalog + 40-char SHA pin on every uses:).
- Authored 5 docs bats files (24 tests) covering DOCS-01 (README.md 10-section locked fresh-clone-path order + v1 doc + ADR links + 60-second TL;DR), DOCS-02 (docs/architecture.md h1-before-mermaid + Mermaid topology with clusters/ports/k8s-net/spec.kubeConfig/4 controllers), DOCS-04 (docs/gpu-notes.md 3-part GPU contract + RTX 5090 / sm_120 / 12.8 floor), DOCS-05 (docs/rebuild-runbook.md 7 step markers in order + 190-second baseline + Common failures appendix), DOCS-06..10 (5 ADRs with locked slugs + 4 Nygard sections + `Status: Accepted` + per-ADR semantic keywords).
- All 8 files use the three project grep idioms verbatim from the Phase 5 bats analogs and inherit the standard `load 'test_helper'` + `${REPO_ROOT}/...` rooting pattern.
- `bats --count tests/bats/repo-hygiene-*.bats tests/bats/docs-*.bats` reports `39`, parsing cleanly with no syntax errors.

## Task Commits

Each task was committed atomically with `--no-verify` (parallel-executor mode):

1. **Task 1: Author 4 repo-hygiene bats files (REPO-02..05/07)** — `c85942b` (test)
2. **Task 2: Author 5 docs bats files (DOCS-01/02/04/05 + DOCS-06..10)** — `7767503` (test)

_Note: This was a `type: execute` plan with no TDD frontmatter, so each task is a single test commit. Plan-level metadata commit (this SUMMARY.md) follows in the orchestrator's metadata step._

## Files Created/Modified

- `tests/bats/repo-hygiene-01-static.bats` (NEW, 90 lines, 6 tests) — REPO-02 (.gitignore D-16 expansion), REPO-03 (.env.example contract), REPO-04 (hooks/pre-commit existence + executable + strict mode + preflight-lib sourcing + canonical gitleaks invocation + remediation message + .gitleaks.toml allow-rules).
- `tests/bats/repo-hygiene-02-taskfile.bats` (NEW, 43 lines, 3 tests) — REPO-05 thin-wrapper assertion (every cmds: line is `bash scripts/<name>.sh`; no inline kubectl|docker|k3d|flux outside cmds:) + Phase 1-5 task list presence.
- `tests/bats/repo-hygiene-03-ci.bats` (NEW, 63 lines, 6 tests) — REPO-07 .github/workflows/ci.yml top-level shape, 5 required job names, gitleaks fetch-depth: 0, prune-lint-bats wiring, datreeio CRDs catalog reference, 40-char SHA pin on every uses: line.
- `tests/bats/docs-01-readme-order.bats` (NEW, 64 lines, 4 tests) — DOCS-01 README.md h1, 10-section ordered fresh-clone path, links to all v1 docs + 5 ADRs, 60-second TL;DR before installation steps.
- `tests/bats/docs-02-architecture.bats` (NEW, 64 lines, 5 tests) — DOCS-02 docs/architecture.md h1-before-mermaid (MD041), fenced mermaid block, 3 clusters with API ports, k8s-net 172.30.0.0/16 + spec.kubeConfig, 4 flux-system controllers.
- `tests/bats/docs-04-gpu-notes.bats` (NEW, 41 lines, 3 tests) — DOCS-04 docs/gpu-notes.md h1, 3-part k3d GPU contract (default-runtime + nvidia/cuda + config.toml.tmpl), RTX 5090 + sm_120 + CUDA 12.8+ floor.
- `tests/bats/docs-05-runbook.bats` (NEW, 59 lines, 4 tests) — DOCS-05 docs/rebuild-runbook.md h1, 7 step markers in strict order, Phase 5 190-second baseline, Common failures appendix with fix-dns / nvidia.com/gpu / tls-san keywords.
- `tests/bats/docs-adr-template.bats` (NEW, 120 lines, 8 tests) — DOCS-06..10 5 ADRs with locked slugs, 4 Nygard sections per ADR (Status / Context / Decision / Consequences) in order, `Accepted` literal in first 10 lines, per-ADR semantic keywords (single-WSL2 + k8s-net + Docker; k3d + Kind + --gpus all; Flux + ArgoCD + ApplicationSet + migration; hub + spec.kubeConfig + controller; v1.34.6-k3s1 + 12.8 + RTX 5090 + sm_120 + current line).

## Decisions Made

None - followed plan as specified. All three grep idioms (existence + literal, negative-grep with comment-filter, ordered-literal) were copied verbatim from the documented Phase 5 analogs in 06-PATTERNS.md "Shared Patterns" §`bats static-grep test conventions`.

## Deviations from Plan

None - plan executed exactly as written.

The plan specified each test verbatim (file paths, literals, idiom choice, line ordering); the executor authored exactly the 8 files with exactly the assertions enumerated in the `<action>` blocks of Tasks 1 and 2. Test counts per file match the plan's acceptance criteria (6 + 3 + 6 + 4 + 5 + 3 + 4 + 8 = 39, exceeding the >= 32 minimum specified in Task 2's `<done>`).

## Issues Encountered

None during the actual scaffold authoring. (One environment-level note: the parent main repo at `/home/rich/code/gsd/karyon` happens to already contain a separate Plan 06-01-style commit `2551a9d` from a prior run; this is independent of the worktree branch `worktree-agent-a2f467a439dfce42b` that this executor produced. The worktree commits do not depend on or interact with that commit; the orchestrator owns the merge.)

## TDD Gate Compliance

Not applicable — plan frontmatter is `type: execute` (not `type: tdd`). Both task commits use `test(...)` prefix because the artifacts are themselves bats test files; no `feat(...)` GREEN gate is required since the implementation artifacts that turn these tests green are owned by Plans 06-01 through 06-07.

## Verification

- `bats --count tests/bats/repo-hygiene-*.bats tests/bats/docs-*.bats` → `39` (no parse errors).
- All 8 files exist as committed git objects on branch `worktree-agent-a2f467a439dfce42b`.
- Each file starts with literal `#!/usr/bin/env bats` and contains literal `load 'test_helper'`.
- Per-file test counts: 6 / 3 / 6 / 4 / 5 / 3 / 4 / 8 (sum = 39).
- Manual sanity (`bats tests/bats/repo-hygiene-01-static.bats`) confirms tests RED-FAIL on missing artifacts (e.g., `.gitleaks.toml` not present yet) — this is the Nyquist gate, not a bug. Tests turn green automatically when Waves 1-3 ship the artifacts.

## Notes

All tests are RED-FAIL by design until Waves 1-3 ship the artifacts; this is the Nyquist gate per Phase 6 06-VALIDATION.md. The 8 NEW bats files complete Wave 0; downstream plans (06-01 through 06-07) own the implementation that flips each test green without modifying the test file itself.

Existing test reused verbatim per 06-VALIDATION.md: `tests/bats/destroy-rebuild-01-static.bats` covers REPO-06 (DESTROY-01..02 confirmation) and is invoked by the `prune-lint-bats` CI job (D-12). No duplication needed.

DOCS-03 is excluded from Wave 0 — already complete from Phase 3 (`docs/flux-hub-spoke.md`).

## Next Phase Readiness

- 8 bats scaffolds ready; downstream Phase 6 Waves 1-3 plans can now ship implementation against pre-existing automated tests.
- `bats --count tests/bats/repo-hygiene-*.bats tests/bats/docs-*.bats` is the canonical Phase 6 quick-run verification command (per 06-VALIDATION.md).

## Self-Check: PASSED

**Files (8/8 verified present in worktree):**
- FOUND: tests/bats/repo-hygiene-01-static.bats
- FOUND: tests/bats/repo-hygiene-02-taskfile.bats
- FOUND: tests/bats/repo-hygiene-03-ci.bats
- FOUND: tests/bats/docs-01-readme-order.bats
- FOUND: tests/bats/docs-02-architecture.bats
- FOUND: tests/bats/docs-04-gpu-notes.bats
- FOUND: tests/bats/docs-05-runbook.bats
- FOUND: tests/bats/docs-adr-template.bats

**Commits (2/2 verified in git log):**
- FOUND: c85942b (Task 1: repo-hygiene bats scaffolds)
- FOUND: 7767503 (Task 2: docs bats scaffolds)

**Parse check:**
- `bats --count tests/bats/repo-hygiene-*.bats tests/bats/docs-*.bats` → 39 (no parse errors)

---
*Phase: 06-repo-hygiene-docs-adrs*
*Plan: 00*
*Completed: 2026-04-28*
