# tests/bats/test_helper.bash
# Shared loader for preflight bats suites.
# Sourced via `load 'test_helper'` in each suite.
# NOTE: bats resolves load paths relative to the suite file's directory.
# Since suites live in tests/bats/, `load 'test_helper'` resolves to this file.
# Do NOT use `load '../test_helper'` — that resolves to tests/test_helper (wrong path).

# Resolve scripts dir from bats test filename (works regardless of CWD)
SCRIPTS_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME:-$0}")/../.." && pwd)/scripts"

# Source the preflight helper library so pass()/fail()/warn()/info()/have() and
# all preflight_check_*() functions are available in test suites.
# shellcheck source=../../scripts/lib/preflight-lib.sh
# shellcheck disable=SC1091
source "${SCRIPTS_DIR}/lib/preflight-lib.sh"

# -----------------------------------------------------------------------------
# Cluster-layer extensions
# -----------------------------------------------------------------------------

# REPO_ROOT resolves the top of the repo from any bats suite.
REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME:-$0}")/../.." && pwd)"

# IMAGES_DIR: where Dockerfile.k3s-cuda, config.toml.tmpl, etc. live.
IMAGES_DIR="${REPO_ROOT}/images"

# cuda_image_tag: emits the canonical CUDA image tag via images/image-tag.sh
# (single source of truth shared with the image build).
cuda_image_tag() {
  bash "${IMAGES_DIR}/image-tag.sh"
}

# require_live: skip the test unless KARYON_LIVE_TESTS is set.
# L3/L4 tests (those that need Docker + k3d + a live cluster or GPU) call this
# in setup() so per-commit CI skips them and live verification runs them explicitly.
require_live() {
  if [[ -z "${KARYON_LIVE_TESTS:-}" ]]; then
    skip "live test — set KARYON_LIVE_TESTS=1 to run (requires docker + k3d + GPU for some suites)"
  fi
}

# require_live_destructive: skip unless both KARYON_LIVE_TESTS and KARYON_LIVE_TESTS_DESTRUCTIVE are set.
# Use ONLY for tests that destroy persistent state (e.g., delete-clusters live test).
require_live_destructive() {
  if [[ -z "${KARYON_LIVE_TESTS:-}" || -z "${KARYON_LIVE_TESTS_DESTRUCTIVE:-}" ]]; then
    skip "destructive live test — set KARYON_LIVE_TESTS=1 KARYON_LIVE_TESTS_DESTRUCTIVE=1 to run (tears down k3d clusters)"
  fi
}
