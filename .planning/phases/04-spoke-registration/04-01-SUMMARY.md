---
phase: 04-spoke-registration
plan: 01
subsystem: testing
tags: [bats, flux, spoke-registration, tdd-scaffold, k3d]

# Dependency graph
requires:
  - phase: 03-flux-hub-bootstrap
    provides: hub Flux bootstrap, flux-system patch surface, and shared bats helpers
provides:
  - Static Bats contract for Phase 4 spoke registration artifacts
  - Live/destructive Bats contract for post-push spoke reconciliation proof
  - Pinned inventory ID, P18, token-safety, TLS, wget, and node-name assertions
affects: [04-spoke-registration, 05-workloads-and-health, 06-docs-and-repo-hygiene]

# Tech tracking
tech-stack:
  added: []
  patterns: [bats static contract, require_live_destructive gated live contract, fail-closed TDD scaffold]

key-files:
  created:
    - tests/bats/register-spokes-01-static.bats
    - tests/bats/register-spokes-02-live.bats
  modified: []

key-decisions:
  - "Phase 4 P18 contract treats omitted spec.kubeConfig as the real silent-misroute risk; value.yaml remains pinned as defense in depth."
  - "Live in-pod probes use openssl for CA/TLS proof and busybox wget for auth/node identity because the kustomize-controller image lacks kubectl."
  - "The live suite centralizes its destructive env gate in setup() and skips local-only or unpushed Phase 4 state."

patterns-established:
  - "Static Bats files can intentionally fail closed while later plans land the contracted artifacts."
  - "Live destructive Bats suites should skip without KARYON_LIVE_TESTS and KARYON_LIVE_TESTS_DESTRUCTIVE, then detect uncommitted and unpushed reconciliation-tree changes."

requirements-completed: [SPOKE-01, SPOKE-02, SPOKE-03, SPOKE-04, SPOKE-05, SPOKE-06]

# Metrics
duration: 5min
completed: 2026-04-27
---

# Phase 4 Plan 1: Spoke Registration Test Scaffold Summary

**Bats contracts for spoke-registration TDD, covering static artifact shape plus gated live reconciliation proof.**

## Performance

- **Duration:** 5 min
- **Started:** 2026-04-27T18:13:39Z
- **Completed:** 2026-04-27T18:18:18Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Created `tests/bats/register-spokes-01-static.bats` with 24 static @tests pinning SPOKE-01..06 literals, D-02 sentinel wiring, D-04 no-git-mutation, D-11 token safety, D-13/D-14 probe literals, D-15 P18 node-name proof, docs, Taskfile, and seed manifests.
- Created `tests/bats/register-spokes-02-live.bats` with 18 live/destructive @tests covering hub Secret decode, spoke RBAC, token Secret population, Kustomization Ready status, inventory ID double-underscore format, cross-cluster ConfigMap falsifiers, openssl TLS proof, wget `/readyz`, and node-name proof.
- Preserved Wave 0 posture: no live state was mutated; static checks fail closed until Plans 04-02, 04-03, and 04-04 land their artifacts; live checks skip cleanly without destructive env gates.

## Task Commits

Each task was committed atomically:

1. **Task 1: Static spoke registration contract** - `3422d4d` (test)
2. **Task 2: Live spoke registration contract** - `c4760f9` (test)

## Files Created/Modified

- `tests/bats/register-spokes-01-static.bats` - Local-only static/yq contract for script, hub Kustomization YAMLs, spoke seed manifests, doc, Taskfile, and patch sentinel.
- `tests/bats/register-spokes-02-live.bats` - Destructive live contract gated by env vars, with push-state skip guards and post-push reconciliation proof.

## Verification

- `bats --count tests/bats/register-spokes-01-static.bats && bats --count tests/bats/register-spokes-02-live.bats` -> `24`, `18`
- `bats tests/bats/register-spokes-01-static.bats --tap 2>&1 | head -3` -> TAP header `1..24`, then expected `not ok` lines
- `bats tests/bats/register-spokes-02-live.bats --tap` without env vars -> 18 skipped tests
- `bats tests/bats/register-spokes-01-static.bats --tap 2>&1 | grep -c '^not ok'` -> `22` expected fail-closed assertions
- `grep -c -F 'karyon-spoke-ml_karyon-spoke-id__ConfigMap' tests/bats/register-spokes-02-live.bats` -> `3`
- `grep -c -F 'wget' tests/bats/register-spokes-02-live.bats` -> `4`
- `grep -c -F 'openssl s_client' tests/bats/register-spokes-02-live.bats` -> `2`

## TDD Posture

- Static suite: 24 @tests, 22 currently fail closed because `scripts/register-spokes-for-flux.sh`, hub-side spoke Kustomizations, spoke seed manifests, Taskfile entry, patch sentinel, and final docs are not all present yet.
- Live suite: 18 @tests, all skip cleanly without `KARYON_LIVE_TESTS=1 KARYON_LIVE_TESTS_DESTRUCTIVE=1`.
- No live cluster commands ran beyond the skipped Bats harness path.

## Hand-Off

- Plan 04-02 should flip the hub-side Kustomization YAML and spoke seed-manifest assertions green.
- Plan 04-03 should flip the script, RBAC, token-safety, wget, openssl, and node-name proof static assertions green.
- Plan 04-04 should flip the `# KARYON SPOKES MOUNT`, docs, and Taskfile hand-off assertions green.
- The live suite should only pass after the registration script has run, the Phase 4 artifacts are committed and pushed, and Flux has reconciled.

## Decisions Made

- Followed RESEARCH.md's P18 reframe: the real silent misroute is omitted `spec.kubeConfig`; explicit `key: value.yaml` remains pinned as a defense-in-depth contract.
- Encoded the D-14 adjustment: in-pod CA/TLS proof uses `openssl s_client`; auth and node identity use busybox `wget` because the controller image does not include kubectl.
- Kept the live gate centralized in `setup()` so the destructive suite has one clear opt-in path and all tests skip uniformly when env vars are absent.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None. The one stub-pattern scan hit was the word "placeholder" in a comment describing the literal `${spoke}` placeholder; it is not a functional stub.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Plan 04-02 can now implement the hub-side manifest and spoke seed files against a fixed static contract. Plan 04-03 can implement the registration script against the pinned token-safety, no-auto-push, TLS, auth, and P18 probe assertions.

## Self-Check: PASSED

- Found created files: `tests/bats/register-spokes-01-static.bats`, `tests/bats/register-spokes-02-live.bats`, `.planning/phases/04-spoke-registration/04-01-SUMMARY.md`
- Found task commits: `3422d4d`, `c4760f9`

---
*Phase: 04-spoke-registration*
*Completed: 2026-04-27*
