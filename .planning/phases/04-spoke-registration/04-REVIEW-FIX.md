---
phase: 04-spoke-registration
status: all_fixed
findings_in_scope: 3
fixed: 3
skipped: 0
iteration: 1
review_before: .planning/phases/04-spoke-registration/04-REVIEW.md
review_after: .planning/phases/04-spoke-registration/04-REVIEW.md
fixed_at: 2026-04-27T22:38:22Z
---

# Phase 04 Code Review Fix Report

## Summary

Resolved all findings from the Phase 04 code review and re-ran the same
standard review scope. The latest `04-REVIEW.md` is clean with 0 findings.

## Fixes Applied

### CR-01: Bearer-token probe handling

- Replaced `wget --no-check-certificate` bearer-token probes with verified
  `openssl s_client` HTTPS requests.
- The bearer token now travels in stdin through `kubectl exec -i`, not in the
  remote shell command argv.
- Updated static and live Bats coverage to reject `--no-check-certificate` for
  bearer-token probe paths.

Commit: `2d5a4c1`

### CR-02: Hub kustomization repair

- Replaced sentinel-only state detection with YAML-aware `yq` repair.
- The script now ensures `../spokes` is actually present in `.resources[]`,
  validates the repaired YAML, and preserves the sentinel comment.

Commit: `2d5a4c1`

### WR-01: Temporary OpenSSL probe cleanup

- Added a shared cleanup helper for temporary verifier pods.
- Wrapped fallback failure paths so probe pods are deleted when readiness,
  CA copy, or HTTPS probe execution fails.

Commit: `2d5a4c1`

## Verification

- `bash -n scripts/register-spokes-for-flux.sh`
- `shellcheck -e SC1091 scripts/register-spokes-for-flux.sh tests/bats/register-spokes-02-live.bats`
- `bats tests/bats/register-spokes-01-static.bats --tap`
- `bats tests/bats/bootstrap-flux-02-docs.bats --tap`
- `kubectl --context k3d-hub-flux kustomize clusters/hub-flux/`
- `bash scripts/register-spokes-for-flux.sh`
- Standard re-review of 17 Phase 04 files: clean

## Notes

The live destructive Bats suite must be rerun after the fix commit is pushed,
because its setup intentionally skips when Phase 04 reconciliation files are
committed locally but not yet present on `origin/main`.
