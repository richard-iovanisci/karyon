---
phase: 13-rbac-narrowing-globaltenantresource-seed-delivery-mechanism
reviewed: 2026-05-19T00:00:00Z
depth: standard
files_reviewed: 38
files_reviewed_list:
  - docs/poc-capsule.md
  - pocs/capsule/spoke/global-resources/hello-world.yaml
  - pocs/capsule/spoke/global-resources/kustomization.yaml
  - pocs/capsule/spoke/kustomization.yaml
  - pocs/capsule/spoke/rbac/kustomization.yaml
  - pocs/capsule/spoke/rbac/platform-owner-sa.yaml
  - pocs/capsule/spoke/rbac/platform-owner.yaml
  - pocs/capsule/spoke/rbac/tenant-workload-editor.yaml
  - pocs/capsule/spoke/tenant-crs/alpha.yaml
  - pocs/capsule/spoke/tenant-crs/bravo.yaml
  - pocs/capsule/spoke/tenants/alpha/human-owner-sa.yaml
  - pocs/capsule/spoke/tenants/alpha/kustomization.yaml
  - pocs/capsule/spoke/tenants/bravo/human-owner-sa.yaml
  - pocs/capsule/spoke/tenants/bravo/kustomization.yaml
  - scripts/poc/capsule/issue-platform-owner-kubeconfig.sh
  - scripts/poc/capsule/issue-tenant-kubeconfig.sh
  - scripts/poc/capsule/new-tenant.sh
  - tests/bats/delivery-01-static-mount-sentinel.bats
  - tests/bats/delivery-02-static-paths.bats
  - tests/bats/delivery-03-live-additive-only.bats
  - tests/bats/delivery-04-live-flux-reconcile.bats
  - tests/bats/delivery-05-live-slo-regression.bats
  - tests/bats/negative-rbac-03-webhook-policy.bats
  - tests/bats/push-gate-03-static-tenant-ns-label.bats
  - tests/bats/rbac-01-static-tenant-workload-editor.bats
  - tests/bats/rbac-02-static-platform-owner-sa.bats
  - tests/bats/rbac-03-static-tenant-co-ownership.bats
  - tests/bats/rbac-04-static-human-owner-sa.bats
  - tests/bats/rbac-05-live-tenant-owner-grant-matrix.bats
  - tests/bats/rbac-06-live-tenant-kubeconfig.bats
  - tests/bats/rbac-07-live-flux-sa-preservation.bats
  - tests/bats/rbac-08-live-platform-owner-grant-matrix.bats
  - tests/bats/rbac-09-live-platform-owner-kubeconfig.bats
  - tests/bats/rbac-10-live-tenant-crud.bats
  - tests/bats/seed-01-static-globaltenantresource.bats
  - tests/bats/seed-02-live-existing-tenants.bats
  - tests/bats/seed-03-live-fresh-tenant.bats
  - tests/bats/seed-04-live-shape.bats
findings_summary:
  critical: 2
  warning: 9
  info: 4
  total: 15
status: issues_found
---

# Phase 13: Code Review Report

**Reviewed:** 2026-05-19
**Depth:** standard
**Files Reviewed:** 38
**Status:** issues_found

## Summary

Phase 13 implements Tier-3 tenant-developer least-privilege (`tenant-workload-editor` ClusterRole), Tier-2 platform-owner identity (`platform-owner` SA + dual-subject CRB), `GlobalTenantResource`-based `hello-world` Pod+Service propagation, and operator scripts for kubeconfig minting + new-tenant provisioning. The YAML manifests are tight (Pitfall 13-P3 aggregate-to-* correctly avoided; FQCI image used; clusterRoles non-empty per Pitfall 13-P8). The kubeconfig minter scripts contain solid defenses (umask 0077, symlink rejection, realpath prefix checks), but the second-pass TOCTOU prefix check is weaker than the first and is exploitable in principle. The most consequential bugs are **regression-gate self-invalidations** in bats: `delivery-03-live-additive-only.bats` falls back to `HEAD..HEAD` (empty diff → always passes), and the additive-only diff counter is too loose (matches any `name:` line, not only owners). These tests would not actually catch a non-additive change to alpha/bravo Tenant CRs.

## Critical Issues

### CR-01: delivery-03 additive-only gate self-invalidates via HEAD..HEAD fallback

**File:** `tests/bats/delivery-03-live-additive-only.bats:16-31`
**Issue:** `_base_sha()` returns `HEAD` as the final fallback when neither the `v0.19` tag nor `HEAD~20` / `HEAD~5` exist. When base == HEAD, `git diff HEAD..HEAD -- pocs/capsule/spoke/tenant-crs/alpha.yaml` is **empty**, so `removals` is `0` regardless of what changed. This is the canonical Wave-0 RED gate against accidental removal of `spec.owners[]` entries — the gate cannot fail. On any branch where `v0.19` is absent (the current pre-release state) and `HEAD~20` resolves, the test compares against a 20-commit-old SHA which may itself include Phase 13 owners (depending on commit cadence), further reducing falsifier validity. The contract DELIVERY-03 ("no non-additive diff") is **not actually enforced** in v0.19-tag-absent runs once `HEAD..HEAD` is hit.
**Fix:**
```bash
_base_sha() {
  if git -C "$REPO_ROOT" rev-parse --verify v0.19 >/dev/null 2>&1; then
    git -C "$REPO_ROOT" rev-parse v0.19
    return
  fi
  # Explicit Phase-12-close pin (the orchestrator should provide diff_base via env).
  if [[ -n "${KARYON_PHASE13_BASE_SHA:-}" ]]; then
    git -C "$REPO_ROOT" rev-parse "${KARYON_PHASE13_BASE_SHA}"
    return
  fi
  # No safe fallback exists — bail out hard rather than silently no-op.
  echo "ERROR: cannot resolve Phase 12 base SHA (no v0.19 tag, no KARYON_PHASE13_BASE_SHA)" >&2
  return 1
}

setup() {
  ...
  BASE_SHA="$(_base_sha)" || skip "no resolvable base SHA for additive-only gate"
}
```

### CR-02: delivery-03 'name:' counter matches non-owner lines

**File:** `tests/bats/delivery-03-live-additive-only.bats:45-48,56-59`
**Issue:** `git diff ... | grep -E '^-[^-]' | grep -F 'name:' | wc -l` counts ANY removed line containing `name:`, including:
- `metadata.name:` lines (renaming a Tenant CR — should be a hard violation, but conflates with owners-removal severity)
- `containers[].name:` (in embedded Pod templates — does not apply here but would in the GTR file)
- Any `containerRegistries` future field that might use `name:`
- Comment lines mentioning `name:` (e.g., the existing comment block `spec.owners[].name: ...` on lines 13-14 of alpha.yaml — if removed, would trip the gate even though no owner was removed)

The test does NOT scope to `spec.owners[]` context. A user could remove a comment containing `name:` and trigger a false positive, OR remove an owner entry whose `name:` line happens to be on a continuation that the grep misses. The contract is far looser than its title claims.
**Fix:**
```bash
# Use yq before/after to extract the actual spec.owners[] arrays then compare:
_owner_names_at_rev() {
  local rev="$1" file="$2"
  git -C "$REPO_ROOT" show "${rev}:${file}" 2>/dev/null \
    | yq eval '.spec.owners[].name // ""' - 2>/dev/null \
    | sort -u
}
BEFORE=$(_owner_names_at_rev "$BASE_SHA" pocs/capsule/spoke/tenant-crs/alpha.yaml)
AFTER=$(yq eval '.spec.owners[].name // ""' "$ALPHA" | sort -u)
# comm -23 prints lines in BEFORE not in AFTER (i.e. removed owners)
removals=$(comm -23 <(echo "$BEFORE") <(echo "$AFTER") | grep -c .)
[ "$removals" -eq 0 ]
```

## Warnings

### WR-01: TOCTOU second-pass prefix check uses weaker pattern than primary

**File:** `scripts/poc/capsule/issue-tenant-kubeconfig.sh:217-222` and `scripts/poc/capsule/issue-platform-owner-kubeconfig.sh:205-210`
**Issue:** The primary `--write-to` validation at lines 207 (tenant) / 197 (platform-owner) correctly enforces a `/`-terminated prefix:
```bash
if [[ "$RESOLVED" != "${TMPDIR_RESOLVED}/"* ]]; then
```
But the defense-in-depth second check (after `mkdir -p`) uses the prefix WITHOUT a trailing slash:
```bash
if [[ "$PARENT_REAL" != "${TMPDIR_RESOLVED}"* ]]; then
```
Concrete bypass scenario: an attacker controls a directory `/tmp/karyon-tenants-evil/` (sibling, not under). Because the primary check requires `/tmp/karyon-tenants/`, the primary check rejects this path. So the second check never sees it — UNLESS a symlink swap between the primary check and mkdir relocates the realpath. In that case, `PARENT_REAL` could resolve to `/tmp/karyon-tenants-evil/something`, and `"$PARENT_REAL" != "${TMPDIR_RESOLVED}"*` evaluates **false** (it IS prefixed by `/tmp/karyon-tenants` — the sibling), so the defense-in-depth check **passes** when it should fail. The comment claims this catches TOCTOU symlink swaps but the pattern doesn't.
**Fix:**
```bash
if [[ "$PARENT_REAL" != "${TMPDIR_RESOLVED}" && "$PARENT_REAL" != "${TMPDIR_RESOLVED}/"* ]]; then
  fail "parent dir of '${RESOLVED}' resolves outside ${TENANT_TMPDIR}/ after canonicalization..."
  exit 1
fi
```

### WR-02: new-tenant.sh proceeds past Capsule RoleBinding wait with only a warn

**File:** `scripts/poc/capsule/new-tenant.sh:268-287`
**Issue:** If the 30s wait for `platform-owner` RoleBinding injection in the new tenant namespace times out, the script emits a `warn` and continues to Stage 3 — which will then fail with Forbidden (no RoleBinding grants the platform-owner SA `create serviceaccounts` in this ns yet). The user gets confusing two-step failure: warn → opaque kubectl apply error. The wait is documented as required precondition for Stage 3; if it times out, the only sane behavior is `fail` + exit.
**Fix:**
```bash
if [[ "$PO_BINDING_FOUND" -eq 0 ]]; then
  fail "30s timeout waiting for Capsule per-namespace RoleBinding injection in tenant-${NAME}.
       Inspect: kubectl --kubeconfig=\"$KC\" -n tenant-${NAME} get rolebindings
       Hint:    Capsule controller may be backed up or unreachable; re-run after capsule-controller-manager is Ready."
  exit 1
fi
```

### WR-03: setup_file() failures + skip pattern may bury bats RED diagnostics

**File:** `tests/bats/rbac-05/06/08/09/10-live*.bats`, `tests/bats/negative-rbac-03-webhook-policy.bats:30-34`, `tests/bats/seed-03-live-fresh-tenant.bats:28-30`
**Issue:** Multiple live bats files invoke `issue-{platform-owner,tenant}-kubeconfig.sh ... >/dev/null 2>&1` inside `setup_file()`. If the script fails (e.g., capsule-proxy Secret missing, TLS read failure after retries), the kubeconfig file is never produced, and each test individually `skip`s with `"kubeconfig not minted (setup_file failed; expected RED pre-implementation)"`. This collapses ALL post-implementation failures into "skipped" rather than RED, masking genuine implementation breakage from the suite. After Plans 13-01..03 land (post-RED), failures here should be visible.
**Fix:**
```bash
setup_file() {
  ...
  if ! bash "${REPO_ROOT}/scripts/poc/capsule/issue-platform-owner-kubeconfig.sh" \
        --duration=2h --write-to "${KARYON_BATS_TMPDIR}/po.kubeconfig" 2>"${KARYON_BATS_TMPDIR}/mint.err"; then
    if [[ "${KARYON_PHASE13_STRICT_LIVE:-}" == "1" ]]; then
      cat "${KARYON_BATS_TMPDIR}/mint.err" >&2
      return 1  # surfaces as setup_file failure (all tests fail-with-context, not skip)
    fi
    # else: leave file absent; per-test `skip` for the pre-implementation RED path.
  fi
}
```

### WR-04: setup_file() `skip` may not be honored by all bats versions

**File:** `tests/bats/negative-rbac-03-webhook-policy.bats:22-29`, multiple others
**Issue:** `bats-core` documents `skip` as valid in `setup_file()` since v1.5, but the test files mix `skip` (line 26) with `return 1` (line 24) when `KARYON_PHASE11_STRICT_LIVE=1`. `return 1` from `setup_file()` causes a hard error, not a per-test skip; behavior is subtly different from `skip`. The `_strict_skip` helper at lines 11-19 is the right pattern, but `setup_file()` doesn't use it. Inconsistency between setup_file and per-test setup behavior on strict-live.
**Fix:** apply `_strict_skip` or equivalent inside `setup_file()` consistently, or document the divergence.

### WR-05: duration_to_hours under-converts sub-3600s durations

**File:** `scripts/poc/capsule/issue-tenant-kubeconfig.sh:231-248` and `issue-platform-owner-kubeconfig.sh:216-230`
**Issue:** `duration_to_hours` for unit `s` computes `n / 3600` via bash integer arithmetic. Any duration like `3000s` (50 min) returns `0`; `7200s` returns 2; `3600s` returns 1. Only the `>24h` portability warn depends on this, so durations like `90000s` (25h) → `25` → warn fires correctly. But `89999s` (just under 25h) → `24` → warn skipped though k3s would still honor 25h close enough. Edge: `86400s` exactly = 24h returns 24, the warn says `>24h` so 24h itself does NOT warn. This is consistent with the contract ("Info-warn if > 24h") but the underlying math accepts losing seconds-precision. Worse: compound forms like `1h30m` regex-match `[smhd]` and only the leading `1h` parses (returns 1) — explicitly noted in the comment, but means `25h30m` parses to 25 and warns, while `1d12h` parses to 24 and does NOT warn (even though 36h > 24h). Cross-script asymmetry between platform-owner script (lacks the explicit "strip trailing compound" comment) and tenant script. Inconsistent edge-case handling.
**Fix:** Standardize behavior, or accept the documented limitation; consider switching to `awk` for exact float arithmetic if precision matters, or reject compound forms outright.

### WR-06: delivery-04 status_val capture conflates 'NotFound' with other kubectl errors

**File:** `tests/bats/delivery-04-live-flux-reconcile.bats:18-49`
**Issue:** Each test captures `kubectl ... 2>&1 || true` into `status_val`. If kubectl errors (network blip, permission denied, etc.), `$status_val` contains stderr text mixed with the absent jsonpath result. The only special-case is `grep -qF 'NotFound'`. All other error modes fall through to `[ "$status_val" = "True" ]`, which fails with no diagnostic showing what went wrong (the test prints only "expected: True; got: <stderr blob>"). For a regression gate that should be tight, error mode collapse is a smell.
**Fix:**
```bash
@test "DELIVERY-03 (Flux Ks): poc-capsule-spoke Ready=True on hub-flux" {
  run kubectl --context=k3d-hub-flux get kustomization poc-capsule-spoke \
    -n flux-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
  [ "$status" -eq 0 ] || { echo "kubectl failed: $output"; return 1; }
  [ "$output" = "True" ] || { echo "Not Ready, got: $output"; return 1; }
}
```

### WR-07: rbac-07 owner-preservation test captures stderr into name variable

**File:** `tests/bats/rbac-07-live-flux-sa-preservation.bats:18-56`
**Issue:** Each `kubectl get tenant ... -o jsonpath='{...}' 2>&1 || true` mixes stderr into `$owner`. If kubectl fails for any reason other than `NotFound`, the variable contains the error message, and `[ "$owner" = "system:serviceaccount:..." ]` fails with a confusing message. Only `NotFound` is special-cased. Same anti-pattern as WR-06.
**Fix:** capture stderr separately, fail-fast on non-zero kubectl exit, then compare clean stdout.

### WR-08: delivery-05 SLO test reads /tmp/karyon-rebuild.log without staleness check

**File:** `tests/bats/delivery-05-live-slo-regression.bats:17-32`
**Issue:** `/tmp/karyon-rebuild.log` may be arbitrarily old. There is no `find ... -mmin -N` freshness check, so an older successful rebuild log could falsely satisfy the test long after a regression has been introduced. Combined with `KARYON_REBUILD_APPROVED=1` gating, this means an operator could see `230s` from a prior run and assume the gate confirms current performance. Stale-evidence problem.
**Fix:**
```bash
[ -f "$LOG_FILE" ]
# Reject logs older than 1 hour to prevent stale-evidence pass.
if [[ $(find "$LOG_FILE" -mmin -60 -print 2>/dev/null | wc -l) -eq 0 ]]; then
  echo "rebuild log /tmp/karyon-rebuild.log is stale (>1h old); re-run 'task rebuild' before this gate"
  return 1
fi
```

### WR-09: rbac-02 dual-subject CRB test does not enforce length == 2 (allows orphan extras)

**File:** `tests/bats/rbac-02-static-platform-owner-sa.bats:31-43`
**Issue:** The test asserts that the CRB subjects[] contains the Group AND the SA, each with `length == 1`. It does NOT assert the total `subjects[] | length == 2`. A future edit could add a third subject (e.g., a privilege-escalation Group `cluster-admins` if a reviewer were tricked) without breaking this test. The dual-subject contract per D-13-06 is exactly two subjects.
**Fix:**
```bash
@test "RBAC-02 / D-13-06: CRB subjects[] has exactly 2 entries (no orphan extras)" {
  [ -f "$CRB_YAML" ]
  run yq eval-all 'select(.kind == "ClusterRoleBinding") | .subjects | length' "$CRB_YAML"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]
}
```

## Info

### IN-01: issue-platform-owner-kubeconfig.sh lacks K8S_NAME_RE validator parity

**File:** `scripts/poc/capsule/issue-platform-owner-kubeconfig.sh` (entire file)
**Issue:** The sibling `issue-tenant-kubeconfig.sh:121-135` validates `<tenant>` and `<owner>` positionals against `^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$` as a defense against future automation passing shell-special chars. The platform-owner script has no positional args (SA name is pinned), so the validator is technically unnecessary. But `--duration` is still operator-supplied and flows into `kubectl create token --duration="${DURATION}"`. While shell-quoted properly, an unusual value (e.g., `--duration='$(rm -rf /)'`) would be rejected by kubectl, not by the script. Low risk — `kubectl create token` will fail-closed — but a regex pre-check on `DURATION` (must match `^[0-9]+(s|m|h|d|y)$` or similar) would harden the boundary.
**Fix:** add an explicit `DURATION` regex validator before line 238.

### IN-02: hello-world.yaml Pod has no securityContext / runAsNonRoot

**File:** `pocs/capsule/spoke/global-resources/hello-world.yaml:56-69`
**Issue:** The nginx Pod runs without `securityContext: { runAsNonRoot: true, readOnlyRootFilesystem: true, ... }`. nginx official `library/nginx:alpine` runs as root by default. For a POC demo this is fine, but if PodSecurity admission (`baseline` / `restricted`) is ever enabled on spoke-capsule, GTR propagation will fail. Documenting this as a deferred concern (POC scope) is enough; calling it out so it's not forgotten.
**Fix:** non-blocking. Consider adding `securityContext: { runAsNonRoot: false }` explicit doc, or document that PodSecurity is intentionally not enforced.

### IN-03: new-tenant.sh hardcodes `containerRegistries.allowed: [docker.io]` only

**File:** `scripts/poc/capsule/new-tenant.sh:200-202`
**Issue:** The rendered Tenant CR for new tenants only allows `docker.io`. The seeded `alpha`/`bravo` Tenants allow both `registry.example.io` AND `docker.io`. Fresh tenants provisioned via this script will fail N7-style registry-allowlist negative tests differently from the seeded tenants. Not a bug per the contract (RBAC-05 demo intent), but worth documenting that fresh tenants intentionally have a single-registry allowlist (`docker.io` only) so the GTR propagation works.
**Fix:** add comment block clarifying intent.

### IN-04: setup() in rbac-09 setup_file uses `setup_file` skip pattern, all live setups don't validate Tenant CR labels match the .karyon.io/poc label

**File:** `tests/bats/*-live-*.bats` (broad pattern)
**Issue:** Live bats files repeat `if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then skip ...; fi` boilerplate in both `setup_file` and `setup`. Refactoring into a shared `require_spoke_capsule` helper in `tests/bats/test_helper.bash` would reduce drift risk (one of the existing files already has subtle differences: `rbac-05` uses bare `skip`, `negative-rbac-03` has the `_strict_skip` helper). Maintenance smell, not a bug.
**Fix:** add `require_spoke_capsule` helper in test_helper.bash and use it consistently.

---

_Reviewed: 2026-05-19_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
