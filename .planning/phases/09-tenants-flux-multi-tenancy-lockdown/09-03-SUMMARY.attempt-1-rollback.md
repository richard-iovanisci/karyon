---
phase: 09-tenants-flux-multi-tenancy-lockdown
plan: 03
subsystem: infra
tags: [flux, multi-tenancy, lockdown, kustomize-controller, helm-controller, notification-controller, default-service-account, no-cross-namespace-refs, no-remote-bases, escape-hatch, regression-rollback, ten-05, d-09-05, d-09-05a, research-gap-correction]

# Dependency graph
requires:
  - phase: 09-tenants-flux-multi-tenancy-lockdown
    provides: Plan 09-02 — per-tenant inner Ks + Secret-mirror extension; provides the surface that the lockdown patches were meant to harden (TEN-04 P27 in place)
  - phase: 08-capsule-capsule-proxy-bare-minimum-install
    provides: D-08-12 split-path layout (clusters/hub-flux/pocs/{capsule,capsule-spoke}.yaml); D-08-13 push-gate deferral to Phase 11 VAL-05; capsule.yaml hub-targeted Phase 8 head comment block
  - phase: 04-spoke-registration
    provides: clusters/hub-flux/spokes/spoke-{apps,ml}.yaml with spec.kubeConfig set; cluster-admin SA tokens via remote kubeconfig Secrets
provides:
  - "ROLLED BACK — no surface delivered. Plan 09-03 attempted to land FLUX PATCH SURFACE patches block (4 patches: kustomize-controller 3 flags + helm-controller 2 flags + notification-controller 1 flag + flux-system K escape hatch) plus capsule.yaml escape hatch, but post-patch task health-check regression assertion FAILED."
  - "Concrete RESEARCH §Gap 3 + §Gap 11 correction observed live (formerly HIGH-confidence; now FALSIFIED): Flux v2.8.6 --default-service-account=default flag on kustomize-controller DOES apply to cross-cluster reconciles with spec.kubeConfig set. The kubeConfig principal does NOT override the SA fallback when serviceAccountName is empty."
  - "Re-plan path documented: Plan 09-03 must be re-planned to add spec.serviceAccountName: kustomize-controller to clusters/hub-flux/spokes/spoke-apps.yaml + spoke-ml.yaml BEFORE the lockdown patches can land safely. RESEARCH §Gap 11 line 693 explicitly recommended NOT modifying these files (to avoid scope creep), but that recommendation was based on the now-falsified Gap 3 prediction."
affects:
  - "Plan 09-03 RE-PLAN (REQUIRED) — Phase 9 cannot complete until lockdown patches land cleanly. Re-plan must expand scope to v0.18 spoke files (clusters/hub-flux/spokes/spoke-{apps,ml}.yaml — add spec.serviceAccountName: kustomize-controller to both)."
  - "Plan 09-04 (Phase 9 verifier) — currently BLOCKED on 09-03 re-plan landing successfully. Verifier inherits the regression gate via tenants-12-live-health-check.bats (calls task health-check)."
  - "RESEARCH §Gap 3 + §Gap 11 confidence rating REVISED from HIGH to FALSIFIED for the specific cross-cluster + empty-serviceAccountName case. Future planners must not rely on Gap 3's claim that --default-service-account flag scope is local-cluster-only."
  - "STATE.md Phase 9 Blockers/Concerns subsection (lockdown flag patches → high regression risk) — VALIDATED. The risk did materialize on first attempt; mitigation path (atomic rollback) worked exactly as designed."

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Atomic-rollback pattern via `git revert --no-edit HEAD` per CONTEXT.md Discretion §'Order of task health-check rerun' line 296 — falsifier-driven rollback at the FLUX PATCH SURFACE level"
    - "Suspend+apply test pattern (D-08-13 push-gate workaround) — flux suspend kustomization flux-system + kubectl kustomize | kubectl apply lets cluster-side state diverge from origin/main long enough to exercise the regression gate without violating the push-gate deferral"
    - "RESEARCH gap correction-on-falsifier — when live behavior contradicts a HIGH-confidence research claim, the correction is captured in SUMMARY frontmatter for downstream consumption (re-planner reads it before re-attempting)"

key-files:
  created:
    - "(NONE — plan rolled back; SUMMARY documents what was attempted + the failure mode)"
  modified:
    - "(NET-ZERO modifications post-rollback — Task 2 commit 899f2fe was atomically reverted by 9b6b3a5)"

key-decisions:
  - "RESEARCH §Gap 3 + §Gap 11 prediction FALSIFIED by live observation: --default-service-account=default flag on kustomize-controller applies to cross-cluster reconciles with spec.kubeConfig set when spec.serviceAccountName is empty. The flag falls through to `default` SA on the TARGET cluster (the spokes), causing forbidden errors on namespace patches. This is a Flux v2.8.6 behavior that contradicts both Gap 3 ('flag applies ONLY when spec.kubeConfig is unset') and Gap 11 line 693 ('v0.18 spoke-{apps,ml} use cluster-admin SA via kubeConfig — no impact')."
  - "Atomic rollback executed per plan Task 3 step 6 + CONTEXT.md Discretion §line 296: 'Failure on (2) → roll back patch atomically.' Commit 9b6b3a5 (`git revert --no-edit HEAD`) reverted Task 2 commit 899f2fe. NO fix-forward attempted (per plan's explicit instruction). Cluster restored to pre-Task-2 baseline (controllers without lockdown flags; flux-system K + capsule.yaml without spec.serviceAccountName); task health-check exit 0 post-rollback (19/19 pass)."
  - "Suspend+apply pattern adopted as the regression-gate exercise mechanism under D-08-13 push-gate deferral. The plan's Task 3 step 1 calls `flux reconcile kustomization flux-system` but that pulls from origin/main which doesn't have the un-pushed Plan 09-03 commit. To exercise the post-patch regression assertion, executor used `flux suspend kustomization flux-system` + `kubectl kustomize ... | kubectl apply` to land the patches in-cluster. After test (PASS or FAIL), executor unsuspended Flux to allow it to converge back to origin/main baseline (which has no lockdown patches yet, so converges cleanly)."
  - "Re-plan scope expansion documented: Phase 9 Plan 09-03 re-plan MUST expand scope to v0.18 spoke files (clusters/hub-flux/spokes/spoke-apps.yaml + spoke-ml.yaml) and add `spec.serviceAccountName: kustomize-controller` to both. RESEARCH §Gap 11 line 693 explicitly recommended NOT modifying these to avoid scope creep, but that recommendation rested on the now-falsified Gap 3 prediction. The defense-in-depth path (set explicit serviceAccountName on every Kustomization CR before lockdown lands) is the only safe path forward."

patterns-established:
  - "Pattern: Atomic-rollback via `git revert --no-edit HEAD` for FLUX PATCH SURFACE high-regression-risk plans — when post-patch regression assertion fails, the revert IS the contract-honoring outcome (NOT a fix-forward attempt). The annotation commit (Task 3 chore) records the failure mode + re-plan path for downstream consumers."
  - "Pattern: Suspend+apply for in-worktree exercise of bootstrap-managed surfaces under push-gate deferral — `flux suspend kustomization flux-system` + `kubectl kustomize | kubectl apply` lets executor verify FLUX PATCH SURFACE patches land + reconcile correctly without requiring a push to origin/main. After verification, `flux resume` lets the cluster converge back to origin/main baseline."
  - "Pattern: RESEARCH gap correction-on-falsifier — live observation that contradicts HIGH-confidence research claims is documented in SUMMARY frontmatter (key-decisions + tech-stack patterns) so future planners pick it up automatically. Future Phase 9 Plan 09-03 re-plan reads this SUMMARY and updates RESEARCH.md accordingly."

requirements-completed: []  # TEN-05 NOT completed — atomic rollback. Re-plan required.

# Metrics
duration: 7min
completed: 2026-04-30
---

# Phase 09 Plan 03: Hub Flux Multi-Tenancy Lockdown — REGRESSION DETECTED + ATOMIC ROLLBACK Summary

**Lockdown patches landed atomically (4 patches in FLUX PATCH SURFACE + capsule.yaml escape hatch) but post-patch task health-check regression FAILED with `User "system:serviceaccount:flux-system:default" cannot patch resource "namespaces"` on spoke-apps + spoke-ml — falsifying RESEARCH §Gap 3 + §Gap 11 line 693 claims. Atomic rollback executed per CONTEXT.md Discretion line 296. Re-plan required to expand scope to spoke-{apps,ml}.yaml.**

## Performance

- **Duration:** 7 min
- **Started:** 2026-04-30T04:24:16Z
- **Completed:** 2026-04-30T04:31:18Z
- **Tasks:** 3 (1 baseline-pass, 1 patch-attempt + auto-revert, 1 rollback-annotation)
- **Files modified (net):** 0 (Task 2's 2-file change atomically reverted by 9b6b3a5)

## Outcome

**Plan ROLLED BACK.** TEN-05 NOT completed. Phase 9 cannot advance past Plan 09-03 until a re-plan expands scope to v0.18 spoke files.

## Accomplishments

- **Pre-patch baseline assertion PASSED** — Phase 8 close-out + Plans 09-01/02 verified clean (19/19 health-check assertions; all 7 v0.18 sections green)
- **Lockdown patches landed cleanly in-cluster** — kustomize-controller restarted with all 3 lockdown flags; helm-controller with 2; notification-controller with 1; source-controller unchanged (correct per RESEARCH §Gap 2). flux-system Kustomization CR + poc-capsule Kustomization CR escape hatches confirmed live (`spec.serviceAccountName: kustomize-controller`). All 4 controllers reached `availableReplicas == replicas` on first poll (no CrashLoopBackOff per RESEARCH §Gap 2 line 235-236, falsifying that potential failure mode).
- **Post-patch regression detected within 1 minute** — `task health-check` exit 201 with spoke-ml + spoke-apps Ready=False (forbidden namespace patch by `default` SA on spoke). RESEARCH §Gap 11 line 693's prediction ("v0.18 spoke-{apps,ml} use cluster-admin SA via kubeConfig — no impact") is FALSIFIED.
- **Atomic rollback executed cleanly** — `git revert --no-edit HEAD` reverted Task 2 commit 899f2fe; cluster restored to pre-Task-2 baseline; `task health-check` exit 0 post-rollback (19/19 pass). NO fix-forward attempted (per plan's explicit instruction + CONTEXT.md Discretion line 296).
- **Re-plan path documented** — Plan 09-03 re-plan must expand scope to add `spec.serviceAccountName: kustomize-controller` (or equivalent) to `clusters/hub-flux/spokes/spoke-apps.yaml` + `clusters/hub-flux/spokes/spoke-ml.yaml`. The defense-in-depth path is the only safe path forward.

## Task Commits

Each task was committed atomically:

1. **Task 1: Pre-patch baseline `task health-check`** — `5c24af6` (chore — empty commit; assertion PASSED)
2. **Task 2: Apply lockdown patches atomically** — `899f2fe` (feat — 2 files, +64 lines; landed cleanly per static contracts)
3. **Auto-revert (Task 3 fallback path)** — `9b6b3a5` (Revert "feat(09-03): hub Flux multi-tenancy lockdown patches…"; -64 lines; per Task 3 step 6)
4. **Task 3: Post-patch regression FAILED — rollback annotation** — `6cdbfb2` (chore — empty commit documenting the failure mode + re-plan path)

**Plan metadata:** (forthcoming `docs(09-03)` final commit captures SUMMARY.md only)

## Files Created/Modified

**Net post-rollback: 0 source-file modifications.**

- `clusters/hub-flux/flux-system/kustomization.yaml` — modified by 899f2fe (added `# KARYON FLUX LOCKDOWN PATCHES` sentinel + `patches:` block with 4 patches), reverted by 9b6b3a5. Final state: identical to pre-Task-2 baseline (head comment block + KARYON SPOKES MOUNT + KARYON POC MOUNT + resources block only).
- `clusters/hub-flux/pocs/capsule.yaml` — modified by 899f2fe (added Phase 9 D-09-05a comment block + `serviceAccountName: kustomize-controller` to spec), reverted by 9b6b3a5. Final state: identical to pre-Task-2 baseline (Phase 8 D-08-12 head comment + spec without serviceAccountName).

## Decisions Made

### Pattern: Suspend+apply for D-08-13 push-gate deferral

The plan's Task 3 step 1 calls `flux reconcile kustomization flux-system --context=k3d-hub-flux` to trigger the post-patch reconcile that exercises the regression gate. But hub-flux's GitRepository points at `origin/main branch: main`, and Plan 09-03's Task 2 commit (and Plans 09-00, 09-01, 09-02 commits) are all un-pushed under D-08-13 deferral. So `flux reconcile` would just re-pull origin/main (which lacks the lockdown patches) and the regression gate would never exercise.

Executor adopted the suspend+apply pattern (Rule 3 — auto-fix blocking issue):
1. `flux suspend kustomization flux-system` — pause reconcile so direct edits aren't reverted
2. `kubectl kustomize clusters/hub-flux/flux-system/ | kubectl --context=k3d-hub-flux apply -f -` — render the patched FLUX PATCH SURFACE and apply it directly
3. Wait for controllers to restart with new args + escape hatches to take effect
4. Run `task health-check` (post-patch regression assertion)
5. On FAIL: `git revert --no-edit HEAD` + `flux resume kustomization flux-system` (Flux converges back to origin/main baseline cleanly because origin/main lacks the lockdown patches anyway, so there's no conflicting state to reconcile)

This pattern lets executor exercise the regression gate WITHOUT pushing to origin/main, preserving D-08-13 deferral intact.

### Atomic rollback via `git revert --no-edit HEAD` (NOT `--no-verify`)

Per parallel_execution context "For direct git commits: git commit --no-verify -m '…'" — but `git revert --no-verify` is NOT a valid revert option (revert subcommand doesn't accept `--no-verify`). The first rollback attempt failed with usage error; the corrected invocation `git revert --no-edit HEAD` succeeded. The plan's verify hook contract is satisfied because pre-commit hooks don't fire on `git revert` (the resulting commit is a metadata revert, not a fresh content commit subject to hook gating).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking issue] Adopted suspend+apply pattern under D-08-13 push-gate deferral**

- **Found during:** Task 3 step 1 (post-patch reconcile attempt)
- **Issue:** Plan's Task 3 step 1 calls `flux reconcile kustomization flux-system --context=k3d-hub-flux` assuming origin/main has the patches block. But D-08-13 explicitly defers push to Phase 11 VAL-05, so origin/main lacks Plan 09-03 commits and the reconcile would just re-pull the un-patched baseline. Without exercising the regression gate, the plan can't reach its <verify> contract.
- **Fix:** Used `flux suspend kustomization flux-system` to pause reconcile, then `kubectl kustomize ... | kubectl apply` to land patches directly. After regression test (PASS or FAIL path), used `flux resume` to converge cluster back to origin/main baseline (clean convergence because origin/main lacks lockdown patches → no state conflict).
- **Files modified:** None (operational pattern, no source file changes)
- **Verification:** Pre-suspend live state confirmed Flux self-reverted on first kubectl-apply attempt (confirming the bootstrap-managed surface gotcha). Post-suspend the patches landed cleanly + controllers restarted with new args. Post-resume the cluster converged back to baseline (verified by post-rollback `task health-check` exit 0).
- **Committed in:** N/A (operational pattern, no commit)

### Plan-driven Rollback (NOT a deviation — explicit fallback path)

**Atomic rollback was the plan's explicit Task 3 step 6 fallback path on regression detection.** The plan author anticipated this exact failure mode and documented the rollback path verbatim:

> "If post-patch task health-check FAILS:
> - DO NOT continue to Task 4.
> - Atomic rollback: revert the Task 2 commit:
>   ```bash
>   git revert --no-edit HEAD
>   ```"

Per CONTEXT.md Discretion §"Order of task health-check rerun" line 296: "Failure on (2) → roll back patch atomically." This is the explicit fallback path, NOT a deviation.

---

**Total deviations:** 1 auto-fixed (1 Rule 3 blocking — suspend+apply under D-08-13). Atomic rollback is explicit plan fallback path.

**Impact on plan:** Plan ROLLED BACK; TEN-05 NOT completed. Phase 9 advance blocked on re-plan landing.

## Issues Encountered

### Regression: spoke-apps + spoke-ml Ready=False post-lockdown (PRIMARY FINDING)

**Root cause:** Flux v2.8.6 `--default-service-account=default` flag on kustomize-controller applies to cross-cluster reconciles (with `spec.kubeConfig` set) when `spec.serviceAccountName` is empty. The flag falls through to the `default` SA on the TARGET cluster (the spokes), which has no permissions, so dry-run apply of namespaces fails with:

```
Namespace/gpu-smoke dry-run failed (Forbidden):
namespaces "gpu-smoke" is forbidden:
User "system:serviceaccount:flux-system:default" cannot patch resource
"namespaces" in API group "" in the namespace "gpu-smoke"
```

(Mirror error on spoke-apps targeting `karyon-spoke-apps` namespace.)

**Research falsification:** This contradicts RESEARCH §Gap 3 (line 244) and §Gap 11 line 693:

| Gap | Research claim | Live behavior | Verdict |
|-----|---------------|---------------|---------|
| §Gap 3 | "the flag applies ONLY when `spec.kubeConfig` is unset" | flag DID apply to spoke-{apps,ml} which have kubeConfig set | FALSIFIED |
| §Gap 11 line 693 | "v0.18 spoke-{apps,ml} use cluster-admin SA via kubeConfig — no impact" | spoke-{apps,ml} reconciled as `default` SA on TARGET cluster (no impact reasoning was based on incorrect Gap 3) | FALSIFIED |

The research's reasoning that the kubeConfig principal would override the SA fallback turns out to be incorrect for Flux v2.8.6. The flag takes precedence even when kubeConfig is set, IF serviceAccountName is empty.

**Re-plan path (REQUIRED):** Plan 09-03 re-plan MUST add `spec.serviceAccountName: kustomize-controller` (or equivalent) to BOTH:
- `clusters/hub-flux/spokes/spoke-apps.yaml`
- `clusters/hub-flux/spokes/spoke-ml.yaml`

This expands Phase 9 scope to v0.18 spoke files. RESEARCH §Gap 11 line 693 explicitly recommended NOT modifying these (to avoid scope creep), but that recommendation was based on the now-falsified Gap 3 prediction.

**Defense-in-depth path:** the only safe path forward is to add explicit `spec.serviceAccountName` to EVERY Kustomization CR before the lockdown patches land — including the v0.18 spokes. The re-plan should:
1. Add `spec.serviceAccountName: kustomize-controller` to spoke-apps.yaml + spoke-ml.yaml (NEW)
2. Apply the same FLUX PATCH SURFACE patches block + capsule.yaml escape hatch as Plan 09-03 attempted
3. Re-run pre-patch + post-patch health-check
4. Update RESEARCH.md to mark §Gap 3 + §Gap 11 line 693 as FALSIFIED with this SUMMARY as evidence

### Live cluster state mismatch under D-08-13 push-gate deferral

**Issue:** Plan's Task 3 step 1 (`flux reconcile kustomization flux-system`) assumes origin/main has the patches. Under D-08-13, all Phase 9 commits are un-pushed; origin/main is at `32e0b2fa` (Phase 8 close-out state). Without intervention, the regression gate would never exercise.

**Resolution:** Adopted suspend+apply pattern (Rule 3 deviation, see above). This pattern is now documented for any future plan that modifies the FLUX PATCH SURFACE under D-08-13 deferral.

## Static Bats Coverage

| Bats file | Pre-patch (Task 1) | Post-patch (Task 2) | Post-rollback (Task 3 final) |
|-----------|--------------------|---------------------|-----------------------------|
| `tests/bats/tenants-03-static-lockdown.bats` | 3/12 GREEN (sentinels) | **12/12 FULLY GREEN** | 3/12 GREEN (back to baseline RED) |
| `tests/bats/tenants-05-static-split-path.bats` | 3/4 GREEN (D-08-12 invariants) | **4/4 FULLY GREEN** | 3/4 GREEN (back to baseline) |

Static bats correctly track the rollback: post-rollback contract surface matches pre-Task-2 baseline. The bats files themselves were validated as accurate detectors of both the patch landing AND its rollback.

## RESEARCH Gap Falsification Record

For consumption by Plan 09-03 re-planner. Update `.planning/phases/09-tenants-flux-multi-tenancy-lockdown/09-RESEARCH.md` with this finding:

```markdown
## Gap 3 (REVISED post-Plan-09-03 falsification)

### CORRECTION: previous claim "flag applies ONLY when spec.kubeConfig is unset" is FALSIFIED.

Live observation in Flux v2.8.6 (Plan 09-03 attempt 1):
- Cross-cluster Kustomizations with spec.kubeConfig set BUT spec.serviceAccountName empty
- → kustomize-controller falls through to --default-service-account flag value (`default`) on the TARGET cluster
- → reconcile fails: "User system:serviceaccount:flux-system:default cannot patch resource"

The kubeConfig principal does NOT override the SA fallback when serviceAccountName is empty.

Mitigation: set explicit spec.serviceAccountName on EVERY Kustomization CR before --default-service-account lockdown lands.

Confidence: HIGH (live falsifier; cluster state captured in 09-03-SUMMARY.md commit chain).
```

## User Setup Required

None — no external service configuration required. The re-plan is a pure refactor of additional Kustomization CR yaml.

## Next Phase Readiness

**Phase 9 BLOCKED on Plan 09-03 re-plan.** Cannot advance to Plan 09-04 (Phase 9 verifier) until lockdown patches land cleanly with the spoke-side `spec.serviceAccountName` extension.

**Suggested orchestrator handling:**
1. Mark Plan 09-03 as ROLLED BACK in STATE.md / ROADMAP.md
2. Trigger Plan 09-03 re-plan via `/gsd-plan` with the falsifier record from this SUMMARY as input
3. Re-plan adds `spec.serviceAccountName: kustomize-controller` to spoke-apps.yaml + spoke-ml.yaml + applies same FLUX PATCH SURFACE patches block
4. Re-execute via `/gsd-execute-phase` — pre-patch baseline + post-patch regression should BOTH pass with the spoke-side defense in depth in place

**Forward-pointer:** Plan 09-03 re-plan owns RESEARCH.md update for §Gap 3 + §Gap 11 line 693 falsification record.

---
*Phase: 09-tenants-flux-multi-tenancy-lockdown*
*Plan: 03 (ROLLED BACK)*
*Completed: 2026-04-30*

## Self-Check: PASSED

Verifications performed:

- [x] Task 1 commit `5c24af6` exists in git log (`git log --oneline -5` confirms)
- [x] Task 2 commit `899f2fe` exists (atomic patch landing — 2 files, +64 lines)
- [x] Auto-revert commit `9b6b3a5` exists (revert of Task 2 — same 2 files, -64 lines; net zero)
- [x] Task 3 commit `6cdbfb2` exists (rollback annotation, empty)
- [x] `clusters/hub-flux/flux-system/kustomization.yaml` post-rollback: NO `patches:` block (yq `.patches` returns null)
- [x] `clusters/hub-flux/pocs/capsule.yaml` post-rollback: NO `spec.serviceAccountName` (yq returns null); `spec.kubeConfig` still null (D-08-12 invariant intact)
- [x] Post-rollback `task health-check` exit 0 (19/19 pass — full v0.18 baseline restored)
- [x] All 4 controllers post-rollback: avail=1 desired=1 (no CrashLoopBackOff residue)
- [x] Static bats tenants-03 + tenants-05 correctly track the rollback (back to pre-Task-2 RED state)
- [x] D-08-13 push-gate deferral honored throughout — no push to origin/main
