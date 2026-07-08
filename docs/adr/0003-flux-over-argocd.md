# 3. Flux Over ArgoCD

## Status

Accepted (2026-04-22)

## Context

The lab needs a GitOps controller stack to reconcile manifests under
`clusters/` and `examples/` into the three k3d clusters. Two well-established
candidates: Flux v2 (CNCF Graduated, controller set: `source-controller`,
`kustomize-controller`, `helm-controller`, `notification-controller`) and
ArgoCD (CNCF Graduated, server + repo-server + application-controller +
applicationset-controller). Both reconcile a Git repo into a Kubernetes
cluster; both support hub-spoke topologies; both have mature Helm + Kustomize
support.

The lab has 2-3 spokes today and a hub-only control plane (see
`0004-hub-only-flux-control-plane.md`). The CRD set installed on the hub
matters because every controller increases the hub's footprint. Spoke
multiplicity is low — a feature like ArgoCD's `ApplicationSet` cluster
generator with label-based targeting (one declaration → many clusters) is
worth less here than a per-spoke explicit Kustomization is.

## Decision

Use Flux v2 as the GitOps controller stack on `hub-flux`. Author 2-3 explicit
hub-side `Kustomization` resources per spoke under `clusters/hub-flux/spokes/`,
each with `spec.kubeConfig` pointing at a kubeconfig Secret in `flux-system`.

## Consequences

**Easier:**
- Smaller controller footprint on the hub: 4 Flux controllers vs ArgoCD's
  full server+UI+repo-server+applicationset-controller stack. Fewer Pods and
  less idle RAM. Pertinent on a single dev box.
- `flux bootstrap github` is a single, idempotent command. No
  cluster-config-only-via-UI gotchas.
- Tighter integration with `kustomize-controller`'s native `spec.kubeConfig`
  remote-cluster reconciliation (the hub-only pattern this lab uses; see
  ADR-004). Direct, no `Application` resource layer.
- The silent-misroute defense (explicit `spec.kubeConfig.secretRef`
  with `key: value.yaml`) is documented in `docs/flux-hub-spoke.md` and
  enforced in `clusters/hub-flux/spokes/spoke-{ml,apps}.yaml`.

**Harder:**
- No clean Flux equivalent of ArgoCD's `ApplicationSet` cluster generator
  with label-based targeting. For 2-3 spokes (the v1 scope), authoring
  per-spoke explicit Kustomizations is acceptable; the lab's current pattern
  is `clusters/hub-flux/spokes/spoke-ml.yaml` + `clusters/hub-flux/spokes/spoke-apps.yaml`.
  At higher spoke counts (~5+), the duplication starts to add real
  maintenance cost.
- No web UI baked in. The lab compensates with `flux check`, `flux get
  kustomizations -A`, `flux logs`, and `task health-check`. A web UI
  (e.g., `weave-gitops`, `headlamp`) can be layered later but is out of
  scope for v1.

**No-change:**
- Both controllers are CNCF Graduated and well-supported. The Flux choice is
  reversible later if the spoke count grows enough that
  ApplicationSet pays for itself.

## Migration note

If future work (e.g., when the lab grows to 5+ spokes) reverses this
decision, the migration is non-trivial but bounded:

1. Replace `clusters/hub-flux/flux-system/` with the ArgoCD installation
   manifests (likely via Helm chart `argo/argo-cd`).
2. Translate each `Kustomization` under `clusters/hub-flux/spokes/` to an
   `Application` (or, more efficiently, to a single `ApplicationSet` with a
   `clusters` generator targeting all spoke labels).
3. Re-author `register-spokes-for-flux.sh` to provision spokes as ArgoCD
   Cluster registrations (which use a Secret with `type: Opaque` and the
   `argocd.argoproj.io/secret-type: cluster` label) instead of Flux
   kubeconfig Secrets.
4. The `spec.kubeConfig` defense-in-depth pattern does not
   exist in ArgoCD; the equivalent is the cluster-registration model itself.
   Re-document the silent-misroute defense for ArgoCD before the migration
   ships.
5. The Helm `HelmRelease` resources from `helm-controller` translate to
   `Application` resources with `source.helm` blocks; semantics are
   equivalent for the lab's current scope.

The migration is documented as v2-eligible (not v1 scope); concrete trigger
is "spoke count exceeds 5" or "ApplicationSet semantic features become
load-bearing for new use cases."
