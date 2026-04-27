#!/usr/bin/env bash
# preflight-check.sh
# Read-only environment check for the k8s-lab project.
# Run inside your WSL2 Ubuntu instance. Makes no changes. Safe to re-run.
#
# Usage:  bash preflight-check.sh
# Exit:   0 if no blockers, 1 if blockers present.

set -u  # intentionally NOT -e: we want to continue through failed checks

# ---------- output helpers ----------
if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_DIM=$'\033[2m'; C_BOLD=$'\033[1m'
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_BLUE=$'\033[34m'
else
  C_RESET=""; C_DIM=""; C_BOLD=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_BLUE=""
fi

PASS=0; WARN=0; FAIL=0
WARN_MSGS=(); FAIL_MSGS=()

section() { printf "\n%s%s== %s ==%s\n" "$C_BOLD" "$C_BLUE" "$1" "$C_RESET"; }
pass()    { printf "  %s✓%s %s\n" "$C_GREEN" "$C_RESET" "$1"; PASS=$((PASS+1)); }
warn()    { printf "  %s!%s %s\n" "$C_YELLOW" "$C_RESET" "$1"; WARN=$((WARN+1)); WARN_MSGS+=("$1"); }
fail()    { printf "  %s✗%s %s\n" "$C_RED" "$C_RESET" "$1"; FAIL=$((FAIL+1)); FAIL_MSGS+=("$1"); }
info()    { printf "  %s·%s %s\n" "$C_DIM" "$C_RESET" "$1"; }

have()    { command -v "$1" >/dev/null 2>&1; }

# ---------- 1. WSL environment ----------
section "WSL environment"

if uname -r | grep -qi "WSL2"; then
  pass "WSL2 kernel detected ($(uname -r))"
elif uname -r | grep -qi "microsoft"; then
  fail "Looks like WSL1 — this project requires WSL2 ('wsl --set-version <distro> 2')"
elif grep -qiE "(microsoft|wsl)" /proc/version 2>/dev/null; then
  warn "Inside WSL but couldn't confirm WSL2 from kernel string"
else
  fail "Not running inside WSL"
fi

if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  info "Distro: ${PRETTY_NAME:-unknown}"
  if [[ "${ID:-}" == "ubuntu" ]]; then
    case "${VERSION_ID:-}" in
      24.04) pass "Ubuntu 24.04 (target)" ;;
      22.04) warn "Ubuntu 22.04 — project targets 24.04; 22.04 usable but untested" ;;
      *)     warn "Ubuntu ${VERSION_ID:-?} — untested for this project" ;;
    esac
  else
    warn "Non-Ubuntu distro (${ID:-unknown}) — project targets Ubuntu 24.04"
  fi
fi

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

if (( docker_desktop == 1 )); then
  warn "Docker Desktop WSL integration detected — project wants Docker Engine installed directly in this distro. Disable Desktop's integration for this distro (Desktop → Settings → Resources → WSL integration) before proceeding."
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

# ---------- 7. Tools ----------
section "Tools (required + helpful)"

show_tool_version() {
  local t="$1"
  case "$t" in
    kubectl) kubectl version --client 2>/dev/null | head -1 ;;
    helm)    helm version --short 2>/dev/null ;;
    flux)    flux --version 2>/dev/null | head -1 ;;
    k3d)     k3d version 2>/dev/null | head -1 ;;
    task)    task --version 2>/dev/null ;;
    asdf)    asdf --version 2>/dev/null ;;
    *)       "$t" --version 2>&1 | head -1 ;;
  esac
}

check_required() {
  if have "$1"; then pass "$1: $(show_tool_version "$1")"
  else fail "$1 not installed"; fi
}
check_optional() {
  if have "$1"; then pass "$1: $(show_tool_version "$1")"
  else info "$1 not installed (install-tools.sh will handle)"; fi
}

check_required git
check_required curl
check_required jq
check_optional yq
check_optional kubectl
check_optional helm
check_optional flux
check_optional k3d
check_optional task
check_optional asdf

if have kubectl && have asdf; then
  if ! asdf which kubectl >/dev/null 2>&1; then
    info "kubectl is installed outside asdf — may conflict once project pins a version"
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