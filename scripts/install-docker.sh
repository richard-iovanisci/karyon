#!/usr/bin/env bash
# scripts/install-docker.sh
# Idempotent Docker Engine installer for WSL2 Ubuntu 24.04.
# Installs docker-ce, configures daemon.json, adds user to docker group,
# and installs the hwclock-resume.service unit for clock-skew fixes.
#
# Usage:  bash scripts/install-docker.sh
# Safe to re-run — skips steps already done.
#
# Security note (T-02-04): docker group = root-equivalent. User must explicitly
# run 'newgrp docker' or log out and back in — no silent activation.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/preflight-lib.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/preflight-lib.sh"

# ---------------------------------------------------------------------------
# Section 0: Prerequisites (jq, gnupg, ca-certificates, curl) — MUST BE FIRST
# H3 fix: jq needed for daemon.json merge (Section 6); gnupg for GPG key
# dearmor (Section 2). Install before any section that depends on them.
# ---------------------------------------------------------------------------
section "Prerequisites (jq, gnupg, ca-certificates, curl)"
if have jq && have gpg && dpkg -s ca-certificates >/dev/null 2>&1 && have curl; then
  info "already done, skipping: prerequisites (jq gnupg ca-certificates curl)"
else
  sudo apt-get update -q
  sudo apt-get install -y ca-certificates curl gnupg jq
  pass "installing: prerequisites (jq gnupg ca-certificates curl)"
fi

# ---------------------------------------------------------------------------
# Section 2: Docker GPG key
# Guard: key file exists at /etc/apt/keyrings/docker.asc
# ---------------------------------------------------------------------------
section "Docker GPG key"
if [[ -f /etc/apt/keyrings/docker.asc ]]; then
  info "already done, skipping: docker GPG key"
else
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  pass "installing: docker GPG key"
fi

# ---------------------------------------------------------------------------
# Section 3: Docker apt repository
# M2 content-correct guard: verify exact repo line (not just file presence).
# Detects drift (wrong codename, wrong signing-key path, stale Ubuntu version).
# ---------------------------------------------------------------------------
section "Docker apt repository"
# shellcheck source=/dev/null
CODENAME="$(. /etc/os-release 2>/dev/null && echo "${UBUNTU_CODENAME:-${VERSION_CODENAME:-noble}}")"
ARCH="$(dpkg --print-architecture)"
EXPECTED_REPO_LINE="deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${CODENAME} stable"

if grep -Fxq "$EXPECTED_REPO_LINE" /etc/apt/sources.list.d/docker.list 2>/dev/null; then
  info "already done, skipping: docker apt repo (${CODENAME})"
else
  echo "$EXPECTED_REPO_LINE" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update -q
  pass "installing: docker apt repo (${CODENAME})"
fi

# ---------------------------------------------------------------------------
# Section 4: Docker Engine packages
# Guard: docker-ce package installed
# ---------------------------------------------------------------------------
section "Docker Engine packages"
if dpkg -s docker-ce >/dev/null 2>&1; then
  info "already done, skipping: docker-ce packages"
else
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  pass "installing: docker-ce and plugins"
fi

# ---------------------------------------------------------------------------
# Section 5: docker group membership
# Guard: invoking user already in docker group
# T-02-04: docker group = root-equivalent; user must explicitly re-login
# ---------------------------------------------------------------------------
section "docker group membership"
if id -nG "$USER" | tr ' ' '\n' | grep -qx docker; then
  info "already done, skipping: user in docker group"
else
  sudo usermod -aG docker "$USER"
  pass "installing: user '$USER' added to docker group"
  info "IMPORTANT: run 'newgrp docker' or log out and back in to activate docker group membership"
fi

# ---------------------------------------------------------------------------
# Section 6: daemon.json — default-runtime + dns
# jq-merge strategy (RESEARCH.md §Ref-4, D-05).
# Guard: both default-runtime=nvidia and dns non-empty already set.
# T-02-05: guard checks both keys before writing; jq merge preserves existing keys.
# ---------------------------------------------------------------------------
section "daemon.json (default-runtime + dns)"
DAEMON_JSON=/etc/docker/daemon.json
DESIRED_DNS='["1.1.1.1","8.8.8.8"]'
DESIRED_RUNTIME="nvidia"

if [[ -f "$DAEMON_JSON" ]] && \
   sudo jq -e '."default-runtime" == "nvidia"' "$DAEMON_JSON" >/dev/null 2>&1 && \
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

# ---------------------------------------------------------------------------
# Section 7: hwclock-resume.service (clock-skew fix)
# M2 content-correct guard: uses systemctl is-enabled (not file-exists).
# Detects drift: file present but unit disabled/removed from systemd.
# D-08: this script is the owner of hwclock-resume.service installation.
# T-02-06: ExecStart is /sbin/hwclock --hctosys only — no network, no file writes.
# ---------------------------------------------------------------------------
section "hwclock-resume.service (clock-skew fix)"
UNIT_SRC="${SCRIPT_DIR}/../config/hwclock-resume.service"
UNIT_DEST=/etc/systemd/system/hwclock-resume.service

if [[ ! -f "$UNIT_SRC" ]]; then
  fail "config/hwclock-resume.service not found at ${UNIT_SRC} — run from repo root or check Plan 01 output"
  exit 1
fi

if systemctl is-enabled hwclock-resume.service 2>/dev/null | grep -q '^enabled$'; then
  info "already done, skipping: hwclock-resume.service"
else
  sudo cp "$UNIT_SRC" "$UNIT_DEST"
  sudo systemctl daemon-reload
  sudo systemctl enable hwclock-resume.service
  pass "installing: hwclock-resume.service (WSL2 clock-skew fix on resume)"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
section "Summary"
printf "  %s%d passed%s, %s%d warnings%s, %s%d failed%s\n" \
  "$C_GREEN" "$PASS" "$C_RESET" "$C_YELLOW" "$WARN" "$C_RESET" "$C_RED" "$FAIL" "$C_RESET"
if (( FAIL > 0 )); then
  printf "\n%sBlockers:%s\n" "$C_RED" "$C_RESET"
  for m in "${FAIL_MSGS[@]}"; do printf "  • %s\n" "$m"; done
  exit 1
fi
printf "\n%sDocker install complete. Verify with: docker info%s\n" "$C_GREEN" "$C_RESET"
