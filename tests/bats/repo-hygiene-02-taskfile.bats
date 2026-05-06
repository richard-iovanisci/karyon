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

@test "REPO-05: Taskfile.yml is a thin wrapper — every cmds: entry calls bash scripts/<path>.sh and nothing else" {
  [ -f "$TASKFILE" ]
  # Allow flat (scripts/foo.sh) and nested POC paths (scripts/poc/capsule/fix-dns.sh)
  # per D-12 / P31 isolation. Thin-wrapper invariant preserved: still only
  # `bash <path>.sh` is permitted; no inline kubectl/docker/k3d/flux.
  # Phase 11 D-11-12: also accept the Taskfile v3 `{{.CLI_ARGS}}` variadic pass-through
  # idiom as a trailing token (e.g. `bash scripts/poc/capsule/destroy-poc.sh {{.CLI_ARGS}}`).
  # The trailing token is a literal Taskfile substitution marker, not an inline command,
  # so the thin-wrapper invariant is preserved (test 3 below still rejects inline
  # kubectl|docker|k3d|flux invocations everywhere).
  run bash -c "awk '/^[[:space:]]+cmds:/{flag=1; next} /^  [a-z]/{flag=0} flag && /^[[:space:]]*-/' '$TASKFILE' | grep -vE '^[[:space:]]*-[[:space:]]+bash scripts/[a-z0-9/-]+\\.sh([[:space:]]+\\{\\{\\.CLI_ARGS\\}\\})?\$'"
  [ "$status" -ne 0 ]
}

@test "REPO-05: Taskfile.yml has no inline kubectl|docker|k3d|flux invocations outside cmds:" {
  [ -f "$TASKFILE" ]
  # Exclude comments, cmds:, desc: (descriptions narratively reference k3d/Flux),
  # and the canonical `- bash scripts/<name>.sh` list items. The remaining lines
  # are everything that COULD harbor an inline invocation; assert none contain
  # a kubectl|docker|k3d|flux command followed by whitespace.
  run bash -c "grep -vE '^[[:space:]]*(#|cmds:|desc:|-[[:space:]]+bash scripts/)' '$TASKFILE' | grep -vE '^[[:space:]]*\$' | grep -E '\\b(kubectl|docker|k3d|flux)[[:space:]]+'"
  [ "$status" -ne 0 ]
}
