#!/usr/bin/env bats
# tests/bats/preflight-pre09.bats
# Unit tests for PRE-09: .env presence and GITHUB_* key checks via preflight_check_env_file().

load 'test_helper'

setup() {
  TEST_TMPDIR="$(mktemp -d)"
  ENV_FILE="${TEST_TMPDIR}/.env"
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

@test "PRE-09: missing .env file fails preflight_check_env_file" {
  run preflight_check_env_file "${TEST_TMPDIR}/missing.env"
  [ "$status" -ne 0 ]
  [[ "$output" =~ ".env not found" ]]
}

@test "PRE-09: .env with all keys set passes preflight_check_env_file" {
  printf 'GITHUB_OWNER=myuser\nGITHUB_REPO=myrepo\nGITHUB_TOKEN=ghp_abc123\n' > "$ENV_FILE"
  run preflight_check_env_file "$ENV_FILE"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "GITHUB_OWNER is set" ]]
  [[ "$output" =~ "GITHUB_TOKEN is set" ]]
}

@test "PRE-09: .env with empty GITHUB_TOKEN fails" {
  printf 'GITHUB_OWNER=myuser\nGITHUB_REPO=myrepo\nGITHUB_TOKEN=\n' > "$ENV_FILE"
  run preflight_check_env_file "$ENV_FILE"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "GITHUB_TOKEN is missing or empty" ]]
}

@test "PRE-09: .env missing GITHUB_REPO key fails" {
  printf 'GITHUB_OWNER=myuser\nGITHUB_TOKEN=ghp_abc123\n' > "$ENV_FILE"
  run preflight_check_env_file "$ENV_FILE"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "GITHUB_REPO is missing or empty" ]]
}

@test "PRE-09: placeholder token value (non-empty) passes presence check" {
  printf 'GITHUB_OWNER=your-github-username\nGITHUB_REPO=your-repo-name\nGITHUB_TOKEN=ghp_REPLACE_WITH_PAT_WITH_repo_SCOPE\n' > "$ENV_FILE"
  run preflight_check_env_file "$ENV_FILE"
  [ "$status" -eq 0 ]
}

@test "PRE-09: KEY= (empty value) fails" {
  printf 'GITHUB_OWNER=\nGITHUB_REPO=myrepo\nGITHUB_TOKEN=tok\n' > "$ENV_FILE"
  run preflight_check_env_file "$ENV_FILE"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "GITHUB_OWNER is missing or empty" ]]
}
