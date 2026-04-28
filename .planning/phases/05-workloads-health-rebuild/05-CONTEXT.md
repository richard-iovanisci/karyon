# Phase 5: Workloads + Health + Rebuild - Context

**Gathered:** 2026-04-27T21:37:37-04:00
**Status:** Ready for planning

<domain>
## Phase Boundary

Deliver the example workload layer, operational health checks, DNS repair task,
destructive teardown wrapper, and full rebuild chain for the existing three
cluster Flux lab. Scope:

- `examples/podinfo/` and `examples/gpu-smoke-test/` become the canonical
  workload manifest locations.
- `clusters/spoke-apps/` and `clusters/spoke-ml/` wire those examples into the
  existing one-Flux-Kustomization-per-spoke model created in Phase 4.
- `scripts/deploy-examples.sh` and `task deploy-examples` are GitOps-only: they
  create or repair local manifests/wiring, trigger Flux reconciliation/waits, and
  may force a fresh GPU smoke Job run, but never directly apply workload
  manifests to spokes as a fallback.
- `scripts/health-check.sh` and `task health-check` are read-only, fail-fast,
  and verify the ordered health gates from ROADMAP Phase 5.
- `scripts/fix-coredns.sh` and `task fix-dns` implement the documented k3d
  CoreDNS/NodeHosts workaround by stop/starting `hub-flux` only.
- `task destroy` wraps the existing cache-preserving teardown behind a typed
  confirmation.
- `task rebuild` runs the strict DESTROY-05 chain:
  destroy -> create-clusters -> bootstrap-flux -> register-spokes ->
  deploy-examples -> health-check.
- `task rebuild` measures elapsed wall-clock time and fails if a warm-cache run
  exceeds 20 minutes.

Out of scope:

- Additional observability stacks, dashboards, Prometheus, or DCGM exporter.
- New workload types beyond podinfo and `nvidia-smi`.
- Direct imperative workload deployment as a backup path.
- Repo hygiene, ADRs, README, rebuild runbook, CI, and prune lint beyond the
  Phase 5 artifacts explicitly needed here; those remain Phase 6.

</domain>

<decisions>
## Implementation Decisions

### Workload Wiring

- **D-01:** `examples/` is the source of truth. Put podinfo manifests under
  `examples/podinfo/` and GPU smoke manifests under
  `examples/gpu-smoke-test/`. The spoke cluster trees reference these examples
  instead of duplicating workload YAML.
- **D-02:** `task deploy-examples` is GitOps-only plus reconcile/wait. It may
  create or repair local manifest wiring, trigger Flux reconcile operations, and
  wait for rollout, but it must not imperatively `kubectl apply` podinfo or GPU
  workload manifests into the spokes.
- **D-03:** Keep one Flux `Kustomization` per spoke. Extend the existing
  Phase-4 `spoke-apps` and `spoke-ml` Kustomizations rather than adding
  workload-level Flux Kustomizations such as `spoke-apps-podinfo` or
  `spoke-ml-gpu-smoke`.
- **D-04:** Spoke trees should reference example manifests with relative
  Kustomize resources, e.g. `clusters/spoke-apps/kustomization.yaml` references
  `../../examples/podinfo` and `clusters/spoke-ml/kustomization.yaml` references
  `../../examples/gpu-smoke-test`. The planner/researcher must verify current
  Flux/Kustomize load-restriction behavior before locking the exact path form,
  but the desired model is no duplicated generated snapshots.

### GPU Smoke Lifecycle

- **D-05:** The GPU smoke test is a Kubernetes `Job` with a stable name such as
  `gpu-smoke/nvidia-smi`, not a long-lived Pod and not a CronJob/template-first
  system.
- **D-06:** `deploy-examples` is responsible for causing a fresh GPU smoke run
  when needed. `health-check` remains read-only and verifies the latest run.
- **D-07:** GPU proof comes from both the Job condition and logs:
  `job/nvidia-smi` must report `Complete=True`, and its logs must contain
  `NVIDIA-SMI` plus a CUDA/GPU device signal.
- **D-08:** If Kubernetes Job immutability blocks a rerun, the deploy path may
  delete/recreate only the `gpu-smoke/nvidia-smi` Job. Do not delete the
  namespace, examples, or broader spoke resources for a rerun.

### Health and DNS Behavior

- **D-09:** `health-check` is read-only. If it detects stale hub CoreDNS /
  NodeHosts symptoms, it fails with an exact `task fix-dns` remediation instead
  of mutating cluster state.
- **D-10:** `fix-dns` stop/starts only `hub-flux`, then waits for hub and Flux
  readiness. Do not restart all clusters and do not patch CoreDNS directly.
- **D-11:** `health-check` uses fail-fast ordered gates matching ROADMAP Phase 5:
  all three clusters exist and nodes Ready; Flux controllers Ready and
  `flux check` passes; hub-side spoke Kustomizations Ready; in-hub DNS probe;
  `spoke-ml` GPU capacity; spoke API TLS SANs; workload proofs.
- **D-12:** Spoke Kustomization health is proven from the hub side by querying
  Flux status on `k3d-hub-flux` and requiring `spoke-ml` and `spoke-apps` to be
  `Ready=True`.

### Destroy and Rebuild UX

- **D-13:** Destructive tasks use one typed confirmation at the outer task.
  `task destroy` requires typed `yes`. `task rebuild` requires typed `yes` once
  and then calls teardown through an explicit non-interactive approved path so
  users are not double-prompted mid-rebuild.
- **D-14:** `task rebuild` enforces the 20-minute warm-cache SLO as a hard
  failure. If elapsed wall-clock time exceeds 20 minutes, the command exits
  nonzero even if the final health check is green.
- **D-15:** Rebuild timing proof lives in script output and the Phase 5
  verification/summary artifact, not in a committed timing log.
- **D-16:** `task rebuild` uses the strict DESTROY-05 sequence:
  destroy -> create-clusters -> bootstrap-flux -> register-spokes ->
  deploy-examples -> health-check. Do not insert extra phases unless research
  proves a small preflight wrapper is necessary for clearer failures; the
  observable chain must remain DESTROY-05.

### Agent Discretion

- Exact podinfo version, service exposure details, namespaces, labels, and
  readiness probes are planner/researcher decisions as long as DEP-01 and the
  GitOps-only model are satisfied.
- Exact `nvidia-smi` Job YAML, restart/backoff policy, TTL behavior, log grep,
  timeout values, and whether `deploy-examples` deletes the Job before or after
  Flux reconcile are planner/researcher decisions within D-05..D-08.
- Exact Flux reconcile commands, wait timeouts, and failure-message wording are
  planner/researcher decisions, but failures must include actionable remediation
  commands consistent with existing scripts.
- Exact confirmation mechanism variable/name for the approved teardown path is
  flexible, but it must be explicit and cannot silently bypass confirmation.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project-level specs

- `.planning/PROJECT.md` - Core value (`task rebuild` under 20 minutes), active
  requirements for deploy examples, health-check, fix-dns, destroy, rebuild, and
  public-safe repo posture.
- `.planning/REQUIREMENTS.md` - Phase 5 REQ-IDs: DEP-01..04,
  HEALTH-01..07, DESTROY-01..06. Also note Phase 6 owns REPO/DOCS/ADR/CI
  deliverables unless a Phase 5 script must touch Taskfile wiring.
- `.planning/ROADMAP.md` - Phase 5 goal, dependencies, risk statement, success
  criteria, and exact rebuild chain. This is the source of truth for the ordered
  health gates and DESTROY-05/06.
- `.planning/STATE.md` - Current focus and accumulated decisions affecting
  Phase 5, especially cache preservation and the prior Phase 4 hub-spoke
  reconciliation proof.

### Prior phase contracts

- `.planning/phases/04-spoke-registration/04-CONTEXT.md` - Existing
  one-Kustomization-per-spoke model; `clusters/hub-flux/spokes/` resources;
  Phase 4 seed manifests under `clusters/spoke-ml/` and `clusters/spoke-apps/`;
  P18 guardrails around `spec.kubeConfig`; live Flux/inventory proof.
- `.planning/phases/03-flux-hub-bootstrap/03-CONTEXT.md` - Flux bootstrap
  idempotency, `clusters/hub-flux/flux-system/kustomization.yaml` patch
  surface, `bootstrap-flux` behavior, and `flux check`/controller readiness
  patterns.
- `.planning/phases/02-cluster-layer/02-CONTEXT.md` - k3d cluster creation,
  `k8s-net`, CUDA image, GPU capacity contract, TLS SAN verification, and
  cache-preserving `delete-clusters.sh` D-14.

### Existing code and docs

- `Taskfile.yml` - Current task surface: `build-image`, `create-clusters`,
  `delete-clusters`, `bootstrap-flux`, `register-spokes`. Phase 5 adds
  `deploy-examples`, `health-check`, `fix-dns`, `destroy`, and `rebuild`.
- `scripts/lib/preflight-lib.sh` - Shared script output helpers and style.
- `scripts/create-clusters.sh` - Existing idempotent cluster creation and TLS
  SAN verification pattern.
- `scripts/delete-clusters.sh` - Existing teardown implementation that preserves
  CUDA image/build cache and contains the D-14 `INTENTIONALLY NOT calling`
  comment.
- `scripts/bootstrap-flux.sh` - Existing Flux bootstrap/reconcile health pattern
  and token-safe script style.
- `scripts/register-spokes-for-flux.sh` - Existing hub-spoke registration,
  local-file repair, in-pod probe, and no-auto-push discipline.
- `clusters/hub-flux/spokes/spoke-ml.yaml` and
  `clusters/hub-flux/spokes/spoke-apps.yaml` - Existing hub-side Flux
  Kustomizations that Phase 5 extends indirectly via the spoke trees.
- `clusters/spoke-ml/kustomization.yaml` and
  `clusters/spoke-apps/kustomization.yaml` - Phase 4 seed Kustomizations that
  Phase 5 augments with relative `examples/` references.
- `tests/bats/test_helper.bash` - Existing `require_live` and
  `require_live_destructive` gates.
- `tests/bats/delete-clusters-01-cache.bats` - Existing cache-preservation test
  that Phase 5 destroy/rebuild work must not weaken.
- `tests/bats/register-spokes-02-live.bats` - Existing hub-spoke live proof and
  examples of in-hub TLS/auth probe patterns.
- `docs/flux-hub-spoke.md` - Operational hub-spoke model and reconciliation
  contract that Phase 5 must not contradict.

### External references to verify during research/planning

- Current Flux/Kustomize behavior for relative resource paths that reference
  directories outside the spoke tree from a GitRepository source.
- Current podinfo recommended Kubernetes manifests/image tag.
- Current Kubernetes Job immutability and rerun patterns under GitOps control.
- Current k3d stop/start behavior and CoreDNS/NodeHosts refresh workaround for
  the pinned k3d line.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- `scripts/lib/preflight-lib.sh`: source this in all new Phase 5 scripts for
  `section`, `pass`, `warn`, `fail`, `info`, `have`, counters, and ANSI gating.
- `scripts/delete-clusters.sh`: already implements the low-level teardown and
  cache-preservation proof. `task destroy` should wrap it rather than duplicating
  cluster deletion logic.
- `scripts/create-clusters.sh`: reusable gate/order style for fail-fast
  infrastructure scripts and exact SAN verification commands.
- `scripts/bootstrap-flux.sh`: reusable Flux readiness, `flux check`, controller
  wait, token-safe parsing discipline, and post-action verification pattern.
- `scripts/register-spokes-for-flux.sh`: reusable GitOps local-file repair plus
  reconciliation proof style; Phase 5 should keep the same "no direct workload
  apply to spokes" posture.
- `tests/bats/test_helper.bash`: reuse existing live/destructive gates for any
  rebuild or destroy live tests.

### Established Patterns

- Imperative scripts use `#!/usr/bin/env bash` and `set -euo pipefail`.
- Scripts source `scripts/lib/preflight-lib.sh` instead of duplicating helpers.
- Output is sectioned and remediation-rich: first failing gate should tell the
  user exactly which command to run next.
- Live/destructive Bats tests require both `KARYON_LIVE_TESTS=1` and
  `KARYON_LIVE_TESTS_DESTRUCTIVE=1`.
- Existing scripts prefer idempotent repair/check-first behavior and no hidden
  global state mutation.
- Secrets and kubeconfigs are never committed; manifests stay public-safe.

### Integration Points

- `clusters/spoke-apps/kustomization.yaml` currently lists Phase 4 seed
  resources. Phase 5 augments it with a reference to `../../examples/podinfo`.
- `clusters/spoke-ml/kustomization.yaml` currently lists Phase 4 seed resources.
  Phase 5 augments it with a reference to `../../examples/gpu-smoke-test`.
- Existing hub-side `spoke-apps` and `spoke-ml` Flux Kustomizations already
  reconcile the spoke trees. Phase 5 should avoid adding hub-side workload
  Kustomizations unless research proves the locked model cannot work.
- `Taskfile.yml` is currently a minimal task surface. Phase 5 extends it, while
  Phase 6 still owns full Taskfile organization/audit.
- `task rebuild` depends on all previous phases being green and on CUDA image
  cache surviving teardown. Any change to destroy/rebuild must keep
  `scripts/delete-clusters.sh` D-14 intact.

</code_context>

<specifics>
## Specific Ideas

- Preferred file layout:
  ```text
  examples/
    podinfo/
      kustomization.yaml
      namespace.yaml
      deployment.yaml
      service.yaml
    gpu-smoke-test/
      kustomization.yaml
      namespace.yaml
      job.yaml
  scripts/
    deploy-examples.sh
    health-check.sh
    fix-coredns.sh
  ```
- Preferred spoke wiring:
  ```yaml
  # clusters/spoke-apps/kustomization.yaml
  resources:
    - namespace.yaml
    - configmap.yaml
    - ../../examples/podinfo
  ```
  ```yaml
  # clusters/spoke-ml/kustomization.yaml
  resources:
    - namespace.yaml
    - configmap.yaml
    - ../../examples/gpu-smoke-test
  ```
- `deploy-examples` should be allowed to delete only the old
  `gpu-smoke/nvidia-smi` Job to force a fresh run, then reconcile/wait through
  Flux rather than applying workload manifests directly.
- `health-check` stale-DNS failure should point to `task fix-dns` and stop,
  because the check is intentionally read-only.
- `fix-dns` should wait for `hub-flux` and Flux controllers to become Ready
  after the stop/start before reporting success.
- `rebuild` should print elapsed time in a human-readable form and exit nonzero
  if elapsed seconds exceed 1200.

</specifics>

<deferred>
## Deferred Ideas

None - discussion stayed within phase scope.

</deferred>

---

*Phase: 05-workloads-health-rebuild*
*Context gathered: 2026-04-27T21:37:37-04:00*
