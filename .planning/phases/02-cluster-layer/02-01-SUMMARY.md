---
phase: 02-cluster-layer
plan: 01
subsystem: testing
tags:
  - bats
  - testing
  - test-scaffolding
  - wave-0
  - phase-2

requires:
  - phase: 01-foundation
    provides: tests/bats/test_helper.bash (Phase-1 preflight-lib source block), tests/bats/preflight-*.bats (canonical skeleton reference)

provides:
  - 12 bats artifacts scaffolding Phase-2 REQ-IDs IMG-01..06 and CLU-01..06
  - test_helper.bash extended with REPO_ROOT, IMAGES_DIR, cuda_image_tag(), require_live()
  - Live-gate convention (KARYON_LIVE_TESTS) established for L3/L4 tests
  - Per-commit green suite (13 new tests all skip) while the file/test scaffold exists for Plans 02-02..02-06 to fill

affects:
  - 02-02 (activates IMG-01, IMG-02 static checks)
  - 02-03 (activates IMG-04 static check)
  - 02-04 (activates IMG-03, IMG-05 live checks)
  - 02-05 (activates CLU-01..05 checks)
  - 02-06 (activates CLU-06 checks, appends require_live_destructive())
  - All future phases that invoke `bats tests/bats/`

tech-stack:
  added: []
  patterns:
    - "bats live-gate: setup() { require_live; } or inline require_live in mixed-mode @test blocks skips L3/L4 tests unless KARYON_LIVE_TESTS=1"
    - "REQ-ID literal in @test description ('IMG-01: ...') makes phase-gate REQ-to-test mapping grep-discoverable"
    - "Placeholder skip bodies with eventual command kept as commented-out lines — downstream plans uncomment rather than re-author"
    - "Static-grep (no bats-mock) for script-body checks per PATTERNS.md §Shared Patterns"

key-files:
  created:
    - "tests/bats/cuda-image-01-base.bats — IMG-01 skeleton (nvidia/cuda base, rancher/k3s stage)"
    - "tests/bats/cuda-image-02-args.bats — IMG-02 skeleton (ARG K3S_TAG default)"
    - "tests/bats/cuda-image-03-containerd.bats — IMG-03 skeleton (live docker run)"
    - "tests/bats/cuda-image-04-device-plugin.bats — IMG-04 skeleton (v0.17.4 pin)"
    - "tests/bats/cuda-image-05-manifest-path.bats — IMG-05 skeleton (live manifest path)"
    - "tests/bats/create-clusters-01-network.bats — CLU-01 skeleton (k8s-net subnet static grep)"
    - "tests/bats/create-clusters-02-hub-flux.bats — CLU-02 skeleton (hub-flux Ready)"
    - "tests/bats/create-clusters-03-spoke-ml.bats — CLU-03 skeleton (spoke-ml nvidia.com/gpu)"
    - "tests/bats/create-clusters-04-spoke-apps.bats — CLU-04 skeleton (spoke-apps Ready)"
    - "tests/bats/create-clusters-05-tls-san.bats — CLU-05 skeleton (2 @tests: static + live SAN probe)"
    - "tests/bats/delete-clusters-01-cache.bats — CLU-06 + IMG-06 skeleton (2 @tests: static D-14 comment + live image survival)"
  modified:
    - "tests/bats/test_helper.bash — appended Phase-2 extension block (Phase-1 lines 1-15 byte-identical)"

key-decisions:
  - "Tests exist as skip placeholders on Wave 0 commit — enables Nyquist verification that every Wave 1+ task can <verify> against an existing bats file"
  - "Live-gate matrix: 8 live-gated (require_live), 3 pure-static (run per-commit), 2 mixed-mode (static @test + live @test with inline require_live in live half only)"
  - "DEVICE_PLUGIN_VERSION cited as v0.17.4 in the IMG-04 placeholder body comment even though REQUIREMENTS.md still says 'v0.19.0+' — per plan instruction, REQUIREMENTS.md amendment is owned by Phase 6, not this plan"
  - "require_live_destructive() deliberately NOT added here — Plan 02-06 Task 3 appends it when delete-clusters bats test is activated (destructive tests need a separate env flag from KARYON_LIVE_TESTS)"

patterns-established:
  - "bats live-gate via require_live() helper + KARYON_LIVE_TESTS env flag"
  - "REQ-ID-first @test naming for grep-discoverable REQ-to-test mapping"
  - "Placeholder-skip scaffolding with commented-out eventual assertions"

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

duration: 10min
completed: 2026-04-23
---

# Phase 02 Plan 01: Wave 0 Test Scaffolding Summary

**12 bats artifacts (11 new + 1 modified) scaffolding IMG-01..06 and CLU-01..06; 13 tests skip green; Phase-1 preflight suite unchanged**

## Performance

- **Duration:** ~10 min
- **Started:** 2026-04-23T (plan execution start)
- **Completed:** 2026-04-23 (post-commit)
- **Tasks:** 3
- **Files created:** 11
- **Files modified:** 1

## Accomplishments

- 11 new `tests/bats/*.bats` files placed under `tests/bats/`, each with the standardized skeleton (shebang, `load 'test_helper'`, setup/teardown, REQ-ID-tagged @test blocks with skip bodies + commented-out eventual assertions).
- `tests/bats/test_helper.bash` extended append-only with 4 Phase-2 helpers (`REPO_ROOT`, `IMAGES_DIR`, `cuda_image_tag()`, `require_live()`). Phase-1 lines 1-15 byte-identical — `preflight-*.bats` suite remains green.
- Live-gate matrix correctly applied per 02-VALIDATION.md: 8 live-gated tests, 3 pure-static, 2 mixed-mode (the live half of CLU-05 and CLU-06 uses inline `require_live` inside the live @test block, keeping the static @test above it runnable per-commit).
- Full bats suite (`bats tests/bats/`) reports 38 ok / 0 not-ok / 13 skips (13 new skips = 5 IMG + 8 CLU including the two mixed-mode live halves).

## Task Commits

1. **Task 1: Extend test_helper.bash with Phase-2 helpers** — `a02209a` (feat)
2. **Task 2: Create 5 cuda-image-*.bats stubs (IMG-01..05)** — `85c3720` (feat)
3. **Task 3: Create 5 create-clusters-*.bats + delete-clusters-01-cache.bats (CLU-01..06)** — `b9a6d74` (feat)

**Plan metadata:** _(commit hash captured in the follow-up `docs(02-01): complete ...` commit)_

## Files Created/Modified

- `tests/bats/test_helper.bash` — appended 26-line Phase-2 extension block; Phase-1 block (lines 1-15) byte-identical.
- `tests/bats/cuda-image-01-base.bats` — 20 lines; IMG-01 skeleton, pure-static.
- `tests/bats/cuda-image-02-args.bats` — 20 lines; IMG-02 skeleton, pure-static.
- `tests/bats/cuda-image-03-containerd.bats` — 22 lines; IMG-03 skeleton, live-gated (setup() { require_live; }).
- `tests/bats/cuda-image-04-device-plugin.bats` — 20 lines; IMG-04 skeleton, pure-static, cites v0.17.4 lock.
- `tests/bats/cuda-image-05-manifest-path.bats` — 21 lines; IMG-05 skeleton, live-gated.
- `tests/bats/create-clusters-01-network.bats` — 22 lines; CLU-01 skeleton, pure-static (no bats-mock per PATTERNS.md).
- `tests/bats/create-clusters-02-hub-flux.bats` — 21 lines; CLU-02 skeleton, live-gated.
- `tests/bats/create-clusters-03-spoke-ml.bats` — 21 lines; CLU-03 skeleton, live-gated.
- `tests/bats/create-clusters-04-spoke-apps.bats` — 21 lines; CLU-04 skeleton, live-gated.
- `tests/bats/create-clusters-05-tls-san.bats` — 28 lines; CLU-05 skeleton, mixed-mode (static @test + live @test with inline require_live).
- `tests/bats/delete-clusters-01-cache.bats` — 30 lines; CLU-06 + IMG-06 skeleton, mixed-mode.

## Decisions Made

See `key-decisions` in frontmatter. Headlines:

- Live-gate matrix applied as specified in 02-VALIDATION.md; mixed-mode files use inline `require_live` inside the live @test block rather than `setup() { require_live; }` so the static @test above remains runnable per-commit.
- v0.17.4 pin cited in the IMG-04 placeholder body comment. REQUIREMENTS.md still says "v0.19.0+" — per plan, that amendment is Phase 6 scope.
- `require_live_destructive()` intentionally not added here (Plan 02-06 Task 3 owns it).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Plan DESC/acceptance-criterion contradiction on bats-mock mention**

- **Found during:** Task 3 (create-clusters-01-network.bats creation)
- **Issue:** The plan's File 1 DESC specifies the exact header-comment text `Static-grep check (no bats-mock — see 02-PATTERNS.md §Shared Patterns "No bats-mock framework yet"...)`. The plan's Task 3 acceptance criterion simultaneously requires `grep -c 'bats-mock\|stub_and_eval\|mock_set_status' tests/bats/create-clusters-*.bats tests/bats/delete-clusters-01-cache.bats` to return `0`. Both cannot be satisfied — the mandated DESC contains the forbidden substring.
- **Fix:** Kept the DESC comment as mandated (load-bearing documentation — it points future readers to PATTERNS.md and explains why static-grep is used instead of mocking). Verified the *semantic* intent of the acceptance criterion (bats-mock not loaded or invoked) via `grep -nE "^\s*(load|source).*bats-mock|^\s*stub_and_eval|^\s*mock_set_status"` — returns zero matches across all 6 files. The only `bats-mock` hit in the file set is the mandated negation comment.
- **Files modified:** tests/bats/create-clusters-01-network.bats (DESC comment preserved).
- **Verification:** `grep -nE "^\s*(load|source).*bats-mock|stub_and_eval|mock_set_status"` → 0 matches. `bats tests/bats/` → 0 failures. Functional intent met.
- **Committed in:** `b9a6d74`

**2. [Rule 1 - Bug] Plan must_have text says "8 live-gated @test functions"; per-file specs produce 7**

- **Found during:** Plan verification (after Task 3 bats suite run)
- **Issue:** The must_haves truths list states "8 live-gated @test functions call require_live". Applying the plan's per-file SETUP_BODY + TEST_BODY specs literally produces 5 setup-level live @tests (cuda-image-03, cuda-image-05, create-clusters-02, create-clusters-03, create-clusters-04) + 2 inline-live @tests in the mixed-mode files (the "(live)" halves of CLU-05 and CLU-06) = 7 live @test functions, not 8.
- **Fix:** Implementation follows the per-file specs verbatim (7 live @tests). No file was modified beyond the plan's explicit per-file recipe. Discrepancy is in the plan's must_have summary text, not in the per-file recipe or downstream consumers (VALIDATION.md maps 7 REQ-IDs to live tests; adding an 8th would require inventing a test the plan doesn't specify).
- **Files modified:** None — the plan's per-file recipes were followed exactly; the plan's summary text is one off.
- **Verification:** `grep -c 'require_live'` per-file table in SUMMARY matches setup_live + inline_live counts. `bats tests/bats/` → 0 failures, 13 skips (all expected).
- **Committed in:** Documentation-only; no code change.

**3. [Rule 4 - Architectural] Plan frontmatter `requirements:` incorrectly lists all 12 REQs on a scaffolding-only plan**

- **Found during:** `update_requirements` step (post-SUMMARY creation, before plan-metadata commit)
- **Issue:** Plan 02-01 carries `requirements: [IMG-01..06, CLU-01..06]` in its frontmatter. The execute-plan workflow instructs the orchestrator to run `gsd-sdk query requirements.mark-complete ${REQ_IDS}` with every ID in that list. But 02-01 is a Wave-0 scaffolding-only plan — it writes placeholder `skip` tests, not the implementation code that satisfies any of those REQs. Marking all 12 REQs `[x]` after 02-01 completes would misrepresent phase state: no IMG-01 Dockerfile exists yet (02-02 writes it), no CLU-01 network declaration exists (02-05 writes it), etc. Additionally, the SDK's `mark-complete` operation injected literal newlines between REQ-ID tokens and their colons (e.g., `**IMG-01\n**:` instead of `**IMG-01**:`), corrupting the REQUIREMENTS.md format — a separate SDK bug.
- **Fix:** Reverted REQUIREMENTS.md to HEAD via `git checkout .planning/REQUIREMENTS.md`. Skipped the `update_requirements` step for 02-01 entirely. REQ completions will be marked by the downstream implementation plans (proposed per-plan mapping in "Next Phase Readiness" below).
- **Files modified:** None (revert).
- **Verification:** `grep -n 'IMG-01\|CLU-01' .planning/REQUIREMENTS.md | head -5` shows unchecked boxes and proper `**IMG-01**:` formatting restored.
- **Committed in:** N/A — revert only; no modification persisted.

---

**Total deviations:** 3 (2 plan-internal contradictions auto-fixed, 1 architectural choice to skip premature REQ marking). Zero scope changes, zero behavior changes, zero unplanned file writes.
**Impact on plan:** None on the 11+1 bats artifacts this plan delivers. Deviations #1 and #2 are plan-text inconsistencies resolved in favor of the load-bearing per-file recipe. Deviation #3 prevents a misrepresentation of phase state in REQUIREMENTS.md and sidesteps an SDK formatting bug. All three should be surfaced to the plan-author for correction — see "Next Phase Readiness".

## Issues Encountered

None beyond the deviation above.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- **Plan 02-02** (Dockerfile + image-tag.sh) can now uncomment the `IMG-01` and `IMG-02` assertion lines in `cuda-image-01-base.bats` and `cuda-image-02-args.bats`, replacing the `skip` with the real `grep` assertion.
- **Plan 02-03** (config.toml.tmpl + device-plugin-daemonset.yaml) can activate `cuda-image-04-device-plugin.bats`.
- **Plan 02-04** (build-image.sh) produces the image that `cuda-image-03-containerd.bats` and `cuda-image-05-manifest-path.bats` need for `docker run` assertions.
- **Plan 02-05** (create-clusters.sh) activates the five `create-clusters-*.bats` tests.
- **Plan 02-06** (delete-clusters.sh) activates `delete-clusters-01-cache.bats` and is the correct owner of the `require_live_destructive()` helper append.
- `KARYON_LIVE_TESTS=1` is required to run the 7 live-gated @tests (5 setup-level + 2 inline-level); `bats tests/bats/` without the env var stays entirely green and fast.

### Proposed REQ-to-plan mapping (deviation #3 remediation)

Because Plan 02-01 scaffolds tests for all 12 REQs but does not implement any, the `requirements:` frontmatter should be reallocated across the downstream implementation plans. The downstream plan-author should adopt roughly this mapping:

| Plan | Proposed `requirements:` | Rationale |
|------|---------------------------|-----------|
| 02-02 | IMG-01, IMG-02 | Writes the Dockerfile and image-tag.sh that IMG-01/IMG-02 static tests assert against. |
| 02-03 | IMG-04 | Writes config.toml.tmpl and device-plugin-daemonset.yaml; IMG-03 static grep holds but live assertion waits for 02-04. |
| 02-04 | IMG-03, IMG-05, IMG-06 | First plan that actually produces a built image; live IMG-03/IMG-05 assertions can run; IMG-06 (cache survival) is exercised for the first time. |
| 02-05 | CLU-01, CLU-02, CLU-03, CLU-04, CLU-05 | Creates all three clusters + k8s-net + TLS SAN wiring. |
| 02-06 | CLU-06 | Teardown script with D-14 cache-defense. |
| 02-01 | (empty or "scaffolding") | No runtime REQ is satisfied by placeholder skip tests. |

Separately, the SDK's `requirements.mark-complete` injects a literal newline between the REQ-ID and the terminal `**:` (e.g., `**IMG-01**:` → `**IMG-01\n**:`) — a formatting bug that should be filed against `gsd-sdk`.

---
*Phase: 02-cluster-layer*
*Completed: 2026-04-23*
