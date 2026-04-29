# karyon

A reproducible local Kubernetes lab — three k3d clusters (Flux hub + GPU
spoke + apps spoke) on Windows 11 + WSL2 — that you can rebuild from zero
in under 20 minutes.

## TL;DR

`task rebuild` performs a scorched-earth tear-down and reaches a healthy
hub-spoke Flux GitOps environment with a CUDA-capable spoke in under 20
minutes, every time. On a warm CUDA image cache, the chain (destroy →
create-clusters → bootstrap-flux → register-spokes → deploy-examples →
health-check) ran in 190 seconds end-to-end on the author's dev box.

If `task rebuild` is green, every layer of the lab is green. That is the
contract this project ships with.

***

## Quick Start (Fresh Clone)

These ten steps walk a clean Windows 11 + WSL2 dev box to a running lab.
Each step has a corresponding [Per-Task Reference](#per-task-reference)
section below with details and recovery procedures.

> **Hardware floor:** RTX 5090 (Blackwell, sm_120) + 16+ cores + 40+ GB RAM
> + 100+ GB free disk. The dev box was tuned to 20 cores / 52 GB / ample
> NVMe; downscale at your own risk and re-time `task rebuild` accordingly.

### 1. Windows prereqs

Install WSL2 + an Ubuntu 24.04 distro. The `config/wslconfig` template at
the repo root pins `52 GB RAM / 20 CPU` for WSL — copy it (or merge with
your existing `%USERPROFILE%\.wslconfig`) and run `wsl --shutdown` for the
limits to take effect. NVIDIA driver 570.x or newer is required on the
Windows side for the RTX 5090 + sm_120 floor (see [`docs/gpu-notes.md`](docs/gpu-notes.md)).

### 2. WSL config

Inside the Ubuntu distro, copy `config/wsl.conf` to `/etc/wsl.conf` (the
template enables `systemd=true`). Re-shutdown WSL once. Confirm:

```bash
systemctl is-system-running   # expected: running (or degraded; not "offline")
```

WSL2 networking modes are documented in [`docs/wsl-networking.md`](docs/wsl-networking.md);
v1 requires NAT mode. Mirrored mode + Docker custom networks have unresolved
upstream issues.

### 3. Docker install

Run the Docker Engine installer (NOT Docker Desktop integration — see
[`docs/adr/0001-single-wsl2-shared-docker-network.md`](docs/adr/0001-single-wsl2-shared-docker-network.md)):

```bash
bash scripts/install-docker.sh
```

This sets `default-runtime: nvidia` and an explicit `dns` array in
`/etc/docker/daemon.json` (HOST-04 — required for the 3-part k3d GPU
contract).

### 4. NVIDIA setup

Install the NVIDIA Container Toolkit:

```bash
bash scripts/install-nvidia-container-toolkit.sh
```

Confirm GPU pass-through:

```bash
docker run --rm --gpus all nvcr.io/nvidia/cuda:12.8.0-base-ubuntu22.04 nvidia-smi
# Expected: NVIDIA-SMI output naming an RTX 5090 device.
```

### 5. tools install

Install asdf and the pinned toolchain (`.tool-versions` carries the line:
`kubectl 1.35.0`, `helm 3.20.2`, `flux2 2.8.6`, `k3d 5.8.3`, `task 3.50.0`,
plus `gitleaks 8.30.1` for the pre-commit hook):

```bash
bash scripts/install-tools.sh
source ~/.bashrc            # picks up the new asdf shim path
```

This step also wires the local git pre-commit hook (REPO-04) by setting
`git config --local core.hooksPath hooks` — see
[Repo Hygiene & CI](#repo-hygiene--ci) below.

Verify with `task preflight` (read-only, idempotent):

```bash
task preflight              # expected: exits 0 with all green checks
```

### 6. cluster creation

Build the custom k3s+CUDA image (cached across rebuilds), then create the
three clusters on the shared `k8s-net` Docker bridge:

```bash
cp .env.example .env        # populate GITHUB_OWNER, GITHUB_REPO, GITHUB_TOKEN
task build-image
task create-clusters
```

`hub-flux` lands on API port 6443, `spoke-ml` on 6444 (`--gpus all`),
`spoke-apps` on 6445. Topology is rendered in [`docs/architecture.md`](docs/architecture.md).

### 7. Flux bootstrap

Bootstrap Flux GitOps on `hub-flux`:

```bash
task bootstrap-flux
```

This runs `flux bootstrap github --path clusters/hub-flux` (the path is
hard-coded — see [`docs/flux-hub-spoke.md`](docs/flux-hub-spoke.md) for the
patch-surface contract).

### 8. spoke registration

Register the two spokes for hub-only Flux reconciliation:

```bash
task register-spokes
```

Provisions a `flux-reconciler` ServiceAccount + cluster-admin
ClusterRoleBinding on each spoke, embeds the kubeconfig (server + CA + token)
into a `flux-system/<spoke>-kubeconfig` Secret on the hub under key
`value.yaml`, and authors hub-side `Kustomization` resources with explicit
`spec.kubeConfig.secretRef`. Rationale: [`docs/adr/0004-hub-only-flux-control-plane.md`](docs/adr/0004-hub-only-flux-control-plane.md).

### 9. example deploy

Deploy podinfo and a GPU smoke-test:

```bash
task deploy-examples
task health-check
```

Manifests live under `examples/podinfo/` and `examples/gpu-smoke-test/`;
they reconcile through Flux into their target spokes. `task health-check`
verifies clusters, controllers, Kustomizations, in-hub DNS, GPU capacity,
TLS SANs, and the workload proofs.

### 10. teardown

Either remove just the clusters (preserves the CUDA image cache for the
next `task rebuild`):

```bash
task destroy                # type "yes" to confirm
```

…or do the full destructive rebuild loop (preserves the CUDA cache, then
exercises the entire chain end-to-end):

```bash
task rebuild                # type "yes" to confirm
```

***

## Per-Task Reference

Each task is a thin wrapper around a script under `scripts/`. All logic
lives in the scripts; `Taskfile.yml` is the orchestration surface.

| Task | Script | What it does | REQ-IDs |
|------|--------|--------------|---------|
| `preflight` | `scripts/preflight.sh` | Read-only environment check; idempotent; exits 0 / 1 | PRE-01..14 |
| `build-image` | `scripts/build-image.sh` | Build the custom k3s+CUDA image (Ubuntu 22.04 + k3s + nvidia-device-plugin) | IMG-01..06 |
| `create-clusters` | `scripts/create-clusters.sh` | Idempotently create `k8s-net` + three k3d clusters | CLU-01..05 |
| `delete-clusters` | `scripts/delete-clusters.sh` | Remove clusters + `k8s-net`, preserve `karyon/k3s-cuda` image | CLU-06, IMG-06 |
| `bootstrap-flux` | `scripts/bootstrap-flux.sh` | Bootstrap Flux GitOps on `hub-flux` | FLUX-01..05 |
| `register-spokes` | `scripts/register-spokes-for-flux.sh` | Provision spoke kubeconfig Secrets + hub-side Kustomizations | SPOKE-01..06 |
| `deploy-examples` | `scripts/deploy-examples.sh` | Reconcile podinfo (apps) + GPU smoke-test (ml) | DEP-01..04 |
| `fix-dns` | `scripts/fix-coredns.sh` | Stop/start `hub-flux` to refresh stale CoreDNS NodeHosts | HEALTH-07 |
| `health-check` | `scripts/health-check.sh` | Verify clusters, Flux, spokes, DNS, GPU capacity, TLS SANs | HEALTH-01..06 |
| `destroy` | `scripts/destroy.sh` | Confirm + remove clusters + `k8s-net`; CUDA cache preserved | DESTROY-01..04 |
| `rebuild` | `scripts/rebuild.sh` | Full destroy → create → bootstrap → register → deploy → health-check; < 20 min SLO | DESTROY-05..06 |

`task --list` shows all tasks; `task --dry <name>` previews the script
invocation without running it.

***

## Why These Choices

Architectural decisions are recorded in [`docs/adr/`](docs/adr/):

- **Single-WSL2 + shared Docker network** — [`adr/0001-single-wsl2-shared-docker-network.md`](docs/adr/0001-single-wsl2-shared-docker-network.md)
- **k3d over Kind** — [`adr/0002-k3d-over-kind.md`](docs/adr/0002-k3d-over-kind.md)
- **Flux over ArgoCD (with ApplicationSet trade-off)** — [`adr/0003-flux-over-argocd.md`](docs/adr/0003-flux-over-argocd.md)
- **Hub-only Flux control plane** — [`adr/0004-hub-only-flux-control-plane.md`](docs/adr/0004-hub-only-flux-control-plane.md)
- **k3s `v1.34.6-k3s1` + CUDA 12.8+ pins** — [`adr/0005-kubernetes-version-pin.md`](docs/adr/0005-kubernetes-version-pin.md)

For deeper reference:

- Topology diagram: [`docs/architecture.md`](docs/architecture.md)
- 3-part k3d GPU contract + Blackwell floor: [`docs/gpu-notes.md`](docs/gpu-notes.md)
- Flux patch-surface contract: [`docs/flux-hub-spoke.md`](docs/flux-hub-spoke.md)
- WSL2 networking modes (mirrored vs NAT): [`docs/wsl-networking.md`](docs/wsl-networking.md)
- Rebuild procedure + timings + failure-mode appendix: [`docs/rebuild-runbook.md`](docs/rebuild-runbook.md)

***

## Repo Hygiene & CI

This is a public-safe repository. No real tokens, kubeconfigs, CA keys, or
client certs are committed. The substitution contract is the gitignored
`.env` populated locally from the committed `.env.example` template.

A `gitleaks` pre-commit hook (configured by
`bash scripts/install-tools.sh`, wired through `git config --local
core.hooksPath hooks`) blocks commits that would leak secrets. A GitHub
Actions workflow ([`.github/workflows/ci.yml`](.github/workflows/ci.yml))
runs the same gitleaks scan plus shellcheck, kubeconform, markdownlint, and
the existing prune-lint bats test on every push and pull-request.

### One-time branch-protection setup

After CI runs green at least once on `main`, configure branch protection:

1. GitHub repo → Settings → Branches → Add branch protection rule
2. Branch name pattern: `main`
3. Require status checks to pass before merging
4. Require branches to be up to date before merging
5. Status checks required: `shellcheck`, `markdownlint`, `kubeconform`,
   `prune-lint-bats`, `gitleaks-scan`
6. Do not allow bypassing the above settings (recommended)

***

## Project Surface

- `scripts/` — bash automation (idempotent, fail-fast, source `lib/preflight-lib.sh` for shared helpers)
- `images/` — `Dockerfile.k3s-cuda` + `config.toml.tmpl` + the `nvidia-device-plugin` manifest
- `clusters/hub-flux/` — Flux bootstrap manifests + spoke `Kustomization` resources
- `clusters/spoke-{ml,apps}/` — per-spoke Kustomize trees (namespace, configmap, etc.)
- `examples/` — workload manifests reconciled into spokes (podinfo, gpu-smoke-test)
- `docs/` — reference docs (this README + the files cross-linked above) and ADRs
- `tests/bats/` — bats-core static and live tests; live tests gated by `KARYON_LIVE_TESTS=1`
- `Taskfile.yml` — the single orchestration surface; runs scripts, never inline logic
- `hooks/` — git hooks (currently `pre-commit` for gitleaks; wired via `core.hooksPath`)
- `.planning/` — the GSD v1 planning state (intentionally tracked; NOT a build artifact)

***

## License

(TODO: add a LICENSE file when the project ships v1.)
