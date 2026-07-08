#!/usr/bin/env bats
# tests/bats/proxy-01-static-script.bats
# Static script-shape contract for scripts/poc/capsule/issue-tenant-kubeconfig.sh:
# TokenRequest surface, kubeconfig heredoc shape, --write-to defenses, TLS anti-pattern lints.

load 'test_helper'

setup() {
  SCRIPT="${REPO_ROOT}/scripts/poc/capsule/issue-tenant-kubeconfig.sh"
}

@test "scripts/poc/capsule/issue-tenant-kubeconfig.sh exists" {
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

@test "head comment documents TokenRequest + proxy CA + isolation contract" {
  [ -f "$SCRIPT" ]
  # The head comment must keep the load-bearing rationale in plain language:
  # token minting mechanism, the tls.crt-is-the-CA-root gotcha, the
  # standalone-POC-helper isolation contract, and the hub-only Flux constraint.
  for literal in \
    'TokenRequest API' \
    'tls.crt IS the CA root' \
    'never invoked by task rebuild' \
    'poc-isolation-01-static.bats' \
    'Hub-only Flux' ; do
    run grep -F -- "$literal" "$SCRIPT"
    [ "$status" -eq 0 ]
  done
}

@test "TokenRequest contract literals present" {
  [ -f "$SCRIPT" ]
  for literal in \
    'kubectl --context=k3d-spoke-capsule' \
    'create token' \
    '-n "tenant-' \
    '--duration=' ; do
    run grep -F -- "$literal" "$SCRIPT"
    [ "$status" -eq 0 ]
  done
}

@test "kubeconfig heredoc literals present" {
  [ -f "$SCRIPT" ]
  for literal in \
    'server: https://127.0.0.1:30443' \
    'certificate-authority-data:' \
    'capsule-proxy-127.0.0.1' \
    'current-context: tenant-${TENANT}-via-proxy' ; do
    run grep -F -- "$literal" "$SCRIPT"
    [ "$status" -eq 0 ]
  done
}

@test "arg parsing — positional <tenant> <owner> + --duration + --write-to + --help" {
  [ -f "$SCRIPT" ]
  for literal in \
    '--duration)' \
    '--write-to)' \
    '--help|-h)' \
    'TENANT=""' \
    'OWNER=""' \
    'DURATION=' \
    'WRITE_TO=""' ; do
    run grep -F -- "$literal" "$SCRIPT"
    [ "$status" -eq 0 ]
  done
}

@test "SA-not-found fail-fast message includes 'Available SAs in this tenant'" {
  [ -f "$SCRIPT" ]
  run grep -F -- 'Available SAs in this tenant' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "--write-to validation uses realpath -m + TENANT_TMPDIR prefix check" {
  [ -f "$SCRIPT" ]
  for literal in \
    'realpath -m' \
    'TENANT_TMPDIR=' \
    'karyon-tenants' ; do
    run grep -F -- "$literal" "$SCRIPT"
    [ "$status" -eq 0 ]
  done
}

@test "script reads tls.crt jsonpath (NOT ca.crt)" {
  [ -f "$SCRIPT" ]
  run grep -F -- "{.data.tls\\.crt}" "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "script has NO 'insecure-skip-tls-verify' (anti-pattern lint)" {
  [ -f "$SCRIPT" ]
  # Strip comments before grepping for the anti-pattern; comment lines may
  # mention 'insecure-skip-tls-verify' as an anti-pattern reference.
  run grep -v '^#' "$SCRIPT"
  echo "$output" | grep -F -- 'insecure-skip-tls-verify' && return 1 || return 0
}

@test "script has NO '--mode direct' flag (anti-pattern lint)" {
  [ -f "$SCRIPT" ]
  run grep -v '^#' "$SCRIPT"
  echo "$output" | grep -F -- '--mode direct' && return 1 || return 0
}

@test "script has NO ca.crt jsonpath (Secret only has tls.crt)" {
  [ -f "$SCRIPT" ]
  run grep -v '^#' "$SCRIPT"
  echo "$output" | grep -F -- "{.data.ca\\.crt}" && return 1 || return 0
}
