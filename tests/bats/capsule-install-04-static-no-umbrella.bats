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

@test "Anti-umbrella (D-08-01 milestone-open / WR-01 fix): operator HelmRelease has NO values.proxy.enabled=true at any depth" {
  [ -f "$OPERATOR_HR" ]
  # WR-01 fix (08-REVIEW.md): replaces vacuous `grep -F 'proxy.enabled: true'` (impossible
  # dotted-key literal in valid YAML) with a yq path negative assertion that walks all keys
  # named 'proxy' anywhere in the document and asserts none have nested .enabled == true.
  # proxy.enabled: false is still allowed (explicit positive presence asserted by
  # capsule-install-03-static-values.bats:57-62).
  # NOTE: mikefarah/yq syntax — `..` recursive descent operator does NOT take a path prefix
  # (`.spec.values..` is a parse error); use `[.. | select(has("proxy")) | .proxy.enabled]`
  # to walk the whole document. `any_c(. == true)` (NOT jq's `any(. == true)`) is yq's
  # collection-of-conditions reducer.
  run yq eval '[.. | select(has("proxy")) | .proxy.enabled] | any_c(. == true)' "$OPERATOR_HR"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "Pitfall 9 / RESEARCH catch: proxy HelmRelease dependsOn[0] has NO 'wait:' field" {
  [ -f "$PROXY_HR" ]
  run yq eval '.spec.dependsOn[0] | has("wait")' "$PROXY_HR"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "Anti-pattern (D-08-04 / WR-02 fix): operator HR has values.certManager.generateCertificates explicitly false (or absent)" {
  [ -f "$OPERATOR_HR" ]
  # WR-02 fix (08-REVIEW.md): replaces vacuous `grep -F 'certManager.generateCertificates: true'`
  # (impossible dotted-key literal) with a yq path assertion. The operator HR's
  # .spec.values.certManager.generateCertificates is set to false (operator uses
  # tls.enableController for its built-in certgen path per D-08-04). Both 'absent' and
  # 'present-with-false' satisfy the gate; assert NOT true.
  run yq eval '(.spec.values.certManager.generateCertificates // false) == false' "$OPERATOR_HR"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "D-08-11 (gap-close): proxy HR has options.generateCertificates=true AND certManager.generateCertificates=false (controller-less certgen)" {
  [ -f "$PROXY_HR" ]
  # D-08-11 cert flip (08-CONTEXT.md lines 88-94 + 08-VERIFICATION.md G-03 + 08-REVIEW.md BL-01).
  # Verifies the proxy HR uses the chart's controller-less self-sign Job path, NOT the
  # cert-manager.io Issuer/Certificate path that requires an absent controller.
  run yq eval '.spec.values.options.generateCertificates == true and .spec.values.certManager.generateCertificates == false' "$PROXY_HR"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
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
