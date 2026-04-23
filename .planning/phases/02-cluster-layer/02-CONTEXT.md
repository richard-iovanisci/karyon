# Phase 2: Cluster Layer - Context

**Gathered:** 2026-04-23
**Status:** Ready for planning

<domain>
## Phase Boundary

Deliver the custom `karyon/k3s-cuda` Docker image and stand up the three k3d clusters on a shared Docker network with correct `--tls-san` wiring. Scope:

- `images/Dockerfile.k3s-cuda` — multi-stage build. FROM `nvidia/cuda:12.8.1-base-ubuntu22.04` (final stage); build stage layers k3s binaries from `rancher/k3s:v1.34.6-k3s1`.
- `images/config.toml.tmpl` — containerd template setting `default_runtime_name = "nvidia"`; `COPY`'d into the image at `/var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl`.
- `images/device-plugin-daemonset.yaml` — NVIDIA device-plugin DaemonSet manifest; `COPY`'d into the image at `/var/lib/rancher/k3s/server/manifests/` (k3s auto-apply dir) so `nvidia.com/gpu` capacity is available at t=0.
- `scripts/create-clusters.sh` — idempotently creates `k8s-net` bridge network (pinned CIDR `172.30.0.0/16`) and three k3d clusters: `hub-flux` (6443, stock k3s), `spoke-ml` (6444, `--gpus all`, custom CUDA image), `spoke-apps` (6445, stock k3s). Each cluster passes `--k3s-arg '--tls-san=k3d-<name>-server-0@server:*'`. Serial creation; post-create `openssl` SAN verification per cluster.
- `scripts/delete-clusters.sh` — removes the three clusters + `k8s-net`, explicitly defends the docker build cache (comments + post-run verify that `karyon/k3s-cuda` image still exists).

Out of scope (owned elsewhere):
- Flux bootstrap on `hub-flux` → Phase 3.
- Spoke SA + ClusterRoleBinding, kubeconfig Secrets, hub-side Kustomizations → Phase 4.
- GPU smoke-test pod, podinfo, health-check, `task fix-dns`, `task rebuild` chain → Phase 5.
- Taskfile.yml full reorganization (REPO-05), ADR-002, ADR-005, `docs/gpu-notes.md`, `docs/architecture.md` Mermaid, shellcheck CI, `docker system/builder prune` lint (DESTROY-04) → Phase 6.
- v2 Flux HelmRelease migration for the device-plugin (add when DCGM-exporter or larger NVIDIA stack is needed).

</domain>

<decisions>
## Implementation Decisions

### Device Plugin Delivery
- **D-01:** NVIDIA device-plugin DaemonSet is **baked into the custom image only** (no Flux HelmRelease in v1). REQ-IMG-05 + ROADMAP §Phase 2 success criterion #1 require `nvidia.com/gpu` capacity at t=0. Bake-only eliminates the k3s ↔ Flux reconciliation-ownership conflict. Helm path is deferred to v2 when DCGM-exporter or additional NVIDIA stack components justify a reconciled release cadence.
- **D-02:** Device-plugin manifest lives at `images/device-plugin-daemonset.yaml` (matches `starter.md` repo layout). Dockerfile does `COPY images/device-plugin-daemonset.yaml /var/lib/rancher/k3s/server/manifests/`. Human-readable, diffable, lintable separately from Dockerfile.

### Dockerfile + Image Tagging
- **D-03:** `images/Dockerfile.k3s-cuda` exposes three build ARGs: `K3S_TAG` (default `v1.34.6-k3s1`), `CUDA_TAG` (default `12.8.1-base-ubuntu22.04`), `DEVICE_PLUGIN_VERSION` (default set by researcher to the current 2026 stable — v0.17.3 or v0.19.x per REQ-IMG-04 "v0.19.0+"). All three pins are a single-line diff for future bumps.
- **D-04:** Final image tag is **compound**: `karyon/k3s-cuda:v1.34.6-k3s1-cuda12.8.1`. Both pinned versions are visible in the tag. No `:latest` tag — explicit reproducibility over developer convenience.
- **D-05:** containerd template lives at `images/config.toml.tmpl` (committed file), `COPY`'d into the image at `/var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl`. Starts from the current canonical k3s v1.34.x template (researcher fetches it at planning time), overrides `default_runtime_name = "nvidia"` with an inline comment naming the 3-part GPU contract (daemon.json + Ubuntu-base image + this template).
- **D-06:** Dockerfile ARG defaults are the **canonical source of truth** for version pins. A small shell helper (e.g., `images/image-tag.sh`) derives the full tag string from those same pins and is called by both the build step (`docker build -t "$(images/image-tag.sh)" -f images/Dockerfile.k3s-cuda .`) and `scripts/create-clusters.sh` (`--image "$(images/image-tag.sh)"`). Single edit point, zero drift.

### Cluster Creation Script (`scripts/create-clusters.sh`)
- **D-07:** **Inline k3d CLI flags**, wrapped in a `create_cluster()` helper function taking `name port extra_args...`. `--k3s-arg '--tls-san=k3d-<name>-server-0@server:*'` passes as a shell string — cleaner than the YAML `options.k3s.extraArgs` + `nodeFilters` schema. No `config/k3d/*.yaml` files in v1.
- **D-08:** **Serial cluster creation** (`hub-flux` → `spoke-ml` → `spoke-apps`). `set -euo pipefail`; fail-fast on any error. Parallel creation rejected: Docker layer caching makes time savings after the first cluster small; serial simplifies error reporting and survives any Docker Hub rate-limit edge case.
- **D-09:** Idempotency = **"skip if exists + verify expected config"**. `k3d cluster list | grep -qx <name>` → if present, `info "already done, skipping: cluster <name>"`. Additionally verify via `docker inspect` that the container image, API port, and network match expectations; on drift, `warn` and instruct the user to run `scripts/delete-clusters.sh` before retrying. Matches the Phase 1 D-05 guarded-sections pattern.
- **D-10:** Error recovery = **no auto-cleanup; idempotent rerun resumes**. If cluster 2 fails after cluster 1 succeeds, the script exits (set -e) and cluster 1 stays up. User fixes the underlying cause and reruns — D-09 skips cluster 1, retries cluster 2, proceeds to cluster 3. Trap-on-ERR teardown is rejected (throws away working state on transient failures).

### k8s-net Network + SAN Verification
- **D-11:** `k8s-net` pinned to explicit CIDR **`172.30.0.0/16`**, driver `bridge`. Deterministic; avoids WSL eth0 range (172.16–172.24) and common Docker auto-assign conflicts. The diagram in `docs/architecture.md` (Phase 6) renders this subnet.
- **D-12:** Network idempotency: `docker network inspect k8s-net` → if subnet matches `172.30.0.0/16` and driver is `bridge`, `info "already done, skipping: k8s-net"`. If drift (different subnet or driver), `warn` and instruct the user to run `scripts/delete-clusters.sh` first. Mirrors D-09.
- **D-13:** **Belt-and-suspenders SAN verification in `scripts/create-clusters.sh`.** Immediately after each cluster is reported Ready, the script runs `openssl s_client -connect 127.0.0.1:<port> </dev/null 2>/dev/null | openssl x509 -noout -text` and greps for `k3d-<name>-server-0` in the SAN section. If the SAN is missing: `k3d cluster delete <name>` + `fail` loudly with the `--k3s-arg '--tls-san=...'` fix. Rationale: `--tls-san` cannot be fixed post-hoc (ROADMAP §Phase 2 risk); Phase 4 spoke-registration depends on correct SANs; catching early prevents silent propagation. Cost: ~1 second per cluster.

### Delete Script — Build-Cache Defense (`scripts/delete-clusters.sh`)
- **D-14:** Script removes the three clusters first, then `k8s-net` (order matters — containers must detach before network removal). **Top-of-file blocking comment**: `# INTENTIONALLY NOT calling docker system prune or docker builder prune — CUDA build layers must survive the task rebuild SLO (REQ-DESTROY-03).` **Post-run verification**: `docker images karyon/k3s-cuda | grep -q k3s-cuda` → if the image has vanished, `fail` loudly (catches anyone who slips a prune command in downstream). Defense-in-depth before Phase 6's DESTROY-04 lint ships.

### NVIDIA Device Plugin Version Override (REQ-IMG-04)
- **D-15:** `DEVICE_PLUGIN_VERSION` is pinned to **v0.17.4** for this phase, overriding REQ-IMG-04's "v0.19.0+" wording. Rationale: the researcher confirmed in the Phase 2 planning discussion log (2026-04-23) that v0.19.x had not cut a stable release compatible with RTX 5090 / Blackwell / sm_120 at research time; v0.17.4 is the current nvcr.io/nvidia/k8s-device-plugin stable release for this GPU generation. REQUIREMENTS.md text ("v0.19.0+") remains authoritative for future bumps — this D-15 is the phase-scoped exception. References: `02-CONTEXT.md §decisions D-03` (DEVICE_PLUGIN_VERSION ARG), `images/device-plugin-daemonset.yaml` image tag, `images/Dockerfile.k3s-cuda` ARG default, `tests/bats/cuda-image-04-device-plugin.bats` IMG-04 assertion.

### Claude's Discretion

These were not explicitly discussed; planner/researcher decides:
- **Taskfile.yml scope in Phase 2** — whether Phase 2 stubs a new `Taskfile.yml` at repo root with `build-image` / `create-clusters` / `delete-clusters` entries, or leaves all Taskfile wiring to Phase 5/6 per the ROADMAP parallelization note (REPO-05 "reorganization pass" during Phase 5). **Guidance:** If no `Taskfile.yml` exists at repo root, Phase 2 should stub the minimum useful set (those three tasks) so scripts are usable via `task` during development; Phase 6 does the full REPO-05 audit. If one already exists, append those three tasks idempotently.
- **Image build invocation** — whether `scripts/create-clusters.sh` builds the CUDA image on-demand if missing, vs a dedicated `scripts/build-image.sh` invoked as a prerequisite. **Guidance:** Prefer a separate `scripts/build-image.sh` that `scripts/create-clusters.sh` optionally calls (`if ! docker images | grep -q karyon/k3s-cuda; then ./scripts/build-image.sh; fi`). Keeps responsibilities clean and lets `task rebuild` (Phase 5) compose the chain explicitly.
- **Exact `DEVICE_PLUGIN_VERSION` pin** — REQ-IMG-04 specifies "v0.19.0+"; researcher confirms the current 2026 stable release and whether v0.19+ is cut, and whether any RTX 5090 / sm_120 compatibility notes apply. Use an explicit pin; no floating tag.
- **`config.toml.tmpl` body** — start from the upstream k3s v1.34.x containerd template (researcher fetches current canonical version); override only `default_runtime_name = "nvidia"`. Do NOT hand-write from scratch; k3s template includes auto-loaded NVIDIA-runtime registration that the reference template already carries.
- **Dockerfile build-stage structure** — multi-stage ordering (k3s-source stage + CUDA-runtime stage), BuildKit cache mount usage, layer ordering for maximal cache hits; implementation detail.
- **Device-plugin DaemonSet flags** — current NVIDIA recommendations for a GPU-only cluster: `--mig-strategy=none` (RTX 5090 has no MIG), `--fail-on-init-error=true`, `--pass-device-specs=true`, tolerations/nodeSelector that are compatible with spoke-ml being single-node. Researcher picks current 2026 defaults.
- **`scripts/delete-clusters.sh` sequencing detail** — whether to call `k3d cluster delete` per cluster then `docker network rm k8s-net`, or use `k3d cluster delete --all` + explicit network removal; either works — pick the form with clearer error messages for missing-cluster cases.
- **k3d v5.8.3 behavior on config-drift edge cases** — e.g., what `k3d cluster list` outputs if a cluster's Docker container was manually stopped but the k3d-internal state file says running. Researcher verifies stability of the `grep`-based idempotency check across the pinned k3d release.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project-level specs
- `.planning/PROJECT.md` — Core value, locked architectural decisions (ADR-001..005 rationale), pinned k3s/CUDA versions, public-repo secrets posture, the 3-part k3d GPU contract.
- `.planning/REQUIREMENTS.md` §CUDA Image (IMG-01..06), §Cluster Layer (CLU-01..06), §Teardown & Rebuild (DESTROY-03..04 referenced for defense-in-depth) — 12 REQ-IDs in this phase plus the two DESTROY rules that shape D-14.
- `.planning/ROADMAP.md` §Phase 2 — goal, 5 success criteria, HIGH-risk notes (three-part GPU contract, `--tls-san` via `--k3s-arg`, Docker rate limits, build-cache preservation), parallelization with Phase 6.

### Prior-phase context (Phase 1 — completed)
- `.planning/phases/01-host-foundation/01-CONTEXT.md` — Phase 1 decisions that carry in: D-05 (guarded-sections), D-06 (`~/.karyon/shell-init.sh` for asdf shim precedence), D-08 (systemd unit install pattern), D-11 (daemon.json jq-merge pattern with `default-runtime: nvidia`).
- `.planning/phases/01-host-foundation/01-PATTERNS.md` — Pattern Map: shebang + `set -euo pipefail` (imperative scripts) vs `set -u` (preflight), ANSI-color gate, `section`/`pass`/`warn`/`fail`/`info`/`have` vocabulary, guarded-sections idiom, blocker-with-remediation message style. **Phase 2's two new scripts follow these patterns verbatim.**
- `.planning/phases/01-host-foundation/01-RESEARCH.md` — Phase 1 research on 3-part GPU contract, daemon.json schema, `nvidia-ctk runtime configure` — the Docker-runtime half; Phase 2 owns the containerd + CUDA-base-image halves.
- `.planning/phases/01-host-foundation/01-VERIFICATION.md` — completed Phase 1 verification (10/10 must-haves); use as a reference for Phase 2 verification artifact structure.

### Existing code to reuse / extend
- `scripts/lib/preflight-lib.sh` — shared helpers. `scripts/create-clusters.sh` and `scripts/delete-clusters.sh` **must** `source` this library, not duplicate.
- `scripts/preflight.sh` + `scripts/install-*.sh` — style references for guarded-section structure and remediation-rich `fail` messages.
- `prereqs.sh` — original voice / ethos; new scripts should feel continuous.
- `starter.md` — repo-layout reference: confirms `images/Dockerfile.k3s-cuda`, `images/device-plugin-daemonset.yaml`, `scripts/create-clusters.sh`, `scripts/delete-clusters.sh` paths.
- `.tool-versions` — `k3d 5.8.3`, `kubectl 1.35.0`, `task 3.50.0`, `jq 1.8.1`, `yq 4.53.2`. Phase 2 scripts must work with exactly these pins.
- `config/wslconfig`, `config/wsl.conf`, `docs/wsl-networking.md` — Phase 1 artifacts. Do not touch, but understand the NAT-mode mandate so the `k8s-net` at `172.30.0.0/16` does not regress PRE-14's bridge-curl probe.
- `/etc/docker/daemon.json` (host-level side effect from Phase 1) — contains `default-runtime: nvidia` + `dns` keys. Phase 2 assumes this is present; do not re-patch.

### External references (researcher must fetch current docs at planning time — no URLs assumed)
- **k3d v5.8.3** — `cluster create` flag surface (`--api-port`, `--network`, `--image`, `--gpus all`, `--k3s-arg '--tls-san=...'`, `--servers`, `--agents`); `cluster delete` + network lifecycle; `--k3s-arg` vs top-level `--tls-san` (the latter is NOT a k3d flag — see ROADMAP risk note); 2026 stability of the `cluster list` output format.
- **k3s `v1.34.6-k3s1`** — auto-apply manifests directory semantics (`/var/lib/rancher/k3s/server/manifests/`), containerd config template path (`/var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl`), template format and version-specific syntax, `default_runtime_name` override mechanics.
- **NVIDIA container toolkit + containerd** — `default_runtime_name = "nvidia"` containerd template pattern for k3s; interaction with k3d's CUDA-image flow (current 2026 NVIDIA docs; confirm deprecation status of `nvidia-container-runtime` vs CDI path).
- **NVIDIA device plugin** — current stable release (v0.17.3 vs v0.19+), recommended DaemonSet manifest for k3s, runtime flags (`--mig-strategy=none`, `--pass-device-specs=true`, `--fail-on-init-error=true`), tolerations/nodeSelectors for a single-node GPU cluster, RTX 5090 / Blackwell / sm_120 compatibility notes.
- **Docker Engine bridge networks** — `docker network create --subnet=172.30.0.0/16 --driver=bridge k8s-net` semantics on WSL2; `docker network inspect` output shape for idempotency verification; cleanup semantics in `docker network rm`.
- **openssl s_client / x509** — portable bash-friendly way to assert a cert includes a given SAN (without jq-parsing; `grep -q` against the text output is acceptable per D-13).
- **`rancher/k3s:v1.34.6-k3s1` upstream image layout** — location of k3s binaries for the multi-stage `COPY --from`.

### ADR pointers (authored in Phase 6 — consistency required)
- **ADR-002 (k3d-over-Kind)** — Phase 2 decisions must be consistent with the GPU-support / idle-RAM / `--network`-control rationale. Do not write ADR content here; just don't contradict it.
- **ADR-005 (k3s + CUDA version pins)** — Phase 2 implements the pinned versions; ADR-005 (Phase 6) captures the why. Use the pins exactly as stated in PROJECT.md.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `scripts/lib/preflight-lib.sh` — full helper library (`section`/`pass`/`warn`/`fail`/`info`/`have`, ANSI-color gate, counters). Both Phase 2 scripts source this. **Do NOT duplicate helper functions.**
- Phase 1 install scripts (`install-docker.sh`, `install-nvidia-container-toolkit.sh`, `install-tools.sh`) — direct style references for guarded-section structure in `create-clusters.sh` and `delete-clusters.sh`.
- `prereqs.sh` / `scripts/preflight.sh` — style reference for section headers and remediation-oriented error messages.

### Established Patterns
- **`set -euo pipefail`** — imperative side-effecting scripts (Phase 2 scripts, Phase 1 install scripts). `set -u` only is preflight-specific.
- **ANSI colors gated on `[[ -t 1 ]]`** — preserved in `preflight-lib.sh`.
- **Guarded-sections** — every logical step checks state first and logs `info "already done, skipping: X"` or `pass "creating: X"`. The script's stdout becomes a live audit log.
- **Blocker messages include exact remediation command** — e.g., `fail "k8s-net subnet drift (expected 172.30.0.0/16) → scripts/delete-clusters.sh, then rerun create-clusters.sh"`.
- **`have()` for command presence** — POSIX `command -v` based, from the lib. Never `which`/`type`.

### Integration Points
- `scripts/preflight.sh` (Phase 1) must pass before `scripts/create-clusters.sh` runs. Create-clusters should begin with a delegation (e.g., `scripts/preflight.sh > /dev/null 2>&1 || { printf "preflight blockers — run scripts/preflight.sh\n" >&2; exit 1; }`). Preflight already verifies daemon.json runtime, docker group, tool pins, free ports (6443–6445), and no residual k3d/network state.
- `/etc/docker/daemon.json` (Phase 1 D-11) contains `default-runtime: nvidia`. This is the Docker leg of the 3-part GPU contract; Phase 2 adds the containerd template + CUDA-base-image legs.
- `~/.karyon/shell-init.sh` (Phase 1 D-06) ensures asdf shim precedence for `k3d`, `kubectl`, `helm`. Phase 2 scripts rely on this being sourced in the user's shell; scripts do not re-source it.
- **Downstream blocker for Phase 3**: `scripts/bootstrap-flux.sh` uses `kubectl --context k3d-hub-flux` to reach the cluster on :6443. Phase 2 must ensure the kubeconfig context is written correctly by `k3d cluster create` (k3d does this by default; no special handling needed).
- **Downstream blocker for Phase 4**: `scripts/register-spokes-for-flux.sh` uses `k3d-<spoke>-server-0` (Docker embedded DNS on `k8s-net`) as the kubeconfig `server:` URL. This depends on (a) `k8s-net` being a shared bridge network (D-11), and (b) each cluster's cert carrying the `--tls-san` (D-13). Phase 4 is blocked if D-13 verification misses.
- **`task rebuild` SLO (Phase 5)**: hinges on the CUDA image surviving `task destroy`. `scripts/delete-clusters.sh` D-14 is the guard.

</code_context>

<specifics>
## Specific Ideas

- Prefer the `scripts/delete-clusters.sh` filename (matches `starter.md` layout), NOT `scripts/cluster-ops.sh destroy` or similar subcommand-style. One-file-per-verb.
- `create_cluster()` helper in `scripts/create-clusters.sh` takes `name port extra_args...` so the three call-sites read naturally:
  ```bash
  create_cluster hub-flux   6443
  create_cluster spoke-ml   6444 --gpus all --image "$(images/image-tag.sh)"
  create_cluster spoke-apps 6445
  ```
- `scripts/delete-clusters.sh` must carry a top-of-file blocking comment:
  ```bash
  # INTENTIONALLY NOT calling `docker system prune` or `docker builder prune`.
  # CUDA build layers must survive the `task rebuild` SLO (REQ-DESTROY-03).
  # A lint in Phase 6 (REQ-DESTROY-04) will enforce this across scripts/.
  ```
- Single source of truth for the image tag: `images/image-tag.sh` echoes `karyon/k3s-cuda:<K3S_TAG>-cuda<CUDA_TAG_SHORT>`. The build step and create-clusters both invoke it via command substitution. Dockerfile ARG defaults match what the helper reads.
- Every `fail` message tells the user exactly what to run to fix it:
  - `k8s-net subnet drift → scripts/delete-clusters.sh && scripts/create-clusters.sh`
  - `k3d missing or version drift → scripts/install-tools.sh`
  - `karyon/k3s-cuda image missing → scripts/build-image.sh (or docker build -f images/Dockerfile.k3s-cuda)`
  - `--tls-san missing on cert → check --k3s-arg syntax; cluster was deleted, rerun scripts/create-clusters.sh after fixing`
  - `CUDA image deleted after destroy → scripts/delete-clusters.sh hit a prune path; audit the script`
- Use Phase 1's `section "…"` headers to group the script's output:
  - `section "Preflight gate"` (one-line pass or bail)
  - `section "k8s-net network"` (idempotent create/verify)
  - `section "hub-flux cluster"` → `section "spoke-ml cluster"` → `section "spoke-apps cluster"` (one per cluster, with pass/verify steps nested)
- Keep all `fail`/`warn` vocabulary consistent with Phase 1 so the user sees one interface.

</specifics>

<deferred>
## Deferred Ideas

- **v2: Flux HelmRelease migration for device-plugin** — Adopt `nvidia-device-plugin` Helm chart via Flux HelmRelease on spoke-ml when DCGM-exporter or a larger NVIDIA stack (gpu-feature-discovery, node-feature-discovery) justifies a reconciled release cadence. Requires either a `kubernetes.io/managed-by` annotation on the baked manifest or an explicit delete-before-helm step to avoid k3s auto-apply / Flux ownership conflicts.
- **Taskfile.yml full REPO-05 reorganization** — Phase 2 stubs the minimum `Taskfile.yml` if one doesn't exist; Phase 6 does the comprehensive audit.
- **ADR-002 (k3d-over-Kind), ADR-005 (version pins)** — authored in Phase 6 per ROADMAP parallelization schedule. Phase 2 must not block on these; ADR content is already locked in `PROJECT.md`.
- **`docs/gpu-notes.md` (DOCS-04), `docs/architecture.md` Mermaid (DOCS-02)** — Phase 6. Phase 2 produces the artifacts and locks the CIDR; diagrams render later.
- **`config/k3d/*.yaml` declarative cluster configs** — explicitly rejected in D-07 in favor of inline CLI flags. Revisit only if k3d upstream pushes config files as the primary UX.
- **Parallel cluster creation** — rejected in D-08. Revisit only if serial creation crosses into the `task rebuild` SLO (it won't, given CUDA-image layer cache).
- **Trap-on-ERR teardown on partial failure** — rejected in D-10. Keeps user state intact across transient failures.
- **`:latest` floating image tag** — rejected in D-04. Revisit only if CI/CD integration requires a moving pointer.
- **Docker Hub credential / registry mirror for rate-limit avoidance** — not needed for serial creation with layer caching in a single-user lab. Revisit if CI integration hits anonymous limits.
- **`--tls-san` verification outside the create script** (e.g., in Phase 5 health-check only) — rejected in D-13 because the failure mode is a one-way door and Phase 4 depends on correct SANs.

</deferred>

---

*Phase: 02-cluster-layer*
*Context gathered: 2026-04-23*
