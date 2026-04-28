---
phase: 05-workloads-health-rebuild
plan: 04
subsystem: infra
tags: [health-check, read-only, flux, dns, gpu]

# Dependency graph
requires:
  - phase: 05-workloads-health-rebuild
    provides: Plan 05-01 health-check static contract, Plan 05-02 workload examples, and Plan 05-03 fix-dns remediation path.
provides:
  - Read-only ordered health-check script for clusters, Flux, spoke Kustomizations, DNS, GPU capacity, TLS SANs, and workloads.
  - Taskfile health-check entry that delegates to scripts/health-check.sh.
affects: [05-workloads-health-rebuild, health-check, rebuild, phase5]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Read-only health gate with remediation-rich fail-fast messages.
    - In-hub DNS proof by execing into existing source-controller instead of creating a probe pod.
    - Flux controller deployment count gate before kubectl wait --all.

key-files:
  created:
    - scripts/health-check.sh
  modified:
    - Taskfile.yml

key-decisions:
  - "health-check remains read-only; stale hub DNS failures point to task fix-dns instead of mutating cluster state."
  - "The in-hub DNS proof uses source-controller getent probes for both spokes, satisfying the HIGH-2 read-only contract."
  - "Flux controller readiness waits are guarded by deployment count >= 4 before kubectl wait --all."

patterns-established:
  - "Health gate order: clusters/nodes, Flux controllers, spoke Kustomizations, hub DNS, GPU capacity, TLS SANs, workload proofs."
  - "Read-only DNS probe: kubectl exec into deploy/source-controller with getent hosts for each spoke hostname."

requirements-completed: [HEALTH-01, HEALTH-02, HEALTH-03, HEALTH-04, HEALTH-05, HEALTH-06, HEALTH-07, DEP-01, DEP-02, DEP-03]

# Metrics
duration: 5 min
completed: 2026-04-28
---

# Phase 05 Plan 04: Read-Only Health Check Summary

**Read-only ordered health gate proving clusters, Flux, spoke routing, DNS, GPU capacity, TLS SANs, and workload readiness**

## Performance

- **Duration:** 5 min
- **Started:** 2026-04-28T15:35:40Z
- **Completed:** 2026-04-28T15:40:36Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Added `scripts/health-check.sh` with the required ordered sections and fail-fast remediation messages.
- Implemented the HIGH-2 DNS proof with read-only `kubectl exec deploy/source-controller -- getent hosts ...` checks for both spoke server hostnames.
- Added the MED-3 Flux deployment-count gate before `kubectl wait --all`, plus GPU capacity, TLS SAN, podinfo, and `nvidia-smi` Job/log proofs.
- Wired `task health-check` through `Taskfile.yml`.

## Task Commits

Each task was committed atomically:

1. **Task 1: Create scripts/health-check.sh** - `5b6d0a4` (feat)
2. **Task 2: Add Taskfile health-check task** - `7f317ca` (feat)

## Files Created/Modified

- `scripts/health-check.sh` - Read-only health-check script covering clusters/nodes, Flux controllers, spoke Kustomizations, DNS, GPU, TLS, and workload proofs.
- `Taskfile.yml` - Adds `health-check` task invoking `bash scripts/health-check.sh`.

## Decisions Made

- Kept health-check read-only; it never applies, deletes, creates probe pods, or stop/starts clusters.
- Used explicit source-controller `getent hosts` probes rather than a temporary pod so the DNS check runs from inside the hub cluster without mutation.
- Used a positive Flux controller count gate before waiting on all deployments to avoid empty-set pass-through.

## Verification

- `bash -n scripts/health-check.sh` -> passed.
- `bats tests/bats/health-check-01-static.bats` -> 15 tests passed.
- `grep -F 'health-check:' Taskfile.yml && grep -F 'bash scripts/health-check.sh' Taskfile.yml` -> passed.
- Literal acceptance checks for the seven ordered sections, `--timeout=180s`, `first-pull GPU device-plugin`, `Fix: task fix-dns`, `nvidia.com/gpu`, `logs job/nvidia-smi`, source-controller DNS probes, `get deploy --no-headers`, and `wc -l` -> passed.
- Comment-filtered mutation scan for `kubectl apply`, `kubectl delete`, `kubectl run`, `k3d cluster stop`, and `k3d cluster start` -> passed.
- Optional live `bash scripts/health-check.sh` was not run; the plan marks it optional and the static contract is the required verification for this plan.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- Task 1's full Bats suite initially failed only on the Taskfile wiring assertion owned by Task 2. All script-owned checks passed before the Task 1 commit; after Task 2 added `health-check`, the full 15-test suite passed.

## Known Stubs

None.

## Authentication Gates

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Ready for Plan 05-05. The rebuild wrapper can now call `task health-check` as the final green-state gate.

## Self-Check: PASSED

- Confirmed SUMMARY, `scripts/health-check.sh`, and `Taskfile.yml` exist on disk.
- Confirmed task commits `5b6d0a4` and `7f317ca` exist in git history.
- Re-ran plan verification: `bash -n scripts/health-check.sh` and `bats tests/bats/health-check-01-static.bats` passed.

---
*Phase: 05-workloads-health-rebuild*
*Completed: 2026-04-28*
