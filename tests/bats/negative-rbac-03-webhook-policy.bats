#!/usr/bin/env bats
# tests/bats/negative-rbac-03-webhook-policy.bats
# Phase 11 / Wave 0 (D-11-06 partition: N5 prefix, N6 quota, N7 registry).
# RED until Plan 11-03 turns these GREEN (after tenant.yaml namespaceOptions.quota + containerRegistries land).
# Pitfall 11-P3 permissive grep on N6 quota error.
# REVISED 2026-05-05: N6 idempotent precondition (delete leftover alpha- namespaces EXCEPT
# tenant-alpha + alpha-app1) per reviewer MEDIUM #7. Pitfall 11-P6 strict-mode env var.

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
  # REVISED 2026-05-05 (reviewer MEDIUM #7) -- N6 idempotent precondition.
  # Delete any leftover alpha-* namespaces from prior failed runs, EXCEPT:
  #   - tenant-alpha (the home namespace; created by Phase 9 D-09-02)
  #   - alpha-app1   (the Phase 9 TEN-02 fixture; required for N6 starting state of 2)
  # Without this cleanup, leftover alpha-app2/app3 from prior runs cause N6 false-pass
  # (already at quota on first iteration) or false-fail (3rd create unexpectedly succeeds).
  if kubectl --context=k3d-spoke-capsule get namespace alpha-app1 >/dev/null 2>&1; then
    LEFTOVERS=$(kubectl --context=k3d-spoke-capsule get ns -o name 2>/dev/null \
      | sed 's|namespace/||' \
      | grep -E '^alpha-' \
      | grep -vE '^(alpha-app1)$' \
      || true)
    if [[ -n "$LEFTOVERS" ]]; then
      echo "$LEFTOVERS" | while read -r ns; do
        [[ -z "$ns" ]] && continue
        kubectl --context=k3d-spoke-capsule delete namespace "$ns" --ignore-not-found --wait=true --timeout=60s >/dev/null 2>&1 || true
      done
    fi
  fi
}

teardown_file() {
  rm -rf "$KARYON_BATS_TMPDIR"
}

setup() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    _strict_skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
}

@test "N5 -- namespace prefix violation denied (forceTenantPrefix webhook)" {
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" create namespace evil-no-prefix
  [ "$status" -ne 0 ]
  echo "$output" | grep -qE "(prefix|forceTenantPrefix|tenant)"
  kubectl --context=k3d-spoke-capsule delete namespace evil-no-prefix --ignore-not-found >/dev/null 2>&1 || true
}

@test "N6 -- tenant quota violation denied (real CRUD probe; Pitfall 11-P3 permissive grep)" {
  # REVISED 2026-05-05 (reviewer MEDIUM #7): setup_file did the precondition cleanup.
  # Skip if alpha-app1 absent (Phase 9 TEN-02 fixture missing).
  if ! kubectl --context=k3d-spoke-capsule get namespace alpha-app1 >/dev/null 2>&1; then
    _strict_skip "alpha-app1 namespace absent (Phase 9 TEN-02 fixture missing); pre-create before re-running"
  fi
  # Tenant alpha quota = 3 (set in pocs/capsule/spoke/tenants/alpha/tenant.yaml via Plan 11-03)
  # Pre-state (post-cleanup): tenant-alpha (home) + alpha-app1 (Phase 9 TEN-02) = 2 namespaces
  # 3rd namespace (within quota) -- should succeed
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" create namespace alpha-app2
  [ "$status" -eq 0 ]
  # REVISED 2026-05-06 (Plan 11-03 Rule 1 auto-fix): Capsule's namespaces.projectcapsule.dev
  # webhook reads from tenant.status.size which is updated asynchronously by the controller.
  # Without a poll, rapid back-to-back CREATEs both succeed because the controller hasn't
  # reconciled status.size from 2 -> 3 yet (race condition observed in Plan 11-03 live run:
  # both alpha-app2 AND alpha-app3 created with quota=3). Poll up to 30s for status.size to
  # reflect the new namespace before attempting the 4th create.
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    SIZE=$(kubectl --context=k3d-spoke-capsule get tenant alpha -o jsonpath='{.status.size}' 2>/dev/null || echo "0")
    if [ "$SIZE" = "3" ]; then
      break
    fi
    [ "$i" -lt 15 ] && sleep 2
  done
  # 4th namespace (exceeds quota) -- should be rejected by Capsule webhook
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" create namespace alpha-app3
  [ "$status" -ne 0 ]
  echo "$output" | grep -qE "(quota|namespace.*(limit|max)|exceeded)"
  # Idempotent cleanup
  kubectl --kubeconfig="$ALPHA_KUBECONFIG" delete namespace alpha-app2 --ignore-not-found --wait=false >/dev/null 2>&1 || true
  kubectl --kubeconfig="$ALPHA_KUBECONFIG" delete namespace alpha-app3 --ignore-not-found --wait=false >/dev/null 2>&1 || true
}

@test "N7 -- denied registry pull (Capsule containerRegistries allowlist webhook)" {
  # alpha-app1 created by Phase 9 TEN-02. If absent (cluster reset), test skips below.
  if ! kubectl --context=k3d-spoke-capsule get namespace alpha-app1 >/dev/null 2>&1; then
    _strict_skip "alpha-app1 namespace absent (Phase 9 TEN-02 fixture missing); re-create before re-running"
  fi
  # Phase 13 (Plan 13-04 verifier Rule 1 - Bug):
  # Plan 13-01 additively added `docker.io` to alpha + bravo `containerRegistries.allowed[]`
  # (required so the GTR-propagated `docker.io/library/nginx:alpine` Pod is webhook-accepted
  # per Pitfall 13-P1). The N7 falsifier MUST pull from a registry NOT in `allowed[]` to
  # exercise the webhook. After Phase 13: `allowed[] = [registry.example.io, docker.io]`,
  # so `quay.io/library/nginx` is the canonical "different registry" probe. Phase 13 Plan
  # 13-01 Notable Observation #3 promised this non-regression — that promise is honored
  # here by retargeting the fixture to a registry still outside the allowlist.
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" run probe-n7 \
    --image=quay.io/library/nginx -n alpha-app1
  [ "$status" -ne 0 ]
  # REVISED 2026-05-05 (gsd-plan-checker BLOCKER 1): N7 falsifier validity tightening.
  # Capsule v0.12.4 deprecated `containerRegistries.allowed` in favor of
  # `Enforcement.Registries`. The deprecated form may not trigger the webhook reliably;
  # N7 may pass for unrelated reasons (e.g., a `forbidden` from RBAC). Tightening:
  #   1) POSITIVE: grep narrowed to `(registry|containerRegistries|registries)` ONLY.
  #      Dropped `allowed` and `forbidden` from the permissive set -- those words may
  #      appear in unrelated denial contexts (RBAC, NetworkPolicy, etc.).
  #   2) NEGATIVE (anti-RBAC-confusion): output MUST NOT contain `system:serviceaccount`,
  #      `RBAC`, or `cannot create resource`. Those strings would indicate an RBAC denial,
  #      NOT a Capsule webhook registry-allowlist denial. Pre-check in Plan 11-03 Step 1.5
  #      verifies the Capsule pods-CREATE webhook is registered; if absent, this @test is
  #      expected RED and Plan 11-04 disposition records it as a Rule 3 deviation.
  echo "$output" | grep -qE "(registry|containerRegistries|registries)"
  if echo "$output" | grep -qE "(system:serviceaccount|RBAC|cannot create resource)"; then
    echo "N7 ANTI-PATTERN: output matches RBAC-denial keywords -- this is NOT a registry-allowlist denial:"
    echo "$output"
    return 1
  fi
  kubectl --kubeconfig="$ALPHA_KUBECONFIG" delete pod probe-n7 -n alpha-app1 --ignore-not-found --wait=false >/dev/null 2>&1 || true
}
