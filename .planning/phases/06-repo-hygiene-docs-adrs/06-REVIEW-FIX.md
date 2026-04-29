---
phase: 06-repo-hygiene-docs-adrs
review_path: .planning/phases/06-repo-hygiene-docs-adrs/06-REVIEW.md
fixed_at: 2026-04-29T07:19:00Z
fix_scope: critical_warning
findings_in_scope: 4
fixed: 4
skipped: 0
iteration: 1
status: all_fixed
---

# Phase 6: Code Review Fix Report

## Summary

Applied fixes for all Critical and Warning findings from `06-REVIEW.md`.
The fixer subagent could not start because its isolated worktree setup tried
to reuse the active `main` worktree, so the fix pass was recovered inline in
the shared repo.

Info findings were intentionally left unchanged because `--all` was not
requested.

## Fixed Findings

### WR-01: `scripts/install-tools.sh` asdf version check regex never matches

Fixed in commit `ea30765` (`fix(06): make asdf install idempotent`).

The asdf idempotency guard now extracts the installed semantic version from
`asdf --version` output and compares it to the pinned `ASDF_VERSION`. This
matches the actual v0.18+ Go binary output and prevents unnecessary tarball
download/extraction on every rerun.

### WR-02: `.gitleaks.toml` path allowlist regex is unanchored

Fixed in commit `fa0424a` (`fix(06): anchor gitleaks env example allowlist`).

The gitleaks path allowlist now anchors the whole-file exemption to the root
`.env.example` path with `^\.env\.example$`, avoiding accidental exemptions
for unrelated files whose names merely contain `.env.example`.

### WR-03: `scripts/install-tools.sh` Section 7 is dead code

Fixed in commit `ab82c59` (`fix(06): remove duplicate gitleaks plugin step`).

Removed the duplicate gitleaks-only plugin section. The general plugin loop in
Section 5 already installs `gitleaks`, and the Git hooks section was renumbered
accordingly.

### WR-04: `.gitignore` has redundant `kubeconfig` + `kubeconfig*` lines

Fixed in commit `90e2906` (`fix(06): remove redundant kubeconfig ignore`).

Removed the bare `kubeconfig` entry because `kubeconfig*` already covers it.
The broader `kubeconfig*` and `*.kubeconfig` patterns remain in place.

## Verification

- `bash -n scripts/install-tools.sh`
- `shellcheck --severity=error scripts/install-tools.sh`
- `bats tests/bats/repo-hygiene-01-static.bats tests/bats/repo-hygiene-02-taskfile.bats tests/bats/repo-hygiene-03-ci.bats`
- `gitleaks git --redact --log-opts="--all"`

All commands passed.
