---
phase: 05-workloads-health-rebuild
plan: 05
subsystem: infra
tags: [destroy, rebuild, taskfile, slo, destructive-confirmation]

# Dependency graph
requires:
  - phase: 05-workloads-health-rebuild
    provides: Plan 05-02 deploy-examples, Plan 05-03 fix-dns, and Plan 05-04 health-check scripts for the rebuild chain.
provides:
  - Destructive destroy wrapper with one typed confirmation and cache-preserving teardown delegation.
  - Timed strict rebuild wrapper with ordered step markers, hub context re-pin, and hard 1200-second SLO failure.
  - Taskfile destroy and rebuild entries.
affects: [05-workloads-health-rebuild, destroy, rebuild, phase5, live-verification]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - One-prompt destructive wrappers delegate to existing scripts through SCRIPT_DIR-prefixed bash invocations.
    - Rebuild progress is mirrored to /tmp/karyon-rebuild.log with ordered markers for later state checking.
    - Rebuild re-pins kubectl context to k3d-hub-flux after cluster creation and before Flux bootstrap.

key-files:
  created:
    - scripts/destroy.sh
    - scripts/rebuild.sh
  modified:
    - Taskfile.yml

key-decisions:
  - "Plan 05-05 keeps scripts/delete-clusters.sh as the only teardown implementation; destroy is a confirmation wrapper."
  - "Plan 05-05 records rebuild step markers and elapsed seconds in /tmp/karyon-rebuild.log for the Plan 05-06 state checker."
  - "Plan 05-05 re-pins kubectl context to k3d-hub-flux between create-clusters and bootstrap-flux to satisfy HIGH-1."

patterns-established:
  - "Destructive approval path: outer wrapper prompts once, then passes explicit approval to nested destructive commands."
  - "Rebuild chain observability: emit >>> step markers immediately before each chain command."
  - "SLO enforcement: print elapsed seconds before failing if elapsed > 1200."

requirements-completed: [DESTROY-01, DESTROY-02, DESTROY-03, DESTROY-04, DESTROY-05, DESTROY-06]

# Metrics
duration: 5 min
completed: 2026-04-28
---

# Phase 05 Plan 05: Destroy and Rebuild Wrappers Summary

**Typed-confirmation destroy and timed strict rebuild wrappers with cache-safe teardown, ordered log markers, and HIGH-1 hub context re-pin**

## Performance

- **Duration:** 5 min
- **Started:** 2026-04-28T15:45:56Z
- **Completed:** 2026-04-28T15:50:32Z
- **Tasks:** 3
- **Files modified:** 3

## Accomplishments

- Added `scripts/destroy.sh` as a destructive confirmation wrapper that delegates all teardown to the cache-preserving `scripts/delete-clusters.sh`.
- Added `scripts/rebuild.sh` with the strict destroy -> create-clusters -> bootstrap-flux -> register-spokes -> deploy-examples -> health-check chain.
- Added `/tmp/karyon-rebuild.log` markers and the `rebuild elapsed seconds: N` line for Plan 05-06's live state checker.
- Added the HIGH-1 `kubectl config use-context k3d-hub-flux` pin after cluster creation and before Flux bootstrap.
- Wired `task destroy` and `task rebuild` in `Taskfile.yml`.

## Task Commits

Each task was committed atomically:

1. **Task 1: Create scripts/destroy.sh** - `8e27ab7` (feat)
2. **Task 2: Create scripts/rebuild.sh** - `db16b86` (feat)
3. **Task 3: Add Taskfile destroy/rebuild tasks** - `d8d48b9` (feat)

## Files Created/Modified

- `scripts/destroy.sh` - Requires typed `yes` unless `KARYON_DESTROY_APPROVED=yes`, then calls only `bash "${SCRIPT_DIR}/delete-clusters.sh"`.
- `scripts/rebuild.sh` - Prompts once unless `KARYON_REBUILD_APPROVED=yes`, logs ordered rebuild markers, re-pins context, runs the strict chain, and fails if elapsed time exceeds 1200 seconds.
- `Taskfile.yml` - Adds `destroy` and `rebuild` tasks while preserving prior Phase 05 task entries.

## Decisions Made

- Kept the cache-safe teardown implementation centralized in `scripts/delete-clusters.sh`; the new destroy wrapper contains no cluster deletion logic.
- Used `/tmp/karyon-rebuild.log` as the non-committed structured timing artifact, matching the Plan 05-06 verification contract.
- Implemented the kube-context pin in `rebuild.sh` rather than changing completed Phase 3/4 scripts, preserving their read-only context assertions.

## Verification

- `bash -n scripts/destroy.sh scripts/rebuild.sh` -> passed.
- `bats tests/bats/destroy-rebuild-01-static.bats` -> 15 tests passed.
- Comment-aware DESTROY-04 lint across `scripts/*.sh` -> passed with no matches.
- Source ordering check for `kubectl config use-context k3d-hub-flux` between `create-clusters.sh` and `bootstrap-flux.sh` -> passed.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- The shared `destroy-rebuild-01-static.bats` suite intentionally stayed red after Task 1 and Task 2 because it also asserts future `rebuild.sh` and Taskfile artifacts. Task-specific acceptance criteria passed before each commit; the full suite passed after Task 3.
- `state.record-metric` required named flags despite the workflow's positional example; reran it with `--phase`, `--plan`, `--duration`, `--tasks`, and `--files`.
- `roadmap.update-plan-progress` checkmarked `05-05-PLAN.md` but did not update the Phase 5 progress table row, so `ROADMAP.md` was manually corrected from `4/6` to `5/6`.

## Known Stubs

None.

## Threat Flags

None - the new destructive wrappers and rebuild log surface were explicitly covered by the plan threat model.

## Authentication Gates

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Ready for Plan 05-06. `task rebuild` now produces the structured log and state markers that the live state-checker suite can inspect without triggering a second rebuild.

## Self-Check: PASSED

- Confirmed SUMMARY, `scripts/destroy.sh`, `scripts/rebuild.sh`, and `Taskfile.yml` exist on disk.
- Confirmed task commits `8e27ab7`, `db16b86`, and `d8d48b9` exist in git history.
- Re-ran plan verification: `bash -n scripts/destroy.sh scripts/rebuild.sh` and `bats tests/bats/destroy-rebuild-01-static.bats` passed.

---
*Phase: 05-workloads-health-rebuild*
*Completed: 2026-04-28*
