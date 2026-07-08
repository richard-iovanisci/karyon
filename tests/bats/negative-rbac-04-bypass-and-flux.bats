#!/usr/bin/env bats
# tests/bats/negative-rbac-04-bypass-and-flux.bats
# Bypass + Flux denial probes: direct-apiserver bypass (qualitative 403 + 'cannot list
# resource'), cross-tenant sourceRef, and missing serviceAccountName.
# Probe Kustomizations are tmpdir-rooted.
#
# Probe design notes:
#   - The cross-tenant probe references a VALID GitRepository in tenant-bravo (not an
#     absent source); it accepts ONLY an explicit "cross-namespace" keyword (a permissive
#     "not allowed" substring could match unrelated denials).
#   - The missing-SA probe references a VALID sourceRef (tenant-alpha-source); positive
#     RBAC-keyword assertion; negative assert (message MUST NOT contain "source not found").
#   - The direct-apiserver probe does a TCP pre-check first + a negative TLS-failure
#     assertion (no x509/tls/connection refused/timeout).
#   - KARYON_PHASE11_STRICT_LIVE=1 converts skips to FAIL.

load 'test_helper'

_strict_skip() {
  local msg="$1"
  if [[ "${KARYON_PHASE11_STRICT_LIVE:-}" == "1" ]]; then
    echo "STRICT_LIVE: ${msg}" >&2
    return 1
  else
    skip "${msg}"
  fi
}

setup_file() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    if [[ "${KARYON_PHASE11_STRICT_LIVE:-}" == "1" ]]; then
      echo "STRICT_LIVE: k3d-spoke-capsule cluster not reachable" >&2
      return 1
    else
      skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
    fi
  fi
  export KARYON_BATS_TMPDIR="${TMPDIR:-/tmp}/karyon-tenants/bats-${BATS_RUN_TMPDIR##*/}"
  mkdir -p "$KARYON_BATS_TMPDIR"
  bash "${REPO_ROOT}/scripts/poc/capsule/issue-tenant-kubeconfig.sh" alpha gitops-reconciler \
    --duration=2h --write-to "${KARYON_BATS_TMPDIR}/alpha.kubeconfig" >/dev/null 2>&1
  export ALPHA_KUBECONFIG="${KARYON_BATS_TMPDIR}/alpha.kubeconfig"
}

teardown_file() {
  rm -rf "$KARYON_BATS_TMPDIR"
}

setup() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    _strict_skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
}

@test "N8 -- direct apiserver bypass on :6446 returns 403 + 'cannot list resource' (Pitfall 10-P3 + reviewer MEDIUM #12 negative TLS)" {
  # TCP pre-check first. If the apiserver is unreachable
  # via TCP, SKIP with explanatory message (NOT pass for the wrong reason -- we're testing
  # an RBAC denial, not network/TLS unreachability).
  if ! command -v nc >/dev/null 2>&1; then
    _strict_skip "nc command unavailable; cannot pre-check apiserver TCP reachability"
  fi
  if ! nc -z -w 5 127.0.0.1 6446 >/dev/null 2>&1; then
    _strict_skip "spoke-capsule apiserver port 127.0.0.1:6446 not reachable via TCP; skipping (RBAC-denial test requires reachable apiserver)"
  fi

  TOKEN=$(yq eval '.users[0].user.token' "$ALPHA_KUBECONFIG")
  DIRECT_KC=$(mktemp -p "${TMPDIR:-/tmp}" karyon-bats-n8-direct-XXXX.kubeconfig)
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
  DIRECT_RC=0
  DIRECT_OUT=$(kubectl --kubeconfig="$DIRECT_KC" get namespaces 2>&1) || DIRECT_RC=$?
  rm -f "$DIRECT_KC"
  [ "$DIRECT_RC" -ne 0 ]
  # POSITIVE assertions (existing): RBAC denial signature
  echo "$DIRECT_OUT" | grep -qF 'Forbidden'
  echo "$DIRECT_OUT" | grep -qF 'cannot list resource "namespaces"'
  # NEGATIVE assertions: output MUST NOT
  # indicate network/TLS failure -- those would mean the test passed for the WRONG reason
  # (we'd be detecting an unreachable apiserver, not an RBAC-denied LIST).
  if echo "$DIRECT_OUT" | grep -qE '(x509|tls:|connection refused|i/o timeout|no route to host)'; then
    echo "N8 FAIL: direct-apiserver returned a network/TLS error, not the RBAC denial we expected:"
    echo "$DIRECT_OUT"
    return 1
  fi
}

@test "N9 -- cross-tenant sourceRef in tenant Kustomization denied by Flux (--no-cross-namespace-refs); REVISED valid cross-tenant target" {
  # The probe Kustomization references a VALID GitRepository that EXISTS in tenant-bravo
  # namespace (the per-tenant GitRepository pattern mints `tenant-bravo-source` in
  # tenant-bravo). The ONLY failing variable is the cross-namespace reference --
  # not "source missing". Flux MUST surface a "cross-namespace" keyword in the Ready message.
  PROBE=$(mktemp -p "${TMPDIR:-/tmp}" karyon-bats-n9-cross-tenant-XXXX.yaml)
  cat > "$PROBE" <<EOF
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: probe-n9-cross-tenant
  namespace: tenant-alpha
spec:
  interval: 1m
  path: ./
  prune: false
  serviceAccountName: gitops-reconciler
  sourceRef:
    kind: GitRepository
    name: tenant-bravo-source
    namespace: tenant-bravo
EOF
  # Apply via cluster-admin (mints the K CR; Flux's lockdown flag denies its reconcile)
  run kubectl --context=k3d-spoke-capsule apply -f "$PROBE"
  rm -f "$PROBE"
  if [ "$status" -ne 0 ]; then
    # Apiserver-side admission rejection MUST cite cross-namespace explicitly
    echo "$output" | grep -qE 'cross-namespace' || {
      echo "N9 FAIL: apiserver rejected probe but reason was not cross-namespace: $output"
      return 1
    }
    return 0
  fi
  # Otherwise wait up to 90s for Flux to surface the denial in the Kustomization status
  for i in 1 2 3; do
    READY=$(kubectl --context=k3d-spoke-capsule get kustomization probe-n9-cross-tenant -n tenant-alpha \
      -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null || true)
    # Require the explicit "cross-namespace" keyword
    # (drop permissive "not allowed" / "namespace .* not allowed" substring -- those could
    # match unrelated denials).
    if echo "$READY" | grep -qE 'cross-namespace'; then
      kubectl --context=k3d-spoke-capsule delete kustomization probe-n9-cross-tenant -n tenant-alpha --ignore-not-found >/dev/null 2>&1 || true
      return 0
    fi
    [ "$i" -lt 3 ] && sleep 30
  done
  kubectl --context=k3d-spoke-capsule delete kustomization probe-n9-cross-tenant -n tenant-alpha --ignore-not-found >/dev/null 2>&1 || true
  echo "Last observed Ready message: '$READY'"
  return 1
}

@test "N10 -- tenant Kustomization without spec.serviceAccountName falls through to no-permission default SA (--default-service-account=default); REVISED RBAC-keyword assertion" {
  # The probe Kustomization references a VALID sourceRef (the `tenant-alpha-source`
  # GitRepository). The ONLY failing variable is the missing spec.serviceAccountName.
  # Under the hub lockdown (--default-service-account=default), Flux falls
  # through to the `default` SA in tenant-alpha (zero permissions). Failure message MUST
  # reference RBAC (e.g., system:serviceaccount:tenant-alpha:default + forbidden), NOT
  # "source not found".
  PROBE=$(mktemp -p "${TMPDIR:-/tmp}" karyon-bats-n10-no-sa-XXXX.yaml)
  cat > "$PROBE" <<EOF
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: probe-n10-no-sa
  namespace: tenant-alpha
spec:
  interval: 1m
  path: ./
  prune: false
  sourceRef:
    kind: GitRepository
    name: tenant-alpha-source
EOF
  run kubectl --context=k3d-spoke-capsule apply -f "$PROBE"
  rm -f "$PROBE"
  [ "$status" -eq 0 ]
  for i in 1 2 3; do
    READY=$(kubectl --context=k3d-spoke-capsule get kustomization probe-n10-no-sa -n tenant-alpha \
      -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null || true)
    # POSITIVE assertion -- RBAC keyword present
    # AND NEGATIVE assertion -- "source not found" MUST NOT appear (otherwise the test
    # would pass for the wrong reason: a missing source rather than a no-permission default SA).
    if echo "$READY" | grep -qE '(system:serviceaccount:tenant-alpha:default|default.*tenant-alpha)' \
       && echo "$READY" | grep -qE '(forbidden|Forbidden|cannot)' \
       && ! echo "$READY" | grep -qE '(source not found|GitRepository.*not found)'; then
      kubectl --context=k3d-spoke-capsule delete kustomization probe-n10-no-sa -n tenant-alpha --ignore-not-found >/dev/null 2>&1 || true
      return 0
    fi
    [ "$i" -lt 3 ] && sleep 30
  done
  kubectl --context=k3d-spoke-capsule delete kustomization probe-n10-no-sa -n tenant-alpha --ignore-not-found >/dev/null 2>&1 || true
  echo "Last observed Ready message: '$READY'"
  echo "N10 FAIL: expected RBAC denial against system:serviceaccount:tenant-alpha:default; observed message did not match positive RBAC-keyword + non-source-not-found gate"
  return 1
}
