---
phase: 05-workloads-health-rebuild
plan: 01
subsystem: testing
tags: [bats, testing, workloads, health-check, rebuild, contracts]

# Dependency graph
requires:
  - phase: 04-spoke-registration
    provides: Hub-spoke Flux reconciliation model, spoke seed Kustomizations, and live test helper gates.
provides:
  - Phase 5 Wave 0 Bats contract suites for deploy examples, kustomize builds, CoreDNS repair, health checks, destroy/rebuild, and live rebuild state checking.
  - Parse-only verification gate that downstream Plans 05-02 through 05-05 will turn green as scripts and manifests land.
affects: [05-workloads-health-rebuild, phase5, deploy-examples, fix-dns, health-check, destroy, rebuild]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Bats static contract tests with comment-aware negative greps.
    - Line-number ordering assertions for critical shell command sequencing.
    - Live destructive suite as a state checker only.

key-files:
  created:
    - tests/bats/deploy-examples-01-static.bats
    - tests/bats/deploy-examples-02-kustomize-build.bats
    - tests/bats/fix-coredns-01-static.bats
    - tests/bats/health-check-01-static.bats
    - tests/bats/destroy-rebuild-01-static.bats
    - tests/bats/phase5-02-live.bats
  modified: []

key-decisions:
  - "Plan 05-01 verifies Bats syntax with bats --count; behavioral fail-closed checks are intentionally enforced when downstream implementation artifacts land."
  - "The live Phase 5 suite is a post-rebuild state checker only and does not invoke rebuild, destroy, delete-clusters, or k3d delete commands."
  - "Static tests pin the review fixes for HIGH-1, HIGH-2, HIGH-3, MED-1, MED-2, and MED-3 before implementation begins."

patterns-established:
  - "Comment-aware negative greps: filter ^[[:space:]]*# before rejecting forbidden shell literals."
  - "Critical command ordering: capture grep -n line numbers and assert strict less-than order."
  - "Destructive live verification: require_live_destructive plus state-only assertions."

requirements-completed: [DEP-01, DEP-02, DEP-03, DEP-04, HEALTH-01, HEALTH-02, HEALTH-03, HEALTH-04, HEALTH-05, HEALTH-06, HEALTH-07, DESTROY-01, DESTROY-02, DESTROY-03, DESTROY-04, DESTROY-05, DESTROY-06]

# Metrics
duration: 5 min
completed: 2026-04-28
---

# Phase 05 Plan 01: Phase 5 Test Contracts Summary

**Phase 5 Wave 0 Bats contracts for workload deployment, health repair, destructive rebuild wrappers, and live post-rebuild state verification**

## Performance

- **Duration:** 5 min
- **Started:** 2026-04-28T15:10:32Z
- **Completed:** 2026-04-28T15:16:21Z
- **Tasks:** 5
- **Files modified:** 6

## Accomplishments

- Added six Phase 5 Bats suites that parse cleanly and pin the full Wave 0 contract surface.
- Captured the cross-review fixes: kube-context repin in rebuild, source-controller DNS probe, Git visibility gate, comment-aware prune lint, narrowed spoke mutation bans, and Flux deployment count gates.
- Kept the live destructive suite as a state checker only, so Plan 05-06 can run rebuild once and verify the resulting state without causing a second teardown.

## Task Commits

Each task was committed atomically:

1. **Task 1: Add deploy-examples static suite** - `1f1eabd` (test)
2. **Task 2: Add kustomize-build verification suite** - `ff22354` (test)
3. **Task 3: Add fix-coredns static suite** - `cb0cf1b` (test)
4. **Task 4: Add health-check static suite** - `715bbc3` (test)
5. **Task 5: Add destroy/rebuild static suite + live state-checker suite** - `40b27e8` (test)

## Files Created/Modified

- `tests/bats/deploy-examples-01-static.bats` - Static contract for examples layout, GitOps-only deploy behavior, bounded waits, Flux ordering, and HIGH-3 Git visibility checks.
- `tests/bats/deploy-examples-02-kustomize-build.bats` - Build-only `kubectl kustomize` gate for both spoke trees, skipped until Plan 05-02 manifests exist.
- `tests/bats/fix-coredns-01-static.bats` - Hub-only CoreDNS repair contract with MED-2 narrowed spoke mutation bans and MED-3 count-before-wait gate.
- `tests/bats/health-check-01-static.bats` - Read-only health-check contract with ordered gates, HIGH-2 DNS probe literals, and mutation bans.
- `tests/bats/destroy-rebuild-01-static.bats` - Destroy/rebuild wrapper contract with typed approval, strict chain ordering, HIGH-1 context pin, timing log, and MED-1 prune lint.
- `tests/bats/phase5-02-live.bats` - Destructive-gated live state checker for an externally completed rebuild run.

## Decisions Made

- Used `bats --count` as the Wave 0 verification command exactly as planned; it proves syntax and test discovery only.
- Implemented live-suite self-checks with split forbidden strings so the source file can verify absence of destructive command literals without containing those literals contiguously.
- Scoped DESTROY-04 prune lint to checked-in shell scripts under `scripts/`, filtering comments and known diagnostic `Audit:`/`Rebuild:` lines before matching prune commands.

## Verification

- `bats --count tests/bats/deploy-examples-01-static.bats tests/bats/deploy-examples-02-kustomize-build.bats tests/bats/fix-coredns-01-static.bats tests/bats/health-check-01-static.bats tests/bats/destroy-rebuild-01-static.bats tests/bats/phase5-02-live.bats` -> `71`
- File existence check for all six Bats suites -> passed.
- Literal spot-check for HIGH-1, HIGH-2, HIGH-3, MED-1, MED-3, and `require_live_destructive` -> passed.
- Negative source scan for destructive command literals in `phase5-02-live.bats` -> passed.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- The SDK rejected positional `state.record-metric` and `state.add-decision` calls with JSON error responses; reran those updates with named flags.
- `roadmap.update-plan-progress` reported success but did not modify the Phase 5 `TBD` row, so `ROADMAP.md` was updated manually to record `1/6` progress and the six Phase 5 plan names.

## Known Stubs

None - these are contract-first tests. The kustomize build suite intentionally skips behavior until Plan 05-02 manifests exist, matching the plan's standalone Wave 0 parse requirement.

## Authentication Gates

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Ready for Plan 05-02. The deploy examples implementation can now target the newly pinned static and kustomize-build contracts.

## Self-Check: PASSED

- Confirmed SUMMARY and all six created Bats suites exist on disk.
- Confirmed task commits `1f1eabd`, `ff22354`, `cb0cf1b`, `715bbc3`, and `40b27e8` exist in git history.
- Re-ran full plan verification: `bats --count ...` returned `71`.

---
*Phase: 05-workloads-health-rebuild*
*Completed: 2026-04-28*
