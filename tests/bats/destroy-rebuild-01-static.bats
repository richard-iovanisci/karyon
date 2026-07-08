#!/usr/bin/env bats
# tests/bats/destroy-rebuild-01-static.bats
# Static contract for destructive wrappers and the strict rebuild chain.

load 'test_helper'

setup() {
  DESTROY_SCRIPT="${REPO_ROOT}/scripts/destroy.sh"
  REBUILD_SCRIPT="${REPO_ROOT}/scripts/rebuild.sh"
  TASKFILE="${REPO_ROOT}/Taskfile.yml"
}

@test "DESTROY-01: destroy and rebuild wrappers exist, are strict, and source preflight helpers" {
  [ -f "$DESTROY_SCRIPT" ]
  [ -f "$REBUILD_SCRIPT" ]
  run grep -E '^set -euo pipefail' "$DESTROY_SCRIPT"
  [ "$status" -eq 0 ]
  run grep -E '^set -euo pipefail' "$REBUILD_SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- 'preflight-lib.sh' "$DESTROY_SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- 'preflight-lib.sh' "$REBUILD_SCRIPT"
  [ "$status" -eq 0 ]
}

@test "DESTROY-01: destroy wrapper supports explicit approved path" {
  [ -f "$DESTROY_SCRIPT" ]
  run grep -F -- 'KARYON_DESTROY_APPROVED' "$DESTROY_SCRIPT"
  [ "$status" -eq 0 ]
}

@test "DESTROY-01: destroy wrapper requires typed yes without approval env" {
  [ -f "$DESTROY_SCRIPT" ]
  run grep -F -- 'read -r' "$DESTROY_SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- 'yes' "$DESTROY_SCRIPT"
  [ "$status" -eq 0 ]
}

@test "DESTROY-02: destroy wrapper delegates to cache-preserving delete script through SCRIPT_DIR" {
  [ -f "$DESTROY_SCRIPT" ]
  run grep -F -- 'bash "${SCRIPT_DIR}/delete-clusters.sh"' "$DESTROY_SCRIPT"
  [ "$status" -eq 0 ]
}

@test "DESTROY-05: rebuild wrapper runs the strict script chain in order" {
  [ -f "$REBUILD_SCRIPT" ]
  previous=0
  for literal in \
    'bash "${SCRIPT_DIR}/preflight.sh"' \
    'bash "${SCRIPT_DIR}/destroy.sh"' \
    'bash "${SCRIPT_DIR}/create-clusters.sh"' \
    'bash "${SCRIPT_DIR}/bootstrap-flux.sh"' \
    'bash "${SCRIPT_DIR}/register-spokes-for-flux.sh"' \
    'bash "${SCRIPT_DIR}/deploy-examples.sh"' \
    'bash "${SCRIPT_DIR}/health-check.sh"'
  do
    line="$(grep -nF -- "$literal" "$REBUILD_SCRIPT" | head -1 | cut -d: -f1)"
    [ -n "$line" ]
    [ "$line" -gt "$previous" ]
    previous="$line"
  done
}

@test "DESTROY-05: rebuild runs preflight before the destructive step" {
  [ -f "$REBUILD_SCRIPT" ]
  preflight_line="$(grep -nF -- '>>> step preflight' "$REBUILD_SCRIPT" | head -1 | cut -d: -f1)"
  destroy_line="$(grep -nF -- '>>> step destroy' "$REBUILD_SCRIPT" | head -1 | cut -d: -f1)"
  preflight_cmd_line="$(grep -nF -- 'bash "${SCRIPT_DIR}/preflight.sh"' "$REBUILD_SCRIPT" | head -1 | cut -d: -f1)"
  destroy_cmd_line="$(grep -nF -- 'bash "${SCRIPT_DIR}/destroy.sh"' "$REBUILD_SCRIPT" | head -1 | cut -d: -f1)"
  [ -n "$preflight_line" ]
  [ -n "$destroy_line" ]
  [ -n "$preflight_cmd_line" ]
  [ -n "$destroy_cmd_line" ]
  [ "$preflight_line" -lt "$destroy_line" ]
  [ "$preflight_cmd_line" -lt "$destroy_cmd_line" ]
}

@test "HIGH-1: rebuild repins kubectl context after create-clusters and before bootstrap-flux" {
  [ -f "$REBUILD_SCRIPT" ]
  create_line="$(grep -nF -- 'bash "${SCRIPT_DIR}/create-clusters.sh"' "$REBUILD_SCRIPT" | head -1 | cut -d: -f1)"
  context_line="$(grep -nF -- 'kubectl config use-context k3d-hub-flux' "$REBUILD_SCRIPT" | head -1 | cut -d: -f1)"
  bootstrap_line="$(grep -nF -- 'bash "${SCRIPT_DIR}/bootstrap-flux.sh"' "$REBUILD_SCRIPT" | head -1 | cut -d: -f1)"
  [ -n "$create_line" ]
  [ -n "$context_line" ]
  [ -n "$bootstrap_line" ]
  [ "$create_line" -lt "$context_line" ]
  [ "$context_line" -lt "$bootstrap_line" ]
}

@test "DESTROY-06: rebuild enforces 1200 second timeout as nonzero failure" {
  [ -f "$REBUILD_SCRIPT" ]
  run grep -F -- '1200' "$REBUILD_SCRIPT"
  [ "$status" -eq 0 ]
  run grep -E -- '(exit|return)[[:space:]]+[1-9]' "$REBUILD_SCRIPT"
  [ "$status" -eq 0 ]
}

@test "DESTROY-06: rebuild writes elapsed seconds to the expected log file" {
  [ -f "$REBUILD_SCRIPT" ]
  run grep -F -- 'rebuild elapsed seconds:' "$REBUILD_SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- '/tmp/karyon-rebuild.log' "$REBUILD_SCRIPT"
  [ "$status" -eq 0 ]
}

@test "DESTROY-06: rebuild refuses unsafe log paths before truncating" {
  [ -f "$REBUILD_SCRIPT" ]
  run grep -F -- 'KARYON_REBUILD_LOG_FILE:-/tmp/karyon-rebuild.log' "$REBUILD_SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- '-L "${LOG_FILE}"' "$REBUILD_SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- 'unsafe rebuild log path' "$REBUILD_SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- 'old_umask="$(umask)"' "$REBUILD_SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- 'umask "${old_umask}"' "$REBUILD_SCRIPT"
  [ "$status" -eq 0 ]
  guard_line="$(grep -nF -- 'unsafe rebuild log path' "$REBUILD_SCRIPT" | head -1 | cut -d: -f1)"
  truncate_line="$(grep -nF -- ': > "$LOG_FILE"' "$REBUILD_SCRIPT" | head -1 | cut -d: -f1)"
  restore_line="$(grep -nF -- 'umask "${old_umask}"' "$REBUILD_SCRIPT" | head -1 | cut -d: -f1)"
  [ -n "$guard_line" ]
  [ -n "$truncate_line" ]
  [ -n "$restore_line" ]
  [ "$guard_line" -lt "$truncate_line" ]
  [ "$truncate_line" -lt "$restore_line" ]
}

@test "DESTROY-05: rebuild step markers appear in strict order" {
  [ -f "$REBUILD_SCRIPT" ]
  previous=0
  for literal in \
    '>>> step preflight' \
    '>>> step destroy' \
    '>>> step create-clusters' \
    '>>> step bootstrap-flux' \
    '>>> step register-spokes' \
    '>>> step deploy-examples' \
    '>>> step health-check'
  do
    line="$(grep -nF -- "$literal" "$REBUILD_SCRIPT" | head -1 | cut -d: -f1)"
    [ -n "$line" ]
    [ "$line" -gt "$previous" ]
    previous="$line"
  done
}

@test "DESTROY-04 lint: comment-aware prune rejection" {
  run bash -c '
    violation=0
    while IFS= read -r f; do
      if grep -v "^[[:space:]]*#" "$f" \
        | grep -v "^[[:space:]]*Audit:" \
        | grep -v "^[[:space:]]*Rebuild:" \
        | grep -E "docker (system|builder|image) prune"; then
        echo "VIOLATION in $f" >&2
        violation=1
      fi
    done < <(find scripts -type f -name "*.sh" | sort)
    exit "$violation"
  '
  [ "$status" -eq 0 ]
}

@test "DESTROY-04: destroy and rebuild wrappers contain zero prune literals even without comment filtering" {
  [ -f "$DESTROY_SCRIPT" ]
  [ -f "$REBUILD_SCRIPT" ]
  for f in "$DESTROY_SCRIPT" "$REBUILD_SCRIPT"; do
    if grep -E 'docker (system|builder|image) prune' "$f"; then
      return 1
    fi
  done
}

@test "DESTROY-03/04: destroy and rebuild wrappers do not execute docker system prune" {
  [ -f "$DESTROY_SCRIPT" ]
  [ -f "$REBUILD_SCRIPT" ]
  for f in "$DESTROY_SCRIPT" "$REBUILD_SCRIPT"; do
    run bash -c "grep -v '^[[:space:]]*#' '$f' | grep -F -- 'docker system prune'"
    [ "$status" -ne 0 ]
  done
}

@test "DESTROY-03/04: destroy and rebuild wrappers do not execute docker builder prune" {
  [ -f "$DESTROY_SCRIPT" ]
  [ -f "$REBUILD_SCRIPT" ]
  for f in "$DESTROY_SCRIPT" "$REBUILD_SCRIPT"; do
    run bash -c "grep -v '^[[:space:]]*#' '$f' | grep -F -- 'docker builder prune'"
    [ "$status" -ne 0 ]
  done
}

@test "DESTROY-03/04: destroy and rebuild wrappers do not execute docker image prune" {
  [ -f "$DESTROY_SCRIPT" ]
  [ -f "$REBUILD_SCRIPT" ]
  for f in "$DESTROY_SCRIPT" "$REBUILD_SCRIPT"; do
    run bash -c "grep -v '^[[:space:]]*#' '$f' | grep -F -- 'docker image prune'"
    [ "$status" -ne 0 ]
  done
}

@test "REPO-05: Taskfile wires destroy and rebuild tasks" {
  [ -f "$TASKFILE" ]
  run grep -F -- 'destroy:' "$TASKFILE"
  [ "$status" -eq 0 ]
  run grep -F -- 'rebuild:' "$TASKFILE"
  [ "$status" -eq 0 ]
}
