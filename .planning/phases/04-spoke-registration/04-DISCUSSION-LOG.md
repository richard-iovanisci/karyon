# Phase 4: Spoke Registration - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in `04-CONTEXT.md` — this log preserves the alternatives considered.

**Date:** 2026-04-27
**Phase:** 04-spoke-registration
**Areas discussed:** Orchestration & seed manifests, Spoke RBAC layout, Kubeconfig generation mechanics, In-script verification depth

---

## Orchestration & seed manifests

### Q1: Script shape for `scripts/register-spokes-for-flux.sh`?

| Option | Description | Selected |
|--------|-------------|----------|
| Helper function + 2 calls | `register_spoke <name>` helper, called twice for spoke-ml and spoke-apps. Mirrors Phase 2 `create_cluster()` pattern verbatim. Failures show the spoke name in the section header. | ✓ |
| Loop over spoke array | `for spoke in spoke-ml spoke-apps; do ...; done`. Slightly tighter but worse error context (loop iteration vs named function call). | |
| Inline duplication for both spokes | Two copy-pasted blocks. Most readable per-spoke but duplicates ~60 lines of logic. Worst diff-cost on future tweaks. | |

**User's choice:** Helper function + 2 calls (Recommended)
**Notes:** Mirrors Phase 2 D-07 + Phase 3 D-12 pattern.

### Q2: How do hub-side Flux Kustomizations for spokes get reconciled?

| Option | Description | Selected |
|--------|-------------|----------|
| Patch flux-system kustomization.yaml + spokes/kustomization.yaml dir | Use Phase 3 D-13 patch surface: add `- ../spokes` to flux-system/kustomization.yaml resources. Seed `clusters/hub-flux/spokes/kustomization.yaml` listing spoke-ml.yaml + spoke-apps.yaml. Single top-level Flux Kustomization, idiomatic kustomize directory ref. Patch survives re-bootstrap per Phase 3 Rule 2. | ✓ |
| Inline as flat resources in flux-system/kustomization.yaml | `resources: [gotk-components.yaml, gotk-sync.yaml, ../spokes/spoke-ml.yaml, ../spokes/spoke-apps.yaml]`. No spokes/kustomization.yaml needed. Simpler but each new spoke = another flux-system patch. | |
| Separate top-level 'spokes' Flux Kustomization (one-time kubectl apply) | Apply a new Flux Kustomization 'spokes' on the hub pointing at `./clusters/hub-flux/spokes/`. Two top-level Kustomizations on the hub. Imperative apply once = breaks GitOps purity. | |

**User's choice:** Patch flux-system kustomization.yaml + spokes/kustomization.yaml dir (Recommended)
**Notes:** Reuses the Phase 3 D-13 patch surface that was advertised exactly for this kind of extension. Single top-level Flux Kustomization keeps the hub mental model simple.

### Q3: What seed lands at `clusters/spoke-ml/` and `clusters/spoke-apps/` for negative-proof?

| Option | Description | Selected |
|--------|-------------|----------|
| Per-spoke Namespace + ConfigMap with spoke name baked in | e.g., `clusters/spoke-ml/kustomization.yaml` -> Namespace `karyon-spoke-ml` + ConfigMap `karyon-spoke-id` (data.spoke=spoke-ml) in that ns. Distinct per spoke, makes ROADMAP success #5 negative-proof falsifiable, doesn't collide with Phase 5 workloads. | ✓ |
| Per-spoke ConfigMap only, in flux-system ns | Smallest possible. Lives in shared `flux-system` namespace on each spoke. Less obviously distinct since the same ns exists on hub — has to embed spoke name in ConfigMap data for negative-proof. | |
| Empty kustomization.yaml (zero resources) | `clusters/spoke-ml/kustomization.yaml` with `resources: []`. `.status.inventory` empty. Negative-proof FAILS Phase 4 — kicks the can to Phase 5. Rejected by ROADMAP success #5. | |
| Reference Phase 5 paths now (./apps, ./infrastructure) | Couples Phase 4 to Phase 5 manifests that don't exist yet. Reconciliation fails until Phase 5 commits its files. Bad sequencing. | |

**User's choice:** Per-spoke Namespace + ConfigMap with spoke name baked in (Recommended)
**Notes:** Falsifiable. Phase 5 adds workloads alongside (`./apps/`, `./infrastructure/`); seed stays as the negative-proof canary.

### Q4: Script commits/pushes new files, or write-local-only?

| Option | Description | Selected |
|--------|-------------|----------|
| Write-local-only; info user to commit + push | Mirrors Phase 3 bootstrap-flux.sh discipline (no automated git mutations). Script writes files, the patch surface marker, prints `info` with exact `git add ... && git commit ... && git push` line. User stays in control of git history. | ✓ |
| Auto-commit + auto-push to origin/main | Faster end-to-end. Requires clean working tree gate up front. Mutates remote without explicit user confirmation — breaks Phase 3 posture. | |
| Hybrid: auto-commit, no auto-push | Script commits locally; user reviews diff and pushes manually. Middle ground. But still mutates local history without explicit consent. | |

**User's choice:** Write-local-only; info user to commit + push (Recommended)
**Notes:** Architectural consistency with Phase 3 bootstrap-flux.sh. Cascades into D-15 (in-script negative-proof can't rely on `.status.inventory` since user hasn't pushed).

---

## Spoke RBAC layout

### Q1: Namespace for the SA + legacy-Secret token on each spoke?

| Option | Description | Selected |
|--------|-------------|----------|
| flux-system | Mirrors hub layout. Architectural intent reads cleanly: 'hub flux-system talks to flux-reconciler in flux-system on the spoke'. Phase 5 GPU smoke-test + podinfo will create their own namespaces; no collision. | ✓ |
| kube-system | Common pattern for system-level SAs. Mixes karyon's reconciler identity with K8s built-ins; harder to spot in `kubectl -n kube-system get sa`. | |
| karyon-flux-reconciler (dedicated ns) | Explicit isolation. One-namespace-per-purpose. Adds a namespace just for the SA; verbose. | |

**User's choice:** flux-system (Recommended)

### Q2: ServiceAccount name on each spoke?

| Option | Description | Selected |
|--------|-------------|----------|
| flux-reconciler | Matches the success criterion in Phase 3 03-CONTEXT.md. Specific to the role: the hub's kustomize-controller authenticates as this SA on the spoke. Reads correctly in kubectl error messages. | ✓ |
| flux | Generic. Could collide if spokes ever grow a full Flux install. Less informative in `kubectl who-am-i` style traces. | |
| kustomize-controller | Mirrors the hub controller name. Misleading — this is a standalone SA on the spoke, not the controller's own SA on the hub. | |

**User's choice:** flux-reconciler (Recommended)

### Q3: Name for the legacy SA-token Secret?

| Option | Description | Selected |
|--------|-------------|----------|
| flux-reconciler-token | Short, follows the standard `<sa>-token` convention. kubectl shows it next to the SA in `kubectl -n flux-system get secret`. Annotation `kubernetes.io/service-account.name=flux-reconciler` binds it back to the SA. | ✓ |
| flux-reconciler-sa-token | More verbose; `-sa-` redundant since it's already in the Secret type. | |
| flux-reconciler-static-token | Descriptive of the indefinite-lifetime intent (vs TokenRequest). Longer but documents the legacy choice in the name. | |

**User's choice:** flux-reconciler-token (Recommended)

### Q4: Name for the ClusterRoleBinding granting cluster-admin?

| Option | Description | Selected |
|--------|-------------|----------|
| flux-reconciler-cluster-admin | Reads as 'flux-reconciler bound to cluster-admin'. `kubectl get clusterrolebinding` makes the binding intent obvious. | ✓ |
| flux-reconciler | Matches SA name. Cleaner but doesn't say what role is bound. | |
| karyon-flux-reconciler-binding | Project-prefixed, verbose. Useful only if the spoke might ever host non-karyon CRBs. | |

**User's choice:** flux-reconciler-cluster-admin (Recommended)

---

## Kubeconfig generation mechanics

### Q1: How is the per-spoke kubeconfig YAML assembled?

| Option | Description | Selected |
|--------|-------------|----------|
| Heredoc with bash substitution | Hand-write a ~25-line kubeconfig YAML via `cat <<EOF`, substituting $CA_DATA, $TOKEN, $SERVER. Most explicit. Smaller on-disk footprint during script. grep-able. Token is base64-url alphanumeric so no shell-escape risk. | ✓ |
| kubectl config set-cluster/credentials/context against temp KUBECONFIG | `KUBECONFIG=$(mktemp) kubectl config set-cluster ... && set-credentials ... && set-context ... && use-context`. kubectl owns the schema. More verbose; survives kubeconfig schema bumps. More moving parts. | |
| yq-based template | Maintain a `kubeconfig.tmpl.yaml` under config/ with placeholders, render via yq. Overkill for 25 lines and a one-shot artifact. | |

**User's choice:** Heredoc with bash substitution (Recommended)

### Q2: Where do CA-data and the bearer token come from?

| Option | Description | Selected |
|--------|-------------|----------|
| Both from the SA-token Secret on each spoke | `kubectl --context k3d-<spoke> -n flux-system get secret flux-reconciler-token -o jsonpath='{.data.ca\.crt}'` AND `'{.data.token}'`. Single source of truth: the Kubernetes controller populates both fields on the SA Secret. CA-data is base64-encoded already (matches kubeconfig schema). Indefinite-lifetime token (PROJECT.md Phase-4 key decision). Bounded wait-loop needed in case the controller hasn't filled `data.token` yet. | ✓ |
| CA from `kubectl config view --raw --minify --flatten`, token from SA Secret | Two sources — CA from the local kubeconfig (which k3d wrote at cluster create), token from the SA Secret. Works but mixes sources. Local kubeconfig CA can drift if k3d ever rewrites it. | |
| CA from openssl s_client probe of apiserver, token from SA Secret | openssl pulls the SERVING leaf cert, not the CA. Would fail TLS validation if used as `certificate-authority-data`. Rejected as architecturally wrong. | |

**User's choice:** Both from the SA-token Secret on each spoke (Recommended)

### Q3: How does the script wait for the controller to populate token + ca.crt on the Secret?

| Option | Description | Selected |
|--------|-------------|----------|
| Bounded retry loop | `for i in $(seq 1 10); do kubectl get secret ...token -o jsonpath='{.data.token}'` returns non-empty; break; sleep 1; done. Mirrors Phase 2 D-13 SAN-verify pattern (10×3s = 30s cap; here 10×1s = 10s since controller is local). Fail loudly with remediation if exhausted. | ✓ |
| kubectl wait --for=jsonpath | kubectl 1.23+ supports `--for=jsonpath='{.data.token}'`. One line, idiomatic. But error surface is opaque if it fails (just times out). Less greppable failure reason than explicit loop. | |
| Single-shot assert (no retry) | Read once, fail if empty. Will likely race the controller in fresh-cluster scenarios. Rejected. | |

**User's choice:** Bounded retry loop (Recommended)

### Q4: Server URL handling — trust literal or pre-probe before stuffing into kubeconfig?

| Option | Description | Selected |
|--------|-------------|----------|
| Trust literal `https://k3d-<spoke>-server-0:6443` | ROADMAP locks the URL. Verification phase (Area 4) tests reachability and TLS via in-hub-pod nslookup + curl probe. Don't conflate kubeconfig assembly with reachability — cleaner failure attribution. | ✓ |
| DNS probe before assembly | `kubectl --context k3d-hub-flux exec` into kustomize-controller pod, `nslookup k3d-<spoke>-server-0`. Catches DNS issues early but blurs the line between assembly and verification. | |
| Full TLS probe before assembly | Assemble a candidate kubeconfig, run a `kubectl --kubeconfig <tmp> auth can-i list ns` round-trip from inside a hub pod. Heavyweight. Overlaps with Area 4. | |

**User's choice:** Trust literal `https://k3d-<spoke>-server-0:6443` (Recommended)

---

## In-script verification depth

### Q1: What does `scripts/register-spokes-for-flux.sh` verify before exit 0?

| Option | Description | Selected |
|--------|-------------|----------|
| Belt-and-suspenders: presence + decode + auth roundtrip + node-name negative-proof | (1) Hub Secret `<spoke>-kubeconfig` exists in flux-system with `value.yaml` key. (2) Decode + parse the kubeconfig YAML. (3) From inside the hub's kustomize-controller pod, exec `kubectl --kubeconfig <piped> auth can-i '*' '*' --all-namespaces` against each spoke. (4) Same pod: `kubectl get nodes -o jsonpath` returns `k3d-<spoke>-server-0`, NOT `k3d-hub-flux-server-0` — the P18 trip-wire. ~10s per spoke. Mirrors Phase 2 D-13 defensive posture. | ✓ |
| Moderate: presence + decode + auth roundtrip | Skip step 4. Trust that if auth works, the cluster identity is implicit. Risks P18: an auth roundtrip CAN succeed against the wrong cluster if both clusters share an admin SA in the same ns. | |
| Minimal: presence + decode only | Verify the Secret exists and the kubeconfig parses. Defer everything else to Phase 5 health-check + bats. Fastest. Worst P18 protection — a misrouted Secret looks identical to a correct one until Flux tries to reconcile. | |

**User's choice:** Belt-and-suspenders (Recommended)
**Notes:** Phase 4 is HIGH risk per ROADMAP — defensive in-script verification is the precedent (Phase 2 D-13 SAN-verify).

### Q2: Which hub pod does the in-pod probe exec into?

| Option | Description | Selected |
|--------|-------------|----------|
| kustomize-controller | Authoritative — this is the actual identity Flux's reconciliation uses. Probe failures here mirror real reconciliation failures. Pod is in flux-system on hub, always Ready post-Phase-3. | ✓ |
| source-controller | Wrong layer — source-controller fetches Git, doesn't authenticate to spoke apiservers. Not representative. | |
| Spawn a fresh debug pod | `kubectl run --rm -i busybox` / `kubectl exec` into a pod just for the probe. Clean isolation but extra moving parts; pod creation adds 5–10s; probe-time identity diverges from reconciliation identity. | |

**User's choice:** kustomize-controller (Recommended)

### Q3: How is the negative-proof done given user hasn't pushed yet?

| Option | Description | Selected |
|--------|-------------|----------|
| Node-name check via kubeconfig | `kubectl --kubeconfig <Secret content> get nodes -o jsonpath='{.items[*].metadata.name}'` returns `k3d-spoke-ml-server-0` for spoke-ml's Secret (NOT `k3d-hub-flux-server-0`). Catches P18 at the credential layer — BEFORE Flux even tries to reconcile. Doesn't require git push. Deterministic per cluster (k3d-`<name>`-server-0 is the node name set by k3d). | ✓ |
| Wait for user to push, then check Flux Kustomization .status.inventory | ROADMAP success #5 verbatim. Requires a two-step run (or interactive wait). Script blocks until user pushes — awful UX. | |
| Apply seed manifests imperatively then check .status.inventory | Defeats GitOps pattern. Script imperatively creates the seed resources, then waits for Flux to claim ownership via reconciliation. Adds drift surface. | |

**User's choice:** Node-name check via kubeconfig (Recommended)
**Notes:** Catches the P18 fault mode at a more fundamental layer than `.status.inventory` would.

### Q4: Where does the canonical .status.inventory negative-proof (ROADMAP success #5) live?

| Option | Description | Selected |
|--------|-------------|----------|
| Bats live/destructive test, runs after push | `tests/bats/register-spokes-04-inventory.bats` (renamed `register-spokes-02-live.bats` per CONTEXT.md): gated by `require_live_destructive()`, assumes git push has happened, queries `flux get kustomization spoke-ml -n flux-system` and asserts `.status.inventory` contains the spoke-only ConfigMap UID. Script's responsibility ends at 'kubeconfig auths into the right cluster'; reconciliation is GitOps and lives on its own clock. | ✓ |
| In-script with 5-min timeout polling | Script polls `.status.inventory` for up to 5 min hoping the user pushes. Blocks the terminal; bad UX; race if user takes longer. | |
| Both — script (fast feedback once pushed) + bats (canonical) | Script does the check IF the spoke Kustomization is found and Ready (skip if not). Bats covers the case-after-push canonically. Defensive but doubles the verification surface. | |

**User's choice:** Bats live/destructive test, runs after push (Recommended)

---

## Claude's Discretion

Items not explicitly discussed; planner/researcher decides per CONTEXT.md `<decisions>` Claude's Discretion subsection:

- Order of operations within `register_spoke` helper.
- Where the patch to `clusters/hub-flux/flux-system/kustomization.yaml` happens (once outside helper vs inside per spoke).
- Sentinel literal for the kustomization.yaml patch (recommended `# KARYON SPOKES MOUNT`).
- Idempotency check granularity for the `<spoke>-kubeconfig` Secret on the hub (3-part AND inheriting Phase 3 D-07).
- Token-Secret data-population wait timeout exact value (recommended 10s; researcher confirms typical k3s controller latency).
- `kubectl apply -f -` heredoc vs `kubectl create secret generic --dry-run=client -o yaml | kubectl apply -f -` for the hub Secret.
- In-pod kubectl invocation mechanics (kubectl-shipped-in-image vs sidecar fallback).
- CA / token export mechanics inside the in-pod probe (stdin vs Secret volume).
- `docs/flux-hub-spoke.md` Phase 4 section depth (recommended medium depth — REQ-IDs + value.yaml contract + P18 + node-name rationale).
- Diff/conflict handling on the `clusters/hub-flux/flux-system/kustomization.yaml` patch (idempotent re-apply via sentinel).
- Behavior on rerun if `clusters/<spoke>/` already contains Phase-5 content (skip-if-present, don't overwrite).

---

## Deferred Ideas

Captured in `04-CONTEXT.md` `<deferred>` section. Highlights:

- Token rotation / Secret renewal (v2; SOPS/age territory)
- Namespace-scoped RBAC narrowing (v2)
- TokenRequest tokens (rejected — PROJECT.md Phase-4 key decision)
- Auto-commit + auto-push from script (rejected — Phase 3 posture)
- Imperative-apply of hub-side Kustomization YAMLs (rejected — defeats GitOps)
- Two-step register/verify split (rejected — single-script keeps loop tight)
- In-script `.status.inventory` polling (rejected — UX)
- gitleaks pre-commit install in Phase 4 (Phase 6 owns it)
