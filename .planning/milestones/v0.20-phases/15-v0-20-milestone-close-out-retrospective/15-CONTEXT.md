# Phase 15: v0.20 Milestone Close-out + Retrospective - Context

**Gathered:** 2026-05-20
**Status:** Ready for planning
**Mode:** `--auto` (recommended defaults auto-selected; see 15-DISCUSSION-LOG.md)

<domain>
## Phase Boundary

This phase **reconciles and closes** the v0.20 milestone. Nothing about the three-tier permission model, the demo runbook, the `tenant-workload-editor` ClusterRole, the `GlobalTenantResource` propagation, or the kubeconfig minting changes here — Phases 13 + 14 already shipped and live-verified all of that. Phase 15 is purely book-keeping + audit + retrospective.

It produces:

1. **REQUIREMENTS.md reconciled** — 11 remaining `[ ]` checkboxes (DEMO-01..06 + RUNBOOK-01..05) flipped to `[x]` against live evidence from Phase 13 + Phase 14, with phase/plan citations. Any Phase 13/14 spec deviations from the original briefing captured inline (mirrors v0.19 Phase 12 Plan 12-01's TEN-01 `forceTenantPrefix: false` pattern).
2. **STATE.md + ROADMAP.md consistent** — `last_activity` advanced past Phase 14 close-out, Performance Metrics By-Phase table populated for Phases 13/14/15, ROADMAP Progress table refreshed (no within-document contradictions), milestone Phase Summary checkboxes all marked complete.
3. **Three-tier model regression-verified live** — Full Phase 13 + Phase 14 bats suite re-run GREEN against live `spoke-capsule`; `kubectl auth can-i '*' '*'` returns `no` for both platform-owner and tenant-workload-editor identities; v0.18 `task rebuild` SLO < 230s preserved (DELIVERY-02 + DELIVERY-03 regression gates).
4. **`/gsd-audit-milestone v0.20` returns `passed`** — zero `tech_debt`, all 23 REQs satisfied, Nyquist VALIDATION ledgers closed for Phases 13/14 (`status: final`, `nyquist_compliant: true`, `wave_0_complete: true` — already true at Phase 15 open; gate verifies and records).
5. **Retrospective captured** — v0.20 milestone retrospective appended to the existing `.planning/RETROSPECTIVE.md` living document (continues v0.18 + v0.19 pattern); v0.20 carry-forward parking lot reconciled in PROJECT.md (close items that landed, append Phase 13/14-surfaced deferrals); milestone is `ready_to_archive`.

**Explicitly NOT in scope (these belong to other phases / future milestones):**

- Any net-new feature work, ClusterRole edits, `GlobalTenantResource` changes, demo-runbook content edits, RBAC narrowing, or `task rebuild` chain modifications — all owned by Phases 13 + 14 and final.
- Fixing the `tls: bad certificate` capsule-controller chatter at the cert-rotation layer — `document-only` per OQ-1 (Phase 14 D-14-01); deferred to a future capsule-graduation phase.
- Capsule production graduation, EKS migration, `capsule-addon-fluxcd` trial — ADR-008 = DEFER; v0.20 carry-forward parking lot.
- Starting the v0.21 milestone (briefing, requirements, roadmap) — `/gsd-new-milestone v0.21` runs after `/gsd-complete-milestone v0.20`, NOT as part of Phase 15.
- Archiving the milestone directory — `/gsd-complete-milestone v0.20` does the file moves AFTER Phase 15 closes; Phase 15 only sets `ready_to_archive`.
- Pre-existing markdownlint failures, Phase 1-5 shellcheck warnings, real secret management, G-04 architectural decision — all v0.18/v0.19 carry-forward; explicitly NOT v0.20 scope per `.planning/v0.20-MILESTONE-BRIEFING.md` "Out of Scope" section.

</domain>

<decisions>
## Implementation Decisions

### Plan Decomposition + Wave Shape

- **D-15-01:** **5 plans across 2 waves** — Wave 1 (4 file-disjoint parallel plans) + Wave 2 (1 sequential audit + retrospective + verifier plan).
  - **Why:** Phase 12 (v0.19 close-out) used 7 plans / 2 waves but had heavier supersedure work (Plan 12-03 specifically superseded Phase 11's VERIFICATION). Phase 15 has none of that — Phase 13 + Phase 14 both already have `status: final` + `nyquist_compliant: true` + `wave_0_complete: true`. Compressing to 5 plans matches the milestone briefing's "lean / additive" framing and the smaller artifact surface.
  - **How to apply:** Anticipated plan shape (planner decides final names + boundaries; this is the target cadence, not a contract):
    - **Wave 1 (file-disjoint, runnable in parallel git worktrees per the v0.18 + v0.19 close-out idiom):**
      - **Plan 15-01** — REQUIREMENTS.md: flip 11 unchecked v0.20 mandatory checkboxes (DEMO-01..06 + RUNBOOK-01..05) to `[x]` with phase/plan citations; capture any Phase 13/14 spec deviations inline (D-15-03 below); refresh Traceability table.
      - **Plan 15-02** — STATE.md: advance `last_activity`, flip milestone status to `closing`/`complete` (per `/gsd-complete-milestone` contract — planner picks the exact transition), populate Performance Metrics By-Phase rows for Phases 13/14/15 with actual plan counts.
      - **Plan 15-03** — ROADMAP.md: refresh Progress table (Phase 14: 0/4 → 4/4 Complete, Phase 15: in-progress → Complete on land); flip milestone Phase Summary checkboxes; sweep within-document contradictions (any "Not started" / "in progress" remnants).
      - **Plan 15-04** — Live regression rerun: Phase 13 + Phase 14 live bats GREEN end-to-end against `spoke-capsule`; `kubectl auth can-i '*' '*'` returns `no` for both platform-owner and tenant-workload-editor identities; single `task rebuild` invocation captures SLO < 230s evidence (DELIVERY-02 gate); evidence log committed.
    - **Wave 2 (sequential, depends on all Wave 1):**
      - **Plan 15-05** — Audit + retrospective + verifier: `/gsd-audit-milestone v0.20` runs to `passed`; v0.20 retrospective section appended to `.planning/RETROSPECTIVE.md` (D-15-04); v0.20 carry-forward parking lot reconciled in PROJECT.md (D-15-05); `15-VALIDATION.md` finalized (`status: final`, `nyquist_compliant: true`, `wave_0_complete: true` — book-keeping phase has no RED bats Nyquist gate; ledger documents that fact explicitly); `15-VERIFICATION.md` written; milestone set `ready_to_archive`.

### Live Regression Rerun Scope (Success Criterion 3)

- **D-15-02:** **Phase 13 + Phase 14 live bats subset only — NOT the full project bats suite.** Plus a single `task rebuild` cold-run for v0.18 SLO < 230s evidence.
  - **Why:** Success criterion 3 in ROADMAP.md scopes the rerun explicitly to "Full Phase 13 + Phase 14 bats suite" + "v0.18 `task rebuild` SLO < 230s preserved". Extending to the full project bats suite (which includes Phase 1-12 historical falsifiers) re-litigates v0.18 + v0.19 ground that ADR-008 + Phase 12 already finalized — adds noise, no signal. The targeted subset is the smallest evidence set that closes the three-tier regression gates (RBAC-03, RBAC-04, DELIVERY-02, DELIVERY-03).
  - **How to apply:** Plan 15-04 runs:
    - `bats tests/bats/rbac-{08,09,10,11}-live-*.bats` + `bats tests/bats/seed-{02,03}-live-*.bats` + `bats tests/bats/demo-*.bats` + `bats tests/bats/negative-rbac-*.bats` (or whatever Phase 13 + Phase 14 named their live bats files — planner globs against actual filenames at plan time).
    - `kubectl --kubeconfig=$PO_KC auth can-i '*' '*'` → `no` (platform-owner ceiling).
    - `kubectl --kubeconfig=$TO_ALPHA_KC auth can-i '*' '*'` → `no` (tenant-workload-editor ceiling).
    - `task rebuild` cold-run, captured with `time` wrapper; SLO assert `< 230s`; followed by `task health-check` exit 0.
    - All evidence appended to `15-04-live-rerun-evidence.log` (mirrors Phase 14's `14-02-full-suite-evidence.log` + `14-03-uat-cold-run-evidence.log` pattern).
  - **Failure handling:** If any of the above fails, that's NOT a Phase 15 close-out fix — it's a regression in Phase 13/14 that has to land as its own remediation plan (likely a `/gsd-insert-phase 14.1` or a Phase 13/14 patch). Phase 15 close-out blocks until live regression is GREEN; this is a hard gate, not a "best-effort" attempt.

### Spec Deviation Capture Pattern (Success Criterion 1)

- **D-15-03:** **Inline in REQUIREMENTS.md** — mirrors v0.19 Phase 12 Plan 12-01's TEN-01 `forceTenantPrefix: false` amendment.
  - **Why:** ROADMAP success criterion 1 explicitly cites the v0.19 TEN-01 pattern as the reference. REQUIREMENTS.md is the canonical milestone REQ ledger; deviations live next to the REQ they affect so downstream readers see them in one place. A separate deviations doc would fragment the audit trail.
  - **How to apply:** When flipping a `[ ]` to `[x]` in Plan 15-01, if the implementation diverged from the original REQ text, amend the REQ text inline to match live reality + cite the phase/plan that surfaced the deviation. Examples (planner verifies which actually occurred):
    - **OQ-1 RUNBOOK-03** — TLS noise treatment = `document-only` (not `fix`) per Phase 14 D-14-01. If RUNBOOK-03 text presupposed `fix`, amend to `document-only` + cite "Phase 14 D-14-01".
    - **OQ-5 RUNBOOK-05** — new-tenant name = `charlie` (not generic placeholder) per Phase 14 D-14-02. If RUNBOOK-05 text used a placeholder, amend to `charlie` + cite "Phase 14 D-14-02".
    - **OQ-3 SEED-03** — hello-world shape = whatever Phase 13 D-13-* resolved (Pod + Service, ConfigMap-only, or Deployment + Service + ConfigMap). If the live YAML diverged from the briefing-time framing, capture inline.
    - **OQ-4 DELIVERY-01** — delivery mechanism = GitOps (`pocs/capsule/`) vs Taskfile (`task seed-capsule-demo`) — capture the actual landed choice with a one-line citation.
  - **No-deviation case:** If Phase 13/14 landed exactly per spec, REQ text is unchanged — only the checkbox flips. Plan 15-01 reads each of the 11 REQs against the live evidence and records "no deviation" vs "deviation: <description>" in the plan summary.

### Retrospective Shape (Success Criterion 5)

- **D-15-04:** **Append v0.20 section to `.planning/RETROSPECTIVE.md`** (continues v0.18 + v0.19 living-doc pattern). NOT a standalone `RETROSPECTIVE-v0.20.md` file.
  - **Why:** The existing `.planning/RETROSPECTIVE.md` header says "A living document updated after each milestone. Lessons feed forward into future planning." v0.18 + v0.19 both appended sections to this single file. ROADMAP success criterion 5 says "`RETROSPECTIVE-v0.20.md` (or equivalent)" — the "or equivalent" clause explicitly permits the living-doc pattern. Single-file convention preserves cross-milestone pattern continuity (a future reader compares v0.18 → v0.19 → v0.20 lessons in one scroll) and avoids file proliferation.
  - **How to apply:** Plan 15-05 appends a `## Milestone: v0.20 — Capsule POC Demo & RBAC Polish` section to `.planning/RETROSPECTIVE.md` with subsections matching the v0.18 + v0.19 cadence:
    - **Shipped** date + Phases/Plans/Tasks/Commits/Timeline summary.
    - **What Was Built** (3-6 bullets covering: `tenant-workload-editor` ClusterRole, `GlobalTenantResource` propagation, platform-owner co-owner pattern, two-perspective demo verification, `docs/poc-capsule-demo.md` 6-act runbook, OQ-1..5 resolutions).
    - **What Worked** (lean-milestone framing held; additive-only constraint preserved alpha/bravo Flux reconciliation; Wave 0 RED bats Nyquist gate continues to pay off; UAT cold-read caught actual runbook friction).
    - **What Was Inefficient** (any Phase 13/14-specific friction the orchestrator noted — e.g., capsule-controller TLS noise cosmetic, `spoke-capsule` cluster recovery patterns, etc. — planner pulls from Phase 13/14 SUMMARY.md + VERIFICATION.md).
    - **Patterns Established** (three-tier permission model articulated as Tier 1 / Tier 2 / Tier 3; co-owner CRB pattern for platform-owner LIST/WATCH/GET/LOGS/EXEC; `new-tenant.sh` provisioning template; demo runbook 6-act cadence with executable pre-demo checklist + Known Noise appendix).
    - **OQ Resolutions** — table or sub-bullet list of OQ-1..5 + resolution + Phase/D-code citation (OQ-1 = document-only / 14 D-14-01; OQ-2 = tenant Secrets policy / 13; OQ-3 = hello-world shape / 13; OQ-4 = delivery mechanism / 13; OQ-5 = `charlie` + live provision / 14 D-14-02 + D-14-03).
    - **Carry-forward updates** — what closed (none expected — v0.20 was purely additive), what's added to the parking lot (TLS-fix-at-cert-layer, `task demo-capsule` wrapper, any other Phase 13/14-deferred items).

### Carry-Forward Parking Lot Reconciliation

- **D-15-05:** **Reconcile inline in `.planning/PROJECT.md` "Carry-forward parking lot" section.** Same Plan 15-05 that writes the retrospective also updates PROJECT.md.
  - **Why:** PROJECT.md is the canonical home for the parking lot (already established v0.18 → v0.19 → v0.20). Updating in place keeps the v0.21 milestone briefing process sane — `/gsd-new-milestone v0.21` will read PROJECT.md to seed the next milestone's scope-vs-defer decisions.
  - **How to apply:** Plan 15-05 makes additive edits to the "Carry-forward parking lot" section:
    - **Retain** existing entries (none of `capsule-addon-fluxcd`, G-04, `KARYON_PHASE11_STRICT_LIVE`, slo-regression-live, markdownlint, gitleaks-proxy-06, Phase 1-5 shellcheck, first-push CI verification, real secret management, frontmatter reconciliation closed during v0.20).
    - **Append** Phase 13/14-surfaced deferrals (from Phase 14 `<deferred>` section + Phase 13 `deferred-items.md`):
      - Fix `tls: bad certificate` capsule-controller chatter at the cert-rotation layer (cert-manager wiring / CA distribution) — was OQ-1 `document-only` in v0.20.
      - `task demo-capsule` Taskfile wrapper — tempting ergonomics but breaks P31 isolation; revisit at graduation or in a POC-ergonomics milestone.
      - Any other deferred items captured in Phase 13 `deferred-items.md` (Plan 15-05 reads the file at plan time).
    - **Reorder** if needed so most-load-bearing items are listed first (planner's call).

### Audit Gate Failure Handling

- **D-15-06:** **Hard block on audit failure; remediate as its own plan; rerun audit.** Audit failure does NOT close the milestone.
  - **Why:** `/gsd-audit-milestone v0.20` is the milestone-close gate. If it returns anything other than `passed` (e.g., `tech_debt > 0`, REQ unsatisfied, VALIDATION ledger not final), shipping a partially-audited milestone defeats the purpose of the audit gate. v0.19 Phase 12 set this precedent — Plan 12-07 was the audit gate and was Wave 2 / sequential / last because of it.
  - **How to apply:** Plan 15-05 runs `/gsd-audit-milestone v0.20` as its terminal step. If `passed`: write `15-VERIFICATION.md` with `passed`, set milestone `ready_to_archive`, commit. If failed: the plan halts, surfaces the audit report inline in its SUMMARY, and the orchestrator either (a) inserts a remediation plan (e.g., `/gsd-insert-phase 14.2` or a new Plan 15-06) and reruns the audit, or (b) flags the failure to the human owner for triage. Either way, the milestone is NOT marked `ready_to_archive` until the audit returns `passed`.

### Nyquist / Wave 0 RED Bats — Not Applicable to Book-Keeping Phase

- **D-15-07:** **No Wave 0 RED bats scaffold for Phase 15.** `15-VALIDATION.md` documents this explicitly with `wave_0_complete: true` + a one-line rationale.
  - **Why:** Phase 15 is pure book-keeping: REQ checkbox flips, STATE/ROADMAP refreshes, live regression rerun (existing bats; no new bats), retrospective append, audit gate. There is no new behavior to falsify — falsifiers for the three-tier model live in Phase 13/14 bats and re-run as-is. Nyquist gate (no implementation without a pre-existing RED falsifier) is satisfied vacuously: zero implementation = zero falsifiers required.
  - **How to apply:** `15-VALIDATION.md` frontmatter sets `status: final`, `nyquist_compliant: true`, `wave_0_complete: true`. Body has a one-paragraph "Why no Wave 0 bats" section citing this decision + cross-linking to v0.19 Phase 12's matching pattern.

### Claude's Discretion

- **Exact plan boundaries within Wave 1.** Planner may merge 15-02 (STATE) + 15-03 (ROADMAP) into a single "metadata refresh" plan if the change surface is trivial, or split 15-04 (live regression) into bats-only + `task rebuild`-only if the cluster state demands sequencing. Target stays 4–6 plans / 2 waves; harder bound is "no plan does more than one canonical artifact category."
- **Whether Plan 15-04 needs a fresh `task fix-dns-poc-capsule` invocation before the bats run.** If `spoke-capsule` cluster state is unknown at plan execution time, the plan opens with the same pre-demo checklist Phase 14 D-14-05 specified. Planner verifies live cluster reachability before running bats.
- **Naming of `15-VERIFICATION.md` sections.** Mirrors Phase 12 + Phase 14 verifier output shape; planner picks final section headers.
- **Whether to commit `15-04-live-rerun-evidence.log` as a binary or a markdown-formatted log.** Phase 14 used both patterns (plain `.log` files committed alongside SUMMARY.md). Recommendation: plain `.log` (matches Phase 14 precedent).
- **Whether to invoke `/gsd-stats` or `/gsd-progress` mid-phase for a sanity-check on Performance Metrics By-Phase numbers before Plan 15-02 writes them.** Optional; planner decides if the SDK can populate the numbers directly or if a manual count is needed.
- **Retrospective sub-section depth.** D-15-04 lists the cadence; planner may expand or compress individual sub-sections based on actual Phase 13/14 SUMMARY.md content density.

### Folded Todos

None — `gsd-sdk query todo.match-phase 15` returned 0 matches.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase Inputs (v0.20 milestone scoping)

- `.planning/ROADMAP.md` §"Phase 15: v0.20 Milestone Close-out + Retrospective" — phase goal, success criteria 1–5, depends-on (Phase 14), no new REQ-IDs (book-keeping phase closes 23 v0.20 mandatory checkboxes against live evidence from Phases 13 + 14).
- `.planning/REQUIREMENTS.md` — 23 v0.20 mandatory REQs (RBAC-01..06 already `[x]` post-Phase 13; SEED-01..03 already `[x]` post-Phase 13; DELIVERY-01..03 already `[x]` post-Phase 13; DEMO-01..06 + RUNBOOK-01..05 still `[ ]` at Phase 15 open — these 11 are what Plan 15-01 flips). Traceability table needs final phase mapping.
- `.planning/PROJECT.md` §"Current Milestone: v0.20" + §"Carry-forward parking lot" + §"Open questions" — milestone framing (lean / additive), three-tier permission model definition, OQ-1..5 resolution citations, parking lot text to reconcile in Plan 15-05 (D-15-05).
- `.planning/STATE.md` — current `last_activity` ("Phase 14 marked complete"), Performance Metrics By-Phase table to populate Phase 13/14/15 rows in Plan 15-02.
- `.planning/v0.20-MILESTONE-BRIEFING.md` — original milestone briefing (Demo R1..R5 framing, in-scope / out-of-scope lists, OQ-1..5 recommended defaults). Reference for spec-deviation comparison in Plan 15-01 (D-15-03).

### Phase 13 + Phase 14 Inheritance (live evidence sources)

- `.planning/phases/13-rbac-narrowing-globaltenantresource-seed-delivery-mechanism/13-CONTEXT.md` — Phase 13 decisions D-13-01..10+, OQ-2/3/4 resolutions.
- `.planning/phases/13-rbac-narrowing-globaltenantresource-seed-delivery-mechanism/13-VERIFICATION.md` — Phase 13 verifier output (RBAC-01..06 + SEED-01..03 + DELIVERY-01..03 GREEN). Phase 15 cites this as the evidence anchor for the 12 already-flipped checkboxes.
- `.planning/phases/13-rbac-narrowing-globaltenantresource-seed-delivery-mechanism/13-VALIDATION.md` — Phase 13 Nyquist VALIDATION ledger (`status: final`, `nyquist_compliant: true`, `wave_0_complete: true`).
- `.planning/phases/13-rbac-narrowing-globaltenantresource-seed-delivery-mechanism/13-SUMMARY.md` files (13-00..04 SUMMARY.md) — plan-level evidence for REQUIREMENTS.md citations in Plan 15-01.
- `.planning/phases/13-rbac-narrowing-globaltenantresource-seed-delivery-mechanism/deferred-items.md` — Phase 13-surfaced deferrals; Plan 15-05 reads this when updating PROJECT.md parking lot.
- `.planning/phases/14-two-perspective-demo-verification-6-act-runbook-tls-noise-re/14-CONTEXT.md` — Phase 14 decisions D-14-01..10, OQ-1 + OQ-5 resolutions (`document-only` TLS noise; `charlie` marquee name; `live` provision style). Spec-deviation source for Plan 15-01 (D-15-03).
- `.planning/phases/14-two-perspective-demo-verification-6-act-runbook-tls-noise-re/14-VERIFICATION.md` — Phase 14 verifier output (DEMO-01..06 + RUNBOOK-01..05 GREEN). Phase 15 cites this as evidence for the 11 remaining `[ ]` → `[x]` flips.
- `.planning/phases/14-two-perspective-demo-verification-6-act-runbook-tls-noise-re/14-VALIDATION.md` — Phase 14 Nyquist VALIDATION ledger (`status: final`, `nyquist_compliant: true`, `wave_0_complete: true`).
- `.planning/phases/14-two-perspective-demo-verification-6-act-runbook-tls-noise-re/14-03-uat-cold-run-evidence.log` — Phase 14 UAT cold-read evidence (RUNBOOK-04 ≤ 15-min gate).
- `.planning/phases/14-two-perspective-demo-verification-6-act-runbook-tls-noise-re/14-02-full-suite-evidence.log` — Phase 14 full bats suite evidence. Reference precedent for Plan 15-04 evidence-log shape.

### v0.19 Phase 12 Close-out Pattern (the explicit reference for Phase 15)

- `.planning/milestones/v0.19-phases/12-v0-19-close-out-reconciliation/12-01-PLAN.md` through `12-07-PLAN.md` — v0.19 close-out plan decomposition. Phase 15 mirrors this shape compressed to 5 plans / 2 waves (D-15-01).
- `.planning/milestones/v0.19-phases/12-v0-19-close-out-reconciliation/12-RESEARCH.md` — v0.19 close-out research; Wave / Parallelism Opportunity section is the file-disjoint Wave 1 idiom Phase 15 inherits.
- `.planning/milestones/v0.19-phases/12-v0-19-close-out-reconciliation/12-VERIFICATION.md` — v0.19 close-out verifier output; shape reference for `15-VERIFICATION.md`.
- `.planning/milestones/v0.19-phases/12-v0-19-close-out-reconciliation/12-VALIDATION.md` — v0.19 close-out Nyquist VALIDATION ledger; shape reference for `15-VALIDATION.md` (D-15-07).

### Retrospective Living-Doc

- `.planning/RETROSPECTIVE.md` — Living retrospective doc; existing v0.18 + v0.19 sections set the cadence Plan 15-05 follows when appending v0.20 (D-15-04).

### Architectural / Governance Anchors

- `docs/adr/0008-capsule-multi-tenancy-graduation.md` — POC graduation = DEFER per D-11-14 evidence-bound rubric. Anchor for OQ-1 `document-only` decision; carry-forward parking lot framing.
- `docs/adr/0004-hub-only-flux-control-plane.md` — Hub-only Flux pattern; preserved by v0.20 "additive only" constraint (DELIVERY-03 regression gate).
- `docs/poc-capsule.md` — Operator's runbook; unchanged by Phase 15 (Phase 13 + Phase 14 are its last touch points).
- `docs/poc-capsule-demo.md` — Demo runbook; unchanged by Phase 15 (Phase 14 is its last touch point — but Plan 15-04's UAT-style live rerun may surface friction that lands as a Phase 15-06 patch if material).

### Live Cluster Artifacts (Phase 15 reads from, does NOT modify)

- `pocs/capsule/spoke/tenant-crs/{alpha,bravo}.yaml` — Existing alpha + bravo Tenant CRs (`spec.owners[]` includes `capsule-platform-owners` post-Phase 13; `clusterRoles: [admin]` Flux SA owner pattern preserved per RBAC-03). Plan 15-04 live regression rerun verifies these are unchanged at HEAD.
- `pocs/capsule/spoke/cluster-roles/tenant-workload-editor.yaml` (or equivalent Phase 13-named path) — `tenant-workload-editor` ClusterRole. Plan 15-04 live regression rerun verifies grant matrix.
- `pocs/capsule/spoke/global-tenant-resources/hello-world.yaml` (or equivalent) — `GlobalTenantResource` CR. Plan 15-04 verifies propagation latency ≤ 60s holds.
- `scripts/poc/capsule/{issue-platform-owner-kubeconfig.sh,issue-tenant-kubeconfig.sh,new-tenant.sh,fix-dns.sh}` — Plan 15-04 uses these verbatim to mint kubeconfigs for the live rerun (no script edits).

### Anti-Pattern / Invariant Anchors (regression gates this phase enforces)

- **P31** — POC isolation: `spoke-capsule` never enters `task rebuild`. Plan 15-04 verifies via `task rebuild` SLO < 230s test (DELIVERY-02 regression gate).
- **P27** — Tenant Flux Kustomization `spec.serviceAccountName: flux-reconciler` defense. Plan 15-04 verifies alpha + bravo Flux reconciliation continues unbroken (RBAC-03 regression gate).
- **P29** — Kubeconfigs never land in git; gitleaks defense. Plan 15-04 mints kubeconfigs to `/tmp`; evidence log redacts any kubeconfig contents.
- **D-11-14** — Evidence-bound graduation rubric (ADR-008 = DEFER). v0.20 closes without graduating; rubric stays DEFER.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- **`.planning/RETROSPECTIVE.md`** — Living doc with v0.18 + v0.19 sections already in place. Plan 15-05 appends a v0.20 section using the existing cadence (Shipped / What Was Built / What Worked / What Was Inefficient / Patterns Established) — no new file, no new format.
- **Phase 12 plan shape** (`.planning/milestones/v0.19-phases/12-v0-19-close-out-reconciliation/12-{01..07}-PLAN.md`) — Direct template for Phase 15 plan decomposition. Plan 12-01 (REQUIREMENTS flip) → Plan 15-01; Plan 12-02 (STATE) → Plan 15-02; Plan 12-06 (ROADMAP) → Plan 15-03; Plan 12-07 (audit gate) → Plan 15-05 audit step. Phase 15 omits Plan 12-03 (Phase 11 VERIFICATION supersedure) entirely since Phase 13/14 VERIFICATION.md files are already final.
- **Phase 14 evidence-log idiom** (`14-02-full-suite-evidence.log`, `14-02-visceral-check-evidence.log`, `14-02-demo-live-evidence.log`, `14-03-uat-cold-run-evidence.log`) — Plan 15-04 reuses this `.log`-file-committed-alongside-SUMMARY pattern verbatim.
- **`/gsd-audit-milestone v0.20`** — Direct slash command from the GSD toolkit. No custom audit harness needed.
- **`/gsd-stats` + `/gsd-progress`** — Available for mid-phase Performance Metrics By-Phase sanity checks (Plan 15-02 may invoke).
- **`.planning/STATE.md` Performance Metrics By-Phase table** — Already has v0.18 (Phases 01..06) + v0.19 (Phases 07..12) populated. Plan 15-02 extends with Phase 13 (5 plans) + Phase 14 (4 plans) + Phase 15 (5 plans target) rows.
- **`.planning/MILESTONES.md`** — v0.19 entry already documents the shipped pattern (Phases / Plans / Tasks / Key accomplishments). `/gsd-complete-milestone v0.20` will append a v0.20 entry post-Phase 15 close — NOT Phase 15's job, but Plan 15-05 verifies the milestone is `ready_to_archive` so `/gsd-complete-milestone` runs cleanly.

### Established Patterns

- **Wave 1 file-disjoint parallel + Wave 2 sequential audit gate** — v0.18 + v0.19 close-out idiom. Different plans touch different files (REQUIREMENTS / STATE / ROADMAP / live rerun evidence log) so they run in independent git worktrees with zero merge conflicts.
- **Inline spec-deviation amendment in REQUIREMENTS.md** — Plan 12-01's TEN-01 `forceTenantPrefix: false` amend pattern. Phase 15 Plan 15-01 inherits.
- **Phase/plan citation idiom for `[x]` flips** — REQUIREMENTS.md already cites phases (e.g., RBAC-01..06 closed by Phase 13 plans; Plan 15-01 adds explicit `(Phase 13 / 13-01-PLAN)` citations to the flipped lines if not already present).
- **Living-doc retrospective** — `.planning/RETROSPECTIVE.md` is the canonical home for milestone-close lessons. v0.18 + v0.19 sections demonstrate cadence.
- **Carry-forward parking lot in PROJECT.md** — Updated at each milestone close. v0.18 → v0.19 → v0.20 transitions all touched this section.
- **VALIDATION.md frontmatter convention** — `status: final`, `nyquist_compliant: true`, `wave_0_complete: true`. Phase 15 sets all three with an explicit "book-keeping phase; no Wave 0 bats required" rationale in the body (D-15-07).
- **Bats live-rerun idiom** — `bats tests/bats/<glob>` with kubeconfig env vars (`PO_KC`, `TO_ALPHA_KC`, `TO_BRAVO_KC`) pre-minted from Phase 10 + 13 scripts. Plan 15-04 inherits Phase 14's pre-demo-checklist preamble.

### Integration Points

- **Phase 15 → `/gsd-complete-milestone v0.20`** — Phase 15 sets `ready_to_archive: true`; `/gsd-complete-milestone v0.20` (run AFTER Phase 15 closes) does the actual milestone archival file moves (`.planning/phases/13-* + 14-* + 15-*` → `.planning/milestones/v0.20-phases/`). Phase 15 does NOT do the moves.
- **Phase 15 → `/gsd-new-milestone v0.21`** — Optional next step after `/gsd-complete-milestone v0.20`. Phase 15 itself does NOT touch v0.21 planning.
- **Phase 15 → `.planning/MILESTONES.md`** — `/gsd-complete-milestone v0.20` (post-Phase 15) appends the v0.20 entry. Phase 15 does NOT modify MILESTONES.md directly.
- **No code-level integration** — Phase 15 modifies only `.planning/*.md` files + appends to `.planning/RETROSPECTIVE.md` + writes evidence logs under the phase dir. Zero source-code edits, zero `pocs/`, `scripts/`, or `docs/` edits (the live rerun in Plan 15-04 only READS from these paths).

</code_context>

<specifics>
## Specific Ideas

- **5 plans / 2 waves** target (D-15-01) — pattern-mirror v0.19 Phase 12 compressed by ~2 plans because Phase 15 has no VERIFICATION supersedure work.
- **Retrospective = append to `.planning/RETROSPECTIVE.md`** (D-15-04), not a standalone file. The existing living-doc pattern is canonical.
- **Spec deviations = inline REQUIREMENTS.md amend** (D-15-03), mirroring v0.19 Plan 12-01's TEN-01 `forceTenantPrefix: false` precedent.
- **Live regression rerun = Phase 13 + Phase 14 bats subset + single `task rebuild` SLO check** (D-15-02). NOT full project bats suite.
- **Audit gate failure = hard block + remediate + rerun** (D-15-06). Milestone is NOT `ready_to_archive` until audit returns `passed`.
- **No Wave 0 RED bats** for Phase 15 (D-15-07) — book-keeping phase; Nyquist gate satisfied vacuously.
- **Carry-forward parking lot reconciliation = inline in PROJECT.md** (D-15-05), with Phase 13/14-surfaced deferrals (TLS-fix-at-cert-layer, `task demo-capsule` wrapper) appended.

</specifics>

<deferred>
## Deferred Ideas

These came up during analysis but belong outside Phase 15:

- **Fixing the `tls: bad certificate` capsule-controller chatter at the cert-rotation layer** (cert-manager wiring or proper CA distribution). → Belongs on the v0.20 carry-forward parking lot (Plan 15-05 appends it there). Future capsule-graduation phase or production EKS cut.
- **`task demo-capsule` Taskfile wrapper.** Phase 14 already declined this (D-14 Discretion note) for P31 isolation reasons. → Parking lot; revisit at graduation or in a POC-ergonomics milestone.
- **`capsule-addon-fluxcd` Trial (ADDON-01/02).** Inherited carry-forward from v0.19. → Stays on parking lot.
- **G-04 architectural decision / split-Kustomization refactor.** Inherited carry-forward from v0.19. → Stays on parking lot.
- **v0.21 milestone briefing + planning.** → Runs AFTER `/gsd-complete-milestone v0.20` via `/gsd-new-milestone v0.21`. Out of Phase 15 scope.
- **Pre-existing markdownlint failures + Phase 1-5 shellcheck warnings + real secret management.** → Inherited v0.18 carry-forward; stays deferred per `.planning/v0.20-MILESTONE-BRIEFING.md` "Out of Scope".
- **Demo runbook content edits surfaced by Plan 15-04 live rerun.** If the live rerun reveals runbook friction beyond cosmetic (e.g., a kubectl command no longer producing the documented expected output), the fix is a Phase 14 patch (e.g., `/gsd-insert-phase 14.1`), NOT a Phase 15 close-out edit. Phase 15 surfaces, does not fix.
- **MILESTONES.md v0.20 entry.** Written by `/gsd-complete-milestone v0.20` AFTER Phase 15 closes. → Out of Phase 15 scope.

### Reviewed Todos (not folded)

None — `gsd-sdk query todo.match-phase 15` returned 0 matches; no todos were reviewed.

</deferred>

---

*Phase: 15-v0-20-milestone-close-out-retrospective*
*Context gathered: 2026-05-20*
*Mode: --auto (recommended defaults; see 15-DISCUSSION-LOG.md for per-area auto-selection trail)*
