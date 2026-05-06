#!/usr/bin/env bats
# tests/bats/push-gate-01-static-rbac-postbuild.bats
# Phase 11 D-11-01 -- capsule-proxy HelmRelease spec.postRenderers extends the
# chart-rendered Role capsule-proxy:capsule-proxy in capsule-system with secrets RBAC
# (so kube-webhook-certgen Job can write its output Secret on initial Flux reconcile).
#
# G-04 gap-close (2026-05-06): RELOCATED from the hub-targeted outer Flux
# Kustomization (clusters/hub-flux/pocs/capsule .yaml) spec.patches block --
# Kustomization patches only modify kustomize-build output, so they cannot reach
# helm-rendered Roles. New location is pocs/capsule/proxy/helmrelease.yaml
# spec.postRenderers (correct Flux mechanism for patching helm-rendered chart output).
# See Pitfall 11-P1.
#
# Plan 11-04 HARD-GATE 1 jq check against the LIVE chart-rendered Role remains
# the discriminating propagation test:
# kubectl get role capsule-proxy:capsule-proxy -o json | jq -e \
#   '.rules[] | select(.resources | contains(["secrets"])) | select(.verbs | contains(["create"]))'

load 'test_helper'

setup() {
  PROXY_HR="${REPO_ROOT}/pocs/capsule/proxy/helmrelease.yaml"
}

@test "D-11-01: proxy/helmrelease.yaml has spec.postRenderers targeting Role capsule-proxy:capsule-proxy in capsule-system" {
  [ -f "$PROXY_HR" ]
  run yq eval '(.spec.postRenderers // []) | .[0].kustomize.patches | map(select(.target.kind == "Role" and .target.name == "capsule-proxy:capsule-proxy" and .target.namespace == "capsule-system")) | length >= 1' "$PROXY_HR"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "D-11-01: proxy/helmrelease.yaml postRenderers patch literal includes secrets verb 'create' (so certgen Job can write Secret)" {
  [ -f "$PROXY_HR" ]
  run grep -F -- '"create"' "$PROXY_HR"
  [ "$status" -eq 0 ]
}
