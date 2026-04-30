#!/usr/bin/env bats
# tests/bats/tenants-08-live-quota-limit.bats
# Phase 9 / Wave 0 (D-09-08 Nyquist gate)
# TEN-03 — Capsule auto-materializes ResourceQuota + LimitRange in tenant namespaces.
# Plans 09-01..09-03 land the yaml that turns these GREEN.
#
# Verifies (per CONTEXT D-09-04 + RESEARCH §"Bats Coverage"):
#   - ResourceQuota auto-materializes in alpha-app1 namespace within 30s of namespace
#     creation (capsule-alpha-* names — Capsule controller naming convention)
#   - LimitRange auto-materializes in alpha-app1 namespace
#   - Mirror for bravo
#
# Auto-materialization is observed within ~5–10s on a healthy operator (per RESEARCH
# §"D-09-07 verifier path"). Use 3×10s polling to allow ≤30s reconcile latency.
# Depends on tenants-07 having created the alpha-app1 / bravo-app1 namespaces first.

load 'test_helper'

setup() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
}

# ---- alpha ----

@test "TEN-03 / D-09-04 (alpha): ResourceQuota auto-materializes in alpha-app1 namespace (capsule-alpha-* name, 3×10s poll)" {
  local i names
  for i in 1 2 3; do
    names=$(kubectl --context=k3d-spoke-capsule -n alpha-app1 get resourcequota -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)
    [[ "$names" == capsule-alpha-* ]] && return 0
    [[ $i -lt 3 ]] && sleep 10
  done
  echo "Last observed resourcequota names: '$names'"
  return 1
}

@test "TEN-03 / D-09-04 (alpha): LimitRange auto-materializes in alpha-app1 namespace (capsule-alpha-* name, 3×10s poll)" {
  local i names
  for i in 1 2 3; do
    names=$(kubectl --context=k3d-spoke-capsule -n alpha-app1 get limitrange -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)
    [[ "$names" == capsule-alpha-* ]] && return 0
    [[ $i -lt 3 ]] && sleep 10
  done
  echo "Last observed limitrange names: '$names'"
  return 1
}

# ---- bravo ----

@test "TEN-03 / D-09-04 (bravo): ResourceQuota auto-materializes in bravo-app1 namespace (capsule-bravo-* name, 3×10s poll)" {
  local i names
  for i in 1 2 3; do
    names=$(kubectl --context=k3d-spoke-capsule -n bravo-app1 get resourcequota -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)
    [[ "$names" == capsule-bravo-* ]] && return 0
    [[ $i -lt 3 ]] && sleep 10
  done
  echo "Last observed resourcequota names: '$names'"
  return 1
}

@test "TEN-03 / D-09-04 (bravo): LimitRange auto-materializes in bravo-app1 namespace (capsule-bravo-* name, 3×10s poll)" {
  local i names
  for i in 1 2 3; do
    names=$(kubectl --context=k3d-spoke-capsule -n bravo-app1 get limitrange -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)
    [[ "$names" == capsule-bravo-* ]] && return 0
    [[ $i -lt 3 ]] && sleep 10
  done
  echo "Last observed limitrange names: '$names'"
  return 1
}
