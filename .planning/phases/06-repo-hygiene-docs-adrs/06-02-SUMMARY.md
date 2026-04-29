---
phase: 06-repo-hygiene-docs-adrs
plan: 02
subsystem: documentation
tags:
  - phase-6
  - wave-2
  - adrs
dependency_graph:
  requires:
    - .planning/PROJECT.md (Key Decisions table)
    - .planning/REQUIREMENTS.md (DOCS-07, DOCS-08, DOCS-09, DOCS-10)
    - .planning/phases/06-repo-hygiene-docs-adrs/06-CONTEXT.md (D-02 template)
    - .planning/phases/06-repo-hygiene-docs-adrs/06-PATTERNS.md (Nygard exemplar)
    - .planning/phases/06-repo-hygiene-docs-adrs/06-RESEARCH.md (§Pattern 3)
    - .planning/phases/02-cluster-layer/02-CONTEXT.md (k8s-net CIDR, D-13/D-14/D-15)
    - .planning/phases/04-spoke-registration/04-CONTEXT.md (P18 silent-misroute)
    - docs/adr/0001-single-wsl2-shared-docker-network.md (canonical Nygard analog)
    - docs/flux-hub-spoke.md (DOCS-03; cross-link target for ADR-004)
    - tests/bats/docs-adr-template.bats (Wave 0 contract)
  provides:
    - ADR-002 (k3d-over-Kind) at docs/adr/0002-k3d-over-kind.md
    - ADR-003 (Flux-over-ArgoCD with ApplicationSet trade-off + migration note) at docs/adr/0003-flux-over-argocd.md
    - ADR-004 (hub-only Flux control plane + P18 defense) at docs/adr/0004-hub-only-flux-control-plane.md
    - ADR-005 (k3s v1.34.6-k3s1 + CUDA 12.8+ pin) at docs/adr/0005-kubernetes-version-pin.md
  affects:
    - DOCS-07 / DOCS-08 / DOCS-09 / DOCS-10 (REQUIREMENTS.md)
    - bats tests/bats/docs-adr-template.bats (suite now fully green; was 1/8 → 8/8)
    - Phase 6 README (Plan 05 will cross-link from README to ADRs)
tech_stack:
  added: []
  patterns:
    - Nygard 4-section ADR template (Status / Context / Decision / Consequences) with `Status: Accepted (2026-04-22)`
key_files:
  created:
    - docs/adr/0002-k3d-over-kind.md
    - docs/adr/0003-flux-over-argocd.md
    - docs/adr/0004-hub-only-flux-control-plane.md
    - docs/adr/0005-kubernetes-version-pin.md
  modified: []
decisions:
  - "ADR text draws verbatim from PROJECT.md Key Decisions; only synthesis is the Nygard structure (D-02 explicit)."
  - "ADR-004 cross-links to ../flux-hub-spoke.md (DOCS-03 ✅) so the patch-surface and immutability rules carry through unchanged."
  - "ADR-003 Migration note triggers at 5+ spokes OR when ApplicationSet semantic features become load-bearing."
  - "ADR-005 explicitly frames v1.34.6-k3s1 as a 'current line' pin (NOT LTS) and notes RTX 5090 sm_120 Blackwell forces the CUDA 12.8+ floor."
metrics:
  duration: 190s (3m 10s)
  completed: 2026-04-29
  tasks_completed: 2
  files_created: 4
  files_modified: 0
---

# Phase 6 Plan 02: ADRs (Wave 2 — k3d, Flux, Hub-only, k3s+CUDA pins) Summary

**One-liner:** Authored ADR-002/003/004/005 in the locked Nygard 4-section template, satisfying DOCS-07..10 and turning the full bats `docs-adr-template.bats` suite (8 tests) green.

## What Was Built

This plan converts the four remaining locked v1 architectural decisions into on-disk ADR artifacts under `docs/adr/`. ADR-001 already shipped in Plan 01; this plan completes the v1 ADR set.

### Tasks

**Task 1: ADR-002 (k3d-over-Kind) + ADR-005 (Kubernetes version pin)** — commit `5079195`
- `docs/adr/0002-k3d-over-kind.md` (57 lines): captures k3d-over-Kind decision; Easier section names `--gpus all`, `--network k8s-net`, `--k3s-arg '--tls-san=...'`; Harder section names the lab-specific 3-part k3d GPU contract (`/etc/docker/daemon.json` `default-runtime: nvidia` + Ubuntu 22.04 base + containerd `config.toml.tmpl`); No-change section restates that cloud migration is out of scope per REQUIREMENTS.md.
- `docs/adr/0005-kubernetes-version-pin.md` (69 lines): pins `rancher/k3s:v1.34.6-k3s1` (current line, NOT LTS) and `nvcr.io/nvidia/cuda:12.8.0-base-ubuntu22.04`; explicitly notes RTX 5090 sm_120 Blackwell forces the CUDA 12.8+ floor; records the v0.17.4 nvidia-device-plugin override (Phase 2 D-15) as a Harder consequence; tracks the future-line bump as KUBE-01 (v2).

**Task 2: ADR-003 (Flux-over-ArgoCD) + ADR-004 (hub-only Flux)** — commit `b6a7372`
- `docs/adr/0003-flux-over-argocd.md` (87 lines): captures the Flux choice with the explicit ApplicationSet trade-off (Harder section: "No clean Flux equivalent of ArgoCD's `ApplicationSet` cluster generator with label-based targeting"); includes a dedicated `## Migration note` section with 5 numbered steps and the explicit trigger ("spoke count exceeds 5" or "ApplicationSet semantic features become load-bearing"). Both REQUIREMENTS.md DOCS-08 mandates (`ApplicationSet`, `migration`) satisfied.
- `docs/adr/0004-hub-only-flux-control-plane.md` (80 lines): captures the hub-only topology, the `spec.kubeConfig.secretRef` reconciliation pattern with `key: value.yaml`, and the Phase 4 P18 silent-misroute defense (omitted `spec.kubeConfig` falls back to in-cluster SA → workloads land on the wrong cluster while reporting `Ready=True`); cross-links to `../flux-hub-spoke.md` (DOCS-03 ✅) per CONTEXT.md mandate; names `tests/bats/register-spokes-02-live.bats` as the negative-proof test source.

## Verification

```bash
bats tests/bats/docs-adr-template.bats
# 1..8
# ok 1 DOCS-06..10 (D-02): all five ADR files exist with locked slugs
# ok 2 DOCS-06..10 (D-02): each ADR contains the 4 Nygard sections in order
# ok 3 DOCS-06..10 (D-02): each ADR has Status: Accepted in the first 10 lines
# ok 4 DOCS-06: ADR-001 captures single-WSL2 + shared k8s-net Docker network
# ok 5 DOCS-07: ADR-002 captures k3d-over-Kind decision
# ok 6 DOCS-08: ADR-003 captures Flux-over-ArgoCD with ApplicationSet trade-off + migration note
# ok 7 DOCS-09: ADR-004 captures hub-only Flux control plane
# ok 8 DOCS-10 (specifics): ADR-005 pins k3s v1.34.6-k3s1 and CUDA 12.8+, notes current line + RTX 5090 sm_120 floor
```

All 8 tests pass — full DOCS-06..10 contract green.

## CONTEXT.md `<specifics>` mandates satisfied

| ADR | Mandate | Status |
|-----|---------|--------|
| ADR-002 | Locked slug `0002-k3d-over-kind.md` | met |
| ADR-002 | `--gpus all` literal present (Easier) | met |
| ADR-002 | `Kind` literal present (Decision/Context/Easier) | met |
| ADR-003 | REQUIREMENTS DOCS-08: literal `ApplicationSet` present | met (Harder + Migration sections) |
| ADR-003 | REQUIREMENTS DOCS-08: `migration` present | met (`## Migration note` section + numbered steps) |
| ADR-003 | Locked slug `0003-flux-over-argocd.md` | met |
| ADR-004 | REQUIREMENTS SPOKE-04..05: `spec.kubeConfig` literal present | met (Decision + Harder sections) |
| ADR-004 | Phase 4 P18 silent-misroute narrative | met (Context section: "controller falls back to its own in-cluster ServiceAccount and reconciles the manifests into the HUB cluster" + Harder bullet 1: defense in depth requires explicit secretRef) |
| ADR-004 | Cross-link to `../flux-hub-spoke.md` (DOCS-03 ✅) | met (Easier bullet 3) |
| ADR-005 | CONTEXT.md `<specifics>` 416: "current line" pin (NOT LTS) | met (Decision step 1 + Harder bullet 1) |
| ADR-005 | CONTEXT.md `<specifics>` 417: CUDA 12.8+ floor forced by RTX 5090 sm_120 Blackwell | met (Context section + Easier bullet 3) |
| ADR-005 | Literal `v1.34.6-k3s1` | met |
| All 4 | Status: Accepted (2026-04-22) in first 10 lines | met |
| All 4 | Exactly 4 Nygard sections in order | met |

## Deviations from Plan

None — plan executed exactly as written. ADR text draws verbatim from PROJECT.md "Key Decisions" wording (D-02 mandate) with synthesis only into the 4-section template.

## Self-Check: PASSED

- `docs/adr/0002-k3d-over-kind.md`: FOUND (57 lines)
- `docs/adr/0003-flux-over-argocd.md`: FOUND (87 lines)
- `docs/adr/0004-hub-only-flux-control-plane.md`: FOUND (80 lines)
- `docs/adr/0005-kubernetes-version-pin.md`: FOUND (69 lines)
- Commit `5079195` (Task 1): FOUND
- Commit `b6a7372` (Task 2): FOUND
- bats suite `docs-adr-template.bats`: 8/8 green
