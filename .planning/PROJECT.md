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
- [x] Generic POC onboarding seam (`KARYON POC MOUNT` sentinel-guarded patch surface in `clusters/hub-flux/flux-system/kustomization.yaml`) so future POCs onboard consistently *(Validated in Phase 7 — POC-01..04)*
- [x] Persistent isolated `spoke-capsule` k3d cluster reconciled hub-only by Flux; never enters `task rebuild` until a graduation ADR adopts it (P31 invariant) *(Validated in Phase 7 — CAPCLU-01..04)*
- [x] Self-contained EKS-targeted Capsule rough-cut doc (`docs/capsule-on-eks.md`, Status: Reviewed) — Mermaid topology + IRSA / NLB+ALB / CapsuleConfiguration YAML for team-presentation use *(Validated in Phase 7 + 11 — EKSDOC-01; D-11-15 rolled Status Draft → Reviewed with 4 evidence blocks)*
- [x] Capsule operator (`capsule:0.12.4`) + capsule-proxy installed as two separate Flux HelmReleases reconciled hub-only into spoke-capsule; CRDs visible; proxy reachable from WSL host *(Validated in Phase 8 — CAP-01..03; D-08-12 split-Kustomization architecture — spoke-targeted Ks include `kubeConfig`, hub-targeted Ks exclude it; D-08-11 controller-less self-sign cert flip)*
- [x] Two Tenants (alpha, bravo) with disjoint owners, auto-materialized resource isolation, namespaceOptions quotas, containerRegistries allowlists; hub Flux controllers patched with multi-tenancy lockdown flags; P27 defense (`spec.serviceAccountName: flux-reconciler`) on every tenant Flux Kustomization *(Validated in Phase 9 — TEN-01..06; D-11-07 `forceTenantPrefix: false` repair landed live; Plan 09-03 landed on attempt 3 after two atomic rollbacks)*
- [x] Tenant owner kubeconfigs minted imperatively via TokenRequest + tls.crt embed, routed through capsule-proxy (never apiserver direct), give each owner LIST visibility ONLY into their own tenant's namespaces, and never land in git (P29) *(Validated in Phase 10 — PROXY-01..03; D-08-13 push-gate deferral inherited)*
- [x] Empirical bats evidence proves Capsule's tenant boundary holds (12-test negative-RBAC suite + webhook failure recovery + clean teardown), v0.18 `task rebuild` SLO unchanged, public-repo gitleaks defense (P29 kubeconfig-bearer-token rule + one-shot history scan) clean; closing graduation ADR-008 records adopt/defer/reject/replaced decision backed by bats evidence *(Validated in Phase 11 — VAL-01..06; ADR-008 outcome = **DEFER** per D-11-14 evidence-bound rubric)*
- [x] Custom `tenant-workload-editor` ClusterRole replaces `admin` for human-exercised tenant owners (Flux SA owner pattern preserved with talk-track) *(Validated in Phase 13: RBAC Narrowing — RBAC-01..06; D-13-04 grant matrix with 4 explicit denial categories; D-13-05 per-tenant `human-tenant-owner` SA bound via Tenant CR `spec.owners[]` with explicit `clusterRoles: [tenant-workload-editor]`; existing `gitops-reconciler` Flux SA + admin pattern preserved per RBAC-03 regression gate)*
- [x] `GlobalTenantResource` CR auto-propagates a hello-world workload into every tenant namespace within 60s of namespace creation *(Validated in Phase 13: GlobalTenantResource Seed — SEED-01..03; `capsule.clastix.io/v1beta2 GlobalTenantResource` match-all selector; embedded Pod + Service per D-13-02 with FQCI `docker.io/library/nginx:alpine` per Pitfall 13-P1; `docker.io` additively appended to `containerRegistries.allowed` on alpha + bravo; SEED-02 ≤ 60s falsifier GREEN on fresh tenant)*
- [x] Self-contained delivery path for demo resources (resolved per OQ-4 = GitOps under `pocs/capsule/`; NO Taskfile entry) *(Validated in Phase 13: Delivery Mechanism — DELIVERY-01..03; all new artifacts land via existing `poc-capsule-spoke` + `poc-capsule-spoke-rbac` + `poc-capsule-spoke-tenants` Flux Kustomizations; alpha + bravo Tenant CR diffs additive-only; P31 isolation preserved)*

### Active

<!-- Current scope. Building toward these. -->

- [x] Capsule-proxy two-perspective demo: platform-owner kubeconfig (all-tenants visibility) vs tenant-owner kubeconfig (single-tenant; rejected on `kubectl create secret` and cross-tenant access) *(Validated in Phase 14 — DEMO-01..06; verified live end-to-end 2026-05-29)*
- [x] `docs/poc-capsule-demo.md` polished 6-act demo runbook with pre-demo checklist + known-noise notes *(Validated in Phase 14 — RUNBOOK-01..05; cold-read UAT ≤ 15 min)*

## Current Milestone: v0.20 Capsule POC Demo & RBAC Polish

**Goal:** Take the v0.19 Capsule POC from "shipped + technically correct" to **"demo-ready and least-privilege-aligned"** — land the artifacts + runbook needed to walk a Mixed Eng + Cloud Ops team through a falsifiable **three-tier permission model** end-to-end, with a strict no-admin posture for every human-exercised role.

**Three-tier permission model** (the real-world target this milestone validates — modeling the constraint that the Karyon Platform Team does NOT have cloud-account-level cluster admin):

- **Tier 1 — Cloud Ops / EKS cluster owners** — provisions the EKS cluster itself; holds AWS-side cluster-admin equivalent. Out of scope here (talk-track only).
- **Tier 2 — Karyon Platform Team (platform-owner role)** — does NOT have k8s cluster-admin; CAN add/remove tenants (Tenant CR lifecycle); IS a co-owner on every tenant (visibility + operational access inside every tenant namespace, but bounded).
- **Tier 3 — Tenant Developers (tenant-owner role)** — narrower than k8s `edit`; access ONLY to their own tenant's namespaces.

**Target features:**

- Custom `tenant-workload-editor` ClusterRole replacing `admin` for human tenant owners (narrower than k8s `edit`; no Secret create/edit, no RoleBinding, no ResourceQuota, no LimitRange) — Demo R1
- `GlobalTenantResource` CR auto-propagating a hello-world workload across every tenant namespace (alpha-app1, tenant-alpha, bravo-app1, tenant-bravo, and any new tenant provisioned live) within 60s — Demo R2
- Capsule-proxy two-perspective demo using 2 distinct kubeconfigs (platform-owner sees all; tenant-owner via capsule-proxy on NodePort 30443 sees only their tenant) — Demo R3
- `docs/poc-capsule-demo.md` 6-act walkthrough — architecture → platform-owner role → provision new tenant live → GlobalTenantResource auto-seed → two perspectives → cleanup — Demo R4
- Self-contained delivery path for the new demo resources — GitOps under `pocs/capsule/` OR `task seed-capsule-demo` Taskfile entry (decision in discuss-phase) — Demo R5

**Framing:** Lean milestone. Smallest viable phase count to get a meaningful demo together ASAP. Purely additive — existing alpha/bravo tenants + existing Flux reconciliation stay untouched. Anti-scope guard active: discuss-phase "while we're at it, can we also..." additions get rejected unless directly load-bearing for R1–R5.

**Audience for the resulting demo:** Mixed internal team — Engineering + Cloud Ops mix. ~10–15 minute live walkthrough; goal is to leave them able to articulate the platform-owner vs tenant-owner delegation model and the capsule-proxy LIST-filter mechanic.

**Open questions (resolved in discuss-phase, not at milestone open):**

1. `tls: bad certificate` controller-noise — fix as part of R4, document-only in runbook, or defer entirely? (Recommended default: document-only)
2. `tenant-workload-editor` Secrets policy — read-only (recommended), no-access-at-all (strictest), or upstream-`edit`-equivalent (full read+write, less demo-distinct)
3. Hello-world workload shape — Pod + Service (recommended; lightweight, visual), ConfigMap-only (fastest), or Deployment + Service + ConfigMap (heavier)
4. R5 delivery path — GitOps via `pocs/capsule/` vs `task seed-capsule-demo` direct apply
5. New tenant name for the live-provisioning marquee moment ("charlie", "demo", "team-foo", etc.) + provision-live vs pre-staged delete+recreate dance

**Carry-forward parking lot** (acknowledged, still deferred — NOT scoped into v0.20):

- ~~`capsule-addon-fluxcd` Trial (ADDON-01 / ADDON-02 deferred from v0.19 Phase 12)~~ — **RESOLVED 2026-07-06: PASS (do not adopt)** per ADR-008 addendum. Source-level evaluation: the addon is a same-cluster kubeconfig factory whose output hub Flux can never consume under ADR-004; the P27 pattern already delivers tenant GitOps deploys. Revisit only if ADR-004 reverses.
- G-04 architectural decision / split-Kustomization refactor — Plan 11-07 D-11-01 PostBuild workaround stays. Architecture review is a future-milestone concern.
- Optional `KARYON_PHASE11_STRICT_LIVE=1` re-verification path
- slo-regression-live `KARYON_REBUILD_APPROVED` infrastructure
- Pre-existing markdownlint failures
- Pre-existing gitleaks finding in `proxy-06` fixture
- Phase 1-5 shellcheck warning cleanup (SC2034 / SC2155) (v0.18 close carryover)
- First-push CI verification + GitHub branch-protection setup (v0.18 close carryover)
- Real secret management (Vault / SOPS / age) (v0.18 close carryover)
- Stale frontmatter reconciliation pass (v0.18 close carryover)
- Fix the `tls: bad certificate` capsule-controller chatter at the cert-rotation layer (cert-manager wiring / proper CA distribution) — was OQ-1 `document-only` in v0.20 per Phase 14 D-14-01; cross-linked to ADR-008 (DEFER) and `docs/poc-capsule-demo.md` Known Noise appendix. Revisit at capsule graduation or production EKS cut. (v0.20 close carryover)
- `task demo-capsule` Taskfile wrapper for one-shot demo execution — tempting ergonomics but breaks P31 isolation (would add a `spoke-capsule` mention to the default-path Taskfile, which the v0.19 P31 contract forbids). Revisit at graduation or in a POC-ergonomics milestone. (v0.20 close carryover)
- DELIVERY-02 live `task rebuild` SLO re-attestation — Plan 15-04 retry-#2 elected PATH-B (partial evidence) because of architectural rebuild-vs-worktree conflict (Plan 15-04 Tasks 1-3 GREEN + Phase 14 14-02 inheritance precedent + post-rebuild `task health-check` exit 0 baseline captured; full SLO measurement carry-forward to v0.21). (v0.20 close carryover)
- `task rebuild` vs parallel-executor-worktree pattern architectural reconciliation — spec amendment candidate for v0.21. Either (a) amend `task rebuild` to handle in-worktree branches via a temporary push-to-test-branch + Flux test-revision pin, OR (b) amend the parallel-executor pattern so close-out plans that need `task rebuild` run sequentially on main rather than in worktrees. Surfaced by Plan 15-04 retry-#2. (v0.20 close carryover)
- `KARYON_REBUILD_APPROVED` env-gate value drift — Plan 15-04 docs + plan spec say `=1`, but `scripts/rebuild.sh` line 30 requires literal `=yes`. Single-line fix; alignment direction (script vs docs) to be decided in v0.21 docs hygiene pass. (v0.20 close carryover)
- Repo visibility decision: public (design intent, PROJECT.md "Public from day one") vs private (current live state — unrecorded flip between Phase 9 and Plan 11-07). The 2026-07-06 defect sweep restored the tenant GitOps path under the PRIVATE posture (per-tenant `karyon-git-auth` secretRef + mirror in `register-poc-cluster.sh`), which also works if the repo goes public later. If flipping public: re-run a FULL-history gitleaks scan first. (post-v0.20 quick task)
- Least-privilege git credential for tenant sources — `karyon-git-auth` currently mirrors the repo-write bootstrap PAT into tenant-alpha/bravo namespaces on the hub (operator-only namespaces; P29 unaffected). Upgrade to a read-only fine-grained PAT or deploy key. (post-v0.20 quick task)
- Audit the remaining ~13 D-08-03 `failurePolicy: Ignore` webhook overrides for cold-bootstrap failure modes analogous to the namespaces-hook deadlock (flagged as v0.21 candidate in `.planning/debug/capsule-tenant-ns-claim.md`). **Second live instance found 2026-07-07:** pods recreated during the apiserver-oidc node restart missed the `managed-by` label (assignment.misc webhook = Ignore) → platform-owner `pods -A` via capsule-proxy silently EMPTY until the pods were recreated with the controller up. The audit is no longer hypothetical.
- ~~Keycloak OIDC wiring in front of capsule-proxy~~ — **RESOLVED 2026-07-06 (tenant-ui-oidc quick task): WIRED + live-verified.** Issuer `https://localhost:31443/realms/karyon` (research falsified host.k3d.internal — NXDOMAIN in this lab), apiserver flags via config.yaml retrofit, Headlamp v0.43.0 tenant UI through capsule-proxy, kubelogin terminal flow, headless e2e proof (`e2e-oidc-test.sh`). Runbook: `docs/tenant-access.md`. Residuals below.
- OIDC hardening follow-ups — replace the temporary bootstrap admin (`keycloak-initial-admin`) with a permanent master-realm admin; import the karyon OIDC CA into Windows Trusted Root (manual, documented); kube-proxy nftables would break the localhost-NodePort issuer path (guard check in `apiserver-oidc.sh`); imperative OIDC layer (CA file, k3s config.yaml, forwarder, secrets) must be re-run after `k3d cluster delete` (documented in `tenant-access.md` §0). (tenant-ui-oidc quick task)
- Per-tenant code-server + oauth2-proxy web IDE — pattern fully documented in `docs/tenant-access.md` §6 (per-tenant instances mandatory; oauth2-proxy is CNCF Sandbox); Headlamp's built-in pod shell covers quick-exec today. Implement when a tenant actually needs a browser IDE. (tenant-ui-oidc quick task)
- Keycloak realm lifecycle beyond import-once — KeycloakRealmImport never updates an existing realm; decide day-2 posture (admin-UI-as-source-of-truth vs delete/recreate vs admin-API scripting). (keycloak-idp-poc quick task)
- `scripts/preflight.sh` POC-04 strict port check vs POC coexistence — `check_port_strict 30443` fails whenever the spoke-capsule serverlb is up (its docker-proxy legitimately binds the port; the check can't tell it from a squatter), which blocks `task deploy-examples`/full preflight while the POC runs. Fix is design-sensitive: P31's static lint forbids naming spoke-capsule in v0.18 scripts, so the allowance must be generic (e.g. pass when the listener is a docker-proxy), and preflight's mock bats suites (preflight-pre*) need matching updates. Found 2026-07-06 while restoring the gpu-smoke health baseline. (keycloak-idp-poc quick task)

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

**Current state (post-v0.19 — shipped 2026-05-18):** The full karyon Lab v1 stack remains operational at the 190-second `task rebuild` SLO (v0.18 baseline preserved across v0.19 — VAL-04 SLO regression gate green). v0.19 added a generic, sentinel-guarded POC onboarding seam (`KARYON POC MOUNT`) plus a persistent isolated `spoke-capsule` k3d cluster reconciled hub-only by Flux, demonstrating multi-tenancy via Capsule operator + capsule-proxy + 2 tenants (alpha, bravo) with disjoint owners, RBAC isolation (12-test negative suite GREEN), and tenant kubeconfigs routed through capsule-proxy (never apiserver direct). Graduation ADR-008 records the **DEFER** decision (HARD-GATE 1 RED on Phase 8 G-04 cascade; ≥1 documented workaround via Plan 11-07 D-11-01 PostBuild patch + namespace seed). `spoke-capsule` stays outside `task rebuild` per P31. All 108 requirements across both milestones satisfied (81 v0.18 + 27 v0.19 mandatory; ADDON-01/02 deferred to a future milestone). 6 ADRs (ADR-001..005 from v0.18 + ADR-008 from v0.19); EKS-target reference doc `docs/capsule-on-eks.md` rolled Status: Draft → Reviewed for team-presentation use. Public-repo secrets defense extended in v0.19: kubeconfig-bearer-token gitleaks rule + 4 tenant-kubeconfig .gitignore globs; post-push history scan + Phase 11 VAL-05 verifier both clean.

**Prior state (post-v0.18 — shipped 2026-04-29):** karyon Lab v1 reached `task rebuild` at 190s with warm CUDA cache; 81/81 v0.18 requirements across 6 phases / 41 plans / 90 tasks; public-repo secrets defense with 0 historical findings across 251 commits; 5-job GitHub Actions CI workflow with SHA-pinned third-party actions.

**Prior work (consumed during v0.18):** An existing preflight checker at `prereqs.sh` was ported to `scripts/preflight.sh` + `scripts/lib/preflight-lib.sh` and extended with PRE-04 (default-runtime), PRE-09..14 (env, shim precedence, systemd-resolved, clock skew, cgroup v2, mirrored-mode bridge probe). Both `prereqs.sh` and the original `starter.md` walkthrough were superseded by the new entry-point surface (README + Taskfile) and removed in Phase 6 Plan 05.

**Repo visibility:** Public from day one *(design intent)*. This shifts the secrets model: no real tokens, kubeconfigs, or certs may land in git. GITHUB_OWNER / GITHUB_REPO / GITHUB_TOKEN (and any other user-substituted values) live in a gitignored `.env` populated locally; a committed `.env.example` documents the contract. `flux bootstrap github` writes its PAT to an in-cluster Secret only; `flux-system/` manifests are fine to commit but the PAT must not be.
> **Drift note (2026-07-06):** the repo is LIVE-PRIVATE — flipped as an unrecorded operator action between Phase 9 authoring and Plan 11-07 (`gh repo view`: `isPrivate: true`). All public-safe hygiene above remains in force. The per-tenant GitOps sources were repaired to work under either posture (`karyon-git-auth` secretRef); the public-vs-private decision is in the carry-forward parking lot.

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
*Last updated: 2026-05-29 after v0.20 milestone — Capsule POC Demo & RBAC Polish SHIPPED (3 phases, 14 plans, 27 tasks; 23/23 mandatory REQs satisfied). Delivered a demoable three-tier multi-tenancy POC where the platform team runs the full tenant lifecycle without cluster-admin; `docs/poc-capsule-demo.md` 6-act runbook verified live end-to-end. Audit: passed with 1 operator-accepted tech_debt (DELIVERY-02 live `task rebuild` SLO re-attestation → v0.21 carry-forward). Post-ship: namespaces-webhook `failurePolicy: Ignore→Fail` regression found + fixed (`.planning/debug/capsule-tenant-ns-claim.md`); `docs/capsule-portable-setup-guide.md` written for replicating the demo elsewhere. Archives under `.planning/milestones/v0.20-*`. Prior: v0.19 (Capsule Multi-Tenancy POC) shipped 2026-05-18 (6 phases, 34 plans, 76 tasks; ADR-008 = **DEFER** per D-11-14); v0.18 (karyon Lab v1) shipped 2026-04-29 (6 phases, 41 plans, 81/81 requirements). Next: `/gsd-new-milestone` for v0.21.*
