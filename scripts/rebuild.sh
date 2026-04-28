#!/usr/bin/env bash
# scripts/rebuild.sh
#
# Full destructive rebuild wrapper for the local karyon lab.
#
# Usage: bash scripts/rebuild.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/preflight-lib.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/preflight-lib.sh"

LOG_FILE="/tmp/karyon-rebuild.log"
readonly LOG_FILE

main() {
  : > "$LOG_FILE"

  if [[ "${KARYON_REBUILD_APPROVED:-}" != "yes" ]]; then
    section "Destructive rebuild confirmation"
    printf "This will delete and recreate the local karyon lab, then run the health gate.\n"
    printf "Type yes to continue: "

    local confirmation
    read -r confirmation

    if [[ "${confirmation}" != "yes" ]]; then
      fail "confirmation did not match exact yes; aborting before rebuild"
      exit 1
    fi
  else
    info "KARYON_REBUILD_APPROVED=yes set; skipping interactive confirmation"
  fi

  local start_epoch elapsed
  start_epoch="$(date +%s)"

  echo ">>> step destroy" | tee -a "$LOG_FILE"
  KARYON_DESTROY_APPROVED=yes bash "${SCRIPT_DIR}/destroy.sh" 2>&1 | tee -a "$LOG_FILE"

  echo ">>> step create-clusters" | tee -a "$LOG_FILE"
  bash "${SCRIPT_DIR}/create-clusters.sh" 2>&1 | tee -a "$LOG_FILE"

  # HIGH-1: k3d cluster create switches current context to the last-created
  # cluster. After create-clusters.sh finishes, current context is
  # k3d-spoke-apps. bootstrap-flux.sh and register-spokes-for-flux.sh fail if
  # current context is not k3d-hub-flux because they intentionally only assert
  # the active context. Pin context here so the rebuild chain does not break.
  echo ">>> pin context k3d-hub-flux" | tee -a "$LOG_FILE"
  kubectl config use-context k3d-hub-flux | tee -a "$LOG_FILE"

  echo ">>> step bootstrap-flux" | tee -a "$LOG_FILE"
  bash "${SCRIPT_DIR}/bootstrap-flux.sh" 2>&1 | tee -a "$LOG_FILE"

  echo ">>> step register-spokes" | tee -a "$LOG_FILE"
  bash "${SCRIPT_DIR}/register-spokes-for-flux.sh" 2>&1 | tee -a "$LOG_FILE"

  echo ">>> step deploy-examples" | tee -a "$LOG_FILE"
  bash "${SCRIPT_DIR}/deploy-examples.sh" 2>&1 | tee -a "$LOG_FILE"

  echo ">>> step health-check" | tee -a "$LOG_FILE"
  bash "${SCRIPT_DIR}/health-check.sh" 2>&1 | tee -a "$LOG_FILE"

  elapsed=$(( $(date +%s) - start_epoch ))
  echo "rebuild elapsed seconds: ${elapsed}" | tee -a "$LOG_FILE"

  if (( elapsed > 1200 )); then
    fail "rebuild exceeded 1200 second SLO (elapsed=${elapsed}); see ${LOG_FILE}"
    exit 1
  fi

  pass "rebuild completed within 1200 seconds (elapsed=${elapsed})"
}

main "$@"
