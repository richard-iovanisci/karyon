---
phase: 05-workloads-health-rebuild
verified: 2026-04-28T17:27:01Z
status: passed
score: "16/16 must-haves verified"
overrides_applied: 0
---

# Phase 5: Workloads + Health + Rebuild Verification Report

**Phase Goal:** Deploy podinfo and a GPU `nvidia-smi` smoke test through hub-managed Flux, provide `task fix-dns` and read-only `task health-check`, and prove `task rebuild` completes the full destructive chain in under 20 minutes with a warm CUDA image cache.
**Verified:** 2026-04-28T17:27:01Z
**Status:** passed
**Re-verification:** Yes - final verification after code review fixes and final live rebuild proof.

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Canonical workload manifests exist under `examples/podinfo/` and `examples/gpu-smoke-test/`. | VERIFIED | Static Bats and kustomize builds passed; manifests are version-controlled and referenced from spoke trees. |
| 2 | `podinfo` is reconciled to `spoke-apps` by hub Flux, not by direct apply. | VERIFIED | `spoke-apps` Kustomization is `Ready=True` at `main@sha1:346221d72dbfd4e3bd855d9731d65414ac3180ea`; live deployment status is `Available=True`. |
| 3 | GPU smoke Job is reconciled to `spoke-ml` by hub Flux and runs pinned `nvidia-smi`. | VERIFIED | `spoke-ml` Kustomization is `Ready=True` at the same revision; live Job logs contain `NVIDIA-SMI`. |
| 4 | `scripts/deploy-examples.sh` has a Git visibility gate before Flux reconcile. | VERIFIED | Static tests passed for clean `examples/`/`clusters/` checks and `HEAD == origin/main` comparison; final rebuild deploy step reconciled revision `346221d`. |
| 5 | `scripts/fix-coredns.sh` implements the stale CoreDNS repair without mutating spokes. | VERIFIED | Static suite passed hub-only stop/start assertions and post-restart DNS fail-closed proof. |
| 6 | `scripts/health-check.sh` is read-only and checks clusters, Flux, spoke Kustomizations, DNS, GPU, TLS, and workloads. | VERIFIED | Rebuild embedded health-check passed: 19 passed, 0 warnings, 0 failed. Static tests passed mutation bans and ordered-section checks. |
| 7 | All three clusters and nodes are live and Ready after rebuild. | VERIFIED | Live node probes show `k3d-hub-flux-server-0`, `k3d-spoke-ml-server-0`, and `k3d-spoke-apps-server-0` are `Ready` on Kubernetes `v1.34.6+k3s1`. |
| 8 | `spoke-ml` exposes GPU capacity. | VERIFIED | Live node capacity reports `nvidia.com/gpu=1`; rebuild health-check also passed GPU capacity and `nvidia-smi` log gates. |
| 9 | Spoke apiserver TLS SANs validate for Docker-DNS hostnames. | VERIFIED | Final rebuild health-check passed SAN validation for `k3d-spoke-ml-server-0` and `k3d-spoke-apps-server-0`. |
| 10 | Destroy/rebuild wrappers preserve the CUDA image cache and avoid prune commands. | VERIFIED | Destroy step preserved `karyon/k3s-cuda:v1.34.6-k3s1-cuda12.8.1`; static tests passed no-prune assertions. |
| 11 | `task rebuild` runs the strict chain in order and re-pins hub context before bootstrap. | VERIFIED | `/tmp/karyon-rebuild.log` has ordered markers: preflight, destroy, create-clusters, `pin context k3d-hub-flux`, bootstrap-flux, register-spokes, deploy-examples, health-check. |
| 12 | `task rebuild` completes under the 20-minute SLO. | VERIFIED | Final approved run exited `0` and wrote `rebuild elapsed seconds: 190`, well below 1200 seconds. |
| 13 | Live state-checker Bats verifies post-rebuild state without invoking destructive commands. | VERIFIED | `KARYON_LIVE_TESTS=1 KARYON_LIVE_TESTS_DESTRUCTIVE=1 bats tests/bats/phase5-02-live.bats` passed 7/7. |
| 14 | Review-fix hardening is present and review is clean. | VERIFIED | `05-REVIEW.md` has `critical: 0`, `warning: 0`, `info: 0`, `status: clean`; follow-up OpenSSL probe fix is documented in `05-REVIEW-FIX.md`. |
| 15 | Schema drift gate is clear. | VERIFIED | `gsd-sdk query verify.schema-drift 05` returned `drift_detected: false`, `blocking: false`. |
| 16 | Structural drift gate does not block verification. | VERIFIED | `gsd-sdk query verify.codebase-drift` skipped with `reason: no-structure-md`, `action_required: false`. |

**Score:** 16/16 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `examples/podinfo/*` | Podinfo namespace, deployment, service, and kustomization. | VERIFIED | Static tests and `kubectl kustomize clusters/spoke-apps` passed. |
| `examples/gpu-smoke-test/*` | GPU smoke namespace, pinned CUDA Job, and kustomization. | VERIFIED | Static tests and `kubectl kustomize clusters/spoke-ml` passed. |
| `clusters/spoke-apps/kustomization.yaml` | References canonical podinfo example. | VERIFIED | Static tests and Flux reconciliation passed. |
| `clusters/spoke-ml/kustomization.yaml` | References canonical GPU smoke example. | VERIFIED | Static tests and Flux reconciliation passed. |
| `scripts/deploy-examples.sh` | GitOps-only deploy script with Git visibility gate and bounded waits. | VERIFIED | `bash -n` and static Bats passed; final rebuild deploy step passed. |
| `scripts/fix-coredns.sh` | Hub-only DNS repair script. | VERIFIED | `bash -n` and static Bats passed. |
| `scripts/health-check.sh` | Read-only ordered health gate. | VERIFIED | `bash -n`, static Bats, and final rebuild health-check passed. |
| `scripts/destroy.sh` | Destructive wrapper with typed approval / explicit approved path. | VERIFIED | `bash -n` and static Bats passed; final rebuild used explicit approved path. |
| `scripts/rebuild.sh` | Timed strict rebuild wrapper with structured log and SLO enforcement. | VERIFIED | `bash -n`, static Bats, live rebuild, and live state-checker passed. |
| `Taskfile.yml` | Tasks for deploy-examples, fix-dns, health-check, destroy, and rebuild. | VERIFIED | `task --list` shows all five Phase 5 tasks. |
| `tests/bats/phase5-02-live.bats` | State-only live checker for external rebuild proof. | VERIFIED | Gated live run passed 7/7 and static self-check asserts destructive invocations are absent. |

### Requirements Coverage

| Requirement | Status | Evidence |
|-------------|--------|----------|
| DEP-01 | SATISFIED | `podinfo` manifests exist and live deployment is `Available=True` on `spoke-apps`. |
| DEP-02 | SATISFIED | GPU smoke Job reconciles to `spoke-ml` and completed in final rebuild. |
| DEP-03 | SATISFIED | GPU smoke image is pinned to `nvcr.io/nvidia/cuda:12.8.0-base-ubuntu22.04` and runs `nvidia-smi`. |
| DEP-04 | SATISFIED | Example manifests live under version-controlled `examples/podinfo/` and `examples/gpu-smoke-test/`. |
| HEALTH-01 | SATISFIED | Final health-check verified all clusters exist and nodes are Ready. |
| HEALTH-02 | SATISFIED | Final health-check verified Flux controller deployments and `flux check`. |
| HEALTH-03 | SATISFIED | `spoke-ml` and `spoke-apps` Kustomizations are `Ready=True`. |
| HEALTH-04 | SATISFIED | Final health-check passed in-hub DNS probes for both spoke server hostnames. |
| HEALTH-05 | SATISFIED | `spoke-ml` GPU capacity is `1`. |
| HEALTH-06 | SATISFIED | Final health-check passed TLS SAN validation for both spokes. |
| HEALTH-07 | SATISFIED | `fix-coredns` task/script exists, is hub-only, and static tests pin fail-closed DNS proof. |
| DESTROY-01 | SATISFIED | `task destroy` wrapper requires typed `yes` unless approved env is set. |
| DESTROY-02 | SATISFIED | Destroy deletes all three k3d clusters and `k8s-net`; final rebuild destroy step passed. |
| DESTROY-03 | SATISFIED | Destroy/rebuild avoid prune commands and preserve CUDA image cache. |
| DESTROY-04 | SATISFIED | Bats lint rejects prune literals in scripts; full Bats regression passed. |
| DESTROY-05 | SATISFIED | Rebuild log proves strict chain order including hub context pin. |
| DESTROY-06 | SATISFIED | Final rebuild completed in 190 seconds and ended in a green health-check. |

No orphaned Phase 5 requirement IDs were found: all Phase 5 IDs listed in `.planning/REQUIREMENTS.md` are mapped to Phase 5 and marked complete.

### Verification Commands

| Command | Result |
|---------|--------|
| `KARYON_REBUILD_APPROVED=yes task rebuild` | Passed; elapsed 190 seconds. |
| `KARYON_LIVE_TESTS=1 KARYON_LIVE_TESTS_DESTRUCTIVE=1 bats tests/bats/phase5-02-live.bats` | Passed 7/7. |
| `KARYON_LIVE_TESTS=1 KARYON_LIVE_TESTS_DESTRUCTIVE=1 bats tests/bats/deploy-examples-01-static.bats tests/bats/deploy-examples-02-kustomize-build.bats tests/bats/fix-coredns-01-static.bats tests/bats/health-check-01-static.bats tests/bats/destroy-rebuild-01-static.bats tests/bats/register-spokes-01-static.bats tests/bats/phase5-02-live.bats` | Passed 101/101. |
| `bats tests/bats/*.bats` | Passed 169/169 with gated live/destructive checks skipped. |
| `bash -n scripts/deploy-examples.sh scripts/destroy.sh scripts/fix-coredns.sh scripts/health-check.sh scripts/rebuild.sh scripts/register-spokes-for-flux.sh` | Passed. |
| `kubectl kustomize clusters/spoke-apps` and `kubectl kustomize clusters/spoke-ml` | Passed. |
| `git diff --check` | Passed. |
| `gsd-sdk query verify.schema-drift 05` | No drift detected. |
| `gsd-sdk query verify.codebase-drift` | Skipped: `no-structure-md`; non-blocking. |

### Human Verification Required

None. The required runtime behavior is covered by deterministic Kubernetes, Flux, Bats, and log checks.

### Gaps Summary

No gaps found. Phase 5 achieved its goal and all 16 Phase 5 requirements are verified.

---

_Verified: 2026-04-28T17:27:01Z_
_Verifier: the agent_
