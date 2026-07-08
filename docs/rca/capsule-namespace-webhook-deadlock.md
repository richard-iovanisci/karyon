# RCA: Capsule namespace webhook deadlock on cold bootstrap

- **Date observed:** 2026-05-27
- **Date resolved:** 2026-05-27 (fix commit `c89f1b2`)
- **Component:** Capsule v0.12.4 on `k3d-spoke-capsule`, reconciled from the hub cluster by Flux
- **Severity:** Tenant isolation silently broken; cluster unrecoverable without bypassing the webhook

## Summary

The repo's Capsule HelmRelease overrode the `namespaces.tenants.projectcapsule.dev`
mutating webhook's `failurePolicy` from the chart default `Fail` to `Ignore`. On a cold
bootstrap there is a window where the webhook service is not yet reachable; with
`Ignore`, tenant-labeled namespaces are admitted **without** the `ownerReferences`
mutation that claims them for their Tenant CR. The companion validating webhook (chart
default `Fail`) then blocks every subsequent UPDATE/DELETE on the labeled-but-unowned
namespace, leaving the cluster in a deadlock that can only be escaped by scaling the
Capsule controller to zero. The fix restores the chart default `failurePolicy: Fail`
for the `namespaces` hook only.

## Symptoms

Expected on a healthy cluster:

- The `namespaces.tenants.projectcapsule.dev` mutating webhook fires on namespace
  CREATE and adds an `ownerReference` pointing at the Tenant CR.
- The Capsule controller materializes per-namespace RoleBindings from the Tenant's
  `spec.owners[]`.
- `Tenant.status.size > 0` and `Tenant.status.namespaces[]` is populated.

Actual, on a freshly rebuilt cluster (2026-05-27):

- Tenant CRs `alpha` and `bravo` reconcile to `Ready=True`, `STATE=Active`,
  `reason=Succeeded` — the Tenants *look* healthy.
- But `Tenant.status.size: 0` and `status.namespaces: []`.
- `kubectl get ns tenant-alpha -o jsonpath='{.metadata.ownerReferences}'` returns empty.
- `kubectl -n tenant-alpha get rolebindings` returns `No resources found`.
- Tenant-owner LIST through capsule-proxy returns nothing (should return the tenant's
  own namespace). Platform-owner LIST and cross-tenant denial still work, so the
  failure is specific to the namespace claim, not RBAC at large.
- No error events surface anywhere — the failure mode is silent by construction.

Probe commands:

```bash
kubectl --context k3d-spoke-capsule get tenant alpha -o jsonpath='{.status.size}{"\n"}'
# Expected: > 0; Actual: 0

kubectl --context k3d-spoke-capsule get ns tenant-alpha -o jsonpath='{.metadata.ownerReferences}{"\n"}'
# Expected: [{"kind":"Tenant","name":"alpha",...}]; Actual: empty

kubectl --context k3d-spoke-capsule -n tenant-alpha get rolebindings
# Expected: RoleBindings from Tenant spec.owners[]; Actual: "No resources found"
```

The same setup had worked end-to-end in a demo run on 2026-05-19 — see
"Why it did not reproduce earlier" below.

## Root cause

An earlier bootstrap-hardening change in `pocs/capsule/operator/helmrelease.yaml` had
weakened roughly 13 Capsule webhook `failurePolicy` values from the chart default
`Fail` to `Ignore`, on the theory that failing open makes cold bootstrap more robust.
For the `namespaces` mutating hook — the one that adds the claiming `ownerReference` —
that reasoning inverts. The cold-bootstrap race:

1. Flux applies the `tenant-alpha` namespace (as the Flux reconciler service account).
2. The mutating webhook is briefly unreachable — the `capsule-webhook-service`
   Endpoint is not yet Ready after the controller starts. With `failurePolicy: Ignore`
   the apiserver ignores the failed admission call and admits the namespace **without**
   the ownerRef mutation. (Chart default `Fail` would have rejected the CREATE, and
   Flux would retry until the webhook serves — self-healing.)
3. The Capsule reconciler skips the namespace because no ownerRef claims it, so
   `status.size` stays 0 and no RoleBindings are created.
4. The validating webhook `namespaces.projectcapsule.dev` (chart default `Fail`) then
   blocks every UPDATE/DELETE on the labeled-but-unowned namespace
   (`namespace label "alpha" does not match owner reference ""`).
5. The cluster is stuck until the webhook is bypassed (scale the controller to 0).

### Controlled experiment: which chart key controls the webhook

`helm template` against the pinned chart proved `webhooks.hooks.namespaces` is the
controlling value key (and that a plausible-looking alternative is a silent no-op):

```text
helm template ... --set webhooks.hooks.namespaces.failurePolicy=Ignore     => rendered webhook = Ignore
helm template ... --set webhooks.hooks.namespacePatch.failurePolicy=Ignore => rendered webhook = Fail (no-op key)
```

A live A/B on the cluster confirmed causality end-to-end: with the repo value
`namespaces: Ignore` the live webhook rendered `Ignore` and the bug reproduced; with
`namespaces: Fail` the live webhook rendered `Fail` and the tenant claim worked.

### Why it did not reproduce earlier

The race is timing-dependent. Under `Ignore`, whether the silent skip happens depends
on the webhook-readiness window versus Flux's namespace-apply timing. The 2026-05-19
cold rebuild won the dice roll; the 2026-05-27 rebuilds lost it repeatedly. The bug was
always latent under `Ignore` — nothing upstream changed.

## Eliminated hypotheses

- **Damage from a prior partial cluster rebuild** — the bug reproduces on a true
  blank-slate rebuild (destroy everything, recreate the cluster, re-register, cold
  Flux reconcile).
- **Stale capsule-proxy pod** — `kubectl rollout restart deploy/capsule-proxy` changed
  nothing.
- **Stale capsule-controller-manager** — restarting it did not change
  `Tenant.status.size` or trigger RoleBinding creation.
- **Damaged Tenant CR** — deleting the Tenant and letting Flux re-apply it reproduced
  the same broken state; the CR on disk matched git HEAD.
- **Cluster stop/start clearing namespace ownership** — a k3d stop/start cycle did not
  help; a full cold rebuild was still broken.
- **`forceTenantPrefix` override semantics** — an early suspect (CapsuleConfiguration
  set `forceTenantPrefix: true` while the Tenant CRs set `false`), but the proven
  mechanism explains every observation without any prefix involvement, and flipping
  only the `failurePolicy` closed the bug.
- **Upstream chart repackage** — a mid-investigation draft blamed a silent repackage of
  the `0.12.4` chart tag. Disproven: the chart build (`+56638ab8bf45`) dates
  2025-12-19 and is stable; digest pinning confirmed zero drift.
- **Missing Flux dependency edge** — the spoke Kustomization already depended on the
  operator Kustomization; apply ordering was never the gap.
- **Bogus `webhooks.hooks` value keys** — the per-hook keys are valid chart keys; the
  problem was the *value* chosen for one of them, not the key path.

## Fix

### Part A — immediate cluster recovery (no rebuild required)

The validating webhook only fires on namespaces carrying the tenant label, so removing
the label unblocks deletion:

```bash
# Suspend Flux so it does not fight the manual repair
flux --context k3d-hub-flux suspend kustomization poc-capsule-spoke

# Strip the tenant label from the unowned namespaces, then delete them
kubectl --context k3d-spoke-capsule label ns tenant-alpha capsule.clastix.io/tenant-
kubectl --context k3d-spoke-capsule label ns tenant-bravo capsule.clastix.io/tenant-
kubectl --context k3d-spoke-capsule delete ns tenant-alpha tenant-bravo

# Resume Flux; it re-creates the namespaces while the webhook is warm,
# so the mutation fires correctly this time.
flux --context k3d-hub-flux resume kustomization poc-capsule-spoke
flux --context k3d-hub-flux reconcile kustomization poc-capsule-spoke --timeout=2m
```

### Part B — permanent fix (commit `c89f1b2`)

1. **Restore the chart default** — flip `webhooks.hooks.namespaces.failurePolicy` from
   `Ignore` to `Fail` in `pocs/capsule/operator/helmrelease.yaml`. With `Fail`, a
   webhook-unavailable window at cold bootstrap rejects the namespace CREATE, and Flux
   retries until the webhook serves — self-healing, no silent skip. The change is
   surgical: only the `namespaces` hook flips; the other hooks keep `Ignore` for
   bootstrap resilience.

   ```yaml
   webhooks:
     hooks:
       namespaces:
         failurePolicy: Fail   # restores the chart default; other hooks keep Ignore
   ```

2. **Pin both Capsule chart sources by digest** (`pocs/capsule/operator/ocirepository.yaml`
   and `pocs/capsule/proxy/ocirepository.yaml`). Not the root cause — the chart was
   never repackaged — but the investigation showed why tags alone are insufficient: an
   OCI tag such as `0.12.4` is mutable, so the registry could repackage the artifact
   silently and Flux would follow it. Pinning by digest makes every reconcile
   reproducible across cold rebuilds; the tag is kept alongside the digest for human
   readability, but the digest is authoritative per the OCI spec. Digests were captured
   on 2026-05-27 from each OCIRepository's `.status.artifact.revision`:

   - capsule: `sha256:56638ab8bf455c5a1f5cf581c474681147cfe7031a0ff902a42c3715f0011fb7`
   - capsule-proxy: `sha256:0b8c6ef4a74425c8bd4c0e383cf1847042580ca4071db2ed07b3c26bc0b0d02d`

3. **Extra ordering machinery — investigated and rejected.** The spoke Kustomization
   already depended on the operator Kustomization; a hub-targeted Kustomization cannot
   health-check a spoke Deployment under the hub-only-Flux architecture (see
   `docs/adr/0004`-series constraints); and with `failurePolicy: Fail` the webhook
   self-heals via apiserver-reject plus Flux-retry, so no additional ordering is
   needed.

## Verification (live, 2026-05-27 — all green)

- `mutatingwebhookconfiguration .../namespaces.tenants.projectcapsule.dev` shows
  `failurePolicy: Fail`.
- Tenant `alpha` `status.size` = 1, `status.namespaces` = `["tenant-alpha"]`; `bravo`
  identical.
- `ns/tenant-alpha` has `ownerReferences[0]` = `Tenant/alpha`; `bravo` likewise.
- 11 RoleBindings auto-created in each tenant namespace.
- Demo dry-run green: platform-owner LIST returns both tenants, privilege escalation
  denied, tenant-owner LIST returns only its own namespace, cross-tenant access
  Forbidden.

A regression guard lives in `tests/bats/capsule-install-03-static-values.bats`: the
`namespaces` hook must stay at `Fail` and must never be reverted to `Ignore`.

## Recovery runbook (for a cluster that predates the fix)

```bash
flux --context k3d-hub-flux suspend kustomization poc-capsule-spoke
kubectl --context k3d-spoke-capsule -n capsule-system scale deploy capsule-controller-manager --replicas=0
kubectl --context k3d-spoke-capsule delete ns tenant-alpha tenant-bravo --wait=true
kubectl --context k3d-spoke-capsule -n capsule-system scale deploy capsule-controller-manager --replicas=1
kubectl --context k3d-spoke-capsule -n capsule-system rollout status deploy/capsule-controller-manager
flux --context k3d-hub-flux resume kustomization poc-capsule-spoke
flux --context k3d-hub-flux reconcile kustomization poc-capsule-spoke --timeout=2m
```

## Residual follow-ups (non-blocking)

- Audit the other ~12 `Ignore` overrides in the HelmRelease: does any other hook have a
  failure mode that is recoverable only by bypassing the webhook? (`namespaces` was the
  dangerous one; the rest are likely acceptable for a POC.)
- A full cold-rebuild test with the fix in place would prove non-recurrence end-to-end;
  it was not run on the day of the fix because the cluster was green and demo-ready.

## Related documents

- `docs/adr/0008-capsule-multi-tenancy-graduation.md` — carries an addendum recording
  this finding.
