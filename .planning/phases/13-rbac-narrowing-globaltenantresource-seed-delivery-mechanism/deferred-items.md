# Phase 13 Deferred Items


## Plan 13-00 — pre-existing inherited bats failures (out of scope)

Discovered during Plan 13-00 Wave 0 inheritance verification run on
2026-05-19. NOT caused by Plan 13-00 work (which only adds NEW files under
`tests/bats/`); these failures exist in the inheritance state and are observed
to be pre-existing.

- `tests/bats/tenants-04-static-dependson.bats` (Phase 9 D-09-06/D-09-05):
  - Test 5: `TEN-06 / D-09-06: capsule-spoke.yaml dependsOn[0].name == poc-capsule` — FAIL
  - Test 8: `TEN-06 / D-09-05: capsule-spoke.yaml spec.serviceAccountName == kustomize-controller (explicit clarity)` — FAIL
  - Target file: `clusters/hub-flux/pocs/capsule-spoke.yaml`
  - Phase 13 does NOT touch this file; failures appear to be carry-over from prior phase verification state.
  - **Action:** logged here; Plan 13-04 verifier may decide to (a) repair under Rule 3 if blocking, (b) record as `passed_with_overrides` if non-blocking. NOT addressed in Plan 13-00.

