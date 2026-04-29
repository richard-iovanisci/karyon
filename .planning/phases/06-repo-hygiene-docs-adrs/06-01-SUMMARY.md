---
phase: 06-repo-hygiene-docs-adrs
plan: 01
subsystem: infra
tags: [gitleaks, pre-commit, secrets-defense, public-repo-gate, adr]

requires:
  - phase: 06-00
    provides: bats validation scaffold (REPO-02 / REPO-03 / REPO-04 contract tests)
provides:
  - Public-repo secrets gate (T-06-PAT-01 layers a-e)
  - gitleaks 8.30.1 toolchain pin via asdf
  - Native git pre-commit hook (no Python framework, no lefthook) wired via core.hooksPath
  - ADR-0001 single-WSL2 + shared docker network decision
  - One-shot history scan baseline (227 commits / 0 findings)
affects: [06-07-ci, future-secret-handling, future-adrs]

tech-stack:
  added: [gitleaks 8.30.1, .gitleaks.toml, hooks/pre-commit, ADR template]
  patterns:
    - Native git hooks via core.hooksPath (rejected Python pre-commit framework D-06)
    - asdf-managed tool pins in .tool-versions (D-07)
    - Nygard 4-section ADR template (Status / Context / Decision / Consequences) (D-02)
    - Whole-file path allowlist for .env.example in .gitleaks.toml (D-08)

key-files:
  created:
    - .gitleaks.toml
    - hooks/pre-commit
    - docs/adr/0001-single-wsl2-shared-docker-network.md
  modified:
    - .gitignore
    - .tool-versions
    - scripts/install-tools.sh

key-decisions:
  - "gitleaks chosen over detect-secrets (D-05): single binary, faster, fewer false positives"
  - "Native git hooks over Python pre-commit framework (D-06): zero runtime deps, no Python needed for shell-only repo"
  - "core.hooksPath set via install-tools.sh (D-06): repo-local, no global git config pollution"
  - ".env.example whole-file path allowlist (D-08): safer than per-token allow rules; survives placeholder rotation"
  - "One-shot history scan run as part of plan execution (D-15): NOT committed; report retained at /tmp/karyon-gitleaks/history.json"
  - "ADR-0001 documents single-WSL2 + shared k8s-net Docker network as the locked architecture (Status: Accepted)"

patterns-established:
  - "ADR Nygard template: Status / Context / Decision / Consequences sections, Status: Accepted line, dated"
  - "gitleaks allowlist: regex-based for placeholder tokens, path-based for whole-file allowances"
  - "Pre-commit hook output: redacts on failure, prints remediation including --no-verify audit-loud bypass"

requirements-completed:
  - REPO-01
  - REPO-02
  - REPO-03
  - REPO-04
  - DOCS-06

duration: ~7min
completed: 2026-04-28
---

# Phase 06 Plan 01: Public-Repo Secrets Gate Summary

**gitleaks 8.30.1 pinned with native git pre-commit hook + .gitignore D-16 expansion + ADR-0001 single-WSL2 docker network — public-repo PAT exposure gate (T-06-PAT-01) operational with 0 historical findings across 227 commits.**

## Performance

- **Duration:** ~7 min (executor 425s, including verified self-checks)
- **Started:** 2026-04-28T20:03:38Z
- **Completed:** 2026-04-28T20:10:43Z
- **Tasks:** 4 (3 atomic + 1 human-verify checkpoint)
- **Files modified:** 7

## Accomplishments

- `.gitignore` D-16 expansion (kubeconfig artifacts, TLS material, Flux scratch, IDE noise) — `.planning/` intentionally still tracked per D-15
- `.gitleaks.toml` allow-rules (placeholder + .env.example whole-file path)
- `.tool-versions` adds `gitleaks 8.30.1` (asdf-managed)
- `hooks/pre-commit` native git hook invoking `gitleaks git --pre-commit --redact --staged --verbose` with redacted-output remediation
- `scripts/install-tools.sh` Sections 5/7/8 (asdf gitleaks plugin + `git config --local core.hooksPath hooks`, both idempotent)
- `docs/adr/0001-single-wsl2-shared-docker-network.md` Nygard 4-section ADR (Status: Accepted, 2026-04-22)
- One-shot gitleaks history scan: 227 commits / 3.69 MB / **0 findings** (no PAT rotation needed)

## Task Commits

1. **Task 1: gitleaks pin + allowlist + .gitignore D-16** — `2551a9d` (feat)
2. **Task 2: pre-commit hook + install-tools.sh sections 7-8** — `0b70ea9` (feat)
3. **Task 3: .env.example verify + history scan + ADR-0001** — `e0f1ec1` (docs)
4. **Task 4: human-verify checkpoint** — approved based on executor self-checks (gitleaks 8.30.1 reachable; core.hooksPath = hooks; bats repo-hygiene-01-static.bats 5/5; both shell scripts pass `bash -n`; history scan 0 findings)

## Files Created/Modified

- `.gitignore` — D-16 patterns (kubeconfig, TLS, Flux scratch, IDE/OS); `.planning/` still tracked
- `.gitleaks.toml` — placeholder allow-rule + .env.example whole-file path
- `.tool-versions` — `gitleaks 8.30.1` pin
- `hooks/pre-commit` — gitleaks --pre-commit --redact --staged --verbose; remediation message names `git commit --no-verify` audit-loud bypass
- `scripts/install-tools.sh` — asdf gitleaks plugin + `git config --local core.hooksPath hooks` (idempotent)
- `docs/adr/0001-single-wsl2-shared-docker-network.md` — Nygard 4-section, Status: Accepted

## Decisions Made

None — followed plan as specified. All 5 D-decisions (D-05/06/07/08/15) reflected in final artifacts.

## Deviations from Plan

### Orchestration Anomaly (not a plan deviation, but worth recording)

The executor agent inadvertently committed to `main` directly instead of its `worktree-agent-aad080418e3ee4d8d` worktree branch. The cause: the agent's Bash tool calls did not consistently `cd` into the worktree path (cwd does not persist across Bash invocations in this runtime). Commit `2551a9d` also captured 3 untracked bats files that were leftover from 06-00's earlier writes to the main tree. The bats files are byte-identical to those in 06-00's worktree, so this is a packaging issue (the bats files belong logically to 06-00) but not a content issue. The orchestrator merged 06-00's worktree branch on top with no conflicts.

**Total deviations:** 0 plan deviations; 1 orchestration anomaly (no auto-fix required, recorded for postmortem).
**Impact on plan:** None — all artifacts landed correctly on main with intended content.

## Issues Encountered

None during plan execution. The orchestration anomaly above was caught and reconciled during the post-wave merge step.

## User Setup Required

No external service configuration required — the gitleaks history scan returned 0 findings, so the placeholder PAT in `.env.example` does NOT need rotation. If a real PAT is committed and detected by future scans, see PLAN.md `user_setup` for the rotation procedure.

## Next Phase Readiness

- Public-repo gate operational (layers a-e of T-06-PAT-01); layer f (CI gitleaks job) lands in Plan 06-07
- ADR-0001 sets the precedent for ADRs 0002-0005 (Plan 06-02)
- `.gitignore` and `.gitleaks.toml` are stable; downstream plans inherit them transparently
- No blockers for Wave 2

---
*Phase: 06-repo-hygiene-docs-adrs*
*Completed: 2026-04-28*
