---
phase: 04-spoke-registration
plan: 04
subsystem: integration
tags: [flux, kustomize, taskfile, docs, spoke-registration]

# Dependency graph
requires:
  - phase: 04-spoke-registration
    provides: Plan 04-01 static and live Bats contracts
  - phase: 04-spoke-registration
    provides: Plan 04-02 hub-spoke manifests and spoke seed trees
  - phase: 04-spoke-registration
    provides: Plan 04-03 spoke registration script and verification gates
provides:
  - Flux root Kustomization mount for clusters/hub-flux/spokes/
  - Taskfile register-spokes hand-off invoking scripts/register-spokes-for-flux.sh
  - Phase 4 hub-spoke reconciliation documentation with P18 reframe and probe split
  - Updated bootstrap docs Bats assertion after consuming the Phase 4 stub
affects: [04-spoke-registration, 05-workloads-and-health, 06-docs-and-repo-hygiene]

# Tech tracking
tech-stack:
  added: []
  patterns: [sentinel-guarded kustomize mount, Taskfile hand-off entry, docs stub consumption, static Bats non-regression update]

key-files:
  created:
    - .planning/phases/04-spoke-registration/04-04-SUMMARY.md
  modified:
    - clusters/hub-flux/flux-system/kustomization.yaml
    - Taskfile.yml
    - docs/flux-hub-spoke.md
    - tests/bats/bootstrap-flux-02-docs.bats

key-decisions:
  - "Plan 04-04 mounts clusters/hub-flux/spokes through the existing Phase 3 patch surface using # KARYON SPOKES MOUNT plus - ../spokes."
  - "The Phase 4 docs frame P18 as omitted spec.kubeConfig, while treating key: value.yaml as defense in depth."
  - "Phase 3 docs tests now assert the filled Phase 4 section instead of the consumed HTML stub."

patterns-established:
  - "When a planned docs stub is consumed, inherited static docs tests must move from stub-existence checks to filled-section checks."
  - "Taskfile hand-offs stay as single-command tasks until Phase 6 owns the broader repo hygiene reorganization."

requirements-completed: [SPOKE-04, SPOKE-05, DOCS-03]

# Metrics
duration: 5min
completed: 2026-04-27
---

# Phase 04 Plan 04: Hub-Spoke Wire-Up Summary

**Flux hub-spoke wire-up through the root Kustomization, Taskfile entry, and operational docs with static Bats fully green.**

## Performance

- **Duration:** 5 min
- **Started:** 2026-04-27T18:38:57Z
- **Completed:** 2026-04-27T18:43:22Z
- **Tasks:** 4
- **Files modified:** 4 total; 3 planned files plus 1 directly related test update

## Accomplishments

- Patched `clusters/hub-flux/flux-system/kustomization.yaml` with `# KARYON SPOKES MOUNT` and `- ../spokes`, preserving the Phase 3 `# FLUX PATCH SURFACE` block and bootstrap-managed resources.
- Added `task register-spokes`, invoking `bash scripts/register-spokes-for-flux.sh` with the SPOKE-01..06 description.
- Replaced the Phase 4 docs stub with the hub-spoke reconciliation section covering the three artifacts, omitted-`spec.kubeConfig` P18 risk, openssl CA/TLS proof, wget auth/node proof, and live Bats hand-off.
- Updated the inherited Phase 3 docs Bats assertion so prior smoke tests remain green after the planned stub replacement.

## Task Commits

Each task was committed atomically:

1. **Task 1: Patch clusters/hub-flux/flux-system/kustomization.yaml** - `9def104` (feat)
2. **Task 2: Append register-spokes task to Taskfile.yml** - `6960d3e` (feat)
3. **Task 3: Fill the Phase 4 stub in docs/flux-hub-spoke.md** - `42222b4` (docs)
4. **Task 4: Run the full static bats suite and fix direct regression** - `d037f32` (fix)

## Files Created/Modified

- `clusters/hub-flux/flux-system/kustomization.yaml` - Added 2 lines for the Phase 4 spokes mount sentinel and `- ../spokes`.
- `Taskfile.yml` - Added 5 lines for the `register-spokes` task.
- `docs/flux-hub-spoke.md` - Replaced the Phase 4 stub with a 62-line hub-spoke reconciliation section.
- `tests/bats/bootstrap-flux-02-docs.bats` - Updated the consumed-stub assertion to check the filled Phase 4 section.
- `.planning/phases/04-spoke-registration/04-04-SUMMARY.md` - This execution summary.

## Verification

- `kubectl --context k3d-hub-flux kustomize clusters/hub-flux/flux-system/` -> passed.
- `bats tests/bats/register-spokes-01-static.bats --tap` -> 24 passed, 0 failed.
- `bats tests/bats/bootstrap-flux-01-idempotent.bats --tap` -> 8 passed, 0 failed; destructive test skipped without env gates.
- `bats tests/bats/register-spokes-02-live.bats --tap` -> 18 skipped cleanly, 0 failed without destructive env gates.
- `bats tests/bats/preflight-*.bats tests/bats/create-clusters-*.bats tests/bats/delete-clusters-*.bats tests/bats/bootstrap-flux-*.bats --tap` -> 45 passed, 0 failed.
- `task --list` -> includes `register-spokes`.

## Decisions Made

- Used the exact `# KARYON SPOKES MOUNT` sentinel from the Phase 4 contract and appended the mount after the bootstrap-managed Flux resources.
- Kept the Taskfile addition to one command, leaving full Taskfile reorganization to Phase 6 as planned.
- Documented openssl as the CA/TLS proof and wget as bearer-token auth plus node identity proof, avoiding the incorrect claim that `wget --no-check-certificate` validates TLS.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Updated stale Phase 3 docs Bats assertion after planned stub replacement**
- **Found during:** Task 4 (Run the full static bats suite)
- **Issue:** `tests/bats/bootstrap-flux-02-docs.bats` still required the Phase 4 HTML stub to exist, but Task 3 intentionally replaced that stub with the real Phase 4 section.
- **Fix:** Updated the test to assert `## Phase 4: Hub-spoke reconciliation`, absence of the old `<!-- Phase 4:` comment, and presence of `spec.kubeConfig`.
- **Files modified:** `tests/bats/bootstrap-flux-02-docs.bats`
- **Verification:** `bats tests/bats/bootstrap-flux-02-docs.bats --tap` passed 4/4; prior smoke suite passed 45/45.
- **Committed in:** `d037f32`

---

**Total deviations:** 1 auto-fixed (Rule 1 bug)
**Impact on plan:** The fix was directly caused by the planned docs stub consumption and restored Phase 3 non-regression coverage. No product scope was added.

## Issues Encountered

- The plan's broad smoke example referenced `tests/bats/cluster-*.bats`, but this repo's actual cluster suites are named `create-clusters-*.bats` and `delete-clusters-*.bats`. The literal glob failed because no files matched; the equivalent existing prior-suite smoke was run and passed 45/45.

## Known Stubs

None. Stub-pattern scan across files modified by this plan found no functional stubs or placeholder data.

## Threat Flags

None. The only security-relevant surface added, the `- ../spokes` Flux tree mount, was in the plan threat model and is sentinel-pinned by Bats.

## Auth Gates

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Plan 04-05 can run the live spoke registration flow, commit/push the reconciled tree, and exercise the post-push live destructive Bats proof for Ready spoke Kustomizations and `.status.inventory` negative-proof.

---
*Phase: 04-spoke-registration*
*Completed: 2026-04-27*

## Self-Check: PASSED

- Found modified files: `clusters/hub-flux/flux-system/kustomization.yaml`, `Taskfile.yml`, `docs/flux-hub-spoke.md`, `tests/bats/bootstrap-flux-02-docs.bats`
- Found created summary: `.planning/phases/04-spoke-registration/04-04-SUMMARY.md`
- Found task commits: `9def104`, `6960d3e`, `42222b4`, `d037f32`
