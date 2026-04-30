# Capsule Quickstart

Bare-minimum install: namespace + Helm chart + verification. Lockdown, tenants, and proxy round-trip are out of scope here — see `docs/capsule-on-eks.md` for the full design.

## Version matrix

| Kubernetes | Capsule operator | capsule-proxy | Verify with |
|---|---|---|---|
| 1.34+ | `0.12.4` | `0.12.0` | `helm show chart oci://ghcr.io/projectcapsule/charts/capsule --version 0.12.4` |
| 1.33  | latest `0.11.x` | latest `0.11.x` | same `helm show chart` against the 0.11 pin |
| ≤ 1.32 | not supported by current Capsule | — | use Capsule 0.10.x (community-best-effort only) |

The chart's `kubeVersion` field is the source of truth — pin to whatever satisfies it for your cluster's exact patch.

## Prerequisites

- cluster-admin kubeconfig (install only)
- Helm 3.x
- RBAC + admission webhooks enabled (default in any standard distribution)

## Install

```bash
# 1. Namespace (just one)
kubectl create namespace capsule-system

# 2. Operator (installs all 7-9 CRDs automatically)
helm install capsule oci://ghcr.io/projectcapsule/charts/capsule \
  --version 0.12.4 \
  --namespace capsule-system

# 3. Proxy (separate chart — do NOT use the operator's umbrella `proxy.enabled=true`,
#    it pins capsule-proxy to a stale minor)
helm install capsule-proxy oci://ghcr.io/projectcapsule/charts/capsule-proxy \
  --version 0.12.0 \
  --namespace capsule-system
```

For Kubernetes 1.33, swap both `--version` pins to the matching 0.11.x release.

## Verify

```bash
kubectl -n capsule-system get pods
# capsule-controller-manager-*       Running
# capsule-proxy-*                    Running

kubectl get crd | grep capsule.clastix.io
# 9 rows on Capsule 0.12 (7 on 0.11 — resourcepools + resourcepoolclaims are 0.12-only)
```

## Next

`docs/capsule-on-eks.md` covers tenant CR shape, CapsuleConfiguration singleton, IRSA, NLB/ALB exposure, and the Flux multi-tenancy lockdown.
