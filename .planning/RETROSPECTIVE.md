# Project Retrospective

*A living document updated after each milestone. Lessons feed forward into future planning.*

## Milestone: v0.18 — karyon Lab v1

**Shipped:** 2026-04-29
**Phases:** 6 | **Plans:** 41 | **Tasks:** 90 | **Commits:** 274 | **Timeline:** 2026-04-22 → 2026-04-29 (7 days)

### What Was Built

- **3-cluster local k8s lab on Windows 11 + WSL2 + k3d** — hub-flux (stock k3s) + spoke-ml (CUDA 12.8 / RTX 5090 sm_120) + spoke-apps, attached to a shared `k8s-net` Docker network with TLS SAN wiring for cross-cluster apiserver reach.
- **Hub-only Flux GitOps control plane** — hub reconciles into spokes via `spec.kubeConfig` + remote kubeconfig Secrets; spokes run zero Flux controllers. ApplicationSet trade-off documented in ADR-003 with migration note.
- **Read-only `task health-check` + `task fix-dns`** — proves clusters / nodes / Flux controllers / Kustomizations / in-hub DNS / GPU capacity / TLS SANs / workload readiness in one ordered gate; fix-dns clears stale CoreDNS NodeHosts after Docker/WSL restart by stop/starting only the hub.
- **Idempotent `task rebuild` chain** — destroy → create-clusters → bootstrap-flux → register-spokes → deploy-examples → health-check, validated end-to-end at **190 seconds** with warm CUDA image cache (well under the 20-minute SLO; CUDA cache survives `task destroy` per D-14 prune prohibition).
- **Public-repo secrets defense (5 layers)** — `.gitignore` D-16 expansion + `.env.example` 3-key contract + `.gitleaks.toml` allowlist + native git pre-commit hook (no Python framework) + post-push GitHub Actions CI gitleaks-scan job with `fetch-depth: 0`. One-shot history scan returned 0 findings across 251 commits.
- **5 Nygard 4-section ADRs** — single-WSL2 + shared docker network, k3d-over-Kind, Flux-over-ArgoCD, hub-only Flux, k3s/CUDA version pin. All Status: Accepted.
- **5-job parallel GitHub Actions CI** — shellcheck, markdownlint, kubeconform (against datreeio CRDs catalog), prune-lint-bats (reuses `tests/bats/destroy-rebuild-01-static.bats`), gitleaks-scan. All third-party actions pinned to 40-char SHAs (D-09).
- **Reference doc set** — README (DOCS-01 locked-order walkthrough), architecture.md (Mermaid topology), gpu-notes.md (3-part GPU contract), rebuild-runbook.md (7 step markers + timing + Common failures), flux-hub-spoke.md (Phase 3 patch surface narrative).

### What Worked

- **Phase 0 / Wave 0 bats validation scaffolds (Nyquist gate)** — Phases 2, 3, 4, 5, 6 all opened with a Wave 0 plan that committed parse-clean bats tests for every downstream contract before any implementation landed. Tests RED-failed on missing artifacts and turned green automatically as Waves 1-3 shipped, with no test-file modification needed. Eliminated the "implement and test in same plan" anti-pattern.
- **Phase artifact stack (CONTEXT → RESEARCH → PATTERNS → VALIDATION → PLAN → SUMMARY → REVIEW → VERIFICATION)** — running each phase through the full GSD artifact stack caught issues at the right layer. Discuss-phase surfaced ambiguities; research surfaced pitfalls; PATTERNS mapped new files to existing analogs; verifier did goal-backward checks that were independent of plan claims.
- **Worktree isolation for parallel waves** — Phases 4/5/6 ran multi-plan waves in parallel git worktrees with `--no-verify` commits and post-wave hook validation. Generally clean; one outlier in 06-01 (cwd-not-persisting bug — agent committed to main directly instead of its worktree) was caught at merge time and reconciled cleanly.
- **Verifier as second pair of eyes** — Phase 4 verifier caught a P18 silent-misroute risk that the executor's self-checks missed (`spec.kubeConfig` OMITTED was reframed as the real fault). Phase 5 verifier caught HIGH-1 hub-context-pin requirement after `k3d cluster create` leaves last-context on the spoke. Both fixes landed in subsequent plans.
- **D-letter decision codes** — short stable codes (D-04 runbook layout, D-08 gitleaks allowlist, D-13 starter.md cleanup, D-14 prune prohibition, D-15 history-scan-not-committed, D-16 gitignore expansion) made it easy to reference decisions across plans and commits without paragraph-length quotes. Codes propagated cleanly into commit messages and SUMMARY frontmatter.

### What Was Inefficient

- **REQUIREMENTS.md traceability table never auto-updated** — `gsd-sdk query phase.complete` returned `requirements_updated: false` for most phases. Many Phase 1, 2, and 6 requirements still showed `Pending` in REQUIREMENTS.md despite VERIFICATION.md status `passed`. The audit caught this; archive captures it as known tech debt. Suggests a table-format mismatch with what the SDK expects, or a missing claim path through plan frontmatter.
- **VALIDATION.md frontmatter goes stale** — 3 phases (03, 05, 06) have `nyquist_compliant: false` or `wave_0_complete: false` despite passing verification. The frontmatter reflects planning-time state; nothing updates it post-execution. Recommend a one-time reconciliation pass or an SDK feature.
- **SUMMARY.md `requirements-completed` frontmatter inconsistent** — 3 Phase 6 plans (06-02, 06-05, 06-06) shipped without populating `requirements-completed`. Verifier confirmed the requirements via codebase evidence, but the frontmatter cosmetic gap propagated into the audit and milestone-archive flows.
- **Worktree cwd discipline** — 1 of 8 Phase 6 executor agents committed to main directly because Bash tool calls don't persist `cd` between invocations. Reconciled at merge time without data loss, but worth recording as an orchestration anti-pattern. Wave 2+ prompts started including explicit "use `git -C <wt-path>` for every git command" guidance and the bug didn't recur.
- **Bats `grep -c Ready` substring-matches `NotReady`** in two Phase 2 test files — only caught during Phase 2 live re-confirmation; manually worked around with `awk '$2 == "Ready"'`. Test idiom that should have been caught earlier.

### Patterns Established

- **Wave 0 Nyquist gate:** every phase opens with a Wave 0 plan that authors parse-clean bats tests for every downstream contract before any implementation lands. Tests RED-fail by design until later waves ship the artifacts.
- **`scripts/lib/preflight-lib.sh` shared library:** every later script sources it for ANSI helpers + structured failure messages + destructive-op gates (`require_live_destructive` double-gate). Pre-commit hook also sources it.
- **`>>> step <name>` log markers** in `scripts/rebuild.sh` parsed by Phase 5's live state-checker. Allows post-rebuild verification without re-running the destructive chain.
- **D-14 literal exact-text comment** in `scripts/delete-clusters.sh`: `INTENTIONALLY NOT calling docker (system|builder|image|volume) prune` — verbatim, greppable. Phase 6's prune-lint-bats CI job greps for this literal as a contract.
- **`spec.kubeConfig` defense in depth:** Plan 04-04 documents the P18 silent-misroute trap (omitting `spec.kubeConfig` causes Flux to reconcile against the local cluster) — `value.yaml` pin remains as defense in depth even with `spec.kubeConfig` always declared. ADR-004 captures the constraint.
- **All GitHub Actions pinned to 40-char SHAs** (D-09) with a comment showing the human-readable tag: `actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd  # v6.0.2`.

### Key Lessons

1. **Worktrees + `cd` don't mix without explicit discipline.** Bash tool calls reset cwd between invocations. Always pass an absolute worktree path via `git -C <path>` or prefix every bash command with `cd <path> &&`. Adding this to executor prompts after the Phase 6 Wave 1 cwd-misroute eliminated recurrence in Waves 2-3.
2. **Plan-level Nyquist gates pay off.** Authoring tests in Wave 0 before any implementation lands meant every Wave 1+ task had a pre-existing red→green oracle. No "implement and test in same plan" debt; downstream verification was nearly automatic.
3. **Verification is goal-backward, not task-counting.** Verifier agents catch issues that pass plan-level self-checks (Phase 4 P18 silent-misroute, Phase 5 HIGH-1 context drift, Phase 6 WR-01 asdf regex). Goal-backward verification > task-completion-counting.
4. **Public-repo secrets defense needs all 5 layers.** Layers a-e (gitignore + env.example + pre-commit + history-scan + CI) each catch a different leak path; gitleaks pre-commit alone wouldn't catch a forced commit, and CI alone wouldn't catch a leak between commits. The 5-layer model is the contract.
5. **Documentation order matters as much as content.** README's DOCS-01 locked section order ("Windows prereqs → WSL config → Docker → NVIDIA → tools → cluster → bootstrap → register → deploy → teardown") doubles as the Taskfile order doubles as the rebuild.sh chain order. The 3 surfaces stay in sync because the order is canonical.

### Cost Observations

- **Model mix:** Predominantly Opus 4.7 (1M context) for orchestration + planning; Sonnet for executor agents in some waves. Specific percentages not tracked.
- **Sessions:** Multiple sessions across 7 days; sessions stayed coherent thanks to STATE.md + per-phase CONTEXT.md persistence.
- **Notable:** Per-phase artifacts (SUMMARY.md, VERIFICATION.md, REVIEW.md) were valuable handoff anchors between sessions — picking up after `/clear` rarely required re-explaining context. The biggest cost waste was the 06-01 cwd-misroute (had to manually reconcile commits at merge time); explicit cwd-discipline guidance in Wave 2+ prompts paid for itself many times over.

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Sessions | Phases | Key Change |
|-----------|----------|--------|------------|
| v0.18 | many | 6 | Initial milestone — established Wave 0 Nyquist gate, D-letter decision codes, hub-only Flux GitOps pattern, public-repo 5-layer secrets defense |

### Cumulative Quality

| Milestone | Bats Tests | Phase Verifications | Code Review Findings (auto-fixed) |
|-----------|------------|---------------------|-----------------------------------|
| v0.18 | 169 (excluding live destructive) | 6/6 passed (5/5 must-haves each) | 0 critical / 4 warnings (all auto-fixed) |

### Top Lessons (Verified Across Milestones)

*Single-milestone state — re-verify after v0.19+ ships.*

1. *(Wave 0 Nyquist gate paid off in v0.18 — re-verify in v0.19)*
2. *(Worktree cwd discipline issue caught in v0.18 — re-verify mitigation works in v0.19)*
