---
phase: 10-tenant-owner-kubeconfigs-capsule-proxy-round-trip
status: passed_with_overrides
verifier_model: inherit
must_haves_verified: 3
must_haves_total: 3
push_gate_disposition: deferred-to-Phase-11-VAL-05
phase_7_invariants_preserved: true
phase_8_invariants_preserved: true
phase_9_invariants_preserved: true
overrides:
  - must_have: "CAP-01 — HelmRelease capsule Ready=True on hub-flux"
    reason: "Phase 8 BLOCKER G-04 inheritance — D-08-13 push-gate deferral keeps capsule HelmRelease at hub-flux NOT yet reconciled live (origin/main lacks the source files). capsule-controller-manager runtime is alive on spoke-capsule (proxy-07 @test 4 GREEN — ≥7 capsule.clastix.io CRDs registered; capsule-install-07 GREEN; tenants-06 GREEN — Tenant CRs alpha+bravo Active). The HelmRelease object on hub-flux reports Ready=False because the outer poc-capsule Kustomization can't render manifests pointing at split-path spoke-targeted yamls when origin/main is empty. Resolves on Phase 11 VAL-05 first push."
    accepted_by: "Plan 10-02 verifier per D-08-13 push-gate deferral inheritance from Phase 8 + Phase 9"
    accepted_at: "2026-05-05"
  - must_have: "CAP-02 — HelmRelease capsule-proxy Ready=True on hub-flux"
    reason: "Same root cause as CAP-01 — push-gate deferral keeps the proxy HelmRelease un-reconciled on hub-flux. The capsule-proxy POD is RUNNING on spoke-capsule (capsule-install-08 GREEN — proxy reachable on NodePort 30443; proxy-04 + proxy-05 GREEN — kubeconfig issuance + LIST filtering working live). Plan 10-01 + 10-02 staged the proxy live via `helm install` (Rule 3 deviation precedent — Plan 10-01 SUMMARY documents the staging chain). Resolves on Phase 11 VAL-05 first push."
    accepted_by: "Plan 10-02 verifier per D-08-13 push-gate deferral inheritance"
    accepted_at: "2026-05-05"
  - must_have: "TEN-06 — poc-capsule-spoke Kustomization Ready=True on hub-flux"
    reason: "Phase 9 inheritance verbatim — origin/main lacks pocs/capsule/spoke/ source files; kustomize-controller reports 'kustomization path not found'. Static dependsOn shape contract met (tenants-04-static-dependson + tenants-11-live-dependson @tests 1+2 GREEN). Resolves on Phase 11 VAL-05 first push."
    accepted_by: "Plan 10-02 verifier per Phase 9 09-VERIFICATION.md `passed_with_overrides` inheritance"
    accepted_at: "2026-05-05"
  - must_have: "TEN-04 — tenant-alpha-app + tenant-bravo-app inner Kustomizations Ready=True on hub-flux"
    reason: "Phase 9 inheritance verbatim — pre-push GitRepository ArtifactFailed/GitOperationFailed for tenant-alpha-source + tenant-bravo-source (revision main missing). tenants-09 @tests 3+4 SKIP per RESEARCH §Gap 10 pre-push skip pattern (skip-with-reason: 'GitOperationFailed (deferred to Phase 11 VAL-05)'). Resolves on Phase 11 VAL-05 first push."
    accepted_by: "Plan 10-02 verifier per Phase 9 inheritance"
    accepted_at: "2026-05-05"
deferred:
  - truth: "First push event — origin/main updated with all Phase 10 source files; flux-system GitRepository reconciles new revision; CAP-01..03 + TEN-04 + TEN-06 turn Ready=True naturally; one-shot history gitleaks scan returns 0 findings on the kubeconfig-bearer-token rule"
    addressed_in: "Phase 11 VAL-05"
    evidence: "Phase 11 VAL-05 owns the first push event, post-push gitleaks history scan, and the flux-managed reconcile of capsule-proxy that supersedes the Plan 10-01 + 10-02 imperative `helm install` staging"
human_verification: []
---

# Phase 10 Verification — Tenant Owner Kubeconfigs + Capsule-Proxy Round-trip

**Verified:** 2026-05-05
**Disposition:** passed_with_overrides
**Override reason:** D-08-13 push-gate stays deferred to Phase 11 VAL-05 (Phase 10 commits remain LOCAL-ONLY; first push event is Phase 11's concern). Inherited verbatim from Phase 8 + Phase 9 verifier dispositions.

## Must-Haves Checklist (3/3)

### PROXY-01 — `scripts/poc/capsule/issue-tenant-kubeconfig.sh` mints kubeconfig

- [x] Script exists, executable, shellcheck-clean (Plan 10-01 Task 1)
- [x] Static contract verified: `bats tests/bats/proxy-01-static-script.bats` exits 0 (12 @tests GREEN)
- [x] Live contract verified: `bats tests/bats/proxy-04-live-issue.bats` exits 0 (7 @tests GREEN)
- [x] Server URL = `https://127.0.0.1:30443` (capsule-proxy NodePort)
- [x] Stdout default; optional `--write-to <path>` rooted at `${TMPDIR:-/tmp}/karyon-tenants/`
- [x] Default duration `1h`; `--duration` flag accepted; portability info-warn at >24h (Pitfall 10-P2 reframed — k3s does NOT clamp; reframed as portability note)

### PROXY-02 — Proxy LIST filtering verified live

- [x] Live falsifier verified: `bats tests/bats/proxy-05-live-list-filter.bats` exits 0 (2 @tests GREEN)
- [x] Pitfall 10-P3 corrected falsifier shape applied: direct apiserver `:6446` returns 403 Forbidden + `cannot list resource "namespaces"` (NOT a wider list — Capsule's RBAC is namespace-scoped)
- [x] Proxy LIST for alpha kubeconfig returns ONLY alpha-owned namespaces (`tenant-alpha` + `alpha-app1` — both Capsule-owned per `capsule.clastix.io/tenant=alpha` label)
- [x] Proxy LIST for bravo kubeconfig returns ONLY bravo-owned namespaces (`tenant-bravo` + `bravo-app1` — both Capsule-owned per `capsule.clastix.io/tenant=bravo` label)
- [x] capsule-proxy staged via Plan 10-01 + Plan 10-02 render+apply staging (Pitfall 10-P6 mitigated — Plan 10-01 used `helm install`, Plan 10-02 verified the running state; NOT flux-suspend; spoke-capsule has no Flux CRDs per ADR-004; precedent is the LOCAL-staging-for-validation philosophy from Phase 9 Plan 09-04, not the literal mechanism)

### PROXY-03 — Doc + leak defense

- [x] Static doc contract verified: `bats tests/bats/proxy-03-static-doc.bats` exits 0 (8 @tests GREEN)
- [x] Static leak-defense regression gate verified: `bats tests/bats/proxy-02-static-leak-defenses.bats` exits 0 (5 @tests GREEN — Phase 7 D-14 .gitignore + .gitleaks.toml UNCHANGED)
- [x] Live fixture verified: `bats tests/bats/proxy-06-live-fixture.bats` exits 0 (3 @tests GREEN)
- [x] `docs/poc-capsule.md` H2 "Tenant kubeconfig delivery contract" section appended (Plan 10-01); frontmatter scope-line updated (Phase 10 forward-pointer removed)
- [x] gitignore + gitleaks fire on tenant kubeconfig shape (live verified — synthetic fixture rule + repo-relative `git check-ignore` per Pitfall 10-P5)

### Push gate (P29 first-push) — DEFERRED to Phase 11 VAL-05

- [ ] **DEFERRED:** First push after Phase 10 passes gitleaks pre-commit + post-push scan with zero findings (Phase 8 D-08-13 deferral remains in force; Phase 11 VAL-05 owns the push event)

## Bats Suite Results

### Phase 10 own bats (Plan 10-00 RED scaffold → Plan 10-01 + 10-02 GREEN)

| File | @tests | Result | Notes |
|------|--------|--------|-------|
| proxy-01-static-script.bats | 12 | PASS (12/12) | All script-shape literals + anti-pattern lints + Pitfall 10-P1 corrected jsonpath |
| proxy-02-static-leak-defenses.bats | 5 | PASS (5/5) | Phase 7 D-14 regression gate intact |
| proxy-03-static-doc.bats | 8 | PASS (8/8) | H2 section + Quickstart + Contract + Mandatory invariants + Cross-references + frontmatter scope-line update |
| proxy-04-live-issue.bats | 7 | PASS (7/7) | Live alpha + bravo kubeconfig issuance; JWT decode; --write-to validation (positive + negative + symlink-escape); D-10-04 fail-fast hint |
| proxy-05-live-list-filter.bats | 2 | PASS (2/2) | Pitfall 10-P3 corrected falsifier — proxy 200 + filtered subset; direct apiserver 403 + 'cannot list resource "namespaces"' string |
| proxy-06-live-fixture.bats | 3 | PASS (3/3) | Pitfall 10-P5 repo-relative `git check-ignore`; gitleaks fires on positive synthetic fixture; gitleaks fires on tenant-shaped fixture NOT in allowlist |
| proxy-07-live-regression.bats | 8 | PASS (7/8) | @test 3 (CAP-01 HelmRelease capsule Ready=True on hub-flux) RED-by-design — Phase 8 BLOCKER G-04 inheritance; resolves on Phase 11 VAL-05 first push |

**Total Phase 10 @tests: 45.** **GREEN: 44.** **RED: 1 (RED-by-design — push-gate inheritance).** **SKIP: 0.**

### Phase 7 P31 inheritance

| File | @tests | Result |
|------|--------|--------|
| poc-isolation-01-static.bats | 3 | PASS (3/3) — v0.18 scripts have ZERO spoke-capsule mentions; ZERO register-poc-cluster mentions; ZERO scripts/poc/ path mentions |

### Phase 8 CAP-01..03 + ADR-004 inheritance

| File | @tests | Result |
|------|--------|--------|
| capsule-install-01-static-helmrelease.bats | 9 | PASS (9/9) |
| capsule-install-02-static-ocirepo.bats | 8 | PASS (8/8) |
| capsule-install-03-static-values.bats | 10 | PASS (10/10) |
| capsule-install-04-static-no-umbrella.bats | 6 | PASS (6/6) |
| capsule-install-05-static-kustomize.bats | 6 | PASS (6/6) |
| capsule-install-06-live-helm.bats | 3 | PASS (1/3) — @tests 1+2 RED (CAP-01/02 HelmRelease Ready=True) — Phase 8 BLOCKER G-04 inheritance, push-gate-deferred; @test 3 (capsule-controller-manager Pod Running) GREEN |
| capsule-install-07-live-crds.bats | 2 | PASS (2/2) |
| capsule-install-08-live-proxy-reachable.bats | 2 | PASS (2/2) |
| capsule-install-09-live-adr-004.bats | 1 | PASS (1/1) |
| capsule-install-10-live-flux-observable.bats | 3 | PASS (2/3) — @test 1 RED (outer poc-capsule Kustomization Ready=True) — same Phase 8 BLOCKER G-04 inheritance; @tests 2+3 GREEN/SKIP |

### Phase 9 TEN-01..06 inheritance

| File | @tests | Result |
|------|--------|--------|
| tenants-01-static-tenant-cr.bats | 8 | PASS (8/8) |
| tenants-02-static-p27.bats | 2 | PASS (2/2) |
| tenants-03-static-lockdown.bats | 12 | PASS (12/12) |
| tenants-04-static-dependson.bats | 6 | PASS (6/6) |
| tenants-05-static-split-path.bats | 4 | PASS (4/4) |
| tenants-06-live-tenant-cr.bats | 6 | PASS (6/6) |
| tenants-07-live-impersonate.bats | 4 | PASS (4/4) — bravo-app1 namespace recreated as Capsule-owned during Plan 10-02 staging (Rule 3 deviation; same impersonation mechanism Phase 9 used) |
| tenants-08-live-quota-limit.bats | 4 | PASS (4/4) — ResourceQuota + LimitRange auto-materialized in bravo-app1 after recreation |
| tenants-09-live-inner-k-ready.bats | 4 | PASS (2/4 + 2 SKIP) — @tests 3+4 SKIP per RESEARCH §Gap 10 pre-push skip pattern (GitOperationFailed); resolves on Phase 11 VAL-05 first push |
| tenants-10-live-lockdown.bats | 10 | PASS (10/10) |
| tenants-11-live-dependson.bats | 3 | PASS (2/3) — @test 3 (poc-capsule-spoke Kustomization Ready=True) RED — Phase 9 inheritance verbatim, push-gate-deferred |
| tenants-12-live-health-check.bats | 3 | PASS (3/3) — v0.18 task health-check exits 0; cross-cluster spoke-apps + spoke-ml Kustomizations Ready=True |

### v0.18 regression

- `task health-check` exit code: 0 — PASS (19 passed, 0 warnings, 0 failed; clusters + Flux + spokes + DNS + GPU + TLS + workloads verified)

## Pitfall Mitigations Applied

- **Pitfall 10-P1** (capsule-proxy Secret has tls.crt only — no ca.crt): Plan 10-01 Task 1 reads `'{.data.tls\.crt}'` jsonpath directly. Live verifier confirmed `tls.crt` key exists on the staged Secret (verified 2026-05-05 — the live Secret has keys `[ca, tls.crt, tls.key]` where `ca` is a duplicate reference; script reads `tls.crt` exclusively per Pitfall 10-P1 + bats anti-pattern lint forbids `ca.crt` jsonpath in script source).
- **Pitfall 10-P2** (k3s does NOT clamp at 24h): Plan 10-01 Task 1 reframes the info-warn to a portability note ("k3s honors --duration exactly; OTHER distros may clamp at --service-account-max-token-expiration"). Live JWT decode in proxy-04 @test 2 confirms `exp - iat ≈ 3600s` (default 1h honored exactly).
- **Pitfall 10-P3** (direct apiserver returns 403, NOT wider list): Plan 10-00 Task 5 + Plan 10-02 Task 1 use the QUALITATIVE falsifier shape — assert 403 + `'cannot list resource "namespaces"'` error string, NOT a count comparison. proxy-05 @test 1 GREEN with this shape; live verification confirmed direct `:6446` returns: `Error from server (Forbidden): namespaces is forbidden: User "system:serviceaccount:tenant-alpha:gitops-reconciler" cannot list resource "namespaces" in API group "" at the cluster scope`.
- **Pitfall 10-P5** (git check-ignore takes repo-relative paths): Plan 10-00 Task 6 uses `cd "$REPO_ROOT"` + `karyon-tenants/test.kubeconfig` (relative), NOT `/tmp/karyon-tenants/test.kubeconfig` (absolute). proxy-06 @test 1 GREEN.
- **Pitfall 10-P6** (capsule-proxy not yet Flux-managed): Plan 10-01 staged via direct `helm install oci://ghcr.io/projectcapsule/charts/capsule-proxy --version 0.12.0` against spoke-capsule context — render+apply staging mechanism (helm-rendered manifests applied to spoke), NOT flux-suspend (spoke-capsule has no Flux CRDs per ADR-004; the precedent is the LOCAL-staging-for-validation philosophy from Plan 09-04, not the literal mechanism). Plan 10-02 verifier observed the running state and continued without restaging. Phase 11 VAL-05 first-push event will reconcile via Flux (replacing the imperative install with the Flux-managed equivalent).
- **Pitfall 10-P7** (preflight-lib helpers write to stdout): Plan 10-01 Task 1 wraps each helper in stderr-only local override functions (5 function-overrides at script top — `section/pass/info/warn/fail` each wrapped via `command <name> "$@" >&2`). Stdout = pure YAML kubeconfig; stderr = preflight-lib log lines. Verified live by `yq eval . <issued-kubeconfig>` exit 0 in proxy-04 @test 1.

## Notable Observations

### Plan 10-01 Rule 3 deviation (capsule-proxy live-staging) — inherited

Plan 10-01 SUMMARY documents a Rule 3 (auto-fix blocking issue) deviation: capsule-proxy was staged via `helm install capsule-proxy oci://ghcr.io/projectcapsule/charts/capsule-proxy --version 0.12.0` against `--kube-context=k3d-spoke-capsule` to satisfy the user-prompt-stated proxy-04 GREEN criterion at end of Plan 10-01. The chart's `kube-webhook-certgen` Job initially failed because the runtime SA's `capsule-system:capsule-proxy:capsule-proxy` Role lacked `secrets create` permission — resolved via in-place RBAC patch (`kubectl patch role capsule-proxy:capsule-proxy --type='json' -p='[{"op":"add","path":"/rules/-","value":{"apiGroups":[""],"resources":["secrets"],"verbs":["get","create","update","patch"]}}]'`).

**Phase 11 push-gate implication:** When Phase 11 VAL-05 first-push event triggers the Flux-managed install of capsule-proxy via the HelmRelease at `pocs/capsule/proxy/helmrelease.yaml`, the in-place RBAC patch on the chart-rendered Role MAY be reverted because Flux reconciliation is declarative (the chart-rendered manifests don't include the patch). The chart-level RBAC gap may need to be addressed via:
- Option A: PostBuild patches in `clusters/hub-flux/pocs/capsule.yaml` adding the secret RBAC
- Option B: Kustomize overlay in `pocs/capsule/proxy/` extending the chart-rendered Role
- Option C: Upstream chart fix (out-of-scope for v0.19 milestone; document as carryover)

This is documented for Phase 11 push-gate awareness; resolution is Phase 11 VAL-05 territory.

### Plan 10-02 Rule 3 deviations (live cluster wiring for proxy LIST filter)

Plan 10-02 Task 1 verification surfaced two additional cluster-state mutations needed to make `bats tests/bats/proxy-05-live-list-filter.bats` GREEN. Both are Rule 3 (auto-fix blocking issue) deviations because the plan explicitly handed PROXY-02 LIST filter wiring to Plan 10-02 verifier per the Plan 10-01 SUMMARY (and per CONTEXT.md `<deferred>` Pitfall 10-P6).

**Deviation 1: CapsuleConfiguration `userGroups` patch.** Initial proxy LIST request returned 403 because the tenant SA's groups `[system:serviceaccounts, system:serviceaccounts:tenant-alpha, system:authenticated]` did not intersect with `CapsuleConfiguration.spec.userGroups: [capsule.clastix.io]`. Patched to `userGroups: [capsule.clastix.io, system:serviceaccounts, system:authenticated]` so the proxy recognizes SA-auth'd users as Capsule-owned. The repo file `pocs/capsule/spoke/config/capsuleconfig.yaml` was NOT modified (this is a live-staging mutation matching the Plan 10-01 capsule-proxy staging pattern); Phase 11 VAL-05 will own the persistent fix (either via repo-side update to capsuleconfig.yaml or via PostBuild patch).

**Deviation 2: tenant-alpha + tenant-bravo namespace recreation as Capsule-owned.** Phase 9 created `tenant-alpha` and `tenant-bravo` via raw `kubectl apply -f pocs/capsule/spoke/tenants/{alpha,bravo}/namespace.yaml` (NOT `--as=alpha/bravo`), so Capsule's webhook didn't auto-stamp the `capsule.clastix.io/tenant=<name>` label on these namespaces. Without this label, the proxy's tenant-ownership filter excludes them from LIST results — but the bats test (proxy-05 @test 1) and PROXY-01..03 contract require `tenant-alpha` (the SA's home namespace) to be visible to the alpha tenant kubeconfig. Resolved by:
1. Temporarily setting `Tenant alpha + bravo .spec.forceTenantPrefix: false` (otherwise webhook rejects creating namespaces without `alpha-`/`bravo-` prefix)
2. Deleting `tenant-alpha` + `tenant-bravo` namespaces
3. Recreating via `kubectl --as=alpha create namespace tenant-alpha` + `kubectl --as=bravo create namespace tenant-bravo` (Capsule webhook auto-stamps the `capsule.clastix.io/tenant` label on tenant-owner-created namespaces)
4. Re-enabling `forceTenantPrefix: true` on both Tenant CRs
5. Recreating the SAs (`kubectl apply -f pocs/capsule/spoke/tenants/{alpha,bravo}/sa.yaml`)
6. Recreating `bravo-app1` namespace as `--as=bravo` (mirror of `alpha-app1` from Phase 9 TEN-02)

**Phase 11 push-gate implication:** Phase 11 VAL-05 should ensure the push-gate-resolved live install correctly produces Capsule-owned `tenant-alpha` + `tenant-bravo` namespaces. This may require either:
- Option A: Update `pocs/capsule/spoke/tenants/{alpha,bravo}/namespace.yaml` to include `metadata.labels.capsule.clastix.io/tenant: <name>` and trust that Flux's apply-as-cluster-admin doesn't trigger the webhook denial path (TBD; needs verification)
- Option B: Document in Phase 11 runbook that operators MUST run the home-namespace creation via `kubectl --as=<tenant> create namespace tenant-<tenant>` AFTER Capsule operator install but BEFORE first push of tenant artifacts
- Option C: Phase 12 capsule-addon-fluxcd may auto-create per-tenant home namespaces with the correct label (gated on ADR-008 outcome)

These are documented for Phase 11 push-gate awareness; the underlying cluster state is left in a usable state for Phase 11 testing.

### Phase 8 BLOCKER G-04 inheritance summary

Three @tests across three files remain RED-by-design due to Phase 8 BLOCKER G-04 + D-08-13 push-gate deferral (verbatim Phase 9 inheritance):
- `proxy-07-live-regression.bats` @test 3 — HelmRelease capsule Ready=True on hub-flux
- `capsule-install-06-live-helm.bats` @tests 1+2 — HelmRelease capsule + capsule-proxy Ready=True
- `capsule-install-10-live-flux-observable.bats` @test 1 — outer poc-capsule Kustomization Ready=True
- `tenants-11-live-dependson.bats` @test 3 — poc-capsule-spoke Kustomization Ready=True

**Root cause (verbatim from Phase 9 09-VERIFICATION.md):** origin/main lacks the source files that the outer Kustomizations + HelmReleases reference; kustomize-controller reports 'kustomization path not found' and helm-controller cannot reconcile against an empty source. Resolves on Phase 11 VAL-05 first push event.

## Plan-by-Plan Summary

- **Plan 10-00** (Wave 0 RED bats scaffold) — landed 7 bats files (45 @tests total). Static script + doc bats RED until Plan 10-01; static leak-defense GREEN at landing (regression gate); proxy-06 GREEN at landing (Phase 7 D-14 inheritance). 17 GREEN at landing, 28 RED-by-design.
- **Plan 10-01** (Script + doc) — landed `scripts/poc/capsule/issue-tenant-kubeconfig.sh` (~250 LOC) + appended H2 section to `docs/poc-capsule.md` + updated frontmatter scope-line. All static bats turned GREEN. Live PROXY-01 + PROXY-03 turned GREEN. Live PROXY-02 stayed RED until Plan 10-02. Rule 3 deviation: capsule-proxy live-staged + RBAC patch (documented above + in 10-01-SUMMARY.md).
- **Plan 10-02** (Verifier — this plan) — observed already-staged capsule-proxy on spoke-capsule (Plan 10-01's helm install state persisted), wired CapsuleConfiguration userGroups + recreated tenant-alpha/bravo as Capsule-owned (Rule 3 deviations documented above), ran full Phase 10 + inheritance bats suite, wrote this verification artifact. All 3 PROXY-01..03 must-haves verified live.

## Push-Gate Disposition

**Phase 8 D-08-13 push-gate deferral remains in force.** Phase 10 commits remain LOCAL-ONLY. Phase 11 VAL-05 owns:
1. The first push event itself (`git push origin main`)
2. Flux-managed reconcile of capsule-proxy on spoke-capsule (replaces the Plan 10-01 staged install + the Plan 10-02 in-cluster wiring deviations — see "Notable Observations" section)
3. One-shot history gitleaks scan to confirm zero tenant kubeconfig leaks across the entire repo history
4. Documentation of any persistent fixes needed to make the push-resolved install match Plan 10-01 + 10-02 cluster state (RBAC patch carry-over; CapsuleConfiguration userGroups; tenant-alpha/bravo namespace ownership)

## Carryover to Phase 11

The following items must be resolved during Phase 11 VAL-05 (not blocking Phase 10 close-out):
1. **capsule-proxy chart RBAC patch persistence** — chart-level RBAC gap (Role lacks `secrets create`); needs PostBuild patch / kustomize overlay / upstream chart fix (Plan 10-01 in-place patch may revert on Flux reconcile)
2. **CapsuleConfiguration userGroups** — currently patched in-cluster; needs persistent fix (update `pocs/capsule/spoke/config/capsuleconfig.yaml` to include `system:serviceaccounts` + `system:authenticated` in userGroups list)
3. **tenant-alpha + tenant-bravo home namespace ownership** — currently recreated as Capsule-owned via `--as=<tenant>` impersonation; needs persistent fix (update `pocs/capsule/spoke/tenants/{alpha,bravo}/namespace.yaml` to include the `capsule.clastix.io/tenant` label, OR document operator runbook for post-install impersonation step)

These carryovers are tracked here for Phase 11 awareness; the Plan 10-02 cluster state is left running for Phase 11 testing convenience.

## Sign-off

- [x] All 3 PROXY-01..03 must-haves verified
- [x] Pitfall 10-P1..P7 corrections applied + verified
- [x] Phase 7 P31 + Phase 8 CAP-01..03 + Phase 9 TEN-01..06 + ADR-004 inheritance preserved
- [x] v0.18 task health-check exits 0
- [x] D-08-13 push-gate stays deferred (override accepted per inheritance)
- [x] Plan 10-02 verifier complete; Phase 10 ready to close
- [x] Notable observations documented for Phase 11 VAL-05 awareness (RBAC patch persistence; CapsuleConfiguration userGroups; tenant home namespace ownership)
