#!/usr/bin/env bash
# images/image-tag.sh
#
# Single source of truth for the karyon/k3s-cuda image tag string.
# Called by:
#   - scripts/build-image.sh: docker build -t "$(images/image-tag.sh)" ...
#   - scripts/create-clusters.sh: k3d cluster create ... --image "$(images/image-tag.sh)"
#
# Reads the Dockerfile ARG defaults so pins live in exactly one place.
#
# Output format: karyon/k3s-cuda:<K3S_TAG>-cuda<CUDA_TAG_SHORT>
# Example:       karyon/k3s-cuda:v1.34.6-k3s1-cuda12.8.1
#
# Safe to source or exec: writes only to stdout; no side effects.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKERFILE="${SCRIPT_DIR}/Dockerfile.k3s-cuda"

if [[ ! -f "$DOCKERFILE" ]]; then
  echo "image-tag.sh: Dockerfile.k3s-cuda not found at ${DOCKERFILE}" >&2
  exit 1
fi

# Extract ARG defaults. Lines look like:  ARG K3S_TAG=v1.34.6-k3s1
K3S_TAG="$(grep -E '^ARG K3S_TAG=' "$DOCKERFILE" | head -1 | cut -d= -f2)"
CUDA_TAG="$(grep -E '^ARG CUDA_TAG=' "$DOCKERFILE" | head -1 | cut -d= -f2)"

if [[ -z "$K3S_TAG" || -z "$CUDA_TAG" ]]; then
  echo "image-tag.sh: failed to parse K3S_TAG or CUDA_TAG defaults from ${DOCKERFILE}" >&2
  exit 1
fi

# CUDA_TAG short form: 12.8.1-base-ubuntu22.04 → 12.8.1
CUDA_TAG_SHORT="${CUDA_TAG%%-*}"

printf '%s\n' "karyon/k3s-cuda:${K3S_TAG}-cuda${CUDA_TAG_SHORT}"
