---
phase: 11
slug: validation-graduation-adr-008
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-05-05
---

# Phase 11 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bats v1.11.0 (already installed) |
| **Config file** | `tests/bats/test_helper` (Phase 7 inheritance) |
| **Quick run command** | `bats tests/bats/<area>-NN-static-*.bats` (per-file static) |
| **Full suite command** | `bats tests/bats/` (all bats; live @tests gated by setup_file probes) |
| **Estimated runtime** | ~30s static-only suite; ~5min full suite (live @tests including SLO regression task rebuild) |

---

## Sampling Rate

- **After every task commit:** Run the bats file(s) modified or created by the task (per Phase 7-10 inheritance)
- **After every plan wave:** Run `bats tests/bats/` for the full suite to catch cross-file regressions
- **Before `/gsd-verify-work`:** Full suite must be green (all RED bats from Wave 0 turned GREEN by their owning plan; live @tests skip cleanly when cluster down via D-11-13 BEFORE_CID="MISSING" pattern)
- **Max feedback latency:** ~30s for static-only loops; ~90s for live @tests including kubectl rollout waits

---

## Per-Task Verification Map

> The bats files Phase 11 creates and which D-11-XX decision + VAL requirement each maps to. Plan IDs are placeholder (planner assigns final IDs in step 8); the file names + grouping are locked per CONTEXT.md D-11-06.

| Bats file | Plan | Wave | Requirement | Decision | Test Type | Automated Command | File Exists | Status |
|-----------|------|------|-------------|----------|-----------|-------------------|-------------|--------|
| `tests/bats/negative-rbac-01-cross-tenant-list.bats` (N1, N2, N3) | 11-00 lands RED → 11-03 turns GREEN | 0 RED → 3 GREEN | VAL-01 | D-11-05, D-11-06, D-11-07 | bats live | `bats tests/bats/negative-rbac-01-cross-tenant-list.bats` | ❌ W0 | ⬜ pending |
| `tests/bats/negative-rbac-02-escalation.bats` (N4) | 11-00 → 11-03 | 0 RED → 3 GREEN | VAL-01 | D-11-05, D-11-06, D-11-07 | bats live | `bats tests/bats/negative-rbac-02-escalation.bats` | ❌ W0 | ⬜ pending |
| `tests/bats/negative-rbac-03-webhook-policy.bats` (N5, N6, N7) | 11-00 → 11-03 (with Tenant CR fixtures) | 0 RED → 3 GREEN | VAL-01 | D-11-05, D-11-06, D-11-07 + Claude's Discretion N6/N7 fixtures | bats live | `bats tests/bats/negative-rbac-03-webhook-policy.bats` | ❌ W0 | ⬜ pending |
| `tests/bats/negative-rbac-04-bypass-and-flux.bats` (N8, N9, N10) | 11-00 → 11-03 | 0 RED → 3 GREEN | VAL-01 | D-11-05..08 + N9/N10 tmpdir Kustomization fixtures | bats live | `bats tests/bats/negative-rbac-04-bypass-and-flux.bats` | ❌ W0 | ⬜ pending |
| `tests/bats/negative-rbac-05-webhook-down.bats` (N11, N12) | 11-00 → 11-03 (after fail-capsule-webhook lands) | 0 RED → 3 GREEN | VAL-01, VAL-02 | D-11-05..07 + D-11-09 mechanism | bats live | `bats tests/bats/negative-rbac-05-webhook-down.bats` | ❌ W0 | ⬜ pending |
| `tests/bats/negative-rbac-anti-pattern-lint-static.bats` | 11-00 (static — GREEN immediately) | 0 GREEN | VAL-01 (anti-flake) | D-11-05 enforcement | bats static | `bats tests/bats/negative-rbac-anti-pattern-lint-static.bats` | ❌ W0 | ⬜ pending |
| `tests/bats/push-gate-01-static-rbac-postbuild.bats` | 11-00 RED → 11-01 GREEN | 0 RED → 1 GREEN | VAL-05 | D-11-01 | bats static | `bats tests/bats/push-gate-01-static-rbac-postbuild.bats` | ❌ W0 | ⬜ pending |
| `tests/bats/push-gate-02-static-capsuleconfig.bats` | 11-00 RED → 11-01 GREEN | 0 RED → 1 GREEN | VAL-05 | D-11-02 | bats static | `bats tests/bats/push-gate-02-static-capsuleconfig.bats` | ❌ W0 | ⬜ pending |
| `tests/bats/push-gate-03-static-tenant-ns-label.bats` | 11-00 RED → 11-01 GREEN | 0 RED → 1 GREEN | VAL-05 | D-11-03 | bats static | `bats tests/bats/push-gate-03-static-tenant-ns-label.bats` | ❌ W0 | ⬜ pending |
| `tests/bats/push-gate-04-live-tenant-ns-flux-apply.bats` | 11-00 RED → 11-04 GREEN (post-push) | 0 RED → 4 GREEN | VAL-05 | D-11-03 falsifier (Pitfall 11-P2 empirical) | bats live | `bats tests/bats/push-gate-04-live-tenant-ns-flux-apply.bats` | ❌ W0 | ⬜ pending |
| `tests/bats/push-gate-05-static-gitleaks-allowlist.bats` | 11-00 RED → 11-01 GREEN | 0 RED → 1 GREEN | VAL-05 | D-11-04 | bats static | `bats tests/bats/push-gate-05-static-gitleaks-allowlist.bats` | ❌ W0 | ⬜ pending |
| `tests/bats/teardown-01-static-script.bats` | 11-00 RED → 11-02 GREEN | 0 RED → 2 GREEN | VAL-03 | D-11-10 script shape | bats static | `bats tests/bats/teardown-01-static-script.bats` | ❌ W0 | ⬜ pending |
| `tests/bats/teardown-02-static-sentinel-preservation.bats` | 11-00 RED → 11-02 GREEN | 0 RED → 2 GREEN | VAL-03 | D-11-10 sentinel + mount preservation | bats static | `bats tests/bats/teardown-02-static-sentinel-preservation.bats` | ❌ W0 | ⬜ pending |
| `tests/bats/teardown-03-live-ordered.bats` | 11-00 RED → 11-04 GREEN | 0 RED → 4 GREEN | VAL-03 | D-11-10 5-step canonical | bats live | `bats tests/bats/teardown-03-live-ordered.bats` | ❌ W0 | ⬜ pending |
| `tests/bats/teardown-04-live-pvc-strand-mitigation.bats` | 11-00 RED → 11-04 GREEN | 0 RED → 4 GREEN | VAL-03 | D-11-11 auto force-delete | bats live | `bats tests/bats/teardown-04-live-pvc-strand-mitigation.bats` | ❌ W0 | ⬜ pending |
| `tests/bats/slo-regression-live.bats` (4 @tests: rebuild < 230s, CID unchanged, health-check, P31 lint) | 11-00 RED → 11-04 GREEN | 0 RED → 4 GREEN | VAL-04 | D-11-13 + D-11-16 (P31 inheritance) | bats live | `bats tests/bats/slo-regression-live.bats` | ❌ W0 | ⬜ pending |

> Plan IDs above use the recommended Plan 11-00..11-04 mapping from CONTEXT.md "Plan ordering" section. Planner reshapes if necessary; the bats file names + grouping (5 files for negative-rbac per D-11-06; one slo-regression-live; per-area static/live split for push-gate and teardown) are LOCKED.

---

## Wave 0 Requirements

Wave 0 (Plan 11-00) lands all bats files RED-by-design (live @tests skip cleanly via setup_file probe; static @tests targeting yet-to-land artifacts naturally fail until later plans land them):

- [ ] `tests/bats/negative-rbac-01-cross-tenant-list.bats` — RED at landing (kubeconfigs not yet minted by setup_file in absence of Capsule/Tenant CRs)
- [ ] `tests/bats/negative-rbac-02-escalation.bats` — RED at landing
- [ ] `tests/bats/negative-rbac-03-webhook-policy.bats` — RED at landing (also requires Tenant CR fixture extensions for N6/N7, landed in Plan 11-03)
- [ ] `tests/bats/negative-rbac-04-bypass-and-flux.bats` — RED at landing
- [ ] `tests/bats/negative-rbac-05-webhook-down.bats` — RED at landing (also requires fail-capsule-webhook.sh, landed in Plan 11-02)
- [ ] `tests/bats/negative-rbac-anti-pattern-lint-static.bats` — GREEN at landing (static lint of ZERO `kubectl auth can-i` matches in negative-rbac source files; passes the moment all 5 negative-rbac files are committed)
- [ ] `tests/bats/push-gate-01-static-rbac-postbuild.bats` — RED at landing (greps clusters/hub-flux/pocs/capsule.yaml for PostBuild patch literal not yet present; turns GREEN when Plan 11-01 lands D-11-01 patch)
- [ ] `tests/bats/push-gate-02-static-capsuleconfig.bats` — RED at landing (greps capsuleconfig.yaml for 3-group userGroups; turns GREEN when Plan 11-01 lands D-11-02 edit)
- [ ] `tests/bats/push-gate-03-static-tenant-ns-label.bats` — RED at landing (greps namespace.yaml files for label; turns GREEN when Plan 11-01 lands D-11-03 edit)
- [ ] `tests/bats/push-gate-04-live-tenant-ns-flux-apply.bats` — RED at landing (post-push reconcile required; turns GREEN after Plan 11-04 push event)
- [ ] `tests/bats/push-gate-05-static-gitleaks-allowlist.bats` — RED at landing (greps .gitleaks.toml for path-allowlist literal; turns GREEN when Plan 11-01 lands D-11-04 edit)
- [ ] `tests/bats/teardown-01-static-script.bats` — RED at landing (greps for script existence + shape; turns GREEN when Plan 11-02 lands script)
- [ ] `tests/bats/teardown-02-static-sentinel-preservation.bats` — RED at landing (greps script for ABSENCE of clusters/hub-flux/flux-system/kustomization.yaml mutations; turns GREEN when Plan 11-02 lands script)
- [ ] `tests/bats/teardown-03-live-ordered.bats` — RED at landing (live execution required; turns GREEN after Plan 11-04 verifier)
- [ ] `tests/bats/teardown-04-live-pvc-strand-mitigation.bats` — RED at landing (synthetic PVC test; turns GREEN after Plan 11-04 verifier)
- [ ] `tests/bats/slo-regression-live.bats` — RED at landing (4 @tests: rebuild timing + CID unchanged + health-check + P31 inheritance; turns GREEN after Plan 11-04 verifier)

**Wave 0 install pattern:** Bats v1.11.0 already installed (verified by RESEARCH.md). No framework install. tests/bats/test_helper exists from Phase 7. Phase 11 contributes 16 new bats files (5 negative-rbac + 1 anti-pattern-lint + 5 push-gate + 4 teardown + 1 slo-regression).

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| ADR-008 outcome decision (adopt / defer / reject / replaced by ADR-009) | VAL-06 | Outcome is a human judgment based on bats evidence rubric (D-11-14); cannot be automated — only the *evidence* underlying the decision is automated | After Plan 11-04 produces 11-VERIFICATION.md, milestone owner reads the bats GREEN/RED counts + carryover state + SLO measurement, applies the D-11-14 evidence-bound rubric (ADOPT requires 12/12 N1-N12 + VAL-02..05 + zero open BLOCKER), and writes the outcome into ADR-008 Status field per Plan 11-05 |
| EKSDOC-01 frontmatter Status: Draft → Reviewed (D-11-15) | VAL-06 | The 4 targeted revision blocks (cert source, IRSA, proxy LIST scope, push-gate translation) require human synthesis of Phase 7-10 + Phase 11 evidence into prose | Plan 11-05 writer (human or agent following PLAN.md) reads the relevant bats outputs + ADR-008 rubric mapping, edits docs/capsule-on-eks.md per D-11-15 spec, and updates frontmatter |
| Push event itself (`git push origin main` for VAL-05) | VAL-05 | Pushes to origin/main are user-authorized (per CLAUDE.md global default — destructive/visible-to-others actions require user confirmation); the script + plan can prepare everything but the push is operator-initiated | After Plan 11-04 cleanup tasks (helm uninstall capsule-proxy + bats GREEN locally), operator runs `git push origin main`; CI gitleaks-scan + post-push history scan validate VAL-05 |
| Optional `task destroy-poc -- capsule --full` execution (CONTEXT.md `--full` flag) | VAL-03 | The `--full` flag actually deletes the k3d cluster — non-trivial destruction the operator should consciously invoke | Operator runs `task destroy-poc -- capsule --full` deliberately to reset cluster state; bats teardown-03 validates the `--full=false` (default) path; `--full=true` is operator-initiated |

---

## Validation Sign-Off

- [ ] All 16 Phase 11 bats files have `automated` verify (Wave 0 RED → later-plan GREEN sequence) per the Per-Task Verification Map above
- [ ] Sampling continuity: every plan that lands a bats file or a code surface owns its corresponding bats GREEN transition (no 3 consecutive tasks without automated verify — Phase 7-10 Wave-0-RED-then-flip-GREEN pattern enforces this naturally)
- [ ] Wave 0 covers all 16 bats files at landing time (RED-by-design or GREEN-static where the static check is satisfied at Wave 0 landing)
- [ ] No watch-mode flags (bats has no watch mode by design; tests are run on-demand per Phase 7-10 inheritance)
- [ ] Feedback latency: ~30s for per-file static bats; ~5min for full live suite including SLO regression `task rebuild` invocation
- [ ] `nyquist_compliant: true` set in frontmatter once executor confirms the Wave 0 RED scaffold + GREEN-flip sequence is complete and all 16 bats files are accounted for in plan task verifications

**Approval:** pending — flips to "approved YYYY-MM-DD" when Plan 11-04 verifier writes 11-VERIFICATION.md and the milestone owner confirms the rubric in 11-VERIFICATION.md matches expected GREEN counts per ADR-008's chosen outcome.
