---
phase: 05-workloads-health-rebuild
plan: 02
subsystem: infra
tags: [examples, gitops, flux, kustomize, gpu-smoke]

# Dependency graph
requires:
  - phase: 04-spoke-registration
    provides: Existing spoke-apps and spoke-ml Flux Kustomizations with remote kubeConfig wiring.
  - phase: 05-workloads-health-rebuild
    provides: Plan 05-01 Wave 0 Bats contracts for deploy examples and Kustomize builds.
provides:
  - Canonical podinfo and GPU smoke example manifests under examples/.
  - Relative spoke Kustomize references from clusters/spoke-apps and clusters/spoke-ml into examples/.
  - GitOps-only deploy-examples script and Taskfile task with Git visibility gate, source refresh, bounded waits, and GPU log proof.
affects: [05-workloads-health-rebuild, deploy-examples, health-check, rebuild, phase5]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Canonical examples referenced from spoke Kustomizations with local kubectl kustomize build gates.
    - Flux deploy script checks Git visibility before reconcile because Flux reads origin/main.
    - Stable GPU smoke Job rerun is limited to deleting gpu-smoke/nvidia-smi.

key-files:
  created:
    - examples/podinfo/kustomization.yaml
    - examples/podinfo/namespace.yaml
    - examples/podinfo/deployment.yaml
    - examples/podinfo/service.yaml
    - examples/gpu-smoke-test/kustomization.yaml
    - examples/gpu-smoke-test/namespace.yaml
    - examples/gpu-smoke-test/job.yaml
    - scripts/deploy-examples.sh
  modified:
    - clusters/spoke-apps/kustomization.yaml
    - clusters/spoke-ml/kustomization.yaml
    - Taskfile.yml

key-decisions:
  - "Plan 05-02 keeps examples/ as the canonical workload source and uses relative Kustomize resources from the existing spoke trees."
  - "deploy-examples fails before Flux reconcile when examples/ or clusters/ are dirty or local HEAD differs from origin/main."
  - "Flux source refresh precedes spoke Kustomization reconciliation; the script guards the source-git --with-source flag for Flux CLI compatibility."

patterns-established:
  - "Git visibility gate: check git status --short on Flux-watched paths and compare HEAD to origin/main before reconcile."
  - "Kustomize traversal proof: run kubectl kustomize and the deploy-examples build Bats suite after adding ../../examples resources."
  - "GPU smoke rerun: delete only gpu-smoke/nvidia-smi before reconciling GitOps state."

requirements-completed: [DEP-01, DEP-02, DEP-03, DEP-04]

# Metrics
duration: 5 min
completed: 2026-04-28
---

# Phase 05 Plan 02: Example Manifests and Deploy Script Summary

**GitOps-only podinfo and GPU smoke deployment with canonical examples, relative spoke wiring, and Flux visibility gates**

## Performance

- **Duration:** 5 min
- **Started:** 2026-04-28T15:20:54Z
- **Completed:** 2026-04-28T15:26:02Z
- **Tasks:** 3
- **Files modified:** 11

## Accomplishments

- Added canonical `examples/podinfo/` and `examples/gpu-smoke-test/` manifests with pinned public image tags.
- Wired the existing `clusters/spoke-apps` and `clusters/spoke-ml` Kustomizations to those examples using `../../examples/*` resources.
- Added `scripts/deploy-examples.sh` and `task deploy-examples` with static manifest checks, HIGH-3 Git visibility checks, Flux source refresh, spoke reconciliation, bounded waits, and GPU log proof.

## Task Commits

Each task was committed atomically:

1. **Task 1: Add canonical example manifests** - `2747c2f` (feat)
2. **Task 2: Wire examples into spoke Kustomizations + verify kubectl kustomize build** - `c38f4f4` (feat)
3. **Task 3: Add scripts/deploy-examples.sh and Taskfile entry** - `8b81aeb` (feat)

## Files Created/Modified

- `examples/podinfo/kustomization.yaml` - Kustomize entrypoint for podinfo namespace, deployment, and service.
- `examples/podinfo/namespace.yaml` - `podinfo` Namespace.
- `examples/podinfo/deployment.yaml` - `podinfo` Deployment pinned to `ghcr.io/stefanprodan/podinfo:6.7.1`.
- `examples/podinfo/service.yaml` - ClusterIP service exposing port 9898.
- `examples/gpu-smoke-test/kustomization.yaml` - Kustomize entrypoint for GPU smoke namespace and Job.
- `examples/gpu-smoke-test/namespace.yaml` - `gpu-smoke` Namespace.
- `examples/gpu-smoke-test/job.yaml` - Stable `gpu-smoke/nvidia-smi` Job pinned to `nvcr.io/nvidia/cuda:12.8.0-base-ubuntu22.04`.
- `clusters/spoke-apps/kustomization.yaml` - Adds `../../examples/podinfo` while preserving Phase 4 seed resources.
- `clusters/spoke-ml/kustomization.yaml` - Adds `../../examples/gpu-smoke-test` while preserving Phase 4 seed resources.
- `scripts/deploy-examples.sh` - GitOps-only deploy script with Git visibility gate, source refresh, reconcile, waits, and log proof.
- `Taskfile.yml` - Adds `deploy-examples`.

## Decisions Made

- Kept the existing one-Flux-Kustomization-per-spoke model; no new hub-side workload Kustomizations were added.
- Used a deploy-time Git visibility gate rather than relying on later live verification, because Flux reconciles pushed `origin/main` state rather than the working tree.
- Kept the GPU smoke rerun mutation narrow: only `kubectl --context k3d-spoke-ml -n gpu-smoke delete job nvidia-smi --ignore-not-found --wait=true`.

## Verification

- `bash -n scripts/deploy-examples.sh` -> passed.
- `bats tests/bats/deploy-examples-01-static.bats` -> 17 tests passed.
- `bats tests/bats/deploy-examples-02-kustomize-build.bats` -> 2 tests passed.
- `kubectl kustomize clusters/spoke-apps` -> passed and includes `kind: Deployment` / `name: podinfo`.
- `kubectl kustomize clusters/spoke-ml` -> passed and includes `kind: Job` / `name: nvidia-smi`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Guarded unsupported Flux source-git flag**
- **Found during:** Task 3 (Add scripts/deploy-examples.sh and Taskfile entry)
- **Issue:** Local `flux v2.8.6` help shows `flux reconcile source git` does not support `--with-source`; running the exact planned source command would fail before any workload reconcile.
- **Fix:** `scripts/deploy-examples.sh` checks the CLI help and uses the pinned `--with-source` source command only if supported; otherwise it runs the valid `flux --context k3d-hub-flux reconcile source git flux-system` command. Source refresh still precedes both spoke Kustomization reconciles.
- **Files modified:** `scripts/deploy-examples.sh`
- **Verification:** `flux reconcile source git --help`, `bash -n scripts/deploy-examples.sh`, `bats tests/bats/deploy-examples-01-static.bats`, and source-before-spoke line ordering checks.
- **Committed in:** `8b81aeb`

---

**Total deviations:** 1 auto-fixed (Rule 1).
**Impact on plan:** Correctness-only adjustment for the installed Flux CLI; the GitOps source-refresh behavior and static ordering contract remain intact.

## Issues Encountered

- The first Task 3 Bats run failed because `git -C "${REPO_ROOT}" status --short` did not contain the exact `git status --short` literal pinned by the HIGH-3 static contract. The script now runs that command from `REPO_ROOT`, and the suite passes.
- `roadmap.update-plan-progress` reported success but did not update the Phase 5 progress table row, so `ROADMAP.md` was updated manually from `1/6` to `2/6`.

## Known Stubs

None.

## Authentication Gates

None.

## User Setup Required

None for this plan. Running `task deploy-examples` later still requires the GitOps state to be committed and pushed so `HEAD == origin/main`, by design.

## Next Phase Readiness

Ready for Plan 05-03. The example workloads and deploy task are in place; upcoming health and rebuild work can rely on `podinfo` and `gpu-smoke/nvidia-smi` as the workload proof targets.

## Self-Check: PASSED

- Confirmed SUMMARY and all created/modified plan files exist on disk.
- Confirmed task commits `2747c2f`, `c38f4f4`, and `8b81aeb` exist in git history.
- Re-ran plan verification: `bash -n`, both deploy-example Bats suites, and both `kubectl kustomize` builds passed.

---
*Phase: 05-workloads-health-rebuild*
*Completed: 2026-04-28*
