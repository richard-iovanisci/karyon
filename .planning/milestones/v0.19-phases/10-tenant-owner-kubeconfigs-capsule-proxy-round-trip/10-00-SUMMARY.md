---
phase: 10-tenant-owner-kubeconfigs-capsule-proxy-round-trip
plan: 00
subsystem: testing
tags: [bats, capsule-proxy, tenant-kubeconfig, gitleaks, p29, regression-gate, wave-0, nyquist]

# Dependency graph
requires:
  - phase: 07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc
    provides: D-14 leak defenses (.gitignore globs + .gitleaks.toml kubeconfig-bearer-token rule + tests/fixtures/gitleaks/synthetic-kubeconfig.yaml positive fixture); P31 isolation contract (scripts/poc/capsule/ namespace); docs/poc-capsule.md frontmatter scope: line carrying the Phase 10/11 forward-pointer
  - phase: 08-capsule-capsule-proxy-bare-minimum-install
    provides: D-08-09 cluster-info skip-gate pattern (NOT KARYON_LIVE_TESTS env-var); D-08-11 capsule-proxy chart certgen Secret produced by kube-webhook-certgen Job; CAP-01..03 invariants for proxy-07 regression-rerun
  - phase: 09-tenants-flux-multi-tenancy-lockdown
    provides: D-09-02 per-tenant gitops-reconciler SA (the only owner Phase 10 supports per D-10-03); TEN-01..06 + P27 invariants for proxy-07 regression-rerun; D-09-08 Wave 0 RED bats scaffold pattern (Phase 10 inheritance)
provides:
  - 7 bats files under tests/bats/proxy-*.bats (45 @tests total) locking the PROXY-01/02/03 contract before script + doc land
  - Static script-shape contract (proxy-01) — 12 @tests asserting head-block, args, kubeconfig literals, anti-pattern lints, Pitfall 10-P1 corrected jsonpath
  - Static leak-defense regression-gate (proxy-02) — 5 @tests verifying Phase 7 D-14 globs/rule/allowlist still intact (GREEN-by-design)
  - Static doc-shape contract (proxy-03) — 8 @tests asserting docs/poc-capsule.md H2 section + cross-link literals + frontmatter scope-line update
  - Live script-invocation (proxy-04) — 7 @tests covering YAML parse, JWT decode, --write-to validation (positive + negative including symlink escape), D-10-04 fail-fast
  - Live proxy-LIST + 403 falsifier (proxy-05) — 2 @tests with corrected qualitative shape per Pitfall 10-P3 (NOT count comparison)
  - Live synthetic-fixture (proxy-06) — 3 @tests for git check-ignore + gitleaks fires (Pitfall 10-P5 repo-relative paths)
  - Live multi-cluster regression-rerun (proxy-07) — 8 @tests reasserting Phase 7 P31 + Phase 8 CAP-01..03 + Phase 9 TEN-01..06 + ADR-004
affects: [10-01, 10-02, 11]

# Tech tracking
tech-stack:
  added: []  # No new tools/libraries — bats 1.11.0 + yq + jq + gitleaks + kubectl already pinned via asdf
  patterns:
    - "Phase 10 Wave 0 RED bats scaffold (Phase 7/8/9 D-09-08 inheritance) — full contract locked BEFORE the script lands"
    - "Cluster-info skip-gate (Phase 8 D-08-09 inheritance) for live bats; NEVER KARYON_LIVE_TESTS env-var"
    - "Pitfall 10-P3 corrected falsifier: qualitative 403 + 'cannot list resource \"namespaces\"' assertion, NOT quantitative count comparison"
    - "Pitfall 10-P5 corrected check-ignore: repo-relative paths (cd \"$REPO_ROOT\" + karyon-tenants/test.kubeconfig), NOT absolute /tmp paths"
    - "grep -F -- literal-iter for static script-shape lints (Phase 8 WR-01..04 hardening)"
    - "Strip-comments-then-grep pattern (grep -v '^#' | grep -F) for negative-lint anti-pattern checks"

key-files:
  created:
    - tests/bats/proxy-01-static-script.bats
    - tests/bats/proxy-02-static-leak-defenses.bats
    - tests/bats/proxy-03-static-doc.bats
    - tests/bats/proxy-04-live-issue.bats
    - tests/bats/proxy-05-live-list-filter.bats
    - tests/bats/proxy-06-live-fixture.bats
    - tests/bats/proxy-07-live-regression.bats
  modified: []

key-decisions:
  - "Followed plan exactly — zero deviations. Pitfall 10-P3 falsifier shape (qualitative 403 + error string, not count comparison) was already baked into the plan; Pitfall 10-P5 repo-relative paths likewise; both implemented as written"
  - "@test 3 of proxy-07 (HelmRelease capsule Ready=True) is RED-by-design at landing — Phase 8 BLOCKER G-04 outer Kustomization split-path means capsule-proxy not yet installed live. GREEN at Plan 10-02 verifier time after suspend+apply staging (Plan 09-04 precedent)"
  - "proxy-06 omits the cluster-info gate (3 @tests are filesystem-only — no cluster needed); proxy-04, 05, 07 all use the cluster-info gate per Phase 8 D-08-09 inheritance"

patterns-established:
  - "Phase 10 'proxy-' bats prefix conflicts with NO existing tests/bats/*.bats filename — namespace clean for proxy-04..07 live + proxy-01..03 static partition"
  - "Per-task atomic commit cadence: 7 tasks → 7 commits (test(10-00): land ... bats), each commit body documents which @tests + which contracts (PROXY-01/02/03 + D-IDs + Pitfall IDs)"

requirements-completed: [PROXY-01, PROXY-02, PROXY-03]  # Coverage scaffolded; Plans 10-01 + 10-02 turn the scaffolded contracts GREEN

# Metrics
duration: 7m5s
completed: 2026-05-05
---

# Phase 10 Plan 10-00: Wave 0 RED Bats Scaffold (Nyquist Gate) Summary

**7 bats files (45 @tests) locking the PROXY-01/02/03 contract for `scripts/poc/capsule/issue-tenant-kubeconfig.sh` BEFORE the script lands — mirrors Phase 7/8/9 D-09-08 Wave 0 RED scaffold pattern.**

## Performance

- **Duration:** 7m5s
- **Started:** 2026-05-05T17:24:14Z
- **Completed:** 2026-05-05T17:31:26Z
- **Tasks:** 7
- **Files created:** 7 (`tests/bats/proxy-01..07-*.bats`)
- **Files modified:** 0

## Accomplishments

- All 7 D-10-09 Wave 0 RED bats files landed under `tests/bats/proxy-*.bats` — partition matches PATTERNS.md analog table verbatim (proxy-01..03 static + proxy-04..07 live).
- 45 @tests authored: 12 static script-shape + 5 static leak-defense + 8 static doc-shape + 7 live script-invocation + 2 live LIST/403 + 3 live fixture + 8 live regression.
- Three load-bearing CONTEXT.md corrections per RESEARCH §"Pitfalls" baked into bats verbatim:
  - **Pitfall 10-P1**: proxy-01 asserts script reads `'{.data.tls\.crt}'` (NOT `ca.crt`) + anti-pattern lint forbids `ca.crt` jsonpath.
  - **Pitfall 10-P3**: proxy-05 falsifier is QUALITATIVE (403 + `'cannot list resource "namespaces"'` error string), NOT quantitative count comparison.
  - **Pitfall 10-P5**: proxy-06 `cd "$REPO_ROOT"` + relative `karyon-tenants/test.kubeconfig` for `git check-ignore` (absolute paths fail silently).
- ALL live bats use cluster-info skip-gate (Phase 8 D-08-09 inheritance); ZERO `KARYON_LIVE_TESTS` env-var references (verified via `grep -F`).
- ZERO modifications to `.gitignore` / `.gitleaks.toml` / scripts / docs / pocs / tests/fixtures (regression-gate inheritance preserved).

## Task Commits

Each task was committed atomically:

1. **Task 1: Land static script-shape bats (proxy-01-static-script.bats)** — `dfaa20e` (test)
2. **Task 2: Land static leak-defense bats (proxy-02-static-leak-defenses.bats)** — `9108589` (test)
3. **Task 3: Land static doc-shape bats (proxy-03-static-doc.bats)** — `937e7ef` (test)
4. **Task 4: Land live script-invocation bats (proxy-04-live-issue.bats)** — `929c754` (test)
5. **Task 5: Land live proxy-LIST + 403 falsifier bats (proxy-05-live-list-filter.bats)** — `5d6462f` (test)
6. **Task 6: Land live synthetic-fixture bats (proxy-06-live-fixture.bats)** — `d973448` (test)
7. **Task 7: Land live regression-rerun bats (proxy-07-live-regression.bats)** — `c7354fb` (test)

**Plan metadata commit:** _pending — final commit captures SUMMARY.md + STATE.md + ROADMAP.md_

## Files Created/Modified

- `tests/bats/proxy-01-static-script.bats` — 12 @tests asserting script-shape contract; RED at landing (script not yet written)
- `tests/bats/proxy-02-static-leak-defenses.bats` — 5 @tests asserting Phase 7 D-14 globs/rule/allowlist intact; **GREEN at landing** (regression-gate by design)
- `tests/bats/proxy-03-static-doc.bats` — 8 @tests asserting docs/poc-capsule.md H2 section + cross-links; RED at landing on @test 2 onward (H2 not yet appended); @test 1 GREEN (doc exists from Phase 7)
- `tests/bats/proxy-04-live-issue.bats` — 7 @tests for live script invocation, JWT decode, --write-to validation, D-10-04 fail-fast; RED at landing (status 127 = command not found)
- `tests/bats/proxy-05-live-list-filter.bats` — 2 @tests for proxy LIST + 403 falsifier (Pitfall 10-P3 corrected); RED at landing (script + capsule-proxy live install both needed)
- `tests/bats/proxy-06-live-fixture.bats` — 3 @tests for git check-ignore + gitleaks fires (Pitfall 10-P5 corrected); **GREEN at landing** (Phase 7 D-14 inheritance)
- `tests/bats/proxy-07-live-regression.bats` — 8 @tests for Phase 7+8+9+ADR-004 invariant rerun; **7/8 GREEN at landing**, @test 3 RED-by-design (Phase 8 BLOCKER G-04 — capsule-proxy NOT yet installed live; GREEN at Plan 10-02 after suspend+apply)

## RED/GREEN Status at Landing Time

| File | @tests | Status | Reason |
|------|--------|--------|--------|
| proxy-01-static-script.bats | 12 | RED | Script `scripts/poc/capsule/issue-tenant-kubeconfig.sh` not yet written (Plan 10-01 lands it) |
| proxy-02-static-leak-defenses.bats | 5 | **GREEN** | Phase 7 D-14 leak defenses already shipped — regression-gate by design |
| proxy-03-static-doc.bats | 8 | 1 GREEN, 7 RED | Doc exists (Phase 7); H2 section + frontmatter scope-line not yet appended (Plan 10-01) |
| proxy-04-live-issue.bats | 7 | RED | Cluster reachable but script not yet written (status 127); GREEN after Plan 10-01 |
| proxy-05-live-list-filter.bats | 2 | RED | Cluster reachable but script + capsule-proxy live install both needed (D-08-13 push-gate deferred) |
| proxy-06-live-fixture.bats | 3 | **GREEN** | Phase 7 D-14 leak defenses + Pitfall 10-P5 repo-relative path implemented correctly |
| proxy-07-live-regression.bats | 8 | 7 GREEN, 1 RED | All v0.18 + Phase 9 invariants intact; CAP-01 HR Ready=True RED (Phase 8 G-04 split-path; Plan 10-02 suspend+apply) |

**Total at landing:** 17 GREEN, 28 RED (script + Plan 10-01 dependencies). After Plan 10-01: ~36 GREEN. After Plan 10-02 verifier: 45 GREEN.

## Decisions Made

None — plan executed exactly as written. The three Pitfall corrections (10-P1 tls.crt jsonpath, 10-P3 qualitative 403 falsifier, 10-P5 repo-relative paths) were already baked into the plan's `<action>` blocks and implemented as specified.

## Deviations from Plan

None — plan executed exactly as written.

**Total deviations:** 0
**Impact on plan:** None. All 7 task `<acceptance_criteria>` blocks satisfied verbatim.

## Issues Encountered

- **Bats CLI flag mismatch**: Plan acceptance criteria reference `bats --tap --dry-run` (plan-side authoring artifact), but installed bats 1.11.0 does NOT support `--dry-run` (only `--count` is parse-only). Resolved by using `bats --count` for parse validation throughout — equivalent semantic gate (counts emit if and only if the file parses cleanly). No bats file edits required.

## Wave 0 → Wave 1 Handoff (Plan 10-01 Constraints)

Plan 10-01 author MUST honor the contracts locked here:

1. **DO NOT modify `.gitignore` or `.gitleaks.toml`.** proxy-02 is the regression gate; mutation will turn it RED.
2. **Implement script per RESEARCH §A1 + §C1..C5 verbatim.** proxy-01 + proxy-04 grep-assert exact literals (`kubectl --context=k3d-spoke-capsule`, `server: https://127.0.0.1:30443`, `current-context: tenant-${TENANT}-via-proxy`, `realpath -m`, `karyon-tenants`, `Available SAs in this tenant`, `{.data.tls\.crt}` jsonpath); script must NOT contain `insecure-skip-tls-verify`, `--mode direct`, or `{.data.ca\.crt}`.
3. **Append `## Tenant kubeconfig delivery contract` H2 to `docs/poc-capsule.md` per RESEARCH §A3.** Section MUST contain: `### Quickstart`, `### Contract`, `### Mandatory invariants`, `### Cross-references` subsections + literals enumerated in proxy-03 (`https://127.0.0.1:30443`, `TokenRequest API`, `${TMPDIR:-/tmp}/karyon-tenants/`, `realpath -m`, `kubeconfig-bearer-token`, `IRSA`, `gitops-reconciler`, etc.).
4. **Update frontmatter `scope:` line.** Replace `Phases 10/11 will add tenant kubeconfig delivery contract and ordered teardown procedure respectively` with phrasing that includes `tenant kubeconfig delivery contract` (positive grep) and OMITS `Phases 10/11 will add` (negative grep).

## Wave 0 → Wave 2 Handoff (Plan 10-02 Constraints)

Plan 10-02 verifier MUST:

1. **Stage capsule-proxy live** via Plan 09-04 suspend+apply pattern (suspend `flux-system` Kustomization, manually apply rendered chart, validate, resume) — D-08-13 push-gate is deferred; chart is NOT yet reconciled live by hub-flux on spoke-capsule.
2. **Document override in 10-VERIFICATION.md as `passed_with_overrides`** because proxy-05 + proxy-07 @test 3 require live capsule-proxy install (out of band per push-gate deferral).
3. **Run full prior-phase bats suites** (`bats tests/bats/poc-isolation-01-static.bats tests/bats/capsule-install-{06..10}-live-*.bats tests/bats/tenants-{01..12}-*.bats`) for completeness — proxy-07 is an inline-assertion shortcut, but full re-runs catch any subtle regressions inline assertions miss.

## Next Phase Readiness

- **Plan 10-01 unblocked:** All Wave 0 contracts authored. Plan 10-01 (script + doc) lands the artifacts the static + live bats already grep-assert against.
- **Plan 10-02 unblocked:** Multi-cluster regression-rerun bats authored (proxy-07); will be reused by the verifier alongside full prior-phase suite runs.
- **No carryover blockers introduced.** Phase 8 G-03/G-04 BLOCKERs remain deferred (Plan 10-02 suspend+apply absorbs at verifier time).

## Self-Check: PASSED

**Verified files exist on disk:**
- `tests/bats/proxy-01-static-script.bats` (12 @tests, 118 lines)
- `tests/bats/proxy-02-static-leak-defenses.bats` (5 @tests, 46 lines)
- `tests/bats/proxy-03-static-doc.bats` (8 @tests, 93 lines)
- `tests/bats/proxy-04-live-issue.bats` (7 @tests, 108 lines)
- `tests/bats/proxy-05-live-list-filter.bats` (2 @tests, 78 lines)
- `tests/bats/proxy-06-live-fixture.bats` (3 @tests, 62 lines)
- `tests/bats/proxy-07-live-regression.bats` (8 @tests, 71 lines)

**Verified commits exist in git log:**
- `dfaa20e` test(10-00): land static script-shape bats
- `9108589` test(10-00): land static leak-defense regression-gate bats
- `937e7ef` test(10-00): land static doc-shape bats
- `929c754` test(10-00): land live script-invocation bats
- `5d6462f` test(10-00): land live proxy-LIST + 403 falsifier bats
- `d973448` test(10-00): land live synthetic-fixture bats
- `c7354fb` test(10-00): land live regression-rerun bats

**Verified plan-level invariants:**
- 7 files / 45 @tests / 7 commits — exact match to plan `<success_criteria>`
- ZERO modifications outside `tests/bats/proxy-*.bats` (verified `git diff --stat` empty for all read-only paths)
- ZERO `KARYON_LIVE_TESTS` references (verified `grep -F` exit 1)
- 3 live bats use cluster-info gate (proxy-04, 05, 07); proxy-06 is filesystem-only (no cluster needed)

---
*Phase: 10-tenant-owner-kubeconfigs-capsule-proxy-round-trip*
*Completed: 2026-05-05*
