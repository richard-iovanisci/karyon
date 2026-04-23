# Phase 2: Cluster Layer - Pattern Map

**Mapped:** 2026-04-23
**Files analyzed:** 17 new/modified files (4 image artifacts + 3 scripts + 1 Taskfile stub + 11 bats files + 1 bats helper extension)
**Analogs found:** 14 / 17 (3 are greenfield image artifacts with no in-repo analog — drop-in bodies already sit verbatim in RESEARCH.md §2)

---

## File Classification

### Image artifacts (new)

| New File | Role | Data Flow | Closest Analog | Match Quality |
|----------|------|-----------|----------------|---------------|
| `images/Dockerfile.k3s-cuda` | container-image build recipe | static file (consumed by BuildKit) | RESEARCH.md §2.1 (drop-in body) | no code analog — external canonical (k3d CUDA reference + k3s source) |
| `images/config.toml.tmpl` | containerd config template (consumed by k3s agent) | static file baked into image | RESEARCH.md §2.2 (drop-in body) | no code analog — external canonical (k3s `ContainerdConfigTemplateV3`) |
| `images/device-plugin-daemonset.yaml` | Kubernetes DaemonSet + RuntimeClass manifest | static YAML baked into image | RESEARCH.md §2.3 (drop-in body) | no code analog — external canonical (NVIDIA/k8s-device-plugin v0.17.4 static manifest) |
| `images/image-tag.sh` | utility script (tag-string emitter) | read Dockerfile ARG → echo to stdout | `prereqs.sh` (shebang + set) + RESEARCH.md §2.4 (body) | style-match only |

### Imperative scripts (new)

| New File | Role | Data Flow | Closest Analog | Match Quality |
|----------|------|-----------|----------------|---------------|
| `scripts/create-clusters.sh` | installer / orchestrator | side-effecting (docker, k3d, openssl) | `scripts/install-docker.sh` | exact — same guarded-sections + helper-sourcing + remediation style |
| `scripts/build-image.sh` | installer / builder wrapper | side-effecting (docker build) | `scripts/install-docker.sh` + RESEARCH.md §3.2 | exact — same shebang / helpers / section / pass / summary skeleton |
| `scripts/delete-clusters.sh` | teardown / reverser | side-effecting (k3d delete, docker network rm) + post-run verify | `scripts/install-docker.sh` (structure) + RESEARCH.md §3.3 | exact — same structure, loop over targets instead of guarded install |

### Taskfile stub (new — Claude's Discretion resolved YES per RESEARCH §7 item 2)

| New File | Role | Data Flow | Closest Analog | Match Quality |
|----------|------|-----------|----------------|---------------|
| `Taskfile.yml` | task-runner config (go-task v3) | declarative YAML | none in repo | no analog — external canonical (taskfile.dev v3 schema) |

### Bats test suites (new — 11 files)

| New File | Role | Data Flow | Closest Analog | Match Quality |
|----------|------|-----------|----------------|---------------|
| `tests/bats/cuda-image-01-base.bats` | unit test (static Dockerfile parse + L2 docker inspect) | bats-core read-only | `tests/bats/preflight-pre09.bats` | style-match (bats skeleton); target differs |
| `tests/bats/cuda-image-02-args.bats` | unit test (grep `ARG K3S_TAG=` defaults) | bats-core read-only | `tests/bats/preflight-pre09.bats` | style-match |
| `tests/bats/cuda-image-03-containerd.bats` | integration-ish (docker run --entrypoint cat on tmpl) | live-gated | `tests/bats/preflight-pre09.bats` | style-match + live-gate |
| `tests/bats/cuda-image-04-device-plugin.bats` | integration-ish (manifest body presence + path) | live-gated | `tests/bats/preflight-pre09.bats` | style-match + live-gate |
| `tests/bats/cuda-image-05-manifest-path.bats` | integration-ish (fixture path `/var/lib/rancher/k3s/server/manifests/`) | live-gated | `tests/bats/preflight-pre09.bats` | style-match + live-gate |
| `tests/bats/create-clusters-01-network.bats` | unit (mocked docker network inspect / create) | bats-core read-only | `tests/bats/preflight-pre09.bats` | style-match + mocks (bats-mock not yet wired; see Shared Patterns) |
| `tests/bats/create-clusters-02-hub-flux.bats` | integration (live kubectl) | live-gated | `tests/bats/preflight-pre09.bats` | style-match + live-gate |
| `tests/bats/create-clusters-03-spoke-ml.bats` | integration (live kubectl + nvidia.com/gpu) | live-gated | `tests/bats/preflight-pre09.bats` | style-match + live-gate |
| `tests/bats/create-clusters-04-spoke-apps.bats` | integration (live kubectl) | live-gated | `tests/bats/preflight-pre09.bats` | style-match + live-gate |
| `tests/bats/create-clusters-05-tls-san.bats` | unit (static grep of helper) + L4 (openssl probe) | live-gated | `tests/bats/preflight-pre09.bats` | style-match + live-gate |
| `tests/bats/delete-clusters-01-cache.bats` | integration (docker images after teardown) | live-gated | `tests/bats/preflight-pre09.bats` | style-match + live-gate |

### Helper extension (modified)

| Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---------------|------|-----------|----------------|---------------|
| `tests/bats/test_helper.bash` | bats shared loader | sources `preflight-lib.sh`; extend with cluster-test helpers + live-gate function | itself (lines 1-15) | exact — append-only |

---

## Pattern Assignments

### `images/Dockerfile.k3s-cuda` (container-image build recipe, static)

**Analog:** None in repo. Body is drop-in ready in RESEARCH.md §2.1 lines 294-373.
**Instruction:** Write the file verbatim from RESEARCH.md §2.1. Do NOT hand-rewrite.

Three non-negotiable invariants, each traceable to a locked decision:

**Locked ARG defaults (D-03 / A2 confirmed v0.17.4):**
```dockerfile
ARG K3S_TAG=v1.34.6-k3s1
ARG CUDA_TAG=12.8.1-base-ubuntu22.04
ARG DEVICE_PLUGIN_VERSION=v0.17.4
```

**Two-stage FROM (IMG-01):**
```dockerfile
FROM rancher/k3s:${K3S_TAG} AS k3s
FROM nvidia/cuda:${CUDA_TAG}
```

**Baked-artifact COPY destinations (D-05 / IMG-05):**
```dockerfile
COPY images/config.toml.tmpl /var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl
COPY images/device-plugin-daemonset.yaml /var/lib/rancher/k3s/server/manifests/nvidia-device-plugin-daemonset.yaml
```

**BuildKit frontend directive (enables `COPY --from=k3s / / --exclude=/bin`):**
```dockerfile
# syntax=docker/dockerfile:1.7-labs
```

**Top-of-file 3-part GPU contract comment** — verbatim from RESEARCH.md §2.1 lines 298-309. This is the canonical in-repo documentation of the contract and must ship as-is.

---

### `images/config.toml.tmpl` (containerd config template, static)

**Analog:** None in repo. Body is drop-in ready in RESEARCH.md §2.2 lines 395-431.
**Instruction:** Write verbatim from RESEARCH.md §2.2. Do NOT hand-author — the template extension pattern is non-obvious and any deviation risks containerd 2.0 silently rejecting v2 syntax.

**Minimal override body (D-05):**
```toml
{{ template "base" . }}

# Override: default_runtime_name = "nvidia" (unconditional).
[plugins.'io.containerd.cri.v1.runtime'.containerd]
  default_runtime_name = "nvidia"
```

Header block (lines 396-421 of RESEARCH.md) documents the 3-part contract and the template-extension rationale (cites `docs.k3s.io/advanced` "You can extend the K3s base template instead of copy-pasting…"). Ship the header verbatim — it is the in-repo pedagogical artifact that preserves Why-This-Is-Minimal context for future maintainers.

---

### `images/device-plugin-daemonset.yaml` (K8s manifest, static)

**Analog:** None in repo. Body is drop-in ready in RESEARCH.md §2.3 lines 454-533.
**Instruction:** Write verbatim from RESEARCH.md §2.3. Source of truth is `NVIDIA/k8s-device-plugin/blob/v0.17.4/deployments/static/nvidia-device-plugin.yml` with the documented argument set.

**Non-negotiable elements:**
- `apiVersion: node.k8s.io/v1` / `kind: RuntimeClass` / `handler: nvidia` — RuntimeClass resource ships alongside the DaemonSet (v1 RuntimeClass-first flow; see D-01).
- `image: nvcr.io/nvidia/k8s-device-plugin:v0.17.4` — hard-coded pin. Drift with Dockerfile ARG is caught in code review.
- `runtimeClassName: nvidia` on the pod spec.
- Exact arg list: `--mig-strategy=none`, `--fail-on-init-error=true`, `--pass-device-specs=false`, `--device-list-strategy=envvar` (rationale locked in RESEARCH.md §2.3 flag-rationale block lines 537-541).
- Full tolerations block (lines 496-507) for the k3s single-node `master` / `control-plane` taints.

---

### `images/image-tag.sh` (utility script, echo-to-stdout)

**Analog:** `prereqs.sh` (shebang + set stance only) + RESEARCH.md §2.4 (full body).
**Instruction:** Copy body verbatim from RESEARCH.md §2.4 lines 546-583. Matches Phase 1 shebang convention.

**Shebang + set-stance pattern** (`prereqs.sh` line 1 / `scripts/install-tools.sh` line 11):
```bash
#!/usr/bin/env bash
set -euo pipefail
```

Use `set -euo pipefail` (imperative-script stance from Phase 1 D-05), NOT `set -u` (preflight-only).

**SCRIPT_DIR resolution** — standard Phase 1 pattern used in every existing script:
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
```
Reference: `scripts/install-docker.sh` line 15, `scripts/install-tools.sh` line 13, `scripts/preflight.sh` line 12.

**Parse strategy** (RESEARCH.md §2.4 lines 571-583):
```bash
K3S_TAG="$(grep -E '^ARG K3S_TAG=' "$DOCKERFILE" | head -1 | cut -d= -f2)"
CUDA_TAG="$(grep -E '^ARG CUDA_TAG=' "$DOCKERFILE" | head -1 | cut -d= -f2)"
CUDA_TAG_SHORT="${CUDA_TAG%%-*}"
printf '%s\n' "karyon/k3s-cuda:${K3S_TAG}-cuda${CUDA_TAG_SHORT}"
```

**Divergence from other scripts:** does NOT `source preflight-lib.sh`. Must be safe to invoke via `$(...)` substitution with zero side effects and single-line stdout — sourcing the ANSI-color block would leak colors into the captured string. This is by design.

---

### `scripts/create-clusters.sh` (installer / orchestrator, side-effecting)

**Analog:** `scripts/install-docker.sh` (structure) + RESEARCH.md §3.1 (skeleton lines 603-753).
**Instruction:** Use RESEARCH.md §3.1 as the base skeleton; map every section to a Phase 1 analog pattern for the helper/guard idiom.

**Shebang + set-stance + SCRIPT_DIR/REPO_ROOT + source lib** — copy verbatim from `install-docker.sh` lines 1-18 (substitute description):
```bash
#!/usr/bin/env bash
# scripts/create-clusters.sh
# <description>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/preflight-lib.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/preflight-lib.sh"
```

**`readonly` constants block** — new pattern (no Phase 1 analog uses `readonly` explicitly, but matches style of `install-tools.sh` line 19 `ASDF_VERSION=...` top-of-file pins). Constants must sit directly after the `source` line so they are visible to every section. Body from RESEARCH.md §3.1 lines 629-634:
```bash
readonly K8S_NET_NAME="k8s-net"
readonly K8S_NET_SUBNET="172.30.0.0/16"
readonly K8S_NET_DRIVER="bridge"
readonly K3S_STOCK_IMAGE="rancher/k3s:v1.34.6-k3s1"
readonly CUDA_IMAGE_TAG="$("${REPO_ROOT}/images/image-tag.sh")"
```

**Preflight-gate section** — new pattern (integration point documented in CONTEXT.md `<code_context>` lines 122-123). Body from RESEARCH.md §3.1 lines 636-643:
```bash
section "Preflight gate"
if ! bash "${SCRIPT_DIR}/preflight.sh" > /tmp/preflight-$$.log 2>&1; then
  fail "preflight has blockers — run scripts/preflight.sh and fix before creating clusters.
     Log: /tmp/preflight-$$.log"
  exit 1
fi
pass "preflight green"
rm -f /tmp/preflight-$$.log
```

**Guarded-section idiom for `k8s-net`** — same pattern as `install-docker.sh` lines 63-75 (docker apt repo content-correct guard). Drift-detection via `docker network inspect -f` rather than file-exists. Body from RESEARCH.md §3.1 lines 646-660:
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
**Direct analog:** `scripts/install-docker.sh` Section 3 (lines 62-75) uses identical "verify exact content, not just presence" pattern (`grep -Fxq` check → fail/skip/install branches).

**`create_cluster()` helper function** — the single-most-important pattern in this phase. Body from RESEARCH.md §3.1 lines 680-739. Structure:
```bash
create_cluster() {
  local name="$1" port="$2"
  shift 2
  local extra_args=("$@")

  section "${name} cluster"

  # 1. Idempotency: k3d list + docker inspect drift check (D-09)
  # 2. Create with --k3s-arg '--tls-san=k3d-${name}-server-0@server:*' (CLU-05)
  # 3. D-13 SAN verification via openssl s_client | x509 | grep
  # 4. On SAN miss: k3d cluster delete + fail loudly
}
```
Three call-sites at the bottom (RESEARCH.md §3.1 lines 742-744):
```bash
create_cluster hub-flux   6443 --image "$K3S_STOCK_IMAGE"
create_cluster spoke-ml   6444 --image "$CUDA_IMAGE_TAG" --gpus all
create_cluster spoke-apps 6445 --image "$K3S_STOCK_IMAGE"
```

**openssl SAN verification block (D-13)** — no Phase 1 analog (this is a new kind of check). Body from RESEARCH.md §3.1 lines 724-738:
```bash
local expected_san="k3d-${name}-server-0"
if openssl s_client -connect "127.0.0.1:${port}" -servername "$expected_san" </dev/null 2>/dev/null \
     | openssl x509 -noout -text 2>/dev/null \
     | grep -qE "DNS:${expected_san}"; then
  pass "SAN verified: cluster ${name} cert includes DNS:${expected_san}"
else
  warn "deleting broken cluster ${name} (SAN missing)"
  k3d cluster delete "$name" >/dev/null 2>&1 || true
  fail "cluster ${name} apiserver cert missing SAN DNS:${expected_san} (k3d issue #1613 may be firing).
     Fix: confirm --k3s-arg '--tls-san=k3d-${name}-server-0@server:*' syntax in create_cluster helper;
          the cluster has been deleted — rerun scripts/create-clusters.sh"
  exit 1
fi
```

**Summary block** — copy verbatim from `scripts/install-docker.sh` lines 207-216. Same counter-reporting format every Phase 1 script uses. Body from RESEARCH.md §3.1 lines 747-752.

---

### `scripts/build-image.sh` (builder wrapper, side-effecting)

**Analog:** `scripts/install-docker.sh` (structure) + RESEARCH.md §3.2 (full body lines 757-817).
**Instruction:** Port RESEARCH.md §3.2 verbatim; no divergence from pattern.

**Shebang + helpers + SCRIPT_DIR/REPO_ROOT** — identical to `install-docker.sh` lines 1-18 (use Dockerfile `.sh` suffix in description).

**Sanity-check section** — new pattern but identical idiom to `install-docker.sh` Section 7 lines 191-194 (`[[ ! -f "$UNIT_SRC" ]] && fail`). Body from RESEARCH.md §3.2 lines 779-786:
```bash
section "Build context sanity"
for required in images/Dockerfile.k3s-cuda images/config.toml.tmpl images/device-plugin-daemonset.yaml images/image-tag.sh; do
  if [[ ! -f "${REPO_ROOT}/${required}" ]]; then
    fail "${required} missing — cannot build karyon/k3s-cuda"
    exit 1
  fi
done
pass "required files present"
```

**BuildKit availability section** — same `have`-style check as Phase 1:
```bash
section "BuildKit availability"
if ! docker buildx version >/dev/null 2>&1; then
  fail "docker buildx not available — install docker-buildx-plugin (Phase 1 install-docker.sh should have done this)"
  exit 1
fi
pass "docker buildx ready"
```
**Analog:** `scripts/install-docker.sh` Section 4 uses `dpkg -s docker-ce >/dev/null 2>&1` — same style (run-and-exit-code, not version parse).

**Build invocation** (RESEARCH.md §3.2 lines 799-807):
```bash
TAG="$("${REPO_ROOT}/images/image-tag.sh")"
info "tag: ${TAG}"

cd "$REPO_ROOT"
DOCKER_BUILDKIT=1 docker build \
  --progress=plain \
  --tag "$TAG" \
  -f images/Dockerfile.k3s-cuda \
  .
pass "built: ${TAG}"
```
Note: no `--build-arg` flags — Dockerfile ARG defaults ARE the pins (D-06 single-source-of-truth). This is intentional.

**Summary block** — identical to `install-docker.sh` lines 207-216.

---

### `scripts/delete-clusters.sh` (teardown / reverser, side-effecting + post-verify)

**Analog:** `scripts/install-docker.sh` (structure) + RESEARCH.md §3.3 (full body lines 822-889).
**Instruction:** Port RESEARCH.md §3.3 verbatim. The top-of-file blocking comment is D-14 and must ship exactly as written.

**Top-of-file blocking comment (D-14 — exact text required)** — this is the one pattern that has NO Phase 1 analog and MUST ship verbatim from RESEARCH.md §3.3 lines 823-827:
```bash
#!/usr/bin/env bash
# scripts/delete-clusters.sh
#
# INTENTIONALLY NOT calling `docker system prune` or `docker builder prune`.
# CUDA build layers must survive the `task rebuild` SLO (REQ-DESTROY-03).
# A lint in Phase 6 (REQ-DESTROY-04) will enforce this across scripts/.
```
The Phase 6 lint (REQ-DESTROY-04) will `grep -c 'INTENTIONALLY NOT calling'` against this file — verification row 5.3 in RESEARCH.md §5 expects count 1.

**Teardown loop** (RESEARCH.md §3.3 lines 849-858) — analog is any loop in Phase 1 over `for plugin in ...` (e.g. `install-tools.sh` — see RESEARCH.md Phase 1 PATTERNS.md pattern `asdf plugins`). Pattern is: pre-check with grep, then invoke action, log `pass` or `info skipping`.
```bash
section "k3d clusters"
for name in hub-flux spoke-ml spoke-apps; do
  if k3d cluster list --no-headers 2>/dev/null | awk '{print $1}' | grep -qx "$name"; then
    info "deleting: cluster ${name}"
    k3d cluster delete "$name" >/dev/null
    pass "deleted: cluster ${name}"
  else
    info "already done, skipping: cluster ${name} (not present)"
  fi
done
```

**Post-run survival verification (D-14)** — new kind of check (Phase 1 had no reversers). Body from RESEARCH.md §3.3 lines 874-882:
```bash
section "Build cache defense"
if docker images "$CUDA_IMAGE_TAG" --format '{{.Repository}}:{{.Tag}}' | grep -qx "$CUDA_IMAGE_TAG"; then
  pass "karyon/k3s-cuda image survived teardown (expected: ${CUDA_IMAGE_TAG})"
else
  fail "karyon/k3s-cuda image ${CUDA_IMAGE_TAG} is missing after teardown — a prune path slipped in.
     Audit: grep -rE 'docker (system|builder) prune' scripts/
     Rebuild: scripts/build-image.sh"
  exit 1
fi
```

**Summary block** — identical to `install-docker.sh` lines 207-216.

---

### `Taskfile.yml` (task-runner config, declarative YAML)

**Analog:** None in repo.
**Instruction:** Stub with three entries only — `build-image`, `create-clusters`, `delete-clusters`. Each is a one-liner invoking the corresponding `scripts/*.sh`. Phase 6 owns the full REPO-05 reorganization; do NOT expand the scope here.

**Minimum stub content** (taskfile.dev v3 schema):
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

**Rationale** — locked by RESEARCH.md §7 item 2 (researcher-recommended; CONTEXT.md `<decisions>` Claude's Discretion). No `Taskfile.yml` exists today (`ls /home/rich/code/gsd/karyon/` confirms absent). Phase 5 will extend this file; Phase 6 audits it. Keep the stub tight.

---

### `tests/bats/cuda-image-*.bats` (5 files, image-level bats suites)

**Analog:** `tests/bats/preflight-pre09.bats` (test-framework skeleton).
**Instruction:** Use the `preflight-pre09.bats` skeleton for all 5. Test bodies vary per target; framework is invariant.

**Shared bats skeleton** (from `tests/bats/preflight-pre09.bats` lines 1-14):
```bash
#!/usr/bin/env bats
# tests/bats/cuda-image-01-base.bats
# <description>

load 'test_helper'

setup() {
  # per-test setup (tmpdirs, env vars) if needed
}

teardown() {
  # cleanup
}

@test "<REQ-ID>: <behavior>" {
  run <command>
  [ "$status" -eq 0 ]
  [[ "$output" =~ "<expected>" ]]
}
```

**Per-file target mapping** (tests map to REQs per RESEARCH.md §6 lines 994-1007):

| File | REQ | Test strategy | Live-gate? |
|------|-----|---------------|------------|
| `cuda-image-01-base.bats` | IMG-01 | Static: `grep 'FROM nvidia/cuda' images/Dockerfile.k3s-cuda`. Live (L2): `docker inspect karyon/k3s-cuda:<tag> --format '{{range .RootFS.Layers}}...'` for layer count > 8 | YES for L2 block |
| `cuda-image-02-args.bats` | IMG-02 | Pure static: `grep -E '^ARG K3S_TAG=v1.34.6-k3s1' images/Dockerfile.k3s-cuda` | NO (static) |
| `cuda-image-03-containerd.bats` | IMG-03 | L2: `docker run --rm --entrypoint cat <tag> /var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl | grep -c 'default_runtime_name = "nvidia"'` | YES |
| `cuda-image-04-device-plugin.bats` | IMG-04 | Static: `grep -c 'v0.17.4' images/device-plugin-daemonset.yaml`. L2: `docker run ... /var/lib/rancher/k3s/server/manifests/nvidia-device-plugin-daemonset.yaml | grep 'kind: DaemonSet'` | YES for L2 |
| `cuda-image-05-manifest-path.bats` | IMG-05 | L2: same docker-run cat but asserting exact file path `/var/lib/rancher/k3s/server/manifests/nvidia-device-plugin-daemonset.yaml` exists | YES |

All commands above map directly to RESEARCH.md §5 verification rows 1.1-1.6.

---

### `tests/bats/create-clusters-*.bats` (5 files, cluster-level bats suites)

**Analog:** `tests/bats/preflight-pre09.bats` (skeleton) + RESEARCH.md §5 §6 (commands).

| File | REQ | Test strategy | Live-gate? |
|------|-----|---------------|------------|
| `create-clusters-01-network.bats` | CLU-01 | Static: grep helper body in `scripts/create-clusters.sh` for `--subnet "172.30.0.0/16"`. (No bats-mock wiring yet — see Shared Patterns; mocking docker CLI deferred to Phase 6 test-hygiene pass.) | NO |
| `create-clusters-02-hub-flux.bats` | CLU-02 | L3: `kubectl --context k3d-hub-flux get nodes --no-headers | grep -c Ready` == 1 | YES |
| `create-clusters-03-spoke-ml.bats` | CLU-03 | L3: `kubectl --context k3d-spoke-ml get nodes -o jsonpath='{.items[*].status.capacity.nvidia\.com/gpu}'` ≥ 1 | YES |
| `create-clusters-04-spoke-apps.bats` | CLU-04 | L3: `kubectl --context k3d-spoke-apps get nodes --no-headers | grep -c Ready` == 1 | YES |
| `create-clusters-05-tls-san.bats` | CLU-05 | Static: grep `scripts/create-clusters.sh` for `'--tls-san=k3d-${name}-server-0@server:*'` literal. L4: `openssl s_client … | x509 | grep 'DNS:k3d-hub-flux-server-0'` per port 6443/6444/6445 | YES for L4 |

Verification-command bodies all sit verbatim in RESEARCH.md §5 tables 2 and 3.

---

### `tests/bats/delete-clusters-01-cache.bats` (1 file, image-survival suite)

**Analog:** `tests/bats/preflight-pre09.bats` (skeleton).

| File | REQ | Test strategy | Live-gate? |
|------|-----|---------------|------------|
| `delete-clusters-01-cache.bats` | CLU-06 / IMG-06 / D-14 | L3: after `bash scripts/delete-clusters.sh`, assert `docker images karyon/k3s-cuda --format '{{.Repository}}:{{.Tag}}'` contains tag. Static: `grep -c 'INTENTIONALLY NOT calling' scripts/delete-clusters.sh` == 1 | YES for L3 |

Commands from RESEARCH.md §5 verification rows 4.3 and 5.3.

---

### `tests/bats/test_helper.bash` (modified — append-only)

**Analog:** itself (existing lines 1-15).
**Instruction:** DO NOT modify existing lines 1-15. Append after line 15.

**Existing content preserved (read-only)** — lines 1-15 already:
```bash
# tests/bats/test_helper.bash
# Shared loader for preflight bats suites.
# ...
SCRIPTS_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME:-$0}")/../.." && pwd)/scripts"
source "${SCRIPTS_DIR}/lib/preflight-lib.sh"
```

**Append block** (planner to write, body derived from RESEARCH.md §6 "Wave 0" live-gate convention):
```bash
# -----------------------------------------------------------------------------
# Cluster-layer (Phase 2) extensions
# -----------------------------------------------------------------------------

# REPO_ROOT resolves the top of the repo from any bats suite.
REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME:-$0}")/../.." && pwd)"

# IMAGES_DIR: where Dockerfile.k3s-cuda, config.toml.tmpl, etc. live.
IMAGES_DIR="${REPO_ROOT}/images"

# cuda_image_tag: emits the canonical CUDA image tag via images/image-tag.sh.
# Single source of truth matches D-06.
cuda_image_tag() {
  bash "${IMAGES_DIR}/image-tag.sh"
}

# require_live: skip the test unless KARYON_LIVE_TESTS is set.
# L3/L4 tests (those that need Docker + k3d + a live cluster or GPU) call this
# in setup() so per-commit CI skips them and final verifier runs them explicitly.
# Mirrors RESEARCH.md §6 Wave 0 live-gate pattern.
require_live() {
  if [[ -z "${KARYON_LIVE_TESTS:-}" ]]; then
    skip "live test — set KARYON_LIVE_TESTS=1 to run (requires docker + k3d + GPU for some suites)"
  fi
}
```

**Invariant:** The existing `source "${SCRIPTS_DIR}/lib/preflight-lib.sh"` line must remain first-effect so the helper vocabulary (`pass`/`fail`/etc.) stays available for any new unit tests that use it. Phase 2 extensions append below; they do not replace.

---

## Shared Patterns

### Shebang and `set` stance for imperative scripts
**Source:** `scripts/install-docker.sh` line 1+13 (`#!/usr/bin/env bash` + `set -euo pipefail`).
**Apply to:** `scripts/create-clusters.sh`, `scripts/build-image.sh`, `scripts/delete-clusters.sh`, `images/image-tag.sh`.

Use `set -euo pipefail` (NOT `set -u`). Preflight is the ONLY script that uses `set -u`-only stance. Phase 2 scripts are all imperative side-effecting installers; fail-fast is required (D-08 / D-10).

### `SCRIPT_DIR` + `REPO_ROOT` + `source lib` preamble
**Source:** `scripts/install-docker.sh` lines 15-18.
**Apply to:** All Phase 2 `scripts/*.sh` EXCEPT `images/image-tag.sh` (which must not source the lib — it's called via command substitution and ANSI colors would corrupt the captured string).
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/preflight-lib.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/preflight-lib.sh"
```

### Vocabulary inherited verbatim from `preflight-lib.sh`
**Source:** `scripts/lib/preflight-lib.sh` lines 21-27.
**Apply to:** All Phase 2 `scripts/*.sh` that source the lib.

Use ONLY these: `section`, `pass`, `warn`, `fail`, `info`, `have`. Never invent new helpers (e.g. do NOT add `error()` or `note()` — it fragments the interface). If a Phase 2 behavior doesn't fit these six, change the behavior, not the vocabulary.

### Guarded-sections idiom (D-09 / D-12 / Phase 1 D-05)
**Source:** `scripts/install-docker.sh` Sections 2-7 (lines 48-203) — five exemplar guarded sections.
**Apply to:** `scripts/create-clusters.sh` (all sections), `scripts/build-image.sh` (sanity + buildx), `scripts/delete-clusters.sh` (teardown loop).

Every logical step:
1. State-check guard (file exists? network matches? image tagged? cluster listed? + drift verification)
2. If already done with correct config: `info "already done, skipping: <what>"`
3. If drift detected: `fail "<what> drift (...) → <remediation>"` + `exit 1`
4. If absent: perform action, then `pass "creating/installing/deleting: <what>"`

**Phase 2 refinement over Phase 1:** the "drift detected" branch (step 3) is explicit — Phase 1 typically only had present/absent. `create-clusters.sh` k8s-net section and `create_cluster()` helper both branch into the drift case with remediation pointing at `delete-clusters.sh`.

### Remediation-rich `fail` messages
**Source:** `scripts/install-docker.sh` Section 7 line 192 (`fail "config/hwclock-resume.service not found at ${UNIT_SRC} — run from repo root..."`); Phase 1 PATTERNS.md §Shared Patterns.
**Apply to:** EVERY `fail()` call in every Phase 2 script.

Mandatory failure messages and their exact remediation tails (from CONTEXT.md `<specifics>` lines 149-154):
- `k8s-net subnet drift → scripts/delete-clusters.sh && scripts/create-clusters.sh`
- `k3d missing or version drift → scripts/install-tools.sh`
- `karyon/k3s-cuda image missing → scripts/build-image.sh (or docker build -f images/Dockerfile.k3s-cuda)`
- `--tls-san missing on cert → check --k3s-arg syntax; cluster was deleted, rerun scripts/create-clusters.sh after fixing`
- `CUDA image deleted after destroy → scripts/delete-clusters.sh hit a prune path; audit the script`

### Summary block — per-script counters + exit code
**Source:** `scripts/install-docker.sh` lines 207-216 (identical to `preflight.sh` lines 432-456 and `install-tools.sh`).
**Apply to:** `scripts/create-clusters.sh`, `scripts/build-image.sh`, `scripts/delete-clusters.sh`.
```bash
section "Summary"
printf "  %s%d passed%s, %s%d warnings%s, %s%d failed%s\n" \
  "$C_GREEN" "$PASS" "$C_RESET" "$C_YELLOW" "$WARN" "$C_RESET" "$C_RED" "$FAIL" "$C_RESET"
if (( FAIL > 0 )); then
  printf "\n%sBlockers:%s\n" "$C_RED" "$C_RESET"
  for m in "${FAIL_MSGS[@]}"; do printf "  • %s\n" "$m"; done
  exit 1
fi
printf "\n%s<success message>%s\n" "$C_GREEN" "$C_RESET"
```

### Bats suite skeleton
**Source:** `tests/bats/preflight-pre09.bats` lines 1-14.
**Apply to:** All 11 new `tests/bats/*.bats` files.
```bash
#!/usr/bin/env bats
# tests/bats/<name>.bats
# <description>

load 'test_helper'

setup() { ... }
teardown() { ... }

@test "<REQ-ID>: <behavior>" {
  run <command>
  [ "$status" -eq 0 ]
  [[ "$output" =~ "<expected>" ]]
}
```

### `load 'test_helper'` path form (NOT `'../test_helper'`)
**Source:** `tests/bats/test_helper.bash` lines 3-6 (comment block warning).
**Apply to:** All 11 new bats files.

Must use `load 'test_helper'` — bats resolves relative to the suite file's directory (`tests/bats/`), so this locates `tests/bats/test_helper.bash` correctly. Using `load '../test_helper'` resolves to `tests/test_helper` (wrong) and breaks suite loading silently.

### Live-gate for L3/L4 tests
**Source:** RESEARCH.md §6 Wave 0 methodology (no in-repo analog — new pattern).
**Apply to:** 8 of 11 bats files (every cluster/image suite except `cuda-image-02-args.bats`, `create-clusters-01-network.bats`, and the static half of `create-clusters-05-tls-san.bats`).

Every live-dependent suite calls `require_live` (new helper being added to `test_helper.bash` in this phase) in its `setup()`. Per-commit CI skips; final verifier exports `KARYON_LIVE_TESTS=1` and runs them.

### `readonly` constants at top of script
**Source:** No strict Phase 1 analog — `install-tools.sh` line 19 uses plain assignment (`ASDF_VERSION="v0.18.1"`). Phase 2 upgrades to `readonly` for tag/network/image constants that must not mutate mid-execution.
**Apply to:** `scripts/create-clusters.sh`, `scripts/delete-clusters.sh`.

Pattern:
```bash
readonly K8S_NET_NAME="k8s-net"
readonly K8S_NET_SUBNET="172.30.0.0/16"
readonly K8S_NET_DRIVER="bridge"
readonly K3S_STOCK_IMAGE="rancher/k3s:v1.34.6-k3s1"
readonly CUDA_IMAGE_TAG="$("${REPO_ROOT}/images/image-tag.sh")"
```

### 3-part GPU contract documentation (cross-file)
**Source:** CONTEXT.md `<code_context>` lines 124-125 + PROJECT.md 3-part contract.
**Apply to:** Header comment of `images/Dockerfile.k3s-cuda` AND `images/config.toml.tmpl` AND a one-line cross-reference in `images/device-plugin-daemonset.yaml`.

Every artifact that is a leg of the 3-part GPU contract must carry a top-of-file comment enumerating all three legs, so any one file read in isolation tells the full story. Exact language lives in RESEARCH.md §2.1 lines 298-309 (Dockerfile) and §2.2 lines 396-422 (template) — use those as the canonical wording.

### No bats-mock framework yet (conscious gap)
**Status:** bats-mock is NOT installed in Phase 1 tooling. `tests/bats/create-clusters-01-network.bats` is called out in RESEARCH.md §6 as "mock `docker network inspect` / `docker network create`" but the project has no mocking harness.

**Resolution for Phase 2 planner:** The `create-clusters-01-network.bats` test becomes a static-grep test (grep the helper-function body for the expected flags/values) rather than a live mocked integration test. This preserves the REQ-to-test mapping without introducing a new test dependency. Full mock harness deferred to Phase 6 test-hygiene pass.

---

## No Analog Found

Files with no close code match in the codebase (planner uses RESEARCH.md drop-in bodies directly):

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `images/Dockerfile.k3s-cuda` | container-image recipe | static | No Dockerfiles exist yet; canonical source is k3d CUDA reference + k3s source |
| `images/config.toml.tmpl` | containerd template | static | No TOML templates exist yet; canonical source is k3s `ContainerdConfigTemplateV3` |
| `images/device-plugin-daemonset.yaml` | K8s manifest | static | No K8s manifests exist yet; canonical source is NVIDIA static manifest v0.17.4 |
| `Taskfile.yml` | task-runner config | declarative YAML | No Taskfile exists yet; taskfile.dev v3 schema is external canonical |

All four have full drop-in bodies in RESEARCH.md §2 (image artifacts) and §7 item 2 (Taskfile stub rationale). Planner hands these to executors verbatim; no pattern extraction needed because no in-repo analog exists.

---

## Metadata

**Analog search scope:** `/home/rich/code/gsd/karyon/` (all Phase 1 artifacts: `scripts/`, `tests/bats/`, `config/`, repo-root)
**Files read:**
- `scripts/lib/preflight-lib.sh` (247 lines — full)
- `scripts/preflight.sh` (457 lines — full)
- `scripts/install-docker.sh` (217 lines — full)
- `scripts/install-nvidia-container-toolkit.sh` (first 80 lines — style reference only)
- `scripts/install-tools.sh` (first 60 lines — style reference only)
- `tests/bats/test_helper.bash` (16 lines — full)
- `tests/bats/preflight-pre09.bats` (55 lines — full)
- `.planning/phases/02-cluster-layer/02-CONTEXT.md` (full)
- `.planning/phases/02-cluster-layer/02-RESEARCH.md` (sections 1-3 in full + §4-§7 + assumptions log + sources)
- `.planning/phases/01-host-foundation/01-PATTERNS.md` (prior-phase pattern map — full)

**Analog files not re-read (reference only):** Other Phase 1 scripts beyond their first 60-80 lines (structure repeats; no new patterns to extract).

**Pattern extraction date:** 2026-04-23
**Researcher analogs confirmed via:** RESEARCH.md §2 drop-in artifacts (which themselves cite canonical upstream sources with HIGH confidence).
