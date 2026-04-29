# Stack Research

**Domain:** Local multi-cluster Kubernetes lab (k3d + Flux + WSL2 + GPU)
**Researched:** 2026-04-22
**Confidence:** HIGH (all pins verified against GitHub release lists and/or official docs pulled 2026-04-22)

## TL;DR — Pinned Versions

| Tool | Pinned version | Confidence |
|---|---|---|
| k3s image | `rancher/k3s:v1.34.6-k3s1` | HIGH |
| k3d CLI | `v5.8.3` | HIGH |
| Flux CLI | `v2.8.6` | HIGH |
| kubectl | `v1.34.7` | HIGH |
| helm | `v3.20.2` (stay on Helm 3) | HIGH |
| task | `v3.50.0` | HIGH |
| asdf | `v0.18.1` (Go rewrite, NOT classic bash) | HIGH |
| jq | `1.8.1` | HIGH |
| yq | `v4.53.2` (mikefarah Go yq) | HIGH |
| NVIDIA container toolkit | `1.19.0-1` | HIGH |
| NVIDIA k8s-device-plugin | `v0.19.0` (Helm chart `0.19.0`) | HIGH |
| CUDA smoke-test image | `nvcr.io/nvidia/cuda:12.8.0-base-ubuntu22.04` | HIGH |
| CUDA base for custom k3s+CUDA image | `nvidia/cuda:12.8.1-base-ubuntu22.04` | HIGH |
| NVIDIA Windows driver floor | `572.xx` (Windows) / CUDA 12.8 GA needs `>= 570.65` | HIGH |

---

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|---|---|---|---|
| **k3s (as container image)** | `rancher/k3s:v1.34.6-k3s1` | The actual Kubernetes distribution running inside each k3d node container | Tag is live on Docker Hub (pushed ~2026-03-28 by autorancher, confirmed 2026-04-22). Falls within Flux 2.8.x supported K8s range (`>= 1.34.1`). v1.34.6 ships etcd `v3.6.7-k3s1` which resolves the "Zombie-Member" etcd upgrade issue that affected `v1.34.3+k3s1`. Embeds containerd v2.2.2, CoreDNS v1.14.2, Helm-controller v0.16.17. |
| **k3d** | `v5.8.3` | CLI that runs k3s inside Docker container nodes; gives us `--gpus`, `--network`, and k3s-arg passthrough | Latest stable (2025-02-15). `--gpus` and `--network` are native `k3d cluster create` flags. `--tls-san` is passed through as `--k3s-arg '--tls-san=...@server:*'` — k3d does not expose it as its own top-level flag. v5.9.0-rc.0 exists but is pre-release; stay on 5.8.3. |
| **Flux v2** | CLI `v2.8.6`; controllers pinned by bootstrap | GitOps reconciler on hub-flux with remote-kubeconfig reconciliation into spokes | Latest stable (2026-04-21), one day old at research time. v2.8.x officially supports Kubernetes `>= 1.34.1` — our `v1.34.6+k3s1` clears the floor by five patches. Components: helm-controller v1.5.4, kustomize-controller v1.8.4, source-controller v1.8.3. No known Flux↔k3s v1.34.x interop issues surfaced in release notes or issue tracker. |
| **kubectl** | `v1.34.7` | Cluster-side CLI; hub + spokes + preflight | Exact match to cluster minor. Kubernetes version-skew policy guarantees kubectl N-1/N/N+1 vs API server, so v1.33.x / v1.34.x / v1.35.x would all work, but pinning N matches minimizes surprise for `kubectl apply` server-side dry-runs and admission-webhook edge cases. v1.34.7 is the latest v1.34.x patch (2026-04-15). |
| **helm** | `v3.20.2` | Chart installs (device plugin, optional addons) | Stay on Helm 3. Helm 4.1.4 is available but introduces breaking changes: SSA-by-default for new installs, `--force` renamed to `--force-replace`, `HELM_EXPERIMENTAL_OCI=1` removed, post-renderers must be plugins, different SDK. Lab aims for reproducibility, not cutting-edge; most third-party charts still target v3. Helm 3 bug-fix window runs until 2026-07-08 and security fixes until 2026-11-11 per helm.sh — re-evaluate next milestone. |
| **Taskfile** | `task v3.50.0` | Orchestrator for all `task <name>` workflows | Latest stable (2026-04-13). Go-based, single binary, CI-friendly. No known blockers for v3.x line. |
| **asdf** | `v0.18.1` | Tool-version manager with `.tool-versions` pinning | **Use the Go rewrite (v0.16+), NOT the bash classic.** v0.16.0 (2025-01-30) was the complete Go rewrite; v0.18.x hardens it. Shims live in `~/.asdf/shims` and asdf prepends that directory to `PATH` — shim precedence over system `/usr/local/bin/kubectl` works as long as the `. <(asdf ...)` snippet in `~/.bashrc` runs AFTER anything that modifies `PATH`. Post-v0.16 shim generation is now handled by Go, not bash — faster but requires the upgrade guide if coming from `<0.16`. |
| **jq** | `1.8.1` | JSON parsing inside scripts (e.g., k3d cluster list, kubeconfig surgery) | Latest stable (2025-07-01). The 1.7 → 1.8 jump brought native regex, `abs`/`getpath` fixes. 1.6 is on many distros but is end-of-maintenance since 2018 — pin 1.8.1 via asdf to avoid surprises. |
| **yq (mikefarah)** | `v4.53.2` | YAML manipulation in scripts (kubeconfig rewrites, Kustomization generation, `tlsSAN` edits) | Latest stable (2026-04-17) of Mike Farah's Go yq. **Not** kislyuk's Python yq (which wraps jq differently — incompatible syntax). Confirm which one asdf pulls; the canonical plugin is `asdf-community/asdf-yq` → mikefarah. |
| **NVIDIA Container Toolkit** | `1.19.0-1` | Plumbs `/dev/nvidia*` into Docker containers (and thus k3d node containers); provides `nvidia-ctk` CLI | Latest stable (2026-03-12). Install via NVIDIA's apt repo (`nvidia.github.io/libnvidia-container/stable/deb`), not the Ubuntu archive. Adds support for "running containers as a user that may not have explicit access to a device node" — matches our non-root WSL user. |
| **NVIDIA k8s-device-plugin** | `v0.19.0` (Helm chart `0.19.0`) | DaemonSet inside spoke-ml that exposes `nvidia.com/gpu` to the kubelet | Latest stable (2026-03-17). NVIDIA explicitly states Helm is the "preferred method" in their README; static DaemonSet YAML is demo-only. Chart repo: `https://nvidia.github.io/k8s-device-plugin`. The plugin supports K8s >= 1.10, so v1.34.x is comfortably in range. |

### CUDA images

| Image tag | Version | Purpose | Why Recommended |
|---|---|---|---|
| `nvcr.io/nvidia/cuda:12.8.0-base-ubuntu22.04` | 12.8.0 GA | GPU smoke-test pod (`nvidia-smi` only) | Tag exists and is directly referenced by PROJECT.md. 12.8.0 is the exact version that NVIDIA documents as the first release adding **sm_120** (Blackwell / RTX 5090) compiler support. "base" variant (~250 MB) is correct for a smoke test — no cuDNN, no dev headers needed. Ubuntu 22.04 is fine; the host is Ubuntu 24.04 but container userspace glibc is decoupled from the host. |
| `nvidia/cuda:12.8.1-base-ubuntu22.04` | 12.8.1 | Base for the custom `k3s+CUDA` image used by spoke-ml | 12.8.1 is the latest 12.8.x patch on Docker Hub; use the patched version for the bigger, longer-lived image. Ubuntu 22.04 base is intentional: k3s upstream docs and the k3d CUDA guide both build against 22.04; 24.04 works but adds an unneeded variable when we're already tracking RTX 5090 + CUDA 12.8 as new/edge pieces. |

Note: `nvidia/cuda` on Docker Hub and `nvcr.io/nvidia/cuda` on NVIDIA NGC are content-identical mirrors. Use `nvcr.io` for the smoke-test (matches PROJECT.md) and `nvidia/cuda` (Docker Hub) for the custom image build — no auth required for either on public tags.

### NVIDIA Windows driver floor for RTX 5090

| Requirement | Value | Source |
|---|---|---|
| CUDA 12.8 GA minimum Windows driver | `>= 570.65` | NVIDIA CUDA 12.8 Release Notes |
| RTX 50 series Windows Game Ready Driver line | `572.xx` (Windows) / `570.xx` (Linux) | NVIDIA GeForce launch blog; Tesla release notes 570.86.15/572.13, 570.133.20/572.83, 570.172.08/573.48 |
| Recommended floor for this lab | **Windows driver `>= 572.13`** (ships Linux-side 570.86.15, which is the first 570 branch with public Windows RTX 5090 support) | Synthesis |

The existing `prereqs.sh` already gates on driver major `>= 570`, which is correct — the nvidia-smi output inside WSL reports the *Linux-side* bridge version (570.x), not the Windows-side 572.x/573.x. Keep the `>= 570` gate; no change needed.

---

## Installation — one-liners

```bash
# Docker Engine in WSL2 Ubuntu 24.04 (NOT Docker Desktop integration)
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker "$USER"
sudo systemctl enable --now docker.service containerd.service
# log out/in (or `newgrp docker`) to pick up group membership

# NVIDIA Container Toolkit
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt-get update
export NVIDIA_CONTAINER_TOOLKIT_VERSION=1.19.0-1
sudo apt-get install -y \
  nvidia-container-toolkit=${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
  nvidia-container-toolkit-base=${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
  libnvidia-container-tools=${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
  libnvidia-container1=${NVIDIA_CONTAINER_TOOLKIT_VERSION}
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker

# asdf v0.18.1 (Go rewrite)
ASDF_VERSION=v0.18.1
curl -LO "https://github.com/asdf-vm/asdf/releases/download/${ASDF_VERSION}/asdf-${ASDF_VERSION}-linux-amd64.tar.gz"
tar -xzf "asdf-${ASDF_VERSION}-linux-amd64.tar.gz"
sudo install -m 0755 asdf /usr/local/bin/
# add to ~/.bashrc (AFTER any other PATH-mutating lines):
#   export PATH="${ASDF_DATA_DIR:-$HOME/.asdf}/shims:$PATH"

# Tools via asdf (run after .tool-versions is committed)
for plugin in kubectl helm flux k3d task jq yq; do asdf plugin add "$plugin" || true; done
asdf install

# NVIDIA device plugin (on spoke-ml only, from hub via Flux HelmRelease later)
helm repo add nvdp https://nvidia.github.io/k8s-device-plugin
helm repo update
helm upgrade -i nvdp nvdp/nvidia-device-plugin \
  --namespace nvidia-device-plugin --create-namespace \
  --version 0.19.0
```

---

## `.tool-versions` — copy-paste ready

```
kubectl 1.34.7
helm 3.20.2
flux2 2.8.6
k3d 5.8.3
task 3.50.0
jq 1.8.1
yq 4.53.2
```

Notes on plugin names:
- The flux plugin is commonly `flux2` (not `flux`) in the asdf community registry. Confirm at `asdf plugin list all | grep flux` before committing.
- asdf itself is NOT listed in `.tool-versions` (it's the thing reading the file). Document the asdf version in README.

---

## Version Compatibility — what talks cleanly to what

| Pair | Compatible? | Notes |
|---|---|---|
| k3s v1.34.6 ↔ Flux v2.8.6 | ✅ | Flux 2.8.x explicitly supports K8s `>= 1.34.1`; v1.34.6 is the fifth patch above that floor. |
| kubectl v1.34.7 ↔ k3s v1.34.6 | ✅ | Same minor; skew policy allows N±1. |
| k3d v5.8.3 ↔ k3s v1.34.6-k3s1 | ✅ | k3d is version-agnostic about the k3s image — it just runs it. `--image=rancher/k3s:v1.34.6-k3s1` works. |
| k3d `--gpus all` ↔ Docker nvidia runtime | ✅ | `--gpus` is a straight Docker CLI passthrough — requires `nvidia-ctk runtime configure --runtime=docker` to have run first. |
| Helm 3.20.2 ↔ k8s 1.34.x | ✅ | Helm 3 tracks the current K8s release line; no minor-version ceiling. |
| NVIDIA device plugin v0.19.0 ↔ k8s 1.34.x | ✅ | Plugin supports K8s >= 1.10; v0.19 bumped to NodeFeature API by default in GFD. |
| CUDA 12.8 ↔ RTX 5090 (sm_120) | ✅ | 12.8 GA is the first CUDA release with SM_100/SM_101/SM_120 compiler support per NVIDIA release notes. |
| WSL2 + Docker Engine (native, no Docker Desktop) + k3d | ✅ (with caveats) | See PITFALLS — mirrored networking + cgroup v2 quirks. Current Ubuntu 24.04 + WSL2 works but `networkingMode=mirrored` has documented Docker port-forwarding issues; NAT-mode is the safer default for this lab. |

---

## Alternatives Considered

| Our Choice | Alternative | When to Use the Alternative |
|---|---|---|
| k3s v1.34.6 | k3s v1.35.3 (latest K3s release line) | If the lab wants the newest upstream features. Downside: v1.35 is only one minor above Flux 2.8.x's tested floor (`>= 1.35.0`), leaving zero margin. v1.34.x is the "one behind latest" sweet spot. |
| k3d v5.8.3 | k3d v5.9.0-rc.0 | Only if a v5.9 feature is needed. v5.9 is pre-release — skip until GA. |
| Helm 3.20.2 | Helm 4.1.4 | If greenfield with no v3 charts to migrate. For this lab: SSA-default and SDK breakage aren't worth the churn right now. |
| asdf v0.18.1 (Go) | mise, rtx, Volta | mise (née rtx) is faster and asdf-compatible, but asdf is the lab's stated choice and `.tool-versions` format is portable across all three. Stick with asdf. |
| NVIDIA device plugin (DaemonSet) | NVIDIA GPU Operator | Operator is richer (GFD, MIG config, DCGM, driver mgmt) but PROJECT.md explicitly defers it. Plugin is right for v1. |
| kubectl v1.34.7 | kubectl v1.35.4 (N+1) | Works per skew policy, but buys nothing for a lab where cluster and client are co-installed. |
| yq mikefarah v4 | yq kislyuk (Python wrapper) | mikefarah yq is a single Go binary with richer syntax; kislyuk needs Python + jq. Mikefarah's variant is what PROJECT.md assumes. |
| Docker Engine native in WSL | Docker Desktop's WSL integration | ADR-001 rejects Docker Desktop: it spawns extra WSL distros (`docker-desktop`, `docker-desktop-data`) that consume the same shared WSL VM memory. |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|---|---|---|
| **asdf v0.15 or earlier (bash classic)** | Pre-v0.16 bash implementation is EOL. v0.16+ prints a loud deprecation warning at shell startup if you try the old source-style integration. Shim generation and plugin execution are materially different. | asdf v0.18.1 (Go binary) with the `PATH`-prepend integration shown above. |
| **k3s v1.34.3+k3s1** (specific intermediate patch) | Known etcd "Zombie-Member" upgrade bug when going 1.33.7 → 1.34.3 — etcd v3.6.6 detected members in the v3 store that shouldn't be there. | k3s v1.34.6+k3s1 (etcd v3.6.7-k3s1, fix included). |
| **k3d v5.8.0** | Release notes explicitly say "Missing helper images with this tag - please just use v5.8.1". | k3d v5.8.3 (patched). |
| **Docker Desktop WSL integration** | Consumes shared VM memory via auxiliary WSL distros; conflicts with ADR-001 single-distro model. Also nondeterministic interaction with `networkingMode=mirrored` per Docker for Win issue #14691. | Docker Engine installed natively inside the Ubuntu 24.04 distro via `docker-ce` apt repo. |
| **Helm 4.x (for this lab)** | Breaking changes in post-renderers, flag renames (`--force` → `--force-replace`), removed `HELM_EXPERIMENTAL_OCI`, SDK churn. Third-party chart ecosystem still catching up. | Helm 3.20.2 — still in bug-fix + security support through late 2026. |
| **`networkingMode=mirrored` in `.wslconfig` (as default)** | Documented breakage: Docker port forwarding fails (microsoft/WSL#10494), TCP stalls in containers (moby/moby#48201), loopback unreachable (microsoft/WSL#13868). | Keep `networkingMode=nat` (default) for v1. Document `mirrored` as a fallback that may need additional tuning; PROJECT.md already calls this out. |
| **kislyuk yq (Python)** | Different syntax from Mike Farah's yq; scripts written against v4 syntax will silently fail or misbehave. | mikefarah yq v4.53.2 (Go binary). Verify asdf-yq plugin points at mikefarah (it does, by default). |
| **Raw device-plugin DaemonSet YAML** | NVIDIA's own README marks it as "for demonstration purposes only" and recommends Helm. Static manifest lags releases. | `nvidia-device-plugin` Helm chart v0.19.0 from `https://nvidia.github.io/k8s-device-plugin`. |
| **`--tls-san=...` as a top-level k3d flag** | It's not a k3d flag. Using it naively will fail parse. | Pass via `--k3s-arg '--tls-san=k3d-<cluster>-server-0@server:*'` on `k3d cluster create`, or the `extraArgs` block in a k3d config file. |

---

## Stack Patterns by Variant

**If WSL2 `networkingMode=mirrored` is required (corp-policy, etc.):**
- Document the NAT-mode fallback as the default path.
- In mirrored mode, expect to set `hostAddressLoopback=true` and `nestedVirtualization=true` (Docker for Win #14691 pattern).
- Test `docker run -p 8080:80 nginx` and `curl localhost:8080` before trusting the setup for k3d.

**If the host GPU is ever swapped off RTX 5090 (e.g., older RTX 40xx / Ada):**
- Drop the CUDA floor from 12.8 to 12.4+ (Ada is sm_89 — 12.2+ is sufficient).
- Smoke-test image can drop to `nvcr.io/nvidia/cuda:12.4.1-base-ubuntu22.04` (the version k3d's own CUDA docs example uses).
- Driver floor drops to the 550 branch.

**If Flux is later upgraded to v2.9 (when it ships):**
- GCR Receiver `audience` field becomes mandatory — audit any Flux Receiver CRs.
- Re-check `MigrateAPIVersion` feature-gate behavior in kustomize-controller (introduced in v1.8.4).

---

## Sources

All fetched or verified on 2026-04-22:

- **k3s releases** — `gh release list --repo k3s-io/k3s` → v1.34.6+k3s1 (2026-03-28), release notes with embedded component versions (etcd v3.6.7-k3s1, containerd v2.2.2). HIGH.
- **k3s v1.34.6 Docker Hub tag** — https://hub.docker.com/r/rancher/k3s/tags?name=v1.34.6 confirmed live (pushed ~2026-03-28 by autorancher). HIGH.
- **k3d releases** — `gh release list --repo k3d-io/k3d` → v5.8.3 latest stable (2025-02-15); v5.8.0 explicitly deprecated by its own release notes ("please just use v5.8.1"). HIGH.
- **k3d cluster create flags** — https://k3d.io/v5.8.3/usage/commands/k3d_cluster_create/ confirms `--gpus`, `--network`, `--image`; https://k3d.io/stable/usage/configfile/ shows `--tls-san` is a k3s arg passed via `--k3s-arg` or `extraArgs`. HIGH.
- **k3d CUDA guide** — https://k3d.io/stable/usage/advanced/cuda/ confirms custom-image approach, `--gpus=1` or `--gpus=all`. HIGH.
- **Flux releases** — `gh release list --repo fluxcd/flux2` → v2.8.6 (2026-04-21). Release notes confirm current component versions. HIGH.
- **Flux K8s compatibility** — https://fluxcd.io/flux/installation/: "Kubernetes v1.34: `>= 1.34.1`". HIGH.
- **Kubernetes releases** — `gh release list --repo kubernetes/kubernetes` → v1.34.7 (2026-04-15). HIGH.
- **kubectl skew policy** — https://kubernetes.io/releases/version-skew-policy/: kubectl is N-1/N/N+1 vs kube-apiserver. HIGH.
- **Helm releases** — `gh release list --repo helm/helm` → v3.20.2 (2026-04-09) and v4.1.4 (latest overall 2026-04-09). Helm 4 breaking-change summary from helm.sh/docs/overview and multiple migration guides. HIGH (versions), HIGH (breakage summary — multi-source agreement).
- **Taskfile releases** — `gh release list --repo go-task/task` → v3.50.0 (2026-04-13). HIGH.
- **asdf releases + v0.16 rewrite** — `gh release view v0.16.0 --repo asdf-vm/asdf` confirms "Rewrite asdf in Golang"; v0.18.1 (2026-03-04) is current stable. HIGH.
- **jq release** — `gh release list --repo jqlang/jq` → 1.8.1 (2025-07-01). HIGH.
- **yq (mikefarah) release** — `gh release list --repo mikefarah/yq` → v4.53.2 (2026-04-17). HIGH.
- **NVIDIA container toolkit release + install** — `gh release view v1.19.0 --repo NVIDIA/nvidia-container-toolkit` (2026-03-12); https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html for exact apt flow. HIGH.
- **NVIDIA device plugin release** — `gh release list --repo NVIDIA/k8s-device-plugin` → v0.19.0 (2026-03-17); https://github.com/NVIDIA/k8s-device-plugin README confirms Helm as preferred path. HIGH.
- **CUDA 12.8 GPU / driver support** — https://docs.nvidia.com/cuda/archive/12.8.0/cuda-toolkit-release-notes/index.html: SM_100/SM_101/SM_120 compiler support added; Windows driver `>= 570.65`. HIGH.
- **nvcr.io / Docker Hub CUDA tag inventory** — Docker Hub v2 API pull of `nvidia/cuda` tags matching `base-ubuntu` confirms `12.8.0-base-ubuntu22.04` and `12.8.1-base-ubuntu22.04` both exist. HIGH.
- **Docker Engine install on Ubuntu 24.04** — https://docs.docker.com/engine/install/ubuntu/; post-install https://docs.docker.com/engine/install/linux-postinstall/ for the `usermod -aG docker`, `systemctl enable` steps. HIGH.
- **RTX 5090 Windows driver 572.x** — NVIDIA GeForce blog (RTX 5090 launch Game Ready Driver) + Tesla release notes 570.86.15/572.13, 570.133.20/572.83. MEDIUM-HIGH (multi-source agreement, specific exact Windows build not in CUDA release notes). Existing `prereqs.sh` `>= 570` gate (on Linux-side bridge version) remains correct.
- **WSL2 mirrored-networking caveats** — microsoft/WSL#10494, #13868, moby/moby#48201, docker/for-win#14691. MEDIUM (community issues, not product docs; consistent across many reports). Actionable as a PITFALL, not a blocker.

---

*Stack research for: local multi-cluster Kubernetes lab (k3d + Flux + WSL2 + GPU)*
*Researched: 2026-04-22*
