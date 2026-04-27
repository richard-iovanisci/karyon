#!/usr/bin/env bats
# tests/bats/register-spokes-02-live.bats
# Destructive live contract for Phase 4 (spoke registration). All @tests are
# gated by two env vars: KARYON_LIVE_TESTS=1 and KARYON_LIVE_TESTS_DESTRUCTIVE=1.
#
# Preconditions for these to PASS:
#   1. scripts/register-spokes-for-flux.sh has been run successfully on a
#      live three-cluster k3d topology (k3d-hub-flux + k3d-spoke-ml + k3d-spoke-apps).
#   2. The user has committed AND pushed the Phase-4 changes:
#        - clusters/hub-flux/spokes/{kustomization,spoke-ml,spoke-apps}.yaml
#        - clusters/hub-flux/flux-system/kustomization.yaml (with - ../spokes patch)
#        - clusters/spoke-ml/{kustomization,namespace,configmap}.yaml
#        - clusters/spoke-apps/{kustomization,namespace,configmap}.yaml
#   3. Flux has reconciled - typically 1-2 minutes after push, OR after
#      `flux reconcile source git flux-system && flux reconcile kustomization flux-system`.
#
# If preconditions are not met, the @tests will fail loudly. The setup() runs
# the live/destructive gate first (skips cleanly if env vars unset) and then
# detects the unpushed-commits case and skip-with-message (RESEARCH.md Q4).
#
# Inventory ID format (RESEARCH.md Sources, verified live):
#   <namespace>_<name>_<group>_<kind>
# For core-API ConfigMap (empty group), this is:
#   karyon-spoke-ml_karyon-spoke-id__ConfigMap   (literal double-underscore)
#   karyon-spoke-apps_karyon-spoke-id__ConfigMap

load 'test_helper'

OPENSSL_PROBE_IMAGE="karyon/k3s-cuda:v1.34.6-k3s1-cuda12.8.1"

setup() {
  require_live_destructive

  # Review feedback: detect both uncommitted and committed-but-unpushed changes
  # under the Phase-4 tree and skip-with-message. The test is not broken; Flux
  # cannot reconcile local-only state.
  local phase_paths=(
    clusters/hub-flux/spokes
    clusters/hub-flux/flux-system/kustomization.yaml
    clusters/spoke-ml
    clusters/spoke-apps
    scripts/register-spokes-for-flux.sh
    tests/bats/register-spokes-01-static.bats
    tests/bats/register-spokes-02-live.bats
  )
  local dirty
  # shellcheck disable=SC2015 # In Bats this intentionally falls back to true on git/status errors.
  dirty="$(cd "${REPO_ROOT}" && git status --porcelain -- "${phase_paths[@]}" 2>/dev/null || true)"
  if [[ -n "${dirty}" ]]; then
    skip "Phase 4 has uncommitted local changes under the reconciliation tree. Commit and push them, then wait 1-2 min for Flux to reconcile (or run: flux --context k3d-hub-flux reconcile source git flux-system && flux --context k3d-hub-flux reconcile kustomization flux-system), then rerun this test."
  fi

  local ahead
  ahead="$(cd "${REPO_ROOT}" && git rev-list --count origin/main..HEAD -- \
    "${phase_paths[@]}" \
    2>/dev/null || echo 0)"
  if [[ "${ahead}" -gt 0 ]]; then
    skip "Phase 4 has ${ahead} committed-but-unpushed commits under the reconciliation tree. Push to origin/main and wait 1-2 min for Flux to reconcile (or run: flux --context k3d-hub-flux reconcile source git flux-system && flux --context k3d-hub-flux reconcile kustomization flux-system), then rerun this test."
  fi
}

teardown() {
  :
}

delete_openssl_probe_pod() {
  local pod="$1"
  kubectl --context k3d-hub-flux -n flux-system delete pod "$pod" \
    --ignore-not-found --grace-period=0 --force --wait=true >/dev/null 2>&1 || true
}

run_openssl_tls_probe() {
  local spoke="$1" ca_pem="$2"
  local pod="karyon-openssl-probe-${spoke}-bats-$$"
  local ca_file="/tmp/karyon-${spoke}-ca.crt"
  local out_file="/tmp/karyon-${spoke}-tls.out"
  local tls_ok=0

  if kubectl --context k3d-hub-flux -n flux-system exec deploy/kustomize-controller -- \
      /bin/sh -c 'command -v openssl >/dev/null 2>&1' >/dev/null 2>&1; then
    printf '%s\n' "$ca_pem" |
      kubectl --context k3d-hub-flux -n flux-system exec -i deploy/kustomize-controller -- \
        /bin/sh -c "cat > '${ca_file}'"
    for _ in 1 2; do
      if kubectl --context k3d-hub-flux -n flux-system exec deploy/kustomize-controller -- \
          /bin/sh -c "openssl s_client -brief -verify_return_error -verify_hostname k3d-${spoke}-server-0 -CAfile '${ca_file}' -connect k3d-${spoke}-server-0:6443 </dev/null >'${out_file}' 2>&1"; then
        tls_ok=1
        break
      fi
      sleep 1
    done
    kubectl --context k3d-hub-flux -n flux-system exec deploy/kustomize-controller -- \
      /bin/sh -c "rm -f '${ca_file}' '${out_file}'" >/dev/null 2>&1 || true
    [ "$tls_ok" -eq 1 ]
    return
  fi

  delete_openssl_probe_pod "$pod"
  kubectl --context k3d-hub-flux -n flux-system run "$pod" \
    --image="$OPENSSL_PROBE_IMAGE" \
    --image-pull-policy=Never \
    --restart=Never \
    --command -- sleep 3600 >/dev/null

  if ! kubectl --context k3d-hub-flux -n flux-system wait \
      --for=condition=Ready "pod/$pod" --timeout=20s >/dev/null 2>&1; then
    delete_openssl_probe_pod "$pod"
    docker image inspect "$OPENSSL_PROBE_IMAGE" >/dev/null 2>&1 || return 1
    k3d image import -c hub-flux "$OPENSSL_PROBE_IMAGE" >/dev/null || return 1
    kubectl --context k3d-hub-flux -n flux-system run "$pod" \
      --image="$OPENSSL_PROBE_IMAGE" \
      --image-pull-policy=Never \
      --restart=Never \
      --command -- sleep 3600 >/dev/null
    if ! kubectl --context k3d-hub-flux -n flux-system wait \
        --for=condition=Ready "pod/$pod" --timeout=60s >/dev/null; then
      delete_openssl_probe_pod "$pod"
      return 1
    fi
  fi

  printf '%s\n' "$ca_pem" |
    kubectl --context k3d-hub-flux -n flux-system exec -i "$pod" -- \
      /bin/sh -c "cat > '${ca_file}'"
  for _ in 1 2; do
    if kubectl --context k3d-hub-flux -n flux-system exec "$pod" -- \
        /bin/sh -c "openssl s_client -brief -verify_return_error -verify_hostname k3d-${spoke}-server-0 -CAfile '${ca_file}' -connect k3d-${spoke}-server-0:6443 </dev/null >'${out_file}' 2>&1"; then
      tls_ok=1
      break
    fi
    sleep 1
  done
  local rc=1
  [ "$tls_ok" -eq 1 ] && rc=0
  kubectl --context k3d-hub-flux -n flux-system exec "$pod" -- \
    /bin/sh -c "rm -f '${ca_file}' '${out_file}'" >/dev/null 2>&1 || true
  delete_openssl_probe_pod "$pod"
  return "$rc"
}

run_verified_https_probe() {
  local spoke="$1" token="$2" ca_pem="$3" path="$4"
  local pod="karyon-openssl-probe-${spoke}-https-bats-$$"
  local ca_file="/tmp/karyon-${spoke}-https-ca.crt"
  local host="k3d-${spoke}-server-0"
  local target="deploy/kustomize-controller"
  local output rc

  if ! kubectl --context k3d-hub-flux -n flux-system exec deploy/kustomize-controller -- \
      /bin/sh -c 'command -v openssl >/dev/null 2>&1' >/dev/null 2>&1; then
    delete_openssl_probe_pod "$pod"
    kubectl --context k3d-hub-flux -n flux-system run "$pod" \
      --image="$OPENSSL_PROBE_IMAGE" \
      --image-pull-policy=Never \
      --restart=Never \
      --command -- sleep 3600 >/dev/null
    if ! kubectl --context k3d-hub-flux -n flux-system wait \
        --for=condition=Ready "pod/$pod" --timeout=20s >/dev/null 2>&1; then
      delete_openssl_probe_pod "$pod"
      docker image inspect "$OPENSSL_PROBE_IMAGE" >/dev/null 2>&1 || return 1
      k3d image import -c hub-flux "$OPENSSL_PROBE_IMAGE" >/dev/null || return 1
      kubectl --context k3d-hub-flux -n flux-system run "$pod" \
        --image="$OPENSSL_PROBE_IMAGE" \
        --image-pull-policy=Never \
        --restart=Never \
        --command -- sleep 3600 >/dev/null
      if ! kubectl --context k3d-hub-flux -n flux-system wait \
          --for=condition=Ready "pod/$pod" --timeout=60s >/dev/null; then
        delete_openssl_probe_pod "$pod"
        return 1
      fi
    fi
    target="$pod"
  fi

  if ! printf '%s\n' "$ca_pem" |
      kubectl --context k3d-hub-flux -n flux-system exec -i "$target" -- \
        /bin/sh -c "cat > '${ca_file}'"; then
    [[ "$target" = "$pod" ]] && delete_openssl_probe_pod "$pod"
    return 1
  fi
  if output="$(
    printf 'GET %s HTTP/1.1\r\nHost: %s\r\nAuthorization: Bearer %s\r\nConnection: close\r\n\r\n' \
      "$path" "$host" "$token" |
      kubectl --context k3d-hub-flux -n flux-system exec -i "$target" -- \
        /bin/sh -c "openssl s_client -quiet -verify_return_error -verify_hostname '${host}' -CAfile '${ca_file}' -connect '${host}:6443' 2>/dev/null"
  )"; then
    rc=0
  else
    rc=$?
  fi
  kubectl --context k3d-hub-flux -n flux-system exec "$target" -- \
    /bin/sh -c "rm -f '${ca_file}'" >/dev/null 2>&1 || true
  [[ "$target" = "$pod" ]] && delete_openssl_probe_pod "$pod"
  printf '%s\n' "$output"
  return "$rc"
}

# ---- SPOKE-04: hub-side <spoke>-kubeconfig Secret has data.value.yaml populated ----

@test "SPOKE-04 (live): hub-side spoke-ml-kubeconfig Secret has data.value.yaml populated" {
  run kubectl --context k3d-hub-flux -n flux-system get secret spoke-ml-kubeconfig \
        -o jsonpath='{.data.value\.yaml}'
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "SPOKE-04 (live): hub-side spoke-apps-kubeconfig Secret has data.value.yaml populated" {
  run kubectl --context k3d-hub-flux -n flux-system get secret spoke-apps-kubeconfig \
        -o jsonpath='{.data.value\.yaml}'
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "SPOKE-04/06 (live): hub-side spoke-ml kubeconfig decodes with expected server, token, and CA matching the spoke token Secret" {
  local kubeconfig ca_from_kubeconfig ca_from_spoke token server
  kubeconfig="$(kubectl --context k3d-hub-flux -n flux-system get secret spoke-ml-kubeconfig -o jsonpath='{.data.value\.yaml}' | base64 -d)"
  server="$(printf '%s\n' "$kubeconfig" | yq eval '.clusters[0].cluster.server' -)"
  ca_from_kubeconfig="$(printf '%s\n' "$kubeconfig" | yq eval '.clusters[0].cluster.certificate-authority-data' -)"
  token="$(printf '%s\n' "$kubeconfig" | yq eval '.users[0].user.token' -)"
  ca_from_spoke="$(kubectl --context k3d-spoke-ml -n flux-system get secret flux-reconciler-token -o jsonpath='{.data.ca\.crt}')"
  [ "$server" = "https://k3d-spoke-ml-server-0:6443" ]
  [ -n "$token" ]
  [ -n "$ca_from_kubeconfig" ]
  printf '%s' "$ca_from_kubeconfig" | base64 -d >/dev/null
  [ "$ca_from_kubeconfig" = "$ca_from_spoke" ]
}

@test "SPOKE-04/06 (live): hub-side spoke-apps kubeconfig decodes with expected server, token, and CA matching the spoke token Secret" {
  local kubeconfig ca_from_kubeconfig ca_from_spoke token server
  kubeconfig="$(kubectl --context k3d-hub-flux -n flux-system get secret spoke-apps-kubeconfig -o jsonpath='{.data.value\.yaml}' | base64 -d)"
  server="$(printf '%s\n' "$kubeconfig" | yq eval '.clusters[0].cluster.server' -)"
  ca_from_kubeconfig="$(printf '%s\n' "$kubeconfig" | yq eval '.clusters[0].cluster.certificate-authority-data' -)"
  token="$(printf '%s\n' "$kubeconfig" | yq eval '.users[0].user.token' -)"
  ca_from_spoke="$(kubectl --context k3d-spoke-apps -n flux-system get secret flux-reconciler-token -o jsonpath='{.data.ca\.crt}')"
  [ "$server" = "https://k3d-spoke-apps-server-0:6443" ]
  [ -n "$token" ]
  [ -n "$ca_from_kubeconfig" ]
  printf '%s' "$ca_from_kubeconfig" | base64 -d >/dev/null
  [ "$ca_from_kubeconfig" = "$ca_from_spoke" ]
}

# ---- SPOKE-01 (live): spoke-side RBAC actually applied ----

@test "SPOKE-01 (live): k3d-spoke-ml has flux-reconciler SA + flux-reconciler-cluster-admin CRB" {
  run kubectl --context k3d-spoke-ml -n flux-system get serviceaccount flux-reconciler -o name
  [ "$status" -eq 0 ]
  [ "$output" = "serviceaccount/flux-reconciler" ]
  run kubectl --context k3d-spoke-ml get clusterrolebinding flux-reconciler-cluster-admin -o jsonpath='{.roleRef.name}'
  [ "$status" -eq 0 ]
  [ "$output" = "cluster-admin" ]
}

@test "SPOKE-01 (live): k3d-spoke-apps has flux-reconciler SA + flux-reconciler-cluster-admin CRB" {
  run kubectl --context k3d-spoke-apps -n flux-system get serviceaccount flux-reconciler -o name
  [ "$status" -eq 0 ]
  [ "$output" = "serviceaccount/flux-reconciler" ]
  run kubectl --context k3d-spoke-apps get clusterrolebinding flux-reconciler-cluster-admin -o jsonpath='{.roleRef.name}'
  [ "$status" -eq 0 ]
  [ "$output" = "cluster-admin" ]
}

# ---- SPOKE-02 (live): SA-token Secret data populated on each spoke ----

@test "SPOKE-02 (live): k3d-spoke-ml flux-reconciler-token Secret has data.token AND data.ca.crt" {
  run kubectl --context k3d-spoke-ml -n flux-system get secret flux-reconciler-token -o jsonpath='{.data.token}'
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  run kubectl --context k3d-spoke-ml -n flux-system get secret flux-reconciler-token -o jsonpath='{.data.ca\.crt}'
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "SPOKE-02 (live): k3d-spoke-apps flux-reconciler-token Secret has data.token AND data.ca.crt" {
  run kubectl --context k3d-spoke-apps -n flux-system get secret flux-reconciler-token -o jsonpath='{.data.token}'
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  run kubectl --context k3d-spoke-apps -n flux-system get secret flux-reconciler-token -o jsonpath='{.data.ca\.crt}'
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

# ---- SPOKE-05 (live): Kustomizations Ready=True post-push ----

@test "SPOKE-05 (live): spoke-ml Kustomization Ready=True (assumes user has pushed and Flux has reconciled)" {
  run kubectl --context k3d-hub-flux -n flux-system get kustomization spoke-ml \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
  [ "$status" -eq 0 ]
  [ "$output" = "True" ]
}

@test "SPOKE-05 (live): spoke-apps Kustomization Ready=True" {
  run kubectl --context k3d-hub-flux -n flux-system get kustomization spoke-apps \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
  [ "$status" -eq 0 ]
  [ "$output" = "True" ]
}

# ---- SPOKE-05 (live): .status.inventory contains seed ConfigMap (negative-proof of correct cluster) ----

@test "SPOKE-05 (live): spoke-ml inventory contains 'karyon-spoke-ml_karyon-spoke-id__ConfigMap' (literal double-underscore for core API)" {
  run bash -c "kubectl --context k3d-hub-flux -n flux-system get kustomization spoke-ml \
        -o json | jq -r '.status.inventory.entries[].id' \
        | grep -F 'karyon-spoke-ml_karyon-spoke-id__ConfigMap'"
  [ "$status" -eq 0 ]
}

@test "SPOKE-05 (live): spoke-apps inventory contains 'karyon-spoke-apps_karyon-spoke-id__ConfigMap'" {
  run bash -c "kubectl --context k3d-hub-flux -n flux-system get kustomization spoke-apps \
        -o json | jq -r '.status.inventory.entries[].id' \
        | grep -F 'karyon-spoke-apps_karyon-spoke-id__ConfigMap'"
  [ "$status" -eq 0 ]
}

# ---- ROADMAP success #5: cross-cluster ConfigMap falsifier (P18 catch-all) ----

@test "ROADMAP success #5: karyon-spoke-id ConfigMap exists on spoke-ml (NOT on hub) - proves correct routing" {
  # Negative: NOT on hub.
  run kubectl --context k3d-hub-flux -n karyon-spoke-ml get configmap karyon-spoke-id 2>&1
  [ "$status" -ne 0 ]
  # Positive: ON spoke-ml with data.spoke=spoke-ml.
  run kubectl --context k3d-spoke-ml -n karyon-spoke-ml get configmap karyon-spoke-id \
        -o jsonpath='{.data.spoke}'
  [ "$status" -eq 0 ]
  [ "$output" = "spoke-ml" ]
}

@test "ROADMAP success #5: karyon-spoke-id ConfigMap exists on spoke-apps (NOT on hub, NOT on spoke-ml under karyon-spoke-apps ns)" {
  # Negative: NOT on hub.
  run kubectl --context k3d-hub-flux -n karyon-spoke-apps get configmap karyon-spoke-id 2>&1
  [ "$status" -ne 0 ]
  # Negative: spoke-ml does NOT have a karyon-spoke-apps namespace.
  run kubectl --context k3d-spoke-ml -n karyon-spoke-apps get configmap karyon-spoke-id 2>&1
  [ "$status" -ne 0 ]
  # Positive: ON spoke-apps with data.spoke=spoke-apps.
  run kubectl --context k3d-spoke-apps -n karyon-spoke-apps get configmap karyon-spoke-id \
        -o jsonpath='{.data.spoke}'
  [ "$status" -eq 0 ]
  [ "$output" = "spoke-apps" ]
}

# ---- SPOKE-03/06 (live): in-pod TLS + auth + node-name probes for BOTH spokes ----
#
# RESEARCH.md adjustment: ghcr.io/fluxcd/kustomize-controller:v1.8.4 ships no kubectl.
# We exec into the pod and use openssl for the CA/TLS proof, bearer auth, and
# node-name negative-proof. Bearer material is sent over stdin, not argv.

@test "SPOKE-06 (live, in-pod): openssl validates spoke-ml CA and hostname from inside the hub cluster" {
  local ca_pem
  ca_pem="$(kubectl --context k3d-spoke-ml -n flux-system get secret flux-reconciler-token -o jsonpath='{.data.ca\.crt}' | base64 -d)"
  [ -n "$ca_pem" ]
  run run_openssl_tls_probe "spoke-ml" "$ca_pem"
  [ "$status" -eq 0 ]
}

@test "SPOKE-06 (live, in-pod): openssl validates spoke-apps CA and hostname from inside the hub cluster" {
  local ca_pem
  ca_pem="$(kubectl --context k3d-spoke-apps -n flux-system get secret flux-reconciler-token -o jsonpath='{.data.ca\.crt}' | base64 -d)"
  [ -n "$ca_pem" ]
  run run_openssl_tls_probe "spoke-apps" "$ca_pem"
  [ "$status" -eq 0 ]
}

@test "SPOKE-03/06 (live, in-pod): verified HTTPS probe reaches /readyz with each spoke bearer token" {
  local token_ml token_apps ca_ml ca_apps ready_ml ready_apps
  token_ml="$(kubectl --context k3d-spoke-ml -n flux-system get secret flux-reconciler-token -o jsonpath='{.data.token}' | base64 -d)"
  token_apps="$(kubectl --context k3d-spoke-apps -n flux-system get secret flux-reconciler-token -o jsonpath='{.data.token}' | base64 -d)"
  ca_ml="$(kubectl --context k3d-spoke-ml -n flux-system get secret flux-reconciler-token -o jsonpath='{.data.ca\.crt}' | base64 -d)"
  ca_apps="$(kubectl --context k3d-spoke-apps -n flux-system get secret flux-reconciler-token -o jsonpath='{.data.ca\.crt}' | base64 -d)"
  [ -n "$token_ml" ]
  [ -n "$token_apps" ]
  [ -n "$ca_ml" ]
  [ -n "$ca_apps" ]
  ready_ml="$(run_verified_https_probe "spoke-ml" "$token_ml" "$ca_ml" "/readyz")"
  ready_apps="$(run_verified_https_probe "spoke-apps" "$token_apps" "$ca_apps" "/readyz")"
  printf '%s\n' "$ready_ml" | tr -d '\r' | grep -qx 'ok'
  printf '%s\n' "$ready_apps" | tr -d '\r' | grep -qx 'ok'
}

@test "SPOKE-03/06 (live, in-pod): node-name negative-proof for both spokes" {
  local token_ml token_apps ca_ml ca_apps nodes_ml nodes_apps
  token_ml="$(kubectl --context k3d-spoke-ml -n flux-system get secret flux-reconciler-token -o jsonpath='{.data.token}' | base64 -d)"
  token_apps="$(kubectl --context k3d-spoke-apps -n flux-system get secret flux-reconciler-token -o jsonpath='{.data.token}' | base64 -d)"
  ca_ml="$(kubectl --context k3d-spoke-ml -n flux-system get secret flux-reconciler-token -o jsonpath='{.data.ca\.crt}' | base64 -d)"
  ca_apps="$(kubectl --context k3d-spoke-apps -n flux-system get secret flux-reconciler-token -o jsonpath='{.data.ca\.crt}' | base64 -d)"
  [ -n "$token_ml" ]
  [ -n "$token_apps" ]
  [ -n "$ca_ml" ]
  [ -n "$ca_apps" ]
  nodes_ml="$(run_verified_https_probe "spoke-ml" "$token_ml" "$ca_ml" "/api/v1/nodes")"
  nodes_apps="$(run_verified_https_probe "spoke-apps" "$token_apps" "$ca_apps" "/api/v1/nodes")"
  [[ "$nodes_ml" == *'"k3d-spoke-ml-server-0"'* ]]
  [[ "$nodes_apps" == *'"k3d-spoke-apps-server-0"'* ]]
  [[ "$nodes_ml" != *'"k3d-hub-flux-server-0"'* ]]
  [[ "$nodes_apps" != *'"k3d-hub-flux-server-0"'* ]]
}
