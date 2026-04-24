# Roadmap: karyon

## Overview

karyon builds a reproducible three-cluster local Kubernetes lab (hub-flux + spoke-ml GPU + spoke-apps) on Windows 11 + WSL2 + k3d, with hub-only Flux reconciling into spokes via `spec.kubeConfig`. Execution proceeds in a strict dependency chain — nothing above works until the layer below is green. **Host Foundation** brings WSL + Docker (explicit `dns` + `default-runtime: nvidia`) + the NVIDIA container toolkit + asdf tools up to a state where `scripts/preflight.sh` exits `0` on a clean dev box. **Cluster Layer** builds the custom k3s+CUDA image and stands up the three clusters on `k8s-net` with correct `--tls-san` wiring. **Flux Hub** bootstraps self-managing GitOps on `hub-flux`. **Spoke Registration** (highest-risk — DNS + TLS + CA + RBAC + Secret-key all converge here) lands the two kubeconfig Secrets on the hub. **Workloads + Health** deploys podinfo + a `nvidia-smi` GPU smoke-test, ships `task fix-dns` and `task health-check`, and proves the core-value requirement: `task rebuild` in < 20 minutes. **Repo Hygiene / Docs / ADRs** ships the public-repo contract (gitignore + `.env.example` + gitleaks + 5 ADRs + runbook + Mermaid diagram + CI workflow) and can run largely in parallel with Phases 1–5 during plan execution. Every v1 REQ-ID maps to exactly one phase; `task rebuild` (DESTROY-05/06) lives in Phase 5 but its success depends on Phases 1–4 being green first.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Host Foundation** - WSL + Docker + GPU toolkit + asdf tools + preflight gate pass *(completed 2026-04-23)*
- [ ] **Phase 2: Cluster Layer** - Custom k3s+CUDA image + `k8s-net` + three clusters with correct `--tls-san`
- [ ] **Phase 3: Flux Hub Bootstrap** - `flux bootstrap github` on hub-flux, self-managing GitOps, documented patch surface
- [ ] **Phase 4: Spoke Registration** - SA + cluster-admin + legacy-Secret tokens + hub-side kubeconfig Secrets with `value.yaml` key
- [ ] **Phase 5: Workloads + Health + Rebuild** - podinfo + `nvidia-smi` pod + `task fix-dns` + `task health-check` + `task rebuild` < 20 min
- [ ] **Phase 6: Repo Hygiene + Docs + ADRs** - Public-safe repo, 5 ADRs, README, Mermaid diagram, rebuild runbook, CI workflow

## Phase Details

### Phase 1: Host Foundation
**Goal**: `scripts/preflight.sh` exits `0` on a clean dev box — WSL2 + Docker (with explicit `dns` + `default-runtime: nvidia`) + NVIDIA container toolkit + asdf-pinned tools are all in a reproducible, idempotent state.
**Depends on**: Nothing (first phase)
**Parallelizable with**: Phase 6 (Repo Hygiene / Docs) — ADR-001, ADR-005 drafts and `.env.example` can be authored alongside; see "Parallelization notes" below.
**Risk**: MEDIUM — host-layer (WSL mirrored-mode edge cases, systemd-resolved 127.0.0.53 leak, asdf v0.18 PATH migration, clock drift, docker-group membership, Docker-Desktop-integration detection) is where most first-run failures cluster. Recovery is always "fix and rerun preflight", never a scorched-earth rebuild.
**Requirements**: HOST-01, HOST-02, HOST-03, HOST-04, HOST-05, HOST-06, HOST-07, TOOLS-01, TOOLS-02, TOOLS-03, PRE-01, PRE-02, PRE-03, PRE-04, PRE-05, PRE-06, PRE-07, PRE-08, PRE-09, PRE-10, PRE-11, PRE-12, PRE-13, PRE-14
**Success Criteria** (what must be TRUE):
  1. `scripts/preflight.sh` runs read-only and exits `0` on a correctly-configured dev box; exits `1` with a specific, actionable message on any blocker (WSL kernel, Ubuntu 24.04, systemd active, resource floor, GPU chain, tool pins, ports 6443–6445 / 8080–8082, residual k3d/network state, Docker-Desktop integration, `.env` keys present, asdf shim precedence, `systemd-resolved` 127.0.0.53 stub, clock skew > 30 s, cgroup-v2 purity, mirrored-mode bridge-curl probe).
  2. `docker info | grep "Default Runtime"` returns `nvidia`; `/etc/docker/daemon.json` contains an explicit `dns` array so containers do not inherit `systemd-resolved`'s `127.0.0.53` stub.
  3. `command -v kubectl && command -v helm && command -v k3d` all resolve under `$HOME/.asdf/shims/` (NOT `/usr/bin` or `/usr/local/bin`), and their versions match every pin in the checked-in `.tool-versions`.
  4. `config/wslconfig` and `config/wsl.conf` templates exist with documented `systemd=true` + NAT-mode default + `mirrored → NAT` fallback section in `docs/wsl-networking.md`; a systemd unit runs `hwclock -s` on resume.
  5. All install scripts (`install-docker.sh`, `install-nvidia-container-toolkit.sh`, `install-tools.sh`) are idempotent — rerunning them on an already-configured host is a no-op and still exits `0`.
**Plans**: 9 plans (8 waves, incl. 2 gap-closure rounds)

Plans:
- [x] 01-01-PLAN.md — Static foundation: lib extract, config templates, .tool-versions, .env.example, .gitignore, docs/wsl-networking.md
- [x] 01-02-PLAN.md — install-docker.sh: Docker Engine + daemon.json (default-runtime=nvidia + dns) + hwclock unit
- [x] 01-03-PLAN.md — install-nvidia-container-toolkit.sh: NVIDIA toolkit packages + nvidia-ctk runtime configure
- [x] 01-04-PLAN.md — install-tools.sh: asdf binary + shell-init + plugins + pinned versions from .tool-versions
- [x] 01-05-PLAN.md — scripts/preflight.sh: port prereqs.sh + PRE-01..08 + PRE-08 warn→fail + enhanced PRE-04/PRE-05
- [x] 01-06-PLAN.md — scripts/preflight.sh: append PRE-09..14 (env, shim precedence, resolv, clock, cgroup, bridge-curl)
- [x] 01-07-PLAN.md — bats test infrastructure: test_helper + 5 stub suites (PRE-01/02/09/11/13)
- [x] 01-08-PLAN.md — Round-1 gap closure: CR-01 default-runtime jq pre-check + CR-02 jq-merge writer (install-docker.sh + install-nvidia-container-toolkit.sh)
- [x] 01-09-PLAN.md — Round-2 gap closure: PRE-12 UtcNow fix, PRE-05 k9s parser, PRE-03 mirrored-mode downgrade, util-linux-extra for hwclock

### Phase 2: Cluster Layer
**Goal**: `kubectl --context k3d-<name> get nodes` returns `Ready` for all three clusters, `spoke-ml` advertises `nvidia.com/gpu` capacity ≥ 1, and every apiserver's serving cert includes the `k3d-<name>-server-0` SAN.
**Depends on**: Phase 1 (needs Docker with `default-runtime: nvidia`, pinned k3d/kubectl, preflight green)
**Parallelizable with**: Phase 6 (ADR-002 k3d-over-Kind can land during this phase; image Dockerfile review can parallel docs)
**Risk**: HIGH — the three-part k3d GPU contract (daemon.json `default-runtime: nvidia` + Ubuntu-base custom image + containerd `config.toml.tmpl` with `default_runtime_name = "nvidia"`) is the #1 pitfall in research; `--tls-san` must be passed via `--k3s-arg` (not as a k3d top-level flag — P6) and cannot be fixed post-hoc; docker.io rate limits on parallel creates; `task destroy` must NOT prune the build cache or rebuild breaks its SLO.
**Requirements**: IMG-01, IMG-02, IMG-03, IMG-04, IMG-05, IMG-06, CLU-01, CLU-02, CLU-03, CLU-04, CLU-05, CLU-06
**Success Criteria** (what must be TRUE):
  1. `docker build -t karyon/k3s-cuda:...` produces an image FROM `nvidia/cuda:12.8.1-base-ubuntu22.04` with k3s binaries layered from `rancher/k3s:v1.34.6-k3s1`, a `config.toml.tmpl` setting `default_runtime_name = "nvidia"`, and a NVIDIA device-plugin DaemonSet baked at `/var/lib/rancher/k3s/server/manifests/` — and the build is cached across `task destroy` (build layers survive).
  2. `scripts/create-clusters.sh` idempotently creates the `k8s-net` Docker bridge network (if missing), then stands up `hub-flux` (:6443, stock k3s), `spoke-ml` (:6444, `--gpus all`, custom k3s+CUDA image), and `spoke-apps` (:6445, stock k3s), all attached to `k8s-net`, each passing `--k3s-arg '--tls-san=k3d-<name>-server-0@server:*'`.
  3. `kubectl --context k3d-spoke-ml get nodes -o jsonpath='{.items[*].status.capacity.nvidia\.com/gpu}'` returns a value ≥ 1; `openssl s_client -connect 127.0.0.1:6444 </dev/null 2>/dev/null | openssl x509 -noout -text` shows `k3d-spoke-ml-server-0` among the cert SANs (same for 6443/hub and 6445/spoke-apps).
  4. `scripts/delete-clusters.sh` removes all three clusters and the `k8s-net` network, but `docker images | grep karyon/k3s-cuda` still shows the custom image present afterward (build cache preserved).
  5. No script under `scripts/` calls `docker system prune` or `docker builder prune` (verifiable by grep — enforced as a lint in Phase 6).
**Plans**: 7 plans (5 waves)

Plans:
- [x] 02-01-PLAN.md — Wave 0 test scaffolding: 12 bats files + test_helper.bash extension (REQ coverage: IMG-01..06, CLU-01..06)
- [x] 02-02-PLAN.md — Dockerfile.k3s-cuda + image-tag.sh (IMG-01, IMG-02; Wave 1)
- [x] 02-03-PLAN.md — config.toml.tmpl + device-plugin-daemonset.yaml (IMG-03, IMG-04; Wave 1)
- [x] 02-04-PLAN.md — scripts/build-image.sh + activate IMG-03/05 live bats (IMG-01..06; Wave 2)
- [x] 02-05-PLAN.md — scripts/create-clusters.sh with D-13 SAN verify (CLU-01..05; Wave 3; checkpoint)
- [x] 02-06-PLAN.md — scripts/delete-clusters.sh with D-14 cache defense (CLU-06, IMG-06; Wave 3; checkpoint)
- [x] 02-07-PLAN.md — Taskfile.yml stub (build-image/create-clusters/delete-clusters; Wave 4)

### Phase 3: Flux Hub Bootstrap
**Goal**: `flux --context k3d-hub-flux get kustomizations -A` shows the root `flux-system` Kustomization as `Ready=True`; the hub is self-managing and commits to `clusters/hub-flux/**` round-trip through reconciliation.
**Depends on**: Phase 2 (needs hub-flux cluster up)
**Parallelizable with**: Phase 6 (ADR-003 Flux-over-ArgoCD, ADR-004 hub-only-Flux, `docs/flux-hub-spoke.md` patch-surface documentation can land alongside this phase)
**Risk**: LOW — `flux bootstrap github` is a single documented command; the nuance is the two corrections to starter guidance (the `kustomization.yaml` customization surface is editable; `--path` is effectively immutable and must be hard-coded). Token-leak risk is real but mitigated by gating first commit on Phase 6's gitleaks (see Parallelization notes).
**Requirements**: FLUX-01, FLUX-02, FLUX-03, FLUX-04, FLUX-05
**Success Criteria** (what must be TRUE):
  1. `scripts/bootstrap-flux.sh` runs `flux bootstrap github` against `hub-flux` with `--path` hard-coded to `clusters/hub-flux` (no env override accepted); re-running it after a successful first bootstrap is a no-op and exits `0` (idempotency verified).
  2. `kubectl --context k3d-hub-flux -n flux-system get deploy` shows `source-controller`, `kustomize-controller`, `helm-controller`, `notification-controller` all Ready; `flux --context k3d-hub-flux check` passes.
  3. `GITHUB_OWNER`, `GITHUB_REPO`, `GITHUB_TOKEN` are sourced exclusively from the gitignored `.env`; the script never prints the token value (verifiable by piping to a log and grepping for the literal PAT).
  4. `docs/flux-hub-spoke.md` exists and explicitly states: `gotk-components.yaml` + `gotk-sync.yaml` are bootstrap-managed (do not hand-edit), but `kustomization.yaml` IS the supported patch surface (survives re-bootstrap); `--path` is effectively immutable after first run.
**Plans**: TBD

### Phase 4: Spoke Registration
**Goal**: `kubectl --context k3d-hub-flux -n flux-system get secret spoke-ml-kubeconfig spoke-apps-kubeconfig` returns both Secrets, each with a `value.yaml` key containing a kubeconfig whose `server:` is `https://k3d-<spoke>-server-0:6443`, and the hub's `kustomize-controller` pod can reach each spoke's apiserver with TLS validated and bearer-token auth succeeding.
**Depends on**: Phase 3 (needs `flux-system` namespace on hub to hold the kubeconfig Secrets)
**Parallelizable with**: Phase 6 (ADR-004 hub-only-Flux rationale + `docs/flux-hub-spoke.md` hub-spoke reconciliation section can land alongside)
**Risk**: HIGH — this is the single highest-risk phase in the project. DNS (`k3d-<spoke>-server-0` resolvable on `k8s-net`), TLS (`--tls-san` SAN present), CA-data (base64 PEM embedded correctly), RBAC (cluster-admin CRB), token format (legacy Secret-backed, NOT TokenRequest — `kubectl create token` expires), and Secret key name (`value.yaml`) all converge. Failure mode on Secret-key mismatch is silent: controllers fall back to the hub's in-cluster SA and reconcile into the WRONG cluster while reporting `Ready=True` (P18).
**Requirements**: SPOKE-01, SPOKE-02, SPOKE-03, SPOKE-04, SPOKE-05, SPOKE-06
**Success Criteria** (what must be TRUE):
  1. `scripts/register-spokes-for-flux.sh` creates a `flux-reconciler` ServiceAccount + cluster-admin ClusterRoleBinding + explicit `kubernetes.io/service-account-token` Secret on each spoke; re-running it is a no-op (idempotent).
  2. `kubectl --context k3d-hub-flux -n flux-system get secret <spoke>-kubeconfig -o jsonpath='{.data.value\.yaml}' | base64 -d` yields a valid kubeconfig with `server: https://k3d-<spoke>-server-0:6443`, valid base64 `certificate-authority-data`, and a non-expiring bearer token.
  3. A hand-crafted in-hub-pod probe (`kubectl --context k3d-hub-flux -n flux-system exec deploy/kustomize-controller -- sh -c 'nslookup k3d-spoke-ml-server-0 && curl -ksS --cacert <embedded CA> https://k3d-spoke-ml-server-0:6443/readyz'`) returns `ok` for both spokes.
  4. `clusters/hub-flux/spokes/spoke-ml.yaml` and `spoke-apps.yaml` exist as Flux `Kustomization` resources with `spec.kubeConfig.secretRef.name: <spoke>-kubeconfig`, `spec.kubeConfig.secretRef.key: value.yaml` (explicit), and `spec.path: ./clusters/<spoke>`.
  5. Negative-proof check: the Kustomization's `.status.inventory` contains at least one resource whose namespace/name only exists on the targeted spoke (not on the hub) — proves reconciliation landed on the right cluster, not the hub (guards against P18 silent-misroute).
**Plans**: TBD

### Phase 5: Workloads + Health + Rebuild
**Goal**: `task rebuild` chains destroy → create-clusters → bootstrap-flux → register-spokes → deploy-examples → health-check in under 20 minutes on the target dev box with warm CUDA image cache, ending with `task health-check` green.
**Depends on**: Phases 1, 2, 3, 4 (rebuild exercises the entire stack end-to-end)
**Parallelizable with**: Phase 6 (`docs/rebuild-runbook.md`, `docs/gpu-notes.md` can be authored alongside)
**Risk**: MEDIUM — individual workloads are stock patterns (podinfo, `nvidia-smi` pod); the risk is the SLO (20-min rebuild) being hit only if the CUDA image cache is preserved across destroy (Phase 2 responsibility) AND the `task fix-dns` workaround reliably clears stale CoreDNS NodeHosts. The `DESTROY-05` rebuild chain's success criterion is load-bearing for the core-value requirement.
**Requirements**: DEP-01, DEP-02, DEP-03, DEP-04, HEALTH-01, HEALTH-02, HEALTH-03, HEALTH-04, HEALTH-05, HEALTH-06, HEALTH-07, DESTROY-01, DESTROY-02, DESTROY-03, DESTROY-04, DESTROY-05, DESTROY-06
**Success Criteria** (what must be TRUE):
  1. `task deploy-examples` ensures hub-flux Kustomizations exist such that `kubectl --context k3d-spoke-apps -n podinfo get deploy podinfo` reports `Available=True` and `kubectl --context k3d-spoke-ml -n gpu-smoke logs job/nvidia-smi` contains `NVIDIA-SMI` output naming a CUDA device (manifests live under `examples/podinfo/` and `examples/gpu-smoke-test/`, committed to git).
  2. `task health-check` exits `0` and verifies, in order: all three clusters exist + nodes Ready; Flux controllers Ready and `flux check` passes; every spoke Kustomization `Ready=True`; an in-hub-pod DNS probe resolves `k3d-spoke-ml-server-0` + `k3d-spoke-apps-server-0`; `spoke-ml` reports `nvidia.com/gpu` > 0; each spoke apiserver's serving cert includes its expected SAN (openssl probe).
  3. `task fix-dns` stops and starts `hub-flux` (NOT `K3D_FIX_DNS=1`), refreshes stale CoreDNS NodeHosts, and leaves the cluster green; documented as the 2026-era workaround for k3d#1009 / #1112.
  4. `task destroy` requires explicit typed `yes` confirmation before proceeding, deletes all three clusters + `k8s-net`, preserves `docker builder` cache (custom CUDA image still present in `docker images`), and neither invokes nor transitively calls `docker system prune` or `docker builder prune`.
  5. `task rebuild` — on a machine where the CUDA image cache is warm — completes destroy → create → bootstrap → register → deploy → health-check in under 20 minutes and ends in a green `task health-check` (timed end-to-end on the target dev box; core-value requirement).
**Plans**: TBD

### Phase 6: Repo Hygiene + Docs + ADRs
**Goal**: The repository is safe to publish publicly — no real secrets committed, `.env.example` contract documented, five ADRs under `docs/adr/` capture the locked architectural decisions, README walks a fresh clone from Windows prereqs to running lab, rebuild runbook documents timings + failure modes, GitHub Actions CI runs shellcheck + kubeconform + markdownlint on every push/PR.
**Depends on**: Nothing hard — but DOCS content matures as Phases 1–5 land real artifacts. Items that lock before first commit (see Parallelization notes): REPO-01..04 (gitignore, gitleaks, `.env.example`) MUST land before the first `git push`. ADR-001 / ADR-002 / ADR-005 can be authored during Phases 1–2; ADR-003 / ADR-004 during Phase 3–4; README + rebuild-runbook + CI workflow land near the end.
**Parallelizable with**: Phases 1, 2, 3, 4, 5 (largely — see Parallelization notes). A planner should schedule REPO-01..04 as the first work item in plan execution so secrets cannot leak during Phase 1.
**Risk**: LOW — standard repo hygiene; the single real risk (GITHUB_TOKEN leak on public repo, P10) is mitigated by gitleaks pre-commit BEFORE the first commit.
**Requirements**: REPO-01, REPO-02, REPO-03, REPO-04, REPO-05, REPO-06, REPO-07, DOCS-01, DOCS-02, DOCS-03, DOCS-04, DOCS-05, DOCS-06, DOCS-07, DOCS-08, DOCS-09, DOCS-10
**Success Criteria** (what must be TRUE):
  1. `.gitignore` excludes `.env` + other secret-bearing paths (but does NOT re-ignore `.planning/` — that is intentionally tracked); `.env.example` is committed and documents every required key (`GITHUB_OWNER`, `GITHUB_REPO`, `GITHUB_TOKEN`) with placeholder values and one-line descriptions; a `gitleaks` (or `detect-secrets`) pre-commit hook installs via `scripts/install-tools.sh` and blocks commits containing plausible secrets.
  2. `docs/adr/0001..0005` each exist and correspond to the five locked decisions: single-WSL2 + shared Docker network, k3d-over-Kind, Flux-over-ArgoCD, hub-only Flux control plane, k3s `v1.34.6-k3s1` + CUDA 12.8+ pins. Each ADR names decision, context, consequences.
  3. `README.md` walks a fresh clone through: Windows prereqs → WSL config → Docker install → NVIDIA setup → tools install → cluster creation → Flux bootstrap → spoke registration → example deploy → teardown — in that order; `docs/architecture.md` includes a GitHub-renderable Mermaid hub-spoke diagram; `docs/gpu-notes.md` explains the 3-part k3d GPU contract + RTX 5090 / sm_120 / CUDA 12.8+ floor; `docs/rebuild-runbook.md` is step-by-step with expected timings and common failure modes.
  4. `Taskfile.yml` is the single orchestration surface (all logic in `scripts/`, Taskfile invokes scripts not the reverse); destructive tasks `destroy` and `rebuild` are named explicitly and require confirmation.
  5. `.github/workflows/ci.yml` runs `shellcheck scripts/*.sh`, `kubeconform` on YAML under `clusters/` + `examples/`, and `markdownlint` on `**/*.md` — green on every push and PR; a lint step rejects any `scripts/**` file referencing `docker system prune` or `docker builder prune` (enforces DESTROY-04).
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5. Phase 6 parallelizes with 1–5 during plan execution (see Parallelization notes below) but rolls up its own status independently.

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Host Foundation | 9/9 | Complete | 2026-04-23 |
| 2. Cluster Layer | 0/TBD | Not started | - |
| 3. Flux Hub Bootstrap | 0/TBD | Not started | - |
| 4. Spoke Registration | 0/TBD | Not started | - |
| 5. Workloads + Health + Rebuild | 0/TBD | Not started | - |
| 6. Repo Hygiene + Docs + ADRs | 0/TBD | Not started | - |

## Parallelization Notes

**config.json:** `parallelization=true`, `granularity=standard`, `mode=yolo`, `model_profile=inherit`.

**Hard ordering (cannot parallelize):**
- Phase 1 → Phase 2: cluster creation requires Docker + GPU chain + pinned tools.
- Phase 2 → Phase 3: `flux bootstrap` needs `hub-flux` up.
- Phase 3 → Phase 4: kubeconfig Secrets land in `flux-system` namespace created by bootstrap.
- Phase 4 → Phase 5: Flux cannot reconcile workloads into spokes without `spec.kubeConfig` Secrets.

**Phase 6 parallelization schedule (recommended for plan execution):**
- **Before Phase 1 ends** (first work item in plan execution): REPO-01 + REPO-02 + REPO-03 + REPO-04 (`.gitignore`, `.env.example`, gitleaks pre-commit hook). **Rationale:** these must be installed BEFORE the first `git push`, since public-repo + leaked PAT is unrecoverable (P10). Also: DOCS-06 (ADR-001 single-WSL2 + shared network) — decision already locked.
- **During Phase 2:** DOCS-07 (ADR-002 k3d-over-Kind), DOCS-10 (ADR-005 version pins), DOCS-04 (GPU notes first draft).
- **During Phase 3:** DOCS-08 (ADR-003 Flux-over-ArgoCD), DOCS-03 (hub-spoke patch-surface doc).
- **During Phase 4:** DOCS-09 (ADR-004 hub-only Flux).
- **During Phase 5:** DOCS-01 (README final assembly), DOCS-02 (architecture.md Mermaid diagram), DOCS-05 (rebuild-runbook with measured timings from real `task rebuild` runs), REPO-05 (Taskfile.yml reorganization pass), REPO-06 (destructive-task naming audit), REPO-07 (GitHub Actions CI workflow).

**`task rebuild` cuts across all phases.** DESTROY-05 (the rebuild chain) lives in Phase 5, but its success criterion (under 20 minutes, ending green) depends on every prior phase being green. Flag surfaced in Phase 5 success criterion 5 and in STATE.md blockers if any prior phase regresses.

## Risk Register

| Phase | Risk | Rationale |
|-------|------|-----------|
| 1 | MEDIUM | Host-layer (WSL mirrored-mode, systemd-resolved 127.0.0.53 leak, asdf v0.18 PATH migration, clock drift, Docker-Desktop conflict) — most first-run failures cluster here; recovery is always "fix + rerun preflight". |
| 2 | HIGH | Three-part k3d GPU contract must be right simultaneously (daemon.json + Ubuntu-base image + containerd config.toml.tmpl); `--tls-san` cannot be fixed post-hoc; build cache must survive destroy. |
| 3 | LOW | `flux bootstrap github` is well-documented and idempotent; corrections to starter guidance are documentation, not code. |
| 4 | HIGH | Single highest-risk phase. DNS + TLS + CA + RBAC + Secret-key (`value.yaml`) all converge; Secret-key mismatch fails silently into the wrong cluster (P18). |
| 5 | MEDIUM | Rebuild SLO (< 20 min) only achievable with CUDA cache preserved and `task fix-dns` reliable; individual workloads are stock. |
| 6 | LOW | Standard repo hygiene; main risk (PAT leak) gated by Phase 6's own gitleaks-pre-commit requirement landing BEFORE Phase 1's first commit. |
