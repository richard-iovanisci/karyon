#!/usr/bin/env bats
# tests/bats/proxy-06-live-fixture.bats
# Phase 10 / Wave 0 (D-10-09 Nyquist gate)
# Live PROXY-03 leak-defense fixture verification:
# (1) git check-ignore catches karyon-tenants/ glob — REPO-RELATIVE path per Pitfall 10-P5.
# (2) gitleaks detect fires on Phase 7 positive fixture (synthetic-kubeconfig.yaml).
# (3) gitleaks detect fires on a NEW tenant-shaped fixture NOT in the allowlist.
# REPO-RELATIVE path requirement is LOAD-BEARING (Pitfall 10-P5).

load 'test_helper'

setup() {
  GITLEAKS_TOML="${REPO_ROOT}/.gitleaks.toml"
  POSITIVE_FIXTURE="${REPO_ROOT}/tests/fixtures/gitleaks/synthetic-kubeconfig.yaml"
}

@test "PROXY-03 leak defense (Pitfall 10-P5): git check-ignore catches karyon-tenants/ glob (repo-relative)" {
  cd "$REPO_ROOT"
  mkdir -p karyon-tenants
  : > karyon-tenants/test.kubeconfig

  run git check-ignore -v karyon-tenants/test.kubeconfig
  [ "$status" -eq 0 ]
  [[ "$output" == *karyon-tenants/* ]]
}

@test "PROXY-03 leak defense: gitleaks fires on Phase 7 synthetic-kubeconfig.yaml positive fixture" {
  [ -f "$POSITIVE_FIXTURE" ]
  [ -f "$GITLEAKS_TOML" ]
  run gitleaks detect --no-banner --no-git --source "$POSITIVE_FIXTURE" --config "$GITLEAKS_TOML" --redact --verbose
  [ "$status" -ne 0 ]
}

@test "PROXY-03 leak defense: gitleaks fires on tenant-shaped fixture NOT in allowlist" {
  TEMP_FIXTURE=$(mktemp -p "${REPO_ROOT}/tests/fixtures/gitleaks" temp-tenant-fixture-XXXX.yaml)
  cat > "$TEMP_FIXTURE" <<EOF
apiVersion: v1
kind: Config
clusters:
  - name: capsule-proxy-127.0.0.1
    cluster:
      server: https://127.0.0.1:30443
users:
  - name: gitops-reconciler
    user:
      token: ZXhhbXBsZS1pbmVydC10b2tlbi12MC4xOS1zeW50aGV0aWMtZml4dHVyZS1mb3ItcHJveHktMDYtbGl2ZQ
contexts:
  - name: tenant-alpha-via-proxy
    context:
      cluster: capsule-proxy-127.0.0.1
      user: gitops-reconciler
current-context: tenant-alpha-via-proxy
EOF

  run gitleaks detect --no-banner --no-git --source "$TEMP_FIXTURE" --config "$GITLEAKS_TOML" --redact --verbose
  rm -f "$TEMP_FIXTURE"
  [ "$status" -ne 0 ]
}

teardown() {
  rm -rf "${REPO_ROOT}/karyon-tenants" 2>/dev/null || true
}
