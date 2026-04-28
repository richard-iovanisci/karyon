---
phase: 05-workloads-health-rebuild
plan: 06
subsystem: live-execution
tags: [rebuild, live-destructive, timing, health-check, gpu, flux]

# Dependency graph
requires:
  - phase: 05-workloads-health-rebuild
    provides: Plans 05-02..05-05 example workloads, DNS repair, health-check, destroy wrapper, rebuild wrapper, and live state-checker contract.
  - phase: 04-spoke-registration
    provides: Hub-spoke Flux reconciliation model and spoke kubeconfig Secrets required by the rebuild chain.
provides:
  - Live destructive proof that task rebuild completes the strict chain in under 20 minutes with warm CUDA image cache.
  - Structured /tmp/karyon-rebuild.log evidence with ordered step markers, hub context pin marker, and elapsed seconds.
  - Final health, podinfo, GPU log, and Bats state-checker proof for Phase 5.
affects: [05-workloads-health-rebuild, 06-repo-hygiene-docs-adrs, task-rebuild, rebuild-runbook]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Human-gated destructive rebuild proof with one command invocation and log-only verification.
    - Live state-checker Bats suite reads post-rebuild state without invoking destructive scripts.
    - Flux visibility precheck requires clean examples/clusters paths and HEAD == origin/main before rebuild.

key-files:
  created:
    - .planning/phases/05-workloads-health-rebuild/05-06-SUMMARY.md
  modified:
    - scripts/register-spokes-for-flux.sh
    - tests/bats/register-spokes-01-static.bats

key-decisions:
  - "Plan 05-06 treats /tmp/karyon-rebuild.log as the canonical non-committed proof artifact; verification parses it without rerunning task rebuild."
  - "The final live proof requires HEAD == origin/main and clean examples/clusters paths before any destructive command runs."
  - "The failed first rebuild was resolved by preserving Phase 5 example references during spoke seed repair before accepting the second destructive approval."

patterns-established:
  - "Execution-only live tasks may have no source task commit; record the proof in the plan summary and commit only metadata."
  - "Sensitive live command output is captured to /tmp and summarized by exit codes, markers, and sanitized proof lines."

requirements-completed: [DEP-01, DEP-02, DEP-03, DEP-04, HEALTH-01, HEALTH-02, HEALTH-03, HEALTH-04, HEALTH-05, HEALTH-06, HEALTH-07, DESTROY-01, DESTROY-02, DESTROY-03, DESTROY-04, DESTROY-05, DESTROY-06]

# Metrics
duration: checkpointed; continuation live proof 5 min
completed: 2026-04-28
---

# Phase 05 Plan 06: Live Rebuild Timing Proof Summary

**Single approved destructive rebuild completed in 193 seconds with green health, podinfo, GPU, and live state-checker proofs.**

## Performance

- **Duration:** checkpointed; continuation proof ran from 2026-04-28T16:19:34Z to 2026-04-28T16:24:16Z.
- **Started:** checkpoint preconditions completed before this continuation; first failed rebuild exited after 185s before the root-cause fix.
- **Completed:** 2026-04-28T16:24:16Z.
- **Tasks:** 3 total; Task 1 checkpoint completed before continuation, Tasks 2-3 completed in this continuation.
- **Files modified:** 2 source/test files from the root-cause fix plus this summary.

## Accomplishments

- Re-verified destructive preconditions immediately before the second approved rebuild: `HEAD == origin/main == 2f578fe0e3ca3a25abf0e073c3a30add441dd94b`, `examples/` and `clusters/` clean, warm `karyon/k3s-cuda:v1.34.6-k3s1-cuda12.8.1` image present, `.env` non-empty, and no existing 05-06 summary.
- Ran `KARYON_REBUILD_APPROVED=yes task rebuild` exactly once in this continuation; it exited `0`.
- Verified `/tmp/karyon-rebuild.log` has all strict chain markers in order and reports `rebuild elapsed seconds: 193`.
- Verified the HIGH-1 marker `>>> pin context k3d-hub-flux` appears between `>>> step create-clusters` and `>>> step bootstrap-flux`.
- Proved final state with `task health-check`, podinfo Available=True, GPU logs containing `NVIDIA-SMI`, and 7/7 live Bats state-checker tests passing.

## Task Commits

1. **Task 1: Confirm live destructive preconditions** - checkpoint completed before this continuation; no source commit.
2. **Support: Preserve example refs during spoke repair** - `2f578fe` (fix)
3. **Task 2: Run task rebuild once and verify timing/order from log** - execution-only proof; no source commit.
4. **Task 3: Run live state-checker bats and final workload proofs** - execution-only proof; no source commit.

The final docs metadata commit records this summary plus STATE/ROADMAP/REQUIREMENTS updates.

## Files Created/Modified

- `.planning/phases/05-workloads-health-rebuild/05-06-SUMMARY.md` - Captures the live rebuild timing proof, final state checks, deviations, and self-check.
- `scripts/register-spokes-for-flux.sh` - Preserves `../../examples/podinfo` and `../../examples/gpu-smoke-test` references when repairing spoke seed Kustomizations after a rebuild.
- `tests/bats/register-spokes-01-static.bats` - Adds regression checks that repaired spoke Kustomizations retain the Phase 5 example references.

## Live Verification

- `KARYON_REBUILD_APPROVED=yes task rebuild` -> exit `0`, wall-clock 193s.
- `/tmp/karyon-rebuild.log` -> contains ordered markers:

```text
>>> step destroy
>>> step create-clusters
>>> pin context k3d-hub-flux
>>> step bootstrap-flux
>>> step register-spokes
>>> step deploy-examples
>>> step health-check
rebuild elapsed seconds: 193
```

- Log marker line proof: `create=22`, `pin=110`, `bootstrap=112`.
- `task health-check` -> exit `0`.
- `kubectl --context k3d-spoke-apps -n podinfo get deploy podinfo -o jsonpath='{.status.conditions[?(@.type=="Available")].status}'` -> `True`.
- `kubectl --context k3d-spoke-ml -n gpu-smoke logs job/nvidia-smi` -> contained `NVIDIA-SMI`.
- `KARYON_LIVE_TESTS=1 KARYON_LIVE_TESTS_DESTRUCTIVE=1 bats tests/bats/phase5-02-live.bats` -> exit `0`.

```text
1..7
ok 1 rebuild log exists and contains elapsed seconds
ok 2 elapsed seconds <= 1200
ok 3 strict chain step markers appear in order
ok 4 kubeconfig contexts exist after rebuild
ok 5 podinfo Available=True on spoke-apps
ok 6 GPU job logs contain NVIDIA-SMI on spoke-ml
ok 7 state checker source omits destructive invocations
```

## Decisions Made

- Did not rerun `task rebuild` during verification. All Task 2 verification parsed the log from the single approved continuation run.
- Kept detailed live command output in `/tmp/karyon-05-06-*.out` and summarized only non-sensitive exit codes, markers, and proof values.
- Treated the second destructive approval as valid only after rechecking Git visibility, image cache, `.env` presence, and summary absence.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Preserved Phase 5 example refs during spoke repair**
- **Found during:** Task 2 first approved rebuild attempt.
- **Issue:** The first approved `KARYON_REBUILD_APPROVED=yes task rebuild` ran once before this continuation and failed after 185s with exit code 201 because spoke seed repair rewrote Kustomizations without the Phase 5 example resource references, causing workload reconciliation/proof to fail.
- **Fix:** Updated `ensure_spoke_seed` so repairs retain `../../examples/podinfo` for `spoke-apps` and `../../examples/gpu-smoke-test` for `spoke-ml` when those example directories exist; added static regression checks.
- **Files modified:** `scripts/register-spokes-for-flux.sh`, `tests/bats/register-spokes-01-static.bats`
- **Verification:** Root-cause fix was pushed as `2f578fe`; continuation precheck confirmed `HEAD == origin/main == 2f578fe0e3ca3a25abf0e073c3a30add441dd94b`; second approved rebuild and all Task 3 proofs passed.
- **Committed in:** `2f578fe`

---

**Total deviations:** 1 auto-fixed (1 bug).
**Impact on plan:** The fix was required for the planned live rebuild to converge after spoke repair. It did not add new architecture or change the one-Kustomization-per-spoke model.

## Issues Encountered

- The first approved rebuild attempt failed before this continuation. It was not retried until the root cause was fixed and pushed, and the user gave fresh approval for the second destructive rebuild.
- Task 2 and Task 3 are execution-only live proof tasks, so they produced no source commits. Their evidence is recorded in this summary and in the final metadata commit.

## Known Stubs

None. Stub scan found only local bash variables initialized to empty strings before assignment and planned placeholder-safe wording in the plan; none are UI/rendering stubs or unfinished implementation.

## Threat Flags

None. The destructive command and live log surfaces were explicitly covered by the plan threat model; no new endpoint, auth path, file access pattern, schema change, or trust boundary was introduced.

## Authentication Gates

None.

## User Setup Required

None - no external service configuration required. The live destructive proof has already run on the target machine.

## Next Phase Readiness

Phase 5 is complete. Phase 6 can use the measured `193` second rebuild result in the rebuild runbook and continue repo hygiene/docs/ADR work.

---
*Phase: 05-workloads-health-rebuild*
*Completed: 2026-04-28*

## Self-Check: PASSED

- Found created summary: `.planning/phases/05-workloads-health-rebuild/05-06-SUMMARY.md`
- Found modified files from the root-cause fix: `scripts/register-spokes-for-flux.sh`, `tests/bats/register-spokes-01-static.bats`
- Found root-cause fix commit: `2f578fe`
- Confirmed `/tmp/karyon-rebuild.log` still reports `rebuild elapsed seconds: 193` and includes the hub context pin marker.
- Confirmed captured Bats output includes `ok 7 state checker source omits destructive invocations`.
