---
phase: 08-capsule-capsule-proxy-bare-minimum-install
verified: 2026-04-29T20:50:00Z
status: gaps_found
score: 6/10 must-haves verified
overrides_applied: 0
gaps:
  - truth: "Both Flux v2 HelmReleases (capsule:0.12.4 operator + capsule-proxy:0.12.0) reach Ready=True"
    status: failed
    reason: "Push gate not satisfied — Plans 08-01 + 08-02 commits are local-only (HEAD=16f3638; origin/main=32e0b2fa). Hub-flux GitRepository has not ingested the install yaml; HelmReleases not present anywhere. ALSO: even if push lands, the architectural seam defect (outer Kustomization applies CRs to spoke which has no Flux CRDs) will block Ready=True at the SEAM level. SEE GAP G-04 for the architectural cause."
    artifacts:
      - path: "pocs/capsule/operator/helmrelease.yaml"
        issue: "HR shape correct but install pathway broken — see G-04"
      - path: "pocs/capsule/proxy/helmrelease.yaml"
        issue: "HR shape correct but install pathway broken — see G-04"
    missing:
      - "git push origin main (Phase 11 VAL-05 owns)"
      - "Resolution of architectural seam defect G-04 before push lands (otherwise outer Kustomization will go Ready=False)"
      - "Resolution of cert-source defect G-03 (otherwise proxy pod will never reach Running)"
  - truth: "capsule-controller-manager pod is Running on spoke-capsule (CAP-01 secondary signal)"
    status: failed
    reason: "Operator HelmRelease has not reconciled; no pods in capsule-system namespace on spoke. Downstream of must-have #2 failure."
    artifacts: []
    missing:
      - "Resolution of must-have #2 (HelmRelease Ready=True) — chain depends on push gate + architectural fix + cert source fix"
  - truth: "≥7 capsule.clastix.io CRDs registered on spoke-capsule (CAP-03)"
    status: failed
    reason: "Operator HelmRelease has not reconciled; chart's CRDs not landed on spoke. Downstream of must-have #2."
    artifacts: []
    missing:
      - "Resolution of must-have #2"
  - truth: "NodePort 30443 reachable from WSL host — TLS handshake + HTTP code [1-5][0-9][0-9] (CAP-02)"
    status: failed
    reason: "TWO independent gaps block this: (a) push gate not satisfied (proxy yaml not in origin/main), (b) BL-01 cert-source defect — chosen `certManager.generateCertificates: true` renders cert-manager.io Issuer/Certificate CRs that REQUIRE the cert-manager controller to reconcile into Secrets. spoke-capsule has NO cert-manager controller per D-08-04; without controller, proxy pod cannot mount its TLS volume. Verified by `helm template` inspection (see G-03 evidence)."
    artifacts:
      - path: "pocs/capsule/proxy/helmrelease.yaml"
        issue: "Lines 75-76: `certManager.generateCertificates: true` is incompatible with D-08-04 (no cert-manager controller installed). Reviewer's BL-01 finding confirmed by helm template inspection — only `options.generateCertificates: true` path renders the controller-less certgen Job."
    missing:
      - "Flip to `options.generateCertificates: true` + `certManager.generateCertificates: false` (per BL-01 fix)"
      - "Re-run static bats — may need adjustment for new cert source values"
      - "Push gate clearance (Phase 11 VAL-05)"
  - truth: "If outer poc-capsule Kustomization is NOT Ready=True after push lands, treat as Phase 7 SEAM defect (gap-close to /gsd-plan-phase 7 --gaps)"
    status: failed
    reason: "**ARCHITECTURAL SEAM DEFECT (G-04 / WR-05)**: The outer `clusters/hub-flux/pocs/capsule.yaml` Kustomization has `spec.kubeConfig.secretRef.name: spoke-capsule-kubeconfig` (Phase 7 invariant). When push lands, kustomize-controller will apply Phase 8 manifests (HelmRelease + OCIRepository CRs) to spoke-capsule per the kubeConfig redirect. But spoke-capsule has NO Flux CRDs (per ADR-004). Verified by server-side dry-run: `kubectl --context=k3d-spoke-capsule apply --dry-run=server -f pocs/capsule/operator/helmrelease.yaml` returns: `error: resource mapping not found ... no matches for kind \"HelmRelease\" in version \"helm.toolkit.fluxcd.io/v2\"`. The HelmRelease CRs MUST land on hub-flux (where helm-controller exists), but the outer Kustomization is configured to apply to spoke. This is a FUNDAMENTAL contradiction between Phase 7's outer Kustomization design and Phase 8's HelmRelease residency assumption. The Phase 8 SUMMARY/PLAN never explicitly acknowledged this; the Wave 0 static bats catch shape but not architecture. Currently masked because outer Kustomization is reconciling against pre-Phase-8 source (`32e0b2fa`) where `pocs/capsule/kustomization.yaml: resources: []` produces zero objects to apply (inventory.entries: [])."
    artifacts:
      - path: "clusters/hub-flux/pocs/capsule.yaml"
        issue: "Phase 7 file (P40/P18 invariant) — NOT modifiable in Phase 8 scope, but its `spec.kubeConfig` redirect is incompatible with Phase 8's HelmRelease residency requirement"
      - path: "pocs/capsule/operator/helmrelease.yaml"
        issue: "HR has its own `spec.kubeConfig` redirect — design assumes HR lives on hub-flux where helm-controller picks it up; outer Kustomization sends it to spoke instead"
      - path: "pocs/capsule/proxy/helmrelease.yaml"
        issue: "Same as operator HR"
    missing:
      - "Architectural decision: remove `spec.kubeConfig` from `clusters/hub-flux/pocs/capsule.yaml` (HR + OCIRepo land on hub; HR's own `kubeConfig` redirects helm install to spoke) — but this contradicts Phase 7's explicit P40/P18 silent-misroute defense"
      - "OR: split paths — outer Kustomization applies HR/OCIRepo CRs to hub (via flux-system kubeconfig), while a separate Kustomization with spoke kubeConfig applies any spoke-only CRs (none in Phase 8 scope)"
      - "Decision required from milestone owner before push lands"
deferred: []
human_verification: []
---

# Phase 8: Capsule + capsule-proxy Bare-Minimum Install — Verification Report

**Phase Goal:** Capsule operator and capsule-proxy run on spoke-capsule via two separate Flux HelmReleases reconciled hub-only; CRDs are visible and the proxy is reachable from the WSL host
**Verified:** 2026-04-29T20:50:00Z
**Status:** `gaps_found`
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| #   | Truth                                                                                                                                                                                                | Status      | Evidence                                                                                                                                                                                                                                                                       |
| --- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1   | Two SEPARATE Flux HelmReleases reconciled hub-only — `capsule:0.12.4` operator + `capsule-proxy:0.12.0` (NOT umbrella `proxy.enabled: true`)                                                         | VERIFIED    | Both yaml files exist with correct shape. `pocs/capsule/operator/helmrelease.yaml` (88 lines) + `pocs/capsule/proxy/helmrelease.yaml` (79 lines) declare separate HelmReleases with distinct chartRefs (`capsule` + `capsule-proxy`). Static bats 28 confirms operator HR has no `proxy.enabled: true` literal. |
| 2   | Both HelmReleases report `Ready=True` via `flux get helmrelease`                                                                                                                                     | FAILED      | `flux get helmrelease -A --context k3d-hub-flux` reports "no HelmRelease objects found in any namespace". Push gate not satisfied (HEAD=16f3638; origin/main=32e0b2fa). ALSO see G-04 architectural defect.                                                                  |
| 3   | `capsule-controller-manager` pod is `Running` on spoke-capsule                                                                                                                                       | FAILED      | `kubectl --context=k3d-spoke-capsule -n capsule-system get pods` returns "No resources found in capsule-system namespace." Operator HR never reconciled.                                                                                                                       |
| 4   | ≥7 `capsule.clastix.io` CRDs registered on spoke-capsule                                                                                                                                             | FAILED      | `kubectl --context=k3d-spoke-capsule get crds \| grep -c capsule.clastix.io` returns 0. Chart's CRDs not landed.                                                                                                                                                                |
| 5   | NodePort 30443 reachable from WSL host (TLS handshake + HTTP `[1-5][0-9][0-9]`)                                                                                                                      | FAILED      | TWO independent blockers: (a) push gate, (b) **G-03 BL-01 cert-source defect**. Live bats `capsule-install-08` test 6 NOT OK; test 7 (TCP bound) OK from Phase 7 D-10 inheritance.                                                                                                |
| 6   | ADR-004 invariant preserved — `kubectl --context=k3d-spoke-capsule -n flux-system get pods` returns no flux controllers                                                                              | VERIFIED    | `kubectl --context=k3d-spoke-capsule get pods -n flux-system` returns "No resources found in flux-system namespace." Live bats `capsule-install-09` test 8 OK. ADR-004 positively verified live.                                                                              |
| 7   | FOLDED CARRYOVER — outer `poc-capsule` Kustomization on hub-flux reports `Ready=True` against a post-Phase-7 source revision                                                                         | VERIFIED    | `flux get kustomization poc-capsule -n flux-system --context k3d-hub-flux` reports `Ready=True` with `Applied revision: main@sha1:32e0b2fa` (past `1f2da1d3`). Live bats `capsule-install-10` tests 9 + 11 OK; test 10 SKIPS appropriately on push-gate.                          |
| 8   | Phase 7 P31 isolation regression — `tests/bats/poc-isolation-01-static.bats` GREEN                                                                                                                   | VERIFIED    | `bats tests/bats/poc-isolation-01-static.bats` reports 3/3 ok. Phase 8 introduced ZERO `spoke-capsule` mentions in 6 v0.18 scripts.                                                                                                                                            |
| 9   | Phase 7 P40 / P18 invariant regression — `clusters/hub-flux/pocs/capsule.yaml` retains `secretRef.name: spoke-capsule-kubeconfig` AND `key: value.yaml`                                               | VERIFIED    | `yq eval '.spec.kubeConfig.secretRef.name == "spoke-capsule-kubeconfig" and .spec.kubeConfig.secretRef.key == "value.yaml"' clusters/hub-flux/pocs/capsule.yaml` returns `true`. File NOT modified by Phase 8 (`git diff origin/main..HEAD -- clusters/hub-flux/pocs/capsule.yaml` empty). |
| 10  | Pitfall 9 anti-pattern lint — proxy HelmRelease `dependsOn` block has NO `wait:` field                                                                                                               | VERIFIED    | `yq eval '(.spec.dependsOn[0] \| has("wait")) == false' pocs/capsule/proxy/helmrelease.yaml` returns `true`. Static bats `capsule-install-04` test 29 ok.                                                                                                                       |

**Score:** 6/10 truths verified

### Required Artifacts

| Artifact                                                | Expected                                                                                  | Status     | Details                                                                                                                                                                                                       |
| ------------------------------------------------------- | ----------------------------------------------------------------------------------------- | ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `pocs/capsule/operator/ocirepository.yaml`              | Flux v1 OCIRepository pinning `capsule:0.12.4`                                            | VERIFIED   | 23 lines, all yq invariants pass (apiVersion source.toolkit.fluxcd.io/v1, name capsule, url, ref.tag 0.12.4, layerSelector.mediaType, no secretRef/serviceAccountName)                                         |
| `pocs/capsule/operator/helmrelease.yaml`                | Flux v2 HelmRelease (built-in certgen, per-hook failurePolicy, kubeConfig)                | VERIFIED (shape) / FAILED (wiring) | 88 lines, all yq shape invariants pass. WIRING: outer Kustomization applies it to spoke instead of hub (G-04).                                                                                                  |
| `pocs/capsule/operator/kustomization.yaml`              | Local Kustomize aggregator                                                                | VERIFIED   | 13 lines, resources: [ocirepository.yaml, helmrelease.yaml]                                                                                                                                                  |
| `pocs/capsule/proxy/ocirepository.yaml`                 | Flux v1 OCIRepository pinning `capsule-proxy:0.12.0`                                      | VERIFIED   | 22 lines, all yq invariants pass                                                                                                                                                                              |
| `pocs/capsule/proxy/helmrelease.yaml`                   | Flux v2 HelmRelease (dependsOn operator, NodePort 30443, options.additionalSANs, certmgr) | FAILED     | Shape correct (yq passes), Pitfall 9 honored (no `wait:`), additionalSANs RESEARCH-verified path used. **BL-01 cert-source defect (G-03)**: `certManager.generateCertificates: true` requires absent controller. |
| `pocs/capsule/proxy/kustomization.yaml`                 | Local Kustomize aggregator                                                                | VERIFIED   | 13 lines, mirrors operator subdir aggregator                                                                                                                                                                  |
| `pocs/capsule/kustomization.yaml`                       | Inner aggregator rewritten `resources: [operator/, proxy/]`, Phase 7 head comment preserved | VERIFIED | 18 lines, REQ-CAPCLU-02 + Pitfall 7 attribution preserved, Phase 8 update note appended                                                                                                                       |
| `tests/bats/capsule-install-{01..05}-static-*.bats`     | 5 static contract bats files                                                              | VERIFIED   | 38/38 tests GREEN end-to-end                                                                                                                                                                                   |
| `tests/bats/capsule-install-{06..10}-live-*.bats`       | 5 live observability bats files                                                           | VERIFIED   | All exist with cluster-info gates, TLS-handshake reframe encoded                                                                                                                                              |

### Key Link Verification

| From                                          | To                                              | Via                                            | Status      | Details                                                                                                                          |
| --------------------------------------------- | ----------------------------------------------- | ---------------------------------------------- | ----------- | -------------------------------------------------------------------------------------------------------------------------------- |
| operator/helmrelease.yaml                     | operator/ocirepository.yaml                     | spec.chartRef.kind=OCIRepository + name=capsule | WIRED       | yq verifies; static bats 02 + 10 confirm                                                                                          |
| proxy/helmrelease.yaml                        | proxy/ocirepository.yaml                        | spec.chartRef.kind=OCIRepository + name=capsule-proxy | WIRED       | yq verifies; static bats 07 confirms                                                                                              |
| operator/helmrelease.yaml                     | spoke-capsule-kubeconfig Secret                 | spec.kubeConfig.secretRef.name + key=value.yaml | WIRED       | P18/P40 invariant honored; static bats 03 confirms                                                                                |
| proxy/helmrelease.yaml                        | spoke-capsule-kubeconfig Secret                 | spec.kubeConfig.secretRef.name + key=value.yaml | WIRED       | P18/P40 invariant honored; static bats 08 confirms                                                                                |
| proxy/helmrelease.yaml                        | operator/helmrelease.yaml                       | spec.dependsOn[0].name=capsule + namespace=capsule-system | WIRED       | yq verifies; static bats 09 confirms                                                                                              |
| pocs/capsule/kustomization.yaml               | operator/ + proxy/                              | resources: [operator/, proxy/]                 | WIRED       | static bats 33 confirms                                                                                                           |
| clusters/hub-flux/pocs/capsule.yaml (outer)   | pocs/capsule/                                   | spec.path: ./pocs/capsule + spec.kubeConfig    | **NOT_WIRED at runtime** | **G-04 architectural defect**: outer Kustomization applies CRs to spoke per kubeConfig redirect, but spoke has no Flux CRDs to receive them |

### Data-Flow Trace (Level 4)

| Artifact                                | Data Variable                       | Source                                                                       | Produces Real Data | Status        |
| --------------------------------------- | ----------------------------------- | ---------------------------------------------------------------------------- | ------------------ | ------------- |
| `pocs/capsule/operator/helmrelease.yaml` | HelmRelease CR install state         | hub-flux helm-controller (post-push, post-reconcile)                         | NO (push pending + G-04 blocks) | DISCONNECTED  |
| `pocs/capsule/proxy/helmrelease.yaml`    | HelmRelease CR install state + TLS Secret | hub-flux helm-controller + cert source (cert-manager controller MISSING per BL-01) | NO (G-03 + G-04 + push pending) | DISCONNECTED  |
| `clusters/hub-flux/pocs/capsule.yaml` (outer) | Kustomization Ready=True           | hub-flux kustomize-controller (currently reconciling against pre-Phase-8 source) | YES — partially. Currently Ready=True only because pre-Phase-8 source has empty `resources: []`. Once push lands, will fail to apply Phase 8 CRs to spoke per G-04. | STATIC (will turn DISCONNECTED post-push) |

### Behavioral Spot-Checks

| Behavior                                                                        | Command                                                                                                          | Result                                                                                                                                                                                                              | Status |
| ------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------ |
| All 38 static bats GREEN                                                        | `bats tests/bats/capsule-install-0[12345]-static-*.bats`                                                         | 38/38 ok                                                                                                                                                                                                            | PASS   |
| Phase 7 regression bats 22/22 GREEN                                             | `bats tests/bats/poc-{mount,isolation,cluster}-01-static.bats`                                                   | 22/22 ok                                                                                                                                                                                                            | PASS   |
| Live bats run                                                                   | `bats tests/bats/capsule-install-0[6789]-live-*.bats tests/bats/capsule-install-10-live-*.bats`                  | 4 ok + 6 not ok + 1 skip = 11 outcomes                                                                                                                                                                              | MIXED  |
| BL-01 verification: `certManager.generateCertificates: true` renders Job?       | `helm template ... --set certManager.generateCertificates=true 2>&1 \| grep -c 'kind: Job'`                      | 1 Job (`capsule-proxy-crds` — CRD install hook, NOT certgen). Renders 2 Issuer + 2 Certificate (cert-manager.io) — REQUIRES controller. **BL-01 CONFIRMED.**                                                       | FAIL   |
| BL-01 alternative: `options.generateCertificates: true` renders certgen Job?    | `helm template ... --set options.generateCertificates=true --set certManager.generateCertificates=false 2>&1 \| grep -c 'kind: Job'` | 2 Jobs (`capsule-proxy-certgen` using `kube-webhook-certgen` + `capsule-proxy-crds`). NO cert-manager.io CRs. Controller-less self-sign Job. **Reviewer's fix path validated.**                                       | PASS   |
| G-04 architectural defect: applying HR to spoke succeeds?                       | `kubectl --context=k3d-spoke-capsule apply --dry-run=server -f pocs/capsule/operator/helmrelease.yaml`           | `error: resource mapping not found ... no matches for kind "HelmRelease" in version "helm.toolkit.fluxcd.io/v2" ... ensure CRDs are installed first`. **G-04 CONFIRMED — spoke has no Flux CRDs per ADR-004.** | FAIL   |
| G-04 contrast: applying HR to hub succeeds?                                     | `kubectl --context=k3d-hub-flux apply --dry-run=server -f pocs/capsule/operator/helmrelease.yaml`                | Only fails because namespace doesn't exist; CRDs DO exist on hub. Confirms HRs MUST land on hub.                                                                                                                    | INFO   |

### Requirements Coverage

| Requirement | Source Plan(s)                                | Description                                                                                                                                                                                                                                                                                                                  | Status     | Evidence                                                                                                                                                              |
| ----------- | --------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| CAP-01      | 08-00, 08-01, 08-03                           | Capsule operator (Helm chart `capsule:0.12.4`, OCI `ghcr.io/projectcapsule/charts/capsule`) installed via Flux HelmRelease on hub-flux, reconciling to spoke-capsule via `spec.kubeConfig` — HelmRelease `Ready=True` and `capsule-controller-manager` pod Running on spoke                                                            | BLOCKED    | Yaml shape verified (38/38 static bats GREEN). Live state FAILED — HelmRelease never created (push gate not satisfied + G-04 architectural defect blocks reconcile). |
| CAP-02      | 08-00, 08-02, 08-03                           | capsule-proxy (Helm chart `capsule-proxy:0.12.0`, separate HelmRelease, NOT umbrella) installed with `service.type: NodePort + service.nodePort: 30443` and `additionalSANs: [127.0.0.1, localhost]` — reachable via `curl -k https://127.0.0.1:30443/healthz` returning 200                                                          | BLOCKED    | Yaml shape verified. Live FAILED — push gate + G-04 + G-03 BL-01 cert-source defect (proxy pod cannot get TLS Secret without cert-manager controller).                |
| CAP-03      | 08-00, 08-01, 08-02, 08-03                    | Capsule CRDs (`Tenant`, `CapsuleConfiguration`, `GlobalTenantResource`, `TenantResource`, `ResourcePool`, `ResourcePoolClaim`, `TenantOwner`) installed and visible on spoke-capsule (`kubectl get crds \| grep capsule.clastix.io` returns ≥7 entries)                                                                       | BLOCKED    | Yaml shape configures `install.crds: CreateReplace` correctly, but operator HelmRelease never reconciled. CRDs not registered on spoke.                                |

**Orphaned requirements:** None — all 3 Phase 8 REQ-IDs (CAP-01, CAP-02, CAP-03) are claimed by at least one plan. REQUIREMENTS.md table at lines 157-159 confirms the 1:1 phase mapping.

### Anti-Patterns Found

| File                                              | Line   | Pattern                                                                                                                            | Severity   | Impact                                                                                                                                                                                                                                                                                              |
| ------------------------------------------------- | ------ | ---------------------------------------------------------------------------------------------------------------------------------- | ---------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `pocs/capsule/proxy/helmrelease.yaml`             | 75-76  | `certManager.generateCertificates: true` chosen with comment claiming "works WITHOUT cert-manager controller installed"             | BLOCKER    | **G-03 (BL-01)** — incorrect. cert-manager.io `Issuer` + `Certificate` CRs (regardless of `SelfSigned` issuer type) require the cert-manager controller to reconcile into Secrets. spoke-capsule has no controller per D-08-04. Proxy pod will fail to mount TLS volume; CAP-02 cannot pass.            |
| `tests/bats/capsule-install-04-static-no-umbrella.bats` | 15-21  | `grep -F -- 'proxy.enabled: true'` against operator HR YAML                                                                       | WARNING    | **WR-01** — dotted-key form never appears in valid YAML; test passes vacuously. No real anti-umbrella coverage. The yq positive assertion at static bats 03:57-62 covers presence of `false` but not absence of `true` deeper in structure.                                                              |
| `tests/bats/capsule-install-04-static-no-umbrella.bats` | 30-34  | `grep -F -- 'certManager.generateCertificates: true'` against operator HR YAML                                                    | WARNING    | **WR-02** — same defect as WR-01. Test passes vacuously.                                                                                                                                                                                                                                            |
| `tests/bats/capsule-install-06-live-helm.bats`    | 23, 36 | Regex `<name>[[:space:]]+.*True` admits false positives if "True" appears in flux MESSAGE column                                  | WARNING    | **WR-03** — could mask real Ready=False conditions on failed HRs whose MESSAGE contains "True" substring.                                                                                                                                                                                            |
| `tests/bats/capsule-install-09-live-adr-004.bats` | 16-24  | Test silently passes on ANY non-zero `kubectl get pods` exit (transient apiserver errors → silent pass)                            | WARNING    | **WR-04** — wrong direction for a domain-boundary invariant. Should distinguish NotFound from transient errors.                                                                                                                                                                                       |
| `pocs/capsule/proxy/helmrelease.yaml`             | 68-76  | Block comment is internally inconsistent (claims chart works without controller, then describes alternative as "fallback")         | WARNING    | **WR-06** — pairs with BL-01. Comment block conflates cert-manager API surface (CRDs) with cert-manager controller; if BL-01 is fixed, this comment is removed.                                                                                                                                       |
| `pocs/capsule/operator/helmrelease.yaml`, `pocs/capsule/proxy/helmrelease.yaml` | 37-40, 39-42 | HR `spec.kubeConfig` redirect assumes HR resides on hub (helm-controller picks up); but outer Kustomization (Phase 7) applies CRs to spoke per its own `kubeConfig` | BLOCKER    | **G-04 / WR-05** — fundamental architectural contradiction. The outer Kustomization at `clusters/hub-flux/pocs/capsule.yaml` carries `spec.kubeConfig: spoke-capsule-kubeconfig`, which causes kustomize-controller to apply Phase 8's HelmRelease + OCIRepository CRs to spoke, but spoke has no Flux CRDs. Verified by server-side dry-run: applying HR to spoke fails with `no matches for kind "HelmRelease"`. Currently masked because outer Kustomization is reconciling against pre-Phase-8 source where `resources: []` produces zero objects to apply. **Once push lands, outer Kustomization will go Ready=False.** |
| `tests/bats/capsule-install-08-live-proxy-reachable.bats` | 28-31 | bash-only `/dev/tcp` magic with explicit `bash -c` wrapper; comment doesn't flag this dependency                                  | INFO       | **IN-01** — could break on future cleanup pass that drops the wrapper.                                                                                                                                                                                                                            |
| `pocs/capsule/proxy/helmrelease.yaml`             | 63    | `options.capsuleConfigurationName: default` references CR not committed in Phase 8 (chart auto-creates `CapsuleConfiguration/default`) | INFO       | **IN-02** — load-bearing assumption that operator chart auto-creates the default CR; not independently verified.                                                                                                                                                                                  |
| `tests/bats/capsule-install-06-live-helm.bats`    | 21, 33 | 3 × 30s = 90s retry budget tight for first install with cold image cache                                                          | INFO       | **IN-03** — could flake live runs.                                                                                                                                                                                                                                                                  |
| `pocs/capsule/operator/kustomization.yaml`, `pocs/capsule/proxy/kustomization.yaml` | 10 | `namespace: capsule-system` directive unconditionally rewrites resource namespaces; future per-resource override would be silently shadowed | INFO       | **IN-04** — non-intuitive Kustomize override behavior; document or remove.                                                                                                                                                                                                                          |

### Human Verification Required

None — all gaps are programmatically verifiable. The blockers (G-03 BL-01 cert source, G-04 outer Kustomization architecture) require milestone-owner architectural decisions but the gap evidence is concrete.

### Gaps Summary

Phase 8 ships with a static-contract surface that is well-formed and testable, but with **TWO BLOCKER-class architectural defects** that prevent the phase goal from being achieved at runtime — both of which Phase 8's static bats cannot catch by design (they verify yaml shape, not runtime semantics or controller reconciliation chains):

**G-01 / G-02 (Push gate not satisfied)** — Plans 08-01 + 08-02 commits exist locally (HEAD=`16f3638`) but are not pushed to origin/main (still at `32e0b2fa`). hub-flux's GitRepository has not ingested the install yaml. **This is the EXPLICITLY DEFERRED carryover** that Phase 11 VAL-05 owns (one-shot history scan + first-push gate). The Phase 8 SUMMARY's `closed-with-deferred-carryover` framing accepts this as Path B. The verifier respects the deferral framing — must-haves #2/#3/#4/#5 are FAILED but the proper resolution is Phase 11 VAL-05 work, NOT Phase 8 gap-close.

**G-03 (BL-01 — cert source incompatible with D-08-04)** — Verified by `helm template`: the proxy chart's `certManager.generateCertificates: true` path renders cert-manager.io `Issuer` + `Certificate` CRs (no certgen Job). These CRs require the cert-manager *controller* to reconcile into the `capsule-proxy` Secret. spoke-capsule has NO cert-manager controller per D-08-04 ("cert-manager.io CRDs as API surface only — no controller installed"). The reviewer's fix path (`options.generateCertificates: true` + `certManager.generateCertificates: false`) is validated by `helm template`: it renders a `capsule-proxy-certgen` Job (using `kube-webhook-certgen` image) that is controller-less and produces the Secret directly. **The proxy pod WILL FAIL to mount its TLS volume on first install — must-have #5 cannot pass even after push gate clears.**

**G-04 (Architectural seam defect — outer Kustomization → spoke applies HR CRs to wrong cluster)** — Verified by server-side dry-run: `kubectl --context=k3d-spoke-capsule apply --dry-run=server -f pocs/capsule/operator/helmrelease.yaml` fails with `no matches for kind "HelmRelease" in version "helm.toolkit.fluxcd.io/v2" ... ensure CRDs are installed first`. Confirmed: spoke-capsule has zero Flux CRDs (per ADR-004), but the outer Kustomization at `clusters/hub-flux/pocs/capsule.yaml` (Phase 7) carries `spec.kubeConfig.secretRef: spoke-capsule-kubeconfig`, which redirects kustomize-controller's apply to spoke. **Once push lands, outer Kustomization will go Ready=False with this CRD-not-found error.** This contradicts the SUMMARY's expectation that HelmReleases land on hub-flux where helm-controller can reconcile them. The Phase 8 plan and SUMMARYs do not acknowledge this defect; the static bats verify yaml shape but not the apply-target architecture.

Currently masked because outer Kustomization is reconciling against pre-Phase-8 source (`32e0b2fa`) where `pocs/capsule/kustomization.yaml: resources: []` produces zero objects to apply (`inventory.entries: []`). The masking will lift the moment push lands, surfacing the SEAM defect.

**Categorical assessment of Path B closure framing** (per parallel_execution prompt's verifier decision framework):

The phase prompt asked the verifier to choose between:
- `passed` (accept Path B + treat BL-01 as advisory; defer fix to Phase 11)
- `gaps_found` (BL-01 is substantive; create gap-fix plan)
- `human_needed` (architectural call)

This verifier recommends **`gaps_found`** with TWO gap-fix recommendations:

1. **G-03 (BL-01)** — Apply reviewer's suggested fix. Flip to `options.generateCertificates: true` + `certManager.generateCertificates: false` in `pocs/capsule/proxy/helmrelease.yaml`. Update static bats `capsule-install-03` to assert the new key path. Re-run `helm template` OQ-2 verification with the new flags. This is a small, mechanical change with low risk.

2. **G-04 (Architectural seam)** — Requires architectural decision before push. Two options:
   - **Option A (recommended by WR-05)**: Remove `spec.kubeConfig` from `clusters/hub-flux/pocs/capsule.yaml`. HR + OCIRepo CRs land on hub-flux (where helm-controller exists). HR's own `spec.kubeConfig` redirects helm install to spoke. Standard Flux remote-cluster pattern. *But this contradicts Phase 7's explicit P40/P18 silent-misroute defense, so it would require gap-close back to Phase 7.*
   - **Option B**: Split paths — outer Kustomization with NO kubeConfig applies HR + OCIRepo to hub; a separate Kustomization with spoke kubeConfig applies any spoke-only CRs (none in Phase 8 scope, but Phase 9 will need this for Tenant CRs).

**Recommendation rationale**: While the Path B push-gate framing legitimately defers must-haves #2/#3/#4/#5 to Phase 11 VAL-05, both G-03 and G-04 are independent defects that the push-gate deferral does NOT cover. They represent yaml-shape correctness (G-03) and architectural-wiring correctness (G-04) issues that are concretely verified to fail at runtime via `helm template` and server-side dry-run respectively. Defending these as "advisory" or "human-needed" would amount to deferring known-failing wiring to Phase 11 — at which point the same gaps would surface as Phase 11 install failures, not first-push observability successes.

A Phase 11 install attempt without these fixes would produce: outer Kustomization Ready=False (G-04), proxy pod CrashLoopBackOff or never-Running (G-03). The Phase 11 VAL-05 success criteria (HelmReleases Ready=True, proxy reachable, ≥7 CRDs) would fail, requiring gap-close back to Phase 8 anyway. Closing those gaps NOW is more efficient than discovering them at Phase 11.

**Suggested human override (if milestone owner chooses to defer)**: Add the following to VERIFICATION.md frontmatter:

```yaml
overrides:
  - must_have: "Both Flux v2 HelmReleases reach Ready=True"
    reason: "Push gate deferred to Phase 11 VAL-05 per Path B framing; cert-source + outer-Kustomization architecture defects acknowledged but accepted-as-tracked-debt for Phase 11 install-time discovery"
    accepted_by: "{milestone owner}"
    accepted_at: "{ISO timestamp}"
```

But this verifier flags that doing so would constitute a known design defect under override — that is what overrides are for, but the user should be aware the override is not a "deferral" of an unmet requirement; it is an active acceptance that the install pathway is broken.

---

_Verified: 2026-04-29T20:50:00Z_
_Verifier: Claude (gsd-verifier)_
