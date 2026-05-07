---
phase: 11-validation-graduation-adr-008
plan: 07
purpose: G-06 root-cause empirical evidence (codex review §2 MEDIUM #4 closure)
created: 2026-05-06
captured_by: operator (Task 6 human-verify checkpoint)
captured_at: TBD-FILLED-DURING-TASK-6
---

# G-06 Root-Cause Empirical Evidence

**Why this file exists:** Codex review §2 MEDIUM #4 (.planning/phases/11-validation-graduation-adr-008/11-REVIEWS.md L127-128) flagged that "context deadline exceeded" has multiple plausible causes (RBAC, namespace missing, network, hook Job timeout, CRD readiness, chart hook failure). Plan 11-07 declares helm-controller impersonation is the root cause and ships the spec.serviceAccountName fix. This file captures empirical evidence BEFORE declaring G-06 closed so the impersonation-RBAC hypothesis is bound to observable data, not just code-side reasoning.

## Hypothesis Under Test

**G-06 root cause hypothesis:** When a HelmRelease has `spec.kubeConfig` (cross-cluster) but NO `spec.serviceAccountName`, helm-controller defaults to impersonating `system:serviceaccount:capsule-system:default` on the TARGET cluster (spoke-capsule). The `default` SA in capsule-system has zero RBAC, so helm install/upgrade requests fail with `context deadline exceeded`.

**Falsifier:** If helm-controller logs show `forbidden` errors on apiserver requests (impersonation succeeded but the impersonated SA had no perms), hypothesis CONFIRMED. If logs show network/DNS errors or no impersonation attempt at all, hypothesis FALSIFIED — root cause is something else.

## PRE-PUSH Evidence Capture

(Operator: capture these BEFORE pushing the Plan 11-07 commits, so we have the RED baseline.)

### A. HelmRelease state pre-fix

```bash
flux get hr -n capsule-system --context=k3d-hub-flux
# expected: capsule + capsule-proxy show NotReady with reason "context deadline exceeded"
```

Captured output (TBD):

```text
TBD — paste output here
```

### B. helm-controller logs around the timeout

```bash
kubectl --context=k3d-hub-flux -n flux-system logs deploy/helm-controller --tail=200 \
  | grep -iE 'capsule|impersonat|forbidden|deadline|context'
```

Captured output (TBD):

```text
TBD — paste output here
```

### C. HR-related events on hub

```bash
kubectl --context=k3d-hub-flux -n capsule-system get events --sort-by='.lastTimestamp' \
  | grep -iE 'helmrelease|capsule|forbidden|deadline'
```

Captured output (TBD):

```text
TBD — paste output here
```

### D. SA existence on spoke (proves the impersonation target was missing pre-fix)

```bash
kubectl --context=k3d-spoke-capsule -n capsule-system get sa
# expected: only "default" SA; "helm-controller" absent
```

Captured output (TBD):

```text
TBD — paste output here
```

### E. SAR check for default SA on spoke (proves zero RBAC pre-fix)

```bash
kubectl --context=k3d-spoke-capsule auth can-i create deployments \
  --namespace=capsule-system \
  --as=system:serviceaccount:capsule-system:default
# expected: "no"

kubectl --context=k3d-spoke-capsule auth can-i create secrets \
  --namespace=capsule-system \
  --as=system:serviceaccount:capsule-system:default
# expected: "no"
```

Captured output (TBD):

```text
TBD — paste output here
```

## POST-PUSH Evidence Capture

(Operator: capture these AFTER pushing Plan 11-07 commits and waiting 2-3 min for Flux reconcile.)

### F. HelmRelease state post-fix

```bash
flux get hr -n capsule-system --context=k3d-hub-flux
# expected: capsule + capsule-proxy BOTH Ready=True (NOT context deadline exceeded)
```

Captured output (TBD):

```text
TBD — paste output here
```

### G. SA existence on spoke post-fix

```bash
kubectl --context=k3d-spoke-capsule -n capsule-system get sa helm-controller
kubectl --context=k3d-spoke-capsule get clusterrolebinding helm-controller-cluster-admin
# expected: both exist (provisioned by Flux apply of pocs/capsule/spoke/rbac/ via
# the new poc-capsule-spoke-rbac Kustomization)
```

Captured output (TBD):

```text
TBD — paste output here
```

### H. SAR check for helm-controller SA on spoke post-fix

```bash
kubectl --context=k3d-spoke-capsule auth can-i '*' '*' \
  --as=system:serviceaccount:capsule-system:helm-controller
# expected: "yes" (cluster-admin via helm-controller-cluster-admin CRB)
```

Captured output (TBD):

```text
TBD — paste output here
```

### I. helm-controller logs post-fix

```bash
kubectl --context=k3d-hub-flux -n flux-system logs deploy/helm-controller --tail=200 \
  | grep -iE 'capsule|impersonat|forbidden|deadline|context'
# expected: previous "context deadline exceeded" errors STOP appearing; new entries
# should show successful chart install (or a DIFFERENT failure mode if hypothesis was wrong)
```

Captured output (TBD):

```text
TBD — paste output here
```

## Hypothesis Disposition

(Operator: fill in after PRE + POST captures.)

- [ ] PRE-PUSH evidence shows: TBD (impersonation default to `default` SA / network / other)
- [ ] POST-PUSH evidence shows: TBD (Ready=True / different failure mode)
- [ ] Hypothesis: TBD (CONFIRMED / FALSIFIED / PARTIALLY-CONFIRMED)

If hypothesis is CONFIRMED: G-06 closure landed. Update Plan 11-06 SUMMARY disposition to `passed` per Task 6.

If hypothesis is FALSIFIED: G-06 fix did NOT close the timeout. Operator must:
1. Document the observed root cause in this file
2. NOT update Plan 11-06 disposition to `passed`
3. Open a follow-up plan (11-08) addressing the actual root cause
4. Update Plan 11-04 11-VERIFICATION.md to record the falsified hypothesis

If hypothesis is PARTIALLY CONFIRMED (e.g., the SA fix DID close one of two failure modes; the other has a different root cause):
1. Document both observations in this file
2. Update Plan 11-06 disposition to `passed_with_overrides`
3. Open a follow-up plan addressing the residual root cause

## Cross-Reference

- 11-REVIEWS.md §2 MEDIUM #4 (the original codex concern this file addresses)
- 11-VERIFICATION.md HARD-GATE 1 (the chart-rendered Role propagation gate that depends on G-06 being closed)
- 11-06-SUMMARY.md "Awaiting" section (Task 3 verification preconditions)
- 11-07-PLAN.md Task 1 sub-step 1.1-1.10 (the static landings whose effectiveness this file empirically verifies)
- ADR-008 § DEFER outcome (carryover items list — G-06 closure is a precondition for transitioning ADR-008 from DEFER to ADOPT in v0.20+)
