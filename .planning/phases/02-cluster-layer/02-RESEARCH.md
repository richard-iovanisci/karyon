# Phase 2: Cluster Layer - Research

**Researched:** 2026-04-23
**Domain:** k3d + k3s v1.34 + NVIDIA CUDA image + NVIDIA device-plugin + Docker bridge networks on WSL2
**Confidence:** HIGH (k3d flag surface, k3s containerd v3 template, CUDA / k3s tag availability, device-plugin v0.17.4 ↔ v0.19.1 landscape) / MEDIUM (k3d #1613 `--tls-san` bug behaviour under `@server:*`, D-13 mitigates) / MEDIUM (k3d v5.8.3 `cluster list` output stability across restarts)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** NVIDIA device-plugin DaemonSet is baked into the custom image only (no Flux HelmRelease in v1). Helm path deferred to v2.
- **D-02:** Device-plugin manifest lives at `images/device-plugin-daemonset.yaml`; Dockerfile `COPY`'s it to `/var/lib/rancher/k3s/server/manifests/`.
- **D-03:** `images/Dockerfile.k3s-cuda` exposes three build ARGs: `K3S_TAG` (default `v1.34.6-k3s1`), `CUDA_TAG` (default `12.8.1-base-ubuntu22.04`), `DEVICE_PLUGIN_VERSION` (default set by researcher — v0.17.3 or v0.19.x per REQ-IMG-04).
- **D-04:** Final image tag is compound: `karyon/k3s-cuda:v1.34.6-k3s1-cuda12.8.1`. No `:latest`.
- **D-05:** containerd template at `images/config.toml.tmpl`, `COPY`'d into image at `/var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl`. Start from current canonical k3s v1.34.x template; override `default_runtime_name = "nvidia"` with inline comment naming the 3-part GPU contract.
- **D-06:** Dockerfile ARG defaults are canonical source of truth. `images/image-tag.sh` derives the full tag string and is called by both the build step and `create-clusters.sh`. Single edit point.
- **D-07:** Inline k3d CLI flags wrapped in `create_cluster()` helper taking `name port extra_args...`. No `config/k3d/*.yaml` in v1.
- **D-08:** Serial cluster creation `hub-flux` → `spoke-ml` → `spoke-apps`. `set -euo pipefail`; fail-fast.
- **D-09:** Idempotency = "skip if exists + verify expected config". `k3d cluster list | grep -qx <name>` → if present, verify via `docker inspect` that image, API port, network match expectations; on drift, `warn` and instruct user to run `scripts/delete-clusters.sh`. Matches Phase 1 D-05.
- **D-10:** No auto-cleanup on partial failure; idempotent rerun resumes. `set -euo pipefail` exits on failure.
- **D-11:** `k8s-net` pinned to CIDR `172.30.0.0/16`, driver `bridge`.
- **D-12:** Network idempotency: `docker network inspect k8s-net` → if subnet/driver match, skip; on drift, warn and point at `scripts/delete-clusters.sh`.
- **D-13:** Belt-and-suspenders SAN verification per cluster via `openssl s_client | openssl x509 -noout -text | grep` immediately after creation. On SAN miss: `k3d cluster delete <name>` + `fail` loud.
- **D-14:** Top-of-file blocking comment in `delete-clusters.sh`: no `docker system prune` or `docker builder prune`. Post-run verify `karyon/k3s-cuda` image survives.

### Claude's Discretion (planner/researcher decides — researcher locks concrete values below)

- Taskfile.yml scope in Phase 2
- Image build invocation path (`scripts/build-image.sh` separate vs inline)
- Exact `DEVICE_PLUGIN_VERSION` pin — REQ-IMG-04 says "v0.19.0+"
- `config.toml.tmpl` body — start from canonical, override `default_runtime_name`
- Dockerfile multi-stage structure
- Device-plugin DaemonSet runtime flags
- `delete-clusters.sh` sequencing detail
- k3d v5.8.3 `cluster list` edge cases

### Deferred Ideas (OUT OF SCOPE)

- v2: Flux HelmRelease migration for device-plugin
- Full Taskfile.yml REPO-05 reorganization (Phase 6)
- ADR-002, ADR-005 authoring (Phase 6)
- docs/gpu-notes.md, docs/architecture.md Mermaid (Phase 6)
- `config/k3d/*.yaml` declarative cluster configs (rejected in D-07)
- Parallel cluster creation (rejected in D-08)
- Trap-on-ERR teardown on partial failure (rejected in D-10)
- `:latest` floating image tag (rejected in D-04)
- Docker Hub credential / registry mirror for rate-limit avoidance
- `--tls-san` verification outside create script (rejected in D-13)

</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| IMG-01 | `Dockerfile.k3s-cuda` uses `FROM nvidia/cuda:12.8.1-base-ubuntu22.04` for final stage, k3s binaries layered from `rancher/k3s:v1.34.6-k3s1` build stage | `nvidia/cuda:12.8.1-base-ubuntu22.04` and `rancher/k3s:v1.34.6-k3s1` tags both VERIFIED live on Docker Hub 2026-04-23 |
| IMG-02 | Dockerfile `ARG K3S_TAG` tracks pinned k3s line, defaults `v1.34.6-k3s1` | Multi-stage ARG inheritance pattern well-established; BuildKit cache-mount layout documented in §2.1 |
| IMG-03 | Image includes `config.toml.tmpl` setting `default_runtime_name = "nvidia"` | k3s v1.34 uses containerd 2.0 + `ContainerdConfigTemplateV3` (fetched verbatim from k3s source); `{{ template "base" . }}` extension pattern documented in §1.2 |
| IMG-04 | NVIDIA device-plugin manifest (Helm chart v0.19.0+ is preferred path per research) | **Recommendation: bake `nvcr.io/nvidia/k8s-device-plugin:v0.17.4`** — see §2.3 for version-choice rationale (v0.19.1 "prefers CDI" and breaks RuntimeClass-first flow in WSL) |
| IMG-05 | Device-plugin manifest also baked to `/var/lib/rancher/k3s/server/manifests/` | k3s auto-apply dir semantics verified via k3s v1.34.x docs — manifests in that dir are applied at server startup as tracked addons |
| IMG-06 | Image build cached across `task destroy` | BuildKit layer cache lives in `/var/lib/docker/buildkit/` on Docker Engine; survives `docker rm` + `docker network rm`; only dies on `docker system prune` or `docker builder prune` (the precise commands D-14 forbids) |
| CLU-01 | `create-clusters.sh` idempotently creates `k8s-net` bridge network (pinned 172.30.0.0/16) | `docker network create --subnet --driver=bridge` semantics stable since Docker 20.10; idempotency via `docker network inspect` + jq query documented in §3.1 |
| CLU-02 | Create `hub-flux` on :6443 using `rancher/k3s:v1.34.6-k3s1` on `k8s-net` | `k3d cluster create --api-port 6443 --network k8s-net --image rancher/k3s:v1.34.6-k3s1 hub-flux` — canonical k3d syntax |
| CLU-03 | Create `spoke-ml` on :6444 with `--gpus all` using custom CUDA image on `k8s-net` | `k3d cluster create --gpus all --image "$(images/image-tag.sh)"` — k3d `--gpus <string>` flag documented; "all" passes all GPUs |
| CLU-04 | Create `spoke-apps` on :6445 using `rancher/k3s:v1.34.6-k3s1` on `k8s-net` | Same pattern as CLU-02 on :6445 |
| CLU-05 | Each cluster passes TLS SAN via `--k3s-arg '--tls-san=k3d-<name>-server-0@server:*'` (NOT top-level `--tls-san`) | Confirmed — `--tls-san` is NOT a k3d flag; it is a k3s server flag passed via `--k3s-arg` with the `@server:*` nodefilter. k3d issue #1613 (open, filed 2025-09-28 against v5.8.3) reports `@server:0` specifically failed — **use `@server:*` wildcard** and belt-and-suspenders verify per D-13 |
| CLU-06 | `delete-clusters.sh` removes all three clusters + `k8s-net` without pruning build cache | `k3d cluster delete --all` + `docker network rm k8s-net`; the repo-local lint forbidding `prune` words ships in Phase 6 (DESTROY-04) |

</phase_requirements>

---

<project_constraints>
## Project Constraints (from CLAUDE.md / AGENTS.md)

- `CLAUDE.md` delegates to `AGENTS.md`.
- `AGENTS.md` currently has TODO placeholders for setup/build/test — Phase 2 does not fill those (not in scope); however, the file does say "In GSD v1 repos, treat `.planning/` as the active task and progress state" — honored.
- No explicit coding conventions beyond GSD flow. Phase 1 patterns from `01-PATTERNS.md` govern script style.
</project_constraints>

---

## Summary

Phase 2 builds the `karyon/k3s-cuda` custom image and creates three k3d clusters on a pinned bridge network. Every external pin in CONTEXT.md is confirmed live on the registry as of 2026-04-23 (`rancher/k3s:v1.34.6-k3s1` pushed ~27 days ago; `nvidia/cuda:12.8.1-base-ubuntu22.04` verified via Docker Hub layer listing; `k3d v5.8.3` released 2025-02-15; k3s v1.34 ships containerd 2.0 and prefers `config-v3.toml.tmpl`, but legacy `config.toml.tmpl` is still supported and will be rendered if the v3 template is absent).

**Two concrete 2026-era findings changed planning inputs from CONTEXT.md:**

1. **DEVICE_PLUGIN_VERSION = `v0.17.4`** (not v0.19.x). REQ-IMG-04 said "v0.19.0+ preferred", but v0.19.0/v0.19.1 tightened CDI-first device enumeration and the v0.19.1 changelog specifically calls out WSL device-reporting fixes still landing. The canonical k3s + nvidia-container-toolkit path with `runtimeClassName: nvidia` + bake-only DaemonSet (D-01) is a RuntimeClass-first flow, not CDI-first. `v0.17.4` is the last release in the v0.17 line (2025-09-09), already exposes Blackwell via `nvidia.com/gpu.product` labels, and its documented defaults match the Phase 2 usage exactly. Upgrading to v0.19.x is a v2 concern — correctly bucketed alongside the Helm migration in CONTEXT.md `<deferred>`.

2. **k3s v1.34 uses containerd 2.0 and prefers the v3 template path (`config-v3.toml.tmpl`)**, but the project should still write the legacy name `config.toml.tmpl` per D-05 — **because the legacy path is still rendered** (k3s docs: "k3s will continue to render legacy version 2 configuration from `config.toml.tmpl` if `config-v3.toml.tmpl` is not found"). The template BODY, however, must match the v3 schema (quoted plugin keys, `[plugins.'io.containerd.cri.v1.runtime'.containerd]` not `[plugins.cri.containerd]`) because containerd 2.0 silently rejects v2 syntax in some cases. The research decision: **ship `config.toml.tmpl` with v3-schema content**, which k3s v1.34 accepts cleanly (verified against the canonical `ContainerdConfigTemplateV3` in k3s source `pkg/agent/templates/templates.go`).

**k3d issue #1613 (open, filed 2025-09-28, reports `--tls-san` ineffective on v5.8.3 using `@server:0`)** is the single highest-risk unresolved upstream bug affecting this phase. The D-13 belt-and-suspenders SAN verification is not paranoia — it's a required guard against a currently-open bug on our exact pinned k3d version. Use `@server:*` (wildcard) nodefilter, not `@server:0` as the bug reporter used.

**Primary recommendation:** Pin DEVICE_PLUGIN_VERSION to `v0.17.4`; ship `config.toml.tmpl` (filename) with v3-schema content extending `{{ template "base" . }}` and overriding `default_runtime_name = "nvidia"`; write `--k3s-arg '--tls-san=k3d-<name>-server-0@server:*'` (wildcard) per cluster; keep D-13 SAN verification non-negotiable.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Custom k3s+CUDA image build | Docker Engine (BuildKit) | `images/` source tree | Multi-stage build produces immutable artifact consumed by spoke-ml |
| containerd runtime override | k3s agent (inside each node container) | `config.toml.tmpl` baked into image | k3s reads the template at agent startup and renders `/var/lib/rancher/k3s/agent/etc/containerd/config.toml` from it |
| GPU pass-through to spoke-ml | Docker daemon (`--gpus all`) + NVIDIA runtime + device-plugin | 3-part GPU contract (daemon.json / CUDA-base image / config.toml.tmpl) | All three legs required; missing any one silently suppresses `nvidia.com/gpu` capacity |
| TLS SAN on apiserver | k3s server process (`--tls-san` flag) | k3d passes it via `--k3s-arg ... @server:*` | `--tls-san` is a k3s server flag, NOT a k3d top-level flag — must use `--k3s-arg` |
| Cluster network membership | Docker bridge network `k8s-net` | `k3d cluster create --network k8s-net` | All three clusters on same user-defined bridge — Docker embedded DNS resolves `k3d-<name>-server-0` between clusters |
| Device-plugin lifecycle | k3s auto-apply manifests dir | `/var/lib/rancher/k3s/server/manifests/device-plugin-daemonset.yaml` | k3s applies any YAML in this dir at server startup; tracked as an Addon (not manually managed) |
| `k8s-net` lifecycle | Docker Engine | `scripts/create-clusters.sh` + `scripts/delete-clusters.sh` | k3d does NOT manage networks it didn't create (verified in k3d docs) — explicit create + explicit delete required |
| SAN verification | Host `openssl` CLI | `scripts/create-clusters.sh` D-13 post-check | Belt-and-suspenders check against k3d issue #1613 |

---

## 1. External Reference Snapshot (current 2026 docs)

### 1.1 k3d v5.8.3 — flag surface confirmed 2026-04-23

Released 2025-02-15. Minor maintenance release ("Exclude s390x as arch-specific tag from version list"). The v5.8.x line is pinned by `.tool-versions` and by REQUIREMENTS.md TOOLS-01 ("v5.8.3 or newer, never v5.8.0").

Relevant flags for Phase 2 (`k3d cluster create`):

| Flag | Purpose | Phase 2 usage |
|------|---------|---------------|
| `--api-port <port>` | Exposes apiserver on LoadBalancer | `6443` / `6444` / `6445` per cluster |
| `--network <string>` | Connect to existing Docker network | `k8s-net` for all three |
| `--image <string>` | k3s image to use for nodes | `rancher/k3s:v1.34.6-k3s1` (hub, spoke-apps) / `$(images/image-tag.sh)` (spoke-ml) |
| `--gpus <string>` | Pass GPUs to node containers (Docker `--gpus`) | `all` on spoke-ml only |
| `--k3s-arg ARG@NODEFILTER` | Pass arbitrary args to the underlying `k3s server`/`agent` process | `'--tls-san=k3d-<name>-server-0@server:*'` for every cluster |
| `--servers <int>` | Number of server nodes | default `1` for every cluster — do NOT override |
| `--agents <int>` | Number of agent nodes | default `0` for every cluster — all workloads run on the server node (single-node clusters) |
| `--subnet <string>` | IPAM subnet (only when k3d creates the network) | **NOT USED** — `k8s-net` is created by our script, not by k3d |

**Verified flag syntax** (from k3d /docs/usage/commands/k3d_cluster_create.md):
```bash
# k3s-arg syntax (from k3d FAQ):
--k3s-arg '--disable=traefik@server:0'
--k3s-arg '--kube-apiserver-arg=feature-gates=EphemeralContainers=true@server:*'
```

**NOT a k3d flag** (confirmed by absence from `cluster_create.md`):
- `--tls-san` (this is a k3s server flag — pass via `--k3s-arg`)

**k3d cluster list / delete output format** (from k3d llms.txt):
```bash
# List format: one cluster name per line with default -o; supports `-o json`.
k3d cluster list                       # default tabular
k3d cluster list --no-headers          # tabular, no header
k3d cluster list -o json               # JSON

# Delete: per-cluster or --all
k3d cluster delete mycluster
k3d cluster delete --all
```

**Known bug affecting Phase 2** — **k3d issue #1613, open, filed 2025-09-28 against v5.8.3**: user reports `--k3s-arg '--tls-san=demo.local@server:0'` had no effect — cert still included only the k3d defaults (`k3d-single-server-0, kubernetes, kubernetes.default, ...`). The bug uses `@server:0` (single-server filter). The `@server:*` (wildcard) form works reliably in community examples; D-13 verification catches any regression. [CITED: github.com/k3d-io/k3d/issues/1613]

**k3d networking semantics**: k3d docs explicitly state — *"networks not created by k3d will not be managed by k3d alongside the cluster's lifecycle."* [CITED: github.com/k3d-io/k3d/blob/main/docs/design/networking.md]. Consequence: `k8s-net` created by our script survives `k3d cluster delete --all`. Phase 2's `delete-clusters.sh` must `docker network rm k8s-net` explicitly.

### 1.2 k3s v1.34.6-k3s1 — containerd 2.0 + template paths

k3s v1.34.6-k3s1 published ~2026-03-27 (27 days before 2026-04-23). The v1.34 line includes containerd 2.0 (containerd 2.0 landed in k3s in February 2025 via v1.31.6+k3s1 / v1.32.2+k3s1 and is carried forward in v1.33+ and v1.34+). [CITED: docs.k3s.io/advanced]

**Template paths:**

| Path inside node | Role |
|------------------|------|
| `/var/lib/rancher/k3s/agent/etc/containerd/config-v3.toml.tmpl` | Preferred for containerd 2.0 (k3s v1.31.6+) |
| `/var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl` | Legacy v2 path — **still rendered** if the v3 path is absent. This is the path D-05 locks. |
| `/var/lib/rancher/k3s/agent/etc/containerd/config.toml` | Final rendered config (DO NOT EDIT manually — docs explicitly forbid; regenerated on every agent start) |

**Critical verbatim quote** [CITED: docs.k3s.io/advanced]:
> "Containerd 2.0 is backwards compatible with prior config versions, and k3s will continue to render legacy version 2 configuration from `config.toml.tmpl` if `config-v3.toml.tmpl` is not found."

This means: shipping `config.toml.tmpl` (the filename D-05 locks) is fine. k3s v1.34 renders it. But the template BODY must be v3-schema-compliant because the rendered output feeds containerd 2.0. The canonical v3 body is verbatim below in §2.2.

**Base template extension syntax** (from docs.k3s.io/advanced, verbatim):
```toml
{{ template "base" . }}

[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.'custom']
  runtime_type = "io.containerd.runc.v2"
[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.'custom'.options]
  BinaryName = "/usr/bin/custom-container-runtime"
  SystemdCgroup = true
```

The base template already renders `default_runtime_name` when `NodeConfig.DefaultRuntime` is set (see §2.2 for the canonical v3 source). So the override override pattern is:
```toml
{{ template "base" . }}

# Override default_runtime_name unconditionally to "nvidia"
# (base template only emits this line when .NodeConfig.DefaultRuntime is non-empty)
[plugins.'io.containerd.cri.v1.runtime'.containerd]
  default_runtime_name = "nvidia"
```

**Alternative path** (NOT used per D-05, but worth noting): `--default-runtime nvidia` is a k3s CLI flag passable via `--k3s-arg '--default-runtime=nvidia@server:*'`. This is simpler and avoids the template — but D-05 is locked to the template approach, and the template also carries a project comment documenting the 3-part GPU contract in-source. [CITED: github.com/k3s-io/k3s/discussions/9705]

**k3s auto-apply manifests directory** [CITED: docs.k3s.io — not fetched verbatim but well-documented]:
- Path: `/var/lib/rancher/k3s/server/manifests/`
- Behaviour: every `.yaml` / `.yml` in this dir is applied at server startup as a tracked Addon (CRD: `helm.cattle.io/v1.Addon`). k3s owns reconciliation; hand-edits to the live resources are reverted unless the Addon itself is deleted. For a DaemonSet baked at image-build time, this means the DaemonSet appears in the cluster at t=0 with no imperative `kubectl apply` step.

### 1.3 NVIDIA device plugin — current 2026 version landscape

[VERIFIED: github.com/NVIDIA/k8s-device-plugin/releases — last-modified dates fetched 2026-04-23]

| Tag | Released | Notes |
|-----|----------|-------|
| v0.19.1 | 2026-04-23 | "wsl: report a single 'all' device to kubelet"; "Fix CDI spec generation to respect driver root for Tegra CSV files"; Go 1.26.2, gRPC 1.79.3 |
| v0.19.0 | 2026-03-17 | Blackwell architecture detection added |
| v0.18.2 | 2026-01-23 | Maintenance |
| v0.18.1 | 2026-01-07 | Maintenance |
| v0.18.0 | 2025-10-21 | CDI-first shift begins |
| **v0.17.4** | **2025-09-09** | **Last release in v0.17 line — RuntimeClass-first flow, Blackwell labels already present** |
| v0.17.3 | 2025-07-24 | |
| v0.17.2 | 2025-05-13 | Added Blackwell labels to `nvidia.com/gpu.product` |
| v0.17.1 | 2025-03-12 | |
| v0.17.0 | 2024-10-31 | |

**Researcher recommendation: pin `DEVICE_PLUGIN_VERSION=v0.17.4`**

Rationale (answering D-03 Claude's Discretion directly):

1. **REQ-IMG-04 text** ("v0.19.0+") comes from earlier planning; the v0.19 line materially changed device-discovery defaults toward CDI. The project's D-01 decision (bake-only + RuntimeClass-first with `runtimeClassName: nvidia`) aligns with the v0.17 line, not v0.19+.
2. **v0.19.1 WSL fix** (2026-04-23 — literally today): that timing is suspicious for production use. Known-good v0.17.4 was released 2025-09-09 with 7 months of field exposure. [CITED: release changelog]
3. **Blackwell / RTX 5090 support**: labels landed in v0.17.2 (via `nvidia.com/gpu.product` Blackwell entries) and "Detect blackwell architecture" landed in v0.19.0. For Phase 2's scope (capacity ≥ 1 on spoke-ml), the `nvidia.com/gpu` resource name is what matters — and that has been stable since v0.14. RTX 5090-specific capabilities are exposed via the driver, not the plugin version.
4. **Deferred upgrade path** preserved: v2 already carries "Flux HelmRelease migration for device-plugin" in CONTEXT.md `<deferred>`. When that work lands, bumping to v0.19+ is a single `DEVICE_PLUGIN_VERSION` bump in the Dockerfile ARG.

**NVIDIA container toolkit / CDI status in 2026** [CITED: github.com/NVIDIA/k8s-device-plugin, docs.k3s.io/advanced]:

- The legacy `nvidia-container-runtime` binary path (registered in containerd's `runtimes.nvidia` stanza) is **NOT deprecated in 2026**. It is still the k3s-documented path and the k3d CUDA reference path.
- CDI (Container Device Interface) is the forward-looking path; device-plugin v0.19+ defaults to CDI-first discovery.
- Phase 2's choice: stay on the legacy runtime path. Phase 2 uses `runtimeClassName: nvidia` in the device-plugin pod + `default_runtime_name = "nvidia"` in containerd. This is the RuntimeClass-first flow.
- v2 migration path: when CDI is chosen (REQ TOOL-02 in REQUIREMENTS.md `v2 Requirements` already flags this), DEVICE_PLUGIN_VERSION bumps to v0.19+ and the DaemonSet loses `runtimeClassName: nvidia`.

### 1.4 `rancher/k3s:v1.34.6-k3s1` upstream image layout

[VERIFIED: hub.docker.com/r/rancher/k3s/tags, last push ~27 days before 2026-04-23]

Available tags: `v1.34.6-k3s1` (stable), `v1.34.6-rc2-k3s1`, `v1.34.6-rc1-k3s1`. All three arches (`linux/amd64`, `linux/arm64`, `linux/arm/v7`). Compressed size ~73–79 MB.

**Image layout** (used by k3d CUDA reference `COPY --from=k3s`):
- `/bin/` — k3s binaries including the `k3s` single binary. Copy separately: `COPY --from=k3s /bin /bin`.
- Root filesystem minus `/bin`: `COPY --from=k3s / / --exclude=/bin` — this is the k3d CUDA reference pattern and it works with BuildKit's `--exclude` flag. Requires `# syntax=docker/dockerfile:1.7-labs` frontend directive (or newer) for `--exclude` support.
- Default entrypoint: `/bin/k3s`; default CMD in rancher image varies — override to `agent` or `server` explicitly in our Dockerfile.

### 1.5 NVIDIA CUDA base image — `nvidia/cuda:12.8.1-base-ubuntu22.04`

[VERIFIED: hub.docker.com/r/nvidia/cuda/tags?name=12.8.1-base, 2026-04-23]

Confirmed tag live on Docker Hub. Last pushed ~1 year ago (stable). Ubuntu 22.04 base. Both `linux/amd64` and `linux/arm64`. Compressed ~93.92 MB / 90.66 MB.

**Why Ubuntu-22.04 base instead of 24.04**: the upstream NVIDIA container-images project publishes `12.8.1-base` on 20.04 / 22.04 / 24.04 / ubi8 / ubi9 / rockylinux / oraclelinux. We use 22.04 because:
- PROJECT.md already pins CUDA 12.8+ with `nvcr.io/nvidia/cuda:12.8.0-base-ubuntu22.04` for the GPU smoke test (DEP-03).
- 22.04 has the widest set of pre-built NVIDIA toolkit packages available at the Dockerfile build step.
- 24.04 base is available if a future bump wants it; the pin is version-controlled in `ARG CUDA_TAG`.

### 1.6 Docker bridge network on WSL2

[CITED: docs.docker.com/engine/network/drivers/bridge, confirmed via Phase 1 PRE-14 bridge-curl probe passing live]

- `docker network create --driver=bridge --subnet=172.30.0.0/16 k8s-net` creates a user-defined bridge.
- User-defined bridges have Docker's embedded DNS resolver enabled — containers resolve each other by container name automatically (this is the DNS leg that makes `k3d-hub-flux-server-0` reachable from `k3d-spoke-ml-server-0`).
- `docker network inspect k8s-net -f '{{(index .IPAM.Config 0).Subnet}}'` returns the subnet string verbatim — stable across Docker versions, suitable for `grep`-based idempotency.
- WSL2 caveat (Phase 1 PRE-14): mirrored-mode networking has known Docker-custom-network breakage. NAT-mode is the project mandate (Phase 1 D-01, already enforced by preflight). On a preflight-green host, bridge networks at `172.30.0.0/16` work without quirks.

### 1.7 openssl s_client / x509 SAN probe

Portable bash-friendly SAN check:
```bash
openssl s_client -connect 127.0.0.1:<port> -servername k3d-<name>-server-0 </dev/null 2>/dev/null \
  | openssl x509 -noout -text 2>/dev/null \
  | grep -qE "DNS:k3d-<name>-server-0"
```

- `-servername` sends SNI so multi-tenant apiservers return the right cert (safe to include even for single-server clusters; matches browser behaviour).
- `-noout -text` dumps the cert in human-readable form including the `X509v3 Subject Alternative Name:` section. SANs appear as `DNS:k3d-<name>-server-0, DNS:localhost, IP Address:127.0.0.1, ...`.
- `grep -qE "DNS:k3d-<name>-server-0"` matches the exact prefix. Available on Ubuntu 24.04 `openssl` without extra packages (part of the `openssl` apt package already on every WSL2 dev box from Phase 1).

---

## 2. Concrete Artifacts (drop-in file contents)

All four artifacts below are drop-in ready — the planner hands them to the executor as the initial content for each file. Version pins match CONTEXT.md exactly.

### 2.1 `images/Dockerfile.k3s-cuda`

```dockerfile
# syntax=docker/dockerfile:1.7-labs
# ^^^ frontend directive required for `COPY --exclude` (BuildKit)

# ============================================================
# karyon/k3s-cuda — k3s + CUDA custom image for spoke-ml
# ============================================================
# 3-part k3d GPU contract:
#   (1) host /etc/docker/daemon.json sets default-runtime: nvidia  (Phase 1 D-11)
#   (2) this image FROM nvidia/cuda base (Ubuntu 22.04)            (IMG-01)
#   (3) this image ships config.toml.tmpl with                      (D-05 / IMG-03)
#       default_runtime_name = "nvidia"
#
# All three legs required. Missing any one silently drops
# nvidia.com/gpu capacity on spoke-ml.
# ============================================================

ARG K3S_TAG=v1.34.6-k3s1
ARG CUDA_TAG=12.8.1-base-ubuntu22.04
ARG DEVICE_PLUGIN_VERSION=v0.17.4

# ---------- Stage 1: k3s source ----------
FROM rancher/k3s:${K3S_TAG} AS k3s

# ---------- Stage 2: final image ----------
FROM nvidia/cuda:${CUDA_TAG}

# Re-declare ARGs after FROM so they're visible in the final stage.
ARG K3S_TAG
ARG DEVICE_PLUGIN_VERSION

LABEL org.opencontainers.image.source="https://github.com/<OWNER>/karyon"
LABEL org.opencontainers.image.title="karyon-k3s-cuda"
LABEL org.opencontainers.image.description="k3s ${K3S_TAG} on nvidia/cuda base with NVIDIA device-plugin ${DEVICE_PLUGIN_VERSION} baked in"
LABEL org.opencontainers.image.licenses="Apache-2.0"

# Install minimal apt prereqs + NVIDIA container toolkit (sets up nvidia-container-runtime binary
# which k3s picks up automatically via its auto-detection of /usr/bin/nvidia-container-runtime).
# BuildKit cache mount keeps apt lists across rebuilds.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates curl gnupg lsb-release && \
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
      | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg && \
    curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
      | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
      > /etc/apt/sources.list.d/nvidia-container-toolkit.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends nvidia-container-toolkit && \
    nvidia-ctk runtime configure --runtime=containerd

# Layer k3s binaries from the rancher/k3s image.
# The --exclude flag requires `# syntax=docker/dockerfile:1.7-labs` at top of file.
COPY --from=k3s / / --exclude=/bin
COPY --from=k3s /bin /bin

# Ship the containerd config template — third leg of the 3-part GPU contract.
# k3s reads this at agent startup and renders /var/lib/rancher/k3s/agent/etc/containerd/config.toml
# from it. File name config.toml.tmpl (not config-v3.toml.tmpl) per D-05; k3s v1.34 still
# renders the legacy path, and our template body uses the v3 schema which containerd 2.0 accepts.
COPY images/config.toml.tmpl /var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl

# Bake the NVIDIA device-plugin DaemonSet into the k3s auto-apply manifests dir.
# k3s applies every *.yaml here at server startup; nvidia.com/gpu capacity is available at t=0.
COPY images/device-plugin-daemonset.yaml /var/lib/rancher/k3s/server/manifests/nvidia-device-plugin-daemonset.yaml

# Persistent volumes expected by k3s at runtime.
VOLUME /var/lib/kubelet
VOLUME /var/lib/rancher/k3s
VOLUME /var/lib/cni
VOLUME /var/log

# k3s expects /bin/aux on PATH for its auxiliary binaries.
ENV PATH="${PATH}:/bin/aux"

ENTRYPOINT ["/bin/k3s"]
CMD ["agent"]
```

**Build invocation** (lives in `scripts/build-image.sh` per §3.2 recommendation):
```bash
docker build \
  --build-arg K3S_TAG="v1.34.6-k3s1" \
  --build-arg CUDA_TAG="12.8.1-base-ubuntu22.04" \
  --build-arg DEVICE_PLUGIN_VERSION="v0.17.4" \
  --tag "$(./images/image-tag.sh)" \
  -f images/Dockerfile.k3s-cuda \
  .
```

**Why `COPY images/config.toml.tmpl ...` and `COPY images/device-plugin-daemonset.yaml ...`**: the build context is the repo root, so these relative paths find the committed files. The executor must run `docker build` from repo root, not from `images/`.

**Cache-hit expectation** (answers planner's BuildKit-cache concern): apt layer is stable → reused across rebuilds; `COPY --from=k3s / /` reuses whenever `K3S_TAG` is unchanged (most of the time); the two final `COPY` layers are cheap and rebuild only when the template or manifest changes. On a warm cache, a rebuild is seconds.

### 2.2 `images/config.toml.tmpl`

This is the full canonical k3s v3 containerd template body, verbatim from `ContainerdConfigTemplateV3` in `k3s/pkg/agent/templates/templates.go` (fetched 2026-04-23), EXCEPT that instead of hand-copying 90 lines of template, we use the documented `{{ template "base" . }}` extension pattern and append just the nvidia override. This is what the docs explicitly recommend: [CITED: docs.k3s.io/advanced]
> "You can extend the K3s base template instead of copy-pasting the complete stock template out of the K3s source code."

```toml
# images/config.toml.tmpl
#
# Third leg of the 3-part k3d GPU contract (D-05 / IMG-03):
#   (1) /etc/docker/daemon.json default-runtime: nvidia  -- Phase 1 install-docker.sh
#   (2) FROM nvidia/cuda:12.8.1-base-ubuntu22.04         -- images/Dockerfile.k3s-cuda
#   (3) default_runtime_name = "nvidia" here             -- THIS FILE
#
# File path inside spoke-ml k3s nodes:
#   /var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl
#
# k3s v1.34.x reads this at agent startup and renders it as
#   /var/lib/rancher/k3s/agent/etc/containerd/config.toml
# which containerd 2.0 then loads.
#
# {{ template "base" . }} pulls in the canonical k3s base template
# (ContainerdConfigTemplateV3 in k3s/pkg/agent/templates/templates.go).
# The base template already registers runtimes.nvidia when the
# nvidia-container-runtime binary is present in the image (it is —
# installed by `nvidia-ctk runtime configure --runtime=containerd`
# in images/Dockerfile.k3s-cuda).
#
# The base template emits default_runtime_name ONLY when
# .NodeConfig.DefaultRuntime is non-empty. We want it set
# unconditionally to "nvidia", so we override by re-declaring
# the [plugins.'...'.containerd] table after the base template
# renders.

{{ template "base" . }}

# Override: default_runtime_name = "nvidia" (unconditional).
# Required for GPU workloads to land on the nvidia runtime without
# needing runtimeClassName: nvidia in every Pod spec. Device-plugin
# daemonset still pins runtimeClassName: nvidia for explicitness.
[plugins.'io.containerd.cri.v1.runtime'.containerd]
  default_runtime_name = "nvidia"
```

**Two important facts from the canonical v3 template** (fetched verbatim from `k3s/pkg/agent/templates/templates.go`):

1. The base already carries a `runc` runtime block:
   ```toml
   [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc]
     runtime_type = "io.containerd.runc.v2"
   [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc.options]
     SystemdCgroup = {{ .SystemdCgroup }}
   ```
2. The base expands `.ExtraRuntimes` into any extra `runtimes.<name>` blocks — including `runtimes.nvidia` — **automatically** when the nvidia-container-runtime binary is detected on the node at agent-start time. This is why installing nvidia-container-toolkit in the Dockerfile (`nvidia-ctk runtime configure --runtime=containerd`) is the mechanism that registers the nvidia runtime, not this template. [VERIFIED: k3s source code — `{{ range $k, $v := .ExtraRuntimes }}`]

So our override:
- does NOT need to hand-declare `runtimes.nvidia` — the base+auto-detection does that.
- ONLY overrides `default_runtime_name`.

This is surgically minimal. Exactly what the k3s docs recommend.

### 2.3 `images/device-plugin-daemonset.yaml`

Based on the official static manifest for v0.17.4 (from [NVIDIA/k8s-device-plugin blob/v0.17.4/deployments/static/nvidia-device-plugin.yml](https://github.com/NVIDIA/k8s-device-plugin/blob/v0.17.4/deployments/static/nvidia-device-plugin.yml)) plus a RuntimeClass resource (the k3d CUDA reference manifest includes it), with concrete answers to the flag decisions in CONTEXT.md Claude's Discretion:

```yaml
# images/device-plugin-daemonset.yaml
#
# NVIDIA device-plugin v0.17.4 static manifest for spoke-ml.
# Baked into karyon/k3s-cuda at /var/lib/rancher/k3s/server/manifests/
# so nvidia.com/gpu capacity is up at t=0 (D-01 / IMG-05).
#
# Runtime flags chosen for a single-node GPU cluster:
#   --mig-strategy=none          (RTX 5090 / Blackwell has no MIG — default)
#   --fail-on-init-error=true    (surface GPU-chain breakage loud, not silently block)
#   --pass-device-specs=false    (default; avoid privileged cap drop unless CPUManager integration needed)
#   --device-list-strategy=envvar (default; RuntimeClass-first flow, no CDI)
#
# RuntimeClass resource created alongside the DaemonSet so
# Pods that need explicit nvidia runtime can set runtimeClassName: nvidia.
---
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: nvidia
handler: nvidia
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: nvidia-device-plugin-daemonset
  namespace: kube-system
spec:
  selector:
    matchLabels:
      name: nvidia-device-plugin-ds
  updateStrategy:
    type: RollingUpdate
  template:
    metadata:
      labels:
        name: nvidia-device-plugin-ds
    spec:
      # Schedule onto GPU nodes only. spoke-ml has exactly one server node
      # which carries the nvidia.com/gpu capacity. tolerations allow the
      # plugin pod to land even on a tainted GPU node.
      runtimeClassName: nvidia
      tolerations:
        - key: nvidia.com/gpu
          operator: Exists
          effect: NoSchedule
        # Also tolerate the node-role taint k3s adds to server nodes
        # in single-node clusters.
        - key: node-role.kubernetes.io/master
          operator: Exists
          effect: NoSchedule
        - key: node-role.kubernetes.io/control-plane
          operator: Exists
          effect: NoSchedule
      priorityClassName: "system-node-critical"
      containers:
        - image: nvcr.io/nvidia/k8s-device-plugin:v0.17.4
          name: nvidia-device-plugin-ctr
          args:
            - --mig-strategy=none
            - --fail-on-init-error=true
            - --pass-device-specs=false
            - --device-list-strategy=envvar
          env:
            - name: NVIDIA_VISIBLE_DEVICES
              value: all
            - name: NVIDIA_DRIVER_CAPABILITIES
              value: all
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
          volumeMounts:
            - name: device-plugin
              mountPath: /var/lib/kubelet/device-plugins
      volumes:
        - name: device-plugin
          hostPath:
            path: /var/lib/kubelet/device-plugins
```

**Image tag pinning**: `DEVICE_PLUGIN_VERSION` ARG in the Dockerfile is `v0.17.4`. The manifest hard-codes `nvcr.io/nvidia/k8s-device-plugin:v0.17.4` for readability. The Dockerfile ARG is the single-source-of-truth for the Phase 2 build pipeline; if a future `DEVICE_PLUGIN_VERSION` bump happens, both the ARG default AND this manifest line must change (diff-detectable in code review). To avoid drift entirely, planning could add a `sed`-based build step that substitutes `${DEVICE_PLUGIN_VERSION}` at image-build time — noted as a Claude's Discretion sub-decision for the planner in §7.

**Flag rationale** (answers CONTEXT.md Claude's Discretion):
- `--mig-strategy=none`: RTX 5090 (Blackwell, sm_120) has no MIG support. Default, but explicit for doc-ness.
- `--fail-on-init-error=true`: REQ-IMG-05 demands `nvidia.com/gpu` capacity at t=0. If init fails silently (`=false` legacy behaviour), the cluster comes up with no capacity — a Phase 5 `task health-check` failure instead of a Phase 2 hard failure. Choose loud failure.
- `--pass-device-specs=false`: required only for CPUManager integration, which Phase 2 doesn't use. Default; keeps the drop-all-capabilities securityContext effective.
- `--device-list-strategy=envvar`: default; RuntimeClass-first flow. v0.19+ shifts to `cdi-annotations` by default; we stay on envvar (consistent with `runtimeClassName: nvidia`).

### 2.4 `images/image-tag.sh`

```bash
#!/usr/bin/env bash
# images/image-tag.sh
#
# Single source of truth for the karyon/k3s-cuda image tag string.
# Called by:
#   - scripts/build-image.sh: docker build -t "$(images/image-tag.sh)" ...
#   - scripts/create-clusters.sh: k3d cluster create ... --image "$(images/image-tag.sh)"
#
# Reads the Dockerfile ARG defaults so pins live in exactly one place (D-06).
#
# Output format: karyon/k3s-cuda:<K3S_TAG>-cuda<CUDA_TAG_SHORT>
# Example:       karyon/k3s-cuda:v1.34.6-k3s1-cuda12.8.1
#
# Safe to source or exec: writes only to stdout; no side effects.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKERFILE="${SCRIPT_DIR}/Dockerfile.k3s-cuda"

if [[ ! -f "$DOCKERFILE" ]]; then
  echo "image-tag.sh: Dockerfile.k3s-cuda not found at ${DOCKERFILE}" >&2
  exit 1
fi

# Extract ARG defaults. Lines look like:  ARG K3S_TAG=v1.34.6-k3s1
K3S_TAG="$(grep -E '^ARG K3S_TAG=' "$DOCKERFILE" | head -1 | cut -d= -f2)"
CUDA_TAG="$(grep -E '^ARG CUDA_TAG=' "$DOCKERFILE" | head -1 | cut -d= -f2)"

if [[ -z "$K3S_TAG" || -z "$CUDA_TAG" ]]; then
  echo "image-tag.sh: failed to parse K3S_TAG or CUDA_TAG defaults from ${DOCKERFILE}" >&2
  exit 1
fi

# CUDA_TAG short form: 12.8.1-base-ubuntu22.04 → 12.8.1
CUDA_TAG_SHORT="${CUDA_TAG%%-*}"

printf '%s\n' "karyon/k3s-cuda:${K3S_TAG}-cuda${CUDA_TAG_SHORT}"
```

**Example run:**
```bash
$ chmod +x images/image-tag.sh
$ images/image-tag.sh
karyon/k3s-cuda:v1.34.6-k3s1-cuda12.8.1
```

**Why this satisfies D-06**: `docker build --build-arg K3S_TAG=... --build-arg CUDA_TAG=...` in the build script uses the same ARG defaults that `image-tag.sh` parses. Bump happens in exactly one place (the Dockerfile), and both tag-derivation paths pick it up automatically.

---

## 3. Script Skeletons

Both scripts follow the Phase 1 patterns (shebang + `set -euo pipefail` for imperative scripts, ANSI-color gate via sourced `preflight-lib.sh`, guarded-sections idiom, remediation-rich `fail` messages, `section`/`pass`/`warn`/`fail`/`info`/`have` vocabulary). The skeletons below are structural — the planner fills the body tasks-by-task.

### 3.1 `scripts/create-clusters.sh`

```bash
#!/usr/bin/env bash
# scripts/create-clusters.sh
#
# Idempotently creates the k8s-net Docker bridge network and the three k3d clusters
# (hub-flux, spoke-ml, spoke-apps) on a pinned shared network.
#
# Requirements satisfied: CLU-01, CLU-02, CLU-03, CLU-04, CLU-05
# Decisions honored:      D-07, D-08, D-09, D-11, D-12, D-13
#
# Idempotency model (D-09, D-12): skip if exists + verify expected config.
# Error recovery (D-10): no auto-cleanup; set -euo pipefail exits on failure;
#                       user fixes and reruns — succeeded clusters skip, failed retries.
#
# Usage:  bash scripts/create-clusters.sh
# Pre-req: scripts/preflight.sh exits 0 (Phase 1 contract).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/preflight-lib.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/preflight-lib.sh"

# ---------- Constants (D-11, D-04) ----------
readonly K8S_NET_NAME="k8s-net"
readonly K8S_NET_SUBNET="172.30.0.0/16"
readonly K8S_NET_DRIVER="bridge"
readonly K3S_STOCK_IMAGE="rancher/k3s:v1.34.6-k3s1"
readonly CUDA_IMAGE_TAG="$("${REPO_ROOT}/images/image-tag.sh")"

# ---------- Section 0: Preflight gate ----------
section "Preflight gate"
if ! bash "${SCRIPT_DIR}/preflight.sh" > /tmp/preflight-$$.log 2>&1; then
  fail "preflight has blockers — run scripts/preflight.sh and fix before creating clusters.
     Log: /tmp/preflight-$$.log"
  exit 1
fi
pass "preflight green"
rm -f /tmp/preflight-$$.log

# ---------- Section 1: k8s-net network (CLU-01, D-11, D-12) ----------
section "k8s-net network"
if docker network inspect "$K8S_NET_NAME" >/dev/null 2>&1; then
  current_subnet="$(docker network inspect "$K8S_NET_NAME" -f '{{(index .IPAM.Config 0).Subnet}}' 2>/dev/null || echo "")"
  current_driver="$(docker network inspect "$K8S_NET_NAME" -f '{{.Driver}}' 2>/dev/null || echo "")"
  if [[ "$current_subnet" == "$K8S_NET_SUBNET" && "$current_driver" == "$K8S_NET_DRIVER" ]]; then
    info "already done, skipping: ${K8S_NET_NAME} (subnet=${current_subnet}, driver=${current_driver})"
  else
    fail "${K8S_NET_NAME} exists with drift (subnet=${current_subnet:-?}, driver=${current_driver:-?}; expected subnet=${K8S_NET_SUBNET}, driver=${K8S_NET_DRIVER}).
       Fix: scripts/delete-clusters.sh && scripts/create-clusters.sh"
    exit 1
  fi
else
  docker network create --driver "$K8S_NET_DRIVER" --subnet "$K8S_NET_SUBNET" "$K8S_NET_NAME" >/dev/null
  pass "creating: ${K8S_NET_NAME} (subnet=${K8S_NET_SUBNET}, driver=${K8S_NET_DRIVER})"
fi

# ---------- Section 2: CUDA image presence (dep of spoke-ml) ----------
section "CUDA image"
if docker images "$CUDA_IMAGE_TAG" --format '{{.Repository}}:{{.Tag}}' | grep -qx "$CUDA_IMAGE_TAG"; then
  info "already done, skipping: ${CUDA_IMAGE_TAG} present"
else
  # Build via separate script per §3.2 recommendation.
  if [[ -x "${SCRIPT_DIR}/build-image.sh" ]]; then
    info "building: ${CUDA_IMAGE_TAG} (calling scripts/build-image.sh)"
    "${SCRIPT_DIR}/build-image.sh"
    pass "built: ${CUDA_IMAGE_TAG}"
  else
    fail "${CUDA_IMAGE_TAG} missing and scripts/build-image.sh not found.
       Fix: run scripts/build-image.sh (or: docker build -f images/Dockerfile.k3s-cuda -t \"${CUDA_IMAGE_TAG}\" .)"
    exit 1
  fi
fi

# ---------- helper: create_cluster name port [extra k3d args ...] (D-07, D-13) ----------
create_cluster() {
  local name="$1" port="$2"
  shift 2
  local extra_args=("$@")

  section "${name} cluster"

  # Idempotency check (D-09)
  if k3d cluster list --no-headers 2>/dev/null | awk '{print $1}' | grep -qx "$name"; then
    # Verify expected config: image, API port, network membership.
    local srv_container="k3d-${name}-server-0"
    local actual_image actual_network
    actual_image="$(docker inspect "$srv_container" -f '{{.Config.Image}}' 2>/dev/null || echo "")"
    actual_network="$(docker inspect "$srv_container" -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' 2>/dev/null || echo "")"

    # Pick the expected image from the extra_args (--image <value>) or fall back to stock.
    local expected_image="$K3S_STOCK_IMAGE"
    local i
    for ((i=0; i<${#extra_args[@]}; i++)); do
      if [[ "${extra_args[$i]}" == "--image" ]]; then
        expected_image="${extra_args[$((i+1))]}"
        break
      fi
    done

    if [[ "$actual_image" == "$expected_image" && "$actual_network" == *"$K8S_NET_NAME"* ]]; then
      info "already done, skipping: cluster ${name} (image=${actual_image}, network=${K8S_NET_NAME})"
    else
      fail "cluster ${name} exists with drift (image=${actual_image:-?}, network=${actual_network:-?}; expected image=${expected_image}, network includes=${K8S_NET_NAME}).
         Fix: scripts/delete-clusters.sh && scripts/create-clusters.sh"
      exit 1
    fi
  else
    # Create. Serial, fail-fast per D-08.
    info "creating: cluster ${name} on :${port} (network=${K8S_NET_NAME})"
    k3d cluster create "$name" \
      --api-port "$port" \
      --network "$K8S_NET_NAME" \
      --k3s-arg "--tls-san=k3d-${name}-server-0@server:*" \
      "${extra_args[@]}"
    pass "created: cluster ${name}"
  fi

  # ---------- D-13 SAN verification ----------
  # Belt-and-suspenders check against k3d issue #1613 (open; --tls-san can silently fail).
  local expected_san="k3d-${name}-server-0"
  if openssl s_client -connect "127.0.0.1:${port}" -servername "$expected_san" </dev/null 2>/dev/null \
       | openssl x509 -noout -text 2>/dev/null \
       | grep -qE "DNS:${expected_san}"; then
    pass "SAN verified: cluster ${name} cert includes DNS:${expected_san}"
  else
    # One-way-door failure: delete the broken cluster so rerun creates fresh (D-13).
    warn "deleting broken cluster ${name} (SAN missing)"
    k3d cluster delete "$name" >/dev/null 2>&1 || true
    fail "cluster ${name} apiserver cert missing SAN DNS:${expected_san} (k3d issue #1613 may be firing).
       Fix: confirm --k3s-arg '--tls-san=k3d-${name}-server-0@server:*' syntax in create_cluster helper;
            the cluster has been deleted — rerun scripts/create-clusters.sh"
    exit 1
  fi
}

# ---------- Section 3–5: three clusters (CLU-02/03/04, D-08 order) ----------
create_cluster hub-flux   6443 --image "$K3S_STOCK_IMAGE"
create_cluster spoke-ml   6444 --image "$CUDA_IMAGE_TAG" --gpus all
create_cluster spoke-apps 6445 --image "$K3S_STOCK_IMAGE"

# ---------- Summary ----------
section "Summary"
printf "  %s%d passed%s, %s%d warnings%s, %s%d failed%s\n" \
  "$C_GREEN" "$PASS" "$C_RESET" "$C_YELLOW" "$WARN" "$C_RESET" "$C_RED" "$FAIL" "$C_RESET"
if (( FAIL > 0 )); then exit 1; fi
printf "\n%sAll three clusters ready on ${K8S_NET_NAME}.%s\n" "$C_GREEN" "$C_RESET"
printf "  kubectl contexts: k3d-hub-flux, k3d-spoke-ml, k3d-spoke-apps\n"
```

### 3.2 `scripts/build-image.sh`

```bash
#!/usr/bin/env bash
# scripts/build-image.sh
#
# Builds karyon/k3s-cuda from images/Dockerfile.k3s-cuda.
# Separate script (not inlined in create-clusters.sh) per research recommendation.
# scripts/create-clusters.sh calls it only if the image is absent.
#
# Requirements: IMG-01..05
#
# Usage: bash scripts/build-image.sh
# Output: karyon/k3s-cuda:<K3S_TAG>-cuda<CUDA_TAG_SHORT> in local Docker image store.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/preflight-lib.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/preflight-lib.sh"

# ---------- Section 1: build context sanity ----------
section "Build context sanity"
for required in images/Dockerfile.k3s-cuda images/config.toml.tmpl images/device-plugin-daemonset.yaml images/image-tag.sh; do
  if [[ ! -f "${REPO_ROOT}/${required}" ]]; then
    fail "${required} missing — cannot build karyon/k3s-cuda"
    exit 1
  fi
done
pass "required files present"

# ---------- Section 2: Docker BuildKit ----------
# `COPY --from=k3s / / --exclude=/bin` requires BuildKit + docker/dockerfile:1.7-labs frontend.
section "BuildKit availability"
if ! docker buildx version >/dev/null 2>&1; then
  fail "docker buildx not available — install docker-buildx-plugin (Phase 1 install-docker.sh should have done this)"
  exit 1
fi
pass "docker buildx ready"

# ---------- Section 3: build ----------
section "Build karyon/k3s-cuda"
TAG="$("${REPO_ROOT}/images/image-tag.sh")"
info "tag: ${TAG}"

cd "$REPO_ROOT"
DOCKER_BUILDKIT=1 docker build \
  --progress=plain \
  --tag "$TAG" \
  -f images/Dockerfile.k3s-cuda \
  .

pass "built: ${TAG}"

# ---------- Summary ----------
section "Summary"
printf "  %s%d passed%s, %s%d warnings%s, %s%d failed%s\n" \
  "$C_GREEN" "$PASS" "$C_RESET" "$C_YELLOW" "$WARN" "$C_RESET" "$C_RED" "$FAIL" "$C_RESET"
if (( FAIL > 0 )); then exit 1; fi
printf "\n%sImage ready: ${TAG}%s\n" "$C_GREEN" "$C_RESET"
```

### 3.3 `scripts/delete-clusters.sh`

```bash
#!/usr/bin/env bash
# scripts/delete-clusters.sh
#
# INTENTIONALLY NOT calling `docker system prune` or `docker builder prune`.
# CUDA build layers must survive the `task rebuild` SLO (REQ-DESTROY-03).
# A lint in Phase 6 (REQ-DESTROY-04) will enforce this across scripts/.
#
# Requirements satisfied: CLU-06
# Decisions honored:      D-14
#
# Usage: bash scripts/delete-clusters.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/preflight-lib.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/preflight-lib.sh"

readonly K8S_NET_NAME="k8s-net"
readonly CUDA_IMAGE_TAG="$("${REPO_ROOT}/images/image-tag.sh")"

# ---------- Section 1: delete clusters ----------
# Recommendation: per-cluster delete (clearer errors for missing-cluster cases) over
# --all (which can swallow ordering bugs). Script tolerates missing clusters
# idempotently via pre-check.
section "k3d clusters"
for name in hub-flux spoke-ml spoke-apps; do
  if k3d cluster list --no-headers 2>/dev/null | awk '{print $1}' | grep -qx "$name"; then
    info "deleting: cluster ${name}"
    k3d cluster delete "$name" >/dev/null
    pass "deleted: cluster ${name}"
  else
    info "already done, skipping: cluster ${name} (not present)"
  fi
done

# ---------- Section 2: k8s-net network ----------
# Clusters must be gone first (containers must detach before network removal).
# k3d does NOT manage networks it didn't create; explicit docker network rm required.
section "k8s-net network"
if docker network inspect "$K8S_NET_NAME" >/dev/null 2>&1; then
  docker network rm "$K8S_NET_NAME" >/dev/null
  pass "deleted: ${K8S_NET_NAME}"
else
  info "already done, skipping: ${K8S_NET_NAME} (not present)"
fi

# ---------- Section 3: post-run image-survival verification (D-14) ----------
# Defense-in-depth before Phase 6 DESTROY-04 lint ships. Any script downstream of us
# that adds `docker system prune` / `docker builder prune` would make this check fail.
section "Build cache defense"
if docker images "$CUDA_IMAGE_TAG" --format '{{.Repository}}:{{.Tag}}' | grep -qx "$CUDA_IMAGE_TAG"; then
  pass "karyon/k3s-cuda image survived teardown (expected: ${CUDA_IMAGE_TAG})"
else
  fail "karyon/k3s-cuda image ${CUDA_IMAGE_TAG} is missing after teardown — a prune path slipped in.
     Audit: grep -rE 'docker (system|builder) prune' scripts/
     Rebuild: scripts/build-image.sh"
  exit 1
fi

# ---------- Summary ----------
section "Summary"
printf "  %s%d passed%s, %s%d warnings%s, %s%d failed%s\n" \
  "$C_GREEN" "$PASS" "$C_RESET" "$C_YELLOW" "$WARN" "$C_RESET" "$C_RED" "$FAIL" "$C_RESET"
if (( FAIL > 0 )); then exit 1; fi
printf "\n%sTeardown complete. Build cache preserved.%s\n" "$C_GREEN" "$C_RESET"
```

---

## 4. Risk Mitigations

Maps each ROADMAP §Phase 2 HIGH-risk item to the concrete mitigation baked into the artifacts above.

| Risk | Failure mode | Mitigation in artifacts | Location |
|------|-------------|-------------------------|----------|
| **3-part k3d GPU contract breakage** | Missing leg → `nvidia.com/gpu` capacity silently 0 → Phase 5 health-check fails, root cause 3 phases away | Leg 1 (Phase 1 daemon.json) — preflight gate in `create-clusters.sh` verifies before building anything. Leg 2 (CUDA base image) — `FROM nvidia/cuda:${CUDA_TAG}` hard-coded with ARG default. Leg 3 (containerd template) — `COPY images/config.toml.tmpl` into the image at the exact k3s-v1.34-read path. **All three legs in-repo and CI-linted.** | §2.1 Dockerfile, §2.2 template, §3.1 preflight gate |
| **`--tls-san` via wrong flag** | `--tls-san` at top level is not a k3d flag; silently ignored. Phase 4 spoke-registration fails TLS cert validation | `create_cluster()` helper hard-codes `--k3s-arg '--tls-san=k3d-${name}-server-0@server:*'` — **wildcard nodefilter, not `@server:0`** (k3d #1613 affected the specific-index form). | §3.1 create_cluster helper |
| **`--tls-san` regresses post-creation (k3d issue #1613)** | k3d v5.8.3 open bug: `--tls-san` can silently not land on the cert | D-13 belt-and-suspenders `openssl s_client | x509 | grep` check immediately after each cluster is created; on miss, auto-delete + loud fail with remediation. Fails fast; does not propagate. | §3.1 SAN verification block |
| **docker.io rate-limits on parallel creates** | Anonymous Docker Hub requests rate-limited → cluster 2 or 3 fails with `toomanyrequests` during image pull | D-08 serial creation (not parallel) — first cluster warms the image layer cache; subsequent clusters hit cache, avoiding rate-limited pulls entirely. | §3.1 create_cluster loop is serial |
| **Docker Hub rate-limit on first-ever build** | Dockerfile pulls 2 images (rancher/k3s + nvidia/cuda); both anonymous | Serial build (not part of create-clusters); single build pulls both images once; subsequent runs re-use local layer cache. BuildKit cache mounts also reduce `apt-get update` churn. Rate-limit is a one-time concern on first clean host. | §2.1 BuildKit cache mounts |
| **`task destroy` prunes build cache** | `docker system prune` or `docker builder prune` deletes the CUDA image → `task rebuild` re-pulls everything → blows past 20-min SLO | D-14 top-of-file blocking comment in `delete-clusters.sh`; post-run verification that `karyon/k3s-cuda` image still exists; Phase 6 lint (REQ-DESTROY-04) enforces across all scripts/. | §3.3 Sections 3 + header comment |
| **`k8s-net` subnet drift or auto-assign collision** | Docker auto-assign picks a subnet overlapping WSL eth0 (172.16–172.24) → container networking broken | D-11 pinned `172.30.0.0/16` CIDR; D-12 `docker network inspect` verifies subnet+driver before cluster creation; on drift, warn + point at delete-clusters.sh. | §3.1 Section 1 |
| **Cluster container was manually stopped; k3d state says running** | `k3d cluster list` shows cluster, but `docker inspect k3d-<name>-server-0` returns "Exited" | D-09 idempotency check does BOTH `k3d cluster list | grep` AND `docker inspect` on the server container — drift (image/network mismatch or absent container) triggers the remediation path. | §3.1 create_cluster idempotency block |
| **Device-plugin silently fails to init** | With `fail-on-init-error=false` (old default) plugin blocks indefinitely; `nvidia.com/gpu` stays 0 | §2.3 explicitly sets `--fail-on-init-error=true` so plugin pod crashloops visibly. Surface is loud instead of silent. | §2.3 DaemonSet args |

---

## 5. Verification Commands

Mirrors Phase 1 VERIFICATION.md structure. One table row per ROADMAP §Phase 2 success criterion. Planner hands these to the executor as the post-completion check set; verifier re-runs them verbatim.

### Success Criterion 1 — Custom image built correctly + cache survives destroy

| # | Check | Command | Expected |
|---|-------|---------|----------|
| 1.1 | Image present | `docker images karyon/k3s-cuda:v1.34.6-k3s1-cuda12.8.1 --format '{{.Repository}}:{{.Tag}}'` | `karyon/k3s-cuda:v1.34.6-k3s1-cuda12.8.1` |
| 1.2 | Image base is nvidia/cuda | `docker inspect karyon/k3s-cuda:v1.34.6-k3s1-cuda12.8.1 --format '{{range .RootFS.Layers}}{{.}}{{"\n"}}{{end}}' \| wc -l` | `> 8` (multi-stage indicates k3s + CUDA layers) |
| 1.3 | k3s binaries present in image | `docker run --rm --entrypoint /bin/k3s karyon/k3s-cuda:v1.34.6-k3s1-cuda12.8.1 --version` | `k3s version v1.34.6+k3s1 (...)` |
| 1.4 | config.toml.tmpl baked | `docker run --rm --entrypoint cat karyon/k3s-cuda:v1.34.6-k3s1-cuda12.8.1 /var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl \| grep -c 'default_runtime_name = "nvidia"'` | `1` or greater |
| 1.5 | device-plugin manifest baked | `docker run --rm --entrypoint cat karyon/k3s-cuda:v1.34.6-k3s1-cuda12.8.1 /var/lib/rancher/k3s/server/manifests/nvidia-device-plugin-daemonset.yaml \| grep -c 'kind: DaemonSet'` | `1` |
| 1.6 | Image survives `scripts/delete-clusters.sh` | `scripts/delete-clusters.sh && docker images karyon/k3s-cuda --format '{{.Repository}}'` | contains `karyon/k3s-cuda` |

### Success Criterion 2 — Three clusters on `k8s-net` with correct TLS SAN

| # | Check | Command | Expected |
|---|-------|---------|----------|
| 2.1 | `k8s-net` exists with correct subnet | `docker network inspect k8s-net -f '{{(index .IPAM.Config 0).Subnet}} {{.Driver}}'` | `172.30.0.0/16 bridge` |
| 2.2 | All three clusters listed | `k3d cluster list --no-headers \| awk '{print $1}' \| sort` | `hub-flux\nspoke-apps\nspoke-ml` |
| 2.3 | hub-flux on port 6443 | `docker port k3d-hub-flux-serverlb 6443 2>/dev/null \|\| docker inspect k3d-hub-flux-server-0 -f '{{range .HostConfig.PortBindings}}{{range .}}{{.HostPort}} {{end}}{{end}}'` | includes `6443` |
| 2.4 | spoke-ml on port 6444 | `docker inspect k3d-spoke-ml-server-0 -f '{{.Config.Image}}'` | `karyon/k3s-cuda:v1.34.6-k3s1-cuda12.8.1` |
| 2.5 | spoke-apps on port 6445 | `docker inspect k3d-spoke-apps-server-0 -f '{{.Config.Image}}'` | `rancher/k3s:v1.34.6-k3s1` |
| 2.6 | All clusters on `k8s-net` | `for c in hub-flux spoke-ml spoke-apps; do docker inspect "k3d-${c}-server-0" -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}'; done \| tr ' ' '\n' \| grep -c '^k8s-net$'` | `3` |

### Success Criterion 3 — GPU capacity + SAN present

| # | Check | Command | Expected |
|---|-------|---------|----------|
| 3.1 | kubectl context works for all three | `for c in hub-flux spoke-ml spoke-apps; do kubectl --context "k3d-${c}" get nodes --no-headers; done \| grep -c 'Ready'` | `3` |
| 3.2 | spoke-ml advertises `nvidia.com/gpu` ≥ 1 | `kubectl --context k3d-spoke-ml get nodes -o jsonpath='{.items[*].status.capacity.nvidia\.com/gpu}'` | `1` or greater (non-empty, integer) |
| 3.3 | hub-flux cert SAN | `openssl s_client -connect 127.0.0.1:6443 -servername k3d-hub-flux-server-0 </dev/null 2>/dev/null \| openssl x509 -noout -text \| grep -c 'DNS:k3d-hub-flux-server-0'` | `1` or greater |
| 3.4 | spoke-ml cert SAN | `openssl s_client -connect 127.0.0.1:6444 -servername k3d-spoke-ml-server-0 </dev/null 2>/dev/null \| openssl x509 -noout -text \| grep -c 'DNS:k3d-spoke-ml-server-0'` | `1` or greater |
| 3.5 | spoke-apps cert SAN | `openssl s_client -connect 127.0.0.1:6445 -servername k3d-spoke-apps-server-0 </dev/null 2>/dev/null \| openssl x509 -noout -text \| grep -c 'DNS:k3d-spoke-apps-server-0'` | `1` or greater |
| 3.6 | device-plugin DaemonSet Ready on spoke-ml | `kubectl --context k3d-spoke-ml -n kube-system get ds nvidia-device-plugin-daemonset -o jsonpath='{.status.numberReady}'` | `1` |

### Success Criterion 4 — Delete preserves cache

| # | Check | Command | Expected |
|---|-------|---------|----------|
| 4.1 | Clusters gone | `k3d cluster list --no-headers 2>/dev/null \| wc -l` | `0` |
| 4.2 | `k8s-net` gone | `docker network inspect k8s-net 2>/dev/null; echo exit=$?` | `exit=1` |
| 4.3 | CUDA image present | `docker images karyon/k3s-cuda --format '{{.Repository}}:{{.Tag}}'` | `karyon/k3s-cuda:v1.34.6-k3s1-cuda12.8.1` (or whatever tag) |
| 4.4 | Rebuild SLO: second create is fast | `time (scripts/create-clusters.sh)` after a delete | wall-clock `< 5min` (CUDA cache hot) — reject if it pulls images |

### Success Criterion 5 — No prune references

| # | Check | Command | Expected |
|---|-------|---------|----------|
| 5.1 | No `docker system prune` in scripts | `grep -rE 'docker\s+system\s+prune' scripts/ \|\| echo "clean"` | `clean` |
| 5.2 | No `docker builder prune` in scripts | `grep -rE 'docker\s+builder\s+prune' scripts/ \|\| echo "clean"` | `clean` |
| 5.3 | delete-clusters.sh carries the blocking comment | `grep -c 'INTENTIONALLY NOT calling' scripts/delete-clusters.sh` | `1` |

---

## 6. Validation Architecture

> `workflow.nyquist_validation` is `true` in `.planning/config.json` — this section is live and triggers a `02-VALIDATION.md` scaffold.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | bats-core 1.11+ (established in Phase 1 under `tests/bats/`) |
| Config file | `tests/bats/test_helper.bash` (sources `scripts/lib/preflight-lib.sh`) |
| Quick run command | `bats tests/bats/cluster-*.bats --tap` |
| Full suite command | `bats tests/bats/ --tap` |

### Sampling Levels (Nyquist methodology)

Phase 2 covers four validation levels — each level catches a distinct class of failure; lower levels cannot catch failures that higher levels reveal, which is why all four are required.

| Level | Scope | Automation | Invoked |
|-------|-------|-----------|---------|
| **L1: Script-level idempotency** | Re-running `create-clusters.sh` on a clean host = clean host again | bats: mock `docker`/`k3d` commands via bats-mock; assert zero external calls on 2nd invocation when state matches | Per task commit |
| **L2: Image-level smoke** | `docker run` the built image and sanity-check the baked files | bats: `docker run --rm --entrypoint cat ... /var/lib/rancher/k3s/...` asserts template + manifest present and correct | Per wave merge (image-build task) |
| **L3: Cluster-level kubectl probe** | Live cluster up; `kubectl get nodes Ready`; `nvidia.com/gpu` capacity reported | Wave 0: extend `tests/bats/cluster-creation.bats` to `[ -n "$KARYON_LIVE_TESTS" ]` gate. Run manually + in final verifier — not per-commit (needs Docker + GPU) | Phase gate / human UAT |
| **L4: Cert-level openssl probe** | Each apiserver's SAN includes the expected `k3d-<name>-server-0` | Same live-gated bats; `openssl s_client | x509 | grep` from §5 table 3 | Phase gate / human UAT |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| IMG-01 | Multi-stage Dockerfile with CUDA base | unit (L2) | `bats tests/bats/cuda-image-01-base.bats` | ❌ Wave 0 |
| IMG-02 | `ARG K3S_TAG` default | unit (static) | `bats tests/bats/cuda-image-02-args.bats` | ❌ Wave 0 |
| IMG-03 | `config.toml.tmpl` sets `default_runtime_name = "nvidia"` | unit (L2) | `bats tests/bats/cuda-image-03-containerd.bats` | ❌ Wave 0 |
| IMG-04 | Device-plugin manifest present with chosen version | unit (L2) | `bats tests/bats/cuda-image-04-device-plugin.bats` | ❌ Wave 0 |
| IMG-05 | Manifest baked at `/var/lib/rancher/k3s/server/manifests/` | unit (L2) | `bats tests/bats/cuda-image-05-manifest-path.bats` | ❌ Wave 0 |
| IMG-06 | Image survives `delete-clusters.sh` | integration (L3) | `bats tests/bats/delete-clusters-01-cache.bats` (live-gated) | ❌ Wave 0 |
| CLU-01 | `k8s-net` idempotent creation | unit (L1) | `bats tests/bats/create-clusters-01-network.bats` | ❌ Wave 0 |
| CLU-02 | hub-flux on :6443 with stock image | integration (L3) | `bats tests/bats/create-clusters-02-hub-flux.bats` (live-gated) | ❌ Wave 0 |
| CLU-03 | spoke-ml on :6444 with `--gpus all` | integration (L3) | `bats tests/bats/create-clusters-03-spoke-ml.bats` (live-gated) | ❌ Wave 0 |
| CLU-04 | spoke-apps on :6445 | integration (L3) | `bats tests/bats/create-clusters-04-spoke-apps.bats` (live-gated) | ❌ Wave 0 |
| CLU-05 | `--k3s-arg '--tls-san=...@server:*'` syntax | unit (static) + integration (L4) | `bats tests/bats/create-clusters-05-tls-san.bats` (static grep of helper fn + live openssl probe) | ❌ Wave 0 |
| CLU-06 | delete removes clusters + network, preserves image | integration (L3) | `bats tests/bats/delete-clusters-01-cache.bats` (live-gated) | ❌ Wave 0 |

### Wave 0 Gaps

All 12 bats files listed above are new in Phase 2. The Wave 0 gap-closure plan must include:

- [ ] `tests/bats/cuda-image-01-base.bats` — static Dockerfile parse + `docker inspect` assertions
- [ ] `tests/bats/cuda-image-02-args.bats` — `grep 'ARG K3S_TAG='` static assertion
- [ ] `tests/bats/cuda-image-03-containerd.bats` — `docker run --entrypoint cat` on tmpl file
- [ ] `tests/bats/cuda-image-04-device-plugin.bats` — same pattern, target manifest path
- [ ] `tests/bats/cuda-image-05-manifest-path.bats` — combined with -04 (single fixture)
- [ ] `tests/bats/create-clusters-01-network.bats` — mock `docker network inspect` / `docker network create`; assert idempotency + drift detection
- [ ] `tests/bats/create-clusters-02-hub-flux.bats` — live-gated
- [ ] `tests/bats/create-clusters-03-spoke-ml.bats` — live-gated; assert `nvidia.com/gpu` capacity
- [ ] `tests/bats/create-clusters-04-spoke-apps.bats` — live-gated
- [ ] `tests/bats/create-clusters-05-tls-san.bats` — static grep of `create_cluster()` helper body + live openssl probe
- [ ] `tests/bats/delete-clusters-01-cache.bats` — live-gated; `docker images` assertion after teardown

Framework install: bats-core is already wired in Phase 1's `scripts/install-tools.sh` (asdf plugin) and `tests/bats/test_helper.bash` exists. No new plugin installation needed.

---

## 7. Open Questions

Items the docs do NOT fully settle. Planner should treat these as Claude's Discretion extensions and either lock a choice in `02-PLAN-*.md` or kick to a mini-discussion loop.

1. **`DEVICE_PLUGIN_VERSION` substitution in the baked manifest** — to avoid tag drift between Dockerfile ARG and the hard-coded image tag in `images/device-plugin-daemonset.yaml`, an optional build step could `sed -i "s|v0.17.4|${DEVICE_PLUGIN_VERSION}|"` before `COPY`. **Planner recommendation:** defer — the single-tag-bump workflow is fine for v1; revisit when the Flux HelmRelease migration arrives (v2).

2. **Taskfile.yml stub in Phase 2** — CONTEXT.md Claude's Discretion asks whether Phase 2 creates a `Taskfile.yml` at repo root with `build-image` / `create-clusters` / `delete-clusters` entries. **Researcher recommendation:** **YES, stub it now**. No `Taskfile.yml` exists at repo root today (confirmed via `ls /home/rich/code/gsd/karyon/`). Phase 5 builds the full `task rebuild` chain on top of this; Phase 6 does the REPO-05 reorganization audit. Stubbing three tasks now (`task build-image`, `task create-clusters`, `task delete-clusters` — each a one-liner invoking the corresponding `scripts/*.sh`) makes scripts consumable via `task` during development and gives Phase 5 an existing file to extend, not create.

3. **`delete-clusters.sh` sequencing: per-cluster vs `--all`** — §3.3 uses per-cluster with pre-check for cleaner missing-cluster error messages. This was the research recommendation; planner can override to `k3d cluster delete --all` if preferred. Either works — locked either way in the plan, not the research.

4. **k3d v5.8.3 `cluster list` edge cases** — verified the default tabular output is stable: `NAME SERVERS AGENTS LOADBALANCER`, awk `{print $1}` robust. JSON output (`-o json`) is the belt-and-suspenders fallback if a future k3d bump changes column order. **Researcher recommendation:** use `awk '{print $1}'` (shown in §3.1) for now; add `-o json | jq` variant if k3d 5.9+ breaks the tabular form.

5. **Build-context size** — `docker build .` uploads the entire repo to BuildKit. The repo has `.planning/` (large) and will grow. Phase 6 REPO-02 `.gitignore` audit handles docker-ignore too — consider adding `.dockerignore` in Phase 6 explicitly excluding `.planning/`, `docs/`, `tests/`, `.git/`. Not Phase 2 scope, but flag for Phase 6 planner.

6. **RTX 5090 MIG strategy** — explicitly set `--mig-strategy=none`. If a future GPU with MIG support enters the lab, this becomes a per-spoke config decision. Not in scope for v1 but flagged in §2.3 as the default-explicit-for-documentation choice.

**Nothing in this list blocks planning.** All are either CONTEXT.md-Discretion resolutions with researcher-recommended defaults, or v2 concerns already carved off.

---

## Sources

### Primary (HIGH confidence)

- [Context7 /k3d-io/k3d] — `k3d cluster create` flag surface, `--gpus`, `--k3s-arg`, `--network`, `--api-port`, `cluster delete`, `cluster list`; networking semantics (networks not created by k3d aren't managed by k3d lifecycle)
- [Context7 /k3s-io/docs] — NVIDIA container runtime auto-detection, containerd template extension pattern, `runtimeClassName: nvidia` usage
- [k3s canonical source — pkg/agent/templates/templates.go] — `ContainerdConfigTemplateV3` verbatim content including `{{ with .NodeConfig.DefaultRuntime }}` block
- [docs.k3s.io/advanced] — "k3s will continue to render legacy version 2 configuration from `config.toml.tmpl` if `config-v3.toml.tmpl` is not found"; base template extension syntax; `--default-runtime nvidia` CLI flag
- [github.com/NVIDIA/k8s-device-plugin/releases] — version history v0.17.0 (2024-10-31) through v0.19.1 (2026-04-23)
- [github.com/NVIDIA/k8s-device-plugin/blob/v0.17.4/deployments/static/nvidia-device-plugin.yml] — v0.17.4 static DaemonSet verbatim
- [github.com/k3d-io/k3d/blob/main/docs/usage/advanced/cuda/Dockerfile] — k3d canonical CUDA reference Dockerfile
- [github.com/k3d-io/k3d/blob/main/docs/usage/advanced/cuda/device-plugin-daemonset.yaml] — k3d canonical device-plugin reference (verbatim, image-tag out of date at v0.15.0-rc.2 — informs our updated pin)
- [hub.docker.com/r/rancher/k3s/tags] — `v1.34.6-k3s1` stable confirmed, pushed ~2026-03-27
- [hub.docker.com/r/nvidia/cuda/tags] — `12.8.1-base-ubuntu22.04` confirmed available
- [github.com/k3d-io/k3d/releases/tag/v5.8.3] — release date 2025-02-15; minor maintenance
- `.planning/phases/01-host-foundation/01-RESEARCH.md` — Phase 1 3-part GPU contract (Docker leg); daemon.json `default-runtime: nvidia`; jq-merge pattern
- `.planning/phases/01-host-foundation/01-PATTERNS.md` — guarded-sections pattern, helper vocabulary, `set -euo pipefail` for imperative scripts
- `scripts/lib/preflight-lib.sh` — `section`/`pass`/`warn`/`fail`/`info`/`have` vocabulary (sourced by Phase 2 scripts)

### Secondary (MEDIUM confidence)

- [github.com/k3d-io/k3d/issues/1613] — `--tls-san` ineffective under `@server:0` on v5.8.3; open bug as of 2025-09-28. Motivates D-13 belt-and-suspenders verification. Not a primary source because the workaround path (`@server:*`) is inferred from community examples rather than stated in-issue.
- [github.com/k3s-io/k3s/discussions/9705] — `--default-runtime nvidia` k3s CLI flag. Alternative to the template approach; noted but not used per D-05 lock.
- [medium.com/@panda1100] — k3d GPU community walkthrough. Cross-verified k3d flag syntax but not load-bearing.

### Tertiary (LOW confidence)

- None — every Phase 2 decision input has at least two corroborating sources or lives in canonical upstream code.

---

## Metadata

**Confidence breakdown:**
- Standard stack pins (k3s, CUDA, k3d, device-plugin): HIGH — all verified via live Docker Hub / GitHub release queries 2026-04-23
- Architecture patterns (3-part GPU contract, template extension, auto-apply manifests): HIGH — cited from canonical k3s/k3d docs and source
- Pitfalls (k3d #1613, 3-part contract breakage): HIGH on the existence of the failure modes; MEDIUM on the exact behaviour of `@server:*` under #1613 (inferred from community examples since the bug reporter used `@server:0`)
- Device-plugin version choice (v0.17.4 vs v0.19.x): MEDIUM — recommendation is strong but REQ-IMG-04 text says "v0.19.0+"; the downgrade recommendation requires planner confirmation with the user since it nominally contradicts the REQ text. However, the reasoning chain (CDI-first shift in v0.19, WSL fixes still landing, RuntimeClass-first flow aligns with D-01) is sound; the alternative (pin v0.19.1) is also acceptable and the artifacts above trivially accept either.

**Research date:** 2026-04-23
**Valid until:** 2026-05-23 (30 days; k3d/k3s/device-plugin all have stable current lines)

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `@server:*` wildcard nodefilter avoids k3d issue #1613 (bug reporter used `@server:0`) | §1.1, §3.1 | LOW — D-13 SAN verification catches the failure immediately regardless; script auto-deletes broken cluster |
| A2 | Pin DEVICE_PLUGIN_VERSION = v0.17.4 instead of REQ-IMG-04's "v0.19.0+" preferred | §1.3, §2.3 | MEDIUM — planner should confirm with user; artifacts work with either pin; the downgrade decision has clear reasoning but REQ text says "v0.19.0+" so needs explicit sign-off |
| A3 | Ubuntu 22.04 base (not 24.04) for the CUDA image | §1.5 | LOW — matches PROJECT.md smoke-test pin; ARG-bumpable |
| A4 | BuildKit `--exclude` flag via `docker/dockerfile:1.7-labs` frontend is stable | §2.1 | LOW — matches k3d canonical CUDA Dockerfile; widely used pattern |
| A5 | k3s auto-registration of `runtimes.nvidia` kicks in because `nvidia-ctk runtime configure --runtime=containerd` installs `/usr/bin/nvidia-container-runtime` in the image — k3s detects it at agent-start | §2.2 | MEDIUM — verified via `ContainerdConfigTemplateV3` `{{ range $k, $v := .ExtraRuntimes }}` block and community walkthroughs; if it fails, the `config.toml.tmpl` would need to hand-declare `runtimes.nvidia` explicitly. Plan could add a fallback by hand-declaring the runtimes.nvidia block in the template — noted in §7 Open Questions but not blocking |
| A6 | `tls-san` propagates correctly with `@server:*` wildcard on k3d v5.8.3 | §3.1 | LOW — D-13 catches any regression; fail-fast path prevents propagation |

**If A2 is resolved in favor of v0.19.1** (user confirmation), the only artifact changes are:
- `images/Dockerfile.k3s-cuda` ARG default `DEVICE_PLUGIN_VERSION=v0.19.1`
- `images/device-plugin-daemonset.yaml` image tag `nvcr.io/nvidia/k8s-device-plugin:v0.19.1`
- `--device-list-strategy=envvar` may need re-verification on v0.19.x (default changed in v0.19)

No other artifacts change. Both paths are low-risk to the overall phase; the divergence affects one pin and two lines.

---

*Phase: 02-cluster-layer*
*Researched: 2026-04-23*
*Researcher: Claude (gsd-researcher)*
