# karyon

## What This Is

A reproducible, source-controlled local Kubernetes lab that rebuilds a three-cluster topology — Flux hub + ML spoke (GPU) + apps spoke — on Windows 11 + WSL2 + k3d. Everything is driven by a Taskfile and idempotent scripts; a fresh clone reaches a working hub-spoke Flux GitOps environment using only documented commands. Audience: the author (and anyone who wants to mirror the setup on similar hardware) for learning, experimenting, and running GPU-capable workloads locally without cloud spend.

## Core Value

`task rebuild` performs a scorched-earth teardown and reaches a healthy hub-spoke Flux lab — with a CUDA-capable spoke — in under 20 minutes, every time.

## Requirements

### Validated

<!-- Shipped and confirmed valuable. -->

- [x] `task create-clusters` idempotently creates hub-flux (6443), spoke-ml (6444 + `--gpus all`), spoke-apps (6445) on `rancher/k3s:v1.34.6-k3s1` *(Validated in Phase 2: Cluster Layer — CLU-01..05)*
- [x] Custom `k3s+CUDA` image (CUDA 12.8+ base) for spoke-ml, cached across `task destroy` runs *(Validated in Phase 2: Cluster Layer — IMG-01..06; cache-preservation primitive in scripts/delete-clusters.sh via D-14; `task destroy` wrapper itself deferred to Phase 5)*
- [x] NVIDIA device plugin DaemonSet deployed to spoke-ml exposing `nvidia.com/gpu` *(Validated in Phase 2: Cluster Layer — IMG-04; pinned to v0.17.4 per D-15 Blackwell override of REQUIREMENTS.md v0.19.0+)*

### Active

<!-- Current scope. Building toward these. -->

- [ ] Single WSL2 Ubuntu 24.04 instance hosts all clusters on a shared `k8s-net` Docker network
- [ ] Docker Engine installed directly in WSL2 (no Docker Desktop integration)
- [ ] NVIDIA container toolkit + Docker nvidia runtime configured for GPU pass-through
- [ ] Tool versions pinned via checked-in `.tool-versions` and installed via asdf
- [ ] `task preflight` verifies env, resources, GPU chain, tools, ports, and residual k3d/network state
- [ ] `task bootstrap-flux` runs `flux bootstrap github` on hub-flux idempotently (path = `clusters/hub-flux`)
- [ ] `task register-spokes` provisions SA + cluster-admin CRB on each spoke and stores a remote kubeconfig Secret on hub-flux (key `value.yaml`, server `https://k3d-<spoke>-server-0:6443`)
- [ ] Hub-only Flux control plane reconciles Kustomizations into spokes via `spec.kubeConfig` (no Flux on spokes)
- [ ] `task deploy-examples` deploys a sample app to spoke-apps and a GPU smoke-test pod to spoke-ml
- [ ] `task fix-dns` stops/starts the hub to clear stale CoreDNS NodeHosts after Docker/WSL restart
- [ ] `task health-check` verifies clusters, nodes, Flux controllers, spoke Kustomizations, and cross-cluster DNS resolution
- [ ] `task destroy` confirms, removes clusters + `k8s-net`, and preserves docker build cache (CUDA image survives)
- [ ] `task rebuild` = destroy → create → bootstrap → register → deploy → health-check, completing in under 20 minutes with CUDA image cached
- [ ] Five ADRs written under `docs/adr/` for the locked architectural decisions
- [ ] README covers Windows prereqs, WSL config, Docker install, NVIDIA setup, cluster creation, Flux bootstrap, spoke registration, teardown
- [ ] Repo is safe to publish publicly: no committed secrets, all sensitive inputs via gitignored `.env` with a committed `.env.example` template, placeholder comments where user substitution is required
- [ ] Destructive tasks (`destroy`, `rebuild`) require explicit confirmation
- [ ] All scripts are idempotent, fail fast, preflight their own prerequisites, and produce useful errors
- [ ] Documented NAT-mode fallback procedure for WSL2 `networkingMode=mirrored` edge cases with Docker custom networks

### Out of Scope

<!-- Explicit boundaries. Includes reasoning to prevent re-adding. -->

- Production hardening — lab-only; no HA, no hardened RBAC, no network policies baseline
- Cloud clusters — local-only by design; keeps dependencies and cost predictable
- Real secret management — placeholder structure only (gitignored `.env` + `.env.example`); Vault/SOPS/age deferred to a later milestone
- Full ML workload implementation — GPU smoke-test verifies `nvidia-smi` from inside a pod only; framework workloads are separate work
- NVIDIA GPU Operator — device plugin DaemonSet path first; Operator deferred if/when needed
- ArgoCD — Flux-only; trade-offs captured in ADR-003 with migration note
- One WSL2 distro per cluster — all distros share the host VM; per-distro isolation is illusory (ADR-001)
- Non-Windows hosts — targets Windows 11 + WSL2 only; Linux-native and macOS not supported in v1
- CI/CD pipeline — local dev loop only; GitHub Actions integration deferred

## Context

**Host target:** Author's development machine — Windows 11, RTX 5090 (Blackwell, sm_120), ample RAM/disk. `.wslconfig` pins 52 GB RAM and 20 CPU to WSL. Preflight floor is tight (40 GB RAM / 16 C / 100 GB free pass; 16 GB RAM / 8 C / 30 GB warn; below → fail). Because the topology is tuned to this machine, "works on my dev box" is explicitly the floor, not a generic minimum.

**Prior work:** An existing preflight checker at `prereqs.sh` (read-only, no-change, re-runnable bash) already covers WSL2 detection, Ubuntu 24.04 check, systemd, memory/CPU/disk floors, Docker daemon + group + Desktop-integration detection, WSL libcuda stub, nvidia-smi + RTX 5090 + driver 570.x+ gate, nvidia-ctk + docker nvidia runtime, port 6443–6445 / 8080–8082 occupancy, and existing k3d container / `k8s-net` residue. This script is the canonical starting point for `scripts/preflight.sh` (not a rewrite from scratch).

**Repo visibility:** Public from day one. This shifts the secrets model: no real tokens, kubeconfigs, or certs may land in git. GITHUB_OWNER / GITHUB_REPO / GITHUB_TOKEN (and any other user-substituted values) live in a gitignored `.env` populated locally; a committed `.env.example` documents the contract. `flux bootstrap github` writes its PAT to an in-cluster Secret only; `flux-system/` manifests are fine to commit but the PAT must not be.

**Pinned versions (research should re-verify currency in 2025):**
- k3s: `rancher/k3s:v1.34.6-k3s1`
- CUDA base: 12.8+ (required for RTX 5090 / sm_120)
- GPU smoke-test image: `nvcr.io/nvidia/cuda:12.8.0-base-ubuntu22.04` — verifies `nvidia-smi` only, no framework workload
- Tool versions: pinned in `.tool-versions` via asdf

**Key behavioral notes discovered up-front:**
- k3d CoreDNS caches Docker NodeHosts entries that can go stale after a Docker or WSL restart; stop/start of the hub cluster refreshes them (→ `task fix-dns`)
- `flux bootstrap` is idempotent but is reconciliation-based — any hand-edit under `clusters/hub-flux/flux-system/` will be reverted by the next reconcile, so that directory is documented as "bootstrap-managed, do not hand-edit"
- asdf shims must take PATH precedence over any system-wide kubectl/helm/k3d already on the dev machine
- WSL2 `networkingMode=mirrored` has historical edge cases with Docker custom networks; NAT-mode fallback must be documented

## Constraints

- **Tech stack:** Windows 11 host, single WSL2 Ubuntu 24.04 distro, Docker Engine native in WSL (no Docker Desktop integration) — ADR-001, ADR-002
- **Cluster runtime:** k3d + k3s, not Kind — reason: official GPU support, lower idle RAM, explicit `--network` control (ADR-002)
- **GitOps:** Flux over ArgoCD — reason: simpler bootstrap + CRD set for lab scope; known trade-off: no clean equivalent of ArgoCD ApplicationSet cluster generators with label-based targeting, so 2–3 spokes authored as explicit Kustomizations (ADR-003)
- **Control plane topology:** Hub-only Flux in v1; hub reconciles to spokes via `spec.kubeConfig` + remote kubeconfig Secrets — no Flux controllers run on spokes (ADR-004)
- **Version pinning:** k3s pinned to `v1.34.6-k3s1`; CUDA base pinned to 12.8+ — both pinning decisions justified in ADR-005
- **Tool installation:** asdf-managed only, with shim precedence over system binaries
- **Performance:** `task rebuild` must complete < 20 minutes with CUDA image cache warm; `task destroy` must NOT prune docker build cache
- **Security:** Repo is public; no real secrets in git; all substitution via gitignored `.env` + committed `.env.example`
- **GPU target:** RTX 5090 (Blackwell, sm_120) — most PyTorch stable releases still need nightlies; smoke-test deliberately scoped to `nvidia-smi` only to avoid coupling the lab to PyTorch nightly availability
- **Process:** Spec before code — PROJECT.md, REQUIREMENTS.md, ROADMAP.md approved before any scripts or manifests are written; each phase ends with a verifiable artifact

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Single WSL2 Ubuntu 24.04 distro for all clusters | All WSL2 distros share one host VM — per-distro isolation is illusory (→ ADR-001) | — Pending |
| Docker Engine installed natively in WSL (not Docker Desktop) | Avoids extra WSL distros consuming shared memory (→ ADR-001) | — Pending |
| k3d over Kind | Official GPU support, lower idle RAM, explicit `--network` control (→ ADR-002) | — Pending |
| Flux over ArgoCD | Simpler for lab scope; trade-off: no clean ApplicationSet cluster-generator equivalent; acceptable for 2–3 spokes (→ ADR-003) | — Pending |
| Hub-only Flux control plane (v1) | Reduces controller footprint on spokes; hub uses `spec.kubeConfig` + kubeconfig Secrets to reconcile into spokes (→ ADR-004) | — Pending |
| Pin k3s to `rancher/k3s:v1.34.6-k3s1`; pin CUDA base to 12.8+ | Flux-compatible current line; CUDA 12.8 is floor for RTX 5090 sm_120 (→ ADR-005) | — Pending |
| Tool versions via asdf + `.tool-versions` | Reproducible versions; shim precedence avoids collisions with system binaries | — Pending |
| Public repo with gitignored `.env` + `.env.example` template | Shareable by design; zero real secrets in git; explicit contract for substitution | — Pending |
| GPU smoke-test limited to `nvidia-smi` inside a pod | Avoids coupling lab health to PyTorch nightly availability for sm_120 | — Pending |
| Port existing `prereqs.sh` as `scripts/preflight.sh` | Existing script already covers the full checklist; starting from scratch would be wasted effort | — Pending |
| Pin nvidia-device-plugin to v0.17.4 (overrides REQUIREMENTS.md v0.19.0+) | No stable v0.19.x release compatible with RTX 5090 / Blackwell / sm_120 at Phase 2 research time — phase-scoped D-15 override | — Validated in Phase 2 |
| `scripts/delete-clusters.sh` must never invoke `docker (system\|builder\|image\|volume) prune` | BuildKit CUDA cache must survive teardown so Phase 5 `task rebuild` SLO (< 20 min) is achievable; literal `INTENTIONALLY NOT calling` comment is the Phase 6 DESTROY-04 lint's grep target | — Validated in Phase 2 (D-14) |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-04-24 after Phase 2 (cluster-layer) completion*
