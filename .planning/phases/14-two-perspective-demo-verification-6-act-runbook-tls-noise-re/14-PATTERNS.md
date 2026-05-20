# Phase 14: Two-Perspective Demo Verification + 6-Act Runbook + TLS-Noise Resolution — Pattern Map

**Mapped:** 2026-05-19
**Files analyzed:** 13 new + 1 modified (docs/capsule-on-eks.md append) = 14
**Analogs found:** 14 / 14 (100% — verification + documentation phase; everything has a precedent in the Phase 13 inheritance set)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `tests/bats/demo-01-live-platform-owner-list.bats` | test (live-RBAC bats) | request-response (kubectl→apiserver) | `tests/bats/rbac-08-live-platform-owner-grant-matrix.bats` | exact |
| `tests/bats/demo-02-live-tenant-owner-scoped-list.bats` | test (live-RBAC bats) | request-response | `tests/bats/rbac-05-live-tenant-owner-grant-matrix.bats` + `negative-rbac-01-cross-tenant-list.bats` (dual-kc setup_file) | exact |
| `tests/bats/demo-03-live-pod-ops.bats` | test (live-RBAC bats) | request-response (kubectl exec/logs) | `tests/bats/rbac-06-live-tenant-kubeconfig.bats` (positive-control kubectl pattern) + `seed-02-live-existing-tenants.bats` (hello-world probing) | role-match |
| `tests/bats/demo-04-live-tenant-secret-forbidden.bats` | test (live-RBAC bats) | request-response (Forbidden assertion) | `tests/bats/rbac-06-live-tenant-kubeconfig.bats` lines 44-53 (exact DEMO-04 idiom verbatim) | exact |
| `tests/bats/demo-05-live-cross-tenant-forbidden.bats` | test (live-RBAC bats) | request-response (cross-tenant Forbidden) | `tests/bats/negative-rbac-01-cross-tenant-list.bats` (N1/N2/N3 verbatim) | exact |
| `tests/bats/demo-06-live-platform-owner-cluster-admin-denials.bats` | test (live-RBAC bats) | request-response (multi-Forbidden matrix) | `tests/bats/rbac-08-live-platform-owner-grant-matrix.bats` (auth can-i ceiling lines 63-94) + Q6 RESEARCH live-captured CRB string | exact |
| `tests/bats/runbook-01-static-acts.bats` | test (static-grep bats) | file-I/O (grep markdown) | `tests/bats/docs-05-runbook.bats` (DOCS-05 strict-order step-marker grep) | exact |
| `tests/bats/runbook-02-static-checklist.bats` | test (static-grep bats) | file-I/O | `tests/bats/seed-01-static-globaltenantresource.bats` (file-exists + grep -F literal) + `docs-05-runbook.bats` | exact |
| `tests/bats/runbook-03-static-tls-noise.bats` | test (static-grep bats) | file-I/O | `tests/bats/seed-01-static-globaltenantresource.bats` (literal-grep with `grep -F`) | exact |
| `tests/bats/runbook-03-static-eks-three-tier.bats` | test (static-grep bats) | file-I/O | `tests/bats/docs-06-eks.bats` (EKSDOC-01 multi-literal grep loop) | exact |
| `tests/bats/runbook-05-static-charlie.bats` | test (static-grep bats) | file-I/O | `tests/bats/rbac-01-static-tenant-workload-editor.bats` (grep -v comments + grep -F literal idiom) | exact |
| `docs/poc-capsule-demo.md` (NEW) | doc (runbook) | narrative + executable shell snippets | `docs/poc-capsule.md` (frontmatter + Active status + sectioned operator runbook) + `docs/rebuild-runbook.md` (Step N — Title cadence + expected-output blocks) | exact (composite) |
| `docs/capsule-on-eks.md` (MODIFY — append ~15 lines) | doc (EKS rough-cut) | additive markdown section | Same file's existing `## Section` shape (lines 34-43 RBAC table; lines 217-225 "What this POC does NOT prove" three-item list) | exact (self-analog) |
| `.planning/phases/14-…/14-VALIDATION.md` (NEW) | planning artifact | narrative validation report | `.planning/phases/13-…/13-VALIDATION.md` | exact (sibling phase) |

## Pattern Assignments

### `tests/bats/demo-01-live-platform-owner-list.bats` (test, live-RBAC)

**Analog:** `tests/bats/rbac-08-live-platform-owner-grant-matrix.bats`

**Header / shebang / comment block** (lines 1-9):
```bash
#!/usr/bin/env bats
# tests/bats/demo-N-live-<slug>.bats
# Phase 14 / Wave 0 (D-14-08 + D-13-15 Nyquist gate)
# DEMO-N — <one-line behavior summary>.
# RED until Plan 14-01 (runbook) + Plan 14-02 (DEMO bats GREEN) land.

load 'test_helper'
```

**setup_file pattern — platform-owner only** (lines 12-25 verbatim from rbac-08):
```bash
setup_file() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
  export KARYON_BATS_TMPDIR="${TMPDIR:-/tmp}/karyon-tenants/bats-${BATS_RUN_TMPDIR##*/}"
  mkdir -p "$KARYON_BATS_TMPDIR"
  bash "${REPO_ROOT}/scripts/poc/capsule/issue-platform-owner-kubeconfig.sh" \
    --duration=2h --write-to "${KARYON_BATS_TMPDIR}/po.kubeconfig" >/dev/null 2>&1
  export PO_KUBECONFIG="${KARYON_BATS_TMPDIR}/po.kubeconfig"
}

teardown_file() {
  rm -rf "$KARYON_BATS_TMPDIR"
}

setup() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
  [ -f "${PO_KUBECONFIG:-/dev/null}" ] || skip "platform-owner kubeconfig not minted (setup_file failed; expected RED pre-implementation)"
}
```

**Core positive-LIST assertion pattern** (DEMO-01 specifics; rbac-08 lines 36-54 inspired):
```bash
@test "DEMO-01 (Tier-2 platform-owner): kubectl get tenants returns alpha + bravo" {
  run kubectl --kubeconfig="$PO_KUBECONFIG" get tenants.capsule.clastix.io \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx 'alpha'
  echo "$output" | grep -qx 'bravo'
}

@test "DEMO-01 (Tier-2 platform-owner): kubectl get namespaces sees tenant-alpha + tenant-bravo" {
  run kubectl --kubeconfig="$PO_KUBECONFIG" get namespaces \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx 'tenant-alpha'
  echo "$output" | grep -qx 'tenant-bravo'
}
```

---

### `tests/bats/demo-02-live-tenant-owner-scoped-list.bats` (test, live-RBAC)

**Analog:** `tests/bats/rbac-05-live-tenant-owner-grant-matrix.bats` (dual-kubeconfig setup_file lines 10-22) + `tests/bats/negative-rbac-01-cross-tenant-list.bats` (proxy LIST-filter idiom lines 58-66).

**Dual-kubeconfig setup_file** (verbatim from rbac-05 lines 10-22):
```bash
setup_file() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
  export KARYON_BATS_TMPDIR="${TMPDIR:-/tmp}/karyon-tenants/bats-${BATS_RUN_TMPDIR##*/}"
  mkdir -p "$KARYON_BATS_TMPDIR"
  bash "${REPO_ROOT}/scripts/poc/capsule/issue-tenant-kubeconfig.sh" alpha human-tenant-owner \
    --duration=2h --write-to "${KARYON_BATS_TMPDIR}/alpha.kubeconfig" >/dev/null 2>&1
  bash "${REPO_ROOT}/scripts/poc/capsule/issue-tenant-kubeconfig.sh" bravo human-tenant-owner \
    --duration=2h --write-to "${KARYON_BATS_TMPDIR}/bravo.kubeconfig" >/dev/null 2>&1
  export ALPHA_KUBECONFIG="${KARYON_BATS_TMPDIR}/alpha.kubeconfig"
  export BRAVO_KUBECONFIG="${KARYON_BATS_TMPDIR}/bravo.kubeconfig"
}
```

**Scoped-LIST assertion pattern** (verbatim from negative-rbac-01 lines 58-66):
```bash
@test "DEMO-02 (alpha scoped LIST): cluster-wide ns LIST returns only alpha-owned via proxy" {
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" get namespaces \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'
  [ "$status" -eq 0 ]
  while IFS= read -r ns; do
    [[ -z "$ns" ]] && continue
    [[ "$ns" =~ ^(tenant-alpha|alpha-) ]] || { echo "leaked namespace: $ns"; return 1; }
  done <<< "$(echo "$output" | sort -u)"
}
```

Mirror @test for bravo (swap `ALPHA_KUBECONFIG`→`BRAVO_KUBECONFIG` and the regex).

---

### `tests/bats/demo-03-live-pod-ops.bats` (test, live-RBAC)

**Analog:** `tests/bats/rbac-06-live-tenant-kubeconfig.bats` (positive-control kubectl + Forbidden idiom) for structural skeleton; Q3 + Q4 RESEARCH for verbatim probe strings.

**Use the dual-kubeconfig setup_file from demo-02 above** (mints PO + ALPHA + BRAVO; needs all three because DEMO-03 exercises platform-owner-via-proxy AND tenant-owner-via-proxy for both logs and exec).

**Exec assertion pattern** (Q3 RESEARCH verbatim live-captured probe):
```bash
@test "DEMO-03 (tenant-owner alpha exec): kubectl exec hello-world emits 'ok'" {
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" -n tenant-alpha exec hello-world \
    -- sh -c "echo ok-from-shell"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "ok-from-shell"
}

@test "DEMO-03 (tenant-owner alpha logs): kubectl logs hello-world emits 'worker process'" {
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" -n tenant-alpha logs hello-world --tail=3
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "worker process"
}
```

(Mirror @test for `BRAVO_KUBECONFIG` / `tenant-bravo`; and again for `PO_KUBECONFIG` probing both tenant namespaces per DEMO-03 cross-perspective contract.)

---

### `tests/bats/demo-04-live-tenant-secret-forbidden.bats` (test, live-RBAC)

**Analog:** `tests/bats/rbac-06-live-tenant-kubeconfig.bats` lines 44-53 (DEMO-04 idiom verbatim — secret create returns Forbidden with idempotent cleanup).

**Forbidden-create-secret idiom** (verbatim from rbac-06 lines 44-53):
```bash
@test "DEMO-04 (alpha boundary): tenant-owner cannot create secret in own namespace" {
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" create secret generic demo-deny \
    --from-literal=k=v -n tenant-alpha
  [ "$status" -ne 0 ]
  # Pitfall 11-P3: permissive Forbidden grep
  echo "$output" | grep -qE 'Forbidden|forbidden|cannot create resource'
  # Q6 RESEARCH verbatim: the User string proves the SA identity
  echo "$output" | grep -qF 'human-tenant-owner'
  # Idempotent cleanup
  kubectl --kubeconfig="$ALPHA_KUBECONFIG" delete secret demo-deny -n tenant-alpha \
    --ignore-not-found --wait=false >/dev/null 2>&1 || true
}
```

(Mirror @test for `BRAVO_KUBECONFIG` / `tenant-bravo`.)

---

### `tests/bats/demo-05-live-cross-tenant-forbidden.bats` (test, live-RBAC)

**Analog:** `tests/bats/negative-rbac-01-cross-tenant-list.bats` lines 52-72 (exact — N1/N2/N3 already covers alpha→bravo direction; demo-05 extends to bravo→alpha symmetric mirror).

**Cross-tenant Forbidden pattern** (verbatim from negative-rbac-01 N1 lines 52-56):
```bash
@test "DEMO-05 (alpha→bravo): cross-tenant pod LIST denied" {
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" get pods -n tenant-bravo
  [ "$status" -ne 0 ]
  echo "$output" | grep -qE "(Forbidden|forbidden|cannot list)"
}

@test "DEMO-05 (bravo→alpha): cross-tenant pod LIST denied (symmetric mirror)" {
  run kubectl --kubeconfig="$BRAVO_KUBECONFIG" get pods -n tenant-alpha
  [ "$status" -ne 0 ]
  echo "$output" | grep -qE "(Forbidden|forbidden|cannot list)"
}
```

(Note: kubeconfigs are minted via `human-tenant-owner`, NOT `gitops-reconciler` — D-14-08 + RBAC-02; tenant-owner is the human-exercised SA. The Phase 11 fixture used `gitops-reconciler` because it predates the human-tenant-owner SA. For demo-05, swap the SA in setup_file.)

---

### `tests/bats/demo-06-live-platform-owner-cluster-admin-denials.bats` (test, live-RBAC)

**Analog:** `tests/bats/rbac-08-live-platform-owner-grant-matrix.bats` lines 63-94 (auth can-i ceiling matrix) + Q6 RESEARCH verbatim CRB Forbidden string.

**Use platform-owner-only setup_file from demo-01.**

**Three-action denial matrix — real-CRUD probes (Pitfall P37: NOT auth can-i; D-11-05):**
```bash
@test "DEMO-06 (Tier-2 ceiling): platform-owner cannot create ClusterRoleBinding (headline)" {
  run kubectl --kubeconfig="$PO_KUBECONFIG" create clusterrolebinding po-cluster-admin-attempt \
    --clusterrole=cluster-admin --user=platform-owner
  [ "$status" -ne 0 ]
  # Q6 RESEARCH verbatim Forbidden string
  echo "$output" | grep -qF "clusterrolebindings.rbac.authorization.k8s.io is forbidden"
  echo "$output" | grep -qF "system:serviceaccount:capsule-system:platform-owner"
}

@test "DEMO-06 (Tier-2 ceiling): platform-owner cannot read nodes -o yaml" {
  run kubectl --kubeconfig="$PO_KUBECONFIG" get nodes -o yaml
  [ "$status" -ne 0 ]
  echo "$output" | grep -qE 'Forbidden|forbidden'
}

@test "DEMO-06 (Tier-2 ceiling): platform-owner cannot list certificatesigningrequests" {
  run kubectl --kubeconfig="$PO_KUBECONFIG" get certificatesigningrequests
  [ "$status" -ne 0 ]
  echo "$output" | grep -qE 'Forbidden|forbidden'
}
```

---

### `tests/bats/runbook-01-static-acts.bats` (test, static-grep)

**Analog:** `tests/bats/docs-05-runbook.bats` (DOCS-05 strict-ordered step-marker grep).

**Frontmatter + h1 + ordered-section assertion** (verbatim cadence from docs-05 lines 14-37):
```bash
load 'test_helper'

setup() {
  DOC="${REPO_ROOT}/docs/poc-capsule-demo.md"
}

@test "RUNBOOK-01: docs/poc-capsule-demo.md exists and starts with an h1" {
  [ -f "$DOC" ]
  run bash -c "head -20 '$DOC' | grep -E '^# '"
  [ "$status" -eq 0 ]
}

@test "RUNBOOK-01 / D-14-04: doc carries 'status: Active' frontmatter" {
  [ -f "$DOC" ]
  run grep -iE '^status:[[:space:]]*Active' "$DOC"
  [ "$status" -eq 0 ]
}

@test "RUNBOOK-01 / D-14-04: doc lists 6 acts in strict order" {
  [ -f "$DOC" ]
  previous=0
  for literal in \
    '## Act 1 — ' \
    '## Act 2 — ' \
    '## Act 3 — ' \
    '## Act 4 — ' \
    '## Act 5 — ' \
    '## Act 6 — '
  do
    line="$(grep -nF -- "$literal" "$DOC" | head -1 | cut -d: -f1)"
    [ -n "$line" ]
    [ "$line" -gt "$previous" ]
    previous="$line"
  done
}

@test "RUNBOOK-01 / D-14-06: every act has an 'Expected output' subsection" {
  [ -f "$DOC" ]
  count="$(grep -cE '^### Expected output' "$DOC")"
  [ "$count" -ge 6 ]
}
```

---

### `tests/bats/runbook-02-static-checklist.bats` (test, static-grep)

**Analog:** `tests/bats/seed-01-static-globaltenantresource.bats` lines 20-56 (file-exists + grep -F literal idiom).

**Pre-demo checklist literal-presence pattern** (D-14-05 executable, not narrative):
```bash
load 'test_helper'

setup() {
  DOC="${REPO_ROOT}/docs/poc-capsule-demo.md"
}

@test "RUNBOOK-02 / D-14-05: pre-demo checklist section exists" {
  [ -f "$DOC" ]
  run grep -iE '^## Pre-demo checklist' "$DOC"
  [ "$status" -eq 0 ]
}

@test "RUNBOOK-02 / D-14-05: checklist references task fix-dns-poc-capsule" {
  [ -f "$DOC" ]
  run grep -F -- 'task fix-dns-poc-capsule' "$DOC"
  [ "$status" -eq 0 ]
}

@test "RUNBOOK-02 / D-14-05: checklist mints platform-owner kubeconfig" {
  [ -f "$DOC" ]
  run grep -F -- 'issue-platform-owner-kubeconfig.sh' "$DOC"
  [ "$status" -eq 0 ]
}

@test "RUNBOOK-02 / D-14-05: checklist mints tenant-owner kubeconfigs (alpha + bravo)" {
  [ -f "$DOC" ]
  for literal in \
    'issue-tenant-kubeconfig.sh alpha human-tenant-owner' \
    'issue-tenant-kubeconfig.sh bravo human-tenant-owner'
  do
    run grep -F -- "$literal" "$DOC"
    [ "$status" -eq 0 ]
  done
}

@test "RUNBOOK-02 / D-14-03 idempotency: checklist resets charlie tenant" {
  [ -f "$DOC" ]
  run grep -F -- 'delete tenant charlie --ignore-not-found' "$DOC"
  [ "$status" -eq 0 ]
}
```

---

### `tests/bats/runbook-03-static-tls-noise.bats` (test, static-grep)

**Analog:** `tests/bats/seed-01-static-globaltenantresource.bats` (file-exists + literal-grep) + Q2 RESEARCH verbatim TLS log line.

**TLS-noise appendix shape contract** (D-14-01 document-only):
```bash
load 'test_helper'

setup() {
  DOC="${REPO_ROOT}/docs/poc-capsule-demo.md"
}

@test "RUNBOOK-03 / D-14-01: doc contains verbatim 'tls: bad certificate' string" {
  [ -f "$DOC" ]
  run grep -F -- 'tls: bad certificate' "$DOC"
  [ "$status" -eq 0 ]
}

@test "RUNBOOK-03 / D-14-01: TLS noise section cross-links ADR-008" {
  [ -f "$DOC" ]
  run grep -iE '(adr/0008|ADR-008)' "$DOC"
  [ "$status" -eq 0 ]
}

@test "RUNBOOK-03 / D-14-01: 'Known noise' appendix appears AFTER Act 6 (not inline)" {
  [ -f "$DOC" ]
  act6_line="$(grep -nE '^## Act 6 —' "$DOC" | head -1 | cut -d: -f1)"
  noise_line="$(grep -nE '^## Known noise' "$DOC" | head -1 | cut -d: -f1)"
  [ -n "$act6_line" ]
  [ -n "$noise_line" ]
  [ "$noise_line" -gt "$act6_line" ]
}

@test "RUNBOOK-03 / D-14-01: noise section labels chatter as 1Hz / capsule-controller-manager" {
  [ -f "$DOC" ]
  run grep -iF -- 'capsule-controller-manager' "$DOC"
  [ "$status" -eq 0 ]
}
```

---

### `tests/bats/runbook-03-static-eks-three-tier.bats` (test, static-grep)

**Analog:** `tests/bats/docs-06-eks.bats` (EKSDOC-01 multi-literal grep loop lines 33-39 + 41-53).

**Three-tier-on-EKS append contract** (Q1 RESEARCH + A1 assumption):
```bash
load 'test_helper'

setup() {
  DOC="${REPO_ROOT}/docs/capsule-on-eks.md"
}

@test "RUNBOOK-03 / Q1: docs/capsule-on-eks.md exists" {
  [ -f "$DOC" ]
}

@test "RUNBOOK-03 / Q1: doc contains 'Three-tier permission model on EKS' section" {
  [ -f "$DOC" ]
  run grep -iE '^## Three-tier permission model' "$DOC"
  [ "$status" -eq 0 ]
}

@test "RUNBOOK-03 / Q1: doc labels Tier 1 / Tier 2 / Tier 3 explicitly" {
  [ -f "$DOC" ]
  for literal in 'Tier 1' 'Tier 2' 'Tier 3'; do
    run grep -F -- "$literal" "$DOC"
    [ "$status" -eq 0 ]
  done
}

@test "RUNBOOK-03 / Q1: doc maps tiers to IRSA + tenant-workload-editor + capsule-platform-owner" {
  [ -f "$DOC" ]
  for literal in 'IRSA' 'tenant-workload-editor' 'capsule-platform-owner'; do
    run grep -F -- "$literal" "$DOC"
    [ "$status" -eq 0 ]
  done
}
```

---

### `tests/bats/runbook-05-static-charlie.bats` (test, static-grep)

**Analog:** `tests/bats/rbac-01-static-tenant-workload-editor.bats` lines 180-186 (`grep -v '^[[:space:]]*#'` comment filter to avoid bats's own comments triggering self-validation).

**Charlie verbatim presence in acts 3 + 6** (D-14-02):
```bash
load 'test_helper'

setup() {
  DOC="${REPO_ROOT}/docs/poc-capsule-demo.md"
}

@test "RUNBOOK-05 / D-14-02: charlie referenced in Act 3 (live provisioning)" {
  [ -f "$DOC" ]
  # Locate Act 3 boundary; assert 'charlie' appears between Act 3 and Act 4
  act3_line="$(grep -nE '^## Act 3 —' "$DOC" | head -1 | cut -d: -f1)"
  act4_line="$(grep -nE '^## Act 4 —' "$DOC" | head -1 | cut -d: -f1)"
  [ -n "$act3_line" ] && [ -n "$act4_line" ]
  run bash -c "sed -n \"${act3_line},${act4_line}p\" '$DOC' | grep -F 'charlie'"
  [ "$status" -eq 0 ]
}

@test "RUNBOOK-05 / D-14-02: charlie referenced in Act 6 (cleanup)" {
  [ -f "$DOC" ]
  act6_line="$(grep -nE '^## Act 6 —' "$DOC" | head -1 | cut -d: -f1)"
  [ -n "$act6_line" ]
  run bash -c "tail -n +${act6_line} '$DOC' | grep -F 'charlie'"
  [ "$status" -eq 0 ]
}

@test "RUNBOOK-05 / D-14-03: Act 3 invokes 'new-tenant.sh charlie' live" {
  [ -f "$DOC" ]
  run grep -F -- 'new-tenant.sh charlie' "$DOC"
  [ "$status" -eq 0 ]
}

@test "RUNBOOK-05 / D-14-02: Act 4 watches tenant-charlie namespace for SEED-02 propagation" {
  [ -f "$DOC" ]
  run grep -F -- 'tenant-charlie' "$DOC"
  [ "$status" -eq 0 ]
}
```

---

### `docs/poc-capsule-demo.md` (NEW doc — composite)

**Analog 1:** `docs/poc-capsule.md` lines 1-13 (frontmatter + h1 + status blockquote + companion-docs cross-link).
**Analog 2:** `docs/rebuild-runbook.md` lines 45-88 (`## Step N — Title (~Nsec)` cadence + executable bash block + narrative paragraph).
**Analog 3:** `docs/poc-capsule.md` lines 29-67 (Quickstart / What to expect / How to verify three-block-per-section cadence with fenced `text` expected-output block).

**Frontmatter** (verbatim cadence from `docs/poc-capsule.md` lines 1-6):
```yaml
---
status: Active
audience: demo presenter + audience
purpose: 6-act Capsule POC demo walkthrough — three-tier permission model end-to-end.
scope: Phase 14 verification + demo runbook. Single canonical document; companion to docs/poc-capsule.md (operator runbook) and docs/capsule-on-eks.md (EKS translation).
---
```

**H1 + status blockquote + companion-docs** (verbatim cadence from `docs/poc-capsule.md` lines 8-11):
```markdown
# spoke-capsule POC Demo Walkthrough

> **Status:** Active (Phase 14 — Two-Perspective Demo Verification).
> **Companion docs:** [`docs/poc-capsule.md`](poc-capsule.md) (operator runbook — host-restart recovery + kubeconfig delivery contracts), [`docs/capsule-on-eks.md`](capsule-on-eks.md) (EKS translation rough-cut), [`docs/adr/0008-capsule-multi-tenancy-graduation.md`](adr/0008-capsule-multi-tenancy-graduation.md) (POC graduation = DEFER framing).
```

**Per-act section pattern** (composite — `rebuild-runbook.md` line 45-58 + `poc-capsule.md` line 29-58 + RESEARCH Pattern 1):
```markdown
## Act 2 — Platform-owner role + ceiling demo

The Karyon Platform Team (Tier 2) sees every tenant but is NOT cluster-admin.
Tenant CR LIST proves the visibility. Attempting to create a ClusterRoleBinding
proves the ceiling.

```bash
# Tenant CR LIST (platform-owner)
kubectl --kubeconfig=$PO_KC get tenants

# Forbidden: ClusterRoleBinding create (Tier-2 ceiling)
kubectl --kubeconfig=$PO_KC create clusterrolebinding po-cluster-admin-attempt \
  --clusterrole=cluster-admin --user=platform-owner
```

### Expected output

```text
NAME    STATE    NAMESPACE QUOTA   NAMESPACE COUNT   ...   READY   STATUS       AGE
alpha   Active   3                 2                       True    reconciled   12d
bravo   Active   3                 2                       True    reconciled   12d

error: failed to create clusterrolebinding: clusterrolebindings.rbac.authorization.k8s.io is forbidden: User "system:serviceaccount:capsule-system:platform-owner" cannot create resource "clusterrolebindings" in API group "rbac.authorization.k8s.io" at the cluster scope
```
```

**Appendix pattern — Known noise** (D-14-01; 2-paragraph; uses Q2 RESEARCH verbatim TLS log line):
```markdown
## Known noise — `tls: bad certificate` chatter

**What it is.** The capsule-controller-manager pod emits a `tls: bad certificate` log line ~1Hz throughout normal operation, visible via:

```bash
kubectl --context k3d-spoke-capsule -n capsule-system logs deploy/capsule-controller-manager --tail=30 | grep tls
```

Example:

```text
2026/05/19 23:50:49 http: TLS handshake error from 10.42.0.1:39986: remote error: tls: bad certificate
```

This is the apiserver's webhook-handshake retry loop against capsule-controller-manager using a self-signed cert it doesn't trust. It does NOT affect tenant boundary enforcement or `GlobalTenantResource` propagation (verified empirically via Phase 13 + this phase's DEMO-01..06 bats).

**Why document-only.** Per [ADR-008](adr/0008-capsule-multi-tenancy-graduation.md) the Capsule POC is `DEFER` for production graduation; the chatter is cosmetic, not functional. Fixing it pulls in cert-manager / CA-distribution work that the lean v0.20 milestone is explicitly scope-guarded against. A production EKS cut would wire AWS Certificate Manager or cert-manager controller-managed certs cleanly; see `docs/capsule-on-eks.md` §"Phase 11 Evidence — Cert source".
```

---

### `docs/capsule-on-eks.md` (MODIFY — append ~15 lines)

**Analog:** Same file's existing structure (lines 34-43 "Required permissions / RBAC" 3-row table; lines 217-225 "What this POC does NOT prove" 3-item ordered list).

**Self-analog section shape to mirror** (capsule-on-eks.md lines 34-43):
```markdown
## Required permissions / RBAC

| Subject | Permissions | Where it lives |
|---|---|---|
| **Capsule operator SA** (`capsule-controller-manager`) | `cluster-admin` (operator manages all tenant resources cluster-wide) | `capsule-system` namespace |
| **capsule-proxy SA** | Read tenants + impersonate tenant owners | `capsule-system` namespace |
| **Per-tenant SA** (`gitops-reconciler` in tenant namespace) | Bound to `Tenant.spec.owners`; Capsule scopes their effective permissions to tenant namespaces | Each tenant's namespace prefix |
```

**Append pattern — new section to add** (Q1 RESEARCH; placement: after existing "## Required permissions / RBAC" table, before "## Topology (EKS target)"):
```markdown
## Three-tier permission model on EKS

The Phase 13 three-tier model translates to EKS as follows. Each tier preserves the same RBAC shape as the k3d POC; the platform-specific carriers change.

| Tier | k3d POC carrier | EKS carrier | Permission ceiling |
|---|---|---|---|
| **Tier 1 — Cloud Ops** | k3d host operator (full cluster control) | AWS account / IAM admin holding `cluster-admin` on the EKS cluster | `cluster-admin` (nodes, csr, clusterrolebindings) |
| **Tier 2 — Karyon Platform Team** | `capsule-platform-owners` group + `platform-owner@capsule-system` SA | EKS IRSA-bound IAM role + cluster-scoped `capsule-platform-owner` ClusterRole | Tenant CR CRUD + namespace LIST; NO cluster-admin, NO nodes, NO csr, NO clusterrolebinding writes |
| **Tier 3 — Tenant Developers** | `human-tenant-owner@tenant-<name>` SA + Tenant `spec.owners[]` co-ownership | IRSA-bound IAM role per tenant SA (existing pattern above) | `tenant-workload-editor` ClusterRole scoped to own tenant namespaces |

The IRSA TrustPolicy YAML (Tier 3 carrier) appears verbatim below in §"Verbatim YAML #1". Tier 2's IRSA shape is identical except the role's namespace-scope is cluster-wide and the bound ClusterRole is `capsule-platform-owner` (NOT `tenant-workload-editor`).
```

---

### `.planning/phases/14-…/14-VALIDATION.md` (NEW)

**Analog:** `.planning/phases/13-rbac-narrowing-globaltenantresource-seed-delivery-mechanism/13-VALIDATION.md` (per D-14-10 explicit pattern-mirror directive).

Use the Phase 13 VALIDATION.md structure verbatim: frontmatter + per-task verification map + UAT stopwatch record (RUNBOOK-04 specific). Planner consults the Phase 13 file at write-time.

---

## Shared Patterns

### Shared: Live-bats Forbidden assertion (permissive grep)

**Source:** `tests/bats/rbac-06-live-tenant-kubeconfig.bats` line 49 (the **canonical** permissive grep — Pitfall 11-P3).
**Apply to:** All `demo-0{4,5,6}-live-*.bats` Forbidden assertions.

```bash
# Pitfall 11-P3 lesson: variants of Forbidden text across kubectl versions
echo "$output" | grep -qE 'Forbidden|forbidden|cannot create resource|cannot list'
```

For DEMO-04 / DEMO-06 specifically, add the verbatim User-identity sub-grep per Q6 RESEARCH:
```bash
echo "$output" | grep -qF "system:serviceaccount:capsule-system:platform-owner"   # DEMO-06
echo "$output" | grep -qF "system:serviceaccount:tenant-alpha:human-tenant-owner" # DEMO-04 alpha
```

### Shared: Per-suite TMPDIR for kubeconfig mint (P29 leak defense)

**Source:** `tests/bats/rbac-08-live-platform-owner-grant-matrix.bats` lines 16-20 (Phase 7 P29 + Phase 10 BL-02 hardening contract).
**Apply to:** Every `demo-*-live-*.bats` file.

```bash
export KARYON_BATS_TMPDIR="${TMPDIR:-/tmp}/karyon-tenants/bats-${BATS_RUN_TMPDIR##*/}"
mkdir -p "$KARYON_BATS_TMPDIR"
# ...mint kubeconfigs into $KARYON_BATS_TMPDIR/...
teardown_file() {
  rm -rf "$KARYON_BATS_TMPDIR"
}
```

**Why this exact path:** `issue-*-kubeconfig.sh --write-to` rejects paths outside `${TMPDIR:-/tmp}/karyon-tenants/` (BL-01 + BL-02 symlink defenses). The `bats-${BATS_RUN_TMPDIR##*/}` suffix isolates parallel suites.

### Shared: Cluster-info skip gate (in BOTH setup_file AND setup)

**Source:** `tests/bats/rbac-08-live-platform-owner-grant-matrix.bats` lines 13-14 + 28-30.
**Apply to:** Every `demo-*-live-*.bats` file.

```bash
if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
  skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
fi
```

Place this check in **both** `setup_file()` (mint gate) AND `setup()` (per-@test gate). The `setup_file` skip protects against mint failures cascading; the `setup` skip protects against mid-suite cluster loss.

### Shared: Comment-filtered grep for self-validation defense

**Source:** `tests/bats/rbac-01-static-tenant-workload-editor.bats` lines 180-186.
**Apply to:** Any static-grep bats whose own comments contain literal strings that would otherwise match the doc-grep assertion (e.g., `runbook-05-static-charlie.bats` if its comments mention `charlie` they'd falsely-pass the test against an empty doc).

```bash
# Filter comments first so this bats's own comments are not counted.
run bash -c "grep -v '^[[:space:]]*#' '$F' | grep -F 'literal'"
```

### Shared: bats header comment block (D-13-15 Nyquist-gate convention)

**Source:** `tests/bats/rbac-08-live-platform-owner-grant-matrix.bats` lines 1-9 (and every Phase 13 bats file).
**Apply to:** Every new `demo-*` and `runbook-*` bats file.

```bash
#!/usr/bin/env bats
# tests/bats/<filename>.bats
# Phase 14 / Wave 0 (D-14-08 + D-13-15 Nyquist gate)
# <REQ-ID> — <one-line behavior>.
# RED until <Plan N-NN> lands <what>.

load 'test_helper'
```

The `RED until …` line is load-bearing — it signals the Nyquist failing-first contract to the verifier.

### Shared: Markdown frontmatter convention

**Source:** `docs/poc-capsule.md` lines 1-6.
**Apply to:** `docs/poc-capsule-demo.md`.

```yaml
---
status: Active
audience: <e.g., demo presenter + audience>
purpose: <one-sentence purpose>
scope: <which phase shipped what; cross-link companion docs>
---
```

(Note: `docs/capsule-on-eks.md` uses capital-S `Status:` while `docs/poc-capsule.md` uses lowercase `status:` — both are accepted by `tests/bats/docs-06-eks.bats` line 23's case-insensitive grep. Pick lowercase for new docs to match the more recent convention.)

### Shared: Section-then-fenced-text expected-output pattern

**Source:** `docs/poc-capsule.md` lines 42-55 (`### What to expect` followed by ```` ```text ```` fenced block).
**Apply to:** Every `## Act N` section in `docs/poc-capsule-demo.md` (D-14-06: each act ends with a `### Expected output` block).

```markdown
### Expected output

```text
<verbatim canonical output from Q3/Q4/Q5/Q6 RESEARCH live-capture>
```
```

**Critical:** Never invent expected-output strings (RESEARCH anti-pattern: "Inventing expected-output strings"). All canonical outputs are in `14-RESEARCH.md` Q2-Q6.

### Shared: Ordered-section + section-anchor cross-link pattern

**Source:** `docs/poc-capsule.md` lines 184-189 ("### Cross-references" — bulleted markdown links with section anchors `§"..."`).
**Apply to:** `docs/poc-capsule-demo.md` final "Forward pointers" section.

```markdown
## Forward pointers

- [`docs/poc-capsule.md`](poc-capsule.md) §"Host restart recovery" — operator-side fix-dns + cluster-stop/start recovery procedures.
- [`docs/capsule-on-eks.md`](capsule-on-eks.md) §"Three-tier permission model on EKS" — production translation of the three-tier carriers (Cloud Ops / Karyon Platform Team / Tenant Developers).
- [`docs/adr/0008-capsule-multi-tenancy-graduation.md`](adr/0008-capsule-multi-tenancy-graduation.md) — POC graduation = DEFER framing (cited in "Known noise" appendix).
```

---

## No Analog Found

None. Every Phase 14 file has a direct, recent (Phase 7+10+11+13) analog in the codebase. This is consistent with the phase being **pure verification + documentation** — no novel patterns are introduced; everything builds on inherited primitives.

---

## Metadata

**Analog search scope:**
- `tests/bats/` (78 files — focused on `rbac-*`, `seed-*`, `negative-rbac-*`, `docs-*` subsets)
- `docs/` (10+ files — focused on `poc-capsule.md`, `rebuild-runbook.md`, `capsule-on-eks.md`)
- `.planning/phases/13-…/` (sibling phase patterns — VALIDATION.md, CONTEXT.md inheritance)

**Files scanned (read in full or relevant ranges):** 11
- `tests/bats/rbac-08-live-platform-owner-grant-matrix.bats` (full)
- `tests/bats/rbac-05-live-tenant-owner-grant-matrix.bats` (full)
- `tests/bats/rbac-06-live-tenant-kubeconfig.bats` (full)
- `tests/bats/negative-rbac-01-cross-tenant-list.bats` (full)
- `tests/bats/seed-03-live-fresh-tenant.bats` (full)
- `tests/bats/seed-02-live-existing-tenants.bats` (head)
- `tests/bats/seed-01-static-globaltenantresource.bats` (full)
- `tests/bats/rbac-01-static-tenant-workload-editor.bats` (full)
- `tests/bats/docs-05-runbook.bats` (full)
- `tests/bats/docs-06-eks.bats` (full)
- `tests/bats/test_helper.bash` (full)
- `docs/poc-capsule.md` (head + relevant ranges)
- `docs/rebuild-runbook.md` (head + headings)
- `docs/capsule-on-eks.md` (head + relevant ranges + headings)

**Pattern extraction date:** 2026-05-19

---

## PATTERN MAPPING COMPLETE

**Phase:** 14 — Two-Perspective Demo Verification + 6-Act Runbook + TLS-Noise Resolution
**Files classified:** 14 (13 new + 1 modified)
**Analogs found:** 14 / 14

### Coverage
- Files with exact analog: 13 (every bats file + frontmatter/section pattern for the runbook + self-analog for capsule-on-eks.md append)
- Files with role-match analog: 1 (`demo-03-live-pod-ops.bats` — exec/logs probe shape is a role-match of rbac-06 + seed-02 composite; no single existing bats exercises both kubectl exec + kubectl logs against the same pod)
- Files with no analog: 0

### Key Patterns Identified
- **bats live-RBAC fixture pattern is canonical and uniform:** every Phase 13+ live bats uses `${TMPDIR}/karyon-tenants/bats-${BATS_RUN_TMPDIR##*/}` per-suite mint dir, `issue-{platform-owner,tenant}-kubeconfig.sh --duration=2h --write-to ...`, double-skip-gate (setup_file + setup), and the `load 'test_helper'` + `REPO_ROOT` resolution. The new demo-*-live-*.bats files copy this verbatim.
- **Forbidden-assertion idiom is permissive-grep + verbatim-User-string:** `grep -qE 'Forbidden|forbidden|cannot ...'` (Pitfall 11-P3) plus `grep -qF "system:serviceaccount:..."` (Q6 RESEARCH verbatim) — the User string is the load-bearing identity proof.
- **Static-grep bats use `grep -F` for literal markers + `grep -v '^[[:space:]]*#'` comment filter** to prevent self-validation against the bats's own comment block.
- **Doc frontmatter + h1 + status-blockquote + companion-docs cadence** is uniform across `docs/poc-capsule.md` / `docs/capsule-on-eks.md` / `docs/rebuild-runbook.md` — new `docs/poc-capsule-demo.md` inherits verbatim.
- **`### Expected output` ```text ``` block after every `## Act N` section** is the load-bearing UAT contract; verbatim canonical strings come from RESEARCH.md Q2-Q6 live-captures (never invented).

### File Created
`/home/rich/code/gsd/karyon/.planning/phases/14-two-perspective-demo-verification-6-act-runbook-tls-noise-re/14-PATTERNS.md`

### Ready for Planning
Pattern mapping complete. Planner can now reference analog patterns + concrete code excerpts directly in `14-{00..03}-PLAN.md` files. Every Phase 14 new artifact has a verbatim-copyable precedent — the executor's job is wiring + naming, not novel pattern invention.
