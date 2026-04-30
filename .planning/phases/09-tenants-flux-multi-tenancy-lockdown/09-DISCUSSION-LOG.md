# Phase 9: Tenants + Flux Multi-Tenancy Lockdown - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-29
**Phase:** 09-tenants-flux-multi-tenancy-lockdown
**Mode:** `--auto` (Claude selected recommended defaults across all gray areas; no interactive questions)
**Areas discussed:** Directory layout, Tenant owner identity, Tenant inner Kustomization shape, CapsuleConfiguration placement, Lockdown patch surface + per-controller scoping, flux-system Kustomization escape hatch, dependsOn chain (P32), TEN-02/03 verifier path, Test scaffolding pattern, Plan ordering

---

## Directory Layout (D-09-01)

| Option | Description | Selected |
|--------|-------------|----------|
| Flat layout | `pocs/capsule/{tenant-alpha.yaml, tenant-bravo.yaml, capsuleconfig.yaml}` — everything at one level | |
| Split-path inheritance | Extend Phase 8 D-08-12 split-path: hub-targeted under `pocs/capsule/tenants/`, spoke-targeted under `pocs/capsule/spoke/{config,tenants}/` | ✓ |
| Per-area subdirs without split-path awareness | Each tenant gets one subdir mixing hub/spoke content | |

**Selection rationale (auto-mode default):** Phase 8 D-08-12 split-path is a load-bearing architectural seam (validated by the gap-close cycle). Phase 9 inherits the same hub-targeted vs spoke-targeted distinction to preserve the invariant. Flat layout would lose split-path; mixed-content subdirs would re-introduce the architectural ambiguity D-08-12 closed.

---

## Tenant Owner Identity (D-09-02)

| Option | Description | Selected |
|--------|-------------|----------|
| Per-tenant SA only (`<tenant-ns>:gitops-reconciler`) | Single SA owner per Tenant; `kubectl --as=alpha` would fail | |
| Per-tenant SA + per-tenant User | Multi-owner Tenant: SA for Flux impersonation + User for `kubectl --as` testing | ✓ |
| Shared SA in flux-system across tenants | One `flux-system:gitops-reconciler` registered as owner on both Tenants; weaker isolation | |

**Selection rationale (auto-mode default):** TEN-01 contract literal phrasing locks per-tenant SA pattern (`<tenant-ns>:gitops-reconciler`); TEN-02 contract literal phrasing locks `kubectl --as=alpha`. Multi-owner Tenant CR satisfies both contracts in one CR. Shared-SA simplification rejected because it weakens P27 defense (one SA owner of both tenants → path-discipline-only isolation).

---

## Tenant Inner Kustomization Shape (D-09-03)

| Option | Description | Selected |
|--------|-------------|----------|
| Use `<tenant>-proxy-kubeconfig` immediately in Phase 9 | Mint per-tenant proxy kubeconfigs in Phase 9 + use directly | |
| Transitional: `spoke-capsule-kubeconfig` + SA impersonation in Phase 9; swap to per-tenant proxy in Phase 10 | Phase 9 ships P27 structural defense; Phase 10 swaps kubeConfig source | ✓ |
| Hub-side direct apply (no kubeConfig at all) | Apply tenant content to hub locally; tenant resources land on hub instead of spoke | |

**Selection rationale (auto-mode default):** ROADMAP Phase 9 (TEN-01..06) does NOT include kubeconfig minting — that's Phase 10 PROXY-01..03. Using existing `spoke-capsule-kubeconfig` + `serviceAccountName: gitops-reconciler` impersonation gives P27 defense in Phase 9 without bringing Phase 10 scope forward. Hub-side direct apply rejected because it doesn't validate the cross-cluster reconcile path.

---

## CapsuleConfiguration Placement (D-09-04)

| Option | Description | Selected |
|--------|-------------|----------|
| Inline with Tenant CRs | Single `tenants.yaml` containing CapsuleConfiguration + Tenant CRs | |
| Dedicated `pocs/capsule/spoke/config/` subdir | CapsuleConfiguration gets its own subdir, mirroring D-08-01 operator/proxy convention | ✓ |
| Top-level `pocs/capsule/spoke/capsuleconfig.yaml` flat file | Single file, no subdir | |

**Selection rationale (auto-mode default):** Mirrors D-08-01 two-subdir layout pattern. Each functional area (operator, proxy, config, tenants) gets its own self-contained subdirectory. Forward-compatible with adding more cluster-scoped policy CRs later (e.g., `GlobalTenantResource`) under `config/`.

---

## Lockdown Patch Surface + Per-Controller Scoping (D-09-05)

| Option | Description | Selected |
|--------|-------------|----------|
| Patch all 4 controllers with all 3 flags | Apply unscoped flag set to kustomize/helm/source/notification controllers | |
| Patch kustomize-controller only with all 3 flags + scoped single-flag patches for helm/notification | Per-controller scope per Flux v2.8 docs | ✓ |
| Apply flags to bootstrap-managed flux-system file directly | Edit `gotk-components.yaml` directly (anti-pattern; bootstrap-reverted) | |
| Single new file `clusters/hub-flux/flux-system/lockdown-patches.yaml` | Side-car file referenced from kustomization.yaml | |

**Selection rationale (auto-mode default):** Per-controller flag scoping per Flux v2.8 docs — each controller accepts only the subset that makes semantic sense. kustomize-controller accepts all 3; helm-controller and notification-controller accept `--no-cross-namespace-refs` only; source-controller accepts none (sources are owned cross-namespace by design). Inline `patches:` block in `clusters/hub-flux/flux-system/kustomization.yaml` (FLUX PATCH SURFACE — the documented hand-edit surface that survives `flux bootstrap` re-runs) keeps everything together with the existing sentinels. Side-car file rejected because it diverges from the established sentinel pattern. Editing `gotk-components.yaml` directly is the documented anti-pattern.

---

## flux-system Kustomization Escape Hatch (D-09-05a)

| Option | Description | Selected |
|--------|-------------|----------|
| Patch the flux-system Kustomization CR to set `spec.serviceAccountName: kustomize-controller` | Platform-admin escape hatch via Kustomization-CR patch in same `patches:` block | ✓ |
| Skip the escape hatch | Apply `--default-service-account=default` flag without flux-system K patch (BREAKS Flux) | |
| Use a different SA name | Create a new platform-admin SA with explicit cluster-admin CRB | |

**Selection rationale (auto-mode default):** The `--default-service-account=default` flag means any local-cluster Kustomization CR without `spec.serviceAccountName` reconciles as a no-permission `default` SA. The bootstrap-managed `flux-system` Kustomization CR does NOT set serviceAccountName by default, so the lockdown immediately bricks Flux's own bootstrap reconcile WITHOUT this patch. The `kustomize-controller` SA (which RUNS kustomize-controller) already has cluster-admin via the `flux-system` ClusterRoleBinding, so reusing it is the cheapest hatch. Different-SA option rejected because it adds an unnecessary SA + CRB.

---

## P32 dependsOn Chain (D-09-06 — TEN-06)

| Option | Description | Selected |
|--------|-------------|----------|
| Single dependsOn at the outer-K level | `poc-capsule-spoke` depends on `poc-capsule` with `wait: true` | |
| Two-arm dependsOn | Both `poc-capsule-spoke` outer K AND each per-tenant inner K depend on `poc-capsule` with `wait: true` | ✓ |
| HelmRelease-only dependsOn (Phase 8 D-08-07 inheritance) | Rely on Phase 8 chain; no new K-level dependsOn | |

**Selection rationale (auto-mode default):** TEN-06 contract literally says "Tenants Kustomization declares `dependsOn` chain on operator Kustomization with `wait: true`". Two arms cover BOTH the spoke-targeted Tenant CR apply (which needs CRDs registered) AND the per-tenant inner K reconcile (which needs the SAs registered as Tenant Owners). Single-arm option misses the per-tenant inner K case. HelmRelease-only inheritance is insufficient because the Tenant CR + per-tenant SA + per-tenant inner K are NEW Kustomization-level dependencies introduced in Phase 9.

---

## TEN-02 / TEN-03 Verifier Path (D-09-07)

| Option | Description | Selected |
|--------|-------------|----------|
| Mint a tenant kubeconfig in Phase 9, then `kubectl --kubeconfig=alpha.kubeconfig create namespace` | Pulls Phase 10 PROXY-01 forward into Phase 9 | |
| Use local cluster-admin context with `kubectl --as=alpha` impersonation | Native to local k3d kubeconfig; matches ROADMAP TEN-02 literal phrasing | ✓ |
| Skip TEN-02/03 verification in Phase 9 (defer to Phase 11) | Static-only contracts in Phase 9 | |

**Selection rationale (auto-mode default):** ROADMAP TEN-02 literally says `kubectl --as=alpha create namespace alpha-app1`. The local k3d cluster-admin kubeconfig has the impersonation privilege; the User identity `alpha` is registered as Tenant Owner via the multi-owner pattern (D-09-02). No need to mint a kubeconfig (Phase 10 PROXY-01) for Phase 9's positive-direction shape verification. Negative-direction tests (cross-tenant deny, etc.) are Phase 11 scope.

---

## Test Scaffolding Pattern (D-09-08)

| Option | Description | Selected |
|--------|-------------|----------|
| Repeat Phase 7/8 Wave 0 RED bats scaffold | Plan 09-00 lands all bats RED before any tenant YAML | ✓ |
| "Implement and test in same plan" anti-pattern | Tenant YAML + corresponding bats land together | |
| Live-bats only (skip static-contract bats) | Lighter-weight verification; accept risk | |

**Selection rationale (auto-mode default):** Phase 7/8 Nyquist-gate pattern is already-validated (Phase 7 39 tests across 8 files all green; Phase 8 10 bats GREEN per `passed_with_overrides`). Repeating is pure-win — no new risk, no new pattern to test. The "implement and test in same plan" anti-pattern is the documented v0.18 / v0.19 lint target.

---

## Plan Ordering (D-09-09)

| Option | Description | Selected |
|--------|-------------|----------|
| 4-plan structure (Wave 0 RED → spoke side → hub side → verifier) | Tenant content lands first, lockdown last (regression-isolated) | |
| 5-plan structure (Wave 0 RED → CapsuleConfig + spoke tenants → hub tenants → lockdown → verifier) | Lockdown isolated as its own plan with health-check rerun | ✓ |
| Single mega-plan | Everything in one plan; risky for atomic rollback | |

**Selection rationale (auto-mode default):** Lockdown patches are the dominant Phase 9 risk per STATE.md. Isolating them in their own plan (Plan 09-03) means atomic rollback is cheap if `task health-check` regression fires. Tenant content (Plans 09-01, 09-02) lands first, validating tenant reconcile path BEFORE the high-risk patch lands. Verifier (Plan 09-04) runs after lockdown to catch any cross-impact. Single mega-plan rejected because rollback granularity matters.

---

## Claude's Discretion

The following gray areas were intentionally NOT specified — planner/researcher should default to v0.18 / Phase 7/8 patterns and note the chosen approach in PLAN.md without re-asking:

- `task` surface extensions — none recommended (Flux-driven; verifier surface is bats + `task health-check`)
- HelmRelease values shape (values inline vs ConfigMap) — values inline (Phase 8 D-08 inheritance)
- Tenant CR `spec.resourceQuotas` and `spec.limitRanges` — minimal POC values (cpu: 4, memory: 8Gi, pods: 20 per tenant)
- Tenant CR `spec.storageClasses`, `ingressClasses`, `containerRegistries`, `nodeSelectors` — omit (allow-all defaults; Phase 11 may exercise via N7 if needed)
- `spec.networkPolicies` on Tenant CR — omit (avoids P43 too-permissive vs too-restrictive ambiguity)
- Per-tenant proxy-kubeconfig Secret name pattern — Phase 10 owns; Phase 9 uses spoke-capsule-kubeconfig transitionally
- Phase 9 verifier script wrapper — bats-only (no shell wrapper script)
- `task health-check` rerun timing within Plan 09-03 — TWO reruns (baseline pre-patch + regression post-patch)
- Reconcile loop noise tolerance — ≤2 reconcile cycles (≤10 min) before treating as failure (Phase 8 D-08 inheritance)

## Open Research Questions (D-09-03a — Plan 09-RESEARCH owns)

- **`kubeConfig.secretRef` under `--no-cross-namespace-refs`** — Flux v2.8.6 docs ambiguous on whether `kubeConfig.secretRef` is governed by the flag (documented scope is `sourceRef`, `decryption.secretRef`, `verify.secretRef`; `kubeConfig.secretRef` not in the list). Researcher MUST verify against kustomize-controller v2.8.x source. Fallback: mirror `spoke-capsule-kubeconfig` Secret into each tenant namespace via `scripts/register-poc-cluster.sh` extension. Default assumption: Flux exempts `kubeConfig.secretRef`; D-09-03 spec stands as written.

## Reviewed Todos (Not Folded)

- `2026-04-29-phase-7-gitleaks-planning-doc-allowlist.md` — `resolves_phase: 11` marker overrides keyword-match; owned by Phase 11 VAL-05.
- `2026-04-29-phase-7-hub-flux-observable-reconcile.md` — `resolves_phase: 8` marker overrides keyword-match; folded into Phase 8 verifier (08-CONTEXT D-08-09); Phase 8 close-out reported "fragile pass" that resolves naturally on Phase 11 first push.

## Deferred Ideas

True deferrals to later phases (already locked at milestone-open or by ROADMAP / REQUIREMENTS un-bundling):

- Tenant owner kubeconfigs minted via `scripts/poc/capsule/issue-tenant-kubeconfig.sh` → Phase 10 (PROXY-01..03)
- Tenant inner Kustomizations swap to per-tenant proxy-kubeconfigs → Phase 10
- Negative RBAC bats N1–N12 → Phase 11 (VAL-01)
- Capsule webhook failure / recovery → Phase 11 (VAL-02)
- Clean teardown via `task destroy-poc capsule` → Phase 11 (VAL-03)
- `task rebuild` SLO regression test → Phase 11 (VAL-04)
- One-shot history gitleaks scan post-Phase-10 first push → Phase 11 (VAL-05)
- Graduation ADR-008 → Phase 11 (VAL-06)
- `capsule-addon-fluxcd v0.2.3` trial → Phase 12 (OPTIONAL — gated)
- Tenant workload Deployments (e.g., alpha-app1 running an actual pod) → Phase 11 workload demonstration
- HA Capsule, OIDC, multi-spoke federation, less-privileged spoke SA → POST-v0.19 milestones

---

## Plan 09-03 Attempt 3 — Gap-Resolution Discussion (2026-04-30)

**Date:** 2026-04-30
**Mode:** `--auto --gaps` (post-rollback gap-resolution discussion before attempt-3 re-plan)
**Trigger:** Plan 09-03 has been atomically rolled back twice — attempt 1 (commits `899f2fe` → `9b6b3a5`) falsified RESEARCH §Gap 3's "flag scope is local-cluster only" prediction; attempt 2 (commits `7598cd8` + `cb9b00e` → `0feb191` + `cd1cf32`) falsified attempt-1's proposed mitigation (the `kustomize-controller` SA-name on spokes).
**Areas discussed:** 6 attempt-3-specific gap areas (A-F). Original D-09-XX decisions remain LOCKED.

---

## Gap A — Spoke SA Mitigation Hypothesis (PRIMARY)

| Option | Description | Selected |
|--------|-------------|----------|
| (a) `spec.serviceAccountName: flux-reconciler` on spoke Ks | Matches actually-existing SA on spoke (cluster-admin via CRB; self-impersonation safe) | ✓ |
| (b) Skip spoke DiD + narrow lockdown scope | Defeats P27 safety net for spoke Ks | |
| (c) Extend `register-spokes-for-flux.sh` to create `kustomize-controller` SA + CRB on each spoke | Out of scope — touches Phase 7 spoke-registration surface | |

**Selection rationale (auto-mode default):** Minimal-scope path with strongest evidence trail. `flux-reconciler` SA exists on each spoke (verified via `register-spokes-for-flux.sh:286`); CRB binds to cluster-admin (`:292`); kubeConfig token IS the SA's own token (`:303-309`). Self-impersonation under cluster-admin is RFC-compliant kubernetes behavior.

---

## Gap B — Pre-patch SA-existence Assertion

| Option | Description | Selected |
|--------|-------------|----------|
| (i) Add Task 0.5 explicit `kubectl get sa flux-reconciler` assertion on each spoke | Fail-fast guard against another premise-falsification | ✓ |
| (ii) Trust attempt-2 SUMMARY's verification | Saves one assertion but loses fail-fast guard | |

**Selection rationale (auto-mode default):** Cheap defense (one bats `run kubectl ... get sa` per spoke). Closes "did spoke-registration drift?" risk. Attempt 2's SA verification was exploratory (post-failure); attempt 3 makes it a structural pre-condition.

---

## Gap C — RESEARCH.md §Gap 3 Third Correction Block

| Option | Description | Selected |
|--------|-------------|----------|
| (i) Add CORRECTION 2 block to §Gap 3 documenting attempt-2 falsification | Cumulative falsification record per attempt-1 pattern | ✓ |
| (ii) Defer to verifier or leave 09-03-SUMMARY.attempt-2-rollback.md as the only record | Saves docs commit but loses cumulative correction trail | |

**Selection rationale (auto-mode default):** Pattern established in attempt 1 (CORRECTION 1 already in RESEARCH.md). Cumulative falsification record helps future re-planners. Concrete shape pre-drafted in `09-03-SUMMARY.attempt-2-rollback.md NEW Falsification Candidate` section.

---

## Gap D — Atomic Rollback Contract Update

| Option | Description | Selected |
|--------|-------------|----------|
| (i) Update plan's rollback step to "revert ALL plan commits to baseline" | Match contract to actually-executed pattern | ✓ |
| (ii) Keep "revert HEAD" + Rule 3 deviation as the formal pattern | Smaller plan-text delta but accepts known deviation | |

**Selection rationale (auto-mode default):** Attempt 2's rollback chain required 2 reverts (Rule 3 extension). Make rollback contract MATCH actual semantic ("revert all plan commits in reverse order until pre-Task-1 baseline restored") so executor doesn't need a Rule 3 deviation each time.

---

## Gap E — Hub-targeted K Coverage Scope

| Option | Description | Selected |
|--------|-------------|----------|
| (i) Add `serviceAccountName` to ALL Ks defensively | Expands scope beyond falsified path; introduces risk on un-tested Ks | |
| (ii) Add only to LOCAL-cluster-targeting Ks (no kubeConfig) | Doesn't fix the spoke falsification (cross-cluster) | |
| (iii) Match attempt 2's scope (spoke-apps, spoke-ml, capsule.yaml, flux-system K) with SA-name fix | Stays focused on falsified path; verifier catches unforeseen regressions | ✓ |

**Selection rationale (auto-mode default):** Scope discipline. capsule-spoke.yaml has `spec.kubeConfig` set but is NOT in attempt 1 or 2's failure path; defensively adding `serviceAccountName` could introduce a NEW failure mode. Wait for evidence (Plan 09-04 verifier task health-check) before expanding.

---

## Gap F — Pre-patch Live Experiment

| Option | Description | Selected |
|--------|-------------|----------|
| (i) Pre-patch single-spoke experiment (`flux-reconciler` on spoke-apps only, observe Ready=True) | Adds a third checkpoint between baseline and regression | |
| (ii) Plan-time research deep-dive into Flux v2.8.6 source for self-impersonation semantics | Already covered by RESEARCH.md attempt-1 correction | |
| (iii) Skip — Gap B's pre-patch SA assertion is sufficient | KISS — three checkpoints (Gap B + Task 1 + Task 5) is sufficient | ✓ |

**Selection rationale (auto-mode default):** Over-engineering. Gap B's SA-existence assertion + Task 1 pre-patch baseline + Task 5 post-patch regression already cover the failure surface. Adding a fourth checkpoint doesn't change rollback semantics.

---

## Plan 09-03 Attempt-3 Recommended Task Graph

| Task | Description | Status vs attempt 2 |
|------|-------------|---------------------|
| 0.5 | Pre-patch SA assertion: `kubectl get sa flux-reconciler` on each spoke (Gap B) | NEW |
| 1 | Pre-patch baseline `task health-check` exit 0 | preserved |
| 2 | Spoke DiD: `serviceAccountName: flux-reconciler` on `spoke-{apps,ml}.yaml` (Gap A) | CHANGED — was `kustomize-controller` |
| 3 | RESEARCH.md §Gap 3 + §Gap 11 — append CORRECTION 2 block (Gap C) | CHANGED — different content |
| 4 | FLUX PATCH SURFACE patches block + capsule.yaml escape hatch (D-09-05/05a) | preserved |
| 5 | Post-patch `task health-check` OR atomic-rollback chain (Gap D) | preserved (rollback contract sharpened) |

---

## Anti-patterns Surfaced (for the planner)

1. **"Defense-in-depth across the board" is FALSE for cross-cluster reconciles** — each K's `serviceAccountName` MUST match an SA on its TARGET cluster (hub: `kustomize-controller`; spoke-{apps,ml}: `flux-reconciler`; spoke-capsule tenant ns: `gitops-reconciler`).
2. **"Revert HEAD" as a literal contract is INSUFFICIENT** when a precondition task has been falsified — rollback must say "revert all plan commits to baseline" semantically.
3. **Pre-patch `task health-check` baseline is necessary but NOT sufficient** — attempt 2 had clean baseline and still failed because the falsified premise wasn't checkable from health-check alone.

---

*Phase: 09-tenants-flux-multi-tenancy-lockdown*
*Original discussion completed: 2026-04-29*
*Attempt-3 gap-resolution discussion completed: 2026-04-30*
