# Phase 13: RBAC Narrowing + GlobalTenantResource Seed + Delivery Mechanism - Context

**Gathered:** 2026-05-19
**Status:** Ready for planning
**Mode:** `--auto` (Claude picked recommended defaults for every gray area; see DISCUSSION-LOG.md for the audit trail)

<domain>
## Phase Boundary

Phase 13 ships the **artifacts** that make the three-tier permission model + tenant-namespace seeding falsifiable. It does NOT ship the demo runbook or the two-perspective live walkthrough (Phase 14 owns those). Concretely, Phase 13 succeeds when:

1. **`tenant-workload-editor` ClusterRole exists** on `spoke-capsule` — narrower than upstream k8s `edit` (no Secret create/edit per D-13-01, no RoleBinding, no ResourceQuota, no LimitRange).
2. **Per-tenant `human-tenant-owner` SAs exist** in `tenant-alpha` + `tenant-bravo` namespaces and are listed as Tenant CR co-owners with explicit `clusterRoles: [tenant-workload-editor]`. The existing Flux SA owner (`gitops-reconciler` with default `clusterRoles: [admin, capsule-namespace-deleter]`) is preserved verbatim per RBAC-03 — v0.19 Flux reconcile loop continues unbroken.
3. **`issue-tenant-kubeconfig.sh` mints kubeconfigs for the new `human-tenant-owner` SA** so the resulting kubeconfig binds to `tenant-workload-editor` (NOT `admin`). `kubectl auth can-i '*' '*'` returns `no` for the resulting identity (RBAC-02).
4. **Platform-owner identity exists** as a real SA (`platform-owner` in `capsule-system` ns), bound to the existing `capsule-platform-owner` ClusterRole via an extended ClusterRoleBinding (subjects = both `Group: capsule-platform-owners` for the spike's impersonation path AND `ServiceAccount: platform-owner@capsule-system` for the v0.20 TokenRequest kubeconfig). `kubectl auth can-i '*' '*'` returns `no` under the platform-owner kubeconfig (RBAC-04).
5. **Platform-owner is a Tenant CR co-owner** on alpha + bravo (additive `spec.owners[]` additions — both the Group AND the SA, so impersonation AND TokenRequest-kubeconfig paths get tenant-namespace operational access). New-tenant provisioning template carries the same co-owners by default (RBAC-05/RBAC-06).
6. **`issue-platform-owner-kubeconfig.sh` exists** — mints a TokenRequest-backed kubeconfig for the platform-owner SA, routed through capsule-proxy NodePort 30443 (uniform proxy path with tenant kubeconfigs).
7. **`GlobalTenantResource` CR is reconciled** into `spoke-capsule` and auto-propagates a hello-world Pod + Service into every existing tenant namespace (alpha-app1, tenant-alpha, bravo-app1, tenant-bravo). Propagation latency ≤ 60s on a fresh-namespace falsifier (SEED-01/02/03).
8. **All new artifacts land via GitOps under `pocs/capsule/spoke/`** (per OQ-4 resolution D-13-03). No new Taskfile entries, no `task seed-capsule-demo`. Existing alpha + bravo Tenant CR diffs are ADDITIVE-only (no removals from `spec.owners[]`, no destructive edits). P31 invariant preserved (zero new `spoke-capsule` mentions in any v0.18 default-path script) — DELIVERY-01/02/03.
9. **Wave 0 RED bats scaffold lands first** (Plan 13-00) — covers the ClusterRole grant matrix, GlobalTenantResource propagation falsifier, platform-owner cluster-admin Forbidden assertions + Tenant CR CRUD positive controls, and P27/P29/P31 + ADR-004 regression greps.

**Phase 13 ships ARTIFACTS only.** The following are out of scope for Phase 13:

- **Two-perspective demo walkthrough (DEMO-01..06)** → Phase 14.
- **6-act runbook `docs/poc-capsule-demo.md` (RUNBOOK-01..05)** → Phase 14.
- **TLS noise treatment (OQ-1)** → Phase 14 (RUNBOOK-03).
- **New-tenant marquee name + provision-live vs pre-staged dance (OQ-5)** → Phase 14 (RBAC-05 demo verification; Phase 13's RBAC-05 bats uses a throwaway test tenant like `phase13-fresh`).
- **REQUIREMENTS.md `[ ]` → `[x]` checkbox flips against live evidence + retrospective** → Phase 15.

**Three-tier permission model boundaries this phase delivers:**

- **Tier 2 (platform-owner — Karyon Platform Team)** — falsifiable on `spoke-capsule` via RBAC-04 (no cluster-admin), RBAC-05 (Tenant CR CRUD works), RBAC-06 (co-owner LIST/EXEC works). Out-of-tenant ceiling lands here; Phase 14 verifies the human walkthrough.
- **Tier 3 (tenant-owner — Tenant Devs)** — falsifiable on `spoke-capsule` via RBAC-01 (ClusterRole narrower than edit), RBAC-02 (kubeconfig `auth can-i '*' '*'` no). Phase 14 verifies cross-tenant rejection + create-secret Forbidden live.

</domain>

<decisions>
## Implementation Decisions

### Open Questions resolved (auto-picked recommended defaults)

#### D-13-01: OQ-2 — `tenant-workload-editor` Secrets policy = **read-only**

`tenant-workload-editor` ClusterRole grants `secrets` access at **read-only** scope: `get`, `list`, `watch` only. NO `create`, `update`, `patch`, `delete` on Secrets. Recommended per PROJECT.md OQ list ("read-only (recommended)").

- **Rationale:** Read-only Secret access lets tenant developers pull a TLS secret an operator pre-staged (legitimate POC ergonomics) without granting the keys-to-the-kingdom create/edit power that lets a compromised tenant identity exfiltrate API tokens, sign new CSRs, etc. RBAC-01's "narrower than edit" requirement is satisfied: upstream k8s `edit` ClusterRole grants full Secret CRUD; this role removes 4 of the 5 verbs.
- **DEMO-04 implication:** Tenant-owner gets Forbidden on `kubectl create secret` (the literal RBAC-01 boundary enforcement test). Read-only Secret access does NOT undermine the demo narrative — the audience-facing assertion is "tenant-owner can't CREATE secrets", which is the rejection the runbook scripts.
- **Researcher note:** Verify upstream k8s `edit` ClusterRole's exact Secret verbs against the k8s 1.34.x release matching `rancher/k3s:v1.34.6-k3s1` (ADR-005); document the diff in Plan 13-RESEARCH.

#### D-13-02: OQ-3 — Hello-world workload shape = **Pod + Service**

The `GlobalTenantResource`-propagated workload is a Pod (single nginx container) + a ClusterIP Service (port 80 → Pod port 80). NOT ConfigMap-only (fastest but no running workload to LIST/EXEC against). NOT Deployment + Service + ConfigMap (heavier; pulls in Deployment churn for a demo that doesn't exercise replica scaling). Recommended per PROJECT.md OQ list ("Pod + Service (recommended; lightweight, visual)").

- **Rationale:** Pod + Service is the smallest visually-meaningful workload shape for the demo: tenant-owner can `kubectl get pods` (sees the Pod), `kubectl logs <pod>` (positive control), `kubectl exec <pod> ...` (positive control), `kubectl get svc` (sees the Service). Platform-owner sees the same across all tenants (RBAC-06 + DEMO-01). Deployment shape would add replica-count noise without adding demo value.
- **Image choice (specifics, planner discretion):** `nginx:alpine` — small (~5 MB), ubiquitous, no GPU / no special runtime needs. **Caveat (specifics):** the existing alpha/bravo Tenant CRs carry `containerRegistries.allowed: [registry.example.io]` from Phase 9 N7 fixture; pulling from `docker.io/library/nginx:alpine` would be REJECTED by Capsule's webhook. **Researcher MUST verify in Plan 13-RESEARCH** whether (a) we relax the registry allowlist on the Tenant CRs to include `docker.io` for v0.20, (b) we keep nginx but mirror via local image stamp (`karyon/k3s-cuda`-style pre-baked image), or (c) we switch to a different workload (busybox sleep, hashicorp/http-echo, etc.) hosted on `registry.example.io` (fictional — must be pulled-and-retagged into the local k3d registry or made truly local). **Recommended approach (planner reshapes freely):** add `docker.io` to the `containerRegistries.allowed` list on alpha + bravo Tenant CRs as part of Plan 13-01 (additive change). This is a tenant-spec mutation but it's purely additive and does NOT regress the Phase 9 N7 negative-RBAC fixture (N7 uses a DIFFERENT registry — `nginx` from `docker.io` works; an arbitrary third registry still rejects). Document the trade-off in CONTEXT.md → planner → PLAN.md → DECISIONS.

#### D-13-03: OQ-4 — Delivery path = **GitOps under `pocs/capsule/`**

All new demo artifacts (ClusterRole, GlobalTenantResource, hello-world Pod + Service, platform-owner SA + CRB extension, per-tenant `human-tenant-owner` SAs, Tenant CR co-owner additions) land via Flux reconcile of `pocs/capsule/spoke/` (spoke-targeted) and/or `pocs/capsule/` (hub-targeted). NO new Taskfile entries. NO `task seed-capsule-demo`.

- **Rationale:**
  1. **P31 isolation preserved cleanly.** Adding a Taskfile entry would land a new top-level task in `Taskfile.yml` (not under `scripts/poc/capsule/`). Static bats `tests/bats/poc-isolation-01-static.bats` would need to be updated to whitelist it. GitOps path needs zero Taskfile churn.
  2. **Existing KARYON POC MOUNT sentinel handles it.** `clusters/hub-flux/flux-system/kustomization.yaml` already mounts `clusters/hub-flux/pocs/capsule.yaml` (hub-targeted) + `capsule-spoke.yaml` (spoke-targeted) + `capsule-spoke-rbac.yaml` + `capsule-spoke-tenants.yaml`. New artifacts ride the existing reconcile loops — no new Flux Kustomizations required unless sequencing demands it.
  3. **Production-correct.** A future EKS-translation per `docs/capsule-on-eks.md` would use GitOps for new RBAC + custom Capsule resources. A `task seed-capsule-demo` direct-apply mechanism would NOT translate.
  4. **Faster than expected.** Concern that GitOps adds reconcile-cycle latency vs `task ... apply -f` is real but small (Flux interval = 5m default; can be force-reconciled via `flux reconcile kustomization poc-capsule-spoke --with-source`). Demo prep can include a force-reconcile in the pre-demo checklist (RUNBOOK-02 Phase 14 concern).
- **`task seed-capsule-demo` rejected:** Introduces a non-GitOps surface for demo content; needs P31 isolation whitelist; doesn't translate to EKS; adds a 3rd POC entry point (we already have `task fix-dns-poc-capsule`, `task fail-capsule-webhook`, `task destroy-poc`). Future enhancement only if Phase 14 finds GitOps reconcile latency to be a demo-killer (unlikely; force-reconcile is fast).

### RBAC architecture

#### D-13-04: `tenant-workload-editor` ClusterRole shape (narrower than `edit`)

Define a new cluster-scoped role at `pocs/capsule/spoke/rbac/tenant-workload-editor.yaml`. **Positive grants** (the typical tenant-developer workload-author surface):

- `pods`, `pods/log`, `pods/exec`, `pods/portforward` — get/list/watch/create/update/patch/delete/deletecollection (workload management) + create on pods/exec, pods/portforward subresources.
- `deployments`, `replicasets`, `statefulsets`, `daemonsets`, `jobs`, `cronjobs` — full CRUD (workload lifecycle).
- `services`, `endpoints`, `endpointslices` — full CRUD (service exposure).
- `configmaps` — full CRUD (workload configuration).
- `persistentvolumeclaims` — get/list/watch (read-only — PV creation is platform-team concern; tenant can request via existing PVC mechanism but not edit cluster-scoped storage).
- `events` — get/list/watch (debugging).
- `secrets` — **get/list/watch only** (per D-13-01).

**Explicit denials** (the four "narrower than `edit`" guarantees from RBAC-01):

- NO `secrets` `create/update/patch/delete/deletecollection`.
- NO `rolebindings`, `roles` any verb.
- NO `resourcequotas` any verb.
- NO `limitranges` any verb.

**Additional implicit denials** (everything not in the positive list is denied by default):

- NO `nodes`, `csr`, `clusterrolebinding`, `clusterrole`, `customresourcedefinitions` (Tier-1/Tier-2 surface).
- NO `tenants.capsule.clastix.io` (Tier-2 surface; tenant-owner can't create/modify Tenants).
- NO `networkpolicies` (defense-in-depth; tenant can't disable existing network isolation).

**Apply scope:** ClusterRole (not Role). Capsule's `additionalRoleBindings` or owner `clusterRoles:` mechanism binds it to per-tenant namespaces (D-13-05). The ClusterRole is named — not auto-aggregated into `system:aggregate-to-edit` to avoid surprise inheritance from upstream label-selector aggregation.

**Bats falsifier (Wave 0 static):** Grep-assert positive verbs present; assert each of the 4 denial categories absent; assert `apiGroups` shapes match k8s 1.34 conventions (`""`, `apps`, `batch`, `networking.k8s.io`).

#### D-13-05: `tenant-workload-editor` binding mechanism — per-tenant SA in `spec.owners[]`

New per-tenant ServiceAccount `human-tenant-owner` is added in `tenant-<tenant>` namespace and listed as a Tenant CR co-owner with **explicit `clusterRoles: [tenant-workload-editor]`** field set on that owner entry. The existing `gitops-reconciler` SA owner (with implicit default `clusterRoles: [admin, capsule-namespace-deleter]`) is **preserved verbatim** per RBAC-03 — v0.19 Flux reconcile loop continues unbroken.

**Example Tenant CR diff (alpha — additive only):**

```yaml
# pocs/capsule/spoke/tenant-crs/alpha.yaml (EDITED — additions ONLY)
spec:
  owners:
    # === Existing entries preserved verbatim (RBAC-03 regression gate) ===
    - kind: ServiceAccount
      name: system:serviceaccount:flux-system:flux-reconciler
      # (clusterRoles not set; Capsule defaults to [admin, capsule-namespace-deleter])
    - kind: ServiceAccount
      name: system:serviceaccount:tenant-alpha:gitops-reconciler
      # (clusterRoles not set; Capsule defaults to [admin, capsule-namespace-deleter])
    - kind: User
      name: alpha
      # (clusterRoles not set; Capsule defaults; not used for v0.20 demo)
    # === NEW entries (Phase 13 additive) ===
    - kind: ServiceAccount
      name: system:serviceaccount:tenant-alpha:human-tenant-owner
      clusterRoles:                            # ← EXPLICIT (not default)
        - tenant-workload-editor              # ← D-13-04 ClusterRole
    - kind: Group
      name: capsule-platform-owners            # ← D-13-07 platform-owner co-ownership (Group path)
      # clusterRoles not set; Capsule defaults [admin, capsule-namespace-deleter] —
      # broader-than-tenant-workload-editor + narrower-than-cluster-admin is the
      # platform-team operational ceiling per Three-Tier Model (Tier 2)
    - kind: ServiceAccount
      name: system:serviceaccount:capsule-system:platform-owner   # ← D-13-07 SA path
      # clusterRoles not set; Capsule defaults [admin, capsule-namespace-deleter]
```

Bravo follows the identical shape (s/alpha/bravo/g) preserved verbatim from Phase 11 D-11-07 + Phase 9 D-09-02 + Phase 9 N6/N7 fixtures.

- **Rationale:** Capsule v0.12.4's per-owner `clusterRoles: []string` field is the natural extension. Researcher MUST verify the schema accepts mixed implicit-default + explicit-clusterRoles entries in the same `spec.owners[]` array (low risk — confirmed via Phase 9 RESEARCH §Gap 4 + Capsule docs; the field is non-required and per-entry).
- **`additionalRoleBindings` alternative (rejected):** Capsule also offers `spec.additionalRoleBindings[]` for arbitrary CR → role bindings inside tenant namespaces. This would bypass the `spec.owners[]` machinery and not engage Capsule-proxy's owner-aware LIST filter. Owner-entry + explicit `clusterRoles:` is the idiomatic Capsule v0.12.4 path.

#### D-13-06: Platform-owner identity — SA in `capsule-system` ns + dual-subject CRB

Land a new ServiceAccount `platform-owner` in `capsule-system` namespace and **extend** the existing `capsule-platform-owner` ClusterRoleBinding's `subjects[]` array to include this SA in addition to the existing `Group: capsule-platform-owners`. The existing ClusterRole (`pocs/capsule/spoke/rbac/platform-owner.yaml`) shape is preserved verbatim; only the binding is extended.

**Example diff (additive only):**

```yaml
# pocs/capsule/spoke/rbac/platform-owner.yaml (EDITED — subjects[] only)
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: capsule-platform-owner
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: capsule-platform-owner
subjects:
  # === Existing entry preserved verbatim ===
  - apiGroup: rbac.authorization.k8s.io
    kind: Group
    name: capsule-platform-owners            # impersonation path: `kubectl --as=... --as-group=capsule-platform-owners`
  # === NEW entry (Phase 13 additive) ===
  - kind: ServiceAccount                     # SA-token-authenticated kubeconfig path (v0.20 demo)
    name: platform-owner
    namespace: capsule-system
```

A NEW file `pocs/capsule/spoke/rbac/platform-owner-sa.yaml` lands the SA:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: platform-owner
  namespace: capsule-system
  labels:
    karyon.io/poc: capsule
    karyon.io/role: capsule-platform-owner
```

`pocs/capsule/spoke/rbac/kustomization.yaml` is updated to include the new file (after `namespace.yaml` so the namespace exists first; placement after `helm-controller-sa.yaml` is fine since they're both in `capsule-system`).

- **Rationale:** Dual-subject CRB keeps both identity-delivery paths working: the spike's `kubectl --as=... --as-group=capsule-platform-owners` impersonation pattern (existing demo invocation example in platform-owner.yaml head comment) AND the v0.20 TokenRequest-backed kubeconfig (D-13-09 below) for `kubectl --kubeconfig=<minted>`. Planner may keep both paths documented in Plan 13-02 SUMMARY.

#### D-13-07: Platform-owner Tenant CR co-ownership — Group + SA dual entries

Both `Group: capsule-platform-owners` AND `ServiceAccount: system:serviceaccount:capsule-system:platform-owner` are added to **every existing Tenant CR's `spec.owners[]`** (alpha + bravo), AND to every newly-created Tenant CR via the provisioning template (D-13-08). Both entries use Capsule's default `clusterRoles: [admin, capsule-namespace-deleter]` (NOT `tenant-workload-editor` — platform-owner needs broader cross-tenant-namespace operational access for debug, but still bounded by the tenant-namespace scope through capsule-proxy LIST filtering).

- **Rationale:** Both entries are load-bearing:
  - **`Group: capsule-platform-owners`** — load-bearing for the impersonation demo path AND for the future-EKS-translation pattern (in EKS, this Group is bound to an IRSA-backed IdP group identity).
  - **`ServiceAccount platform-owner@capsule-system`** — load-bearing for the v0.20 SA-token kubeconfig path. Capsule-proxy's LIST filter matches on the SA-token-authenticated subject's tenant ownership. Without the SA entry, the platform-owner kubeconfig would still authenticate (via the dual-subject CRB) but capsule-proxy would NOT include alpha/bravo namespaces in the LIST result (no tenant ownership for the SA = no LIST filter hit). Group impersonation isn't a kubeconfig persona — it's a transient impersonation token.
- **Bats falsifier (Wave 0 static):** Grep-assert each new Tenant CR's `spec.owners[]` contains BOTH entries; assert existing entries (flux-reconciler SA, gitops-reconciler SA, User) are preserved character-for-character.
- **CapsuleConfiguration `userGroups` inheritance:** Phase 11 D-11-02 already added `system:serviceaccounts` + `system:authenticated` to `capsule.clastix.io` group filter (`pocs/capsule/spoke/config/capsuleconfig.yaml` lines 32-35). This is REQUIRED for capsule-proxy LIST filter to recognize SA-token-authenticated subjects as tenant owners. Phase 13 inherits this — no edits. Researcher RE-VERIFIES live state via `kubectl get capsuleconfiguration default -o yaml` before Plan 13-00.

#### D-13-08: New-tenant provisioning template + script

Land `scripts/poc/capsule/new-tenant.sh <name>` that substitutes a tenant name into a YAML template and applies via `kubectl --kubeconfig=<platform-owner-kc> apply -f -`. The template lives at `scripts/poc/capsule/templates/new-tenant.yaml.tmpl` (planner discretion on exact filename; could be inline heredoc in the script). The template MUST include the `capsule-platform-owners` Group + `platform-owner` SA + a per-new-tenant `human-tenant-owner` SA in `spec.owners[]` BY DEFAULT — RBAC-05/06 requires this.

- **Script shape (mirrors `issue-tenant-kubeconfig.sh` ergonomics):**
  - Positional arg: `<name>` (e.g., `phase13-fresh`, `charlie`).
  - Flags: `--dry-run` (kubectl-dry-run; print the rendered YAML without apply); `--kubeconfig <path>` (default reads `${TMPDIR:-/tmp}/karyon-tenants/platform-owner.kubeconfig` if present, else falls back to `~/.kube/config` cluster-admin).
  - Calls preflight-lib for log helpers, fail-fast pattern matching v0.18 + Phase 7.
  - Validates `<name>` against `^[a-z][a-z0-9-]{1,30}$` regex (Capsule's namespace-name constraint) — fail-fast on invalid input.
- **What the rendered YAML produces** for tenant `<name>`:
  1. `Tenant/<name>` CR with `spec.owners[]` carrying: `Group capsule-platform-owners`, `SA system:serviceaccount:capsule-system:platform-owner`, `SA system:serviceaccount:tenant-<name>:human-tenant-owner` (`clusterRoles: [tenant-workload-editor]`), `SA system:serviceaccount:flux-system:flux-reconciler` (matches existing alpha/bravo pattern for Capsule namespace-assignment webhook), and `forceTenantPrefix: false` matching D-11-07 live repair.
  2. `Namespace/tenant-<name>` with `capsule.clastix.io/tenant: <name>` label.
  3. `ServiceAccount/human-tenant-owner` in `tenant-<name>` namespace.
- **NOT included in the rendered YAML:** A per-tenant `gitops-reconciler` SA (the alpha/bravo Flux-driven pattern). RBAC-05's "provision a new tenant live" demo doesn't need Flux reconciliation of the new tenant; it just needs the Tenant CR + namespace + human-tenant-owner SA so the platform-owner can demonstrate CREATE → LIST → SEED-02 propagation → DELETE. If a future phase wants Flux-driven new-tenant reconciliation, the template grows to add a `gitops-reconciler` SA + corresponding owner entry.
- **Researcher MUST verify:** The minimal Tenant CR shape (without `resourceQuotas`, `limitRanges`, `containerRegistries`, `namespaceOptions`) is accepted by Capsule v0.12.4's admission webhook. The alpha/bravo CRs carry these for Phase 9 N6/N7 fixtures; the new-tenant template MAY omit them (Capsule defaults to no-quota / no-limit-range / allow-all-registries). If the webhook rejects, add minimal-default values to the template.

#### D-13-09: New script `scripts/poc/capsule/issue-platform-owner-kubeconfig.sh`

Mirrors `scripts/poc/capsule/issue-tenant-kubeconfig.sh` structure (TokenRequest, TLS embed via `tls.crt`, stdout YAML, optional `--write-to` rooted at `${TMPDIR:-/tmp}/karyon-tenants/`, `--duration <d>` default `1h`).

- **Target identity:** `ServiceAccount/platform-owner` in `capsule-system` namespace (D-13-06).
- **Cluster server URL in issued kubeconfig:** `https://127.0.0.1:30443` (capsule-proxy NodePort — D-13-10 below). NOT `:6446` direct apiserver — RBAC-06's "platform-owner sees all tenant namespaces through proxy" requires the proxy path.
- **Context name in issued kubeconfig:** `platform-owner-via-proxy`. User name: `platform-owner`. Cluster name: `capsule-proxy-127.0.0.1` (identical to tenant-kubeconfig cluster name; the proxy serves multiple identities).
- **Default namespace (`context.namespace`):** unset (platform-owner ops are mostly cluster-scoped — Tenant CR LIST, namespaces LIST — not pinned to one ns).
- **Preflight checks:**
  1. `kubectl --context=k3d-spoke-capsule -n capsule-system get sa platform-owner` exists.
  2. `kubectl --context=k3d-spoke-capsule get clusterrolebinding capsule-platform-owner` exists.
  3. Subjects[] of the CRB include the SA (asserts the binding is live, not just the CR).
  4. Capsule-proxy reachable on `:30443` (TLS cert fetched).
- **Stdout/stderr contract:** identical to `issue-tenant-kubeconfig.sh` — stdout pure YAML, stderr all log lines via shadowed preflight-lib helpers (per Pitfall 10-P7).
- **Bats coverage (D-13-15):** static (script shape: shebang, args, literals, header citation) + live (run script, decode JWT, assert payload + `aud` claim + TokenRequest duration ≈ requested).

#### D-13-10: Platform-owner kubeconfig routing — capsule-proxy NodePort 30443

The minted platform-owner kubeconfig points at `https://127.0.0.1:30443` (capsule-proxy). NOT the spoke apiserver `:6446`. Same uniform pattern as Phase 10 tenant kubeconfigs.

- **Rationale:** RBAC-06 + DEMO-01 expect the platform-owner kubeconfig to LIST namespaces across all tenants. Capsule-proxy applies its LIST filter on the SA-authenticated identity's tenant ownership (D-13-07 added SA to `spec.owners[]`), so a proxy-routed LIST returns alpha + bravo namespaces (+ any new tenant the platform-owner provisions). Direct apiserver LIST would return ALL namespaces (kube-system, flux-system, capsule-system, etc.) — but the platform-owner ClusterRole grants `namespaces` get/list/watch at cluster scope, so the result would be the full list. That's the "platform-owner sees too much" surface RBAC-04 wants to prevent. Capsule-proxy filtering is the bounded path.
- **DEMO-06 (Forbidden) implication:** Platform-owner kubeconfig routed through proxy hits Forbidden on `get nodes`, `get csr`, `create clusterrolebinding` — because the underlying RBAC denies these verbs. The proxy may either forward and let apiserver return Forbidden, OR reject upstream. Either path produces the demo-visible Forbidden response. Researcher verifies capsule-proxy's behavior on cluster-scoped non-Capsule resources during Plan 13-RESEARCH.
- **Cert source:** Same as Phase 10 D-10-06 — read `tls.crt` from `capsule-system/capsule-proxy` Secret (Phase 10 Pitfall 10-P1 verified: the chart's certgen Job outputs `tls.crt` + `tls.key` only; `tls.crt` doubles as the CA root).

### GlobalTenantResource shape

#### D-13-11: GlobalTenantResource CR — match-all tenant selector

A `GlobalTenantResource` CR (apiVersion to verify in Plan 13-RESEARCH against Capsule v0.12.4 — Phase 9 D-09-04 RESEARCH inheritance confirms `capsule.clastix.io/v1beta2` is the storage version for Tenant CRs; GlobalTenantResource may be on a different sub-version). Selects ALL tenants via match-all tenant selector. Reconciliation interval ≤ 60s (researcher confirms whether the field is `resyncPeriod` or apiserver controller-loop default).

- **Match-all selector** — researcher confirms exact shape; expected:
  ```yaml
  spec:
    tenantSelector:
      matchLabels: {}                    # match-all (empty matchLabels matches every Tenant)
    # OR equivalently:
    # tenantSelector: {}
  ```
- **`resources[]` field shape** — embeds the Pod + Service manifests inline. Researcher verifies whether the CRD expects raw objects or apiVersion+kind references. Per docs/capsule-on-eks.md mention, this CRD "auto-replicates [a resource] into every tenant namespace" — the resource manifest is embedded.
- **Pruning behavior** — `pruningOnDelete: true` so deleting the GlobalTenantResource removes the propagated copies. Researcher confirms exact field name.

**Researcher MUST verify in Plan 13-RESEARCH:**

- Exact CRD `apiVersion` + `kind` name for Capsule v0.12.4 (could be `capsule.clastix.io/v1beta1` GlobalTenantResource, or `capsule.clastix.io/v1beta2` GlobalTenantResource, or a different shape). Confirmed CRD reference for the operator chart pinned in Phase 8 D-08-02 (`capsule:0.12.4`).
- Match-all selector syntax (`matchLabels: {}` vs `{}` vs `matchExpressions: []`).
- Resource embedding shape (inline vs reference vs templated).
- Propagation latency control (`resyncPeriod` field if any) — Phase 13 SEED-02 contract: ≤ 60s.
- Behavior on Tenant CR deletion (does Capsule unmaterialize cleanly?).
- Whether the CR is cluster-scoped (expected) or namespaced.

#### D-13-12: Hello-world workload manifest content

Pod + Service per OQ-3 (D-13-02), embedded in the GlobalTenantResource CR (or referenced from `pocs/capsule/spoke/global-resources/hello-world.yaml`):

```yaml
# Pod
apiVersion: v1
kind: Pod
metadata:
  name: hello-world
  labels:
    app: hello-world
    karyon.io/poc: capsule
    karyon.io/managed-by: capsule-global-tenant-resource
spec:
  containers:
    - name: nginx
      image: nginx:alpine        # SUBJECT TO D-13-02 caveat — see registry-allowlist note above
      ports:
        - containerPort: 80
          name: http
      resources:
        requests:
          cpu: 50m
          memory: 64Mi
        limits:
          cpu: 100m
          memory: 128Mi
---
# Service
apiVersion: v1
kind: Service
metadata:
  name: hello-world
  labels:
    app: hello-world
    karyon.io/poc: capsule
    karyon.io/managed-by: capsule-global-tenant-resource
spec:
  type: ClusterIP
  selector:
    app: hello-world
  ports:
    - port: 80
      targetPort: http
      protocol: TCP
```

- **`karyon.io/managed-by: capsule-global-tenant-resource` label** — provenance for bats grep-assertions and demo narrative ("Capsule auto-propagated this").
- **Resource requests/limits** — small (50m / 64Mi requests; 100m / 128Mi limits). Fits within the per-tenant Phase 9 N6 quota (`pods: 20`, `cpu: 4`, `memory: 8Gi`); 4 namespaces × 1 Pod + 1 Service = 4 Pods + 4 Services = trivial overhead.
- **No replica count** — Pod is a single-instance shape (not a Deployment). This matches OQ-3 = Pod + Service.

### Delivery path artifacts (GitOps)

#### D-13-13: New file layout under `pocs/capsule/spoke/`

```
pocs/capsule/spoke/
├── rbac/
│   ├── kustomization.yaml                       # EDITED — add tenant-workload-editor.yaml + platform-owner-sa.yaml
│   ├── namespace.yaml                           # UNCHANGED
│   ├── helm-controller-sa.yaml                  # UNCHANGED
│   ├── platform-owner.yaml                      # EDITED — extend ClusterRoleBinding subjects[] with SA entry
│   ├── platform-owner-sa.yaml                   # NEW — platform-owner SA in capsule-system ns
│   └── tenant-workload-editor.yaml              # NEW — D-13-04 ClusterRole
├── tenant-crs/
│   ├── kustomization.yaml                       # UNCHANGED
│   ├── alpha.yaml                               # EDITED — additive spec.owners[] entries (D-13-05/07)
│   └── bravo.yaml                               # EDITED — additive spec.owners[] entries (D-13-05/07)
├── tenants/
│   ├── alpha/
│   │   ├── kustomization.yaml                   # EDITED — add human-owner-sa.yaml
│   │   ├── namespace.yaml                       # UNCHANGED
│   │   ├── sa.yaml                              # UNCHANGED (existing gitops-reconciler SA)
│   │   └── human-owner-sa.yaml                  # NEW — human-tenant-owner SA in tenant-alpha
│   └── bravo/
│       ├── kustomization.yaml                   # EDITED — add human-owner-sa.yaml
│       ├── namespace.yaml                       # UNCHANGED
│       ├── sa.yaml                              # UNCHANGED (existing gitops-reconciler SA)
│       └── human-owner-sa.yaml                  # NEW — human-tenant-owner SA in tenant-bravo
├── global-resources/                            # NEW DIRECTORY
│   ├── kustomization.yaml                       # NEW — local Kustomize aggregator
│   └── hello-world.yaml                         # NEW — GlobalTenantResource CR + Pod + Service
├── config/                                      # UNCHANGED (CapsuleConfiguration)
└── kustomization.yaml                           # EDITED — add global-resources/ to resources list
                                                 #   (ordering: rbac/, config/, tenants/, global-resources/)

scripts/poc/capsule/
├── create-cluster.sh                            # UNCHANGED
├── destroy-poc.sh                               # UNCHANGED
├── fail-capsule-webhook.sh                      # UNCHANGED
├── fix-dns.sh                                   # UNCHANGED
├── issue-tenant-kubeconfig.sh                   # EDITED — update <owner> default semantic; expand fail-fast SA enum list (D-13-10b)
├── issue-platform-owner-kubeconfig.sh           # NEW — D-13-09
├── new-tenant.sh                                # NEW — D-13-08
└── templates/
    └── new-tenant.yaml.tmpl                     # NEW — D-13-08 (or inline heredoc in new-tenant.sh; planner discretion)
```

**Sequencing notes:**
- `global-resources/` must apply AFTER `tenants/` so tenant home namespaces exist (the GlobalTenantResource controller will reconcile into existing namespaces on next interval; eager apply may produce transient errors). Researcher confirms Capsule's behavior on apply-before-tenant-namespace-exists.
- The `pocs/capsule/spoke/kustomization.yaml` `resources:` list grows to `[rbac/, config/, tenants/, global-resources/]` (FIFO sortOptions per existing pattern).
- No new outer Flux Kustomization needed. The existing `poc-capsule-spoke` Kustomization (`clusters/hub-flux/pocs/capsule-spoke.yaml`) reconciles the whole `pocs/capsule/spoke/` tree per its current `spec.path: ./pocs/capsule/spoke`.

#### D-13-14: No Taskfile.yml edits

Per D-13-03 (OQ-4 = GitOps), `Taskfile.yml` is UNCHANGED. No `task seed-capsule-demo`. No `task issue-platform-owner-kubeconfig`. POC scripts are invoked directly:

```bash
bash scripts/poc/capsule/issue-platform-owner-kubeconfig.sh                            # 2>/dev/null > /tmp/po.kc
bash scripts/poc/capsule/issue-tenant-kubeconfig.sh alpha human-tenant-owner           # 2>/dev/null > /tmp/alpha.kc
bash scripts/poc/capsule/new-tenant.sh phase13-fresh --kubeconfig /tmp/po.kc           # provision test tenant
```

### Wave 0 RED bats scaffold (D-13-15)

Mirror Phase 7/8/9/10/11 D-09-08 inheritance pattern. Plan 13-00 lands ALL bats RED before any artifact lands. Coverage floor (planner reshapes file partition without re-asking):

**Static (Wave 0) — ClusterRole:**

- `tests/bats/rbac-01-static-tenant-workload-editor.bats` — `pocs/capsule/spoke/rbac/tenant-workload-editor.yaml` exists; grep-assert `kind: ClusterRole`, `name: tenant-workload-editor`; positive verbs (pods CRUD + exec + log, deployments CRUD, services CRUD, configmaps CRUD, jobs/cronjobs CRUD, persistentvolumeclaims get/list/watch, secrets get/list/watch); 4 denial categories absent (no `secrets` create/update/patch/delete; no `rolebindings` any verb; no `resourcequotas` any verb; no `limitranges` any verb).
- `tests/bats/rbac-02-static-platform-owner-sa.bats` — `pocs/capsule/spoke/rbac/platform-owner-sa.yaml` exists; `kind: ServiceAccount`, `metadata.name: platform-owner`, `metadata.namespace: capsule-system`. `pocs/capsule/spoke/rbac/platform-owner.yaml` ClusterRoleBinding `subjects[]` includes BOTH `Group: capsule-platform-owners` AND `ServiceAccount: platform-owner@capsule-system`.
- `tests/bats/rbac-03-static-tenant-co-ownership.bats` — `pocs/capsule/spoke/tenant-crs/alpha.yaml` `spec.owners[]` contains: `Group capsule-platform-owners`, `SA system:serviceaccount:capsule-system:platform-owner`, `SA system:serviceaccount:tenant-alpha:human-tenant-owner` with explicit `clusterRoles: [tenant-workload-editor]`. Existing entries (flux-reconciler SA, gitops-reconciler SA, User alpha) preserved character-for-character. Bravo mirrors.
- `tests/bats/rbac-04-static-human-owner-sa.bats` — `pocs/capsule/spoke/tenants/alpha/human-owner-sa.yaml` exists; ServiceAccount in `tenant-alpha` namespace. Bravo mirrors.

**Static (Wave 0) — GlobalTenantResource:**

- `tests/bats/seed-01-static-globaltenantresource.bats` — `pocs/capsule/spoke/global-resources/hello-world.yaml` exists; grep-assert `kind: GlobalTenantResource` (or CRD-verified name per D-13-11); match-all tenant selector shape; embedded Pod + Service manifests; karyon.io/managed-by provenance label.

**Static (Wave 0) — Invariant regression gates:**

- `tests/bats/poc-isolation-01-static.bats` — UNCHANGED Phase 7 file; re-runs to confirm new artifacts add ZERO `spoke-capsule` mentions in v0.18 default-path scripts.
- `tests/bats/p27-tenant-kustomization-sa-static.bats` — UNCHANGED Phase 9 file; re-runs to confirm `spec.serviceAccountName` still set on every tenant Flux Kustomization.
- `tests/bats/proxy-02-static-leak-defenses.bats` — UNCHANGED Phase 10 file; re-runs to confirm `.gitignore` + `.gitleaks.toml` cover Phase 13's new kubeconfig output (`platform-owner.kubeconfig` under `${TMPDIR:-/tmp}/karyon-tenants/` already covered by Phase 7 D-14 globs).
- `tests/bats/delivery-01-static-mount-sentinel.bats` — NEW; grep-assert `clusters/hub-flux/flux-system/kustomization.yaml` contains `# KARYON POC MOUNT` sentinel; the `../pocs` resource line present; no duplicate sentinel anywhere else.
- `tests/bats/delivery-02-static-paths.bats` — NEW; assert all new artifacts under `pocs/capsule/spoke/` or `scripts/poc/capsule/`; no edits to `Taskfile.yml`; no edits to `scripts/preflight.sh` or other v0.18 scripts.

**Live (Wave 1+) — RBAC:**

- `tests/bats/rbac-05-live-tenant-owner-grant-matrix.bats` — Use `kubectl --context=k3d-spoke-capsule auth can-i` against `system:serviceaccount:tenant-alpha:human-tenant-owner`: positive grants pass (`can-i create pods`, `can-i get secrets`, `can-i create deployments`, etc.); 4 denial categories Forbidden (`can-i create secrets`, `can-i create rolebindings`, `can-i create resourcequotas`, `can-i create limitranges`). Bravo mirrors.
- `tests/bats/rbac-06-live-tenant-kubeconfig.bats` — Run `bash scripts/poc/capsule/issue-tenant-kubeconfig.sh alpha human-tenant-owner > $tmpfile`; `kubectl --kubeconfig=$tmpfile auth can-i '*' '*'` returns `no` (RBAC-02 ceiling); `kubectl --kubeconfig=$tmpfile get pods -n alpha-app1` succeeds (positive control); `kubectl --kubeconfig=$tmpfile create secret generic foo --from-literal=k=v -n alpha-app1` returns Forbidden (D-13-01 boundary).
- `tests/bats/rbac-07-live-flux-sa-preservation.bats` — `kubectl get tenant alpha -o jsonpath='{.spec.owners[?(@.name=="system:serviceaccount:tenant-alpha:gitops-reconciler")]}'` returns the existing entry verbatim; Flux kustomize-controller pod still Ready; existing `poc-capsule-spoke-tenants` Flux Kustomization still Ready=True (RBAC-03 regression gate).
- `tests/bats/rbac-08-live-platform-owner-grant-matrix.bats` — Use `kubectl auth can-i` against `system:serviceaccount:capsule-system:platform-owner`: positive grants (`can-i create tenants`, `can-i get namespaces`, `can-i list customresourcedefinitions`); cluster-admin Forbidden (`can-i get nodes`, `can-i get csr`, `can-i create clusterrolebinding`, `can-i '*' '*'` no). RBAC-04 + RBAC-06.
- `tests/bats/rbac-09-live-platform-owner-kubeconfig.bats` — Run `bash scripts/poc/capsule/issue-platform-owner-kubeconfig.sh > $tmpfile`; `kubectl --kubeconfig=$tmpfile auth can-i '*' '*'` returns `no`; `kubectl --kubeconfig=$tmpfile get tenants` returns alpha + bravo (cluster-scoped LIST through proxy); `kubectl --kubeconfig=$tmpfile get namespaces` returns tenant-alpha + tenant-bravo + alpha-app1 + bravo-app1 (proxy LIST filter applies — co-owner sees co-owned namespaces); `kubectl --kubeconfig=$tmpfile get nodes` Forbidden (RBAC-04 ceiling); `kubectl --kubeconfig=$tmpfile get pods -n tenant-alpha` succeeds (RBAC-06 co-owner LIST/GET).
- `tests/bats/rbac-10-live-tenant-crud.bats` — `kubectl --kubeconfig=$po_kc create -f <new-tenant-yaml>` succeeds (RBAC-05 create); `kubectl --kubeconfig=$po_kc get tenant phase13-fresh` succeeds; `kubectl --kubeconfig=$po_kc patch tenant phase13-fresh ...` succeeds; `kubectl --kubeconfig=$po_kc delete tenant phase13-fresh` succeeds. Use a throwaway tenant name `phase13-fresh` distinct from OQ-5 Phase 14 marquee name. Teardown asserts Capsule unmaterializes tenant namespaces cleanly.

**Live (Wave 1+) — GlobalTenantResource propagation:**

- `tests/bats/seed-02-live-existing-tenants.bats` — Capsule reconciles GlobalTenantResource; assert hello-world Pod + Service materialize in alpha-app1, tenant-alpha, bravo-app1, tenant-bravo (4 namespaces × 2 resources = 8 objects); each Pod reaches Ready state within 60s. `karyon.io/managed-by` label present.
- `tests/bats/seed-03-live-fresh-tenant.bats` — Use platform-owner kubeconfig to `new-tenant.sh phase13-fresh`; wait for namespace `tenant-phase13-fresh` to appear; `kubectl wait pod/hello-world --for=condition=Ready -n tenant-phase13-fresh --timeout=60s` succeeds. SEED-02 ≤60s assertion (the wait itself bounds the latency). Teardown: `kubectl delete tenant phase13-fresh`; assert Capsule unmaterializes (`kubectl wait --for=delete namespace tenant-phase13-fresh --timeout=30s`).
- `tests/bats/seed-04-live-shape.bats` — Assert workload shape matches OQ-3 (Pod + Service only); NO Deployment, NO ReplicaSet, NO ConfigMap created by the GlobalTenantResource (D-13-12 SEED-03).

**Live (Wave 1+) — Delivery regression:**

- `tests/bats/delivery-03-live-additive-only.bats` — `git diff HEAD~N pocs/capsule/spoke/tenant-crs/alpha.yaml` shows additive-only changes to `spec.owners[]` (no removals from the array). Same for bravo. Compare against the SHA of the last Phase 12 commit (planner verifies the right base SHA).
- `tests/bats/delivery-04-live-flux-reconcile.bats` — Existing `poc-capsule-spoke` + `poc-capsule-spoke-rbac` + `poc-capsule-spoke-tenants` Flux Kustomizations all Ready=True after Phase 13 lands. Flux source GitRepository at HEAD; no Ready=False on any outer K.
- `tests/bats/delivery-05-live-slo-regression.bats` — GATED on `KARYON_REBUILD_APPROVED=1` env (per Phase 11 carryover from VAL-04). `task rebuild` exits 0 in < 230s. v0.18 health-check exits 0. Skipped without the env-var gate.
- Re-run Phase 7+8+9+10+11 inheritance bats — `tests/bats/capsule-install-09-live-adr-004.bats` (ADR-004), `tests/bats/tenants-04-static-dependson.bats` (P32 dependsOn chain), `tests/bats/proxy-04-live-issue.bats` (PROXY-01 — `issue-tenant-kubeconfig.sh` script shape; Phase 13 edits to this script must not regress PROXY-01..03). NO modifications to these files in Phase 13; the verifier reruns them.

### Plan ordering (D-13-16)

Recommended plan ordering (planner may reshape into 4–6 plans without re-asking):

- **Plan 13-00 — Wave 0 RED bats scaffold.** Lands ALL bats files RED. Static contracts greppable; live gated on cluster-info probe. Mirrors Phases 7-00 / 8-00 / 9-00 / 10-00 / 11-00.
- **Plan 13-01 — `tenant-workload-editor` ClusterRole + per-tenant human-tenant-owner SAs + Tenant CR human-owner co-ownership additions + `issue-tenant-kubeconfig.sh` <owner> semantic edit.** Lands `tenant-workload-editor.yaml`, `tenants/{alpha,bravo}/human-owner-sa.yaml`, `tenant-crs/{alpha,bravo}.yaml` human-tenant-owner entry; updates `issue-tenant-kubeconfig.sh` fail-fast SA enumeration. RBAC-01 + RBAC-02 + RBAC-03 (regression gate) live bats turn green. Static bats turn green.
- **Plan 13-02 — `platform-owner` SA + extended ClusterRoleBinding + `issue-platform-owner-kubeconfig.sh` + Tenant CR platform-owner co-ownership additions + `new-tenant.sh` template.** Lands `platform-owner-sa.yaml`, extends `platform-owner.yaml` subjects[], lands `issue-platform-owner-kubeconfig.sh`, lands `new-tenant.sh` + template, edits `tenant-crs/{alpha,bravo}.yaml` for platform-owner entries. RBAC-04/05/06 live bats turn green. Static bats turn green.
- **Plan 13-03 — `GlobalTenantResource` CR + hello-world Pod + Service.** Lands `global-resources/hello-world.yaml` + `global-resources/kustomization.yaml`; updates `pocs/capsule/spoke/kustomization.yaml` resources list. If D-13-02 caveat triggers (nginx blocked by registry allowlist), Plan 13-03 also adds `docker.io` to alpha + bravo `containerRegistries.allowed`. SEED-01/02/03 live bats turn green.
- **Plan 13-04 — Verifier.** Reruns ALL Phase 7+8+9+10+11+13 invariants. Writes `13-VERIFICATION.md`. Documents the platform-owner kubeconfig brief in `docs/poc-capsule.md` (1-paragraph "Platform-owner kubeconfig" section that Phase 14 expands into the runbook act 2 narrative). DELIVERY-01/02/03 regression checks green.

Planner may merge 13-01 + 13-02 (full RBAC bundle in one plan; both touch RBAC YAML + scripts), or split 13-03 (CR + workload manifest into separate plans), or roll the `new-tenant.sh` script into 13-02 only if the RBAC bundle isn't too dense. 4–5 plans is the target; 6 plans is acceptable if Wave 0 RED bats partition dictates it.

### Claude's Discretion

The following gray areas are intentionally NOT pre-specified — planner/researcher default to v0.18 + Phase 7-11 patterns and note the chosen approach in PLAN.md without re-asking:

- **`human-tenant-owner` SA name** — recommended `human-tenant-owner` for explicit human-vs-Flux semantic distinction; planner may shorten to `tenant-owner` (collides with existing `User: alpha` owner naming?) or `tenant-human-owner`. Bats grep-pattern updates if the planner changes the name.
- **New-tenant template path** — planner picks `scripts/poc/capsule/templates/new-tenant.yaml.tmpl` (file) vs inline heredoc in `scripts/poc/capsule/new-tenant.sh` (heredoc). Both work; heredoc is simpler for a 1-template POC; file allows multi-template future (e.g., per-environment templates).
- **GlobalTenantResource subdir name** — `pocs/capsule/spoke/global-resources/` vs `pocs/capsule/spoke/seeded-resources/` vs inline under existing `pocs/capsule/spoke/`. Recommended: separate subdir for clarity (researcher and planner can reason about "what's auto-propagated" vs "what's per-tenant manually applied").
- **Reconcile loop noise tolerance** — same as Phases 8/9/10 (≤ 3 reconcile attempts with 30s sleep budget for any live observation gated by Flux reconcile).
- **Bats file naming** — recommended pattern `rbac-NN-{static|live}-<topic>.bats`, `seed-NN-{static|live}-<topic>.bats`, `delivery-NN-{static|live}-<topic>.bats`. Planner reshapes file partition without re-asking.
- **Test fixture for fresh-namespace SEED-02** — planner picks throwaway tenant name (`phase13-fresh`, `phase13-test`, etc.); kept distinct from OQ-5 Phase 14 marquee name (resolved in Phase 14 discuss-phase). Teardown asserts cleanup.
- **TokenRequest duration default for platform-owner kubeconfig** — recommended 1h (mirrors Phase 10 D-10-02). Operator can extend via `--duration` flag.
- **No `task` surface extensions** — continues Phase 7/8/9/10 default. Scripts invoked directly. If Phase 14 demo prep needs `task` ergonomics (e.g., `task seed-capsule-demo` to force-reconcile Flux + verify state), it lands in Phase 14 — NOT Phase 13.
- **Capsule v0.12.4 GlobalTenantResource schema verification** — researcher confirms CRD name + apiVersion + fields during Plan 13-RESEARCH. If the CRD doesn't exist in v0.12.4 (lower version had `TenantResource` cluster-scoped variant; v0.12.x may have renamed), researcher proposes an alternative (cron-style controller, manual propagation script, or fallback to per-tenant TenantResource CRs). Phase 13 boundary assumes the CRD exists; surface alternative early in research if not.
- **Hello-world image source** — `nginx:alpine` vs `busybox` vs `hashicorp/http-echo` vs locally-baked `karyon/hello-world` image stamp. Planner reshapes per D-13-02 caveat (registry allowlist Phase 9 N7 fixture).

### Folded Todos

No todos folded into Phase 13 scope. `gsd-sdk query todo.match-phase 13` returned `todo_count: 0` and an empty matches array.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project planning artifacts (REQUIRED reading)

- `.planning/REQUIREMENTS.md` — v0.20 requirements for Phase 13: RBAC-01..06 (Tier 2 + Tier 3 RBAC narrowing), SEED-01..03 (GlobalTenantResource propagation), DELIVERY-01..03 (additive GitOps + P31 + SLO). Inheritance: v0.18 + v0.19 ADR invariants (ADR-004, P27, P29, P31, KARYON POC MOUNT location, `task rebuild` SLO < 230s, existing alpha/bravo Tenant CRs preserved).
- `.planning/ROADMAP.md` (Phase 13 section + Phase 14 boundary call-out for DEMO + RUNBOOK) — phase goal, ordered success criteria 1-5, dependency declarations (v0.19 baseline + capsule-proxy reachable on NodePort 30443 + ADR-008 DEFER stands).
- `.planning/PROJECT.md` — Three-Tier Permission Model is the load-bearing architectural addition; Anti-Scope guard is active; existing alpha/bravo Tenant CRs preserved as-is; v0.18 + v0.19 inheritance.
- `.planning/STATE.md` — v0.20 milestone-open decisions (lean / additive, 3-phase decomposition); v0.20 roadmap-landing decisions (Phase 13 owns RBAC-01..06 + SEED-01..03 + DELIVERY-01..03 + OQ-2/3/4 resolution; Phase 14 owns DEMO + RUNBOOK + OQ-1/5; Phase 15 close-out + retrospective). Capsule-proxy LIST filter wiring inheritance from Plan 10-02 + Phase 11 D-11-02 (capsule-proxy LIST filter dependency for RBAC-06 + DEMO-01/02 — confirm live state before Plan 13-00 per STATE.md Blockers).

### Phase 7-11 artifacts — REQUIRED context (Phase 13 inherits ALL v0.19 contracts)

- `.planning/milestones/v0.19-phases/07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc/07-CONTEXT.md` — D-05 through D-17. Especially D-10 (NodePort 30443 lock; CAPCLU-01 cluster shape), D-12 (P31 `scripts/poc/capsule/` namespace), D-14 (`.gitignore` + `.gitleaks.toml` leak defenses + synthetic-kubeconfig fixture).
- `.planning/milestones/v0.19-phases/08-capsule-capsule-proxy-bare-minimum-install/08-CONTEXT.md` — D-08-01 through D-08-13. Especially D-08-02 (capsule + capsule-proxy chart pins; operator `capsule:0.12.4`), D-08-11 (controller-less certgen Job + `capsule-proxy` Secret in `capsule-system` ns), D-08-12 (split-path architectural seam — Phase 13 EDITS spoke-targeted files only), D-08-13 (push-gate inheritance — no Phase 11 carryover for Phase 13; ADR-008 = DEFER stands).
- `.planning/milestones/v0.19-phases/09-tenants-flux-multi-tenancy-lockdown/09-CONTEXT.md` — D-09-01 through D-09-09. Especially D-09-02 (per-tenant SA `gitops-reconciler` in `tenant-<tenant>` ns; multi-owner Tenant CR with SA + User), D-09-03 (transitional kubeConfig pattern — Phase 13 does NOT modify tenant inner Ks beyond what RBAC-06 requires for spec.owners[] additions), D-09-04 (CapsuleConfiguration `forceTenantPrefix: true` + `allowServiceAccountPromotion: true`), D-09-08 (Wave 0 RED bats scaffold — Phase 13 INHERITS).
- `.planning/milestones/v0.19-phases/10-tenant-owner-kubeconfigs-capsule-proxy-round-trip/10-CONTEXT.md` — D-10-01 through D-10-10. Phase 13 INHERITS the existing `issue-tenant-kubeconfig.sh` shape + Phase 10 `<owner>` arg semantic + capsule-proxy LIST filter wiring. Phase 13 EDITS the script to expand `<owner>` enumeration to `human-tenant-owner` (RBAC-02).
- `.planning/milestones/v0.19-phases/11-validation-graduation-adr-008/11-CONTEXT.md` — D-11-01 through D-11-14. Especially D-11-02 (CapsuleConfiguration `userGroups: [capsule.clastix.io, system:serviceaccounts, system:authenticated]` — REQUIRED for capsule-proxy LIST filter to work for SA-token-authenticated identities; Phase 13 inheritance), D-11-07 (Tenant CR D-11-07 live repair — `forceTenantPrefix: false` + Tenant CR sub-directory split; Phase 13 EDITS preserve this), D-11-14 (ADR-008 = DEFER stands — no graduation revisit in v0.20).
- `.planning/milestones/v0.19-phases/12-v019-close-out-reconciliation/12-CONTEXT.md` (if exists) — close-out reconciliation pattern; Phase 15 will mirror at smaller scale.
- `.planning/milestones/v0.19-phases/*/`<NN>-VERIFICATION.md` — verification outcomes per phase. Phase 11 VERIFICATION especially relevant (push-gate VAL-05 closure; one-shot history scan clean; ADR-008 outcome DEFER).

### Architecture Decision Records (load-bearing for Phase 13)

- `docs/adr/0001-single-wsl2-shared-docker-network.md` — k8s-net shared bridge; spoke-capsule reachable from WSL host via `127.0.0.1`.
- `docs/adr/0002-k3d-over-kind.md` — k3d cluster runtime; NodePort publish.
- `docs/adr/0003-flux-over-argocd.md` — Flux 2 as GitOps tool; informational for Phase 13 (Phase 13 EDITS Flux-managed resources but does NOT change Flux topology).
- `docs/adr/0004-hub-only-flux-control-plane.md` — **load-bearing**: NO Flux controllers run on spoke-capsule. Phase 13 verifier MUST re-grep-assert `kubectl --context=k3d-spoke-capsule get pods -n flux-system` returns no flux controllers (regression gate inheritance from Phase 7-11).
- `docs/adr/0005-kubernetes-version-pin.md` — k3s `v1.34.6-k3s1`; TokenRequest API + `--service-account-max-token-expiration` 24h-default clamp behavior verified in Phase 10 Pitfall 10-P2 (this pin does NOT clamp — `--duration` honored exactly).
- `docs/adr/0008-capsule-multi-tenancy-graduation.md` — ADR-008 = **DEFER**. Phase 13 inherits this verbatim; no graduation re-evaluation in v0.20.

### Existing GitOps wiring (load-bearing — Phase 13 EDITS these or relies on them)

- `clusters/hub-flux/flux-system/kustomization.yaml` — KARYON POC MOUNT sentinel location. NOT moved or duplicated in Phase 13.
- `clusters/hub-flux/pocs/capsule.yaml` — hub-targeted Flux Kustomization for `pocs/capsule/` (operator + proxy + tenant inner Ks). Phase 13 does NOT modify.
- `clusters/hub-flux/pocs/capsule-spoke.yaml` — spoke-targeted Flux Kustomization for `pocs/capsule/spoke/` (rbac + config + tenants + NEW global-resources). Reconciles Phase 13's new artifacts. NOT MODIFIED by Phase 13 (already broadly-scoped via `spec.path: ./pocs/capsule/spoke`).
- `clusters/hub-flux/pocs/capsule-spoke-rbac.yaml` — spoke-targeted Flux K for `pocs/capsule/spoke/rbac/` (defense-in-depth ordering — rbac lands BEFORE poc-capsule-spoke applies tenants). Phase 13's new RBAC files (`tenant-workload-editor.yaml`, `platform-owner-sa.yaml`) reconcile through this K. NOT MODIFIED by Phase 13.
- `clusters/hub-flux/pocs/capsule-spoke-tenants.yaml` — spoke-targeted Flux K for `pocs/capsule/spoke/tenant-crs/` (Tenant CRs land before tenant home namespaces dry-run/apply per D-11-07). Phase 13's Tenant CR edits reconcile through this K. NOT MODIFIED by Phase 13.

### Reference implementations (analogs to mirror in Phase 13)

- **`pocs/capsule/spoke/rbac/platform-owner.yaml`** (Phase 11 G-06 / spike `001-capsule-platform-owner-rbac` artifact) — existing `capsule-platform-owner` ClusterRole + ClusterRoleBinding (Group subject). Phase 13 EDITS the CRB `subjects[]` only (additive).
- **`pocs/capsule/spoke/tenant-crs/{alpha,bravo}.yaml`** (Phase 11 D-11-07 repair) — existing Tenant CRs. Phase 13 EDITS `spec.owners[]` ADDITIVELY (D-13-05 + D-13-07).
- **`pocs/capsule/spoke/tenants/{alpha,bravo}/sa.yaml`** (Phase 9 D-09-02) — existing per-tenant `gitops-reconciler` SA. Phase 13 ADDS `human-owner-sa.yaml` as a sibling file.
- **`pocs/capsule/spoke/config/capsuleconfig.yaml`** (Phase 9 D-09-04 + Phase 10 D-11-02 patch) — CapsuleConfiguration `userGroups` includes `system:serviceaccounts` + `system:authenticated`. Phase 13 INHERITS — no edits.
- **`scripts/poc/capsule/issue-tenant-kubeconfig.sh`** (Phase 10 D-10-01..D-10-10) — reference shape for `issue-platform-owner-kubeconfig.sh`. Phase 13 EDITS this script ONLY to expand `<owner>` enumeration; structural shape (TokenRequest, TLS embed, stdout YAML, `--write-to` tmpdir-root check, `--duration`) is preserved verbatim.
- **`scripts/poc/capsule/create-cluster.sh`** (Phase 7 D-05..D-09) — reference for `scripts/poc/capsule/`-rooted scripts (preamble, REPO_ROOT pinning, preflight-lib source, fail-fast pattern).
- **`scripts/lib/preflight-lib.sh`** — output helpers (`section`, `pass`, `warn`, `fail`, `info`, `have`). Phase 13's NEW scripts source this.
- **`tests/bats/test_helper`** — shared bats loader. Phase 13's NEW bats files load without modification.
- **`tests/bats/poc-isolation-01-static.bats`** — Phase 7 P31 regression gate. Phase 13 verifier reruns; new files under `scripts/poc/capsule/` + `pocs/capsule/spoke/` are excluded from v0.18 lint set by location.
- **`tests/bats/proxy-04-live-issue.bats`** — Phase 10 PROXY-01 live test. Phase 13 verifier reruns to confirm `issue-tenant-kubeconfig.sh` EDITS don't regress PROXY-01..03.
- **`tests/bats/capsule-install-09-live-adr-004.bats`** — Phase 8 ADR-004 regression gate. Phase 13 verifier reruns.
- **`tests/bats/tenants-04-static-dependson.bats`** — Phase 9 P32 dependsOn chain regression gate. Phase 13 verifier reruns.
- **`.gitignore` + `.gitleaks.toml`** — Phase 7 D-14 leak defenses cover Phase 13's new kubeconfig output (`platform-owner.kubeconfig` under `${TMPDIR:-/tmp}/karyon-tenants/` — already covered by existing globs). NOT MODIFIED.

### Milestone-level research

- `.planning/research/SUMMARY.md` + `STACK.md` + `ARCHITECTURE.md` + `PITFALLS.md` (if exist for v0.20; else v0.19 versions inherited) — researcher consumes for Plan 13-RESEARCH. v0.19 inheritance: capsule-proxy 0.12.0 + Capsule operator 0.12.4 pins; CRD schema verification pattern (D-09-04 Gap 4..9 corrections to v1beta2 storage version).

### External upstream references (informational; no edits)

- Capsule project — `https://capsule.clastix.io/`.
- Capsule v0.12.x release notes — researcher checks for `GlobalTenantResource` CRD presence + schema.
- Capsule docs — `https://capsule.clastix.io/docs/` — especially "Tenant resources" + "Global tenant resources" sections (if available in v0.12.4 docs).
- capsule-proxy v0.12.0 docs — `https://capsule.clastix.io/docs/proxy/` — LIST filter semantics; researcher verifies cluster-scoped resource passthrough (e.g., Tenant CR LIST through proxy).
- Kubernetes RBAC reference — `https://kubernetes.io/docs/reference/access-authn-authz/rbac/` — for `tenant-workload-editor` ClusterRole shape verification against upstream `edit` ClusterRole baseline.
- Kubernetes TokenRequest — Phase 10 Pitfall 10-P2 inheritance (k3s does NOT clamp `--duration` on this pin).
- nginx Docker Hub — `https://hub.docker.com/_/nginx` — image tag verification; `nginx:alpine` is a multi-arch image (works on amd64 + arm64; Phase 1 host is amd64).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- **`pocs/capsule/spoke/rbac/platform-owner.yaml`** (Phase 11 G-06 / spike artifact) — existing `capsule-platform-owner` ClusterRole grants: get/list/watch on `capsule.clastix.io/*`; create/update/patch/delete on `capsule.clastix.io/tenants`; get/list/watch on `namespaces` + `customresourcedefinitions`. **Phase 13 EDITS the ClusterRoleBinding subjects[] (additive)** — no ClusterRole rule changes. The spike's RBAC grants are sufficient for RBAC-04..06.
- **`pocs/capsule/spoke/tenant-crs/{alpha,bravo}.yaml`** — existing Tenant CRs with multi-owner `spec.owners[]` (Flux SA, gitops-reconciler SA, User). Phase 13 EDITS `spec.owners[]` ADDITIVELY (3 new entries per tenant: Group capsule-platform-owners, SA platform-owner@capsule-system, SA human-tenant-owner@tenant-<name>).
- **`pocs/capsule/spoke/tenants/{alpha,bravo}/sa.yaml`** — existing per-tenant `gitops-reconciler` SA. Phase 13 ADDS `human-owner-sa.yaml` as a sibling file in the same kustomization aggregate.
- **`pocs/capsule/spoke/config/capsuleconfig.yaml`** (Phase 9 D-09-04 + Phase 10/11 D-11-02 patch) — CapsuleConfiguration `userGroups` includes `system:serviceaccounts` + `system:authenticated` — REQUIRED for capsule-proxy LIST filter to work on SA-token identities. Phase 13 INHERITS — no edits.
- **`scripts/poc/capsule/issue-tenant-kubeconfig.sh`** — existing tenant kubeconfig minter. Phase 13 EDITS `<owner>` enumeration (expand from `gitops-reconciler` only to also accept `human-tenant-owner`). Script structure (TokenRequest, TLS embed via tls.crt, stdout YAML, `--write-to` tmpdir-root check, `--duration`) is preserved verbatim. The Phase 10 P7 stderr-redirect pattern (shadowed preflight-lib helpers) carries over to the NEW `issue-platform-owner-kubeconfig.sh` script.
- **`scripts/lib/preflight-lib.sh`** — output helpers Phase 13's NEW scripts source.
- **`tests/bats/test_helper`** — shared bats loader; Phase 13's NEW bats files load without modification.
- **`tests/bats/poc-isolation-01-static.bats`** — Phase 7 P31 regression gate; Phase 13 verifier reruns.
- **`tests/bats/proxy-04-live-issue.bats`** — Phase 10 PROXY-01 live test; Phase 13 verifier reruns to ensure no regression from `issue-tenant-kubeconfig.sh` EDITS.
- **`tests/bats/tenants-04-static-dependson.bats`** — Phase 9 P32 dependsOn chain regression gate; Phase 13 verifier reruns.
- **`tests/bats/capsule-install-09-live-adr-004.bats`** — Phase 8 ADR-004 regression gate; Phase 13 verifier reruns.

### Established Patterns

- **`pocs/capsule/spoke/` GitOps spoke-targeted path** — Phase 8 D-08-12 split-path architectural seam; Phase 13's new artifacts under `pocs/capsule/spoke/{rbac,tenants,tenant-crs,global-resources}` reconcile via existing `poc-capsule-spoke` + `poc-capsule-spoke-rbac` + `poc-capsule-spoke-tenants` outer Flux Ks. No new outer Flux Ks needed.
- **Tenant CR `spec.owners[]` per-entry `clusterRoles: []string`** — Capsule v0.12.4 schema allows mixed implicit-default (no `clusterRoles` field → `[admin, capsule-namespace-deleter]`) + explicit per-entry (`clusterRoles: [tenant-workload-editor]`) in the same array. Phase 13 D-13-05 uses this for the `human-tenant-owner` SA owner entry.
- **`scripts/poc/capsule/`-rooted scripts** — Phase 7 D-12 / P31 isolation contract. Phase 13's new scripts (`issue-platform-owner-kubeconfig.sh`, `new-tenant.sh`) live here. NEVER invoked by `task rebuild`; never referenced from v0.18 scripts.
- **Bash strict-mode + `REPO_ROOT`/`SCRIPT_DIR` pinning** — Phase 13's new scripts adopt identical preamble.
- **`preflight-lib` ergonomics** — section/pass/warn/fail/info/have helpers. Phase 13's new scripts source these. Phase 10 Pitfall 10-P7 shadow-helpers pattern (stdout = YAML; stderr = logs) is reused in `issue-platform-owner-kubeconfig.sh`.
- **TokenRequest token minting** — Phase 10 D-10-01 + Pitfall 10-P2 (`k3s` does NOT clamp `--duration`). Phase 13's `issue-platform-owner-kubeconfig.sh` uses identical TokenRequest invocation against `kubectl --context=k3d-spoke-capsule -n capsule-system create token platform-owner --duration=<d>`.
- **TLS-embed via tls.crt** — Phase 10 D-10-06 + Pitfall 10-P1 (chart's certgen Job outputs `tls.crt` + `tls.key` only; `tls.crt` doubles as CA root). Phase 13's `issue-platform-owner-kubeconfig.sh` reads from the same Secret.
- **Capsule-proxy NodePort 30443 routing** — Phase 8 D-08-04 + Phase 10 D-10-07. Phase 13's platform-owner kubeconfig uses the same uniform endpoint.
- **Wave 0 RED bats scaffold** — Phase 7 / 8 / 9 / 10 / 11 D-09-08 pattern. Phase 13 Plan 13-00 mirrors.
- **POC isolation regression gate** — Phase 7 P31 contract. Phase 13 verifier reruns `tests/bats/poc-isolation-01-static.bats` to confirm new artifacts add ZERO `spoke-capsule` mentions in v0.18 scripts.
- **TmpDir-rooted ephemeral artifacts** — Phase 7 D-14. Phase 13's `--write-to <path>` enforces `${TMPDIR:-/tmp}/karyon-tenants/` prefix verbatim; new `platform-owner.kubeconfig` filename naturally fits under the same root (covered by existing `karyon-tenants/` .gitignore glob).
- **Sentinel-guarded Flux mount surface** — Phase 7 D-02. Phase 13 does NOT modify any sentinel; new artifacts ride existing reconcile loops.
- **Phase 11 D-11-07 Tenant CR splitting (Tenant CRs in `tenant-crs/`, home namespaces + per-tenant SAs in `tenants/<name>/`)** — Phase 13 inherits this layout. New `human-owner-sa.yaml` lands in `tenants/<name>/` alongside existing `sa.yaml`. Tenant CR edits go in `tenant-crs/<name>.yaml`.

### Integration Points

- **`pocs/capsule/spoke/rbac/tenant-workload-editor.yaml`** (NEW) — net-new ClusterRole resource. Reconciles via existing `poc-capsule-spoke-rbac` Flux K (no new K needed; `path: ./pocs/capsule/spoke/rbac` already broadly-scoped).
- **`pocs/capsule/spoke/rbac/platform-owner-sa.yaml`** (NEW) — `platform-owner` SA in `capsule-system` ns. Same Flux K.
- **`pocs/capsule/spoke/rbac/platform-owner.yaml`** (EDITED) — CRB `subjects[]` extended with SA entry (additive only).
- **`pocs/capsule/spoke/rbac/kustomization.yaml`** (EDITED) — `resources:` list grows to include `platform-owner-sa.yaml` + `tenant-workload-editor.yaml`. Ordering: namespace.yaml (existing) → helm-controller-sa.yaml (existing) → platform-owner-sa.yaml (NEW) → platform-owner.yaml (existing, edited) → tenant-workload-editor.yaml (NEW). Bats grep-assert namespace.yaml stays first.
- **`pocs/capsule/spoke/tenants/{alpha,bravo}/human-owner-sa.yaml`** (NEW per tenant) — SA in tenant home namespace. Reconciles via existing `poc-capsule-spoke` Flux K (`path: ./pocs/capsule/spoke`, recursive aggregation through nested kustomization.yaml).
- **`pocs/capsule/spoke/tenants/{alpha,bravo}/kustomization.yaml`** (EDITED) — `resources:` list adds `human-owner-sa.yaml` after existing `namespace.yaml` + `sa.yaml`. Bats grep-assert ordering.
- **`pocs/capsule/spoke/tenant-crs/{alpha,bravo}.yaml`** (EDITED) — `spec.owners[]` additive. Diff against pre-Phase-13 HEAD asserts no removals from the array.
- **`pocs/capsule/spoke/global-resources/`** (NEW DIRECTORY) — `kustomization.yaml` (aggregator) + `hello-world.yaml` (GlobalTenantResource CR + Pod + Service). Phase 13 ADDS `global-resources/` to `pocs/capsule/spoke/kustomization.yaml` resources list AFTER existing `tenants/` (FIFO sortOptions → ensures Tenant CRs + tenant home namespaces exist before global-resources reconcile).
- **`pocs/capsule/spoke/kustomization.yaml`** (EDITED) — `resources: [rbac/, config/, tenants/, global-resources/]`. Phase 11 G-06 already added `rbac/` first; Phase 13 appends `global-resources/`.
- **`scripts/poc/capsule/issue-tenant-kubeconfig.sh`** (EDITED) — `<owner>` enumeration: now accepts `gitops-reconciler` (legacy/Flux) OR `human-tenant-owner` (RBAC-02 default). Fail-fast error message expanded to list both. NO other structural changes.
- **`scripts/poc/capsule/issue-platform-owner-kubeconfig.sh`** (NEW) — net-new script. Sources preflight-lib, gates kubectl/k3d, mints TokenRequest token against `platform-owner` SA in `capsule-system` ns, emits kubeconfig YAML to stdout (or `--write-to` tmpdir-rooted path). Cluster URL = capsule-proxy NodePort `https://127.0.0.1:30443`.
- **`scripts/poc/capsule/new-tenant.sh`** (NEW) — net-new script. Substitutes `<name>` into a Tenant + Namespace + ServiceAccount template, applies via `kubectl --kubeconfig=<platform-owner-kc> apply -f -`. Includes RBAC-05 demo path + SEED-02 fresh-namespace falsifier path.
- **`scripts/poc/capsule/templates/new-tenant.yaml.tmpl`** (NEW; optional per Claude's Discretion — planner may inline as heredoc in `new-tenant.sh`).
- **`Taskfile.yml`** (UNCHANGED) — no new task targets. Phase 13 scripts invoked directly: `bash scripts/poc/capsule/...`.
- **`docs/poc-capsule.md`** (EDITED — Plan 13-04) — append a brief "Platform-owner kubeconfig" subsection (1 paragraph) covering the `issue-platform-owner-kubeconfig.sh` invocation + capsule-proxy NodePort route + cross-link to Phase 14 RUNBOOK-01 act 2 forward-pointer. Phase 14 expands this into the runbook narrative.
- **No `.gitignore` / `.gitleaks.toml` extensions in Phase 13** — Phase 7 D-14 closed the kubeconfig leak surface; existing rules cover Phase 13 output shape verbatim. `platform-owner.kubeconfig` fits under `karyon-tenants/` glob (any file in that tmpdir is git-ignored).

### Risks (carried from STATE.md + Phase 9-11 close-outs)

- **D-13-11 GlobalTenantResource CRD verification** — research uncertainty. Capsule v0.12.4 may have `GlobalTenantResource` OR `TenantResource` (cluster-scoped variant) OR neither. Researcher confirms CRD existence + schema in Plan 13-RESEARCH; if absent, propose alternative (per-tenant TenantResource CRs + a controller / cron / direct apply mechanism). Phase 13 boundary assumes the CRD exists; surface alternative early.
- **D-13-02 nginx image registry-allowlist conflict** — Phase 9 N7 fixture pins alpha + bravo `containerRegistries.allowed: [registry.example.io]`. `nginx:alpine` pulls from `docker.io/library/nginx`. Researcher verifies whether Capsule's webhook rejects the Pod create on tenant namespace; if yes, Plan 13-01 adds `docker.io` to the allowed list (additive, does NOT regress Phase 9 N7 negative-RBAC fixture).
- **Capsule-proxy LIST filter for cluster-scoped resources** — research uncertainty inherited from Phase 10. Phase 13 DEMO-01 expects `kubectl get tenants` (cluster-scoped) through platform-owner kubeconfig to return all tenants. Researcher verifies capsule-proxy's pass-through behavior on cluster-scoped Capsule CRDs.
- **CapsuleConfiguration `userGroups` live-state verification** — Phase 10 Plan 10-02 + Phase 11 D-11-02 patched the live CapsuleConfiguration with `system:serviceaccounts` + `system:authenticated`. Phase 11 G-06 / Plan 11-07 also made the GitOps source canonical. Phase 13 inherits — but the planner should re-verify via `kubectl get capsuleconfiguration default -o yaml` before Plan 13-00 to confirm live state matches Git (no drift).
- **Tenant CR additive edits + Flux reconciliation** — alpha/bravo Tenant CRs are reconciled by the existing `poc-capsule-spoke-tenants` Flux K. Phase 13's additive `spec.owners[]` edits commit to Git; next Flux reconcile applies. Researcher verifies Capsule's admission webhook accepts the new owners (Group + SA mix with explicit clusterRoles on some entries) — should be fine per v0.12.4 schema, but the existing Phase 9 N7 negative-RBAC suite is the regression gate.
- **`task rebuild` SLO regression risk** — Phase 13 adds new YAML + scripts under `pocs/capsule/spoke/` + `scripts/poc/capsule/`. P31 invariant: zero new `spoke-capsule` mentions in v0.18 default-path scripts → static bats `poc-isolation-01-static.bats` regression-gated. `task rebuild` SLO < 230s preserved by the static + the Plan 13-04 verifier's live regression check (gated on KARYON_REBUILD_APPROVED=1 per Phase 11 carryover).
- **ADR-008 = DEFER inheritance** — v0.20 does NOT revisit. Phase 13 does NOT touch the graduation rubric. spoke-capsule stays outside `task rebuild`.

</code_context>

<specifics>
## Specific Ideas

- **Script preamble cite anchors** — `issue-platform-owner-kubeconfig.sh` head comment cites RBAC-04..06 + D-13-06 (SA + dual CRB subject) + D-13-09 (script) + D-13-10 (proxy routing) + P31 isolation + ADR-004 (no Flux on spoke; this script reads from spoke directly). `new-tenant.sh` head cites RBAC-05 + D-13-08 (template) + Phase 9 D-09-04 (Capsule tenant admission webhook constraints).

- **Stdout/stderr contract for new scripts** — `issue-platform-owner-kubeconfig.sh` follows Phase 10 Pitfall 10-P7 exactly: shadow preflight-lib helpers with `>&2` redirects; stdout = pure YAML kubeconfig; stderr = log lines. `new-tenant.sh` does NOT need this (stdout is shell-friendly summary, not machine-consumed YAML); standard preflight-lib helpers are used.

- **TokenRequest audiences claim** — Phase 13's `issue-platform-owner-kubeconfig.sh` uses default audience (apiserver). For capsule-proxy routing, the platform-owner kubeconfig server URL is `:30443` so the proxy receives the request; the proxy verifies the token against apiserver and applies LIST filter. No special audience needed.

- **`--write-to <path>` realpath check** — same Phase 10 D-10-07 pattern (`realpath -m` canonicalize + tmpdir-root prefix check) for `issue-platform-owner-kubeconfig.sh`. Default filename when `--write-to` directory given: `${TMPDIR:-/tmp}/karyon-tenants/platform-owner.kubeconfig`.

- **JWT exp claim verification (live bats)** — `kubectl create token` returns a JWT. Bats decode payload (`echo $TOKEN | cut -d. -f2 | base64 -d 2>/dev/null | jq .exp`) and assert `exp - iat ≈ DURATION` (per Phase 10 D-10-09 live coverage). Same approach for platform-owner kubeconfig.

- **`kubectl auth can-i` matrix coverage** — RBAC-01 (tenant-workload-editor) positive grants exhaustive enumeration:
  ```
  pods: get/list/watch/create/update/patch/delete                     # positive
  pods/log: get                                                       # positive
  pods/exec: create                                                   # positive
  pods/portforward: create                                            # positive
  deployments / replicasets / statefulsets / daemonsets: GLW + CUPDc  # positive
  jobs / cronjobs: GLW + CUPDc                                        # positive
  services / endpoints / endpointslices: GLW + CUPDc                  # positive
  configmaps: GLW + CUPDc                                             # positive
  persistentvolumeclaims: get/list/watch                              # read-only positive
  events: get/list/watch                                              # positive
  secrets: get/list/watch                                             # read-only positive (D-13-01)
  -----
  secrets: create/update/patch/delete                                 # DENIAL (4 verbs)
  rolebindings: any verb                                              # DENIAL
  roles: any verb                                                     # DENIAL
  resourcequotas: any verb                                            # DENIAL
  limitranges: any verb                                               # DENIAL
  -----
  nodes / csr / clusterrolebinding / clusterrole: any verb            # implicit denial
  tenants.capsule.clastix.io: any verb                                # implicit denial
  customresourcedefinitions: any verb                                 # implicit denial
  networkpolicies.networking.k8s.io: write verbs                      # implicit denial
  ```
  Bats can-i iterates this matrix. Use `--as=system:serviceaccount:tenant-alpha:human-tenant-owner` for the kubeconfig-less form, OR `--kubeconfig=<minted>` for the minted-kubeconfig form. Both forms produce the same Yes/No matrix.

- **Platform-owner `kubectl auth can-i` matrix** — RBAC-04 + RBAC-06 coverage:
  ```
  tenants.capsule.clastix.io: get/list/watch/create/update/patch/delete    # positive
  namespaces: get/list/watch                                                # positive (broad LIST)
  customresourcedefinitions: get/list/watch                                 # positive
  capsule.clastix.io/*: get/list/watch                                      # positive
  -----
  '*' '*': returns "no"                                                     # RBAC-04 ceiling
  nodes: any verb                                                           # DENIAL
  csr: any verb                                                             # DENIAL
  clusterrolebinding: create/update/patch/delete                            # DENIAL
  clusterrole: create/update/patch/delete                                   # DENIAL
  pods: any verb (cluster-scoped — without tenant impersonation)            # DENIAL (cluster-scoped query)
  pods -n tenant-alpha (namespace-scoped): get/list/watch + exec + log      # positive via Tenant CR co-ownership (RBAC-06)
  ```
  The cluster-scoped vs namespace-scoped `kubectl auth can-i pods` distinction is key. Bats runs both: `kubectl auth can-i list pods --all-namespaces` (Forbidden — no cluster-scoped pods grant) vs `kubectl auth can-i list pods -n tenant-alpha` (Yes — Capsule-injected RoleBinding from Tenant owner entry per RBAC-06).

- **Capsule's auto-injected RoleBindings on Tenant owners** — Capsule's controller injects RoleBindings (kind: RoleBinding, namespace: tenant home + tenant child namespaces) for each Tenant owner entry. Default `clusterRoles: [admin, capsule-namespace-deleter]` → 2 RoleBindings per owner per tenant ns. For the human-tenant-owner SA with explicit `clusterRoles: [tenant-workload-editor]` → 1 RoleBinding per tenant ns. Bats can-i live test exercises these injected bindings.

- **`new-tenant.sh` regex validation for `<name>`** — `^[a-z][a-z0-9-]{1,30}$` (DNS-label-safe lowercase + hyphens). Fail-fast: `Tenant name '<name>' must match DNS label conventions (lowercase, start with letter, ≤ 31 chars). Hint: try 'phase13-fresh' for the SEED-02 test.`

- **GlobalTenantResource embedded resource shape** — Capsule v0.12.x docs reference (researcher verifies):
  ```yaml
  apiVersion: capsule.clastix.io/v1beta2     # OR v1beta1 — researcher confirms
  kind: GlobalTenantResource
  metadata:
    name: hello-world-seeded
  spec:
    tenantSelector:
      matchLabels: {}                         # match-all
    resyncPeriod: 60s                         # researcher confirms exact field name
    pruningOnDelete: true                     # researcher confirms exact field name
    resources:
      - namespacedItems:
          - apiVersion: v1
            kind: Pod
            metadata:
              name: hello-world
              labels:
                app: hello-world
                karyon.io/managed-by: capsule-global-tenant-resource
            spec:
              containers: [...]
          - apiVersion: v1
            kind: Service
            metadata:
              name: hello-world
              labels: {...}
            spec: {...}
  ```
  Field shapes (`namespacedItems`, `rawItems`, `resourceSelectors`) are placeholders pending researcher confirmation.

- **Plan 13-04 verifier docs snippet** — append to `docs/poc-capsule.md` (1 paragraph):
  ```markdown
  ## Platform-owner kubeconfig (v0.20 Phase 13)

  The platform-owner identity (`capsule-platform-owners` Group + `platform-owner` SA in
  `capsule-system`) is bound to the `capsule-platform-owner` ClusterRole. Mint a
  TokenRequest-backed kubeconfig with:

      bash scripts/poc/capsule/issue-platform-owner-kubeconfig.sh 2>/dev/null > /tmp/po.kc

  The minted kubeconfig routes through capsule-proxy NodePort 30443. Use it to LIST
  tenants (`kubectl --kubeconfig=/tmp/po.kc get tenants`), provision new tenants
  (`bash scripts/poc/capsule/new-tenant.sh phase13-fresh --kubeconfig /tmp/po.kc`),
  and exercise co-owner LIST/EXEC across tenant namespaces. The platform-owner does
  NOT have cluster-admin; `kubectl auth can-i '*' '*'` returns "no". See Phase 14
  `docs/poc-capsule-demo.md` runbook act 2 for the full demo narrative.
  ```

- **Bats fixture for fresh-tenant SEED-02** — use throwaway tenant name `phase13-fresh` (distinct from Phase 14 OQ-5 marquee name). Teardown deletes the tenant + asserts Capsule unmaterializes cleanly. SEED-02 latency assertion: `kubectl wait pod/hello-world --for=condition=Ready -n tenant-phase13-fresh --timeout=60s` (the wait timeout IS the SEED-02 ≤60s contract).

- **Plan 13-04 verifier output** — `13-VERIFICATION.md` mirrors Phase 7-11 close-out shape. Must-have checklist (12 REQs):
  - RBAC-01..06 ✓
  - SEED-01..03 ✓
  - DELIVERY-01..03 ✓
  Each item references the bats file + commit SHA + live observation.

</specifics>

<deferred>
## Deferred Ideas

- **DEMO-01..06 + RUNBOOK-01..05** → Phase 14. Phase 13 ships artifacts only; Phase 14 verifies the two-perspective demo + writes the 6-act runbook.
- **OQ-1 (TLS noise treatment)** → Phase 14 (RUNBOOK-03).
- **OQ-5 (new-tenant marquee name + provision-live vs pre-staged dance)** → Phase 14. Phase 13's RBAC-05 test uses throwaway `phase13-fresh`.
- **REQUIREMENTS.md `[ ]` → `[x]` flips against live evidence + retrospective + `/gsd-audit-milestone v0.20`** → Phase 15 close-out + retrospective.
- **`task seed-capsule-demo` Taskfile entry** — REJECTED per D-13-03 OQ-4 resolution. Future enhancement only if Phase 14 finds GitOps reconcile latency to be a demo-killer (highly unlikely; `flux reconcile kustomization poc-capsule-spoke --with-source` is fast).
- **`task issue-platform-owner-kubeconfig` wrapper** — none. Continues "no task surface extensions" default from Phase 7/8/9/10/11. If a future phase needs `task` ergonomics, wrapper is trivial.
- **`task new-tenant` wrapper** — none. Same.
- **JSON output mode for new scripts** — none. Mirrors Phase 10 D-10-09 default. Future enhancement if a machine-consumer needs structured output.
- **`additionalRoleBindings` Tenant CR field** for the human-tenant-owner SA → tenant-workload-editor mapping — REJECTED in favor of per-entry `clusterRoles: []` field on owner entry (D-13-05). Cleaner; tracks ownership semantics; tested in v0.19 Phase 9. Planner may swap if research surfaces a strong reason.
- **OIDC-based platform-owner identity** — out of v0.20 scope (PROJECT.md / REQUIREMENTS.md Out of Scope: OIDC). v0.20 uses SA TokenRequest + impersonation. Future milestone considers OIDC issuer (Dex / Keycloak / Auth0) + IdP group mapping.
- **Production ingress + cert-manager + real TLS for capsule-proxy** — out of v0.20 scope (REQUIREMENTS.md Out of Scope).
- **`tenant-workload-editor` ClusterRole aggregation labels** — none added. The role is named, not auto-aggregated into `system:aggregate-to-edit`. This avoids surprise inheritance from upstream label-selector aggregation.
- **`tenant-workload-editor` for cluster-scoped resources** — none granted. Tenant developers cannot create or modify cluster-scoped resources (Tier-3 boundary).
- **Per-tenant network isolation** — out of scope. v0.20 does NOT add NetworkPolicy enforcement (Phase 9 Tenant CR `networkPolicies` field is empty; deferred to a future milestone).
- **Multi-developer SAs per tenant** — out of scope. Phase 13 ships ONE `human-tenant-owner` SA per tenant. If a future phase introduces per-developer SAs (one SA per teammate), the Tenant CR `spec.owners[]` array grows; the existing `tenant-workload-editor` ClusterRole covers all of them.
- **Capsule operator chart upgrade** — out of scope. Phase 13 stays on `capsule:0.12.4` (Phase 8 D-08-02 pin). Upgrade is a future milestone concern.
- **`spoke-capsule` ↔ `task rebuild` graduation** — out of scope per ADR-008 = DEFER inheritance.
- **G-04 architectural decision / split-Kustomization refactor** — Plan 11-07 D-11-01 PostBuild workaround stays (deferred from v0.19 close-out; future-milestone concern per STATE.md "Carry-forward parking lot").
- **Hub-side Capsule install + `capsule-addon-fluxcd` Trial** — deferred from v0.19 (ADDON-01/02); not in v0.20 scope.
- **Real secret management (Vault / SOPS / age)** — v0.18 follow-up; deferred to a future milestone.
- **Phase 1-5 shellcheck warning cleanup (SC2034 / SC2155)** — v0.18 follow-up; deferred.
- **Pre-existing markdownlint failures** — v0.19 carryover; deferred.
- **Pre-existing gitleaks finding in `proxy-06` fixture (allowlisted)** — v0.19 carryover; deferred.

### Reviewed Todos (not folded)

No todos were reviewed — `gsd-sdk query todo.match-phase 13` returned `todo_count: 0`. The two v0.19-era pending todos (`2026-04-29-phase-7-gitleaks-planning-doc-allowlist.md` resolves_phase: 11; `2026-04-29-phase-7-hub-flux-observable-reconcile.md` resolves_phase: 8) were CLOSED during Phase 11 + Phase 12 close-out per STATE.md "Accumulated Context — Pending Todos" notes (see entries marked RESOLVED 2026-05-07 / 2026-05-11).

### Out-of-band ideas surfaced during analysis (NOT in current scope)

- None — analysis stayed within Phase 13 scope. The OQ-1 / OQ-5 / DEMO / RUNBOOK / Phase 15 close-out items are deliberate ROADMAP-literal phase boundaries (Phase 13 owns RBAC + SEED + DELIVERY only).

</deferred>

---

*Phase: 13-rbac-narrowing-globaltenantresource-seed-delivery-mechanism*
*Context gathered: 2026-05-19*
*Mode: `--auto` (Claude auto-selected all gray areas and picked recommended defaults — see 13-DISCUSSION-LOG.md for the audit trail)*
