# GPU Notes: 3-Part k3d Contract and the RTX 5090 (Blackwell) Floor

The karyon lab runs CUDA workloads on `spoke-ml` via Docker → containerd → k3s
→ Pod. Three configuration knobs must be set CORRECTLY at the same time for
the spoke to advertise `nvidia.com/gpu` capacity. This is the "3-part k3d GPU
contract" — the most common cause of "the cluster is up but no GPU" failures
during early lab setup.

This document also covers the RTX 5090 (Blackwell architecture, sm_120
compiled-kernel set) compatibility floor: CUDA 12.8 or newer at the runtime
is required.

***

## The 3-Part k3d GPU Contract

All three parts must be configured before the lab will surface
`nvidia.com/gpu` to Pod scheduling. If any one is missing, the cluster looks
healthy in `kubectl get nodes` output but
`kubectl --context k3d-spoke-ml describe node` shows zero GPU capacity.

### Part 1: `/etc/docker/daemon.json` sets `default-runtime: nvidia`

`scripts/install-docker.sh` writes a `daemon.json` with the `default-runtime`
key set to `nvidia` and an explicit `dns` array (the DNS array prevents the
container from inheriting `systemd-resolved`'s `127.0.0.53` stub address —
HOST-04). The default-runtime change is what makes every `docker run` —
including the one k3d invokes when it boots a cluster server container —
inherit the NVIDIA Container Toolkit shim.

```bash
# Confirm:
docker info | grep "Default Runtime"     # expected: Default Runtime: nvidia
```

If this line is missing or returns `runc`, the GPU contract is broken at
its foundation.

### Part 2: Ubuntu-base custom k3s+CUDA image (NOT Alpine)

`images/Dockerfile.k3s-cuda` builds an image FROM
`nvidia/cuda:12.8.1-base-ubuntu22.04` with k3s binaries layered in from
`rancher/k3s:v1.34.6-k3s1` as a build stage. The base MUST be Ubuntu (or
another glibc distro): the NVIDIA Container Runtime cannot inject the
`libcuda.so.1` stub into Alpine's musl libc, so a stock Alpine k3s image
will fail to host any CUDA workload.

```bash
# Confirm the image exists locally and was tagged correctly:
docker images | grep karyon/k3s-cuda     # expected: at least one tag
```

### Part 3: containerd `config.toml.tmpl` with `default_runtime_name = "nvidia"`

The custom k3s image bakes a containerd config template at
`/var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl` (see
`images/config.toml.tmpl`). The template sets:

```toml
[plugins."io.containerd.grpc.v1.cri".containerd]
  default_runtime_name = "nvidia"
```

Without this, containerd will use the default `runc` runtime even if Docker
itself launches the k3s server container with `--runtime=nvidia`. The result:
GPU pass-through works at the Docker layer but evaporates inside k3s.

```bash
# Confirm by inspecting a running spoke-ml node:
docker exec k3d-spoke-ml-server-0 cat /var/lib/rancher/k3s/agent/etc/containerd/config.toml \
  | grep default_runtime_name      # expected: default_runtime_name = "nvidia"
```

***

## RTX 5090 (Blackwell, sm_120) Compatibility Floor

The author's dev box has an RTX 5090. Blackwell architecture compiles to the
`sm_120` PTX target. CUDA 12.8 is the **first** release with first-class
sm_120 support in the runtime; any CUDA version earlier than 12.8 cannot
dispatch sm_120 kernels and the GPU smoke-test pod will fail.

**v1 of this project requires CUDA 12.8 or newer at the runtime.** This is
why:

- The custom k3s+CUDA image is FROM `nvidia/cuda:12.8.1-base-ubuntu22.04`
  (the build stage; IMG-01).
- The GPU smoke-test container is `nvcr.io/nvidia/cuda:12.8.0-base-ubuntu22.04`
  (DEP-03).
- The smoke-test runs ONLY `nvidia-smi` (DEP-03). PyTorch / framework workloads
  are explicitly out of scope because most stable PyTorch wheels still need
  nightlies for sm_120 support; coupling lab health to nightly availability is
  not acceptable.

Pinning rationale is documented in
[`adr/0005-kubernetes-version-pin.md`](adr/0005-kubernetes-version-pin.md).

***

## Version override: nvidia-device-plugin v0.17.4

The original target was `nvidia-device-plugin` v0.19.0 or newer, but no
stable v0.19.x release was compatible with RTX 5090 / Blackwell / sm_120 at
pin time; the lab pins to `v0.17.4` instead (see the decision log in
`backlog.md`).

The override is not architectural — it's a "ship-with-what-works" decision.
When a v0.19.x release lands with verified sm_120 support, bump the pin in
`images/device-plugin-daemonset.yaml` (guarded by
`tests/bats/cuda-image-04-device-plugin.bats`).

***

## Failure Modes and What to Check First

| Symptom | First place to look |
|---------|---------------------|
| `kubectl --context k3d-spoke-ml describe node` shows no `nvidia.com/gpu` | Run `bash scripts/preflight.sh` — it covers Parts 1 and 2 of the contract. If preflight is green, exec into the spoke-ml server container and verify Part 3. |
| `nvidia-smi` works on the host but not inside any container | `default-runtime` is wrong or `nvidia-ctk runtime configure` was never run. Re-run `scripts/install-nvidia-container-toolkit.sh`. |
| GPU smoke-test Job loops or `CrashLoopBackOff` | Check Pod logs with `kubectl --context k3d-spoke-ml -n gpu-smoke logs job/nvidia-smi`. CUDA-version mismatch (smoke-test image too old) is the most common cause. |
| Cluster appears `Ready` but DNS to `k3d-spoke-ml-server-0` fails from the hub | Stale CoreDNS NodeHosts; run `task fix-dns`. See [`flux-hub-spoke.md`](flux-hub-spoke.md). |

***

## Cross-References

- Architecture topology: [`architecture.md`](architecture.md)
- Version pin rationale: [`adr/0005-kubernetes-version-pin.md`](adr/0005-kubernetes-version-pin.md)
- WSL2 networking modes: [`wsl-networking.md`](wsl-networking.md)
- Rebuild runbook (incident response): [`rebuild-runbook.md`](rebuild-runbook.md)
