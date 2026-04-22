---
phase: 01-host-foundation
plan: "01"
subsystem: infra
tags: [bash, shellcheck, bats, wsl2, asdf, docker, systemd, preflight]

# Dependency graph
requires: []
provides:
  - scripts/lib/preflight-lib.sh with ANSI helpers, ip_in_cidr() pure-bash network math, and 6 preflight_check_* callable functions
  - config/wslconfig: WSL2 NAT-mode template for %USERPROFILE%\.wslconfig
  - config/wsl.conf: per-distro systemd=true template for /etc/wsl.conf
  - config/hwclock-resume.service: systemd unit for WSL2 resume clock-skew fix
  - .tool-versions: 9 asdf-managed tool version pins
  - .env.example: GITHUB_OWNER/REPO/TOKEN contract with placeholder values
  - .gitignore: narrow secret-exclusion slice (.env, .env.local, .env.*.local)
  - docs/wsl-networking.md: mirrored-to-NAT migration procedure and PRE-14 bridge probe note
  - tests/bats/test_helper.bash: shared bats loader sourcing preflight-lib.sh
  - shellcheck and bats binaries available in ~/.local/bin for Wave 2+ verify blocks
affects:
  - 01-host-foundation/01-02 (install-docker.sh sources lib via source "$(dirname $0)/lib/preflight-lib.sh")
  - 01-host-foundation/01-03 (install-nvidia-container-toolkit.sh sources lib)
  - 01-host-foundation/01-04 (install-tools.sh sources lib; .tool-versions consumed by asdf install)
  - 01-host-foundation/01-05 (scripts/preflight.sh sources lib)
  - 01-host-foundation/01-06 (scripts/preflight.sh extended with PRE-09..14 callable functions)
  - 01-host-foundation/01-07 (tests/bats/*.bats load test_helper.bash)

# Tech tracking
tech-stack:
  added:
    - shellcheck 0.10.0 (installed to ~/.local/bin via direct binary download)
    - bats-core 1.11.0 (installed to ~/.local/bin via bats-core/install.sh)
  patterns:
    - source-guard pattern for library scripts ([[ "${BASH_SOURCE[0]}" == "$0" ]])
    - ANSI color helpers gated on [[ -t 1 ]] for CI-safe output
    - pure-bash ip_in_cidr() using bit-masking arithmetic (no ipcalc, no python)
    - preflight_check_* callable functions — each takes no args, returns 0/1, uses pass()/fail()
    - shellcheck source=/dev/null directive for dynamic dot-sources (. /etc/os-release)
    - shellcheck disable=SC1091 for BATS_TEST_FILENAME-relative dynamic sources

key-files:
  created:
    - scripts/lib/preflight-lib.sh
    - config/wslconfig
    - config/wsl.conf
    - config/hwclock-resume.service
    - .tool-versions
    - .env.example
    - docs/wsl-networking.md
    - tests/bats/test_helper.bash
  modified:
    - .gitignore (appended .env.local and .env.*.local to existing .env entry)

key-decisions:
  - "kubectl pinned to 1.35.0 (not 1.36.0) — stays within +1 minor skew of k3s v1.34.6 per Kubernetes version-skew policy"
  - "shellcheck and bats installed to ~/.local/bin via direct binary download (no sudo required in non-interactive execution environment)"
  - "shellcheck disable=SC1091 used in test_helper.bash for BATS_TEST_FILENAME-relative dynamic source paths"
  - "Second shellcheck source=/dev/null directive added in preflight_check_ubuntu_24_04() to cover both dot-sourced /etc/os-release lines"

patterns-established:
  - "Library source guard: [[ \"${BASH_SOURCE[0]}\" == \"$0\" ]] && { echo 'source this file'; exit 1; }"
  - "ANSI color block: if [[ -t 1 ]]; then ... else ... fi (CI-safe, no color when not TTY)"
  - "preflight_check_*() convention: no args, ambient state, returns 0/1, writes via pass()/fail()/warn()/info()"
  - "ip_in_cidr(): pure bash network math with bitwise mask, no external dependencies"
  - "bats test helper: BATS_TEST_FILENAME-relative path resolution for cross-CWD sourcing"

requirements-completed: [HOST-01, HOST-02, HOST-06, HOST-07, TOOLS-01, PRE-09]

# Metrics
duration: 5min
completed: 2026-04-22
---

# Phase 1 Plan 01: Static Artifacts and Helper Library Summary

**preflight-lib.sh with 6 preflight_check_* functions + ip_in_cidr() pure-bash network math, all WSL2 config templates, asdf tool pins, .env contract, and bats/shellcheck tooling installed**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-04-22T22:10:52Z
- **Completed:** 2026-04-22T22:15:49Z
- **Tasks:** 4
- **Files modified:** 9 (8 created, 1 modified)

## Accomplishments

- Created `scripts/lib/preflight-lib.sh` — shared bash library with ANSI output helpers (section/pass/warn/fail/info/have), pure-bash ip_to_int/ip_in_cidr network math for D-02 mirrored detection, and 6 preflight_check_* callable functions (wsl_kernel, ubuntu_24_04, env_file, systemd_resolved, cgroup_v2, mirrored_mode)
- Created all four static config templates: wslconfig (explicit networkingMode=NAT + commented mirrored fallback), wsl.conf (systemd=true), hwclock-resume.service (clock-skew fix)
- Created .tool-versions pinning 9 asdf tools (kubectl 1.35.0, helm, flux2, k3d, k9s, task, jq, yq, asdf), .env.example with placeholder GITHUB_* keys, .gitignore narrow slice, docs/wsl-networking.md with 5-step migration procedure
- Created tests/bats/test_helper.bash shared loader for Wave 6 bats suites
- Installed shellcheck 0.10.0 and bats 1.11.0 to ~/.local/bin (no sudo required) so Wave 2+ verify blocks can reference them

## Task Commits

Each task was committed atomically:

1. **Task 1: Extract helper library + config templates** - `e0d441f` (feat)
2. **Task 2: Write .tool-versions, .env.example, .gitignore, docs/wsl-networking.md** - `84c9f34` (feat)
3. **Task 3: Create tests/bats/test_helper.bash** - `e64293b` (feat)
4. **Task 4: Install bats and shellcheck; fix SC1091 directives** - `df4547e` (feat)

## Files Created/Modified

- `scripts/lib/preflight-lib.sh` — shared bash library: ANSI helpers, ip_in_cidr(), 6 preflight_check_* functions; passes bash -n and shellcheck
- `config/wslconfig` — WSL2 memory/CPU/networking template; explicit networkingMode=NAT, commented mirrored fallback with docs pointer
- `config/wsl.conf` — per-distro systemd=true template with generateResolvConf and hostname=karyon-dev
- `config/hwclock-resume.service` — systemd unit: ExecStart=/sbin/hwclock --hctosys, WantedBy=suspend.target
- `.tool-versions` — 9 asdf tool version pins; kubectl=1.35.0, flux2=2.8.6, asdf=0.18.1
- `.env.example` — GITHUB_OWNER/REPO/TOKEN with ghp_REPLACE placeholder and inline comments
- `.gitignore` — added .env.local and .env.*.local to existing .env entry (narrow D-12 slice)
- `docs/wsl-networking.md` — mirrored vs NAT explanation, D-02 IP-subnet heuristic, exact 5-step wsl --shutdown migration, Windows Task Scheduler hwclock note, PRE-14 ephemeral Docker note
- `tests/bats/test_helper.bash` — bats shared loader sourcing preflight-lib.sh via BATS_TEST_FILENAME-relative path; shellcheck clean

## Decisions Made

- kubectl pinned to 1.35.0 (not 1.36.0) to stay within +1 minor skew of k3s v1.34.6 per Kubernetes version-skew policy (RESEARCH.md flagged this concern)
- shellcheck and bats installed to ~/.local/bin via direct binary download — `sudo apt-get` is not available without a password in non-interactive execution environments; `~/.local/bin` is already on PATH
- Added `# shellcheck disable=SC1091` to test_helper.bash since SCRIPTS_DIR is dynamically computed and shellcheck cannot follow the dynamic source path
- Added a second `# shellcheck source=/dev/null` directive in `preflight_check_ubuntu_24_04()` — each sourced line needs its own directive

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] SC1091 shellcheck failure on test_helper.bash dynamic source**
- **Found during:** Task 4 (shellcheck verification)
- **Issue:** `shellcheck tests/bats/test_helper.bash` exited 1 because the `source "${SCRIPTS_DIR}/lib/preflight-lib.sh"` line used a dynamically computed variable — shellcheck cannot follow it even with the `# shellcheck source=` directive present
- **Fix:** Added `# shellcheck disable=SC1091` above the source line in test_helper.bash
- **Files modified:** tests/bats/test_helper.bash
- **Verification:** `shellcheck tests/bats/test_helper.bash` exits 0
- **Committed in:** df4547e (Task 4 commit)

**2. [Rule 1 - Bug] SC1091 shellcheck failure on second /etc/os-release dot-source**
- **Found during:** Task 4 (shellcheck verification of preflight-lib.sh)
- **Issue:** `preflight_check_ubuntu_24_04()` dot-sources `/etc/os-release` twice; the plan-provided `# shellcheck source=/dev/null` directive covered only the first line — the second line triggered SC1091
- **Fix:** Added a second `# shellcheck source=/dev/null` directive before the `version_id=` line
- **Files modified:** scripts/lib/preflight-lib.sh
- **Verification:** `shellcheck scripts/lib/preflight-lib.sh` exits 0
- **Committed in:** df4547e (Task 4 commit)

**3. [Rule 3 - Blocking] shellcheck/bats installed via direct binary download (not apt-get)**
- **Found during:** Task 4 (installing shellcheck)
- **Issue:** `sudo apt-get install -y shellcheck` requires a password; non-interactive execution environment — sudo prompts for terminal input
- **Fix:** Downloaded shellcheck 0.10.0 binary from GitHub releases to `~/.local/bin`; installed bats-core 1.11.0 via its install.sh to `~/.local/bin` (no sudo required)
- **Files modified:** None committed (system binaries)
- **Verification:** `command -v shellcheck` and `command -v bats` both exit 0
- **Committed in:** df4547e (incidentally — no file changes from this fix, but the task commit covers the verification)

---

**Total deviations:** 3 auto-fixed (2 Rule 1 bugs, 1 Rule 3 blocking)
**Impact on plan:** All auto-fixes necessary for shellcheck clean exit and tool availability. No scope creep.

## Issues Encountered

- Non-interactive sudo requirement for apt-get — resolved by using direct binary downloads to ~/.local/bin (already on PATH)

## Threat Surface Scan

No new network endpoints, auth paths, or trust boundaries introduced. All files are static templates or bash libraries sourced locally. .env.example contains only placeholder values (ghp_REPLACE_WITH_PAT_WITH_repo_SCOPE) — no real secrets. .gitignore narrow slice (.env, .env.local, .env.*.local) ensures real secrets cannot be committed. No threat flags.

## Known Stubs

None — all files are complete static artifacts. No placeholder data flowing to any UI or runtime consumer.

## Next Phase Readiness

- Wave 2 plans (01-02 install-docker.sh, 01-03 install-nvidia-container-toolkit.sh, 01-04 install-tools.sh) can source `scripts/lib/preflight-lib.sh` via the established pattern
- Wave 2+ verify blocks can use `shellcheck` and `bats` commands (both available in ~/.local/bin)
- .tool-versions is ready for `asdf install` in install-tools.sh
- config/ templates are ready for install-docker.sh to copy hwclock-resume.service to /etc/systemd/system/
- No blockers for subsequent plans

---
*Phase: 01-host-foundation*
*Completed: 2026-04-22*
