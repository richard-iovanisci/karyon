---
phase: 09-tenants-flux-multi-tenancy-lockdown
plan: 03
subsystem: infra
tags: [flux, multi-tenancy, lockdown, kustomize-controller, helm-controller, notification-controller, default-service-account, no-cross-namespace-refs, no-remote-bases, escape-hatch, regression-rollback, ten-05, d-09-05, d-09-05a, research-gap-correction, attempt-2-falsification, spoke-sa-mismatch]

# Dependency graph
requires:
  - phase: 09-tenants-flux-multi-tenancy-lockdown
    provides: Plan 09-02 — per-tenant inner Ks + Secret-mirror extension; provides the surface that the lockdown patches were meant to harden (TEN-04 P27 in place)
  - phase: 08-capsule-capsule-proxy-bare-minimum-install
    provides: D-08-12 split-path layout (clusters/hub-flux/pocs/{capsule,capsule-spoke}.yaml); D-08-13 push-gate deferral to Phase 11 VAL-05; capsule.yaml hub-targeted Phase 8 head comment block
  - phase: 04-spoke-registration
    provides: clusters/hub-flux/spokes/spoke-{apps,ml}.yaml with spec.kubeConfig set; flux-reconciler SA + cluster-admin CRB on each spoke (NOT kustomize-controller — Plan 09-03 RE-PLAN attempt 2 falsifier)
provides:
  - "ROLLED BACK (ATTEMPT 2) — no surface delivered. Plan 09-03 RE-PLAN attempted spoke defense-in-depth (Task 2: spec.serviceAccountName: kustomize-controller on spoke-{apps,ml}.yaml) + RESEARCH falsification record (Task 3) + FLUX PATCH SURFACE patches block (Task 4: kustomize/helm/notification flags + flux-system K escape hatch + capsule.yaml escape hatch). Post-patch task health-check FAILED with NEW failure mode different from attempt 1 (forbidden namespace patch by 'kustomize-controller' SA on spoke target cluster — kustomize-controller SA does NOT exist on spoke-{apps,ml,capsule} clusters; only flux-reconciler SA has cluster-admin via flux-reconciler-cluster-admin CRB)."
  - "RESEARCH.md §Gap 3 + §Gap 11 line 693 FALSIFICATION RECORD COMMITTED (Task 3 commit 7cd0b92) — this commit is KEPT post-rollback (the original §Gap 3 prediction is still falsified; the falsification record itself remains valid evidence for next-attempt re-planner)."
  - "NEW FALSIFICATION CANDIDATE for next-attempt re-plan: Plan 09-03 RE-PLAN's Task 2 assumed spoke clusters have a 'kustomize-controller' SA with cluster-admin permissions. ASSUMPTION FALSIFIED: spoke clusters (k3d-spoke-{apps,ml}) only have 'flux-reconciler' SA with cluster-admin (registered by scripts/register-spokes-for-flux.sh; ClusterRoleBinding 'flux-reconciler-cluster-admin' → 'cluster-admin'). The defense-in-depth proposal in attempt 2's plan was based on an unverified premise about spoke cluster SAs."
  - "Re-plan path documented: Phase 9 Plan 09-03 must be re-planned (ATTEMPT 3) using one of three mitigation hypotheses: (a) spec.serviceAccountName: flux-reconciler on spoke Ks (matches actually-existing SA); (b) skip defense-in-depth on spoke Ks entirely + re-investigate why kubeConfig token's principal isn't honored when serviceAccountName is empty; (c) extend scripts/register-spokes-for-flux.sh to create kustomize-controller SA + CRB on each spoke."
affects:
  - "Plan 09-03 RE-PLAN (REQUIRED, ATTEMPT 3) — Phase 9 cannot complete until lockdown patches land cleanly. Re-plan must address spoke SA naming mismatch."
  - "Plan 09-04 (Phase 9 verifier) — currently BLOCKED on 09-03 attempt 3 re-plan landing successfully. Verifier inherits the regression gate via tenants-12-live-health-check.bats (calls task health-check)."
  - "RESEARCH §Gap 3 confidence rating: original FALSIFICATION (from attempt 1) STANDS — kustomize-controller --default-service-account fallback DOES apply to cross-cluster reconciles. NEW falsification (this attempt): the proposed mitigation (set serviceAccountName: kustomize-controller on spoke Ks) does NOT work because kustomize-controller SA doesn't exist on spoke clusters."
  - "STATE.md Phase 9 Blockers/Concerns subsection (lockdown flag patches → high regression risk) — VALIDATED AGAIN. The risk materialized on attempt 2 with a different failure mode; mitigation path (atomic rollback) worked but required 2 reverts (Task 4 + Task 2) instead of 1."

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Atomic-rollback pattern via `git revert --no-edit HEAD` per CONTEXT.md Discretion §'Order of task health-check rerun' line 296 — falsifier-driven rollback at the FLUX PATCH SURFACE level. Attempt 2 EXTENSION: when a single revert doesn't restore baseline (because Task 2's premise was itself falsified), the rollback expands to include Task 2's revert as well. The plan's literal 'revert HEAD' instruction was insufficient — Rule 3 deviation: revert chain extended to 2 commits to actually restore baseline (per the plan's success criteria 'baseline restored')."
    - "Suspend+apply test pattern (D-08-13 push-gate workaround) — flux suspend kustomization flux-system + kubectl kustomize | kubectl apply lets cluster-side state diverge from origin/main long enough to exercise the regression gate without violating the push-gate deferral. Worked exactly as designed in attempt 2."
    - "RESEARCH gap correction-on-falsifier — when live behavior contradicts a HIGH-confidence research claim, the correction is captured in SUMMARY frontmatter for downstream consumption (re-planner reads it before re-attempting). Attempt 2 EXTENSION: when a re-plan's MITIGATION is itself falsified, the new SUMMARY captures the new falsification candidate (Plan 09-03 RE-PLAN Task 2's spoke-SA-name assumption) for the next-attempt re-planner."

key-files:
  created:
    - "(NONE — plan rolled back; SUMMARY documents what was attempted + the failure mode)"
  modified:
    - ".planning/phases/09-tenants-flux-multi-tenancy-lockdown/09-RESEARCH.md (Task 3 commit 7cd0b92 — KEPT; FALSIFIED correction blocks for §Gap 3 + §Gap 11 line 693)"
    - "(Task 2 commit 7598cd8 + Task 4 commit cb9b00e — REVERTED post-rollback; net-zero modifications to clusters/hub-flux/spokes/spoke-{apps,ml}.yaml + clusters/hub-flux/flux-system/kustomization.yaml + clusters/hub-flux/pocs/capsule.yaml)"

key-decisions:
  - "NEW FALSIFICATION (attempt 2): Plan 09-03 RE-PLAN's Task 2 assumed `serviceAccountName: kustomize-controller` would work as defense-in-depth on spoke Kustomization CRs. Live observation contradicts: spoke clusters (k3d-spoke-{apps,ml}) have only `flux-reconciler` SA with cluster-admin (registered by scripts/register-spokes-for-flux.sh), not `kustomize-controller`. When Flux v2.8.6 sees BOTH spec.kubeConfig + spec.serviceAccountName on a Kustomization, it impersonates the named SA on the TARGET cluster. Setting serviceAccountName: kustomize-controller targets a non-existent SA on the spoke, causing immediate forbidden errors regardless of whether the lockdown patches are applied."
  - "Atomic rollback executed per plan Task 5 step 7 + CONTEXT.md Discretion §line 296: 'Failure on (2) → roll back patch atomically.' Required 2 reverts (Task 4 commit cb9b00e then Task 2 commit 7598cd8) to actually restore baseline — Rule 3 deviation extending the plan's literal 'revert HEAD' instruction. NO fix-forward attempted (per plan's explicit instruction). Cluster restored to pre-Task-2 baseline; task health-check exit 0 post-rollback (19/19 pass)."
  - "Task 3 (RESEARCH.md falsification record commit 7cd0b92) KEPT post-rollback — the original §Gap 3 prediction (from attempt 1) is still falsified, and that falsification record is independent valid evidence for downstream consumers. Only the proposed MITIGATION in attempt 2 (set serviceAccountName: kustomize-controller on spoke Ks) was falsified, not the original prediction."
  - "Suspend+apply pattern (D-08-13 push-gate workaround) confirmed working as designed in attempt 2 — `flux suspend kustomization flux-system` + `kubectl kustomize | kubectl apply` lets cluster diverge from origin/main long enough to exercise the regression gate. After rollback, `flux resume` converged cluster back to origin/main baseline (32e0b2fa) cleanly."
  - "Re-plan scope expansion documented: Phase 9 Plan 09-03 ATTEMPT 3 must address spoke SA naming mismatch. Three candidate hypotheses: (a) use spec.serviceAccountName: flux-reconciler on spoke Ks (matches actually-existing SA, but planner must verify the impersonation chain works through kubeConfig); (b) skip spoke-side defense-in-depth + re-investigate the §Gap 3 falsification with a different mitigation (e.g., NOT setting --default-service-account=default on kustomize-controller, or only narrowing it to local-cluster K targets via OpenAPI patch selectors); (c) extend scripts/register-spokes-for-flux.sh to create a 'kustomize-controller' SA + cluster-admin CRB on each spoke (extends infrastructure scope significantly — out of scope for one plan)."

patterns-established:
  - "Pattern: Atomic-rollback via `git revert --no-edit HEAD` for FLUX PATCH SURFACE high-regression-risk plans — when post-patch regression assertion fails, the revert IS the contract-honoring outcome (NOT a fix-forward attempt). EXTENSION (this attempt): when a re-plan's PRECONDITION task (here: Task 2 spoke DiD) is itself based on a falsified premise, the rollback expands to revert the precondition commit too. The literal 'revert HEAD' is the floor; the actual contract is 'restore baseline'. Document the extension as a Rule 3 deviation."
  - "Pattern: Suspend+apply for in-worktree exercise of bootstrap-managed surfaces under push-gate deferral — `flux suspend kustomization flux-system` + `kubectl kustomize | kubectl apply` lets executor verify FLUX PATCH SURFACE patches land + reconcile correctly without requiring a push to origin/main. After verification (PASS or FAIL path), `flux resume` lets the cluster converge back to origin/main baseline. Worked identically in both attempts 1 and 2."
  - "Pattern: RESEARCH gap correction-on-falsifier remains separable from rollback — Task 3 RESEARCH.md update is a docs commit, NOT load-bearing on the FLUX PATCH SURFACE state. It survives rollback because the falsification it documents (original §Gap 3 prediction from attempt 1) is independent of attempt 2's NEW falsification (Task 2's spoke-SA-name assumption). Two falsifications now stand: the original §Gap 3 prediction AND the proposed mitigation hypothesis."

requirements-completed: []  # TEN-05 NOT completed — atomic rollback. Re-plan (attempt 3) required.

# Metrics
duration: 8min
completed: 2026-04-30
---

# Phase 09 Plan 03 RE-PLAN ATTEMPT 2: Hub Flux Multi-Tenancy Lockdown — REGRESSION DETECTED + ATOMIC ROLLBACK Summary

**Spoke defense-in-depth landed (Task 2 commit 7598cd8) + RESEARCH falsification record committed (Task 3 commit 7cd0b92) + FLUX PATCH SURFACE patches + capsule.yaml escape hatch landed atomically (Task 4 commit cb9b00e), but post-patch task health-check FAILED with NEW failure mode: spoke-{apps,ml} reconciles fell through to `system:serviceaccount:flux-system:kustomize-controller` SA on TARGET cluster (which does NOT exist on spoke clusters; only `flux-reconciler` SA has cluster-admin). The plan's Task 2 spoke defense-in-depth premise (that spokes have a `kustomize-controller` SA) is FALSIFIED. Atomic rollback required 2 reverts (Task 4 + Task 2) to actually restore baseline. RESEARCH.md falsification record (Task 3) KEPT post-rollback. Re-plan ATTEMPT 3 required to address spoke SA naming mismatch.**

## Performance

- **Duration:** 8 min
- **Started:** 2026-04-30T16:54:41Z
- **Completed:** 2026-04-30T17:02:34Z
- **Tasks attempted:** 5 of 5
- **Tasks committed (kept):** 2 — Task 1 (chore baseline), Task 3 (docs RESEARCH.md falsification)
- **Tasks committed (reverted):** 2 — Task 2 (spoke DiD), Task 4 (FLUX PATCH SURFACE patches + capsule escape hatch)
- **Tasks committed (rollback annotation):** 1 — Task 5 (chore failure mode + re-plan path)
- **Files modified (net post-rollback):** 1 (RESEARCH.md from Task 3 — falsification correction blocks; the 4 cluster yaml files net-zero)

## Outcome

**Plan ROLLED BACK (ATTEMPT 2).** TEN-05 NOT completed. Phase 9 cannot advance past Plan 09-03 until ATTEMPT 3 re-plan addresses spoke SA naming mismatch.

## Accomplishments

- **Task 1: Pre-patch baseline assertion PASSED** — `task health-check` exit 0; 19/19 health-check assertions; all 7 v0.18 sections green. Confirmed post-rollback baseline from attempt 1 was clean before attempt 2 changes landed.
- **Task 2: Spoke defense-in-depth landed cleanly per static contracts** — both `clusters/hub-flux/spokes/spoke-apps.yaml` and `spoke-ml.yaml` updated with `spec.serviceAccountName: kustomize-controller`. REQ-SPOKE-04 + REQ-SPOKE-05 head comment blocks preserved. P40/P18 invariant (kubeConfig.secretRef.key: value.yaml) preserved. `kubectl kustomize clusters/hub-flux/flux-system/` rendered cleanly with new fields. Single atomic commit `7598cd8`. **REVERTED post-rollback (commit cd1cf32).**
- **Task 3: RESEARCH.md §Gap 3 + §Gap 11 line 693 FALSIFIED correction blocks committed** — appended below the closing `Confidence: HIGH` line of each Gap section, citing 09-03-SUMMARY.attempt-1-rollback.md commit chain (`899f2fe` → `9b6b3a5` revert → `6cdbfb2` annotation). Original Gap section headers preserved; appended (not replaced). Single docs commit `7cd0b92`. **KEPT post-rollback** (the falsification record is independent valid evidence; only attempt 2's mitigation hypothesis is newly falsified, not the original §Gap 3 prediction).
- **Task 4: Lockdown patches landed cleanly per static contracts (12/12 + 4/4 GREEN)** — `tenants-03-static-lockdown.bats`: 12/12 GREEN; `tenants-05-static-split-path.bats`: 4/4 FULLY GREEN. All 4 controllers reached `availableReplicas == replicas` on first poll (no CrashLoopBackOff per RESEARCH §Gap 2 line 235-236). Lockdown flag args confirmed live: kustomize-controller (3 flags) + helm-controller (2 flags) + notification-controller (1 flag). Single atomic commit `cb9b00e`. **REVERTED post-rollback (commit 0feb191).**
- **Task 5: Post-patch task health-check FAILED with exit 201** — spoke-apps + spoke-ml Ready=False with NEW failure message: `User "system:serviceaccount:flux-system:kustomize-controller" cannot patch resource "namespaces"` (different from attempt 1's `default` SA). Atomic rollback executed per plan Task 5 step 7. Required 2 reverts (Task 4 then Task 2) to actually restore baseline. Post-rollback task health-check exit 0 (19/19 pass). Single chore commit `d194031` documenting failure mode + re-plan path.

## Task Commits

Each task was committed atomically. Commit chain (in execution order):

1. **Task 1: Pre-patch baseline `task health-check`** — `6fbda21` (chore — empty commit; assertion PASSED)
2. **Task 2: Spoke defense-in-depth** — `7598cd8` (feat — 2 files, +2 lines; landed cleanly per static contracts)
3. **Task 3: RESEARCH.md falsification record** — `7cd0b92` (docs — 1 file, +33 lines; KEPT post-rollback)
4. **Task 4: FLUX PATCH SURFACE patches + capsule.yaml escape hatch** — `cb9b00e` (feat — 2 files, +64 lines; landed cleanly per static contracts)
5. **Auto-revert (Task 5 fallback step 1)** — `0feb191` (Revert "feat(09-03 RE-PLAN): hub Flux multi-tenancy lockdown patches…"; -64 lines; reverts cb9b00e)
6. **Auto-revert (Task 5 fallback step 2 — Rule 3 extension)** — `cd1cf32` (Revert "feat(09-03 RE-PLAN): spoke defense-in-depth…"; -2 lines; reverts 7598cd8)
7. **Task 5: Post-patch regression FAILED — rollback annotation** — `d194031` (chore — empty commit documenting failure mode + re-plan path)

**Plan metadata commit:** This SUMMARY commits separately after self-check.

## Files Created/Modified

**Net post-rollback: 1 file modified (RESEARCH.md).**

- `clusters/hub-flux/spokes/spoke-apps.yaml` — modified by 7598cd8 (added `spec.serviceAccountName: kustomize-controller` after `prune: true`), reverted by cd1cf32. Final state: identical to pre-Task-2 baseline.
- `clusters/hub-flux/spokes/spoke-ml.yaml` — modified by 7598cd8, reverted by cd1cf32. Final state: identical to pre-Task-2 baseline.
- `clusters/hub-flux/flux-system/kustomization.yaml` — modified by cb9b00e (added `# KARYON FLUX LOCKDOWN PATCHES` sentinel + `patches:` block with 4 patches), reverted by 0feb191. Final state: identical to pre-Task-4 baseline (head comment block + KARYON SPOKES MOUNT + KARYON POC MOUNT + resources block only).
- `clusters/hub-flux/pocs/capsule.yaml` — modified by cb9b00e (added Phase 9 D-09-05a comment block + `serviceAccountName: kustomize-controller` to spec), reverted by 0feb191. Final state: identical to pre-Task-4 baseline (Phase 8 D-08-12 head comment + spec without serviceAccountName).
- `.planning/phases/09-tenants-flux-multi-tenancy-lockdown/09-RESEARCH.md` — modified by 7cd0b92 (appended FALSIFIED correction blocks to §Gap 3 + §Gap 11). **NOT REVERTED** — falsification record kept post-rollback.

## Decisions Made

### Pattern: Suspend+apply for D-08-13 push-gate deferral

Identical to attempt 1's adoption: `flux suspend kustomization flux-system --context=k3d-hub-flux` + `kubectl kustomize clusters/hub-flux/flux-system/ | kubectl --context=k3d-hub-flux apply -f -`. After regression test (PASS or FAIL path), `flux resume kustomization flux-system --context=k3d-hub-flux` lets cluster converge back to origin/main baseline cleanly because origin/main lacks lockdown patches → no state conflict.

This pattern continues to work as designed under D-08-13 push-gate deferral. No deviation from attempt 1's pattern.

### Atomic rollback via `git revert --no-edit HEAD` (NOT `--no-verify`) — Rule 3 EXTENSION

Per attempt 1's correction: `git revert --no-verify HEAD` is invalid; correct invocation is `git revert --no-edit HEAD`. Honored throughout attempt 2.

**EXTENSION in attempt 2 (Rule 3 deviation):** the plan's Task 5 step 7 says "revert the Task 4 commit" using `git revert --no-edit HEAD`. After Task 4's revert, the cluster spokes were STILL failing because the worktree's spoke files still had `serviceAccountName: kustomize-controller` from Task 2. The plan's success criteria says "baseline restored" — to achieve that, executor extended the rollback chain to revert Task 2's commit too:

```bash
git revert --no-edit HEAD             # revert cb9b00e (Task 4) → 0feb191
git revert --no-edit 7598cd8          # revert Task 2 → cd1cf32
kubectl kustomize ... | kubectl apply  # align cluster state with reverted yaml
flux reconcile spoke-apps; flux reconcile spoke-ml
flux resume kustomization flux-system  # cluster converges on origin/main baseline
task health-check                      # exit 0 (baseline confirmed)
```

This is a Rule 3 (auto-fix blocking issue) extension of the plan's literal "revert HEAD" instruction, applied because the plan's premise (Task 2's spoke DiD as a safe precondition for Task 4) was itself falsified. The contract honored is "baseline restored", which the plan's success criteria explicitly state.

### KEEPING Task 3 (RESEARCH.md falsification record) post-rollback

Task 3 commit `7cd0b92` was NOT reverted because the falsification it documents is independent valid evidence:
- The ORIGINAL §Gap 3 prediction (attempt 1: "flag applies ONLY when kubeConfig is unset") is still FALSIFIED. That falsification rests on attempt 1's commit chain (`899f2fe` → `9b6b3a5`), not on attempt 2's now-falsified mitigation hypothesis.
- The §Gap 11 line 693 prediction ("v0.18 spokes use cluster-admin SA via kubeConfig — no impact") is also still FALSIFIED for the same reason.
- Only attempt 2's MITIGATION (set `serviceAccountName: kustomize-controller` on spoke Ks) is newly falsified — that's documented in this SUMMARY's `key-decisions`, NOT in RESEARCH.md (yet — next-attempt re-planner should consider whether to add a third correction block to §Gap 3 reflecting attempt 2's new finding about spoke SA naming).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking issue] Atomic rollback chain extended from 1 commit to 2 commits**

- **Found during:** Task 5 step 7 (post-rollback baseline assertion attempt)
- **Issue:** Plan's Task 5 step 7 says "Atomic rollback: revert the Task 4 commit. Use `git revert --no-edit HEAD`." After executing this, cluster spokes continued to fail with the same forbidden-namespace-patch error (`system:serviceaccount:flux-system:kustomize-controller cannot patch resource "namespaces"`). Root cause: the worktree's `clusters/hub-flux/spokes/spoke-{apps,ml}.yaml` still had `serviceAccountName: kustomize-controller` from Task 2, and Flux's impersonation behavior (when both kubeConfig + serviceAccountName are set) is independent of the `--default-service-account` controller flag — the controller forwards the SA name across the kubeConfig boundary as the impersonation target on the spoke cluster, regardless of whether the lockdown flag is set on the controller itself.
- **Fix:** Extended the revert chain to also revert Task 2's commit (`git revert --no-edit 7598cd8` → commit `cd1cf32`). Then `kubectl kustomize | kubectl apply` to align cluster state with the doubly-reverted yaml. Then `flux reconcile spoke-apps + spoke-ml` to force a fresh apply with empty serviceAccountName. Then `flux resume kustomization flux-system` to converge cluster on origin/main baseline.
- **Files modified:** None (operational chain — git revert + kubectl apply + flux reconcile + flux resume; no source file edits beyond what the reverts already did).
- **Verification:** Post-extension `task health-check` exit 0 (19/19 pass). Spoke-apps + spoke-ml both Ready=True. Controller args back to baseline (no lockdown flags).
- **Committed in:** Two revert commits (`0feb191` for Task 4, `cd1cf32` for Task 2) + the Task 5 chore annotation (`d194031`) documenting the extension.

### Plan-driven Rollback (NOT a deviation — explicit fallback path)

**Atomic rollback was the plan's explicit Task 5 step 7 fallback path on regression detection.** The plan author anticipated the failure-mode possibility and documented the rollback path verbatim:

> "If post-patch task health-check FAILS:
> - DO NOT continue to plan-end output.
> - Atomic rollback: revert the Task 4 commit. **Use `git revert --no-edit HEAD` (NOT `--no-verify`)**"

Per CONTEXT.md Discretion §"Order of task health-check rerun" line 296: "Failure on (2) → roll back patch atomically." This is the explicit fallback path, NOT a deviation. The Rule 3 EXTENSION above (chain revert to 2 commits) is the only formal deviation.

---

**Total deviations:** 1 auto-fixed (1 Rule 3 blocking — chain rollback extended). Atomic rollback (single commit) is explicit plan fallback path; the 2-commit chain is the Rule 3 extension.

**Impact on plan:** Plan ROLLED BACK; TEN-05 NOT completed. Phase 9 advance blocked on attempt 3 re-plan landing.

## Issues Encountered

### Regression: spoke-apps + spoke-ml Ready=False post-lockdown — NEW FAILURE MODE (PRIMARY FINDING)

**Root cause (different from attempt 1):** Plan 09-03 RE-PLAN's Task 2 set `spec.serviceAccountName: kustomize-controller` on `clusters/hub-flux/spokes/spoke-apps.yaml` + `spoke-ml.yaml` as defense-in-depth against attempt 1's failure mode. But the spoke clusters (k3d-spoke-apps + k3d-spoke-ml) do NOT have a `kustomize-controller` ServiceAccount with cluster-admin permissions. Verified via `kubectl --context=k3d-spoke-apps get sa -A`:

```
NAMESPACE           NAME                                          SECRETS   AGE
flux-system         default                                       0         47h
flux-system         flux-reconciler                               0         47h
```

And `kubectl --context=k3d-spoke-apps get clusterrolebindings`:

```
flux-reconciler-cluster-admin    ClusterRole/cluster-admin    47h
```

The ONLY SA with cluster-admin on each spoke is `flux-reconciler` (registered by `scripts/register-spokes-for-flux.sh`). The `kustomize-controller` SA name only exists in the HUB cluster's flux-system namespace (where the actual kustomize-controller Deployment runs). When a Flux Kustomization CR has both `spec.kubeConfig` and `spec.serviceAccountName: kustomize-controller`, Flux v2.8.6 impersonates the named SA ON THE TARGET CLUSTER (the spoke) — so it tries to act as `system:serviceaccount:flux-system:kustomize-controller` on the spoke, which does not exist with cluster-admin perms, hence the forbidden namespace-patch error.

**Live observation (Task 5 step 6):**
```
Namespace/podinfo dry-run failed (Forbidden): namespaces "podinfo" is forbidden:
  User "system:serviceaccount:flux-system:kustomize-controller" cannot patch resource
  "namespaces" in API group "" in the namespace "podinfo"
Namespace/karyon-spoke-apps dry-run failed (Forbidden): namespaces "karyon-spoke-apps" is forbidden:
  User "system:serviceaccount:flux-system:kustomize-controller" cannot patch resource
  "namespaces" in API group "" in the namespace "karyon-spoke-apps"
```

(Mirror error on spoke-ml targeting `gpu-smoke` + `karyon-spoke-ml` namespaces.)

This failure mode is INDEPENDENT of the lockdown flag patches (Task 4) — it persists even after reverting Task 4 alone. Confirmed by checking spoke-apps Ready condition AFTER Task 4 revert but BEFORE Task 2 revert:

```json
{
    "lastTransitionTime": "2026-04-30T17:00:46Z",
    "message": "Namespace/karyon-spoke-apps dry-run failed (Forbidden): namespaces \"karyon-spoke-apps\" is forbidden: User \"system:serviceaccount:flux-system:kustomize-controller\" cannot patch resource \"namespaces\" in API group \"\" in the namespace \"karyon-spoke-apps\"",
    "observedGeneration": 2,
    "reason": "ReconciliationFailed",
    "status": "False",
    "type": "Ready"
}
```

This forced the Rule 3 extension of the rollback chain (revert Task 2 too).

**Comparison to attempt 1:**

| Attribute | Attempt 1 | Attempt 2 |
|-----------|-----------|-----------|
| Trigger | --default-service-account=default flag (Task 4 attempt 1's commit 899f2fe) | spec.serviceAccountName: kustomize-controller on spoke Ks (Task 2 attempt 2's commit 7598cd8) |
| Impersonated SA on spoke | `default` (no perms) | `kustomize-controller` (does not exist on spoke) |
| Persists after reverting only the FLUX PATCH SURFACE patches? | NO — reverting attempt 1's single commit restored baseline | YES — reverting Task 4 alone left the worktree spoke files with serviceAccountName still set; cluster still failing |
| Rollback commits required | 1 (`9b6b3a5`) | 2 (`0feb191` + `cd1cf32`) |
| RESEARCH falsification | §Gap 3 + §Gap 11 line 693 (original predictions) | NEW: Plan 09-03 RE-PLAN Task 2 spoke-SA-name assumption |

**Re-plan path (REQUIRED, ATTEMPT 3):** Three candidate mitigation hypotheses (next-attempt re-planner picks one):

(a) **Use `spec.serviceAccountName: flux-reconciler` on spoke Ks.** This matches the actually-existing SA on spoke clusters (cluster-admin via `flux-reconciler-cluster-admin` CRB). Risk: must verify the impersonation chain works correctly through the kubeConfig token's identity (the kubeConfig principal must have permission to impersonate `flux-reconciler` SA on the spoke; if the kubeConfig token IS already `flux-reconciler` then this is a self-impersonation which Kubernetes typically allows). Recommended as the most likely safe path.

(b) **Skip spoke-side defense-in-depth + re-investigate the §Gap 3 falsification.** Maybe NOT setting `--default-service-account=default` on kustomize-controller is the right call (i.e., narrow the lockdown to other controllers only). Or set it, but use a kustomize patch selector that excludes the spoke Ks from the controller's flag scope (Flux v2.8.6 likely doesn't support per-K flag overrides, so this may not be feasible). Risk: this defeats the multi-tenancy lockdown contract for the spoke Ks themselves; tenant Ks (Plan 09-02 P27 inner Ks) still get the flag protection because they reside in tenant namespaces and run under per-tenant SAs explicitly set.

(c) **Extend `scripts/register-spokes-for-flux.sh` to create a `kustomize-controller` SA + cluster-admin CRB on each spoke.** Then attempt 3 can use `serviceAccountName: kustomize-controller` as originally planned. Risk: extends infrastructure scope significantly (touches scripts/, not just clusters/hub-flux/) — likely out of scope for one plan; would need its own planning cycle.

### Live cluster state mismatch under D-08-13 push-gate deferral (PRESERVED from attempt 1)

Identical to attempt 1: `flux reconcile kustomization flux-system` would just re-pull origin/main (which lacks Plan 09-03 commits) without exercising the regression gate. Suspend+apply pattern continues to work as designed.

## Static Bats Coverage

| Bats file | Pre-patch (Task 1) | Post-Task-4 (in-cluster) | Post-rollback |
|-----------|--------------------|--------------------------|---------------|
| `tests/bats/tenants-03-static-lockdown.bats` | 3/12 GREEN (sentinels) | **12/12 FULLY GREEN** | 3/12 GREEN (back to baseline RED — yaml reverted) |
| `tests/bats/tenants-05-static-split-path.bats` | 3/4 GREEN (D-08-12 invariants) | **4/4 FULLY GREEN** | 3/4 GREEN (back to baseline) |

Static bats correctly track the rollback: post-rollback contract surface matches pre-Task-4 baseline. The bats files themselves were validated as accurate detectors of both the patch landing AND its rollback.

## NEW Falsification Candidate (for next-attempt re-planner)

For consumption by Plan 09-03 ATTEMPT 3 re-planner. Suggested update to `.planning/phases/09-tenants-flux-multi-tenancy-lockdown/09-RESEARCH.md` §Gap 3 (append a third correction block):

```markdown
### CORRECTION 2 (Plan 09-03 attempt 2 falsifier — 2026-04-30)

The Plan 09-03 RE-PLAN attempt 2's proposed mitigation (set `spec.serviceAccountName: kustomize-controller` on v0.18 spoke Kustomization CRs as defense-in-depth before the lockdown flags land) is **FALSIFIED** by live observation in Flux v2.8.6 (Plan 09-03 RE-PLAN attempt 2, rolled back at commits `0feb191` + `cd1cf32`; documented in `.planning/phases/09-tenants-flux-multi-tenancy-lockdown/09-03-SUMMARY.md`).

**Live observation:**
- Spoke clusters (k3d-spoke-{apps,ml}) only have `flux-reconciler` SA with cluster-admin (registered by scripts/register-spokes-for-flux.sh; ClusterRoleBinding `flux-reconciler-cluster-admin` → cluster-admin role)
- They do NOT have a `kustomize-controller` SA — that name only exists on the hub cluster (where the actual kustomize-controller Deployment runs)
- When Flux v2.8.6 sees both `spec.kubeConfig` + `spec.serviceAccountName: kustomize-controller`, it impersonates the named SA ON THE TARGET CLUSTER (the spoke), which fails: `User "system:serviceaccount:flux-system:kustomize-controller" cannot patch resource "namespaces"`
- This failure mode persists EVEN WITHOUT the lockdown flag patches applied — it's caused by the Task 2 yaml change alone

**Mitigation (next-attempt re-plan candidates):**
- (a) Use `spec.serviceAccountName: flux-reconciler` on spoke Ks (matches actually-existing SA)
- (b) Skip spoke-side defense-in-depth entirely + re-narrow lockdown scope
- (c) Extend `scripts/register-spokes-for-flux.sh` to create kustomize-controller SA + CRB on each spoke

Confidence: HIGH (live falsifier; cluster state captured in 09-03-SUMMARY.md commit chain — `7598cd8` (Task 2) + `cb9b00e` (Task 4) → `0feb191` + `cd1cf32` reverts → `d194031` annotation).
```

(NOT committed in this attempt — left for next-attempt re-planner to add as part of attempt 3's RESEARCH.md update.)

## User Setup Required

None — no external service configuration required. The next-attempt re-plan is a pure refactor of Kustomization CR yaml (or a bigger script change if mitigation hypothesis (c) is chosen).

## Next Phase Readiness

**Phase 9 BLOCKED on Plan 09-03 ATTEMPT 3 re-plan.** Cannot advance to Plan 09-04 (Phase 9 verifier) until lockdown patches land cleanly with a corrected spoke-side mitigation.

**Suggested orchestrator handling:**
1. Mark Plan 09-03 as ROLLED BACK (ATTEMPT 2) in STATE.md / ROADMAP.md
2. Trigger Plan 09-03 ATTEMPT 3 re-plan via `/gsd-plan` with this SUMMARY as input (the falsification candidate documented above is the primary input for the re-planner)
3. Re-plan ATTEMPT 3 picks one of the three mitigation hypotheses and rebuilds the task graph accordingly
4. Re-execute via `/gsd-execute-phase` — pre-patch baseline + post-patch regression should BOTH pass with the corrected mitigation in place

**Forward-pointer:** Plan 09-03 ATTEMPT 3 owns RESEARCH.md update for §Gap 3 second correction block (per the suggested update above).

---
*Phase: 09-tenants-flux-multi-tenancy-lockdown*
*Plan: 03 (RE-PLAN ATTEMPT 2 — ROLLED BACK)*
*Completed: 2026-04-30*

## Self-Check: PASSED

Verifications performed:

- [x] Task 1 commit `6fbda21` exists in git log (`git log --oneline --all | grep` confirms)
- [x] Task 2 commit `7598cd8` exists (atomic spoke DiD landing — 2 files, +2 lines)
- [x] Task 3 commit `7cd0b92` exists (RESEARCH.md falsification — 1 file, +33 lines; KEPT post-rollback)
- [x] Task 4 commit `cb9b00e` exists (atomic patches block landing — 2 files, +64 lines)
- [x] Auto-revert commit `0feb191` exists (revert of Task 4 — same 2 files, -64 lines)
- [x] Auto-revert commit `cd1cf32` exists (revert of Task 2 — same 2 files, -2 lines; Rule 3 extension)
- [x] Task 5 chore commit `d194031` exists (rollback annotation, empty)
- [x] `clusters/hub-flux/flux-system/kustomization.yaml` post-rollback: NO `patches:` block (yq `.patches` returns null)
- [x] `clusters/hub-flux/pocs/capsule.yaml` post-rollback: NO `spec.serviceAccountName` (yq returns null); `spec.kubeConfig` still null (D-08-12 invariant intact)
- [x] `clusters/hub-flux/spokes/spoke-apps.yaml` post-rollback: NO `spec.serviceAccountName` (yq returns null)
- [x] `clusters/hub-flux/spokes/spoke-ml.yaml` post-rollback: NO `spec.serviceAccountName` (yq returns null)
- [x] `.planning/phases/09-tenants-flux-multi-tenancy-lockdown/09-RESEARCH.md` Task 3 changes preserved post-rollback (FALSIFIED markers + 09-03-SUMMARY.attempt-1-rollback.md citation present)
- [x] `.planning/phases/09-tenants-flux-multi-tenancy-lockdown/09-03-SUMMARY.attempt-1-rollback.md` archive PRESERVED (NOT overwritten — separate file; user objective honored)
- [x] `.planning/phases/09-tenants-flux-multi-tenancy-lockdown/09-03-SUMMARY.md` canonical SUMMARY created (this file)
- [x] Final `task health-check` exit 0 (19/19 pass — full v0.18 baseline restored)
- [x] All 4 controllers post-rollback: avail=1 desired=1 (no CrashLoopBackOff residue)
- [x] Static bats tenants-03 + tenants-05 correctly track the rollback (back to pre-Task-4 RED state)
- [x] D-08-13 push-gate deferral honored throughout — no push to origin/main
- [x] No modifications to STATE.md / ROADMAP.md (orchestrator owns those writes after wave merge)
