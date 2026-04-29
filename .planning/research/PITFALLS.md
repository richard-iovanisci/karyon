# Pitfalls Research — v0.19 Capsule Multi-Tenancy POC

**Domain:** Adding Capsule + capsule-proxy + multi-tenant Flux to an existing hub-only Flux k3d lab (karyon, post-v0.18).
**Researched:** 2026-04-29
**Confidence:** HIGH on Capsule webhook + RBAC behaviour, the Flux `kubeConfig`/`serviceAccountName` interaction, capsule-proxy exposure modes, and the public-repo / kubeconfig leak surface (verified against Capsule v0.12 docs, Flux kustomize-controller v1 spec, fluxcd/flux2-multi-tenancy, and clastix/flux2-capsule-multi-tenancy). MEDIUM on Capsule v0.12 + k3s v1.34.6 currency (the v0.12 line was published Dec 2025 and explicitly requires Kubernetes >=1.34.0; no in-the-wild incompatibility reports surfaced for the specific patch v1.34.6+k3s1, but the matrix is fresh). MEDIUM on persistent-spoke CoreDNS-staleness behaviour for a fourth k3d cluster (extrapolated from k3d #1009/#1112 — same root cause as the existing 3-cluster lab).

---

## Summary

This pitfalls catalogue enumerates **integration-level mistakes** when bolting a Capsule POC onto the v0.18 karyon lab. It is NOT a generic Capsule docs cheat-sheet — every pitfall ties back to a specific v0.18 design choice (hub-only Flux per ADR-004, public repo per Phase 6 REPO-01..04, k3d-on-WSL2 single-host per ADR-001, `task rebuild` 20-min SLO per Phase 5 DESTROY-05/06, `KARYON SPOKES MOUNT` sentinel pattern from Phase 4 D-02).

The catalogue is organised into:

- **Critical pitfalls (P26–P34)** — would cause silent tenant escape, scorched-earth rebuild failures, public-repo secret leaks, or invariant-breaking ADR violations. Roadmap MUST address each one in a named phase.
- **Moderate pitfalls (P35–P40)** — operational footguns that don't break security but burn debugging time.
- **Minor pitfalls (P41–P43)** — ergonomic / docs gaps.
- **Pitfalls that DO NOT apply** — re-prevention work the planner should *skip* because v0.18 already mitigates the same root cause, or the v0.19 design choices remove the failure surface entirely.
- **Recovery strategies + a phase-mapping matrix** at the end.

**Numbering continues from v0.18 (which closed at P25)** so the planner can reference both catalogues without renumbering collisions. The v0.18 PITFALLS file is archived at `.planning/milestones/v0.18-research/PITFALLS.md`.

**Phase ordering convention used below** mirrors the v0.19 build-order from ARCHITECTURE.md research:

- **Phase 7 — POC Onboarding Seam** (KARYON POC MOUNT sentinel, gitignore, gitleaks, lifecycle isolation from `task rebuild` / `task health-check` / `register-spokes-for-flux.sh`)
- **Phase 8 — spoke-capsule cluster** (k3d cluster, `--tls-san`, persistence, NOT in default `task rebuild`)
- **Phase 9 — Capsule operator + capsule-proxy** (Flux HelmRelease, CRD ordering, webhook failurePolicy, cert-manager dependency)
- **Phase 10 — Tenants + Flux multi-tenancy lockdown** (Tenant CRs, tenant SA, Flux Kustomization with `spec.kubeConfig` + `spec.serviceAccountName`)
- **Phase 11 — Tenant kubeconfig + capsule-proxy access** (proxy-kubeconfig-generator, NodePort exposure, never-in-git contract)
- **Phase 12 — Validation + graduation ADR** (positive RBAC, negative RBAC, webhook-down probe, teardown probe, ADR-006)

Phase numbers are local to v0.19; the orchestrator may renumber.

---

## Pitfall Catalog

### P26: Capsule webhook `failurePolicy: Fail` blocks hub-flux Kustomization apply when capsule-proxy/operator pod is down

**What goes wrong:** Capsule installs `MutatingWebhookConfiguration` and `ValidatingWebhookConfiguration` against `Pod CREATE`, `PVC CREATE`, `Ingress CREATE/UPDATE`, `Namespace CREATE/UPDATE`, and `Tenant CREATE/UPDATE/DELETE`. Default chart values use `failurePolicy: Fail`. If the Capsule operator deployment is not Ready when hub-flux's kustomize-controller (running in `k3d-hub-flux`) tries to apply *any* tenant manifest into spoke-capsule via `spec.kubeConfig`, the spoke's apiserver fails the webhook callout and rejects the apply. The Flux Kustomization on the hub goes `Ready: False` with `failed calling webhook`. Worse: an Ingress or Pod create from the platform-admin path can also be blocked, because the webhook intercepts cluster-wide.

**Why it's likely in THIS lab:**
- The reconcile path is `hub-flux kustomize-controller → spoke-capsule:6443` (per ADR-004 + Phase 4 P18). The kustomize-controller pod has no operational coupling to Capsule's controller pod — the two cannot interlock to wait for each other.
- After `k3d cluster start spoke-capsule` the Capsule operator pod takes ~30–60s to become Ready. During that window any tenant Kustomization the hub tries to apply hits the webhook before the webhook backend is up.
- WSL/Docker restarts (the same trigger that motivated `task fix-dns`) will leave Capsule's pod Pending while the hub's Flux is already running and racing to reconcile.

**Detection signal:**
- `kubectl --context k3d-hub-flux -n flux-system get kustomization tenant-<name> -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}'` contains `failed calling webhook` or `connect: connection refused`.
- `kubectl --context k3d-spoke-capsule -n capsule-system get pods` shows `capsule-controller-manager` with `Ready: 0/1` while a tenant apply is in flight.
- bats: `tests/bats/capsule-webhook-recovery-live.bats` deletes the Capsule pod, confirms tenant Kustomization goes NotReady, then confirms recovery within 2m once the pod restarts (and *also* confirms platform-admin Kustomizations targeting non-tenant namespaces are NOT blocked, see P27).

**Prevention:**
1. Configure the Helm values so Capsule's webhooks have **`failurePolicy: Ignore`** for the POC. This is the documented Capsule guidance for non-critical-path control planes ("set failurePolicy=Ignore to avoid disruption when Capsule is not running"). Concrete YAML in `clusters/spoke-capsule/infrastructure/capsule-helmrelease.yaml`:
   ```yaml
   spec:
     values:
       webhook:
         failurePolicy: Ignore
   ```
2. **Always pair this with `matchConditions`/`namespaceSelector`** so the webhook only intercepts requests targeting Capsule-managed (tenant-labelled) namespaces, never `kube-system`, `flux-system`, or `capsule-system`. Capsule's chart already sets `objectSelector` excluding `capsule.clastix.io/tenant=` not present, but verify it survives our values overrides.
3. Hub Flux Kustomization `tenant-*` declares `dependsOn: [capsule-operator]` so reconciliation waits for the operator HelmRelease to report `Ready` before the first tenant apply.
4. Health-check assertion: Capsule pod Ready must be a precondition probe before any tenant Kustomization is checked.

**Phase to address:** Phase 9 (Capsule install) — set `failurePolicy: Ignore` in HelmRelease values; Phase 10 — add `dependsOn` chain.

---

### P27: Tenant escape via Flux — hub `flux-reconciler` SA has cluster-admin on spoke-capsule, so a tenant Kustomization without `spec.serviceAccountName` runs as cluster-admin and bypasses Capsule entirely

**What goes wrong:** v0.18's spoke-side identity is `flux-reconciler` ServiceAccount with `ClusterRoleBinding` to `cluster-admin` (per Pattern 3 in ARCHITECTURE.md). The kubeconfig on hub embeds that token. If a tenant's Flux Kustomization on the hub does NOT set `spec.serviceAccountName: <tenant-sa>`, kustomize-controller applies the tenant's manifests using the embedded `flux-reconciler` token — i.e. as `cluster-admin` on the spoke. Capsule's webhooks **deliberately exempt cluster-admin / kube-system identities** from tenant boundary enforcement (see Capsule's webhook `matchConditions`). Result: the tenant can create resources outside their namespace, bind themselves to cluster-admin, and Capsule will not stop them. **This is a Capsule-bypass equivalent to having no multi-tenancy at all.**

**Why it's likely in THIS lab:**
- v0.18 ADR-004 (`hub-only Flux`) commits us to one shared `flux-reconciler` cluster-admin SA per spoke. There is no per-tenant kubeconfig on the hub by default; everything reuses `spoke-capsule-kubeconfig` Secret.
- The Flux multi-tenancy lockdown patch (`--default-service-account`) **does not apply when `spec.kubeConfig` is set** — per Flux v1 spec, the default-SA flag is for local-cluster reconcile only. Cross-cluster reconcile gets *no* automatic safety net.
- The "obvious" tenant Kustomization shape (just copy spoke-apps.yaml, change the path) ships without `spec.serviceAccountName` — it works in v0.18 because there's no Capsule, but in v0.19 it becomes the silent escape.

**Detection signal:**
- bats negative-RBAC test: applies a tenant Kustomization without `spec.serviceAccountName`; expects either (a) Flux refuses to apply (best — see Prevention #2), or (b) the apply succeeds AND a follow-up `kubectl auth can-i create namespace --as=system:serviceaccount:tenant-a:reconciler -n kube-system` returns `no`. If (a) does not refuse AND (b) returns `yes`, escape is live.
- Audit probe: `kubectl --context k3d-spoke-capsule logs -n capsule-system deploy/capsule-controller-manager --tail=200 | grep -i bypass` — Capsule logs identify which SA bypassed the webhook by `matchConditions`.
- Static check: a CI bats test greps every `clusters/spoke-capsule/tenants/**/kustomization.yaml` for `spec.serviceAccountName:` and fails if any is missing.

**Prevention:**
1. **Every tenant Flux Kustomization on the hub MUST set `spec.serviceAccountName: <tenant-owner-sa-name>`.** That SA must exist on spoke-capsule in the namespace matching the Kustomization's hub namespace (`flux-system`). Per Flux docs: with both `kubeConfig` and `serviceAccountName`, kustomize-controller impersonates the named SA on the *target* cluster.
2. Add a static bats assertion that fails fast in CI:
   ```bash
   for f in clusters/spoke-capsule/tenants/*/flux-tenant-kustomization.yaml; do
     yq '.spec.serviceAccountName' "$f" | grep -qv null
   done
   ```
3. Document this in `docs/capsule-poc.md` as the load-bearing security invariant (analogous to v0.18's P18 `spec.kubeConfig` invariant).
4. **Optional but recommended:** Replace the cluster-admin `flux-reconciler` SA on spoke-capsule with a *less-privileged* SA that can only `impersonate` tenant SAs in `flux-system`. This is the canonical clastix/flux2-capsule-multi-tenancy pattern. Out of scope for v1 POC if it complicates the Phase 4 v0.18 SA recipe; track as a v0.20 follow-up. Note however that the existing v0.18 `cluster-admin` token + `spec.serviceAccountName` impersonation already gives Capsule the chokepoint it needs.

**Phase to address:** Phase 10 (Tenants + Flux multi-tenancy lockdown) owns the static bats; Phase 12 (Validation) owns the live negative-RBAC probe.

---

### P28: capsule-proxy exposure as ClusterIP makes tenant kubeconfigs unreachable from a developer's WSL2 host — must be NodePort with a stable host port

**What goes wrong:** capsule-proxy default Helm values expose the proxy as `ClusterIP` on port 9001. From inside the spoke-capsule cluster a tenant Pod can `curl https://capsule-proxy.capsule-system.svc:9001`. **From the developer's WSL2 host** (i.e. the human running `kubectl --kubeconfig tenant-a.kubeconfig`), the ClusterIP is unreachable — there is no `host.docker.internal`-style hop into a k3d service IP. Tenant kubeconfigs that point at `https://capsule-proxy.capsule-system.svc:9001` will fail with `dial tcp: lookup capsule-proxy.capsule-system.svc: no such host`.

**Why it's likely in THIS lab:**
- v0.18 only ever needed cross-cluster `apiserver` reach FROM the hub (kustomize-controller running inside `k3d-hub-flux`). That used Docker DNS on the shared `k8s-net` bridge — fine for *pod-to-pod-on-shared-bridge* traffic, useless for *host-to-pod*.
- The whole point of the POC is "a tenant developer runs `kubectl get pods` from their dev machine and Capsule filters the response." That implies the human is OUTSIDE the cluster.
- WSL2 + k3d + Docker bridge means the only stable reachable surface from the host is `127.0.0.1:<host-port>`, where `<host-port>` is whatever k3d's loadbalancer published.

**Detection signal:**
- Static: bats greps `clusters/spoke-capsule/infrastructure/capsule-proxy-helmrelease.yaml` for `service.type` and asserts `NodePort`.
- Live: `curl -sk https://127.0.0.1:<nodeport>/healthz` from the WSL2 host returns 200; same query against the ClusterIP fails.
- Generated tenant kubeconfig must contain `server: https://127.0.0.1:<nodeport>` (or a stable hostname → host-mapped port), NOT `https://capsule-proxy.capsule-system.svc:9001`.

**Prevention:**
1. capsule-proxy Helm values fix `service.type: NodePort` AND pin `service.nodePort: 30443` (or another stable port outside the v0.18 `127.0.0.1:6443/6444/6445` triple AND outside the spoke-capsule's own `--api-port` host mapping).
2. `k3d cluster create spoke-capsule` MUST publish that NodePort to the host. The k3d incantation:
   ```
   k3d cluster create spoke-capsule \
     --image rancher/k3s:v1.34.6-k3s1 \
     --network k8s-net \
     --port "30443:30443@loadbalancer" \
     --k3s-arg '--tls-san=k3d-spoke-capsule-server-0@server:*' \
     --api-port 127.0.0.1:6446
   ```
3. **Tenant kubeconfig server URL: `https://127.0.0.1:30443`** (NOT the in-cluster service name, NOT the k3d-spoke-capsule-server-0 hostname).
4. capsule-proxy's TLS serving cert must cover `127.0.0.1` (and ideally `localhost`) — verify the cert's SAN list. The cert-manager-issued default cert for the proxy includes the service DNS but may not include `127.0.0.1`. Override via Helm values or accept the cert via `insecure-skip-tls-verify: true` in the tenant kubeconfig (acceptable for POC; document as v0.19 simplification).
5. Document the dual-server-URL caveat in `docs/capsule-poc.md`: pods inside spoke-capsule reach the proxy via the in-cluster service; humans reach it via `127.0.0.1:30443`.

**Phase to address:** Phase 8 (spoke-capsule cluster) owns the `k3d cluster create` flag; Phase 9 (Capsule install) owns the Helm values; Phase 11 (tenant kubeconfig) owns the server URL choice + insecure-skip-tls-verify decision.

---

### P29: Tenant kubeconfigs land in `git status` — public-repo + bearer-token leak unrecoverable

**What goes wrong:** v0.18's secrets contract (`.gitignore` Phase 6 D-16 expansion) covers `kubeconfig*` and `*.kubeconfig` — but it covers **only filenames matching those globs**. The `proxy-kubeconfig-generator` utility produces a kubeconfig that the Phase 11 setup script will emit to a working file. If the script emits to (for example) `tenants/tenant-a/admin.yaml`, the gitignore globs do NOT match, and the next `git add tenants/` puts a tenant token straight onto the public main branch. Same for any tenant kubeconfig stored as `tenant-a-config`, `kubeconfig-tenant-a`, or `tenant-a/access.yaml`.

The v0.18 `.gitignore` glob list:
```
kubeconfig*
*.kubeconfig
```
does NOT match `admin.yaml`, `access.yaml`, `tenant-a-config`, `users/alice.yaml`. gitleaks **does** scan content, but its default ruleset has no kubeconfig-shaped pattern (no `kind: Config` regex). Default rules look for high-entropy strings + named API keys; a Kubernetes bearer token is a JWT-like high-entropy string and gitleaks usually catches it via the entropy heuristic, but v0.18 added an explicit `.gitleaks.toml` *allowlist* for `.env.example`, and the project's gitleaks config does not currently include a positive rule that ALWAYS flags a `kind: Config` document.

**Why it's likely in THIS lab:**
- Public repo from day one (Phase 6 REPO-01..04). A leaked tenant token reaches GitHub the second a developer pushes.
- v0.18's 5-layer secrets defense was tuned for `GITHUB_TOKEN`, not for kubeconfig-shaped artifacts. Layers (a) gitignore + (b) gitleaks allowlist + (c) gitleaks pre-commit + (d) post-push CI gitleaks-scan + (e) one-shot history scan all assume the leak vector is short PAT-shaped tokens.
- The `proxy-kubeconfig-generator` utility from clastix is an external tool that produces a multi-line YAML document with `users.user.token: <jwt>`. Multi-line tokens can sometimes evade entropy heuristics if line-folded.
- A future refactor could store tenant kubeconfigs under `tenants/tenant-a/` "for convenience" — exactly the pattern that defeats the existing gitignore globs.

**Detection signal:**
- Pre-commit: gitleaks must catch a synthetic kubeconfig fixture. Add an explicit gitleaks rule that matches the literal `kind: Config` plus `users:` plus a bearer-token shape (multi-line regex). Test it with a fixture file under `tests/fixtures/leaked-kubeconfig.yaml` (NOT committed; placed in a temp file by the bats test).
- Static bats: `tests/bats/v0.19-public-repo.bats` greps `git ls-files` for any path matching `**/{tenant,access,user,admin}*.yaml` AND with content containing `kind: Config`. Fails if found.
- CI gitleaks-scan with `fetch-depth: 0` already runs on every push — extend `.gitleaks.toml` with the kubeconfig rule; it will scan the whole history.

**Prevention:**
1. **Expand `.gitignore` (D-16+1):**
   ```
   # v0.19 — Capsule POC tenant kubeconfigs (public-repo defense)
   tenants/**/access.yaml
   tenants/**/admin.yaml
   tenants/**/kubeconfig.yaml
   tenants/**/*.kubeconfig
   tenants/**/users/*.yaml
   ```
2. **Add an explicit gitleaks rule** in `.gitleaks.toml` that matches kubeconfig shape:
   ```toml
   [[rules]]
   id = "kubeconfig-bearer-token"
   description = "Kubernetes kubeconfig with embedded bearer token"
   regex = '''(?ms)^kind:\s*Config[\s\S]*?users:[\s\S]*?token:\s*[A-Za-z0-9._-]{32,}'''
   tags = ["kubernetes", "kubeconfig", "bearer-token"]
   ```
3. **The `proxy-kubeconfig-generator` invocation script must write to a path that's already gitignored**, AND produce a separate, public-safe `*-template.yaml` that the user's command line fills in via `KUBE_TOKEN_PATH=...` indirection. Default output path: `${TMPDIR:-/tmp}/karyon-tenant-<name>.kubeconfig` — outside the repo entirely.
4. **Document the contract in `.env.example` style**: a `tenants/.env.example` with comments naming `KARYON_TENANT_KUBECONFIG_DIR=/tmp/karyon-tenants` as the convention.
5. **Bats fixture** under `tests/fixtures/synthetic-kubeconfig.yaml` (NOT committed — written by the test setup, deleted by teardown) confirms gitleaks catches it before the rule lands in production.
6. v0.19 needs its own one-shot history scan after the first push that introduces tenant kubeconfigs (parallel to v0.18's 251-commit clean scan from REPO-04).

**Phase to address:** Phase 7 (POC Onboarding Seam) owns the `.gitignore` expansion + `.gitleaks.toml` rule; Phase 11 (Tenant kubeconfig) owns the generator script's output-path choice; Phase 12 (Validation) owns the synthetic-fixture gitleaks bats and the one-shot history scan.

---

### P30: KARYON POC MOUNT sentinel collides with KARYON SPOKES MOUNT (or with itself if two POCs land in the same path)

**What goes wrong:** v0.18 Phase 4 D-02 introduced a sentinel-guarded patch surface in `clusters/hub-flux/flux-system/kustomization.yaml`:
```yaml
resources:
  - gotk-components.yaml
  - gotk-sync.yaml
  # KARYON SPOKES MOUNT
  - ../spokes
```
The `# KARYON SPOKES MOUNT` literal is matched verbatim by `scripts/register-spokes-for-flux.sh` (line 30: `readonly SPOKES_SENTINEL="# KARYON SPOKES MOUNT"`). The v0.19 milestone goal calls for a generic `KARYON POC MOUNT` sentinel for future-POC onboarding. **Three failure modes:**

1. **Same-line collision:** The new sentinel `# KARYON POC MOUNT` and `- ../pocs/capsule` lines are placed BELOW `# KARYON SPOKES MOUNT`. A future awk/sed insert keyed on the SPOKES sentinel could mis-detect and place a SPOKES item inside the POCS section, or vice versa.
2. **Sentinel grep ambiguity:** `grep -F 'KARYON' clusters/hub-flux/flux-system/kustomization.yaml` returns multiple matches; idempotency checks that `grep -c` for "the sentinel exists" and expect `1` will become flaky.
3. **Two POCs same path:** A v0.20 POC adds resources under `clusters/hub-flux/pocs/<other>` — the awk insert that placed the v0.19 line breaks because the mount block now has two child-resource lines and the script's sentinel-anchored insert prepends instead of appends.

**Why it's likely in THIS lab:**
- The success of v0.18's SPOKES sentinel pattern guarantees we'll repeat the pattern. But the existing pattern is hard-coded to `# KARYON SPOKES MOUNT` — there's no generic *category* abstraction yet.
- The flux-system/kustomization.yaml file is bootstrap-managed (`flux bootstrap` regenerates it every reconcile cycle) — the only way to make our patches survive is to keep the awk-insert idempotent, which means strict sentinel control.
- The v0.18 `register-spokes-for-flux.sh` script already does sentinel-anchored mutations to this file. A second script doing similar work is a merge-conflict risk.

**Detection signal:**
- bats: `tests/bats/poc-mount-sentinel.bats` asserts:
  - Both sentinels appear exactly once (`grep -c '# KARYON SPOKES MOUNT' = 1` AND `grep -c '# KARYON POC MOUNT' = 1`)
  - Each sentinel has a corresponding `- ../<dir>` line on the next non-blank line
  - The two sentinels do NOT overlap (no resource line between them is missing the leading `- `)
- After `flux bootstrap` re-runs (Phase 3 contract), both sentinels survive (idempotent re-insert by the registration script + new POC-onboarding script).

**Prevention:**
1. **Disambiguate the sentinels with category prefixes.** Use:
   - `# KARYON SPOKES MOUNT` (existing — keep verbatim)
   - `# KARYON POC MOUNT — capsule` (v0.19 — note the per-POC suffix)
   This is greppable as `# KARYON POC MOUNT` (prefix-anchored) AND distinct per-POC. A future v0.20 POC adds `# KARYON POC MOUNT — vcluster` and the existing `capsule` mount is untouched.
2. **One file, one sentinel-namespace, one resources line per sentinel.** Each POC gets exactly one `- ../pocs/<poc-name>` line. Multi-resource POCs aggregate into their own `pocs/<poc-name>/kustomization.yaml`.
3. **Use a separate awk-insert function for POC mount vs spokes mount.** The v0.19 onboarding script `scripts/register-poc.sh` (or whatever Phase 7 names it) MUST NOT reuse `register-spokes-for-flux.sh`'s sentinel-insert helper. Bats asserts both functions are independent.
4. The v0.18 SPOKES `kustomization.yaml` pattern (`clusters/hub-flux/spokes/kustomization.yaml` aggregates `spoke-ml.yaml + spoke-apps.yaml`) is a precedent — adopt the same shape for `clusters/hub-flux/pocs/kustomization.yaml`.

**Phase to address:** Phase 7 (POC Onboarding Seam) — defines the sentinel disambiguation, writes the bats, ships `scripts/register-poc.sh`.

---

### P31: spoke-capsule lifecycle accidentally coupled to `task rebuild` / `task health-check` / `scripts/register-spokes-for-flux.sh` — POC pollutes the v1 SLO

**What goes wrong:** v0.18 Phase 5 DESTROY-05/06 measured `task rebuild` at 190 seconds with warm CUDA cache. v0.19 PROJECT.md explicitly calls out **`spoke-capsule` is persistent for the POC, NOT part of default v1 topology, NOT in `task rebuild`**. Three failure modes that violate this:

1. `scripts/create-clusters.sh` (Phase 2 v0.18 — CLU-01..05) hard-codes `for c in hub-flux spoke-ml spoke-apps`. A patch that adds `spoke-capsule` to that loop pulls the POC into `task rebuild`.
2. `scripts/register-spokes-for-flux.sh` (Phase 4 v0.18 — SPOKE-01..04) hard-codes the same triple. Same risk.
3. `scripts/health-check.sh` (Phase 5 v0.18 — HEALTH-01..06) checks all clusters for Ready nodes and Flux Kustomizations. Adding `spoke-capsule` to its loop without gating means health-check fails when the POC is intentionally torn down.

Knock-on consequences: rebuild SLO regresses (was 190s; spoke-capsule + Capsule HelmRelease + capsule-proxy = +60–120s). The graduation ADR prematurely "adopts" Capsule by forcing it into rebuild.

**Why it's likely in THIS lab:**
- The whole v0.18 codebase has a `for c in hub-flux spoke-ml spoke-apps` shape baked into 5+ scripts. The "obvious" diff for a new spoke is to extend the loop.
- The `task rebuild` SLO was the headline v0.18 deliverable; protecting it across POCs requires explicit guardrails, not just docs.
- The `KARYON POC MOUNT` sentinel keeps Flux-side wire-up clean, but doesn't prevent script-side coupling.

**Detection signal:**
- Static bats: `tests/bats/poc-isolation.bats` greps every script in `scripts/` for `spoke-capsule` and asserts:
  - `scripts/create-clusters.sh` does NOT mention `spoke-capsule`
  - `scripts/register-spokes-for-flux.sh` does NOT mention `spoke-capsule`
  - `scripts/health-check.sh` does NOT mention `spoke-capsule` (or only inside a guarded `if [ -n "$KARYON_POC_CAPSULE" ]` block)
  - `scripts/rebuild.sh` does NOT mention `spoke-capsule`
  - `scripts/destroy.sh` / `scripts/delete-clusters.sh` do NOT mention `spoke-capsule` (POC tears down via its OWN dedicated `task destroy-poc-capsule`)
- Live: `task rebuild` end-to-end run with spoke-capsule **alive** — must not touch it. After rebuild, `kubectl --context k3d-spoke-capsule get nodes` still works (cluster intact).
- Live: `task rebuild` end-to-end run with spoke-capsule **already destroyed** — must succeed without trying to re-create it. SLO check: 190s ± 20s.

**Prevention:**
1. **All POC concerns live in dedicated scripts under `scripts/poc/capsule/`** (new directory). Examples: `scripts/poc/capsule/create-cluster.sh`, `scripts/poc/capsule/install-operator.sh`, `scripts/poc/capsule/register-tenant.sh`, `scripts/poc/capsule/destroy.sh`.
2. **Dedicated Taskfile entries** that DO NOT compose into `rebuild`: `task poc-capsule-up`, `task poc-capsule-down`, `task poc-capsule-validate`. None of these are wired into `task rebuild`'s chain.
3. **Negative-test the SLO**: Phase 12 validation runs `task rebuild` and asserts `task rebuild` log timing < 230 seconds (= v0.18 SLO + 20s margin) AND that `task health-check` does NOT mention `spoke-capsule`.
4. **Health-check graduation path:** if/when ADR-006 graduates Capsule into v1, that ADR is the trigger for adding `spoke-capsule` to the v1 scripts — not before.

**Phase to address:** Phase 7 (POC Onboarding Seam) — defines the script-isolation pattern + bats; Phase 8 (spoke-capsule cluster) — owns `scripts/poc/capsule/create-cluster.sh`; Phase 12 (Validation) — owns the rebuild SLO regression test.

---

### P32: Capsule HelmRelease applied before Capsule CRDs exist → Tenant CR reconciles fail with `no matches for kind "Tenant"`

**What goes wrong:** Capsule's Helm chart bundles its CRDs (`Tenant`, `CapsuleConfiguration`, `TenantResource`, etc.) and installs them. But the order across two Flux Kustomizations is:
1. Hub kustomize-controller applies `clusters/spoke-capsule/infrastructure/capsule-helmrelease.yaml` (the HelmRelease + a Source) → spoke's helm-controller installs the chart → CRDs land.
2. Hub kustomize-controller applies `clusters/spoke-capsule/tenants/tenant-a.yaml` (a `Tenant` CR).

If both files are in the same hub Kustomization with the same reconcile interval, kustomize-controller server-side-applies them in one batch, in alphabetical order — `infrastructure` first, then `tenants`. **But the Tenant CR is rejected** because the CRD has not yet been registered by the spoke's apiserver discovery cache. Symptom: hub Kustomization status `Reconciliation failed: no matches for kind "Tenant" in version "capsule.clastix.io/v1beta2"`. The HelmRelease is reconciling concurrently — by the time you re-run, the CRDs exist; this hides the flake.

**Why it's likely in THIS lab:**
- v0.18's hub kustomize-controller treats one path as one apply batch. There's no CRD-aware staging.
- Capsule v0.12's chart sets `crds: install: true` (default) but the discovery refresh on the spoke's apiserver is the wait point, not the chart.
- The `task rebuild`-style cold-start sequence amplifies the race: bootstrap → register spokes → reconcile Capsule → reconcile tenants in sub-second sequence.

**Detection signal:**
- Live: first `task poc-capsule-up` after a fresh spoke-capsule create → tenant Kustomization status reports `no matches for kind "Tenant"` for ~20–60s, then self-heals.
- Bats: `tests/bats/capsule-crd-ordering-live.bats` triggers a fresh install (delete spoke-capsule, recreate, apply Flux), waits for `Tenant` CR Ready, fails if the wait exceeds 5 minutes.

**Prevention:**
1. **Two Flux Kustomizations on the hub, with `dependsOn`:**
   ```yaml
   # clusters/hub-flux/pocs/capsule/capsule-operator.yaml
   apiVersion: kustomize.toolkit.fluxcd.io/v1
   kind: Kustomization
   metadata:
     name: capsule-operator
     namespace: flux-system
   spec:
     path: ./clusters/spoke-capsule/infrastructure
     kubeConfig:
       secretRef:
         name: spoke-capsule-kubeconfig
         key: value.yaml
     wait: true
     timeout: 5m
   ---
   # clusters/hub-flux/pocs/capsule/capsule-tenants.yaml
   apiVersion: kustomize.toolkit.fluxcd.io/v1
   kind: Kustomization
   metadata:
     name: capsule-tenants
     namespace: flux-system
   spec:
     path: ./clusters/spoke-capsule/tenants
     kubeConfig:
       secretRef:
         name: spoke-capsule-kubeconfig
         key: value.yaml
     dependsOn:
       - name: capsule-operator
     wait: true
     timeout: 10m
   ```
   The `dependsOn` + `wait: true` combo means tenants' Kustomization will not even start applying until `capsule-operator` reports Ready (HelmRelease installed and the chart's CRDs are present).
2. **HelmRelease `install.crds: Create` AND `upgrade.crds: CreateReplace`** — explicit Helm options so the chart's CRDs land deterministically.
3. **Health-check probe** on the operator side: hub Flux Kustomization checks `kubectl --context spoke-capsule get crd tenants.capsule.clastix.io` exists before declaring `capsule-operator` Ready (Flux's default `wait: true` checks HelmRelease status only — that's USUALLY enough but doubles up nicely with an explicit CRD presence probe in the validation phase).
4. **Order of operations in `scripts/poc/capsule/install.sh` (one-shot manual):** `flux reconcile kustomization capsule-operator --with-source && flux reconcile kustomization capsule-tenants --with-source`.

**Phase to address:** Phase 9 (Capsule operator install) — owns the dependsOn chain; Phase 10 (Tenants) — owns the second Kustomization.

---

### P33: capsule-proxy serving cert SANs missing `127.0.0.1` (or whatever host-side address the tenant kubeconfig uses) — TLS fails AFTER auth works

**What goes wrong:** capsule-proxy's default Helm values issue a TLS serving cert via cert-manager (or its built-in certgen) whose SANs cover the in-cluster service DNS name (`capsule-proxy.capsule-system.svc`). When the tenant kubeconfig is configured with `server: https://127.0.0.1:30443`, the TLS handshake fails with `x509: certificate is valid for capsule-proxy.capsule-system.svc, capsule-proxy.capsule-system.svc.cluster.local, not 127.0.0.1`. Symptom from the developer's machine: `kubectl get pods` returns `Unable to connect to the server: x509: certificate is valid for ..., not 127.0.0.1`. Auth (token) was never even sent.

**Why it's likely in THIS lab:**
- This is the proxy-side analogue of v0.18 P6 (k3d apiserver TLS SAN missing) — same shape of failure, different component. The lab has ADR-supported guidance for k3s `--tls-san` (Phase 2) but capsule-proxy's cert is governed by Helm values, not k3d flags.
- The "obvious" tenant kubeconfig points at `127.0.0.1:30443` (per P28 prevention); the "obvious" capsule-proxy install does not extend its SANs to cover host-side IPs.
- The lab cannot use a real ingress (PROJECT.md v0.19 Out-of-Scope: "Production ingress / TLS for capsule-proxy"), which means we're stuck with self-signed certs — fixing the SANs at install time is the only cheap option.

**Detection signal:**
- Static: bats greps `clusters/spoke-capsule/infrastructure/capsule-proxy-helmrelease.yaml` for `certManager` or `tls.additionalSANs` containing `127.0.0.1`.
- Live: `kubectl --kubeconfig /tmp/karyon-tenants/tenant-a.kubeconfig get pods` from the WSL2 host succeeds (no x509 error). If failing, examine `openssl s_client -connect 127.0.0.1:30443 < /dev/null 2>&1 | openssl x509 -noout -text | grep -A1 'Subject Alternative Name'`.

**Prevention:**
1. capsule-proxy Helm values inject `127.0.0.1` (and `localhost`) into the serving cert's SANs. Concrete YAML fragment depends on whether we use cert-manager or built-in certgen — lock the choice in Phase 9. With cert-manager:
   ```yaml
   spec:
     values:
       options:
         additionalSANs:
           - 127.0.0.1
           - localhost
   ```
   (exact key path: see capsule-proxy chart values reference).
2. **POC simplification escape hatch:** if cert SAN injection is fiddly, the tenant kubeconfig sets `insecure-skip-tls-verify: true`. Document this as a v0.19 POC simplification with a follow-up note that v0.20 hardens via cert-manager + valid SAN list. ADR-006 (graduation) is the right place to record the deferral.
3. **Health-check live probe:** `tests/bats/capsule-proxy-tls-live.bats` runs `openssl s_client` against `127.0.0.1:30443` and asserts the cert SANs include `127.0.0.1` (or asserts the documented `insecure-skip-tls-verify: true` shortcut is in the kubeconfig generator script).

**Phase to address:** Phase 9 (capsule-proxy install) — Helm values; Phase 11 (tenant kubeconfig) — server URL + skip-verify decision; Phase 12 (Validation) — TLS bats.

---

### P34: cert-manager dependency for Capsule webhook certs — install-order chain hub→spoke

**What goes wrong:** Capsule's `MutatingWebhookConfiguration` and `ValidatingWebhookConfiguration` need a TLS serving cert (for the apiserver to call into the webhook backend pod). Two installation modes:
- **Built-in Helm certgen** (the chart's `tls.create=true` default): a pre-install Helm hook runs a Job that generates a self-signed cert and writes it to a Secret. Works without cert-manager, but the regeneration semantics are awkward in GitOps (chart upgrade may attempt re-generate; idempotency depends on the chart version).
- **cert-manager-issued cert** (`certManager.generateCertificates=true`, `tls.create=false`): the chart creates `Issuer` + `Certificate` resources, cert-manager produces the Secret. Cleaner GitOps semantics, but cert-manager **must be installed and Ready BEFORE the Capsule chart reconciles**, or Capsule's webhook pod stays NotReady waiting for its cert Secret.

If the planner picks cert-manager mode without wiring `dependsOn`, the spoke-capsule reconcile sequence is `hub-flux applies cert-manager → applies Capsule (in parallel) → cert-manager not Ready yet → Capsule cert Secret not created → Capsule pod CrashLoopBackOff`.

If the planner picks the built-in certgen mode, there's a Helm-hook Job that v0.18's GitOps doesn't have a precedent for — flux-helm-controller does support pre-install hooks, but the lifecycle on `task rebuild` (NOT applicable here, but on a fresh cold start of spoke-capsule) is worth verifying.

**Why it's likely in THIS lab:**
- v0.18's clusters do NOT install cert-manager. Adding it for the POC is a dependency chain, not a one-liner.
- The "obvious" first try is to install Capsule with default values; the default values include `failurePolicy: Fail` (P26) AND assume the user knows whether they want certgen or cert-manager.

**Detection signal:**
- Live: capsule-controller-manager pod status — if the pod stays `ContainerCreating` waiting for `capsule-tls` Secret to mount, the cert source isn't ready.
- bats: `tests/bats/capsule-cert-source-live.bats` waits up to 3m for capsule-controller-manager to be Ready; on timeout, prints both pod events and which Secret it was waiting on.

**Prevention:**
1. **Decision: use the built-in `certgen` mode for the POC** — values: `certManager.generateCertificates=false`, `tls.create=true`. This avoids the cert-manager prereq chain entirely. Trade-off: chart upgrade may re-issue the cert; for the POC this is acceptable. Document as a v0.19 simplification.
2. If cert-manager mode is preferred (longer-term), add a separate hub Flux Kustomization `cert-manager` that targets spoke-capsule, set `dependsOn: [cert-manager]` on the Capsule Kustomization, and verify the Helm chart values are set correctly.
3. **Log the choice in `docs/poc-capsule.md` and ADR-006** explicitly. The decision is reversible but matters for the hub-Flux dependsOn chain.

**Phase to address:** Phase 9 (Capsule install) — owns the certgen-vs-cert-manager decision; Phase 12 (Validation) — owns the live cert-source probe.

---

## Moderate Pitfalls

### P35: Persistent spoke-capsule cluster goes stale across Docker / WSL restart — same CoreDNS NodeHosts bug as v0.18 P11, now affecting a *fourth* cluster

**What goes wrong:** v0.18 P11 (k3d issues #1009, #1112) — CoreDNS NodeHosts entries in the cluster's CoreDNS ConfigMap go stale after Docker daemon restart or WSL2 resume. v0.18 mitigates with `task fix-dns` which `k3d cluster stop hub-flux && k3d cluster start hub-flux`. **This applies to spoke-capsule too**, but `task fix-dns` only operates on `hub-flux`. After a WSL restart with spoke-capsule alive, hub-flux's CoreDNS entries get refreshed by the existing fix-dns; but **spoke-capsule's CoreDNS entries are NOT refreshed** unless the user knows to extend the workaround.

**Why it's likely in THIS lab:**
- spoke-capsule is a persistent fourth cluster on the shared `k8s-net` Docker bridge. Any pod inside spoke-capsule that needs cross-cluster DNS (e.g., capsule-proxy logs sometimes mention reaching the k3d apiserver via the in-network DNS name) will hit the stale-NodeHosts trap.
- Existing v0.18 mitigation hard-codes `hub-flux` as the only cluster to bounce.

**Detection signal:**
- After `wsl --shutdown && wsl` cycle, `kubectl --context k3d-spoke-capsule -n capsule-system exec deploy/capsule-controller-manager -- nslookup k3d-spoke-capsule-server-0` either returns NXDOMAIN or stale IP.
- bats: `tests/bats/wsl-restart-recovery-poc.bats` — gated on `KARYON_LIVE_DESTRUCTIVE=1` because cycling WSL is heavy-handed. May want to skip in default test runs.

**Prevention:**
1. Extend the `task fix-dns` script (or add a `task fix-dns-poc-capsule`) to also bounce spoke-capsule. Implementation: `scripts/fix-coredns.sh` already takes a cluster argument; adding `spoke-capsule` to its target list when `KARYON_POC_CAPSULE_ACTIVE=1` (env signal) is a small change.
2. Document the recovery action in `docs/poc-capsule.md`.
3. Decide whether to add `spoke-capsule` to the default `task fix-dns` chain. **Recommendation: NO** (per P31 — keep POC isolated from v1 health/fix paths). Instead, ship a separate `task fix-dns-poc-capsule`.

**Phase to address:** Phase 8 (spoke-capsule cluster) — adds the dedicated fix-dns task; Phase 12 (Validation) — light-touch documentation, optional WSL-restart bats.

---

### P36: Tenant teardown leaves stranded PVCs / RoleBindings / NetworkPolicies → spoke-capsule accumulates orphans across rebuild loops

**What goes wrong:** Capsule's `Tenant` CR creates Namespaces (Capsule-managed) and Capsule's controller propagates RoleBindings, ResourceQuotas, LimitRanges, and NetworkPolicies into each tenant namespace. When the Tenant is deleted, Capsule's controller tears down the Namespaces. **But:**
- PVCs in tenant namespaces have `pvc-protection` finalizers; if a Pod still references the PVC, the namespace deletion blocks until the Pod terminates. Combined with Capsule's NetworkPolicy enforcement and the tenant's possibly-stuck Pods, namespaces can stick in `Terminating` for hours.
- If the tenant Flux Kustomization (the *hub*-side one) is deleted out-of-order with the Tenant CR, the controller can't reconcile cleanup; the Tenant itself can stick on its `capsule.clastix.io/tenant-protection` finalizer.

**Why it's likely in THIS lab:**
- POC iteration cycles will see frequent `task poc-capsule-down && task poc-capsule-up` runs. Each iteration accumulates orphans if cleanup is partial.
- The graduation ADR depends on a clean teardown story.

**Detection signal:**
- After `task poc-capsule-down` (full teardown), `kubectl --context k3d-spoke-capsule get ns,pvc -A | grep -i terminating` should return nothing.
- bats: `tests/bats/capsule-teardown-cleanup-live.bats` runs `task poc-capsule-up`, applies tenant resources (deployment + PVC), runs `task poc-capsule-down`, asserts no stuck namespaces or PVCs after 90s.

**Prevention:**
1. **`task poc-capsule-down` runs in correct order:**
   1. Suspend hub Flux Kustomization for `capsule-tenants` (`flux suspend kustomization capsule-tenants`).
   2. Delete Tenant CRs explicitly (`kubectl --context spoke-capsule delete tenant --all`).
   3. Wait for Capsule's namespace reconciliation to complete (poll `kubectl get ns -l capsule.clastix.io/tenant=`).
   4. If any namespace stuck in Terminating > 60s, force-delete remaining PVCs (`kubectl get pvc -A -l capsule.clastix.io/tenant= -o json | jq ...`).
   5. Suspend `capsule-operator` Kustomization, then resume to allow controlled HelmRelease uninstall.
   6. Optionally: full nuclear option — `k3d cluster delete spoke-capsule` (the tenant POC's destroy script — NOT to be confused with v1 `task destroy`).
2. **Document the per-step preconditions** in `docs/poc-capsule.md`.
3. **Persistent-cluster mode means we expect data residue.** For iteration speed, accept that `task poc-capsule-up` may report "namespace exists, reconciling" rather than "fresh start." Document this.

**Phase to address:** Phase 12 (Validation + graduation ADR) — owns the teardown ordering script + bats.

---

### P37: Negative-RBAC test (`kubectl auth can-i`) returns stale results due to apiserver SubjectAccessReview cache → flaky tenant isolation tests

**What goes wrong:** `kubectl auth can-i` calls the Kubernetes `SubjectAccessReview` API, which the apiserver caches (default `authorization.authorizedTTL: 5m`, `unauthorizedTTL: 30s`). Negative-RBAC tests like:
```bash
# tenant-a tries to access tenant-b's namespace
kubectl --kubeconfig tenant-a.kubeconfig auth can-i get pods -n tenant-b
```
expect a deterministic `no` output. **But:** if the test was just preceded by a permission grant (or a tenant SA recreation), a stale cache entry can return `yes`. Or more commonly: a tenant policy *change* happens but SARs against the old policy state still answer based on the cache.

**Why it's likely in THIS lab:**
- The Phase 12 validation suite is meant to be a deterministic gate. Flakes erode trust in the POC results.
- Capsule's webhook DOES NOT directly affect SAR cache — but Capsule changes RoleBindings dynamically when tenant owners change, which is exactly the lifecycle the cache resists.
- The bats test idiom for negative RBAC is `kubectl auth can-i ... | grep -q '^no$'` — that grep silently passes when the apiserver returns `yes` (false negative).

**Detection signal:**
- Same test run twice within 30s shows different results.
- A new tenant SA shows access granted/denied that doesn't match the policy.

**Prevention:**
1. **Use `--fail-empty` style strictness:** assert exact-text output, exit code, AND verify against multiple probes:
   ```bash
   out=$(kubectl --kubeconfig tenant-a.kubeconfig auth can-i get pods -n tenant-b 2>&1)
   echo "$out" | grep -qx "no"  # exact match for "no" — not "no\nWarning..."
   ```
2. **Augment SAR with a real `kubectl get` probe** — the actual apply path is the more reliable negative test:
   ```bash
   ! kubectl --kubeconfig tenant-a.kubeconfig get pods -n tenant-b 2>/dev/null
   # Should return non-zero with "Forbidden" message
   ```
3. **Sleep tactically: 35s + retry on flake.** Less elegant than fixing the cache, but bounded. Document as POC-validity tradeoff.
4. **Test against capsule-proxy first:** the proxy filters API responses before the apiserver SAR cache is consulted. A negative test against `kubectl --kubeconfig tenant-a-via-proxy get namespaces` should not list `tenant-b` namespaces — that's a proxy-level filter, not a SAR-cache-affected RBAC grant. This is more reliable for tenant-isolation negative tests.
5. **Use Capsule's logs as a tertiary signal:** `kubectl --context spoke-capsule logs -n capsule-system deploy/capsule-controller-manager` should record the rejection.

**Phase to address:** Phase 12 (Validation) — designs the negative-RBAC bats with multi-probe assertions; Phase 10 (tenants) — supplies tenant SAs and namespaces in a way that supports proxy-level filtering tests.

---

### P38: Capsule v0.12 + k3s v1.34.6 version-skew — Capsule explicitly requires Kubernetes >=1.34.0; older Capsule lines won't work

**What goes wrong:** Capsule v0.12.x line (Dec 2025) explicitly bumped its Kubernetes API floor to `>=1.34.0`. Older Capsule releases (v0.11.x and earlier) targeted Kubernetes <=1.33 and may use deprecated API versions (`admissionregistration.k8s.io/v1beta1`, etc.) that don't exist in 1.34+. Picking a "stable enough" older Capsule (e.g., `v0.7.x` from a tutorial) will fail to install on k3s `v1.34.6-k3s1`. Symptom: Helm install errors with `unknown apiVersion` or webhooks fail to register.

**Why it's likely in THIS lab:**
- Most Capsule tutorials online (including the projectcapsule.dev "Use FluxCD" guide) use unspecified versions or older lines. Cargo-culting from a tutorial pins an older chart.
- v0.18 ADR-005 pins k3s to v1.34.6 specifically — Capsule must match.

**Detection signal:**
- HelmRelease status: `chart version 0.x.x failed: unknown field "matchPolicy"` or similar API version error.
- `helm template` rendered output references `admissionregistration.k8s.io/v1beta1`.

**Prevention:**
1. **Pin Capsule to v0.12.4 (or latest v0.12.x)** in the HelmRelease:
   ```yaml
   spec:
     chart:
       spec:
         chart: capsule
         version: 0.12.4
         sourceRef:
           kind: HelmRepository
           name: projectcapsule
   ```
2. **Pin the HelmRepository url:** `https://projectcapsule.github.io/charts`.
3. **Add the version pin to the v0.19 STACK.md** (if it exists; otherwise, document in `docs/poc-capsule.md` and a Decision in PROJECT.md's Key Decisions table).
4. **CI: kubeconform validates the rendered HelmRelease output against k8s 1.34 schema.** v0.18's Phase 6 already runs kubeconform; ensure the v0.19 HelmRelease + Tenant CRs are in scope.

**Phase to address:** Phase 9 (Capsule install) — owns the HelmRelease version pin; Phase 12 (Validation) — owns kubeconform extension.

---

### P39: Tenant kubeconfig server URL hard-coded to `127.0.0.1:30443` doesn't survive a port collision (or another k3d cluster takes 30443)

**What goes wrong:** P28 prevention picks `127.0.0.1:30443` for capsule-proxy NodePort. v0.18 already publishes `127.0.0.1:6443` (hub-flux apiserver), `:6444` (spoke-ml), `:6445` (spoke-apps). A future POC adds another NodePort / api-port; if it lands on `:30443` first, capsule-proxy's k3d publish fails OR worse: the proxy starts on a different port silently, and the hard-coded tenant kubeconfig stops working.

**Why it's likely in THIS lab:**
- WSL2 host has a finite port range. v0.18 already documents 3 host-port mappings.
- Future POCs (v0.20 vcluster? v0.21 something else?) will compete for ports.
- The "obvious" tenant kubeconfig has a bare `https://127.0.0.1:30443` literal.

**Detection signal:**
- `task preflight` reserved-port check (PRE-13 in v0.18) doesn't yet know about 30443.
- `ss -lntp | grep 30443` from the WSL2 host before/after k3d cluster create.

**Prevention:**
1. **Extend `task preflight` PRE-13 to include `30443` (or whatever Phase 8 chooses).** v0.18 already has port reservation logic; one-line addition.
2. **Generate the tenant kubeconfig from a template** keyed on `KARYON_POC_CAPSULE_PROXY_PORT` env var (defaults to 30443). The `proxy-kubeconfig-generator` invocation script reads it. Tenant kubeconfigs become rebuildable if the port changes.
3. **Document the reserved-port table** in `docs/architecture.md` (v0.18) — append `30443` to the v0.19 row.

**Phase to address:** Phase 7 (POC Onboarding Seam) — preflight extension; Phase 11 (kubeconfig generator) — env-var templating.

---

### P40: Spoke-capsule kubeconfig Secret on hub uses `value.yaml` key (per v0.18 P18 contract) but Capsule guides use unrelated key names → confused copy-paste

**What goes wrong:** v0.18 P18 + Phase 4 D-02 mandates `key: value.yaml` for `spec.kubeConfig.secretRef`. Capsule's own GitOps tutorials show `key: kubeconfig` or `key: config`. Copy-pasting from Capsule docs into our hub Kustomization breaks v0.18's invariant — the Secret-key mismatch then triggers the **silent in-cluster fallback** documented in v0.18 P18 (kustomize-controller falls back to its in-cluster ServiceAccount and reconciles into the *hub*, depositing tenant-shaped manifests into hub-flux instead of spoke-capsule).

**Why it's likely in THIS lab:**
- The POC plan author is reading both v0.18 PITFALLS.md AND projectcapsule.dev tutorials at the same time. Copy-paste is the direct path.
- v0.18 P18 was a hard-won lesson — the v0.19 POC is the first multi-cluster-Flux work since v0.18 closed.

**Detection signal:**
- bats: `tests/bats/poc-capsule-kubeconfig-key.bats` greps every `clusters/hub-flux/pocs/capsule/**/kustomization.yaml` and `clusters/hub-flux/pocs/capsule/**.yaml` for `secretRef.key` and asserts `value.yaml`.
- Live: hub Kustomization status `inventory` lists hub node names instead of spoke node names — same probe as v0.18 P18.

**Prevention:**
1. **Inherit the v0.18 P18 invariant verbatim**: `secretRef.key: value.yaml` AND the entire `spec.kubeConfig` block must be present (defense-in-depth — omitting `spec.kubeConfig` triggers the silent fallback even if the Secret has the right key).
2. **Document inheritance** in `docs/poc-capsule.md`: "v0.18 P18 invariant applies: `key: value.yaml` + full `spec.kubeConfig` block."
3. **Re-use the same bats pattern** as Phase 4 v0.18 (`tests/bats/spoke-registration-04-static.bats`) — extend with the v0.19 paths.

**Phase to address:** Phase 9 / Phase 10 — every hub Kustomization YAML; Phase 12 (Validation) — extends the v0.18 P18 bats pattern.

---

## Minor Pitfalls

### P41: Graduation ADR (ADR-006) skipped or postponed — POC drifts into "live but unblessed" tech debt

**What goes wrong:** v0.19 PROJECT.md explicitly says: "Close with an explicit graduation ADR (adopt / defer / reject / another POC)." If the POC works and there's pressure to move on, the ADR can slip. Without it, the POC is in a permanent half-life — neither in v1 nor explicitly rejected — accumulating maintenance cost.

**Prevention:** Phase 12 acceptance criterion is `docs/adr/006-capsule-graduation.md` exists with Status: one of {Accepted (adopt), Accepted (defer), Accepted (reject), Accepted (replaced by ADR-007 - another POC)}. ADR template inherits from the Nygard 4-section pattern used in v0.18 ADRs 001–005.

**Phase to address:** Phase 12 (Validation + graduation ADR).

---

### P42: Tenant SA on spoke-capsule has no expiry on its bearer token (v0.18 Pattern 3 inheritance) — POC simulates "real users" with cluster-resident long-lived tokens

**What goes wrong:** v0.18 ARCHITECTURE.md Pattern 3 uses legacy `kubernetes.io/service-account-token` Secrets for cluster-admin SA tokens — non-expiring, correct for a hub→spoke reconcile path. **But v0.19's tenant kubeconfig** is meant to simulate a developer accessing the cluster — for which short-lived tokens (TokenRequest, OIDC, etc.) are the production-correct path. The POC will use the v0.18 pattern (long-lived legacy tokens) for simplicity. **Document this as a POC simplification, not a recommendation.**

**Prevention:** Document in ADR-006's "Trade-offs" section: "POC uses long-lived legacy tokens for tenant kubeconfigs; production deployment requires OIDC or short-lived TokenRequest tokens, deferred to v0.20+." PROJECT.md v0.19 Out-of-Scope already names this: "OIDC tenant authentication — token-based for the Capsule POC; OIDC issuer / dex / keycloak deferred to a later milestone."

**Phase to address:** Phase 11 (kubeconfig) + Phase 12 (graduation ADR).

---

### P43: Capsule's NetworkPolicy auto-creation is too permissive / too restrictive depending on default values

**What goes wrong:** Capsule auto-creates a NetworkPolicy in each tenant namespace based on `Tenant.spec.networkPolicies` (or chart defaults if unset). Default Capsule configurations vary across versions — v0.12 may default to no NetworkPolicy or a default-deny + intra-tenant-allow shape. Incorrect default means either (a) tenant-A pods can reach tenant-B pods (if no NP), or (b) tenant-A pods can't reach their own services (if NP is too aggressive).

**Prevention:** Phase 10 explicitly sets `Tenant.spec.networkPolicies` to `[]` for the POC (no policy enforced) OR to a documented allow-intra-tenant + deny-cross-tenant shape. Either choice is valid; document in `docs/poc-capsule.md`. v0.19 is not testing network isolation — focus on RBAC isolation.

**Phase to address:** Phase 10 (tenants).

---

## Pitfalls That DO NOT Apply

These are pitfalls the planner should NOT spend research/planning effort on, because v0.18 design choices already mitigate them or remove the failure surface entirely.

| Pitfall (typically researched for new Capsule deployments) | Why it doesn't apply in v0.19 karyon |
|---|---|
| **ArgoCD ApplicationSet cluster-generator pitfalls (e.g., generator scope explosion, label-selector drift across clusters)** | v0.18 ADR-003 commits to Flux. Not using ArgoCD. |
| **Single-cluster Capsule mode** with hub-resident Capsule webhook intercepting Flux's own apply traffic — webhook recursion / chicken-and-egg loop | v0.19 explicitly puts Capsule on a *separate* spoke (`spoke-capsule`), not on hub-flux. PROJECT.md v0.19 Out-of-Scope: "Capsule installed on hub-flux itself — POC validates spoke-side multi-tenancy first; hub-side Capsule deferred." |
| **TokenRequest-based tenant kubeconfigs that expire mid-test → flaky CI** | v0.19 inherits v0.18 Pattern 3: long-lived legacy `kubernetes.io/service-account-token` Secrets. POC simplification per P42. |
| **`networkingMode=mirrored` Docker bridge breakage** | v0.18 P1 and Phase 1 PRE-14 already validated NAT-mode + the documented mirrored-mode fallback. v0.19 inherits the same WSL2 networking contract; no new mitigation needed. |
| **Docker Desktop conflict with native Docker Engine** | v0.18 ADR-001 + Phase 1 PRE-08 fail-gate. v0.19 uses the same host. |
| **CUDA build-cache wiped during `task destroy`** | v0.18 D-14 prune prohibition + the literal `INTENTIONALLY NOT calling docker (system\|builder\|image\|volume) prune` comment + Phase 6 prune-lint-bats CI job. v0.19 POC clusters do NOT use the CUDA image (Capsule operator + capsule-proxy are stock images). The POC's own destroy script must inherit the same prune prohibition for symmetry. |
| **gitleaks false-negative on ASCII-armored age/SOPS keys** | v0.19 explicitly does NOT introduce real secret management (PROJECT.md v0.19 Out-of-Scope). Tenant kubeconfigs are placeholder-style; no age keys. |
| **ApplicationSet cluster-generator label-selector drift across spoke kubeconfigs** | Flux only. N/A. |
| **Multi-spoke tenant federation (tenant spans spoke-apps + spoke-ml + spoke-capsule)** | PROJECT.md v0.19 Out-of-Scope. |
| **Generic "ephemeral cluster factory"** that spawns short-lived spokes for tenant tests | PROJECT.md v0.19 Out-of-Scope: "spoke-capsule is hand-rolled and persistent for the POC; a parameterized 'spawn ephemeral spoke' factory is future work." |
| **Production ingress + cert-manager + LetsEncrypt for capsule-proxy** | PROJECT.md v0.19 Out-of-Scope. NodePort + skip-tls-verify for POC (P28, P33). |
| **OIDC issuer setup (Dex, Keycloak)** | PROJECT.md v0.19 Out-of-Scope. Bearer-token kubeconfigs for POC. |
| **Default platform adoption of Capsule** | PROJECT.md v0.19 Out-of-Scope: "Capsule stays outside `task rebuild` until a graduation ADR explicitly adopts it." Specifically prevented by P31. |
| **`spec.kubeConfig` Secret key default-name confusion** (Flux v1 supports both `value` and `value.yaml`) | v0.18 P18 already locks this to `value.yaml`. v0.19 inherits — see P40 above for the inheritance assertion bats. |
| **Hub→spoke TLS SAN missing** for spoke-capsule's apiserver | Inherited mitigation: Phase 8 `k3d cluster create spoke-capsule` MUST include `--k3s-arg '--tls-san=k3d-spoke-capsule-server-0@server:*'` (same shape as v0.18 P6). The pitfall itself is v0.18 P6; the v0.19 risk is only forgetting to extend the existing pattern. **No new pitfall — flag during Phase 8 plan review.** |
| **WSL2 clock drift after hibernate breaks bearer-token validation** | v0.18 P4 + hwclock systemd unit. Tenant tokens here are non-expiring (P42), so clock drift doesn't expire them; the underlying clock-skew mitigation is shared with v0.18. |
| **systemd-resolved 127.0.0.53 leaks into Capsule pods** | v0.18 P16 + install-docker.sh explicit DNS in `/etc/docker/daemon.json`. v0.19 inherits. |
| **`docker.io` rate limit during parallel cluster + image pull** | v0.18 P20. Capsule operator image is small + cached after first pull; not a new risk. |
| **k3s auto-runtime + hand-rolled containerd config collision** | v0.18 P25, only relevant to spoke-ml's CUDA image. spoke-capsule uses stock `rancher/k3s:v1.34.6-k3s1`. |
| **k3d v5.8.3 NodeHosts staleness** | v0.18 P11 + `task fix-dns`. v0.19 P35 extends the same pattern to spoke-capsule. |

---

## Recovery Strategies

For each Critical pitfall, the recovery cost and steps if prevention fails:

| Pitfall | Recovery cost | Recovery steps |
|---|---|---|
| P26 Webhook failurePolicy=Fail blocks reconcile | LOW | `kubectl --context spoke-capsule patch validatingwebhookconfiguration capsule-validating-webhook --type=json -p '[{"op":"replace","path":"/webhooks/0/failurePolicy","value":"Ignore"}]'` (and same for mutating). Re-trigger Flux reconcile. |
| P27 Tenant escape via Flux | HIGH | (1) Suspend the offending Flux Kustomization. (2) Audit what got created on the spoke (`kubectl get all -A --selector=...`). (3) Manually clean up out-of-tenant resources. (4) Add `spec.serviceAccountName` to the Kustomization. (5) Re-resume. (6) Run negative-RBAC bats to confirm escape closed. |
| P28 capsule-proxy ClusterIP unreachable | LOW | Patch capsule-proxy Service to NodePort, regenerate tenant kubeconfig. |
| P29 Tenant kubeconfig leaked to public repo | HIGHEST | (1) Rotate the tenant SA token immediately (`kubectl --context spoke-capsule -n <tenant-ns> delete secret <token-secret>` — k8s recreates with a new token). (2) Force-push history rewrite on the leaked file (`git filter-repo --path <leak-path> --invert-paths`) — coordinate with all clones. (3) Audit access logs on spoke-capsule for unauthorized API calls during the leak window. (4) Add `tests/bats/v0.19-public-repo.bats` to prevent recurrence. |
| P30 Sentinel collision | MEDIUM | Disambiguate sentinels manually, re-run idempotent register-poc.sh / register-spokes.sh, verify bats green. |
| P31 spoke-capsule pulled into `task rebuild` | LOW | Revert offending diff. Worth double-checking via `task rebuild` timing regression (must stay < 230s). |
| P32 CRDs not present when Tenants apply | LOW | Wait 60s, retry `flux reconcile kustomization capsule-tenants`. Add `dependsOn` to permanent fix. |
| P33 capsule-proxy TLS cert SANs missing 127.0.0.1 | LOW | Add `insecure-skip-tls-verify: true` to tenant kubeconfig as immediate POC unblock; permanent fix is Helm values + cert-manager / certgen reconfig + chart upgrade. |
| P34 cert-manager dependency unsatisfied | LOW | Choose certgen mode (`certManager.generateCertificates=false`, `tls.create=true`); re-reconcile. |

---

## Phase-mapping matrix

How v0.19 phases address each pitfall:

| Pitfall | Phase 7 (POC Seam) | Phase 8 (spoke-capsule) | Phase 9 (Capsule install) | Phase 10 (Tenants + lockdown) | Phase 11 (Tenant kubeconfig) | Phase 12 (Validation + ADR-006) |
|---|---|---|---|---|---|---|
| P26 Webhook failurePolicy | | | ✓ values | | | ✓ recovery probe |
| P27 Tenant escape via Flux | | | | ✓ static bats | | ✓ live negative-RBAC |
| P28 capsule-proxy NodePort | | ✓ k3d port publish | ✓ Helm values | | ✓ kubeconfig server | |
| P29 Tenant kubeconfig leak | ✓ .gitignore + .gitleaks.toml | | | | ✓ generator output path | ✓ history scan + bats |
| P30 KARYON POC MOUNT sentinel | ✓ register-poc.sh + bats | | | | | |
| P31 POC isolation from rebuild | ✓ scripts/poc/ structure + bats | ✓ dedicated create script | | | | ✓ rebuild SLO regression |
| P32 CRD ordering | | | ✓ dependsOn chain | ✓ wait: true | | ✓ live CRD-presence bats |
| P33 capsule-proxy TLS SANs | | | ✓ Helm values | | ✓ skip-verify decision | ✓ openssl bats |
| P34 cert-manager dependency | | | ✓ certgen-vs-cert-manager decision | | | ✓ live cert-source probe |
| P35 spoke-capsule CoreDNS staleness | | ✓ task fix-dns-poc-capsule | | | | |
| P36 Tenant teardown orphans | | | | | | ✓ teardown ordering bats |
| P37 SAR cache flake | | | | | | ✓ multi-probe negative bats |
| P38 Capsule v0.12 + k3s 1.34.6 pin | | | ✓ HelmRelease version pin | | | ✓ kubeconform |
| P39 Tenant kubeconfig port hard-code | ✓ preflight reserved-port | | | | ✓ env-var templating | |
| P40 Inherit v0.18 P18 (value.yaml) | | | ✓ hub Kustomization | ✓ hub Kustomization | | ✓ extend v0.18 P18 bats |
| P41 ADR-006 graduation | | | | | | ✓ acceptance criterion |
| P42 Long-lived tenant tokens | | | | | ✓ POC simplification | ✓ ADR-006 trade-off note |
| P43 Capsule NetworkPolicy default | | | | ✓ Tenant.spec.networkPolicies | | |

---

## Sources

### Tier 1 — Authoritative (HIGH confidence)
- [Flux Kustomization spec v1 — kubeConfig + serviceAccountName interaction](https://fluxcd.io/flux/components/kustomize/kustomizations/) — definitive on remote-cluster impersonation; `--default-service-account` does NOT apply when `spec.kubeConfig` is set; ServiceAccount must exist on the *target* cluster
- [Flux multi-tenancy lockdown configuration](https://fluxcd.io/flux/installation/configuration/multitenancy/) — `--no-cross-namespace-refs`, `--no-remote-bases`, `--default-service-account`
- [fluxcd/flux2-multi-tenancy](https://github.com/fluxcd/flux2-multi-tenancy) — canonical Flux multi-tenancy reference
- [Capsule Installation Guide](https://projectcapsule.dev/docs/operating/setup/installation/) — Helm values + webhook configuration
- [Capsule Use FluxCD Guide](https://projectcapsule.dev/docs/guides/use-fluxcd/) — the canonical Capsule + Flux integration pattern; ServiceAccount impersonation flow
- [Capsule Proxy Installation](https://projectcapsule.dev/docs/proxy/installation/) — exposure modes (Ingress/NodePort/LB/HostPort/HostNetwork); client-cert vs token authentication; CA Secret default location
- [Capsule v0.12 Releases](https://github.com/projectcapsule/capsule/releases) — v0.12.x line bumped K8s API floor to >=1.34.0; latest patch v0.12.4 (2025-12-19)
- [Capsule MutatingWebhookConfiguration template](https://github.com/projectcapsule/capsule/blob/main/charts/capsule/templates/mutatingwebhookconfiguration.yaml) — failurePolicy, resource scopes (Pods/PVCs/Ingress/Gateway/Namespace/ResourcePool/Tenant)
- [clastix/flux2-capsule-multi-tenancy ARCHITECTURE.md](https://github.com/clastix/flux2-capsule-multi-tenancy/blob/main/docs/ARCHITECTURE.md) — proxy-kubeconfig-generator workflow; Tenant GitOps Reconciler ServiceAccount lives in its OWN namespace, not in tenant namespaces; impersonation flow
- [Kubernetes Admission Webhook Good Practices](https://kubernetes.io/docs/concepts/cluster-administration/admission-webhooks-good-practices/) — failurePolicy=Ignore guidance for non-critical-path webhooks
- [Kubernetes Authorization — SubjectAccessReview cache TTLs](https://kubernetes.io/docs/reference/access-authn-authz/authorization/) — `authorizedTTL: 5m`, `unauthorizedTTL: 30s` defaults

### Tier 2 — Primary issue trackers (MEDIUM confidence)
- [Flux issue #5543 — Allow impersonating service accounts in arbitrary namespace on remote clusters](https://github.com/fluxcd/flux2/issues/5543) — confirms current SA-namespace-must-match-Kustomization-namespace constraint
- [Flux issue #5465 — RFC-0010 Full multi-tenancy lockdown support](https://github.com/fluxcd/flux2/issues/5465)
- [Capsule issue #1360 — Capsule upgrade in FluxCD failing due to missing certgen Job](https://github.com/projectcapsule/capsule/issues/1360) — concrete cert-source choice trade-offs
- [Capsule issue #1292 — Cluster admin actions intercepted as tenant owner / cluster level create blocked](https://github.com/projectcapsule/capsule/issues/1292) — webhook scope confirmation
- [Capsule issue #424 — Tenant owner cannot impersonate namespace admin](https://github.com/projectcapsule/capsule/issues/424)
- [k3d issue #1009 — CoreDNS NodeHosts lost after adding a new node](https://github.com/k3d-io/k3d/issues/1009) — same root cause for spoke-capsule as v0.18 hub-flux
- [k3d issue #1112 — coredns looses customization after cluster or docker restart](https://github.com/k3d-io/k3d/issues/1112)

### Tier 3 — Tutorial / commentary (LOW individually, MEDIUM in aggregate)
- [How to operate Tenants GitOps with Flux | Capsule docs](https://projectcapsule.dev/docs/guides/use-fluxcd/) (re-listed for tutorial context)
- [TomTom Engineering — Kubernetes multi-tenancy with Capsule](https://engineering.tomtom.com/capsule-kubernetes-multitenancy/)
- [DZone — Implementing EKS Multi-Tenancy Using Capsule (Part 1)](https://dzone.com/articles/implementing-eks-multi-tenancy-using-capsule)
- [How to Use Capsule with Flux CD for Multi-Tenancy (oneuptime)](https://oneuptime.com/blog/post/2026-03-05-capsule-flux-cd-multi-tenancy/view)
- [How to Restrict Cross-Namespace References in Flux (oneuptime)](https://oneuptime.com/blog/post/2026-03-05-restrict-cross-namespace-references-flux/view)

### Inherited from v0.18 research (HIGH confidence — already validated in v0.18 ship)
- v0.18 PITFALLS.md P6 (`--tls-san` at cluster create), P11 (CoreDNS NodeHosts staleness), P14 (asdf PATH), P16 (systemd-resolved), P18 (`spec.kubeConfig` key + omitted-block silent fallback), P25 (containerd auto-runtime collision)
- v0.18 ARCHITECTURE.md Pattern 3 (legacy Secret-backed SA tokens) — adopted as v0.19 default for tenant kubeconfigs (with the explicit POC-simplification caveat in P42)
- v0.18 STACK.md k3s pin (`v1.34.6-k3s1`), Flux pin (`v2.8.6`), kubectl pin (`v1.34.7`), helm pin (`v3.20.2`)
- v0.18 Phase 4 D-02 sentinel pattern (`# KARYON SPOKES MOUNT`) — extended in P30 to disambiguate `# KARYON POC MOUNT — capsule`
- v0.18 Phase 6 D-16 gitignore expansion + .gitleaks.toml + 5-layer secrets defense — extended in P29 with kubeconfig-shape gitleaks rule + tenant directory globs

---
*Pitfalls research for: Capsule Multi-Tenancy POC on existing hub-only Flux k3d lab (karyon v0.19)*
*Researched: 2026-04-29*
*Numbering continues from v0.18 PITFALLS.md (closed at P25); archived at .planning/milestones/v0.18-research/PITFALLS.md*
