---
phase: 03-flux-hub-bootstrap
plan: 06
subsystem: infra
tags: [flux, bats, live-destructive, gap-closure, human-verification]

requires:
  - phase: 03-flux-hub-bootstrap
    provides: Plans 03-05 CR-01/CR-02 fixes and the Phase 3 live destructive test contract
provides:
  - Live destructive proof that Flux bootstrap is idempotent on k3d-hub-flux
  - Captured TAP output proving the FLUX-04 + D-13 combined test ran and passed
  - Patch-surface marker present in clusters/hub-flux/flux-system/kustomization.yaml
  - Flux readiness evidence for the root flux-system Kustomization
affects: [03-flux-hub-bootstrap, 04-spoke-registration, 05-rebuild-health]

tech-stack:
  added: []
  patterns:
    - Human-gated destructive proof captured as TAP plus Flux readiness output
    - Live proof runner separates safe prechecks from destructive execution

key-files:
  created:
    - .planning/phases/03-flux-hub-bootstrap/03-06-SUMMARY.md
    - scripts/verify-flux-bootstrap-live.sh
  modified:
    - tests/bats/bootstrap-flux-01-idempotent.bats
    - clusters/hub-flux/flux-system/kustomization.yaml

key-decisions:
  - "Run the live destructive proof only after explicit human confirmation."
  - "Merge Flux bootstrap commits from origin/main into local main rather than resetting local planning/code history."

patterns-established:
  - "Live destructive verification scripts should print secret presence only, never secret values."
  - "Flux bootstrap remote commits must be reconciled into the local branch before patch-surface marker verification."

requirements-completed: [FLUX-04]

duration: human-checkpoint
completed: 2026-04-27
---

# Phase 03 Plan 06: Live Flux Bootstrap Proof Summary

**Human-gated live proof that `scripts/bootstrap-flux.sh` bootstraps Flux, preserves the patch surface, and reruns idempotently on `k3d-hub-flux`.**

## Performance

- **Duration:** human-checkpoint
- **Started:** 2026-04-26T20:00:00Z
- **Completed:** 2026-04-27T12:07:22Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- Confirmed the existing live/destructive Bats contract still matched the post-03-05 script behavior without changing the test body.
- Added a reusable live proof runner that performs safe prechecks, requires explicit destructive confirmation, and captures TAP to `/tmp/karyon-03-06-live.tap`.
- Ran the live destructive proof against `k3d-hub-flux`; all eight Bats tests passed, including the FLUX-04 + D-13 combined live test.
- Verified the patch-surface marker is present in `clusters/hub-flux/flux-system/kustomization.yaml`.
- Verified Flux is bootstrapped and the root `flux-system` Kustomization is `Ready=True`.

## Task Commits

1. **Task 1: Verify live/destructive @test contract against patched script** - `232fd0f` (docs)
2. **Support: Add live proof runner requested during checkpoint** - `2891e8c` (test)
3. **Live bootstrap reconciliation: merge Flux-generated manifests from origin/main** - `7312532` (merge)
4. **Task 2: Record live destructive proof and patch-surface marker evidence** - final summary commit

## Files Created/Modified

- `tests/bats/bootstrap-flux-01-idempotent.bats` - Records that the live contract was reviewed against the post-03-05 script.
- `scripts/verify-flux-bootstrap-live.sh` - Runs safe prechecks, human confirmation, live Bats proof, and readiness evidence capture.
- `clusters/hub-flux/flux-system/kustomization.yaml` - Contains the D-13 `# FLUX PATCH SURFACE` marker.
- `.planning/phases/03-flux-hub-bootstrap/03-06-SUMMARY.md` - Captures live verification evidence.

## Captured TAP Output

```text
1..8
ok 1 FLUX-01: scripts/bootstrap-flux.sh invokes flux bootstrap github
ok 2 FLUX-02: scripts/bootstrap-flux.sh hard-codes --path clusters/hub-flux (no env override)
ok 3 FLUX-03 / D-11: scripts/bootstrap-flux.sh uses set -euo pipefail and does NOT use set -x
ok 4 FLUX-03 / D-11 (token safety, broadened): $GITHUB_TOKEN never funneled through echo/printf/pass/info/warn/fail/tee
ok 5 D-07 / FLUX-04: scripts/bootstrap-flux.sh contains the exact skip-message literal
ok 6 D-13: scripts/bootstrap-flux.sh carries the FLUX PATCH SURFACE sentinel literal
ok 7 Phase-6 hand-off: scripts/bootstrap-flux.sh contains the gitleaks pre-commit advisory section
ok 8 FLUX-04 + D-13 (live/destructive, combined): bootstrap is idempotent AND patch-surface marker survives re-run
```

## Patch-Surface Marker Evidence

```text
# ──────────────────────────────────────────────────────────────────────────
# FLUX PATCH SURFACE
#
```

## Flux Kustomization Evidence

```text
NAMESPACE   NAME        REVISION           SUSPENDED READY MESSAGE
flux-system flux-system main@sha1:feafc20d False     True  Applied revision: main@sha1:feafc20d
```

## Flux Check Evidence

```text
► checking prerequisites
✔ Kubernetes 1.34.6+k3s1 >=1.33.0-0
► checking version in cluster
✔ distribution: flux-v2.8.6
✔ bootstrapped: true
► checking controllers
✔ helm-controller: deployment ready
► ghcr.io/fluxcd/helm-controller:v1.5.4
✔ kustomize-controller: deployment ready
► ghcr.io/fluxcd/kustomize-controller:v1.8.4
✔ notification-controller: deployment ready
► ghcr.io/fluxcd/notification-controller:v1.8.4
✔ source-controller: deployment ready
► ghcr.io/fluxcd/source-controller:v1.8.3
► checking crds
✔ alerts.notification.toolkit.fluxcd.io/v1beta3
✔ buckets.source.toolkit.fluxcd.io/v1
✔ externalartifacts.source.toolkit.fluxcd.io/v1
✔ gitrepositories.source.toolkit.fluxcd.io/v1
✔ helmcharts.source.toolkit.fluxcd.io/v1
✔ helmreleases.helm.toolkit.fluxcd.io/v2
✔ helmrepositories.source.toolkit.fluxcd.io/v1
✔ kustomizations.kustomize.toolkit.fluxcd.io/v1
✔ ocirepositories.source.toolkit.fluxcd.io/v1
✔ providers.notification.toolkit.fluxcd.io/v1beta3
✔ receivers.notification.toolkit.fluxcd.io/v1
✔ all checks passed
```

## Gap Closure Mapping

| Failed Truth from 03-VERIFICATION.md | Closure Evidence |
|--------------------------------------|------------------|
| Truth #1: root `flux-system` is `Ready=True` and hub self-manages from `clusters/hub-flux/**`. | `flux get kustomizations -A` reports `flux-system` `Ready=True`; `flux check` passes all controller and CRD checks. |
| Truth #3: first-run bootstrap completes locally and round-trips through `clusters/hub-flux/**`. | Flux bootstrap created the remote manifests, those commits were merged locally, and `clusters/hub-flux/flux-system/kustomization.yaml` now contains the patch-surface marker. |
| Truth #4: rerunning bootstrap after success is a no-op and exits 0. | TAP line `ok 8 FLUX-04 + D-13...` proves the script ran twice, exited 0 both times, observed the skip path, and preserved the marker. |

Plans 03-05 and 03-06 collectively close all three Phase 3 verification gaps: CR-01 local manifest sync, CR-02 data-only `.env` parsing, and Gap C live destructive idempotency proof.

## Decisions Made

- Kept the destructive operation human-gated; the helper script requires `RUN LIVE PROOF` unless `--yes` is passed.
- Reconciled Flux-generated remote commits with a normal merge because local `main` already had unpublished phase work and `git pull --ff-only` correctly refused to flatten divergent histories.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added live proof runner for checkpoint ergonomics**
- **Found during:** Human verification checkpoint
- **Issue:** The raw checkpoint commands were error-prone to retype and did not package the required evidence capture.
- **Fix:** Added `scripts/verify-flux-bootstrap-live.sh` with safe prechecks, explicit destructive confirmation, TAP capture, marker evidence, and Flux readiness output.
- **Files modified:** `scripts/verify-flux-bootstrap-live.sh`
- **Verification:** `bash -n`, `shellcheck -x`, and `--help` passed.
- **Committed in:** `2891e8c`

**2. [Rule 3 - Blocking] Reconciled Flux remote bootstrap commits before rerun proof**
- **Found during:** First live proof attempt
- **Issue:** The first live proof bootstrapped Flux successfully, but `git pull --ff-only origin main` failed because Flux had pushed two commits to `origin/main` while local `main` already had unpublished phase commits.
- **Fix:** Merged `origin/main` into local `main`, bringing in `gotk-components.yaml`, `gotk-sync.yaml`, and `kustomization.yaml` without resetting or losing local work.
- **Files modified:** `clusters/hub-flux/flux-system/*`
- **Verification:** Safe prechecks passed; second live proof passed all eight Bats tests.
- **Committed in:** `7312532`

---

**Total deviations:** 2 auto-fixed (2 Rule 3)
**Impact on plan:** Both were required to complete the human-gated live proof safely. No unrelated code behavior was changed.

## Issues Encountered

The first live proof attempt failed at Bats line 110 because the script exited non-zero after Flux successfully pushed remote manifests. Root cause: local `main` and `origin/main` diverged, so `git pull --ff-only origin main` correctly refused to proceed. Merging the Flux-generated remote commits into local `main` resolved the mismatch, and the rerun proof passed.

## User Setup Required

The proof has run. The local patch-surface marker is committed in this plan's final metadata commit; push local `main` when ready so GitHub contains the marker as part of the reconciled GitOps tree.

## Next Phase Readiness

Phase 3 is ready for re-verification. The hub has Flux controllers running, the root Kustomization is `Ready=True`, the patch-surface marker exists locally, and the live destructive idempotency proof passed.

## Self-Check: PASSED

- `grep -F 'ok 8 FLUX-04 + D-13 (live/destructive, combined)' /tmp/karyon-03-06-live.tap` passed.
- `grep -c '^not ok' /tmp/karyon-03-06-live.tap` returned `0`.
- `grep -F '# FLUX PATCH SURFACE' clusters/hub-flux/flux-system/kustomization.yaml` passed.
- `flux --context k3d-hub-flux get kustomizations -A` reports `flux-system` `Ready=True`.
- `flux --context k3d-hub-flux check` passed all checks.

---
*Phase: 03-flux-hub-bootstrap*
*Completed: 2026-04-27*
