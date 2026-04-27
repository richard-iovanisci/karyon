#!/usr/bin/env bash
# scripts/verify-flux-bootstrap-live.sh
# Runs the Phase 03 live/destructive Flux bootstrap idempotency proof.
#
# This mutates the real k3d-hub-flux cluster and may push bootstrap commits to
# the configured GitHub repository through `flux bootstrap github`.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

readonly FLUX_PATH="clusters/hub-flux"
readonly KUBE_CTX="k3d-hub-flux"
readonly FLUX_NS="flux-system"
readonly KUST_FILE="${REPO_ROOT}/${FLUX_PATH}/${FLUX_NS}/kustomization.yaml"

TAP_OUT="${KARYON_03_06_TAP_OUT:-}"
ASSUME_YES=0
PRECHECK_ONLY=0

usage() {
  cat <<'EOF'
Usage: bash scripts/verify-flux-bootstrap-live.sh [--yes] [--precheck-only] [--tap-out PATH]

Runs the Phase 03 live/destructive Flux bootstrap proof:
  1. Checks the local Flux path is clean before bootstrap can pull origin/main.
  2. Checks .env contains GITHUB_OWNER, GITHUB_REPO, and GITHUB_TOKEN without printing values.
  3. Checks kubectl is pointed at k3d-hub-flux and the hub-flux k3d cluster exists.
  4. Runs the live destructive Bats proof with both gates set.
  5. Prints marker and Flux readiness evidence for the GSD checkpoint.

Options:
  --yes              Skip the interactive confirmation prompt.
  --precheck-only    Run only the safe precondition checks, then exit.
  --tap-out PATH     Write TAP output to PATH instead of a generated /tmp/karyon-03-06-live.*.tap file.
  -h, --help         Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes)
      ASSUME_YES=1
      shift
      ;;
    --precheck-only)
      PRECHECK_ONLY=1
      shift
      ;;
    --tap-out)
      if [[ $# -lt 2 || -z "$2" ]]; then
        echo "ERROR: --tap-out requires a path" >&2
        exit 2
      fi
      TAP_OUT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

section() {
  printf "\n== %s ==\n" "$1"
}

pass() {
  printf "PASS: %s\n" "$1"
}

fail() {
  printf "FAIL: %s\n" "$1" >&2
  exit 1
}

need() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

if [[ -z "$TAP_OUT" ]]; then
  TAP_OUT="$(mktemp -t karyon-03-06-live.XXXXXX.tap)"
fi

env_value_present() {
  local key="$1" raw val first last

  raw="$(grep -E "^${key}=" "${REPO_ROOT}/.env" 2>/dev/null | tail -n1 | cut -d= -f2- || true)"
  val="${raw}"

  if [[ ${#val} -ge 2 ]]; then
    first="${val:0:1}"
    last="${val: -1}"
    if [[ "$first" == "$last" && ( "$first" == "'" || "$first" == '"' ) ]]; then
      val="${val:1:${#val}-2}"
    fi
  fi

  [[ -n "$val" ]]
}

env_value() {
  local key="$1" raw val first last
  raw="$(grep -E "^${key}=" "${REPO_ROOT}/.env" 2>/dev/null | tail -n1 | cut -d= -f2- || true)"
  val="${raw}"

  if [[ ${#val} -ge 2 ]]; then
    first="${val:0:1}"
    last="${val: -1}"
    if [[ "$first" == "$last" && ( "$first" == "'" || "$first" == '"' ) ]]; then
      val="${val:1:${#val}-2}"
    fi
  fi

  printf '%s\n' "$val"
}

check_commands() {
  section "Tool checks"
  need git
  need grep
  need head
  need tee
  need bats
  need kubectl
  need k3d
  need flux
  pass "required commands are present"
}

check_flux_path_clean() {
  section "Flux path worktree check"
  if ! git -C "${REPO_ROOT}" diff --quiet -- "${FLUX_PATH}" 2>/dev/null; then
    git -C "${REPO_ROOT}" status --short -- "${FLUX_PATH}" >&2 || true
    fail "${FLUX_PATH}/ has unstaged changes. Commit or stash them before running this proof."
  fi
  if ! git -C "${REPO_ROOT}" diff --cached --quiet -- "${FLUX_PATH}" 2>/dev/null; then
    git -C "${REPO_ROOT}" status --short -- "${FLUX_PATH}" >&2 || true
    fail "${FLUX_PATH}/ has staged changes. Commit or unstage/stash them before running this proof."
  fi

  local untracked
  untracked="$(git -C "${REPO_ROOT}" ls-files --others --exclude-standard -- "${FLUX_PATH}" 2>/dev/null || true)"
  if [[ -n "$untracked" ]]; then
    printf "%s\n" "$untracked" >&2
    fail "${FLUX_PATH}/ has untracked files. Commit, stash, or remove them before running this proof."
  fi

  pass "WORKTREE_CLEAN_UNDER_FLUX_PATH=YES"
}

check_origin_main_fast_forwardable() {
  if [[ -f "$KUST_FILE" ]]; then
    pass "bootstrap manifests already present locally; origin/main fast-forward precheck not needed"
    return 0
  fi

  section "Bootstrap branch sync check"
  if ! git -C "${REPO_ROOT}" fetch origin main >/dev/null 2>&1; then
    fail "could not fetch origin/main. Verify network access and that origin points at the GitHub repo in .env."
  fi
  if ! git -C "${REPO_ROOT}" merge-base --is-ancestor HEAD origin/main; then
    fail "local main has commits that are not on origin/main. Push local main first, or merge/rebase origin/main locally, before running the destructive proof."
  fi
  pass "local main can fast-forward from origin/main after Flux writes bootstrap manifests"
}

check_origin_matches_env_repo() {
  local owner repo expected_slug url
  owner="$(env_value GITHUB_OWNER)"
  repo="$(env_value GITHUB_REPO)"
  expected_slug="${owner}/${repo}"
  url="$(git -C "${REPO_ROOT}" remote get-url origin 2>/dev/null || true)"
  case "${url}" in
    "git@github.com:${expected_slug}.git"|"https://github.com/${expected_slug}.git"|"https://github.com/${expected_slug}")
      pass "git origin matches GITHUB_OWNER/GITHUB_REPO"
      return 0
      ;;
  esac
  fail "git origin does not match GITHUB_OWNER/GITHUB_REPO from .env; update origin or .env before running the destructive proof"
}

check_env_file() {
  section ".env presence check"
  [[ -f "${REPO_ROOT}/.env" ]] || fail ".env not found at ${REPO_ROOT}/.env"

  local key missing=0
  for key in GITHUB_OWNER GITHUB_REPO GITHUB_TOKEN; do
    if env_value_present "$key"; then
      printf "%s=PRESENT\n" "$key"
    else
      printf "%s=MISSING\n" "$key" >&2
      missing=1
    fi
  done

  [[ "$missing" -eq 0 ]] || fail ".env is missing one or more required non-empty GitHub keys"
  pass ".env keys are present; values were not printed"
}

check_cluster_context() {
  section "Cluster context check"

  local ctx
  ctx="$(kubectl config current-context 2>/dev/null || true)"
  printf "kubectl current-context: %s\n" "${ctx:-unset}"
  [[ "$ctx" == "$KUBE_CTX" ]] || fail "kubectl context must be ${KUBE_CTX}"

  local cluster_line
  cluster_line="$(k3d cluster list 2>/dev/null | grep -F hub-flux || true)"
  [[ -n "$cluster_line" ]] || fail "k3d cluster list does not show hub-flux"
  printf "%s\n" "$cluster_line"
  pass "hub-flux cluster is visible"
}

confirm_destructive_run() {
  if [[ "$ASSUME_YES" -eq 1 ]]; then
    return 0
  fi

  if [[ ! -t 0 ]]; then
    fail "interactive confirmation required; rerun with --yes after reviewing this script"
  fi

  section "Destructive confirmation"
  cat <<EOF
This will run the live/destructive Bats proof with:
  KARYON_LIVE_TESTS=1
  KARYON_LIVE_TESTS_DESTRUCTIVE=1

It can mutate the real ${KUBE_CTX} cluster and trigger Flux bootstrap GitHub writes.
EOF
  printf "Type RUN LIVE PROOF to continue: "
  local reply
  read -r reply
  [[ "$reply" == "RUN LIVE PROOF" ]] || fail "confirmation did not match; aborting"
}

run_live_bats() {
  section "Live destructive Bats proof"
  mkdir -p "$(dirname "$TAP_OUT")"
  rm -f "$TAP_OUT"
  local live_line_re='^ok [0-9]+ FLUX-04 \+ D-13 \(live/destructive, combined\)'

  (
    cd "$REPO_ROOT"
    KARYON_LIVE_TESTS=1 KARYON_LIVE_TESTS_DESTRUCTIVE=1 \
      bats tests/bats/bootstrap-flux-01-idempotent.bats --tap | tee "$TAP_OUT"
  )

  if grep -E "$live_line_re" "$TAP_OUT" | grep -qF "# skip"; then
    fail "live/destructive test was skipped; expected it to run with both gates set"
  fi
  grep -E "$live_line_re" "$TAP_OUT" >/dev/null \
    || fail "TAP output did not contain the required live/destructive proof line"
  if grep -q "^not ok" "$TAP_OUT"; then
    fail "TAP output contains failing tests; see ${TAP_OUT}"
  fi

  pass "live/destructive Bats proof passed; TAP saved to ${TAP_OUT}"
}

print_supporting_evidence() {
  section "Patch-surface marker evidence"
  [[ -f "$KUST_FILE" ]] || fail "expected kustomization not found: ${KUST_FILE}"
  head -3 "$KUST_FILE"
  grep -F "# FLUX PATCH SURFACE" "$KUST_FILE" >/dev/null \
    || fail "patch-surface marker not found in ${KUST_FILE}"

  section "Flux readiness evidence"
  flux --context "$KUBE_CTX" check
  flux --context "$KUBE_CTX" get kustomizations -A

  section "Checkpoint resume text"
  cat <<EOF
approved - TAP shows the FLUX-04 + D-13 live/destructive proof passed and all preconditions passed

Paste the full contents of:
  ${TAP_OUT}

Also paste the Patch-surface marker evidence and Flux readiness evidence printed above.
EOF
}

check_commands
check_flux_path_clean
check_env_file
check_origin_matches_env_repo
check_origin_main_fast_forwardable
check_cluster_context

if [[ "$PRECHECK_ONLY" -eq 1 ]]; then
  section "Precheck complete"
  pass "safe preconditions passed; live destructive proof was not run"
  exit 0
fi

confirm_destructive_run
run_live_bats
print_supporting_evidence
