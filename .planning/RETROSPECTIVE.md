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

## Milestone: v0.19 — Capsule Multi-Tenancy POC

**Shipped:** 2026-05-18
**Phases:** 6 (7-12) | **Plans:** 34 | **Tasks:** 76

### What Was Built

Generic POC onboarding seam (`KARYON POC MOUNT` sentinel in `clusters/hub-flux/flux-system/kustomization.yaml`); persistent isolated `spoke-capsule` k3d cluster reconciled hub-only by Flux (never enters `task rebuild`); Capsule operator + capsule-proxy installed as two separate Flux HelmReleases reconciled into spoke-capsule; two Tenants (alpha, bravo) with disjoint owners and Flux multi-tenancy lockdown; imperative tenant-owner kubeconfig minting routed through capsule-proxy with tenant-scoped LIST visibility; empirical bats evidence (12-test negative-RBAC suite + webhook failure + clean teardown + SLO regression gate) + graduation ADR-008 (outcome: DEFER); EKS-targeted reference doc `docs/capsule-on-eks.md` rolled Status: Draft → Reviewed for team-presentation use.

### What Worked

- **Wave 0 Nyquist gate** carried forward from v0.18: RED bats scaffolds landed before every implementation plan in Phases 7-11. Caught design issues at scaffold time (Pitfall 7 placeholder yamls, P27 falsifier, 10-P1 tls.crt jsonpath) rather than at execution time.
- **Split-plan-from-execute discipline:** every Plan {phase}-00 was Wave-0 scaffold, Plans {phase}-01..N were implementation, Plan {phase}-{last} was verifier. Made re-runs after fixes mechanical (e.g. Plan 09-03 attempt-3 after two atomic rollbacks).
- **D-letter decision codes** scaled cleanly across milestones: v0.19 added D-08-11 (cert flip), D-08-12 (split-Kustomization), D-08-13 (push-gate deferral), D-09-08 (Wave 0 contract), D-11-14 (ADR-008 evidence-bound rubric), D-11-15 (EKS doc evidence rollover) — all traceable to phase artifacts.
- **D-08-13 push-gate-deferred-with-override** pattern unblocked Phase 8/9/10 verifiers without forcing a premature first-push; carryover items collected and discharged at Phase 11 VAL-05.
- **`/gsd-plan-milestone-gaps`** worked as designed: 2026-05-11 invocation reframed the original optional Phase 12 (`capsule-addon-fluxcd` trial) as the v0.19 close-out reconciliation phase when audit surfaced the stale-checkbox / narrative-drift / artifact-supersedure cleanup needed before archive.
- **Parallel worktree execution in Phase 12 Wave 1** (6 plans across `.planning/` files with disjoint targets) merged cleanly with zero conflicts; the orchestrator's protective restore-from-main logic correctly preserved plan 12-02's STATE.md and plan 12-06's ROADMAP.md edits.

### What Was Inefficient

- **Plan 09-03 landed on attempt 3** after two atomic rollbacks. Cumulative falsification record (RESEARCH.md §Gap 3 + §Gap 11) eventually caught the right SA name (`flux-reconciler` per `register-spokes-for-flux.sh:286`, not `kustomize-controller`). Lesson: live state verification before assuming script-named identifiers.
- **Phase 8 G-04 BLOCKER (chart-rendered Role NotFound) sat unresolved from 2026-04-29 to Plan 11-07 (2026-05-06).** The architectural seam (`spec.kubeConfig` redirecting HR/OCIRepo to a cluster without Flux CRDs) needed a PostBuild patch + namespace seed, not a kustomize-spec.patches relocation. Workaround documented as ≥1 in ADR-008 graduation rubric.
- **Stale documentation accumulated faster than expected.** By Phase 11 close, REQUIREMENTS.md had 18 unflipped `[x]` checkboxes against satisfied REQs, STATE.md was 4 days behind reality, 11-VERIFICATION.md was at the pre-G-04-fix state, 4 Nyquist VALIDATION.md ledgers had `status: draft`. Phase 12 explicitly existed to reconcile this. Future milestones: tighter per-phase doc-evolution discipline could shrink the close-out burden.
- **SDK's `extractFrontmatter` "corruption recovery" heuristic bit milestone-close audit-open:** the parser greedily picks the LAST `---...---` block, which gets confused by markdown H2 horizontal rules in UAT files. Discovered when 07-HUMAN-UAT.md (`status: complete`) showed as `unknown` in audit-open output; fixed by replacing `---` H2 separators with `***`. Should be fixed upstream in the SDK.

### Patterns Established

- **Split-Kustomization architecture (D-08-12):** when reconciling resources to spokes that don't have Flux CRDs, split outer Kustomizations into hub-targeted (no `kubeConfig`) and spoke-targeted (with `kubeConfig`) — separate `spec.kubeConfig` from `spec.path` is the wrong simplification.
- **PostBuild over spec.patches (D-11-01 relocation):** to patch helm-rendered manifests, use HelmRelease `spec.postRenderers`, not Kustomization `spec.patches` (the latter only modifies kustomize-build output, not helm-rendered output).
- **Evidence-bound graduation rubric (D-11-14):** ADR graduation outcome (adopt / defer / reject / replaced) gated on falsifiable bats matrix counts (GREEN/RED/SKIP) + documented workarounds; outcome derives from the rubric, not from authorship judgment.
- **`/gsd-audit-milestone` re-run as Phase-close gate:** for milestones where docs drift during execution, run audit re-run as a Wave-2 gate before declaring phase-close. Plan 12-07 demonstrated the pattern cleanly.

### Key Lessons

1. **Wave 0 Nyquist gate continues to pay off** — verified across v0.18 and v0.19. Every implementation plan in Phases 7-11 was preceded by a Wave 0 RED bats scaffold landing the falsification contracts. Zero "implement and test in same plan" anti-patterns; rollbacks (Plan 09-03 attempts 1/2) were mechanical because tests existed.
2. **Live state verification before identifier-naming assumptions** — Plan 09-03 attempts 1/2 failed by assuming script-internal SA names; attempt 3 succeeded by grepping `register-spokes-for-flux.sh` for the actual SA name. Pattern: always verify the runtime artifact's name before referencing it in a patch.
3. **Stale-doc accumulation is real; budget for explicit close-out reconciliation.** Phase 12 (`/gsd-plan-milestone-gaps` driven) was 7 plans of pure bookkeeping. Cheap to run (mostly grep + Edit) but mandatory if `/gsd-audit-milestone` is to return `passed` cleanly.
4. **`spec.kubeConfig` is architecturally load-bearing** — it changes what a Flux Kustomization can validly contain. Spoke-targeted Ks can reference CRDs that don't exist on the hub; hub-targeted Ks cannot reference CRDs that don't exist on the hub. Split-Kustomization (D-08-12) is the canonical pattern.
5. **PostBuild ≠ spec.patches.** Helm-rendered output needs PostBuild; kustomize-build output needs spec.patches. The two are not interchangeable. (Fired as Pitfall 11-P1; closed in Plan 11-07.)

### Cost Observations

- **Model mix:** Predominantly Opus 4.7 (1M context) for orchestration + planning + most executor agents (config `model_profile: inherit`); occasional Sonnet for shorter executor agents. Specific percentages not tracked.
- **Sessions:** Many sessions across ~19 days (2026-04-29 → 2026-05-18); STATE.md + per-phase CONTEXT.md + per-plan SUMMARY.md anchored cross-session handoffs.
- **Notable:** Parallel worktree execution (Phase 12 Wave 1) and `--auto` mode (Phase 11 + Phase 12 execute) cut wall-time meaningfully; the cost trade-off was the Phase 12 SDK quirks (counter overshoot in `phase.complete`, audit-open frontmatter parse) that needed manual correction.

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Sessions | Phases | Key Change |
|-----------|----------|--------|------------|
| v0.18 | many | 6 | Initial milestone — established Wave 0 Nyquist gate, D-letter decision codes, hub-only Flux GitOps pattern, public-repo 5-layer secrets defense |
| v0.19 | many | 6 | Carried v0.18 patterns forward; added split-Kustomization for `spec.kubeConfig` seams (D-08-12), PostBuild-over-spec.patches for helm-rendered manifests (D-11-01), evidence-bound graduation rubric (D-11-14), `/gsd-plan-milestone-gaps` close-out reconciliation phase (Phase 12) |

### Cumulative Quality

| Milestone | Bats Tests | Phase Verifications | Code Review Findings (auto-fixed) |
|-----------|------------|---------------------|-----------------------------------|
| v0.18 | 169 (excluding live destructive) | 6/6 passed (5/5 must-haves each) | 0 critical / 4 warnings (all auto-fixed) |
| v0.19 | ~315 cumulative (incl. ~146 new in Phases 7-11) | 6/6 passed (Phase 7 `human_needed → passed` post-UAT 2026-05-13; Phases 8-10 `passed_with_overrides`; Phase 11 `passed_with_overrides`; Phase 12 `passed`) | 3 BLOCKER + 8 WARNING + 4 INFO (advisory — 11-REVIEW.md) |

### Top Lessons (Verified Across Milestones)

1. **Wave 0 Nyquist gate pays off** — verified in v0.18 (caught 06-01 cwd issue) AND v0.19 (Plan 09-03 attempt-1/2 rollbacks were mechanical because RED tests existed before scripts).
2. **Worktree cwd discipline matters** — caught in v0.18, mitigation (explicit cwd-discipline in executor prompts + ORCHESTRATOR-RULE block + post-merge restore of orchestrator-owned files) held in v0.19 across multiple parallel-wave executions (Phase 8 Wave 0 spawn, Phase 11 Plan 11-04 hard-gate verifier, Phase 12 Wave 1 6-plan parallel).
3. **Document reconciliation is mandatory before milestone close** — v0.19 needed a dedicated 7-plan Phase 12 to flip 18 stale checkboxes, supersede Phase 11 verification artifacts, close 5 Nyquist VALIDATION ledgers, and re-run `/gsd-audit-milestone` to `passed`. Future milestones: tighter per-phase doc-evolution discipline OR routinize the close-out reconciliation as a planned final phase.
4. **`spec.kubeConfig` is architecturally load-bearing** — split-Kustomization (D-08-12) is the canonical pattern for reconciling to spokes without Flux CRDs.
5. **PostBuild ≠ spec.patches** — for helm-rendered manifests, use HelmRelease `spec.postRenderers`, not Kustomization `spec.patches`.
