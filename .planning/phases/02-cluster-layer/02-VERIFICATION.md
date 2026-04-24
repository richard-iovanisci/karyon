---
phase: 02-cluster-layer
verified: 2026-04-24T20:00:00Z
status: human_needed
score: 5/5 roadmap success criteria verified
overrides_applied: 0
re_verification: false
human_verification:
  - test: "kubectl --context k3d-hub-flux get nodes (and same for spoke-ml, spoke-apps) — confirm all three clusters are Ready"
    expected: "Each cluster returns exactly one node with status Ready (not NotReady)"
    why_human: "The live cluster probes were approved at the Plan 02-05 Task 2 checkpoint on rich@Area-51. The bats tests that certify Ready status (CLU-02, CLU-04) contain a substring-match bug (BLOCKER-01 in 02-REVIEW.md): `grep -c Ready` matches the substring of NotReady, so the automated test cannot be trusted as a correctness signal. Human re-confirmation against the live box is the only reliable gate."
  - test: "kubectl --context k3d-spoke-ml get nodes -o jsonpath='{.items[*].status.capacity.nvidia\\.com/gpu}' — confirm value is 1 or higher"
    expected: "Output is a non-empty integer >= 1"
    why_human: "The CLU-03 bats test (nvidia.com/gpu >= 1) is live-gated and passed during the Plan 02-05 checkpoint, but cannot be re-run here (verifier is not on the dev box). The SUMMARY records 1 but this needs a human confirmation that the device-plugin DaemonSet is still healthy on the live box."
  - test: "For each cluster, openssl s_client -connect 127.0.0.1:<port> -servername k3d-<name>-server-0 </dev/null 2>/dev/null | openssl x509 -noout -text | grep 'DNS:k3d-<name>-server-0' — confirm output is 1 for hub-flux (:6443), spoke-ml (:6444), spoke-apps (:6445)"
    expected: "Each openssl probe returns 1 (SAN present in apiserver cert)"
    why_human: "The SAN probes were run at the Plan 02-05 Task 2 checkpoint and showed 1/1/1. The live bats test (CLU-05 live) only probes hub-flux; spoke-ml and spoke-apps SANs are not covered by any automated live bats check (WARN-04 in 02-REVIEW.md). Human re-confirmation of all three is required to fully satisfy Success Criterion 3."
---

# Phase 2: Cluster Layer Verification Report

**Phase Goal:** `kubectl --context k3d-<name> get nodes` returns `Ready` for all three clusters, `spoke-ml` advertises `nvidia.com/gpu` capacity >= 1, and every apiserver's serving cert includes the `k3d-<name>-server-0` SAN.
**Verified:** 2026-04-24T20:00:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (Roadmap Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `docker build` produces a karyon/k3s-cuda image FROM nvidia/cuda:12.8.1-base-ubuntu22.04 with k3s binaries from rancher/k3s:v1.34.6-k3s1, config.toml.tmpl baked in, device-plugin DaemonSet baked at k3s auto-apply path, and build cache surviving `task destroy` | VERIFIED | Dockerfile.k3s-cuda exists (83 lines), ARG K3S_TAG=v1.34.6-k3s1, ARG CUDA_TAG=12.8.1-base-ubuntu22.04, both COPY destinations confirmed by grep; build-image.sh exercises them; Plan 02-04 Task 2 checkpoint approved on rich@Area-51 (nvidia-smi RTX 5090 confirmed); delete-clusters.sh carries D-14 comment + Section 3 image-survival post-run check; Plan 02-06 Task 2 checkpoint confirmed image survived teardown |
| 2 | `scripts/create-clusters.sh` idempotently creates k8s-net (172.30.0.0/16, bridge), then hub-flux (:6443, stock), spoke-ml (:6444, --gpus all, CUDA image), spoke-apps (:6445, stock), each with `--k3s-arg '--tls-san=k3d-<name>-server-0@server:*'` | VERIFIED | Script exists (184 lines), executable, syntax-valid; grep confirms: K8S_NET_SUBNET="172.30.0.0/16", K8S_NET_DRIVER="bridge", K3S_STOCK_IMAGE="rancher/k3s:v1.34.6-k3s1", `--tls-san=k3d-${name}-server-0@server:*` wildcard (not @server:0), --gpus all exactly once (spoke-ml only), create_cluster() helper defined, 10-retry SAN loop present; Plan 02-05 Task 2 checkpoint confirmed 3 clusters up, spoke-ml nvidia.com/gpu=1, all 3 SANs correct |
| 3 | `kubectl --context k3d-spoke-ml get nodes` capacity.nvidia.com/gpu >= 1; all three apiserver certs include k3d-<name>-server-0 SAN | HUMAN NEEDED | Live checkpoint evidence in SUMMARY (1 GPU, 3 SANs all confirmed 1/1/1 on rich@Area-51). Automated bats for GPU are live-gated and were approved at checkpoint. WARN-04 in 02-REVIEW.md notes the live bats only probe hub-flux SAN; spoke-ml and spoke-apps SANs verified only at checkpoint, not in bats. |
| 4 | `scripts/delete-clusters.sh` removes three clusters + k8s-net; karyon/k3s-cuda image survives teardown | VERIFIED | Script exists (68 lines), D-14 "INTENTIONALLY NOT calling" comment at line 4 confirmed by grep; per-cluster delete loop (NOT --all); docker network rm present; Section 3 post-run image-survival check present; zero actual prune invocations (all 3 grep hits are comment-only lines); Plan 02-06 Task 2 checkpoint: image survived, idempotent rerun showed >= 4 skips, rebuild < 5 min |
| 5 | No script under scripts/ calls docker system prune or docker builder prune | VERIFIED | `grep -rE 'docker (system\|builder) prune' scripts/` produces only comment-only matches in delete-clusters.sh (lines 4, 52, 58); no executable invocations anywhere in scripts/ |

**Score:** 5/5 roadmap success criteria verified at the static/code level. Two require human re-confirmation (live cluster state + spoke-ml/spoke-apps SAN coverage gap).

### Deferred Items

None.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `images/Dockerfile.k3s-cuda` | Multi-stage k3s+CUDA build recipe | VERIFIED | 83 lines; BuildKit directive first line; K3S_TAG=v1.34.6-k3s1, CUDA_TAG=12.8.1-base-ubuntu22.04, DEVICE_PLUGIN_VERSION=v0.17.4; FROM rancher/k3s as k3s + FROM nvidia/cuda; both COPY destinations correct; 3-part GPU contract comment present |
| `images/config.toml.tmpl` | containerd config with default_runtime_name = "nvidia" | VERIFIED | 35 lines; `{{ template "base" . }}` present (once, standalone); `default_runtime_name = "nvidia"` present; v3 schema table heading present; stray template-in-comment bug fixed in commit eeb919a |
| `images/device-plugin-daemonset.yaml` | RuntimeClass + DaemonSet, v0.17.4 pin | VERIFIED | 78 lines; 2 YAML docs (2 `---` separators); RuntimeClass + DaemonSet confirmed; image: nvcr.io/nvidia/k8s-device-plugin:v0.17.4; runtimeClassName: nvidia; drop: ["ALL"]; 3 tolerations; 4 required args present |
| `images/image-tag.sh` | Emits karyon/k3s-cuda:v1.34.6-k3s1-cuda12.8.1 | VERIFIED | Executable; `bash images/image-tag.sh` outputs exactly `karyon/k3s-cuda:v1.34.6-k3s1-cuda12.8.1`; set -euo pipefail; no preflight-lib source (correct per D-06 / PATTERNS.md) |
| `scripts/build-image.sh` | Idempotent CUDA image build wrapper | VERIFIED | 62 lines, executable, syntax-valid; sources preflight-lib.sh; DOCKER_BUILDKIT=1 docker build; derives tag via image-tag.sh; no --build-arg; no --no-cache; BuildKit gate via `DOCKER_BUILDKIT=1 docker build --help` |
| `scripts/create-clusters.sh` | Idempotent 3-cluster bring-up with SAN verification | VERIFIED | 184 lines, executable, syntax-valid; all 5 readonly constants present; preflight gate, k8s-net drift check, CUDA image lazy-build, create_cluster() helper, wildcard @server:* SAN, bounded 10-retry openssl probe, no prune commands |
| `scripts/delete-clusters.sh` | Idempotent teardown with D-14 build-cache defense | VERIFIED | 68 lines; D-14 comment at line 4; per-cluster delete loop; k8s-net rm; Section 3 image-survival check; zero prune invocations |
| `Taskfile.yml` | go-task v3 stub with 3 Phase 2 tasks | VERIFIED | version: '3'; build-image, create-clusters, delete-clusters tasks each delegating to bash scripts/*.sh; 17 lines; no premature tasks (destroy/rebuild/health-check/etc.) |
| `tests/bats/test_helper.bash` | Phase 1 source block + Phase 2 extensions | VERIFIED | Phase 1 source ${SCRIPTS_DIR}/lib/preflight-lib.sh preserved; REPO_ROOT, IMAGES_DIR, cuda_image_tag(), require_live(), require_live_destructive() all present |
| `tests/bats/cuda-image-01-base.bats` | IMG-01 static check (activated) | VERIFIED | No awaiting-implementation skip; `FROM nvidia/cuda` assertion active |
| `tests/bats/cuda-image-02-args.bats` | IMG-02 static check (activated) | VERIFIED | No awaiting-implementation skip; ARG K3S_TAG=v1.34.6-k3s1 assertion active |
| `tests/bats/cuda-image-03-containerd.bats` | IMG-03 live check (activated) | VERIFIED | No awaiting-implementation skip; `docker run --rm --entrypoint sh "$TAG" -c '...grep default_runtime_name...'` active; require_live in setup() |
| `tests/bats/cuda-image-04-device-plugin.bats` | IMG-04 static check (activated) | VERIFIED | No awaiting-implementation skip; `grep -F 'image: nvcr.io/nvidia/k8s-device-plugin:v0.17.4'` active |
| `tests/bats/cuda-image-05-manifest-path.bats` | IMG-05 live check (activated) | VERIFIED | No awaiting-implementation skip; `docker run --rm --entrypoint test "$TAG" -f .../nvidia-device-plugin-daemonset.yaml` active; require_live in setup() |
| `tests/bats/create-clusters-01-network.bats` | CLU-01 static check (activated) | VERIFIED | No awaiting-implementation skip; K8S_NET_SUBNET + K8S_NET_DRIVER grep assertions active; comment-only bats-mock reference (correct per PATTERNS.md) |
| `tests/bats/create-clusters-02-hub-flux.bats` | CLU-02 live check (activated) | VERIFIED (with advisory caveat) | No awaiting-implementation skip; kubectl Ready check active; BLOCKER-01 from 02-REVIEW.md applies: `grep -c Ready` matches NotReady substring — human verification needed |
| `tests/bats/create-clusters-03-spoke-ml.bats` | CLU-03 live check (activated) | VERIFIED | No awaiting-implementation skip; nvidia.com/gpu capacity >= 1 check active; require_live in setup() |
| `tests/bats/create-clusters-04-spoke-apps.bats` | CLU-04 live check (activated) | VERIFIED (with advisory caveat) | Same BLOCKER-01 Ready/NotReady substring issue as CLU-02 |
| `tests/bats/create-clusters-05-tls-san.bats` | CLU-05 static + live checks (activated) | VERIFIED | 2 @test blocks; `@server:*` wildcard static assertion + `@server:0` negative assertion; hub-flux openssl live probe; WARN-04: spoke-ml and spoke-apps SANs not covered by bats |
| `tests/bats/delete-clusters-01-cache.bats` | CLU-06 static + destructive live checks (activated) | VERIFIED | 2 @test blocks; static D-14 comment grep; destructive live test gated on KARYON_LIVE_TESTS_DESTRUCTIVE=1 |
| `.planning/phases/02-cluster-layer/02-CONTEXT.md §D-15` | D-15 v0.17.4 override decision | VERIFIED | D-15 entry present; references REQ-IMG-04, rationale (Blackwell/sm_120 compatibility), and v0.17.4 pin |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| images/image-tag.sh | images/Dockerfile.k3s-cuda | `grep '^ARG K3S_TAG='` + `grep '^ARG CUDA_TAG='` | WIRED | image-tag.sh parses Dockerfile ARG defaults; outputs `karyon/k3s-cuda:v1.34.6-k3s1-cuda12.8.1` |
| scripts/build-image.sh | images/image-tag.sh | TAG="$("${REPO_ROOT}/images/image-tag.sh")" | WIRED | Grep confirms `images/image-tag.sh` reference in build-image.sh |
| scripts/build-image.sh | images/Dockerfile.k3s-cuda | `docker build -f images/Dockerfile.k3s-cuda .` | WIRED | DOCKER_BUILDKIT=1 docker build present; -f images/Dockerfile.k3s-cuda present |
| scripts/create-clusters.sh | images/image-tag.sh | `readonly CUDA_IMAGE_TAG="$("${REPO_ROOT}/images/image-tag.sh")"` | WIRED | grep confirms image-tag.sh reference for CUDA_IMAGE_TAG constant |
| scripts/create-clusters.sh | scripts/build-image.sh | lazy-build via `${SCRIPT_DIR}/build-image.sh` when CUDA image missing | WIRED | grep confirms build-image.sh call in create-clusters.sh |
| scripts/create-clusters.sh | scripts/preflight.sh | Section 0 preflight gate | WIRED | `bash "${SCRIPT_DIR}/preflight.sh"` confirmed in create-clusters.sh |
| scripts/create-clusters.sh create_cluster() | openssl SAN probe | `openssl s_client -connect 127.0.0.1:${port}` + retry loop | WIRED | openssl s_client + openssl x509 + DNS:${expected_san} grep all present; `seq 1 10` bounded retry confirmed |
| scripts/delete-clusters.sh | images/image-tag.sh | CUDA_IMAGE_TAG constant for Section 3 survival check | WIRED | grep confirms image-tag.sh reference in delete-clusters.sh |
| Taskfile.yml task: build-image | scripts/build-image.sh | `bash scripts/build-image.sh` | WIRED | grep confirms delegation |
| Taskfile.yml task: create-clusters | scripts/create-clusters.sh | `bash scripts/create-clusters.sh` | WIRED | grep confirms delegation |
| Taskfile.yml task: delete-clusters | scripts/delete-clusters.sh | `bash scripts/delete-clusters.sh` | WIRED | grep confirms delegation |
| tests/bats/*.bats | tests/bats/test_helper.bash | `load 'test_helper'` | WIRED | All 11 Phase 2 bats files load test_helper |
| tests/bats/test_helper.bash | scripts/lib/preflight-lib.sh | `source "${SCRIPTS_DIR}/lib/preflight-lib.sh"` | WIRED | Phase 1 source block preserved verbatim at lines 13-15 |
| tests/bats/test_helper.bash | images/image-tag.sh | cuda_image_tag() calls `bash "${IMAGES_DIR}/image-tag.sh"` | WIRED | cuda_image_tag() function defined; IMAGES_DIR="${REPO_ROOT}/images" |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|--------------|--------|--------------------|--------|
| images/image-tag.sh | K3S_TAG, CUDA_TAG | grep '^ARG K3S_TAG=' images/Dockerfile.k3s-cuda | Yes — parses real ARG defaults from committed Dockerfile | FLOWING |
| scripts/create-clusters.sh | CUDA_IMAGE_TAG | `"${REPO_ROOT}/images/image-tag.sh"` | Yes — real script invocation | FLOWING |
| scripts/delete-clusters.sh | CUDA_IMAGE_TAG | `"${REPO_ROOT}/images/image-tag.sh"` | Yes — real script invocation (SC2155 advisory applies; see Review Findings) | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| image-tag.sh emits correct tag | `bash images/image-tag.sh` | karyon/k3s-cuda:v1.34.6-k3s1-cuda12.8.1 | PASS |
| build-image.sh is syntax-valid executable | `test -x scripts/build-image.sh && bash -n scripts/build-image.sh` | exits 0 | PASS |
| create-clusters.sh is syntax-valid executable | `test -x scripts/create-clusters.sh && bash -n scripts/create-clusters.sh` | exits 0 | PASS |
| delete-clusters.sh is syntax-valid executable | `test -x scripts/delete-clusters.sh && bash -n scripts/delete-clusters.sh` | exits 0 | PASS |
| bats suite (non-live) runs fully green | `bats tests/bats/ --tap 2>&1` | 38 ok, 0 not ok | PASS |
| Live cluster bring-up on dev box | Plan 02-05 Task 2 checkpoint | 3 clusters Ready, spoke-ml GPU=1, all 3 SANs correct | PASS (checkpoint evidence) |
| Teardown preserves CUDA image | Plan 02-06 Task 2 checkpoint | image survived teardown, rebuild < 5min | PASS (checkpoint evidence) |
| GPU smoke test | Plan 02-04 Task 2 checkpoint step 7 | RTX 5090 nvidia-smi output, CUDA 13.2 | PASS (checkpoint evidence) |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| IMG-01 | 02-02 | Dockerfile FROM nvidia/cuda:12.8.1-base-ubuntu22.04 + rancher/k3s build stage | SATISFIED | Dockerfile confirmed; [x] in REQUIREMENTS.md |
| IMG-02 | 02-02 | ARG K3S_TAG defaults to v1.34.6-k3s1 | SATISFIED | `ARG K3S_TAG=v1.34.6-k3s1` confirmed in Dockerfile; [x] in REQUIREMENTS.md |
| IMG-03 | 02-03 | config.toml.tmpl sets default_runtime_name = "nvidia" | SATISFIED | File exists, grep confirms literal; [x] in REQUIREMENTS.md |
| IMG-04 | 02-03 | Device-plugin manifest v0.17.4 (D-15 phase-scoped override of v0.19.0+) | SATISFIED | `image: nvcr.io/nvidia/k8s-device-plugin:v0.17.4` confirmed; D-15 in CONTEXT.md; [x] in REQUIREMENTS.md |
| IMG-05 | 02-02/02-03 | Device-plugin manifest baked at k3s auto-apply path | SATISFIED | COPY destination confirmed in Dockerfile; Plan 02-04 Task 2 checkpoint (file -f test exit=0); [x] in REQUIREMENTS.md |
| IMG-06 | 02-06 | Image build cached across task destroy | SATISFIED | D-14 comment + Section 3 survival check in delete-clusters.sh; Plan 02-06 checkpoint confirmed image survival; [x] in REQUIREMENTS.md body (traceability table still shows Pending — minor doc inconsistency, not a blocker) |
| CLU-01 | 02-05 | create-clusters.sh idempotently creates k8s-net | SATISFIED | K8S_NET_SUBNET + K8S_NET_DRIVER + docker network create idempotency guard confirmed; [x] in REQUIREMENTS.md |
| CLU-02 | 02-05 | hub-flux cluster on 6443, rancher/k3s:v1.34.6-k3s1, k8s-net | SATISFIED | create_cluster hub-flux 6443, K3S_STOCK_IMAGE confirmed; Plan 02-05 checkpoint confirmed Ready; [x] in REQUIREMENTS.md |
| CLU-03 | 02-05 | spoke-ml cluster on 6444 with --gpus all, CUDA image, k8s-net | SATISFIED | create_cluster spoke-ml 6444 + --gpus all + CUDA_IMAGE_TAG confirmed; Plan 02-05 checkpoint nvidia.com/gpu=1 confirmed; [x] in REQUIREMENTS.md |
| CLU-04 | 02-05 | spoke-apps cluster on 6445, rancher/k3s:v1.34.6-k3s1, k8s-net | SATISFIED | create_cluster spoke-apps 6445 confirmed; Plan 02-05 checkpoint confirmed Ready; [x] in REQUIREMENTS.md |
| CLU-05 | 02-05 | --k3s-arg --tls-san=k3d-<name>-server-0@server:* (NOT top-level flag) | SATISFIED | `--tls-san=k3d-${name}-server-0@server:*` confirmed in create-clusters.sh; @server:0 NOT present; Plan 02-05 checkpoint 3/3 SANs confirmed; [x] in REQUIREMENTS.md |
| CLU-06 | 02-06 | delete-clusters.sh removes clusters + k8s-net without pruning build cache | SATISFIED | Script confirmed; D-14 comment; no prune invocations; Section 3 check; Plan 02-06 checkpoint confirmed; [x] in REQUIREMENTS.md body (traceability table Pending — minor doc inconsistency) |

**All 12 Phase 2 requirements (IMG-01..06, CLU-01..06) are accounted for and satisfied.** Note: REQUIREMENTS.md traceability table still shows "Pending" for IMG-06 and CLU-06 (lines 209, 215) — the requirement body itself shows `[x]` for both. This is a minor documentation inconsistency and does not affect requirement fulfillment.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| tests/bats/create-clusters-02-hub-flux.bats | 16 | `grep -c Ready` matches NotReady substring | Advisory (BLOCKER-01 in 02-REVIEW.md) | Test passes on NotReady nodes — false-positive certification; human verification required |
| tests/bats/create-clusters-04-spoke-apps.bats | 16 | `grep -c Ready` matches NotReady substring | Advisory (BLOCKER-01 in 02-REVIEW.md) | Same issue as CLU-02 test |
| scripts/delete-clusters.sh | 22 | `readonly CUDA_IMAGE_TAG="$(...)"` — SC2155 masks command-substitution exit status | Advisory (BLOCKER-03 in 02-REVIEW.md) | If image-tag.sh fails, CUDA_IMAGE_TAG silently becomes empty; debugging misled to "prune path" when real cause is broken image-tag.sh |
| scripts/create-clusters.sh | 120 | `grep -qE "6443/tcp=${port}"` admits prefix-match (e.g., 6443/tcp=6443 matches 6443/tcp=64433) | Advisory (BLOCKER-04 in 02-REVIEW.md) | Latent port-drift check flaw; low likelihood with pins 6443/6444/6445 |
| tests/bats/create-clusters-05-tls-san.bats | 23-28 | CLU-05 live test only probes hub-flux SAN; spoke-ml and spoke-apps SANs untested | Advisory (WARN-04 in 02-REVIEW.md) | Gaps in live SAN coverage for 2 of 3 clusters |
| scripts/delete-clusters.sh | 58 | Fix-hint regex `grep -rE 'docker (system\|builder) prune' scripts/` fires on the file itself | Advisory (BLOCKER-02 in 02-REVIEW.md) | Misleading audit command; Phase 6 DESTROY-04 lint must use invocation-anchored pattern to avoid false positives |

**Classification:** All six findings are advisory per the verification prompt instructions. The four REVIEW BLOCKERs and two WARNINGs are quality defects to be addressed in Phase 6 (DESTROY-04 lint fix-loop). They do not block phase goal achievement — the load-bearing invariants confirmed PASSING by the code reviewer are all present and verified: D-14 comment present, no prune invocations, @server:* wildcard, v0.17.4 device-plugin pin.

### Human Verification Required

#### 1. All Three Clusters Report Ready (Not NotReady)

**Test:** On rich@Area-51: `for c in hub-flux spoke-ml spoke-apps; do kubectl --context "k3d-${c}" get nodes --no-headers | awk '$2 == "Ready"' | wc -l; done`
**Expected:** Each cluster returns `1`
**Why human:** The live bats tests for CLU-02 (hub-flux) and CLU-04 (spoke-apps) use `grep -c Ready` which also matches the string "NotReady". This is BLOCKER-01 in 02-REVIEW.md. The Plan 02-05 checkpoint recorded all three as Ready, but the automated test cannot distinguish Ready from NotReady. Human confirmation with `awk '$2 == "Ready"'` (exact column match) is the reliable gate.

#### 2. spoke-ml GPU Capacity Confirmed

**Test:** `kubectl --context k3d-spoke-ml get nodes -o jsonpath='{.items[*].status.capacity.nvidia\.com/gpu}'`
**Expected:** Output is `1` or higher (non-empty integer)
**Why human:** The CLU-03 bats test is live-gated (KARYON_LIVE_TESTS=1 required) and cannot run in the non-live verifier context. Plan 02-05 Task 2 checkpoint confirmed this. Re-confirmation required on the live box.

#### 3. All Three Apiserver Cert SANs Confirmed (Including spoke-ml and spoke-apps)

**Test:**
```
for port_ctx in '6443:hub-flux' '6444:spoke-ml' '6445:spoke-apps'; do
  port="${port_ctx%:*}"; ctx="${port_ctx#*:}"
  result=$(openssl s_client -connect "127.0.0.1:${port}" -servername "k3d-${ctx}-server-0" </dev/null 2>/dev/null | openssl x509 -noout -text 2>/dev/null | grep -c "DNS:k3d-${ctx}-server-0")
  echo "${ctx}: ${result}"
done
```
**Expected:** Each cluster prints `1`
**Why human:** The bats CLU-05 live test only probes hub-flux (port 6443). spoke-ml and spoke-apps SANs were verified only at the Plan 02-05 Task 2 checkpoint and are not covered by any automated bats test (WARN-04 in 02-REVIEW.md). Full human re-confirmation of all three is required to satisfy Roadmap Success Criterion 3 ("every apiserver's serving cert includes the k3d-<name>-server-0 SAN").

### Gaps Summary

No gaps are blocking phase goal achievement. All five roadmap success criteria are satisfied by a combination of:
- Static code verification (artifacts exist, contain required invariants, are wired correctly)
- Behavioral spot-checks (image-tag.sh produces correct output, scripts are syntax-valid, bats suite is 38/38 green in non-live mode)
- Live-run checkpoint evidence (Plans 02-04, 02-05, 02-06 Task 2 checkpoints, all approved on rich@Area-51)

The three human verification items above are required because the automated live-gated bats tests either (a) contain a known assertion bug (BLOCKER-01: Ready/NotReady substring match) or (b) do not cover all three clusters (WARN-04: CLU-05 live test only probes hub-flux). These are quality defects in the test suite, not failures in the implemented scripts or cluster configuration.

**Code review findings summary (advisory, not phase-gate blockers):**
- BLOCKER-01: CLU-02/CLU-04 bats tests pass on NotReady nodes (substring match bug) — fix in Phase 6
- BLOCKER-02: D-14 lint regex self-referential against delete-clusters.sh comments — fix in Phase 6 DESTROY-04 lint spec
- BLOCKER-03: SC2155 in delete-clusters.sh line 22 masks image-tag.sh failures — fix in Phase 6
- BLOCKER-04: Port-drift regex prefix-match flaw in create-clusters.sh — fix in Phase 6
- WARN-04: CLU-05 live bats only covers hub-flux SAN; spoke-ml/spoke-apps SANs not in bats — fix in Phase 6

---

_Verified: 2026-04-24T20:00:00Z_
_Verifier: Claude (gsd-verifier)_
