#!/usr/bin/env bats
# tests/bats/capsule-install-04-static-no-umbrella.bats
# Phase 8 / Wave 0 (D-08-09 Nyquist gate)
# Anti-pattern lints — no umbrella `proxy.enabled: true`; no `wait:` field in dependsOn (Pitfall 9);
# no cert-manager (D-08-04); no Phase 9 scope creep (CapsuleConfiguration / Tenant CRs).
# Plans 08-01 and 08-02 land the yaml that turns these GREEN.

load 'test_helper'

setup() {
  OPERATOR_HR="${REPO_ROOT}/pocs/capsule/operator/helmrelease.yaml"
  PROXY_HR="${REPO_ROOT}/pocs/capsule/proxy/helmrelease.yaml"
}

@test "Anti-umbrella (D-08-01 milestone-open): operator HelmRelease has NO 'proxy.enabled: true' literal (proxy.enabled: false is allowed)" {
  [ -f "$OPERATOR_HR" ]
  # proxy.enabled: false is allowed (explicit anti-pattern lint per RESEARCH §Example 1).
  # Anti-grep: only the literal 'proxy.enabled: true' is forbidden.
  run bash -c "grep -v '^[[:space:]]*#' '$OPERATOR_HR' | grep -F -- 'proxy.enabled: true'"
  [ "$status" -ne 0 ]
}

@test "Pitfall 9 / RESEARCH catch: proxy HelmRelease dependsOn[0] has NO 'wait:' field" {
  [ -f "$PROXY_HR" ]
  run yq eval '.spec.dependsOn[0] | has("wait")' "$PROXY_HR"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "Anti-pattern: operator HR has NO 'certManager.generateCertificates: true' (D-08-04 — built-in certgen, NO cert-manager)" {
  [ -f "$OPERATOR_HR" ]
  run bash -c "grep -v '^[[:space:]]*#' '$OPERATOR_HR' | grep -F -- 'certManager.generateCertificates: true'"
  [ "$status" -ne 0 ]
}

@test "Phase 8 scope boundary: operator HR file does NOT include CapsuleConfiguration CR shape (apiVersion: capsule.clastix.io)" {
  [ -f "$OPERATOR_HR" ]
  run grep -F -- 'kind: CapsuleConfiguration' "$OPERATOR_HR"
  [ "$status" -ne 0 ]
}

@test "Phase 8 scope boundary: proxy HR file does NOT include Tenant CR shape" {
  [ -f "$PROXY_HR" ]
  run grep -F -- 'kind: Tenant' "$PROXY_HR"
  [ "$status" -ne 0 ]
}
