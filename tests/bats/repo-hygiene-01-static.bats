#!/usr/bin/env bats
# tests/bats/repo-hygiene-01-static.bats
# Repo hygiene contracts: .gitignore secret-material globs, the .env.example
# template shape, and the gitleaks pre-commit hook.

load 'test_helper'

setup() {
  GITIGNORE="${REPO_ROOT}/.gitignore"
  ENVEXAMPLE="${REPO_ROOT}/.env.example"
  HOOK="${REPO_ROOT}/hooks/pre-commit"
  GITLEAKS_TOML="${REPO_ROOT}/.gitleaks.toml"
}

@test ".gitignore carries the secret-material and IDE-noise globs" {
  [ -f "$GITIGNORE" ]
  for literal in \
    '.env' \
    'kubeconfig' \
    '*.kubeconfig' \
    '*.pem' \
    '*.key' \
    '*.crt' \
    'flux-system/identity*' \
    '.DS_Store' \
    '*.swp' \
    '.idea/' \
    '.vscode/'
  do
    run grep -F -- "$literal" "$GITIGNORE"
    [ "$status" -eq 0 ]
  done
}

@test ".env.example documents all three required keys with placeholder values" {
  [ -f "$ENVEXAMPLE" ]
  for literal in \
    'GITHUB_OWNER=' \
    'GITHUB_REPO=' \
    'GITHUB_TOKEN=' \
    'ghp_REPLACE_WITH_PAT_WITH_repo_SCOPE'
  do
    run grep -F -- "$literal" "$ENVEXAMPLE"
    [ "$status" -eq 0 ]
  done
}

@test "hooks/pre-commit exists and is executable bash with strict mode + preflight-lib sourcing" {
  [ -f "$HOOK" ]
  [ -x "$HOOK" ]
  run grep -E '^#!/usr/bin/env bash' "$HOOK"
  [ "$status" -eq 0 ]
  run grep -E '^set -euo pipefail' "$HOOK"
  [ "$status" -eq 0 ]
  run grep -F -- 'preflight-lib.sh' "$HOOK"
  [ "$status" -eq 0 ]
}

@test "hooks/pre-commit invokes the canonical gitleaks subcommand" {
  [ -f "$HOOK" ]
  run grep -F -- 'gitleaks git --pre-commit' "$HOOK"
  [ "$status" -eq 0 ]
  run grep -F -- '--redact' "$HOOK"
  [ "$status" -eq 0 ]
  run grep -F -- '--staged' "$HOOK"
  [ "$status" -eq 0 ]
  run grep -F -- '--verbose' "$HOOK"
  [ "$status" -eq 0 ]
}

@test "hooks/pre-commit gates on gitleaks presence with remediation message" {
  [ -f "$HOOK" ]
  run grep -F -- 'have gitleaks' "$HOOK"
  [ "$status" -eq 0 ]
  run grep -F -- 'install-tools.sh' "$HOOK"
  [ "$status" -eq 0 ]
}

@test ".gitleaks.toml exists with allow-rules for placeholders" {
  [ -f "$GITLEAKS_TOML" ]
  run grep -F -- '[allowlist]' "$GITLEAKS_TOML"
  [ "$status" -eq 0 ]
  run grep -F -- 'ghp_REPLACE_WITH_PAT_WITH_repo_SCOPE' "$GITLEAKS_TOML"
  [ "$status" -eq 0 ]
  run grep -F -- '\.env\.example' "$GITLEAKS_TOML"
  [ "$status" -eq 0 ]
}
