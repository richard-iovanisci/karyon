# Phase 4: Spoke Registration - Research

**Researched:** 2026-04-27
**Domain:** Hub-spoke Flux GitOps reconciliation via `spec.kubeConfig` (Flux 2.8.6 / kustomize-controller v1.8.4 / k8s 1.35 / k3d 5.8.3)
**Confidence:** HIGH (most claims empirically verified live against the project's k3d clusters; remainder cited from official Flux + Kubernetes 2026 docs)

## Summary

Phase 4 lands per-spoke kubeconfig Secrets on `hub-flux/flux-system` so the hub's `kustomize-controller` reconciles into `spoke-ml` and `spoke-apps` via `spec.kubeConfig.secretRef`. CONTEXT.md (16 locked decisions D-01..D-16, 6 SPOKE-01..06 requirements) is unusually thorough; this research focused on **empirically verifying the external API/CLI behavior the locked decisions assume**, against the live three-cluster k3d topology that Phase 2 already created and Phase 3 already bootstrapped.

The vast majority of D-01..D-16 are **verified correct as written**. Two locked decisions need targeted adjustments:

1. **D-14 (in-pod probe via kustomize-controller exec) cannot run as written.** The `ghcr.io/fluxcd/kustomize-controller:v1.8.4` image is distroless-style: it ships `wget` (busybox), `nslookup`, `getent`, `openssl`, `sh`, and `ssh` — but **no `kubectl`, no `curl`, no `yq`, no `jq`, no `python3`, no `bash`**. Phase 4 must replace `kubectl --kubeconfig <piped> ...` invocations with `wget --no-check-certificate --header='Authorization: Bearer <TOKEN>' https://k3d-<spoke>-server-0:6443/<api-path>` from inside the pod, parsing JSON with `grep`/`sed`. Net effect on D-13 verification: still works for auth roundtrip (`/readyz`) and node-name negative-proof (`/api/v1/nodes`), with the loss that **busybox-wget cannot validate the kubeconfig's CA-data field** (no `--ca-certificate` flag). This is acceptable — the bearer token is what authenticates, and the apiserver returns the node name of *whichever cluster the token actually belongs to*, so the P18 trip-wire still trips on a misrouted Secret.

2. **The P18 silent-misroute threat model in CONTEXT.md is partially folkloric.** Live tests against Flux 2.8.6 / kustomize-controller v1.8.4 show that **a wrong/missing `secretRef.key` produces `Ready=False`**, NOT a silent misroute (verified empirically — "KubeConfig secret '...' does not contain a 'value.yaml' key with a kubeconfig"). The REAL P18 fault mode is **`spec.kubeConfig` block omitted entirely** (the Kustomization reconciles via the controller's in-cluster SA, lands on the hub, reports `Ready=True`). Phase 4's defenses (explicit `key: value.yaml` + ALWAYS include `spec.kubeConfig.secretRef.{name,key}` + node-name probe) are still the right posture — but the rationale should be updated: "always include `spec.kubeConfig`" is the primary guard; "explicit key" is belt-and-suspenders against future Flux behavior changes and developer mistakes.

Three smaller findings: (a) `spec.kubeConfig.secretRef.key` default IS BOTH `value` AND `value.yaml` per current Flux docs, verified live (Flux probes both keys when `key:` is unset); (b) `.status.inventory.entries[].id` format is `<namespace>_<name>_<group>_<kind>` (NOT UID-suffixed as CONTEXT.md guesses); (c) k3s legacy SA-token Secret data populates in <200ms on idle clusters — the 10×1s = 10s cap in D-11 is very comfortable.

**Primary recommendation:** Honor D-01..D-13, D-15, D-16 verbatim. Adjust D-14 to use `wget`-based in-pod probes (kustomize-controller image lacks kubectl). Frame P18 in the docs as "spec.kubeConfig accidentally omitted" rather than "Secret-key typo silently misroutes" — the wrong-key case is loud, the missing-block case is silent.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Script Orchestration & Wire-up:**

- **D-01:** **Helper function `register_spoke <name>`**, called twice (`register_spoke spoke-ml`, `register_spoke spoke-apps`). Mirrors Phase 2 `create_cluster()` pattern.
- **D-02:** **Wire-up via Phase 3 D-13 patch surface + spokes/kustomization.yaml directory reference.** Sentinel-guarded patch to `clusters/hub-flux/flux-system/kustomization.yaml` adds `- ../spokes` to `resources:`. Seed `clusters/hub-flux/spokes/kustomization.yaml` lists `- spoke-ml.yaml` + `- spoke-apps.yaml`. Single top-level Flux Kustomization (`flux-system`) keeps reconciling everything.
- **D-03:** **Per-spoke `Namespace` + `ConfigMap` seed** under `clusters/spoke-ml/` and `clusters/spoke-apps/`. Each tree contains `kustomization.yaml` referencing `namespace.yaml` (creates `karyon-spoke-ml` / `karyon-spoke-apps`) + `configmap.yaml` (creates `karyon-spoke-id` in that ns with `data.spoke=spoke-ml` / `spoke-apps`).
- **D-04:** **Write-local-only; no git mutations from the script.** Script writes `clusters/hub-flux/spokes/*.yaml`, `clusters/hub-flux/spokes/kustomization.yaml`, `clusters/spoke-ml/**`, `clusters/spoke-apps/**`, and the patch to `clusters/hub-flux/flux-system/kustomization.yaml`. Then `info`s the user with the exact `git add ... && git commit -m '...' && git push` line. Kubeconfig Secrets on the hub are applied imperatively via `kubectl apply -f -` (NOT committed).

**Spoke RBAC Layout:**

- **D-05:** **Spoke-side namespace = `flux-system`** for the SA + token Secret. Mirrors hub layout.
- **D-06:** **`flux-reconciler` ServiceAccount** on each spoke.
- **D-07:** **`flux-reconciler-token` Secret** of type `kubernetes.io/service-account-token`, annotated `kubernetes.io/service-account.name: flux-reconciler`. Indefinite-lifetime token.
- **D-08:** **`flux-reconciler-cluster-admin` ClusterRoleBinding** binding the SA to the built-in `cluster-admin` ClusterRole.

**Kubeconfig Generation:**

- **D-09:** **Kubeconfig assembled via heredoc with bash substitution.** ~25-line YAML, single `cat <<EOF` block substituting `$CA_DATA`, `$TOKEN`, `$SERVER`.
- **D-10:** **CA-data AND bearer token both extracted from the spoke's `flux-reconciler-token` Secret.** `kubectl --context k3d-<spoke> -n flux-system get secret flux-reconciler-token -o jsonpath='{.data.ca\.crt}'` for CA, `'{.data.token}'` for token.
- **D-11:** **Bounded retry loop for Secret data population** (10 attempts × 1s = 10s cap). Same pattern for `ca.crt`. Single-shot rejected (will race the controller in fresh-cluster scenarios).
- **D-12:** **Trust the literal `https://k3d-<spoke>-server-0:6443`.** ROADMAP REQ-SPOKE-03 locks the URL. No DNS or TLS pre-probe before assembly.

**Verification (HIGH-risk P18 mitigation):**

- **D-13:** **Belt-and-suspenders in-script verification.** Before `exit 0` the script asserts, per spoke: (1) Presence of `<spoke>-kubeconfig` Secret with `value.yaml` key. (2) Decode + parse the kubeconfig YAML. (3) Auth roundtrip. (4) Node-name negative-proof.
- **D-14:** **In-pod probes exec into `kustomize-controller`** in `flux-system` on `k3d-hub-flux`. *(See research §Adjustment Needed — image ships no kubectl; replace `kubectl auth can-i` / `kubectl get nodes` invocations with `wget`-based equivalents.)*
- **D-15:** **Negative-proof done at the credential layer (node-name check), NOT at `.status.inventory`.** Block-on-push rejected. Imperative apply of seed manifests rejected.
- **D-16:** **Canonical `.status.inventory` negative-proof lives in `tests/bats/register-spokes-02-live.bats`**, gated by `require_live_destructive()` per Phase 2/3 pattern.

### Claude's Discretion

These were not explicitly discussed; planner/researcher decides:

- **Order of operations within `register_spoke` helper** — recommended: (1) RBAC: SA + CRB + token Secret on spoke; (2) wait for Secret data; (3) extract CA + token; (4) build kubeconfig; (5) imperative `kubectl apply -f -` of `<spoke>-kubeconfig` Secret on hub; (6) write `clusters/hub-flux/spokes/<spoke>.yaml` Kustomization YAML to local checkout; (7) write `clusters/<spoke>/` seed tree; (8) verify (D-13/D-14).
- **Where the patch to `clusters/hub-flux/flux-system/kustomization.yaml` happens** — once across both spokes (idempotent, sentinel-guarded `# KARYON SPOKES MOUNT` or similar) outside the per-spoke helper.
- **Sentinel for the kustomization.yaml patch** — pick a literal that's grep-friendly and unique (e.g., `# KARYON SPOKES MOUNT`).
- **Idempotency check granularity for the `<spoke>-kubeconfig` Secret on the hub** — three-part AND like Phase 3 D-07: (a) Secret exists, (b) `data.value\.yaml` decodes to a valid kubeconfig with the expected `server:` and (c) auth roundtrip succeeds. On any failing, fall through to full re-creation.
- **Token-Secret data-population wait timeout exact value** — D-11 recommends 10s; researcher confirms typical k3s SA-token-controller latency.
- **`kubectl apply -f -` vs `kubectl create secret generic --dry-run=client -o yaml | kubectl apply -f -`** for the hub Secret — both work; pick whichever has clearer error messages on conflict.
- **In-pod kubectl invocation mechanics** — `kubectl exec deploy/kustomize-controller -n flux-system -- sh -c '<cmd>'` vs `kubectl exec ... -- kubectl ...`. The kustomize-controller image SHOULD ship kubectl in 2026 (researcher confirms); if not, fall back to a one-shot `busybox`-style debug pod (deviates from D-14 — flag if research surfaces this).
- **CA / token export mechanics inside the in-pod probe** — kubeconfig is piped in via stdin (`<<EOF`), or written to `/tmp/kubeconfig` inside the pod, or mounted as a Secret volume. Stdin is least invasive.
- **`docs/flux-hub-spoke.md` Phase 4 section depth** — medium depth: REQ-IDs + value.yaml contract + P18 callout + node-name negative-proof rationale.
- **Diff/conflict handling on the `clusters/hub-flux/flux-system/kustomization.yaml` patch** — if a re-bootstrap rewrites the file, the script should re-apply the patch idempotently (`grep -qF "# KARYON SPOKES MOUNT"` → skip; else `sed`/`yq` insert).
- **What to do if `clusters/<spoke>/` already has Phase-5 content during Phase 4 rerun** — D-03's seed manifests are additive; if a future rerun finds existing files at `clusters/spoke-ml/namespace.yaml`, the script should `info "already done, skipping: clusters/spoke-ml seed (file exists)"`. Idempotent-by-presence; don't overwrite.

### Deferred Ideas (OUT OF SCOPE)

- **Token rotation / Secret renewal** — explicitly rejected for v1; legacy SA-token Secrets have indefinite lifetime per PROJECT.md Phase-4 key decision. Revisit in v2 (SECRETS-01).
- **Namespace-scoped RBAC narrowing** — REQ-SPOKE-01 locks cluster-admin for v1.
- **Per-namespace Flux Kustomizations on spokes (one Kustomization per app, not per spoke)** — Phase 4 lands one Flux Kustomization per spoke; Phase 5 may split podinfo / gpu-smoke-test into their own Kustomizations.
- **TokenRequest (`kubectl create token`)** — PROJECT.md Phase-4 key decision rejects in favor of legacy Secret-backed indefinite-lifetime tokens.
- **CDI (Container Device Interface) for the spoke kubeconfig** — orthogonal; CDI is for device pass-through (Phase 2 owns).
- **Auto-commit + auto-push from the script** — rejected (Phase 4 D-04). Mirrors Phase 3 bootstrap-flux's posture.
- **Imperative-apply of the hub-side spoke Kustomization YAMLs** — rejected. Defeats GitOps.
- **Splitting Phase 4 into "register-spokes" and "verify-spokes" two-step scripts** — rejected.
- **In-script `.status.inventory` polling with timeout** — rejected.
- **Spawn a fresh debug pod for the in-pod probe** — rejected (D-14). kustomize-controller is the authoritative identity. *(Note: research §Adjustment Needed elaborates — D-14 still picks kustomize-controller exec, just uses wget instead of kubectl since the image lacks kubectl.)*
- **`kubectl wait --for=jsonpath` for the SA-Secret data-population wait** — rejected (D-11). Bounded retry has clearer failure surface.
- **`openssl s_client` for CA extraction** — rejected (D-10). Pulls SERVING leaf cert, not CA.
- **`kubectl config view --raw --minify --flatten` for CA extraction** — rejected (D-10).
- **`yq`-based template for kubeconfig assembly** — rejected (D-09). Heredoc with bash substitution is sufficient.
- **DNS/TLS pre-probe before kubeconfig assembly** — rejected (D-12).
- **Source-controller pod for in-pod probes** — rejected (D-14). Wrong layer.
- **Loop-over-array (`for spoke in spoke-ml spoke-apps`) in the script body** — rejected (D-01).
- **Inline duplication for both spokes** — rejected (D-01).
- **Separate top-level "spokes" Flux Kustomization on the hub** — rejected (D-02).
- **Inline-flat resources in flux-system/kustomization.yaml** — rejected (D-02).
- **Empty `kustomization.yaml` (zero resources) under clusters/<spoke>/** — rejected (D-03).
- **Reference Phase 5 paths (`./apps`, `./infrastructure`) from Phase 4 seed** — rejected (D-03).
- **Phase 4 doc deliverable as a separate `docs/spoke-registration.md`** — folded into existing `docs/flux-hub-spoke.md`.
- **gitleaks pre-commit hook install in Phase 4** — Phase 6 owns it (REPO-04).
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| **SPOKE-01** | `scripts/register-spokes-for-flux.sh` creates a `ServiceAccount` plus cluster-admin `ClusterRoleBinding` on each spoke | Verified live: applying the SA + cluster-admin CRB on `k3d-spoke-ml` worked in <1s. The SA name `flux-reconciler` and CRB name `flux-reconciler-cluster-admin` are project conventions per D-06/D-08; no upstream constraint blocks them. |
| **SPOKE-02** | For each spoke SA, creates an explicit legacy Secret of type `kubernetes.io/service-account-token` annotated with the SA name (indefinite lifetime is acceptable for lab scope) | Verified live + cited from k8s docs: the annotation key is `kubernetes.io/service-account.name` (singular). The token controller populates `data.token` and `data.ca.crt` in <200ms on an idle k3s cluster when the annotated SA exists. **Failure mode (verified live):** if the annotated SA does NOT exist when the Secret is created, **the Secret may be auto-deleted by the controller** (got `Error from server (NotFound)` when probing 3s after creating an orphan Secret). This means the registration script MUST apply the SA *before* the Secret. The decisions correctly imply this ordering; Phase 4 plan should make it explicit. |
| **SPOKE-03** | Generates a kubeconfig per spoke with `server: https://k3d-<spoke>-server-0:6443` (Docker-embedded-DNS hostname reachable from hub pods on `k8s-net`) | Verified live: from inside `kustomize-controller` on `k3d-hub-flux`, `nslookup k3d-spoke-ml-server-0` resolves and `wget -qO- --no-check-certificate https://k3d-spoke-ml-server-0:6443/healthz` returns `401 Unauthorized` (the apiserver is reachable; the anonymous request is correctly rejected). DNS resolution and TCP/TLS reachability across `k8s-net` are confirmed. |
| **SPOKE-04** | Stores each kubeconfig as a `flux-system/<spoke>-kubeconfig` Secret on `hub-flux` under the key `value.yaml` (confirmed correct key name per Flux `kustomize-controller` v1 spec) | Verified live + cited from Flux docs: `spec.kubeConfig.secretRef.key` defaults to **EITHER `value` OR `value.yaml`** (Flux probes both when `key:` is unset). Setting `key: value.yaml` explicitly is the right call — it makes the contract unambiguous and is a defense-in-depth posture against future Flux changes. The hub Secret applied via `kubectl create secret generic <spoke>-kubeconfig --from-file=value.yaml=/dev/stdin --dry-run=client -o yaml \| kubectl apply -f -` produces `data.value.yaml` correctly (verified). |
| **SPOKE-05** | Authors a hub-side Flux `Kustomization` per spoke under `clusters/hub-flux/spokes/` with `spec.kubeConfig.secretRef` pointing to the kubeconfig Secret and `spec.path` pointing to the spoke's tree | Verified live: the `kustomize.toolkit.fluxcd.io/v1` CRD has `spec.kubeConfig.secretRef.{name (required), key}` and the controller resolves the secretRef in **the same namespace as the Kustomization** (per Flux docs + verified). Phase 4 places both Kustomizations in `flux-system` on hub, so the Secrets must also be in `flux-system` on hub. |
| **SPOKE-06** | Each spoke kubeconfig embeds CA-data from the spoke's apiserver cert so TLS validation succeeds against the `--tls-san` | Verified live: SAN coverage on each apiserver cert (Phase 2 D-13 inheritance) — `k3d-hub-flux-server-0`, `k3d-spoke-ml-server-0`, `k3d-spoke-apps-server-0` are all present in the respective certs' DNS SAN list. The CA-data extracted from `data.ca.crt` of the SA-token Secret IS the cluster's signing CA (the same CA that signed the apiserver leaf cert), so TLS validates from the controller's REST client. |
</phase_requirements>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Per-spoke RBAC (SA + CRB + token Secret) | Each spoke's API server (`k3d-spoke-ml`, `k3d-spoke-apps`) | — | Lives where the identity is consumed; spoke is the auth boundary |
| Hub-side `<spoke>-kubeconfig` Secret | Hub API server (`k3d-hub-flux`), `flux-system` namespace | — | Flux's secretRef is resolved in the Kustomization's namespace per upstream Flux docs |
| Hub-side Flux `Kustomization` per spoke | Hub API server (`k3d-hub-flux`), `flux-system` namespace | — | Reconciliation engine (kustomize-controller) lives on hub; per ADR-004 hub-only topology |
| Spoke seed manifests (`clusters/spoke-ml/`, `clusters/spoke-apps/`) | Git repository (`origin/main`) | Spoke API server (eventual reconciliation target) | GitOps source of truth; Phase 5 adds workloads alongside |
| Kustomization wire-up patch | `clusters/hub-flux/flux-system/kustomization.yaml` (committed Git artifact, sentinel-guarded) | Flux's reconciliation loop (consumes the patched tree) | Phase 3 D-13 patch surface; survives re-bootstrap |
| In-script verification probe (D-13/D-14) | `kustomize-controller` pod on hub | — | Pod identity is authoritative; failures here mirror real reconciliation failures |
| Reconciliation negative-proof (`.status.inventory`) | Hub API server | Spoke API server (resources actually applied there) | Inventory is on hub; the resources it lists land on spokes — the cross-cluster mismatch is the negative-proof |

**Key insight:** Phase 4 spans **three tier boundaries** in a single script run: (a) SA/CRB/Secret writes on each spoke's apiserver, (b) Secret + Kustomization writes on hub's apiserver, and (c) local file writes in the Git checkout. The script's own RBAC (the user's local kubeconfig) must hold cluster-admin on all three apiservers — guaranteed by k3d's default kubeconfig export. No cross-spoke writes happen on hub or vice versa; each apiserver is touched only via its own context.

## Standard Stack

### Core (already pinned in `.tool-versions`)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `kubectl` | 1.35.0 | Apply RBAC on spokes; apply Secret on hub; jsonpath-extract CA/token | Pinned; standard k8s CLI |
| `flux2` | 2.8.6 | (Used only for `flux check` on hub; spoke-side ops are pure kubectl) | Pinned; Phase 3 dependency |
| `k3d` | 5.8.3 | (Used only for `k3d cluster list` precondition checks if needed) | Pinned; Phase 2 dependency |
| `jq` | 1.8.1 | Parse `flux get kustomization ... -o json` `.status.inventory` in bats | Pinned; live test parsing |
| `yq` | 4.53.2 (mikefarah Go yq) | Parse decoded kubeconfig YAML in D-13 step 2 (`yq eval '.clusters[0].cluster.server'`) | Pinned; verified live: `echo "$b64" \| base64 -d \| yq eval '.clusters[0].cluster.server' -` works cleanly |
| `openssl` | OpenSSL 3.0.13 (system) | Already used by Phase 2 SAN verification; not strictly needed in Phase 4 (D-12 trusts the literal) | System binary |

**No new dependencies.** Phase 4 is purely additive code over the Phase 1–3 toolchain.

**Version verification (run 2026-04-27):**

```text
$ kubectl version --client --output=yaml | grep gitVersion
  gitVersion: v1.35.0
$ flux --version
flux version 2.8.6
$ k3d version
k3d version v5.8.3
k3s version v1.31.5-k3s1 (default)
$ jq --version
jq-1.8.1
$ yq --version
yq (https://github.com/mikefarah/yq/) version v4.53.2
```

All match `.tool-versions` pins; preflight (PRE-05) enforces this gate.

### In-Pod Probe Tooling (D-14 adjustment)

**The kustomize-controller image (`ghcr.io/fluxcd/kustomize-controller:v1.8.4`) ships ONLY:**

```text
sh, ssh, ssh-add, ssh-agent, ssh-copy-id, ssh-keygen, ssh-keyscan,
ssh-pkcs11-helper, openssl, c_rehash, findssl.sh, sha1sum, sha256sum,
sha3sum, sha512sum, showkey, shred, shuf, unshare, wget, nslookup,
getent, git-shell
```

**It does NOT ship:** `kubectl`, `curl`, `yq`, `jq`, `python3`, `bash`, `cat` (it has busybox `cat` though), or any other Kubernetes-aware tooling.

The pod has `/etc/resolv.conf` pointing at the cluster's CoreDNS (`10.43.0.10`), and the search path includes `cluster.local`. Importantly, `nslookup k3d-spoke-ml-server-0` from inside the pod **resolves successfully** because Docker's user-defined network DNS is reachable through the cluster's iptables — verified live: a `wget --no-check-certificate https://k3d-spoke-ml-server-0:6443/healthz` from inside the pod returns `401 Unauthorized` (TCP+TLS work; auth correctly rejects anonymous).

**Recommendation:** Replace `kubectl auth can-i` and `kubectl get nodes` invocations in D-14 with `wget`-based equivalents:

```bash
# Auth roundtrip — proves token authenticates on the targeted apiserver
wget -qO- --no-check-certificate \
  --header="Authorization: Bearer $TOKEN" \
  "https://k3d-${spoke}-server-0:6443/readyz"
# Returns "ok" if 200 + token authorized; non-zero exit + error message otherwise.

# Node-name negative-proof — proves the kubeconfig points at the RIGHT cluster
wget -qO- --no-check-certificate \
  --header="Authorization: Bearer $TOKEN" \
  "https://k3d-${spoke}-server-0:6443/api/v1/nodes" \
  | grep -oE '"name":[[:space:]]*"k3d-[^"]+-server-0"'
# Asserts the literal "k3d-${spoke}-server-0" appears AND "k3d-hub-flux-server-0" does NOT.
```

**Trade-off vs. kubectl-based probe:** busybox `wget` does not support `--ca-certificate`, so this approach **does not validate the kubeconfig's `certificate-authority-data` field**. The bearer token authenticates against whatever apiserver the request reaches; the apiserver returns its own node name. So the probe still catches:
- Wrong server URL → wrong cluster → wrong node name (P18 misroute caught)
- Wrong token → 401/403 (auth caught)
- Server unreachable → wget fails (DNS/network caught)

It does NOT catch a corrupted CA-data field. Acceptable risk: D-10 extracts CA-data from the same Secret as the token — they're populated by the same controller in the same atomic operation, so if the token is valid, the CA is also valid. The script trusts D-10's "single source of truth" property.

**Alternative considered (rejected):** spawn an ephemeral `bitnami/kubectl:latest` pod on hub for the probe. Tested live; requires Docker Hub access during script runs and adds 5–10s latency for image pull on a cold cache. The wget approach is cleaner; the trade-off (no CA validation) is mitigated by D-10's single-source extraction.

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Heredoc kubeconfig assembly (D-09) | `kubectl config set-cluster/credentials/context` against a temp KUBECONFIG | More moving parts, verbose; rejected per D-09 |
| Bounded retry loop (D-11) | `kubectl wait --for=jsonpath='{.data.token}' secret/<name> --timeout=10s` | Verified live: works in 195ms when SA exists. Cleaner one-liner. Rejected per D-11 due to "opaque failure surface" — a timeout doesn't tell you WHY (controller down? SA missing? RBAC?). The bounded-retry loop's `fail` message can include `kubectl describe secret/...` remediation. |
| Hub Secret apply via `--from-file=value.yaml=/dev/stdin --dry-run=client -o yaml \| kubectl apply -f -` | Heredoc Secret YAML with pre-base64-encoded `data.value.yaml: <b64>` | Both work. The `--from-file` form is simpler (kubectl handles base64); the heredoc form is more explicit. Either is acceptable per CONTEXT.md Claude's Discretion. **Recommendation:** `--from-file=value.yaml=/dev/stdin` — verified live, idempotent on `kubectl apply` (creates → configures → no-op). |
| In-pod probe via `kubectl exec ... -- kubectl ...` (D-14 as written) | `kubectl exec ... -- /bin/sh -c 'wget ...'` (D-14 adjustment) | The kustomize-controller image lacks kubectl. Adjustment is required. |
| In-pod probe via `kubectl debug --target=manager --image=bitnami/kubectl:latest` | Ephemeral container with kubectl | Tested live; works but requires Docker Hub access on cold cache + adds 5–10s. Wget approach is cleaner. |

## Architecture Patterns

### System Architecture Diagram

```text
                                      ┌─────────────────────────────────────────────────────────┐
                                      │ Git repository (origin/main)                            │
                                      │                                                          │
                                      │   clusters/hub-flux/flux-system/kustomization.yaml      │
                                      │     [resources: + ../spokes]                            │
                                      │   clusters/hub-flux/spokes/kustomization.yaml           │
                                      │     [resources: spoke-ml.yaml, spoke-apps.yaml]         │
                                      │   clusters/hub-flux/spokes/spoke-ml.yaml                │
                                      │     [Flux Kustomization w/ spec.kubeConfig]             │
                                      │   clusters/hub-flux/spokes/spoke-apps.yaml              │
                                      │     [Flux Kustomization w/ spec.kubeConfig]             │
                                      │   clusters/spoke-ml/kustomization.yaml                  │
                                      │     [namespace.yaml + configmap.yaml]                   │
                                      │   clusters/spoke-apps/kustomization.yaml                │
                                      │     [namespace.yaml + configmap.yaml]                   │
                                      └─────────────────────────────────────────────────────────┘
                                                            │ git pull (every 1m by Flux GitRepository source)
                                                            ▼
┌────────────────────────────────────────────────────────────────────────────────────────────────┐
│ k3d-hub-flux (apiserver :6443, network k8s-net)                                                │
│                                                                                                │
│  flux-system namespace:                                                                        │
│    ├─ source-controller    ────► fetches Git, exposes artifacts                                │
│    ├─ kustomize-controller ────► reconciles Kustomization CRDs                                 │
│    │   │  ┌──────────────────────────────────────────────────────┐                             │
│    │   │  │ Per Kustomization spoke-ml.yaml (in flux-system ns): │                             │
│    │   │  │   spec.kubeConfig.secretRef: spoke-ml-kubeconfig     │                             │
│    │   │  │     key: value.yaml                                  │                             │
│    │   │  │   spec.path: ./clusters/spoke-ml                     │                             │
│    │   │  │   ►   reads Secret 'spoke-ml-kubeconfig' from flux-  │                             │
│    │   │  │       system; uses it to build a remote REST client  │                             │
│    │   │  └──────────────────────────────────────────────────────┘                             │
│    │   ▼                                                                                       │
│    │  Secret spoke-ml-kubeconfig (Opaque, key=value.yaml)                                      │
│    │    │                                                                                      │
│    │    ▼ contains kubeconfig pointing at https://k3d-spoke-ml-server-0:6443                   │
│    │      with CA from spoke-ml & bearer token from spoke-ml's flux-reconciler-token Secret    │
│    │                                                                                           │
│    └────────────────────────────────────────────► kustomize-controller authenticates          │
│                                                   to spoke-ml as flux-reconciler              │
│                                                   (cluster-admin on spoke-ml)                  │
└────────────────────────────────────────────────────────────────────────────────────────────────┘
                            │  apply ConfigMap karyon-spoke-id in karyon-spoke-ml ns
                            ▼  (via spec.kubeConfig path)
┌────────────────────────────────────────────────────────────────────────────────────────────────┐
│ k3d-spoke-ml (apiserver :6444, network k8s-net)                                                │
│                                                                                                │
│  flux-system namespace:                                                                        │
│    ├─ flux-reconciler ServiceAccount (no Flux controllers — hub-only topology)                 │
│    ├─ flux-reconciler-token Secret (legacy SA-token, indefinite-lifetime)                      │
│    └─ flux-reconciler-cluster-admin ClusterRoleBinding → cluster-admin                         │
│                                                                                                │
│  karyon-spoke-ml namespace (created by Phase 4 seed):                                          │
│    └─ ConfigMap karyon-spoke-id { spoke: spoke-ml }   ◄── reconciled in by hub kustomize-ctrl │
│                                                                                                │
│  (Phase 5 will add ./apps/, ./infrastructure/ trees alongside)                                 │
└────────────────────────────────────────────────────────────────────────────────────────────────┘

Same shape for k3d-spoke-apps (apiserver :6445), with karyon-spoke-apps namespace.
```

### Recommended Project Structure (post-Phase-4)

```text
scripts/
  ├── register-spokes-for-flux.sh        # Phase 4 main script
  └── lib/preflight-lib.sh                # already exists (sourced)

clusters/
  ├── hub-flux/
  │   ├── flux-system/
  │   │   ├── gotk-components.yaml        # bootstrap-managed
  │   │   ├── gotk-sync.yaml              # bootstrap-managed
  │   │   └── kustomization.yaml          # PATCH SURFACE (Phase 3 D-13)
  │   │                                   # Phase 4 adds `- ../spokes` under resources:
  │   │                                   # sentinel: # KARYON SPOKES MOUNT
  │   └── spokes/                         # NEW (Phase 4)
  │       ├── kustomization.yaml          # resources: spoke-ml.yaml, spoke-apps.yaml
  │       ├── spoke-ml.yaml               # Flux Kustomization w/ spec.kubeConfig
  │       └── spoke-apps.yaml             # Flux Kustomization w/ spec.kubeConfig
  ├── spoke-ml/                           # NEW (Phase 4 seed; Phase 5 extends)
  │   ├── kustomization.yaml              # resources: namespace.yaml, configmap.yaml
  │   ├── namespace.yaml                  # Namespace karyon-spoke-ml
  │   └── configmap.yaml                  # ConfigMap karyon-spoke-id { spoke: spoke-ml }
  └── spoke-apps/                         # NEW (Phase 4 seed; Phase 5 extends)
      ├── kustomization.yaml              # resources: namespace.yaml, configmap.yaml
      ├── namespace.yaml                  # Namespace karyon-spoke-apps
      └── configmap.yaml                  # ConfigMap karyon-spoke-id { spoke: spoke-apps }

tests/bats/
  ├── register-spokes-01-static.bats       # NEW (static greps, no live state)
  └── register-spokes-02-live.bats         # NEW (require_live_destructive)

docs/flux-hub-spoke.md                     # extended (Phase 4 stub filled in)

Taskfile.yml                               # extended (register-spokes task appended)
```

**On-cluster state (NOT in git):**
- On each spoke: SA + CRB + token Secret in `flux-system`.
- On hub: `spoke-ml-kubeconfig`, `spoke-apps-kubeconfig` Secrets in `flux-system` (applied imperatively by the script — bearer tokens, never committed).

### Pattern 1: Idempotent Imperative Apply with Sentinel Guard

Phase 3 D-13 established the pattern: a sentinel comment line marks the script's edit; the script greps for the sentinel and skips if already present.

**Source:** Phase 3 `scripts/bootstrap-flux.sh` Section 5.

```bash
# Sentinel for Phase 4: # KARYON SPOKES MOUNT
KUST_FILE="${REPO_ROOT}/clusters/hub-flux/flux-system/kustomization.yaml"
if grep -qF "# KARYON SPOKES MOUNT" "$KUST_FILE"; then
  info "already done, skipping: spokes mount sentinel present"
else
  # Insert `  - ../spokes` under `resources:` block, with the sentinel comment above it.
  # Use awk or yq; awk is simpler and sentinel-grep is the source of truth.
  tmp="$(mktemp)"
  awk '
    /^resources:/ {print; in_resources=1; next}
    in_resources && /^[^ -]/ {
      # First non-resource line — emit our addition before it
      print "# KARYON SPOKES MOUNT"
      print "- ../spokes"
      in_resources=0
    }
    {print}
    END {
      if (in_resources) {
        print "# KARYON SPOKES MOUNT"
        print "- ../spokes"
      }
    }
  ' "$KUST_FILE" > "$tmp"
  mv "$tmp" "$KUST_FILE"
  pass "applied: spokes mount in $KUST_FILE"
fi
```

**Note:** `yq -i 'with(.resources; . += ["../spokes"])' "$KUST_FILE"` is also viable but doesn't carry the sentinel comment (which the bats static test pins). The awk approach preserves the FLUX PATCH SURFACE comment block at top + adds our own sentinel.

### Pattern 2: Bounded Retry Loop (Phase 2 D-13 / Phase 4 D-11)

```bash
local timeout_s=10
local token=""
for i in $(seq 1 "${timeout_s}"); do
  token="$(kubectl --context "k3d-${spoke}" -n flux-system \
    get secret flux-reconciler-token -o jsonpath='{.data.token}' 2>/dev/null || true)"
  [[ -n "${token}" ]] && break
  sleep 1
done
if [[ -z "${token}" ]]; then
  fail "flux-reconciler-token never populated on ${spoke} after ${timeout_s}s.
       Inspect: kubectl --context k3d-${spoke} -n flux-system describe secret/flux-reconciler-token
       Possible causes: SA was not applied first (D-07 ordering); apiserver under load.
       Fix: rerun: bash scripts/register-spokes-for-flux.sh"
  exit 1
fi
# Same shape for ca.crt extraction.
```

**Latency observation (verified live, k3s v1.31.5-k3s1):** the SA-token controller populates `data.token` and `data.ca.crt` in **<200ms** when the SA already exists (`kubectl wait --for=jsonpath` returned in 195ms in research probe #43). 10s cap is **very comfortable**; 5s would also work. Sticking with 10s per D-11 — defense-in-depth against a slow controller.

### Pattern 3: In-Pod Probe via `kubectl exec ... -- /bin/sh -c '...'` with Bearer Token (D-14 ADJUSTED)

```bash
# After hub Secret apply + kubeconfig assembly, run probes from inside kustomize-controller.
# Skip TLS validation (busybox wget can't load CA from a file); D-10's single-source CA
# extraction guarantees the CA in the kubeconfig matches the cert if the token is valid.

probe_pod_auth_and_node() {
  local spoke="$1" token="$2"
  local server="https://k3d-${spoke}-server-0:6443"

  # Step 1: auth roundtrip
  local readyz_out
  readyz_out="$(kubectl --context k3d-hub-flux -n flux-system exec deploy/kustomize-controller -- \
    /bin/sh -c "wget -qO- --no-check-certificate --header='Authorization: Bearer ${token}' '${server}/readyz' 2>&1" 2>&1 || true)"
  if [[ "${readyz_out}" != "ok" ]]; then
    fail "auth roundtrip failed for ${spoke}: ${readyz_out}
         Manually inspect: kubectl --context k3d-hub-flux -n flux-system exec deploy/kustomize-controller -- \\
           sh -c 'wget --no-check-certificate --header=\"Authorization: Bearer <TOKEN>\" ${server}/readyz'"
    exit 1
  fi
  pass "auth roundtrip ok: ${server}/readyz returned 'ok'"

  # Step 2: node-name negative-proof (P18 trip-wire)
  local nodes_out node_name expected_node="k3d-${spoke}-server-0" forbidden_node="k3d-hub-flux-server-0"
  nodes_out="$(kubectl --context k3d-hub-flux -n flux-system exec deploy/kustomize-controller -- \
    /bin/sh -c "wget -qO- --no-check-certificate --header='Authorization: Bearer ${token}' '${server}/api/v1/nodes' 2>/dev/null" 2>&1 || true)"
  # Extract node names from JSON (busybox toolkit — grep/sed)
  node_name="$(echo "${nodes_out}" | grep -oE '"name":[[:space:]]*"[^"]+"' | head -1 | grep -oE '"[^"]+"$' | tr -d '"')"
  if [[ "${node_name}" != "${expected_node}" ]]; then
    fail "node-name negative-proof FAILED for ${spoke}.
         Expected: '${expected_node}' (the spoke we targeted)
         Got:      '${node_name:-empty}'
         If '${forbidden_node}' appeared: P18 SILENT MISROUTE — kubeconfig routes hub→hub.
         Inspect: kubectl --context k3d-hub-flux -n flux-system get secret ${spoke}-kubeconfig -o jsonpath='{.data.value\\.yaml}' | base64 -d
         Fix: scripts/register-spokes-for-flux.sh — DO NOT push current state."
    exit 1
  fi
  pass "node-name proof ok: ${expected_node} reached via kubeconfig"
}
```

**Why `/api/v1/nodes` instead of `kubectl get nodes`:** the busybox image lacks kubectl. The REST API call returns the same data; we parse it with `grep -oE` — busybox grep supports `-oE`. The spoke clusters are single-node, so there's exactly one `"name"` field in the JSON; `head -1` is defensive.

**Why `/readyz` for the auth roundtrip instead of `auth can-i`:** kubectl-less pod can't run can-i. `/readyz` returns `ok` if the apiserver is up AND the bearer token is valid (or the apiserver allows anonymous /readyz, which k8s does NOT by default — verified live: anonymous returned 401, authenticated returned 200 + "ok"). For a richer auth check, POST a `SelfSubjectAccessReview` to `/apis/authorization.k8s.io/v1/selfsubjectaccessreviews` (verified live too) — but `/readyz` is simpler and sufficient for our purpose (it proves the token authenticates).

### Anti-Patterns to Avoid

- **`set -x` in the script** — the kubeconfig contains a bearer token; tracing every command would echo the token. Phase 3 D-11 already locks this; Phase 4 inherits.
- **`echo "$TOKEN"` / `printf "%s" "$TOKEN"` / `info "$TOKEN"` / `pass "$TOKEN"` / etc.** — the helpers `pass`/`warn`/`fail`/`info` (from `preflight-lib.sh`) print to stdout; pass them token strings and you've leaked. The bats `register-spokes-01-static.bats` MUST grep for `\$TOKEN` near these helpers and fail if found.
- **Committing the hub-side `<spoke>-kubeconfig` Secret** — it contains a bearer token. Apply imperatively only; never `kubectl create -f spoke-kubeconfig.yaml` on a path under `clusters/`. Phase 4 D-04 codifies this.
- **`set -a; source .env; set +a`** — Phase 3 banned this for the same reason (Phase 3 D-11). Phase 4 doesn't read `.env` at all (no GitHub PAT needed); but the pattern would be wrong if introduced.
- **Omitting `spec.kubeConfig` from the Flux Kustomization YAML** — the REAL P18 fault mode (verified live: when `spec.kubeConfig` is absent, the controller reconciles via in-cluster SA, lands on hub, reports `Ready=True`). The Kustomization template MUST always include `spec.kubeConfig.secretRef.{name,key}`.
- **`spec.kubeConfig.secretRef.key:` left blank/missing** — verified safe in current Flux 2.8.6 (defaults to `value` OR `value.yaml`), but a future Flux behavior change could trigger silent-misroute drift. Always set `key: value.yaml` explicitly. Bats static test pins the literal `value.yaml` in the spoke-ml.yaml / spoke-apps.yaml templates.
- **Using `kubectl create token <sa>`** — TokenRequest tokens expire (default 1h). PROJECT.md Phase-4 key decision rejects this; legacy Secret-backed tokens have indefinite lifetime which is correct for a lab.
- **Creating the SA-token Secret BEFORE the SA exists** — verified live: the orphan Secret was auto-deleted by the controller within 3 seconds. Order of operations MUST be: SA → CRB → Secret (annotation references the SA name). The `register_spoke` helper enforces this naturally if it applies all three resources in a single `kubectl apply -f -` heredoc (kubectl applies in document order; SA appears first).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Building a kubeconfig YAML by hand | Custom YAML library / template engine | `cat <<EOF ... EOF` heredoc with `$CA_DATA`, `$TOKEN`, `$SERVER` substitution (D-09) | 25-line one-shot artifact; bash substitution handles base64-url alphanumeric tokens cleanly |
| Extracting CA + token from a Secret | `openssl s_client + base64` from the apiserver | `kubectl get secret <name> -o jsonpath='{.data.ca\.crt}'` and `'{.data.token}'` (D-10) | The `kubernetes.io/service-account-token` controller writes both fields atomically; using one source eliminates drift |
| Creating a Secret with `value.yaml` key | Hand-craft the base64 + heredoc Secret YAML | `kubectl create secret generic <name> --from-file=value.yaml=/dev/stdin --dry-run=client -o yaml \| kubectl apply -f -` | Verified live: produces correct `data.value.yaml` field; idempotent on apply |
| Waiting for Secret data population | Polling `kubectl get` in a `while true` loop | Bounded retry loop (10×1s) per D-11 OR `kubectl wait --for=jsonpath='{.data.token}' secret/<name> --timeout=10s` | k3s controller populates in <200ms; either approach works. D-11 picks bounded retry for clearer failure surface — keep that. |
| In-pod kubeconfig probe | Spawn ephemeral kubectl pod via `kubectl run` | `kubectl exec deploy/kustomize-controller -- sh -c 'wget ...'` (D-14 adjusted) | Authoritative: this IS the identity Flux uses. wget is enough for /readyz + /api/v1/nodes |
| Parsing a kubeconfig server URL | sed/awk over base64-decoded YAML | `... \| base64 -d \| yq eval '.clusters[0].cluster.server' -` (D-13 step 2) | Verified live: yq 4.53.2 handles piped YAML cleanly |
| Negative-proof of correct cluster | Walking node objects manually, parsing labels | Node-name probe: `name == k3d-${spoke}-server-0` (D-15) | k3d sets node `metadata.name` to literal `k3d-<cluster>-server-0` — verified live on all 3 clusters |
| Negative-proof of correct reconciliation | Polling `.status.inventory` from inside the script | bats live test post-push (D-16) | Reconciliation is GitOps; lives on its own clock. Script ends at credential layer (D-15) |
| Patch surface re-application on re-run | Diff-based approach with full file rewrite | Sentinel-grep idempotency: `grep -qF "# KARYON SPOKES MOUNT"` → skip; else awk-insert (D-02 / Phase 3 D-13 pattern) | Phase 3 proved this pattern works through one bootstrap re-run; Phase 4 inherits |

**Key insight:** The controller (in this case `kustomize-controller` for Flux, or `kube-controller-manager` for legacy SA tokens) is doing real, well-tested work. Hand-rolled equivalents either duplicate this work badly (e.g., openssl s_client extracts the wrong cert) or miss edge cases the upstream controller already handles (e.g., empty data fields if the SA doesn't exist when the Secret is created).

## Runtime State Inventory

> Phase 4 is **NOT a rename / refactor / migration phase** — it adds new files and on-cluster resources without renaming or replacing existing assets. This section is included for completeness but most rows are "N/A — greenfield".

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — Phase 4 creates new SAs/Secrets/CRBs/ConfigMaps; no existing data is renamed | None |
| Live service config | None — no n8n / Datadog / external service references | None |
| OS-registered state | None — nothing in Windows Task Scheduler, systemd, or pm2 references Phase-4 names | None |
| Secrets/env vars | None NEW required from `.env`; no env var renames | None — Phase 4 reads ZERO `.env` keys |
| Build artifacts | None — Phase 4 doesn't build images or packages | None |

**Phase 4 idempotency-by-presence:** the script's "skip if exists + verify expected config" pattern (Phase 2 D-09 / Phase 3 D-07 inheritance) handles re-runs without state churn.

## Common Pitfalls

### Pitfall 1: Creating the SA-token Secret BEFORE the SA exists

**What goes wrong:** Apply a Secret of type `kubernetes.io/service-account-token` with annotation `kubernetes.io/service-account.name: foo` when SA `foo` doesn't exist yet → the Secret is auto-deleted by the controller within ~3 seconds (verified live, 2026-04-27 against k3s v1.31.5-k3s1).

**Why it happens:** The token controller validates the SA reference; an orphan Secret is treated as garbage and removed.

**How to avoid:** Apply SA + CRB + Secret in a single `kubectl apply -f -` heredoc — kubectl applies resources in document order, so the SA lands first. Verified live: this works.

**Warning signs:** `kubectl get secret/<token-name>` returns `NotFound` 5 seconds after apply. The bounded retry loop (D-11) will time out on `data.token` extraction. Diagnostic: `kubectl get sa/<sa-name>` first to confirm the SA exists.

### Pitfall 2: Wrong-key vs missing-`spec.kubeConfig` are DIFFERENT failure modes

**What goes wrong:** Phase 4 conflates two distinct silent-misroute scenarios in P18 framing.

| Scenario | Live behavior | Where caught |
|----------|--------------|--------------|
| `spec.kubeConfig.secretRef.key: value.yaml` set; Secret has only key `value` | `Ready=False` with message `KubeConfig secret '...' does not contain a 'value.yaml' key` | LOUD — Flux surfaces it immediately |
| `spec.kubeConfig.secretRef.key:` unset; Secret has key `value` OR `value.yaml` | Reconciles successfully (Flux probes BOTH defaults — verified live) | LOUD if content is invalid; SILENT if content is wrong-but-valid |
| `spec.kubeConfig` block ENTIRELY ABSENT | Reconciles via controller's in-cluster SA → lands on HUB → `Ready=True` | **SILENT — this is the real P18** |
| Kubeconfig content has wrong `server:` URL | Either fails (TLS / network) or reconciles into wrong cluster — depends on what server points at | SILENT if the wrong server is also reachable + has compatible CA/token; otherwise loud |

**Why it happens:** Older Flux versions and folkloric posts conflate these. Live testing against Flux 2.8.6 shows wrong-key produces a clear error.

**How to avoid:** Phase 4's defenses still cover both:
1. Always include `spec.kubeConfig.secretRef.{name,key}` in every spoke Kustomization YAML (defends against the silent-fallback case).
2. Set `key: value.yaml` explicitly (defense-in-depth against future Flux behavior changes).
3. Run the node-name probe (D-13 step 4) — proves the kubeconfig actually targets the spoke.

**Warning signs:** Kustomization Ready=True but resources appearing on hub instead of spoke. The bats live test (`register-spokes-02-live.bats`, D-16) catches this via `.status.inventory` regex `karyon-spoke-ml_karyon-spoke-id__ConfigMap` (the seed ConfigMap only exists on the spoke; if reconciled to hub, the entry would never appear).

### Pitfall 3: kustomize-controller image lacks `kubectl` (D-14 deviation)

**What goes wrong:** D-14 as written runs `kubectl exec deploy/kustomize-controller -- kubectl auth can-i ...`. The kustomize-controller v1.8.4 image is distroless-style and ships no `kubectl`, no `curl`, no `jq`.

**Why it happens:** Flux upstream removed shell-tool clutter from controller images years ago for security/size; the image carries only what the Go binary needs at runtime (sh + ssh + openssl + busybox-wget for cloning Git repos / talking to apiservers).

**How to avoid:** Phase 4 plan adjusts D-14: replace the kubectl invocations inside the pod with `wget --no-check-certificate --header='Authorization: Bearer <TOKEN>' <URL>` against `/readyz` and `/api/v1/nodes`. Parse with `grep -oE` (busybox grep supports `-oE`).

**Warning signs:** `command terminated with exit code 1` from `kubectl exec ... -- kubectl ...`. Diagnostic: `kubectl exec deploy/kustomize-controller -- which kubectl 2>&1` returns no output / exit 1.

### Pitfall 4: `kubectl wait --all` on an empty Deployment set

**What goes wrong:** `kubectl wait --for=condition=Available deploy --all --timeout=120s` returns 0 if there are ZERO Deployments matching, masking a total failure.

**Why it happens:** k8s `--all` semantics: empty set trivially passes.

**How to avoid:** Phase 3 already encoded this as Pitfall 4 in `scripts/bootstrap-flux.sh` ("count deployments BEFORE kubectl wait --all"). Phase 4 doesn't run this kind of wait — but the principle generalizes to inventory checks: assert that `.status.inventory.entries` has length ≥ 1 before grepping for the seed ConfigMap entry. Empty inventory could be misread as "no resources found and that's fine".

**Warning signs:** Tests passing inexplicably; spoke clusters appearing empty when they shouldn't be.

### Pitfall 5: `grep` matching `Ready` substring of `NotReady`

**What goes wrong:** `flux get kustomizations | grep -q Ready` matches `NotReady` too. Phase 3 already encoded this in `scripts/bootstrap-flux.sh` (Pitfall 5).

**Why it happens:** `Ready` is a strict substring of `NotReady`.

**How to avoid:** Use `kubectl get kustomization <name> -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'` and compare to literal `True`. This is the form Phase 3 already uses; Phase 4 inherits.

**Warning signs:** Bats test passes but `flux get kustomizations` shows the Kustomization in `False` state.

### Pitfall 6: Re-bootstrap rewrites the FLUX PATCH SURFACE kustomization.yaml

**What goes wrong:** Theoretically, `flux bootstrap` rewriting `clusters/hub-flux/flux-system/kustomization.yaml` could remove our `- ../spokes` line (Phase 4 D-02).

**Why it happens:** Flux bootstrap is reconciliation-based; if its idempotency rules diverge from what the local file already has, it rewrites.

**How to avoid:** Phase 3 D-13 already proved (via the live destructive test in 03-VERIFICATION.md) that `flux bootstrap` does NOT rewrite `kustomization.yaml` if its `resources:` block is consistent with what the bootstrap flags imply. Adding `- ../spokes` doesn't conflict with `resources: [gotk-components.yaml, gotk-sync.yaml]` (the bootstrap manages only those two; user additions survive). However:
- The Phase 4 register-spokes script must re-apply the patch idempotently on every run (sentinel-grep) — defends against an unforeseen flux behavior change.
- The bats static test pins both the `# KARYON SPOKES MOUNT` sentinel AND the `- ../spokes` literal.

**Warning signs:** `git diff clusters/hub-flux/flux-system/kustomization.yaml` after a `task bootstrap-flux && task register-spokes` chain shows the spokes line removed. Bats test fails on the sentinel grep.

### Pitfall 7: kustomize-build's load-restrictor on parent-dir reference

**What goes wrong:** Some kustomize versions reject `- ../spokes` (parent-dir reference) without `--load-restrictor=LoadRestrictionsNone`.

**Why it happens:** Pre-3.x kustomize had stricter root-restriction semantics.

**How to avoid:** Verified live with kustomize 5.7.1 (embedded in kubectl 1.35.0): `kubectl kustomize clusters/hub-flux/flux-system/` with `- ../spokes` in resources reads cleanly without any flag. Flux 2.8.6's bundled kustomize-controller image (v1.8.4) uses kustomize 5.x as well — same behavior. **No flag adjustment needed.**

**Warning signs:** `kustomize build` fails with `security; file is not in or below ...`. Diagnostic: `kubectl kustomize clusters/hub-flux/flux-system/` from the repo root.

## Code Examples

Verified patterns from official sources / live tests:

### Example 1: Apply Spoke RBAC (SA + CRB + Token Secret) Atomically

```bash
# Source: live-tested 2026-04-27 against k3d-spoke-ml; SA-first ordering verified.
register_spoke_rbac() {
  local spoke="$1"
  kubectl --context "k3d-${spoke}" apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: flux-reconciler
  namespace: flux-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: flux-reconciler-cluster-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: flux-reconciler
  namespace: flux-system
---
apiVersion: v1
kind: Secret
metadata:
  name: flux-reconciler-token
  namespace: flux-system
  annotations:
    kubernetes.io/service-account.name: flux-reconciler
type: kubernetes.io/service-account-token
EOF
}
```

**Why this works:** kubectl applies multi-document YAML in input order. The SA lands first (so it exists when the controller observes the annotated Secret), the CRB second (no order dependency), the Secret last. The `flux-system` namespace already exists on each spoke from k3s default kube-system installation? **NO — verify:** k3s spokes ship without a `flux-system` namespace by default; the helper must `kubectl create namespace flux-system --dry-run=client -o yaml | kubectl apply -f -` before applying RBAC, OR include the Namespace in the heredoc above. Adding it to the heredoc is cleaner:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: flux-system
---
apiVersion: v1
kind: ServiceAccount
...
```

### Example 2: Wait for Token + CA Population

```bash
# Source: D-11 + verified live (k3s populates in <200ms when SA exists).
wait_for_token_secret() {
  local spoke="$1"
  local timeout_s=10
  local token=""
  local ca=""
  for i in $(seq 1 "${timeout_s}"); do
    token="$(kubectl --context "k3d-${spoke}" -n flux-system \
      get secret flux-reconciler-token -o jsonpath='{.data.token}' 2>/dev/null || true)"
    ca="$(kubectl --context "k3d-${spoke}" -n flux-system \
      get secret flux-reconciler-token -o jsonpath='{.data.ca\.crt}' 2>/dev/null || true)"
    [[ -n "${token}" && -n "${ca}" ]] && break
    sleep 1
  done
  if [[ -z "${token}" || -z "${ca}" ]]; then
    fail "flux-reconciler-token not populated on ${spoke} after ${timeout_s}s.
         Inspect: kubectl --context k3d-${spoke} -n flux-system describe secret/flux-reconciler-token
         Possible: SA missing (orphan Secret); apiserver under load; controller race.
         Fix: rerun: bash scripts/register-spokes-for-flux.sh"
    exit 1
  fi
  # Return via globals (or printf — caller's choice).
  TOKEN_B64="${token}"
  CA_B64="${ca}"
}
```

**Note:** TOKEN_B64 and CA_B64 are returned base64-ENCODED (raw `data.token` / `data.ca.crt` are base64). The kubeconfig YAML expects `certificate-authority-data: <base64>` (already base64) and `token: <decoded-string>`. So:

```bash
TOKEN="$(echo "${TOKEN_B64}" | base64 -d)"  # decode for kubeconfig token: field
# CA_B64 stays as-is — kubeconfig wants base64 in certificate-authority-data
```

### Example 3: Build the Kubeconfig YAML

```bash
# Source: D-09 heredoc; verified shape against the live spoke-ml extraction.
build_kubeconfig() {
  local spoke="$1" token="$2" ca_b64="$3"
  local server="https://k3d-${spoke}-server-0:6443"
  cat <<EOF
apiVersion: v1
kind: Config
clusters:
- name: ${spoke}
  cluster:
    server: ${server}
    certificate-authority-data: ${ca_b64}
contexts:
- name: ${spoke}
  context:
    cluster: ${spoke}
    user: flux-reconciler
current-context: ${spoke}
users:
- name: flux-reconciler
  user:
    token: ${token}
EOF
}
```

### Example 4: Apply Hub Secret Imperatively (NEVER committed)

```bash
# Source: verified live — --from-file=value.yaml=/dev/stdin produces data.value.yaml.
# Idempotent on apply: creates → configures → no-op based on content hash.
apply_hub_secret() {
  local spoke="$1" kubeconfig_yaml="$2"
  printf '%s\n' "${kubeconfig_yaml}" \
    | kubectl --context k3d-hub-flux -n flux-system create secret generic \
        "${spoke}-kubeconfig" \
        --from-file=value.yaml=/dev/stdin \
        --dry-run=client -o yaml \
    | kubectl --context k3d-hub-flux -n flux-system apply -f -
}
```

### Example 5: Hub-side Flux Kustomization YAML (Per-spoke)

```yaml
# Source: D-15 + Flux v1 CRD spec verified via `kubectl explain`.
# File: clusters/hub-flux/spokes/spoke-ml.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: spoke-ml
  namespace: flux-system
spec:
  interval: 5m            # Phase 4 default; Phase 5 may tune per workload tree.
  path: ./clusters/spoke-ml
  prune: true             # Phase 5 will exercise pruning; Phase 4 seed is additive.
  sourceRef:
    kind: GitRepository
    name: flux-system     # The bootstrap-managed GitRepo created by Phase 3.
  kubeConfig:
    secretRef:
      name: spoke-ml-kubeconfig
      key: value.yaml     # EXPLICIT per REQ-SPOKE-04 / Pitfall 2 defense-in-depth.
  # No spec.targetNamespace — let the spoke's manifests declare their own namespaces.
```

**Note:** No `serviceAccountName` set. With `spec.kubeConfig`, the controller authenticates as the `flux-reconciler` SA on the spoke (via the bearer token in the kubeconfig). Adding `serviceAccountName` would trigger impersonation (a different RBAC path); we don't need it.

### Example 6: Spoke Seed Manifests

```yaml
# File: clusters/spoke-ml/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- namespace.yaml
- configmap.yaml
```

```yaml
# File: clusters/spoke-ml/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: karyon-spoke-ml
```

```yaml
# File: clusters/spoke-ml/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: karyon-spoke-id
  namespace: karyon-spoke-ml
data:
  spoke: spoke-ml          # Distinct per spoke — falsifiable for negative-proof.
```

The mirror for `clusters/spoke-apps/` substitutes `karyon-spoke-apps` and `data.spoke: spoke-apps`.

### Example 7: In-Pod Auth + Node-Name Probe (D-14 ADJUSTED)

```bash
# Source: live-verified 2026-04-27 against k3d-hub-flux + k3d-spoke-ml.
# Drop-in replacement for D-14's kubectl-based form (image lacks kubectl).
probe_in_pod() {
  local spoke="$1" token="$2"
  local server="https://k3d-${spoke}-server-0:6443"

  # Auth roundtrip — /readyz returns "ok" if 200 + token authorized.
  local readyz
  readyz="$(kubectl --context k3d-hub-flux -n flux-system exec deploy/kustomize-controller -- \
    /bin/sh -c "wget -qO- --no-check-certificate --header='Authorization: Bearer ${token}' '${server}/readyz' 2>&1" \
    2>&1 || true)"
  if [[ "${readyz}" != "ok" ]]; then
    fail "auth roundtrip failed for ${spoke}: ${readyz}
         Manual repro: kubectl --context k3d-hub-flux -n flux-system exec deploy/kustomize-controller -- \\
           /bin/sh -c \"wget --no-check-certificate --header='Authorization: Bearer <TOKEN>' ${server}/readyz\""
    exit 1
  fi
  pass "auth roundtrip ok for ${spoke}"

  # Node-name negative-proof — the apiserver returns the node's metadata.name.
  local nodes_json node_name expected="k3d-${spoke}-server-0"
  nodes_json="$(kubectl --context k3d-hub-flux -n flux-system exec deploy/kustomize-controller -- \
    /bin/sh -c "wget -qO- --no-check-certificate --header='Authorization: Bearer ${token}' '${server}/api/v1/nodes' 2>/dev/null" \
    2>&1 || true)"
  node_name="$(echo "${nodes_json}" | grep -oE '"name"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | grep -oE '"[^"]+"$' | tr -d '"')"
  if [[ "${node_name}" != "${expected}" ]]; then
    fail "node-name negative-proof FAILED for ${spoke}.
         Expected: '${expected}' — Got: '${node_name:-empty}'
         If node_name is 'k3d-hub-flux-server-0' → P18 SILENT MISROUTE caught.
         Inspect: kubectl --context k3d-hub-flux -n flux-system get secret ${spoke}-kubeconfig -o jsonpath='{.data.value\\.yaml}' | base64 -d
         Action:  DO NOT push current state."
    exit 1
  fi
  pass "node-name proof ok for ${spoke}: '${node_name}'"
}
```

### Example 8: bats Live Test — `.status.inventory` Negative-Proof (D-16)

```bash
# File: tests/bats/register-spokes-02-live.bats
load 'test_helper'

setup() {
  require_live_destructive
}

@test "spoke-ml Kustomization Ready=True (assumes user has pushed)" {
  run kubectl --context k3d-hub-flux -n flux-system get kustomization spoke-ml \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
  [[ "$status" -eq 0 ]]
  [[ "$output" == "True" ]]
}

@test "spoke-ml inventory contains the seed ConfigMap (negative-proof of correct cluster)" {
  run bash -c "kubectl --context k3d-hub-flux -n flux-system get kustomization spoke-ml \
        -o json | jq -r '.status.inventory.entries[].id' \
        | grep -F 'karyon-spoke-ml_karyon-spoke-id__ConfigMap'"
  [[ "$status" -eq 0 ]]
}

@test "spoke-apps Kustomization Ready=True" {
  run kubectl --context k3d-hub-flux -n flux-system get kustomization spoke-apps \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
  [[ "$status" -eq 0 ]]
  [[ "$output" == "True" ]]
}

@test "spoke-apps inventory contains the seed ConfigMap" {
  run bash -c "kubectl --context k3d-hub-flux -n flux-system get kustomization spoke-apps \
        -o json | jq -r '.status.inventory.entries[].id' \
        | grep -F 'karyon-spoke-apps_karyon-spoke-id__ConfigMap'"
  [[ "$status" -eq 0 ]]
}

@test "spoke seed ConfigMap exists ONLY on the targeted spoke (cross-cluster falsifier)" {
  # The karyon-spoke-id ConfigMap should NOT exist on hub.
  run kubectl --context k3d-hub-flux -n karyon-spoke-ml get configmap karyon-spoke-id 2>&1
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"NotFound"* ]] || [[ "$output" == *"not found"* ]]
  # AND it SHOULD exist on the spoke.
  run kubectl --context k3d-spoke-ml -n karyon-spoke-ml get configmap karyon-spoke-id \
        -o jsonpath='{.data.spoke}'
  [[ "$status" -eq 0 ]]
  [[ "$output" == "spoke-ml" ]]
}
```

**Inventory ID format** (verified live + cited from Flux docs): `<namespace>_<name>_<group>_<kind>` — for a core API ConfigMap (empty group), this becomes `<namespace>_<name>__<kind>` (literal double-underscore between name and kind). Examples from the live `flux-system` Kustomization on hub:

```text
flux-system_kustomize-controller__ServiceAccount      # core API: empty group
flux-system_kustomize-controller_apps_Deployment      # apps API
flux-system_helm-controller_apps_Deployment
_alerts.notification.toolkit.fluxcd.io_apiextensions.k8s.io_CustomResourceDefinition   # cluster-scoped: empty namespace
```

So our seed ConfigMap entry is `karyon-spoke-ml_karyon-spoke-id__ConfigMap` (or `karyon-spoke-apps_karyon-spoke-id__ConfigMap`). The bats grep MUST use the literal `__ConfigMap` (two underscores).

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Auto-generated SA token Secrets per ServiceAccount | Manual creation: explicit Secret of type `kubernetes.io/service-account-token` with `kubernetes.io/service-account.name` annotation | k8s 1.24 (LegacyServiceAccountTokenNoAutoGeneration GA), 2022 | Phase 4 must create the Secret explicitly. CONTEXT.md / D-07 already encodes this. Indefinite-lifetime tokens are STILL supported — the deprecation only removed *auto*-creation. |
| `kubectl create token <sa>` (TokenRequest API) | Legacy Secret-backed token (this phase) | k8s 1.22 (TokenRequest GA), 2021 | TokenRequest tokens expire (default 1h, configurable). PROJECT.md Phase-4 key decision rejects TokenRequest in favor of Secret-backed for the lab — token expiry is not a useful failure mode. |
| Flux `kustomize-controller` v0/v1beta1/v1beta2 | `kustomize.toolkit.fluxcd.io/v1` (GA) | Flux 2.0.0 (May 2023) | Phase 4 uses v1; the spec.kubeConfig shape is stable. |
| `--load-restrictor=LoadRestrictionsNone` for parent-dir kustomize references | Default behavior in kustomize 5.x permits `- ../spokes` | kustomize 5.0 (Dec 2022) | Verified live: kubectl 1.35.0 / kustomize 5.7.1 reads `- ../spokes` cleanly. No flag needed. |
| In-cluster fallback for `spec.kubeConfig` errors | `Ready=False` for wrong-key / missing-Secret; in-cluster fallback only when `spec.kubeConfig` is ABSENT entirely | At least Flux 2.8.x; not a recent change (verified live 2026-04-27) | Updates the threat model: P18 is "block accidentally omitted" not "key typo silently misroutes". |

**Deprecated/outdated:**
- `apiVersion: kustomize.toolkit.fluxcd.io/v1beta1` and `v1beta2` — still work (Flux maintains compatibility) but should not be used in new manifests. Use `v1`.
- TokenRequest (`kubectl create token`) for hub-spoke kubeconfigs in lab settings — token expiry adds operational toil with no security benefit at lab scope.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Flux 2.8.6 / kustomize-controller v1.8.4 will continue to probe BOTH `value` AND `value.yaml` as default keys when `key:` is unset (verified live 2026-04-27, but a future Flux behavior change could narrow this) | SPOKE-04 | LOW — Phase 4 sets `key: value.yaml` explicitly (D-15 / Pitfall 2 defense), so any narrowing of the default doesn't affect us. Bats static test pins the literal `value.yaml`. |
| A2 | Future re-bootstraps of Flux on hub will continue to leave `clusters/hub-flux/flux-system/kustomization.yaml`'s user-added `resources:` entries (`- ../spokes`) untouched (Phase 3 D-13 Rule 2 inheritance — verified for inline patches; assumed for `resources:` directory references) | D-02 | MEDIUM — if a future flux-bootstrap version starts rewriting `resources:`, the Phase 4 patch is lost on re-bootstrap. Mitigation: register-spokes script's sentinel-grep idempotency re-applies the patch on every run. |
| A3 | Spokes (`k3d-spoke-ml`, `k3d-spoke-apps`) ship WITHOUT a `flux-system` namespace by default (CONTEXT.md doesn't explicitly say; the Phase 4 RBAC must create it) | SPOKE-01 / Example 1 | LOW — even if it exists, `kubectl apply` of a Namespace is idempotent. Plan should verify by `kubectl --context k3d-spoke-ml get ns flux-system 2>&1` in research-prep step (researcher confirms below). |
| A4 | k3s v1.31.5-k3s1 SA-token controller behavior (verified live) generalizes to k3s v1.34.6-k3s1 (the pinned line for Phase 4 spokes) — both are k8s 1.31+ which has stable LegacyServiceAccountTokenNoAutoGeneration semantics | SPOKE-02 / Pitfall 1 | LOW — the SA-token Secret protocol is part of stable kube-controller-manager behavior; not a k3s-specific surface. |
| A5 | The kustomize-controller image (`ghcr.io/fluxcd/kustomize-controller:v1.8.4`) shipped with Flux 2.8.6 won't change its tooling layer in patch releases (verified live; future minor bumps may differ) | D-14 / Example 7 | LOW — pinned to 2.8.6; bats live test verifies `wget` + `nslookup` are available before running probes. If Flux 2.9 ever ships kubectl-equipped images, we can swap probes back. |
| A6 | The negative-proof bats test (D-16) only runs after the user has manually pushed Phase 4 changes to `origin/main` AND Flux has reconciled (interval 1m for the GitRepository, 10m for the root flux-system Kustomization) | D-16 | LOW — test gated by `KARYON_LIVE_TESTS_DESTRUCTIVE=1`; user runs it explicitly post-push. The bats test should `info` "If this test fails, ensure: (a) git push completed, (b) `flux reconcile source git flux-system` was run, (c) `flux reconcile kustomization flux-system` was run". |
| A7 | The k8s.io documentation page on Service Accounts (cited in §State of the Art) accurately describes legacy SA-token Secret behavior in k8s 1.31+ (the pinned k3s line) | SPOKE-02 | LOW — the docs page is the canonical source; verified empirically against the live cluster as well. |

**Note on A2:** This is the highest-risk assumption. The mitigation (sentinel-grep idempotency on every `register-spokes` run) is robust but only fires if the user runs the script after a re-bootstrap. The bats static test pins the literals, so a CI run would catch a missing `- ../spokes` line — provided the user committed the post-rerun state. The plan should include an `info` line at the end of `bootstrap-flux.sh` (or `register-spokes-for-flux.sh`) suggesting a follow-up `task register-spokes` after any `task bootstrap-flux` run. (Optional.)

## Open Questions

1. **Should the script create the `flux-system` namespace on each spoke explicitly, or rely on it being pre-existent?**
   - What we know: k3d default k3s install ships kube-system / default / kube-public / kube-node-lease / kube-flannel only. `flux-system` does not exist on a fresh spoke.
   - What's unclear: whether including `Namespace flux-system` in the RBAC heredoc is cleaner than running a prior `kubectl apply -f <(echo "apiVersion: v1; kind: Namespace; ...")` step.
   - Recommendation: include in the heredoc (Example 1 above). kubectl multi-doc apply handles it idempotently; no separate step.

2. **Should `spec.interval` on the spoke Flux Kustomization match the root `flux-system` Kustomization's interval (10m), or be tighter (5m)?**
   - What we know: D-15 example uses 5m. The root flux-system uses 10m (verified live in `gotk-sync.yaml`).
   - What's unclear: whether 5m is too aggressive for a lab (more apiserver chatter) or appropriate for fast feedback during development.
   - Recommendation: 5m for spokes during active development; the root continues at 10m. Phase 5 may revisit when full workloads land.

3. **Should the script handle a partial-success scenario where spoke-ml registers but spoke-apps fails?**
   - What we know: D-10 (Phase 2) "no auto-cleanup; idempotent rerun resumes" — the helper structure (`register_spoke spoke-ml; register_spoke spoke-apps`) means a failure on spoke-apps leaves spoke-ml's RBAC + hub Secret in place; rerun continues from spoke-apps.
   - What's unclear: whether the user-facing Summary should distinguish "1 of 2 spokes registered" from "all spokes registered". Phase 1/2/3 vocabulary uses `pass`/`warn`/`fail` counters, not per-spoke state.
   - Recommendation: current vocabulary is sufficient. The script's section structure (`section "spoke-ml"`, `section "spoke-apps"`) makes a failure self-locating.

4. **Should the bats live test include a "user must push before running this" precondition check?**
   - What we know: D-16 explicitly assumes the user has pushed; the test reads `.status.inventory` which only populates after Flux reconciles a pushed commit.
   - What's unclear: whether the test should `skip` (with a helpful message) if it detects the local checkout is ahead of `origin/main`, vs. fail loudly.
   - Recommendation: skip-with-message — the test isn't broken, the user just hasn't completed the workflow. Add `setup()`: `git diff origin/main HEAD -- clusters/hub-flux/spokes/ clusters/spoke-ml/ clusters/spoke-apps/` exits 0 (no diff) → run; otherwise skip with `"please git push and wait 1-2 min for Flux to reconcile, then rerun"`.

5. **Should the script include a `flux reconcile kustomization flux-system --with-source` invocation at the end as a convenience nudge?**
   - What we know: D-04 says "no git mutations from the script"; doesn't speak to manually triggering Flux reconciliation.
   - What's unclear: whether triggering reconciliation is mutation-y enough to fall under D-04's spirit. The user has to push first anyway, so the trigger only helps after push.
   - Recommendation: don't trigger from the script — the user runs it themselves after `git push`. The summary `info` line should include the suggested command (`flux reconcile source git flux-system && flux reconcile kustomization flux-system`).

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `kubectl` | RBAC apply, Secret apply, jsonpath extraction, exec into pod | ✓ | 1.35.0 | — |
| `flux` (CLI) | Optional `flux reconcile` nudge in summary `info` | ✓ | 2.8.6 | omit nudge if absent (warn-only) |
| `jq` | bats live test parsing `.status.inventory` JSON | ✓ | 1.8.1 | — |
| `yq` | D-13 step 2 — parse decoded kubeconfig YAML | ✓ | 4.53.2 (mikefarah Go yq) | — |
| `openssl` | Not used in Phase 4 (D-12 trusts the literal) | ✓ | OpenSSL 3.0.13 | — |
| `awk`, `sed`, `grep` | Sentinel-grep idempotency, JSON parsing in pod (busybox grep -oE) | ✓ | system + busybox | — |
| `base64` | base64-encode / -decode kubeconfig fields | ✓ | system (coreutils) | — |
| Hub apiserver `:6443` reachability from local host | `kubectl --context k3d-hub-flux ...` | ✓ | k3d publishes :6443 | — |
| Spoke apiservers `:6444` / `:6445` reachability from local host | `kubectl --context k3d-spoke-ml ...`, `--context k3d-spoke-apps ...` | ✓ | k3d publishes ports | — |
| `k3d-<spoke>-server-0` DNS reachability from inside hub kustomize-controller pod | D-13 / D-14 in-pod probe | ✓ | Verified live: nslookup + wget reach |
| `kustomize-controller` pod has `wget` + `nslookup` + `sh` | D-14 in-pod probe (adjusted) | ✓ | Verified live in image v1.8.4 | — |
| `kustomize-controller` pod has `kubectl` | D-14 ORIGINAL form (kubectl auth can-i / get nodes) | ✗ | — | wget-based probe (Example 7 above) |
| `kustomize-controller` pod has `curl` / `jq` / `yq` / `python3` | (Not used) | ✗ | — | wget + busybox grep -oE / sed sufficient |

**Missing dependencies with fallback:**
- `kubectl` inside `kustomize-controller` pod → use `wget --no-check-certificate --header='Authorization: Bearer <TOKEN>'` against `/readyz` and `/api/v1/nodes` (Example 7).

**Missing dependencies with no fallback:** None. All Phase 4 needs is satisfied.

## Validation Architecture

> Required per Phase 4 ROADMAP risk profile (HIGH-risk single phase). Nyquist sampling: each requirement has at least one "below-Nyquist" automated check (catches obvious failure modes) AND at least one human-verifiable post-push check (catches the residual reconciliation-layer risks).

### Test Framework

| Property | Value |
|----------|-------|
| Framework | bats-core (system-installed; bats files live under `tests/bats/`) |
| Config file | None — `tests/bats/test_helper.bash` is the shared loader (already exists from Phase 1/2/3). |
| Quick run command | `bats tests/bats/register-spokes-01-static.bats --tap` |
| Full suite command | `KARYON_LIVE_TESTS=1 KARYON_LIVE_TESTS_DESTRUCTIVE=1 bats tests/bats/register-spokes-*.bats --tap` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SPOKE-01 | Script creates SA + cluster-admin CRB on each spoke | static (greps for SA name + CRB name + ClusterRole reference) | `bats tests/bats/register-spokes-01-static.bats -f 'SPOKE-01'` | ❌ Wave 0 |
| SPOKE-01 | RBAC actually applied on cluster (live) | live destructive | `KARYON_LIVE_TESTS=1 KARYON_LIVE_TESTS_DESTRUCTIVE=1 bats tests/bats/register-spokes-02-live.bats -f 'SPOKE-01'` | ❌ Wave 0 |
| SPOKE-02 | Token Secret type + annotation correct | static | `bats tests/bats/register-spokes-01-static.bats -f 'SPOKE-02'` | ❌ Wave 0 |
| SPOKE-02 | Token Secret data populated on spoke after run | live | included in -02-live.bats | ❌ Wave 0 |
| SPOKE-03 | Server URL literal `https://k3d-<spoke>-server-0:6443` in script | static | `bats tests/bats/register-spokes-01-static.bats -f 'SPOKE-03'` | ❌ Wave 0 |
| SPOKE-04 | `value.yaml` key literal in 4+ places (script, Kustomization YAML template, doc, bats) | static | `bats tests/bats/register-spokes-01-static.bats -f 'SPOKE-04'` | ❌ Wave 0 |
| SPOKE-04 | Hub Secret has `data.value.yaml` (live) | live | `kubectl --context k3d-hub-flux -n flux-system get secret spoke-ml-kubeconfig -o jsonpath='{.data.value\.yaml}' \| head -c 1` (in-script verification gate D-13 step 1) | included in -02-live.bats |
| SPOKE-05 | Hub-side Kustomization YAMLs exist with required spec fields | static | check files in `clusters/hub-flux/spokes/`; bats greps for `spec.path:` + `spec.kubeConfig.secretRef.{name,key}` | ❌ Wave 0 |
| SPOKE-05 | Kustomizations Ready=True post-push (negative-proof of correct cluster) | live destructive (post-push) | `bats tests/bats/register-spokes-02-live.bats -f 'inventory'` | ❌ Wave 0 |
| SPOKE-06 | CA-data extraction correct (single source: SA-token Secret) | in-script gate (D-13 step 2) + live test | the script's own `yq eval` parse + the auth roundtrip in -02-live.bats | included in -02-live.bats |

### Sampling Rate

- **Per task commit:** `bats tests/bats/register-spokes-01-static.bats` — pure static greps, runs in <1s, catches 80% of regression risk (filename/sentinel/literal drift).
- **Per script run (in-script):** D-13 4-gate verification (presence + decode + auth roundtrip + node-name negative-proof) — catches the credential-layer fault modes BEFORE the user pushes.
- **Per phase gate (live destructive, post-push):** `KARYON_LIVE_TESTS=1 KARYON_LIVE_TESTS_DESTRUCTIVE=1 bats tests/bats/register-spokes-02-live.bats` — catches the reconciliation-layer fault modes (.status.inventory contents, Ready=True, cross-cluster falsifier).

### Wave 0 Gaps

- [ ] `tests/bats/register-spokes-01-static.bats` — static contract for the script + manifest files (filename, RBAC names, `value.yaml` key literal in 4+ places, sentinel `# KARYON SPOKES MOUNT`, no auto-push grep, no `set -x`, no token-funneling helpers, `set -euo pipefail`)
- [ ] `tests/bats/register-spokes-02-live.bats` — live/destructive contract: `<spoke>-kubeconfig` Secret with `value.yaml` key exists on hub; node-name negative-proof reaches expected node from inside kustomize-controller pod; `flux get kustomization <spoke>` Ready=True; `.status.inventory` contains `<ns>_karyon-spoke-id__ConfigMap` regex; cross-cluster falsifier (`karyon-spoke-id` ConfigMap exists ONLY on the targeted spoke, NOT on hub)
- No new framework install needed — bats already in use from Phase 1/2/3.
- No shared fixture additions needed — `test_helper.bash` already exposes `require_live`, `require_live_destructive`, `REPO_ROOT`, `SCRIPTS_DIR`.

## Security Domain

> Phase 4 has direct security implications: kubeconfigs containing bearer tokens with cluster-admin permissions on remote clusters. Required per project's public-repo posture (PROJECT.md).

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | yes | Bearer-token auth (legacy SA-token Secret); indefinite lifetime acceptable per PROJECT.md Phase-4 key decision (lab scope) |
| V3 Session Management | partially | Token does not expire; equivalent to a session that doesn't time out. Mitigation: lab-scope risk acceptance documented in PROJECT.md. |
| V4 Access Control | yes | Cluster-admin ClusterRoleBinding per spoke per REQ-SPOKE-01. Namespace-scoped narrowing is v2 (REQUIREMENTS.md). |
| V5 Input Validation | yes | The kubeconfig YAML is generated by us, never user input. Bats static test asserts the heredoc structure to catch tampering. |
| V6 Cryptography | yes | TLS to spoke apiservers — CA-data extracted from spoke's SA-token Secret (same source as the cluster's signing CA). NEVER hand-roll. |
| V8 Data Protection | yes | Bearer tokens NEVER committed (D-04). Hub Secrets applied imperatively, not git-tracked. |
| V14 Configuration | yes | `spec.kubeConfig.secretRef.key: value.yaml` set explicitly (Pitfall 2) — no reliance on default key behavior. |

### Known Threat Patterns for {flux v2 hub-spoke + k3d local lab}

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Bearer token leak via shell tracing | Information Disclosure | `set -euo pipefail` (NEVER `-x`); ban echo/printf/info/warn/fail/pass/tee of `$TOKEN`/`$KUBECONFIG_YAML`; bats static test grep |
| Bearer token leak via committed file | Information Disclosure | Hub Secret applied imperatively only (D-04); `clusters/**/<spoke>-kubeconfig.yaml` paths NEVER created |
| Silent misroute via `spec.kubeConfig` omission (REAL P18) | Tampering / Spoofing | Always include `spec.kubeConfig.secretRef.{name,key}` in spoke Kustomization YAMLs; bats static test pins the field |
| Silent misroute via wrong server URL in kubeconfig | Tampering / Spoofing | Node-name negative-proof in D-13 step 4 — proves the kubeconfig actually targets the spoke |
| TokenRequest privilege escalation (n/a — not used) | EoP | Lab uses legacy Secret-backed SA-token (PROJECT.md Phase-4 key decision); no TokenRequest exposure |
| MITM via skipped TLS validation in probe | Tampering | Acceptable risk: the in-pod probe uses busybox-wget which can't validate TLS. Mitigated by D-10's single-source CA extraction (token + CA from same atomic Secret population) |
| Stolen kubeconfig Secret on hub-flux | EoP | Hub access already requires cluster-admin on hub; if attacker has that, the spoke cluster-admins are equivalent. Lab scope: no adversarial isolation between hub and spokes. |
| Stale Secret after spoke recreation | Data drift | Phase 4 idempotent rerun re-extracts token + CA after `task delete-clusters && task create-clusters`; old hub Secret content gets replaced via `kubectl apply -f -` |

**Public-repo posture defense:**
- Hub-side `<spoke>-kubeconfig` Secrets contain bearer tokens. Phase 4 D-04 codifies "imperative apply only, never git-tracked" — verified by bats static test grep `git push` in script body, and by `gitleaks` (Phase 6 REPO-04, lands before first push).
- The script's stdout NEVER prints the token (D-11 inheritance from Phase 3) — bats static test grep `echo.*TOKEN`, `printf.*TOKEN`, `info.*TOKEN`, etc.
- `.gitignore` already excludes `.env` (Phase 1 D-12); Phase 4 doesn't read `.env`, so no widening needed.

## Sources

### Primary (HIGH confidence — verified empirically against live k3d clusters 2026-04-27)

- **Live cluster probes 2026-04-27** — full transcript embedded in research session above. All major claims (D-14 image lacks kubectl, default key both `value` and `value.yaml`, inventory ID format, P18 actually triggered by missing `spec.kubeConfig` block, SA-token Secret population latency <200ms, `kubectl create secret --from-file=value.yaml=/dev/stdin` correct behavior, `kubectl kustomize` accepts `../spokes` parent reference, busybox-wget supports `--header` and `--no-check-certificate` but NOT `--ca-certificate`) — empirical.
- **`kubectl explain kustomization.spec.kubeConfig.secretRef`** (Flux v1, kustomize-controller v1.8.4) — `key` field is optional; required field is `name`; defaults documented as "implementation-specific default key".
- **`kubectl explain kustomization.status.inventory.entries`** — id format documented as `<namespace>_<name>_<group>_<kind>` directly from CRD schema.
- **`gotk-sync.yaml` and `kustomization.yaml`** in `clusters/hub-flux/flux-system/` — bootstrap-managed shape verified by direct file read.

### Secondary (MEDIUM confidence — current 2026 docs cited)

- [Flux Kustomization | fluxcd.io](https://fluxcd.io/flux/components/kustomize/kustomizations/) — official spec for `spec.kubeConfig`, default keys, fallback semantics, inventory format. Cross-checked against live behavior.
- [kustomize-controller/docs/spec/v1/kustomizations.md | github.com/fluxcd](https://github.com/fluxcd/kustomize-controller/blob/main/docs/spec/v1/kustomizations.md) — canonical CRD spec, inventory ID format with examples.
- [Managing Service Accounts | kubernetes.io](https://kubernetes.io/docs/reference/access-authn-authz/service-accounts-admin/) — annotation key (`kubernetes.io/service-account.name` singular), legacy Secret-based token semantics, indefinite lifetime confirmation.
- [Service Account Tokens in Kubernetes v1.24 | D2iQ Engineering Blog](https://eng.d2iq.com/blog/service-account-tokens-in-kubernetes-v1.24/) — context for the LegacyServiceAccountTokenNoAutoGeneration feature gate transition.
- [Flux v2.8.6 release notes | github.com/fluxcd/flux2](https://github.com/fluxcd/flux2/releases/tag/v2.8.6) — bundled kustomize-controller v1.8.4, no breaking changes to spec.kubeConfig.
- [bound-service-account-tokens KEP | github.com/kubernetes/enhancements](https://github.com/kubernetes/enhancements/blob/master/keps/sig-auth/1205-bound-service-account-tokens/README.md) — TokenRequest API context for the rejected-alternative rationale.
- [Support specifying a Secret key containing a kubeconfig — fluxcd/kustomize-controller#613](https://github.com/fluxcd/kustomize-controller/issues/613) — context for how the `key` field was added to the CRD.

### Tertiary (LOW confidence — fallback patterns, not load-bearing)

- [Deploy with Flux | vcluster docs](https://www.vcluster.com/docs/vcluster/third-party-integrations/git-operations/flux) — third-party guide; pattern-confirming for hub-spoke.
- [Tenants GitOps with Flux | Capsule docs](https://projectcapsule.dev/docs/guides/use-fluxcd/) — multi-tenant Flux pattern reference.

## Metadata

**Confidence breakdown:**

- Standard stack: HIGH — all dependencies pre-pinned in `.tool-versions`, all CLI behaviors verified live.
- Architecture (kubeconfig + RBAC + spec.kubeConfig contract): HIGH — verified by direct CRD inspection + live tests against a working three-cluster k3d topology.
- Pitfalls: HIGH — Pitfall 1 (orphan Secret deletion), Pitfall 2 (wrong-key vs missing-block), Pitfall 3 (kustomize-controller image lacks kubectl), Pitfall 7 (load-restrictor) all verified live; Pitfalls 4 and 5 inherited from Phase 3 verified history.
- D-14 adjustment: HIGH — image tooling fully enumerated by `ls /usr/local/bin /usr/bin` inside the live pod; wget-based replacement verified to work end-to-end (auth roundtrip + node-name probe both succeed against spoke-ml).
- P18 threat model adjustment: HIGH — empirically tested 4 distinct misrouting scenarios on the live cluster.
- Inventory ID format: HIGH — verified by parsing real `.status.inventory.entries[].id` from the live `flux-system` Kustomization on hub.
- Negative claims (e.g., "image does NOT ship kubectl"): HIGH — direct `ls` + `which kubectl` inside the pod confirmed.

**Research date:** 2026-04-27
**Valid until:** 30 days for the Flux + kustomize-controller behaviors (stable v1 CRD, Flux on a patch-release line); 60 days for Kubernetes legacy SA-token Secret behavior (stable since 1.24); shorter if Flux 2.9 ships during this window — the kustomize-controller image tooling layer would be the most likely thing to change.

---

*Phase: 04-spoke-registration*
*Researched: 2026-04-27*
*Researcher: gsd-research-phase agent*
*Live cluster state at research time: hub-flux + spoke-ml + spoke-apps all Ready on k8s-net (172.30.0.0/16); flux-system on hub-flux with 4/4 controllers Ready*
