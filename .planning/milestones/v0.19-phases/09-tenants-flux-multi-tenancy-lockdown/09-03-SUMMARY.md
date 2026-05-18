---
phase: 09-tenants-flux-multi-tenancy-lockdown
plan: 03
subsystem: infra
tags: [flux, multi-tenancy, lockdown, kustomize-controller, helm-controller, notification-controller, default-service-account, no-cross-namespace-refs, no-remote-bases, escape-hatch, regression-rollback, ten-05, d-09-05, d-09-05a, research-gap-correction, attempt-3, flux-reconciler-spoke-sa, sa-existence-pre-check, ten-05-delivered]

# Dependency graph
requires:
  - phase: 09-tenants-flux-multi-tenancy-lockdown
    provides: Plan 09-02 — per-tenant inner Ks + Secret-mirror extension; provides the surface that the lockdown patches harden (TEN-04 P27 in place)
  - phase: 08-capsule-capsule-proxy-bare-minimum-install
    provides: D-08-12 split-path layout (clusters/hub-flux/pocs/{capsule,capsule-spoke}.yaml); D-08-13 push-gate deferral to Phase 11 VAL-05; capsule.yaml hub-targeted Phase 8 head comment block
  - phase: 04-spoke-registration
    provides: clusters/hub-flux/spokes/spoke-{apps,ml}.yaml with spec.kubeConfig set; flux-reconciler SA + cluster-admin CRB on each spoke (registered by scripts/register-spokes-for-flux.sh:275-310)
provides:
  - "TEN-05 DELIVERED — hub Flux controllers run with multi-tenancy lockdown flags + flux-system Kustomization escape hatch + v0.18 task health-check regression gate PASSED post-patch under suspend+apply pattern. The 3-controller patches (kustomize-controller 3 flags + helm-controller 1 flag + notification-controller 1 flag) + flux-system K escape hatch + capsule.yaml escape hatch all landed cleanly; spoke-{apps,ml} Ks reconciled successfully under spec.serviceAccountName: flux-reconciler (Gap A — corrected attempt-2 falsifier where kustomize-controller SA was used)."
  - "RESEARCH.md §Gap 3 + §Gap 11 each carry BOTH attempt-1 CORRECTION + attempt-2 CORRECTION 2 blocks (cumulative falsification record per Gap C pattern); attempt-1 evidence chain (899f2fe → 9b6b3a5 revert → 6cdbfb2) preserved verbatim; attempt-2 evidence chain (7598cd8 + cb9b00e → 0feb191 + cd1cf32 reverts → d194031) cited in CORRECTION 2."
  - "Target-cluster-specific SA naming invariant established as load-bearing pattern for cross-cluster Flux Kustomizations: hub-targeted → kustomize-controller; spoke-{apps,ml}-targeted → flux-reconciler; spoke-capsule tenant Ks → gitops-reconciler (per Plan 09-02). The three SA names are NOT interchangeable; each must match the SA available on the target cluster."
  - "FLUX PATCH SURFACE patch surface (clusters/hub-flux/flux-system/kustomization.yaml — # KARYON FLUX LOCKDOWN PATCHES sentinel + 4 patches block) survives flux bootstrap re-runs per file's own header documentation. Phase 9 lockdown is a stable patch surface for future Phase 11 VAL-05 push to origin/main."
affects:
  - "Plan 09-04 (Phase 9 verifier) — UNBLOCKED. Verifier inherits the regression gate via tenants-12-live-health-check.bats (calls task health-check). Plan 09-04 may now execute."
  - "RESEARCH §Gap 3 confidence rating: original FALSIFICATION (attempt 1) STANDS; attempt-2 mitigation FALSIFICATION (CORRECTION 2) STANDS; attempt-3 mitigation (flux-reconciler SA) VERIFIED via live regression test under suspend+apply."
  - "STATE.md Phase 9 Blockers/Concerns subsection (lockdown flag patches → high regression risk) — RESOLVED. The risk materialized on attempts 1 + 2 with different failure modes; attempt-3 mitigation per Gap A succeeded; lockdown patches now stable."
  - "Phase 11 VAL-05 push-gate (D-08-13 deferred): Plan 09-03 commits remain local-only on the worktree branch; orchestrator merges back to main; no push to origin/main during this plan execution per D-08-13."

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Pre-patch SA-existence assertion (Gap B) — kubectl get sa + clusterrolebinding probes BEFORE any source-file modification. Closes premise-drift risk identified by attempt-2 rollback (where the kustomize-controller SA assumption on spoke clusters was unverified). Structurally checkable: 4 kubectl probes return non-empty literal-match before Task 2 begins."
    - "Target-cluster-specific SA naming for cross-cluster Flux Kustomizations — when spec.kubeConfig is set, spec.serviceAccountName names a SA on the TARGET cluster (the spoke), not the hub. Naming differs per target: hub→kustomize-controller, spoke-{apps,ml}→flux-reconciler, spoke-capsule tenant ns→gitops-reconciler. Naming mismatch causes immediate forbidden errors at reconcile time (attempt-2 falsifier)."
    - "Suspend+apply pattern (D-08-13 push-gate workaround) — flux suspend kustomization flux-system + kubectl kustomize | kubectl apply lets cluster-side state diverge from origin/main long enough to exercise the regression gate without violating push-gate deferral. After exercise (PASS or FAIL), flux resume converges cluster back to origin/main baseline cleanly because origin lacks Plan 09-03 commits → no state conflict."
    - "Atomic-rollback fallback contract (Gap D — sharpened from attempt-1's literal 'revert HEAD'): on post-patch FAIL, revert ALL plan commits in reverse chronological order using `git revert --no-edit <sha>` (NOT --no-verify — invalid for git revert) until pre-Task-1 baseline restored; cluster baseline confirmed via task health-check exit 0 post-rollback. This attempt did NOT exercise the rollback path — Task 5 PASS path executed."
    - "Cumulative falsification record (Gap C) — when a re-plan's mitigation is itself falsified, append a CORRECTION 2 block below the existing CORRECTION block in RESEARCH.md, preserving the prior evidence verbatim. Each falsification cites its commit chain (e.g., attempt-1: 899f2fe + 9b6b3a5 + 6cdbfb2; attempt-2: 7598cd8 + cb9b00e + 0feb191 + cd1cf32 + d194031). Provides cumulative audit trail for downstream consumers."

key-files:
  created:
    - ".planning/phases/09-tenants-flux-multi-tenancy-lockdown/09-03-SUMMARY.md (this file — attempt-3 SUMMARY; attempt-1 archive at 09-03-SUMMARY.attempt-1-rollback.md and attempt-2 archive at 09-03-SUMMARY.attempt-2-rollback.md preserved unchanged)"
  modified:
    - "clusters/hub-flux/spokes/spoke-apps.yaml — added `spec.serviceAccountName: flux-reconciler` (Task 2 commit 621e530)"
    - "clusters/hub-flux/spokes/spoke-ml.yaml — added `spec.serviceAccountName: flux-reconciler` (Task 2 commit 621e530)"
    - "clusters/hub-flux/flux-system/kustomization.yaml — appended # KARYON FLUX LOCKDOWN PATCHES sentinel + patches block (4 patches) (Task 4 commit d519b90)"
    - "clusters/hub-flux/pocs/capsule.yaml — added D-09-05a comment block + spec.serviceAccountName: kustomize-controller (Task 4 commit d519b90)"
    - ".planning/phases/09-tenants-flux-multi-tenancy-lockdown/09-RESEARCH.md — appended CORRECTION 2 blocks to §Gap 3 + §Gap 11 (Task 3 commit a537e67)"

key-decisions:
  - "Gap A LOCKED: spec.serviceAccountName: flux-reconciler on spoke v0.18 Ks (NOT kustomize-controller per attempt 2 falsifier; NOT default per attempt 1 falsifier). The SA name flux-reconciler matches the actually-existing SA on each spoke cluster per scripts/register-spokes-for-flux.sh:286. The hub-side spoke-{apps,ml}-kubeconfig Secret bearer token IS the flux-reconciler SA's token — self-impersonation under cluster-admin via the flux-reconciler-cluster-admin CRB. VERIFIED via live task health-check exit 0 post-Task-4."
  - "Gap B LOCKED: NEW Task 0.5 — pre-patch SA-existence assertion on BOTH spoke contexts. Four kubectl probes (SA + CRB on each spoke) returned non-empty literal-match → Task 1+ proceeded. Premise-drift risk structurally closed; if scripts/register-spokes-for-flux.sh ever drifts to a different SA name, Task 0.5 will fail-fast before any yaml change lands."
  - "Gap C LOCKED: RESEARCH.md §Gap 3 + §Gap 11 each have BOTH attempt-1 CORRECTION + attempt-2 CORRECTION 2 blocks. Attempt-1 blocks preserved verbatim (no removal); attempt-2 CORRECTION 2 blocks appended per pre-drafted text in 09-03-SUMMARY.attempt-2-rollback.md NEW Falsification Candidate section. Cumulative falsification trail preserved per attempt-1 pattern."
  - "Gap D LOCKED but NOT EXERCISED: sharpened atomic-rollback contract reads 'revert ALL plan commits in reverse chronological order until pre-Task-1 baseline restored. Each revert uses git revert --no-edit <sha> (NOT --no-verify — invalid for git revert).' Plan 09-03 ATTEMPT 3 PASS path triggered Step 5 PATH A — no rollback executed. The contract remains documented as the FAIL-path contract for any future high-regression-risk plan."
  - "Gap E LOCKED: file scope unchanged from attempt 2 — exactly 5 files modified (spoke-apps.yaml, spoke-ml.yaml, flux-system/kustomization.yaml, pocs/capsule.yaml, 09-RESEARCH.md). Did NOT touch capsule-spoke.yaml or any other file. Plan 09-04 verifier task health-check is the safety net for any out-of-scope drift."
  - "Gap F LOCKED: no additional pre-patch live experiment. Three-checkpoint structure (Task 0.5 + Task 1 + Task 5) is the agreed bound — did not add a fourth task."
  - "D-08-13 push-gate deferral HONORED throughout: no git push at any task; commits remain local-only on worktree branch. Suspend+apply pattern (flux suspend + kubectl kustomize | kubectl apply + flux resume) lets cluster diverge from origin/main long enough to exercise regression gate without violating push-gate deferral."
  - "Suspend+apply pattern confirmed working as designed for the third time (attempts 1, 2, 3). After Step 4 PASS regression test, flux resume converged cluster back to origin/main baseline (sha 32e0b2faca63a9cdbb51cd8800376c33afa697e8) cleanly because origin/main lacks Plan 09-03 commits → no state conflict. Pattern remains the canonical test approach for high-regression-risk plans landing under D-08-13."

patterns-established:
  - "Pattern: Pre-patch SA-existence assertion as fail-fast guard for cross-cluster reconciles — when a plan modifies a Flux Kustomization CR's spec.serviceAccountName, structurally verify the named SA + cluster-admin CRB exist on the TARGET cluster BEFORE landing the yaml change. kubectl get sa + clusterrolebinding probes return non-empty literal-match or abort the plan. Closes 'unverified premise on spoke registration' regression class."
  - "Pattern: Target-cluster-specific SA naming as load-bearing invariant for cross-cluster Ks. Three SA names (kustomize-controller, flux-reconciler, gitops-reconciler) each correspond to a target cluster (hub, spoke-{apps,ml}, spoke-capsule tenant ns). Documented in RESEARCH.md §Gap 3 CORRECTION 2 block as 'Defense-in-depth invariant restated (target-cluster-specific SA naming)'."
  - "Pattern: Cumulative falsification record (CORRECTION blocks chained) — preserves audit trail of all falsifications across re-plan attempts. Future plans referencing the falsified prediction can read both the original prediction + all CORRECTION blocks and choose the most recent verified mitigation. CORRECTION 2 cites attempt-2 commit chain; CORRECTION 3 (if needed) would cite this attempt-3 evidence chain (621e530 + d519b90 + 37db011)."
  - "Pattern: Suspend+apply for in-worktree exercise of bootstrap-managed surfaces under push-gate deferral — verified across 3 plan executions (attempts 1, 2, 3). Worked identically all 3 times: flux suspend → kubectl kustomize | kubectl apply → exercise → flux resume → origin/main baseline restored. No state conflict at resume because origin/main lacks plan commits."
  - "Pattern: Phase 9 FLUX PATCH SURFACE survives flux bootstrap — the patches block + flux-system K escape hatch land in clusters/hub-flux/flux-system/kustomization.yaml (the documented edit point), NOT in gotk-components.yaml or gotk-sync.yaml (which are bootstrap-managed). Future flux bootstrap re-runs preserve the patches block per file's own header documentation."

requirements-completed: [TEN-05]

# Metrics
duration: 6min
completed: 2026-04-30
---

# Phase 09 Plan 03 ATTEMPT 3: Hub Flux Multi-Tenancy Lockdown — TEN-05 DELIVERED Summary

**Hub Flux multi-tenancy lockdown landed cleanly on attempt 3 after two prior atomic rollbacks. Gap A's mitigation (spec.serviceAccountName: flux-reconciler on spoke v0.18 Kustomization CRs — matching the actually-existing SA per scripts/register-spokes-for-flux.sh:286) is VERIFIED via live regression test under suspend+apply pattern: post-patch task health-check exits 0 (19/19 v0.18 assertions green); all 3 patched controllers carry the expected lockdown flags (kustomize-controller 3 flags + helm-controller 1 flag + notification-controller 1 flag); flux-system Kustomization CR escape hatch (D-09-05a) confirmed live; capsule.yaml hub-targeted escape hatch confirmed via static bats; spoke-{apps,ml} + flux-system + poc-capsule + poc-capsule-spoke Kustomizations all reach Ready=True post-patch. Suspend+apply executed cleanly under D-08-13 push-gate deferral; flux resume converged cluster back to origin/main baseline (sha 32e0b2fa) cleanly. TEN-05 contract DELIVERED. Plan 09-04 (Phase 9 verifier) UNBLOCKED.**

## Performance

- **Duration:** 6 min 24 sec
- **Started:** 2026-04-30T17:57:49Z
- **Completed:** 2026-04-30T18:04:13Z
- **Tasks attempted:** 6 of 6
- **Tasks committed (kept):** 6 — Task 0.5 (chore SA assertion), Task 1 (chore baseline), Task 2 (feat spoke DiD), Task 3 (docs RESEARCH CORRECTION 2), Task 4 (feat FLUX PATCH SURFACE patches + capsule escape hatch), Task 5 (chore PASS)
- **Tasks committed (reverted):** 0 — no rollback exercised this attempt; Gap D contract remains documented but unused
- **Files modified (net):** 5 — spoke-apps.yaml, spoke-ml.yaml, flux-system/kustomization.yaml, pocs/capsule.yaml, 09-RESEARCH.md

## Outcome

**Plan COMPLETED (ATTEMPT 3).** TEN-05 delivered. Phase 9 may advance to Plan 09-04 (verifier).

## Accomplishments

- **Task 0.5: Pre-patch SA-existence assertion PASSED (Gap B)** — Four kubectl probes returned non-empty literal-match: `serviceaccount/flux-reconciler` on each spoke + `clusterrolebinding.rbac.authorization.k8s.io/flux-reconciler-cluster-admin` on each spoke. Premise-drift risk structurally closed — Task 2's spec.serviceAccountName: flux-reconciler choice is verified against actual cluster state BEFORE any yaml change lands. Empty chore commit `ea8d8a1`.

- **Task 1: Pre-patch baseline assertion PASSED** — `task health-check` exit 0; 19/19 health-check assertions; all 7 v0.18 sections green (clusters + Flux controllers + spoke Kustomizations + DNS probe + GPU capacity + TLS SANs + workload proofs). Confirmed pre-Plan-09-03 baseline clean before any source-file change. Empty chore commit `b7b9b01`.

- **Task 2: Spoke defense-in-depth landed cleanly per static + acceptance contracts (Gap A)** — Both `clusters/hub-flux/spokes/spoke-apps.yaml` and `spoke-ml.yaml` updated with `spec.serviceAccountName: flux-reconciler`. yq round-trip verified flux-reconciler value on both files. REQ-SPOKE-04 + REQ-SPOKE-05 head comment blocks preserved verbatim (grep confirms). P40/P18 invariant (kubeConfig.secretRef.key: value.yaml) preserved. secretRef.name unchanged (spoke-apps-kubeconfig / spoke-ml-kubeconfig — regression gate). `kubectl kustomize clusters/hub-flux/flux-system/` rendered cleanly. Single atomic feat commit `621e530` (2 files, +2 lines).

- **Task 3: RESEARCH.md §Gap 3 + §Gap 11 CORRECTION 2 blocks landed (Gap C)** — Pre-drafted text from 09-03-SUMMARY.attempt-2-rollback.md NEW Falsification Candidate section appended below the existing attempt-1 CORRECTION blocks in both Gap sections. Existing CORRECTION blocks preserved verbatim (grep -c '### CORRECTION (Plan 09-03 attempt 1 falsifier' returns 2; grep -c '### CORRECTION 2 (Plan 09-03 attempt 2 falsifier' returns 2). Citation chain present: 0feb191 + cd1cf32 + d194031 (attempt-2) + 899f2fe + 9b6b3a5 (attempt-1). Target-cluster-specific SA naming invariant text present (hub: kustomize-controller; spoke-{apps,ml}: flux-reconciler; spoke-capsule tenant: gitops-reconciler). Single atomic docs commit `a537e67` (1 file, +29 lines, additive only).

- **Task 4: FLUX PATCH SURFACE patches block + capsule.yaml escape hatch landed cleanly per static contracts (Gap E)** — `clusters/hub-flux/flux-system/kustomization.yaml` got the # KARYON FLUX LOCKDOWN PATCHES sentinel + 4-patch block (kustomize-controller 3 flags + helm-controller 1 flag + notification-controller 1 flag + flux-system K escape hatch). FLUX PATCH SURFACE head comment + KARYON SPOKES MOUNT + KARYON POC MOUNT sentinels preserved verbatim above the new patches block. `clusters/hub-flux/pocs/capsule.yaml` got D-09-05a comment block + `spec.serviceAccountName: kustomize-controller`; D-08-12 head comment + invariant evolution paragraph preserved verbatim; spec.kubeConfig remains null (D-08-12 split-path invariant). Static bats: `tenants-03-static-lockdown.bats` 12/12 GREEN; `tenants-05-static-split-path.bats` 4/4 GREEN. Single atomic feat commit `d519b90` (2 files, +51 lines).

- **Task 5: Suspend+apply + post-patch task health-check PASSED (PATH A)** — `flux suspend kustomization flux-system --context=k3d-hub-flux` succeeded; `kubectl kustomize clusters/hub-flux/flux-system/ | kubectl --context=k3d-hub-flux apply -f -` applied all resources cleanly (Deployments + Kustomization CRs + RBAC). Controllers restarted with new args within 3s of polling start (kustomize-controller carries all 3 flags; helm-controller + notification-controller carry --no-cross-namespace-refs=true each). `flux reconcile source git flux-system + kustomization spoke-apps + kustomization spoke-ml` all reported `applied revision main@sha1:32e0b2fa` successfully. spoke-apps + spoke-ml + flux-system Kustomizations all reached Ready=True at first poll iteration (~3s). `task health-check` exit 0 (19/19 assertions). `flux resume kustomization flux-system` succeeded; cluster converged back to origin/main baseline within 3s of polling (controller args back to baseline — no lockdown flags). Final `task health-check` exit 0. Empty chore commit `37db011`.

## Task Commits

Each task was committed atomically. Commit chain (in execution order):

1. **Task 0.5: Pre-patch SA-existence assertion** — `ea8d8a1` (chore — empty commit; 4 kubectl probes PASSED)
2. **Task 1: Pre-patch baseline `task health-check`** — `b7b9b01` (chore — empty commit; 19/19 PASSED)
3. **Task 2: Spoke defense-in-depth** — `621e530` (feat — 2 files, +2 lines; spec.serviceAccountName: flux-reconciler)
4. **Task 3: RESEARCH.md §Gap 3 + §Gap 11 CORRECTION 2** — `a537e67` (docs — 1 file, +29 lines; appended below existing CORRECTION blocks)
5. **Task 4: FLUX PATCH SURFACE patches + capsule.yaml escape hatch** — `d519b90` (feat — 2 files, +51 lines; 4 patches + capsule SA + D-09-05a comment)
6. **Task 5: Post-patch task health-check PASS + flux resume** — `37db011` (chore — empty commit; PATH A executed; PATH B not exercised)

**Plan metadata commit:** This SUMMARY is committed separately after self-check.

## Files Created/Modified

**Net: 5 files modified (no files created beyond this SUMMARY).**

- `clusters/hub-flux/spokes/spoke-apps.yaml` — modified by Task 2 commit `621e530`. Added `spec.serviceAccountName: flux-reconciler` (1 line). REQ-SPOKE-04/05 head comment + P40/P18 invariant preserved verbatim. Final state: 30 lines (was 29).
- `clusters/hub-flux/spokes/spoke-ml.yaml` — modified by Task 2 commit `621e530`. Same shape as spoke-apps. Final state: 30 lines (was 29).
- `clusters/hub-flux/flux-system/kustomization.yaml` — modified by Task 4 commit `d519b90`. Appended # KARYON FLUX LOCKDOWN PATCHES sentinel + patches block (4 patches: kustomize-controller / helm-controller / notification-controller Deployments + flux-system Kustomization CR). FLUX PATCH SURFACE head comment + KARYON SPOKES MOUNT + KARYON POC MOUNT sentinels preserved verbatim above the new block. Final state: 67 lines (was 23); +44 lines.
- `clusters/hub-flux/pocs/capsule.yaml` — modified by Task 4 commit `d519b90`. Added D-09-05a comment block (6 lines, between D-08-12 invariant evolution paragraph and apiVersion line) + `spec.serviceAccountName: kustomize-controller` (1 line, in spec block). D-08-12 head comment block + invariant evolution paragraph preserved verbatim. spec.kubeConfig remains null (D-08-12 split-path invariant intact). Final state: 40 lines (was 33); +7 lines.
- `.planning/phases/09-tenants-flux-multi-tenancy-lockdown/09-RESEARCH.md` — modified by Task 3 commit `a537e67`. Appended CORRECTION 2 blocks below existing attempt-1 CORRECTION blocks in §Gap 3 (at line 302) + §Gap 11 (at line 780). +29 lines total. Existing CORRECTION blocks preserved verbatim. Cumulative falsification record per Gap C pattern.

## Decisions Made

### Gap A — Mitigation hypothesis (a) selected: spec.serviceAccountName: flux-reconciler on spoke Ks

Per CONTEXT.md `<attempt3_gap_resolutions>` Gap A: the SA name `flux-reconciler` matches the actually-existing SA on each spoke cluster per `scripts/register-spokes-for-flux.sh:286` (`apply_spoke_rbac` function). The hub-side `spoke-{apps,ml}-kubeconfig` Secret bearer token IS the `flux-reconciler` SA's token (mirrored from the spoke's `flux-reconciler-token` Secret). When Flux v2.8.6 sees both `spec.kubeConfig` + `spec.serviceAccountName: flux-reconciler` on a Kustomization, it impersonates `flux-reconciler` on the TARGET cluster (the spoke) using a token that already IS `flux-reconciler` — self-impersonation under cluster-admin (allowed by Kubernetes when the principal has impersonate:* — cluster-admin includes this).

**VERIFIED via live regression test:** post-Task-4 task health-check exit 0; spoke-apps + spoke-ml + flux-system + poc-capsule + poc-capsule-spoke Kustomizations all Ready=True under the lockdown patches. The mitigation works as designed.

Rejected alternatives:
- Hypothesis (b) "skip spoke-side defense-in-depth + re-narrow lockdown scope" — would defeat TEN-05 contract for spoke Ks (the lockdown's primary protection is for the kustomize-controller running on hub, which reconciles spoke Ks); not selected.
- Hypothesis (c) "extend register-spokes-for-flux.sh to create kustomize-controller SA + CRB on each spoke" — extends infrastructure scope significantly (touches scripts/, not just clusters/hub-flux/); out of scope for one plan; not selected.

### Gap B — NEW Task 0.5 fail-fast guard

Pre-patch SA-existence assertion structurally closes the premise-drift risk that caused attempt 2's failure mode. Four kubectl probes (SA + CRB on each of 2 spoke contexts) MUST return non-empty literal-match before Task 1+ proceeds. If `register-spokes-for-flux.sh` ever drifts to a different SA name in the future, Task 0.5 would fail-fast at iteration 1 (not on iteration N where lockdown is already half-applied).

**This attempt:** all 4 probes returned non-empty literal-match within milliseconds. Plan proceeded immediately to Task 1.

### Gap C — Cumulative falsification record

Pre-drafted CORRECTION 2 text from 09-03-SUMMARY.attempt-2-rollback.md NEW Falsification Candidate section appended below existing attempt-1 CORRECTION blocks in §Gap 3 (line 302) + §Gap 11 (line 780). Append-only; existing CORRECTION blocks preserved verbatim. Citation chain spans both attempts (attempt-1: 899f2fe + 9b6b3a5 + 6cdbfb2; attempt-2: 7598cd8 + cb9b00e + 0feb191 + cd1cf32 + d194031). Target-cluster-specific SA naming invariant text included (hub: kustomize-controller; spoke-{apps,ml}: flux-reconciler; spoke-capsule tenant: gitops-reconciler).

### Gap D — Sharpened atomic-rollback contract documented but NOT exercised

The plan's Task 5 step 7 fallback contract reads: "On post-patch FAIL: revert ALL plan commits in reverse chronological order using `git revert --no-edit <sha>` for each (NOT --no-verify — invalid for git revert) until pre-Task-1 baseline restored." Plan 09-03 ATTEMPT 3 hit Step 5 PATH A (PASS) — no rollback executed. The sharpened contract remains documented for any future high-regression-risk plan; the wording is now SEMANTIC ("until baseline restored") rather than LITERAL ("revert HEAD") to avoid attempt-2's underrun.

### Gap E — File scope discipline maintained

Modified exactly the 5 files listed in the plan's `files_modified` frontmatter. Did NOT touch `clusters/hub-flux/pocs/capsule-spoke.yaml` (would conflate hub-targeted + spoke-targeted patterns; capsule-spoke uses its own per-tenant SA `gitops-reconciler` per Plan 09-02 P27 — out of this plan's scope). Plan 09-04 verifier `task health-check` is the safety net for any out-of-scope drift.

### Gap F — No additional pre-patch live experiment

Three-checkpoint structure (Task 0.5 + Task 1 + Task 5) was sufficient. Task 0.5's SA-existence pre-assertion + Task 1's pre-patch baseline + Task 5's post-patch regression assertion together cover the regression-risk surface. No fourth task added.

### D-08-13 push-gate deferral honored throughout

No `git push` invoked at any task step. All 6 commits remain local on the worktree branch (`worktree-agent-a8260eacf0613582d`). The orchestrator merges back to main after this executor returns; future Phase 11 VAL-05 push to origin/main is the deferred contract.

### Suspend+apply pattern confirmed across 3 attempts

The suspend+apply pattern (`flux suspend kustomization flux-system` + `kubectl kustomize | kubectl apply` + `flux resume`) worked identically across attempts 1, 2, 3. Attempt 1 ROLLED BACK cleanly, attempt 2 ROLLED BACK cleanly (with Rule 3 chain extension), attempt 3 PASSED cleanly. The pattern is the canonical test approach for high-regression-risk plans landing under D-08-13.

## Deviations from Plan

**None.**

The plan was executed exactly as written. No Rule 1 (bug fix), Rule 2 (missing critical functionality), Rule 3 (blocking issue), or Rule 4 (architectural change) deviations were encountered. The plan's pre-drafted text + verification commands + commit messages were used verbatim; the only minor adjustment was using the `Edit` tool instead of `cat >>` HEREDOC for Sub-task 4a (functionally equivalent — appended the same yaml content to the same file at the same insertion point).

The case-sensitivity inconsistency between the plan's pre-drafted CORRECTION 2 text (capital "Spoke-{apps,ml}-targeted Ks" at line 561 of PLAN.md) and the verify command (lowercase "spoke-{apps,ml}-targeted Ks" at line 642) is a transcription artifact in the plan — the inserted text matches the pre-drafted block verbatim (capital S), and the acceptance criterion (target-cluster-specific SA naming invariant text present) is satisfied. Documented here for transparency, not as a deviation.

## Issues Encountered

**None.**

Task 0.5 probes returned non-empty literal-match within milliseconds. Task 1 baseline was clean. Task 2 yq edits applied cleanly with all invariants preserved. Task 3 RESEARCH.md edits applied cleanly with existing CORRECTION blocks preserved verbatim. Task 4 patches block + capsule escape hatch landed cleanly with all static bats green (12/12 + 4/4). Task 5 suspend+apply + post-patch task health-check exit 0 within 3s of controller restart polling; flux resume converged cluster back to origin/main baseline within 3s of polling.

The two prior attempts' failure modes (attempt-1: `default` SA fallthrough on spokes; attempt-2: nonexistent `kustomize-controller` SA on spokes) were both successfully avoided by Gap A's mitigation (`flux-reconciler` SA on spokes — matches actually-existing SA).

## Static Bats Coverage

| Bats file | Pre-patch (Task 1) | Post-Task-4 (in-cluster) | Post-resume (origin/main baseline) |
|-----------|--------------------|--------------------------|-------------------------------------|
| `tests/bats/tenants-03-static-lockdown.bats` | 3/12 GREEN (sentinels only) | **12/12 FULLY GREEN** | (worktree state preserved — bats still 12/12 GREEN against worktree yaml) |
| `tests/bats/tenants-05-static-split-path.bats` | 3/4 GREEN (D-08-12 invariants) | **4/4 FULLY GREEN** | (worktree state preserved — bats still 4/4 GREEN) |

Static bats correctly track the patches block landing. Post-Task-4 evidence: tenants-03 12/12 + tenants-05 4/4 GREEN. After flux resume, the cluster runtime args revert to origin/main baseline (no lockdown), but the worktree yaml STILL HAS the lockdown patches block (Plan 09-03 commits remain local) — so the static bats continue to pass against the worktree yaml. This split between worktree static state (lockdown present) and cluster runtime state (origin/main baseline) is the suspend+apply contract — both are correct simultaneously.

## Live Cluster State (during suspend window — captured for forensic record)

### Controller args post-Task-4 apply

```
kustomize-controller args:
["--events-addr=http://notification-controller.$(RUNTIME_NAMESPACE).svc.cluster.local./",
 "--watch-all-namespaces=true",
 "--log-level=info",
 "--log-encoding=json",
 "--enable-leader-election",
 "--no-cross-namespace-refs=true",
 "--no-remote-bases=true",
 "--default-service-account=default"]

helm-controller args:
[..., "--no-cross-namespace-refs=true"]

notification-controller args:
[..., "--no-cross-namespace-refs=true"]
```

### Kustomization Ready conditions post-Task-4 (peak suspend-window state)

- `kustomization/spoke-apps`: Ready=True (immediate — first poll iteration)
- `kustomization/spoke-ml`: Ready=True (immediate)
- `kustomization/flux-system`: Ready=True (immediate)
- `kustomization/poc-capsule`: applied during kubectl apply step (configured)
- `kustomization/poc-capsule-spoke`: unchanged from pre-patch state

### Post-flux-resume controller args (origin/main baseline restored)

```
kustomize-controller args:
["--events-addr=...",
 "--watch-all-namespaces=true",
 "--log-level=info",
 "--log-encoding=json",
 "--enable-leader-election"]
# (no lockdown flags — origin/main baseline)
```

The suspend+apply window held ~30s before resume; cluster diverged from origin/main during that window long enough to exercise the regression gate; flux resume converged back cleanly without state conflict.

## Next Phase Readiness

**Phase 9 ready to advance to Plan 09-04 (verifier).** Plan 09-04 inherits the regression gate via `tests/bats/tenants-12-live-health-check.bats` (calls `task health-check`). Phase 9 verifier may now execute.

**Suggested orchestrator handling:**

1. Mark Plan 09-03 as COMPLETED in STATE.md / ROADMAP.md (orchestrator owns those writes after worktree merge — execute-plan skipped them per worktree mode).
2. Trigger Plan 09-04 (Phase 9 verifier) via `/gsd-execute-plan`.
3. After Plan 09-04 verifier passes, Phase 9 closes; Phase 10 (Karpor) may begin.
4. D-08-13 push-gate deferral remains active until Phase 11 VAL-05 (push of cumulative tracked plans to origin/main).

**Forward-pointer:** All Plan 09-03 commits remain local on the worktree branch. Orchestrator merges worktree back to main (the worktree branch contains Plan 09-03's source-file changes; cluster runtime is at origin/main baseline post-flux-resume; static bats pass against worktree yaml). After merge, Plan 09-04 verifier runs against the merged tree; cluster is reconciled back to lockdown state by hub-flux's flux-system K when origin/main carries the patches block.

---

*Phase: 09-tenants-flux-multi-tenancy-lockdown*
*Plan: 03 (ATTEMPT 3 — COMPLETED)*
*Completed: 2026-04-30*

## Self-Check: PASSED

Verifications performed:

- [x] Task 0.5 commit `ea8d8a1` exists (git rev-parse confirms)
- [x] Task 1 commit `b7b9b01` exists
- [x] Task 2 commit `621e530` exists (atomic spoke DiD landing — 2 files, +2 lines)
- [x] Task 3 commit `a537e67` exists (RESEARCH.md CORRECTION 2 — 1 file, +29 lines, additive only)
- [x] Task 4 commit `d519b90` exists (atomic patches block + capsule escape hatch — 2 files, +51 lines)
- [x] Task 5 commit `37db011` exists (PASS chore commit, empty)
- [x] `clusters/hub-flux/spokes/spoke-apps.yaml` post-Task-2: yq returns `flux-reconciler` for spec.serviceAccountName; secretRef.name == spoke-apps-kubeconfig; secretRef.key == value.yaml; REQ-SPOKE-04/05 head comment preserved
- [x] `clusters/hub-flux/spokes/spoke-ml.yaml` post-Task-2: yq returns `flux-reconciler` for spec.serviceAccountName; secretRef.name == spoke-ml-kubeconfig; secretRef.key == value.yaml; REQ-SPOKE-04/05 head comment preserved
- [x] `clusters/hub-flux/flux-system/kustomization.yaml` post-Task-4: contains `# KARYON FLUX LOCKDOWN PATCHES (D-09-05 / TEN-05)` sentinel; FLUX PATCH SURFACE head + KARYON SPOKES MOUNT + KARYON POC MOUNT sentinels preserved verbatim; `value: --no-cross-namespace-refs=true` count is 3 (kc + hc + nc); `value: --no-remote-bases=true` + `value: --default-service-account=default` + `value: kustomize-controller` (escape hatch) all present
- [x] `clusters/hub-flux/pocs/capsule.yaml` post-Task-4: yq returns `kustomize-controller` for spec.serviceAccountName; yq returns `null` for spec.kubeConfig (D-08-12 invariant intact); D-09-05a comment block + D-08-12 head comment preserved
- [x] `.planning/phases/09-tenants-flux-multi-tenancy-lockdown/09-RESEARCH.md` post-Task-3: grep -c '### CORRECTION (Plan 09-03 attempt 1 falsifier' returns 2 (preserved verbatim); grep -c '### CORRECTION 2 (Plan 09-03 attempt 2 falsifier' returns 2 (newly appended); attempt-2 commit shas (0feb191, cd1cf32, d194031) cited; attempt-1 evidence chain (899f2fe, 9b6b3a5) preserved
- [x] `.planning/phases/09-tenants-flux-multi-tenancy-lockdown/09-03-SUMMARY.attempt-1-rollback.md` PRESERVED (NOT modified — separate file; attempt-1 archive intact)
- [x] `.planning/phases/09-tenants-flux-multi-tenancy-lockdown/09-03-SUMMARY.attempt-2-rollback.md` PRESERVED (NOT modified — separate file; attempt-2 archive intact)
- [x] `.planning/phases/09-tenants-flux-multi-tenancy-lockdown/09-03-SUMMARY.md` (this file) created with attempt-3 PASS path content
- [x] Live: post-Task-4 task health-check exit 0 (19/19 v0.18 assertions; controller args verified; spoke + flux-system + poc-capsule Ready=True)
- [x] Live: post-resume task health-check exit 0 (origin/main baseline restored; controller args back to baseline; no lockdown flags)
- [x] Static bats tenants-03-static-lockdown.bats 12/12 GREEN post-Task-4 (commit hash `d519b90`)
- [x] Static bats tenants-05-static-split-path.bats 4/4 GREEN post-Task-4
- [x] D-08-13 push-gate deferral honored throughout — no `git push` to origin/main during execution
- [x] No modifications to STATE.md / ROADMAP.md (orchestrator owns those writes after worktree merge per execute-plan worktree-mode auto-detection)
- [x] kubectl kustomize clusters/hub-flux/flux-system/ exits 0 post-Task-4 (no yaml syntax error; render valid)
- [x] All 6 plan task commits land in execution order with correct conventional-commit prefixes (chore/chore/feat/docs/feat/chore for tasks 0.5/1/2/3/4/5)
