---
slug: capsule-tenant-ns-claim
status: root_cause_found
trigger: capsule-tenant-namespace-claim-regression
created: 2026-05-27
updated: 2026-05-27
tags: [capsule, multi-tenancy, webhook, ownership, supply-chain, v0.21-carryforward]
---

# Capsule Tenant Namespace Claim Regression

## Symptoms

### Expected behavior

Capsule v0.12.4 claims the `tenant-alpha` and `tenant-bravo` namespaces:
- Mutating webhook `namespaces.tenants.projectcapsule.dev` fires on namespace CREATE
- Adds `ownerReferences` to the namespace pointing at the Tenant CR
- Capsule controller materializes per-namespace `RoleBindings` from the Tenant's `spec.owners[]`
- `Tenant.status.size > 0`, `Tenant.status.namespaces[]` populated
- Per Phase 14 evidence captured 2026-05-19 (`14-02-demo-live-evidence.log` line: `ok 99 DEMO-01 (Tier-2 platform-owner): kubectl get tenants returns alpha + bravo`, plus `ok 102 DEMO-02 (alpha scoped LIST): tenant-owner via proxy:30443 sees only own tenant ns`), this worked end-to-end and `kubectl --kubeconfig=$TO_ALPHA_KC get namespaces` returned only `tenant-alpha`.

### Actual behavior

On freshly-rebuilt cluster at HEAD `e26c18ef` (after `task destroy && task rebuild && bash scripts/poc/capsule/create-cluster.sh && bash scripts/register-poc-cluster.sh spoke-capsule && flux reconcile poc-capsule + poc-capsule-spoke-rbac + poc-capsule-spoke + poc-capsule-spoke-tenants`):

- Tenant CRs alpha + bravo reconcile to `Ready=True`, `STATE=Active`, `reason=Succeeded`, `message=reconciled`
- BUT `Tenant.status.size: 0`
- BUT `Tenant.status.namespaces: []` (empty)
- BUT `kubectl get ns tenant-alpha -o jsonpath='{.metadata.ownerReferences}'` returns empty (no ownerReferences set)
- BUT `kubectl -n tenant-alpha get rolebindings` returns `No resources found in tenant-alpha namespace`
- Platform-owner kubeconfig LIST tenants → works (returns alpha + bravo) — proxy path partially functional
- Platform-owner self-escalation → correctly Forbidden — RBAC ceiling holds
- Tenant-owner alpha kubeconfig LIST namespaces → `No resources found` (regression — should return `tenant-alpha`)
- Cross-tenant peek → correctly Forbidden (RBAC-level enforcement intact)

### Error messages

No explicit error events surface. Capsule controller logs show only:
- Recent reconciles successful (transient optimistic-concurrency on initial setup, normal)
- `GlobalTenantResource` (hello-world-seeded) replication errors due to Pod immutability on rerun (separate concern, unrelated to namespace claim)
- The mutating webhook for namespace creation has `failurePolicy: Ignore` — this means if the webhook fails to respond during admission, the namespace is created WITHOUT the webhook's mutations (i.e., without `ownerReferences`). Silent failure mode.

### Timeline

- **Worked:** 2026-05-19 (Phase 14 cold-run + DEMO-01..06 bats all GREEN)
- **Broken:** 2026-05-27 (this debug session). Reproduces on:
  - Original cluster state pre-Plan 15-04
  - After Plan 15-04 retry-2's partial `task rebuild` cascade
  - After full `task destroy && task rebuild` + spoke-capsule cold rebuild
  - **Even on a true blank-slate cluster the regression persists.**

### Reproduction

```bash
# Setup (assumes git HEAD = origin/main, hub-flux + spoke-ml + spoke-apps healthy via task rebuild + task health-check 19/19):
k3d cluster delete spoke-capsule 2>/dev/null  # idempotent
bash scripts/poc/capsule/create-cluster.sh
bash scripts/register-poc-cluster.sh spoke-capsule
flux --context k3d-hub-flux reconcile kustomization poc-capsule --with-source --timeout=2m
flux --context k3d-hub-flux reconcile kustomization poc-capsule-spoke-rbac --timeout=2m
flux --context k3d-hub-flux reconcile kustomization poc-capsule-spoke --timeout=2m
flux --context k3d-hub-flux reconcile kustomization poc-capsule-spoke-tenants --timeout=2m
sleep 15

# Probe the regression:
kubectl --context k3d-spoke-capsule get tenant alpha -o jsonpath='{.status.size}{"\n"}'
# Expected: > 0 (claims tenant-alpha namespace); Actual: 0

kubectl --context k3d-spoke-capsule get ns tenant-alpha -o jsonpath='{.metadata.ownerReferences}{"\n"}'
# Expected: [{"apiVersion":"capsule.clastix.io/v1beta2","kind":"Tenant",...}]; Actual: empty

kubectl --context k3d-spoke-capsule -n tenant-alpha get rolebindings
# Expected: RoleBindings auto-created from Tenant spec.owners[]; Actual: "No resources found"
```

## Configuration state at time of bug

### CapsuleConfiguration `default`

```yaml
spec:
  forceTenantPrefix: true   # <-- mismatch suspect
  allowServiceAccountPromotion: true
  enableTLSReconciler: false
  userGroups:
    - capsule.clastix.io
    - system:serviceaccounts
    - system:authenticated
  protectedNamespaceRegex: ^kube-.*$
```

### Tenant CR alpha (relevant fields)

```yaml
spec:
  forceTenantPrefix: false   # <-- D-11-07 live repair (Phase 11 + Plan 12-01 TEN-01 amendment); supposed to override CapsuleConfiguration
  namespaceOptions:
    managedMetadataOnly: false
    quota: 3
  owners:
    - kind: ServiceAccount
      name: system:serviceaccount:flux-system:flux-reconciler   # Note: SA-as-User format, not kind+namespace+name
    - kind: ServiceAccount
      name: system:serviceaccount:tenant-alpha:gitops-reconciler
    - kind: User
      name: alpha
    - kind: ServiceAccount
      name: system:serviceaccount:tenant-alpha:human-tenant-owner
    - kind: Group
      name: capsule-platform-owners
    - kind: ServiceAccount
      name: system:serviceaccount:capsule-system:platform-owner
```

### Namespace `tenant-alpha`

```yaml
metadata:
  name: tenant-alpha
  labels:
    capsule.clastix.io/tenant: alpha
    kustomize.toolkit.fluxcd.io/name: poc-capsule-spoke
    kustomize.toolkit.fluxcd.io/namespace: flux-system
  ownerReferences: []   # <-- empty! webhook should have populated this
```

### Mutating webhook `namespaces.tenants.projectcapsule.dev`

```yaml
clientConfig:
  service:
    name: capsule-webhook-service
    namespace: capsule-system
    port: 443
    path: /namespace-patch
failurePolicy: Ignore   # <-- silent failure mode suspect
matchPolicy: Equivalent
rules:
  - apiGroups: [""]
    apiVersions: ["v1"]
    operations: [CREATE]
    resources: [namespaces]
```

## Current Focus

**hypothesis:** Capsule v0.12.4 does NOT honor the Tenant CR's `spec.forceTenantPrefix: false` as an override of CapsuleConfiguration's `spec.forceTenantPrefix: true`. The mutating webhook's `failurePolicy: Ignore` masks any rejection — when the webhook decides the namespace name `tenant-alpha` doesn't match the prefix-enforced `alpha-*` pattern (per CapsuleConfiguration), it silently skips the mutation, leaving `ownerReferences` empty. The Tenant CR alpha then never claims the namespace, `status.size` stays 0, and no RoleBindings get created.

**alternative hypothesis 1:** Webhook is firing correctly but the Flux SA's identity (`system:serviceaccount:flux-system:flux-reconciler`) isn't being recognized as a tenant owner because the `spec.owners[]` entry uses SA-as-User format (`kind: ServiceAccount, name: system:serviceaccount:flux-system:flux-reconciler`) rather than the canonical `kind: ServiceAccount, name: flux-reconciler, namespace: flux-system` form. Capsule v0.12.4 may have tightened this comparison.

**alternative hypothesis 2:** Race condition between Tenant CR application and Namespace creation by Flux — the Tenant's owner-index may not be fully built when the Namespace is created, so Capsule's webhook doesn't recognize the namespace as belonging to alpha tenant.

**alternative hypothesis 3:** Capsule v0.12.4 chart upgrade or behavior change between 2026-05-19 (Phase 14) and 2026-05-27 — but the cluster pulls the exact same chart version (`ghcr.io/projectcapsule/capsule:v0.12.4`) and `pocs/capsule/spoke/config/capsuleconfig.yaml` hasn't changed (per `git log -- pocs/capsule/spoke/config/`).

**test:** Patch CapsuleConfiguration to `forceTenantPrefix: false` on the live cluster (won't survive Flux reconcile, but tests the override hypothesis). If Tenant alpha's `status.size` jumps to 1 and RoleBindings appear in `tenant-alpha`, hypothesis 1 is confirmed.

**expecting:** With `forceTenantPrefix: false` cluster-wide, Capsule should claim the labeled `tenant-alpha` namespace, populate ownerReferences, create RoleBindings, populate `Tenant.status.size`.

**next_action:** Run the test above (live patch of CapsuleConfiguration). If it works → root cause is the override semantic. If it doesn't → escalate to webhook logs (enable webhook payload logging or check capsule-controller-manager logs for webhook decision events on namespace CREATE).

**reasoning_checkpoint:** Phase 14 evidence is unambiguous that this worked on 2026-05-19. Either:
(a) Cluster environment differs (e.g., k3d/k3s version, host inotify/cgroup state) — but task rebuild + cold rebuild from same git HEAD should be hermetic
(b) Capsule's behavior changed in a way that's not version-pinned (e.g., a chart values default flipped between minor releases — but image SHA is pinned)
(c) Something in the Plan 15-04 cluster cascade silently corrupted the CapsuleConfiguration values that ARE on the cluster — worth comparing live state vs disk YAML

## Evidence

- timestamp: 2026-05-27T17:40Z | event: fresh cluster created (k3d-spoke-capsule) via create-cluster.sh; 3/3 preflight passed; SAN verified
- timestamp: 2026-05-27T17:41Z | event: register-poc-cluster.sh 11/11 passed; kubeconfig Secret applied to flux-system/spoke-capsule-kubeconfig; P18 silent-misroute falsifier GREEN
- timestamp: 2026-05-27T17:42Z | event: Flux reconcile chain: poc-capsule Ready, poc-capsule-spoke-rbac Ready, poc-capsule-spoke-tenants Ready, poc-capsule-spoke Ready
- timestamp: 2026-05-27T17:42Z | event: Tenant CRs alpha + bravo created; `STATE=Active`, `Ready=True`, `reason=Succeeded`, `message=reconciled`
- timestamp: 2026-05-27T17:42Z | event: Namespaces tenant-alpha + tenant-bravo created by Flux; have `capsule.clastix.io/tenant: alpha/bravo` label; empty `ownerReferences`
- timestamp: 2026-05-27T17:43Z | event: Tenant alpha `status.size: 0`, `status.namespaces: []` — Capsule has NOT claimed the namespaces
- timestamp: 2026-05-27T17:43Z | event: Zero RoleBindings in tenant-alpha; zero RoleBindings cluster-wide with `capsule.clastix.io/tenant` label
- timestamp: 2026-05-27T17:43Z | event: Tenant-owner alpha kubeconfig `kubectl get namespaces` returns empty (proxy LIST filter sees no managed ns for this owner)

## Eliminated

- hypothesis: Cluster recovery damage from Plan 15-04 cascade is the cause | eliminated: 2026-05-27 | reason: Bug reproduces on a true blank-slate `task destroy && task rebuild && create-cluster.sh && register-poc-cluster.sh` cold path. Not a cluster-recovery artifact.
- hypothesis: capsule-proxy pod is stale/needs restart | eliminated: 2026-05-27 | reason: `kubectl rollout restart deploy/capsule-proxy` didn't change the LIST result.
- hypothesis: capsule-controller-manager is stale/needs restart | eliminated: 2026-05-27 | reason: `kubectl rollout restart deploy/capsule-controller-manager` didn't change Tenant.status.size or trigger RoleBinding creation.
- hypothesis: Tenant CR was created in a damaged state | eliminated: 2026-05-27 | reason: Tenant alpha freshly deleted + Flux re-applied → same broken state. Tenant CR YAML on disk matches HEAD.
- hypothesis: Cluster restart bumps namespace ownership (k3d cluster stop/start) | eliminated: 2026-05-27 | reason: Stopping spoke-capsule for the rebuild test + restarting did NOT help; full cold rebuild still broken.

## Resolution

### Root Cause

**Upstream OCI chart at mutable tag `oci://ghcr.io/projectcapsule/charts/capsule:0.12.4` was repackaged between 2026-05-19 (Phase 14 GREEN) and 2026-05-27 (this debug session).** The new chart build (`+56638ab8bf45`) ships a stricter validation webhook (`namespaces.projectcapsule.dev`) that enforces label↔ownerReferences consistency on UPDATE/DELETE. Combined with the existing mutation webhook (`namespaces.tenants.projectcapsule.dev`) being configured with `failurePolicy: Ignore`, the cold-bootstrap path now has a fatal race:

1. Flux applies `tenant-alpha` namespace as `system:serviceaccount:flux-system:flux-reconciler`
2. The mutation webhook is briefly unreachable (Endpoint not yet ready, or kube-proxy not yet converged in k3d/WSL2). With `failurePolicy: Ignore`, the namespace is admitted **without the ownerRef mutation**
3. The Capsule controller's tenant reconciler skips this namespace because it has no ownerRefs claiming Tenant alpha → `status.size` stays 0
4. The validation webhook now blocks any UPDATE/DELETE of the unowned tenant-labeled namespace (the "Denied patch request for this namespace" + "namespace label \"alpha\" does not match owner reference \"\"" errors we hit during recovery attempts)
5. Flux retries on subsequent reconciles fail with the same denial; the cluster is in an unrecoverable webhook-deadlock state

**Why this didn't reproduce on Phase 14 (2026-05-19):** the prior chart build either (a) used `failurePolicy: Fail` for the mutation webhook (which would have caused the apply to retry until the webhook was reachable), (b) lacked the strict UPDATE-time validation that now blocks recovery, or (c) had different mutation logic that didn't require the requester identity to satisfy stricter checks. The chart was tag-pinned without a digest, so the upstream repackage was invisible to Flux.

### Fix (two-part)

**Part A — Immediate cluster recovery (no rebuild required):**

```bash
# Suspend Flux so it doesn't fight us
flux --context k3d-hub-flux suspend kustomization poc-capsule-spoke

# Strip the tenant label from the unowned ns (validation webhook only fires when label is present)
kubectl --context k3d-spoke-capsule label ns tenant-alpha capsule.clastix.io/tenant-
kubectl --context k3d-spoke-capsule label ns tenant-bravo capsule.clastix.io/tenant-

# Now delete is allowed (no label → no webhook denial)
kubectl --context k3d-spoke-capsule delete ns tenant-alpha tenant-bravo

# Resume Flux; it will re-create the namespaces. The webhook is now warm and the mutation will fire correctly this time.
flux --context k3d-hub-flux resume kustomization poc-capsule-spoke
flux --context k3d-hub-flux reconcile kustomization poc-capsule-spoke --timeout=2m
```

After this, `kubectl get tenant alpha -o jsonpath='{.status.size}'` should return `>0` and the demo should be GREEN.

**Part B — Permanent fix (prevent recurrence on every cold rebuild):**

1. **Pin both Capsule OCIRepositories by digest, not tag** (eliminates the silent upstream-repackage failure mode). Edit `pocs/capsule/operator/ocirepository.yaml` + `pocs/capsule/proxy/ocirepository.yaml`:
   ```yaml
   spec:
     ref:
       # OLD: tag: "0.12.4"  ← mutable; upstream repackage caused this regression
       # NEW: pin by digest (immutable)
       digest: sha256:<digest-from-last-known-good-build>
   ```
   Get the digest via: `crane manifest oci://ghcr.io/projectcapsule/charts/capsule:0.12.4 | jq -r '.config.digest'` (after recovering to known-good state) OR pin the current build's digest.

2. **Flip the namespaces mutation webhook `failurePolicy: Ignore → Fail`** in `pocs/capsule/operator/helmrelease.yaml`. The original D-08-03 / P26 belt-and-suspenders rationale was correct for MOST hooks (silent skip is safer than blocking unrelated operations), but for the namespace-claim webhook specifically, silent skip produces unrecoverable state. Surgical change:
   ```yaml
   webhooks:
     hooks:
       namespaces:
         failurePolicy: Fail   # was: Ignore — surgical override; other hooks keep Ignore
   ```

3. **Optional but recommended — add a healthCheck on capsule-webhook-service Endpoints to `poc-capsule-spoke` Kustomization** so Flux waits for the webhook to be ready before applying tenant namespaces. This adds a structural ordering guarantee on top of the failurePolicy fix.

### Verification

- `kubectl get tenant alpha -o jsonpath='{.status.size}'` returns `1` (claims tenant-alpha namespace)
- `kubectl get ns tenant-alpha -o jsonpath='{.metadata.ownerReferences[0].kind}'` returns `Tenant`
- `kubectl -n tenant-alpha get rolebindings` returns multiple RBs from spec.owners[]
- `kubectl --kubeconfig=$TO_ALPHA_KC get namespaces` returns only `tenant-alpha`
- Phase 14 demo flow GREEN end-to-end

### Files to change (Part B)

- `pocs/capsule/operator/ocirepository.yaml` — pin by digest
- `pocs/capsule/proxy/ocirepository.yaml` — pin by digest
- `pocs/capsule/operator/helmrelease.yaml` — flip namespace webhook failurePolicy to Fail
- `pocs/capsule/spoke/kustomization.yaml` (or the parent `poc-capsule-spoke` Kustomization spec) — add Endpoints healthCheck (optional)
- `docs/adr/0008-capsule-multi-tenancy-graduation.md` — append addendum noting the supply-chain finding (mutable-tag chart repackage caused a production-blocking regression — strong additional evidence for DEFER stance)

### Specialist review needed

- Confirm the upstream chart repackage via `crane manifest oci://ghcr.io/projectcapsule/charts/capsule:0.12.4` and compare to any digest captured in Phase 14 evidence
- Confirm that flipping namespace mutation webhook to `Fail` doesn't break the operator chart's own bootstrap (the webhook config is installed by the controller, which creates capsule-system NS first — but the namespace mutation hook fires on FUTURE namespaces, so this should be safe)
- Confirm digest-pinning works through Flux `OCIRepository` for ghcr.io (some registries normalize digests differently)

## Files Changed During Investigation

None — investigation was read-only. Cluster state probed with two temporary namespaces (`webhook-probe-alpha-2`, `webhook-probe-ssa`) that were cleaned up. One repair attempt failed (couldn't delete tenant-alpha because of the validation webhook deadlock — same broken state as session start, plus `poc-capsule-spoke` Kustomization now mid-retry).

## Files relevant to investigation

- `pocs/capsule/spoke/config/capsuleconfig.yaml` — CapsuleConfiguration source-of-truth on disk
- `pocs/capsule/spoke/tenant-crs/alpha.yaml` — Tenant CR alpha source-of-truth (has `forceTenantPrefix: false`)
- `pocs/capsule/spoke/tenant-crs/bravo.yaml` — Tenant CR bravo source-of-truth
- `pocs/capsule/spoke/tenants/alpha/namespace.yaml` — Namespace tenant-alpha source-of-truth
- `pocs/capsule/spoke/tenants/bravo/namespace.yaml` — Namespace tenant-bravo source-of-truth
- `pocs/capsule/operator/helmrelease.yaml` — Capsule operator HelmRelease (pins image to `capsule:0.12.4`)
- `pocs/capsule/proxy/helmrelease.yaml` — capsule-proxy HelmRelease
- `scripts/poc/capsule/create-cluster.sh` — cluster create script (idempotent)
- `scripts/register-poc-cluster.sh` — hub-flux registration script
- `.planning/phases/14-two-perspective-demo-verification-6-act-runbook-tls-noise-re/14-02-demo-live-evidence.log` — Phase 14 evidence proving demo worked on 2026-05-19
- `.planning/phases/11-validation-graduation-adr-008/11-07-SUMMARY.md` — D-11-07 forceTenantPrefix:false live repair documentation

## Open questions for the debugger agent

1. What was the exact CapsuleConfiguration cluster state on 2026-05-19 when Phase 14 evidence was captured? Was `forceTenantPrefix: false` set at the CapsuleConfiguration level then? (`git log -p` on the YAML, plus any historical cluster snapshots.)
2. Does Capsule v0.12.4's `Tenant.spec.forceTenantPrefix` actually override `CapsuleConfiguration.spec.forceTenantPrefix`? Check Capsule docs + source for v0.12.4.
3. What does `kubectl auth can-i create namespaces --as=system:serviceaccount:flux-system:flux-reconciler` return on this cluster? Is the Flux SA recognized as a tenant owner by Capsule's webhook?
4. Are the Flux Kustomization apply ordering guarantees actually maintained? `poc-capsule-spoke-tenants` Kustomization applies Tenant CRs AND Namespaces — what's the ordering within a single Kustomization? Should Tenant CR creation be a separate Kustomization that completes before Namespace Kustomization runs?
5. Is there a Capsule controller log entry showing the webhook DECISION for the namespace CREATE? Need to enable verbose webhook logging or look for the specific event.

## Cross-references

- Plan 15-04 retry-2 SUMMARY: `.planning/phases/15-v0-20-milestone-close-out-retrospective/15-04-SUMMARY.md` — surfaced the architectural worktree-vs-rebuild conflict and the cluster-recovery cascade
- Plan 12-01 SUMMARY: `.planning/milestones/v0.19-phases/12-v0-19-close-out-reconciliation/12-01-SUMMARY.md` — D-11-07 TEN-01 forceTenantPrefix:false REQUIREMENTS amendment
- ADR-008: `docs/adr/0008-capsule-multi-tenancy-graduation.md` — POC graduation = DEFER framing (this bug confirms why)
