# Phase 5: Workloads + Health + Rebuild - Research

**Phase:** 05-workloads-health-rebuild  
**Date:** 2026-04-27T21:37:37-04:00  
**Status:** Research complete

## Research Summary

Phase 5 should be planned as a small number of tightly ordered infrastructure
deliverables:

1. Static/live Bats contracts first, because this repo already uses Bats to pin
   script behavior, destructive gates, and live k3d proofs.
2. Example manifests and spoke wiring second, preserving the locked decision
   that `examples/` is canonical and spoke trees reference those examples.
3. `fix-coredns.sh` and `health-check.sh` as separate scripts because
   `health-check` is read-only and `fix-dns` mutates `hub-flux`.
4. Destroy/rebuild wrappers last, after deploy/health/fix scripts exist.
5. A final live destructive plan proves warm-cache rebuild timing and health.

## Technical Findings

### Flux and Kustomize

- Flux `Kustomization.spec.path` points at a directory inside the Source
  artifact and reconciles the manifests or the `kustomization.yaml` found there.
  This supports the existing Phase 4 model where hub-side Flux Kustomizations
  point at `./clusters/spoke-ml` and `./clusters/spoke-apps`.
- Flux marks a Kustomization `Ready=True` after source fetch, build, apply, and
  health checks pass. This is the right hub-side proof for HEALTH-03.
- `flux reconcile kustomization <name> --with-source` triggers a source sync,
  applies the Kustomization outside the interval, and waits for it to finish.
  This is the correct primitive for `deploy-examples`.
- Flux supports health checks for built-in `Deployment` and `Job` objects, so
  adding `spec.healthChecks` to the existing spoke Kustomizations is a viable
  planning option if research during execution confirms it behaves cleanly with
  remote `spec.kubeConfig` targets. If not, script-level waits remain sufficient.
- Open point: relative Kustomize resources from `clusters/spoke-*` to
  `../../examples/*` must be verified locally with the pinned Flux/Kustomize
  toolchain before implementation finalizes. If Flux/Kustomize rejects the
  traversal, the executor should stop and report the conflict rather than
  silently copy manifests into the spoke tree, because D-04 rejects duplication.

### Kubernetes Job Semantics

- Kubernetes Jobs are the right model for one-off `nvidia-smi`: Jobs run one or
  more Pods to completion and track completions.
- Completed Jobs and their Pods normally remain available for status/log
  inspection until deleted. `kubectl logs jobs/<name>` is documented and should
  be used by `health-check`.
- Job spec mutations can hit immutable-field errors. The locked decision is to
  delete/recreate only `job/nvidia-smi` from `deploy-examples` when a fresh run is
  needed.

### k3d DNS Fix

- k3d supports `k3d cluster stop <name>` and `k3d cluster start <name>`.
  `cluster start` waits by default for server/loadbalancer readiness. The Phase 5
  fix should target only `hub-flux`, then run Flux readiness checks.
- ROADMAP explicitly names the stale CoreDNS NodeHosts workaround as stop/start
  hub. Do not restart the spokes and do not patch CoreDNS manifests.

## Recommended Plan Architecture

### Plan 05-01: Phase 5 Test Contracts

Create Bats suites for:

- Deploy examples static contract: `examples/` layout, spoke kustomization
  relative references, `deploy-examples` GitOps-only behavior.
- Health/fix DNS static contract: `health-check` ordered read-only gates and
  `fix-coredns` hub-only stop/start.
- Destroy/rebuild static contract: confirmation, no prune, strict chain, timing
  hard-fail.
- Live/destructive smoke contract gated behind `require_live_destructive`.

### Plan 05-02: Example Manifests + Deploy Script

Create:

- `examples/podinfo/{kustomization,namespace,deployment,service}.yaml`
- `examples/gpu-smoke-test/{kustomization,namespace,job}.yaml`
- Append relative references to the existing spoke kustomizations.
- `scripts/deploy-examples.sh` to repair files, optionally delete the old GPU
  Job, reconcile source/Kustomizations, and wait for podinfo + GPU Job.
- `task deploy-examples`.

### Plan 05-03: DNS Fix Script

Create:

- `scripts/fix-coredns.sh`
- `task fix-dns`

The script should stop/start only `hub-flux`, then verify hub node readiness,
Flux controller readiness, and `flux check`.

### Plan 05-04: Health Check Script

Create:

- `scripts/health-check.sh`
- `task health-check`

The script runs fail-fast ordered gates:

1. Three clusters exist and nodes Ready.
2. Flux controllers Ready and `flux check` passes.
3. Hub-side `spoke-ml` and `spoke-apps` Kustomizations Ready=True.
4. In-hub DNS probe resolves `k3d-spoke-ml-server-0` and
   `k3d-spoke-apps-server-0`; stale DNS failure says `task fix-dns`.
5. `spoke-ml` advertises `nvidia.com/gpu` capacity > 0.
6. Spoke API TLS SANs include expected container hostnames.
7. Podinfo Deployment Available=True and GPU Job Complete=True/logs prove
   `NVIDIA-SMI`.

### Plan 05-05: Destroy/Rebuild UX

Create:

- `scripts/destroy.sh` wrapper around `scripts/delete-clusters.sh`.
- `scripts/rebuild.sh` strict chain wrapper.
- `task destroy` and `task rebuild`.

Destroy/rebuild must use a one-prompt outer confirmation model. Rebuild should
pass an explicit approved env var to `destroy.sh`, enforce 1200 seconds as a
hard failure, and print elapsed time.

### Plan 05-06: Live Destructive Verification

Run the full chain on the target machine with warm CUDA image cache:

- `task rebuild`
- `task health-check`
- live/destructive Bats suite

Record timing in Phase 5 summary/verification artifacts during execution. Do
not commit a machine-specific timing log.

## Validation Architecture

Use the existing Bats framework and shell/YAML greps. Validation layers:

- Static Bats after every plan: `bats tests/bats/*phase5*.bats` or the exact
  suites created in Plan 05-01.
- Script syntax: `bash -n scripts/deploy-examples.sh scripts/fix-coredns.sh
  scripts/health-check.sh scripts/destroy.sh scripts/rebuild.sh`.
- Kustomize local build checks if supported by the pinned tooling:
  `kubectl kustomize clusters/spoke-apps` and `kubectl kustomize
  clusters/spoke-ml`.
- Live checks behind `KARYON_LIVE_TESTS=1 KARYON_LIVE_TESTS_DESTRUCTIVE=1`.

Nyquist coverage:

- DEP-01..04 covered by deploy static tests, kustomize build, deploy live wait,
  podinfo Deployment availability, and GPU Job logs.
- HEALTH-01..07 covered by health/fix static tests plus read-only live
  health-check.
- DESTROY-01..06 covered by static confirmation/chain/prune tests and final
  live destructive rebuild timing.

## Sources

- Flux Kustomization docs: https://fluxcd.io/flux/components/kustomize/kustomizations/
- Flux reconcile kustomization CLI: https://fluxcd.io/flux/cmd/flux_reconcile_kustomization/
- Kubernetes Job docs: https://kubernetes.io/docs/concepts/workloads/controllers/job/
- k3d cluster stop docs: https://k3d.io/stable/usage/commands/k3d_cluster_stop/
- k3d cluster start docs: https://k3d.io/stable/usage/commands/k3d_cluster_start/
- podinfo upstream repo: https://github.com/stefanprodan/podinfo

## RESEARCH COMPLETE
