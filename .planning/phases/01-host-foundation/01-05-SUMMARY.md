---
phase: 01-host-foundation
plan: "05"
subsystem: infra
tags: [bash, shellcheck, preflight, wsl2, docker, nvidia, asdf, tool-versions]

# Dependency graph
requires:
  - 01-01 (scripts/lib/preflight-lib.sh — sourced; preflight_check_* functions called)
  - 01-04 (install-tools.sh — .tool-versions version pins consumed by PRE-05 loop)
provides:
  - scripts/preflight.sh: executable read-only preflight checker covering PRE-01..08
affects:
  - 01-06 (scripts/preflight.sh extended with PRE-09..14 callable functions)
  - 01-07 (bats tests exercise preflight_check_* functions sourced from lib)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - source-guard delegation: preflight.sh calls preflight_check_*() from lib (M4 bats-testable)
    - PRE-08 docker_desktop sock-target detection via readlink /var/run/docker.sock
    - PRE-04 default-runtime check via docker info --format '{{.DefaultRuntime}}'
    - PRE-05 .tool-versions iteration with PLUGIN_TO_CMD name-mapping declare -A
    - REPO_ROOT derivation at top of script for CWD-independent .tool-versions lookup

key-files:
  created:
    - scripts/preflight.sh
  modified: []

key-decisions:
  - "PRE-01 and PRE-02 section bodies delegate to library functions (not inline logic) so bats can invoke them directly (M4 fix)"
  - "PRE-03 calls preflight_check_mirrored_mode() — D-02 faithful IP-subnet overlap algorithm replaces 172.x gateway heuristic (H5 fix)"
  - "PRE-08 upgraded from warn to fail: Docker Desktop integration is a hard blocker for native Docker Engine (RESEARCH.md Ref-10)"
  - "PRE-04 default-runtime check added after existing nvidia runtime check; conditional on docker being reachable"
  - "SC1091 disabled on source line: path is dynamically computed via SCRIPT_DIR; shellcheck cannot follow it (same pattern as Plans 01 and 04)"
  - "asdf itself checked separately after .tool-versions loop since asdf line appears in .tool-versions but asdf manages itself"

requirements-completed: [PRE-01, PRE-02, PRE-03, PRE-04, PRE-05, PRE-06, PRE-07, PRE-08]

# Metrics
duration: 8min
completed: 2026-04-22
---

# Phase 1 Plan 05: scripts/preflight.sh Port Summary

**prereqs.sh ported to scripts/preflight.sh — sources preflight-lib.sh, delegates PRE-01/02/03 to library functions, upgrades PRE-08 Docker Desktop to fail, adds PRE-04 default-runtime check, and replaces tool list with .tool-versions version-pin loop**

## Performance

- **Duration:** ~8 min
- **Completed:** 2026-04-22
- **Tasks:** 1
- **Files modified:** 1 (created)

## Accomplishments

- Created `scripts/preflight.sh` — executable, shellcheck-clean (exit 0), bash -n clean, set -u present, set -e intentionally absent
- Header + SCRIPT_DIR/REPO_ROOT derivation at top; sources `scripts/lib/preflight-lib.sh` via shellcheck-annotated source line
- Section 1 (WSL environment): calls `preflight_check_wsl_kernel()`, `preflight_check_ubuntu_24_04()`, `preflight_check_mirrored_mode()` from lib; systemd check and interface IPs info ported verbatim
- Section 2 (System resources): ported verbatim from prereqs.sh (memory/CPU/disk floor checks)
- Section 3 (Docker): added sock_target readlink detection; PRE-08 `warn` → `fail` with remediation message pointing to scripts/install-docker.sh; remaining docker checks ported verbatim
- Section 4 (NVIDIA/GPU): all existing checks ported verbatim; added PRE-04 enhancement `docker info --format '{{.DefaultRuntime}}'` nvidia check after existing runtime check
- Section 5 (Network/ports): `check_port()` helper + loop ported verbatim
- Section 6 (Container/k8s state): k3d/kind container + k8s-net network checks ported verbatim
- Section 7 (Tools): replaced static optional/required list with `show_tool_version()` helper + `.tool-versions` version-pin loop; `PLUGIN_TO_CMD` array maps flux2→flux, task→task; version mismatch calls `fail()` not `warn()`; asdf checked separately post-loop
- Section 8 (Summary): exit 0/1 block ported verbatim from prereqs.sh

## Task Commits

1. **Task 1: Port prereqs.sh to scripts/preflight.sh with lib sourcing and targeted upgrades** — `98cef58` (feat)

## Files Created/Modified

- `scripts/preflight.sh` — 250 lines; bash -n clean; shellcheck exit 0; chmod +x; all 15 plan verify checks pass

## Decisions Made

- PRE-01/02/03 section bodies delegate to library functions rather than inlining logic — makes them callable from bats test suites (M4 fix, closes Plan 01 testability gap)
- PRE-03 uses `preflight_check_mirrored_mode()` from lib which implements the correct D-02 IP-subnet overlap algorithm, not the 172.x gateway heuristic that was in the original prereqs.sh discussion
- PRE-08 upgraded from `warn` to `fail` per RESEARCH.md §Ref-10 and CONTEXT.md D-01: Docker Desktop integration prevents native Docker Engine operation and is a hard blocker
- PRE-04 default-runtime check guarded by `have docker && docker info >/dev/null 2>&1` to avoid false positives when Docker isn't installed yet
- `SC1091` disabled on source line — same pattern established in Plans 01 and 04; dynamically computed SCRIPT_DIR path cannot be statically followed by shellcheck
- The `asdf` line in `.tool-versions` pins asdf's own version; the loop body would call `asdf --version` to verify it — this is intentional but the loop still processes it correctly via PLUGIN_TO_CMD lookup (asdf maps to itself)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing critical functionality] Added SC1091 disable for source line**
- **Found during:** Task 1 (shellcheck verification)
- **Issue:** shellcheck flagged SC1091 on `source "${SCRIPT_DIR}/lib/preflight-lib.sh"` — cannot follow dynamically computed path
- **Fix:** Added `# shellcheck disable=SC1091` on the line before the source call (same pattern as Plans 01 and 04)
- **Files modified:** scripts/preflight.sh
- **Commit:** 98cef58

---

**Total deviations:** 1 auto-fixed (Rule 2 — shellcheck compliance required for plan success criteria)
**Impact on plan:** Shellcheck compliance only; no behavioral change to the script.

## Verification Results

All structural checks passed:

| Check | Result |
|-------|--------|
| `bash -n scripts/preflight.sh` | PASS |
| `shellcheck scripts/preflight.sh` | PASS |
| `test -x scripts/preflight.sh` | PASS |
| `grep -q 'set -u'` | PASS |
| `! grep -qE '^set[[:space:]]+-[a-z]*e'` | PASS |
| `grep -q 'source.*lib/preflight-lib.sh'` | PASS |
| `! grep -q 'C_RESET=.*033'` (no inline ANSI) | PASS |
| `grep -q 'preflight_check_wsl_kernel'` | PASS |
| `grep -q 'preflight_check_ubuntu_24_04'` | PASS |
| `grep -q 'preflight_check_mirrored_mode'` | PASS |
| `grep -q 'docker_desktop=0'` | PASS |
| `grep -q 'fail.*Docker Desktop WSL integration is active'` | PASS |
| `! grep -q 'warn.*Docker Desktop WSL integration detected'` | PASS |
| `grep -q 'DefaultRuntime.*nvidia'` | PASS |
| `grep -q '.tool-versions'` | PASS |
| `grep -q 'REPO_ROOT'` | PASS |
| `grep -q 'version mismatch.*Run scripts/install-tools.sh'` | PASS |

## Threat Surface Scan

No new network endpoints or auth paths introduced. Script is read-only; it only reads system state and `.tool-versions`. The `docker info --format` call reads Docker daemon metadata (no writes). The `readlink /var/run/docker.sock` check reads socket symlink target (no writes). All output goes to stdout; no values from `.tool-versions` are echoed as secrets (tool names and version strings are not sensitive). The plan's threat model T-05-01 (`.env` read) applies to Plan 06, not this plan.

No threat flags.

## Known Stubs

None — script is complete and wired to real checks. No placeholder data or TODO markers.

## Self-Check

### Files exist
- `scripts/preflight.sh`: FOUND

### Commits exist
- `98cef58` feat(01-05): port prereqs.sh to scripts/preflight.sh with lib sourcing and upgrades: FOUND

## Self-Check: PASSED
