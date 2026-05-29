---
slug: capsule-tenant-ns-claim
status: resolved
trigger: capsule-tenant-namespace-claim-regression
created: 2026-05-27
updated: 2026-05-27
resolved: 2026-05-27
tags: [capsule, multi-tenancy, webhook, ownership, failure-policy, v0.20]
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

### Root Cause (empirically proven; supersedes the earlier "upstream repackage" draft)

> **CORRECTION (2026-05-27, post-fix):** A mid-investigation draft of this section blamed an upstream
> chart repackage. That hypothesis was DISPROVEN — the chart build `+56638ab8bf45` dates 2025-12-19 and
> is stable; digest pinning confirmed zero drift. A controlled `helm template --set` experiment + a live
> A/B on the cluster proved the true cause is a repo-side webhook-policy weakening. Corrected analysis:

**The repo's `pocs/capsule/operator/helmrelease.yaml` (Phase 8 D-08-03, "P26 belt-and-suspenders") set
`webhooks.hooks.namespaces.failurePolicy: Ignore`, overriding the Capsule chart DEFAULT of `Fail` for
the `namespaces.tenants.projectcapsule.dev` mutating webhook** — the hook that ADDS the `ownerReference`
claiming a tenant-labeled namespace for its Tenant CR. The cold-bootstrap race:

1. Flux applies `tenant-alpha` namespace as `system:serviceaccount:flux-system:flux-reconciler`.
2. The mutation webhook is briefly unreachable (capsule-webhook-service Endpoint not yet Ready after the
   controller starts). With `failurePolicy: Ignore`, the apiserver's failed admission call is ignored and
   the namespace is admitted **without the ownerRef mutation**. (Chart default `Fail` would have REJECTED
   the CREATE → Flux retries until the webhook serves → self-heals.)
3. The Capsule reconciler skips the namespace because it has no ownerRefs claiming Tenant alpha →
   `status.size` stays 0, no RoleBindings.
4. The validating webhook `namespaces.projectcapsule.dev` (chart default `Fail`) then blocks every
   UPDATE/DELETE on the labeled-but-unowned namespace ("namespace label \"alpha\" does not match owner
   reference \"\"").
5. Cluster is in an unrecoverable webhook-deadlock until the webhook is bypassed (scale controller to 0).

**Controlled experiment proving `namespaces` is the controlling chart value key:**
```
helm template ... --set webhooks.hooks.namespaces.failurePolicy=Ignore     => webhook = Ignore
helm template ... --set webhooks.hooks.namespacePatch.failurePolicy=Ignore => webhook = Fail (no-op key)
```
Live A/B: repo `namespaces: Ignore` → live webhook `Ignore` (bug); fix `namespaces: Fail` → live `Fail` (closed).

**Why this didn't reproduce on Phase 14 (2026-05-19):** the race is timing-dependent. Under `Ignore`,
whether the silent-skip happens depends on the webhook-readiness window vs Flux's namespace-apply timing.
Phase 14's cold rebuild won the dice roll. The bug was always latent under `Ignore` — not an upstream change.

**Other earlier claims corrected:** (a) the Flux dependency edge was NOT missing — `poc-capsule-spoke`
already `dependsOn` `poc-capsule`; ordering was never the gap. (b) The repo's `webhooks.hooks` keys are
NOT bogus — they are valid chart keys; D-08-03 weakened ~13 of them from chart-default `Fail` to `Ignore`,
and only the `namespaces` one carried the unrecoverable-deadlock failure mode.

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

**Part B — Permanent fix. APPLIED + VERIFIED LIVE in commit `c89f1b2`; written-record correction in the follow-up commit.**

1. **[PRIMARY FIX] Flip `webhooks.hooks.namespaces.failurePolicy` `Ignore → Fail`** in
   `pocs/capsule/operator/helmrelease.yaml`. This RESTORES the Capsule chart default; D-08-03's P26
   belt-and-suspenders had weakened it. With `Fail`, a webhook-unavailable window at cold-bootstrap causes
   the namespace CREATE to be REJECTED, so Flux retries until the webhook serves — self-healing, no silent
   skip. Surgical: only the `namespaces` hook flips; the other ~13 keep their D-08-03 `Ignore` posture.
   ```yaml
   webhooks:
     hooks:
       namespaces:
         failurePolicy: Fail   # was: Ignore (D-08-03) — restores chart default; surgical, others keep Ignore
   ```
   **Verified live:** `mutatingwebhookconfiguration .../namespaces.tenants.projectcapsule.dev
   failurePolicy` = `Fail`; tenant claim restored.

2. **[SECONDARY hardening] Pin both Capsule OCIRepositories by digest** (`operator/ocirepository.yaml` +
   `proxy/ocirepository.yaml`). NOT the root cause (chart never repackaged — stable build 2025-12-19), but
   good supply-chain hygiene: reproducible reconcile even if upstream re-tags. Digests from
   `kubectl -n capsule-system get ocirepository <name> -o jsonpath='{.status.artifact.revision}'`:
   - capsule:       `sha256:56638ab8bf455c5a1f5cf581c474681147cfe7031a0ff902a42c3715f0011fb7`
   - capsule-proxy: `sha256:0b8c6ef4a74425c8bd4c0e383cf1847042580ca4071db2ed07b3c26bc0b0d02d`

3. **[NOT NEEDED] healthCheck / dependsOn ordering** — investigated and rejected. `poc-capsule-spoke`
   already `dependsOn` `poc-capsule`; a hub-targeted Kustomization can't health-check a spoke Deployment
   under ADR-004; and with `failurePolicy: Fail` the webhook self-heals via apiserver-reject + Flux-retry,
   so no extra ordering machinery is required.

### Verification (live, 2026-05-27 — all GREEN)

- `mutatingwebhookconfiguration .../namespaces.tenants.projectcapsule.dev failurePolicy` = `Fail`
- `Tenant alpha status.size` = 1, `status.namespaces` = `["tenant-alpha"]`; bravo identical
- `ns/tenant-alpha ownerReferences[0]` = `Tenant/alpha`; bravo = `Tenant/bravo`
- 11 RoleBindings auto-created in each tenant namespace
- Demo dry-run GREEN: Act2a (platform-owner LIST = alpha+bravo), Act2b (`auth can-i '*' '*'` = no),
  Act5a (tenant-owner LIST = only own ns), Act5d (cross-tenant = Forbidden), tenant ceiling (`no`)

### Recovery runbook (if the deadlock recurs on a cluster that predates the fix)

```bash
flux --context k3d-hub-flux suspend kustomization poc-capsule-spoke
kubectl --context k3d-spoke-capsule -n capsule-system scale deploy capsule-controller-manager --replicas=0
kubectl --context k3d-spoke-capsule delete ns tenant-alpha tenant-bravo --wait=true
kubectl --context k3d-spoke-capsule -n capsule-system scale deploy capsule-controller-manager --replicas=1
kubectl --context k3d-spoke-capsule -n capsule-system rollout status deploy/capsule-controller-manager
flux --context k3d-hub-flux resume kustomization poc-capsule-spoke
flux --context k3d-hub-flux reconcile kustomization poc-capsule-spoke --timeout=2m
```

### Files changed by the fix (commit c89f1b2)

- `pocs/capsule/operator/helmrelease.yaml` — `namespaces` webhook `failurePolicy: Ignore → Fail` (PRIMARY)
- `pocs/capsule/operator/ocirepository.yaml` — pin by digest (hardening)
- `pocs/capsule/proxy/ocirepository.yaml` — pin by digest (hardening)
- `docs/adr/0008-capsule-multi-tenancy-graduation.md` — addendum documenting the finding + DEFER reinforcement

### Residual / future (v0.21 candidates, non-blocking)

- Audit the other ~12 D-08-03 `Ignore` overrides — any others masking a recoverable-only-via-bypass mode?
  (`namespaces` was the dangerous one; the rest are likely fine for a POC.)
- A true cold-rebuild test (`task destroy && task rebuild && create-cluster.sh && register-poc-cluster.sh`)
  with the fix in place would prove non-recurrence end-to-end. Not run today (cluster green + demo-ready;
  another destroy was not warranted).

## Files Changed During Investigation

Investigation itself was read-only. Live cluster operations during recovery + fix verification:
temporary probe namespaces (cleaned up), the Part A recovery sequence (scale-controller-to-0 + delete
orphan ns + resume Flux — restored the cluster), and the Flux reconcile that applied commit `c89f1b2`'s
HelmRelease values (rolled the namespaces webhook to `Fail`). Repo files changed are listed under "Files
changed by the fix" above.

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
