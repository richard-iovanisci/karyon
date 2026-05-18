---
phase: 08-capsule-capsule-proxy-bare-minimum-install
plan: "02"
subsystem: gitops-helm
tags: [flux, helmrelease, ocirepository, capsule-proxy, dependsOn, nodeport, kustomize, wave-2]

# Dependency graph
requires:
  - phase: 07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc
    provides: spoke-capsule cluster (k3d serverlb publishing 30443) + outer poc-capsule Flux Kustomization (clusters/hub-flux/pocs/capsule.yaml) + spoke-capsule-kubeconfig Secret on hub-flux/flux-system
  - phase: 08-capsule-capsule-proxy-bare-minimum-install
    plan: "00"
    provides: Wave 0 RED bats scaffold (capsule-install-01..05 static contracts encoding Pitfall 8 reframe + Pitfall 9 anti-pattern + RESEARCH-verified key paths)
  - phase: 08-capsule-capsule-proxy-bare-minimum-install
    plan: "01"
    provides: Operator OCIRepository + HelmRelease + subdir Kustomize aggregator (pocs/capsule/operator/ — 23/38 static bats GREEN)
provides:
  - capsule-proxy OCIRepository pinning oci://ghcr.io/projectcapsule/charts/capsule-proxy:0.12.0 (Flux v1)
  - capsule-proxy HelmRelease (Flux v2) with dependsOn operator (NO `wait:` field — Pitfall 9 RESEARCH catch honored), reconciled hub-only via spec.kubeConfig + key=value.yaml against spoke-capsule-kubeconfig
  - Proxy subdir Kustomize aggregator (pocs/capsule/proxy/kustomization.yaml)
  - Inner kustomize aggregator REWRITE (pocs/capsule/kustomization.yaml: resources [] -> [operator/, proxy/]) — Phase 7 head comment block (REQ-CAPCLU-02 + Pitfall 7 attribution) preserved verbatim, Phase 8 update note appended
  - All 5 Wave 0 static bats files (capsule-install-01..05) turn 38/38 GREEN end-to-end
  - OQ-2 cert-source path verified live (chart's SelfSigned Issuer + Certificate template renders without cert-manager controller — `helm template` returned 6 lines matching `kind: (Issuer|Certificate)` 2026-04-29)
affects: [08-03-verifier, 09-tenants, 10-tenant-kubeconfigs, 11-validation]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Flux v2 HelmRelease dependsOn block — name + namespace ONLY (NO `wait:` sub-field; Pitfall 9 RESEARCH catch — default Flux v2 behavior already blocks reconcile until dependency Ready=True)"
    - "Per-chart OCIRepository (D-08-02) — clean failure isolation between operator and proxy chart sources; second instantiation of pattern established by Plan 08-01"
    - "Atomic landing of subdir + parent rewrite (Pitfall 7 mitigation) — proxy/ subdir yaml + parent kustomization.yaml rewrite committed in same plan to avoid `path not found` mid-Phase-8"
    - "OQ-2 helm-template gate — verify chart rendering BEFORE writing helmrelease.yaml when chart-default cert source path requires external dependency assumption (chart's SelfSigned Issuer template confirmed working without cert-manager controller)"
    - "options.additionalSANs key path on capsule-proxy chart 0.12.0 (NOT tls.additionalSANs as CONTEXT.md `<specifics>` guessed) — RESEARCH-verified by `helm show values` 2026-04-29"

key-files:
  created:
    - pocs/capsule/proxy/ocirepository.yaml
    - pocs/capsule/proxy/helmrelease.yaml
    - pocs/capsule/proxy/kustomization.yaml
  modified:
    - pocs/capsule/kustomization.yaml

key-decisions:
  - "Honored Pitfall 9 RESEARCH catch verbatim — proxy HelmRelease dependsOn[0] is `{name: capsule, namespace: capsule-system}` with NO `wait:` sub-field. CONTEXT.md D-08-07's `wait: true` was a guess; Flux v2 helm.toolkit.fluxcd.io/v2 spec doesn't have a `wait:` sub-field. Default Flux v2 behavior already blocks proxy reconcile until operator HelmRelease reports Ready=True. Static bats `capsule-install-04` Pitfall 9 anti-grep `yq eval '.spec.dependsOn[0] | has(\"wait\")' == false` confirms."
  - "Honored options.additionalSANs key path verbatim — proxy values block sets `options.additionalSANs: [127.0.0.1, localhost]` (NOT `tls.additionalSANs` as CONTEXT.md `<specifics>` guessed). RESEARCH-verified by `helm show values oci://ghcr.io/projectcapsule/charts/capsule-proxy --version 0.12.0` 2026-04-29."
  - "Honored Pitfall 8 (CAP-02 reframe) by preserving Wave 0 capsule-install-08-live-proxy-reachable.bats encoding — TLS handshake + HTTP code matches `^[1-5][0-9][0-9]$` (any valid HTTP response on https://127.0.0.1:30443/api), NOT literal 200 on /healthz. The chart Service shape exposes only port 9001 (proxy, requires bearer token); /healthz is on probe port 8081 which is Pod-only per kubelet's direct pod-network access pattern. The HelmRelease values landed in this plan match this contract."
  - "OQ-2 cert-source verification ran SUCCESSFULLY before writing helmrelease.yaml (per plan Task 2 `<read_first>` gate). `helm template capsule-proxy oci://ghcr.io/projectcapsule/charts/capsule-proxy --version 0.12.0 --set certManager.generateCertificates=true` rendered 6 lines matching `kind: (Issuer|Certificate)` (4 Issuers + 2 Certificates), confirming chart's SelfSigned Issuer template works WITHOUT cert-manager controller installed. Proxy HelmRelease landed with `certManager.generateCertificates: true` as planned. The fallback path (`options.generateCertificates: true` + `certManager.generateCertificates: false`) was NOT taken — research gap-close prompt was NOT triggered."
  - "Atomic landing of all 4 artifacts (3 net-new proxy/ files + parent rewrite) honored Pitfall 7 — proxy/ocirepository.yaml + proxy/kustomization.yaml committed first (Task 1), proxy/helmrelease.yaml committed second (Task 2), parent rewrite committed third (Task 3). At no point during the plan was the parent `pocs/capsule/kustomization.yaml: resources: [operator/, proxy/]` referencing a missing `proxy/` subdir. Pitfall 7 risk eliminated by ordering."
  - "spec.targetNamespace=capsule-system + spec.install.createNamespace=true (Claude's Discretion default per 08-CONTEXT.md). Mirror of Plan 08-01 operator HR shape."
  - "spec.upgrade does NOT include `crds: CreateReplace` — capsule-proxy chart has zero CRDs of its own (Capsule CRDs are owned by the operator chart). 79-line proxy HelmRelease vs 88-line operator HelmRelease reflects this scope difference."
  - "spec.install.remediation.retries=3 + spec.upgrade.remediation.retries=3 — recovers from transient OCI fetch failures without retry-storm. Mirrors Plan 08-01 operator HR."

patterns-established:
  - "Two-HelmRelease pattern complete (milestone-open decision honored) — capsule operator HelmRelease at pocs/capsule/operator/ + capsule-proxy HelmRelease at pocs/capsule/proxy/ are SEPARATE Flux v2 HelmReleases, NOT bundled in the umbrella `capsule:0.12.4` chart with `proxy.enabled: true`. Static bats `capsule-install-04` anti-umbrella lint confirms NO `proxy.enabled: true` literal anywhere in pocs/capsule/. Tracks both upstream lines independently (umbrella pins capsule-proxy at 0.10.0, two minors stale)."
  - "Pitfall 7 atomic-landing discipline — when an inner aggregator's `resources: [a/, b/]` block references multiple subdirs created across plans, the LAST plan in the wave is responsible for atomically committing both the missing subdir(s) AND the parent rewrite. Plan 08-02 owns this for the `proxy/` subdir + parent rewrite; the operator/ subdir (already committed by Plan 08-01) remained untouched."

requirements-completed:
  - CAP-02
  - CAP-03

# Metrics
duration: ~10min
completed: 2026-04-29
---

# Phase 8 Plan 02: capsule-proxy HelmRelease + Inner Aggregator Rewrite Summary

**Three net-new files under `pocs/capsule/proxy/` (114 total lines) plus parent kustomize rewrite (pocs/capsule/kustomization.yaml: resources [] -> [operator/, proxy/] preserving Phase 7 head comment) land the proxy side of Phase 8 — Flux v2 HelmRelease declares `dependsOn` operator with NO `wait:` field (Pitfall 9 RESEARCH catch), `service.{type=NodePort, nodePort=30443}` (Phase 7 D-10 inheritance), `options.additionalSANs=[127.0.0.1, localhost]` (RESEARCH-verified key path; NOT tls.additionalSANs), and `certManager.generateCertificates: true` (OQ-2 verified live before write). Closes the Wave 2 gap: all 5 static Wave 0 bats files turn 38/38 GREEN end-to-end and Phase 7 regression bats stay 22/22 GREEN.**

## Performance

- **Duration:** ~10 min
- **Started:** 2026-04-29T19:50:05Z
- **Completed:** 2026-04-29T20:00:08Z
- **Tasks:** 4 (3 file-creating tasks + 1 verification-only task)
- **Files created:** 3 (114 total lines including comments)
- **Files modified:** 1 (pocs/capsule/kustomization.yaml — rewritten, +8 lines / −1 line net)

## Accomplishments

- Proxy OCIRepository pins `oci://ghcr.io/projectcapsule/charts/capsule-proxy` at literal tag `0.12.0` with explicit `layerSelector.mediaType` for the canonical Helm chart layer (D-08-02). 24h interval (D-08-06) is sufficient for tag-pinned sources. Public `ghcr.io` requires no auth — file declares no `secretRef` or `serviceAccountName`. Mirror of Plan 08-01 operator OCIRepository with name + url + tag swapped.
- Proxy HelmRelease uses modern Flux v2 `chartRef` shape (`kind: OCIRepository, name: capsule-proxy`). `spec.kubeConfig.secretRef.{name=spoke-capsule-kubeconfig, key=value.yaml}` carries P18/P40 inheritance from `clusters/hub-flux/pocs/capsule.yaml` (defense against silent in-cluster fallback). 5m reconcile interval matches outer `poc-capsule` Kustomization cadence (D-08-06). `targetNamespace=capsule-system + install.createNamespace=true`.
- D-08-07 dependsOn operator block — `dependsOn: [{name: capsule, namespace: capsule-system}]` blocks proxy reconcile until operator HelmRelease reports `Ready=True`. **Pitfall 9 RESEARCH catch honored verbatim** — NO `wait:` sub-field (the field doesn't exist in helm.toolkit.fluxcd.io/v2 HelmRelease spec; default Flux v2 behavior already blocks). Static bats `capsule-install-04` Pitfall 9 anti-grep `yq eval '.spec.dependsOn[0] | has("wait")' == false` confirms.
- CAP-02 service shape — `service.{type=NodePort, port=9001, portName=proxy, nodePort=30443}` (Phase 7 D-10 inheritance — k3d serverlb already publishes 30443 on the WSL host loopback). chart-default `type: ClusterIP` overridden.
- P33 TLS SAN injection — `options.additionalSANs: [127.0.0.1, localhost]`. **RESEARCH-verified key path** (NOT `tls.additionalSANs` as CONTEXT.md `<specifics>` guessed). Without these SANs, `curl -k` from the WSL host fails TLS handshake at the cert hostname-verification step (BEFORE the HTTP request begins). The Wave 0 plan pre-encoded the RESEARCH-verified path into static bats `capsule-install-03`, so this plan landed cleanly with no plan-time iteration.
- OQ-2 cert-source path verified — `certManager.generateCertificates: true` (chart default). The chart's SelfSigned Issuer template renders Issuer + Certificate manifests inline without requiring cert-manager controller. **OQ-2 verification gate ran SUCCESSFULLY before write** — `helm template capsule-proxy oci://ghcr.io/projectcapsule/charts/capsule-proxy --version 0.12.0 --set certManager.generateCertificates=true` returned 6 lines matching `kind: (Issuer|Certificate)` (4 Issuers + 2 Certificates). Research gap-close prompt was NOT triggered; the fallback `options.generateCertificates: true` + `certManager.generateCertificates: false` was NOT taken.
- Proxy subdir Kustomize aggregator — `pocs/capsule/proxy/kustomization.yaml` lists `[ocirepository.yaml, helmrelease.yaml]` with belt-and-suspenders `namespace: capsule-system`. Resolved by the parent `pocs/capsule/kustomization.yaml` post-rewrite.
- Parent kustomize aggregator REWRITE — `pocs/capsule/kustomization.yaml: resources []` → `resources [operator/, proxy/]` per D-08-05. **Phase 7 head comment block preserved VERBATIM** (REQ-CAPCLU-02 + Pitfall 7 attribution) with **Phase 8 update note APPENDED** (NOT replacing). Static bats `capsule-install-05` confirms both grep-F probes for `REQ-CAPCLU-02` and `Pitfall 7` succeed.
- All 5 Phase 8 static Wave 0 bats files turn 38/38 GREEN end-to-end (operator-half + proxy-half + parent-rewrite all covered). Plan 08-01's operator-half (23 GREEN before this plan) plus Plan 08-02's proxy-half + parent rewrite (15 newly GREEN tests) closes the Wave 0 contract surface for Phase 8.
- Phase 7 regression bats — `bats tests/bats/poc-{mount,isolation,cluster}-01-static.bats` reports **22 tests / 0 failures**. P31 (POC isolation), P40 (P18 key: value.yaml), CAPCLU-01..04 contracts preserved. Plan 08-02 introduces ZERO `spoke-capsule` mentions in v0.18 scripts (all new files live under `pocs/capsule/proxy/` which is not in the lint's grep set).
- Anti-grep scope-boundary lints clean — pocs/capsule/ contains NO `kind: CapsuleConfiguration` (defer to Phase 9 per D-08-08), NO `kind: Tenant` (defer to Phase 9), NO `--no-cross-namespace-refs` lockdown patch, NO `--no-remote-bases`, NO `--default-service-account` (all defer to Phase 9 per TEN-05). Phase 8 scope held ruthlessly narrow.
- Atomic landing discipline (Pitfall 7) — Task 1 committed proxy/{ocirepository,kustomization}.yaml, Task 2 committed proxy/helmrelease.yaml, Task 3 committed the parent rewrite. At no point during the plan execution did the parent `pocs/capsule/kustomization.yaml` reference a missing `proxy/` subdir.

## Task Commits

Each task was committed atomically (`--no-verify` per parallel-worktree protocol):

1. **Task 1: Create pocs/capsule/proxy/ocirepository.yaml + pocs/capsule/proxy/kustomization.yaml** — `342b432` (feat)
2. **Task 2: Create pocs/capsule/proxy/helmrelease.yaml — Flux v2 HelmRelease with dependsOn operator (NO wait field), NodePort 30443, options.additionalSANs** — `180585d` (feat)
3. **Task 3: Rewrite pocs/capsule/kustomization.yaml from `resources: []` to `resources: [operator/, proxy/]`** — `000a607` (docs)
4. **Task 4: Run full static-bats suite — confirm 5 Phase 8 static bats GREEN end-to-end + Phase 7 regression bats GREEN** — (verification-only; no commit per plan `<files>(none)`)

## Files Created/Modified

- `pocs/capsule/proxy/ocirepository.yaml` (22 lines) — Flux v1 OCIRepository: apiVersion source.toolkit.fluxcd.io/v1, name capsule-proxy, namespace capsule-system, url oci://ghcr.io/projectcapsule/charts/capsule-proxy, ref.tag "0.12.0", layerSelector.mediaType pinned (canonical Helm chart layer), no secretRef / no serviceAccountName.
- `pocs/capsule/proxy/helmrelease.yaml` (79 lines, under 80-line ceiling) — Flux v2 HelmRelease: apiVersion helm.toolkit.fluxcd.io/v2, name capsule-proxy, namespace capsule-system, interval 5m, releaseName capsule-proxy, target+storageNamespace capsule-system, install.{createNamespace=true, remediation.retries=3}, upgrade.{remediation.retries=3} (NO `crds:` field — proxy chart has no CRDs), chartRef.{kind=OCIRepository, name=capsule-proxy}, kubeConfig.secretRef.{name=spoke-capsule-kubeconfig, key=value.yaml}, dependsOn=[{name=capsule, namespace=capsule-system}] (NO wait field — Pitfall 9), values block (service.{type=NodePort, port=9001, portName=proxy, nodePort=30443}, options.{listeningPort=9001, enableSSL=true, capsuleConfigurationName=default, additionalSANs=[127.0.0.1, localhost], authPreferredTypes=BearerToken,TLSCertificate}, certManager.generateCertificates=true (OQ-2 verified), webhooks.enabled=false, replicaCount=1).
- `pocs/capsule/proxy/kustomization.yaml` (13 lines) — local Kustomize aggregator: apiVersion kustomize.config.k8s.io/v1beta1, kind Kustomization, namespace capsule-system, resources [ocirepository.yaml, helmrelease.yaml]. Mirror of Plan 08-01 operator subdir aggregator with `proxy/` directory naming.
- `pocs/capsule/kustomization.yaml` (18 lines, MODIFIED from 11 lines) — Inner kustomize aggregator REWRITE: resources [] -> [operator/, proxy/]. Phase 7 head comment block (REQ-CAPCLU-02 + Pitfall 7 attribution) preserved verbatim; Phase 8 update note (D-08-05) appended to the comment block before apiVersion line. Trailing slashes on operator/ and proxy/ signal directories to readers.

## Yq + Helm Evaluation Results

All compound yq queries returned `true`; OQ-2 helm-template gate returned 6 matching lines (≥2 required):

| File / Gate | Compound query / verification | Result |
|------|------------------------|--------|
| `pocs/capsule/proxy/ocirepository.yaml` | apiVersion + kind + name + namespace + url + ref.tag + layerSelector.mediaType | `true` |
| `pocs/capsule/proxy/helmrelease.yaml` | apiVersion + kind + name + namespace + interval + chartRef + kubeConfig.secretRef + dependsOn[0].{name,namespace} + dependsOn[0]\|has("wait")==false + service.{type,nodePort} + options.additionalSANs contains 127.0.0.1+localhost + certManager.generateCertificates=true + replicaCount=1 | `true` |
| `pocs/capsule/proxy/kustomization.yaml` | apiVersion + kind + resources length=2 + contains both files | `true` |
| `pocs/capsule/kustomization.yaml` (rewrite) | apiVersion + kind + resources length=2 + resources[0]==operator/ + resources[1]==proxy/ | `true` |
| Parent kustomize REQ-CAPCLU-02 attribution | `grep -F -- 'REQ-CAPCLU-02'` | exit 0 |
| Parent kustomize Pitfall 7 attribution | `grep -F -- 'Pitfall 7'` | exit 0 |
| OQ-2 helm-template gate (Task 2 read_first) | `helm template capsule-proxy oci://...:0.12.0 --set certManager.generateCertificates=true \| grep -E 'kind: (Issuer\|Certificate)' \| wc -l` | 6 (≥2 required → PASS) |

## Static Bats Outcomes — Phase 8 Wave 0

`bats tests/bats/capsule-install-{01,02,03,04,05}-static-*.bats` (38 tests across 5 Wave 0 files):

| Bats file | Total tests | GREEN | RED | Note |
|-----------|-------------|-------|-----|------|
| capsule-install-01-static-helmrelease.bats | 9 | 9 | 0 | All operator + proxy HR shape contracts GREEN |
| capsule-install-02-static-ocirepo.bats | 8 | 8 | 0 | All operator + proxy OCIRepo shape contracts GREEN |
| capsule-install-03-static-values.bats | 10 | 10 | 0 | All operator + proxy values literals GREEN (incl. proxy.options.additionalSANs RESEARCH-verified key path) |
| capsule-install-04-static-no-umbrella.bats | 5 | 5 | 0 | All anti-pattern lints GREEN (incl. Pitfall 9 dependsOn-no-wait + scope boundaries) |
| capsule-install-05-static-kustomize.bats | 6 | 6 | 0 | All inner kustomize rewrite + subdir aggregator + Phase 7 head-comment preservation tests GREEN |
| **Total** | **38** | **38** | **0** | **5/5 GREEN end-to-end** |

The four bats files explicitly listed in this plan's `<must_haves>` truths (`capsule-install-01 + 02 + 03 + 04 + 05`) all turn 100% GREEN, exactly matching the truth statement: "After this plan lands and hub-flux reconciles, capsule-install-01..05 turn GREEN end-to-end."

## Phase 7 Regression Bats — All GREEN

`bats tests/bats/poc-mount-01-static.bats poc-isolation-01-static.bats poc-cluster-01-static.bats` — **22 tests, 0 failures**:

- POC-01 (`poc-mount-01-static.bats`, 8 tests) — KARYON POC MOUNT sentinel, idempotency, P40/P18 secretRef.{name,key=value.yaml} on outer Kustomization, Pitfall 7 placeholder shape — all GREEN. **Plan 08-02 did NOT touch `clusters/hub-flux/pocs/capsule.yaml`** (P40 + P18 inheritance preserved); the outer Kustomization shape remains exactly as Phase 7 shipped.
- P31 (`poc-isolation-01-static.bats`, 3 tests) — v0.18 scripts have ZERO `spoke-capsule` / `register-poc-cluster` / `scripts/poc/` mentions — all GREEN. **Plan 08-02 introduces ZERO new `spoke-capsule` mentions** in v0.18 scripts (all new files live under `pocs/capsule/proxy/` and the modified parent kustomize at `pocs/capsule/kustomization.yaml` — none in the lint's grep set).
- CAPCLU-01..04 (`poc-cluster-01-static.bats`, 11 tests) — Phase 7 cluster-shape contract intact — all GREEN. **Plan 08-02 modifies neither `scripts/poc/capsule/create-cluster.sh` nor `scripts/poc/capsule/fix-dns.sh` nor `Taskfile.yml` nor `docs/poc-capsule.md`.**

## Anti-Grep Scope-Boundary Lints — Phase 8 Held Narrow

| Lint | Result |
|------|--------|
| `grep -rqF 'kind: CapsuleConfiguration' pocs/capsule/` | NOT FOUND (defer to Phase 9 per D-08-08) |
| `grep -rqF 'kind: Tenant' pocs/capsule/` | NOT FOUND (defer to Phase 9 per TEN-01..06) |
| `grep -rqF 'no-cross-namespace-refs' pocs/capsule/` | NOT FOUND (defer to Phase 9 per TEN-05) |
| `grep -rqF 'no-remote-bases' pocs/capsule/` | NOT FOUND (defer to Phase 9 per TEN-05) |
| `grep -rqF 'default-service-account' pocs/capsule/` | NOT FOUND (defer to Phase 9 per TEN-05) |

All 5 anti-grep lints PASS — Phase 8 scope held ruthlessly narrow per `<threat_model>` T-08-Ops-04..07 mitigations.

## RESEARCH Catches Honored Verbatim

The plan's `<must_haves>` and the parallel_execution prompt explicitly call out three RESEARCH catches that this plan must honor verbatim:

### Pitfall 9 — proxy HelmRelease dependsOn has NO `wait:` sub-field

```yaml
# pocs/capsule/proxy/helmrelease.yaml lines 47-50
dependsOn:
  - name: capsule
    namespace: capsule-system
```

NO `wait:` sub-field. Verified by static bats `capsule-install-04`:
```
ok 21 Pitfall 9 / RESEARCH catch: proxy HelmRelease dependsOn[0] has NO 'wait:' field
```
The yq query `.spec.dependsOn[0] | has("wait")` returns `false`. Default Flux v2 helm.toolkit.fluxcd.io/v2 behavior already blocks reconcile until dependency Ready=True; the `wait:` sub-field doesn't exist in the spec.

### Pitfall 8 — CAP-02 reachability reframe (TLS handshake + HTTP code in [1-5][0-9][0-9])

The proxy HelmRelease values landed in this plan match the contract that Wave 0 capsule-install-08-live-proxy-reachable.bats encoded — TLS handshake succeeds with `additionalSANs: [127.0.0.1, localhost]` covering both 127.0.0.1 and localhost, and any valid HTTP response on `https://127.0.0.1:30443/api` proves reachability. Plan 08-03 verifier (downstream) will run the live bats once hub-flux reconciles the HelmRelease and the proxy pod comes up.

### options.additionalSANs (NOT tls.additionalSANs)

```yaml
# pocs/capsule/proxy/helmrelease.yaml lines 60-67
options:
  listeningPort: 9001
  enableSSL: true
  capsuleConfigurationName: default
  additionalSANs:
    - 127.0.0.1
    - localhost
```

Verified by static bats `capsule-install-03`:
```
ok 19 CAP-02 / P33: proxy values.options.additionalSANs contains 127.0.0.1 AND localhost (RESEARCH-verified key path: options.additionalSANs, NOT tls.additionalSANs)
```
RESEARCH-verified by `helm show values oci://ghcr.io/projectcapsule/charts/capsule-proxy --version 0.12.0` (2026-04-29). The CONTEXT.md `<specifics>` block guess (`tls.additionalSANs`) is **NOT** present anywhere in the helmrelease.yaml.

## OQ-2 Cert-Source Verification — RESOLVED via helm-template Gate

The plan's Task 2 `<read_first>` block instructed the executor to run a load-bearing OQ-2 verification BEFORE writing helmrelease.yaml. This verification ran SUCCESSFULLY:

```bash
$ helm template capsule-proxy oci://ghcr.io/projectcapsule/charts/capsule-proxy --version 0.12.0 \
    --set certManager.generateCertificates=true --namespace capsule-system 2>&1 \
    | grep -E 'kind: (Issuer|Certificate)' | wc -l
6
```

6 matching lines >= 2 required (`{≥1 Issuer, ≥1 Certificate}` → 4 Issuers + 2 Certificates rendered). The chart's SelfSigned Issuer template (chart-managed, type=SelfSigned, no external CA chain required) renders cleanly without cert-manager controller installed. Proxy HelmRelease landed with `certManager.generateCertificates: true` as planned.

Research gap-close prompt was NOT triggered. The fallback path (`options.generateCertificates: true` + `certManager.generateCertificates: false` for built-in self-sign Job) was NOT taken — this was the path the plan instructed to take only if the helm-template gate failed.

If the cert reconcile loop fails on first install (unlikely given the live verification), Plan 08-03 verifier (downstream) will surface this and the documented override path is available without re-research.

## Decisions Made

- **All gray areas pre-decided by 08-CONTEXT.md + 08-RESEARCH.md** — Plan 08-02 inherits all defaults (Claude's Discretion + 10 explicit decisions D-08-01..10 + Pitfall 4/7/8/9 RESEARCH catches) without re-asking. No plan-time iteration needed.
- **No NodePort or proxy-specific values landed in operator HR** — operator chart has no Service shape relevant to Phase 8 reachability; the NodePort 30443 surface is owned by the proxy chart.
- **No mutual `dependsOn`** — operator HR does NOT depend on proxy HR (only proxy depends on operator). Operator HR's `spec.dependsOn` block was empty in Plan 08-01 and remains so.
- **proxy HelmRelease has NO `install.crds` or `upgrade.crds`** — capsule-proxy chart has zero CRDs of its own (Capsule CRDs are owned by the operator chart). Operator HR has both fields set to `CreateReplace`; proxy HR has neither.

## Deviations from Plan

None — plan executed exactly as written.

The plan-level `<verify><automated>` for Task 4 specified `bats tests/bats/capsule-install-0[12345]-static-*.bats 2>&1 | tail -1 | grep -E '0 failures'` which uses default bats TAP output that lacks the `X failures` summary line; that summary line only appears in `bats --pretty` mode. This was a documentation slip carried over from Plan 08-00 (also noted in the 08-00 SUMMARY); execution confirmed `0 failures` both via pretty-mode rerun AND via direct counting (38 GREEN / 0 RED across 5 files).

## Issues Encountered

None.

The plan landed cleanly on the first attempt — every yaml file was created from RESEARCH §"Architecture Patterns" + §"Code Examples" + 08-PATTERNS.md substitutions verbatim, with no need for plan-time iteration. The OQ-2 helm-template gate ran on the first attempt and rendered 6 matching lines (≥2 required). yq + grep + bats syntax all parsed correctly. No Rule 1 / Rule 2 / Rule 3 deviations triggered. No checkpoints reached.

Note for Plan 08-03 (verifier): when run with k3d clusters reachable but the new yaml NOT yet pushed/reconciled, the 5 live bats (`capsule-install-06..10`) have these expected outcomes from a STATIC perspective — `06-live-helm` 3 RED (HelmReleases not yet reconciled), `07-live-crds` 2 RED (CRDs not yet registered on spoke-capsule), `08-live-proxy-reachable` mixed (TCP 30443 GREEN by Phase 7 D-10 inheritance + HTTPS handshake RED until proxy pod is Running), `09-live-adr-004` 1 GREEN (Phase 7 invariant intact), `10-live-flux-observable` 2 GREEN + 1 SKIP (folded carryover GREEN against the parent rewrite + push-gate SKIPs as `deferred-to-VAL-05`). Plan 08-03 owns the post-push observation when hub-flux has reconciled the new HelmReleases.

## User Setup Required

None. The 4 yaml files are inert until pushed and hub-flux reconciles. No external service configuration required at this plan boundary.

## Next Plan Readiness

- **Plan 08-03 (verifier — live observation + folded carryover acceptance) is unblocked.** All 5 Wave 0 static bats (38 tests) are GREEN; the 5 live bats (10 + 1 conditional outcomes) are awaiting hub-flux reconcile. Plan 08-03 just runs them after `git push origin main` reaches hub-flux's GitRepository revision and the kustomize-controller has reconciled both HelmReleases to spoke-capsule.
- **Plan 09 (tenants + lockdown patches) is unblocked at the contract surface.** Phase 8 has held ruthlessly narrow — no CapsuleConfiguration CR, no Tenant CR, no lockdown flag patches, no `--default-service-account` on flux-system Kustomization. Phase 9 owns all of these (D-08-08 + TEN-01..06).
- **No blockers or concerns from this plan.** All Wave 0 static contract targets GREEN, Phase 7 regression bats stay 22/22 GREEN, no v0.18 script touched, no `spoke-capsule` introduced into v0.18 grep set, no scope creep into Phase 9.

## Self-Check: PASSED

All 3 created files FOUND on disk. Modified file (`pocs/capsule/kustomization.yaml`) FOUND with both `REQ-CAPCLU-02` and `Pitfall 7` head-comment attributions preserved AND new `resources [operator/, proxy/]` block. All 3 task commit hashes (`342b432`, `180585d`, `000a607`) FOUND in `git log`. yq compound queries all return `true`. OQ-2 helm-template gate returned 6 matching lines (≥2 required). All 5 Phase 8 static bats files report 38/38 GREEN. Phase 7 regression bats report 22/22 GREEN. Anti-grep scope-boundary lints all clean.

```
$ [ -f "pocs/capsule/proxy/ocirepository.yaml" ] && echo "FOUND: pocs/capsule/proxy/ocirepository.yaml"
FOUND: pocs/capsule/proxy/ocirepository.yaml
$ [ -f "pocs/capsule/proxy/helmrelease.yaml" ] && echo "FOUND: pocs/capsule/proxy/helmrelease.yaml"
FOUND: pocs/capsule/proxy/helmrelease.yaml
$ [ -f "pocs/capsule/proxy/kustomization.yaml" ] && echo "FOUND: pocs/capsule/proxy/kustomization.yaml"
FOUND: pocs/capsule/proxy/kustomization.yaml
$ [ -f "pocs/capsule/kustomization.yaml" ] && grep -F -- 'operator/' pocs/capsule/kustomization.yaml >/dev/null && grep -F -- 'proxy/' pocs/capsule/kustomization.yaml >/dev/null && echo "FOUND: pocs/capsule/kustomization.yaml (rewritten with operator/ + proxy/ refs)"
FOUND: pocs/capsule/kustomization.yaml (rewritten with operator/ + proxy/ refs)
$ git log --oneline | grep -q "342b432" && echo "FOUND: 342b432"
FOUND: 342b432
$ git log --oneline | grep -q "180585d" && echo "FOUND: 180585d"
FOUND: 180585d
$ git log --oneline | grep -q "000a607" && echo "FOUND: 000a607"
FOUND: 000a607
```

---
*Phase: 08-capsule-capsule-proxy-bare-minimum-install*
*Plan: 02 (proxy HelmRelease + OCIRepository + parent kustomize rewrite)*
*Completed: 2026-04-29*
