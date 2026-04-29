---
phase: 07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc
plan: 02
subsystem: infra
tags: [flux, kustomize, gitops, poc-seam, capsule, multi-tenancy]

# Dependency graph
requires:
  - phase: 04-spoke-registration
    provides: "FLUX PATCH SURFACE pattern (clusters/hub-flux/flux-system/kustomization.yaml) + # KARYON SPOKES MOUNT sentinel + ../spokes — Phase 4 D-13 inheritance preserved here"
  - phase: 07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc
    provides: "Wave 0 bats target tests/bats/poc-mount-01-static.bats (Plan 07-00) — turned GREEN by this plan"
provides:
  - "# KARYON POC MOUNT sentinel + ../pocs resource line in FLUX PATCH SURFACE (D-05/D-09; survives flux bootstrap re-runs)"
  - "clusters/hub-flux/pocs/ aggregator + flat capsule.yaml outer Flux Kustomization (D-06; mirrors v0.18 spokes/ pattern)"
  - "spec.kubeConfig.secretRef.name=spoke-capsule-kubeconfig + key=value.yaml literal in pocs/capsule.yaml (D-11; P18 inheritance — silent-misroute defense)"
  - "pocs/capsule/kustomization.yaml empty-resources placeholder so outer Kustomization reconciles as no-op (Pitfall 7)"
affects: [07-03 (register-poc-cluster.sh consumes spoke-capsule-kubeconfig Secret name + ensure_hub_pocs_mount idempotency target), 08-* (Capsule operator + capsule-proxy HelmReleases land in pocs/capsule/), future POCs (1-line edit to clusters/hub-flux/pocs/kustomization.yaml resources list)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "FLUX PATCH SURFACE sentinel-guarded extension (KARYON POC MOUNT parallel to KARYON SPOKES MOUNT)"
    - "Aggregator + flat outer Flux Kustomization (clusters/hub-flux/pocs/ mirrors clusters/hub-flux/spokes/)"
    - "Empty-resources Kustomize placeholder for not-yet-populated reconcile path (resources: [])"

key-files:
  created:
    - "clusters/hub-flux/pocs/kustomization.yaml — kustomize aggregator (resources: [capsule.yaml])"
    - "clusters/hub-flux/pocs/capsule.yaml — outer Flux v1 Kustomization (poc-capsule, ./pocs/capsule, spoke-capsule-kubeconfig)"
    - "pocs/capsule/kustomization.yaml — empty placeholder (resources: [])"
  modified:
    - "clusters/hub-flux/flux-system/kustomization.yaml — appended # KARYON POC MOUNT + - ../pocs (2-line addition, lines 21-22)"

key-decisions:
  - "Sentinel literal `# KARYON POC MOUNT` (no Capsule-specific suffix) — D-05 + STATE.md milestone-scope decision; future POCs reuse the same sentinel"
  - "`# KARYON POC MOUNT` placed BELOW the existing `# KARYON SPOKES MOUNT` (D-05) — production baseline above experimental; new sentinel becomes the file's tail extension point"
  - "Aggregator filename is `kustomization.yaml` (NOT `aggregator.yaml`/`index.yaml`) — D-06 specifics, matches v0.18 spokes/kustomization.yaml precedent"
  - "Outer Kustomization metadata.name = `poc-capsule` (D-11; `poc-` prefix differentiates from spoke pattern)"
  - "`spec.kubeConfig.secretRef.key: value.yaml` carried explicitly (P18 inheritance) — silent-misroute defense; bats yq query asserts the literal"
  - "Empty `resources: []` placeholder ships in Phase 7 (Pitfall 7); Phase 8 replaces with [operator, proxy, config]"

patterns-established:
  - "KARYON POC MOUNT pattern: future POCs (Crossplane, Linkerd, vcluster) onboard via 1-line edit to clusters/hub-flux/pocs/kustomization.yaml; FLUX PATCH SURFACE stays untouched"
  - "Outer-Kustomization-with-empty-placeholder pattern: ship the seam in one phase, populate resources in the next — keeps reconcile path Ready=True from day one"

requirements-completed:
  - POC-01
  - CAPCLU-02

# Metrics
duration: ~10 min
completed: 2026-04-29
---

# Phase 07 Plan 02: POC Seam Static Infrastructure Summary

**Generic, sentinel-guarded POC onboarding seam landed in the FLUX PATCH SURFACE plus a v0.18-mirrored aggregator + outer Flux Kustomization for spoke-capsule with empty-resources placeholder — POC-01 and CAPCLU-02 file-shape contracts now satisfied.**

## Performance

- **Duration:** ~10 min
- **Started:** 2026-04-29 (worktree wave 2)
- **Completed:** 2026-04-29
- **Tasks:** 2 / 2
- **Files modified:** 1
- **Files created:** 3

## Accomplishments

- Extended FLUX PATCH SURFACE (`clusters/hub-flux/flux-system/kustomization.yaml`) with `# KARYON POC MOUNT` + `- ../pocs` directly below the existing `# KARYON SPOKES MOUNT` block; Phase 4 D-13 inheritance preserved verbatim.
- Sentinel uniqueness verified (P30): `grep -cF '# KARYON POC MOUNT'` returns exactly 1; D-09 anti-pattern guard verified: sentinel does NOT appear in `clusters/hub-flux/kustomization.yaml`.
- Created `clusters/hub-flux/pocs/` aggregator + flat `capsule.yaml` outer Flux Kustomization, exact structural mirror of the v0.18 `spokes/` pattern.
- `clusters/hub-flux/pocs/capsule.yaml` carries the load-bearing `spec.kubeConfig.secretRef.name: spoke-capsule-kubeconfig` + `key: value.yaml` (P18 inheritance — defense against silent in-cluster fallback per D-11).
- `pocs/capsule/kustomization.yaml` ships as a valid empty-resources Kustomize placeholder (Pitfall 7) so the outer Kustomization reconciles cleanly as a no-op once Plan 07-03 lands the kubeconfig Secret.
- `tests/bats/poc-mount-01-static.bats`: 8 of 8 GREEN.
- `tests/bats/poc-cluster-01-static.bats --filter "CAPCLU-02"`: 1 of 1 GREEN (capsule.yaml shape contract).

## Task Commits

Each task was committed atomically (--no-verify due to parallel-worktree contention):

1. **Task 1: Insert # KARYON POC MOUNT sentinel + ../pocs resource line** — `5bc8cb0` (feat)
2. **Task 2: Create pocs/ aggregator + capsule.yaml outer Kustomization + placeholder** — `afa8e08` (feat)

## Files Created/Modified

### Created (3)

- `clusters/hub-flux/pocs/kustomization.yaml` — kustomize aggregator (`resources: [capsule.yaml]`); direct mirror of `clusters/hub-flux/spokes/kustomization.yaml`.
- `clusters/hub-flux/pocs/capsule.yaml` — outer Flux v1 Kustomization. `metadata.name=poc-capsule`, `metadata.namespace=flux-system`, `spec.path=./pocs/capsule`, `spec.prune=true`, `spec.interval=5m`, `spec.sourceRef={kind: GitRepository, name: flux-system}`, `spec.kubeConfig.secretRef={name: spoke-capsule-kubeconfig, key: value.yaml}`. Top-of-file comment block documents the `key: value.yaml` rationale (Phase 4 P18 inheritance — silent-misroute defense).
- `pocs/capsule/kustomization.yaml` — empty placeholder (`resources: []`) so the outer Kustomization at `clusters/hub-flux/pocs/capsule.yaml` (which references `spec.path: ./pocs/capsule`) reconciles successfully as a no-op until Phase 8 replaces resources with `[operator, proxy, config]` (Pitfall 7 mitigation).

### Modified (1)

- `clusters/hub-flux/flux-system/kustomization.yaml` — append-only 2-line edit (lines 21-22). New content:
  ```yaml
    # KARYON POC MOUNT
    - ../pocs
  ```
  Inserted directly below the existing `# KARYON SPOKES MOUNT` + `- ../spokes` block per D-05. Lines 1-20 preserved verbatim (Phase 4 D-13 inheritance).

## Decisions Made

None — followed plan as specified. The plan's `<action>` blocks already encoded D-05 (sentinel placement), D-06 (aggregator shape), D-09 (FLUX PATCH SURFACE location), D-11 (P18 secretRef shape), and Pitfall 7 (empty placeholder) decisions. No discretionary choices remained at the implementation layer.

## Deviations from Plan

None — plan executed exactly as written.

The plan was extremely tight: 2 tasks, 1 modified file (2-line append), 3 created files (each a structural copy of an existing v0.18 analog with literal substitutions). No bugs or missing-functionality conditions appeared during execution. No auth gates. No checkpoints. The plan's Wave 0 bats target (`tests/bats/poc-mount-01-static.bats`) acted as the green/red oracle and turned 5/8 → 8/8 across the two task commits as expected.

## Issues Encountered

None. The system's `grep` is aliased to `ugrep`, which interpreted `- ../pocs` (sans `--`) as an option-like argument during a verification check; resolved by adding `--` to subsequent grep invocations. No code path affected.

## Verification Results

### Plan-defined acceptance criteria

**Task 1:**
- `yq eval '.kind' …kustomization.yaml` → `Kustomization` ✓
- `grep -cF '# KARYON POC MOUNT' …flux-system/kustomization.yaml` → `1` ✓
- `grep -cF '# KARYON SPOKES MOUNT' …flux-system/kustomization.yaml` → `1` (Phase 4 D-13 inheritance) ✓
- `grep -cF '- ../pocs' …flux-system/kustomization.yaml` → `1` ✓
- `grep -cF '- ../spokes' …flux-system/kustomization.yaml` → `1` (Phase 4 inheritance) ✓
- `grep -cF '# KARYON POC MOUNT' …hub-flux/kustomization.yaml` → `0` (D-09 anti-pattern guard) ✓
- `yq eval '.resources | length' …flux-system/kustomization.yaml` → `4` ✓
- `yq eval '.resources[3]' …flux-system/kustomization.yaml` → `../pocs` ✓
- awk adjacency check → `OK` (sentinel directly precedes `- ../pocs`) ✓

**Task 2:**
- `yq eval '.apiVersion == "kustomize.config.k8s.io/v1beta1" and .kind == "Kustomization" and (.resources | length) == 1 and .resources[0] == "capsule.yaml"' …pocs/kustomization.yaml` → `true` ✓
- Full outer-Kustomization yq shape check on `…pocs/capsule.yaml` (including `spec.kubeConfig.secretRef.{name,key}`, `spec.path`, `spec.prune`, `spec.sourceRef`, `spec.interval`, `metadata.name=poc-capsule`, `metadata.namespace=flux-system`) → `true` ✓
- `yq eval '.apiVersion == "kustomize.config.k8s.io/v1beta1" and .kind == "Kustomization" and (has("resources"))' pocs/capsule/kustomization.yaml` → `true` ✓
- `yq eval '.resources | length' pocs/capsule/kustomization.yaml` → `0` ✓
- `find clusters/hub-flux/pocs/ pocs/capsule/ -type f` → exactly 3 files (matches plan output) ✓

### Bats results

- `tests/bats/poc-mount-01-static.bats` → 8/8 GREEN
- `tests/bats/poc-cluster-01-static.bats --filter "CAPCLU-02"` → 1/1 GREEN

The full-suite `bats tests/bats/` shows preexisting RED-state tests for downstream plans (CAPCLU-01 / scripts/poc/capsule/create-cluster.sh, POC-02 / scripts/register-poc-cluster.sh, POC-04 / preflight.sh PRE-15, POC-03 / .gitleaks.toml). None of these failures are caused by Plan 07-02; all are intentional Wave 0 RED-state contracts for plans 07-03 and 07-04 and beyond.

## Threat Model Verification

| Threat ID | Status | Verification |
|-----------|--------|--------------|
| T-7-D-09 (sentinel placement survives bootstrap) | mitigated | Sentinel landed in `clusters/hub-flux/flux-system/kustomization.yaml`; bats positive grep + bats negative grep on peer file both pass. |
| T-7-P-30 (sentinel uniqueness) | mitigated | `grep -cF '# KARYON POC MOUNT' …` == 1; bats P30 case passes. |
| T-7-P-40 (silent in-cluster fallback) | mitigated | `pocs/capsule.yaml` carries explicit `spec.kubeConfig.secretRef.name` + `key: value.yaml`; bats yq query asserts both literals. Top-of-file comment documents the silent-misroute fault for future maintainers. |
| T-7-Pitfall-7 (Ready=False; path not found) | mitigated | `pocs/capsule/kustomization.yaml` ships with valid `resources: []`; bats validates apiVersion + kind + has("resources"). |
| T-7-D-13-inherit (SPOKES MOUNT preservation) | mitigated | Edit was append-only (2-line addition at end); `grep -cF '# KARYON SPOKES MOUNT'` == 1; `grep -cF '- ../spokes'` == 1. |

No new threat surface introduced beyond what the plan's `<threat_model>` already enumerates. No threat-flag entries needed.

## User Setup Required

None — no external service configuration required.

The kubeconfig Secret (`spoke-capsule-kubeconfig` in `flux-system` namespace) referenced by `pocs/capsule.yaml` is applied imperatively by Plan 07-03's `scripts/register-poc-cluster.sh` and is intentionally NOT git-tracked. Until that Secret exists on hub-flux, the outer Kustomization will report Ready=False with a "secret not found" reason — this is expected and is closed by Plan 07-03's `verify_credential_layer()` step.

## Next Phase Readiness

- POC-01 + CAPCLU-02 file-shape contracts satisfied; live reconcile verification deferred to Plan 07-03 (`scripts/register-poc-cluster.sh`'s `verify_credential_layer` step against an actual `k3d-spoke-capsule` cluster).
- The POC seam pattern is now reusable: future POCs onboard with a 1-line edit to `clusters/hub-flux/pocs/kustomization.yaml` (`resources: [capsule.yaml, <next-poc>.yaml]`) plus a peer flat outer Flux Kustomization. No FLUX PATCH SURFACE edit needed for second/third/Nth POCs.
- Phase 8 (CAP-01..03) will replace `pocs/capsule/kustomization.yaml`'s `resources: []` with `[operator, proxy, config]` once the Capsule + capsule-proxy HelmReleases land — the outer Kustomization reconcile path is already wired and ready.
- No blockers or concerns.

## Self-Check: PASSED

**Created files exist:**
- FOUND: clusters/hub-flux/pocs/kustomization.yaml
- FOUND: clusters/hub-flux/pocs/capsule.yaml
- FOUND: pocs/capsule/kustomization.yaml

**Modified file changed:**
- FOUND: clusters/hub-flux/flux-system/kustomization.yaml (lines 21-22 appended)

**Commits exist:**
- FOUND: 5bc8cb0 — feat(07-02): extend FLUX PATCH SURFACE with KARYON POC MOUNT sentinel
- FOUND: afa8e08 — feat(07-02): create POC seam aggregator + outer Kustomization + placeholder

**Bats green:**
- FOUND: tests/bats/poc-mount-01-static.bats — 8/8 GREEN
- FOUND: tests/bats/poc-cluster-01-static.bats --filter "CAPCLU-02" — 1/1 GREEN

---
*Phase: 07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc*
*Plan: 02*
*Completed: 2026-04-29*
