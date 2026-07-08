#!/usr/bin/env bats
# tests/bats/teardown-01-static-script.bats
# Static script-shape contract for scripts/poc/capsule/destroy-poc.sh:
# ordered teardown sequence, PVC finalizer mitigation, sentinel preservation.

load 'test_helper'

setup() {
  SCRIPT="${REPO_ROOT}/scripts/poc/capsule/destroy-poc.sh"
}

@test "scripts/poc/capsule/destroy-poc.sh exists" {
  [ -f "$SCRIPT" ]
}

@test "script has shebang + strict-mode + path pinning + preflight-lib source" {
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

@test "head comment documents teardown order + POC isolation contract" {
  [ -f "$SCRIPT" ]
  # The head comment must keep the load-bearing rationale in plain language:
  # the ordered teardown shape, the PVC finalizer mitigation, and the
  # standalone-POC-helper isolation contract.
  for literal in \
    'Ordered teardown' \
    'Suspend-before-delete' \
    'force-delete PVC finalizers after 60s' \
    'never invoked by task rebuild' \
    'poc-isolation-01-static.bats' ; do
    run grep -F -- "$literal" "$SCRIPT"
    [ "$status" -eq 0 ]
  done
}

@test "script implements 5-step canonical sequence + --full flag (per-Kustomization suspend)" {
  [ -f "$SCRIPT" ]
  # The script must invoke flux suspend ONCE PER Kustomization (not multi-arg): the multi-arg
  # form may not be valid for the installed flux CLI version and obscures error attribution.
  # Each name must appear as its own suspend invocation literal.
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
  # Standardized task command form (with `--`)
  for literal in \
    'task destroy-poc -- capsule' ; do
    run grep -F -- "$literal" "$SCRIPT"
    [ "$status" -eq 0 ]
  done
}

@test "script has PVC strand auto force-delete logic via NS_LIST loop" {
  [ -f "$SCRIPT" ]
  # PVCs do NOT carry the capsule.clastix.io/tenant label (only namespaces do), so the
  # script must walk the NS_LIST of labeled namespaces instead of using a -l selector
  # on the PVC list. Required literals:
  for literal in \
    'NS_LIST=' \
    'finalizers' \
    '{"metadata":{"finalizers":null}}' \
    '--type=merge' ; do
    run grep -F -- "$literal" "$SCRIPT"
    [ "$status" -eq 0 ]
  done
}

@test "sentinel preservation: destroy-poc.sh does NOT mutate flux-system kustomization.yaml" {
  [ -f "$SCRIPT" ]
  # Comment-stripped grep ensures head-comment context references to the file path don't trip the lint
  run bash -c "grep -v '^[[:space:]]*#' '$SCRIPT' | grep -F -- 'flux-system/kustomization.yaml'"
  [ "$status" -ne 0 ]
}
