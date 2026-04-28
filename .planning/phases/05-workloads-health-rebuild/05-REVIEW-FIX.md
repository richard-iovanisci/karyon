---
phase: 05-workloads-health-rebuild
source: 05-REVIEW.md
status: fixed
fixed_at: 2026-04-28T16:40:00Z
findings_fixed:
  critical: 4
  warning: 8
  total: 12
---

# Phase 05 Code Review Fix Summary

## Fixed Findings

- CR-01 / WR-02: `scripts/fix-coredns.sh` now treats failed post-restart spoke DNS probes as failures, and `tests/bats/fix-coredns-01-static.bats` pins the fail-closed behavior.
- CR-02 / WR-03: `scripts/rebuild.sh` now runs `scripts/preflight.sh` before `destroy`, and `tests/bats/destroy-rebuild-01-static.bats` pins preflight-before-destroy ordering.
- CR-03: `scripts/rebuild.sh` now rejects symlink or non-regular rebuild log paths before truncation, supports `KARYON_REBUILD_LOG_FILE`, and creates the log with `umask 077`.
- WR-01: `scripts/register-spokes-for-flux.sh` now preserves existing spoke Kustomization resources while appending required seed and example references. `tests/bats/register-spokes-01-static.bats` pins the merge-style repair path.

## Follow-up Warnings Fixed

- Re-review WR-01: `tests/bats/phase5-02-live.bats` now includes the `>>> step preflight` marker in the strict chain order check.
- Re-review WR-02: `scripts/rebuild.sh` now scopes `umask 077` to rebuild log creation and restores the previous umask before running the rebuild chain.
- Re-review WR-03: `scripts/register-spokes-for-flux.sh` now uses `yq eval '.resources[]?'` to read existing Kustomization resources instead of scraping YAML with `awk`.
- Re-review WR-04: `scripts/register-spokes-for-flux.sh` remediation text now uses a secret metadata/data-presence go-template instead of telling operators to dump kubeconfig Secret YAML.
- Re-review CR-01: `scripts/deploy-examples.sh` now fails closed if deleting the prior `gpu-smoke/nvidia-smi` Job fails; `--ignore-not-found` remains the only absent-job allowance.
- Re-review WR-01: `scripts/register-spokes-for-flux.sh` now captures `yq` output through a temporary file so invalid existing Kustomization YAML fails closed instead of being treated as an empty resource list.

## Verification

- `bash -n scripts/fix-coredns.sh scripts/rebuild.sh scripts/register-spokes-for-flux.sh`
- `bats tests/bats/fix-coredns-01-static.bats tests/bats/destroy-rebuild-01-static.bats tests/bats/register-spokes-01-static.bats`
- `bats tests/bats/destroy-rebuild-01-static.bats tests/bats/register-spokes-01-static.bats tests/bats/phase5-02-live.bats`
- `kubectl kustomize clusters/spoke-apps`
- `kubectl kustomize clusters/spoke-ml`
- `bats tests/bats/deploy-examples-01-static.bats tests/bats/deploy-examples-02-kustomize-build.bats tests/bats/register-spokes-01-static.bats`
- `git diff --check`
