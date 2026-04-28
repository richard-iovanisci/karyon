---
phase: 05
slug: workloads-health-rebuild
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-04-27
---

# Phase 05 - Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Bats + shell/yq/kubectl/flux checks |
| **Config file** | none |
| **Quick run command** | `bats tests/bats/deploy-examples-01-static.bats tests/bats/health-check-01-static.bats tests/bats/destroy-rebuild-01-static.bats` |
| **Full suite command** | `bats tests/bats/deploy-examples-01-static.bats tests/bats/health-check-01-static.bats tests/bats/destroy-rebuild-01-static.bats tests/bats/phase5-02-live.bats` |
| **Estimated runtime** | static ~10s; live destructive up to 20m |

## Sampling Rate

- **After every task commit:** Run the static Bats suites that cover files touched
  by the task.
- **After every plan wave:** Run all Phase 5 static Bats suites.
- **Before `$gsd-verify-work`:** Full static suite must be green; live destructive
  suite must be run on the target machine when clusters/GPU are available.
- **Max feedback latency:** static <30s; live destructive <=20m.

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 05-01-01 | 01 | 1 | DEP-01..04 | T-05-01 | No secrets in example manifests | static | `bats tests/bats/deploy-examples-01-static.bats` | no | pending |
| 05-01-02 | 01 | 1 | HEALTH-01..07 | T-05-02 | health-check read-only | static | `bats tests/bats/health-check-01-static.bats` | no | pending |
| 05-01-03 | 01 | 1 | DESTROY-01..06 | T-05-03 | confirmation + no prune | static | `bats tests/bats/destroy-rebuild-01-static.bats` | no | pending |
| 05-02-01 | 02 | 2 | DEP-01..04 | T-05-01 | GitOps-only deploy | static/live | `bash -n scripts/deploy-examples.sh && kubectl kustomize clusters/spoke-apps && kubectl kustomize clusters/spoke-ml` | no | pending |
| 05-03-01 | 03 | 2 | HEALTH-07 | T-05-02 | hub-only stop/start | static | `bash -n scripts/fix-coredns.sh && bats tests/bats/health-check-01-static.bats` | no | pending |
| 05-04-01 | 04 | 3 | HEALTH-01..06 | T-05-02 | read-only ordered gates | static/live | `bash -n scripts/health-check.sh && bats tests/bats/health-check-01-static.bats` | no | pending |
| 05-05-01 | 05 | 4 | DESTROY-01..06 | T-05-03 | typed confirmation, no prune, SLO hard fail | static | `bash -n scripts/destroy.sh scripts/rebuild.sh && bats tests/bats/destroy-rebuild-01-static.bats` | no | pending |
| 05-06-01 | 06 | 5 | DEP/HEALTH/DESTROY all | T-05-04 | full live destructive proof | live | `KARYON_LIVE_TESTS=1 KARYON_LIVE_TESTS_DESTRUCTIVE=1 bats tests/bats/phase5-02-live.bats` | no | pending |

## Wave 0 Requirements

- [ ] `tests/bats/deploy-examples-01-static.bats` - static contracts for D-01..D-08 / DEP-01..04.
- [ ] `tests/bats/health-check-01-static.bats` - static contracts for D-09..D-12 / HEALTH-01..07.
- [ ] `tests/bats/destroy-rebuild-01-static.bats` - static contracts for D-13..D-16 / DESTROY-01..06.
- [ ] `tests/bats/phase5-02-live.bats` - live/destructive contract for final rebuild and health proof.

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Warm-cache rebuild under 20 minutes on target dev box | DESTROY-06 | Depends on local GPU host, Docker cache, GitHub/Flux availability | Run `task rebuild`, capture elapsed output, then run `task health-check`; record result in the Plan 05-06 summary |
| Git push/reconcile timing if local checkout is ahead | DEP-01..04 | Flux reconciles origin/main, not unpushed local files | Commit/push Phase 5 files or confirm the local branch state before live checks |

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies.
- [x] Sampling continuity: no 3 consecutive tasks without automated verify.
- [x] Wave 0 covers all missing references.
- [x] No watch-mode flags.
- [x] Feedback latency < 30s for static checks.
- [x] `nyquist_compliant: true` set in frontmatter.

**Approval:** pending
