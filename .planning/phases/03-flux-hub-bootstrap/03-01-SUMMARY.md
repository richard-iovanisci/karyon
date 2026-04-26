---
phase: 03-flux-hub-bootstrap
plan: 01
subsystem: testing
tags: [bats, flux, gitops, contract-tests, wave-0]

requires:
  - phase: 02-cluster-layer
    provides: hub-flux cluster context and existing bats test conventions
provides:
  - Phase 3 Wave 0 executable Bats contract for FLUX-01 through FLUX-05
  - Static RED tests for scripts/bootstrap-flux.sh invariants
  - Static RED tests for docs/flux-hub-spoke.md content contract
  - Double-gated live destructive bootstrap idempotency proof
affects: [03-flux-hub-bootstrap, 04-spoke-registration, 06-repo-hygiene-docs-adrs]

tech-stack:
  added: []
  patterns: [bats contract tests, require_live_destructive double gate, expected-red wave-0 tests]

key-files:
  created:
    - tests/bats/bootstrap-flux-01-idempotent.bats
    - tests/bats/bootstrap-flux-02-docs.bats
  modified: []

key-decisions:
  - "Phase 3 contracts are locked as Bats tests before scripts/bootstrap-flux.sh and docs/flux-hub-spoke.md land."
  - "The live bootstrap proof is one self-contained destructive test guarded by both KARYON_LIVE_TESTS and KARYON_LIVE_TESTS_DESTRUCTIVE."

patterns-established:
  - "Wave 0 Bats suites intentionally fail static assertions until downstream implementation plans create the target artifacts."
  - "Live destructive Flux bootstrap checks must call require_live_destructive and remain independently runnable."

requirements-completed: [FLUX-01, FLUX-02, FLUX-03, FLUX-04, FLUX-05]

duration: 3min
completed: 2026-04-26
---

# Phase 3 Plan 01: Wave 0 Flux Bootstrap Contract Tests Summary

**Bats contract tests now define the Flux bootstrap script and docs invariants before Wave 1 implementation lands.**

## Performance

- **Duration:** 3min
- **Started:** 2026-04-26T18:49:37Z
- **Completed:** 2026-04-26T18:52:03Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- Created `tests/bats/bootstrap-flux-01-idempotent.bats` with 8 tests: 7 static script-contract tests plus 1 combined live/destructive idempotency and marker-survival proof.
- Created `tests/bats/bootstrap-flux-02-docs.bats` with 4 static docs-contract tests for the FLUX-05 patch-surface rules and D-14/D-15/D-16 literals.
- Verified the current Wave 0 state is RED/SKIP by design: missing Phase 3 artifacts fail static checks, and the destructive live test skips when gates are unset.

## Task Commits

Each task was committed atomically:

1. **Task 1: bootstrap flux idempotency contract** - `aa6840e` (test)
2. **Task 2: flux hub docs contract** - `3d69d05` (test)

## Files Created/Modified

- `tests/bats/bootstrap-flux-01-idempotent.bats` - 125 lines; pins FLUX-01/02/03/04, D-07, D-11, D-13, token-safety, and gitleaks advisory sentinels.
- `tests/bats/bootstrap-flux-02-docs.bats` - 58 lines; pins FLUX-05 docs rules, kustomize-controller memory patch example, skip-message cross-reference, and Phase 4 stub sentinel.
- `.planning/phases/03-flux-hub-bootstrap/03-01-SUMMARY.md` - Plan execution summary.

## Verification

- Acceptance checks passed for file existence, shebangs, `load 'test_helper'`, `${REPO_ROOT}` path wiring, `@test` counts, required literals, live-gate counts, and `bats --count`.
- `bats tests/bats/bootstrap-flux-01-idempotent.bats --tap` returned the expected RED/SKIP state: 7 static failures because `scripts/bootstrap-flux.sh` does not exist yet, and 1 skipped destructive live test.
- `bats tests/bats/bootstrap-flux-02-docs.bats --tap` returned the expected RED state: 4 static failures because `docs/flux-hub-spoke.md` does not exist yet.
- Combined plan check `bats tests/bats/bootstrap-flux-01-idempotent.bats tests/bats/bootstrap-flux-02-docs.bats --tap` parsed cleanly and returned the expected 11 static failures plus 1 destructive skip.

## Decisions Made

- Followed the reviewed 03-01 plan revision that resolves Codex HIGH-1, MEDIUM-1, MEDIUM-2, MEDIUM-3, MEDIUM-4, and LOW-2 concerns.
- Kept Phase 3 artifacts unimplemented in this plan so Wave 1 plans 03-02 and 03-03 can flip the tests green without editing the contract tests.

## Deviations from Plan

None - plan executed as written.

## Issues Encountered

None. Non-zero Bats exits are the expected Wave 0 RED state, not execution failures.

## Known Stubs

- `tests/bats/bootstrap-flux-02-docs.bats:55` contains the word `placeholder` in a comment describing the intentional D-14 Phase 4 HTML-comment stub that Wave 1 docs must include. This is a test-contract reference, not a product stub.

## User Setup Required

None. The destructive live test remains skipped unless `KARYON_LIVE_TESTS=1 KARYON_LIVE_TESTS_DESTRUCTIVE=1` is explicitly set.

## Next Phase Readiness

Wave 1 plans can now implement `scripts/bootstrap-flux.sh` and `docs/flux-hub-spoke.md` against these fixed contracts. Plans 03-02 and 03-03 should flip the static assertions green; the combined live destructive test remains reserved for an explicit gated run.

## Self-Check: PASSED

- Found created files: `tests/bats/bootstrap-flux-01-idempotent.bats`, `tests/bats/bootstrap-flux-02-docs.bats`, `.planning/phases/03-flux-hub-bootstrap/03-01-SUMMARY.md`.
- Found task commits: `aa6840e`, `3d69d05`.

---
*Phase: 03-flux-hub-bootstrap*
*Completed: 2026-04-26*
