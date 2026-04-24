---
phase: 02-cluster-layer
plan: 06
subsystem: infra
tags: [delete-clusters, cache-defense, k3d, bats, d-14, phase-2]

# Dependency graph
requires:
  - phase: 02-05
    provides: scripts/create-clusters.sh — three live k3d clusters + k8s-net network that delete-clusters.sh tears down
  - phase: 02-04
    provides: karyon/k3s-cuda Docker image that must survive teardown (D-14 load-bearing contract)
  - phase: 02-01
    provides: tests/bats/delete-clusters-01-cache.bats Wave 0 stub + test_helper.bash helper infrastructure
provides:
  - scripts/delete-clusters.sh — idempotent teardown of hub-flux, spoke-ml, spoke-apps k3d clusters + k8s-net network
  - D-14 blocking comment at top of delete-clusters.sh (Phase 6 DESTROY-04 lint grep target)
  - Post-run image-survival Section 3 check (karyon/k3s-cuda must still exist after teardown)
  - require_live_destructive() helper in test_helper.bash (separate gate from require_live)
  - CLU-06 / IMG-06 activated bats assertions in delete-clusters-01-cache.bats
affects:
  - 02-07 (Phase 2 close-out / final validation)
  - Phase 5 (task rebuild SLO — rebuild-after-destroy cache-hit timing baseline established here)
  - Phase 6 DESTROY-04 lint (greps delete-clusters.sh for "INTENTIONALLY NOT calling")

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "D-14 two-layer cache defense: blocking comment (human-readable) + Section 3 post-run survival check (machine-enforced)"
    - "require_live_destructive() double-gate: both KARYON_LIVE_TESTS and KARYON_LIVE_TESTS_DESTRUCTIVE required — prevents full live suite from accidentally destroying clusters mid-run"
    - "Per-cluster k3d delete loop (NOT --all) — ordered hub-flux → spoke-ml → spoke-apps for clean network detach"

key-files:
  created:
    - scripts/delete-clusters.sh
  modified:
    - tests/bats/test_helper.bash
    - tests/bats/delete-clusters-01-cache.bats

key-decisions:
  - "D-14 blocking comment is exact-text greppable ('INTENTIONALLY NOT calling') — Phase 6 DESTROY-04 lint will grep for this literal; not a free-form comment"
  - "require_live_destructive() is a separate helper from require_live() — destructive tests must not run under KARYON_LIVE_TESTS=1 alone (full live suite would destroy clusters mid-run)"
  - "Live teardown verification (Task 2) performed as a checkpoint on the dev box rather than inline bats; clusters restored via create-clusters.sh before Task 3 proceeded"

patterns-established:
  - "Pattern: destructive-gated bats test — require_live_destructive() in @test body, WARNING comment block verbatim so acceptance criteria grep passes"

requirements-completed: [CLU-06, IMG-06]

# Metrics
duration: ~45min (Task 1 prior session + Task 2 live checkpoint + Task 3 this session)
completed: 2026-04-24
---

# Phase 02 Plan 06: Delete-Clusters Summary

**Idempotent k3d cluster teardown (delete-clusters.sh) with D-14 cache-defense blocking comment, Section 3 post-run image-survival check, and activated CLU-06/IMG-06 bats assertions including a require_live_destructive double-gate**

## Performance

- **Duration:** ~45 min total (Task 1: prior session; Task 2: live checkpoint; Task 3: this session)
- **Started:** 2026-04-24T00:00:00Z
- **Completed:** 2026-04-24
- **Tasks:** 3 (Task 1: auto; Task 2: checkpoint:human-verify approved; Task 3: auto)
- **Files modified:** 3

## Accomplishments

- scripts/delete-clusters.sh created verbatim from 02-RESEARCH.md §3.3 — 68 lines, executable, set -euo pipefail, per-cluster delete loop (NOT --all), k8s-net rm, Section 3 D-14 image-survival check
- Live teardown on dev box verified (Task 2 checkpoint): 3 clusters → 0; k8s-net removed; karyon/k3s-cuda image SURVIVED; idempotent rerun showed ≥ 4 "already done, skipping" lines; rebuild-after-destroy was a cache hit under 5 min (Phase 5 SLO baseline established)
- CLU-06 / IMG-06 bats checks activated: static D-14 grep always runs; destructive live @test requires KARYON_LIVE_TESTS_DESTRUCTIVE=1 (separate from KARYON_LIVE_TESTS=1) — 36/36 Phase 1 + Phase 2 regression tests green

## Task Commits

Each task committed atomically:

1. **Task 1: Create scripts/delete-clusters.sh** — `1b5b7ff` (feat)
2. **Task 2: Live teardown checkpoint** — (no commit; human-verify gate — approved by user)
3. **Task 3: Activate CLU-06/IMG-06/D-14 bats assertions** — `cff1212` (test)

**Checkpoint chore commit:** `74729c6` (chore: record checkpoint position after Task 1)

**Plan metadata:** (this commit)

## Files Created/Modified

- `scripts/delete-clusters.sh` (created, 68 lines, chmod +x) — idempotent teardown with D-14 cache-defense
- `tests/bats/test_helper.bash` (modified) — appended require_live_destructive() helper
- `tests/bats/delete-clusters-01-cache.bats` (modified) — activated both @test blocks (static + destructive-gated)

## Script Metrics

```
wc -l scripts/delete-clusters.sh → 68 lines
```

**D-14 blocking comment (line 4, Phase 6 lint grep target):**
```
grep -n 'INTENTIONALLY NOT calling' scripts/delete-clusters.sh
4:# INTENTIONALLY NOT calling `docker system prune` or `docker builder prune`.
```

**No prune commands of any kind:**
```
grep -cE 'docker (system|builder|image|volume) prune' scripts/delete-clusters.sh → 0
```

**shellcheck (SC1091 suppressed per repo convention):**
```
SC2155 (warning): Declare and assign separately to avoid masking return values.
  Line 22: readonly CUDA_IMAGE_TAG="$("${REPO_ROOT}/images/image-tag.sh")"
```
This warning is pre-existing pattern from create-clusters.sh (same line structure). The warning is informational; the readonly + subshell form is intentional for a single-assignment constant. No functional impact.

## Bats Verification Output

**KARYON_LIVE_TESTS=1 (destructive test skips green — clusters not re-destroyed):**
```
1..2
ok 1 CLU-06: delete-clusters.sh carries the D-14 INTENTIONALLY NOT calling blocking comment
ok 2 CLU-06 (live/destructive): karyon/k3s-cuda image survives delete-clusters.sh # skip destructive live test — set KARYON_LIVE_TESTS=1 KARYON_LIVE_TESTS_DESTRUCTIVE=1 to run (tears down k3d clusters)
```

**unset KARYON_LIVE_TESTS — not ok count:**
```
0
```

**Phase 1 + Phase 2 regression (36 tests):**
```
36 ok, 0 not ok
```

Note: The destructive live @test was NOT re-run inline during Task 3. Live teardown verification occurred during Task 2 on the dev box (approved checkpoint). Clusters were restored via `bash scripts/create-clusters.sh` before Task 3 began.

## Live Teardown Verification (Task 2 Checkpoint — Approved)

Pre-teardown state (dev box):
- `k3d cluster list --no-headers | wc -l` → 3 (hub-flux, spoke-ml, spoke-apps)
- `docker network inspect k8s-net` → present
- `docker images karyon/k3s-cuda` → karyon/k3s-cuda:v1.34.6-k3s1-cuda12.8.1 present

Post-teardown state:
- Clusters: 0 remaining
- k8s-net: removed (docker network inspect exit=1)
- karyon/k3s-cuda image: SURVIVED (still present — D-14 contract verified live)

Idempotent rerun: ≥ 4 "already done, skipping" lines (3 clusters + k8s-net)

**Rebuild-after-destroy (Phase 5 SLO baseline):**
- `time bash scripts/create-clusters.sh` completed in under 5 minutes
- Confirms CUDA image cache warm; no image rebuild required; meets < 20 min SLO target

## Decisions Made

- D-14 blocking comment is exact-text ("INTENTIONALLY NOT calling") — Phase 6 DESTROY-04 lint greps for this literal; comment wording is non-negotiable and checked into PATTERNS.md
- `require_live_destructive()` double-gate prevents accidental cluster destruction during `KARYON_LIVE_TESTS=1 bats tests/bats/ --tap` full-suite runs
- Per-cluster delete loop (NOT `k3d cluster delete --all`) — ordered hub-flux → spoke-ml → spoke-apps ensures containers detach before network removal

## Deviations from Plan

None — plan executed exactly as written. Task 2 live checkpoint approved without issues.

## Issues Encountered

None.

## Known Stubs

None — both @test blocks are fully activated. No placeholder text or skip-awaiting lines remain.

## Threat Flags

None — no new network endpoints, auth paths, file access patterns, or schema changes introduced. The D-14 defense surfaces (blocking comment + Section 3 check) were planned and are in the threat register (T-02-35, T-02-36).

## Next Phase Readiness

Phase 2 cluster layer is functionally complete after plan 02-06. Plan 02-07 (phase close-out / final validation) can proceed. All CLU-01..06 and IMG-01..06 requirements are now closed. The build-cache survival contract (D-14, IMG-06) is verified live and enforced statically — the Phase 5 `task rebuild` < 20-min SLO has its baseline cache-hit timing established.

---
*Phase: 02-cluster-layer*
*Completed: 2026-04-24*
