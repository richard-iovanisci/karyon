# Phase 3: Flux Hub Bootstrap - Pattern Map

**Mapped:** 2026-04-24
**Files analyzed:** 5 (4 created + 1 modified + 1 runtime-modified)
**Analogs found:** 5 / 5

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `scripts/bootstrap-flux.sh` | orchestration script (mutates cluster + git remote; wrapper around `flux bootstrap github`) | imperative request-response (delegates to `scripts/preflight.sh`; drives `flux` CLI → kube-apiserver + GitHub REST) | `scripts/create-clusters.sh` | exact (same shape: preflight gate → guarded sections → in-cluster mutation → post-op verification) |
| `docs/flux-hub-spoke.md` | contract doc (patch-surface rules; Phase-3-scoped skeleton with HTML-comment stub for Phase 4) | static markdown | `docs/wsl-networking.md` | role-match (only other multi-rule contract doc in `docs/`) |
| `tests/bats/bootstrap-flux-01-idempotent.bats` | destructive live-gated bats test with static-grep @tests + one live double-gated @test | static grep + shell-out to script; asserts stdout, exit code, and file state | `tests/bats/delete-clusters-01-cache.bats` | exact (same dual-layer shape: static-grep @test + `require_live_destructive` @test that runs a cluster-mutating script) |
| `tests/bats/bootstrap-flux-02-docs.bats` | static-grep-only bats test asserting `docs/flux-hub-spoke.md` carries the FLUX-05 3-rule structure + D-15 patch example | pure grep against committed file | `tests/bats/create-clusters-05-tls-san.bats` (@test #1) + `tests/bats/create-clusters-01-network.bats` | exact (static-grep-only; no `require_live*`) |
| `Taskfile.yml` (append) | task-runner config (YAML) | declarative — single new task entry | existing entries in the same file (`build-image`, `create-clusters`, `delete-clusters`) | exact (in-file self-analog) |
| `clusters/hub-flux/flux-system/kustomization.yaml` (runtime-modified) | kustomize manifest (bootstrap-generated; augmented by Section 5 of `scripts/bootstrap-flux.sh` with a sentinel-guarded comment block) | file-I/O (idempotent prepend via grep-sentinel + awk/sed to temp + mv) | `scripts/create-clusters.sh` Section 1 drift-check idiom + Section 3 `create_cluster` guarded-section helper | role-match (no existing file-mutating-idempotent-prepend-with-sentinel exists yet — closest is the docker-network drift-check pattern) |

---

## Pattern Assignments

### `scripts/bootstrap-flux.sh` (orchestration script, imperative request-response)

**Analog:** `scripts/create-clusters.sh` (primary) + `scripts/delete-clusters.sh` (single-responsibility shape)

**Shebang + strict-mode + lib-source pattern** (from `scripts/create-clusters.sh` lines 1-23):

```bash
#!/usr/bin/env bash
# scripts/create-clusters.sh
#
# Idempotently creates the k8s-net Docker bridge network and the three k3d clusters
# (hub-flux, spoke-ml, spoke-apps) on a pinned shared network.
#
# Requirements satisfied: CLU-01, CLU-02, CLU-03, CLU-04, CLU-05
# Decisions honored:      D-07, D-08, D-09, D-11, D-12, D-13
#
# ...

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/preflight-lib.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/preflight-lib.sh"
```

**Phase 3 application (verbatim shape, Phase-3-specific REQ/D list + D-11 "NOT set -x" comment):**

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
# GITHUB_TOKEN on stdout/stderr).
#
# Usage:   bash scripts/bootstrap-flux.sh
# Pre-req: scripts/preflight.sh exits 0; kubectl context is k3d-hub-flux.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/preflight-lib.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/preflight-lib.sh"
```

---

**Section 1 (preflight delegation) pattern** (from `scripts/create-clusters.sh` lines 33-41):

```bash
# ---------- Section 0: Preflight gate ----------
section "Preflight gate"
if ! bash "${SCRIPT_DIR}/preflight.sh" > /tmp/preflight-$$.log 2>&1; then
  fail "preflight has blockers — run scripts/preflight.sh and fix before creating clusters.
     Log: /tmp/preflight-$$.log"
  exit 1
fi
pass "preflight green"
rm -f /tmp/preflight-$$.log
```

**Phase 3 application:** Reuse verbatim, retarget the `fail` remediation to the Phase-3 verb ("bootstrapping flux"):

```bash
section "Preflight gate"
if ! bash "${SCRIPT_DIR}/preflight.sh" > /tmp/preflight-$$.log 2>&1; then
  fail "preflight has blockers — run scripts/preflight.sh and fix before bootstrapping flux.
     Log: /tmp/preflight-$$.log"
  exit 1
fi
pass "preflight green"
rm -f /tmp/preflight-$$.log
```

---

**Section 2 (guarded sections / idempotency) pattern** (from `scripts/create-clusters.sh` lines 43-58):

```bash
section "k8s-net network"
if docker network inspect "$K8S_NET_NAME" >/dev/null 2>&1; then
  current_subnet="$(docker network inspect "$K8S_NET_NAME" -f '{{(index .IPAM.Config 0).Subnet}}' 2>/dev/null || echo "")"
  current_driver="$(docker network inspect "$K8S_NET_NAME" -f '{{.Driver}}' 2>/dev/null || echo "")"
  if [[ "$current_subnet" == "$K8S_NET_SUBNET" && "$current_driver" == "$K8S_NET_DRIVER" ]]; then
    info "already done, skipping: ${K8S_NET_NAME} (subnet=${current_subnet}, driver=${current_driver})"
  else
    fail "${K8S_NET_NAME} exists with drift (subnet=${current_subnet:-?}, driver=${current_driver:-?}; expected subnet=${K8S_NET_SUBNET}, driver=${K8S_NET_DRIVER}).
       Fix: scripts/delete-clusters.sh && scripts/create-clusters.sh"
    exit 1
  fi
else
  docker network create --driver "$K8S_NET_DRIVER" --subnet "$K8S_NET_SUBNET" "$K8S_NET_NAME" >/dev/null
  pass "creating: ${K8S_NET_NAME} (subnet=${K8S_NET_SUBNET}, driver=${K8S_NET_DRIVER})"
fi
```

**Phase 3 application:** D-06 context gate + D-07 three-part idempotency AND. The template translation is direct — substitute `docker network inspect` probes with `kubectl get ns` / `flux check` / `kubectl get deploy` probes; substitute "drift" with "healthy → skip; else fall through":

```bash
section "Context + idempotency checks"

# D-06: kubectl context gate (read-only assertion; NEVER auto-switch)
ctx="$(kubectl config current-context 2>/dev/null || echo "")"
if [[ "$ctx" != "k3d-hub-flux" ]]; then
  fail "kubectl context is ${ctx:-unset}, expected k3d-hub-flux.
     Fix: kubectl config use-context k3d-hub-flux"
  exit 1
fi
pass "kubectl context: k3d-hub-flux"

# D-07: three-part idempotency AND (ns exists AND flux check AND 4 controllers Available)
# Mirrors the Section 1 drift-vs-skip structure from create-clusters.sh.
if kubectl get ns flux-system >/dev/null 2>&1 \
   && flux --context k3d-hub-flux check >/dev/null 2>&1 \
   && [[ $(kubectl --context k3d-hub-flux -n flux-system get deploy --no-headers 2>/dev/null | wc -l) -eq 4 ]] \
   && kubectl --context k3d-hub-flux -n flux-system wait \
        --for=condition=Available deploy --all --timeout=5s >/dev/null 2>&1; then
  info "already done, skipping: flux bootstrap"
  # Still run Section 5 (patch marker is idempotent on its own) before exit 0.
  # OR: exit 0 here; planner picks per D-12 (test asserts log + exit 0).
  exit 0
fi
```

Note the **count guard** (Pitfall 4 from RESEARCH.md): `[[ $(... | wc -l) -eq 4 ]]` before `kubectl wait --all`, because `kubectl wait --all` on an empty set returns 0 trivially.

---

**Section 3 (flux bootstrap github invocation)** — no prior analog (Phase 3 is the first script to shell out to `flux`). Template from RESEARCH.md §Architecture Section 3:

```bash
section "flux bootstrap"

# D-11: source .env in a way that does NOT expose the token on argv.
# set -a; source; set +a exports every assignment without wrapping any in argv.
set -a
# shellcheck disable=SC1091
source "${REPO_ROOT}/.env"
set +a

# The --token-auth flag is a boolean toggle; flux reads GITHUB_TOKEN from env.
# Token is NEVER on argv; only the env-scoped pass-through `GITHUB_TOKEN="$GITHUB_TOKEN"`
# is used, and the receiving process inherits it via environ (not visible to `ps auxww`).
GITHUB_TOKEN="$GITHUB_TOKEN" flux bootstrap github \
  --owner "$GITHUB_OWNER" \
  --repository "$GITHUB_REPO" \
  --path clusters/hub-flux \
  --personal \
  --private=false \
  --network-policy=false \
  --token-auth \
  --branch main

pass "flux bootstrap github returned 0"
```

---

**Section 4 (post-bootstrap verification)** — composite of three primitives. Two have no direct analog (`flux check`, `flux get kustomizations`); one mirrors the SAN-verification bounded-retry pattern from `scripts/create-clusters.sh` lines 149-170:

```bash
section "Post-bootstrap verification"

# D-09 gate 1: flux check
if ! flux --context k3d-hub-flux check >/dev/null 2>&1; then
  fail "flux check failed post-bootstrap.
     Debug: flux --context k3d-hub-flux check
     Logs:  flux --context k3d-hub-flux logs"
  exit 1
fi
pass "flux check passed"

# D-09 gate 2 + Pitfall 4: require exactly 4 deployments, THEN kubectl wait
deploy_count="$(kubectl --context k3d-hub-flux -n flux-system get deploy --no-headers 2>/dev/null | wc -l)"
if [[ "$deploy_count" -ne 4 ]]; then
  fail "expected 4 flux controllers in flux-system, found ${deploy_count}.
     Fix: kubectl --context k3d-hub-flux -n flux-system get deploy,pod"
  exit 1
fi
if ! kubectl --context k3d-hub-flux -n flux-system wait \
       --for=condition=Available deploy --all --timeout=120s >/dev/null 2>&1; then
  fail "flux controllers did not reach Ready in 120s.
     Fix: kubectl -n flux-system get deploy,pod; flux logs"
  exit 1
fi
pass "4 flux controllers Available"

# D-09 gate 3: flux-system Kustomization Ready=True (Pitfall 5: exact-column match, not grep Ready)
ks_ready="$(flux --context k3d-hub-flux get kustomizations flux-system --no-header 2>/dev/null | awk '{print $3}')"
if [[ "$ks_ready" != "True" ]]; then
  fail "flux-system Kustomization not Ready=True (got: ${ks_ready:-unknown}).
     Fix: flux get kustomizations flux-system; flux logs --kind=Kustomization"
  exit 1
fi
pass "flux-system Kustomization Ready=True"
```

---

**Section 5 (patch-surface marker)** — idempotent prepend via grep-sentinel + awk/sed. No exact analog, but the guarded-skip shape comes from `scripts/create-clusters.sh` Section 1 (grep-for-state → info-skip / proceed):

```bash
section "Patch-surface marker"

KUSTOMIZATION_FILE="${REPO_ROOT}/clusters/hub-flux/flux-system/kustomization.yaml"
SENTINEL="# FLUX PATCH SURFACE"

if [[ ! -f "$KUSTOMIZATION_FILE" ]]; then
  fail "expected ${KUSTOMIZATION_FILE} after flux bootstrap, not found.
     Fix: ensure --path clusters/hub-flux was used; inspect the bootstrap commit."
  exit 1
fi

if grep -qF "$SENTINEL" "$KUSTOMIZATION_FILE"; then
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
#
# Peer files in this directory — gotk-components.yaml, gotk-sync.yaml —
# are bootstrap-managed and WILL be overwritten by `flux bootstrap`.
# Do NOT hand-edit them.
#
# See: docs/flux-hub-spoke.md
# ──────────────────────────────────────────────────────────────────────────
EOF
    cat "$KUSTOMIZATION_FILE"
  } > "$tmp"
  mv "$tmp" "$KUSTOMIZATION_FILE"
  pass "applied: patch-surface marker prepended to clusters/hub-flux/flux-system/kustomization.yaml"
fi
```

Remediation-rich `fail` on failure (from CONTEXT.md §specifics):

```bash
# Alternate failure path if the prepend itself errors:
fail "patch-surface marker failed to apply to ${KUSTOMIZATION_FILE}.
   Fix: manually prepend the comment block (canonical form in docs/flux-hub-spoke.md § Rule 2)."
```

---

**Summary footer pattern** (from `scripts/create-clusters.sh` lines 178-184):

```bash
# ---------- Summary ----------
section "Summary"
printf "  %s%d passed%s, %s%d warnings%s, %s%d failed%s\n" \
  "$C_GREEN" "$PASS" "$C_RESET" "$C_YELLOW" "$WARN" "$C_RESET" "$C_RED" "$FAIL" "$C_RESET"
if (( FAIL > 0 )); then exit 1; fi
printf "\n%sAll three clusters ready on ${K8S_NET_NAME}.%s\n" "$C_GREEN" "$C_RESET"
```

**Phase 3 application:** Same shape, Phase-3-specific success message:

```bash
section "Summary"
printf "  %s%d passed%s, %s%d warnings%s, %s%d failed%s\n" \
  "$C_GREEN" "$PASS" "$C_RESET" "$C_YELLOW" "$WARN" "$C_RESET" "$C_RED" "$FAIL" "$C_RESET"
if (( FAIL > 0 )); then exit 1; fi
printf "\n%sflux hub bootstrap complete — k3d-hub-flux is now GitOps-managed from %s/%s (clusters/hub-flux).%s\n" \
  "$C_GREEN" "$GITHUB_OWNER" "$GITHUB_REPO" "$C_RESET"
```

---

### `docs/flux-hub-spoke.md` (contract doc)

**Analog:** `docs/wsl-networking.md`

**Heading + intro structure** (from `docs/wsl-networking.md` lines 1-9):

```markdown
# WSL2 Networking: Mirrored Mode, NAT Mode, and the Migration Procedure

## What Is mirrored Mode and Why It Breaks Docker Custom Networks

WSL2 supports two networking modes: **NAT** (the default prior to Windows 11 22H2) and
**mirrored** (introduced in Windows 11 22H2). In mirrored mode, Windows host NICs are mirrored
directly into the WSL2 VM — the WSL2 instance shares the same IP addresses and network interfaces
as the Windows host.
```

**Phase 3 application:** Same top-level-heading + second-level-heading + paragraph-intro pattern. Planner fills the exact skeleton from CONTEXT.md §specifics (What `flux bootstrap` writes → Rule 1 → Rule 2 with D-15 example → Rule 3 → Rerun behavior → Phase-4 HTML-comment stub).

**Phase-4-stub pattern (HTML comment idiom)** — no exact analog in `docs/`; template from CONTEXT.md D-14:

```markdown
<!-- Phase 4: hub-spoke reconciliation (spec.kubeConfig, <spoke>-kubeconfig Secrets, value.yaml key) -->
```

**D-15 worked example (Kustomize patches: block)** — template from CONTEXT.md D-15:

```yaml
resources:
- gotk-components.yaml
- gotk-sync.yaml
patches:
- target:
    kind: Deployment
    name: kustomize-controller
    namespace: flux-system
  patch: |
    - op: replace
      path: /spec/template/spec/containers/0/resources/limits/memory
      value: 1Gi
```

**D-16 skip-message mention (one sentence)** — ties the doc to the script's observable behavior:

> Rerunning `scripts/bootstrap-flux.sh` on an already-bootstrapped hub logs `already done, skipping: flux bootstrap` and exits 0.

---

### `tests/bats/bootstrap-flux-01-idempotent.bats` (destructive live-gated bats test)

**Analog:** `tests/bats/delete-clusters-01-cache.bats` (verbatim shape)

**Header + load + setup pattern** (from `tests/bats/delete-clusters-01-cache.bats` lines 1-14):

```bash
#!/usr/bin/env bats
# tests/bats/delete-clusters-01-cache.bats
# Two-part check (CLU-06 / IMG-06 / D-14): static-grep that scripts/delete-clusters.sh carries the "INTENTIONALLY NOT calling" blocking comment AND L3 live-gated assertion that karyon/k3s-cuda image survives a teardown run.

load 'test_helper'

setup() {
  SCRIPT="${REPO_ROOT}/scripts/delete-clusters.sh"
}

teardown() {
  :
}
```

**Phase 3 application** (static `SCRIPT` wiring identical; header reflects FLUX-04 / D-11 / D-12):

```bash
#!/usr/bin/env bats
# tests/bats/bootstrap-flux-01-idempotent.bats
# Multi-part check (FLUX-01/02/03/04 / D-07 / D-11 / D-12):
#   - static-grep that scripts/bootstrap-flux.sh references FLUX-01/02/03,
#   - static-grep that the script uses `set -euo pipefail` and does NOT contain `set -x` (D-11),
#   - L3 live-destructive that two back-to-back runs produce an "already done, skipping: flux bootstrap" on run 2 and exit 0 (D-12).

load 'test_helper'

setup() {
  SCRIPT="${REPO_ROOT}/scripts/bootstrap-flux.sh"
}

teardown() {
  :
}
```

---

**Static-grep @test pattern** (from `tests/bats/delete-clusters-01-cache.bats` lines 16-20):

```bash
@test "CLU-06: delete-clusters.sh carries the D-14 INTENTIONALLY NOT calling blocking comment" {
  run grep -c 'INTENTIONALLY NOT calling' "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}
```

And negative-grep idiom from `tests/bats/create-clusters-05-tls-san.bats` lines 16-21:

```bash
@test "CLU-05: scripts/create-clusters.sh uses --k3s-arg --tls-san=k3d-NAME-server-0@server:* (wildcard nodefilter)" {
  run grep -F -- "--tls-san=k3d-\${name}-server-0@server:*" "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- "@server:0" "$SCRIPT"
  [ "$status" -ne 0 ]
}
```

**Phase 3 application** (FLUX-01/02/03 grep + D-11 no-`set -x` negative grep):

```bash
@test "FLUX-01: scripts/bootstrap-flux.sh invokes flux bootstrap github" {
  run grep -c 'flux bootstrap github' "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "FLUX-02: scripts/bootstrap-flux.sh pins --path clusters/hub-flux" {
  run grep -F -- '--path clusters/hub-flux' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "FLUX-03: scripts/bootstrap-flux.sh sources .env (GITHUB_OWNER/REPO/TOKEN contract)" {
  run grep -F -- 'source "${REPO_ROOT}/.env"' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "D-11: scripts/bootstrap-flux.sh uses set -euo pipefail and does NOT set -x" {
  run grep -E '^set -euo pipefail' "$SCRIPT"
  [ "$status" -eq 0 ]
  # Negative grep: no `set -x` line anywhere (D-11 token-safety).
  run grep -E '^[[:space:]]*set -[a-zA-Z]*x' "$SCRIPT"
  [ "$status" -ne 0 ]
}
```

---

**Live-destructive @test pattern** (from `tests/bats/delete-clusters-01-cache.bats` lines 25-31):

```bash
@test "CLU-06 (live/destructive): karyon/k3s-cuda image survives delete-clusters.sh" {
  require_live_destructive
  bash "${REPO_ROOT}/scripts/delete-clusters.sh" >/dev/null 2>&1 || true
  run bash -c "docker images karyon/k3s-cuda --format '{{.Repository}}' | grep -c '^karyon/k3s-cuda$'"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}
```

**Phase 3 application** (D-12 idempotency proof — run twice, assert skip-message + exit 0 on run 2):

```bash
@test "FLUX-04 (live/destructive): scripts/bootstrap-flux.sh is idempotent on rerun" {
  require_live_destructive
  # First invocation: may bootstrap or skip depending on cluster state. Tolerate either.
  bash "${REPO_ROOT}/scripts/bootstrap-flux.sh" >/dev/null 2>&1 || true

  # Second invocation MUST short-circuit on the D-07 three-part gate.
  run bash "${REPO_ROOT}/scripts/bootstrap-flux.sh"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "already done, skipping: flux bootstrap" ]]
}

# Bonus: Pitfall 9 validation — patch-surface marker survives re-bootstrap (run-2 still has sentinel).
@test "D-13 (live/destructive): patch-surface marker survives re-bootstrap" {
  require_live_destructive
  bash "${REPO_ROOT}/scripts/bootstrap-flux.sh" >/dev/null 2>&1 || true
  bash "${REPO_ROOT}/scripts/bootstrap-flux.sh" >/dev/null 2>&1 || true
  run grep -F "# FLUX PATCH SURFACE" "${REPO_ROOT}/clusters/hub-flux/flux-system/kustomization.yaml"
  [ "$status" -eq 0 ]
}
```

**Caveat:** `require_live_destructive` requires BOTH `KARYON_LIVE_TESTS=1` AND `KARYON_LIVE_TESTS_DESTRUCTIVE=1` (from `tests/bats/test_helper.bash` lines 45-49) — inherit verbatim.

---

### `tests/bats/bootstrap-flux-02-docs.bats` (static-grep-only bats test)

**Analog:** `tests/bats/create-clusters-05-tls-san.bats` (first @test — static-grep only; no `require_live*`)

**Shape** (verbatim from `create-clusters-05-tls-san.bats`):

```bash
#!/usr/bin/env bats
# tests/bats/create-clusters-05-tls-san.bats
# ...
load 'test_helper'

setup() {
  SCRIPT="${REPO_ROOT}/scripts/create-clusters.sh"
}

teardown() {
  :
}

@test "CLU-05: scripts/create-clusters.sh uses --k3s-arg --tls-san=k3d-NAME-server-0@server:* (wildcard nodefilter)" {
  run grep -F -- "--tls-san=k3d-\${name}-server-0@server:*" "$SCRIPT"
  [ "$status" -eq 0 ]
  ...
}
```

**Phase 3 application** (target: `docs/flux-hub-spoke.md`; FLUX-05 3-rule grep + D-15 patch example grep):

```bash
#!/usr/bin/env bats
# tests/bats/bootstrap-flux-02-docs.bats
# Static-grep check (FLUX-05 / DOCS-03 / D-14 / D-15 / D-16):
# docs/flux-hub-spoke.md carries the 3 patch-surface rules, the D-15 patches: example,
# the D-16 skip-message reference, and the Phase-4 HTML-comment stub.

load 'test_helper'

setup() {
  DOC="${REPO_ROOT}/docs/flux-hub-spoke.md"
}

teardown() {
  :
}

@test "FLUX-05: docs/flux-hub-spoke.md documents the 3 patch-surface rules" {
  [ -f "$DOC" ]
  # Rule 1: gotk-*.yaml bootstrap-managed
  run grep -F 'gotk-components.yaml' "$DOC"
  [ "$status" -eq 0 ]
  run grep -F 'gotk-sync.yaml' "$DOC"
  [ "$status" -eq 0 ]
  # Rule 2: kustomization.yaml IS the patch surface
  run grep -iE 'patch surface' "$DOC"
  [ "$status" -eq 0 ]
  # Rule 3: --path immutable after first run
  run grep -F -- '--path' "$DOC"
  [ "$status" -eq 0 ]
}

@test "D-15: docs/flux-hub-spoke.md contains the kustomize-controller memory patch example" {
  run grep -F 'kustomize-controller' "$DOC"
  [ "$status" -eq 0 ]
  run grep -F '/spec/template/spec/containers/0/resources/limits/memory' "$DOC"
  [ "$status" -eq 0 ]
}

@test "D-16: docs/flux-hub-spoke.md mentions the idempotency skip message" {
  run grep -F 'already done, skipping: flux bootstrap' "$DOC"
  [ "$status" -eq 0 ]
}

@test "D-14: docs/flux-hub-spoke.md carries the Phase 4 stub HTML comment" {
  run grep -F '<!-- Phase 4:' "$DOC"
  [ "$status" -eq 0 ]
}
```

---

### `Taskfile.yml` (append single task)

**Analog:** existing entries in the same file (self-analog).

**Existing pattern** (from `Taskfile.yml` lines 1-17, verbatim):

```yaml
version: '3'

tasks:
  build-image:
    desc: Build the karyon/k3s-cuda custom image (IMG-01..06)
    cmds:
      - bash scripts/build-image.sh

  create-clusters:
    desc: Create k8s-net + three k3d clusters (CLU-01..05)
    cmds:
      - bash scripts/create-clusters.sh

  delete-clusters:
    desc: Remove clusters + k8s-net; preserve karyon/k3s-cuda image (CLU-06, D-14)
    cmds:
      - bash scripts/delete-clusters.sh
```

**Phase 3 addition** (append 4 lines after `delete-clusters` block; REQ ref FLUX-01..04, no REPO-05 reorg per CONTEXT.md §code_context):

```yaml
  bootstrap-flux:
    desc: Bootstrap Flux GitOps on k3d-hub-flux from clusters/hub-flux/ (FLUX-01..04)
    cmds:
      - bash scripts/bootstrap-flux.sh
```

---

### `clusters/hub-flux/flux-system/kustomization.yaml` (runtime-modified)

**Analog:** no file-level analog (file is bootstrap-generated by `flux bootstrap` on first run). **Modification pattern** draws from two sources:

1. **Sentinel-guarded idempotent file mutation** — new-to-Phase-3; template shown inline in Section 5 of the `scripts/bootstrap-flux.sh` assignment above. The guard shape (`grep -qF "$SENTINEL" file && info skip; else { tmp=$(mktemp); { cat sentinel_block; cat file; } > "$tmp"; mv "$tmp" file; pass }`) mirrors the drift-check-or-create shape from `scripts/create-clusters.sh` Section 1.

2. **In-file comment-block content** — from CONTEXT.md D-13 (verbatim YAML block; no existing analog because this is the first comment-block-as-contract pattern in the repo).

---

## Shared Patterns

### Strict-mode + lib-sourcing preamble
**Source:** `scripts/create-clusters.sh` lines 17-23 (verbatim shape in `scripts/delete-clusters.sh` lines 13-19)
**Apply to:** `scripts/bootstrap-flux.sh`

```bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/preflight-lib.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/preflight-lib.sh"
```

**Phase-3 divergence:** Documenting the D-11 "intentionally NOT -x" choice in the top-of-file comment block is a Phase-3 addition; the `set -euo pipefail` line itself is unchanged.

---

### Output vocabulary (section / pass / warn / fail / info / have)
**Source:** `scripts/lib/preflight-lib.sh` lines 18-27
**Apply to:** every new script and every fail/skip message in bootstrap-flux.sh

```bash
PASS=0; WARN=0; FAIL=0
WARN_MSGS=(); FAIL_MSGS=()

section() { printf "\n%s%s== %s ==%s\n" "$C_BOLD" "$C_BLUE" "$1" "$C_RESET"; }
pass()    { printf "  %s✓%s %s\n" "$C_GREEN" "$C_RESET" "$1"; PASS=$((PASS+1)); }
warn()    { printf "  %s!%s %s\n" "$C_YELLOW" "$C_RESET" "$1"; WARN=$((WARN+1)); WARN_MSGS+=("$1"); }
fail()    { printf "  %s✗%s %s\n" "$C_RED" "$C_RESET" "$1"; FAIL=$((FAIL+1)); FAIL_MSGS+=("$1"); }
info()    { printf "  %s·%s %s\n" "$C_DIM" "$C_RESET" "$1"; }

have()    { command -v "$1" >/dev/null 2>&1; }
```

**Critical:** all 5 sections of `bootstrap-flux.sh` use these; specifically `info "already done, skipping: flux bootstrap"` on D-07 healthy-skip is the **exact string** the D-12 bats test asserts. Any wording drift breaks the test contract.

---

### Remediation-rich `fail` idiom
**Source:** `scripts/preflight.sh` lines 302-304; `scripts/create-clusters.sh` lines 107-109, 121-123; `scripts/delete-clusters.sh` lines 57-59
**Apply to:** every `fail` call in `scripts/bootstrap-flux.sh`

Existing exemplar (from `scripts/create-clusters.sh` lines 121-123):

```bash
fail "cluster ${name} API PORT drift (serverlb ports=${actual_ports:-?}, expected=6443/tcp=${port}).
   Fix: scripts/delete-clusters.sh && scripts/create-clusters.sh"
exit 1
```

**Phase-3 catalog** (from CONTEXT.md §specifics — each `fail` in bootstrap-flux.sh ends with an exact remediation command):

| Failure | Remediation surfaced in `fail` |
|---------|--------------------------------|
| preflight blockers | `run scripts/preflight.sh and fix before bootstrapping flux. Log: /tmp/preflight-$$.log` |
| kubectl context mismatch | `kubectl config use-context k3d-hub-flux` |
| `flux check` fails post-bootstrap | `flux --context k3d-hub-flux check; flux --context k3d-hub-flux logs` |
| controllers not Ready in 120s | `kubectl -n flux-system get deploy,pod; flux logs` |
| `flux-system` Kustomization not Ready=True | `flux get kustomizations flux-system; flux logs --kind=Kustomization` |
| kustomization.yaml patch-marker prepend failed | `manually prepend the comment block to clusters/hub-flux/flux-system/kustomization.yaml (docs/flux-hub-spoke.md § Rule 2 shows the canonical form)` |

---

### Guarded-sections idempotency (Phase 1 D-05, Phase 2 D-09 → Phase 3 D-07 / D-13)
**Source:** `scripts/create-clusters.sh` lines 43-58 (network drift-check), lines 84-138 (cluster drift-check); `scripts/delete-clusters.sh` lines 28-37 (cluster delete skip-if-missing)
**Apply to:** `scripts/bootstrap-flux.sh` Section 2 (D-07 three-part idempotency) + Section 5 (D-13 sentinel-guarded prepend)

**Canonical shape:**

```bash
if <state-probe>; then
  info "already done, skipping: <label>"
else
  <do-the-thing>
  pass "<verb-past-tense>: <label>"
fi
```

Phase 3 applications:
- Section 2 D-07: `<state-probe>` = three-part AND of `kubectl get ns` + `flux check` + `kubectl wait --for=Available`. Skip-label = `flux bootstrap`.
- Section 5 D-13: `<state-probe>` = `grep -qF "$SENTINEL" "$KUSTOMIZATION_FILE"`. Skip-label = `patch-surface marker present`.

---

### Summary footer + exit-code convention
**Source:** `scripts/create-clusters.sh` lines 179-184; `scripts/delete-clusters.sh` lines 64-68
**Apply to:** `scripts/bootstrap-flux.sh` tail

```bash
section "Summary"
printf "  %s%d passed%s, %s%d warnings%s, %s%d failed%s\n" \
  "$C_GREEN" "$PASS" "$C_RESET" "$C_YELLOW" "$WARN" "$C_RESET" "$C_RED" "$FAIL" "$C_RESET"
if (( FAIL > 0 )); then exit 1; fi
```

Counters (`PASS`/`WARN`/`FAIL`) come from `scripts/lib/preflight-lib.sh` line 18 — no separate declaration in `bootstrap-flux.sh`.

---

### Bats destructive-gated test shape
**Source:** `tests/bats/test_helper.bash` lines 45-49 + `tests/bats/delete-clusters-01-cache.bats` lines 25-31
**Apply to:** both new Phase-3 bats files, but especially `bootstrap-flux-01-idempotent.bats` (which runs the actual bootstrap twice)

```bash
# test_helper.bash:
require_live_destructive() {
  if [[ -z "${KARYON_LIVE_TESTS:-}" || -z "${KARYON_LIVE_TESTS_DESTRUCTIVE:-}" ]]; then
    skip "destructive live test — set KARYON_LIVE_TESTS=1 KARYON_LIVE_TESTS_DESTRUCTIVE=1 to run (tears down k3d clusters)"
  fi
}

# usage in *.bats:
@test "FLUX-04 (live/destructive): ..." {
  require_live_destructive
  bash "${REPO_ROOT}/scripts/bootstrap-flux.sh" >/dev/null 2>&1 || true
  run bash "${REPO_ROOT}/scripts/bootstrap-flux.sh"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "already done, skipping: flux bootstrap" ]]
}
```

No new test-helper function is required — reuse `require_live_destructive` verbatim.

---

### Bats static-grep test shape (no live gate)
**Source:** `tests/bats/create-clusters-05-tls-san.bats` (first @test), `tests/bats/create-clusters-01-network.bats`, `tests/bats/delete-clusters-01-cache.bats` (first @test)
**Apply to:** both Phase-3 bats files (all @tests in `bootstrap-flux-02-docs.bats`; pure-grep @tests in `bootstrap-flux-01-idempotent.bats`)

```bash
@test "<REQ-ID>: <assertion>" {
  run grep -F -- '<literal pattern>' "$SCRIPT_OR_DOC"
  [ "$status" -eq 0 ]
  # optional negative grep:
  run grep -F -- '<forbidden pattern>' "$SCRIPT_OR_DOC"
  [ "$status" -ne 0 ]
}
```

**Critical:** use `grep -F --` (fixed-string, end-of-options) for literal strings; `grep -E` only when regex is required. Matches the exact convention in `tests/bats/create-clusters-05-tls-san.bats`.

---

### D-11 token-safety discipline (anti-patterns)
**Source:** CONTEXT.md D-11 + RESEARCH.md Pitfall 1 + §Anti-Patterns
**Apply to:** `scripts/bootstrap-flux.sh` entire file

| DO | DO NOT |
|----|--------|
| `set -euo pipefail` | `set -x` anywhere (token visible in trace) |
| `set -a; source .env; set +a` | `echo "$GITHUB_TOKEN"` / `info "...$GITHUB_TOKEN..."` |
| `GITHUB_TOKEN="$GITHUB_TOKEN" flux bootstrap ...` (env-scoped pass-through, argv-clean) | `flux bootstrap --token "$GITHUB_TOKEN"` (argv leaks via `ps auxww`) |
| `--token-auth` as boolean flag | `--token-auth=$GITHUB_TOKEN` or `--token-auth "$GITHUB_TOKEN"` |
| stderr/stdout inherit default from flux | `... | tee /tmp/bootstrap.log` (logs may capture future token echoes) |

The bats negative-grep `grep -E '^[[:space:]]*set -[a-zA-Z]*x' "$SCRIPT"` enforces the no-`set -x` rule at test time.

---

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| (none) | — | — | All 5 files have at least a role-match analog. The closest gap is the **sentinel-guarded idempotent file prepend** idiom (Section 5 of `scripts/bootstrap-flux.sh`); partial analog is the `grep -qx` drift-check shape from `scripts/create-clusters.sh` Section 1, but the prepend-via-tmpfile-mv pattern itself is Phase-3-novel. RESEARCH.md Pitfall 9 flags validation risk (does the comment survive re-bootstrap?) — the D-13 bats test covers this as a validated invariant, not an assumption. |

---

## Metadata

**Analog search scope:** `scripts/` (7 shell scripts), `scripts/lib/` (1 shared lib), `tests/bats/` (16 bats suites + 1 test_helper), `docs/` (1 existing doc), `Taskfile.yml` (3 existing task entries).
**Files scanned:** 8 (read for pattern extraction) of ~25 candidate files.
**Pattern extraction date:** 2026-04-24.

**Key patterns identified (top 3):**
1. **Guarded-sections idempotency** — `if <state-probe>; then info "already done, skipping: <label>"; else <act>; pass "<verb>: <label>"; fi` is the project's canonical idempotency idiom. Phase 3 D-07 (whole-script short-circuit) and D-13 (per-section sentinel skip) are two applications of the same shape.
2. **Remediation-rich `fail`** — every `fail` in the repo ends with an exact next-step command (e.g., `Fix: kubectl config use-context k3d-hub-flux`). Phase 3 has a 6-entry catalog above; any new `fail` must follow this.
3. **`scripts/lib/preflight-lib.sh` is the single source of truth** for output vocabulary + counters + `have()`. Sourced by all scripts and by every bats suite via `test_helper.bash`. No duplicate helpers; no output outside `section/pass/warn/fail/info`.
