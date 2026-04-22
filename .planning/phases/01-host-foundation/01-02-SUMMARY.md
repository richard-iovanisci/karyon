---
phase: 01-host-foundation
plan: "02"
subsystem: infra
tags: [bash, shellcheck, docker, systemd, wsl2, idempotent, installer]

# Dependency graph
requires:
  - scripts/lib/preflight-lib.sh (Plan 01 — section/pass/warn/fail/info/have helpers)
  - config/hwclock-resume.service (Plan 01 — static unit file)
provides:
  - scripts/install-docker.sh: idempotent Docker Engine + daemon.json + hwclock unit installer
affects:
  - 01-host-foundation/01-05 (scripts/preflight.sh validates Docker state install-docker.sh establishes)
  - 01-host-foundation/01-03 (install-nvidia-container-toolkit.sh follows same guarded-sections pattern)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - guarded-sections pattern (D-05): check state before acting; log "already done, skipping: X" or "installing: X"
    - content-correct guard for apt repo: grep -Fxq on exact repo line (M2 — not file-exists)
    - content-correct guard for systemd unit: systemctl is-enabled (M2 — not file-exists)
    - jq-merge for daemon.json: '. + {key: val}' preserves existing keys without overwriting
    - prerequisites-first ordering (H3): jq + gnupg installed before any section that uses them

key-files:
  created:
    - scripts/install-docker.sh
  modified: []

key-decisions:
  - "Section 0 installs jq + gnupg + ca-certificates + curl FIRST (H3): jq needed in Section 6 for daemon.json merge; gnupg needed in Section 2 for GPG key dearmor"
  - "Docker apt repo guard uses grep -Fxq on exact repo line including arch, codename, and signing-key path (M2 content-correct — detects drift from stale Ubuntu version or wrong codename)"
  - "hwclock enablement guard uses systemctl is-enabled piped through grep -q '^enabled$' (M2 content-correct — detects file-present-but-disabled drift)"
  - "shellcheck SC1091 suppressed on source line (dynamic SCRIPT_DIR variable) and /etc/os-release dot-source (same pattern established in Plan 01)"
  - "set -euo pipefail (not set -u only): install scripts abort on unexpected errors; preflight uses set -u only to collect all failures"

requirements-completed: [HOST-03, HOST-04, HOST-06]

# Metrics
duration: 2min
completed: 2026-04-22
---

# Phase 1 Plan 02: install-docker.sh Summary

**Idempotent Docker Engine installer with content-correct guards for apt repo (M2) and hwclock systemd unit (M2), prerequisites-first section ordering (H3), and jq-merge daemon.json strategy**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-04-22T22:19:30Z
- **Completed:** 2026-04-22T22:21:05Z
- **Tasks:** 1
- **Files modified:** 1 (created)

## Accomplishments

- Created `scripts/install-docker.sh` — 156-line idempotent installer with 7 guarded sections sourcing `scripts/lib/preflight-lib.sh` for ANSI helpers
- Section 0 (Prerequisites) installs jq + gnupg + ca-certificates + curl BEFORE any downstream section uses them (H3 correctness fix from cross-AI review)
- Docker apt repository guard upgraded to `grep -Fxq` on exact repo line including arch, codename, and signing-key path — detects stale files from prior Ubuntu versions (M2 fix)
- hwclock unit enablement guard upgraded to `systemctl is-enabled ... | grep -q '^enabled$'` — detects file-present-but-disabled drift (M2 fix)
- daemon.json section uses jq-merge strategy: `. + {"default-runtime": $dr, "dns": $dns}` — preserves existing keys; guard checks both `default-runtime` and `dns` before acting
- Every section has the D-05 audit log: `info "already done, skipping: X"` or `pass "installing: X"`
- Script passes `bash -n` and `shellcheck` with 0 errors; executable bit set

## Task Commits

Each task was committed atomically:

1. **Task 1: Write scripts/install-docker.sh with all guarded sections** — `43da4e0` (feat)

## Files Created/Modified

- `scripts/install-docker.sh` — 156 lines; set -euo pipefail; sources lib/preflight-lib.sh; 7 guarded sections; shellcheck-clean

## Decisions Made

- Section 0 ordering (H3): jq and gnupg must precede the sections that use them. The plan flag H3 from cross-AI review was the primary driver — this is a hard correctness requirement, not a style choice.
- Content-correct guards over file-exists guards (M2): `grep -Fxq` on the exact apt repo line catches codename drift; `systemctl is-enabled` catches unit-file-present-but-disabled drift. Both are superior to `[[ -f ... ]]` for detecting real configuration state.
- `shellcheck disable=SC1091` on the `source "${SCRIPT_DIR}/lib/preflight-lib.sh"` line: shellcheck cannot follow a dynamically computed variable path; same approach as `test_helper.bash` from Plan 01.
- `# shellcheck source=/dev/null` on the `. /etc/os-release` subshell: same pattern as `preflight_check_ubuntu_24_04()` in preflight-lib.sh from Plan 01.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] SC1091 shellcheck failure on dynamic source paths**
- **Found during:** Task 1 (shellcheck verification)
- **Issue:** `shellcheck scripts/install-docker.sh` exited 1 with two SC1091 warnings: (a) `source "${SCRIPT_DIR}/lib/preflight-lib.sh"` — dynamic variable path shellcheck cannot follow; (b) `. /etc/os-release` inside a command substitution subshell
- **Fix:** Added `# shellcheck disable=SC1091` before the `source` line; added `# shellcheck source=/dev/null` before the `. /etc/os-release` subshell. Same pattern established in Plan 01 for preflight-lib.sh and test_helper.bash.
- **Files modified:** scripts/install-docker.sh
- **Verification:** `shellcheck scripts/install-docker.sh` exits 0
- **Committed in:** 43da4e0 (Task 1 commit — fixed inline before commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 bug — shellcheck SC1091 directives)
**Impact on plan:** Minimal; same suppression pattern already established in Plan 01. No scope creep.

## Known Stubs

None — `scripts/install-docker.sh` is a complete, standalone installer. No placeholder data, no hardcoded empty values, no TODO markers.

## Threat Surface Scan

All sudo calls in `install-docker.sh` use hard-coded command paths with no user-controlled arguments — satisfies T-02-01 mitigation. The docker group membership comment explicitly warns about root-equivalent access requiring explicit re-login (T-02-04 mitigation). No new network endpoints or trust boundaries beyond those documented in the plan's threat model. No threat flags.

## Self-Check

- [x] `scripts/install-docker.sh` exists and is executable
- [x] Commit `43da4e0` exists in git log
- [x] `bash -n scripts/install-docker.sh` exits 0
- [x] `shellcheck scripts/install-docker.sh` exits 0
- [x] All 11 automated verification checks from plan pass
