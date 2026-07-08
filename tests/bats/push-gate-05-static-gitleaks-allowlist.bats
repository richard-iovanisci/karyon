#!/usr/bin/env bats
# tests/bats/push-gate-05-static-gitleaks-allowlist.bats
# Guards the shape of the gitleaks allowlist in .gitleaks.toml.
# The fourteen .planning/... path entries are HISTORY-ONLY: the directory was
# deleted from the working tree (July 2026), but CI scans full git history and
# the fixture-quoting files remain in historical commits at two locations
# (original and archived). Dropping an entry re-flags those blobs and fails CI.
# @test 1: the file-specific literals are present in .gitleaks.toml.
# @test 2: ASSERT ABSENCE of a single broad planning-markdown regex — one
#          broad pattern would hide the accidental-leak class the custom
#          kubeconfig rule exists to catch.
# @test 3 (live): full-tree gitleaks scan exits 0.

load 'test_helper'

setup() {
  GITLEAKS="${REPO_ROOT}/.gitleaks.toml"
}

@test "gitleaks allowlist: history-only file-specific entries for the fixture-quoting planning files are present" {
  [ -f "$GITLEAKS" ]
  # The verified fixture-quoting files (grep -l 'kind: Config', 2026-05-05) —
  # now history-only, at both their original and archived paths:
  for literal in \
    '07-00-PLAN' \
    '07-RESEARCH' \
    '07-REVIEW' \
    '07-PATTERNS' \
    '10-00-PLAN' \
    '10-REVIEW' \
    '10-PATTERNS' ; do
    run grep -F -- "$literal" "$GITLEAKS"
    [ "$status" -eq 0 ]
  done
}

@test "gitleaks allowlist: no broad planning-markdown regex anywhere in the file (anti-regression)" {
  [ -f "$GITLEAKS" ]
  # A single regex covering every markdown file under the old planning tree
  # was rejected because it would allowlist future accidental leaks wholesale.
  # File-specific paths only. grep -F also catches the literal in comments.
  if grep -F -- '^\.planning/.*\.md$' "$GITLEAKS"; then
    echo "ANTI-REGRESSION: broad planning-markdown regex found in .gitleaks.toml. Use file-specific paths instead."
    return 1
  fi
}

@test "(live) gitleaks detect on full working tree exits 0 (zero findings)" {
  cd "$REPO_ROOT"
  if ! command -v gitleaks >/dev/null 2>&1; then
    skip "gitleaks not installed; skipping live scan"
  fi
  run gitleaks detect --no-banner --no-git --source . --config "$REPO_ROOT/.gitleaks.toml" --redact
  [ "$status" -eq 0 ]
}
