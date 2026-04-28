---
phase: 4
slug: spoke-registration
status: verified
nyquist_compliant: true
wave_0_complete: true
created: 2026-04-27
updated: 2026-04-28
---

# Phase 4 - Validation Strategy

Per-phase validation contract for completed Phase 4 spoke registration.

Source artifacts:
- `04-01-PLAN.md` through `04-05-PLAN.md`
- `04-01-SUMMARY.md` through `04-05-SUMMARY.md`
- `04-VERIFICATION.md`
- Current test suite under `tests/bats/`

## Audit Summary

| Metric | Count |
|--------|-------|
| Requirements audited | 6 |
| Requirements covered | 6 |
| Gaps found | 0 |
| Gaps resolved in this audit | 0 |
| Manual-only requirements | 0 |

## Test Infrastructure

| Property | Value |
|----------|-------|
| Framework | bats-core |
| Config file | None; `tests/bats/test_helper.bash` is the shared loader. |
| Quick run command | `bats tests/bats/register-spokes-01-static.bats --tap` |
| Full non-destructive command | `bats tests/bats/ --tap` |
| Phase 4 live command | `KARYON_LIVE_TESTS=1 KARYON_LIVE_TESTS_DESTRUCTIVE=1 bats tests/bats/register-spokes-02-live.bats --tap` |
| Script static command | `bash -n scripts/register-spokes-for-flux.sh && shellcheck -e SC1091 scripts/register-spokes-for-flux.sh` |

## Sampling Rate

- After every Phase 4 source change: run `bats tests/bats/register-spokes-01-static.bats --tap`.
- After script changes: run `bash -n scripts/register-spokes-for-flux.sh && shellcheck -e SC1091 scripts/register-spokes-for-flux.sh`.
- Before Phase 4 sign-off: run `bats tests/bats/ --tap`.
- For live reconciliation proof: run the gated destructive suite with `KARYON_LIVE_TESTS=1 KARYON_LIVE_TESTS_DESTRUCTIVE=1`.
- For read-only live status: run `kubectl --context k3d-hub-flux -n flux-system get kustomization spoke-ml spoke-apps`.

## Per-Task Verification Map

| Req ID | Behavior | Automated Coverage | Current Status | Evidence |
|--------|----------|--------------------|----------------|----------|
| SPOKE-01 | Script creates `flux-reconciler` ServiceAccount and `flux-reconciler-cluster-admin` ClusterRoleBinding on each spoke. | Static Bats and live destructive Bats. | COVERED | Static tests 1-2 passed; live tests 5-6 exist and the latest gated run in `04-05-SUMMARY.md` passed 18/18. |
| SPOKE-02 | Script creates legacy `flux-reconciler-token` Secret with correct type, annotation, token, and CA data. | Static Bats, live destructive Bats, and in-script token wait. | COVERED | Static tests 3-4 passed; live tests 7-8 cover token and CA population. |
| SPOKE-03 | Kubeconfig server URL uses `https://k3d-<spoke>-server-0:6443`. | Static Bats, hub Secret decode tests, and verified HTTPS probes. | COVERED | Static test 5 passed; live decode tests 3-4 cover expected server URLs; current script uses `expected_server`. |
| SPOKE-04 | Hub stores each spoke kubeconfig in `flux-system/<spoke>-kubeconfig` under `data.value.yaml`. | Static Bats, live destructive Bats, and script presence/decode gates. | COVERED | Static tests 6-9 passed; live tests 1-4 cover hub Secret population and decode. |
| SPOKE-05 | Hub-side Flux Kustomizations reference the correct path and explicit `spec.kubeConfig.secretRef.{name,key}`; spoke seed resources reconcile to the target spokes. | Static/yq Bats, live Ready/inventory tests, cross-cluster falsifier tests, and read-only Flux check. | COVERED | Static tests 10-13 and 20-24 passed; current read-only Flux check shows `spoke-ml` and `spoke-apps` Ready=True at `main@sha1:8ce74cc3fdc3cbb5ad3a285dd000a1b986b1117e`. |
| SPOKE-06 | Kubeconfig embeds spoke CA data so TLS validates against the spoke apiserver hostname. | Script OpenSSL gate and live destructive Bats OpenSSL tests. | COVERED | Static test 18 pins verified OpenSSL probes; live tests 15-18 cover TLS, `/readyz`, and node-name proof; latest gated run in `04-05-SUMMARY.md` passed 18/18. |

## Cross-Cutting Gates

| Gate | Coverage | Status |
|------|----------|--------|
| D-02 spokes mount sentinel | `register-spokes-01-static.bats` asserts `# KARYON SPOKES MOUNT`, `- ../spokes`, and the inherited `# FLUX PATCH SURFACE`. | COVERED |
| D-04 no script-driven Git mutation | Static Bats rejects executable `git add`, `git commit`, and `git push` in `scripts/register-spokes-for-flux.sh`. | COVERED |
| D-11 token safety | Static Bats rejects trace mode, helper logging funnels, `tee`, and `--from-literal`; script applies hub Secrets via stdin. | COVERED |
| D-13 credential verification | Script verifies hub Secret presence, decode, server URL, token presence, CA decode/equality, OpenSSL TLS, `/readyz`, and node-name proof. | COVERED |
| P18 silent-misroute proof | Static Bats pins explicit `spec.kubeConfig`; script and live Bats reject hub node-name routing; live falsifier checks resources are not on hub. | COVERED |

## Gap Analysis

| Requirement | Gap Type | Result |
|-------------|----------|--------|
| SPOKE-01 | none | Covered by static and live tests. |
| SPOKE-02 | none | Covered by static, live, and in-script gates. |
| SPOKE-03 | none | Covered by static, decode, and HTTPS route proof. |
| SPOKE-04 | none | Covered by static, live Secret, and in-script decode gates. |
| SPOKE-05 | none | Covered by static/yq, Flux Ready, inventory, and cross-cluster falsifier checks. |
| SPOKE-06 | none | Covered by OpenSSL CA/TLS verification in script and live Bats. |

No generated test files were needed in this audit.

## Verification Evidence

| Check | Result |
|-------|--------|
| `bats tests/bats/register-spokes-01-static.bats --tap` | Passed 24/24 on 2026-04-28. |
| `bats tests/bats/register-spokes-02-live.bats --tap` without destructive env gates | Passed as 18 clean skips on 2026-04-28. |
| `bats tests/bats/ --tap` | Passed 92/92 on 2026-04-28; live/destructive checks skipped without opt-in env gates. |
| `shellcheck -e SC1091 scripts/register-spokes-for-flux.sh` | Passed on 2026-04-28. |
| Read-only current Flux check | `spoke-ml` and `spoke-apps` Ready=True at `main@sha1:8ce74cc3fdc3cbb5ad3a285dd000a1b986b1117e`. |
| Latest gated destructive live proof | `04-05-SUMMARY.md` records `KARYON_LIVE_TESTS=1 KARYON_LIVE_TESTS_DESTRUCTIVE=1 bats tests/bats/register-spokes-02-live.bats --tap` passed 18 ok, 0 not ok, 0 skipped. |

## Manual-Only Verifications

No Phase 4 requirement is manual-only. The live Kubernetes/Flux checks are automated but intentionally gated by `KARYON_LIVE_TESTS=1 KARYON_LIVE_TESTS_DESTRUCTIVE=1`.

## Validation Audit 2026-04-28

| Metric | Count |
|--------|-------|
| Gaps found | 0 |
| Resolved | 0 |
| Escalated | 0 |

## Validation Sign-Off

- [x] All Phase 4 requirements have automated verification.
- [x] Static contract is green.
- [x] Non-destructive full suite is green.
- [x] Live destructive suite exists, is gated, and has recorded passing evidence.
- [x] No manual-only requirements remain.
- [x] `nyquist_compliant: true` set in frontmatter.

**Approval:** verified 2026-04-28
