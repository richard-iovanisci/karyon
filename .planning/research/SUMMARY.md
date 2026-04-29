# Project Research Summary — v0.19 Capsule Multi-Tenancy POC

**Project:** karyon
**Milestone:** v0.19 — Capsule Multi-Tenancy POC (additive to validated v0.18 Lab v1)
**Domain:** Multi-tenancy operator (Capsule) + RBAC reverse proxy (capsule-proxy) + Flux 2 multi-tenancy lockdown on a dedicated, isolated POC k3d spoke (`spoke-capsule`), reconciled hub-only by the existing v0.18 Flux control plane.
**Researched:** 2026-04-29
**Confidence:** HIGH on stack pins (all 3 chart versions verified against upstream GitHub release API the day of writing); HIGH on architecture (existing v0.18 invariants read directly from committed files; clastix/flux2-capsule-multi-tenancy reference matches verbatim); HIGH on table-stakes feature surface; HIGH on critical pitfalls. MEDIUM on capsule-addon-fluxcd v0.2.3 ↔ Capsule v0.12.4 specific compatibility (date proximity strongly implies it; not declared by README — Phase 9 should re-verify before adopting the addon).

---

## Executive Summary

The v0.19 milestone is an **isolated POC**, not a default-platform extension. Its single deliverable is a graduation ADR (adopt / defer / reject / another POC) backed by empirical bats evidence. Everything in the milestone exists to inform that decision while preserving the v0.18 SLO (`task rebuild` < 230 s, was 190 s) and the ADR-004 hub-only-Flux invariant.

The mental model is two cooperating components on a fourth k3d cluster (`spoke-capsule`, port 6446, on the shared `k8s-net` bridge): the **Capsule operator** layers a `Tenant` CRD over a flat namespace plane and installs ~9 admission webhooks that reject tenant boundary violations at admission time; **capsule-proxy** sits in front of the apiserver on a NodePort and filters cluster-scoped LIST/WATCH responses (namespaces, nodes, ingressclasses, storageclasses, pv) so each tenant sees only their own resources. The hub's existing kustomize-controller reconciles all of this via the same `spec.kubeConfig.secretRef.name + key: value.yaml` pattern that v0.18 already proved against `spoke-apps` and `spoke-ml`.

Three things make this POC genuinely new (not a copy of v0.18 spoke wiring): (1) a **second sentinel-guarded mount seam** (`# KARYON POC MOUNT`) added to the FLUX PATCH SURFACE alongside the existing `# KARYON SPOKES MOUNT`, allowing future POCs to onboard cleanly; (2) an **inner reconciliation hop** where per-tenant Flux Kustomizations live in tenant home namespaces with both `spec.kubeConfig` (routed through capsule-proxy) AND `spec.serviceAccountName` (impersonating a per-tenant SA registered as a Capsule Tenant Owner); (3) **multi-tenancy lockdown patches** to hub Flux controllers (`--no-cross-namespace-refs`, `--no-remote-bases`, `--default-service-account`). The risk profile is dominated by two load-bearing security pitfalls (P27 silent tenant escape via missing `spec.serviceAccountName`; P29 tenant kubeconfigs leaking to a public repo) plus one architectural correction the prompt's planning needed (the KARYON sentinels live in `clusters/hub-flux/flux-system/kustomization.yaml`, NOT `clusters/hub-flux/kustomization.yaml`).

---

## Mental Model

### One Paragraph

Capsule's `Tenant` CRD (cluster-scoped, `capsule.clastix.io/v1beta2`) declares **(a) who owns it** — one or more `owners` of `kind: User | Group | ServiceAccount`; **(b) what they can create** — a label-stamped set of `namespaces` (each gets `capsule.clastix.io/tenant: <name>`) capped by `namespaceOptions.quota` and optionally prefix-enforced via `forceTenantPrefix: true`; and **(c) the policy box around them** — `resourceQuotas` aggregated across all tenant namespaces, `limitRanges` auto-materialized into each tenant namespace, allow-lists for storage classes / ingress classes / hostnames / image registries / nodeSelectors, and `additionalRoleBindings`. The Capsule controller reconciles these into real `ResourceQuota`/`LimitRange`/`RoleBinding`/`NetworkPolicy` objects inside each tenant namespace, and 9 admission webhooks block tenant attempts to step outside the box at admission time. capsule-proxy fills the one gap RBAC cannot: it filters cluster-scoped LIST responses so a tenant running `kubectl get namespaces` only sees their own. Tenant kubeconfigs **always** point at the proxy (`https://...:30443` NodePort), never the apiserver direct (`:6446`). For Flux multi-tenancy, the hub's controllers run with `--default-service-account=default` + `--no-cross-namespace-refs=true` + `--no-remote-bases=true` lockdown flags; tenant Kustomizations declare an explicit `spec.serviceAccountName` (a per-tenant SA registered as a Tenant Owner) that Flux impersonates against capsule-proxy, end-to-end constraining the reconcile to what Capsule allows.

### ASCII Diagram

```
                  ┌───────────────────────────────────────────────────────────┐
                  │   Single WSL2 Ubuntu 24.04 — Docker network: k8s-net      │
                  │                                                            │
                  │  ┌────────────────────────────────────────────────────┐    │
                  │  │  k3d-hub-flux  (apiserver :6443) — FLUX HUB ONLY   │    │
                  │  │  flux-system controllers + lockdown flag patches:  │    │
                  │  │    --no-cross-namespace-refs=true                  │    │
                  │  │    --no-remote-bases=true                          │    │
                  │  │    --default-service-account=default               │    │
                  │  │                                                    │    │
                  │  │  Hub Kustomizations (all in flux-system):          │    │
                  │  │    spoke-apps  → spec.kubeConfig (existing)        │────┼──→ k3d-spoke-apps  (:6445)
                  │  │    spoke-ml    → spec.kubeConfig (existing)        │────┼──→ k3d-spoke-ml    (:6444 + GPU)
                  │  │                                                    │    │
                  │  │    poc-capsule (NEW; OUTER reconcile)              │────┼──┐
                  │  │      → spec.kubeConfig: spoke-capsule-kubeconfig   │    │  │
                  │  │                                                    │    │  │
                  │  │  Tenant inner Kustomizations (NEW; in tenant ns    │────┼──┤
                  │  │    on spoke-capsule, picked up by hub controller): │    │  │
                  │  │    tenant-alpha-app:  kubeConfig=proxy-kubeconfig  │    │  │
                  │  │                       serviceAccountName=          │    │  │
                  │  │                          gitops-reconciler         │    │  │
                  │  │    tenant-bravo-app:  (mirror of alpha)            │    │  │
                  │  └────────────────────────────────────────────────────┘    │  │
                  │                                                            │  │
                  │  ┌────────────────────────────────────────────────────┐    │  │
                  │  │  k3d-spoke-capsule  (:6446 + NodePort :30443)      │←───┼──┘
                  │  │  Persistent for the POC; NOT in `task rebuild`     │    │
                  │  │                                                    │    │
                  │  │  capsule-system/                                   │    │
                  │  │    capsule-controller-manager   (HelmRelease)      │    │
                  │  │      9 webhooks: /tenants /namespaces /pods        │    │
                  │  │      /services /pvc /ingresses /networkpolicies    │    │
                  │  │      /nodes /cordoning   (failurePolicy: Ignore)   │    │
                  │  │    capsule-proxy                (HelmRelease)      │    │
                  │  │      Service NodePort :30443 (k3d host-publish)    │    │
                  │  │      Filters LIST: namespaces, nodes, ingressclass,│    │
                  │  │      storageclasses, pv, priorityclasses,          │    │
                  │  │      runtimeclasses                                │    │
                  │  │    CapsuleConfiguration "default"                  │    │
                  │  │                                                    │    │
                  │  │  Tenants (capsule.clastix.io/v1beta2):             │    │
                  │  │    Tenant alpha → owners[ServiceAccount:           │    │
                  │  │                   tenant-alpha:gitops-reconciler]  │    │
                  │  │    Tenant bravo → owners[ServiceAccount:           │    │
                  │  │                   tenant-bravo:gitops-reconciler]  │    │
                  │  │                                                    │    │
                  │  │  Capsule-managed namespaces:                       │    │
                  │  │    alpha-app1 (label: tenant=alpha; auto-injected  │    │
                  │  │      ResourceQuota + LimitRange + RoleBindings)    │    │
                  │  │    bravo-app1 (mirror)                             │    │
                  │  └────────────────────────────────────────────────────┘    │
                  │                                                            │
                  │  Tenant-owner kubeconfigs (out-of-band, NEVER in git):     │
                  │    /tmp/karyon-tenants/alice.kubeconfig                    │
                  │      server: https://127.0.0.1:30443  (capsule-proxy)      │
                  │    /tmp/karyon-tenants/bob.kubeconfig                      │
                  └───────────────────────────────────────────────────────────┘
```

**Key invariants encoded above (each is a falsifiable bats observable):**

- ADR-004 preserved: **no Flux on spoke-capsule.** Hub-only.
- Tenant kubeconfigs **always** point at `:30443` (proxy NodePort), never `:6446` (apiserver direct).
- Namespaces are bound to a tenant by **label**, not membership — Capsule's controller stamps `capsule.clastix.io/tenant: <name>` on creation.
- Tenant Kustomizations are constrained at **three independent layers**: network/auth (via proxy), identity (via impersonation), authorization (via webhooks).

---

## Canonical Pin Set

| Component | Pin | Source |
|-----------|-----|--------|
| Capsule operator (Helm chart) | **0.12.4** | `oci://ghcr.io/projectcapsule/charts/capsule:0.12.4` |
| capsule-proxy (Helm chart) | **0.12.0** | `oci://ghcr.io/projectcapsule/charts/capsule-proxy:0.12.0` |
| capsule-addon-fluxcd (Helm chart, optional, Phase B) | **0.2.3** | `oci://ghcr.io/projectcapsule/charts/capsule-addon-fluxcd:0.2.3` |
| `hack/create-user.sh` (vendored under `scripts/poc/capsule/`) | tag **`v0.12.4`** | `https://raw.githubusercontent.com/projectcapsule/capsule/v0.12.4/hack/create-user.sh` |
| k3s (already pinned) | **v1.34.6-k3s1** | ADR-005 — Capsule v0.12.x requires k8s ≥ 1.34.0; current pin has 6 patches of margin |
| Flux (already pinned) | **v2.8.6** | v0.18 STACK — supports the three lockdown flags natively |

**No new asdf entries. No new system packages.** All v0.18 tool pins (`kubectl`, `helm`, `k3d`, `flux`) carry forward unchanged.

**Two pin-related decisions worth flagging:**

1. **Install Capsule and capsule-proxy as two separate `HelmRelease` objects, not the umbrella chart with `proxy.enabled=true`.** The umbrella chart (`charts/capsule/Chart.yaml` at v0.12.4) pins its `capsule-proxy` sub-dependency at **0.10.0** — two minors stale. Splitting into two HelmReleases is the supported way to track both lines independently.
2. **k8s ≥ 1.34.0 is the floor for both Capsule v0.12.x and capsule-proxy v0.12.0.** Karyon's `rancher/k3s:v1.34.6-k3s1` (ADR-005) clears this with 6 patches of margin. If k3s is ever bumped to 1.35+, Capsule must be re-verified.

---

## Recommended Phase Split (with rationale for choosing it over alternatives)

**The three research files proposed three different splits.** Reconciling them:

| Source | Phase count | Phases (paraphrased) |
|--------|-------------|---------------------|
| FEATURES.md | **4 phases** | (1) POC seam + spoke-capsule, (2) Capsule + proxy install, (3) Tenants + RBAC + proxy kubeconfigs, (4) Flux tenant reconciliation + webhook failure + teardown + ADR |
| ARCHITECTURE.md | **6 phases** | (1) POC seam + cluster + registration, (2) Capsule + proxy + Flux lockdown, (3) Two tenants, (4) Negative RBAC validation, (5) Webhook failure + teardown, (6) Graduation ADR |
| PITFALLS.md | **6 phases** | (7) POC Onboarding Seam, (8) spoke-capsule cluster, (9) Capsule + proxy install, (10) Tenants + lockdown, (11) Tenant kubeconfig + proxy access, (12) Validation + ADR |

### Selected Split: **6 Phases** (PITFALLS.md / ARCHITECTURE.md aligned, numbered 7–12 to continue from v0.18)

**Rationale for choosing 6 over 4:**

1. **Phase 1 of FEATURES.md (POC seam + cluster) bundles two distinct testability surfaces.** The KARYON POC MOUNT sentinel work is *static* (yq + grep + bats); the cluster + registration is *live* (k3d + kubectl + the P18 silent-misroute falsifier). Bundling them means the static gate can't go green until the live work is done — bad Wave 0 ordering.
2. **Phase 4 of FEATURES.md is a kitchen sink** — bundles Flux tenant reconciliation, negative RBAC, webhook failure, AND graduation ADR. Each is independently failable; bundling risks slip on the ADR (P41).
3. **PITFALLS.md and ARCHITECTURE.md agreed independently on a 6-phase split** with the same internal ordering, despite different agents. Strong signal.
4. **Capsule install (Phase 9) deserves its own phase** because of the cert-source decision (P34) and the CRD ordering trap (P32 — the Tenants Kustomization must `dependsOn` the operator Kustomization with `wait: true`).
5. **Tenants (Phase 10) and Tenant kubeconfigs (Phase 11) are split because the kubeconfig generator is the public-repo leak surface** (P29) — cleanest scope is to land all tenant control objects declaratively first, then add the imperative kubeconfig-minting helper as a separate phase with its own gitignore-expansion and gitleaks-rule story.

### Phase 7 — POC Onboarding Seam

**Rationale:** Foundational — *no place to install Capsule until the seam exists, and the seam is a generic asset for future POCs (Crossplane, Linkerd, vcluster), not Capsule-specific.* Designing it inside-out from Capsule shape risks coupling.

**Delivers:**
- `# KARYON POC MOUNT` sentinel inserted into `clusters/hub-flux/flux-system/kustomization.yaml` (the FLUX PATCH SURFACE — see "Load-Bearing Architectural Correction" below).
- `clusters/hub-flux/pocs/kustomization.yaml` aggregating sibling POC Kustomizations.
- `scripts/register-poc-cluster.sh` (sibling of `register-spokes-for-flux.sh`).
- `.gitignore` expansion (D-16+1) for tenant kubeconfig globs + `.gitleaks.toml` rule for `kind: Config` + bearer-token shape.
- `task preflight` extension to reserve port 30443.
- Wave 0 bats: sentinel uniqueness, file shapes, `task rebuild` MUST NOT mention `spoke-capsule`.

**Addresses pitfalls:** P29 (kubeconfig leak), P30 (sentinel collision), P31 (POC isolation from rebuild), P39 (port 30443 reservation).

### Phase 8 — spoke-capsule Cluster + OUTER Reconcile

**Rationale:** *No Capsule install target until the cluster is up and the hub's outer-reconcile path proves the P18 silent-misroute defense.*

**Delivers:**
- `k3d-spoke-capsule` cluster on `k8s-net`, apiserver port 6446, NodePort 30443 published, `--tls-san=k3d-spoke-capsule-server-0@server:*`.
- `flux-reconciler` SA + cluster-admin CRB + legacy SA-token Secret on spoke-capsule (mirrors v0.18 Pattern 3).
- `spoke-capsule-kubeconfig` Secret applied imperatively to `flux-system` on hub-flux.
- `clusters/hub-flux/pocs/capsule.yaml` — OUTER hub-side Kustomization with `spec.kubeConfig.secretRef.name: spoke-capsule-kubeconfig` + `key: value.yaml`.
- `task fix-dns-poc-capsule` (does NOT compose into default `task fix-dns`).
- bats: P18 falsifier per spoke-capsule.

**Addresses pitfalls:** P28 (NodePort host-publish), P31 (dedicated `scripts/poc/capsule/`), P35 (per-cluster CoreDNS recovery), P40 (P18 invariant — `key: value.yaml`).

### Phase 9 — Capsule + capsule-proxy Install + Flux Lockdown Patches

**Rationale:** *No tenants creatable until Capsule + proxy are running. Lockdown patches must land in the same phase to avoid a brittle interim where one is on and the other isn't.*

**Delivers:**
- `pocs/capsule/operator/` — `OCIRepository` + `HelmRelease` for `capsule:0.12.4`, with `failurePolicy: Ignore` override on webhooks (P26), `tls.enableController: true` (built-in certgen, no cert-manager dep — P34).
- `pocs/capsule/proxy/` — `OCIRepository` + `HelmRelease` for `capsule-proxy:0.12.0`, with `service.type: NodePort + service.nodePort: 30443` (P28) and `additionalSANs: [127.0.0.1, localhost]` (P33).
- `pocs/capsule/config/` — `CapsuleConfiguration/default` (forceTenantPrefix=true, allowServiceAccountPromotion=true).
- **Hub-side multi-tenancy lockdown patch** in `clusters/hub-flux/flux-system/kustomization.yaml`: `--no-cross-namespace-refs=true`, `--no-remote-bases=true`, `--default-service-account=default`. Plus `flux-system` Kustomization sets explicit `spec.serviceAccountName: kustomize-controller`.
- `dependsOn` chain: tenants Kustomization waits for operator Kustomization with `wait: true` (P32 CRD ordering).
- bats: capsule-system pods Ready; proxy NodePort reachable; HelmRelease pin matches docs.

**Addresses pitfalls:** P26, P28, P32, P33, P34, P38.

### Phase 10 — Two Tenants + Tenant Flux Inner Reconcile

**Rationale:** *First answerable graduation question — does Capsule + Flux actually contain a misbehaving tenant Kustomization? Cannot be answered without tenants.*

**Delivers:**
- `pocs/capsule/tenants/alpha/` and `tenants/bravo/`: tenant home namespace, `gitops-reconciler` SA, self-impersonation Role+RoleBinding, `Tenant` CR with `owners[ServiceAccount: <ns>:gitops-reconciler]`, GitRepository, **inner Kustomization** with `spec.serviceAccountName: gitops-reconciler` + `spec.kubeConfig: <tenant>-proxy-kubeconfig` (the load-bearing P27 defense).
- `pocs/capsule/tenants/alpha-workload/` + `bravo-workload/`: trivial Deployments under tenant namespaces (`alpha-app1`, `bravo-app1`).
- Per-tenant proxy kubeconfig Secrets applied imperatively (NOT committed).
- Static bats: every tenant Kustomization grep-asserts `spec.serviceAccountName != null`.
- Live bats: positive RBAC; negative RBAC seed test.

**Addresses pitfalls:** P27 (load-bearing — every tenant Kustomization MUST set `spec.serviceAccountName`), P40, P43.

### Phase 11 — Tenant Owner Kubeconfigs + capsule-proxy Round-trip

**Rationale:** *The "tenant kubeconfig routes via proxy" requirement is the single most important POC outcome and the public-repo leak surface — clean scope is to handle imperative kubeconfig minting + delivery contract in its own phase.*

**Delivers:**
- `scripts/poc/capsule/create-user.sh` (vendored from upstream tag `v0.12.4`).
- `scripts/poc/capsule/issue-tenant-kubeconfig.sh capsule alpha` — reads SA token, builds kubeconfig with `server: https://127.0.0.1:30443`, prints to stdout (default).
- Documented contract: tenant kubeconfigs default to `${TMPDIR:-/tmp}/karyon-tenants/<name>.kubeconfig` (outside repo); `tenants/.env.example` documents the `KARYON_TENANT_KUBECONFIG_DIR` convention.
- Live bats: `kubectl --kubeconfig=alice get namespaces` returns ONLY alpha-* namespaces; bypass attempt on `:6446` directly returns Forbidden or wider list.
- Synthetic-fixture gitleaks bats.

**Addresses pitfalls:** P29, P33, P39, P42.

### Phase 12 — Validation + Graduation ADR-008

**Rationale:** *Graduation cannot be informed without teardown evidence and webhook-failure observation. Compresses these into a single phase to reduce slip risk on the ADR.*

**Delivers:**
- Negative-RBAC bats suite (N1–N12 from FEATURES.md): cross-tenant pod read denied, cluster-wide LIST filtered, secret read denied, ClusterRoleBinding escalation denied, prefix violation denied, quota violation denied, registry violation denied, direct apiserver bypass denied, cross-tenant sourceRef denied, missing serviceAccountName denied, webhook-down recovery observed.
- Webhook failure probe: `task fail-capsule-webhook` (test-only) scales operator to 0, asserts namespace rejection; scales back, asserts recovery.
- Teardown probe: `task destroy-poc capsule` ordered teardown (suspend → delete Tenants → wait for cascade → optionally `k3d cluster delete`); leaves `# KARYON POC MOUNT` and `../pocs` mount in place.
- `task rebuild` SLO regression test: < 230 s with spoke-capsule alive AND torn down; spoke-capsule's container ID unchanged across rebuild.
- One-shot history gitleaks scan post-Phase-11 first push.
- **ADR-008** (Capsule graduation): Status: Accepted (one of {adopt, defer, reject, replaced by ADR-N}).

**Addresses pitfalls:** P26, P27, P31, P36, P37, P41.

### Phase Ordering Rationale (Compressed)

```
Phase 7 ── precedes ──→ Phase 8   (no place to install Capsule until pocs/capsule/ is reconciled)
Phase 8 ── precedes ──→ Phase 9   (no Tenant CRD until operator + proxy run)
Phase 9 ── precedes ──→ Phase 10  (no tenants creatable until Capsule + lockdown patches are live)
Phase 10 ── precedes ──→ Phase 11 (no tenant kubeconfig to mint until tenants exist)
Phase 11 ── precedes ──→ Phase 12 (graduation cannot be informed without proxy round-trip + teardown)
```

### Research Flags

Phases likely needing `/gsd-research-phase` during planning:

- **Phase 9 (Capsule install):** MEDIUM-confidence area — `failurePolicy: Ignore` + `matchConditions` interaction with `objectSelector` defaults; built-in certgen lifecycle on chart upgrade vs cert-manager. **Plus:** capsule-addon-fluxcd v0.2.3 vs Capsule v0.12.4 specific compatibility (MEDIUM — verify via smoke test if addon brought into scope).
- **Phase 10 (Tenants + lockdown):** HIGH-risk single requirement (TS-10) because flag patches touch the v0.18 Flux bootstrap surface. Mitigation: rerun full v0.18 `task health-check` as regression gate.
- **Phase 12 (Validation + ADR):** designs the multi-probe negative bats (P37 SAR cache flake) and teardown ordering (P36 stranded PVCs).

Phases with standard patterns (skip research-phase):

- **Phase 7:** sentinel + gitignore + script-isolation patterns are direct lifts from v0.18 Phase 4 D-02.
- **Phase 8:** k3d cluster create + SA + kubeconfig Secret + outer Kustomization is a verbatim mirror of v0.18 spoke registration.
- **Phase 11:** the `proxy-kubeconfig-generator` flow is documented at clastix/flux2-capsule-multi-tenancy.

---

## Load-Bearing Pitfalls

### P27 — Tenant Escape via Flux (CRITICAL — load-bearing security invariant)

**Threat:** Flux's `--default-service-account=default` lockdown flag **does NOT apply when `spec.kubeConfig` is set**. (Verified against Flux Kustomization v1 spec — the flag is for local-cluster reconcile only; cross-cluster reconcile gets *no* automatic safety net.) The hub's `flux-reconciler` SA on each spoke is `cluster-admin`. Therefore, any tenant Flux Kustomization on the hub that **omits `spec.serviceAccountName`** runs as `cluster-admin` on spoke-capsule and bypasses Capsule entirely — Capsule's webhooks deliberately exempt cluster-admin / kube-system identities. **This is a Capsule-bypass equivalent to having no multi-tenancy at all.**

**Mandatory defense (every plan that creates a tenant Kustomization MUST do this):**

1. Every tenant Flux Kustomization on the hub sets `spec.serviceAccountName: gitops-reconciler` (or per-tenant SA name) explicitly. The SA must exist on spoke-capsule in the namespace matching the Kustomization's namespace.
2. Static bats assertion (Phase 10 acceptance criterion):
   ```bash
   for f in pocs/capsule/tenants/*/kustomization-app.yaml; do
     yq '.spec.serviceAccountName' "$f" | grep -qv null
   done
   ```
3. Live negative-RBAC test (Phase 12) applies a tenant Kustomization without `spec.serviceAccountName` and asserts either Flux refuses to apply OR the impersonation falls through to a no-permission default SA.
4. Document this in ADR-007 / docs/poc-capsule.md as the load-bearing security invariant — the v0.19 analogue of v0.18's P18 `spec.kubeConfig` invariant.

### P29 — Tenant Kubeconfig Leak to Public Repo (CRITICAL — recovery cost HIGHEST)

**Threat:** v0.18's `.gitignore` covers `kubeconfig*` and `*.kubeconfig` — but only those filename globs. A tenant kubeconfig stored as `tenants/tenant-a/admin.yaml` does NOT match. gitleaks's default ruleset has no kubeconfig-shaped pattern.

**Mandatory defense:**

1. Phase 7 expands `.gitignore` (D-16+1) for tenant directory globs.
2. Phase 7 adds explicit `.gitleaks.toml` rule matching `kind: Config` + `users:` + bearer-token regex (multi-line).
3. Phase 11 kubeconfig generator script defaults to `${TMPDIR:-/tmp}/karyon-tenants/<name>.kubeconfig` (outside repo) AND prints to stdout by default.
4. Phase 12 synthetic-fixture bats verifies the new gitleaks rule catches a mock kubeconfig.
5. Phase 12 one-shot history gitleaks scan after first push.

### P31 — POC Pollution of `task rebuild` (CRITICAL — invariant violation)

**Threat:** Adding `spoke-capsule` to any of `scripts/{create-clusters,register-spokes-for-flux,health-check,destroy,delete-clusters,rebuild}.sh` would (a) break PROJECT.md boundary, (b) regress 190 s SLO by +60–120 s, (c) prematurely "graduate" Capsule.

**Mandatory defense (Phase 7 acceptance criterion):**

1. All POC concerns under `scripts/poc/capsule/` (dedicated namespace).
2. Static bats greps every script in `scripts/` (excluding `scripts/poc/`) for `spoke-capsule` and asserts ZERO mentions.
3. Phase 12 live regression test: `task rebuild` with spoke-capsule alive must leave the spoke-capsule container ID unchanged AND complete in < 230 s.

### Load-Bearing Architectural Correction — KARYON POC MOUNT Location

**The prompt's planning notes referenced `clusters/hub-flux/kustomization.yaml` for the new sentinel. This is incorrect.**

Verified by reading the file directly: the existing `# KARYON SPOKES MOUNT` sentinel and the FLUX PATCH SURFACE comment block both live in **`clusters/hub-flux/flux-system/kustomization.yaml`** — the file inside the `flux-system/` subdirectory. That file documents itself in lines 1–13 as the supported patch surface that survives `flux bootstrap` re-runs. Peer files in `flux-system/` (`gotk-components.yaml`, `gotk-sync.yaml`) are bootstrap-managed and WILL be overwritten.

**The new `# KARYON POC MOUNT` sentinel MUST be inserted into the same file** (`clusters/hub-flux/flux-system/kustomization.yaml`), parallel to the existing SPOKES sentinel. Putting it in `clusters/hub-flux/kustomization.yaml` would not survive `flux bootstrap` re-runs.

Final shape after Phase 7:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - gotk-components.yaml
  - gotk-sync.yaml
  # KARYON SPOKES MOUNT
  - ../spokes
  # KARYON POC MOUNT
  - ../pocs
```

### Other High-Severity Pitfalls (defenses summarized)

- **P26 webhook failurePolicy:** `failurePolicy: Ignore` on Capsule webhooks for the POC + `dependsOn: [capsule-operator]` on tenant Kustomization with `wait: true`.
- **P28 capsule-proxy ClusterIP unreachable from WSL host:** `service.type: NodePort + service.nodePort: 30443` + `k3d cluster create --port "30443:30443@loadbalancer"`.
- **P32 CRDs not present when Tenants apply:** two Flux Kustomizations on the hub with `dependsOn` chain + `wait: true`.
- **P33 capsule-proxy TLS cert SANs missing 127.0.0.1:** Helm values inject `additionalSANs: [127.0.0.1, localhost]`; fallback `insecure-skip-tls-verify: true` in tenant kubeconfig is acceptable POC simplification.
- **P38 Capsule v0.12 ↔ k3s v1.34.6 pin:** Capsule HelmRelease pinned to `0.12.4`; CI kubeconform validates against k8s 1.34 schema.
- **P40 `value.yaml` Secret key inheritance from v0.18 P18:** every `spec.kubeConfig.secretRef` block in `pocs/capsule/**` uses `key: value.yaml`; bats grep-asserts.

---

## Table-Stakes Features (REQ-ID Seeds)

These twelve table-stakes features (TS-01..TS-12 from FEATURES.md) become the requirement seed — each MUST validate during the POC or graduation cannot be "adopt."

| TS-ID | Requirement seed | Phase | Observable success signal |
|-------|------------------|-------|---------------------------|
| TS-01 | `spoke-capsule` k3d cluster created and persistent (NOT in `task rebuild`) | 8 | `k3d cluster list` shows spoke-capsule; `task rebuild` does not touch it; container ID unchanged |
| TS-02 | Capsule operator installed via Flux HelmRelease on hub-flux, reconciling to spoke-capsule | 9 | HelmRelease `Ready=True` on hub; capsule-controller-manager pod Running on spoke |
| TS-03 | capsule-proxy installed and reachable from WSL host | 9 | `curl -k https://127.0.0.1:30443/healthz` returns 200 |
| TS-04 | Two `Tenant` CRs (alpha, bravo) with distinct owners | 10 | `kubectl get tenants` returns both; owners arrays disjoint |
| TS-05 | Tenant owner can self-serve namespaces inside tenant | 10 | `kubectl create namespace alpha-prod --as=alice ...` succeeds; namespace label `capsule.clastix.io/tenant=alpha` stamped |
| TS-06 | ResourceQuota and LimitRange auto-materialized in tenant namespace | 10 | `kubectl get resourcequota -n alpha-prod` shows `capsule-alpha-*` object |
| TS-07 | Positive RBAC: tenant owner can do legitimate ops in own namespace | 10 | `kubectl auth can-i create pods -n alpha-prod --as=alice` returns `yes` |
| TS-08 | Negative RBAC: cross-tenant access denied | 10/12 | N1–N4 from negative-RBAC table return `Forbidden` |
| TS-09 | Tenant kubeconfig routes through capsule-proxy (NOT direct apiserver) | 11 | Tenant kubeconfig `server:` is `:30443`; `kubectl get namespaces` returns ONLY tenant's |
| TS-10 | Flux tenant-scoped Kustomization reconciles as tenant SA (load-bearing — see P27) | 10 | Tenant Kustomization with `serviceAccountName: gitops-reconciler` reaches Ready=True; cross-tenant sourceRef reaches Ready=False |
| TS-11 | Capsule webhook failure observed and recoverable | 12 | Scale operator to 0 → tenant pod create rejected; scale to 1 → succeeds |
| TS-12 | `kubectl delete tenant <name>` clean teardown | 12 | Post-delete, no namespaces or resources with `capsule.clastix.io/tenant=<name>` label remain |

---

## Anti-Features (Out-of-Scope Seeds)

These ten items (from FEATURES.md, aligned with PROJECT.md v0.19 Out-of-Scope) become the explicit Out of Scope seed in REQUIREMENTS.md:

1. **OIDC issuer (Dex / Keycloak) for tenant auth** — POC uses ServiceAccount tokens.
2. **Production ingress + cert-manager + real TLS for capsule-proxy** — POC uses NodePort + self-signed + optional `insecure-skip-tls-verify`.
3. **Capsule installed on hub-flux itself** — POC validates spoke-side multi-tenancy first.
4. **Multi-spoke tenant federation** — Capsule has no native cross-cluster Tenant.
5. **`ResourcePool` + `ResourcePoolClaim`** — separate CRD model, orthogonal to baseline tenant isolation.
6. **Gateway API tenancy** — requires Gateway API CRDs + implementation; massive scope expansion.
7. **`runtimeClasses: [gvisor, kata]` enforcement** — k3d/k3s on WSL2 doesn't ship those runtimes.
8. **Full Pod Security Admission + admission-policy stack (OPA Gatekeeper / Kyverno)** — Capsule already covers tenant-scoped policy.
9. **Real network-policy baseline + actual packet-drop verification** — separate domain.
10. **"Capsule replaces all RBAC"** — Capsule layers on top of Kubernetes RBAC.

**Plus the v0.19 PROJECT.md explicit deferrals:** generic ephemeral cluster factory; default platform adoption of Capsule (`task rebuild` integration); cert-manager / dex / keycloak / oauth2-proxy / Vault / SOPS / age; HA Capsule (replicas: 2); NVIDIA device plugin on spoke-capsule.

---

## Graduation ADR Criteria (ADR-008)

**The milestone closes when ADR-008 is written with `Status: Accepted` and one of these four outcomes**, backed by empirical bats evidence captured during Phases 10–12:

| Outcome | Trigger evidence | Action taken in v0.20+ |
|---------|------------------|------------------------|
| **Accepted (adopt)** | All 12 TS-* PASS; all N1–N12 negative-RBAC PASS; webhook failure recovers cleanly; teardown leaves no orphans; rebuild SLO unchanged | v0.20 incorporates Capsule into default `task rebuild`; spoke-capsule promoted from POC to v1 spoke |
| **Accepted (defer)** | All 12 TS-* PASS but trade-offs (long-lived tokens, NodePort + skip-TLS, no OIDC) blocking next adoption use-case | v0.20 picks next experiment; spoke-capsule stays under `pocs/` until trade-offs are addressed |
| **Accepted (reject)** | One or more TS-* FAIL; OR critical pitfall manifests in production-flavored use; OR Capsule's mental model proves too leaky | v0.20 picks different multi-tenancy path (HNC, vcluster); spoke-capsule torn down |
| **Accepted (replaced by ADR-N — another POC)** | Mid-POC discovery that different approach more aligned with karyon learning goals | v0.20 opens new POC milestone |

**Required ADR-008 sections** (Nygard 4-section, inheriting v0.18 ADR template):

- **Status:** Accepted (one of the four)
- **Context:** What was the POC? Why was Capsule the candidate?
- **Decision:** The chosen outcome
- **Consequences (split into "What we proved" / "What we did not prove" / "Trade-offs")**:
  - **What we proved:** Each TS-* with bats reference; each falsifier observed
  - **What we did not prove:** Each anti-feature explicitly enumerated — prevents future readers from inferring claims the POC didn't make
  - **Trade-offs:** Long-lived legacy tokens (P42); built-in certgen vs cert-manager (P34); NodePort + skip-TLS-verify (P33); capsule-addon-fluxcd not used in POC; failurePolicy: Ignore on webhooks (P26); single-spoke vs multi-spoke

---

## Open Questions by Phase

### Phase 7 (POC Onboarding Seam)
- (P30) Should the new sentinel be `# KARYON POC MOUNT` (singular, generic) or `# KARYON POC MOUNT — capsule` (per-POC)? **Recommended:** singular for v0.19 (one POC at a time); reserve suffix-disambiguation as a Phase 7 ADR-006 trade-off note for future v0.20+ POCs.
- (P39) Is port `30443` definitely free across all v0.18 host-port mappings? Phase 7 preflight extension must positively confirm.

### Phase 8 (spoke-capsule cluster)
- (STACK §ServiceType) Confirm exact k3d port-publish flag: `--port "30443:30443@server:0"` (STACK suggestion) vs `--port "30443:30443@loadbalancer"` (PITFALLS suggestion). Both work; lock during Phase 8 plan review.
- (P35) Should `task fix-dns-poc-capsule` be a separate task OR `task fix-dns` accept `KARYON_POC_FIXDNS=capsule` env-var? **Recommended:** separate task (cleaner default isolation per P31).

### Phase 9 (Capsule install)
- (P34) certgen vs cert-manager — recommendation is built-in certgen for the POC. Confirm with a Phase 9 plan-time live test that chart upgrade re-issuing the cert doesn't break running webhooks.
- (P26) Verify Capsule chart's default `objectSelector` excludes `capsule.clastix.io/tenant=` not present. If yes, `failurePolicy: Ignore` override is belt-and-suspenders; if no, it's load-bearing.
- (STACK Confidence summary) capsule-addon-fluxcd v0.2.3 ↔ Capsule v0.12.4 specific compatibility — MEDIUM. Phase 9 should re-verify with a smoke test if the addon is brought into Phase B scope (it is OPTIONAL).

### Phase 10 (Tenants + Flux lockdown)
- (FEATURES "Dependency Notes") `--no-cross-namespace-refs=true` flag patch applies cluster-wide — could break a v0.18 cross-namespace ref. Mitigation: Phase 10 plan acceptance includes rerun of v0.18 `task health-check` as regression gate.
- (P40) Verify every `secretRef` in `pocs/capsule/**` uses `key: value.yaml` — including proxy kubeconfig Secrets (NOT just spoke-capsule-kubeconfig).
- (TS-10 risk note) Platform-admin escape hatch (`flux-system` Kustomization gets explicit `spec.serviceAccountName: kustomize-controller`) MUST land in the same patch.

### Phase 11 (Tenant kubeconfig)
- (ARCHITECTURE Public-repo / Secrets Layer) Stdout-only output OR optional gitignored path (`.kubeconfigs/karyon-tenant-<name>.yaml`)? **Recommended:** stdout-only by default; document convention in `docs/poc-capsule.md`.
- (P29) Decide whether the kubeconfig generator should emit a public-safe `*-template.yaml` companion file with placeholder for the bearer token, distinct from runtime artifact. Probably yes — template is committable, artifact is not.
- (P33) Lock the choice: `additionalSANs: [127.0.0.1, localhost]` in capsule-proxy Helm values OR `insecure-skip-tls-verify: true` in tenant kubeconfig. **Recommended:** SANs first (cleaner); skip-verify as fallback documented in ADR-008 trade-offs.

### Phase 12 (Validation + ADR-008)
- (P36) Teardown ordering script must handle `Tenant.spec.preventDeletion: true` case. Phase 12 plan should specify whether the POC sets this for either tenant (DF-03 differentiator suggests one might).
- (P37) Decide canonical negative-RBAC test idiom: `kubectl auth can-i` (subject to SAR cache flake) vs real `kubectl get` (more reliable but slower). **Recommended:** both; `auth can-i` for fast static; `kubectl get | grep -q Forbidden` for validation negatives.
- (TS-11 detail) For webhook failure observation, scale to 0 vs delete the operator deploy entirely — does recovery look the same? Phase 12 plan picks one.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | **HIGH** | All 3 chart pins verified against upstream GitHub release API the day of writing. Two MEDIUM caveats: capsule-addon-fluxcd ↔ Capsule v0.12.4 specific compatibility (date proximity strong, README declaration absent); k3d NodePort + WSL host-port-publish pattern (HIGH overall, one open syntactic question) |
| Features | **HIGH** | Context7 `/projectcapsule/capsule` 267 snippets benchmark 89.6, official Capsule + Flux docs cross-verified, multiple production case studies. Two MEDIUM-confidence claims flagged as POC-level falsifiers |
| Architecture | **HIGH** | v0.18 invariants verified by reading committed files directly. clastix/flux2-capsule-multi-tenancy reference matches recommended pattern verbatim. Reconciliation Pattern Decision (option c) explicitly the right call |
| Pitfalls | **HIGH** | All critical pitfalls (P26–P34) traced to authoritative sources. Two MEDIUM-confidence: P38 (Capsule v0.12 + k3s v1.34.6 currency — matrix is fresh) and P35 (CoreDNS staleness extrapolated from k3d issues) |

**Overall confidence: HIGH.** The four research files agree on the mental model, pin set, and load-bearing pitfalls; they disagree only on phase granularity (4 vs 6 — reconciled in favor of 6) and minor open questions appropriate to resolve at plan-time.

### Gaps to Address During Implementation

- **capsule-addon-fluxcd compatibility verification** — Phase 9 if and only if addon brought into scope (OPTIONAL per PROJECT.md).
- **Lockdown flag regression** — Phase 10 must rerun full v0.18 `task health-check` after `--no-cross-namespace-refs=true` lands.
- **Webhook objectSelector default** — Phase 9 should empirically confirm the chart's default `objectSelector` excludes non-tenant namespaces.

---

## Sources

### Primary (HIGH confidence)

- **Authoritative — Capsule project:**
  - Context7 `/projectcapsule/capsule` (267 snippets, benchmark 89.6) — Tenant CRD shape, Helm install patterns, namespace impersonation
  - GitHub release API: Capsule v0.12.4, capsule-proxy v0.12.0, capsule-addon-fluxcd v0.2.3
  - Capsule v0.12.4 chart values — `tls.enableController: true`, `crds.install: true`, `proxy.enabled: false`
  - capsule-proxy v0.12.0 chart values — `service.type` ClusterIP/NodePort/LoadBalancer, `listeningPort: 9001`, `capsuleConfigurationName: default`
  - Capsule DEVELOPMENT.md — webhook list (9 endpoints)
  - projectcapsule.dev — installation, proxy options/feature gates, tenant authentication, Use FluxCD guide
- **Authoritative — Flux:**
  - Flux multi-tenancy lockdown configuration — three lockdown flags + platform-admin SA escape hatch
  - Flux Kustomization spec v1 — `kubeConfig`/`serviceAccountName` interaction; **`--default-service-account` does NOT apply when `spec.kubeConfig` is set** (the load-bearing P27 fact)
  - fluxcd/flux2-multi-tenancy — canonical multi-tenancy reference repo
  - clastix/flux2-capsule-multi-tenancy ARCHITECTURE.md — proxy-kubeconfig-generator workflow; SA-as-Tenant-Owner impersonation
- **Authoritative — Kubernetes:**
  - Admission Webhook Good Practices — `failurePolicy: Ignore` guidance
  - SubjectAccessReview cache TTLs (`authorizedTTL: 5m`, `unauthorizedTTL: 30s`)
- **Repo-internal cross-references (HIGH — verified by reading committed files):**
  - clusters/hub-flux/flux-system/kustomization.yaml — existing `# KARYON SPOKES MOUNT` sentinel + FLUX PATCH SURFACE comment block
  - clusters/hub-flux/spokes/spoke-apps.yaml — proven `spec.kubeConfig.secretRef + key: value.yaml` shape
  - scripts/register-spokes-for-flux.sh — `ensure_hub_spokes_mount()` sentinel-insertion pattern
  - docs/adr/0004-hub-only-flux-control-plane.md — ADR-004 invariant
  - .planning/PROJECT.md v0.19 milestone scope, deferred items
  - .planning/MILESTONES.md v0.18 baseline

### Secondary (MEDIUM confidence — production case studies)

- TomTom Engineering — Kubernetes multi-tenancy with Capsule
- pet2cattle — How to make Kubernetes multi-tenant with Capsule
- DZone — Implementing EKS Multi-Tenancy Using Capsule
- oneuptime — Capsule + Flux CD multi-tenancy walkthrough

### Tertiary (issue trackers — MEDIUM, used for behavior corroboration)

- projectcapsule/capsule#143 — Capsule pods become unresponsive (failurePolicy semantics)
- projectcapsule/capsule#1360 — Capsule upgrade in FluxCD failing due to missing certgen Job
- projectcapsule/capsule#1292 — cluster-admin actions intercepted as tenant owner
- fluxcd/flux2#5543 — Allow impersonating service accounts in arbitrary namespace on remote clusters
- fluxcd/flux2#5465 — RFC-0010 full multi-tenancy lockdown support
- k3d#1009, k3d#1112 — CoreDNS NodeHosts staleness (inherited from v0.18 P11)

### Detailed research files (primary inputs to this synthesis)

- .planning/research/STACK.md — chart pins, OCI URLs, k8s floor, CRDs introduced, Flux multi-tenancy knobs
- .planning/research/FEATURES.md — table-stakes 12, differentiators 8, anti-features 10, negative-RBAC table N1–N12
- .planning/research/ARCHITECTURE.md — topology diagram, KARYON POC MOUNT shape, repo layout, reconciliation pattern decision (option c selected over a + b), tenant onboarding sequence, build order, boundary with existing system
- .planning/research/PITFALLS.md — 18 pitfalls (P26–P43) catalogued by severity, recovery strategies, phase-mapping matrix

---

*Research synthesis for: v0.19 Capsule Multi-Tenancy POC — additive to karyon Lab v1 (v0.18 shipped 2026-04-29).*
*Synthesized: 2026-04-29.*
*Ready for requirements + roadmap: yes.*
