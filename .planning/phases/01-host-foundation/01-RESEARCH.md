# Phase 1: Host Foundation - Research

**Researched:** 2026-04-22
**Domain:** WSL2 + Docker Engine + NVIDIA Container Toolkit + asdf + preflight bash scripting
**Confidence:** HIGH (stack, patterns, command syntax) / MEDIUM (systemd/WSL2 sleep behavior) / LOW (nvidia-ctk idempotency details)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Preflight detects mirrored-mode networking and hard-fails (exit 1) with a pointer to `docs/wsl-networking.md`. NAT is the v1 mandate.
- **D-02:** Mirrored detection uses the IP-subnet heuristic — if any non-`lo` interface's IPv4 subnet overlaps the Windows host subnet, classify as mirrored.
- **D-03:** `config/wslconfig` pins `networkingMode=NAT` explicitly with a commented-out mirrored line pointing to `docs/wsl-networking.md`.
- **D-04:** PRE-14 bridge-curl probe runs even after mirrored detection passes.
- **D-05:** All install scripts use the guarded-sections pattern — every logical step logs `already done, skipping: X` or `installing: X`.
- **D-06:** asdf PATH enforced via `~/.karyon/shell-init.sh`; single `[ -f ~/.karyon/shell-init.sh ] && source ~/.karyon/shell-init.sh` appended to `~/.bashrc` (guarded by grep).
- **D-07:** bash only for shell-init.
- **D-08:** hwclock-resume systemd unit lives at `config/hwclock-resume.service`; installed by `install-docker.sh`.
- **D-09:** `.env.example` ships in Phase 1.
- **D-10:** Preflight validates `.env` at presence + non-empty per key only (no token format, no API calls).
- **D-11:** `.env.example` carries placeholder values with inline comments.
- **D-12:** Phase 1 updates `.gitignore` with narrow slice: `.env`, `.env.local`, `.env.*.local`.

### Claude's Discretion

- Preflight strictness / output format
- `daemon.json` patching strategy
- Exact `dns` array content
- asdf plugin sourcing per tool
- PRE-11 (systemd-resolved probe) and PRE-13 (cgroup-v2) implementation detail

### Deferred Ideas (OUT OF SCOPE)

- Preflight `--json` / `--quiet` output modes
- Preflight token-format sanity checks
- zsh / fish shell support for asdf PATH init
- GitHub API reachability probe from preflight
- gitleaks pre-commit hook (Phase 6)
- Full REPO-01..07 hygiene (Phase 6)
- ADR drafts (Phase 6)
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| HOST-01 | `config/wslconfig` template with NAT-mode + mirrored fallback | WSL2 `.wslconfig` schema verified via Microsoft docs |
| HOST-02 | `config/wsl.conf` template with `systemd=true` | `[boot] systemd=true` syntax verified via Microsoft docs |
| HOST-03 | `install-docker.sh` idempotent, native Docker Engine, adds user to docker group | Docker apt repo procedure verified; guarded-sections pattern documented |
| HOST-04 | `/etc/docker/daemon.json` with `default-runtime: nvidia` and explicit `dns` | daemon.json schema verified; jq-merge strategy documented |
| HOST-05 | `install-nvidia-container-toolkit.sh` idempotent, runs `nvidia-ctk runtime configure` | NVIDIA install procedure verified via official docs |
| HOST-06 | systemd unit runs `hwclock -s` on resume | Unit file pattern researched; WSL2 sleep.target caveats documented |
| HOST-07 | `docs/wsl-networking.md` with exact `.wslconfig` delta | mirrored → NAT procedure documented |
| TOOLS-01 | `.tool-versions` pinning all tools | Versions verified via GitHub API 2026-04-22 |
| TOOLS-02 | `install-tools.sh` installs asdf plugins and pinned versions idempotently | asdf plugin names verified via asdf-plugins registry |
| TOOLS-03 | asdf shim directory precedes `/usr/bin` and `/usr/local/bin` | asdf v0.18 PATH syntax verified via official docs |
| PRE-01 | `scripts/preflight.sh` exists, read-only, exits 0/1 | prereqs.sh baseline documented |
| PRE-02 | Verifies WSL2 kernel, Ubuntu 24.04, active systemd | Already implemented in prereqs.sh |
| PRE-03 | Resource floor (cores / RAM / disk) | Already implemented in prereqs.sh |
| PRE-04 | Full GPU chain check | Already implemented in prereqs.sh (partial); PRE-04 adds nvidia-ctk + runtime check |
| PRE-05 | Tools installed, versions match `.tool-versions` | asdf version comparison approach documented |
| PRE-06 | Ports 6443-6445, 8080-8082 free | Already implemented in prereqs.sh |
| PRE-07 | k3d containers + k8s-net network warns | Already implemented in prereqs.sh |
| PRE-08 | Docker Desktop WSL integration detected → fail | Already implemented in prereqs.sh (warn); must upgrade to fail |
| PRE-09 | `.env` exists, `GITHUB_*` keys non-empty | New check; implementation pattern documented |
| PRE-10 | kubectl/helm/k3d outside asdf shims → fail | New check; `command -v` + shim path comparison documented |
| PRE-11 | systemd-resolved 127.0.0.53 stub detected → fail | New check; grep /etc/resolv.conf approach documented |
| PRE-12 | Clock skew > 30s → fail | New check; date comparison approach documented |
| PRE-13 | cgroup v2 purity check | New check; `stat -fc %T /sys/fs/cgroup` approach documented; Ubuntu 24.04 caveat |
| PRE-14 | Bridge-curl probe → fail if probe fails | New check; docker run two-container curl approach documented |
</phase_requirements>

---

## Summary

Phase 1 establishes the host-layer foundation on Windows 11 + WSL2 Ubuntu 24.04. The primary deliverable is `scripts/preflight.sh`, ported from the existing `prereqs.sh` and extended to cover PRE-09 through PRE-14. Three idempotent install scripts (`install-docker.sh`, `install-nvidia-container-toolkit.sh`, `install-tools.sh`) handle the one-time setup that preflight validates. Config templates, a clock-skew systemd unit, `.tool-versions` pins, `.env.example`, and `.gitignore` round out the phase.

The research confirms all 10 external-reference items are resolvable with current documentation. Key findings: asdf v0.18 (Go rewrite) uses a pure PATH export instead of shell sourcing; WSL2 sleep.target does NOT reliably fire in systemd-under-WSL2, so the hwclock unit needs `After=suspend.target` with the acknowledgment that it may not trigger on bare WSL resume (Windows-side Task Scheduler is the reliable fallback, but the systemd unit covers the in-distro case); `nvidia-ctk runtime configure` writes a `runtimes` key to `daemon.json` but does NOT add `default-runtime`, requiring a separate jq-merge step; Helm 4.x shipped November 2025 (REQUIREMENTS.md mandates the 3.x line — use Helm 3.20.2); all tool version pins are verified against GitHub releases as of 2026-04-22.

**Primary recommendation:** Port `prereqs.sh` as the scaffolding, add new sections for PRE-09..14 in sequence, and write the three install scripts as separate idempotent files following the guarded-sections pattern. The planner should sequence the `install-docker.sh` task to also install the hwclock unit (D-08), and ensure `install-tools.sh` creates `~/.karyon/shell-init.sh` (D-06) before any tool-version checks.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| WSL2 config templates | Host filesystem (WSL) | Windows-side copy instructions | Templates live in repo; user copies to `%USERPROFILE%\.wslconfig` and `/etc/wsl.conf` |
| Docker Engine install | WSL Ubuntu shell | systemd service | apt-based install writes to distro; Docker daemon runs as systemd service |
| NVIDIA container toolkit | WSL Ubuntu shell | Docker daemon.json | nvidia-ctk writes to daemon.json; toolkit runs as host-layer shim |
| asdf + tool shims | WSL Ubuntu shell (`~/.asdf`) | `~/.bashrc` / `~/.karyon/shell-init.sh` | Tools install into user home; PATH wired via shell init |
| preflight gate | WSL bash script | Exit code → Taskfile | Scripts produce exit code; Taskfile surfaces result |
| clock-skew unit | systemd (WSL) | `/etc/systemd/system/` | Unit installed to system path; started by systemd inside WSL |
| `.env` / secrets | WSL repo root (gitignored) | `.env.example` (committed) | Live values never committed; template is the committed contract |

---

## Standard Stack

### Core

| Library / Tool | Version (verified 2026-04-22) | Purpose | Why Standard |
|----------------|-------------------------------|---------|--------------|
| Docker Engine (`docker-ce`) | Latest from apt (e.g., 5:29.x) | Container runtime | Native install in WSL; no Desktop bloat |
| `nvidia-container-toolkit` | 1.19.0-1 (pinned in install script) | GPU pass-through to containers | Only NVIDIA-official method; `nvidia-ctk` CLI manages daemon.json |
| asdf | 0.18.1 [VERIFIED: github.com/asdf-vm/asdf] | Tool version management | Go rewrite; single binary; shim PATH model |
| kubectl | 1.36.0 [VERIFIED: dl.k8s.io/release/stable.txt] | Kubernetes CLI | Latest stable; within +2 minor of k3s v1.34 |
| helm | 3.20.2 [VERIFIED: github.com/helm/helm] | Kubernetes package manager | 3.x line mandated by REQUIREMENTS.md; Helm 4 released Nov 2025 but ecosystem still consolidating |
| flux | 2.8.6 [VERIFIED: github.com/fluxcd/flux2] | GitOps operator CLI | Latest stable flux2 CLI |
| k3d | 5.8.3 [VERIFIED: github.com/k3d-io/k3d] | k3s-in-Docker cluster manager | REQUIREMENTS.md: "v5.8.3 or newer, never v5.8.0" |
| k9s | 0.50.18 [VERIFIED: github.com/derailed/k9s] | Kubernetes TUI | Developer quality-of-life |
| task (go-task) | 3.50.0 [VERIFIED: github.com/go-task/task] | Task runner (Taskfile.yml) | Project orchestration surface |
| jq | 1.8.1 [VERIFIED: github.com/jqlang/jq] | JSON CLI processor | Used in daemon.json merge; install scripts |
| yq (mikefarah) | 4.53.2 [VERIFIED: github.com/mikefarah/yq] | YAML CLI processor | Used in config template generation |

### Supporting

| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| `docker-ce-cli` | same as docker-ce | Docker CLI | Always installed alongside docker-ce |
| `containerd.io` | latest via apt | Container runtime | Docker dependency |
| `docker-buildx-plugin` | latest via apt | Multi-platform builds | Docker dependency |
| `docker-compose-plugin` | latest via apt | Compose support | Docker dependency |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| asdf v0.18 (Go binary) | mise (v1 alternative) | mise is faster but asdf is the locked choice per REQUIREMENTS.md |
| helm 3.20.x | helm 4.1.x | REQUIREMENTS.md explicitly mandates 3.x; Helm 4 is breaking-change territory |
| docker-ce apt repo | Snap docker | Snap docker has rootless issues with systemd + nvidia runtime; apt is correct path |

**Installation:**

```bash
# Docker Engine
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# NVIDIA Container Toolkit
export NVIDIA_CONTAINER_TOOLKIT_VERSION=1.19.0-1
sudo apt-get install nvidia-container-toolkit=${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
  nvidia-container-toolkit-base=${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
  libnvidia-container-tools=${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
  libnvidia-container1=${NVIDIA_CONTAINER_TOOLKIT_VERSION}

# asdf (via git bootstrap or binary)
# asdf v0.18 is distributed as a Go binary; install via GitHub release tarball
# then add to PATH per shell-init below

# All other tools installed via asdf plugin add / asdf install
```

---

## Architecture Patterns

### System Architecture Diagram

```
User runs `scripts/preflight.sh`
         │
         ▼
[Section: WSL env] ──► checks: WSL2 kernel, Ubuntu 24.04, systemd active, mirrored-mode heuristic (D-02)
         │                  └── mirrored detected? → FAIL + docs/wsl-networking.md pointer (D-01)
         ▼
[Section: Resources] ──► cores / RAM / disk thresholds (fail/warn/pass)
         │
         ▼
[Section: Docker] ──► daemon reachable, user in docker group, Docker Desktop integration absent (PRE-08 → FAIL)
         │             daemon.json has default-runtime: nvidia + explicit dns array (PRE-04 partial)
         ▼
[Section: NVIDIA/GPU] ──► libcuda.so stub, nvidia-smi, driver ≥570.x, nvidia-ctk, docker nvidia runtime (PRE-04)
         │
         ▼
[Section: .env] ──► .env file exists, GITHUB_OWNER/REPO/TOKEN non-empty (PRE-09 → FAIL)
         │
         ▼
[Section: Tools/asdf] ──► each tool in .tool-versions: installed, version matches pin, resolves via asdf shim (PRE-05, PRE-10)
         │
         ▼
[Section: DNS/Network] ──► /etc/resolv.conf has no 127.0.0.53 nameserver (PRE-11 → FAIL)
         │
         ▼
[Section: Clock] ──► |$(date +%s) - $(hwclock --get --utc | ...)|  ≤ 30s (PRE-12 → FAIL)
         │
         ▼
[Section: cgroup] ──► stat -fc %T /sys/fs/cgroup = cgroup2fs (PRE-13)
         │
         ▼
[Section: Ports] ──► 6443-6445, 8080-8082 not listening (PRE-06)
         │
         ▼
[Section: Residue] ──► k3d containers, k8s-net network absent/warn (PRE-07)
         │
         ▼
[Section: Bridge probe] ──► docker run two containers on k8s-net, container-A curls container-B by DNS name (PRE-14 → FAIL)
         │
         ▼
[Summary] ──► N passed, N warnings, N failed → exit 0 / exit 1
```

### Recommended Project Structure

```
karyon/
├── scripts/
│   ├── preflight.sh                 # read-only, exit 0/1
│   ├── install-docker.sh            # installs docker-ce, hwclock unit, daemon.json
│   ├── install-nvidia-container-toolkit.sh  # installs toolkit, runs nvidia-ctk configure
│   └── install-tools.sh             # installs asdf, plugins, pinned versions
├── config/
│   ├── wslconfig                    # template for %USERPROFILE%\.wslconfig
│   ├── wsl.conf                     # template for /etc/wsl.conf
│   └── hwclock-resume.service       # systemd unit template
├── docs/
│   └── wsl-networking.md            # mirrored → NAT fallback procedure
├── .tool-versions                   # asdf version pins
├── .env.example                     # committed; all keys with placeholder values
└── .gitignore                       # includes .env, .env.local, .env.*.local
```

---

## External Reference Items (Detailed Findings)

### Ref-1: asdf v0.18+ PATH Migration

**VERIFIED via asdf-vm.com/guide/getting-started.html and asdf-vm.com/guide/upgrading-to-v0-16.html**

asdf v0.16+ (Go rewrite — the line REQUIREMENTS.md mandates ≥0.18) is a compiled binary, not a shell script collection. The old `. "$HOME/.asdf/asdf.sh"` sourcing pattern is GONE and MUST be removed.

**Shim directory:** `${ASDF_DATA_DIR:-$HOME/.asdf}/shims`
Default without any config: `~/.asdf/shims`

**New shell init snippet (bash, for `~/.karyon/shell-init.sh`):**
```bash
# asdf v0.16+ (Go rewrite) — no longer needs source; just PATH export
export PATH="${ASDF_DATA_DIR:-$HOME/.asdf}/shims:$PATH"
```

**Install asdf binary itself:**
```bash
# Download latest release binary
ASDF_VERSION="v0.18.1"
curl -fsSL "https://github.com/asdf-vm/asdf/releases/download/${ASDF_VERSION}/asdf-${ASDF_VERSION}-linux-amd64.tar.gz" \
  | sudo tar -xz -C /usr/local/bin asdf
# or install to user-local: mkdir -p ~/.local/bin && tar -xz -C ~/.local/bin asdf
```

**Guarded-sections check for shell-init.sh creation:**
```bash
if grep -qF '~/.karyon/shell-init.sh' ~/.bashrc 2>/dev/null; then
  info "already done, skipping: ~/.bashrc karyon shell-init hook"
else
  echo '[ -f ~/.karyon/shell-init.sh ] && source ~/.karyon/shell-init.sh' >> ~/.bashrc
  pass "installing: ~/.bashrc karyon shell-init hook"
fi
```

**Pitfall:** The old `asdf.sh` source line breaks silently if left in when upgrading to v0.16+. The binary is not at `~/.asdf/bin/asdf` anymore (that was the shell-script version). The binary lives wherever you put it (e.g., `/usr/local/bin/asdf` or `~/.local/bin/asdf`).

### Ref-2: WSL2 `.wslconfig` and `wsl.conf` Schemas

**VERIFIED via learn.microsoft.com/en-us/windows/wsl/wsl-config (fetched 2026-04-22)**

**`.wslconfig` — global, lives at `%USERPROFILE%\.wslconfig` (Windows-side)**

Valid `networkingMode` values: `none`, `nat`, `mirrored`, `virtioproxy`, `bridged` (deprecated since WSL 2.4.5).
Requires Windows 11 22H2 or higher for `mirrored` / `dnsTunneling` / `firewall`.

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

**`wsl.conf` — per-distro, lives at `/etc/wsl.conf` (inside WSL)**

```ini
# config/wsl.conf  — template for /etc/wsl.conf
[boot]
systemd=true

[network]
generateResolvConf=true
hostname=karyon-dev
```

`systemd=true` requires WSL version 0.67.6+. If absent, preflight must fail for systemd check (PRE-02).

**After editing either file:** run `wsl --shutdown` from PowerShell (the 8-second rule applies — all distros must fully stop).

### Ref-3: NVIDIA Container Toolkit — Install + `nvidia-ctk` Behavior

**VERIFIED via docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html**

**Full install sequence (Ubuntu 24.04):**
```bash
# Add NVIDIA repo keyring
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb \[signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg\] https://#g' \
  | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt-get update

NVIDIA_CONTAINER_TOOLKIT_VERSION=1.19.0-1
sudo apt-get install -y \
  nvidia-container-toolkit=${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
  nvidia-container-toolkit-base=${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
  libnvidia-container-tools=${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
  libnvidia-container1=${NVIDIA_CONTAINER_TOOLKIT_VERSION}
```

**Runtime configure:**
```bash
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

**What `nvidia-ctk runtime configure --runtime=docker` writes to `/etc/docker/daemon.json`:**
```json
{
  "runtimes": {
    "nvidia": {
      "args": [],
      "path": "nvidia-container-runtime"
    }
  }
}
```

**CRITICAL: `nvidia-ctk` does NOT set `default-runtime`** — it only adds to the `runtimes` map. The `default-runtime: nvidia` key must be added separately. [ASSUMED: nvidia-ctk does not destroy existing keys when the file already exists, but this is not confirmed in official docs — verified only that it writes a `runtimes` key]

**Idempotency:** Running `nvidia-ctk runtime configure` twice appears safe in practice (it rewrites the runtimes section), but the install script should guard with a presence check before calling it. [ASSUMED: idempotent based on community reports, not official documentation]

### Ref-4: Docker Engine Install on Ubuntu 24.04

**VERIFIED via docs.docker.com/engine/install/ubuntu/ (fetched 2026-04-22)**

```bash
# 1. Add Docker GPG key
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# 2. Add apt repository (modern .sources format, Ubuntu 24.04 = noble)
sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
sudo apt-get update

# 3. Install packages
sudo apt-get install -y \
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 4. Add user to docker group
sudo usermod -aG docker "$USER"
# NOTE: group membership requires re-login to take effect; newgrp docker works in current session
```

**Guarded idempotency check for repo:**
```bash
if [[ -f /etc/apt/sources.list.d/docker.sources ]]; then
  info "already done, skipping: docker apt repo"
else
  # add repo...
fi
```

**Guarded idempotency check for install:**
```bash
if dpkg -s docker-ce >/dev/null 2>&1; then
  info "already done, skipping: docker-ce install"
else
  sudo apt-get install -y docker-ce ...
fi
```

**Guarded idempotency check for group membership:**
```bash
if id -nG "$USER" | tr ' ' '\n' | grep -qx docker; then
  info "already done, skipping: user in docker group"
else
  sudo usermod -aG docker "$USER"
  pass "installing: user '$USER' added to docker group (re-login required)"
fi
```

**daemon.json patching strategy (D-05 / Claude's Discretion):**

Use `jq` to merge keys rather than overwriting the file. This preserves any existing keys (e.g., the `runtimes.nvidia` key added by `nvidia-ctk`):

```bash
# Merge default-runtime + dns into existing daemon.json (jq-merge strategy)
DAEMON_JSON=/etc/docker/daemon.json
DESIRED_DNS='["1.1.1.1","8.8.8.8"]'
DESIRED_RUNTIME="nvidia"

if [[ ! -f "$DAEMON_JSON" ]]; then
  echo '{}' | sudo tee "$DAEMON_JSON" > /dev/null
fi

# Read current, merge, write back
current=$(sudo cat "$DAEMON_JSON")
merged=$(echo "$current" | jq \
  --arg dr "$DESIRED_RUNTIME" \
  --argjson dns "$DESIRED_DNS" \
  '. + {"default-runtime": $dr, "dns": $dns}')
echo "$merged" | sudo tee "$DAEMON_JSON" > /dev/null
sudo systemctl restart docker
```

**Guarded check for idempotency:**
```bash
if sudo jq -e '."default-runtime" == "nvidia"' "$DAEMON_JSON" >/dev/null 2>&1 && \
   sudo jq -e '.dns | length > 0' "$DAEMON_JSON" >/dev/null 2>&1; then
  info "already done, skipping: daemon.json default-runtime + dns"
else
  # apply jq merge...
fi
```

**DNS array content decision:** Use `["1.1.1.1","8.8.8.8"]` (Cloudflare + Google). These are standard public resolvers that work reliably in NAT mode without relying on systemd-resolved's `127.0.0.53` stub. [ASSUMED: no project-specific DNS requirement; public resolvers are appropriate]

### Ref-5: k3d GPU Contract (Docker Half — Phase 1 Scope)

**VERIFIED via k3d.io/v5.4.2/usage/advanced/cuda/ and github.com/k3d-io/k3d/issues/1108**

The 3-part k3d GPU contract (Phase 2 implements parts 2 and 3; Phase 1 must verify part 1):

| Part | Owner | What | Phase |
|------|-------|------|-------|
| 1 | Docker daemon.json | `"default-runtime": "nvidia"` at top level AND `runtimes.nvidia` registered | **Phase 1** |
| 2 | Custom k3s image | `config.toml.tmpl` with `default_runtime_name = "nvidia"` under containerd CRI section | Phase 2 |
| 3 | Ubuntu-based image | k3s image must use Ubuntu base (not Alpine) because NVIDIA runtime not supported on Alpine | Phase 2 |

**Preflight PRE-04 verifies the Phase 1 half:**
```bash
# Check nvidia runtime registered
if docker info 2>/dev/null | grep -qi "Runtimes:.*nvidia"; then
  pass "docker nvidia runtime registered"
else
  fail "docker nvidia runtime NOT registered — run install-nvidia-container-toolkit.sh"
fi

# Check default-runtime = nvidia
if docker info 2>/dev/null | grep -qi "Default Runtime: nvidia"; then
  pass "docker default-runtime is nvidia"
else
  fail "docker default-runtime is not nvidia — fix /etc/docker/daemon.json"
fi
```

**Full `config.toml.tmpl` content (Phase 2 reference, do not implement in Phase 1):**
```toml
[plugins."io.containerd.grpc.v1.cri".containerd]
  default_runtime_name = "nvidia"
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia]
    runtime_type = "io.containerd.runc.v2"
    [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia.options]
      BinaryName = "nvidia-container-runtime"
```

### Ref-6: systemd-resolved 127.0.0.53 Probe (PRE-11)

**MEDIUM confidence — verified against systemd behavior; WSL2-specific interaction confirmed via community reports**

**Why it matters:** Docker containers inherit the host's `/etc/resolv.conf` nameserver. If systemd-resolved is active and the resolv.conf nameserver is `127.0.0.53`, containers get a loopback address that doesn't route correctly from inside the container network namespace. `/etc/docker/daemon.json` with explicit `dns` overrides this for containers, but preflight must detect the underlying issue on the host.

**Detection approach — PRE-11:**
```bash
# Check /etc/resolv.conf for 127.0.0.53 stub
if grep -qE '^nameserver[[:space:]]+127\.0\.0\.53' /etc/resolv.conf 2>/dev/null; then
  fail "systemd-resolved 127.0.0.53 stub detected in /etc/resolv.conf — fix: ensure
/etc/docker/daemon.json contains explicit dns array (install-docker.sh handles this)"
else
  pass "resolv.conf nameserver is not 127.0.0.53 stub"
fi
```

**Note:** This check is only a FAIL if `daemon.json` does NOT already have a `dns` array override. The install script (`install-docker.sh`) sets `dns` in `daemon.json`, which fixes the container-side problem. Preflight should fail when the stub is present AND daemon.json lacks the fix, because until docker restarts the containers will be broken. Alternatively (simpler): always fail if 127.0.0.53 is in resolv.conf and tell user to run install-docker.sh. The install script then sets the dns key and restarts docker.

**Alternative probe:** Check symlink target of `/etc/resolv.conf`:
```bash
readlink /etc/resolv.conf
# Returns /run/systemd/resolve/stub-resolv.conf when systemd-resolved stub is active
# Returns /run/systemd/resolve/resolv.conf when systemd-resolved passes through real DNS
# Returns nothing (real file) when not managed by systemd-resolved
```

Both approaches work; the `grep` approach is more robust across WSL configurations.

### Ref-7: cgroup v2 Purity Check (PRE-13)

**VERIFIED via Kubernetes cgroup docs and community sources**

**Command:**
```bash
stat -fc %T /sys/fs/cgroup
```
Returns `cgroup2fs` for pure cgroup v2, `tmpfs` for cgroup v1 or hybrid.

**Ubuntu 24.04 reality:** Ubuntu 24.04 ships with cgroup v2 as primary, but systemd historically mounted v1 controllers in parallel. On WSL2 with Ubuntu 24.04 and a current WSL2 kernel (5.15+), the unified cgroup v2 hierarchy is active. [ASSUMED: WSL2's Microsoft-maintained kernel defaults to pure cgroup v2 on current versions; this is not explicitly confirmed in WSL2 docs but is consistent with community reports]

**PRE-13 implementation:**
```bash
cg_type="$(stat -fc %T /sys/fs/cgroup 2>/dev/null)"
if [[ "$cg_type" == "cgroup2fs" ]]; then
  pass "cgroup v2 pure (cgroup2fs)"
elif [[ "$cg_type" == "tmpfs" ]]; then
  fail "cgroup v1 or hybrid detected — k3d + GPU workloads require cgroup v2 pure"
else
  warn "unable to determine cgroup type (got: ${cg_type:-empty})"
fi
```

**Caveat:** k3s/k3d 1.34 requires cgroup v2 for full functionality. If this check fails on an otherwise correct Ubuntu 24.04 / WSL2 setup, the user needs to check for `[wsl2] kernelCommandLine` overrides in `.wslconfig`.

### Ref-8: hwclock Resume Unit (HOST-06 / D-08)

**MEDIUM confidence — verified pattern; WSL2 sleep.target behavior is uncertain**

**The problem:** WSL2's VM clock drifts after Windows hibernates/sleeps because the Linux kernel clock is not updated when the hypervisor resumes. `hwclock -s` syncs the Linux system clock from the hardware clock (RTC), correcting the drift.

**WSL2 + systemd sleep target reality:** On WSL2, `sleep.target` and `suspend.target` do NOT reliably fire because WSL2 uses Hyper-V save/restore (not ACPI suspend). The Windows kernel does not signal the WSL2 VM via the ACPI sleep flow. Therefore:
- A pure `After=suspend.target` / `WantedBy=suspend.target` unit will NOT reliably trigger on WSL resume.
- The unit still has value: it fires when a user explicitly runs `systemctl suspend` inside WSL (rare), and provides a documented hook for the future.

**The reliable Windows-side alternative (belt-and-suspenders approach documented in `docs/wsl-networking.md`):**
A Windows Task Scheduler task triggered by `Kernel-Power` Event ID 107 (resume from sleep) runs `wsl -u root sh -c "hwclock -s"`. This is more reliable but requires Windows-side setup outside Phase 1's WSL-only scope.

**Recommended unit file (`config/hwclock-resume.service`):**
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

**Install procedure (idempotent, inside `install-docker.sh`):**
```bash
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

**Note for `docs/wsl-networking.md`:** Document that the systemd unit covers the Linux-side hook but Windows-side Task Scheduler is more reliable. Provide PowerShell snippet for Task Scheduler setup as an optional "belt-and-suspenders" step.

### Ref-9: Mirrored-Mode IP-Subnet Heuristic (D-02)

**MEDIUM confidence — heuristic approach; exact Windows subnet ranges vary**

**The problem:** From inside WSL2, there is no direct API to query the networkingMode from `.wslconfig`. The heuristic relies on the fact that in mirrored mode, WSL2 interfaces share the Windows host's network addresses directly, so WSL interfaces will have IP addresses in the same subnet as the Windows host NICs.

**In NAT mode:** WSL2 gets a distinct `172.x.x.x` or `192.168.x.x` address on a dedicated virtual switch subnet, typically with a gateway at `172.x.x.1`.

**In mirrored mode:** WSL2 interfaces directly mirror the Windows host's physical NICs, so they appear in the same subnet (e.g., `192.168.1.x/24` if the Windows host is on `192.168.1.0/24`).

**Detection implementation (PRE-02 + D-01):**
```bash
# Get the default route gateway — in NAT mode this is the WSL virtual switch IP
gateway="$(ip -4 route show default 2>/dev/null | awk '/via/ {print $3}' | head -1)"

# Get all non-loopback interface CIDRs
iface_cidrs="$(ip -4 -o addr show 2>/dev/null | awk '$2!="lo"{print $4}' | tr '\n' ' ')"

# Heuristic: if the gateway is in a 172.x.x.x block it's almost certainly NAT (Hyper-V default range)
# If the gateway is in 192.168.x.x or 10.x.x.x it may be mirrored OR it may be a custom home network
# A stronger signal: check if WSL interfaces have the SAME subnet prefix as the gateway
# In NAT mode: gateway = 172.x.x.1, iface = 172.x.x.2/20 → same subnet, but 172.x range = NAT
# In mirrored mode: gateway = 192.168.1.1, iface = 192.168.1.x/24 → same subnet

# Simple approach: check if gateway is NOT in 172.16.0.0/12 (Hyper-V NAT range)
if [[ -n "$gateway" ]]; then
  IFS='.' read -r oct1 oct2 _ _ <<< "$gateway"
  if (( oct1 == 172 && oct2 >= 16 && oct2 <= 31 )); then
    pass "networking mode appears to be NAT (gateway ${gateway} in Hyper-V range)"
  else
    fail "networking mode may be mirrored (gateway ${gateway} not in Hyper-V 172.16-31.x.x range)
      If intentional, see docs/wsl-networking.md for NAT migration procedure.
      If on an unusual home network (192.168.x.x host), this may be a false positive."
  fi
fi
```

**Known false-positive surface:** Home/corporate networks with `192.168.x.x` addressing where the user has customized their Hyper-V switch. The error message must tell the user to confirm with `cat /proc/net/dev` and check their `.wslconfig`. The mirrored detection is belt-and-suspenders with PRE-14 (bridge-curl probe).

**Additional signal (belt-and-suspenders):** Check for `/proc/sys/net/ipv4/conf/eth0/accept_local` being 1 (set by WSL mirrored mode). [ASSUMED: this sysctl is set by WSL mirrored mode; unconfirmed in official docs]

### Ref-10: Docker Desktop WSL Integration Detection (PRE-08)

**HIGH confidence — filesystem markers are reliable heuristics**

**Current state in prereqs.sh:** PRE-08 is already implemented as a `warn` (not `fail`). Per CONTEXT.md, it must be upgraded to `fail`.

**Detection heuristics (already in prereqs.sh — carry forward):**
```bash
docker_desktop=0
# Marker 1: Docker Desktop mounts bind-mount directories in /mnt/wsl/
if [[ -d /mnt/wsl/docker-desktop ]] || [[ -d /mnt/wsl/docker-desktop-data ]]; then
  docker_desktop=1
fi
# Marker 2: Mount table contains docker-desktop entries
if mount 2>/dev/null | grep -qi "docker-desktop"; then
  docker_desktop=1
fi
```

**Upgrade from warn to fail:**
```bash
if (( docker_desktop == 1 )); then
  fail "Docker Desktop WSL integration is active on this distro.
      This project requires Docker Engine installed natively (not via Desktop integration).
      Fix: Docker Desktop → Settings → Resources → WSL Integration → disable for this distro.
      Then run: install-docker.sh"
fi
```

**Additional signal:** Check if `/var/run/docker.sock` is a symlink pointing outside `/run/`:
```bash
sock_target=$(readlink /var/run/docker.sock 2>/dev/null || echo "")
if [[ "$sock_target" == *"docker-desktop"* ]] || [[ "$sock_target" == *"/mnt/wsl"* ]]; then
  docker_desktop=1
fi
```

---

## Claude's Discretion — Resolved Answers

### 1. Preflight Strictness and Output Format

**Decision:** Keep the current permissive model from `prereqs.sh` (warnings non-fatal) plus **hard-fail on PRE-08 through PRE-14**. No `--flags` in v1.

- PRE-08 (Docker Desktop integration): upgrade from `warn` to `fail`
- PRE-09..14 (new checks): all `fail` — these are blockers
- PRE-07 (k3d residue, k8s-net exists): keep as `warn`
- Resource floor: fail below 8 cores / 16GB / 30GB; warn below target floor

### 2. daemon.json Patching Strategy

**Decision:** `jq`-merge when file exists; create from scratch when absent. Never overwrite. The merge preserves the `runtimes.nvidia` key written by `nvidia-ctk` and adds `default-runtime` + `dns` alongside it. See Ref-4 for implementation. [CITED: pattern recommended by NVIDIA docker issue #1575; jq merge approach is standard practice]

### 3. DNS Array Content

**Decision:** `["1.1.1.1","8.8.8.8"]` — Cloudflare (primary) + Google (fallback). These are public, reliable, work in NAT mode, and do not depend on any host-local resolver. [ASSUMED: no project-specific DNS requirement]

### 4. asdf Plugin Sources

**VERIFIED via github.com/asdf-vm/asdf-plugins registry:**

| Tool | asdf plugin name | Repository |
|------|-----------------|------------|
| kubectl | `kubectl` | github.com/asdf-community/asdf-kubectl |
| helm | `helm` | github.com/Antiarchitect/asdf-helm |
| flux | `flux2` | github.com/tablexi/asdf-flux2 |
| k3d | `k3d` | github.com/spencergilbert/asdf-k3d |
| k9s | `k9s` | github.com/looztra/asdf-k9s |
| task | `task` | github.com/particledecay/asdf-task |
| jq | `jq` | github.com/lsanwick/asdf-jq |
| yq | `yq` | github.com/sudermanjr/asdf-yq |

All are community plugins (not first-party asdf plugins, which only cover Elixir/Erlang/Node/Ruby). All are in the official asdf shortname registry and are installable via `asdf plugin add <name>`.

**Note on `yq`:** The `asdf plugin add yq` shortname resolves to `sudermanjr/asdf-yq`, which installs mikefarah/yq (Go yq, `v4.x`). Confirm with `yq --version` that it shows `yq (https://github.com/mikefarah/yq) version v4.x.x` after install.

**Install sequence in `install-tools.sh`:**
```bash
for plugin in kubectl helm flux2 k3d k9s task jq yq; do
  if asdf plugin list 2>/dev/null | grep -qx "$plugin"; then
    info "already done, skipping: asdf plugin $plugin"
  else
    asdf plugin add "$plugin"
    pass "installing: asdf plugin $plugin"
  fi
done

# Install pinned versions from .tool-versions
asdf install
# or for each tool explicitly:
# asdf install kubectl 1.36.0
# asdf install helm 3.20.2
# etc.
```

### 5. PRE-11 Implementation

See Ref-6 above. Use `grep` on `/etc/resolv.conf` for `127.0.0.53`.

### 6. PRE-13 Implementation

See Ref-7 above. Use `stat -fc %T /sys/fs/cgroup`.

---

## Tool Version Pins (`.tool-versions` content)

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

**Notes:**
- `kubectl 1.36.0`: 2 minor versions ahead of k3s v1.34. Kubernetes skew policy allows kubectl to be up to 1 version ahead of the server; 2 ahead may cause issues. Consider pinning `1.35.x` if compatibility problems arise. [ASSUMED: k3s v1.34 = Kubernetes v1.34; kubectl skew tolerance is ±1 minor per official policy] — use `1.35.0` as safer choice if it exists.
- `helm 3.20.2`: REQUIREMENTS.md mandates "3.x line". Helm 4 released November 2025 but ecosystem still consolidating; 3.x is the correct choice per spec.
- `flux2 2.8.6`: The asdf plugin name is `flux2`, not `flux`.
- `k3d 5.8.3`: REQUIREMENTS.md explicitly prohibits v5.8.0 ("v5.8.3 or newer, never v5.8.0").
- `jq 1.8.1`: Tag is `jq-1.8.1`; asdf plugin version string may be `1.8.1` (strip the prefix).
- `yq 4.53.2`: Confirms mikefarah yq v4 line.
- `asdf 0.18.1`: REQUIREMENTS.md says "≥0.18"; 0.18.1 is latest as of research date.

**Kubectl skew check:** [VERIFIED: dl.k8s.io/release/stable.txt returns v1.36.0 as of 2026-04-22]. k3s v1.34.6 maps to Kubernetes server v1.34.6. Kubectl v1.36.0 is 2 minors ahead. Per the Kubernetes version skew policy, kubectl may be at most 1 minor version ahead of the server for full compatibility. Recommend pinning kubectl to `1.35.x`. As of research date, checking latest v1.35.x:

[ASSUMED: kubectl v1.35.x exists and is the correct pin for k3s v1.34; research used stable.txt which returns v1.36.0 — planner should verify a v1.35.x release exists before using v1.36.0]

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON merge for daemon.json | Custom Python/bash JSON parser | `jq . + {...}` | jq handles quoting, escaping, nested keys correctly |
| Tool version management | Custom download scripts per tool | `asdf install` | Handles shims, PATH, version switching automatically |
| GPU runtime detection | Parse `docker info` text manually | `docker info --format '{{.DefaultRuntime}}'` | Format flag gives machine-readable output |
| Clock skew calculation | Parsing `/proc/driver/rtc` manually | `hwclock --get` + `date +%s` delta | hwclock abstracts RTC access correctly |
| resolv.conf stub detection | DNS socket probe | `grep` on `/etc/resolv.conf` | Simple, reliable, no network dependency |

**Key insight:** All the "clever" checks in preflight should be one-liners using standard POSIX/Linux tools. Anything requiring more than 5 lines for a single check is probably hand-rolling something that a standard tool does better.

---

## Common Pitfalls

### Pitfall 1: asdf PATH Not Preceding System Binaries

**What goes wrong:** User has `kubectl` installed via snap or `apt` at `/usr/bin/kubectl`. The asdf shim at `~/.asdf/shims/kubectl` shadows it only if `~/.asdf/shims` is FIRST in PATH. If `~/.bashrc` appends rather than prepends, the system binary wins silently.

**Why it happens:** Many guides say `export PATH="$PATH:~/.asdf/shims"` (append). The correct form is `export PATH="${ASDF_DATA_DIR:-$HOME/.asdf}/shims:$PATH"` (prepend).

**How to avoid:** `install-tools.sh` writes the prepend form to `~/.karyon/shell-init.sh`. PRE-10 detects this by comparing `command -v kubectl` output against `~/.asdf/shims/kubectl`.

**Warning signs:** `command -v kubectl` returns `/usr/bin/kubectl` instead of `$HOME/.asdf/shims/kubectl`.

### Pitfall 2: `nvidia-ctk runtime configure` Does Not Set `default-runtime`

**What goes wrong:** After running `nvidia-ctk runtime configure --runtime=docker`, developers assume `default-runtime: nvidia` is set. It is NOT. Only the `runtimes.nvidia` map entry is added. Forgetting the `default-runtime` jq-merge step means k3d's `--gpus all` flag works (it explicitly requests the nvidia runtime) but any container not specifying `--runtime=nvidia` gets `runc`.

**Why it happens:** NVIDIA docs say "configure the runtime" without distinguishing `runtimes` (registry) from `default-runtime` (default selection).

**How to avoid:** `install-docker.sh` performs the jq-merge for `default-runtime` after running `nvidia-ctk`. PRE-04 checks `docker info | grep "Default Runtime"` for `nvidia`.

**Warning signs:** `docker info | grep Runtime` shows `nvidia` in the list but `Default Runtime: runc`.

### Pitfall 3: Docker Group Membership Not Active in Current Session

**What goes wrong:** `install-docker.sh` adds the user to the `docker` group but the current shell session still uses the old group list. `docker ps` returns "permission denied" even after the script exits 0.

**Why it happens:** Group membership is cached in the process table at login time. `usermod -aG docker $USER` changes `/etc/group` but not the running session.

**How to avoid:** Install script should print: "IMPORTANT: run 'newgrp docker' or log out and back in to activate group membership." PRE-02/PRE-03 preflight checks that the daemon is reachable (which implicitly tests group membership).

**Warning signs:** `docker ps` fails with permission denied immediately after install without logout.

### Pitfall 4: asdf v0.18 Binary Install Path Confusion

**What goes wrong:** Some guides still document `~/.asdf/bin/asdf` as the binary location (the shell-script-era path). In v0.18 (Go binary), this path may not exist. The binary should be in `/usr/local/bin/asdf` or `~/.local/bin/asdf`.

**Why it happens:** Many blog posts and tools check for `~/.asdf/bin/asdf` to detect asdf installation.

**How to avoid:** Detect asdf by `command -v asdf` only. Install the binary to `/usr/local/bin/asdf` from the GitHub release tarball. The guarded check should be: `if have asdf && asdf --version | grep -q "^0\.(1[6-9])"`.

### Pitfall 5: WSL2 `wsl --shutdown` Required After `.wslconfig` Changes

**What goes wrong:** User edits `.wslconfig` on the Windows side, opens a new WSL terminal, and the old config is still active. Configuration does not apply until the WSL2 VM fully stops and restarts.

**Why it happens:** WSL keeps the Hyper-V VM running for up to 8 seconds after the last distro shell closes.

**How to avoid:** `docs/wsl-networking.md` must include the `wsl --shutdown` step explicitly. The exact NAT migration procedure is:
1. Edit `%USERPROFILE%\.wslconfig` to set `networkingMode=NAT`
2. Run `wsl --shutdown` in PowerShell
3. Wait 8+ seconds
4. Open WSL terminal
5. Verify with `ip addr show` — should see `172.x.x.x` on `eth0`

### Pitfall 6: `prereqs.sh` Sections PRE-08 Must Change from warn to fail

**What goes wrong:** The existing `prereqs.sh` uses `warn` for Docker Desktop integration (line 117). If ported as-is, PRE-08 stays non-fatal. Per requirements, Docker Desktop integration is a hard blocker.

**How to avoid:** In the port step, grep for `warn "Docker Desktop"` and replace with `fail`.

### Pitfall 7: Bridge-Curl Probe (PRE-14) Creates and Removes Docker Containers

**What goes wrong:** PRE-14 requires two running containers on `k8s-net` for the probe. If the network `k8s-net` doesn't exist yet (e.g., first run before Phase 2), the probe must either create it temporarily or skip gracefully.

**How to avoid:** PRE-14 should create `k8s-net` if absent (for probe only), run the test, then remove the probe containers. It should NOT remove `k8s-net` if it created it (leave it for Phase 2 to manage). Implementation:

```bash
# PRE-14: bridge-curl probe
section "Bridge networking probe (PRE-14)"
if ! have docker || ! docker info >/dev/null 2>&1; then
  warn "docker not reachable — skipping bridge probe"
else
  # Ensure k8s-net exists (create if absent, note if created)
  net_created=0
  if ! docker network ls --format '{{.Name}}' | grep -qx "k8s-net"; then
    docker network create k8s-net >/dev/null 2>&1
    net_created=1
  fi
  # Run probe: container A serves a file, container B curls it by Docker DNS name
  probe_pass=0
  A_ID=$(docker run -d --rm --network k8s-net --name preflight-probe-a \
    busybox sh -c 'echo ok > /tmp/h && httpd -f -p 8080 -h /tmp' 2>/dev/null)
  if [[ -n "$A_ID" ]]; then
    result=$(docker run --rm --network k8s-net busybox \
      wget -qO- http://preflight-probe-a:8080/h 2>/dev/null || echo "FAIL")
    docker rm -f "$A_ID" >/dev/null 2>&1
    if [[ "$result" == "ok" ]]; then
      probe_pass=1
    fi
  fi
  (( net_created == 1 )) && docker network rm k8s-net >/dev/null 2>&1
  if (( probe_pass == 1 )); then
    pass "bridge-curl probe: container DNS resolution on k8s-net works"
  else
    fail "bridge-curl probe FAILED — Docker custom network DNS is broken.
      In mirrored mode this is a known Docker limitation (moby/moby#48201).
      Fix: set networkingMode=NAT in %USERPROFILE%\\.wslconfig, then run 'wsl --shutdown'."
  fi
fi
```

---

## Code Examples

### PRE-09: .env Validation

```bash
# Source: D-10 (CONTEXT.md locked decision)
section ".env secrets presence (PRE-09)"
ENV_FILE="${REPO_ROOT}/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  fail ".env not found — run: cp .env.example .env && edit it"
else
  pass ".env file exists"
  for key in GITHUB_OWNER GITHUB_REPO GITHUB_TOKEN; do
    val="$(grep -E "^${key}=" "$ENV_FILE" 2>/dev/null | cut -d= -f2-)"
    if [[ -z "$val" ]]; then
      fail "${key} is missing or empty in .env"
    else
      pass "${key} is set (value hidden)"
    fi
  done
fi
```

### PRE-10: asdf Shim Precedence

```bash
# Source: D-06 (CONTEXT.md), TOOLS-03 requirement
section "Tool shim precedence (PRE-10)"
SHIM_DIR="${ASDF_DATA_DIR:-$HOME/.asdf}/shims"
for tool in kubectl helm k3d; do
  if have "$tool"; then
    tool_path="$(command -v "$tool")"
    if [[ "$tool_path" == "$SHIM_DIR"* ]]; then
      pass "$tool resolves via asdf shim ($tool_path)"
    else
      fail "$tool resolves to $tool_path (outside asdf shims at $SHIM_DIR)
        Fix: ensure $SHIM_DIR precedes /usr/bin in PATH (source ~/.karyon/shell-init.sh)"
    fi
  else
    fail "$tool not found — run install-tools.sh"
  fi
done
```

### PRE-12: Clock Skew Check

```bash
# Source: PRE-12 requirement (>30s delta = fail)
section "Clock skew check (PRE-12)"
sys_epoch="$(date +%s 2>/dev/null)"
hw_epoch="$(sudo hwclock --get --utc 2>/dev/null | awk '{print $1, $2}' | date -f - +%s 2>/dev/null)"
if [[ -z "$sys_epoch" || -z "$hw_epoch" ]]; then
  warn "could not determine clock skew (hwclock not accessible)"
else
  skew=$(( sys_epoch - hw_epoch ))
  skew_abs=${skew#-}  # absolute value via string manipulation
  if (( skew_abs > 30 )); then
    fail "clock skew ${skew_abs}s exceeds 30s threshold.
      Fix: sudo hwclock -s  (or run the hwclock-resume systemd unit)"
  else
    pass "clock skew ${skew_abs}s (within 30s threshold)"
  fi
fi
```

### `.env.example` Content

```bash
# .env.example — copy to .env and fill in real values before running preflight
# NEVER commit .env to git (it is gitignored)

# GitHub identity for Flux bootstrap
GITHUB_OWNER=your-github-username
# GITHUB_REPO should match the repository name (not the full URL)
GITHUB_REPO=karyon
# Personal Access Token with 'repo' scope (classic PAT or fine-grained with repo write)
# Generate at: https://github.com/settings/tokens/new?scopes=repo
GITHUB_TOKEN=ghp_REPLACE_WITH_PAT_WITH_repo_SCOPE
```

### `.gitignore` Narrow Slice (Phase 1)

```gitignore
# Secrets (Phase 1 — narrow slice required for PRE-09)
.env
.env.local
.env.*.local
```

### Guarded-Sections Pattern Template

```bash
# Standard pattern for all install steps (D-05)
install_step_name() {
  local description="$1"
  local check_cmd="$2"    # command that returns 0 if already done
  local install_cmd="$3"  # command to run if not done

  if eval "$check_cmd" >/dev/null 2>&1; then
    info "already done, skipping: ${description}"
  else
    info "installing: ${description}"
    eval "$install_cmd"
    pass "installed: ${description}"
  fi
}
```

---

## Validation Architecture

Nyquist validation is enabled per `config.json` (`nyquist_validation: true`).

### Test Framework

| Property | Value |
|----------|-------|
| Framework | bash (shellcheck + functional integration tests) |
| Config file | none — tests are bash scripts |
| Quick run command | `bash scripts/preflight.sh` (on a correctly configured host) |
| Full suite command | `bash scripts/preflight.sh && shellcheck scripts/*.sh` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| PRE-01 | preflight.sh exits 0 on clean box, exits 1 on blocker | integration | `bash scripts/preflight.sh; echo $?` | Wave 0 |
| PRE-02 | WSL2 + Ubuntu 24.04 + systemd detected | smoke (run inside WSL) | `bash scripts/preflight.sh 2>&1 | grep -E "(WSL2|Ubuntu|systemd)"` | Wave 0 |
| PRE-03 | Resource floor enforced | smoke | `bash scripts/preflight.sh 2>&1 | grep "Memory\|CPU\|Free"` | Wave 0 |
| PRE-04 | GPU chain verified | integration | `bash scripts/preflight.sh 2>&1 | grep "nvidia"` | Wave 0 |
| PRE-05 | Tool versions match .tool-versions | integration | `bash scripts/preflight.sh 2>&1 | grep "tool"` | Wave 0 |
| PRE-08 | Docker Desktop integration fails | unit-style | mock `/mnt/wsl/docker-desktop` dir, run preflight section | Wave 0 |
| PRE-09 | .env presence validated | unit-style | remove .env, `bash scripts/preflight.sh 2>&1 | grep "FAIL\|env"` | Wave 0 |
| PRE-10 | asdf shim precedence enforced | integration | verify `command -v kubectl` returns shim path | Wave 0 |
| PRE-11 | systemd-resolved stub detected | unit-style | inject `nameserver 127.0.0.53` into test resolv.conf | Wave 0 |
| PRE-12 | Clock skew > 30s fails | unit-style | mock hwclock output | Wave 0 |
| PRE-13 | cgroup v2 pure | smoke | `stat -fc %T /sys/fs/cgroup` | Wave 0 |
| PRE-14 | Bridge-curl probe | integration | requires docker daemon running | Wave 0 |
| HOST-03 | install-docker.sh idempotent | integration | run twice, verify exit 0 both times, no error output | Wave 0 |
| HOST-04 | daemon.json has correct keys | unit | `jq '."default-runtime" == "nvidia"' /etc/docker/daemon.json` | Wave 0 |
| HOST-05 | install-nvidia-container-toolkit.sh idempotent | integration | run twice, verify exit 0 | Wave 0 |
| TOOLS-01 | .tool-versions pins all 9 tools | lint | grep each tool name in .tool-versions | Wave 0 |
| TOOLS-02 | install-tools.sh idempotent | integration | run twice | Wave 0 |
| TOOLS-03 | shim dir precedes /usr/bin | integration | `echo $PATH \| tr : \\n \| head -5` contains `.asdf/shims` first | Wave 0 |

**Integration test note:** Most of these tests require a real WSL2+Docker+GPU box and cannot run in CI without the target hardware. The "test" for this phase is primarily `scripts/preflight.sh` itself exiting 0 on a correctly-configured box. Wave 0 gap tests below focus on what CAN be tested without hardware.

### Sampling Rate

- **Per task commit:** `shellcheck scripts/preflight.sh scripts/install-*.sh`
- **Per wave merge:** `shellcheck scripts/*.sh` + `bash scripts/preflight.sh` on dev box
- **Phase gate:** Full `bash scripts/preflight.sh` exits 0 on target dev box before `/gsd-verify-work`

### Wave 0 Gaps

- [ ] `tests/test-preflight-sections.sh` — unit tests for individual check sections using mock inputs (covers PRE-08, PRE-09, PRE-11, PRE-12 without real hardware)
- [ ] `tests/test-idempotency.sh` — runs each install script twice and verifies no errors on second run (covers HOST-03, HOST-05, TOOLS-02)
- [ ] `tests/test-tool-versions.sh` — verifies .tool-versions contains all required tool pins
- [ ] Shellcheck configured via `.shellcheckrc` (optional but recommended for CI)

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| WSL2 Ubuntu 24.04 | All Phase 1 | Assumed (target machine) | 24.04 | None — required |
| Windows 11 22H2+ | networkingMode=NAT in .wslconfig | Assumed | — | Older Windows lacks mirrored/NAT toggle; NAT is default anyway |
| NVIDIA GPU (RTX 5090) | PRE-04, HOST-05 | Present (per PROJECT.md) | driver ≥570.x | Skip GPU checks with clear fail message if no GPU |
| systemd inside WSL | HOST-06, PRE-02 | Present when `[boot] systemd=true` | — | Fail PRE-02 if systemd not active |
| jq | daemon.json merge | Not guaranteed pre-install | — | Install via `apt-get install jq` in install-docker.sh |
| curl | Repo key downloads | Present in Ubuntu 24.04 minimal | — | `apt-get install curl` as first step |

**Missing dependencies with no fallback:**
- WSL2 + Ubuntu 24.04 (the entire phase targets this platform)
- NVIDIA GPU + drivers (GPU checks will warn/fail without them; non-GPU setup is not a supported path for this lab)

**Missing dependencies with fallback:**
- `jq`: install at start of `install-docker.sh` before using it for daemon.json merge
- `curl`: install via apt if not present (pre-step in all install scripts)

---

## Security Domain

`security_enforcement` is not explicitly set to false in `config.json` — treat as enabled.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | No user auth in preflight/install scripts |
| V3 Session Management | No | No sessions |
| V4 Access Control | Partial | Scripts use `sudo` for root operations; user must be in sudoers |
| V5 Input Validation | Yes | `.env` key validation (presence + non-empty); no format validation by design (D-10) |
| V6 Cryptography | No | No crypto operations |
| V7 Error Handling | Yes | Scripts use `set -u`, collect all failures, never leak secrets in error messages |

### Known Threat Patterns

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| `GITHUB_TOKEN` echoed in log output | Information Disclosure | PRE-09 logs "value hidden"; scripts never `echo $GITHUB_TOKEN` |
| `.env` committed to git | Information Disclosure | `.gitignore` narrow slice (D-12); `.env.example` is the committed artifact |
| Privilege escalation via install scripts | Elevation of Privilege | Scripts require `sudo`; never run as root by default; user confirms intentionally |
| jq injection via daemon.json values | Tampering | Use `--arg` / `--argjson` jq flags (not string interpolation) to prevent injection |

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `source ~/.asdf/asdf.sh` | `export PATH="${ASDF_DATA_DIR:-$HOME/.asdf}/shims:$PATH"` | asdf v0.16.0 (Go rewrite, ~2024) | Shell init must be rewritten; old sourcing breaks silently |
| `nvidia-docker2` package | `nvidia-container-toolkit` | ~2022; universally adopted by 2024 | nvidia-docker2 is deprecated; toolkit is the only supported path |
| Helm v3 (pre-v4) | Helm v3.20.x (still 3.x line) | Helm 4 released November 2025 | REQUIREMENTS.md mandates 3.x; v4 brings Server-Side Apply and WASM plugins but 3.x stays supported |
| `bridged` networkingMode | NAT (default) or mirrored | bridged deprecated in WSL 2.4.5 | Do not use `bridged` in wslconfig template |

**Deprecated/outdated:**
- `nvidia-docker2` package: replaced by `nvidia-container-toolkit`; do not install
- `asdf.sh` source: removed in v0.16+; use PATH export only
- `.wslconfig` `networkingMode=bridged`: deprecated since WSL 2.4.5; use `nat` or `mirrored`
- Helm v3 `helm init` (pre-v3 pattern): Helm v3+ has no Tiller; `helm init` doesn't exist

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | DNS array `["1.1.1.1","8.8.8.8"]` is appropriate (no project-specific DNS) | Ref-4 | Containers can't resolve names; fix by updating daemon.json |
| A2 | nvidia-ctk does not destroy existing daemon.json keys (only merges runtimes) | Ref-3 | If it overwrites, jq-merge step for default-runtime + dns must run AFTER nvidia-ctk |
| A3 | nvidia-ctk runtime configure is idempotent (safe to run twice) | Ref-3 | If not idempotent, guarded check must be added before calling it |
| A4 | WSL2 Ubuntu 24.04 with current Microsoft kernel uses pure cgroup v2 (cgroup2fs) | Ref-7 | PRE-13 may false-fail on some kernel versions; degrade to warn |
| A5 | kubectl v1.36.0 is compatible with k3s v1.34.6 (2 minor versions ahead) | Tool Versions | May need to pin to v1.35.x; verify before committing .tool-versions |
| A6 | sleep.target does not fire reliably in WSL2 systemd on Windows hibernate | Ref-8 | If it does fire, the unit is even better than expected; no downside |
| A7 | asdf plugin `yq` (shortname) installs mikefarah/yq (not kislyuk/yq) | Ref-1 | Wrong yq installed; verify with `yq --version` after install |
| A8 | `/proc/sys/net/ipv4/conf/eth0/accept_local=1` is a reliable mirrored-mode signal | Ref-9 | Extra signal only; not used in primary heuristic; low risk |

---

## Open Questions

1. **kubectl version pin**
   - What we know: k3s v1.34.6, kubectl v1.36.0 is latest, official skew policy is ±1 minor
   - What's unclear: Whether v1.35.x is a released stable tag; dl.k8s.io/release/stable.txt returned v1.36.0
   - Recommendation: Planner should `curl -fsSL https://dl.k8s.io/release/stable-1.35.txt` to get latest v1.35.x patch and use that in `.tool-versions`

2. **nvidia-ctk idempotency guarantee**
   - What we know: Running it twice is safe in community practice; official docs don't commit to idempotency
   - What's unclear: Whether it appends, merges, or overwrites the `runtimes` key on repeat runs
   - Recommendation: Add a `dpkg -s nvidia-container-toolkit` presence check and a `jq -e '.runtimes.nvidia'` daemon.json check before calling nvidia-ctk; only call if runtime not already registered

3. **k3d v5.8.3 asdf plugin support**
   - What we know: plugin exists at github.com/spencergilbert/asdf-k3d
   - What's unclear: Whether k3d v5.8.3 is available in the plugin's release list
   - Recommendation: In install-tools.sh, verify with `asdf list all k3d` before pinning; if 5.8.3 is missing, use `asdf plugin add k3d https://github.com/spencergilbert/asdf-k3d` and verify

---

## Sources

### Primary (HIGH confidence)

- [asdf v0.16+ upgrade guide](https://asdf-vm.com/guide/upgrading-to-v0-16.html) — PATH export syntax, removal of asdf.sh source
- [asdf getting started](https://asdf-vm.com/guide/getting-started.html) — shim directory path, ASDF_DATA_DIR
- [Microsoft WSL wsl-config docs](https://learn.microsoft.com/en-us/windows/wsl/wsl-config) — complete .wslconfig [wsl2] schema, wsl.conf [boot] systemd=true syntax, networkingMode valid values
- [NVIDIA Container Toolkit install guide](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) — Ubuntu 24.04 apt install sequence, nvidia-ctk runtime configure command
- [Docker Engine install Ubuntu](https://docs.docker.com/engine/install/ubuntu/) — full apt repository setup, package names for Ubuntu 24.04 (noble)
- [k3d GPU usage guide](https://k3d.io/v5.4.2/usage/advanced/cuda/) — config.toml.tmpl content, 3-part GPU contract
- [asdf-plugins registry](https://github.com/asdf-vm/asdf-plugins/blob/master/README.md) — shortname → repo mapping for all tools
- GitHub API releases (verified 2026-04-22): kubectl v1.36.0, helm v3.20.2 / v4.1.4, flux v2.8.6, k3d v5.8.3, k9s v0.50.18, task v3.50.0, jq jq-1.8.1, yq v4.53.2, asdf v0.18.1

### Secondary (MEDIUM confidence)

- [k3d GitHub issue #1108](https://github.com/k3d-io/k3d/issues/1108) — community-confirmed config.toml.tmpl pattern for GPU
- [WSL clock skew discussion (Microsoft)](https://github.com/microsoft/WSL/issues/5324) — confirms hwclock -s as the fix; sleep.target behavior in WSL2
- [Kubernetes cgroup v2 docs](https://kubernetes.io/docs/concepts/architecture/cgroups/) — `stat -fc %T /sys/fs/cgroup` = cgroup2fs is the canonical check
- [NVIDIA/nvidia-docker issue #1575](https://github.com/NVIDIA/nvidia-docker/issues/1575) — jq-merge as standard daemon.json patching pattern

### Tertiary (LOW confidence)

- Community blog posts on mirrored-mode detection heuristics — single sources, not officially documented
- asdf k3d plugin version availability — needs live `asdf list all k3d` verification at install time

---

## Metadata

**Confidence breakdown:**
- Standard stack (versions): HIGH — all versions verified via GitHub API on research date
- asdf v0.18 PATH syntax: HIGH — verified via official asdf docs
- WSL2 config schemas: HIGH — verified via official Microsoft docs
- Docker install procedure: HIGH — verified via official Docker docs
- NVIDIA install procedure: HIGH — verified via official NVIDIA docs
- nvidia-ctk idempotency: LOW — community reports only; not in official docs
- hwclock systemd unit (WSL2 sleep.target): MEDIUM — unit file pattern is correct; whether it fires on WSL resume is uncertain
- Mirrored-mode heuristic: MEDIUM — well-known pattern, false-positive risk on unusual networks
- cgroup v2 on Ubuntu 24.04/WSL2: MEDIUM — standard check; WSL2-specific behavior assumed

**Research date:** 2026-04-22
**Valid until:** 2026-05-22 (30 days — most components are stable; nginx-ctk version may update)
