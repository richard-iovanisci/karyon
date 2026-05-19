---
gsd_state_version: 1.0
milestone: v0.20
milestone_name: Capsule POC Demo & RBAC Polish
status: Roadmap landed; awaiting Phase 13 discuss-phase
stopped_at: Phase 13 context gathered
last_updated: "2026-05-19T19:55:03.738Z"
last_activity: 2026-05-19 — Roadmap landed (Phases 13/14/15; 23/23 REQs mapped)
progress:
  total_phases: 3
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-05-19)

**Core value:** `task rebuild` performs a scorched-earth teardown and reaches a healthy hub-spoke Flux lab — with a CUDA-capable spoke — in under 20 minutes, every time.
**Current focus:** v0.20 — roadmap landed (Phases 13/14/15); REQUIREMENTS.md Traceability filled (23/23 mapped; 0 unmapped). Ready for Phase 13 discuss-phase (OQ-2 Secrets policy, OQ-3 workload shape, OQ-4 delivery path).

**Milestone framing (v0.20):** Lean / additive — Smallest viable phase count to ship the Capsule POC demo runbook and the least-privilege tenant ClusterRole. 3 phases total: Phase 13 (RBAC narrowing + GlobalTenantResource seed + delivery mechanism — 12 REQs), Phase 14 (two-perspective demo verification + 6-act runbook + TLS-noise resolution — 11 REQs), Phase 15 (v0.20 close-out + retrospective — 0 new REQs). Anti-scope guard active: no exploratory side-quests; existing alpha/bravo tenants + Flux reconciliation stay untouched.

## Current Position

Phase: Not started (Phase 13 ready to open with `/gsd-plan-phase 13`)
Plan: —
Status: Roadmap landed; awaiting Phase 13 discuss-phase
Last activity: 2026-05-19 — Roadmap landed (Phases 13/14/15; 23/23 REQs mapped)

## Performance Metrics

**Velocity:**

- Total plans completed (v0.18): 35
- Total plans completed (v0.19): 18
- Average duration: -
- Total execution time: -

**By Phase (v0.18 — shipped):**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01 | 9 | - | - |
| 02 | 7 | - | - |
| 03 | 6 | - | - |
| 04 | 5 | - | - |
| 05 | 6 | - | - |
| 06 | 8 | - | - |
| 07 | 6 | - | - |
| 09 | 5 | - | - |
| 10 | 3 | - | - |
| 11 | 6 | - | - |
| 12 | 7 | - | - |

**By Phase (v0.19 — shipped):**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 07 | 6 | - | - |
| 08 | 4 | - | - |
| 09 | 5 | - | - |
| 10 | 3 | - | - |
| 11 | 6 | - | - |
| 12 | 7 | - | - |

**By Phase (v0.20 — pending):**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 13 (RBAC + SEED + DELIVERY) | TBD | — | — |
| 14 (DEMO + RUNBOOK) | TBD | — | — |
| 15 (Close-out + Retrospective) | TBD | — | — |

**Recent Trend:**

- Last 5 plans: -
- Trend: -

*Updated after each plan completion*
| Phase 10 P00 | 7m5s | 7 tasks | 7 files |
| Phase 10 P01 | 22min | 2 tasks | 2 files |
| Phase 10 P02 | ~30min | 3 tasks | 1 file (10-VERIFICATION.md) |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table. Recent decisions affecting current work:

**v0.18 close (carried forward as inheritance for v0.19):**

- Phase 4 P18 invariant: `spec.kubeConfig.secretRef` blocks always use `key: value.yaml` — defense in depth against silent in-cluster fallback
- Phase 4 D-02: Sentinel-guarded patch surface in `clusters/hub-flux/flux-system/kustomization.yaml` (not the bootstrap-managed `kustomization.yaml` peer files); `# KARYON SPOKES MOUNT` sentinel + `../spokes` resource line; idempotent yq+awk insertion in `register-spokes-for-flux.sh`
- ADR-004: Hub-only Flux — no Flux controllers run on spokes; hub uses `spec.kubeConfig` + remote kubeconfig Secrets to reconcile
- D-14 blocking comment is exact-text greppable ('INTENTIONALLY NOT calling') — Phase 6 DESTROY-04 lint grep target; preserved through v0.19 P31 isolation contract
- Public-repo gitleaks defense (Phase 6 REPO-01..04): native pre-commit + `.gitleaks.toml` allowlist + post-push CI fetch-depth: 0 + one-shot history scan; v0.19 P29 extends with kubeconfig-shaped rule

**v0.20 milestone-open (2026-05-19):**

- Lean / additive milestone framing per `v0.20-MILESTONE-BRIEFING.md` — 5 in-scope demo requirements (R1 RBAC narrowing, R2 GlobalTenantResource seed, R3 capsule-proxy two-perspective demo, R4 demo runbook, R5 delivery path); 5 open questions deferred to discuss-phase; 11-item parking lot stays deferred
- Anti-scope guard active — discuss-phase "while we're at it" additions get rejected unless directly load-bearing for R1–R5
- Suggested decomposition (planner guidance): 2 phases (RBAC + GlobalTenantResource seed; then two-perspective demo + runbook) plus v0.20 close-out — planner MAY collapse but MUST NOT add a 4th phase
- ADR-008 = DEFER inheritance: v0.20 does NOT revisit graduation rubric (D-11-14)
- P27/P29/P31 invariants + `task rebuild` SLO < 230s preserved (no regression)
- Existing alpha/bravo Tenant CRs preserved as-is; v0.20 work is additive, NOT retroactive

**v0.20 roadmap landed (2026-05-19):**

- Selected 3-phase decomposition (briefing's suggested shape; not collapsed) — Phase 13 RBAC+SEED+DELIVERY artifacts (12 REQs), Phase 14 DEMO+RUNBOOK verification (11 REQs), Phase 15 close-out (0 new REQs). Rationale: Phase 13 builds the artifacts (ClusterRole, GlobalTenantResource, delivery mechanism, platform-owner co-ownership) with Wave 0 RED bats locking the falsifier matrix BEFORE implementation; Phase 14 verifies the two-perspective demo behavior live against the Phase 13 artifacts and writes the 6-act runbook. Collapsing would mean ~23 REQs in one phase + Wave 0 RED bats scaffolds for both artifact-shape AND live-demo-behavior in the same plan cluster — less healthy split. Phase 15 mirrors v0.19 Phase 12 close-out pattern at smaller scale.
- Three-tier permission model is the load-bearing architectural addition — Tier 1 (Cloud Ops) out-of-scope/talk-track only; Tier 2 (Karyon Platform Team / platform-owner) falsifiable via RBAC-04..06 + DEMO-06; Tier 3 (Tenant Devs / tenant-owner) narrower than k8s `edit` per RBAC-01/02 + DEMO-02/04/05
- OQ ownership: OQ-1 (TLS noise) → Phase 14; OQ-2 (Secrets policy) → Phase 13; OQ-3 (workload shape) → Phase 13; OQ-4 (delivery path) → Phase 13; OQ-5 (new-tenant name + live-provisioning style) → Phase 14
- 23/23 REQ coverage validated — Phase 13: RBAC-01..06 + SEED-01..03 + DELIVERY-01..03; Phase 14: DEMO-01..06 + RUNBOOK-01..05; Phase 15: 0 new (closes the 23 mandatory checkboxes against live evidence)

**v0.19 milestone-open (logged in PROJECT.md):**

- Selected 6-phase split (PITFALLS.md / ARCHITECTURE.md aligned over FEATURES.md 4-phase) — bundles risk: KARYON POC MOUNT static surface separated from cluster live work; webhook failure + teardown + ADR isolated from negative-RBAC validation
- Selected reconciliation pattern (c) — hub-managed, tenant-impersonated via per-tenant SA + capsule-proxy — over (a) reused cluster-admin SA (rejected: leaks cluster-admin to every tenant) and (b) Flux-on-spoke-capsule (rejected: ADR-004 violation)
- Install Capsule + capsule-proxy as TWO separate HelmReleases (NOT umbrella `proxy.enabled=true`) — umbrella pins capsule-proxy at 0.10.0 (two minors stale); standalone tracks both lines independently
- Phase 12 (capsule-addon-fluxcd) is OPTIONAL and gated on ADR-008 outcome — only run if Status is Accepted with outcome ∈ {adopt, defer}; if reject or replaced, Phase 12 is SKIPPED
- EKSDOC-01 lands EARLY in Phase 7 (first or second plan) — milestone owner needs the rough-cut EKS doc for an immediate team presentation while later phases land
- [Phase 10]: Phase 10 Plan 00 Wave 0 RED bats scaffold: 7 files (45 @tests) landed; Pitfall corrections (10-P1 tls.crt jsonpath, 10-P3 qualitative 403 falsifier, 10-P5 repo-relative paths) implemented verbatim; ZERO deviations — Mirrors Phase 7/8/9 Wave 0 D-09-08 inheritance — full PROXY-01/02/03 contract locked before Plan 10-01 lands script + doc. proxy-02 + proxy-06 GREEN-by-design (Phase 7 D-14 leak-defense regression-gate inheritance).
- [Phase ?]: Phase 10 Plan 10-01: issue-tenant-kubeconfig.sh script (PROXY-01) + docs/poc-capsule.md H2 append (PROXY-03) landed; Pitfall 10-P7 implemented via 5-helper function-override at definition time (cleaner than per-call-site >&2); Rule 3 deviation: capsule-proxy live-staged via helm install + RBAC patch (secrets create on tenant Role) to satisfy proxy-04 GREEN criterion — staging brought forward 1 plan from Plan 10-02 territory; proxy-05 stays RED (LIST filter wiring deferred to Plan 10-02 verifier)
- [Phase 10]: Phase 10 Plan 10-02 verifier: 10-VERIFICATION.md written with `passed_with_overrides` disposition; all 3 PROXY-01..03 must-haves verified live; 44/45 Phase 10 @tests GREEN (1 RED-by-design — Phase 8 BLOCKER G-04 inheritance); Pitfall 10-P1..P7 mitigations applied + verified; Phase 7 P31 + Phase 8 CAP-01..03 + Phase 9 TEN-01..06 + ADR-004 inheritance preserved; v0.18 task health-check exits 0; D-08-13 push-gate stays deferred to Phase 11 VAL-05; 2 Rule 3 deviations during verifier: (a) CapsuleConfiguration userGroups patched in-cluster to add system:serviceaccounts + system:authenticated (proxy LIST filter wiring); (b) tenant-alpha + tenant-bravo namespaces recreated as Capsule-owned via --as=alpha/bravo impersonation (home namespace ownership for proxy LIST visibility); both deviations documented in 10-VERIFICATION.md "Notable Observations" for Phase 11 push-gate awareness

### Load-Bearing Invariants Inherited Into v0.20 (every plan must respect)

- **P27** — every tenant Flux Kustomization MUST set `spec.serviceAccountName` explicitly. Flux's `--default-service-account` lockdown does NOT apply when `spec.kubeConfig` is set. Without explicit `serviceAccountName`, tenants run as cluster-admin and bypass Capsule. Static bats grep-asserts every tenant Kustomization has a non-null `serviceAccountName` (Phase 9 contract; Phase 11 falsifier).
- **P29** — tenant kubeconfigs MUST NOT land in git. Phase 7 expands `.gitignore` + adds `.gitleaks.toml` rule for `kind: Config` + bearer-token shape. Phase 10 generator defaults to `${TMPDIR:-/tmp}/karyon-tenants/` (outside repo) and prints to stdout. Phase 11 synthetic-fixture bats + one-shot history scan close the loop.
- **P31** — `spoke-capsule` MUST NOT enter `task rebuild` until graduation ADR-008 says "adopt." All POC concerns under `scripts/poc/capsule/`. Static bats greps `scripts/` (excluding `scripts/poc/`) for `spoke-capsule` and asserts ZERO mentions. Phase 11 live regression test: `task rebuild` with spoke-capsule alive must complete in <230s with spoke-capsule container ID unchanged.
- **KARYON POC MOUNT location** — sentinel goes in `clusters/hub-flux/flux-system/kustomization.yaml` (the FLUX PATCH SURFACE), parallel to existing `# KARYON SPOKES MOUNT`. NOT `clusters/hub-flux/kustomization.yaml`. Putting it in the wrong file means the sentinel does not survive `flux bootstrap` re-runs.
- **ADR-008 = DEFER stands** — v0.20 does NOT revisit graduation rubric (D-11-14). No new ADRs in v0.20.
- **Existing alpha/bravo Tenant CRs** — additive co-ownership only (RBAC-06 appends `capsule-platform-owners` to `spec.owners[]`); existing Flux SA owner pattern (RBAC-03) MUST be preserved across all Phase 13 implementation.

### Pending Todos

- **Phase 7 carryover — hub Flux observable reconcile of `poc-capsule` (RESOLVED 2026-05-11)** — All 4 outer Flux Kustomizations Ready=True at HEAD `8415ab66` per `11-07-SUMMARY.md` (G-04 + G-06 closed). Todo moved to `.planning/todos/completed/2026-04-29-phase-7-hub-flux-observable-reconcile.md` by Plan 12-05.
- **Phase 7 carryover — gitleaks rule fires on planning docs that quote inert synthetic fixture (RESOLVED 2026-05-07)** — Allowlist for proxy-fixture source landed in commit `384f859 fix(11-07): allowlist proxy fixture source`; Phase 11 VAL-05 one-shot history scan passed (per `11-VERIFICATION.md` VAL-05 row). Original todo file: `.planning/todos/pending/2026-04-29-phase-7-gitleaks-planning-doc-allowlist.md` (not yet relocated; lifecycle managed independent of Plan 12-05 hub-flux move).
- **Phase 7 HUMAN-UAT items 2/3/4** (non-blocking; tracked in `07-HUMAN-UAT.md`). Real Docker/WSL restart recovery (item 2 — environmental, observe-when-it-happens), Mermaid GitHub render fidelity (item 3 — gated behind first-push deferred to Phase 11), EKS doc presentation walkthrough (item 4 — subjective milestone-owner judgment).
- **Phase 8 BLOCKER gap G-03 (BL-01) — cert source incompatible with D-08-04 (RESOLVED 2026-04-30)** — Decision D-08-11 cert flip applied in commit `75e5b78 fix(08-04): D-08-11 cert flip on proxy HR + WR-01/WR-02 yq-path bats hardening`; closure summarized in commit `ecbb4b6 docs(08-04): plan summary — gap-close (G-03 cert + G-04 split-K + WR-01..04 lints)`. Phase 8 re-verification commit `2c60d5a docs(08): re-verification post-gap-close — passed_with_overrides` confirms G-03 closed. → `08-VERIFICATION.md` Gap G-03.
- **Phase 8 BLOCKER gap G-04 — architectural seam: outer Kustomization → spoke applies HR CRs to wrong cluster (RESOLVED 2026-04-30)** — Decision D-08-12 split-Kustomization architecture (Option B) applied in commit `a9af679 fix(08-04): D-08-12 architectural seam fix — split outer K into hub-targeted + spoke-targeted`; closure summarized in commit `ecbb4b6 docs(08-04): plan summary — gap-close (G-03 cert + G-04 split-K + WR-01..04 lints)`. P40/P18 invariant evolved: split-path pattern (spoke-targeted Ks include kubeConfig; hub-targeted Ks exclude it). Phase 8 re-verification commit `2c60d5a docs(08): re-verification post-gap-close — passed_with_overrides` confirms G-04 closed. → `08-VERIFICATION.md` Gap G-04.

### Blockers/Concerns

- Phase 9 lockdown flag patches (`--no-cross-namespace-refs=true`, `--no-remote-bases=true`, `--default-service-account=default`) touch the v0.18 Flux bootstrap surface — high regression risk. Mitigation: rerun full v0.18 `task health-check` as Phase 9 acceptance gate.
- Phase 11 SLO regression gate (<230s) is the single hardest invariant of the milestone. P31 enforces zero `spoke-capsule` mentions in any v0.18 script — must be locked early in Phase 7 with static bats.
- capsule-addon-fluxcd v0.2.3 ↔ Capsule v0.12.4 specific compatibility is MEDIUM-confidence (date proximity strong; README declaration absent). Phase 12 should re-verify via smoke test if the addon is brought into scope.
- k8s ≥ 1.34.0 floor: `rancher/k3s:v1.34.6-k3s1` (ADR-005) clears with 6 patches of margin. If k3s is bumped to 1.35+, Capsule must be re-verified.
- [Plan 10-02 RESOLVED]: capsule-proxy LIST filter wired (CapsuleConfiguration userGroups patched + tenant-alpha/bravo home namespaces recreated as Capsule-owned); proxy-07 @test 3 documented as passed_with_overrides; chart-level RBAC patch carried forward to Phase 11 VAL-05 (3 carryover items in 10-VERIFICATION.md "Carryover to Phase 11" section: chart RBAC patch persistence; CapsuleConfiguration userGroups; tenant home namespace ownership)
- **v0.20 Phase 13 dependency on Phase 10 carryover wiring**: capsule-proxy LIST filter (CapsuleConfiguration userGroups + tenant home namespace ownership) was patched live in Plan 10-02 and persisted into Phase 11. v0.20 Phase 13 platform-owner LIST visibility (RBAC-06 + DEMO-01) and tenant-owner LIST scoping (DEMO-02) BOTH depend on this wiring continuing to hold. Phase 13 discuss-phase should confirm live state before opening Plan 13-01.

## Deferred Items

Items acknowledged and carried forward from previous milestone close:

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| v0.18 follow-up | Phase 1-5 shellcheck warning cleanup (SC2034 / SC2155) | Active | v0.18 close 2026-04-29 |
| v0.18 follow-up | First-push CI verification + GitHub branch-protection setup | Active | v0.18 close 2026-04-29 |
| v0.18 follow-up | Real secret management (Vault / SOPS / age) | Active | v0.18 explicit out-of-scope |
| v0.18 follow-up | Stale frontmatter reconciliation pass | Active | v0.18 close 2026-04-29 |
| v0.19 phase-7 carryover | Hub Flux observable reconcile of `poc-capsule` Kustomization (script-internal P18 falsifier passed; runtime Flux observation deferred) | Active (resolves_phase: 8) — Phase 8 verifier truth #7 *momentarily* PASS at `32e0b2fa` but masked by empty inventory; G-04 will break on push | Phase 7 close 2026-04-29 |
| v0.19 phase-7 carryover | gitleaks `kubeconfig-bearer-token` rule fires on planning docs (07-00-PLAN, 07-RESEARCH, 07-REVIEW) that quote inert synthetic fixture content; first-push CI will fail until allowlisted | Active (resolves_phase: 11) | Phase 7 close 2026-04-29 |
| v0.19 phase-8 gap | G-03 (BL-01) — `certManager.generateCertificates: true` in `pocs/capsule/proxy/helmrelease.yaml:75-76` requires absent cert-manager controller; proxy pod cannot mount TLS volume | Active (BLOCKER — needs gap-fix plan) | Phase 8 verifier 2026-04-29 |
| v0.19 phase-8 gap | G-04 — outer `clusters/hub-flux/pocs/capsule.yaml` `spec.kubeConfig: spoke-capsule-kubeconfig` redirects HR/OCIRepo CRs to spoke which has no Flux CRDs; outer Kustomization Ready=False on push | Active (BLOCKER — needs architectural decision) | Phase 8 verifier 2026-04-29 |
| v0.19 close-out (still deferred into v0.20) | ADDON-01 / ADDON-02 capsule-addon-fluxcd Trial + hand-managed vs addon-managed comparison doc | Active (parking lot; no plan in v0.20) | v0.19 close 2026-05-18 |
| v0.19 close-out (still deferred into v0.20) | G-04 architectural decision / split-Kustomization refactor (PostBuild workaround stays) | Active (future-milestone concern) | v0.19 close 2026-05-18 |
| v0.19 close-out (still deferred into v0.20) | Optional `KARYON_PHASE11_STRICT_LIVE=1` re-verification path | Active (future-milestone concern) | v0.19 close 2026-05-18 |
| v0.19 close-out (still deferred into v0.20) | slo-regression-live `KARYON_REBUILD_APPROVED` infrastructure | Active (future-milestone concern) | v0.19 close 2026-05-18 |
| v0.19 close-out (still deferred into v0.20) | Pre-existing markdownlint failures | Active (lint cleanup deferred) | v0.19 close 2026-05-18 |
| v0.19 close-out (still deferred into v0.20) | Pre-existing gitleaks finding in `proxy-06` fixture (allowlisted) | Active (lint cleanup deferred) | v0.19 close 2026-05-18 |

## Session Continuity

Last session: 2026-05-19T19:55:03.732Z
Stopped at: Phase 13 context gathered
Resume file: .planning/phases/13-rbac-narrowing-globaltenantresource-seed-delivery-mechanism/13-CONTEXT.md
