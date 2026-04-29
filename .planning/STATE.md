---
gsd_state_version: 1.0
milestone: v0.19
milestone_name: Capsule Multi-Tenancy POC
status: executing
stopped_at: Phase 7 context gathered
last_updated: "2026-04-29T14:30:50.525Z"
last_activity: 2026-04-29 -- Phase 7 execution started
progress:
  total_phases: 6
  completed_phases: 0
  total_plans: 6
  completed_plans: 0
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-29)

**Core value:** `task rebuild` performs a scorched-earth teardown and reaches a healthy hub-spoke Flux lab — with a CUDA-capable spoke — in under 20 minutes, every time.
**Current focus:** Phase 7 — Foundation — POC Seam + spoke-capsule Cluster + EKS Capsule Doc

**Phase counting choice:** `total_phases: 5` counts only the 5 MANDATORY phases (7-11). Phase 12 (capsule-addon-fluxcd) is OPTIONAL and gated on ADR-008 outcome ∈ {adopt, defer}; it is tracked separately as `total_phases_with_optional: 6`. Progress percent computes against the mandatory 5 unless Phase 12 is activated, at which point it switches to 6.

## Current Position

Phase: 7 (Foundation — POC Seam + spoke-capsule Cluster + EKS Capsule Doc) — EXECUTING
Plan: 1 of 6
Status: Executing Phase 7
Last activity: 2026-04-29 -- Phase 7 execution started

## Performance Metrics

**Velocity:**

- Total plans completed (v0.18): 35
- Total plans completed (v0.19): 0
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

**By Phase (v0.19 — pending):**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 07 | TBD | - | - |
| 08 | TBD | - | - |
| 09 | TBD | - | - |
| 10 | TBD | - | - |
| 11 | TBD | - | - |
| 12 (optional) | TBD | - | - |

**Recent Trend:**

- Last 5 plans: -
- Trend: -

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table. Recent decisions affecting current work:

**v0.18 close (carried forward as inheritance for v0.19):**

- Phase 4 P18 invariant: `spec.kubeConfig.secretRef` blocks always use `key: value.yaml` — defense in depth against silent in-cluster fallback
- Phase 4 D-02: Sentinel-guarded patch surface in `clusters/hub-flux/flux-system/kustomization.yaml` (not the bootstrap-managed `kustomization.yaml` peer files); `# KARYON SPOKES MOUNT` sentinel + `../spokes` resource line; idempotent yq+awk insertion in `register-spokes-for-flux.sh`
- ADR-004: Hub-only Flux — no Flux controllers run on spokes; hub uses `spec.kubeConfig` + remote kubeconfig Secrets to reconcile
- D-14 blocking comment is exact-text greppable ('INTENTIONALLY NOT calling') — Phase 6 DESTROY-04 lint grep target; preserved through v0.19 P31 isolation contract
- Public-repo gitleaks defense (Phase 6 REPO-01..04): native pre-commit + `.gitleaks.toml` allowlist + post-push CI fetch-depth: 0 + one-shot history scan; v0.19 P29 extends with kubeconfig-shaped rule

**v0.19 milestone-open (logged in PROJECT.md):**

- Selected 6-phase split (PITFALLS.md / ARCHITECTURE.md aligned over FEATURES.md 4-phase) — bundles risk: KARYON POC MOUNT static surface separated from cluster live work; webhook failure + teardown + ADR isolated from negative-RBAC validation
- Selected reconciliation pattern (c) — hub-managed, tenant-impersonated via per-tenant SA + capsule-proxy — over (a) reused cluster-admin SA (rejected: leaks cluster-admin to every tenant) and (b) Flux-on-spoke-capsule (rejected: ADR-004 violation)
- Install Capsule + capsule-proxy as TWO separate HelmReleases (NOT umbrella `proxy.enabled=true`) — umbrella pins capsule-proxy at 0.10.0 (two minors stale); standalone tracks both lines independently
- Phase 12 (capsule-addon-fluxcd) is OPTIONAL and gated on ADR-008 outcome — only run if Status is Accepted with outcome ∈ {adopt, defer}; if reject or replaced, Phase 12 is SKIPPED
- EKSDOC-01 lands EARLY in Phase 7 (first or second plan) — milestone owner needs the rough-cut EKS doc for an immediate team presentation while later phases land

### Load-Bearing v0.19 Invariants (every plan must respect)

- **P27** — every tenant Flux Kustomization MUST set `spec.serviceAccountName` explicitly. Flux's `--default-service-account` lockdown does NOT apply when `spec.kubeConfig` is set. Without explicit `serviceAccountName`, tenants run as cluster-admin and bypass Capsule. Static bats grep-asserts every tenant Kustomization has a non-null `serviceAccountName` (Phase 9 contract; Phase 11 falsifier).
- **P29** — tenant kubeconfigs MUST NOT land in git. Phase 7 expands `.gitignore` + adds `.gitleaks.toml` rule for `kind: Config` + bearer-token shape. Phase 10 generator defaults to `${TMPDIR:-/tmp}/karyon-tenants/` (outside repo) and prints to stdout. Phase 11 synthetic-fixture bats + one-shot history scan close the loop.
- **P31** — `spoke-capsule` MUST NOT enter `task rebuild` until graduation ADR-008 says "adopt." All POC concerns under `scripts/poc/capsule/`. Static bats greps `scripts/` (excluding `scripts/poc/`) for `spoke-capsule` and asserts ZERO mentions. Phase 11 live regression test: `task rebuild` with spoke-capsule alive must complete in <230s with spoke-capsule container ID unchanged.
- **KARYON POC MOUNT location** — sentinel goes in `clusters/hub-flux/flux-system/kustomization.yaml` (the FLUX PATCH SURFACE), parallel to existing `# KARYON SPOKES MOUNT`. NOT `clusters/hub-flux/kustomization.yaml`. Putting it in the wrong file means the sentinel does not survive `flux bootstrap` re-runs.

### Pending Todos

None yet. [From .planning/todos/pending/ — ideas captured during sessions.]

### Blockers/Concerns

- Phase 9 lockdown flag patches (`--no-cross-namespace-refs=true`, `--no-remote-bases=true`, `--default-service-account=default`) touch the v0.18 Flux bootstrap surface — high regression risk. Mitigation: rerun full v0.18 `task health-check` as Phase 9 acceptance gate.
- Phase 11 SLO regression gate (<230s) is the single hardest invariant of the milestone. P31 enforces zero `spoke-capsule` mentions in any v0.18 script — must be locked early in Phase 7 with static bats.
- capsule-addon-fluxcd v0.2.3 ↔ Capsule v0.12.4 specific compatibility is MEDIUM-confidence (date proximity strong; README declaration absent). Phase 12 should re-verify via smoke test if the addon is brought into scope.
- k8s ≥ 1.34.0 floor: `rancher/k3s:v1.34.6-k3s1` (ADR-005) clears with 6 patches of margin. If k3s is bumped to 1.35+, Capsule must be re-verified.

## Deferred Items

Items acknowledged and carried forward from previous milestone close:

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| v0.18 follow-up | Phase 1-5 shellcheck warning cleanup (SC2034 / SC2155) | Active | v0.18 close 2026-04-29 |
| v0.18 follow-up | First-push CI verification + GitHub branch-protection setup | Active | v0.18 close 2026-04-29 |
| v0.18 follow-up | Real secret management (Vault / SOPS / age) | Active | v0.18 explicit out-of-scope |
| v0.18 follow-up | Stale frontmatter reconciliation pass | Active | v0.18 close 2026-04-29 |

## Session Continuity

Last session: 2026-04-29T13:08:22.420Z
Stopped at: Phase 7 context gathered
Resume file: .planning/phases/07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc/07-CONTEXT.md

**Planned Phase:** 07 (foundation-poc-seam-spoke-capsule-eks-doc) — TBD plans — 2026-04-29
