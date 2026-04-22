---
phase: 1
slug: host-foundation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-22
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bats-core (bash-native) + `shellcheck` static analysis |
| **Config file** | `tests/bats/` (create in Wave 0 if missing) |
| **Quick run command** | `bats tests/bats/ --tap --filter-tags '!slow'` |
| **Full suite command** | `scripts/preflight.sh && bats tests/bats/` |
| **Estimated runtime** | ~15 seconds quick / ~90 seconds full (preflight is the long pole) |

---

## Sampling Rate

- **After every task commit:** Run `shellcheck <modified script>` + `bats tests/bats/<suite>.bats` for the script just touched
- **After every plan wave:** Run `bats tests/bats/` (all suites)
- **Before `/gsd-verify-work`:** Full suite must be green — `scripts/preflight.sh` on the dev box must exit `0`
- **Max feedback latency:** 15 seconds (quick) / 90 seconds (full)

*Rationale: this phase ships bash + systemd + config templates, not a compiled app. Feedback signal comes from (1) `shellcheck` on every script edit, (2) bats unit tests for pure-function helpers (`have`, `pass`, `warn`, subnet-overlap math), and (3) running `scripts/preflight.sh` itself as the integration test — it exercises every PRE-xx check against the live box.*

---

## Per-Task Verification Map

> This table is seeded at planning time; task IDs are filled by the planner. Each REQ-ID in the phase maps to at least one automated check OR a manual step documented below. See RESEARCH.md §Validation Architecture for the full probe catalog.

| REQ | Probe | Test Type | Automated Command | Status |
|-----|-------|-----------|-------------------|--------|
| HOST-01 | Ubuntu 24.04 | unit + live | `bats tests/bats/preflight-pre01.bats` / `scripts/preflight.sh` | ⬜ |
| HOST-02 | systemd active | live | `systemctl is-system-running` | ⬜ |
| HOST-03 | Docker Engine + docker group | live | `docker info && id -nG | grep -q docker` | ⬜ |
| HOST-04 | NVIDIA runtime registered | live | `docker info --format '{{.DefaultRuntime}}'` returns `nvidia` | ⬜ |
| HOST-05 | `.wslconfig` + `wsl.conf` templates | static | `test -f config/wslconfig && test -f config/wsl.conf` | ⬜ |
| HOST-06 | hwclock resume unit | live | `systemctl is-enabled hwclock-resume.service` | ⬜ |
| HOST-07 | `.env.example` shipped | static | `test -f .env.example && grep -q GITHUB_OWNER .env.example` | ⬜ |
| TOOLS-01 | `.tool-versions` pins present | static | `test -f .tool-versions && awk '{print $1}' .tool-versions | sort -u | wc -l` ≥ 9 | ⬜ |
| TOOLS-02 | asdf shim precedence | live | `command -v kubectl` resolves under `$HOME/.asdf/shims/` | ⬜ |
| TOOLS-03 | asdf ≥ 0.18 (Go rewrite) | live | `asdf --version` matches `^0\.1[89]\|^[1-9]` | ⬜ |
| PRE-01 | WSL kernel | bats + live | `bats tests/bats/preflight-pre01.bats` | ⬜ |
| PRE-02 | Ubuntu 24.04 distro | bats + live | `bats tests/bats/preflight-pre02.bats` | ⬜ |
| PRE-03 | systemd active | live | covered by HOST-02 probe | ⬜ |
| PRE-04 | resource floor (CPU/RAM) | live | `scripts/preflight.sh` section output | ⬜ |
| PRE-05 | GPU chain (nvidia-smi, driver) | live | `nvidia-smi` exits 0 in a container | ⬜ |
| PRE-06 | Tool pins match | live | `scripts/preflight.sh` section output | ⬜ |
| PRE-07 | Ports 6443–6445 / 8080–8082 free | live | `ss -tln` no match for listed ports | ⬜ |
| PRE-08 | Residual k3d / network state | live | `docker network ls | grep -v k8s-net` clean | ⬜ |
| PRE-09 | `.env` presence + non-empty per key | bats + live | `bats tests/bats/preflight-pre09.bats` | ⬜ |
| PRE-10 | Docker-Desktop-integration detection | live | `scripts/preflight.sh` section output | ⬜ |
| PRE-11 | `systemd-resolved` 127.0.0.53 stub | bats + live | `bats tests/bats/preflight-pre11.bats` | ⬜ |
| PRE-12 | Clock skew > 30s | live | `scripts/preflight.sh` section output | ⬜ |
| PRE-13 | cgroup-v2 purity | bats + live | `bats tests/bats/preflight-pre13.bats` | ⬜ |
| PRE-14 | Mirrored-mode bridge-curl probe | live | two-container curl on `k8s-net` | ⬜ |
| idempotency | Install scripts rerunnable | live | run `install-*.sh` twice; second run logs only `already done, skipping:` | ⬜ |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `tests/bats/` directory created with `test_helper.bash` (sourcing `lib/preflight-lib.sh` once extracted)
- [ ] `bats-core` installed via asdf (pin in `.tool-versions` if adopted) or apt as a dev dep — planner's choice, but must not pollute global PATH
- [ ] `shellcheck` available (Ubuntu 24.04 ships it; `apt-get install -y shellcheck` if missing)
- [ ] Stub suites for PRE-01, PRE-02, PRE-09, PRE-11, PRE-13 (the five pure-function checks worth unit-testing; remaining PRE-xx are live-only and validated by running `scripts/preflight.sh`)
- [ ] Helper function library extracted from `prereqs.sh` into `scripts/lib/preflight-lib.sh` so bats can source it without executing the full script

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| NVIDIA runtime end-to-end | HOST-04 | Requires physical GPU + driver — cannot mock in CI | `docker run --rm --gpus all nvidia/cuda:12.5.1-base-ubuntu24.04 nvidia-smi` exits 0 |
| `hwclock -s` fires on WSL resume | HOST-06 | WSL2 `sleep.target` firing is uncertain (see RESEARCH.md); only observable on real Windows hibernate/resume | `date` before Windows sleep → sleep 15 min → resume → `date` skew < 5s |
| Mirrored-mode hard-fail triggers | D-01 / PRE-14 | Requires switching `.wslconfig` to `networkingMode=mirrored` + `wsl --shutdown` | Set mirrored, rerun `scripts/preflight.sh`, confirm exit 1 with doc pointer |
| Docker Desktop integration detection | PRE-10 | Requires Docker Desktop installation — only testable on a box that has it | Install Docker Desktop with WSL integration enabled, rerun preflight, confirm hard-fail message |
| `.env.example` → `.env` workflow | D-11 / HOST-07 | User-level file handling; tests only assert shape | `cp .env.example .env && edit`, confirm preflight transitions from PRE-09 fail → pass |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references (bats + shellcheck infrastructure)
- [ ] No watch-mode flags (all runs are one-shot)
- [ ] Feedback latency < 15s (quick) / 90s (full)
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
