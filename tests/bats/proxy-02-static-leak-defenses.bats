#!/usr/bin/env bats
# tests/bats/proxy-02-static-leak-defenses.bats
# REGRESSION GATE: leak defenses (.gitignore globs + .gitleaks.toml rule + synthetic fixture allowlist).
# The proxy work does NOT modify these files; this bats fails if either is mutated.

load 'test_helper'

setup() {
  GITIGNORE="${REPO_ROOT}/.gitignore"
  GITLEAKS_TOML="${REPO_ROOT}/.gitleaks.toml"
  POSITIVE_FIXTURE="${REPO_ROOT}/tests/fixtures/gitleaks/synthetic-kubeconfig.yaml"
}

@test "PROXY-03 / D-10-09 (Phase 7 D-14 inheritance): .gitignore includes tenant-kubeconfig globs" {
  [ -f "$GITIGNORE" ]
  for literal in 'karyon-tenants/' '*.tenant.kubeconfig' 'tenants/**/access.yaml' 'tenants/**/admin.yaml'; do
    run grep -F -- "$literal" "$GITIGNORE"
    [ "$status" -eq 0 ]
  done
}

@test "PROXY-03 / D-10-09 (Phase 7 D-14 inheritance): .gitleaks.toml has kubeconfig-bearer-token positive rule" {
  [ -f "$GITLEAKS_TOML" ]
  run grep -F -- 'id = "kubeconfig-bearer-token"' "$GITLEAKS_TOML"
  [ "$status" -eq 0 ]
}

@test "PROXY-03 / D-10-09 (Phase 7 D-14 inheritance): .gitleaks.toml allowlists tests/fixtures/gitleaks/synthetic-kubeconfig.yaml by path" {
  [ -f "$GITLEAKS_TOML" ]
  run grep -F -- 'tests/fixtures/gitleaks/synthetic-kubeconfig' "$GITLEAKS_TOML"
  [ "$status" -eq 0 ]
}

@test "PROXY-03 / D-10-09: synthetic-kubeconfig.yaml fixture exists at tests/fixtures/gitleaks/" {
  [ -f "$POSITIVE_FIXTURE" ]
}

@test "PROXY-03 / D-10-09: synthetic fixture contains 'kind: Config' + 'token:' literal pair" {
  [ -f "$POSITIVE_FIXTURE" ]
  run grep -F -- 'kind: Config' "$POSITIVE_FIXTURE"
  [ "$status" -eq 0 ]
  run grep -F -- 'token:' "$POSITIVE_FIXTURE"
  [ "$status" -eq 0 ]
}
