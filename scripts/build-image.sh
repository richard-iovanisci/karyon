#!/usr/bin/env bash
# scripts/build-image.sh
#
# Builds karyon/k3s-cuda from images/Dockerfile.k3s-cuda.
# Separate script (not inlined in create-clusters.sh) so the image can be built
# on its own; scripts/create-clusters.sh calls it only if the image is absent.
#
# Usage: bash scripts/build-image.sh
# Output: karyon/k3s-cuda:<K3S_TAG>-cuda<CUDA_TAG_SHORT> in local Docker image store.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/preflight-lib.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/preflight-lib.sh"

# ---------- Section 1: build context sanity ----------
section "Build context sanity"
for required in images/Dockerfile.k3s-cuda images/config.toml.tmpl images/device-plugin-daemonset.yaml images/image-tag.sh; do
  if [[ ! -f "${REPO_ROOT}/${required}" ]]; then
    fail "${required} missing — cannot build karyon/k3s-cuda"
    exit 1
  fi
done
pass "required files present"

# ---------- Section 2: Docker BuildKit ----------
# `COPY --from=k3s / / --exclude=/bin` requires BuildKit + docker/dockerfile:1.7-labs frontend.
# Gate on the envvar path rather than the buildx plugin: the plugin may be
# absent in environments where BuildKit works fine via DOCKER_BUILDKIT=1.
section "BuildKit availability"
if ! DOCKER_BUILDKIT=1 docker build --help >/dev/null 2>&1; then
  fail "BuildKit capability check failed — Docker daemon does not support BuildKit; upgrade Docker Engine"
  exit 1
fi
pass "BuildKit capable"

# ---------- Section 3: build ----------
section "Build karyon/k3s-cuda"
TAG="$("${REPO_ROOT}/images/image-tag.sh")"
info "tag: ${TAG}"

cd "$REPO_ROOT"
DOCKER_BUILDKIT=1 docker build \
  --progress=plain \
  --tag "$TAG" \
  -f images/Dockerfile.k3s-cuda \
  .

pass "built: ${TAG}"

# ---------- Summary ----------
section "Summary"
printf "  %s%d passed%s, %s%d warnings%s, %s%d failed%s\n" \
  "$C_GREEN" "$PASS" "$C_RESET" "$C_YELLOW" "$WARN" "$C_RESET" "$C_RED" "$FAIL" "$C_RESET"
if (( FAIL > 0 )); then exit 1; fi
printf "\n%sImage ready: ${TAG}%s\n" "$C_GREEN" "$C_RESET"
