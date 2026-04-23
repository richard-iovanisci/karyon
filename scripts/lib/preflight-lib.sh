#!/usr/bin/env bash
# scripts/lib/preflight-lib.sh
# Shared output helpers, network math, and preflight check functions.
# Source this file; do not execute directly.
# Used by: scripts/preflight.sh, scripts/install-*.sh, tests/bats/*.bats
[[ "${BASH_SOURCE[0]}" == "$0" ]] && { echo "source this file, don't run it directly" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Section A: ANSI output helpers (verbatim from prereqs.sh)
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# Section B: Network math helpers (pure bash, no external tools)
# ---------------------------------------------------------------------------

# ip_to_int <dotted-quad>  — converts "192.168.1.5" to integer
ip_to_int() {
  local ip="$1"
  local a b c d
  IFS='.' read -r a b c d <<< "$ip"
  echo $(( (a << 24) | (b << 16) | (c << 8) | d ))
}

# ip_in_cidr <ip> <cidr>
# Returns 0 if <ip> is inside <cidr> (e.g. ip_in_cidr 192.168.1.5 192.168.1.0/24).
# Returns 1 otherwise.
# Pure bash arithmetic; no ipcalc, no python, no awk required.
ip_in_cidr() {
  local ip="$1"
  local cidr="$2"
  local net_addr prefix
  net_addr="${cidr%%/*}"
  prefix="${cidr##*/}"
  local ip_int net_int mask
  ip_int="$(ip_to_int "$ip")"
  net_int="$(ip_to_int "$net_addr")"
  # Build bitmask: shift 1 left by (32-prefix), subtract 1, invert within 32 bits
  mask=$(( 0xFFFFFFFF ^ ( (1 << (32 - prefix)) - 1 ) ))
  [[ $(( ip_int & mask )) -eq $(( net_int & mask )) ]]
}

# ---------------------------------------------------------------------------
# Section C: Preflight check functions (callable from bats and preflight.sh)
#
# Contract: each function takes no arguments (reads ambient host state),
# returns 0 on pass / 1 on fail, writes output via pass()/warn()/fail()/info().
# preflight.sh calls section() then delegates to the check function.
# bats suites source this library and invoke check functions directly.
# ---------------------------------------------------------------------------

# preflight_check_wsl_kernel: PRE-01
# Passes if uname -r contains "microsoft" (case-insensitive) and "WSL2".
preflight_check_wsl_kernel() {
  local kernel
  kernel="$(uname -r 2>/dev/null)"
  if echo "$kernel" | grep -qi "microsoft" && echo "$kernel" | grep -qi "WSL2"; then
    pass "WSL2 kernel detected: ${kernel}"
    return 0
  else
    fail "Not running on a WSL2 kernel (got: ${kernel:-empty}).
      Fix: ensure you are inside a WSL2 distro (not WSL1 or native Linux).
      Check: wsl.exe -l -v in PowerShell — VERSION column must show 2."
    return 1
  fi
}

# preflight_check_ubuntu_24_04: PRE-02
# Passes if /etc/os-release has ID=ubuntu and VERSION_ID="24.04".
preflight_check_ubuntu_24_04() {
  local id version_id
  # shellcheck source=/dev/null
  id="$(. /etc/os-release 2>/dev/null && echo "${ID:-}")"
  # shellcheck source=/dev/null
  version_id="$(. /etc/os-release 2>/dev/null && echo "${VERSION_ID:-}")"
  if [[ "$id" == "ubuntu" && "$version_id" == "24.04" ]]; then
    pass "Ubuntu 24.04 confirmed (ID=${id}, VERSION_ID=${version_id})"
    return 0
  else
    fail "Expected Ubuntu 24.04 but got ID=${id:-unknown} VERSION_ID=${version_id:-unknown}.
      Fix: install Ubuntu 24.04 from the Microsoft Store and re-provision."
    return 1
  fi
}

# preflight_check_env_file: PRE-09
# Argument: path to .env file (REPO_ROOT/.env)
# Passes if file exists and GITHUB_OWNER/GITHUB_REPO/GITHUB_TOKEN are all non-empty.
preflight_check_env_file() {
  local env_file="$1"
  if [[ ! -f "$env_file" ]]; then
    fail ".env not found — run: cp .env.example .env && edit it (fill in GITHUB_OWNER, GITHUB_REPO, GITHUB_TOKEN)"
    return 1
  fi
  pass ".env file exists"
  local key val rc=0
  for key in GITHUB_OWNER GITHUB_REPO GITHUB_TOKEN; do
    val="$(grep -E "^${key}=" "$env_file" 2>/dev/null | cut -d= -f2-)"
    if [[ -z "$val" ]]; then
      fail "${key} is missing or empty in .env — edit .env and set a non-empty value"
      rc=1
    else
      pass "${key} is set (value hidden)"
    fi
  done
  return $rc
}

# preflight_check_systemd_resolved: PRE-11
# Argument: path to resolv.conf (default /etc/resolv.conf)
# Fails if nameserver 127.0.0.53 is present.
preflight_check_systemd_resolved() {
  local resolv_file="${1:-/etc/resolv.conf}"
  if grep -qE '^nameserver[[:space:]]+127\.0\.0\.53' "$resolv_file" 2>/dev/null; then
    fail "systemd-resolved 127.0.0.53 stub detected in ${resolv_file}.
      Containers inheriting this nameserver cannot resolve external DNS.
      Fix: run scripts/install-docker.sh — it sets explicit dns=[1.1.1.1,8.8.8.8] in /etc/docker/daemon.json"
    return 1
  else
    pass "resolv.conf nameserver is not 127.0.0.53 stub"
    return 0
  fi
}

# preflight_check_cgroup_v2: PRE-13
# Passes if /sys/fs/cgroup is mounted as cgroup2fs.
preflight_check_cgroup_v2() {
  local cg_type
  cg_type="$(stat -fc %T /sys/fs/cgroup 2>/dev/null)"
  if [[ "$cg_type" == "cgroup2fs" ]]; then
    pass "cgroup v2 pure (cgroup2fs)"
    return 0
  elif [[ "$cg_type" == "tmpfs" ]]; then
    fail "cgroup v1 or hybrid detected (got: tmpfs) — k3d + GPU workloads require pure cgroup v2.
      Fix: check %USERPROFILE%\\.wslconfig for kernelCommandLine overrides; ensure WSL kernel >= 5.15"
    return 1
  else
    warn "unable to determine cgroup type (got: ${cg_type:-empty}) — may be harmless on this kernel"
    return 0
  fi
}

# preflight_check_mirrored_mode: PRE-03
# Uses the D-02 IP-subnet overlap heuristic, with authoritative pre-check against
# wsl.exe --status and a warn()-downgrade when the overlap is explainable by a
# shared home-router subnet (common false-positive pattern surfaced in 01-HUMAN-UAT.md).
#
# Policy (per D-01 + plan 01-09 gap closure):
#   1. wsl.exe --status says networkingMode: mirrored  -> fail() (unambiguous)
#   2. Subnet overlap AND default-gateway-equals-host AND CIDR in RFC1918 home-router
#      range AND wsl.exe does NOT confirm mirrored                 -> warn() (likely false positive)
#   3. Subnet overlap but does NOT match the home-router pattern   -> fail() (preserves D-01)
#   4. No subnet overlap                                           -> pass() (NAT)
#
# This preserves D-01's hard-fail intent for unambiguous mirrored mode while fixing
# the false positive on typical home networks where the Windows host is the router.
preflight_check_mirrored_mode() {
  # Step 0: Authoritative pre-check via wsl.exe --status (runs inside WSL via interop).
  # If wsl.exe is unreachable or output does not include a networkingMode line, fall
  # through to the heuristic. If it explicitly says mirrored, fail immediately.
  local wsl_status=""
  if command -v wsl.exe >/dev/null 2>&1; then
    wsl_status="$(wsl.exe --status 2>/dev/null | tr -d '\r' || true)"
  fi
  if [[ -n "$wsl_status" ]] && echo "$wsl_status" | grep -qiE 'networkingMode:[[:space:]]*mirrored'; then
    fail "Mirrored networking confirmed by wsl.exe --status (networkingMode: mirrored).
      Project requires networkingMode=NAT (D-01). See docs/wsl-networking.md for the migration procedure."
    return 1
  fi

  # Step 1: Get all non-lo WSL IPv4 CIDRs
  local wsl_cidrs
  mapfile -t wsl_cidrs < <(ip -4 -o addr show 2>/dev/null | awk '$2 != "lo" {print $4}')

  if [[ ${#wsl_cidrs[@]} -eq 0 ]]; then
    warn "no non-loopback IPv4 interfaces found — cannot check mirrored mode"
    return 0
  fi

  # Step 2: Determine Windows host IP (try default route gateway first, then resolv.conf)
  local windows_ip=""
  local gw_ip
  gw_ip="$(ip -4 route show default 2>/dev/null | awk '/via/ {print $3}' | head -1)"
  [[ -n "$gw_ip" ]] && windows_ip="$gw_ip"

  # Fallback: resolv.conf nameserver (valid when generateResolvConf=true in wsl.conf)
  local windows_ip_source="gateway"
  if [[ -z "$windows_ip" ]]; then
    windows_ip="$(grep -m1 '^nameserver' /etc/resolv.conf 2>/dev/null | awk '{print $2}')"
    windows_ip_source="resolv.conf"
  fi

  if [[ -z "$windows_ip" ]]; then
    warn "could not determine Windows host IP — skipping mirrored-mode check"
    return 0
  fi

  # Step 3: Check if Windows host IP falls inside any WSL interface CIDR
  local cidr
  for cidr in "${wsl_cidrs[@]}"; do
    if ip_in_cidr "$windows_ip" "$cidr"; then
      # Heuristic fired. Classify as likely-false-positive only when BOTH:
      #   (a) windows_ip was derived from the default gateway (source=="gateway"),
      #       AND windows_ip == gw_ip (default gateway IS the host).
      #   (b) the overlapping CIDR is inside a common home-router RFC1918 range.
      # Note: wsl.exe --status was already consulted above; reaching here means it
      # did NOT confirm mirrored mode.
      local is_home_router_cidr=0
      if ip_in_cidr "${cidr%%/*}" "192.168.0.0/16" \
         || ip_in_cidr "${cidr%%/*}" "10.0.0.0/8" \
         || ip_in_cidr "${cidr%%/*}" "172.16.0.0/12"; then
        is_home_router_cidr=1
      fi

      if [[ "$windows_ip_source" == "gateway" && "$windows_ip" == "$gw_ip" && $is_home_router_cidr -eq 1 ]]; then
        warn "Mirrored-mode heuristic fired for Windows host ${windows_ip} inside WSL CIDR ${cidr}, but wsl.exe --status does not confirm mirrored mode. Likely false positive from shared home-router subnet.
      To silence: set networkingMode=NAT explicitly in %USERPROFILE%\\.wslconfig per D-03, and run 'wsl --shutdown'.
      If you believe this is actually mirrored mode, see docs/wsl-networking.md."
        return 0
      fi

      fail "Mirrored networking detected: Windows host IP ${windows_ip} is inside WSL interface CIDR ${cidr}.
      Project requires networkingMode=NAT (D-01). See docs/wsl-networking.md for the migration procedure.
      Authoritative signal (wsl.exe --status) was unavailable or ambiguous."
      return 1
    fi
  done

  pass "Networking mode appears to be NAT (Windows host IP ${windows_ip} not inside any WSL interface CIDR)"
  return 0
}
