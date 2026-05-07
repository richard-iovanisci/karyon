---
phase: 11-validation-graduation-adr-008
plan: 07
subsystem: infra
tags: [flux, capsule, multi-tenancy, validation, g-06, rbac, diagnostics]
requirements-completed: [VAL-01, VAL-05]
disposition: passed
completed: 2026-05-07
depends_on: [11-06]
---

# Phase 11 Plan 07: G-06 Diagnostics + Operator Verification Summary

Plan 11-07 closed the G-06 HelmRelease reconciliation blocker and completed the
Plan 11-06 human verification gate. The original hypothesis was confirmed:
cross-cluster HelmReleases without `spec.serviceAccountName` caused
helm-controller to use `system:serviceaccount:capsule-system:default` on the
spoke target, and that target identity could not read Helm storage Secrets in
`capsule-system`.

## Result

- `poc-capsule`, `poc-capsule-spoke`, `poc-capsule-spoke-rbac`, and
  `poc-capsule-spoke-tenants` are Ready=True at `main@sha1:8415ab66`.
- `capsule` and `capsule-proxy` HelmReleases are Ready=True.
- `capsule-system:helm-controller` exists on `k3d-spoke-capsule`.
- `helm-controller-cluster-admin` exists on `k3d-spoke-capsule`.
- SAR for `system:serviceaccount:capsule-system:helm-controller` returns `yes`.
- `curl -sk https://127.0.0.1:30443/healthz` returns HTTP 200.
- CI passed for pushed head `8415ab6655faba324ee1809fdb22b08380f42a38`.

## Accomplishments

- Added spoke-side bootstrap RBAC under `pocs/capsule/spoke/rbac/`.
- Added the separate `poc-capsule-spoke-rbac` Flux Kustomization so the
  namespace, ServiceAccount, and ClusterRoleBinding land before HelmRelease
  reconciliation depends on them.
- Corrected spoke-targeted Kustomizations to use `serviceAccountName:
  flux-reconciler`, matching the POC spoke bootstrap identity.
- Added `spec.serviceAccountName: helm-controller` to the Capsule operator and
  capsule-proxy HelmReleases.
- Split Tenant CR bootstrap ahead of tenant home namespace reconciliation.
- Authorized Flux as a temporary bootstrap owner on Tenant CRs so it can apply
  tenant home namespaces through Capsule admission.
- Preserved established `tenant-alpha` and `tenant-bravo` home namespace names
  by setting per-Tenant `forceTenantPrefix: false`.
- Fixed the residual capsule-proxy namespace admission failure by preventing
  Helm from trying to create or patch the already-existing `capsule-system`
  namespace.
- Captured empirical pre/post evidence in `11-07-G06-DIAGNOSTICS.md`.
- Updated `11-06-SUMMARY.md` from the previous verification hold to `passed`.

## Verification

Static checks run:

```text
bats tests/bats/tenants-01-static-tenant-cr.bats tests/bats/push-gate-03-static-tenant-ns-label.bats tests/bats/tenants-02-static-p27.bats
bats tests/bats/push-gate-03-static-tenant-ns-label.bats tests/bats/push-gate-06-static-helmrelease-sa.bats
bats tests/bats/push-gate-07-static-spoke-rbac-bootstrap.bats tests/bats/capsule-install-01-static-helmrelease.bats tests/bats/tenants-01-static-tenant-cr.bats
kubectl kustomize pocs/capsule/spoke
kubectl kustomize pocs/capsule/spoke/rbac
flux build kustomization poc-capsule-spoke-tenants --dry-run --path ./pocs/capsule/spoke/tenant-crs --kustomization-file clusters/hub-flux/pocs/capsule-spoke-tenants.yaml
```

Live checks run:

```text
bats tests/bats/tenants-06-live-tenant-cr.bats tests/bats/push-gate-04-live-tenant-ns-flux-apply.bats
bats tests/bats/capsule-install-06-live-helm.bats tests/bats/capsule-install-08-live-proxy-reachable.bats
bash .planning/phases/11-validation-graduation-adr-008/capture-g06-postpush-evidence.sh
```

Closeout evidence is recorded in:

- `11-07-G06-DIAGNOSTICS.md`
- `11-06-SUMMARY.md` section `Task 3 Verification Evidence (Plan 11-07 closure)`

## Important Nuance

The G-06 impersonation/RBAC hypothesis was confirmed, but it was not the only
failure observed during closeout. Once the `helm-controller` ServiceAccount and
RBAC were in place, `capsule-proxy` exposed a separate namespace-patch admission
failure against the already-existing `capsule-system` namespace. That residual
failure was fixed in the same closeout path by disabling Helm namespace creation
for `capsule-proxy`.

## Residual Work

The remaining visible Flux failures for `tenant-alpha-app` and
`tenant-bravo-app` are intentionally not closed by this plan. They are tenant
GitRepository authentication failures against the private GitHub repository.
The user explicitly chose to hold off on alpha/bravo app-source work for now.

## Commits

- `8b5bae9` docs(11-07): add G-06 prepush capture helper
- `df5eda6` fix(11-07): avoid Capsule namespace patch during rbac bootstrap
- `f817982` fix(11-07): split Tenant CR bootstrap before home namespaces
- `8d8aa8a` fix(11-07): preserve Capsule tenant bootstrap ordering
- `6405c6f` fix(11-07): authorize Flux tenant namespace bootstrap
- `faecf14` fix(11-07): preserve tenant home namespace names

## Next Step

Run `$gsd-progress` again. It should no longer route back to 11-07 Task 6 for
G-06 diagnostics and should instead route to the next phase-level verification or
next planned phase.
