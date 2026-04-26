---
phase: 03-flux-hub-bootstrap
plan: 05
subsystem: infra
tags: [flux, bash, scripts, security, gap-closure]

requires:
  - phase: 03-flux-hub-bootstrap
    provides: Plan 03-02 bootstrap-flux.sh script and Plan 03 verification gaps CR-01/CR-02
provides:
  - Data-only .env parser for GitHub bootstrap keys
  - Local checkout fast-forward sync before patch-surface marker assertion
  - Static verification proving CR-01 and CR-02 are closed for Plan 03-06
affects: [03-flux-hub-bootstrap, 04-spoke-registration, 05-rebuild-health]

tech-stack:
  added: []
  patterns:
    - grep/tail/cut .env key parser with printf -v export
    - git pull --ff-only sync guarded by scoped dirty-worktree checks

key-files:
  created:
    - .planning/phases/03-flux-hub-bootstrap/03-05-SUMMARY.md
  modified:
    - scripts/bootstrap-flux.sh

key-decisions:
  - "Keep the CR-01 fix as a local read-only fast-forward sync instead of reimplementing Flux bootstrap's remote Git workflow."
  - "Treat .env as data for the three GitHub keys only; do not source it or evaluate arbitrary shell."

patterns-established:
  - "Bootstrap scripts load secrets through narrow parsers that never print secret values."
  - "Bootstrap-generated remote files are reconciled into the local checkout before local patch-surface edits."

requirements-completed: [FLUX-01, FLUX-03, FLUX-04]

duration: 3min
completed: 2026-04-26
---

# Phase 03 Plan 05: Flux Bootstrap Gap Closure Summary

**Data-only GitHub env loading plus a guarded fast-forward sync so first-run Flux bootstrap can finish locally.**

## Performance

- **Duration:** 3min
- **Started:** 2026-04-26T19:54:30Z
- **Completed:** 2026-04-26T19:57:37Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Replaced `source "${REPO_ROOT}/.env"` and `set -a` with `load_env_key`, which reads only `GITHUB_OWNER`, `GITHUB_REPO`, and `GITHUB_TOKEN` as data.
- Added the Section 5 fast-forward sync from `origin/main` when Flux-generated manifests are missing locally, guarded by clean tracked/index state under `clusters/hub-flux`.
- Preserved the D-13 marker block, idempotent skip messages, static Bats contracts, and the live/destructive skip gate for Plan 03-06.

## Task Commits

Each task was committed atomically:

1. **Task 1: Replace source .env with load_env_key parser** - `941dd60` (fix)
2. **Task 2: Sync local checkout before patch-surface marker** - `1897199` (fix)

## Files Created/Modified

- `scripts/bootstrap-flux.sh` - Replaced shell execution of `.env` with data-only key parsing and added Section 5 local checkout sync.
- `.planning/phases/03-flux-hub-bootstrap/03-05-SUMMARY.md` - Plan execution summary.

## Truth Evidence

| Truth | Evidence |
|-------|----------|
| Local sync happens before reading `${KUST_FILE}` | `scripts/bootstrap-flux.sh:216-239` attempts `git -C "${REPO_ROOT}" pull --ff-only origin main` before the post-sync file assertion at `242-248`. |
| Dirty worktree under `${FLUX_PATH}` fails closed | `scripts/bootstrap-flux.sh:221-227` checks tracked and staged changes under `${FLUX_PATH}` and prints the exact status/stash/commit remediation. |
| Missing `${KUST_FILE}` after sync fails loudly | `scripts/bootstrap-flux.sh:242-248` reports `missing AFTER sync` with `ls` and `git log` remediation. |
| Marker-present rerun remains idempotent | Existing `info "already done, skipping: patch-surface marker present"` remains at `scripts/bootstrap-flux.sh:250-251`; sync only runs when the file is absent. |
| `.env` is not sourced | Negative grep for `source "${REPO_ROOT}/.env"` and `set -a` passed; parser lives at `scripts/bootstrap-flux.sh:114-136`. |
| Malicious `.env` statements do not execute | Temp proof output: `OWNER=foo REPO=bar TOKEN_LEN=3`; stderr bytes `0`; no `PWNED_INJECT`. |
| Token value is not emitted | Bats token-funnel negative grep passed; parser failure paths log key names only at `scripts/bootstrap-flux.sh:116-131`. |
| Syntax, ShellCheck, and static Bats pass | `bash -n`, `shellcheck -x`, `bats bootstrap-flux-01-idempotent.bats --tap`, and `bats bootstrap-flux-02-docs.bats --tap` all passed. |

## Threat Model Dispositions

| Threat | Disposition | Mitigation Pointer |
|--------|-------------|--------------------|
| T-3-05-01 `.env` shell injection | Mitigated | `load_env_key` at `scripts/bootstrap-flux.sh:114-136`; no `source`, no `set -a`, no `eval`. |
| T-3-05-02 token leak via parser logging | Mitigated | Missing/empty failures name only `${key}` at `scripts/bootstrap-flux.sh:116-131`; Bats token-funnel grep passed. |
| T-3-05-03 dirty-worktree clobber | Mitigated | Scoped `git diff` and `git diff --cached` guard at `scripts/bootstrap-flux.sh:221-227`; pull is `--ff-only`. |
| T-3-05-04 wrong remote / no network | Accepted | Pull failure path at `scripts/bootstrap-flux.sh:231-237` surfaces remote/log inspection and manual reconciliation. |
| T-3-05-05 quoted shell metacharacters | Mitigated | Quote stripping and `printf -v` preserve value as data at `scripts/bootstrap-flux.sh:121-131`. |

## Verification

- `bash -n scripts/bootstrap-flux.sh` passed.
- `shellcheck -x scripts/bootstrap-flux.sh` passed.
- Negative greps for `source "${REPO_ROOT}/.env"`, `set -a`, and `eval` passed.
- Positive greps for `load_env_key GITHUB_OWNER`, `load_env_key GITHUB_REPO`, `load_env_key GITHUB_TOKEN`, `git -C "${REPO_ROOT}" pull --ff-only origin main`, `uncommitted changes detected under`, and `fast-forward sync complete` passed.
- `bats tests/bats/bootstrap-flux-01-idempotent.bats --tap` passed `1..8`; the live/destructive test correctly skipped without gates.
- `bats tests/bats/bootstrap-flux-02-docs.bats --tap` passed `1..4`.
- Parser negative-execution proof passed with `OWNER=foo REPO=bar TOKEN_LEN=3` and zero stderr bytes.

## Decisions Made

- Used the planned sync approach rather than moving marker editing into a second remote Git workflow.
- Kept parser scope to the three required GitHub keys and exported with `printf -v` plus ShellCheck-clean dynamic export.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Made dynamic export ShellCheck-clean**
- **Found during:** Task 1
- **Issue:** The plan's `export "${key}"` form triggered ShellCheck SC2163, blocking the required clean shellcheck gate.
- **Fix:** Changed it to `export "${key?}"`, preserving dynamic export of the parsed key while quieting the false positive.
- **Files modified:** `scripts/bootstrap-flux.sh`
- **Verification:** `shellcheck -x scripts/bootstrap-flux.sh` passed.
- **Committed in:** `941dd60`

**2. [Rule 3 - Blocking] Removed literal `eval` from parser comments**
- **Found during:** Task 1
- **Issue:** The inserted parser comment used the word "evaluates", but the acceptance gate requires `grep -F 'eval' scripts/bootstrap-flux.sh` to exit non-zero.
- **Fix:** Reworded the comment to "runs the file as shell" without changing behavior.
- **Files modified:** `scripts/bootstrap-flux.sh`
- **Verification:** Negative `grep -F 'eval' scripts/bootstrap-flux.sh` passed.
- **Committed in:** `941dd60`

---

**Total deviations:** 2 auto-fixed (2 Rule 3)
**Impact on plan:** Both were required to satisfy the plan's own verification gates; no scope expansion or behavior change beyond making the requested parser verifiable.

## Issues Encountered

None beyond the auto-fixed verification blockers above.

## Known Stubs

None.

## Auth Gates

None. No authenticated GitHub or live Flux bootstrap command was run in this plan; Plan 03-06 owns the live/destructive proof.

## User Setup Required

None for this static gap-closure plan.

## Next Phase Readiness

Plan 03-06 can now run the live/destructive bootstrap idempotency proof against the real `k3d-hub-flux` cluster: the first-run local-manifest gap and `.env` shell-execution gap are closed.

## Self-Check: PASSED

- Found created files: `scripts/bootstrap-flux.sh`, `.planning/phases/03-flux-hub-bootstrap/03-05-SUMMARY.md`.
- Found task commits: `941dd60`, `1897199`.
- Stub scan found no `TODO`, `FIXME`, placeholder, or empty-data stub patterns in the files modified by this plan.
- Final verification passed: `bash -n`, `shellcheck -x`, negative/positive greps, both non-live Bats suites, and the parser negative-execution proof.

---
*Phase: 03-flux-hub-bootstrap*
*Completed: 2026-04-26*
