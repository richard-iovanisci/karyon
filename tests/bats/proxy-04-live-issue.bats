#!/usr/bin/env bats
# tests/bats/proxy-04-live-issue.bats
# Live verification: scripts/poc/capsule/issue-tenant-kubeconfig.sh
# Auto-skips when k3d-spoke-capsule is unreachable.
# Validates: clean stdout YAML (all logging on stderr) + JWT decode + --write-to.

load 'test_helper'

setup() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
}

@test "PROXY-01 live (D-10-09): alpha kubeconfig issuance — clean stdout YAML + 'tenant-alpha-via-proxy' current-context" {
  ISSUED_KC=$(mktemp -p "${TMPDIR:-/tmp}" karyon-proxy-04-alpha-XXXX.kubeconfig)
  bash "${REPO_ROOT}/scripts/poc/capsule/issue-tenant-kubeconfig.sh" alpha gitops-reconciler 2>/dev/null > "$ISSUED_KC"

  # Stdout YAML is parseable (all logging goes to stderr; stdout is pure YAML)
  run yq eval '.kind' "$ISSUED_KC"
  [ "$status" -eq 0 ]
  [ "$output" = "Config" ]

  # current-context literal
  run yq eval '.current-context' "$ISSUED_KC"
  [ "$status" -eq 0 ]
  [ "$output" = "tenant-alpha-via-proxy" ]

  # Server URL literal
  run yq eval '.clusters[0].cluster.server' "$ISSUED_KC"
  [ "$status" -eq 0 ]
  [ "$output" = "https://127.0.0.1:30443" ]

  # Default namespace in context = tenant-alpha
  run yq eval '.contexts[0].context.namespace' "$ISSUED_KC"
  [ "$status" -eq 0 ]
  [ "$output" = "tenant-alpha" ]

  rm -f "$ISSUED_KC"
}

@test "PROXY-01 live: JWT decode — exp - iat ≈ 1h (default duration honored on k3s; Pitfall 10-P3)" {
  ISSUED_KC=$(mktemp -p "${TMPDIR:-/tmp}" karyon-proxy-04-jwt-XXXX.kubeconfig)
  bash "${REPO_ROOT}/scripts/poc/capsule/issue-tenant-kubeconfig.sh" alpha gitops-reconciler 2>/dev/null > "$ISSUED_KC"

  # Validate JWT shape with clear diagnostics before arithmetic.
  # Without these guards, a malformed token would cause base64 -d / jq to silently
  # produce empty strings; arithmetic on empty values yields 0, and the test would
  # red-fail with "expected 0 >= 3540" -- much less useful than "token is not a JWT".
  TOKEN=$(yq eval '.users[0].user.token' "$ISSUED_KC")
  [ -n "$TOKEN" ] && [ "$TOKEN" != "null" ] || { echo "no token in kubeconfig"; rm -f "$ISSUED_KC"; return 1; }
  # Real JWT has exactly 3 dot-separated segments
  dot_count=$(echo "$TOKEN" | tr -cd '.' | wc -c)
  [ "$dot_count" = "2" ] || { echo "token is not a JWT (got ${dot_count} dots, want 2)"; rm -f "$ISSUED_KC"; return 1; }

  PAYLOAD=$(echo "$TOKEN" | cut -d. -f2)
  # All four padding cases:
  case $((${#PAYLOAD} % 4)) in
    0) ;;
    2) PAYLOAD="${PAYLOAD}==" ;;
    3) PAYLOAD="${PAYLOAD}=" ;;
    *) echo "invalid base64 payload length"; rm -f "$ISSUED_KC"; return 1 ;;
  esac
  DECODED=$(printf '%s' "$PAYLOAD" | tr '_-' '/+' | base64 -d) || { echo "base64 decode failed"; rm -f "$ISSUED_KC"; return 1; }
  echo "$DECODED" | jq empty || { echo "decoded payload is not JSON"; rm -f "$ISSUED_KC"; return 1; }

  EXP=$(echo "$DECODED" | jq -r '.exp')
  IAT=$(echo "$DECODED" | jq -r '.iat')

  # ±60s tolerance for clock skew
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
  # File must be owner-private (mode 0600), not world-readable (0644).
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
