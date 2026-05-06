#!/usr/bin/env bats
# tests/bats/teardown-01-static-script.bats
# Phase 11 / Wave 0 -- D-11-10 / D-11-11 static script-shape contract for
# scripts/poc/capsule/destroy-poc.sh. RED until Plan 11-02 lands the script.

load 'test_helper'

setup() {
  SCRIPT="${REPO_ROOT}/scripts/poc/capsule/destroy-poc.sh"
}

@test "D-11-10: scripts/poc/capsule/destroy-poc.sh exists" {
  [ -f "$SCRIPT" ]
}

@test "D-11-10: script has shebang + strict-mode + path pinning + preflight-lib source" {
  [ -f "$SCRIPT" ]
  for literal in \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'SCRIPT_DIR=' \
    'REPO_ROOT=' \
    'source "${REPO_ROOT}/scripts/lib/preflight-lib.sh"' ; do
    run grep -F -- "$literal" "$SCRIPT"
    [ "$status" -eq 0 ]
  done
}

@test "D-11-10: head comment cites VAL-03 + D-11-10 + D-11-11 + P31 + ADR-004" {
  [ -f "$SCRIPT" ]
  for literal in 'VAL-03' 'D-11-10' 'D-11-11' 'P31' 'ADR-004' ; do
    run grep -F -- "$literal" "$SCRIPT"
    [ "$status" -eq 0 ]
  done
}

@test "D-11-10: script implements 5-step canonical sequence + --full flag (REVISED per-Kustomization suspend per reviewer HIGH #5)" {
  [ -f "$SCRIPT" ]
  # REVISED 2026-05-05 (reviewer HIGH #5): script must invoke flux suspend ONE PER Kustomization
  # (not multi-arg). Each name must appear as its own suspend invocation literal.
  for literal in \
    'flux suspend kustomization tenant-alpha' \
    'flux suspend kustomization tenant-bravo' \
    'flux suspend kustomization poc-capsule-spoke' \
    'kubectl --context=k3d-spoke-capsule delete tenant alpha bravo' \
    'capsule.clastix.io/tenant' \
    'flux suspend kustomization poc-capsule -n flux-system' \
    '--full' \
    'k3d cluster delete spoke-capsule' ; do
    run grep -F -- "$literal" "$SCRIPT"
    [ "$status" -eq 0 ]
  done
  # REVISED 2026-05-05 (reviewer MEDIUM #11): standardize task command form (with `--`)
  for literal in \
    'task destroy-poc -- capsule' ; do
    run grep -F -- "$literal" "$SCRIPT"
    [ "$status" -eq 0 ]
  done
}

@test "D-11-11: script has PVC strand auto force-delete logic via NS_LIST loop (REVISED per reviewer MEDIUM #9)" {
  [ -f "$SCRIPT" ]
  # REVISED 2026-05-05 (reviewer MEDIUM #9): drop -l label selector when listing PVCs;
  # use NS_LIST-of-labeled-namespaces loop instead. Required literals:
  for literal in \
    'NS_LIST=' \
    'finalizers' \
    '{"metadata":{"finalizers":null}}' \
    '--type=merge' ; do
    run grep -F -- "$literal" "$SCRIPT"
    [ "$status" -eq 0 ]
  done
}

@test "D-11-10 / sentinel preservation: destroy-poc.sh does NOT mutate flux-system kustomization.yaml" {
  [ -f "$SCRIPT" ]
  # Comment-stripped grep ensures head-comment context references to the file path don't trip the lint
  run bash -c "grep -v '^[[:space:]]*#' '$SCRIPT' | grep -F -- 'flux-system/kustomization.yaml'"
  [ "$status" -ne 0 ]
}
