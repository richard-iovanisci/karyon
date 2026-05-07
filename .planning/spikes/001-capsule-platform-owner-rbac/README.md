---
spike: 001
name: capsule-platform-owner-rbac
type: standard
validates: "Given a non-cluster-admin platform owner group, when it creates a Tenant CR, then Capsule delegates namespace creation to the lower-level owner while platform owner can inspect Capsule resources but cannot read tenant Secrets."
verdict: VALIDATED
related: []
tags: [capsule, rbac, tenancy]
---

# Spike 001: Capsule Platform Owner RBAC

## What This Validates

Given a `capsule-platform-owners` group bound to a narrow ClusterRole, when an
operator creates a lower-level Capsule `Tenant`, then Capsule accepts the Tenant
CR and the delegated owner can create namespaces through normal Capsule
admission.

## Research

This spike used the live `k3d-spoke-capsule` API as the source of truth because
the repo pins Capsule v0.12.4.

| Approach | Tool/Library | Pros | Cons | Status |
|---|---|---|---|---|
| Kubernetes RBAC ClusterRole bound to a platform group | Kubernetes RBAC | Simple, auditable, maps cleanly to an IdP group, does not grant tenant workload access by default | Platform owner uses direct apiserver RBAC rather than capsule-proxy tenant filtering | Chosen |
| Add platform group as owner to every Tenant | Capsule `spec.owners[]` | Lets platform owners act inside tenant namespaces | Blurs platform admin and tenant workload admin responsibilities | Rejected for default |
| Reuse `cluster-admin` | Kubernetes RBAC | Fastest to make work | Violates the isolation goal and hides the real permission set | Rejected |

Relevant live findings:

- `kubectl explain tenant.spec.owners --api-version=capsule.clastix.io/v1beta2`
  confirms `owners[].kind` supports `User`, `Group`, and `ServiceAccount`.
- A user with Tenant CR create/update/delete RBAC can create a new `Tenant`.
- Capsule grants namespace-create admission only to identities assigned to a
  Tenant; unaffiliated authenticated users still hit the Capsule webhook denial.
- Lower-level owners should use `kubectl create namespace ...` for the smoke
  path. `kubectl apply` performs a preflight `get namespaces`, which Capsule's
  owner RBAC does not grant at cluster scope.

## How to Run

Static contract:

```bash
bats tests/bats/capsule-platform-owner-01-static-rbac.bats
```

Live smoke after the RBAC lands on `k3d-spoke-capsule`:

```bash
bats tests/bats/capsule-platform-owner-02-live-rbac.bats
```

Manual probe:

```bash
kubectl --context=k3d-spoke-capsule \
  --as=capsule-platform-owner \
  --as-group=capsule-platform-owners \
  get tenants.capsule.clastix.io
```

## What to Expect

- Platform owner can list `alpha` and `bravo` Tenant CRs.
- Platform owner can read `capsuleconfiguration/default`.
- Platform owner can create a temporary lower-level Tenant.
- The delegated lower-level owner can create a namespace assigned to that Tenant.
- Platform owner cannot create ClusterRoleBindings and cannot read tenant Secrets.

## Investigation Trail

1. Confirmed the starting state: `capsule-platform-owner` had no Tenant or
   CapsuleConfiguration permissions.
2. Applied a temporary live ClusterRole/ClusterRoleBinding directly to
   `k3d-spoke-capsule`.
3. Verified Tenant CRUD worked through `kubectl --as=capsule-platform-owner`.
4. Verified an unaffiliated lower owner could not use `kubectl apply` for
   namespaces because apply requires cluster-scope `get namespaces`.
5. Retested with `kubectl create namespace`; Capsule admission assigned the
   namespace to the newly created Tenant.
6. Cleaned up the temporary Tenant, namespace, ClusterRoleBinding, and
   ClusterRole.
7. Persisted the narrow RBAC in `pocs/capsule/spoke/rbac/platform-owner.yaml`
   with static and live regression coverage.

## Results

VALIDATED.

The useful model is a narrow Kubernetes RBAC role:

- Read all `capsule.clastix.io` resources.
- Manage `tenants.capsule.clastix.io`.
- Read namespace inventory.
- Avoid `cluster-admin`, tenant Secret access, and default tenant workload admin
  access.

The platform owner creates and manages the Tenant CR boundary; lower-level owners
listed in `spec.owners[]` operate inside their assigned tenants.
