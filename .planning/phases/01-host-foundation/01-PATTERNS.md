# Phase 1: Host Foundation - Pattern Map

**Mapped:** 2026-04-22
**Files analyzed:** 13 new/modified files
**Analogs found:** 5 / 13 (8 are greenfield config/doc with no code analog in codebase)

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `scripts/preflight.sh` | script / checker | read-only + side-effect-free + exit-code | `prereqs.sh` (repo root) | exact — port + extend |
| `scripts/lib/preflight-lib.sh` | utility library | shared helpers | `prereqs.sh` lines 10-28 | role-match — extract from analog |
| `scripts/install-docker.sh` | script / installer | side-effecting (apt, sudo, systemd) | `prereqs.sh` (guarded-section style) | style-match |
| `scripts/install-nvidia-container-toolkit.sh` | script / installer | side-effecting (apt, sudo, nvidia-ctk) | `prereqs.sh` (guarded-section style) | style-match |
| `scripts/install-tools.sh` | script / installer | side-effecting (asdf, PATH, bashrc) | `prereqs.sh` (guarded-section style) | style-match |
| `config/wslconfig` | config template | static file (user copies to Windows) | none — greenfield | no analog |
| `config/wsl.conf` | config template | static file (user copies to /etc/) | none — greenfield | no analog |
| `config/hwclock-resume.service` | config / systemd unit | static file (installed to /etc/systemd/) | none — greenfield | no analog |
| `docs/wsl-networking.md` | documentation | static prose | none — greenfield | no analog |
| `.tool-versions` | config / version pin | static file (consumed by asdf) | none — greenfield | no analog |
| `.env.example` | config / secrets template | static file (user copies to .env) | none — greenfield | no analog |
| `.gitignore` (narrow slice) | config | static file | none — greenfield | no analog |
| `tests/bats/*.bats` | test suites | bats-core unit tests of helper functions | none — greenfield | no analog |

---

## Pattern Assignments

### `scripts/preflight.sh` (script / checker, read-only exit-code)

**Analog:** `prereqs.sh` (repo root)
**Instruction:** Port `prereqs.sh` directly to `scripts/preflight.sh`. Do NOT rewrite from scratch.
All five named patterns below must be preserved verbatim in the port.

**Shebang + intentional `set -u` (not `-e`)** (`prereqs.sh` lines 1-9):
```bash
#!/usr/bin/env bash
# preflight.sh
# Read-only environment check for the karyon project.
# Run inside your WSL2 Ubuntu instance. Makes no changes. Safe to re-run.
#
# Usage:  bash scripts/preflight.sh
# Exit:   0 if no blockers, 1 if blockers present.

set -u  # intentionally NOT -e: we want to continue through failed checks
```

**ANSI-color block gated on `[[ -t 1 ]]`** (`prereqs.sh` lines 11-17):
```bash
if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_DIM=$'\033[2m'; C_BOLD=$'\033[1m'
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_BLUE=$'\033[34m'
else
  C_RESET=""; C_DIM=""; C_BOLD=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_BLUE=""
fi
```

**Counter initializers + message accumulators** (`prereqs.sh` lines 19-20):
```bash
PASS=0; WARN=0; FAIL=0
WARN_MSGS=(); FAIL_MSGS=()
```

**Named helper functions — preserve exactly** (`prereqs.sh` lines 22-28):
```bash
section() { printf "\n%s%s== %s ==%s\n" "$C_BOLD" "$C_BLUE" "$1" "$C_RESET"; }
pass()    { printf "  %s✓%s %s\n" "$C_GREEN" "$C_RESET" "$1"; PASS=$((PASS+1)); }
warn()    { printf "  %s!%s %s\n" "$C_YELLOW" "$C_RESET" "$1"; WARN=$((WARN+1)); WARN_MSGS+=("$1"); }
fail()    { printf "  %s✗%s %s\n" "$C_RED" "$C_RESET" "$1"; FAIL=$((FAIL+1)); FAIL_MSGS+=("$1"); }
info()    { printf "  %s·%s %s\n" "$C_DIM" "$C_RESET" "$1"; }

have()    { command -v "$1" >/dev/null 2>&1; }
```

**Summary block with counters + exit code logic** (`prereqs.sh` lines 273-297):
```bash
section "Summary"
printf "  %s%d passed%s, %s%d warnings%s, %s%d failed%s\n" \
  "$C_GREEN" "$PASS" "$C_RESET" "$C_YELLOW" "$WARN" "$C_RESET" "$C_RED" "$FAIL" "$C_RESET"

if (( FAIL > 0 )); then
  printf "\n%sBlockers:%s\n" "$C_RED" "$C_RESET"
  for m in "${FAIL_MSGS[@]}"; do printf "  • %s\n" "$m"; done
fi
if (( WARN > 0 )); then
  printf "\n%sWarnings:%s\n" "$C_YELLOW" "$C_RESET"
  for m in "${WARN_MSGS[@]}"; do printf "  • %s\n" "$m"; done
fi

printf "\n"
if (( FAIL == 0 && WARN == 0 )); then
  printf "%sEnvironment looks clean. Ready to start the project.%s\n" "$C_GREEN" "$C_RESET"
  exit 0
elif (( FAIL == 0 )); then
  printf "%sNo blockers — review warnings and proceed.%s\n" "$C_GREEN" "$C_RESET"
  exit 0
else
  printf "%sFix blockers above before continuing.%s\n" "$C_RED" "$C_RESET"
  exit 1
fi
```

**Existing checks to carry forward unchanged** (`prereqs.sh` lines 30-271):
All six existing sections (WSL environment, System resources, Docker, NVIDIA/GPU, Network/ports,
Existing container/k8s state, Tools) port verbatim with one targeted change:

- Docker Desktop detection (lines 108-117): change the final `warn` to `fail` — this is the only
  behavioral change required in the existing sections. See RESEARCH.md §Ref-10 for the exact
  upgraded `fail` message to substitute.

**New check `check_required` / `check_optional` helpers** (`prereqs.sh` lines 247-254):
```bash
check_required() {
  if have "$1"; then pass "$1: $(show_tool_version "$1")"
  else fail "$1 not installed"; fi
}
check_optional() {
  if have "$1"; then pass "$1: $(show_tool_version "$1")"
  else info "$1 not installed (install-tools.sh will handle)"; fi
}
```

**New PRE-xx sections to add after porting** (no analog — use RESEARCH.md patterns):

| Section | Source in RESEARCH.md |
|---------|-----------------------|
| PRE-09 `.env` validation | RESEARCH.md §Code Examples (PRE-09) |
| PRE-10 asdf shim precedence | RESEARCH.md §Pitfall 1 |
| PRE-11 systemd-resolved stub | RESEARCH.md §Ref-6 |
| PRE-12 clock skew > 30s | RESEARCH.md §Architecture Patterns (diagram) |
| PRE-13 cgroup v2 purity | RESEARCH.md §Ref-7 |
| PRE-14 bridge-curl probe | RESEARCH.md §Pitfall 7 |
| PRE-02 mirrored-mode heuristic | RESEARCH.md §Ref-9 (D-02 decision) |

Each new section follows the same `section()` / `pass()` / `warn()` / `fail()` / `info()` call
convention as the existing sections.

---

### `scripts/lib/preflight-lib.sh` (utility library, shared helpers)

**Analog:** `prereqs.sh` lines 10-28 (the helper block)
**Instruction:** Extract the ANSI-color block, counter initializers, and all six helper functions
(`section`, `pass`, `warn`, `fail`, `info`, `have`) verbatim into this library file. Both
`scripts/preflight.sh` and the bats test helper will `source` it.

**Library shebang and source guard:**
```bash
#!/usr/bin/env bash
# scripts/lib/preflight-lib.sh
# Shared output helpers for preflight.sh and bats test suites.
# Source this file; do not execute directly.
[[ "${BASH_SOURCE[0]}" == "$0" ]] && { echo "source this file, don't run it directly" >&2; exit 1; }
```

Then copy the ANSI-color block, counter initializers, and helper functions verbatim
(same code as shown in the `scripts/preflight.sh` pattern above, lines 11-28 of `prereqs.sh`).

---

### `scripts/install-docker.sh` (script / installer, side-effecting)

**Analog:** `prereqs.sh` for structure (shebang, `set -u`, helpers); RESEARCH.md §Ref-4 for
every guarded step.

**Shebang + set stance** — copy from `prereqs.sh` lines 1-9, changing the description comment.

**ANSI-color + helpers** — source `scripts/lib/preflight-lib.sh` rather than duplicating:
```bash
# shellcheck source=lib/preflight-lib.sh
source "$(dirname "$0")/lib/preflight-lib.sh"
```

**Guarded-sections pattern** (D-05 decision — every step checks state before acting):
```bash
# Pattern: each logical step wraps a state check, logs "already done, skipping: X"
# or calls pass "installing: X" and performs the action.
# Source: RESEARCH.md §Ref-4 (Docker) and D-05 (CONTEXT.md)

section "Docker apt repository"
if [[ -f /etc/apt/sources.list.d/docker.sources ]]; then
  info "already done, skipping: docker apt repo"
else
  # ... add repo ...
  pass "installing: docker apt repo"
fi

section "Docker Engine packages"
if dpkg -s docker-ce >/dev/null 2>&1; then
  info "already done, skipping: docker-ce install"
else
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin
  pass "installing: docker-ce and plugins"
fi

section "Docker group membership"
if id -nG "$USER" | tr ' ' '\n' | grep -qx docker; then
  info "already done, skipping: user in docker group"
else
  sudo usermod -aG docker "$USER"
  pass "installing: user '$USER' added to docker group (re-login or 'newgrp docker' required)"
fi
```

**daemon.json jq-merge step** (resolved in RESEARCH.md §Ref-4, §Claude's Discretion #2 and #3):
```bash
section "daemon.json (default-runtime + dns)"
DAEMON_JSON=/etc/docker/daemon.json
DESIRED_DNS='["1.1.1.1","8.8.8.8"]'
DESIRED_RUNTIME="nvidia"

if sudo jq -e '."default-runtime" == "nvidia"' "$DAEMON_JSON" >/dev/null 2>&1 && \
   sudo jq -e '.dns | length > 0' "$DAEMON_JSON" >/dev/null 2>&1; then
  info "already done, skipping: daemon.json default-runtime + dns"
else
  [[ ! -f "$DAEMON_JSON" ]] && echo '{}' | sudo tee "$DAEMON_JSON" > /dev/null
  current=$(sudo cat "$DAEMON_JSON")
  merged=$(echo "$current" | jq \
    --arg dr "$DESIRED_RUNTIME" \
    --argjson dns "$DESIRED_DNS" \
    '. + {"default-runtime": $dr, "dns": $dns}')
  echo "$merged" | sudo tee "$DAEMON_JSON" > /dev/null
  sudo systemctl restart docker
  pass "installing: daemon.json default-runtime=nvidia + dns=[1.1.1.1,8.8.8.8]"
fi
```

**hwclock-resume.service install step** (D-08 decision — lives in this script):
```bash
section "hwclock-resume.service (clock-skew fix)"
UNIT_SRC="$(dirname "$0")/../config/hwclock-resume.service"
UNIT_DEST=/etc/systemd/system/hwclock-resume.service

if systemctl is-enabled hwclock-resume.service >/dev/null 2>&1; then
  info "already done, skipping: hwclock-resume.service"
else
  sudo cp "$UNIT_SRC" "$UNIT_DEST"
  sudo systemctl daemon-reload
  sudo systemctl enable hwclock-resume.service
  pass "installing: hwclock-resume.service (WSL2 clock-skew fix)"
fi
```

---

### `scripts/install-nvidia-container-toolkit.sh` (script / installer, side-effecting)

**Analog:** Same guarded-sections pattern as `install-docker.sh` above.

**Structure:** shebang + `set -u` from `prereqs.sh` line 9, source `lib/preflight-lib.sh`, then
guarded sections following D-05.

**Three guarded sections** (from RESEARCH.md §Ref-3):
1. NVIDIA apt keyring + repo (guard: `[[ -f /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg ]]`)
2. Package install (guard: `dpkg -s nvidia-container-toolkit >/dev/null 2>&1`)
3. `nvidia-ctk runtime configure` (guard: `docker info 2>/dev/null | grep -qi "Runtimes:.*nvidia"`)

After `nvidia-ctk runtime configure`, the `default-runtime` jq-merge is handled by
`install-docker.sh` (not this script). This script ends with `sudo systemctl restart docker`.

---

### `scripts/install-tools.sh` (script / installer, side-effecting)

**Analog:** Same guarded-sections pattern. Sources `lib/preflight-lib.sh`.

**asdf binary install** (from RESEARCH.md §Ref-1):
```bash
section "asdf binary"
ASDF_VERSION="v0.18.1"
if have asdf && asdf --version | grep -qE "^0\.(1[89]|[2-9])"; then
  info "already done, skipping: asdf ${ASDF_VERSION}"
else
  curl -fsSL "https://github.com/asdf-vm/asdf/releases/download/${ASDF_VERSION}/asdf-${ASDF_VERSION}-linux-amd64.tar.gz" \
    | sudo tar -xz -C /usr/local/bin asdf
  pass "installing: asdf ${ASDF_VERSION}"
fi
```

**shell-init.sh creation** (D-06 decision — RESEARCH.md §Ref-1):
```bash
section "~/.karyon/shell-init.sh"
mkdir -p ~/.karyon
INIT_FILE=~/.karyon/shell-init.sh
if [[ -f "$INIT_FILE" ]]; then
  info "already done, skipping: ~/.karyon/shell-init.sh"
else
  cat > "$INIT_FILE" <<'EOF'
# asdf v0.16+ (Go rewrite) — no longer needs source; just PATH export
export PATH="${ASDF_DATA_DIR:-$HOME/.asdf}/shims:$PATH"
EOF
  pass "installing: ~/.karyon/shell-init.sh"
fi

# Idempotent ~/.bashrc hook (D-06)
if grep -qF '~/.karyon/shell-init.sh' ~/.bashrc 2>/dev/null; then
  info "already done, skipping: ~/.bashrc karyon shell-init hook"
else
  echo '[ -f ~/.karyon/shell-init.sh ] && source ~/.karyon/shell-init.sh' >> ~/.bashrc
  pass "installing: ~/.bashrc karyon shell-init hook"
fi
```

**Plugin + version install loop** (RESEARCH.md §Claude's Discretion #4):
```bash
section "asdf plugins"
for plugin in kubectl helm flux2 k3d k9s task jq yq; do
  if asdf plugin list 2>/dev/null | grep -qx "$plugin"; then
    info "already done, skipping: asdf plugin $plugin"
  else
    asdf plugin add "$plugin"
    pass "installing: asdf plugin $plugin"
  fi
done

section "tool versions (from .tool-versions)"
asdf install
pass "tool versions installed (or already present)"
```

---

### `config/wslconfig` (config template, static)

**Analog:** None — greenfield. Use RESEARCH.md §Ref-2 content verbatim.

**Content to copy from RESEARCH.md §Ref-2 (lines 278-288 of RESEARCH.md):**
```ini
# config/wslconfig  — template for %USERPROFILE%\.wslconfig
[wsl2]
memory=52GB
processors=20
networkingMode=NAT
# networkingMode=mirrored  # UNSUPPORTED in v1 — known Docker custom-network breakage
#                          # See docs/wsl-networking.md before uncommenting
swap=8GB
localhostForwarding=true
```

**D-03 requirement:** The `networkingMode=NAT` line must be explicit (not commented out). The
mirrored fallback appears as a commented-out line with a pointer to `docs/wsl-networking.md`.

---

### `config/wsl.conf` (config template, static)

**Analog:** None — greenfield. Use RESEARCH.md §Ref-2 content verbatim.

**Content to copy from RESEARCH.md §Ref-2:**
```ini
# config/wsl.conf  — template for /etc/wsl.conf
[boot]
systemd=true

[network]
generateResolvConf=true
hostname=karyon-dev
```

---

### `config/hwclock-resume.service` (config / systemd unit, static)

**Analog:** None — greenfield. Use RESEARCH.md §Ref-8 content verbatim.

**Content to copy from RESEARCH.md §Ref-8 (lines 555-568 of RESEARCH.md):**
```ini
[Unit]
Description=Sync system clock from hardware clock (WSL2 resume clock-skew fix)
After=suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target

[Service]
Type=oneshot
ExecStart=/sbin/hwclock --hctosys
RemainAfterExit=yes

[Install]
WantedBy=suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target
```

---

### `docs/wsl-networking.md` (documentation, static prose)

**Analog:** None — greenfield.

**Required sections (from CONTEXT.md §Specific Ideas and RESEARCH.md §Pitfall 5):**
1. Mirrored mode — what it is and why it breaks Docker custom networks
2. NAT mode — the v1 mandate (D-01)
3. Detection — how `scripts/preflight.sh` PRE-02 detects mirrored mode
4. Migration procedure — exact 5-step `.wslconfig` delta + `wsl --shutdown` dance:
   1. Edit `%USERPROFILE%\.wslconfig`: set `networkingMode=NAT`
   2. Run `wsl --shutdown` in PowerShell
   3. Wait 8+ seconds
   4. Open WSL terminal
   5. Verify: `ip addr show eth0` should show `172.x.x.x`
5. Belt-and-suspenders: optional Windows Task Scheduler `hwclock -s` on resume (from RESEARCH.md §Ref-8)

---

### `.tool-versions` (config / version pin, static)

**Analog:** None — greenfield. Content is fully specified in RESEARCH.md §Tool Version Pins.

**Exact content to write** (from RESEARCH.md lines 736-746):
```
kubectl 1.36.0
helm 3.20.2
flux2 2.8.6
k3d 5.8.3
k9s 0.50.18
task 3.50.0
jq 1.8.1
yq 4.53.2
asdf 0.18.1
```

**Note for planner:** RESEARCH.md flags a kubectl skew concern — `1.36.0` is 2 minors ahead of
k3s v1.34. Planner should decide whether to use `1.35.x` if that release exists. Either pin is
acceptable; document the choice.

---

### `.env.example` (config / secrets template, static)

**Analog:** None — greenfield.

**D-11 requirement:** Placeholder values with inline comments. Keys alphabetical.
**D-09 requirement:** Ships in Phase 1 (not deferred to Phase 6).

**Minimum content (from D-10 and D-11 in CONTEXT.md):**
```bash
# .env.example — copy to .env and fill in real values
# DO NOT commit .env (see .gitignore)

# GitHub personal access token with 'repo' scope.
# Generate at: https://github.com/settings/tokens/new?scopes=repo
GITHUB_OWNER=your-github-username

# Repository name (without the owner prefix, e.g. "karyon")
GITHUB_REPO=your-repo-name

# PAT with repo scope — used by scripts/preflight.sh (presence check only; not validated against GitHub API)
GITHUB_TOKEN=ghp_REPLACE_WITH_PAT_WITH_repo_SCOPE
```

Keys must stay alphabetical within groups so Phase 3 additions diff cleanly (D-11 rationale).

---

### `.gitignore` (narrow slice, static)

**Analog:** None — greenfield for this slice.

**D-12 requirement:** Add exactly these lines (minimum — broader hygiene deferred to Phase 6):
```
# Secrets — NEVER commit .env with real values
.env
.env.local
.env.*.local
```

If a `.gitignore` already exists at repo root, append these lines idempotently. If absent, create
the file with these lines plus a header comment.

---

### `tests/bats/*.bats` (test suites, bats-core)

**Analog:** None — greenfield. VALIDATION.md §Wave 0 Requirements specifies five stub suites.

**Test helper structure** (each suite sources the lib):
```bash
#!/usr/bin/env bats
# tests/bats/preflight-pre09.bats

load '../test_helper'  # sources scripts/lib/preflight-lib.sh + bats helpers

@test "PRE-09: .env present and GITHUB_OWNER set" {
  # test logic here using sourced helpers
}
```

**`tests/bats/test_helper.bash`** — the shared loader:
```bash
# Adjust path relative to tests/bats/
SCRIPTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)/scripts"
source "${SCRIPTS_DIR}/lib/preflight-lib.sh"
```

**Five stub suites required by VALIDATION.md Wave 0:**
- `tests/bats/preflight-pre01.bats` — WSL2 kernel detection (pure function: uname parsing)
- `tests/bats/preflight-pre02.bats` — Ubuntu 24.04 distro detection (`/etc/os-release` parsing)
- `tests/bats/preflight-pre09.bats` — `.env` presence + non-empty key check
- `tests/bats/preflight-pre11.bats` — `127.0.0.53` grep in resolv.conf
- `tests/bats/preflight-pre13.bats` — cgroup v2 `stat -fc %T` output parsing

These five are the only PRE-xx checks with pure-function logic testable without a live system.
Remaining PRE-xx checks are live-only (validated by running `scripts/preflight.sh` on the dev box).

---

## Shared Patterns

### Script Shebang and `set` Stance
**Source:** `prereqs.sh` line 1 and 9
**Apply to:** All `scripts/*.sh` files
```bash
#!/usr/bin/env bash
set -u  # intentionally NOT -e: continue through failures to collect all errors
```
For install scripts that must abort on unexpected errors, use `set -euo pipefail` instead — the
`set -u` only stance is specific to preflight (which collects all failures before exiting).

### ANSI Color + Helper Functions
**Source:** `prereqs.sh` lines 11-28 (extract to `scripts/lib/preflight-lib.sh`)
**Apply to:** All `scripts/*.sh` files via `source "$(dirname "$0")/lib/preflight-lib.sh"`
All scripts share the same `section` / `pass` / `warn` / `fail` / `info` / `have` vocabulary.
Install scripts use `pass "installing: X"` and `info "already done, skipping: X"` as their
audit log per D-05.

### Guarded-Sections Pattern
**Source:** D-05 (CONTEXT.md locked decision) + RESEARCH.md §Ref-4 examples
**Apply to:** `scripts/install-docker.sh`, `scripts/install-nvidia-container-toolkit.sh`, `scripts/install-tools.sh`
Every logical step:
1. State-check guard (file exists? package installed? service enabled? grep present?)
2. If already done: `info "already done, skipping: <what>"`
3. If not done: perform action, then `pass "installing: <what>"`
This turns the script's stdout into a live audit log, not just a fast no-op.

### `have()` Tool Presence Check
**Source:** `prereqs.sh` line 28
**Apply to:** All scripts
```bash
have() { command -v "$1" >/dev/null 2>&1; }
```
Never use `which` or `type` — `command -v` is POSIX-portable and works inside bats.

### Blocker Messages with Remediation
**Source:** CONTEXT.md §Specific Ideas
**Apply to:** All `fail()` calls in `scripts/preflight.sh`
Every `fail` message must tell the user *exactly what to run* to fix the blocker, e.g.:
- `.env missing → cp .env.example .env && edit it`
- `docker not reachable → run scripts/install-docker.sh; newgrp docker or re-login`
- `mirrored mode → see docs/wsl-networking.md`

---

## No Analog Found

Files with no close match in the codebase (planner uses RESEARCH.md patterns directly):

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `config/wslconfig` | config template | static | No config templates exist yet |
| `config/wsl.conf` | config template | static | No config templates exist yet |
| `config/hwclock-resume.service` | systemd unit | static | No systemd units exist yet |
| `docs/wsl-networking.md` | documentation | static | No docs/ directory yet |
| `.tool-versions` | version pin | static | No .tool-versions exists yet |
| `.env.example` | secrets template | static | No .env* files exist yet |
| `.gitignore` (slice) | config | static | No .gitignore exists at repo root yet |
| `tests/bats/*.bats` | test suites | bats-core | No test infrastructure exists yet |

---

## Metadata

**Analog search scope:** `/home/rich/code/gsd/karyon/` (repo root + all subdirectories)
**Analog files read:** 1 (`prereqs.sh` — 297 lines, fully read in one pass)
**Supporting files read:** `01-CONTEXT.md`, `01-RESEARCH.md`, `01-VALIDATION.md`, `starter.md`
**Pattern extraction date:** 2026-04-22
