#!/usr/bin/env bash
# scripts/install-nvidia-container-toolkit.sh
# Idempotent NVIDIA container toolkit installer for WSL2 Ubuntu 24.04.
# Installs nvidia-container-toolkit, configures Docker runtime integration.
#
# Prerequisites: Docker Engine must be installed and daemon.json must have
# default-runtime=nvidia (set by install-docker.sh). Run install-docker.sh first.
#
# This script calls `nvidia-ctk runtime configure --runtime=docker` which adds
# ONLY the `runtimes.nvidia` key to daemon.json via structured merge. It does NOT
# write default-runtime or dns — those are owned by install-docker.sh (Plan 02).
#
# Usage:  bash scripts/install-nvidia-container-toolkit.sh
# Safe to re-run — skips steps already done.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/preflight-lib.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/preflight-lib.sh"

NVIDIA_CONTAINER_TOOLKIT_VERSION="1.19.0-1"
DAEMON_JSON=/etc/docker/daemon.json

# ---------------------------------------------------------------------------
# Pre-check: verify Docker daemon is reachable and default-runtime=nvidia is
# already set (H1 guard — prevents execution-order violation with Plan 02).
# ---------------------------------------------------------------------------
section "Pre-check: Docker daemon and daemon.json state"
if ! have docker || ! docker info >/dev/null 2>&1; then
  fail "Docker daemon not reachable — run install-docker.sh first, then re-login for docker group membership"
  exit 1
fi
pass "Docker daemon is reachable"

# Guard: verify install-docker.sh has already written default-runtime=nvidia.
# nvidia-ctk configure uses structured merge and will preserve this key,
# but we verify it exists first to catch execution-order violations.
_key='"default-runtime"'
_dr_check=$(jq -r "${_key} // empty" "$DAEMON_JSON" 2>/dev/null)
if [[ "$_dr_check" != "nvidia" ]]; then
  fail "daemon.json does not have default-runtime=nvidia (expected from install-docker.sh).
      Run install-docker.sh before running this script."
  exit 1
fi
pass "daemon.json has default-runtime=nvidia (set by install-docker.sh)"

# ---------------------------------------------------------------------------
# Section 1: NVIDIA apt keyring + repo
# Guard: keyring file exists at /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
# ---------------------------------------------------------------------------
section "NVIDIA apt keyring + repo"
if [[ -f /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg ]]; then
  info "already done, skipping: NVIDIA apt keyring + repo"
else
  curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
    | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

  curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
    | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
    | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null

  sudo apt-get update -q
  pass "installing: NVIDIA apt keyring and repo"
fi

# ---------------------------------------------------------------------------
# Section 2: nvidia-container-toolkit packages (pinned version)
# Guard: dpkg -s nvidia-container-toolkit returns 0
# ---------------------------------------------------------------------------
section "nvidia-container-toolkit packages (${NVIDIA_CONTAINER_TOOLKIT_VERSION})"
if dpkg -s nvidia-container-toolkit >/dev/null 2>&1; then
  info "already done, skipping: nvidia-container-toolkit ${NVIDIA_CONTAINER_TOOLKIT_VERSION}"
else
  sudo apt-get install -y \
    "nvidia-container-toolkit=${NVIDIA_CONTAINER_TOOLKIT_VERSION}" \
    "nvidia-container-toolkit-base=${NVIDIA_CONTAINER_TOOLKIT_VERSION}" \
    "libnvidia-container-tools=${NVIDIA_CONTAINER_TOOLKIT_VERSION}" \
    "libnvidia-container1=${NVIDIA_CONTAINER_TOOLKIT_VERSION}"
  pass "installing: nvidia-container-toolkit ${NVIDIA_CONTAINER_TOOLKIT_VERSION}"
fi

# ---------------------------------------------------------------------------
# Section 3: nvidia-ctk runtime configure
# Guard: docker info shows Runtimes:.*nvidia
# Post-verify: confirm default-runtime=nvidia preserved after nvidia-ctk merge (H1).
# nvidia-ctk configure uses structured merge — adds runtimes.nvidia ONLY.
# It does NOT write default-runtime or dns (owned by install-docker.sh).
# ---------------------------------------------------------------------------
section "nvidia-ctk runtime configure"
if docker info 2>/dev/null | grep -qi "Runtimes:.*nvidia"; then
  info "already done, skipping: nvidia-ctk runtime configure"
else
  sudo nvidia-ctk runtime configure --runtime=docker
  sudo systemctl restart docker

  # Verify additive merge: both default-runtime (from install-docker.sh) and runtimes.nvidia
  # (from nvidia-ctk) must be present. If default-runtime was clobbered, fail loudly.
  # Repair hint: manually restore the nvidia runtime key in daemon.json, then restart docker.
  _dr_post=$(jq -r "${_key} // empty" "$DAEMON_JSON" 2>/dev/null)
  if [[ "$_dr_post" != "nvidia" ]]; then
    fail "nvidia-ctk configure clobbered default-runtime in daemon.json — manual repair needed (see comment above)"
    exit 1
  fi
  pass "installing: nvidia-ctk runtime configure --runtime=docker"
  info "NOTE: default-runtime=nvidia is preserved (set by install-docker.sh, verified after nvidia-ctk)"
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
printf "\n%sNVIDIA container toolkit install complete.%s\n" "$C_GREEN" "$C_RESET"
printf "Verify: docker info | grep -i 'Runtimes\\|DefaultRuntime'\n"
