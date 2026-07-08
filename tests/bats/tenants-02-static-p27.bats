#!/usr/bin/env bats
# tests/bats/tenants-02-static-p27.bats
# LOAD-BEARING DEFENSE: explicit serviceAccountName on tenant Flux Kustomizations.
#
# Every tenant Flux Kustomization MUST set spec.serviceAccountName explicitly.
# Without it, kustomize-controller falls through to the kubeConfig Secret's principal
# (cluster-admin via spoke-capsule-kubeconfig), bypassing Capsule's tenant boundary
# entirely. The upstream kustomize_types.go KubeConfig field comment documents this
# fall-through behavior.
#
# This bats lints every multi-doc yaml under pocs/capsule/tenants/*.yaml and asserts
# every Flux Kustomization document has a non-null spec.serviceAccountName.
#
# A NEGATIVE FALSIFIER (synthetic broken fixture without serviceAccountName) is also
# tested below — it MUST FAIL the lint. If it ever passes, the lint logic is broken.

load 'test_helper'

# Lint loop is implemented as a callable bash function so the negative falsifier @test
# can invoke the same logic against the broken fixture. This is the load-bearing
# adapter pattern — the lint is identical for positive (real tenants) and negative
# (synthetic fixture) inputs.
#
# Function: lint_kustomization_sa_dir <directory>
#   For every *.yaml file in the directory, walks every multi-doc document.
#   For each document where kind == Kustomization AND apiVersion == kustomize.toolkit.fluxcd.io/v1,
#   asserts spec.serviceAccountName is set AND non-null AND non-empty.
#   Exits non-zero on the first violation; exits 0 if all docs pass.
#   If the directory has no matching Kustomization docs at all, exits non-zero
#   (so a directory with zero Kustomizations cannot vacuously pass).
lint_kustomization_sa_dir() {
  local dir="$1"
  local found_any=0
  shopt -s nullglob
  for f in "${dir}"/*.yaml "${dir}"/*.yml; do
    [ -f "$f" ] || continue
    # Walk every doc in the file. `yq eval` (per-doc) emits one TSV row per
    # YAML document; this is the per-doc iteration we want. NOTE: `yq eval-all`
    # would collapse all docs into a SINGLE flattened TSV row (tab-joining
    # fields across docs), defeating the per-doc lint loop — that is why this
    # uses `eval`, not `eval-all`.
    while IFS=$'\t' read -r kind apiv sa; do
      # Skip docs that aren't Flux v1 Kustomizations.
      [ "$kind" = "Kustomization" ] && [ "$apiv" = "kustomize.toolkit.fluxcd.io/v1" ] || continue
      found_any=1
      if [ -z "$sa" ] || [ "$sa" = "null" ]; then
        echo "P27 violation in ${f}: spec.serviceAccountName is '${sa}' (must be non-null)"
        return 1
      fi
    done < <(yq eval '[.kind // "", .apiVersion // "", .spec.serviceAccountName // ""] | @tsv' "$f" 2>/dev/null || true)
  done
  if [ "$found_any" -eq 0 ]; then
    echo "P27 lint found NO Flux Kustomization docs under ${dir} — cannot vacuously pass"
    return 1
  fi
  return 0
}

setup() {
  TENANTS_DIR="${REPO_ROOT}/pocs/capsule/tenants"
  BROKEN_FIXTURE_DIR="${REPO_ROOT}/tests/fixtures/p27-broken"
  export -f lint_kustomization_sa_dir 2>/dev/null || true
}

@test "P27 LOAD-BEARING / TEN-04: every Kustomization in pocs/capsule/tenants/*.yaml has non-null spec.serviceAccountName" {
  [ -d "$TENANTS_DIR" ]
  run lint_kustomization_sa_dir "$TENANTS_DIR"
  [ "$status" -eq 0 ]
}

@test "P27 negative falsifier: synthetic broken-fixture (no serviceAccountName) MUST FAIL the lint" {
  [ -d "$BROKEN_FIXTURE_DIR" ]
  # Run the SAME lint loop against the broken fixture and assert non-zero exit.
  # If this @test ever passes (i.e., lint exits 0 against the broken fixture),
  # the lint is silently broken and the serviceAccountName defense is compromised.
  run lint_kustomization_sa_dir "$BROKEN_FIXTURE_DIR"
  [ "$status" -ne 0 ]
}
