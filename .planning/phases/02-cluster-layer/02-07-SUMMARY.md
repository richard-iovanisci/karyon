---
phase: 02-cluster-layer
plan: "07"
subsystem: infra
tags: [taskfile, go-task, task-runner, phase-2, wave-4]

requires:
  - phase: 02-cluster-layer/02-04
    provides: scripts/build-image.sh (IMG-01..06)
  - phase: 02-cluster-layer/02-05
    provides: scripts/create-clusters.sh (CLU-01..05)
  - phase: 02-cluster-layer/02-06
    provides: scripts/delete-clusters.sh (CLU-06, D-14)

provides:
  - Taskfile.yml at repo root — go-task v3 stub exposing build-image, create-clusters, delete-clusters
  - Phase 2 scripts consumable via `task` CLI surface

affects:
  - 03-flux-bootstrap (will extend Taskfile.yml with bootstrap-flux task)
  - 04-spoke-registration (will extend Taskfile.yml with register-spokes task)
  - 05-operations (will extend Taskfile.yml with destroy/rebuild/health-check tasks)
  - 06-repo-hardening (REPO-05 full audit/reorganization of Taskfile.yml)

tech-stack:
  added: [go-task v3.50.0 (via .tool-versions asdf pin)]
  patterns:
    - Taskfile delegates to scripts/*.sh — never the reverse (REPO-05 architectural lock)
    - One-liner cmds per task — no deps/preconditions/vars in Phase 2 stub
    - Each task desc cites REQ-IDs for reverse traceability

key-files:
  created:
    - Taskfile.yml
  modified: []

key-decisions:
  - "Stub minimum three tasks now (Phase 2 usability) — Phase 6 REPO-05 owns full audit (CONTEXT.md Claude's Discretion + RESEARCH.md §7 OQ-2)"
  - "bash explicit in cmds (not ./scripts/*.sh) — makes bash dependency visible and avoids executable-bit drift"
  - "No premature tasks (destroy/rebuild/health-check/etc.) — strict Phase 5/6 ownership boundary"

patterns-established:
  - "Taskfile.yml at repo root — single entry point for all task commands"
  - "Task desc cites REQ-IDs — reverse traceability from Taskfile to requirements"

requirements-completed:
  - IMG-01
  - IMG-02
  - IMG-03
  - IMG-04
  - IMG-05
  - IMG-06
  - CLU-01
  - CLU-02
  - CLU-03
  - CLU-04
  - CLU-05
  - CLU-06

duration: 5min
completed: 2026-04-24
---

# Phase 02 Plan 07: Taskfile.yml Stub Summary

**go-task v3 stub at repo root wiring three Phase 2 scripts (build-image, create-clusters, delete-clusters) into a `task` CLI surface, completing Phase 2 scope**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-04-24T17:53:00Z
- **Completed:** 2026-04-24T17:53:57Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments

- Taskfile.yml created at repo root: go-task v3 schema, 3 tasks, 17 lines
- All three tasks one-line delegates to Phase 2 scripts (bash explicit)
- No premature tasks — Phase 5/6 ownership boundary respected
- `task --list` surfaces all three tasks with REQ-ID-citing descriptions
- Phase 2 bats suite: 38 ok, 0 not ok (7 skipped live-only tests)
- Phase 2 scope declared COMPLETE

## Task Commits

1. **Task 1: Create Taskfile.yml stub** - `5b31772` (feat)

**Plan metadata:** *(pending final docs commit)*

## Taskfile.yml Content (17 lines)

```yaml
version: '3'

tasks:
  build-image:
    desc: Build the karyon/k3s-cuda custom image (IMG-01..06)
    cmds:
      - bash scripts/build-image.sh

  create-clusters:
    desc: Create k8s-net + three k3d clusters (CLU-01..05)
    cmds:
      - bash scripts/create-clusters.sh

  delete-clusters:
    desc: Remove clusters + k8s-net; preserve karyon/k3s-cuda image (CLU-06, D-14)
    cmds:
      - bash scripts/delete-clusters.sh
```

## `task --list` Output

```
task: Available tasks for this project:
* build-image:           Build the karyon/k3s-cuda custom image (IMG-01..06)
* create-clusters:       Create k8s-net + three k3d clusters (CLU-01..05)
* delete-clusters:       Remove clusters + k8s-net; preserve karyon/k3s-cuda image (CLU-06, D-14)
```

## `task --version` Output

```
3.50.0
```

Matches `.tool-versions` pin: `task 3.50.0`

## End-of-Phase-2 Artifact Inventory

### images/
- `images/Dockerfile.k3s-cuda`
- `images/config.toml.tmpl`
- `images/device-plugin-daemonset.yaml`
- `images/image-tag.sh`

### scripts/
- `scripts/build-image.sh`
- `scripts/create-clusters.sh`
- `scripts/delete-clusters.sh`
- `scripts/install-docker.sh`
- `scripts/install-nvidia-container-toolkit.sh`
- `scripts/install-tools.sh`
- `scripts/lib/` (library functions)
- `scripts/preflight.sh`

### tests/bats/
- `tests/bats/create-clusters-01-network.bats`
- `tests/bats/create-clusters-02-hub-flux.bats`
- `tests/bats/create-clusters-03-spoke-ml.bats`
- `tests/bats/create-clusters-04-spoke-apps.bats`
- `tests/bats/create-clusters-05-tls-san.bats`
- `tests/bats/cuda-image-01-base.bats`
- `tests/bats/cuda-image-02-args.bats`
- `tests/bats/cuda-image-03-containerd.bats`
- `tests/bats/cuda-image-04-device-plugin.bats`
- `tests/bats/cuda-image-05-manifest-path.bats`
- `tests/bats/delete-clusters-01-cache.bats`
- `tests/bats/preflight-pre01.bats`
- `tests/bats/preflight-pre02.bats`
- `tests/bats/preflight-pre09.bats`
- `tests/bats/preflight-pre11.bats`
- `tests/bats/preflight-pre13.bats`
- `tests/bats/test_helper.bash`

### Repo root
- `Taskfile.yml` (created this plan)

## Final Bats Suite Result

`unset KARYON_LIVE_TESTS; bats tests/bats/ --tap`

- **ok:** 38
- **not ok:** 0
- **skipped (live-gated):** 7

`KARYON_LIVE_TESTS=1 bats tests/bats/ --tap` — not run (live infrastructure not available in this environment). The 7 skipped tests are live-gated (require real k3d/Docker infrastructure).

## Phase 2 Scope: COMPLETE

All 7 plans delivered:
- 02-01: .tool-versions, .env.example
- 02-02: images/ (Dockerfile.k3s-cuda, config.toml.tmpl, device-plugin-daemonset.yaml, image-tag.sh)
- 02-03: scripts/build-image.sh (IMG-01..05)
- 02-04: tests/bats/cuda-image-*.bats
- 02-05: scripts/create-clusters.sh + tests/bats/create-clusters-*.bats
- 02-06: scripts/delete-clusters.sh + tests/bats/delete-clusters-*.bats
- 02-07: Taskfile.yml (this plan)

Phase 6 REPO-05 will audit and reorganize: add destroy/rebuild/health-check/bootstrap-flux/register-spokes/deploy-examples tasks with typed-yes confirmation guards, full Phase 6 task surface.

## Files Created/Modified

- `Taskfile.yml` - go-task v3 stub, 3 tasks delegating to Phase 2 scripts

## Decisions Made

None — followed plan as specified. Exact content from PATTERNS.md §Taskfile.yml `<interfaces>` block used verbatim.

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

Minor: `task --version` outputs `3.50.0` (bare version string) rather than `Task version: v3.x` format assumed by one acceptance criterion grep. The binary IS go-task v3.50.0, matching the `.tool-versions` pin. The grep pattern difference is a documentation artifact in the plan — the actual requirement (v3.x, matching .tool-versions) is satisfied.

## Threat Surface Scan

No new network endpoints, auth paths, file access patterns, or schema changes introduced. Taskfile.yml is a local development convenience shim; trust posture matches scripts/*.sh (as documented in plan threat model).

## Next Phase Readiness

Phase 2 is complete. Phase 3 (flux-bootstrap) and Phase 5 (operations) will extend Taskfile.yml with additional tasks. Phase 6 REPO-05 owns the full audit.

No blockers.

---
*Phase: 02-cluster-layer*
*Completed: 2026-04-24*

## Self-Check: PASSED

- `Taskfile.yml` exists: FOUND
- Commit `5b31772` exists: FOUND
- 38 bats tests passing, 0 failing: CONFIRMED
