# Phase 14: Two-Perspective Demo Verification + 6-Act Runbook + TLS-Noise Resolution - Context

**Gathered:** 2026-05-19
**Status:** Ready for planning
**Mode:** `--auto` (recommended defaults auto-selected; see DISCUSSION-LOG.md)

<domain>
## Phase Boundary

This phase **verifies and documents** the three-tier permission model that Phase 13 built. It produces:

1. **Live demo verification** — Two distinct kubeconfigs (platform-owner + tenant-owner) demonstrably enforce the Tier 2 / Tier 3 boundary end-to-end against the live `spoke-capsule` cluster (DEMO-01..06 GREEN against real cluster, not just unit-level bats).
2. **`docs/poc-capsule-demo.md`** — A polished 6-act walkthrough executable cold in ≤ 15 minutes by a teammate (RUNBOOK-01..05).
3. **OQ-1 + OQ-5 resolution** — TLS noise treatment locked (`document-only`); new-tenant marquee name locked (`charlie`); provision-style locked (`live`).

**Explicitly NOT in scope (these belong to other phases):**

- Building new RBAC artifacts, ClusterRoles, `GlobalTenantResource`, or delivery infrastructure — all owned by Phase 13 and already live.
- Adopting Capsule into the production topology — graduation = DEFER per ADR-008.
- Closing the v0.20 milestone, retrospective, or REQUIREMENTS.md checkbox flips — Phase 15.
- Fixing the `tls: bad certificate` controller chatter at the cert-rotation layer — explicitly out-of-scope per OQ-1 resolution below.

</domain>

<decisions>
## Implementation Decisions

### OQ-1 — TLS Noise Treatment (RUNBOOK-03)

- **D-14-01:** **Document-only.** The capsule-controller `tls: bad certificate` 1Hz chatter is NOT fixed in this phase. It is called out explicitly in `docs/poc-capsule-demo.md` as a known-noise note with a 2-paragraph explanation: (a) **what** it is — a self-signed-cert handshake re-attempt loop visible in controller logs that does NOT affect tenant boundary enforcement or `GlobalTenantResource` propagation; (b) **why** document-only — POC scope (per ADR-008 = DEFER), fixable in a production EKS cut via cert-manager wiring or proper CA distribution but not load-bearing for the three-tier demo.
  - **Why:** Matches the milestone briefing's "recommended default = document-only" framing. The chatter is cosmetic, not functional. Fixing it pulls in cert-manager / CA-distribution work that the lean v0.20 milestone is explicitly scope-guarded against.
  - **How to apply:** Runbook gets a "Known noise" section after act 6 (NOT inline in any act — keeps the live walkthrough flowing). Cross-links ADR-008. No code changes; no script changes; no Helm value changes.

### OQ-5 — New-Tenant Marquee Name + Provision Style (RUNBOOK-05, RUNBOOK-01 act 3)

- **D-14-02:** **Marquee tenant name = `charlie`.**
  - **Why:** Continues the alpha → bravo → charlie phonetic alphabet pattern already established for `alpha` + `bravo` tenants. Already cited as an example in `scripts/poc/capsule/new-tenant.sh` head-comment usage block ("Examples: ... charlie ..."). Single-word, regex-clean, memorable for the demo audience.
  - **How to apply:** `charlie` appears **verbatim** in (a) `docs/poc-capsule-demo.md` act 3 + act 6, (b) any new helper script under `scripts/poc/capsule/` if planner lands one, (c) any new bats fixture for DEMO-01..06 (kept distinct from Phase 13's `phase13-fresh` throwaway). Single canonical name across runbook + scripts + bats.

- **D-14-03:** **Provision style = live (use `new-tenant.sh charlie` cold).**
  - **Why:** RUNBOOK-01 act 3 says "provision a new tenant **live**". The audience-facing moment is the platform-owner CREATE → Capsule materialize → SEED-02 ≤ 60s observation chain — that lives or dies on real-time materialization. Pre-staged delete+recreate dance hides exactly what's interesting. Phase 13's `new-tenant.sh` already exists, works, and is the canonical provisioning path.
  - **How to apply:** Act 3 invokes `bash scripts/poc/capsule/new-tenant.sh charlie` cold (no pre-staging beyond ensuring `charlie` is NOT already present — pre-demo checklist covers a `kubectl delete tenant charlie --ignore-not-found` reset step for idempotent reruns). Act 4 immediately observes SEED-02 propagation into `tenant-charlie` / `charlie-app1` (whichever namespace shape Capsule materializes — verify against Phase 13 SEED-02 fixture).
  - **Reset / idempotency:** Pre-demo checklist includes `kubectl --kubeconfig=$po_kc delete tenant charlie --ignore-not-found` so the runbook is safely re-runnable.

### Runbook Structure (RUNBOOK-01..05)

- **D-14-04:** **Single document** at `docs/poc-capsule-demo.md`, NOT split across multiple files.
  - **Why:** RUNBOOK-01 specifies a single 6-act walkthrough; UAT (RUNBOOK-04) is a single ≤ 15-minute cold read; splitting fragments the reader's context. Cross-links to `docs/poc-capsule.md` (operator's runbook) + `docs/capsule-on-eks.md` (EKS translation) + ADR-008 (DEFER framing) live as forward-pointers, not embedded content.
  - **How to apply:** New file `docs/poc-capsule-demo.md` with frontmatter (`status: Active`, `audience: demo presenter + audience`, `purpose: 6-act capsule POC demo walkthrough`, `scope: Phase 14 verification + demo runbook`). 6 ordered `## Act N — ...` sections + appendix-style "Pre-demo checklist", "Known noise", and "Forward pointers" sections.

- **D-14-05:** **Pre-demo checklist is executable, not narrative** (RUNBOOK-02).
  - **Why:** RUNBOOK-02 mandates "executable, not narrative". Operators copy-paste and verify.
  - **How to apply:** Each checklist item is a `kubectl` / `bash` snippet with expected output (e.g., `kubectl --context k3d-spoke-capsule get nodes` → `Ready`). Checklist covers: (a) cluster reachable, (b) `task fix-dns-poc-capsule` if needed, (c) both kubeconfigs minted + paths exported as env vars (`PO_KC`, `TO_ALPHA_KC`, `TO_BRAVO_KC`), (d) `kubectl delete tenant charlie --ignore-not-found` reset, (e) `task -l | grep poc` sanity check.

- **D-14-06:** **Each act has a concrete kubectl/task step + expected output block.**
  - **Why:** RUNBOOK-01 + RUNBOOK-04 require executable acts with predictable output for the ≤ 15-minute cold read.
  - **How to apply:** Every act ends with a `### Expected output` fenced block showing the canonical successful response. Forbidden-action expected outputs include the `Error from server (Forbidden): ...` line so the audience can read the actual rejection.

### DEMO-06 Forbidden-Action Showcase (Tier 2 Ceiling)

- **D-14-07:** **Runbook act 2 surfaces ONE primary Forbidden action live; bats verifies all three.**
  - **Why:** DEMO-06 requires the platform-owner be rejected on cluster-admin actions; RUNBOOK-01 act 2 says "at least one Forbidden cluster-admin action". Running all three live bloats the walkthrough; one well-chosen action is more visceral. Bats coverage on all three (`kubectl get nodes -o yaml`, `kubectl get csr`, `kubectl create clusterrolebinding`) preserves the falsifiable contract.
  - **How to apply:** Act 2 features `kubectl create clusterrolebinding po-cluster-admin-attempt --clusterrole=cluster-admin --user=platform-owner` → `Forbidden`. Bats (likely an extension of `rbac-09-live-platform-owner-kubeconfig.bats` or a new `rbac-11-live-platform-owner-cluster-admin-denials.bats`) asserts the full 3-action denial matrix.

### Two-Perspective Verification Strategy (DEMO-01..05)

- **D-14-08:** **Live bats over both kubeconfigs** — Phase 14 lands new live bats (or extends Phase 13's `rbac-08/09/10` + `negative-rbac-01..04`) that drive `kubectl` through both `$PO_KC` and `$TO_{ALPHA,BRAVO}_KC` to assert the DEMO-01..05 contracts. The runbook narrative + the bats falsifiers are **parallel artifacts** — runbook for humans, bats for CI/regression. Bats names follow the existing `tests/bats/` convention: `demo-01-live-platform-owner-tenants-list.bats`, `demo-02-live-tenant-owner-scoped-list.bats`, etc. (planner picks final names + count; 4–6 new bats files anticipated).
  - **Why:** RBAC-08/09/10 already cover the live RBAC grant matrix from Phase 13. DEMO-01..05 layer the **two-kubeconfig** assertion (platform-owner vs tenant-owner, both alpha + bravo). New bats keep the falsifiable contract; runbook stays a human-readable document.
  - **How to apply:** Planner decides whether to extend existing bats files or land new `demo-*.bats` files; preference is **new files** keyed `demo-N-live-*.bats` for traceability against DEMO-01..06 REQs.

### Capsule-Proxy Routing for Tenant-Owner Demo (DEMO-02 + DEMO-05)

- **D-14-09:** **Tenant-owner kubeconfigs route through capsule-proxy NodePort 30443** (inherited from v0.19 Phase 10).
  - **Why:** DEMO-02 / DEMO-05 / RUNBOOK-01 act 5 require the capsule-proxy LIST-filter mechanic to be the audience-visible mechanism. `issue-tenant-kubeconfig.sh` already mints kubeconfigs pointing at `https://<host>:30443`. No new wiring required.
  - **How to apply:** Pre-demo checklist mints `TO_ALPHA_KC` + `TO_BRAVO_KC` via `bash scripts/poc/capsule/issue-tenant-kubeconfig.sh alpha-owner alpha` (+ bravo equivalent). Runbook act 5 explicitly notes the `:30443` capsule-proxy hop as the LIST-filter enforcement point.

### UAT Verification (RUNBOOK-04)

- **D-14-10:** **Cold-read UAT against live `spoke-capsule` cluster.**
  - **Why:** RUNBOOK-04 mandates ≤ 15-minute cold read by a human with no prior context. This is the milestone-owner UAT gate.
  - **How to apply:** Final plan in Phase 14 (verifier-equivalent) walks the runbook cold against a freshly `task fix-dns-poc-capsule`-d cluster, stopwatches the duration, captures any rough edges, writes results to `14-VALIDATION.md` (mirrors Phase 13's VALIDATION.md pattern). If > 15 min: tighten the runbook prose / pre-mint scripts / collapse expository sections until ≤ 15 min. Pass criterion = single-pass cold-run under 15 min.

### Claude's Discretion

- **Exact split of plans within Phase 14.** Planner picks the wave decomposition. Anticipated shape (planner may adjust): (a) Wave 0 — RED bats scaffold for DEMO-01..06 + extended `rbac-11-live-platform-owner-cluster-admin-denials.bats`; (b) Wave 1 — `docs/poc-capsule-demo.md` 6-act draft + pre-demo checklist; (c) Wave 2 — TLS-noise documentation (RUNBOOK-03) + ADR-008 + EKS-doc cross-links; (d) Wave 3 — UAT cold-read against live cluster + `14-VALIDATION.md`. 3–5 plans is the target.
- **Whether DEMO bats files extend existing rbac/negative-rbac files or land as new `demo-*.bats`.** Preference is new files (D-14-08); planner may consolidate if there's heavy overlap.
- **Exact bats fixture for SEED-02 fresh-tenant assertion on `charlie`.** Phase 13 already proved the SEED-02 ≤ 60s contract on `phase13-fresh`; Phase 14 may add `demo-04-live-charlie-seed-propagation.bats` or simply re-cite Phase 13's `seed-03-live-fresh-tenant.bats` and exercise via `new-tenant.sh charlie`. Planner picks.
- **TLS noise documentation depth.** D-14-01 specifies 2 paragraphs minimum; planner may expand if helpful for reader comprehension (cap at ~half a page so it stays "known noise note", not "engineering deep-dive").
- **Whether to add a `task` Taskfile wrapper for the demo flow** (e.g., `task demo-capsule`). Recommendation: **no** — keeps P31 isolation strict (no new `spoke-capsule` mentions in v0.18 default-path scripts per DELIVERY-02). All commands stay raw `bash scripts/poc/capsule/...` or `kubectl --kubeconfig=...` invocations in the runbook itself. Planner may revisit if UAT identifies friction.

### Folded Todos

None — no pending todos matched Phase 14 scope (gsd-sdk query returned 0 matches).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase Inputs (v0.20 milestone scoping)

- `.planning/ROADMAP.md` §"Phase 14" — phase goal, success criteria 1–5, REQ list (DEMO-01..06, RUNBOOK-01..05), depends-on (Phase 13).
- `.planning/REQUIREMENTS.md` §"DEMO — Capsule-Proxy Two-Perspective Demo (Demo R3)" + §"RUNBOOK — Polished Demo Runbook (Demo R4)" — 11 REQs definitive text + traceability table.
- `.planning/PROJECT.md` §"Current Milestone: v0.20" + §"Open questions" — milestone framing (lean / additive), three-tier permission model definition, OQ-1 + OQ-5 recommended defaults.

### Phase 13 Inheritance (already live on `spoke-capsule`)

- `.planning/phases/13-rbac-narrowing-globaltenantresource-seed-delivery-mechanism/13-CONTEXT.md` — Phase 13 decisions (D-13-01..10+), OQ-2/3/4 resolutions, RBAC-01..06 + SEED-01..03 + DELIVERY-01..03 land state.
- `.planning/phases/13-rbac-narrowing-globaltenantresource-seed-delivery-mechanism/13-VALIDATION.md` — Phase 13 final validation evidence (live cluster state).
- `.planning/phases/13-rbac-narrowing-globaltenantresource-seed-delivery-mechanism/13-VERIFICATION.md` — Phase 13 verifier output (RBAC + SEED + DELIVERY GREEN).
- `docs/poc-capsule.md` — Operator's runbook for the `spoke-capsule` POC; Phase 13 appended a platform-owner H2 section (per Plan 13-04). Phase 14's demo runbook cross-links here for operational recovery procedures (fix-dns-poc-capsule).

### Architectural / Governance

- `docs/adr/0008-capsule-multi-tenancy-graduation.md` — POC graduation decision = DEFER per D-11-14 evidence-bound rubric. Demo runbook cross-links this as the "why we don't fix TLS noise" anchor (OQ-1 resolution) and as the "POC, not production" framing for the audience.
- `docs/adr/0004-hub-only-flux-control-plane.md` — Hub-only Flux pattern. Relevant because the `new-tenant.sh charlie` invocation in act 3 applies via `kubectl` (NOT via Flux reconcile) — keeps the demo direct + audience-observable.
- `docs/capsule-on-eks.md` — Self-contained EKS-targeted Capsule rough-cut. RUNBOOK-03 forward-pointer for the three-tier-on-EKS translation (Cloud Ops = AWS IAM admin / Karyon Platform Team = EKS IRSA-bound role / Tenants = Capsule-scoped workload-editors).

### Inherited Scripts (Phase 10 + Phase 13)

- `scripts/poc/capsule/issue-platform-owner-kubeconfig.sh` — Mints platform-owner kubeconfig (Phase 13 D-13-09). Used in pre-demo checklist + every platform-owner act.
- `scripts/poc/capsule/issue-tenant-kubeconfig.sh` — Mints tenant-owner kubeconfig via TokenRequest + tls.crt embed, routed through capsule-proxy NodePort 30443 (Phase 10). Used in pre-demo checklist + act 5.
- `scripts/poc/capsule/new-tenant.sh` — Provisions a new Tenant CR + namespace + human-tenant-owner SA via platform-owner kubeconfig (Phase 13 D-13-08). Used in act 3 with `charlie` (per D-14-02).
- `scripts/poc/capsule/fix-dns.sh` (invoked via `task fix-dns-poc-capsule`) — Hub-spoke DNS recovery on `spoke-capsule`. Pre-demo checklist conditional step.

### Bats Inheritance (Phase 13 falsifiable contracts)

- `tests/bats/rbac-08-live-platform-owner-grant-matrix.bats` — Phase 13 platform-owner live RBAC grant matrix.
- `tests/bats/rbac-09-live-platform-owner-kubeconfig.bats` — Phase 13 platform-owner kubeconfig sanity.
- `tests/bats/rbac-10-live-tenant-crud.bats` — Phase 13 RBAC-05 live Tenant CR CRUD (uses `phase13-fresh` throwaway).
- `tests/bats/seed-03-live-fresh-tenant.bats` — Phase 13 SEED-02 ≤ 60s falsifier on fresh tenant.
- `tests/bats/negative-rbac-01-cross-tenant-list.bats` — capsule-proxy LIST-filter cross-tenant rejection (inherited from Phase 11).

### Anti-Pattern / Invariant Anchors

- P31 — POC isolation: `spoke-capsule` never enters `task rebuild`; new artifacts stay under `pocs/capsule/` or `scripts/poc/capsule/`. **Phase 14 adds DOCS only (`docs/poc-capsule-demo.md`); no v0.18 default-path script edits.** DELIVERY-02 regression gate.
- P27 — Tenant Flux Kustomization `spec.serviceAccountName: flux-reconciler` defense. Not touched by Phase 14, but the runbook talk-track surfaces it during act 1 architecture overview (multi-tenancy lockdown context).
- P29 — Kubeconfigs never land in git; gitleaks defense. Phase 14 pre-demo checklist mints kubeconfigs to `/tmp` (per Phase 10 + Phase 13 conventions); runbook prose explicitly notes this.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- **`scripts/poc/capsule/new-tenant.sh`** — Already accepts `<name>` positional + `--kubeconfig` + `--dry-run`. Used verbatim in act 3 as `bash scripts/poc/capsule/new-tenant.sh charlie`. No edits required.
- **`scripts/poc/capsule/issue-platform-owner-kubeconfig.sh` + `issue-tenant-kubeconfig.sh`** — Mint both kubeconfig types. Used in pre-demo checklist; no edits required.
- **`scripts/poc/capsule/fix-dns.sh` + `task fix-dns-poc-capsule`** — Hub-spoke DNS recovery; conditional pre-demo step.
- **`docs/poc-capsule.md`** (Phase 7 + 10 + 13 cumulative content) — Operator's runbook. Cross-linked from `docs/poc-capsule-demo.md` for fix-dns + recovery procedures. NOT modified by Phase 14 (clean separation: operator runbook vs demo runbook).
- **`docs/capsule-on-eks.md` (Status: Reviewed per Phase 7 + Phase 11 D-11-15)** — EKS translation forward-pointer. Phase 14 may **append** a small "Three-tier model on EKS" section if the existing doc doesn't already explicitly map Tier 1/2/3 onto AWS IAM + EKS IRSA + Capsule. Planner verifies; appends only if gap exists.
- **Bats live-RBAC pattern** — `rbac-08..10`, `seed-02..03` establish the `${KUBECONFIG}` + `kubectl --kubeconfig=` + `Forbidden` assertion idiom. New DEMO bats inherit this pattern verbatim.

### Established Patterns

- **`docs/*.md` frontmatter convention** — `status: ...`, `audience: ...`, `purpose: ...`, `scope: ...`. New `docs/poc-capsule-demo.md` follows this.
- **6-act / N-section walkthrough cadence** — `docs/rebuild-runbook.md`, `docs/poc-capsule.md` use ordered `## Section N — Title` with concrete commands + expected output blocks. New demo runbook inherits.
- **Forbidden-action assertion idiom in bats** — `! kubectl ...` or `run kubectl ...; assert_output --partial "Forbidden"`. Inherited from `negative-rbac-*.bats` + `rbac-08-live-platform-owner-grant-matrix.bats`.
- **P31 isolation contract** — Demo runbook only references `scripts/poc/capsule/*` + `task fix-dns-poc-capsule` (the explicit POC Taskfile entry); never references v0.18 `task rebuild` / `task create-clusters` / `task deploy-examples` (those don't include `spoke-capsule`).
- **ADR-008 + D-11-14 evidence-bound rubric framing** — Capsule = POC, not production; demo runbook surfaces this in act 1 architecture overview + "Known noise" appendix.

### Integration Points

- **Demo runbook ↔ operator runbook** (`docs/poc-capsule-demo.md` cross-links `docs/poc-capsule.md` for fix-dns / recovery procedures + back-link from operator runbook to demo runbook).
- **Demo runbook ↔ EKS translation** (`docs/poc-capsule-demo.md` cross-links `docs/capsule-on-eks.md` for production forward-pointer).
- **Demo runbook ↔ ADR-008** (forward-pointer for "POC = DEFER" framing).
- **DEMO bats ↔ live `spoke-capsule` cluster** — bats drive both kubeconfigs against the live cluster; no fixture mocking. Pattern inherited from `rbac-08..10` Phase 13.
- **No code-level integration** — Phase 14 adds NO new YAML manifests under `pocs/capsule/`, NO new ClusterRoles, NO Helm value changes. Pure verification + documentation phase.

</code_context>

<specifics>
## Specific Ideas

- **Tenant name = `charlie`.** Phonetic alphabet continuity from `alpha` + `bravo`. (D-14-02)
- **TLS noise = document-only with cross-link to ADR-008.** Recommended default from milestone briefing. (D-14-01)
- **Live provisioning, no pre-staged delete+recreate dance.** Demo lives or dies on real-time Capsule materialization. (D-14-03)
- **One Forbidden action surfaced live in act 2; full 3-action denial matrix asserted in bats.** `kubectl create clusterrolebinding ...` is the headline rejection (most visceral). (D-14-07)
- **`task demo-capsule` Taskfile wrapper = no.** Keeps P31 isolation strict; all commands stay raw `bash scripts/poc/capsule/...` in the runbook. (D-14 Discretion note)
- **UAT = cold-read by milestone owner, stopwatched, captured in `14-VALIDATION.md`.** Pattern-mirrors Phase 13's `13-VALIDATION.md`. (D-14-10)

</specifics>

<deferred>
## Deferred Ideas

These came up during analysis but belong outside Phase 14:

- **Fix the `tls: bad certificate` chatter at the cert-rotation layer** (cert-manager wiring or proper CA distribution on capsule-controller). → Belongs to a future capsule-graduation phase (or a production EKS cut). Tracked via ADR-008 = DEFER. Phase 14 documents only.
- **`task demo-capsule` Taskfile wrapper for one-shot demo execution.** Tempting ergonomics but breaks P31 isolation (adds a `spoke-capsule` mention to the Taskfile). → Revisit at graduation, or in a future POC-ergonomics milestone if UAT identifies friction.
- **`capsule-addon-fluxcd` Trial (ADDON-01/02 carry-forward from v0.19 Phase 12).** Adopting addon-managed Flux + Capsule integration. → Already on v0.20 carry-forward parking lot; not load-bearing for the demo.
- **Pre-existing markdownlint failures + Phase 1–5 shellcheck warnings.** → v0.18 close carryover parking lot. Not Phase 14 scope.
- **Real secret management (Vault / SOPS / age) for the tenant kubeconfigs minted to `/tmp`.** → v0.18 close carryover. Phase 14 keeps the inherited `/tmp` pattern + P29 gitleaks defense.
- **G-04 architectural decision / split-Kustomization refactor.** Plan 11-07 D-11-01 PostBuild workaround stays. → Future-milestone architecture review. Not Phase 14.

### Reviewed Todos (not folded)

None — gsd-sdk `todo.match-phase 14` returned 0 matches; no todos were reviewed.

</deferred>

---

*Phase: 14-Two-Perspective-Demo-Verification-6-Act-Runbook-TLS-Noise-Resolution*
*Context gathered: 2026-05-19*
*Mode: --auto (recommended defaults; see 14-DISCUSSION-LOG.md for per-area auto-selection trail)*
