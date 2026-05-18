# Phase 7 Deferred Items

Items discovered during execution that are out of scope for the current plan.

## Plan 07-04 — Discovered 2026-04-29

### gitleaks fires on planning docs that quote synthetic-kubeconfig fixture content

**Discovered during:** Plan 07-04 Task 2 (repo-wide gitleaks scan verification)

**Issue:** A repo-wide `gitleaks detect --no-git --source . --config .gitleaks.toml` scan reports 4 leaks (exit 1) on these files (NOT the synthetic fixture itself, which is correctly allowlisted):

- `.planning/phases/07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc/07-00-PLAN.md` (line 808)
- `.planning/phases/07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc/07-RESEARCH.md` (line 647)

These files quote the inert synthetic-kubeconfig content (verbatim YAML block with `kind: Config` + `users:` + `token:`). The kubeconfig-bearer-token rule fires on the embedded YAML.

**Why deferred:**
- Plan 07-04 file scope: `scripts/preflight.sh`, `.gitignore`, `.gitleaks.toml` only.
- The flagged files were created by Plan 07-00 (planning) and the Phase 7 RESEARCH step.
- The Plan 07-04 contract (`tests/bats/repo-hygiene-04-poc.bats`) is fully satisfied — including both live gitleaks tests on the two specific fixtures (positive fires, negative silent).
- Per execution scope boundary: only auto-fix issues directly caused by current task changes.

**Resolution options for a follow-up plan or planning-doc cleanup:**
1. Add a path-allowlist entry for `^\.planning/phases/.*/.*\.md$` to the `kubeconfig-bearer-token` rule (broad — risks future planning docs containing real-shape kubeconfig content not being caught).
2. Add a per-fingerprint allowlist for these specific known-inert literals via `regexes` in `[rules.allowlist]` (narrow — but requires updating allowlist whenever planning docs change).
3. Replace the verbatim YAML quotes in the two planning docs with a redacted reference (e.g., `token: <REDACTED-INERT>`) so the rule does not fire.
4. Leave as-is — the leak is the inert synthetic fixture, no real secret material; pre-commit hook only scans staged files (the planning docs are already committed).

**Recommended:** Option 4 (no action) — the leak is provably inert; Phase 11 history scan will confirm zero real secrets across history. If/when a CI gitleaks job runs against the full repo and fails, opt for Option 3 (redact in-place).

