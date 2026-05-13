# karyon

## What This Is

A reproducible, source-controlled local Kubernetes lab that rebuilds a three-cluster topology — Flux hub + ML spoke (GPU) + apps spoke — on Windows 11 + WSL2 + k3d. Everything is driven by a Taskfile and idempotent scripts; a fresh clone reaches a working hub-spoke Flux GitOps environment using only documented commands. Audience: the author (and anyone who wants to mirror the setup on similar hardware) for learning, experimenting, and running GPU-capable workloads locally without cloud spend.

## Core Value

`task rebuild` performs a scorched-earth teardown and reaches a healthy hub-spoke Flux lab — with a CUDA-capable spoke — in under 20 minutes, every time.

## Requirements

### Validated

<!-- Shipped and confirmed valuable. -->

- [x] `task create-clusters` idempotently creates hub-flux (6443), spoke-ml (6444 + `--gpus all`), spoke-apps (6445) on `rancher/k3s:v1.34.6-k3s1` *(Validated in Phase 2: Cluster Layer — CLU-01..05)*
- [x] Custom `k3s+CUDA` image (CUDA 12.8+ base) for spoke-ml, cached across `task destroy` runs *(Validated in Phase 2: Cluster Layer — IMG-01..06; cache-preservation primitive in scripts/delete-clusters.sh via D-14; `task destroy` wrapper itself deferred to Phase 5)*
- [x] NVIDIA device plugin DaemonSet deployed to spoke-ml exposing `nvidia.com/gpu` *(Validated in Phase 2: Cluster Layer — IMG-04; pinned to v0.17.4 per D-15 Blackwell override of REQUIREMENTS.md v0.19.0+)*
- [x] `task register-spokes` provisions SA + cluster-admin CRB on each spoke and stores remote kubeconfig Secrets on hub-flux under `value.yaml` with `server: https://k3d-<spoke>-server-0:6443` *(Validated in Phase 4: Spoke Registration — SPOKE-01..04)*
- [x] Hub-only Flux control plane reconciles Kustomizations into spokes via `spec.kubeConfig` without running Flux on the spokes *(Validated in Phase 4: Spoke Registration — SPOKE-05..06; live Flux Ready at post-push revision and cross-cluster falsifiers passed)*
- [x] `task deploy-examples` deploys podinfo to spoke-apps and a GPU `nvidia-smi` smoke test to spoke-ml through hub Flux *(Validated in Phase 5: Workloads + Health + Rebuild — DEP-01..04)*
- [x] `task fix-dns` stops/starts only the hub to clear stale CoreDNS NodeHosts after Docker/WSL restart *(Validated in Phase 5: Workloads + Health + Rebuild — HEALTH-07)*
- [x] `task health-check` verifies clusters, nodes, Flux controllers, spoke Kustomizations, in-hub DNS, GPU capacity, TLS SANs, and workload proofs *(Validated in Phase 5: Workloads + Health + Rebuild — HEALTH-01..06)*
- [x] `task destroy` confirms, removes all three clusters plus `k8s-net`, and preserves the CUDA image/cache by avoiding prune commands *(Validated in Phase 5: Workloads + Health + Rebuild — DESTROY-01..04)*
- [x] `task rebuild` runs destroy → create → bootstrap → register → deploy → health-check and completed in 190 seconds with warm CUDA image cache *(Validated in Phase 5: Workloads + Health + Rebuild — DESTROY-05..06)*
- [x] Five ADRs written under `docs/adr/` for the locked architectural decisions *(Validated in Phase 6: Repo Hygiene + Docs + ADRs — DOCS-06..10; ADR-001 single-WSL2 + shared docker network, ADR-002 k3d-over-Kind, ADR-003 Flux-over-ArgoCD with ApplicationSet trade-off + migration note, ADR-004 hub-only Flux control plane, ADR-005 k3s/CUDA version pin; all Nygard 4-section, Status: Accepted)*
- [x] README covers Windows prereqs, WSL config, Docker install, NVIDIA setup, cluster creation, Flux bootstrap, spoke registration, teardown *(Validated in Phase 6: Repo Hygiene + Docs + ADRs — DOCS-01; 260-line hybrid quickstart + reference in locked DOCS-01 order; cross-links to architecture.md / gpu-notes.md / rebuild-runbook.md / 5 ADRs)*
- [x] Repo is safe to publish publicly: no committed secrets, all sensitive inputs via gitignored `.env` with a committed `.env.example` template, placeholder comments where user substitution is required *(Validated in Phase 6: Repo Hygiene + Docs + ADRs — REPO-01..04; gitleaks 8.30.1 native pre-commit hook + .gitleaks.toml allowlist + .gitignore D-16 + post-push CI gitleaks-scan with fetch-depth: 0; one-shot history scan returned 0 findings across 251 commits)*
- [x] Single WSL2 Ubuntu 24.04 instance hosts all clusters on a shared `k8s-net` Docker network *(Validated in Phase 1+2 — HOST-01/02 + CLU-01..05; ADR-001)*
- [x] Docker Engine installed directly in WSL2 (no Docker Desktop integration) *(Validated in Phase 1 — HOST-03 + PRE-08; ADR-001)*
- [x] NVIDIA container toolkit + Docker nvidia runtime configured for GPU pass-through *(Validated in Phase 1 — HOST-05 + PRE-04 default-runtime check)*
- [x] Tool versions pinned via checked-in `.tool-versions` and installed via asdf *(Validated in Phase 1 — TOOLS-01..03 + asdf v0.18.1 + 8 plugins; later extended in Phase 6 with gitleaks 8.30.1 pin)*
- [x] `task preflight` verifies env, resources, GPU chain, tools, ports, and residual k3d/network state *(Validated in Phase 1 — PRE-01..14; ported from prereqs.sh into scripts/preflight.sh + scripts/lib/preflight-lib.sh)*
- [x] `task bootstrap-flux` runs `flux bootstrap github` on hub-flux idempotently (path = `clusters/hub-flux`) *(Validated in Phase 3 — FLUX-01..05; idempotent via patch-surface marker, env-only PAT handling)*
- [x] Destructive tasks (`destroy`, `rebuild`) require explicit confirmation *(Validated in Phase 5 + audited in Phase 6 — DESTROY-01..06 + REPO-06; typed-yes confirmation in scripts/destroy.sh + scripts/rebuild.sh)*
- [x] All scripts are idempotent, fail fast, preflight their own prerequisites, and produce useful errors *(Validated across Phases 1-5 — preflight delegation in create-clusters/bootstrap-flux/register-spokes/deploy-examples/rebuild; strict-mode bash + `set -euo pipefail` throughout)*
- [x] Documented NAT-mode fallback procedure for WSL2 `networkingMode=mirrored` edge cases with Docker custom networks *(Validated in Phase 1 — docs/wsl-networking.md)*

### Active

<!-- Current scope. Building toward these. -->

## Current Milestone: v0.19 — Capsule Multi-Tenancy POC

**Goal:** Prove [Capsule](https://capsule.clastix.io/) as a Karyon-managed multi-tenancy pattern on a dedicated, isolated POC spoke — without polluting the default v1 topology or `task rebuild` path. Close with an explicit graduation ADR (adopt / defer / reject / another POC).

**Target features:**

- Generic external POC onboarding seam (`KARYON POC MOUNT` sentinel-guarded patch surface) so future POCs onboard consistently
- `spoke-capsule` POC cluster — persistent for the POC, NOT part of default v1 topology, NOT in `task rebuild`
- Hub-only Flux preserved — Capsule HelmRelease + tenant Kustomizations live on hub-flux, reconcile to spoke-capsule via `spec.kubeConfig` (ADR-004 invariant)
- Capsule operator installation via Flux HelmRelease
- Capsule-proxy installation and reachable via kubeconfig
- ≥2 tenants with separate owners and isolated namespaces
- Tenant owner access validation (positive RBAC)
- Negative RBAC tests (owner-A cannot access tenant-B; no escalation to cluster-admin)
- Kube-api access through capsule-proxy (tenant kubeconfig routes via proxy, not direct apiserver)
- Flux tenant reconciliation investigation (multi-tenancy lockdown / SA impersonation / cross-namespace refs)
- Capsule webhook failure / teardown validation
- Graduation ADR closing the milestone

**Carried-forward candidates from v0.18 close (not in v0.19 scope unless explicitly added later):**

- Phase 1-5 shellcheck warning cleanup (SC2034 / SC2155)
- First-push CI verification + GitHub branch-protection setup
- Real secret management (Vault / SOPS / age)
- Stale frontmatter reconciliation pass (VALIDATION.md flags + REQUIREMENTS.md traceability table)

### Out of Scope

<!-- Explicit boundaries. Includes reasoning to prevent re-adding. -->

- Production hardening — lab-only; no HA, no hardened RBAC, no network policies baseline
- Cloud clusters — local-only by design; keeps dependencies and cost predictable
- Real secret management — placeholder structure only (gitignored `.env` + `.env.example`); Vault/SOPS/age deferred to a later milestone
- Full ML workload implementation — GPU smoke-test verifies `nvidia-smi` from inside a pod only; framework workloads are separate work
- NVIDIA GPU Operator — device plugin DaemonSet path first; Operator deferred if/when needed
- ArgoCD — Flux-only; trade-offs captured in ADR-003 with migration note
- One WSL2 distro per cluster — all distros share the host VM; per-distro isolation is illusory (ADR-001)
- Non-Windows hosts — targets Windows 11 + WSL2 only; Linux-native and macOS not supported in v1
- CI/CD pipeline — local dev loop only; GitHub Actions integration deferred
- **(v0.19)** OIDC tenant authentication — token-based for the Capsule POC; OIDC issuer / dex / keycloak deferred to a later milestone
- **(v0.19)** Production ingress / TLS for capsule-proxy — port-forward / NodePort acceptable for POC; real ingress + cert-manager deferred
- **(v0.19)** Generic ephemeral cluster factory — `spoke-capsule` is hand-rolled and persistent for the POC; a parameterized "spawn ephemeral spoke" factory is future work
- **(v0.19)** Multi-spoke tenant federation — POC stays on a single spoke; tenants spanning spoke-apps + spoke-ml + spoke-capsule is out of scope
- **(v0.19)** Capsule installed on hub-flux itself — POC validates spoke-side multi-tenancy first; hub-side Capsule deferred
- **(v0.19)** Default platform adoption of Capsule — Capsule stays outside `task rebuild` until a graduation ADR explicitly adopts it

## Context

**Host target:** Author's development machine — Windows 11, RTX 5090 (Blackwell, sm_120), ample RAM/disk. `.wslconfig` pins 52 GB RAM and 20 CPU to WSL. Preflight floor is tight (40 GB RAM / 16 C / 100 GB free pass; 16 GB RAM / 8 C / 30 GB warn; below → fail). Because the topology is tuned to this machine, "works on my dev box" is explicitly the floor, not a generic minimum.

**Current state (post-v0.18 — shipped 2026-04-29):** The full karyon Lab v1 stack is operational. `task rebuild` chains preflight → destroy → create-clusters → bootstrap-flux → register-spokes → deploy-examples → health-check end-to-end and was validated at **190 seconds** with warm CUDA cache (well under the 20-minute SLO). All 81 v0.18 requirements are satisfied across 6 phases / 41 plans / 90 tasks. Public-repo secrets defense is operational with 0 historical findings across 251 commits and a 5-job GitHub Actions CI workflow (gitleaks fetch-depth: 0, shellcheck, kubeconform, markdownlint, prune-lint-bats) with all third-party actions SHA-pinned. Five ADRs document the locked architectural decisions; README + architecture.md (Mermaid topology) + gpu-notes.md + rebuild-runbook.md + flux-hub-spoke.md cross-link the full reference.

**Prior work (consumed during v0.18):** An existing preflight checker at `prereqs.sh` was ported to `scripts/preflight.sh` + `scripts/lib/preflight-lib.sh` and extended with PRE-04 (default-runtime), PRE-09..14 (env, shim precedence, systemd-resolved, clock skew, cgroup v2, mirrored-mode bridge probe). Both `prereqs.sh` and the original `starter.md` walkthrough were superseded by the new entry-point surface (README + Taskfile) and removed in Phase 6 Plan 05.

**Repo visibility:** Public from day one. This shifts the secrets model: no real tokens, kubeconfigs, or certs may land in git. GITHUB_OWNER / GITHUB_REPO / GITHUB_TOKEN (and any other user-substituted values) live in a gitignored `.env` populated locally; a committed `.env.example` documents the contract. `flux bootstrap github` writes its PAT to an in-cluster Secret only; `flux-system/` manifests are fine to commit but the PAT must not be.

**Pinned versions (research should re-verify currency in 2025):**
- k3s: `rancher/k3s:v1.34.6-k3s1`
- CUDA base: 12.8+ (required for RTX 5090 / sm_120)
- GPU smoke-test image: `nvcr.io/nvidia/cuda:12.8.0-base-ubuntu22.04` — verifies `nvidia-smi` only, no framework workload
- Tool versions: pinned in `.tool-versions` via asdf

**Key behavioral notes discovered up-front:**
- k3d CoreDNS caches Docker NodeHosts entries that can go stale after a Docker or WSL restart; stop/start of the hub cluster refreshes them (→ `task fix-dns`)
- `flux bootstrap` is idempotent but is reconciliation-based — any hand-edit under `clusters/hub-flux/flux-system/` will be reverted by the next reconcile, so that directory is documented as "bootstrap-managed, do not hand-edit"
- asdf shims must take PATH precedence over any system-wide kubectl/helm/k3d already on the dev machine
- WSL2 `networkingMode=mirrored` has historical edge cases with Docker custom networks; NAT-mode fallback must be documented

## Constraints

- **Tech stack:** Windows 11 host, single WSL2 Ubuntu 24.04 distro, Docker Engine native in WSL (no Docker Desktop integration) — ADR-001, ADR-002
- **Cluster runtime:** k3d + k3s, not Kind — reason: official GPU support, lower idle RAM, explicit `--network` control (ADR-002)
- **GitOps:** Flux over ArgoCD — reason: simpler bootstrap + CRD set for lab scope; known trade-off: no clean equivalent of ArgoCD ApplicationSet cluster generators with label-based targeting, so 2–3 spokes authored as explicit Kustomizations (ADR-003)
- **Control plane topology:** Hub-only Flux in v1; hub reconciles to spokes via `spec.kubeConfig` + remote kubeconfig Secrets — no Flux controllers run on spokes (ADR-004)
- **Version pinning:** k3s pinned to `v1.34.6-k3s1`; CUDA base pinned to 12.8+ — both pinning decisions justified in ADR-005
- **Tool installation:** asdf-managed only, with shim precedence over system binaries
- **Performance:** `task rebuild` must complete < 20 minutes with CUDA image cache warm; `task destroy` must NOT prune docker build cache
- **Security:** Repo is public; no real secrets in git; all substitution via gitignored `.env` + committed `.env.example`
- **GPU target:** RTX 5090 (Blackwell, sm_120) — most PyTorch stable releases still need nightlies; smoke-test deliberately scoped to `nvidia-smi` only to avoid coupling the lab to PyTorch nightly availability
- **Process:** Spec before code — PROJECT.md, REQUIREMENTS.md, ROADMAP.md approved before any scripts or manifests are written; each phase ends with a verifiable artifact

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Single WSL2 Ubuntu 24.04 distro for all clusters | All WSL2 distros share one host VM — per-distro isolation is illusory (→ ADR-001) | ✓ Validated in Phase 1 (HOST-01) + ADR-001 |
| Docker Engine installed natively in WSL (not Docker Desktop) | Avoids extra WSL distros consuming shared memory (→ ADR-001) | ✓ Validated in Phase 1 (HOST-03 + PRE-08 fail gate) |
| k3d over Kind | Official GPU support, lower idle RAM, explicit `--network` control (→ ADR-002) | ✓ Validated in Phase 2 (CLU-01..05) + ADR-002 |
| Flux over ArgoCD | Simpler for lab scope; trade-off: no clean ApplicationSet cluster-generator equivalent; acceptable for 2–3 spokes (→ ADR-003) | ✓ Validated in Phase 3 (FLUX-01..05) + ADR-003 |
| Hub-only Flux control plane (v1) | Reduces controller footprint on spokes; hub uses `spec.kubeConfig` + kubeconfig Secrets to reconcile into spokes (→ ADR-004) | ✓ Validated in Phase 4 (SPOKE-04..06) + ADR-004 |
| Pin k3s to `rancher/k3s:v1.34.6-k3s1`; pin CUDA base to 12.8+ | Flux-compatible current line; CUDA 12.8 is floor for RTX 5090 sm_120 (→ ADR-005) | ✓ Validated in Phase 2 (IMG-01..05) + ADR-005 |
| Tool versions via asdf + `.tool-versions` | Reproducible versions; shim precedence avoids collisions with system binaries | ✓ Validated in Phase 1 (TOOLS-01..03 + PRE-10 shim precedence) |
| Public repo with gitignored `.env` + `.env.example` template | Shareable by design; zero real secrets in git; explicit contract for substitution | ✓ Validated in Phase 6 (REPO-01..04; 0 historical findings across 251 commits) |
| GPU smoke-test limited to `nvidia-smi` inside a pod | Avoids coupling lab health to PyTorch nightly availability for sm_120 | ✓ Validated in Phase 5 (DEP-04) |
| Port existing `prereqs.sh` as `scripts/preflight.sh` | Existing script already covers the full checklist; starting from scratch would be wasted effort | ✓ Validated in Phase 1 (PRE-01..14; lib extracted to scripts/lib/preflight-lib.sh) |
| Pin nvidia-device-plugin to v0.17.4 (overrides REQUIREMENTS.md v0.19.0+) | No stable v0.19.x release compatible with RTX 5090 / Blackwell / sm_120 at Phase 2 research time — phase-scoped D-15 override | ✓ Validated in Phase 2 (IMG-04) |
| `scripts/delete-clusters.sh` must never invoke `docker (system\|builder\|image\|volume) prune` | BuildKit CUDA cache must survive teardown so Phase 5 `task rebuild` SLO (< 20 min) is achievable; literal `INTENTIONALLY NOT calling` comment is the Phase 6 DESTROY-04 lint's grep target | ✓ Validated in Phase 2 + 5 (D-14; SLO 190s achieved) |
| Wave 0 bats validation scaffold (Nyquist gate) | Every executor task in Phase 6 Waves 1-3 has a pre-existing automated test command before implementation lands; no "implement and test in same plan" anti-pattern | ✓ Validated in Phase 6 (06-00; 39 tests across 8 files; all green after Waves 1-3) |
| All GitHub Actions pinned to 40-char commit SHAs (D-09) | Tag re-points are a supply-chain risk; SHAs are immutable | ✓ Validated in Phase 6 (REPO-07; 4 actions pinned, post-push CI green locally) |
| Capsule Multi-Tenancy POC graduation = **DEFER** (ADR-008, D-11-14 evidence-bound rubric) | HARD-GATE 1 RED on Phase 8 G-04 cascade (`spec.kubeConfig` redirects HR/OCIRepo to spoke without Flux CRDs); 22/13/0 GREEN/RED/SKIP bats matrix; ≥1 documented workaround (D-11-01 PostBuild patch); Phase 12 capsule-addon-fluxcd Trial would clarify the architectural shape; ADOPT not eligible, REJECT not supported | ✓ Validated in Phase 11 (VAL-01..06; 6/6 plans `passed_with_overrides`; ADR-008 + EKSDOC-01 Reviewed) |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-05-13 — milestone v0.19 (Capsule Multi-Tenancy POC) complete; Phase 12 (v0.19 Close-out Reconciliation) closed `passed` (7/7 plans; 30/30 plan-level must-haves verified; all 7 ROADMAP Success Criteria satisfied). `/gsd-audit-milestone v0.19` re-run returned `status: passed` — 27/27 v0.19 mandatory REQs satisfied (POC-01..04 + CAPCLU-01..04 + EKSDOC-01 + CAP-01..03 + TEN-01..06 = 18 mandatory checkboxes flipped; PROXY-01..03 + VAL-01..06 = 9 already-validated; ADDON-01/02 deferred to v0.20). 5/5 Nyquist VALIDATION ledgers `status: final`. 11-VERIFICATION.md + 11-PHASE-VERIFICATION.md disposition flipped to `passed` via Supersedure 2026-05-11 blocks. v0.19 milestone state: `ready_to_archive` (next: `/gsd-complete-milestone v0.19`). Prior: Phase 11 closed `passed_with_overrides` (6/6 plans; VAL-01..06 verified). ADR-008 outcome = **DEFER** per D-11-14 evidence-bound rubric — HARD-GATE 1 RED on Phase 8 G-04 cascade (chart-rendered Role NotFound; `spec.kubeConfig` architecture redirects HR/OCIRepo to spoke without Flux CRDs), HARD-GATE 2 GREEN, 22/13/0 GREEN/RED/SKIP bats matrix across 35 @tests, ≥1 documented workaround. Phase 12 capsule-addon-fluxcd Trial UNLOCKED via OPTIONAL gate condition (∈ {adopt, defer}); 6 carryover items forwarded to v0.20 / Phase 12 (G-04 architectural decision, Pitfall 11-P1 D-11-01 relocation, pre-existing markdownlint failures, pre-existing gitleaks finding in proxy-06 fixture, slo-regression-live `KARYON_REBUILD_APPROVED` infrastructure, optional `KARYON_PHASE11_STRICT_LIVE=1` re-verification). docs/capsule-on-eks.md rolled forward Status: Draft → Reviewed (D-11-15 4 evidence blocks). Code review: 3 BLOCKER + 8 WARNING + 4 INFO findings — see 11-REVIEW.md (advisory). Prior: Phase 9 closed out `passed_with_overrides` (5/5 plans, 8/8 must-haves). v0.18 (karyon Lab v1) shipped 2026-04-29 — 6 phases, 41 plans, 81/81 requirements.*
