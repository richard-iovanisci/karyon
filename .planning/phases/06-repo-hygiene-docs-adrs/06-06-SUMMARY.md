---
phase: 06-repo-hygiene-docs-adrs
plan: 06
subsystem: docs
tags:
  - phase-6
  - wave-3
  - documentation
  - runbook
  - DOCS-05
requires:
  - DESTROY-05 (rebuild step markers in scripts/rebuild.sh:49-79)
  - HEALTH-07 (task fix-dns recovery)
  - CLU-05 (TLS-SAN immutability post-create)
  - PHASE-5 baseline (rebuild elapsed seconds: 190)
provides:
  - DOCS-05 (D-04): linear rebuild runbook + per-step timings + failure-mode appendix
affects:
  - docs/rebuild-runbook.md (NEW, 322 lines)
tech-stack:
  added: []
  patterns:
    - "D-04 layout: linear numbered steps (timings on top) + failure-mode appendix (symptom-keyed)"
    - "Step heading parity: doc h2 sections mirror >>> step <name> log markers from scripts/rebuild.sh"
    - "Cross-link reference cluster: architecture.md, flux-hub-spoke.md, gpu-notes.md, wsl-networking.md, adr/"
key-files:
  created:
    - docs/rebuild-runbook.md
  modified: []
decisions:
  - "Per-step timings reconstructed from Phase 5 logs in git history (NOT remeasured) — baseline is the recorded total of 190s; per-step splits are illustrative warm-cache RTX 5090 / 20-core figures."
  - "Runbook explicitly disclaims warm-cache + dev-box hardware envelope so future contributors with different hardware understand timings are illustrative, not normative."
  - "Failure-mode appendix routes by SYMPTOM (what the user sees in /tmp/karyon-rebuild.log or task health-check output), not by component, so mid-incident readers can pattern-match quickly."
metrics:
  duration_seconds: 152
  completed_date: "2026-04-29"
  tasks_completed: 1
  tasks_total: 1
  files_changed: 1
  lines_added: 322
  lines_deleted: 0
---

# Phase 06 Plan 06: Rebuild Runbook (DOCS-05) Summary

One-liner: Authored `docs/rebuild-runbook.md` — D-04 linear-steps-then-failure-appendix layout with the 7 `>>> step` markers in strict order, per-step warm-cache timings reconstructed from Phase 5 git history, and a symptom-keyed failure-mode appendix (`fix-dns`, GPU 3-part contract, TLS-SAN, CUDA image disappeared, PAT rotation, `.env` missing, WSL2 mirrored mode).

## What Was Built

A single new Markdown file: `docs/rebuild-runbook.md` (322 lines, 12 h2 headings, 7 h3 failure-mode entries).

### Section Inventory

| Section                       | Heading                                       | Purpose                                                                  |
| ----------------------------- | --------------------------------------------- | ------------------------------------------------------------------------ |
| Title + orientation paragraph | `# Rebuild Runbook`                           | What `task rebuild` does + 190s warm-cache baseline anchor.              |
| Timing disclaimer             | (blockquote)                                  | Warm-cache, RTX 5090, 20-core dev-box envelope.                          |
| Pre-flight                    | `## Pre-flight: Confirm .env and tools`       | `.env` + asdf shim + `task preflight` exit-0 prerequisites before step 1.|
| Step 1                        | `## Step 1: >>> step preflight (~5 seconds)`  | Runtime preflight gate; PRE-09/10/11 most-common failures.               |
| Step 2                        | `## Step 2: >>> step destroy (~10 seconds)`   | Destroy chain; cache-preserving (DESTROY-04).                            |
| Step 3                        | `## Step 3: >>> step create-clusters (~45s)`  | k3d cluster creation + GPU image; the longest leg on warm cache.         |
| Step 4                        | `## Step 4: pin context >>> pin context k3d-hub-flux` | HIGH-1 fix; prereq for steps 5-6.                                |
| Step 5                        | `## Step 5: >>> step bootstrap-flux (~30s)`   | flux bootstrap github; idempotent.                                       |
| Step 6                        | `## Step 6: >>> step register-spokes (~30s)`  | SA + CRB + Secret + kubeconfig encode; P18 silent-misroute defense link. |
| Step 7                        | `## Step 7: >>> step deploy-examples (~30s)`  | GitRepository sync + Kustomization Ready=True wait.                      |
| Step 8                        | `## Step 8: >>> step health-check (~40s)`     | 7-check read-only verification gate; 1200s SLO ceiling.                  |
| Total table                   | `## Total Expected Wall-Clock`                | Warm vs cold vs below-floor hardware breakdown.                          |
| Failure appendix              | `## Common failures`                          | 7 symptom-keyed entries (h3) with recovery commands + cross-links.       |
| Reference                     | `## Reference`                                | Cross-links to architecture.md, flux-hub-spoke.md, gpu-notes.md, wsl-networking.md, adr/ + log path note. |

### Per-Step Timing Breakdown (Reconstructed)

Sourced from Phase 5 git history (PROJECT.md "Validated" rows + 05-CONTEXT.md per-step UX notes); the recorded total `rebuild elapsed seconds: 190` from `/tmp/karyon-rebuild.log` is the canonical baseline.

| Step                | Approx Seconds | Notes                                                                                            |
| ------------------- | -------------- | ------------------------------------------------------------------------------------------------ |
| preflight           | ~5             | Read-only checks PRE-01..14.                                                                     |
| destroy             | ~10            | k3d cluster delete x3 + docker network rm.                                                       |
| create-clusters     | ~45            | k3d cluster create x3 with image pull from local cache; longest single leg.                      |
| pin context         | instant        | Single `kubectl config use-context` (HIGH-1 fix).                                                |
| bootstrap-flux      | ~30            | flux bootstrap github + reconciliation handshake.                                                |
| register-spokes     | ~30            | SA + CRB + Secret + kubeconfig encode + 2 spokes.                                                |
| deploy-examples     | ~30            | Flux GitRepository sync + Kustomization apply on 2 spokes.                                       |
| health-check        | ~40            | Cluster + Flux + Kustomization + DNS + GPU + TLS-SAN + workload validation.                      |
| **Total**           | **~190**       | Phase 5 logged baseline.                                                                         |

> **Caveat:** Per-step timings are reconstructed approximations from Phase 5 logs in git history. Re-measure during a future rebuild and update this table if any step drifts > 25%.

### Failure-Mode Appendix Coverage

| Symptom                                    | Recovery Command           | Routes To                                                |
| ------------------------------------------ | -------------------------- | -------------------------------------------------------- |
| Stale CoreDNS NodeHosts (DNS probe fail)   | `task fix-dns`             | flux-hub-spoke.md, HEALTH-07                             |
| Missing GPU capacity (`nvidia.com/gpu` 0)  | 3-part contract diagnosis  | gpu-notes.md (IMG-03/04/05)                              |
| TLS-SAN mismatch (cert verify fail)        | `task destroy && rebuild`  | CLU-05 immutability rule + openssl probe                 |
| CUDA image disappeared (step 3 cold)       | `task build-image`         | DESTROY-04 (no prune in scripts/)                        |
| Flux bootstrap PAT invalid                 | rotate via GitHub UI       | `.env` GITHUB_TOKEN line                                 |
| `.env` missing keys (PRE-09)               | `cp .env.example .env`     | preflight rerun                                          |
| WSL2 mirrored mode (PRE-14 bridge probe)   | switch to NAT              | wsl-networking.md "Migration: mirrored to NAT"           |

## Verification

### bats DOCS-05 Suite

```
$ bats tests/bats/docs-05-runbook.bats
1..4
ok 1 DOCS-05: docs/rebuild-runbook.md exists and starts with an h1
ok 2 DOCS-05 (D-04): rebuild runbook lists the 7 step names in strict order
ok 3 DOCS-05 (specifics): rebuild runbook references the Phase 5 190-second baseline
ok 4 DOCS-05 (D-04): rebuild runbook has a Common failures appendix
```

All 4 contract tests green (status: 0).

### Acceptance Criteria

| Criterion                                                                | Result |
| ------------------------------------------------------------------------ | ------ |
| `[ -f docs/rebuild-runbook.md ]`                                         | PASS   |
| `head -1` matches `^# `                                                  | PASS (`# Rebuild Runbook`) |
| 7 step markers present and IN STRICT ORDER                               | PASS (lines 45, 59, 78, 111, 125, 141, 152) |
| `grep -E '\b190\b'`                                                      | PASS (Phase 5 warm-cache baseline) |
| `grep -iE '(seconds|minute)'`                                            | PASS (timing units present) |
| `grep -iE '^## (common failures|failure modes)'`                         | PASS (`## Common failures`) |
| `grep -iF 'fix-dns'`                                                     | PASS   |
| `grep -iF 'nvidia.com/gpu'`                                              | PASS   |
| `grep -iF 'tls-san'`                                                     | PASS   |
| `wc -l < docs/rebuild-runbook.md` >= 80                                  | PASS (322 lines) |
| Cross-link to flux-hub-spoke.md                                          | PASS   |
| Cross-link to gpu-notes.md                                               | PASS   |
| Cross-link to wsl-networking.md                                          | PASS   |
| Cross-link to architecture.md                                            | PASS   |
| `bats tests/bats/docs-05-runbook.bats` green                             | PASS (4/4) |

### Side-Effect Check

`bats tests/bats/destroy-rebuild-01-static.bats` still 17/17 green (DESTROY-05 step-marker contract on `scripts/rebuild.sh` is unaffected — the runbook mirrors those markers but does not modify the script).

## Deviations from Plan

None - plan executed exactly as written. The `<action>` block prescribed the full file content; it was authored verbatim with the prescribed D-04 layout, timing table, and failure-mode appendix.

## Commits

- `a085a19` `docs(06-06): add docs/rebuild-runbook.md (DOCS-05)` — single per-task commit; 1 file, +322 lines.

## Self-Check: PASSED

- File exists: `/home/rich/code/gsd/karyon/.claude/worktrees/agent-abe13ccc88eb65156/docs/rebuild-runbook.md` (FOUND)
- Commit exists: `a085a19` (FOUND in git log)
- bats DOCS-05: 4/4 green
- All 14 acceptance criteria green

## Notes for Future Phases

- The per-step timings in this runbook are reconstructed approximations from Phase 5 git history; the canonical baseline is the recorded 190-second total from `/tmp/karyon-rebuild.log`. If a future rebuild reveals per-step drift > 25%, update the per-step table; the 190-second total is the authoritative figure to defend.
- The failure-mode appendix is symptom-keyed (not component-keyed) on purpose: a mid-incident reader sees a symptom in the log and pattern-matches to a recovery command. New failure modes discovered in subsequent operations should be added in the same symptom→recovery pattern.
- Cross-links currently point at `architecture.md`, `flux-hub-spoke.md`, `gpu-notes.md`, `wsl-networking.md`, and `adr/0004-hub-only-flux-control-plane.md`. Plan 07 (or whichever plan finalizes ADR numbering) should verify the ADR filename still matches; if it changes, update the cross-link in this runbook.
