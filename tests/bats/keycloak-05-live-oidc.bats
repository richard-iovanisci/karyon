#!/usr/bin/env bats
# tests/bats/keycloak-05-live-oidc.bats
# tenant-ui-oidc quick task — live falsifiers for the OIDC wiring + Headlamp.
# Auto-skips when the cluster or the imperative pieces are absent.

load 'test_helper'

setup() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
}

@test "oidc-live: keycloak-oidc NodePort 31443 exists" {
  run kubectl --context=k3d-spoke-capsule -n keycloak get svc keycloak-oidc \
    -o jsonpath='{.spec.ports[0].nodePort}'
  [ "$status" -eq 0 ]
  [ "$output" = "31443" ]
}

@test "oidc-live: forwarder container serves the pinned issuer from the host" {
  [ -f "${HOME}/.karyon/oidc-pki/ca.crt" ] || skip "OIDC PKI absent; run create-tls.sh + start-oidc-forwarder.sh"
  run bash -c "curl -s --max-time 5 --cacert '${HOME}/.karyon/oidc-pki/ca.crt' https://localhost:31443/realms/karyon/.well-known/openid-configuration | grep -o '\"issuer\":\"[^\"]*\"'"
  [ "$status" -eq 0 ]
  [ "$output" = '"issuer":"https://localhost:31443/realms/karyon"' ]
}

@test "oidc-live: apiserver runs all 6 oidc flags (k3s log line — ps cannot see them)" {
  command -v docker >/dev/null 2>&1 || skip "docker unavailable"
  run bash -c "docker logs k3d-spoke-capsule-server-0 2>&1 | grep 'Running kube-apiserver' | tail -1 | tr ' ' '\n' | grep -c oidc"
  [ "$status" -eq 0 ]
  [ "$output" = "6" ]
}

@test "oidc-live: headlamp Deployment Available in capsule-system" {
  run kubectl --context=k3d-spoke-capsule -n capsule-system get deployment headlamp \
    -o jsonpath='{.status.conditions[?(@.type=="Available")].status}'
  [ "$status" -eq 0 ]
  [ "$output" = "True" ]
}

@test "oidc-live: headlamp reports auth_type oidc against the capsule-proxy endpoint" {
  # /config via the apiserver service proxy — no port-forward needed.
  run kubectl --context=k3d-spoke-capsule -n capsule-system get --raw \
    "/api/v1/namespaces/capsule-system/services/headlamp:80/proxy/config"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF '"auth_type":"oidc"'
  echo "$output" | grep -qF 'capsule-proxy.capsule-system.svc:9001'
}

@test "oidc-live: e2e chain — OIDC tokens yield tenant-scoped LISTs through capsule-proxy" {
  [ -f "${HOME}/.karyon/demo-credentials.txt" ] || skip "demo credentials absent; run e2e-oidc-test.sh once"
  run bash "${REPO_ROOT}/scripts/poc/keycloak/e2e-oidc-test.sh"
  [ "$status" -eq 0 ]
}
