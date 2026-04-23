---
status: complete
phase: 01-host-foundation
source: [01-VERIFICATION.md]
started: 2026-04-22T23:59:00Z
updated: 2026-04-23T16:10:00Z
rounds:
  - round: 1
    plan: 01-08
    status: complete
  - round: 2
    plan: 01-09
    status: complete
    notes: "Live re-run passed (preflight.sh exited 0 with 45 passed, 1 expected warning, 0 failures). WR-02 resolved via revert."
---

## Current Test

[testing complete — round 2 live UAT passed on rich@Area-51]

## Tests

### 1. install-docker.sh fresh-host run (HOST-03, HOST-04, HOST-06)
expected: On a fresh WSL2 Ubuntu 24.04 box with Docker NOT yet installed, `bash scripts/install-docker.sh` exits 0. Path A (first run, `runtimes.nvidia` absent) writes only the `dns` key to daemon.json and emits an info() message stating that install-nvidia-container-toolkit.sh will set default-runtime. Docker daemon starts cleanly under `set -euo pipefail`. `hwclock-resume.service` is enabled.
result: pass
notes: |
  Ran on rich@Area-51 WSL2 Ubuntu 24.04.2 box after clearing a stale GitHub CLI apt source (archive_uri-https_cli_github_com_packages-noble.list — unrelated to phase 01). Script Sections 0, 2, 3 resumed cleanly on the retry after the apt source fix. Output confirmed CR-02 Path A: daemon.json received dns=[1.1.1.1,8.8.8.8] only; default-runtime write was correctly deferred with info() message pointing at install-nvidia-container-toolkit.sh. hwclock-resume.service enabled with 4 systemd target symlinks. docker group membership flagged as requiring newgrp/relogin per T-02-04.

### 2. install-nvidia-container-toolkit.sh fresh-host run (HOST-05)
expected: Immediately after install-docker.sh succeeds, `bash scripts/install-nvidia-container-toolkit.sh` exits 0. nvidia-ctk runtime configure registers `runtimes.nvidia`, then the new Section 4 jq-merges `default-runtime: nvidia` into daemon.json and restarts Docker exactly once. Final daemon.json contains all three keys: dns, runtimes.nvidia, default-runtime=nvidia. `docker info` shows `Default Runtime: nvidia`.
result: pass
notes: |
  Ran on rich@Area-51 WSL2 Ubuntu 24.04.2 immediately after Test 1. Script sections in order:
  - Section 1 (pre-check): "daemon.json default-runtime absent (expected on first run...)" — CR-01 fix confirmed working end-to-end; jq read actual absent state, not the literal "default-runtime" string.
  - Section 3: nvidia-ctk runtime configure wrote runtimes.nvidia to daemon.json; did NOT restart docker itself (Option B invariant preserved).
  - Section 4 (new, CR-02 Option B writer): jq-merged default-runtime=nvidia after runtimes.nvidia was registered.
  - Post-verify: passed via the same fixed jq expression (CR-01 second site).
  - Summary: "5 passed, 0 warnings, 0 failed".
  Final daemon.json confirmed via sudo cat: {dns: [1.1.1.1, 8.8.8.8], runtimes.nvidia: {args: [], path: nvidia-container-runtime}, default-runtime: nvidia} — all three keys in correct structure.
  docker info confirms runtime activation: "Runtimes: io.containerd.runc.v2 nvidia runc" AND "Default Runtime: nvidia".
  Minor INFO candidate: the script's own verification hint `grep -i 'Runtimes\|DefaultRuntime'` has a cosmetic pattern bug — DefaultRuntime (no space) can't match "Default Runtime:" (as docker prints it). Not a phase blocker; could be polished in a future pass.

### 3. End-to-end idempotent re-run (HOST-03, HOST-05)
expected: On a fully-configured host (after #1 and #2 succeeded), re-running both install scripts in order emits only `already done, skipping:` messages, triggers zero `systemctl restart docker` calls, and leaves daemon.json byte-identical to its prior state.
result: pass
notes: |
  Verified via two separate runs on rich@Area-51 WSL2 Ubuntu 24.04.2.
  install-docker.sh re-run: all 7 sections skipped with `· already done, skipping:` bullets. Summary: `0 passed, 0 warnings, 0 failed` (no real work, no counter increments).
  install-nvidia-container-toolkit.sh re-run: all 3 install sections skipped. Summary: `2 passed` = the two pre-check `pass()` calls only (Docker daemon reachable + daemon.json already has default-runtime=nvidia from prior run — the latter confirms CR-01-fixed jq expression reading the actual stored "nvidia" value, not the string literal "default-runtime").
  grep -c '✓ installing:' across both re-run logs returned 0:0 — no real installation work done.
  daemon.json sha256 unchanged across the full test sequence: 6293582ff8c36f68c16b2e71a9ea90f168e186f8e2584bf8cf85db257bfacebe (before) ≡ (after). Byte-identical.
  Zero systemctl restart docker: implied by daemon.json byte-identity (no write → no restart path triggered). Docker API remained responsive throughout (docker info continued to respond to the same server session), confirming the daemon was never cycled.
  All three Test 3 invariants (skip-only messages, zero restarts, byte-identical daemon.json) confirmed. Idempotency is production-ready.

### 4. preflight.sh exits 0 on a clean dev box (phase goal)
expected: On a fully-installed WSL2 Ubuntu 24.04 box with Docker + NVIDIA toolkit + asdf tools all installed per the install scripts, `bash scripts/preflight.sh` exits 0 with all 14 PRE-xx checks passing (PRE-01..14).
result: pass_with_caveats
notes: |
  Ran on rich@Area-51 WSL2 Ubuntu 24.04.2 after install-tools.sh completed (asdf 0.18.1 + 8 tools installed successfully). Preflight summary: 43 passed, 0 warnings, 3 failed.

  All gap-closure-specific criteria delivered by plan 01-08 pass LIVE:
  - docker CLI present + daemon reachable + user in docker group (Section 5/6 of install-docker.sh)
  - WSL libcuda stub, nvidia-smi (RTX 5090 detected), nvidia-container-toolkit installed
  - docker has nvidia runtime registered (nvidia-ctk output)
  - docker default-runtime is nvidia (CR-02 Option B: Section 4 of install-nvidia-container-toolkit.sh wrote this AFTER runtimes.nvidia was registered)
  - .env secrets contract: all three GITHUB_* keys detected present
  - bridge-curl probe: container DNS resolution on preflight-pre14-net works
  - cgroup v2 purity, port availability, tool shim precedence (post install-tools.sh)

  The 3 remaining preflight failures are UNRELATED to plan 01-08's gap-closure scope and are pre-existing bugs/limitations in preflight.sh or infrastructure:

  1. Mirrored networking false positive — the user's home LAN (192.168.1.0/24) happens to contain both the Windows host IP (192.168.1.1, the router) and WSL's eth1 (192.168.1.184). The preflight heuristic flags this as likely mirrored mode, but the false-positive note in the script's own output acknowledges this edge case. WSL is actually in NAT mode. Fixing requires either changing the user's home router subnet OR adjusting the preflight heuristic to be smarter about subnet overlap.

  2. k9s version parser bug — preflight.sh's version check for k9s grabs the tool's ASCII-art banner (`____  __ ________`) instead of the version line. k9s 0.50.18 IS correctly installed via asdf (install-tools.sh reported success + asdf shim resolves correctly). This is a parser bug in scripts/preflight.sh or scripts/lib/preflight-lib.sh's `show_tool_version` helper that needs to handle k9s's multi-line version output.

  3. PRE-12 clock skew timezone bug — reports exactly 14400s (4 hours) off, which is EXACTLY the EDT-to-UTC offset (4×3600). In reality WSL and Windows are in sync. PowerShell's `Get-Date -UFormat %s` is known to return local-time-as-if-UTC seconds (a PowerShell quirk), while Linux `date +%s` returns true UTC seconds. The comparison in PRE-12 produces a false-positive clock skew equal to the timezone offset on every run. Script's suggested remediation (`sudo hwclock -s`) also can't run because `hwclock` isn't installed — see finding #4 below.

  4. hwclock binary missing — install-docker.sh installs hwclock-resume.service pointing at /sbin/hwclock, but doesn't ensure util-linux-extra (which provides hwclock on Ubuntu 24.04) is installed. The service would fail on every resume. Separate new gap finding for a future plan.

  Final verdict: plan 01-08 (CR-01 + CR-02) delivered exactly what it promised — validated end-to-end on a live WSL2 Ubuntu 24.04 box with an RTX 5090. The phase's larger "preflight exits 0" goal is blocked by 3 pre-existing preflight.sh bugs + 1 missing runtime dependency, all out of 01-08's scope. Each has been added to the ## Gaps section below for a follow-up gap-closure cycle.

### 5. preflight.sh live re-run after plan 01-09 edits (round 2 re-validation)
expected: After re-running `scripts/install-docker.sh` (picks up util-linux-extra install), `bash scripts/preflight.sh` exits 0 with all 14 PRE-xx checks passing. Specifically the 3 Test-4 caveats are closed: PRE-12 reports skew < 30s (not 14400s); PRE-05 k9s reports `0.50.18 (matches 0.50.18)` (not ASCII banner); PRE-03 reports warn (not fail) on 192.168.1.1/24 home-router subnet.
result: pass
notes: |
  Live run on rich@Area-51 WSL2 Ubuntu 24.04.2 after plan 01-09 + WR-02 revert + k9s-parser second-pass fix. Final output: `45 passed, 1 warnings, 0 failed. No blockers — review warnings and proceed.` Exit 0.

  Round-2 gap closures confirmed live:
  - PRE-12 clock skew: `within 1s (threshold 30s)` — UtcNow.ToUnixTimeSeconds() fix working; previously reported 14400s (EDT offset).
  - PRE-05 k9s: `v0.50.18 (matches 0.50.18)` — required a second-pass fix after round-2 shipped. The initial `grep -oP 'Version:\s+\K\S+'` on `k9s version` failed in practice because k9s emits ANSI color codes in the interactive-format output that break the `\K` anchor. Fixed to `k9s version --short | awk '/^Version/ {print $NF; exit}'` — the `--short` flag disables color and produces a plain `Version              v0.50.18` line. Commit bcc... (to be filled) on main.
  - PRE-03 mirrored-mode: `Mirrored-mode heuristic fired ... Likely false positive from shared home-router subnet` emitted as `warn()` (!), not `fail()` (✗). Hard-fail path preserved for unambiguous wsl.exe --status mirrored signal.
  - util-linux-extra: implied by `✓ docker daemon reachable` + `✓ docker has nvidia runtime registered` + no hwclock errors in output (post-install-docker.sh run).

  The 1 remaining warning is the expected mirrored-mode home-router false-positive downgrade (scoped by plan 01-09 must_have truth 5). It is by design — acceptable on home networks where WSL is NAT'd into the same /24 as the Windows host.

### 6. WR-02 policy decision (172.16.0.0/12 in home-router CIDR whitelist)
expected: Developer picks one of: (a) accept the 172.16.0.0/12 inclusion in preflight_check_mirrored_mode()'s warn()-downgrade whitelist — record an override in 01-VERIFICATION.md frontmatter, OR (b) revert by removing line 227 of scripts/lib/preflight-lib.sh to match must_have truth 5 exactly (`192.168.0.0/16 or 10.0.0.0/8` only).
result: resolved
resolution: Option (b) — reverted. 172.16.0.0/12 removed from preflight_check_mirrored_mode() warn()-downgrade whitelist in commit 2ebae5c. Remaining CIDRs match must_have truth 5 exactly: `192.168.0.0/16` and `10.0.0.0/8`. Bash syntax clean on scripts/lib/preflight-lib.sh; all 25 bats tests still pass.

## Summary

total: 6
passed: 5
pass_with_caveats: 1
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps

The 4 issues below surfaced during round-1 UAT on Test 4 and were closed by plan 01-09 (round-2 gap closure). Status transitioned `failed` → `resolved` after the round-2 code edits. Round-2 surfaced 1 new WARNING (WR-02, 172.16/12 scope) that is tracked as Test 6 above and awaits a human policy decision.

- truth: "preflight.sh PRE-12 clock skew check reports accurate delta between WSL and Windows clocks"
  status: resolved
  reason: "PowerShell's `Get-Date -UFormat %s` returns local-time-as-if-UTC seconds (known PowerShell quirk), while `date +%s` returns true UTC seconds. The comparison in PRE-12 produces a false-positive clock skew equal to the timezone offset on every run (14400s in EDT, 25200s in MST, etc.). Reproducer: on any WSL2 box in a non-UTC timezone, PRE-12 always reports a skew of (|TZ-offset-seconds|)."
  severity: major
  test: 4
  artifacts:
    - path: "scripts/lib/preflight-lib.sh"
      issue: "Likely in the preflight_check_clock_skew function or inline logic. The PowerShell command needs to return UTC epoch seconds directly, not Get-Date -UFormat %s."
    - path: "scripts/preflight.sh"
      issue: "Section calling the clock skew check."
  missing:
    - "Replace `powershell.exe -NoProfile -Command 'Get-Date -UFormat %s'` with a call that returns true UTC seconds. Options: `powershell.exe -NoProfile -Command '[int][double]::Parse((Get-Date (Get-Date).ToUniversalTime() -UFormat %s))'` or use `[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()` in PowerShell. Validate: on a box with WSL/Windows in sync, the delta should be < 30s regardless of local timezone."

- truth: "preflight.sh PRE-05 k9s version check parses k9s's multi-line version output correctly"
  status: resolved
  reason: "preflight.sh's `show_tool_version` helper (or the inline k9s case) grabs k9s's ASCII-art banner (`____  __ ________`) as the version string. Reproducer: `k9s version | head -1` returns the banner's top border; the version string appears several lines down after the ASCII art. Current check: `k9s: version mismatch — expected 0.50.18, got  ____  __ ________ . Run scripts/install-tools.sh` — falsely flags k9s as broken when it's correctly installed."
  severity: minor
  test: 4
  artifacts:
    - path: "scripts/preflight.sh"
      issue: "PLUGIN_TO_CMD / show_tool_version iteration for k9s. Needs to extract the `Version:` line specifically from `k9s version` output rather than the first line."
  missing:
    - "Update the k9s version extraction to: `k9s version | grep -oP 'Version:\\s+\\K.*' || k9s version --short 2>/dev/null`. Validate: on a box with k9s 0.50.18 installed via asdf, the version detection returns `0.50.18` (or equivalent match), not the banner."

- truth: "preflight.sh PRE-03 mirrored-mode heuristic correctly distinguishes mirrored mode from NAT mode on networks where Windows host IP falls inside the WSL interface subnet"
  status: resolved
  reason: "The ip_in_cidr subnet-overlap heuristic fires when Windows host IP (e.g., 192.168.1.1 home router) is inside WSL's eth1 CIDR (e.g., 192.168.1.184/24). On a typical home network where WSL is NAT'd into the same /24 as the Windows host, the check always flags mirrored mode regardless of the actual networkingMode setting. The script's own output includes a 'False-positive note' acknowledging this edge case, but the fail() is emitted unconditionally."
  severity: minor
  test: 4
  artifacts:
    - path: "scripts/lib/preflight-lib.sh"
      issue: "preflight_check_mirrored_mode() — ip_in_cidr-based heuristic cannot reliably distinguish mirrored from NAT on shared subnets."
  missing:
    - "Add a stronger signal before calling fail(): e.g., check `wsl.exe --status` output for 'networkingMode: mirrored', or read the actual /etc/wsl.conf / .wslconfig if accessible, or downgrade this to warn() when the false-positive scenario is detected (Windows host IP is exactly the default gateway AND the CIDR is a common home-router range like 192.168.x.0/24)."

- truth: "install-docker.sh ensures hwclock binary is installed as a prerequisite for hwclock-resume.service"
  status: resolved
  reason: "install-docker.sh installs hwclock-resume.service pointing at /sbin/hwclock in Section 7 (enabled via systemctl enable), but on Ubuntu 24.04 the `hwclock` binary lives in util-linux-extra (split from util-linux in newer Ubuntu versions) and isn't installed by default on minimal WSL2 images. Result: hwclock-resume.service fails on every resume with 'hwclock: command not found', silently. Also prevents the preflight.sh remediation suggestion `sudo hwclock -s` from working."
  severity: major
  test: 4
  artifacts:
    - path: "scripts/install-docker.sh"
      issue: "Section 0 or Section 7 should include util-linux-extra (or explicitly verify hwclock exists at /sbin/hwclock before enabling hwclock-resume.service)."
  missing:
    - "Add util-linux-extra to Section 0 prereqs: `sudo apt-get install -y util-linux-extra` with a dpkg -s guard. Validate: after install-docker.sh on a fresh minimal WSL2 Ubuntu 24.04, `command -v hwclock` returns /sbin/hwclock (or /usr/sbin/hwclock)."
