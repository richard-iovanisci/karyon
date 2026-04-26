---
phase: 03-flux-hub-bootstrap
plan: 02
subsystem: infra
tags: [flux, bash, gitops, k3d, bootstrap]

requires:
  - phase: 03-flux-hub-bootstrap
    provides: Plan 03-01 Bats contract tests for bootstrap-flux.sh
provides:
  - Executable scripts/bootstrap-flux.sh wrapper around flux bootstrap github
  - Context-safe and token-safe Flux bootstrap flow for k3d-hub-flux
  - Post-bootstrap Flux health verification and patch-surface marker handling
affects: [03-flux-hub-bootstrap, 04-spoke-registration, 05-rebuild-health, 06-repo-hygiene-docs-adrs]

tech-stack:
  added: []
  patterns:
    - preflight-lib sourced bash orchestration
    - guarded idempotency checks before side effects
    - sentinel-guarded file prepend with developer git-flow hint

key-files:
  created:
    - scripts/bootstrap-flux.sh
    - .planning/phases/03-flux-hub-bootstrap/03-02-SUMMARY.md
  modified: []

key-decisions:
  - "Flux bootstrap path remains hard-coded to clusters/hub-flux with no environment override."
  - "GITHUB_TOKEN is passed only through the process environment, never argv or helper logging."
  - "The D-13 patch marker is applied locally and the script tells the developer when to commit and push it."

patterns-established:
  - "Flux bootstrap wrappers must prove health with flux check, deployment count plus kubectl wait, and Kustomization Ready=True."
  - "Bootstrap-generated kustomization.yaml changes use a # FLUX PATCH SURFACE sentinel and git diff hint."

requirements-completed: [FLUX-01, FLUX-02, FLUX-03, FLUX-04]

duration: 5min
completed: 2026-04-26
---

# Phase 03 Plan 02: Flux Bootstrap Script Summary

**Executable Flux bootstrap wrapper with context safety, env-only PAT handling, health gates, and an idempotent patch-surface marker.**

## Performance

- **Duration:** 5min
- **Started:** 2026-04-26T18:54:46Z
- **Completed:** 2026-04-26T18:59:42Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Created `scripts/bootstrap-flux.sh` as a 240-line executable script with five plan-defined sections.
- Implemented preflight delegation, warn-only gitleaks advisory, kubectl context fail-fast gate, and three-part idempotency short-circuit.
- Added `flux bootstrap github` with `--path "${FLUX_PATH}"`, `--personal`, `--private=false`, `--network-policy=false`, `--token-auth`, and `--branch main`.
- Added post-bootstrap verification for `flux check`, four Available controller Deployments, and `flux-system` Kustomization Ready=True via kubectl jsonpath.
- Added sentinel-guarded `# FLUX PATCH SURFACE` prepend plus git-diff-aware commit/push guidance.

## Task Commits

Each task was committed atomically:

1. **Task 1: Create Sections 1-3** - `d04c556` (feat)
2. **Task 2: Append Sections 4-5 and summary footer** - `a8c9fb2` (feat)

## Files Created/Modified

- `scripts/bootstrap-flux.sh` - 240-line executable Flux bootstrap orchestration script.
- `.planning/phases/03-flux-hub-bootstrap/03-02-SUMMARY.md` - Plan execution summary.

## Verification

- `bash -n scripts/bootstrap-flux.sh` passed.
- `shellcheck -x scripts/bootstrap-flux.sh` passed.
- `bash scripts/preflight.sh > /tmp/karyon-preflight-plan03-02.log 2>&1; rc=$?` returned `preflight rc=0`, proving preflight tolerates the current post-Phase-2 host state.
- `bats tests/bats/bootstrap-flux-01-idempotent.bats --tap` passed all 7 static tests and skipped the combined live/destructive test as expected:
  - `ok 1..ok 7`
  - `ok 8 ... # skip destructive live test ...`

## Decisions Made

- Kept the corrected `--network-policy=false` rationale directly above the bootstrap invocation so maintainers see that k3s can enforce NetworkPolicy, but this single-user lab intentionally disables Flux's default policy.
- Used kubectl jsonpath for the Kustomization Ready gate instead of `flux get | awk`, matching the plan's review fix for column-order fragility.
- Left shared `.planning/STATE.md` and `.planning/ROADMAP.md` untouched per executor coordination; the orchestrator owns shared tracking updates.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Made Task 1 independently ShellCheck-clean**
- **Found during:** Task 1
- **Issue:** The plan's Sections 1-3 define `KUST_FILE` for Section 5 before Section 5 exists, so `shellcheck -x scripts/bootstrap-flux.sh` reported SC2034 during the Task 1 gate.
- **Fix:** Temporarily suppressed SC2034 in the Task 1 commit, then removed the suppression when Task 2 appended Section 5 and consumed `KUST_FILE`.
- **Files modified:** `scripts/bootstrap-flux.sh`
- **Verification:** `shellcheck -x scripts/bootstrap-flux.sh` passed after each task.
- **Committed in:** `d04c556`, resolved in `a8c9fb2`

**2. [Rule 2 - Missing Critical] Used safe printf arguments for final summary**
- **Found during:** Task 2
- **Issue:** The literal plan footer embedded repository values in the printf format string. The script is public-safe and should avoid data-dependent format strings.
- **Fix:** Kept the same final message but passed owner, repo, and path as `%s` arguments.
- **Files modified:** `scripts/bootstrap-flux.sh`
- **Verification:** `bash -n`, `shellcheck -x`, and Bats all passed.
- **Committed in:** `a8c9fb2`

---

**Total deviations:** 2 auto-fixed (1 Rule 3, 1 Rule 2)  
**Impact on plan:** No behavior or required literals changed; both adjustments support the plan's safety and verification requirements.

## Issues Encountered

None beyond the auto-fixed issues documented above.

## Known Stubs

None.

## Auth Gates

None. No authenticated GitHub or live Flux command was run; live bootstrap remains gated by `KARYON_LIVE_TESTS=1 KARYON_LIVE_TESTS_DESTRUCTIVE=1`.

## User Setup Required

The live destructive proof still requires a real `k3d-hub-flux` cluster and `.env` with `GITHUB_OWNER`, `GITHUB_REPO`, and `GITHUB_TOKEN`, then:

```bash
KARYON_LIVE_TESTS=1 KARYON_LIVE_TESTS_DESTRUCTIVE=1 bats tests/bats/bootstrap-flux-01-idempotent.bats --tap
```

## Next Phase Readiness

Plan 03-03 can document the Flux patch-surface contract in parallel, and Plan 03-04 can expose `scripts/bootstrap-flux.sh` through Taskfile once docs land. Phase 4 can rely on the hub Flux bootstrap script creating and verifying a healthy `flux-system` control plane.

## Self-Check: PASSED

- Found created files: `scripts/bootstrap-flux.sh`, `.planning/phases/03-flux-hub-bootstrap/03-02-SUMMARY.md`.
- Found task commits: `d04c556`, `a8c9fb2`.
- Final verification passed: `bash -n scripts/bootstrap-flux.sh`, `shellcheck -x scripts/bootstrap-flux.sh`, and `bats tests/bats/bootstrap-flux-01-idempotent.bats --tap`.

---
*Phase: 03-flux-hub-bootstrap*
*Completed: 2026-04-26*
