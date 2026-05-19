---
plan: 13-01
status: complete
completed: 2026-05-19
tasks_completed: 2
tasks_total: 2
requirements: [RBAC-01, RBAC-02, RBAC-03]
---

# Plan 13-01 SUMMARY — Tier 3 RBAC Narrowing

## Objective Recap

Land the Tier 3 (tenant-developer) RBAC artifacts:
- New `tenant-workload-editor` ClusterRole (narrower than upstream k8s `edit`; per D-13-04 grant matrix).
- Per-tenant `human-tenant-owner` ServiceAccounts in `tenant-alpha` + `tenant-bravo` namespaces.
- Additive Tenant CR `spec.owners[]` entries binding human SAs to the new ClusterRole (explicit `clusterRoles: [tenant-workload-editor]` per D-13-05; Pitfall 13-P8 non-empty).
- Additive `docker.io` to `containerRegistries.allowed[]` on both Tenant CRs (Pitfall 13-P1 — required for Plan 13-03 FQCI nginx Pod propagation by GlobalTenantResource).
- Minor `issue-tenant-kubeconfig.sh` hint expansion (Usage block + fail-fast SA enumeration) to mention `human-tenant-owner` alongside existing `gitops-reconciler`.

## Tasks Completed

### Task 1 — ClusterRole + per-tenant human-owner SAs + kustomization edits — `203cadb`

Landed:
- `pocs/capsule/spoke/rbac/tenant-workload-editor.yaml` — NEW ClusterRole. D-13-04 grant matrix complete:
  - Pods CRUD + log/exec/portforward subresources
  - Workload lifecycle (apps + batch: deployments, replicasets, statefulsets, daemonsets, jobs, cronjobs CRUD)
  - Service exposure (services, endpoints, endpointslices CRUD)
  - ConfigMaps CRUD
  - Storage refs (PVC read-only — get/list/watch)
  - Events read-only (`""` + `events.k8s.io`)
  - **Secrets read-only ONLY** per D-13-01 (no create/update/patch/delete)
  - No `rbac.authorization.k8s.io/aggregate-to-*` label (Pitfall 13-P3 — would silently inherit upstream `edit` Secret CUD)
- `pocs/capsule/spoke/tenants/alpha/human-owner-sa.yaml` — NEW SA in `tenant-alpha` namespace.
- `pocs/capsule/spoke/tenants/bravo/human-owner-sa.yaml` — NEW SA in `tenant-bravo` namespace (mirror).
- `pocs/capsule/spoke/rbac/kustomization.yaml` — EDITED: appended `tenant-workload-editor.yaml` to `resources[]` (after existing `platform-owner.yaml`; `namespace.yaml` preserved FIRST per Phase 11 G-06 codex review §2 HIGH #1).
- `pocs/capsule/spoke/tenants/alpha/kustomization.yaml` — EDITED: appended `human-owner-sa.yaml` after `sa.yaml` (sortOptions.order: fifo preserved).
- `pocs/capsule/spoke/tenants/bravo/kustomization.yaml` — EDITED: mirror of alpha.

### Task 2 — Tenant CR human-owner co-ownership + docker.io allowlist + script hint expansion — `6e91216`

Landed:
- `pocs/capsule/spoke/tenant-crs/alpha.yaml` — EDITED additively:
  - Appended `system:serviceaccount:tenant-alpha:human-tenant-owner` SA owner entry to `spec.owners[]` with **explicit** `clusterRoles: [tenant-workload-editor]` (D-13-05; Pitfall 13-P8 non-empty array). Capsule v0.12.4 will auto-inject a `capsule-alpha-<index>-tenant-workload-editor` RoleBinding per tenant namespace on next reconcile.
  - Appended `docker.io` to `spec.containerRegistries.allowed[]` (Pitfall 13-P1; required before Plan 13-03 GTR Pod uses `docker.io/library/nginx:alpine`).
  - **No existing entries removed or reordered.** flux-system/flux-reconciler SA + tenant-alpha/gitops-reconciler SA + User alpha entries preserved character-for-character (RBAC-03 regression gate).
- `pocs/capsule/spoke/tenant-crs/bravo.yaml` — EDITED additively (mirror).
- `scripts/poc/capsule/issue-tenant-kubeconfig.sh` — EDITED (HINT-ONLY):
  - Usage block `<owner>` description expanded to enumerate both SA names.
  - Fail-fast hint at line ~175 expanded from "currently only 'gitops-reconciler'" to "currently 'gitops-reconciler' or 'human-tenant-owner' — Phase 13 RBAC-02 default".
  - **All other script logic preserved verbatim** — `set -euo pipefail`, REPO_ROOT pinning, preflight-lib source, shadowed helpers (Pitfall 10-P7 stdout/stderr contract), TokenRequest mint, TLS embed via `tls.crt` (Pitfall 10-P1), kubeconfig heredoc, `--write-to` realpath check, `--duration` flag handling. Phase 10 PROXY-01..03 contract intact.

## Key Artifacts

| Path | Type | Purpose |
|------|------|---------|
| `pocs/capsule/spoke/rbac/tenant-workload-editor.yaml` | NEW | D-13-04 ClusterRole — narrower than upstream k8s `edit` |
| `pocs/capsule/spoke/tenants/alpha/human-owner-sa.yaml` | NEW | Per-tenant SA (RBAC-01 binding target) |
| `pocs/capsule/spoke/tenants/bravo/human-owner-sa.yaml` | NEW | Bravo mirror |
| `pocs/capsule/spoke/rbac/kustomization.yaml` | EDITED | Appended `tenant-workload-editor.yaml` |
| `pocs/capsule/spoke/tenants/alpha/kustomization.yaml` | EDITED | Appended `human-owner-sa.yaml` |
| `pocs/capsule/spoke/tenants/bravo/kustomization.yaml` | EDITED | Appended `human-owner-sa.yaml` |
| `pocs/capsule/spoke/tenant-crs/alpha.yaml` | EDITED | Additive `spec.owners[]` + `containerRegistries.allowed += docker.io` |
| `pocs/capsule/spoke/tenant-crs/bravo.yaml` | EDITED | Bravo mirror |
| `scripts/poc/capsule/issue-tenant-kubeconfig.sh` | EDITED | Usage + fail-fast hint expansion only |

## Requirements Verification

| REQ | Disposition | Evidence |
|-----|-------------|----------|
| RBAC-01 | satisfied | `tenant-workload-editor` ClusterRole landed with 4 explicit denial categories (no Secret CUD, no RoleBinding/Role, no ResourceQuota, no LimitRange). No aggregation labels. |
| RBAC-02 | satisfied | Per-tenant `human-tenant-owner` SA + Tenant CR owner entry with explicit `clusterRoles: [tenant-workload-editor]`. Mint via `bash scripts/poc/capsule/issue-tenant-kubeconfig.sh <t> human-tenant-owner` produces kubeconfig binding to the narrow ClusterRole. |
| RBAC-03 | preserved (regression gate) | Existing `gitops-reconciler` SA owner entry + implicit-default `clusterRoles: [admin, capsule-namespace-deleter]` preserved verbatim on alpha + bravo. Edits are append-only to `spec.owners[]`. |

## Validation

- **Static bats (will turn GREEN after Flux reconcile of new resources):**
  - `bats tests/bats/rbac-01-static-tenant-workload-editor.bats` → ClusterRole shape (positive verbs + 4 denials + no aggregation label)
  - `bats tests/bats/rbac-04-static-human-owner-sa.bats` → SA shape + per-tenant placement
- **Live bats (gated on `kubectl --context=k3d-spoke-capsule cluster-info` probe):**
  - `bats tests/bats/rbac-05-live-tenant-owner-grant-matrix.bats` → grant matrix (pos + 4 denials)
  - `bats tests/bats/rbac-06-live-tenant-kubeconfig.bats` → minted kubeconfig: `auth can-i '*' '*'` → no; `auth can-i create secret` → no
  - `bats tests/bats/rbac-07-live-flux-sa-preservation.bats` → RBAC-03 Flux SA owner pattern intact
  - `bats tests/bats/proxy-04-live-issue.bats` → Phase 10 PROXY-01..03 regression gate
- **Inherited regression gates:**
  - `bats tests/bats/poc-isolation-01-static.bats` → Phase 7 P31 (zero new spoke-capsule mentions in v0.18 scripts; new artifacts under `pocs/capsule/spoke/` and `scripts/poc/capsule/` only)
  - `bats tests/bats/negative-rbac-*.bats` → Phase 9 N7 fixture (a DIFFERENT arbitrary registry continues to be rejected — additive `docker.io` does NOT regress)

## Notable Observations

1. **Power-failure recovery context:** Task 1 was committed before the power loss (`203cadb`). Task 2 edits were complete on disk but uncommitted; recovery surfaced no semantic differences from the planned spec — diff inspection showed all 3 modifications matched D-13-05 + Pitfall 13-P1 + script hint expansion verbatim. Task 2 was committed inline as `6e91216` to finish the plan without re-spawning a fresh executor.
2. **Capsule auto-injected RoleBinding shape:** With explicit `clusterRoles: [tenant-workload-editor]` on the human-tenant-owner owner entry, Capsule v0.12.4 injects ONE RoleBinding per (owner, clusterRole) pair per tenant namespace. Expected live shape: `capsule-alpha-<index>-tenant-workload-editor` + `capsule-bravo-<index>-tenant-workload-editor` (index numbering is Capsule controller-internal — Research A2 ASSUMED; Plan 13-04 verifier observes live values for Notable Observations).
3. **docker.io additive — N7 non-regression:** The `containerRegistries.allowed += docker.io` edit is purely additive. The Phase 9 N7 negative-RBAC fixture asserts that workloads pulling from `ghcr.io/something-else` (or any other arbitrary registry NOT in `allowed[]`) continue to be rejected. Both alpha + bravo Tenant CRs still reject non-listed registries after this edit.
4. **issue-tenant-kubeconfig.sh edit is hint-only:** No structural change. The script's SA-exists check at the `kubectl ... get sa ${OWNER}` line already works for any SA name passed via the `<owner>` positional arg. The Usage + error-hint enums are documentation-level guidance for the operator running the script, not enforcement.

## Hand-off to Plan 13-02

`tests/bats/rbac-03-static-tenant-co-ownership.bats` remains RED after Plan 13-01 because:
- Plan 13-01 added only the **human-tenant-owner SA** entry to `spec.owners[]`.
- The bats file asserts ALL co-ownership entries land — including `Group: capsule-platform-owners` AND `ServiceAccount: system:serviceaccount:capsule-system:platform-owner`.
- Those two entries are Plan 13-02's responsibility (D-13-07 platform-owner co-ownership).

Plan 13-02 will:
- Append the `Group capsule-platform-owners` owner entry (Capsule default clusterRoles).
- Append the `ServiceAccount platform-owner@capsule-system` owner entry (Capsule default clusterRoles for proxy LIST filter eligibility).
- Make `rbac-03-static-tenant-co-ownership.bats` turn GREEN.

The append-after position is documented in Plan 13-02 — both new entries go BELOW the human-tenant-owner entry that Plan 13-01 just landed. Plan 13-02's bats verify the additive-only pattern is preserved.
