---
phase: 02-cluster-layer
plan: 05
subsystem: infra
tags:
  - create-clusters
  - k3d
  - tls-san
  - gpu
  - phase-2

requires:
  - phase: 02-02
    provides: images/Dockerfile.k3s-cuda + images/image-tag.sh (CUDA_IMAGE_TAG source-of-truth)
  - phase: 02-03
    provides: images/config.toml.tmpl + images/device-plugin-daemonset.yaml (baked into the CUDA image)
  - phase: 02-04
    provides: scripts/build-image.sh (lazy-build fallback when karyon/k3s-cuda is missing)
  - phase: 02-01
    provides: tests/bats/create-clusters-0{1..5}.bats Wave-0 stubs

provides:
  - scripts/create-clusters.sh (idempotent k8s-net + 3 k3d clusters with D-13 SAN verification)
  - Live 3-cluster lab on rich@Area-51 (hub-flux :6443, spoke-ml :6444 + GPU, spoke-apps :6445)
  - CLU-01..05 bats checks active (KARYON_LIVE_TESTS-gated for 02/03/04/05-live)

affects:
  - 02-06 (delete-clusters.sh tears down what this script stands up; shares k8s-net lifetime invariant)
  - 02-07 (Taskfile.yml wires `task create-clusters` to this script)
  - Phase 3 (flux bootstrap targets k3d-hub-flux; SANs must be correct for Phase 4 TLS trust chain)
  - Phase 4 (cross-cluster TLS uses the same k3d-NAME-server-0 SAN to trust apiserver certs)

tech-stack:
  added:
    - "k3d 5.8.3 cluster create orchestration (3 clusters on pinned 172.30.0.0/16 bridge network)"
    - "openssl x509 -noout -text | grep DNS SAN probe (D-13 belt-and-suspenders vs k3d issue #1613)"
  patterns:
    - "create_cluster() helper wraps idempotency check + create + SAN verification (PATTERNS.md §create_cluster helper)"
    - "Four-field drift detection on existing clusters: IMAGE, NETWORK, API PORT, GPU (spoke-ml only)"
    - "Bounded retry loop (10 × 3s) around openssl probe distinguishes transient startup race from persistent #1613"

key-files:
  created:
    - "scripts/create-clusters.sh — 184 lines, executable, shellcheck clean"
    - ".planning/debug/resolved/02-05-spoke-ml-apiserver-hang.md (debug session archive)"
  modified:
    - "tests/bats/create-clusters-01-network.bats (skip removed; static K8S_NET_SUBNET / K8S_NET_DRIVER assertions active)"
    - "tests/bats/create-clusters-02-hub-flux.bats (skip removed; live kubectl Ready assertion active)"
    - "tests/bats/create-clusters-03-spoke-ml.bats (skip removed; live nvidia.com/gpu ≥ 1 assertion active)"
    - "tests/bats/create-clusters-04-spoke-apps.bats (skip removed; live kubectl Ready assertion active)"
    - "tests/bats/create-clusters-05-tls-san.bats (both skips removed; @server:* wildcard static + openssl SAN live assertions active; @server:0 negative-assertion added)"
    - "images/config.toml.tmpl (stray {{ template \"base\" . }} removed from comment line — debug fix, commit eeb919a)"

key-decisions:
  - "Wildcard SAN nodefilter `--tls-san=k3d-${name}-server-0@server:*` (NOT @server:0) — k3d issue #1613 mitigation (D-13)"
  - "Port-drift check greps `6443/tcp=${port}` because k3d serverlb ALWAYS exposes container port 6443 regardless of host port; only the host-side port varies per cluster (fix applied mid-plan; see Deviations #1)"
  - "Debug session 02-05-spoke-ml-apiserver-hang isolated an unrelated template-render bug in images/config.toml.tmpl (Go templates execute inside comments — stray `{{ template \"base\" . }}` inside an explanatory comment duplicated the base template and corrupted TOML). Fix was in Plan 02-03 territory (images/config.toml.tmpl) but landed here because the symptom surfaced during Plan 02-05 Task 2 live bring-up."
  - "Override `default_runtime_name = \"nvidia\"` in images/config.toml.tmpl REMAINS ACTIVE — empirical evidence (this plan) shows the apiserver boots cleanly with it in place once the template-render bug was fixed. The override was NEVER the cause of the hang."

patterns-established:
  - "Debug-session-first when a live-run checkpoint fails: /gsd-debug isolates root cause before code change; keeps plan scope stable while blocker is investigated in its own context"
  - "k3d serverlb port mapping is container-port-stable (always 6443) and host-port-varying; drift checks must pin the container side, not the host side"

requirements-completed:
  - CLU-01
  - CLU-02
  - CLU-03
  - CLU-04
  - CLU-05

duration: Checkpoint-paced — Task 1 inline; Task 2 user-run on rich@Area-51 (~1 min create + verify); Task 3 inline. Total wall-clock including debug detour: ~1 day.
completed: 2026-04-24
---

# Phase 02 Plan 05: scripts/create-clusters.sh + CLU-01..05 live activations

**Idempotent 3-cluster k3d lab stands up cleanly on k8s-net; spoke-ml reports `nvidia.com/gpu=1`; all three apiserver certs carry the k3d-NAME-server-0 SAN; CLU-01..05 bats checks active.**

## Performance

- **Tasks:** 3 (1 inline, 1 human-verify checkpoint, 1 inline)
- **Files created:** 1 (scripts/create-clusters.sh)
- **Files modified:** 6 (5 bats activations + 1 template-bug fix in images/config.toml.tmpl)

## Task Commits

1. **Task 1: Create scripts/create-clusters.sh** — `5aa85df` (feat)
2. **Task 2: Live 3-cluster bring-up checkpoint** — user ran on rich@Area-51 after unblocking debug session; initial run hung (template-render bug, separate diagnosis), resolved in `eeb919a` (fix in 02-03 artifact); final bring-up clean
3. **Task 3: Activate CLU-01..05 bats bodies** — (this commit)
4. **Plan finalization: drift-check + SUMMARY + REQUIREMENTS flips** — (this commit)

## Files Created/Modified

- `scripts/create-clusters.sh` — 184 lines, executable, shellcheck clean.
  - Sections: preflight gate → k8s-net network (subnet/driver drift check) → CUDA image (lazy build via scripts/build-image.sh) → create_cluster helper → hub-flux/spoke-ml/spoke-apps serial invocations → summary.
  - `create_cluster()` idempotency: 4-field drift check (IMAGE, NETWORK, API PORT via serverlb, GPU via DeviceRequests on spoke-ml only) + wildcard SAN nodefilter + bounded-retry openssl SAN probe.
- `tests/bats/create-clusters-01-network.bats` — static grep for `K8S_NET_SUBNET="172.30.0.0/16"` + `K8S_NET_DRIVER="bridge"`.
- `tests/bats/create-clusters-02-hub-flux.bats` — `kubectl --context k3d-hub-flux get nodes` Ready check.
- `tests/bats/create-clusters-03-spoke-ml.bats` — `kubectl --context k3d-spoke-ml get nodes ...capacity.nvidia\.com/gpu` ≥ 1.
- `tests/bats/create-clusters-04-spoke-apps.bats` — `kubectl --context k3d-spoke-apps get nodes` Ready check.
- `tests/bats/create-clusters-05-tls-san.bats` — 2 @test blocks: static wildcard-SAN assertion + `@server:0` negative assertion; live openssl SAN probe against hub-flux :6443.
- `images/config.toml.tmpl` — removed inline `{{ template "base" . }}` from the comment line on line 17 (commit `eeb919a`); the template action now fires exactly once on line 28. Fix was made during debug session but lives in Plan 02-03's artifact.

## Verification

Live run on rich@Area-51 (WSL2, Docker 29.4.1, NVIDIA driver 596.21, RTX 5090):

1. `bash scripts/create-clusters.sh` — exits 0, Summary reports `7 passed, 0 warnings, 0 failed`, creation times: hub-flux 17s, spoke-ml 20s, spoke-apps 21s.
2. `k3d cluster list --no-headers | awk '{print $1}' | sort` → `hub-flux\nspoke-apps\nspoke-ml` ✓
3. All 3 Ready:
   ```
   hub-flux:   Ready
   spoke-ml:   Ready
   spoke-apps: Ready
   ```
4. `kubectl --context k3d-spoke-ml get nodes -o jsonpath='{.items[*].status.capacity.nvidia\.com/gpu}'` → `1` ✓
5. All 3 SANs correct: `hub-flux (:6443): 1`, `spoke-ml (:6444): 1`, `spoke-apps (:6445): 1` ✓
6. `docker network inspect k8s-net -f '{{(index .IPAM.Config 0).Subnet}} {{.Driver}}'` → `172.30.0.0/16 bridge` ✓
7. Idempotent rerun: 5 "already done, skipping" lines (k8s-net + CUDA image + 3 clusters) ✓
8. `KARYON_LIVE_TESTS=1 bats tests/bats/create-clusters-*.bats` → 6 ok / 0 fail ✓
9. Earlier tests still green: `bats tests/bats/preflight-*.bats tests/bats/cuda-image-*.bats` → all green (IMG-03/05 skip cleanly without KARYON_LIVE_TESTS) ✓

## Decisions Made

See `key-decisions` in frontmatter.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] API PORT drift check in scripts/create-clusters.sh was wrong for non-hub clusters**

- **Found during:** Task 2 idempotent-rerun verification (step 8 of Task 2 checkpoint)
- **Issue:** Initial script greps `${port}/tcp=${port}` against the serverlb port-map string. But k3d serverlb always exposes container port **6443** regardless of the `--api-port` host binding. `docker inspect k3d-spoke-ml-serverlb` returns `80/tcp= 6443/tcp=6444`, so the check failed with `API PORT drift (serverlb ports=80/tcp= 6443/tcp=6444, expected=6444/tcp=6444)`. hub-flux happened to pass because its internal and host port are both 6443 (coincidence). The plan's acceptance-criteria hint (line 290) used `6443/tcp=6443` and was ambiguously stated as a "cluster-appropriate port" pattern.
- **Fix:** Changed grep pattern from `${port}/tcp=${port}` → `6443/tcp=${port}` (container side pinned, host side parameterized).
- **Files modified:** scripts/create-clusters.sh (1-line grep pattern + fail message).
- **Verification:** Idempotent rerun now reports 5 "already done, skipping" lines; hub-flux/spoke-ml/spoke-apps all hit the skip path without drift.
- **Committed in:** (this commit)

**2. [Rule 2 - Design issue] Task 2 checkpoint blocked for ~1 day on an unrelated template-render bug**

- **Found during:** Task 2 first-run on 2026-04-23 evening — spoke-ml hung indefinitely at apiserver probe loop
- **Issue:** `images/config.toml.tmpl` contained the Go-template action `{{ template "base" . }}` twice: once intentionally on its own line, once accidentally inside an explanatory comment line. Go templates execute inside comments, so k3s rendered the base template into the middle of the comment (producing a bare text line `pulls in the canonical k3s base template` at row 62) AND at the standalone invocation a second time, duplicating TOML sections. containerd failed to unmarshal, exited, and k3s never reached apiserver-ready. Pause handoff written (commit `80c10ac`), debug session opened (`/gsd-debug 02-05-spoke-ml-apiserver-hang`), root cause found via live-container exec into the hung node.
- **Fix:** Removed the inline `{{ template "base" . }}` token from the comment on line 17 of `images/config.toml.tmpl`. Rebuilt image, reran `k3d cluster create spoke-ml` → came up in ~18s. Debug session archived at `.planning/debug/resolved/02-05-spoke-ml-apiserver-hang.md`.
- **Files modified:** images/config.toml.tmpl (1-line comment edit — the template action was removed; explanatory English text stayed).
- **Verification:** Live bring-up on 2026-04-24 green; apiserver up, node Ready, `nvidia.com/gpu=1`, RuntimeClass `nvidia` present.
- **Committed in:** `eeb919a fix(02-03): remove stray template action from config.toml.tmpl comment` — note: technically a Plan 02-03 artifact fix, committed mid-debug. 02-03-SUMMARY should eventually be annotated; for now it's scoped here because the symptom surfaced in 02-05.

**3. [Rule 1 - Over-scoped anti-pattern] Initial leading hypothesis during pause blamed the `default_runtime_name = "nvidia"` override**

- **Found during:** Debug session reasoning checkpoint (2026-04-24 evening)
- **Issue:** The pause handoff's leading hypothesis was that the config.toml.tmpl `default_runtime_name = "nvidia"` override was forcing every system pod through the nvidia runtime in a way that blocked k3s boot. Multiple alternative hypotheses were discriminated (WSL GPU regression, --gpus all, custom image entrypoint). Live-container log inspection showed the actual cause was upstream of any runtime behavior — containerd couldn't even parse its own config file because of the template duplication. The override ran fine once the parse error was gone.
- **Fix:** No code change to the override; hypothesis retracted in the debug session's Eliminated section. The anti-pattern from the handoff ("Do not re-enable `default_runtime_name = \"nvidia\"` without empirical evidence") is now COMPLIANT by having collected that evidence.
- **Files modified:** None (no override change applied). Debug session Eliminated section documents the retraction.
- **Verification:** spoke-ml now boots cleanly with the override in place; `kubectl get runtimeclass nvidia` present; `nvidia.com/gpu=1` on the node.
- **Committed in:** N/A (hypothesis-only retraction)

---

**Total deviations:** 3 (1 auto-fixed script bug, 1 template-render bug in sibling plan artifact, 1 retracted hypothesis). Zero scope changes to the plan itself.

## Issues Encountered

**Docker group sandbox artifact (recurrence from 02-04).** Agent bash tool isn't in the docker group; live cluster commands required `sg docker -c` to verify. The interactive user shell IS in the docker group per Phase 1 D-11 — Task 2 checkpoint and all 8 verification steps were either user-run or `sg docker -c`-wrapped.

**Debug session overhead (~1 day).** The template-render bug was invisible to static checks and surfaced only at live boot. Pause-and-resume via `.continue-here.md` + `/gsd-debug` worked cleanly: the handoff captured A/B deltas, leading hypothesis, and diagnostic plan; the debug session expanded hypothesis space, collected ground-truth evidence from the live hung container, and produced a targeted fix. The 1-day delay was real but the mechanism is the right mechanism for this class of failure.

## User Setup Required

None.

## Next Phase Readiness

- All 3 clusters running and advertising the expected capabilities (hub-flux Ready, spoke-ml Ready + 1 GPU, spoke-apps Ready). **Plan 02-06** (`scripts/delete-clusters.sh`) can now be written and tested against a live lab.
- The k3s auto-apply mechanism is confirmed working end-to-end (the baked device-plugin manifest lands, RuntimeClass `nvidia` is admitted, GPU capacity surfaces on the node). This closes the 3-part GPU contract empirically.
- **Plan 02-07** (Taskfile.yml) should wire `task create-clusters` to `bash scripts/create-clusters.sh` and `task delete-clusters` to the 02-06 script.
- **Phase 3** (flux bootstrap) can target `k3d-hub-flux` on :6443 with SAN verified. The `k3d-hub-flux-server-0` SAN is carried in the cert — downstream TLS trust chains in Phase 4 will resolve.
- REQUIREMENTS.md now marks CLU-01..05 complete. CLU-06 stays open — Plan 02-06's `scripts/delete-clusters.sh` closes it. IMG-06 stays open — also 02-06 territory (D-14 build-cache survival).

---
*Phase: 02-cluster-layer*
*Completed: 2026-04-24*
