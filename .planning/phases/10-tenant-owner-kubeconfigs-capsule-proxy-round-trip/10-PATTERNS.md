# Phase 10: Tenant Owner Kubeconfigs + Capsule-Proxy Round-trip — Pattern Map

**Mapped:** 2026-05-05
**Files analyzed:** 9 (8 NEW + 1 MODIFIED)
**Analogs found:** 9 / 9 (100% coverage — all in-repo)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `scripts/poc/capsule/issue-tenant-kubeconfig.sh` (NEW) | imperative bash script — kubeconfig emitter under `scripts/poc/capsule/` (P31) | request-response (positional + flags → stdout YAML) with kubectl-mediated TokenRequest call | `scripts/register-poc-cluster.sh` (kubeconfig heredoc + kubectl preflight + multi-line `fail` + token-safe stdout split) AND `scripts/poc/capsule/create-cluster.sh` (head structure + readonly D-10 pin block + `preflight-lib` ergonomics) | exact (composite — head from create-cluster.sh; body from register-poc-cluster.sh's `build_kubeconfig` heredoc; arg parsing similar to neither — see RESEARCH §A1) |
| `tests/bats/proxy-01-static-script.bats` (NEW) | static bats — script-shape contract with `grep -F --` literal asserts | static file-content assertion (no cluster) | `tests/bats/capsule-install-04-static-no-umbrella.bats` (mixed yq + `grep -F --` literal lints) AND `tests/bats/repo-hygiene-04-poc.bats` (literals iteration + presence asserts on script-like artifacts) | exact (script-shape literals + Phase 8 WR-01..04 hardened pattern) |
| `tests/bats/proxy-02-static-leak-defenses.bats` (NEW) | static bats — `.gitignore` + `.gitleaks.toml` regression-gate | static text-file presence + literal asserts | `tests/bats/repo-hygiene-04-poc.bats` (Phase 7 D-14 leak-defenses regression bats) | exact — same `.gitignore` + `.gitleaks.toml` setup, same allowlist + rule literal asserts; Phase 10 is a non-modifying re-grep of the Phase 7 D-14 globs/rule |
| `tests/bats/proxy-03-static-doc.bats` (NEW) | static bats — `docs/poc-capsule.md` H2 section + cross-link contract | static markdown-content assertion | `tests/bats/docs-06-eks.bats` (frontmatter + section + literal-iter content lints) AND `tests/bats/docs-05-runbook.bats` (`grep -nF` line-order assertions for doc structure) | exact (mirror docs-06-eks pattern: existence, h1 anchor, frontmatter status, literals iter, section heading match) |
| `tests/bats/proxy-04-live-issue.bats` (NEW) | live bats — script invocation + stdout YAML decode + JWT decode | request-response (script→stdout YAML→yq parse + JWT base64url decode) | `tests/bats/capsule-install-06-live-helm.bats` (cluster-info skip-gate + retry loop) AND `tests/bats/capsule-install-08-live-proxy-reachable.bats` (live curl probe) | role-match (live invocation + stdout-capture; novel JWT decode shape per RESEARCH §C4) |
| `tests/bats/proxy-05-live-list-filter.bats` (NEW) | live bats — proxy LIST + 403 falsifier | request-response (kubectl GET via two kubeconfigs — proxy positive + direct apiserver 403 negative) | `tests/bats/capsule-install-08-live-proxy-reachable.bats` (curl probe across NodePort) AND `tests/bats/tenants-07-live-impersonate.bats` (kubectl with `--as=` for negative-direction RBAC; not yet read but cited in RESEARCH) | partial (cluster-info gate + multi-context kubectl; corrected falsifier shape per Pitfall 10-P3) |
| `tests/bats/proxy-06-live-fixture.bats` (NEW) | live bats — `git check-ignore` + `gitleaks detect` synthetic fixture | event-driven (drop synthetic fixture → run gitleaks/git → cleanup) | `tests/bats/repo-hygiene-04-poc.bats` (gitleaks detect on positive + negative fixtures, exit-code asserts) | exact — same `gitleaks detect --no-banner --no-git --source <fixture> --config "$GITLEAKS_TOML"` shape, same exit-code assertions; Phase 10 adds repo-relative `git check-ignore` per Pitfall 10-P5 |
| `tests/bats/proxy-07-live-regression.bats` (NEW) | live bats — Phase 7 P31 + Phase 8 CAP-01..03 + ADR-004 + Phase 9 TEN-01..06 inheritance reruns | composite (multi-cluster, multi-context regression rerun) | `tests/bats/tenants-12-live-health-check.bats` (multi-cluster cluster-info gate + `task health-check` rerun + cross-cluster Ready=True assertions) | exact (regression-rerun shape — multi-cluster gate, sequential invariant assertions) |
| `docs/poc-capsule.md` (MODIFIED — APPEND) | runbook — Active-status H2 section append | document — Phase 7 frontmatter `scope:` line update + new "Tenant kubeconfig delivery contract" H2 | `docs/poc-capsule.md` itself (Phase 7 "Host restart recovery" H2 — same file, same structure, just an additional sibling H2 + frontmatter scope-line update) | exact (self-analog — same file, same heading depth, same `### Quickstart`/`### Contract` subsection style; cross-link section already established as a final H2 in Phase 7) |

## Pattern Assignments

### `scripts/poc/capsule/issue-tenant-kubeconfig.sh` (NEW — imperative bash, request-response)

**Primary analog:** `scripts/poc/capsule/create-cluster.sh` (head structure + ergonomics)
**Secondary analog:** `scripts/register-poc-cluster.sh` (kubeconfig heredoc body)
**Why both:** Phase 10 needs the *short-script head structure* of create-cluster.sh (P31-rooted, preflight-lib sourced, readonly D-10 pin block, fail-fast with hint) AND the *kubeconfig heredoc body* shape of register-poc-cluster.sh's `build_kubeconfig()` (D-10-07's exact YAML structure differs from register-poc-cluster only by server URL, user name, and added `namespace:` default).

**Head pattern — copy verbatim shape from `scripts/poc/capsule/create-cluster.sh` lines 1-29:**

```bash
#!/usr/bin/env bash
# scripts/poc/capsule/create-cluster.sh
# Creates the persistent spoke-capsule k3d cluster on k8s-net.
#
# REQ: CAPCLU-01.
# Idempotent: skip-if-exists with image/network/api-port/NodePort drift verify
# (mirrors create_cluster() in scripts/create-clusters.sh).
#
# IMPORTANT: This script is NEVER invoked by `task rebuild`. It lives under
# scripts/poc/capsule/ per D-12 / P31 isolation contract. The v0.18 scripts
# {create-clusters,register-spokes-for-flux,health-check,destroy,delete-clusters,rebuild}.sh
# MUST NOT reference spoke-capsule (tests/bats/poc-isolation-01-static.bats enforces).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# shellcheck source=../../lib/preflight-lib.sh
# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/lib/preflight-lib.sh"

# D-10 pins (LOCKED -- bats grep-asserts these literals):
readonly POC_CLUSTER="spoke-capsule"
readonly POC_API_PORT="6446"
readonly POC_NODEPORT="30443"
readonly K8S_NET_NAME="k8s-net"
readonly K3S_STOCK_IMAGE="rancher/k3s:v1.34.6-k3s1"
readonly EXPECTED_SAN="k3d-${POC_CLUSTER}-server-0"
```

**What to copy verbatim from create-cluster.sh head:**
- Lines 1, 14, 16-20: shebang, `set -euo pipefail`, `SCRIPT_DIR`/`REPO_ROOT` pinning, `source preflight-lib.sh`. **Identical token-by-token.**
- Lines 22-28: `readonly` D-10 pin block at top. Phase 10's pin block is per RESEARCH §A1 lines 305-310: `POC_CTX="k3d-spoke-capsule"`, `POC_NODEPORT="30443"`, `DEFAULT_DURATION="1h"`, `TMPDIR_DEFAULT="${TMPDIR:-/tmp}"`, `TENANT_TMPDIR="${TMPDIR_DEFAULT}/karyon-tenants"`.

**What to vary:**
- Head comment block (lines 2-12): Replace `CAPCLU-01` cite with `PROXY-01..03 + D-10-01 + D-10-03 + D-10-06 + P31 + ADR-004` per CONTEXT.md `<specifics>` "Script preamble cite anchor". Replace "Idempotent: skip-if-exists" rationale with "Idempotent: each invocation produces a fresh TokenRequest token (D-10-09 / Claude's Discretion)". Add stdout-vs-stderr contract sentence ("kubeconfig YAML on stdout; preflight-lib log lines on stderr — clean redirect contract").

**Body pattern — kubeconfig heredoc emit, copy verbatim shape from `scripts/register-poc-cluster.sh` lines 162-185 (`build_kubeconfig()`):**

```bash
build_kubeconfig() {
  local spoke="$1" bearer="$2" cert_part="$3"
  local server
  server="$(expected_server)"
  cat <<EOF
apiVersion: v1
kind: Config
clusters:
- name: ${spoke}
  cluster:
    server: ${server}
    certificate-authority-data: ${cert_part}
users:
- name: ${RECONCILER_SA}
  user:
    token: ${bearer}
contexts:
- name: ${spoke}
  context:
    cluster: ${spoke}
    user: ${RECONCILER_SA}
current-context: ${spoke}
EOF
}
```

**What to vary in the heredoc:**
- `server: ${server}` → `server: https://127.0.0.1:30443` (D-10-07 LITERAL — bats grep-asserts).
- Cluster `name: ${spoke}` → `name: capsule-proxy-127.0.0.1` (D-10-07).
- User `name: ${RECONCILER_SA}` → `name: ${OWNER}` (parameterized).
- Context `name: ${spoke}` → `name: tenant-${TENANT}-via-proxy` (D-10-07 LITERAL).
- Add `namespace: tenant-${TENANT}` line under context (D-10-07 default-namespace ergonomic).
- Replace `current-context: ${spoke}` → `current-context: tenant-${TENANT}-via-proxy`.
- Wrap in `section "Emit kubeconfig" >&2` and follow with `pass "..." >&2` per RESEARCH §C3 (stderr split — load-bearing per Pitfall 10-P7).

**Preflight pattern — copy verbatim shape from `scripts/poc/capsule/fix-dns.sh` lines 28-37:**

```bash
# ---------- Section 1: Tool gate ----------
section "Tool gate"
for cmd in k3d kubectl; do
  if ! have "$cmd"; then
    fail "required command missing: $cmd.
       Fix: install project tools with asdf, then rerun: bash scripts/poc/capsule/fix-dns.sh"
    exit 1
  fi
done
pass "required commands present"
```

**What to vary:**
- Tool list: `k3d kubectl` → `kubectl jq` (Phase 10 needs jq for JWT decode per RESEARCH §C4 NOT in script — but realpath also needs verifying per Pitfall 10-P4; lean: `kubectl jq realpath`).
- Hint: `bash scripts/poc/capsule/fix-dns.sh` → `bash scripts/poc/capsule/issue-tenant-kubeconfig.sh ${TENANT} ${OWNER}`.
- Sections after tool-gate (per D-10-04 ordering): (2) `kubectl config get-contexts k3d-spoke-capsule` exists, (3) Tenant CR exists on spoke (`kubectl get tenant <tenant>`), (4) SA exists in tenant ns (`kubectl get sa <owner> -n tenant-<tenant>`), (5) Mint TokenRequest, (6) Read CA cert, (7) Emit kubeconfig.

**Fail-fast pattern — copy verbatim shape from `scripts/poc/capsule/fix-dns.sh` lines 32-35:**

```bash
fail "required command missing: $cmd.
   Fix: install project tools with asdf, then rerun: bash scripts/poc/capsule/fix-dns.sh"
exit 1
```

**What to vary:** SA-not-found message per CONTEXT.md D-10-04:

```bash
fail "Owner '${OWNER}' SA not found in namespace tenant-${TENANT}.
     Available SAs in this tenant: $(kubectl --context=k3d-spoke-capsule -n tenant-${TENANT} get sa -o name | sed 's|serviceaccount/||g' | tr '\n' ',' | sed 's/,$//').
     Hint: run /gsd-execute-phase 9 first if Phase 9 has not landed yet,
           or pass a known SA name (currently only 'gitops-reconciler')." >&2
exit 1
```

Note the trailing `>&2` redirect — REQUIRED per Pitfall 10-P7 stdout/stderr split. The script may instead define **local override functions** (RESEARCH §Pitfall 10-P7 cleanest fix):

```bash
# Local override — preflight-lib log helpers MUST go to stderr (Pitfall 10-P7).
# Cleanest blast radius: override locally, leave create-cluster.sh + fix-dns.sh untouched.
section() { command section "$@" >&2; }
pass()    { command pass    "$@" >&2; }
info()    { command info    "$@" >&2; }
warn()    { command warn    "$@" >&2; }
fail()    { command fail    "$@" >&2; }
```

**TokenRequest call — copy verbatim from RESEARCH §C1:**

```bash
TOKEN=$(kubectl --context=k3d-spoke-capsule create token "${OWNER}" -n "tenant-${TENANT}" --duration="${DURATION}")
```

**Bats grep-asserts these EXACT literals** (per RESEARCH §C1):
- `kubectl --context=k3d-spoke-capsule`
- `create token`
- `-n "tenant-`
- `--duration=`

**CA cert read — copy verbatim from RESEARCH §C2 (corrected `tls.crt` path, NOT `ca.crt`):**

```bash
CA_B64=$(kubectl --context=k3d-spoke-capsule -n capsule-system \
    get secret capsule-proxy -o jsonpath='{.data.tls\.crt}')

if [[ -z "$CA_B64" ]]; then
  warn "capsule-proxy Secret tls.crt is empty (chart cert rotation in flight?). Retrying once after 5s..."
  sleep 5
  CA_B64=$(kubectl --context=k3d-spoke-capsule -n capsule-system \
      get secret capsule-proxy -o jsonpath='{.data.tls\.crt}')
fi
[[ -z "$CA_B64" ]] && { fail "capsule-proxy Secret tls.crt is empty after retry"; exit 1; }
```

**`--write-to` validation — copy verbatim from RESEARCH §C5:**

```bash
if [[ -n "$WRITE_TO" ]]; then
  RESOLVED=$(realpath -m "$WRITE_TO")
  TMPDIR_RESOLVED=$(realpath -m "${TENANT_TMPDIR}")
  if [[ "$RESOLVED" != "${TMPDIR_RESOLVED}/"* ]]; then
    fail "--write-to '${WRITE_TO}' is outside ${TENANT_TMPDIR}/.
       Hint: tenant kubeconfigs MUST live in tmpdir per Phase 10 PROXY-03 + Phase 7 P29 invariant.
       Try: --write-to ${TENANT_TMPDIR}/${TENANT}.kubeconfig"
    exit 1
  fi
  mkdir -p "$(dirname "$RESOLVED")"
fi
```

**Argument parsing — copy verbatim from RESEARCH §A1 lines 343-363:**

```bash
TENANT=""
OWNER=""
DURATION="${DEFAULT_DURATION}"
WRITE_TO=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --duration) DURATION="${2:?--duration requires a value}"; shift 2 ;;
    --write-to) WRITE_TO="${2:?--write-to requires a value}"; shift 2 ;;
    --help|-h)  usage 0 ;;
    --*)        fail "unknown flag: $1"; usage 1 ;;
    *)          if [[ -z "$TENANT" ]]; then TENANT="$1"; shift
                elif [[ -z "$OWNER" ]]; then OWNER="$1"; shift
                else fail "unexpected positional arg: $1"; usage 1
                fi ;;
  esac
done

[[ -z "$TENANT" ]] && { fail "missing positional <tenant>"; usage 1; }
[[ -z "$OWNER"  ]] && { fail "missing positional <owner>"; usage 1; }
```

**Anti-patterns explicitly avoided (RESEARCH §"Anti-Patterns to Avoid"):**
- NO `--mode direct` flag (footgun).
- NO `yq -n` to build kubeconfig (heredoc only).
- NO ca.crt jsonpath (the Secret has `tls.crt` only — Pitfall 10-P1).
- NO `insecure-skip-tls-verify: true` in issued kubeconfig (D-10-06; ships an anti-pattern).
- NO `task issue-tenant-kubeconfig` wrapper (Claude's Discretion default).
- NO base64url custom decoder (use `tr '_-' '/+'` substitution per RESEARCH §C4).
- NO file caching of CA cert (live-read at script-time per D-10-06).

---

### `tests/bats/proxy-01-static-script.bats` (NEW — static bats, file-content)

**Primary analog:** `tests/bats/capsule-install-04-static-no-umbrella.bats` (literal-iter `grep -F --` lints over a script-shaped artifact).
**Secondary analog:** `tests/bats/repo-hygiene-04-poc.bats` (existence + literal iteration block + per-literal `[ "$status" -eq 0 ]` pattern).

**Header + setup pattern — copy verbatim shape from `tests/bats/capsule-install-04-static-no-umbrella.bats` lines 1-13:**

```bash
#!/usr/bin/env bats
# tests/bats/capsule-install-04-static-no-umbrella.bats
# Phase 8 / Wave 0 (D-08-09 Nyquist gate)
# Anti-pattern lints — no umbrella `proxy.enabled: true`; no `wait:` field in dependsOn (Pitfall 9);
# no cert-manager (D-08-04); no Phase 9 scope creep (CapsuleConfiguration / Tenant CRs).
# Plans 08-01 and 08-02 land the yaml that turns these GREEN.

load 'test_helper'

setup() {
  OPERATOR_HR="${REPO_ROOT}/pocs/capsule/operator/helmrelease.yaml"
  PROXY_HR="${REPO_ROOT}/pocs/capsule/proxy/helmrelease.yaml"
}
```

**What to vary:**
- File header citation block: `Phase 8` → `Phase 10`, `D-08-09` → `D-10-09`, `CAP-01..03` → `PROXY-01..03`.
- `setup()`: replace yaml paths with `SCRIPT="${REPO_ROOT}/scripts/poc/capsule/issue-tenant-kubeconfig.sh"`.

**Literal-iter pattern — copy verbatim shape from `tests/bats/repo-hygiene-04-poc.bats` lines 14-19:**

```bash
@test "POC-03 / D-14: .gitignore includes tenant-kubeconfig globs" {
  [ -f "$GITIGNORE" ]
  for literal in 'karyon-tenants/' '*.tenant.kubeconfig' 'tenants/**/access.yaml' 'tenants/**/admin.yaml'; do
    run grep -F -- "$literal" "$GITIGNORE"
    [ "$status" -eq 0 ]
  done
}
```

**What to vary — Phase 10 literals to grep-assert in `issue-tenant-kubeconfig.sh`** (per CONTEXT.md D-10-09 + RESEARCH §"Phase Requirements → Test Map"):

```bash
# Bats grep-asserts these EXACT literals (per RESEARCH §C1 + D-10-07 + D-10-09):
# Block A: shebang + strict-mode + path pinning (per Phase 7 + Phase 8 inheritance)
'#!/usr/bin/env bash'
'set -euo pipefail'
'SCRIPT_DIR='
'REPO_ROOT='
'source "${REPO_ROOT}/scripts/lib/preflight-lib.sh"'

# Block B: head comment cite anchors (D-10-09 verbatim coverage)
'PROXY-01'
'D-10-01'
'D-10-03'
'D-10-06'
'P31'
'ADR-004'

# Block C: TokenRequest contract (RESEARCH §C1)
'kubectl --context=k3d-spoke-capsule'
'create token'
'-n "tenant-'
'--duration='

# Block D: kubeconfig literals (D-10-07)
'server: https://127.0.0.1:30443'
'certificate-authority-data:'
'current-context: tenant-${TENANT}-via-proxy'
'capsule-proxy-127.0.0.1'

# Block E: anti-patterns NOT present (negative-grep — exit non-zero)
# These use `[ "$status" -ne 0 ]`:
'insecure-skip-tls-verify'             # D-10-06 anti-pattern
'--mode direct'                        # D-10-08 anti-pattern
"'{.data.ca\\.crt}'"                   # Pitfall 10-P1 anti-pattern (NOT this jsonpath)
```

**Sample @test (PROXY-01 shebang + strict-mode):**

```bash
@test "PROXY-01 / D-10-09: script has #!/usr/bin/env bash + set -euo pipefail" {
  [ -f "$SCRIPT" ]
  run grep -F -- '#!/usr/bin/env bash' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- 'set -euo pipefail' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "PROXY-01 / D-10-09: script sources preflight-lib.sh" {
  [ -f "$SCRIPT" ]
  run grep -F -- 'source "${REPO_ROOT}/scripts/lib/preflight-lib.sh"' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "PROXY-01 / D-10-06: script has NO insecure-skip-tls-verify (anti-pattern lint)" {
  [ -f "$SCRIPT" ]
  run grep -F -- 'insecure-skip-tls-verify' "$SCRIPT"
  [ "$status" -ne 0 ]
}
```

---

### `tests/bats/proxy-02-static-leak-defenses.bats` (NEW — static bats, regression-gate)

**Primary analog:** `tests/bats/repo-hygiene-04-poc.bats` (Phase 7 D-14 `.gitignore` + `.gitleaks.toml` literal-iter regression gate).

**Why this analog:** Phase 10's PROXY-03 leak-defense static-bats is *literally a re-grep of the same Phase 7 D-14 globs and rule that repo-hygiene-04-poc.bats already asserts*. Phase 10 does NOT modify `.gitignore` or `.gitleaks.toml` per CONTEXT.md `<deferred>` "Anti-Patterns to Avoid" + `<code_context>`. The Phase 10 bats is a *defensive regression-gate*: it would FAIL if Phase 10 inadvertently mutated those files.

**Setup pattern — copy verbatim from `tests/bats/repo-hygiene-04-poc.bats` lines 7-12:**

```bash
setup() {
  GITIGNORE="${REPO_ROOT}/.gitignore"
  GITLEAKS_TOML="${REPO_ROOT}/.gitleaks.toml"
  POSITIVE_FIXTURE="${REPO_ROOT}/tests/fixtures/gitleaks/synthetic-kubeconfig.yaml"
  NEGATIVE_FIXTURE="${REPO_ROOT}/tests/fixtures/gitleaks/benign-configmap.yaml"
}
```

**Test pattern — copy verbatim from `tests/bats/repo-hygiene-04-poc.bats` lines 14-58 (test bodies 1-6):**

```bash
@test "POC-03 / D-14: .gitignore includes tenant-kubeconfig globs" {
  [ -f "$GITIGNORE" ]
  for literal in 'karyon-tenants/' '*.tenant.kubeconfig' 'tenants/**/access.yaml' 'tenants/**/admin.yaml'; do
    run grep -F -- "$literal" "$GITIGNORE"
    [ "$status" -eq 0 ]
  done
}

@test "POC-03 / D-14: .gitleaks.toml has kubeconfig-bearer-token positive rule" {
  [ -f "$GITLEAKS_TOML" ]
  run grep -F -- 'id = "kubeconfig-bearer-token"' "$GITLEAKS_TOML"
  [ "$status" -eq 0 ]
}

@test "POC-03 / D-14: .gitleaks.toml allowlists tests/fixtures/gitleaks/synthetic-kubeconfig.yaml by path" {
  [ -f "$GITLEAKS_TOML" ]
  run grep -F -- 'tests/fixtures/gitleaks/synthetic-kubeconfig' "$GITLEAKS_TOML"
  [ "$status" -eq 0 ]
}
```

**What to vary — minimal:**
- File header citation: `POC-03 / D-14` → `PROXY-03 / D-10-09 (Phase 7 D-14 inheritance)`.
- Description framing: emphasize "regression-gate" rather than "Phase-7 owns" — the test fails if Phase 10 inadvertently mutates these files. Add a comment block: `# This bats is a Phase 10 PROXY-03 regression-gate ONLY. Phase 7 D-14 already shipped these defenses; Phase 10 does NOT modify .gitignore or .gitleaks.toml. The bats fails if either file is mutated to drop a Phase 7 glob/rule/allowlist entry.`

---

### `tests/bats/proxy-03-static-doc.bats` (NEW — static bats, markdown shape)

**Primary analog:** `tests/bats/docs-06-eks.bats` (frontmatter + h1-anchor + literal-iter content lint pattern).
**Secondary analog:** `tests/bats/docs-05-runbook.bats` (line-order assertions for doc structure via `grep -nF` + `cut -d:`).

**Setup + h1 anchor pattern — copy verbatim from `tests/bats/docs-06-eks.bats` lines 7-19:**

```bash
setup() {
  DOC="${REPO_ROOT}/docs/capsule-on-eks.md"
}

@test "EKSDOC-01: docs/capsule-on-eks.md exists" {
  [ -f "$DOC" ]
}

@test "EKSDOC-01: doc starts with an h1 (MD041 safety) before any mermaid block" {
  [ -f "$DOC" ]
  run bash -c "h1_line=\$(grep -nE '^# ' '$DOC' | head -1 | cut -d: -f1); mermaid_line=\$(grep -nE '^\`\`\`mermaid' '$DOC' | head -1 | cut -d: -f1); [ -n \"\$h1_line\" ] && [ -n \"\$mermaid_line\" ] && [ \"\$h1_line\" -lt \"\$mermaid_line\" ]"
  [ "$status" -eq 0 ]
}
```

**What to vary:**
- `DOC` path: `docs/capsule-on-eks.md` → `docs/poc-capsule.md`.
- Drop the mermaid-block assertion (Phase 10's appended H2 has no mermaid).

**H2 section + literal-iter pattern — copy verbatim from `tests/bats/docs-06-eks.bats` lines 41-53:**

```bash
@test "EKSDOC-01 / D-02: section (d) contains the 3 verbatim YAML anchor literals (IRSA + LB + CapsuleConfiguration)" {
  [ -f "$DOC" ]
  for literal in \
    'sts:AssumeRoleWithWebIdentity' \
    'eks.amazonaws.com/role-arn' \
    'service.beta.kubernetes.io/aws-load-balancer-type' \
    'CapsuleConfiguration' \
    'allowedNodeSelectors'
  do
    run grep -F -- "$literal" "$DOC"
    [ "$status" -eq 0 ]
  done
}
```

**What to vary — Phase 10 PROXY-03 doc literals (per RESEARCH §A3):**

```bash
@test "PROXY-03 / D-10-09: docs/poc-capsule.md has 'Tenant kubeconfig delivery contract' H2 section" {
  [ -f "$DOC" ]
  run grep -F -- '## Tenant kubeconfig delivery contract' "$DOC"
  [ "$status" -eq 0 ]
}

@test "PROXY-03 / D-10-09: doc cross-links to capsule-on-eks.md (EKS-translation forward-pointer)" {
  [ -f "$DOC" ]
  for literal in \
    'capsule-on-eks.md' \
    'IRSA' \
    'TokenRequest' \
    'capsule-proxy' \
    'NodePort 30443' \
    'gitops-reconciler' \
    '${TMPDIR:-/tmp}/karyon-tenants/' \
    'kubeconfig-bearer-token'
  do
    run grep -F -- "$literal" "$DOC"
    [ "$status" -eq 0 ]
  done
}
```

**Frontmatter scope-line update assertion — copy adapt from `docs-06-eks.bats` line 22:**

```bash
@test "PROXY-03: doc frontmatter scope: line removes the Phase 10 forward-pointer (Phase 10 satisfied)" {
  [ -f "$DOC" ]
  # The Phase 7-shipped scope line said 'Phases 10/11 will add ...'; after Phase 10 lands,
  # the scope line should say only 'Phase 11 will add ordered teardown procedure' (Phase 10 forward-pointer removed).
  run grep -F -- 'tenant kubeconfig delivery contract' "$DOC"
  [ "$status" -eq 0 ]
  # negative: no longer contains the forward-pointer phrasing
  run grep -F -- 'Phases 10/11 will add' "$DOC"
  [ "$status" -ne 0 ]
}
```

---

### `tests/bats/proxy-04-live-issue.bats` (NEW — live bats, script invocation + JWT decode)

**Primary analog:** `tests/bats/capsule-install-06-live-helm.bats` (cluster-info skip-gate + retry loop).
**Secondary analog:** `tests/bats/capsule-install-08-live-proxy-reachable.bats` (live curl probe shape).

**Setup pattern — copy verbatim from `tests/bats/capsule-install-08-live-proxy-reachable.bats` lines 12-16:**

```bash
setup() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
}
```

**What to vary:** None — cluster-info gate is identical (Phase 10 inherits Phase 8 D-08-09 `cluster-info` gate, NOT `KARYON_LIVE_TESTS` env-var; cited in RESEARCH §"Pattern A4: Wave 0 RED bats scaffold").

**Test pattern — script-invocation + stdout YAML decode (novel; no exact analog — pull from RESEARCH §A2 + §C4):**

```bash
@test "PROXY-01 live (D-10-09): script issues kubeconfig with stdout YAML + JWT decode (exp-iat ≈ 1h)" {
  ISSUED_KC=$(mktemp -p "${TMPDIR:-/tmp}" karyon-proxy-issued-XXXX.kubeconfig)
  bash "${REPO_ROOT}/scripts/poc/capsule/issue-tenant-kubeconfig.sh" alpha gitops-reconciler 2>/dev/null > "$ISSUED_KC"

  # Stdout YAML is parseable (kubeconfig contract — clean redirect via 2>/dev/null per Pitfall 10-P7)
  run yq eval '.kind' "$ISSUED_KC"
  [ "$status" -eq 0 ]
  [ "$output" = "Config" ]

  # current-context literal (D-10-07)
  run yq eval '.current-context' "$ISSUED_KC"
  [ "$output" = "tenant-alpha-via-proxy" ]

  # JWT decode (RESEARCH §C4) — exp - iat ≈ 3600s (1h ±60s for clock skew)
  TOKEN=$(yq eval '.users[0].user.token' "$ISSUED_KC")
  PAYLOAD=$(echo "$TOKEN" | cut -d. -f2)
  case $((${#PAYLOAD} % 4)) in
    2) PAYLOAD="${PAYLOAD}==" ;;
    3) PAYLOAD="${PAYLOAD}=" ;;
  esac
  DECODED=$(echo "$PAYLOAD" | tr '_-' '/+' | base64 -d 2>/dev/null)
  EXP=$(echo "$DECODED" | jq -r '.exp')
  IAT=$(echo "$DECODED" | jq -r '.iat')
  [ "$((EXP - IAT))" -ge 3540 ]   # ±60s tolerance
  [ "$((EXP - IAT))" -le 3660 ]
  SUB=$(echo "$DECODED" | jq -r '.sub')
  [ "$SUB" = "system:serviceaccount:tenant-alpha:gitops-reconciler" ]
}

teardown() {
  rm -f "${ISSUED_KC:-}" 2>/dev/null || true
}
```

**`--write-to` validation @test (per CONTEXT.md D-10-09 + RESEARCH §C5):**

```bash
@test "PROXY-01 live: --write-to inside tmpdir succeeds + outside tmpdir rejected exit 1" {
  WRITE_PATH="${TMPDIR:-/tmp}/karyon-tenants/proxy-04-test.kubeconfig"
  bash "${REPO_ROOT}/scripts/poc/capsule/issue-tenant-kubeconfig.sh" alpha gitops-reconciler --write-to "$WRITE_PATH" >/dev/null 2>&1
  [ -f "$WRITE_PATH" ]
  rm -f "$WRITE_PATH"

  # Negative: outside tmpdir rejected
  run bash "${REPO_ROOT}/scripts/poc/capsule/issue-tenant-kubeconfig.sh" alpha gitops-reconciler --write-to /etc/passwd
  [ "$status" -ne 0 ]
}
```

---

### `tests/bats/proxy-05-live-list-filter.bats` (NEW — live bats, proxy LIST + 403 falsifier)

**Primary analog:** `tests/bats/capsule-install-08-live-proxy-reachable.bats` (cluster-info gate + curl probe).

**Test pattern — copy verbatim FALSIFIER from RESEARCH §A2 (corrected per Pitfall 10-P3):**

The pattern is verbatim in RESEARCH §A2 lines 376-433 — already a complete bats @test. Plan should reference `10-RESEARCH.md §A2` directly. **What to vary:** None — the pattern is fully resolved.

**Key shape elements (for verifier review):**
- `setup()` cluster-info gate (Phase 8 D-08-09 inheritance).
- `@test` invokes the issued kubeconfig path script + extracts token via `yq eval '.users[0].user.token'`.
- Constructs direct-apiserver kubeconfig via `cat <<EOF` heredoc (mirrors RESEARCH §A2).
- Proxy LIST: positive (alpha-app1, tenant-alpha) + negative (NOT tenant-bravo, kube-system, flux-system, capsule-system) — `grep -qF` per literal.
- Direct apiserver: 403 Forbidden + `cannot list resource "namespaces"` error message — qualitative not quantitative (Pitfall 10-P3).
- `teardown()` removes both kubeconfig files.

**CRITICAL: Pitfall 10-P6 deferral signal.** Per CONTEXT.md `<deferred>` Pitfall 10-P6: capsule-proxy is NOT yet installed on spoke (D-08-13 push-gate deferred). Plan 10-02 verifier MUST use suspend+apply (Phase 9 Plan 09-04 precedent) to validate this bats locally. Document override in 10-VERIFICATION.md as `passed_with_overrides`.

---

### `tests/bats/proxy-06-live-fixture.bats` (NEW — live bats, gitleaks + git check-ignore)

**Primary analog:** `tests/bats/repo-hygiene-04-poc.bats` (gitleaks detect on positive + negative fixtures).

**`gitleaks detect` pattern — copy verbatim from `tests/bats/repo-hygiene-04-poc.bats` lines 84-96:**

```bash
@test "POC-03 (live): gitleaks fires on positive fixture (catches kubeconfig + bearer token)" {
  [ -f "$POSITIVE_FIXTURE" ]
  [ -f "$GITLEAKS_TOML" ]
  run gitleaks detect --no-banner --no-git --source "$POSITIVE_FIXTURE" --config "$GITLEAKS_TOML" --redact --verbose
  [ "$status" -ne 0 ]
}
```

**What to vary — Phase 10 adds two new behaviors:**
1. **`git check-ignore` for tmpdir glob** — copy from RESEARCH §C6 lines 790-803 (with the Pitfall 10-P5 fix: path MUST be repo-relative, NOT absolute):

```bash
@test "PROXY-03 leak defense: gitignore catches karyon-tenants/ glob (D-14 inheritance)" {
  cd "$REPO_ROOT"
  mkdir -p karyon-tenants
  : > karyon-tenants/test.kubeconfig
  run git check-ignore -v karyon-tenants/test.kubeconfig
  [ "$status" -eq 0 ]
}

teardown() {
  rm -rf "${REPO_ROOT}/karyon-tenants" 2>/dev/null || true
}
```

2. **gitleaks fires on NEW (not allowlisted) tenant-shaped fixture** — adapt repo-hygiene-04-poc.bats's positive-fixture test, but drop a temporary fixture at a path NOT in the allowlist (per CONTEXT.md D-10-09 / RESEARCH §"Phase Requirements → Test Map"):

```bash
@test "PROXY-03 leak defense: gitleaks fires on tenant-shaped fixture NOT in allowlist" {
  TEMP_FIXTURE="${REPO_ROOT}/tests/fixtures/gitleaks/temp-tenant-fixture-XXXX.yaml"
  cat > "$TEMP_FIXTURE" <<EOF
apiVersion: v1
kind: Config
users:
  - name: tenant-test
    user:
      token: ZXhhbXBsZS1pbmVydC10b2tlbi12MC4xOS1zeW50aGV0aWMtZml4dHVyZQ
EOF
  run gitleaks detect --no-banner --no-git --source "$TEMP_FIXTURE" --config "${REPO_ROOT}/.gitleaks.toml" --redact --verbose
  [ "$status" -ne 0 ]
  rm -f "$TEMP_FIXTURE"
}
```

---

### `tests/bats/proxy-07-live-regression.bats` (NEW — live bats, multi-cluster regression-rerun)

**Primary analog:** `tests/bats/tenants-12-live-health-check.bats` (multi-cluster cluster-info gate + sequential invariant assertions).

**Setup pattern — copy verbatim from `tests/bats/tenants-12-live-health-check.bats` lines 17-29:**

```bash
load 'test_helper'

setup() {
  if ! kubectl --context=k3d-hub-flux cluster-info >/dev/null 2>&1; then
    skip "k3d-hub-flux cluster not reachable; skipping live bats"
  fi
  if ! kubectl --context=k3d-spoke-apps cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-apps cluster not reachable; skipping live bats"
  fi
  if ! kubectl --context=k3d-spoke-ml cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-ml cluster not reachable; skipping live bats"
  fi
}
```

**What to vary — add k3d-spoke-capsule context check** (Phase 10 inherits Phase 7 P31 + Phase 8 + Phase 9 invariants which span ALL FOUR clusters):

```bash
setup() {
  for ctx in k3d-hub-flux k3d-spoke-apps k3d-spoke-ml k3d-spoke-capsule; do
    if ! kubectl --context="$ctx" cluster-info >/dev/null 2>&1; then
      skip "${ctx} cluster not reachable; skipping live regression"
    fi
  done
}
```

**Test pattern — sequential invariant rerun. Copy shape from `tests/bats/tenants-12-live-health-check.bats` lines 31-46:**

```bash
@test "v0.18 regression: task health-check exits 0 (D-09-09 + RESEARCH Gap 11 belt-and-suspenders)" {
  run bash -c "cd '${REPO_ROOT}' && task health-check"
  [ "$status" -eq 0 ]
}

@test "RESEARCH Gap 11: spoke-apps Kustomization Ready=True (cross-cluster lockdown impact regression)" {
  local ready
  ready=$(kubectl --context=k3d-hub-flux -n flux-system get kustomization spoke-apps -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
  [[ "$ready" == "True" ]]
}
```

**What to vary — Phase 10 cross-phase rerun assertions** (per CONTEXT.md D-10-09 "Live (Wave 1+) — Phase 8 + 9 invariant preservation"):

```bash
# Phase 7 P31 — v0.18 health-check regression (the v0.18 baseline still works)
@test "Phase 7 P31 inheritance: task health-check exits 0 (v0.18 baseline)" {
  run bash -c "cd '${REPO_ROOT}' && task health-check"
  [ "$status" -eq 0 ]
}

# Phase 8 CAP-01 invariant — capsule HelmRelease Ready=True
@test "Phase 8 CAP-01 inheritance: HelmRelease capsule Ready=True on hub-flux" {
  local ready
  ready=$(kubectl --context=k3d-hub-flux -n capsule-system get helmrelease capsule -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
  [[ "$ready" == "True" ]]
}

# ADR-004 invariant — no Flux on spoke-capsule
@test "ADR-004 inheritance: spoke-capsule flux-system has zero Flux controllers (NotFound or empty)" {
  ns_check=$(kubectl --context=k3d-spoke-capsule get ns flux-system -o jsonpath='{.status.phase}' 2>&1 || true)
  if echo "$ns_check" | grep -qF 'NotFound'; then return 0; fi
  pod_count=$(kubectl --context=k3d-spoke-capsule get pods -n flux-system --no-headers 2>/dev/null | wc -l)
  [[ "$pod_count" -eq 0 ]]
}

# Phase 9 TEN-01 invariant — Tenant CRs alpha+bravo Active
@test "Phase 9 TEN-01 inheritance: kubectl get tenant alpha + bravo both report forceTenantPrefix=true" {
  local ftp_alpha ftp_bravo
  ftp_alpha=$(kubectl --context=k3d-spoke-capsule get tenant alpha -o jsonpath='{.spec.forceTenantPrefix}' 2>/dev/null || true)
  ftp_bravo=$(kubectl --context=k3d-spoke-capsule get tenant bravo -o jsonpath='{.spec.forceTenantPrefix}' 2>/dev/null || true)
  [[ "$ftp_alpha" == "true" ]]
  [[ "$ftp_bravo" == "true" ]]
}
```

**Note:** Per CONTEXT.md D-10-09 the planner may instead invoke prior bats files directly via `bats tests/bats/poc-isolation-01-static.bats` etc. inside the verifier (Plan 10-02), rather than re-grepping all the assertions. Either pattern is sufficient. The bats analog here exists in case the planner chooses inline assertions.

---

### `docs/poc-capsule.md` (MODIFIED — APPEND new H2 section)

**Self-analog:** The same file's existing "Host restart recovery" H2 (Phase 7-shipped) provides the heading-depth + subsection structure for Phase 10's append.

**Existing structure (Phase 7-shipped) — reference from `docs/poc-capsule.md` lines 25-77:**

```markdown
## Host restart recovery

After a Docker daemon restart or a WSL2 resume, k3d clusters can carry stale CoreDNS NodeHosts entries. ...

### Quickstart

```
task fix-dns-poc-capsule
```

### What to expect

```text
== Tool gate ==
  ok  required commands present
...
```

### How to verify

After the task completes:
...

### Distinct from `task fix-dns`

`task fix-dns` (which calls `scripts/fix-coredns.sh`) handles **hub-flux only** -- it is the v0.18 default. ...
```

**What to copy verbatim:** H2 + ### subsection depth pattern (`### Quickstart`, `### Contract`, `### Mandatory invariants`, `### Cross-references` per RESEARCH §A3).

**What to vary — Phase 10 H2 body — copy verbatim from RESEARCH §A3 lines 442-485** (already fully resolved with markdown structure):

The full H2 section is already in RESEARCH §A3 — Phase 10 plan should reference `10-RESEARCH.md §A3 (Pattern A3)` directly. The pattern includes:
- Status badge: `> **Status:** Active. Phase 10 — PROXY-01..03.`
- `### Quickstart` (with bash example)
- `### Contract` (markdown table — Output channel default, Optional file output, Server URL, Authentication, TLS trust, Default namespace)
- `### Mandatory invariants (P29 — leak defense)` (5-item ordered list)
- `### Cross-references` (4-item bullet list cross-linking Phase 7 D-14, Phase 8 CAP-02, Phase 9 D-09-02, capsule-on-eks.md)

**Frontmatter scope-line update:**

Existing line 5 (Phase 7-shipped):
```yaml
scope: Phase 7 ships only the Host restart recovery section. Phases 10/11 will add tenant kubeconfig delivery contract and ordered teardown procedure respectively.
```

After Phase 10 lands:
```yaml
scope: Phase 7 ships the Host restart recovery section. Phase 10 added tenant kubeconfig delivery contract. Phase 11 will add ordered teardown procedure.
```

---

## Shared Patterns

### Bash strict-mode + path pinning (REQUIRED for all `scripts/poc/capsule/` scripts)
**Source:** `scripts/poc/capsule/create-cluster.sh` lines 14-20
**Apply to:** `scripts/poc/capsule/issue-tenant-kubeconfig.sh` (PRIMARY)

```bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# shellcheck source=../../lib/preflight-lib.sh
# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/lib/preflight-lib.sh"
```

**Verbatim — no variation.** Bats grep-asserts via `proxy-01-static-script.bats`.

### Cluster-info live-bats skip-gate (REQUIRED for all live bats)
**Source:** `tests/bats/capsule-install-08-live-proxy-reachable.bats` lines 12-16 + `tests/bats/capsule-install-09-live-adr-004.bats` lines 10-13
**Apply to:** `proxy-04-live-issue.bats`, `proxy-05-live-list-filter.bats`, `proxy-06-live-fixture.bats`, `proxy-07-live-regression.bats`

```bash
setup() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
}
```

**Variation:** `proxy-07-live-regression.bats` adds k3d-hub-flux + k3d-spoke-apps + k3d-spoke-ml gates per the multi-cluster regression rerun (mirror `tenants-12-live-health-check.bats`).

**NOT `KARYON_LIVE_TESTS` env var** — Phase 8 D-08-09 inherited the cluster-info gate, Phase 10 inherits the inheritance (RESEARCH §"Anti-Patterns to Avoid").

### Multi-line `fail` with `Hint:` ergonomics (REQUIRED for all script preflight failures)
**Source:** `scripts/poc/capsule/fix-dns.sh` lines 32-35; `scripts/poc/capsule/create-cluster.sh` lines 33-36; `scripts/register-poc-cluster.sh` lines 72-75 + 313-314 + 376-378
**Apply to:** `scripts/poc/capsule/issue-tenant-kubeconfig.sh` (PRIMARY)

Pattern shape:
```bash
fail "<terse statement of what went wrong>.
   Inspect: <command to diagnose>     # optional
   Fix:     <command to recover>"
```

Phase 10 SA-not-found `fail` body per D-10-04 (multi-line, with `Available SAs in this tenant: ...` enumeration + `Hint:` line). All `fail` calls in Phase 10's script MUST be wrapped with `>&2` redirect (Pitfall 10-P7) — OR use the local-override pattern (RESEARCH §C7).

### Bats literal-iter `grep -F --` lint
**Source:** `tests/bats/repo-hygiene-04-poc.bats` lines 14-19; `tests/bats/docs-06-eks.bats` lines 41-53; `tests/bats/capsule-install-04-static-no-umbrella.bats` lines 60-69
**Apply to:** `proxy-01-static-script.bats`, `proxy-02-static-leak-defenses.bats`, `proxy-03-static-doc.bats`

Pattern shape:
```bash
[ -f "$TARGET_FILE" ]
for literal in 'literal-1' 'literal-2' 'literal-3'; do
  run grep -F -- "$literal" "$TARGET_FILE"
  [ "$status" -eq 0 ]
done
```

**`-F --` flag combo is LOAD-BEARING** — `-F` disables regex (treats `$literal` as plain string); `--` ends grep options (allows literals starting with `-`). Phase 8 WR-01..04 hardening pattern.

### Test_helper.bash load (REQUIRED for all bats)
**Source:** `tests/bats/test_helper.bash` lines 22-25 (defines `REPO_ROOT`); EVERY bats file's first non-comment line.
**Apply to:** ALL Phase 10 bats files

```bash
load 'test_helper'
```

`REPO_ROOT` is exported by `test_helper.bash`; bats files DO NOT redefine it. Phase 10 inherits.

### Heredoc-based kubeconfig emission (NOT yq-build)
**Source:** `scripts/register-poc-cluster.sh` lines 162-185 (`build_kubeconfig()`)
**Apply to:** `scripts/poc/capsule/issue-tenant-kubeconfig.sh`

Heredoc keeps the script's preflight surface minimal (no yq dependency for build); structure parallel to register-poc-cluster.sh's existing build_kubeconfig with parameter substitution. Phase 10 anti-pattern explicitly avoided: `yq -n` build (RESEARCH §"Anti-Patterns to Avoid").

### `mktemp -p "${TMPDIR:-/tmp}"` for ephemeral bats artifacts
**Source:** `scripts/register-poc-cluster.sh` line 335 (`cert_tmp="$(mktemp -t "karyon-${spoke}-apiserver-ca.XXXXXX.pem")"`); RESEARCH §A2 line 386
**Apply to:** `proxy-04-live-issue.bats`, `proxy-05-live-list-filter.bats`

Pattern: `mktemp -p "${TMPDIR:-/tmp}" karyon-proxy-XXXX.kubeconfig` followed by `rm -f` in `teardown()`. NEVER `/tmp/${RANDOM}` (race + perm issues per RESEARCH §"Don't Hand-Roll").

### Read-only files (Phase 10 does NOT modify)
**Apply to:** Plan-side validation — Phase 10 reads but does NOT mutate:
- `pocs/capsule/spoke/tenants/{alpha,bravo}/sa.yaml` — Phase 9 D-09-02 SA. Phase 10 reads SA name (`gitops-reconciler`) for D-10-03 owner validation.
- `pocs/capsule/spoke/tenants/{alpha,bravo}/tenant.yaml` — Phase 9 D-09-02 Tenant CR. Phase 10 verifies Tenant exists via `kubectl get tenant <tenant>`.
- `pocs/capsule/tenants/{alpha,bravo}.yaml` — Phase 9 D-09-03 transitional inner Ks. Phase 10 D-10-05 explicitly DEFERS the kubeConfig swap; these files remain unchanged.
- `clusters/hub-flux/pocs/capsule.yaml` + `clusters/hub-flux/pocs/capsule-spoke.yaml` — Phase 8 D-08-12 split-path outer Ks. Phase 10 does NOT modify; `tests/bats/tenants-05-static-split-path.bats` regression-gates verbatim during Plan 10-02 verifier.
- `.gitignore` — Phase 7 D-14 globs are sufficient; Phase 10 does NOT extend.
- `.gitleaks.toml` — Phase 7 D-14 rule + allowlist sufficient; Phase 10 does NOT extend.
- `Taskfile.yml` — Per Claude's Discretion default of "no new task targets," Phase 10 does NOT extend.

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| (none) | — | — | All Phase 10 files have in-repo analogs (100% coverage). |

## Metadata

**Analog search scope:**
- `scripts/poc/capsule/` (2 scripts) → ALL READ
- `scripts/lib/preflight-lib.sh` → READ
- `scripts/register-poc-cluster.sh` (multi-cluster kubeconfig analog) → READ
- `tests/bats/` (60+ bats files) → 8 read directly (test_helper.bash, poc-isolation-01-static, capsule-install-{01,04,06,08,09}-*, repo-hygiene-04-poc, tenants-{01,05,06,12}-*, docs-{05,06}-*)
- `tests/fixtures/gitleaks/` → INSPECTED
- `docs/poc-capsule.md` → FULL READ (Phase 7-shipped + Phase 10 append target)
- `pocs/capsule/spoke/tenants/alpha/{sa,tenant}.yaml` → READ (read-only refs only)
- `.gitignore` + `.gitleaks.toml` → INSPECTED (regression-gate refs)

**Files scanned (Read invocations):** 14
**Pattern extraction date:** 2026-05-05
**Decisions referenced:** D-10-01 through D-10-10 (CONTEXT.md); RESEARCH §A1..A4, §C1..C6, Pitfalls 10-P1..P7
