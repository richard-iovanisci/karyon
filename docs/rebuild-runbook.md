# Rebuild Runbook

`task rebuild` is the lab's scorched-earth recovery procedure. It chains
`destroy → create-clusters → bootstrap-flux → register-spokes →
deploy-examples → health-check` and ends in a green health gate. On a warm
CUDA image cache and the author's dev box (Windows 11 + WSL2 + RTX 5090 +
20 cores / 52 GB RAM), the chain completed in **190 seconds**
(`/tmp/karyon-rebuild.log` rebuild elapsed seconds: 190).

This document walks each step with expected wall-clock timing and points to
the relevant remediation if anything fails.

> **Timing disclaimer.** All per-step timings below are illustrative for a
> warm CUDA image cache on RTX 5090 / 20-core dev box. Cold-cache rebuilds
> (first run after `docker builder prune` — which the lab explicitly avoids;
> see DESTROY-04) add ~5-10 minutes to step 3. Hardware that doesn't meet
> the lab's floor (16 cores / 40 GB RAM / 100 GB free) will measure
> longer; re-time on your own dev box and update if the difference is
> material.

***

## Pre-flight: Confirm `.env` and tools

Before running `task rebuild`, the lab assumes:

1. `.env` exists at the repo root with valid `GITHUB_OWNER`, `GITHUB_REPO`,
   `GITHUB_TOKEN` (the latter is a real GitHub PAT with `repo` scope; the
   placeholder `ghp_REPLACE_WITH_PAT_WITH_repo_SCOPE` will pass preflight
   but `flux bootstrap github` will fail authentication).
2. The asdf shim path is in `PATH` (run `source ~/.bashrc` after a fresh
   `bash scripts/install-tools.sh`).
3. `task preflight` exits 0 (read-only check; if it doesn't, fix the
   blockers listed in its output before proceeding to step 1 below).

To start a rebuild:

```bash
task rebuild
# Type "yes" to confirm the destructive operation.
```

***

## Step 1: `>>> step preflight` (~5 seconds)

The wrapper runs `bash scripts/preflight.sh` first as a fail-fast gate
before anything destructive happens. Read-only; idempotent. Exits 0 on
green / 1 on any blocker.

If this step fails, the rebuild ABORTS before destroy. Read the preflight
output to find the failing check (PRE-01..14 — the most common are
PRE-09 `.env` keys missing, PRE-10 a system kubectl ahead of the asdf shim
in `PATH`, PRE-11 `systemd-resolved`'s `127.0.0.53` leaking into
containers).

***

## Step 2: `>>> step destroy` (~10 seconds)

`KARYON_DESTROY_APPROVED=yes bash scripts/destroy.sh` skips the
script-level prompt (the user already confirmed at the rebuild prompt) and
delegates to `scripts/delete-clusters.sh`, which:

1. `k3d cluster delete spoke-apps spoke-ml hub-flux` (in that order).
2. `docker network rm k8s-net` (idempotent — error tolerated if already
   gone).

CRITICAL: `delete-clusters.sh` does NOT call `docker system prune` or
`docker builder prune`. The custom `karyon/k3s-cuda` image must survive
this step or the next one slows from ~45 seconds to ~5-10 minutes. If
`docker images | grep karyon/k3s-cuda` is empty after this step, see the
[Common failures](#common-failures) appendix entry "CUDA image
disappeared".

***

## Step 3: `>>> step create-clusters` (~45 seconds)

`bash scripts/create-clusters.sh`:

1. Idempotently creates the `k8s-net` Docker bridge network on
   `172.30.0.0/16`.
2. `k3d cluster create hub-flux --api-port 6443 --network k8s-net
   --k3s-arg '--tls-san=k3d-hub-flux-server-0@server:*' …`
3. `k3d cluster create spoke-ml --api-port 6444 --network k8s-net
   --gpus all --image karyon/k3s-cuda:<tag> …`
4. `k3d cluster create spoke-apps --api-port 6445 --network k8s-net …`

This step is the single longest leg on warm cache because the k3s server
container has to come up on each cluster and its CoreDNS / Traefik /
local-path-provisioner pods have to land Ready. On cold cache (CUDA image
not present), the pull from `nvcr.io/nvidia/cuda:12.8.1-base-ubuntu22.04`
adds 5-10 minutes.

After this step, `kubectl --context k3d-spoke-ml get nodes` should show
`Ready` and the device-plugin DaemonSet should be advertising
`nvidia.com/gpu` capacity.

***

## Step 4: pin context (`>>> pin context k3d-hub-flux`) (instant)

`kubectl config use-context k3d-hub-flux`. Required because
`create-clusters.sh` finishes with the kubectl context pointing at
`k3d-spoke-apps` (the last-created cluster), and the next steps assume the
hub context. Phase 5 HIGH-1 fix (see STATE.md decision log).

***

## Step 5: `>>> step bootstrap-flux` (~30 seconds)

`bash scripts/bootstrap-flux.sh` runs `flux bootstrap github --path
clusters/hub-flux`. Idempotent — skip-message contract documented in
[`flux-hub-spoke.md`](flux-hub-spoke.md). Installs the four flux-system
controllers and seeds the GitRepository pointing at `$GITHUB_OWNER/$GITHUB_REPO`.

The bootstrap is reconciliation-based: edits to
`clusters/hub-flux/flux-system/` will be reverted by the next reconcile
unless they're applied to `kustomization.yaml` (the supported patch
surface — see [`flux-hub-spoke.md`](flux-hub-spoke.md)).

***

## Step 6: `>>> step register-spokes` (~30 seconds)

`bash scripts/register-spokes-for-flux.sh` provisions a `flux-reconciler`
ServiceAccount + cluster-admin ClusterRoleBinding + a legacy
`kubernetes.io/service-account-token` Secret on each spoke; encodes the
kubeconfig (server + CA + bearer token) into a
`flux-system/<spoke>-kubeconfig` Secret on the hub under key `value.yaml`;
authors hub-side `Kustomization` resources under
`clusters/hub-flux/spokes/<spoke>.yaml` with explicit
`spec.kubeConfig.secretRef`.

Phase 4 P18 silent-misroute defense applies — see
[`adr/0004-hub-only-flux-control-plane.md`](adr/0004-hub-only-flux-control-plane.md).

***

## Step 7: `>>> step deploy-examples` (~30 seconds)

`bash scripts/deploy-examples.sh` ensures the GitRepository on `hub-flux`
has reconciled past the post-register-spokes commit (a brief Git pull /
sync + a Flux source refresh) and waits for the spoke Kustomizations to
report `Ready=True`. After this step, podinfo is running on `spoke-apps`
in the `podinfo` namespace and the `nvidia-smi` Job is complete on
`spoke-ml` in the `gpu-smoke` namespace.

***

## Step 8: `>>> step health-check` (~40 seconds)

`bash scripts/health-check.sh` is the final read-only verification gate. It
checks, in order:

1. All 3 k3d clusters exist; nodes Ready.
2. Flux controllers Ready on `hub-flux`; `flux check` passes.
3. Every spoke `Kustomization` reports `Ready=True`.
4. In-hub-pod DNS resolves `k3d-spoke-ml-server-0` and
   `k3d-spoke-apps-server-0` (catches stale CoreDNS NodeHosts).
5. `spoke-ml` reports `nvidia.com/gpu` capacity > 0.
6. Each spoke apiserver's serving cert includes its expected
   `--tls-san` SAN (openssl probe).
7. Workload proofs: podinfo Deployment Available; `nvidia-smi` Job
   completed.

If health-check fails, the runbook does NOT auto-recover — that is by
design (HEALTH-04 is read-only). Use the [Common failures](#common-failures)
appendix to map the failing check to the right `task` recovery.

If health-check passes, the chain logs `rebuild elapsed seconds: <total>`
and the wrapper exits 0. The 1200-second SLO ceiling is enforced — over
that, the wrapper exits non-zero (DESTROY-06).

***

## Total Expected Wall-Clock

| Cache State | Total | Notes |
|-------------|-------|-------|
| Warm (CUDA image present) | ~190 seconds | The Phase 5 baseline. |
| Cold (image must be pulled / rebuilt) | ~10-15 minutes | First-ever rebuild OR after an accidental `docker system prune`. |
| Hardware below floor | longer; re-time | Re-baseline on your own dev box and update locally. |

***

## Common failures

Mid-incident reference. Each entry maps a symptom seen in
`/tmp/karyon-rebuild.log` (or in `task health-check` output) to the
recommended `task` recovery and the docs to consult.

### "Stale CoreDNS NodeHosts" — DNS probe in step 8 fails after Docker / WSL restart

**Symptom:** `health-check.sh` reports DNS probe failed for
`k3d-spoke-ml-server-0` (or `k3d-spoke-apps-server-0`); cluster otherwise
healthy.

**Recovery:**

```bash
task fix-dns
task health-check
```

`task fix-dns` stops and starts only the hub cluster (NOT the spokes); the
hub's CoreDNS picks up fresh Docker NodeHosts on restart. This is the
documented k3d#1009 / #1112 workaround — see HEALTH-07 in REQUIREMENTS.md.
Documented further in [`flux-hub-spoke.md`](flux-hub-spoke.md).

### "Missing GPU capacity on spoke-ml" — `nvidia.com/gpu` is 0

**Symptom:** step 8 (health-check) reports `spoke-ml` capacity for
`nvidia.com/gpu` is 0 OR the smoke-test Job loops in `CrashLoopBackOff`.

**Recovery:** the 3-part k3d GPU contract is broken at one of its three
legs.

1. `docker info | grep "Default Runtime"` should return `nvidia` (Part 1).
   If not, re-run `bash scripts/install-docker.sh`.
2. `docker images | grep karyon/k3s-cuda` should show at least one tag
   (Part 2). If not, re-run `task build-image`.
3. Inside `spoke-ml`, `cat /var/lib/rancher/k3s/agent/etc/containerd/config.toml
   | grep default_runtime_name` should return `nvidia` (Part 3). If not,
   the custom image is wrong; re-run `task build-image` and re-create.

Full diagnosis procedure in [`gpu-notes.md`](gpu-notes.md).

### "TLS-SAN mismatch" — `flux` reconciliation reports cert verification failure

**Symptom:** `flux get kustomizations -A` shows a spoke Kustomization
`Ready=False` with reason `connection refused`, `x509: certificate is
valid for ...` errors in the kustomize-controller logs.

**Recovery:** `--tls-san` is immutable after k3d cluster creation
(CLU-05). The fix is to recreate the cluster with the right SANs:

```bash
task destroy        # only delete the affected cluster if you can; full
                    # rebuild is simpler since the chain is fast.
task rebuild
```

Confirm the fix:

```bash
openssl s_client -connect 127.0.0.1:6444 </dev/null 2>/dev/null \
  | openssl x509 -noout -text \
  | grep -F 'k3d-spoke-ml-server-0'  # MUST match
```

### "CUDA image disappeared" — step 3 takes 10+ minutes instead of ~45 seconds

**Symptom:** `task rebuild` total exceeds the 1200-second SLO; the wrapper
exits non-zero with the elapsed time logged in `/tmp/karyon-rebuild.log`.

**Recovery:** the build cache or image was pruned. Confirm:

```bash
docker images | grep karyon/k3s-cuda    # if empty, the image is gone
```

If gone, rebuild it once (this run will take 5-10 minutes; subsequent
rebuilds are warm again):

```bash
task build-image
task rebuild
```

DESTROY-04 ensures `scripts/` does not call `docker system prune` /
`docker builder prune`; if the cache vanished, an external action did it
(e.g., a manual `docker system prune` or a Docker Desktop integration that
ran prune behind the scenes).

### "Flux bootstrap PAT invalid" — step 5 fails with auth error

**Symptom:** `bootstrap-flux.sh` exits non-zero; the script's output
includes `401 Unauthorized` from the GitHub API.

**Recovery:** rotate the PAT.

1. Generate a new PAT in the GitHub UI (Settings → Developer settings →
   Personal access tokens) with `repo` scope.
2. Update `.env`'s `GITHUB_TOKEN` line locally (do NOT commit `.env` —
   .gitignore enforces this).
3. Re-run `task rebuild` (or just `task bootstrap-flux` if everything
   else is intact).

### ".env missing keys" — step 1 fails with PRE-09

**Symptom:** `preflight.sh` exits non-zero; the failing check is PRE-09
"GITHUB_OWNER/GITHUB_REPO/GITHUB_TOKEN missing in .env".

**Recovery:**

```bash
cp .env.example .env       # if .env doesn't exist
$EDITOR .env                # populate the 3 keys with real values
task preflight              # re-verify
```

### "WSL2 mirrored mode" — Docker custom networks cannot be bridged

**Symptom:** preflight PRE-14 fails the bridge-curl probe; clusters
created but nothing reaches them.

**Recovery:** switch WSL2 to NAT mode. Procedure documented in
[`wsl-networking.md`](wsl-networking.md) section "Migration: mirrored to
NAT".

***

## Reference

- Topology: [`architecture.md`](architecture.md)
- Flux patch-surface contract: [`flux-hub-spoke.md`](flux-hub-spoke.md)
- 3-part k3d GPU contract: [`gpu-notes.md`](gpu-notes.md)
- WSL2 networking modes: [`wsl-networking.md`](wsl-networking.md)
- ADRs: [`adr/`](adr/)
- The rebuild log path: `/tmp/karyon-rebuild.log` (NOT committed; rotated on every `task rebuild`)
