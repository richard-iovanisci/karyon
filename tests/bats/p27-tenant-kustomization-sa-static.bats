#!/usr/bin/env bats
# tests/bats/p27-tenant-kustomization-sa-static.bats
# Every Flux Kustomization under clusters/hub-flux/pocs/ MUST declare a non-empty
# spec.serviceAccountName. Without an explicit serviceAccountName, tenants run
# as the cluster-admin Flux SA and BYPASS Capsule entirely.
# tenants-02-static-p27.bats lints tenant inner Ks only -- this lint walks the
# FULL clusters/hub-flux/pocs/ tree.

load 'test_helper'

setup() {
  POCS_DIR="${REPO_ROOT}/clusters/hub-flux/pocs"
}

@test "P27 (D-09-08 inheritance): every Flux Kustomization under clusters/hub-flux/pocs/ declares non-empty spec.serviceAccountName" {
  [ -d "$POCS_DIR" ]
  # Walk every YAML file recursively under clusters/hub-flux/pocs/
  # For each YAML doc that has kind: Kustomization AND apiVersion starting with
  # `kustomize.toolkit.fluxcd.io/` (Flux Kustomization, NOT the kustomize-config
  # `kustomize.config.k8s.io/` aggregator -- that one has no spec.serviceAccountName field
  # and would always falsely "violate" the lint), assert spec.serviceAccountName is non-empty.
  # Use yq's multi-doc support (`-N -s` would split docs; here we use a per-file loop with
  # `eval-all 'select(.kind == "Kustomization" and (.apiVersion | test("^kustomize.toolkit.fluxcd.io/")))'`
  # to handle multi-doc YAML files and apiVersion-discriminate from kustomize-config aggregators).
  local violations=0
  while IFS= read -r yaml_file; do
    # Extract every Flux Kustomization doc + its serviceAccountName (or "MISSING")
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      # Format: name@namespace:saValue
      local sa="${line##*:}"
      local name_ns="${line%:*}"
      if [[ "$sa" == "MISSING" || "$sa" == "null" || -z "$sa" ]]; then
        echo "P27 VIOLATION: $yaml_file -- Kustomization $name_ns has empty/missing spec.serviceAccountName"
        violations=$((violations + 1))
      fi
    done < <(yq eval-all 'select(.kind == "Kustomization" and (.apiVersion | test("^kustomize.toolkit.fluxcd.io/"))) | (.metadata.name // "?") + "@" + (.metadata.namespace // "default") + ":" + (.spec.serviceAccountName // "MISSING")' "$yaml_file" 2>/dev/null || true)
  done < <(find "$POCS_DIR" -type f \( -name '*.yaml' -o -name '*.yml' \))
  [[ "$violations" -eq 0 ]] || { echo "TOTAL P27 VIOLATIONS: $violations"; return 1; }
}
