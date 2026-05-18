---
phase: 11-validation-graduation-adr-008
plan: 02
subsystem: poc-scripts
tags: [bash, kubectl, flux, k3d, jq, taskfile, capsule, teardown, webhook-failure]

# Dependency graph
requires:
  - phase: 11
    provides: 11-00 lays the static-RED bats contracts (teardown-01-static-script.bats + teardown-02-static-sentinel-preservation.bats); these RED-by-design tests assert the per-Kustomization suspend literals + sentinel-preservation contract this plan satisfies. Wave 1 isolation: this worktree was based off the pre-11-00 commit, so the static teardown-01/02 bats files were not present at execution; their literal-grep contracts were verified inline in this plan's `<verify>` block instead. Orchestrator will run teardown-01/02 GREEN as a post-merge gate after wave 0 + wave 1 land in main.
  - phase: 9
    provides: D-09-04 Capsule labeling invariant — namespaces (NOT PVCs) carry `capsule.clastix.io/tenant=<name>`; this plan's destroy-poc.sh PVC enumeration honors that invariant via NS_LIST loop (reviewer MEDIUM #9).
  - phase: 7
    provides: P31 / D-12 isolation contract — POC scripts live under `scripts/poc/capsule/`, v0.18 scripts have ZERO references; this plan's 2 new scripts inherit and preserve that contract.
provides:
  - "scripts/poc/capsule/destroy-poc.sh — 5-step canonical teardown for spoke-capsule POC (D-11-10 + D-11-11) with reviewer HIGH #5 + MEDIUM #9 + MEDIUM #11 revisions baked in"
  - "scripts/poc/capsule/fail-capsule-webhook.sh — test-only failure simulation by scaling capsule-controller-manager to 0/1 (D-11-09)"
  - "Taskfile.yml top-level `fail-capsule-webhook` + `destroy-poc` entries with standardized `task X -- args` form (D-11-12 + reviewer MEDIUM #11)"
  - "tests/bats/repo-hygiene-02-taskfile.bats relaxed thin-wrapper regex to permit Taskfile v3 {{.CLI_ARGS}} idiom (Rule 3 deviation; thin-wrapper invariant preserved)"
affects: [11-03, 11-04]  # 11-03 negative-rbac-05 N11/N12 invokes `task fail-capsule-webhook`; 11-04 teardown-03 verifier invokes `task destroy-poc -- capsule [--full]`

# Tech tracking
tech-stack:
  added: []  # No new tools/libraries; all primitives (kubectl, flux, k3d, jq) already in .tool-versions.
  patterns:
    - "Per-Kustomization flux suspend (one literal invocation per name, NOT $k loop variable) so static grep contracts see fixed strings — reviewer HIGH #5(a)"
    - "Verify-suspend-state via kubectl get kustomization -o jsonpath='{.spec.suspend}' after each suspend invocation — catches silent flux CLI version skews; reviewer HIGH #5 + MEDIUM #11"
    - "warn-on-non-zero (NOT `|| true` swallow) — operator visibility into which suspend invocation failed; reviewer HIGH #5(b)"
    - "Explicit --context=k3d-spoke-capsule on every kubectl call in cluster-mutating sections — defense against ambient-context surprises; reviewer HIGH #5(c)"
    - "PVC enumeration via NS_LIST loop (enumerate labeled namespaces FIRST, then PVCs WITHIN each — drop -l label selector on PVC list because PVCs do NOT carry capsule.clastix.io/tenant per Phase 9 D-09-04; reviewer MEDIUM #9)"
    - "Standardized `task <name> -- args` form everywhere (Taskfile v3 {{.CLI_ARGS}} requires the `--` separator) — reviewer MEDIUM #11"

key-files:
  created:
    - scripts/poc/capsule/destroy-poc.sh
    - scripts/poc/capsule/fail-capsule-webhook.sh
  modified:
    - Taskfile.yml
    - tests/bats/repo-hygiene-02-taskfile.bats  # Rule 3 deviation: regex relax to accept {{.CLI_ARGS}} suffix

key-decisions:
  - "Unrolled the per-Kustomization suspend loop to explicit per-name invocations so the static teardown-01 bats grep contract sees fixed strings `flux suspend kustomization tenant-alpha`, `... tenant-bravo`, `... poc-capsule-spoke` (NOT a $k loop variable). The functional behavior is identical to the loop pattern shown in 11-PATTERNS.md; only the source-text shape changed to satisfy the verify-block contract."
  - "Relaxed tests/bats/repo-hygiene-02-taskfile.bats test 2 regex to accept an optional trailing ` {{.CLI_ARGS}}` token after `bash scripts/<path>.sh`. The thin-wrapper invariant is preserved because (a) the regex still requires `bash scripts/<path>.sh` as the prefix and (b) test 3 (no inline kubectl|docker|k3d|flux outside cmds:) is the second-line defense for inline invocations everywhere."

patterns-established:
  - "Pattern: `task <name> -- arg1 arg2` form documented in head comments + error strings everywhere (NOT `task <name> arg1 arg2`)"
  - "Pattern: post-suspend verify via kubectl get kustomization -o jsonpath='{.spec.suspend}' returns one of {true, false, absent}; emit pass/warn/info accordingly"
  - "Pattern: PVC enumeration walks NS_LIST (labeled namespaces) and lists PVCs WITHIN each; do NOT apply `-l capsule.clastix.io/tenant` selector to PVC list because PVCs don't carry the label"

requirements-completed: [VAL-02, VAL-03]

# Metrics
duration: 5m46s
completed: 2026-05-06
---

# Phase 11 Plan 02: spoke-capsule POC scripts (destroy-poc + fail-capsule-webhook) Summary

**2 net-new POC scripts (~244 lines combined) + 2 Taskfile entries that satisfy VAL-02 (webhook failure simulation) + VAL-03 (clean teardown) at the script-shape level, with reviewer HIGH #5 + MEDIUM #9 + MEDIUM #11 revisions baked in.**

## Performance

- **Duration:** 5m46s
- **Started:** 2026-05-06T02:00:26Z
- **Completed:** 2026-05-06T02:06:12Z
- **Tasks:** 2 / 2
- **Files modified:** 4 (2 created + 2 modified)

## Accomplishments

- **`scripts/poc/capsule/destroy-poc.sh` (183 lines, mode 0755):** 5-step canonical teardown sequence — Step 1 per-Kustomization flux suspend (tenant-alpha + tenant-bravo + poc-capsule-spoke, each as a literal invocation with verify-suspend-state), Step 2 delete Tenant CRs `alpha bravo`, Step 3 poll namespace cascade up to 90s with auto force-delete PVC finalizers after 60s via NS_LIST loop, Step 4 single-object suspend `poc-capsule` outer K with verify, Step 5 optional `--full` flag → `k3d cluster delete spoke-capsule`. Arg whitelist: `capsule` + optional `--full` only; unknown args fail-fast.
- **`scripts/poc/capsule/fail-capsule-webhook.sh` (61 lines, mode 0755):** kubectl-scale-deploy mechanism for webhook failure simulation; arg whitelist `[01]`; on recovery (1) polls rollout-status with --timeout=90s. Idempotent.
- **`Taskfile.yml`:** 2 new top-level POC entries (`fail-capsule-webhook` + `destroy-poc`) appended after `rebuild:` block with `(POC)` desc prefix + standardized `task <name> -- args` form per reviewer MEDIUM #11. Existing v0.18 task ordering preserved verbatim.
- **`tests/bats/repo-hygiene-02-taskfile.bats`:** Rule 3 deviation (auto-fix blocking issue) — relaxed test 2 regex to accept optional ` {{.CLI_ARGS}}` suffix, allowing the canonical Taskfile v3 variadic-pass-through idiom mandated by Plan 11-02 D-11-12. Thin-wrapper invariant preserved.
- **Sentinel preservation:** comment-stripped grep finds ZERO `flux-system/kustomization.yaml` references in destroy-poc.sh — the # KARYON POC MOUNT sentinel + ../pocs mount line are guaranteed verbatim post-teardown.
- **P31 inheritance preserved:** `bats tests/bats/poc-isolation-01-static.bats` stays GREEN (3/3 @tests) after the 2 new scripts land under `scripts/poc/capsule/` (isolated from v0.18 path).

## Task Commits

1. **Task 1: Create scripts/poc/capsule/destroy-poc.sh + fail-capsule-webhook.sh** — `a22530d` (feat)
2. **Task 2: Add task fail-capsule-webhook + task destroy-poc to Taskfile.yml + relax repo-hygiene-02 regex** — `c7a4097` (feat)

_Note: Task 1 was a TDD task in plan frontmatter (`tdd="true"`), but in this parallel-execution model the static-RED gate (`teardown-01-static-script.bats` + `teardown-02-static-sentinel-preservation.bats`) is owned by Plan 11-00 in wave 0 — by the time my GREEN implementation lands, those bats files will assert the literal-grep contract. The verify-block literal-grep checks were run inline in this plan to confirm the contract is satisfied._

## Files Created/Modified

- `scripts/poc/capsule/destroy-poc.sh` — Created (183 lines, mode 0755). 5-step teardown: per-Kustomization flux suspend with verify (Step 1) → delete Tenant CRs (Step 2) → poll namespace cascade with PVC strand mitigation (Step 3) → suspend operator outer K with verify (Step 4) → optional cluster delete (Step 5). All cluster-mutating kubectl calls explicitly use `--context=k3d-spoke-capsule`; flux suspend verify uses `--context=k3d-hub-flux`.
- `scripts/poc/capsule/fail-capsule-webhook.sh` — Created (61 lines, mode 0755). kubectl scale capsule-controller-manager to N replicas (validated [01]) with rollout-status wait on recovery.
- `Taskfile.yml` — Modified: appended 2 new top-level POC entries (`fail-capsule-webhook`, `destroy-poc`) after `rebuild:` block. Both invoke their scripts via `bash scripts/poc/capsule/<name>.sh {{.CLI_ARGS}}`. Existing v0.18 task ordering preserved verbatim.
- `tests/bats/repo-hygiene-02-taskfile.bats` — Modified: relaxed test 2 regex to accept optional ` {{.CLI_ARGS}}` suffix per Rule 3 deviation (see "Deviations from Plan" below).

## Decisions Made

1. **Per-Kustomization suspend pattern unrolled to explicit literal invocations.** The plan's `<context>` block (11-CONTEXT.md lines 137-145) showed the pattern as a `for k in tenant-alpha tenant-bravo poc-capsule-spoke; do flux suspend kustomization "$k" ...; done` loop — but the plan's `<verify>` block (Plan 11-02 lines 457-460) requires fixed-string greps `flux suspend kustomization tenant-alpha`, `... tenant-bravo`, `... poc-capsule-spoke`, which would fail against a `$k` loop variable. The fixed strings ARE the test contract (asserted by Plan 11-00's teardown-01-static-script.bats). I unrolled the loop into 3 explicit per-name blocks. Functional behavior is identical; only the source-text shape changed to satisfy the static contract.
2. **Use kubectl context names verbatim (no readonly variable).** Phase 7 fix-dns.sh uses `readonly POC_CTX="k3d-${POC_CLUSTER}"`. For destroy-poc.sh + fail-capsule-webhook.sh, I followed the verify-block contract verbatim (`kubectl --context=k3d-spoke-capsule ...` and `kubectl --context=k3d-hub-flux ...` as fixed strings) since the bats greps assert those exact literals. This minor stylistic divergence from fix-dns.sh is contract-driven, not preference-driven.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Per-Kustomization suspend loop unrolled to explicit per-name invocations**
- **Found during:** Task 1 (verify block run after first script write)
- **Issue:** The first script revision implemented the suspend pattern as a `for k in tenant-alpha tenant-bravo poc-capsule-spoke; do flux suspend kustomization "$k" -n flux-system; done` loop (matches the canonical pattern shown in 11-CONTEXT.md lines 137-145). But the plan's `<verify>` block (Plan 11-02 lines 457-460) requires fixed-string greps for `flux suspend kustomization tenant-alpha`, `... tenant-bravo`, `... poc-capsule-spoke` — the loop form contains `$k` not the literal name. The verify block IS the static contract enforced by Plan 11-00's `teardown-01-static-script.bats`.
- **Fix:** Unrolled the loop to 3 explicit per-name blocks. Each block performs (a) `flux suspend kustomization NAME -n flux-system` with warn-on-non-zero, (b) `kubectl --context=k3d-hub-flux get kustomization NAME -n flux-system -o jsonpath='{.spec.suspend}'` with pass/warn/info classification.
- **Files modified:** scripts/poc/capsule/destroy-poc.sh
- **Verification:** All 8 reviewer-revision literal-grep checks pass; `bash -n` + `shellcheck -x` both clean.
- **Committed in:** a22530d (Task 1 commit; the unroll happened in-place before commit, so the loop form never landed in git).

**2. [Rule 3 - Blocking] Relaxed `tests/bats/repo-hygiene-02-taskfile.bats` test 2 regex to accept Taskfile v3 `{{.CLI_ARGS}}` idiom**
- **Found during:** Task 2 (running `bats tests/bats/repo-hygiene-02-taskfile.bats` per the plan's verify block)
- **Issue:** The existing test 2 regex `^[[:space:]]*-[[:space:]]+bash scripts/[a-z0-9/-]+\.sh$` anchors at end-of-line, which rejects the canonical Taskfile v3 `{{.CLI_ARGS}}` variadic pass-through idiom (e.g. `bash scripts/poc/capsule/destroy-poc.sh {{.CLI_ARGS}}`). Plan 11-02 D-11-12 + reviewer MEDIUM #11 + 11-RESEARCH.md line 129 + 11-PATTERNS.md line 1116 all explicitly mandate the `{{.CLI_ARGS}}` form for the 2 new POC entries. Plan 11-02 acceptance criterion line 587 also asserts `bats tests/bats/repo-hygiene-02-taskfile.bats` should pass after the new entries land.
- **Fix:** Updated test 2 regex to `^[[:space:]]*-[[:space:]]+bash scripts/[a-z0-9/-]+\.sh([[:space:]]+\{\{\.CLI_ARGS\}\})?$` — the trailing token is now optional. Added a comment explaining the Phase 11 D-11-12 rationale and noting that the thin-wrapper invariant is preserved because (a) the regex still requires `bash scripts/<path>.sh` as the prefix and (b) test 3 (no inline kubectl|docker|k3d|flux outside cmds:) remains the second-line defense for inline invocations everywhere.
- **Files modified:** tests/bats/repo-hygiene-02-taskfile.bats
- **Verification:** All 3 @tests in repo-hygiene-02-taskfile.bats GREEN; full repo-hygiene-01..04 suite (26 @tests) GREEN; sibling Taskfile-touching static bats (destroy-rebuild-01-static, fix-coredns-01-static, health-check-01-static, poc-cluster-01-static, deploy-examples-01-static, register-spokes-01-static) all GREEN.
- **Committed in:** c7a4097 (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (both Rule 3 — blocking issues directly caused by current task's static contracts vs. canonical pattern mismatches; both essential to satisfy the plan's own verify block).
**Impact on plan:** No scope creep; both fixes are contract-driven (the plan's verify block + Plan 11-00's static bats files dictate the source-text shape).

## Issues Encountered

- **Plan dependency on wave 0 (`depends_on: ["11-00"]`) not satisfied at worktree base:** Plan 11-02 frontmatter declares `depends_on: ["11-00"]` and the plan's verify block calls `bats tests/bats/teardown-01-static-script.bats` + `bats tests/bats/teardown-02-static-sentinel-preservation.bats`. These bats files are owned by Plan 11-00 (wave 0). The worktree base (`dabe015 docs(11): replan with codex review feedback`) was the merge-base for wave-1 spawning, but Plan 11-00's outputs were not present in the base. Resolution: I executed all the `<verify>` block's literal-grep checks inline (which is the actual contract teardown-01/02 will enforce) and verified P31 + repo-hygiene-02 + 5 sibling Taskfile-touching static bats are all GREEN. The orchestrator merging wave 0 + wave 1 should run `bats tests/bats/teardown-01-static-script.bats` and `bats tests/bats/teardown-02-static-sentinel-preservation.bats` as a post-merge gate to confirm GREEN-by-construction.

## Deferred Verification (post-merge gate for orchestrator)

Plan 11-02 verify block also calls these 2 bats files which DO NOT EXIST in this worktree (they're owned by wave-0 Plan 11-00):

```bash
bats tests/bats/teardown-01-static-script.bats   # Owned by 11-00 (wave 0); RED-by-design until 11-02 lands
bats tests/bats/teardown-02-static-sentinel-preservation.bats  # Owned by 11-00 (wave 0)
```

After the orchestrator merges wave 0 (Plan 11-00) + wave 1 (Plans 11-01, 11-02, 11-03, etc.) into the integration branch, these 2 files SHOULD turn GREEN. The literal-grep contracts I verified inline (per-Kustomization suspend literals + sentinel-preservation lint) are the same contracts these bats files will assert.

## User Setup Required

None - no external service configuration required; both new scripts run against existing k3d-hub-flux + k3d-spoke-capsule contexts.

## Self-Check: PASSED

**Created files exist:**
- FOUND: scripts/poc/capsule/destroy-poc.sh (183 lines, mode 0755)
- FOUND: scripts/poc/capsule/fail-capsule-webhook.sh (61 lines, mode 0755)

**Modified files exist:**
- FOUND: Taskfile.yml (73 lines; added 2 new top-level entries)
- FOUND: tests/bats/repo-hygiene-02-taskfile.bats (52 lines; regex relaxed)

**Commits exist:**
- FOUND: a22530d (Task 1 — feat: land destroy-poc.sh + fail-capsule-webhook.sh)
- FOUND: c7a4097 (Task 2 — feat: add task fail-capsule-webhook + task destroy-poc to Taskfile.yml)

**Acceptance criteria from plan:**
- [x] `[ -x scripts/poc/capsule/destroy-poc.sh ]` succeeds
- [x] `[ -x scripts/poc/capsule/fail-capsule-webhook.sh ]` succeeds
- [x] `bash -n` clean on both scripts
- [x] shellcheck -x clean on both scripts
- [x] destroy-poc.sh contains literals: VAL-03, D-11-10, D-11-11, P31, ADR-004
- [x] destroy-poc.sh contains 5-step literals (per-Kustomization suspend: tenant-alpha, tenant-bravo, poc-capsule-spoke, poc-capsule outer K)
- [x] destroy-poc.sh contains PVC strand literals: NS_LIST=, finalizers, {"metadata":{"finalizers":null}}, --type=merge
- [x] destroy-poc.sh contains kubectl --context=k3d-hub-flux get kustomization + spec.suspend (verify-suspend per reviewer HIGH #5)
- [x] destroy-poc.sh contains task destroy-poc -- capsule (standardized form per reviewer MEDIUM #11)
- [x] destroy-poc.sh contains warn "could not (collect-rather-than-swallow per reviewer HIGH #5(b))
- [x] fail-capsule-webhook.sh contains literals: VAL-02, D-11-09, P31, kubectl --context=k3d-spoke-capsule scale deploy capsule-controller-manager, --timeout=90s
- [x] fail-capsule-webhook.sh contains task fail-capsule-webhook -- 0|1 (standardized form per reviewer MEDIUM #11)
- [x] sentinel preservation lint: comment-stripped grep finds NO mention of flux-system/kustomization.yaml in destroy-poc.sh
- [x] yq eval of Taskfile.yml fields all match plan acceptance values
- [x] bats tests/bats/repo-hygiene-02-taskfile.bats exits 0 (after Rule 3 regex relax)
- [x] bats tests/bats/poc-isolation-01-static.bats exits 0 (P31 inheritance preserved)
- [ ] bats tests/bats/teardown-01-static-script.bats exits 0 — DEFERRED to orchestrator post-merge gate (file owned by Plan 11-00 wave 0; not present in this worktree base)
- [ ] bats tests/bats/teardown-02-static-sentinel-preservation.bats exits 0 — DEFERRED to orchestrator post-merge gate (file owned by Plan 11-00 wave 0; not present in this worktree base)

## Next Phase Readiness

- **Plan 11-03 (negative-rbac validators):** `task fail-capsule-webhook -- 0|1` is wired and ready. N11/N12 bats can invoke it directly with --timeout=90s rollout-status guarantee on recovery.
- **Plan 11-04 (teardown-03 verifier):** `task destroy-poc -- capsule [--full]` is wired and ready. The 5-step canonical sequence + sentinel preservation are guaranteed by static contract; the live regression test in 11-04 will verify ordering + cluster-mutating side-effects.
- **No blockers** for downstream plans 11-03 + 11-04 + 11-05.

---
*Phase: 11-validation-graduation-adr-008*
*Completed: 2026-05-06*
