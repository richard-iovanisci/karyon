#!/usr/bin/env bats
# tests/bats/register-spokes-01-static.bats
# Multi-part static contract for Phase 4 (spoke registration). Pins:
#   - SPOKE-01: scripts/register-spokes-for-flux.sh creates flux-reconciler SA + flux-reconciler-cluster-admin CRB
#   - SPOKE-02: legacy SA-token Secret 'flux-reconciler-token' with annotation kubernetes.io/service-account.name: flux-reconciler
#   - SPOKE-03: server URL literal https://k3d-${spoke}-server-0:6443 in script body
#   - SPOKE-04: 'value.yaml' key literal in script + each hub-side Kustomization YAML + doc (>=4 occurrences)
#   - SPOKE-05: each hub-side Kustomization YAML has spec.kubeConfig.secretRef.{name,key} and spec.path
#   - D-02:    flux-system/kustomization.yaml carries # KARYON SPOKES MOUNT sentinel + - ../spokes
#   - D-11:    set -euo pipefail present, set -x absent, token/kubeconfig data never logged, echoed, tee'd, or sent via --from-literal;
#              the one safe printf pipe into `kubectl create secret --from-file=value.yaml=/dev/stdin` is explicitly allowed.
#   - D-04:    no auto-push (no executable `git add`, `git commit`, or `git push` command in script body - comments + info-line text are exempt)
# All @tests are pure-static (grep/yq against committed files). The script + manifests + doc + patch
# arrive in Plans 04-02 / 04-03 / 04-04; this suite fails-closed until they do (TDD-style).

load 'test_helper'

setup() {
  SCRIPT="${REPO_ROOT}/scripts/register-spokes-for-flux.sh"
  SPOKE_ML_KS="${REPO_ROOT}/clusters/hub-flux/spokes/spoke-ml.yaml"
  SPOKE_APPS_KS="${REPO_ROOT}/clusters/hub-flux/spokes/spoke-apps.yaml"
  SPOKES_INDEX="${REPO_ROOT}/clusters/hub-flux/spokes/kustomization.yaml"
  HUB_FS_KUST="${REPO_ROOT}/clusters/hub-flux/flux-system/kustomization.yaml"
  DOC="${REPO_ROOT}/docs/flux-hub-spoke.md"
  TASKFILE="${REPO_ROOT}/Taskfile.yml"
}

teardown() {
  :
}

# ---- SPOKE-01: SA + CRB on each spoke ----

@test "SPOKE-01: scripts/register-spokes-for-flux.sh creates flux-reconciler ServiceAccount" {
  [ -f "$SCRIPT" ]
  run grep -F -- 'flux-reconciler' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- 'kind: ServiceAccount' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "SPOKE-01: scripts/register-spokes-for-flux.sh creates flux-reconciler-cluster-admin CRB bound to cluster-admin" {
  [ -f "$SCRIPT" ]
  run grep -F -- 'flux-reconciler-cluster-admin' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- 'name: cluster-admin' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- 'kind: ClusterRoleBinding' "$SCRIPT"
  [ "$status" -eq 0 ]
}

# ---- SPOKE-02: legacy SA-token Secret with annotation ----

@test "SPOKE-02: scripts/register-spokes-for-flux.sh creates flux-reconciler-token Secret of type kubernetes.io/service-account-token" {
  [ -f "$SCRIPT" ]
  run grep -F -- 'flux-reconciler-token' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- 'type: kubernetes.io/service-account-token' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "SPOKE-02: SA-token Secret carries kubernetes.io/service-account.name annotation (singular per k8s docs)" {
  [ -f "$SCRIPT" ]
  run grep -F -- 'kubernetes.io/service-account.name: flux-reconciler' "$SCRIPT"
  [ "$status" -eq 0 ]
}

# ---- SPOKE-03: server URL literal ----

@test "SPOKE-03: server URL literal https://k3d-\${spoke}-server-0:6443 in script body" {
  [ -f "$SCRIPT" ]
  # Match the literal pattern with bash-substitution placeholder. The script
  # builds the URL via "server=https://k3d-${spoke}-server-0:6443"; pin the
  # full literal so a future drift away from the Docker-DNS form is caught.
  run grep -F -- 'k3d-${spoke}-server-0:6443' "$SCRIPT"
  [ "$status" -eq 0 ]
}

# ---- SPOKE-04: value.yaml key literal in 4+ places ----

@test "SPOKE-04: value.yaml key literal in script body" {
  [ -f "$SCRIPT" ]
  run grep -F -- 'value.yaml' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "SPOKE-04: key: value.yaml in clusters/hub-flux/spokes/spoke-ml.yaml" {
  [ -f "$SPOKE_ML_KS" ]
  run grep -F -- 'key: value.yaml' "$SPOKE_ML_KS"
  [ "$status" -eq 0 ]
}

@test "SPOKE-04: key: value.yaml in clusters/hub-flux/spokes/spoke-apps.yaml" {
  [ -f "$SPOKE_APPS_KS" ]
  run grep -F -- 'key: value.yaml' "$SPOKE_APPS_KS"
  [ "$status" -eq 0 ]
}

@test "SPOKE-04: value.yaml literal in docs/flux-hub-spoke.md (Phase 4 section)" {
  [ -f "$DOC" ]
  run grep -F -- 'value.yaml' "$DOC"
  [ "$status" -eq 0 ]
}

# ---- SPOKE-05: hub-side Flux v1 Kustomization YAML shape ----

@test "SPOKE-05: clusters/hub-flux/spokes/spoke-ml.yaml is a Flux v1 Kustomization with spec.kubeConfig.secretRef" {
  [ -f "$SPOKE_ML_KS" ]
  run yq eval '.apiVersion == "kustomize.toolkit.fluxcd.io/v1" and .kind == "Kustomization" and .metadata.name == "spoke-ml" and .metadata.namespace == "flux-system" and .spec.path == "./clusters/spoke-ml" and .spec.kubeConfig.secretRef.name == "spoke-ml-kubeconfig" and .spec.kubeConfig.secretRef.key == "value.yaml"' "$SPOKE_ML_KS"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "SPOKE-05: clusters/hub-flux/spokes/spoke-apps.yaml is a Flux v1 Kustomization with spec.kubeConfig.secretRef" {
  [ -f "$SPOKE_APPS_KS" ]
  run yq eval '.apiVersion == "kustomize.toolkit.fluxcd.io/v1" and .kind == "Kustomization" and .metadata.name == "spoke-apps" and .metadata.namespace == "flux-system" and .spec.path == "./clusters/spoke-apps" and .spec.kubeConfig.secretRef.name == "spoke-apps-kubeconfig" and .spec.kubeConfig.secretRef.key == "value.yaml"' "$SPOKE_APPS_KS"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "SPOKE-05: clusters/hub-flux/spokes/kustomization.yaml lists spoke-ml.yaml and spoke-apps.yaml as resources" {
  [ -f "$SPOKES_INDEX" ]
  run yq eval '.apiVersion == "kustomize.config.k8s.io/v1beta1" and .kind == "Kustomization" and (.resources | length) == 2 and .resources[0] == "spoke-ml.yaml" and .resources[1] == "spoke-apps.yaml"' "$SPOKES_INDEX"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

# ---- D-02: sentinel-guarded patch in flux-system/kustomization.yaml ----

@test "D-02: clusters/hub-flux/flux-system/kustomization.yaml carries # KARYON SPOKES MOUNT sentinel and - ../spokes entry" {
  [ -f "$HUB_FS_KUST" ]
  run grep -F -- '# KARYON SPOKES MOUNT' "$HUB_FS_KUST"
  [ "$status" -eq 0 ]
  run grep -F -- '- ../spokes' "$HUB_FS_KUST"
  [ "$status" -eq 0 ]
  # Phase 3 sentinel must STILL be present (D-13 inheritance / non-regression):
  run grep -F -- '# FLUX PATCH SURFACE' "$HUB_FS_KUST"
  [ "$status" -eq 0 ]
}

# ---- D-11: strict mode + token safety ----

@test "D-11: scripts/register-spokes-for-flux.sh uses set -euo pipefail and does NOT use set -x" {
  [ -f "$SCRIPT" ]
  # Positive: strict mode line present.
  run grep -E '^set -euo pipefail' "$SCRIPT"
  [ "$status" -eq 0 ]
  # Negative: no `set -x` (or `set -eux`, `set -xe`, etc.) - D-11 forbids trace mode.
  # Filter comments first to avoid self-invalidating grep gate (header prose mentions set -x).
  run bash -c "grep -v '^[[:space:]]*#' '$SCRIPT' | grep -E '^[[:space:]]*set[[:space:]]+-[a-zA-Z]*x'"
  [ "$status" -ne 0 ]
}

@test "D-11 (token safety): token/kubeconfig data is never logged or literalized; only safe stdin Secret pipe is allowed" {
  [ -f "$SCRIPT" ]
  # Filter comments so the token-safety comment block does not self-invalidate the regex.
  # Allow the exact safe pipe into kubectl's stdin Secret creation path, then ban:
  #   - echo/printf of token, CA, or kubeconfig variables anywhere else
  #   - pass/info/warn/fail logging of those variables
  #   - tee and --from-literal, which can expose secret material in argv/stdout/history
  #   - set -x / shell tracing (covered by the prior @test)
  run bash -c '
    grep -v "^[[:space:]]*#" "$1" \
      | grep -vE "printf[[:space:]]+'\''%s\\\\n'\''[[:space:]]+\"\$\{kubeconfig_yaml\}\"[[:space:]]*\\\\?[|][[:space:]]*$" \
      | grep -Ei "(echo|printf)[[:space:]]+.*(token|kubeconfig|ca_b64|ca_data)|^[[:space:]]*(pass|info|warn|fail)[[:space:]]+.*(token|kubeconfig|ca_b64|ca_data)|tee[[:space:]]+|--from-literal"
  ' _ "$SCRIPT"
  [ "$status" -ne 0 ]
}

# ---- D-04: no auto-push from script body ----

@test "D-04: scripts/register-spokes-for-flux.sh does NOT mutate git (no executable git add/commit/push command in body)" {
  [ -f "$SCRIPT" ]
  # Filter comments and user-facing reminder lines. Negative match: literal executable git
  # mutation commands at start-of-line or after shell control operators.
  run bash -c "grep -v '^[[:space:]]*#' '$SCRIPT' | grep -vE '^[[:space:]]*(info|warn|pass)[[:space:]]' | grep -E '(^|[;&|])[[:space:]]*(command[[:space:]]+)?git[[:space:]]+(add|commit|push)\\b'"
  [ "$status" -ne 0 ]
}

# ---- D-13 / P18 defenses: skip-message literals and verification gates ----

@test "D-07/D-13: scripts/register-spokes-for-flux.sh contains an idempotency skip-message literal" {
  [ -f "$SCRIPT" ]
  # The script's per-spoke 3-part-AND skip OR the spokes-mount sentinel skip must use
  # the established 'already done, skipping:' literal (Phase 1/2/3 vocabulary).
  run grep -F -- 'already done, skipping:' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "D-13: scripts/register-spokes-for-flux.sh contains verified openssl HTTPS probes" {
  [ -f "$SCRIPT" ]
  # Bearer-token probes must use the same verified TLS connection that carries
  # the Authorization header. Do not allow wget --no-check-certificate here.
  run grep -F -- '--no-check-certificate' "$SCRIPT"
  [ "$status" -ne 0 ]
  run grep -F -- '/readyz' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- '/api/v1/nodes' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- 'openssl s_client -quiet -verify_return_error' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- '-verify_return_error' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "D-15 / P18 trip-wire: node-name negative-proof literal forbidden-node 'k3d-hub-flux-server-0' present in script" {
  [ -f "$SCRIPT" ]
  # The P18 silent-misroute check asserts node-name is k3d-${spoke}-server-0 AND NOT k3d-hub-flux-server-0.
  # Pin both literals.
  run grep -F -- 'k3d-hub-flux-server-0' "$SCRIPT"
  [ "$status" -eq 0 ]
}

# ---- Doc + Taskfile pinning ----

@test "DOCS-03 (Phase 4 section): docs/flux-hub-spoke.md no longer carries the Phase 4 stub comment" {
  [ -f "$DOC" ]
  # Phase 3 left the line: <!-- Phase 4: hub-spoke reconciliation ... -->
  # Phase 4 doc-fill (Plan 04-04) replaces that stub with a real ## Phase 4 section.
  run grep -F -- '<!-- Phase 4: hub-spoke reconciliation' "$DOC"
  [ "$status" -ne 0 ]
  # And the Phase 4 section heading is present:
  run grep -F -- '## Phase 4: Hub-spoke reconciliation' "$DOC"
  [ "$status" -eq 0 ]
}

@test "DOCS-03: docs/flux-hub-spoke.md Phase 4 section explains the P18 silent-misroute (spec.kubeConfig OMITTED is the real fault, per RESEARCH.md reframe)" {
  [ -f "$DOC" ]
  # P18 reframe: the silent-misroute is `spec.kubeConfig` block ENTIRELY ABSENT, not key typo.
  # The doc must mention this distinction.
  run grep -F -- 'spec.kubeConfig' "$DOC"
  [ "$status" -eq 0 ]
  run grep -iF -- 'silent' "$DOC"
  [ "$status" -eq 0 ]
}

@test "REPO-05 hand-off: Taskfile.yml has a register-spokes task entry (single-line bash invocation)" {
  [ -f "$TASKFILE" ]
  run grep -F -- 'register-spokes:' "$TASKFILE"
  [ "$status" -eq 0 ]
  run grep -F -- 'bash scripts/register-spokes-for-flux.sh' "$TASKFILE"
  [ "$status" -eq 0 ]
}

# ---- Spoke seed manifests ----

@test "SPOKE-05 (seed): clusters/spoke-ml has Namespace karyon-spoke-ml and ConfigMap karyon-spoke-id with data.spoke=spoke-ml" {
  [ -f "${REPO_ROOT}/clusters/spoke-ml/namespace.yaml" ]
  run grep -F -- 'name: karyon-spoke-ml' "${REPO_ROOT}/clusters/spoke-ml/namespace.yaml"
  [ "$status" -eq 0 ]
  [ -f "${REPO_ROOT}/clusters/spoke-ml/configmap.yaml" ]
  run grep -F -- 'name: karyon-spoke-id' "${REPO_ROOT}/clusters/spoke-ml/configmap.yaml"
  [ "$status" -eq 0 ]
  run grep -F -- 'spoke: spoke-ml' "${REPO_ROOT}/clusters/spoke-ml/configmap.yaml"
  [ "$status" -eq 0 ]
  [ -f "${REPO_ROOT}/clusters/spoke-ml/kustomization.yaml" ]
  run grep -F -- '- namespace.yaml' "${REPO_ROOT}/clusters/spoke-ml/kustomization.yaml"
  [ "$status" -eq 0 ]
  run grep -F -- '- configmap.yaml' "${REPO_ROOT}/clusters/spoke-ml/kustomization.yaml"
  [ "$status" -eq 0 ]
  run grep -F -- '../../examples/gpu-smoke-test' "${REPO_ROOT}/clusters/spoke-ml/kustomization.yaml"
  [ "$status" -eq 0 ]
}

@test "SPOKE-05 (seed): clusters/spoke-apps has Namespace karyon-spoke-apps and ConfigMap karyon-spoke-id with data.spoke=spoke-apps" {
  [ -f "${REPO_ROOT}/clusters/spoke-apps/namespace.yaml" ]
  run grep -F -- 'name: karyon-spoke-apps' "${REPO_ROOT}/clusters/spoke-apps/namespace.yaml"
  [ "$status" -eq 0 ]
  [ -f "${REPO_ROOT}/clusters/spoke-apps/configmap.yaml" ]
  run grep -F -- 'name: karyon-spoke-id' "${REPO_ROOT}/clusters/spoke-apps/configmap.yaml"
  [ "$status" -eq 0 ]
  run grep -F -- 'spoke: spoke-apps' "${REPO_ROOT}/clusters/spoke-apps/configmap.yaml"
  [ "$status" -eq 0 ]
  [ -f "${REPO_ROOT}/clusters/spoke-apps/kustomization.yaml" ]
  run grep -F -- '- namespace.yaml' "${REPO_ROOT}/clusters/spoke-apps/kustomization.yaml"
  [ "$status" -eq 0 ]
  run grep -F -- '- configmap.yaml' "${REPO_ROOT}/clusters/spoke-apps/kustomization.yaml"
  [ "$status" -eq 0 ]
  run grep -F -- '../../examples/podinfo' "${REPO_ROOT}/clusters/spoke-apps/kustomization.yaml"
  [ "$status" -eq 0 ]
}

@test "SPOKE-05 (seed repair): register script preserves existing spoke kustomization resources" {
  [ -f "$SCRIPT" ]
  run grep -F -- 'existing_resources=()' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- 'append_resource_once' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- 'in_resources && /^[[:space:]]*-[[:space:]]*/' "$SCRIPT"
  [ "$status" -eq 0 ]
}
