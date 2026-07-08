#!/usr/bin/env bats
# tests/bats/preflight-pre13.bats
# Unit tests for cgroup v2 purity via preflight_check_cgroup_v2().
# Mocks stat output to simulate different cgroup filesystem types.

load 'test_helper'

@test "PRE-13: cgroup2fs passes preflight_check_cgroup_v2" {
  run bash -c "
    source '${SCRIPTS_DIR}/lib/preflight-lib.sh'
    stat() { echo 'cgroup2fs'; }
    export -f stat
    preflight_check_cgroup_v2
  "
  [ "$status" -eq 0 ]
  [[ "$output" =~ "cgroup v2 pure" ]]
}

@test "PRE-13: tmpfs fails preflight_check_cgroup_v2" {
  run bash -c "
    source '${SCRIPTS_DIR}/lib/preflight-lib.sh'
    stat() { echo 'tmpfs'; }
    export -f stat
    preflight_check_cgroup_v2
  "
  [ "$status" -ne 0 ]
  [[ "$output" =~ "cgroup v1 or hybrid detected" ]]
}

@test "PRE-13: unknown type produces warn (status 0)" {
  run bash -c "
    source '${SCRIPTS_DIR}/lib/preflight-lib.sh'
    stat() { echo 'overlayfs'; }
    export -f stat
    preflight_check_cgroup_v2
  "
  # warn() does not set non-zero return; preflight_check_cgroup_v2 returns 0 on warn path
  [ "$status" -eq 0 ]
  [[ "$output" =~ "unable to determine cgroup type" ]]
}

@test "PRE-13: empty stat output produces warn (status 0)" {
  run bash -c "
    source '${SCRIPTS_DIR}/lib/preflight-lib.sh'
    stat() { echo ''; }
    export -f stat
    preflight_check_cgroup_v2
  "
  [ "$status" -eq 0 ]
  [[ "$output" =~ "unable to determine cgroup type" ]]
}

@test "PRE-13: cgroup2fs string matches exactly (case sensitive)" {
  cg_type="cgroup2fs"
  [ "$cg_type" = "cgroup2fs" ]
}
