#!/usr/bin/env bats
# tests/bats/preflight-pre11.bats
# Unit tests for 127.0.0.53 stub detection via preflight_check_systemd_resolved().

load 'test_helper'

setup() {
  TEST_TMPDIR="$(mktemp -d)"
  RESOLV_FILE="${TEST_TMPDIR}/resolv.conf"
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

@test "PRE-11: 127.0.0.53 nameserver fails preflight_check_systemd_resolved" {
  echo 'nameserver 127.0.0.53' > "$RESOLV_FILE"
  run preflight_check_systemd_resolved "$RESOLV_FILE"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "127.0.0.53 stub detected" ]]
}

@test "PRE-11: real nameserver passes preflight_check_systemd_resolved" {
  echo 'nameserver 1.1.1.1' > "$RESOLV_FILE"
  run preflight_check_systemd_resolved "$RESOLV_FILE"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "not 127.0.0.53 stub" ]]
}

@test "PRE-11: 127.0.0.1 is not flagged (different loopback)" {
  echo 'nameserver 127.0.0.1' > "$RESOLV_FILE"
  run preflight_check_systemd_resolved "$RESOLV_FILE"
  [ "$status" -eq 0 ]
}

@test "PRE-11: comment line with 127.0.0.53 not matched" {
  echo '# nameserver 127.0.0.53' > "$RESOLV_FILE"
  run preflight_check_systemd_resolved "$RESOLV_FILE"
  [ "$status" -eq 0 ]
}

@test "PRE-11: empty resolv.conf passes (no stub present)" {
  touch "$RESOLV_FILE"
  run preflight_check_systemd_resolved "$RESOLV_FILE"
  [ "$status" -eq 0 ]
}
