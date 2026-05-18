---
phase: 08-capsule-capsule-proxy-bare-minimum-install
plan: "01"
subsystem: gitops-helm
tags: [flux, helmrelease, ocirepository, capsule, operator, wave-1]

# Dependency graph
requires:
  - phase: 07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc
    provides: spoke-capsule cluster + outer poc-capsule Flux Kustomization (clusters/hub-flux/pocs/capsule.yaml) + pocs/capsule/kustomization.yaml placeholder + spoke-capsule-kubeconfig Secret on hub-flux/flux-system
  - phase: 08-capsule-capsule-proxy-bare-minimum-install
    plan: "00"
    provides: Wave 0 RED bats scaffold (49 tests across 10 files; capsule-install-01..05 static contracts ready to turn GREEN by yaml)
provides:
  - Capsule operator OCIRepository pinning oci://ghcr.io/projectcapsule/charts/capsule:0.12.4 (Flux v1)
  - Capsule operator HelmRelease (Flux v2) reconciled hub-only via spec.kubeConfig + key=value.yaml against spoke-capsule-kubeconfig
  - Operator subdir Kustomize aggregator (pocs/capsule/operator/kustomization.yaml)
  - Operator-half of Wave 0 static bats turn GREEN — 23 of 38 tests across 01..05
  - Built-in certgen (D-08-04 — tls.enableController=true, certManager.generateCertificates=false)
  - Per-hook failurePolicy: Ignore overrides for 14 webhook hooks (D-08-03 — RESEARCH-verified per-hook key path; supersedes CONTEXT.md webhooks.validatingWebhookConfiguration.failurePolicy guess)
affects: [08-02-proxy-helmrelease, 08-03-verifier, 09-tenants]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Flux v2 HelmRelease with chartRef → OCIRepository (modern post-2024 shape; spec.chartRef.kind=OCIRepository, NOT legacy spec.chart.spec.chart)"
    - "Flux v1 OCIRepository with explicit layerSelector.mediaType pinning canonical Helm chart layer (application/vnd.cncf.helm.chart.content.v1.tar+gzip)"
    - "Cross-cluster install via spec.kubeConfig.secretRef.{name,key} — explicit key=value.yaml (P18/P40 — defense against silent in-cluster fallback)"
    - "Per-chart OCIRepository (D-08-02) — clean failure isolation between operator and proxy chart sources"
    - "Built-in certgen for Capsule operator webhook TLS (D-08-04) — NO cert-manager dependency"
    - "Per-hook webhooks.hooks.<hook>.failurePolicy: Ignore (D-08-03; P26 belt-and-suspenders) — RESEARCH-verified key path discovered during Plan 08-00 research and encoded in Wave 0 bats"

key-files:
  created:
    - pocs/capsule/operator/ocirepository.yaml
    - pocs/capsule/operator/helmrelease.yaml
    - pocs/capsule/operator/kustomization.yaml
  modified: []

key-decisions:
  - "Honored Pitfall 9 / RESEARCH-wins-over-CONTEXT discipline — failurePolicy is set at the per-hook key path values.webhooks.hooks.<hook>.failurePolicy (verified by helm show values 2026-04-29), NOT the global webhooks.validatingWebhookConfiguration.failurePolicy that 08-CONTEXT.md <specifics> guessed. All 14 hooks (tenants, tenantLabel, customresources, namespaces, pods, services, ingresses, persistentvolumeclaims, networkpolicies, gateways, cordoning, devices, serviceaccounts, tenantResourceObjects) override to Ignore. The config hook default is already Ignore (no override needed); the nodes hook is disabled by default (no override needed)."
  - "Used built-in certgen exclusively — values.tls.enableController=true + values.certManager.generateCertificates=false (D-08-04). cert-manager is explicitly Out-of-Scope per PROJECT.md; built-in chart certgen is documented chart-supported. Single-replica per ADR-008 framing means no cross-pod cert-sharing concern."
  - "Anti-umbrella explicit lint via values.proxy.enabled: false in operator HR (NOT proxy.enabled: true). Two-HelmRelease pattern (milestone-open decision) — capsule-proxy is a SEPARATE HelmRelease at pocs/capsule/proxy/ (Plan 08-02), not bundled in the umbrella chart that pins capsule-proxy two minors stale at 0.10.0."
  - "spec.install.crds=CreateReplace + spec.upgrade.crds=CreateReplace per documented Capsule operator chart contract (Phase 8 CAP-03 — chart's CRDs land deterministically on first install + on chart upgrade)."
  - "spec.install.remediation.retries=3 + spec.upgrade.remediation.retries=3 — recovers from transient OCI fetch failures without retry-storm."

# Metrics
duration: ~2min
completed: 2026-04-29
---

# Phase 8 Plan 01: Capsule Operator HelmRelease + OCIRepository Summary

**Three net-new files under `pocs/capsule/operator/` (124 total lines) land the operator side of Phase 8: Flux v1 OCIRepository pinning `capsule:0.12.4`, Flux v2 HelmRelease using modern `chartRef`/`kubeConfig` syntax with built-in certgen + 14 per-hook `failurePolicy: Ignore` overrides at the RESEARCH-verified per-hook key path (NOT the path 08-CONTEXT.md guessed), and a local Kustomize aggregator. Turns 23 of 38 Wave 0 static-bats tests GREEN for the operator-half; proxy-half remains RED awaiting Plan 08-02.**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-04-29T19:43:21Z
- **Completed:** 2026-04-29T19:45:25Z
- **Tasks:** 3 (all `type="auto"`, all atomically committed)
- **Files created:** 3 (124 total lines including comments)

## Accomplishments

- Operator OCIRepository pins `oci://ghcr.io/projectcapsule/charts/capsule` at literal tag `0.12.4` with explicit `layerSelector.mediaType` for the canonical Helm chart layer (D-08-02). 24h interval (D-08-06) is sufficient for tag-pinned sources. Public `ghcr.io` requires no auth — file declares no `secretRef` or `serviceAccountName`.
- Operator HelmRelease uses modern Flux v2 `chartRef` shape (`kind: OCIRepository, name: capsule`) — NOT legacy `spec.chart.spec.chart`. `spec.kubeConfig.secretRef.{name=spoke-capsule-kubeconfig, key=value.yaml}` carries P18/P40 inheritance from `clusters/hub-flux/pocs/capsule.yaml` (defense against silent in-cluster fallback). 5m reconcile interval matches outer `poc-capsule` Kustomization cadence (D-08-06). `targetNamespace=capsule-system + install.createNamespace=true`. `install.crds + upgrade.crds = CreateReplace` for deterministic CRD reconcile (CAP-03 framing).
- D-08-04 built-in certgen — `values.tls.enableController=true + values.certManager.generateCertificates=false`. NO cert-manager dependency. Chart's pre-install Helm hook generates self-signed cert on spoke-capsule.
- D-08-03 per-hook failurePolicy override — all 14 dynamic-policy hooks set `webhooks.hooks.<hook>.failurePolicy: Ignore`. Belt-and-suspenders posture for the Phase 8 → Phase 9 transition window where webhook fail-closed semantics could otherwise reject pod creates during operator restarts. **RESEARCH-verified per-hook key path** (verified 2026-04-29 against `helm show values oci://ghcr.io/projectcapsule/charts/capsule --version 0.12.4`); this **supersedes** the path 08-CONTEXT.md `<specifics>` block guessed (`webhooks.validatingWebhookConfiguration.failurePolicy`). Wave 0 Plan 08-00 already pre-encoded the RESEARCH-verified path into static bats, so this plan landed cleanly with no plan-time iteration.
- Anti-umbrella explicit lint — `values.proxy.enabled: false` in operator HR. Two-HelmRelease pattern preserved (milestone-open decision); capsule-proxy is a separate HelmRelease landed by Plan 08-02.
- Operator subdir Kustomize aggregator — `pocs/capsule/operator/kustomization.yaml` lists `[ocirepository.yaml, helmrelease.yaml]` with belt-and-suspenders `namespace: capsule-system`. Resolved by the parent `pocs/capsule/kustomization.yaml` once Plan 08-02 rewrites it.
- Operator-half of all five Wave 0 static contract bats turns GREEN: 23 of 38 tests pass; 15 remaining tests await Plan 08-02 (proxy yaml + top-level kustomize rewrite) or are scope-boundary checks for proxy-only files. Phase 7 regression bats (22 tests across `poc-mount`, `poc-isolation`, `poc-cluster`) all stay GREEN — P31, P40/P18, CAPCLU-01..04 contracts preserved.
- Pitfall 9 (RESEARCH-verified) honored — operator HR has zero `dependsOn` block (proxy depends on operator, not vice versa); no `wait:` field anywhere.

## Task Commits

Each task was committed atomically (`--no-verify` per parallel-worktree protocol):

1. **Task 1: Create pocs/capsule/operator/ocirepository.yaml — Flux v1 OCIRepository pinning capsule:0.12.4** — `e9ddac5` (feat)
2. **Task 2: Create pocs/capsule/operator/helmrelease.yaml — Flux v2 HelmRelease with built-in certgen, per-hook failurePolicy, kubeConfig to spoke-capsule** — `874cff9` (feat)
3. **Task 3: Create pocs/capsule/operator/kustomization.yaml — local Kustomize aggregator wiring OCIRepository + HelmRelease** — `0e6072d` (feat)

## Files Created/Modified

- `pocs/capsule/operator/ocirepository.yaml` (23 lines) — Flux v1 OCIRepository: apiVersion source.toolkit.fluxcd.io/v1, name capsule, namespace capsule-system, url oci://ghcr.io/projectcapsule/charts/capsule, ref.tag "0.12.4", layerSelector.mediaType pinned, no secretRef / no serviceAccountName.
- `pocs/capsule/operator/helmrelease.yaml` (88 lines) — Flux v2 HelmRelease: apiVersion helm.toolkit.fluxcd.io/v2, name capsule, namespace capsule-system, interval 5m, releaseName capsule, target+storageNamespace capsule-system, install.{createNamespace=true, crds=CreateReplace, remediation.retries=3}, upgrade.{crds=CreateReplace, remediation.retries=3}, chartRef.{kind=OCIRepository, name=capsule}, kubeConfig.secretRef.{name=spoke-capsule-kubeconfig, key=value.yaml}, values block (tls.{enableController=true, create=true}, certManager.generateCertificates=false, crds.install=true, webhooks.hooks for 14 hooks all failurePolicy=Ignore, replicaCount=1, proxy.enabled=false).
- `pocs/capsule/operator/kustomization.yaml` (13 lines) — local Kustomize aggregator: apiVersion kustomize.config.k8s.io/v1beta1, kind Kustomization, namespace capsule-system, resources [ocirepository.yaml, helmrelease.yaml].

## Yq Evaluation Results

All compound yq queries returned `true`:

| File | Compound query summary | Result |
|------|------------------------|--------|
| `pocs/capsule/operator/ocirepository.yaml` | apiVersion + kind + name + namespace + url + ref.tag + layerSelector.mediaType | `true` |
| `pocs/capsule/operator/helmrelease.yaml` | apiVersion + kind + name + namespace + interval + chartRef.{kind,name} + kubeConfig.secretRef.{name,key} + targetNamespace + install.createNamespace + install.crds + upgrade.crds + values.tls.enableController + values.certManager.generateCertificates + values.webhooks.hooks.tenants.failurePolicy + values.proxy.enabled + values.replicaCount | `true` |
| `pocs/capsule/operator/kustomization.yaml` | apiVersion + kind + resources length=2 + resources contains both files | `true` |
| Anti-umbrella negative grep | `grep -v '^[[:space:]]*#' helmrelease.yaml \| grep -F -- 'proxy.enabled: true'` returns non-zero | `OK: no proxy.enabled: true outside comments` |

## Static Bats Outcomes

`bats tests/bats/capsule-install-{01,02,03,04,05}-static-*.bats` (38 tests across 5 Wave 0 files):

| Bats file | Total tests | GREEN now | RED now | Reason for RED |
|-----------|-------------|-----------|---------|----------------|
| capsule-install-01-static-helmrelease.bats | 9 | 5 (operator) | 4 (proxy) | `[ -f $PROXY_HR ]` precondition fails — Plan 08-02 owns |
| capsule-install-02-static-ocirepo.bats | 8 | 4 (operator) | 4 (proxy) | `[ -f $PROXY_OCIREPO ]` precondition fails — Plan 08-02 owns |
| capsule-install-03-static-values.bats | 10 | 7 (operator) | 3 (proxy) | `[ -f $PROXY_HR ]` precondition fails — Plan 08-02 owns |
| capsule-install-04-static-no-umbrella.bats | 5 | 3 (operator-related: anti-umbrella, no-cert-manager-true, no-CapsuleConfiguration-CR) | 2 (Pitfall 9 dependsOn-no-wait, Tenant CR scope on proxy file) | `[ -f $PROXY_HR ]` precondition fails — Plan 08-02 owns |
| capsule-install-05-static-kustomize.bats | 6 | 4 (apiVersion+kind, REQ-CAPCLU-02 attribution, Pitfall 7 attribution, operator subdir aggregator) | 2 (top-level resources=[operator/, proxy/], proxy subdir) | Plan 08-02 owns parent rewrite + proxy subdir |
| **Total** | **38** | **23 GREEN** | **15 RED** (all proxy-half) | Plan 08-02 closes the gap |

The four bats files explicitly listed in this plan's `<must_haves>` truths (`capsule-install-01-static-helmrelease.bats + capsule-install-02-static-ocirepo.bats + capsule-install-03-static-values.bats + capsule-install-04-static-no-umbrella.bats`) all turn GREEN for the **operator-half** of their assertions, exactly matching the truth statement.

## Phase 7 Regression Bats — All GREEN

`bats tests/bats/poc-mount-01-static.bats tests/bats/poc-isolation-01-static.bats tests/bats/poc-cluster-01-static.bats` — **22 tests, 0 failures**:

- POC-01 (`poc-mount-01-static.bats`, 8 tests) — KARYON POC MOUNT sentinel, idempotency, P40/P18 secretRef.{name,key=value.yaml} on outer Kustomization, Pitfall 7 placeholder shape — all GREEN.
- P31 (`poc-isolation-01-static.bats`, 3 tests) — v0.18 scripts have ZERO `spoke-capsule` / `register-poc-cluster` / `scripts/poc/` mentions — all GREEN. **Phase 8 Plan 01 introduces ZERO new mentions** (all new files live under `pocs/capsule/operator/` which is not in the lint's grep set).
- CAPCLU-01..04 (`poc-cluster-01-static.bats`, 11 tests) — Phase 7 cluster-shape contract intact — all GREEN. **Phase 8 Plan 01 modifies neither `scripts/poc/capsule/create-cluster.sh` nor `scripts/poc/capsule/fix-dns.sh` nor `Taskfile.yml` nor `docs/poc-capsule.md`.**

## Pitfall 9 (RESEARCH catch) — Honored

The plan's `<must_haves>` explicitly call out the Pitfall 9 RESEARCH catch on `failurePolicy` per-hook key path:

> "Operator chart values use RESEARCH-verified per-hook key paths — `webhooks.hooks.<hook>.failurePolicy=Ignore` (NOT the global `webhooks.validatingWebhookConfiguration.failurePolicy` that CONTEXT.md guessed)"

This was honored. The HelmRelease values block sets `failurePolicy: Ignore` at the **per-hook** key path under `webhooks.hooks.<name>.failurePolicy` for all 14 dynamic-policy hooks (`tenants`, `tenantLabel`, `customresources`, `namespaces`, `pods`, `services`, `ingresses`, `persistentvolumeclaims`, `networkpolicies`, `gateways`, `cordoning`, `devices`, `serviceaccounts`, `tenantResourceObjects`). The `config` hook default is already `Ignore` (no override needed); the `nodes` hook is disabled by default (no override needed). The verified static bats (`capsule-install-03-static-values.bats` lines 29-48) sample-check three of these hooks (`tenants`, `namespaces`, `pods`) and all three turn GREEN.

The CONTEXT.md `<specifics>` block guess (`webhooks.validatingWebhookConfiguration.failurePolicy`) is **NOT** present anywhere in the HelmRelease values. RESEARCH-wins-over-CONTEXT discipline preserved.

## Decisions Made

- **All gray areas pre-decided by 08-CONTEXT.md** — Plan 08-01 inherits all defaults (Claude's Discretion + 10 explicit decisions D-08-01..10) without re-asking. No deviations from the plan-as-written.
- **No NodePort or proxy-specific values** — operator chart has no Service shape relevant to Phase 8 reachability (proxy chart owns the NodePort 30443 surface).
- **No `dependsOn` block on the operator HR** — operator depends on no other HelmRelease in this scope. Plan 08-02's proxy HR is the one with `dependsOn: [{name: capsule, namespace: capsule-system}]`.

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None. The three yaml files are inert until the parent `pocs/capsule/kustomization.yaml` is rewritten by Plan 08-02 to `resources: [operator/, proxy/]` AND the proxy subdir lands. Until then, the outer Flux Kustomization `poc-capsule` will continue reconciling against `pocs/capsule/kustomization.yaml: resources: []` (the Phase 7 placeholder is unchanged by this plan).

This is intentional and matches the Wave 1 Plan 08-00 SUMMARY note: "Plans 08-01 / 08-02 must keep [outer poc-capsule Ready=True] GREEN by landing the operator/ + proxy/ subdirs simultaneously with the parent rewrite to avoid Pitfall 7 `path not found` mid-Phase-8." This plan ships ONLY operator content; the parent rewrite happens atomically with proxy yaml in Plan 08-02.

## Next Plan Readiness

- **Plan 08-02 (proxy HelmRelease + OCIRepository + parent kustomize rewrite + proxy subdir kustomization) is unblocked.** The 15 currently-RED static-bats tests all wait on Plan 08-02's three new files under `pocs/capsule/proxy/` plus the rewrite of `pocs/capsule/kustomization.yaml`. RESEARCH §"Pattern 1+2+3" + §"Code Examples Example 2 + 3" + Pitfall 8/9 give the exact target shapes.
- **Plan 08-03 (verifier — live observation + folded carryover acceptance)** is downstream of Plan 08-02. The 5 live bats (`capsule-install-06..10`) are already in place from Wave 0; once Plan 08-02 lands and hub-flux reconciles, Plan 08-03 just runs them and adds any docs/poc-capsule.md "What's installed" subsection.
- **No blockers or concerns from this plan.** Operator-half GREEN, proxy-half stays RED on schedule, Phase 7 regression bats stay 22/22 GREEN, no v0.18 script touched, no `spoke-capsule` introduced into v0.18 grep set.

## Self-Check: PASSED

All 3 created files FOUND on disk. All 3 task commit hashes (`e9ddac5`, `874cff9`, `0e6072d`) FOUND in `git log`. yq compound queries all return `true`. Anti-umbrella negative grep clean. Phase 7 regression bats 22/22 GREEN. Operator-half of Wave 0 static bats GREEN. Proxy-half tests RED on schedule (Plan 08-02 owns).

```
$ [ -f "pocs/capsule/operator/ocirepository.yaml" ] && echo "FOUND: pocs/capsule/operator/ocirepository.yaml"
FOUND: pocs/capsule/operator/ocirepository.yaml
$ [ -f "pocs/capsule/operator/helmrelease.yaml" ] && echo "FOUND: pocs/capsule/operator/helmrelease.yaml"
FOUND: pocs/capsule/operator/helmrelease.yaml
$ [ -f "pocs/capsule/operator/kustomization.yaml" ] && echo "FOUND: pocs/capsule/operator/kustomization.yaml"
FOUND: pocs/capsule/operator/kustomization.yaml
$ git log --oneline | grep -q "e9ddac5" && echo "FOUND: e9ddac5"
FOUND: e9ddac5
$ git log --oneline | grep -q "874cff9" && echo "FOUND: 874cff9"
FOUND: 874cff9
$ git log --oneline | grep -q "0e6072d" && echo "FOUND: 0e6072d"
FOUND: 0e6072d
```

---
*Phase: 08-capsule-capsule-proxy-bare-minimum-install*
*Plan: 01 (operator HelmRelease + OCIRepository)*
*Completed: 2026-04-29*
