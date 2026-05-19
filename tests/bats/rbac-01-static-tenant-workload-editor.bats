#!/usr/bin/env bats
# tests/bats/rbac-01-static-tenant-workload-editor.bats
# Phase 13 / Wave 0 (D-13-15 Nyquist gate)
# RBAC-01 — ClusterRole shape static contract (D-13-04).
# Positive grants + 4 explicit denial categories + Pitfall 13-P3 aggregate-to anti-pattern.
# RED until Plan 13-01 lands tenant-workload-editor.yaml.

load 'test_helper'

setup() {
  F="${REPO_ROOT}/pocs/capsule/spoke/rbac/tenant-workload-editor.yaml"
}

@test "RBAC-01 / D-13-04: tenant-workload-editor.yaml exists at pocs/capsule/spoke/rbac/" {
  [ -f "$F" ]
}

@test "RBAC-01 / D-13-04: kind == ClusterRole and metadata.name == tenant-workload-editor" {
  [ -f "$F" ]
  run yq eval '.kind' "$F"
  [ "$status" -eq 0 ]
  [ "$output" = "ClusterRole" ]
  run yq eval '.metadata.name' "$F"
  [ "$status" -eq 0 ]
  [ "$output" = "tenant-workload-editor" ]
}

@test "RBAC-01 / D-13-04 (positive): rules grant pods create/list/watch/get/update/patch/delete" {
  [ -f "$F" ]
  for verb in create list watch get update patch delete; do
    run yq eval "[.rules[] | select((.apiGroups | contains([\"\"])) and (.resources | contains([\"pods\"]))) | .verbs] | flatten | any_c(. == \"${verb}\")" "$F"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
  done
}

@test "RBAC-01 / D-13-04 (positive): rules grant pods/log get" {
  [ -f "$F" ]
  run yq eval '[.rules[] | select((.apiGroups | contains([""])) and (.resources | contains(["pods/log"]))) | .verbs] | flatten | any_c(. == "get")' "$F"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "RBAC-01 / D-13-04 (positive): rules grant pods/exec create" {
  [ -f "$F" ]
  run yq eval '[.rules[] | select((.apiGroups | contains([""])) and (.resources | contains(["pods/exec"]))) | .verbs] | flatten | any_c(. == "create")' "$F"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "RBAC-01 / D-13-04 (positive): rules grant pods/portforward create" {
  [ -f "$F" ]
  run yq eval '[.rules[] | select((.apiGroups | contains([""])) and (.resources | contains(["pods/portforward"]))) | .verbs] | flatten | any_c(. == "create")' "$F"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "RBAC-01 / D-13-04 (positive): rules grant deployments (apps) CRUD" {
  [ -f "$F" ]
  for verb in create get list watch update patch delete; do
    run yq eval "[.rules[] | select((.apiGroups | contains([\"apps\"])) and (.resources | contains([\"deployments\"]))) | .verbs] | flatten | any_c(. == \"${verb}\")" "$F"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
  done
}

@test "RBAC-01 / D-13-04 (positive): rules grant services (core) CRUD" {
  [ -f "$F" ]
  for verb in create get list watch update patch delete; do
    run yq eval "[.rules[] | select((.apiGroups | contains([\"\"])) and (.resources | contains([\"services\"]))) | .verbs] | flatten | any_c(. == \"${verb}\")" "$F"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
  done
}

@test "RBAC-01 / D-13-04 (positive): rules grant configmaps (core) CRUD" {
  [ -f "$F" ]
  for verb in create get list watch update patch delete; do
    run yq eval "[.rules[] | select((.apiGroups | contains([\"\"])) and (.resources | contains([\"configmaps\"]))) | .verbs] | flatten | any_c(. == \"${verb}\")" "$F"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
  done
}

@test "RBAC-01 / D-13-04 (positive): rules grant persistentvolumeclaims get/list/watch (read-only)" {
  [ -f "$F" ]
  for verb in get list watch; do
    run yq eval "[.rules[] | select((.apiGroups | contains([\"\"])) and (.resources | contains([\"persistentvolumeclaims\"]))) | .verbs] | flatten | any_c(. == \"${verb}\")" "$F"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
  done
}

@test "RBAC-01 / D-13-01 (positive read-only): rules grant secrets get/list/watch" {
  [ -f "$F" ]
  for verb in get list watch; do
    run yq eval "[.rules[] | select((.apiGroups | contains([\"\"])) and (.resources | contains([\"secrets\"]))) | .verbs] | flatten | any_c(. == \"${verb}\")" "$F"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
  done
}

@test "RBAC-01 / D-13-01 (denial): rules MUST NOT grant secrets create" {
  [ -f "$F" ]
  run yq eval '[.rules[] | select(.resources | contains(["secrets"])) | .verbs] | flatten | any_c(. == "create")' "$F"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "RBAC-01 / D-13-01 (denial): rules MUST NOT grant secrets update" {
  [ -f "$F" ]
  run yq eval '[.rules[] | select(.resources | contains(["secrets"])) | .verbs] | flatten | any_c(. == "update")' "$F"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "RBAC-01 / D-13-01 (denial): rules MUST NOT grant secrets patch" {
  [ -f "$F" ]
  run yq eval '[.rules[] | select(.resources | contains(["secrets"])) | .verbs] | flatten | any_c(. == "patch")' "$F"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "RBAC-01 / D-13-01 (denial): rules MUST NOT grant secrets delete" {
  [ -f "$F" ]
  run yq eval '[.rules[] | select(.resources | contains(["secrets"])) | .verbs] | flatten | any_c(. == "delete")' "$F"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "RBAC-01 / D-13-04 (denial): rules MUST NOT mention rolebindings" {
  [ -f "$F" ]
  run yq eval '[.rules[].resources // []] | flatten | any_c(. == "rolebindings")' "$F"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "RBAC-01 / D-13-04 (denial): rules MUST NOT mention roles (rbac.authorization.k8s.io)" {
  [ -f "$F" ]
  run yq eval '[.rules[].resources // []] | flatten | any_c(. == "roles")' "$F"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "RBAC-01 / D-13-04 (denial): rules MUST NOT mention resourcequotas" {
  [ -f "$F" ]
  run yq eval '[.rules[].resources // []] | flatten | any_c(. == "resourcequotas")' "$F"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "RBAC-01 / D-13-04 (denial): rules MUST NOT mention limitranges" {
  [ -f "$F" ]
  run yq eval '[.rules[].resources // []] | flatten | any_c(. == "limitranges")' "$F"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "RBAC-01 / D-13-04 (denial): rules MUST NOT mention nodes" {
  [ -f "$F" ]
  run yq eval '[.rules[].resources // []] | flatten | any_c(. == "nodes")' "$F"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "RBAC-01 / D-13-04 (denial): rules MUST NOT mention customresourcedefinitions" {
  [ -f "$F" ]
  run yq eval '[.rules[].resources // []] | flatten | any_c(. == "customresourcedefinitions")' "$F"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "RBAC-01 / D-13-04 (denial): rules MUST NOT mention tenants (capsule.clastix.io Tier-2 surface)" {
  [ -f "$F" ]
  run yq eval '[.rules[].resources // []] | flatten | any_c(. == "tenants")' "$F"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "RBAC-01 / Pitfall 13-P3 (anti-pattern): MUST NOT carry aggregate-to-* labels (no surprise inheritance)" {
  [ -f "$F" ]
  # Filter comments first to avoid self-invalidating grep gate (this bats file
  # itself contains 'aggregate-to-' in this comment block).
  run bash -c "grep -v '^[[:space:]]*#' '$F' | grep -F 'aggregate-to-'"
  [ "$status" -ne 0 ]
}
