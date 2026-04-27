# Phase 4: Spoke Registration - Context

**Gathered:** 2026-04-27
**Status:** Ready for planning

<domain>
## Phase Boundary

Land per-spoke kubeconfig Secrets on `hub-flux/flux-system` so Flux's `kustomize-controller` can reconcile manifests into `spoke-ml` and `spoke-apps` via `spec.kubeConfig`. Highest-risk phase — DNS, TLS, CA-data, RBAC, token format, and Secret-key (`value.yaml`) all converge, with a silent-misroute failure mode (P18) where a misconfigured Secret causes Flux to fall back to its in-cluster SA and reconcile manifests into the WRONG cluster while reporting `Ready=True`. Scope:

- `scripts/register-spokes-for-flux.sh` — idempotent script with a `register_spoke <name>` helper called twice (`spoke-ml`, `spoke-apps`). Sources `scripts/lib/preflight-lib.sh`. Delegates to `scripts/preflight.sh` first. Mirrors Phase 2 `create_cluster()` shape and Phase 3 bootstrap-flux's preflight + context-gate + idempotency pattern.
- Per-spoke RBAC: `flux-reconciler` ServiceAccount + `flux-reconciler-cluster-admin` ClusterRoleBinding (cluster-admin) + `flux-reconciler-token` Secret of type `kubernetes.io/service-account-token` annotated `kubernetes.io/service-account.name=flux-reconciler` — all in `flux-system` namespace on each spoke (mirrors hub layout).
- Per-spoke kubeconfig: 5-section YAML built via heredoc with bash substitution; `certificate-authority-data` and `token` extracted from the spoke's `flux-reconciler-token` Secret in a single source of truth; `server: https://k3d-<spoke>-server-0:6443` literal (no pre-probe).
- Hub-side Secret per spoke: `<spoke>-kubeconfig` in `flux-system` ns, key `value.yaml` (explicit, locked by REQ-SPOKE-04), opaque type, applied imperatively via `kubectl apply -f -` from a heredoc (NEVER committed to git — token leak posture).
- Hub-side Flux Kustomizations: `clusters/hub-flux/spokes/spoke-ml.yaml` and `spoke-apps.yaml` written to local checkout (not committed by script); `spec.kubeConfig.secretRef.key: value.yaml` explicit; `spec.path: ./clusters/spoke-ml` and `./clusters/spoke-apps`.
- Wire-up: patch `clusters/hub-flux/flux-system/kustomization.yaml` (Phase 3 D-13 patch surface, sentinel-guarded) to add `- ../spokes` directory reference; seed `clusters/hub-flux/spokes/kustomization.yaml` listing `- spoke-ml.yaml` + `- spoke-apps.yaml`. Single top-level Flux Kustomization (`flux-system`) keeps reconciling everything.
- Negative-proof seed: `clusters/spoke-ml/kustomization.yaml` and `clusters/spoke-apps/kustomization.yaml` each create a per-spoke `Namespace` (`karyon-spoke-ml`, `karyon-spoke-apps`) plus a `ConfigMap` (`karyon-spoke-id`) in that namespace with `data.spoke=<spoke-name>` baked in — distinct per spoke, falsifiable, doesn't collide with Phase 5 workloads (which add to `./apps/`, `./infrastructure/` subdirs).
- Filling Phase 3's `<!-- Phase 4: hub-spoke reconciliation -->` stub at the bottom of `docs/flux-hub-spoke.md` with: the 6 SPOKE REQ-IDs, the `value.yaml` key contract, the P18 silent-misroute pitfall, the negative-proof guidance, and the `flux-reconciler` SA layout.
- Two bats suites under `tests/bats/`:
  - `register-spokes-01-static.bats` — static greps (filename, RBAC names, `value.yaml` key literal, no auto-push, `set -euo pipefail`, no `set -x`, no token funneling through `echo`/`printf`/`pass`/`info`/`warn`/`fail`/`tee`).
  - `register-spokes-02-live.bats` — live/destructive (`require_live_destructive` double-gate): runs script, asserts each `<spoke>-kubeconfig` Secret exists with `value.yaml` key, asserts node-name negative-proof in-pod, AND — assuming the user has pushed — asserts each spoke Kustomization is `Ready=True` and `.status.inventory` contains the seed ConfigMap UID (ROADMAP success #5).
- Append a `register-spokes` task entry to `Taskfile.yml` (single-line invocation; full REPO-05 reorganization stays Phase 6).

Out of scope (owned elsewhere):
- podinfo / `nvidia-smi` smoke-test pod / `task fix-dns` / `task health-check` / `task rebuild` chain → Phase 5.
- ADR-004 (hub-only Flux control plane) authoring → Phase 6 per ROADMAP parallelization. Phase 4 must not block on it.
- gitleaks pre-commit (REPO-04) — Phase 6. Phase 4 retains the warn-only advisory pattern from Phase 3 if applicable, but the canonical install lives in Phase 6.
- Token-rotation / Secret-renewal handling — explicitly rejected for v1; legacy SA-token Secrets have indefinite lifetime per PROJECT.md Phase-4 key decision.
- Per-namespace RBAC scoping — REQ-SPOKE-01 locks cluster-admin; namespace-scoped role narrowing is a v2 concern.

</domain>

<decisions>
## Implementation Decisions

### Script Orchestration & Wire-up

- **D-01:** **Helper function `register_spoke <name>`**, called twice (`register_spoke spoke-ml`, `register_spoke spoke-apps`). Mirrors Phase 2 `create_cluster()` pattern. Per-spoke section headers via `section "$name spoke"` make failures self-locating in the script's stdout. Loop-over-array rejected (worse error context); inline duplication rejected (~60 lines of copy-paste).
- **D-02:** **Wire-up via Phase 3 D-13 patch surface + spokes/kustomization.yaml directory reference.** Sentinel-guarded patch to `clusters/hub-flux/flux-system/kustomization.yaml` adds `- ../spokes` to `resources:`. Seed `clusters/hub-flux/spokes/kustomization.yaml` lists `- spoke-ml.yaml` + `- spoke-apps.yaml` as resources. Single top-level Flux Kustomization (`flux-system`) keeps reconciling the entire tree. This route was explicitly enabled by Phase 3 Rule 2 (`kustomization.yaml` IS the patch surface; edits survive re-bootstrap). Inline-flat-resources rejected (each new spoke = another flux-system patch). Separate top-level "spokes" Flux Kustomization rejected (one-time `kubectl apply` breaks GitOps purity).
- **D-03:** **Per-spoke `Namespace` + `ConfigMap` seed** under `clusters/spoke-ml/` and `clusters/spoke-apps/`. Each tree contains `kustomization.yaml` referencing `namespace.yaml` (creates `karyon-spoke-ml` / `karyon-spoke-apps`) + `configmap.yaml` (creates `karyon-spoke-id` in that ns with `data.spoke=spoke-ml` / `spoke-apps`). Distinct per spoke. Makes ROADMAP success #5 negative-proof falsifiable (the ConfigMap's name + ns combo only exists on the targeted spoke). Phase 5 adds workloads alongside (`./apps/`, `./infrastructure/`) without collision.
- **D-04:** **Write-local-only; no git mutations from the script.** Script writes `clusters/hub-flux/spokes/*.yaml`, `clusters/hub-flux/spokes/kustomization.yaml`, `clusters/spoke-ml/**`, `clusters/spoke-apps/**`, and the patch to `clusters/hub-flux/flux-system/kustomization.yaml`. Then `info`s the user with the exact `git add ... && git commit -m '...' && git push` line. Mirrors Phase 3 bootstrap-flux's discipline (`infos`, never auto-pushes). User retains full control of git history. Kubeconfig Secrets on the hub are applied imperatively via `kubectl apply -f -` (NOT committed — they contain bearer tokens).

### Spoke RBAC Layout

- **D-05:** **Spoke-side namespace = `flux-system`** for the SA + token Secret. Mirrors hub layout — architectural intent reads cleanly: "hub `flux-system` talks to `flux-reconciler` in `flux-system` on the spoke". `kube-system` rejected (mixes karyon identity with K8s built-ins). Dedicated `karyon-flux-reconciler` namespace rejected (verbose; one-namespace-per-purpose overkill at this scope).
- **D-06:** **`flux-reconciler` ServiceAccount** on each spoke. Specific to the role; matches the success-criterion text in 03-CONTEXT.md. `flux` (generic) rejected — collides if spokes ever grow a full Flux install. `kustomize-controller` rejected — misleading; this is a standalone SA on the spoke, not the hub controller's own SA.
- **D-07:** **`flux-reconciler-token` Secret** of type `kubernetes.io/service-account-token`, annotated `kubernetes.io/service-account.name: flux-reconciler`. Standard `<sa>-token` convention; reads cleanly in `kubectl -n flux-system get secret`. Kubernetes auto-populates `data.token` and `data.ca.crt` once the controller observes the SA + annotation pairing. Indefinite-lifetime token (PROJECT.md Phase-4 key decision: NOT `kubectl create token`).
- **D-08:** **`flux-reconciler-cluster-admin` ClusterRoleBinding** binding the SA to the built-in `cluster-admin` ClusterRole. Reads as "flux-reconciler bound to cluster-admin" in `kubectl get clusterrolebinding`. Rejected: `flux-reconciler` (cleaner but doesn't express the role); `karyon-flux-reconciler-binding` (verbose, prefix only valuable if multi-tenant).

### Kubeconfig Generation

- **D-09:** **Kubeconfig assembled via heredoc with bash substitution.** ~25-line YAML, single `cat <<EOF` block substituting `$CA_DATA`, `$TOKEN`, `$SERVER`. Most explicit; smaller on-disk during script; grep-able; tokens are base64-url alphanumeric so no shell-escape risk. `kubectl config set-cluster/credentials/context` against a temp KUBECONFIG rejected (more moving parts; verbose output). yq-template rejected (overkill for a 25-line one-shot artifact).
- **D-10:** **CA-data AND bearer token both extracted from the spoke's `flux-reconciler-token` Secret.** Single source of truth: `kubectl --context k3d-<spoke> -n flux-system get secret flux-reconciler-token -o jsonpath='{.data.ca\.crt}'` for CA, `'{.data.token}'` for token. Kubernetes' SA-token controller populates both fields when the Secret type + annotation are correct. CA-from-`kubectl config view` rejected (mixes sources; can drift if k3d ever rewrites local kubeconfig). CA-from-`openssl s_client` rejected (pulls SERVING leaf cert, not the CA — architecturally wrong).
- **D-11:** **Bounded retry loop for Secret data population** (10 attempts × 1s = 10s cap). Mirrors Phase 2 D-13 SAN-verify pattern. Pseudo-code:
  ```bash
  for i in $(seq 1 10); do
    token="$(kubectl --context k3d-${spoke} -n flux-system get secret flux-reconciler-token -o jsonpath='{.data.token}' 2>/dev/null || true)"
    [[ -n "$token" ]] && break
    sleep 1
  done
  [[ -n "$token" ]] || fail "flux-reconciler-token never populated on ${spoke} after 10s — kubectl describe secret/flux-reconciler-token -n flux-system to inspect"
  ```
  Same pattern for `ca.crt`. `kubectl wait --for=jsonpath` rejected (opaque failure surface). Single-shot rejected (will race the controller in fresh-cluster scenarios).
- **D-12:** **Trust the literal `https://k3d-<spoke>-server-0:6443`.** ROADMAP REQ-SPOKE-03 locks the URL. No DNS or TLS pre-probe before assembly — verification phase (D-13/D-14) tests reachability and the auth roundtrip. Don't conflate kubeconfig assembly with reachability — cleaner failure attribution and tighter loop.

### Verification (HIGH-risk P18 mitigation)

- **D-13:** **Belt-and-suspenders in-script verification.** Before `exit 0` the script asserts, per spoke:
  1. **Presence:** `kubectl --context k3d-hub-flux -n flux-system get secret <spoke>-kubeconfig -o jsonpath='{.data.value\.yaml}'` returns non-empty.
  2. **Decode:** the base64-decoded `value.yaml` parses as YAML (e.g., via `yq eval` or by extracting `.clusters[0].cluster.server` and asserting equality to the expected URL).
  3. **Auth roundtrip (ROADMAP success #3):** from inside the hub's `kustomize-controller` Deployment pod, run `kubectl --kubeconfig <piped-from-Secret> auth can-i '*' '*' --all-namespaces` and assert exit 0 + output `yes`. Proves DNS resolves, TLS validates, CA-data is correct, and the token authenticates with cluster-admin permissions on the targeted apiserver.
  4. **Node-name negative-proof (P18 trip-wire):** same pod, `kubectl --kubeconfig <piped> get nodes -o jsonpath='{.items[*].metadata.name}'` returns a string CONTAINING `k3d-<spoke>-server-0` and NOT containing `k3d-hub-flux-server-0`. Catches a misrouted Secret at the credential layer — BEFORE Flux ever tries to reconcile. Cost: ~10s per spoke total. Mirrors Phase 2 D-13 defensive intent.
- **D-14:** **In-pod probes exec into `kustomize-controller`** in `flux-system` on `k3d-hub-flux`. Authoritative: this IS the identity Flux uses for reconciliation. Probe failures here mirror real reconciliation failures. Pod is always Ready post-Phase-3 (`kubectl wait --for=condition=Available deploy/kustomize-controller` is a free precondition). `source-controller` rejected (wrong layer — it fetches Git, not auth-to-spokes). Fresh debug pod rejected (extra moving parts; identity diverges from reconciliation identity).
- **D-15:** **Negative-proof done at the credential layer (node-name check), NOT at `.status.inventory`.** ROADMAP success #5's `.status.inventory` check requires the spoke Kustomization to have reconciled successfully — which requires the user to push first. Node-name check via the kubeconfig works immediately, deterministic per cluster (k3d sets the node name to `k3d-<cluster>-server-0`), catches the same P18 fault mode at a more fundamental layer. Block-on-push rejected (awful UX; requires interactive wait). Imperative apply of seed manifests rejected (defeats the GitOps pattern).
- **D-16:** **Canonical `.status.inventory` negative-proof lives in `tests/bats/register-spokes-02-live.bats`**, gated by `require_live_destructive()` per Phase 2/3 pattern. The bats test assumes git push has happened (the developer commits, pushes, then `KARYON_LIVE_TESTS=1 KARYON_LIVE_TESTS_DESTRUCTIVE=1 bats tests/bats/register-spokes-02-live.bats`). Asserts `kubectl --context k3d-hub-flux -n flux-system get kustomization spoke-ml -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'` == `True`, AND `flux get kustomization spoke-ml -n flux-system` `.status.inventory` contains the seed ConfigMap's UID-suffixed entry (e.g., `karyon-spoke-ml_karyon-spoke-id__ConfigMap`). Script's responsibility ends at "kubeconfig auths into the right cluster"; reconciliation is GitOps and lives on its own clock. In-script polling rejected; both-script-and-bats rejected (doubles surface).

### Claude's Discretion

These were not explicitly discussed; planner/researcher decides:

- **Order of operations within `register_spoke` helper** — recommended: (1) RBAC: SA + CRB + token Secret on spoke; (2) wait for Secret data; (3) extract CA + token; (4) build kubeconfig; (5) imperative `kubectl apply -f -` of `<spoke>-kubeconfig` Secret on hub; (6) write `clusters/hub-flux/spokes/<spoke>.yaml` Kustomization YAML to local checkout; (7) write `clusters/<spoke>/` seed tree; (8) verify (D-13/D-14). Sections (6) and (7) can swap; everything else is order-dependent.
- **Where the patch to `clusters/hub-flux/flux-system/kustomization.yaml` happens** — once across both spokes (idempotent, sentinel-guarded `# KARYON SPOKES MOUNT` or similar) outside the per-spoke helper, OR inside the helper guarded by per-spoke sentinel. Recommendation: once outside; the patch is symmetric across spokes (`- ../spokes`).
- **Sentinel for the kustomization.yaml patch** — pick a literal that's grep-friendly and unique (e.g., `# KARYON SPOKES MOUNT` or `# Phase 4 spokes wire-up`). Bats static test pins the literal so future drift is caught.
- **Idempotency check granularity for the `<spoke>-kubeconfig` Secret on the hub** — three-part AND like Phase 3 D-07: (a) Secret exists, (b) `data.value\.yaml` decodes to a valid kubeconfig with the expected `server:` and (c) auth roundtrip succeeds. On any of those failing, fall through to full re-creation. Token rotation isn't a v1 concern; if the SA Secret on the spoke is the same UID as last run, the kubeconfig contents will match exactly, so the re-create is a no-op apply.
- **Token-Secret data-population wait timeout exact value** — D-11 recommends 10s; researcher confirms typical k3s SA-token-controller latency. If 10s is tight, bump to 20s with the same retry shape.
- **`kubectl apply -f -` vs `kubectl create secret generic --dry-run=client -o yaml | kubectl apply -f -`** for the hub Secret — both work; the heredoc-Secret-YAML route is cleaner because the script already has the YAML in hand. Pick whichever has clearer error messages on conflict.
- **In-pod kubectl invocation mechanics** — `kubectl exec deploy/kustomize-controller -n flux-system -- sh -c '<cmd>'` vs `kubectl exec ... -- kubectl ...`. The kustomize-controller image SHOULD ship kubectl in 2026 (researcher confirms); if not, fall back to a one-shot `busybox`-style debug pod (deviates from D-14 — flag if research surfaces this).
- **CA / token export mechanics inside the in-pod probe** — kubeconfig is piped in via stdin (`<<EOF`), or written to `/tmp/kubeconfig` inside the pod, or mounted as a Secret volume. Stdin is least invasive; Secret volume is the cleanest but requires a Pod spec edit. Pick stdin.
- **`docs/flux-hub-spoke.md` Phase 4 section depth** — single paragraph + the 6 SPOKE REQ-IDs + the P18 callout, OR a longer "how reconciliation works hub→spoke" walkthrough with a diagram-ready table of `<spoke>-kubeconfig` → Flux Kustomization → spoke namespaces. Recommendation: medium depth — REQ-IDs + the value.yaml key contract + P18 pitfall as a callout box + node-name negative-proof rationale. ADR-004 (Phase 6) carries the topology rationale; this doc carries the operational contract.
- **Diff/conflict handling on the `clusters/hub-flux/flux-system/kustomization.yaml` patch** — if a re-bootstrap rewrites the file (it shouldn't per Phase 3 Rule 2, but be defensive), the script should re-apply the patch idempotently (`grep -qF "# KARYON SPOKES MOUNT"` → skip; else `sed`/`yq` insert). Bats test pins the sentinel to detect drift.
- **What to do if `clusters/<spoke>/` already has Phase-5 content during Phase 4 rerun** — D-03's seed manifests are additive (new files, not overwriting Phase 5's), but if a future rerun finds existing files at `clusters/spoke-ml/namespace.yaml` (because Phase 5 author moved files), the script should `info "already done, skipping: clusters/spoke-ml seed (file exists)"`. Idempotent-by-presence; don't overwrite.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project-level specs

- `.planning/PROJECT.md` — Core value; Key Decisions table (Phase 4: legacy Secret-backed SA tokens NOT `kubectl create token` — indefinite lifetime correct for lab); Out of Scope (no real secret management; v2 covers SOPS/age); Constraints (hub-only Flux topology — ADR-004; public repo + `.env` posture); Context (3-part k3d GPU contract irrelevant here, but `k8s-net` Docker-embedded-DNS reachability for `k3d-<spoke>-server-0` IS load-bearing).
- `.planning/REQUIREMENTS.md` §Spoke Registration (SPOKE-01..06 — the 6 REQ-IDs in this phase), §Documentation (DOCS-03 referenced — `docs/flux-hub-spoke.md` extension), §Repo Hygiene (REPO-01..04 referenced for token posture; Phase 6 owns gitleaks).
- `.planning/ROADMAP.md` §Phase 4 — goal (the dual `kubectl ... get secret` proof clause), 5 success criteria (esp. #3 in-hub-pod probe and #5 negative-proof of `.status.inventory` containing a spoke-only resource), HIGH-risk notes (DNS + TLS + CA + RBAC + Secret-key all converge; Secret-key mismatch is silent-misroute P18), dependency on Phase 3, parallelization with Phase 6 ADR-004 + Phase-4 hub-spoke section in `docs/flux-hub-spoke.md`.
- `.planning/STATE.md` — Phase 4 blocker note ("single highest-risk phase ... schedule a dedicated research pass during planning if initial planning surfaces ambiguity") informs research scope.

### Prior-phase context (Phases 1, 2, 3 — all completed)

- `.planning/phases/01-host-foundation/01-CONTEXT.md` — Phase 1 decisions still active: D-05 (guarded-sections idempotency idiom — Phase 4 D-13 verification gate follows this verbatim per spoke), D-12 (`.gitignore` covers `.env*`; Phase 4 must not commit Secret-yielding kubeconfig material).
- `.planning/phases/01-host-foundation/01-PATTERNS.md` — script style: `set -euo pipefail`, ANSI-color gate via `[[ -t 1 ]]`, `section`/`pass`/`warn`/`fail`/`info`/`have` vocabulary, `# INTENTIONALLY` blocking-comment idiom (Phase 2 D-14 used this for `docker prune` defense; Phase 4 may reuse for "NEVER commit kubeconfig Secret YAML to git" defense).
- `.planning/phases/02-cluster-layer/02-CONTEXT.md` — Phase 2 decisions: D-07 (helper function shape — `create_cluster name port extra_args`; Phase 4 D-01 mirrors with `register_spoke name`), D-08 (serial creation, fail-fast, no auto-cleanup), D-09 (skip-if-exists + verify-config idempotency model), D-13 (belt-and-suspenders SAN verification with bounded retry — Phase 4 D-11 reuses the retry shape; Phase 4 D-13 reuses the defensive-verification posture verbatim).
- `.planning/phases/03-flux-hub-bootstrap/03-CONTEXT.md` — Phase 3 decisions: D-05 (preflight delegation as Step 1), D-06 (kubectl context gate; read-only assertion, no auto-switch), D-07 (3-part AND idempotency + skip-if-healthy/fall-through pattern; Phase 4 D-13 verification gate inherits the 3-part-AND shape), D-09 (full verification before exit 0), D-10 (`kubectl wait --for=condition=Available deploy --all --timeout=120s` precedent), D-11 (`set -euo pipefail`; NEVER `set -x`; never echo tokens; Phase 4 inherits VERBATIM — bearer tokens replace GITHUB_TOKEN), D-12 (external bats live/destructive test pattern; Phase 4 register-spokes-02-live.bats follows the exact pattern with `require_live_destructive()` double-gate), D-13 (`# FLUX PATCH SURFACE` sentinel-guarded marker; Phase 4 D-02 reuses the same sentinel-guard pattern for its `# KARYON SPOKES MOUNT` patch to flux-system/kustomization.yaml), D-16 (idempotency-skip messaging — Phase 4 reuses `info "already done, skipping: <what>"` literal).
- `.planning/phases/03-flux-hub-bootstrap/03-VERIFICATION.md` — Phase 3 verification artifact structure; Phase 4 verification (forthcoming) follows the same shape.

### Existing code to reuse / extend

- `scripts/lib/preflight-lib.sh` — shared helper library. `scripts/register-spokes-for-flux.sh` **must** `source` it; duplicate helpers are forbidden.
- `scripts/preflight.sh` — Phase 4 delegates to it as first script step (D-05 from Phase 3 verbatim).
- `scripts/bootstrap-flux.sh` — closest style/structure reference for Phase 4's new script: section headers, kubectl-context gate (D-06 from Phase 3), the `load_env_key`-style data parsing (Phase 4 doesn't read `.env`, but the `set -a; source .env; set +a` ban applies — bearer tokens NEVER touch shell environment except as kubectl `--token` parameters which never echo). The post-bootstrap verification structure (Phase 3 D-09 three-gate) is the template for Phase 4's per-spoke 4-gate verification (D-13).
- `scripts/create-clusters.sh` — direct shape reference for the `register_spoke <name>` helper (mirrors `create_cluster <name> <port> [extra_args]`); the Section/pass/info/fail vocabulary; bounded-retry loop (Phase 2 D-13 SAN verify) — Phase 4 D-11 reuses the retry shape verbatim.
- `clusters/hub-flux/flux-system/kustomization.yaml` — bootstrap-managed but explicitly `Rule 2 patch surface` per Phase 3 D-13 / `docs/flux-hub-spoke.md`. Phase 4 patches it idempotently (sentinel-guarded) to add `- ../spokes`.
- `Taskfile.yml` — Phase 3 stub. Phase 4 appends a `register-spokes` task entry (single-line `bash scripts/register-spokes-for-flux.sh`); full REPO-05 reorganization stays Phase 6.
- `docs/flux-hub-spoke.md` — Phase 3 carries an `<!-- Phase 4: hub-spoke reconciliation -->` stub at EOF; Phase 4 fills it in.
- `tests/bats/test_helper.bash` — `require_live()` and `require_live_destructive()` helpers, REPO_ROOT resolution, scripts-dir resolution. Phase 4 bats suites use both gates; no extension needed.
- `.tool-versions` — `kubectl 1.35.0`, `flux2 2.8.6`, `k3d 5.8.3`, `jq 1.8.1`, `yq 4.53.2`. Phase 4 scripts assume these via asdf shim; preflight (PRE-05) validates the pins.

### External references (researcher must fetch current 2026 docs at planning time — no URLs assumed)

- **Kubernetes legacy SA-token Secret behavior (`kubernetes.io/service-account-token` type)** — k8s 1.24+ deprecation note (auto-creation removed; explicit Secret with annotation still supported with indefinite lifetime); k8s 1.35 (the pinned line) current behavior for `data.token` and `data.ca.crt` population latency; whether the controller polls or watches; failure modes if the SA doesn't exist yet (the Secret stays empty). Researcher MUST confirm the exact annotation key — `kubernetes.io/service-account.name` (singular).
- **Flux `kustomize-controller` v1 spec** — Kustomization CRD, `spec.kubeConfig.secretRef` shape (specifically: must `secretRef.key` be `value.yaml` literally, or any key as long as the Secret has exactly one key? per ROADMAP it's `value.yaml`); `.status.inventory` field structure (UID-suffixed `<ns>_<name>__<kind>` entries) for the bats test's negative-proof regex; what the `flux get kustomization` `Ready=True` condition exactly proves; how the controller resolves `spec.kubeConfig.secretRef` lookups (lookup is in the Kustomization's namespace — `flux-system` on hub).
- **`kubectl exec` mechanics** for piping a kubeconfig via stdin into a kubectl invocation inside another pod (`kubectl exec ... -i -- sh -c 'KUBECONFIG=/dev/stdin kubectl ...'` patterns); whether k8s 1.35's `kubectl-1.35` binary inside the kustomize-controller image supports `--kubeconfig=/dev/stdin` directly; image-shipped binaries on the kustomize-controller pod (`fluxcd/kustomize-controller:v1.x` 2026 release).
- **`flux bootstrap` patch survival** — confirms Phase 3 Rule 2 holds for a `- ../spokes` resource entry under `resources:` (not just for `patches:`/`configMapGenerator:`/`images:`); how kustomize-build resolves `../spokes` reference from `clusters/hub-flux/flux-system/` to `clusters/hub-flux/spokes/` (load-restrictor semantics).
- **k3d v5.8.3 Docker-embedded-DNS** — confirms `k3d-<name>-server-0` is the registered container alias on `k8s-net` for hub-pod-to-spoke-apiserver resolution; how DNS is published when `--network k8s-net` is used; SAN coverage on the apiserver cert (Phase 2 D-13 confirmed `k3d-<name>-server-0` is in the cert SAN list — Phase 4 inherits this).
- **`yq eval` for parsing the kubeconfig** — extracting `.clusters[0].cluster.server` for the assembly verification (D-13 step 2); whether `yq 4.53.2` (mikefarah Go yq) handles base64-decoded YAML cleanly in a pipe.
- **`kubectl auth can-i '*' '*' --all-namespaces`** — exit codes when authorized vs not vs unreachable; output format (`yes` / `no`) stability for the bats grep.
- **`kubectl get nodes -o jsonpath`** for the negative-proof — confirms k3d sets `metadata.name` to `k3d-<cluster>-server-0` on the single server node; whether `--no-headers` matters; what's printed if the apiserver is unreachable (relevant for the failure path in D-13 step 4).

### ADR pointers (authored in Phase 6 — consistency required)

- **ADR-004 (hub-only Flux control plane)** — Phase 4 IS the practical instantiation of ADR-004's topology decision. Phase 4 decisions must not contradict ADR-004's "hub reconciles to spokes via `spec.kubeConfig` + remote kubeconfig Secrets, no Flux on spokes" framing. ADR content authored in Phase 6 per ROADMAP parallelization; Phase 4 must not block on it.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- `scripts/lib/preflight-lib.sh` — full helper library inherited from Phase 1 (ANSI-color gate, `section`/`pass`/`warn`/`fail`/`info`/`have` vocabulary, counters). `scripts/register-spokes-for-flux.sh` sources it and uses these helpers verbatim.
- `scripts/preflight.sh` — Phase 1 preflight; Phase 4 delegates to it as first script step (D-05 from Phase 3 verbatim). Already verifies `.env` keys, asdf shim precedence, `kubectl 1.35.0` + `flux 2.8.6` + `jq 1.8.1` + `yq 4.53.2` presence, Docker runtime, host floor. Phase 4 doesn't re-implement any of those.
- `scripts/bootstrap-flux.sh` — Phase 3 reference for: kubectl-context gate (D-06), 3-part-AND idempotency check pattern (D-07), `set -euo pipefail` discipline (D-11 token safety; bearer tokens replace GITHUB_TOKEN), section structure, post-script verification gate, sentinel-guarded patch idempotency (D-13 `# FLUX PATCH SURFACE`).
- `scripts/create-clusters.sh` — Phase 2 reference for the `register_spoke <name>` helper shape (mirrors `create_cluster <name> <port> [extra_args]`); bounded-retry loop (Phase 2 D-13 SAN verify; Phase 4 D-11 reuses for Secret-data wait).
- `clusters/hub-flux/flux-system/kustomization.yaml` — Phase 3 patch surface (D-13). Currently has the FLUX PATCH SURFACE comment block + `resources: [gotk-components.yaml, gotk-sync.yaml]`. Phase 4 patches `resources:` to add `- ../spokes` (sentinel-guarded `# KARYON SPOKES MOUNT`).
- `Taskfile.yml` — Phase 3 stub. Phase 4 appends a `register-spokes` task entry (single line); full REPO-05 reorganization is Phase 6.
- `docs/flux-hub-spoke.md` — Phase 3 doc with `<!-- Phase 4: hub-spoke reconciliation -->` stub at EOF; Phase 4 fills it in.
- `tests/bats/test_helper.bash` — `require_live()` and `require_live_destructive()` gates; REPO_ROOT + scripts-dir resolution. Phase 4 reuses without extension.

### Established Patterns

- **`#!/usr/bin/env bash` + `set -euo pipefail`** — imperative mutating scripts (Phase 1, 2, 3). Phase 4 follows this; specifically NOT `set -x` (D-11 token-safety; bearer tokens for Phase 4 == GITHUB_TOKEN for Phase 3).
- **ANSI colors gated on `[[ -t 1 ]]`** — via preflight-lib.sh.
- **Guarded-sections idiom** — every logical step checks state first and either logs `info "already done, skipping: <what>"` or proceeds with `pass "<doing>: <what>"`.
- **Blocker message includes remediation command** — every `fail` ends with `Fix: <exact next command>`.
- **Bounded retry loop pattern** — Phase 2 D-13 SAN verify (10 × 3s); Phase 4 reuses for Secret-data wait (10 × 1s — controller is local, not network) and for the in-pod auth roundtrip if kustomize-controller pod is restarting.
- **Bats live/destructive double-gate** — `require_live_destructive()` from `tests/bats/test_helper.bash`. Phase 4 register-spokes-02-live.bats inherits the pattern verbatim from Phase 3 bootstrap-flux-01-idempotent.bats.
- **Sentinel-guarded idempotent patch** — Phase 3 D-13 (`# FLUX PATCH SURFACE`); Phase 4 D-02 reuses with a new sentinel literal (`# KARYON SPOKES MOUNT` recommended).

### Integration Points

- **Upstream (required for Phase 4 to run):**
  - Phase 2: `hub-flux`, `spoke-ml`, `spoke-apps` clusters all Ready on `k8s-net`; each apiserver cert includes `k3d-<name>-server-0` SAN (Phase 2 D-13 verified).
  - Phase 3: `flux-system` namespace exists on `hub-flux` with all 4 controllers Ready; root `flux-system` Kustomization is Ready=True; `clusters/hub-flux/flux-system/kustomization.yaml` exists with FLUX PATCH SURFACE marker (Phase 3 D-13).
  - kubectl contexts `k3d-spoke-ml` and `k3d-spoke-apps` are exported (k3d defaults; no special handling).
  - `scripts/preflight.sh` exits 0.

- **Downstream (Phase 5 depends on Phase 4 landing):**
  - `<spoke>-kubeconfig` Secrets exist on `hub-flux/flux-system` and authenticate to the correct spoke (Phase 4 D-13 verified).
  - `clusters/hub-flux/spokes/{spoke-ml,spoke-apps}.yaml` Flux Kustomizations exist on origin/main after user push.
  - `clusters/spoke-ml/`, `clusters/spoke-apps/` trees exist with seed manifests on origin/main.
  - Phase 5 HEALTH-03 verifies "every spoke Kustomization Ready=True" — that's the canonical end-to-end proof; Phase 4's bats live test (D-16) carries the same proof for Phase 4's CI/manual-verification artifact.
  - Phase 5 DEP-01/02 commits podinfo (to `clusters/spoke-apps/apps/`) and gpu-smoke-test (to `clusters/spoke-ml/apps/`) ALONGSIDE Phase 4's seed manifests — Phase 4's Namespace + ConfigMap stay; Phase 5 adds.
  - `task rebuild` (Phase 5 DESTROY-05/06) calls `task register-spokes` as the fourth step in the chain; idempotency is load-bearing for the < 20 min SLO.

- **Downstream (Phase 6 parallelizable):**
  - `docs/adr/0004-hub-only-flux-control-plane.md` — Phase 6 captures the topology rationale; Phase 4 implements it; landing during Phase 4 is ROADMAP-sanctioned but not required.

- **External side effects on Phase 4 execution:**
  - `kubectl --context k3d-spoke-ml apply` creates SA, CRB, token Secret on spoke-ml.
  - `kubectl --context k3d-spoke-apps apply` creates same on spoke-apps.
  - `kubectl --context k3d-hub-flux -n flux-system apply -f -` creates `<spoke>-kubeconfig` Secrets on hub.
  - Local files written: `clusters/hub-flux/spokes/{spoke-ml,spoke-apps,kustomization}.yaml`, `clusters/hub-flux/flux-system/kustomization.yaml` patched (sentinel-guarded), `clusters/spoke-ml/{kustomization,namespace,configmap}.yaml`, `clusters/spoke-apps/{kustomization,namespace,configmap}.yaml`, `docs/flux-hub-spoke.md` Phase 4 section, `Taskfile.yml` register-spokes entry.
  - NO git mutations (D-04). NO secrets in any committed file.

</code_context>

<specifics>
## Specific Ideas

- `scripts/register-spokes-for-flux.sh` **top-of-file comment** cross-references the locked decisions:
  ```bash
  # scripts/register-spokes-for-flux.sh
  #
  # Creates per-spoke RBAC (SA + cluster-admin CRB + legacy SA-token Secret),
  # builds a kubeconfig from each spoke's SA-token Secret, and lands it on
  # k3d-hub-flux as flux-system/<spoke>-kubeconfig (key: value.yaml — explicit,
  # REQ-SPOKE-04 / D-15 silent-misroute trip-wire).
  #
  # Wires the hub-side Flux Kustomizations under clusters/hub-flux/spokes/ and
  # patches the FLUX PATCH SURFACE (clusters/hub-flux/flux-system/kustomization.yaml,
  # Phase 3 D-13) to add `- ../spokes`.
  #
  # Requirements satisfied: SPOKE-01..06
  # Decisions honored:      D-01..D-16
  #
  # D-11 token-safety: set -euo pipefail INTENTIONALLY omits -x (no bearer-token
  # trace on stdout/stderr). Bearer tokens are NEVER echo/printf/pass/info/warn/fail/tee'd.
  # Bearer tokens NEVER land in any committed file. The hub Secret is applied
  # imperatively via `kubectl apply -f -` from a heredoc; it is not git-tracked.
  ```
- Section headers (matching Phase 1/2/3 vocabulary):
  - `section "Preflight gate"` — one-line pass or bail via `scripts/preflight.sh`.
  - `section "Context check"` — kubectl context gate (Phase 3 D-06 verbatim, expects `k3d-hub-flux`).
  - `section "spoke-ml"` (then per-spoke flow inside `register_spoke`).
  - `section "spoke-apps"` (per-spoke flow).
  - `section "Hub-side Kustomizations"` — write `clusters/hub-flux/spokes/{spoke-ml,spoke-apps,kustomization}.yaml` + patch `flux-system/kustomization.yaml` (sentinel-guarded).
  - `section "Spoke seed manifests"` — write `clusters/{spoke-ml,spoke-apps}/{kustomization,namespace,configmap}.yaml`.
  - `section "In-script verification"` — D-13's 4 gates per spoke (presence, decode, auth roundtrip, node-name negative-proof).
  - `section "Summary"` — pass/warn/fail counts; `info` line with the exact `git add ... && git commit -m '...' && git push` reminder (D-04).
- Per-spoke section inside `register_spoke <name>`:
  - **Subsection 1: spoke-side RBAC** — apply SA + CRB + token Secret via heredoc-piped `kubectl apply -f -`.
  - **Subsection 2: token-Secret data wait** — bounded retry (D-11) for `data.token` AND `data.ca.crt` populated.
  - **Subsection 3: kubeconfig assembly** — heredoc with `$CA_DATA`, `$TOKEN`, `$SERVER`. Local variable `KUBECONFIG_YAML`.
  - **Subsection 4: hub Secret apply** — `printf "%s" "$KUBECONFIG_YAML" | kubectl --context k3d-hub-flux -n flux-system create secret generic <spoke>-kubeconfig --from-file=value.yaml=/dev/stdin --dry-run=client -o yaml | kubectl apply -f -` (or equivalent — researcher confirms cleanest form).
  - **Subsection 5: write hub-side Kustomization YAML** — `clusters/hub-flux/spokes/<spoke>.yaml`.
  - **Subsection 6: write spoke seed tree** — `clusters/<spoke>/{kustomization,namespace,configmap}.yaml`.
- Every `fail` message tells the user exactly what to run to fix it (matches Phase 1/2/3 vocabulary):
  - `cluster k3d-${spoke} not reachable → kubectl --context k3d-${spoke} cluster-info; check that scripts/create-clusters.sh succeeded`
  - `flux-reconciler-token never populated on ${spoke} after 10s → kubectl --context k3d-${spoke} -n flux-system describe secret/flux-reconciler-token (controller race; rerun the script after 30s)`
  - `<spoke>-kubeconfig Secret missing on hub → script bug (apply step failed silently); rerun: bash scripts/register-spokes-for-flux.sh`
  - `auth roundtrip failed for ${spoke} → kubectl --context k3d-hub-flux -n flux-system exec deploy/kustomize-controller -- sh -c 'KUBECONFIG=<...> kubectl auth can-i list namespaces' (manually inspect)`
  - `node-name negative-proof FAILED: kubeconfig for ${spoke} routed to k3d-hub-flux-server-0 — P18 SILENT MISROUTE → check the Secret's value.yaml key spelling AND the server URL in the kubeconfig; do NOT push current state`
- **Hub-side Flux Kustomization YAML template** (researcher confirms exact apiVersion + spec.interval default):
  ```yaml
  apiVersion: kustomize.toolkit.fluxcd.io/v1
  kind: Kustomization
  metadata:
    name: spoke-ml
    namespace: flux-system
  spec:
    interval: 5m
    path: ./clusters/spoke-ml
    prune: true
    sourceRef:
      kind: GitRepository
      name: flux-system
    kubeConfig:
      secretRef:
        name: spoke-ml-kubeconfig
        key: value.yaml          # explicit per REQ-SPOKE-04 / P18 trip-wire
    targetNamespace: ""           # empty — let manifests declare their own ns
  ```
- **Spoke seed `clusters/spoke-ml/kustomization.yaml`** (Phase 5 adds to it):
  ```yaml
  apiVersion: kustomize.config.k8s.io/v1beta1
  kind: Kustomization
  resources:
    - namespace.yaml
    - configmap.yaml
  ```
  `namespace.yaml` creates `karyon-spoke-ml`; `configmap.yaml` creates `karyon-spoke-id` in `karyon-spoke-ml` ns with `data.spoke=spoke-ml`. Mirror for `spoke-apps`.
- **`docs/flux-hub-spoke.md` Phase 4 section** (replaces the Phase 3 stub):
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
     `clusters/hub-flux/flux-system/kustomization.yaml`'s `resources:`). Has
     `spec.kubeConfig.secretRef.key: value.yaml` set EXPLICITLY (the silent-misroute
     trip-wire).

  ### Silent-misroute pitfall (P18)

  If `spec.kubeConfig.secretRef.key` is wrong (typo, missing, or omitted to
  rely on the default), the controller falls back to its in-cluster SA and
  reconciles into the WRONG cluster (the hub) while reporting `Ready=True`.
  Two defenses:

  - The hub-side Kustomization YAML sets the key explicitly to `value.yaml`.
    Do NOT remove it.
  - `scripts/register-spokes-for-flux.sh` runs an in-pod node-name probe per
    spoke after creating the Secret: `kubectl --kubeconfig <Secret-content>
    get nodes` MUST return `k3d-<spoke>-server-0` (NOT `k3d-hub-flux-server-0`).
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
- Bats static suite (`register-spokes-01-static.bats`) pins the literals so future drift surfaces:
  - `flux-reconciler` (SA name)
  - `flux-reconciler-cluster-admin` (CRB name)
  - `flux-reconciler-token` (token Secret name)
  - `value.yaml` (key — appears 4+ times: hub Secret, Kustomization YAML template, doc)
  - `# KARYON SPOKES MOUNT` (sentinel)
  - `k3d-<spoke>-server-0` (node-name negative-proof literal)
  - `kubernetes.io/service-account.name: flux-reconciler` (annotation)
  - No auto-push: negative grep for `git push` in script body (excluding info-line content).

</specifics>

<deferred>
## Deferred Ideas

- **Token rotation / Secret renewal** — explicitly rejected for v1; legacy SA-token Secrets have indefinite lifetime per PROJECT.md Phase-4 key decision. Revisit in v2 when SOPS/age + a real secret-management story arrives (REQUIREMENTS.md SECRETS-01).
- **Namespace-scoped RBAC narrowing** — REQ-SPOKE-01 locks cluster-admin for v1. Revisit in v2 when multi-tenant or adversarial separation enters scope.
- **Per-namespace Flux Kustomizations on spokes (one Kustomization per app, not per spoke)** — Phase 4 lands one Flux Kustomization per spoke; Phase 5 may split podinfo / gpu-smoke-test into their own Kustomizations. Out of scope for Phase 4.
- **TokenRequest (`kubectl create token`)** — PROJECT.md Phase-4 key decision rejects in favor of legacy Secret-backed indefinite-lifetime tokens for the lab. Revisit in v2 when token-rotation policy enters scope.
- **CDI (Container Device Interface) for the spoke kubeconfig** — orthogonal; CDI is for device pass-through (Phase 2 owns), not auth.
- **Auto-commit + auto-push from the script** — rejected (Phase 4 D-04). Mirrors Phase 3 bootstrap-flux's "no automated git mutations" posture.
- **Imperative-apply of the hub-side spoke Kustomization YAMLs (kubectl apply during script run)** — rejected. Defeats GitOps; mixing imperative apply with reconciliation creates drift surface. Trust the user to commit + push; let the existing `flux-system` Kustomization reconcile.
- **Splitting Phase 4 into "register-spokes" and "verify-spokes" two-step scripts** — rejected (D-15: in-script verification covers the credential layer, bats covers the reconciliation layer post-push). Single script keeps the loop tight.
- **In-script `.status.inventory` polling with timeout** — rejected (D-15/D-16). User would be blocked waiting for their own git push; awful UX.
- **Spawn a fresh debug pod for the in-pod probe** — rejected (D-14). kustomize-controller is the authoritative identity.
- **`kubectl wait --for=jsonpath` for the SA-Secret data-population wait** — rejected (D-11). Bounded retry has clearer failure surface.
- **`openssl s_client` for CA extraction** — rejected (D-10). Pulls SERVING leaf cert, not CA — architecturally wrong.
- **`kubectl config view --raw --minify --flatten` for CA extraction** — rejected (D-10). Mixes sources; the SA-token Secret is the canonical source.
- **`yq`-based template for kubeconfig assembly** — rejected (D-09). Heredoc with bash substitution is sufficient for a 25-line one-shot artifact.
- **DNS/TLS pre-probe before kubeconfig assembly** — rejected (D-12). Verification phase covers reachability; pre-probe blurs the line.
- **Source-controller pod for in-pod probes** — rejected (D-14). Wrong layer.
- **Loop-over-array (`for spoke in spoke-ml spoke-apps`) in the script body** — rejected (D-01). Worse error context than named helper calls.
- **Inline duplication for both spokes** — rejected (D-01). Copy-paste of ~60 lines.
- **Separate top-level "spokes" Flux Kustomization on the hub** — rejected (D-02). Two top-level Kustomizations on hub; one-time imperative `kubectl apply` breaks GitOps purity.
- **Inline-flat resources in flux-system/kustomization.yaml** — rejected (D-02). Each new spoke = another flux-system patch; directory reference scales.
- **Empty `kustomization.yaml` (zero resources) under clusters/<spoke>/** — rejected (D-03). `.status.inventory` empty; ROADMAP success #5 negative-proof unsatisfiable.
- **Reference Phase 5 paths (`./apps`, `./infrastructure`) from Phase 4 seed** — rejected (D-03). Couples Phase 4 to Phase 5 manifests that don't exist yet; reconciliation fails until Phase 5 ships.
- **Phase 4 doc deliverable as a separate `docs/spoke-registration.md`** — folded into existing `docs/flux-hub-spoke.md` Phase 4 section per Phase 3 D-14 stub. Single source of truth for hub↔spoke operational contract.
- **gitleaks pre-commit hook install in Phase 4** — Phase 6 owns it (REPO-04 per ROADMAP parallelization). Phase 4 retains the warn-only advisory pattern from Phase 3 if useful, but the canonical install lives in Phase 6.

</deferred>

---

*Phase: 04-spoke-registration*
*Context gathered: 2026-04-27*
