---
phase: 04-spoke-registration
plan: 02
subsystem: manifests
tags: [flux, kustomize, spoke-registration, hub-spoke, yaml]

# Dependency graph
requires:
  - phase: 04-spoke-registration
    provides: Plan 04-01 static Bats contract for spoke registration artifacts
provides:
  - Hub-side Flux Kustomization manifests for spoke-ml and spoke-apps
  - Per-spoke seed Namespace and ConfigMap manifests for spoke-ml and spoke-apps
  - Static Bats SPOKE-05 manifest contract passing for hub and seed files
affects: [04-spoke-registration, 05-workloads-and-health, flux-reconciliation]

# Tech tracking
tech-stack:
  added: []
  patterns: [Flux v1 remote Kustomization, explicit spec.kubeConfig secretRef, per-spoke seed falsifier]

key-files:
  created:
    - clusters/hub-flux/spokes/kustomization.yaml
    - clusters/hub-flux/spokes/spoke-ml.yaml
    - clusters/hub-flux/spokes/spoke-apps.yaml
    - clusters/spoke-ml/kustomization.yaml
    - clusters/spoke-ml/namespace.yaml
    - clusters/spoke-ml/configmap.yaml
    - clusters/spoke-apps/kustomization.yaml
    - clusters/spoke-apps/namespace.yaml
    - clusters/spoke-apps/configmap.yaml
  modified:
    - tests/bats/register-spokes-01-static.bats

key-decisions:
  - "Hub-side spoke Kustomizations keep the full spec.kubeConfig block as the primary P18 defense; key: value.yaml remains pinned as defense in depth."
  - "Both spokes use ConfigMap name karyon-spoke-id, while namespace and data.spoke differ to preserve the cross-cluster falsifier."

patterns-established:
  - "Flux remote-cluster Kustomization YAMLs live under clusters/hub-flux/spokes/ and reference spoke seed trees by spec.path."
  - "Spoke seed trees start with a minimal Namespace plus ConfigMap kustomization that Phase 5 can extend."

requirements-completed: [SPOKE-04, SPOKE-05]

# Metrics
duration: 4min
completed: 2026-04-27
---

# Phase 04 Plan 02: Spoke GitOps Manifest Summary

**Static hub-spoke GitOps source of truth with explicit Flux kubeConfig refs and per-spoke falsifier seed manifests.**

## Performance

- **Duration:** 4 min
- **Started:** 2026-04-27T18:22:16Z
- **Completed:** 2026-04-27T18:26:18Z
- **Tasks:** 3
- **Files modified:** 10

## Accomplishments

- Created `clusters/hub-flux/spokes/` with a kustomize index and two Flux v1 `Kustomization` CRs, each pinned to `spec.kubeConfig.secretRef.{name,key}` with `key: value.yaml`.
- Created minimal `clusters/spoke-ml/` and `clusters/spoke-apps/` seed trees containing one Namespace and one `karyon-spoke-id` ConfigMap per spoke.
- Verified the cross-cluster falsifier shape: both ConfigMaps use the same name, while namespaces and `data.spoke` values are distinct.

## Task Commits

Each task was committed atomically:

1. **Task 1: Create hub-side spokes Kustomizations** - `b6fc32d` (feat)
2. **Task 2: Create spoke-ml seed tree** - `2cdc4e2` (feat)
3. **Task 3: Create spoke-apps seed tree** - `4b4a11c` (feat)

## Files Created/Modified

- `clusters/hub-flux/spokes/kustomization.yaml` - 5-line kustomize index listing `spoke-ml.yaml` and `spoke-apps.yaml`.
- `clusters/hub-flux/spokes/spoke-ml.yaml` - 28-line Flux v1 Kustomization for `./clusters/spoke-ml` via `spoke-ml-kubeconfig`.
- `clusters/hub-flux/spokes/spoke-apps.yaml` - 22-line Flux v1 Kustomization for `./clusters/spoke-apps` via `spoke-apps-kubeconfig`.
- `clusters/spoke-ml/kustomization.yaml` - 5-line seed index for namespace and configmap.
- `clusters/spoke-ml/namespace.yaml` - 7-line `karyon-spoke-ml` Namespace.
- `clusters/spoke-ml/configmap.yaml` - 11-line `karyon-spoke-id` ConfigMap with `spoke: spoke-ml`.
- `clusters/spoke-apps/kustomization.yaml` - 5-line seed index mirroring `spoke-ml`.
- `clusters/spoke-apps/namespace.yaml` - 7-line `karyon-spoke-apps` Namespace.
- `clusters/spoke-apps/configmap.yaml` - 11-line `karyon-spoke-id` ConfigMap with `spoke: spoke-apps`.
- `tests/bats/register-spokes-01-static.bats` - Fixed one Bats yq assertion so the spokes index resources are checked semantically.

## Verification

- `find clusters/hub-flux/spokes clusters/spoke-ml clusters/spoke-apps -type f -name '*.yaml' | wc -l` -> `9`
- `kubectl --context k3d-hub-flux kustomize clusters/hub-flux/spokes/ | grep -c '^apiVersion: kustomize.toolkit.fluxcd.io/v1'` -> `2`
- `kubectl --context k3d-hub-flux apply --dry-run=client -k clusters/hub-flux/spokes` -> dry-run created `spoke-apps` and `spoke-ml` Kustomizations
- `kubectl --context k3d-hub-flux apply --dry-run=client -k clusters/spoke-ml` -> dry-run created `karyon-spoke-ml` Namespace and `karyon-spoke-id` ConfigMap
- `kubectl --context k3d-hub-flux apply --dry-run=client -k clusters/spoke-apps` -> dry-run created `karyon-spoke-apps` Namespace and `karyon-spoke-id` ConfigMap
- `kubectl --context k3d-spoke-ml apply --dry-run=client -f clusters/spoke-ml/namespace.yaml` -> created (dry run)
- `kubectl --context k3d-spoke-ml apply --dry-run=client -f clusters/spoke-ml/configmap.yaml` -> created (dry run)
- `kubectl --context k3d-spoke-apps apply --dry-run=client -f clusters/spoke-apps/namespace.yaml` -> created (dry run)
- `kubectl --context k3d-spoke-apps apply --dry-run=client -f clusters/spoke-apps/configmap.yaml` -> created (dry run)
- `bats tests/bats/register-spokes-01-static.bats -f 'SPOKE-05' --tap` -> `1..5`, all 5 passed
- `bats tests/bats/register-spokes-01-static.bats --tap` -> 10 passed, 14 failed closed as expected for later plans
- `grep -R -n -E 'serviceAccountName|targetNamespace' clusters/hub-flux/spokes clusters/spoke-ml clusters/spoke-apps` -> no matches
- Secret-material scan found only safe comments and kubeconfig Secret names, not token or certificate data.

## Bats Posture

This plan flipped the manifest-owned static checks green:

- SPOKE-04 per-spoke `key: value.yaml` checks for `spoke-ml.yaml` and `spoke-apps.yaml`
- SPOKE-05 hub Kustomization shape checks for `spoke-ml.yaml`, `spoke-apps.yaml`, and the spokes index
- SPOKE-05 seed checks for `clusters/spoke-ml/` and `clusters/spoke-apps/`

Still failing closed for later plans:

- SPOKE-01, SPOKE-02, SPOKE-03, D-11, D-04, D-07/D-13, and D-15 wait for Plan 04-03's `scripts/register-spokes-for-flux.sh`.
- D-02 waits for Plan 04-04's `# KARYON SPOKES MOUNT` patch in `clusters/hub-flux/flux-system/kustomization.yaml`.
- DOCS-03 stub removal and REPO-05 Taskfile entry wait for Plan 04-04.

## Decisions Made

- Followed the plan's P18 reframe: `spec.kubeConfig` block omission is the silent-misroute risk, so both Flux Kustomizations include the complete block plus explicit `key: value.yaml`.
- Kept spoke seed manifests minimal: Namespace plus falsifier ConfigMap only, leaving Phase 5 room to add workload resources beside them.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed static yq array assertion for spokes index**
- **Found during:** Task 1 (Create hub-side spokes Kustomizations)
- **Issue:** `yq eval '.resources == ["spoke-ml.yaml", "spoke-apps.yaml"]'` returned `false` under mikefarah yq v4.53.2 even when the parsed array contained the expected two entries.
- **Fix:** Replaced the array-literal equality with length plus indexed element checks.
- **Files modified:** `tests/bats/register-spokes-01-static.bats`
- **Verification:** `bats tests/bats/register-spokes-01-static.bats -f 'SPOKE-05: clusters/hub-flux' --tap` passed 3/3; full `SPOKE-05` filter passed 5/5 after all tasks.
- **Committed in:** `b6fc32d` (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 bug)
**Impact on plan:** The fix was required for the existing static contract to test the implemented YAML correctly. No behavioral scope was added.

## Issues Encountered

- Full static Bats remains red by design until Plans 04-03 and 04-04 land the script, patch sentinel, docs fill, and Taskfile entry.

## Known Stubs

None. Stub-pattern scan only matched a test comment describing the literal bash `${spoke}` placeholder; it is not a functional stub.

## Auth Gates

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Plan 04-03 can now treat these manifests as the canonical static source of truth while implementing the registration script and hub Secret creation. Plan 04-04 should wire `clusters/hub-flux/spokes/` into the root Flux tree, fill the docs stub, and add the Taskfile hand-off.

---
*Phase: 04-spoke-registration*
*Completed: 2026-04-27*

## Self-Check: PASSED

- Found created files: `clusters/hub-flux/spokes/kustomization.yaml`, `clusters/hub-flux/spokes/spoke-ml.yaml`, `clusters/hub-flux/spokes/spoke-apps.yaml`, `clusters/spoke-ml/kustomization.yaml`, `clusters/spoke-ml/namespace.yaml`, `clusters/spoke-ml/configmap.yaml`, `clusters/spoke-apps/kustomization.yaml`, `clusters/spoke-apps/namespace.yaml`, `clusters/spoke-apps/configmap.yaml`, `.planning/phases/04-spoke-registration/04-02-SUMMARY.md`
- Found task commits: `b6fc32d`, `2cdc4e2`, `4b4a11c`
