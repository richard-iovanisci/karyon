---
phase: 02-cluster-layer
reviewed: 2026-04-24T18:01:50Z
depth: standard
files_reviewed: 20
files_reviewed_list:
  - Taskfile.yml
  - images/Dockerfile.k3s-cuda
  - images/config.toml.tmpl
  - images/device-plugin-daemonset.yaml
  - images/image-tag.sh
  - scripts/build-image.sh
  - scripts/create-clusters.sh
  - scripts/delete-clusters.sh
  - tests/bats/create-clusters-01-network.bats
  - tests/bats/create-clusters-02-hub-flux.bats
  - tests/bats/create-clusters-03-spoke-ml.bats
  - tests/bats/create-clusters-04-spoke-apps.bats
  - tests/bats/create-clusters-05-tls-san.bats
  - tests/bats/cuda-image-01-base.bats
  - tests/bats/cuda-image-02-args.bats
  - tests/bats/cuda-image-03-containerd.bats
  - tests/bats/cuda-image-04-device-plugin.bats
  - tests/bats/cuda-image-05-manifest-path.bats
  - tests/bats/delete-clusters-01-cache.bats
  - tests/bats/test_helper.bash
findings:
  blocker: 4
  warning: 9
  info: 6
  total: 19
status: issues_found
---

# Phase 2: Code Review Report

**Reviewed:** 2026-04-24T18:01:50Z
**Depth:** standard
**Files Reviewed:** 20
**Status:** issues_found

## Summary

The Phase 2 cluster-layer submission correctly ships the three-leg k3d GPU
contract (CUDA base + config.toml.tmpl `default_runtime_name = "nvidia"` +
baked device-plugin DaemonSet) and honors the two load-bearing invariants
explicitly called out in the review prompt:

- `scripts/delete-clusters.sh` carries the literal `INTENTIONALLY NOT calling`
  D-14 comment (line 4) and contains **no invocations** of `docker system
  prune` / `docker builder prune` / `docker image prune` / `docker volume
  prune` — only three comment-only references remain (lines 4, 52, 58).
- `scripts/create-clusters.sh` pins TLS SAN via the `@server:*` wildcard
  nodefilter (line 144), not `@server:0`.
- `images/device-plugin-daemonset.yaml` pins
  `nvcr.io/nvidia/k8s-device-plugin:v0.17.4` (RTX 5090 Blackwell lock).
- All four shell scripts start with `set -euo pipefail` and source
  `scripts/lib/preflight-lib.sh`.
- `require_live` / `require_live_destructive` skip correctly when the env
  vars are unset.

However, review surfaced multiple correctness defects. The most serious are:

1. **CLU-02 / CLU-04 tests pass on NotReady nodes** (substring match of
   `Ready` against `NotReady` output). This is a false-negative test; a
   broken cluster is certified Ready.
2. **The CLU-06 D-14 lint regex published in the script itself is
   self-referential** — `grep -rE 'docker (system|builder) prune' scripts/`
   will fire on `delete-clusters.sh` (three comment-only matches). The Phase
   6 DESTROY-04 lint must either grep for call syntax or exclude the
   D-14 comment block, or the fix-hint published by the script will
   mislead users.
3. **`readonly CUDA_IMAGE_TAG="$(...)"` in `delete-clusters.sh:22` masks
   return values** (SC2155). If `image-tag.sh` fails, the script
   silently proceeds with an empty tag, and the downstream survival
   check then prints a confusing "image missing after teardown" error
   instead of the real root cause.
4. **Port-drift regex `grep -qE "6443/tcp=${port}"` has a prefix-match
   flaw** — e.g., `6443/tcp=6443 ` matches `6443/tcp=64433` (if a future
   port were assigned in that range). Low likelihood today (pins are
   6443/6444/6445) but a latent correctness issue that should be anchored.

Additional warnings cover: asymmetric device-plugin version tracking (ARG
vs hard-coded manifest), weak BuildKit gate, `local i` hygiene, missing
spoke-ml / spoke-apps TLS SAN live coverage, and a handful of quality
issues.

## Blockers

### BLOCKER-01: CLU-02 and CLU-04 bats tests pass on NotReady nodes

**File:** `tests/bats/create-clusters-02-hub-flux.bats:17`,
`tests/bats/create-clusters-04-spoke-apps.bats:17`

**Issue:** Both tests do:

```bash
kubectl --context k3d-... get nodes --no-headers 2>/dev/null | grep -c Ready
```

`grep -c Ready` matches the substring `Ready`, which is ALSO a substring
of `NotReady`. A single-node cluster reporting `NotReady` will therefore
return `1` and the assertion `[ "$output" -ge 1 ]` passes. The tests
cannot distinguish Ready from NotReady and give a false-positive
certification of cluster health.

Reproduction:
```
$ echo "k3d-hub-flux-server-0   NotReady   control-plane,master   20s   v1.34.6+k3s1" | grep -c Ready
1
```

**Fix:** Anchor the pattern to the STATUS column. Two safe options:

```bash
# Option A: exact word boundary
run bash -c "kubectl --context k3d-hub-flux get nodes --no-headers 2>/dev/null | awk '\$2 == \"Ready\"' | wc -l"

# Option B: use kubectl's own conditions API (preferred — robust to column reordering)
run bash -c "kubectl --context k3d-hub-flux get nodes -o jsonpath='{range .items[*]}{.status.conditions[?(@.type==\"Ready\")].status}{\"\\n\"}{end}' | grep -c '^True$'"
```

---

### BLOCKER-02: D-14 self-referential lint regex will misfire against delete-clusters.sh itself

**File:** `scripts/delete-clusters.sh:4,52,58`

**Issue:** `delete-clusters.sh` publishes a hint telling users to run
`grep -rE 'docker (system|builder) prune' scripts/` (line 58) when the
image-survival check fails. That exact regex fires **three matches on
this very file**:

- Line 4: `# INTENTIONALLY NOT calling \`docker system prune\` or \`docker builder prune\`.`
- Line 52: `# that adds \`docker system prune\` / \`docker builder prune\` would make this check fail.`
- Line 58: `#      Audit: grep -rE 'docker (system|builder) prune' scripts/`

Consequences:
1. A user following the published fix hint would see 3 matches on the
   file explicitly exempted by the D-14 decision and have no way to
   distinguish real violations from documentation references.
2. The Phase 6 DESTROY-04 lint (referenced in the same file) must
   therefore be specified carefully — matching the literal string in
   comments is not a useful signal. If Phase 6 lint uses the naive
   regex, **it will fail on Phase 2's own output**, and Phase 6 will
   be unable to ship.

**Fix:** Either (a) tighten the fix-hint and the future Phase 6 lint to
match invocation syntax instead of any textual reference, or (b) mark
the comment block with a well-known exemption marker so the lint can
exclude it:

```bash
# Option A: lint invocation syntax only (no leading # in the same line)
grep -rE '^[^#]*docker[[:space:]]+(system|builder|image|volume)[[:space:]]+prune' scripts/

# Option B: exempt the D-14 comment block via a magic marker
#   # D-14-EXEMPT: doc-only reference
#   ...
# then the lint: grep -rE 'docker (system|builder) prune' scripts/ | grep -v 'D-14-EXEMPT'
```

Either way, update the fix-hint string on line 58 so the published
remediation command does not give false positives.

---

### BLOCKER-03: SC2155 — `readonly` with command substitution masks exit status

**File:** `scripts/delete-clusters.sh:22`

**Issue:** The line
```bash
readonly CUDA_IMAGE_TAG="$("${REPO_ROOT}/images/image-tag.sh")"
```
bundles the assignment and `readonly` declaration. When the RHS command
substitution fails, bash ignores the non-zero exit under `set -e`
because the enclosing `readonly` command succeeded. Confirmed
empirically:

```
$ bash -c 'set -euo pipefail; readonly X="$(false)"; echo "reached: $X"'
reached:
```

If `image-tag.sh` is ever broken (or `images/Dockerfile.k3s-cuda` is
missing), `CUDA_IMAGE_TAG` silently becomes empty, the script continues,
and the downstream check

```bash
docker images "$CUDA_IMAGE_TAG" --format ... | grep -qx "$CUDA_IMAGE_TAG"
```

issues `docker images ""` (which lists everything) but `grep -qx ""`
never matches — so the user sees "image missing after teardown — a
prune path slipped in" when the actual root cause is a broken
`image-tag.sh` / `Dockerfile.k3s-cuda`. That misdirects debugging onto
the wrong subsystem.

Note: `create-clusters.sh` gets this right — see lines 30–31, which
separate the assignment from the `readonly`. The same split must be
applied here.

**Fix:**
```bash
CUDA_IMAGE_TAG="$("${REPO_ROOT}/images/image-tag.sh")"
readonly CUDA_IMAGE_TAG
```

---

### BLOCKER-04: API-PORT drift regex admits prefix matches

**File:** `scripts/create-clusters.sh:120`

**Issue:** The drift check is:
```bash
if ! echo "$actual_ports" | grep -qE "6443/tcp=${port}"; then
```

Because `actual_ports` is a space-separated string like
`6443/tcp=6443 ` and the regex is not anchored, the pattern
`6443/tcp=6443` also matches `6443/tcp=64433 `, `6443/tcp=64439 `, etc.
Confirmed empirically:

```
$ echo "6443/tcp=64433 " | grep -qE "6443/tcp=6443" && echo MATCH
MATCH
```

If k3d ever assigns the serverlb to a port whose decimal representation
starts with the expected port (e.g., a user manually edits the cluster
to 64430 but the idempotency check still expects 6443), the drift
check silently succeeds and the cluster is certified as "already
done". Current hardcoded ports (6443/6444/6445) make the prefix
collision unlikely today, but the bug is latent.

**Fix:** Anchor the match to a trailing boundary. `actual_ports`
always ends each port entry with a literal space, so:

```bash
if ! echo "$actual_ports" | grep -qE "(^| )6443/tcp=${port}( |$)"; then
```

Or use an exact-match shell pattern instead of regex:

```bash
if [[ " $actual_ports " != *" 6443/tcp=${port} "* ]]; then
```

## Warnings

### WARN-01: `ARG DEVICE_PLUGIN_VERSION` is decorative only — manifest version is hard-coded

**File:** `images/Dockerfile.k3s-cuda:19,34,38` and
`images/device-plugin-daemonset.yaml:56`

**Issue:** The Dockerfile declares `ARG DEVICE_PLUGIN_VERSION=v0.17.4`
and references it only in a LABEL. The actual deployed image tag is
hard-coded in `device-plugin-daemonset.yaml` as
`nvcr.io/nvidia/k8s-device-plugin:v0.17.4`. A future maintainer who
bumps the ARG (the visibly-pinned constant) will produce an image
whose LABEL advertises the new version while the shipped DaemonSet
still runs the old version — a silent version-drift footgun.
Given D-15 explicitly pins v0.17.4 for Blackwell compatibility, drift
here could reintroduce a GPU-capacity regression.

**Fix:** Make the manifest version follow the ARG. Either (a) drop the
unused ARG and keep the manifest version as the single source of
truth, or (b) template the manifest at build time via `envsubst` /
`sed`. Option (a) is simpler and aligns with the D-06 "single source
of truth" principle already applied to `images/image-tag.sh`:

```dockerfile
# Remove the ARG entirely, and drop the ${DEVICE_PLUGIN_VERSION} from the LABEL
LABEL org.opencontainers.image.description="k3s ${K3S_TAG} on nvidia/cuda base with NVIDIA device-plugin baked in"
```

Add a top-of-file comment in `device-plugin-daemonset.yaml` declaring
it the single source of truth for the plugin pin.

---

### WARN-02: `docker build --help` is not a meaningful BuildKit gate

**File:** `scripts/build-image.sh:37`

**Issue:** The check is:

```bash
if ! DOCKER_BUILDKIT=1 docker build --help >/dev/null 2>&1; then
```

`docker build --help` always prints help and exits 0 — regardless of
whether BuildKit is functional. Confirmed empirically. This gate
therefore only tells you that `docker` is installed, not that
BuildKit can be invoked. The actual build on line 49 requires the
`docker/dockerfile:1.7-labs` frontend (for `COPY --exclude`), so a
BuildKit-less daemon will fail there with a confusing parse error.

**Fix:** Probe BuildKit capability directly. Any of:

```bash
# Option A: docker buildx version (plugin presence — covers the vast majority of recent installs)
if ! docker buildx version >/dev/null 2>&1; then ...

# Option B: trivial probe build
if ! DOCKER_BUILDKIT=1 docker build -q -f - . <<<'FROM scratch' >/dev/null 2>&1; then ...

# Option C: inspect server info (BuildKit enabled on Docker Engine >= 23)
if ! docker info --format '{{.ServerVersion}}' 2>/dev/null | awk -F. '{exit !($1 >= 23)}'; then ...
```

---

### WARN-03: `local i` leaks into the outer scope from the SAN retry loop

**File:** `scripts/create-clusters.sh:152`

**Issue:** Inside `create_cluster()`:

```bash
for i in $(seq 1 10); do
```

`i` is not declared `local`. The earlier `local i gpu_requested=0` on
line 95 is inside a nested block (`if k3d cluster list...`) and does
NOT cover the later for-loop — under bash scoping, `local` inside a
function applies function-wide once declared, so in practice `i` is
already local by the time line 152 runs. However this depends on
code-path ordering; if a future refactor moves the for-loop ahead of
the idempotency branch, `i` becomes a global leak. Additionally the
loop variable is unused, so the declaration + variable are
gratuitous.

**Fix:**
```bash
for _ in $(seq 1 10); do
```
Or, with explicit declaration:
```bash
local attempt
for attempt in $(seq 1 10); do
```

---

### WARN-04: CLU-05 live test only covers hub-flux; spoke-ml and spoke-apps SANs untested

**File:** `tests/bats/create-clusters-05-tls-san.bats:23-28`

**Issue:** Only hub-flux has a live SAN probe. The comment in
`create-clusters-05-tls-san.bats:3` says "L4 openssl probe that
**each** apiserver cert carries `DNS:k3d-<name>-server-0`", but only
one of three clusters is actually probed. D-13's wildcard SAN mitigation
applies per-cluster, and the CLU-03 / CLU-04 tests only verify Ready
(and BLOCKER-01 shows they don't even do that reliably). A broken
TLS SAN on spoke-ml or spoke-apps can ship without being caught.

Note that `create-clusters.sh` itself performs a per-cluster SAN
verification (line 152–170), so runtime enforcement exists — but the
bats suite is the gate that the verifier uses, and it's incomplete
relative to the advertised intent.

**Fix:** Add two more live-gated @tests mirroring the hub-flux one,
using ports 6444 (spoke-ml) and 6445 (spoke-apps). Consider a
parameterized helper:

```bash
_san_live_probe() {
  local name="$1" port="$2"
  openssl s_client -connect "127.0.0.1:${port}" -servername "k3d-${name}-server-0" </dev/null 2>/dev/null \
    | openssl x509 -noout -text 2>/dev/null \
    | grep -c "DNS:k3d-${name}-server-0"
}
```

---

### WARN-05: Device-plugin DaemonSet lacks nodeSelector — "GPU nodes only" comment is misleading

**File:** `images/device-plugin-daemonset.yaml:38-53`

**Issue:** The comment at line 38 says "Schedule onto GPU nodes only"
but the Pod spec only sets `runtimeClassName: nvidia` and
tolerations — there is no `nodeSelector` or `affinity` limiting the
DaemonSet to nodes that actually have GPU capacity. On a single-node
spoke-ml this is moot (the one node is the GPU node). But:

1. The comment is misleading — `runtimeClassName` doesn't select
   nodes, it picks the CRI runtime.
2. If spoke-ml ever grows a second non-GPU node, the plugin pod
   will attempt to land there too, fail `nvidia` runtime lookup,
   and generate CrashLoopBackOff noise.

**Fix:** Either delete the misleading comment, or add a nodeSelector
that matches a GPU-capacity label. For spoke-ml on k3s a common
pattern is:
```yaml
nodeSelector:
  nvidia.com/gpu.deploy.device-plugin: "true"
```
or label the node post-create in the install script.

---

### WARN-06: `[[ -x "$SCRIPT" ]]` false negative if file is present but not executable

**File:** `scripts/create-clusters.sh:65-72`

**Issue:** The fallback-build path checks `[[ -x "${SCRIPT_DIR}/build-image.sh" ]]`
and, if false, emits "scripts/build-image.sh not found". This is a
lie when the file exists but is not +x. Shipping + permissions drift
(e.g., files extracted from a tar without preserved modes, or a
Windows checkout) would trigger this misdiagnosis.

**Fix:** Match the Taskfile pattern — call via `bash` so the +x bit
is irrelevant:

```bash
if [[ -f "${SCRIPT_DIR}/build-image.sh" ]]; then
  info "building: ${CUDA_IMAGE_TAG} (calling scripts/build-image.sh)"
  bash "${SCRIPT_DIR}/build-image.sh"
  pass "built: ${CUDA_IMAGE_TAG}"
else
  ...
fi
```

---

### WARN-07: `delete-clusters.sh` destructive live test assumes image pre-exists

**File:** `tests/bats/delete-clusters-01-cache.bats:25-31`

**Issue:** The test's invariant is "image survives `delete-clusters.sh`".
It does not check that the image exists **before** running the
teardown. If a fresh box runs the destructive suite without first
building the image, `delete-clusters.sh` exits 1 on its own survival
check (`exit 1` at line 60) — the `|| true` on line 27 swallows
that — and then the test's own grep returns 0 matches, reporting
"image did not survive". The real cause is "image was never built".

**Fix:** Add a pre-condition before running the script under test:

```bash
@test "CLU-06 (live/destructive): karyon/k3s-cuda image survives delete-clusters.sh" {
  require_live_destructive
  local tag
  tag="$(cuda_image_tag)"
  run bash -c "docker images '${tag}' --format '{{.Repository}}:{{.Tag}}' | grep -qx '${tag}'"
  [ "$status" -eq 0 ] || skip "prerequisite: karyon/k3s-cuda must be built before this destructive test"
  bash "${REPO_ROOT}/scripts/delete-clusters.sh" >/dev/null 2>&1 || true
  ...
}
```

---

### WARN-08: CLU-01 regex pattern assumes exact-literal quoting of constants

**File:** `tests/bats/create-clusters-01-network.bats:17-20`

**Issue:** The grep assertions require `^readonly K8S_NET_SUBNET="172\.30\.0\.0/16"`
and `^readonly K8S_NET_DRIVER="bridge"`. Any benign future refactor that
(a) switches to single quotes, (b) introduces a space around `=`, or
(c) factors the value out to a variable (e.g.,
`readonly K8S_NET_SUBNET="${K8S_NET_SUBNET_OVERRIDE:-172.30.0.0/16}"`)
would fail the test despite preserving the invariant. This is a
brittle structural test rather than a behavioral test.

**Fix:** Either loosen the regex to match either quoting style and
tolerate variable expansion, or shift to a behavioral check that
sources the script and verifies the resolved values. A minimal
loosening:

```bash
run grep -E "^readonly K8S_NET_SUBNET=['\"]172\.30\.0\.0/16['\"]" "$SCRIPT"
```

---

### WARN-09: `image-tag.sh` `cut -d= -f2` truncates values containing `=`

**File:** `images/image-tag.sh:27-28`

**Issue:**

```bash
K3S_TAG="$(grep -E '^ARG K3S_TAG=' "$DOCKERFILE" | head -1 | cut -d= -f2)"
CUDA_TAG="$(grep -E '^ARG CUDA_TAG=' "$DOCKERFILE" | head -1 | cut -d= -f2)"
```

`cut -d= -f2` returns the field between the first and second `=`. Current
values (`v1.34.6-k3s1`, `12.8.1-base-ubuntu22.04`) have no `=` so this
works, but any future ARG with an `=` embedded in its default (e.g.
`ARG EXTRA_FLAGS=foo=bar`) would be silently truncated to `foo`.

**Fix:**
```bash
K3S_TAG="$(grep -E '^ARG K3S_TAG=' "$DOCKERFILE" | head -1 | cut -d= -f2-)"
CUDA_TAG="$(grep -E '^ARG CUDA_TAG=' "$DOCKERFILE" | head -1 | cut -d= -f2-)"
```

## Info

### INFO-01: D-04 referenced in header comment but not listed in "Decisions honored"

**File:** `scripts/create-clusters.sh:8,25`

**Issue:** Line 8 lists `D-07, D-08, D-09, D-11, D-12, D-13` as honored
decisions, but line 25 references `(D-11, D-04)`. Either D-04 should
be added to the line-8 header or removed from line 25.

**Fix:** Pick one list and reconcile.

---

### INFO-02: `<OWNER>` placeholder in OCI source label

**File:** `images/Dockerfile.k3s-cuda:36`

**Issue:** `LABEL org.opencontainers.image.source="https://github.com/<OWNER>/karyon"`
ships a literal `<OWNER>` placeholder. If the image is ever pushed to
a registry it will advertise a broken URL. Current image is local-only,
so impact is minimal.

**Fix:** Either substitute a real owner at build time via an ARG
(`ARG REPO_OWNER`, then `LABEL ...="https://github.com/${REPO_OWNER}/karyon"`)
or delete the label until an owner is settled.

---

### INFO-03: `CUDA_TAG` ARG not re-declared after final FROM (asymmetric)

**File:** `images/Dockerfile.k3s-cuda:30-34`

**Issue:** `K3S_TAG` and `DEVICE_PLUGIN_VERSION` are re-declared after
the final FROM (lines 33–34), but `CUDA_TAG` is not. Today `CUDA_TAG`
is not referenced in the final stage, so this is harmless. The
asymmetry invites a bug if a future maintainer tries to reference
`${CUDA_TAG}` in a LABEL or ENV and is surprised when it expands to
empty.

**Fix:** Re-declare for consistency:
```dockerfile
ARG K3S_TAG
ARG CUDA_TAG
ARG DEVICE_PLUGIN_VERSION
```

---

### INFO-04: `/tmp/preflight-$$.log` not cleaned up on failure path and is predictable

**File:** `scripts/create-clusters.sh:35-41`

**Issue:** On preflight failure, the script exits 1 leaving
`/tmp/preflight-$$.log` on disk (by design, to let the user read it).
Repeated failures accumulate. The predictable filename also creates a
minor `/tmp` symlink-race surface on shared boxes. Impact is low on
single-user dev machines.

**Fix:** Use `mktemp`:
```bash
LOG="$(mktemp -t preflight.XXXXXXXX.log)"
if ! bash "${SCRIPT_DIR}/preflight.sh" > "$LOG" 2>&1; then
  fail "preflight has blockers — Log: ${LOG}"
  exit 1
fi
rm -f "$LOG"
```

---

### INFO-05: Dockerfile `COPY --from=k3s / /` ordering is fragile

**File:** `images/Dockerfile.k3s-cuda:60-61`

**Issue:** The NVIDIA container toolkit install (lines 44–56) runs
**before** `COPY --from=k3s / / --exclude=/bin`. The rancher/k3s image
is currently sparse, so the overlay does not clobber
`/usr/bin/nvidia-container-runtime` or `/etc/containerd/...`. But this
is an implicit contract on the rancher/k3s image layout. A future k3s
image carrying e.g. `/usr/bin/*` or `/etc/*` content could silently
displace toolkit files. A comment or explicit `--exclude` list for
`/usr` paths would future-proof this.

**Fix:** Either pin behavior with more `--exclude` flags:

```dockerfile
COPY --from=k3s / / --exclude=/bin --exclude=/usr --exclude=/etc
```

or flip the order — do the COPY first, then install nvidia tooling
last so the toolkit wins any collision.

---

### INFO-06: bats test_helper sources preflight-lib via `SCRIPTS_DIR` but computes `REPO_ROOT` separately

**File:** `tests/bats/test_helper.bash:9,22`

**Issue:** Both `SCRIPTS_DIR` (line 9) and `REPO_ROOT` (line 22) are
derived from `$(dirname "${BATS_TEST_FILENAME:-$0}")/../..` with
identical logic. DRY suggests computing once:

```bash
REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME:-$0}")/../.." && pwd)"
SCRIPTS_DIR="${REPO_ROOT}/scripts"
IMAGES_DIR="${REPO_ROOT}/images"
```

Currently correct, but the duplication will drift if one path is
refactored and the other isn't.

**Fix:** Derive `SCRIPTS_DIR` from `REPO_ROOT` as above.

---

_Reviewed: 2026-04-24T18:01:50Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
