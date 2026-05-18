---
phase: 11-validation-graduation-adr-008
plan: 00

subsystem: testing
tags: [bats, capsule, flux, multi-tenancy, negative-rbac, push-gate, slo-regression, p27, kustomization]

# Dependency graph
requires:
  - phase: 09-tenants-and-impersonation
    provides: P27 invariant (every Flux Kustomization spec.serviceAccountName non-empty); D-09-08 lockdown contract; tenant-alpha + tenant-bravo home namespaces
  - phase: 10-tenant-owner-kubeconfigs-capsule-proxy-round-trip
    provides: scripts/poc/capsule/issue-tenant-kubeconfig.sh contract (mint-once setup_file pattern); proxy-05 LIST filter precedent for cross-tenant probe shape
  - phase: 07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc
    provides: KARYON POC MOUNT sentinel + ../pocs in clusters/hub-flux/flux-system/kustomization.yaml; poc-isolation-01-static.bats P31 lint
provides:
  - 16 Phase 11 bats files RED-by-design (Wave 0 Nyquist scaffold) covering VAL-01..05 falsification surface
  - 3 GREEN-at-landing static lints (negative-rbac anti-pattern lint, sentinel preservation, NEW p27 Flux Kustomization SA lint)
  - KARYON_PHASE11_STRICT_LIVE strict-mode contract (Pitfall 11-P6) for graduation-deciding runs that flip live-skip → FAIL
  - Standardized teardown command form `task destroy-poc -- capsule` (reviewer MEDIUM #11) embedded in 5+ literals across teardown-01 + teardown-03
  - Cross-tenant Flux Kustomization probe pattern (N9/N10 valid sourceRef) for negative-rbac multi-tenancy testing
affects: [11-01, 11-02, 11-03, 11-04, 11-05]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Wave 0 RED bats scaffold (D-09-08 / D-10-09 inheritance) — every executor task in later plans has a pre-existing automated falsifier before implementation lands"
    - "setup_file mint-once kubeconfig (D-11-07) — single tenant kubeconfig issued in setup_file, reused across all @tests in that bats file"
    - "Live-skip strict-mode (Pitfall 11-P6) — `_strict_skip` helper converts skip→FAIL when `KARYON_PHASE11_STRICT_LIVE=1` is set"
    - "Real-CRUD probe (D-11-05, anti P37 SAR cache flake) — assertions use real `kubectl get/create/delete` against tmpdir kubeconfigs, NOT `kubectl auth can-i`"
    - "Ordered live tests (HIGH #6) — when a 2nd @test depends on 1st @test's setup, MERGE into ordered @tests within one bats file rather than separate files (independent-by-default bats invariant violated by shared destroy invocation)"
    - "apiVersion-discriminating Flux-vs-kustomize-config Kustomization filter — `select(.kind == \"Kustomization\" and (.apiVersion | test(\"^kustomize.toolkit.fluxcd.io/\")))` to avoid false-positive on aggregator kustomization.yaml files"

key-files:
  created:
    - tests/bats/negative-rbac-01-cross-tenant-list.bats
    - tests/bats/negative-rbac-02-escalation.bats
    - tests/bats/negative-rbac-03-webhook-policy.bats
    - tests/bats/negative-rbac-04-bypass-and-flux.bats
    - tests/bats/negative-rbac-05-webhook-down.bats
    - tests/bats/negative-rbac-anti-pattern-lint-static.bats
    - tests/bats/p27-tenant-kustomization-sa-static.bats
    - tests/bats/push-gate-01-static-rbac-postbuild.bats
    - tests/bats/push-gate-02-static-capsuleconfig.bats
    - tests/bats/push-gate-03-static-tenant-ns-label.bats
    - tests/bats/push-gate-04-live-tenant-ns-flux-apply.bats
    - tests/bats/push-gate-05-static-gitleaks-allowlist.bats
    - tests/bats/teardown-01-static-script.bats
    - tests/bats/teardown-02-static-sentinel-preservation.bats
    - tests/bats/teardown-03-live-ordered.bats
    - tests/bats/slo-regression-live.bats
  modified: []

key-decisions:
  - "p27 lint apiVersion-discriminates Flux Kustomizations (kustomize.toolkit.fluxcd.io/) from kustomize-config aggregator Kustomizations (kustomize.config.k8s.io/) — Rule 1 fix landed inline against false-positive on clusters/hub-flux/pocs/kustomization.yaml aggregator"
  - "_strict_skip helper defined per-file (no shared loader) — keeps each live bats self-contained per Phase 7-10 inheritance"
  - "teardown-04 file NOT created — reviewer HIGH #6 merged its PVC strand mitigation behavior into teardown-03-live-ordered.bats as an ordered 2-@test sequence (independent bats files cannot share the destroy invocation)"

patterns-established:
  - "Wave 0 RED bats scaffold: 16 files land before any production code; later plans flip RED→GREEN deterministically with clear ownership map"
  - "Strict-mode live testing: Pitfall 11-P6 KARYON_PHASE11_STRICT_LIVE env var converts every skip into a FAIL signal during graduation-deciding ADR-008 runs, eliminating invisible 'pass' from absent live env"
  - "Anti-pattern lint at landing: GREEN-static @test asserts ZERO `kubectl auth can-i` literals across 5 negative-rbac files; SAR cache TTL flake (P37) cannot regress without lint failing"
  - "P27 lint at landing: GREEN-static @test walks clusters/hub-flux/pocs/ recursively and asserts every Flux Kustomization declares non-empty spec.serviceAccountName (apiVersion-discriminating); inheritance from Phase 9 D-09-08 contract"
  - "PVC strand precondition + invariant in ONE ordered bats file: @test 1 seeds the PVC, @test 2 runs destroy-poc + asserts cascade + sentinel preservation; inverse pattern was rejected (separate files cannot share destroy invocation)"

requirements-completed: [VAL-01, VAL-02, VAL-03, VAL-04, VAL-05]

# Metrics
duration: 8min
completed: 2026-05-06
---

# Phase 11 Plan 00: Wave 0 RED Bats Scaffold Summary

**16 Phase 11 bats files landed RED-by-design (3 GREEN at landing) covering VAL-01..05 falsification surface — Nyquist gate locked before any production code in Plans 11-01..04**

## Performance

- **Duration:** 8 min
- **Started:** 2026-05-06T01:59:39Z
- **Completed:** 2026-05-06T02:07:40Z
- **Tasks:** 2
- **Files modified:** 16 (all newly created)

## Accomplishments

- 6 negative-rbac bats files lock the cross-tenant + escalation + webhook + bypass + Flux + webhook-down probe surface (12 @tests + 1 anti-pattern lint @test) covering VAL-01 negative RBAC
- 5 push-gate bats files lock D-11-01..04 GitOps source-of-truth invariants (RBAC PostBuild patch, 3-group userGroups, namespace labels, live label assertion, file-specific gitleaks allowlist + anti-broad-regex)
- 3 teardown bats files lock D-11-10/11 destroy-poc.sh script-shape contract + sentinel preservation + ordered PVC-strand-mitigation live scenario
- slo-regression-live.bats locks 3 @tests for VAL-04 (rebuild < 230s + CID stable + Phase 7 P31 lint inheritance)
- p27-tenant-kustomization-sa-static.bats locks the Phase 9 D-09-08 contract at graduation time as a static lint walking the FULL clusters/hub-flux/pocs/ tree (vs. Phase 9's tenant-only dynamic grep)
- Anti-pattern enforcement: ZERO `kubectl auth can-i` literals across 5 negative-rbac source files (lint GREEN at landing)

## Task Commits

1. **Task 1: 6 negative-rbac bats files (Wave 0 RED + anti-pattern lint GREEN)** — `7964459` (test)
2. **Task 2: 10 push-gate/teardown/slo/p27 bats files (Wave 0 RED + 2 GREEN)** — `51c0ab1` (test)

## Files Created

### Negative RBAC (6 files; D-11-06 partition)
- `tests/bats/negative-rbac-01-cross-tenant-list.bats` — N1/N2/N3 cross-tenant pod LIST + cluster-wide LIST filter + secret read denials (3 @tests, RED)
- `tests/bats/negative-rbac-02-escalation.bats` — N4 ClusterRoleBinding cluster-scope escalation denied (1 @test, RED)
- `tests/bats/negative-rbac-03-webhook-policy.bats` — N5/N6/N7 prefix + quota + registry webhook denials; N6 has idempotent precondition cleanup (3 @tests, RED)
- `tests/bats/negative-rbac-04-bypass-and-flux.bats` — N8 direct apiserver bypass (TCP pre-check + negative TLS-failure assert); N9 valid cross-tenant sourceRef + cross-namespace keyword; N10 valid sourceRef + RBAC keyword + negative source-not-found (3 @tests, RED)
- `tests/bats/negative-rbac-05-webhook-down.bats` — N11 webhook-down probe with poll-loop on readyReplicas/endpoints (NOT bare sleep); N12 recovery probe (2 @tests, RED)
- `tests/bats/negative-rbac-anti-pattern-lint-static.bats` — D-11-05/P37 enforcement: ZERO `kubectl auth can-i` in 5 source files (1 @test, **GREEN at landing**)

### Push Gate (5 files)
- `tests/bats/push-gate-01-static-rbac-postbuild.bats` — D-11-01 spec.patches Role capsule-proxy:capsule-proxy + secrets create verb (2 @tests, RED)
- `tests/bats/push-gate-02-static-capsuleconfig.bats` — D-11-02 3-group userGroups in capsuleconfig.yaml (1 @test, RED)
- `tests/bats/push-gate-03-static-tenant-ns-label.bats` — D-11-03 alpha + bravo namespace.yaml capsule.clastix.io/tenant labels (2 @tests, RED)
- `tests/bats/push-gate-04-live-tenant-ns-flux-apply.bats` — D-11-03 live post-push label survival + cluster-admin Flux apply assertion with strict-mode (2 @tests, RED)
- `tests/bats/push-gate-05-static-gitleaks-allowlist.bats` — D-11-04-revised file-specific Phase 7 + 10 markdown literals + ASSERT ABSENCE of broad regex anti-regression + live gitleaks scan (3 @tests, RED)

### Teardown (3 files)
- `tests/bats/teardown-01-static-script.bats` — D-11-10/11 script-shape contract (existence + shebang + strict-mode + path pinning + 5-step canonical sequence + per-Kustomization suspend + PVC strand NS_LIST loop + sentinel preservation lint) (6 @tests, RED)
- `tests/bats/teardown-02-static-sentinel-preservation.bats` — KARYON POC MOUNT + ../pocs preservation in flux-system/kustomization.yaml (1 @test, **GREEN at landing**)
- `tests/bats/teardown-03-live-ordered.bats` — Ordered 2-@test sequence (HIGH #6 merge): @test 1 seeds synthetic Pod-bound PVC labeled in alpha-app1; @test 2 runs `task destroy-poc -- capsule` + asserts cascade + PVC absent + sentinel preserved (2 @tests, RED)

### SLO + P27 (2 files)
- `tests/bats/slo-regression-live.bats` — VAL-04 SLO regression (rebuild < 230s + CID stable + Phase 7 P31 lint inheritance) with KARYON_RUN_SLO_IN_CI override + KARYON_PHASE11_STRICT_LIVE strict-mode (3 @tests, RED)
- `tests/bats/p27-tenant-kustomization-sa-static.bats` — NEW per Suggestion #14: walks clusters/hub-flux/pocs/ recursively + asserts every Flux Kustomization (apiVersion-discriminated from kustomize-config aggregators) declares non-empty spec.serviceAccountName (1 @test, **GREEN at landing**)

## Decisions Made

- **p27 lint apiVersion discrimination (Rule 1 fix during Task 2):** the initial yq filter `select(.kind == "Kustomization")` correctly matched Flux Kustomizations, but ALSO matched `clusters/hub-flux/pocs/kustomization.yaml` — a kustomize-config (`kustomize.config.k8s.io/v1beta1`) aggregator that has no `spec.serviceAccountName` field. The lint was tightened to `select(.kind == "Kustomization" and (.apiVersion | test("^kustomize.toolkit.fluxcd.io/")))` to discriminate Flux from config-Kustomization at the apiVersion level. Without this fix, the GREEN-at-landing claim would have been false (the lint would always FAIL). Tracked under Deviations Rule 1 below.
- **_strict_skip helper defined per-file:** Per Phase 7-10 inheritance, each live bats file is self-contained — no shared bats loader. The 8 live bats files each define `_strict_skip` locally; refactoring to a shared helper was deliberately deferred to keep the Wave 0 RED scaffold uniform across plans.
- **teardown-04 NOT created:** Reviewer HIGH #6 identified that the originally-planned `teardown-04-live-pvc-strand-mitigation.bats` could not work as an independent bats file because it shared the `task destroy-poc -- capsule` invocation with teardown-03; running them independently meant the 2nd test had no namespace to seed the synthetic PVC. The merged ordered @tests in teardown-03-live-ordered.bats (precondition seed + action+invariants) preserves the falsifier intent without the cross-file ordering trap.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Tightened p27 lint apiVersion filter to exclude kustomize-config Kustomizations**
- **Found during:** Task 2 (verifying p27-tenant-kustomization-sa-static.bats GREEN-at-landing claim)
- **Issue:** The initial yq filter `select(.kind == "Kustomization")` matched both Flux Kustomizations (`apiVersion: kustomize.toolkit.fluxcd.io/v1`) AND the kustomize-config aggregator `clusters/hub-flux/pocs/kustomization.yaml` (`apiVersion: kustomize.config.k8s.io/v1beta1`). The aggregator has no `spec.serviceAccountName` field by design (it's a kustomize build manifest, not a Flux reconciliation contract), so the lint reported a false-positive "P27 VIOLATION" against it, breaking the GREEN-at-landing claim.
- **Fix:** Tightened the yq filter to `select(.kind == "Kustomization" and (.apiVersion | test("^kustomize.toolkit.fluxcd.io/")))` — discriminating Flux Kustomizations (the only kind that has a `spec.serviceAccountName` field and is bound by the P27 contract) from kustomize-config aggregators.
- **Files modified:** `tests/bats/p27-tenant-kustomization-sa-static.bats` (one yq filter line + accompanying head-comment explanation)
- **Verification:** `bats tests/bats/p27-tenant-kustomization-sa-static.bats` now reports `ok 1` (GREEN at landing). Manual yq sanity check confirmed only `capsule.yaml` and `capsule-spoke.yaml` Flux Kustomizations are now matched, with `kustomization.yaml` aggregator correctly excluded.
- **Committed in:** `51c0ab1` (Task 2 commit; the corrected lint and the corrected head-comment shipped together with the other 9 bats files)

---

**Total deviations:** 1 auto-fixed (1 Rule 1 bug)
**Impact on plan:** Necessary correctness fix to honor the GREEN-at-landing claim in success_criteria. Lint semantics unchanged — still enforces the Phase 9 D-09-08 P27 contract on every Flux Kustomization under clusters/hub-flux/pocs/. No scope creep.

## Issues Encountered

None additional beyond the deviation above. Live tests skipped cleanly (no spoke-capsule cluster reachable in this worktree environment), as expected by the Wave 0 RED-by-design contract.

## User Setup Required

None — no external service configuration required. All bats files are self-contained and live-skip cleanly when `kubectl --context=k3d-spoke-capsule cluster-info` is unreachable, unless `KARYON_PHASE11_STRICT_LIVE=1` is set (per Pitfall 11-P6) — in which case skips become FAILs to ensure live evidence collection during ADR-008-deciding runs.

## Next Phase Readiness

**Plans 11-01..04 unblocked.** Each downstream plan now has a deterministic falsification surface:
- **Plan 11-01 (push-gate fixes):** `bats tests/bats/push-gate-{01,02,03,05}-static-*.bats` flips RED→GREEN as D-11-01..04 land
- **Plan 11-02 (destroy-poc.sh + Taskfile entries):** `bats tests/bats/teardown-01-static-script.bats` flips RED→GREEN; `bats tests/bats/negative-rbac-05-webhook-down.bats` becomes runnable when `task fail-capsule-webhook` is wired
- **Plan 11-03 (tenant.yaml + Capsule resources):** N5/N6/N7 + N11/N12 flip RED→GREEN as tenant.yaml namespaceOptions.quota + containerRegistries land
- **Plan 11-04 (live verifier + first push):** `bats tests/bats/push-gate-04-live-tenant-ns-flux-apply.bats` + `bats tests/bats/teardown-03-live-ordered.bats` + `bats tests/bats/slo-regression-live.bats` runnable; ADR-008 disposition computed from full RED→GREEN delta
- **Plan 11-05 (ADR-008):** Human-judgment from accumulated bats evidence

**Carryover:** None new. Phase 7 carryover (gitleaks `kubeconfig-bearer-token` rule firing on Phase 7 + Phase 10 fixture-bearing markdown) is now empirically locked to the file-specific allowlist in push-gate-05; resolution is the responsibility of Plan 11-01.

**TDD Gate Compliance:** Plans 11-00 is `type: execute` (not `type: tdd`); RED/GREEN/REFACTOR commit gating does not apply at the plan level. The bats files themselves implement the RED scaffold for Plans 11-01..04 to flip GREEN.

## Self-Check: PASSED

Verification claims:
- 16 files landed at canonical paths under `tests/bats/`: VERIFIED (file-by-file existence check)
- All 16 parse cleanly via `bats --count`: VERIFIED (counts match expected: 3+1+3+3+2+1 + 2+1+2+2+3 + 6+1+2 + 3 + 1 = 36 total @tests)
- 3 GREEN-at-landing bats pass: VERIFIED (anti-pattern lint, sentinel preservation, p27 lint all `bats <file>` returns 0)
- ZERO `kubectl auth can-i` in 5 negative-rbac source files: VERIFIED (comment-stripped grep returns no matches)
- 8 live bats honor KARYON_PHASE11_STRICT_LIVE: VERIFIED (grep finds env var literal in each)
- All 16 use `load 'test_helper'`: VERIFIED (grep finds literal in each)
- Commit hashes exist in git log: `7964459` (Task 1), `51c0ab1` (Task 2) both VERIFIED via `git log --oneline --all`

---
*Phase: 11-validation-graduation-adr-008*
*Completed: 2026-05-06*
