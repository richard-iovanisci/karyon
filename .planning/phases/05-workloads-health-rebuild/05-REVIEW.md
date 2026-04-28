---
phase: 05-workloads-health-rebuild
reviewed: 2026-04-28T16:32:25Z
depth: standard
files_reviewed: 23
files_reviewed_list:
  - Taskfile.yml
  - clusters/spoke-apps/kustomization.yaml
  - clusters/spoke-ml/kustomization.yaml
  - examples/gpu-smoke-test/job.yaml
  - examples/gpu-smoke-test/kustomization.yaml
  - examples/gpu-smoke-test/namespace.yaml
  - examples/podinfo/deployment.yaml
  - examples/podinfo/kustomization.yaml
  - examples/podinfo/namespace.yaml
  - examples/podinfo/service.yaml
  - scripts/deploy-examples.sh
  - scripts/destroy.sh
  - scripts/fix-coredns.sh
  - scripts/health-check.sh
  - scripts/rebuild.sh
  - scripts/register-spokes-for-flux.sh
  - tests/bats/deploy-examples-01-static.bats
  - tests/bats/deploy-examples-02-kustomize-build.bats
  - tests/bats/destroy-rebuild-01-static.bats
  - tests/bats/fix-coredns-01-static.bats
  - tests/bats/health-check-01-static.bats
  - tests/bats/phase5-02-live.bats
  - tests/bats/register-spokes-01-static.bats
findings:
  critical: 3
  warning: 3
  info: 0
  total: 6
status: issues_found
---

# Phase 05: Code Review Report

**Reviewed:** 2026-04-28T16:32:25Z
**Depth:** standard
**Files Reviewed:** 23
**Status:** issues_found

## Summary

Reviewed the Phase 5 workload, health, rebuild, spoke-registration, and Bats coverage files. The main risks are in destructive/remediation flows: `fix-coredns` can report success after the DNS repair fails, and `rebuild` can delete the local lab before proving the rebuild prerequisites are available. The test suite also misses assertions that would have caught those regressions.

## Critical Issues

### CR-01: BLOCKER - fix-coredns exits successfully when the DNS repair fails

**File:** `scripts/fix-coredns.sh:100`
**Issue:** The post-restart spoke DNS probe uses `warn` when `getent hosts` still fails, and the summary only exits nonzero when `FAIL > 0`. That means `task fix-dns` can print `CoreDNS NodeHosts refresh complete` and exit 0 while hub DNS is still broken for one or both spokes. Automation and users will proceed even though `health-check` will still fail.
**Fix:**
```bash
dns_ok=1
for spoke in spoke-ml spoke-apps; do
  if kubectl --context "${HUB_CTX}" -n "${FLUX_NS}" exec deploy/source-controller -- \
       getent hosts "k3d-${spoke}-server-0" >/dev/null 2>&1; then
    pass "spoke DNS ok: hub can resolve k3d-${spoke}-server-0"
  else
    fail "spoke DNS still failing for k3d-${spoke}-server-0 after hub-flux stop/start.
       The k3d CoreDNS NodeHosts workaround did not fully resolve.
       Fix: rerun: bash scripts/fix-coredns.sh"
    dns_ok=0
  fi
done
[[ "${dns_ok}" -eq 1 ]] || exit 1
```

### CR-02: BLOCKER - rebuild destroys the lab before checking rebuild prerequisites

**File:** `scripts/rebuild.sh:41`
**Issue:** After confirmation, the first chain step is `destroy`. The preflight checks that catch missing tools, `.env`, Docker/GPU blockers, and host readiness do not run until `create-clusters.sh` or `bootstrap-flux.sh`, after the existing clusters have already been deleted. A user can approve a rebuild and be left with no working lab even though known blockers could have been detected before any destructive action.
**Fix:**
```bash
echo ">>> step preflight" | tee -a "$LOG_FILE"
if ! bash "${SCRIPT_DIR}/preflight.sh" 2>&1 | tee -a "$LOG_FILE"; then
  fail "preflight failed; aborting before destructive rebuild"
  exit 1
fi

echo ">>> step destroy" | tee -a "$LOG_FILE"
KARYON_DESTROY_APPROVED=yes bash "${SCRIPT_DIR}/destroy.sh" 2>&1 | tee -a "$LOG_FILE"
```

### CR-03: BLOCKER - fixed /tmp rebuild log can clobber arbitrary files through symlinks

**File:** `scripts/rebuild.sh:16`
**Issue:** `LOG_FILE` is hard-coded to `/tmp/karyon-rebuild.log`, and line 20 truncates it with `: > "$LOG_FILE"`. If that path is a symlink, the script follows it and truncates the target with the user's permissions. This is a local file-clobber/data-loss risk in a destructive command.
**Fix:**
```bash
LOG_FILE="${KARYON_REBUILD_LOG_FILE:-/tmp/karyon-rebuild.log}"
if [[ -L "${LOG_FILE}" || ( -e "${LOG_FILE}" && ! -f "${LOG_FILE}" ) ]]; then
  fail "unsafe rebuild log path: ${LOG_FILE}"
  exit 1
fi
umask 077
: > "${LOG_FILE}"
```

## Warnings

### WR-01: WARNING - spoke kustomization repair drops existing resources

**File:** `scripts/register-spokes-for-flux.sh:445`
**Issue:** `ensure_spoke_seed` rewrites `clusters/${spoke}/kustomization.yaml` from a fixed template, preserving only `namespace.yaml`, `configmap.yaml`, and the Phase 5 example ref when the example directory currently exists. Any existing or future resource entry is silently removed; if an example directory is temporarily absent, the Phase 5 workload ref is removed too.
**Fix:** Merge required resources into the existing YAML instead of replacing the whole file. For example, load `.resources`, append missing required refs, de-duplicate while preserving existing entries, and only write the file when the merged result differs.

### WR-02: WARNING - fix-coredns tests do not require DNS probe failures to fail the script

**File:** `tests/bats/fix-coredns-01-static.bats:99`
**Issue:** The static suite checks stop/start scope and Flux readiness, but it does not assert that the post-restart spoke DNS probe exists for both spokes or that DNS probe failures call `fail`/exit nonzero. This gap allows CR-01 to pass tests.
**Fix:** Add tests that pin the two `getent hosts k3d-...-server-0` probes and reject a `warn`-only failure path in that section.

### WR-03: WARNING - rebuild tests do not require preflight before the destructive step

**File:** `tests/bats/destroy-rebuild-01-static.bats:46`
**Issue:** The rebuild chain-order test starts with `destroy` and never asserts a preflight gate before deletion. This leaves the destructive ordering regression in CR-02 untested.
**Fix:** Add a static order assertion that the first `bash "${SCRIPT_DIR}/preflight.sh"` or `>>> step preflight` marker appears before `>>> step destroy`.

---

_Reviewed: 2026-04-28T16:32:25Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
