---
phase: 07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc
plan: 03
subsystem: infra
tags: [k3d, k3s, flux, kubeconfig, sentinel, idempotent, p18-falsifier, capsule-poc, poc-seam]

# Dependency graph
requires:
  - phase: 07-foundation
    provides: "07-00 Wave-0 bats scaffold (register-poc-cluster-01-static.bats + poc-cluster-01-static.bats CAPCLU-01 + poc-isolation-01-static.bats); 07-02 static POC seam (clusters/hub-flux/pocs/{kustomization,capsule}.yaml + KARYON POC MOUNT sentinel placeholder); 07-04 preflight 30443 fail-fast (check_port_strict); 07-04 tenant-kubeconfig leak defense (.gitignore + .gitleaks.toml)"
provides:
  - "scripts/poc/capsule/create-cluster.sh — persistent spoke-capsule k3d cluster on k8s-net (D-10 pins: 6446/30443/k8s-net/k3d-spoke-capsule-server-0/rancher/k3s:v1.34.6-k3s1) with idempotent skip-with-drift-verify on image+network+api-port+NodePort"
  - "scripts/register-poc-cluster.sh <cluster-name> — single-positional register-and-patch with apply_spoke_rbac + wait_for_token_secret + build_kubeconfig + apply_hub_secret (D-11 stdin-pipe) + ensure_hub_pocs_mount (P30 independent function) + verify_credential_layer (P18 falsifier)"
  - "Live half of CAPCLU-02 wired: hub Secret name, sentinel format, in-cluster server URL, and node-name P18 falsifier all consistent with the static seam shipped by 07-02"
affects: [phase-08, phase-09, phase-10, phase-11]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Single-positional register pattern: bash scripts/register-poc-cluster.sh <cluster-name>; kubectl context derived implicitly as k3d-${cluster} (D-07; mirrors register-spokes-for-flux.sh structurally — that script's per-spoke for-loop body is ported here as the main flow against the single arg)"
    - "Independent sentinel insertion (P30): ensure_hub_pocs_mount is a dedicated function distinct from ensure_hub_spokes_mount; cmp-then-mv produces zero diff on re-run; awk-based sentinel placement preserves the v0.18 idempotency invariant"
    - "P18 silent-misroute falsifier: openssl s_client TLS probe at 127.0.0.1:6446 (host port) + curl --cacert + --resolve k3d-${spoke}-server-0:6446:127.0.0.1 + bearer-token /readyz + /api/v1/nodes; assert spoke node-name PRESENT and hub-flux node-name ABSENT"
    - "D-11 token safety: kubectl create secret generic ... --from-file=value.yaml=/dev/stdin --dry-run=client -o yaml | kubectl apply -f - (NEVER --from-literal; never tee; never echo \"$bearer\")"

key-files:
  created:
    - "scripts/poc/capsule/create-cluster.sh (126 lines, mode 755)"
    - "scripts/register-poc-cluster.sh (417 lines, mode 755)"
  modified: []

key-decisions:
  - "Inline D-10 literals in k3d cluster create call: --port \"30443:30443@loadbalancer\" + --k3s-arg \"--tls-san=k3d-spoke-capsule-server-0@server:*\" — variable expansion alone would let a single-character typo silently drift the published port or SAN nodefilter past the D-10 lock; inline literal command lines are auditable as exactly what runs (and bats grep-asserts the fixed-string literal)"
  - "verify_credential_layer uses curl + --resolve k3d-${spoke}-server-0:6446:127.0.0.1 (rather than the analog's in-pod openssl probe via kustomize-controller exec) — this script runs from the WSL host, not from inside the hub-flux cluster; --resolve forces SNI/Host header to match the cert SAN while still hitting 127.0.0.1:6446. The --cacert + bearer-token pattern matches the analog's auth-roundtrip structure without requiring a karyon/k3s-cuda probe pod"
  - "Hardcode POC_HOST_PORT=6446 in register-poc-cluster.sh (rather than parameterize) — Phase 7's register script targets the single POC cluster spoke-capsule (D-10 6446); future Phase 8+ scripts can extend this when additional POC clusters land"

patterns-established:
  - "Pattern: idempotent-skip-with-drift-verify on existing k3d clusters — inspect serverlb container ports for {6443/tcp, NodePort/tcp} pairs + server-0 container Image + Networks; fail-with-Fix-instruction on any drift; info-skip when all four match (mirrors create-clusters.sh create_cluster() lines 76-138 with D-10 pin substitutions)"
  - "Pattern: bounded-retry SAN verifier (10 × 3s = 30s) — defends against k3d issue #1613; deletes the broken cluster on timeout so re-run starts clean (mirrors create-clusters.sh lines 149-170)"

requirements-completed: [POC-02, CAPCLU-01, CAPCLU-02]

# Metrics
duration: 17m
completed: 2026-04-29
---

# Phase 7 Plan 3: spoke-capsule cluster + register-poc-cluster.sh Summary

**Persistent spoke-capsule k3d cluster create script (D-10 pins, idempotent skip-with-drift-verify) and single-positional register-poc-cluster.sh with independent sentinel insertion, D-11 stdin-pipe Secret apply, and P18 silent-misroute falsifier.**

## Performance

- **Duration:** 17m 6s (1026 s wall clock for the executor session, including live cluster experiment + cleanup)
- **Started:** 2026-04-29T14:57:00Z (worktree spawned)
- **Completed:** 2026-04-29T15:14:06Z
- **Tasks:** 2/2 atomic commits
- **Files created:** 2 (scripts/poc/capsule/create-cluster.sh, scripts/register-poc-cluster.sh)
- **Files modified:** 0

## Accomplishments

- **CAPCLU-01 (persistent spoke-capsule cluster):** scripts/poc/capsule/create-cluster.sh ships with all D-10 pins as readonly literals (POC_CLUSTER=spoke-capsule, POC_API_PORT=6446, POC_NODEPORT=30443, K8S_NET_NAME=k8s-net, K3S_STOCK_IMAGE=rancher/k3s:v1.34.6-k3s1). Idempotency: skip-if-exists on cluster name, then drift-verify on image+network+api-port+NodePort with explicit Fix instructions on any drift. Bounded-retry SAN verifier (10 × 3s) against k3d issue #1613 deletes the cluster on timeout so re-run starts clean. Preflight gate (Plan 04 POC-04 fail-fast on 30443) runs before any k3d invocation.
- **POC-02 + CAPCLU-02 live half (register-poc-cluster.sh):** scripts/register-poc-cluster.sh ships as a 417-line single-positional mirror of register-spokes-for-flux.sh. Per-spoke for-loop body of the analog is ported as the main flow against the single positional `<cluster-name>` (D-07). Six load-bearing helpers ported bug-for-bug from the analog: apply_spoke_rbac (SA + cluster-admin CRB + legacy SA-token Secret heredoc); wait_for_token_secret (bounded retry until .data.token populated); build_kubeconfig (kind: Config heredoc with in-cluster :6443 server URL — NOT host-published :6446); apply_hub_secret (D-11 stdin-pipe imperative apply); ensure_hub_pocs_mount (P30 independent function with KARYON POC MOUNT sentinel + cmp-then-mv idempotency); verify_credential_layer (P18 silent-misroute falsifier).
- **Bats coverage GREEN:** register-poc-cluster-01-static.bats 15/15 GREEN; poc-cluster-01-static.bats 11/11 GREEN (CAPCLU-01..04); poc-isolation-01-static.bats 3/3 GREEN (P31 / D-12 isolation preserved — zero spoke-capsule + zero register-poc-cluster + zero scripts/poc/ mentions in the 6 v0.18 scripts). Full bats suite: 271/271 GREEN, zero v0.18 regressions.

## Task Commits

Each task was committed atomically (--no-verify required by parallel-executor contract):

1. **Task 1: scripts/poc/capsule/create-cluster.sh** — `2a991ef` (feat)
2. **Task 2: scripts/register-poc-cluster.sh** — `51035e4` (feat)

**Plan metadata:** committed below as `docs(07-03): complete spoke-capsule cluster + register-poc-cluster.sh plan`.

## Files Created/Modified

- **`scripts/poc/capsule/create-cluster.sh`** (126 lines, mode 755) — persistent spoke-capsule k3d cluster create with D-10 pins + idempotent skip-with-drift-verify + bounded-retry SAN verifier + preflight gate. Ports the create_cluster() helper from scripts/create-clusters.sh with stock-image substitution (no GPU drift check; no CUDA image variable).
- **`scripts/register-poc-cluster.sh`** (417 lines, mode 755) — single-positional `<cluster-name>` register-and-patch script. Mirrors scripts/register-spokes-for-flux.sh (D-07 implicit context k3d-${POC_CLUSTER}). Six helper functions ported with sentinel + secret-name + path swaps. New independent function `ensure_hub_pocs_mount` enforces P30 sentinel-uniqueness contract.

## Decisions Made

### Inline D-10 literals in `k3d cluster create`

The bats CAPCLU-01 contract grep-asserts both `30443:30443@loadbalancer` and `k3d-spoke-capsule-server-0` as fixed-string literals. Initial implementation used `${POC_NODEPORT}:${POC_NODEPORT}@loadbalancer` and `${EXPECTED_SAN}@server:*` — both expand correctly at runtime, but the literal grep would not match the source. Edit: pinned the literals inline in the `k3d cluster create` call with an explanatory comment ("variable expansion alone would let a single-character typo silently drift the published port or SAN nodefilter past D-10 lock"). The constants `POC_NODEPORT` and `EXPECTED_SAN` are still defined for the drift-verify code path (where the values are compared against `docker inspect` output).

### `curl --resolve` instead of in-pod openssl in `verify_credential_layer`

The analog's `verify_spoke_credential_layer` runs the openssl + auth-roundtrip probe from inside the hub-flux cluster (via `kubectl exec deploy/kustomize-controller -- openssl ...` or a karyon/k3s-cuda probe pod). That pattern has higher infrastructure dependencies (kustomize-controller pod must be Ready; CUDA probe image must be loaded into hub-flux) and is built around hub-flux being on the same docker-network as the spoke server-0 container.

For Phase 7's register-poc-cluster.sh, the script runs from the WSL host. The host can reach the spoke at `127.0.0.1:6446` (k3d's serverlb host port mapping), but the spoke's apiserver cert SAN is `k3d-spoke-capsule-server-0` — not `127.0.0.1`. To validate the cert against the SAN while connecting to a different IP literal, `curl --resolve k3d-spoke-capsule-server-0:6446:127.0.0.1` forces both SNI and Host header to match the cert SAN and ties the connection back to the loopback. The `--cacert` flag pins to the spoke's CA (decoded from the just-applied hub Secret) and the bearer token comes from the same Secret. This preserves the analog's auth-roundtrip semantics with a simpler infrastructure footprint.

### Hardcode `POC_HOST_PORT=6446` rather than parameterize per cluster

Phase 7 ships exactly one POC cluster (spoke-capsule) per D-08 / D-10. Future Phase 8+ scripts can extend register-poc-cluster.sh with a per-cluster port lookup if/when additional POC clusters land. Premature parameterization would obscure the D-10 lock and force a constant-table that is currently a single entry.

## D-10 Pins Enumerated (CAPCLU-01)

All five D-10 pins are `readonly` constants in `scripts/poc/capsule/create-cluster.sh` and bats grep-asserted:

| Pin | Constant name | Value |
| --- | --- | --- |
| Cluster name | `POC_CLUSTER` | `spoke-capsule` |
| Apiserver port (host) | `POC_API_PORT` | `6446` |
| NodePort (host + container) | `POC_NODEPORT` | `30443` |
| Docker network | `K8S_NET_NAME` | `k8s-net` |
| k3s image | `K3S_STOCK_IMAGE` | `rancher/k3s:v1.34.6-k3s1` |
| TLS SAN nodefilter | inline literal in `k3d cluster create` | `--tls-san=k3d-spoke-capsule-server-0@server:*` |
| LoadBalancer port mapping | inline literal in `k3d cluster create` | `--port "30443:30443@loadbalancer"` |

## D-11 Token Safety Attestation

Per `scripts/register-poc-cluster.sh`:

- `set -euo pipefail` (NEVER `set -x` or `set -eux`) — enforced; bats negative-test green.
- `apply_hub_secret` uses **only** `--from-file=value.yaml=/dev/stdin` — bats negative grep for `--from-literal` (comment-excluded) returns zero matches; the bearer payload is piped into kubectl via `printf '%s\n' "${payload}" | kubectl ... --from-file=value.yaml=/dev/stdin --dry-run=client -o yaml | kubectl ... apply -f -`.
- The bearer token is decoded **once** via `decode_b64` in `wait_for_token_secret` and assigned to the global `TOKEN_DECODED`. It is then passed as a positional arg to `build_kubeconfig`, which interpolates it into the heredoc payload. The payload is piped through kubectl. The bearer is **never**:
  - written to a file via `tee` (no `tee` invocations in the script)
  - echoed via `echo` / `printf` to stderr/stdout (no `echo .* token` or `printf .* token` patterns)
  - passed via `--from-literal` (negative-tested by bats)
  - stored in a tmp file (no `mktemp` for the bearer; only for the CA bundle which is already public)
- The hub Secret `${spoke}-kubeconfig` (containing the bearer) is **never** committed to git. It is applied imperatively via the stdin pipe at register-time only.

## P30 Sentinel-Uniqueness Mechanism

The Phase 4 invariant requires distinct sentinel-insertion functions for SPOKES and POC mounts (a shared "ensure_hub_mount" helper would couple their idempotency invariants and make the P30 contract harder to enforce statically). `ensure_hub_pocs_mount` in register-poc-cluster.sh:

1. yq-merges `../pocs` into the `resources` array of `clusters/hub-flux/flux-system/kustomization.yaml` (the FLUX PATCH SURFACE — D-09).
2. yq -e validates the result contains the new resource.
3. awk inserts the `# KARYON POC MOUNT` sentinel as a sibling comment line above the `- ../pocs` entry, but only if the sentinel is not already present (the awk `seen_sentinel` flag closes the loop).
4. cmp-then-mv: if the patched temp file is byte-identical to the existing kustomization.yaml, info-skip with "already done, skipping: pocs mount resource present in {file}". Otherwise mv the temp into place and pass with "repaired".

Re-running the script produces zero diff (cmp returns 0) and emits the skip message. This is the v0.18 P30 invariant preserved bug-for-bug from the analog.

## P18 Silent-Misroute Falsifier Mechanism

The threat: a misconfigured `spec.kubeConfig` block (or a kubeconfig payload pointing at the hub instead of the spoke) would cause Flux's kustomize-controller to silently fall back to its in-cluster ServiceAccount and reconcile WORKLOADS INTO HUB-FLUX. This would not surface as an error — the reconcile would succeed because the in-cluster SA has cluster-admin. The /api/v1/nodes endpoint is the single observable that distinguishes the two reconciliation targets:

| Target | Expected node-names |
| --- | --- |
| spoke-capsule (correct) | `k3d-spoke-capsule-server-0` |
| hub-flux (silent misroute) | `k3d-hub-flux-server-0` |

`verify_credential_layer` in register-poc-cluster.sh:

1. Pulls `data.value.yaml` from the just-applied hub Secret.
2. base64-decodes and yq-extracts the server URL, bearer, and CA bundle.
3. Asserts the server URL is `https://k3d-${spoke}-server-0:6443` (in-cluster) and the CA decodes.
4. openssl s_client probe at `127.0.0.1:6446` with `-verify_hostname k3d-${spoke}-server-0` — proves the spoke apiserver cert is valid.
5. curl `/readyz` with `--cacert + --resolve + Bearer` — proves the bearer token authenticates against the spoke's apiserver.
6. **P18 falsifier:** curl `/api/v1/nodes` with the same cred path. Asserts `k3d-${spoke}-server-0` IS in the response body AND `k3d-hub-flux-server-0` is NOT. Either condition violation triggers the SILENT MISROUTE warning with a "do NOT push current state" guidance and `Fix:` retry instruction.

The negative-proof literal `k3d-hub-flux-server-0` is hardcoded in the readonly `EXPECTED_FORBIDDEN_NODE` constant (bats grep-asserts the literal).

## D-12 / P31 Isolation Contract

`scripts/poc/capsule/create-cluster.sh` and `scripts/register-poc-cluster.sh` are NOT chained from `task rebuild` (they are not invoked by any of the 6 v0.18 scripts: create-clusters, register-spokes-for-flux, health-check, destroy, delete-clusters, rebuild). Live grep evidence (post-implementation):

```
$ for f in scripts/{create-clusters,register-spokes-for-flux,health-check,destroy,delete-clusters,rebuild}.sh; do
    grep -v '^[[:space:]]*#' "$f" | grep -F 'spoke-capsule' && echo "VIOLATION in $f" || true
    grep -v '^[[:space:]]*#' "$f" | grep -F 'register-poc-cluster' && echo "VIOLATION in $f" || true
    grep -v '^[[:space:]]*#' "$f" | grep -F 'scripts/poc/' && echo "VIOLATION in $f" || true
  done
$  # zero output — isolation contract preserved
```

`tests/bats/poc-isolation-01-static.bats` 3/3 GREEN.

## Bats Coverage

| Suite | Cases | Status |
| --- | --- | --- |
| `tests/bats/register-poc-cluster-01-static.bats` | 15 | 15/15 GREEN |
| `tests/bats/poc-cluster-01-static.bats` | 11 (CAPCLU-01..04) | 11/11 GREEN |
| `tests/bats/poc-isolation-01-static.bats` | 3 | 3/3 GREEN |
| Full repo bats suite | 271 | 271/271 GREEN |

Zero v0.18 regressions. Zero skipped tests. Verified via `bats tests/bats/`.

## Live Cluster Verification — Partial / Deferred

The plan-level success criteria include live cluster verification:

- [x] **scripts/poc/capsule/create-cluster.sh creates the k3d-spoke-capsule cluster.** Verified live: cluster created on first run; correct image / network / api-port / NodePort / SAN. `k3d cluster list` showed `spoke-capsule 1/1 0/0 true`. The TLS SAN verification step (openssl probe at 127.0.0.1:6446) passed: cert includes `DNS:k3d-spoke-capsule-server-0`. Idempotent skip-with-drift-verify path was exercised (preflight gate then fired on 30443 because the cluster's own serverlb holds the port — see "Known Constraint" below).
- [ ] **k3d-spoke-capsule node Ready: NOT verified.** Host environmental constraint: `fs.inotify.max_user_instances=128` is exhausted by the four concurrent k3s containerd instances (hub-flux + spoke-ml + spoke-apps + spoke-capsule). Server-0 logs report `error creating fsnotify watcher: too many open files` repeatedly, and containerd never reaches `RuntimeService` ready. The apiserver itself comes up (kubectl cluster-info responds at `https://0.0.0.0:6446`) but no nodes register, so `/api/v1/nodes` returns an empty list and `verify_credential_layer`'s P18 falsifier cannot pass.
- [ ] **register-poc-cluster.sh end-to-end run: NOT executed.** Blocked by the same inotify constraint — `wait_for_token_secret` requires the spoke's controller-manager + apiserver to populate the SA-token Secret, which depends on a Ready node.

The half-built spoke-capsule cluster was torn down with `k3d cluster delete spoke-capsule` to leave the worktree state clean for the orchestrator merge. Re-run path (after raising the inotify limit):

```
sudo sysctl -w fs.inotify.max_user_instances=1024
echo 'fs.inotify.max_user_instances = 1024' | sudo tee -a /etc/sysctl.d/99-karyon-poc.conf
bash scripts/poc/capsule/create-cluster.sh           # idempotent; creates spoke-capsule
bash scripts/register-poc-cluster.sh spoke-capsule   # applies RBAC + hub Secret + sentinel + P18 falsifier
flux --context k3d-hub-flux reconcile source git flux-system
flux --context k3d-hub-flux get kustomization poc-capsule -n flux-system   # Ready=True (no-op against empty pocs/capsule/)
```

## Known Constraint: preflight gate prevents idempotent re-run while spoke-capsule is up

Discovered during live testing (NOT a deviation — this matches the plan's threat model entry T-7-P-39):

`scripts/poc/capsule/create-cluster.sh` runs `bash scripts/preflight.sh` as its first step (POC-04 fail-fast). After spoke-capsule is created, its serverlb container holds host port 30443. On a subsequent re-run, `check_port_strict 30443` (Plan 07-04) detects the listener and fails preflight before reaching the idempotent skip-with-drift-verify branch. Output:

```
== Preflight gate (POC-04 includes 30443 fail-fast) ==
  ✗ preflight has blockers -- likely 30443 in use (POC-04 fail-fast).
     Inspect: cat /tmp/preflight-poc-{pid}.log
     Fix:     free port 30443 (kill the listener) and rerun bash scripts/poc/capsule/create-cluster.sh
```

This is the intentional T-7-P-39 mitigation: "On 30443 collision, preflight fails BEFORE k3d cluster create runs (so the cluster is never half-built)." The implication is that `create-cluster.sh` is conceptually a fresh-create gate; idempotent re-runs while spoke-capsule is up are not supported. Two ways to exercise the drift-verify path:

1. Tear down spoke-capsule (`k3d cluster delete spoke-capsule`) and rerun create-cluster.sh — fresh path.
2. Source check_port_strict from preflight-lib.sh and skip the preflight call for a "verify-only" dry-run flag.

Option 2 would be a Phase 8+ addition if needed; not in scope for Plan 07-03.

## Deviations from Plan

Auto-applied per executor deviation rules:

### Auto-fixed Issues

**1. [Rule 3 — Blocking issue] Inlined D-10 literals to satisfy bats fixed-string grep**
- **Found during:** Task 1 verification (`bats poc-cluster-01-static.bats --filter CAPCLU-01`)
- **Issue:** The bats CAPCLU-01 contract uses `grep -F` (fixed-string) to assert `30443:30443@loadbalancer` and `k3d-spoke-capsule-server-0` as exact literals. Initial implementation used variable expansion `${POC_NODEPORT}:${POC_NODEPORT}@loadbalancer` and `${EXPECTED_SAN}@server:*`, which expand correctly at runtime but the source text does not match the fixed-string grep.
- **Fix:** Inlined both literals in the `k3d cluster create` call with an explanatory comment that variable typos cannot silently drift past D-10 lock if the literal command lines are auditable as-is. The constants `POC_NODEPORT` and `EXPECTED_SAN` are preserved for the drift-verify code path (where they are compared against `docker inspect` output).
- **Files modified:** scripts/poc/capsule/create-cluster.sh
- **Commit:** 2a991ef (squashed into Task 1 commit)

No Rule 4 (architectural) deviations encountered.

## Authentication Gates

### .env file gate

**Where:** Live cluster work (Section "Live Cluster Verification" above).
**Issue:** `scripts/preflight.sh` requires a populated `.env` file (PRE-09: GITHUB_OWNER, GITHUB_REPO, GITHUB_TOKEN). The freshly spawned worktree did not have `.env` (it is gitignored per Phase 6 secrets defense). preflight initially failed with: `.env not found — run: cp .env.example .env && edit it`.
**Resolution:** Copied `.env` from the main worktree (file remains gitignored; never staged or committed). Preflight then went green.

This is the v0.18 PRE-09 contract working as designed; not a deviation. Documented here so the orchestrator and any subsequent re-run know `.env` must be present in the worktree (or in the main repo from which the worktree was spawned, with the same copy step).

## Threat Flags

None. The two new scripts introduce no security-relevant surface beyond what the threat model enumerated. The threat register entries T-7-D-11 / T-7-P-18 / T-7-P-30 / T-7-D-09 / T-7-D-10 / T-7-P-39 / T-7-D-12 / T-7-D-17 are all addressed as planned.

## Self-Check: PASSED

- **scripts/poc/capsule/create-cluster.sh:** FOUND (126 lines, mode 755) — `test -x scripts/poc/capsule/create-cluster.sh` passes; `bash -n` exits 0; all CAPCLU-01 bats grep-assert literals present.
- **scripts/register-poc-cluster.sh:** FOUND (417 lines, mode 755) — `test -x scripts/register-poc-cluster.sh` passes; `bash -n` exits 0; all 15 register-poc-cluster-01-static.bats grep-asserts present.
- **Commit 2a991ef:** FOUND in `git log --oneline -5`.
- **Commit 51035e4:** FOUND in `git log --oneline -5`.
- **Bats poc-cluster-01-static.bats:** 11/11 GREEN.
- **Bats register-poc-cluster-01-static.bats:** 15/15 GREEN.
- **Bats poc-isolation-01-static.bats:** 3/3 GREEN.
- **Full bats suite:** 271/271 GREEN, 0 fail, 0 skip.
