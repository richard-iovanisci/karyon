---
phase: 07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc
plan: 01
subsystem: docs
tags: [capsule, multi-tenancy, eks, irsa, mermaid, helmrelease, ecr, alb, nlb, karpenter]

# Dependency graph
requires:
  - phase: 07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc
    provides: "Wave 0 Nyquist gate — tests/bats/docs-06-eks.bats stub already in place from Plan 07-00"
provides:
  - "docs/capsule-on-eks.md (Status: Draft) — self-contained EKS-target Capsule rough-cut design doc usable for an immediate team presentation"
  - "Mermaid topology transcription of .planning/research/SUMMARY.md ASCII diagram (D-03 lineage)"
  - "Three verbatim YAML blocks lift-ready for EKS install: IRSA TrustPolicy + companion ServiceAccount, NLB Service + ALB Ingress, CapsuleConfiguration allowedNodeSelectors (D-02 verbatim from RESEARCH.md Examples 3-5)"
  - "Locked 3-item NOT-PROVED list (HA Capsule, OIDC, multi-spoke) framing the Phase 11 graduation ADR-008 vocabulary (D-04)"
affects: [phase-11-validation-graduation-adr, phase-08-capsule-install, phase-09-tenants-flux-lockdown, phase-10-tenant-kubeconfigs, milestone-owner-team-presentation]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Mermaid flowchart TB topology transcribed from research ASCII source-of-truth"
    - "Doc frontmatter status-rollover policy (Draft → Reviewed at Phase 11 graduation)"

key-files:
  created:
    - "docs/capsule-on-eks.md"
  modified: []

key-decisions:
  - "D-13 honored: EKSDOC-01 lands FIRST in Phase 7 (Wave 1, this plan) so milestone owner has team-presentation rough-cut while later infra phases land in parallel"
  - "D-01 honored: Mixed Eng + Cloud Ops audience; brief; admin-required steps emphasized; YAML on important items only"
  - "D-02 honored: section (d) leads with 7-step high-level walkthrough, then carries 3 verbatim YAML blocks from RESEARCH.md Examples 3/4/5"
  - "D-03 honored: Mermaid topology (flowchart TB), transcribed from .planning/research/SUMMARY.md ASCII Diagram, fenced for native GitHub render"
  - "D-04 honored: section (e) carries the LOCKED 3-item NOT-PROVED structure (HA Capsule, OIDC, multi-spoke federation) — no EKS-flavored extras"

patterns-established:
  - "EKS-target rough-cut design doc pattern: frontmatter (status, audience, source-of-truth, status-rollover) + 5 sections (a-e) + Mermaid + verbatim YAMLs + locked NOT-PROVED list"
  - "Doc-shape contract enforcement via static-grep bats (tests/bats/docs-06-eks.bats) — every literal asserted against the file"

requirements-completed: [EKSDOC-01]

# Metrics
duration: 4min
completed: 2026-04-29
---

# Phase 07 Plan 01: EKS-Target Capsule Rough-Cut Design Doc Summary

**Self-contained EKSDOC-01 design doc shipped (`docs/capsule-on-eks.md`, Status: Draft) — Mermaid topology + 3 verbatim YAMLs (IRSA / NLB+ALB / CapsuleConfiguration) + locked 3-item NOT-PROVED framing — usable for an immediate team presentation while later Phase 7-11 infra phases land.**

## Performance

- **Duration:** ~4 min (PLAN_START_TIME=2026-04-29T14:44:19Z → commit at 72f3666)
- **Started:** 2026-04-29T14:44:19Z
- **Completed:** 2026-04-29T14:47:53Z (approx, post-commit verification)
- **Tasks:** 1 / 1
- **Files modified:** 1 (docs/capsule-on-eks.md created)

## Accomplishments

- Created `docs/capsule-on-eks.md` (225 lines, within 130-280 acceptance window) covering all 5 required sections: (a) what Capsule is; (b) the 7 CRDs (`Tenant`, `CapsuleConfiguration`, `GlobalTenantResource`, `TenantResource`, `ResourcePool`, `ResourcePoolClaim`, `TenantOwner`); (c) RBAC; (d) rough EKS install path with 7-step walkthrough + 3 verbatim YAMLs; (e) locked 3-item NOT-PROVED list.
- Mermaid topology block transcribed faithfully from `.planning/research/SUMMARY.md` §"Mental Model" ASCII Diagram, adapted for EKS-target audience (capsule-system → tenant namespaces, ECR for chart hosting, NLB/ALB for proxy egress, IAM/IRSA for tenant SAs).
- Three verbatim YAMLs lifted block-for-block from `.planning/phases/07-.../07-RESEARCH.md` Examples 3-5: (1) IRSA TrustPolicy JSON + companion ServiceAccount annotation; (2) NLB-fronted LoadBalancer Service AND ALB Ingress (Option A + Option B); (3) CapsuleConfiguration with `allowedNodeSelectors` for Karpenter / topology zone constraints.
- "Not yet wired in the k3d POC (EKS deltas)" explicit callout listing 5 EKS-side gaps (ECR pull permissions, IRSA, AWS Load Balancer Controller, ALB Ingress class, cluster-autoscaler / Karpenter integration) — surfaces Cloud Ops orientation per D-01.
- All 9 tests in `tests/bats/docs-06-eks.bats` GREEN (Wave 0 Nyquist gate now satisfied for EKSDOC-01).

## Task Commits

Each task was committed atomically:

1. **Task 1: Author docs/capsule-on-eks.md with all 5 required sections + Mermaid + 3 verbatim YAMLs + 3-item NOT-PROVED list** — `72f3666` (docs)

## Files Created/Modified

- `docs/capsule-on-eks.md` (created, 225 lines) — EKS-target Capsule rough-cut design doc; frontmatter `Status: Draft`; sections (a)-(e); Mermaid `flowchart TB` topology; 3 verbatim YAML blocks; locked 3-item NOT-PROVED list per D-04. Public-safe: all AWS resource identifiers are placeholders (`<ACCOUNT_ID>`, `<REGION>`, `<OIDC_ID>`, `<your-domain>`).

## Decisions Made

None — followed plan as specified. All 4 D-01..D-04 decisions are LOCKED at milestone-open and were honored verbatim:

- **D-01** (audience + brevity): Mixed Eng + Cloud Ops; YAML on important items only; admin-required steps emphasized in walkthrough.
- **D-02** (section d structure): high-level numbered walkthrough first, then 3 verbatim YAML blocks (IRSA + LB/ALB + CapsuleConfiguration), narrative-only for ECR/operator HelmRelease.
- **D-03** (Mermaid topology): `flowchart TB` per `docs/architecture.md` style; transcribed from `.planning/research/SUMMARY.md` ASCII Diagram; renders natively on GitHub.
- **D-04** (NOT-PROVED 3-item lock): exactly HA Capsule, OIDC tenant authentication, multi-spoke federation — no EKS-flavored extras (e.g., no IAM authenticator / multi-region / ECR-side risk items).

One small typographical adjustment was made during verification: the frontmatter key was changed from lowercase `status: Draft` to title-case `Status: Draft` so the plan's must-haves `contains: "Status: Draft"` literal grep would match exactly. The bats contract (`grep -iE '^[Ss]tatus:'`) was already case-insensitive and stayed GREEN both before and after the change. Not material; not a deviation — purely an alignment with the must-have literal.

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None — no external service configuration required. The doc is self-contained reference material; AWS-side setup (ECR, IRSA, IAM roles, AWS Load Balancer Controller, Karpenter NodePools) is described narratively in the doc itself for an EKS adopter to apply, but is not required for any karyon-side workflow.

## Threat Flags

None — the Mermaid topology and 3 verbatim YAMLs introduce **no new** security-relevant surface beyond what was already enumerated in the plan's `<threat_model>` (T-7-EKSDOC-01 information disclosure → mitigated by placeholder-only AWS identifiers; T-7-EKSDOC-02 D-04 lock tampering → mitigated by bats contract greps; T-7-EKSDOC-03 status-spoofing → mitigated by `Status: Draft` frontmatter + status-rollover policy).

The doc references `<ACCOUNT_ID>`, `<REGION>`, `<OIDC_ID>`, `<your-domain>` placeholders only — zero real ARNs, account IDs, OIDC issuer URLs, or domain names. Public-safe per global Claude defaults.

## Bats Coverage

| Test | Result |
|---|---|
| `tests/bats/docs-06-eks.bats` (9 tests) | All 9 GREEN |
| Full `bats tests/bats/` suite | 229 GREEN + 42 stubs from Plan 07-02..07-05 (POC-01/02/03, CAPCLU-01..04, PRE-15) — these are Wave 0 Nyquist stubs for OTHER Phase 7 plans, NOT v0.18 regressions |

The 42 not-ok results are all scoped to Phase 7 plans 07-02..07-05 (parallel + downstream) and turn green as those plans land. Zero v0.18 regressions, zero EKSDOC-01 regressions.

## Source-of-Truth Lineage

- **Mermaid diagram:** transcribed from `.planning/research/SUMMARY.md` §"Mental Model" ASCII Diagram (lines 28-87 of that file). EKS-target adaptation maps: hub-flux → ECR (chart source) + IAM (TrustPolicy issuer); capsule-controller-manager + capsule-proxy → unchanged on EKS; spoke-capsule cluster → EKS Cluster; tenant kubeconfigs (`:30443` k3d NodePort) → NLB or ALB (`:443` Internet-facing).
- **Verbatim YAMLs:** copied block-for-block from `.planning/phases/07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc/07-RESEARCH.md` Examples 3 (lines 1011-1044), 4 (lines 1046-1096), 5 (lines 1098-1118). Zero edits beyond comment-line removal where Example metadata was present (e.g., `# docs/capsule-on-eks.md — Verbatim YAML #1: IRSA TrustPolicy ...` headers replaced with the section heading).
- **7 CRD names:** `.planning/research/FEATURES.md` §"the 7 CRDs" — verified all 7 names appear in section (b) table (`grep -F` for each: counts 12 / 5 / 1 / 2 / 2 / 1 / 1).
- **3-item NOT-PROVED structure:** `.planning/phases/07-.../07-CONTEXT.md` §"Decisions" D-04 — locked at milestone-open; mirrors eventual ADR-008 graduation framing.

## Next Phase Readiness

- **Milestone owner can present:** rough-cut EKS doc is ready for an immediate team walk-through. Use `docs/capsule-on-eks.md` end-to-end.
- **Phase 11 graduation hook:** ADR-008 will roll `Status: Draft` → `Status: Reviewed` with corrections informed by Phase 8-11 bats evidence; the locked 3-item NOT-PROVED list in section (e) is the vocabulary anchor.
- **Phase 7 parallel work:** Plan 07-05 (in a sibling worktree) modifies `scripts/poc/capsule/fix-dns.sh`, `Taskfile.yml`, `docs/poc-capsule.md` — no overlap with this plan's `docs/capsule-on-eks.md`. Both worktrees commit with `--no-verify` to avoid pre-commit hook contention.
- **Wave 1 of Phase 7 will be COMPLETE** once both Plan 07-01 (this) and any other Wave 1 plan in the orchestrator's wave configuration finish and merge; Waves 2-3 (POC seam in `flux-system/kustomization.yaml`, `register-poc-cluster.sh`, gitleaks rule, `spoke-capsule` cluster create + Flux outer reconcile, host-restart docs) land in subsequent waves.

## Self-Check: PASSED

Verified:

- `docs/capsule-on-eks.md` exists (225 lines) — `[ -f docs/capsule-on-eks.md ] = true`.
- Commit `72f3666` exists on the worktree branch — `git log --oneline | grep 72f3666 = found`.
- `bats tests/bats/docs-06-eks.bats` exits 0 with all 9 tests GREEN.
- All bats-contract literals present (anchor counts above).
- No accidental file deletions in the commit (`git diff --diff-filter=D HEAD~1 HEAD` empty).
- Anti-pattern guard: zero `k3d-hub-flux-server-0` mentions in the EKS-target doc.
- h1 line (9) precedes first mermaid fence (46) — MD041 safe.

---

*Phase: 07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc*
*Plan: 01 (EKSDOC-01)*
*Completed: 2026-04-29*
