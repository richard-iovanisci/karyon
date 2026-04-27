---
phase: 4
slug: spoke-registration
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-27
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Source: `04-RESEARCH.md` §Validation Architecture plus `04-REVIEWS.md` review revisions (HIGH-risk phase per ROADMAP — Nyquist sampling combines static/yq checks + in-script gates + post-push live-destructive bats).

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bats-core (system-installed; bats files live under `tests/bats/`) |
| **Config file** | None — `tests/bats/test_helper.bash` is the shared loader (Phase 1/2/3 inheritance) |
| **Quick run command** | `bats tests/bats/register-spokes-01-static.bats --tap` |
| **Full suite command** | `KARYON_LIVE_TESTS=1 KARYON_LIVE_TESTS_DESTRUCTIVE=1 bats tests/bats/register-spokes-*.bats --tap` |
| **Estimated runtime** | ~1s (static) / ~30–60s (live destructive, includes script run + reconciliation wait) |

---

## Sampling Rate

- **After every task commit:** Run `bats tests/bats/register-spokes-01-static.bats --tap` (static greps; <1s; catches filename/sentinel/literal drift; ~80% of regression risk)
- **After every plan wave:** Run the full suite **AND** the in-script D-13 verification (presence + deep decode + CA/TLS proof via openssl + auth roundtrip + node-name negative-proof) by re-running `bash scripts/register-spokes-for-flux.sh` against a fresh `task rebuild`
- **Before `/gsd-verify-work`:** Full suite must be green AND `flux --context k3d-hub-flux get kustomizations -n flux-system` shows both `spoke-ml` and `spoke-apps` `Ready=True`
- **Max feedback latency:** 60 seconds (full live-destructive suite)

---

## Per-Task Verification Map

| Req ID | Behavior | Test Type | Automated Command | File Exists | Status |
|--------|----------|-----------|-------------------|-------------|--------|
| SPOKE-01 | Script creates `flux-reconciler` SA + `flux-reconciler-cluster-admin` CRB on each spoke | static (greps for SA name + CRB name + ClusterRole reference) | `bats tests/bats/register-spokes-01-static.bats -f 'SPOKE-01'` | ❌ Wave 0 | ⬜ pending |
| SPOKE-01 | RBAC actually applied on each spoke cluster | live destructive | `KARYON_LIVE_TESTS=1 KARYON_LIVE_TESTS_DESTRUCTIVE=1 bats tests/bats/register-spokes-02-live.bats -f 'SPOKE-01'` | ❌ Wave 0 | ⬜ pending |
| SPOKE-02 | Token Secret type `kubernetes.io/service-account-token` + annotation `kubernetes.io/service-account.name: flux-reconciler` (singular) | static | `bats tests/bats/register-spokes-01-static.bats -f 'SPOKE-02'` | ❌ Wave 0 | ⬜ pending |
| SPOKE-02 | Token Secret `data.token` + `data.ca.crt` populated on spoke (controller fills <200ms; D-11 retry caps at 10s) | live | included in `register-spokes-02-live.bats` | ❌ Wave 0 | ⬜ pending |
| SPOKE-03 | Server URL literal `https://k3d-<spoke>-server-0:6443` present in script body | static | `bats tests/bats/register-spokes-01-static.bats -f 'SPOKE-03'` | ❌ Wave 0 | ⬜ pending |
| SPOKE-04 | `value.yaml` key literal appears in 4+ places (script Secret apply, hub Kustomization YAML, doc, bats) | static | `bats tests/bats/register-spokes-01-static.bats -f 'SPOKE-04'` | ❌ Wave 0 | ⬜ pending |
| SPOKE-04 | Hub Secret has `data.value.yaml` populated (D-13 step 1: presence) | in-script gate + live | `kubectl --context k3d-hub-flux -n flux-system get secret spoke-ml-kubeconfig -o jsonpath='{.data.value\.yaml}' \| head -c 1` returns non-empty | ❌ Wave 0 | ⬜ pending |
| SPOKE-05 | `clusters/hub-flux/spokes/{spoke-ml,spoke-apps}.yaml` exist with `spec.path`, `spec.kubeConfig.secretRef.name`, `spec.kubeConfig.secretRef.key: value.yaml` (explicit) | static | `bats tests/bats/register-spokes-01-static.bats -f 'SPOKE-05'` (greps for required fields) | ❌ Wave 0 | ⬜ pending |
| SPOKE-05 | Both spoke Kustomizations reach `Ready=True` post-push; `.status.inventory.entries[].id` contains literal `karyon-spoke-ml_karyon-spoke-id__ConfigMap` (and `karyon-spoke-apps_karyon-spoke-id__ConfigMap`) | live destructive (post-push) | `bats tests/bats/register-spokes-02-live.bats -f 'inventory'` | ❌ Wave 0 | ⬜ pending |
| SPOKE-06 | CA-data + bearer token both extracted from spoke's `flux-reconciler-token` Secret (single source of truth), and CA validates the spoke apiserver cert hostname | in-script gate (D-13 step 2 yq parse + openssl CA/TLS proof) + live (openssl proof + auth roundtrip via wget against `/readyz`) | the script's `yq eval` parse + in-pod `openssl s_client -verify_return_error -verify_hostname ... -CAfile ...` + wget probe in `-02-live.bats` | included in `-02-live.bats` | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

**Cross-cutting in-script gates (D-13, all per spoke; not strictly per-REQ but block phase completion):**
- Gate 1: Presence — `kubectl ... get secret <spoke>-kubeconfig -o jsonpath='{.data.value\.yaml}'` non-empty
- Gate 2: Decode — base64-decoded `value.yaml` parses as YAML; `.clusters[0].cluster.server` equals expected URL, `.users[0].user.token` is non-empty, `.clusters[0].cluster.certificate-authority-data` is base64-decodable and equals the spoke `flux-reconciler-token` Secret CA (via `yq eval`)
- Gate 3: CA/TLS proof — in-pod `openssl s_client -verify_return_error -verify_hostname k3d-<spoke>-server-0 -CAfile <decoded CA>` succeeds from the hub `kustomize-controller` pod
- Gate 4: Auth roundtrip — in-pod `wget --no-check-certificate --header="Authorization: Bearer <TOKEN>" https://k3d-<spoke>-server-0:6443/readyz` returns `ok` (D-14 ADJUSTED — image lacks kubectl, busybox-wget used for auth only)
- Gate 5: Node-name negative-proof (P18 trip-wire) — in-pod `wget ... /api/v1/nodes` returns JSON whose `metadata.name` for the single node CONTAINS `k3d-<spoke>-server-0` and DOES NOT contain `k3d-hub-flux-server-0`

---

## Wave 0 Requirements

- [ ] `tests/bats/register-spokes-01-static.bats` — static/yq contract for the script + manifest files. Pins literals and semantic fields: `flux-reconciler` (SA), `flux-reconciler-cluster-admin` (CRB), `flux-reconciler-token` (token Secret), actual YAML `spec.kubeConfig.secretRef.key: value.yaml`, `# KARYON SPOKES MOUNT` (sentinel), `kubernetes.io/service-account.name: flux-reconciler` (singular annotation), `https://k3d-<spoke>-server-0:6443` (server URL pattern), `set -euo pipefail` present, `set -x` absent, no executable `git add`/`git commit`/`git push` in script body, no token/kubeconfig funneling except the single safe stdin Secret pipe.
- [ ] `tests/bats/register-spokes-02-live.bats` — live/destructive contract: `<spoke>-kubeconfig` Secret with `value.yaml` key exists on hub and decodes deeply; in-pod openssl proves CA/TLS for both spokes; in-pod wget probes reach each spoke's apiserver and return `/readyz` + the right node-name; `flux get kustomization <spoke>` `Ready=True` post-push; `.status.inventory.entries[].id` contains literal `karyon-spoke-ml_karyon-spoke-id__ConfigMap` regex AND `karyon-spoke-apps_karyon-spoke-id__ConfigMap`; cross-cluster falsifier asserts `karyon-spoke-id` ConfigMap exists ONLY on the targeted spoke (not on hub, not on the OTHER spoke).
- No new framework install needed — bats-core already present from Phase 1/2/3.
- No new shared fixtures needed — `tests/bats/test_helper.bash` already exposes `require_live`, `require_live_destructive`, `REPO_ROOT`, `SCRIPTS_DIR`.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Post-push reconciliation latency (Flux pulls + applies the new spoke trees) | SPOKE-05 success #5 | Reconciliation runs on Flux's interval (5m default), not on the script's clock. Live-destructive bats waits up to 2min via `kubectl wait --for=condition=Ready` on each spoke Kustomization, but if the user delays the `git push`, the test will skip-with-message rather than fail-loud. | After `git push origin main`: wait 1–2 min OR run `flux --context k3d-hub-flux reconcile kustomization flux-system --with-source` to nudge. Then `flux --context k3d-hub-flux get kustomizations -n flux-system` should show `spoke-ml` + `spoke-apps` both Ready=True. |
| Cross-cluster ConfigMap existence falsification | SPOKE-05 success #5 (negative-proof) | Requires running `kubectl --context k3d-hub-flux -n karyon-spoke-ml get configmap karyon-spoke-id` on hub and asserting the ConfigMap does NOT exist on hub (ROADMAP success #5: P18 silent-misroute would land it on hub). The bats live test automates this, but the manual command is the canonical proof. | `kubectl --context k3d-hub-flux -n karyon-spoke-ml get configmap karyon-spoke-id 2>&1` should return `Error from server (NotFound)` or `error: the server doesn't have a resource type "namespaces"`. Confirm absence on hub. |

---

## Validation Sign-Off

- [ ] All tasks have `<acceptance_criteria>` referencing the bats target OR Wave 0 dependency
- [ ] Sampling continuity: no 3 consecutive plan tasks without an automated verify (static bats + in-script D-13 gates ensure this)
- [ ] Wave 0 covers both bats suites (`-01-static.bats`, `-02-live.bats`)
- [ ] No watch-mode flags (bats runs single-shot)
- [ ] Feedback latency < 60s (full live-destructive suite)
- [ ] `nyquist_compliant: true` set in frontmatter (after planner integrates this strategy into PLAN.md tasks)

**Approval:** pending
