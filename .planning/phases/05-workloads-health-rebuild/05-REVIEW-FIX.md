---
phase: 05-workloads-health-rebuild
source: 05-REVIEW.md
status: fixed
fixed_at: 2026-04-28T16:40:00Z
findings_fixed:
  critical: 3
  warning: 3
  total: 6
---

# Phase 05 Code Review Fix Summary

## Fixed Findings

- CR-01 / WR-02: `scripts/fix-coredns.sh` now treats failed post-restart spoke DNS probes as failures, and `tests/bats/fix-coredns-01-static.bats` pins the fail-closed behavior.
- CR-02 / WR-03: `scripts/rebuild.sh` now runs `scripts/preflight.sh` before `destroy`, and `tests/bats/destroy-rebuild-01-static.bats` pins preflight-before-destroy ordering.
- CR-03: `scripts/rebuild.sh` now rejects symlink or non-regular rebuild log paths before truncation, supports `KARYON_REBUILD_LOG_FILE`, and creates the log with `umask 077`.
- WR-01: `scripts/register-spokes-for-flux.sh` now preserves existing spoke Kustomization resources while appending required seed and example references. `tests/bats/register-spokes-01-static.bats` pins the merge-style repair path.

## Verification

- `bash -n scripts/fix-coredns.sh scripts/rebuild.sh scripts/register-spokes-for-flux.sh`
- `bats tests/bats/fix-coredns-01-static.bats tests/bats/destroy-rebuild-01-static.bats tests/bats/register-spokes-01-static.bats`
- `git diff --check`
