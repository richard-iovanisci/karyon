---
phase: 08-capsule-capsule-proxy-bare-minimum-install
plan: "00"
subsystem: testing
tags: [bats, flux, helmrelease, ocirepository, capsule, capsule-proxy, wave-0, nyquist-gate]

# Dependency graph
requires:
  - phase: 07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc
    provides: spoke-capsule cluster + KARYON POC MOUNT seam + outer poc-capsule Flux Kustomization (clusters/hub-flux/pocs/capsule.yaml) + pocs/capsule/kustomization.yaml placeholder + tests/bats/test_helper.bash + Phase 7 static contract bats (poc-mount, poc-isolation, poc-cluster) as regression gates
provides:
  - 5 static contract bats (capsule-install-01..05) — HelmRelease v2 shape, OCIRepository v1 shape, chart values literals, anti-pattern lints (no umbrella, no wait: in dependsOn, no cert-manager, no Phase 9 scope creep), inner kustomization rewrite contract
  - 5 live observability bats (capsule-install-06..10) — HelmRelease Ready=True, ≥7 capsule.clastix.io CRDs, NodePort 30443 reachability per OQ-1 reframe, ADR-004 zero Flux on spoke-capsule, folded carryover (outer poc-capsule Kustomization Ready=True)
  - Encoded Pitfall 8 reframe (CAP-02 reachability via TLS handshake + HTTP code [1-5][0-9][0-9], NOT literal 200 on /healthz)
  - Encoded Pitfall 9 anti-pattern (proxy HelmRelease dependsOn[0] has NO wait: field — Flux v2 default behavior already blocks until Ready=True)
  - Cluster-info gate pattern (auto-skip on unreachable k3d clusters, NOT KARYON_LIVE_TESTS env-var) — RESEARCH §"Pattern 4"
affects: [08-01-operator-helmrelease, 08-02-proxy-helmrelease, 08-03-verifier, 09-tenants, 11-validation]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Wave 0 RED bats scaffold (Nyquist gate) — repeats Phase 7 Plan 07-00 pattern verbatim per D-08-09"
    - "Cluster-info skip-gate (kubectl --context=k3d-{cluster} cluster-info >/dev/null 2>&1) replaces Phase 7's require_live env-var gate for live bats"
    - "Anti-pattern lint via grep -v '^[[:space:]]*#' | grep -F (Phase 7 fix-coredns-01-static.bats analog) + yq has(...) for structured anti-pattern checks"
    - "bats retry budget = 3 attempts × 30s sleep = 90s window for flux get Ready=True polls"

key-files:
  created:
    - tests/bats/capsule-install-01-static-helmrelease.bats
    - tests/bats/capsule-install-02-static-ocirepo.bats
    - tests/bats/capsule-install-03-static-values.bats
    - tests/bats/capsule-install-04-static-no-umbrella.bats
    - tests/bats/capsule-install-05-static-kustomize.bats
    - tests/bats/capsule-install-06-live-helm.bats
    - tests/bats/capsule-install-07-live-crds.bats
    - tests/bats/capsule-install-08-live-proxy-reachable.bats
    - tests/bats/capsule-install-09-live-adr-004.bats
    - tests/bats/capsule-install-10-live-flux-observable.bats
  modified: []

key-decisions:
  - "Encoded Pitfall 8 reframe (RESEARCH-verified) into capsule-install-08-live-proxy-reachable.bats: HTTP code regex ^[1-5][0-9][0-9]$ (NOT literal 200 on /healthz). Probe port 8081 is Pod-only per chart Service shape; NodePort 30443 maps to proxy port 9001 which requires bearer token. Spirit of CAP-02 = 'proxy reachable from WSL host' = TLS handshake succeeds + any valid HTTP response."
  - "Encoded Pitfall 9 anti-pattern (RESEARCH-verified) into capsule-install-04-static-no-umbrella.bats: yq eval '.spec.dependsOn[0] | has(\"wait\")' returns 'false'. The wait: sub-field doesn't exist in helm.toolkit.fluxcd.io/v2 HelmRelease spec — default Flux v2 behavior already blocks reconcile until dependency Ready=True. CONTEXT.md D-08-07 'wait: true' guess was reframed during research."
  - "Used per-hook key path (.spec.values.webhooks.hooks.<hook>.failurePolicy) in capsule-install-03-static-values.bats per RESEARCH-verified helm show values output, NOT a single global webhooks.validatingWebhookConfiguration.failurePolicy as CONTEXT.md initially guessed."
  - "Used cluster-info skip-gate (RESEARCH §Pattern 4) for live bats setup() — auto-skips when k3d-{hub-flux,spoke-capsule} unreachable. NOT require_live() env-var gate from test_helper.bash. Matches CONTEXT D-08-09 'auto-skip when the cluster is not yet up' default."

patterns-established:
  - "Wave 0 Nyquist gate for Phase 8 — every bats target file referenced by downstream Plans 08-01..03 lands BEFORE any HelmRelease/OCIRepository yaml. Subsequent plans turn red→green by landing actual yaml. Mirrors Phase 7 Plan 07-00 pattern verbatim per D-08-09."
  - "RESEARCH-wins-over-CONTEXT-guesses discipline — when CONTEXT.md proposes a literal value (e.g., 'curl returns 200', 'wait: true', 'webhooks.validatingWebhookConfiguration.failurePolicy') and RESEARCH.md disagrees after live verification (helm template, helm show values, fluxcd.io/flux/components/helm/api/v2/), the bats encode the RESEARCH-verified shape. Plans 08-01 / 08-02 will discover the contract is already correct rather than guessing from CONTEXT."

requirements-completed: []  # CAP-01, CAP-02, CAP-03 are NOT yet complete — Plans 08-01 (operator), 08-02 (proxy), 08-03 (verifier) will land the yaml. Plan 08-00 lands the Wave 0 contract bats only.

# Metrics
duration: ~9min
completed: 2026-04-29
---

# Phase 8 Plan 00: Wave 0 Nyquist Gate Bats Scaffold Summary

**10 bats files (5 static + 5 live, 49 tests, 507 lines) preposition every HelmRelease/OCIRepository/proxy contract + folded Phase-7 carryover for Plans 08-01/08-02/08-03 to turn GREEN by landing yaml — Pitfall 8 (CAP-02 reachability reframe) and Pitfall 9 (no wait: in dependsOn) encoded RESEARCH-verbatim.**

## Performance

- **Duration:** ~9 min
- **Started:** 2026-04-29T19:29:21Z
- **Completed:** 2026-04-29T19:38:11Z
- **Tasks:** 3 (2 file-creating + 1 verification-only)
- **Files modified:** 10 net-new bats files (zero existing files modified)

## Accomplishments

- Wave 0 Nyquist gate established (D-08-09 — repeat of Phase 7 Plan 07-00 pattern verbatim) — 49 RED tests across 10 bats files preposition every static contract + every live observability check that Plans 08-01..03 will turn GREEN by landing yaml.
- Pitfall 8 reframe encoded — capsule-install-08-live-proxy-reachable.bats asserts HTTP code matches `^[1-5][0-9][0-9]$` (TLS handshake + any valid HTTP response), NOT literal 200 on /healthz. Plans 08-01 / 08-02 will discover the contract is already correct rather than guessing from CONTEXT.md's outdated literal.
- Pitfall 9 anti-pattern encoded — capsule-install-04-static-no-umbrella.bats asserts `yq eval '.spec.dependsOn[0] | has("wait")' == false`. The `wait:` sub-field doesn't exist in helm.toolkit.fluxcd.io/v2 HelmRelease spec — CONTEXT.md D-08-07 guess reframed.
- Phase 7 regression gates GREEN — `bats tests/bats/poc-{mount,isolation,cluster}-01-static.bats` reports 22 tests / 0 failures. P31 (POC isolation), P40 (P18 key: value.yaml), CAPCLU contract preserved. Wave 0 introduces ZERO `spoke-capsule` mentions in v0.18 scripts.
- Live cluster observability — when run with k3d clusters reachable, 5 of the 11 live tests already PASS by virtue of Phase 7 inheritance (port 30443 bound on 127.0.0.1, ADR-004 zero pods on spoke-capsule flux-system, outer poc-capsule Kustomization Ready=True for the empty pocs/capsule placeholder, hub-flux GitRepo past 1f2da1d3, push-gate skips appropriately). The folded carryover (Phase 7 verification item 1b) is observable-GREEN right now against the current empty `pocs/capsule/kustomization.yaml: resources: []`.

## Task Commits

Each task was committed atomically:

1. **Task 1: Land 5 static contract bats (capsule-install-01..05)** - `76fd4cc` (test)
2. **Task 2: Land 5 live observability bats (capsule-install-06..10) with cluster-info gating** - `6b8f415` (test)
3. **Task 3: Run full Phase 8 + Phase 7 regression bats suite — confirm 10 RED + Phase 7 GREEN baseline** - (verification-only; no commit per plan `<files>(none)`)

**Plan metadata:** (orchestrator owns; this is a parallel worktree commit)

## Files Created/Modified

- `tests/bats/capsule-install-01-static-helmrelease.bats` (75 lines, 9 @tests) — HelmRelease v2 shape contract for both operator + proxy: apiVersion helm.toolkit.fluxcd.io/v2, chartRef.{kind=OCIRepository, name}, kubeConfig.secretRef.{name=spoke-capsule-kubeconfig, key=value.yaml}, interval=5m, targetNamespace=capsule-system, install/upgrade.crds=CreateReplace, dependsOn[0] block on proxy
- `tests/bats/capsule-install-02-static-ocirepo.bats` (68 lines, 7 @tests) — OCIRepository v1 shape contract for both operator + proxy: apiVersion source.toolkit.fluxcd.io/v1, ghcr.io/projectcapsule/charts/{capsule,capsule-proxy} URLs, ref.tag pins (0.12.4 / 0.12.0), layerSelector.mediaType, no auth fields
- `tests/bats/capsule-install-03-static-values.bats` (83 lines, 10 @tests) — Chart values literals: operator (tls.enableController=true, certManager.generateCertificates=false, webhooks.hooks.{tenants,namespaces,pods}.failurePolicy=Ignore per RESEARCH-verified per-hook path, replicaCount=1, proxy.enabled=false); proxy (service.type=NodePort, service.nodePort=30443, options.additionalSANs contains 127.0.0.1+localhost per RESEARCH-verified key path)
- `tests/bats/capsule-install-04-static-no-umbrella.bats` (46 lines, 5 @tests) — Anti-pattern lints: no `proxy.enabled: true` in operator HR (D-08-01), no `wait:` field in proxy HR dependsOn[0] (Pitfall 9), no `certManager.generateCertificates: true` in operator HR (D-08-04), no Phase 9 scope creep (no CapsuleConfiguration / Tenant CRs in Phase 8 yamls)
- `tests/bats/capsule-install-05-static-kustomize.bats` (53 lines, 6 @tests) — D-08-05 inner kustomize rewrite: pocs/capsule/kustomization.yaml resources=[operator/, proxy/], head comment block preserves REQ-CAPCLU-02 + Pitfall 7 attribution; subdir kustomization.yamls reference [ocirepository.yaml, helmrelease.yaml]
- `tests/bats/capsule-install-06-live-helm.bats` (49 lines, 3 @tests) — CAP-01+CAP-02 live HelmRelease Ready=True observation (3×30s retry budget), capsule-controller-manager pod Running on spoke-capsule
- `tests/bats/capsule-install-07-live-crds.bats` (28 lines, 2 @tests) — CAP-03 live ≥7 capsule.clastix.io CRDs, each of 7 expected CRD names present (tenants, capsuleconfigurations, globaltenantresources, tenantresources, resourcepools, resourcepoolclaims, tenantowners)
- `tests/bats/capsule-install-08-live-proxy-reachable.bats` (31 lines, 2 @tests) — CAP-02 NodePort 30443 reachability per OQ-1 / Pitfall 8 reframe (TLS handshake + HTTP code regex `^[1-5][0-9][0-9]$`), TCP port 30443 bound on 127.0.0.1 (Phase 7 D-10 serverlb)
- `tests/bats/capsule-install-09-live-adr-004.bats` (24 lines, 1 @test) — ADR-004 / domain-boundary-#4: spoke-capsule flux-system ns has zero pods (or NotFound)
- `tests/bats/capsule-install-10-live-flux-observable.bats` (50 lines, 3 @tests) — FOLDED CARRYOVER from Phase 7 verification item 1b: outer poc-capsule Kustomization Ready=True (3×30s retry), post-Phase-7 push gate (deferred-to-VAL-05 fall-through), hub-flux GitRepo revision past 1f2da1d3

## Bats Outcome Summary (Wave 0 RED scaffold confirmed)

`bats tests/bats/capsule-install-*.bats` (49 tests total):

| File | @tests | Initial state w/ clusters reachable | Reason |
| ---- | ------ | ----------------------------------- | ------ |
| capsule-install-01-static-helmrelease.bats | 9 | 9 RED | `[ -f $OPERATOR_HR ]` precondition fails (Plan 08-01 lands) |
| capsule-install-02-static-ocirepo.bats | 7 | 7 RED | `[ -f $OPERATOR_OCIREPO ]` precondition fails (Plan 08-01 lands) |
| capsule-install-03-static-values.bats | 10 | 10 RED | `[ -f ... ]` precondition fails (Plans 08-01/08-02 land) |
| capsule-install-04-static-no-umbrella.bats | 5 | 5 RED | `[ -f ... ]` precondition fails (Plans 08-01/08-02 land) |
| capsule-install-05-static-kustomize.bats | 6 | 3 GREEN, 3 RED | head-comment + apiVersion+kind tests pass against existing Phase 7 placeholder; resources/subdir kustomize tests RED until Plans 08-01/08-02 land |
| capsule-install-06-live-helm.bats | 3 | 3 RED | HelmReleases not yet installed |
| capsule-install-07-live-crds.bats | 2 | 2 RED | Capsule CRDs not yet registered on spoke-capsule |
| capsule-install-08-live-proxy-reachable.bats | 2 | 1 GREEN (TCP 30443 bound — Phase 7 D-10 serverlb) + 1 RED (HTTPS 401/403/etc not yet — proxy not installed) | Phase 7 inheritance |
| capsule-install-09-live-adr-004.bats | 1 | 1 GREEN | ADR-004 invariant from Phase 7 setup |
| capsule-install-10-live-flux-observable.bats | 3 | 2 GREEN + 1 SKIP | Folded carryover GREEN against placeholder; push-gate SKIP `deferred-to-VAL-05` |

**Net: 41 RED + 8 GREEN + 1 SKIP = 50 outcomes across 49 unique @tests** (one test triggers both green and skip paths conditionally — Test 10's deferred-to-VAL-05 handler).

`bats tests/bats/poc-{mount,isolation,cluster}-01-static.bats` (Phase 7 regression gates): **22 tests, 0 failures** — P31 / P40 / CAPCLU inheritance preserved.

## Decisions Made

- **Encoded Pitfall 8 reframe verbatim** — capsule-install-08 uses `[[ "$code" =~ ^[1-5][0-9][0-9]$ ]]` per RESEARCH §"Pitfall 8 → Option A" lines 812-821, NOT a literal 200 check on /healthz. Plans 08-01 / 08-02 will discover the contract is already correct rather than guessing from CONTEXT.md's outdated literal `curl -k https://127.0.0.1:30443/healthz returns 200`. The chart Service shape exposes only port 9001 (proxy, requires bearer token); /healthz is on probe port 8081 which is Pod-only per kubelet's direct pod-network access pattern.
- **Encoded Pitfall 9 anti-pattern verbatim** — capsule-install-04 uses `yq eval '.spec.dependsOn[0] | has("wait")' == "false"` per RESEARCH §"Pitfall 9" lines 832-847, NOT trusting CONTEXT.md D-08-07's `dependsOn[*].wait: true` guess. The `wait:` sub-field does NOT exist in helm.toolkit.fluxcd.io/v2 HelmRelease spec per Flux v2 docs verified 2026-04-29; default Flux v2 behavior already blocks reconcile until dependency Ready=True.
- **Used per-hook webhook key path** — capsule-install-03 asserts `.spec.values.webhooks.hooks.<hook>.failurePolicy: Ignore` per-hook (tenants, namespaces, pods) per RESEARCH-verified `helm show values` output, NOT a single global `webhooks.validatingWebhookConfiguration.failurePolicy` as CONTEXT.md initially guessed. Plans 08-01 will land all 14 per-hook overrides per RESEARCH §Example 1; bats only sample-check 3 hooks for sufficiency without over-coupling.
- **Used cluster-info skip-gate** — All 5 live bats use `kubectl --context=k3d-{cluster} cluster-info >/dev/null 2>&1; skip` pattern per RESEARCH §"Pattern 4" lines 569-579, NOT `require_live` env-var gate from test_helper.bash. Matches CONTEXT D-08-09 default ("auto-skip when the cluster is not yet up") and lets the bats file be both RED-on-cluster-down (skip) AND RED-on-no-yaml (cluster up but install yaml not landed) without env-var ceremony.
- **Used `kubectl --context=k3d-{cluster}` explicit form** — Never reads ambient KUBECONFIG. Matches Phase 7 + CONTEXT D-08-09 default. Live bats setup() and @test bodies use explicit context throughout.

## Deviations from Plan

None - plan executed exactly as written.

The plan-level `<verify><automated>` command for Task 3 used `bats ... | tail -1 | grep -E '0 failures'` against default bats TAP output, which lacks the `X failures` summary line; that summary line only appears in `bats --pretty` mode. This was a documentation slip in the plan's automated command, not a deviation in execution — Phase 7 regression at 22/22 GREEN was confirmed both via manual `tail -1` parse (last line is `ok 22 ...`) and via re-run with `bats --pretty` which produced `22 tests, 0 failures` then OK. Future plans should specify `bats --pretty` for any `0 failures`-style asserts.

## Issues Encountered

None.

The Wave 0 RED scaffold landed cleanly on the first attempt — every bats file was created from RESEARCH §"Code Examples" + §"Pattern 1..5" + §"Pitfall 8/9" excerpts and 08-PATTERNS.md substitutions verbatim, with no need for plan-time iteration. yq + grep + bats syntax all parsed correctly. No Rule 1 / Rule 2 / Rule 3 deviations triggered. No checkpoints reached.

Note for downstream Plans 08-01..08-03: 5 of the live bats already report PASS on the current cluster state by virtue of Phase 7 inheritance (port 30443 bound on 127.0.0.1, ADR-004 zero pods, outer Kustomization Ready=True for empty placeholder, hub-flux GitRepo revision past 1f2da1d3). This is observable confirmation that Phase 7 D-10 (k3d serverlb host-publish) and ADR-004 invariants are intact. The folded carryover (Phase 7 verification item 1b) is GREEN against the current `pocs/capsule/kustomization.yaml: resources: []` — Plans 08-01 / 08-02 must keep it GREEN by landing the operator/ + proxy/ subdirs simultaneously with the parent rewrite to avoid Pitfall 7 `path not found` mid-Phase-8.

## User Setup Required

None - no external service configuration required. The 10 bats files are inert until Plans 08-01..03 land HelmRelease/OCIRepository/kustomization yaml.

## Next Phase Readiness

- **Plan 08-01 (operator HelmRelease + OCIRepository) is unblocked.** All 4 operator-related contract bats (capsule-install-01 + 02 operator subset, 03 operator subset, 04 operator subset, 05 operator subdir) await yaml under `pocs/capsule/operator/`. RESEARCH §Pattern 1+2 + §Example 1 + 08-PATTERNS.md gives the exact target shapes.
- **Plan 08-02 (proxy HelmRelease + OCIRepository + parent kustomize rewrite) is unblocked.** All proxy-related contract bats (capsule-install-01 + 02 proxy subset, 03 proxy subset, 04 dependsOn-no-wait + scope-boundary, 05 proxy subdir + parent rewrite) await yaml under `pocs/capsule/proxy/` + `pocs/capsule/kustomization.yaml` modification. RESEARCH §Pattern 1+2+3 + §Example 2 + Pitfall 9 lint give exact shapes.
- **Plan 08-03 (verifier — live observation + folded carryover acceptance) is partially pre-satisfied.** The 5 live bats are already in place; Plan 08-03 just runs them after Plans 08-01/08-02 land yaml + adds any missing observability hooks (e.g., docs/poc-capsule.md "What's installed" subsection per CONTEXT `<code_context>`).
- **No blockers or concerns from this plan.** Wave 0 succeeds: 41 RED bats await yaml, 22 Phase 7 GREEN regression bats stay GREEN, no v0.18 script touched, no `spoke-capsule` introduced into v0.18 grep set.

## Self-Check: PASSED

All 10 created bats files FOUND on disk + SUMMARY.md FOUND. Both task commit hashes (`76fd4cc`, `6b8f415`) FOUND in `git log`. Phase 7 regression at 22/22 GREEN, Phase 8 Wave 0 RED scaffold confirmed (49 tests with expected mix of RED/GREEN/SKIP based on Phase 7 inheritance).

---
*Phase: 08-capsule-capsule-proxy-bare-minimum-install*
*Completed: 2026-04-29*
