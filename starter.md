I want to build a reproducible local multi-cluster Kubernetes lab on Windows 11 + WSL2 + k3d, using Flux for GitOps.

PROJECT NAME: karyon

PRIMARY GOAL:
A source-controlled, spec-driven lab that rebuilds a local multi-cluster Kubernetes environment from scratch via Taskfile-driven scripts. Supports Flux hub-spoke GitOps, an optional GPU-enabled ML spoke, and end-to-end scorched-earth rebuild in under 20 minutes.

ARCHITECTURAL DECISIONS ALREADY MADE (record each as an ADR in docs/adr/):
1. Single WSL2 Ubuntu 24.04 instance (not one per cluster). Reason: all WSL2 distros share a VM; per-instance isolation is illusory.
2. Docker Engine installed directly in WSL2 (not Docker Desktop). Reason: avoids extra WSL distros consuming shared memory.
3. All k3d clusters on a shared Docker network named k8s-net.
4. k3d over Kind. Reasons: official GPU support, lower idle RAM, explicit --network control.
5. Flux over ArgoCD. Trade-off noted: ApplicationSet cluster generators with label-based targeting have no clean Flux equivalent; for 2-3 spokes we author Kustomizations explicitly.
6. Hub-only Flux control plane in v1 (no Flux on spokes). The hub reconciles into spokes via `.spec.kubeConfig` and remote kubeconfig Secrets.
7. Kubernetes/k3s pinned to a Flux-compatible current line: `rancher/k3s:v1.34.6-k3s1`. CUDA base pinned to 12.8+ for RTX 5090 (sm_120).
8. Tool versions pinned via asdf with a checked-in `.tool-versions` file.

TOPOLOGY:
- hub-flux: management cluster running Flux controllers (API port 6443).
- spoke-ml: GPU-capable workload cluster, API port 6444, uses custom k3s+CUDA image.
- spoke-apps: general application workload cluster, API port 6445.

OUT OF SCOPE FOR V1:
- Production hardening.
- Cloud clusters.
- Real secret management beyond placeholder structure.
- Full ML workload implementation.
- GPU Operator (prefer the NVIDIA device plugin path first).
- ArgoCD.

DESIRED REPO STRUCTURE (subject to spec review):
karyon/
  README.md
  Taskfile.yml
  .tool-versions
  .gitignore
  docs/
    adr/
      0001-single-wsl2-shared-docker-network.md
      0002-k3d-over-kind.md
      0003-flux-over-argocd.md
      0004-hub-only-flux-control-plane.md
      0005-kubernetes-version-pin.md
    architecture.md
    flux-hub-spoke.md
    gpu-notes.md
    rebuild-runbook.md
  config/
    wslconfig                   # template for Windows-side .wslconfig
    wsl.conf                    # template for per-distro wsl.conf
  scripts/
    preflight.sh                # read-only env check (port the existing preflight-check.sh)
    install-docker.sh
    install-nvidia-container-toolkit.sh
    install-tools.sh            # asdf-based
    create-clusters.sh
    delete-clusters.sh
    register-spokes-for-flux.sh
    bootstrap-flux.sh
    fix-coredns.sh              # stop/start hub to clear stale NodeHosts after restarts
    health-check.sh
  clusters/
    hub-flux/
      flux-system/              # bootstrap-managed; do NOT hand-edit
      spokes/                   # Kustomizations targeting remote kubeconfigs
    spoke-ml/
      apps/
      infrastructure/
    spoke-apps/
      apps/
      infrastructure/
  images/
    Dockerfile.k3s-cuda         # ARG K3S_TAG must track the pinned k3s line
    device-plugin-daemonset.yaml
  examples/
    podinfo/
    gpu-smoke-test/

IMPLEMENTATION STYLE:
- Spec before code. Nothing gets implemented until the spec and phase plan are approved.
- Small, testable phases. Each phase ends with a verifiable artifact.
- Scripts are idempotent and safe to rerun.
- Taskfile orchestrates; scripts hold logic.
- Destructive tasks explicitly named (`task destroy`, `task rebuild`) and require confirmation.
- Scripts fail fast with useful errors.
- Scripts preflight their own prerequisites.
- No hardcoded GitHub username. Use GITHUB_OWNER, GITHUB_REPO, GITHUB_TOKEN env vars.
- Repo is private by default.
- Use placeholder comments where user substitution is required.

FUNCTIONAL REQUIREMENTS:

`task preflight` — delegate to scripts/preflight.sh, which verifies:
  - WSL2, systemd, Ubuntu 24.04
  - Docker daemon, user in docker group, Desktop integration NOT active
  - Memory / CPU / disk against project floor
  - GPU chain (nvidia-smi, libcuda stub, nvidia-container-toolkit, docker nvidia runtime)
  - kubectl, helm, flux, k3d, task, jq, yq installed via asdf
  - Ports 6443-6445 and 8080-8082 free
  - No conflicting existing k3d clusters or `k8s-net` network

`task create-clusters` — idempotent cluster creation:
  - Creates Docker network `k8s-net` if missing
  - hub-flux on 6443, spoke-ml on 6444 (--gpus all), spoke-apps on 6445
  - Each with --tls-san for its `k3d-<name>-server-0` Docker DNS name
  - All pinned to `rancher/k3s:v1.34.6-k3s1`

`task bootstrap-flux` — Flux bootstrap on hub-flux:
  - Uses `flux bootstrap github` with path=`clusters/hub-flux`
  - Idempotent (safe to rerun)
  - Documents that anything under `clusters/hub-flux/flux-system/` is bootstrap-managed and must not be hand-edited

`task register-spokes`:
  - Creates ServiceAccount + cluster-admin ClusterRoleBinding on each spoke
  - Produces kubeconfig pointing at `https://k3d-<spoke>-server-0:6443`
  - Stores kubeconfig as `flux-system/<spoke>-kubeconfig` Secret on hub-flux (key: `value.yaml`)

`task deploy-examples` — sample app to spoke-apps, GPU smoke-test to spoke-ml.

`task fix-dns` — workaround for k3d CoreDNS stale `NodeHosts` after Docker/WSL restart: stop and start the hub cluster to refresh DNS entries.

`task health-check`:
  - All k3d clusters exist, all nodes Ready
  - Flux controllers Ready on hub-flux
  - Flux Kustomizations targeting spokes Ready
  - Docker DNS names for spoke API servers resolve from hub Flux pods

`task destroy`:
  - Confirms before destroying
  - Deletes all k3d clusters, then `k8s-net` network
  - Does NOT prune docker build cache (CUDA image must survive rebuilds for the <15-minute rebuild target)

`task rebuild` — full scorched-earth: destroy → create → bootstrap → register → deploy → health-check.

KNOWN RISKS / ITEMS TO ADDRESS IN SPEC:
- `networkingMode=mirrored` has historically had edge cases with Docker custom networks; spec should include a NAT-mode fallback procedure.
- Flux bootstrap is idempotent but reconciles against the committed state — any hand-edits under `clusters/hub-flux/flux-system/` will be reverted. Document this clearly.
- CUDA image build should be cached across `task destroy` runs to preserve the sub-15-minute rebuild target.
- RTX 5090 is Blackwell/sm_120. Most PyTorch stable releases still need nightlies; the GPU smoke-test should use `nvcr.io/nvidia/cuda:12.8.0-base-ubuntu22.04` and just verify `nvidia-smi` inside a pod, not a framework workload.
- kubectl/helm/k3d may already be installed globally on the dev machine; `install-tools.sh` must rely on asdf shims taking PATH precedence over system binaries.

ACCEPTANCE CRITERIA:
- A fresh clone reaches a working hub-spoke Flux lab using only documented commands.
- `task rebuild` completes in under 20 minutes with CUDA image cached.
- Flux on hub-flux successfully applies Kustomizations into spoke-apps and spoke-ml.
- GPU smoke-test pod reports `nvidia-smi` output on spoke-ml.
- All five ADRs written and committed.
- No ArgoCD references anywhere except a short migration note in ADR-003.
- README covers: Windows prereqs, WSL config, Docker install, NVIDIA setup, cluster creation, Flux bootstrap, spoke registration, teardown.

FIRST DELIVERABLE (before any code):
A written spec containing:
1. Assumptions and constraints
2. Risk register (include the Known Risks above plus anything else discovered)
3. Phased roadmap with acceptance criteria per phase
4. Verification strategy per phase
5. ADR stubs for the five decisions above

Please begin with the spec. Do not write scripts or manifests until the spec is approved.