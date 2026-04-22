---
phase: 01-host-foundation
verified: 2026-04-22T20:30:00Z
status: gaps_found
score: 14/16 must-haves verified
overrides_applied: 0
gaps:
  - truth: "install-nvidia-container-toolkit.sh verifies default-runtime=nvidia was set by install-docker.sh before proceeding"
    status: failed
    reason: "CR-01: _key variable is set to the string '\"default-runtime\"' (with embedded double-quotes), so the jq expression expands to '\"default-runtime\" // empty' — a string literal that always evaluates to 'default-runtime', never reading the key from the JSON file. The pre-check at line 41 always sees 'default-runtime' != 'nvidia' and exits 1 on every run. The post-verify at line 101 has the identical bug. Script cannot succeed on happy path."
    artifacts:
      - path: "scripts/install-nvidia-container-toolkit.sh"
        issue: "Line 40: _key='\"default-runtime\"' — double-quotes embedded in shell value cause jq to evaluate a string literal instead of a key access. Lines 41 and 101 both use ${_key} // empty which expands to \"default-runtime\" // empty."
    missing:
      - "Replace _key variable with direct jq key access: jq -r '.\"default-runtime\" // empty' at both lines 41 and 101 (or equivalently: jq -r '.\"default-runtime\" // empty')"

  - truth: "install-docker.sh performs jq-merge to set default-runtime=nvidia and dns=[1.1.1.1,8.8.8.8] in /etc/docker/daemon.json"
    status: failed
    reason: "CR-02: install-docker.sh Section 6 writes default-runtime=nvidia to daemon.json and immediately runs 'sudo systemctl restart docker'. At this point, runtimes.nvidia does NOT exist in daemon.json (that key is written only by install-nvidia-container-toolkit.sh which runs after). Docker refuses to start when default-runtime names a runtime not defined under runtimes, so systemctl restart docker exits non-zero. Because set -euo pipefail is in effect (line 13), install-docker.sh aborts. install-nvidia-container-toolkit.sh's pre-check then requires 'docker info' to succeed, but the daemon is down — the user is wedged with no automatic recovery path."
    artifacts:
      - path: "scripts/install-docker.sh"
        issue: "Lines 116-117: writes default-runtime=nvidia to daemon.json and restarts Docker before runtimes.nvidia entry exists. Docker will refuse to start. set -euo pipefail causes the script to abort at this point on a fresh host."
    missing:
      - "Either (a) move the default-runtime write into install-nvidia-container-toolkit.sh where runtimes.nvidia is also registered in the same transaction, or (b) skip writing default-runtime in install-docker.sh if runtimes.nvidia is not yet present (emit info that it will be set by the nvidia toolkit script), or (c) add runtimes.nvidia stub before the daemon restart to prevent Docker from rejecting the config."
---

# Phase 01: Host Foundation Verification Report

**Phase Goal:** `scripts/preflight.sh` exits `0` on a clean dev box — WSL2 + Docker (with explicit `dns` + `default-runtime: nvidia`) + NVIDIA container toolkit + asdf-pinned tools are all in a reproducible, idempotent state.
**Verified:** 2026-04-22T20:30:00Z
**Status:** gaps_found — 2 CRITICAL blockers confirmed (CR-01 and CR-02 from 01-REVIEW.md)
**Re-verification:** No — initial verification

## Step 0: Previous Verification

No previous VERIFICATION.md found. Proceeding as initial mode.

## Goal Achievement

The phase produces all required static artifacts and a structurally complete preflight script. However, two install scripts have bugs that prevent execution on a fresh host. Because `scripts/preflight.sh` depends on the install scripts having run successfully (the preflight gate verifies Docker's default-runtime=nvidia, the nvidia runtime registration, and tool shim paths), the phase goal of "preflight.sh exits 0 on a clean dev box" is NOT achievable with the current install scripts.

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | scripts/preflight.sh exists, is executable, passes bash -n, and has set -u (not -e) | VERIFIED | File exists, executable bit set, bash -n exits 0, line 10: `set -u`, no `set -e` found |
| 2 | All 14 PRE-xx checks are present and structurally correct in preflight.sh | VERIFIED | PRE-01..14 all confirmed present with section() headers and correct function calls |
| 3 | scripts/lib/preflight-lib.sh exists with source guard, all helpers, ip_in_cidr(), and all 6 preflight_check_* functions | VERIFIED | Source guard at line 6, section/pass/warn/fail/info/have, ip_to_int, ip_in_cidr, all 6 check functions defined |
| 4 | config/wslconfig has explicit networkingMode=NAT and commented mirrored line | VERIFIED | Lines 7-8 of config/wslconfig confirmed |
| 5 | config/wsl.conf has [boot] systemd=true | VERIFIED | Lines 4-5 of config/wsl.conf confirmed |
| 6 | config/hwclock-resume.service is a valid systemd unit with ExecStart=/sbin/hwclock and WantedBy=suspend.target | VERIFIED | Both lines confirmed in file |
| 7 | .tool-versions pins all 9 tools with correct versions | VERIFIED | 9 lines, kubectl 1.35.0, helm 3.20.2, flux2 2.8.6, k3d 5.8.3, k9s 0.50.18, task 3.50.0, jq 1.8.1, yq 4.53.2, asdf 0.18.1 |
| 8 | .env.example has GITHUB_OWNER, GITHUB_REPO, GITHUB_TOKEN with placeholder values | UNCERTAIN | File exists (confirmed by find), content unreadable by this agent (permission restriction). Review noted the same limitation and flagged it for human review. File existence verified. |
| 9 | .gitignore contains .env, .env.local, .env.*.local | VERIFIED | Lines 5-7 of .gitignore confirmed |
| 10 | docs/wsl-networking.md has the 5-step wsl --shutdown procedure and PRE-14 ephemeral Docker note | VERIFIED | Both elements confirmed present in file |
| 11 | tests/bats/test_helper.bash exists and sources scripts/lib/preflight-lib.sh via BATS_TEST_FILENAME-relative path | VERIFIED | File at line 9 uses BATS_TEST_FILENAME, sources lib at line 15 |
| 12 | Five bats suites exist covering PRE-01/02/09/11/13, all using load 'test_helper' and calling real preflight_check_* functions | VERIFIED | All 5 files exist, all use `load 'test_helper'` (1 per file), no `../` paths in .bats files, 25/25 tests pass |
| 13 | install-nvidia-container-toolkit.sh verifies default-runtime=nvidia before proceeding — the H1 pre-check guard | FAILED | CR-01: `_key='"default-runtime"'` causes jq to evaluate a string literal, not a key access. `jq -r '"default-runtime" // empty'` returns the string `default-runtime` for any input. Pre-check always fires and exits 1. Script cannot succeed. |
| 14 | install-docker.sh idempotently sets default-runtime=nvidia and dns in daemon.json without breaking the Docker daemon | FAILED | CR-02: Section 6 writes default-runtime=nvidia and runs `sudo systemctl restart docker` before runtimes.nvidia exists. Docker refuses to start with an undefined default-runtime. `set -euo pipefail` causes script abort. User is wedged. |
| 15 | All install scripts are idempotent | PARTIAL | install-docker.sh and install-tools.sh have idempotency guards throughout (7 "already done, skipping:" instances each). install-nvidia-container-toolkit.sh has 3 guards but cannot execute past the pre-check due to CR-01. |
| 16 | install-tools.sh installs asdf binary standalone, creates ~/.karyon/shell-init.sh, adds 8 plugins, installs from .tool-versions (skipping asdf line) | VERIFIED | All structural requirements present: v0.18.1 tarball URL, shell-init section, all 8 plugins in loop, asdf skip guard at lines 129 and 144 with explanatory comment |

**Score:** 14/16 truths verified (2 failed — both CRITICAL blockers; 1 uncertain — .env.example content unverifiable)

### Deferred Items

None.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `scripts/preflight.sh` | Complete 14-check preflight gate | VERIFIED | All checks present, set -u, sources lib, exit 0/1 logic correct |
| `scripts/lib/preflight-lib.sh` | Shared helpers + preflight_check_* | VERIFIED | Source guard, 6 ANSI helpers, ip_to_int, ip_in_cidr, 6 check functions |
| `scripts/install-docker.sh` | Idempotent Docker installer | STUB-BROKEN | Structurally correct but CR-02 prevents execution on fresh host |
| `scripts/install-nvidia-container-toolkit.sh` | Idempotent NVIDIA toolkit installer | STUB-BROKEN | Structurally correct but CR-01 prevents execution past pre-check |
| `scripts/install-tools.sh` | Idempotent asdf installer | VERIFIED | All sections present, asdf skip guard, shell-init, 8 plugins |
| `config/wslconfig` | WSL2 config template with NAT | VERIFIED | networkingMode=NAT, mirrored commented with docs pointer |
| `config/wsl.conf` | Distro config template with systemd | VERIFIED | [boot] systemd=true present |
| `config/hwclock-resume.service` | systemd unit for clock-skew fix | VERIFIED | ExecStart, WantedBy=suspend.target present |
| `.tool-versions` | 9 tool pins | VERIFIED | 9 lines, all correct versions |
| `.env.example` | Secret key contract | UNCERTAIN | File exists, content unreadable by verifier agent |
| `.gitignore` | Secret exclusion slice | VERIFIED | .env, .env.local, .env.*.local present |
| `docs/wsl-networking.md` | Mirrored-to-NAT migration procedure | VERIFIED | 5-step procedure, D-02 heuristic explanation, PRE-14 note |
| `tests/bats/test_helper.bash` | Shared bats loader | VERIFIED | Sources lib via BATS_TEST_FILENAME path |
| `tests/bats/preflight-pre01.bats` | PRE-01 bats suite | VERIFIED | 5 tests, calls preflight_check_wsl_kernel |
| `tests/bats/preflight-pre02.bats` | PRE-02 bats suite | VERIFIED | 4 tests, calls preflight_check_ubuntu_24_04 |
| `tests/bats/preflight-pre09.bats` | PRE-09 bats suite | VERIFIED | 6 tests, calls preflight_check_env_file |
| `tests/bats/preflight-pre11.bats` | PRE-11 bats suite | VERIFIED | 5 tests, calls preflight_check_systemd_resolved |
| `tests/bats/preflight-pre13.bats` | PRE-13 bats suite | VERIFIED | 5 tests, calls preflight_check_cgroup_v2 |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| scripts/preflight.sh | scripts/lib/preflight-lib.sh | source "${SCRIPT_DIR}/lib/preflight-lib.sh" | WIRED | Line 16 of preflight.sh |
| scripts/install-docker.sh | scripts/lib/preflight-lib.sh | source "${SCRIPT_DIR}/lib/preflight-lib.sh" | WIRED | Line 18 of install-docker.sh |
| scripts/install-nvidia-container-toolkit.sh | scripts/lib/preflight-lib.sh | source "${SCRIPT_DIR}/lib/preflight-lib.sh" | WIRED | Line 21 of script |
| scripts/install-tools.sh | scripts/lib/preflight-lib.sh | source "${SCRIPT_DIR}/lib/preflight-lib.sh" | WIRED | Line 17 of install-tools.sh |
| scripts/install-docker.sh | config/hwclock-resume.service | UNIT_SRC="${SCRIPT_DIR}/../config/hwclock-resume.service" | WIRED | Lines 128-142 |
| scripts/install-nvidia-container-toolkit.sh | daemon.json default-runtime check | jq -r "${_key} // empty" | BROKEN | CR-01: _key embeds double-quotes, making jq expression a string literal not a key access |
| tests/bats/*.bats | scripts/lib/preflight-lib.sh | load 'test_helper' → source lib | WIRED | All 5 suites confirmed; 25/25 tests pass |
| scripts/preflight.sh PRE-05 | .tool-versions | while IFS=' ' read -r plugin expected_ver | WIRED | Lines 255-279 |
| scripts/preflight.sh PRE-03 | preflight_check_mirrored_mode() | direct call line 32 | WIRED | Uses ip_in_cidr() D-02 algorithm |
| scripts/install-tools.sh | .tool-versions | asdf install reads .tool-versions from REPO_ROOT | WIRED | Lines 115-147, with asdf self-skip guard |

### Data-Flow Trace (Level 4)

Not applicable. All phase artifacts are shell scripts and config files, not rendering components with data sources.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| preflight.sh syntax valid | bash -n scripts/preflight.sh | Exit 0 | PASS |
| install-docker.sh syntax valid | bash -n scripts/install-docker.sh | Exit 0 | PASS |
| install-nvidia-container-toolkit.sh syntax valid | bash -n scripts/install-nvidia-container-toolkit.sh | Exit 0 | PASS |
| install-tools.sh syntax valid | bash -n scripts/install-tools.sh | Exit 0 | PASS |
| preflight-lib.sh syntax valid | bash -n scripts/lib/preflight-lib.sh | Exit 0 | PASS |
| All bats tests pass | bats tests/bats/ --tap | 25 ok, 0 not ok | PASS |
| CR-01 jq bug confirmed | echo '{"default-runtime":"nvidia"}' pipe jq -r '"default-runtime" // empty' | outputs "default-runtime" (not "nvidia") | CONFIRMED BLOCKER |
| .tool-versions has 9 entries | grep -c '^[a-z]' .tool-versions | 9 | PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| HOST-01 | 01-01 | config/wslconfig with NAT mode and mirrored fallback section | SATISFIED | networkingMode=NAT + commented mirrored line with docs/wsl-networking.md pointer |
| HOST-02 | 01-01 | config/wsl.conf with systemd=true | SATISFIED | [boot] systemd=true present in config/wsl.conf |
| HOST-03 | 01-02 | install-docker.sh installs Docker Engine natively, idempotent | BLOCKED | CR-02 prevents execution on fresh host — default-runtime=nvidia written before runtimes.nvidia exists, causing Docker restart failure under set -euo pipefail |
| HOST-04 | 01-02 | daemon.json sets default-runtime: nvidia and explicit dns | BLOCKED | Depends on HOST-03 succeeding; CR-02 blocks the daemon.json write reaching a stable state |
| HOST-05 | 01-03 | install-nvidia-container-toolkit.sh installs nvidia-ctk, configures runtime, idempotent | BLOCKED | CR-01 causes pre-check to always exit 1 (jq string literal bug) |
| HOST-06 | 01-02 | systemd unit runs hwclock -s on resume | SATISFIED (script) | config/hwclock-resume.service correct; install-docker.sh Section 7 wires it correctly — but HOST-06 also blocked by CR-02 preventing install-docker.sh from completing |
| HOST-07 | 01-01 | docs/wsl-networking.md with mirrored→NAT procedure | SATISFIED | 5-step procedure, D-02 detection explanation, PRE-14 note all present |
| TOOLS-01 | 01-01 | .tool-versions pins all tools | SATISFIED | 9 pins, all correct versions, flux2 (not flux) |
| TOOLS-02 | 01-04 | install-tools.sh installs asdf plugins and pinned versions idempotently | SATISFIED | All structural requirements met; asdf self-skip guard present |
| TOOLS-03 | 01-04 | asdf shim directory precedes /usr/bin in PATH | SATISFIED | ~/.karyon/shell-init.sh with PATH prepend; PRE-10 enforces shim precedence |
| PRE-01 | 01-05 | preflight.sh exists, read-only, exits 0/1 | SATISFIED (structure) | Script exists, executable, set -u, exit logic correct — but cannot be meaningfully tested until install scripts work |
| PRE-02 | 01-05 | Verifies WSL2 kernel, Ubuntu 24.04, active systemd | SATISFIED | preflight_check_wsl_kernel(), preflight_check_ubuntu_24_04(), systemd check all present |
| PRE-03 | 01-05 | Resource floor (cores, RAM, disk) | SATISFIED | Memory/CPU/disk checks in Section 2 of preflight.sh |
| PRE-04 | 01-05 | GPU chain: libcuda.so, nvidia-smi, driver version, nvidia-ctk, Docker runtime | SATISFIED | All GPU chain checks present in Section 4, including default-runtime check |
| PRE-05 | 01-05 | Tool versions match .tool-versions pins | SATISFIED | Loop at lines 266-279, version mismatch calls fail() |
| PRE-06 | 01-05 | Ports 6443-6445 and 8080-8082 free | SATISFIED | check_port loop in Section 5 covers all 6 ports |
| PRE-07 | 01-05 | Detect k3d-* containers and k8s-net network | SATISFIED | k3d_n check and k8s-net network check in Section 6 |
| PRE-08 | 01-05 | Docker Desktop WSL integration detected, fails with remediation | SATISFIED | fail() call at line 99 with actionable message |
| PRE-09 | 01-06 | .env exists, GITHUB_* keys non-empty | SATISFIED | preflight_check_env_file() call at line 291 |
| PRE-10 | 01-06 | kubectl/helm/k3d resolve under asdf shims | SATISFIED | SHIM_DIR check for all 3 tools in Section PRE-10 |
| PRE-11 | 01-06 | resolv.conf 127.0.0.53 stub detection | SATISFIED | preflight_check_systemd_resolved() call at line 313 |
| PRE-12 | 01-06 | Clock skew > 30s detection | SATISFIED | powershell.exe primary + sudo hwclock fallback, 30s threshold |
| PRE-13 | 01-06 | cgroup v2 purity | SATISFIED | preflight_check_cgroup_v2() call at line 349 |
| PRE-14 | 01-06 | Bridge-curl probe with trap cleanup | SATISFIED | preflight-pre14-* names, EXIT trap, straggler cleanup, post-verify |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| scripts/install-nvidia-container-toolkit.sh | 40-41 | `_key='"default-runtime"'` then `jq -r "${_key} // empty"` — string literal, not key access | BLOCKER | Script cannot succeed on happy path; pre-check always exits 1 |
| scripts/install-nvidia-container-toolkit.sh | 101 | Same `_key` variable used in post-verify — same bug | BLOCKER | Post-verify is also permanently broken |
| scripts/install-docker.sh | 116 | `sudo systemctl restart docker` immediately after writing default-runtime=nvidia, before runtimes.nvidia exists | BLOCKER | Docker daemon refuses to start with undefined default-runtime; set -euo pipefail causes script abort |
| scripts/preflight.sh | 427 | Comment `---------- 8. Summary ----------` is mis-numbered (should be 15 or "Final") | INFO | Cosmetic only — IN-02 from review |
| scripts/lib/preflight-lib.sh | 112-121 | PRE-09 check accepts `GITHUB_TOKEN=""` (quoted-empty string) as "set" | WARNING | WR-01 from review — masked configuration error, not a security hole |
| scripts/preflight.sh | 200 | `--filter 'name=k3d-'` is substring match, not prefix anchor | WARNING | WR-07 from review — may overcount containers |
| scripts/preflight.sh | 220 | `grep -c '"name"'` overcounts k3d clusters | WARNING | WR-06 from review — cosmetic display issue |

### Human Verification Required

#### 1. .env.example Content

**Test:** Read the file `.env.example` and confirm it contains: GITHUB_OWNER with placeholder, GITHUB_REPO with placeholder, GITHUB_TOKEN=ghp_REPLACE... with inline comments
**Expected:** Three GITHUB_* keys with placeholder values and explanatory comments
**Why human:** File permission restriction prevents programmatic read by this agent; the review agent had the same restriction. File existence is confirmed (find returns it).

#### 2. install-docker.sh Live Execution on Fresh Host

**Test:** On a fresh WSL2 Ubuntu 24.04 box with Docker NOT yet installed, run `bash scripts/install-docker.sh` and observe whether it exits 0 or fails at the `systemctl restart docker` call in Section 6
**Expected after CR-02 fix:** Script exits 0, Docker daemon running, daemon.json has both default-runtime=nvidia and dns array
**Current behavior (unfixed):** Script aborts at `systemctl restart docker` because default-runtime names an undefined runtime; Docker refuses to start
**Why human:** Cannot run live Docker installation in this environment

#### 3. install-nvidia-container-toolkit.sh Live Execution after Docker Install

**Test:** On a configured Docker host (install-docker.sh successfully run), run `bash scripts/install-nvidia-container-toolkit.sh` and observe whether it passes the pre-check
**Expected after CR-01 fix:** Pre-check reads `."default-runtime"` from daemon.json and correctly returns "nvidia"; script proceeds
**Current behavior (unfixed):** Pre-check always fails (`"default-runtime" != "nvidia"`) because the jq expression is a string literal
**Why human:** Cannot run live NVIDIA toolkit installation in this environment

## Gaps Summary

Two CRITICAL blockers prevent the install pipeline from executing on a fresh host:

**CR-01 (install-nvidia-container-toolkit.sh lines 40, 101):** The `_key` variable is set to the string `'"default-runtime"'` — a shell string containing literal double-quote characters. When interpolated into `jq -r "${_key} // empty"`, the resulting jq expression is `"default-runtime" // empty`, which is a jq string constant. jq evaluates string constants to themselves; it never reads the JSON file. The `_dr_check` variable always gets the value `default-runtime`, which never equals `nvidia`, so the pre-check always exits 1. The fix is to use `jq -r '."default-runtime" // empty'` directly (no _key variable).

**CR-02 (install-docker.sh Section 6, line 116):** The script writes `{"default-runtime":"nvidia","dns":[...]}` to daemon.json and immediately runs `sudo systemctl restart docker`. Docker's daemon requires that any runtime named in `default-runtime` also appear under `runtimes`. The `runtimes.nvidia` entry is added only by `nvidia-ctk runtime configure --runtime=docker`, which runs in `install-nvidia-container-toolkit.sh` (a later script). On a fresh host with no NVIDIA toolkit installed, Docker exits non-zero and the script aborts under `set -euo pipefail`. The toolkit installer's own pre-check then requires `docker info` to succeed, which it cannot because the daemon is down. The user has no automated recovery path. The fix is to either move the `default-runtime` write into the toolkit installer where `runtimes.nvidia` is registered in the same transaction, or conditionally skip the `default-runtime` write if `runtimes.nvidia` is not yet present.

Both bugs were identified in 01-REVIEW.md as CR-01 and CR-02. The codebase retains both bugs in their original form — neither was patched post-review.

All static artifacts (config templates, .tool-versions, docs, preflight-lib.sh, preflight.sh, bats suites) are structurally correct and the 25 bats tests pass. The blocker is exclusively in the two install scripts.

---

_Verified: 2026-04-22T20:30:00Z_
_Verifier: Claude (gsd-verifier)_
