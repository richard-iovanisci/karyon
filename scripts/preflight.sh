#!/usr/bin/env bash
# scripts/preflight.sh
# Read-only environment check for the karyon project.
# Run inside your WSL2 Ubuntu instance. Makes no changes to persistent host state.
# (PRE-14 creates ephemeral Docker resources that are trap-cleaned before exit.)
#
# Usage:  bash scripts/preflight.sh
# Exit:   0 if no blockers, 1 if blockers present.

set -u  # intentionally NOT -e: we want to continue through failed checks

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/preflight-lib.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/preflight-lib.sh"

# ---------- 1. WSL environment (PRE-01/02/03) ----------
section "WSL environment (PRE-01/02/03)"

# PRE-01: WSL2 kernel detection — delegates to library function (callable from bats)
preflight_check_wsl_kernel

# PRE-02: Ubuntu 24.04 — delegates to library function (callable from bats)
preflight_check_ubuntu_24_04

# PRE-03: Mirrored-mode detection (D-01/D-02)
# Uses ip_in_cidr() to test whether Windows host IP is inside any WSL interface CIDR.
# Algorithm: enumerate non-lo WSL CIDRs, determine Windows host IP via gateway/resolv.conf,
# fail if any WSL CIDR contains the Windows host IP (subnet overlap = mirrored indicator).
# False-positive risk documented in docs/wsl-networking.md and in preflight-lib.sh.
preflight_check_mirrored_mode

if [[ -d /run/systemd/system ]]; then
  pass "systemd is active"
  state="$(systemctl is-system-running 2>/dev/null || true)"
  info "systemctl state: ${state:-unknown}"
else
  fail "systemd not active — add [boot] systemd=true to /etc/wsl.conf, then 'wsl --shutdown' from PowerShell"
fi

# Networking mode signal (best-effort — can't read .wslconfig from inside WSL)
ip4s="$(ip -4 -o addr show 2>/dev/null | awk '$2!="lo"{print $2"="$4}' | tr '\n' ' ')"
info "Interface IPs: ${ip4s:-none}"

# ---------- 2. System resources ----------
section "System resources"

mem_gb="$(awk '/MemTotal/ {printf "%.1f", $2/1024/1024}' /proc/meminfo)"
cpu_count="$(nproc)"
info "Memory visible to WSL: ${mem_gb} GB"
info "CPU cores visible to WSL: ${cpu_count}"

if awk "BEGIN{exit !($mem_gb >= 40)}"; then
  pass "Memory >= 40GB (have ${mem_gb}GB; project plan pins 52GB via .wslconfig)"
elif awk "BEGIN{exit !($mem_gb >= 16)}"; then
  warn "Memory ${mem_gb}GB — project plan allocates 52GB; update .wslconfig on Windows"
else
  fail "Memory ${mem_gb}GB is too low for the 3-cluster topology"
fi

if (( cpu_count >= 16 )); then
  pass "CPU cores >= 16 (have ${cpu_count}; project plan pins 20)"
elif (( cpu_count >= 8 )); then
  warn "CPU cores ${cpu_count} — project plan uses 20 via .wslconfig"
else
  fail "CPU cores ${cpu_count} is low for 3-cluster topology"
fi

avail_gb="$(df -BG --output=avail "$HOME" 2>/dev/null | tail -1 | tr -dc '0-9')"
info "Free space in \$HOME fs: ${avail_gb:-?} GB"
if [[ -n "$avail_gb" ]] && (( avail_gb >= 100 )); then
  pass "Free space >= 100GB"
elif [[ -n "$avail_gb" ]] && (( avail_gb >= 30 )); then
  warn "Free space ${avail_gb}GB — CUDA images + clusters can consume 30-50GB"
elif [[ -n "$avail_gb" ]]; then
  fail "Free space ${avail_gb}GB is too low"
fi

# ---------- 3. Docker ----------
section "Docker"

docker_desktop=0
if [[ -d /mnt/wsl/docker-desktop ]] || [[ -d /mnt/wsl/docker-desktop-data ]]; then
  docker_desktop=1
fi
if mount 2>/dev/null | grep -qi "docker-desktop"; then
  docker_desktop=1
fi

# Additional docker.sock symlink detection (RESEARCH.md §Ref-10)
sock_target=$(readlink /var/run/docker.sock 2>/dev/null || echo "")
if [[ "$sock_target" == *"docker-desktop"* ]] || [[ "$sock_target" == *"/mnt/wsl"* ]]; then
  docker_desktop=1
fi

# PRE-08: Docker Desktop detection upgraded from warn to fail (RESEARCH.md §Ref-10)
if (( docker_desktop == 1 )); then
  fail "Docker Desktop WSL integration is active on this distro.
      This project requires Docker Engine installed natively (not via Desktop integration).
      Fix: Docker Desktop → Settings → Resources → WSL Integration → disable for this distro.
      Then run: scripts/install-docker.sh"
fi

if have docker; then
  pass "docker CLI present: $(docker --version 2>/dev/null)"
  if docker info >/dev/null 2>&1; then
    pass "docker daemon reachable"
    server_ver="$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo unknown)"
    info "Docker server version: ${server_ver}"
    if id -nG "$USER" | tr ' ' '\n' | grep -qx docker; then
      pass "User '$USER' in 'docker' group"
    else
      warn "User '$USER' not in 'docker' group — you'll need sudo for docker commands"
    fi
  else
    warn "docker CLI present but daemon not reachable (stopped? permissions?)"
  fi
else
  info "docker not installed (install-docker.sh will handle this)"
fi

# ---------- 4. NVIDIA / GPU ----------
section "NVIDIA / GPU"

if [[ -e /usr/lib/wsl/lib/libcuda.so.1 ]] || [[ -e /usr/lib/wsl/lib/libcuda.so ]]; then
  pass "WSL libcuda stub present at /usr/lib/wsl/lib/ (Windows driver bridge)"
else
  warn "WSL libcuda stub not found at /usr/lib/wsl/lib/ — GPU-PV may not be wired up"
fi

if have nvidia-smi; then
  if nvidia-smi >/dev/null 2>&1; then
    gpu_name="$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)"
    driver_ver="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)"
    cuda_hdr="$(nvidia-smi 2>/dev/null | awk '/CUDA Version/ {for(i=1;i<=NF;i++) if($i=="Version:") print $(i+1)}' | head -1)"
    pass "nvidia-smi works — ${gpu_name}"
    info "Driver: ${driver_ver}, reported CUDA: ${cuda_hdr}"
    if [[ "$gpu_name" == *"5090"* ]]; then
      pass "RTX 5090 detected (Blackwell, sm_120 — requires CUDA 12.8+)"
      major="${driver_ver%%.*}"
      if [[ -n "$major" ]] && (( major < 570 )); then
        fail "RTX 5090 needs Windows driver 570.x+ (have ${driver_ver})"
      fi
    fi
  else
    warn "nvidia-smi installed but failed — check Windows driver install"
  fi
else
  info "nvidia-smi not in PATH (expected if GPU bits aren't set up yet)"
fi

if have nvidia-ctk; then
  pass "nvidia-container-toolkit installed"
else
  info "nvidia-container-toolkit not installed (needed for GPU in containers)"
fi

if have docker && docker info 2>/dev/null | grep -qiE "Runtimes:.*nvidia"; then
  pass "docker has nvidia runtime registered"
elif have docker; then
  info "docker nvidia runtime not registered yet"
fi

# PRE-04 enhancement: check default-runtime is nvidia (RESEARCH.md §Ref-5)
if have docker && docker info >/dev/null 2>&1; then
  if docker info --format '{{.DefaultRuntime}}' 2>/dev/null | grep -qx "nvidia"; then
    pass "docker default-runtime is nvidia"
  else
    fail "docker default-runtime is NOT nvidia (got: $(docker info --format '{{.DefaultRuntime}}' 2>/dev/null)).
      Fix: run scripts/install-docker.sh (performs jq-merge to set default-runtime in /etc/docker/daemon.json)"
  fi
fi

# ---------- 5. Network / ports ----------
section "Network / ports (k3d will want these)"

check_port() {
  local port="$1"
  if ss -ltn 2>/dev/null | awk 'NR>1 {print $4}' | grep -qE "[:.]${port}$"; then
    warn "Port ${port} is in use"
    ss -ltnp 2>/dev/null | awk -v p=":${port}" '$4 ~ p {print "      " $0}' | head -2
  else
    pass "Port ${port} free"
  fi
}

for p in 6443 6444 6445 8080 8081 8082; do
  check_port "$p"
done

# ---------- 6. Existing container / k8s state ----------
section "Existing container / k8s state"

if have docker && docker info >/dev/null 2>&1; then
  running="$(docker ps --format '{{.Names}}' 2>/dev/null | wc -l)"
  total="$(docker ps -a --format '{{.Names}}' 2>/dev/null | wc -l)"
  info "Docker containers: ${running} running, ${total} total"

  k3d_n="$(docker ps -a --filter 'name=k3d-' --format '{{.Names}}' 2>/dev/null | wc -l)"
  if (( k3d_n > 0 )); then
    warn "${k3d_n} existing k3d containers — consider cleaning before fresh start"
    docker ps -a --filter 'name=k3d-' --format '      {{.Names}} ({{.Status}})' 2>/dev/null | head -10
  else
    pass "No existing k3d containers"
  fi

  kind_n="$(docker ps -a --filter 'name=kind' --format '{{.Names}}' 2>/dev/null | wc -l)"
  if (( kind_n > 0 )); then
    info "${kind_n} Kind containers present"
  fi

  if docker network ls --format '{{.Name}}' 2>/dev/null | grep -qx "k8s-net"; then
    warn "Docker network 'k8s-net' already exists — will be reused or need manual removal"
  fi
fi

if have k3d; then
  # k3d cluster list -o json returns [] when empty
  cluster_count="$(k3d cluster list -o json 2>/dev/null | grep -c '"name"' || true)"
  if (( cluster_count > 0 )); then
    warn "${cluster_count} existing k3d cluster(s)"
    k3d cluster list 2>/dev/null | sed 's/^/      /'
  fi
fi

# ---------- 7. Tools (version pins from .tool-versions) ----------
section "Tools (version pins from .tool-versions)"

# Always-required system tools
check_required() {
  if have "$1"; then pass "$1: $(show_tool_version "$1")"
  else fail "$1 not installed"; fi
}
show_tool_version() {
  local t="$1"
  case "$t" in
    kubectl) kubectl version --client --output=yaml 2>/dev/null | awk '/gitVersion:/ {print $2}' | head -1 ;;
    helm)    helm version --short 2>/dev/null ;;
    flux)    flux --version 2>/dev/null | head -1 ;;
    k3d)     k3d version 2>/dev/null | head -1 ;;
    task)    task --version 2>/dev/null ;;
    asdf)    asdf --version 2>/dev/null ;;
    jq)      jq --version 2>/dev/null ;;
    yq)      yq --version 2>/dev/null | head -1 ;;
    k9s)     k9s version 2>/dev/null | grep -oP 'Version:\s+\K\S+' ;;
    *)       "$t" --version 2>&1 | head -1 ;;
  esac
}
check_required git
check_required curl
check_required jq

# asdf-managed tools: verify presence AND version pin matches .tool-versions
TOOL_VERSIONS_FILE="${REPO_ROOT}/.tool-versions"
if [[ ! -f "$TOOL_VERSIONS_FILE" ]]; then
  fail ".tool-versions not found at ${REPO_ROOT} — repo may be incomplete"
else
  info "Checking tool versions against ${TOOL_VERSIONS_FILE}"
  # Map .tool-versions plugin names to executable names
  declare -A PLUGIN_TO_CMD
  PLUGIN_TO_CMD[flux2]="flux"
  PLUGIN_TO_CMD[task]="task"
  # All other plugin names match the executable name directly

  while IFS=' ' read -r plugin expected_ver; do
    [[ -z "$plugin" || "$plugin" == \#* ]] && continue
    cmd="${PLUGIN_TO_CMD[$plugin]:-$plugin}"
    if ! have "$cmd"; then
      fail "$cmd not installed (expected ${expected_ver} from .tool-versions) — run scripts/install-tools.sh"
      continue
    fi
    actual_ver="$(show_tool_version "$cmd" 2>/dev/null || echo unknown)"
    if echo "$actual_ver" | grep -qF "$expected_ver"; then
      pass "$cmd: ${actual_ver} (matches ${expected_ver})"
    else
      fail "$cmd: version mismatch — expected ${expected_ver}, got ${actual_ver}. Run scripts/install-tools.sh"
    fi
  done < "$TOOL_VERSIONS_FILE"
fi

# asdf itself
if have asdf; then
  pass "asdf: $(asdf --version 2>/dev/null)"
else
  fail "asdf not installed — run scripts/install-tools.sh"
fi

# ---------- 9. .env secrets (PRE-09) ----------
section ".env secrets presence (PRE-09)"
preflight_check_env_file "${REPO_ROOT}/.env"

# ---------- 10. Tool shim precedence (PRE-10) ----------
section "Tool shim precedence (PRE-10)"
SHIM_DIR="${ASDF_DATA_DIR:-$HOME/.asdf}/shims"
for tool in kubectl helm k3d; do
  if have "$tool"; then
    tool_path="$(command -v "$tool")"
    if [[ "$tool_path" == "$SHIM_DIR"* ]]; then
      pass "$tool resolves via asdf shim ($tool_path)"
    else
      fail "$tool resolves to $tool_path (outside asdf shims at $SHIM_DIR).
        Fix: ensure ${SHIM_DIR} precedes /usr/bin in PATH.
        Run: source ~/.karyon/shell-init.sh  (or open a new terminal after running install-tools.sh)"
    fi
  else
    fail "$tool not found — run scripts/install-tools.sh"
  fi
done

# ---------- 11. systemd-resolved stub (PRE-11) ----------
section "systemd-resolved DNS stub (PRE-11)"
preflight_check_systemd_resolved /etc/resolv.conf

# ---------- 12. Clock skew check (PRE-12) ----------
section "Clock skew check (PRE-12)"
sys_epoch="$(date -u +%s 2>/dev/null)"
win_epoch=""

# Primary: powershell.exe (no sudo required; standard WSL2 interop)
# [DateTimeOffset]::UtcNow returns a UTC-anchored instant regardless of the host's local
# timezone; .ToUnixTimeSeconds() returns a Unix epoch integer. The prior PowerShell call
# used Get-Date with UFormat %s, which returned local-time-as-if-UTC seconds — a known
# quirk causing PRE-12 to false-positive with a skew equal to the TZ offset (gap 1 in
# .planning/phases/01-host-foundation/01-HUMAN-UAT.md).
if have powershell.exe; then
  win_epoch="$(powershell.exe -NoProfile -Command '[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()' 2>/dev/null \
    | tr -d '\r' | awk '{print int($1)}')"
fi

# Second-chance fallback: sudo -n hwclock (non-interactive sudo — no password prompt)
if [[ -z "$win_epoch" ]]; then
  win_epoch="$(sudo -n hwclock --get --utc 2>/dev/null \
    | awk '{print $1, $2}' \
    | date -f - +%s 2>/dev/null || echo "")"
fi

if [[ -z "$sys_epoch" || -z "$win_epoch" ]]; then
  warn "PRE-12 clock skew: could not read reference time (powershell.exe not reachable and sudo -n hwclock failed).
    Install Windows PowerShell WSL integration or run preflight with sudo for PRE-12 enforcement."
else
  skew=$(( sys_epoch - win_epoch ))
  skew_abs="${skew#-}"  # absolute value via string manipulation
  if (( skew_abs > 30 )); then
    fail "PRE-12 clock skew: WSL vs Windows differs by ${skew_abs}s (threshold 30s).
      Fix: sudo hwclock -s  (or: sudo systemctl restart systemd-timesyncd)"
  else
    pass "PRE-12 clock skew within ${skew_abs}s (threshold 30s)"
  fi
fi

# ---------- 13. cgroup v2 purity (PRE-13) ----------
section "cgroup v2 purity (PRE-13)"
preflight_check_cgroup_v2

# ---------- 14. Bridge networking probe (PRE-14) ----------
# D-04: belt-and-suspenders check — runs regardless of PRE-03 mirrored detection result.
# Creates ephemeral Docker resources (network + 2 containers) and trap-cleans them.
# preflight.sh is read-only w.r.t. persistent host state; PRE-14 ephemeral Docker
# resources are the sole exception — all are removed before this section exits.
section "Bridge networking probe (PRE-14)"

if ! have docker || ! docker info >/dev/null 2>&1; then
  warn "docker not reachable — skipping bridge probe (install docker first)"
else
  # Run PRE-14 in a subshell so the EXIT trap is scoped to this probe only.
  (
    _PRE14_NET="preflight-pre14-net"
    _PRE14_A="preflight-pre14-a"
    _PRE14_B="preflight-pre14-b"

    # Cleanup function — called by trap on any exit path
    _pre14_cleanup() {
      docker rm -f "$_PRE14_A" "$_PRE14_B" >/dev/null 2>&1 || true
      docker network rm "$_PRE14_NET" >/dev/null 2>&1 || true
    }
    trap _pre14_cleanup EXIT

    # Pre-check: remove stragglers from a crashed prior run
    if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q '^preflight-pre14-'; then
      info "PRE-14: cleaning up preflight-pre14-* stragglers from prior run"
      docker rm -f "$_PRE14_A" "$_PRE14_B" >/dev/null 2>&1 || true
    fi
    if docker network ls --format '{{.Name}}' 2>/dev/null | grep -qx "$_PRE14_NET"; then
      info "PRE-14: removing straggler network ${_PRE14_NET} from prior run"
      docker network rm "$_PRE14_NET" >/dev/null 2>&1 || true
    fi

    # Create the ephemeral test network
    docker network create "$_PRE14_NET" >/dev/null 2>&1

    # Start server container
    A_ID=$(docker run -d --network "$_PRE14_NET" --name "$_PRE14_A" \
      busybox sh -c 'echo ok > /tmp/h && httpd -f -p 8080 -h /tmp' 2>/dev/null || echo "")

    probe_pass=0
    if [[ -n "$A_ID" ]]; then
      result=$(docker run --rm --network "$_PRE14_NET" --name "$_PRE14_B" busybox \
        wget -qO- "http://${_PRE14_A}:8080/h" 2>/dev/null || echo "FAIL")
      [[ "$result" == "ok" ]] && probe_pass=1
    fi

    # Cleanup happens via trap — explicit call to ensure immediate removal
    _pre14_cleanup

    # Post-cleanup verification: warn if stragglers persist (not a config failure)
    straggler_names="$(docker ps -a --filter "name=preflight-pre14" --format '{{.Names}}' 2>/dev/null)"
    if [[ -n "$straggler_names" ]]; then
      warn "PRE-14 left stragglers after cleanup: ${straggler_names} — may be a Docker race; re-run preflight"
    fi

    if (( probe_pass == 1 )); then
      pass "bridge-curl probe: container DNS resolution on ${_PRE14_NET} works"
      exit 0
    else
      fail "bridge-curl probe FAILED — Docker custom network DNS is broken.
        In mirrored mode this is a known limitation (moby/moby#48201).
        Fix: set networkingMode=NAT in %USERPROFILE%\\.wslconfig, then run 'wsl --shutdown'.
        See docs/wsl-networking.md for the migration procedure."
      exit 1
    fi
  )
  # Propagate the subshell exit code into the outer pass/fail counters
  _pre14_rc=$?
  if (( _pre14_rc != 0 )); then
    # fail() already called inside subshell; outer FAIL counter needs incrementing
    # (subshell counters are separate). Re-record the failure at outer scope.
    fail "PRE-14 bridge probe failed (see above)"
  fi
fi

# ---------- 8. Summary ----------
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
