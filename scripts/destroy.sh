#!/usr/bin/env bash
# scripts/destroy.sh
#
# Confirmation wrapper for the cache-preserving k3d teardown.
#
# Usage: bash scripts/destroy.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/preflight-lib.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/preflight-lib.sh"

main() {
  if [[ "${KARYON_DESTROY_APPROVED:-}" == "yes" ]]; then
    info "KARYON_DESTROY_APPROVED=yes set; skipping interactive confirmation"
    bash "${SCRIPT_DIR}/delete-clusters.sh"
    return
  fi

  section "Destructive teardown confirmation"
  printf "This will delete the local k3d clusters and k8s-net network.\n"
  printf "The CUDA image/build cache is preserved by scripts/delete-clusters.sh.\n"
  printf "Type yes to continue: "

  local confirmation
  read -r confirmation

  if [[ "${confirmation}" != "yes" ]]; then
    fail "confirmation did not match exact yes; aborting before teardown"
    exit 1
  fi

  bash "${SCRIPT_DIR}/delete-clusters.sh"
}

main "$@"
