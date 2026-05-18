# Phase 11: Validation + Graduation ADR-008 - Pattern Map

**Mapped:** 2026-05-05
**Files analyzed:** 23 (2 NEW scripts; 11 NEW bats; 1 NEW ADR; 6 EDITED files; 2 OPTIONAL Tenant CR fixture extensions; 1 OPTIONAL doc append)
**Analogs found:** 23 / 23

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `scripts/poc/capsule/destroy-poc.sh` (NEW) | poc-script (orchestration wrapper) | request-response (kubectl/flux/k3d CLIs → exit code) | `scripts/poc/capsule/fix-dns.sh` | exact (same role, same data flow, same dir) |
| `scripts/poc/capsule/fail-capsule-webhook.sh` (NEW) | poc-script (one-shot CLI wrapper) | request-response (kubectl scale + rollout-status → exit code) | `scripts/poc/capsule/fix-dns.sh` | exact |
| `tests/bats/negative-rbac-01-cross-tenant-list.bats` (NEW) | test (live; setup_file mint-once) | live-bats; calls `kubectl --kubeconfig=…` against capsule-proxy | `tests/bats/proxy-05-live-list-filter.bats` | exact (same probe shape, same kubeconfig source) |
| `tests/bats/negative-rbac-02-escalation.bats` (NEW) | test (live; setup_file mint-once) | live-bats; cluster-scoped CRB create → Forbidden | `tests/bats/proxy-05-live-list-filter.bats` | exact |
| `tests/bats/negative-rbac-03-webhook-policy.bats` (NEW) | test (live; setup_file mint-once) | live-bats; namespace/registry/quota create → Capsule webhook reject | `tests/bats/tenants-07-live-impersonate.bats` (impersonation analog) + `tests/bats/proxy-05-live-list-filter.bats` (kubeconfig analog) | exact |
| `tests/bats/negative-rbac-04-bypass-and-flux.bats` (NEW) | test (live; setup_file mint-once + per-test direct-kubeconfig setup) | live-bats; direct-apiserver bypass + Flux sourceRef cross-namespace | `tests/bats/proxy-05-live-list-filter.bats` (direct-kubeconfig pattern verbatim) | exact |
| `tests/bats/negative-rbac-05-webhook-down.bats` (NEW) | test (live; setup_file ensures controller Ready=1 at start) | live-bats; calls `task fail-capsule-webhook -- 0/1` then probes | `tests/bats/proxy-05-live-list-filter.bats` (kubeconfig analog) + `tests/bats/tenants-08-live-quota-limit.bats` (poll-with-retry analog) | exact |
| `tests/bats/negative-rbac-anti-pattern-lint-static.bats` (NEW) | test (static lint) | grep-asserts ZERO `kubectl auth can-i` in source files | `tests/bats/poc-isolation-01-static.bats` (anti-pattern grep-loop analog) | exact |
| `tests/bats/push-gate-01-static-rbac-postbuild.bats` (NEW) | test (static yaml shape) | grep/yq-asserts spec.patches literal in `clusters/hub-flux/pocs/capsule.yaml` | `tests/bats/capsule-install-01-static-helmrelease.bats` (yq shape contract) + `tests/bats/poc-mount-01-static.bats` (outer-K shape contract) | exact |
| `tests/bats/push-gate-02-static-capsuleconfig.bats` (NEW) | test (static yaml shape) | yq-asserts 3-group userGroups in `pocs/capsule/spoke/config/capsuleconfig.yaml` | `tests/bats/tenants-01-static-tenant-cr.bats` (yq shape contract) | exact |
| `tests/bats/push-gate-03-static-tenant-ns-label.bats` (NEW) | test (static yaml shape) | yq-asserts metadata.labels in tenant namespace.yaml files | `tests/bats/tenants-01-static-tenant-cr.bats` | exact |
| `tests/bats/push-gate-04-live-tenant-ns-flux-apply.bats` (NEW) | test (live; cluster-info gate) | kubectl jsonpath query for label on live namespace | `tests/bats/tenants-07-live-impersonate.bats` (label-poll-with-retry analog) | exact |
| `tests/bats/push-gate-05-static-gitleaks-allowlist.bats` (NEW) | test (static config + live gitleaks scan) | grep-asserts allowlist literal + invokes gitleaks | `tests/bats/repo-hygiene-04-poc.bats` (gitleaks scan analog) + `tests/bats/proxy-02-static-leak-defenses.bats` (allowlist literal grep analog) | exact |
| `tests/bats/teardown-01-static-script.bats` (NEW) | test (static script-shape lint) | grep-asserts shebang/strict-mode/REPO_ROOT/preflight-lib/head-comment literals | `tests/bats/proxy-01-static-script.bats` (script-shape lint verbatim) | exact |
| `tests/bats/teardown-02-static-sentinel-preservation.bats` (NEW) | test (static anti-pattern lint) | grep-asserts script does NOT mutate `clusters/hub-flux/flux-system/kustomization.yaml` | `tests/bats/proxy-01-static-script.bats` (anti-pattern grep-NOT analog) + `tests/bats/poc-mount-01-static.bats` (sentinel-preservation analog) | exact |
| `tests/bats/teardown-03-live-ordered.bats` (NEW) | test (live; cluster-info gate; destructive) | runs `task destroy-poc -- capsule`; asserts post-state | `tests/bats/proxy-04-live-issue.bats` (live-skip analog) + `tests/bats/tenants-08-live-quota-limit.bats` (post-state assertion analog) | exact |
| `tests/bats/teardown-04-live-pvc-strand-mitigation.bats` (NEW) | test (live; cluster-info gate; destructive) | seeds PVC; runs destroy; polls finalizer cleared | `tests/bats/proxy-04-live-issue.bats` + `tests/bats/tenants-08-live-quota-limit.bats` (poll analog) | exact |
| `tests/bats/slo-regression-live.bats` (NEW; ~4 @tests) | test (live; cluster-info gate; ~5 min runtime) | wraps `task rebuild` with `date +%s` differential + docker inspect CID compare | `tests/bats/destroy-rebuild-01-static.bats` (DESTROY-06 elapsed-seconds analog) + `tests/bats/poc-isolation-01-static.bats` (verbatim @test inheritance) | role-match (no exact analog wraps `task rebuild`; closest is rebuild static contract) |
| `docs/adr/0008-capsule-multi-tenancy-graduation.md` (NEW) | doc (ADR; Nygard 4-section + 3 sub-sections) | markdown artifact | `docs/adr/0004-hub-only-flux-control-plane.md` (most structurally similar — long Decision section, Easier/Harder/No-change Consequences) | exact |
| `clusters/hub-flux/pocs/capsule.yaml` (EDIT — D-11-01 ADD spec.patches) | infra config (Flux Kustomization v1) | yaml inline edit; PostBuild patch JSON6902 op:add | `clusters/hub-flux/flux-system/kustomization.yaml` (existing patches block; same JSON6902 shape) | exact |
| `pocs/capsule/spoke/config/capsuleconfig.yaml` (EDIT — D-11-02) | infra config (Capsule v1beta2 CapsuleConfiguration CR) | yaml inline edit; spec.userGroups list update | (self — file already exists with 1-group userGroups; edit replaces with 3-group) | self-edit |
| `pocs/capsule/spoke/tenants/{alpha,bravo}/namespace.yaml` (EDIT — D-11-03 ADD label) | infra config (Namespace CR) | yaml inline edit; metadata.labels addition | (self — file is currently 11 lines, no labels block) | self-edit |
| `pocs/capsule/spoke/tenants/{alpha,bravo}/tenant.yaml` (EDIT — Claude's discretion N6/N7) | infra config (Capsule v1beta2 Tenant CR) | yaml inline edit; spec.namespaceOptions.quota + spec.containerRegistries | (self — file already has resourceQuotas + limitRanges; edit adds 2 sibling fields) | self-edit |
| `.gitleaks.toml` (EDIT — D-11-04 APPEND path-allowlist) | repo config (TOML) | toml inline edit; append to `[allowlist] paths` | (self — file already has `^\.env\.example$` precedent at line 13) | self-edit |
| `Taskfile.yml` (EDIT — D-11-12 ADD 2 entries) | repo config (YAML) | yaml inline append; 2 top-level task entries | (self — file already has `fix-dns-poc-capsule:` POC sibling at line 44) | self-edit |
| `docs/capsule-on-eks.md` (EDIT — D-11-15 ROLLFORWARD) | doc (rough-cut design) | markdown frontmatter Status flip + 4 targeted revision blocks | (self — frontmatter already has `status-rollover` policy line declaring this rollforward) | self-edit |
| `docs/poc-capsule.md` (OPTIONAL EDIT — Plan 11-02 discretion) | doc (operator runbook) | markdown append H2 "Ordered teardown procedure" | (self — frontmatter already declares "Phase 11 will add ordered teardown procedure") | self-edit |

## Pattern Assignments

### `scripts/poc/capsule/destroy-poc.sh` (NEW; poc-script, request-response)

**Analog:** `scripts/poc/capsule/fix-dns.sh`

**Imports / preamble pattern** (fix-dns.sh lines 1-23 — copy verbatim, swap head comment):
```bash
#!/usr/bin/env bash
# scripts/poc/capsule/destroy-poc.sh
#
# Ordered teardown for the spoke-capsule POC: suspend tenant inner Ks + outer-K → delete
# Tenant CRs → poll namespace cascade (auto force-delete PVC finalizers after 60s) →
# suspend operator+config outer Ks → optional --full flag for `k3d cluster delete spoke-capsule`.
#
# Surfaces as `task destroy-poc -- capsule [--full]`. Sentinel preservation: this script
# does NOT mutate clusters/hub-flux/flux-system/kustomization.yaml (the # KARYON POC MOUNT
# sentinel + ../pocs mount line stay verbatim post-teardown regardless of --full).
#
# REQ: VAL-03. Decisions: D-11-10 (5-step canonical), D-11-11 (PVC strand auto force-delete after 60s).
# D-12 / P31: Lives under scripts/poc/capsule/; the v0.18 scripts have ZERO references
#             to this file (tests/bats/poc-isolation-01-static.bats enforces).
# D-17 / ADR-004: NO Flux runs on spoke-capsule -- `flux suspend` targets hub-flux only.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# shellcheck source=../../lib/preflight-lib.sh
# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/lib/preflight-lib.sh"
```

**Tool-gate pattern** (fix-dns.sh lines 28-37 — copy verbatim, extend tool list):
```bash
section "Tool gate"
for cmd in kubectl k3d flux jq; do
  if ! have "$cmd"; then
    fail "required command missing: $cmd.
       Fix: install project tools with asdf, then rerun: bash scripts/poc/capsule/destroy-poc.sh"
    exit 1
  fi
done
pass "required commands present"
```

**Flag-parse pattern** (CONTEXT.md `<specifics>` lines 543-553 — D-11-10 `--full` flag):
```bash
FULL=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    capsule) shift ;;
    --full) FULL=true; shift ;;
    *) fail "destroy-poc: unknown arg '$1' (usage: destroy-poc -- capsule [--full])"; exit 1 ;;
  esac
done
```

**5-step ordered-teardown pattern** (CONTEXT.md D-11-10 + D-11-11 lines 188-216):
```bash
section "Step 1: suspend tenant inner Ks + spoke-targeted outer K"
flux --context=k3d-hub-flux suspend kustomization tenant-alpha tenant-bravo poc-capsule-spoke -n flux-system || true
pass "suspended: tenant-alpha tenant-bravo poc-capsule-spoke"

section "Step 2: delete Tenant CRs (cascade triggers tenant namespace cascade)"
kubectl --context=k3d-spoke-capsule delete tenant alpha bravo --wait=true --ignore-not-found
pass "deleted: Tenant alpha bravo"

section "Step 3: poll namespace cascade (max 90s; auto force-delete PVCs after 60s)"
for i in $(seq 1 90); do
  REMAINING=$(kubectl --context=k3d-spoke-capsule get ns -l capsule.clastix.io/tenant -o name 2>/dev/null | wc -l)
  if [[ "$REMAINING" -eq 0 ]]; then break; fi
  if [[ "$i" -ge 60 ]]; then
    info "namespace cascade stuck at ${i}s; force-clearing PVC finalizers (P36 mitigation)"
    kubectl --context=k3d-spoke-capsule get pvc -A -l capsule.clastix.io/tenant -o json \
      | jq -r '.items[] | "\(.metadata.namespace)/\(.metadata.name)"' \
      | xargs -r -I{} kubectl --context=k3d-spoke-capsule patch pvc {} \
          -p '{"metadata":{"finalizers":null}}' --type=merge || true
  fi
  sleep 1
done
pass "namespace cascade complete"

section "Step 4: suspend operator + config outer Ks (preserves GitOps install state)"
flux --context=k3d-hub-flux suspend kustomization poc-capsule poc-capsule-config -n flux-system || true
pass "suspended: poc-capsule poc-capsule-config"

section "Step 5: optional cluster delete (--full flag)"
if [[ "$FULL" == "true" ]]; then
  k3d cluster delete spoke-capsule
  pass "deleted: k3d cluster spoke-capsule"
else
  info "skipping k3d cluster delete (--full not set; cluster + Capsule operator remain alive but tenants gone)"
fi
```

**Summary pattern** (fix-dns.sh lines 70-75 — copy verbatim):
```bash
section "Summary"
printf "  %s%d passed%s, %s%d warnings%s, %s%d failed%s\n" \
  "${C_GREEN}" "${PASS}" "${C_RESET}" "${C_YELLOW}" "${WARN}" "${C_RESET}" "${C_RED}" "${FAIL}" "${C_RESET}"
if (( FAIL > 0 )); then exit 1; fi
printf "\n%sOrdered teardown complete for spoke-capsule POC.%s\n" "${C_GREEN}" "${C_RESET}"
```

**Conventions to replicate:**
- `set -euo pipefail` on line 14 of analog (verbatim).
- `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` + `REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"` (line 16-17 verbatim — three `..` because script is 3 levels deep at `scripts/poc/capsule/`).
- `# shellcheck source=../../lib/preflight-lib.sh` + `# shellcheck disable=SC1091` (lines 18-19 verbatim).
- Numbered `section "..."` headers per logical step (analog uses 4 sections; this script needs 5 + summary).
- `pass`/`fail`/`warn`/`info` calls — stdout output (NOT stderr like issue-tenant-kubeconfig.sh; this script has no kubeconfig payload to protect).
- `|| true` after destructive idempotent calls (`flux suspend`, `kubectl delete`) so re-running on partial state is non-fatal.
- Fail-fast `exit 1` after `fail` calls in tool-gate / flag-parse; data-step failures use `|| true` to continue then summary-fail at end.

---

### `scripts/poc/capsule/fail-capsule-webhook.sh` (NEW; poc-script, request-response)

**Analog:** `scripts/poc/capsule/fix-dns.sh` (head structure) + RESEARCH.md §"Code Examples" lines 631-649 (verbatim shape)

**Imports / preamble pattern** (fix-dns.sh lines 1-23 — copy verbatim, swap head comment):
```bash
#!/usr/bin/env bash
# scripts/poc/capsule/fail-capsule-webhook.sh
#
# Scales capsule-controller-manager Deployment to N replicas (test-only failure simulation).
# `fail-capsule-webhook -- 0` → apiserver returns "no endpoints available" for capsule webhooks
#                               (failurePolicy: Fail blocks tenant pod create; N11 falsifier).
# `fail-capsule-webhook -- 1` → recovery: scale to 1, polls rollout-status to Ready (90s timeout).
#                               (N12 falsifier — apply succeeds again post-recovery).
#
# Surfaces as `task fail-capsule-webhook -- 0|1`. Idempotent — re-running with the same
# replica count is a no-op (kubectl scale is declarative).
#
# REQ: VAL-02. Decision: D-11-09 (scale Deployment 0/1; rollout-status with 90s timeout on recovery).
# D-12 / P31: Lives under scripts/poc/capsule/; the v0.18 scripts have ZERO references
#             to this file (tests/bats/poc-isolation-01-static.bats enforces).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# shellcheck source=../../lib/preflight-lib.sh
# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/lib/preflight-lib.sh"
```

**Argument validation + tool-gate pattern** (RESEARCH.md lines 640-643 + fix-dns.sh tool-gate analog):
```bash
REPLICAS="${1:-0}"
[[ "$REPLICAS" =~ ^[01]$ ]] || { fail "Usage: fail-capsule-webhook.sh [0|1]"; exit 1; }

section "Tool gate"
have kubectl || { fail "kubectl not found.
       Fix: install project tools with asdf, then rerun: bash scripts/poc/capsule/fail-capsule-webhook.sh ${REPLICAS}"; exit 1; }
pass "required commands present"
```

**Scale + rollout-wait pattern** (RESEARCH.md lines 645-649 + CONTEXT.md D-11-09):
```bash
section "Scaling capsule-controller-manager to ${REPLICAS} replicas (test-only failure simulation)"
kubectl --context=k3d-spoke-capsule scale deploy capsule-controller-manager \
  -n capsule-system --replicas="${REPLICAS}"
pass "scaled capsule-controller-manager to ${REPLICAS}"

if [[ "$REPLICAS" == "1" ]]; then
  section "Rollout status (recovery path; 90s timeout)"
  kubectl --context=k3d-spoke-capsule rollout status deploy/capsule-controller-manager \
    -n capsule-system --timeout=90s
  pass "capsule-controller-manager Ready"
fi
```

**Summary pattern** (fix-dns.sh lines 70-75 — copy verbatim, swap final message):
```bash
section "Summary"
printf "  %s%d passed%s, %s%d warnings%s, %s%d failed%s\n" \
  "${C_GREEN}" "${PASS}" "${C_RESET}" "${C_YELLOW}" "${WARN}" "${C_RESET}" "${C_RED}" "${FAIL}" "${C_RESET}"
if (( FAIL > 0 )); then exit 1; fi
printf "\n%scapsule-controller-manager scaled to ${REPLICAS}.%s\n" "${C_GREEN}" "${C_RESET}"
```

**Conventions to replicate:** identical to `destroy-poc.sh` above (same dir, same preamble, same `pass`/`fail` style, same summary block).

---

### `tests/bats/negative-rbac-{01..05}-*.bats` (NEW; live-bats, real-CRUD probe path)

**Analog:** `tests/bats/proxy-05-live-list-filter.bats` (closest analog — exact same probe shape, exact same kubeconfig source via `issue-tenant-kubeconfig.sh`, exact same direct-apiserver kubeconfig construction for N8). Secondary analogs: `tests/bats/tenants-07-live-impersonate.bats` (label-poll-with-retry) + `tests/bats/tenants-08-live-quota-limit.bats` (3×10s poll pattern).

**Header + load + setup_file pattern** (RESEARCH.md §"Pattern 2" lines 343-358 + proxy-05 lines 1-16 hybridized):
```bash
#!/usr/bin/env bats
# tests/bats/negative-rbac-01-cross-tenant-list.bats
# Phase 11 / Wave 0 (D-11-06 partition: N1-N3 cross-tenant list/secret falsifiers).
# RED until Plan 11-01 lands push-gate fixes + Plan 11-03 lands Tenant CR fixture extensions.
# Real-CRUD probe shape (D-11-05) — NOT kubectl auth can-i (P37 SAR cache flake).
# Mint-once kubeconfig via setup_file (D-11-07) — TmpDir-rooted, P29 invariant preserved.

load 'test_helper'

setup_file() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
  export KARYON_BATS_TMPDIR="${TMPDIR:-/tmp}/karyon-tenants/bats-${BATS_RUN_TMPDIR##*/}"
  mkdir -p "$KARYON_BATS_TMPDIR"
  bash "${REPO_ROOT}/scripts/poc/capsule/issue-tenant-kubeconfig.sh" alpha gitops-reconciler \
    --duration=2h --write-to "${KARYON_BATS_TMPDIR}/alpha.kubeconfig" >/dev/null
  bash "${REPO_ROOT}/scripts/poc/capsule/issue-tenant-kubeconfig.sh" bravo gitops-reconciler \
    --duration=2h --write-to "${KARYON_BATS_TMPDIR}/bravo.kubeconfig" >/dev/null
  export ALPHA_KUBECONFIG="${KARYON_BATS_TMPDIR}/alpha.kubeconfig"
  export BRAVO_KUBECONFIG="${KARYON_BATS_TMPDIR}/bravo.kubeconfig"
}

teardown_file() {
  rm -rf "$KARYON_BATS_TMPDIR"
}

setup() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
}
```

**N1-N3 cross-tenant probe pattern** (proxy-05 lines 53-69 + CONTEXT.md D-11-05 lines 86-87):
```bash
@test "N1 — cross-tenant pod LIST denied (alpha kubeconfig probing tenant-bravo)" {
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" get pods -n tenant-bravo
  [ "$status" -ne 0 ]
  echo "$output" | grep -qE "(Forbidden|forbidden|cannot list)"
}

@test "N2 — cluster-wide LIST filtered to alpha-owned namespaces" {
  PROXY_OUT=$(kubectl --kubeconfig="$ALPHA_KUBECONFIG" get pods --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{"\n"}{end}' 2>&1)
  echo "$PROXY_OUT" | sort -u | while read -r ns; do
    [[ "$ns" =~ ^(tenant-alpha|alpha-)$|^alpha- ]] || { echo "leaked namespace: $ns"; return 1; }
  done
}

@test "N3 — cross-tenant secret read denied (alpha kubeconfig probing tenant-bravo secrets)" {
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" get secret -n tenant-bravo
  [ "$status" -ne 0 ]
  echo "$output" | grep -qE "(Forbidden|forbidden|cannot list)"
}
```

**N8 direct-apiserver bypass pattern** (proxy-05 lines 18-71 — copy VERBATIM into negative-rbac-04):
```bash
@test "N8 — direct apiserver bypass returns 403 + 'cannot list resource' (Pitfall 10-P3 corrected)" {
  TOKEN=$(yq eval '.users[0].user.token' "$ALPHA_KUBECONFIG")
  DIRECT_KC=$(mktemp -p "${TMPDIR:-/tmp}" karyon-bats-n8-direct-XXXX.kubeconfig)
  cat > "$DIRECT_KC" <<EOF
apiVersion: v1
kind: Config
clusters:
- name: direct
  cluster:
    server: https://127.0.0.1:6446
    insecure-skip-tls-verify: true
users:
- name: alpha-sa
  user:
    token: $TOKEN
contexts:
- name: direct
  context:
    cluster: direct
    user: alpha-sa
current-context: direct
EOF
  DIRECT_RC=0
  DIRECT_OUT=$(kubectl --kubeconfig="$DIRECT_KC" get namespaces 2>&1) || DIRECT_RC=$?
  [ "$DIRECT_RC" -ne 0 ]
  echo "$DIRECT_OUT" | grep -qF 'Forbidden'
  echo "$DIRECT_OUT" | grep -qF 'cannot list resource "namespaces"'
  rm -f "$DIRECT_KC"
}
```

**N6 quota-violation probe pattern** (RESEARCH.md lines 567-588 + Pitfall 11-P3 permissive grep):
```bash
@test "N6 — tenant quota violation denied (real CRUD probe; Pitfall 11-P3 permissive grep)" {
  # Tenant alpha quota = 3 (set in pocs/capsule/spoke/tenants/alpha/tenant.yaml via Claude's discretion)
  # Pre-state: tenant-alpha (home) + alpha-app1 (Phase 9 TEN-02) = 2 namespaces
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" create namespace alpha-app2
  [ "$status" -eq 0 ]
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" create namespace alpha-app3
  [ "$status" -ne 0 ]
  echo "$output" | grep -qE "(quota|namespace.*(limit|max)|exceeded)"
  kubectl --kubeconfig="$ALPHA_KUBECONFIG" delete namespace alpha-app2 --wait=false || true
}
```

**N11/N12 webhook-down + recovery pattern** (RESEARCH.md lines 595-625 — copy verbatim):
```bash
@test "N11 — workload create rejected when capsule-controller down" {
  run task fail-capsule-webhook -- 0
  [ "$status" -eq 0 ]
  sleep 5
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" run probe-n11 \
    --image=registry.example.io/probe -n alpha-app1
  [ "$status" -ne 0 ]
  echo "$output" | grep -qE "(failed calling webhook|no endpoints available)"
}

@test "N12 — workload create succeeds again after operator recovers" {
  run task fail-capsule-webhook -- 1
  [ "$status" -eq 0 ]
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" run probe-n12 \
    --image=registry.example.io/probe -n alpha-app1
  [ "$status" -eq 0 ]
  kubectl --kubeconfig="$ALPHA_KUBECONFIG" delete pod probe-n12 -n alpha-app1 --wait=false || true
}
```

**Conventions to replicate:**
- `load 'test_helper'` (line 5 of every analog).
- `setup_file()` for mint-once kubeconfig (cited by RESEARCH.md as the canonical pattern — bats v1.5+).
- `setup()` cluster-info gate WITH `skip` (NOT `return 1`) — proxy-04 / proxy-05 / tenants-07-12 all use this; live-skip philosophy per D-11-13.
- `mktemp -p "${TMPDIR:-/tmp}" karyon-bats-XXXX-XXXX` for ephemeral kubeconfig files (proxy-04 line 17, proxy-05 lines 19+32 verbatim).
- `rm -f "$DIRECT_KC"` at end of each @test (per-test cleanup; proxy-05 line 71 verbatim).
- `echo "$output" | grep -qE` for permissive multi-pattern grep (Pitfall 11-P3 quota error).
- `echo "$output" | grep -qF` for exact literal grep (proxy-05 lines 57-62 verbatim).

---

### `tests/bats/negative-rbac-anti-pattern-lint-static.bats` (NEW; static lint)

**Analog:** `tests/bats/poc-isolation-01-static.bats` (anti-pattern grep-loop verbatim) + `tests/bats/proxy-01-static-script.bats` lines 100-118 (anti-pattern grep-NOT)

**Header + setup pattern** (poc-isolation-01-static.bats lines 1-16 — copy + adapt):
```bash
#!/usr/bin/env bats
# tests/bats/negative-rbac-anti-pattern-lint-static.bats
# D-11-05 enforcement — negative-rbac-*.bats source files MUST NOT contain
# `kubectl auth can-i` (Pitfall P37: SAR cache 5min/30s TTLs return stale results).

load 'test_helper'

setup() {
  NEGATIVE_RBAC_BATS=(
    "${REPO_ROOT}/tests/bats/negative-rbac-01-cross-tenant-list.bats"
    "${REPO_ROOT}/tests/bats/negative-rbac-02-escalation.bats"
    "${REPO_ROOT}/tests/bats/negative-rbac-03-webhook-policy.bats"
    "${REPO_ROOT}/tests/bats/negative-rbac-04-bypass-and-flux.bats"
    "${REPO_ROOT}/tests/bats/negative-rbac-05-webhook-down.bats"
  )
}
```

**Anti-pattern lint pattern** (poc-isolation-01-static.bats lines 18-24 verbatim shape):
```bash
@test "D-11-05 / P37: negative-rbac-*.bats files have ZERO 'kubectl auth can-i' (SAR cache anti-pattern)" {
  for f in "${NEGATIVE_RBAC_BATS[@]}"; do
    [ -f "$f" ]
    run bash -c "grep -v '^[[:space:]]*#' '$f' | grep -F -- 'kubectl auth can-i'"
    [ "$status" -ne 0 ]
  done
}
```

**Conventions to replicate:**
- Comment-stripping `grep -v '^[[:space:]]*#'` BEFORE the literal grep (poc-isolation-01-static.bats line 21 verbatim) — head comments documenting the anti-pattern as context don't trip the lint.
- `grep -F --` for literal-only match (no regex traps).
- `[ "$status" -ne 0 ]` to assert NO match (the lint passes when the anti-pattern is absent).

---

### `tests/bats/push-gate-{01..05}-{static|live}-*.bats` (NEW; static yaml shape + live cluster assertion)

**Analog (static):** `tests/bats/tenants-01-static-tenant-cr.bats` (yq path-extract verbatim shape) + `tests/bats/poc-mount-01-static.bats` (outer-K shape contract verbatim)

**Static yaml shape pattern** (tenants-01-static-tenant-cr.bats lines 1-22 + poc-mount-01-static.bats lines 59-66):

```bash
#!/usr/bin/env bats
# tests/bats/push-gate-01-static-rbac-postbuild.bats
# Phase 11 D-11-01 — Flux PostBuild patch on clusters/hub-flux/pocs/capsule.yaml extends
# the chart-rendered Role capsule-proxy:capsule-proxy in capsule-system with secrets RBAC
# (so kube-webhook-certgen Job can write its output Secret on initial Flux reconcile).

load 'test_helper'

setup() {
  POC_CAPSULE="${REPO_ROOT}/clusters/hub-flux/pocs/capsule.yaml"
}

@test "D-11-01: capsule.yaml has spec.patches block targeting Role capsule-proxy:capsule-proxy in capsule-system" {
  [ -f "$POC_CAPSULE" ]
  run yq eval '(.spec.patches // [])
    | map(select(.target.kind == "Role"
                 and .target.name == "capsule-proxy:capsule-proxy"
                 and .target.namespace == "capsule-system"))
    | length >= 1' "$POC_CAPSULE"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "D-11-01: capsule.yaml patch literal includes secrets verb 'create' (so certgen Job can write Secret)" {
  [ -f "$POC_CAPSULE" ]
  run grep -F -- '"create"' "$POC_CAPSULE"
  [ "$status" -eq 0 ]
}
```

**CapsuleConfiguration userGroups assertion** (tenants-01 lines 26-31 + capsuleconfig.yaml current shape on line 35):
```bash
@test "D-11-02: capsuleconfig.yaml spec.userGroups contains 3 canonical groups" {
  CC="${REPO_ROOT}/pocs/capsule/spoke/config/capsuleconfig.yaml"
  [ -f "$CC" ]
  run yq eval '(.spec.userGroups | length) == 3
               and (.spec.userGroups | contains(["capsule.clastix.io"]))
               and (.spec.userGroups | contains(["system:serviceaccounts"]))
               and (.spec.userGroups | contains(["system:authenticated"]))' "$CC"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}
```

**Tenant namespace label assertion** (tenants-01 lines 26-31 verbatim shape):
```bash
@test "D-11-03: tenant-alpha/namespace.yaml has metadata.labels.capsule.clastix.io/tenant=alpha" {
  NS="${REPO_ROOT}/pocs/capsule/spoke/tenants/alpha/namespace.yaml"
  [ -f "$NS" ]
  run yq eval '.metadata.labels."capsule.clastix.io/tenant" == "alpha"' "$NS"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}
```

**Gitleaks allowlist literal assertion** (proxy-02-static-leak-defenses.bats lines 24-28 verbatim shape):
```bash
@test "D-11-04: .gitleaks.toml [allowlist] paths contains '^\\.planning/.*\\.md\$' regex" {
  GITLEAKS="${REPO_ROOT}/.gitleaks.toml"
  [ -f "$GITLEAKS" ]
  # Match the exact triple-single-quoted regex literal (TOML raw-string form)
  run grep -E "'\\^\\\\\\.planning/\\.\\*\\\\\\.md\\\$'" "$GITLEAKS"
  [ "$status" -eq 0 ]
}
```

**Live gitleaks scan pattern** (repo-hygiene-04-poc.bats lines 84-95 verbatim shape):
```bash
@test "D-11-04 (live): gitleaks detect on full working tree exits 0 (zero findings)" {
  cd "$REPO_ROOT"
  run gitleaks detect --no-banner --no-git --source . --config "$REPO_ROOT/.gitleaks.toml" --redact
  [ "$status" -eq 0 ]
}
```

**Live tenant namespace label assertion** (tenants-07-live-impersonate.bats lines 37-46 verbatim — 3×30s retry):
```bash
@test "D-11-03 live (post-first-push): tenant-alpha namespace has capsule.clastix.io/tenant=alpha label (3×30s retry for Flux reconcile)" {
  local i label
  for i in 1 2 3; do
    label=$(kubectl --context=k3d-spoke-capsule get namespace tenant-alpha -o jsonpath='{.metadata.labels.capsule\.clastix\.io/tenant}' 2>/dev/null || true)
    [[ "$label" == "alpha" ]] && return 0
    [[ $i -lt 3 ]] && sleep 30
  done
  echo "Last observed label: '$label'"
  return 1
}
```

**Conventions to replicate:**
- `setup()` defines file path constants (tenants-01 lines 19-22 verbatim).
- `[ -f "$..." ]` first assertion in every @test (tenants-01 line 27 verbatim).
- `run yq eval '<expression>' "$file"` then `[ "$status" -eq 0 ]` then `[ "$output" = "true" ]` (tenants-01 lines 28-30 verbatim).
- `run grep -F --` for literal grep (no regex escaping).
- `run grep -E` only when regex needed (gitleaks allowlist literal).
- Live tests gate via `setup() { kubectl ... cluster-info ... || skip ...; }` (proxy-04 lines 10-14 verbatim).
- Polling pattern `for i in 1 2 3; do ... [[ "$x" == "$expected" ]] && return 0; [[ $i -lt 3 ]] && sleep 30; done` (tenants-07 lines 37-46 verbatim).

---

### `tests/bats/teardown-{01..04}-{static|live}-*.bats` (NEW; script-shape lint + live cluster assertion)

**Analog (static script-shape):** `tests/bats/proxy-01-static-script.bats` (verbatim shape — same kind of POC script, same lint surface)

**Header + setup pattern** (proxy-01-static-script.bats lines 1-11 — copy + adapt):
```bash
#!/usr/bin/env bats
# tests/bats/teardown-01-static-script.bats
# Phase 11 / Wave 0 — D-11-10 / D-11-11 static script-shape contract for
# scripts/poc/capsule/destroy-poc.sh. RED until Plan 11-02 lands the script.

load 'test_helper'

setup() {
  SCRIPT="${REPO_ROOT}/scripts/poc/capsule/destroy-poc.sh"
}
```

**Existence + shebang + strict-mode + path-pinning + preflight-lib pattern** (proxy-01 lines 13-28 verbatim shape):
```bash
@test "D-11-10: scripts/poc/capsule/destroy-poc.sh exists" {
  [ -f "$SCRIPT" ]
}

@test "D-11-10: script has shebang + strict-mode + path pinning + preflight-lib source" {
  [ -f "$SCRIPT" ]
  for literal in \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'SCRIPT_DIR=' \
    'REPO_ROOT=' \
    'source "${REPO_ROOT}/scripts/lib/preflight-lib.sh"' ; do
    run grep -F -- "$literal" "$SCRIPT"
    [ "$status" -eq 0 ]
  done
}
```

**Head-comment citation pattern** (proxy-01 lines 30-36 verbatim shape):
```bash
@test "D-11-10: head comment cites VAL-03 + D-11-10/11/12 + P31 + ADR-004" {
  [ -f "$SCRIPT" ]
  for literal in 'VAL-03' 'D-11-10' 'D-11-11' 'P31' 'ADR-004' ; do
    run grep -F -- "$literal" "$SCRIPT"
    [ "$status" -eq 0 ]
  done
}
```

**Sentinel-preservation anti-pattern lint** (proxy-01 lines 100-118 + poc-mount-01-static lines 17-21 hybridized):
```bash
@test "D-11-10 / sentinel preservation: destroy-poc.sh does NOT mutate flux-system kustomization.yaml" {
  [ -f "$SCRIPT" ]
  # Comment-stripped grep ensures head-comment context references to the file path don't trip the lint
  run bash -c "grep -v '^[[:space:]]*#' '$SCRIPT' | grep -F -- 'flux-system/kustomization.yaml'"
  [ "$status" -ne 0 ]
}

@test "D-11-10 / sentinel preservation: clusters/hub-flux/flux-system/kustomization.yaml retains # KARYON POC MOUNT after teardown" {
  HUB_FS_KUST="${REPO_ROOT}/clusters/hub-flux/flux-system/kustomization.yaml"
  [ -f "$HUB_FS_KUST" ]
  run grep -F -- '# KARYON POC MOUNT' "$HUB_FS_KUST"
  [ "$status" -eq 0 ]
  run grep -F -- '- ../pocs' "$HUB_FS_KUST"
  [ "$status" -eq 0 ]
}
```

**Live ordered-teardown probe pattern** (proxy-04 lines 10-14 + tenants-07 line 39 polling hybridized):
```bash
@test "D-11-10 live: post-task-destroy-poc-capsule no namespaces with capsule.clastix.io/tenant label remain" {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable"
  fi
  run task destroy-poc -- capsule
  [ "$status" -eq 0 ]
  # Post-state: zero labeled namespaces remain
  run kubectl --context=k3d-spoke-capsule get ns -l capsule.clastix.io/tenant -o name
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
```

**Live PVC strand mitigation pattern** (RESEARCH.md "Pitfall 11-P4" + tenants-08-live-quota-limit lines 27-36):
```bash
@test "D-11-11 live: synthetic Pod-bound PVC is force-deleted within 90s during destroy" {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable"
  fi
  # Seed a PVC bound by a Pod in alpha-app1 (depends on Plan 11-03 having created the namespace + tenant-alpha label)
  kubectl --context=k3d-spoke-capsule apply -n alpha-app1 -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: bats-strand-pvc
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 1Mi
EOF
  run task destroy-poc -- capsule
  [ "$status" -eq 0 ]
  # PVC should be gone within 90s (script auto-clears finalizer after 60s)
  for i in 1 2 3; do
    REMAINING=$(kubectl --context=k3d-spoke-capsule get pvc -A -l capsule.clastix.io/tenant=alpha -o name 2>/dev/null | wc -l)
    [[ "$REMAINING" -eq 0 ]] && return 0
    [[ $i -lt 3 ]] && sleep 30
  done
  return 1
}
```

**Conventions to replicate:**
- Comment-aware anti-pattern lint via `grep -v '^[[:space:]]*#' '$f' | grep -F` (proxy-01 line 104 verbatim).
- Live tests use `if ! kubectl ... cluster-info; then skip ...` (proxy-04 lines 11-13 verbatim) — NOT `return 1`.
- Sentinel preservation reads target file directly (poc-mount-01-static.bats lines 17-21).

---

### `tests/bats/slo-regression-live.bats` (NEW; ~4 @tests; live cluster + `task rebuild` wrapper)

**Analog:** `tests/bats/destroy-rebuild-01-static.bats` lines 91-105 (DESTROY-06 elapsed-seconds + log-file pattern; closest existing rebuild assertion) + `tests/bats/poc-isolation-01-static.bats` (verbatim @test inheritance per D-11-16)

**Header + setup_file pattern** (CONTEXT.md D-11-13 lines 246-281 — copy verbatim, planner-locked):
```bash
#!/usr/bin/env bats
# tests/bats/slo-regression-live.bats
# Phase 11 / VAL-04 — `task rebuild` SLO regression test (4 @tests):
#   a — task rebuild < 230s
#   b — k3d-spoke-capsule-server-0 container ID unchanged
#   c — task health-check exit 0
#   d — Phase 7 P31 lint inheritance (verbatim re-run of poc-isolation-01-static.bats per D-11-16)
# Live-skip gating: setup_file SKIPS if spoke-capsule not running (BEFORE_CID="MISSING" trap).

load 'test_helper'

setup_file() {
  export BEFORE_CID=$(docker inspect -f '{{.Id}}' k3d-spoke-capsule-server-0 2>/dev/null || echo "MISSING")
  if [[ "$BEFORE_CID" == "MISSING" ]]; then
    skip "spoke-capsule not running — VAL-04 requires live spoke-capsule for CID stability assertion"
  fi
}
```

**SLO timer pattern** (CONTEXT.md D-11-13 + RESEARCH.md "Pitfall 11-P5" verbatim):
```bash
@test "VAL-04 a — task rebuild completes < 230s" {
  cd "$REPO_ROOT"
  local start_s=$(date +%s)
  run task rebuild
  local end_s=$(date +%s)
  local elapsed=$((end_s - start_s))
  [[ "$status" -eq 0 ]] || { echo "task rebuild failed (status=$status)"; return 1; }
  [[ "$elapsed" -lt 230 ]] || { echo "task rebuild took ${elapsed}s (>= 230s SLO ceiling)"; return 1; }
  echo "rebuild elapsed: ${elapsed}s (budget: 230s)"
}
```

**CID compare pattern** (D-11-13 verbatim):
```bash
@test "VAL-04 b — k3d-spoke-capsule-server-0 container ID unchanged across rebuild" {
  local AFTER_CID=$(docker inspect -f '{{.Id}}' k3d-spoke-capsule-server-0)
  [[ "$BEFORE_CID" == "$AFTER_CID" ]] || { echo "spoke-capsule CID changed: $BEFORE_CID -> $AFTER_CID"; return 1; }
}
```

**Phase 7 P31 lint inheritance** (D-11-13 + D-11-16 verbatim):
```bash
@test "VAL-04 d — P31 static lint via Phase 7 inheritance" {
  cd "$REPO_ROOT"
  run bats tests/bats/poc-isolation-01-static.bats
  [[ "$status" -eq 0 ]]
}
```

**Conventions to replicate:**
- `setup_file()` for one-time pre-state capture (D-11-13 + RESEARCH.md Pattern 2 verbatim).
- `BEFORE_CID="MISSING"` early-skip trap (D-11-13 + RESEARCH.md Pattern 3 verbatim).
- `echo "rebuild elapsed: ..."` for human-readable diagnostic output even on PASS (D-11-13 specifics).
- Strict ceiling `< 230` (NOT `<=`) per D-11-13 specifics.

---

### `docs/adr/0008-capsule-multi-tenancy-graduation.md` (NEW; Nygard 4-section + 3 sub-sections)

**Analog:** `docs/adr/0004-hub-only-flux-control-plane.md` (most structurally similar; extensive Decision section, Easier/Harder/No-change Consequences breakdown)

**Header + Status pattern** (0004 lines 1-5 + CONTEXT.md D-11-14 frontmatter):
```markdown
# 8. Capsule Multi-Tenancy POC Graduation

## Status

Accepted (2026-MM-DD)

Outcome: <ADOPT|DEFER|REJECT|REPLACED BY ADR-009>
```

**Context section pattern** (0004 lines 7-25 — narrative explaining background):
```markdown
## Context

milestone v0.19 set out to validate Capsule multi-tenancy as a graduation candidate
for karyon's hub-only Flux control plane (ADR-004) running on the spoke-capsule
isolated k3d cluster (ADR-002). Phases 7-10 delivered:

- **Phase 7** — POC seam (spoke-capsule cluster + scripts/poc/capsule/ namespace
  isolation per P31 + EKSDOC-01 rough-cut design + .gitleaks.toml + .gitignore
  leak defenses).
- **Phase 8** — Capsule operator + capsule-proxy install via Flux HelmRelease +
  OCIRepository (split-path D-08-12 architectural seam).
- **Phase 9** — Tenant CRs (alpha, bravo) + multi-tenancy lockdown patches on
  hub-flux Flux controllers (--no-cross-namespace-refs + --default-service-account).
- **Phase 10** — Tenant kubeconfig issuance via TokenRequest API +
  capsule-proxy LIST filter validation.

This ADR records the v0.19 graduation decision based on Phase 11 empirical evidence.
```

**Decision section pattern** (CONTEXT.md D-11-14 evidence-bound rubric verbatim — incorporates 4-row outcome table):
```markdown
## Decision

The graduation outcome is **<ADOPT|DEFER|REJECT|REPLACED BY ADR-009>** per the
evidence-bound rubric (D-11-14):

| Outcome | Required evidence | Matched? |
|---|---|---|
| **ADOPT** | All 12/12 N1-N12 PASS + VAL-02 webhook recovery PASS + VAL-03 clean teardown PASS + VAL-04 < 230s + CID unchanged + zero gitleaks findings + ZERO open BLOCKER carryovers | <Y/N> |
| **DEFER** | ≥ 1 of: workaround documented OR upstream chart issue OR Phase 12 addon trial would clarify | <Y/N> |
| **REJECT** | ≥ 1 of: tenant-isolation invariant breached OR VAL-04 SLO regressed OR webhook recovery non-deterministic | <Y/N> |
| **REPLACED BY ADR-009** | Mid-validation discovery of fundamentally different POC | <Y/N> |

### What we proved

[bats refs: VAL-01 pass count from 11-VERIFICATION.md; VAL-02 webhook halves N11+N12 GREEN;
 VAL-03 teardown clean — zero stuck namespaces post-90s; VAL-04 < 230s + CID stability]

### What we did not prove

- HA Capsule (single replica only on spoke-capsule).
- OIDC integration (TokenRequest API only; no external IDP).
- Multi-spoke federation (spoke-capsule isolated; not part of hub-flux spoke topology).
- Hub-side Capsule (POC kept on isolated spoke per ADR-004).
- Real ingress / TLS for capsule-proxy (NodePort 30443 only; insecure-skip-tls-verify
  on direct apiserver bypass falsifier path).
- Production secret management (k3s TokenRequest, not IRSA/OIDC).

### Trade-offs

- **TokenRequest semantics on k3s vs IRSA on EKS** — k3s does NOT clamp at 24h
  (Phase 10 D-10-02 reframe; verified live for up to 720h). EKS clamps at 24h
  default via `--service-account-max-token-expiration`. Portability requires
  forking the duration logic for prod.
- **Chart-level RBAC patch (D-11-01)** is a workaround pending upstream
  capsule-proxy chart fix — the chart-rendered Role lacks `secrets create`
  permission needed by the bundled `kube-webhook-certgen` Job; karyon extends
  it via Flux PostBuild patches.
- **CapsuleConfiguration userGroups list (D-11-02)** is opinionated — chart
  default is `[capsule.clastix.io]` only; karyon adds `system:serviceaccounts`
  + `system:authenticated` to make proxy LIST recognize SA-token-authenticated
  identities as Capsule-owned.
- **PVC strand auto force-delete after 60s (D-11-11)** is acceptable for POC
  iteration — production teardown would need a `--preserve-data` flag.
```

**Consequences section pattern** (0004 lines 38-81 — Easier/Harder/No-change blocks):
```markdown
## Consequences

**[CONDITIONAL ON OUTCOME]**

### If ADOPT:

- v0.20 incorporates Capsule into the default `task rebuild` chain.
- spoke-capsule promoted from POC to v1 spoke; rebuild SLO budget updated.
- Phase 12 (capsule-addon-fluxcd v0.2.3 Trial) runs as adoption acceleration.
- D-09-03 forward-pointer (tenant inner K kubeConfig source swap) absorbed by Phase 12.

### If DEFER:

- v0.20 reruns Phase 11 with the addon pattern.
- spoke-capsule stays on persistent isolated cluster; not promoted to v1.
- Phase 12 (capsule-addon-fluxcd Trial) runs as gated re-evaluation pass.

### If REJECT:

- spoke-capsule torn down as part of v0.19 close (`task destroy-poc -- capsule --full`).
- No v0.20 carryover; multi-tenancy strategy returns to the design phase.
- ADR-008 references in EKSDOC-01 are negated.

### If REPLACED BY ADR-009:

- ADR-009 is named with the replacement POC (e.g., Hierarchical Namespaces, vCluster).
- This POC's artifacts archived under .planning/milestones/v0.19-archive/.

### Cross-references

- `docs/capsule-on-eks.md` (EKSDOC-01) — rolled forward to `Status: Reviewed` in this
  same plan; see "Push-gate translation" + "Cert source" + "IRSA" + "Proxy LIST scope"
  sections for prod-side translation informed by this graduation evidence.
```

**Conventions to replicate:**
- 4 Nygard sections in order: `## Status` / `## Context` / `## Decision` / `## Consequences` (verified by `tests/bats/docs-adr-template.bats` lines 26-43; ADR-008 should match for forward-compat with that lint).
- `Accepted (YYYY-MM-DD)` line in `## Status` (line 5 of every existing ADR — required by docs-adr-template.bats line 49).
- 3 sub-sections under `## Decision`: "What we proved" / "What we did not prove" / "Trade-offs" (per CONTEXT.md D-11-14 + RESEARCH.md §"Code Examples" ADR template).
- Multi-block structure under `## Consequences` mirroring 0004's "Easier/Harder/No-change" pattern but adapted to "If ADOPT/DEFER/REJECT/REPLACED" branches.
- Cross-reference to `docs/capsule-on-eks.md` (D-11-15 rollforward).

**Note on docs-adr-template.bats compatibility:** The existing static lint at lines 11-17 hardcodes a 5-element ADRS array. Plan 11-05 either (a) extends ADRS to include 0008 + adds a new @test asserting ADR-008-specific keywords, OR (b) lands ADR-008 as outside the existing lint's scope and adds `tests/bats/docs-08-adr-graduation-static.bats` as a sibling. Recommendation: (a) — extend existing lint for parity with 0001-0005.

---

### `clusters/hub-flux/pocs/capsule.yaml` (EDIT — D-11-01 ADD spec.patches)

**Analog:** `clusters/hub-flux/flux-system/kustomization.yaml` (existing JSON6902 patches block — same Flux v1 PostBuild patches shape; lines 28-69 verbatim shape)

**Existing file** (40 lines; see lines 27-39 for current spec):
```yaml
spec:
  interval: 5m
  path: ./pocs/capsule
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  serviceAccountName: kustomize-controller
```

**Patch addition pattern** (flux-system/kustomization.yaml lines 28-69 + RESEARCH.md §"Pattern 1" lines 314-326 — Flux v1 spec.patches JSON6902 op:add verbatim shape):
```yaml
spec:
  interval: 5m
  path: ./pocs/capsule
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  serviceAccountName: kustomize-controller
  # D-11-01 — PostBuild patch extends chart-rendered Role capsule-proxy:capsule-proxy in
  # capsule-system with secrets {get,create,update,patch} so kube-webhook-certgen Job can
  # write its output Secret on initial Flux reconcile (closes Phase 10 D-08-13 chart RBAC gap).
  # See Pitfall 11-P1 for the alternative target file consideration (capsule-spoke.yaml vs capsule.yaml).
  patches:
    - target:
        kind: Role
        name: capsule-proxy:capsule-proxy
        namespace: capsule-system
      patch: |
        - op: add
          path: /rules/-
          value:
            apiGroups: [""]
            resources: ["secrets"]
            verbs: ["get", "create", "update", "patch"]
```

**Conventions to replicate:**
- `target.kind` REQUIRED (RESEARCH.md "Critical syntax notes" line 331 verbatim — flux v1 doc requirement).
- `target.name` + `target.namespace` for precise targeting (mirrors flux-system/kustomization.yaml lines 30-32 pattern).
- `patch:` value as literal block scalar (`|`) holding YAML list of JSON6902 ops (same shape as flux-system/kustomization.yaml lines 33-42).
- `op: add` + `path: /rules/-` (RFC 6901 JSON pointer; `-` appends to array; verified shape against flux-system/kustomization.yaml lines 35-36).
- Inline comment block citing D-11-01 + Pitfall 11-P1 (precedent: flux-system/kustomization.yaml lines 23-27 inline comments above the patches block).

**Pitfall 11-P1 escalation note:** RESEARCH.md flagged that this patch may target the wrong file — Helm-rendered manifests are downstream of kustomize-controller, so the Role may not exist at patch time. Plan 11-01 may need to relocate the patch to `clusters/hub-flux/pocs/capsule-spoke.yaml` instead. Bats `push-gate-04-live-tenant-ns-flux-apply.bats` is the empirical falsifier.

---

### `pocs/capsule/spoke/config/capsuleconfig.yaml` (EDIT — D-11-02 spec.userGroups → 3-group list)

**Analog:** (self-edit — file already exists with `userGroups: [capsule.clastix.io]` at line 35)

**Current state** (lines 30-35):
```yaml
  # Owner-group filter (chart default; matches what capsule webhooks expect)
  # NOTE: userGroups is DEPRECATED in v1beta2 (replaced by spec.users), but the
  # capsule chart still uses this for default group-based owner detection.
  # Keeping for compatibility; planner may switch to spec.users post-graduation.
  userGroups:
    - capsule.clastix.io
```

**Target state** (CONTEXT.md D-11-02 + Plan 10-02 patched live state mirrored to repo):
```yaml
  # Owner-group filter (chart default + Phase 11 D-11-02 extension to recognize
  # SA-token-authenticated identities as Capsule-owned for proxy LIST behavior).
  # Phase 10 Plan 10-02 patched the live CapsuleConfiguration with these 3 groups; this
  # repo edit makes the GitOps source canonical (single source of truth — reads exactly
  # like the live cluster state). NOTE: userGroups is DEPRECATED in v1beta2 (replaced
  # by spec.users), but the capsule chart still uses this for default group-based owner
  # detection. Keeping for compatibility; planner may switch to spec.users post-graduation.
  userGroups:
    - capsule.clastix.io
    - system:serviceaccounts
    - system:authenticated
```

**Conventions to replicate:**
- Inline comment block citing D-11-02 + Plan 10-02 ancestry (precedent: same file lines 31-33 already include the deprecated/spec.users note).
- 3-element list verbatim — order matters for some yq path-extract assertions in push-gate-02-static-capsuleconfig.bats; align with bats `contains([...])` checks.

---

### `pocs/capsule/spoke/tenants/{alpha,bravo}/namespace.yaml` (EDIT — D-11-03 ADD metadata.labels)

**Analog:** (self-edit — file is currently 11 lines; no labels block exists)

**Current state** (alpha/namespace.yaml lines 1-12, bravo/namespace.yaml mirror):
```yaml
# pocs/capsule/spoke/tenants/alpha/namespace.yaml
# TEN-01 — the tenant home namespace on spoke-capsule. Holds the gitops-reconciler
# SA that the Tenant CR registers as ServiceAccount owner.
#
# D-09-02 — tenant home namespace name pattern: tenant-<tenant-name>.
# The tenant's auto-created child namespaces use prefix <tenant-name>- (e.g. alpha-app1)
# enforced by spec.forceTenantPrefix in the Tenant CR.
apiVersion: v1
kind: Namespace
metadata:
  name: tenant-alpha
```

**Target state** (D-11-03 verbatim + Pitfall 11-P2 cluster-admin Flux apply assumption):
```yaml
# pocs/capsule/spoke/tenants/alpha/namespace.yaml
# TEN-01 — the tenant home namespace on spoke-capsule. Holds the gitops-reconciler
# SA that the Tenant CR registers as ServiceAccount owner.
#
# D-09-02 — tenant home namespace name pattern: tenant-<tenant-name>.
# The tenant's auto-created child namespaces use prefix <tenant-name>- (e.g. alpha-app1)
# enforced by spec.forceTenantPrefix in the Tenant CR.
#
# D-11-03 (Phase 11) — capsule.clastix.io/tenant=alpha label inline. Trust that the
# cluster-admin Flux apply path bypasses Capsule's webhook prefix-violation check
# (Pitfall 11-P2: empirical verification at Plan 11-04 first-push event; if rejected,
# escalate to operator-runbook --as=alpha fallback).
apiVersion: v1
kind: Namespace
metadata:
  name: tenant-alpha
  labels:
    capsule.clastix.io/tenant: alpha
```

**Conventions to replicate:**
- bravo/namespace.yaml mirrors with `name: tenant-bravo` + `capsule.clastix.io/tenant: bravo`.
- Inline comment block citing D-11-03 + Pitfall 11-P2 (precedent: existing comments lines 1-7).

---

### `pocs/capsule/spoke/tenants/{alpha,bravo}/tenant.yaml` (OPTIONAL EDIT — Claude's discretion N6/N7 fixtures)

**Analog:** (self-edit — file is currently 58 lines with `resourceQuotas` + `limitRanges` already present at lines 35-51; no `namespaceOptions` or `containerRegistries`)

**Current state** (alpha/tenant.yaml lines 19-57; relevant sub-tree):
```yaml
spec:
  forceTenantPrefix: true
  owners:
    - kind: ServiceAccount
      name: system:serviceaccount:tenant-alpha:gitops-reconciler
    - kind: User
      name: alpha
  resourceQuotas:
    items:
      - hard:
          cpu: "4"
          memory: 8Gi
          pods: "20"
  limitRanges:
    items:
      - limits:
          - type: Container
            default:
              cpu: 100m
              memory: 128Mi
            defaultRequest:
              cpu: 50m
              memory: 64Mi
  # NOTE: namespaceOptions intentionally OMITTED — TEN-01 only requires
  # forceTenantPrefix (now top-level). namespaceOptions.quota (max namespace
  # count) is omitted; tenant can create unlimited namespaces inside prefix.
  # No additionalRoleBindings, storageClasses, ingressClasses, containerRegistries,
  # nodeSelector, networkPolicies — Capsule defaults to allow-all (per CONTEXT.md
  # Claude's Discretion).
```

**Target state** (RESEARCH.md §"Code Examples" lines 521-565 verified Capsule v0.12.4 schema + CONTEXT.md Claude's Discretion defaults):
```yaml
spec:
  forceTenantPrefix: true
  owners:
    - kind: ServiceAccount
      name: system:serviceaccount:tenant-alpha:gitops-reconciler
    - kind: User
      name: alpha
  # N6 fixture (Phase 11 Claude's discretion) — namespace quota 3:
  # tenant-alpha (home) + alpha-app1 (Phase 9 TEN-02) = 2; bats N6 creates alpha-app2 (3rd, OK)
  # then alpha-app3 (4th, REJECTED with quota webhook error per Pitfall 11-P3 permissive grep).
  namespaceOptions:
    quota: 3
  # N7 fixture (Phase 11 Claude's discretion) — container registry allowlist:
  # bats N7 runs `kubectl run x --image=docker.io/library/nginx -n alpha-app1` and asserts
  # webhook rejects with registry-violation error (only registry.example.io is allowed).
  containerRegistries:
    allowed:
      - registry.example.io
  resourceQuotas:
    items:
      - hard:
          cpu: "4"
          memory: 8Gi
          pods: "20"
  limitRanges:
    items:
      - limits:
          - type: Container
            default:
              cpu: 100m
              memory: 128Mi
            defaultRequest:
              cpu: 50m
              memory: 64Mi
```

**Conventions to replicate:**
- `spec.namespaceOptions.quota: 3` (RESEARCH.md verified type `*int32`; Capsule v0.12.4 v1beta2 schema).
- `spec.containerRegistries.allowed: [registry.example.io]` (RESEARCH.md verified type `AllowedListSpec {allowed: []string, allowedRegex: string}`; deprecated in v0.12.4 but still functional for POC).
- Inline comments citing N6/N7 fixture + bats trigger (precedent: existing comments lines 21-22 + 31-34 + 41-43 already cite N1-N12 mappings).
- Bravo mirror: `quota: 3` (same default — symmetric tenants).

---

### `.gitleaks.toml` (EDIT — D-11-04 APPEND `^\.planning/.*\.md$` to allowlist paths)

**Analog:** (self-edit — file is currently 35 lines; existing precedent at line 13 `^\.env\.example$`)

**Current state** (lines 7-15):
```toml
[allowlist]
description = "False positives: placeholder tokens and CONTEXT.md SHAs"
regexes = [
  '''ghp_REPLACE_WITH_PAT_WITH_repo_SCOPE''',  # .env.example placeholder (D-09 Phase 1)
]
paths = [
  '''^\.env\.example$''',                       # whole-file allow (Phase 1 D-11 contract)
]
```

**Target state** (D-11-04 verbatim — append `'^\.planning/.*\.md$'` to `paths` list):
```toml
[allowlist]
description = "False positives: placeholder tokens and CONTEXT.md SHAs"
regexes = [
  '''ghp_REPLACE_WITH_PAT_WITH_repo_SCOPE''',  # .env.example placeholder (D-09 Phase 1)
]
paths = [
  '''^\.env\.example$''',                       # whole-file allow (Phase 1 D-11 contract)
  '''^\.planning/.*\.md$''',                    # Phase 11 D-11-04 — planning docs auto-allowlisted
                                                # (Phase 7 carryover: synthetic-kubeconfig fixture content
                                                # quoted in retrospective markdown is non-leak surface)
]
```

**Conventions to replicate:**
- Triple-single-quoted TOML raw strings (no escape needed for backslashes — verified lines 11+13 precedent).
- Inline `#` comment beside the new path entry citing D-11-04 + Phase 7 carryover (precedent: line 13 trailing comment style).

---

### `Taskfile.yml` (EDIT — D-11-12 ADD 2 top-level entries)

**Analog:** (self-edit — file is currently 62 lines; existing precedent at lines 44-47 `fix-dns-poc-capsule:` POC sibling)

**Current state** (lines 44-47):
```yaml
  fix-dns-poc-capsule:
    desc: Stop/start spoke-capsule to refresh stale k3d CoreDNS NodeHosts (POC; does NOT affect default fix-dns)
    cmds:
      - bash scripts/poc/capsule/fix-dns.sh
```

**Target state** (CONTEXT.md D-11-12 verbatim — append after `rebuild:` block at line 62):
```yaml
  fail-capsule-webhook:
    desc: (POC) Scale capsule-controller-manager to N replicas (test-only failure simulation; usage `task fail-capsule-webhook -- 0|1`)
    cmds:
      - bash scripts/poc/capsule/fail-capsule-webhook.sh {{.CLI_ARGS}}

  destroy-poc:
    desc: (POC) Ordered teardown for a named POC (usage `task destroy-poc -- capsule [--full]`)
    cmds:
      - bash scripts/poc/capsule/destroy-poc.sh {{.CLI_ARGS}}
```

**Conventions to replicate:**
- 2-space indent for top-level task names (file uses 2-space throughout).
- `desc:` line with `(POC)` prefix to distinguish from v0.18 tasks (precedent: line 45 `(POC; does NOT affect default fix-dns)` parenthetical pattern).
- `cmds:` block with single `bash scripts/...` invocation (REPO-05 thin-wrapper invariant per `tests/bats/repo-hygiene-02-taskfile.bats` lines 33-40 — verified accepts nested POC paths per line 36 comment).
- `{{.CLI_ARGS}}` for variadic positional/flag pass-through (CONTEXT.md D-11-12 verbatim — Taskfile v3 idiom).

---

### `docs/capsule-on-eks.md` (EDIT — D-11-15 ROLLFORWARD frontmatter + 4 revision blocks)

**Analog:** (self-edit — file currently has `Status: Draft` at line 1; frontmatter `status-rollover` policy line 6 declares this rollforward)

**Current frontmatter** (lines 1-7):
```yaml
---
Status: Draft
audience: Mixed Engineering + Cloud Ops
purpose: Team-presentation primer for the Karyon v0.19 Capsule POC translated to an EKS target.
source-of-truth: .planning/research/SUMMARY.md (topology), .planning/research/FEATURES.md (CRDs), .planning/research/STACK.md (chart pins).
status-rollover: Phase 11 graduation ADR-008 rolls Status from Draft to Reviewed with corrections informed by bats evidence.
---
```

**Target frontmatter** (CONTEXT.md `<specifics>` lines 561-569 verbatim):
```yaml
---
Status: Reviewed
audience: Mixed Engineering + Cloud Ops
purpose: Team-presentation primer for the Karyon v0.19 Capsule POC translated to an EKS target.
source-of-truth: .planning/research/SUMMARY.md (topology), .planning/research/FEATURES.md (CRDs), .planning/research/STACK.md (chart pins).
reviewed: 2026-MM-DD
reviewed_against: ADR-008 (Capsule Multi-Tenancy POC Graduation)
reviewed_by: karyon milestone owner
---
```

**4 revision blocks** (CONTEXT.md D-11-15 lines 326-330 verbatim — locations are the existing H2 sections in the file):

1. **Cert source section** (currently around line 100-150) — add Pitfall 10-P1 finding paragraph:
   > **Phase 11 evidence (ADR-008 cross-reference):** capsule-proxy chart's `kube-webhook-certgen` Job emits `tls.crt` only; the chart self-signs the root with `tls.crt` doubling as CA; **NO `ca.crt` key is generated**. EKS translation requires cert-manager (controller-managed) or AWS Certificate Manager (ALB-side termination) — the controller-less certgen Job pattern doesn't translate cleanly to EKS without operational state-tracking.

2. **IRSA section** — add or correct Phase 10 D-10-01 TokenRequest API + JWT exp claim verification paragraph:
   > **Phase 11 evidence (ADR-008 cross-reference):** The POC's TokenRequest pattern translates cleanly to IRSA on EKS (both are short-lived bearer tokens via apiserver-side lifecycle); however, the `--service-account-max-token-expiration` clamp behavior differs across distros — k3s does NOT clamp (Phase 10 D-10-02 verified live for up to 720h); EKS clamps at 24h default. Production translation must adapt the duration logic.

3. **Proxy LIST scope section** — add Phase 11 N1-N9 evidence paragraph:
   > **Phase 11 evidence (ADR-008 cross-reference):** Negative RBAC bats N1-N9 empirically verified the proxy-edge LIST filter scope:
   > - capsule-proxy filters: namespace LIST (verified by N1, N2, N3 with cross-tenant kubeconfig).
   > - cluster-scoped resources (ClusterRole, ClusterRoleBinding, nodes) filtered by upstream RBAC NOT proxy (verified by N4 ClusterRoleBinding escalation denied at apiserver auth, not at proxy edge).

4. **Push-gate translation section** (NEW — append at end of doc OR fold into existing Push-gate / Bootstrap section):
   > **Phase 11 evidence (ADR-008 cross-reference) — EKS analogues for the v0.19 push-gate fixes:**
   > - **Flux PostBuild patch (D-11-01)** maps to Argo CD's post-render kustomization patches (or `argocd-application-controller` JSON patches via `argocd.argoproj.io/sync-options`).
   > - **CapsuleConfiguration repo-side update (D-11-02)** is portable as-is — single declarative source-of-truth.
   > - **Tenant home namespace label (D-11-03)** requires Argo CD's `argocd.argoproj.io/sync-options: ServerSideApply` to handle the cluster-admin-bypass-webhook semantics (system:masters bypass is identical across distros — verified Pitfall 11-P2).

**Conventions to replicate:**
- Frontmatter YAML format with `---` delimiters (line 1 + 7 of current file).
- New frontmatter keys (`reviewed`, `reviewed_against`, `reviewed_by`) inline below existing keys (preserves order).
- Inline reference `(ADR-008 cross-reference)` pattern for each revision block.

---

### `docs/poc-capsule.md` (OPTIONAL EDIT — Plan 11-02 discretion; H2 append)

**Analog:** (self-edit — frontmatter line 5 already declares "Phase 11 will add ordered teardown procedure")

**Current frontmatter** (line 5):
```
scope: Phase 7 ships the Host restart recovery section. Phase 10 added tenant kubeconfig delivery contract. Phase 11 will add ordered teardown procedure.
```

**Target H2 append** (Plan 11-02 discretion per CONTEXT.md `<deferred>` line 603):
```markdown
## Ordered teardown procedure

> **Status:** Active (Phase 11 — D-11-10 + D-11-11 + ADR-008 cross-reference).

The `task destroy-poc -- capsule [--full]` command performs an ordered 5-step teardown
of the spoke-capsule POC. See ADR-008 "Trade-offs" section for the POC-vs-prod boundary.

### Quickstart

```
task destroy-poc -- capsule          # leaves spoke-capsule + Capsule operator alive; tenants gone
task destroy-poc -- capsule --full   # destroys the spoke-capsule cluster entirely
```

### What to expect

```text
== Step 1: suspend tenant inner Ks + spoke-targeted outer K ==
  ok  suspended: tenant-alpha tenant-bravo poc-capsule-spoke
== Step 2: delete Tenant CRs (cascade triggers tenant namespace cascade) ==
  ok  deleted: Tenant alpha bravo
== Step 3: poll namespace cascade (max 90s; auto force-delete PVCs after 60s) ==
  --  namespace cascade stuck at 60s; force-clearing PVC finalizers (P36 mitigation)
  ok  namespace cascade complete
== Step 4: suspend operator + config outer Ks (preserves GitOps install state) ==
  ok  suspended: poc-capsule poc-capsule-config
== Step 5: optional cluster delete (--full flag) ==
  --  skipping k3d cluster delete (--full not set; cluster + Capsule operator remain alive but tenants gone)
== Summary ==
  4 passed, 0 warnings, 0 failed
Ordered teardown complete for spoke-capsule POC.
```

### PVC strand mitigation (P36)

Step 3 polls the namespace cascade for up to 90 seconds. If any namespace is stuck due to
a stranded PVC (`pvc-protection` finalizer not cleared by deleter), the script auto-clears
the finalizer at the 60-second mark per D-11-11.

**POC-only limitation (ADR-008 "Trade-offs"):** This force-clears PVC data without prompt.
Acceptable for POC iteration where data is ephemeral. Production teardown would need a
`--preserve-data` flag (out of scope for v0.19).

### Sentinel preservation guarantee

The `# KARYON POC MOUNT` sentinel and `- ../pocs` mount line in
`clusters/hub-flux/flux-system/kustomization.yaml` stay verbatim post-teardown
regardless of `--full`. The script does NOT modify this file.
```

**Conventions to replicate:**
- H2 (`##`) section heading style (precedent: poc-capsule.md `## Host restart recovery` at line 25).
- `> **Status:** Active (...)` blockquote line below H2 (precedent: line 11 `> **Status:** Active (Phase 7 ...)`)
- `### Quickstart` / `### What to expect` / `### How to verify` H3 sub-sections (precedent: lines 29-67 in current file).
- Code-fenced expected output block (precedent: lines 44-55 fix-dns-poc-capsule expected output).

---

## Shared Patterns

### Bash strict-mode + path pinning (poc-script preamble)

**Source:** `scripts/poc/capsule/fix-dns.sh` lines 17-23 (also identical in `create-cluster.sh` lines 14-20)

**Apply to:** Both NEW scripts (`destroy-poc.sh`, `fail-capsule-webhook.sh`).

```bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# shellcheck source=../../lib/preflight-lib.sh
# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/lib/preflight-lib.sh"
```

**Critical:** `${SCRIPT_DIR}/../../..` (THREE levels up) — POC scripts are 3 directories deep at `scripts/poc/capsule/<script>.sh`. The v0.18 scripts at `scripts/<script>.sh` use ONE level up (`${SCRIPT_DIR}/..`); using the wrong path silently breaks `REPO_ROOT` resolution.

### Preflight-lib output helpers (pass/fail/warn/info)

**Source:** `scripts/lib/preflight-lib.sh` lines 21-27

**Apply to:** Both NEW scripts. Used as ANSI-colored stdout helpers (NOT stderr like `issue-tenant-kubeconfig.sh` — that script's stdout reserved for kubeconfig YAML payload; Phase 11 scripts have no payload to protect).

```bash
section() { printf "\n%s%s== %s ==%s\n" "$C_BOLD" "$C_BLUE" "$1" "$C_RESET"; }
pass()    { printf "  %s✓%s %s\n" "$C_GREEN" "$C_RESET" "$1"; PASS=$((PASS+1)); }
warn()    { printf "  %s!%s %s\n" "$C_YELLOW" "$C_RESET" "$1"; WARN=$((WARN+1)); WARN_MSGS+=("$1"); }
fail()    { printf "  %s✗%s %s\n" "$C_RED" "$C_RESET" "$1"; FAIL=$((FAIL+1)); FAIL_MSGS+=("$1"); }
info()    { printf "  %s·%s %s\n" "$C_DIM" "$C_RESET" "$1"; }
have()    { command -v "$1" >/dev/null 2>&1; }
```

### Bats test_helper loader

**Source:** `tests/bats/test_helper.bash` lines 1-22

**Apply to:** All 11 NEW bats files.

```bash
load 'test_helper'
```

`test_helper.bash` provides `REPO_ROOT`, `IMAGES_DIR`, `cuda_image_tag`, and sources `preflight-lib.sh`. Every NEW bats file uses `${REPO_ROOT}/...` path constants in `setup()` per the proxy-04 / tenants-07 / poc-mount-01 / proxy-01 conventions.

### Live-skip cluster-info gate (live bats)

**Source:** `tests/bats/proxy-04-live-issue.bats` lines 10-14 (verbatim across proxy-04, proxy-05, tenants-07-12)

**Apply to:** All NEW live-bats files (negative-rbac-01..05, push-gate-04, teardown-03/04, slo-regression-live).

```bash
setup() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
}
```

For `slo-regression-live.bats` specifically, the gate goes in `setup_file()` and uses the Docker CID probe (D-11-13 verbatim) — `BEFORE_CID="MISSING"` early-skip variant.

### Anti-pattern grep lint (comment-aware)

**Source:** `tests/bats/poc-isolation-01-static.bats` lines 18-24 + `tests/bats/proxy-01-static-script.bats` lines 100-118

**Apply to:** `negative-rbac-anti-pattern-lint-static.bats`, `teardown-02-static-sentinel-preservation.bats`, `push-gate-*.bats` anti-pattern @tests.

```bash
@test "<anti-pattern lint>" {
  run bash -c "grep -v '^[[:space:]]*#' '$f' | grep -F -- '<anti-pattern literal>'"
  [ "$status" -ne 0 ]
}
```

The `grep -v '^[[:space:]]*#'` first-pass strips comments so head-comment context references don't trip the lint.

### Yq path-extract assertion (static yaml shape)

**Source:** `tests/bats/tenants-01-static-tenant-cr.bats` lines 26-31 + `tests/bats/poc-mount-01-static.bats` lines 52-66

**Apply to:** All `push-gate-*-static-*.bats` + `teardown-01-static-script.bats`.

```bash
@test "<assertion>" {
  [ -f "$YAML_FILE" ]
  run yq eval '<expression returning true|false>' "$YAML_FILE"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}
```

### Polling-with-retry (live cluster state convergence)

**Source:** `tests/bats/tenants-07-live-impersonate.bats` lines 37-46 + `tests/bats/tenants-08-live-quota-limit.bats` lines 27-36 + `tests/bats/tenants-10-live-lockdown.bats` lines 68-82

**Apply to:** `push-gate-04-live-tenant-ns-flux-apply.bats` (Flux reconcile up to 90s) + `teardown-03-live-ordered.bats` + `teardown-04-live-pvc-strand-mitigation.bats`.

```bash
local i value
for i in 1 2 3; do
  value=$(kubectl ... 2>/dev/null || true)
  [[ "$value" == "$expected" ]] && return 0
  [[ $i -lt 3 ]] && sleep 30
done
echo "Last observed: '$value'"
return 1
```

Standard bats budgets: 3×30s (90s total — Flux reconcile + Capsule controller observation), 3×10s (30s total — auto-materialization), 4×30s (2-min — controller restart).

### TmpDir-rooted ephemeral artifacts (P29 invariant)

**Source:** `tests/bats/proxy-04-live-issue.bats` line 17 + `tests/bats/proxy-05-live-list-filter.bats` lines 19+32 + RESEARCH.md §"Pattern 2" lines 343-358

**Apply to:** All `negative-rbac-*.bats` (kubeconfig minting + N8 direct-apiserver kubeconfig + N9/N10 cross-tenant Kustomization probes).

```bash
TMPFILE=$(mktemp -p "${TMPDIR:-/tmp}" karyon-bats-<topic>-XXXX.<suffix>)
# ... use $TMPFILE ...
rm -f "$TMPFILE"  # per-test cleanup
```

For `setup_file()`-managed kubeconfig caches:
```bash
export KARYON_BATS_TMPDIR="${TMPDIR:-/tmp}/karyon-tenants/bats-${BATS_RUN_TMPDIR##*/}"
mkdir -p "$KARYON_BATS_TMPDIR"
# ... mint kubeconfigs to $KARYON_BATS_TMPDIR ...
# teardown_file: rm -rf "$KARYON_BATS_TMPDIR"
```

P29 invariant: kubeconfigs MUST NOT land in repo. Always tmpdir-rooted, always cleaned up.

### Idempotent destructive ops (`|| true`)

**Source:** Common idiom across `destroy.sh`, `delete-clusters.sh`, `fix-dns.sh` line 113 (`k3d cluster delete ${POC_CLUSTER} >/dev/null 2>&1 || true`)

**Apply to:** `destroy-poc.sh` step 1 (`flux suspend ... || true`), step 2 (`kubectl delete ... --ignore-not-found`), step 4 (`flux suspend ... || true`), step 3 PVC patch (`xargs ... || true`).

The script is fail-fast on tool-gate / flag-parse via `exit 1` after `fail`, but data-step failures use `|| true` to continue then summary-fail at end (so partial-state re-run is non-destructive).

### ADR Nygard 4-section template (verified by lint)

**Source:** `docs/adr/0004-hub-only-flux-control-plane.md` (canonical structurally similar — long Decision section, layered Consequences) + `tests/bats/docs-adr-template.bats` lines 26-43 (lint that asserts the 4 sections in order)

**Apply to:** `docs/adr/0008-capsule-multi-tenancy-graduation.md`.

```markdown
# 8. <Title>

## Status

Accepted (YYYY-MM-DD)

## Context

<background; load-bearing context references>

## Decision

<decision statement; for ADR-008 the rubric table + 3 sub-sections "What we proved" / "What we did not prove" / "Trade-offs">

## Consequences

<easier/harder/no-change blocks; for ADR-008 the conditional outcome blocks ADOPT/DEFER/REJECT/REPLACED>
```

**Critical for compatibility with existing lint:** `docs-adr-template.bats` line 49 asserts `Status: Accepted` in the first 10 lines. ADR-008 must comply.

---

## No Analog Found

None — every Phase 11 file has a strong analog in the codebase. Phase 11 is largely an assembly + extension phase.

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| (none) | | | All NEW files have at least one strong analog. |

The closest case to "no analog" is `tests/bats/slo-regression-live.bats` — no existing bats file wraps `task rebuild` and times it. The closest analog (`tests/bats/destroy-rebuild-01-static.bats` lines 91-105 DESTROY-06) only asserts that the rebuild script's source code mentions the timeout literal `1200` and the log-file path; it does not actually invoke `task rebuild`. Phase 11 introduces the LIVE wrapper for the first time. Pattern guidance: combine the `setup_file()` pattern from RESEARCH.md §"Pattern 2" with the BEFORE_CID skip-trap from RESEARCH.md §"Pattern 3"; the assertion shape itself is a fresh combination of `date +%s` differential + `docker inspect -f '{{.Id}}'` (both bash-native, no analog needed).

---

## Metadata

**Analog search scope:**
- `scripts/poc/capsule/` (3 existing files; all 3 read fully)
- `scripts/lib/` (1 file: preflight-lib.sh; relevant top section read)
- `tests/bats/` (62 existing files; sampled 13 most relevant)
- `clusters/hub-flux/pocs/` (3 files; all read fully)
- `clusters/hub-flux/flux-system/` (1 file kustomization.yaml read for spec.patches analog)
- `pocs/capsule/spoke/tenants/{alpha,bravo}/` (4 files: namespace.yaml + tenant.yaml × 2 — all read fully)
- `pocs/capsule/spoke/config/` (1 file: capsuleconfig.yaml read fully)
- `docs/adr/` (5 existing ADRs; ADR-0001 + 0004 + 0005 read fully; rest cited via existing lint)
- `docs/` (capsule-on-eks.md head + poc-capsule.md head read)
- Repo-root config (`.gitleaks.toml`, `Taskfile.yml` — both read fully)

**Files scanned:** ~30 (read or grep-targeted)
**Pattern extraction date:** 2026-05-05

**Key cross-cutting notes for the planner:**

1. **Path depth invariant:** POC scripts at `scripts/poc/capsule/` use `${SCRIPT_DIR}/../../..` (3 levels). Misusing `..` breaks REPO_ROOT silently.
2. **Stdout/stderr split:** `destroy-poc.sh` + `fail-capsule-webhook.sh` use stdout (no payload to protect; mirrors `fix-dns.sh` + `create-cluster.sh`). The stderr-redirect pattern in `issue-tenant-kubeconfig.sh` lines 47-51 is NOT applicable here.
3. **Bats live-skip philosophy:** `cluster-info` gate uses `skip` (NOT `return 1`). Phase 11 inherits this from Phase 7-10 verbatim.
4. **Sentinel preservation:** `clusters/hub-flux/flux-system/kustomization.yaml` lines 19-22 (`# KARYON POC MOUNT` + `- ../pocs`) is the load-bearing invariant. `destroy-poc.sh` MUST NOT touch this file. `teardown-02-static-sentinel-preservation.bats` enforces.
5. **Pitfall 11-P1 escalation:** D-11-01's PostBuild patch on `clusters/hub-flux/pocs/capsule.yaml` may need to relocate to `clusters/hub-flux/pocs/capsule-spoke.yaml` if the chart-rendered Role isn't visible at kustomize-controller patch time. Plan 11-01 verifies empirically via `push-gate-04-live-tenant-ns-flux-apply.bats`. The pattern shape itself stays identical — only the target file changes.
6. **Pitfall 11-P3 permissive grep:** N6 quota-violation error string is not a Capsule constant. Use `grep -qE "(quota|namespace.*(limit|max)|exceeded)"` (multi-pattern) per RESEARCH.md §"Pitfall 11-P3" verbatim.
7. **Existing lint compatibility:** `docs-adr-template.bats` hardcodes a 5-element ADRS array. Plan 11-05 either extends the array to 6 (preferred) or adds a sibling `docs-08-adr-graduation-static.bats` that mirrors the lint surface for ADR-008 alone.
