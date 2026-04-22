---
phase: 01-host-foundation
plan: "06"
subsystem: infra
tags: [bash, shellcheck, preflight, wsl2, docker, asdf, cgroup, clock-skew, bridge-networking]

# Dependency graph
requires:
  - 01-01 (scripts/lib/preflight-lib.sh — preflight_check_env_file, preflight_check_systemd_resolved, preflight_check_cgroup_v2 called)
  - 01-05 (scripts/preflight.sh — PRE-01..08 already present; new sections appended before Summary block)
provides:
  - scripts/preflight.sh: complete preflight checker covering all 14 PRE-xx checks (PRE-09..14 added)
affects:
  - 01-07 (bats tests exercise PRE-09/11/13 via lib functions called from preflight.sh)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - M4 lib delegation: PRE-09/11/13 call preflight_check_*() from lib (bats-testable without inline logic duplication)
    - M1 clock check: powershell.exe Get-Date primary, sudo -n hwclock fallback, warn if both unavailable
    - H4 trap pattern: PRE-14 subshell with trap _pre14_cleanup EXIT covers success/failure/SIGINT paths
    - H4 straggler pre-check: docker ps -a + network ls for preflight-pre14-* before creating ephemeral resources
    - H4 post-cleanup verify: docker ps -a --filter after _pre14_cleanup to detect Docker race conditions
    - H4 outer-scope re-fail: subshell exit code propagated via _pre14_rc; outer FAIL counter incremented explicitly

key-files:
  created: []
  modified:
    - scripts/preflight.sh

key-decisions:
  - "PRE-09/11/13 delegate to lib functions (not inline logic) — callable from bats test suites without copy-pasting shell (M4 fix)"
  - "PRE-12 uses powershell.exe Get-Date as primary (no sudo required in standard WSL2); sudo -n hwclock is second-chance fallback; both failing emits warn not fail (M1 fix)"
  - "PRE-14 wrapped in subshell with EXIT trap — ensures _pre14_cleanup runs on success, failure, and SIGINT (H4 fix)"
  - "PRE-14 uses preflight-pre14-* name prefix (not k8s-net, not preflight-probe-*) — prevents collision with user real networks/containers (H4 fix)"
  - "PRE-14 outer scope re-records fail() after subshell exits non-zero — subshell FAIL counter is separate from outer scope counters"
  - "PRE-10 reads ASDF_DATA_DIR env var with $HOME/.asdf fallback — matches asdf v0.18 data directory behavior"

requirements-completed: [PRE-09, PRE-10, PRE-11, PRE-12, PRE-13, PRE-14]

# Metrics
duration: 10min
completed: 2026-04-22
---

# Phase 1 Plan 06: PRE-09..14 Preflight Extensions Summary

**Six new preflight check sections appended to scripts/preflight.sh: .env secrets contract (lib delegation), asdf shim precedence, systemd-resolved stub, powershell.exe/hwclock clock skew, cgroup v2 purity (lib delegation), and trap-cleaned bridge-curl Docker network probe with straggler pre-check**

## Performance

- **Duration:** ~10 min
- **Completed:** 2026-04-22
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments

- Extended `scripts/preflight.sh` with PRE-09 through PRE-14, completing the full 14-check preflight gate
- PRE-09, PRE-11, PRE-13 delegate to `preflight_check_*()` functions in `scripts/lib/preflight-lib.sh` (M4 fix — makes them bats-testable without duplicating logic)
- PRE-12 clock skew uses `powershell.exe Get-Date -UFormat %s` as primary path (no sudo required in WSL2 interop) with `sudo -n hwclock` second-chance fallback (M1 fix)
- PRE-14 bridge-curl probe uses `preflight-pre14-*` name prefix, runs inside subshell with `trap _pre14_cleanup EXIT`, performs straggler pre-check, and post-cleanup verification (H4 fix)
- All 14 `section()` calls present; `bash -n` and `shellcheck` exit 0; script remains executable

## Task Commits

1. **Task 1: Append PRE-09 through PRE-14 sections to scripts/preflight.sh** — `b809026` (feat)

## Files Created/Modified

- `scripts/preflight.sh` — 138 lines added; bash -n clean; shellcheck exit 0; 14 section() calls; PRE-09..14 all present

## Decisions Made

- PRE-09/11/13 section bodies delegate to library functions rather than inlining logic — bats test suites (Plan 07) can call them directly with fixture arguments without copy-pasting shell fragments
- PRE-12 primary path uses `powershell.exe -NoProfile -Command 'Get-Date -UFormat %s'` — available in standard WSL2 without sudo; `tr -d '\r'` strips Windows line endings before `awk int()` conversion
- PRE-12 fallback `sudo -n hwclock --get --utc` runs silently (no password prompt if sudo not cached); if both fail the check emits `warn` not `fail` (cannot enforce without reference clock)
- PRE-14 runs in a subshell so the EXIT trap does not affect the outer preflight script's exit path; the outer scope re-calls `fail()` if `_pre14_rc != 0` to increment outer FAIL counter (subshell counters are scoped to the subshell)
- PRE-10 reads `${ASDF_DATA_DIR:-$HOME/.asdf}/shims` — matches asdf v0.18 (Go rewrite) data directory resolution; ASDF_DATA_DIR is set by the asdf binary itself when it initialises the PATH

## Deviations from Plan

None — plan executed exactly as written. All six sections implemented per plan spec with all M1, M4, H4 fixes applied.

## Issues Encountered

None.

## User Setup Required

None — no external service configuration required. All checks are read-only host-state inspection.

## Next Phase Readiness

- `scripts/preflight.sh` now covers all 14 PRE-xx requirements; exits 0 on correctly configured box, exits 1 on any blocker
- Plan 07 (bats tests) can source `scripts/lib/preflight-lib.sh` and call `preflight_check_env_file`, `preflight_check_systemd_resolved`, `preflight_check_cgroup_v2` with fixture arguments — M4 delegation pattern is in place
- PRE-14 Docker probe is self-cleaning; no stale preflight-pre14-* resources should remain between runs

---

## Threat Surface Scan

| Threat ID | Category | Component | Disposition | Notes |
|-----------|----------|-----------|-------------|-------|
| T-06-01 | Information Disclosure | PRE-09 reads .env | mitigate | `preflight_check_env_file()` reads values into local vars; `pass()` message says "(value hidden)"; value never echoed |
| T-06-02 | Denial of Service | PRE-14 Docker resources | mitigate | EXIT trap + straggler pre-check ensure ephemeral cleanup on all exit paths |
| T-06-03 | Tampering | busybox image in PRE-14 probe | accept | Official Docker Hub image; probe is read-only GET; lab-only environment |
| T-06-04 | Information Disclosure | PRE-10 PATH structure reveal | accept | PATH structure is non-sensitive; check is defensive |

No new threat surface beyond the plan's registered threats.

## Known Stubs

None — all checks are wired to real host-state reads. No placeholder data, hardcoded empties, or TODO markers.

## Self-Check

### Files exist

- `scripts/preflight.sh`: FOUND

### Commits exist

- `b809026` feat(01-06): extend preflight.sh with PRE-09 through PRE-14 checks: FOUND

## Self-Check: PASSED
