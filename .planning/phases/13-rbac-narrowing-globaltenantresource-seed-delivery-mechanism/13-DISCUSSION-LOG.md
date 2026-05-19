# Phase 13: RBAC Narrowing + GlobalTenantResource Seed + Delivery Mechanism - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-19
**Phase:** 13-rbac-narrowing-globaltenantresource-seed-delivery-mechanism
**Mode:** `--auto` (Claude picked recommended defaults; no interactive prompts)
**Areas discussed:** OQ-2 Secrets policy, OQ-3 Workload shape, OQ-4 Delivery path, Tenant-workload-editor binding mechanism, Platform-owner identity shape, Platform-owner Tenant CR co-ownership, Platform-owner kubeconfig routing, GlobalTenantResource shape, Wave 0 RED bats coverage, Plan ordering

---

## OQ-2 — `tenant-workload-editor` Secrets policy (REQ: RBAC-01)

Source: PROJECT.md open questions (carry-forward); resolved in Phase 13 discuss-phase.

| Option | Description | Selected |
|--------|-------------|----------|
| Read-only (get/list/watch only) | Tenant developers can read pre-staged TLS secrets / mounted configs but cannot create, edit, or delete Secrets. Aligns with PROJECT.md "(Recommended)". Demo-distinct (RBAC-01 boundary visible via Forbidden on `kubectl create secret`). | ✓ |
| No-access-at-all | No verbs on Secrets. Strictest posture; tenant developers can't even read TLS secrets they need for ingress. Demo-distinct but operationally restrictive. | |
| Upstream-`edit`-equivalent (full read+write) | Mirrors k8s `edit` ClusterRole Secret CRUD. Less demo-distinct from `admin` (the "tenant-workload-editor is narrower than edit" boundary becomes purely structural — no live Forbidden on Secret create). | |

**Selection:** Read-only (recommended default per PROJECT.md OQ list).
**Auto-mode log:** `[auto] OQ-2 — Q: "tenant-workload-editor Secrets policy?" → Selected: "Read-only (get/list/watch; no create/update/patch/delete)" (recommended default)`
**Notes:** DEMO-04 contract requires tenant-owner Forbidden on `kubectl create secret`; read-only satisfies this directly without breaking common positive-control workflows (pull-mounted-secret). Captured as D-13-01 in CONTEXT.md.

---

## OQ-3 — Hello-world workload shape (REQ: SEED-03)

Source: PROJECT.md open questions; resolved in Phase 13.

| Option | Description | Selected |
|--------|-------------|----------|
| Pod + Service | Smallest visually-meaningful shape: tenant-owner can `kubectl get pods` / `logs` / `exec`; Service shows up under `kubectl get svc`. Recommended per PROJECT.md "(Recommended; lightweight, visual)". | ✓ |
| ConfigMap-only | Fastest, no running workload. No live Pod to LIST/EXEC against in the runbook narrative. | |
| Deployment + Service + ConfigMap | Heavier. Adds replica-count noise without adding demo value. Pulls in Deployment churn (rolling updates, etc.) that the audience doesn't need to see. | |

**Selection:** Pod + Service (recommended default per PROJECT.md OQ list).
**Auto-mode log:** `[auto] OQ-3 — Q: "Hello-world workload shape?" → Selected: "Pod + Service" (recommended; lightweight, visual)`
**Notes:** Image choice `nginx:alpine` carries a Phase 9 N7 registry-allowlist caveat (alpha/bravo Tenant CRs pin `containerRegistries.allowed: [registry.example.io]`). Researcher verifies during Plan 13-RESEARCH; if `docker.io` is blocked, Plan 13-01 adds it to the allowed list additively (does not regress N7 negative-RBAC fixture). Captured as D-13-02 in CONTEXT.md.

---

## OQ-4 — Delivery path (REQ: DELIVERY-01)

Source: PROJECT.md open questions; resolved in Phase 13.

| Option | Description | Selected |
|--------|-------------|----------|
| GitOps under `pocs/capsule/` | All new artifacts (ClusterRole, GlobalTenantResource, hello-world, platform-owner SA + CRB, per-tenant human-owner SA, Tenant CR edits) land in `pocs/capsule/spoke/` and reconcile via existing `poc-capsule-spoke` + `poc-capsule-spoke-rbac` + `poc-capsule-spoke-tenants` outer Flux Kustomizations. NO Taskfile churn. Production-correct. Aligns with existing KARYON POC MOUNT sentinel + Phase 7 D-12 P31 isolation. | ✓ |
| `task seed-capsule-demo` Taskfile entry | Direct-apply mechanism. Faster (no Flux reconcile cycle) but adds a non-GitOps surface. Needs P31 isolation whitelist update for `tests/bats/poc-isolation-01-static.bats`. Doesn't translate to EKS. Adds a 3rd POC entry point (we already have `task fix-dns-poc-capsule`, `task fail-capsule-webhook`, `task destroy-poc`). | |

**Selection:** GitOps under `pocs/capsule/` (planner-side recommended default; aligns with existing GitOps culture, P31 isolation contract, and future-EKS-translation posture).
**Auto-mode log:** `[auto] OQ-4 — Q: "Delivery path?" → Selected: "GitOps under pocs/capsule/" (production-correct; aligns with existing KARYON POC MOUNT + Phase 7 D-12 P31 isolation)`
**Notes:** Concern about Flux reconcile latency for demo prep is real but small. Force-reconcile via `flux reconcile kustomization poc-capsule-spoke --with-source` is fast. Phase 14 RUNBOOK-02 pre-demo checklist will include the force-reconcile if needed. Captured as D-13-03 in CONTEXT.md.

---

## Tenant-workload-editor binding mechanism (REQs: RBAC-01, RBAC-02, RBAC-03)

| Option | Description | Selected |
|--------|-------------|----------|
| Per-tenant `human-tenant-owner` SA in `spec.owners[]` with explicit `clusterRoles: [tenant-workload-editor]` | Adds a new SA owner entry per Tenant CR. Capsule's per-entry `clusterRoles` field overrides the default `[admin, capsule-namespace-deleter]` for that specific owner. Existing `gitops-reconciler` SA + admin pattern preserved verbatim (RBAC-03). Clean separation: Flux SA = admin (automation); human SA = tenant-workload-editor (human). | ✓ |
| Modify existing `gitops-reconciler` SA owner entry to `clusterRoles: [tenant-workload-editor]` | Breaks RBAC-03 (Flux SA owner pattern preservation). Flux reconciliation would lose `admin` privileges and likely break Tenant inner Kustomization reconcile. Rejected. | |
| Use `spec.additionalRoleBindings[]` on Tenant CR | Bypasses owner-aware capsule-proxy LIST filter. Tenant-workload-editor RoleBinding lives outside Capsule's owner machinery, so capsule-proxy won't recognize the human SA as a tenant owner for LIST filter purposes. Rejected as the idiomatic Capsule v0.12.4 path. | |
| Use `kubectl create rolebinding` imperatively (no Tenant CR mutation) | Drift-prone (lives outside GitOps). Rejected; conflicts with D-13-03 GitOps default. | |

**Selection:** Per-tenant `human-tenant-owner` SA in Tenant CR `spec.owners[]` with explicit `clusterRoles: [tenant-workload-editor]`.
**Auto-mode log:** `[auto] Tenant-workload-editor binding mechanism → Selected: "Per-tenant human-tenant-owner SA in spec.owners[] with explicit clusterRoles:[tenant-workload-editor]" (preserves RBAC-03 Flux SA + admin pattern; engages capsule-proxy LIST filter via owner machinery)`
**Notes:** SA name `human-tenant-owner` (planner may shorten — see Claude's Discretion in CONTEXT.md). Captured as D-13-05 in CONTEXT.md.

---

## Platform-owner identity shape (REQs: RBAC-04, RBAC-05, RBAC-06)

| Option | Description | Selected |
|--------|-------------|----------|
| New SA `platform-owner` in `capsule-system` ns + extend existing CRB subjects[] | Adds an SA as a second subject on the existing `capsule-platform-owner` ClusterRoleBinding (alongside `Group: capsule-platform-owners` from the spike). Both impersonation (`--as=...`) and TokenRequest-backed kubeconfig paths work. CRB rule set unchanged. | ✓ |
| Group-only via impersonation (no SA) | The spike pattern — `kubectl --as=capsule-platform-owner --as-group=capsule-platform-owners`. Works for one-off demo, but not a "kubeconfig persona" — every demo invocation needs `--as` flags. Less ergonomic than a minted kubeconfig. | |
| Separate ClusterRoleBinding for SA (instead of extending existing) | Adds a second CRB referring to the same ClusterRole. Functionally equivalent but creates RBAC noise (two CRBs to keep in sync). Rejected for cleanliness. | |
| Bind ClusterRole directly to the human user via `--user=alice` | No persistent identity; depends on apiserver flag config. Rejected. | |

**Selection:** SA `platform-owner` in `capsule-system` + extended existing CRB subjects[] (dual-subject).
**Auto-mode log:** `[auto] Platform-owner identity → Selected: "SA platform-owner in capsule-system ns + extended existing CRB subjects (Group + SA dual)" (preserves spike impersonation path; adds SA TokenRequest path for v0.20 kubeconfig)`
**Notes:** Captured as D-13-06 in CONTEXT.md.

---

## Platform-owner Tenant CR co-ownership (REQ: RBAC-06)

| Option | Description | Selected |
|--------|-------------|----------|
| Both Group + SA in `spec.owners[]` | Group entry preserves impersonation path semantics; SA entry is what capsule-proxy LIST filter actually matches on (proxy filters by SA-token-authenticated identity's tenant ownership). Both load-bearing. Capsule's default `clusterRoles: [admin, capsule-namespace-deleter]` for both entries — broader than tenant-workload-editor (RBAC-06 wants platform-team to debug across tenants) but bounded inside tenant namespaces. | ✓ |
| Group only | Capsule-proxy LIST filter does NOT recognize Group-based identity (filter operates on SA-token-authenticated subject's tenant ownership). Without SA entry, platform-owner kubeconfig LIST would not return tenant namespaces. Demo fails. Rejected. | |
| SA only | Drops the impersonation path. Existing spike example invocation (`--as=capsule-platform-owner --as-group=capsule-platform-owners`) stops working. Backward-compat regression. Rejected. | |
| User entry (no Group, no SA) | Pre-CRB pattern; doesn't align with the existing ClusterRoleBinding subjects[] shape. Rejected. | |

**Selection:** Both Group AND SA in `spec.owners[]` (dual entries).
**Auto-mode log:** `[auto] Platform-owner Tenant CR co-ownership → Selected: "Both Group capsule-platform-owners AND SA system:serviceaccount:capsule-system:platform-owner added to spec.owners[]" (SA entry engages capsule-proxy LIST filter; Group entry preserves impersonation path)`
**Notes:** Existing alpha/bravo `spec.owners[]` entries (flux-reconciler SA, gitops-reconciler SA, User) preserved verbatim. Additive only. Captured as D-13-07 in CONTEXT.md.

---

## Platform-owner kubeconfig routing (REQs: RBAC-04, RBAC-06, DEMO-01, DEMO-06)

| Option | Description | Selected |
|--------|-------------|----------|
| Through capsule-proxy NodePort 30443 | Uniform with tenant kubeconfigs (Phase 10 pattern). Capsule-proxy applies LIST filter on SA-token-authenticated identity's tenant ownership → returns only the alpha + bravo namespaces the platform-owner co-owns (NOT kube-system, flux-system, capsule-system). Forbidden actions (RBAC-04 `auth can-i '*' '*'`) work via either the proxy passthrough or direct apiserver. Same uniform proxy path keeps demo simple. | ✓ |
| Direct apiserver `:6446` | LIST namespaces returns ALL namespaces (kube-system, flux-system, etc.) — undermines "platform-owner is bounded" framing. RBAC-04 + RBAC-06 contracts diverge from DEMO-01 expectation. Rejected. | |
| Hybrid: minted kubeconfig with two contexts (one proxy, one direct) | Adds operator decision-fatigue (which context to use for which kubectl). Demo narrative gets confused. Rejected. | |

**Selection:** Through capsule-proxy NodePort 30443.
**Auto-mode log:** `[auto] Platform-owner kubeconfig routing → Selected: "Through capsule-proxy NodePort 30443" (uniform proxy path with tenant kubeconfigs; co-owner LIST filter applies for namespace visibility per RBAC-06/DEMO-01)`
**Notes:** Tenant CR LIST is cluster-scoped — researcher verifies capsule-proxy's pass-through behavior on cluster-scoped Capsule CRDs in Plan 13-RESEARCH. Captured as D-13-10 in CONTEXT.md.

---

## GlobalTenantResource shape (REQs: SEED-01, SEED-02, SEED-03)

| Option | Description | Selected |
|--------|-------------|----------|
| Match-all tenant selector + embedded Pod + Service per OQ-3 | Selects ALL tenants via `tenantSelector: matchLabels: {}` (or equivalent). Embedded resource list is the Pod + Service per D-13-02. resyncPeriod ≤ 60s (researcher confirms exact field). pruningOnDelete: true. Researcher verifies CRD name + apiVersion against v0.12.4 schema. | ✓ |
| Label-selector tenant selector (e.g., `karyon.io/poc: capsule`) | More restrictive but adds a per-tenant label dependency. Alpha/bravo Tenant CRs do NOT currently carry this label. Would require an additive label-write to existing Tenant CRs. Rejected as unnecessarily complicated for "every tenant" semantics. | |
| Per-tenant TenantResource CRs (cluster-scoped variant absent) | Fallback option if researcher determines GlobalTenantResource doesn't exist in v0.12.4. One TenantResource CR per tenant — works but operationally heavier (N CRs instead of 1). Held in reserve. | |
| Manual propagation script (no CRD) | Drift-prone (lives outside the Capsule controller's reconcile loop). Rejected. | |

**Selection:** Match-all selector + embedded Pod + Service.
**Auto-mode log:** `[auto] GlobalTenantResource shape → Selected: "Match-all tenant selector; embed Pod + Service per D-13-02; researcher verifies CRD name/apiVersion in v0.12.4"`
**Notes:** Capsule v0.12.4 schema verification is research-uncertain. If GlobalTenantResource is absent, fall back to per-tenant TenantResource CRs (one per tenant). Captured as D-13-11 + D-13-12 in CONTEXT.md.

---

## Wave 0 RED bats coverage (REQs: ALL — Nyquist gate)

| Option | Description | Selected |
|--------|-------------|----------|
| Mirror Phase 7/8/9/10/11 D-09-08 pattern (Plan 13-00 lands all bats RED before any artifact) | Already-validated pattern across 5 prior phases. Static contracts (file shapes, grep-asserts) + live observation (gated on cluster-info probe). Each REQ (RBAC-01..06, SEED-01..03, DELIVERY-01..03) gets at least one bats file. | ✓ |
| Bats-after-implementation (implement-then-test) | Anti-pattern per Phase 6 Nyquist gate establishment. Risk: tests retrofitted to implementation; falsifier shape diverges from REQ contract. Rejected. | |
| Skip Wave 0 RED phase; merge into Plan 13-01..04 | Loses the "scaffold first" discipline. Rejected. | |

**Selection:** Mirror Phase 7/8/9/10/11 D-09-08 pattern.
**Auto-mode log:** `[auto] Wave 0 RED bats coverage → Selected: "Mirror Phase 7/8/9/10/11 D-09-08 pattern — Plan 13-00 RED scaffold before any artifact"`
**Notes:** Bats file partition (per-area files vs per-REQ files) is planner discretion. Recommended: `rbac-NN-{static|live}-<topic>.bats`, `seed-NN-{static|live}-<topic>.bats`, `delivery-NN-{static|live}-<topic>.bats`. Captured as D-13-15 in CONTEXT.md.

---

## Plan ordering (REQ: process)

| Option | Description | Selected |
|--------|-------------|----------|
| 5-plan structure (13-00 Wave 0 → 13-01 ClusterRole + human-owner SAs + Tenant CR human-owner additions → 13-02 platform-owner SA + CRB extension + new-tenant.sh + Tenant CR platform-owner additions → 13-03 GlobalTenantResource + hello-world → 13-04 verifier) | Mirrors v0.19 Phase 10 (3-plan) + Phase 11 (8-plan, larger) close-out patterns; partitions RBAC bundle by identity (tenant vs platform-owner). Verifier as separate plan keeps reruns of Phase 7+8+9+10+11 inheritance focused. | ✓ |
| 4-plan structure (merge 13-01 + 13-02 into single RBAC bundle) | Faster path; both plans touch RBAC YAML + scripts. Reasonable alternative; planner may merge if Wave 0 bats partition aligns. | (planner option) |
| 6-plan structure (split 13-03 into CR + workload manifest plans) | Over-decomposed; both files are interdependent (GlobalTenantResource embeds the workload). Rejected as default; planner may use if a research-uncertain CRD shape forces incremental landing. | |
| 3-plan structure (Wave 0 + bundle + verifier) | Under-decomposed; bundle plan touches 8+ files in one commit. Less reviewable. Rejected. | |

**Selection:** 5-plan structure (planner may merge 13-01 + 13-02 if Wave 0 bats partition allows).
**Auto-mode log:** `[auto] Plan ordering → Selected: "5-plan structure (13-00 Wave 0 → 13-01 ClusterRole+human-owner SAs → 13-02 platform-owner+CRB+co-ownership+new-tenant → 13-03 GlobalTenantResource+helloworld → 13-04 verifier); planner may merge/split"`
**Notes:** Plan 13-04 verifier writes `13-VERIFICATION.md` mirroring v0.19 Phase 10-12 close-out shape; reruns all Phase 7-11 inheritance bats. Captured as D-13-16 in CONTEXT.md.

---

## Claude's Discretion

Areas Claude has flexibility on (no user input required — planner/researcher defaults apply, documented in CONTEXT.md):

- SA name `human-tenant-owner` vs alternatives (planner may shorten to `tenant-owner` or `tenant-human-owner`).
- New-tenant template path (file at `scripts/poc/capsule/templates/new-tenant.yaml.tmpl` vs inline heredoc in `new-tenant.sh`).
- GlobalTenantResource subdir name (`global-resources/` vs `seeded-resources/` vs inline; recommended separate subdir).
- Reconcile loop noise tolerance (≤ 3 attempts × 30s sleep — Phase 8/9/10 pattern).
- Bats file naming (`rbac-NN-{static|live}-<topic>.bats` etc.).
- Test fixture for fresh-namespace SEED-02 — throwaway tenant name (e.g., `phase13-fresh`); kept distinct from OQ-5 Phase 14 marquee name.
- TokenRequest duration default (1h per Phase 10 D-10-02 — mirrors).
- No `task` surface extensions — continues Phase 7/8/9/10/11 "no new task targets" default.
- Capsule v0.12.4 GlobalTenantResource schema verification (researcher confirms CRD name + apiVersion + fields).
- Hello-world image source (`nginx:alpine` per D-13-02 + caveat; planner reshapes per registry-allowlist resolution).

---

## Deferred Ideas

- **DEMO-01..06 + RUNBOOK-01..05** → Phase 14.
- **OQ-1 (TLS noise treatment)** → Phase 14 (RUNBOOK-03).
- **OQ-5 (new-tenant marquee name + provision-live vs pre-staged dance)** → Phase 14. Phase 13 uses throwaway `phase13-fresh`.
- **REQ checkbox flips against live evidence + retrospective** → Phase 15 close-out.
- **`task seed-capsule-demo` Taskfile entry** — REJECTED per OQ-4 D-13-03. Future enhancement only if Phase 14 finds GitOps reconcile latency unworkable.
- **`task issue-platform-owner-kubeconfig` / `task new-tenant` wrappers** — none (continues "no task surface extensions" default).
- **JSON output mode for new scripts** — none (mirrors Phase 10 D-10-09 default).
- **`additionalRoleBindings` Tenant CR field** for the human-tenant-owner SA → tenant-workload-editor mapping — REJECTED in favor of per-entry `clusterRoles: []` field on owner entry.
- **OIDC-based platform-owner identity** — out of v0.20 scope.
- **Production ingress + cert-manager + real TLS for capsule-proxy** — out of v0.20 scope.
- **`tenant-workload-editor` ClusterRole aggregation labels** — none added (no auto-aggregation into `system:aggregate-to-edit`).
- **Per-tenant network isolation (NetworkPolicy)** — out of scope.
- **Multi-developer SAs per tenant** — out of scope.
- **Capsule operator chart upgrade** — out of scope.
- **`spoke-capsule` ↔ `task rebuild` graduation** — out of scope (ADR-008 = DEFER stands).
- **G-04 architectural decision / split-Kustomization refactor** — v0.19 carryover; future-milestone concern.
- **Hub-side Capsule install + `capsule-addon-fluxcd` Trial** — v0.19 deferred (ADDON-01/02).
- **Real secret management (Vault / SOPS / age)** — v0.18 follow-up; deferred.
- **Phase 1-5 shellcheck warning cleanup** — v0.18 follow-up; deferred.
- **Pre-existing markdownlint failures** — v0.19 carryover; deferred.
- **Pre-existing gitleaks finding in `proxy-06` fixture** — v0.19 carryover; deferred.

---

*See `13-CONTEXT.md` for the final captured decisions consumed by gsd-phase-researcher + gsd-planner.*
