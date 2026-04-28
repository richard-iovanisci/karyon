---
phase: 05-workloads-health-rebuild
plan: 03
subsystem: infra
tags: [dns, k3d, flux, fix-dns, coredns]

# Dependency graph
requires:
  - phase: 05-workloads-health-rebuild
    provides: Plan 05-01 split fix-coredns Bats contract and Plan 05-02 current Taskfile task surface.
provides:
  - Hub-only stale CoreDNS NodeHosts repair script using k3d stop/start for hub-flux.
  - Flux readiness gate that counts controller deployments before wait --all.
  - Taskfile fix-dns entry that invokes scripts/fix-coredns.sh.
affects: [05-workloads-health-rebuild, fix-dns, health-check, rebuild]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Hub-only k3d stop/start repair for stale NodeHosts.
    - MED-3 count-before-wait gate for Flux controller readiness.
    - Warning-only read-only spoke DNS probe from an existing Flux controller pod.

key-files:
  created:
    - scripts/fix-coredns.sh
  modified:
    - Taskfile.yml

key-decisions:
  - "fix-coredns applies the stale k3d CoreDNS NodeHosts workaround by mutating only hub-flux."
  - "Flux controller readiness waits are guarded by a deployment count >= 4 before kubectl wait --all."
  - "Post-restart spoke DNS proof is read-only via kubectl exec into source-controller and warns rather than mutating spokes."

patterns-established:
  - "DNS repair mutation scope: k3d stop/start is allowed only for hub-flux; spokes may be named only for read-only resolution probes."
  - "Empty-set wait defense: count expected Flux deployments before running kubectl wait --all."

requirements-completed: [HEALTH-07]

# Metrics
duration: 5 min
completed: 2026-04-28
---

# Phase 05 Plan 03: CoreDNS Repair Script Summary

**Hub-only k3d stop/start DNS repair with guarded Flux readiness and Taskfile fix-dns wiring**

## Performance

- **Duration:** 5 min
- **Started:** 2026-04-28T15:29:24Z
- **Completed:** 2026-04-28T15:34:00Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Added `scripts/fix-coredns.sh`, an executable repair path for stale k3d CoreDNS NodeHosts that stop/starts only `hub-flux`.
- Added the MED-3 deployment-count gate before `kubectl wait --all`, preventing empty-set Flux readiness from passing.
- Added warning-only read-only spoke DNS probes and wired `task fix-dns` through `Taskfile.yml`.

## Task Commits

Each task was committed atomically:

1. **Task 1: Create scripts/fix-coredns.sh** - `1cc4747` (feat)
2. **Task 2: Add Taskfile fix-dns task** - `51e8566` (feat)

## Files Created/Modified

- `scripts/fix-coredns.sh` - Hub-only k3d stop/start repair script with hub node wait, Flux controller count gate, Flux check, and read-only spoke DNS probes.
- `Taskfile.yml` - Adds `fix-dns` task invoking `bash scripts/fix-coredns.sh` while preserving the existing `deploy-examples` entry.

## Decisions Made

- Kept the DNS repair mutation scope limited to `hub-flux`; the script never stop/starts or restarts spokes.
- Used a positive `deploy_count >= 4` gate before `kubectl wait --all`, matching the static test contract and the existing bootstrap defense.
- Made post-restart spoke DNS probes warning-only so the main repair succeeds when hub and Flux are healthy, while still surfacing unresolved stale DNS symptoms.

## Verification

- `bash -n scripts/fix-coredns.sh` -> passed.
- `bats tests/bats/fix-coredns-01-static.bats` -> 15 tests passed.
- `grep -F 'fix-dns:' Taskfile.yml` -> passed.
- `grep -F 'bash scripts/fix-coredns.sh' Taskfile.yml` -> passed.
- Script acceptance checks for hub-only stop/start, `flux --context k3d-hub-flux check`, `get deploy --no-headers`, `wc -l`, and forbidden spoke/CoreDNS mutation literals -> passed.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Added explicit tool gate**
- **Found during:** Task 1 (Create scripts/fix-coredns.sh)
- **Issue:** A missing `k3d`, `kubectl`, or `flux` binary would have failed as a raw shell error without the remediation-rich failure style required by the plan and existing scripts.
- **Fix:** Added a `Tool gate` section using the shared `have` helper and exact rerun guidance.
- **Files modified:** `scripts/fix-coredns.sh`
- **Verification:** `bash -n scripts/fix-coredns.sh` and `bats tests/bats/fix-coredns-01-static.bats`.
- **Committed in:** `1cc4747`

---

**Total deviations:** 1 auto-fixed (Rule 2).
**Impact on plan:** Error handling improved without changing the DNS repair contract or mutation scope.

## Issues Encountered

- Task 1's full Bats command initially failed only on the Taskfile assertion owned by Task 2. The script-specific Task 1 acceptance criteria passed; after Task 2 added `fix-dns`, the full split suite passed.

## Known Stubs

None.

## Authentication Gates

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Ready for Plan 05-04. The `fix-dns` remediation path now exists for health-check to reference when stale hub CoreDNS NodeHosts symptoms are detected.

## Self-Check: PASSED

- Confirmed SUMMARY, `scripts/fix-coredns.sh`, and `Taskfile.yml` exist on disk.
- Confirmed task commits `1cc4747` and `51e8566` exist in git history.
- Re-ran plan verification: `bash -n scripts/fix-coredns.sh` and `bats tests/bats/fix-coredns-01-static.bats` passed.

---
*Phase: 05-workloads-health-rebuild*
*Completed: 2026-04-28*
