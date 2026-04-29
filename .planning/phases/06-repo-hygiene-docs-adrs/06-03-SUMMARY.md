---
phase: 06-repo-hygiene-docs-adrs
plan: 03
subsystem: documentation
tags: [phase-6, wave-2, documentation, mermaid, gpu, architecture, k3d, blackwell, sm_120, cuda]

# Dependency graph
requires:
  - phase: 02-cluster-layer
    provides: k8s-net 172.30.0.0/16 CIDR pin (D-11), nvidia-device-plugin v0.17.4 phase-scoped override (D-15), 3-part k3d GPU contract IMG-01..06
  - phase: 04-spoke-registration
    provides: hub-only Flux reconciliation model + spec.kubeConfig.secretRef.{name,key} explicit defense (P18 silent-misroute)
  - phase: 06-repo-hygiene-docs-adrs
    provides: docs-02-architecture.bats and docs-04-gpu-notes.bats Wave 0 contracts (Plan 00)
provides:
  - docs/architecture.md — single Mermaid hub-spoke topology with all 13 required literals (DOCS-02 / D-03)
  - docs/gpu-notes.md — 3-part k3d GPU contract + RTX 5090 / sm_120 / CUDA 12.8+ floor (DOCS-04)
  - Both docs follow the project doc style: h1 + orientation paragraph + ## h2 sections + horizontal-rule separators + bold lead-ins for hard rules
  - Cross-reference scaffold for Plan 05 (README) and Plan 04 (ADR-005 link target verified)
affects: [Plan 04 (ADR-005 cross-link target verified), Plan 05 (README cross-links to architecture.md/gpu-notes.md), Plan 06 (markdownlint MD041 lints will pass)]

# Tech tracking
tech-stack:
  added: [Mermaid GitHub-rendered fenced block (flowchart LR with subgraph composition)]
  patterns: [Markdown reference doc with h1+orientation+## sections+horizontal-rule separators (inherited from docs/flux-hub-spoke.md and docs/wsl-networking.md)]

key-files:
  created:
    - docs/architecture.md (102 lines)
    - docs/gpu-notes.md (130 lines)
  modified: []

key-decisions:
  - "Architecture diagram uses verbatim Mermaid block from RESEARCH.md §Pattern 4 lines 603-647 — single flowchart LR with one subgraph per cluster on k8s-net (Docker bridge, 172.30.0.0/16), capturing both Secret-via-spec.kubeConfig (dotted) and applies-via (heavy) edges to make the P18 silent-misroute defense visible at a glance"
  - "h1 deliberately placed BEFORE the Mermaid fence to satisfy MD041 (Pitfall 4 in 06-RESEARCH.md), with the bats line-number comparison test (test #1 in docs-02-architecture.bats) enforcing the ordering"
  - "gpu-notes.md follows docs/wsl-networking.md style (h1 + orientation paragraph + ## sections + bold v1-mandate lead-in + horizontal rule separators) for consistency across the v1 reference doc set"
  - "Phase 2 D-15 nvidia-device-plugin v0.17.4 override is documented in gpu-notes.md as a phase-scoped, ship-with-what-works decision so the constraint is discoverable from the canonical GPU doc rather than only PROJECT.md/STATE.md"
  - "Cross-link to adr/0005-kubernetes-version-pin.md is a forward reference: ADR-005 lands in Plan 04 (Wave 3); the link path is verified by bats test acceptance criterion `grep -F 'adr/0005-kubernetes-version-pin.md' docs/gpu-notes.md`"

patterns-established:
  - "Mermaid topology blocks for hub-spoke architectures: subgraph per cluster with direction TB, node labels include API port + GPU annotation, top-level edges show GitOps reconciliation flow (GitRepository -> source-controller -> kustomize-controller -> spoke Kustomizations) and spec.kubeConfig-mediated apply (dotted -.uses.- and heavy ==> arrows)"
  - "Reference doc structure: h1 + orientation paragraph naming the load-bearing concept + horizontal-rule (***) separators between major sections + bold lead-in (**v1 of this project requires X.**) for hard rules + Cross-References section at the end"
  - "GPU contract documentation pattern: numbered Parts (1, 2, 3) each with WHY+HOW+CONFIRM blocks, where CONFIRM gives a one-line shell verification command"

requirements-completed: [DOCS-02, DOCS-04]

# Metrics
duration: ~10min
completed: 2026-04-28
---

# Phase 6 Plan 03: Reference Docs (architecture.md + gpu-notes.md) Summary

**Authored the two greenfield v1 reference docs that the README will cross-link to: a Mermaid hub-spoke topology and the 3-part k3d GPU contract narrative — both ship in Wave 2 with all 8 bats DOCS-02 + DOCS-04 contracts green.**

## Tasks Completed

| Task | Name | Commit | Files | Lines |
|------|------|--------|-------|-------|
| 1 | Author docs/architecture.md with Mermaid hub-spoke topology | `940e629` | `docs/architecture.md` | 102 |
| 2 | Author docs/gpu-notes.md with the 3-part k3d GPU contract and Blackwell floor | `116525a` | `docs/gpu-notes.md` | 130 |

## Verification

```bash
$ bats tests/bats/docs-02-architecture.bats tests/bats/docs-04-gpu-notes.bats
1..8
ok 1 DOCS-02 (Pitfall 4): docs/architecture.md starts with an h1 before the Mermaid block (MD041 safety)
ok 2 DOCS-02 (D-03): docs/architecture.md contains a fenced mermaid block
ok 3 DOCS-02 (D-03): Mermaid topology contains all 3 clusters with API ports
ok 4 DOCS-02 (D-03): Mermaid topology contains the k8s-net 172.30.0.0/16 network and spec.kubeConfig arrows
ok 5 DOCS-02 (D-03): Mermaid topology lists the four flux-system controllers
ok 6 DOCS-04: docs/gpu-notes.md exists and starts with an h1
ok 7 DOCS-04: gpu-notes covers the 3-part k3d GPU contract
ok 8 DOCS-04: gpu-notes covers the RTX 5090 / sm_120 / CUDA 12.8+ floor
```

All 8 contracts green. Acceptance criteria verified:

- `docs/architecture.md` line 1 = `# Karyon Architecture` (MD041 lead-in); first Mermaid fence at line 14; line count 102 (>= 40 floor); single h1; all 13 required literals present (`hub-flux`, `spoke-ml`, `spoke-apps`, `6443`, `6444`, `6445`, `k8s-net`, `172.30.0.0/16`, `spec.kubeConfig`, `source-controller`, `kustomize-controller`, `helm-controller`, `notification-controller`).
- `docs/gpu-notes.md` line 1 = h1 (`# GPU Notes: 3-Part k3d Contract and the RTX 5090 (Blackwell) Floor`); line count 130 (>= 50 floor); all 6 required keywords present (`default-runtime`, `nvidia/cuda`, `config.toml.tmpl`, `RTX 5090`, `sm_120`, `12.8`); cross-link to `adr/0005-kubernetes-version-pin.md` present.

## Manual / Render Verification (Developer Sign-Off)

The bats contracts cover textual structure only. Two manual verifications remain for downstream-acceptance sign-off (not Wave 2 blockers — covered by Phase 6 Plan 07 CI markdownlint and human review of the rendered diagram):

- Open `docs/architecture.md` in the GitHub UI (or `glow`) and confirm the Mermaid block renders as a labeled hub-spoke graph with all expected ports, the dotted `Secret: spoke-*-kubeconfig` edges, and the heavy `applies via spec.kubeConfig` arrows from each spoke Kustomization into its target spoke cluster.
- Open `docs/gpu-notes.md` and confirm the four `***` horizontal-rule sections render correctly, the bold `**v1 of this project requires CUDA 12.8 or newer at the runtime.**` lead-in is visually distinct, and the Failure Modes table renders as a 4-row table.

## Deviations from Plan

None — plan executed exactly as written. The verbatim Mermaid block from RESEARCH.md §Pattern 4 was used unchanged; the gpu-notes.md content followed the doc-skeleton in PLAN.md Task 2 line-for-line.

## Files Created

- `docs/architecture.md` — 102 lines, h1 at line 1, Mermaid fence at line 14, references `adr/`, `gpu-notes.md`, `flux-hub-spoke.md`, `wsl-networking.md`, `rebuild-runbook.md`, and `examples/`.
- `docs/gpu-notes.md` — 130 lines, h1 at line 1, references `adr/0005-kubernetes-version-pin.md`, `architecture.md`, `wsl-networking.md`, `rebuild-runbook.md`, and `flux-hub-spoke.md`.

## Forward Dependencies

- **Plan 04 (ADRs):** `docs/gpu-notes.md` cross-links to `adr/0005-kubernetes-version-pin.md`. ADR-005 lands in Plan 04 (Wave 3); link is verified by string match in the bats acceptance criteria but resolves to a real file only after Plan 04 completes.
- **Plan 05 (README):** README will cross-link to both `docs/architecture.md` and `docs/gpu-notes.md` from the "Why these choices" / fresh-clone-walkthrough sections per CONTEXT.md `<code_context>` 388-390.
- **Plan 06 / Plan 07 (markdownlint CI):** MD041 enforcement (h1 first) is intentional; both docs are MD041-safe by construction.

## Self-Check: PASSED

Verified file presence and commit hashes:

- `docs/architecture.md`: FOUND (102 lines, committed in 940e629)
- `docs/gpu-notes.md`: FOUND (130 lines, committed in 116525a)
- Commit `940e629`: FOUND in `git log --oneline`
- Commit `116525a`: FOUND in `git log --oneline`
- bats DOCS-02 + DOCS-04: 8/8 green
