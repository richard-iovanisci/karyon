#!/usr/bin/env bats
# tests/bats/repo-hygiene-03-ci.bats
# Static contract: .github/workflows/ci.yml has
# 5 required job names + fetch-depth: 0 in the gitleaks job + datreeio CRDs
# catalog reference for kubeconform + every uses: pinned to a 40-char SHA.

load 'test_helper'

setup() {
  CI_FILE="${REPO_ROOT}/.github/workflows/ci.yml"
}

@test "REPO-07: .github/workflows/ci.yml exists with correct top-level shape" {
  [ -f "$CI_FILE" ]
  run grep -E '^name: CI' "$CI_FILE"
  [ "$status" -eq 0 ]
  run grep -F -- 'pull_request:' "$CI_FILE"
  [ "$status" -eq 0 ]
  run grep -F -- 'permissions:' "$CI_FILE"
  [ "$status" -eq 0 ]
  run grep -F -- 'contents: read' "$CI_FILE"
  [ "$status" -eq 0 ]
}

@test "REPO-07 (D-09): all five required jobs present" {
  [ -f "$CI_FILE" ]
  for literal in \
    'shellcheck:' \
    'markdownlint:' \
    'kubeconform:' \
    'prune-lint-bats:' \
    'gitleaks-scan:'
  do
    run grep -F -- "$literal" "$CI_FILE"
    [ "$status" -eq 0 ]
  done
}

@test "REPO-07 (Pitfall 3 / T-06-PAT-01): gitleaks job uses fetch-depth: 0" {
  [ -f "$CI_FILE" ]
  run bash -c "awk '/gitleaks-scan:/{flag=1} flag' '$CI_FILE' | grep -F 'fetch-depth: 0'"
  [ "$status" -eq 0 ]
}

@test "REPO-07 (D-12): prune-lint-bats job runs the existing destroy-rebuild-01-static.bats" {
  [ -f "$CI_FILE" ]
  run grep -F -- 'bats tests/bats/destroy-rebuild-01-static.bats' "$CI_FILE"
  [ "$status" -eq 0 ]
}

@test "REPO-07 (D-10): kubeconform schema-location includes the datreeio CRDs catalog" {
  [ -f "$CI_FILE" ]
  run grep -F -- 'datreeio/CRDs-catalog' "$CI_FILE"
  [ "$status" -eq 0 ]
  run grep -F -- '{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' "$CI_FILE"
  [ "$status" -eq 0 ]
}

@test "REPO-07 (T-06-CI-01): all uses: lines pin to a 40-character commit SHA" {
  [ -f "$CI_FILE" ]
  run bash -c "grep -E '^[[:space:]]+- uses:' '$CI_FILE' | grep -vE '@[a-f0-9]{40}'"
  [ "$status" -ne 0 ]
}
