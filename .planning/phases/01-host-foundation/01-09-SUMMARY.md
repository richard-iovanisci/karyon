---
phase: 01-host-foundation
plan: "09"
subsystem: infra
tags: [bash, preflight, wsl2, powershell, shellcheck, bats, docker, hwclock]

requires:
  - phase: 01-host-foundation
    plan: "02"
    provides: preflight-lib.sh with ip_in_cidr/ip_to_int helpers and check functions
  - phase: 01-host-foundation
    plan: "05"
    provides: install-docker.sh with Section 0 prereqs pattern and guarded-sections (D-05)
  - phase: 01-host-foundation
    plan: "06"
    provides: bats test suite (25 tests) as regression harness

provides:
  - PRE-12 reports accurate clock skew on non-UTC hosts (no TZ-offset false positive)
  - PRE-05 k9s version check extracts the actual semver (not ASCII-art banner border)
  - PRE-03 mirrored-mode check downgrades to warn() on home-router false positive; hard-fails on unambiguous mirrored
  - install-docker.sh Section 0 installs util-linux-extra so /sbin/hwclock exists for hwclock-resume.service

affects: [01-host-foundation verification, 01-HUMAN-UAT re-run, UAT Test 4 re-run on rich@Area-51]

tech-stack:
  added: []
  patterns:
    - "Authoritative-signal-before-heuristic: consult wsl.exe --status before falling through to subnet-overlap heuristic"
    - "warn()-downgrade for false-positive pattern: two corroborating signals required (gateway equality + RFC1918 CIDR)"
    - "UTC-anchored PowerShell: [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() instead of Get-Date -UFormat %s"
    - "PCRE lookahead extraction: grep -oP 'Pattern:\\s+\\K\\S+' for structured CLI output parsing"

key-files:
  created: []
  modified:
    - scripts/lib/preflight-lib.sh
    - scripts/preflight.sh
    - scripts/install-docker.sh

key-decisions:
  - "PRE-03 warn()-downgrade only fires when BOTH gateway-equality AND RFC1918 home-router CIDR are true AND wsl.exe does not confirm mirrored — preserves D-01 hard-fail for unambiguous mirrored mode"
  - "Get-Date -UFormat %s replaced with [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() — the former returns local-time-as-if-UTC seconds causing false TZ-offset skew"
  - "dpkg -s util-linux-extra used as idempotency guard (not command -v hwclock) because PATH may not include /sbin in non-login shells"
  - "No new bats suites added — existing 25-test suite is the regression harness; all 4 fixes are confirmed clean"

patterns-established:
  - "Step 0 authoritative check before heuristic: prevents false-positive failures from subnet-overlap logic"
  - "RFC1918 home-router CIDR detection via ip_in_cidr reuse: 192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12"

requirements-completed:
  - HOST-06
  - HOST-01
  - PRE-03
  - PRE-05
  - PRE-12
  - TOOLS-01

duration: 4min
completed: "2026-04-23"
---

# Phase 01 Plan 09: Gap Closure (PRE-12 TZ, PRE-05 k9s, PRE-03 mirrored, util-linux-extra) Summary

**Four surgical fixes to preflight.sh, preflight-lib.sh, and install-docker.sh closing all UAT gaps from 01-HUMAN-UAT.md Test 4; 25/25 bats tests pass with no regression.**

## Performance

- **Duration:** ~4 min
- **Started:** 2026-04-23T14:42:57Z
- **Completed:** 2026-04-23T14:46:45Z
- **Tasks:** 4 (3 implementation + 1 verification)
- **Files modified:** 3

## Accomplishments

- PRE-12 now calls `[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()` — returns true UTC epoch regardless of Windows host TZ, eliminating the 14400s (EDT) / 25200s (MDT) false-positive clock skew
- PRE-05 k9s version extraction uses `grep -oP 'Version:\s+\K\S+'` — captures the actual semver from the `Version:` line instead of the ASCII-art banner's top border line
- PRE-03 mirrored-mode heuristic now consults `wsl.exe --status` first (hard-fail on `networkingMode: mirrored`), and downgrades to `warn()` when the subnet-overlap fires on a home-router RFC1918 subnet where the Windows host IS the default gateway and wsl.exe does not confirm mirrored mode
- install-docker.sh Section 0 now installs `util-linux-extra` (guarded by `dpkg -s util-linux-extra`) so `/sbin/hwclock` exists on minimal WSL2 Ubuntu 24.04 images, making `hwclock-resume.service`'s `ExecStart=/sbin/hwclock --hctosys` functional

## Task Commits

1. **Task 1: PRE-03 mirrored-mode warn-downgrade** - `7934de7` (fix)
2. **Task 2: PRE-12 UTC epoch fix and PRE-05 k9s parser** - `b38047f` (fix)
3. **Task 3: util-linux-extra in install-docker.sh Section 0** - `7d0d44e` (fix)
4. **Task 4: Regression verification** - no commit (pure verification, 27/27 checks passed)

## Files Created/Modified

- `scripts/lib/preflight-lib.sh` — `preflight_check_mirrored_mode()` replaced with 3-policy version: Step 0 wsl.exe authoritative check, warn()-downgrade for home-router false positive, hard-fail for non-home-router overlap
- `scripts/preflight.sh` — PRE-12 PowerShell call updated to `[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()`; PRE-05 k9s case updated to `grep -oP 'Version:\s+\K\S+'`
- `scripts/install-docker.sh` — Section 0 extended with `util-linux-extra` in guard condition, `apt-get install` line, section header, and log messages

## Gap Details

### Gap 1 — PRE-12 Clock Skew False Positive (MAJOR)

**Root cause:** `powershell.exe -NoProfile -Command 'Get-Date -UFormat %s'` uses the local clock and formats it as if it were UTC. On a host in EDT (UTC-4), it returns a value 14400 seconds behind the WSL UTC clock — well above the 30s threshold.

**Fix:** Replace with `[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()`. `DateTimeOffset.UtcNow` is pinned to UTC; `ToUnixTimeSeconds()` returns a 64-bit integer with no TZ influence. No change to the surrounding skew arithmetic, fallback block, or threshold.

**Reference:** `.planning/phases/01-host-foundation/01-HUMAN-UAT.md` §Gaps gap 1.

### Gap 2 — hwclock Binary Missing (MAJOR)

**Root cause:** Ubuntu 24.04 ("noble") split `hwclock` out of `util-linux` into `util-linux-extra`. Minimal WSL2 images do not install it. `install-docker.sh` Section 7 enables `hwclock-resume.service` with `ExecStart=/sbin/hwclock --hctosys`, but the binary was absent — the unit silently fails on every resume.

**Fix:** Added `util-linux-extra` to Section 0's guard condition (`dpkg -s util-linux-extra >/dev/null 2>&1`) and `apt-get install` line. Section 7 and `config/hwclock-resume.service` are untouched — root cause was the missing binary, not a misconfigured unit.

**Reference:** `.planning/phases/01-host-foundation/01-HUMAN-UAT.md` §Gaps gap 2.

### Gap 3 — PRE-05 k9s Version Parser (MINOR)

**Root cause:** `k9s version | head -1` captured the first line of k9s output, which is the ASCII-art banner top border (`____  __ ________`), not the version string. The version appears several lines later as `Version:    v0.50.18`.

**Fix:** `k9s version 2>/dev/null | grep -oP 'Version:\s+\K\S+'`. The PCRE `\K` resets the match start so only the token after `Version:` is printed (`v0.50.18`). The downstream comparison at line 274 uses `grep -qF "$expected_ver"` (substring match) — `v0.50.18` contains `0.50.18` so the pin comparison still passes.

**Reference:** `.planning/phases/01-host-foundation/01-HUMAN-UAT.md` §Gaps gap 3.

### Gap 4 — PRE-03 Mirrored-Mode False Positive (MINOR)

**Root cause:** The D-02 subnet-overlap heuristic fires whenever the Windows host IP (derived from the default gateway) falls inside a WSL interface CIDR. On a home network where Windows is the router (e.g., gateway 192.168.1.1, WSL eth0 192.168.1.184/24), the heuristic always fires even though WSL is in NAT mode.

**Fix (three-policy mirrored-mode function):**
1. **Step 0 — Authoritative:** `wsl.exe --status | grep -qiE 'networkingMode:\s*mirrored'` → hard-fail immediately (D-01 preserved)
2. **Home-router false positive** — subnet-overlap AND `windows_ip == gw_ip` (gateway-source only) AND CIDR inside 192.168.0.0/16 OR 10.0.0.0/8 OR 172.16.0.0/12 AND wsl.exe did NOT confirm mirrored → `warn()` with actionable message
3. **Other overlap** (non-home-router CIDR, or wsl.exe unavailable/ambiguous) → `fail()` (D-01 preserved)

**Reference:** `.planning/phases/01-host-foundation/01-HUMAN-UAT.md` §Gaps gap 4; D-01, D-03.

## Regression Check — bats 25/25

All 27 Task 4 verification checks passed:
- `bash -n` on all 3 modified files: OK
- `shellcheck` on all 3 modified files: OK
- `bats tests/bats/ --tap`: 25 ok, 0 not ok
- Plan 01-08 CR-01 (`_key=` in install-nvidia-container-toolkit.sh == 0): OK
- Plan 01-08 CR-02 (`runtimes.nvidia` guard + `deferring default-runtime` in install-docker.sh): OK
- All Gap 1–4 invariants: OK

## Decisions Made

- `warn()`-downgrade requires BOTH corroborating signals (gateway-equality AND home-router RFC1918 CIDR) — single signal insufficient to override D-01 hard-fail intent
- `dpkg -s util-linux-extra` preferred over `command -v hwclock` as the idempotency guard because `/sbin` may not be on PATH in non-login shells
- Comment in preflight.sh referencing the old PowerShell command was worded to avoid the literal `Get-Date -UFormat %s` string (which would trigger the `grep -c == 0` invariant check)

## Deviations from Plan

None — plan executed exactly as written. The comment wording adjustment (avoiding the literal old PowerShell string in the code comment) was a minor implementation detail required to satisfy the plan's own verification invariant, not a scope change.

## Next Steps

Re-run Test 4 from `.planning/phases/01-host-foundation/01-HUMAN-UAT.md` on the live `rich@Area-51` WSL2 Ubuntu 24.04 box with RTX 5090. The 3 `pass_with_caveats` items (PRE-12 TZ false positive, PRE-05 k9s banner, PRE-03 home-subnet false positive) should now report `pass`, and the hwclock gap (gap 2) should be closed after re-running `scripts/install-docker.sh`. Once all 4 gaps are verified as closed, run `/gsd-verify-phase 01` to complete the phase.

---
*Phase: 01-host-foundation*
*Completed: 2026-04-23*
