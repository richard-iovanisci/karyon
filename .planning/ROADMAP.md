# Roadmap: karyon

## Milestones

- [x] **v0.18 — karyon Lab v1** — Phases 1-6 (shipped 2026-04-29)
- [ ] **v0.19 — Capsule Multi-Tenancy POC** — Phases 7-12 (in progress)

## Phases

<details>
<summary>v0.18 — karyon Lab v1 (Phases 1-6) — SHIPPED 2026-04-29</summary>

- [x] Phase 1: Host Foundation (9/9 plans) — completed 2026-04-23
- [x] Phase 2: Cluster Layer (7/7 plans) — completed 2026-04-24
- [x] Phase 3: Flux Hub Bootstrap (6/6 plans) — completed 2026-04-27
- [x] Phase 4: Spoke Registration (5/5 plans) — completed 2026-04-28
- [x] Phase 5: Workloads + Health + Rebuild (6/6 plans) — completed 2026-04-28
- [x] Phase 6: Repo Hygiene + Docs + ADRs (8/8 plans) — completed 2026-04-29

**Total:** 6 phases, 41 plans, 90 tasks. Full archive: `.planning/milestones/v0.18-ROADMAP.md`. Audit: `.planning/milestones/v0.18-MILESTONE-AUDIT.md` (status: tech_debt — all 81 requirements satisfied; 4 code-review warnings auto-fixed in commits `ea30765`, `fa0424a`, `ab82c59`, `90e2906`; first-push CI verification deferred as user follow-up).

</details>

### v0.19 — Capsule Multi-Tenancy POC (Phases 7-12)

**Goal:** Prove [Capsule](https://capsule.clastix.io/) as a Karyon-managed multi-tenancy pattern on a dedicated, isolated POC spoke (`spoke-capsule`) — without polluting the default v1 topology or `task rebuild` path. Close with an explicit graduation ADR-008 (adopt / defer / reject / another POC).

**Phase numbering:** Continues from v0.18 (Phase 6 → Phase 7). Phase 12 was originally scoped as an OPTIONAL gated `capsule-addon-fluxcd` trial; per `/gsd-plan-milestone-gaps` (2026-05-11), the addon trial is deferred to v0.20 and Phase 12 is repurposed as v0.19 close-out reconciliation (ADDON-01/02 moved to Future Requirements).

**Load-bearing invariants every phase respects:**

- **P27** — every tenant Flux Kustomization MUST set `spec.serviceAccountName` (Flux's `--default-service-account` lockdown does NOT apply when `spec.kubeConfig` is set; without explicit `serviceAccountName` tenants run as cluster-admin and bypass Capsule)
- **P29** — tenant kubeconfigs MUST NOT land in git
- **P31** — `spoke-capsule` MUST NOT enter `task rebuild` until graduation ADR adopts Capsule
- **KARYON POC MOUNT location** — sentinel inserted in `clusters/hub-flux/flux-system/kustomization.yaml` (NOT `clusters/hub-flux/kustomization.yaml`)

#### Phase Summary

- [x] **Phase 7: Foundation — POC Seam + spoke-capsule Cluster + EKS Capsule Doc** — Generic POC mount surface, persistent isolated POC k3d cluster, and EKS-targeted Capsule rough-cut doc for team-presentation (completed 2026-04-29; 6/6 plans, 9/9 must-haves verified, 271/271 bats GREEN; carryover 1b folded into Phase 8 verifier; HUMAN-UAT items 2/3/4 tracked as non-blocking follow-ups in `.planning/todos/pending/`)
- [x] **Phase 8: Capsule + capsule-proxy Bare-Minimum Install** — Two upstream HelmReleases reconciled hub-only into spoke-capsule; operator alive + proxy reachable + CRDs visible (plans 0-4 executed 2026-04-29..2026-04-30; verifier `08-VERIFICATION.md` reports `passed_with_overrides` 10/10 must-haves; G-03 cert source + G-04 architectural seam closed by plan 08-04 [D-08-11/12]; G-01/02 push gate deferred-with-override to Phase 11 VAL-05 per D-08-13. Phase 7 P40/P18 invariant evolved: split-path Kustomization pattern — spoke-targeted Ks include kubeConfig; hub-targeted Ks exclude it.)
- [x] **Phase 9: Tenants + Flux Multi-Tenancy Lockdown** — Two Tenants with disjoint owners, hub Flux controllers patched with lockdown flags, P27 defense in tenant inner Kustomizations (completed 2026-04-30; 5/5 plans, 8/8 must-haves; verifier `09-VERIFICATION.md` reports `passed_with_overrides` — 4 live PASS + 4 D-08-13 push-gate-deferred to Phase 11 VAL-05; Plan 09-03 lockdown landed on **attempt 3** after two atomic rollbacks — Gap A spoke SA name corrected from `kustomize-controller` to `flux-reconciler` per `register-spokes-for-flux.sh:286`; attempt-1+2 archives preserved at `09-03-SUMMARY.attempt-{1,2}-rollback.md`; RESEARCH.md §Gap 3 + §Gap 11 carry CORRECTION + CORRECTION 2 cumulative falsification record; Plan 09-04 verifier added `--default-service-account=default` to helm-controller per RESEARCH §Gap 2 [Rule 2 deviation, defense-in-depth]; v0.18 task health-check exit 0 across 3 cluster states.)
- [x] **Phase 10: Tenant Owner Kubeconfigs + Capsule-Proxy Round-trip** — Imperative kubeconfig minting routed via proxy (Plan 10-01 issue-tenant-kubeconfig.sh), tenant-scoped LIST verified live (Plan 10-02 render+apply staging — Pitfall 10-P6 mitigated; helm template + kubectl apply -f, NOT flux-suspend; spoke-capsule has no Flux CRDs per ADR-004), kubeconfig delivery contract documented (PROXY-03 H2 in docs/poc-capsule.md). Plan 10-00 RED bats scaffold (45 @tests) + Plan 10-01 script + doc + Plan 10-02 verifier. Disposition: `passed_with_overrides` (D-08-13 push-gate stays deferred to Phase 11 VAL-05). (completed 2026-05-05)
- [x] **Phase 11: Validation + Graduation ADR-008** — Negative RBAC suite (N1-N12), webhook failure recovery, clean teardown, rebuild SLO regression gate, graduation ADR (completed 2026-05-06)
- [x] **Phase 12: v0.19 Close-out Reconciliation** — Gap closure phase created by `/gsd-plan-milestone-gaps` 2026-05-11; completed 2026-05-11 (7/7 plans). Reconciled REQUIREMENTS.md (18 v0.19 mandatory checkboxes flipped: POC-01..04 + CAPCLU-01..04 + EKSDOC-01 + CAP-01..03 + TEN-01..06 = 4+4+1+3+6 = 18; TEN-01 spec amended per D-11-07), STATE.md (last_activity past Plan 11-07; Phase 12 entered; Pending Todos reconciled), 11-VERIFICATION.md + 11-PHASE-VERIFICATION.md (Supersedure 2026-05-11 blocks appended; disposition `passed`), Nyquist VALIDATION ledgers (phases 7, 8, 9, 10, 11 → status: final), Phase 7 hub-flux observable-reconcile todo (moved to completed/). Audit re-run returned `passed` per 12-07-SUMMARY.md. (Replaces the original Phase 12 `capsule-addon-fluxcd` trial; addon trial deferred to v0.20.)

## Phase Details

### Phase 7: Foundation — POC Seam + spoke-capsule Cluster + EKS Capsule Doc
**Goal**: User has a generic, sentinel-guarded POC onboarding seam, a persistent isolated `spoke-capsule` k3d cluster reconciled hub-only by Flux, and a self-contained EKS-targeted Capsule rough-cut doc usable for an immediate team presentation
**Depends on**: v0.18 baseline (ADR-001..005, hub-only Flux, P18 silent-misroute defense)
**Requirements**: POC-01, POC-02, POC-03, POC-04, CAPCLU-01, CAPCLU-02, CAPCLU-03, CAPCLU-04, EKSDOC-01
**Success Criteria** (what must be TRUE, in order of delivery within the phase):
  1. **EKS doc lands first** — User can read `docs/capsule-on-eks.md` (Status: Draft) covering all five required sections (what Capsule is, the 7 CRDs, RBAC needs, EKS install path with IRSA + ALB + ECR translation, "what the POC does NOT prove") and walk a team through it
  2. `# KARYON POC MOUNT` sentinel exists in `clusters/hub-flux/flux-system/kustomization.yaml` (the FLUX PATCH SURFACE) parallel to existing `# KARYON SPOKES MOUNT`, surviving `flux bootstrap` re-runs
  3. User can run `scripts/poc/capsule/create-cluster.sh` to create persistent `spoke-capsule` k3d cluster (apiserver port 6446, NodePort 30443, `--tls-san k3d-spoke-capsule-server-0`) on the shared `k8s-net` network — `k3d cluster list` shows spoke-capsule
  4. `task preflight` reserves the capsule-proxy NodePort (30443) and fails fast if the port is already in use
  5. Hub-flux reconciles into spoke-capsule via outer Kustomization `clusters/hub-flux/pocs/capsule.yaml` with `spec.kubeConfig.secretRef.key: value.yaml` (P18 inheritance) — silent-misroute falsifier passes
  6. Tenant kubeconfig leak defense in place: extended `.gitignore` globs + new `.gitleaks.toml` rule for `kind: Config` + bearer-token shape, verified by synthetic-fixture bats
  7. `task fix-dns-poc-capsule` recovers stale CoreDNS NodeHosts on spoke-capsule alone, without affecting v0.18 default `task fix-dns`; host-restart procedure documented in `docs/poc-capsule.md`
**Plans**: 6 plans (Wave 0 Nyquist gate + Waves 1-3 implementation)
- [x] 07-00-PLAN.md — Wave 0 Nyquist gate: 7 bats stubs + 2 gitleaks fixtures (POC-01..04, CAPCLU-01..04, EKSDOC-01 contracts)
- [x] 07-01-PLAN.md — EKS doc (docs/capsule-on-eks.md, Status: Draft) — EKSDOC-01 lands first per D-13
- [x] 07-02-PLAN.md — POC seam static infra (# KARYON POC MOUNT sentinel + clusters/hub-flux/pocs/{kustomization.yaml, capsule.yaml} + pocs/capsule/kustomization.yaml placeholder) — POC-01, CAPCLU-02
- [x] 07-03-PLAN.md — spoke-capsule cluster + register-poc-cluster.sh (with P18 falsifier) — POC-02, CAPCLU-01, CAPCLU-02 (live)
- [x] 07-04-PLAN.md — Preflight 30443 fail-fast + tenant-kubeconfig leak defense (.gitignore + .gitleaks.toml) — POC-03, POC-04
- [x] 07-05-PLAN.md — Host-restart recovery (scripts/poc/capsule/fix-dns.sh + task fix-dns-poc-capsule + docs/poc-capsule.md) — CAPCLU-03, CAPCLU-04

### Phase 8: Capsule + capsule-proxy Bare-Minimum Install
**Goal**: Capsule operator and capsule-proxy run on spoke-capsule via two separate Flux HelmReleases reconciled hub-only; CRDs are visible and the proxy is reachable from the WSL host
**Depends on**: Phase 7 (POC mount surface + spoke-capsule cluster reconciling)
**Requirements**: CAP-01, CAP-02, CAP-03
**Success Criteria** (what must be TRUE):
  1. Capsule operator (`capsule:0.12.4`, OCI `ghcr.io/projectcapsule/charts/capsule`) installed via Flux HelmRelease — `capsule-controller-manager` pod is `Running` on spoke-capsule and HelmRelease reports `Ready=True`
  2. `capsule-proxy:0.12.0` (separate HelmRelease, NOT umbrella) is reachable from the WSL host — `curl -k https://127.0.0.1:30443/healthz` returns 200
  3. All 7 Capsule CRDs (`Tenant`, `CapsuleConfiguration`, `GlobalTenantResource`, `TenantResource`, `ResourcePool`, `ResourcePoolClaim`, `TenantOwner`) are installed and visible — `kubectl get crds | grep capsule.clastix.io` returns ≥7 entries
  4. ADR-004 invariant preserved — `kubectl --context=k3d-spoke-capsule get pods -n flux-system` returns no Flux controllers (hub-only Flux unchanged)
**Plans**: 5 plans (Wave 0 Nyquist gate + Waves 1-3 implementation + verifier + Wave 4 gap-close)
- [x] 08-00-PLAN.md — Wave 0 Nyquist gate: 10 bats files RED (5 static + 5 live, cluster-info gated) covering CAP-01/02/03 contracts + Pitfall 8 reframe + Pitfall 9 anti-pattern lint
- [x] 08-01-PLAN.md — Operator HelmRelease + OCIRepository + local kustomize (pocs/capsule/operator/) — CAP-01, CAP-03
- [x] 08-02-PLAN.md — Proxy HelmRelease + OCIRepository + local kustomize (pocs/capsule/proxy/) + atomic rewrite of pocs/capsule/kustomization.yaml to resources: [operator/, proxy/] — CAP-02, CAP-03
- [x] 08-03-PLAN.md — Verifier — live HelmRelease Ready=True + CRDs + proxy reachable + ADR-004 invariant + FOLDED CARRYOVER (outer poc-capsule Kustomization Ready=True; Phase 7 verification 1b) + Phase 7 P31/P40/P18 regression rerun
- [x] 08-04-PLAN.md — Gap closure — D-08-11 cert flip (controller-less certgen Job) + D-08-12 architectural seam (split paths: hub-targeted + spoke-targeted Kustomizations) + WR-01..WR-04 bats hardening (yq path / kubectl jsonpath); D-08-13 push-gate deferred to Phase 11 VAL-05

### Phase 9: Tenants + Flux Multi-Tenancy Lockdown
**Goal**: Two tenants with disjoint owners exist on spoke-capsule with auto-materialized resource isolation; hub Flux controllers run with multi-tenancy lockdown flags; tenant inner Kustomizations carry the load-bearing P27 defense (`spec.serviceAccountName`)
**Depends on**: Phase 8 (Capsule operator running, CRDs registered)
**Requirements**: TEN-01, TEN-02, TEN-03, TEN-04, TEN-05, TEN-06
**Success Criteria** (what must be TRUE):
  1. Two `Tenant` CRs (`alpha`, `bravo`) exist with disjoint `owners` arrays (each kind ServiceAccount registered as `<tenant-ns>:gitops-reconciler`); namespace prefix enforcement enabled (`forceTenantPrefix: true`)
  2. Tenant owner can self-serve a namespace inside their tenant prefix — `kubectl --as=alpha create namespace alpha-app1` succeeds and the namespace gets `capsule.clastix.io/tenant=alpha` label automatically
  3. ResourceQuota and LimitRange objects auto-materialize inside each tenant namespace (`kubectl get resourcequota -n alpha-app1` shows `capsule-alpha-*` objects without manual creation)
  4. **P27 defense in place** — every tenant inner Flux Kustomization under `pocs/capsule/tenants/<name>/` declares `spec.serviceAccountName: gitops-reconciler` explicitly; static bats grep-asserts every tenant Kustomization has a non-null `serviceAccountName`
  5. Hub Flux controllers run with multi-tenancy lockdown (`--no-cross-namespace-refs=true`, `--no-remote-bases=true`, `--default-service-account=default`) AND `flux-system` Kustomization sets explicit `spec.serviceAccountName: kustomize-controller` (platform-admin escape hatch); v0.18 `task health-check` regression gate still passes
  6. Tenants Kustomization declares `dependsOn` chain on operator Kustomization with `wait: true` (P32 — Tenant CR apply blocks until CRDs exist)
**Plans**: 5 plans (Wave 0 RED bats scaffold + Waves 1-4 implementation + verifier)
- [x] 09-00-PLAN.md — Wave 0 RED bats scaffold: 12 bats files (5 static + 7 live) + p27 negative falsifier fixture (TEN-01..06 contracts; D-09-08 Nyquist gate)
- [x] 09-01-PLAN.md — Spoke-side: CapsuleConfiguration singleton + per-tenant namespaces + per-tenant SAs + Tenant CRs + capsule-spoke.yaml dependsOn chain (TEN-01/03/06; D-09-01/02/04/06; RESEARCH Gap 4/5/9 corrections)
- [x] 09-02-PLAN.md — Hub-side: per-tenant inner Kustomizations + per-tenant GitRepositories + register-poc-cluster.sh Secret-mirror extension (TEN-04 P27 + TEN-06; D-09-01/03; RESEARCH Gap 1 mitigation)
- [x] 09-03-PLAN.md — Hub Flux multi-tenancy lockdown patches + escape hatches + spoke defense-in-depth (RE-PLAN after 09-03 attempt 1 rollback at commit 9b6b3a5; TEN-05; D-09-05/05a; expands scope to v0.18 spoke files spoke-apps.yaml + spoke-ml.yaml per 09-03-SUMMARY.md falsified §Gap 3 / §Gap 11 line 693; HIGH regression risk; pre/post task health-check rerun; atomic rollback fallback via git revert --no-edit HEAD)
- [x] 09-04-PLAN.md — Verifier: full Phase 9 bats + Phase 7 P31 + Phase 8 CAP-01..03 + ADR-004 + final task health-check; writes 09-VERIFICATION.md

### Phase 10: Tenant Owner Kubeconfigs + Capsule-Proxy Round-trip
**Goal**: Tenant owner kubeconfigs are minted imperatively, route through capsule-proxy (never the apiserver direct), give each owner LIST visibility ONLY into their own tenant's namespaces, and never land in git
**Depends on**: Phase 9 (Tenants exist with owner ServiceAccounts)
**Requirements**: PROXY-01, PROXY-02, PROXY-03
**Success Criteria** (what must be TRUE):
  1. `scripts/poc/capsule/issue-tenant-kubeconfig.sh <tenant> <owner>` mints a tenant kubeconfig with `server: https://127.0.0.1:30443` (capsule-proxy NodePort), prints to stdout by default, supports optional `--write-to <path>` rooted at `${TMPDIR:-/tmp}/karyon-tenants/`
  2. Using the issued kubeconfig, `kubectl get namespaces` returns ONLY namespaces owned by the tenant (proxy LIST filtering working) — direct apiserver access on `:6446` with the same token returns the unfiltered list (proves proxy is doing the filtering, not RBAC alone)
  3. Kubeconfig delivery contract documented in `docs/poc-capsule.md`: stdout default, optional `--write-to`, mandatory tmpdir-not-repo location, gitleaks rule catches accidental commits (synthetic-fixture bats verifies)
  4. **P29 defense holds** — first push after this phase passes the gitleaks pre-commit + post-push scan with zero findings
**Plans**: 3 plans (Wave 0 RED bats + Wave 1 script + doc + Wave 2 verifier)
- [x] 10-00-PLAN.md — Wave 0 RED bats scaffold: 7 bats files (45 @tests; PROXY-01..03 contracts; Pitfall 10-P2/P3/P5 corrections applied)
- [x] 10-01-PLAN.md — `scripts/poc/capsule/issue-tenant-kubeconfig.sh` (TokenRequest mint + heredoc kubeconfig + tmpdir-rooted --write-to) + `docs/poc-capsule.md` "Tenant kubeconfig delivery contract" H2 append (Pitfall 10-P1/P2/P7 corrections applied)
- [x] 10-02-PLAN.md — Verifier: capsule-proxy live staging observed (Plan 10-01 helm install state persisted; render+apply staging mechanism per Pitfall 10-P6 — helm install + kubectl apply against spoke-capsule context; NOT flux-suspend; spoke-capsule has no Flux CRDs per ADR-004) + full Phase 10 + Phase 7+8+9 inheritance bats + task health-check exits 0; writes 10-VERIFICATION.md with `passed_with_overrides` disposition + D-08-13 push-gate forward to Phase 11 VAL-05; 2 Rule 3 deviations documented for Phase 11 carryover (CapsuleConfiguration userGroups patch + tenant home namespace ownership)

### Phase 11: Validation + Graduation ADR-008
**Goal**: Empirical bats evidence proves Capsule's tenant boundary holds (negative RBAC + webhook failure + clean teardown), the v0.18 `task rebuild` SLO is unchanged, and the closing graduation ADR-008 records the adopt/defer/reject/replaced decision backed by the bats evidence
**Depends on**: Phase 10 (proxy round-trip working, tenant kubeconfigs minted)
**Requirements**: VAL-01, VAL-02, VAL-03, VAL-04, VAL-05, VAL-06
**Success Criteria** (what must be TRUE):
  1. All 12 negative RBAC bats falsifiers (N1-N12) PASS: cross-tenant pod read denied (N1), cluster-wide LIST filtered to own tenant (N2), cross-tenant secret read denied (N3), ClusterRoleBinding escalation denied (N4), namespace prefix violation denied (N5), tenant quota violation denied (N6), denied registry pull denied (N7), direct-apiserver bypass on :6446 denied or limited (N8), cross-tenant `sourceRef` in tenant Kustomization denied (N9), missing `spec.serviceAccountName` denied/falls through (N10), workload create rejected when capsule-controller is down (N11), workload create succeeds again after operator recovers (N12)
  2. Capsule webhook failure mode observed and recoverable — `task fail-capsule-webhook` (test-only) scales operator to 0 then 1; both halves bats-asserted
  3. Clean teardown — `task destroy-poc capsule` performs ordered teardown (suspend → delete Tenants → wait for namespace cascade → optional `k3d cluster delete spoke-capsule`) leaving `# KARYON POC MOUNT` sentinel + `clusters/hub-flux/pocs/` mount in place; post-teardown no `capsule.clastix.io/tenant=<name>` labeled objects remain
  4. **`task rebuild` SLO regression test PASSES** — total time < 230s; spoke-capsule's container ID is unchanged across rebuild; zero `spoke-capsule` mentions in `scripts/{create-clusters,register-spokes-for-flux,health-check,destroy,delete-clusters,rebuild}.sh` (P31 enforcement)
  5. One-shot history gitleaks scan post-Phase-10 first push returns 0 findings — proves no tenant kubeconfig leaked
  6. **ADR-008 graduation written** with `Status: Accepted` and one of {adopt, defer, reject, replaced by ADR-N}, sectioned per Nygard 4-section template, with explicit "What we proved / What we did not prove / Trade-offs" sub-sections backed by bats references; ADR-008 also rolls forward `docs/capsule-on-eks.md` (EKSDOC-01) from `Status: Draft` to `Status: Reviewed` with corrections informed by the bats evidence
**Plans**: 8 plans (Wave 0 RED scaffold + Waves 1-4 implementation + verifier + ADR write + G-04 gap closure + G-06 + CI carryovers gap closure)
- [x] 11-00-PLAN.md — Wave 0 RED bats scaffold: 16 bats files (5 negative-rbac + 1 anti-pattern lint + 5 push-gate + 4 teardown + 1 slo-regression-live) covering D-11-05..16 contracts
- [x] 11-01-PLAN.md — Push-gate persistent fixes: D-11-01 PostBuild patch on capsule.yaml + D-11-02 CapsuleConfiguration 3-group userGroups + D-11-03 tenant namespace labels + D-11-04 .gitleaks.toml .planning/*.md allowlist (resolves Phase 10 carryover items + Phase 7 gitleaks-planning-doc-todo)
- [x] 11-02-PLAN.md — POC scripts + Taskfile: scripts/poc/capsule/destroy-poc.sh (D-11-10 5-step + D-11-11 PVC strand mitigation) + scripts/poc/capsule/fail-capsule-webhook.sh (D-11-09 scale 0/1) + Taskfile.yml entries (D-11-12)
- [x] 11-03-PLAN.md — Negative RBAC bats GREEN: Tenant CR fixture extensions (N6 quota: 3, N7 containerRegistries.allowed: [registry.example.io]) + live negative-rbac-*.bats run; targets 12/12 N1-N12 GREEN
- [x] 11-04-PLAN.md — Verifier: imperative helm install cleanup + first push event (operator checkpoint per CLAUDE.md) + post-push Flux reconcile observation + full 16-bats live re-run + VAL-04 SLO regression + post-push gitleaks history scan; writes 11-VERIFICATION.md
- [x] 11-05-PLAN.md — ADR-008 + EKSDOC-01 rollforward: docs/adr/0008-capsule-multi-tenancy-graduation.md per D-11-14 evidence-bound rubric (operator-confirmed outcome) + docs/capsule-on-eks.md Status Draft -> Reviewed with 4 D-11-15 revision blocks + tests/bats/docs-adr-template.bats lint extension for ADR-008
- [ ] 11-06-PLAN.md — G-04 gap closure: capsule-system Namespace on hub + D-11-01 PostBuild patch relocated from Kustomization spec.patches to HelmRelease spec.postRenderers (Pitfall 11-P1 fix) + push-gate-01 bats updated + Flux reconcile verification
- [ ] 11-07-PLAN.md — G-06 + CI carryovers gap closure (REVISED 2026-05-06 per codex review §2): helm-controller SA on spoke (spec.serviceAccountName impersonation fix; closes flux reconcile context-deadline-exceeded) + spoke-side capsule-system Namespace (codex HIGH #1) + corrected poc-capsule-spoke target SA from kustomize-controller to flux-reconciler (codex HIGH #2) + new poc-capsule-spoke-rbac top-level Flux K with no dependsOn for deterministic ordering (codex MEDIUM #3) + G-06 root-cause diagnostics scaffold + markdownlint pre-existing 31 errors + gitleaks file-specific allowlist for proxy-06-live-fixture.bats + slo-regression-live KARYON_REBUILD_APPROVED export + Plan 11-06 Task 3 finalization

### Phase 12: v0.19 Close-out Reconciliation
**Goal**: Reconcile v0.19 milestone artifacts to match implementation reality at HEAD `8415ab66`. Update all stale documentation, close Nyquist ledgers, supersede pre-11-07-closeout Phase 11 verification artifacts, resolve the TEN-01 `forceTenantPrefix` spec deviation, and archive the stale Phase 7 carryover todo. Prepares v0.19 for clean archival via `/gsd-complete-milestone`.
**Depends on**: Phase 11 (Plan 11-07 G-04 + G-06 closeout — must be the canonical post-fix state)
**Gap closure**: Closes ALL `tech_debt` items from `.planning/v0.19-MILESTONE-AUDIT.md` (audited 2026-05-07; status `tech_debt`).
**Requirements**: No new REQ-IDs (book-keeping phase). Closes the 18 v0.19 mandatory `[ ]` checkboxes for POC-01..04 + CAPCLU-01..04 + EKSDOC-01 + CAP-01..03 + TEN-01..06 (= 4+4+1+3+6 = 18) against the existing implementation.
**Success Criteria** (what must be TRUE):
  1. `.planning/REQUIREMENTS.md`: 18 v0.19 mandatory `[ ]` checkboxes flipped to `[x]` for POC-01..04 + CAPCLU-01..04 + EKSDOC-01 + CAP-01..03 + TEN-01..06 (= 4+4+1+3+6 = 18) against the audit's WIRED evidence. TEN-01 spec text amended to reflect `forceTenantPrefix: false` per Plan 11-07 D-11-07 live repair, OR an ADR-008 amendment records the deviation explicitly.
  2. `.planning/ROADMAP.md` Progress table (lines 149-162) refreshed to match the Phase Summary checkboxes — no within-document contradiction. Phase 11 row reflects 8/8 Complete (2026-05-07). Phase 12 row reflects new close-out scope, not addon trial.
  3. `.planning/STATE.md` `last_activity` updated past Plan 11-07 closeout; `current_phase` advances correctly post close-out.
  4. `.planning/phases/11-validation-graduation-adr-008/11-VERIFICATION.md` and `11-PHASE-VERIFICATION.md` superseded by post-11-07 versions reflecting G-04 + G-06 CLOSED, all 4 outer Flux Ks Ready=True, both HelmReleases Ready=True, healthz HTTP 200. Stale gitleaks (proxy-06-live-fixture.bats:38) and markdownlint citations corrected or removed (live `gitleaks detect --no-git --config .gitleaks.toml` returns 0 leaks; live `markdownlint-cli2` returns 0 errors).
  5. `.planning/todos/pending/2026-04-29-phase-7-hub-flux-observable-reconcile.md` resolved (auto-close target Phase 8 ran 2026-04-30 — close manually) and removed from pending or archived to `.planning/todos/completed/`.
  6. Nyquist VALIDATION.md ledgers closed for phases 7, 8, 10, 11 (status `final`, `nyquist_compliant: true`, `wave_0_complete: true` where the underlying Wave-0 RED bats scaffold became GREEN over the phase) — verified via `/gsd-validate-phase` per phase OR direct edits.
  7. Re-run `/gsd-audit-milestone v0.19` returns `passed` (no remaining gaps, no remaining `tech_debt` items).
**Plans**: 7 plans (6 Wave-1 parallel clusters + 1 Wave-2 audit-rerun gate)
- [ ] 12-01-PLAN.md — Cluster A: REQUIREMENTS.md flip (17 same-line checkbox flips + TEN-01 spec amend per D-11-07)
- [ ] 12-02-PLAN.md — Cluster C: STATE.md update (frontmatter last_activity / progress counters + Current Position block)
- [ ] 12-03-PLAN.md — Cluster D: 11-VERIFICATION.md + 11-PHASE-VERIFICATION.md supersedure (append `## Supersedure — 2026-05-11` H2 + frontmatter disposition_history)
- [ ] 12-04-PLAN.md — Cluster E: 5 VALIDATION.md ledger closes (phases 7, 8, 9, 10, 11 — Phase 9 included per T-3 / RESEARCH.md Open Q 1)
- [ ] 12-05-PLAN.md — Cluster F: stale Phase 7 hub-flux observable-reconcile todo git-mv pending → completed + closure appendix
- [ ] 12-06-PLAN.md — Cluster B: ROADMAP.md Progress-table verification (verify-only; commit 83b81bb already fixed this per RESEARCH.md Pitfall 1)
- [ ] 12-07-PLAN.md — Wave-2 gate: `/gsd-audit-milestone v0.19` re-run + Phase 12 self-close (ROADMAP + STATE + 12-VALIDATION flips) + human-verify checkpoint

## Progress

| Phase | Milestone | Plans | Status | Completed |
|-------|-----------|-------|--------|-----------|
| 1. Host Foundation | v0.18 | 9/9 | Complete | 2026-04-23 |
| 2. Cluster Layer | v0.18 | 7/7 | Complete | 2026-04-24 |
| 3. Flux Hub Bootstrap | v0.18 | 6/6 | Complete | 2026-04-27 |
| 4. Spoke Registration | v0.18 | 5/5 | Complete | 2026-04-28 |
| 5. Workloads + Health + Rebuild | v0.18 | 6/6 | Complete | 2026-04-28 |
| 6. Repo Hygiene + Docs + ADRs | v0.18 | 8/8 | Complete | 2026-04-29 |
| 7. Foundation: POC Seam + spoke-capsule + EKS Doc | v0.19 | 6/6 | Complete | 2026-04-29 |
| 8. Capsule + capsule-proxy Install | v0.19 | 5/5 | Complete | 2026-04-30 |
| 9. Tenants + Flux Multi-Tenancy Lockdown | v0.19 | 5/5 | Complete | 2026-04-30 |
| 10. Tenant Kubeconfigs + Proxy Round-trip | v0.19 | 3/3 | Complete | 2026-05-05 |
| 11. Validation + Graduation ADR-008 | v0.19 | 8/8 | Complete | 2026-05-07 |
| 12. v0.19 Close-out Reconciliation | v0.19 | 7/7 | Complete | 2026-05-11 |

---

*See `.planning/MILESTONES.md` for shipped-milestone summary index. Per-milestone full ROADMAP/REQUIREMENTS/AUDIT archives live under `.planning/milestones/`.*
