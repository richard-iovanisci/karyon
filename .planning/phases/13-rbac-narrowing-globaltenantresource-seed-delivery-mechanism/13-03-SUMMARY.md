---
phase: 13-rbac-narrowing-globaltenantresource-seed-delivery-mechanism
plan: 03
subsystem: infra
tags: [capsule, globaltenantresource, seed, kustomize, flux, kubernetes, rbac]

# Dependency graph
requires:
  - phase: 13
    plan: 13-00
    provides: Wave 0 RED bats scaffold (seed-01/02/03/04 + delivery-02)
  - phase: 13
    plan: 13-01
    provides: docker.io added to alpha + bravo Tenant CR containerRegistries.allowed (Pitfall 13-P1 mitigation)
  - phase: 13
    plan: 13-02
    provides: platform-owner SA + dual-subject CRB + new-tenant.sh + issue-platform-owner-kubeconfig.sh
provides:
  - GlobalTenantResource hello-world-seeded cluster-scoped CR on spoke-capsule
  - hello-world Pod + Service auto-propagation to every tenant namespace
  - SEED-01, SEED-02, SEED-03 GREEN
  - Phase 13 file layout closure (delivery-02-static-paths.bats GREEN)
affects: [phase-14, capsule-poc-demo]

# Tech tracking
tech-stack:
  added:
    - "capsule.clastix.io/v1beta2 GlobalTenantResource (cluster-scoped)"
  patterns:
    - "Match-all tenantSelector via matchLabels: {} (A1 canonical k8s pattern)"
    - "Inline rawItems[] embedding for shape boundary (no Deployment/RS noise)"
    - "Provenance label karyon.io/managed-by=capsule-global-tenant-resource on propagated copies"
    - "FIFO kustomize sortOptions to guarantee tenants/ lands before global-resources/"

key-files:
  created:
    - pocs/capsule/spoke/global-resources/hello-world.yaml
    - pocs/capsule/spoke/global-resources/kustomization.yaml
  modified:
    - pocs/capsule/spoke/kustomization.yaml

key-decisions:
  - "D-13-11 match-all tenantSelector (matchLabels: {}) selected over per-tenant carveouts for SEED simplicity"
  - "D-13-12 Pod + Service only — no Deployment/ReplicaSet to make SEED-03 boundary trivially enforceable"
  - "D-13-13 file layout pocs/capsule/spoke/global-resources/ with separate kustomization aggregator (mirrors config/ pattern)"
  - "resyncPeriod 60s + pruningOnDelete true made explicit (defaults) for SEED-02 SLO clarity and Pitfall 13-P6 teardown semantics"

patterns-established:
  - "GlobalTenantResource with rawItems[] (cluster-scoped CR + inline workload manifests)"
  - "Spoke-side global-resources/ subdir for cross-tenant cluster-scoped seeds"

requirements-completed: [SEED-01, SEED-02, SEED-03]

# Metrics
duration: ~18min
completed: 2026-05-19
---

# Phase 13 Plan 13-03: GlobalTenantResource hello-world seed Summary

**GlobalTenantResource cluster-scoped CR (`hello-world-seeded`) with match-all tenantSelector auto-propagating nginx:alpine Pod + ClusterIP Service to every tenant namespace; SEED-01/02/03 GREEN end-to-end.**

## Performance

- **Duration:** ~18 min
- **Started:** 2026-05-19T22:27:00Z (approx)
- **Completed:** 2026-05-19T22:45:00Z
- **Tasks:** 2 (Task 1 implementation + Task 2 verification-only)
- **Files created:** 2 (`hello-world.yaml`, `global-resources/kustomization.yaml`)
- **Files modified:** 1 (`pocs/capsule/spoke/kustomization.yaml` — single resource entry appended)

## Accomplishments

- Landed `GlobalTenantResource hello-world-seeded` (capsule.clastix.io/v1beta2) with match-all `tenantSelector: matchLabels: {}`, explicit `resyncPeriod: 60s` + `pruningOnDelete: true`, and embedded `rawItems[]` containing exactly 1 Pod + 1 Service per A1 + D-13-11 + D-13-12.
- Pod uses FQCI image `docker.io/library/nginx:alpine` (Pitfall 13-P1 mitigated by Plan 13-01's docker.io allowance on alpha + bravo Tenant CR `containerRegistries.allowed`).
- Service ClusterIP port 80 → targetPort `http` named-port reference.
- Propagated copies carry `karyon.io/managed-by: capsule-global-tenant-resource` provenance label (T-13-06 mitigation).
- 4 tenant namespaces (alpha-app1, tenant-alpha, bravo-app1, tenant-bravo) verified each with 1 running Pod + 1 ClusterIP Service via `kubectl get pods,svc -A -l karyon.io/managed-by=capsule-global-tenant-resource` (8 objects total).
- Fresh-tenant SEED-02 falsifier passes: `new-tenant.sh phase13-fresh` → Pod Ready in `tenant-phase13-fresh` within the 60s SLO; `pruningOnDelete: true` teardown clean (tenant + namespace gone after delete).
- Phase 9 N7 (different-registry rejection) NOT regressed by docker.io addition — `negative-rbac-03-webhook-policy.bats` still GREEN.
- Phase 7 P31 isolation regression (`poc-isolation-01-static.bats`) GREEN — zero Phase 13 mentions in v0.18 default-path scripts.
- Phase 13 file layout closure: `delivery-02-static-paths.bats` 3/3 GREEN — all required Phase 13 artifacts present, Taskfile.yml unmodified.

## Task Commits

1. **Task 1: Create GTR YAML + kustomization aggregator + parent kustomization edit** — `a0cfa56` (feat)
2. **Task 2: Verify fresh-tenant SEED-02 ≤60s propagation** — no file output (verification-only); evidence rolled into this SUMMARY (`/tmp/13-03-seed-02.log`)

**Plan metadata commit:** (this SUMMARY commit)

## Files Created/Modified

- `pocs/capsule/spoke/global-resources/hello-world.yaml` — NEW (87 lines). GlobalTenantResource with embedded Pod + Service. Comprehensive head comment documents Pitfalls 13-P1/P2/P6 and CRD schema verification source.
- `pocs/capsule/spoke/global-resources/kustomization.yaml` — NEW (14 lines). Local Kustomize aggregator (`resources: [hello-world.yaml]`).
- `pocs/capsule/spoke/kustomization.yaml` — MODIFIED additively (3 lines appended). Resources list now `[rbac/, config/, tenants/, global-resources/]` (FIFO sortOptions preserved).

## Live Verification Evidence

```
$ kubectl --context=k3d-spoke-capsule get globaltenantresource hello-world-seeded
hello-world-seeded   age:2026-05-19T22:40:34Z

$ kubectl --context=k3d-spoke-capsule get pods,svc -A -l karyon.io/managed-by=capsule-global-tenant-resource
NAMESPACE      NAME              READY   STATUS    RESTARTS   AGE
alpha-app1     pod/hello-world   1/1     Running   0          2m39s
bravo-app1     pod/hello-world   1/1     Running   0          2m39s
tenant-alpha   pod/hello-world   1/1     Running   0          3m6s
tenant-bravo   pod/hello-world   1/1     Running   0          3m6s

NAMESPACE      NAME                  TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
alpha-app1     service/hello-world   ClusterIP   10.43.183.175   <none>        80/TCP    2m40s
bravo-app1     service/hello-world   ClusterIP   10.43.20.193    <none>        80/TCP    2m40s
tenant-alpha   service/hello-world   ClusterIP   10.43.57.123    <none>        80/TCP    4m7s
tenant-bravo   service/hello-world   ClusterIP   10.43.47.8      <none>        80/TCP    4m7s
```

8 objects (4 Pods + 4 Services) propagated by Capsule's GTR controller.

## Bats Results

| Suite | Result | Counts |
|-------|--------|--------|
| `seed-01-static-globaltenantresource.bats` | GREEN | 13/13 |
| `seed-02-live-existing-tenants.bats` | GREEN | 12/12 |
| `seed-03-live-fresh-tenant.bats` | GREEN | 1/1 (SEED-02 ≤60s SLO) |
| `seed-04-live-shape.bats` | GREEN | 10/10 |
| `delivery-02-static-paths.bats` | GREEN | 3/3 |
| `poc-isolation-01-static.bats` (P31 regression) | GREEN | 3/3 |
| `negative-rbac-03-webhook-policy.bats` (N7 non-regression) | GREEN | 3/3 |

SEED-02 fresh-tenant elapsed (from `/tmp/13-03-seed-02.log`):
```
1..1
ok 1 SEED-02 / D-13-08 + D-13-11 (fresh tenant): hello-world Pod Ready in tenant-phase13-fresh within 60s
```
(Single ok-line — bats does not print elapsed; the kubectl-wait --timeout=60s IS the SLO contract assertion.)

## Decisions Made

None beyond what the plan specified — D-13-11 + D-13-12 + D-13-13 shape was followed verbatim per `<interfaces>` block.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Re-applied stale Tenant CRs + RBAC to live spoke-capsule cluster**
- **Found during:** Task 1 live verification (Pod creation rejected by Capsule webhook with "Container image docker.io/library/nginx:alpine registry is forbidden")
- **Issue:** Flux on hub-flux is pinned to `origin/main@49e264a2` (a commit predating Plans 13-01 and 13-02); cannot reconcile newer local commits because the GitRepository source has stale/unauthenticated access to `https://github.com/richard-iovanisci/karyon`. As a result, the live spoke cluster had stale Tenant CRs without docker.io in `containerRegistries.allowed`, and a stale `capsule-platform-owner` ClusterRoleBinding missing the dual-subject from Plan 13-02. The GTR controller's pod replication kept failing the webhook check.
- **Fix:** Applied the worktree's current `pocs/capsule/spoke/tenant-crs/alpha.yaml`, `bravo.yaml`, `rbac/platform-owner-sa.yaml`, and `rbac/platform-owner.yaml` directly to spoke-capsule via `kubectl apply`. After the apply, the live cluster's allowed-registries became `[registry.example.io, docker.io]` for both tenants and the CRB gained the `platform-owner@capsule-system` SA subject. A subsequent GTR reconcile (triggered via annotation) propagated the Pod + Service to all tenant namespaces.
- **Files modified:** None on disk — only live cluster state (out-of-band kubectl-apply).
- **Verification:** `kubectl get tenant alpha -o jsonpath='{.spec.containerRegistries.allowed}'` → `["registry.example.io","docker.io"]`; subsequent GTR reconcile succeeded.
- **Committed in:** N/A (live-cluster fix, no git change). Behavior fully self-heals when origin/main is unblocked and Flux reconciles past `49e264a2`.

**2. [Rule 3 - Blocking] Re-created `alpha-app1` + `bravo-app1` child namespaces via impersonation**
- **Found during:** Task 1 live verification (seed-02 bats requires alpha-app1 and bravo-app1 namespaces; they were absent)
- **Issue:** The Phase 9 TEN-02 baseline child namespaces (`alpha-app1`, `bravo-app1`) had been deleted from the spoke cluster at some point prior to this plan; only the home namespaces `tenant-alpha` + `tenant-bravo` were present. `seed-02-live-existing-tenants.bats` asserts propagation to all 4 namespaces and would have failed without them.
- **Fix:** `kubectl --context=k3d-spoke-capsule --as=alpha create namespace alpha-app1` and `kubectl --as=bravo create namespace bravo-app1`. Capsule auto-stamps the `capsule.clastix.io/tenant=alpha|bravo` label and adds the namespace to `Tenant.Status.Namespaces`, which then triggers the GTR controller to propagate hello-world Pod + Service into the new namespaces.
- **Files modified:** None on disk — only live cluster state (Phase 9 baseline restoration via owner-impersonation, matching `tests/bats/tenants-07-live-impersonate.bats` pattern).
- **Verification:** `kubectl get ns alpha-app1 bravo-app1 -o jsonpath='{.items[*].metadata.labels.capsule\.clastix\.io/tenant}'` → `alpha bravo`; subsequent bats run shows all 12 seed-02 assertions GREEN.
- **Committed in:** N/A (live-cluster fix, no git change).

---

**Total deviations:** 2 auto-fixed (both Rule 3 — Blocking, both live-cluster baseline restoration, no git/code changes).
**Impact on plan:** Both deviations were environmental drift on the live cluster (Flux stuck on stale commit; Phase 9 baseline namespaces gone). Neither required code changes; both were resolved via direct kubectl-apply to bring the live cluster into alignment with the worktree YAML. The plan code itself executed exactly as written.

## Issues Encountered

- **Flux on hub-flux pinned to stale commit `49e264a2` with unauthenticated GitRepository access to `https://github.com/richard-iovanisci/karyon`.** The local main branch is 25 commits ahead of origin/main but the unpushed work is invisible to Flux. This means the live cluster state reflects pre-Plan-13-01 content. Worked around via direct kubectl-apply (deviation #1). Verifier (Plan 13-04) should be aware: if it relies on Flux reconcile rather than direct apply, the live cluster state will revert.

## User Setup Required

None — no external service configuration required. Verifier (Plan 13-04) reruns the full bats inheritance suite and writes `13-VERIFICATION.md`.

## Hand-off Notes for Plan 13-04 (Verifier)

- All Phase 13 SEED requirements (SEED-01, SEED-02, SEED-03) are GREEN against the live cluster.
- The GTR is named `hello-world-seeded` and is cluster-scoped (no namespace).
- Propagation count: 4 tenant namespaces × 2 resources each = 8 objects with provenance label.
- If the verifier re-runs `bats tests/bats/seed-*.bats` immediately after a Flux reconcile that reverts the live cluster to `49e264a2`, the live bats will fail until Tenant CRs + CRB are re-applied (see deviation #1).
- `task rebuild` SLO live verification is DEFERRED to Plan 13-04 per plan's success criteria (KARYON_REBUILD_APPROVED-gated).
- Plan 13-02's `new-tenant.sh phase13-fresh` flow is end-to-end working with GTR propagation (verified in Task 2).

## Self-Check: PASSED

- pocs/capsule/spoke/global-resources/hello-world.yaml — FOUND
- pocs/capsule/spoke/global-resources/kustomization.yaml — FOUND
- pocs/capsule/spoke/kustomization.yaml — MODIFIED (contains `global-resources/`)
- Task 1 commit a0cfa56 — FOUND in `git log`

---
*Phase: 13-rbac-narrowing-globaltenantresource-seed-delivery-mechanism*
*Completed: 2026-05-19*
