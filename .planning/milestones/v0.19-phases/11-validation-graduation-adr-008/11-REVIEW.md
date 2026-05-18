---
phase: 11-validation-graduation-adr-008
reviewed: 2026-05-05T00:00:00Z
depth: standard
files_reviewed: 30
files_reviewed_list:
  - .gitleaks.toml
  - Taskfile.yml
  - clusters/hub-flux/pocs/capsule.yaml
  - docs/adr/0008-capsule-multi-tenancy-graduation.md
  - docs/capsule-on-eks.md
  - pocs/capsule/spoke/config/capsuleconfig.yaml
  - pocs/capsule/spoke/tenants/alpha/namespace.yaml
  - pocs/capsule/spoke/tenants/alpha/tenant.yaml
  - pocs/capsule/spoke/tenants/bravo/namespace.yaml
  - pocs/capsule/spoke/tenants/bravo/tenant.yaml
  - scripts/poc/capsule/destroy-poc.sh
  - scripts/poc/capsule/fail-capsule-webhook.sh
  - tests/bats/docs-adr-template.bats
  - tests/bats/negative-rbac-01-cross-tenant-list.bats
  - tests/bats/negative-rbac-02-escalation.bats
  - tests/bats/negative-rbac-03-webhook-policy.bats
  - tests/bats/negative-rbac-04-bypass-and-flux.bats
  - tests/bats/negative-rbac-05-webhook-down.bats
  - tests/bats/negative-rbac-anti-pattern-lint-static.bats
  - tests/bats/p27-tenant-kustomization-sa-static.bats
  - tests/bats/push-gate-01-static-rbac-postbuild.bats
  - tests/bats/push-gate-02-static-capsuleconfig.bats
  - tests/bats/push-gate-03-static-tenant-ns-label.bats
  - tests/bats/push-gate-04-live-tenant-ns-flux-apply.bats
  - tests/bats/push-gate-05-static-gitleaks-allowlist.bats
  - tests/bats/repo-hygiene-02-taskfile.bats
  - tests/bats/slo-regression-live.bats
  - tests/bats/teardown-01-static-script.bats
  - tests/bats/teardown-02-static-sentinel-preservation.bats
  - tests/bats/teardown-03-live-ordered.bats
findings:
  critical: 3
  warning: 8
  info: 4
  total: 15
status: issues_found
---

# Phase 11: Code Review Report

**Reviewed:** 2026-05-05T00:00:00Z
**Depth:** standard
**Files Reviewed:** 30
**Status:** issues_found

## Summary

Phase 11 ships graduation evidence for the Capsule multi-tenancy POC: ADR-008 with the
DEFER outcome, EKSDOC-01 cross-references rolled forward, the negative-RBAC bats suite
(N1-N12), webhook failure mode + recovery, ordered teardown script, and gitleaks allowlist
tightening. The static-contract layer (push-gate-01..03 + p27 lint + anti-pattern lint)
appears well-formed; ADR-008 satisfies the docs-adr-template lint and EKSDOC-01 frontmatter
declares Status: Reviewed.

Three BLOCKER-class defects landed in the live testing path:
- `destroy-poc.sh` has two pipefail-vulnerable command substitutions in the cascade poll
  that can crash the script mid-teardown if the spoke cluster becomes unreachable.
- The N2 LIST-filter falsifier passes vacuously when no pods exist (no positive assertion
  that the filter actually returned content); given the POC ships zero workload manifests,
  a fresh cluster makes this a real, reachable false-pass path on a security-critical test.

Multiple WARNING-class issues center on permissive grep patterns in negative-rbac tests
(N5 includes "tenant" alone; N6 includes "exceeded" alone) that risk passing the test for
the wrong reason - the same anti-pattern N7 was already tightened against per the inline
comment. Error-swallowing patterns (`2>/dev/null || true`) in destroy-poc.sh's tenant
delete and kubeconfig-mint redirects mask non-not-found failures.

## Critical Issues

### CR-01: destroy-poc.sh cascade poll crashes under set -euo pipefail when kubectl fails

**File:** `scripts/poc/capsule/destroy-poc.sh:127`
**Issue:** Under the script's strict-mode (`set -euo pipefail` on line 26), the assignment
`REMAINING=$(kubectl --context=k3d-spoke-capsule get ns -l capsule.clastix.io/tenant -o name 2>/dev/null | wc -l)`
crashes the entire script if kubectl exits non-zero (cluster unreachable, RBAC denied,
apiserver mid-restart, etc.). The `2>/dev/null` swallows stderr, but `pipefail` propagates
kubectl's non-zero exit through the pipeline. Command substitution then fails, and `set -e`
aborts the script.

Empirically verified: `bash -c 'set -euo pipefail; X=$(false 2>/dev/null | wc -l)'` exits 1.

The teardown is then incomplete: Steps 4 (suspend operator outer K) and 5 (optional
`k3d cluster delete --full`) never execute. The user's CI/script may silently consume the
non-zero exit and surface no error.

**Fix:**
```bash
REMAINING=$(kubectl --context=k3d-spoke-capsule get ns -l capsule.clastix.io/tenant -o name 2>/dev/null | wc -l || echo 0)
```

Or equivalently, decouple the pipeline from the substitution:
```bash
RAW=$(kubectl --context=k3d-spoke-capsule get ns -l capsule.clastix.io/tenant -o name 2>/dev/null || true)
REMAINING=$(printf '%s\n' "$RAW" | grep -c '^namespace/' || true)
```

### CR-02: destroy-poc.sh NS_LIST enumeration crashes under set -euo pipefail when kubectl fails

**File:** `scripts/poc/capsule/destroy-poc.sh:137`
**Issue:** Same root cause as CR-01:
`NS_LIST=$(kubectl --context=k3d-spoke-capsule get ns -l capsule.clastix.io/tenant -o name 2>/dev/null | sed 's|namespace/||')`
crashes the script under `set -euo pipefail` if kubectl exits non-zero. This branch only
executes when `i == 60` (the PVC strand mitigation path), so it is reached precisely when
the cascade is already abnormal - making transient cluster issues a likely co-occurrence.
The script aborts before any PVC finalizer patching can run.

**Fix:**
```bash
NS_LIST=$(kubectl --context=k3d-spoke-capsule get ns -l capsule.clastix.io/tenant -o name 2>/dev/null | sed 's|namespace/||' || true)
```

Compare with the SUSPEND_STATE pattern on lines 76, 91, 106, 160, which correctly uses
`|| echo "absent"` inside the substitution. The same defensive idiom is needed here.

### CR-03: negative-rbac-01 N2 LIST-filter falsifier passes vacuously when no pods exist

**File:** `tests/bats/negative-rbac-01-cross-tenant-list.bats:58-66`
**Issue:** The N2 test verifies the proxy LIST filter via:
```bash
run kubectl --kubeconfig="$ALPHA_KUBECONFIG" get pods --all-namespaces -o jsonpath='...'
[ "$status" -eq 0 ]
while IFS= read -r ns; do
  [[ -z "$ns" ]] && continue
  [[ "$ns" =~ ^(tenant-alpha|alpha-) ]] || { echo "leaked namespace: $ns"; return 1; }
done <<< "$(echo "$output" | sort -u)"
```

When no pods are running cluster-wide visible to alpha, `$output` is empty. The while loop
iterates zero times. The test passes WITHOUT verifying the filter actually filters
anything. Verified empirically: an empty `$output` yields no loop iterations.

This is a security-critical test: it proves the proxy filters cross-tenant LIST requests.
Phase 11 ships ZERO Pod/Deployment manifests under `pocs/capsule/` (verified via
`find pocs/capsule -name '*.yaml' -exec grep -l 'kind: Pod\|kind: Deployment' {} \;`
returning empty). On a fresh cluster, N2 ships GREEN without proving the security
property. If the proxy filter regresses AND alpha happens to have no pods, N2 will not
catch the regression.

The vacuous-truth issue mirrors the N7 anti-pattern fix the reviewer already documented
inline: "N7 may pass for unrelated reasons" - but N2 was not similarly tightened.

**Fix:** Add a positive assertion that LIST returned at least one entry, or seed a known
pod in `tenant-alpha`/`alpha-app1` as a setup_file precondition:
```bash
@test "N2 -- cluster-wide LIST filtered to alpha-owned namespaces (proxy LIST filter)" {
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" get pods --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{"\n"}{end}'
  [ "$status" -eq 0 ]
  # POSITIVE assertion: LIST must return at least one pod (otherwise the filter cannot be falsified)
  POD_COUNT=$(echo "$output" | sort -u | grep -c .)
  [ "$POD_COUNT" -gt 0 ] || { echo "N2 vacuous: alpha sees zero pods cluster-wide; cannot prove filter"; return 1; }
  while IFS= read -r ns; do
    [[ -z "$ns" ]] && continue
    [[ "$ns" =~ ^(tenant-alpha|alpha-) ]] || { echo "leaked namespace: $ns"; return 1; }
  done <<< "$(echo "$output" | sort -u)"
}
```

Alternatively, `setup_file` can `kubectl run probe-n2 --image=... -n alpha-app1` to seed a
pod, then `teardown_file` removes it.

## Warnings

### WR-01: fail-capsule-webhook.sh printf format string contains shell variable (SC2059)

**File:** `scripts/poc/capsule/fail-capsule-webhook.sh:61`
**Issue:** `printf "\n%scapsule-controller-manager scaled to ${REPLICAS}.%s\n" "${C_GREEN}" "${C_RESET}"`
interpolates `${REPLICAS}` directly into the format string. This is the shellcheck SC2059
anti-pattern. While `REPLICAS` is validated as `^[01]$` (so format injection is impossible
in practice), the pattern is still bad form: it breaks under future schema changes (e.g.,
allowing N != 0|1) and confuses readers about whether printf format-specifier interpolation
is intentional.

**Fix:**
```bash
printf "\n%scapsule-controller-manager scaled to %s.%s\n" "${C_GREEN}" "${REPLICAS}" "${C_RESET}"
```

### WR-02: destroy-poc.sh tenant delete swallows non-not-found errors

**File:** `scripts/poc/capsule/destroy-poc.sh:117-118`
**Issue:**
```bash
kubectl --context=k3d-spoke-capsule delete tenant alpha bravo --wait=true --ignore-not-found 2>/dev/null || true
pass "Tenant CRs deleted (or already absent)"
```

The `2>/dev/null || true` mask absorbs ALL kubectl failures: cluster unreachable, RBAC
denied, webhook timeout, etc. The `--ignore-not-found` flag only handles already-deleted
Tenants - other failure classes are silently swallowed and the script unconditionally
prints success. Subsequent steps (cascade poll, suspend operator) then run against
unexpected state and may produce confusing downstream errors.

**Fix:** Capture the exit code, distinguish not-found from other failures, and `warn` on
unexpected non-zero exits while still proceeding:
```bash
DELETE_RC=0
DELETE_OUT=$(kubectl --context=k3d-spoke-capsule delete tenant alpha bravo --wait=true --ignore-not-found 2>&1) || DELETE_RC=$?
if [[ "$DELETE_RC" -eq 0 ]]; then
  pass "Tenant CRs deleted (or already absent)"
else
  warn "tenant delete exited $DELETE_RC: $DELETE_OUT (continuing teardown best-effort)"
fi
```

### WR-03: N5 grep alternation includes 'tenant' - false-pass risk for RBAC denials

**File:** `tests/bats/negative-rbac-03-webhook-policy.bats:69`
**Issue:** `echo "$output" | grep -qE "(prefix|forceTenantPrefix|tenant)"` matches the
substring `tenant` anywhere in the kubectl output. Real-world kubectl errors frequently
mention "tenant-alpha" (the namespace context, the User in `User "alpha" cannot create...`,
the impersonation chain, etc.). If the apiserver/RBAC layer denies the
`create namespace evil-no-prefix` request BEFORE Capsule's webhook fires (e.g., because
alpha SA lacks namespace-create permissions), the test passes for the wrong reason -
identical to the N7 anti-pattern the reviewer already explicitly tightened against.

**Fix:** Drop the bare `tenant` alternative and require explicit Capsule-webhook denial
keywords. Add an anti-RBAC-confusion negative assertion mirroring N7's pattern:
```bash
echo "$output" | grep -qE "(prefix|forceTenantPrefix)"
if echo "$output" | grep -qE "(system:serviceaccount|RBAC|cannot create resource)"; then
  echo "N5 ANTI-PATTERN: output matches RBAC-denial keywords -- this is NOT a forceTenantPrefix webhook denial:"
  echo "$output"
  return 1
fi
```

### WR-04: N6 grep alternation includes 'exceeded' - false-pass risk

**File:** `tests/bats/negative-rbac-03-webhook-policy.bats:100`
**Issue:** `echo "$output" | grep -qE "(quota|namespace.*(limit|max)|exceeded)"` includes
`exceeded` as a standalone alternative. Many unrelated kubectl errors contain "exceeded"
(timeout exceeded, request size exceeded, deadline exceeded, etc.). The Pitfall 11-P3
permissive-grep rationale acknowledges this risk but does not mitigate it. Because the
N6 falsifier is graduation-decisive, the false-pass scenario meaningfully degrades
evidence quality.

**Fix:** Tighten to require explicit quota-domain context. Either anchor to "quota" or
require a more specific "exceeded" context such as "namespace count exceeded":
```bash
echo "$output" | grep -qE "(quota|namespace.*(limit|max|exceeded))"
```

This drops the bare `exceeded` alternative; "namespace exceeded N" or "namespace limit"
or "quota" patterns still match.

### WR-05: N6 cleanup runs only when assertions succeed

**File:** `tests/bats/negative-rbac-03-webhook-policy.bats:73-104`
**Issue:** The N6 test creates `alpha-app2` (line 82) and attempts to create `alpha-app3`
(line 98). Cleanup of both namespaces (lines 102-103) runs at the END of the @test, which
under bats `set -e` semantics is unreachable if any earlier assertion fails. Specifically:
- If `[ "$status" -ne 0 ]` on line 99 fails (alpha-app3 unexpectedly created), test exits
  before cleanup; alpha-app2 AND alpha-app3 leak.
- If `grep -qE` on line 100 fails (denial message didn't match), same leak.

The setup_file leftover-cleanup block (lines 41-53) reaps these on next run, but a developer
hitting this in CI or a one-off run will see lingering namespaces and possibly cascading
test failures (subsequent N7/N8 may trip Capsule's quota webhook unexpectedly).

**Fix:** Move cleanup into a bats teardown function that runs regardless of test outcome:
```bash
teardown() {
  kubectl --kubeconfig="$ALPHA_KUBECONFIG" delete namespace alpha-app2 --ignore-not-found --wait=false >/dev/null 2>&1 || true
  kubectl --kubeconfig="$ALPHA_KUBECONFIG" delete namespace alpha-app3 --ignore-not-found --wait=false >/dev/null 2>&1 || true
}
```

Or use `trap` inside the test to ensure cleanup on any exit path.

### WR-06: N8 TOKEN extraction has no validation for null/empty

**File:** `tests/bats/negative-rbac-04-bypass-and-flux.bats:64`
**Issue:** `TOKEN=$(yq eval '.users[0].user.token' "$ALPHA_KUBECONFIG")` returns the literal
string `null` if the path doesn't exist, or empty if the file is malformed. The kubeconfig
heredoc on lines 66-84 then embeds `token: null` (invalid) or `token: ` (invalid YAML),
making downstream kubectl fail with parser errors that don't match the expected RBAC-denial
grep, and the test fails for an opaque reason.

**Fix:** Validate after extraction and skip with a clear message:
```bash
TOKEN=$(yq eval '.users[0].user.token' "$ALPHA_KUBECONFIG")
if [[ -z "$TOKEN" || "$TOKEN" == "null" ]]; then
  _strict_skip "alpha kubeconfig has no .users[0].user.token; cannot construct direct-apiserver bypass test"
fi
```

### WR-07: kubeconfig minting in setup_file silently swallows issuance errors

**Files:**
- `tests/bats/negative-rbac-01-cross-tenant-list.bats:34-37`
- `tests/bats/negative-rbac-02-escalation.bats:30-31`
- `tests/bats/negative-rbac-03-webhook-policy.bats:32-33`
- `tests/bats/negative-rbac-04-bypass-and-flux.bats:38-39`
- `tests/bats/negative-rbac-05-webhook-down.bats:37-38`

**Issue:** All five files invoke `bash "${REPO_ROOT}/scripts/poc/capsule/issue-tenant-kubeconfig.sh" alpha gitops-reconciler --duration=2h --write-to "..." >/dev/null 2>&1`.
The redirects suppress both stdout and stderr. While bats setup_file failure correctly
aborts all tests when the bash invocation returns non-zero, the diagnostic output is
discarded. A developer debugging "setup_file failed" gets no kubeconfig-issuance error to
read - they have to manually re-run the script to see the failure.

**Fix:** Drop `2>&1` so stderr is preserved (bats captures it on test failure):
```bash
bash "${REPO_ROOT}/scripts/poc/capsule/issue-tenant-kubeconfig.sh" alpha gitops-reconciler \
  --duration=2h --write-to "${KARYON_BATS_TMPDIR}/alpha.kubeconfig" >/dev/null
```

Or capture the error and bubble it up:
```bash
if ! bash "${REPO_ROOT}/scripts/poc/capsule/issue-tenant-kubeconfig.sh" alpha gitops-reconciler \
  --duration=2h --write-to "${KARYON_BATS_TMPDIR}/alpha.kubeconfig" 2>&1; then
  echo "issue-tenant-kubeconfig.sh failed for alpha; setup_file aborting" >&2
  return 1
fi
```

### WR-08: Tenant `containerRegistries` field is deprecated in v0.12.4

**Files:**
- `pocs/capsule/spoke/tenants/alpha/tenant.yaml:64-66`
- `pocs/capsule/spoke/tenants/bravo/tenant.yaml:62-64`

**Issue:** Both Tenant CRs use `spec.containerRegistries.allowed` which the inline comment
acknowledges is deprecated in favor of `Enforcement.Registries`. The N7 falsifier specifically
notes "the deprecated form may not trigger the webhook reliably" - meaning the negative-RBAC
test is built on a wobbling foundation. If Capsule v0.12.4 silently downgrades enforcement
on deprecated fields, N7 ships GREEN without proving registry policy enforcement.

**Fix:** Migrate to the non-deprecated form when graduating per the comment's planner note,
or pin Capsule to a version where the deprecated form is still authoritative and document
the version constraint. Example for the new form (verify against your Capsule v0.12.4 schema):
```yaml
spec:
  enforcement:
    registries:
      allowed:
        - registry.example.io
```

If migrating is out-of-scope for v0.19, surface this as a Plan 11-05 carryover with explicit
rollover to Phase 12 / capsule-addon-fluxcd trial.

## Info

### IN-01: N7 grep alternation `(registry|containerRegistries|registries)` is functionally redundant

**File:** `tests/bats/negative-rbac-03-webhook-policy.bats:126`
**Issue:** The alternation `(registry|containerRegistries|registries)` reduces to `registry`
because the substring `registry` is contained in both `containerRegistries` and `registries`.
Adding the longer alternatives is a no-op. Cosmetic only - test logic is unaffected.

**Fix:** Simplify to `grep -qE "registry"` or, if the intent was word boundaries, use
`grep -qE "\b(registry|registries|containerRegistries)\b"` - though the latter has portability
issues across grep flavors.

### IN-02: CapsuleConfiguration uses deprecated `userGroups` field

**File:** `pocs/capsule/spoke/config/capsuleconfig.yaml:37-40`
**Issue:** The inline comment at line 33-36 acknowledges `userGroups is DEPRECATED in v1beta2
(replaced by spec.users)`. Same migration concern as WR-08. Documented; not a defect per se,
but worth tracking as a Plan 11-05 carryover or post-graduation cleanup item.

**Fix:** Track in deferred-items.md alongside the `containerRegistries` migration.

### IN-03: slo-regression-live.bats relies on env-var propagation from setup_file to @tests

**File:** `tests/bats/slo-regression-live.bats:27, 50-51`
**Issue:** `BEFORE_CID` is `export`-ed in `setup_file()` and read in `@test "VAL-04 b"` via
plain variable expansion. bats does propagate exported vars across @tests within a file, so
this works, but the implicit dependency is fragile - if a developer reorders @tests or splits
the file, the test silently breaks (AFTER_CID compares against an undefined BEFORE_CID).

**Fix:** Add a defensive guard in @test b:
```bash
@test "VAL-04 b -- ..." {
  [[ -n "$BEFORE_CID" && "$BEFORE_CID" != "MISSING" ]] || skip "BEFORE_CID not set by setup_file"
  local AFTER_CID=$(docker inspect -f '{{.Id}}' k3d-spoke-capsule-server-0 2>/dev/null || echo "MISSING")
  [[ "$AFTER_CID" != "MISSING" ]] || { echo "spoke-capsule container missing post-rebuild"; return 1; }
  [[ "$BEFORE_CID" == "$AFTER_CID" ]] || { echo "spoke-capsule CID changed: $BEFORE_CID -> $AFTER_CID"; return 1; }
}
```

### IN-04: docs/capsule-on-eks.md frontmatter mixes case conventions

**File:** `docs/capsule-on-eks.md:2-9`
**Issue:** The YAML frontmatter has `Status: Reviewed` (capital S) while peer keys use
lowercase (`audience`, `purpose`, `source-of-truth`, `reviewed`, etc.). Pure cosmetic; no
parser cares (this is a Markdown frontmatter, not a Kubernetes manifest). Suggest aligning to
consistent lowercase.

**Fix:**
```yaml
---
status: Reviewed
audience: Mixed Engineering + Cloud Ops
...
```

---

_Reviewed: 2026-05-05T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
