# Phase 8: Capsule + capsule-proxy Bare-Minimum Install — Pattern Map

**Mapped:** 2026-04-29
**Files analyzed:** 17 (16 NEW + 1 MODIFIED)
**Analogs found:** 13 / 17 (4 net-new shapes — Flux v2 HelmRelease + OCIRepository — have NO existing repo analog; planner uses RESEARCH.md §"Architecture Patterns" Patterns 1+2 verbatim)

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `pocs/capsule/operator/kustomization.yaml` | Kustomize aggregator (subdir) | declarative; resolved by parent kustomize-build | `clusters/hub-flux/spokes/kustomization.yaml` | exact (peer aggregator) |
| `pocs/capsule/operator/ocirepository.yaml` | Flux source manifest (OCIRepository v1) | source-controller fetches OCI chart on `interval` | none in repo — RESEARCH.md §"Pattern 1" | no-analog (greenfield) |
| `pocs/capsule/operator/helmrelease.yaml` | Flux state manifest (HelmRelease v2) | helm-controller reconciles via `kubeConfig.secretRef` to spoke-capsule | none in repo — RESEARCH.md §"Pattern 2" | no-analog (greenfield) |
| `pocs/capsule/proxy/kustomization.yaml` | Kustomize aggregator (subdir) | declarative; resolved by parent kustomize-build | `clusters/hub-flux/spokes/kustomization.yaml` | exact (peer aggregator) |
| `pocs/capsule/proxy/ocirepository.yaml` | Flux source manifest (OCIRepository v1) | source-controller fetches OCI chart on `interval` | none in repo — RESEARCH.md §"Pattern 1" | no-analog (greenfield) |
| `pocs/capsule/proxy/helmrelease.yaml` | Flux state manifest (HelmRelease v2) | helm-controller reconciles + `dependsOn: capsule` blocks until operator Ready=True | none in repo — RESEARCH.md §"Pattern 2" | no-analog (greenfield) |
| `tests/bats/capsule-install-01-static-helmrelease.bats` | Static contract bats | yq-eval + grep -F on committed YAML | `tests/bats/poc-mount-01-static.bats` | exact (yq+grep static contract) |
| `tests/bats/capsule-install-02-static-ocirepo.bats` | Static contract bats | yq-eval on committed YAML | `tests/bats/poc-mount-01-static.bats` | exact |
| `tests/bats/capsule-install-03-static-values.bats` | Static contract bats | yq-eval on HelmRelease values block | `tests/bats/poc-mount-01-static.bats` | exact |
| `tests/bats/capsule-install-04-static-no-umbrella.bats` | Static anti-pattern lint bats | grep -F negative assertions on committed YAML | `tests/bats/fix-coredns-01-static.bats` (grep `-v ^#` + grep -F negative pattern) | exact |
| `tests/bats/capsule-install-05-static-kustomize.bats` | Static contract bats | yq-eval on `pocs/capsule/kustomization.yaml` | `tests/bats/poc-mount-01-static.bats` | exact |
| `tests/bats/capsule-install-06-live-helm.bats` | Live integration bats (cluster-info gated) | `flux get helmrelease ... --context k3d-hub-flux` parsing | RESEARCH.md §"Pattern 4" + `tests/bats/phase5-02-live.bats` | role-match (live `kubectl --context` pattern) |
| `tests/bats/capsule-install-07-live-crds.bats` | Live integration bats (cluster-info gated) | `kubectl --context=k3d-spoke-capsule get crds` count | RESEARCH.md §"Code Examples Example 4" + `tests/bats/phase5-02-live.bats` | role-match |
| `tests/bats/capsule-install-08-live-proxy-reachable.bats` | Live integration bats (cluster-info gated) | `curl -k https://127.0.0.1:30443/...` HTTP code parsing | RESEARCH.md §"Pitfall 8 Option A" — no in-repo curl-based bats analog | partial (live bats setup pattern only) |
| `tests/bats/capsule-install-09-live-adr-004.bats` | Live integration bats (cluster-info gated) | `kubectl --context=k3d-spoke-capsule get pods -n flux-system` count=0 | RESEARCH.md §"Code Examples Example 5" + `tests/bats/phase5-02-live.bats` | role-match |
| `tests/bats/capsule-install-10-live-flux-observable.bats` | Live integration bats (cluster-info gated) | `flux get kustomization poc-capsule ... --context k3d-hub-flux` Ready=True | RESEARCH.md §"Pattern 5" carryover assertion | role-match |
| `pocs/capsule/kustomization.yaml` (MODIFY) | Kustomize aggregator (top-level) | resolved by outer Flux Kustomization `poc-capsule.spec.path: ./pocs/capsule` | `clusters/hub-flux/spokes/kustomization.yaml` (peer aggregator) | role-match (rewrite from `resources: []` to `resources: [operator/, proxy/]`) |

**Match quality legend:**
- **exact** — same role + same data flow; copy pattern verbatim with substitutions
- **role-match** — same role; data flow differs slightly (e.g., live vs static); adapt setup/imports
- **partial** — only structural skeleton transfers (e.g., bats file shape); core logic per RESEARCH
- **no-analog** — greenfield in repo; planner uses RESEARCH.md §"Architecture Patterns" verbatim

---

## Pattern Assignments

### `pocs/capsule/operator/kustomization.yaml` (Kustomize aggregator, subdir)

**Analog:** `clusters/hub-flux/spokes/kustomization.yaml` (lines 1-5)

**Imports/header pattern** (no header — minimal Kustomize subdir aggregator):
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- spoke-ml.yaml
- spoke-apps.yaml
```

**Substitutions for Phase 8 operator subdir:**
- Add `namespace: capsule-system` line per RESEARCH §"Pattern 3" (belt-and-suspenders default)
- Replace `resources` list with `[ocirepository.yaml, helmrelease.yaml]`

**Target shape:**
```yaml
# pocs/capsule/operator/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: capsule-system
resources:
- ocirepository.yaml
- helmrelease.yaml
```

---

### `pocs/capsule/proxy/kustomization.yaml` (Kustomize aggregator, subdir)

**Analog:** `clusters/hub-flux/spokes/kustomization.yaml` (same as operator subdir)

**Target shape (mirror of operator subdir):**
```yaml
# pocs/capsule/proxy/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: capsule-system
resources:
- ocirepository.yaml
- helmrelease.yaml
```

---

### `pocs/capsule/operator/ocirepository.yaml` (Flux v1 OCIRepository)

**Analog:** **None in repo.** Phase 8 introduces the first OCIRepository to karyon.

**Pattern source:** `08-RESEARCH.md` §"Architecture Patterns → Pattern 1: Per-chart OCIRepository (D-08-02)" lines 310-327.

**Verified shape (copy verbatim, swap chart name + tag for proxy variant):**
```yaml
# pocs/capsule/operator/ocirepository.yaml
# Verified against Flux v1 SourceController API:
#   https://fluxcd.io/flux/components/source/api/v1/
# Verified against helm show values oci://ghcr.io/projectcapsule/charts/capsule --version 0.12.4 (2026-04-29)
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: capsule
  namespace: capsule-system
spec:
  interval: 24h                              # tag-pinned; 24h cadence is sufficient
  url: oci://ghcr.io/projectcapsule/charts/capsule
  ref:
    tag: "0.12.4"                            # D-08-02 — exact tag pin, NOT semver/digest
  layerSelector:
    mediaType: application/vnd.cncf.helm.chart.content.v1.tar+gzip
```

**Critical invariants (verify in static bats):**
- `apiVersion: source.toolkit.fluxcd.io/v1` (modern v1, NOT v1beta2)
- `metadata.name: capsule` (matches `helmrelease.yaml` `spec.chartRef.name`)
- `metadata.namespace: capsule-system`
- `spec.ref.tag: "0.12.4"` (literal string, quoted)
- `spec.url: oci://ghcr.io/projectcapsule/charts/capsule` (no trailing colon, no tag suffix)
- `spec.layerSelector.mediaType: application/vnd.cncf.helm.chart.content.v1.tar+gzip` (canonical Helm chart layer)
- NO `secretRef` / `serviceAccountName` (public ghcr.io requires no auth)

---

### `pocs/capsule/proxy/ocirepository.yaml` (Flux v1 OCIRepository)

**Analog:** Same Pattern 1 as operator OCIRepository.

**Pattern source:** `08-RESEARCH.md` §"Architecture Patterns → Pattern 1" lines 332-344.

**Substitutions vs operator variant:**
- `metadata.name: capsule` → `metadata.name: capsule-proxy`
- `spec.url: oci://ghcr.io/projectcapsule/charts/capsule` → `spec.url: oci://ghcr.io/projectcapsule/charts/capsule-proxy`
- `spec.ref.tag: "0.12.4"` → `spec.ref.tag: "0.12.0"`
- All other fields verbatim

**Target shape:**
```yaml
# pocs/capsule/proxy/ocirepository.yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: capsule-proxy
  namespace: capsule-system
spec:
  interval: 24h
  url: oci://ghcr.io/projectcapsule/charts/capsule-proxy
  ref:
    tag: "0.12.0"
  layerSelector:
    mediaType: application/vnd.cncf.helm.chart.content.v1.tar+gzip
```

---

### `pocs/capsule/operator/helmrelease.yaml` (Flux v2 HelmRelease — operator)

**Analog:** **None in repo.** Phase 8 introduces the first HelmRelease.

**Pattern source:** `08-RESEARCH.md` §"Architecture Patterns → Pattern 2: HelmRelease v2 with chartRef → OCIRepository" lines 362-435 + `08-RESEARCH.md` §"Code Examples → Example 1: Operator HelmRelease values block" lines 866-927.

**`kubeConfig.secretRef` pattern** (P18 / P40 inheritance — matches `clusters/hub-flux/pocs/capsule.yaml` lines 24-27 verbatim):
```yaml
  kubeConfig:                                   # P18 / P40 inheritance — outer Kustomization already does this; HelmRelease MUST too
    secretRef:
      name: spoke-capsule-kubeconfig
      key: value.yaml                           # explicit; defends against silent in-cluster fallback
```

**Core HelmRelease shape (copy verbatim from RESEARCH §"Pattern 2"):**
```yaml
# pocs/capsule/operator/helmrelease.yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: capsule
  namespace: capsule-system
spec:
  interval: 5m                                  # D-08-06 — explicit, matches outer Kustomization cadence
  releaseName: capsule
  targetNamespace: capsule-system               # Claude's Discretion default
  storageNamespace: capsule-system              # Helm release Secret co-located
  install:
    createNamespace: true                       # Claude's Discretion default
    crds: CreateReplace                         # Claude's Discretion default
    remediation:
      retries: 3
  upgrade:
    crds: CreateReplace
    remediation:
      retries: 3
  chartRef:                                     # POST-2024 modern shape (NOT spec.chart.spec.chart)
    kind: OCIRepository
    name: capsule                               # references pocs/capsule/operator/ocirepository.yaml
  kubeConfig:
    secretRef:
      name: spoke-capsule-kubeconfig
      key: value.yaml
  values:
    # ⏷ values block — see RESEARCH §"Code Examples Example 1" for exact verified key paths
```

**Operator values block** (copy verbatim from RESEARCH §"Example 1" lines 866-927):
```yaml
  values:
    tls:
      enableController: true   # D-08-04 — built-in certgen
      create: true
    certManager:
      generateCertificates: false  # default already false; explicit anti-pattern lint
    crds:
      install: true
    webhooks:
      hooks:
        tenants:
          failurePolicy: Ignore
        tenantLabel:
          failurePolicy: Ignore
        customresources:
          failurePolicy: Ignore
        namespaces:
          failurePolicy: Ignore
        pods:
          failurePolicy: Ignore
        services:
          failurePolicy: Ignore
        ingresses:
          failurePolicy: Ignore
        persistentvolumeclaims:
          failurePolicy: Ignore
        networkpolicies:
          failurePolicy: Ignore
        gateways:
          failurePolicy: Ignore
        cordoning:
          failurePolicy: Ignore
        devices:
          failurePolicy: Ignore
        serviceaccounts:
          failurePolicy: Ignore
        tenantResourceObjects:
          failurePolicy: Ignore
    replicaCount: 1
    proxy:
      enabled: false  # default already false; explicit anti-pattern lint
```

**Critical invariants (verify in static bats):**
- `apiVersion: helm.toolkit.fluxcd.io/v2` (modern v2, NOT v2beta2)
- `spec.chartRef.kind: OCIRepository` + `spec.chartRef.name: capsule` (modern shape — NOT legacy `spec.chart.spec.chart`)
- `spec.kubeConfig.secretRef.name: spoke-capsule-kubeconfig` (P18 inheritance from `clusters/hub-flux/pocs/capsule.yaml`)
- `spec.kubeConfig.secretRef.key: value.yaml` (P18 — explicit key against silent in-cluster fallback)
- `spec.interval: 5m` (D-08-06 explicit)
- `spec.targetNamespace: capsule-system` + `spec.install.createNamespace: true`
- `spec.upgrade.crds: CreateReplace`
- `spec.values.tls.enableController: true` (D-08-04 built-in certgen)
- `spec.values.certManager.generateCertificates: false` (anti-pattern lint)
- `spec.values.webhooks.hooks.tenants.failurePolicy: Ignore` (P26 belt-and-suspenders, plus the 13 other hooks)
- `spec.values.proxy.enabled: false` (anti-umbrella explicit)

---

### `pocs/capsule/proxy/helmrelease.yaml` (Flux v2 HelmRelease — proxy)

**Analog:** Same Pattern 2 as operator HelmRelease, plus `dependsOn` block.

**Pattern source:** `08-RESEARCH.md` §"Architecture Patterns → Pattern 2" lines 440-492 + `08-RESEARCH.md` §"Code Examples → Example 2: Proxy HelmRelease values block" lines 933-967.

**Substitutions vs operator HelmRelease:**
- `metadata.name: capsule` → `metadata.name: capsule-proxy`
- `spec.releaseName: capsule` → `spec.releaseName: capsule-proxy`
- `spec.chartRef.name: capsule` → `spec.chartRef.name: capsule-proxy`
- ADD `spec.dependsOn` block (proxy waits for operator)
- REMOVE `spec.install.crds` and `spec.upgrade.crds` (proxy chart has no CRDs)
- Replace `values` block with proxy-specific values

**`dependsOn` shape (Pitfall 9 catch — NO `wait:` field):**
```yaml
  # D-08-07 — proxy waits for operator HelmRelease Ready=True before reconciling.
  # NOTE: dependsOn DOES NOT support a `wait: true` field per Flux v2 HelmRelease spec —
  # default behavior IS "block until dependency Ready=True." See Pitfall 9.
  dependsOn:
    - name: capsule
      namespace: capsule-system
```

**Proxy values block** (copy verbatim from RESEARCH §"Example 2" lines 933-967):
```yaml
  values:
    service:
      type: NodePort
      port: 9001
      portName: proxy
      nodePort: 30443         # D-10 / Phase 7 inheritance — k3d already publishes this
    options:
      listeningPort: 9001
      enableSSL: true
      capsuleConfigurationName: default
      additionalSANs:
        - 127.0.0.1
        - localhost
      authPreferredTypes: "BearerToken,TLSCertificate"
    certManager:
      generateCertificates: true  # ⚠ TENTATIVE — see OQ-2 (Plan 08-02 verifies via helm template)
    webhooks:
      enabled: false
    replicaCount: 1
```

**Critical invariants (verify in static bats):**
- `apiVersion: helm.toolkit.fluxcd.io/v2`
- `spec.chartRef.kind: OCIRepository` + `spec.chartRef.name: capsule-proxy`
- `spec.kubeConfig.secretRef.name: spoke-capsule-kubeconfig` + `key: value.yaml` (P18)
- `spec.interval: 5m`
- `spec.dependsOn[0].name: capsule` + `spec.dependsOn[0].namespace: capsule-system`
- `spec.dependsOn[0]` has NO `wait` field (Pitfall 9 anti-pattern lint — assert via `yq eval '.spec.dependsOn[0] | has("wait")'` returns `false`)
- `spec.values.service.type: NodePort`, `spec.values.service.nodePort: 30443`
- `spec.values.options.additionalSANs` includes `127.0.0.1` AND `localhost` (P33)

---

### `pocs/capsule/kustomization.yaml` (MODIFY — top-level Kustomize aggregator)

**Analog:** `clusters/hub-flux/spokes/kustomization.yaml` (lines 1-5) for the rewrite shape.

**Existing file (read first — REPO_ROOT/pocs/capsule/kustomization.yaml lines 1-11):**
```yaml
# pocs/capsule/kustomization.yaml
# Phase 7 placeholder so the outer Flux Kustomization
# (clusters/hub-flux/pocs/capsule.yaml, spec.path: ./pocs/capsule) reconciles
# successfully against an empty resource list. Phase 8 will replace `resources: []`
# with `[operator, proxy, config]` once the HelmReleases land.
#
# REQ-CAPCLU-02 (Pitfall 7 — without this file the outer Kustomization reports
# Ready=False; path not found).
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources: []
```

**Substitutions per D-08-05:**
- PRESERVE the Phase 7 head comment block (REQ-CAPCLU-02 + Pitfall-7 attribution)
- APPEND a Phase 8 update note to the comment block (NOT replacing)
- Replace `resources: []` with `resources:` followed by `- operator/` and `- proxy/`

**Target shape (per RESEARCH §"Pattern 3" lines 510-524):**
```yaml
# pocs/capsule/kustomization.yaml
# Phase 7 placeholder so the outer Flux Kustomization
# (clusters/hub-flux/pocs/capsule.yaml, spec.path: ./pocs/capsule) reconciles
# successfully against an empty resource list. Phase 8 will replace `resources: []`
# with `[operator, proxy, config]` once the HelmReleases land.
#
# REQ-CAPCLU-02 (Pitfall 7 — without this file the outer Kustomization reports
# Ready=False; path not found).
#
# Phase 8 update (D-08-05): operator/ and proxy/ subdir refs added — outer
# poc-capsule Flux Kustomization now reconciles operator HelmRelease + proxy
# HelmRelease + their per-chart OCIRepositories under capsule-system on
# spoke-capsule via spoke-capsule-kubeconfig. Phase 9 will append config/ + tenants/.
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- operator/
- proxy/
```

**Critical invariants:**
- Trailing slashes on `operator/` and `proxy/` (signals "directory" to readers)
- Phase 7 head comment block PRESERVED (REQ-CAPCLU-02 attribution + Pitfall-7 attribution)
- Phase 8 update note APPENDED (single comment block, NOT replacing Phase 7 attribution)

---

### `tests/bats/capsule-install-01-static-helmrelease.bats` (Static contract bats — HR shape)

**Analog:** `tests/bats/poc-mount-01-static.bats` (lines 1-69) — yq-eval pattern on Kustomize/Flux YAML.

**`load + setup` pattern (lines 1-13):**
```bash
#!/usr/bin/env bats
# tests/bats/poc-mount-01-static.bats
# POC-01 — sentinel + pocs/ aggregator + capsule.yaml outer Kustomization + placeholder shape

load 'test_helper'

setup() {
  HUB_FS_KUST="${REPO_ROOT}/clusters/hub-flux/flux-system/kustomization.yaml"
  HUB_PEER_KUST="${REPO_ROOT}/clusters/hub-flux/kustomization.yaml"
  POCS_INDEX="${REPO_ROOT}/clusters/hub-flux/pocs/kustomization.yaml"
  POCS_CAPSULE="${REPO_ROOT}/clusters/hub-flux/pocs/capsule.yaml"
  POCS_PLACEHOLDER="${REPO_ROOT}/pocs/capsule/kustomization.yaml"
}
```

**`yq eval` pattern (lines 50-62) — copy verbatim with substitutions:**
```bash
@test "POC-01 / D-11 / P40: clusters/hub-flux/pocs/capsule.yaml carries spec.kubeConfig.secretRef.name and key value.yaml" {
  [ -f "$POCS_CAPSULE" ]
  run yq eval '.apiVersion == "kustomize.toolkit.fluxcd.io/v1" and .kind == "Kustomization" and .metadata.name == "poc-capsule" and .metadata.namespace == "flux-system" and .spec.path == "./pocs/capsule" and .spec.kubeConfig.secretRef.name == "spoke-capsule-kubeconfig" and .spec.kubeConfig.secretRef.key == "value.yaml" and .spec.prune == true' "$POCS_CAPSULE"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}
```

**Substitutions for Phase 8 operator HR test:**
- `POCS_CAPSULE` → `OPERATOR_HR="${REPO_ROOT}/pocs/capsule/operator/helmrelease.yaml"`
- yq path `.apiVersion == "kustomize.toolkit.fluxcd.io/v1"` → `.apiVersion == "helm.toolkit.fluxcd.io/v2"`
- yq path `.kind == "Kustomization"` → `.kind == "HelmRelease"`
- yq path `.metadata.name == "poc-capsule"` → `.metadata.name == "capsule"`
- ADD assertions: `.spec.chartRef.kind == "OCIRepository"`, `.spec.chartRef.name == "capsule"`, `.spec.interval == "5m"`, `.spec.targetNamespace == "capsule-system"`, `.spec.kubeConfig.secretRef.name == "spoke-capsule-kubeconfig"`, `.spec.kubeConfig.secretRef.key == "value.yaml"`

**Mirror tests for proxy HelmRelease in same file** — same shape with `metadata.name == "capsule-proxy"`, `chartRef.name == "capsule-proxy"`, plus `dependsOn[0].name == "capsule"`, `dependsOn[0].namespace == "capsule-system"`.

---

### `tests/bats/capsule-install-02-static-ocirepo.bats` (Static contract bats — OCIRepo shape)

**Analog:** `tests/bats/poc-mount-01-static.bats` (lines 1-13 setup + lines 50-62 yq pattern).

**Substitutions:**
- `setup()` paths: `OPERATOR_OCIREPO="${REPO_ROOT}/pocs/capsule/operator/ocirepository.yaml"`, `PROXY_OCIREPO="${REPO_ROOT}/pocs/capsule/proxy/ocirepository.yaml"`
- yq paths: `.apiVersion == "source.toolkit.fluxcd.io/v1"`, `.kind == "OCIRepository"`, `.metadata.name == "capsule"` (operator) / `"capsule-proxy"` (proxy), `.spec.url == "oci://ghcr.io/projectcapsule/charts/capsule"` / `"oci://ghcr.io/projectcapsule/charts/capsule-proxy"`, `.spec.ref.tag == "0.12.4"` / `"0.12.0"`

---

### `tests/bats/capsule-install-03-static-values.bats` (Static contract bats — chart values literals)

**Analog:** `tests/bats/poc-mount-01-static.bats` (yq-eval pattern).

**Substitutions:**
- `setup()` paths: `OPERATOR_HR`, `PROXY_HR`
- yq paths for operator: `.spec.values.tls.enableController == true`, `.spec.values.certManager.generateCertificates == false`, `.spec.values.webhooks.hooks.tenants.failurePolicy == "Ignore"`, `.spec.values.replicaCount == 1`, `.spec.values.proxy.enabled == false`
- yq paths for proxy: `.spec.values.service.type == "NodePort"`, `.spec.values.service.nodePort == 30443`, `.spec.values.options.additionalSANs | contains(["127.0.0.1", "localhost"])`

---

### `tests/bats/capsule-install-04-static-no-umbrella.bats` (Anti-pattern lint bats)

**Analog:** `tests/bats/fix-coredns-01-static.bats` (lines 38-72 — grep `-v ^#` + grep -F negative pattern) + `tests/bats/poc-isolation-01-static.bats` (lines 17-32 — `[ "$status" -ne 0 ]` negative assertion).

**`-v ^#` + `grep -F` negative pattern** (`fix-coredns-01-static.bats` lines 38-42):
```bash
@test "MED-2: fix-coredns does not stop spoke-ml" {
  [ -f "$SCRIPT" ]
  run bash -c "grep -v '^[[:space:]]*#' '$SCRIPT' | grep -F -- 'k3d cluster stop spoke-ml'"
  [ "$status" -ne 0 ]
}
```

**Substitutions for Phase 8 anti-umbrella + Pitfall 9 lint:**
- `SCRIPT` → `OPERATOR_HR="${REPO_ROOT}/pocs/capsule/operator/helmrelease.yaml"` and `PROXY_HR="${REPO_ROOT}/pocs/capsule/proxy/helmrelease.yaml"`
- For "operator HR has NO `proxy.enabled: true`" — see RESEARCH §"Code Examples → Example 3" lines 982-989 (note: `proxy.enabled: false` is allowed; only `proxy.enabled: true` is forbidden)
- For "proxy HR `dependsOn[0]` has NO `wait` key" — see RESEARCH §"Example 3" lines 992-998 using `yq eval '.spec.dependsOn[0] | has("wait")'` returns `"false"`

**Reference snippet (RESEARCH §"Code Examples Example 3" lines 982-1006, copy verbatim):**
```bash
@test "D-01-02 anti-grep: operator HelmRelease has NO proxy.enabled: true" {
  [ -f "$OPERATOR_HR" ]
  run grep -F -- 'proxy.enabled' "$OPERATOR_HR"
  if [ "$status" -eq 0 ]; then
    run grep -F -- 'proxy.enabled: true' "$OPERATOR_HR"
    [ "$status" -ne 0 ]
  fi
}

@test "Pitfall 9 anti-grep: proxy HelmRelease dependsOn has NO 'wait:' field" {
  [ -f "$PROXY_HR" ]
  run yq eval '.spec.dependsOn[0] | has("wait")' "$PROXY_HR"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}
```

---

### `tests/bats/capsule-install-05-static-kustomize.bats` (Static contract bats — inner kustomization rewrite)

**Analog:** `tests/bats/poc-mount-01-static.bats` (lines 64-69 — yq-eval on `pocs/capsule/kustomization.yaml`).

**Existing test (lines 64-69) — modify to assert post-rewrite shape:**
```bash
@test "POC-01 / Pitfall 7: pocs/capsule/kustomization.yaml exists with valid Kustomize shape (resources may be empty)" {
  [ -f "$POCS_PLACEHOLDER" ]
  run yq eval '.apiVersion == "kustomize.config.k8s.io/v1beta1" and .kind == "Kustomization" and (has("resources"))' "$POCS_PLACEHOLDER"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}
```

**Substitutions for Phase 8 (D-08-05 rewrite):**
- Tighten yq assertion: `.resources | length == 2 and .resources[0] == "operator/" and .resources[1] == "proxy/"`
- Preserve the existing assertion that `apiVersion == "kustomize.config.k8s.io/v1beta1" and .kind == "Kustomization"`
- ADD: assert head-comment block preserved (grep `-F -- 'REQ-CAPCLU-02 (Pitfall 7'` for head-comment retention)

---

### `tests/bats/capsule-install-06-live-helm.bats` (Live integration bats — HelmRelease Ready=True)

**Analog:** `tests/bats/phase5-02-live.bats` (lines 1-50 — live `kubectl --context k3d-*` pattern) + RESEARCH §"Pattern 4: Live bats gating" lines 569-606.

**`load + setup` pattern (RESEARCH §"Pattern 4" lines 569-579):**
```bash
load 'test_helper'

setup() {
  if ! kubectl --context=k3d-hub-flux cluster-info >/dev/null 2>&1; then
    skip "k3d-hub-flux cluster not reachable; skipping live bats"
  fi
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
}
```

**`flux get` retry pattern (RESEARCH §"Pattern 4" lines 581-593, copy verbatim):**
```bash
@test "CAP-01 live: HelmRelease capsule reports Ready=True" {
  local i
  for i in 1 2 3; do
    run flux get helmrelease capsule -n capsule-system --context k3d-hub-flux
    if [[ "$status" -eq 0 ]] && echo "$output" | grep -qE 'capsule[[:space:]]+.*True'; then
      return 0
    fi
    [[ $i -lt 3 ]] && sleep 30
  done
  echo "$output"
  return 1
}
```

**Substitutions:**
- Mirror @test for `capsule-proxy` HelmRelease — same retry pattern, swap `capsule` → `capsule-proxy`
- ADD @test for `capsule-controller-manager` pod Running on spoke-capsule (CAP-01 secondary signal):
  ```bash
  @test "CAP-01 live: capsule-controller-manager pod Running on spoke-capsule" {
    run kubectl --context=k3d-spoke-capsule -n capsule-system get pod -l app.kubernetes.io/name=capsule -o jsonpath='{.items[*].status.phase}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"Running"* ]]
  }
  ```

**NOTE:** RESEARCH §"Pattern 4" uses inline `kubectl cluster-info` skip-gate (NOT `require_live` from `test_helper.bash`). Phase 8 follows RESEARCH §"Pattern 4" exactly — does not require setting `KARYON_LIVE_TESTS=1`; tests skip on cluster unreachability instead. This matches CONTEXT D-08-09 "auto-skip when the cluster is not yet up".

---

### `tests/bats/capsule-install-07-live-crds.bats` (Live integration bats — ≥7 CRDs)

**Analog:** RESEARCH §"Code Examples → Example 4: CRD presence live bats" lines 1014-1043.

**Pattern source (copy verbatim):**
```bash
load 'test_helper'

setup() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
}

@test "CAP-03 live: ≥7 capsule.clastix.io CRDs registered" {
  local count
  count=$(kubectl --context=k3d-spoke-capsule get crds 2>/dev/null \
    | grep -c '.capsule.clastix.io' || true)
  [[ "$count" -ge 7 ]]
}

@test "CAP-03 live: each of the 7 expected CRD names is present" {
  for crd in tenants capsuleconfigurations globaltenantresources tenantresources \
             resourcepools resourcepoolclaims tenantowners; do
    run kubectl --context=k3d-spoke-capsule get crd "${crd}.capsule.clastix.io"
    [ "$status" -eq 0 ]
  done
}
```

---

### `tests/bats/capsule-install-08-live-proxy-reachable.bats` (Live integration bats — proxy reachability)

**Analog:** RESEARCH §"Pitfall 8 → Option A" lines 812-821 (no in-repo curl-based live bats analog).

**Pattern source (copy verbatim, OQ-1 reframe):**
```bash
load 'test_helper'

setup() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
}

@test "CAP-02 live: capsule-proxy reachable from WSL host (TLS handshake)" {
  local code
  code=$(curl -k -s -o /dev/null -w '%{http_code}' --max-time 5 \
    https://127.0.0.1:30443/api 2>/dev/null) || true
  # Acceptable: 401 (no token), 403 (denied), 404 (path), 200 (proxied),
  # 502 (apiserver upstream issue). Unacceptable: 000 (TLS handshake failed),
  # 7 (connection refused), curl exit non-zero with no code.
  [[ "$code" =~ ^[1-5][0-9][0-9]$ ]]
}
```

---

### `tests/bats/capsule-install-09-live-adr-004.bats` (Live integration bats — ADR-004 invariant)

**Analog:** RESEARCH §"Code Examples → Example 5: ADR-004 invariant live bats" lines 1051-1069.

**Pattern source (copy verbatim):**
```bash
load 'test_helper'

setup() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
}

@test "ADR-004 / domain-boundary-#4: spoke-capsule flux-system ns has zero controllers" {
  run kubectl --context=k3d-spoke-capsule get pods -n flux-system 2>/dev/null
  if [ "$status" -eq 0 ]; then
    local pod_count
    pod_count=$(kubectl --context=k3d-spoke-capsule get pods -n flux-system --no-headers 2>/dev/null | wc -l || true)
    [[ "$pod_count" -eq 0 ]]
  fi
}
```

---

### `tests/bats/capsule-install-10-live-flux-observable.bats` (Live integration bats — folded carryover)

**Analog:** RESEARCH §"Pattern 5: Phase 7 carryover assertion as load-bearing acceptance" lines 614-636 + `tests/bats/phase5-02-live.bats` (live test pattern).

**Pattern source (copy verbatim from RESEARCH §"Pattern 4" lines 599-606):**
```bash
load 'test_helper'

setup() {
  if ! kubectl --context=k3d-hub-flux cluster-info >/dev/null 2>&1; then
    skip "k3d-hub-flux cluster not reachable; skipping live bats"
  fi
}

@test "Phase 7 carryover: outer poc-capsule Kustomization Ready=True" {
  # MUST report Ready=True against a post-Phase-7 source revision.
  # If FAIL: this is a Phase 7 SEAM defect — gap-close to Phase 7 with /gsd-plan-phase 7 --gaps,
  # NOT a Phase 8 install defect.
  run flux get kustomization poc-capsule -n flux-system --context k3d-hub-flux
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -qE 'poc-capsule[[:space:]]+.*True'
}
```

**Additional assertions (per RESEARCH §"Pattern 5" lines 624-635):**
- Confirm `git log origin/main..main` is empty (post-Phase-7 push gate; see RESEARCH OQ-VAL-05 — failure of this step is "deferred-to-VAL-05" NOT a Phase 8 fail)
- Confirm GitRepository revision past `1f2da1d3` (Phase 7 close-out commit)

---

## Shared Patterns

### Authentication / kubeConfig pattern (P18 / P40 inheritance)

**Source:** `clusters/hub-flux/pocs/capsule.yaml` lines 24-27
**Apply to:** Both HelmRelease yamls (`pocs/capsule/{operator,proxy}/helmrelease.yaml`)

**Pattern:**
```yaml
  kubeConfig:
    secretRef:
      name: spoke-capsule-kubeconfig
      key: value.yaml
```

**Why:** Without explicit `key: value.yaml`, Flux v2 silently falls back to default key behavior, which can result in in-cluster reconciliation (P18 silent-misroute). Phase 7's outer Kustomization already has this; HelmReleases MUST match.

---

### Bats `load + setup` pattern (Phase 7 inheritance)

**Source:** `tests/bats/poc-mount-01-static.bats` lines 1-13, `tests/bats/test_helper.bash` lines 22-23 (`REPO_ROOT` resolution)
**Apply to:** All 10 new Phase 8 bats files

**Pattern (static):**
```bash
#!/usr/bin/env bats
load 'test_helper'

setup() {
  OPERATOR_HR="${REPO_ROOT}/pocs/capsule/operator/helmrelease.yaml"
  # ... other path vars
}
```

**Pattern (live, with cluster-info gate per RESEARCH §"Pattern 4"):**
```bash
load 'test_helper'

setup() {
  if ! kubectl --context=k3d-hub-flux cluster-info >/dev/null 2>&1; then
    skip "k3d-hub-flux cluster not reachable; skipping live bats"
  fi
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
}
```

**Why:** `load 'test_helper'` resolves to `tests/bats/test_helper.bash`, which provides `REPO_ROOT` (line 22) and `require_live` helper (line 38). RESEARCH §"Pattern 4" specifies `cluster-info` gating for Phase 8 instead of `require_live` — auto-skips on unreachable cluster without requiring `KARYON_LIVE_TESTS=1` env var. Matches CONTEXT D-08-09 "auto-skip when the cluster is not yet up".

---

### Static contract grep / yq pattern (Phase 7 inheritance)

**Source:** `tests/bats/poc-mount-01-static.bats` lines 16-69 + `tests/bats/poc-cluster-01-static.bats` lines 15-127
**Apply to:** All 5 static Phase 8 bats files (capsule-install-01 through 05)

**`grep -F --` for literal text** (poc-cluster-01-static.bats lines 24-35):
```bash
@test "CAPCLU-01 / D-10: create-cluster.sh pins POC_CLUSTER=spoke-capsule, port 6446, NodePort 30443, k8s-net" {
  [ -f "$CREATE_SCRIPT" ]
  run grep -F -- 'POC_CLUSTER="spoke-capsule"' "$CREATE_SCRIPT"
  [ "$status" -eq 0 ]
  ...
}
```

**`yq eval` for structured assertions** (poc-mount-01-static.bats lines 50-62):
```bash
@test "POC-01 / D-11 / P40: clusters/hub-flux/pocs/capsule.yaml carries spec.kubeConfig..." {
  [ -f "$POCS_CAPSULE" ]
  run yq eval '.spec.kubeConfig.secretRef.name == "spoke-capsule-kubeconfig" and .spec.kubeConfig.secretRef.key == "value.yaml"' "$POCS_CAPSULE"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}
```

**Why:** Two complementary tools. `grep -F --` for literal text matches (e.g., chart pins, comment sentinels). `yq eval` for structured assertions on YAML schema (e.g., apiVersion, kind, nested paths). Both used in every Phase 7 static bats; Phase 8 inherits.

---

### Anti-pattern (negative grep) lint (Phase 7 inheritance)

**Source:** `tests/bats/fix-coredns-01-static.bats` lines 38-72, `tests/bats/poc-isolation-01-static.bats` lines 17-32
**Apply to:** `capsule-install-04-static-no-umbrella.bats`

**Pattern (`grep -v ^# | grep -F`, then assert `$status -ne 0`):**
```bash
@test "P31 / D-12: v0.18 scripts have ZERO spoke-capsule mentions (comments excluded)" {
  for f in "${V018_SCRIPTS[@]}"; do
    [ -f "$f" ]
    run bash -c "grep -v '^[[:space:]]*#' '$f' | grep -F -- 'spoke-capsule'"
    [ "$status" -ne 0 ]
  done
}
```

**Why:** `grep -v '^[[:space:]]*#'` strips comments, so anti-pattern lint matches code only (allows comment attribution like `# proxy.enabled: false  # explicit anti-pattern lint`).

---

### Cross-namespace `kubectl --context=k3d-{cluster}` invocation (Phase 7 inheritance)

**Source:** `tests/bats/phase5-02-live.bats` lines 44-56, `tests/bats/poc-cluster-01-static.bats` lines 89-100
**Apply to:** All 5 live Phase 8 bats files (capsule-install-06 through 10)

**Pattern (Claude's Discretion default per CONTEXT D-08-09 — explicit context, NEVER reads ambient KUBECONFIG):**
```bash
@test "kubeconfig contexts exist after rebuild" {
  run kubectl config get-contexts -o name
  [ "$status" -eq 0 ]
  [[ "$output" == *"k3d-hub-flux"* ]]
  [[ "$output" == *"k3d-spoke-ml"* ]]
  [[ "$output" == *"k3d-spoke-apps"* ]]
}

@test "podinfo Available=True on spoke-apps" {
  run kubectl --context k3d-spoke-apps -n podinfo get deploy podinfo -o jsonpath='{.status.conditions[?(@.type=="Available")].status}'
  [ "$status" -eq 0 ]
  [ "$output" = "True" ]
}
```

**Why:** Explicit `--context=k3d-{cluster}` form — clean failure mode if context is missing; never reads ambient KUBECONFIG. Matches Phase 7 + CONTEXT D-08-09 default.

---

## No Analog Found

Files with no close match in the codebase (planner uses RESEARCH.md patterns instead):

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `pocs/capsule/operator/ocirepository.yaml` | Flux source | OCI chart fetch | Phase 8 introduces the FIRST OCIRepository in karyon. Use RESEARCH §"Pattern 1" lines 310-327 verbatim. |
| `pocs/capsule/proxy/ocirepository.yaml` | Flux source | OCI chart fetch | Same as above; mirror with name + url + tag swap. |
| `pocs/capsule/operator/helmrelease.yaml` | Flux state | helm-controller install via kubeConfig | Phase 8 introduces the FIRST HelmRelease in karyon. Use RESEARCH §"Pattern 2" lines 362-435 + §"Example 1" lines 866-927 verbatim. |
| `pocs/capsule/proxy/helmrelease.yaml` | Flux state | helm-controller install + dependsOn | Same as above; use RESEARCH §"Pattern 2" lines 440-492 + §"Example 2" lines 933-967 verbatim. |
| `tests/bats/capsule-install-08-live-proxy-reachable.bats` | Live curl bats | curl + http_code parsing | No existing curl-based bats in repo; use RESEARCH §"Pitfall 8 Option A" lines 812-821 verbatim. The setup() cluster-info gate matches Pattern 4. |

**Net-new shape recovery:** Even though OCIRepository + HelmRelease have no in-repo analog, RESEARCH.md provides verified-against-`helm show values` reference shapes, plus Flux v2 docs verification. Planner copies RESEARCH excerpts directly. The `kubeConfig.secretRef` block within each HelmRelease IS analog'd (from `clusters/hub-flux/pocs/capsule.yaml` lines 24-27 — see Shared Patterns above).

---

## Regression Reruns (Phase 7 bats — UNCHANGED, must stay GREEN)

These Phase 7 bats files are NOT modified in Phase 8 but Plan 08-03 verifier MUST re-run them as regression gates:

| File | Why Re-run |
|------|------------|
| `tests/bats/poc-isolation-01-static.bats` | P31 / D-12 — confirms Phase 8's new files under `pocs/capsule/operator/` + `pocs/capsule/proxy/` did NOT introduce `spoke-capsule` mentions in v0.18 scripts (none of the new files match the lint's grep set) |
| `tests/bats/poc-mount-01-static.bats` | P40 / P18 — confirms `clusters/hub-flux/pocs/capsule.yaml` still has `secretRef.name: spoke-capsule-kubeconfig` AND `key: value.yaml` (Phase 8 must NOT modify this file) |
| `tests/bats/poc-cluster-01-static.bats` | CAPCLU-01..04 — confirms Phase 7 cluster-shape contract still intact (Phase 8 does NOT modify `scripts/poc/capsule/create-cluster.sh` or `scripts/poc/capsule/fix-dns.sh`) |

---

## Metadata

**Analog search scope:**
- `clusters/hub-flux/` (Flux state files)
- `pocs/capsule/` (Phase 7 placeholder)
- `tests/bats/` (40 existing bats files; identified poc-mount-01, poc-isolation-01, poc-cluster-01, fix-coredns-01, phase5-02, register-poc-cluster-01 as primary analogs)
- `scripts/lib/preflight-lib.sh` (output helpers, sourced via `test_helper.bash`)
- `scripts/poc/capsule/` (Phase 7 POC scripts; analog for verifier-script preamble if planner adds one — none expected per Claude's Discretion)

**Files scanned:** ~50 (Flux yaml + bats + Phase 7 scripts + research/context inputs)

**Pattern extraction date:** 2026-04-29

**RESEARCH.md sections used as no-analog fallback:**
- §"Pattern 1: Per-chart OCIRepository (D-08-02)" lines 304-353
- §"Pattern 2: HelmRelease v2 with chartRef → OCIRepository" lines 354-502
- §"Pattern 3: Inner kustomization.yaml subdir composition" lines 503-554
- §"Pattern 4: Live bats gating (D-08-09)" lines 555-612
- §"Pattern 5: Phase 7 carryover assertion as load-bearing acceptance" lines 614-642
- §"Code Examples → Example 1: Operator HelmRelease values" lines 866-927
- §"Code Examples → Example 2: Proxy HelmRelease values" lines 933-967
- §"Code Examples → Example 3: Anti-pattern lint bats" lines 982-1006
- §"Code Examples → Example 4: CRD presence live bats" lines 1014-1043
- §"Code Examples → Example 5: ADR-004 invariant live bats" lines 1051-1069
- §"Pitfall 8 → Option A (CAP-02 reframe)" lines 812-821
- §"Pitfall 9 → dependsOn no `wait` field" lines 832-847

**Shared pattern attributions:**
- P18/P40 `kubeConfig.secretRef.key: value.yaml` — `clusters/hub-flux/pocs/capsule.yaml:24-27`
- Bats `load + setup` static — `tests/bats/poc-mount-01-static.bats:1-13` + `tests/bats/test_helper.bash:22-23`
- Bats `load + setup` live (cluster-info gate) — RESEARCH §"Pattern 4:569-579"
- `grep -F --` literal-text matching — `tests/bats/poc-cluster-01-static.bats:24-35`
- `yq eval` structured assertions — `tests/bats/poc-mount-01-static.bats:50-62`
- `grep -v '^[[:space:]]*#'` anti-pattern lint — `tests/bats/fix-coredns-01-static.bats:38-42`, `tests/bats/poc-isolation-01-static.bats:17-32`
- Explicit `kubectl --context=k3d-{cluster}` (no ambient KUBECONFIG) — `tests/bats/phase5-02-live.bats:44-56`
