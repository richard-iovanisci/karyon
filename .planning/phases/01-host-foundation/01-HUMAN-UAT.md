---
status: partial
phase: 01-host-foundation
source: [01-VERIFICATION.md]
started: 2026-04-22T23:59:00Z
updated: 2026-04-22T23:59:00Z
---

## Current Test

[awaiting human testing — requires live WSL2 Ubuntu 24.04 box]

## Tests

### 1. install-docker.sh fresh-host run (HOST-03, HOST-04, HOST-06)
expected: On a fresh WSL2 Ubuntu 24.04 box with Docker NOT yet installed, `bash scripts/install-docker.sh` exits 0. Path A (first run, `runtimes.nvidia` absent) writes only the `dns` key to daemon.json and emits an info() message stating that install-nvidia-container-toolkit.sh will set default-runtime. Docker daemon starts cleanly under `set -euo pipefail`. `hwclock-resume.service` is enabled.
result: [pending]

### 2. install-nvidia-container-toolkit.sh fresh-host run (HOST-05)
expected: Immediately after install-docker.sh succeeds, `bash scripts/install-nvidia-container-toolkit.sh` exits 0. nvidia-ctk runtime configure registers `runtimes.nvidia`, then the new Section 4 jq-merges `default-runtime: nvidia` into daemon.json and restarts Docker exactly once. Final daemon.json contains all three keys: dns, runtimes.nvidia, default-runtime=nvidia. `docker info` shows `Default Runtime: nvidia`.
result: [pending]

### 3. End-to-end idempotent re-run (HOST-03, HOST-05)
expected: On a fully-configured host (after #1 and #2 succeeded), re-running both install scripts in order emits only `already done, skipping:` messages, triggers zero `systemctl restart docker` calls, and leaves daemon.json byte-identical to its prior state.
result: [pending]

### 4. preflight.sh exits 0 on a clean dev box (phase goal)
expected: On a fully-installed WSL2 Ubuntu 24.04 box with Docker + NVIDIA toolkit + asdf tools all installed per the install scripts, `bash scripts/preflight.sh` exits 0 with all 14 PRE-xx checks passing (PRE-01..14).
result: [pending]

## Summary

total: 4
passed: 0
issues: 0
pending: 4
skipped: 0
blocked: 0

## Gaps
