---
phase: 2
slug: cluster-layer
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-23
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Derived from `02-RESEARCH.md` §6 Validation Architecture.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bats-core 1.11+ (established in Phase 1 under `tests/bats/`) |
| **Config file** | `tests/bats/test_helper.bash` (sources `scripts/lib/preflight-lib.sh`) |
| **Quick run command** | `bats tests/bats/cuda-image-*.bats tests/bats/create-clusters-*.bats --tap` |
| **Full suite command** | `KARYON_LIVE_TESTS=1 bats tests/bats/ --tap` |
| **Estimated runtime** | ~30s (static) / ~8min (live-gated with cluster creation) |

---

## Sampling Rate

- **After every task commit:** Run `bats tests/bats/cuda-image-*.bats tests/bats/create-clusters-*.bats --tap` (L1/L2 only — static + mocked)
- **After every plan wave:** Run full suite with `KARYON_LIVE_TESTS=1` (L3/L4 — actual cluster bring-up)
- **Before `/gsd-verify-work`:** Full suite green; all 12 bats files present
- **Max feedback latency:** 30 seconds (L1/L2); 8 minutes (L3/L4 live)

---

## Sampling Levels (Nyquist methodology)

| Level | Scope | Automation | Invoked |
|-------|-------|-----------|---------|
| **L1: Script-level idempotency** | Re-running `create-clusters.sh`/`delete-clusters.sh` with state matching = zero external calls | bats-mock the `docker`/`k3d` commands; assert zero real invocations on 2nd run | Per task commit |
| **L2: Image-level smoke** | `docker run` the built image and sanity-check baked files (`config.toml.tmpl`, device-plugin manifest) | `docker run --rm --entrypoint cat ... /var/lib/rancher/k3s/...` assertions | Per wave merge (image-build task) |
| **L3: Cluster-level kubectl probe** | Live cluster; `kubectl get nodes Ready`; `nvidia.com/gpu` capacity reported | Wave 0: `[ -n "$KARYON_LIVE_TESTS" ]` gate in bats; run manually + in final verifier | Phase gate / human UAT |
| **L4: Cert-level openssl probe** | Each apiserver's SAN includes `k3d-<name>-server-0` | Same live-gated bats; `openssl s_client \| x509 \| grep` | Phase gate / human UAT |

---

## Per-Task Verification Map

> Populated during planning. Format: one row per task (filled when plans are finalized in step 8).

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| _(planner fills during step 8)_ | — | — | — | — | — | — | — | — | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| IMG-01 | Multi-stage Dockerfile with CUDA base | unit (L2) | `bats tests/bats/cuda-image-01-base.bats` | ❌ Wave 0 |
| IMG-02 | `ARG K3S_TAG` default present | unit (static) | `bats tests/bats/cuda-image-02-args.bats` | ❌ Wave 0 |
| IMG-03 | `config.toml.tmpl` sets `default_runtime_name = "nvidia"` | unit (L2) | `bats tests/bats/cuda-image-03-containerd.bats` | ❌ Wave 0 |
| IMG-04 | Device-plugin manifest present, version pinned (v0.17.4) | unit (L2) | `bats tests/bats/cuda-image-04-device-plugin.bats` | ❌ Wave 0 |
| IMG-05 | Manifest baked at `/var/lib/rancher/k3s/server/manifests/` | unit (L2) | `bats tests/bats/cuda-image-05-manifest-path.bats` | ❌ Wave 0 |
| IMG-06 | Image survives `delete-clusters.sh` | integration (L3) | `bats tests/bats/delete-clusters-01-cache.bats` (live-gated) | ❌ Wave 0 |
| CLU-01 | `k8s-net` idempotent creation | unit (L1) | `bats tests/bats/create-clusters-01-network.bats` | ❌ Wave 0 |
| CLU-02 | hub-flux on :6443 with stock image | integration (L3) | `bats tests/bats/create-clusters-02-hub-flux.bats` (live-gated) | ❌ Wave 0 |
| CLU-03 | spoke-ml on :6444 with `--gpus all` | integration (L3) | `bats tests/bats/create-clusters-03-spoke-ml.bats` (live-gated) | ❌ Wave 0 |
| CLU-04 | spoke-apps on :6445 | integration (L3) | `bats tests/bats/create-clusters-04-spoke-apps.bats` (live-gated) | ❌ Wave 0 |
| CLU-05 | `--k3s-arg '--tls-san=...@server:*'` syntax used | unit (static) + integration (L4) | `bats tests/bats/create-clusters-05-tls-san.bats` (static grep + live openssl) | ❌ Wave 0 |
| CLU-06 | delete removes clusters + network; preserves image | integration (L3) | `bats tests/bats/delete-clusters-01-cache.bats` (live-gated) | ❌ Wave 0 |

---

## Wave 0 Requirements

All 12 bats files are new in Phase 2. Planner MUST schedule a Wave 0 plan (e.g., `02-00-PLAN.md`) that creates stubs before any implementation plan runs:

- [ ] `tests/bats/cuda-image-01-base.bats` — static Dockerfile parse + `docker inspect` assertions
- [ ] `tests/bats/cuda-image-02-args.bats` — `grep 'ARG K3S_TAG='` static assertion
- [ ] `tests/bats/cuda-image-03-containerd.bats` — `docker run --entrypoint cat` on tmpl file
- [ ] `tests/bats/cuda-image-04-device-plugin.bats` — same pattern, target manifest path
- [ ] `tests/bats/cuda-image-05-manifest-path.bats` — combined with -04 (single fixture)
- [ ] `tests/bats/create-clusters-01-network.bats` — mock `docker network inspect`/`create`; idempotency + drift detection
- [ ] `tests/bats/create-clusters-02-hub-flux.bats` — live-gated
- [ ] `tests/bats/create-clusters-03-spoke-ml.bats` — live-gated; assert `nvidia.com/gpu` capacity ≥ 1
- [ ] `tests/bats/create-clusters-04-spoke-apps.bats` — live-gated
- [ ] `tests/bats/create-clusters-05-tls-san.bats` — static grep of `create_cluster()` helper + live openssl probe
- [ ] `tests/bats/delete-clusters-01-cache.bats` — live-gated; `docker images` assertion after teardown
- [ ] `tests/bats/test_helper.bash` — extend with cluster-test helpers (live-gate check, common kubectl assertions)

**Framework install:** bats-core is already installed in Phase 1 (`scripts/install-tools.sh` asdf plugin). No new framework dependencies needed.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| GPU smoke-test (`nvidia-smi` in a pod) | IMG-04, CLU-03 | Requires actual RTX 5090 hardware; not available in headless CI | Run Phase 5 GPU smoke-test pod; verify `nvidia-smi` output shows GPU |
| Build-cache survival across `task destroy` | IMG-06, DESTROY-03 | Requires user-level `docker images` inspection pre/post teardown | `scripts/delete-clusters.sh && docker images karyon/k3s-cuda` → image row still present |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references (12 bats files)
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s (L1/L2) and < 8min (L3/L4)
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
