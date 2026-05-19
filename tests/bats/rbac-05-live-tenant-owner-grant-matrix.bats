#!/usr/bin/env bats
# tests/bats/rbac-05-live-tenant-owner-grant-matrix.bats
# Phase 13 / Wave 0 (D-13-15 Nyquist gate)
# RBAC-01 live grant matrix — positive grants + explicit denials via kubectl auth can-i.
# Tenant kubeconfigs minted via issue-tenant-kubeconfig.sh against the human-tenant-owner SA.
# RED until Plans 13-01..13-02 land (script + SA + ClusterRole + binding).

load 'test_helper'

setup_file() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
  export KARYON_BATS_TMPDIR="${TMPDIR:-/tmp}/karyon-tenants/bats-${BATS_RUN_TMPDIR##*/}"
  mkdir -p "$KARYON_BATS_TMPDIR"
  bash "${REPO_ROOT}/scripts/poc/capsule/issue-tenant-kubeconfig.sh" alpha human-tenant-owner \
    --duration=2h --write-to "${KARYON_BATS_TMPDIR}/alpha.kubeconfig" >/dev/null 2>&1
  bash "${REPO_ROOT}/scripts/poc/capsule/issue-tenant-kubeconfig.sh" bravo human-tenant-owner \
    --duration=2h --write-to "${KARYON_BATS_TMPDIR}/bravo.kubeconfig" >/dev/null 2>&1
  export ALPHA_KUBECONFIG="${KARYON_BATS_TMPDIR}/alpha.kubeconfig"
  export BRAVO_KUBECONFIG="${KARYON_BATS_TMPDIR}/bravo.kubeconfig"
}

teardown_file() {
  rm -rf "$KARYON_BATS_TMPDIR"
}

setup() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
  [ -f "${ALPHA_KUBECONFIG:-/dev/null}" ] || skip "alpha kubeconfig not minted (setup_file failed; expected RED pre-implementation)"
}

# ---- positive grants (alpha) ----

@test "RBAC-01 / D-13-04 (alpha positive): can create pods in tenant-alpha" {
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" auth can-i create pods -n tenant-alpha
  [ "$output" = "yes" ]
}

@test "RBAC-01 / D-13-04 (alpha positive): can get pods in tenant-alpha" {
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" auth can-i get pods -n tenant-alpha
  [ "$output" = "yes" ]
}

@test "RBAC-01 / D-13-04 (alpha positive): can list pods in tenant-alpha" {
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" auth can-i list pods -n tenant-alpha
  [ "$output" = "yes" ]
}

@test "RBAC-01 / D-13-04 (alpha positive): can watch pods in tenant-alpha" {
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" auth can-i watch pods -n tenant-alpha
  [ "$output" = "yes" ]
}

@test "RBAC-01 / D-13-04 (alpha positive): can create deployments in tenant-alpha" {
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" auth can-i create deployments -n tenant-alpha
  [ "$output" = "yes" ]
}

@test "RBAC-01 / D-13-04 (alpha positive): can create services in tenant-alpha" {
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" auth can-i create services -n tenant-alpha
  [ "$output" = "yes" ]
}

@test "RBAC-01 / D-13-04 (alpha positive): can create configmaps in tenant-alpha" {
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" auth can-i create configmaps -n tenant-alpha
  [ "$output" = "yes" ]
}

@test "RBAC-01 / D-13-04 (alpha positive): can list events in tenant-alpha" {
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" auth can-i list events -n tenant-alpha
  [ "$output" = "yes" ]
}

@test "RBAC-01 / D-13-04 (alpha positive): can get pods/log in tenant-alpha" {
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" auth can-i get pods/log -n tenant-alpha
  [ "$output" = "yes" ]
}

@test "RBAC-01 / D-13-04 (alpha positive): can create pods/exec in tenant-alpha" {
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" auth can-i create pods/exec -n tenant-alpha
  [ "$output" = "yes" ]
}

@test "RBAC-01 / D-13-04 (alpha positive): can get persistentvolumeclaims in tenant-alpha" {
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" auth can-i get persistentvolumeclaims -n tenant-alpha
  [ "$output" = "yes" ]
}

@test "RBAC-01 / D-13-04 (alpha positive): can list persistentvolumeclaims in tenant-alpha" {
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" auth can-i list persistentvolumeclaims -n tenant-alpha
  [ "$output" = "yes" ]
}

@test "RBAC-01 / D-13-01 (alpha positive read-only): can get secrets in tenant-alpha" {
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" auth can-i get secrets -n tenant-alpha
  [ "$output" = "yes" ]
}

@test "RBAC-01 / D-13-01 (alpha positive read-only): can list secrets in tenant-alpha" {
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" auth can-i list secrets -n tenant-alpha
  [ "$output" = "yes" ]
}

@test "RBAC-01 / D-13-01 (alpha positive read-only): can watch secrets in tenant-alpha" {
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" auth can-i watch secrets -n tenant-alpha
  [ "$output" = "yes" ]
}

# ---- denial verbs (alpha) ----

@test "RBAC-01 / D-13-01 (alpha denial): cannot create secrets in tenant-alpha" {
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" auth can-i create secrets -n tenant-alpha
  [ "$output" = "no" ]
}

@test "RBAC-01 / D-13-01 (alpha denial): cannot update secrets in tenant-alpha" {
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" auth can-i update secrets -n tenant-alpha
  [ "$output" = "no" ]
}

@test "RBAC-01 / D-13-01 (alpha denial): cannot patch secrets in tenant-alpha" {
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" auth can-i patch secrets -n tenant-alpha
  [ "$output" = "no" ]
}

@test "RBAC-01 / D-13-01 (alpha denial): cannot delete secrets in tenant-alpha" {
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" auth can-i delete secrets -n tenant-alpha
  [ "$output" = "no" ]
}

@test "RBAC-01 / D-13-04 (alpha denial): cannot create rolebindings in tenant-alpha" {
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" auth can-i create rolebindings -n tenant-alpha
  [ "$output" = "no" ]
}

@test "RBAC-01 / D-13-04 (alpha denial): cannot update roles in tenant-alpha" {
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" auth can-i update roles -n tenant-alpha
  [ "$output" = "no" ]
}

@test "RBAC-01 / D-13-04 (alpha denial): cannot create resourcequotas in tenant-alpha" {
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" auth can-i create resourcequotas -n tenant-alpha
  [ "$output" = "no" ]
}

@test "RBAC-01 / D-13-04 (alpha denial): cannot create limitranges in tenant-alpha" {
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" auth can-i create limitranges -n tenant-alpha
  [ "$output" = "no" ]
}

@test "RBAC-01 / D-13-04 (alpha denial): cannot create namespaces (cluster-scoped) as tenant-owner" {
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" auth can-i create namespaces
  [ "$output" = "no" ]
}

@test "RBAC-01 / D-13-04 (alpha denial): cannot create tenants.capsule.clastix.io" {
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" auth can-i create tenants.capsule.clastix.io
  [ "$output" = "no" ]
}

@test "RBAC-01 / D-13-04 (alpha denial): cannot get nodes" {
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" auth can-i get nodes
  [ "$output" = "no" ]
}

@test "RBAC-01 / D-13-04 (alpha denial): cannot create clusterrolebinding" {
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" auth can-i create clusterrolebinding
  [ "$output" = "no" ]
}

# ---- bravo (mirror; positive + denial sampled) ----

@test "RBAC-01 / D-13-04 (bravo positive): can create pods in tenant-bravo" {
  [ -f "${BRAVO_KUBECONFIG:-/dev/null}" ] || skip "bravo kubeconfig not minted"
  run kubectl --kubeconfig="$BRAVO_KUBECONFIG" auth can-i create pods -n tenant-bravo
  [ "$output" = "yes" ]
}

@test "RBAC-01 / D-13-04 (bravo positive): can get pods/log in tenant-bravo" {
  [ -f "${BRAVO_KUBECONFIG:-/dev/null}" ] || skip "bravo kubeconfig not minted"
  run kubectl --kubeconfig="$BRAVO_KUBECONFIG" auth can-i get pods/log -n tenant-bravo
  [ "$output" = "yes" ]
}

@test "RBAC-01 / D-13-01 (bravo denial): cannot create secrets in tenant-bravo" {
  [ -f "${BRAVO_KUBECONFIG:-/dev/null}" ] || skip "bravo kubeconfig not minted"
  run kubectl --kubeconfig="$BRAVO_KUBECONFIG" auth can-i create secrets -n tenant-bravo
  [ "$output" = "no" ]
}

@test "RBAC-01 / D-13-04 (bravo denial): cannot create rolebindings in tenant-bravo" {
  [ -f "${BRAVO_KUBECONFIG:-/dev/null}" ] || skip "bravo kubeconfig not minted"
  run kubectl --kubeconfig="$BRAVO_KUBECONFIG" auth can-i create rolebindings -n tenant-bravo
  [ "$output" = "no" ]
}
