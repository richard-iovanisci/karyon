---
gsd_state_version: 1.0
milestone: v0.19
milestone_name: — Capsule Multi-Tenancy POC
status: executing
stopped_at: Phase 11 context gathered
last_updated: "2026-05-05T23:36:31.745Z"
last_activity: 2026-05-05 -- Phase 11 planning complete
progress:
  total_phases: 6
  completed_phases: 4
  total_plans: 25
  completed_plans: 19
  percent: 76
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-29)

**Core value:** `task rebuild` performs a scorched-earth teardown and reaches a healthy hub-spoke Flux lab — with a CUDA-capable spoke — in under 20 minutes, every time.
**Current focus:** Phase 11 — Validation + Graduation ADR-008 (VAL-01..06)

**Phase counting choice:** `total_phases: 5` counts only the 5 MANDATORY phases (7-11). Phase 12 (capsule-addon-fluxcd) is OPTIONAL and gated on ADR-008 outcome ∈ {adopt, defer}; it is tracked separately as `total_phases_with_optional: 6`. Progress percent computes against the mandatory 5 unless Phase 12 is activated, at which point it switches to 6.

## Current Position

Phase: 11
Plan: Not started
Status: Ready to execute
Last activity: 2026-05-05 -- Phase 11 planning complete

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

**By Phase (v0.19 — pending):**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 07 | 6 | - | - |
| 08 | 4 | - | - |
| 09 | 5 | - | - |
| 10 | 3 | - | - |
| 11 | TBD | - | - |
| 12 (optional) | TBD | - | - |

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

**v0.19 milestone-open (logged in PROJECT.md):**

- Selected 6-phase split (PITFALLS.md / ARCHITECTURE.md aligned over FEATURES.md 4-phase) — bundles risk: KARYON POC MOUNT static surface separated from cluster live work; webhook failure + teardown + ADR isolated from negative-RBAC validation
- Selected reconciliation pattern (c) — hub-managed, tenant-impersonated via per-tenant SA + capsule-proxy — over (a) reused cluster-admin SA (rejected: leaks cluster-admin to every tenant) and (b) Flux-on-spoke-capsule (rejected: ADR-004 violation)
- Install Capsule + capsule-proxy as TWO separate HelmReleases (NOT umbrella `proxy.enabled=true`) — umbrella pins capsule-proxy at 0.10.0 (two minors stale); standalone tracks both lines independently
- Phase 12 (capsule-addon-fluxcd) is OPTIONAL and gated on ADR-008 outcome — only run if Status is Accepted with outcome ∈ {adopt, defer}; if reject or replaced, Phase 12 is SKIPPED
- EKSDOC-01 lands EARLY in Phase 7 (first or second plan) — milestone owner needs the rough-cut EKS doc for an immediate team presentation while later phases land
- [Phase 10]: Phase 10 Plan 00 Wave 0 RED bats scaffold: 7 files (45 @tests) landed; Pitfall corrections (10-P1 tls.crt jsonpath, 10-P3 qualitative 403 falsifier, 10-P5 repo-relative paths) implemented verbatim; ZERO deviations — Mirrors Phase 7/8/9 Wave 0 D-09-08 inheritance — full PROXY-01/02/03 contract locked before Plan 10-01 lands script + doc. proxy-02 + proxy-06 GREEN-by-design (Phase 7 D-14 leak-defense regression-gate inheritance).
- [Phase ?]: Phase 10 Plan 10-01: issue-tenant-kubeconfig.sh script (PROXY-01) + docs/poc-capsule.md H2 append (PROXY-03) landed; Pitfall 10-P7 implemented via 5-helper function-override at definition time (cleaner than per-call-site >&2); Rule 3 deviation: capsule-proxy live-staged via helm install + RBAC patch (secrets create on tenant Role) to satisfy proxy-04 GREEN criterion — staging brought forward 1 plan from Plan 10-02 territory; proxy-05 stays RED (LIST filter wiring deferred to Plan 10-02 verifier)
- [Phase 10]: Phase 10 Plan 10-02 verifier: 10-VERIFICATION.md written with `passed_with_overrides` disposition; all 3 PROXY-01..03 must-haves verified live; 44/45 Phase 10 @tests GREEN (1 RED-by-design — Phase 8 BLOCKER G-04 inheritance); Pitfall 10-P1..P7 mitigations applied + verified; Phase 7 P31 + Phase 8 CAP-01..03 + Phase 9 TEN-01..06 + ADR-004 inheritance preserved; v0.18 task health-check exits 0; D-08-13 push-gate stays deferred to Phase 11 VAL-05; 2 Rule 3 deviations during verifier: (a) CapsuleConfiguration userGroups patched in-cluster to add system:serviceaccounts + system:authenticated (proxy LIST filter wiring); (b) tenant-alpha + tenant-bravo namespaces recreated as Capsule-owned via --as=alpha/bravo impersonation (home namespace ownership for proxy LIST visibility); both deviations documented in 10-VERIFICATION.md "Notable Observations" for Phase 11 push-gate awareness

### Load-Bearing v0.19 Invariants (every plan must respect)

- **P27** — every tenant Flux Kustomization MUST set `spec.serviceAccountName` explicitly. Flux's `--default-service-account` lockdown does NOT apply when `spec.kubeConfig` is set. Without explicit `serviceAccountName`, tenants run as cluster-admin and bypass Capsule. Static bats grep-asserts every tenant Kustomization has a non-null `serviceAccountName` (Phase 9 contract; Phase 11 falsifier).
- **P29** — tenant kubeconfigs MUST NOT land in git. Phase 7 expands `.gitignore` + adds `.gitleaks.toml` rule for `kind: Config` + bearer-token shape. Phase 10 generator defaults to `${TMPDIR:-/tmp}/karyon-tenants/` (outside repo) and prints to stdout. Phase 11 synthetic-fixture bats + one-shot history scan close the loop.
- **P31** — `spoke-capsule` MUST NOT enter `task rebuild` until graduation ADR-008 says "adopt." All POC concerns under `scripts/poc/capsule/`. Static bats greps `scripts/` (excluding `scripts/poc/`) for `spoke-capsule` and asserts ZERO mentions. Phase 11 live regression test: `task rebuild` with spoke-capsule alive must complete in <230s with spoke-capsule container ID unchanged.
- **KARYON POC MOUNT location** — sentinel goes in `clusters/hub-flux/flux-system/kustomization.yaml` (the FLUX PATCH SURFACE), parallel to existing `# KARYON SPOKES MOUNT`. NOT `clusters/hub-flux/kustomization.yaml`. Putting it in the wrong file means the sentinel does not survive `flux bootstrap` re-runs.

### Pending Todos

- **Phase 7 carryover — hub Flux observable reconcile of `poc-capsule`** (resolves_phase: 8). Script-internal P18 falsifier passed; runtime Flux observation of `Ready=True` deferred to Phase 8 where CAP-01/02 HelmRelease landings naturally exercise the seam. Phase 8 verifier truth #7 *momentarily* observed Ready=True at `32e0b2fa`, but masked by empty inventory (G-04 will break this on push). → `.planning/todos/pending/2026-04-29-phase-7-hub-flux-observable-reconcile.md`
- **Phase 7 carryover — gitleaks rule fires on planning docs that quote inert synthetic fixture** (resolves_phase: 11). New `kubeconfig-bearer-token` rule catches embedded fixture YAML in 3 planning docs; CI gitleaks-scan job will fail on first push to origin. Phase 11 VAL-05 owns one-shot history scan; resolution must precede VAL-05. → `.planning/todos/pending/2026-04-29-phase-7-gitleaks-planning-doc-allowlist.md`
- **Phase 7 HUMAN-UAT items 2/3/4** (non-blocking; tracked in `07-HUMAN-UAT.md`). Real Docker/WSL restart recovery (item 2 — environmental, observe-when-it-happens), Mermaid GitHub render fidelity (item 3 — gated behind first-push deferred to Phase 11), EKS doc presentation walkthrough (item 4 — subjective milestone-owner judgment).
- **Phase 8 BLOCKER gap G-03 (BL-01) — cert source incompatible with D-08-04**. `pocs/capsule/proxy/helmrelease.yaml:75-76` uses `certManager.generateCertificates: true` which requires a cert-manager controller; spoke-capsule has none. Verifier-recommended fix: flip to `options.generateCertificates: true` + `certManager.generateCertificates: false` (controller-less certgen Job). → `08-VERIFICATION.md` Gap G-03 (untracked file).
- **Phase 8 BLOCKER gap G-04 — architectural seam: outer Kustomization → spoke applies HR CRs to wrong cluster**. Outer `clusters/hub-flux/pocs/capsule.yaml` carries `spec.kubeConfig: spoke-capsule-kubeconfig` (Phase 7 P40/P18 invariant) but spoke has no Flux CRDs. Server-side dry-run confirms `no matches for kind "HelmRelease"`. Requires architectural decision (verifier offers Option A: remove kubeConfig from outer; Option B: split paths) before push. → `08-VERIFICATION.md` Gap G-04.

### Blockers/Concerns

- Phase 9 lockdown flag patches (`--no-cross-namespace-refs=true`, `--no-remote-bases=true`, `--default-service-account=default`) touch the v0.18 Flux bootstrap surface — high regression risk. Mitigation: rerun full v0.18 `task health-check` as Phase 9 acceptance gate.
- Phase 11 SLO regression gate (<230s) is the single hardest invariant of the milestone. P31 enforces zero `spoke-capsule` mentions in any v0.18 script — must be locked early in Phase 7 with static bats.
- capsule-addon-fluxcd v0.2.3 ↔ Capsule v0.12.4 specific compatibility is MEDIUM-confidence (date proximity strong; README declaration absent). Phase 12 should re-verify via smoke test if the addon is brought into scope.
- k8s ≥ 1.34.0 floor: `rancher/k3s:v1.34.6-k3s1` (ADR-005) clears with 6 patches of margin. If k3s is bumped to 1.35+, Capsule must be re-verified.
- [Plan 10-02 RESOLVED]: capsule-proxy LIST filter wired (CapsuleConfiguration userGroups patched + tenant-alpha/bravo home namespaces recreated as Capsule-owned); proxy-07 @test 3 documented as passed_with_overrides; chart-level RBAC patch carried forward to Phase 11 VAL-05 (3 carryover items in 10-VERIFICATION.md "Carryover to Phase 11" section: chart RBAC patch persistence; CapsuleConfiguration userGroups; tenant home namespace ownership)

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

## Session Continuity

Last session: 2026-05-05T20:29:32.608Z
Stopped at: Phase 11 context gathered
Resume file: .planning/phases/11-validation-graduation-adr-008/11-CONTEXT.md
