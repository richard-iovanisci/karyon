# 4. Hub-Only Flux Control Plane

## Status

Accepted (2026-04-22)

## Context

The lab has three k3d clusters: `hub-flux` (control plane home), `spoke-ml`
(GPU workloads), and `spoke-apps` (general-purpose workloads). Two
deployment topologies are common for multi-cluster GitOps:

1. **Per-cluster controllers**: Run a Flux controller stack on every cluster,
   each reconciling a different path of the same Git repo. Independent
   blast radius per cluster; redundant controller footprint per cluster.
2. **Hub-only controllers**: Run Flux on a single hub cluster; have the
   hub's `kustomize-controller` and `helm-controller` reconcile manifests
   into spokes via `spec.kubeConfig` and a remote kubeconfig Secret.

Implementing spoke registration surfaced one significant
risk in the hub-only pattern: the silent misroute. If a Flux Kustomization
omits `spec.kubeConfig`, the controller falls back to its own in-cluster
ServiceAccount and reconciles the manifests into the HUB cluster (where the
controller runs) while reporting `Ready=True`. The Kustomization appears
green; the workloads land in the wrong cluster.

## Decision

Run Flux only on `hub-flux`. Author hub-side Flux `Kustomization` resources
under `clusters/hub-flux/spokes/<spoke>.yaml` with `spec.kubeConfig.secretRef`
pointing at a kubeconfig Secret in the `flux-system` namespace, key
`value.yaml`. Each spoke's `kubeconfig` Secret is provisioned by
`scripts/register-spokes-for-flux.sh` from a `kubernetes.io/service-account-token`-typed
Secret on the spoke (legacy Secret-backed SA token with indefinite lifetime;
not `kubectl create token`, whose TokenRequest expiry is not a useful failure
mode in a lab).

## Consequences

**Easier:**
- One controller stack to operate, observe, upgrade, and restart. Fewer
  moving parts overall; lower aggregate idle RAM (helpful on a single
  dev box).
- Spokes carry only their workloads (no GitOps controller footprint, no
  reconcile loops). They can be torn down and recreated without losing
  GitOps state on the hub.
- The `spec.kubeConfig` reconciliation pattern is documented in
  `../flux-hub-spoke.md` — the patch surface and immutability
  rules carry through unchanged from a vanilla Flux install.

**Harder:**
- The silent-misroute risk is real and not visible in `kubectl` output
  alone. Defense in depth requires:
  1. Every spoke Kustomization MUST include `spec.kubeConfig.secretRef.name:
     <spoke>-kubeconfig` AND `spec.kubeConfig.secretRef.key: value.yaml`.
     Both fields are explicit; the key defaults to `value.yaml` but is
     pinned for clarity.
  2. Negative-proof tests in `tests/bats/register-spokes-02-live.bats`
     verify that `.status.inventory` of each spoke Kustomization contains
     at least one resource (e.g., a `ConfigMap` named `karyon-spoke-id`)
     that exists ONLY on the spoke and NOT on the hub — proves
     reconciliation landed on the right cluster, not the hub.
  3. The hub's `kustomize-controller` has cluster-admin equivalent on every
     spoke (via the ServiceAccount → ClusterRoleBinding chain the register
     script creates). This is acceptable for lab scope but would not be
     acceptable in production (a v2 concern would be per-namespace RBAC).
- DNS dependence: the hub's `kustomize-controller` reaches each spoke's
  apiserver by Docker embedded DNS hostname (`k3d-<spoke>-server-0`).
  Stale CoreDNS NodeHosts after Docker / WSL restart manifest as
  reconcile failures on the hub side. The lab ships `task fix-dns`
  as the canonical workaround.

**No-change:**
- Per-cluster controllers remain feasible (and may be preferred at higher
  spoke counts). Reversal is bounded: install Flux on each spoke, point
  each spoke's `flux-system` Kustomization at the corresponding
  `clusters/<spoke>/` path, remove the hub-side `clusters/hub-flux/spokes/`
  tree.
- Adopting ArgoCD (see `0003-flux-over-argocd.md` migration note) would
  rework the hub-only model into ArgoCD's cluster-registration pattern;
  the same defense-in-depth principles apply.
