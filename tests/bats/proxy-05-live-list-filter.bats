#!/usr/bin/env bats
# tests/bats/proxy-05-live-list-filter.bats
# Live verification: proxy LIST filter + direct-apiserver 403 falsifier.
# Direct apiserver returns 403, NOT a wider list: the SA's RBAC is namespace-scoped
# (admin RoleBinding only inside owned namespaces).
# Falsifier shape: qualitative (Forbidden + 'cannot list resource' string), NOT quantitative count.

load 'test_helper'

setup() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
}

@test "PROXY-02 live (D-10-09 / Pitfall 10-P3 corrected): proxy returns filtered subset + direct apiserver returns 403" {
  ISSUED_KC=$(mktemp -p "${TMPDIR:-/tmp}" karyon-proxy-05-issued-XXXX.kubeconfig)
  bash "${REPO_ROOT}/scripts/poc/capsule/issue-tenant-kubeconfig.sh" alpha gitops-reconciler 2>/dev/null > "$ISSUED_KC"

  # Extract the bearer token from the issued kubeconfig
  TOKEN=$(yq eval '.users[0].user.token' "$ISSUED_KC")

  # Construct a direct-apiserver kubeconfig (same token, different cluster URL).
  # nolint(insecure-skip-tls-verify): the probe deliberately
  # uses `insecure-skip-tls-verify: true` because the spoke-capsule apiserver cert does
  # not have 127.0.0.1:6446 in its SAN list (only NodePort 30443 is in scope for the
  # proxy's cert). This is bats-internal, ephemeral (tmpfile, removed in test), and the
  # apiserver returns 403 Forbidden BEFORE TLS state matters here. The
  # anti-pattern lint (proxy-01-static-script.bats:100) only scans the script, not bats.
  DIRECT_KC=$(mktemp -p "${TMPDIR:-/tmp}" karyon-proxy-05-direct-XXXX.kubeconfig)
  cat > "$DIRECT_KC" <<EOF
apiVersion: v1
kind: Config
clusters:
- name: direct
  cluster:
    server: https://127.0.0.1:6446
    insecure-skip-tls-verify: true
users:
- name: alpha-sa
  user:
    token: $TOKEN
contexts:
- name: direct
  context:
    cluster: direct
    user: alpha-sa
current-context: direct
EOF

  # Proxy: 200 with filtered subset (tenant-alpha — NOT tenant-bravo, NOT kube-*, NOT capsule-system, NOT flux-system).
  # 2026-07-06: alpha-app1 is a fixture namespace created by the tenants quota
  # live suites, not GitOps (same class as the 32a8acf seed-02/seed-04 guards);
  # assert its presence in the filtered list only when the fixture exists so
  # this suite is honest standalone.
  PROXY_OUT=$(kubectl --kubeconfig="$ISSUED_KC" get namespaces -o name 2>&1)
  PROXY_RC=$?
  [ "$PROXY_RC" -eq 0 ]
  echo "$PROXY_OUT" | grep -qF 'namespace/tenant-alpha'
  if kubectl --context=k3d-spoke-capsule get namespace alpha-app1 >/dev/null 2>&1; then
    echo "$PROXY_OUT" | grep -qF 'namespace/alpha-app1'
  fi
  ! echo "$PROXY_OUT" | grep -qF 'namespace/tenant-bravo'
  ! echo "$PROXY_OUT" | grep -qF 'namespace/kube-system'
  ! echo "$PROXY_OUT" | grep -qF 'namespace/flux-system'
  ! echo "$PROXY_OUT" | grep -qF 'namespace/capsule-system'
  # 2026-07-06 keycloak-idp-poc: the third (platform) tenant must NOT leak into
  # alpha's proxy-filtered view.
  ! echo "$PROXY_OUT" | grep -qF 'namespace/keycloak'

  # Direct apiserver: 403 Forbidden (proves filtering happens at proxy, NOT at apiserver RBAC)
  DIRECT_RC=0
  DIRECT_OUT=$(kubectl --kubeconfig="$DIRECT_KC" get namespaces 2>&1) || DIRECT_RC=$?
  [ "$DIRECT_RC" -ne 0 ]
  echo "$DIRECT_OUT" | grep -qF 'Forbidden'
  echo "$DIRECT_OUT" | grep -qF 'cannot list resource "namespaces"'

  rm -f "$ISSUED_KC" "$DIRECT_KC"
}

@test "PROXY-02 live: bravo kubeconfig LIST — bravo namespaces present, alpha absent (cross-tenant negative)" {
  ISSUED_KC=$(mktemp -p "${TMPDIR:-/tmp}" karyon-proxy-05-bravo-XXXX.kubeconfig)
  bash "${REPO_ROOT}/scripts/poc/capsule/issue-tenant-kubeconfig.sh" bravo gitops-reconciler 2>/dev/null > "$ISSUED_KC"

  PROXY_OUT=$(kubectl --kubeconfig="$ISSUED_KC" get namespaces -o name 2>&1)
  echo "$PROXY_OUT" | grep -qF 'namespace/tenant-bravo'
  ! echo "$PROXY_OUT" | grep -qF 'namespace/tenant-alpha'
  ! echo "$PROXY_OUT" | grep -qF 'namespace/alpha-app1'

  rm -f "$ISSUED_KC"
}
