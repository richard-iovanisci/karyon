# Phase 2: Cluster Layer - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in `02-CONTEXT.md` — this log preserves the alternatives considered.

**Date:** 2026-04-23
**Phase:** 02-cluster-layer
**Areas discussed:** Device plugin delivery, Dockerfile ARG surface + image tagging, create-clusters.sh style, k8s-net subnet + cert-SAN verification

---

## Device Plugin Delivery

### Q1: How should the NVIDIA device-plugin DaemonSet be delivered to spoke-ml in v1?

| Option | Description | Selected |
|--------|-------------|----------|
| Bake-only in v1 | `COPY images/device-plugin-daemonset.yaml` into `/var/lib/rancher/k3s/server/manifests/` at build time. `nvidia.com/gpu` capacity up at t=0. No Flux HelmRelease in v1 — Helm path becomes a v2 migration. Simplest, satisfies ROADMAP success criterion #1, zero ownership conflict. | ✓ |
| Bake + Flux HelmRelease takeover | Bake the DaemonSet (t=0 capacity). Phase 3/4 installs a HelmRelease that takes ownership. Requires `managed-by` annotation or delete-before-helm step. More moving parts. | |
| Helm-only (deferred capacity) | No baked manifest. HelmRelease via Flux later. Breaks REQ-IMG-05 and ROADMAP success criterion #1. | |

**User's choice:** Bake-only in v1 (Recommended)
**Notes:** Resolves the apparent IMG-04/IMG-05 overlap in favor of the explicit ROADMAP success criterion. Helm migration path preserved in `<deferred>`.

### Q2: Where does the device-plugin manifest YAML live in the repo?

| Option | Description | Selected |
|--------|-------------|----------|
| `images/device-plugin-daemonset.yaml` | Matches `starter.md` repo structure. Dockerfile does `COPY images/device-plugin-daemonset.yaml /var/lib/rancher/k3s/server/manifests/`. Human-readable, diffable. | ✓ |
| Inline heredoc in Dockerfile | `RUN cat > /var/lib/... <<EOF`. One less file but manifest hidden inside Dockerfile, harder to lint. | |

**User's choice:** `images/device-plugin-daemonset.yaml`

---

## Dockerfile ARG Surface + Image Tagging

### Q3: Which ARGs should `images/Dockerfile.k3s-cuda` expose?

| Option | Description | Selected |
|--------|-------------|----------|
| Full: `K3S_TAG`, `CUDA_TAG`, `DEVICE_PLUGIN_VERSION` | All three pinnable at build time. Defaults in Dockerfile. Future bumps are a single-line diff per arg. | ✓ |
| Minimal: `K3S_TAG` only | Satisfies letter of REQ-IMG-02 but future bumps require Dockerfile edits. | |

**User's choice:** Full — `K3S_TAG`, `CUDA_TAG`, `DEVICE_PLUGIN_VERSION`

### Q4: How should the final image tag encode version info?

| Option | Description | Selected |
|--------|-------------|----------|
| Compound: `karyon/k3s-cuda:v1.34.6-k3s1-cuda12.8.1` | Both pinned versions in the tag. Reproducible, greppable. | ✓ |
| k3s tag only: `karyon/k3s-cuda:v1.34.6-k3s1` | Loses CUDA-version traceability. | |
| Compound + `:latest` | Convenience, but risks drift. | |

**User's choice:** Compound: `karyon/k3s-cuda:v1.34.6-k3s1-cuda12.8.1`

### Q5: How is `config.toml.tmpl` delivered?

| Option | Description | Selected |
|--------|-------------|----------|
| Committed at `images/config.toml.tmpl`, `COPY`'d | Full template in-repo. Readable, diffable, can carry comments about the `default_runtime_name = "nvidia"` override. | ✓ |
| Heredoc in Dockerfile | One less file but template hidden inside Dockerfile. | |

**User's choice:** Committed at `images/config.toml.tmpl`, `COPY`'d

### Q6: Source-of-truth for image version pins?

| Option | Description | Selected |
|--------|-------------|----------|
| Dockerfile ARG defaults canonical; shared shell helper derives the tag | Single edit point. Both `docker build` and `create-clusters.sh --image` call a helper (e.g. `images/image-tag.sh`). | ✓ |
| Separate `images/.versions.env` | Decouples pins from Dockerfile. Extra file. | |
| Hardcode in both places | Brittle. | |

**User's choice:** Dockerfile ARG defaults are canonical; `images/image-tag.sh`-style helper derives the tag.

---

## `scripts/create-clusters.sh` Style

### Q7: Inline k3d CLI flags vs committed k3d config YAMLs?

| Option | Description | Selected |
|--------|-------------|----------|
| Inline CLI flags in a helper shell function | `create_cluster()` takes name/port/extra_args. `--k3s-arg '--tls-san=...'` reads cleanly as a shell string. No `k3d.io/v1alpha5` schema pin to track. | ✓ |
| Committed `config/k3d/*.yaml` configs | Declarative but verbose (`options.k3s.extraArgs` + `nodeFilters`). Schema-pin concern. | |

**User's choice:** Inline CLI flags

### Q8: Serial or parallel cluster creation?

| Option | Description | Selected |
|--------|-------------|----------|
| Serial, fail-fast | Layer caching after first cluster means small time savings from parallel. Simpler error messages. Survives Docker Hub rate-limit edge cases. | ✓ |
| Parallel with wait | Saves ~30–60s. Complicates error capture (bash `wait` + `$?` per pid). | |

**User's choice:** Serial, fail-fast

### Q9: If a cluster already exists, what happens?

| Option | Description | Selected |
|--------|-------------|----------|
| Skip if exists + verify expected config | `k3d cluster list | grep` then `docker inspect` to confirm image/port/network match. On drift: `warn` and point at `scripts/delete-clusters.sh`. Matches D-05 Phase 1. | ✓ |
| Skip if exists, no verify | Simpler but config drift slips through. | |
| Fail fast + require explicit delete | Breaks idempotency. | |

**User's choice:** Skip if exists + verify expected config

### Q10: Error recovery on partial failure?

| Option | Description | Selected |
|--------|-------------|----------|
| No auto-cleanup; idempotent rerun resumes | `set -euo pipefail` exits on first failure. User fixes the cause and reruns; succeeded clusters skip, failed one retries. | ✓ |
| Cleanup trap destroys partial state on failure | Aggressive — throws away working state on transient failures. | |

**User's choice:** No auto-cleanup; idempotent rerun resumes

---

## k8s-net Subnet + Cert-SAN Verification

### Q11: k8s-net subnet — auto-assign or explicit CIDR?

| Option | Description | Selected |
|--------|-------------|----------|
| Explicit CIDR: `172.30.0.0/16` | Deterministic. Avoids WSL eth0 range (172.16–172.24) and other Docker auto-assign conflicts. | ✓ |
| Docker auto-assign | Works most of the time; can collide with WSL NICs. | |

**User's choice:** Explicit CIDR `172.30.0.0/16`

### Q12: Verify `--tls-san` landed in each apiserver cert post-creation?

| Option | Description | Selected |
|--------|-------------|----------|
| Yes — verify in `create-clusters.sh` right after each cluster is ready | `openssl s_client` + `x509` + `grep` for the expected SAN; on miss, delete cluster and fail loud. Catches the one-way-door failure before it propagates. | ✓ |
| No — leave SAN verification to Phase 5 health-check | Error surfaces 3 phases later. | |

**User's choice:** Yes — verify in `create-clusters.sh` immediately after each cluster

### Q13: If k8s-net already exists from a prior run?

| Option | Description | Selected |
|--------|-------------|----------|
| Inspect subnet + driver; skip if match, warn if drift | `docker network inspect k8s-net` — if subnet matches `172.30.0.0/16` and driver is `bridge`, skip. On drift, `warn` and point at `scripts/delete-clusters.sh`. Mirrors cluster idempotency. | ✓ |
| Skip if exists, no verify | Misconfigured `k8s-net` slips through. | |

**User's choice:** Inspect subnet + driver; skip if match, warn if drift

### Q14: delete-clusters.sh — how aggressive in defending the build cache?

| Option | Description | Selected |
|--------|-------------|----------|
| Explicit top-of-file comment + post-run verify image survives | Comment: `# INTENTIONALLY NOT calling docker system prune or docker builder prune`. At end: `docker images karyon/k3s-cuda` — if missing, fail loud. Defense-in-depth before Phase 6 DESTROY-04 lint. | ✓ |
| Just don't call prune | Relies on Phase 6 lint. One less safety net. | |

**User's choice:** Explicit comments + post-run verify image survives

---

## Claude's Discretion

The user deferred these to planner/researcher with guidance in CONTEXT.md:
- Whether Phase 2 stubs a `Taskfile.yml` or leaves all Taskfile wiring to Phase 5/6
- Whether `create-clusters.sh` builds the image on-demand or requires a separate `scripts/build-image.sh` precondition
- Exact `DEVICE_PLUGIN_VERSION` pin (research fetches current 2026 stable)
- `config.toml.tmpl` body — start from upstream k3s v1.34.x canonical, override only `default_runtime_name`
- Dockerfile multi-stage layer ordering + BuildKit cache usage
- Device-plugin DaemonSet runtime flags (`--mig-strategy=none`, `--pass-device-specs=true`, etc.)
- delete-clusters.sh sequencing detail (`k3d cluster delete --all` vs per-cluster)
- k3d v5.8.3 edge cases on drifted cluster state

## Deferred Ideas

Noted for future phases / v2:
- Flux HelmRelease migration for device-plugin (v2 — when DCGM-exporter or larger NVIDIA stack is needed)
- Full Taskfile.yml REPO-05 reorganization (Phase 6)
- ADR-002, ADR-005 authoring (Phase 6)
- docs/gpu-notes.md, docs/architecture.md Mermaid (Phase 6)
- `config/k3d/*.yaml` declarative cluster configs (rejected in D-07; revisit only if k3d upstream pushes it)
- Parallel cluster creation (rejected; revisit only if serial crosses rebuild SLO)
- Trap-on-ERR teardown (rejected in D-10)
- `:latest` floating tag (rejected in D-04)
- Docker Hub credential / registry mirror (not needed for single-user lab)
- SAN verification outside create-script (rejected in D-13; failure is one-way-door)
