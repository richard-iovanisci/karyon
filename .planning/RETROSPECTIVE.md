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

## Milestone: v0.20 — Capsule POC Demo & RBAC Polish

**Shipped:** 2026-05-20
**Phases:** 3 (13-15) | **Plans:** 14 | **Tasks:** ~32 | **Timeline:** 2026-05-19 → 2026-05-20

### What Was Built

- `tenant-workload-editor` ClusterRole + per-tenant human-tenant-owner ServiceAccounts + Tenant CR additive `spec.owners[]` co-ownership (Phase 13 RBAC-01..03; D-13-01 read-only Secrets policy)
- Platform-owner SA + dual-subject ClusterRoleBinding + `issue-platform-owner-kubeconfig.sh` + `new-tenant.sh` provisioning helper (Phase 13 RBAC-04..06)
- `GlobalTenantResource` CR + hello-world Pod + Service propagation across all tenant namespaces within 60s (Phase 13 SEED-01..03; D-13-02 Pod+Service shape; FQCI `docker.io/library/nginx:alpine` per Pitfall 13-P1)
- GitOps delivery under `pocs/capsule/` + `docs/poc-capsule.md` platform-owner H2 append (Phase 13 DELIVERY-01..03; D-13-03 — NO `task seed-capsule-demo` Taskfile entry, declined for P31 isolation)
- Two-perspective demo verification (platform-owner kubeconfig + tenant-owner kubeconfigs via capsule-proxy NodePort 30443) end-to-end bats GREEN against `spoke-capsule` (Phase 14 DEMO-01..06)
- `docs/poc-capsule-demo.md` 6-act demo runbook + pre-demo checklist + Known Noise appendix + `docs/capsule-on-eks.md` three-tier-on-EKS append (Phase 14 RUNBOOK-01..05; D-14-01 TLS noise = document-only; D-14-02 marquee tenant = `charlie`; D-14-03 provision style = live)
- OQ-1..5 resolutions landed against falsifiable evidence: TLS noise document-only, Secrets policy read-only, hello-world Pod+Service, GitOps delivery (no Taskfile), `charlie` marquee tenant with live provisioning

### What Worked

- **Lean / additive milestone framing held** (per `v0.20-MILESTONE-BRIEFING.md`): 3-phase decomposition + anti-scope guard rejected every "while we're at it" addition during discuss-phase; ADDON-01/02 + G-04 + KARYON_PHASE11_STRICT_LIVE all stayed deferred to v0.21
- **Additive-only constraint** preserved alpha + bravo Flux reconciliation across all three phases (RBAC-03 + DELIVERY-03 regression gates GREEN at Phase 15 close); existing Flux SA owner pattern intact; `spec.owners[]` additive append only
- **Wave 0 RED bats Nyquist gate** carried forward verbatim from v0.18 + v0.19 to Phase 13 (19 NEW bats files locked the RBAC + SEED + DELIVERY contracts BEFORE Plan 13-01 implementation) and Phase 14 (11 NEW bats files locked DEMO + RUNBOOK contracts BEFORE Plan 14-01 implementation)
- **UAT cold-read caught actual runbook friction** (Phase 14 Plan 14-03 auto-attested-with-carry-forward UAT pattern): the runbook was executable cold in ≤ 15 min, and Plan 15-04 live regression rerun + Plan 15-05 audit gate retired the UAT carry-forward cleanly
- **Phase 12 close-out template scaled cleanly to Phase 15 compressed form** (5 plans / 2 waves vs Phase 12's 7 plans / 2 waves) — supersedure-of-prior-VERIFICATION work was unnecessary because Phase 13 + Phase 14 VERIFICATION ledgers were already final at Phase 15 open
- **Three-tier permission model** as a load-bearing architectural concept proved falsifiable end-to-end via 3 distinct `kubectl auth can-i '*' '*' = no` denials (platform-owner + alpha-owner + bravo-owner) — the conceptual model maps 1:1 to falsifiable bats + visceral kubectl assertions

### What Was Inefficient

- **Plan 15-04 retry chain** — 3 attempts (origin/main lag on attempt 1 → spoke-ml GPU=0 / inotify EMFILE on attempt 2 first try → `task rebuild`-vs-worktree architectural conflict on attempt 2 second try) consumed substantial operator time. The first two were environmental and resolved by operator action; the third surfaced a real architectural conflict between `task rebuild`'s Flux-reconciles-from-origin/main contract and the parallel-executor-worktree pattern. This conflict is worth a dedicated remediation in v0.21 (spec amendment candidate: either teach `task rebuild` to handle in-worktree branches, or amend the parallel-executor pattern so close-out plans that need `task rebuild` run sequentially on main).
- **`KARYON_REBUILD_APPROVED=yes` spec drift** — Plan 15-04 docs + plan spec said `=1`, but `scripts/rebuild.sh` line 30 requires literal `=yes`. Plan 15-04 Rule 3 fix applied at exec time; the spec ↔ script alignment direction is a v0.21 docs hygiene candidate.
- **capsule-controller TLS noise** (`tls: bad certificate` 1Hz chatter) treated as cosmetic per OQ-1 D-14-01 (document-only); cert-rotation layer fix deferred to graduation. The right architectural fix is cert-manager wiring or proper CA distribution, but neither is in scope for a POC demo.
- **`spoke-capsule` cluster state-recovery dance** (Phase 14 destroy-poc → Plan 15-04 pre-flight needed `flux resume kustomization poc-capsule-spoke{,-rbac,-tenants}` recovery + `task fix-dns-poc-capsule` invocation): the rebuild + resume + DNS-fix sequence is operator-knowledge-heavy and would benefit from a `task spoke-capsule-recover` wrapper — but that wrapper itself was declined for P31 isolation, so the workaround is documented-only.
- **Two `delivery-05-live-slo-regression.bats` execution paths** (env-gated bats vs direct `time task rebuild`) both satisfied DELIVERY-02 but added ambiguity about which is canonical; Plan 15-04 chose the direct path for explicit wall-clock measurement clarity (then hit the architectural worktree conflict).

### Patterns Established

- **Three-tier permission model** as a falsifiable architectural articulation: Tier 1 (Cloud Ops, out-of-scope/talk-track only) / Tier 2 (Karyon Platform Team, platform-owner role; `kubectl auth can-i '*' '*' = no` + Tenant CR CRUD CAN + co-owner LIST/WATCH/GET/LOGS/EXEC) / Tier 3 (Tenant Devs, tenant-owner role via capsule-proxy NodePort 30443; `kubectl auth can-i '*' '*' = no` + own-tenant-only LIST + cross-tenant Forbidden + `kubectl create secret` Forbidden)
- **Co-owner ClusterRoleBinding pattern** for platform-owner LIST/WATCH/GET/LOGS/EXEC across every tenant namespace (additive append to existing `spec.owners[]` — preserves v0.19 Flux SA owner)
- **`new-tenant.sh` provisioning template** (per OQ-5 D-14-02 + D-14-03 — marquee tenant `charlie` with live provisioning style) — default-includes `capsule-platform-owners` in every newly-created Tenant CR's `spec.owners[]`
- **6-act demo runbook cadence** with executable pre-demo checklist + Known Noise appendix + production-translation forward-pointer to `docs/capsule-on-eks.md` (three-tier-on-EKS mapping)
- **`k3d cluster stop`/`start` as P31-preserving way to free POC-4 ports for v0.18 rebuild testing** (new pattern from Plan 15-04 retry-#2; pauses container without deleting it, preserving spoke-capsule state for graceful resume post-test)
- **Phase 15 5-plan compressed close-out** (vs Phase 12's 7-plan template): omits Plan 12-03 (Phase-11 VERIFICATION supersedure) entirely; collapses Plan 12-04 (4 VALIDATION ledgers close) into Plan 15-05 Task 4 since only the Phase 15 ledger needs flipping (Phase 13 + Phase 14 ledgers were already final at phase-open)
- **Living-doc retrospective convention** (D-15-04): single `.planning/RETROSPECTIVE.md` with sequential `## Milestone: vX.YZ` section appends rather than per-milestone standalone files — preserves cross-milestone scroll-comparison for future readers
- **Audit-gate + Path-X/Path-Y Contingency** (D-15-06; inherited from Plan 12-07): hard-block on audit failure; lenient Path-X-with-tech-debt acceptable for ADDON-pattern Future-Requirements drift OR (new in v0.20) PATH-B architectural-conflict deferral with carry-forward justification

### OQ Resolutions

| OQ | Briefing-recommended default | Landed Decision | Phase / D-code |
|----|------------------------------|----------------|----------------|
| OQ-1 (TLS noise treatment) | document-only | document-only (cert-rotation-layer fix deferred to graduation) | Phase 14 D-14-01 |
| OQ-2 (`tenant-workload-editor` Secrets policy) | read-only | read-only (`get`/`list`/`watch` only; explicit deny on `create`/`update`/`patch`/`delete`) | Phase 13 D-13-01 |
| OQ-3 (hello-world workload shape) | Pod + Service | Pod + Service (FQCI `docker.io/library/nginx:alpine` per Pitfall 13-P1) | Phase 13 D-13-02 |
| OQ-4 (delivery path) | GitOps `pocs/capsule/` | GitOps `pocs/capsule/` (NO `task seed-capsule-demo` Taskfile entry — declined for P31 isolation) | Phase 13 D-13-03 |
| OQ-5 (new-tenant name + provision style) | `charlie` + live | `charlie` + live (single canonical name across runbook + `new-tenant.sh` + bats fixtures) | Phase 14 D-14-02 + D-14-03 |

### Carry-forward updates

- **Closed by v0.20:** (none) — v0.20 was purely additive; no v0.19 carry-forward items were closed. ADDON-01/02 stay deferred to v0.21 *(post-ship note 2026-07-06: settled as PASS/do-not-adopt per the ADR-008 addendum — no trial needed)*; G-04 PostBuild workaround stays; KARYON_PHASE11_STRICT_LIVE remains optional; slo-regression-live env-gate stays; markdownlint + gitleaks-proxy-06 + Phase 1-5 shellcheck + first-push CI + real secret management + frontmatter reconciliation all stay deferred per `v0.20-MILESTONE-BRIEFING.md` "Out of Scope".
- **Added to parking lot by v0.20:** (a) Fix `tls: bad certificate` capsule-controller chatter at the cert-rotation layer (cert-manager wiring or proper CA distribution) — was OQ-1 `document-only` per D-14-01; cross-linked to ADR-008 (DEFER) and `docs/poc-capsule-demo.md` Known Noise appendix; revisit at capsule graduation or production EKS cut. (b) `task demo-capsule` Taskfile wrapper — tempting ergonomics but breaks P31 isolation (would add a `spoke-capsule` mention to the default-path Taskfile); revisit at graduation or in a POC-ergonomics milestone. (c) **DELIVERY-02 live `task rebuild` SLO re-attestation** — Plan 15-04 retry-#2 elected PATH-B (partial evidence) because of architectural rebuild-vs-worktree conflict; Plan 15-04 Tasks 1-3 GREEN + Phase 14 14-02 inheritance precedent + post-rebuild `task health-check` exit 0 baseline captured; full SLO measurement carry-forward to v0.21. (d) **`task rebuild` vs parallel-executor-worktree pattern architectural reconciliation** — spec amendment candidate for v0.21 (either teach `task rebuild` to handle in-worktree branches via push-to-test-branch + Flux test-revision pin, OR amend parallel-executor pattern so close-out plans run sequentially on main rather than in worktrees). (e) **`KARYON_REBUILD_APPROVED` env-gate value drift** — Plan 15-04 docs + plan spec say `=1`, but `scripts/rebuild.sh` line 30 requires literal `=yes`; single-line fix; alignment direction to be decided in v0.21 docs hygiene pass.

### Key Lessons

1. **Lean / additive milestone framing scales.** v0.20's 3-phase decomposition (RBAC + SEED + DELIVERY → DEMO + RUNBOOK → close-out) with anti-scope guard active during discuss-phase shipped 23 mandatory REQs across 14 plans without any "while we're at it" scope creep. Future lean milestones should preserve the briefing's "in-scope / out-of-scope" lists as enforceable contracts during discuss-phase.
2. **Three-tier permission model is the right articulation for Capsule POC demos.** Tier 1/2/3 maps cleanly to Cloud-Ops / Platform-Team / Tenant-Devs roles and lets each tier's ceiling be falsified by a distinct `kubectl auth can-i '*' '*' = no` assertion + a positive control. The articulation is reusable for any future multi-tenancy demo (Capsule, vCluster, kiosk, etc.).
3. **Phase 12 close-out template compresses cleanly when no prior-VERIFICATION supersedure work is needed.** v0.19 Phase 12 needed 7 plans because Plan 12-03 superseded Phase 11's pre-fix VERIFICATION artifact; v0.20 Phase 15 needed only 5 plans because Phase 13 + Phase 14 VERIFICATION ledgers were already final at phase-open. Future close-out phases should estimate plan count by counting (a) artifact reconciliation surfaces + (b) VERIFICATION supersedure needs + (c) live regression rerun gates separately, not by analogy to prior milestones.
4. **Living-doc retrospective is the right convention.** Single `.planning/RETROSPECTIVE.md` with sequential `## Milestone: vX.YZ` sections preserves cross-milestone scroll-comparison (a future reader compares v0.18 → v0.19 → v0.20 patterns + lessons in one file). Per-milestone standalone files would fragment that signal.
5. **OQ-resolution table is the cleanest format for retrospective OQ closure.** The 4-column table (OQ # | briefing default | landed decision | Phase/D-code) makes the briefing-vs-landed delta scannable and auditable without prose. Future milestones with open questions should adopt this table format verbatim.
6. **Architectural conflicts surface late and are best documented as PATH-B carry-forward when they don't compromise the milestone's core value.** Plan 15-04's `task rebuild`-vs-worktree conflict is a real architectural seam (rebuild's Flux contract assumes pushed origin/main; parallel-executor pattern intentionally puts plan-in-progress commits on unpushed feature branches). Inline reconciliation would violate Git Safety Protocol. PATH-B disposition + carry-forward to v0.21 is the right answer when the partial evidence + precedent inheritance satisfy the audit gate's lenient reading.

### Cost Observations

- **Model mix:** Opus 4.7 (1M context) for orchestration + planning + most executor agents; occasional Sonnet for shorter executor agents. No deviation from v0.18 + v0.19 pattern.
- **Sessions:** ~2-3 sessions across 2 days (2026-05-19 → 2026-05-20); STATE.md + per-phase CONTEXT.md + per-plan SUMMARY.md anchored cross-session handoffs.
- **Notable:** Phase 15 compressed close-out (5 plans / 2 waves) executed in significantly less wall-time than Phase 12 (7 plans / 2 waves) — the no-supersedure-needed shortcut is real. Plan 15-04 (live regression rerun) was the longest single plan due to `task rebuild` cold-run wall-time + the retry chain (origin/main lag → GPU/inotify EMFILE → architectural worktree conflict on attempts 1-3 respectively); the architectural conflict accounted for the largest share of operator time and surfaced a v0.21 spec-amendment candidate.

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
