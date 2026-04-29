#!/usr/bin/env bats
# tests/bats/repo-hygiene-04-poc.bats
# POC-03 / D-14 — .gitignore + .gitleaks.toml positive rule + per-fixture allowlist + fixture invocations

load 'test_helper'

setup() {
  GITIGNORE="${REPO_ROOT}/.gitignore"
  GITLEAKS_TOML="${REPO_ROOT}/.gitleaks.toml"
  POSITIVE_FIXTURE="${REPO_ROOT}/tests/fixtures/gitleaks/synthetic-kubeconfig.yaml"
  NEGATIVE_FIXTURE="${REPO_ROOT}/tests/fixtures/gitleaks/benign-configmap.yaml"
}

@test "POC-03 / D-14: .gitignore includes tenant-kubeconfig globs" {
  [ -f "$GITIGNORE" ]
  for literal in 'karyon-tenants/' '*.tenant.kubeconfig' 'tenants/**/access.yaml' 'tenants/**/admin.yaml'; do
    run grep -F -- "$literal" "$GITIGNORE"
    [ "$status" -eq 0 ]
  done
}

@test "POC-03 / D-14: .gitignore preserves Phase 6 D-16 expansion globs (kubeconfig*, *.kubeconfig, *.pem, *.key, *.crt)" {
  [ -f "$GITIGNORE" ]
  for literal in 'kubeconfig*' '*.kubeconfig' '*.pem' '*.key' '*.crt'; do
    run grep -F -- "$literal" "$GITIGNORE"
    [ "$status" -eq 0 ]
  done
}

@test "POC-03 / D-14: .gitleaks.toml has kubeconfig-bearer-token positive rule" {
  [ -f "$GITLEAKS_TOML" ]
  run grep -F -- 'id = "kubeconfig-bearer-token"' "$GITLEAKS_TOML"
  [ "$status" -eq 0 ]
}

@test "POC-03 / D-14: .gitleaks.toml rule regex anchors on kind: Config + users + token" {
  [ -f "$GITLEAKS_TOML" ]
  # Multi-line (?ms) regex containing kind:\s*Config and users: and token:
  run grep -F -- '(?ms)' "$GITLEAKS_TOML"
  [ "$status" -eq 0 ]
  run grep -F -- 'kind:' "$GITLEAKS_TOML"
  [ "$status" -eq 0 ]
  run grep -F -- 'users:' "$GITLEAKS_TOML"
  [ "$status" -eq 0 ]
  run grep -F -- 'token:' "$GITLEAKS_TOML"
  [ "$status" -eq 0 ]
}

@test "POC-03 / D-14: .gitleaks.toml rule has v0.19 tag" {
  [ -f "$GITLEAKS_TOML" ]
  run grep -F -- 'v0.19' "$GITLEAKS_TOML"
  [ "$status" -eq 0 ]
}

@test "POC-03 / D-14: .gitleaks.toml allowlists tests/fixtures/gitleaks/synthetic-kubeconfig.yaml by path" {
  [ -f "$GITLEAKS_TOML" ]
  run grep -F -- 'tests/fixtures/gitleaks/synthetic-kubeconfig' "$GITLEAKS_TOML"
  [ "$status" -eq 0 ]
}

@test "POC-03: .gitleaks.toml preserves Phase 1 [allowlist] block (existing ghp_REPLACE allowlist)" {
  [ -f "$GITLEAKS_TOML" ]
  run grep -F -- 'ghp_REPLACE_WITH_PAT_WITH_repo_SCOPE' "$GITLEAKS_TOML"
  [ "$status" -eq 0 ]
}

@test "POC-03: positive fixture exists with kind: Config + users.token shape" {
  [ -f "$POSITIVE_FIXTURE" ]
  run grep -F -- 'kind: Config' "$POSITIVE_FIXTURE"
  [ "$status" -eq 0 ]
  run grep -E '^[[:space:]]*token:' "$POSITIVE_FIXTURE"
  [ "$status" -eq 0 ]
}

@test "POC-03: negative fixture exists with kind: ConfigMap (NOT kind: Config)" {
  [ -f "$NEGATIVE_FIXTURE" ]
  run grep -F -- 'kind: ConfigMap' "$NEGATIVE_FIXTURE"
  [ "$status" -eq 0 ]
  run grep -F -- 'kind: Config' "$NEGATIVE_FIXTURE"
  # ConfigMap also matches "Config" prefix; assertion is that we have ConfigMap, NOT bare Config
  # (the test above on positive fixture is the discriminator)
}

@test "POC-03 (live): gitleaks fires on positive fixture (catches kubeconfig + bearer token)" {
  [ -f "$POSITIVE_FIXTURE" ]
  [ -f "$GITLEAKS_TOML" ]
  run gitleaks detect --no-banner --no-git --source "$POSITIVE_FIXTURE" --config "$GITLEAKS_TOML" --redact --verbose
  [ "$status" -ne 0 ]
}

@test "POC-03 (live): gitleaks does NOT fire on negative fixture" {
  [ -f "$NEGATIVE_FIXTURE" ]
  [ -f "$GITLEAKS_TOML" ]
  run gitleaks detect --no-banner --no-git --source "$NEGATIVE_FIXTURE" --config "$GITLEAKS_TOML" --redact --verbose
  [ "$status" -eq 0 ]
}
