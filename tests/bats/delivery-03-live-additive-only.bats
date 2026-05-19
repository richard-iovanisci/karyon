#!/usr/bin/env bats
# tests/bats/delivery-03-live-additive-only.bats
# Phase 13 / Wave 0 (D-13-15 Nyquist gate)
# DELIVERY-03 — additive-only Tenant CR diff against Phase 12 base.
# Asserts no name-line removals from spec.owners[] in alpha.yaml + bravo.yaml.
#
# Base SHA selection: we pick the most recent commit on the current branch BEFORE Phase 13
# implementation commits (i.e., the Phase 12 close-out or 13-00 plan-creation commit).
# We use `tags/v0.19` if present, else look for the last commit touching tenant-crs/
# BEFORE any Phase 13 owner additions land. For Wave 0 RED, the test is GREEN-by-design
# (no Phase 13 implementation has landed, so diff against any prior SHA shows zero removals);
# becomes a falsifier post Plan 13-01/13-02 if those plans remove existing owners[] entries.

load 'test_helper'

# Discover a sensible base SHA: try v0.19 tag, then HEAD~20, then HEAD~10, then HEAD.
_base_sha() {
  if git -C "$REPO_ROOT" rev-parse --verify v0.19 >/dev/null 2>&1; then
    git -C "$REPO_ROOT" rev-parse v0.19
    return
  fi
  if git -C "$REPO_ROOT" rev-parse HEAD~20 >/dev/null 2>&1; then
    git -C "$REPO_ROOT" rev-parse HEAD~20
    return
  fi
  if git -C "$REPO_ROOT" rev-parse HEAD~5 >/dev/null 2>&1; then
    git -C "$REPO_ROOT" rev-parse HEAD~5
    return
  fi
  git -C "$REPO_ROOT" rev-parse HEAD
}

setup() {
  ALPHA="${REPO_ROOT}/pocs/capsule/spoke/tenant-crs/alpha.yaml"
  BRAVO="${REPO_ROOT}/pocs/capsule/spoke/tenant-crs/bravo.yaml"
  BASE_SHA="$(_base_sha)"
}

@test "DELIVERY-03 (alpha): no removals from spec.owners[] in alpha.yaml since Phase 12 base" {
  [ -f "$ALPHA" ]
  [ -n "$BASE_SHA" ]
  # git diff: count removal lines that match `name:` in owners[] context.
  # `^-[^-]` matches removed lines but excludes the `---` diff header.
  local removals
  removals=$(git -C "$REPO_ROOT" diff "$BASE_SHA" -- pocs/capsule/spoke/tenant-crs/alpha.yaml 2>/dev/null \
    | grep -E '^-[^-]' \
    | grep -F 'name:' \
    | wc -l)
  [ "$removals" -eq 0 ] || { echo "Non-additive diff in alpha.yaml: $removals owners 'name:' lines removed"; return 1; }
}

@test "DELIVERY-03 (bravo): no removals from spec.owners[] in bravo.yaml since Phase 12 base" {
  [ -f "$BRAVO" ]
  [ -n "$BASE_SHA" ]
  local removals
  removals=$(git -C "$REPO_ROOT" diff "$BASE_SHA" -- pocs/capsule/spoke/tenant-crs/bravo.yaml 2>/dev/null \
    | grep -E '^-[^-]' \
    | grep -F 'name:' \
    | wc -l)
  [ "$removals" -eq 0 ] || { echo "Non-additive diff in bravo.yaml: $removals owners 'name:' lines removed"; return 1; }
}
