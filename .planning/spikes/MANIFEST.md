# Spike Manifest

## Idea

Explore a Capsule platform-owner role for operators who can see Capsule control-plane resources and manage lower-level Tenant CRs without receiving unrestricted cluster-admin access or tenant workload access.

## Requirements

- Platform ownership should be represented as Kubernetes RBAC on the spoke cluster, not as a blanket Capsule tenant owner on every tenant.
- Platform owners may manage `Tenant` CRs and inspect tenant inventory, but tenant-local workload access must continue to come from each Tenant's `spec.owners[]`.
- The POC should remain public-safe: no real identities, tokens, hostnames, or secrets in git.

## Spikes

| # | Name | Type | Validates | Verdict | Tags |
|---|------|------|-----------|---------|------|
| 001 | capsule-platform-owner-rbac | standard | Given a non-cluster-admin platform owner group, when it creates a Tenant CR, then Capsule delegates namespace creation to the lower-level owner while platform owner can inspect Capsule resources but cannot read tenant Secrets. | VALIDATED | capsule, rbac, tenancy |
