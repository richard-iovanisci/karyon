---
phase: 06-repo-hygiene-docs-adrs
plan: 04
subsystem: infra
tags:
  - phase-6
  - wave-2
  - taskfile
  - repo-hygiene
  - REPO-05
  - REPO-06

requires:
  - phase: 06-repo-hygiene-docs-adrs
    provides: "Wave 0 (06-00) bats contracts for REPO-05 (repo-hygiene-02-taskfile.bats); Wave 1 (06-01) gitleaks/.env.example/.gitignore expansion (no direct dependency, parallel)"
provides:
  - Taskfile.yml `preflight:` task entry for symmetry with the README fresh-clone walkthrough
  - REPO-05 thin-wrapper invariant verified across all 11 task entries
  - REPO-06 destructive-task contract intact (no `prompt:` added; script-level confirmation preserved)
  - Wave-0 contract grep fix: `desc:` lines no longer trigger false positives in REPO-05 inline-invocation check
affects:
  - Plan 06-05 (README rewrite — fresh-clone path will reference `task preflight`)
  - Plan 06-07 (CI workflow — `prune-lint-bats` job runs `bats tests/bats/destroy-rebuild-01-static.bats` and incidentally exercises Taskfile contract)
  - Anyone running `task --list` after a fresh clone

tech-stack:
  added: []
  patterns:
    - "Taskfile thin-wrapper: every cmds: line is exactly `bash scripts/<name>.sh` and nothing else; no inline kubectl/docker/k3d/flux logic; no `prompt:` keys (script-level confirmation owns destructive UX)."

key-files:
  created: []
  modified:
    - "Taskfile.yml"
    - "tests/bats/repo-hygiene-02-taskfile.bats"

key-decisions:
  - "Insert preflight: at the TOP of tasks: (before build-image:) so the README's fresh-clone first-step matches the Taskfile order — Taskfile becomes self-documenting."
  - "Did NOT add Taskfile `prompt:` to destroy:/rebuild: — RESEARCH §Pitfall 5 + Phase 5 D-13/D-14 explicit: confirmation lives in scripts/destroy.sh:26-29 + scripts/rebuild.sh:32-43. Adding `prompt:` would force two confirmations."
  - "Fixed pre-existing bug in tests/bats/repo-hygiene-02-taskfile.bats test 3: the inline-invocation grep didn't exclude `desc:` lines, so descriptions naming `k3d`/`Flux` triggered false positives. Added `desc:` to the negation pattern."

patterns-established:
  - "Taskfile thin-wrapper: 11 entries, all <name>: + desc: + cmds: (single bash scripts/<name>.sh line). Future tasks follow this exact shape."

requirements-completed:
  - REPO-05
  - REPO-06

duration: 5min
completed: 2026-04-29
---

# Phase 6 Plan 04: Taskfile Audit Summary

**Added `preflight:` task entry to Taskfile.yml so the README fresh-clone walkthrough's `task preflight` shortcut resolves to a real entry; REPO-05 thin-wrapper invariant verified, REPO-06 typed-yes confirmation contract preserved at the script level.**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-04-29T01:01:00Z (approx — agent spawn)
- **Completed:** 2026-04-29T01:04:46Z
- **Tasks:** 1 (per plan)
- **Files modified:** 2

## Accomplishments

- Inserted `preflight:` block at the top of `tasks:` in Taskfile.yml (5-line addition: blank + `preflight:` + `desc:` + `cmds:` + `bash scripts/preflight.sh`).
- Confirmed all 10 existing task entries unchanged; thin-wrapper invariant intact (every `cmds:` line is `bash scripts/<name>.sh` and nothing else).
- Confirmed no `prompt:` key on `destroy:` or `rebuild:` (REPO-06 + RESEARCH §Pitfall 5 contract: confirmation owned by `scripts/destroy.sh:26-29` and `scripts/rebuild.sh:32-43`, not the Taskfile).
- Fixed pre-existing bug in `tests/bats/repo-hygiene-02-taskfile.bats` test 3 grep pattern that was matching `desc:` lines naming `k3d`/`Flux`.
- Live `task --list` now lists 11 entries; `task --dry preflight` resolves to `bash scripts/preflight.sh`.

## Task Commits

Each task was committed atomically (single task in this plan):

1. **Task 1: Add `preflight:` task to Taskfile.yml without disturbing the existing 10 entries** - `8e8f820` (feat)

## Files Created/Modified

- `Taskfile.yml` — Inserted 5-line `preflight:` block at top of `tasks:` map. Total entries: 10 → 11. Format matches existing block style (2-space task indent, 4-space key indent, 6-space list-item indent, blank-line separator).
- `tests/bats/repo-hygiene-02-taskfile.bats` — Test 3 grep negation pattern: added `desc:` to the exclusion list so descriptive text mentioning `k3d`/`Flux`/`docker`/`kubectl` doesn't masquerade as an inline invocation. Comment added explaining the rationale.

## Decisions Made

- **Insert position:** `preflight:` placed at the top of `tasks:` (before `build-image:`) so the Taskfile order matches the README's fresh-clone path order — `preflight` is the first command a new user runs after install. Taskfile becomes self-documenting.
- **No Taskfile `prompt:`:** REPO-06 contract is satisfied at the script level. Adding `prompt:` to the `destroy:` / `rebuild:` Taskfile entries would force the user to type `y` (Taskfile default `[y/N]`) THEN type `yes` (script-level prompt) — a UX regression flagged in RESEARCH §Pitfall 5 and locked by Phase 5 D-13/D-14.
- **Test 3 fix scope:** chose to fix the bats negation pattern (Rule 3 deviation) rather than rewording Taskfile descriptions to avoid the words `k3d`/`Flux`. The test's intent is to catch INLINE INVOCATIONS of those commands; descriptive prose is not in scope. Minimal change preserves the test's load-bearing assertion.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Fixed `desc:` false-positive in `tests/bats/repo-hygiene-02-taskfile.bats` test 3**

- **Found during:** Task 1 verification step (running `bats tests/bats/repo-hygiene-02-taskfile.bats` after the Taskfile edit)
- **Issue:** Test 3 (`REPO-05: Taskfile.yml has no inline kubectl|docker|k3d|flux invocations outside cmds:`) used a `grep -vE` exclusion pattern that filtered out lines starting with `#`, `cmds:`, or `- bash scripts/` — but did NOT exclude `desc:` lines. Several Taskfile entries have descriptions naming `k3d` (e.g., "Create k8s-net + three k3d clusters") or `Flux` (e.g., "Bootstrap Flux GitOps on k3d-hub-flux"). The downstream `grep -E '\b(kubectl|docker|k3d|flux)[[:space:]]+'` then matched these descriptions and the test failed even though there are NO inline invocations anywhere outside `cmds:`. This was a pre-existing bug authored in Wave 0 (commit `2551a9d` of plan 06-01) that the plan's success criteria require to be green — so the bug blocks Plan 06-04's acceptance.
- **Fix:** Added `desc:` to the exclusion pattern in test 3, and added a comment block explaining the rationale (descriptions narratively reference `k3d`/`Flux`; only true non-cmds/non-desc/non-comment lines should be checked for inline invocations).
- **Files modified:** `tests/bats/repo-hygiene-02-taskfile.bats` (line 41 of the original; now lines 41-46 with explanatory comment + amended grep).
- **Verification:** `bats tests/bats/repo-hygiene-02-taskfile.bats` reports 3/3 green; `bats tests/bats/destroy-rebuild-01-static.bats` reports 17/17 green (REPO-05 wiring + DESTROY-01..06 unchanged).
- **Committed in:** `8e8f820` (combined with Task 1 since both changes serve the same single-task plan).

---

**Total deviations:** 1 auto-fixed (1 blocking issue per Rule 3)
**Impact on plan:** The fix preserves the test's intent (catching inline command invocations) and removes a false-positive that blocked acceptance. No scope creep — the test still asserts exactly the same REPO-05 thin-wrapper invariant.

## Issues Encountered

None during execution beyond the test-grep deviation handled above. The plan's `<action>` Step 1 noted that `wc -l < Taskfile.yml` would return 53 baseline; the actual file reports 52 lines (no trailing newline counted). Post-edit `wc -l` returns 57 (5 lines added). This is a minor count discrepancy between the plan's expected baseline and reality, not a behavior change — the file was well-formed in both states.

## Verification Output

```
bats tests/bats/repo-hygiene-02-taskfile.bats
1..3
ok 1 REPO-05: Taskfile.yml exists and lists every Phase 1-5 task
ok 2 REPO-05: Taskfile.yml is a thin wrapper — every cmds: entry calls bash scripts/<name>.sh and nothing else
ok 3 REPO-05: Taskfile.yml has no inline kubectl|docker|k3d|flux invocations outside cmds:

bats tests/bats/destroy-rebuild-01-static.bats
1..17
ok 1..17 (all green; REPO-05 wiring + DESTROY-01..06 contracts unchanged)

task --list
* preflight:             Read-only environment check (PRE-01..14); idempotent, exits 0 on pass / 1 on any blocker
(plus 10 existing entries listed alphabetically)

task --dry preflight
task: [preflight] bash scripts/preflight.sh
```

## User Setup Required

None — this is a config edit only. Existing users running `task --list` after pulling will simply see the new `preflight:` entry. No environment variables, no service config.

## Next Phase Readiness

- Plan 06-05 (README rewrite) can reference `task preflight` knowing the entry exists.
- Plan 06-07 (CI workflow) — the `prune-lint-bats` job that runs `bats tests/bats/destroy-rebuild-01-static.bats` will incidentally exercise the REPO-05 wiring assertion (test 17 of that file). The new W0 contract `repo-hygiene-02-taskfile.bats` is also CI-runnable as part of `bats tests/bats/`.
- No blockers introduced. REPO-06 contract preserved without modification.

## Self-Check

```
FOUND: /home/rich/code/gsd/karyon/.claude/worktrees/agent-a0fdccdb60f3987cf/Taskfile.yml (modified, 57 lines, 11 task entries, preflight at top)
FOUND: /home/rich/code/gsd/karyon/.claude/worktrees/agent-a0fdccdb60f3987cf/tests/bats/repo-hygiene-02-taskfile.bats (modified, test 3 grep fixed)
FOUND: commit 8e8f820 (`feat(06-04): add preflight: task to Taskfile.yml + fix REPO-05 desc: false-positive`)
```

## Self-Check: PASSED

---
*Phase: 06-repo-hygiene-docs-adrs*
*Completed: 2026-04-29*
