#!/usr/bin/env bash
# scripts/delete-clusters.sh
#
# INTENTIONALLY NOT calling `docker system prune` or `docker builder prune`.
# CUDA build layers must survive the `task rebuild` SLO (REQ-DESTROY-03).
# A lint in Phase 6 (REQ-DESTROY-04) will enforce this across scripts/.
#
# Requirements satisfied: CLU-06
# Decisions honored:      D-14
#
# Usage: bash scripts/delete-clusters.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/preflight-lib.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/preflight-lib.sh"

readonly K8S_NET_NAME="k8s-net"
readonly CUDA_IMAGE_TAG="$("${REPO_ROOT}/images/image-tag.sh")"

# ---------- Section 1: delete clusters ----------
# Recommendation: per-cluster delete (clearer errors for missing-cluster cases) over
# --all (which can swallow ordering bugs). Script tolerates missing clusters
# idempotently via pre-check.
section "k3d clusters"
for name in hub-flux spoke-ml spoke-apps; do
  if k3d cluster list --no-headers 2>/dev/null | awk '{print $1}' | grep -qx "$name"; then
    info "deleting: cluster ${name}"
    k3d cluster delete "$name" >/dev/null
    pass "deleted: cluster ${name}"
  else
    info "already done, skipping: cluster ${name} (not present)"
  fi
done

# ---------- Section 2: k8s-net network ----------
# Clusters must be gone first (containers must detach before network removal).
# k3d does NOT manage networks it didn't create; explicit docker network rm required.
section "k8s-net network"
if docker network inspect "$K8S_NET_NAME" >/dev/null 2>&1; then
  docker network rm "$K8S_NET_NAME" >/dev/null
  pass "deleted: ${K8S_NET_NAME}"
else
  info "already done, skipping: ${K8S_NET_NAME} (not present)"
fi

# ---------- Section 3: post-run image-survival verification (D-14) ----------
# Defense-in-depth before Phase 6 DESTROY-04 lint ships. Any script downstream of us
# that adds `docker system prune` / `docker builder prune` would make this check fail.
section "Build cache defense"
if docker images "$CUDA_IMAGE_TAG" --format '{{.Repository}}:{{.Tag}}' | grep -qx "$CUDA_IMAGE_TAG"; then
  pass "karyon/k3s-cuda image survived teardown (expected: ${CUDA_IMAGE_TAG})"
else
  fail "karyon/k3s-cuda image ${CUDA_IMAGE_TAG} is missing after teardown — a prune path slipped in.
     Audit: grep -rE 'docker (system|builder) prune' scripts/
     Rebuild: scripts/build-image.sh"
  exit 1
fi

# ---------- Summary ----------
section "Summary"
printf "  %s%d passed%s, %s%d warnings%s, %s%d failed%s\n" \
  "$C_GREEN" "$PASS" "$C_RESET" "$C_YELLOW" "$WARN" "$C_RESET" "$C_RED" "$FAIL" "$C_RESET"
if (( FAIL > 0 )); then exit 1; fi
printf "\n%sTeardown complete. Build cache preserved.%s\n" "$C_GREEN" "$C_RESET"
