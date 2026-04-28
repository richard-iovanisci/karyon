# Phase 5: Workloads + Health + Rebuild - Pattern Map

**Phase:** 05-workloads-health-rebuild  
**Date:** 2026-04-27T21:37:37-04:00

## Reusable Assets

### `scripts/lib/preflight-lib.sh`

Use this in every new script:

```bash
source "${SCRIPT_DIR}/lib/preflight-lib.sh"
section "Section name"
pass "message"
info "already done, skipping: item"
fail "problem.
   Fix: exact command"
```

Counters `PASS`, `WARN`, `FAIL` are already global and should be printed in
script summaries.

### Existing Script Shape

Closest analogs:

- `scripts/create-clusters.sh` for fail-fast ordered gates, cluster existence
  checks, TLS SAN probes, and remediation text.
- `scripts/delete-clusters.sh` for cache preservation and no-prune guardrails.
- `scripts/bootstrap-flux.sh` for Flux checks, reconcile/wait shape, and
  token-safe shell discipline.
- `scripts/register-spokes-for-flux.sh` for GitOps repair, hub-side probes, and
  no direct git mutation.

Every new Phase 5 script should use:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/lib/preflight-lib.sh"
```

### Bats Test Patterns

Use `tests/bats/test_helper.bash`:

- `REPO_ROOT` for anchored paths.
- `require_live()` for live read-only tests.
- `require_live_destructive()` for anything that destroys/rebuilds clusters.

Existing style:

```bash
#!/usr/bin/env bats
load 'test_helper'

setup() {
  SCRIPT="${REPO_ROOT}/scripts/example.sh"
}

@test "requirement: literal contract" {
  [ -f "$SCRIPT" ]
  run grep -F -- 'literal' "$SCRIPT"
  [ "$status" -eq 0 ]
}
```

## File Ownership for Plans

### Plan 05-01

Owns tests only:

- `tests/bats/deploy-examples-01-static.bats`
- `tests/bats/health-check-01-static.bats`
- `tests/bats/destroy-rebuild-01-static.bats`
- `tests/bats/phase5-02-live.bats`

### Plan 05-02

Owns example manifests, spoke kustomization references, deploy script, and
Taskfile `deploy-examples` task:

- `examples/podinfo/*`
- `examples/gpu-smoke-test/*`
- `clusters/spoke-apps/kustomization.yaml`
- `clusters/spoke-ml/kustomization.yaml`
- `scripts/deploy-examples.sh`
- `Taskfile.yml`

### Plan 05-03

Owns DNS fix script and `fix-dns` task:

- `scripts/fix-coredns.sh`
- `Taskfile.yml`

### Plan 05-04

Owns health-check script and `health-check` task:

- `scripts/health-check.sh`
- `Taskfile.yml`

### Plan 05-05

Owns destructive wrappers and `destroy`/`rebuild` tasks:

- `scripts/destroy.sh`
- `scripts/rebuild.sh`
- `Taskfile.yml`

### Plan 05-06

Owns no source files; live execution and timing proof only.

## Known Pitfalls

- Do not use `git add`, `git commit`, or `git push` inside scripts.
- Do not directly apply workload manifests to spokes from `deploy-examples`.
- Do not mutate cluster state from `health-check`.
- Do not call `docker system prune`, `docker builder prune`, or `docker image
  prune` from destroy/rebuild wrappers.
- Do not restart all clusters from `fix-coredns`; only `hub-flux`.
- Do not hide a >20 minute warm-cache rebuild behind a warning; it is a hard
  failure.
- Relative Kustomize references to `../../examples/*` must be verified with the
  pinned toolchain before considering Plan 05-02 complete.

## Output Contracts

- `deploy-examples` must leave podinfo available and GPU Job complete.
- `health-check` must be read-only and fail-fast.
- `fix-dns` must leave hub Flux green.
- `destroy` must require typed `yes` unless an explicit approved env var is set.
- `rebuild` must run the strict chain and enforce 1200 seconds.
