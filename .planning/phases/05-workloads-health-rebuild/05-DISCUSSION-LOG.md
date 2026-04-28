# Phase 5: Workloads + Health + Rebuild - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md - this log preserves the alternatives considered.

**Date:** 2026-04-27T21:37:37-04:00
**Phase:** 5-Workloads + Health + Rebuild
**Areas discussed:** Workload wiring, GPU smoke lifecycle, Health and DNS behavior, Destroy/rebuild UX

---

## Workload Wiring

### How should Phase 5 connect the example workloads to Flux?

| Option | Description | Selected |
|--------|-------------|----------|
| Examples as source of truth | Put manifests under `examples/podinfo/` and `examples/gpu-smoke-test/`, then reference them from `clusters/spoke-apps/` and `clusters/spoke-ml/`. | yes |
| Cluster trees only | Put workload manifests directly under `clusters/spoke-apps/` and `clusters/spoke-ml/`. | |
| Separate hub Kustomizations | Add new Flux Kustomizations under `clusters/hub-flux/spokes/` for each workload. | |

**User's choice:** Examples as source of truth  
**Notes:** This preserves DEP-04 and makes `examples/` canonical.

### What should `task deploy-examples` be allowed to do?

| Option | Description | Selected |
|--------|-------------|----------|
| GitOps-only + reconcile | Create/repair manifest wiring, never `kubectl apply` workloads directly to spokes; during rebuild, run Flux reconcile/wait so committed examples roll out. | yes |
| GitOps files only | Create/repair files and print commit/push instructions, but do not reconcile. | |
| Imperative fallback | If Flux is slow or broken, directly apply workloads to spokes. | |

**User's choice:** GitOps-only + reconcile  
**Notes:** Direct workload apply to spokes is rejected as a drift source.

### How much should Phase 5 split workload status in Flux?

| Option | Description | Selected |
|--------|-------------|----------|
| Keep one Kustomization per spoke | Add podinfo/gpu resources into the existing `spoke-apps` and `spoke-ml` Flux Kustomizations. | yes |
| Add workload-level Flux Kustomizations | Keep Phase 4 spoke seeds separate, and add `spoke-apps-podinfo` / `spoke-ml-gpu-smoke` Kustomizations. | |
| Let planner choose | Planner decides after checking Flux/Kustomize path constraints. | |

**User's choice:** Keep one Kustomization per spoke  
**Notes:** This preserves the Phase 4 model.

### How should the `examples/` manifests be referenced from the spoke trees?

| Option | Description | Selected |
|--------|-------------|----------|
| Relative Kustomize references | `clusters/spoke-apps/kustomization.yaml` references `../../examples/podinfo`; `clusters/spoke-ml/kustomization.yaml` references `../../examples/gpu-smoke-test`. | yes |
| Copy generated snapshots | `deploy-examples` copies manifests from `examples/` into `clusters/spoke-*`. | |
| Planner decides after testing | Prefer relative refs unless Flux/Kustomize load restrictions reject crossing out of the spoke tree. | |

**User's choice:** Relative Kustomize references  
**Notes:** Research/planning must verify current load-restriction behavior.

---

## GPU Smoke Lifecycle

### What Kubernetes shape should the `nvidia-smi` smoke test use?

| Option | Description | Selected |
|--------|-------------|----------|
| Job with stable name | A `Job` such as `gpu-smoke/nvidia-smi` reconciled by Flux. | yes |
| Long-lived Pod | A Pod that runs `nvidia-smi` then sleeps so logs remain easy to inspect. | |
| CronJob/manual Job template | Flux owns a reusable template, while deploy/health triggers runs. | |

**User's choice:** Job with stable name  
**Notes:** Stable name keeps health-check lookup straightforward.

### Should the Job be expected to run fresh on each `task deploy-examples` or `task health-check`?

| Option | Description | Selected |
|--------|-------------|----------|
| Fresh on deploy, read-only in health | `deploy-examples` forces a rerun when needed; `health-check` only verifies the latest Job succeeded and logs contain `NVIDIA-SMI`. | yes |
| Fresh on every health-check | `health-check` deletes/recreates the Job before checking logs. | |
| Only first reconcile | Flux creates the Job once; later checks only inspect existing completion/logs. | |

**User's choice:** Fresh on deploy, read-only in health  
**Notes:** Keeps health-check read-only.

### Where should `health-check` read the GPU proof from?

| Option | Description | Selected |
|--------|-------------|----------|
| Job condition + logs | Check `job/nvidia-smi` is `Complete=True`, then assert logs contain `NVIDIA-SMI` and a CUDA/GPU device line. | yes |
| Node capacity only | Rely on `nvidia.com/gpu` capacity and skip Job logs. | |
| ConfigMap result artifact | Job writes a ConfigMap with parsed result; health-check reads that. | |

**User's choice:** Job condition + logs  
**Notes:** Node capacity alone is insufficient for DEP-02/03.

### What should happen when a previous stable-name Job blocks rerun because Kubernetes Jobs are immutable?

| Option | Description | Selected |
|--------|-------------|----------|
| Script deletes/recreates only the Job | `deploy-examples` deletes the old `gpu-smoke/nvidia-smi` Job before reconciling or rerunning, leaving namespace/manifests intact. | yes |
| Use generated Job names | Avoid immutability by generating unique Job names. | |
| Planner decides after testing Flux behavior | Prefer stable name, but allow generated names if Flux/Kustomize cannot manage reruns cleanly. | |

**User's choice:** Script deletes/recreates only the Job  
**Notes:** Rerun mutation is intentionally narrow.

---

## Health and DNS Behavior

### What should `task health-check` do when it detects stale hub CoreDNS / NodeHosts behavior?

| Option | Description | Selected |
|--------|-------------|----------|
| Fail with fix command | Health-check stays read-only and says to run `task fix-dns`. | yes |
| Auto-run fix-dns once | Health-check mutates only for this known failure, then retries. | |
| Warn only | Print a warning but keep checking other gates. | |

**User's choice:** Fail with fix command  
**Notes:** Read-only health-check is locked.

### What should `task fix-dns` do?

| Option | Description | Selected |
|--------|-------------|----------|
| Stop/start hub only | Run `k3d cluster stop hub-flux` then `k3d cluster start hub-flux`, wait for Flux controllers, then exit. | yes |
| Restart all clusters | Stop/start hub and both spokes. | |
| Patch CoreDNS directly | Restart CoreDNS pods or edit config. | |

**User's choice:** Stop/start hub only  
**Notes:** Matches ROADMAP and targets the known stale NodeHosts issue.

### How strict should `health-check` be about ordering?

| Option | Description | Selected |
|--------|-------------|----------|
| Fail-fast ordered gates | Clusters/nodes -> Flux controllers/check -> spoke Kustomizations -> DNS -> GPU capacity -> TLS SAN -> workload proofs. | yes |
| Collect all failures | Run every check and print a full report. | |
| Hybrid | Fail fast on prerequisites, collect failures on independent checks. | |

**User's choice:** Fail-fast ordered gates  
**Notes:** First failure should be the most actionable.

### How should `health-check` prove spoke Kustomizations are healthy?

| Option | Description | Selected |
|--------|-------------|----------|
| Hub-side Flux status | Query `flux-system` Kustomizations on `k3d-hub-flux` and require `spoke-ml` and `spoke-apps` `Ready=True`. | yes |
| Direct spoke resources only | Skip Flux status and look only for podinfo/GPU objects on spokes. | |
| Both Flux status and direct resources | Require Kustomizations Ready and then verify workload objects directly. | |

**User's choice:** Hub-side Flux status  
**Notes:** Workload proofs are still later health gates, but Kustomization health is hub-side.

---

## Destroy/Rebuild UX

### How should confirmation work for destructive tasks?

| Option | Description | Selected |
|--------|-------------|----------|
| Single typed confirmation at outer task | `task destroy` requires typed `yes`; `task rebuild` requires typed `yes` once, then calls destroy in a non-interactive approved mode. | yes |
| Prompt every destructive script | `task rebuild` prompts once, then `destroy` prompts again. | |
| Env-gated bypass only | No prompt if `KARYON_CONFIRM_DESTROY=1` or similar is set; otherwise fail. | |

**User's choice:** Single typed confirmation at outer task  
**Notes:** Rebuild should not double-prompt.

### How should the 20-minute rebuild SLO be enforced?

| Option | Description | Selected |
|--------|-------------|----------|
| Fail if over 20 minutes | `task rebuild` measures wall-clock and exits nonzero when the warm-cache run exceeds 20 minutes. | yes |
| Warn if over 20 minutes | Keep the lab usable even if slow, but surface the SLO miss. | |
| Record only | Write timing to logs/docs, no pass/fail behavior. | |

**User's choice:** Fail if over 20 minutes  
**Notes:** Makes the core value falsifiable.

### Where should the rebuild timing proof live?

| Option | Description | Selected |
|--------|-------------|----------|
| Script output + verification artifact | `task rebuild` prints elapsed time; later verification records the measured run in Phase 5 verification/summary. | yes |
| Committed timing log | Append measured runs to a repo file. | |
| Docs only | The rebuild runbook captures expected timings, but scripts do not persist anything. | |

**User's choice:** Script output + verification artifact  
**Notes:** Avoids committing machine-specific timing logs.

### How should `task rebuild` sequence the existing and new tasks?

| Option | Description | Selected |
|--------|-------------|----------|
| Strict full chain | destroy -> create-clusters -> bootstrap-flux -> register-spokes -> deploy-examples -> health-check. | yes |
| Preflight first, then full chain | preflight -> destroy -> create-clusters -> bootstrap-flux -> register-spokes -> deploy-examples -> health-check. | |
| Planner decides | Preserve DESTROY-05 ordering but allow a separate initial preflight if it materially improves failure messages. | |

**User's choice:** Strict full chain  
**Notes:** Matches DESTROY-05.

---

## Agent Discretion

- Exact podinfo version, Job details, Flux wait timeouts, and confirmation variable names are left for research/planning within the locked decisions.

## Deferred Ideas

None.
