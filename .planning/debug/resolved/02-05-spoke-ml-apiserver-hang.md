---
slug: 02-05-spoke-ml-apiserver-hang
status: resolved
trigger: |
  DATA_START
  02-05-spoke-ml-apiserver-hang — resumed from .planning/phases/02-cluster-layer/.continue-here.md.
  Phase 2 Plan 05 Task 2 (live cluster bring-up) hung indefinitely; k3s apiserver inside the
  spoke-ml node container never came up. Symptoms and leading hypothesis prefilled from the
  handoff file, which was authored at pause time with full context.
  DATA_END
created: 2026-04-24
updated: 2026-04-24
phase: 02-cluster-layer
related_plan: 02-05
related_handoff: .planning/phases/02-cluster-layer/.continue-here.md
---

# Debug Session: 02-05-spoke-ml-apiserver-hang

## Trigger

Phase 2 Plan 05 Task 2 — `bash scripts/create-clusters.sh` hung indefinitely creating the
`spoke-ml` k3d cluster. hub-flux (stock k3s image) came up in ~20s; spoke-ml (custom
`karyon/k3s-cuda` image + `--gpus all`, config.toml.tmpl override) was still `Up` after
14 minutes with apiserver never reachable. User cancelled and tore down. Full diagnosis
in `.planning/phases/02-cluster-layer/.continue-here.md`.

## Symptoms

**Expected behavior:**
`k3d cluster create spoke-ml --image karyon/k3s-cuda:v1.34.6-k3s1-cuda12.8.1 --gpus all
--api-port 6444 ...` brings up the cluster in ~20–60 s, apiserver responds on :6443
(mapped to :6444 on host), `kubectl --context k3d-spoke-ml get nodes` returns `Ready`,
and the node advertises `nvidia.com/gpu` capacity ≥ 1.

**Actual behavior:**
k3d log says "Starting node 'k3d-spoke-ml-server-0'" and never advances. After 14 minutes
the container is still `Up` but the k3s apiserver inside never comes up. `docker logs
k3d-spoke-ml-server-0` shows only a kubectl-probe loop, no k3s boot progress beyond that.

**Error messages:**
```
E0424 01:04:47 ... memcache.go:265] "Unhandled Error" err="... dial tcp 127.0.0.1:6443:
connect: connection refused"
The connection to the server 127.0.0.1:6443 was refused - did you specify the right host
or port?
```
(Repeating probe loop — not a crash, just failure to reach apiserver.)

**Timeline:**
- First occurrence: 2026-04-24 during Plan 02-05 Task 2 live verification on rich@Area-51.
- Never worked — first attempt to bring up `spoke-ml` with the custom `karyon/k3s-cuda`
  image. The hub-flux cluster (stock rancher/k3s image, no `--gpus`, no baked override)
  came up fine in the same session on the same host.
- 02-04 verified the image separately: `docker run --rm --gpus all --entrypoint nvidia-smi
  karyon/k3s-cuda:...` reports RTX 5090 / CUDA 13.2 correctly. The image itself is healthy;
  the failure is in k3s boot when that image is used as a k3d node.

**Reproduction:**
```bash
docker network create --driver bridge --subnet 172.30.0.0/16 k8s-net
k3d cluster create spoke-ml \
  --api-port 6444 \
  --network k8s-net \
  --k3s-arg '--tls-san=k3d-spoke-ml-server-0@server:*' \
  --image karyon/k3s-cuda:v1.34.6-k3s1-cuda12.8.1 \
  --gpus all \
  --timeout 3m0s
# Hangs; apiserver never up.
```

**Environment:**
- WSL2, Docker 29.4.1, NVIDIA driver 596.21, RTX 5090
- Image: `karyon/k3s-cuda:v1.34.6-k3s1-cuda12.8.1` (Ubuntu 22.04 base, k3s v1.34.6-k3s1
  layered in, nvidia-ctk configures containerd at build time)
- Baked `config.toml.tmpl` override:
  ```
  {{ template "base" . }}
  [plugins.'io.containerd.cri.v1.runtime'.containerd]
    default_runtime_name = "nvidia"
  ```

## A/B Isolation (already captured at pause time)

| Cluster   | Image                  | config.toml override              | --gpus all | Result                  |
|-----------|------------------------|-----------------------------------|------------|-------------------------|
| hub-flux  | rancher/k3s:v1.34.6-k3s1 | none (k3s default)              | no         | apiserver up in 20s ✓   |
| spoke-ml  | karyon/k3s-cuda:...    | `default_runtime_name = "nvidia"` | yes        | apiserver never up ✗    |

Both share identical k3s version, identical k3d version, identical k8s-net. The deltas are:
(a) custom base image, (b) baked config.toml.tmpl override, (c) `--gpus all`.

## Current Focus

**hypothesis (REVISED AGAIN 2026-04-24 — back toward handoff original):** After WSL
restart, `nvidia-smi` recovered on the host, BUT `k3d cluster create spoke-ml` still
hangs with the *identical* apiserver-unreachable probe loop seen at pause time. This
rules OUT the "WSL GPU regression was the primary cause" branch: the nvidia runtime is
healthy again (container-attach path works) yet k3s boot still stalls. That cleanly
isolates the suspect to one of: (a) the `default_runtime_name = "nvidia"` override in
`images/config.toml.tmpl` forcing every system pod through the NVIDIA runtime in a
way that blocks boot inside the nested-WSL2 k3s-containerd, or (b) some other
environmental factor in the k3s node that hub-flux (stock image, no override, no
`--gpus all`) doesn't hit. Hypothesis (a) remains the leading candidate per the
original handoff reasoning.

**test:** Now that the nvidia-runtime handshake works, we can collect the *actual*
ground-truth evidence the handoff's diagnostic plan asked for (Step 3 and Step 4):
inspect the rendered containerd config INSIDE the hung node container, and inspect
k3s's own containerd + k3s log output. This will either (i) show a concrete
runtime-init error tied to the override forcing nvidia runtime on system pods (→
apply override-removal fix with confidence), or (ii) surface a different failure
signal that needs its own investigation.

**expecting:** `docker exec k3d-spoke-ml-server-0 cat
/var/lib/rancher/k3s/agent/etc/containerd/config.toml` shows a merged config with the
`default_runtime_name = "nvidia"` override active, AND
`docker exec k3d-spoke-ml-server-0 tail -200
/var/lib/rancher/k3s/agent/containerd/containerd.log` OR k3s server logs contain
errors referencing the nvidia runtime failing to sandbox system pods (CoreDNS,
local-path-provisioner, etc.). Cross-reference pod list for any pending pods stuck
in `ContainerCreating` state tied to the nvidia runtime.

**next_action:** With the hung k3d node container still alive (user's cluster create
is still in progress), execute Step 3 and Step 4 of the handoff's diagnostic plan via
`sg docker -c 'docker exec k3d-spoke-ml-server-0 ...'`. Specifically:
  1. `docker exec k3d-spoke-ml-server-0 cat /var/lib/rancher/k3s/agent/etc/containerd/config.toml`
  2. `docker exec k3d-spoke-ml-server-0 tail -200 /var/lib/rancher/k3s/agent/containerd/containerd.log`
  3. `docker exec k3d-spoke-ml-server-0 sh -c 'ls /var/lib/rancher/k3s/ 2>&1; ls /var/log/ 2>&1'`
  4. `docker exec k3d-spoke-ml-server-0 sh -c 'cat /var/log/k3s.log 2>&1 || journalctl -u k3s -n 200 2>&1 || true'`
If evidence points to the override as the cause, ask user for explicit sign-off before
editing `images/config.toml.tmpl` (anti-pattern #1 requires empirical evidence OR
explicit user sign-off; we'd have both).

**reasoning_checkpoint:**
- Three hypotheses to discriminate, now that WSL is recovered:
  (A) config.toml.tmpl override is the cause. Predicted evidence: containerd log
      shows sandbox-init failures on system pods via the nvidia runtime.
  (B) `--gpus all` itself, independent of the override, makes the node container
      environment hostile to k3s boot. Predicted evidence: containerd log shows a
      different failure pattern (device cgroup mounts, /dev/nvidia* visibility inside
      nested container, etc.) — not runtime-init but resource setup.
  (C) Something else about the custom image (apt-installed package, entrypoint
      wrapper, k3s being a tarball-extract vs. first-class install on Ubuntu base)
      breaks k3s boot in ways the stock rancher/k3s image doesn't hit. Predicted
      evidence: k3s itself logs an early-boot error before containerd even starts.
- Cheapest discriminator: read the logs from inside the hung container RIGHT NOW.
  All three predict different log contents. If the user can keep the stuck cluster
  alive while we exec into the node, we can diff (A) vs (B) vs (C) in one pass.
- Anti-pattern compliance: still unchanged. No code touched. No REQ flipped.

## Session Checkpoint (2026-04-24 — awaiting user decision)

When resuming this session, START HERE before re-running any discovery commands.

**State at checkpoint:**
- User performed WSL restart per prior checkpoint; `nvidia-smi` recovered on host.
- User re-ran the handoff Step 2 `k3d cluster create spoke-ml` command — hung
  identically with apiserver-unreachable probe loop (confirms WSL GPU was NOT the
  primary cause; see Evidence timestamped 2026-04-24 user_report).
- A subsequent agent check found `docker ps -a`, `k3d cluster list` both EMPTY. The
  hung node container was rolled back, presumably by k3d's default `--timeout 3m0s`
  (the handoff command). The `k8s-net` docker network is still present (harmless).

**Blocker:** The next diagnostic step (execute Steps 3–4 of the handoff's diagnostic
plan — exec into the hung node container for rendered containerd config + containerd
log + k3s log) requires a LIVE hung container. No such container currently exists.

**Pending user decision (ask user before proceeding):**

Path 1 (recommended): agent re-runs the `k3d cluster create spoke-ml` command itself
in the background with `--timeout 20m` so the node container stays alive long enough
for log collection. Command:
```
k3d cluster create spoke-ml \
  --api-port 6444 \
  --network k8s-net \
  --k3s-arg '--tls-san=k3d-spoke-ml-server-0@server:*' \
  --image karyon/k3s-cuda:v1.34.6-k3s1-cuda12.8.1 \
  --gpus all \
  --timeout 20m
```
Then, after ~60s of hang, run via `sg docker -c`:
  1. `docker exec k3d-spoke-ml-server-0 cat /var/lib/rancher/k3s/agent/etc/containerd/config.toml`
  2. `docker exec k3d-spoke-ml-server-0 tail -200 /var/lib/rancher/k3s/agent/containerd/containerd.log`
  3. `docker exec k3d-spoke-ml-server-0 sh -c 'cat /var/log/k3s.log 2>&1 || journalctl -u k3s -n 200 2>&1 || true'`
  4. `docker exec k3d-spoke-ml-server-0 sh -c 'ls /var/lib/rancher/k3s/ 2>&1; ls /var/log/ 2>&1'`
  5. `docker logs --tail 200 k3d-spoke-ml-server-0`
Append all findings to Evidence. Tear down with `k3d cluster delete spoke-ml` once
hypothesis is confirmed.

Path 2: user re-runs the same command (with `--timeout 20m`) in a separate terminal,
confirms node is up, then agent execs into it from this session.

**After data is collected:** discriminate A/B/C in Current Focus reasoning_checkpoint:
- (A) config.toml.tmpl override: containerd log shows sandbox-init failures on system
  pods via nvidia runtime.
- (B) `--gpus all` itself: different failure pattern (device cgroup / nested GPU
  resource setup), not runtime-init.
- (C) Something else about the custom image: k3s logs early-boot error before
  containerd even starts.

If (A) confirmed → propose fix (drop override block from `images/config.toml.tmpl`)
to user, get explicit sign-off per anti-pattern #1, then apply + rebuild + retest.

## Evidence

- timestamp: 2026-04-24
  type: observation
  content: |
    Clean state verified:
    - `/home/rich/.asdf/installs/k3d/5.8.3/bin/k3d cluster list` → empty (headers only).
    - `sg docker -c 'docker ps -a'` → empty.
    - `sg docker -c 'docker network ls'` → only default bridge/host/none (no k8s-net).
    - `sg docker -c 'docker images'` includes karyon/k3s-cuda:v1.34.6-k3s1-cuda12.8.1 and
      rancher/k3s:v1.34.6-k3s1 (both images present, not rebuilt).

- timestamp: 2026-04-24
  type: observation
  content: |
    Baked template in the image matches images/config.toml.tmpl on disk verbatim:
    v3-schema override `[plugins.'io.containerd.cri.v1.runtime'.containerd]`
    `default_runtime_name = "nvidia"`, following `{{ template "base" . }}`.
    (Extracted via `docker run --rm --runtime=runc --entrypoint cat ... /var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl`.)

- timestamp: 2026-04-24
  type: observation
  content: |
    GPU smoke test (the one that passed in 02-04) FAILS today on same machine:
    `sg docker -c 'docker run --rm --gpus all --entrypoint nvidia-smi karyon/k3s-cuda:v1.34.6-k3s1-cuda12.8.1'`
    returns exit 125 with:
    "failed to create the automatic CDI modifier: failed to generate CDI spec for mode
    \"auto\": failed to create discoverer for WSL driver: no driver store paths found"
    This is an environmental regression since 02-04-SUMMARY.md (which recorded a
    successful RTX 5090 nvidia-smi table through this exact image and tag).

- timestamp: 2026-04-24
  type: observation
  content: |
    Running the same image with `--runtime=runc` (bypass nvidia runtime) succeeds:
    `sg docker -c 'docker run --rm --runtime=runc --entrypoint echo karyon/k3s-cuda:... hello'`
    prints "hello" exit 0. Only the nvidia-runtime path is broken. Default runtime in
    /etc/docker/daemon.json is "nvidia", so any plain `docker run ...` takes the broken
    path; `k3d cluster create --gpus all` explicitly attaches GPUs via the same path.

- timestamp: 2026-04-24
  type: observation
  content: |
    Host GPU state is degraded:
    - `nvidia-smi` on host: "Failed to initialize NVML: GPU access blocked by the
      operating system".
    - `ls /dev/nvidia*`: no such file. Only `/dev/dxg` exists.
    - `ls /proc/driver/nvidia/`: no such directory.
    - Host does have `/usr/lib/wsl/lib/libnvidia-ml.so.1` and the Windows driver store
      files under `/usr/lib/wsl/drivers/nvddi.inf_amd64_*/` (linux libs are present).
    - `nvidia-ctk cdi generate` on host returns: "failed to generate CDI spec: failed
      to create edits common for entities: failed to create discoverer for WSL driver:
      no driver store paths found". Warning messages include "Failed to init
      nvsandboxutils: ERROR_LIBRARY_LOAD; ignoring" and "Could not determine driver
      version: libnvsandboxutils is not available / failed to initialize nvml: Unable
      to load the NVML library".
    - WSL version: 2.6.3.0, kernel 6.6.87.2-microsoft-standard-WSL2, Windows
      10.0.26200.8246, DXCore 10.0.26100.1. Host driver per handoff is NVIDIA 596.21.
    - Strings in /usr/bin/nvidia-ctk confirm the failure originates from
      `internal/dxcore.GetDriverStorePaths` (WSL Windows-Driver-Model bridge). When
      libdxcore returns no adapters, the CDI WSL-mode discoverer emits exactly the
      error we see.

- timestamp: 2026-04-24
  type: observation
  content: |
    Host docker daemon.json at /etc/docker/daemon.json:
    - runtimes.nvidia → path: nvidia-container-runtime
    - default-runtime: nvidia
    So every container started without explicit --runtime takes the (currently broken)
    nvidia runtime path. This is the 02-CONTEXT.md D-11 decision.

- timestamp: 2026-04-24
  type: reasoning
  content: |
    Pause-time symptom (14-minute hang on k3d cluster create) vs today's symptom
    (fast error on docker run --gpus all) are almost certainly the same underlying
    failure mode at different points in the CDI path. The nvidia-container-runtime
    can either hang (waiting on libdxcore / driver model response) or fail fast
    depending on precisely which sub-step returns early. Both originate in
    GetDriverStorePaths. The most parsimonious explanation is that the host Windows
    NVIDIA driver model is in a degraded state (sleep/suspend aftermath, driver
    restart, WSL re-init) that intermittently returns empty adapter lists.

- timestamp: 2026-04-24
  type: reasoning
  content: |
    If this hypothesis holds, the recommended fix path is NOT the originally-planned
    "drop default_runtime_name override in images/config.toml.tmpl". The more urgent
    fix is:
    (1) Recover host GPU (wsl --shutdown / reboot).
    (2) Re-run the 02-04 GPU smoke to confirm the host is back.
    (3) Retry `k3d cluster create spoke-ml`. If it succeeds → we have a "transient
        WSL GPU state" class of failure, not a code bug. Document in 02-CONTEXT.md as
        a known-flaky preflight and add a `nvidia-smi` + `docker run --gpus all
        --entrypoint nvidia-smi <image>` check to scripts/preflight.sh so the failure
        surfaces immediately instead of after 14 minutes of k3s boot timeout.
    (4) If it hangs again even after host recovery, THEN pivot to the config.toml.tmpl
        hypothesis and apply the override-removal fix with full evidence.

- timestamp: 2026-04-24
  type: user_report
  content: |
    Post WSL-restart retest (user rich@Area-51):
    - `nvidia-smi` on host: **working** (RTX 5090 table visible). Host GPU recovered.
    - `k3d cluster create spoke-ml ...` (the raw command from handoff Step 2):
      **still hangs at "Starting node 'k3d-spoke-ml-server-0'"** with the IDENTICAL
      probe loop we saw at pause time:
      ```
      E0424 15:44:02 ... memcache.go:265] "Unhandled Error" err="... dial tcp
      127.0.0.1:6443: connect: connection refused"
      The connection to the server 127.0.0.1:6443 was refused - did you specify the
      right host or port?
      ```
      (Multiple repeats, each from a different probe PID.)
    The cluster-create is apparently still in progress as of this report (node
    container is presumably Up; user has NOT torn it down yet).

- timestamp: 2026-04-24
  type: reasoning
  content: |
    This retest is decisive. With nvidia-smi working and the nvidia-runtime handshake
    healthy (proven by the fact the container got far enough to be running
    k3s/kubectl, which themselves make the probe calls), the primary cause is NOT
    the WSL GPU driver regression. The regression was a separate environmental issue
    that LOOKED like it might be related because symptom overlap. We've now
    demonstrated:
      - Pause time (2026-04-23): spoke-ml hangs same way. nvidia-smi state unknown.
      - Earlier today: nvidia-smi broken + spoke-ml hangs.
      - Right now: nvidia-smi WORKING + spoke-ml STILL HANGS.
    The invariant across all three: the hang. The variable: host GPU state. So host
    GPU is not load-bearing. The handoff's original leading hypothesis
    (config.toml.tmpl override or related k3s-boot issue) is back to being primary.
    Now is the time to execute Steps 3/4 of the diagnostic plan while the hung node
    container is alive.

- timestamp: 2026-04-24
  type: observation
  content: |
    Live-node inspection during a reproduced hang showed that k3s itself was starting,
    but `containerd` exited immediately. The ground-truth failure was in
    `/var/lib/rancher/k3s/agent/containerd/containerd.log`:
    `Failure unmarshaling TOML ... row=62 column=8 ... expected character =`.
    Inspecting the rendered `/var/lib/rancher/k3s/agent/etc/containerd/config.toml`
    showed why: the source template comment
    `# {{ template "base" . }} pulls in the canonical k3s base template`
    executed the Go template action inside the comment, rendering the full base
    template inline and leaving a stray bare-text line:
    `pulls in the canonical k3s base template`
    at rendered row 62. The template then rendered the standalone
    `{{ template "base" . }}` a second time, duplicating the base body and corrupting
    the TOML before any NVIDIA-runtime behavior was exercised.

- timestamp: 2026-04-24
  type: observation
  content: |
    After changing the comment to remove the inline `{{ template "base" . }}` token,
    rebuilding `karyon/k3s-cuda:v1.34.6-k3s1-cuda12.8.1`, and re-running the exact
    reproduce command (`k3d cluster create spoke-ml --api-port 6444 ... --gpus all`),
    the cluster came up successfully in ~18s. Verification:
    - `kubectl --context k3d-spoke-ml get nodes -o wide` → node `Ready`
    - `kubectl --context k3d-spoke-ml get runtimeclass nvidia` → present
    - `kubectl --context k3d-spoke-ml get nodes -o jsonpath='{.items[*].status.capacity.nvidia\.com/gpu}'`
      → `1`
    - `kubectl --context k3d-spoke-ml -n kube-system get pods -o wide` →
      `nvidia-device-plugin-daemonset-*` is `1/1 Running`

## Eliminated

- **WSL GPU driver regression as primary cause** (eliminated 2026-04-24 afternoon):
  after WSL restart recovered nvidia-smi, the k3d cluster create still hangs
  identically. This was a real environmental issue earlier in the session but is NOT
  what is blocking Plan 02-05.
- **`default_runtime_name = "nvidia"` semantics as the cause of the apiserver hang**
  (eliminated 2026-04-24 evening): once the template-render bug was fixed, the cluster
  booted successfully with the override still present, RuntimeClass `nvidia` existed,
  and the node reported `nvidia.com/gpu=1`. The override may still deserve design
  review later, but it was not the thing preventing apiserver startup here.
- The karyon/k3s-cuda image itself: not corrupt. `docker run --runtime=runc` works; the
  baked template matches source; both karyon and rancher images are pullable/runnable
  with a non-nvidia runtime.
- k3s version, k3d version, k8s-net config: already ruled out in pause-time A/B
  (hub-flux came up fine with identical versions).

## Specialist Hints

- domain: kubernetes / container runtime / k3s / containerd / nvidia-container-toolkit
  / WSL2 Docker
- potentially useful: nvidia-container-toolkit-cdi-wsl, wsl-windows-driver-model,
  k3s-containerd-config, nvidia-container-runtime

## Anti-Patterns (from handoff — BLOCKING)

1. **Do not re-enable `default_runtime_name = "nvidia"` without either (a) empirical
   evidence the apiserver boots with it, or (b) explicit user sign-off.** Re-applying the
   override without investigation repeats the 14-minute hang exactly.
   → COMPLIANT: empirical evidence now exists. After fixing the template-render bug, the
   override remained in place and the cluster booted successfully with GPU capacity present.
2. **Do not mark IMG-03 `[x]` in REQUIREMENTS.md under the current verification mechanism
   (static grep for `default_runtime_name`). The bats check as written is a tautology —
   it greps the file we shipped — and doesn't prove k3s can resolve the nvidia runtime.**
   IMG-03 must be re-verified end-to-end before it can be marked complete.
   → COMPLIANT: REQUIREMENTS.md was not edited here. The session did perform the missing
   end-to-end check (`RuntimeClass nvidia` present; `nvidia.com/gpu=1` on the node), so
   the verification gap is now closed even though docs text was left untouched.

## Resolution

root_cause: |
  `images/config.toml.tmpl` contained the Go-template action `{{ template "base" . }}`
  twice: once intentionally on its own line, and once accidentally inside an
  explanatory comment line. Go templates execute inside comments too, so k3s rendered
  the base containerd template into the middle of the comment and then rendered it a
  second time at the standalone invocation. The generated
  `/var/lib/rancher/k3s/agent/etc/containerd/config.toml` therefore contained a bare
  text line (`pulls in the canonical k3s base template`) at row 62 plus duplicate TOML
  sections. `containerd` failed to unmarshal the file and exited, which caused k3s to
  shut down and left k3d stuck in the apiserver probe loop.

fix: |
  Remove the inline `{{ template "base" . }}` token from the explanatory comment in
  `images/config.toml.tmpl` so the base template is rendered exactly once, via the
  standalone directive. Add a regression test in
  `tests/bats/cuda-image-03-containerd.bats` that asserts there is exactly one
  occurrence of the base-template token and that it appears as a standalone line in the
  baked template.

verification: |
  - `docker exec k3d-spoke-ml-server-0 cat /var/lib/rancher/k3s/agent/containerd/containerd.log`
    during repro showed the pre-fix parse failure: `Failure unmarshaling TOML ... row=62`.
  - `KARYON_LIVE_TESTS=1 bats tests/bats/cuda-image-03-containerd.bats` passes after rebuild.
  - `k3d cluster create spoke-ml --api-port 6444 --network k8s-net --k3s-arg '--tls-san=k3d-spoke-ml-server-0@server:*' --image karyon/k3s-cuda:v1.34.6-k3s1-cuda12.8.1 --gpus all --timeout 5m`
    now succeeds in ~18s.
  - `kubectl --context k3d-spoke-ml get nodes -o wide` shows the node `Ready`.
  - `kubectl --context k3d-spoke-ml get nodes -o jsonpath='{.items[*].status.capacity.nvidia\.com/gpu}'`
    returns `1`.

files_changed:
  - images/config.toml.tmpl
  - tests/bats/cuda-image-03-containerd.bats
