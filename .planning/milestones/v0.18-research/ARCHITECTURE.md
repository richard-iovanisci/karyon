# Architecture Research

**Domain:** Local hub-spoke Flux multi-cluster lab on k3d (WSL2 + Docker + shared Docker network), with one GPU-capable spoke.
**Researched:** 2026-04-22
**Confidence:** HIGH on Flux patterns, Dockerfile shape, ServiceAccount recipes; MEDIUM on cross-cluster Docker-DNS semantics (documented for single-cluster, inferred-but-widely-practiced for shared-network multi-cluster); MEDIUM on `task fix-dns` being the right 2026-era workaround (newer CoreDNS reload PRs exist but no clean single-flag replacement is shipped).

---

## Standard Architecture

### System Overview — the three clusters, one network

```
┌──────────────────────────── WSL2 Ubuntu 24.04 ─────────────────────────────┐
│                                                                             │
│   ┌────────────────────────── docker bridge: k8s-net ────────────────────┐  │
│   │                                                                      │  │
│   │   ┌───────────────────── k3d cluster: hub-flux ──────────────────┐   │  │
│   │   │  containers:                                                 │   │  │
│   │   │    k3d-hub-flux-server-0   (kubeapi :6443 → host :6443)      │   │  │
│   │   │    k3d-hub-flux-serverlb                                     │   │  │
│   │   │  workloads:                                                  │   │  │
│   │   │    flux-system ns: source-controller, kustomize-controller,  │   │  │
│   │   │                    helm-controller, notification-controller  │   │  │
│   │   │    flux-system ns Secrets:                                   │   │  │
│   │   │      - flux-system           (bootstrap PAT)                 │   │  │
│   │   │      - spoke-ml-kubeconfig   (key: value.yaml)               │   │  │
│   │   │      - spoke-apps-kubeconfig (key: value.yaml)               │   │  │
│   │   └─────────────┬───────────────────────┬────────────────────────┘   │  │
│   │                 │ spec.kubeConfig      │ spec.kubeConfig             │  │
│   │                 │ secretRef            │ secretRef                   │  │
│   │                 ▼                       ▼                            │  │
│   │   ┌─── k3d cluster: spoke-ml ───┐  ┌── k3d cluster: spoke-apps ──┐   │  │
│   │   │  k3d-spoke-ml-server-0      │  │  k3d-spoke-apps-server-0    │   │  │
│   │   │  (kubeapi :6443 → :6444)    │  │  (kubeapi :6443 → :6445)    │   │  │
│   │   │  image: custom k3s+CUDA     │  │  image: rancher/k3s         │   │  │
│   │   │  runtime: nvidia            │  │                             │   │  │
│   │   │  nvidia-device-plugin DS    │  │                             │   │  │
│   │   │  SA: flux-reconciler        │  │  SA: flux-reconciler        │   │  │
│   │   │  CRB: cluster-admin         │  │  CRB: cluster-admin         │   │  │
│   │   │  GPU workloads:             │  │  App workloads:             │   │  │
│   │   │    gpu-smoke-test pod       │  │    podinfo                  │   │  │
│   │   └─────────────────────────────┘  └─────────────────────────────┘   │  │
│   │                                                                      │  │
│   │   Docker embedded DNS (127.0.0.11 inside every container):           │  │
│   │     k3d-hub-flux-server-0    → 172.x.x.x                             │  │
│   │     k3d-spoke-ml-server-0    → 172.x.x.x   ◄── hub pods resolve this │  │
│   │     k3d-spoke-apps-server-0  → 172.x.x.x   ◄── hub pods resolve this │  │
│   └──────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│   ▲ kubeconfig contexts on host point at 127.0.0.1:6443/6444/6445           │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

 ▲ Repo-side:  github.com/$OWNER/$REPO      ◄── flux-system GitRepository polls this
   ├── clusters/hub-flux/
   │   ├── flux-system/            (bootstrap-managed; gotk-components, gotk-sync, kustomization)
   │   └── spokes/                 (hand-authored; Kustomizations targeting kubeconfig Secrets)
   ├── clusters/spoke-ml/          (reconciled by hub Flux via spec.kubeConfig)
   └── clusters/spoke-apps/        (reconciled by hub Flux via spec.kubeConfig)
```

### Component Responsibilities

| Component | Responsibility | Typical Implementation |
|-----------|----------------|------------------------|
| `hub-flux` cluster | Runs Flux controllers, holds all spoke kubeconfig Secrets, is the only cluster pointed at Git | k3d + `rancher/k3s:v1.34.6-k3s1`, stock Flux v2 via `flux bootstrap github` |
| `spoke-ml` cluster | Runs GPU workloads; receives manifests from hub via kube-apiserver | k3d + custom `k3s+CUDA` image, `--gpus all`, NVIDIA device plugin DaemonSet |
| `spoke-apps` cluster | Runs general apps; receives manifests from hub via kube-apiserver | k3d + stock `rancher/k3s:v1.34.6-k3s1` |
| Shared docker network `k8s-net` | Provides inter-cluster DNS (container-name) and IP connectivity | User-defined bridge network; Docker embedded DNS at 127.0.0.11 |
| `flux-reconciler` SA on spokes | Cluster-admin identity hub uses when reconciling INTO spoke | `ServiceAccount` + `ClusterRoleBinding`(cluster-admin) + explicit `Secret` (type `kubernetes.io/service-account-token`) |
| `<spoke>-kubeconfig` Secret on hub | Credentials bundle (server URL + CA + token) hub's kustomize-controller loads | `Secret` in `flux-system` ns, stringData key `value.yaml` |
| Hub `Kustomization` (one per spoke) | Tells Flux "reconcile path X from the GitRepository INTO the cluster whose kubeconfig is in Secret Y" | `kustomize.toolkit.fluxcd.io/v1` with `spec.kubeConfig.secretRef` |

---

## Recommended Project Structure

This is the layout that matches both the starter's directory intent AND the canonical [`fluxcd/flux2-hub-spoke-example`](https://github.com/fluxcd/flux2-hub-spoke-example) / [Stefan Prodan's multi-cluster architecture blog](https://stefanprodan.com/blog/2024/fluxcd-multi-cluster-architecture/).

```
karyon/
├── clusters/                              ◄── bootstrap points at clusters/hub-flux
│   ├── hub-flux/
│   │   ├── flux-system/                   ◄── BOOTSTRAP-MANAGED — do not hand-edit
│   │   │   ├── gotk-components.yaml       (generated by `flux bootstrap`)
│   │   │   ├── gotk-sync.yaml             (generated: GitRepository + root Kustomization)
│   │   │   └── kustomization.yaml         (generated: references the two above)
│   │   └── spokes/                        ◄── HAND-AUTHORED
│   │       ├── kustomization.yaml         (aggregates the two spoke Kustomizations)
│   │       ├── spoke-ml.yaml              (Flux Kustomization w/ spec.kubeConfig → spoke-ml-kubeconfig)
│   │       └── spoke-apps.yaml            (Flux Kustomization w/ spec.kubeConfig → spoke-apps-kubeconfig)
│   ├── spoke-ml/                          ◄── reconciled INTO spoke-ml by hub Flux
│   │   ├── infrastructure/
│   │   │   ├── kustomization.yaml
│   │   │   ├── runtime-class-nvidia.yaml  (RuntimeClass `nvidia`)
│   │   │   └── nvidia-device-plugin.yaml  (DaemonSet)
│   │   └── apps/
│   │       └── gpu-smoke-test.yaml
│   └── spoke-apps/                        ◄── reconciled INTO spoke-apps by hub Flux
│       ├── infrastructure/
│       └── apps/
│           └── podinfo.yaml
├── images/
│   ├── Dockerfile.k3s-cuda                (FROM nvcr.io/nvidia/cuda:12.8+; k3s layered in)
│   └── device-plugin-daemonset.yaml       (baked-in fallback; normally reconciled by Flux)
├── scripts/
│   ├── preflight.sh
│   ├── create-clusters.sh
│   ├── bootstrap-flux.sh
│   ├── register-spokes-for-flux.sh
│   ├── fix-coredns.sh                     (stop/start hub to refresh NodeHosts)
│   └── health-check.sh
├── Taskfile.yml
├── .env.example
└── docs/
    └── adr/
```

### Structure Rationale

- **`clusters/hub-flux/flux-system/` is inviolate:** `flux bootstrap github --path=clusters/hub-flux` writes three files there and wires itself to reconcile from that path. Any hand-edit is reverted on the next reconcile. This is documented behavior, not speculation.
- **`clusters/hub-flux/spokes/` is separate from `flux-system/`:** Keeping spoke-targeting Kustomizations OUT of `flux-system/` (a) survives future `flux bootstrap` re-runs and (b) makes it obvious what is bootstrap-generated vs. author-written. Because `clusters/hub-flux/` is the root reconcile path, the `spokes/` sibling directory is automatically picked up by the root Kustomization's recursive scan of that path.
- **`clusters/spoke-ml/` and `clusters/spoke-apps/` hold NO Flux controller manifests:** those clusters don't run Flux. These directories hold only the workload manifests Flux will project INTO each spoke via `spec.kubeConfig`. Splitting `infrastructure/` vs `apps/` follows the [flux2-kustomize-helm-example](https://github.com/fluxcd/flux2-kustomize-helm-example) / Prodan multi-cluster pattern and enables dependency ordering (`dependsOn: [infrastructure]`).
- **`images/` is build artifact source** — the CUDA Dockerfile and a copy-of-record of the device-plugin DaemonSet baked into the custom k3s image (per k3d's CUDA guide — the DaemonSet is installed at `/var/lib/rancher/k3s/server/manifests/` in the image so that it's present immediately on cluster creation, BEFORE Flux is reconciling into the spoke). Flux can then take over managing it idempotently.

---

## Architectural Patterns

### Pattern 1: Hub-only Flux control plane with `spec.kubeConfig` reconciliation

**What:** Only the hub cluster runs Flux controllers. Every workload destined for a spoke is described as a Flux `Kustomization` (or `HelmRelease`) on the hub with a `spec.kubeConfig.secretRef` pointing to a `Secret` that contains a kubeconfig for the spoke. The kustomize-controller on the hub applies the rendered manifests to the spoke's API server — the spoke never learns about Git.

**When to use:** Small (2–3) spoke count, trust in a central hub is acceptable, operational overhead of per-cluster Flux is undesirable.

**Trade-offs:**
- (+) One source of truth, one reconcile controller, one PAT to manage.
- (+) Simpler teardown (`task destroy` doesn't need to de-register anything Git-side).
- (−) Hub is SPoF for continuous delivery; spoke drift cannot be self-healed without hub reachability.
- (−) No ArgoCD-style cluster generator — each spoke requires an explicit hand-authored Kustomization. Acceptable at 2–3 spokes (per ADR-003); painful at 10+.

**Minimal working hub `Kustomization` targeting a spoke** — this is the canonical shape per [Flux kustomize-controller v1 spec](https://github.com/fluxcd/kustomize-controller/blob/main/docs/spec/v1/kustomizations.md):

```yaml
# clusters/hub-flux/spokes/spoke-ml.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: spoke-ml
  namespace: flux-system
spec:
  interval: 10m
  path: ./clusters/spoke-ml
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system         # the bootstrap-created GitRepository
  kubeConfig:
    secretRef:
      name: spoke-ml-kubeconfig   # must live in the SAME namespace (flux-system)
      # key: value.yaml           # OPTIONAL — defaults to 'value' or 'value.yaml'
  # Optional — order workloads behind infra:
  # dependsOn:
  #   - name: spoke-ml-infrastructure
```

**On decryption / SOPS for the kubeconfig Secret itself:** `spec.decryption` on a Kustomization decrypts manifests inside its `path` — it does NOT apply to the `kubeConfig.secretRef` Secret. That Secret must already exist, plaintext, in the cluster. Three options:

1. **Plain imperative creation** (starter's implied default, best for v1): script `register-spokes-for-flux.sh` calls `kubectl create secret generic spoke-ml-kubeconfig --from-file=value.yaml=...`. The token inside expires only if you rotate it; fine for a lab.
2. **SOPS-encrypted Secret manifest committed to git**, decrypted by kustomize-controller when reconciling its parent Kustomization. Works, but bootstraps a chicken-and-egg (kustomize-controller can't target a spoke until the decrypted Secret exists on the hub). Defer to a later milestone.
3. **External-Secrets Operator or sealed-secrets**. Out of scope for v1 per PROJECT.md's explicit Out-of-Scope list.

→ **Recommendation: Option 1 for v1.** Store token in a `kubernetes.io/service-account-token` Secret on the spoke (never-expiring legacy token — see Pattern 3), build the kubeconfig imperatively, `kubectl apply` it to `flux-system` on the hub.

### Pattern 2: Spoke kubeconfig Secret format (definitive)

**What:** The Secret that `spec.kubeConfig.secretRef` points to must be of type `Opaque`, in the same namespace as the Kustomization (`flux-system`), with its kubeconfig payload under the key `value` OR `value.yaml`.

**Verified facts (HIGH confidence — from the official kustomize-controller v1 spec):**

- **Default key name:** "the KubeConfig bytes will be loaded from the `.secretRef.key` key (**default: `value` or `value.yaml`**)". Either works out-of-the-box. The starter commits to `value.yaml` — that's valid and is the form shown in the Flux docs' own example. **Keep `value.yaml`.**
- **Server URL in the kubeconfig:** must point at an address reachable from kustomize-controller's Pod network namespace. For our topology that means `https://k3d-<spoke>-server-0:6443` — the in-network Docker DNS name, NOT the host-published `127.0.0.1:6444/6445`. The host-side mappings are only reachable from the WSL host; they are unreachable from inside a hub pod.
- **CA-data handling:** `certificate-authority-data` is a base64-encoded PEM of the spoke's server CA cert. It must be valid for the `server:` address, so **the spoke must be created with `--tls-san k3d-<name>-server-0`** (the starter already encodes this) so that its kube-apiserver's serving cert includes that hostname as a SAN. Without this SAN, TLS verification from the hub will fail.
- **Self-contained requirement:** "The KubeConfig should be self-contained and not rely on binaries, the environment, or credential files from the controller Pod." No `exec` auth plugins, no `cmd-path`. Static token only.

**Minimal Secret YAML** (the kubeconfig is literally embedded as `stringData.value.yaml`):

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: spoke-ml-kubeconfig
  namespace: flux-system
type: Opaque
stringData:
  value.yaml: |
    apiVersion: v1
    kind: Config
    current-context: spoke-ml
    clusters:
      - name: spoke-ml
        cluster:
          server: https://k3d-spoke-ml-server-0:6443
          certificate-authority-data: <base64 spoke CA>
    users:
      - name: flux-reconciler
        user:
          token: <service-account-token>
    contexts:
      - name: spoke-ml
        context:
          cluster: spoke-ml
          user: flux-reconciler
```

### Pattern 3: Remote cluster ServiceAccount + long-lived token

**What:** On each spoke, create a `ServiceAccount` (namespace `kube-system`), bind it cluster-admin, and — because Kubernetes 1.24+ no longer auto-generates Secrets for ServiceAccounts — explicitly create a `Secret` of type `kubernetes.io/service-account-token` annotated with the SA's name. The token controller populates that Secret with a non-expiring token the hub can embed in the kubeconfig.

**Why not TokenRequest (`kubectl create token`) for this lab:**

| Criterion | Secret-backed legacy token | TokenRequest API (`kubectl create token`) |
|---|---|---|
| Lifetime | Indefinite (until Secret deleted) | Bound; default 1h, max typically 48h–1y depending on apiserver flags |
| Rotation burden | None | Must re-issue + re-write hub Secret before expiry |
| k3s v1.34 availability | **Fully supported** (feature stable GA since 1.27) | Supported |
| Lab rebuild compatibility | `task rebuild` runs once; token lives forever with cluster | Expires during idle periods, breaks next reconcile without re-run |

→ **Recommendation (HIGH confidence):** For this lab, use the legacy Secret-backed token. It is explicitly still supported by the official Kubernetes service-accounts-admin docs (the deprecation applied only to *auto-generation*, not to the mechanism itself), works cleanly on k3s v1.34.6, and removes token-expiry as a lab failure mode. When v2 needs rotation or tighter security posture, swap to TokenRequest or external-secrets.

**Canonical recipe** (run once per spoke, context-switched to the spoke):

```yaml
# applied to spoke-ml (and spoke-apps)
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: flux-reconciler
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: flux-reconciler
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: flux-reconciler
    namespace: kube-system
---
apiVersion: v1
kind: Secret
metadata:
  name: flux-reconciler-token
  namespace: kube-system
  annotations:
    kubernetes.io/service-account.name: flux-reconciler
type: kubernetes.io/service-account-token
# The token controller populates data.token and data.ca.crt on its own.
```

Then on the hub, extract and assemble:

```bash
SPOKE=spoke-ml
SPOKE_SERVER="https://k3d-${SPOKE}-server-0:6443"

# CA is already in the SA secret — no round-trip through kubeconfig needed
SPOKE_CA=$(kubectl --context k3d-${SPOKE} -n kube-system \
  get secret flux-reconciler-token -o jsonpath='{.data.ca\.crt}')
SPOKE_TOKEN=$(kubectl --context k3d-${SPOKE} -n kube-system \
  get secret flux-reconciler-token -o jsonpath='{.data.token}' | base64 -d)

kubectl --context k3d-hub-flux -n flux-system create secret generic \
  ${SPOKE}-kubeconfig \
  --from-file=value.yaml=<(cat <<EOF
apiVersion: v1
kind: Config
current-context: ${SPOKE}
clusters:
  - name: ${SPOKE}
    cluster:
      server: ${SPOKE_SERVER}
      certificate-authority-data: ${SPOKE_CA}
users:
  - name: flux-reconciler
    user:
      token: ${SPOKE_TOKEN}
contexts:
  - name: ${SPOKE}
    context:
      cluster: ${SPOKE}
      user: flux-reconciler
EOF
) --dry-run=client -o yaml | kubectl --context k3d-hub-flux apply -f -
```

### Pattern 4: Custom `k3s + CUDA` image for GPU spoke

**What:** k3s's official image (`rancher/k3s`) is Alpine-based; NVIDIA's container toolkit is not supported on Alpine. The canonical pattern — straight from [k3d's own CUDA guide](https://k3d.io/v5.8.3/usage/advanced/cuda/) — is a **two-stage build whose final base is `nvcr.io/nvidia/cuda:<tag>` (Ubuntu)** with the k3s binary + rootfs copied in from `rancher/k3s` as the build stage. This inverts the "obvious" direction but is required because CUDA userspace + nvidia-container-toolkit need glibc.

**Dockerfile skeleton** (pin CUDA_TAG to 12.8+ for RTX 5090 sm_120):

```dockerfile
ARG K3S_TAG="v1.34.6-k3s1"
ARG CUDA_TAG="12.8.0-base-ubuntu22.04"

FROM rancher/k3s:$K3S_TAG as k3s
FROM nvcr.io/nvidia/cuda:$CUDA_TAG

RUN apt-get update && apt-get install -y curl \
 && curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
      gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
 && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
      sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
      > /etc/apt/sources.list.d/nvidia-container-toolkit.list \
 && apt-get update && apt-get install -y nvidia-container-toolkit \
 && nvidia-ctk runtime configure --runtime=containerd

COPY --from=k3s / / --exclude=/bin
COPY --from=k3s /bin /bin

# Baked-in fallback for device plugin — ensures GPU scheduling works even before Flux reconciles
COPY device-plugin-daemonset.yaml /var/lib/rancher/k3s/server/manifests/nvidia-device-plugin-daemonset.yaml

VOLUME /var/lib/kubelet
VOLUME /var/lib/rancher/k3s
VOLUME /var/lib/cni
VOLUME /var/log
ENV PATH="$PATH:/bin/aux"
ENTRYPOINT ["/bin/k3s"]
CMD ["agent"]
```

**`RuntimeClass nvidia` is mandatory.** Pods that need GPU MUST include `runtimeClassName: nvidia` in their spec, or the nvidia-container-runtime hook won't fire and `nvidia-smi` will fail inside the container. This applies to both the device plugin DaemonSet and the GPU smoke-test pod.

### Pattern 5: NVIDIA device plugin placement — "baked-in + Flux-managed"

**What:** Two complementary mechanisms, not a choice:
1. **Baked into the custom image** at `/var/lib/rancher/k3s/server/manifests/nvidia-device-plugin-daemonset.yaml`. k3s's built-in manifest-auto-deploy watcher applies anything in that directory at cluster start. This guarantees GPU scheduling works from the moment `k3d cluster create` completes — before hub Flux has even started reconciling.
2. **Reconciled by Flux** from `clusters/spoke-ml/infrastructure/nvidia-device-plugin.yaml`. Once hub Flux comes online, the DaemonSet becomes GitOps-managed and can be updated via PR.

Because k3s's auto-deploy-manifests and Flux-managed resources use the same API objects, the second pass simply adopts/no-ops the first. The baked-in copy is insurance against "cluster up but Flux not ready yet."

→ **Recommendation:** Do both. Author the DaemonSet + RuntimeClass under `clusters/spoke-ml/infrastructure/` (for GitOps management) AND copy that exact same file into `images/device-plugin-daemonset.yaml` for the Dockerfile's `COPY` line (for cold-start).

**Device plugin image:** latest stable at research time is `nvcr.io/nvidia/k8s-device-plugin:v0.17.x` / `v0.18.0` — pin to a specific v0.17.x or v0.18.x tag, not `latest`.

### Pattern 6: Docker embedded DNS across `k8s-net` — the load-bearing assumption

**What:** Docker Engine runs an embedded DNS server at `127.0.0.11` inside every container attached to a user-defined bridge network. That DNS server resolves **every other container's `--name` on the same user-defined network**, regardless of which "parent" (k3d cluster) created the container.

**Evidence (verified):**
- [Docker Engine bridge-driver docs](https://docs.docker.com/engine/network/drivers/bridge/): "User-defined bridges provide automatic DNS resolution between containers."
- [k3d v5.8.3 networking design](https://k3d.io/v5.8.3/design/networking/): "k3d injects entries to the NodeHosts to enable Pods in the cluster to resolve the names of other containers in the same docker network (cluster network)."

That second sentence is the hinge: k3d's CoreDNS NodeHosts plugin is populated from Docker's view of the network. When `hub-flux`, `spoke-ml`, and `spoke-apps` all share `--network k8s-net`, every container sees every other container's name resolvable.

**Verified end-to-end chain for the starter's topology:**
1. Docker Engine embedded DNS resolves `k3d-spoke-ml-server-0` for the hub cluster's containers (including kustomize-controller's pod, because pod traffic egresses through the node's network namespace when destination is outside the pod CIDR).
2. k3d's CoreDNS NodeHosts on the hub contains an entry for every `k3d-*` container on `k8s-net` — so even if pod DNS doesn't reach Docker's 127.0.0.11 directly, it resolves via CoreDNS.
3. TLS verifies because spokes were created with `--tls-san k3d-<name>-server-0`.
4. Auth succeeds because the embedded ServiceAccount token has cluster-admin via the CRB.

**Known failure mode — CoreDNS NodeHosts goes stale:** [k3d#1009](https://github.com/k3d-io/k3d/issues/1009) and [k3d#1112](https://github.com/k3d-io/k3d/issues/1112) document that the NodeHosts entries in CoreDNS ConfigMap can lose sync after Docker daemon restarts, WSL resume, or cluster-node topology changes. Symptom: hub Flux Kustomizations start failing with `no such host` for `k3d-spoke-ml-server-0`.

**→ The starter's `task fix-dns` (`k3d cluster stop hub-flux && k3d cluster start hub-flux`) IS the correct 2026-era workaround.** There is no shipped single-flag alternative. `kubectl rollout restart deployment/coredns -n kube-system` is a lighter option that works in some variants of the bug but NOT all (because the ConfigMap itself has gone stale, not just CoreDNS's cache). Stop/start triggers k3d's per-cluster entrypoint hooks that regenerate NodeHosts from live Docker state — that's the reliable path.

→ **Confidence: MEDIUM.** The `K3D_FIX_DNS` env var is a different, overlapping fix targeting WSL2 systemd-resolved quirks ([k3d#1515](https://github.com/k3d-io/k3d/issues/1515) shows it actively breaks external DNS when enabled); do NOT set it. The stop/start pattern is the least-bad known workaround.

---

## Data Flow

### Flow A — Flux bootstrap (one-time on fresh hub)

```
Developer runs `task bootstrap-flux`
    │
    │ reads GITHUB_OWNER / GITHUB_REPO / GITHUB_TOKEN from .env
    ▼
flux bootstrap github --owner=... --repository=... --path=clusters/hub-flux
    │
    ├── (1) Creates/uses GitHub repo
    ├── (2) Generates clusters/hub-flux/flux-system/{gotk-components,gotk-sync,kustomization}.yaml, commits, pushes
    ├── (3) Applies gotk-components.yaml to hub cluster → flux-system namespace + controllers + CRDs
    ├── (4) Creates Secret flux-system/flux-system (contains PAT for Git access)
    └── (5) Applies gotk-sync.yaml:
              GitRepository/flux-system  → watches the branch
              Kustomization/flux-system  → path=./clusters/hub-flux, prune=true
    │
    ▼
Flux now self-managing. From here, every change in clusters/hub-flux/** is reconciled back
in. Including clusters/hub-flux/spokes/*.yaml — the hand-authored spoke Kustomizations.
```

### Flow B — Hub → spoke reconciliation (steady state)

```
Git commit pushed to main
    │
    ▼
source-controller on hub polls GitRepository (interval 1m by default)
    │ fetches tarball, stores in internal storage
    ▼
kustomize-controller on hub reconciles Kustomization/spoke-ml
    │
    │ (a) reads Kustomization/spoke-ml  ← spec.kubeConfig.secretRef.name = spoke-ml-kubeconfig
    │ (b) reads Secret flux-system/spoke-ml-kubeconfig → extracts data["value.yaml"] = kubeconfig bytes
    │ (c) builds a client-go rest.Config from those bytes
    │     server: https://k3d-spoke-ml-server-0:6443
    │     ca:     (spoke CA)
    │     token:  (flux-reconciler SA token)
    │ (d) renders ./clusters/spoke-ml/ with kustomize → K8s manifests
    │ (e) applies manifests VIA the spoke's apiserver
    ▼
Pod on hub (kustomize-controller) → k3d-spoke-ml-server-0:6443 over k8s-net bridge
    │ [docker embedded DNS resolves the hostname]
    │ [TLS validates via --tls-san in spoke CA]
    │ [auth via bearer token → cluster-admin]
    ▼
Spoke apiserver applies the manifests. nvidia-device-plugin DaemonSet starts.
GPU smoke-test pod schedules with runtimeClassName: nvidia.
```

### Flow C — `task health-check` exact sequence

```
1. All clusters exist:           k3d cluster list --output json | jq len == 3
2. All nodes Ready:              for c in hub-flux spoke-ml spoke-apps:
                                   kubectl --context k3d-$c get nodes -o json |
                                     jq '.items[].status.conditions[]|select(.type=="Ready").status == "True"'
3. Flux controllers Ready:       kubectl --context k3d-hub-flux -n flux-system \
                                   wait --for=condition=Ready pod -l app.kubernetes.io/part-of=flux --timeout=2m
                                 flux --context k3d-hub-flux check
4. Flux Kustomizations Ready:    flux --context k3d-hub-flux get kustomizations -A
                                 # Expect: flux-system, spoke-ml, spoke-apps all "True"
5. Cross-cluster DNS resolves:   kubectl --context k3d-hub-flux -n flux-system exec \
                                   deploy/kustomize-controller -- \
                                   nslookup k3d-spoke-ml-server-0
                                 # Expect: answer in k8s-net subnet, NOT NXDOMAIN
6. Spokes actually reconciled:   kubectl --context k3d-spoke-ml get ns gpu-smoke
                                 kubectl --context k3d-spoke-apps get deploy -n podinfo podinfo
7. GPU present on spoke-ml:      kubectl --context k3d-spoke-ml get nodes -o json |
                                   jq '.items[].status.capacity."nvidia.com/gpu"' == "1"
8. Smoke-test proves GPU:        kubectl --context k3d-spoke-ml -n gpu-smoke logs job/nvidia-smi |
                                   grep -q "RTX 5090"
```

---

## Build Order (explicit dependencies)

This ordering is dependency-correct. Each step's prerequisites are named.

```
Step 0 ── preflight
          depends on: nothing
          verifies: WSL2, Docker, NVIDIA chain, tools, free ports, no residue
          output: exit 0 or actionable error
          │
          ▼
Step 1 ── Build custom k3s+CUDA image
          depends on: Docker running, NVIDIA container toolkit configured
          output: local docker image karyon/k3s-cuda:v1.34.6-k3s1-cuda-12.8.0-base-ubuntu22.04
          rationale: needed by Step 3 spoke-ml cluster create; long build → do early, cache across rebuilds
          │
          ├─── can run in parallel with Step 2 (Docker network creation)
          ▼
Step 2 ── Create docker network k8s-net
          depends on: Docker running
          output: user-defined bridge network exists
          rationale: ALL clusters attach here; embedded DNS works only on user-defined networks
          │
          ▼
Step 3 ── Create k3d clusters (hub-flux, spoke-ml, spoke-apps)
          depends on: k8s-net exists; custom k3s+CUDA image exists
          critical flags per cluster:
            --network k8s-net                              (shared DNS)
            --tls-san k3d-<name>-server-0                  (spoke CA validates against hostname)
            --k3s-arg --disable=traefik@server:0           (lab, avoid port squatting; optional)
            hub-flux:   --image rancher/k3s:v1.34.6-k3s1   --api-port 127.0.0.1:6443
            spoke-ml:   --image karyon/k3s-cuda:...        --api-port 127.0.0.1:6444  --gpus all
            spoke-apps: --image rancher/k3s:v1.34.6-k3s1   --api-port 127.0.0.1:6445
          output: three running clusters; spoke-ml already has the baked-in device-plugin DaemonSet
          │
          │ Hub cluster create and spoke cluster creates CAN be parallelized
          │ (different containers, no shared state beyond the network).
          ▼
Step 4 ── flux bootstrap github on hub
          depends on: hub-flux cluster up; GITHUB_TOKEN in env; clusters/hub-flux/spokes/*.yaml already committed
          output: flux-system namespace populated; self-managing GitOps active
          gotcha: bootstrap happens BEFORE step 5, but spoke Kustomizations under clusters/hub-flux/spokes/
                  will fail reconciliation until step 5 creates their Secret — this is expected and self-heals
          │
          │ MUST run sequentially — step 5 creates resources in hub's flux-system namespace,
          │ which didn't exist until step 4 finished.
          ▼
Step 5 ── Register spokes (SA + CRB + token Secret on spoke, kubeconfig Secret on hub)
          depends on: all three clusters up; hub's flux-system namespace exists
          per spoke (can parallelize across spokes):
            kubectl --context k3d-<spoke> apply -f flux-reconciler-sa.yaml
            kubectl --context k3d-<spoke> -n kube-system wait secret flux-reconciler-token
            extract ca.crt + token
            kubectl --context k3d-hub-flux -n flux-system apply kubeconfig Secret
          output: two Secrets on hub: spoke-ml-kubeconfig, spoke-apps-kubeconfig
          │
          ▼
Step 6 ── Deploy examples (automatic via Flux)
          depends on: step 5 Secrets exist; Flux reconciles the spoke Kustomizations
          NO explicit user action needed — Flux picks up the now-satisfied Kustomizations
          at the next interval (default 10m; force with `flux reconcile kustomization spoke-ml`)
          output: podinfo on spoke-apps; GPU smoke pod on spoke-ml
          │
          ▼
Step 7 ── Health check
          verifies everything above (see Flow C)
```

### Parallelization summary

| Steps | Can parallelize? | Why |
|-------|------------------|-----|
| 1 & 2 | Yes | Image build and network creation are independent |
| 3 (hub vs spokes) | Yes | Different containers, only share `k8s-net` which already exists |
| 5 (per spoke) | Yes | Per-spoke SA creation and hub-side Secret apply are independent per spoke |
| Everything else | No | Strict dependency chain |

Practical `Taskfile.yml` impact: `task create-clusters` can use `deps:` to express the 1+2 parallelism and fan-out spoke creation. `task register-spokes` can background per-spoke work and `wait`.

---

## Where Phases Split Naturally

Four natural phase boundaries emerge from the build-order dependencies and verification artifacts. **Recommend the roadmap align to these.**

### Phase boundary 1: Host → Clusters (end of Step 3)
*Artifact:* three healthy clusters on `k8s-net`, all nodes Ready, `kubectl --context` works for each. *Does NOT include Flux.* This is the "is my hardware + WSL + Docker + NVIDIA chain correct?" gate. Failing here means host-level issue, not a Kubernetes issue. Acceptance: all contexts respond, spoke-ml has `nvidia.com/gpu` capacity advertised, `docker network inspect k8s-net` shows all six k3d containers attached.

### Phase boundary 2: Clusters → Flux hub (end of Step 4)
*Artifact:* `flux-system` namespace populated on hub; `flux get kustomizations -A` shows `flux-system` Kustomization Ready. The repo is now self-managing. This separates "Flux bootstrap works" (depends only on hub + GitHub) from "cross-cluster reconciliation works" (depends on DNS, TLS, RBAC, tokens — many more failure modes).

### Phase boundary 3: Flux hub → Spoke registration (end of Step 5)
*Artifact:* two kubeconfig Secrets on hub, each verified by `kubectl --kubeconfig <(extract) get nodes` from a hub pod. **This is the highest-risk phase** — it's where DNS, TLS-SAN, CA-data, token format, and Secret key-name can all fail. Worth its own research pass and a dedicated smoke test before moving on.

### Phase boundary 4: Spoke registration → Workloads (end of Steps 6 + 7)
*Artifact:* `flux get kustomizations -A` all Ready; podinfo reachable on spoke-apps; `nvidia-smi` output visible from a pod on spoke-ml. This is where "end user workflow works" is proved.

→ **Suggested roadmap phase split:** one phase per boundary. Phase 3 (spoke registration) deserves deeper research / a validation script because it's where the hub-spoke architectural pattern literally succeeds or fails.

---

## Starter assumptions that research validates / contradicts

| Starter assumption | Research finding | Confidence |
|---|---|---|
| `https://k3d-<spoke>-server-0:6443` is correct server address | **CONFIRMED.** Docker embedded DNS + k3d CoreDNS NodeHosts both resolve this; k3s serves :6443 inside the container regardless of host-port mapping. | HIGH |
| Secret key name `value.yaml` is what Flux expects | **CONFIRMED.** Flux docs explicitly state default is `value` OR `value.yaml`. Either works; `value.yaml` is used in the official spec example. No change needed. | HIGH |
| `task fix-dns` via `k3d cluster stop/start` is necessary | **CONFIRMED as best-available workaround.** Known bug (k3d #1009, #1112) with no shipped fix as of v5.8.3. `kubectl rollout restart coredns` is insufficient because the ConfigMap itself goes stale. Do not use `K3D_FIX_DNS=1` — it breaks external DNS. | MEDIUM (high on "this is needed", medium on "nothing better shipped in 5.8+") |
| Hub-only Flux via `spec.kubeConfig` is clean | **CONFIRMED** by canonical `fluxcd/flux2-hub-spoke-example`. Stefan Prodan's 2024 multi-cluster post endorses the pattern for lab/dev-scale. | HIGH |
| CUDA base is the right base, with k3s layered in | **CONFIRMED.** Direct from official k3d CUDA guide. The inverse (k3s base + CUDA layered) does not work because k3s's Alpine base lacks glibc / apt. | HIGH |
| NVIDIA device plugin DaemonSet is sufficient (no GPU Operator) | **CONFIRMED.** Matches k3d's own documented approach. Operator is correctly scoped out for v1. | HIGH |
| Legacy Secret-backed SA tokens work on k3s v1.34 | **CONFIRMED.** `LegacyServiceAccountTokenNoAutoGeneration` GA'd in 1.27, but only the auto-generation changed — creating an explicit Secret of type `kubernetes.io/service-account-token` still works indefinitely. | HIGH |
| `k3s v1.34.6-k3s1` is Flux-compatible | **CONFIRMED** by absence of incompatibility reports + Flux v2's Kubernetes support matrix historically running 2 minor versions behind latest, which covers 1.34 in early 2026. Note: k3s v1.34 ships etcd 3.6 — not relevant for k3d single-server clusters but worth flagging if someone attempts HA later. | HIGH |
| Device plugin DaemonSet goes under `clusters/spoke-ml/infrastructure/` reconciled by hub | **REFINE.** Recommend ALSO baking it into the custom image at `/var/lib/rancher/k3s/server/manifests/` so GPU scheduling works from t=0 before Flux reconciliation. Hub-managed copy is redundant but idempotent, and provides GitOps lifecycle for updates. | HIGH |

---

## Scaling Considerations

The domain is a local lab, so "scale" is bounded by the dev machine. Relevant dimensions:

| Dimension | Current (3 clusters) | What breaks first | Mitigation |
|-----------|----------------------|-------------------|------------|
| Cluster count | 3 | Explicit hand-authored Kustomization per spoke (per ADR-003 trade-off) | Switch to Flux via per-spoke Flux install, or adopt ArgoCD ApplicationSet, or write a tiny generator that produces `clusters/hub-flux/spokes/<name>.yaml` |
| Memory (52 GB WSL pin) | ~4–6 GB idle all-in | Too many Flux HelmReleases with large charts | Reduce HelmRelease count; use Kustomize; `--disable=traefik,servicelb` on spokes |
| GPU count | 1 (RTX 5090) | GPU over-subscription across pods | NVIDIA time-slicing config in device plugin (out of scope v1) or MIG on supported GPUs |
| Token rotation | Never (legacy SA token) | Nothing breaks, but security drifts | Move to TokenRequest + external-secrets in v2 |
| CoreDNS NodeHosts staleness | Minor, recoverable | Hub pods can't resolve `k3d-*-server-0` after Docker restart | `task fix-dns` (documented); track upstream fix |

---

## Anti-Patterns

### Anti-Pattern 1: Using `host.k3d.internal` as the spoke server address

**What people do:** Put `server: https://host.k3d.internal:6444` in the spoke kubeconfig (using the host-published port).
**Why it's wrong:** `host.k3d.internal` resolves to the gateway IP of the docker network, not to the spoke. On hub pods, the traffic would hairpin out to the WSL host and try to come back — usually blocked by netfilter, always slower, and requires the spoke's kube-apiserver cert to include `host.k3d.internal` in SAN. Completely unnecessary overhead when containers on the same docker network can talk directly.
**Do this instead:** Use `https://k3d-<spoke>-server-0:6443` — direct container-to-container on `k8s-net`.

### Anti-Pattern 2: Installing Flux on every spoke too

**What people do:** Bootstrap Flux on each cluster "for consistency." Each spoke pulls the same repo with its own path.
**Why it's wrong:** Triples controller footprint, triples failure modes, adds 3× GitHub PATs (or one over-permissioned shared one), and breaks the simple "one place to look for cluster state" property of hub-spoke. ADR-004 already rejects this for v1.
**Do this instead:** Hub-only Flux. If later you need spoke autonomy for air-gapped use cases, revisit in v2.

### Anti-Pattern 3: Hand-editing `clusters/hub-flux/flux-system/`

**What people do:** Tweak `gotk-components.yaml` to customize a controller flag. Change gets reverted within 10 minutes.
**Why it's wrong:** Flux's root Kustomization reconciles its own directory. `flux bootstrap` is idempotent and will overwrite hand changes.
**Do this instead:** Put customizations in a separate file (e.g., `clusters/hub-flux/flux-system-patch.yaml`) and reference it from a sibling `kustomization.yaml`. Or use `flux bootstrap --toleration-keys=...`/flags. Or, preferred, don't customize in v1.

### Anti-Pattern 4: Skipping `--tls-san k3d-<name>-server-0` at cluster create

**What people do:** Create the spoke without the TLS SAN, then try to hit `https://k3d-spoke-ml-server-0:6443` from the hub. Gets "x509: certificate is valid for 127.0.0.1, ::1, 10.43.0.1, kubernetes.default.svc, ...".
**Why it's wrong:** Cannot be fixed post-hoc without re-issuing the serving cert (painful on k3s). Must be set at create time.
**Do this instead:** Encode it in `scripts/create-clusters.sh` for every cluster, hub and spokes.

### Anti-Pattern 5: Using TokenRequest API tokens for spoke kubeconfigs in a lab

**What people do:** `kubectl create token flux-reconciler --duration=24h`, embed in kubeconfig, commit to registration script.
**Why it's wrong:** Token expires. Next reconcile fails with 401. Has to be rotated.
**Do this instead:** For a lab with `task rebuild` semantics, Secret-backed tokens that live with the cluster. For prod, TokenRequest + external-secrets + rotation workflow.

### Anti-Pattern 6: Putting the spoke-targeting Kustomization inside `flux-system/`

**What people do:** Add `spoke-ml.yaml` next to `gotk-sync.yaml` under `clusters/hub-flux/flux-system/`.
**Why it's wrong:** Next `flux bootstrap` reverts it (directory is bootstrap-managed).
**Do this instead:** Put spoke Kustomizations in a SIBLING directory under `clusters/hub-flux/spokes/` with its own `kustomization.yaml`. The root Flux Kustomization recursively picks them up.

---

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| GitHub | `flux bootstrap github` creates PAT-backed Secret `flux-system/flux-system`; Flux polls via HTTPS | PAT must have `repo` scope; public repo still needs a PAT for write-back during bootstrap |
| NVIDIA Container Registry (nvcr.io) | Pulled at docker-build time (CUDA base, device plugin image) | Public; no auth needed for these specific images |
| Docker Hub (rancher/k3s) | Pulled at docker-build and cluster-create | Pin digest to avoid surprise upgrades |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| hub kustomize-controller ↔ spoke kube-apiserver | HTTPS over k8s-net; bearer token auth; server cert validated via embedded CA data | The single load-bearing path; failure here = lab broken |
| spoke CoreDNS ↔ Docker embedded DNS | k3d maintains CoreDNS NodeHosts ConfigMap synced from Docker network state | Goes stale on Docker restart; see `task fix-dns` |
| hub Flux ↔ GitHub | HTTPS via source-controller; PAT in flux-system Secret | Survives restart; no special handling |
| GPU pod ↔ nvidia-container-runtime | Pod declares `runtimeClassName: nvidia` → containerd delegates to nvidia-container-runtime → CDI device injection | `RuntimeClass` object must exist in spoke cluster |

---

## Sources

Tier 1 — Official / authoritative (HIGH confidence):
- [Flux Kustomization spec v1 (kustomize-controller)](https://github.com/fluxcd/kustomize-controller/blob/main/docs/spec/v1/kustomizations.md) — definitive for `spec.kubeConfig.secretRef`, default key `value` / `value.yaml`
- [Flux components/kustomize/kustomizations docs](https://fluxcd.io/flux/components/kustomize/kustomizations/) — user-facing Kustomization reference
- [Flux repository structure guide](https://fluxcd.io/flux/guides/repository-structure/) — monorepo / repo-per-env / multi-tenancy patterns
- [fluxcd/flux2-hub-spoke-example](https://github.com/fluxcd/flux2-hub-spoke-example) — the canonical hub-spoke reference repo
- [k3d CUDA guide (v5.8.3)](https://k3d.io/v5.8.3/usage/advanced/cuda/) — authoritative Dockerfile + device plugin DaemonSet
- [k3d networking design (v5.8.3)](https://k3d.io/v5.8.3/design/networking/) — NodeHosts + host.k3d.internal behavior
- [Kubernetes service-accounts-admin docs](https://kubernetes.io/docs/reference/access-authn-authz/service-accounts-admin/) — legacy token Secret mechanism explicitly supported in 1.24+
- [Docker bridge-driver docs](https://docs.docker.com/engine/network/drivers/bridge/) — embedded DNS semantics on user-defined networks
- [K3s v1.34.X release notes](https://docs.k3s.io/release-notes/v1.34.X) — version + etcd 3.6 note
- [Flux bootstrap for GitHub](https://fluxcd.io/flux/installation/bootstrap/github/) — PAT Secret location

Tier 2 — Issue trackers (MEDIUM confidence for current-state findings):
- [k3d #1009 — CoreDNS NodeHosts lost after adding a new node](https://github.com/k3d-io/k3d/issues/1009)
- [k3d #1112 — CoreDNS customization lost after restart](https://github.com/k3d-io/k3d/issues/1112)
- [k3d #1515 — K3D_FIX_DNS breaks external DNS](https://github.com/k3d-io/k3d/issues/1515)
- [k3d #1516 — External DNS resolution not working on pods (v5.7.0)](https://github.com/k3d-io/k3d/issues/1516)
- [k3d discussion #1015 — Connecting across k3d clusters](https://github.com/k3d-io/k3d/discussions/1015)
- [Flux discussion #3280 — Deploy workloads on remote clusters via kubeconfig](https://github.com/fluxcd/flux2/discussions/3280)
- [Flux discussion #4174 — How to add resources in remote cluster by flux](https://github.com/fluxcd/flux2/discussions/4174)

Tier 3 — Tutorial / commentary (corroborating; LOW individually, MEDIUM in aggregate):
- [Stefan Prodan — FluxCD Multi-cluster Architecture (2024)](https://stefanprodan.com/blog/2024/fluxcd-multi-cluster-architecture/)
- [OneUptime — Set Up Hub-and-Spoke Mode Multi-Cluster with Flux CD (2026)](https://oneuptime.com/blog/post/2026-03-13-how-to-set-up-hub-and-spoke-mode-multi-cluster-with-flux-cd/view) — note this source claims `value` (not `value.yaml`) as the key; cross-checked against Flux v1 spec which confirms both work
- [fluxcd/flux2-multi-tenancy](https://github.com/fluxcd/flux2-multi-tenancy) — directory layout reference for multi-tenant patterns

---
*Architecture research for: local hub-spoke Flux lab on k3d (karyon)*
*Researched: 2026-04-22*
