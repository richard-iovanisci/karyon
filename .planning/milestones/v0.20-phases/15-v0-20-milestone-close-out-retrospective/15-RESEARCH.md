# Phase 15: v0.20 Milestone Close-out + Retrospective — Research

**Researched:** 2026-05-20
**Domain:** GSD v1 milestone close-out (book-keeping + audit + retrospective; pattern-mirrors v0.19 Phase 12)
**Confidence:** HIGH — every claim verified against live `.planning/` artifacts, Phase 12 plan files, or `$HOME/.claude/get-shit-done/workflows/` slash-command source

## Summary

Phase 15 is a book-keeping close-out phase: zero new behavior, zero new REQ-IDs. It flips the remaining 11 v0.20 mandatory `[ ]` checkboxes (DEMO-01..06 + RUNBOOK-01..05) in REQUIREMENTS.md against live evidence from Phase 13/14, captures inline spec deviations, advances STATE.md + ROADMAP.md past Phase 14 close, re-runs the Phase 13 + Phase 14 bats subset against live `spoke-capsule` (with a single `task rebuild` SLO check), appends a v0.20 section to the living `.planning/RETROSPECTIVE.md`, reconciles the v0.20 carry-forward parking lot inline in PROJECT.md, runs `/gsd-audit-milestone v0.20` to `passed`, and sets the milestone `ready_to_archive`.

The phase pattern-mirrors v0.19 Phase 12 close-out at smaller scale: 5 plans / 2 waves vs Phase 12's 7 plans / 2 waves. Phase 15 omits Phase 12's VERIFICATION supersedure plan (12-03) entirely because Phase 13/14 VERIFICATION.md files are already `status: final` + `passed_with_overrides` at Phase 15 open — no supersedure needed. Phase 15 also omits Phase 12's todo-move plan (12-05) because `gsd-sdk query todo.match-phase 15` returned 0 matches.

**Primary recommendation:** Mechanical execution under the Phase 12 template, with three Phase-15-specific risks to mitigate up-front: (1) Plan 14-03's UAT carry-forward is the auditable bridge that Plan 15-04 + 15-05 retire; (2) live cluster lags `origin/main@49e264a2` per Phase 14's evidence log — Plan 15-04 MUST verify `git push origin main` has landed before invoking bats; (3) STATE.md frontmatter currently shows `status: completed` + `percent: 100` which is premature — must be reconciled to `executing` (Wave 1) → `ready_to_archive` (Wave 2) per the v0.19 Phase 12 STATE.md trajectory.

## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-15-01:** 5 plans across 2 waves — Wave 1 (4 file-disjoint parallel plans: REQUIREMENTS flip, STATE refresh, ROADMAP refresh, live regression rerun) + Wave 2 (1 sequential audit + retrospective + verifier plan).
- **D-15-02:** Live regression rerun = Phase 13 + Phase 14 bats subset only (NOT the full project bats suite) + single `task rebuild` cold-run for v0.18 SLO < 230s evidence.
- **D-15-03:** Spec deviations captured INLINE in REQUIREMENTS.md (mirrors v0.19 Phase 12 Plan 12-01 TEN-01 `forceTenantPrefix: false` pattern).
- **D-15-04:** Retrospective = append v0.20 section to `.planning/RETROSPECTIVE.md` (living-doc; NOT a standalone `RETROSPECTIVE-v0.20.md` file).
- **D-15-05:** Carry-forward parking lot reconciled inline in `.planning/PROJECT.md`.
- **D-15-06:** Audit gate failure = hard block + remediate as its own plan + rerun audit; milestone NOT marked `ready_to_archive` until `/gsd-audit-milestone v0.20` returns `passed`.
- **D-15-07:** No Wave 0 RED bats scaffold for Phase 15. `15-VALIDATION.md` documents this explicitly with `wave_0_complete: true` + a one-line rationale.

### Claude's Discretion

- Exact plan boundaries within Wave 1 (planner may merge 15-02 + 15-03 if change surface is trivial; may split 15-04 into bats-only + `task rebuild`-only if cluster state demands sequencing). Target 4–6 plans / 2 waves; harder bound is "no plan does more than one canonical artifact category."
- Whether Plan 15-04 needs a fresh `task fix-dns-poc-capsule` invocation before bats run (planner verifies live cluster reachability).
- Naming of `15-VERIFICATION.md` sections (mirrors Phase 12 + Phase 14 verifier output shape).
- Whether to commit `15-04-live-rerun-evidence.log` as plain `.log` (Phase 14 precedent) or markdown-formatted log.
- Whether to invoke `/gsd-stats` or `/gsd-progress` mid-phase for Performance Metrics By-Phase sanity check.
- Retrospective sub-section depth (D-15-04 lists the cadence; planner may expand or compress).

### Deferred Ideas (OUT OF SCOPE)

- Fix `tls: bad certificate` capsule-controller chatter at the cert-rotation layer → carry-forward parking lot; future capsule-graduation phase.
- `task demo-capsule` Taskfile wrapper → parking lot (Phase 14 D-14 Discretion already declined for P31 isolation).
- `capsule-addon-fluxcd` Trial (ADDON-01/02) → v0.19 carry-forward; stays on parking lot.
- G-04 architectural decision / split-Kustomization refactor → v0.19 carry-forward; stays on parking lot.
- v0.21 milestone briefing + planning → runs AFTER `/gsd-complete-milestone v0.20` via `/gsd-new-milestone v0.21`; NOT Phase 15 scope.
- Pre-existing markdownlint failures + Phase 1-5 shellcheck warnings + real secret management → v0.18 carry-forward; stays deferred.
- Demo runbook content edits surfaced by Plan 15-04 live rerun beyond cosmetic → fix is a Phase 14 patch (e.g., `/gsd-insert-phase 14.1`), NOT a Phase 15 close-out edit.
- MILESTONES.md v0.20 entry → written by `/gsd-complete-milestone v0.20` AFTER Phase 15 closes.

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| (no new REQ-IDs) | Phase 15 is book-keeping; closes 23 v0.20 mandatory checkboxes against live evidence | 12 already `[x]` post-Phase 13; 11 still `[ ]` (DEMO-01..06 + RUNBOOK-01..05) at Phase 15 open per `grep -n '^- \[ \]' .planning/REQUIREMENTS.md` |

## Project Constraints (from CLAUDE.md / AGENTS.md)

- `.planning/` is the live planning + progress state (GSD v1).
- Public-safe by default; placeholders instead of real secrets, internal URLs, hostnames.
- Do not read/print/expose secrets unless explicitly asked. (Phase 15 reads zero secrets; mints zero kubeconfigs — Plan 15-04 minting is a separate concern handled per Phase 10 + Phase 13 conventions to `/tmp`.)
- AGENTS.md `Local Guardrails` is TODO (no project-specific unsafe-command list documented).

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| REQUIREMENTS.md checkbox flip (Plan 15-01) | Planning artifact (`.planning/`) | — | REQUIREMENTS.md is the canonical milestone REQ ledger; only file mutated by Plan 15-01 |
| Inline spec-deviation amendment (Plan 15-01) | Planning artifact (`.planning/`) | — | Mirrors v0.19 TEN-01 `forceTenantPrefix: false` pattern; lives next to REQ text |
| STATE.md frontmatter + body advance (Plan 15-02) | Planning artifact (`.planning/`) | — | Live planning + progress ledger per GSD v1 |
| ROADMAP.md Progress table + Phase Summary refresh (Plan 15-03) | Planning artifact (`.planning/`) | — | Source of milestone-level truth for next-milestone-open + audit cross-reference |
| Live regression rerun (Plan 15-04) | Test infrastructure (bats) + Live cluster (`spoke-capsule`) | Evidence log (`.planning/phases/15-*/15-04-*.log`) | Read-only against live cluster; bats is the falsifiable contract; evidence log committed under phase dir |
| `task rebuild` SLO cold-run (Plan 15-04) | Default-path scripts (`scripts/rebuild.sh`) + `Taskfile.yml` | Live host (WSL2 + k3d) | DELIVERY-02 regression gate; destructive ~3min cycle; runs without `spoke-capsule` per P31 isolation |
| Audit gate (Plan 15-05) | `/gsd-audit-milestone v0.20` slash command | `.planning/v0.20-MILESTONE-AUDIT.md` | Reads REQUIREMENTS + ROADMAP + STATE + per-phase VERIFICATION/SUMMARY/VALIDATION |
| Retrospective append (Plan 15-05) | Planning artifact (`.planning/RETROSPECTIVE.md`) | — | Living doc; v0.18 + v0.19 sections set the cadence |
| Carry-forward parking lot reconcile (Plan 15-05) | Planning artifact (`.planning/PROJECT.md`) | — | Canonical home for parking lot; updated at each milestone close |
| `15-VALIDATION.md` finalize (Plan 15-05) | Planning artifact (`.planning/phases/15-*/`) | — | Book-keeping Nyquist ledger; mirrors `12-VALIDATION.md` shape |
| `15-VERIFICATION.md` write (Plan 15-05) | Planning artifact (`.planning/phases/15-*/`) | — | Phase verifier output; mirrors `12-VERIFICATION.md` shape |
| Set `ready_to_archive: true` (Plan 15-05) | Planning artifact (`.planning/STATE.md`) | — | Precondition for `/gsd-complete-milestone v0.20` (run AFTER Phase 15 closes) |

**Key insight:** Every Phase 15 edit targets `.planning/*.md` files. ZERO source code edits. ZERO `pocs/`, `scripts/`, or `docs/` edits. Plan 15-04's bats rerun READS from these paths but does not modify them.

## Mechanical Reconciliation Surfaces

### Plan 15-01 — REQUIREMENTS.md edits

**File:** `.planning/REQUIREMENTS.md`

**11 `[ ] → [x]` flips required** (verified via `grep -n '^- \[ \]' .planning/REQUIREMENTS.md`):

| Line | REQ-ID | Source evidence |
|------|--------|------------------|
| 64 | DEMO-01 | Phase 14 `14-VERIFICATION.md` SC-1; `demo-01-live-platform-owner-list.bats` 3/3 GREEN |
| 65 | DEMO-02 | Phase 14 SC-2; `demo-02-live-tenant-owner-scoped-list.bats` 4/4 GREEN |
| 66 | DEMO-03 | Phase 14 SC-1+SC-2; `demo-03-live-pod-ops.bats` 6/6 GREEN |
| 67 | DEMO-04 | Phase 14 SC-2; `demo-04-live-tenant-secret-forbidden.bats` 2/2 GREEN |
| 68 | DEMO-05 | Phase 14 SC-2; `demo-05-live-cross-tenant-forbidden.bats` 4/4 GREEN |
| 69 | DEMO-06 | Phase 14 SC-3; `demo-06-live-platform-owner-cluster-admin-denials.bats` 3/3 GREEN + visceral live re-run |
| 75 | RUNBOOK-01 | Phase 14 SC-4; `runbook-01-static-acts.bats` 4/4 GREEN; `docs/poc-capsule-demo.md` 253 lines |
| 76 | RUNBOOK-02 | Phase 14 SC-4; `runbook-02-static-checklist.bats` 5/5 GREEN |
| 77 | RUNBOOK-03 | Phase 14 SC-4; `runbook-03-static-tls-noise.bats` 4/4 + `runbook-03-static-eks-three-tier.bats` 4/4 GREEN |
| 78 | RUNBOOK-04 | Phase 14 `passed_with_overrides`; UAT auto-attested-with-carry-forward → Plan 15-04 closes via live regression rerun + Plan 15-05 milestone-owner approval at audit gate |
| 79 | RUNBOOK-05 | Phase 14 SC-5; `runbook-05-static-charlie.bats` 4/4 GREEN |

**12 already `[x]` at Phase 15 open** (verified):
- Lines 45-50: RBAC-01..06 (Phase 13)
- Lines 56-58: SEED-01..03 (Phase 13)
- Lines 85-87: DELIVERY-01..03 (Phase 13)

**Plan 15-01 grep gate (final state after Wave 1 closes):**
- `grep -cE "^- \[x\] \*\*(RBAC|SEED|DEMO|RUNBOOK|DELIVERY)-" .planning/REQUIREMENTS.md` returns **23** (12 Phase-13 + 11 Phase-14 flipped).
- `grep -cE "^- \[ \] \*\*(RBAC|SEED|DEMO|RUNBOOK|DELIVERY)-" .planning/REQUIREMENTS.md` returns **0**.
- Future Requirements + v0.18/v0.19 carryover `[ ]` lines (98+) unchanged.

**Traceability table update (lines 132-160 area):** Each of the 11 flipped REQ rows currently says `Pending` — change to `Complete` (mirrors Phase 13 rows 138-146 which already say `Complete`).

**Inline spec-deviation amendments required** (D-15-03; planner verifies each at plan time against Phase 13/14 evidence):

- **RUNBOOK-03 (line 77) — OQ-1 TLS noise = `document-only`.** Phase 14 D-14-01 landed this verbatim. The REQ text already includes "per OQ-1 resolution — document-only is the recommended default" — no amendment needed; OQ-1 resolution = recommended default = no divergence. Cite "Phase 14 D-14-01" inline if planner wants explicit anchor.
- **RUNBOOK-05 (line 79) — OQ-5 new-tenant name = `charlie`.** Phase 14 D-14-02 landed this. REQ text says "per OQ-5: 'charlie' / 'demo' / 'team-foo' / other" — amend to lock `charlie` as the chosen name (parenthetical) + cite "Phase 14 D-14-02".
- **RUNBOOK-05 (line 79) — provision style = `live`.** Phase 14 D-14-03 landed this; REQ text already says "with the chosen name canonical across runbook + delivery mechanism + any scripted helpers" — implicitly compatible with `live`. Cite "Phase 14 D-14-03" inline if planner wants explicit anchor.
- **RBAC-01 (line 45) — OQ-2 Secrets policy = `read-only`.** Phase 13 D-13-01 landed `read-only` per Project briefing recommended default. REQ text says "Final Secrets policy ... resolved in discuss-phase per OQ-2" — amend to lock `read-only` as the resolved policy + cite "Phase 13 D-13-01".
- **SEED-03 (line 58) — OQ-3 hello-world shape = `Pod + Service`.** Phase 13 D-13-02 landed this. REQ text says "OQ-3-resolved choice" — amend to lock `Pod + Service` (with FQCI `docker.io/library/nginx:alpine` per Pitfall 13-P1) + cite "Phase 13 D-13-02".
- **DELIVERY-01 (line 85) — OQ-4 delivery = GitOps under `pocs/capsule/`** (NO Taskfile entry). Phase 13 D-13-03 landed this. REQ text says "either GitOps under `pocs/capsule/` ... or a `task seed-capsule-demo`" — amend to lock GitOps (with explicit "NO `task seed-capsule-demo` entry") + cite "Phase 13 D-13-03". This is already partly reflected in PROJECT.md `Validated` line 48 (`OQ-4 = GitOps under pocs/capsule/; NO Taskfile entry`).
- **RBAC-06 + RUNBOOK-01 — Capsule auto-assigned RoleBinding numbering instability (Pitfall 13-P7).** Plan 13-04 documented RoleBinding indices are Capsule controller-internal and renumber on `spec.owners[]` order changes. NOT a REQ deviation (REQ text doesn't pin indices) — but worth noting in Plan 15-01 SUMMARY as live-state-quirk-not-spec-deviation.

**No-deviation cases:** Plan 15-01 reads each of the 11 REQs against the live evidence and records "no deviation" vs "deviation: <description>" in the plan summary. The pattern from Plan 12-01: TEN-01 was the only spec deviation in v0.19 close-out; v0.20 has 3-4 candidate amendments (OQ-2, OQ-3, OQ-4, OQ-5 lock-ins) which are formally OQ resolutions rather than mid-flight surprises.

### Plan 15-02 — STATE.md edits

**File:** `.planning/STATE.md`

**Current state (verified via `Read`):**
- Frontmatter `status: completed` — premature; was set when Phase 14 marked complete but milestone is not actually complete until Phase 15 lands. Should be `executing` during Wave 1 and `ready_to_archive` at Wave 2 close.
- `stopped_at: Phase 15 context gathered` — fine for now; advances during Plan 15-02.
- `last_activity: 2026-05-20 -- Phase 14 marked complete` — advance past Phase 14 to Phase 15 entry, then to Phase 15 close in Plan 15-05.
- `progress.total_phases: 3` — wrong frame (only counts v0.20 phases 13/14/15, not lifetime). Phase 12 used `total_phases: 6` for v0.19 (Phases 7-12). v0.20 has 3 phases total. Acceptable framing but keep consistent.
- `progress.completed_phases: 2` (Phase 13 + Phase 14 complete) — advance to 3 after Phase 15 closes.
- `progress.total_plans: 9` — actually 14 (Phase 13: 5 + Phase 14: 4 + Phase 15: 5 anticipated per D-15-01). Plan 15-02 advances to 14.
- `progress.completed_plans: 9` — actually 9 at Wave 1 entry (Phase 13: 5 + Phase 14: 4); advances to 14 at Wave 2 close.
- `progress.percent: 100` — premature; should be 9/14 = 64% at Wave 1 entry, 14/14 = 100% at Wave 2 close.

**Performance Metrics By-Phase table** (lines 72-78 — currently has Phase 13/14/15 as TBD):

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 13 (RBAC + SEED + DELIVERY) | **5** (was TBD) | — | — |
| 14 (DEMO + RUNBOOK) | **4** (was TBD) | — | — |
| 15 (Close-out + Retrospective) | **5** target per D-15-01 (was TBD) | — | — |

**Plan counts verified via** `ls .planning/phases/{13,14}-*/[01]*-PLAN.md | wc -l` = 9 (Phase 13: 13-00, 13-01, 13-02, 13-03, 13-04 = 5; Phase 14: 14-00, 14-01, 14-02, 14-03 = 4). Phase 15 plans not yet written at research time; planner discretion confirms 5 per D-15-01.

**Velocity counters** (lines 36-42):
- `Total plans completed (v0.18): 35` — pre-existing; do not touch.
- `Total plans completed (v0.19): 18` — pre-existing; do not touch.
- **Append `Total plans completed (v0.20): 14`** as a new line under v0.19. Mirrors Phase 12 pattern (Plan 12-02 added v0.19 total).

**Current Position block** (lines 28-33): currently says `Phase: 14 — COMPLETE / Plan: 1 of 4 / Status: Phase 14 complete`. Plan 15-02 flips to `Phase: 15 (v0.20-close-out) — EXECUTING / Plan: 1 of 5 (Wave 1 in flight) / Status: Phase 15 close-out reconciliation` and Plan 15-05 self-close advances to `Phase: 15 — COMPLETE / Plan: 5 of 5 / Status: v0.20 milestone ready to archive`.

**Pending Todos block** (lines 142-146): list 4 already-RESOLVED bullets carried over from v0.19. NONE need to be marked RESOLVED by Plan 15-02 — they were already RESOLVED in Plan 12-02. Plan 15-02 has NO Pending Todos reconciliation work (unlike Plan 12-02 which had 4 bullets to mark RESOLVED). Possibly: append Phase 7 HUMAN-UAT items 2/3/4 status (still active environmental items per `STATE.md`); planner discretion.

**Blockers/Concerns block** (lines 150-156): pre-existing entries about v0.19/v0.20 cluster dependencies; Plan 15-02 may append a note that the live cluster `origin/main` push gap (per Phase 14 D-14 + 14-03 evidence log) is resolved by Plan 15-04 prerequisite.

### Plan 15-03 — ROADMAP.md edits

**File:** `.planning/ROADMAP.md`

**Current state (verified via `Read`):**
- Phase Summary §"Phase 13": `[x]` Complete ✓ (line 71)
- Phase Summary §"Phase 14": `[ ]` (line 72) — flip to `[x]`
- Phase Summary §"Phase 15": `[ ]` (line 73) — flip to `[x]` (Plan 15-05's self-close, NOT Plan 15-03)
- Progress table line 151: `| 14. ... | v0.20 | 0/4 | Not started | - |` — flip to `| 14. ... | v0.20 | 4/4 | Complete | 2026-05-19 |` (Phase 14 closed 2026-05-19 per `14-VERIFICATION.md`)
- Progress table line 152: `| 15. ... | v0.20 | 0/TBD | Not started | - |` — flip to `| 15. ... | v0.20 | 5/5 | Complete | 2026-05-21 |` (Plan 15-05's self-close, NOT Plan 15-03; OR Plan 15-03 sets `0/5 | In progress | - |` mid-phase)
- Progress table line 150: `| 13. ... | v0.20 | 5/5 | Complete    | 2026-05-19 |` — note the extra spaces in the `Complete    |` cell; cosmetic but stale, planner may normalize.

**Within-document contradiction sweep:** ROADMAP.md lines 39, 70-73 carry the milestone-level Phase Summary; lines 138-152 carry the Progress table. They MUST match. Phase 12 Plan 12-06 Task 1 verified this same consistency for v0.19; Plan 15-03 inherits the verification idiom.

**Narrative-drift sweep:** v0.19 Phase 12 had a "15 stale" → "18 v0.19 mandatory" narrative correction at ROADMAP.md lines 44/141/143 (Plan 12-06 Task 2). v0.20 has NO equivalent count-drift in ROADMAP.md — the milestone-level Phase Summary already cites "23 v0.20 mandatory" implicitly. No narrative-drift edits anticipated, but Plan 15-03 should sweep for any `0/4`-style stale counts.

**Phase 15 success-criteria text** (lines 126-131) is correct as-is (5 criteria explicitly listed); Plan 15-03 does NOT edit success criteria, only Progress table + Phase Summary checkboxes.

**Plans block under Phase 15** (line 132: "**Plans**: TBD") — Plan 15-03 expands to explicit plan list once Plan 15-00..15-04 are written (the planner controls this in PLAN.md files; Plan 15-03 may sync the ROADMAP text to match).

### Plan 15-04 — Live regression rerun

**File:** `.planning/phases/15-v0-20-milestone-close-out-retrospective/15-04-live-rerun-evidence.log` (NEW)

**Bats glob** (per D-15-02 + verified `ls tests/bats/` output):

```bash
# Phase 13 live bats (post-Wave-0 + post-implementation; per 13-VALIDATION.md)
bats tests/bats/rbac-{05,06,07,08,09,10}-live-*.bats
bats tests/bats/seed-{02,03,04}-live-*.bats
bats tests/bats/delivery-{03,04}-live-*.bats

# Phase 14 live bats
bats tests/bats/demo-{01,02,03,04,05,06}-live-*.bats

# Phase 14 static bats (runbook structural)
bats tests/bats/runbook-{01,02,03,05}-static-*.bats

# Phase 13 static bats (RBAC + SEED + DELIVERY shape contracts)
bats tests/bats/rbac-{01,02,03,04}-static-*.bats
bats tests/bats/seed-01-static-*.bats
bats tests/bats/delivery-{01,02}-static-*.bats
```

**Single shell expansion (planner discretion; either of these patterns is fine):**

```bash
bats tests/bats/rbac-*.bats \
     tests/bats/seed-*.bats \
     tests/bats/delivery-{01,02,03,04}-*.bats \
     tests/bats/demo-*.bats \
     tests/bats/runbook-*.bats \
     --duration
```

Anticipated count: 159 (Phase 13 NEW) + 44 (Phase 14 NEW) = ~203 @tests. Per `14-02-full-suite-evidence.log`: "Phase 13 RBAC-* + SEED-* + DELIVERY-* GREEN: 163; Phase 14 DEMO + RUNBOOK GREEN: 44" = 207 @tests target.

**`delivery-05-live-slo-regression.bats` skip semantics:** env-gated by `KARYON_REBUILD_APPROVED=1` (Pitfall 11-P5). Plan 15-04 runs `task rebuild` directly as a wall-clock-measured cold-run + may opt-in to the bats wrapper by setting `KARYON_REBUILD_APPROVED=1`. Both paths satisfy DELIVERY-02.

**Kubeconfig env vars (per Phase 14 `14-CONTEXT.md` D-14-05):**

```bash
# Mint platform-owner kubeconfig
bash scripts/poc/capsule/issue-platform-owner-kubeconfig.sh --duration 2h --write-to /tmp/karyon-tenants/platform-owner.kubeconfig
export PO_KC=/tmp/karyon-tenants/platform-owner.kubeconfig

# Mint tenant-owner kubeconfigs (alpha + bravo)
bash scripts/poc/capsule/issue-tenant-kubeconfig.sh alpha-owner alpha --write-to /tmp/karyon-tenants/tenant-alpha.kubeconfig
bash scripts/poc/capsule/issue-tenant-kubeconfig.sh bravo-owner bravo --write-to /tmp/karyon-tenants/tenant-bravo.kubeconfig
export TO_ALPHA_KC=/tmp/karyon-tenants/tenant-alpha.kubeconfig
export TO_BRAVO_KC=/tmp/karyon-tenants/tenant-bravo.kubeconfig
```

**Cluster-admin denial assertions (per CONTEXT.md Success Criterion 3):**

```bash
# Platform-owner ceiling — must return "no"
kubectl --kubeconfig=$PO_KC auth can-i '*' '*'

# Tenant-workload-editor ceiling — must return "no" for both alpha and bravo
kubectl --kubeconfig=$TO_ALPHA_KC auth can-i '*' '*'
kubectl --kubeconfig=$TO_BRAVO_KC auth can-i '*' '*'
```

These are already asserted inside `rbac-08-live-platform-owner-grant-matrix.bats` Test 1 + `rbac-06-live-tenant-kubeconfig.bats` Test 1 (per Phase 13 `13-VERIFICATION.md` REQ Coverage rows for RBAC-04 + RBAC-02). Plan 15-04 may re-run them inline as visceral evidence or rely on the bats assertions.

**`task rebuild` SLO assertion shape (per CONTEXT.md Success Criterion 3 + 13-VALIDATION.md Manual-Only row 1):**

```bash
# Cold-run with wall-clock timing (per Phase 11 + Phase 13 precedent)
time KARYON_REBUILD_APPROVED=1 task rebuild
# Assert: real time < 230s (v0.18 baseline carried through v0.19 VAL-04)

# Followed by health-check exit 0 verification (v0.18 + v0.19 contract)
task health-check
echo $?
# Expected: 0
```

Plan 15-04 captures the wall-clock duration verbatim in `15-04-live-rerun-evidence.log` + asserts `< 230s` + asserts `task health-check` exit 0.

**Pre-demo checklist preamble (per Phase 14 D-14-05):**

```bash
# Step 1: cluster reachable
kubectl --context k3d-spoke-capsule get nodes
# Expected: STATUS Ready

# Step 2: hub Flux reconciling
flux --context k3d-hub-flux get kustomizations | grep capsule
# Expected: poc-capsule-spoke + poc-capsule-spoke-rbac + poc-capsule-spoke-tenants all SUSPENDED=False + READY=True

# Step 3: tenant state intact
kubectl --context k3d-spoke-capsule get tenants
# Expected: alpha + bravo, STATE=Active

# Step 4: fix-dns if needed
task fix-dns-poc-capsule  # only if step 1 returned NotReady or DNS resolution fails

# Step 5: idempotent reset of demo tenant
kubectl --kubeconfig=$PO_KC delete tenant charlie --ignore-not-found

# Step 6: ephemeral state cleanup (per Phase 14 14-03 evidence log lesson)
# Verify origin/main is at Phase 13 HEAD or later before invoking bats
git fetch origin
git log origin/main --oneline -1
# Expected: SHA matches or is later than 897a075 (Phase 14 close commit)
```

**Failure handling (per D-15-02):** If any bats RED or `task rebuild` exceeds 230s or `task health-check` exits non-zero, Phase 15 close-out blocks. The remediation is NOT a Phase 15 fix — it's a regression in Phase 13/14 that lands as its own remediation plan (likely `/gsd-insert-phase 14.1` or a Phase 13/14 patch). Plan 15-04 halts and surfaces the failure inline in its SUMMARY.

**Evidence log shape (mirrors Phase 14's `14-02-full-suite-evidence.log` + `14-03-uat-cold-run-evidence.log`):** plain `.log` file committed under the phase dir. Header block with run metadata (UTC start/end, operator, branch, cluster context, HEAD commit), then verbatim command + output, then summary table with GREEN/RED/SKIP per category, then carry-forward inheritance analysis.

### Plan 15-05 — Audit + retrospective + verifier + parking lot + VALIDATION + VERIFICATION

**Files modified:**
- `.planning/v0.20-MILESTONE-AUDIT.md` (NEW — overwritten by `/gsd-audit-milestone v0.20`)
- `.planning/RETROSPECTIVE.md` (append v0.20 section)
- `.planning/PROJECT.md` (reconcile carry-forward parking lot)
- `.planning/STATE.md` (set `ready_to_archive`)
- `.planning/ROADMAP.md` (Phase Summary line 73 + Progress table line 152: Phase 15 `[x]` Complete)
- `.planning/phases/15-v0-20-milestone-close-out-retrospective/15-VALIDATION.md` (NEW — `status: final`)
- `.planning/phases/15-v0-20-milestone-close-out-retrospective/15-VERIFICATION.md` (NEW — verifier output)

**Audit gate sequence:**

1. **Pre-flight check** (mirrors Plan 12-07 Task 1 — exact-count grep semantics):
   - `grep -cE "^- \[x\] \*\*(RBAC|SEED|DEMO|RUNBOOK|DELIVERY)-" .planning/REQUIREMENTS.md` returns **23** (Plan 15-01 done)
   - `grep -cE "^- \[ \] \*\*(RBAC|SEED|DEMO|RUNBOOK|DELIVERY)-" .planning/REQUIREMENTS.md` returns **0**
   - `grep "^- \[x\] \*\*Phase 14:" .planning/ROADMAP.md` returns 1 (Plan 15-03 done; Phase 15 still `[ ]` at this moment)
   - STATE.md frontmatter has `total_plans: 14` + `completed_plans: 9` + `percent: 64` (Plan 15-02 mid-phase state)
   - `15-04-live-rerun-evidence.log` exists with `RED count: 0` line for Phase 13/14 categories
2. **Invoke audit:** `/gsd-audit-milestone v0.20`
3. **Read result:** `head -10 .planning/v0.20-MILESTONE-AUDIT.md`
4. **Decision tree (per D-15-06 hard-block):**
   - **`status: passed`** → proceed to Phase 15 self-close edits
   - **`status: tech_debt`** with non-blocking ADDON-style items → operator-decision checkpoint (Plan 12-07 Contingency 1 precedent: accept tech_debt as v0.21-deferred, OR purge items and re-run audit)
   - **`status: gaps_found`** → HARD BLOCK; surface gaps inline in SUMMARY; orchestrator inserts remediation plan (e.g., `/gsd-insert-phase 14.2` or new Plan 15-06) and reruns audit
5. **Phase 15 self-close edits** (after `passed`):
   - ROADMAP Phase 15 `[ ] → [x]` + Progress table `0/5 → 5/5 Complete YYYY-MM-DD`
   - STATE.md `status: ready_to_archive`, `completed_phases: 3`, `completed_plans: 14`, `percent: 100`, `last_activity: YYYY-MM-DD -- Phase 15 complete; v0.20 audit passed; milestone ready to archive`
   - 15-VALIDATION.md frontmatter `status: final` + `nyquist_compliant: true` + `wave_0_complete: true` + `finalized: YYYY-MM-DD` + `finalized_evidence: "book-keeping phase; no Wave-0 scaffold required..."`
   - REQUIREMENTS.md Traceability footer appended (mirrors Plan 12-07 Task 3 Edit 6 pattern)

**Retrospective append shape (per D-15-04, mirrors v0.18 + v0.19 cadence in existing `RETROSPECTIVE.md`):**

```markdown
## Milestone: v0.20 — Capsule POC Demo & RBAC Polish

**Shipped:** YYYY-MM-DD
**Phases:** 3 (13-15) | **Plans:** 14 | **Tasks:** TBD | **Commits:** TBD | **Timeline:** 2026-05-19 → YYYY-MM-DD

### What Was Built
- `tenant-workload-editor` ClusterRole (narrower than k8s `edit`) + per-tenant `human-tenant-owner` SAs
- Platform-owner identity (`platform-owner@capsule-system`) + dual-subject CRB + co-ownership on alpha + bravo + new-tenant template
- `GlobalTenantResource` auto-propagation (≤ 60s; Pod + Service shape per D-13-02)
- `docs/poc-capsule-demo.md` 6-act runbook + `docs/capsule-on-eks.md` three-tier-on-EKS append
- Live two-perspective demo verification (22 DEMO @tests GREEN; 21 RUNBOOK @tests GREEN)
- OQ-1..5 all resolved + amended inline in REQUIREMENTS.md

### What Worked
- Lean / additive milestone framing held — no scope creep across 3 phases
- Wave 0 RED bats Nyquist gate continued to pay off (Phase 13: 19 new bats files; Phase 14: 11 new bats files; all GREEN end-of-phase)
- UAT cold-read auto-attestation-with-carry-forward pattern (Plan 14-03) preserved the audit trail when origin/main lag blocked human cold-read
- 6-act runbook structure caught actual demo friction at structural level (runbook-01 / runbook-03 bats families)

### What Was Inefficient
- Phase 14 Plan 14-02 destroy-poc mid-suite caused 28 carry-forward bats REDs (Phase 9 TEN-01..06 + v0.18 health-check) — destructive test ordering deserves a Phase 14-or-earlier discipline (test suite should NOT contain a destructive test that breaks downstream live tests in the same run)
- Live cluster lag against `origin/main` (Phase 14 14-03 evidence: HEAD=897a075 vs origin/main@49e264a2) blocked mechanical UAT cold-run; the right operator action (`git push origin main`) is owned outside auto-mode
- STATE.md frontmatter `status: completed` set prematurely at Phase 14 close (before Phase 15 ran) — close-out reconciliation reverts to `executing` then `ready_to_archive`

### Patterns Established
- Three-tier permission model articulation (Tier 1 Cloud Ops / Tier 2 Karyon Platform Team / Tier 3 Tenant Devs)
- Co-owner CRB pattern for platform-owner LIST/WATCH/GET/LOGS/EXEC (Group + SA dual subjects)
- `new-tenant.sh` provisioning template with platform-owners group + platform-owner SA + human-tenant-owner SA in `spec.owners[]` by default
- Demo runbook 6-act cadence (architecture → platform-owner role → provision live → GTR auto-seed → two perspectives → cleanup) with executable pre-demo checklist + "Known noise" appendix
- Auto-attestation-with-carry-forward UAT disposition (Plan 14-03 precedent; honored by Phase 15 SC-3 live regression rerun)

### OQ Resolutions

| OQ | Resolution | Owning Phase + D-code |
|----|-----------|----------------------|
| OQ-1 | TLS noise = document-only | Phase 14 D-14-01 |
| OQ-2 | Secrets policy = read-only | Phase 13 D-13-01 |
| OQ-3 | Hello-world shape = Pod + Service | Phase 13 D-13-02 |
| OQ-4 | Delivery path = GitOps under `pocs/capsule/` (NO Taskfile) | Phase 13 D-13-03 |
| OQ-5 | Marquee name = `charlie`; provision-live | Phase 14 D-14-02 + D-14-03 |

### Key Lessons
1. Living-doc retrospective continues to pay off (v0.18 → v0.19 → v0.20 cross-milestone trends visible in one scroll)
2. Spec-deviation-inline-in-REQUIREMENTS.md (v0.19 TEN-01 pattern; v0.20 OQ-2/3/4/5 lock-ins) is the canonical mechanism for capturing planning-time decisions in implementation-time evidence
3. Audit gate failure-handling SHOULD be a hard block (D-15-06); shipping a partially-audited milestone defeats the audit gate purpose

### Carry-forward updates
- **Closed during v0.20:** none (purely additive milestone; no v0.19 carry-forward items addressed)
- **Added to parking lot:** TLS-fix-at-cert-layer (OQ-1 was document-only); revisit of `task demo-capsule` wrapper at graduation or POC-ergonomics milestone

### Cost Observations
- Model mix: TBD
- Sessions: TBD
- Notable: TBD
```

**Carry-forward parking lot reconciliation (PROJECT.md lines 87-99 area):**

Current state (verified via `Read`):
- 9 active parking lot items: capsule-addon-fluxcd Trial, G-04 architectural decision, `KARYON_PHASE11_STRICT_LIVE=1`, slo-regression-live `KARYON_REBUILD_APPROVED`, pre-existing markdownlint, gitleaks `proxy-06` fixture, Phase 1-5 shellcheck, first-push CI verification, real secret management, stale frontmatter reconciliation.

Plan 15-05 appends (per D-15-05):
- **Fix `tls: bad certificate` capsule-controller chatter at the cert-rotation layer** (was OQ-1 document-only in v0.20) — cert-manager wiring or proper CA distribution on capsule-controller; belongs to a future capsule-graduation phase or production EKS cut.
- **`task demo-capsule` Taskfile wrapper** — declined in Phase 14 D-14 Discretion note for P31 isolation reasons; revisit at graduation or in a POC-ergonomics milestone if UAT identifies friction.
- **(verify against `deferred-items.md`)** Phase 13 `deferred-items.md` currently only lists pre-existing inheritance bats failures (poc-mount-01 + tenants-04-static-dependson) — these are NOT v0.20 close-out concerns; they're already documented as pre-existing inheritance per Phase 13 verifier. NOT appended to parking lot.

Plan 15-05 closes (per D-15-05):
- **None expected** — v0.20 was purely additive; did not address any v0.19 carry-forward.

## Open Question Deviation Table

Per CONTEXT.md (Phase 15 has no OQs of its own; all 5 v0.20 OQs were resolved in Phase 13/14 discuss-phases). The table below compares MILESTONE-BRIEFING.md recommended defaults to landed decisions:

| OQ | Briefing recommended default | Landed decision | Resolver | REQ requiring inline amend |
|----|------------------------------|-----------------|----------|----------------------------|
| OQ-1 | document-only | document-only | Phase 14 D-14-01 | RUNBOOK-03 (line 77) — REQ text already includes "document-only is the recommended default"; NO substantive amend; cite "Phase 14 D-14-01" inline if planner wants explicit anchor |
| OQ-2 | read-only | read-only | Phase 13 D-13-01 | RBAC-01 (line 45) — REQ text says "Final Secrets policy ... resolved in discuss-phase per OQ-2"; AMEND to lock `read-only` + cite "Phase 13 D-13-01" |
| OQ-3 | Pod + Service | Pod + Service (FQCI `docker.io/library/nginx:alpine` per Pitfall 13-P1) | Phase 13 D-13-02 | SEED-03 (line 58) — REQ text says "OQ-3-resolved choice"; AMEND to lock `Pod + Service` + cite "Phase 13 D-13-02" |
| OQ-4 | (no recommended default; presented as either-or) | GitOps under `pocs/capsule/` (NO Taskfile entry) | Phase 13 D-13-03 | DELIVERY-01 (line 85) — REQ text says "either GitOps ... or a `task seed-capsule-demo`"; AMEND to lock GitOps with "NO `task seed-capsule-demo` entry" + cite "Phase 13 D-13-03" |
| OQ-5 (name) | (no recommended default; "charlie / demo / team-foo / other") | `charlie` | Phase 14 D-14-02 | RUNBOOK-05 (line 79) — REQ text says "per OQ-5: 'charlie' / 'demo' / 'team-foo' / other"; AMEND to lock `charlie` + cite "Phase 14 D-14-02" |
| OQ-5 (style) | live (recommended) | live | Phase 14 D-14-03 | RUNBOOK-05 (line 79) — REQ text says "with the chosen name canonical across runbook + delivery mechanism + any scripted helpers" (compatible with `live`); cite "Phase 14 D-14-03" inline if planner wants explicit anchor |

**Net deviation count:** 0 substantive deviations (all 5 OQ resolutions match the briefing's recommended defaults where defaults existed; OQ-4 + OQ-5 name selection had no defaults). **5 lock-in amendments** to fold OQ-resolved choices into REQ spec text (RBAC-01 OQ-2, SEED-03 OQ-3, DELIVERY-01 OQ-4, RUNBOOK-05 OQ-5 name + style). RUNBOOK-03 OQ-1 needs no substantive amend (REQ text already cites recommended default verbatim).

**Comparison to v0.19 Phase 12:** v0.19 had ONE spec deviation (TEN-01 `forceTenantPrefix: true → false` per Plan 11-07 D-11-07 live repair). v0.20 has ZERO spec deviations from briefing-time framing — only OQ resolutions that need to be folded into REQ text as lock-ins. This is consistent with the "lean / additive milestone" framing.

## Phase 12 → Phase 15 Plan Mapping Table

| Phase 12 plan (v0.19 close-out, 7 plans) | Phase 15 inheritance | Notes |
|------------------------------------------|----------------------|-------|
| **12-01** REQUIREMENTS.md flip + TEN-01 inline amend + narrative count fix | **Plan 15-01** — direct template | v0.20 has 11 flips (vs v0.19's 18); 4 OQ-lock-in amendments (vs v0.19's 1 TEN-01 amend); no narrative count drift to fix (v0.19 had "15 → 18"; v0.20 has no equivalent) |
| **12-02** STATE.md frontmatter + body update + Pending Todos RESOLVED | **Plan 15-02** — adapted | v0.20 has ZERO stale Pending Todos to reconcile (Plan 12-02 already cleared v0.19's 4 bullets); Plan 15-02's body work is lighter (Current Position + Performance Metrics By-Phase table population) |
| **12-03** Phase 11 VERIFICATION + PHASE-VERIFICATION supersedure | **OMITTED entirely** | Phase 13/14 VERIFICATION.md files are already `status: final` + `passed_with_overrides` at Phase 15 open; no supersedure needed. This is the single largest savings vs Phase 12 |
| **12-04** 5 VALIDATION.md ledgers `draft → final` flip | **OMITTED for Phases 13/14** (both already `status: final` + `nyquist_compliant: true` + `wave_0_complete: true` per `13-VALIDATION.md` + `14-VALIDATION.md` reads); **Plan 15-05 includes a 15-VALIDATION.md finalize** (`status: final` for Phase 15's own ledger only) | Phase 15's own VALIDATION ledger is the only one needing the flip (book-keeping phase pattern; mirrors `12-VALIDATION.md`) |
| **12-05** Stale todo move pending/ → completed/ | **OMITTED entirely** | `gsd-sdk query todo.match-phase 15` returned 0 matches; no pending todos to archive |
| **12-06** ROADMAP.md verify Progress table consistency + narrative count fix | **Plan 15-03** — direct template | v0.20 Progress table needs Phase 14 + Phase 15 row flips (vs v0.19 which only needed verification because gap-closure commits had already updated it); no narrative count drift to fix |
| **12-07** `/gsd-audit-milestone v0.19` + Phase self-close (Wave 2 gate) | **Plan 15-05** — direct template + extended scope | Plan 15-05 also does retrospective append (D-15-04) + carry-forward parking lot reconcile (D-15-05) + 15-VERIFICATION.md write — Phase 12 Plan 12-07 did NOT do these because Phase 12 had no retrospective append (v0.19 retrospective was written by `/gsd-complete-milestone v0.19` post-Phase-12 per workflow Step `write_retrospective`); v0.20 changes the pattern per D-15-04 |

**Live regression rerun (Plan 15-04)** — NO Phase 12 analog. Phase 12 v0.19 had `12-VALIDATION.md` documenting that hygiene tools (gitleaks + markdownlint) were the verification surface; no live cluster rerun. Phase 15 adds Plan 15-04 because the v0.20 close-out specifically requires regression-verifying the three-tier model live (Success Criterion 3). This is a v0.20-specific addition not inherited from Phase 12.

**Net plan count:** Phase 15 = 5 plans (15-01 REQ + 15-02 STATE + 15-03 ROADMAP + 15-04 live rerun + 15-05 audit+retro+verifier+parking-lot+VALIDATION+VERIFICATION) vs Phase 12 = 7 plans (12-01 + 12-02 + 12-03 + 12-04 + 12-05 + 12-06 + 12-07). Compression = 2 plans (12-03 supersedure omitted + 12-05 todo-move omitted + 12-04 VALIDATION mostly omitted + Plan 15-04 added).

## `/gsd-audit-milestone v0.20` Gate Semantics

**Workflow source:** `$HOME/.claude/get-shit-done/workflows/audit-milestone.md` (verified via Read).

**3-source cross-reference (per workflow Step 5):**

The audit reads three sources for each REQ-ID and applies the Status Determination Matrix:

| VERIFICATION.md Status | SUMMARY frontmatter `requirements-completed` | REQUIREMENTS.md checkbox | → Final Status |
|------------------------|----------------------------------------------|--------------------------|----------------|
| `passed` (or `passed_with_overrides`) | REQ listed | `[x]` | **satisfied** |
| `passed` | listed | `[ ]` | **satisfied** (audit logs "update checkbox" recommendation) |
| `passed` | missing | any | **partial** (manual verification needed) |
| `gaps_found` | any | any | **unsatisfied** |
| missing | listed | any | **partial** (verification gap) |
| missing | missing | any | **unsatisfied** |

**FAIL gate:** ANY `unsatisfied` requirement forces `status: gaps_found`. **Orphan detection:** any REQ-ID in REQUIREMENTS.md traceability but absent from ALL phase VERIFICATION.md files = orphaned = treated as `unsatisfied`.

**Status outcomes:**
- `passed` — all requirements satisfied + no critical gaps + minimal tech_debt
- `gaps_found` — critical blockers exist (any `unsatisfied` REQ)
- `tech_debt` — no blockers but accumulated deferred items need review

**Nyquist discovery (workflow Step 5.5):** Per-phase `VALIDATION.md` is parsed for `nyquist_compliant` + `wave_0_complete`. Classification: COMPLIANT (true + all green) / PARTIAL (false or red/pending) / MISSING (no VALIDATION.md). Audit YAML appends `nyquist: { compliant_phases, partial_phases, missing_phases, overall }`.

**For Phase 15 specifically:**
- `15-VALIDATION.md` is the new file Plan 15-05 creates with `status: final` + `nyquist_compliant: true` + `wave_0_complete: true` (book-keeping phase; vacuous Nyquist satisfaction).
- Phase 13/14 VALIDATION.md ledgers are already final per Reads above.
- Expected Nyquist overall: 3/3 phases COMPLIANT.

**Audit output file:** `.planning/v0.20-MILESTONE-AUDIT.md` (overwritten by the audit workflow per Step 6).

**Failure decision tree (per D-15-06 + Plan 12-07 Task 2 Contingency precedent):**

1. **`status: passed`** → proceed to Plan 15-05 Phase self-close + `ready_to_archive: true`
2. **`status: tech_debt`** with ONLY accumulated v0.19 carry-forward parking lot items (acceptable) → operator-decision checkpoint:
   - **Path X (accept):** acknowledge tech_debt as acceptable v0.21-deferred per CONTEXT.md D-15-06's "remediate" framing
   - **Path Y (remediate):** open a new plan (e.g., Plan 15-06) to address the tech_debt items + re-run audit
3. **`status: gaps_found`** for non-ADDON / non-carry-forward reasons → HARD BLOCK; orchestrator inserts remediation plan (e.g., `/gsd-insert-phase 14.2` or new Plan 15-06) and re-runs audit; milestone NOT marked `ready_to_archive` until audit returns `passed`

**Expected audit failure modes for v0.20 (verified against current artifact state):**

- **Likely-pass:** All 23 REQs have evidence in Phase 13/14 VERIFICATION.md REQ Coverage tables; both VALIDATION.md ledgers are final.
- **Possible tech_debt:** RUNBOOK-04 (UAT human cold-read) is carried forward in Phase 14 `14-VERIFICATION.md` with `status: passed_with_overrides`. Plan 15-04's live regression rerun + Plan 15-05's audit gate must collectively satisfy the audit's REQ Coverage check for RUNBOOK-04 OR the audit may report it as partial.
- **Possible orphan risk:** Plan 15-01 must populate the REQUIREMENTS.md Traceability table rows for DEMO-* + RUNBOOK-* with `Complete` status; if left as `Pending`, the audit's 3-source cross-reference may flag inconsistency.

## Nyquist Validation Ledger for Book-Keeping Phases (Phase 12 idiom inherited)

**Verified via Read of `12-VALIDATION.md`:** Book-keeping phases satisfy the Nyquist gate vacuously. The pattern (Phase 12 → Phase 15):

**Frontmatter (required):**
```yaml
---
phase: 15
slug: v0-20-close-out-retrospective
status: final
nyquist_compliant: true
wave_0_complete: true
created: 2026-05-20
finalized: YYYY-MM-DD
finalized_evidence: "Phase 15 is a book-keeping reconciliation phase with no own Wave-0 scaffold (per 15-VALIDATION.md §Wave 0 Requirements `None`; mutates only `.planning/*.md` files; verification surface IS file content). Phase gate `/gsd-audit-milestone v0.20` returns `passed` per 15-07-SUMMARY.md (audit re-run YYYY-MM-DD). nyquist_compliant set true because every Wave-1 plan's `<acceptance_criteria>` is grep-verifiable AND Plan 15-04 live regression rerun (Phase 13 + Phase 14 bats subset + `task rebuild` SLO) is the falsifier for Success Criterion 3 (three-tier model regression-verified live). wave_0_complete set true because no Wave 0 was required per the phase character (book-keeping; D-15-07)."
---
```

**Body sections required (per `12-VALIDATION.md` shape):**

- `## Test Infrastructure` table — for Phase 15, the relevant frameworks are bats (Plan 15-04 live rerun) + `task rebuild` (Plan 15-04 SLO). Hygiene tools (gitleaks, markdownlint) are pre-existing + repo-wide; cite as live-evidence gates if planner wants.
- `## Sampling Rate` — "After every task commit: n/a (file edits); After every plan wave: bats subset sanity check; Before /gsd-verify-work: full Phase 13 + Phase 14 bats subset GREEN per Plan 15-04 + audit returns passed per Plan 15-05"
- `## Per-Task Verification Map` — table with grep-verifiable acceptance criteria; for Plan 15-04 row, the automated command is the bats glob from §Plan 15-04 above
- `## Wave 0 Requirements` — "None. Phase 15 has no Wave 0 scaffold requirement — no new tests are introduced; falsifiers for the three-tier model live in Phase 13/14 bats and re-run as-is in Plan 15-04."
- `## Manual-Only Verifications` — table including the audit gate (`/gsd-audit-milestone v0.20` returns `passed`) + RUNBOOK-04 human cold-read carry-forward closure (Plan 14-03 carry-forward retired by Plan 15-04 + Plan 15-05 milestone-owner approval at audit gate)
- `## Validation Sign-Off` — bulleted checklist mirroring `12-VALIDATION.md` (all tasks have grep-verifiable acceptance criteria; sampling continuity n/a for book-keeping; no Wave 0 needed; feedback latency < 30s for grep checks + ~5min for full bats subset + ~3min for `task rebuild`)
- `**Approval:** pending` initially; Plan 15-05 flips to `**Approval:** approved (verifier signed off — Plan 15-05 verifier YYYY-MM-DD)`

## Validation Architecture (Nyquist gate — book-keeping vacuous + live regression as the close-out's falsifier)

### Test Framework
| Property | Value |
|----------|-------|
| Framework | bats-core 1.11.0 (Plan 15-04 live regression rerun) + bash `time` wrapper for `task rebuild` (Plan 15-04 SLO assertion) |
| Config file | `tests/bats/test_helper.bash` (existing); no new config needed for Phase 15 |
| Quick run command | `bats tests/bats/{demo,runbook}-*.bats --duration` (Phase 14 subset; ~30s) |
| Full suite command | `bats tests/bats/{rbac-{01,02,03,04}-static,rbac-{05,06,07,08,09,10}-live,seed-*,delivery-{01,02,03,04}-*,demo-*,runbook-*}.bats --duration` + `time KARYON_REBUILD_APPROVED=1 task rebuild && task health-check` |
| Estimated runtime | ~5 minutes bats subset + ~3 minutes `task rebuild` cold-run = ~8 minutes total |

### Phase Requirements → Test Map

Phase 15 has NO new REQ-IDs. Closes 23 v0.20 mandatory checkboxes against live evidence from Phase 13/14. Below table maps each of the 11 still-`[ ]` REQs to the Phase 14 bats falsifier that proves it (and which Plan 15-01 then flips):

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DEMO-01 | Platform-owner sees all tenants + co-owner ns LIST/pods -A | live | `bats tests/bats/demo-01-live-platform-owner-list.bats -x` | ✅ Phase 14 W0 |
| DEMO-02 | Tenant-owner via proxy:30443 scoped LIST | live | `bats tests/bats/demo-02-live-tenant-owner-scoped-list.bats -x` | ✅ Phase 14 W0 |
| DEMO-03 | Positive control: tenant-owner + PO get/logs/exec | live | `bats tests/bats/demo-03-live-pod-ops.bats -x` | ✅ Phase 14 W0 |
| DEMO-04 | Tenant-owner Secret create Forbidden | live | `bats tests/bats/demo-04-live-tenant-secret-forbidden.bats -x` | ✅ Phase 14 W0 |
| DEMO-05 | Symmetric cross-tenant Forbidden (alpha ↔ bravo) | live | `bats tests/bats/demo-05-live-cross-tenant-forbidden.bats -x` | ✅ Phase 14 W0 |
| DEMO-06 | Platform-owner Forbidden on 3 cluster-admin actions | live | `bats tests/bats/demo-06-live-platform-owner-cluster-admin-denials.bats -x` | ✅ Phase 14 W0 |
| RUNBOOK-01 | 6 acts + Expected output blocks structural | static | `bats tests/bats/runbook-01-static-acts.bats -x` | ✅ Phase 14 W0 |
| RUNBOOK-02 | Pre-demo checklist executable (not narrative) | static | `bats tests/bats/runbook-02-static-checklist.bats -x` | ✅ Phase 14 W0 |
| RUNBOOK-03 | TLS noise + ADR-008 + capsule-on-eks.md three-tier | static | `bats tests/bats/runbook-03-static-tls-noise.bats tests/bats/runbook-03-static-eks-three-tier.bats -x` | ✅ Phase 14 W0 |
| RUNBOOK-04 | Human cold-read UAT ≤ 15 min | manual-only | (manual UAT; auto-attested-with-carry-forward in Plan 14-03; retired by Plan 15-04 live rerun + Plan 15-05 audit gate + optional human-cold-read on origin/main land) | ⚠️ Phase 14 14-VALIDATION row 1 |
| RUNBOOK-05 | `charlie` canonical across runbook + scripts + bats | static | `bats tests/bats/runbook-05-static-charlie.bats -x` | ✅ Phase 14 W0 |

### Sampling Rate
- **Per task commit:** n/a — Phase 15 tasks are `.planning/*.md` file edits; verification is grep-verifiable acceptance criteria in each PLAN.md
- **Per wave merge:** Plan 15-04 runs the bats subset (~5min) + `task rebuild` (~3min) as the Wave 1 close-out gate
- **Phase gate:** Full Phase 13 + Phase 14 bats subset GREEN + `task rebuild` SLO < 230s + `/gsd-audit-milestone v0.20` returns `passed`

### Wave 0 Gaps
- **None.** Phase 15 is a book-keeping phase per D-15-07. Nyquist gate satisfied vacuously: zero implementation = zero new falsifiers required.
- All falsifiers for the three-tier model live in Phase 13 + Phase 14 bats and re-run as-is in Plan 15-04.
- The **live regression rerun (Plan 15-04) IS the falsifier for Success Criterion 3** ("Three-tier model regression-verified live"). This is the close-out's regression-gate evidence — the bats subset + `task rebuild` SLO + `kubectl auth can-i '*' '*'` denials collectively prove the regression-gate claim is not vacuous.
- 15-VALIDATION.md frontmatter sets `wave_0_complete: true` with the rationale: "book-keeping phase; no Wave-0 scaffold required (D-15-07); falsifier surface = Phase 13/14 inherited bats re-run in Plan 15-04 + audit gate in Plan 15-05".

**Vacuous-Nyquist-with-live-regression-falsifier rationale (Phase 15-specific):**

Standard Nyquist gate: "no implementation lands without a pre-existing RED falsifier." Phase 15 has zero implementation; therefore zero new falsifiers are required (the vacuous truth). However, the close-out makes a non-vacuous claim — "Three-tier model regression-verified live" (SC-3) — which DOES need an active falsifier. The Phase 13 + Phase 14 bats subset (~207 @tests) + `task rebuild` SLO cold-run + `kubectl auth can-i '*' '*'` denials collectively constitute that active falsifier. Plan 15-04 is the wave that exercises this falsifier; its evidence log is committed under `.planning/phases/15-*/15-04-live-rerun-evidence.log`. The audit gate (Plan 15-05) reads Plan 15-04's evidence as the SC-3 satisfaction proof.

**Comparison to Phase 12:** v0.19 Phase 12 satisfied its Nyquist gate with `wave_0_complete: true` + the rationale "file content IS the verification surface" (no live cluster rerun). v0.20 Phase 15 EXTENDS this with `wave_0_complete: true` AND a live regression rerun (Plan 15-04) because v0.20's close-out scope explicitly requires regression-verifying the three-tier model live (per ROADMAP success criterion 3). Both are valid book-keeping-phase Nyquist patterns; v0.20 adds a stricter live-evidence gate on top of the file-content surface.

## `/gsd-complete-milestone` Precondition Checklist

**Workflow source:** `$HOME/.claude/get-shit-done/workflows/complete-milestone.md` (verified via Read).

`/gsd-complete-milestone v0.20` requires (before Phase 15 sets `ready_to_archive: true`):

1. **Pre-close artifact audit** (`gsd-sdk query audit-open`) — must show all artifact types clear OR user explicitly acknowledges open items as deferred (Phase 15 should aim for clear).
2. **All phases complete** (`gsd-sdk query roadmap.analyze`) — every phase shows `disk_status === 'complete'`; `progress_percent` = 100%. Plan 15-05 sets STATE.md to satisfy this.
3. **All v0.20 requirements checked off** in REQUIREMENTS.md (`grep -c '^- \[x\] \*\*(RBAC|SEED|DEMO|RUNBOOK|DELIVERY)-' .planning/REQUIREMENTS.md` returns 23) — Plan 15-01 satisfies.
4. **Audit run completed** (`/gsd-audit-milestone v0.20` returns `passed`) — Plan 15-05 satisfies.
5. **STATE.md `status: ready_to_archive`** — Plan 15-05 sets.

**`/gsd-complete-milestone v0.20` then performs (AFTER Phase 15 closes — NOT Phase 15's job):**
- Stats gathering (git log, LOC, timeline)
- Extract accomplishments from SUMMARY.md files
- Full PROJECT.md evolution review (move Active requirements to Validated; audit Out of Scope; update Key Decisions)
- Reorganize ROADMAP.md with milestone grouping (Backlog preservation; `<details>` collapsed block for v0.20)
- Archive ROADMAP.md → `.planning/milestones/v0.20-ROADMAP.md`
- Archive REQUIREMENTS.md → `.planning/milestones/v0.20-REQUIREMENTS.md` + `git rm REQUIREMENTS.md`
- Move phase directories to `.planning/milestones/v0.20-phases/` (optional; user-prompted)
- Append v0.20 entry to MILESTONES.md
- Git tag `v0.20`
- Final RETROSPECTIVE.md update + cross-milestone trends table append

**Critical: D-15-04 conflict resolution.** The `/gsd-complete-milestone` workflow Step `write_retrospective` would normally write the retrospective at milestone-completion time. v0.20 D-15-04 says Plan 15-05 appends the retrospective during Phase 15 close (BEFORE `/gsd-complete-milestone` runs). This pattern is consistent with v0.19 — the v0.19 retrospective section in `.planning/RETROSPECTIVE.md` was already present when `/gsd-complete-milestone v0.19` ran (per Plan 12-05 / 12-07 lineage). `/gsd-complete-milestone` is idempotent on retrospective append — if the v0.20 section already exists, it should NOT duplicate it. Planner verifies the workflow respects this.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `bats-core` | Plan 15-04 live regression rerun | ✓ (verified existing per `13-VALIDATION.md` Test Infrastructure) | 1.11.0 | — |
| `kubectl` | Plan 15-04 cluster probes + bats | ✓ (asdf-managed per ADR-005 + Phase 1 TOOLS-01..03) | k8s 1.34.x | — |
| `flux` | Plan 15-04 pre-demo checklist (verify hub-flux Kustomizations Ready) | ✓ (Phase 3 FLUX-01..05) | latest stable | — |
| `task` (Taskfile) | Plan 15-04 `task rebuild` + `task fix-dns-poc-capsule` + `task health-check` | ✓ (Phase 2-5 v0.18 baseline) | latest stable | — |
| `k3d` + `k3s` | Plan 15-04 live cluster operations | ✓ (Phase 2 CLU-01..05; spoke-capsule persistent) | `rancher/k3s:v1.34.6-k3s1` | — |
| `spoke-capsule` k3d cluster | Plan 15-04 bats live tests | ✓ (Phase 7 CAPCLU-01..04; persistent) | — | Plan 15-04 pre-demo checklist verifies via `kubectl --context k3d-spoke-capsule get nodes` |
| `hub-flux` Kustomizations RESUMED | Plan 15-04 bats live tests | ⚠️ Per Phase 14 14-03 evidence: `poc-capsule-spoke{,-rbac,-tenants}` are SUSPENDED at HEAD; Plan 15-04 must verify resumed state | — | Plan 15-04 invokes `flux resume kustomization poc-capsule-spoke{,-rbac,-tenants}` if SUSPENDED |
| `origin/main` HEAD ≥ `897a075` (Phase 14 close commit) | Plan 15-04 bats live tests (live cluster reconciles from origin/main; if origin lags, Phase 13 land state is missing) | ⚠️ Per Phase 14 14-03 evidence: live cluster lags at `49e264a2`; operator MUST `git push origin main` before Plan 15-04 invokes bats | — | Plan 15-04 pre-demo Step 6 verifies `git log origin/main --oneline -1` SHA ≥ `897a075` |
| `/gsd-audit-milestone v0.20` slash command | Plan 15-05 audit gate | ✓ (verified existing per `$HOME/.claude/get-shit-done/workflows/audit-milestone.md`) | — | — |
| `gsd-sdk query milestone.complete v0.20` | `/gsd-complete-milestone v0.20` (runs AFTER Phase 15) | ✓ (verified existing per `complete-milestone.md` workflow Step `archive_milestone`) | — | — |

**Missing dependencies with no fallback:** None.

**Missing dependencies with fallback (operator-action-required):**
- `origin/main` HEAD lag (Phase 14 14-03 evidence) — operator MUST `git push origin main` BEFORE Plan 15-04 bats run. If not, bats live tests will fail because live cluster reconciles from the lagged revision and lacks Phase 13 land state (docker.io allowlist, CRB SA subject, Tenant owners[] entries). Plan 15-04 pre-demo checklist Step 6 verifies this gating condition explicitly.
- hub-flux Kustomizations SUSPENDED state (Phase 14 destroy-poc side-effect) — Plan 15-04 resumes via `flux resume kustomization` if needed.

## Pitfalls / Landmines Specific to Milestone Close-out

### Pitfall 15-P1: Audit gate failing mid-plan (D-15-06 hard-block)

**What goes wrong:** Plan 15-05 invokes `/gsd-audit-milestone v0.20` and receives `gaps_found` or `tech_debt` with blocking items. If the orchestrator interprets this as a soft warning and proceeds to set `ready_to_archive`, the milestone ships partially-audited.

**Why it happens:** Audit failures can surface late-discovered gaps that Wave 1 didn't catch. The 3-source cross-reference matrix is strict — a REQ flagged `[x]` in REQUIREMENTS.md but missing from a phase SUMMARY.md `requirements-completed` frontmatter is `partial` not `satisfied`.

**How to avoid:** Plan 15-05 Task 1 (pre-flight check) mirrors Plan 12-07 Task 1 — exact-count grep semantics (`-eq` not `-ge`), all Wave 1 acceptance criteria verified BEFORE invoking the audit. Failure path: orchestrator inserts remediation plan (e.g., Plan 15-06) + re-runs audit; milestone NOT marked `ready_to_archive` until `passed`.

**Warning signs:** Audit returns `gaps_found` listing REQ-IDs Plan 15-01 already flipped; this indicates SUMMARY.md `requirements-completed` frontmatter inconsistency. Mitigation: Plan 15-01 SUMMARY explicitly populates `requirements-completed: [DEMO-01, DEMO-02, ...]` for the 11 flipped REQs.

### Pitfall 15-P2: STATE.md drift between plan execution and audit gate

**What goes wrong:** Plan 15-02 advances STATE.md frontmatter mid-phase (Wave 1); Plan 15-05 audit gate reads STATE.md and sees the mid-phase state (`completed_plans: 9` mid-Wave-1) rather than the desired pre-audit state. Audit may flag inconsistency.

**Why it happens:** STATE.md is mutable across Wave 1 plans; Plan 15-05 runs in Wave 2 after Wave 1 commits land.

**How to avoid:** Plan 15-02 sets the mid-phase frontmatter (`status: executing`, `completed_plans: 9 mid-Wave-1` or similar). Plan 15-05 Task 3 advances to the final state (`status: ready_to_archive`, `completed_plans: 14`, `percent: 100`). Mirrors Plan 12-02 → Plan 12-07 STATE.md trajectory.

**Warning signs:** STATE.md frontmatter says `status: completed` BEFORE Plan 15-05 runs (current state at Phase 15 open — verified). Plan 15-02 MUST revert this to `executing` at Wave 1 entry, otherwise the audit may report stale state.

### Pitfall 15-P3: ROADMAP Progress table desync from Phase Summary checkboxes

**What goes wrong:** Plan 15-03 updates Progress table line 151 (`Phase 14: 0/4 → 4/4 Complete 2026-05-19`) but forgets the Phase Summary line 72 (`[ ] Phase 14: ...` → `[x]`). Within-document contradiction; audit may flag.

**Why it happens:** ROADMAP.md has two parallel representations of phase status (Phase Summary `[ ]`/`[x]` checkboxes at lines 70-73 AND Progress table rows at lines 138-152). Both must stay in sync.

**How to avoid:** Plan 15-03 mirrors Plan 12-06 Task 1 — explicit grep verification that Phase Summary checkboxes match Progress table status. Acceptance criteria: `grep -cE "^- \[x\] \*\*Phase 1[3-5]:" .planning/ROADMAP.md` returns 2 (Phase 13 + Phase 14 at Plan 15-03 close; Plan 15-05 advances to 3 with Phase 15 self-close).

**Warning signs:** `grep "0/4 | Not started" .planning/ROADMAP.md` returns ≥ 1 after Plan 15-03 close = Progress table not refreshed.

### Pitfall 15-P4: Spec-deviation amend introducing line-number shifts that break later grep-based citation patterns

**What goes wrong:** Plan 15-01 inline-amends RBAC-01 / SEED-03 / DELIVERY-01 / RUNBOOK-05 spec text. The amendments may shift line numbers downstream, breaking grep-based citation patterns in PLAN.md acceptance criteria that reference specific REQUIREMENTS.md line numbers.

**Why it happens:** REQUIREMENTS.md is sourced into multiple plans' acceptance criteria via `grep -c "^- \[x\] \*\*<REQ>\*\*" .planning/REQUIREMENTS.md` patterns; these patterns are LINE-NUMBER-INDEPENDENT (use `^- \[x\]` literal-line-start anchor) so they're robust to line-number shifts. However, any acceptance criterion that uses `sed -n '<N>p'` or `awk 'NR==<N>'` patterns IS line-number-dependent and would break.

**How to avoid:** Plan 15-01 amendments use the Edit tool with unique-old_string matching (verbatim REQ text including ID) — same approach as Plan 12-01 Task 2 (TEN-01 amendment). All downstream acceptance criteria in Plan 15-02..15-05 use `grep -c '<literal>'` patterns (line-number-independent), NOT `sed`/`awk` line-number-based patterns. Verified against Phase 12 plan files — all acceptance criteria use grep with literal anchors.

**Warning signs:** Any acceptance criterion in PLAN 15-02..15-05 that references `REQUIREMENTS.md line N` by explicit line number = potential breakage. Planner audits PLAN.md drafts for this pattern.

### Pitfall 15-P5: RUNBOOK-04 UAT carry-forward from Plan 14-03 not retired cleanly

**What goes wrong:** Phase 14 `14-VERIFICATION.md` carries RUNBOOK-04 as `passed_with_overrides` with the carry-forward deferred to Phase 15 SC-3 + SC-5. If Plan 15-04 live regression rerun is GREEN but Plan 15-05 audit gate flags RUNBOOK-04 as `partial` (because no separate human cold-read evidence), the audit may not return `passed`.

**Why it happens:** Phase 14 explicitly designated the auto-attested-with-carry-forward UAT disposition as a Plan 15 retirement task. The audit's 3-source matrix may interpret RUNBOOK-04's `passed_with_overrides` in Phase 14 SUMMARY frontmatter as `partial` (because SUMMARY frontmatter `requirements-completed` lists RUNBOOK-04 but VERIFICATION.md is `passed_with_overrides` not `passed`).

**How to avoid:**
1. Plan 15-04 live regression rerun GREEN provides the regression-gate evidence for SC-3 (auto-satisfies RUNBOOK-04's automated checks).
2. Plan 15-05 audit gate failure-handling explicitly accepts RUNBOOK-04 carry-forward if all OTHER REQs are `satisfied` (Plan 12-07 Task 2 Contingency 1 precedent).
3. OPTIONAL: milestone-owner performs a human cold-read of `docs/poc-capsule-demo.md` against the live cluster (now that `origin/main` is pushed and Phase 13 land state is reconciled) — captures duration in `15-VERIFICATION.md` human-verification section. This retires the carry-forward fully.

**Warning signs:** Audit returns `tech_debt` with RUNBOOK-04 as the sole item; orchestrator hits Contingency 1 decision point.

### Pitfall 15-P6: SUMMARY.md `requirements-completed` frontmatter inconsistency

**What goes wrong:** Plan 15-01 flips 11 REQs to `[x]` in REQUIREMENTS.md, but does NOT populate `requirements-completed: [DEMO-01, DEMO-02, ...]` in Plan 15-01 SUMMARY.md frontmatter. Audit 3-source matrix flags inconsistency (REQUIREMENTS.md `[x]` + SUMMARY.md frontmatter missing = `partial`).

**Why it happens:** v0.18 RETROSPECTIVE flagged this pattern: "SUMMARY.md `requirements-completed` frontmatter inconsistent — 3 Phase 6 plans (06-02, 06-05, 06-06) shipped without populating `requirements-completed`. Verifier confirmed the requirements via codebase evidence, but the frontmatter cosmetic gap propagated into the audit and milestone-archive flows."

**How to avoid:** Plan 15-01 SUMMARY.md MUST populate `requirements-completed: [DEMO-01, DEMO-02, DEMO-03, DEMO-04, DEMO-05, DEMO-06, RUNBOOK-01, RUNBOOK-02, RUNBOOK-03, RUNBOOK-04, RUNBOOK-05]` (all 11 flipped REQ-IDs) — mirrors Plan 12-01 SUMMARY frontmatter `requirements-completed` block. Planner verifies at SUMMARY-template-fill time.

**Warning signs:** Plan 15-01 SUMMARY.md has empty `requirements-completed: []` or omits the field entirely.

### Pitfall 15-P7: Phase 14 destructive `task destroy-poc` test left tenants in destroyed state

**What goes wrong:** Phase 14 14-02 evidence log shows `task destroy-poc` was invoked mid-suite (D-11-10 destructive test @ line 685). After Plan 14-02 close, alpha + bravo tenants were destroyed; Plan 14-03 evidence log shows recovery via `flux resume kustomization`. If Plan 15-04 inherits the destroyed state, bats live tests fail at preflight.

**Why it happens:** Live cluster state persists across plan boundaries; Phase 14 destroy-poc was the last live-state-mutating action before Phase 15.

**How to avoid:** Plan 15-04 pre-demo checklist Step 2 (`flux resume kustomization poc-capsule-spoke{,-rbac,-tenants}` if SUSPENDED) + Step 3 (`kubectl get tenants` returns alpha + bravo Active). If tenants missing, resume Kustomizations in dependency order (tenants → spoke → rbac) per Phase 14 14-03 evidence log lines 34-77.

**Warning signs:** `kubectl --context k3d-spoke-capsule get tenants` returns `No resources found` at Plan 15-04 entry = destroyed state inherited.

### Pitfall 15-P8: `origin/main` push gap blocking Plan 15-04 (Phase 14 14-03 evidence)

**What goes wrong:** Phase 14 14-03 evidence log identified: "Live cluster reconciles from `origin/main@49e264a2` while Phase 13 commits (6e91216..897a0755) are local-only. Live Tenant CRs + capsule-platform-owner CRB + tenant owners[] lack Phase 13 land state." Plan 15-04 bats run against the lagged cluster will RED across multiple categories.

**Why it happens:** Auto-mode never pushes to `origin/main`; this is operator-owned. Auto-mode work is committed to local main; live cluster reconciles from origin/main.

**How to avoid:** Plan 15-04 pre-demo checklist Step 6: verify `git log origin/main --oneline -1` SHA ≥ `897a075` (Phase 14 close) OR ≥ Plan 14-03 close commit OR ≥ Phase 15 entry commit. If NOT, HALT and surface "Operator action required: `git push origin main`" inline in Plan 15-04 SUMMARY. Plan 15-04 does NOT push (per `Git Safety Protocol` — only push when user explicitly requests).

**Warning signs:** `git log origin/main --oneline -1` shows `49e264a2` or earlier = pre-Phase-13 state still in origin; live cluster lacks Phase 13 land state.

### Pitfall 15-P9: Velocity counters in STATE.md (lines 36-42) easily mis-incremented

**What goes wrong:** Plan 15-02 advances `Total plans completed (v0.20): X` (currently absent). Off-by-one or premature increment (counting Phase 15 plans before they land) leads to STATE.md inconsistency Plan 15-05 audit gate flags.

**Why it happens:** Multiple counters across STATE.md (frontmatter `progress.completed_plans`, body Velocity block, Performance Metrics By-Phase table) can drift if not updated consistently. Phase 12 had the SAME pitfall — Plan 12-02 T-2 explicitly called out `total_plans: 27 → 34` off-by-one risk.

**How to avoid:** Plan 15-02 derives counters from `ls .planning/phases/{13,14}-*/[01]*-PLAN.md | wc -l` (= 9 at Plan 15-02 entry — Phase 15 plans not yet committed); Plan 15-05 self-close advances to 14 (9 + 5 Phase 15 plans). Use `gsd-sdk query phases.list` for authoritative count.

**Warning signs:** Plan 15-02 SUMMARY's verified count differs from `ls`-based count.

### Pitfall 15-P10: Retrospective duplicate-append at `/gsd-complete-milestone v0.20`

**What goes wrong:** Plan 15-05 appends v0.20 retrospective section per D-15-04. `/gsd-complete-milestone v0.20` then runs Step `write_retrospective` which may re-append the section, creating a duplicate.

**Why it happens:** `/gsd-complete-milestone` workflow Step `write_retrospective` reads `RETROSPECTIVE.md` and conditionally appends. Idempotency depends on whether the workflow checks for existing v0.20 section header.

**How to avoid:** Plan 15-05 appends v0.20 section with the literal heading `## Milestone: v0.20 — Capsule POC Demo & RBAC Polish` (matching the v0.18 + v0.19 cadence). When `/gsd-complete-milestone v0.20` runs Step `write_retrospective`, it should detect the existing section header and skip the append. If not, planner verifies workflow + opens an upstream bug or uses the workflow's manual override.

**Warning signs:** `grep -c "^## Milestone: v0.20" .planning/RETROSPECTIVE.md` returns 2 after `/gsd-complete-milestone v0.20` = duplicate appended.

### Pitfall 15-P11: PROJECT.md "Carry-forward parking lot" section edit conflict

**What goes wrong:** Plan 15-05 reconciles parking lot inline; if another concurrent edit (e.g., from `/gsd-complete-milestone v0.20`'s full PROJECT.md evolution review) touches the same section, merge conflict.

**Why it happens:** PROJECT.md is the canonical home for the parking lot AND is fully reviewed by `/gsd-complete-milestone` (Step `evolve_project_full_review`).

**How to avoid:** Plan 15-05 makes its parking lot edits BEFORE `/gsd-complete-milestone v0.20` runs (Plan 15-05 is in Wave 2; `/gsd-complete-milestone v0.20` runs AFTER Phase 15 closes per workflow). Linear execution; no concurrent edit risk.

**Warning signs:** PROJECT.md merge conflict during `/gsd-complete-milestone v0.20` Step `evolve_project_full_review` = Plan 15-05 didn't run first OR `/gsd-complete-milestone` is being invoked before Phase 15 close.

## Code Examples

### Example 1: Plan 15-01 REQUIREMENTS.md flip pattern (mirrors Plan 12-01 Task 1)

```bash
# Verbatim per Plan 12-01 Task 1 acceptance pattern
test $(grep -cE "^- \[x\] \*\*(RBAC|SEED|DEMO|RUNBOOK|DELIVERY)-" .planning/REQUIREMENTS.md) -eq 23 && \
test $(grep -cE "^- \[ \] \*\*(RBAC|SEED|DEMO|RUNBOOK|DELIVERY)-" .planning/REQUIREMENTS.md) -eq 0
```

Edit tool call shape (per Plan 12-01 Task 1, repeated 11 times):
```
Edit:
  old_string: "- [ ] **DEMO-01** — Platform-owner kubeconfig..."
  new_string: "- [x] **DEMO-01** — Platform-owner kubeconfig..."
```

### Example 2: Plan 15-01 spec-deviation amend pattern (mirrors Plan 12-01 Task 2 TEN-01)

```
Edit:
  old_string: "- [ ] **RBAC-01** — A `tenant-workload-editor` ClusterRole exists with scope narrower than upstream k8s `edit`: NO Secret create / edit, NO RoleBinding, NO ResourceQuota, NO LimitRange. Final Secrets policy (read-only / no-access / upstream-edit-equivalent) resolved in discuss-phase per OQ-2."
  new_string: "- [x] **RBAC-01** — A `tenant-workload-editor` ClusterRole exists with scope narrower than upstream k8s `edit`: NO Secret create / edit, NO RoleBinding, NO ResourceQuota, NO LimitRange. Final Secrets policy resolved as **read-only** per Phase 13 D-13-01 (Secrets `get`/`list`/`watch` only; explicit deny on `create`/`update`/`patch`/`delete`)."
```

### Example 3: Plan 15-04 bats subset invocation + evidence log header

```bash
#!/usr/bin/env bash
# 15-04 — live regression rerun
set -euo pipefail

EVIDENCE=.planning/phases/15-v0-20-milestone-close-out-retrospective/15-04-live-rerun-evidence.log

{
  echo "=== Plan 15-04 Live Regression Rerun Evidence Log ==="
  echo "Start UTC: $(date -u +%FT%TZ)"
  echo "Operator: $(git config user.email)"
  echo "Branch: $(git branch --show-current)"
  echo "Cluster context: k3d-spoke-capsule"
  echo "HEAD: $(git log --oneline -1)"
  echo "origin/main: $(git log origin/main --oneline -1)"
  echo
} > "$EVIDENCE"

# Pre-demo checklist
echo "--- Step 1: cluster reachable ---" | tee -a "$EVIDENCE"
kubectl --context k3d-spoke-capsule get nodes 2>&1 | tee -a "$EVIDENCE"

# (Steps 2-6 per §Plan 15-04 above)

# Kubeconfig mint
bash scripts/poc/capsule/issue-platform-owner-kubeconfig.sh --duration 2h --write-to /tmp/karyon-tenants/platform-owner.kubeconfig 2>&1 | tee -a "$EVIDENCE"
export PO_KC=/tmp/karyon-tenants/platform-owner.kubeconfig
bash scripts/poc/capsule/issue-tenant-kubeconfig.sh alpha-owner alpha --write-to /tmp/karyon-tenants/tenant-alpha.kubeconfig 2>&1 | tee -a "$EVIDENCE"
export TO_ALPHA_KC=/tmp/karyon-tenants/tenant-alpha.kubeconfig

# Phase 13 + Phase 14 bats subset
echo "--- Phase 13 + Phase 14 bats subset ---" | tee -a "$EVIDENCE"
bats \
  tests/bats/rbac-*.bats \
  tests/bats/seed-*.bats \
  tests/bats/delivery-{01,02,03,04}-*.bats \
  tests/bats/demo-*.bats \
  tests/bats/runbook-*.bats \
  --duration 2>&1 | tee -a "$EVIDENCE"

# Cluster-admin denial assertions
echo "--- Cluster-admin denial assertions ---" | tee -a "$EVIDENCE"
kubectl --kubeconfig=$PO_KC auth can-i '*' '*' 2>&1 | tee -a "$EVIDENCE"  # expected: no
kubectl --kubeconfig=$TO_ALPHA_KC auth can-i '*' '*' 2>&1 | tee -a "$EVIDENCE"  # expected: no

# task rebuild SLO cold-run
echo "--- task rebuild SLO cold-run ---" | tee -a "$EVIDENCE"
{ time KARYON_REBUILD_APPROVED=1 task rebuild; } 2>&1 | tee -a "$EVIDENCE"
task health-check 2>&1 | tee -a "$EVIDENCE"
echo "task health-check exit: $?" | tee -a "$EVIDENCE"

echo "End UTC: $(date -u +%FT%TZ)" | tee -a "$EVIDENCE"
```

### Example 4: Plan 15-05 audit gate sequence (mirrors Plan 12-07)

```bash
# Task 1: Pre-flight check
test $(grep -cE "^- \[x\] \*\*(RBAC|SEED|DEMO|RUNBOOK|DELIVERY)-" .planning/REQUIREMENTS.md) -eq 23 && \
test $(grep -cE "^- \[ \] \*\*(RBAC|SEED|DEMO|RUNBOOK|DELIVERY)-" .planning/REQUIREMENTS.md) -eq 0 && \
test $(grep -cE "^- \[x\] \*\*Phase 14:" .planning/ROADMAP.md) -eq 1 && \
test -f .planning/phases/15-v0-20-milestone-close-out-retrospective/15-04-live-rerun-evidence.log && \
grep -q "RED count: 0" .planning/phases/15-v0-20-milestone-close-out-retrospective/15-04-live-rerun-evidence.log

# Task 2: Invoke audit
/gsd-audit-milestone v0.20

# Task 3: Read result
head -20 .planning/v0.20-MILESTONE-AUDIT.md
# Expected: status: passed

# Task 4: Phase 15 self-close edits
# (per §Plan 15-05 above — ROADMAP Phase 15 [x], STATE ready_to_archive, 15-VALIDATION.md final, REQUIREMENTS.md Traceability footer)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| v0.18 close-out: ad-hoc REQ flip + manual audit | v0.19 Phase 12: dedicated 7-plan close-out reconciliation phase | v0.19 close 2026-05-13 | Phase 12 became the canonical book-keeping template |
| v0.19 Phase 12: 7 plans (incl. VERIFICATION supersedure + todo-move) | v0.20 Phase 15: 5 plans (omits supersedure + todo-move; adds live regression rerun) | v0.20 milestone open 2026-05-19 | Compressed by 2 plans because Phase 13/14 had no VERIFICATION supersedure work; live regression rerun added for v0.20-specific three-tier-model regression-gate evidence |
| RETROSPECTIVE-v[X].md standalone file | `.planning/RETROSPECTIVE.md` living doc with v0.18 + v0.19 sections | v0.18 close 2026-04-29 | Cross-milestone trends visible in one scroll; future readers compare v0.18 → v0.19 → v0.20 lessons in one place |
| Manual STATE.md updates per plan | `gsd-sdk query phase.complete` + manual frontmatter sync | v0.18/v0.19 progression | SDK partial automation; manual sync still required for `last_activity` + `status` |
| Audit-passed = manual disposition judgment | `/gsd-audit-milestone v0.X` with 3-source cross-reference + FAIL gate | v0.19 close 2026-05-13 | Deterministic audit; orphan detection + Nyquist discovery |

**Deprecated / outdated:**
- v0.18-style ad-hoc close-out with no dedicated phase: deprecated; Phase 12 (v0.19) + Phase 15 (v0.20) establish the canonical pattern.
- Splitting retrospective into standalone files: deprecated per D-15-04; living-doc pattern is canonical.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Phase 15 plan count = 5 per D-15-01 | Plan Mapping Table; STATE.md Performance Metrics | If planner chooses 4 or 6, Plan 15-02 STATE.md frontmatter `total_plans: 14` needs adjustment; minor |
| A2 | `/gsd-complete-milestone v0.20` Step `write_retrospective` is idempotent on existing v0.20 section | Pitfall 15-P10 | If non-idempotent, duplicate section appended; cosmetic but visible to next-milestone-open reader. Mitigation: Plan 15-05 SUMMARY notes the section was appended; orchestrator advises operator to skip Step `write_retrospective` |
| A3 | Audit's Future Requirements handling logic excludes ADDON-01/02 from `unsatisfied` scoring | Audit Gate Semantics | Plan 12-07 Task 2 RESEARCH.md A1 documented the same uncertainty for v0.19. If audit DOES score ADDON-01/02 as `unsatisfied`, milestone hits Contingency 1 decision point. v0.20 has no ADDON entries; lower risk for v0.20 |

**Note:** All other claims are verified against live `.planning/` artifacts, Phase 12 PLAN files (`12-{01..07}-PLAN.md`), Phase 13/14 VERIFICATION + VALIDATION files, Phase 14 evidence logs, and `/gsd-audit-milestone` + `/gsd-complete-milestone` workflow source.

## Open Questions

None — CONTEXT.md auto-mode resolved all 7 Phase 15 decision points (D-15-01..07); RESEARCH need only fold these into the mechanical reconciliation surfaces.

## Sources

### Primary (HIGH confidence — verified via Read of working-tree files)

- `.planning/phases/15-v0-20-milestone-close-out-retrospective/15-CONTEXT.md` — D-15-01..07 locked decisions
- `.planning/REQUIREMENTS.md` — 23 v0.20 mandatory REQs; current `[ ]` vs `[x]` state; exact line numbers
- `.planning/STATE.md` — current frontmatter + body state at Phase 15 open
- `.planning/ROADMAP.md` — Phase Summary + Progress table; Phase 15 success criteria 1-5
- `.planning/PROJECT.md` — Current Milestone section; Carry-forward parking lot (lines 87-99)
- `.planning/RETROSPECTIVE.md` — v0.18 + v0.19 sections (cadence template for D-15-04)
- `.planning/v0.20-MILESTONE-BRIEFING.md` — OQ-1..5 recommended defaults
- `.planning/phases/13-rbac-narrowing-globaltenantresource-seed-delivery-mechanism/13-CONTEXT.md` — D-13-01..03 OQ-2/3/4 resolutions
- `.planning/phases/13-rbac-narrowing-globaltenantresource-seed-delivery-mechanism/13-VERIFICATION.md` — Phase 13 verifier output; RBAC/SEED/DELIVERY 12 REQs GREEN evidence
- `.planning/phases/13-rbac-narrowing-globaltenantresource-seed-delivery-mechanism/13-VALIDATION.md` — `status: final`; bats falsifier map
- `.planning/phases/13-rbac-narrowing-globaltenantresource-seed-delivery-mechanism/deferred-items.md` — pre-existing inheritance bats failures (NOT v0.20 carry-forward parking lot additions)
- `.planning/phases/14-two-perspective-demo-verification-6-act-runbook-tls-noise-re/14-CONTEXT.md` — D-14-01..10; OQ-1 + OQ-5 resolutions
- `.planning/phases/14-two-perspective-demo-verification-6-act-runbook-tls-noise-re/14-VERIFICATION.md` — Phase 14 verifier output; DEMO/RUNBOOK 11 REQs GREEN; RUNBOOK-04 carry-forward override
- `.planning/phases/14-two-perspective-demo-verification-6-act-runbook-tls-noise-re/14-VALIDATION.md` — `status: final`; UAT auto-attestation row
- `.planning/phases/14-two-perspective-demo-verification-6-act-runbook-tls-noise-re/14-02-full-suite-evidence.log` — full bats suite evidence shape (Plan 15-04 template)
- `.planning/phases/14-two-perspective-demo-verification-6-act-runbook-tls-noise-re/14-03-uat-cold-run-evidence.log` — cold-run evidence shape + origin/main lag discovery (Pitfall 15-P8 source)
- `.planning/milestones/v0.19-phases/12-v0-19-close-out-reconciliation/12-{01,02,03,04,05,06,07}-PLAN.md` — Plan 12 direct templates for Plans 15-{01,02,03,05}
- `.planning/milestones/v0.19-phases/12-v0-19-close-out-reconciliation/12-VALIDATION.md` — book-keeping-phase Nyquist ledger idiom
- `.planning/milestones/v0.19-phases/12-v0-19-close-out-reconciliation/12-VERIFICATION.md` — book-keeping-phase verifier output shape
- `$HOME/.claude/get-shit-done/workflows/audit-milestone.md` — `/gsd-audit-milestone` workflow source
- `$HOME/.claude/get-shit-done/workflows/complete-milestone.md` — `/gsd-complete-milestone` workflow source
- `.planning/config.json` — `workflow.nyquist_validation: true` (Validation Architecture section is REQUIRED)

### Secondary (MEDIUM confidence — verified via Bash grep / ls / git)

- `tests/bats/` directory listing — Phase 13 + Phase 14 bats file inventory (Plan 15-04 glob source)
- `.planning/phases/{13,14}-*/[01]*-PLAN.md` count = 9 (STATE.md `total_plans` derivation)

### Tertiary (LOW confidence — none)

All claims verified against primary or secondary sources. No unverified claims in this research.

## Metadata

**Confidence breakdown:**
- Standard stack (bats-core, kubectl, flux, task): HIGH — pre-existing, used throughout v0.18/v0.19/v0.20; no version drift risk
- Architecture (book-keeping phase + Phase 12 template + live regression rerun): HIGH — direct template inheritance with documented compression
- Pitfalls (P1-P11): HIGH — most derived from Plan 12-07 Task 1 grep gates + v0.18/v0.19 RETROSPECTIVE pitfalls + Phase 14 14-03 evidence log discoveries

**Research date:** 2026-05-20
**Valid until:** 2026-05-27 (7 days — fast-moving close-out work; STATE.md state changes daily during execution)

---

*Phase: 15-v0-20-milestone-close-out-retrospective*
*Research gathered: 2026-05-20*
*All claims verified against working-tree `.planning/` artifacts + Phase 12 plan files + GSD workflow source*
