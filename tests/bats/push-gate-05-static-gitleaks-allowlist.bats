#!/usr/bin/env bats
# tests/bats/push-gate-05-static-gitleaks-allowlist.bats
# Phase 11 D-11-04-revised -- file-specific path-allowlist for gitleaks (folds Phase 7 carryover todo).
# REVISED 2026-05-05 per reviewer HIGH #3: replaced broad `^\.planning/.*\.md$` regex with
# specific file paths. The broad regex would hide the exact accidental-leak class VAL-05 catches.
# Static @test 1: file-specific literals present in .gitleaks.toml.
# Static @test 2: ASSERT ABSENCE of broad regex (anti-regression).
# Live @test 3: full-tree gitleaks scan exits 0.
# RED until Plan 11-01 lands the .gitleaks.toml edit.

load 'test_helper'

setup() {
  GITLEAKS="${REPO_ROOT}/.gitleaks.toml"
}

@test "D-11-04-revised: .gitleaks.toml [allowlist] paths contains file-specific Phase 7 + 10 fixture-bearing markdown patterns" {
  [ -f "$GITLEAKS" ]
  # Each Phase 7 + Phase 10 fixture-bearing markdown file MUST appear as a specific allowlist entry.
  # The verified leak-bearing files (grep -l 'kind: Config' as of 2026-05-05) were:
  #   .planning/phases/07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc/{07-00-PLAN, 07-RESEARCH, 07-REVIEW, 07-PATTERNS}.md
  #   .planning/phases/10-tenant-owner-kubeconfigs-capsule-proxy-round-trip/{10-00-PLAN, 10-REVIEW, 10-PATTERNS}.md
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

@test "D-11-04-revised: .gitleaks.toml does NOT contain the overly broad '^\\.planning/.*\\.md\$' regex (anti-regression per reviewer HIGH #3)" {
  [ -f "$GITLEAKS" ]
  # The original D-11-04 used a broad regex that allowlisted EVERY markdown file under .planning/.
  # The revised D-11-04 uses file-specific paths instead. This @test prevents accidental
  # re-introduction of the broad regex.
  if grep -F -- '^\.planning/.*\.md$' "$GITLEAKS"; then
    echo "ANTI-REGRESSION: broad '^\.planning/.*\.md\$' regex found in .gitleaks.toml; reviewer HIGH #3 rejected this pattern. Use file-specific paths instead."
    return 1
  fi
}

@test "D-11-04 live: gitleaks detect on full working tree exits 0 (zero findings)" {
  cd "$REPO_ROOT"
  if ! command -v gitleaks >/dev/null 2>&1; then
    skip "gitleaks not installed; skipping live scan"
  fi
  run gitleaks detect --no-banner --no-git --source . --config "$REPO_ROOT/.gitleaks.toml" --redact
  [ "$status" -eq 0 ]
}
