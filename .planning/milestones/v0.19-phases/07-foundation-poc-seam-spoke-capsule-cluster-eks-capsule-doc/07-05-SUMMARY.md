---
phase: 07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc
plan: 05
subsystem: poc-capsule-runbook
tags: [poc-capsule, fix-dns, runbook, host-restart, taskfile-sibling, p31-isolation, d-16, d-17, adr-004]
dependency_graph:
  requires:
    - "07-00 (Wave 0 bats scaffold; CAPCLU-03 + CAPCLU-04 contracts authored before this plan)"
  provides:
    - "task fix-dns-poc-capsule -> scripts/poc/capsule/fix-dns.sh (CAPCLU-03)"
    - "docs/poc-capsule.md operator runbook (CAPCLU-04)"
    - "Reserved-ports table mentioning 30443 (Pitfall 4 mitigation surface for Phase 8 capsule-proxy install)"
  affects:
    - "Phase 8 (capsule-proxy NodePort 30443 install will reference docs/poc-capsule.md Reserved ports table)"
    - "Phase 11 (live regression: task rebuild SLO < 230s with spoke-capsule alive depends on D-12 / P31 isolation preserved here)"
tech_stack:
  added:
    - "no new external deps -- bash script + markdown only"
  patterns:
    - "Sibling Taskfile entry (NOT parent/child env-var dispatch -- D-16 anti-pattern)"
    - "Direct port of scripts/fix-coredns.sh with Flux + post-restart-spoke-DNS-probe sections OMITTED (D-16/D-17)"
    - "Quickstart-depth runbook (Discretion default per CONTEXT.md)"
key_files:
  created:
    - "scripts/poc/capsule/fix-dns.sh (75 lines, 755 mode)"
    - "docs/poc-capsule.md (144 lines)"
  modified:
    - "Taskfile.yml (+5 lines: fix-dns-poc-capsule sibling task)"
    - "tests/bats/repo-hygiene-02-taskfile.bats (regex widened from scripts/[a-z][a-z0-9-]+\\.sh to scripts/[a-z0-9/-]+\\.sh to accept P31-isolated POC subpath)"
decisions:
  - "Mirrored scripts/fix-coredns.sh structure exactly: tool gate -> stop/start -> node readiness -> summary; OMITTED Flux readiness + post-restart spoke DNS probe sections (D-17 / D-16)"
  - "Sibling Taskfile task (NOT parent/child env-var dispatch) per D-16; existing fix-dns task preserved unchanged"
  - "Quickstart depth for poc-capsule.md: Frontmatter, h1, property table, Host restart recovery (quickstart + expected output + verification + sibling-task table), Troubleshooting (4 scenarios), Reserved ports table, Related references (Discretion default per CONTEXT.md §Discretion)"
  - "Pitfall 4 mitigation: Reserved-ports table makes 30443 reservation visible to future POC authors who consult either docs/poc-capsule.md or docs/capsule-on-eks.md"
metrics:
  duration: "~25 minutes"
  completed_date: "2026-04-29"
  tasks_completed: 2
  files_created: 2
  files_modified: 2
  bats_tests_passing_in_scope: 5  # CAPCLU-03 (4 tests) + CAPCLU-04 (1 test)
  bats_tests_regression_count: 0  # widened repo-hygiene-02 regex eliminates the only thin-wrapper regression
---

# Phase 07 Plan 05: spoke-capsule fix-dns + Operator Runbook Summary

POC host-restart recovery bookend lands: `task fix-dns-poc-capsule` recovers spoke-capsule alone (D-16 / D-17 / ADR-004 invariants intact); `docs/poc-capsule.md` ships at quickstart depth with Host restart recovery + Troubleshooting + Reserved-ports table.

## What Was Built

### scripts/poc/capsule/fix-dns.sh (CAPCLU-03)

A direct, structurally faithful port of `scripts/fix-coredns.sh` adapted for the spoke-capsule cluster alone. Sections (in order):

1. **Tool gate**: requires `k3d` + `kubectl` (DROPS `flux` from analog -- D-17 means there is no Flux on spoke-capsule)
2. **${POC_CLUSTER} stop/start**: `k3d cluster stop spoke-capsule` then `k3d cluster start spoke-capsule --wait --timeout 120s`
3. **${POC_CLUSTER} node readiness**: `kubectl --context k3d-spoke-capsule wait --for=condition=Ready node --all --timeout=120s`
4. **Summary**: pass/warn/fail counts; final "CoreDNS NodeHosts refresh complete for spoke-capsule" message

**Sections OMITTED relative to scripts/fix-coredns.sh** (intentional, locked by D-16/D-17):
- Flux readiness count + `kubectl wait` for flux controllers (D-17: NO Flux on spoke-capsule)
- `flux check` invocation (D-17: NO Flux on spoke-capsule)
- Post-restart spoke DNS probe via in-hub `getent hosts` (D-16: hub-flux interaction belongs to existing `task fix-dns`, not this script)

The script is intentionally shorter (~75 lines vs ~122 in the analog).

### Taskfile.yml: fix-dns-poc-capsule sibling task (CAPCLU-03)

Appended a new top-level sibling task entry (NOT parent/child env-var dispatch -- D-16 anti-pattern explicitly rejects that shape):

```yaml
  fix-dns-poc-capsule:
    desc: Stop/start spoke-capsule to refresh stale k3d CoreDNS NodeHosts (POC; does NOT affect default fix-dns)
    cmds:
      - bash scripts/poc/capsule/fix-dns.sh
```

Existing `fix-dns:` task block preserved byte-for-byte (still calls `bash scripts/fix-coredns.sh` for hub-flux only).

### docs/poc-capsule.md: POC Operator's Runbook (CAPCLU-04)

A 144-line quickstart-depth runbook (Discretion default per CONTEXT.md §"Discretion") with:

- **Frontmatter**: status, audience, purpose, scope (calling out that Phase 7 ships only Host restart recovery + Troubleshooting; Phase 10 will add tenant kubeconfig delivery; Phase 11 will add teardown procedure)
- **h1 + status callout**: links to `docs/capsule-on-eks.md` and `docs/architecture.md`
- **Cluster property table**: cluster name, apiserver port (6446), reserved NodePort (30443), network (`k8s-net`), TLS SAN, image, kubeconfig context
- **## Host restart recovery**: 4 sub-sections (Quickstart, What to expect, How to verify, Distinct from `task fix-dns`)
- **## Troubleshooting**: 4 scenarios (cluster fails to stop / fails to start within 120s / Node never reaches Ready=True / hub-flux Kustomizations show errors against spoke-capsule)
- **## Reserved ports**: table with 6446 + 30443 reservations and Phase attribution; explicit note that future POCs adding ports must extend `scripts/preflight.sh` `check_port_strict` invocations and update this table (Pitfall 4 mitigation)
- **## Related references**: 5 cross-links (capsule-on-eks.md, create-cluster.sh, register-poc-cluster.sh, fix-dns.sh, fix-coredns.sh)

## Tasks Completed

| Task | Name                                                                                        | Commit  | Files                                                                                          |
| ---- | ------------------------------------------------------------------------------------------- | ------- | ---------------------------------------------------------------------------------------------- |
| 1    | Create scripts/poc/capsule/fix-dns.sh -- k3d stop/start spoke-capsule alone (D-16 + D-17)   | 2ec95eb | scripts/poc/capsule/fix-dns.sh (new, executable)                                               |
| 2    | Add fix-dns-poc-capsule task to Taskfile.yml + create docs/poc-capsule.md runbook            | d71000c | Taskfile.yml (mod), docs/poc-capsule.md (new), tests/bats/repo-hygiene-02-taskfile.bats (mod)  |

## Verification Results

### Plan-level verification (per <verification> section)

- `bash -n scripts/poc/capsule/fix-dns.sh` -> 0 (PASS)
- `task --list-all` shows both `fix-dns:` and `fix-dns-poc-capsule:` entries (PASS)
- `bats tests/bats/poc-cluster-01-static.bats --filter 'CAPCLU-0[34]'` -> 5/5 GREEN
  - CAPCLU-03 (4 tests): exists+strict+sources preflight-lib, stops/starts ONLY spoke-capsule, ZERO flux check/reconcile, Taskfile entry wired
  - CAPCLU-04 (1 test): docs/poc-capsule.md with all 4 required literals
- `bats tests/bats/poc-isolation-01-static.bats` -> 3/3 GREEN (P31 / D-12 still hold; new POC scripts under `scripts/poc/capsule/` excluded from v0.18 script list)
- `bats tests/bats/fix-coredns-01-static.bats` -> 16/16 GREEN (v0.18 baseline preserved)
- `bats tests/bats/repo-hygiene-02-taskfile.bats` -> 3/3 GREEN (regex widened to accept P31-isolated POC subpath while preserving thin-wrapper invariant)

### Out-of-scope failures (expected RED -- belong to other Phase 7 plans)

The full bats suite has 46 RED tests across the suite. ALL are scope of OTHER Phase 7 plans:

- Tests 79-87 (EKSDOC-01 -- 9 tests): Plan 07-01 (`docs/capsule-on-eks.md`) -- running in parallel
- Tests 134-139 (CAPCLU-01/02 -- 6 tests): Plan 07-03 (`scripts/poc/capsule/create-cluster.sh`) + Plan 07-04 (`clusters/hub-flux/pocs/capsule.yaml`)
- Tests 148-155 (POC-01 -- 6 tests): Plan 07-02 (KARYON POC MOUNT sentinel)
- Tests 181-201 (PRE-15 + POC-02 -- 19 tests): Plan 07-04 (preflight 30443 reservation + register-poc-cluster.sh)
- Tests 261-270 (POC-03 -- 6 tests): Plan 07-XX (.gitignore + .gitleaks.toml extensions)

ZERO failures attributable to this plan (07-05).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Widened repo-hygiene-02-taskfile.bats thin-wrapper regex to accept P31-isolated POC subpath**

- **Found during:** Task 2 verification (`bats tests/bats/`)
- **Issue:** Pre-existing test `tests/bats/repo-hygiene-02-taskfile.bats` line 33 enforced thin-wrapper invariant via regex `bash scripts/[a-z][a-z0-9-]+\.sh$` -- which hardcodes flat `scripts/` paths. The plan REQUIRES adding `bash scripts/poc/capsule/fix-dns.sh` to Taskfile.yml (per acceptance criteria); the test was authored in Phase 6 BEFORE D-12 / P31 isolation introduced the `scripts/poc/<subsystem>/` convention. Without this fix, Task 2 caused a v0.18 regression in test 253 of the full bats suite.
- **Fix:** Widened the regex to `bash scripts/[a-z0-9/-]+\.sh$` to accept the P31-isolated POC subpath. Thin-wrapper invariant preserved -- the test still rejects ANY non-`bash <path>.sh` cmds: entry (sanity-checked: rejects inline `kubectl get nodes`, `docker ps`, etc.).
- **Files modified:** tests/bats/repo-hygiene-02-taskfile.bats (regex change in test 2 + descriptive comment + minor title update from `<name>.sh` to `<path>.sh`)
- **Commit:** d71000c (Task 2)
- **Why Rule 3:** This is a blocking issue caused by the plan's required Taskfile change. The regex was authored in Phase 6 in isolation from the v0.19 P31 decision; widening it preserves the test's intent (reject inline tool invocations) while accommodating the now-required POC isolation subpath. Plan 07-05's success criteria require "no v0.18 regression"; without this fix, test 253 would be RED for the same reason every other Phase 7 plan that lands a POC sub-script would re-trigger.

## Threat Model Attestation

| Threat ID                | Disposition | Verification                                                                                                                                                                                                                                              |
| ------------------------ | ----------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| T-7-D-16                 | mitigate    | Bats test 8 (`CAPCLU-03 / D-16`) GREEN: greps for `k3d cluster stop ${cluster}` / `k3d cluster start ${cluster}` for each of {hub-flux, spoke-ml, spoke-apps} in non-comment lines and asserts non-match. ZERO matches in fix-dns.sh body. |
| T-7-D-17 / ADR-004        | mitigate    | Bats test 9 (`CAPCLU-03 / D-17 / ADR-004`) GREEN: greps `flux[[:space:]]+(check|reconcile)` in non-comment lines and asserts non-match. ZERO matches in fix-dns.sh body.                                                                                  |
| T-7-D-12                 | mitigate    | Bats `poc-isolation-01-static.bats` 3/3 GREEN: v0.18 scripts have ZERO `spoke-capsule`, ZERO `register-poc-cluster`, ZERO `scripts/poc/` mentions. New script lives strictly under `scripts/poc/capsule/`.                                                  |
| T-7-Pitfall-4            | mitigate    | docs/poc-capsule.md "Reserved ports" table makes 30443 reservation visible. Future POC authors who consult docs/poc-capsule.md (or docs/capsule-on-eks.md, separate plan) see the reservation explicitly.                                                |
| T-7-D-16-anti            | mitigate    | Bats test 10 GREEN: `fix-dns-poc-capsule:` is a top-level sibling under `tasks:` in Taskfile.yml; cmds: line is the literal `bash scripts/poc/capsule/fix-dns.sh`; NO env-var dispatch shape.                                                              |
| T-7-CAPCLU-04-discretion | accept      | Per Discretion default + CONTEXT.md §"Discretion": Phase 7 ships ONLY Host restart recovery + Troubleshooting sections. Phase 10 will add Tenant kubeconfig delivery; Phase 11 will add Teardown procedure. Frontmatter `scope:` field documents this.    |

## Self-Check

- [x] scripts/poc/capsule/fix-dns.sh exists and is executable
- [x] docs/poc-capsule.md exists with 4 required literals (Host restart recovery, Troubleshooting, task fix-dns-poc-capsule, 30443)
- [x] Taskfile.yml has fix-dns-poc-capsule sibling entry; existing fix-dns task preserved
- [x] Commits 2ec95eb + d71000c exist in git log
- [x] Phase 7 contracts in scope (CAPCLU-03 + CAPCLU-04) GREEN
- [x] No deviations from D-12 / D-16 / D-17 / ADR-004
- [x] No file deletions in either commit
- [x] No untracked files left behind

## Self-Check: PASSED
