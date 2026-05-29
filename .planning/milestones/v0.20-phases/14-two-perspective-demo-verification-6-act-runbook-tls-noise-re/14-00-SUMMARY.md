---
phase: 14-two-perspective-demo-verification-6-act-runbook-tls-noise-re
plan: 00
subsystem: capsule-demo-verification
wave: 0
tags:
  - capsule
  - demo
  - runbook
  - bats
  - wave0
  - nyquist
requirements_addressed:
  - DEMO-01
  - DEMO-02
  - DEMO-03
  - DEMO-04
  - DEMO-05
  - DEMO-06
  - RUNBOOK-01
  - RUNBOOK-02
  - RUNBOOK-03
  - RUNBOOK-05
dependency_graph:
  requires:
    - Phase 13 RBAC-01..06 (tenant-workload-editor + capsule-platform-owner ClusterRoles, dual-subject CRB)
    - Phase 13 SEED-01 (GlobalTenantResource hello-world-seeded; nginx:alpine BusyBox-sh image)
    - Phase 13 DELIVERY-01..03 (issue-platform-owner-kubeconfig.sh + issue-tenant-kubeconfig.sh + new-tenant.sh)
    - Phase 11 D-11-02 (CapsuleConfiguration.userGroups system:serviceaccounts)
    - Phase 10 (capsule-proxy NodePort 30443; ${TMPDIR}/karyon-tenants/ BL-01/BL-02 path-lock)
  provides:
    - 11 falsifier-locked bats files for DEMO-01..06 + RUNBOOK-01/02/03/05 contracts
    - Nyquist gate scaffold: runbook-* RED forces Plan 14-01 to chase GREEN by authoring docs
    - Phase 13 inheritance baseline (10-probe preflight log)
  affects:
    - tests/bats/ (+11 files; +571 lines)
tech_stack:
  added: []
  patterns:
    - rbac-08-live-platform-owner-grant-matrix.bats (PO-only setup_file + double cluster-info skip)
    - rbac-05-live-tenant-owner-grant-matrix.bats (dual-kubeconfig setup_file alpha + bravo)
    - rbac-06-live-tenant-kubeconfig.bats (Forbidden-create-secret idiom + idempotent cleanup)
    - negative-rbac-01-cross-tenant-list.bats (scoped-LIST regex walker + symmetric mirror)
    - docs-05-runbook.bats (strict-order step-marker grep loop)
    - seed-01-static-globaltenantresource.bats (file-exists + grep -F literal idiom)
    - docs-06-eks.bats (multi-literal grep loop)
    - rbac-01-static-tenant-workload-editor.bats (sed-by-line-range + grep -F slice idiom)
key_files:
  created:
    - tests/bats/demo-01-live-platform-owner-list.bats
    - tests/bats/demo-02-live-tenant-owner-scoped-list.bats
    - tests/bats/demo-03-live-pod-ops.bats
    - tests/bats/demo-04-live-tenant-secret-forbidden.bats
    - tests/bats/demo-05-live-cross-tenant-forbidden.bats
    - tests/bats/demo-06-live-platform-owner-cluster-admin-denials.bats
    - tests/bats/runbook-01-static-acts.bats
    - tests/bats/runbook-02-static-checklist.bats
    - tests/bats/runbook-03-static-tls-noise.bats
    - tests/bats/runbook-03-static-eks-three-tier.bats
    - tests/bats/runbook-05-static-charlie.bats
  modified: []
key_decisions:
  - "D-14-08 honored: 11 NEW bats files keyed by REQ (no extension of Phase 13 rbac-*/negative-rbac-* files)"
  - "D-13-15 Nyquist gate held: 'RED until <Plan N-NN>' header line in every file"
  - "RESEARCH Q6 verbatim Forbidden strings embedded in demo-04 (human-tenant-owner) + demo-06 (clusterrolebindings.rbac.authorization.k8s.io is forbidden) — no invented strings"
  - "RESEARCH Q2 verbatim 'tls: bad certificate' embedded in runbook-03-tls grep target"
  - "Phase 13 inheritance verified live before any bats lands (preflight probes 1-10 all PASS)"
metrics:
  duration_minutes: ~12
  tasks_completed: 2
  files_created: 11
  files_modified: 0
  completed_date: 2026-05-19
---

# Phase 14 Plan 00: Wave 0 RED bats scaffold for DEMO-01..06 + RUNBOOK-01/02/03/05 Summary

11 falsifier-locked bats files (6 live DEMO + 5 static RUNBOOK) landed RED ahead of any documentation work, with a verified Phase 13 inheritance preflight baseline (10/10 probes PASS).

## What Was Built

Wave 0 Nyquist-gate scaffold for Phase 14. Every DEMO-01..06 + RUNBOOK-01/02/03/05 requirement now has a pre-existing failing bats test that Wave 1+ executors must chase to GREEN.

### Task 1 — Phase 13 inheritance preflight (10 probes against k3d-spoke-capsule)

Log captured at `/tmp/14-00-preflight.log`. All 10 probes PASSED:

| Probe | Subject | Result |
| ----- | ------- | ------ |
| 1 | cluster-info | k3d-spoke-capsule reachable on `https://0.0.0.0:6446` |
| 2 | CapsuleConfiguration.userGroups | `["capsule.clastix.io","system:serviceaccounts","system:authenticated"]` (Phase 11 D-11-02 OK) |
| 3 | tenant-workload-editor ClusterRole | present (Phase 13 RBAC-01 OK) |
| 4 | capsule-platform-owner ClusterRole + CRB | ClusterRole present; CRB binds Group `capsule-platform-owners` + SA `platform-owner@capsule-system` (Phase 13 RBAC-04 OK) |
| 5 | platform-owner SA | `serviceaccount/platform-owner` in `capsule-system` |
| 6 | GlobalTenantResource hello-world-seeded | present (Phase 13 SEED-01 OK) |
| 7 | hello-world Pod image | `docker.io/library/nginx:alpine` (DEMO-03 BusyBox-sh enabler OK) |
| 8 | capsule-proxy NodePort | `30443` (D-14-09 OK) |
| 9 | alpha + bravo Tenant `spec.owners[]` | both list `Group/capsule-platform-owners` + SA `platform-owner@capsule-system` (RBAC-06 co-ownership OK) |
| 10 | Forbidden CRB live spot-check | verbatim `clusterrolebindings.rbac.authorization.k8s.io is forbidden: User "system:serviceaccount:capsule-system:platform-owner" cannot create resource "clusterrolebindings" in API group "rbac.authorization.k8s.io" at the cluster scope` (RESEARCH Q6 verbatim string still fires) |

Phase 13 land state is verified intact — Phase 14 may proceed.

### Task 2 — 11 NEW bats files (commit `1d55419`)

**6 live DEMO bats:**

| File | REQ | Contract |
| ---- | --- | -------- |
| `tests/bats/demo-01-live-platform-owner-list.bats` | DEMO-01 | Platform-owner kubeconfig sees `alpha + bravo` tenants + `tenant-alpha + tenant-bravo` namespaces + `pods --all-namespaces` returns `hello-world` |
| `tests/bats/demo-02-live-tenant-owner-scoped-list.bats` | DEMO-02 | Tenant-owner via capsule-proxy:30443 LIST scoped to own tenant ns; symmetric alpha + bravo mirror |
| `tests/bats/demo-03-live-pod-ops.bats` | DEMO-03 | tenant-owner + platform-owner `exec hello-world -- sh -c "echo ok-from-shell"` + `logs hello-world --tail=3` → "worker process" (RESEARCH Q3/Q4 verbatim probes) |
| `tests/bats/demo-04-live-tenant-secret-forbidden.bats` | DEMO-04 | tenant-owner `create secret` Forbidden with verbatim `human-tenant-owner` User-identity sub-grep + permissive Forbidden grep (Pitfall 11-P3) |
| `tests/bats/demo-05-live-cross-tenant-forbidden.bats` | DEMO-05 | alpha→bravo + bravo→alpha pod LIST + namespace GET Forbidden (symmetric mirror) |
| `tests/bats/demo-06-live-platform-owner-cluster-admin-denials.bats` | DEMO-06 | Platform-owner 3-action ceiling: CRB Forbidden (verbatim RESEARCH Q6 `clusterrolebindings.rbac.authorization.k8s.io is forbidden`) + `get nodes -o yaml` Forbidden + `get csr` Forbidden |

**5 static RUNBOOK bats:**

| File | REQ | Contract |
| ---- | --- | -------- |
| `tests/bats/runbook-01-static-acts.bats` | RUNBOOK-01 | `docs/poc-capsule-demo.md` exists + h1 + `status: Active` + 6 strict-ordered `## Act N — ` sections + ≥6 `### Expected output` blocks |
| `tests/bats/runbook-02-static-checklist.bats` | RUNBOOK-02 | Pre-demo checklist literals: `task fix-dns-poc-capsule`, `issue-platform-owner-kubeconfig.sh`, `issue-tenant-kubeconfig.sh {alpha,bravo} human-tenant-owner`, `delete tenant charlie --ignore-not-found` |
| `tests/bats/runbook-03-static-tls-noise.bats` | RUNBOOK-03 / D-14-01 | Verbatim `tls: bad certificate` literal + ADR-008 cross-link + `## Known noise` appears AFTER `## Act 6 —` + `capsule-controller-manager` literal |
| `tests/bats/runbook-03-static-eks-three-tier.bats` | RUNBOOK-03 / Q1 | `docs/capsule-on-eks.md` contains `## Three-tier permission model` section + Tier 1/2/3 labels + IRSA + tenant-workload-editor + capsule-platform-owner literals |
| `tests/bats/runbook-05-static-charlie.bats` | RUNBOOK-05 / D-14-02/03 | `charlie` between Act 3 + Act 4 boundaries + `charlie` after Act 6 + `new-tenant.sh charlie` literal + `tenant-charlie` namespace literal |

## Wave 0 RED Status Snapshot

Live verification of expected RED behavior:

| File | bats exit | Why RED |
| ---- | --------- | ------- |
| `runbook-01-static-acts.bats` | 1 (RED) | `docs/poc-capsule-demo.md` does not exist |
| `runbook-02-static-checklist.bats` | 1 (RED) | `docs/poc-capsule-demo.md` does not exist |
| `runbook-03-static-tls-noise.bats` | 1 (RED) | `docs/poc-capsule-demo.md` does not exist |
| `runbook-03-static-eks-three-tier.bats` | 1 (RED) | `docs/capsule-on-eks.md` exists but lacks `## Three-tier permission model` + Tier 1/2/3 labels |
| `runbook-05-static-charlie.bats` | 1 (RED) | `docs/poc-capsule-demo.md` does not exist |
| `demo-01..06-live-*.bats` | mixed | Runnable; assertions opportunistically pass against Phase 13 live state (the load-bearing Wave 0 falsifier contract per the plan is runbook-* RED; demo-* contracts harden in Plan 14-02) |

This is precisely the Nyquist gate posture mandated by D-13-15: every Wave 1+ executor task now has a pre-existing failing bats command before its implementation lands.

## Verbatim String Provenance

Per RESEARCH Q6 + Q2 live captures (2026-05-19) — no invented strings:

- `demo-06` greps verbatim `clusterrolebindings.rbac.authorization.k8s.io is forbidden` (re-validated by preflight probe 10)
- `demo-06` greps verbatim `system:serviceaccount:capsule-system:platform-owner`
- `demo-04` greps verbatim `human-tenant-owner`
- `runbook-03-tls` greps verbatim `tls: bad certificate`
- `runbook-05` greps verbatim `new-tenant.sh charlie` + `tenant-charlie`

## Deviations from Plan

None — plan executed exactly as written.

## Phase 13 Inheritance Citation

Phase 13 land state verified live before any bats touched the tree:
- ClusterRoles `tenant-workload-editor` + `capsule-platform-owner` present
- Dual-subject CRB binds Group `capsule-platform-owners` + SA `platform-owner@capsule-system`
- `GlobalTenantResource/hello-world-seeded` reconciled
- `hello-world` Pod running `nginx:alpine` in `tenant-alpha` (DEMO-03 BusyBox-sh probe enabler)
- capsule-proxy NodePort `30443` live (DEMO-02 scoped-LIST mechanism)
- alpha + bravo Tenant CRs co-own `Group/capsule-platform-owners` (RBAC-06)
- Verbatim Forbidden CRB string from RESEARCH Q6 still fires

Preflight log: `/tmp/14-00-preflight.log` (10/10 probes PASS).

## Commits

- `1d55419` — `test(14-00): Wave 0 RED bats scaffold for DEMO-01..06 + RUNBOOK-01/02/03/05 (D-14-08 Nyquist gate)` — 11 files, +571 lines

## Self-Check: PASSED

- All 11 bats files exist at documented paths
- Every file contains `RED until` load-bearing header line
- `demo-06` contains verbatim `clusterrolebindings.rbac.authorization.k8s.io is forbidden`
- `demo-04` contains verbatim `human-tenant-owner`
- `runbook-03-tls` contains verbatim `tls: bad certificate`
- `runbook-05` contains verbatim `new-tenant.sh charlie`
- All 5 `runbook-*` bats exit non-zero (RED) — Nyquist gate honored
- Phase 13 inheritance preflight all 10 probes PASS
- Single commit `1d55419` lands all 11 files
- No edits to `pocs/capsule/`, Helm values, `docs/*.md`, `STATE.md`, `ROADMAP.md`, or any non-bats file
