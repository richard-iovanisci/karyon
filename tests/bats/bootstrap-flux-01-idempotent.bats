#!/usr/bin/env bats
# tests/bats/bootstrap-flux-01-idempotent.bats
# Multi-part check for scripts/bootstrap-flux.sh:
#   - static-grep that scripts/bootstrap-flux.sh invokes `flux bootstrap github`,
#   - static-grep that --path is hard-coded to clusters/hub-flux (no env override),
#   - static-grep that the script uses `set -euo pipefail` and does NOT contain `set -x`
#     (token safety — trace mode would echo the GitHub token),
#   - static-grep that GITHUB_TOKEN is never funneled through echo/printf/pass/info/warn/fail/tee
#     (broadened negative grep - catches printf-leak and helper-funnel as well as the obvious echo/tee paths),
#   - static-grep that the idempotency skip-message literal is present,
#   - static-grep that the FLUX PATCH SURFACE sentinel literal is present,
#   - static-grep that the gitleaks pre-commit advisory section exists in the script
#     (a warn-only section; this @test pins the section sentinel),
#   - L3 live-destructive (COMBINED): run bootstrap -> assert exit 0 + sentinel reaches kustomization.yaml,
#     run a SECOND time -> assert exit 0 + skip-message present + sentinel STILL present.

load 'test_helper'

setup() {
  # 2026-04-26: contract reviewed against the current script; all live/destructive assertions hold without modification.
  SCRIPT="${REPO_ROOT}/scripts/bootstrap-flux.sh"
}

teardown() {
  :
}

# ---- Static @tests (no live gate; always run) ----

@test "FLUX-01: scripts/bootstrap-flux.sh invokes flux bootstrap github" {
  [ -f "$SCRIPT" ]
  run grep -F -- 'flux bootstrap github' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "FLUX-02: scripts/bootstrap-flux.sh hard-codes --path clusters/hub-flux (no env override)" {
  [ -f "$SCRIPT" ]
  # Positive: the hard-coded path appears as a literal in the script.
  run grep -F -- 'clusters/hub-flux' "$SCRIPT"
  [ "$status" -eq 0 ]
  # Negative: no FLUX_PATH="${FLUX_PATH:-...}" env-override pattern.
  run grep -E 'FLUX_PATH=\"\$\{FLUX_PATH:?-' "$SCRIPT"
  [ "$status" -ne 0 ]
}

@test "FLUX-03 / D-11: scripts/bootstrap-flux.sh uses set -euo pipefail and does NOT use set -x" {
  [ -f "$SCRIPT" ]
  # Positive: strict mode line present.
  run grep -E '^set -euo pipefail' "$SCRIPT"
  [ "$status" -eq 0 ]
  # Negative: no `set -x` (or `set -eux`, `set -xe`, etc.) - trace mode would leak the token.
  # Filter comments first to avoid self-invalidating grep gate.
  run bash -c "grep -v '^[[:space:]]*#' '$SCRIPT' | grep -E '^[[:space:]]*set[[:space:]]+-[a-zA-Z]*x'"
  [ "$status" -ne 0 ]
}

@test "FLUX-03 / D-11 (token safety, broadened): \$GITHUB_TOKEN never funneled through echo/printf/pass/info/warn/fail/tee" {
  [ -f "$SCRIPT" ]
  # Single combined negative-grep - catches:
  #   - `echo "$GITHUB_TOKEN"` (any quoting)         -> echo[[:space:]]+.*GITHUB_TOKEN
  #   - `printf '%s' "$GITHUB_TOKEN"`                -> printf[[:space:]]+.*GITHUB_TOKEN
  #   - `pass|info|warn|fail "...$GITHUB_TOKEN..."`  -> ^[[:space:]]*(pass|info|warn|fail)[[:space:]]+.*GITHUB_TOKEN
  #   - `tee` (in any role; flux bootstrap output capture forbidden)  -> tee[[:space:]]+
  # Filter comments first so the header prose / threat-model can mention these names without false-failing.
  run bash -c "grep -v '^[[:space:]]*#' '$SCRIPT' | grep -E '(echo|printf)[[:space:]]+.*GITHUB_TOKEN|^[[:space:]]*(pass|info|warn|fail)[[:space:]]+.*GITHUB_TOKEN|tee[[:space:]]+'"
  [ "$status" -ne 0 ]
}

@test "D-07 / FLUX-04: scripts/bootstrap-flux.sh contains the exact skip-message literal" {
  [ -f "$SCRIPT" ]
  # This is the literal string the live rerun @test below asserts in stdout on run 2.
  # ANY drift breaks the test contract. Must match EXACTLY.
  run grep -F -- 'already done, skipping: flux bootstrap' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "D-13: scripts/bootstrap-flux.sh carries the FLUX PATCH SURFACE sentinel literal" {
  [ -f "$SCRIPT" ]
  # Script must contain both the sentinel-guard grep AND the heredoc/cat block that prepends the marker.
  run grep -F -- '# FLUX PATCH SURFACE' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "Phase-6 hand-off: scripts/bootstrap-flux.sh contains the gitleaks pre-commit advisory section" {
  [ -f "$SCRIPT" ]
  # The script includes a warn-only check for
  # `.git/hooks/pre-commit` referencing gitleaks. This @test pins that the section
  # exists in the script so a future edit cannot silently remove the advisory.
  # Match either of two acceptable sentinels: the literal `.git/hooks/pre-commit`
  # path used in the file-existence check, OR the `Gitleaks pre-commit advisory`
  # section header. Either presence is sufficient to prove the advisory section is wired.
  run bash -c "grep -F -- '.git/hooks/pre-commit' '$SCRIPT' || grep -iF -- 'gitleaks pre-commit advisory' '$SCRIPT'"
  [ "$status" -eq 0 ]
}

# ---- Live/destructive @test (require KARYON_LIVE_TESTS=1 KARYON_LIVE_TESTS_DESTRUCTIVE=1) ----

# WARNING: Runs scripts/bootstrap-flux.sh TWICE, creates/updates the GitHub repo, and writes files
# under clusters/hub-flux/flux-system/. Requires valid .env with GITHUB_TOKEN.
#
# COMBINED @test: a single self-contained run covers BOTH the idempotency
# rerun invariant AND the marker survival invariant. No cross-@test state coupling.
@test "flux bootstrap rerun is idempotent (live/destructive, combined): exit 0 twice AND patch-surface marker survives re-run" {
  require_live_destructive
  [ -f "$SCRIPT" ]
  KUST="${REPO_ROOT}/clusters/hub-flux/flux-system/kustomization.yaml"

  # First run: MUST succeed. (Hard status assertion instead of `|| true` masking so
  # a first-run failure surfaces with the standard bats $status/$output trace.)
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]

  # After first run: the patch-surface marker MUST exist in the bootstrapped kustomization.yaml.
  [ -f "$KUST" ]
  run grep -F -- '# FLUX PATCH SURFACE' "$KUST"
  [ "$status" -eq 0 ]

  # Second run: MUST hit the three-part idempotency gate, log the skip message,
  # exit 0 without re-invoking flux bootstrap.
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already done, skipping: flux bootstrap"* ]]

  # After second run: the patch-surface marker MUST still be present.
  run grep -F -- '# FLUX PATCH SURFACE' "$KUST"
  [ "$status" -eq 0 ]
}
