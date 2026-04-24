#!/usr/bin/env bats
# tests/bats/create-clusters-05-tls-san.bats
# Two-part check (CLU-05 / D-13): static-grep that scripts/create-clusters.sh uses --k3s-arg with --tls-san=k3d-${name}-server-0@server:* (NOT @server:0 per k3d issue #1613) AND L4 openssl probe that each apiserver cert carries DNS:k3d-<name>-server-0.
# Wave 0 stub — body filled by Plan 02-05.

load 'test_helper'

setup() {
  SCRIPT="${REPO_ROOT}/scripts/create-clusters.sh"
}

teardown() {
  :
}

@test "CLU-05: scripts/create-clusters.sh uses --k3s-arg --tls-san=k3d-NAME-server-0@server:* (wildcard nodefilter)" {
  run grep -F -- "--tls-san=k3d-\${name}-server-0@server:*" "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- "@server:0" "$SCRIPT"
  [ "$status" -ne 0 ]
}

@test "CLU-05 (live): hub-flux apiserver cert SAN includes k3d-hub-flux-server-0" {
  require_live
  run bash -c "openssl s_client -connect 127.0.0.1:6443 -servername k3d-hub-flux-server-0 </dev/null 2>/dev/null | openssl x509 -noout -text 2>/dev/null | grep -c 'DNS:k3d-hub-flux-server-0'"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}
