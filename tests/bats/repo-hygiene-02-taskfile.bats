#!/usr/bin/env bats
# tests/bats/repo-hygiene-02-taskfile.bats
# Phase 6 Wave 0 static contract for REPO-05: Taskfile.yml is a thin wrapper —
# every cmds: entry calls bash scripts/<name>.sh and nothing else; no inline
# kubectl|docker|k3d|flux invocations outside cmds:.

load 'test_helper'

setup() {
  TASKFILE="${REPO_ROOT}/Taskfile.yml"
}

@test "REPO-05: Taskfile.yml exists and lists every Phase 1-5 task" {
  [ -f "$TASKFILE" ]
  for literal in \
    'build-image:' \
    'create-clusters:' \
    'delete-clusters:' \
    'bootstrap-flux:' \
    'register-spokes:' \
    'deploy-examples:' \
    'fix-dns:' \
    'health-check:' \
    'destroy:' \
    'rebuild:' \
    'preflight:'
  do
    run grep -F -- "$literal" "$TASKFILE"
    [ "$status" -eq 0 ]
  done
}

@test "REPO-05: Taskfile.yml is a thin wrapper — every cmds: entry calls bash scripts/<name>.sh and nothing else" {
  [ -f "$TASKFILE" ]
  run bash -c "awk '/^[[:space:]]+cmds:/{flag=1; next} /^  [a-z]/{flag=0} flag && /^[[:space:]]*-/' '$TASKFILE' | grep -vE '^[[:space:]]*-[[:space:]]+bash scripts/[a-z][a-z0-9-]+\\.sh\$'"
  [ "$status" -ne 0 ]
}

@test "REPO-05: Taskfile.yml has no inline kubectl|docker|k3d|flux invocations outside cmds:" {
  [ -f "$TASKFILE" ]
  run bash -c "grep -vE '^[[:space:]]*(#|cmds:|-[[:space:]]+bash scripts/)' '$TASKFILE' | grep -vE '^[[:space:]]*\$' | grep -E '\\b(kubectl|docker|k3d|flux)[[:space:]]+'"
  [ "$status" -ne 0 ]
}
