---
phase: 02-cluster-layer
plan: 03
subsystem: infra
tags:
  - containerd
  - device-plugin
  - runtime-class
  - phase-2

requires:
  - phase: 02-02
    provides: images/Dockerfile.k3s-cuda (carries the two COPY lines that consume config.toml.tmpl and device-plugin-daemonset.yaml)

provides:
  - images/config.toml.tmpl (third leg of 3-part k3d GPU contract, D-05, IMG-03)
  - images/device-plugin-daemonset.yaml (RuntimeClass + DaemonSet, v0.17.4 pinned per D-15)
  - D-15 phase-scoped decision recorded in 02-CONTEXT.md
  - IMG-04 bats check activated (no skip; real manifest-image grep)

affects:
  - 02-04 (build-image.sh becomes buildable — all four images/* files present)
  - 02-05 (create-clusters.sh uses the built image for spoke-ml; the device-plugin baked in delivers nvidia.com/gpu at t=0)
  - Any future phase that references the canonical v0.17.4 pin

tech-stack:
  added: []
  patterns:
    - "k3s containerd template extension via {{ template \"base\" . }} (docs.k3s.io/advanced recommended approach)"
    - "v3-schema containerd config override via [plugins.'io.containerd.cri.v1.runtime'.containerd] (containerd 2.0 silently rejects v2 schema)"
    - "Phase-scoped D-xx decisions override REQUIREMENTS.md wording with explicit rationale and cross-references"

key-files:
  created:
    - "images/config.toml.tmpl — 35 lines; extends k3s base, overrides default_runtime_name = \"nvidia\""
    - "images/device-plugin-daemonset.yaml — 78 lines; RuntimeClass + DaemonSet, v0.17.4 pin"
  modified:
    - ".planning/phases/02-cluster-layer/02-CONTEXT.md (appended D-15 decision)"
    - "tests/bats/cuda-image-04-device-plugin.bats (skip removed, real grep assertion active)"

key-decisions:
  - "D-15 recorded: DEVICE_PLUGIN_VERSION = v0.17.4 as the phase-scoped override of REQ-IMG-04 (which reads 'v0.19.0+'). Rationale: no stable v0.19.x release compatible with RTX 5090 / Blackwell / sm_120 at research time. REQUIREMENTS.md text remains authoritative for future bumps."
  - "config.toml.tmpl uses the k3s base-template extension pattern rather than a hand-authored replacement — per docs.k3s.io/advanced and PATTERNS.md. Only the default_runtime_name override is our custom surface."
  - "Dockerfile ARG DEVICE_PLUGIN_VERSION (v0.17.4) and manifest image tag (v0.17.4) match exactly — drift is caught by the acceptance-criterion diff check in Task 3."

patterns-established:
  - "D-15: Phase-scoped override pattern — record in CONTEXT.md §decisions with full rationale, cite REQUIREMENTS.md text it overrides, list all files the pin appears in"

requirements-completed: []  # Plan lands the static manifests referenced by IMG-03 (config.toml.tmpl) and IMG-04 (device-plugin-daemonset.yaml). IMG-03 runtime verification requires the built image (Plan 02-04). IMG-04 static check is green now; IMG-04's "baked into image" aspect (IMG-05) also needs the built image. Per 02-01 deviation #3, REQ completion is marked in the plan that closes the final verification gap — 02-04 for IMG-03/IMG-05/IMG-06.

duration: 6min
completed: 2026-04-23
---

# Phase 02 Plan 03: config.toml.tmpl + device-plugin DaemonSet

**Third leg of the 3-part k3d GPU contract landed; NVIDIA device-plugin v0.17.4 manifest pinned per D-15; IMG-04 bats check activated; all four images/* files now exist**

## Performance

- **Duration:** ~6 min
- **Tasks:** 4 (Task 0 decision + 3 implementation tasks)
- **Files created:** 2 (images/config.toml.tmpl, images/device-plugin-daemonset.yaml)
- **Files modified:** 2 (02-CONTEXT.md D-15 append, IMG-04 bats activation)

## Task Commits

1. **Task 0: Record D-15 in 02-CONTEXT.md** — `2b7479e` (docs)
2. **Task 1: Create images/config.toml.tmpl** — `d285eb3` (feat)
3. **Task 2: Create images/device-plugin-daemonset.yaml** — `c9eb68d` (feat)
4. **Task 3: Activate IMG-04 bats assertion** — `fe95b4a` (test)

## Files Created/Modified

- `images/config.toml.tmpl` — 35 lines; first non-comment directive `{{ template "base" . }}`; override block `[plugins.'io.containerd.cri.v1.runtime'.containerd]` with `default_runtime_name = "nvidia"`. Header documents the 3-part GPU contract and file path at `/var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl`.
- `images/device-plugin-daemonset.yaml` — 78 lines; two YAML documents. Doc 1: RuntimeClass (apiVersion node.k8s.io/v1, name=nvidia, handler=nvidia). Doc 2: DaemonSet in kube-system pinning `nvcr.io/nvidia/k8s-device-plugin:v0.17.4`; args --mig-strategy=none, --fail-on-init-error=true, --pass-device-specs=false, --device-list-strategy=envvar; tolerations for nvidia.com/gpu, master, control-plane; drop ALL caps; priorityClassName system-node-critical.
- `.planning/phases/02-cluster-layer/02-CONTEXT.md` — appended D-15 entry under a new `### NVIDIA Device Plugin Version Override (REQ-IMG-04)` sub-heading between D-14 and §Claude's Discretion.
- `tests/bats/cuda-image-04-device-plugin.bats` — skip removed; body `run grep -F 'image: nvcr.io/nvidia/k8s-device-plugin:v0.17.4' "$MANIFEST"; [ "$status" -eq 0 ]`.

## Verification

- `bats tests/bats/cuda-image-04-device-plugin.bats --tap` → 1 ok, 0 skip, 0 fail.
- Drift check: Dockerfile ARG `DEVICE_PLUGIN_VERSION=v0.17.4` matches manifest `image: ...:v0.17.4` — zero drift.
- `bats tests/bats/` full suite → 38 ok / 0 not-ok (10 skips remaining, all Wave-0 stubs awaiting Plans 02-04..02-06).
- `ls images/` → `Dockerfile.k3s-cuda  config.toml.tmpl  device-plugin-daemonset.yaml  image-tag.sh` — the image layer is now complete; Plan 02-04 can invoke `docker build`.

## Decisions Made

See `key-decisions` in frontmatter.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Plan acceptance criteria undercount literal grep matches produced by the verbatim interface body**

- **Found during:** Task 1 (config.toml.tmpl) and Task 2 (device-plugin-daemonset.yaml) acceptance verification
- **Issue:** The plan's `<interfaces>` blocks mandate verbatim bodies that include header comments mirroring the same strings the acceptance criteria expect to find exactly once. For config.toml.tmpl, `grep -F -c '{{ template "base" . }}'` returns 2 (comment on L15 + directive on L28), not the specified 1. `grep -F -c 'default_runtime_name = "nvidia"'` returns 3 (header L6 + override-block comment L30 + directive L35), not 1. For device-plugin-daemonset.yaml, the `--mig-strategy=none` / `--fail-on-init-error=true` / `--pass-device-specs=false` / `--device-list-strategy=envvar` criteria each say `returns 1` but the verbatim header comment block lists all four flags *with rationale*, so each appears twice (header + container args). Similarly, `runtimeClassName: nvidia` appears in the header comment ("Pods that need explicit nvidia runtime can set runtimeClassName: nvidia") and in the pod spec itself, for a count of 2.
- **Fix:** Honored the mandated verbatim body. Semantic intent of each criterion (the literal directive/flag/name is present in the file in the correct structural position) is met — verified manually via `grep -Fn` showing directives on the expected lines. Same class of plan-text inconsistency as 02-01 deviation #1 and #2.
- **Files modified:** None (kept verbatim body).
- **Verification:** Every single one of the plan's *structural* expectations holds (base-template extension directive present, override block present, all four args present, all three tolerations present, drop ALL capabilities, hostPath volume, namespace, apiVersions, two --- separators, line count). The only failing criteria are the literal-count ones which the plan itself mandates through the verbatim body.
- **Committed in:** `d285eb3` and `c9eb68d`.

---

**Total deviations:** 1 auto-fixed (plan-text inconsistency — verbatim body vs count criteria).
**Impact on plan:** None on behavior. All structural requirements met. The acceptance criteria should be reworded to "at least 1" instead of exactly "1" when the mandated body contains header comments that mirror the enforced string.

## Issues Encountered

None.

## User Setup Required

None.

## Next Phase Readiness

- All four `images/*` files exist. **Plan 02-04** can now create `scripts/build-image.sh` and successfully invoke `docker build` — this unlocks the live IMG-03 and IMG-05 bats checks (they need `docker run --rm --entrypoint cat "$TAG" ...`).
- IMG-04 is only half-verified (static manifest grep passes). The "baked into the image at /var/lib/rancher/k3s/server/manifests/..." aspect (IMG-05) needs the live image — still skipped, still waiting on 02-04.
- IMG-03 grep target (`default_runtime_name = "nvidia"` inside the baked config.toml.tmpl) is also waiting for 02-04.
- Drift between Dockerfile ARG and manifest image tag is caught automatically by the bats acceptance workflow; no manual substitution pipeline needed for v1 (per RESEARCH.md §7 OQ-1 / T-02-17).

---
*Phase: 02-cluster-layer*
*Completed: 2026-04-23*
