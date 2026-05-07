#!/usr/bin/env bats
# tests/bats/capsule-platform-owner-02-live-rbac.bats
# Live smoke for the Capsule platform-owner RBAC spike.

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

  export PLATFORM_USER="capsule-platform-owner"
  export PLATFORM_GROUP="capsule-platform-owners"
  export PLATFORM_SMOKE_TENANT="platform-owner-smoke"
  export PLATFORM_SMOKE_OWNER="platform-lower-owner"
  export PLATFORM_SMOKE_NS="platform-owner-smoke-ns"

  kubectl --context=k3d-spoke-capsule delete namespace "${PLATFORM_SMOKE_NS}" --ignore-not-found --wait=false >/dev/null 2>&1 || true
  kubectl --context=k3d-spoke-capsule delete tenant "${PLATFORM_SMOKE_TENANT}" --ignore-not-found >/dev/null 2>&1 || true
}

teardown_file() {
  kubectl --context=k3d-spoke-capsule delete namespace "${PLATFORM_SMOKE_NS}" --ignore-not-found --wait=false >/dev/null 2>&1 || true
  kubectl --context=k3d-spoke-capsule delete tenant "${PLATFORM_SMOKE_TENANT}" --ignore-not-found >/dev/null 2>&1 || true
}

setup() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    _strict_skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
}

@test "platform-owner live: can read Capsule resources and tenant inventory" {
  run kubectl --context=k3d-spoke-capsule \
    --as="${PLATFORM_USER}" \
    --as-group="${PLATFORM_GROUP}" \
    get tenants.capsule.clastix.io -o name
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx 'tenant.capsule.clastix.io/alpha'
  echo "$output" | grep -qx 'tenant.capsule.clastix.io/bravo'

  run kubectl --context=k3d-spoke-capsule \
    --as="${PLATFORM_USER}" \
    --as-group="${PLATFORM_GROUP}" \
    get capsuleconfiguration.capsule.clastix.io default -o name
  [ "$status" -eq 0 ]
  [ "$output" = "capsuleconfiguration.capsule.clastix.io/default" ]

  run kubectl --context=k3d-spoke-capsule \
    --as="${PLATFORM_USER}" \
    --as-group="${PLATFORM_GROUP}" \
    get namespaces -l capsule.clastix.io/tenant -o name
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx 'namespace/tenant-alpha'
  echo "$output" | grep -qx 'namespace/tenant-bravo'
}

@test "platform-owner live: can create a lower-level Tenant and delegate namespace creation" {
  run bash -c "kubectl --context=k3d-spoke-capsule --as='${PLATFORM_USER}' --as-group='${PLATFORM_GROUP}' apply -f - <<'YAML'
apiVersion: capsule.clastix.io/v1beta2
kind: Tenant
metadata:
  name: ${PLATFORM_SMOKE_TENANT}
spec:
  forceTenantPrefix: false
  owners:
    - kind: User
      name: ${PLATFORM_SMOKE_OWNER}
YAML"
  [ "$status" -eq 0 ]

  run kubectl --context=k3d-spoke-capsule \
    --as="${PLATFORM_USER}" \
    --as-group="${PLATFORM_GROUP}" \
    get tenant "${PLATFORM_SMOKE_TENANT}" -o jsonpath='{.spec.owners[0].name}'
  [ "$status" -eq 0 ]
  [ "$output" = "${PLATFORM_SMOKE_OWNER}" ]

  run kubectl --context=k3d-spoke-capsule --as="${PLATFORM_SMOKE_OWNER}" create namespace "${PLATFORM_SMOKE_NS}"
  [ "$status" -eq 0 ]

  run kubectl --context=k3d-spoke-capsule get namespace "${PLATFORM_SMOKE_NS}" -o jsonpath='{.metadata.labels.capsule\.clastix\.io/tenant}'
  [ "$status" -eq 0 ]
  [ "$output" = "${PLATFORM_SMOKE_TENANT}" ]
}

@test "platform-owner live: is not cluster-admin and cannot read tenant Secrets" {
  run bash -c "kubectl --context=k3d-spoke-capsule auth can-i create clusterrolebindings.rbac.authorization.k8s.io \
    --as="${PLATFORM_USER}" \
    --as-group="${PLATFORM_GROUP}" 2>/dev/null"
  [ "$status" -ne 0 ]
  [ "$output" = "no" ]

  run bash -c "kubectl --context=k3d-spoke-capsule auth can-i get secrets --all-namespaces \
    --as="${PLATFORM_USER}" \
    --as-group="${PLATFORM_GROUP}" 2>/dev/null"
  [ "$status" -ne 0 ]
  [ "$output" = "no" ]
}
