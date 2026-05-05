#!/usr/bin/env bats
# tests/bats/proxy-04-live-issue.bats
# Phase 10 / Wave 0 (D-10-09 Nyquist gate)
# Live PROXY-01 verification: scripts/poc/capsule/issue-tenant-kubeconfig.sh
# RED until Plan 10-01 lands the script. Auto-skips when k3d-spoke-capsule unreachable.
# Validates: clean stdout YAML (Pitfall 10-P7) + JWT decode (RESEARCH §C4) + --write-to (RESEARCH §C5).

load 'test_helper'

setup() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
}

@test "PROXY-01 live (D-10-09): alpha kubeconfig issuance — clean stdout YAML + 'tenant-alpha-via-proxy' current-context" {
  ISSUED_KC=$(mktemp -p "${TMPDIR:-/tmp}" karyon-proxy-04-alpha-XXXX.kubeconfig)
  bash "${REPO_ROOT}/scripts/poc/capsule/issue-tenant-kubeconfig.sh" alpha gitops-reconciler 2>/dev/null > "$ISSUED_KC"

  # Stdout YAML is parseable (Pitfall 10-P7 stderr split contract)
  run yq eval '.kind' "$ISSUED_KC"
  [ "$status" -eq 0 ]
  [ "$output" = "Config" ]

  # current-context literal (D-10-07)
  run yq eval '.current-context' "$ISSUED_KC"
  [ "$status" -eq 0 ]
  [ "$output" = "tenant-alpha-via-proxy" ]

  # Server URL literal (D-10-07)
  run yq eval '.clusters[0].cluster.server' "$ISSUED_KC"
  [ "$status" -eq 0 ]
  [ "$output" = "https://127.0.0.1:30443" ]

  # Default namespace in context = tenant-alpha (D-10-07)
  run yq eval '.contexts[0].context.namespace' "$ISSUED_KC"
  [ "$status" -eq 0 ]
  [ "$output" = "tenant-alpha" ]

  rm -f "$ISSUED_KC"
}

@test "PROXY-01 live: JWT decode — exp - iat ≈ 1h (default duration honored on k3s; Pitfall 10-P3)" {
  ISSUED_KC=$(mktemp -p "${TMPDIR:-/tmp}" karyon-proxy-04-jwt-XXXX.kubeconfig)
  bash "${REPO_ROOT}/scripts/poc/capsule/issue-tenant-kubeconfig.sh" alpha gitops-reconciler 2>/dev/null > "$ISSUED_KC"

  TOKEN=$(yq eval '.users[0].user.token' "$ISSUED_KC")
  PAYLOAD=$(echo "$TOKEN" | cut -d. -f2)
  case $((${#PAYLOAD} % 4)) in
    2) PAYLOAD="${PAYLOAD}==" ;;
    3) PAYLOAD="${PAYLOAD}=" ;;
  esac
  DECODED=$(echo "$PAYLOAD" | tr '_-' '/+' | base64 -d 2>/dev/null)
  EXP=$(echo "$DECODED" | jq -r '.exp')
  IAT=$(echo "$DECODED" | jq -r '.iat')

  # ±60s tolerance for clock skew (RESEARCH §C4)
  [ "$((EXP - IAT))" -ge 3540 ]
  [ "$((EXP - IAT))" -le 3660 ]

  # Subject = the SA we requested
  SUB=$(echo "$DECODED" | jq -r '.sub')
  [ "$SUB" = "system:serviceaccount:tenant-alpha:gitops-reconciler" ]

  rm -f "$ISSUED_KC"
}

@test "PROXY-01 live: bravo kubeconfig issuance — current-context 'tenant-bravo-via-proxy', namespace 'tenant-bravo'" {
  ISSUED_KC=$(mktemp -p "${TMPDIR:-/tmp}" karyon-proxy-04-bravo-XXXX.kubeconfig)
  bash "${REPO_ROOT}/scripts/poc/capsule/issue-tenant-kubeconfig.sh" bravo gitops-reconciler 2>/dev/null > "$ISSUED_KC"

  run yq eval '.current-context' "$ISSUED_KC"
  [ "$status" -eq 0 ]
  [ "$output" = "tenant-bravo-via-proxy" ]

  run yq eval '.contexts[0].context.namespace' "$ISSUED_KC"
  [ "$status" -eq 0 ]
  [ "$output" = "tenant-bravo" ]

  rm -f "$ISSUED_KC"
}

@test "PROXY-01 live (D-10-09): --write-to inside \${TMPDIR:-/tmp}/karyon-tenants/ writes owner-private (mode 0600) file" {
  WRITE_PATH="${TMPDIR:-/tmp}/karyon-tenants/proxy-04-test.kubeconfig"
  bash "${REPO_ROOT}/scripts/poc/capsule/issue-tenant-kubeconfig.sh" alpha gitops-reconciler --write-to "$WRITE_PATH" >/dev/null 2>&1
  [ -f "$WRITE_PATH" ]
  # BL-02 / WR-07: file must be owner-private (mode 0600), not world-readable (0644).
  # Bearer-token kubeconfig must remain confidential to the issuing operator.
  mode=$(stat -c '%a' "$WRITE_PATH")
  [ "$mode" = "600" ]
  run yq eval '.kind' "$WRITE_PATH"
  [ "$status" -eq 0 ]
  [ "$output" = "Config" ]
  rm -f "$WRITE_PATH"
}

@test "PROXY-01 live (T-10-02): --write-to /etc/passwd outside tmpdir REJECTED exit non-zero" {
  run bash "${REPO_ROOT}/scripts/poc/capsule/issue-tenant-kubeconfig.sh" alpha gitops-reconciler --write-to /etc/passwd
  [ "$status" -ne 0 ]
  echo "$output" | grep -qF 'outside'
}

@test "PROXY-01 live (T-10-02): --write-to with symlink-escape components rejected via realpath -m" {
  run bash "${REPO_ROOT}/scripts/poc/capsule/issue-tenant-kubeconfig.sh" alpha gitops-reconciler --write-to "${TMPDIR:-/tmp}/karyon-tenants/../../etc/passwd"
  [ "$status" -ne 0 ]
}

@test "PROXY-01 live (D-10-04): unknown owner SA fail-fast with 'Available SAs in this tenant' hint" {
  run bash "${REPO_ROOT}/scripts/poc/capsule/issue-tenant-kubeconfig.sh" alpha nonexistent-sa
  [ "$status" -ne 0 ]
  echo "$output" | grep -qF 'Available SAs in this tenant'
}
