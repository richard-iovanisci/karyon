# Phase 8: Capsule + capsule-proxy Bare-Minimum Install - Context

**Gathered:** 2026-04-29
**Status:** Ready for planning
**Mode:** `--auto` (Claude selected recommended defaults across all gray areas; no interactive questions)

<domain>
## Phase Boundary

Land the Capsule operator and capsule-proxy on `spoke-capsule` via two **separate** Flux HelmReleases reconciled hub-only. Phase 8 succeeds when:

1. **CAP-01** — `capsule:0.12.4` (OCI `ghcr.io/projectcapsule/charts/capsule`) HelmRelease reports `Ready=True`, `capsule-controller-manager` pod is `Running` on spoke-capsule.
2. **CAP-02** — `capsule-proxy:0.12.0` HelmRelease (separate, NOT umbrella `proxy.enabled=true`) is reachable: `curl -k https://127.0.0.1:30443/healthz` returns 200; `service.type: NodePort + service.nodePort: 30443`; `additionalSANs: [127.0.0.1, localhost]`.
3. **CAP-03** — All 7 Capsule CRDs (`Tenant`, `CapsuleConfiguration`, `GlobalTenantResource`, `TenantResource`, `ResourcePool`, `ResourcePoolClaim`, `TenantOwner`) installed and visible — `kubectl get crds | grep capsule.clastix.io` returns ≥7.
4. **ADR-004 invariant preserved** — `kubectl --context=k3d-spoke-capsule get pods -n flux-system` returns no Flux controllers (hub-only Flux unchanged).
5. **Phase 7 carryover (folded)** — Hub-Flux-observable reconcile of `poc-capsule` outer Kustomization is positively verified: `flux get kustomization poc-capsule -n flux-system --context k3d-hub-flux` reports `Ready=True` against a post-Phase-7 source revision, AND both HelmReleases (`flux get helmrelease capsule -n capsule-system --context k3d-spoke-capsule`, `flux get helmrelease capsule-proxy -n capsule-system --context k3d-spoke-capsule`) report `Ready=True`. If outer `poc-capsule` is NOT Ready=True, treat as a Phase 7 SEAM defect (gap-close back to Phase 7 with `/gsd-plan-phase 7 --gaps`), NOT a Phase 8 install defect.

**Phase 8 ships operator + proxy install ONLY.** All of the following are explicitly **out of scope** for Phase 8 (each owned by a later phase):

- `CapsuleConfiguration/default` singleton CR with `forceTenantPrefix: true` / `allowServiceAccountPromotion: true` → **Phase 9** (TEN-01..03 — tenant-relevant policy)
- Hub-Flux multi-tenancy lockdown flag patches (`--no-cross-namespace-refs=true`, `--no-remote-bases=true`, `--default-service-account=default`) and `flux-system` Kustomization `spec.serviceAccountName: kustomize-controller` → **Phase 9** (TEN-05)
- `Tenant` CR creation (alpha + bravo) and tenant inner Flux Kustomizations with P27 `spec.serviceAccountName` → **Phase 9** (TEN-01..06)
- `dependsOn: tenants → operator with wait: true` (P32 CRD ordering) → **Phase 9** (TEN-06)
- Tenant owner kubeconfigs + capsule-proxy round-trip + LIST visibility → **Phase 10** (PROXY-01..03)
- Negative RBAC suite, webhook failure recovery, ordered teardown, graduation ADR-008 → **Phase 11** (VAL-01..06)

> **Important calibration vs. research SUMMARY.md:** `.planning/research/SUMMARY.md` §"Phase 9 — Capsule + capsule-proxy Install + Flux Lockdown Patches" bundles lockdown patches + `CapsuleConfiguration` + `dependsOn` chain into the same phase as operator install. The v0.19 ROADMAP / REQUIREMENTS pass (post-research synthesis) deliberately **un-bundled** these — Phase 8 = bare-minimum install + verifiability; Phase 9 = lockdown + tenants. Treat the research §"Phase 9" plan-time recommendation as research, not as a Phase 8 boundary expansion. Plans MUST hew to the narrower CAP-01..03 scope.

</domain>

<decisions>
## Implementation Decisions

### `pocs/capsule/` directory layout (D-08-01)

- **D-08-01:** Two-subdir layout under `pocs/capsule/` — `pocs/capsule/operator/` for the Capsule operator manifests, `pocs/capsule/proxy/` for capsule-proxy manifests. Top-level `pocs/capsule/kustomization.yaml` (currently `resources: []`, Phase 7 placeholder) is rewritten to `resources: [operator/, proxy/]`. NOT flat (everything at one level).
  - **Rationale:** Mirrors research §"Phase 9 — pocs/capsule/operator/, pocs/capsule/proxy/" naming so Phase 9's tenants/ subdir + Phase 11's ordered teardown `dependsOn` both compose cleanly. Each component has self-contained `OCIRepository + HelmRelease + values ConfigMap (optional)` and a local `kustomization.yaml` that the parent kustomize-build resolves recursively. Sets the surface for Phase 9's `pocs/capsule/config/` (CapsuleConfiguration) and `pocs/capsule/tenants/<name>/` to slot in without rework.

### OCIRepository source pattern (D-08-02)

- **D-08-02:** **Per-chart `OCIRepository`** — one `OCIRepository` named `capsule` covering `oci://ghcr.io/projectcapsule/charts/capsule`, one named `capsule-proxy` covering `oci://ghcr.io/projectcapsule/charts/capsule-proxy`. Each lives next to its corresponding `HelmRelease` (`pocs/capsule/operator/` and `pocs/capsule/proxy/` respectively). NOT a single shared `OCIRepository` covering both.
  - **Rationale:** Clean failure isolation — when one chart's source is mid-fetch failure, the other's HelmRelease reconcile is unaffected. Each `HelmRelease.spec.chartRef` points at the local `OCIRepository` by name, mirroring `clastix/flux2-capsule-multi-tenancy` upstream reference layout. Slight YAML duplication is the intentional cost of decoupling.

### Operator webhook `failurePolicy` override (P26 — D-08-03)

- **D-08-03:** Apply `failurePolicy: Ignore` override on the Capsule operator's webhooks via the operator HelmRelease values block, scoped with `matchConditions` so the webhooks NoOp when no `capsule.clastix.io/tenant` label is present on the target object. Belt-and-suspenders: ChartConfig already has objectSelector defaults, but explicit override insulates the Phase 8 → Phase 9 transition window where tenants exist but cluster has been freshly bootstrapped.
  - **Rationale:** Between Phase 8 install and Phase 9 tenant landing, every `kubectl create pod` against `default` ns triggers Capsule's ValidatingWebhookConfiguration. With chart defaults, fail-closed semantics could theoretically reject a pod create if the operator briefly restarts. `failurePolicy: Ignore` + `matchConditions` is the documented Capsule-recommended fail-open posture for clusters without tenants. Cost: ~10 lines of HelmRelease values block. Reverify in Phase 11 negative-RBAC suite.

### Operator TLS — built-in certgen vs cert-manager (P34 — D-08-04)

- **D-08-04:** **Built-in certgen** — set `tls.enableController: true` in the Capsule operator HelmRelease values. Chart-managed self-signed cert with auto-rotation hooks. NO cert-manager.
  - **Rationale:** cert-manager is NOT in v0.19 scope (PROJECT.md Out-of-Scope). Adding it for the POC is gold-plating. Built-in certgen is documented as fully functional for Capsule operator webhooks; the only downside (no cross-pod cert sharing) doesn't apply since the operator runs single-replica per Phase 8 + ADR-008's "what we did not prove → HA Capsule" framing.

### Inner kustomization.yaml replacement (D-08-05)

- **D-08-05:** Phase 7's placeholder `pocs/capsule/kustomization.yaml` (currently `resources: []`, Pitfall-7 defense for empty path) is **rewritten** in Phase 8 (NOT preserved alongside subdir manifests). New top-level: `apiVersion: kustomize.config.k8s.io/v1beta1; kind: Kustomization; resources: [operator/, proxy/]`. The Phase 7 comment block at the head of the file is preserved (REQ-CAPCLU-02 / Pitfall-7 attribution) with an appended Phase 8 update note.
  - **Rationale:** The single outer Flux `Kustomization poc-capsule` (`spec.path: ./pocs/capsule`, defined in `clusters/hub-flux/pocs/capsule.yaml`) does its kustomize-build over the whole `pocs/capsule/` tree. Subdir refs (`operator/`, `proxy/`) let kustomize resolve recursively without spawning additional Flux Kustomization CRDs. Single-Flux-Kustomization is the v0.18 spoke pattern (one per spoke).

### HelmRelease reconcile interval (D-08-06)

- **D-08-06:** Explicit **`interval: 5m`** on both HelmReleases (`capsule` and `capsule-proxy`). Matches the outer `clusters/hub-flux/pocs/capsule.yaml` Kustomization's own `interval: 5m`. NOT default Flux interval (10m if unset).
  - **Rationale:** Predictable cadence; faster iteration if a HelmRelease needs re-trigger during Phase 8 development; matches v0.18 spoke Kustomization cadence. Cost: 1 line each. Slight controller load increase is acceptable for the 2-HelmRelease POC scope.

### Proxy `dependsOn` operator (D-08-07)

- **D-08-07:** Add `spec.dependsOn: [{ name: capsule, namespace: capsule-system }]` with **`spec.dependsOn[*].wait: true`** on the **`capsule-proxy` HelmRelease**. Proxy HelmRelease reconcile blocks until operator HelmRelease reports `Ready=True`. NO mutual `dependsOn` (operator does NOT depend on proxy).
  - **Rationale:** Proxy's runtime depends on operator-installed CRDs (specifically `Tenant` for proxy LIST filtering rules). Without `dependsOn`, proxy may attempt to start before CRDs land, generating noisy log output and brief CrashLoopBackOff. `wait: true` is cheap insurance (one-line YAML, ≤30s extra reconcile time on cold install). Avoids "first install looks broken because of cosmetic timing".

### CapsuleConfiguration CR scope — defer to Phase 9 (D-08-08)

- **D-08-08:** **Defer** the singleton `CapsuleConfiguration/default` CR to **Phase 9**. Phase 8 lands ONLY the operator HelmRelease + proxy HelmRelease; the `CapsuleConfiguration` CRD itself (registered by the operator chart) is the only Phase 8 artifact in this category. Phase 9 (TEN-01..03) lands the CR with `forceTenantPrefix: true` + `allowServiceAccountPromotion: true` because those flags are tenant-relevant policy.
  - **Rationale:** CAP-03 only requires the CRDs visible. Operator runs without an explicit `CapsuleConfiguration/default` (chart provides defaults at runtime). Landing the CR in Phase 8 and then patching it in Phase 9 is two diffs where one would do. Keeps Phase 8 scope ruthlessly narrow. Re-validates research SUMMARY.md §"Phase 9" deliberately split across our Phase 8 + 9.

### Test scaffolding pattern — repeat Phase 7's Wave 0 RED bats (D-08-09)

- **D-08-09:** **Repeat the Phase 7 Wave 0 pattern** — Plan 08-00 lands ALL Phase 8 bats (every static contract + every live HelmRelease/CRD/proxy probe) BEFORE any HelmRelease yaml lands. Subsequent plans (08-01 operator, 08-02 proxy, 08-03 verifier or whatever the planner shapes) make the bats green by landing actual yaml. Live-only bats (`flux get helmrelease`, `kubectl get crds`, `curl -k :30443/healthz`) are gated by a runtime probe so they auto-skip when the cluster is not yet up — same gating pattern as Phase 5 / Phase 7.
  - **Rationale:** Nyquist gate worked in Phase 7 (39 tests across 8 bats files all green after Waves 1-3). No "implement and test in same plan" anti-pattern. Pure win — already-validated pattern.
  - **Concrete Phase 8 bats coverage** (planner expands; this is the floor):
    - **Static (Wave 0):** Two-HelmRelease pattern enforcement (NOT umbrella `proxy.enabled=true`); chart name + version pin literals (`capsule:0.12.4`, `capsule-proxy:0.12.0`); per-chart `OCIRepository` shape (D-08-02); proxy `service.type: NodePort + service.nodePort: 30443`; proxy `additionalSANs: [127.0.0.1, localhost]`; operator `tls.enableController: true`; operator `failurePolicy: Ignore` + `matchConditions`; outer `pocs/capsule/kustomization.yaml` lists subdir refs; `dependsOn: capsule wait: true` on proxy; HelmRelease `interval: 5m` literals; ADR-004 anti-grep — bats grep `clusters/hub-flux/pocs/capsule.yaml` for `kubeConfig.secretRef.name: spoke-capsule-kubeconfig` AND `key: value.yaml` (P18 / D-11 inheritance).
    - **Live (Waves 1-2):** Outer poc-capsule Kustomization Ready=True (folded carryover); HelmRelease capsule Ready=True; HelmRelease capsule-proxy Ready=True; capsule-controller-manager pod Running on spoke-capsule; ≥7 capsule.clastix.io CRDs installed; `curl -k https://127.0.0.1:30443/healthz` returns 200; ADR-004 invariant — `kubectl --context=k3d-spoke-capsule -n flux-system get pods` returns no flux controllers.
    - **POC isolation regression:** Re-run Phase 7's `tests/bats/poc-isolation-01-static.bats` to confirm Phase 8's new files under `pocs/capsule/operator/` + `pocs/capsule/proxy/` did NOT introduce `spoke-capsule` mentions in v0.18 scripts.

### k3d port-publish flag confirmation (D-08-10)

- **D-08-10:** Phase 7's `scripts/poc/capsule/create-cluster.sh` already locked the port-publish form. Phase 8 does NOT modify cluster create flags. Phase 8 verifier just reads the existing cluster's NodePort 30443 reachability from the WSL host — if `curl -k https://127.0.0.1:30443/healthz` fails post-install, that's a Phase 7 cluster-shape defect (gap-close back to Phase 7), NOT a Phase 8 chart-config defect.
  - **Rationale:** Phase 7 already shipped CAPCLU-01 (cluster create with `--port "30443:30443@server:0"` or equivalent — verified live by milestone owner). Phase 8 inherits and verifies, does not re-decide.

### Claude's Discretion

The following gray areas are intentionally NOT specified — planner/researcher should default to v0.18 + Phase 7 patterns and note the chosen approach in PLAN.md without re-asking:

- **HelmRelease values shape — values inline vs ConfigMap** — recommended default: **values inline** in the HelmRelease `spec.values` block for Phase 8's small surface (proxy NodePort/SAN tuning, operator certgen + failurePolicy override). Promote to a `ConfigMap`-referenced values pattern in Phase 9 if/when tenant-specific values templating becomes the right shape.
- **Operator namespace** — recommended default: **`capsule-system`** (chart default). HelmRelease `spec.targetNamespace: capsule-system` + `spec.install.createNamespace: true`. Mirrors clastix upstream README.
- **`kubectl --context` vs `KUBECONFIG=` invocation in bats live tests** — recommended default: **`kubectl --context=k3d-{cluster}`** explicit form (matches Phase 7 bats pattern; clean failure mode if context is missing; never reads ambient KUBECONFIG).
- **Plan ordering inside Phase 8** — recommended default: Plan 08-00 (Wave 0 bats RED scaffold landing all D-08-09 bats) → Plan 08-01 (operator HelmRelease + OCIRepository, makes operator-related bats green) → Plan 08-02 (proxy HelmRelease + OCIRepository, makes proxy-related bats green) → Plan 08-03 (verifier — live HelmRelease Ready=True observation + ADR-004 anti-grep + POC isolation regression rerun, closes folded carryover). Planner may reshape into 2 or 4 plans without re-asking.
- **`task` surface extensions** — recommended default: **none**. Phase 8 lands no new top-level `task ...` targets. The install path is Flux-driven (commit yaml → hub-flux reconciles); verifiers run as `bash scripts/poc/capsule/verify-install.sh` if the planner wants a script wrapper, OR purely as bats. Do NOT add `task install-capsule` (would be sugar; install is already declarative via Flux).
- **`HelmRelease.spec.upgrade.crds` policy** — recommended default: **`CreateReplace`** for the operator chart (CRDs are reconciled on chart upgrade; documented Capsule operator chart contract). Proxy chart has no CRDs.
- **Reconcile loop noise tolerance window** — recommended default: After Plan 08-01 (operator) lands and Wave 1 bats run, allow ≤2 reconcile cycles (≤10 min) for HelmRelease to reach `Ready=True` before treating as failure. After Plan 08-02 (proxy) with `dependsOn`, allow ≤1 additional cycle (≤5 min). Live-bats retry budget: 3 attempts with 30s sleep between.

### Folded Todos

- **Phase 7 carryover — hub Flux observable reconcile of `poc-capsule` Kustomization** (`.planning/todos/pending/2026-04-29-phase-7-hub-flux-observable-reconcile.md`, `resolves_phase: 8`). Phase 7 verification item 1b — runtime Flux observation of `Ready=True` on the outer `poc-capsule` Kustomization — could not be observed during Phase 7 because hub-flux Flux is reconciling from `origin/main@1f2da1d3` (v0.18 close-out state) and post-Phase-7 commits are not yet pushed. The script-internal P18 silent-misroute falsifier in `register-poc-cluster.sh` step 4 PASSED on user's first run (stronger guarantee than Flux runtime observation), but the seam-through-Flux-runtime path observation was deferred. **Phase 8 fold:** Make this a load-bearing acceptance criterion — Phase 8 verifier MUST observe `flux get kustomization poc-capsule -n flux-system --context k3d-hub-flux Ready=True` against a post-Phase-7 source revision AND both HelmReleases (`capsule`, `capsule-proxy`) Ready=True. If outer `poc-capsule` is NOT Ready=True, treat as Phase 7 SEAM defect (gap-close to Phase 7 with `/gsd-plan-phase 7 --gaps`), NOT Phase 8 install defect. This is the natural exercise — Phase 8 install through the seam is what Phase 7 was preparing for. Todo auto-closes when `/gsd-execute-phase 8` completes (per `resolves_phase: 8` and execute-phase.md `close_phase_todos` step). Documented in domain boundary point #5 above.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project planning artifacts (REQUIRED reading)

- `.planning/REQUIREMENTS.md` — CAP-01, CAP-02, CAP-03 contracts; load-bearing P26/P27/P29/P31 invariants; ADR-004 inheritance; KARYON POC MOUNT location lock.
- `.planning/ROADMAP.md` (Phase 8 section + Phase 9 boundary call-out for un-bundling rationale) — phase goal, ordered success criteria, dependency declarations, scope-tightening rationale.
- `.planning/PROJECT.md` — v0.19 out-of-scope items (cert-manager, OIDC, prod ingress, multi-spoke federation, hub-side Capsule, default platform adoption); ADR-004 hub-only invariant; public-repo secrets contract.
- `.planning/STATE.md` — milestone-open decisions: 6-phase split rationale, two-HelmRelease decision, P27/P29/P31 invariants; Phase 7 close-out blockers (lockdown patch regression risk on Phase 9, capsule-addon-fluxcd compat MEDIUM-confidence).

### Phase 7 artifacts — REQUIRED context (Phase 8 inherits everything Phase 7 shipped)

- `.planning/phases/07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc/07-CONTEXT.md` — D-05 through D-17 (POC seam shape, spoke-capsule pins, P18 inheritance on outer Kustomization, P31 isolation contract, ADR-004 preservation invariant).
- `.planning/phases/07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc/07-RESEARCH.md` — Phase 7 research findings (Capsule chart pin verification, k8s ≥1.34.0 floor confirmation, P26 webhook failurePolicy interaction with objectSelector, P34 certgen lifecycle).
- `.planning/phases/07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc/07-VERIFICATION.md` — Phase 7 verification status (item 1a passed, 1b deferred → folded into Phase 8 here).
- `.planning/phases/07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc/07-HUMAN-UAT.md` — Phase 7 UAT split (1a / 1b split rationale; the load-bearing reason for the carryover todo).
- `.planning/phases/07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc/07-SUMMARY.md` files (07-00 through 07-05) — what each Phase 7 plan shipped (script + yaml shapes Phase 8 inherits).
- `.planning/phases/07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc/deferred-items.md` — Phase 7 deferred items (gitleaks planning-doc allowlist, hub-flux-observable reconcile — both surfaced as todos).

### Architecture Decision Records (load-bearing for Phase 8)

- `docs/adr/0001-single-wsl2-shared-docker-network.md` — k8s-net shared bridge; spoke-capsule already joined in Phase 7.
- `docs/adr/0002-k3d-over-kind.md` — k3d cluster runtime; `OCIRepository` reconciles work the same on k3d as on managed clusters.
- `docs/adr/0003-flux-over-argocd.md` — Flux 2 as GitOps tool; HelmRelease + HelmController is what Phase 8 exercises.
- `docs/adr/0004-hub-only-flux-control-plane.md` — **load-bearing**: NO Flux controllers run on spoke-capsule. Phase 8 verifier MUST grep-assert `kubectl --context=k3d-spoke-capsule get pods -n flux-system` returns no flux controllers.
- `docs/adr/0005-kubernetes-version-pin.md` — k3s `v1.34.6-k3s1` clears Capsule v0.12.x's k8s ≥ 1.34.0 floor with 6 patches of margin.

### Milestone-level research (REQUIRED for planning)

- `.planning/research/SUMMARY.md` §"Mental Model" + §"STACK §Capsule charts" + §"Phase 9 — Capsule + capsule-proxy Install + Flux Lockdown Patches" — chart pins, two-HelmRelease rationale, P26/P32/P33/P34 mitigations. **Note:** SUMMARY's "Phase 9" plan-time recommendation bundled lockdown patches with operator install; ROADMAP / REQUIREMENTS deliberately split — Phase 8 = bare-minimum install only; Phase 9 = lockdown + tenants + CapsuleConfiguration.
- `.planning/research/STACK.md` §"Capsule operator chart" + §"capsule-proxy chart" + §"capsule-addon-fluxcd" — version pins (`capsule:0.12.4`, `capsule-proxy:0.12.0`), OCI source URLs, k8s floor, addon compat MEDIUM-confidence flag.
- `.planning/research/ARCHITECTURE.md` §"Mental Model" + §"Phase 9 outer + inner reconcile" — HelmRelease + OCIRepository pattern; per-chart vs shared OCIRepository discussion.
- `.planning/research/PITFALLS.md` — P26-P43 catalogue. **Phase 8 directly addresses P26** (webhook failurePolicy + objectSelector — D-08-03), **P28** (NodePort host-publish — already locked Phase 7 D-10; Phase 8 verifies via curl), **P32** (CRD ordering — Phase 8 partial: proxy `dependsOn` operator with `wait: true` per D-08-07; Phase 9 owns the tenants→operator dependsOn for CRD-create-then-CR-apply ordering), **P33** (capsule-proxy SANs — D-08-03 / 08-CONTEXT not directly; covered by chart `additionalSANs: [127.0.0.1, localhost]` value), **P34** (built-in certgen — D-08-04), **P38** (chart upgrade webhook re-issue — risk acknowledged, deferred until first chart-pin bump). **Inherited from Phase 7:** P29 (kubeconfig leak — gitleaks rule already lives in `.gitleaks.toml`), P31 (POC isolation from `task rebuild` — Phase 8 verifier reruns Phase 7's static bats), P40 (P18 `key: value.yaml` invariant — outer `clusters/hub-flux/pocs/capsule.yaml` already correct; Phase 8 bats grep-asserts).
- `.planning/research/FEATURES.md` §"Capsule CRDs" — the 7 CRDs that Phase 8 CAP-03 verifies are visible; informs the bats grep target.

### v0.18 + Phase 7 reference implementations (analogs to mirror in Phase 8)

- `clusters/hub-flux/pocs/capsule.yaml` — outer Flux Kustomization for spoke-capsule with `spec.kubeConfig.secretRef.name: spoke-capsule-kubeconfig` + `key: value.yaml` (P18 inheritance / D-11). **Phase 8 does NOT modify this file.** Bats grep-asserts both literals are still present (regression gate against accidental Phase 8 edit).
- `clusters/hub-flux/pocs/kustomization.yaml` — pocs aggregator. **Phase 8 does NOT modify** (resources: [capsule.yaml] is the right shape for the lifetime of the milestone).
- `pocs/capsule/kustomization.yaml` — Phase 7 placeholder (`resources: []`). **Phase 8 rewrites to `resources: [operator/, proxy/]`** per D-08-05.
- `clusters/hub-flux/spokes/spoke-apps.yaml` — outer Flux Kustomization template (already mirrored by Phase 7 for `clusters/hub-flux/pocs/capsule.yaml`).
- `clusters/hub-flux/flux-system/gotk-components.yaml` — bootstrap-managed; contains the existing HelmController + SourceController CRDs that Phase 8's HelmReleases reconcile against. **DO NOT EDIT** (bootstrap-reverted on next Flux reconcile).
- `tests/bats/poc-mount-01-static.bats` + `tests/bats/poc-isolation-01-static.bats` + `tests/bats/poc-cluster-01-static.bats` — Phase 7 static contract bats. **Phase 8 reuses isolation bats verbatim** (Phase 8's new files under `pocs/capsule/operator/` + `pocs/capsule/proxy/` MUST NOT introduce `spoke-capsule` mentions in v0.18 scripts).
- `scripts/poc/capsule/create-cluster.sh` (Phase 7) — establishes spoke-capsule cluster shape Phase 8 inherits. Bats reads its `readonly POC_CLUSTER`/`POC_API_PORT`/`POC_NODEPORT` constants for source-of-truth literals.
- `scripts/poc/capsule/fix-dns.sh` (Phase 7) — establishes per-cluster CoreDNS recovery surface; Phase 8 references in user-facing failure-recovery docs but does not modify.
- `scripts/lib/preflight-lib.sh` — output helpers (`section`, `pass`, `warn`, `fail`, `info`, `have`). Any new Phase 8 verifier script (e.g., `scripts/poc/capsule/verify-install.sh` if planner adds one) sources this for v0.18 ergonomics.
- `tests/bats/test_helper` — shared loader pinning `REPO_ROOT`. Phase 8 bats files load this without modification.
- `tests/bats/preflight-pre*.bats` patterns — pattern for bats split by section/topic.
- `Taskfile.yml` — top-level task naming pattern. **Phase 8 expected to add NO new tasks** (per Claude's Discretion §"task surface extensions"). Verifier runs as bats / direct script invocation.

### External upstream references (informational; no edits)

- Capsule project — `https://capsule.clastix.io/` (linked from REQUIREMENTS.md).
- Capsule operator chart — `oci://ghcr.io/projectcapsule/charts/capsule:0.12.4`.
- capsule-proxy chart — `oci://ghcr.io/projectcapsule/charts/capsule-proxy:0.12.0`.
- clastix/flux2-capsule-multi-tenancy — upstream reference repo for the two-HelmRelease + per-chart OCIRepository pattern (research SUMMARY citation; informs D-08-01 / D-08-02 layout).
- Flux 2 HelmController API — `https://fluxcd.io/flux/components/helm/api/` (HelmRelease v2 spec — `spec.dependsOn`, `spec.chartRef`, `spec.values`, `spec.targetNamespace`, `spec.install.createNamespace`, `spec.upgrade.crds`).
- Flux 2 SourceController API — `https://fluxcd.io/flux/components/source/api/` (OCIRepository spec).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- **`clusters/hub-flux/pocs/capsule.yaml`** (Phase 7 D-11 — outer Flux Kustomization for spoke-capsule) — Phase 8 inherits unchanged. The `spec.path: ./pocs/capsule` is what Phase 8's `pocs/capsule/operator/` + `pocs/capsule/proxy/` recursively kustomize-build under.
- **`pocs/capsule/kustomization.yaml`** (Phase 7 placeholder) — Phase 8 rewrites the `resources` line per D-08-05; the file's Phase 7 head comment block is preserved (REQ-CAPCLU-02 / Pitfall-7 attribution + appended Phase 8 update note).
- **`scripts/lib/preflight-lib.sh`** — output helpers; any new Phase 8 verifier script sources this (Claude's Discretion §"task surface extensions" recommends NO new task; if planner adds a script wrapper for verifier ergonomics, it follows v0.18 conventions).
- **`tests/bats/test_helper`** — shared loader; Phase 8 bats files load without modification.
- **Phase 7 bats files (`poc-mount-01-static.bats`, `poc-isolation-01-static.bats`, `poc-cluster-01-static.bats`)** — Phase 8 reuses `poc-isolation-01-static.bats` verbatim (regression gate); the other two are Phase-7-shape contracts that Phase 8 does not exercise but may extend.
- **HelmController + SourceController in `clusters/hub-flux/flux-system/gotk-components.yaml`** — bootstrap-managed; Phase 8 does NOT touch but consumes (Flux v2 install ships HelmController by default).

### Established Patterns

- **Single-Flux-Kustomization-per-cluster** (`clusters/hub-flux/spokes/spoke-apps.yaml`, `spoke-ml.yaml`, and now `pocs/capsule.yaml`). Phase 8 does NOT introduce additional Flux Kustomizations under `clusters/hub-flux/pocs/`. Subdir composition happens via plain `kustomize.config.k8s.io/v1beta1; kind: Kustomization` references resolved by the outer `poc-capsule` kustomize-build.
- **P18 explicit `key: value.yaml` on every `secretRef`** (`clusters/hub-flux/pocs/capsule.yaml`). Phase 8 has no NEW `secretRef` blocks (no values ConfigMap-by-Secret pattern; values inline per Claude's Discretion default). If planner reverses that and introduces a values-by-Secret reference, P18 invariant applies.
- **Bash strict-mode + `REPO_ROOT`/`SCRIPT_DIR` pinning** (every existing v0.18 + Phase 7 script). Any new Phase 8 verifier script adopts identical preamble.
- **Bats static-contract test naming `<area>-<NN>-<topic>.bats`** + `setup()` with `REPO_ROOT` + `grep -F --` for literal text matches. Phase 8 adopts this convention without invention. Suggested Phase 8 bats names: `capsule-install-01-static-helmrelease.bats`, `capsule-install-02-static-ocirepo.bats`, `capsule-install-03-static-values.bats`, `capsule-install-04-live-helm.bats`, `capsule-install-05-live-crds.bats`, `capsule-install-06-live-proxy-healthz.bats`, `capsule-install-07-live-adr-004.bats`, `capsule-install-08-live-flux-observable.bats` (planner reshapes file partition without re-asking).
- **Wave 0 bats RED scaffold landing** (Phase 7 Plan 07-00 pattern). Phase 8 Plan 08-00 mirrors per D-08-09. Already-validated pattern.

### Integration Points

- **`pocs/capsule/operator/`** + **`pocs/capsule/proxy/`** — net-new directories committed in Phase 8. Each contains `kustomization.yaml` + `OCIRepository` + `HelmRelease` (and optionally a values ConfigMap if Claude's Discretion overrides the inline default). Outer `pocs/capsule/kustomization.yaml` rewritten to `resources: [operator/, proxy/]`. Outer `clusters/hub-flux/pocs/capsule.yaml` UNCHANGED (its `spec.path: ./pocs/capsule` already points here).
- **No Taskfile.yml extensions in Phase 8.** Verifier surface is bats + bare scripts (Claude's Discretion default). Phase 9 may add `task` targets for tenant-related operations.
- **No `Taskfile.yml` `task preflight` extensions in Phase 8.** Phase 7 already locked port 30443 reservation (CAPCLU-04 / D-15). Phase 8 inherits.
- **No `.gitignore` / `.gitleaks.toml` extensions in Phase 8.** Phase 7 closed the kubeconfig leak surface (D-14). Phase 10 (PROXY-03) re-exercises via tenant kubeconfig issuance synthetic fixtures; Phase 8 has no kubeconfig-shaped artifacts to gate.
- **Cross-link surfaces:** `docs/poc-capsule.md` (Phase 7 doc; CAPCLU-04) gains a Phase 8 "What's installed" subsection — Capsule operator + capsule-proxy + the 7 CRDs + the proxy NodePort 30443 endpoint. Planner decides cross-link depth.
- **Phase 7 carryover acceptance**: `flux get kustomization poc-capsule` Ready=True observation is folded into Phase 8 verifier (D-08-09 live bats). If outer `poc-capsule` is NOT Ready=True, treat as Phase 7 SEAM defect — gap-close back to Phase 7 with `/gsd-plan-phase 7 --gaps`.

</code_context>

<specifics>
## Specific Ideas

- **Two-HelmRelease pattern (NOT umbrella)** — milestone-open decision (logged in PROJECT.md / STATE.md): the umbrella chart `charts/capsule/Chart.yaml` at v0.12.4 pins its `capsule-proxy` sub-dependency at `0.10.0` (two minors stale). Splitting into two HelmReleases is the supported way to track both lines independently. Phase 8 bats MUST grep-assert `proxy.enabled=true` is NOT present in any HelmRelease values block (anti-pattern lint).
- **Operator chart values block — minimum required** (D-08-03 + D-08-04 + Phase 9 evolution awareness):
  ```yaml
  values:
    tls:
      enableController: true   # D-08-04 — built-in certgen
    webhooks:
      validatingWebhookConfiguration:
        failurePolicy: Ignore  # D-08-03 — P26 belt-and-suspenders
        # matchConditions optional — chart-default objectSelector already excludes non-tenant-labeled objects;
        # this is explicit defense for clusters with no tenants (Phase 8 → Phase 9 transition window).
      mutatingWebhookConfiguration:
        failurePolicy: Ignore
  ```
  Exact value-key paths depend on chart 0.12.4's values.yaml structure — planner verifies via `helm show values oci://ghcr.io/projectcapsule/charts/capsule --version 0.12.4` during Plan 08-01 research.
- **Proxy chart values block — minimum required** (CAP-02 contract literals):
  ```yaml
  values:
    service:
      type: NodePort
      nodePort: 30443        # D-10 / CAPCLU-04 inheritance from Phase 7
    additionalSANs:
      - 127.0.0.1
      - localhost            # P33 — without these, curl -k fails TLS even with -k for hostname mismatch
  ```
- **OCIRepository shape (per-chart, D-08-02)**:
  ```yaml
  apiVersion: source.toolkit.fluxcd.io/v1
  kind: OCIRepository
  metadata:
    name: capsule
    namespace: capsule-system
  spec:
    interval: 1h
    url: oci://ghcr.io/projectcapsule/charts/capsule
    ref:
      tag: 0.12.4
  ```
  (Same shape for `capsule-proxy` with name + url + tag swapped.)
- **HelmRelease.chartRef shape** — `spec.chartRef.kind: OCIRepository; spec.chartRef.name: <local OCIRepository name>` is the modern Flux v2 pattern (post-2024) replacing the legacy `spec.chart.spec.chart` + `chart.spec.sourceRef`. Verify against Flux HelmController v2 docs during Plan 08-01.
- **`task rebuild` regression non-event** — Phase 7's `tests/bats/poc-isolation-01-static.bats` enforces no `spoke-capsule` mentions in v0.18 scripts (P31). Phase 8's new files live ONLY under `pocs/capsule/operator/`, `pocs/capsule/proxy/`, and `pocs/capsule/kustomization.yaml` — none of which are in the lint's grep set. Bats regression rerun in Plan 08-(verifier) closes the loop.
- **Verifier observation source-of-truth** — Phase 8's "Ready=True" assertions read `flux get kustomization poc-capsule -n flux-system --context k3d-hub-flux` for outer; `flux get helmrelease capsule -n capsule-system --context k3d-spoke-capsule` for operator; `flux get helmrelease capsule-proxy -n capsule-system --context k3d-spoke-capsule` for proxy. NOT `kubectl get helmrelease` (less informative status; Flux CLI provides the lifecycle status field directly).
- **`flux reconcile` priming step** — first-time install on a cold cluster: `flux reconcile source git flux-system --context k3d-hub-flux` followed by `flux reconcile kustomization poc-capsule -n flux-system --context k3d-hub-flux --with-source`. Documents "force" path for the operator's manual UAT walkthrough but is NOT required as a CI test step (live bats use retries with sleep).

</specifics>

<deferred>
## Deferred Ideas

True deferrals to later phases (already locked at milestone-open or by ROADMAP / REQUIREMENTS un-bundling, restated for plan-side awareness):

- **`CapsuleConfiguration/default` singleton CR** with `forceTenantPrefix: true` + `allowServiceAccountPromotion: true` → **Phase 9** (TEN-01..03 — tenant-relevant policy; landing it in Phase 8 would mean two diffs where one suffices).
- **Hub-Flux multi-tenancy lockdown patches** (`--no-cross-namespace-refs=true`, `--no-remote-bases=true`, `--default-service-account=default`) and `flux-system` Kustomization `spec.serviceAccountName: kustomize-controller` → **Phase 9** (TEN-05). High regression risk against v0.18 — STATE.md lists this as the dominant Phase 9 blocker; mitigation = full v0.18 `task health-check` rerun as Phase 9 acceptance gate.
- **Tenant CRs (alpha + bravo) + tenant inner Flux Kustomizations with P27 `spec.serviceAccountName`** → **Phase 9** (TEN-01..06).
- **`dependsOn: tenants → operator with wait: true` (P32 CRD ordering for tenant CR apply)** → **Phase 9** (TEN-06). Phase 8's proxy `dependsOn` operator (D-08-07) is a separate, narrower P32 application (proxy needs CRDs to be running).
- **Tenant owner kubeconfigs + capsule-proxy round-trip + LIST visibility filtering** → **Phase 10** (PROXY-01..03).
- **Negative RBAC bats suite (N1–N12), Capsule webhook failure / recovery, ordered teardown, `task rebuild` SLO regression, one-shot history gitleaks scan, ADR-008** → **Phase 11** (VAL-01..06).
- **`capsule-addon-fluxcd v0.2.3` trial** → **Phase 12** (OPTIONAL — gated on ADR-008 outcome ∈ {adopt, defer}).

### Reviewed Todos (not folded)

- **Phase 7 carryover — gitleaks rule fires on planning docs that quote inert synthetic fixture** (`.planning/todos/pending/2026-04-29-phase-7-gitleaks-planning-doc-allowlist.md`, `resolves_phase: 11`). Auto-mode score 0.6 met the relevance threshold, but the explicit `resolves_phase: 11` marker overrides — this todo is owned by Phase 11 (VAL-05 explicitly owns the one-shot history gitleaks scan post-Phase-10 first push; resolution must precede VAL-05). Phase 8 does NOT touch `.gitleaks.toml`, `.planning/phases/07-*` planning docs, or any of the named files. Reviewing for awareness only — the gitleaks rule fires on planning-doc fixture quotes, not on Phase 8 artifacts. Todo will auto-close when `/gsd-execute-phase 11` runs (per `resolves_phase: 11`).

### Out-of-band ideas surfaced during analysis (NOT in current scope)

- None — analysis stayed within Phase 8 scope. The scope-tightening choice to defer `CapsuleConfiguration` and lockdown patches to Phase 9 is a deliberate ROADMAP / REQUIREMENTS un-bundling, not a deferral discovered during this discussion.

</deferred>

---

*Phase: 08-capsule-capsule-proxy-bare-minimum-install*
*Context gathered: 2026-04-29*
*Mode: --auto (recommended defaults across all 10 gray areas; no interactive questions)*
