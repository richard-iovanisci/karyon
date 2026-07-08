# 5. Kubernetes Version Pin (k3s + CUDA)

## Status

Accepted (2026-04-22)

## Context

Two version axes pin together for the karyon lab: the k3s line that runs in
every cluster and the CUDA base image used for the GPU smoke-test on
`spoke-ml`. Both must be reproducible across rebuilds; both have constraints
imposed by the dev box's hardware (RTX 5090 / sm_120 Blackwell).

The k3s pin governs Kubernetes API surface, k3s subsystems (CoreDNS, Traefik,
local-path-provisioner, etc.), and image-tag stability. The CUDA pin governs
which compiled kernels (`sm_*` sets) the smoke-test container can dispatch.

There are two flavors of pin available for k3s: an LTS line (e.g.,
`rancher/k3s:vX.Y.<patch>-k3s1` against the current Kubernetes LTS) and a
"current line" pin (the latest minor that the project is shipping toolchain
support against). For CUDA, NVIDIA's RTX 5090 (Blackwell, sm_120) requires
CUDA 12.8 or newer at the runtime; nothing earlier supports compiled kernels
for sm_120.

## Decision

1. Pin k3s to `rancher/k3s:v1.34.6-k3s1` (Kubernetes 1.34 line, k3s patch 1).
   This is a "current line" pin — NOT LTS. The line tracks current upstream
   Kubernetes, which is the line for which Flux v2.8.x and the helm-controller
   image set ship maintained tooling.
2. Pin the CUDA base image used by the GPU smoke-test to
   `nvcr.io/nvidia/cuda:12.8.0-base-ubuntu22.04`. The custom k3s+CUDA image
   used by `spoke-ml` is FROM `nvidia/cuda:12.8.1-base-ubuntu22.04` (a
   minor-revision newer base).
3. Both pins are checked-in: k3s line in `.tool-versions`-derived references
   and `scripts/create-clusters.sh`; CUDA base in `images/Dockerfile.k3s-cuda`
   and `examples/gpu-smoke-test/job.yaml`.

## Consequences

**Easier:**
- Reproducible cluster behavior across rebuilds; `task rebuild` lands the
  same image every time.
- Flux compatibility is guaranteed for the duration of v1 (Flux v2.8.x ships
  for Kubernetes 1.30..1.35 — the pinned line is comfortably mid-window).
- The CUDA 12.8+ floor unblocks RTX 5090 sm_120 Blackwell GPU support — the
  smoke-test pod's `nvidia-smi` output names a CUDA 12.8 device, which is
  the lowest version that can host sm_120 kernels.

**Harder:**
- "Current line" pins receive no upstream LTS support. When 1.34 approaches
  EOL (~12-18 months out), the pin must be bumped to whatever the current
  line is at that time; the bump policy (trigger, testing steps, migration
  notes) is deferred future work.
- The CUDA 12.8+ floor disqualifies older PyTorch / framework wheels that
  haven't caught up to sm_120 yet. This is why the GPU smoke-test runs only
  `nvidia-smi` — it avoids coupling the lab's health to PyTorch
  nightly availability for sm_120.
- The nvidia-device-plugin had to be pinned to v0.17.4 instead of the
  originally-targeted v0.19.0+ (no stable v0.19.x release compatible with
  Blackwell at pin time). See `../gpu-notes.md`.

**No-change:**
- Helm 3.20.x stays pinned via `.tool-versions`; Helm 4.x migration is out
  of scope.
- Cloud-cluster migration is out of scope;
  the pin is dev-box-bound and not portable to managed Kubernetes.
