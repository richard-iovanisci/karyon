# Phase 4: Spoke Registration - Pattern Map

**Mapped:** 2026-04-27
**Files analyzed:** 14 (12 created + 2 modified, plus 1 doc-stub-fill)
**Analogs found:** 14 / 14

## File Classification

| New / Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---------------------|------|-----------|----------------|---------------|
| `scripts/register-spokes-for-flux.sh` | orchestration script (mutates 3 apiservers + local checkout; helper-driven) | imperative request-response (delegates to `scripts/preflight.sh`; drives `kubectl` against k3d-spoke-ml, k3d-spoke-apps, and k3d-hub-flux; writes local YAML; in-pod probe via `kubectl exec`) | `scripts/bootstrap-flux.sh` (primary) + `scripts/create-clusters.sh` (helper shape) | exact (3-part-AND idempotency, kubectl-context gate, sentinel-guarded patch, preflight delegation, no `set -x`, no token funnels) |
| `clusters/hub-flux/spokes/kustomization.yaml` | kustomize index (kustomize.config.k8s.io/v1beta1) | declarative file artifact (committed); read by Flux kustomize-controller | `clusters/hub-flux/flux-system/kustomization.yaml` lines 14-18 | exact (resources-list pattern; 4-line idiom) |
| `clusters/hub-flux/spokes/spoke-ml.yaml` | Flux v1 Kustomization CRD per spoke (kustomize.toolkit.fluxcd.io/v1) | declarative file artifact; consumed by hub kustomize-controller; reads `<spoke>-kubeconfig` Secret | `clusters/hub-flux/flux-system/gotk-sync.yaml` lines 16-27 (Flux v1 Kustomization shape) + RESEARCH.md §Example 5 | exact (apiVersion/kind/metadata/spec.{interval,path,prune,sourceRef} verbatim; spec.kubeConfig.secretRef new) |
| `clusters/hub-flux/spokes/spoke-apps.yaml` | Flux v1 Kustomization CRD per spoke | (same as spoke-ml.yaml) | (same as spoke-ml.yaml) | exact (mirror with `spoke-apps` substituted) |
| `clusters/spoke-ml/kustomization.yaml` | kustomize index (kustomize.config.k8s.io/v1beta1) | declarative file artifact; read by hub kustomize-controller via `spec.kubeConfig` → applied on spoke-ml | `clusters/hub-flux/flux-system/kustomization.yaml` lines 14-18 (resources-list pattern) | exact (resources-list pattern; differs only in resource names) |
| `clusters/spoke-ml/namespace.yaml` | core/v1 Namespace manifest | declarative file artifact; reconciled to spoke-ml as `karyon-spoke-ml` | RESEARCH.md §Example 6 (live-verified template) | role-match (no existing core/v1 Namespace YAML in repo yet — Phase 4 is first) |
| `clusters/spoke-ml/configmap.yaml` | core/v1 ConfigMap manifest | declarative file artifact; reconciled to spoke-ml; provides falsifier `data.spoke=spoke-ml` | RESEARCH.md §Example 6 (live-verified template) | role-match (no existing core/v1 ConfigMap YAML in repo yet — Phase 4 is first) |
| `clusters/spoke-apps/kustomization.yaml` | kustomize index | (same as spoke-ml/kustomization.yaml) | (same) | exact (mirror) |
| `clusters/spoke-apps/namespace.yaml` | core/v1 Namespace manifest | declarative; reconciled to spoke-apps as `karyon-spoke-apps` | (same as spoke-ml) | role-match |
| `clusters/spoke-apps/configmap.yaml` | core/v1 ConfigMap manifest | declarative; falsifier `data.spoke=spoke-apps` | (same as spoke-ml) | role-match |
| `tests/bats/register-spokes-01-static.bats` | static-grep bats suite (no live gates) | pure grep against committed files (script + Kustomization YAMLs + doc) | `tests/bats/bootstrap-flux-01-idempotent.bats` lines 27-93 (static @tests block) + `tests/bats/bootstrap-flux-02-docs.bats` (pure-static analog) | exact (token-funnel negative grep, sentinel grep, set-x ban, hard-coded literal pinning) |
| `tests/bats/register-spokes-02-live.bats` | destructive live-gated bats suite | shell-out to script + `kubectl --context k3d-hub-flux` + `kubectl --context k3d-spoke-ml/-apps`; in-pod wget probe; jq parse | `tests/bats/bootstrap-flux-01-idempotent.bats` lines 95-126 (live-destructive `require_live_destructive` block) + RESEARCH.md §Example 8 | exact (require_live_destructive double-gate, runs script, asserts cluster state via kubectl) |
| `clusters/hub-flux/flux-system/kustomization.yaml` (modify) | kustomize index — Phase 3 D-13 patch surface | file-I/O (idempotent insert via grep-sentinel + awk to temp + mv); already carries `# FLUX PATCH SURFACE` | `scripts/bootstrap-flux.sh` lines 319-343 (sentinel-guarded prepend pattern; Phase 4 reuses with NEW sentinel `# KARYON SPOKES MOUNT` and `awk`-insert under `resources:`) | role-match (same idiom; new sentinel + insert-not-prepend) |
| `Taskfile.yml` (append) | task-runner config (YAML) | declarative — single new task entry | `Taskfile.yml` lines 19-22 (`bootstrap-flux` task) — in-file self-analog | exact (4-line task pattern: name + desc + cmds[bash scripts/...]) |
| `docs/flux-hub-spoke.md` (fill stub) | contract doc — fills `<!-- Phase 4: hub-spoke reconciliation -->` stub at EOF (line 126) | static markdown | `docs/flux-hub-spoke.md` Rules 1/2/3 sections (lines 52-115) — in-file self-analog | exact (rule-prose + tables + fenced code blocks; medium depth per CONTEXT.md Claude's Discretion) |

---

## Pattern Assignments

### `scripts/register-spokes-for-flux.sh` (orchestration script, imperative request-response)

**Analogs:**
- **Primary:** `scripts/bootstrap-flux.sh` (entire shape: header → preflight → context gate → 3-part-AND idempotency → mutation → verification → patch surface → summary)
- **Helper-shape:** `scripts/create-clusters.sh` `create_cluster()` function (mirrored as `register_spoke <name>`)
- **Bounded retry:** `scripts/create-clusters.sh` lines 149-170 (10×Ns retry loop with `fail` + remediation)
- **Single-responsibility script length:** `scripts/delete-clusters.sh` (per-item loop pattern)

#### Pattern A1: Shebang + strict-mode + lib-source + REPO_ROOT resolution

**Source:** `scripts/bootstrap-flux.sh` lines 1-33

```bash
#!/usr/bin/env bash
# scripts/bootstrap-flux.sh
# Runs `flux bootstrap github` on k3d-hub-flux with --path locked to
# clusters/hub-flux (REQ-FLUX-02 — effectively immutable after first run).
# Sources GITHUB_OWNER / GITHUB_REPO / GITHUB_TOKEN from the gitignored .env
# (REQ-FLUX-03). The token is never echoed to stdout.
#
# Requirements satisfied: FLUX-01, FLUX-02, FLUX-03, FLUX-04
# Decisions honored:      D-01..D-16
#
# D-11 token-safety: set -euo pipefail INTENTIONALLY omits -x (no trace of
# GITHUB_TOKEN on stdout/stderr; strict-mode only, no debug tracing).
# ...

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/preflight-lib.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/preflight-lib.sh"
```

**Phase 4 adaptation:** Header comment uses CONTEXT.md §specifics top-of-file template (REQ-IDs SPOKE-01..06, decisions D-01..D-16, D-11 token-safety reframed for bearer tokens vs GITHUB_TOKEN). Drop `load_env_key`/`load_github_env` entirely — Phase 4 reads ZERO `.env` keys (RESEARCH.md "Runtime State Inventory" row "Secrets/env vars" → None).

#### Pattern A2: Constants block (readonly + per-spoke-aware)

**Source:** `scripts/bootstrap-flux.sh` lines 35-40 + `scripts/create-clusters.sh` lines 25-31

```bash
# Constants — --path is hard-coded per FLUX-02 / D-decisions; do NOT parameterize.
readonly FLUX_PATH="clusters/hub-flux"
readonly KUBE_CTX="k3d-hub-flux"
readonly FLUX_NS="flux-system"
readonly KUST_FILE="${REPO_ROOT}/${FLUX_PATH}/${FLUX_NS}/kustomization.yaml"
```

**Phase 4 adaptation:**
```bash
readonly HUB_CTX="k3d-hub-flux"
readonly FLUX_NS="flux-system"
readonly HUB_KUST_FILE="${REPO_ROOT}/clusters/hub-flux/flux-system/kustomization.yaml"
readonly SPOKES_DIR="${REPO_ROOT}/clusters/hub-flux/spokes"
readonly SPOKES_SENTINEL="# KARYON SPOKES MOUNT"
readonly TOKEN_WAIT_SECONDS=10              # D-11
readonly EXPECTED_FORBIDDEN_NODE="k3d-hub-flux-server-0"  # P18 negative-proof
# Per-spoke values are positional helper args (D-01).
```

#### Pattern A3: Section 1 — Preflight gate (D-05 inheritance)

**Source:** `scripts/bootstrap-flux.sh` lines 127-141

```bash
# ---------- Section 1: Preflight gate + gitleaks advisory (D-05, Phase-6 hand-off) ----------
section "Preflight gate"
PREFLIGHT_LOG="$(mktemp -t karyon-preflight.XXXXXX.log)"
if ! bash "${SCRIPT_DIR}/preflight.sh" > "${PREFLIGHT_LOG}" 2>&1; then
  fail "preflight has blockers — run scripts/preflight.sh and fix before bootstrapping flux.
     Log: ${PREFLIGHT_LOG}"
  exit 1
fi
pass "preflight green"
rm -f "${PREFLIGHT_LOG}"
```

**Phase 4 adaptation:** identical except message swap (`bootstrapping flux` → `registering spokes for flux`). Drop the `Gitleaks pre-commit advisory` section (Phase 6 owns it canonically; CONTEXT.md §domain "Out of scope" line 27 — Phase 4 may retain warn-only IF `bash scripts/bootstrap-flux.sh` still runs it; otherwise omit to keep Phase 4 single-purpose).

#### Pattern A4: kubectl context gate (D-06 verbatim, NEVER auto-switch)

**Source:** `scripts/bootstrap-flux.sh` lines 156-166

```bash
# ---------- Section 2: Context + idempotency checks (D-06, D-07) ----------
section "Context + idempotency checks"

# D-06: kubectl context gate — read-only assertion; NEVER auto-switch.
ctx="$(kubectl config current-context 2>/dev/null || true)"
if [[ "${ctx}" != "${KUBE_CTX}" ]]; then
  fail "kubectl context is ${ctx:-unset}, expected ${KUBE_CTX}.
     Fix: kubectl config use-context ${KUBE_CTX}"
  exit 1
fi
pass "kubectl context: ${KUBE_CTX}"
```

**Phase 4 adaptation:** verbatim with `${HUB_CTX}` substituted. The script ALSO touches `k3d-spoke-ml` and `k3d-spoke-apps` contexts via `--context`, but the AMBIENT context must be `k3d-hub-flux` — same gate as Phase 3.

#### Pattern A5: 3-part-AND idempotency check (D-07 inheritance, per-spoke)

**Source:** `scripts/bootstrap-flux.sh` lines 168-192 + `scripts/create-clusters.sh` lines 84-138

Phase 3 reference (lines 168-192):
```bash
# D-07: three-part idempotency AND (ns exists AND flux check AND 4 controllers Available).
ns_ok=0; check_ok=0; ctrl_ok=0

if kubectl --context "${KUBE_CTX}" get ns "${FLUX_NS}" >/dev/null 2>&1; then
  ns_ok=1
fi

if flux --context "${KUBE_CTX}" check >/dev/null 2>&1; then
  check_ok=1
fi

ctrl_ready="$(kubectl --context "${KUBE_CTX}" -n "${FLUX_NS}" get deploy \
  -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Available")].status}{"\n"}{end}' 2>/dev/null \
  | grep -cx "True" || true)"
if [[ "${ctrl_ready}" -eq 4 ]]; then
  ctrl_ok=1
fi

SKIP_BOOTSTRAP=0
if [[ ${ns_ok} -eq 1 && ${check_ok} -eq 1 && ${ctrl_ok} -eq 1 ]]; then
  info "already done, skipping: flux bootstrap (ns=present, flux check=ok, 4 controllers Available)"
  SKIP_BOOTSTRAP=1
fi
```

**Phase 4 adaptation (per-spoke 3-part AND for the `<spoke>-kubeconfig` hub Secret per CONTEXT.md Claude's Discretion line 84):**
```bash
# Inside register_spoke() — three-part AND for skip-if-healthy:
#  (a) <spoke>-kubeconfig Secret exists on hub
#  (b) data.value\.yaml decodes to a kubeconfig with the expected server: line
#  (c) auth roundtrip via in-pod wget /readyz returns "ok"
secret_ok=0; decode_ok=0; auth_ok=0

if kubectl --context "${HUB_CTX}" -n "${FLUX_NS}" get secret "${spoke}-kubeconfig" >/dev/null 2>&1; then
  secret_ok=1
fi
# ... etc.
if [[ ${secret_ok} -eq 1 && ${decode_ok} -eq 1 && ${auth_ok} -eq 1 ]]; then
  info "already done, skipping: ${spoke}-kubeconfig (Secret present, decodes, auth ok)"
  return 0
fi
```

#### Pattern A6: Helper function shape — `register_spoke <name>` mirrors `create_cluster <name> <port>`

**Source:** `scripts/create-clusters.sh` lines 76-171 (full `create_cluster` helper)

```bash
# ---------- helper: create_cluster name port [extra k3d args ...] (D-07, D-13) ----------
create_cluster() {
  local name="$1" port="$2"
  shift 2
  local extra_args=("$@")

  section "${name} cluster"

  # Idempotency check (D-09) — must verify IMAGE, NETWORK, API PORT, and GPU (spoke-ml only)
  if k3d cluster list --no-headers 2>/dev/null | awk '{print $1}' | grep -qx "$name"; then
    # ... drift checks (a)..(d), each with fail() + Fix: remediation
    info "already done, skipping: cluster ${name} (image=${actual_image}, network=${K8S_NET_NAME}, port=${port})"
  else
    info "creating: cluster ${name} on :${port} (network=${K8S_NET_NAME})"
    k3d cluster create "$name" \
      --api-port "$port" \
      --network "$K8S_NET_NAME" \
      --k3s-arg "--tls-san=k3d-${name}-server-0@server:*" \
      "${extra_args[@]}"
    pass "created: cluster ${name}"
  fi

  # ---------- D-13 SAN verification (bounded retry: 10 attempts × 3s = 30s cap) ----------
  local expected_san="k3d-${name}-server-0"
  local san_ok=0
  for i in $(seq 1 10); do
    if openssl s_client -connect "127.0.0.1:${port}" -servername "$expected_san" </dev/null 2>/dev/null \
         | openssl x509 -noout -text 2>/dev/null \
         | grep -qE "DNS:${expected_san}"; then
      san_ok=1
      break
    fi
    sleep 3
  done
  if [[ "$san_ok" -eq 1 ]]; then
    pass "SAN verified: cluster ${name} cert includes DNS:${expected_san}"
  else
    warn "deleting broken cluster ${name} (SAN missing after 10 retries / 30s)"
    k3d cluster delete "$name" >/dev/null 2>&1 || true
    fail "cluster ${name} apiserver cert missing SAN DNS:${expected_san} after 30s ..."
    exit 1
  fi
}

# ---------- Section 3-5: three clusters (CLU-02/03/04, D-08 serial order) ----------
create_cluster hub-flux   6443 --image "$K3S_STOCK_IMAGE"
create_cluster spoke-ml   6444 --image "$CUDA_IMAGE_TAG" --gpus all
create_cluster spoke-apps 6445 --image "$K3S_STOCK_IMAGE"
```

**Phase 4 adaptation — `register_spoke <name>` shape (CONTEXT.md D-01 + §specifics line 230):**
```bash
register_spoke() {
  local spoke="$1"

  section "${spoke}"

  # 3-part AND idempotency (per-spoke skip-if-healthy)
  # ... see Pattern A5 above
  # If healthy → return 0; otherwise fall through to full re-create.

  # Subsection 1: spoke-side RBAC (Namespace + SA + CRB + token Secret)
  apply_spoke_rbac "${spoke}"   # Pattern B1 below — multi-doc kubectl apply heredoc
  pass "applied: ${spoke} RBAC (SA + CRB + token Secret in flux-system)"

  # Subsection 2: token-Secret data wait (D-11 bounded retry — 10×1s)
  wait_for_token_secret "${spoke}"   # Pattern B2 below — populates TOKEN, CA_B64
  pass "secret data populated for ${spoke}: token + ca.crt"

  # Subsection 3: kubeconfig assembly (D-09 heredoc)
  local kubeconfig_yaml
  kubeconfig_yaml="$(build_kubeconfig "${spoke}" "${TOKEN}" "${CA_B64}")"   # Pattern B3 below

  # Subsection 4: hub Secret apply (D-04 imperative — NEVER committed)
  apply_hub_secret "${spoke}" "${kubeconfig_yaml}"   # Pattern B4 below
  pass "applied: ${spoke}-kubeconfig Secret on ${HUB_CTX}/${FLUX_NS}"

  # Subsection 5: write hub-side Flux Kustomization YAML (local checkout only — D-04)
  write_hub_kustomization "${spoke}"   # Pattern C1 below
  pass "wrote: clusters/hub-flux/spokes/${spoke}.yaml"

  # Subsection 6: write spoke seed tree (idempotent-by-presence per CONTEXT.md Claude's Discretion line 91)
  write_spoke_seed "${spoke}"   # Pattern C2 below
  pass "wrote: clusters/${spoke}/{kustomization,namespace,configmap}.yaml"

  # Subsection 7: in-script verification — D-13 4 gates
  verify_spoke_credential_layer "${spoke}" "${TOKEN}"   # Pattern D1 below
  pass "${spoke} verified: presence + decode + auth roundtrip + node-name proof"
}

# Caller (mirrors create-clusters.sh lines 174-176):
register_spoke spoke-ml
register_spoke spoke-apps
```

#### Pattern A7: Bounded retry loop (D-11 reuse of Phase 2 D-13 SAN verify shape)

**Source:** `scripts/create-clusters.sh` lines 149-170 (10×3s SAN verify) + RESEARCH.md §Example 2

Reference pattern (Phase 2 SAN verify):
```bash
local expected_san="k3d-${name}-server-0"
local san_ok=0
for i in $(seq 1 10); do
  if openssl s_client ...; then
    san_ok=1
    break
  fi
  sleep 3
done
if [[ "$san_ok" -eq 1 ]]; then
  pass "SAN verified: cluster ${name} cert includes DNS:${expected_san}"
else
  warn "deleting broken cluster ${name} (SAN missing after 10 retries / 30s)"
  k3d cluster delete "$name" >/dev/null 2>&1 || true
  fail "cluster ${name} apiserver cert missing SAN ..."
  exit 1
fi
```

**Phase 4 adaptation — Pattern B2 `wait_for_token_secret` (RESEARCH.md §Example 2; D-11 = 10×1s):**
```bash
wait_for_token_secret() {
  local spoke="$1"
  local timeout_s=10
  local token="" ca=""
  for i in $(seq 1 "${timeout_s}"); do
    token="$(kubectl --context "k3d-${spoke}" -n flux-system \
      get secret flux-reconciler-token -o jsonpath='{.data.token}' 2>/dev/null || true)"
    ca="$(kubectl --context "k3d-${spoke}" -n flux-system \
      get secret flux-reconciler-token -o jsonpath='{.data.ca\.crt}' 2>/dev/null || true)"
    [[ -n "${token}" && -n "${ca}" ]] && break
    sleep 1
  done
  if [[ -z "${token}" || -z "${ca}" ]]; then
    fail "flux-reconciler-token not populated on ${spoke} after ${timeout_s}s.
       Inspect: kubectl --context k3d-${spoke} -n flux-system describe secret/flux-reconciler-token
       Possible: SA missing (orphan Secret); apiserver under load; controller race.
       Fix: rerun: bash scripts/register-spokes-for-flux.sh"
    exit 1
  fi
  TOKEN="$(echo "${token}" | base64 -d)"   # decode for kubeconfig user.token: field
  CA_B64="${ca}"                            # leave base64 — kubeconfig wants base64 in cert-authority-data
}
```

**KEY DIFFERENCE from Phase 2:** Cap is 10s (1s×10), not 30s (3s×10). Phase 2 was network-probing TLS handshakes; Phase 4 is local apiserver controller (RESEARCH.md confirmed <200ms typical). Reusing the SHAPE not the values.

#### Pattern A8: Section 5 — Sentinel-guarded patch surface idempotency (D-13 inheritance, NEW sentinel)

**Source:** `scripts/bootstrap-flux.sh` lines 287-343

```bash
# ---------- Section 5: Patch-surface marker (D-13) ----------
section "Patch-surface marker"

# ... (file-existence guards)

if grep -qF '# FLUX PATCH SURFACE' "${KUST_FILE}"; then
  info "already done, skipping: patch-surface marker present"
else
  tmp="$(mktemp)"
  {
    cat <<'EOF'
# ──────────────────────────────────────────────────────────────────────────
# FLUX PATCH SURFACE
#
# This file IS the supported patch surface for the hub-flux bootstrap.
# Edits here SURVIVE re-bootstrap — add `patches:`, `configMapGenerator:`,
# `images:` etc. here to customize the 4 core controllers.
# ...
# ──────────────────────────────────────────────────────────────────────────
EOF
    cat "${KUST_FILE}"
  } > "${tmp}"
  mv "${tmp}" "${KUST_FILE}"
  pass "applied: patch-surface marker prepended to ${FLUX_PATH}/${FLUX_NS}/kustomization.yaml"
fi
```

**Phase 4 adaptation — Pattern E1 (NEW sentinel `# KARYON SPOKES MOUNT`, INSERT-under-resources NOT prepend; RESEARCH.md §Pattern 1 lines 322-349):**
```bash
# Section "Hub-side Kustomizations" — runs ONCE outside the per-spoke helper (CONTEXT.md
# Claude's Discretion line 82: symmetric across spokes, single insert).
section "Hub-side Kustomization wire-up"
KUST_FILE="${HUB_KUST_FILE}"
if grep -qF "${SPOKES_SENTINEL}" "${KUST_FILE}"; then
  info "already done, skipping: spokes mount sentinel present in ${KUST_FILE}"
else
  tmp="$(mktemp)"
  awk '
    /^resources:/ {print; in_resources=1; next}
    in_resources && /^[^ -]/ {
      print "# KARYON SPOKES MOUNT"
      print "- ../spokes"
      in_resources=0
    }
    {print}
    END {
      if (in_resources) {
        print "# KARYON SPOKES MOUNT"
        print "- ../spokes"
      }
    }
  ' "${KUST_FILE}" > "${tmp}"
  mv "${tmp}" "${KUST_FILE}"
  pass "applied: '- ../spokes' under resources: in ${KUST_FILE} (sentinel ${SPOKES_SENTINEL})"
fi
```

**Why awk-not-yq:** `yq -i 'with(.resources; . += ["../spokes"])'` works but does not carry the sentinel comment; bats static test pins the literal `# KARYON SPOKES MOUNT`. RESEARCH.md §Pattern 1 line 351 confirms.

#### Pattern A9: Section "Summary" — counters + commit/push reminder

**Source:** `scripts/bootstrap-flux.sh` lines 366-372

```bash
# ---------- Summary ----------
section "Summary"
printf "  %s%d passed%s, %s%d warnings%s, %s%d failed%s\n" \
  "${C_GREEN}" "${PASS}" "${C_RESET}" "${C_YELLOW}" "${WARN}" "${C_RESET}" "${C_RED}" "${FAIL}" "${C_RESET}"
if (( FAIL > 0 )); then exit 1; fi
printf "\n%sflux hub bootstrap complete — k3d-hub-flux is now GitOps-managed from %s/%s (%s).%s\n" \
  "${C_GREEN}" "${GITHUB_OWNER:-<owner>}" "${GITHUB_REPO:-<repo>}" "${FLUX_PATH}" "${C_RESET}"
```

**Phase 4 adaptation — D-04 reminder for the user (CONTEXT.md §specifics line 228 + Q5 RESEARCH.md):**
```bash
# ---------- Summary ----------
section "Summary"
printf "  %s%d passed%s, %s%d warnings%s, %s%d failed%s\n" \
  "${C_GREEN}" "${PASS}" "${C_RESET}" "${C_YELLOW}" "${WARN}" "${C_RESET}" "${C_RED}" "${FAIL}" "${C_RESET}"
if (( FAIL > 0 )); then exit 1; fi

info "Next: commit + push the new files so Flux reconciles them.
       git add clusters/hub-flux/spokes clusters/hub-flux/flux-system/kustomization.yaml \\
               clusters/spoke-ml clusters/spoke-apps Taskfile.yml docs/flux-hub-spoke.md \\
               scripts/register-spokes-for-flux.sh tests/bats/register-spokes-*.bats
       git commit -m 'feat(04): register spokes for Flux reconciliation (SPOKE-01..06)'
       git push
       flux reconcile source git flux-system  # (then wait ~30s for the spoke Kustomizations to land)"
printf "\n%sSpoke registration complete — k3d-hub-flux can now reconcile to spoke-ml and spoke-apps.%s\n" \
  "${C_GREEN}" "${C_RESET}"
```

#### Pattern A10: Top-of-file token-safety comment block (D-11 inheritance)

**Source:** `scripts/bootstrap-flux.sh` lines 11-13

```bash
# D-11 token-safety: set -euo pipefail INTENTIONALLY omits -x (no trace of
# GITHUB_TOKEN on stdout/stderr; strict-mode only, no debug tracing).
```

**Phase 4 adaptation — CONTEXT.md §specifics line 215-218 (verbatim):**
```bash
# D-11 token-safety: set -euo pipefail INTENTIONALLY omits -x (no bearer-token
# trace on stdout/stderr). Bearer tokens are NEVER echo/printf/pass/info/warn/fail/tee'd.
# Bearer tokens NEVER land in any committed file. The hub Secret is applied
# imperatively via `kubectl apply -f -` from a heredoc; it is not git-tracked.
```

**Bats static test pins this:** `tests/bats/bootstrap-flux-01-idempotent.bats` lines 56-65 (token-funnel negative-grep). Phase 4 register-spokes-01-static.bats inherits the same negative-grep with `TOKEN` (not `GITHUB_TOKEN`) per the RESEARCH.md §Anti-Patterns section.

---

### `clusters/hub-flux/spokes/spoke-ml.yaml` + `spoke-apps.yaml` (Flux v1 Kustomization CRD)

**Analog:** `clusters/hub-flux/flux-system/gotk-sync.yaml` lines 16-27 (live Flux v1 Kustomization shape, bootstrap-managed reference)

#### Pattern F1: Flux v1 Kustomization shape

**Source:** `clusters/hub-flux/flux-system/gotk-sync.yaml` lines 16-27 (already in repo, bootstrap-managed)

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: flux-system
  namespace: flux-system
spec:
  interval: 10m0s
  path: ./clusters/hub-flux
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
```

**Phase 4 adaptation — RESEARCH.md §Example 5 + CONTEXT.md §specifics lines 242-261 (with `spec.kubeConfig` block — the load-bearing addition):**
```yaml
# clusters/hub-flux/spokes/spoke-ml.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: spoke-ml
  namespace: flux-system
spec:
  interval: 5m            # Phase 4 default; Phase 5 may tune per workload tree.
  path: ./clusters/spoke-ml
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system     # the bootstrap-managed GitRepo from Phase 3
  kubeConfig:
    secretRef:
      name: spoke-ml-kubeconfig
      key: value.yaml     # EXPLICIT per REQ-SPOKE-04 / Pitfall 2 defense-in-depth
  # No spec.targetNamespace — let manifests declare their own namespaces.
```

**RESEARCH.md adjustment — P18 reframe (line 14-15, line 484):**
P18 silent-misroute is **`spec.kubeConfig` block ENTIRELY ABSENT** (controller falls back to in-cluster SA → reconciles to HUB → `Ready=True`). Wrong-key produces `Ready=False` (loud). The defense is "always include `spec.kubeConfig.secretRef.{name,key}`"; explicit `key: value.yaml` is belt-and-suspenders. **Bats static test MUST grep for both `spec.kubeConfig:` AND `key: value.yaml` in each spoke YAML.**

**Mirror for spoke-apps.yaml:** substitute every `spoke-ml` → `spoke-apps`. The shape is byte-identical except for that substitution.

---

### `clusters/hub-flux/spokes/kustomization.yaml` (kustomize index)

**Analog:** `clusters/hub-flux/flux-system/kustomization.yaml` lines 14-18 (resources-list pattern)

#### Pattern F2: kustomize.config.k8s.io/v1beta1 resources-list

**Source:** `clusters/hub-flux/flux-system/kustomization.yaml` lines 14-18

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- gotk-components.yaml
- gotk-sync.yaml
```

**Phase 4 adaptation:**
```yaml
# clusters/hub-flux/spokes/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- spoke-ml.yaml
- spoke-apps.yaml
```

This file is created locally by the script and committed by the user. NOT a patch-surface like the flux-system one — no sentinel header needed.

---

### `clusters/spoke-ml/{kustomization,namespace,configmap}.yaml` + `clusters/spoke-apps/...` (spoke seed tree)

**Analogs:**
- `clusters/hub-flux/flux-system/kustomization.yaml` lines 14-18 → kustomization.yaml resources-list pattern (same as Pattern F2)
- RESEARCH.md §Example 6 → core/v1 Namespace and ConfigMap stock templates (live-verified 2026-04-27)

#### Pattern F3: Per-spoke kustomization.yaml

**Source:** Mirror of `clusters/hub-flux/spokes/kustomization.yaml` (Pattern F2)

```yaml
# clusters/spoke-ml/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- namespace.yaml
- configmap.yaml
```

#### Pattern F4: core/v1 Namespace stock template

**Source:** RESEARCH.md §Example 6 (no in-repo analog — Phase 4 is first to write spoke-side manifests; see CONTEXT.md §code_context line 152)

```yaml
# clusters/spoke-ml/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: karyon-spoke-ml
```

#### Pattern F5: core/v1 ConfigMap stock template (with falsifier `data.spoke=<spoke>`)

**Source:** RESEARCH.md §Example 6

```yaml
# clusters/spoke-ml/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: karyon-spoke-id
  namespace: karyon-spoke-ml
data:
  spoke: spoke-ml          # Distinct per spoke — falsifiable for negative-proof.
```

**Mirror for spoke-apps:** every `spoke-ml` → `spoke-apps`, every `karyon-spoke-ml` → `karyon-spoke-apps`. The ConfigMap NAME stays `karyon-spoke-id` on both — that's the cross-cluster falsifier (RESEARCH.md §Common Pitfalls Pitfall 2 line 494; bats live test asserts the same name appears ONLY on the targeted spoke).

---

### `tests/bats/register-spokes-01-static.bats` (static-grep bats)

**Analogs:**
- **Primary:** `tests/bats/bootstrap-flux-01-idempotent.bats` lines 27-93 (entire static @tests block)
- **Pure-static analog:** `tests/bats/bootstrap-flux-02-docs.bats` (whole file — pure static doc greps; identical patterns)

#### Pattern G1: Test-helper load + setup() variable resolution

**Source:** `tests/bats/bootstrap-flux-01-idempotent.bats` lines 16-22

```bash
load 'test_helper'

setup() {
  SCRIPT="${REPO_ROOT}/scripts/bootstrap-flux.sh"
}

teardown() {
  :
}
```

**Phase 4 adaptation:**
```bash
load 'test_helper'

setup() {
  SCRIPT="${REPO_ROOT}/scripts/register-spokes-for-flux.sh"
  SPOKE_ML_KS="${REPO_ROOT}/clusters/hub-flux/spokes/spoke-ml.yaml"
  SPOKE_APPS_KS="${REPO_ROOT}/clusters/hub-flux/spokes/spoke-apps.yaml"
  SPOKES_INDEX="${REPO_ROOT}/clusters/hub-flux/spokes/kustomization.yaml"
  HUB_FS_KUST="${REPO_ROOT}/clusters/hub-flux/flux-system/kustomization.yaml"
  DOC="${REPO_ROOT}/docs/flux-hub-spoke.md"
}

teardown() {
  :
}
```

#### Pattern G2: File-exists + grep-literal

**Source:** `tests/bats/bootstrap-flux-01-idempotent.bats` lines 29-33

```bash
@test "FLUX-01: scripts/bootstrap-flux.sh invokes flux bootstrap github" {
  [ -f "$SCRIPT" ]
  run grep -F -- 'flux bootstrap github' "$SCRIPT"
  [ "$status" -eq 0 ]
}
```

**Phase 4 adaptation — pin every literal CONTEXT.md §specifics lines 326-333 lists:**
```bash
@test "SPOKE-01: scripts/register-spokes-for-flux.sh creates flux-reconciler ServiceAccount + cluster-admin CRB" {
  [ -f "$SCRIPT" ]
  run grep -F -- 'flux-reconciler' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- 'flux-reconciler-cluster-admin' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- 'cluster-admin' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "SPOKE-02: scripts/register-spokes-for-flux.sh creates legacy SA-token Secret with annotation" {
  [ -f "$SCRIPT" ]
  run grep -F -- 'flux-reconciler-token' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- 'kubernetes.io/service-account-token' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- 'kubernetes.io/service-account.name: flux-reconciler' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "SPOKE-03: server URL literal https://k3d-<spoke>-server-0:6443 in script" {
  [ -f "$SCRIPT" ]
  run grep -F -- 'k3d-${spoke}-server-0:6443' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "SPOKE-04: 'value.yaml' key literal in script + each spoke Kustomization YAML + doc" {
  [ -f "$SCRIPT" ]
  run grep -F -- 'value.yaml' "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -f "$SPOKE_ML_KS" ]
  run grep -F -- 'key: value.yaml' "$SPOKE_ML_KS"
  [ "$status" -eq 0 ]
  [ -f "$SPOKE_APPS_KS" ]
  run grep -F -- 'key: value.yaml' "$SPOKE_APPS_KS"
  [ "$status" -eq 0 ]
  [ -f "$DOC" ]
  run grep -F -- 'value.yaml' "$DOC"
  [ "$status" -eq 0 ]
}

@test "SPOKE-05: each spoke Kustomization YAML has spec.kubeConfig.secretRef.{name,key}" {
  [ -f "$SPOKE_ML_KS" ]
  run grep -F -- 'kubeConfig:' "$SPOKE_ML_KS"
  [ "$status" -eq 0 ]
  run grep -F -- 'secretRef:' "$SPOKE_ML_KS"
  [ "$status" -eq 0 ]
  run grep -F -- 'name: spoke-ml-kubeconfig' "$SPOKE_ML_KS"
  [ "$status" -eq 0 ]
  # Mirror for spoke-apps.
  [ -f "$SPOKE_APPS_KS" ]
  run grep -F -- 'name: spoke-apps-kubeconfig' "$SPOKE_APPS_KS"
  [ "$status" -eq 0 ]
}

@test "D-02: hub-flux/flux-system/kustomization.yaml carries # KARYON SPOKES MOUNT sentinel + - ../spokes" {
  [ -f "$HUB_FS_KUST" ]
  run grep -F -- '# KARYON SPOKES MOUNT' "$HUB_FS_KUST"
  [ "$status" -eq 0 ]
  run grep -F -- '- ../spokes' "$HUB_FS_KUST"
  [ "$status" -eq 0 ]
}
```

#### Pattern G3: set -euo pipefail positive grep + set -x negative grep (D-11)

**Source:** `tests/bats/bootstrap-flux-01-idempotent.bats` lines 45-54

```bash
@test "FLUX-03 / D-11: scripts/bootstrap-flux.sh uses set -euo pipefail and does NOT use set -x" {
  [ -f "$SCRIPT" ]
  # Positive: strict mode line present.
  run grep -E '^set -euo pipefail' "$SCRIPT"
  [ "$status" -eq 0 ]
  # Negative: no `set -x` (or `set -eux`, `set -xe`, etc.) - D-11 forbids trace mode.
  # Filter comments first to avoid self-invalidating grep gate.
  run bash -c "grep -v '^[[:space:]]*#' '$SCRIPT' | grep -E '^[[:space:]]*set[[:space:]]+-[a-zA-Z]*x'"
  [ "$status" -ne 0 ]
}
```

**Phase 4 adaptation:** verbatim (rename to `D-11: scripts/register-spokes-for-flux.sh ...`).

#### Pattern G4: Token-funnel negative-grep (D-11 inheritance — `TOKEN` replaces `GITHUB_TOKEN`)

**Source:** `tests/bats/bootstrap-flux-01-idempotent.bats` lines 56-65

```bash
@test "FLUX-03 / D-11 (token safety, broadened): \$GITHUB_TOKEN never funneled through echo/printf/pass/info/warn/fail/tee" {
  [ -f "$SCRIPT" ]
  # Single combined negative-grep (LOW-2) - catches:
  #   - `echo "$GITHUB_TOKEN"` (any quoting)
  #   - `printf '%s' "$GITHUB_TOKEN"`
  #   - `pass|info|warn|fail "...$GITHUB_TOKEN..."`
  #   - `tee` (in any role; flux bootstrap output capture forbidden)
  # Filter comments first so the header prose / threat-model can mention these names without false-failing.
  run bash -c "grep -v '^[[:space:]]*#' '$SCRIPT' | grep -E '(echo|printf)[[:space:]]+.*GITHUB_TOKEN|^[[:space:]]*(pass|info|warn|fail)[[:space:]]+.*GITHUB_TOKEN|tee[[:space:]]+'"
  [ "$status" -ne 0 ]
}
```

**Phase 4 adaptation — substitute `GITHUB_TOKEN` → `TOKEN` (or `BEARER_TOKEN` if the script names the variable that way), AND add a parallel grep for `KUBECONFIG_YAML` (the assembled YAML carries the token):**
```bash
@test "D-11 (token safety): \$TOKEN / \$KUBECONFIG_YAML never funneled through echo/printf/pass/info/warn/fail/tee" {
  [ -f "$SCRIPT" ]
  # Filter comments so the header prose / token-safety comment block does not self-invalidate.
  run bash -c "grep -v '^[[:space:]]*#' '$SCRIPT' | grep -E '(echo|printf)[[:space:]]+.*(TOKEN|KUBECONFIG_YAML)|^[[:space:]]*(pass|info|warn|fail)[[:space:]]+.*(TOKEN|KUBECONFIG_YAML)|tee[[:space:]]+'"
  [ "$status" -ne 0 ]
}

@test "D-04: scripts/register-spokes-for-flux.sh does NOT auto-push (no 'git push' command)" {
  [ -f "$SCRIPT" ]
  # Filter comments AND info/printf reminder strings (those CAN mention 'git push' in their text).
  # Negative match: a literal `git push` invocation as a command (start-of-line or after &&/||/;).
  run bash -c "grep -v '^[[:space:]]*#' '$SCRIPT' | grep -E '^[[:space:]]*git[[:space:]]+push|[;&|][[:space:]]*git[[:space:]]+push'"
  [ "$status" -ne 0 ]
}
```

#### Pattern G5: skip-message literal pin (D-07 inheritance)

**Source:** `tests/bats/bootstrap-flux-01-idempotent.bats` lines 68-74

```bash
@test "D-07 / FLUX-04: scripts/bootstrap-flux.sh contains the exact skip-message literal" {
  [ -f "$SCRIPT" ]
  run grep -F -- 'already done, skipping: flux bootstrap' "$SCRIPT"
  [ "$status" -eq 0 ]
}
```

**Phase 4 adaptation:** pin one of the script's skip-message literals (e.g., `'already done, skipping: ${spoke}-kubeconfig'` or `'already done, skipping: spokes mount sentinel present'`).

---

### `tests/bats/register-spokes-02-live.bats` (live destructive bats)

**Analogs:**
- **Primary:** `tests/bats/bootstrap-flux-01-idempotent.bats` lines 95-126 (require_live_destructive block — runs script, asserts cluster state)
- **Code pattern:** RESEARCH.md §Example 8 (lines 786-832 — verbatim live test plan)

#### Pattern G6: require_live_destructive double-gate

**Source:** `tests/bats/test_helper.bash` lines 43-49

```bash
require_live_destructive() {
  if [[ -z "${KARYON_LIVE_TESTS:-}" || -z "${KARYON_LIVE_TESTS_DESTRUCTIVE:-}" ]]; then
    skip "destructive live test — set KARYON_LIVE_TESTS=1 KARYON_LIVE_TESTS_DESTRUCTIVE=1 to run (tears down k3d clusters)"
  fi
}
```

**Source:** `tests/bats/bootstrap-flux-01-idempotent.bats` lines 102-104 (usage)

```bash
@test "FLUX-04 + D-13 (live/destructive, combined): bootstrap is idempotent AND patch-surface marker survives re-run" {
  require_live_destructive
  [ -f "$SCRIPT" ]
  # ... live cluster assertions ...
}
```

**Phase 4 adaptation — RESEARCH.md §Example 8 verbatim shape:**
```bash
load 'test_helper'

setup() {
  require_live_destructive
}

@test "spoke-ml Kustomization Ready=True (assumes user has pushed)" {
  run kubectl --context k3d-hub-flux -n flux-system get kustomization spoke-ml \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
  [[ "$status" -eq 0 ]]
  [[ "$output" == "True" ]]
}

@test "spoke-ml inventory contains the seed ConfigMap (negative-proof of correct cluster)" {
  run bash -c "kubectl --context k3d-hub-flux -n flux-system get kustomization spoke-ml \
        -o json | jq -r '.status.inventory.entries[].id' \
        | grep -F 'karyon-spoke-ml_karyon-spoke-id__ConfigMap'"
  [[ "$status" -eq 0 ]]
}

@test "spoke-apps Kustomization Ready=True" {
  run kubectl --context k3d-hub-flux -n flux-system get kustomization spoke-apps \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
  [[ "$status" -eq 0 ]]
  [[ "$output" == "True" ]]
}

@test "spoke-apps inventory contains the seed ConfigMap" {
  run bash -c "kubectl --context k3d-hub-flux -n flux-system get kustomization spoke-apps \
        -o json | jq -r '.status.inventory.entries[].id' \
        | grep -F 'karyon-spoke-apps_karyon-spoke-id__ConfigMap'"
  [[ "$status" -eq 0 ]]
}

@test "spoke seed ConfigMap exists ONLY on the targeted spoke (cross-cluster falsifier)" {
  # The karyon-spoke-id ConfigMap should NOT exist on hub.
  run kubectl --context k3d-hub-flux -n karyon-spoke-ml get configmap karyon-spoke-id 2>&1
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"NotFound"* ]] || [[ "$output" == *"not found"* ]]
  # AND it SHOULD exist on the spoke.
  run kubectl --context k3d-spoke-ml -n karyon-spoke-ml get configmap karyon-spoke-id \
        -o jsonpath='{.data.spoke}'
  [[ "$status" -eq 0 ]]
  [[ "$output" == "spoke-ml" ]]
}
```

**RESEARCH.md adjustment — inventory ID format (lines 834-843):** `<namespace>_<name>_<group>_<kind>` — for core API ConfigMap (empty group), this becomes `<namespace>_<name>__<kind>` with **literal double-underscore** between name and kind. The grep MUST be `karyon-spoke-ml_karyon-spoke-id__ConfigMap` (two underscores). NOT UID-suffixed (CONTEXT.md §domain line 21 guessed UID-suffixed; research empirically corrected).

**Optional precondition check per RESEARCH.md §Open Questions Q4 line 893:** the test `setup()` could detect "user has not pushed yet" (local commits ahead of origin/main under `clusters/hub-flux/spokes/`, `clusters/spoke-ml/`, `clusters/spoke-apps/`) and `skip` with a helpful message rather than fail loudly. Recommendation per researcher: skip with `"please git push and wait 1-2 min for Flux to reconcile, then rerun"`.

---

### `clusters/hub-flux/flux-system/kustomization.yaml` (modify — sentinel-guarded patch)

**Analog:** `scripts/bootstrap-flux.sh` lines 287-343 (Phase 3 D-13 patch surface — Phase 4 adds NEW sentinel under `resources:`, NOT prepend)

See **Pattern A8** above for the awk-insert idiom. Existing file content (snapshot):

```yaml
# ──────────────────────────────────────────────────────────────────────────
# FLUX PATCH SURFACE
# ...
# ──────────────────────────────────────────────────────────────────────────
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- gotk-components.yaml
- gotk-sync.yaml
```

**Post-Phase-4 expected state:**

```yaml
# ──────────────────────────────────────────────────────────────────────────
# FLUX PATCH SURFACE
# ...
# ──────────────────────────────────────────────────────────────────────────
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- gotk-components.yaml
- gotk-sync.yaml
# KARYON SPOKES MOUNT
- ../spokes
```

(The exact insert position depends on awk's loop — top-of-resources vs end-of-resources. Either is valid kustomize; bats static test pins both `# KARYON SPOKES MOUNT` AND `- ../spokes` as separate literals so positional drift doesn't break the test.)

---

### `Taskfile.yml` (append — register-spokes task)

**Analog:** `Taskfile.yml` lines 19-22 (existing `bootstrap-flux` task — in-file self-analog)

#### Pattern T1: Single-task entry shape

**Source:** `Taskfile.yml` lines 19-22

```yaml
  bootstrap-flux:
    desc: Bootstrap Flux GitOps on k3d-hub-flux from clusters/hub-flux/ (FLUX-01..04)
    cmds:
      - bash scripts/bootstrap-flux.sh
```

**Phase 4 adaptation — append after `bootstrap-flux:`:**
```yaml
  register-spokes:
    desc: Register spoke clusters for Flux reconciliation via spec.kubeConfig (SPOKE-01..06)
    cmds:
      - bash scripts/register-spokes-for-flux.sh
```

CONTEXT.md §domain line 22: "single-line invocation; full REPO-05 reorganization stays Phase 6". Stay consistent with the 3 existing entries.

---

### `docs/flux-hub-spoke.md` (fill the Phase 4 stub)

**Analog:** `docs/flux-hub-spoke.md` lines 52-115 (Rule 1, Rule 2, Rule 3 — in-file self-analog for prose+table+code-block depth)

**Existing stub (line 126):**
```markdown
<!-- Phase 4: hub-spoke reconciliation (spec.kubeConfig, <spoke>-kubeconfig Secrets, value.yaml key) -->
```

#### Pattern D1: Section structure (rule-prose + table + fenced code blocks)

**Source — existing self-analog (Rule 2 lines 59-95):**
```markdown
## Rule 2: `kustomization.yaml` IS the supported patch surface

Hand-edits to `clusters/hub-flux/flux-system/kustomization.yaml` survive re-bootstrap.
`flux bootstrap` only rewrites this file when its `resources:` block diverges from what
the current CLI flag set would produce; the `patches:`, `configMapGenerator:`, `images:`,
and other Kustomize-native blocks you add here stay intact. The top-of-file
`# FLUX PATCH SURFACE` comment block that `scripts/bootstrap-flux.sh` prepends is part
of the same invariant.

Example — bump `kustomize-controller`'s memory limit from the default 1Gi default to an
explicit 1Gi declaration:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
...
```

To prove the patch survived re-bootstrap, run:

```bash
bash scripts/bootstrap-flux.sh
kubectl --context k3d-hub-flux -n flux-system get deploy kustomize-controller \
  -o jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}'
# Expected: 1Gi
```
```

**Phase 4 adaptation — REPLACE the line-126 stub with the section per CONTEXT.md §specifics lines 271-324 (P18 reframed per RESEARCH.md §Pitfall 2 lines 478-492 → "spec.kubeConfig accidentally OMITTED" not "key typo silently misroutes"):**

```markdown
## Phase 4: Hub-spoke reconciliation

After `bash scripts/register-spokes-for-flux.sh` runs, the hub knows how to
reconcile manifests into each spoke. Three artifacts make this work:

1. **Per-spoke RBAC.** `flux-reconciler` SA + cluster-admin CRB + legacy
   `flux-reconciler-token` Secret in `flux-system` on each spoke. The legacy
   Secret has indefinite lifetime — chosen over `kubectl create token`
   (TokenRequest) because token expiry is not a useful failure mode in a lab.

2. **Hub-side `<spoke>-kubeconfig` Secret.** Lives in `flux-system` on
   `k3d-hub-flux`, key `value.yaml` (the explicit key REQ-SPOKE-04 locks).
   Contains the spoke's CA-data + bearer token + `https://k3d-<spoke>-server-0:6443`
   server URL. Applied imperatively (never committed — bearer token).

3. **Hub-side Flux `Kustomization` per spoke.** Lives at
   `clusters/hub-flux/spokes/<spoke>.yaml`, mounted into the existing
   flux-system Kustomization via the patch surface (`- ../spokes` added to
   `clusters/hub-flux/flux-system/kustomization.yaml`'s `resources:`). MUST
   include `spec.kubeConfig.secretRef.{name,key}` — both fields explicit. The
   `key: value.yaml` is belt-and-suspenders against future Flux defaults.

### Silent-misroute pitfall (P18)

**The real failure mode is a Kustomization YAML that omits `spec.kubeConfig`
entirely.** When that block is absent, the kustomize-controller reconciles via
its own in-cluster ServiceAccount, lands manifests on the hub instead of the
spoke, and reports `Ready=True`. Verified empirically against Flux 2.8.6
(2026-04-27): a wrong / missing `secretRef.key` produces `Ready=False` (loud);
a missing `spec.kubeConfig` block silently misroutes to hub.

Two defenses:

- Every spoke Kustomization YAML in `clusters/hub-flux/spokes/` includes both
  `spec.kubeConfig.secretRef.name` AND `key: value.yaml` explicitly. Do NOT
  remove either.
- `scripts/register-spokes-for-flux.sh` runs an in-pod node-name probe per
  spoke after creating the Secret: from inside `kustomize-controller` on hub,
  `wget --header='Authorization: Bearer <TOKEN>' https://k3d-<spoke>-server-0:6443/api/v1/nodes`
  MUST return a node named `k3d-<spoke>-server-0` (NOT `k3d-hub-flux-server-0`).
  If the probe fails, the script aborts before declaring success.

### Verification

After committing + pushing the new `clusters/hub-flux/spokes/`, `clusters/spoke-ml/`,
`clusters/spoke-apps/` trees:

```bash
flux --context k3d-hub-flux get kustomizations -n flux-system
# spoke-ml and spoke-apps both Ready=True
```

Live/destructive bats: `KARYON_LIVE_TESTS=1 KARYON_LIVE_TESTS_DESTRUCTIVE=1 \
bats tests/bats/register-spokes-02-live.bats` — asserts the full
`.status.inventory` negative-proof (the seed `karyon-spoke-id` ConfigMap
appears in each spoke Kustomization's inventory and lives ONLY on the
targeted spoke).
```

**RESEARCH.md adjustment — D-14 image deviation (lines 13, 156-197):** the in-pod probe uses `wget` (not `kubectl`) because `ghcr.io/fluxcd/kustomize-controller:v1.8.4` is distroless-style and ships no kubectl. The doc above uses `wget` to match the script. The bats live test does its own kubectl-driven assertions (running on the host with full kubectl tooling).

---

## Shared Patterns

### Authentication / Authorization
**Source:** `scripts/bootstrap-flux.sh` lines 156-166 (kubectl context gate)
**Apply to:** `scripts/register-spokes-for-flux.sh`

The script's authority is the user's local kubeconfig with cluster-admin on hub-flux + spoke-ml + spoke-apps (k3d default). NEVER auto-switch contexts (D-06 inheritance):

```bash
ctx="$(kubectl config current-context 2>/dev/null || true)"
if [[ "${ctx}" != "${HUB_CTX}" ]]; then
  fail "kubectl context is ${ctx:-unset}, expected ${HUB_CTX}.
     Fix: kubectl config use-context ${HUB_CTX}"
  exit 1
fi
```

But each per-spoke step uses `--context "k3d-${spoke}"` explicitly to talk to the spoke's apiserver — the ambient context stays `k3d-hub-flux`.

### Error Handling
**Source:** `scripts/lib/preflight-lib.sh` lines 21-25 (`section`, `pass`, `warn`, `fail`, `info` helpers)
**Apply to:** every section of the new script

```bash
section() { printf "\n%s%s== %s ==%s\n" "$C_BOLD" "$C_BLUE" "$1" "$C_RESET"; }
pass()    { printf "  %s✓%s %s\n" "$C_GREEN" "$C_RESET" "$1"; PASS=$((PASS+1)); }
warn()    { printf "  %s!%s %s\n" "$C_YELLOW" "$C_RESET" "$1"; WARN=$((WARN+1)); WARN_MSGS+=("$1"); }
fail()    { printf "  %s✗%s %s\n" "$C_RED" "$C_RESET" "$1"; FAIL=$((FAIL+1)); FAIL_MSGS+=("$1"); }
info()    { printf "  %s·%s %s\n" "$C_DIM" "$C_RESET" "$1"; }
```

**Convention from Phase 1/2/3 (verbatim per CONTEXT.md §code_context line 162):** every `fail` ends with `Fix: <exact next command>`; every guarded section either logs `info "already done, skipping: <what>"` or proceeds with `pass "<doing>: <what>"`.

**Phase 4 token-safety override:** NEVER pass `$TOKEN`, `$CA_B64`, or `$KUBECONFIG_YAML` to any of these helpers. The bats static test (Pattern G4) pins this at the regex level.

### Validation / Idempotency Checks
**Source:** `scripts/bootstrap-flux.sh` lines 168-205 (3-part-AND idempotency + skip-if-healthy/fall-through)
**Apply to:** Per-spoke gate inside `register_spoke()`, AND the spokes-mount sentinel guard before patching `clusters/hub-flux/flux-system/kustomization.yaml`, AND the seed-tree write guard (file-exists per CONTEXT.md Claude's Discretion line 91).

The pattern: probe state with multiple boolean gates → if all true, log skip and return; if any false, fall through to full re-create. Never partial-apply.

```bash
if [[ ${gate_a} -eq 1 && ${gate_b} -eq 1 && ${gate_c} -eq 1 ]]; then
  info "already done, skipping: ${what}"
  return 0
fi
# else fall through to re-create
```

### Token-Safety Discipline (CROSS-CUTTING — applies to ALL Phase 4 deliverables)
**Source:** `scripts/bootstrap-flux.sh` lines 11-13 (D-11 verbatim) + `tests/bats/bootstrap-flux-01-idempotent.bats` lines 56-65 (negative-grep enforcement)
**Apply to:** `scripts/register-spokes-for-flux.sh` (NEVER `set -x`, NEVER funnel `$TOKEN`/`$KUBECONFIG_YAML` through helpers/echo/printf/tee), `tests/bats/register-spokes-01-static.bats` (negative-grep), `docs/flux-hub-spoke.md` (NEVER paste real Secret content as example).

**Adapted negative-grep regex for Phase 4 (per Pattern G4):**
```bash
'(echo|printf)[[:space:]]+.*(TOKEN|KUBECONFIG_YAML)|^[[:space:]]*(pass|info|warn|fail)[[:space:]]+.*(TOKEN|KUBECONFIG_YAML)|tee[[:space:]]+'
```

### File-write discipline (D-04 — no auto-push, no committed Secrets)
**Source:** `scripts/bootstrap-flux.sh` lines 345-364 (info-line nudge after marker insertion; never auto-push)
**Apply to:** `scripts/register-spokes-for-flux.sh` Section "Summary" (info line listing the exact `git add ... && git commit && git push` command, plus optional `flux reconcile source git flux-system` nudge per RESEARCH.md §Open Questions Q5).

**Cross-check:** the bats static test (Pattern G4 second @test) negative-greps for `^git push` or `&& git push` or `; git push` outside of comments AND outside of `info "..."` strings (the message text CAN contain the literal "git push" because the user's eyes need it).

---

## No Analog Found

Files that lacked a direct in-repo analog at Phase 4's start (planner uses RESEARCH.md templates verbatim):

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `clusters/spoke-ml/namespace.yaml` | core/v1 Namespace | declarative | Phase 4 is the first phase to write spoke-side manifests; no `kind: Namespace` YAML existed in repo before. RESEARCH.md §Example 6 provides the live-verified stock template. |
| `clusters/spoke-ml/configmap.yaml` | core/v1 ConfigMap | declarative | Same — no `kind: ConfigMap` YAML existed; RESEARCH.md §Example 6 template (with the `data.spoke=<spoke>` falsifier baked in). |
| `clusters/spoke-apps/namespace.yaml` | core/v1 Namespace | declarative | mirror of spoke-ml |
| `clusters/spoke-apps/configmap.yaml` | core/v1 ConfigMap | declarative | mirror of spoke-ml |

These are stock 6-line / 8-line YAML templates; the "no analog" status is benign — there is nothing project-specific to copy. RESEARCH.md §Example 6 IS the source.

---

## RESEARCH.md Adjustments to Carry Through Planning

The planner MUST surface these in the relevant plans (likely 04-01 script, 04-03 verification, 04-04 doc):

1. **D-14 image adjustment** (RESEARCH.md lines 13, 156-197, §Example 7 lines 743-781): `ghcr.io/fluxcd/kustomize-controller:v1.8.4` ships no kubectl/curl/jq. The in-pod probe uses `wget --no-check-certificate --header='Authorization: Bearer <TOKEN>'` against `/readyz` (auth roundtrip) and `/api/v1/nodes` (node-name negative-proof), parsed with busybox `grep -oE` + `head -1` + `tr -d '"'`. Plan 04-03 `verify_spoke_credential_layer` MUST use this form, not `kubectl auth can-i` / `kubectl get nodes`.

2. **P18 reframe** (RESEARCH.md lines 14-15, §Pitfall 2 lines 478-492): the silent-misroute is `spec.kubeConfig` block ENTIRELY ABSENT (in-cluster SA fallback → reconciles to hub → `Ready=True`). Wrong-key produces `Ready=False` (loud). Doc Pattern D1 above already reframes; the script's per-spoke verification still catches both via the node-name probe (proves the kubeconfig actually targets the spoke).

3. **Inventory ID format** (RESEARCH.md lines 834-843): `<namespace>_<name>_<group>_<kind>` — for core API ConfigMap (empty group) → literal **double-underscore** `karyon-spoke-ml_karyon-spoke-id__ConfigMap`. NOT UID-suffixed (CONTEXT.md §domain line 21 guessed UID-suffixed; corrected). The bats live test grep MUST use `__ConfigMap` (two underscores).

4. **`flux-system` namespace creation on each spoke** (RESEARCH.md §Open Question 1 lines 875-879 + §Example 1 lines 590-601, Assumption A3 line 865): k3d-spoke-ml / k3d-spoke-apps do NOT ship a `flux-system` namespace by default. Plan 04-01 multi-doc `kubectl apply -f -` heredoc MUST include `kind: Namespace; metadata.name: flux-system` as the FIRST document, BEFORE the SA, CRB, Secret. (Pitfall 1 line 466-474: orphan SA-token Secrets are auto-deleted within ~3s if their referenced SA does not exist when the Secret is created. The single-heredoc multi-doc apply guarantees document-order applies the Namespace + SA before the Secret.)

5. **Hub Secret apply mechanics** (RESEARCH.md §Example 4 lines 671-683, Don't Hand-Roll table line 440): `kubectl create secret generic <spoke>-kubeconfig --from-file=value.yaml=/dev/stdin --dry-run=client -o yaml | kubectl apply -f -` is verified-live and idempotent. Use this form (not the heredoc-Secret-YAML form) per CONTEXT.md Claude's Discretion line 86. Verified: produces correct `data.value.yaml` field; idempotent on apply.

6. **TOKEN_B64 vs TOKEN decoding** (RESEARCH.md §Example 2 lines 633-638): `data.token` from the Secret comes base64-encoded. Decode it (`base64 -d`) before substituting into the kubeconfig YAML's `users[0].user.token:` field. `data.ca.crt` stays base64-encoded (kubeconfig wants base64 in `clusters[0].cluster.certificate-authority-data:`). The script's variables (TOKEN_B64 vs TOKEN, CA_B64 stays raw) make this unambiguous.

7. **`spec.interval: 5m` on spoke Kustomizations** (RESEARCH.md §Open Question 2 lines 880-883): root flux-system Kustomization is `interval: 10m0s` (verified live in `gotk-sync.yaml` line 22); spoke Kustomizations use `5m` per Researcher recommendation for tighter dev-loop feedback. Phase 5 may revisit.

8. **Bats live test `setup()` precondition** (RESEARCH.md §Open Question 4 lines 890-893): the test should detect "user has not pushed yet" (local commits ahead of `origin/main` under `clusters/hub-flux/spokes/`, `clusters/spoke-ml/`, `clusters/spoke-apps/`) and `skip` with a helpful message ("please git push and wait 1-2 min for Flux to reconcile, then rerun"). Don't fail loudly — the test isn't broken; the user just hasn't completed the workflow.

9. **Phase 6 gitleaks advisory section retention** (CONTEXT.md §domain line 27 + §code_context Section 1 of `bootstrap-flux.sh`): Phase 4 may KEEP the warn-only `Gitleaks pre-commit advisory` section from Phase 3 (as-is) OR drop it (single-purpose script). Recommendation: keep it identical to Phase 3 — code reviewers expect it; Phase 6 lands the canonical install. The bats test in Phase 3 (line 83-93) pins the section; if Phase 4's script omits it, no Phase 4 bats test pins it (no regression coverage).

10. **k3s spokes ship without `flux-system` namespace** (Assumption A3 line 865): include `Namespace flux-system` as the first document in the RBAC heredoc per Pattern B1 below (RESEARCH.md §Example 1 lines 590-601). NEVER skip the Namespace (orphan-Secret risk per Pitfall 1).

---

## Metadata

**Analog search scope:** `scripts/`, `scripts/lib/`, `clusters/hub-flux/`, `tests/bats/`, `docs/`, `Taskfile.yml`, `.planning/phases/03-flux-hub-bootstrap/03-PATTERNS.md` (prior phase pattern map).

**Files scanned:** 14 in-repo files read in full or relevant sections; ~25 cross-referenced via grep / ls / wc.

**Pattern extraction date:** 2026-04-27.

**Source-file line numbers verified against current HEAD** (commit `8304e52`). The PATTERNS.md cites are stable as of this commit.
