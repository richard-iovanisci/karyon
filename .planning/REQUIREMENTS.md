# Requirements: karyon

**Defined:** 2026-04-22
**Core Value:** `task rebuild` performs a scorched-earth teardown and reaches a healthy hub-spoke Flux lab — with a CUDA-capable spoke — in under 20 minutes, every time.

## v1 Requirements

Requirements for initial release. Each maps to one roadmap phase (populated in the Traceability section by the roadmapper).

### Host Foundation

- [ ] **HOST-01**: A `config/wslconfig` template for Windows-side `.wslconfig` exists with a documented NAT-mode fallback section for mirrored-mode edge cases
- [ ] **HOST-02**: A `config/wsl.conf` template for the distro enables `systemd=true` and documents required settings
- [ ] **HOST-03**: `scripts/install-docker.sh` installs Docker Engine natively in WSL Ubuntu 24.04, adds the invoking user to the `docker` group, and is idempotent
- [ ] **HOST-04**: `/etc/docker/daemon.json` sets `default-runtime: nvidia` and explicit `dns` keys so `systemd-resolved`'s `127.0.0.53` does not propagate into containers
- [ ] **HOST-05**: `scripts/install-nvidia-container-toolkit.sh` installs `nvidia-ctk`, runs `nvidia-ctk runtime configure --runtime=docker`, and is idempotent
- [ ] **HOST-06**: A systemd unit (or equivalent boot hook) runs `hwclock -s` on resume to correct WSL2 post-hibernate clock drift
- [ ] **HOST-07**: `docs/wsl-networking.md` documents the mirrored → NAT fallback procedure with the exact `.wslconfig` delta

### Tool Pinning & Install

- [ ] **TOOLS-01**: A checked-in `.tool-versions` file pins `kubectl`, `helm` (3.x line), `flux`, `k3d` (v5.8.3 or newer, never v5.8.0), `task`, `jq`, `yq` (mikefarah Go yq), `k9s`, `asdf` (v0.18+ / Go rewrite line)
- [ ] **TOOLS-02**: `scripts/install-tools.sh` installs asdf plugins and pinned versions idempotently
- [ ] **TOOLS-03**: Tool install step (or documented shell-init snippet) guarantees the asdf shim directory precedes `/usr/bin` and `/usr/local/bin` in `PATH`

### Preflight Gate

- [ ] **PRE-01**: `scripts/preflight.sh` exists, ported from the existing `prereqs.sh`, is read-only/idempotent, and exits `0` on pass / `1` on any blocker
- [ ] **PRE-02**: Preflight verifies WSL2 kernel, Ubuntu 24.04 distro ID, and active systemd
- [ ] **PRE-03**: Preflight enforces the dev-box resource floor (fail below 8 cores / 16 GB RAM / 30 GB free; warn below 16 cores / 40 GB / 100 GB; target 20 cores / 52 GB)
- [ ] **PRE-04**: Preflight verifies the full GPU chain: WSL `libcuda.so.1` stub, `nvidia-smi` working, Linux-bridge driver version ≥ 570.x, `nvidia-ctk` installed, Docker `nvidia` runtime registered
- [ ] **PRE-05**: Preflight verifies all required tools are installed and versions match the `.tool-versions` pins
- [ ] **PRE-06**: Preflight verifies ports 6443–6445 and 8080–8082 are free
- [ ] **PRE-07**: Preflight detects existing `k3d-*` containers and an existing `k8s-net` Docker network and warns
- [ ] **PRE-08**: Preflight detects Docker Desktop WSL integration on this distro and fails with a clear remediation message
- [ ] **PRE-09**: Preflight validates that `.env` exists and contains `GITHUB_OWNER`, `GITHUB_REPO`, `GITHUB_TOKEN`, failing fast with a helpful message when absent
- [ ] **PRE-10**: Preflight FAILS (not warns) when `kubectl`/`helm`/`k3d` resolve to a system binary outside the asdf shim directory
- [ ] **PRE-11**: Preflight probes `/etc/resolv.conf` for `systemd-resolved`'s `127.0.0.53` stub and fails with the `daemon.json` `dns` fix when detected
- [ ] **PRE-12**: Preflight probes host↔WSL clock skew and fails when delta > 30 seconds
- [ ] **PRE-13**: Preflight verifies cgroup v2 purity (no cgroupv1 controllers mounted)
- [ ] **PRE-14**: Preflight runs a mirrored-mode bridge-curl probe (container on `k8s-net` curls its peer by Docker DNS name) and fails if the probe fails — catches mirrored-mode + custom-network breakage early

### CUDA Image

- [ ] **IMG-01**: `images/Dockerfile.k3s-cuda` uses `FROM nvidia/cuda:12.8.1-base-ubuntu22.04` for the final stage, with k3s binaries layered in from `rancher/k3s:v1.34.6-k3s1` as a build stage
- [ ] **IMG-02**: Dockerfile exposes an `ARG K3S_TAG` that tracks the pinned k3s line and defaults to `v1.34.6-k3s1`
- [ ] **IMG-03**: Image includes a custom `config.toml.tmpl` setting `default_runtime_name = "nvidia"` (third leg of the 3-part k3d GPU contract)
- [ ] **IMG-04**: A NVIDIA device-plugin manifest (Helm chart `nvidia-device-plugin` v0.19.0+, delivered via Flux HelmRelease on spoke-ml, is the preferred path per research)
- [ ] **IMG-05**: The device-plugin manifest is also baked into the custom image at `/var/lib/rancher/k3s/server/manifests/` so `nvidia.com/gpu` capacity is available from t=0
- [ ] **IMG-06**: The image build is cached across `task destroy` — `task destroy` must not prune Docker build cache

### Cluster Layer

- [ ] **CLU-01**: `scripts/create-clusters.sh` idempotently creates the `k8s-net` Docker network if missing
- [ ] **CLU-02**: Creates `hub-flux` cluster on API port 6443 using `rancher/k3s:v1.34.6-k3s1`, attached to `k8s-net`
- [ ] **CLU-03**: Creates `spoke-ml` cluster on API port 6444 with `--gpus all`, using the custom k3s+CUDA image, attached to `k8s-net`
- [ ] **CLU-04**: Creates `spoke-apps` cluster on API port 6445 using `rancher/k3s:v1.34.6-k3s1`, attached to `k8s-net`
- [ ] **CLU-05**: Each cluster passes its TLS SAN via `--k3s-arg '--tls-san=k3d-<name>-server-0@server:*'` (NOT as a top-level `--tls-san` flag — this is not a k3d flag)
- [ ] **CLU-06**: `scripts/delete-clusters.sh` removes all three clusters and the `k8s-net` network without pruning Docker build cache

### Flux Hub Bootstrap

- [ ] **FLUX-01**: `scripts/bootstrap-flux.sh` runs `flux bootstrap github` targeting the `hub-flux` cluster
- [ ] **FLUX-02**: The `--path` argument is hard-coded to `clusters/hub-flux` (effectively immutable after first run per Flux design)
- [ ] **FLUX-03**: `GITHUB_OWNER`, `GITHUB_REPO`, `GITHUB_TOKEN` are read from the gitignored `.env` file; the script never echoes the token value
- [ ] **FLUX-04**: Bootstrap is idempotent — rerunning after a successful first run leaves the cluster in the same state
- [ ] **FLUX-05**: `docs/flux-hub-spoke.md` documents that `clusters/hub-flux/flux-system/gotk-components.yaml` and `gotk-sync.yaml` are bootstrap-managed, but `kustomization.yaml` IS the supported patch surface (corrects the starter's overly-broad "do not hand-edit" guidance)

### Spoke Registration

- [ ] **SPOKE-01**: `scripts/register-spokes-for-flux.sh` creates a `ServiceAccount` plus cluster-admin `ClusterRoleBinding` on each spoke
- [ ] **SPOKE-02**: For each spoke SA, creates an explicit legacy Secret of type `kubernetes.io/service-account-token` annotated with the SA name (indefinite lifetime is acceptable for lab scope)
- [ ] **SPOKE-03**: Generates a kubeconfig per spoke with `server: https://k3d-<spoke>-server-0:6443` (Docker-embedded-DNS hostname reachable from hub pods on `k8s-net`)
- [ ] **SPOKE-04**: Stores each kubeconfig as a `flux-system/<spoke>-kubeconfig` Secret on `hub-flux` under the key `value.yaml` (confirmed correct key name per Flux `kustomize-controller` v1 spec)
- [ ] **SPOKE-05**: Authors a hub-side Flux `Kustomization` per spoke under `clusters/hub-flux/spokes/` with `spec.kubeConfig.secretRef` pointing to the kubeconfig Secret and `spec.path` pointing to the spoke's tree
- [ ] **SPOKE-06**: Each spoke kubeconfig embeds CA-data from the spoke's apiserver cert so TLS validation succeeds against the `--tls-san`

### Example Workloads

- [ ] **DEP-01**: `scripts/deploy-examples.sh` (or `task deploy-examples`) ensures a hub-flux `Kustomization` deploys `podinfo` to `spoke-apps`
- [ ] **DEP-02**: A hub-flux `Kustomization` deploys a GPU smoke-test pod to `spoke-ml`
- [ ] **DEP-03**: The GPU smoke-test uses `nvcr.io/nvidia/cuda:12.8.0-base-ubuntu22.04` and runs only `nvidia-smi` — no PyTorch / framework workload (avoids coupling the lab to sm_120 nightly availability)
- [ ] **DEP-04**: Example manifests live under `examples/podinfo/` and `examples/gpu-smoke-test/` and are version-controlled

### Health Check & DNS Fix

- [ ] **HEALTH-01**: `scripts/health-check.sh` verifies all three k3d clusters exist and all nodes are `Ready`
- [ ] **HEALTH-02**: Verifies Flux controllers are Ready on `hub-flux` and runs `flux check` as an explicit sanity step
- [ ] **HEALTH-03**: Verifies every Flux `Kustomization` targeting a spoke is `Ready=True`
- [ ] **HEALTH-04**: Executes an in-hub-pod DNS probe (`nslookup k3d-spoke-ml-server-0` / `k3d-spoke-apps-server-0`) to catch stale CoreDNS `NodeHosts` before they manifest as reconcile failures
- [ ] **HEALTH-05**: Verifies `spoke-ml` reports `nvidia.com/gpu` capacity > 0 (catches 3-part k3d GPU contract breakage)
- [ ] **HEALTH-06**: Verifies each spoke apiserver's TLS cert includes the expected `k3d-<spoke>-server-0` SAN (openssl s_client probe)
- [ ] **HEALTH-07**: `scripts/fix-coredns.sh` stops and starts `hub-flux` to refresh stale CoreDNS `NodeHosts` after Docker/WSL restart (documented workaround; no upstream fix shipped)

### Teardown & Rebuild

- [ ] **DESTROY-01**: `task destroy` requires explicit confirmation (typed `yes` or equivalent) before proceeding
- [ ] **DESTROY-02**: Destroy deletes all three k3d clusters, then removes the `k8s-net` Docker network
- [ ] **DESTROY-03**: Destroy does not run `docker system prune` or `docker builder prune` — CUDA build layers must survive for the `task rebuild` SLO
- [ ] **DESTROY-04**: A lint step (runnable in CI) rejects any script in `scripts/` that references `docker system prune` or `docker builder prune`
- [ ] **DESTROY-05**: `task rebuild` chains `destroy → create-clusters → bootstrap-flux → register-spokes → deploy-examples → health-check`
- [ ] **DESTROY-06**: `task rebuild` completes in under 20 minutes on the target dev box with a warm CUDA image cache, ending in a green health-check

### Repo Hygiene & Secrets

- [ ] **REPO-01**: Repo is public-safe — no real tokens, kubeconfigs, CA keys, or client certs committed
- [ ] **REPO-02**: `.gitignore` excludes `.env` and any other secret-bearing paths (`.planning/` is intentionally tracked and must not be re-ignored)
- [ ] **REPO-03**: `.env.example` is checked in, documents every required key with placeholder values and a one-line description
- [ ] **REPO-04**: A pre-commit hook (gitleaks or detect-secrets) runs on `git commit` and blocks commits that would leak secrets
- [ ] **REPO-05**: `Taskfile.yml` is the single orchestration surface; all logic lives in `scripts/` (Taskfile invokes scripts, not the reverse)
- [ ] **REPO-06**: Destructive tasks (`destroy`, `rebuild`) are named explicitly in `Taskfile.yml` so they cannot be invoked accidentally by tab-completion on a benign verb
- [ ] **REPO-07**: A GitHub Actions workflow runs shellcheck on `scripts/`, kubeconform on YAML under `clusters/`/`examples/`, and markdownlint on docs — on every push and PR

### Documentation

- [ ] **DOCS-01**: `README.md` covers, in this order: Windows prereqs → WSL config → Docker install → NVIDIA setup → tools install → cluster creation → Flux bootstrap → spoke registration → example deploy → teardown
- [ ] **DOCS-02**: `docs/architecture.md` contains a Mermaid diagram of the hub-spoke topology (rendered natively by GitHub)
- [ ] **DOCS-03**: `docs/flux-hub-spoke.md` explains the hub-only reconciliation model, the `kustomization.yaml`-is-editable rule, and the `--path`-is-immutable contract
- [ ] **DOCS-04**: `docs/gpu-notes.md` explains the 3-part k3d GPU contract, the RTX 5090 / sm_120 requirement, and the CUDA 12.8+ floor
- [ ] **DOCS-05**: `docs/rebuild-runbook.md` is a step-by-step scorched-earth procedure including expected timings and common failure modes
- [ ] **DOCS-06**: `docs/adr/0001-single-wsl2-shared-docker-network.md` captures the single-distro + `k8s-net` decision
- [ ] **DOCS-07**: `docs/adr/0002-k3d-over-kind.md` captures the k3d-over-Kind decision with rationale
- [ ] **DOCS-08**: `docs/adr/0003-flux-over-argocd.md` captures the Flux-over-ArgoCD decision and the ApplicationSet-equivalent trade-off, with a migration note
- [ ] **DOCS-09**: `docs/adr/0004-hub-only-flux-control-plane.md` captures the hub-only Flux decision
- [ ] **DOCS-10**: `docs/adr/0005-kubernetes-version-pin.md` captures the k3s `v1.34.6-k3s1` + CUDA 12.8+ pin decisions

## v2 Requirements

Deferred to future milestones. Tracked but not in the current roadmap.

### Secret Management

- **SECRETS-01**: Adopt SOPS + age for secret encryption when real secret material enters the repo (beyond Flux bootstrap PAT)
- **SECRETS-02**: Document the age-key lifecycle (generation, backup, rotation) in `docs/secrets.md`

### Networking

- **NET-01**: Support WSL2 `networkingMode=mirrored` as a first-class mode (not just NAT-fallback documented) once Microsoft ships the fixes for `moby/moby#48201` and friends

### Observability

- **OBS-01**: Optional `kube-prometheus-stack` HelmRelease behind a feature flag (incompatible with the < 20 min rebuild SLO unless the image is pre-pulled)

### K8s Version Maintenance

- **KUBE-01**: Policy for bumping the k3s pinned line (trigger, testing steps, migration notes) — starts becoming relevant when v1.34 approaches EOL

### Tooling

- **TOOL-01**: Migrate to Helm 4.x when the ecosystem consolidates (not before end-of-security-support for Helm 3, ~Nov 2026)
- **TOOL-02**: Migrate legacy NVIDIA runtime path to CDI (Container Device Interface) when the ecosystem consolidates

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Production hardening (HA, hardened RBAC, baseline NetworkPolicies) | Lab-only; not an SRE platform |
| Cloud clusters (EKS/GKE/AKS) | Local-only by design; keeps cost + dependency surface predictable |
| Real secret management beyond placeholder `.env` + gitignore | Flagger-grade secrets are a v2 concern (SECRETS-01) |
| Full ML framework workloads (PyTorch, JAX, TensorFlow) | Smoke-test verifies `nvidia-smi` only; avoids coupling to RTX 5090 / sm_120 nightly-wheel availability |
| NVIDIA GPU Operator | Device-plugin DaemonSet / HelmRelease path is simpler for this scope |
| ArgoCD | Flux-only; trade-off documented in ADR-003 |
| Per-cluster WSL2 distros | All WSL2 distros share one VM — per-distro isolation is illusory (ADR-001) |
| Non-Windows hosts (Linux-native, macOS) | Targets Windows 11 + WSL2 only in v1 |
| Flagger / progressive delivery | Cargo-cult for a single-user lab; no release cadence to automate |
| Image automation controllers | Same — no release cadence to automate |
| `kube-prometheus-stack` in v1 | Would break the < 20 min rebuild SLO unless image is pre-pulled (see OBS-01) |
| SealedSecrets, ExternalSecrets | SealedSecrets doesn't scale cleanly across spokes; ExternalSecrets needs a backing store not present in the lab |

## Traceability

Which phases cover which requirements. Populated during roadmap creation — currently all pending.

| Requirement | Phase | Status |
|-------------|-------|--------|
| HOST-01 | TBD | Pending |
| HOST-02 | TBD | Pending |
| HOST-03 | TBD | Pending |
| HOST-04 | TBD | Pending |
| HOST-05 | TBD | Pending |
| HOST-06 | TBD | Pending |
| HOST-07 | TBD | Pending |
| TOOLS-01 | TBD | Pending |
| TOOLS-02 | TBD | Pending |
| TOOLS-03 | TBD | Pending |
| PRE-01 | TBD | Pending |
| PRE-02 | TBD | Pending |
| PRE-03 | TBD | Pending |
| PRE-04 | TBD | Pending |
| PRE-05 | TBD | Pending |
| PRE-06 | TBD | Pending |
| PRE-07 | TBD | Pending |
| PRE-08 | TBD | Pending |
| PRE-09 | TBD | Pending |
| PRE-10 | TBD | Pending |
| PRE-11 | TBD | Pending |
| PRE-12 | TBD | Pending |
| PRE-13 | TBD | Pending |
| PRE-14 | TBD | Pending |
| IMG-01 | TBD | Pending |
| IMG-02 | TBD | Pending |
| IMG-03 | TBD | Pending |
| IMG-04 | TBD | Pending |
| IMG-05 | TBD | Pending |
| IMG-06 | TBD | Pending |
| CLU-01 | TBD | Pending |
| CLU-02 | TBD | Pending |
| CLU-03 | TBD | Pending |
| CLU-04 | TBD | Pending |
| CLU-05 | TBD | Pending |
| CLU-06 | TBD | Pending |
| FLUX-01 | TBD | Pending |
| FLUX-02 | TBD | Pending |
| FLUX-03 | TBD | Pending |
| FLUX-04 | TBD | Pending |
| FLUX-05 | TBD | Pending |
| SPOKE-01 | TBD | Pending |
| SPOKE-02 | TBD | Pending |
| SPOKE-03 | TBD | Pending |
| SPOKE-04 | TBD | Pending |
| SPOKE-05 | TBD | Pending |
| SPOKE-06 | TBD | Pending |
| DEP-01 | TBD | Pending |
| DEP-02 | TBD | Pending |
| DEP-03 | TBD | Pending |
| DEP-04 | TBD | Pending |
| HEALTH-01 | TBD | Pending |
| HEALTH-02 | TBD | Pending |
| HEALTH-03 | TBD | Pending |
| HEALTH-04 | TBD | Pending |
| HEALTH-05 | TBD | Pending |
| HEALTH-06 | TBD | Pending |
| HEALTH-07 | TBD | Pending |
| DESTROY-01 | TBD | Pending |
| DESTROY-02 | TBD | Pending |
| DESTROY-03 | TBD | Pending |
| DESTROY-04 | TBD | Pending |
| DESTROY-05 | TBD | Pending |
| DESTROY-06 | TBD | Pending |
| REPO-01 | TBD | Pending |
| REPO-02 | TBD | Pending |
| REPO-03 | TBD | Pending |
| REPO-04 | TBD | Pending |
| REPO-05 | TBD | Pending |
| REPO-06 | TBD | Pending |
| REPO-07 | TBD | Pending |
| DOCS-01 | TBD | Pending |
| DOCS-02 | TBD | Pending |
| DOCS-03 | TBD | Pending |
| DOCS-04 | TBD | Pending |
| DOCS-05 | TBD | Pending |
| DOCS-06 | TBD | Pending |
| DOCS-07 | TBD | Pending |
| DOCS-08 | TBD | Pending |
| DOCS-09 | TBD | Pending |
| DOCS-10 | TBD | Pending |

**Coverage:**
- v1 requirements: 73 total
- Mapped to phases: 0 (awaiting roadmap)
- Unmapped: 73 ⚠️ — will become 0 after `/gsd-plan-phase` or roadmap generation

---
*Requirements defined: 2026-04-22*
*Last updated: 2026-04-22 after initial definition*
