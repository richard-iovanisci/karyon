---
phase: 08-capsule-capsule-proxy-bare-minimum-install
reviewed: 2026-04-29T00:00:00Z
depth: standard
files_reviewed: 17
files_reviewed_list:
  - pocs/capsule/kustomization.yaml
  - pocs/capsule/operator/helmrelease.yaml
  - pocs/capsule/operator/kustomization.yaml
  - pocs/capsule/operator/ocirepository.yaml
  - pocs/capsule/proxy/helmrelease.yaml
  - pocs/capsule/proxy/kustomization.yaml
  - pocs/capsule/proxy/ocirepository.yaml
  - tests/bats/capsule-install-01-static-helmrelease.bats
  - tests/bats/capsule-install-02-static-ocirepo.bats
  - tests/bats/capsule-install-03-static-values.bats
  - tests/bats/capsule-install-04-static-no-umbrella.bats
  - tests/bats/capsule-install-05-static-kustomize.bats
  - tests/bats/capsule-install-06-live-helm.bats
  - tests/bats/capsule-install-07-live-crds.bats
  - tests/bats/capsule-install-08-live-proxy-reachable.bats
  - tests/bats/capsule-install-09-live-adr-004.bats
  - tests/bats/capsule-install-10-live-flux-observable.bats
findings:
  blocker: 1
  warning: 6
  info: 4
  total: 11
status: issues_found
---

# Phase 8: Code Review Report

**Reviewed:** 2026-04-29
**Depth:** standard
**Files Reviewed:** 17 (7 YAML manifests + 10 bats suites)
**Status:** issues_found

## Summary

The shape contracts are well-met: Flux v2 modern syntax (`helm.toolkit.fluxcd.io/v2` + `chartRef`), P18 invariant (`secretRef.key: value.yaml`), Pitfall 9 (no `wait:` in `dependsOn`), D-08-05 inner kustomize shape, and the anti-umbrella scope boundary are all correctly implemented and asserted. All 38 static bats tests pass against the submitted YAML, and the Phase 7 regression suite (`poc-mount-01-static`, 8 tests) remains green after Phase 8 changes.

The submission has, however, **one BLOCKER** that calls into question the live verification path for CAP-02: the proxy's chosen cert source (`certManager.generateCertificates: true`) is asserted in comments to "work without cert-manager controller installed," but cert-manager `SelfSigned` Issuer/Certificate CRs require the cert-manager controller to reconcile — without a controller they sit indefinitely as not-Ready, which would block the proxy pod from getting its TLS Secret and prevent CAP-02 from passing live.

The phase also carries **6 WARNINGS** centered on (a) two anti-pattern bats lints that match impossible literals against valid YAML and therefore provide no real coverage (test 04: `proxy.enabled: true` and `certManager.generateCertificates: true`), (b) Phase 7 architectural pre-existing assumption about HelmRelease residency that the in-scope HR `spec.kubeConfig` blocks depend on but cannot independently verify, and (c) live-bats grep regexes that admit false-positive `True` matches inside flux message strings.

There are also **4 INFO items** for minor concerns (port-binding test bash-specific dependency, in-scope dependency on `CapsuleConfiguration/default` auto-creation, etc.).

No security findings, no leaked secrets in fixtures, no out-of-scope leak (no `CapsuleConfiguration` CR, no Tenant CR, no hub-Flux multi-tenancy lockdown patches in scope).

## Blocker Issues

### BL-01: Proxy cert-source claim contradicts cert-manager runtime semantics — likely blocks CAP-02 live

**File:** `pocs/capsule/proxy/helmrelease.yaml:68-76`
**Issue:** The chosen cert source is `certManager.generateCertificates: true`, with the inline rationale claiming this "works WITHOUT cert-manager controller installed (chart includes Issuer + Certificate definitions; the SelfSigned Issuer type doesn't require an external CA chain)." This conflates two unrelated cert-manager concepts:

1. **TRUE:** cert-manager's `SelfSigned` `Issuer` does not require an external CA chain (it issues self-signed certs).
2. **FALSE:** `SelfSigned` `Issuer` + `Certificate` CRs do not require the cert-manager *controller* to be installed.

The cert-manager controller is the component that watches `Issuer`/`Certificate` CRs (regardless of issuer type) and issues `Secret` objects containing the keypair. The chart only ships the *manifests* for those CRs — not a controller that reconciles them. With `D-08-04` design ("cert-manager.io CRDs as API surface only, no controller installed") and the proxy chart's `certManager.generateCertificates: true` rendering `Issuer` + `Certificate` CRs, those CRs land on `spoke-capsule` and never get reconciled into a TLS Secret, so the `capsule-proxy` Deployment will indefinitely fail to mount its TLS volume → pod never Running → NodePort never serves → CAP-02 live test (`capsule-install-08-live-proxy-reachable.bats`) cannot pass.

The comment correctly identifies the working override path (`options.generateCertificates: true` + `certManager.generateCertificates: false`) as a fallback "if cert reconcile loop fails on first install (unlikely)" — that fallback is in fact the *expected default* behavior given D-08-04, not the unlikely escape hatch.

**Fix:** Use the chart's built-in self-sign Job instead of the cert-manager-shaped path:

```yaml
    # CAP-02 cert source: built-in self-sign Job (no cert-manager controller required;
    # matches D-08-04 "cert-manager.io CRDs as API surface only — no controller installed").
    options:
      listeningPort: 9001
      enableSSL: true
      generateCertificates: true   # built-in self-sign Job; produces capsule-proxy-tls Secret
      capsuleConfigurationName: default
      additionalSANs:
        - 127.0.0.1
        - localhost
      authPreferredTypes: "BearerToken,TLSCertificate"
    certManager:
      generateCertificates: false   # do NOT render cert-manager.io Issuer/Certificate CRs
```

If `helm template` truly shows the chart can render an in-cluster `SelfSigned` Issuer that gets reconciled WITHOUT a controller (which would contradict cert-manager's documented architecture), then add an explicit `helm template` excerpt to the comment showing how the chart renders a Job (not just CRs) under the `certManager.generateCertificates: true` path. Without that evidence, this configuration is a CAP-02 live-test failure waiting to happen.

## Warnings

### WR-01: Anti-pattern bats test for `proxy.enabled: true` matches an impossible literal — provides no coverage

**File:** `tests/bats/capsule-install-04-static-no-umbrella.bats:15-21`
**Issue:** The test greps for the literal string `proxy.enabled: true` in the operator HelmRelease YAML. This dotted-key form never appears in valid YAML — Helm/Kustomize-rendered values use `proxy:\n  enabled: true` (two lines). The test therefore exits non-zero (no match) regardless of whether the operator HR actually contains the anti-pattern. It is a "test that passes by construction." A reviewer who relies on it as the anti-umbrella sentinel would miss a real regression.

The yq-based positive assertion at `capsule-install-03-static-values.bats:57-62` (`.spec.values.proxy.enabled == false`) provides the actual coverage — but it asserts the *presence* of `false`, not the *absence* of `true`. If a future edit accidentally added a sibling `enabled: true` deeper in the YAML structure, neither test would catch it.

**Fix:** Replace the literal grep with a yq path negative assertion that survives YAML restructuring:

```bash
@test "Anti-umbrella (D-08-01): operator HR has no values.proxy.enabled=true at any depth" {
  [ -f "$OPERATOR_HR" ]
  # Walk all keys named 'proxy' under .spec.values; none may have nested .enabled == true
  run yq eval '[.spec.values.. | select(has("proxy")) | .proxy.enabled // false] | any(. == true)' "$OPERATOR_HR"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}
```

### WR-02: Anti-pattern bats test for `certManager.generateCertificates: true` matches an impossible literal — provides no coverage

**File:** `tests/bats/capsule-install-04-static-no-umbrella.bats:30-34`
**Issue:** Same defect as WR-01 — the test greps for the dotted literal `certManager.generateCertificates: true` against the operator HR. That literal never appears in valid YAML; the operator HR uses `certManager:\n  generateCertificates: false`. The test passes vacuously. The yq-based positive assertion at `capsule-install-03-static-values.bats:22-27` covers the presence of `false` but not the absence of `true`.

**Fix:** Replace with a yq path assertion:

```bash
@test "Anti-pattern: operator HR has values.certManager.generateCertificates explicitly false" {
  [ -f "$OPERATOR_HR" ]
  run yq eval '.spec.values.certManager.generateCertificates == false' "$OPERATOR_HR"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}
```

(This is technically a *positive* presence assertion of `false`, which is functionally equivalent to the *absence* of `true` for the boolean field — and is what the existing test at line 22-27 already does. Test 04's grep variant adds nothing and should be deleted to avoid false signal.)

### WR-03: Live HR `Ready` regex admits false-positive matches inside Flux MESSAGE column

**File:** `tests/bats/capsule-install-06-live-helm.bats:23,36` and `tests/bats/capsule-install-10-live-flux-observable.bats:21`
**Issue:** The regex `<name>[[:space:]]+.*True` matches any line where "True" appears anywhere after the resource name. Flux's `MESSAGE` column legitimately contains arbitrary text, e.g. `Release reconciliation failed: TruncatedError`, where the substring `True` would be matched even though `READY` is `False`. The shape of `flux get` output is:

```
NAME    REVISION  SUSPENDED  READY  MESSAGE
capsule 0.12.4    False      False  ...something containing 'True'...
```

The current regex would falsely report Ready=True on a failed HR, masking real failures.

**Fix:** Anchor on column structure. Either parse with `awk` to inspect the explicit READY column, or use Flux's `-o json` / `-o yaml` and assert via yq:

```bash
@test "CAP-01 live: HelmRelease capsule reports Ready=True (3 attempts × 30s sleep)" {
  local i ready
  for i in 1 2 3; do
    ready=$(kubectl --context=k3d-hub-flux -n capsule-system get helmrelease capsule \
      -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
    [[ "$ready" == "True" ]] && return 0
    [[ $i -lt 3 ]] && sleep 30
  done
  return 1
}
```

This same pattern applies to the proxy HR test (line 36) and the outer Kustomization test in `-10-`.

### WR-04: ADR-004 zero-pods test silently passes on transient kubectl errors

**File:** `tests/bats/capsule-install-09-live-adr-004.bats:16-24`
**Issue:** The test accepts ANY non-zero `kubectl get pods -n flux-system` exit as "namespace doesn't exist → pass" (per the trailing comment). But many *transient* failures also produce non-zero exit (apiserver flap, RBAC propagation lag, network blip, cert renewal in flight). With the current control flow, those failures yield a silent pass — exactly the wrong direction for a domain-boundary invariant intended to catch ADR-004 violations.

**Fix:** Differentiate "NotFound" from other failures. Either inspect stderr for `(NotFound)` or use a dedicated namespace-existence check:

```bash
@test "ADR-004 / domain-boundary-#4: spoke-capsule flux-system ns has zero controllers" {
  # Distinguish "namespace doesn't exist" (PASS) from "transient apiserver error" (FAIL).
  local ns_status
  ns_status=$(kubectl --context=k3d-spoke-capsule get ns flux-system \
    -o jsonpath='{.status.phase}' 2>&1 || true)
  if echo "$ns_status" | grep -qF 'NotFound'; then
    return 0   # ADR-004 invariant: namespace doesn't exist on spoke at all
  fi
  # Namespace exists; assert zero pods
  local pod_count
  pod_count=$(kubectl --context=k3d-spoke-capsule get pods -n flux-system \
    --no-headers 2>/dev/null | wc -l)
  [[ "$pod_count" -eq 0 ]]
}
```

### WR-05: Outer-kustomization `kubeConfig.spoke` semantics unverified within in-scope HR design

**File:** `pocs/capsule/operator/helmrelease.yaml:37-40`, `pocs/capsule/proxy/helmrelease.yaml:39-42`
**Issue:** The in-scope HR objects carry `spec.kubeConfig.secretRef.{name=spoke-capsule-kubeconfig,key=value.yaml}` whose semantics are: when the helm-controller picks up THIS HR, run `helm install` against the spoke cluster (not the cluster the HR lives on). For that semantic to function, the HR object itself must reside on the cluster running helm-controller (i.e., `k3d-hub-flux`).

However, the *outer* Flux Kustomization that synces these manifests (`clusters/hub-flux/pocs/capsule.yaml`, **out of scope for Phase 8 — inherited from Phase 7**) declares `spec.kubeConfig.secretRef.{name=spoke-capsule-kubeconfig,key=value.yaml}`. With that block, `kustomize-controller` impersonates against the spoke cluster and applies the rendered manifests *to the spoke* — meaning the HelmRelease + OCIRepository CRs land on `spoke-capsule`, not on `hub-flux`. With ADR-004 (no helm-controller on spoke, asserted by test `-09-`), no controller will ever pick up the HRs → CAP-01/CAP-02 live tests cannot pass via this code path.

This is **not** a defect in the in-scope Phase 8 files (the HR YAML themselves are correctly shaped). It is a Phase 7 assumption the in-scope HR design depends on but cannot independently verify. The Phase 8 verifier and the live bats `-06-`/`-10-` will surface this as `flux get helmrelease capsule -n capsule-system --context k3d-hub-flux` returning "no resources" — flag for plan-time clarification before live verification begins.

**Fix:** Decide on one of two architectures and apply consistently in the next code change to `clusters/hub-flux/pocs/capsule.yaml` (or document explicitly in `08-VERIFICATION.md` why my reading is wrong):

- **Option A (HR on hub):** Remove `spec.kubeConfig` from `clusters/hub-flux/pocs/capsule.yaml`. HR + OCIRepository CRs land on hub. Hub helm-controller reconciles HR. HR.spec.kubeConfig redirects helm install to spoke. (Standard Flux remote-cluster pattern.)
- **Option B (HR on spoke):** Keep outer Kustomization's spoke kubeConfig, drop HR.spec.kubeConfig (HR was already going to be on spoke). But this requires helm-controller on spoke, which violates ADR-004.

Option A is the only coherent choice given ADR-004. Note that this finding is OUT-OF-SCOPE for the Phase 8 file set but documents a load-bearing dependency that should be re-verified.

### WR-06: Proxy HR comments contradict each other on cert-source rationale

**File:** `pocs/capsule/proxy/helmrelease.yaml:68-76`
**Issue:** The block-comment justifying `certManager.generateCertificates: true` is internally inconsistent:

- Lines 68-71 claim the chart's SelfSigned Issuer "works WITHOUT cert-manager controller installed."
- Lines 72-74 then describe the override path (`options.generateCertificates: true` + `certManager.generateCertificates: false`) as a "fallback if cert reconcile loop fails on first install (unlikely)."

These two statements cannot both be true. Either cert-manager controller is required (in which case the override path is the *primary* config under D-08-04, not the fallback), or the chart somehow renders a controller-less self-sign Job under the `certManager.generateCertificates: true` path (which would make the cert-manager.io API surface a misnomer for what is functionally a built-in Job — and warrants a citation).

This pairs with BL-01. If BL-01 is accepted (use built-in self-sign Job), this comment block is removed in the same fix. If BL-01 is rejected with concrete `helm template` evidence, this comment should be rewritten to clearly explain WHY the chart's SelfSigned path doesn't need a controller — currently it just asserts the conclusion.

**Fix:** Either remove the block (preferred — collapse with BL-01 fix) or rewrite to cite the specific chart template that renders a Job:

```yaml
    # OQ-2: Use chart's built-in self-sign Job (NOT cert-manager.io CRs).
    # D-08-04 invariant: cert-manager.io CRDs are API surface only — no controller installed —
    # so cert-manager.io Issuer/Certificate CRs cannot be reconciled. The chart's
    # `options.generateCertificates: true` path renders a one-shot Job that produces
    # the `capsule-proxy-tls` Secret in capsule-system; that path is controller-less
    # and works under our installed-CRDs-only design. Verified by:
    #   helm template oci://ghcr.io/projectcapsule/charts/capsule-proxy --version 0.12.0 \
    #     --set options.generateCertificates=true --set certManager.generateCertificates=false \
    #     | grep -A 5 'kind: Job'
    options:
      generateCertificates: true
    certManager:
      generateCertificates: false
```

## Info

### IN-01: TCP-binding test (`-08-` second case) depends on bash-specific `/dev/tcp` magic

**File:** `tests/bats/capsule-install-08-live-proxy-reachable.bats:28-31`
**Issue:** `(echo > /dev/tcp/127.0.0.1/30443)` is a bash-only pseudo-device for TCP connect; this test will SILENTLY MISBEHAVE on systems where `/bin/sh` is dash, busybox-sh, or any non-bash. The current test wraps it in `bash -c`, which is correct — but the dependency is implicit and easy to break in a future cleanup pass that drops the wrapper. Consider switching to a portable check (`nc -z 127.0.0.1 30443`, `timeout 5 bash -c '< /dev/tcp/...'`) or adding an inline comment that flags the bash-c dependency:

```bash
@test "CAP-02 live: TCP port 30443 is bound on 127.0.0.1" {
  # Note: /dev/tcp is bash-only; the explicit `bash -c` wrapper is REQUIRED.
  # Do not remove the wrapper or this test will fail on POSIX-sh systems.
  run bash -c "(echo > /dev/tcp/127.0.0.1/30443) 2>/dev/null"
  [ "$status" -eq 0 ]
}
```

### IN-02: Proxy HR depends on `CapsuleConfiguration/default` auto-creation by operator

**File:** `pocs/capsule/proxy/helmrelease.yaml:63`
**Issue:** `options.capsuleConfigurationName: default` references a `CapsuleConfiguration` CR named `default`. The Phase 8 scope explicitly excludes any committed `CapsuleConfiguration` resource (per spec: "NO `CapsuleConfiguration/default` CR"). The current design therefore depends on the Capsule operator chart auto-creating a default `CapsuleConfiguration` during operator startup. This is a load-bearing assumption that — if the chart doesn't auto-create — would silently break the proxy. Behavior is verifiable post-install with `kubectl get capsuleconfigurations -A` against `spoke-capsule`.

**Fix:** Add a verification step to `08-VERIFICATION.md` Wave 1: after CAP-01 reports `Ready=True`, assert that `kubectl --context=k3d-spoke-capsule get capsuleconfiguration default` returns 0 before declaring CAP-01 complete. If the chart does not auto-create the CR, document this as a Phase 9 prerequisite (since CapsuleConfiguration CRs are out-of-scope here per D-08-01 milestone open).

### IN-03: Live HR-Ready test attempt budget (3 × 30s = 90s) may be undersized for first install with image pulls

**File:** `tests/bats/capsule-install-06-live-helm.bats:21,33`, `tests/bats/capsule-install-10-live-flux-observable.bats:19`
**Issue:** First-install reconcile time is dominated by: outer Kustomization detect (5m interval) + OCIRepository pull from ghcr.io (variable, 5-30s under good network) + helm install (15-60s) + chart's webhooks/Issuer/Job spin-up. On a fresh cluster with cold image cache, 90s is tight. The tests will skip-with-output-on-fail, but a fragile timing margin can flake live runs.

**Fix:** Either bump retries to `5 × 30s = 150s` (matches the outer Kustomization 5m interval more comfortably) OR document the timing assumption inline so a future contributor knows when to dial it up:

```bash
# 3 attempts × 30s = 90s. This budget assumes warm image cache on hub-flux's
# helm-controller. On COLD-CACHE first-install, bump to 5 attempts. The budget
# is intentionally short to fail fast on reconcile-loop pathologies (P26).
for i in 1 2 3; do
```

### IN-04: Inner kustomization `namespace: capsule-system` overrides may shadow explicit metadata

**File:** `pocs/capsule/operator/kustomization.yaml:10`, `pocs/capsule/proxy/kustomization.yaml:10`
**Issue:** Both inner kustomizations carry `namespace: capsule-system`. Per the comments, this is "belt-and-suspenders" because the HR + OCIRepository already carry `metadata.namespace: capsule-system` themselves. Kustomize's `namespace:` directive will *unconditionally rewrite* `metadata.namespace` on every resource — which is fine here because the namespaces already match. But this masks a future edit pitfall: if someone deliberately sets a different namespace on one resource (e.g., to put the OCIRepository in `flux-system` for credential sharing), the kustomization's `namespace:` directive would silently overwrite it. Add an inline comment to surface this non-intuitive override, or remove the directive (since both resources already have the right namespace).

**Fix (option A, drop the directive):**
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
# Each resource already carries metadata.namespace: capsule-system in its own file;
# no Kustomize `namespace:` directive needed (and adding one would silently override
# any future per-resource namespace edit).
resources:
  - ocirepository.yaml
  - helmrelease.yaml
```

**Fix (option B, keep with comment):**
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
# WARNING: this `namespace:` directive UNCONDITIONALLY rewrites metadata.namespace on
# every resource below. If any future resource intentionally lives elsewhere (e.g., an
# OCIRepository sharing credentials in flux-system), remove this directive first.
namespace: capsule-system
resources:
  - ocirepository.yaml
  - helmrelease.yaml
```

---

## Notes On Items NOT Flagged

The following candidate concerns were considered and intentionally NOT flagged because they are design choices or outside review scope:

- **Performance / reconcile cadence (`spec.interval: 5m` on HRs, `24h` on OCIRepositories)** — out of scope per `<review_scope>`; the values are reasonable for a POC and match `08-CONTEXT.md` D-08-06.
- **No `serviceAccountName` on OCIRepositories** — public ghcr.io chart hosting; intentionally absent and asserted by test `-02-` cases at lines 56-67. Not a security gap.
- **`spec.releaseName: capsule` and `releaseName: capsule-proxy`** — explicit release names are correct (avoids Flux auto-generated suffixes that would diverge from chart-default Service names and break the SAN list).
- **Single replica (`replicaCount: 1`) on both HRs** — explicit POC simplification per ADR-008; not an availability bug.
- **Webhooks `failurePolicy: Ignore` on operator (12 hooks)** — D-08-03 P26 belt-and-suspenders for first-install bootstrap; intentional.
- **Empty `replicas` field, missing PDB, missing resource limits/requests** — POC scope; not regressions.
- **`flux get sources git flux-system` test (`-10-` case 3) skip-on-old-revision** — defensive carryover gate; will surface as `deferred-to-VAL-05` per Phase 11 plan, not as Phase 8 failure. Correct deferral.
- **No `set -euo pipefail` at top of bats files** — bats has its own assertion-failure semantics and does not require explicit shell strict mode. The `load 'test_helper'` line at the top of every suite is the project convention. Not a defect.

---

_Reviewed: 2026-04-29_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
