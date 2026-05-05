#!/usr/bin/env bats
# tests/bats/proxy-01-static-script.bats
# Phase 10 / Wave 0 (D-10-09 Nyquist gate)
# Static script-shape contract for scripts/poc/capsule/issue-tenant-kubeconfig.sh.
# RED until Plan 10-01 lands the script. PROXY-01 + D-10-01/03/06/07 + Pitfall 10-P1/10-P7 lints.

load 'test_helper'

setup() {
  SCRIPT="${REPO_ROOT}/scripts/poc/capsule/issue-tenant-kubeconfig.sh"
}

@test "PROXY-01 / D-10-09: scripts/poc/capsule/issue-tenant-kubeconfig.sh exists" {
  [ -f "$SCRIPT" ]
}

@test "PROXY-01 / D-10-09: script has shebang + strict-mode + path pinning + preflight-lib source" {
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

@test "PROXY-01 / D-10-09: head comment cites PROXY-01 + D-10-01/03/06 + P31 + ADR-004" {
  [ -f "$SCRIPT" ]
  for literal in 'PROXY-01' 'D-10-01' 'D-10-03' 'D-10-06' 'P31' 'ADR-004' ; do
    run grep -F -- "$literal" "$SCRIPT"
    [ "$status" -eq 0 ]
  done
}

@test "PROXY-01 / D-10-01: TokenRequest contract literals present" {
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

@test "PROXY-01 / D-10-07: kubeconfig heredoc literals present" {
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

@test "PROXY-01 / D-10-09: arg parsing — positional <tenant> <owner> + --duration + --write-to + --help" {
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

@test "PROXY-01 / D-10-04: SA-not-found fail-fast message includes 'Available SAs in this tenant'" {
  [ -f "$SCRIPT" ]
  run grep -F -- 'Available SAs in this tenant' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "PROXY-01 / D-10-09: --write-to validation uses realpath -m + TENANT_TMPDIR prefix check" {
  [ -f "$SCRIPT" ]
  for literal in \
    'realpath -m' \
    'TENANT_TMPDIR=' \
    'karyon-tenants' ; do
    run grep -F -- "$literal" "$SCRIPT"
    [ "$status" -eq 0 ]
  done
}

@test "PROXY-01 / Pitfall 10-P1: script reads tls.crt jsonpath (NOT ca.crt)" {
  [ -f "$SCRIPT" ]
  run grep -F -- "{.data.tls\\.crt}" "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "PROXY-01 / D-10-06: script has NO 'insecure-skip-tls-verify' (anti-pattern lint)" {
  [ -f "$SCRIPT" ]
  # Strip comments before grepping for the anti-pattern; head-comment context lines may
  # mention 'insecure-skip-tls-verify' as an anti-pattern reference (Phase 8 WR-01..04 hardening).
  run grep -v '^#' "$SCRIPT"
  echo "$output" | grep -F -- 'insecure-skip-tls-verify' && return 1 || return 0
}

@test "PROXY-01 / D-10-08: script has NO '--mode direct' flag (anti-pattern lint)" {
  [ -f "$SCRIPT" ]
  run grep -v '^#' "$SCRIPT"
  echo "$output" | grep -F -- '--mode direct' && return 1 || return 0
}

@test "PROXY-01 / Pitfall 10-P1: script has NO ca.crt jsonpath (Secret only has tls.crt)" {
  [ -f "$SCRIPT" ]
  run grep -v '^#' "$SCRIPT"
  echo "$output" | grep -F -- "{.data.ca\\.crt}" && return 1 || return 0
}
