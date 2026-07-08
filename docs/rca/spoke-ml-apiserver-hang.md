# RCA: spoke-ml k3s apiserver hang from a Go-template token in a comment

- **Date observed:** 2026-04-24
- **Date resolved:** 2026-04-24
- **Component:** `karyon/k3s-cuda` node image (`v1.34.6-k3s1-cuda12.8.1`) used by the
  `spoke-ml` k3d cluster on WSL2
- **Severity:** Cluster creation hangs indefinitely; the k3s apiserver never boots

## Summary

The custom CUDA node image bakes a containerd config template,
`images/config.toml.tmpl`, that k3s renders at boot. An explanatory comment in that
template accidentally contained the Go-template action `{{ template "base" . }}` — and
Go templates execute inside comments too. The base containerd template was therefore
rendered twice (once mid-comment, once at the intentional standalone directive),
leaving a stray bare-text line and duplicated TOML sections in the generated
`config.toml`. containerd failed to parse the file and exited, k3s shut down, and k3d
sat in an apiserver probe loop forever. Removing the inline token from the comment
fixed the boot; a static regression test now asserts the token appears exactly once.

## Symptoms

Expected: `k3d cluster create spoke-ml --image karyon/k3s-cuda:v1.34.6-k3s1-cuda12.8.1
--gpus all ...` brings the cluster up in about 20–60 seconds, the node goes `Ready`,
and it advertises `nvidia.com/gpu` capacity of at least 1.

Actual: k3d logs "Starting node 'k3d-spoke-ml-server-0'" and never advances. After 14
minutes the node container is still `Up` but the apiserver inside never comes up.
`docker logs k3d-spoke-ml-server-0` shows only a repeating kubectl probe loop:

```text
E0424 01:04:47 ... memcache.go:265] "Unhandled Error" err="... dial tcp 127.0.0.1:6443:
connect: connection refused"
The connection to the server 127.0.0.1:6443 was refused - did you specify the right host
or port?
```

Reproduction:

```bash
docker network create --driver bridge --subnet 172.30.0.0/16 k8s-net
k3d cluster create spoke-ml \
  --api-port 6444 \
  --network k8s-net \
  --k3s-arg '--tls-san=k3d-spoke-ml-server-0@server:*' \
  --image karyon/k3s-cuda:v1.34.6-k3s1-cuda12.8.1 \
  --gpus all \
  --timeout 3m0s
# Hangs; apiserver never up.
```

Environment: WSL2 (kernel 6.6.87.2), Docker 29.4.1, NVIDIA driver 596.21, RTX 5090.
The image is Ubuntu 22.04 with k3s v1.34.6-k3s1 layered in and `nvidia-ctk` configuring
containerd at build time, plus a baked `config.toml.tmpl` override setting
`default_runtime_name = "nvidia"`.

## Diagnosis path

### A/B isolation

A stock-image cluster on the same host, network, and k3s/k3d versions came up fine:

| Cluster  | Image                      | config.toml override              | `--gpus all` | Result                |
| -------- | -------------------------- | --------------------------------- | ------------ | --------------------- |
| hub-flux | rancher/k3s:v1.34.6-k3s1   | none (k3s default)                | no           | apiserver up in ~20 s |
| spoke-ml | karyon/k3s-cuda:...        | `default_runtime_name = "nvidia"` | yes          | apiserver never up    |

This narrowed the suspects to: (a) the custom base image, (b) the baked
`config.toml.tmpl` override, (c) `--gpus all`.

### Red herring: a concurrent WSL GPU driver regression

Mid-investigation, the host GPU stack itself degraded: `nvidia-smi` on the host failed
with "Failed to initialize NVML: GPU access blocked by the operating system",
`/dev/nvidia*` was absent, and `nvidia-ctk cdi generate` failed with "no driver store
paths found" (the WSL driver-model bridge returned no adapters). This looked related —
any `docker run --gpus all` failed through the same path.

A WSL restart recovered `nvidia-smi`, but `k3d cluster create spoke-ml` **still hung
identically**. Across three states (GPU state unknown, GPU broken, GPU healthy) the
hang was the invariant and host GPU state the variable — so the GPU regression was a
real but separate environmental issue, not the cause.

### Ground truth from inside the hung node

Three hypotheses predicted different log contents: (A) the `default_runtime_name`
override breaks system-pod sandboxing, (B) `--gpus all` makes the nested container
hostile to k3s boot, (C) something else in the custom image breaks k3s before
containerd matters. Exec-ing into a live hung node during a reproduced hang settled it
with none of the predicted signatures:

- k3s itself was starting, but **containerd exited immediately**.
- `/var/lib/rancher/k3s/agent/containerd/containerd.log` held the real failure:
  `Failure unmarshaling TOML ... row=62 column=8 ... expected character =`.
- The rendered `/var/lib/rancher/k3s/agent/etc/containerd/config.toml` showed why: the
  template comment
  `# {{ template "base" . }} pulls in the canonical k3s base template`
  had *executed* the template action inside the comment, splicing the full base
  template into the middle of the comment and leaving the stray bare-text line
  `pulls in the canonical k3s base template` at row 62. The standalone
  `{{ template "base" . }}` directive then rendered the base body a second time,
  duplicating TOML sections. containerd never got far enough for any NVIDIA-runtime
  behavior to matter.

## Root cause

`images/config.toml.tmpl` contained the Go-template action `{{ template "base" . }}`
twice: once intentionally on its own line, and once accidentally inside an explanatory
comment. Go's template engine does not treat TOML comments as inert, so k3s rendered
the base containerd template into the comment and again at the standalone directive.
The generated `config.toml` contained a bare text line plus duplicate sections,
containerd failed to unmarshal it and exited, k3s shut down, and k3d was left in the
apiserver probe loop.

## Eliminated hypotheses

- **WSL GPU driver regression as the primary cause** — after the WSL restart recovered
  `nvidia-smi`, the cluster create still hung identically.
- **`default_runtime_name = "nvidia"` semantics** — once the template-render bug was
  fixed, the cluster booted with the override still in place, RuntimeClass `nvidia`
  existed, and the node reported `nvidia.com/gpu=1`.
- **A corrupt image** — `docker run --runtime=runc` on the same image worked, and the
  baked template matched the source file verbatim.
- **k3s version, k3d version, or the shared docker network** — ruled out by the A/B:
  hub-flux came up fine with identical versions on the same network.

## Fix

Remove the inline `{{ template "base" . }}` token from the explanatory comment in
`images/config.toml.tmpl`, so the base template is rendered exactly once via the
standalone directive. Rebuild `karyon/k3s-cuda:v1.34.6-k3s1-cuda12.8.1`.

## Verification

- Re-running the exact reproduce command brought the cluster up in about 18 seconds.
- `kubectl --context k3d-spoke-ml get nodes -o wide` shows the node `Ready`.
- `kubectl --context k3d-spoke-ml get runtimeclass nvidia` is present.
- The node reports `nvidia.com/gpu` capacity `1`, and the
  `nvidia-device-plugin-daemonset` pod is `1/1 Running`.

## Regression guard

`tests/bats/cuda-image-03-containerd.bats` asserts there is exactly one occurrence of
the base-template token in the baked template and that it appears as a standalone line,
so the comment-execution mistake cannot silently return.
(`KARYON_LIVE_TESTS=1 bats tests/bats/cuda-image-03-containerd.bats` also exercises the
live-image checks after a rebuild.)

## Files changed

- `images/config.toml.tmpl` — inline template token removed from the comment
- `tests/bats/cuda-image-03-containerd.bats` — regression test added
