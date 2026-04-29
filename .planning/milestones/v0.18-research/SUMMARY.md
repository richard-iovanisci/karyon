# Project Research Summary

**Project:** karyon
**Domain:** Local hub-spoke Flux multi-cluster Kubernetes lab on Windows 11 + WSL2 + k3d (with optional GPU spoke on RTX 5090)
**Researched:** 2026-04-22
**Confidence:** HIGH

## Executive Summary

karyon is a reproducible local Kubernetes lab — three k3d clusters (hub + apps spoke + GPU spoke) on a shared Docker bridge, with hub-only Flux reconciling into the spokes via `spec.kubeConfig`. The canonical reference is `fluxcd/flux2-hub-spoke-example`; the starter is ~90% complete against it. All four research dimensions converge on HIGH confidence in the recommended approach: stack pins are verified against release feeds, architecture follows an official pattern with known-good YAML, features align with existing public Flux-lab repos, and the 25 pitfalls catalogued are well-documented rather than speculative.

The single load-bearing path is **hub kustomize-controller → `k3d-<spoke>-server-0:6443` over the shared `k8s-net` bridge, with TLS validated via a spoke-side `--tls-san` and auth via a legacy Secret-backed ServiceAccount token**. Four things must be right together: the TLS SAN at spoke creation, the Secret key name (`value.yaml`) in the kubeconfig Secret on the hub, Docker's embedded DNS on the user-defined bridge, and k3d's CoreDNS NodeHosts (which goes stale on Docker restart — `task fix-dns` is the correct workaround).

The primary risks are host-layer (WSL2 + Docker + GPU chain) rather than Kubernetes-layer. RTX 5090 / sm_120 requires CUDA 12.8+, a custom k3s+CUDA Ubuntu-based image (Alpine stock image cannot host the NVIDIA runtime), daemon-wide `default-runtime: nvidia` in `/etc/docker/daemon.json`, and a containerd `config.toml.tmpl` that sets `default_runtime_name = "nvidia"`. Research also surfaced several corrections to starter guidance — most notably that `--tls-san` is not a k3d top-level flag (pass via `--k3s-arg`), that `clusters/hub-flux/flux-system/kustomization.yaml` IS the officially supported customization surface (not "do not touch"), and that `flux bootstrap --path` is effectively immutable after first run.

## Key Findings

### Recommended Stack

All versions pinned and verified against GitHub release lists and/or Docker Hub tags on 2026-04-22. Full detail: `STACK.md`.

**Core technologies:**

- **k3s image:** `rancher/k3s:v1.34.6-k3s1` — Flux 2.8.x supports K8s `>= 1.34.1`; this release fixes the etcd 3.6.6 "zombie-member" bug from v1.34.3
- **k3d CLI:** `5.8.3` — latest stable; v5.8.0 is explicitly broken, v5.9.0 is pre-release
- **Flux CLI:** `2.8.6` (bootstrap pins controllers)
- **kubectl:** `1.34.7` — exact minor match to cluster
- **helm:** `3.20.2` — **stay on Helm 3**; Helm 4 is breaking (SSA-by-default, `--force` rename, post-renderer plugin model, SDK churn). Re-evaluate next milestone.
- **asdf:** `0.18.1` (Go rewrite) — **NOT the bash classic**; v0.15 and earlier are EOL. Integration now requires manually prepending `${ASDF_DATA_DIR:-$HOME/.asdf}/shims` to `PATH`.
- **NVIDIA container toolkit:** `1.19.0-1` — installed from NVIDIA's apt repo, not Ubuntu archive
- **NVIDIA device plugin (Helm chart):** `0.19.0` — Helm is NVIDIA's preferred install path; raw YAML is demo-only
- **CUDA smoke-test image:** `nvcr.io/nvidia/cuda:12.8.0-base-ubuntu22.04` — 12.8 is the first CUDA release with sm_120 (Blackwell) support; **use the `base` variant** to avoid CDI libnvidia-ml mount collisions
- **Custom k3s+CUDA base:** `nvidia/cuda:12.8.1-base-ubuntu22.04` + k3s copied in from `rancher/k3s:v1.34.6-k3s1` stage
- **Windows driver floor:** `572.xx` (Linux-side bridge reports 570.xx — existing `prereqs.sh` gate is correct)

**Copy-paste `.tool-versions`:**

```
kubectl 1.34.7
helm 3.20.2
flux2 2.8.6
k3d 5.8.3
task 3.50.0
jq 1.8.1
yq 4.53.2
```

*(Confirm the flux plugin name — `flux2` vs `flux` — against `asdf plugin list all` before committing. asdf itself is not listed in `.tool-versions`; document its version in README.)*

### Expected Features

Full detail: `FEATURES.md`. Starter ships all 12 table-stakes expected of a public Flux lab; anti-features (Flagger, ArgoCD, GPU Operator, kube-prometheus-stack, real secrets, HA, CI) are correctly and deliberately excluded.

**Must have (already in starter, 12/12):**

- Idempotent `task create-clusters` / `task destroy` with confirmation on destructive ops
- Preflight env gate (`scripts/preflight.sh`, porting `prereqs.sh`)
- Pinned tool + k3s versions via asdf + `.tool-versions`
- `flux bootstrap` path, "do-not-hand-edit" guidance (but see correction below)
- Sample workload proving the pipe works end-to-end (podinfo on spoke-apps, `nvidia-smi` pod on spoke-ml)
- Health-check task with green/red signal
- README with fresh-clone walkthrough
- `.gitignore` for `.env` / kubeconfigs; `.env.example` contract
- Teardown that preserves CUDA build cache

**Should have (5 small gaps flagged by FEATURES.md — requirements must decide accept or defer):**

1. Add `k9s` to `.tool-versions` (1 line, universal TUI via asdf)
2. Mermaid hub-spoke diagram in README or `docs/architecture.md` (~20 lines)
3. `flux check --pre` in preflight and `flux check` in health-check (2 lines)
4. `.env` presence + required-keys check in preflight (fail early, not at `flux bootstrap`)
5. Minimum CI workflow — `shellcheck scripts/*.sh` + `kubeconform` on manifests + `markdownlint` (~50 lines, one GHA file). **PROJECT.md Out of Scope currently excludes CI; reconsider before making the repo publicly visible** — canonical `fluxcd/flux2-hub-spoke-example` ships this.

**Defer (v2+, correctly out of scope):**

- SOPS + age real-secret management (add when a real secret beyond `GITHUB_TOKEN` exists; native Flux support via `decryption.provider: sops`)
- kube-prometheus-stack / Grafana / Loki (violates 20-min rebuild SLO)
- Flagger, ArgoCD, GPU Operator, service mesh, ingress+cert-manager, image automation, HA, framework ML workloads

### Architecture Approach

Full detail: `ARCHITECTURE.md`. Three k3d clusters on one user-defined Docker bridge; hub-only Flux reconciles into spokes via `spec.kubeConfig.secretRef`. Matches `fluxcd/flux2-hub-spoke-example` and Stefan Prodan's 2024 multi-cluster pattern.

**Major components:**

1. **Hub cluster (`hub-flux`)** — only cluster running Flux controllers + only cluster pointed at Git; holds kubeconfig Secrets for every spoke in `flux-system` namespace with key `value.yaml`
2. **GPU spoke (`spoke-ml`)** — custom `k3s+CUDA` image (Ubuntu base, k3s layered in), `--gpus all`, NVIDIA device plugin DaemonSet baked into the image at `/var/lib/rancher/k3s/server/manifests/` (for cold-start) AND reconciled by Flux (for GitOps lifecycle)
3. **Apps spoke (`spoke-apps`)** — stock `rancher/k3s:v1.34.6-k3s1`; runs podinfo
4. **Shared `k8s-net` Docker bridge** — Docker embedded DNS at 127.0.0.11 resolves every container by name across all clusters; enables hub→spoke apiserver traffic via `k3d-<spoke>-server-0:6443`
5. **`flux-reconciler` ServiceAccount on each spoke** — cluster-admin via CRB + explicit `kubernetes.io/service-account-token` Secret (Kubernetes 1.24+ no longer auto-generates); token is non-expiring, correct for a lab

**Build order** (strict dependency chain, with natural phase boundaries):

0. preflight
1. build custom k3s+CUDA image (parallel with 2)
2. create `k8s-net` (parallel with 1)
3. create three clusters (hub + spokes can parallelize; each with `--tls-san`)
4. `flux bootstrap github` on hub (must run sequentially; creates `flux-system` ns)
5. register spokes (SA + CRB + token Secret on spoke, kubeconfig Secret on hub)
6. deploy examples (automatic once step 5 satisfies the Kustomizations)
7. health-check

**Four natural phase boundaries from build order** (ARCHITECTURE.md §"Where Phases Split Naturally"):

1. **Host → Clusters** (end of step 3): three healthy clusters, GPU capacity visible on spoke-ml. Failing here = host-layer issue.
2. **Clusters → Flux hub** (end of step 4): `flux-system` populated, repo self-managing.
3. **Flux hub → Spoke registration** (end of step 5): kubeconfig Secrets on hub, TLS+DNS+RBAC+token all correct. **Highest-risk phase** — deserves its own research pass.
4. **Spoke registration → Workloads** (end of steps 6+7): end-user workflow provable.

Recommend roadmap align one phase per boundary.

### Critical Pitfalls

Full detail: `PITFALLS.md` (25 pitfalls, 18 new beyond starter). Top 5 highest-risk for roadmap attention:

1. **k3d GPU is a three-part contract, not a flag** (P7) — `--gpus all` alone does nothing. Requires ALL of: (a) `/etc/docker/daemon.json` with `"default-runtime": "nvidia"` (via `nvidia-ctk runtime configure --set-as-default`), (b) custom k3s image on Ubuntu base (Alpine stock image cannot host the NVIDIA runtime), (c) custom `config.toml.tmpl` in that image setting `default_runtime_name = "nvidia"` under `[plugins.cri.containerd]`. Verify with `docker info | grep "Default Runtime"` returning `nvidia` and `kubectl describe node` showing `nvidia.com/gpu` capacity > 0.
2. **`--tls-san` must be set at cluster creation (cannot be fixed post-hoc)** (P6) — hub→spoke TLS fails with `x509: certificate is valid for ..., not k3d-spoke-ml-server-0`. Pass via `--k3s-arg '--tls-san=k3d-<name>-server-0@server:*'` on `k3d cluster create`. Recovery cost is MEDIUM — scorched-earth rebuild, not edit.
3. **`spec.kubeConfig` Secret key mismatch reconciles into the hub instead of the spoke** (P18) — if the Secret's data key isn't `value.yaml` (or `value`), controllers silently fall back to the hub's in-cluster ServiceAccount and reconcile into the WRONG cluster while reporting `Ready: True`. Explicitly set `secretRef.key: value.yaml` in the Kustomization; health-check verifies `.status.inventory` contains spoke node names.
4. **`systemd-resolved` stub resolver (127.0.0.53) leaks into Docker containers and breaks CoreDNS upstreams** (P16) — symptom: image pulls time out, CoreDNS logs `no such host`. Fix: `install-docker.sh` must write explicit `"dns": ["1.1.1.1", "8.8.8.8"]` (or equivalent) to `/etc/docker/daemon.json`. Preflight probes `docker run --rm alpine nslookup github.com`.
5. **`GITHUB_TOKEN` leak on public repo + in-cluster Secret is not auto-rotated** (P10) — revoking the PAT on GitHub does NOT rotate Flux's in-cluster Secret; subsequent `flux bootstrap` is an upgrade and also does not rotate. Requires manual `flux create secret git flux-system --password=$NEW_TOKEN`. Prevention: `.gitignore` + gitleaks pre-commit BEFORE first commit. Consider GitHub App auth (Flux 2.5+) for a short-lived-token alternative.

**Additional high-impact pitfalls worth naming in the roadmap:**

- P1 mirrored networking (preflight probe needed; default to NAT mode)
- P4 WSL clock drift after hibernate (`hwclock -s` systemd unit)
- P11 k3d CoreDNS NodeHosts staleness after Docker/WSL restart (`task fix-dns` is correct; do NOT use `K3D_FIX_DNS=1`)
- P14 asdf v0.16 PATH migration (preflight must FAIL, not INFO, if `which kubectl` resolves outside `$HOME/.asdf/shims`)
- P17 `docker system prune` destroys CUDA cache (lint rejects `system prune` / `builder prune` in `scripts/`)

### Must-Address Corrections To The Starter

These are corrections, not new requirements. Update starter-derived artifacts to match research before implementation.

1. **`--tls-san` is NOT a k3d top-level flag.** Pass via `--k3s-arg '--tls-san=k3d-<name>-server-0@server:*'` on `k3d cluster create`, or via the `extraArgs` block in a k3d config file. Fix in `scripts/create-clusters.sh` and any example YAML.
2. **"Don't hand-edit `clusters/hub-flux/flux-system/`" is too broad.** The truth: `gotk-components.yaml` and `gotk-sync.yaml` are regenerated by bootstrap (do NOT edit), but `kustomization.yaml` IS the officially supported customization surface — strategic-merge patches and JSON6902 patches against controllers go there and survive re-bootstrap. Update starter docs.
3. **`flux bootstrap --path` is effectively immutable after first run.** Changing it on a re-bootstrap silently overwrites `gotk-sync.yaml` and prunes everything under the old path. Hard-code `FLUX_PATH=clusters/hub-flux` in `bootstrap-flux.sh` and reject env overrides.
4. **k3d GPU is a three-part contract** (daemon.json default-runtime + Ubuntu-base custom image + containerd `config.toml.tmpl`) — see Critical Pitfalls #1. The starter treats this as "custom image + `--gpus all`"; all three parts must be named in requirements.
5. **`systemd-resolved` 127.0.0.53 propagation breaks CoreDNS in containers.** Docker-install phase must write explicit `dns` to `/etc/docker/daemon.json`. Not currently in starter.
6. **asdf v0.18.1 requires manual `PATH` prepend**, not `. ~/.asdf/asdf.sh` (v0.15 style). Update `install-tools.sh` accordingly; upgrade preflight to FAIL on system-binary precedence.

## Implications for Roadmap

The four phase boundaries in ARCHITECTURE.md map cleanly to roadmap phases. Recommended phase structure:

### Phase 1: Host Foundation — WSL + Docker + GPU + Tools

**Rationale:** Nothing else works until WSL2, Docker Engine (native, no Desktop), NVIDIA container toolkit, and asdf-managed tools are correct. The existing `prereqs.sh` already covers detection; this phase ports it to `scripts/preflight.sh` and adds the install scripts + config templates.

**Delivers:** `task preflight` exits 0; `docker info` shows `Default Runtime: nvidia`; `command -v kubectl` resolves under `$HOME/.asdf/shims/`.

**Addresses:** Docker install, NVIDIA install, tool install, WSL config (`.wslconfig` NAT-mode default, hwclock unit, cgroup-v2 template).

**Must avoid:** P1 (mirrored), P2 (nftables), P3 (Docker Desktop conflict), P4 (clock drift), P5 (hybrid cgroups), P14 (asdf PATH), P16 (systemd-resolved DNS), P24 (daemon.json merger).

**Correction integration:** daemon.json explicit `dns`; asdf PATH-prepend snippet; `.wslconfig` template omits cgroup-v1 kernel params.

### Phase 2: Cluster Layer — Image build + `k8s-net` + three clusters

**Rationale:** Custom k3s+CUDA image is the longest-building artifact; creating it before clusters means subsequent rebuilds hit cache. Clusters depend on the image (spoke-ml) and the shared network (all three). Matches architecture boundary 1.

**Delivers:** Three clusters on `k8s-net`, all nodes Ready, `nvidia.com/gpu` capacity on spoke-ml, TLS SANs present on every apiserver cert.

**Uses:** `rancher/k3s:v1.34.6-k3s1`, custom `k3s-cuda:v1.34.6-k3s1-cuda-12.8.x-ubuntu22.04`, k3d 5.8.3.

**Implements:** Shared-bridge topology with Docker embedded DNS; RuntimeClass `nvidia`; baked-in device-plugin manifest.

**Must avoid:** P6 (TLS SAN missing — now use `--k3s-arg --tls-san=...`), P7 (GPU three-part contract), P17 (build cache destruction in destroy), P20 (docker.io rate limit on parallel creates), P25 (k3s auto-runtime + hand-rolled config collision).

### Phase 3: Flux Hub — bootstrap + root reconciliation

**Rationale:** Hub must be self-managing before spokes can be registered (their kubeconfig Secrets land in `flux-system`, which doesn't exist until bootstrap). Matches architecture boundary 2.

**Delivers:** `flux-system` namespace populated; root Kustomization Ready; repo self-managing.

**Uses:** Flux 2.8.6 CLI + bootstrap-installed controllers; GitHub PAT from `.env`.

**Implements:** `clusters/hub-flux/flux-system/` (bootstrap-managed) + `clusters/hub-flux/spokes/` (hand-authored, reconciled by root).

**Must avoid:** P8 (overly-broad "don't edit" — `kustomization.yaml` IS the patch surface), P9 (path immutability — hard-code in script), P10 (token leak + in-cluster Secret rotation).

### Phase 4: Spoke Registration — SAs + kubeconfig Secrets

**Rationale:** Highest-risk phase. TLS SAN, CA data, Secret key name, token format, and Docker DNS must all be right for hub→spoke reconciliation. Matches architecture boundary 3. Deserves dedicated research during planning.

**Delivers:** Two kubeconfig Secrets on hub (`spoke-ml-kubeconfig`, `spoke-apps-kubeconfig`), each with `value.yaml` key, each pointing to `https://k3d-<spoke>-server-0:6443`, each verified from inside a hub pod.

**Uses:** Legacy Secret-backed SA tokens (`kubernetes.io/service-account-token` type) — non-expiring, correct for a lab; NOT `kubectl create token` (expires during idle periods).

**Must avoid:** P18 (Secret key mismatch → silent reconcile into hub), P19 (mixing `kubeConfig` + `serviceAccountName` → impersonation fails).

### Phase 5: Workloads + Health — sample apps + `task fix-dns` + health-check

**Rationale:** End-user workflow proof. Matches architecture boundary 4.

**Delivers:** podinfo on spoke-apps; `nvidia-smi` smoke-test on spoke-ml; `task health-check` green end-to-end (including `flux check`, cross-cluster DNS resolution from hub pod, GPU capacity, `.env` not committed, `docker Default Runtime: nvidia`).

**Must avoid:** P11 (CoreDNS NodeHosts staleness — `task fix-dns` via stop/start, NOT `K3D_FIX_DNS=1`), P12 (libnvidia-ml CDI mount — stick with `base` CUDA variant, toolkit >= 1.17).

### Phase 6: Repo Hygiene + Docs + ADRs

**Rationale:** Public-repo contract. Can run partially in parallel with earlier phases but must complete before the repo is advertised. The five ADRs (WSL+Docker, k3d-vs-Kind, Flux-vs-ArgoCD, hub-only-Flux, k8s-version-pin) all correspond to locked decisions already made.

**Delivers:** `.gitignore` with `.env`; `.env.example`; `docs/adr/001..005`; README with fresh-clone walkthrough; `docs/architecture.md` (with Mermaid diagram — flagged gap); `docs/rebuild-runbook.md`; `docs/gpu-notes.md`; optional `docs/flux-hub-spoke.md` documenting the `kustomization.yaml` patch surface and path-immutability.

**Must avoid:** P10 (gitleaks pre-commit before first commit), P22 (cross-cluster DNS scope — document that `k8s-net` shared network enables hub→spoke apiserver traffic only, NOT cross-cluster service discovery).

### Phase Ordering Rationale

- **Host → Clusters → Flux → Spokes → Workloads** is a strict dependency chain — cannot reorder. Flux hub can't bootstrap until a cluster exists; spoke Secrets can't be applied until `flux-system` namespace exists.
- **Image build parallelizes with network creation** (step 1 & 2 of build order); `task create-clusters` can express this as `deps:` in Taskfile.
- **Hub + spoke cluster creates parallelize** — different containers, shared network already exists.
- **Per-spoke registration parallelizes** — independent SAs and Secrets.
- **Repo hygiene / docs / ADRs can interleave** across all phases — each ADR is written when its decision locks.
- **Phase 4 is the single highest-risk point** — isolating it as its own phase with an explicit validation script lets the roadmapper schedule a dedicated research pass if needed.

### Research Flags

Phases likely needing deeper research during planning (`/gsd-research-phase`):

- **Phase 4 (Spoke Registration):** Highest compounding-risk phase. TLS SAN + DNS + Secret key + token type + CA data all interact. Worth a 2-3 question research pass to validate the exact kubeconfig Secret layout, `.status.inventory` probe, and failure-mode recovery before writing scripts.
- **Phase 2 (Cluster Layer / GPU):** The three-part GPU contract has moving parts (k3s auto-runtime behavior in v1.32+ may collide with hand-rolled `config.toml.tmpl` — P25). Research the exact minimal `config.toml.tmpl` against k3s v1.34.6 defaults before building the image.

Phases with standard patterns (skip research-phase):

- **Phase 1 (Host Foundation):** `prereqs.sh` already covers the detection logic; install scripts follow official NVIDIA / Docker / asdf docs.
- **Phase 3 (Flux Hub):** `flux bootstrap github` is well-documented and idempotent. Corrections are about customization surface and path-immutability — documented once in phase plan.
- **Phase 5 (Workloads + Health):** podinfo and `nvidia-smi` pod are stock patterns.
- **Phase 6 (Repo Hygiene + Docs):** standard repo hygiene; no research needed.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Every pin verified against GitHub release list or Docker Hub tag API on 2026-04-22. Flux 2.8.6 is one day old at research time; k3s v1.34.6 is ~3 weeks old. |
| Features | HIGH | Canonical reference (`fluxcd/flux2-hub-spoke-example`) exists and is under 60 days old; starter is ~90% aligned. Five gaps are polish-level, not correctness. |
| Architecture | HIGH on Flux patterns / Dockerfile / SA recipes (verified against Flux v1 Kustomization spec + k3d CUDA guide); MEDIUM on cross-cluster Docker DNS semantics (documented for single-cluster, inferred-but-widely-practiced for shared-network multi-cluster); MEDIUM on `task fix-dns` being the right 2026-era workaround (no shipped single-flag fix). |
| Pitfalls | HIGH for well-known issues (mirrored mode, clock skew, GPU runtime, Flux bootstrap, systemd-resolved); MEDIUM for RTX 5090 specifics (ecosystem still moving); MEDIUM for k3s v1.34.6 (release is recent). |

**Overall confidence:** HIGH. The lab sits in well-documented terrain. The sm_120 / PyTorch coupling is the only area where research confidence is MEDIUM — and the starter's correct scope decision (smoke-test limited to `nvidia-smi`, no framework workload in v1) specifically sidesteps it.

### Gaps to Address

Questions the requirements or roadmap phase must resolve before implementation:

- **asdf plugin name for Flux:** community registry commonly uses `flux2` (not `flux`). Confirm against `asdf plugin list all | grep flux` and commit the name before `.tool-versions` lands. *Route to: requirements (lock tool-version contents).*
- **k3s line bump timing:** v1.34.6 is 3 weeks old at research time; v1.35.x is the next line. Decide whether lab follows N-1-latest or pins a line for a milestone. *Route to: requirements (version-pinning policy) → ADR-005 update.*
- **Helm 3 → 4 migration timing:** Helm 3.20.2 is in bug-fix support through 2026-07-08 and security through 2026-11-11. Decide whether v1 ships Helm 3 (yes) and when a later milestone re-evaluates. *Route to: ADR when Helm 4 ecosystem catches up; not a v1 blocker.*
- **CI loop decision:** PROJECT.md Out-of-Scope currently excludes GitHub Actions. The canonical public-repo contract includes kubeconform + shellcheck. *Route to: requirements — accept minimum CI before going public, or explicitly defer in README.*
- **k9s inclusion in `.tool-versions`:** flagged in FEATURES.md as a 1-line ergonomic win. *Route to: requirements (accept or defer with the other four small gaps).*
- **Mermaid diagram format:** `docs/architecture.md` is in the starter spec but diagram format unspecified. *Route to: requirements (Mermaid is free via GitHub rendering; accept unless reason to avoid).*
- **`flux check` in preflight + health-check:** 2-line add; idiomatic. *Route to: requirements (accept or defer).*
- **`.env` schema validation in preflight:** currently fails late at `flux bootstrap`. *Route to: requirements (accept — trivially small, meaningful UX improvement).*

## Sources

### Primary (HIGH confidence)

- [Flux Kustomization spec v1 (kustomize-controller)](https://github.com/fluxcd/kustomize-controller/blob/main/docs/spec/v1/kustomizations.md) — definitive for `spec.kubeConfig.secretRef` and default key `value`/`value.yaml`
- [fluxcd/flux2-hub-spoke-example](https://github.com/fluxcd/flux2-hub-spoke-example) — canonical hub-spoke reference
- [k3d CUDA guide (v5.8.3)](https://k3d.io/v5.8.3/usage/advanced/cuda/) — authoritative Dockerfile + `config.toml.tmpl` + daemon.json contract
- [k3d networking design (v5.8.3)](https://k3d.io/v5.8.3/design/networking/) — NodeHosts behavior
- [Flux bootstrap customization](https://fluxcd.io/flux/installation/configuration/bootstrap-customization/) — `kustomization.yaml` IS the patch surface
- [Flux bootstrap for GitHub](https://fluxcd.io/flux/installation/bootstrap/github/) — path-immutability behavior implied
- [Kubernetes service-accounts-admin](https://kubernetes.io/docs/reference/access-authn-authz/service-accounts-admin/) — legacy Secret-backed tokens still supported
- [Docker bridge driver](https://docs.docker.com/engine/network/drivers/bridge/) — embedded DNS on user-defined networks
- [K3s v1.34.X release notes](https://docs.k3s.io/release-notes/v1.34.X) — etcd 3.6, zombie-member fix
- [NVIDIA Container Toolkit install guide](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) — `nvidia-ctk runtime configure --set-as-default`
- [CUDA 12.8 release notes](https://docs.nvidia.com/cuda/archive/12.8.0/cuda-toolkit-release-notes/index.html) — sm_120 support floor
- [asdf upgrade guide v0.16](https://asdf-vm.com/guide/upgrading-to-v0-16.html) — PATH-prepend required, `.sh` sourcing removed
- GitHub release feeds for k3s, k3d, flux2, kubernetes, helm, task, asdf, jq, mikefarah/yq, NVIDIA/nvidia-container-toolkit, NVIDIA/k8s-device-plugin (all pulled 2026-04-22)

### Secondary (MEDIUM confidence)

- [Stefan Prodan — FluxCD Multi-cluster Architecture (2024)](https://stefanprodan.com/blog/2024/fluxcd-multi-cluster-architecture/)
- [ahgraber/homelab-gitops-k3s](https://github.com/ahgraber/homelab-gitops-k3s) — popular k3s+Flux homelab reference
- k3d issues #1009 / #1112 / #1515 / #1516 — CoreDNS NodeHosts staleness + `K3D_FIX_DNS` breakage
- microsoft/WSL + moby/moby + docker/for-win issues — mirrored-mode bridge breakage (#10494, #10683, #13013, moby/moby#48201, moby/moby#48136, docker/for-win#14691)
- microsoft/WSL #10006 / #8204 — clock drift after hibernate
- microsoft/WSL #6655 / #6662 — nftables + hybrid cgroup module gaps
- pytorch/pytorch #159207 / #167244 — sm_120 rollout
- NVIDIA/nvidia-container-toolkit #289 / #631 / #672 — libnvidia-ml mount collisions + daemon.json merger
- k3s-io/k3s #9274 — CoreDNS NodeHosts staleness on k3s side
- fluxcd/flux2 discussions #1517 / #2161 — bootstrap path overwrite + PAT rotation

### Tertiary (LOW confidence, corroborating)

- OneUptime blog (2026-03) on hub-spoke — cross-checked Secret key claim against Flux v1 spec
- vLLM / NVIDIA developer forum threads on RTX 5090 PyTorch status
- Nick Janetakis blog — Docker Engine in WSL2 without Desktop
- Stuart Leeks — clock-skew systemd unit pattern
- cr0x.net / alex-ber.medium.com — systemd-resolved in Docker containers fix
- Patrick Wu's blog — WSL2 iptables-legacy fix
- Panda1100 Medium — k3d+NVIDIA device plugin walkthrough

---
*Research completed: 2026-04-22*
*Ready for roadmap: yes*
