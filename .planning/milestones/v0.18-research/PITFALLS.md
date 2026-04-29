# Pitfalls Research

**Domain:** Local hub-spoke Flux multi-cluster lab on k3d + WSL2 + NVIDIA GPU (RTX 5090 Blackwell / sm_120)
**Researched:** 2026-04-22
**Confidence:** HIGH for well-known issues (mirrored-mode, clock-skew, GPU runtime, Flux bootstrap), MEDIUM for RTX 5090 specifics (ecosystem moving quickly), MEDIUM for k3s v1.34.6 (release is recent).

This file extends `PROJECT.md`'s "Known Risks" section. Starter risks are **acknowledged and cross-linked**, not repeated verbatim. New pitfalls are marked [NEW].

---

## Critical Pitfalls

Issues that cause cluster-bring-up failure, data loss, or silent security exposure.

---

### Pitfall 1: WSL2 `mirrored` mode silently breaks Docker user-defined bridge networks

**What goes wrong:**
With `[wsl2] networkingMode=mirrored` in `.wslconfig`, Docker user-defined bridge networks (`k8s-net`) exhibit multiple failure modes:
- TCP connections from inside containers **stall** on certain remote endpoints while `curl` from the host works (moby/moby#48201).
- Port forwarding from Windows host into container ports on the bridge fails (microsoft/WSL#10494, #10683).
- Response packets don't route back because destination MAC belongs to the Docker bridge, not the WSL interface (moby/moby#48136).
- "Mirrored networking mode is not supported" error on some Windows 11 Insider builds (microsoft/WSL#12578).

**Why it happens:**
`mirrored` exposes Windows interfaces directly into WSL and relies on Hyper-V vSwitch plumbing for return traffic. Docker's `docker0`-based bridge inserts a second L2 hop that the mirrored-mode return path does not understand. This is still not fully resolved as of 2025.

**How to avoid:**
- Default the documented `.wslconfig` to **NAT mode** (the historical default) — do NOT set `networkingMode=mirrored` for v1.
- If the user already uses `mirrored` for other reasons, provide a **fallback `.wslconfig` template** at `config/wslconfig` that comments out `networkingMode=mirrored` and optionally documents `hostAddressLoopback=true`/`nestedVirtualization=true` tradeoffs.
- Add a **preflight probe**: from inside a small container on `k8s-net`, `curl` a known-good external endpoint (e.g., `https://docker.io`) with a 10 s timeout. If it stalls but succeeds from the WSL host, flag mirrored-mode regression.

**Warning signs:**
- `k3d cluster create` hangs in "Starting node 'k3d-hub-flux-server-0'"
- `kubectl get nodes` works, but image pulls from `registry-1.docker.io` stall and time out
- `docker exec <ctr> curl https://example.com` hangs; same command from WSL host succeeds

**Phase to address:**
Preflight phase (add probe) + WSL config phase (ship NAT-mode template as default; document mirrored-mode fallback procedure)

**Source:**
- https://github.com/microsoft/WSL/issues/10494
- https://github.com/microsoft/WSL/issues/10683
- https://github.com/moby/moby/issues/48201
- https://github.com/moby/moby/issues/48136
- https://github.com/microsoft/WSL/issues/12578

---

### Pitfall 2: Docker daemon refuses to start because WSL2 kernel lacks `nftables` modules, or nftables/iptables alternatives mismatch

**What goes wrong:** [NEW]
Docker fails at startup with `failed to setup IP tables` or similar; bridge network cannot be created; all k3d cluster creation fails. Modern Ubuntu 24.04 points `iptables` to `iptables-nft` by default, but WSL2's kernel historically lacked some `nf_tables` modules, and Docker Engine's nftables support is still marked experimental (Docker 29.0+).

**Why it happens:**
Docker was built around the legacy iptables interface. Ubuntu 20.04+ made `iptables-nft` the default via `update-alternatives`. WSL2 kernels intermittently have gaps in the `nft` module set, so Docker's nftables probe fails while its legacy iptables probe would succeed.

**How to avoid:**
- `install-docker.sh` should switch alternatives explicitly: `sudo update-alternatives --set iptables /usr/sbin/iptables-legacy && sudo update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy`
- Restart Docker after the switch
- Document this in `rebuild-runbook.md` as a standard installation step

**Warning signs:**
- `systemctl status docker` shows `failed to create NAT chain DOCKER: iptables failed`
- `docker network create k8s-net` returns `Error response from daemon: Failed to Setup IP tables`

**Phase to address:**
Docker-install phase (install-docker.sh)

**Source:**
- https://github.com/microsoft/WSL/issues/6655
- https://docs.docker.com/engine/network/firewall-nftables/
- https://patrickwu.space/2021/03/09/wsl-solution-to-native-docker-daemon-not-starting/

---

### Pitfall 3: Docker Desktop WSL-integration files conflict with native Docker Engine

**What goes wrong:**
The preflight already detects Docker Desktop integration. But the failure mode if it's missed is specific: stale files like `~/.docker/`, `/var/run/docker.sock`, `/var/run/docker.pid` placed by Docker Desktop remain on the integrated distro even after disabling integration, and cause native Docker Engine to fail at startup with confusing socket / context errors.

**Why it happens:**
Docker Desktop's WSL integration injects binaries and state into every integrated distro. Disabling integration in Desktop settings does NOT clean up these files. The native engine then races against the Desktop-placed files for the same socket paths.

**How to avoid:**
`install-docker.sh` should, after confirming Desktop integration is disabled, remove stale Desktop artifacts:
```bash
rm -rf "$HOME/.docker"
sudo rm -f /var/run/docker.sock /var/run/docker.pid
sudo rm -rf /var/run/docker*
```
Then install Docker Engine natively per the documented path.

**Warning signs:**
- Preflight warns `Docker Desktop WSL integration detected`
- `docker ps` returns `Cannot connect to the Docker daemon` even though `systemctl status docker` shows active
- Two `docker` binaries in PATH — one under `/mnt/wsl/docker-desktop/cli-tools/usr/bin/docker` and one under `/usr/bin/docker`

**Phase to address:**
Docker-install phase (install-docker.sh). Starter already flags the detection in preflight; the cleanup step is [NEW].

**Source:**
- https://docs.docker.com/desktop/features/wsl/
- https://nickjanetakis.com/blog/install-docker-in-wsl-2-without-docker-desktop
- https://forums.docker.com/t/issues-with-docker-desktop-and-wsl-2-integration/141865

---

### Pitfall 4: WSL2 clock drift after hibernate → TLS certificate and OIDC token rejections

**What goes wrong:**
After Windows sleep/hibernate, WSL2's clock lags by minutes or hours. Kubernetes API server refuses kubelet/kubectl requests with `x509: certificate has expired or is not yet valid`; Flux GitHub token validation fails; OIDC auth loops; etcd leader election thrashes.

**Why it happens:**
WSL2 is a Hyper-V VM. When Windows hibernates, the VM is frozen. On resume, the VM's monotonic clock resumes where it left off; no automatic NTP resync occurs. Certificate validity and JWT `exp` fields are time-bound — a 30-minute drift will invalidate newly-issued tokens.

**How to avoid:**
- Install `systemd-timesyncd` or `chrony` and enable the service
- Add a systemd unit that runs `/sbin/hwclock -s` at boot and on `suspend.target`/`hibernate.target` resume
- Alternative: Windows Task Scheduler task triggered by Kernel-Power event ID 107 (resume) that runs `wsl -d <distro> -u root /sbin/hwclock -s`
- Include `health-check.sh` probe: `if (( $(date -u +%s) - $(ssh hub-flux date -u +%s) > 60 )); then echo "clock skew"; fi`

**Warning signs:**
- `flux get sources git flux-system` shows `x509: certificate signed by unknown authority` despite correct CA
- `kubectl get pods` works sometimes but fails with `Unauthorized` after suspend
- `date` inside WSL differs from Windows taskbar clock

**Phase to address:**
WSL-config phase (ship hwclock systemd unit) + preflight (add skew check) + docs (rebuild-runbook notes recovery procedure: `sudo hwclock -s`)

**Source:**
- https://github.com/microsoft/WSL/issues/10006
- https://github.com/microsoft/WSL/issues/8204
- https://stuartleeks.com/posts/fixing-clock-skew-with-wsl-2/
- https://documentation.ubuntu.com/wsl/latest/explanation/time-sync/

---

### Pitfall 5: k3s refuses to start on hybrid cgroup v1/v2 — requires pure cgroup v2

**What goes wrong:** [NEW]
k3s (and k3d by extension) crashes at startup with `failed to find cpu cgroup (v2)` or system pods stuck in CrashLoopBackOff. kubelet logs show cgroup v2 path not mountable.

**Why it happens:**
k3s v1.26+ requires **pure cgroup v2**; it explicitly does not support hybrid v1/v2. WSL2's default kernel on Ubuntu 24.04 is cgroup v2, BUT if the user historically set `kernelCommandLine=systemd.unified_cgroup_hierarchy=1` (or inherited such a setting) in `.wslconfig`, a hybrid configuration emerges and k3s bails.

**How to avoid:**
- Do NOT set any `systemd.unified_cgroup_hierarchy` kernel param in `.wslconfig` on Ubuntu 24.04 — the default is already correct.
- Preflight probe: `cat /proc/cgroups | awk 'NR>1 {print $1":"$4}'` — if any v1 controller is mounted alongside v2, flag.
- Alternative probe: `stat -fc %T /sys/fs/cgroup` should return `cgroup2fs` on pure v2.
- Document in `config/wslconfig`: explicitly omit `kernelCommandLine` for cgroups (with a comment explaining why).

**Warning signs:**
- `k3d cluster create` proceeds but `kubectl get nodes` stays `NotReady`
- `docker logs k3d-hub-flux-server-0` shows `failed to find cgroup v2 ... exiting`
- `stat -fc %T /sys/fs/cgroup` returns `tmpfs` instead of `cgroup2fs`

**Phase to address:**
Preflight phase (cgroup probe) + WSL-config phase (committed template omits v1 kernel params)

**Source:**
- https://docs.k3s.io/advanced
- https://github.com/microsoft/WSL/issues/6662
- https://github.com/k3s-io/k3s/issues/6241

---

### Pitfall 6: `--tls-san` missing for spoke → hub Flux cannot reach spoke via `k3d-<name>-server-0` DNS

**What goes wrong:**
The starter already flags this as a risk. The **specific failure mode** when `--tls-san k3d-<spoke>-server-0` is omitted:
- Kubeconfig Secret on hub points `server: https://k3d-spoke-ml-server-0:6443`
- Spoke's apiserver certificate is valid only for `kubernetes`, `kubernetes.default`, `localhost`, and the container IP — NOT for `k3d-spoke-ml-server-0`
- Hub's `kustomize-controller` and `helm-controller` fail with `x509: certificate is valid for <ips>, not k3d-spoke-ml-server-0`
- Kustomizations stay `NotReady` with `reconciliation failed: unable to connect to cluster`

**Why it happens:**
k3s API server certificate SAN list is fixed at cluster-creation time. k3d injects sensible defaults (`kubernetes`, `localhost`, container IP) but NOT the Docker-DNS hostname. When hub pods resolve `k3d-<spoke>-server-0` via Docker's embedded DNS on the shared `k8s-net` bridge, the TLS verify step fails even though the connection succeeds.

**How to avoid:**
- `scripts/create-clusters.sh` must pass `--tls-san "k3d-<name>-server-0"` for **every** cluster (not just spokes — hub too, in case of future multi-cluster topology).
- Additionally consider `--tls-san "k3d-<name>-serverlb"` if k3d's serverlb is used.
- Spoke kubeconfig Secret generation in `register-spokes.sh` should verify certificate contains the SAN: `openssl s_client -connect k3d-spoke-ml-server-0:6443 -servername k3d-spoke-ml-server-0 </dev/null 2>/dev/null | openssl x509 -noout -text | grep -A2 "Subject Alternative Name"`
- `health-check.sh` probe: from inside a hub pod, `kubectl --kubeconfig=/tmp/spoke.kubeconfig get nodes` and check for `x509` errors in the output.

**Warning signs:**
- Flux Kustomization status: `transport: authentication handshake failed: tls: failed to verify certificate`
- `flux get kustomizations -A` shows spoke targets stuck `Unknown` or `False`

**Phase to address:**
Cluster-creation phase (create-clusters.sh) + health-check phase (verify probe)

**Source:**
- https://github.com/k3s-io/k3s/issues/2365
- https://taozhi.medium.com/k3s-apiserver-unable-to-connect-to-the-server-x509-certificate-is-valid-for-10-43-0-1-8ec1f8c2097f
- https://docs.k3s.io/cli/server

---

### Pitfall 7: k3d GPU setup requires custom k3s image with containerd template — `--gpus all` alone is not enough

**What goes wrong:**
Running `k3d cluster create spoke-ml --gpus all` with the stock `rancher/k3s:v1.34.6-k3s1` image completes successfully. But GPU pods never schedule: `kubectl describe node` shows `nvidia.com/gpu: 0` capacity. Even with NVIDIA device plugin deployed, the plugin logs `failed to load NVML library: libnvidia-ml.so.1: cannot open shared object file`.

**Why it happens:**
Two separate issues:
1. Stock `rancher/k3s` image is Alpine-based. The NVIDIA Container Runtime does not support Alpine. You MUST build a custom image (based on `nvcr.io/nvidia/cuda:12.8.x-base-ubuntu22.04`) that includes the k3s binary plus `nvidia-container-runtime`.
2. k3s generates `/var/lib/rancher/k3s/agent/etc/containerd/config.toml` from a template. Without a custom `config.toml.tmpl` setting `default_runtime_name = "nvidia"` under `[plugins.cri.containerd]`, containerd picks `runc` by default and ignores `runtimeClassName: nvidia` annotations (or worse, NVIDIA devices never reach the container).
3. On the **host** side, `/etc/docker/daemon.json` MUST have `"default-runtime": "nvidia"` — this is specifically so the k3d **node container** itself gets GPU access when k3d starts it. Per-container `--runtime=nvidia` is NOT sufficient because k3d does not let you override the runtime on node containers individually.

**How to avoid:**
- `images/Dockerfile.k3s-cuda`:
  - `FROM nvcr.io/nvidia/cuda:12.8.0-base-ubuntu22.04`
  - Install `nvidia-container-toolkit`
  - Copy k3s binary from `rancher/k3s:v1.34.6-k3s1`
  - Copy custom `config.toml.tmpl` that sets `default_runtime_name = "nvidia"`
- `install-nvidia-container-toolkit.sh` runs `sudo nvidia-ctk runtime configure --runtime=docker --set-as-default` — the `--set-as-default` flag is critical.
- Verify: `docker info | grep -i "Default Runtime"` must print `Default Runtime: nvidia`.
- k3s v1.32+ can auto-detect the NVIDIA runtime and add it to containerd config — but this still requires the runtime binaries in the node image, so custom image is still required.

**Warning signs:**
- `kubectl describe node spoke-ml-server-0 | grep -A3 Capacity` shows no `nvidia.com/gpu` line
- NVIDIA device plugin pod logs: `No valid resources detected, creating a null CDI handler` or `failed to load NVML library`
- GPU smoke-test pod: `Error: failed to create containerd task: ... nvidia-container-cli: initialization error`

**Phase to address:**
GPU-install phase (nvidia-container-toolkit + daemon.json default-runtime) + image-build phase (custom k3s+CUDA image)

**Source:**
- https://k3d.io/v5.8.3/usage/advanced/cuda/
- https://github.com/k3d-io/k3d/issues/1108
- https://github.com/NVIDIA/k8s-device-plugin
- https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html
- https://medium.com/@panda1100/running-gpu-workloads-on-k3d-cluster-by-using-nvidia-device-plugin-for-k8s-4c4853834075

---

### Pitfall 8: Flux bootstrap hand-edits under `clusters/hub-flux/flux-system/` are NOT ALL reverted — `kustomization.yaml` patches ARE preserved

**What goes wrong / Nuance:**
The starter says "don't hand-edit `clusters/hub-flux/flux-system/`" — this is **correct for most files but wrong for one**. The actual behavior:

- `gotk-components.yaml` and `gotk-sync.yaml`: regenerated by bootstrap. **Any hand-edits here ARE reverted on re-bootstrap.**
- `kustomization.yaml` (note: NOT `gotk-components.yaml`, the plain `kustomization.yaml` in the same dir): **preserved across re-bootstrap.** This is the officially supported customization point for Kustomize strategic-merge patches and JSON6902 patches targeting controller args, resource limits, network policies, etc.

So telling the user "do not touch `clusters/hub-flux/flux-system/`" at all is **overly broad** — it forces them to fork bootstrap or post-patch elsewhere, when the supported path is right there.

**Why it happens:**
Flux's bootstrap customization documentation is clear but the distinction between `gotk-components.yaml` (regenerated) and `kustomization.yaml` (preserved) is easy to miss. The `clusters/hub-flux/flux-system/kustomization.yaml` file is the only durable hand-edit surface in that directory.

**How to avoid:**
- Update starter's guidance to: "Do not hand-edit `gotk-components.yaml` or `gotk-sync.yaml` — they are regenerated by bootstrap. To customize components (image args, resource limits, tolerations), add patches to `clusters/hub-flux/flux-system/kustomization.yaml`, which IS preserved across re-bootstrap."
- Document example patches in `docs/flux-hub-spoke.md` (e.g., extending controller memory, adding `--concurrent=10` to kustomize-controller).

**Warning signs:**
- User edits `gotk-components.yaml` to bump a controller arg → next `task bootstrap-flux` reverts it → user assumes Flux is "broken" or "non-idempotent"
- User asks "how do I customize controller X" and the answer is "fork the whole bootstrap"

**Phase to address:**
Docs phase (flux-hub-spoke.md) + bootstrap phase (comment in bootstrap-flux.sh pointing to kustomization.yaml)

**Source:**
- https://fluxcd.io/flux/installation/configuration/bootstrap-customization/
- https://fluxcd.io/flux/installation/bootstrap/github/

---

### Pitfall 9: Bootstrapping twice with a different `--path` flag silently overwrites the hub's sync Kustomization

**What goes wrong:** [NEW]
User bootstraps with `--path=clusters/hub-flux`. Later, someone re-runs `task bootstrap-flux` after renaming the directory to `--path=clusters/hub`. The second bootstrap overwrites the existing `flux-system` Kustomization's `.spec.path` in-place. All spoke Kustomizations under the old path become un-reconciled (pruned!) because the new sync path no longer contains them.

**Why it happens:**
The bootstrap sync path flag writes to the Kustomization's `.spec.path`. Flux's prune semantics on the root Kustomization then garbage-collect everything that was previously reconciled from the old path.

**How to avoid:**
- **Never change `--path`, `--cluster-name`, or `--namespace` on a re-bootstrap.** These are effectively "terraforms the cluster once" flags.
- `bootstrap-flux.sh` should hardcode these values and reject overrides from env:
  ```bash
  : "${FLUX_PATH:=clusters/hub-flux}"
  # comment: changing this after first bootstrap WILL delete unregistered resources on spokes
  ```
- Document this in `docs/flux-hub-spoke.md` under a "Migration / Renaming" section.

**Warning signs:**
- Suddenly-empty spokes after a re-bootstrap
- `flux get kustomizations -A` shows spokes' Kustomizations `NotFound`
- Git diff of `clusters/hub-flux/flux-system/gotk-sync.yaml` shows `.spec.path` changed

**Phase to address:**
Bootstrap phase + docs (hard-code path, document the "flags that cannot change" contract)

**Source:**
- https://github.com/fluxcd/flux2/discussions/1517
- https://fluxcd.io/flux/installation/bootstrap/github/

---

### Pitfall 10: GITHUB_TOKEN committed to public repo — Flux keeps using the stale token until the in-cluster Secret is rotated

**What goes wrong:** [NEW]
User accidentally commits `.env` with `GITHUB_TOKEN=ghp_...` to the public repo. GitHub's secret-scanning notifies within minutes; attackers' bots notify within seconds. User revokes the PAT on GitHub. But **Flux in the hub cluster continues to use the stale token for git-source polling** for up to 1 minute (until the next poll fails) — and if they only update `.env` locally without also rotating the in-cluster Secret, the next `task bootstrap-flux` will NOT rotate it either (bootstrap writes the secret only on first run, unless you use `--force` or delete it manually).

**Why it happens:**
Flux stores the token during bootstrap in the `flux-system` Secret in the `flux-system` namespace. Subsequent bootstraps are "upgrades" and do not touch the Secret by default. The `.env` file and the in-cluster Secret are two independent sources of truth after the initial bootstrap.

**How to avoid:**
- **`.gitignore` must contain `.env`** before the first commit. Enforce via `pre-commit` hook (gitleaks).
- `.env.example` committed; `.env` never. Preflight checks that `.env` is in `.gitignore`.
- If a leak occurs:
  1. Revoke PAT on GitHub immediately.
  2. Rotate the in-cluster Secret: `flux create secret git flux-system --url=... --username=git --password=$NEW_TOKEN`
  3. Use BFG or `git filter-repo` to purge from history; force-push.
  4. Rotate kubeconfig tokens on all spokes (the leaked PAT may have been used to push malicious manifests to the repo → reconciled to spokes).
- Prefer **GitHub Deploy Keys** (SSH) or the **GitHub App** auth flow over a PAT for bootstrap. Flux 2.5+ supports GitHub App bootstrap with short-lived tokens (`flux bootstrap github --github-app-id=... --github-app-installation-id=...`).

**Warning signs:**
- GitHub sends "We detected a token in your public repo" email
- Flux `source-controller` logs: `401 Unauthorized` from github.com after revocation

**Phase to address:**
Repo-hygiene phase (gitignore, .env.example, gitleaks pre-commit) + docs (incident response runbook)

**Source:**
- https://github.com/fluxcd/flux2/discussions/2161
- https://fluxcd.io/blog/2025/04/flux-operator-github-app-bootstrap/
- https://fluxcd.io/flux/installation/bootstrap/github/
- https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository

---

### Pitfall 11: k3d CoreDNS `NodeHosts` goes stale after Docker/WSL restart

**What goes wrong:**
The starter already flags this and has `task fix-dns`. The **specific mechanism** and a subtler failure mode:
- On Docker restart, containers get new IPs but k3s's `/etc/coredns/NodeHosts` (inside CoreDNS configmap) retains the OLD node IPs.
- Pods resolve `k3d-hub-flux-server-0` to the stale IP → connection refused or black-hole timeout.
- Additionally: if a node goes `NotReady` and isn't removed, k3s keeps injecting stale entries on every reconciliation (k3s-io/k3s#9274).

**Why it happens:**
k3s's `helm-controller` injects Node objects' InternalIPs into the CoreDNS ConfigMap's `NodeHosts` key. Docker's bridge networking does not preserve container IPs across daemon restarts. k3s sees old-IP Node objects before they're reconciled.

**How to avoid:**
- Starter's `task fix-dns` (stop → start hub) is the correct workaround.
- Add a **preflight probe**: from hub pod, `getent hosts k3d-hub-flux-server-0` should return the current container IP (verify with `docker inspect k3d-hub-flux-server-0 | jq '.[0].NetworkSettings.Networks."k8s-net".IPAddress'`). Mismatch → recommend `task fix-dns`.
- Consider adding a `hostAliases` entry to hub Flux controllers (as a belt-and-suspenders) so TLS SAN hostname resolution does not depend on CoreDNS — `kustomization.yaml` patch to hub's kustomize-controller Deployment.
- Document in `rebuild-runbook.md`: after Windows reboot / `wsl --shutdown`, always run `task fix-dns` before `task health-check`.

**Warning signs:**
- `kubectl -n flux-system logs kustomize-controller-...` shows `dial tcp: lookup k3d-spoke-ml-server-0 on 10.43.0.10:53: no such host`
- `kubectl exec -n flux-system kustomize-controller-... -- nslookup k3d-spoke-ml-server-0` fails
- Fine immediately after cluster creation; breaks after first `wsl --shutdown` / `docker restart`

**Phase to address:**
Operations phase (`task fix-dns` script exists per starter) + health-check phase (add probe) + docs (runbook mentions the restart gotcha)

**Source:**
- https://github.com/k3d-io/k3d/issues/1009
- https://github.com/k3d-io/k3d/issues/1112
- https://github.com/k3s-io/k3s/issues/9274

---

### Pitfall 12: NVIDIA `libnvidia-ml.so.1: file exists` CDI mount error in WSL2 containers

**What goes wrong:** [NEW]
`nvidia-smi` inside a pod returns `Failed to initialize NVML: Unknown Error` OR the pod fails to start with:
```
nvidia-container-cli: mount error: file creation failed: /usr/lib/wsl/drivers/nvtfsi.inf_amd64_xxx/libcuda.so: file exists
```

**Why it happens:**
WSL2's GPU pass-through puts NVIDIA driver libraries under `/usr/lib/wsl/` (not `/usr/lib/x86_64-linux-gnu/`). The `nvidia-container-toolkit` auto-generated CDI spec sometimes tries to mount libraries to paths that already exist in the container base image, or generates paths appropriate for a native Linux host, not for WSL. Base images that include `libnvidia-ml.so.1` (e.g., `nvcr.io/nvidia/cuda:12.8.0-runtime-ubuntu22.04`) collide with the CDI-mounted version.

**How to avoid:**
- Use **base** images (`nvcr.io/nvidia/cuda:12.8.0-base-ubuntu22.04`), NOT `runtime` or `devel`, for the smoke-test. The `base` variant ships only CUDA runtime headers without pre-installed driver libraries — avoids the collision. Starter already specifies this; call it out explicitly in `docs/gpu-notes.md`.
- Pin `nvidia-container-toolkit` to `>= 1.17` which has WSL-aware CDI generation.
- Verify CDI spec: `nvidia-ctk cdi generate --output=/tmp/nvidia.yaml && cat /tmp/nvidia.yaml` — inspect for `/usr/lib/wsl/` paths.
- Smoke-test pod spec must NOT set `securityContext.privileged: true` unless needed — causes driver path confusion; prefer `nvidia.com/gpu: 1` resource request.

**Warning signs:**
- `kubectl logs <gpu-pod>`: `Failed to initialize NVML`
- `kubectl describe pod <gpu-pod>`: `RunContainerError` with `libnvidia-ml.so.1: file exists`
- Works on native Linux host, fails in WSL

**Phase to address:**
GPU-smoke-test phase + GPU-install phase (verify toolkit >= 1.17)

**Source:**
- https://github.com/NVIDIA/nvidia-container-toolkit/issues/289
- https://github.com/NVIDIA/nvidia-container-toolkit/issues/672
- https://docs.nvidia.com/cuda/wsl-user-guide/index.html
- https://github.com/microsoft/WSL/issues/13773

---

### Pitfall 13: RTX 5090 sm_120 → PyTorch stable wheels unusable; smoke-test must stay framework-free

**What goes wrong:**
The starter already flags this. Specifics of the ecosystem state as of 2025-2026:
- PyTorch stable (2.6 - 2.9 stable) only advertises `sm_50 sm_60 sm_61 sm_70 sm_75 sm_80 sm_86 sm_90`. Running on RTX 5090 emits warning then falls back to CPU (or crashes with "no kernel image is available for execution on the device" RuntimeError).
- PyTorch nightly `cu128` builds started including sm_120 progressively through 2025; `torch==2.9.0+cu128` nightlies from late 2025 work for most users on RTX 5090. See pytorch/pytorch#159207 and pytorch/pytorch#167244.
- TensorRT, cuDNN, cuBLAS, NCCL: all needed ≥ their sm_120-aware releases (CUDA 12.8+ ecosystem).
- Building PyTorch from source with `TORCH_CUDA_ARCH_LIST="12.0"` works but takes 1-2 hours and is not a "reproducible in 20 minutes" option.

**Why it happens:**
PTX forward-compat covers many cases but not Blackwell's new instructions. Vendors must explicitly add sm_120 to `TORCH_CUDA_ARCH_LIST` in the wheel build. This lag is typical for a new architecture; it will close by mid-2026.

**How to avoid:**
- Smoke-test uses `nvcr.io/nvidia/cuda:12.8.0-base-ubuntu22.04` running ONLY `nvidia-smi`. No PyTorch, no TensorFlow, no CUDA samples. This is starter's plan; document rigorously in `docs/gpu-notes.md`.
- If a later milestone adds framework workloads, pin to PyTorch nightly index URL: `pip install --pre torch --index-url https://download.pytorch.org/whl/nightly/cu128`
- Document the "PyTorch ready for sm_120?" check as a manual step: look at https://download.pytorch.org/whl/nightly/cu128/torch/ and verify a recent wheel exists.

**Warning signs:**
- User reports "GPU works but PyTorch doesn't see it" — check `python -c "import torch; print(torch.cuda.get_arch_list())"` for `sm_120` presence.
- `UserWarning: NVIDIA GeForce RTX 5090 with CUDA capability sm_120 is not compatible with the current PyTorch installation`

**Phase to address:**
Scoping decision (v1 out-of-scope for frameworks; documented in `docs/gpu-notes.md`)

**Source:**
- https://github.com/pytorch/pytorch/issues/159207
- https://github.com/pytorch/pytorch/issues/167244
- https://forums.developer.nvidia.com/t/rtx-5090-not-working-with-pytorch-and-stable-diffusion-sm-120-unsupported/338015
- https://discuss.vllm.ai/t/vllm-on-rtx5090-working-gpu-setup-with-torch-2-9-0-cu128/1492

---

### Pitfall 14: asdf v0.16 Go rewrite breaks PATH precedence for users migrating from v0.15

**What goes wrong:** [NEW]
Starter pins asdf-managed tools. But asdf v0.16 (released early 2025) is a Go-binary rewrite — totally different shim mechanism:
- v0.15: `. ~/.asdf/asdf.sh` sourced a shell function that manipulated `PATH` at every shell init.
- v0.16: `asdf` is a static binary. User must manually add `${ASDF_DATA_DIR:-$HOME/.asdf}/shims` to `$PATH` **before** other tool dirs (like `/usr/local/bin`). The shell integration source line is REMOVED.

Migration failure: user installs v0.16 on top of v0.15, keeps the old `. ~/.asdf/asdf.sh` line, and nothing works — `kubectl` still resolves to `/usr/local/bin/kubectl` because shims are never in PATH.

**Why it happens:**
v0.16 deliberately removed the shell function because the new Go binary is fast enough to not need caching via sourced functions. The upgrade guide is NOT backward-compatible; old `.bashrc`/`.zshrc` init lines become no-ops.

**How to avoid:**
- `install-tools.sh` writes shell-init snippet explicitly:
  ```bash
  # For bash
  echo 'export PATH="${ASDF_DATA_DIR:-$HOME/.asdf}/shims:$PATH"' >> "$HOME/.bashrc"
  # For zsh
  echo 'export PATH="${ASDF_DATA_DIR:-$HOME/.asdf}/shims:$PATH"' >> "$HOME/.zshrc"
  ```
- Pin asdf to a specific version in `.tool-versions` (e.g., `asdf 0.16.5`) — reproducibility.
- Preflight probe: `command -v kubectl` must resolve under `$HOME/.asdf/shims/kubectl`, NOT `/usr/local/bin/kubectl`. Starter's preflight already does `asdf which kubectl` check — extend to emit a FAIL (not INFO) if system-kubectl wins PATH.
- After every plugin install, run `asdf reshim <plugin>` — auto-reshim has known bugs in 0.16.5 (asdf-vm/asdf#2023).

**Warning signs:**
- `which kubectl` returns `/usr/local/bin/kubectl` instead of `$HOME/.asdf/shims/kubectl`
- `kubectl version --client` shows a version different from `.tool-versions`
- Starter's `info "kubectl is installed outside asdf"` fires

**Phase to address:**
Tool-install phase (install-tools.sh) + preflight phase (upgrade to FAIL)

**Source:**
- https://asdf-vm.com/guide/upgrading-to-v0-16.html
- http://stratus3d.com/blog/2025/02/03/asdf-has-been-rewritten-in-go/
- https://github.com/asdf-vm/asdf/issues/2023
- https://github.com/asdf-vm/asdf/blob/master/CHANGELOG.md

---

### Pitfall 15: kubectl v1.34 against k3s v1.34.6 — MUST also handle etcd 3.5→3.6 migration blocker if upgrading from an older k3s

**What goes wrong:** [NEW]
Standard kubectl version skew policy: kubectl N±1 against apiserver N is supported. kubectl 1.33, 1.34, 1.35 work against k3s v1.34.6. kubectl 1.32 or 1.36 will work for most operations but some CRD field paths / server-side apply edge cases break.

**More critical, specific to k3s v1.34 series: etcd 3.5→3.6 upgrade trap.** Per k3s release notes, there is no safe path from etcd 3.5 to 3.6 except via v3.5.26 first — skipping that intermediate step causes "zombie members" to rejoin consensus and the cluster loses quorum. If anyone ever upgrades an existing k3s cluster from an older line to v1.34, this is catastrophic.

**Why it happens:**
- kubectl skew: client parses apiserver's OpenAPI spec; newer apiserver fields unknown to older client cause `unknown field` errors on `kubectl apply`.
- etcd: k3s v1.34 embeds etcd 3.6 which refuses to accept legacy 3.5 cluster member records unless the cluster was first stepped up to etcd v3.5.26.

**How to avoid:**
- Pin kubectl to `1.34.x` in `.tool-versions` (exact match with k3s line is zero-friction).
- For v1 (greenfield — no existing cluster to upgrade), the etcd trap does NOT apply, but **document it prominently** in `docs/rebuild-runbook.md` under "Upgrading to a newer k3s line in a future milestone".
- `task destroy` → `task rebuild` bypasses the upgrade path entirely; this is the reason the starter scorched-earth model is elegant here.

**Warning signs:**
- `kubectl apply` returns `error validating data: unknown field "spec.xxx"` on a manifest that works in CI
- After k3s upgrade (future milestone): etcd logs show `member ... not found in cluster` or repeated leader elections

**Phase to address:**
Tool-install phase (pin kubectl=1.34.x) + docs (etcd migration note in rebuild-runbook.md)

**Source:**
- https://kubernetes.io/releases/version-skew-policy/
- https://docs.k3s.io/release-notes/v1.34.X
- https://github.com/k3s-io/k3s/releases/tag/v1.34.6+k3s1

---

### Pitfall 16: `systemd-resolved` stub resolver (127.0.0.53) leaks into Docker containers, breaking CoreDNS upstream lookups

**What goes wrong:** [NEW]
Ubuntu 24.04 defaults to `systemd-resolved`, which symlinks `/etc/resolv.conf` → `/run/systemd/resolve/stub-resolv.conf` pointing at `127.0.0.53`. Docker reads `/etc/resolv.conf` when launching containers and propagates `127.0.0.53` as the container's upstream DNS. Inside a container, `127.0.0.53` is the container's own loopback — nothing listens. CoreDNS pod upstream queries fail; every `externalName` Service, every `git clone github.com`, every image pull from a non-cached registry times out.

**Why it happens:**
systemd-resolved's stub design assumes resolution happens on the host. Docker was designed before systemd-resolved was default; it still naively copies `/etc/resolv.conf`. Docker detects this loopback case sometimes (and substitutes `8.8.8.8`) but the detection is unreliable in WSL2.

**How to avoid:**
- Option A (recommended): Configure Docker daemon to use real DNS servers via `/etc/docker/daemon.json`:
  ```json
  { "dns": ["1.1.1.1", "8.8.8.8"] }
  ```
  Document that the user can change these; `install-docker.sh` applies safe defaults.
- Option B: Point Docker at the real upstream resolv.conf:
  ```json
  { "dns-opts": ["ndots:1"] }
  ```
  plus bind-mount `/run/systemd/resolve/resolv.conf` for daemon startup.
- Option C: Disable systemd-resolved stub listener in `/etc/systemd/resolved.conf` (`DNSStubListener=no`) then relink `/etc/resolv.conf` to `/run/systemd/resolve/resolv.conf`.
- Preflight probe: `docker run --rm alpine nslookup github.com | head -5` — if it fails or shows `127.0.0.53`, flag.

**Warning signs:**
- `kubectl -n kube-system logs coredns-...` shows `no such host` for upstream domains
- Image pulls time out: `docker pull nginx` hangs
- `cat /etc/resolv.conf` on host shows `nameserver 127.0.0.53`

**Phase to address:**
Docker-install phase (install-docker.sh writes daemon.json with explicit `dns`)

**Source:**
- https://cr0x.net/en/docker-dns-systemd-resolved-fixes/
- https://alex-ber.medium.com/dns-resolution-service-inside-docker-container-on-wsl2-072a24d873f6
- https://github.com/microsoft/WSL/issues/10994

---

### Pitfall 17: `docker system prune` destroys the CUDA build cache — `task destroy` must be surgical

**What goes wrong:** [NEW]
Starter requires `task destroy` to NOT prune build cache (to keep the sub-15-min rebuild target). Specific prune-flag behavior:
- `docker system prune` (no flag): removes stopped containers, unused networks, dangling images, **unused build cache**. DESTRUCTIVE to CUDA layer cache.
- `docker system prune -a`: above, plus ALL unused images (not just dangling). EVEN MORE DESTRUCTIVE.
- `docker system prune --volumes`: above, plus unused volumes.
- `docker container prune`: only stopped containers — SAFE for build cache.
- `docker network prune`: only unused networks — SAFE.
- `docker image prune`: dangling images — SAFE for **named** images (like `k3d-cuda:v1.34.6`) which have tags.
- `docker builder prune`: build cache ONLY — must NOT run in `task destroy`.
- `docker buildx prune --keep-storage=10GB`: CAN run, preserves most-used cache entries.

**Why it happens:**
`docker system prune` is the "one-shot cleanup" command everyone reaches for. Its default behavior pruning build cache is easy to miss; without that cache, the CUDA image rebuild is 5-10 min depending on network and disk.

**How to avoid:**
`scripts/delete-clusters.sh` (called by `task destroy`) uses only surgical commands:
```bash
for c in hub-flux spoke-ml spoke-apps; do k3d cluster delete "$c" 2>/dev/null || true; done
docker network rm k8s-net 2>/dev/null || true
docker container prune -f  # safe
# NEVER: docker system prune
# NEVER: docker builder prune
```
Starter's `task destroy` must never call `docker system prune` or `docker builder prune`. Add a pre-commit check for `system prune` literal in scripts/.

**Warning signs:**
- `task rebuild` after `task destroy` takes >15 minutes
- `docker system df` after destroy shows `Build Cache` reclaimable: 0B

**Phase to address:**
Destroy-phase script (`scripts/delete-clusters.sh`) + lint (pre-commit rejects `docker system prune` in scripts)

**Source:**
- https://docs.docker.com/reference/cli/docker/system/prune/
- https://docs.docker.com/build/cache/garbage-collection/
- https://docs.docker.com/reference/cli/docker/builder/prune/

---

### Pitfall 18: `spec.kubeConfig` Secret key mismatch — controllers silently skip remote reconciliation

**What goes wrong:** [NEW]
Flux's `.spec.kubeConfig.secretRef` requires the kubeconfig content be stored under a specific key. The default key name looked up is `value.yaml`. If the Secret stores the kubeconfig under a different key (common mistake: `config`, `kubeconfig`, or plain `value`), the controller does NOT fail loudly — it can log `secret key not found` and fall back to the in-cluster SA, reconciling into the **hub** cluster instead of the spoke.

**Why it happens:**
Flux docs specify the key is `value.yaml` (or `value`) but tutorials often use different conventions. Fallback-to-in-cluster behavior is a footgun.

**How to avoid:**
- `register-spokes.sh` creates the Secret with exactly the right key:
  ```bash
  kubectl create secret generic spoke-ml-kubeconfig \
    -n flux-system \
    --from-file=value.yaml=/tmp/spoke-ml.kubeconfig
  ```
- Starter already specifies `key: value.yaml` — call this out in the script's inline comments as load-bearing.
- In the Kustomization manifest, use:
  ```yaml
  spec:
    kubeConfig:
      secretRef:
        name: spoke-ml-kubeconfig
        key: value.yaml   # explicit, even though "value.yaml" is the default
  ```
- `health-check.sh`: verify hub's Kustomizations targeting spokes list the spoke's node names (not hub's) in `.status.inventory`. If hub nodes leak in, reconciliation is going to the wrong cluster.

**Warning signs:**
- Spoke Kustomization reports `Ready: True` but `kubectl --context spoke-ml get <resource>` shows nothing deployed
- The same resources appear deployed in hub-flux
- `kubectl logs -n flux-system kustomize-controller-... | grep "secret key"` shows `kubeConfig secret key not found`

**Phase to address:**
Spoke-registration phase (register-spokes.sh) + health-check phase (inventory probe)

**Source:**
- https://fluxcd.io/flux/components/kustomize/kustomizations/
- https://github.com/fluxcd/flux2-hub-spoke-example
- https://fluxcd.io/flux/installation/configuration/multitenancy/

---

## Moderate Pitfalls

### Pitfall 19: Spoke ServiceAccount not in `flux-system` namespace → impersonation fails silently

**What goes wrong:**
If `.spec.serviceAccountName` is also set alongside `.spec.kubeConfig`, Flux looks for that SA in the **spoke** cluster, in a namespace matching the Kustomization's namespace on the **hub**. Mismatch → `forbidden: cannot impersonate serviceaccount`.

**How to avoid:**
For v1, do NOT combine `kubeConfig` with `serviceAccountName` — rely on the cluster-admin SA embedded in the kubeconfig itself. Document this as "hub impersonates full cluster-admin; tighten in a later milestone".

**Phase to address:**
Spoke-registration phase (docs)

**Source:** https://fluxcd.io/flux/components/kustomize/kustomizations/

---

### Pitfall 20: k3d image pull `docker.io` rate limit during parallel cluster creation

**What goes wrong:**
Creating 3 clusters in quick succession pulls `rancher/k3s:v1.34.6-k3s1` three times if Docker didn't cache it yet. Unauthenticated pulls from docker.io are rate-limited to 100/6h per IP. Corporate NAT with many users hits the limit.

**How to avoid:**
- `scripts/create-clusters.sh`: pull the image ONCE first (`docker pull rancher/k3s:v1.34.6-k3s1`), then `docker tag` or rely on Docker's content cache for subsequent cluster creations.
- Custom CUDA k3s image for spoke-ml is locally-built → doesn't hit docker.io.

**Phase to address:**
Cluster-creation phase

**Source:** https://k3d.io/v5.8.3/usage/advanced/cuda/

---

### Pitfall 21: WSL2 `hwclock` requires root; running without sudo on boot fails silently

**What goes wrong:**
A `systemd --user` unit running `hwclock -s` fails because `hwclock` needs CAP_SYS_TIME. Users cargo-cult a snippet, put it in `~/.config/systemd/user/`, and see no effect.

**How to avoid:**
Use a system-level unit (`/etc/systemd/system/wsl-clock-sync.service`) with `User=root` and `ExecStart=/sbin/hwclock -s`. Wire to `After=suspend.target` and `After=hibernate.target`.

**Phase to address:**
WSL-config phase

**Source:** https://stuartleeks.com/posts/fixing-clock-skew-with-wsl-2/

---

### Pitfall 22: k3d `--network k8s-net` shared by clusters enables cross-cluster pod traffic but does NOT provide cross-cluster DNS resolution

**What goes wrong:**
Sharing a Docker network lets hub Flux pods reach spoke API servers by container name — but pods in **spoke-apps** cannot resolve `podinfo.default.svc.cluster.local` from **spoke-ml** via standard cluster DNS. Each cluster has its own CoreDNS and `10.43.0.10`-style ClusterIP; they do not federate.

**How to avoid:**
Document the scope: `k8s-net` shared network enables **hub → spoke apiserver** traffic only, NOT **cross-cluster service discovery**. Starter architecture is correct but this limitation deserves a paragraph in `docs/architecture.md`.

**Phase to address:**
Docs phase (architecture.md)

**Source:**
- https://github.com/k3d-io/k3d/discussions/1015
- https://github.com/k3d-io/k3d/issues/111

---

### Pitfall 23: k3s v1.34.6 embeds CoreDNS 1.14.2 — any custom CoreDNS ConfigMap patching must account for the new CoreDNS config syntax

**What goes wrong:** [NEW]
k3s v1.34.6 bumped CoreDNS to 1.14.2. If the user applies a CoreDNS ConfigMap patch (e.g., for custom upstream `forward` plugin) copied from an older blog, certain directives behave differently (e.g., `loop` detection stricter).

**How to avoid:**
If `task fix-dns` or other scripts modify the CoreDNS ConfigMap, base patches on the k3s v1.34.6 default: `kubectl -n kube-system get cm coredns -o yaml > /tmp/coredns-default.yaml` and diff.

**Phase to address:**
Operations phase (if any CoreDNS patching is introduced)

**Source:** https://github.com/k3s-io/k3s/releases/tag/v1.34.6+k3s1

---

### Pitfall 24: `nvidia-ctk runtime configure` with `--set-as-default` also rewrites `daemon.json` — existing Docker daemon config is silently merged, sometimes incorrectly

**What goes wrong:** [NEW]
`nvidia-ctk runtime configure --runtime=docker --set-as-default` edits `/etc/docker/daemon.json` in place. If the file had custom `dns`, `bip`, `mtu`, or `insecure-registries` keys, nvidia-ctk's merger can drop them depending on toolkit version.

**How to avoid:**
- Back up `daemon.json` before running nvidia-ctk: `install-nvidia-container-toolkit.sh` copies to `/etc/docker/daemon.json.bak.$(date +%s)` first.
- After running `nvidia-ctk runtime configure`, diff the result and re-merge custom keys.
- Pin `nvidia-container-toolkit` >= 1.17 which has a safer merger.

**Phase to address:**
GPU-install phase

**Source:**
- https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html
- https://github.com/NVIDIA/nvidia-container-toolkit/issues/631

---

### Pitfall 25: k3s v1.34 auto-detects the NVIDIA runtime and adds it to containerd config → conflicts with a hand-rolled `config.toml.tmpl`

**What goes wrong:** [NEW]
k3s v1.32+ scans for NVIDIA runtime binaries in the node image and adds a `[plugins.cri.containerd.runtimes.nvidia]` block automatically. If the custom `config.toml.tmpl` already defines that block, k3s might generate duplicate definitions or fail to load containerd config.

**How to avoid:**
- In the custom `config.toml.tmpl`, ONLY set `default_runtime_name = "nvidia"` under `[plugins.cri.containerd]` and trust k3s to auto-add the runtime block. Do NOT hand-author the `runtimes.nvidia` block.
- Verify: after cluster start, `docker exec k3d-spoke-ml-server-0 cat /var/lib/rancher/k3s/agent/etc/containerd/config.toml | grep -A5 'runtimes.nvidia'` shows exactly one block.

**Phase to address:**
Image-build phase (Dockerfile.k3s-cuda)

**Source:**
- https://docs.k3s.io/advanced
- https://github.com/k3s-io/k3s/issues/10034

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Cluster-admin SA in remote kubeconfig Secret | Zero RBAC setup per spoke | Hub compromise = all spokes compromised | v1 lab only; real deployments use namespace-scoped SA + impersonation |
| `GITHUB_TOKEN` PAT bootstrap | Simplest Flux bootstrap path | PAT rotation is manual; public-repo leak risk | v1 lab; migrate to GitHub App before first real secret |
| Token stored in `flux-system` Secret after bootstrap | Flux polls Git without external auth | Separate source of truth from `.env`; easy to forget to rotate | v1 lab; GitHub App auth uses short-lived tokens |
| `--force` on bootstrap | Recover from bad state quickly | Can silently destroy hand-tuned flux-system | Recovery only; document as "last-resort" |
| Hub reconciles to spokes via `k3d-<name>-server-0` DNS | Works with zero DNS plumbing | Breaks on Docker restart (→ `task fix-dns`) | v1 lab; real deployments use stable endpoints or headless services |
| No Flux controllers on spokes (hub-only) | Controllers don't double-up on GPU-spoke RAM | Hub becomes single point of failure for all clusters | v1 lab; spokes get their own Flux in later milestone if scale demands |
| Custom `config.toml.tmpl` for CUDA | Explicit, reviewable | Every k3s upgrade requires re-verifying template against new default | Pinned k3s line; re-check when upgrading |
| Ignore PyTorch for v1 smoke-test | Avoids nightly-wheel coupling | Cannot actually run ML workloads in v1 | Per starter scope; frameworks deferred to later milestone |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| WSL2 + Docker Engine | Enabling `networkingMode=mirrored` for "cleaner" Windows↔WSL networking | Use NAT mode; mirrored breaks Docker bridge networking |
| Docker + NVIDIA Container Toolkit | Setting `runtime: nvidia` per-container instead of `default-runtime: nvidia` daemon-wide | k3d node containers require daemon-level `default-runtime` because k3d doesn't expose per-container runtime flag |
| k3d + NVIDIA | Using stock `rancher/k3s:v1.34.6-k3s1` (Alpine-based) with `--gpus all` | Build custom image FROM `nvcr.io/nvidia/cuda:12.8.0-base-ubuntu22.04` with k3s binary and nvidia-container-toolkit |
| Flux bootstrap + GitHub | Using `--token-auth` and committing `.env` | Use GitHub App (Flux 2.5+) with short-lived tokens; if PAT, ensure `.env` is gitignored BEFORE first commit |
| Flux Kustomization `.spec.kubeConfig` | Using Secret key `kubeconfig` or `config` | Use key `value.yaml` (Flux default) and set `.spec.kubeConfig.secretRef.key: value.yaml` explicitly |
| asdf + shell init | Sourcing `asdf.sh` (v0.15 style) after v0.16 install | Manually add `${ASDF_DATA_DIR:-$HOME/.asdf}/shims` to `$PATH` at front |
| systemd-resolved + Docker | Leaving `/etc/resolv.conf` pointing at `127.0.0.53` | Set `dns` in `/etc/docker/daemon.json` explicitly |
| k3s + etcd (future upgrade) | Jumping k3s versions that cross etcd 3.5→3.6 | Step through v3.5.26 first OR scorched-earth rebuild |

---

## Performance Traps

(Performance is secondary for a local lab; these are the ones that matter for the < 20-minute rebuild target.)

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Pulling k3s image per cluster | 30s × 3 = 90s wasted on first run | Pre-pull in `create-clusters.sh` before any `k3d cluster create` | Always, on first run |
| Rebuilding CUDA image on every `task destroy` | 5-10 min wasted per rebuild | Never call `docker builder prune` or `docker system prune` in destroy | Every rebuild if cache is pruned |
| k3d LoadBalancer per cluster uses pause containers | 30MB RAM × 3 = 90MB | Accept — too small to optimize | Irrelevant at 52GB RAM |
| CoreDNS lookup loops via `127.0.0.53` | Pod startup hangs for 5-30s per DNS lookup | daemon.json `"dns": [...]` set by install-docker.sh | When systemd-resolved is the resolv.conf source |
| `flux reconcile` full sweep on every file change | 2-5s extra delay per Kustomization | Use `spec.interval: 5m` + `flux reconcile ks <name>` on-demand for dev loop | Whenever a large monorepo is reconciled |

---

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| `.env` with `GITHUB_TOKEN` committed to public repo | PAT exfiltrated in seconds by bot; repo poisoning via Flux | `.gitignore` enforces; `gitleaks` pre-commit hook; GitHub secret scanning alerts |
| Spoke kubeconfig Secret committed to git as plain YAML | Cluster-admin leak; attacker can deploy to spokes directly | Kubeconfig only generated on demand by `register-spokes.sh` and `kubectl apply`-ed from a temp file; never committed |
| `--insecure-kubeconfig-tls` or `--insecure-skip-tls-verify` on hub Flux | MITM of hub→spoke traffic; attacker can inject manifests | Fix TLS SAN properly via `--tls-san` (Pitfall 6); never use insecure flags |
| `kubeconfig` with long-lived token (no expiry) in Secret | Lost token = permanent compromise vector | Use `kubectl create token` with explicit `--duration=24h`; rotate via CronJob or `task rotate-kubeconfigs` |
| Cluster-admin ClusterRoleBinding for Flux SA on spoke | Over-privileged; Flux can delete everything | v1 lab OK; later milestone: use `edit` cluster role + namespace-scoped RoleBindings |
| docker.sock bind-mounted into any container | Container escape = root on host | Never mount `/var/run/docker.sock` into cluster pods; document this explicitly in `docs/architecture.md` |
| `NVIDIA_DRIVER_CAPABILITIES=all` in pod spec | Exposes non-GPU capabilities (display, utility) | Stick to `NVIDIA_VISIBLE_DEVICES=all NVIDIA_DRIVER_CAPABILITIES=compute,utility` |
| Committed `.tool-versions` with `GITHUB_TOKEN` via env-plugin | PAT encoded in plain text, committed | Never use asdf env-plugin for tokens; `.env` only |

---

## UX Pitfalls

(Lab-audience UX: the author, plus anyone mirroring on similar hardware.)

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| `task rebuild` silent for 10+ minutes during CUDA build | User thinks it's hung, kills it, now rebuild is in unknown state | Progress logging per stage; `docker buildx build --progress=plain` |
| Confirmations on destructive tasks only via `$?` | User double-bangs `task destroy` via history — cluster gone | Interactive confirm (`read -r -p "Type 'yes' to destroy: "`); starter spec already requires this |
| `task preflight` exit 0 with warnings, user ignores warnings | Failure occurs 5 steps later from an unheeded warning | Color output + final summary block (prereqs.sh already does this); consider `task preflight-strict` that fails on warnings |
| Error messages that don't mention the phase | User sees `Error: connection refused` without knowing which of 6 scripts produced it | Every script prefixes errors with its own tag: `[create-clusters] ERROR: ...` |
| `fix-dns` not self-documenting | User doesn't know when to run it | Health-check outputs `→ Run 'task fix-dns' to resolve` if stale-DNS probe fires |

---

## "Looks Done But Isn't" Checklist

Things that appear to be working but are hiding failures. These are the checks that belong in `health-check.sh`.

- [ ] **Clusters created:** `k3d cluster list` shows all 3 → Verify: ALL nodes `Ready` via `kubectl --context k3d-<name> get nodes`. A cluster can "exist" with nodes `NotReady`.
- [ ] **Flux installed:** `flux check` passes → Verify: `flux get kustomizations -A` shows root `flux-system` `Ready: True`.
- [ ] **Flux reconciling spokes:** Spoke Kustomizations exist → Verify: `.status.inventory` on each spoke Kustomization lists spoke node names, NOT hub nodes (catches the key-name mismatch from Pitfall 18).
- [ ] **GPU visible on spoke-ml:** `kubectl describe node` mentions GPU → Verify: `capacity.nvidia.com/gpu` > 0 AND `allocatable.nvidia.com/gpu` > 0.
- [ ] **GPU pod works:** Smoke-test pod in Running state → Verify: `kubectl logs <gpu-pod>` shows `nvidia-smi` output with the RTX 5090 name and driver 570+.
- [ ] **Hub can resolve spoke DNS:** From hub Flux controller pod, `nslookup k3d-spoke-ml-server-0` returns current container IP (catches Pitfall 11 staleness).
- [ ] **TLS SAN correct:** `openssl s_client -connect k3d-spoke-ml-server-0:6443 -servername k3d-spoke-ml-server-0 </dev/null | openssl x509 -noout -text | grep 'DNS:k3d-spoke-ml-server-0'` returns a match.
- [ ] **`.env` not committed:** `git ls-files | grep -E '(^|/)\.env$'` returns empty.
- [ ] **Docker default-runtime is nvidia:** `docker info | grep 'Default Runtime'` returns `nvidia`.
- [ ] **asdf shims win PATH:** `command -v kubectl` returns `$HOME/.asdf/shims/kubectl`.
- [ ] **Clock skew acceptable:** `| date_diff_host_vs_wsl | < 60s`.
- [ ] **Build cache preserved:** `docker system df` after `task destroy` still shows CUDA image layers.

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Mirrored mode breaks bridge (P1) | LOW | Edit `.wslconfig` to NAT mode; `wsl --shutdown`; re-start Docker, `task rebuild` |
| iptables/nftables mismatch (P2) | LOW | `sudo update-alternatives --set iptables /usr/sbin/iptables-legacy`; `sudo systemctl restart docker` |
| Docker Desktop conflict (P3) | MEDIUM | Disable Desktop WSL integration; remove stale artifacts; reinstall Docker Engine natively |
| Clock skew (P4) | LOW | `sudo hwclock -s` |
| Hybrid cgroups (P5) | LOW | Remove `kernelCommandLine=systemd.unified_cgroup_hierarchy=...` from `.wslconfig`; `wsl --shutdown` |
| TLS SAN missing (P6) | MEDIUM | `task destroy` + `task rebuild` (can't edit cert on running cluster safely); OR delete server certs + restart k3s for regen |
| GPU not detected in k3d (P7) | MEDIUM | Verify `daemon.json` has `default-runtime: nvidia`; rebuild custom k3s-CUDA image; recreate spoke-ml |
| Bootstrap regen reverted edit (P8) | LOW | Move edit to `kustomization.yaml` as a patch; re-bootstrap |
| Bootstrap path changed (P9) | HIGH | Manually restore old Kustomization; re-reconcile; OR scorched-earth `task rebuild` |
| GITHUB_TOKEN leaked (P10) | HIGH | Revoke PAT on GitHub; rotate in-cluster Secret; `git filter-repo`; force-push; audit what was reconciled while compromised |
| CoreDNS stale NodeHosts (P11) | LOW | `task fix-dns` (stop/start hub) |
| libnvidia-ml mount error (P12) | LOW | Use `base` CUDA variant instead of `runtime`/`devel`; upgrade nvidia-container-toolkit to ≥ 1.17 |
| PyTorch sm_120 unsupported (P13) | N/A | Out of scope for v1 |
| asdf PATH wrong (P14) | LOW | Fix shell-init file; `exec $SHELL` |
| kubectl skew (P15) | LOW | Install kubectl 1.34.x via asdf |
| systemd-resolved DNS loop (P16) | LOW | Set `dns` in `/etc/docker/daemon.json`; restart Docker; recreate clusters |
| Build cache destroyed (P17) | MEDIUM | Accept the 5-10 min rebuild; inspect `scripts/delete-clusters.sh` for stray prune commands |
| Wrong Secret key (P18) | LOW | Re-create Secret with key `value.yaml`; `flux reconcile ks <spoke>` |

---

## Pitfall-to-Phase Mapping

Starter's phases are inferred from `FUNCTIONAL REQUIREMENTS` in starter.md:
- **P-WSL** = WSL config phase (ships `.wslconfig` template, `wsl.conf`, hwclock unit)
- **P-Docker** = install-docker.sh
- **P-GPU** = install-nvidia-container-toolkit.sh + images/Dockerfile.k3s-cuda
- **P-Tools** = install-tools.sh (asdf)
- **P-Preflight** = scripts/preflight.sh (port of prereqs.sh)
- **P-Cluster** = scripts/create-clusters.sh
- **P-Bootstrap** = scripts/bootstrap-flux.sh
- **P-Register** = scripts/register-spokes.sh
- **P-Health** = scripts/health-check.sh
- **P-Destroy** = scripts/delete-clusters.sh
- **P-Repo** = repo hygiene (gitignore, .env.example, pre-commit)
- **P-Docs** = docs/ (ADRs, runbooks, gpu-notes)

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| P1 mirrored mode | P-WSL + P-Preflight | Bridge-container curl probe passes |
| P2 nftables | P-Docker | `docker network create k8s-net` succeeds |
| P3 Desktop conflict | P-Docker + P-Preflight | `docker info` points at native socket |
| P4 clock skew | P-WSL + P-Health | `| host_clock - wsl_clock | < 60s` |
| P5 hybrid cgroups | P-WSL + P-Preflight | `/sys/fs/cgroup` is `cgroup2fs` |
| P6 TLS SAN | P-Cluster + P-Health | openssl probe finds DNS SAN |
| P7 GPU runtime | P-GPU + P-Cluster | `nvidia.com/gpu > 0` on spoke-ml |
| P8 bootstrap edits | P-Docs | Re-bootstrap leaves kustomization.yaml patches intact |
| P9 bootstrap path | P-Bootstrap + P-Docs | Bootstrap script hardcodes path; docs warn |
| P10 token leak | P-Repo + P-Docs | gitleaks pre-commit; `.env` in gitignore before first commit |
| P11 CoreDNS stale | P-Operations (fix-dns) + P-Health | hub-pod `nslookup` returns current IP |
| P12 libnvidia mount | P-GPU + P-Docs | Smoke-test uses `base` CUDA variant |
| P13 PyTorch sm_120 | P-Docs (scope) | N/A for v1 |
| P14 asdf PATH | P-Tools + P-Preflight | `command -v kubectl` in asdf shims dir |
| P15 kubectl skew | P-Tools | kubectl 1.34.x pinned |
| P16 systemd-resolved | P-Docker | `daemon.json` has explicit `dns` |
| P17 build cache | P-Destroy | `delete-clusters.sh` has no `system prune` |
| P18 Secret key | P-Register + P-Health | Spoke inventory has spoke nodes, not hub |
| P19 SA namespace | P-Register + P-Docs | Doc says "don't combine kubeConfig + serviceAccountName in v1" |
| P20 docker.io rate limit | P-Cluster | Pre-pull before multi-cluster create |
| P21 hwclock as user | P-WSL | systemd unit uses User=root |
| P22 cross-cluster DNS | P-Docs | architecture.md states the scope |
| P23 CoreDNS 1.14.2 | P-Operations (if any patching) | N/A unless patching |
| P24 daemon.json merge | P-GPU | Backup before `nvidia-ctk runtime configure` |
| P25 k3s auto runtime | P-GPU (image build) | Containerd config has exactly one `runtimes.nvidia` block |

---

## Cross-Subsystem Cluster Summary

For easy reference during phase planning — pitfalls grouped by subsystem:

**WSL2 / Networking:** P1 (mirrored mode), P4 (clock skew), P5 (cgroups), P16 (systemd-resolved)

**Docker Engine:** P2 (nftables), P3 (Desktop conflict), P17 (system prune destroys cache)

**k3d / k3s:** P6 (TLS SAN), P11 (CoreDNS stale), P20 (docker.io rate limit), P22 (cross-cluster DNS scope), P23 (CoreDNS 1.14.2)

**Flux:** P8 (bootstrap hand-edits nuance), P9 (bootstrap path immutability), P10 (token leak + in-cluster rotation), P18 (Secret key), P19 (SA namespace)

**GPU (NVIDIA, RTX 5090):** P7 (k3d GPU stack), P12 (CDI mount error), P13 (PyTorch sm_120), P24 (daemon.json merge), P25 (k3s auto-runtime)

**asdf / Tools:** P14 (v0.16 PATH), P15 (kubectl skew)

**Repo hygiene / Secrets:** P10 (token leak), and related security mistakes table

---

## Sources

**Starter risks (acknowledged, extended):**
- `/home/rich/code/gsd/karyon/starter.md` — KNOWN RISKS section
- `/home/rich/code/gsd/karyon/.planning/PROJECT.md` — Context + Constraints

**WSL2 / Docker / Networking:**
- https://github.com/microsoft/WSL/issues/10494 (mirrored → Docker ports)
- https://github.com/microsoft/WSL/issues/10683 (mirrored → container port access from Windows)
- https://github.com/microsoft/WSL/issues/10926 (mirrored → Docker can't reach Windows)
- https://github.com/microsoft/WSL/issues/11758 (mirrored + bridge = unreachable)
- https://github.com/microsoft/WSL/issues/12578 (mirrored unavailable in some Insider builds)
- https://github.com/microsoft/WSL/issues/13013 (Windows → WSL unreachable in mirrored)
- https://github.com/microsoft/WSL/issues/10994 (Docker build breaks DNS)
- https://github.com/moby/moby/issues/48136 (bridge MAC return-path)
- https://github.com/moby/moby/issues/48201 (TCP stall in mirrored)
- https://github.com/microsoft/WSL/issues/6655 (nftables modules missing)
- https://github.com/microsoft/WSL/issues/6662 (hybrid cgroup prohibited)
- https://github.com/microsoft/WSL/issues/9868 (cgroup v2 mount)
- https://docs.docker.com/engine/network/firewall-nftables/
- https://docs.docker.com/desktop/features/wsl/
- https://nickjanetakis.com/blog/install-docker-in-wsl-2-without-docker-desktop
- https://patrickwu.space/2021/03/09/wsl-solution-to-native-docker-daemon-not-starting/
- https://cr0x.net/en/docker-dns-systemd-resolved-fixes/
- https://alex-ber.medium.com/dns-resolution-service-inside-docker-container-on-wsl2-072a24d873f6

**WSL2 clock drift:**
- https://github.com/microsoft/WSL/issues/10006 (megathread)
- https://github.com/microsoft/WSL/issues/8204
- https://github.com/microsoft/WSL/issues/13867
- https://stuartleeks.com/posts/fixing-clock-skew-with-wsl-2/
- https://documentation.ubuntu.com/wsl/latest/explanation/time-sync/
- https://sleeplessbeastie.eu/2023/08/11/how-to-fix-time-inside-ubuntu-on-windows-with-wsl/

**k3d / k3s:**
- https://docs.k3s.io/release-notes/v1.34.X
- https://github.com/k3s-io/k3s/releases/tag/v1.34.6+k3s1
- https://docs.k3s.io/advanced
- https://docs.k3s.io/cli/server
- https://github.com/k3s-io/k3s/issues/2365 (TLS SAN for initial server)
- https://github.com/k3s-io/k3s/issues/6241 (cgroup v2 on RPi)
- https://github.com/k3s-io/k3s/issues/8971 (cpu cgroup v2)
- https://github.com/k3s-io/k3s/issues/9274 (CoreDNS NodeHosts stale)
- https://github.com/k3s-io/k3s/issues/10034 (runtimeClassName)
- https://github.com/k3s-io/k3s/issues/10534 (GPU detection)
- https://github.com/k3d-io/k3d/issues/111 (shared network)
- https://github.com/k3d-io/k3d/issues/1009 (CoreDNS NodeHosts lost)
- https://github.com/k3d-io/k3d/issues/1108 (GPU setup)
- https://github.com/k3d-io/k3d/issues/1112 (CoreDNS loses customization)
- https://github.com/k3d-io/k3d/discussions/1015 (cross-cluster connection)
- https://k3d.io/v5.8.3/usage/advanced/cuda/
- https://github.com/k3d-io/k3d/releases
- https://taozhi.medium.com/k3s-apiserver-unable-to-connect-to-the-server-x509-certificate-is-valid-for-10-43-0-1-8ec1f8c2097f

**Flux:**
- https://fluxcd.io/flux/installation/bootstrap/github/
- https://fluxcd.io/flux/installation/configuration/bootstrap-customization/
- https://fluxcd.io/flux/components/kustomize/kustomizations/
- https://fluxcd.io/flux/installation/configuration/multitenancy/
- https://fluxcd.io/flux/cmd/flux_bootstrap/
- https://fluxcd.io/blog/2025/04/flux-operator-github-app-bootstrap/
- https://github.com/fluxcd/flux2/discussions/1517 (sync path overwrites)
- https://github.com/fluxcd/flux2/discussions/2161 (PAT rotation)
- https://github.com/fluxcd/flux2/discussions/2694 (deploy key migration)
- https://github.com/fluxcd/flux2-hub-spoke-example
- https://github.com/fluxcd/flux2/issues/5543 (SA impersonation)

**NVIDIA / GPU / CUDA / PyTorch:**
- https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html
- https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/cdi-support.html
- https://docs.nvidia.com/cuda/wsl-user-guide/index.html
- https://github.com/NVIDIA/k8s-device-plugin
- https://github.com/NVIDIA/nvidia-container-toolkit/issues/289 (libnvidia-ml mount)
- https://github.com/NVIDIA/nvidia-container-toolkit/issues/271 (WSL driver detect)
- https://github.com/NVIDIA/nvidia-container-toolkit/issues/631 (daemon.json merge warn)
- https://github.com/NVIDIA/nvidia-container-toolkit/issues/672 (nvidia-smi not mounted)
- https://github.com/microsoft/WSL/issues/9962 (GPU blocked by OS in Docker)
- https://github.com/microsoft/WSL/issues/13773 (libcuda.so.1 segfault)
- https://github.com/pytorch/pytorch/issues/159207 (sm_120 official support)
- https://github.com/pytorch/pytorch/issues/167244 (sm_120 in official wheels)
- https://forums.developer.nvidia.com/t/rtx-5090-not-working-with-pytorch-and-stable-diffusion-sm-120-unsupported/338015
- https://discuss.vllm.ai/t/vllm-on-rtx5090-working-gpu-setup-with-torch-2-9-0-cu128/1492
- https://medium.com/@panda1100/running-gpu-workloads-on-k3d-cluster-by-using-nvidia-device-plugin-for-k8s-4c4853834075

**asdf:**
- https://asdf-vm.com/guide/upgrading-to-v0-16.html
- http://stratus3d.com/blog/2025/02/03/asdf-has-been-rewritten-in-go/
- https://github.com/asdf-vm/asdf/blob/master/CHANGELOG.md
- https://github.com/asdf-vm/asdf/issues/2023 (auto-reshim broken)
- https://github.com/asdf-vm/asdf/issues/261 (PATH once)
- https://github.com/asdf-vm/asdf/issues/1550 (macOS PATH)
- https://asdf-vm.com/more/faq.html

**kubectl / Kubernetes skew:**
- https://kubernetes.io/releases/version-skew-policy/

**Docker cache / prune:**
- https://docs.docker.com/reference/cli/docker/system/prune/
- https://docs.docker.com/reference/cli/docker/builder/prune/
- https://docs.docker.com/build/cache/garbage-collection/

**Repo hygiene / Secrets:**
- https://github.com/gitleaks/gitleaks
- https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository
- https://snyk.io/articles/state-of-secrets/

---
*Pitfalls research for: Local hub-spoke Flux multi-cluster lab on k3d + WSL2 + NVIDIA RTX 5090*
*Researched: 2026-04-22*
