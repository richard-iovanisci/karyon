---
created: 2026-04-29T16:30:00Z
title: Phase 7 carryover — gitleaks rule fires on planning docs that quote inert synthetic-kubeconfig fixture
area: security/gitleaks
resolves_phase: 11
files:
  - .gitleaks.toml
  - .planning/phases/07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc/07-00-PLAN.md
  - .planning/phases/07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc/07-RESEARCH.md
  - .planning/phases/07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc/07-REVIEW.md
source: .planning/phases/07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc/deferred-items.md
---

## Problem

The new `kubeconfig-bearer-token` rule introduced in Phase 7 (Plan 07-04, `.gitleaks.toml`) catches `kind: Config` + bearer-token shape. It correctly fires on the synthetic positive fixture (`tests/fixtures/gitleaks/synthetic-kubeconfig.yaml`, allowlisted by path) and correctly does NOT fire on the negative fixture.

It also fires on planning docs that **quote** the inert synthetic fixture content for documentation purposes:
- `.planning/phases/07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc/07-00-PLAN.md` (line 808 — Plan 07-00 Wave 0 task description embeds the fixture YAML)
- `.planning/phases/07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc/07-RESEARCH.md` (line 647 — Code Examples section reproduces the fixture for reviewer reference)
- `.planning/phases/07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc/07-REVIEW.md` — code-review report quotes both planning docs

Local pre-commit hook is NOT installed in `.git/hooks/pre-commit` (REPO-04 contract was for Phase 6 native hook + CI scan; current state has only CI). So local commits pass without gitleaks scrutiny.

The CI `gitleaks-scan` job (`.github/workflows/ci.yml`) runs `gitleaks git --log-opts="--all"` on the full history with `fetch-depth: 0`. **First push to origin/main of any post-Phase-7 commit will trigger CI failure** because the planning docs are part of history.

This is the core reason the milestone owner held off pushing during Phase 7.

## Solution

Phase 11 (Validation + Graduation ADR — VAL-05) explicitly owns the one-shot history scan post-Phase-10 first-push verification. Resolve before VAL-05 runs.

Three resolution options (per `deferred-items.md`):

**Option C (recommended): broad path-allowlist for `.planning/`**
Add to `.gitleaks.toml` `[allowlist] paths`:
```
'^\.planning/.*\.md$',  # Planning docs may quote inert synthetic fixture content for documentation
```
- Pro: Future-proof — any phase whose planning docs reference fixtures or kubeconfig examples is auto-allowlisted.
- Con: Slightly broad — but the risk (a real-shape kubeconfig in a planning doc) would itself be a procedural defect; pre-commit-hook-on-source is the right place to catch real leaks, not planning-doc retroactive scans.

**Option B (fallback): per-fingerprint allowlist**
Add narrow `regexes` entries to the rule's `[rules.allowlist]` matching the specific known-inert literals from the synthetic fixture.
- Pro: Narrowest exception.
- Con: Requires updating allowlist whenever planning docs change.

**Option A (most invasive): redact in-place**
Replace `token: <hash-shaped-string>` with `token: <REDACTED-INERT>` in the three planning docs.
- Pro: No allowlist needed.
- Con: Mutates plan history (philosophical concern about plan-as-written immutability).

Pick C, commit, then `gitleaks git --log-opts="--all"` in a local sanity check before push. Then push origin/main.

This todo will auto-close when `/gsd-execute-phase 11` completes (per `resolves_phase: 11`). It MUST be resolved before VAL-05's "one-shot history scan post-Phase-10 first-push gitleaks scan returns 0 findings" can pass.

## Cross-references

- Original deferred item: `.planning/phases/07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc/deferred-items.md`
- Phase 11 contract: REQUIREMENTS.md VAL-05 ("One-shot history gitleaks scan post-Phase-10 first push returns 0 findings — proves no tenant kubeconfig leaked")
- CI job: `.github/workflows/ci.yml` `gitleaks-scan` job
- Existing path-allowlist precedent: `.gitleaks.toml` `^\.env\.example$` block
