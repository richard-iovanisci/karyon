#!/usr/bin/env bats
# tests/bats/preflight-pre01.bats
# Unit tests for PRE-01: WSL2 kernel detection via preflight_check_wsl_kernel().
# Calls the real library function; mocks uname output via a local override.

load 'test_helper'

@test "PRE-01: WSL2 kernel passes preflight_check_wsl_kernel" {
  run bash -c "
    source '${SCRIPTS_DIR}/lib/preflight-lib.sh'
    uname() { echo '5.15.153.1-microsoft-standard-WSL2'; }
    preflight_check_wsl_kernel
  "
  [ "$status" -eq 0 ]
  [[ "$output" =~ "WSL2 kernel detected" ]]
}

@test "PRE-01: non-WSL kernel fails preflight_check_wsl_kernel" {
  run bash -c "
    source '${SCRIPTS_DIR}/lib/preflight-lib.sh'
    uname() { echo '5.15.0-91-generic'; }
    preflight_check_wsl_kernel
  "
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Not running on a WSL2 kernel" ]]
}

@test "PRE-01: WSL1 kernel (microsoft but no WSL2 suffix) fails" {
  run bash -c "
    source '${SCRIPTS_DIR}/lib/preflight-lib.sh'
    uname() { echo '4.4.0-19041-Microsoft'; }
    preflight_check_wsl_kernel
  "
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Not running on a WSL2 kernel" ]]
}

@test "PRE-01: pass() helper increments PASS counter" {
  PASS=0
  pass "test message"
  [ "$PASS" -eq 1 ]
}

@test "PRE-01: fail() helper increments FAIL counter" {
  FAIL=0
  fail "test message"
  [ "$FAIL" -eq 1 ]
}
