---
phase: 04-spoke-registration
verified: 2026-04-28T00:56:03Z
status: passed
score: "12/12 must-haves verified"
overrides_applied: 0
---

# Phase 4: Spoke Registration Verification Report

**Phase Goal:** `kubectl --context k3d-hub-flux -n flux-system get secret spoke-ml-kubeconfig spoke-apps-kubeconfig` returns both Secrets, each with a `value.yaml` key containing a kubeconfig whose `server:` is `https://k3d-<spoke>-server-0:6443`, and the hub's `kustomize-controller` pod can reach each spoke's apiserver with TLS validated and bearer-token auth succeeding.
**Verified:** 2026-04-28T00:56:03Z
**Status:** passed
**Re-verification:** No - initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `scripts/register-spokes-for-flux.sh` creates spoke-side `flux-reconciler` ServiceAccounts, cluster-admin ClusterRoleBindings, and explicit legacy SA-token Secrets. | VERIFIED | Script applies Namespace, ServiceAccount, ClusterRoleBinding, and `kubernetes.io/service-account-token` Secret in one ordered heredoc (`scripts/register-spokes-for-flux.sh:269-304`). Current live state has both kubeconfig Secrets present and both spoke token payloads have no `exp` claim. |
| 2 | Registration is idempotent and still verifies credentials on rerun. | VERIFIED | Runtime skip requires RBAC, hub Secret decode, auth, and route proof (`scripts/register-spokes-for-flux.sh:590-615`); verification still runs after the skip. Recorded review-fix verification ran the script and re-review clean. |
| 3 | Hub has `spoke-ml-kubeconfig` and `spoke-apps-kubeconfig` Secrets with `data.value.yaml`. | VERIFIED | Read-only live probe: both Secrets present; decoded kubeconfigs have `server=https://k3d-spoke-ml-server-0:6443` and `server=https://k3d-spoke-apps-server-0:6443`; token present; CA base64 decodes and matches each spoke `flux-reconciler-token` CA. |
| 4 | Kubeconfig tokens are non-expiring legacy SA-token Secret tokens. | VERIFIED | Script uses explicit `kubernetes.io/service-account-token` Secret with `kubernetes.io/service-account.name: flux-reconciler` (`scripts/register-spokes-for-flux.sh:296-303`). Read-only JWT payload spot-check showed `token_exp=absent` for both spokes. |
| 5 | Hardened in-hub HTTPS probe validates TLS and uses bearer-token auth without sending token in argv. | VERIFIED | `openssl_https_request` sends the HTTP request, including `Authorization: Bearer`, over stdin to `kubectl exec -i`; the remote argv contains only `openssl s_client -quiet -verify_return_error -verify_hostname ... -CAfile ...` (`scripts/register-spokes-for-flux.sh:171-194`). No `--no-check-certificate` remains in the script. |
| 6 | `/readyz` and `/api/v1/nodes` are reached over the same verified TLS path. | VERIFIED | Script calls `openssl_https_request` for `/readyz` and `/api/v1/nodes` (`scripts/register-spokes-for-flux.sh:570-587`). Live Bats has symmetric tests for both endpoints and both spokes (`tests/bats/register-spokes-02-live.bats:364-396`). |
| 7 | Hub-side Flux Kustomizations for both spokes use explicit `spec.kubeConfig.secretRef.name`, `key: value.yaml`, and correct `spec.path`. | VERIFIED | `spoke-ml.yaml` has `path: ./clusters/spoke-ml`, `name: spoke-ml-kubeconfig`, `key: value.yaml` (`clusters/hub-flux/spokes/spoke-ml.yaml:20-28`); `spoke-apps.yaml` mirrors this (`clusters/hub-flux/spokes/spoke-apps.yaml:20-28`). |
| 8 | Hub Flux root mounts the spokes index without breaking bootstrap-managed resources. | VERIFIED | `clusters/hub-flux/flux-system/kustomization.yaml` preserves `# FLUX PATCH SURFACE`, `gotk-components.yaml`, `gotk-sync.yaml`, and adds `# KARYON SPOKES MOUNT` plus `- ../spokes` (`clusters/hub-flux/flux-system/kustomization.yaml:2-20`). `kubectl kustomize clusters/hub-flux` passed. |
| 9 | Spoke seed manifests provide a falsifiable resource unique to each target spoke. | VERIFIED | `clusters/spoke-ml/configmap.yaml` defines `karyon-spoke-id` in `karyon-spoke-ml` with `spoke: spoke-ml`; apps mirrors it with `karyon-spoke-apps` and `spoke: spoke-apps`. |
| 10 | Negative-proof reconciliation landed on spokes, not hub. | VERIFIED | Current live Flux state at `main@sha1:8ce74cc3`: `flux-system`, `spoke-apps`, and `spoke-ml` are Ready=True. Inventories contain `karyon-spoke-ml_karyon-spoke-id__ConfigMap` and `karyon-spoke-apps_karyon-spoke-id__ConfigMap`; read-only falsifier showed both ConfigMaps absent on hub and present on the correct spoke. |
| 11 | Static and live test scaffolds cover the contract and fail closed. | VERIFIED | Static Bats passed 24/24. Full non-destructive regression `bats tests/bats/ --tap` passed 92/92 with live/destructive tests skipped by env gates. Latest destructive evidence: `KARYON_LIVE_TESTS=1 KARYON_LIVE_TESTS_DESTRUCTIVE=1 bats tests/bats/register-spokes-02-live.bats --tap` passed 18 ok, 0 not ok, 0 skipped after push to `main@sha1:8ce74cc3` (`04-REVIEW-FIX.md:61-65`). |
| 12 | Review-fix hardening is present and review is clean. | VERIFIED | `04-REVIEW.md` has `critical: 0`, `warning: 0`, `info: 0`, `status: clean` (`04-REVIEW.md:24-29`). `04-REVIEW-FIX.md` records all three review findings fixed and final post-push live destructive proof. |

**Score:** 12/12 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `scripts/register-spokes-for-flux.sh` | Executable orchestration script for RBAC, hub kubeconfig Secrets, manifest repair, spokes mount, and verification. | VERIFIED | Exists, mode `755`, `bash -n` passed, `shellcheck -e SC1091` passed, static Bats passed. |
| `tests/bats/register-spokes-01-static.bats` | Static contract for script, manifests, docs, Taskfile, token safety, and no auto-push. | VERIFIED | Exists; `bats tests/bats/register-spokes-01-static.bats --tap` passed 24/24. |
| `tests/bats/register-spokes-02-live.bats` | Live/destructive contract for Secrets, decoded kubeconfigs, RBAC, Ready=True, inventory, cross-cluster falsifier, TLS/auth/node probes. | VERIFIED | Exists; non-destructive regression skipped safely without gates; latest gated run passed 18/18 after push to `main@sha1:8ce74cc3`. |
| `clusters/hub-flux/kustomization.yaml` | Hub GitOps root includes `flux-system`. | VERIFIED | Exists and builds via `kubectl kustomize clusters/hub-flux`. |
| `clusters/hub-flux/flux-system/kustomization.yaml` | Preserves Flux bootstrap resources and mounts `../spokes`. | VERIFIED | Contains `gotk-components.yaml`, `gotk-sync.yaml`, `# KARYON SPOKES MOUNT`, and `- ../spokes`; kustomize build passed. |
| `clusters/hub-flux/spokes/kustomization.yaml` | Lists both spoke Kustomization YAMLs. | VERIFIED | Static Bats semantic `yq` check passed. |
| `clusters/hub-flux/spokes/spoke-ml.yaml` | Flux v1 Kustomization for `spoke-ml` with explicit kubeConfig secretRef. | VERIFIED | `spec.path`, `secretRef.name`, and `secretRef.key` are correct. |
| `clusters/hub-flux/spokes/spoke-apps.yaml` | Flux v1 Kustomization for `spoke-apps` with explicit kubeConfig secretRef. | VERIFIED | `spec.path`, `secretRef.name`, and `secretRef.key` are correct. |
| `clusters/spoke-ml/{kustomization,namespace,configmap}.yaml` | Spoke seed tree with unique namespace and falsifier ConfigMap. | VERIFIED | Kustomize build passed; live falsifier confirmed correct target cluster. |
| `clusters/spoke-apps/{kustomization,namespace,configmap}.yaml` | Spoke seed tree with unique namespace and falsifier ConfigMap. | VERIFIED | Kustomize build passed; live falsifier confirmed correct target cluster. |
| `Taskfile.yml` | `register-spokes` task invokes the script. | VERIFIED | Task exists and runs `bash scripts/register-spokes-for-flux.sh` (`Taskfile.yml:24-27`). |
| `docs/flux-hub-spoke.md` | Phase 4 section documents hub-spoke artifacts, P18 reframe, and hardened probes. | VERIFIED | Section documents `value.yaml`, full `spec.kubeConfig`, OpenSSL TLS validation, stdin bearer-token requests, and live Bats proof (`docs/flux-hub-spoke.md:126-188`). |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `Taskfile.yml` | `scripts/register-spokes-for-flux.sh` | `register-spokes` task command | WIRED | `bash scripts/register-spokes-for-flux.sh` at `Taskfile.yml:27`. |
| Script | `scripts/lib/preflight-lib.sh` | `source "${SCRIPT_DIR}/lib/preflight-lib.sh"` | WIRED | Uses shared `section/pass/warn/fail/info` counters (`scripts/register-spokes-for-flux.sh:20-24`). |
| Script | Spoke clusters | `kubectl --context "k3d-${spoke}" apply -f -` multi-doc RBAC heredoc | WIRED | Namespace, SA, CRB, and token Secret applied in order (`scripts/register-spokes-for-flux.sh:269-304`). |
| Script | Hub kubeconfig Secrets | `kubectl create secret generic --from-file=value.yaml=/dev/stdin --dry-run=client -o yaml | kubectl apply -f -` | WIRED | Secret apply path uses stdin file input, not `--from-literal`. |
| Script | Hub-side TLS/auth probe | `kubectl exec -i ... openssl s_client -verify_return_error -verify_hostname ...` | WIRED | Bearer-token HTTP request is piped over stdin; remote argv has no bearer token (`scripts/register-spokes-for-flux.sh:171-194`). |
| `clusters/hub-flux/flux-system/kustomization.yaml` | `clusters/hub-flux/spokes/kustomization.yaml` | `resources: - ../spokes` | WIRED | Kustomize build passed. |
| Spoke Kustomizations | Hub kubeconfig Secrets | `spec.kubeConfig.secretRef.{name,key}` | WIRED | Both spokes use `<spoke>-kubeconfig` and explicit `key: value.yaml`. |
| Spoke Kustomizations | Spoke seed trees | `spec.path: ./clusters/<spoke>` | WIRED | Both paths are present and kustomize builds pass. |
| Live Bats | Current cluster state | `kubectl`, `jq`, `openssl s_client` assertions | WIRED | Tests cover Secret decode, RBAC, Ready=True, inventory, falsifier, TLS, `/readyz`, and `/api/v1/nodes`. |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `scripts/register-spokes-for-flux.sh` | `TOKEN_DECODED`, `CA_B64` | `kubectl --context k3d-${spoke} -n flux-system get secret flux-reconciler-token` | Yes - reads live SA-token Secret data and waits for both token and CA to populate. | FLOWING |
| `scripts/register-spokes-for-flux.sh` | `kubeconfig_yaml` | `build_kubeconfig "${spoke}" "${TOKEN_DECODED}" "${CA_B64}"` | Yes - built from live token/CA and deterministic server URL. | FLOWING |
| Hub Secret `<spoke>-kubeconfig` | `data.value.yaml` | `kubectl create secret generic --from-file=value.yaml=/dev/stdin` | Yes - live read-only decode confirms server, token presence, CA decode, CA equality. | FLOWING |
| Flux Kustomizations | Remote cluster credentials | `spec.kubeConfig.secretRef` to hub Secrets | Yes - current Flux status Ready=True at `main@sha1:8ce74cc3` for both spokes. | FLOWING |
| Spoke seed ConfigMaps | `.data.spoke` | GitOps apply to target spoke path | Yes - live falsifier confirms resources exist on target spokes and not hub. | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Script syntax/static analysis | `bash -n scripts/register-spokes-for-flux.sh && shellcheck -e SC1091 ...` | Passed. | PASS |
| Static Phase 4 contract | `bats tests/bats/register-spokes-01-static.bats --tap` | 24 ok, 0 not ok. | PASS |
| Kustomize builds | `kubectl kustomize clusters/hub-flux`, `clusters/spoke-ml`, `clusters/spoke-apps` | All passed. | PASS |
| Full non-destructive regression | `bats tests/bats/ --tap` | 92 ok, 0 not ok; live/destructive checks skipped without gates. | PASS |
| Read-only live Secret/decode check | Redacted `kubectl`/`yq` probe | Both hub Secrets present; expected server URLs; token present; CA decodes and matches spoke CA. | PASS |
| Read-only live Flux/falsifier check | `flux --context k3d-hub-flux get kustomizations -n flux-system` plus inventory/ConfigMap probes | `flux-system`, `spoke-apps`, `spoke-ml` Ready=True at `main@sha1:8ce74cc3`; inventories and cross-cluster falsifiers pass. | PASS |
| Latest destructive live proof | `KARYON_LIVE_TESTS=1 KARYON_LIVE_TESTS_DESTRUCTIVE=1 bats tests/bats/register-spokes-02-live.bats --tap` | Recorded result after push to `main@sha1:8ce74cc3`: 18 ok, 0 not ok, 0 skipped. Not re-run in this verifier turn because it creates temporary verifier pods when the controller lacks OpenSSL. | PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| SPOKE-01 | 04-01, 04-03, 04-05 | Create ServiceAccount plus cluster-admin ClusterRoleBinding on each spoke. | SATISFIED | Script heredoc creates SA + CRB; live Bats has per-spoke RBAC checks; latest destructive proof passed. |
| SPOKE-02 | 04-01, 04-03, 04-05 | Create explicit legacy SA-token Secret annotated with the SA name. | SATISFIED | Script creates `flux-reconciler-token` with type and annotation; live token data present; token `exp` absent. |
| SPOKE-03 | 04-01, 04-03, 04-05 | Generate kubeconfig with `https://k3d-<spoke>-server-0:6443`. | SATISFIED | Script `expected_server`; live decode confirms both server URLs. |
| SPOKE-04 | 04-01, 04-02, 04-03, 04-04, 04-05 | Store kubeconfig in hub `flux-system/<spoke>-kubeconfig` under `value.yaml`. | SATISFIED | Script applies `--from-file=value.yaml=/dev/stdin`; live read-only probe confirmed `data.value.yaml` for both. |
| SPOKE-05 | 04-01, 04-02, 04-03, 04-04, 04-05 | Author hub-side Flux Kustomization per spoke with secretRef and path. | SATISFIED | Both manifests have explicit `spec.kubeConfig.secretRef` and paths; Flux Ready=True; inventories prove apply. |
| SPOKE-06 | 04-01, 04-03, 04-05 | Embed spoke CA-data so TLS validates against the SAN. | SATISFIED | Script and live Bats use `openssl s_client -verify_return_error -verify_hostname ... -CAfile`; live destructive proof passed. |
| DOCS-03 | 04-04 | Document hub-only reconciliation model and patch-surface rules. | SATISFIED | `docs/flux-hub-spoke.md` contains the Phase 4 operational section and preserves the patch-surface guidance. Note: REQUIREMENTS maps DOCS-03 to Phase 6, but Plan 04-04 claimed and satisfied this supporting doc update. |

No orphaned Phase 4 requirement IDs found in `.planning/REQUIREMENTS.md`: SPOKE-01 through SPOKE-06 are mapped to Phase 4 and accounted for.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| N/A | N/A | No blocker anti-patterns found. False-positive scan hits were `mktemp ... XXXXXX` and a comment mentioning "placeholder". | INFO | No impact. |

### Human Verification Required

None. The live cluster state was checkable programmatically, and the latest destructive live test evidence plus current read-only probes cover the external Flux/Kubernetes integration points.

### Gaps Summary

No blocking gaps found. Phase 4 goal is achieved in the codebase and in current live state. Current checkout is clean at `7108029`; the source/runtime artifacts verified by Flux are at `origin/main` `8ce74cc3`, and the only local commits beyond that are planning/reporting document changes, not runtime code changes.

---

_Verified: 2026-04-28T00:56:03Z_
_Verifier: the agent (gsd-verifier)_
