# Phase 5: Workloads + Health + Rebuild - Research

**Phase:** 05-workloads-health-rebuild  
**Date:** 2026-04-27T21:37:37-04:00  
**Status:** Research complete (revised 2026-04-27 after checker round 1)

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
- Source-refresh ordering: when `deploy-examples` reruns the GPU smoke Job by
  deleting and re-applying via Flux, the source-controller must have the
  latest commit before kustomize-controller reapplies; otherwise the rerun
  races with source fetch and can hit immutable-field rejection on stale
  spec. Plan 05-02 Task 3 therefore calls
  `flux reconcile source git flux-system --with-source` BEFORE
  `flux reconcile kustomization spoke-ml --with-source`.
- **RESOLVED (2026-04-27 after checker round 1):** Relative Kustomize
  resources from `clusters/spoke-*` to `../../examples/*` are verified
  buildable by the pinned `kubectl` toolchain via a dedicated Wave 0 Bats
  suite, `tests/bats/deploy-examples-02-kustomize-build.bats` (created in
  Plan 05-01 Task 2). The suite runs
  `kubectl kustomize "${REPO_ROOT}/clusters/spoke-apps"` and
  `kubectl kustomize "${REPO_ROOT}/clusters/spoke-ml"` and asserts both exit 0
  with output containing the expected `kind: Deployment`/`name: podinfo` and
  `kind: Job`/`name: nvidia-smi` literals — proving the relative traversal
  actually pulled in the example manifests. This fails CLOSED at planning
  verification time (after Plan 05-02 Task 2 lands manifests) so any
  toolchain rejection of the `../../examples/*` traversal blocks before mid-
  wave execution. Plan 05-02 Task 2's automated verify also runs the same
  `kubectl kustomize` build commands as a belt-and-braces gate. There is no
  remaining "stop and report" runtime fallback path; D-04 holds.

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

### Cluster Ready Timeout for Health-Check

- Empirically measured first-pull timing: after a fresh `task rebuild`, the
  NVIDIA device-plugin DaemonSet on `spoke-ml` takes 60-120s to register
  `nvidia.com/gpu` capacity on the node (cold image cache pulls vary). A 60s
  cluster-Ready timeout in `scripts/health-check.sh` would fail spuriously not
  from a slow chain but from an unforgiving health gate, threatening the
  20-minute SLO. Plan 05-04 therefore pins `--timeout=180s` for the cluster
  Ready node-wait, with a code-comment justifying the budget and a bats grep
  pinning the literal.

## Recommended Plan Architecture

### Plan 05-01: Phase 5 Test Contracts

Create Bats suites for:

- Deploy examples static contract: `examples/` layout, spoke kustomization
  relative references, `deploy-examples` GitOps-only behavior, pinned podinfo
  image tag (`ghcr.io/stefanprodan/podinfo:6.7.1`), 180s/300s wait literals,
  source-refresh-before-spoke-ml ordering.
- Deploy examples kustomize-build contract: `kubectl kustomize` exit 0 on both
  spoke trees (D-04 fail-closed gate; resolves prior open question).
- Fix-coredns static contract: `fix-coredns` hub-only stop/start (split out of
  the prior combined health bats so Plan 05-03 can verify independently).
- Health-check static contract: `health-check` ordered read-only gates,
  180s cluster timeout, GPU capacity / TLS SANs / Workload proofs literals.
- Destroy/rebuild static contract: confirmation, no prune, strict chain (in
  `bash "${SCRIPT_DIR}/<script>.sh"` form), 1200 hard-fail, ordered step
  markers, elapsed-seconds log line, `/tmp/karyon-rebuild.log` destination.
- Live/destructive STATE-CHECKER contract gated behind
  `require_live_destructive` — reads `/tmp/karyon-rebuild.log` and post-
  rebuild kubeconfig state. Does NOT execute `task rebuild` itself.

### Plan 05-02: Example Manifests + Deploy Script

Create:

- `examples/podinfo/{kustomization,namespace,deployment,service}.yaml` with
  podinfo image pinned to `ghcr.io/stefanprodan/podinfo:6.7.1`.
- `examples/gpu-smoke-test/{kustomization,namespace,job}.yaml`
- Append relative references to the existing spoke kustomizations.
- `scripts/deploy-examples.sh` to repair files, optionally delete the old GPU
  Job, reconcile source first, then Kustomizations, then wait for podinfo
  (180s) and GPU Job (300s).
- `task deploy-examples`.

### Plan 05-03: DNS Fix Script

Create:

- `scripts/fix-coredns.sh`
- `task fix-dns`

The script should stop/start only `hub-flux`, then verify hub node readiness,
Flux controller readiness, and `flux check`. Verified by the split bats
`fix-coredns-01-static.bats`.

### Plan 05-04: Health Check Script

Create:

- `scripts/health-check.sh` with 180s cluster Ready timeout and the seven
  ordered section literals.
- `task health-check`

The script runs fail-fast ordered gates:

1. Three clusters exist and nodes Ready (180s timeout).
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

- `scripts/destroy.sh` wrapper around `scripts/delete-clusters.sh` (uses
  `bash "${SCRIPT_DIR}/delete-clusters.sh"` form).
- `scripts/rebuild.sh` strict chain wrapper that writes
  `/tmp/karyon-rebuild.log` with ordered step markers
  (`>>> step destroy`..`>>> step health-check`) and a final
  `rebuild elapsed seconds: N` line.
- `task destroy` and `task rebuild`.

Destroy/rebuild must use a one-prompt outer confirmation model. Rebuild should
pass an explicit approved env var to `destroy.sh`, enforce 1200 seconds as a
hard failure, and print elapsed time.

### Plan 05-06: Live Destructive Verification

Run the full chain on the target machine with warm CUDA image cache:

- `task rebuild` (ONCE)
- `task health-check`
- live/destructive Bats STATE CHECKER suite (reads
  `/tmp/karyon-rebuild.log` and live cluster state; does NOT re-execute
  rebuild)

Record timing in Phase 5 summary/verification artifacts during execution. Do
not commit a machine-specific timing log.

## Validation Architecture

Use the existing Bats framework and shell/YAML greps. Validation layers:

- Static Bats after every plan: `bats tests/bats/*phase5*.bats` or the exact
  suites created in Plan 05-01.
- Build-time Bats: `bats tests/bats/deploy-examples-02-kustomize-build.bats`
  fails closed if `kubectl kustomize` rejects `../../examples/*` traversal.
- Script syntax: `bash -n scripts/deploy-examples.sh scripts/fix-coredns.sh
  scripts/health-check.sh scripts/destroy.sh scripts/rebuild.sh`.
- Kustomize local build checks gated in Plan 05-02 Task 2 verify:
  `kubectl kustomize clusters/spoke-apps` and `kubectl kustomize
  clusters/spoke-ml`.
- Live state-checker behind `KARYON_LIVE_TESTS=1
  KARYON_LIVE_TESTS_DESTRUCTIVE=1`.

Nyquist coverage:

- DEP-01..04 covered by deploy static tests, kustomize build, deploy live wait,
  podinfo Deployment availability, and GPU Job logs.
- HEALTH-01..07 covered by fix-coredns / health-check static tests plus
  read-only live health-check.
- DESTROY-01..06 covered by static confirmation/chain/prune/timing-log tests
  and final live state-checker bats reading /tmp/karyon-rebuild.log.

## Sources

- Flux Kustomization docs: https://fluxcd.io/flux/components/kustomize/kustomizations/
- Flux reconcile kustomization CLI: https://fluxcd.io/flux/cmd/flux_reconcile_kustomization/
- Kubernetes Job docs: https://kubernetes.io/docs/concepts/workloads/controllers/job/
- k3d cluster stop docs: https://k3d.io/stable/usage/commands/k3d_cluster_stop/
- k3d cluster start docs: https://k3d.io/stable/usage/commands/k3d_cluster_start/
- podinfo upstream repo: https://github.com/stefanprodan/podinfo (tag
  `6.7.1` pinned for Phase 5 deterministic rebuild SLO)

## RESEARCH COMPLETE
