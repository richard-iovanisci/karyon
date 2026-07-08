#!/usr/bin/env bats
# tests/bats/capsule-install-08-live-proxy-reachable.bats
# Live NodePort 30443 reachability.
# Asserts TLS handshake succeeds + HTTP code matches [1-5][0-9][0-9] (NOT literal 200 on /healthz —
# that endpoint is on the unexposed probe port 8081 per the chart's Service shape).
# Cluster-info gate — auto-skips when the cluster is unreachable.

load 'test_helper'

setup() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
}

@test "CAP-02 live: capsule-proxy reachable from WSL host (TLS handshake + HTTP code in [1-5][0-9][0-9])" {
  local code
  code=$(curl -k -s -o /dev/null -w '%{http_code}' --max-time 5 \
    https://127.0.0.1:30443/api 2>/dev/null) || true
  # Acceptable: 401 (no token), 403 (denied), 404 (path), 200 (proxied),
  # 502 (apiserver upstream issue). Unacceptable: 000 (TLS handshake failed),
  # 7 (connection refused), curl exit non-zero with no code.
  [[ "$code" =~ ^[1-5][0-9][0-9]$ ]]
}

@test "CAP-02 live: TCP port 30443 is bound on 127.0.0.1 (k3d serverlb host-publish from Phase 7 D-10)" {
  run bash -c "(echo > /dev/tcp/127.0.0.1/30443) 2>/dev/null"
  [ "$status" -eq 0 ]
}
