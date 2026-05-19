# Requirements: karyon — Milestone v0.20 (Capsule POC Demo & RBAC Polish)

**Defined:** 2026-05-19
**Core Value:** `task rebuild` performs a scorched-earth teardown and reaches a healthy hub-spoke Flux lab — with a CUDA-capable spoke — in under 20 minutes, every time.
**Milestone Goal:** Take the v0.19 Capsule POC from "shipped + technically correct" to **"demo-ready and least-privilege-aligned"** — land the artifacts + runbook needed to walk a Mixed Eng + Cloud Ops team through the platform-owner / tenant-owner / capsule-proxy story end-to-end, with a strict no-admin posture for every human-exercised role.

**Phase numbering:** v0.19 ended at Phase 12. v0.20 starts at **Phase 13** and ships in a lean **2 phases + close-out** (planner may collapse but MUST NOT add a 4th phase).

**Framing:** Lean / additive milestone. Smallest viable phase count to ship the demo ASAP. Existing alpha/bravo Tenant CRs + existing Flux reconciliation stay untouched; this milestone is **purely additive**. Anti-scope guard active — "while we're at it" additions get rejected unless directly load-bearing for R1–R5.

**Inheritance from v0.18 + v0.19 (regression gates — must not break):**

- All v0.18 ADR invariants preserved (most importantly **ADR-004 hub-only Flux**: no Flux controllers run on `spoke-capsule`).
- All v0.18 + v0.19 validated requirements remain VALIDATED — `task rebuild` SLO < 230s and the public-repo secrets contract are explicit regression gates.
- v0.18 P18 invariant: every `spec.kubeConfig.secretRef` block uses `key: value.yaml`.
- v0.19 ADR-008 = **DEFER** stands; v0.20 does NOT revisit graduation rubric (D-11-14).

**Load-bearing invariants inherited into v0.20 (every plan must respect):**

- **P27** — every tenant Flux Kustomization MUST set `spec.serviceAccountName` explicitly. Without it, tenants bypass Capsule entirely.
- **P29** — tenant kubeconfigs MUST NOT land in git. `.gitleaks.toml` kubeconfig-bearer-token rule + `.gitignore` globs intact.
- **P31** — `spoke-capsule` MUST NOT enter `task rebuild`. All POC concerns under `scripts/poc/capsule/` namespace; static bats greps `scripts/` (excluding `scripts/poc/`) for `spoke-capsule` and asserts ZERO mentions. v0.20 delivery mechanism (DELIVERY-01) MUST NOT regress this contract.
- **KARYON POC MOUNT location** — sentinel lives in `clusters/hub-flux/flux-system/kustomization.yaml`. NOT to be moved or duplicated.

**Existing tenant CRs (DO NOT MODIFY destructively):** alpha + bravo Tenant CRs land with `clusterRoles: [admin]` Flux SA owner pattern from v0.19. v0.20 work is **additive** — new ClusterRole + new human-exercised tenant-owner kubeconfigs + addition of `capsule-platform-owners` group to existing `spec.owners[]` arrays (co-ownership, not replacement); existing Flux SA owner pattern (RBAC-03) MUST be preserved.

**Three-tier permission model (the real-world target this milestone validates):**

This milestone exists to validate the permission stratification that a Karyon-style platform team actually operates inside — modeling the production constraint that the platform team does NOT have cloud-account-level cluster admin.

- **Tier 1 — Cloud Ops / EKS cluster owners:** Provision the EKS cluster itself; hold the AWS-side cluster-admin equivalent. Out of scope to model — exists only as talk-track context.
- **Tier 2 — Karyon Platform Team (the platform-owner role):** Does NOT have k8s cluster-admin. CAN add / remove tenants (Tenant CR lifecycle). IS listed as a co-owner on every tenant (visibility + operational access within every tenant namespace) without being cluster-admin.
- **Tier 3 — Tenant Developers (the tenant-owner role):** Access ONLY to their own tenant's namespaces. Narrower than k8s `edit`. Cannot create Secrets. Cannot read other tenants.

R1 + R3 + R4 each carry pieces of this model. RBAC-04..06 below make Tier 2's "platform team is not cluster-admin but can run the multi-tenant environment" property falsifiable.

---

## v0.20 Requirements

### RBAC — Least-Privilege Tenant Role (Demo R1)

A custom `tenant-workload-editor` ClusterRole replaces `admin` for **human-exercised tenant owners** — narrower than k8s' `edit`. The existing Flux SA owner pattern (`clusterRoles: [admin]` for GitOps reconciliation) is **preserved** with talk-track explanation of why automation gets broader scope than humans.

- [x] **RBAC-01** — A `tenant-workload-editor` ClusterRole exists with scope narrower than upstream k8s `edit`: NO Secret create / edit, NO RoleBinding, NO ResourceQuota, NO LimitRange. Final Secrets policy (read-only / no-access / upstream-edit-equivalent) resolved in discuss-phase per OQ-2.
- [x] **RBAC-02** — Human-exercised tenant-owner kubeconfigs minted via `issue-tenant-kubeconfig.sh` use `tenant-workload-editor` (NOT `admin`). `kubectl auth can-i '*' '*'` returns `no` for the resulting tenant-owner identity.
- [x] **RBAC-03** — Existing Flux SA owner pattern preserved: alpha + bravo Tenant CRs continue to carry `clusterRoles: [admin]` for the per-tenant Flux ServiceAccount that handles GitOps reconciliation. v0.19 Flux reconciliation continues unbroken (regression gate).
- [x] **RBAC-04** — Platform-owner identity (`capsule-platform-owners` group) demonstrably lacks `cluster-admin`: `kubectl auth can-i '*' '*'` returns `no` under the platform-owner kubeconfig. Platform-owner has only the scoped privileges defined by RBAC-05 + RBAC-06 + the Capsule-required cluster-scoped read on Tenant CRs — no wildcard, no PV/PVC across namespaces, no Node access, no CRD authoring.
- [x] **RBAC-05** — Platform-owner can perform the full Tenant CR lifecycle: `kubectl create / get / patch / delete tenant` succeeds under the platform-owner kubeconfig — verified via demo act-3 ("provision a new tenant live") + a corresponding act for deletion (or cleanup). This is the "Karyon Platform Team can add and remove tenants without being cluster-admin" assertion.
- [x] **RBAC-06** — Platform-owner is listed as a **co-owner** on every Tenant CR (the `capsule-platform-owners` group appears in `spec.owners[]` on alpha + bravo + any new tenant the platform-owner provisions live). This gives platform-owner operational LIST/WATCH/GET/LOGS/EXEC visibility across every tenant namespace through capsule-proxy without granting cluster-admin. The platform-owner's bound ClusterRole inside tenant namespaces is broader than `tenant-workload-editor` (so the platform team can debug across tenants) but is bounded — the exact role + Secrets policy resolved in discuss-phase (OQ-2 also applies here). New-tenant provisioning script / template MUST include the platform-owners group in the new Tenant CR's `spec.owners[]` by default.

### SEED — Tenant Namespace Seeding via GlobalTenantResource (Demo R2)

A `GlobalTenantResource` CR auto-propagates a hello-world workload into **every tenant namespace** (alpha-app1, tenant-alpha, bravo-app1, tenant-bravo, plus any new tenant the platform-owner provisions live during the demo).

- [x] **SEED-01** — A `GlobalTenantResource` CR (or equivalent Capsule mechanism) is reconciled into `spoke-capsule` and auto-propagates a hello-world workload into every existing tenant namespace (alpha-app1, tenant-alpha, bravo-app1, tenant-bravo).
- [x] **SEED-02** — Propagation latency ≤ 60 seconds: from a new tenant namespace appearing on the cluster, the seeded hello workload reaches Ready state in that namespace within 60s. Measured via `kubectl wait --for=condition=Ready` or equivalent verifiable bats falsifier.
- [x] **SEED-03** — Hello-world workload shape is the OQ-3-resolved choice (Pod + Service / ConfigMap-only / Deployment + Service + ConfigMap) — final selection lightweight enough to land alongside ≤230s SLO and visually meaningful enough for the demo narrative.

### DEMO — Capsule-Proxy Two-Perspective View (Demo R3)

The demo demonstrates LIST / WATCH / RBAC behavior from **two distinct kubeconfigs**: platform-owner (sees all tenants) and tenant-owner (sees only their own, routed through capsule-proxy on NodePort 30443).

- [ ] **DEMO-01** — Platform-owner kubeconfig (`capsule-platform-owners` group) provides cluster-scoped Tenant CR visibility AND co-owner access into every tenant namespace through capsule-proxy: `kubectl get tenants` returns both `alpha` and `bravo` (and any new tenant); `kubectl get namespaces` (routed through capsule-proxy) returns all tenant namespaces the platform-owner co-owns; `kubectl get pods -A` returns workloads across every tenant namespace.
- [ ] **DEMO-02** — Tenant-owner kubeconfig (minted via `issue-tenant-kubeconfig.sh`, routed through capsule-proxy on NodePort 30443) sees ONLY their own tenant's namespaces — verified for both alpha-owner and bravo-owner via `kubectl get namespaces` + `kubectl get tenants` (both return only the caller's tenant).
- [ ] **DEMO-03** — Tenant-owner can `kubectl get / kubectl logs / kubectl exec` on the SEED-01 hello-world workload in their own namespaces (positive control — proves the RBAC boundary is "narrow but functional", not "broken"). Platform-owner can perform the same actions across ALL tenant namespaces (RBAC-06 co-owner privilege demonstrated).
- [ ] **DEMO-04** — Tenant-owner is REJECTED on `kubectl create secret` (RBAC-01 boundary enforcement). Rejection is observable + scriptable for the demo runbook. Platform-owner's Secrets behavior in the same namespace contrasts per OQ-2 resolution (the talk-track of "broader than tenant, narrower than cluster-admin").
- [ ] **DEMO-05** — Tenant-owner is REJECTED on cross-tenant access: alpha-owner cannot read bravo namespaces / resources, and vice versa. Capsule-proxy LIST filter + tenant home-namespace ownership wiring (inherited from v0.19 Phase 10) demonstrably holds.
- [ ] **DEMO-06** — Platform-owner is REJECTED on cluster-admin-only actions: `kubectl get nodes -o yaml` (or equivalent) returns Forbidden / 403; `kubectl get csr` returns Forbidden; `kubectl create clusterrolebinding ...` returns Forbidden. This is the "Karyon Platform Team is NOT cluster-admin" assertion made falsifiable — the demo includes at least one Forbidden action from the platform-owner kubeconfig so the audience sees the ceiling.

### RUNBOOK — Polished Demo Runbook (Demo R4)

`docs/poc-capsule-demo.md` captures the 6-act walkthrough end-to-end so a teammate can execute it cold.

- [ ] **RUNBOOK-01** — `docs/poc-capsule-demo.md` exists as a 6-act walkthrough: (1) architecture overview — explicit articulation of the **three-tier permission model** (Tier 1 EKS Cloud Ops out-of-scope / Tier 2 Karyon Platform Team / Tier 3 Tenant Devs) and where each tier acts → (2) platform-owner role — show platform-owner kubeconfig, demonstrate Tenant CR LIST + at least one Forbidden cluster-admin action (DEMO-06) so audience sees the ceiling → (3) provision a new tenant live (RBAC-05; tenant name per OQ-5) — show platform-owner CREATE + observe Capsule materializing the tenant + new tenant namespace appearing in platform-owner LIST → (4) GlobalTenantResource auto-seed observation (SEED-02 ≤ 60s) — watch hello-world workload appear in the new tenant namespace → (5) two perspectives — switch to tenant-owner kubeconfig, demonstrate scoped LIST + DEMO-04 Forbidden create-secret + DEMO-05 cross-tenant rejection; switch back to platform-owner to show co-owner LIST/EXEC into the same tenant → (6) cleanup — platform-owner deletes the new tenant + observe Capsule unmaterializing it (RBAC-05 delete half). Each act has a concrete `kubectl` / `task` step + expected output.
- [ ] **RUNBOOK-02** — Runbook includes a pre-demo checklist: cluster reachable (`kubectl --context k3d-spoke-capsule get nodes`), `task fix-dns-poc-capsule` if needed, both kubeconfigs staged, both tenant-owner identities pre-minted (or scripted-on-demand) — checklist is executable, not narrative.
- [ ] **RUNBOOK-03** — Runbook includes known-noise notes: capsule-controller `tls: bad certificate` 1Hz chatter (per OQ-1 resolution — document-only is the recommended default), cross-link to ADR-008 (POC-graduation = DEFER framing), cross-link to `docs/capsule-on-eks.md` for the production-translation forward-pointer (and specifically how the three-tier model maps onto an actual EKS-on-AWS scenario — Cloud Ops = AWS account / IAM admin; Karyon Platform Team = EKS IRSA-bound role + cluster-scoped RBAC; Tenants = Capsule-scoped workload-editors).
- [ ] **RUNBOOK-04** — Runbook is executable end-to-end against a `spoke-capsule` cluster in **≤ 15 minutes** by a human reading it cold (no prior context required beyond the README). UAT verification by milestone owner before milestone close.
- [ ] **RUNBOOK-05** — New-tenant name selection (per OQ-5: "charlie" / "demo" / "team-foo" / other) is reflected verbatim in the runbook's act-3 "provision a new tenant live" step, with the chosen name canonical across runbook + delivery mechanism + any scripted helpers.

### DELIVERY — Self-Contained Delivery Path (Demo R5)

The demo resources (ClusterRole, GlobalTenantResource, any hello-world workload manifests) land via a clearly-named delivery mechanism — decision deferred to discuss-phase per OQ-4.

- [x] **DELIVERY-01** — New demo resources (`tenant-workload-editor` ClusterRole, `GlobalTenantResource` CR, hello-world workload manifest) land via the OQ-4-resolved delivery mechanism — either GitOps under `pocs/capsule/` (production-correct, slower because of push-and-reconcile cycle) or a `task seed-capsule-demo` Taskfile entry (fast, self-contained). Single canonical path documented in RUNBOOK-01.
- [x] **DELIVERY-02** — Delivery mechanism preserves P31 invariant: zero new `spoke-capsule` mentions in any v0.18 default-path script (anything outside `scripts/poc/`). Verified by the existing static bats P31 grep + a fresh-run `task rebuild` post-deployment showing SLO < 230s holds.
- [x] **DELIVERY-03** — Delivery mechanism is **additive only**: existing alpha + bravo Tenant CRs unchanged, existing Flux reconciliation paths unchanged, `task rebuild` exit-code 0 with v0.18 health-check unchanged.

---

## Future Requirements

Acknowledged + carried forward; NOT in v0.20 scope.

### v0.19 Carryover (still deferred)

- **ADDON-01 / ADDON-02** — `capsule-addon-fluxcd` Trial (deferred from v0.19 Phase 12). Trial the addon as a Flux HelmRelease + hand-managed vs addon-managed comparison doc (token rotation, kubeconfig refresh, complexity, blast radius). Revisit alongside `capsule-addon-fluxcd` releases that pair with newer Capsule minors.
- **G-04 architectural decision / split-Kustomization refactor** — Plan 11-07 D-11-01 PostBuild workaround stays. Architecture review is a future-milestone concern.
- **Optional `KARYON_PHASE11_STRICT_LIVE=1` re-verification path** — Future tightening of Phase 11 verifier.
- **slo-regression-live `KARYON_REBUILD_APPROVED` infrastructure** — Future SLO-regression harness for live-with-spoke-capsule runs.

### v0.18 Carryover (still deferred)

- **Phase 1-5 shellcheck warning cleanup (SC2034 / SC2155)** — Lint cleanup deferred since v0.18 close.
- **First-push CI verification + GitHub branch-protection setup** — Operational hardening deferred.
- **Real secret management (Vault / SOPS / age)** — Placeholder `.env` + `.env.example` pattern continues.
- **Stale frontmatter reconciliation pass** — Largely reconciled during v0.19 close-out; remaining drift deferred.
- **Pre-existing markdownlint failures** — Lint cleanup deferred.
- **Pre-existing gitleaks finding in `proxy-06` fixture** — Allowlisted; full cleanup deferred.

---

## Out of Scope

Explicit exclusions — discuss-phase MUST NOT re-litigate.

| Feature | Reason |
|---------|--------|
| OIDC tenant authentication | Token-based continues; OIDC issuer (Dex / Keycloak / Auth0) is a future-milestone capability. |
| Production ingress + cert-manager + real TLS for capsule-proxy | NodePort + self-signed remains the POC pattern. |
| Generic ephemeral cluster factory | `spoke-capsule` stays hand-rolled and persistent. |
| Multi-spoke tenant federation | Single-spoke POC continues. |
| Hub-side Capsule install | Spoke-only continues. |
| Default platform adoption of Capsule | ADR-008 = DEFER stands; `spoke-capsule` does NOT enter `task rebuild` (P31 invariant preserved). |
| Production hardening | Lab-only; no HA, no hardened RBAC baseline, no network policies baseline. |
| Cloud clusters | Local-only by design; keeps dependencies and cost predictable. |
| New ADRs beyond inheritance | v0.20 introduces no new ADRs (ADR-008 = DEFER stands; no graduation revisit). |
| Revisiting alpha/bravo Tenant CRs | v0.20 work is additive — no edits to existing Tenant CRs. |

---

## Traceability

Which phases cover which requirements. Filled by roadmapper.

| Requirement | Phase | Status |
|-------------|-------|--------|
| RBAC-01 | Phase 13 | Complete |
| RBAC-02 | Phase 13 | Complete |
| RBAC-03 | Phase 13 | Complete |
| RBAC-04 | Phase 13 | Complete |
| RBAC-05 | Phase 13 | Complete |
| RBAC-06 | Phase 13 | Complete |
| SEED-01 | Phase 13 | Complete |
| SEED-02 | Phase 13 | Complete |
| SEED-03 | Phase 13 | Complete |
| DEMO-01 | Phase 14 | Pending |
| DEMO-02 | Phase 14 | Pending |
| DEMO-03 | Phase 14 | Pending |
| DEMO-04 | Phase 14 | Pending |
| DEMO-05 | Phase 14 | Pending |
| DEMO-06 | Phase 14 | Pending |
| RUNBOOK-01 | Phase 14 | Pending |
| RUNBOOK-02 | Phase 14 | Pending |
| RUNBOOK-03 | Phase 14 | Pending |
| RUNBOOK-04 | Phase 14 | Pending |
| RUNBOOK-05 | Phase 14 | Pending |
| DELIVERY-01 | Phase 13 | Complete |
| DELIVERY-02 | Phase 13 | Complete |
| DELIVERY-03 | Phase 13 | Complete |

**Coverage:**

- v0.20 requirements: **23 total** (6 RBAC + 3 SEED + 6 DEMO + 5 RUNBOOK + 3 DELIVERY)
- Mapped to phases: **23 / 23** (Phase 13: 12 REQs = 6 RBAC + 3 SEED + 3 DELIVERY; Phase 14: 11 REQs = 6 DEMO + 5 RUNBOOK; Phase 15: 0 REQs — close-out / book-keeping)
- Unmapped: **0**

**Note:** Phase 15 (v0.20 close-out + retrospective) introduces no new REQ-IDs — it is a book-keeping / reconciliation phase that flips the 23 mandatory checkboxes above against live evidence from Phases 13 + 14 (mirrors v0.19 Phase 12 close-out pattern).

---

## Milestone Success Criteria (from briefing — also tracked at ROADMAP level)

- Demo runbook executable end-to-end against `spoke-capsule` in ≤ 15 minutes by a human reading it cold (RUNBOOK-04)
- Three-tier permission model demonstrably enforced: Tier 2 platform-owner lacks cluster-admin (RBAC-04 + DEMO-06 Forbidden actions), can manage Tenant CRs (RBAC-05), is co-owner inside every tenant namespace (RBAC-06 + DEMO-01); Tier 3 tenant-owner is scoped to own tenant only (RBAC-02 + DEMO-02 + DEMO-04 + DEMO-05)
- All human-exercised roles demonstrably lack `cluster-admin` — `kubectl auth can-i '*' '*'` returns `no` for both platform-owner and tenant-workload-editor (RBAC-02, RBAC-04)
- `kubectl create secret` forbidden for tenant-owner under `tenant-workload-editor` (DEMO-04)
- Platform-owner sees all tenants + has co-owner LIST/EXEC into all tenant namespaces; tenant-owner via capsule-proxy sees only their own (DEMO-01, DEMO-02)
- `GlobalTenantResource` propagates the hello workload to every tenant namespace within 60s (SEED-02)
- Platform-owner can provision + delete tenants live during the demo (RBAC-05 + RUNBOOK-01 act 3 + act 6)
- Existing alpha/bravo Flux reconciliation continues to function — no regression (RBAC-03, DELIVERY-03)
- v0.18 `task rebuild` SLO < 230s preserved — no regression (DELIVERY-02)
- `/gsd-audit-milestone v0.20` returns `passed`

---

*Requirements defined: 2026-05-19 — milestone v0.20 (Capsule POC Demo & RBAC Polish) opened via `/gsd-new-milestone v0.20` ingesting `v0.20-MILESTONE-BRIEFING.md`. 23 requirements across 5 categories (6 RBAC / 3 SEED / 6 DEMO / 5 RUNBOOK / 3 DELIVERY); RBAC-04..06 + DEMO-01/03/04/06 + RUNBOOK-01/03 make the **three-tier permission model** explicit (Tier 1 Cloud Ops out-of-scope / Tier 2 Karyon Platform Team / Tier 3 Tenant Devs) per milestone-owner clarification — the real-world target is "platform team is not cluster-admin but runs the multi-tenant environment". 5 open questions explicitly deferred to discuss-phase (TLS noise, Secrets policy, workload shape, delivery path, new-tenant name + live-provisioning style). Roadmapper traceability filled 2026-05-19 — 3 phases (13: RBAC+SEED+DELIVERY artifacts, 12 REQs; 14: DEMO+RUNBOOK verification, 11 REQs; 15: close-out + retrospective, 0 new REQs).*
