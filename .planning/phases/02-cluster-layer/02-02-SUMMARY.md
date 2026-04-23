---
phase: 02-cluster-layer
plan: 02
subsystem: infra
tags:
  - dockerfile
  - image-tag
  - buildkit
  - k3s
  - cuda
  - phase-2

requires:
  - phase: 02-01
    provides: tests/bats/cuda-image-01-base.bats and cuda-image-02-args.bats Wave-0 stubs (this plan activates their real assertions)

provides:
  - images/Dockerfile.k3s-cuda (2-stage k3s+CUDA image recipe, BuildKit syntax 1.7-labs)
  - images/image-tag.sh (single source of truth for the tag string, D-06)
  - IMG-01 and IMG-02 static bats assertions now running for real (no skip)

affects:
  - 02-03 (adds images/config.toml.tmpl + images/device-plugin-daemonset.yaml — the two COPY targets referenced by the Dockerfile)
  - 02-04 (scripts/build-image.sh calls docker build with $(images/image-tag.sh))
  - 02-05 (scripts/create-clusters.sh passes --image $(images/image-tag.sh) to spoke-ml)
  - 02-06 (scripts/delete-clusters.sh uses the tag string when asserting image survival)

tech-stack:
  added:
    - "BuildKit frontend syntax 1.7-labs (enables COPY --exclude in multi-stage copy)"
  patterns:
    - "Single-source-of-truth for image pins: Dockerfile ARG defaults parsed by image-tag.sh (D-06)"
    - "image-tag.sh deliberately does NOT source preflight-lib.sh to keep stdout ANSI-clean for $() capture"

key-files:
  created:
    - "images/Dockerfile.k3s-cuda — 83 lines, verbatim from 02-RESEARCH.md §2.1 + LOW-traceability NOTE block"
    - "images/image-tag.sh — 38 lines, executable (chmod +x)"
  modified:
    - "tests/bats/cuda-image-01-base.bats (skip removed, 2 grep assertions active)"
    - "tests/bats/cuda-image-02-args.bats (skip removed, 1 grep assertion active)"

key-decisions:
  - "Dockerfile committed as static recipe even though COPY images/config.toml.tmpl + COPY images/device-plugin-daemonset.yaml reference files that Plan 02-03 will create. This is intentional and called out in an inline NOTE block — docker build is not invoked until Plan 02-04 anyway."
  - "image-tag.sh emits karyon/k3s-cuda:v1.34.6-k3s1-cuda12.8.1 on stdout with no side effects and no ANSI codes (verified via od -c grep '033' → 0 matches)."
  - "IMG-01 assertion matches the ARG-referenced FROM (e.g. ^FROM nvidia/cuda:${CUDA_TAG}) rather than the resolved value, so the test remains correct when the ARG default is bumped. Pin-drift is caught separately by IMG-02's literal ^ARG K3S_TAG=v1.34.6-k3s1$ check."

patterns-established:
  - "D-06: Dockerfile ARG defaults = canonical pin source; tag string derived via image-tag.sh"
  - "Inline build-time NOTE blocks in Dockerfiles that depend on files created by later plans"

requirements-completed: []  # Plan scaffolds artifacts for IMG-01 and IMG-02 static checks; full IMG-01/IMG-02 verification requires the built image (Plan 02-04). Per 02-01 SUMMARY deviation #3, requirements are not marked complete here; 02-04 will mark IMG-03/IMG-05/IMG-06.

duration: 6min
completed: 2026-04-23
---

# Phase 02 Plan 02: Dockerfile.k3s-cuda + image-tag.sh

**Two-stage k3s+CUDA Dockerfile (BuildKit 1.7-labs) plus the single-source-of-truth image-tag.sh; IMG-01 and IMG-02 bats assertions now run for real**

## Performance

- **Duration:** ~6 min
- **Tasks:** 3
- **Files created:** 2 (images/Dockerfile.k3s-cuda, images/image-tag.sh)
- **Files modified:** 2 (IMG-01 / IMG-02 bats activations)

## Task Commits

1. **Task 1: Create images/Dockerfile.k3s-cuda** — `9bebb57` (feat)
2. **Task 2: Create images/image-tag.sh (executable)** — `80eb8a0` (feat)
3. **Task 3: Activate IMG-01 and IMG-02 bats static assertions** — `d513eec` (test)

## Files Created/Modified

- `images/Dockerfile.k3s-cuda` — 83 lines; first line `# syntax=docker/dockerfile:1.7-labs`; three ARGs locked at K3S_TAG=v1.34.6-k3s1, CUDA_TAG=12.8.1-base-ubuntu22.04, DEVICE_PLUGIN_VERSION=v0.17.4; two-stage (rancher/k3s AS k3s → nvidia/cuda final); COPYs config.toml.tmpl and device-plugin-daemonset.yaml (both Plan 02-03 artifacts); ENTRYPOINT ["/bin/k3s"] CMD ["agent"]. Includes inline NOTE block explaining why standalone docker build will fail until 02-03 lands.
- `images/image-tag.sh` — 38 lines; executable; shebang `#!/usr/bin/env bash`; `set -euo pipefail`; no source of preflight-lib.sh (by design — ANSI-clean stdout required for $() capture); emits `karyon/k3s-cuda:v1.34.6-k3s1-cuda12.8.1` on stdout; fails clean (exit 1 + stderr) when Dockerfile is missing.
- `tests/bats/cuda-image-01-base.bats` — skip removed; body asserts `^FROM nvidia/cuda:${CUDA_TAG}` and `^FROM rancher/k3s:${K3S_TAG} AS k3s` both present.
- `tests/bats/cuda-image-02-args.bats` — skip removed; body asserts `^ARG K3S_TAG=v1.34.6-k3s1$` present.

## Verification

- `bash images/image-tag.sh` → `karyon/k3s-cuda:v1.34.6-k3s1-cuda12.8.1` (exit 0, ANSI-clean)
- `bash images/image-tag.sh` with Dockerfile missing → exit 1, stderr carries "Dockerfile.k3s-cuda not found"
- `bats tests/bats/cuda-image-01-base.bats tests/bats/cuda-image-02-args.bats --tap` → 2 ok, 0 skip, 0 fail
- `bats tests/bats/` full suite → 38 ok / 0 not-ok (11 skips remaining from other Wave-0 stubs, all expected)

## Decisions Made

See `key-decisions` in frontmatter.

## Deviations from Plan

None — plan executed exactly as written. The per-file verbatim drop-ins from 02-RESEARCH.md §2.1 and §2.4 matched the plan's interface blocks exactly.

## Issues Encountered

None.

## User Setup Required

None.

## Next Phase Readiness

- **Plan 02-03** will create `images/config.toml.tmpl` and `images/device-plugin-daemonset.yaml` — the two files the Dockerfile's COPY directives reference. After 02-03 lands, the Dockerfile becomes buildable.
- **Plan 02-04** will add `scripts/build-image.sh`, invoke `docker build`, and activate the live IMG-03 / IMG-05 bats checks that need a built image to exercise.
- Per 02-01 SUMMARY deviation #3, IMG-01/IMG-02 are not marked complete in REQUIREMENTS.md yet — the plan intentionally leaves `requirements-completed: []` since full verification of these REQs requires the built image. The 02-04 plan-author should mark IMG-01..03 + IMG-05 + IMG-06 complete there.

---
*Phase: 02-cluster-layer*
*Completed: 2026-04-23*
