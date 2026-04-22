---
phase: 1
slug: host-foundation
status: draft
nyquist_compliant: true
wave_0_complete: true
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

*Rationale: this phase ships bash + systemd + config templates, not a compiled app. Feedback signal comes from (1) `shellcheck` on every script edit, (2) bats unit tests for pure-function helpers (`have`, `pass`, `warn`, subnet-overlap math, preflight_check_* functions), and (3) running `scripts/preflight.sh` itself as the integration test — it exercises every PRE-xx check against the live box.*

---

## Per-Task Verification Map

> This table is seeded at planning time; task IDs are filled by the planner. Each REQ-ID in the phase maps to at least one automated check OR a manual step documented below. See RESEARCH.md §Validation Architecture for the full probe catalog.

| REQ | Probe | Test Type | Automated Command | Status |
|-----|-------|-----------|-------------------|--------|
| HOST-01 | test -f config/wslconfig && grep -qE '^networkingMode=NAT' config/wslconfig | static | `grep -qE '^networkingMode=NAT' config/wslconfig` | ⬜ |
| HOST-02 | test -f config/wsl.conf && grep -q 'systemd=true' config/wsl.conf | static | `grep -q 'systemd=true' config/wsl.conf` | ⬜ |
| HOST-03 | Docker Engine + docker group | live | `docker info && id -nG \| grep -q docker` | ⬜ |
| HOST-04 | NVIDIA runtime registered | live | `docker info --format '{{.DefaultRuntime}}'` returns `nvidia` | ⬜ |
| HOST-05 | wslconfig + wsl.conf + docs present | static | `test -f config/wslconfig && test -f config/wsl.conf && test -f docs/wsl-networking.md` | ⬜ |
| HOST-06 | hwclock resume unit enabled | live | `systemctl is-enabled hwclock-resume.service` returns `enabled` | ⬜ |
| HOST-07 | .env.example + GITHUB_* keys present | static | `test -f .env.example && for k in GITHUB_OWNER GITHUB_REPO GITHUB_TOKEN; do grep -q "^${k}=" .env.example; done` | ⬜ |
| TOOLS-01 | `.tool-versions` pins present | static | `test -f .tool-versions && awk '{print $1}' .tool-versions \| sort -u \| wc -l` ≥ 9 | ⬜ |
| TOOLS-02 | install-tools.sh exists and references asdf | static | `test -x scripts/install-tools.sh && grep -q 'asdf' scripts/install-tools.sh` | ⬜ |
| TOOLS-03 | asdf shim precedence | live | `command -v kubectl \| grep -q "$HOME/.asdf/shims"` | ⬜ |
| PRE-01 | WSL kernel | bats + live | `bats tests/bats/preflight-pre01.bats` (calls preflight_check_wsl_kernel()) | ⬜ |
| PRE-02 | Ubuntu 24.04 distro | bats + live | `bats tests/bats/preflight-pre02.bats` (calls preflight_check_ubuntu_24_04()) | ⬜ |
| PRE-03 | mirrored-mode detection (D-02 ip_in_cidr) | live | `scripts/preflight.sh` section output (calls preflight_check_mirrored_mode()) | ⬜ |
| PRE-04 | resource floor (CPU/RAM) | live | `scripts/preflight.sh` section output | ⬜ |
| PRE-05 | Tool pins match | live | `scripts/preflight.sh` section output | ⬜ |
| PRE-06 | Ports 6443–6445 / 8080–8082 free | live | `ss -tln` no match for listed ports | ⬜ |
| PRE-07 | Residual k3d / network state | live | `docker network ls \| grep -v k8s-net` clean | ⬜ |
| PRE-08 | Docker Desktop WSL integration detected → fail | live | `scripts/preflight.sh` section output | ⬜ |
| PRE-09 | `.env` presence + non-empty per key | bats + live | `bats tests/bats/preflight-pre09.bats` (calls preflight_check_env_file()) | ⬜ |
| PRE-10 | kubectl/helm/k3d outside asdf shims → fail | live | `scripts/preflight.sh` section output | ⬜ |
| PRE-11 | `systemd-resolved` 127.0.0.53 stub | bats + live | `bats tests/bats/preflight-pre11.bats` (calls preflight_check_systemd_resolved()) | ⬜ |
| PRE-12 | Clock skew > 30s | live | `scripts/preflight.sh` section output (powershell.exe primary, sudo hwclock fallback) | ⬜ |
| PRE-13 | cgroup-v2 purity | bats + live | `bats tests/bats/preflight-pre13.bats` (calls preflight_check_cgroup_v2()) | ⬜ |
| PRE-14 | Mirrored-mode bridge-curl probe (ephemeral, trap-cleaned) | live | docker run busybox probe on preflight-pre14-net | ⬜ |
| idempotency | Install scripts rerunnable | live | run `install-*.sh` twice; second run logs only `already done, skipping:` | ⬜ |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [x] `tests/bats/` directory created with `test_helper.bash` (sourcing `lib/preflight-lib.sh` and all preflight_check_* functions) — Plan 01 Task 3
- [x] `bats-core` installed via `apt-get install -y bats` (Ubuntu 24.04) — Plan 01 Task 4. Not pinned in `.tool-versions` (no asdf plugin evaluated in RESEARCH.md; apt path chosen)
- [x] `shellcheck` installed via `apt-get install -y shellcheck` (Ubuntu 24.04) — Plan 01 Task 4. Not pinned in `.tool-versions` (author-side lint tool, not a project dev-loop tool)
- [ ] Stub suites for PRE-01, PRE-02, PRE-09, PRE-11, PRE-13 (the five pure-function checks worth unit-testing; remaining PRE-xx are live-only and validated by running `scripts/preflight.sh`) — Plan 07
- [x] Helper function library extracted from `prereqs.sh` into `scripts/lib/preflight-lib.sh` with `ip_in_cidr()` and all `preflight_check_*` callable functions so bats can source it without executing the full script — Plan 01 Task 1

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| NVIDIA runtime end-to-end | HOST-04 | Requires physical GPU + driver — cannot mock in CI | `docker run --rm --gpus all nvidia/cuda:12.5.1-base-ubuntu24.04 nvidia-smi` exits 0 |
| `hwclock -s` fires on WSL resume | HOST-06 | WSL2 `sleep.target` firing is uncertain (see RESEARCH.md); only observable on real Windows hibernate/resume | `date` before Windows sleep → sleep 15 min → resume → `date` skew < 5s |
| Mirrored-mode hard-fail triggers | D-01 / PRE-03 | Requires switching `.wslconfig` to `networkingMode=mirrored` + `wsl --shutdown` | Set mirrored, rerun `scripts/preflight.sh`, confirm exit 1 with doc pointer |
| Docker Desktop integration detection | PRE-08 | Requires Docker Desktop installation — only testable on a box that has it | Install Docker Desktop with WSL integration enabled, rerun preflight, confirm hard-fail message |
| `.env.example` → `.env` workflow | D-11 / HOST-07 | User-level file handling; tests only assert shape | `cp .env.example .env && edit`, confirm preflight transitions from PRE-09 fail → pass |
| PRE-12 clock skew enforcement | PRE-12 | powershell.exe integration required for primary path; sudo hwclock for fallback | Advance WSL system clock by 60s (`sudo date -s '+60 seconds'`), rerun preflight, confirm PRE-12 fail with skew value in message |
| PRE-14 ephemeral cleanup verification | PRE-14 / RD-01 | Requires live Docker daemon | Run `scripts/preflight.sh`; after completion confirm `docker ps -a --filter name=preflight-pre14` returns empty |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references (bats + shellcheck infrastructure)
- [ ] No watch-mode flags (all runs are one-shot)
- [ ] Feedback latency < 15s (quick) / 90s (full)
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
