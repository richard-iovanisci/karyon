---
phase: 8
slug: capsule-capsule-proxy-bare-minimum-install
status: final
nyquist_compliant: true
wave_0_complete: true
created: 2026-04-29
finalized: 2026-05-11
finalized_evidence: "Plan 08-00 Wave 0 RED bats scaffold (10 bats files: 5 static + 5 live, cluster-info gated; covering CAP-01/02/03 contracts + Pitfall 8 reframe + Pitfall 9 anti-pattern lint) became GREEN over Plans 08-01..08-04. 08-VERIFICATION.md reports status: passed_with_overrides with 10/10 must-haves verified (6 live-VERIFIED + 4 deferred-with-override); re-verification at 08-04 closed G-03 (cert source) + G-04 (architectural seam split-path) + WR-01..WR-04 (bats hardening). Post-fix evidence: D-08-13 push-gate-deferred items resolved by Plan 11-07 closeout at HEAD 8415ab66 (per 11-07-SUMMARY.md: both HelmReleases Ready=True; capsule operator alive on spoke; healthz HTTP 200). Nyquist sampling rate satisfied: every REQ-ID (CAP-01..03) has at least one bats falsifier in the Wave-0 scaffold turned GREEN."
---

# Phase 8 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Strategy adapted from `08-RESEARCH.md` §"Validation Architecture". Per-task entries are populated by the planner during plan generation.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bats-core 1.11.0 (pinned via `.tool-versions`; consistent with 271 v0.18 + Phase 7 tests) |
| **Config file** | None — bats discovers `*.bats` files in `tests/bats/` |
| **Quick run command** | `bats tests/bats/capsule-install-*-static-*.bats` (Phase 8 static-only; sub-second) |
| **Full suite command** | `bats tests/bats/capsule-install-*.bats` (Phase 8 full — live bats auto-skip if clusters unreachable; ~5–30s depending on cluster state) |
| **Estimated runtime** | ~30 seconds for Phase 8 full suite when clusters are up; sub-second for static-only |

---

## Sampling Rate

- **After every task commit:** Run `bats tests/bats/capsule-install-*-static-*.bats` (static-only; sub-second feedback)
- **After every plan wave:** Run `bats tests/bats/capsule-install-*.bats` (full Phase 8 — live bats auto-skip when clusters unreachable)
- **Before `/gsd-verify-work`:** Full project suite must be green: `bats tests/bats/`
- **Max feedback latency:** 30 seconds (live cluster state dependent)

---

## Per-Task Verification Map

> Populated by the gsd-planner during plan generation. Each task in every PLAN.md gets a row mapping its requirement, threat reference, expected secure behavior, and the bats command that verifies it.

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| _(planner fills in)_ | | | | | | | | | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Per `08-RESEARCH.md` §"Validation Architecture" → "Wave 0 Gaps", Plan 08-00 lands all of the following bats files RED before any HelmRelease yaml lands:

- [ ] `tests/bats/capsule-install-01-static-helmrelease.bats` — covers CAP-01 (operator HR shape) + CAP-02 (proxy HR shape including dependsOn anti-pattern)
- [ ] `tests/bats/capsule-install-02-static-ocirepo.bats` — covers CAP-01 + CAP-02 OCIRepository shape
- [ ] `tests/bats/capsule-install-03-static-values.bats` — covers CAP-01 + CAP-02 chart values (verified against `helm show values` output during research)
- [ ] `tests/bats/capsule-install-04-static-no-umbrella.bats` — D-08-01 anti-pattern lint (no `proxy.enabled: true`) + Pitfall 9 anti-grep (no `wait:` in `dependsOn` block)
- [ ] `tests/bats/capsule-install-05-static-kustomize.bats` — D-08-05 inner `pocs/capsule/kustomization.yaml` rewrite to `resources: [operator/, proxy/]`
- [ ] `tests/bats/capsule-install-06-live-helm.bats` — CAP-01 + CAP-02 live HelmRelease `Ready=True` observation (gated by cluster-info probe)
- [ ] `tests/bats/capsule-install-07-live-crds.bats` — CAP-03 live: ≥7 `capsule.clastix.io` CRDs (gated by cluster-info probe)
- [ ] `tests/bats/capsule-install-08-live-proxy-reachable.bats` — CAP-02 live NodePort 30443 reachability per RESEARCH OQ-1 reframe (TLS handshake succeeds; HTTP code in `[1-5][0-9][0-9]`)
- [ ] `tests/bats/capsule-install-09-live-adr-004.bats` — Domain boundary item #4 (no Flux on spoke-capsule)
- [ ] `tests/bats/capsule-install-10-live-flux-observable.bats` — Folded Todo carryover (outer `poc-capsule` Kustomization `Ready=True` against post-Phase-7 source revision)

*Existing infrastructure:*
- `tests/bats/test_helper` — shared loader (Phase 7 inheritance; no modification)
- bats-core 1.11.0 — pinned via `.tool-versions` (no install needed)
- v0.18 + Phase 7 regression bats reused verbatim: `poc-isolation-01-static.bats` (P31), `poc-mount-01-static.bats` (P40 / P18 invariant)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| First-time `flux reconcile source git` priming on cold cluster | CAP-01 / CAP-02 (operator's manual UAT walkthrough) | Bats live tests use retries with sleep; the cold-start prime is documented for the milestone owner's UAT walkthrough but is not a CI-gated requirement | Documented in `docs/poc-capsule.md` (Phase 8 may extend with a "What's installed" subsection per 08-CONTEXT.md `<code_context>` Integration Points). Manual: `flux reconcile source git flux-system --context k3d-hub-flux` then `flux reconcile kustomization poc-capsule -n flux-system --context k3d-hub-flux --with-source` |

*All Phase 8 success-criteria behaviors have automated bats verification.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references (the 10 bats files above)
- [ ] No watch-mode flags in any test commands
- [ ] Feedback latency < 30s for static (per-task); < 30s for full Phase 8 with clusters up (per-wave)
- [ ] `nyquist_compliant: true` set in frontmatter once planner populates the per-task map and confirms coverage

**Approval:** pending (planner populates the per-task map; `/gsd-plan-phase` checker step approves)
