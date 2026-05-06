---
phase: 11-validation-graduation-adr-008
plan: 01
subsystem: infra
tags: [flux, kustomization, postbuild-patch, capsule, capsuleconfig, gitleaks, multi-tenancy, push-gate]

# Dependency graph
requires:
  - phase: 07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc
    provides: ".gitleaks.toml kubeconfig-bearer-token rule + paths allowlist precedent (.env.example whole-file)"
  - phase: 08-capsule-install-helm-chart-source-spoke
    provides: "clusters/hub-flux/pocs/capsule.yaml outer K (D-08-12 split-paths, hub-targeted)"
  - phase: 09-tenants-flux-multi-tenancy-lockdown
    provides: "pocs/capsule/spoke/tenants/{alpha,bravo}/namespace.yaml (TEN-01 D-09-02 home namespace pattern); pocs/capsule/spoke/config/capsuleconfig.yaml (CapsuleConfiguration default singleton)"
  - phase: 10-tenant-owner-kubeconfigs-capsule-proxy-round-trip
    provides: "passed_with_overrides D-08-13 push-gate-deferred carryover (chart RBAC patch persistence; CapsuleConfiguration userGroups; tenant home namespace ownership)"
  - phase: 11-validation-graduation-adr-008/11-00
    provides: "Wave 0 RED bats scaffold (push-gate-01..05); MERGE-DEPENDENCY for live verification"

provides:
  - "D-11-01: Flux PostBuild patch on poc-capsule outer K extending Role capsule-proxy:capsule-proxy with [secrets get/create/update/patch] verbs (chart RBAC carryover for kube-webhook-certgen Job)"
  - "D-11-02: capsuleconfig.yaml userGroups inlines the canonical 3-group set (capsule.clastix.io, system:serviceaccounts, system:authenticated) -- matches Plan 10-02 live patch state"
  - "D-11-03: tenant alpha + bravo namespace.yaml carry inline metadata.labels.capsule.clastix.io/tenant=<name> (Capsule webhook bypass on cluster-admin Flux apply path)"
  - "D-11-04-revised: .gitleaks.toml [allowlist] paths gains 7 file-specific entries for the verified Phase 7 + Phase 10 fixture-bearing markdown files (NARROW per-file patterns -- NOT broad whole-tree planning regex per reviewer HIGH #3)"
  - "Anti-regression sentinel: broad whole-tree planning regex literal confirmed ABSENT from .gitleaks.toml (push-gate-05 @test 2 contract)"

affects:
  - 11-02 (POC teardown -- consumes the persistent state these edits land before push)
  - 11-03 (negative-rbac validation -- CapsuleConfiguration 3-group userGroups required for proxy LIST behavior)
  - 11-04 (push event -- HARD GATE on D-11-01 propagation via jq check; Pitfall 11-P1 escalation to capsule-spoke.yaml on RED)
  - 11-05 (verifier -- aggregates pass/fail from push-gate-01..05 into ADR-008 disposition)
  - 12 (capsule-addon-fluxcd OPTIONAL -- ADR-008 outcome ∈ {adopt, defer} required)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Flux v1 Kustomization spec.patches block with JSON6902 op:add at /rules/- to extend chart-rendered RBAC (Pattern 1 from 11-RESEARCH.md Pattern Catalog)"
    - "CapsuleConfiguration spec.userGroups multi-group canonical list (3 entries: clastix native + system:serviceaccounts + system:authenticated for SA-token-authenticated identity recognition)"
    - "Capsule tenant home namespace label (capsule.clastix.io/tenant=<name>) inline in repo YAML (assumes cluster-admin Flux apply bypasses Capsule webhook)"
    - "gitleaks .gitleaks.toml [allowlist] paths file-specific patterns (NARROW per-file allowlist -- NOT broad regex; intentional friction prevents broad-allowlist class of leak)"
    - "Anti-regression sentinel via grep -F absence-check on broad-pattern literal (push-gate-05 @test 2)"

key-files:
  created:
    - ".planning/phases/11-validation-graduation-adr-008/deferred-items.md (tracks pre-existing gitleaks finding in tests/bats/proxy-06-live-fixture.bats out of D-11-04-revised scope)"
  modified:
    - "clusters/hub-flux/pocs/capsule.yaml (D-11-01 PostBuild patch + Pitfall 11-P1 escalation note)"
    - "pocs/capsule/spoke/config/capsuleconfig.yaml (D-11-02 3-group userGroups expansion)"
    - "pocs/capsule/spoke/tenants/alpha/namespace.yaml (D-11-03 capsule.clastix.io/tenant=alpha label)"
    - "pocs/capsule/spoke/tenants/bravo/namespace.yaml (D-11-03 capsule.clastix.io/tenant=bravo label)"
    - ".gitleaks.toml (D-11-04-revised 7 file-specific allowlist patterns; reviewer HIGH #3)"

key-decisions:
  - "D-11-01 patch lands on clusters/hub-flux/pocs/capsule.yaml (hub-targeted outer K) per CONTEXT.md original; Plan 11-04 Task 3 owns empirical hard-gate via jq propagation check; Rule 3 escalation to capsule-spoke.yaml is verifier-time response, NOT preemptive replanning (per reviewer HIGH #2)"
  - "D-11-04-revised: 7 file-specific paths instead of broad whole-tree planning regex (per reviewer HIGH #3 -- broad pattern would hide the exact accidental-leak class VAL-05 catches)"
  - "Anti-regression sentinel: comment text explaining what was removed must NOT contain the broad regex literal (otherwise grep -F absence-check trips on the comment) -- comment rephrased to 'broad whole-tree planning-markdown regex'"
  - "deferred-items.md tracks pre-existing gitleaks finding in tests/bats/proxy-06-live-fixture.bats; out of D-11-04-revised scope (which targets PLANNING markdown specifically); resolution candidate forwarded to Plan 11-04 + VAL-05 push-gate hardening"

patterns-established:
  - "Pattern: Flux PostBuild patch on outer Kustomization extends chart-rendered RBAC -- pairs with empirical hard-gate at verifier time (jq check on live cluster Role) for Pitfall 11-P1 (silent-miss when target Role doesn't exist at kustomize-controller patch time)"
  - "Pattern: GitOps source-of-truth catch-up after imperative live patches -- repo YAML edits make plan 10-02 live state canonical (single source of truth: live cluster reads exactly like repo)"
  - "Pattern: Anti-regression sentinel via grep -F literal absence -- comment text near a removed pattern must NOT contain the literal substring (else absence-check trips on documentation)"
  - "Pattern: file-specific gitleaks path allowlist (NARROW per-file patterns -- one entry per provably-fixture-bearing file) -- intentional friction prevents broad-allowlist class of leak; new fixture-bearing files MUST add a new entry explicitly"

requirements-completed: [VAL-05]

# Metrics
duration: 4min
completed: 2026-05-06
---

# Phase 11 Plan 01: Push-gate persistent fixes (D-11-01..04-revised) Summary

**5 GitOps-source files updated to land Phase 10 D-08-13 push-gate-deferred carryovers + Phase 7 gitleaks planning-doc todo as canonical state before first push.**

## Performance

- **Duration:** ~4 min
- **Started:** 2026-05-06T02:00:30Z
- **Completed:** 2026-05-06T02:04:13Z
- **Tasks:** 2 (both committed atomically)
- **Files modified:** 5 (1 outer Kustomization, 1 CapsuleConfiguration, 2 namespace YAMLs, 1 gitleaks config)
- **Files created:** 1 (deferred-items.md tracking out-of-scope pre-existing finding)

## Accomplishments

- D-11-01: PostBuild patch on `clusters/hub-flux/pocs/capsule.yaml` extending Role `capsule-proxy:capsule-proxy` in `capsule-system` with `[secrets get/create/update/patch]` verbs so kube-webhook-certgen Job can write its output Secret on initial Flux reconcile (closes Phase 10 D-08-13 chart RBAC gap; Plan 10-01 staged the equivalent rule via `kubectl patch role` -- this carries it into the Flux-managed reconcile path).
- D-11-02: `pocs/capsule/spoke/config/capsuleconfig.yaml` `spec.userGroups` expands from 1 group (`capsule.clastix.io`) to 3 (`capsule.clastix.io`, `system:serviceaccounts`, `system:authenticated`); the GitOps source now matches the live cluster state Plan 10-02 patched imperatively.
- D-11-03: `pocs/capsule/spoke/tenants/{alpha,bravo}/namespace.yaml` carry inline `metadata.labels.capsule.clastix.io/tenant=<name>` labels (alpha=alpha, bravo=bravo); trusts cluster-admin Flux apply path bypasses Capsule's webhook prefix-violation check (Pitfall 11-P2 -- Plan 11-04 owns empirical verification).
- D-11-04-revised: `.gitleaks.toml [allowlist] paths` gains 7 file-specific entries for the verified Phase 7 + Phase 10 fixture-bearing markdown files (NOT the broad whole-tree planning regex per reviewer HIGH #3). Anti-regression sentinel ensures the broad regex literal stays absent.
- Phase 7 + Phase 9 + ADR-004 invariants preserved: `forceTenantPrefix: true`, `enableTLSReconciler: false`, namespace name pattern `tenant-<name>`, existing `^\.env\.example$` allowlist entry, `serviceAccountName: kustomize-controller` on poc-capsule outer K.

## Task Commits

Each task was committed atomically:

1. **Task 1: D-11-01 PostBuild patch on poc-capsule outer K** - `2e8746f` (feat)
2. **Task 2: D-11-02 + D-11-03 + D-11-04-revised push-gate persistent fixes** - `6a81a6a` (feat)
3. **(supplementary) Track pre-existing gitleaks finding** - `3cd0353` (docs -- creates deferred-items.md for out-of-scope finding in tests/bats/proxy-06-live-fixture.bats:43)

_Note: Plan 11-01 was not a TDD plan (the bats RED scaffolds live in Plan 11-00 / Wave 0). The plan's `tdd="true"` task attribute applies to per-task TDD inside the plan's lifecycle; here both tasks are GREEN-by-design once landed since the bats files inherit from Plan 11-00._

## Files Created/Modified

- `clusters/hub-flux/pocs/capsule.yaml` -- 25-line `spec.patches` block appended (JSON6902 op:add at /rules/- on Role capsule-proxy:capsule-proxy in capsule-system); cites D-11-01 + Pitfall 11-P1 + Phase 10 D-08-13 + reviewer HIGH #2 escalation note.
- `pocs/capsule/spoke/config/capsuleconfig.yaml` -- userGroups extended from 1 to 3 entries (capsule.clastix.io, system:serviceaccounts, system:authenticated); cites D-11-02 + Plan 10-02 live-patch context.
- `pocs/capsule/spoke/tenants/alpha/namespace.yaml` -- metadata.labels.capsule.clastix.io/tenant: alpha added; cites D-11-03 + Pitfall 11-P2.
- `pocs/capsule/spoke/tenants/bravo/namespace.yaml` -- metadata.labels.capsule.clastix.io/tenant: bravo added; cites D-11-03 + Pitfall 11-P2.
- `.gitleaks.toml` -- [allowlist] paths gains 7 file-specific entries for verified Phase 7 + Phase 10 fixture-bearing markdown; cites D-11-04-revised + reviewer HIGH #3 + anti-regression sentinel rationale.
- `.planning/phases/11-validation-graduation-adr-008/deferred-items.md` -- (NEW) tracks pre-existing 2-finding gitleaks issue in tests/bats/proxy-06-live-fixture.bats:43 (Phase 10 inheritance); resolution candidate forwarded to Plan 11-04 + VAL-05.

## Decisions Made

- **Anti-regression comment rephrasing (Rule 1 deviation):** The plan's `<action>` block specified a comment containing the literal broad regex pattern in backticks. The plan's `<verify>` step ALSO required `grep -F` absence-check of that exact literal. The two contradicted: with the comment as written, `grep -F` would trip on the comment itself, falsely failing the anti-regression check. Resolution: rephrase the comment to describe the broad pattern by NAME ("broad whole-tree planning-markdown regex") instead of by literal, and add an explicit sentinel-warning note to future editors of the file. The comment still cites D-11-04-revised + reviewer HIGH #3 + the verification mechanism.
- **Out-of-scope deferred finding (NOT a deviation -- scope boundary correctness):** During Task 2 verification, gitleaks live scan returned 2 findings in `tests/bats/proxy-06-live-fixture.bats:43`. This file pre-dates Plan 11-01 (Phase 10 inheritance). D-11-04-revised targets PLANNING markdown files specifically; expanding scope to test fixtures would exceed the reviewer HIGH #3 contract. Tracked in `deferred-items.md` for VAL-05 / Plan 11-04 push-gate hardening.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Anti-regression comment text trips its own absence-check**
- **Found during:** Task 2 (.gitleaks.toml verify step)
- **Issue:** The plan's `<action>` text for `.gitleaks.toml` included a comment "The original broad `^\.planning/.*\.md$` regex was rejected by reviewer..." -- the comment LITERALLY contains the broad-regex substring. The plan's `<verify>` step then ran `grep -F -- '^\.planning/.*\.md$' .gitleaks.toml` and required it to NOT match (anti-regression). With the comment as written, this check trips on the comment. The plan's action and verify text contradicted each other.
- **Fix:** Rephrased the comment to describe the broad pattern by NAME ("broad whole-tree planning-markdown regex") instead of by literal pattern. Added an explicit sentinel-warning note to the comment explaining the bats anti-regression check uses `grep -F` and would match a literal in a comment as much as in a paths entry. The comment still cites D-11-04-revised + reviewer HIGH #3 + Phase 7 + Phase 10 verified-fixture context.
- **Files modified:** `.gitleaks.toml` (comment block above the 7 file-specific paths)
- **Verification:** Re-ran `grep -F -- '^\.planning/.*\.md$' .gitleaks.toml` after edit; exit 1 (no match -- anti-regression PASS). All 7 file-specific literal patterns still present (07-00-PLAN, 07-RESEARCH, 07-REVIEW, 07-PATTERNS, 10-00-PLAN, 10-REVIEW, 10-PATTERNS). `gitleaks detect --no-git --source . --config .gitleaks.toml` parsed the TOML successfully.
- **Committed in:** `6a81a6a` (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 plan-internal contradiction).
**Impact on plan:** All 5 file edits land cleanly with all in-worktree acceptance criteria PASS; the deviation was a plan authoring oversight (action text and verify text disagreed) and the fix is purely cosmetic (rephrasing comment language). No scope creep; no semantic change to the allowlist; the bats anti-regression assertion still passes by design.

## Issues Encountered

- **Wave dependency mismatch (out-of-scope; resolved by orchestrator):** This Plan 11-01 worktree is based at `dabe015` (BEFORE Plan 11-00 has been merged from Wave 0). Plan 11-00 creates `tests/bats/push-gate-{01,02,03,04,05}-*.bats` files that this plan's `<verify>` step expects to invoke. The bats invocations (`bats tests/bats/push-gate-XX-*.bats`) cannot run in this worktree because the test files don't exist here. All other in-worktree verifications (yq schema checks, grep literal checks, anti-regression check) pass. The orchestrator merges Wave 0 and Wave 1 worktrees together; the bats verification will be exercised after merge. Documented as a Phase 11 wave-orchestration assumption rather than a Plan 11-01 deviation.
- **Pre-existing gitleaks finding in tests/bats/proxy-06-live-fixture.bats:** 2 findings on line 43 (Kubernetes kubeconfig with embedded bearer token). Phase 10 inheritance, NOT created by Plan 11-01. Out of D-11-04-revised scope (planning markdown specifically). Tracked in `.planning/phases/11-validation-graduation-adr-008/deferred-items.md` for VAL-05 / Plan 11-04 push-gate hardening.

## Threat Flags

None. The 5 file edits land within the threat-model scope already declared in `<threat_model>` (T-11-01-01 PostBuild patch privilege scope = mitigate; T-11-01-02 file-specific allowlist = mitigate; T-11-01-03 namespace label spoofing = accept). No new network endpoints, auth paths, file access patterns, or schema changes at trust boundaries beyond what the plan already declared.

## Pitfall Awareness Forwards

- **Pitfall 11-P1 (Plan 11-04 Task 3 hard gate):** D-11-01 PostBuild patch targets `Role capsule-proxy:capsule-proxy` in `capsule-system`. Flux PostBuild patches apply to kustomize-build output; the Role is rendered by helm-controller LATER on the spoke. If the empirical jq propagation check fails post-push, Plan 11-04 SUMMARY records the Rule 3 escalation: relocate this patch onto `clusters/hub-flux/pocs/capsule-spoke.yaml` (the SPOKE-TARGETED outer K with `spec.kubeConfig`). Disposition is downgraded to `passed_with_overrides` at best (NEVER `passed`) if the empirical check fails. Per reviewer HIGH #2, the empirical falsifier is a HARD GATE at Plan 11-04, not preemptively in this plan.
- **Pitfall 11-P2 (Plan 11-04 first-push live verification):** D-11-03 tenant namespace labels assume cluster-admin Flux apply path bypasses Capsule's webhook prefix-violation check. Capsule's webhook exempts cluster-admin / kube-system identities (Phase 9 P27 exemption applies to Flux's `flux-reconciler` SA on spoke-capsule per ADR-004 + Phase 9 D-09-03 transitional kubeConfig). If `push-gate-04-live-tenant-ns-flux-apply.bats` is RED post-push, Plan 11-04 records the Rule 3 escalation: operator-runbook `--as=alpha`/`--as=bravo` fallback for namespace creation.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Push-gate-{01,02,03,05} static contracts now have GREEN-by-design YAML/TOML state in this worktree; the bats invocations (Plan 11-00 Wave 0 deliverable) will exercise them after orchestrator merge.
- Push-gate-04 stays RED until Plan 11-04 push event (live tenant namespace Flux apply observation).
- Plan 11-02 (POC teardown) consumes this state directly: the pre-push state is now canonical GitOps source-of-truth.
- Plan 11-04 (push event) inherits the HARD-GATE on D-11-01 propagation (Pitfall 11-P1 jq check) and live verification of D-11-03 (Pitfall 11-P2 namespace label observation).
- Plan 11-05 (verifier / ADR-008) aggregates push-gate-01..05 disposition into ADR-008 outcome ∈ {adopt, defer, reject, replaced}.

## Self-Check: PASSED

Files claimed in Files Created/Modified verified to exist:

- `clusters/hub-flux/pocs/capsule.yaml` -- FOUND (modified)
- `pocs/capsule/spoke/config/capsuleconfig.yaml` -- FOUND (modified)
- `pocs/capsule/spoke/tenants/alpha/namespace.yaml` -- FOUND (modified)
- `pocs/capsule/spoke/tenants/bravo/namespace.yaml` -- FOUND (modified)
- `.gitleaks.toml` -- FOUND (modified)
- `.planning/phases/11-validation-graduation-adr-008/deferred-items.md` -- FOUND (created)

Commits claimed in Task Commits verified to exist:

- `2e8746f` (Task 1) -- FOUND in git log
- `6a81a6a` (Task 2) -- FOUND in git log
- `3cd0353` (deferred-items doc) -- FOUND in git log

Acceptance criteria self-check:

- yq eval '.spec.patches[0].target.kind' clusters/hub-flux/pocs/capsule.yaml = `Role` -- PASS
- yq eval '.spec.userGroups | length' capsuleconfig.yaml = `3` -- PASS
- yq eval '.metadata.labels."capsule.clastix.io/tenant"' alpha/namespace.yaml = `alpha` -- PASS
- yq eval '.metadata.labels."capsule.clastix.io/tenant"' bravo/namespace.yaml = `bravo` -- PASS
- All 7 file-specific allowlist literals (07-00-PLAN, 07-RESEARCH, 07-REVIEW, 07-PATTERNS, 10-00-PLAN, 10-REVIEW, 10-PATTERNS) present in .gitleaks.toml -- PASS
- Broad regex literal absent from .gitleaks.toml (anti-regression) -- PASS
- bats invocations (push-gate-01,02,03,05) -- DEFERRED to orchestrator post-merge (test files live in Plan 11-00 Wave 0 worktree)

---
*Phase: 11-validation-graduation-adr-008*
*Plan: 01*
*Completed: 2026-05-06*
