---
phase: 2
slug: cluster-layer
status: verified
nyquist_compliant: true
wave_0_complete: true
created: 2026-04-23
updated: 2026-04-28
---

# Phase 2 - Validation Strategy

Per-phase validation contract for completed Phase 2 cluster layer.

Source artifacts:
- `02-01-PLAN.md` through `02-07-PLAN.md`
- `02-01-SUMMARY.md` through `02-07-SUMMARY.md`
- `02-VERIFICATION.md`
- `02-HUMAN-UAT.md`
- Current test suite under `tests/bats/`

## Audit Summary

| Metric | Count |
|--------|-------|
| Requirements audited | 12 |
| Requirements covered | 12 |
| Gaps found | 2 |
| Gaps resolved in this audit | 2 |
| Manual-only requirements | 0 |

## Test Infrastructure

| Property | Value |
|----------|-------|
| Framework | bats-core |
| Config file | `tests/bats/test_helper.bash` |
| Quick run command | `bats tests/bats/cuda-image-*.bats tests/bats/create-clusters-*.bats tests/bats/delete-clusters-*.bats --tap` |
| Live-gated command | `KARYON_LIVE_TESTS=1 bats tests/bats/cuda-image-*.bats tests/bats/create-clusters-*.bats tests/bats/delete-clusters-*.bats --tap` |
| Destructive command | `KARYON_LIVE_TESTS=1 KARYON_LIVE_TESTS_DESTRUCTIVE=1 bats tests/bats/delete-clusters-01-cache.bats --tap` |

## Sampling Rate

- After image, cluster, or teardown script changes: run the quick Phase 2 Bats command.
- After live cluster changes: run the live-gated command.
- Before milestone sign-off: run `bats tests/bats/ --tap`.
- Before changing teardown behavior: run the destructive command with explicit opt-in.

## Per-Requirement Verification Map

| Req ID | Behavior | Automated Coverage | Current Status | Evidence |
|--------|----------|--------------------|----------------|----------|
| IMG-01 | Custom image Dockerfile uses CUDA base plus rancher/k3s build stage. | `cuda-image-01-base.bats` static check. | COVERED | Phase 2 suite passed; `02-VERIFICATION.md` confirms Dockerfile. |
| IMG-02 | Dockerfile exposes `ARG K3S_TAG=v1.34.6-k3s1`. | `cuda-image-02-args.bats` static check. | COVERED | Phase 2 suite passed. |
| IMG-03 | Baked containerd template sets `default_runtime_name = "nvidia"`. | `cuda-image-03-containerd.bats` live-gated docker-run check. | COVERED | Live-gated Phase 2 suite passed with `KARYON_LIVE_TESTS=1`. |
| IMG-04 | Device-plugin manifest pins `v0.17.4`. | `cuda-image-04-device-plugin.bats` static check. | COVERED | Phase 2 suite passed. |
| IMG-05 | Device-plugin manifest is baked into k3s auto-apply path. | `cuda-image-05-manifest-path.bats` live-gated docker-run check. | COVERED | Live-gated Phase 2 suite passed with `KARYON_LIVE_TESTS=1`. |
| IMG-06 | CUDA image survives teardown. | `delete-clusters-01-cache.bats` destructive live-gated check plus `02-06-SUMMARY.md` checkpoint evidence. | COVERED | Automated destructive test exists and skips unless double-gated; `02-VERIFICATION.md` records image survival. |
| CLU-01 | `k8s-net` network declaration is pinned. | `create-clusters-01-network.bats` static check. | COVERED | Phase 2 suite passed. |
| CLU-02 | `hub-flux` cluster reports exactly one Ready node. | `create-clusters-02-hub-flux.bats` live-gated exact column check. | COVERED | Gap fixed in this audit; targeted live run passed. |
| CLU-03 | `spoke-ml` reports GPU capacity >= 1. | `create-clusters-03-spoke-ml.bats` live-gated kubectl check. | COVERED | Live-gated Phase 2 suite passed with `KARYON_LIVE_TESTS=1`. |
| CLU-04 | `spoke-apps` cluster reports exactly one Ready node. | `create-clusters-04-spoke-apps.bats` live-gated exact column check. | COVERED | Gap fixed in this audit; targeted live run passed. |
| CLU-05 | All apiserver certs include `k3d-<name>-server-0` SAN and use `--tls-san=...@server:*`. | `create-clusters-05-tls-san.bats` static plus live all-cluster OpenSSL check. | COVERED | Gap fixed in this audit; targeted live run passed for hub-flux, spoke-ml, and spoke-apps. |
| CLU-06 | Delete script removes clusters/network while preserving image cache. | `delete-clusters-01-cache.bats` static and destructive live-gated checks. | COVERED | Static check passed; destructive behavior has recorded Phase 2 checkpoint evidence. |

## Gaps Resolved In This Audit

| Gap | Previous State | Resolution | Files |
|-----|----------------|------------|-------|
| Ready/NotReady false positive | `create-clusters-02-hub-flux.bats` and `create-clusters-04-spoke-apps.bats` used `grep -c Ready`, which also matches `NotReady`. | Replaced with exact column-2 `awk '$2 == "Ready"'` checks and `-eq 1` assertions. | `tests/bats/create-clusters-02-hub-flux.bats`, `tests/bats/create-clusters-04-spoke-apps.bats` |
| Partial SAN coverage | `create-clusters-05-tls-san.bats` live test checked only hub-flux. | Expanded live OpenSSL check to hub-flux, spoke-ml, and spoke-apps. | `tests/bats/create-clusters-05-tls-san.bats` |

## Cross-Cutting Gates

| Gate | Coverage | Status |
|------|----------|--------|
| No destructive image pruning | `delete-clusters-01-cache.bats` checks the D-14 blocking comment; `02-VERIFICATION.md` confirms no executable prune invocation. | COVERED |
| Live tests are opt-in | `require_live` and `require_live_destructive` gate Docker/k3d and destructive tests. | COVERED |
| GPU contract | Dockerfile, containerd template, device-plugin manifest, and spoke-ml live GPU check are all covered. | COVERED |
| TLS SAN contract | Static `--tls-san=...@server:*` check plus live all-cluster cert SAN probe. | COVERED |

## Verification Evidence

| Check | Result |
|-------|--------|
| Targeted changed tests without live env | Passed 4/4; live checks skipped cleanly where expected. |
| `KARYON_LIVE_TESTS=1` targeted changed tests | Passed 4/4. |
| Phase 2 quick suite | Passed 13/13 without live env; live/destructive checks skipped cleanly. |
| Phase 2 live-gated suite | Passed 13/13 with `KARYON_LIVE_TESTS=1`; only destructive teardown test skipped without `KARYON_LIVE_TESTS_DESTRUCTIVE=1`. |
| Historical destructive proof | `02-VERIFICATION.md` and `02-HUMAN-UAT.md` record Phase 2 destructive/cache and live cluster checks resolved on 2026-04-24. |

## Manual-Only Verifications

No Phase 2 requirement is manual-only after this audit. Some checks are still live-gated or destructive-gated, but each has an automated command.

## Validation Audit 2026-04-28

| Metric | Count |
|--------|-------|
| Gaps found | 2 |
| Resolved | 2 |
| Escalated | 0 |

## Validation Sign-Off

- [x] All Phase 2 requirements have automated verification.
- [x] Static Phase 2 suite is green.
- [x] Live-gated Phase 2 suite is green.
- [x] Destructive teardown/cache check remains automated and explicitly double-gated.
- [x] No manual-only requirements remain.
- [x] `nyquist_compliant: true` set in frontmatter.

**Approval:** verified 2026-04-28
