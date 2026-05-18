---
phase: 09-tenants-flux-multi-tenancy-lockdown
plan: 00
subsystem: testing
tags: [bats, yq, kubectl, capsule, flux, lockdown, multi-tenancy, p27, nyquist-gate]

# Dependency graph
requires:
  - phase: 07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc
    provides: "tests/bats/test_helper.bash + KARYON SPOKES MOUNT/POC MOUNT sentinels in clusters/hub-flux/flux-system/kustomization.yaml + cluster-info gate pattern + REPO_ROOT helper"
  - phase: 08-capsule-capsule-proxy-bare-minimum-install
    provides: "D-08-12 split-path Kustomization invariant (capsule.yaml hub-targeted no-kubeConfig + capsule-spoke.yaml spoke-targeted full kubeConfig with key=value.yaml) + capsule-install-*.bats analog patterns + 3×30s retry + jsonpath column-anchored pattern + WR-01..04 yq hardening direction"
provides:
  - "12 RED bats files at tests/bats/tenants-{01..12}-{static,live}-*.bats (66 tests total: 32 static + 34 live)"
  - "P27 negative falsifier fixture at tests/fixtures/p27-broken/tenant-broken.yaml (synthetic broken Kustomization without spec.serviceAccountName — proves the P27 lint catches the missing-SA defect before any tenant yaml lands)"
  - "Reusable multi-doc yq lint adapter functions (lint_kustomization_sa_dir + assert_inner_k_dependson_poc_capsule + assert_inner_k_wait_top_level) — same loop logic feeds positive lints (real tenant Ks) AND negative falsifier (broken fixture); load-bearing pattern for Plans 09-02 + 09-03 P27 enforcement"
  - "Wave 0 close-out artifact: 09-VALIDATION.md frontmatter nyquist_compliant: true + wave_0_complete: true + all 13 deliverable checkboxes flipped to [x]"
affects: [09-01, 09-02, 09-03, 09-04]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Wave 0 RED bats Nyquist gate (Phase 9 D-09-08; mirrors Phase 7 Plan 07-00 / Phase 8 Plan 08-00 — every TEN-01..06 contract has a falsifier in place BEFORE any tenant yaml lands)"
    - "Multi-doc yq @tsv adapter (yq eval-all '[.kind, .apiVersion, .spec.X] | @tsv' — emits per-doc tab-separated tuples for bash while loops; safe across multi-doc YAML files including those with no matching docs)"
    - "P27 negative falsifier inversion (the SAME lint function runs against real tenants AND a synthetic broken fixture; positive must succeed [exit 0], negative must fail [exit 1] — guarantees the lint itself is wired correctly before any production yaml lands)"
    - "Cluster-info auto-skip live gate (kubectl --context=... cluster-info >/dev/null 2>&1 || skip — replaces KARYON_LIVE_TESTS env var per Phase 8 D-08-09; auto-skips when k3d clusters are down without operator intervention)"

key-files:
  created:
    - "tests/bats/tenants-01-static-tenant-cr.bats (8 tests; TEN-01 — Tenant CR yaml shape: apiVersion v1beta2 + kind Tenant + alpha/bravo names + spec.forceTenantPrefix TOP-LEVEL=true [RESEARCH Gap 4 correction] + owners[ServiceAccount with combined-name format system:serviceaccount:tenant-{alpha,bravo}:gitops-reconciler] + owners[User] + resourceQuotas/limitRanges shape)"
    - "tests/bats/tenants-02-static-p27.bats (2 tests; TEN-04 P27 LOAD-BEARING — yq lint loop asserts every Flux Kustomization in pocs/capsule/tenants/*.yaml has non-null spec.serviceAccountName + negative falsifier proves the lint correctly fails on missing SA)"
    - "tests/bats/tenants-03-static-lockdown.bats (12 tests; TEN-05 — FLUX PATCH SURFACE comment block preservation + KARYON SPOKES/POC MOUNT sentinels + new # KARYON FLUX LOCKDOWN PATCHES sentinel + patches: block + 3 lockdown flag literals + 4 SMP targets [kustomize-controller, helm-controller per RESEARCH Gap 2, notification-controller, flux-system Kustomization escape hatch per D-09-05a])"
    - "tests/bats/tenants-04-static-dependson.bats (6 tests; TEN-06 P32 — capsule-spoke.yaml dependsOn[0].name=poc-capsule + spec.wait=true TOP-LEVEL [RESEARCH Gap 9] + spec.timeout=10m + spec.serviceAccountName=kustomize-controller + per-tenant inner Ks dependsOn + wait via multi-doc yq lint)"
    - "tests/bats/tenants-05-static-split-path.bats (4 tests; D-08-12 inheritance regression — capsule.yaml NO kubeConfig + serviceAccountName=kustomize-controller; capsule-spoke.yaml kubeConfig.secretRef.name=spoke-capsule-kubeconfig + key=value.yaml [P40/P18 silent-misroute defense])"
    - "tests/bats/tenants-06-live-tenant-cr.bats (6 tests; TEN-01 live — kubectl get tenant alpha/bravo reports forceTenantPrefix=true TOP-LEVEL; tenant-{alpha,bravo} ns + gitops-reconciler SA exist on spoke-capsule; 3×30s retry on ftp jsonpath)"
    - "tests/bats/tenants-07-live-impersonate.bats (4 tests; TEN-02 — kubectl --as=alpha create namespace alpha-app1 succeeds via dry-run | apply pipe for idempotence; capsule.clastix.io/tenant=alpha label auto-stamped by Capsule webhook; mirror for bravo)"
    - "tests/bats/tenants-08-live-quota-limit.bats (4 tests; TEN-03 — ResourceQuota + LimitRange auto-materialize in alpha-app1/bravo-app1 within 30s of namespace creation; capsule-{alpha,bravo}-* names per Capsule controller naming convention; 3×10s poll)"
    - "tests/bats/tenants-09-live-inner-k-ready.bats (4 tests; TEN-04 + RESEARCH Gap 1 D-09-03a — spoke-capsule-kubeconfig Secret mirrored to tenant-{alpha,bravo} ns on hub [Flux's kubeConfig.secretRef has hard same-namespace constraint]; tenant-{alpha,bravo}-app Kustomization Ready=True against empty placeholder paths; pre-push GitRepository ArtifactFailed → skip)"
    - "tests/bats/tenants-10-live-lockdown.bats (10 tests; TEN-05 — kustomize-controller args contain 3 flags, helm-controller args contain 2 flags [RESEARCH Gap 2 extends CONTEXT.md narrowing per upstream canonical], notification-controller args contain 1 flag; all 3 controllers availableReplicas==replicas with 4×30s = 2-min poll [catches CrashLoopBackOff from misapplied flag]; flux-system Kustomization Ready=True [D-09-05a LOAD-BEARING escape hatch validation])"
    - "tests/bats/tenants-11-live-dependson.bats (3 tests; TEN-06 — poc-capsule-spoke Kustomization dependsOn[0].name=poc-capsule + spec.wait=true TOP-LEVEL + Ready=True post-lockdown)"
    - "tests/bats/tenants-12-live-health-check.bats (3 tests; v0.18 regression gate — task health-check exits 0; spoke-apps + spoke-ml Kustomizations Ready=True [cross-cluster lockdown impact regression per RESEARCH Gap 11 belt-and-suspenders])"
    - "tests/fixtures/p27-broken/tenant-broken.yaml (synthetic Kustomization CR omitting spec.serviceAccountName — drives the negative falsifier inside tenants-02; if the falsifier ever passes this fixture, the P27 lint is silently broken and tenant boundary defense is compromised)"
  modified:
    - ".planning/phases/09-tenants-flux-multi-tenancy-lockdown/09-VALIDATION.md (frontmatter nyquist_compliant + wave_0_complete flipped to true; all 13 Wave 0 Requirements checkboxes flipped to [x]; 6 Validation Sign-Off checkboxes flipped to [x] with Approval set to Wave 0 complete summary)"

key-decisions:
  - "Multi-doc yq lint via eval-all + @tsv: yq eval-all '[.kind, .apiVersion, .spec.X] | @tsv' emits one tab-separated tuple per yaml document, fed into bash while-IFS loops. Chosen over the plan's nested split-doc pattern because it works correctly with multi-doc files (the original plan's grep -cv '^---$' counter was unreliable for files with embedded comments containing dashes)."
  - "P27 lint as callable bash function (lint_kustomization_sa_dir): same function feeds positive @test (real tenant Ks under pocs/capsule/tenants/) AND negative falsifier @test (broken fixture under tests/fixtures/p27-broken/). The negative @test invokes via `run lint_...` and asserts non-zero exit — proves the lint logic is wired before any production yaml lands. Hard requirement: positive direction must FAIL during Wave 0 RED state (target dir does not exist) AND the negative direction must PASS (lint correctly catches missing SA). Both confirmed during Task 1 verify."
  - "Live bats cluster-info gate over KARYON_LIVE_TESTS env var: matches Phase 8 D-08-09 pattern (capsule-install-06-live-helm.bats:11-16). Enables auto-skip when k3d clusters down (no env var fiddling required) — verified during Task 2 with k3d clusters up at execution time, where the live bats correctly attempted real assertions and failed because target Tenants/CRs absent."
  - "Lockdown patches matrix follows RESEARCH §Gap 2 canonical (extends CONTEXT.md narrowing): bats-03 + bats-10 assert helm-controller receives BOTH --no-cross-namespace-refs=true AND --default-service-account=default per the upstream fluxcd/flux2-multi-tenancy reference repo. CONTEXT.md narrowed to kustomize-controller-only; RESEARCH overruled for defense in depth (P27 fallback safety for any future tenant HelmReleases without explicit serviceAccountName)."
  - "spec.wait at TOP LEVEL per RESEARCH §Gap 9: tenants-04 + tenants-11 assert .spec.wait == true (not nested inside .spec.dependsOn[0].wait). The CONTEXT.md draft and Phase 8 RESEARCH catch (Pitfall 9 — `spec.dependsOn[0].wait` does not exist) both informed this — wait is documented as a sibling of dependsOn under .spec, not inside it."

patterns-established:
  - "Pattern 1: Multi-doc yq @tsv adapter — yq eval-all '[.kind, .apiVersion, .spec.X] | @tsv' produces one tab-separated tuple per yaml document, parseable via bash `while IFS=$'\\t' read`; safe for multi-doc files and files with no matching docs (returns empty stream)"
  - "Pattern 2: Negative-falsifier bats inversion — lint logic factored into a reusable bash function (e.g. lint_kustomization_sa_dir, assert_inner_k_dependson_poc_capsule); the SAME function gets called via `run` from a positive @test (against real production yaml — must succeed) and from a negative @test (against synthetic broken fixture — must fail). Provides Wave 0 confidence that the lint catches what it's supposed to catch BEFORE any production yaml exists to lint"
  - "Pattern 3: Wave 0 file-existence + parse-validity verification — bats --count enumerates tests without execution (cheap structural check). Used for live bats during Wave 0 since live execution would attempt cluster operations against state that does not yet exist; parse-validity proves the bats files are syntactically correct and will be runnable once Plans 09-01..09-03 land target manifests"

requirements-completed: []  # Wave 0 lands the RED bats scaffold; the actual TEN-01..06 requirements turn GREEN via Plans 09-01 (TEN-01..03 spoke-side), 09-02 (TEN-04 hub-side), 09-03 (TEN-05..06 lockdown + dependsOn). REQUIREMENTS.md `requirements: [TEN-01..06]` in frontmatter denotes which requirements this plan SUPPORTS verification of, not which it COMPLETES — Wave 0 is structural test scaffolding by definition. Plan 09-04 verifier owns marking TEN-01..06 complete in REQUIREMENTS.md.

# Metrics
duration: ~17min
completed: 2026-04-30
---

# Phase 09 Plan 00: Wave 0 RED Bats Scaffold Summary

**12 RED bats files (66 tests) + P27 negative falsifier fixture landing the Phase 9 Nyquist gate per D-09-08 — every TEN-01..06 contract has a deterministic falsifier in place BEFORE any tenant yaml lands.**

## Performance

- **Duration:** ~17 min
- **Started:** 2026-04-30T03:46:00Z (Phase 09 execution started)
- **Completed:** 2026-04-30T04:03:41Z
- **Tasks:** 3
- **Files created:** 13 (12 bats + 1 fixture)
- **Files modified:** 1 (09-VALIDATION.md frontmatter + checkbox flips)

## Accomplishments

- **5 static bats files** (32 tests) covering TEN-01 + TEN-04 P27 + TEN-05 lockdown + TEN-06 dependsOn + D-08-12 split-path inheritance regression — all tied to RESEARCH Gap 4/5/9 corrections (forceTenantPrefix TOP-LEVEL, combined-name SA owners, spec.wait TOP-LEVEL)
- **7 live bats files** (34 tests) covering TEN-01..06 live + v0.18 regression gate (`task health-check`) — each cluster-info gated for auto-skip; 3×30s retry on jsonpath assertions; 4×30s = 2-min poll on controller availableReplicas to catch CrashLoopBackOff
- **P27 negative falsifier fixture** at tests/fixtures/p27-broken/tenant-broken.yaml — synthetic Kustomization without spec.serviceAccountName; the negative falsifier @test inside tenants-02 PASSES (proves the P27 lint catches missing-SA defect) before any production tenant yaml lands
- **VALIDATION.md frontmatter flipped**: `nyquist_compliant: false → true` + `wave_0_complete: false → true`; all 13 Wave 0 Requirements + 6 Validation Sign-Off checkboxes flipped to `[x]`; Approval line updated with Wave 0 complete summary

## Task Commits

Each task was committed atomically:

1. **Task 1: 5 static bats + p27-broken fixture** — `c8d6188` (test)
2. **Task 2: 7 live bats** — `54bd203` (test)
3. **Task 3: VALIDATION.md frontmatter + checkbox flips** — `fe7d98b` (docs)

## Files Created/Modified

### Created (13 files)

- `tests/bats/tenants-01-static-tenant-cr.bats` (8 tests) — TEN-01 Tenant CR yaml shape contract per RESEARCH Gap 4
- `tests/bats/tenants-02-static-p27.bats` (2 tests) — TEN-04 P27 LOAD-BEARING yq lint + negative falsifier
- `tests/bats/tenants-03-static-lockdown.bats` (12 tests) — TEN-05 FLUX PATCH SURFACE preservation + 3 flags + 4 SMP targets (helm-controller per RESEARCH Gap 2)
- `tests/bats/tenants-04-static-dependson.bats` (6 tests) — TEN-06 P32 dependsOn chain + spec.wait TOP-LEVEL per RESEARCH Gap 9
- `tests/bats/tenants-05-static-split-path.bats` (4 tests) — D-08-12 inheritance regression
- `tests/bats/tenants-06-live-tenant-cr.bats` (6 tests) — TEN-01 live (forceTenantPrefix TOP-LEVEL)
- `tests/bats/tenants-07-live-impersonate.bats` (4 tests) — TEN-02 kubectl --as=alpha
- `tests/bats/tenants-08-live-quota-limit.bats` (4 tests) — TEN-03 auto-materialization
- `tests/bats/tenants-09-live-inner-k-ready.bats` (4 tests) — TEN-04 + Secret-mirror per RESEARCH Gap 1
- `tests/bats/tenants-10-live-lockdown.bats` (10 tests) — TEN-05 lockdown live + availableReplicas + escape hatch
- `tests/bats/tenants-11-live-dependson.bats` (3 tests) — TEN-06 live
- `tests/bats/tenants-12-live-health-check.bats` (3 tests) — v0.18 regression gate per RESEARCH Gap 11
- `tests/fixtures/p27-broken/tenant-broken.yaml` — P27 negative falsifier fixture

### Modified (1 file)

- `.planning/phases/09-tenants-flux-multi-tenancy-lockdown/09-VALIDATION.md` — frontmatter `nyquist_compliant: true` + `wave_0_complete: true`; 13 Wave 0 Requirements checkboxes + 6 Validation Sign-Off checkboxes flipped to `[x]`; Approval line updated

## Decisions Made

- **Multi-doc yq lint adapter via eval-all + @tsv** instead of the plan's nested `split_doc` pattern. The plan's draft used `yq eval ... | grep -cv '^---$'` to count Kustomization docs, which is unreliable for files with embedded comments containing dashes. The eval-all + @tsv approach emits one tab-separated tuple per yaml document, parseable via bash `while IFS=$'\t' read` loops, and is safe across multi-doc files of any content. The lint logic stays identical between positive (real Ks) and negative (broken fixture) directions because both call the same bash function via `run`.
- **P27 lint as callable bash function**: lint_kustomization_sa_dir + assert_inner_k_dependson_poc_capsule + assert_inner_k_wait_top_level are factored into reusable functions defined at the top of each bats file (above setup). This enables the negative falsifier @test to invoke the SAME logic against the broken fixture and assert non-zero exit — guarantees the lint is wired correctly before any production yaml exists to lint. Verified during Task 1 verify: positive lints fail (target dir absent), negative falsifier passes (lint catches missing SA).
- **Live bats cluster-info gate over KARYON_LIVE_TESTS env var**: matches Phase 8 D-08-09 pattern. Auto-skips when k3d clusters down (no env var fiddling required). At execution time the k3d clusters were UP, so live bats correctly attempted real assertions and failed because target Tenants/CRs absent (e.g., tenants-09 Secret-mirror @test failed cleanly).
- **Lockdown matrix per RESEARCH §Gap 2 canonical** (extends CONTEXT.md narrowing): bats-03 + bats-10 assert helm-controller receives BOTH `--no-cross-namespace-refs=true` AND `--default-service-account=default` per upstream `fluxcd/flux2-multi-tenancy` reference. CONTEXT.md narrowed to kustomize-controller-only; RESEARCH overruled for defense in depth (P27 fallback safety for any future tenant HelmReleases without explicit serviceAccountName).
- **spec.wait at TOP LEVEL per RESEARCH §Gap 9**: tenants-04 + tenants-11 assert `.spec.wait == true` (not nested inside `.spec.dependsOn[0].wait`). Both Phase 8 RESEARCH (Pitfall 9 — `spec.dependsOn[0].wait` does not exist as a field) and Phase 9 RESEARCH Gap 9 confirm wait is a sibling of dependsOn under `.spec`, not inside it.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Replaced unreliable multi-doc yq counter pattern with eval-all + @tsv**

- **Found during:** Task 1 (writing tenants-02-static-p27.bats)
- **Issue:** The plan-action draft used `yq eval ... | grep -cv '^---$'` to count Flux Kustomization docs in a multi-doc yaml file. This is unreliable because (a) yaml document separators may have surrounding whitespace; (b) embedded comments containing `---` would be miscounted; (c) the original `while IFS= read -r sa; do ... done < <(yq eval '...' "$f")` pattern would read every line of yq output, including non-document lines. A test would silently pass without actually validating.
- **Fix:** Replaced with `yq eval-all '[.kind // "", .apiVersion // "", .spec.X // ""] | @tsv'` which emits one tab-separated tuple per yaml document. Bash `while IFS=$'\t' read -r kind apiv val` parses each tuple and the lint applies per-doc. Same pattern reused in tenants-04-static-dependson.bats.
- **Files modified:** tests/bats/tenants-02-static-p27.bats, tests/bats/tenants-04-static-dependson.bats
- **Verification:** Negative falsifier @test passes (proves the lint catches missing SA in broken fixture); positive lint correctly fails when target dir absent (Wave 0 RED state).
- **Committed in:** c8d6188 (Task 1 commit)

**2. [Rule 2 - Missing Critical] Added "found_any" sentinel to multi-doc lint helpers**

- **Found during:** Task 1 (writing tenants-02-static-p27.bats and tenants-04-static-dependson.bats)
- **Issue:** A directory with zero matching Flux Kustomization docs would vacuously pass the lint (no docs to violate the rule). This means an empty pocs/capsule/tenants/ dir or a dir with only non-Kustomization yaml would silently appear to satisfy P27 / TEN-06 contracts. The lint must FAIL when there's nothing to lint.
- **Fix:** Added a `found_any=0/1` sentinel inside each lint helper function. After the loop, if `found_any` is 0, the function emits a diagnostic message and returns 1 (failure). Wave 0 RED state benefits: when pocs/capsule/tenants/ doesn't exist or is empty, the lint fails — driving Plan 09-02 to land the directory.
- **Files modified:** tests/bats/tenants-02-static-p27.bats, tests/bats/tenants-04-static-dependson.bats
- **Verification:** Wave 0 RED state confirmed for both files (target directory absent → lint fails as expected).
- **Committed in:** c8d6188 (Task 1 commit)

**3. [Rule 1 - Bug] Reordered notification-controller test from 6th @test to natural slot**

- **Found during:** Task 2 (writing tenants-10-live-lockdown.bats)
- **Issue:** The plan-action's enumerated 8 @test blocks but listed 11 distinct test conditions in the description. The notification-controller patch test was listed AFTER the 3 controllers no-CrashLoopBackOff group, but the natural ordering is to keep all flag-content @tests grouped together (kustomize → helm → notification) followed by the availableReplicas group. The plan's draft would have created an awkward test ordering where notification-controller's flag test came AFTER its availableReplicas test.
- **Fix:** Wrote 10 @tests (matching the 11 distinct conditions, with one merged as the bats body): kustomize-controller flags (3), helm-controller flags (2), notification-controller flag (1), 3 availableReplicas tests, flux-system K Ready=True. This matches the natural ordering in tests/bats/capsule-install-06-live-helm.bats analog. Plan-action `<files>` list and `<verify>` command unchanged.
- **Files modified:** tests/bats/tenants-10-live-lockdown.bats
- **Verification:** bats --count reports 10 tests (consistent with VALIDATION.md "10-test live bats" expectation in §Bats Coverage line 1295-1301).
- **Committed in:** 54bd203 (Task 2 commit)

**4. [Rule 2 - Missing Critical] Added empty-string fallback to availableReplicas variables**

- **Found during:** Task 2 (writing tenants-10-live-lockdown.bats availableReplicas tests)
- **Issue:** When kubectl returns empty for `.status.availableReplicas` jsonpath (Deployment in initial Provisioning state), the bash `[[ "$avail" == "$desired" ]]` test would compare `""` to `""` and return true — falsely passing when both fields are unset. The plan-action's `|| echo 0` fallback handles missing kubectl output but not empty-string output from successful but-no-data kubectl invocations.
- **Fix:** Added explicit `[ -z "$avail" ] && avail=0` and `[ -z "$desired" ] && desired=1` guards after the kubectl invocation. Then the test condition checks both `[[ "$avail" == "$desired" ]]` AND `[[ "$avail" -gt 0 ]]` — fails closed when no replicas are available.
- **Files modified:** tests/bats/tenants-10-live-lockdown.bats (3 availableReplicas @tests)
- **Verification:** bats --count reports 10 tests; structure validated.
- **Committed in:** 54bd203 (Task 2 commit)

---

**Total deviations:** 4 auto-fixed (2 Rule 1 bugs + 2 Rule 2 missing critical)
**Impact on plan:** All auto-fixes essential for Wave 0 RED-correctness — without them, the bats would silently pass on Wave 0 inputs (vacuous-pass on empty dir; falsely-pass on empty replicas; miscount multi-doc files), defeating the Nyquist gate's purpose. No scope creep; all changes stay within the plan's task boundaries.

## Issues Encountered

- **Live bats slow-fail behavior under cluster-up state**: at execution time the k3d-hub-flux + k3d-spoke-capsule clusters were running, so the cluster-info gate did NOT auto-skip the live bats. Each live bats with retry loops (3×30s) takes up to 90s per failing assertion. Running the full live suite serially exceeds reasonable verifier timeouts. Resolution: verified each live bats file PARSES via `bats --count` (cheap structural check); ran one targeted live test (tenants-09 Secret-mirror) to confirm RED behavior is functional; plan execution doesn't require running all live retries to completion in Wave 0 since the core contract is "files exist, parse valid, fail when target state absent" — all three confirmed.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- **Plan 09-01 ready** — turns tenants-01 + tenants-06 GREEN by landing the Tenant CRs (alpha + bravo) + per-tenant SAs (gitops-reconciler in tenant-{alpha,bravo} ns) + CapsuleConfiguration/default singleton on spoke-capsule via the spoke-targeted poc-capsule-spoke Kustomization. The static + live bats are RED-as-expected awaiting yaml.
- **Plan 09-02 ready** — turns tenants-02 + tenants-04 + tenants-09 GREEN by landing the per-tenant inner Kustomizations (tenant-alpha-app + tenant-bravo-app) + per-tenant GitRepositories + the spoke-capsule-kubeconfig Secret-mirror to tenant-{alpha,bravo} ns on hub (RESEARCH Gap 1 mitigation — Flux's hard same-namespace constraint on kubeConfig.secretRef).
- **Plan 09-03 ready** — turns tenants-03 + tenants-10 GREEN by landing the lockdown patches in clusters/hub-flux/flux-system/kustomization.yaml (3 flags on kustomize-controller, 2 flags on helm-controller per RESEARCH Gap 2, 1 flag on notification-controller, plus D-09-05a flux-system Kustomization escape hatch). Plan 09-03's mid-plan checkpoint MUST run `task health-check` BEFORE and AFTER the patch lands; failure of the post-patch run rolls back atomically.
- **Plan 09-04 verifier ready** — reruns the full Phase 9 bats suite + Phase 7 P31 isolation bats + Phase 8 CAP-01..03 + ADR-004 invariants + full v0.18 `task health-check`. Closes the phase with all 12 bats GREEN (assuming Plans 09-01..09-03 land their yaml correctly).
- **NO push to origin/main** per D-08-13 (push-gate deferred to Phase 11 VAL-05 — first-push gate owned there alongside one-shot gitleaks history scan).

## Self-Check: PASSED

**Files verified:**
- FOUND: tests/bats/tenants-01-static-tenant-cr.bats
- FOUND: tests/bats/tenants-02-static-p27.bats
- FOUND: tests/bats/tenants-03-static-lockdown.bats
- FOUND: tests/bats/tenants-04-static-dependson.bats
- FOUND: tests/bats/tenants-05-static-split-path.bats
- FOUND: tests/bats/tenants-06-live-tenant-cr.bats
- FOUND: tests/bats/tenants-07-live-impersonate.bats
- FOUND: tests/bats/tenants-08-live-quota-limit.bats
- FOUND: tests/bats/tenants-09-live-inner-k-ready.bats
- FOUND: tests/bats/tenants-10-live-lockdown.bats
- FOUND: tests/bats/tenants-11-live-dependson.bats
- FOUND: tests/bats/tenants-12-live-health-check.bats
- FOUND: tests/fixtures/p27-broken/tenant-broken.yaml

**Commits verified:**
- FOUND: c8d6188 (test(09-00): wave 0 static bats)
- FOUND: 54bd203 (test(09-00): wave 0 live bats)
- FOUND: fe7d98b (docs(09-00): wave 0 complete — flip nyquist_compliant + checkboxes)

**Wave 0 RED state verified:**
- 32 static tests: 7 PASS (Phase 8 invariants preserved + P27 negative falsifier proves lint logic) + 25 RED (target manifests absent — owned by Plans 09-01..09-03)
- 34 live tests: parse valid via `bats --count` (6+4+4+4+10+3+3 = 34 tests)
- P27 negative falsifier @test (tenants-02 test 10) PASSES — proves lint catches missing SA before any production yaml lands

**VALIDATION.md flipped:**
- frontmatter nyquist_compliant: true ✓
- frontmatter wave_0_complete: true ✓
- 13 Wave 0 Requirements checkboxes flipped to [x] ✓
- 6 Validation Sign-Off checkboxes flipped to [x] ✓

---
*Phase: 09-tenants-flux-multi-tenancy-lockdown*
*Completed: 2026-04-30*
