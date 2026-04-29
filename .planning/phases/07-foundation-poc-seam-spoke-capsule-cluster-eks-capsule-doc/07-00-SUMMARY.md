---
phase: 07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc
plan: 00
subsystem: testing
tags: [bats, gitleaks, kubeconfig, kustomize, fixtures, nyquist-gate, capsule, poc]

# Dependency graph
requires:
  - phase: 06-public-repo-publishing
    provides: bats-core 1.11.0 framework + tests/bats/test_helper.bash loader + .gitleaks.toml allowlist conventions
  - phase: 04-spoke-registration
    provides: register-spokes-01-static.bats analog patterns + KARYON SPOKES MOUNT sentinel surface
  - phase: 05-workloads-health-rebuild
    provides: fix-coredns-01-static.bats + destroy-rebuild-01-static.bats analog patterns

provides:
  - 7 Phase 7 bats target files (Nyquist gate) referencing future Plans 01-05 paths
  - 2 gitleaks fixtures (positive + negative) for the kubeconfig-bearer-token rule that lands in Plan 04
  - 51 RED tests fail-closed until Plans 01-05 implement behavior
  - 12 GREEN tests pass immediately (P31/D-12 isolation contract + v0.18 inheritance assertions)
  - Total Phase 7 bats coverage: 63 @test cases across 7 files

affects: [07-01-eks-capsule-doc, 07-02-poc-seam, 07-03-poc-cluster, 07-04-repo-hygiene, 07-05-preflight-30443]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Wave 0 Nyquist gate (carried forward from Phase 6 06-00) — bats target files exist before behavior"
    - "Per-fixture path allowlist for synthetic kubeconfig (committable + caught by upcoming rule)"
    - "Comment-filtered isolation greps (grep -v '^[[:space:]]*#') for self-invalidation safety"
    - "awk-bracketed function-body greps for verify_credential_layer / build_kubeconfig / check_port_strict scoping"

key-files:
  created:
    - tests/bats/poc-mount-01-static.bats
    - tests/bats/register-poc-cluster-01-static.bats
    - tests/bats/poc-cluster-01-static.bats
    - tests/bats/docs-06-eks.bats
    - tests/bats/poc-isolation-01-static.bats
    - tests/bats/preflight-pre15.bats
    - tests/bats/repo-hygiene-04-poc.bats
    - tests/fixtures/gitleaks/synthetic-kubeconfig.yaml
    - tests/fixtures/gitleaks/benign-configmap.yaml
  modified: []

key-decisions:
  - "Inert positive fixture uses RFC 6761 reserved TLD (example.invalid) + clearly-labeled inert token to make security review trivial"
  - "Negative fixture intentionally includes a token: field to exercise the rule's negative case (does the regex fire on tokens-without-kubeconfig-shape?)"
  - "poc-isolation-01-static.bats split out as standalone file (not folded into destroy-rebuild-01-static.bats) for explicit P31/D-12 contract surface"
  - "verify_credential_layer / build_kubeconfig negative-positive carve-out: build_kubeconfig MUST NOT use :6446 (host port leaks into in-cluster URL); verify_credential_layer MUST use 127.0.0.1:6446 (TLS probe target). Plan 02 will land the script that satisfies both halves."

patterns-established:
  - "Pattern: Nyquist gate — every Phase 7 plan task has a Wave-0 bats target before behavior lands"
  - "Pattern: Sentinel-line counting (grep -cF on the literal '# KARYON POC MOUNT') deliberately bypasses the comment-filter pattern because the sentinel IS a comment"
  - "Pattern: Per-fixture per-file allowlist via [rules.allowlist].paths (gitleaks 8.30.1 — narrowest exception that lets fixture coexist with rule)"

requirements-completed: [POC-01, POC-02, POC-03, POC-04, CAPCLU-01, CAPCLU-02, CAPCLU-03, CAPCLU-04, EKSDOC-01]

# Metrics
duration: 5min
completed: 2026-04-29
---

# Phase 07 Plan 00: Wave 0 Nyquist Gate Summary

**7 Phase 7 bats target files + 2 gitleaks fixtures land before any behavior — 51 RED tests pin the contracts that Plans 01-05 will turn green; 12 GREEN tests immediately enforce P31/D-12 POC isolation and v0.18 inheritance.**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-04-29T14:33:58Z
- **Completed:** 2026-04-29T14:39:02Z
- **Tasks:** 2
- **Files created:** 9

## Accomplishments

- Wave 0 Nyquist gate landed: 7 bats files (6 mandatory + 1 optional explicit-isolation file) + 2 gitleaks fixtures committed before any Phase 7 implementation behavior
- 63 new @test cases pin the contracts that Plans 01-05 (07-01..07-05) will satisfy
- P31/D-12 POC isolation contract enforced GREEN-on-creation: zero spoke-capsule + zero register-poc-cluster + zero scripts/poc/ mentions in v0.18 scripts (3 GREEN tests in poc-isolation-01-static.bats verify this immediately)
- Total bats suite grew 208 → 271 with zero v0.18 regressions (all 208 v0.18 tests still GREEN)

## Task Commits

Each task was committed atomically:

1. **Task 1: bats stubs for POC seam + register + cluster + EKS doc + isolation** — `cb1a95b` (test)
2. **Task 2: preflight-pre15 + repo-hygiene-04-poc + 2 gitleaks fixtures** — `407ade2` (test)

## Files Created

### Bats target files (7 total — `tests/bats/`)

| File | Tests | RED | GREEN | Requirement | Notes |
|------|------:|----:|------:|-------------|-------|
| `poc-mount-01-static.bats` | 8 | 6 | 2 | POC-01 | KARYON POC MOUNT sentinel + pocs/ aggregator + capsule.yaml outer Kustomization shape (yq queries). 2 incidentally GREEN: SPOKES sentinel inheritance + peer-file negative guard. |
| `register-poc-cluster-01-static.bats` | 15 | 15 | 0 | POC-02 | register-poc-cluster.sh shape contract: strict-mode + single positional + RBAC literals + ensure_hub_pocs_mount + verify_credential_layer + build_kubeconfig URL carve-out + token safety. |
| `poc-cluster-01-static.bats` | 11 | 11 | 0 | CAPCLU-01..04 | create-cluster.sh + fix-dns.sh + capsule.yaml secretRef + Taskfile fix-dns-poc-capsule + docs/poc-capsule.md sections. |
| `docs-06-eks.bats` | 9 | 9 | 0 | EKSDOC-01 | Mermaid + 3 verbatim YAML anchors (IRSA, LB, CapsuleConfiguration) + 3-item NOT-PROVED list + 7 Capsule CRDs + k3d-name negative. |
| `poc-isolation-01-static.bats` | 3 | 0 | 3 | P31 / D-12 | Zero spoke-capsule + zero register-poc-cluster + zero scripts/poc/ in v0.18 scripts. **GREEN-on-creation.** |
| `preflight-pre15.bats` | 6 | 4 | 2 | POC-04 / D-15 | check_port_strict() + 30443 invocation + fail (not warn) body + PRE-15 section header. 2 GREEN: existing v0.18 check_port + warn-loop literals. |
| `repo-hygiene-04-poc.bats` | 11 | 6 | 5 | POC-03 / D-14 | .gitignore tenant globs + .gitleaks.toml kubeconfig-bearer-token rule + per-fixture path allowlist + positive/negative fixture invocation contracts. 5 GREEN: Phase 6 D-16 expansion globs + Phase 1 [allowlist] preserved + 2 fixture-content checks + negative gitleaks invocation. |
| **Totals** | **63** | **51** | **12** | | |

### Gitleaks fixtures (2 total — `tests/fixtures/gitleaks/`)

| File | Purpose | Inert-token attestation |
|------|---------|-------------------------|
| `synthetic-kubeconfig.yaml` | POSITIVE FIXTURE — MUST be caught by Plan 04's kubeconfig-bearer-token rule | Token is `ZXhhbXBsZS1pbmVydC10b2tlbi12MC4xOS1zeW50aGV0aWMtZml4dHVyZQ` (58 chars, base64-decoded reads `example-inert-token-v0.19-synthetic-fixture`). Server is `https://example.invalid:6443` (RFC 6761 reserved TLD, never resolvable). File header comment explicitly labels inert. |
| `benign-configmap.yaml` | NEGATIVE FIXTURE — MUST NOT be caught (kind: ConfigMap, not Config; canary token labeled `false-positive-canary`) | Token field is intentional bait labeled `false-positive-canary` to test the regex's discrimination. |

Both fixtures pass the existing v0.18 gitleaks allowlist-only configuration today (verified — both invocations return exit 0 against current `.gitleaks.toml`). Plan 04 will land the positive rule + path allowlist; the rule's allowlist for `synthetic-kubeconfig.yaml` prevents the fixture itself from breaking pre-commit thereafter.

## v0.18 Pattern Inheritance

Wave 0 mechanically transferred known patterns from v0.18 analogs (per PATTERNS.md analog map):

| New file | v0.18 analog | What was inherited |
|----------|--------------|--------------------|
| `poc-mount-01-static.bats` | `register-spokes-01-static.bats` lines 130-139 | sentinel-grep + yq-shape + comment-aware peer-file negative |
| `register-poc-cluster-01-static.bats` | `register-spokes-01-static.bats` (full structural mirror) | RBAC literal greps + dry-run-then-apply pattern + token-safety negatives + skip-message literal + openssl probe negative |
| `poc-cluster-01-static.bats` | `fix-coredns-01-static.bats` + `create-clusters-02-hub-flux.bats` | strict-mode + sources-preflight-lib + comment-aware cluster-name greps + Taskfile wire-up |
| `docs-06-eks.bats` | `docs-02-architecture.bats` + `docs-04-gpu-notes.bats` | h1-before-Mermaid (MD041 safety) + multi-literal grep loop |
| `poc-isolation-01-static.bats` | `destroy-rebuild-01-static.bats` lines 148-200 | comment-filtered grep array iteration |
| `preflight-pre15.bats` | `preflight-pre13.bats` (script-content variant) | `awk` function-body bracketing for fail/warn discrimination |
| `repo-hygiene-04-poc.bats` | `repo-hygiene-02-taskfile.bats` | multi-literal grep loop + path allowlist + RESEARCH.md §Pattern 6 fixture-runner pattern |

`load 'test_helper'` + `[ -f "$VAR" ]` existence checks + `grep -F --` for literal text matches + `run` + `[ "$status" -eq 0/-ne 0 ]` style — all v0.18 conventions reused without invention.

## Decisions Made

- **gitleaks rule shape (Claude's Discretion default applied):** single combined rule (lower false-positive surface) anchoring on `(?ms)^kind:\s*Config[\s\S]*?users:[\s\S]*?token:\s*[A-Za-z0-9._-]{32,}`. Fixtures live under `tests/fixtures/gitleaks/` with per-path allowlist in `.gitleaks.toml`. Coverage: 1 positive (real-shape kubeconfig + inert bearer token, MUST be caught) + 1 negative (configmap with token field, MUST NOT be caught). [Plan 04 lands the rule; Wave 0 only ships the fixtures + bats invocation contract.]
- **Isolation file split-out (POC-02-iso planner-judgment defaulted to standalone):** Per VALIDATION.md §"Wave 0 Requirements" line 76, the optional explicit isolation file `poc-isolation-01-static.bats` was created as a standalone file rather than folded into `destroy-rebuild-01-static.bats`. Rationale: keeps the P31/D-12 contract surface explicit and greppable; future maintainers find isolation invariants under their canonical name; uses zero v0.18 file modifications (Wave 0 net-new property preserved).

## Deviations from Plan

None — plan executed exactly as written.

All 5 bats files in Task 1 were created verbatim per the plan's `<action>` block. All 4 files in Task 2 (2 bats + 2 fixtures) were created verbatim per the plan's `<action>` block, including the verbatim YAML content from RESEARCH.md §Pattern 6 lines 643-674.

The plan-source `poc-mount-01-static.bats` test 4 ("sentinel appears EXACTLY ONCE") includes a deliberate self-correcting double assignment to `count` — the first form (`grep -v '^[[:space:]]*#' | grep -cF`) is intentionally documented as incorrect (the sentinel IS a comment) and the second form (`grep -cF`) is the real test. This was preserved verbatim because the plan's source comment explains the educational intent.

## Issues Encountered

None.

## Verification Evidence

```
$ bats tests/bats/poc-isolation-01-static.bats
1..3
ok 1 P31 / D-12: v0.18 scripts have ZERO spoke-capsule mentions (comments excluded)
ok 2 P31 / D-12: v0.18 scripts have ZERO register-poc-cluster mentions
ok 3 P31 / D-12: v0.18 scripts have ZERO scripts/poc/ path mentions
exit=0

$ bats --count tests/bats/
271

$ bats tests/bats/ | grep -c '^ok '
220

$ bats tests/bats/ | grep -c '^not ok'
51

$ # Phase 7 GREEN: 12; Phase 7 RED: 51; v0.18 GREEN: 208 (zero regression)
```

## User Setup Required

None — no external service configuration required. Wave 0 is pure scaffolding (bats files + YAML fixtures); no scripts execute, no clusters created, no secrets needed.

## Next Phase Readiness

Plans 01-05 of Phase 7 are unblocked. Each subsequent plan task in the phase has its bats target pre-positioned:

- **Plan 01 (EKSDOC-01)** → `tests/bats/docs-06-eks.bats` already RED with 9 tests asserting Mermaid + 3 verbatim YAMLs + NOT-PROVED 3-item list + 7 CRDs + k3d-name negative.
- **Plan 02 (POC-01 + POC-02)** → `tests/bats/poc-mount-01-static.bats` (8 tests) + `tests/bats/register-poc-cluster-01-static.bats` (15 tests) RED.
- **Plan 03 (POC-03 + POC-04)** → `tests/bats/repo-hygiene-04-poc.bats` (11 tests, 6 RED) + `tests/bats/preflight-pre15.bats` (6 tests, 4 RED) RED.
- **Plan 04 (CAPCLU-01..04)** → `tests/bats/poc-cluster-01-static.bats` (11 tests) RED.
- **Plan 05 (verification + docs)** → optional, structural rollups.

The Nyquist gate is functioning as intended: every behavior contract is asserted before the implementing plan runs.

## Self-Check: PASSED

**Files verified to exist:**
- FOUND: tests/bats/poc-mount-01-static.bats
- FOUND: tests/bats/register-poc-cluster-01-static.bats
- FOUND: tests/bats/poc-cluster-01-static.bats
- FOUND: tests/bats/docs-06-eks.bats
- FOUND: tests/bats/poc-isolation-01-static.bats
- FOUND: tests/bats/preflight-pre15.bats
- FOUND: tests/bats/repo-hygiene-04-poc.bats
- FOUND: tests/fixtures/gitleaks/synthetic-kubeconfig.yaml
- FOUND: tests/fixtures/gitleaks/benign-configmap.yaml

**Commits verified to exist:**
- FOUND: cb1a95b (Task 1: bats stubs for POC seam + register + cluster + EKS doc + isolation)
- FOUND: 407ade2 (Task 2: preflight-pre15 + repo-hygiene-04-poc + 2 gitleaks fixtures)

---
*Phase: 07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc*
*Plan: 00*
*Completed: 2026-04-29*
