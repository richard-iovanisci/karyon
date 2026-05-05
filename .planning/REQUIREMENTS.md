# Requirements: karyon — Milestone v0.19 (Capsule Multi-Tenancy POC)

**Goal:** Prove [Capsule](https://capsule.clastix.io/) as a Karyon-managed multi-tenancy pattern on a dedicated, isolated POC spoke (`spoke-capsule`) — without polluting the default v1 topology or `task rebuild` path. Close with an explicit graduation ADR (adopt / defer / reject / another POC).

**Phase numbering:** v0.18 ended at Phase 6. v0.19 starts at **Phase 7** and ships in **6 phases (5 mandatory + 1 optional gated)**.

**Inheritance from v0.18:**

- All v0.18 ADR invariants preserved — most importantly **ADR-004 (hub-only Flux)**: no Flux controllers run on `spoke-capsule`.
- All v0.18 validated requirements remain VALIDATED — `task rebuild` SLO < 230 s and the public-repo secrets contract are explicit regression gates here.
- v0.18 P18 invariant carries forward: every `spec.kubeConfig.secretRef` block uses `key: value.yaml`.

**Load-bearing v0.19 invariants (every plan must respect):**

- **P27 — every tenant Flux Kustomization MUST set `spec.serviceAccountName` explicitly.** Flux's `--default-service-account` lockdown flag does NOT apply when `spec.kubeConfig` is set; without explicit `serviceAccountName` tenants run as cluster-admin and bypass Capsule entirely.
- **P29 — tenant kubeconfigs MUST NOT land in git.** New gitignore globs + `.gitleaks.toml` rule for `kind: Config` + bearer-token shape required.
- **P31 — `spoke-capsule` MUST NOT enter `task rebuild` until graduation ADR adopts Capsule.** All POC concerns under `scripts/poc/capsule/` namespace; static bats greps `scripts/` (excluding `scripts/poc/`) for `spoke-capsule` and asserts ZERO mentions.
- **KARYON POC MOUNT location:** sentinel inserted into `clusters/hub-flux/flux-system/kustomization.yaml` (the FLUX PATCH SURFACE, parallel to existing `# KARYON SPOKES MOUNT`). NOT `clusters/hub-flux/kustomization.yaml`.

---

## v0.19 Requirements

### Foundation: POC Seam + spoke-capsule Cluster + EKS Capsule Doc (Phase 7)

Single foundational phase that lands the generic POC mount surface, the persistent isolated POC k3d cluster, and the EKS-targeted Capsule rough-cut doc the milestone owner can share with their team while later phases land. Designed so Capsule install (Phase 8) is the very next phase.

**POC Onboarding Seam (generic — reusable for future POCs):**

- [ ] **POC-01** — User can mount POC Kustomizations on hub-flux through a sentinel-guarded patch surface (`# KARYON POC MOUNT` in `clusters/hub-flux/flux-system/kustomization.yaml`) without modifying bootstrap-managed files
- [ ] **POC-02** — User can register an external POC cluster to hub-flux via `scripts/register-poc-cluster.sh <cluster-name>` (mirrors v0.18 `register-spokes-for-flux.sh` pattern; never invoked by `task rebuild`)
- [ ] **POC-03** — Tenant kubeconfigs / bearer tokens are blocked from committing to the public repo by extended `.gitignore` globs + a new `.gitleaks.toml` rule that matches `kind: Config` + bearer-token shape (verified by synthetic-fixture bats)
- [ ] **POC-04** — `task preflight` reserves the capsule-proxy NodePort (30443) and fails fast if the port is in use elsewhere on the host

**spoke-capsule Cluster + Outer Reconcile:**

- [ ] **CAPCLU-01** — User can create a persistent `spoke-capsule` k3d cluster on the shared `k8s-net` network (apiserver port 6446, NodePort 30443 published, `--tls-san k3d-spoke-capsule-server-0`) via `scripts/poc/capsule/create-cluster.sh`
- [ ] **CAPCLU-02** — Hub-flux reconciles into spoke-capsule via an outer Kustomization at `clusters/hub-flux/pocs/capsule.yaml` with `spec.kubeConfig.secretRef.name: spoke-capsule-kubeconfig` and `key: value.yaml` (P18 inheritance) — silent-misroute falsifier (P18 negative test) passes
- [ ] **CAPCLU-03** — User can recover stale CoreDNS NodeHosts on spoke-capsule alone via `task fix-dns-poc-capsule` after Docker / WSL restart, without affecting the v0.18 default `task fix-dns`
- [ ] **CAPCLU-04** — Documented host-restart procedure (`docs/poc-capsule.md`) explains how to bring spoke-capsule back after Docker / WSL restart

**EKS-targeted Capsule rough-cut doc (team-presentation artifact — generated EARLY in this phase):**

- [ ] **EKSDOC-01** — `docs/capsule-on-eks.md` exists at the start of Phase 7 work and is a self-contained rough-cut sufficient to walk a team through the proposal. Required sections: (a) **What Capsule is** in one paragraph; (b) **Required CRDs** (the 7 from research: Tenant, CapsuleConfiguration, GlobalTenantResource, TenantResource, ResourcePool, ResourcePoolClaim, TenantOwner); (c) **Required permissions / RBAC** for the operator + capsule-proxy SAs and the per-tenant SAs; (d) **Rough EKS install path** translating the karyon k3d POC to EKS (IRSA for tenant SAs instead of legacy SA tokens; LoadBalancer Service or ALB Ingress for capsule-proxy instead of NodePort; ECR-hosted OCI Helm repo or upstream OCI; VPC CNI vs k8s-net Docker bridge; cluster-autoscaler / Karpenter interaction with tenant nodeSelectors); (e) **What this POC does NOT prove** (HA Capsule, OIDC, multi-spoke federation — explicit `What we did not prove` framing inherited from ADR-008's structure). Doc may be marked `Status: Draft` until Phase 11 graduation but MUST exist by end of Phase 7

### Capsule + capsule-proxy Bare-Minimum Install (Phase 8)

Simple, fast Capsule install. Two upstream HelmReleases reconciled by hub-flux into spoke-capsule. Capsule operator alive + proxy reachable + CRDs visible — that is the Phase 8 success bar. Lockdown patches and tenant Kustomizations defer to Phase 9 where they're actually needed.

- [ ] **CAP-01** — Capsule operator (Helm chart `capsule:0.12.4`, OCI `ghcr.io/projectcapsule/charts/capsule`) installed via Flux HelmRelease on hub-flux, reconciling to spoke-capsule via `spec.kubeConfig` — HelmRelease `Ready=True` and `capsule-controller-manager` pod Running on spoke
- [ ] **CAP-02** — capsule-proxy (Helm chart `capsule-proxy:0.12.0`, separate HelmRelease, NOT umbrella) installed with `service.type: NodePort + service.nodePort: 30443` and `additionalSANs: [127.0.0.1, localhost]` — reachable via `curl -k https://127.0.0.1:30443/healthz` returning 200
- [ ] **CAP-03** — Capsule CRDs (`Tenant`, `CapsuleConfiguration`, `GlobalTenantResource`, `TenantResource`, `ResourcePool`, `ResourcePoolClaim`, `TenantOwner`) installed and visible on spoke-capsule (`kubectl get crds | grep capsule.clastix.io` returns ≥7 entries)

### Tenants + Flux Multi-Tenancy Lockdown (Phase 9)

Two tenants with disjoint owners on isolated namespaces. Hub Flux controllers patched with multi-tenancy lockdown flags. Tenant inner Kustomizations carry the load-bearing P27 defense (`spec.serviceAccountName`).

- [ ] **TEN-01** — Two `Tenant` custom resources (`alpha`, `bravo`) exist with disjoint `owners` arrays (each kind ServiceAccount, registered as `<tenant-ns>:gitops-reconciler`); namespace prefix enforcement enabled (`forceTenantPrefix: true`)
- [ ] **TEN-02** — Tenant owner can self-serve a namespace inside their tenant prefix (`kubectl --as=alpha create namespace alpha-app1` succeeds) and the namespace gets the `capsule.clastix.io/tenant=alpha` label automatically
- [ ] **TEN-03** — ResourceQuota and LimitRange objects are auto-materialized inside each tenant namespace (`kubectl get resourcequota -n alpha-app1` shows `capsule-alpha-*` objects without manual creation)
- [ ] **TEN-04** — Tenant inner Flux Kustomizations on hub-flux (under `pocs/capsule/tenants/<name>/`) declare `spec.serviceAccountName: gitops-reconciler` explicitly (P27 defense). Static bats grep-asserts every tenant Kustomization has a non-null `serviceAccountName`
- [ ] **TEN-05** — Hub Flux controllers patched with multi-tenancy lockdown flags (`--no-cross-namespace-refs=true`, `--no-remote-bases=true`, `--default-service-account=default`) and `flux-system` Kustomization sets explicit `spec.serviceAccountName: kustomize-controller` (platform-admin escape hatch); v0.18 `task health-check` regression gate passes after the patch
- [ ] **TEN-06** — Tenants Kustomization declares `dependsOn` chain on the operator Kustomization with `wait: true` (P32 — Tenant CR apply blocks until CRDs exist)

### Tenant Owner Kubeconfigs + Capsule-Proxy Round-trip (Phase 10)

Imperative kubeconfig minting for tenant owners. The kubeconfigs MUST point at the proxy, MUST be excluded from git, and MUST give each owner LIST visibility ONLY into their own tenant's namespaces.

- [x] **PROXY-01** — `scripts/poc/capsule/issue-tenant-kubeconfig.sh <tenant> <owner>` mints a tenant kubeconfig with `server: https://127.0.0.1:30443` (capsule-proxy NodePort), prints to stdout by default, optional `--write-to <path>` for a tmpdir-rooted destination (default `${TMPDIR:-/tmp}/karyon-tenants/`)
- [x] **PROXY-02** — Using the issued kubeconfig, `kubectl get namespaces` returns ONLY namespaces owned by the tenant (proxy LIST filtering working). Direct apiserver access (`https://...:6446`) with the same token returns 403 Forbidden + 'cannot list resource "namespaces"' (Pitfall 10-P3 corrected falsifier — the SA's RBAC is namespace-scoped, NOT a wider list comparison; proves filtering happens at proxy)
- [x] **PROXY-03** — Documented kubeconfig delivery contract in `docs/poc-capsule.md` covers: stdout default; optional `--write-to`; mandatory tmpdir-not-repo location; gitleaks rule catches accidental commits (synthetic-fixture bats)

### Validation + Graduation ADR (Phase 11)

Negative RBAC suite, webhook failure recovery, clean teardown, regression gate against the v0.18 SLO, and the closing graduation ADR.

- [ ] **VAL-01** — Negative RBAC bats suite (N1–N12 falsifiers) all PASS: cross-tenant pod read denied (N1), cluster-wide LIST filtered to own tenant (N2), cross-tenant secret read denied (N3), ClusterRoleBinding escalation denied (N4), namespace prefix violation denied (N5), tenant quota violation denied (N6), denied registry pull denied (N7), direct-apiserver bypass on `:6446` denied or limited (N8), cross-tenant `sourceRef` in tenant Kustomization denied (N9), missing `spec.serviceAccountName` on tenant Kustomization denied / falls through to no-permission default (N10), workload create rejected when capsule-controller is down (N11), workload create succeeds again after operator recovers (N12)
- [ ] **VAL-02** — Capsule webhook failure mode is observed and recoverable: `task fail-capsule-webhook` (test-only) scales operator to 0 → tenant pod create rejected; scales operator → 1 → workload create succeeds. Both halves are bats-asserted
- [ ] **VAL-03** — Clean teardown: `task destroy-poc capsule` performs ordered teardown (suspend tenant Kustomizations → delete Tenant CRs → wait for namespace cascade → optional `k3d cluster delete spoke-capsule`) and leaves the `# KARYON POC MOUNT` sentinel + `clusters/hub-flux/pocs/` mount in place. Post-teardown, no `capsule.clastix.io/tenant=<name>` labeled objects remain
- [ ] **VAL-04** — `task rebuild` SLO regression test PASSES: total time < 230 s; spoke-capsule's container ID is unchanged across rebuild (cluster survives); zero `spoke-capsule` mentions in `scripts/{create-clusters,register-spokes-for-flux,health-check,destroy,delete-clusters,rebuild}.sh`
- [ ] **VAL-05** — One-shot history gitleaks scan post-Phase-10 first push returns 0 findings — proves no tenant kubeconfig leaked
- [ ] **VAL-06** — Graduation ADR-008 written with `Status: Accepted` and one of {adopt, defer, reject, replaced by ADR-N — another POC}, sectioned per Nygard 4-section template, with explicit "What we proved / What we did not prove / Trade-offs" sub-sections backed by bats references. ADR-008 also rolls forward `docs/capsule-on-eks.md` (EKSDOC-01) from `Status: Draft` to `Status: Reviewed` with any corrections informed by the bats evidence

### capsule-addon-fluxcd Trial (Phase 12 — OPTIONAL)

Final optional phase. Trials the upstream `capsule-addon-fluxcd v0.2.3` for tenant SA + kubeconfig automation as a comparison against the hand-managed Phase 9/10 approach. **Gated on Phases 7–11 all green AND ADR-008 outcome ∈ {adopt, defer}.** If ADR-008 is reject / replaced, this phase is skipped.

- [ ] **ADDON-01** — `capsule-addon-fluxcd:0.2.3` HelmRelease deployed to spoke-capsule via hub-flux. Compatibility with Capsule v0.12.4 confirmed by smoke test (tenant SA created automatically; tenant kubeconfig Secret materialized in tenant namespace)
- [ ] **ADDON-02** — Comparison documented in ADR-008 supplement (or a follow-up `docs/poc-capsule-addon.md`): hand-managed vs addon-managed — token rotation, kubeconfig refresh, complexity, blast radius. Decision recorded for v0.20+ adoption

---

## Future Requirements

Deferred to later milestones (kept here so they don't get lost):

### Inherited from v0.18 close

- [ ] Phase 1-5 shellcheck warning cleanup (SC2034 / SC2155 in destroy/rebuild/deploy-examples/fix-coredns/delete-clusters scripts) — would let CI shellcheck severity drop from `error` back to `warning`
- [ ] First-push CI verification + GitHub branch-protection setup (deferred from v0.18 06-07)
- [ ] Real secret management (Vault / SOPS / age) — was explicitly out of scope for v0.18
- [ ] Stale frontmatter reconciliation pass (3 phases' VALIDATION.md flags + 3 Phase 6 SUMMARY `requirements-completed` + REQUIREMENTS.md traceability table)

### Surfaced by v0.19 research

- [ ] OIDC issuer (Dex / Keycloak / Auth0) for tenant auth — POC uses ServiceAccount tokens
- [ ] Production ingress + cert-manager + real TLS for capsule-proxy — POC uses NodePort + self-signed
- [ ] Generic ephemeral cluster factory — `spoke-capsule` is hand-rolled and persistent for the POC; parameterized "spawn ephemeral spoke" factory is future work
- [ ] Multi-spoke tenant federation — Capsule has no native cross-cluster Tenant; deferred until use case emerges
- [ ] Capsule installed on hub-flux itself — POC validates spoke-side first; hub-side Capsule deferred
- [ ] Less-privileged reconciler SA on spokes (replacing v0.18 cluster-admin token Pattern 3) — canonical clastix flux2-capsule pattern, deferred to keep v0.18 invariants intact
- [ ] HA Capsule (multi-replica + leader election) — POC runs single-replica
- [ ] Tenant `spec.preventDeletion: true` validation — only exercised if a v0.19 differentiator pulls it forward
- [ ] EKS implementation of the v0.19 POC — `docs/capsule-on-eks.md` is rough-cut design only; actual EKS deploy + IRSA wiring + ALB ingress + ECR-hosted charts is its own milestone

---

## Out of Scope

Explicit boundaries with reasoning to prevent re-adding:

- **Default platform adoption of Capsule** — Capsule MUST stay outside `task rebuild` until graduation ADR-008 explicitly adopts it. This is the entire point of structuring v0.19 as a POC milestone.
- **OIDC / Dex / Keycloak / oauth2-proxy for tenant auth** — POC scoped to ServiceAccount + bearer tokens. Adding OIDC triples the moving parts without informing the adopt/defer/reject decision.
- **Production ingress + cert-manager + real TLS for capsule-proxy** — NodePort + self-signed (with optional `insecure-skip-tls-verify`) is the explicit POC trade-off. Real ingress drags in cert-manager + DNS + ingress-nginx.
- **Generic ephemeral cluster factory** — Designing a parameterized "spawn ephemeral spoke" pattern is a separate concern. v0.19 hand-rolls `spoke-capsule` via a dedicated script.
- **Multi-spoke tenant federation** — Capsule has no native cross-cluster Tenant. Tenants spanning spoke-apps + spoke-ml + spoke-capsule is a research project, not a POC validation.
- **Capsule installed on hub-flux** — POC validates spoke-side multi-tenancy first; hub-side install is a different threat model (control-plane self-tenancy) and a separate ADR.
- **`ResourcePool` + `ResourcePoolClaim`** — separate Capsule CRD model orthogonal to baseline tenant isolation. POC validates the Tenant CRD only.
- **Gateway API tenancy** — requires Gateway API CRDs + an implementation; massive scope expansion that doesn't inform the graduation ADR.
- **`runtimeClasses: [gvisor, kata]` enforcement** — k3d/k3s on WSL2 doesn't ship those runtimes; would be a no-op test.
- **Full Pod Security Admission + admission-policy stack (OPA Gatekeeper / Kyverno)** — Capsule already covers tenant-scoped policy; adding PSA / Gatekeeper / Kyverno on top is out of scope for the POC.
- **Real network-policy baseline + actual packet-drop verification** — separate domain. NetworkPolicy auto-injection by Capsule is in scope (declarative); actually verifying packet drops with real CNI policy plugins is not.
- **"Capsule replaces all RBAC"** — Capsule layers on top of Kubernetes RBAC. The POC does not adopt the framing that Capsule is sufficient by itself.
- **HA Capsule (multi-replica + leader election)** — POC runs single-replica; HA semantics are explicitly "what we did not prove" in ADR-008.
- **NVIDIA device plugin on spoke-capsule** — GPU access is on spoke-ml, not spoke-capsule. POC does not validate GPU + Capsule interaction.
- **Capsule on Kind / minikube / k3s-on-bare-metal** — POC validates k3d only; other runtimes remain unverified.
- **`task rebuild` integration of `spoke-capsule`** — explicit invariant: spoke-capsule MUST NOT enter the default rebuild chain until graduation ADR-008 says "adopt." VAL-04 enforces this with a static bats grep.
- **Actual EKS deploy of Capsule** — `docs/capsule-on-eks.md` (EKSDOC-01) is a rough-cut design doc only, generated for team-presentation use. Building a real EKS cluster + IRSA + ALB + ECR + Capsule deploy is its own milestone (would inherit from v0.19 evidence but is NOT v0.19 scope).

---

## Traceability

Validated by `/gsd-new-milestone` roadmapper (2026-04-29); each REQ-ID is mapped to exactly one phase (no orphans, no duplicates). `Plan(s)` column will be filled by `/gsd-plan-phase` as each phase is decomposed. Phase 12 is gated on Phase 11 ADR-008 outcome ∈ {adopt, defer}.

| REQ-ID | Phase | Plan(s) |
|--------|-------|---------|
| POC-01 | Phase 7 | 07-00, 07-02 |
| POC-02 | Phase 7 | 07-00, 07-03 |
| POC-03 | Phase 7 | 07-00, 07-04 |
| POC-04 | Phase 7 | 07-00, 07-04 |
| CAPCLU-01 | Phase 7 | 07-00, 07-03 |
| CAPCLU-02 | Phase 7 | 07-00, 07-02, 07-03 |
| CAPCLU-03 | Phase 7 | 07-00, 07-05 |
| CAPCLU-04 | Phase 7 | 07-00, 07-05 |
| EKSDOC-01 | Phase 7 | 07-00, 07-01 |
| CAP-01 | Phase 8 | TBD |
| CAP-02 | Phase 8 | TBD |
| CAP-03 | Phase 8 | TBD |
| TEN-01 | Phase 9 | TBD |
| TEN-02 | Phase 9 | TBD |
| TEN-03 | Phase 9 | TBD |
| TEN-04 | Phase 9 | TBD |
| TEN-05 | Phase 9 | TBD |
| TEN-06 | Phase 9 | TBD |
| PROXY-01 | Phase 10 | 10-00, 10-01, 10-02 |
| PROXY-02 | Phase 10 | 10-00, 10-02 |
| PROXY-03 | Phase 10 | 10-00, 10-01, 10-02 |
| VAL-01 | Phase 11 | TBD |
| VAL-02 | Phase 11 | TBD |
| VAL-03 | Phase 11 | TBD |
| VAL-04 | Phase 11 | TBD |
| VAL-05 | Phase 11 | TBD |
| VAL-06 | Phase 11 | TBD |
| ADDON-01 | Phase 12 (optional) | TBD |
| ADDON-02 | Phase 12 (optional) | TBD |

**Total:** 29 requirements across 6 phases (5 mandatory + 1 optional gated phase).

---

*Last updated: 2026-04-29 — v0.19 milestone requirements drafted from research synthesis (.planning/research/SUMMARY.md), restructured per user feedback to squash POC seam + cluster into Phase 7 and add EKSDOC-01 for team-presentation. Roadmap pass 2026-04-29: 29/29 REQ-IDs mapped, success criteria derived per phase, ROADMAP.md and STATE.md written.*
