# tests/bats/test_helper.bash
# Shared loader for preflight bats suites.
# Sourced via `load 'test_helper'` in each suite (bats-core convention —
# bats resolves load paths relative to the suite file's directory).

# Resolve scripts dir from bats test filename (works regardless of CWD)
SCRIPTS_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME:-$0}")/../.." && pwd)/scripts"

# Source the preflight helper library so pass()/fail()/warn()/info()/have() and
# preflight_check_*() functions are available in test suites.
# shellcheck source=../../scripts/lib/preflight-lib.sh
# shellcheck disable=SC1091
source "${SCRIPTS_DIR}/lib/preflight-lib.sh"
