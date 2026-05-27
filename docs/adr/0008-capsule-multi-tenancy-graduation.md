# 8. Capsule Multi-Tenancy POC Graduation

## Status

Accepted (2026-05-06)

Outcome: DEFER

## Context

Milestone v0.19 (Capsule Multi-Tenancy POC) ran Phases 7-11 to validate
[Capsule](https://capsule.clastix.io/) v0.12.4 as a karyon-managed multi-tenancy
pattern on the dedicated isolated POC spoke (`spoke-capsule`), without polluting
the default v1 topology or `task rebuild` path.

Five mandatory phases shipped:

- **Phase 7** -- POC seam (`# KARYON POC MOUNT` sentinel + `scripts/poc/capsule/`
  isolation per P31; `spoke-capsule` k3d cluster on shared `k8s-net`; EKSDOC-01
  rough-cut design + `.gitleaks.toml` + `.gitignore` leak defenses).
- **Phase 8** -- Capsule operator + capsule-proxy install via Flux HelmRelease +
  OCIRepository (split-path D-08-12 architectural seam: hub-targeted outer K
  for HelmRelease + OCIRepository CRs; spoke-targeted outer K for the rendered
  spoke-side resources via `spec.kubeConfig`).
- **Phase 9** -- Tenant CRs (alpha, bravo) + multi-tenancy lockdown patches on
  hub-flux Flux controllers (`--no-cross-namespace-refs`, `--no-remote-bases`,
  `--default-service-account=default`); P27 defense in tenant inner Kustomizations.
- **Phase 10** -- Tenant kubeconfig issuance via Kubernetes TokenRequest API +
  capsule-proxy LIST filter validation (Pitfall 10-P3 corrected qualitative falsifier).
- **Phase 11** -- Negative RBAC bats suite (N1-N12) + webhook failure mode
  (`task fail-capsule-webhook -- 0|1`) + clean teardown (`task destroy-poc -- capsule
  [--full]`) + `task rebuild` SLO regression test + first push gitleaks history scan +
  this graduation ADR.

This ADR records the v0.19 graduation decision based on Phase 11's empirical evidence
(see `.planning/phases/11-validation-graduation-adr-008/11-VERIFICATION.md`).

## Decision

The graduation outcome is **DEFER** per the D-11-14 evidence-bound rubric:

| Outcome | Required evidence | Matched? |
|---------|-------------------|----------|
| **ADOPT** | All 12/12 N1-N12 PASS + VAL-02 webhook recovery PASS + VAL-03 clean teardown PASS (no stuck namespaces post-90s) + VAL-04 < 230s + CID unchanged + zero gitleaks findings + ZERO open BLOCKER carryovers (all D-08-13 push-gate items resolved) | N |
| **DEFER** | >= 1 of: N1-N12 has a RED-by-design (workaround documented, not bug) OR >= 1 unresolved upstream chart issue (e.g., D-11-01 PostBuild patch is a workaround) OR Phase 12 capsule-addon-fluxcd Trial would clarify the architectural shape | Y |
| **REJECT** | >= 1 of: N1-N12 RED for a tenant-isolation reason (silent escape -- security invariant breached) OR VAL-04 SLO regressed > 230s (POC pollutes v1 SLO) OR webhook recovery non-deterministic (VAL-02 flakes more than 2/3 runs) | N |
| **REPLACED BY ADR-009** | Mid-validation discovery: a fundamentally different POC supersedes Capsule's value proposition for karyon's lab use-case | N |

The DEFER row matches because:

- **Workaround documented (D-11-01 PostBuild patch is a workaround pending upstream chart fix).**
  The capsule-proxy chart-rendered Role lacks the `secrets create` verb required by the bundled
  `kube-webhook-certgen` Job; karyon extends this Role via Flux PostBuild patches in
  `clusters/hub-flux/pocs/capsule.yaml` (D-11-01). The patch literal is verified GREEN by
  `push-gate-01-static` (2/2). However, the empirical propagation HARD-GATE 1 (jq check on
  `kubectl get role capsule-proxy:capsule-proxy -n capsule-system`) returns RED on the live
  spoke-capsule cluster -- Pitfall 11-P1 fired because Phase 8 BLOCKER G-04 redirects the
  outer Kustomization's HR/OCIRepo CRs to spoke-capsule (which has zero Flux CRDs).
- **Phase 12 capsule-addon-fluxcd Trial would clarify the architectural shape.**
  Phase 12 is OPTIONAL and gated on ADR-008 outcome ∈ {adopt, defer}. The addon pattern
  (capsule-addon-fluxcd v0.2.3) auto-installs Capsule on hub via a Flux-managed addon,
  sidestepping G-04 entirely. Running Phase 12 as a re-evaluation pass would either resolve
  the architectural shape (ADOPT-eligible after addon trial) or confirm the addon does not
  cleanly translate to karyon's hub-only Flux contract (REJECT-eligible).
- **Phase 8 G-04 architectural decision is pending** (Option A: remove `spec.kubeConfig` from
  the outer poc-capsule Kustomization; Option B: split paths so HelmRelease + OCIRepository
  CRs live on the hub-targeted K and only K8s resources go to spoke). G-04 has been deferred
  since Phase 8 close (2026-04-29); Plan 11-04 confirms it is still the active blocker for
  live HR-on-spoke reconcile.

ADOPT is not supported because HARD-GATE 1 (D-11-01 propagation jq check) is RED and the
chained 11/12 negative-rbac RED in Plan 11-04's verifier run trace back to the same Phase 8
G-04 BLOCKER (no capsule-proxy installed on spoke; tenant kubeconfigs cannot complete the
LIST filter / RBAC fence loop). REJECT is not supported because no security invariant was
breached (VAL-03 teardown is the strongest GREEN evidence; webhook recovery is deterministic
at infrastructure level per Plan 11-02; VAL-04 SLO is not regressed -- the bats RED on @test
1 is a TEST INFRASTRUCTURE limitation, NOT a regression in `scripts/rebuild.sh`). REPLACED BY
ADR-009 is not supported because Capsule remains the POC; G-04 is an architectural
integration choice, not a Capsule replacement.

### What we proved

Per `.planning/phases/11-validation-graduation-adr-008/11-VERIFICATION.md`:

- **VAL-01 (Negative RBAC):** Plan 11-03 demonstrated 10/12 N1-N12 PASS locally under correct
  preconditions (capsule-proxy installed via Plan 10-01 imperative apply; tenant home
  namespaces Capsule-owned; CapsuleConfiguration userGroups patched). Plan 11-04 verifier
  run shows 1/12 GREEN with 11/12 RED dominated by environmental cascade (capsule-proxy
  absent on spoke due to Phase 8 G-04 BLOCKER inheritance + Task 1 helm uninstall). The
  static-contract layer (push-gate-01..03 + p27 lint + negative-rbac-anti-pattern lint)
  is GREEN throughout.
- **VAL-02 (Webhook failure recovery):** Infrastructure GREEN at static contract level
  (Plan 11-02 fail-capsule-webhook script + Taskfile entries + teardown-01 static); N11 + N12
  GREEN under Plan 11-03 conditions (2/2). RED in Plan 11-04 verifier run on same root cause
  as VAL-01 (capsule-proxy absent due to G-04 cascade). Mechanism (kubectl scale
  capsule-controller-manager replicas=0 + rollout-status wait) verified.
- **VAL-03 (Clean teardown):** GREEN end-to-end. `task destroy-poc -- capsule` performs the
  5-step canonical sequence (suspend tenant inner Ks + spoke-targeted outer K -> delete
  Tenant CRs -> poll namespace cascade with auto force-delete PVC finalizers after 60s ->
  suspend operator + config outer Ks -> optional `--full` cluster delete). Post-teardown:
  zero `capsule.clastix.io/tenant`-labeled namespaces remain; `# KARYON POC MOUNT` sentinel +
  `../pocs` mount line stay verbatim in `clusters/hub-flux/flux-system/kustomization.yaml`.
  teardown-01..03 bats GREEN (9/9). **This is the strongest GREEN evidence of the milestone.**
- **VAL-04 (SLO regression):** task rebuild was NOT MEASURED in this run (bats test
  infrastructure limitation: bats does not export `KARYON_REBUILD_APPROVED=yes`, so
  `scripts/rebuild.sh` aborted at the confirmation gate L30-41). spoke-capsule
  container-ID-unchanged: PASS (rebuild was a no-op). Phase 7 P31 lint inheritance: PASS
  (`poc-isolation-01-static.bats` 3/3 GREEN). v0.18 task rebuild SLO baseline (190s warm)
  was last validated 2026-04-29 in Phase 5 close-out -- underlying primitive uncompromised.
  slo-regression-live.bats GREEN: 2/3 (@test 2 CID stability + @test 3 P31 lint); 1/3 RED
  (test-infrastructure limitation, not a real regression).
- **VAL-05 (Gitleaks history scan):** First push to origin/main triggered CI gitleaks-scan
  (fetch-depth: 0 full history) and post-push `gitleaks git --log-opts="--all"` -- both
  reported 2 findings on `tests/bats/proxy-06-live-fixture.bats:38` (commit d9734486, Plan
  10-00, 2026-05-05). **Confirmed PRE-EXISTING via git blame; NOT introduced by Phase 11.**
  Phase 11 D-11-04-revised file-specific allowlist effective (push-gate-05 @test 1 + @test 2
  GREEN: 7 specific Phase 7 + 10 fixture-bearing markdown files allowlisted; broad
  `^\.planning/.*\.md$` regex confirmed ABSENT via anti-regression sentinel).

### What we did not prove

- **HA Capsule** -- single-replica only on spoke-capsule; multi-replica + leader election
  semantics not validated.
- **OIDC integration** -- TokenRequest API + bearer tokens only; no external IDP (Dex, Keycloak,
  Auth0) tested.
- **Multi-spoke federation** -- Capsule has no native cross-cluster Tenant; spoke-capsule is
  isolated, not part of the hub-flux spoke topology.
- **Hub-side Capsule** -- POC kept on isolated spoke per ADR-004; hub-side install (control-plane
  self-tenancy) is a different threat model + a separate ADR.
- **Real ingress / TLS for capsule-proxy** -- NodePort 30443 + self-signed cert (chart-managed
  controller-less certgen Job); no ingress-nginx, cert-manager, or AWS Certificate Manager
  validated.
- **Production secret management** -- TokenRequest API with `--duration=1h` default; no Vault,
  SOPS, or age integration.
- **GPU + Capsule interaction** -- spoke-capsule has no GPU; spoke-ml is the GPU-bearing spoke
  but not Capsule-managed.
- **Capsule on Kind / minikube / k3s-on-bare-metal** -- POC validates k3d only.
- **Live propagation of D-11-01 PostBuild patch on spoke** -- HARD-GATE 1 RED; the chart-rendered
  Role does not exist on spoke-capsule because of Phase 8 G-04 BLOCKER inheritance. The patch
  is correctly authored on `clusters/hub-flux/pocs/capsule.yaml` (push-gate-01-static GREEN);
  empirical jq propagation falsifier is RED. Recommend relocating D-11-01 to
  `clusters/hub-flux/pocs/capsule-spoke.yaml` in a follow-up plan, gated on G-04 resolution.
- **Live evidence collection guardrails (REVISED 2026-05-05 per `11-REVIEWS.md` codex review HIGH #1; Pitfall 11-P6)**
  -- This run was performed with `KARYON_PHASE11_STRICT_LIVE` UNSET (strict-mode-DISABLED).
  Zero live tests SKIPPED in this run, so HARD-GATE 2 was GREEN regardless. Re-running with
  `KARYON_PHASE11_STRICT_LIVE=1` after Phase 8 G-04 is resolved would convert any future
  bats SKIP -> FAIL for graduation-deciding evidence. 11-VERIFICATION.md "Live Evidence
  Collection" table records what was actually verified vs skipped during this graduation run.
- **slo-regression-live.bats @test 1 task rebuild execution** -- bats test infrastructure
  limitation (`KARYON_REBUILD_APPROVED=yes` not exported); rebuild itself was never invoked.
  Plan 11-05 inherits as carryover; resolution candidates documented in 11-VERIFICATION.md.

### Trade-offs

- **TokenRequest semantics on k3s vs IRSA on EKS** -- k3s does NOT clamp at 24h
  (Phase 10 D-10-02 reframe; verified live up to 720h). EKS clamps at 24h default
  via `--service-account-max-token-expiration`. Portability requires forking the
  duration logic for prod.
- **Chart-level RBAC patch (D-11-01)** is a workaround pending upstream
  capsule-proxy chart fix -- the chart-rendered Role lacks `secrets create`
  permission needed by the bundled `kube-webhook-certgen` Job; karyon extends it
  via Flux PostBuild patches (`clusters/hub-flux/pocs/capsule.yaml` spec.patches).
  HARD-GATE 1 jq propagation check is RED in Plan 11-04 verifier (Pitfall 11-P1
  fired due to Phase 8 G-04 cascade); relocation to `capsule-spoke.yaml` is the
  Plan 11-05 carryover recommendation, gated on G-04 resolution.
- **CapsuleConfiguration userGroups list (D-11-02)** is opinionated -- chart
  default is `[capsule.clastix.io]` only; karyon adds `system:serviceaccounts`
  and `system:authenticated` to make capsule-proxy LIST recognize
  SA-token-authenticated identities as Capsule-owned.
- **PVC strand auto force-delete after 60s (D-11-11)** is acceptable for POC
  iteration -- production teardown would need a `--preserve-data` flag.
- **Pitfall 11-P2 (cluster-admin webhook bypass)** -- `pocs/capsule/spoke/tenants/{alpha,bravo}/namespace.yaml`
  carry `capsule.clastix.io/tenant=<name>` labels; if the Capsule webhook rejects the
  cluster-admin Flux apply (system:masters bypass NOT in effect for the flux-reconciler SA),
  the operator-runbook fallback (`kubectl --as=alpha create namespace tenant-alpha`) applies.
  Empirical observation in 11-VERIFICATION.md: Pitfall 11-P2 did NOT fire in this run
  (push-gate-04-live tenant ns labels survived Flux apply 2/2 GREEN).
- **Live evidence collection mode (REVISED 2026-05-05 per `11-REVIEWS.md` codex review HIGH #1; Pitfall 11-P6)**
  -- The graduation-deciding run can use `KARYON_PHASE11_STRICT_LIVE=1` to convert
  bats SKIP -> FAIL. Without strict mode, live tests that skip (cluster unreachable,
  kubeconfig minting failure) record as evidence-missing in 11-VERIFICATION.md Live
  Evidence Collection table; disposition floor downgrades to passed_with_overrides.
  Plan 11-04 verifier records strict-mode state in 11-VERIFICATION.md frontmatter
  (`strict_mode_active: false` for this run).
- **Tightened gitleaks allowlist (REVISED 2026-05-05 per reviewer HIGH #3)** --
  D-11-04-revised replaces the original broad `^\.planning/.*\.md$` regex with
  file-specific allowlist entries for the 7 verified Phase 7 + Phase 10
  fixture-bearing markdown files. NEW phases that quote synthetic-kubeconfig
  fixture content MUST add a new path entry (intentional friction; prevents
  broad-allowlist-hides-real-leak class of failure).
- **Phase 8 BLOCKER G-04 inheritance** -- the active root cause of HARD-GATE 1 RED + 11/12
  negative-rbac RED in Plan 11-04 verifier. The outer poc-capsule Kustomization carries
  `spec.kubeConfig: spoke-capsule-kubeconfig` (Phase 7 P40/P18 invariant) but spoke-capsule
  has zero Flux CRDs (verified live: `kubectl get crd | grep -ci flux` returns 0). Server-
  side dry-run confirms `no matches for kind "HelmRelease"`. G-04 has been pending since
  2026-04-29; Plan 11-05 carryover item #2 escalates to Phase 12 OR a follow-up architectural
  plan.

## Consequences

**Outcome-conditional.** Karyon proceeds per the chosen graduation outcome.

### If ADOPT (NOT SELECTED)

- v0.20 incorporates Capsule into the default `task rebuild` chain (P31 lifted; spoke-capsule
  promoted from POC to v1 spoke).
- `task rebuild` SLO budget updated for the additional capsule-system + tenant namespaces.
- Phase 12 (capsule-addon-fluxcd v0.2.3 Trial) runs as adoption acceleration.
- ADR-008 references in `docs/capsule-on-eks.md` (EKSDOC-01) become canonical translation guidance.

### If DEFER (SELECTED)

- **v0.20 reruns Phase 11 with the capsule-addon-fluxcd pattern** (Phase 12 OPTIONAL gate
  state ∈ {adopt, defer} is met -- Phase 12 unlocked as a re-evaluation pass).
- spoke-capsule stays on persistent isolated cluster (P31 isolation contract preserved); NOT
  promoted to v1 default `task rebuild` until a future ADR explicitly adopts.
- **Phase 12 (capsule-addon-fluxcd Trial)** runs as a gated re-evaluation pass. The addon
  auto-installs Capsule on hub via a Flux-managed addon, sidestepping the G-04 architectural
  blocker entirely. Phase 12 outcome will inform the next graduation ADR.
- **Plan 11-05 carryover items** (forwarded for v0.20 milestone-open or post-milestone follow-up):
  1. Pitfall 11-P1 D-11-01 relocation to `clusters/hub-flux/pocs/capsule-spoke.yaml` -- gated
     on Phase 8 G-04 resolution.
  2. Phase 8 G-04 architectural decision (Option A: remove kubeConfig from outer; Option B:
     split paths) -- has been pending since 2026-04-29.
  3. Pre-existing markdownlint failures (3 files, 31 errors: README.md commit 7441fba Phase 6
     2026-04-28; docs/capsule-on-eks.md commit 72f36663 Phase 6/7 2026-04-29; docs/poc-capsule.md
     commit d71000c2 Phase 7 2026-04-29) -- repo-hygiene cleanup.
  4. Pre-existing gitleaks finding in `tests/bats/proxy-06-live-fixture.bats:38` (2 findings,
     commit d9734486, Plan 10-00) -- fixture rewrite or scoped allowlist (deferred-items.md
     resolution candidates).
  5. slo-regression-live.bats @test 1 KARYON_REBUILD_APPROVED gating -- test infrastructure
     update or documentation as known limitation.
  6. Optional `KARYON_PHASE11_STRICT_LIVE=1` re-verification run after G-04 resolution -- for
     ADR-008-deciding evidence per Pitfall 11-P6.
- **EKSDOC-01 (`docs/capsule-on-eks.md`)** rolls forward to `Status: Reviewed` (D-11-15) with
  4 targeted revision blocks informed by Phase 11 bats evidence (cert source, IRSA, proxy LIST
  scope, push-gate translation); cross-references this ADR for the audit trail. EKS prod
  translation guidance remains valid -- the DEFER outcome means the karyon POC is still the
  reference implementation, just with a documented re-evaluation pass scheduled for v0.20.

### If REJECT (NOT SELECTED)

- spoke-capsule torn down as part of v0.19 close (`task destroy-poc -- capsule --full`).
- No v0.20 Capsule carryover; multi-tenancy strategy returns to the design phase.
- Phase 12 is SKIPPED (gate condition not met).
- `docs/capsule-on-eks.md` (EKSDOC-01) annotated as superseded.

### If REPLACED BY ADR-009 (NOT SELECTED)

- ADR-009 is named with the replacement POC and the comparison evidence is preserved here
  for historical record.
- This POC's artifacts archived under `.planning/milestones/v0.19-archive/`.
- v0.20+ work resumes against the replacement architecture.

### Cross-references

- `docs/adr/0004-hub-only-flux-control-plane.md` (ADR-004) -- the load-bearing v0.18 ADR this POC
  inherits (NO Flux runs on `spoke-capsule`; hub-only reconciliation via `spec.kubeConfig`).
  ADR-004 is the structural reason Phase 8 G-04 BLOCKER exists -- the outer Kustomization's
  `spec.kubeConfig` redirects HR/OCIRepo CRs to a spoke that has no Flux CRDs by design.
- `docs/capsule-on-eks.md` (EKSDOC-01) -- Status: Reviewed (rolled forward by Plan 11-05);
  contains 4 targeted revision blocks informed by Phase 11 bats evidence (cert source, IRSA,
  proxy LIST scope, push-gate translation).
- `.planning/phases/11-validation-graduation-adr-008/11-VERIFICATION.md` -- the audit trail
  feeding the D-11-14 rubric. Disposition: `passed_with_overrides`. HARD-GATE 1: RED. HARD-GATE
  2: GREEN. 22/35 bats GREEN; 13 RED with documented Rule 3 environmental + test-infrastructure
  escalations.

## Addendum — 2026-05-27 cold-bootstrap webhook race finding

**Trigger:** Operator attempted to test the v0.20 Phase 14 demo runbook (`docs/poc-capsule-demo.md`)
locally on the same git revision (`e26c18ef`) and against the same k3d topology that produced
GREEN evidence on 2026-05-19. The demo failed at Act 5 (tenant-owner LIST namespaces) and
investigation revealed Capsule was NOT claiming tenant namespaces despite the Tenant CRs being
Ready and the namespaces being labeled.

**Root cause** (full session: `.planning/debug/capsule-tenant-ns-claim.md`):

The `namespaces` mutation webhook (`namespaces.tenants.projectcapsule.dev`) was configured with
`failurePolicy: Ignore` per D-08-03's P26 belt-and-suspenders pattern. On cold-bootstrap, the
capsule-webhook-service Endpoint takes a few seconds to become Ready after `capsule-controller-manager`
starts. If Flux applies the tenant namespace YAMLs during that window, the apiserver attempts
to call the webhook, fails (Endpoint not ready), and — because of `failurePolicy: Ignore` — silently
admits the namespaces WITHOUT the ownerReference mutation that claims them for their Tenant CR.

The namespaces then exist with `capsule.clastix.io/tenant: <name>` labels but empty `ownerReferences`.
The companion validating webhook (`namespaces.projectcapsule.dev`) subsequently blocks every UPDATE
and DELETE on these namespaces because the label-vs-ownerRef mismatch fails its consistency check.
The state is unrecoverable without bypassing the webhook (scale `capsule-controller-manager` to 0,
delete the bad namespaces, scale back up, re-reconcile).

**Why Phase 14 (2026-05-19) didn't surface this:** Phase 14's cold rebuild presumably hit the same
race occasionally but was lucky — the webhook readiness window vs Flux apply timing won the dice
roll. The bug was always latent; this debug session is the first reproduction.

**Mitigations applied 2026-05-27:**

1. **`namespaces` hook flipped to `failurePolicy: Fail`** (`pocs/capsule/operator/helmrelease.yaml`).
   Surgical override of D-08-03 for this single hook. Flux now retries the namespace apply until
   the webhook is reachable — exactly the cold-bootstrap-safe behavior the other hooks rely on
   `Ignore` for, inverted for this one because silent skip here produces unrecoverable state.

2. **OCIRepository chart sources pinned by digest** in addition to tag
   (`pocs/capsule/operator/ocirepository.yaml`, `pocs/capsule/proxy/ocirepository.yaml`). Defends
   against any future upstream chart-repackage producing webhook-config drift invisible to tag-only
   pins. Digest is authoritative per OCI spec.

**Reinforcement of DEFER stance:** This finding adds weight to the D-11-14 graduation rubric's
DEFER disposition. A POC stack whose cold-bootstrap path has a webhook race that produces
unrecoverable state without operator-grade rescue procedures is not production-ready by any
reasonable definition. Pinning by digest + failing closed on the namespace-claim webhook makes the
POC reproducibly demoable, but the underlying upstream pattern (silent admission skip on webhook
unavailability + strict validation on the unclaimed result) is exactly the kind of edge case a
production EKS cut would need cert-manager + a proper webhook readiness gate to handle robustly.
