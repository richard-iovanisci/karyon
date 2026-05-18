# Phase 11: Validation + Graduation ADR-008 - Context

**Gathered:** 2026-05-05
**Status:** Ready for planning

<domain>
## Phase Boundary

Empirical bats evidence proves Capsule's tenant boundary holds (negative RBAC + webhook failure + clean teardown), the v0.18 `task rebuild` SLO is unchanged, and the closing graduation ADR-008 records the adopt/defer/reject/replaced decision backed by the bats evidence. **This is the closing phase of milestone v0.19** — it converts everything Phases 7-10 shipped into the decision artifact for v0.20+.

Phase 11 succeeds when:

1. **VAL-01** — All 12 negative RBAC bats falsifiers (N1-N12 per ROADMAP success criterion #1, verbatim) PASS, where the ROADMAP mapping is:
   - N1: cross-tenant pod read denied
   - N2: cluster-wide LIST filtered to own tenant
   - N3: cross-tenant secret read denied
   - N4: ClusterRoleBinding escalation denied
   - N5: namespace prefix violation denied
   - N6: tenant quota violation denied
   - N7: denied registry pull denied
   - N8: direct-apiserver bypass on `:6446` denied or limited
   - N9: cross-tenant `sourceRef` in tenant Kustomization denied
   - N10: missing `spec.serviceAccountName` denied/falls through
   - N11: workload create rejected when capsule-controller is down
   - N12: workload create succeeds again after operator recovers
2. **VAL-02** — Capsule webhook failure mode observed and recoverable. `task fail-capsule-webhook -- 0` rejects tenant pod create; `task fail-capsule-webhook -- 1` recovers; both halves bats-asserted.
3. **VAL-03** — `task destroy-poc -- capsule` performs ordered teardown; `# KARYON POC MOUNT` sentinel + `clusters/hub-flux/pocs/` mount remain verbatim post-teardown; no `capsule.clastix.io/tenant=<name>` labeled objects remain.
4. **VAL-04** — `task rebuild` SLO regression test PASSES: total time < 230s; `k3d-spoke-capsule-server-0` container ID unchanged across rebuild; zero `spoke-capsule` mentions in v0.18 script set (P31 inheritance verbatim).
5. **VAL-05** — One-shot history gitleaks scan post-Phase-10 first-push event returns 0 findings. **Phase 8 D-08-13 + Phase 9 + Phase 10 push-gate-deferral resolves HERE.**
6. **VAL-06** — ADR-008 graduation written with `Status: Accepted` and outcome ∈ {adopt, defer, reject, replaced by ADR-009}, sectioned per Nygard 4-section template plus explicit "What we proved / What we did not prove / Trade-offs" sub-sections backed by bats references; rolls `docs/capsule-on-eks.md` (EKSDOC-01) from `Status: Draft` to `Status: Reviewed` with corrections informed by the bats evidence.

**Phase 11 ships the closing validation + ADR ONLY.** The following are explicitly **out of scope** for Phase 11 (each owned by a later phase or absorbed organically):

- **`capsule-addon-fluxcd v0.2.3` Trial** → **Phase 12 (OPTIONAL — gated)**. Phase 12 only runs if ADR-008 outcome ∈ {adopt, defer}; if reject or replaced, Phase 12 is SKIPPED.
- **Tenant inner K kubeConfig source swap from `spoke-capsule-kubeconfig` to per-tenant proxy-kubeconfigs** (Phase 9 D-09-03 forward-pointer; Phase 10 D-10-05 deferred) → **Phase 12** (capsule-addon-fluxcd absorbs organically) OR future work post-v0.19 if Capsule is rejected/replaced.
- HA Capsule, OIDC, multi-spoke federation → POST-v0.19 milestones (REQUIREMENTS.md "Future Requirements" + PROJECT.md Out-of-Scope).

</domain>

<decisions>
## Implementation Decisions

### Push-gate carryover + first push event (VAL-05 + Phase 10 carryover)

#### capsule-proxy chart-level RBAC patch persistence (D-11-01)

- **D-11-01:** **PostBuild patch on the outer K** — `clusters/hub-flux/pocs/capsule.yaml`. Add a `spec.patches` (or `spec.postBuild.substituteFrom` equivalent) block that extends the chart-rendered Role `capsule-proxy:capsule-proxy` in `capsule-system` namespace with `[secrets get/create/update/patch]` rules so the `kube-webhook-certgen` Job can write its output Secret on initial Flux reconcile.
  - **Rationale:** Lives at the hub-side outer-K boundary (consistent with Phase 9 D-09-05 lockdown patch surface — same FLUX PATCH SURFACE pattern); single canonical surface for Phase 10 → Phase 11 push-gate fixes; survives Flux reconciliation; declarative.
  - **Plan 10-01 in-place patch context:** Plan 10-01 staged via `kubectl patch role capsule-proxy:capsule-proxy --type='json' -p='[{"op":"add","path":"/rules/-","value":{"apiGroups":[""],"resources":["secrets"],"verbs":["get","create","update","patch"]}}]'`. The PostBuild patch carries the equivalent rule additions into the Flux-managed reconcile path.
  - **Bats assertion:** Static — `bats tests/bats/push-gate-01-static-rbac-postbuild.bats` greps `clusters/hub-flux/pocs/capsule.yaml` for the Role-extending patch literal. Live — re-run Phase 10 `proxy-04-live-issue.bats` (kubeconfig issuance) post-first-push to confirm cert-secret materializes via Flux reconcile, NOT via Plan 10-01 imperative `helm install` artifact.

#### CapsuleConfiguration `userGroups` patch persistence (D-11-02)

- **D-11-02:** **Update repo file directly** — edit `pocs/capsule/spoke/config/capsuleconfig.yaml` to inline `spec.userGroups: [capsule.clastix.io, system:serviceaccounts, system:authenticated]` (the canonical 3-group set Plan 10-02 patched live).
  - **Rationale:** CapsuleConfiguration is a Capsule-owned default singleton (per D-09-04); the repo file IS the canonical source. Single source of truth — reads exactly like the live cluster state. Matches D-09-04 framing. Zero patch indirection.
  - **Plan 10-02 in-cluster patch context:** Plan 10-02 patched the live CapsuleConfiguration with the 3-group userGroups list to make proxy LIST recognize SA-token-authenticated identities as Capsule-owned. The repo update carries this into the GitOps source.
  - **Bats assertion:** Static — `bats tests/bats/push-gate-02-static-capsuleconfig.bats` greps `pocs/capsule/spoke/config/capsuleconfig.yaml` for the 3-group userGroups list verbatim (or yq path-extract assertion). Live — re-run Phase 10 `proxy-05-live-list-filter.bats` post-first-push to confirm proxy LIST behavior survives the Flux-managed CapsuleConfiguration apply (no in-cluster patch needed).

#### Tenant home namespace ownership label (D-11-03)

- **D-11-03:** **Add label inline to namespace YAML** — edit `pocs/capsule/spoke/tenants/{alpha,bravo}/namespace.yaml` to include `metadata.labels.capsule.clastix.io/tenant: <name>`. Trust that the cluster-admin Flux apply path bypasses Capsule's webhook prefix-violation check (Capsule's webhook exempts cluster-admin / kube-system identities — the documented Phase 9 P27 exemption applies to Flux's `flux-reconciler` SA on spoke-capsule per ADR-004 + Phase 9 D-09-03 transitional kubeConfig).
  - **Rationale:** Zero operator intervention; YAML-as-source-of-truth; first push reconciles cleanly. Plan 10-02 used `--as=alpha/bravo` impersonation (operator runbook pattern) only because Plan 9 created namespaces via raw `kubectl apply`, not via Flux. Phase 11 fixes this by labeling at apply time.
  - **Falsifier bats (Plan 11-XX RED scaffold):** `bats tests/bats/push-gate-03-static-tenant-ns-label.bats` static-asserts the label key+value in both namespace.yaml files; `push-gate-04-live-tenant-ns-flux-apply.bats` live-asserts that after first push, `kubectl get ns tenant-alpha -o jsonpath='{.metadata.labels.capsule\.clastix\.io/tenant}'` returns `alpha` (and same for bravo). If the webhook DOES reject the cluster-admin Flux apply (assumption invalidated), this falsifier fires fast and forces an escalation to operator-runbook fallback (D-11-03 fallback documented in PLAN.md, NOT here).
  - **Plan 10-02 cluster state context:** Plan 10-02 currently has `tenant-alpha` and `tenant-bravo` recreated as Capsule-owned via impersonation. Phase 11 first-push event will reconcile the YAML-driven label; the existing cluster state already satisfies the label (no destructive recreation needed during Phase 11 testing).

#### Gitleaks planning-doc allowlist (D-11-04 — folded todo)

- **D-11-04:** **Option C — broad path-allowlist for `.planning/*.md`** — append `'^\.planning/.*\.md$'` to `.gitleaks.toml` `[allowlist] paths` list (parallel to the existing `^\.env\.example$` block).
  - **Rationale:** Future-proof — any future phase whose planning docs reference fixture content (or quote kubeconfig examples) is auto-allowlisted; matches the existing `.env.example` precedent; planning docs aren't a real leak surface (real leaks would be in source/config files, not retrospective markdown). The trade-off (a real-shape kubeconfig in a planning doc would slip through) is mitigated by the fact that real kubeconfigs would never typically land in `.planning/` (they live in `${TMPDIR:-/tmp}/karyon-tenants/` per Phase 7 D-14 + Phase 10 D-10-09).
  - **Folded todo:** `2026-04-29-phase-7-gitleaks-planning-doc-allowlist.md` (resolves_phase: 11). The Phase 7 carryover is closed by this decision; planning docs in `.planning/phases/07-*/` (07-00-PLAN.md, 07-RESEARCH.md, 07-REVIEW.md) that quote the synthetic-kubeconfig fixture content are auto-allowlisted post-D-11-04.
  - **Bats assertion:** Static — `bats tests/bats/push-gate-05-static-gitleaks-allowlist.bats` greps `.gitleaks.toml` for the new path-allowlist literal. Live — `gitleaks detect --source . --no-git --redact` on the full working tree exits 0 (zero findings); `gitleaks git --log-opts="--all"` exits 0 (zero findings) post first push.

#### Push-event timing (Claude's Discretion within VAL-05)

- **Recommended pattern:** Push happens AFTER all VAL-01..04 bats are GREEN locally AND after the persistent-fix plans (D-11-01..03 + the imperative `helm install` artifact removal) have landed. This ensures the post-push Flux reconcile observes a clean state. Imperative `helm install`-staged capsule-proxy from Plan 10-01 is removed (`helm uninstall capsule-proxy -n capsule-system --kube-context=k3d-spoke-capsule`) BEFORE first push so the post-push reconcile is the canonical install path.
- **One-shot history gitleaks scan timing:** Run AFTER first push, on origin/main, with `--log-opts="--all"` and full-history fetch-depth: 0 (matches `.github/workflows/ci.yml` `gitleaks-scan` job).
- **Planner reshape freedom:** The planner may split the push event into its own plan (e.g., Plan 11-XX-push) or fold it into the verifier plan (Plan 11-final).

### Negative RBAC probe strategy (VAL-01)

#### Probe shape — real CRUD apply path (D-11-05)

- **D-11-05:** **Real CRUD apply path, single probe** — each Nk asserts the actual `kubectl get/create/...` against the tenant kubeconfig returns non-zero with a specific error string, NOT `kubectl auth can-i` (which queries the SubjectAccessReview API with a 5m authorizedTTL / 30s unauthorizedTTL cache that can return stale results — research P37).
  - **Per-N probe shape:**
    - N1 (cross-tenant pod read): `! kubectl --kubeconfig=alpha.kubeconfig get pods -n tenant-bravo 2>&1 | grep -q "Forbidden"` (real LIST denied)
    - N2 (cluster-wide LIST filtered): `kubectl --kubeconfig=alpha.kubeconfig get pods --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{"\n"}{end}' | sort -u` returns ONLY alpha-owned namespace prefixes (proxy LIST filter)
    - N3 (cross-tenant secret read): `! kubectl --kubeconfig=alpha.kubeconfig get secret -n tenant-bravo 2>&1 | grep -q "Forbidden"`
    - N4 (CRB escalation): `! kubectl --kubeconfig=alpha.kubeconfig create clusterrolebinding evil --clusterrole=cluster-admin --user=alpha 2>&1 | grep -q "forbidden"` (cluster-scope rights denied)
    - N5 (namespace prefix violation): `! kubectl --kubeconfig=alpha.kubeconfig create namespace evil 2>&1 | grep -q "prefix"` or `grep -q "forceTenantPrefix"` (Capsule webhook rejects)
    - N6 (quota violation): create `alpha-1`..`alpha-N+1` where N is `Tenant.spec.namespaceOptions.quota`; assert N+1th rejected with quota webhook message
    - N7 (registry violation): `! kubectl --kubeconfig=alpha.kubeconfig run x --image=docker.io/library/nginx -n alpha-app1 2>&1 | grep -q "registry"` (Capsule webhook rejects unallowed registry)
    - N8 (direct apiserver bypass): per D-11-08 below
    - N9 (cross-tenant sourceRef): apply a tenant-alpha Kustomization with `sourceRef.namespace: tenant-bravo`; assert Flux reports `cross-namespace-refs` denied (after kustomize-controller reconciles ~30s)
    - N10 (missing serviceAccountName): apply a tenant-alpha Kustomization without `spec.serviceAccountName`; assert Flux falls through to `--default-service-account: gitops-reconciler` impersonation OR rejects with RBAC denial (depending on which Capsule policy fires first)
    - N11 (webhook down rejection): `task fail-capsule-webhook -- 0`; `! kubectl --kubeconfig=alpha.kubeconfig run x -n alpha-app1 2>&1 | grep -q "admission webhook"` (apiserver webhook timeout or failure)
    - N12 (webhook recovery): `task fail-capsule-webhook -- 1`; poll until Deployment Ready; retry the apply; assert success (exit 0; pod scheduled)
  - **Rationale:** Bypasses SAR cache entirely (real apply path goes through validating webhooks AND apiserver auth in one shot); deterministic; matches research P37 prevention #2. Each Nk is a single probe — no multi-probe consensus overhead.
  - **Anti-pattern lint (Plan 11-00 Wave 0 bats):** `bats tests/bats/negative-rbac-anti-pattern-lint-static.bats` greps `tests/bats/negative-rbac-*.bats` for `kubectl auth can-i` and asserts ZERO matches (forbids the SAR-cache-flake-prone pattern in source files).

#### Bats file partition — grouped by attack class (D-11-06)

- **D-11-06:** **5 bats files** grouped by attack class (NOT one-per-N, NOT single-file):
  - `tests/bats/negative-rbac-01-cross-tenant-list.bats` — N1, N2, N3 (cross-tenant pod read, cluster-wide LIST filtered, cross-tenant secret read)
  - `tests/bats/negative-rbac-02-escalation.bats` — N4 (ClusterRoleBinding escalation)
  - `tests/bats/negative-rbac-03-webhook-policy.bats` — N5, N6, N7 (namespace prefix violation, quota violation, registry violation)
  - `tests/bats/negative-rbac-04-bypass-and-flux.bats` — N8, N9, N10 (direct apiserver bypass, cross-tenant sourceRef, missing serviceAccountName)
  - `tests/bats/negative-rbac-05-webhook-down.bats` — N11, N12 (capsule-controller scaled 0 → reject; scaled 1 → recover)
  - **Rationale:** Tests sharing setup() (e.g., minting tenant kubeconfigs, reading the proxy CA, constructing the direct-apiserver tmpfile kubeconfig for N8) co-locate. ~5 files keeps bats run fast. Failure isolation per attack class: if N6 quota fails, only the webhook-policy file goes RED; N1-N3 cross-tenant tests stay GREEN.
  - **Wave 0 RED scaffold:** Plan 11-00 lands all 5 files RED-by-design (the kubeconfigs don't exist yet at landing time; live-only @tests are gated by a runtime probe per D-09-08 / D-10-09 inheritance).

#### Tenant kubeconfig sourcing — `setup_file()` mint-once cache (D-11-07)

- **D-11-07:** **Mint once in `setup_file()` per bats file, cache to tmpdir** — each `negative-rbac-*.bats` file's `setup_file()` (runs once per file before all @tests) calls:
  ```bash
  setup_file() {
    export KARYON_BATS_TMPDIR="${TMPDIR:-/tmp}/karyon-tenants/bats-${BATS_RUN_TMPDIR##*/}"
    mkdir -p "$KARYON_BATS_TMPDIR"
    bash scripts/poc/capsule/issue-tenant-kubeconfig.sh alpha gitops-reconciler \
      --duration=2h --write-to "${KARYON_BATS_TMPDIR}/alpha.kubeconfig" >/dev/null
    bash scripts/poc/capsule/issue-tenant-kubeconfig.sh bravo gitops-reconciler \
      --duration=2h --write-to "${KARYON_BATS_TMPDIR}/bravo.kubeconfig" >/dev/null
    export ALPHA_KUBECONFIG="${KARYON_BATS_TMPDIR}/alpha.kubeconfig"
    export BRAVO_KUBECONFIG="${KARYON_BATS_TMPDIR}/bravo.kubeconfig"
  }
  teardown_file() { rm -rf "$KARYON_BATS_TMPDIR"; }
  ```
  - **Rationale:** One TokenRequest API call per bats file (~5 total across the suite); `--duration=2h` covers slow bats runs without re-minting (mid-run token expiry would cause confusing flakes); tmpdir-rooted (P29 invariant — kubeconfigs MUST NOT land in repo); per-file isolation prevents cross-file token sharing; bats `setup_file()`/`teardown_file()` is the canonical mechanism (bats v1.5+; Phase 7/8/9/10 already use it).

#### N8 direct-apiserver bypass falsifier — Phase 10 D-10-08 reuse (D-11-08)

- **D-11-08:** **Reuse Phase 10 D-10-08 falsifier pattern with Pitfall 10-P3 corrected shape.** `negative-rbac-04-bypass-and-flux.bats` `setup()` (per-test):
  1. Read `${ALPHA_KUBECONFIG}` from setup_file().
  2. Extract bearer token: `TOKEN=$(yq '.users[0].user.token' "$ALPHA_KUBECONFIG")`.
  3. Construct minimal direct-apiserver kubeconfig in `mktemp -d "${KARYON_BATS_TMPDIR}/direct-XXXX"`:
     ```yaml
     apiVersion: v1
     kind: Config
     clusters:
       - name: direct
         cluster:
           server: https://127.0.0.1:6446
           insecure-skip-tls-verify: true
     users:
       - name: gitops-reconciler
         user:
           token: <extracted bearer>
     contexts:
       - name: direct
         context:
           cluster: direct
           user: gitops-reconciler
     current-context: direct
     ```
  4. **Per Pitfall 10-P3 corrected falsifier:** assert `kubectl --kubeconfig=$DIRECT_KUBECONFIG get namespaces 2>&1` returns 403 + `"cannot list resource \"namespaces\""` error string (NOT a count comparison — Capsule's namespace-scoped RBAC denies cluster-wide LIST regardless).
  5. teardown() removes the direct-kubeconfig file.
  - **Rationale:** Phase 10 D-10-08 + Pitfall 10-P3 already validated this falsifier shape live (proxy-05 @test 1 GREEN). Phase 11 reuses verbatim. tmpdir-rooted; rejects qualitative output (403 + error string) NOT count comparison.

### Webhook failure + teardown (VAL-02 / VAL-03)

#### `task fail-capsule-webhook` mechanism — scale Deployment 0/1 (D-11-09)

- **D-11-09:** **Scale Deployment to 0 (fail) / 1 (recover)** via `scripts/poc/capsule/fail-capsule-webhook.sh`:
  ```bash
  #!/usr/bin/env bash
  set -euo pipefail
  REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
  source "${REPO_ROOT}/scripts/lib/preflight-lib.sh"
  REPLICAS="${1:-0}"
  [[ "$REPLICAS" =~ ^[01]$ ]] || fail "Usage: fail-capsule-webhook.sh [0|1]"
  kubectl --context=k3d-spoke-capsule scale deploy capsule-controller-manager \
    -n capsule-system --replicas="${REPLICAS}"
  if [[ "$REPLICAS" == "1" ]]; then
    kubectl --context=k3d-spoke-capsule rollout status deploy/capsule-controller-manager \
      -n capsule-system --timeout=90s
  fi
  ```
  Taskfile.yml entry: `task fail-capsule-webhook -- 0` / `task fail-capsule-webhook -- 1`.
  - **Rationale:** Exact research P26 / N12 mechanism; clean reversibility; matches ROADMAP VAL-02 wording verbatim ("scales operator to 0 then 1"); no PVC/manifest mutation. ~30-60s recovery wait per run is acceptable POC overhead.
  - **Bats sequencing (negative-rbac-05-webhook-down.bats):**
    - `setup_file()`: ensure capsule-controller-manager Ready=1 at start (idempotent precondition).
    - `@test "N11 — workload create rejected when capsule-controller down"`: invoke `task fail-capsule-webhook -- 0`; wait for Deployment Ready=0 (via rollout wait or pod count poll); attempt `kubectl --kubeconfig=$ALPHA_KUBECONFIG run probe --image=registry.example.io/probe -n alpha-app1`; assert non-zero exit + admission-webhook-error string; do NOT recover here (let setup_file or next @test handle).
    - `@test "N12 — workload create succeeds again after operator recovers"`: invoke `task fail-capsule-webhook -- 1`; poll until Deployment Ready=1 (rollout-status timeout 90s); retry the apply (idempotent — different probe pod name); assert exit 0 + pod scheduled.
    - `teardown_file()`: ensure capsule-controller-manager Ready=1 (cleanup safety net).

#### `task destroy-poc -- capsule` ordered teardown — strict 5-step canonical (D-11-10)

- **D-11-10:** **`scripts/poc/capsule/destroy-poc.sh`** runs the canonical 5-step sequence:
  1. `flux suspend kustomization tenant-alpha tenant-bravo poc-capsule-spoke -n flux-system` (suspend tenant inner Ks + the spoke-targeted outer K)
  2. `kubectl --context=k3d-spoke-capsule delete tenant alpha bravo --wait=true` (delete Tenant CRs; Capsule's controller cascades namespace deletion)
  3. **Poll** `kubectl --context=k3d-spoke-capsule get ns -l capsule.clastix.io/tenant= -o name` until empty (max 90s); if stuck >60s, **auto force-delete remaining PVCs** per D-11-11.
  4. `flux suspend kustomization poc-capsule poc-capsule-config -n flux-system` (suspend operator + config outer Ks; preserves the GitOps-managed install state without destroying it)
  5. **Optional `--full` flag:** `k3d cluster delete spoke-capsule` (destroys the cluster); WITHOUT `--full`, the cluster + Capsule operator remain alive but with all tenants gone.
  - **Sentinel preservation:** `# KARYON POC MOUNT` sentinel + `clusters/hub-flux/pocs/` mount stay verbatim post-teardown regardless of `--full` flag (the script does NOT modify `clusters/hub-flux/flux-system/kustomization.yaml`).
  - **Rationale:** Deterministic; matches research P36 + ROADMAP VAL-03 wording verbatim ("suspend tenant Kustomizations → delete Tenant CRs → wait for namespace cascade → optional `k3d cluster delete spoke-capsule`"); PVC strand mitigation built-in (D-11-11). Idempotent — re-running after a partial failure is safe (suspend-already-suspended is a no-op; delete-already-deleted is non-fatal with `|| true`).
  - **Taskfile entry:** `task destroy-poc -- capsule` invokes the script (variadic for future POCs); `task destroy-poc -- capsule --full` passes `--full` through to the script.
  - **Bats coverage (Plan 11-XX):**
    - `tests/bats/teardown-01-static-script.bats`: script shape (preflight-lib source, REPO_ROOT pinning, anti-patterns, etc.)
    - `tests/bats/teardown-02-static-sentinel-preservation.bats`: assert script does NOT mutate `clusters/hub-flux/flux-system/kustomization.yaml`
    - `tests/bats/teardown-03-live-ordered.bats`: live run; assert post-teardown no namespaces with `capsule.clastix.io/tenant=` label remain; assert sentinel + mount line still present in `clusters/hub-flux/flux-system/kustomization.yaml`
    - `tests/bats/teardown-04-live-pvc-strand-mitigation.bats`: gated synthetic test — apply a PVC in alpha-app1, run destroy, assert PVC force-deleted within 90s

#### PVC stranded handling — auto force-delete after 60s (D-11-11)

- **D-11-11:** **Auto force-delete PVCs after 60s timeout** per research P36 prevention #4. Inside step 3 of D-11-10:
  ```bash
  for i in $(seq 1 90); do
    REMAINING=$(kubectl --context=k3d-spoke-capsule get ns -l capsule.clastix.io/tenant= -o name | wc -l)
    if [[ "$REMAINING" -eq 0 ]]; then break; fi
    if [[ "$i" -ge 60 ]]; then
      info "namespace cascade stuck at $i s; force-clearing PVC finalizers (P36 mitigation)"
      kubectl --context=k3d-spoke-capsule get pvc -A -l capsule.clastix.io/tenant= -o json \
        | jq -r '.items[] | "\(.metadata.namespace)/\(.metadata.name)"' \
        | xargs -I{} kubectl --context=k3d-spoke-capsule patch pvc {} \
            -p '{"metadata":{"finalizers":null}}' --type=merge
    fi
    sleep 1
  done
  ```
  - **Rationale:** Matches research P36 prevention #4 verbatim; idempotent (no-op if no stuck PVCs); the POC iteration loop benefits from automatic recovery; bats can deterministically assert `no stuck namespaces after 90s`. Bypasses pvc-protection finalizer (acceptable for POC; Capsule-managed PVCs are tenant-scoped — force-delete only affects POC state).
  - **Bats falsifier:** `teardown-04-live-pvc-strand-mitigation.bats` synthetically creates a Pod-bound PVC in alpha-app1 BEFORE running destroy-poc; verifies the script auto-clears the PVC finalizer within the 90s budget.

#### Task surface — top-level POC tasks (D-11-12)

- **D-11-12:** **Top-level Taskfile.yml entries** (siblings of v0.18 tasks; precedent set by Phase 7 `task fix-dns-poc-capsule`):
  ```yaml
  fail-capsule-webhook:
    desc: (POC) Scale capsule-controller-manager to N replicas (test-only failure simulation; usage `task fail-capsule-webhook -- 0|1`)
    cmds:
      - bash scripts/poc/capsule/fail-capsule-webhook.sh {{.CLI_ARGS}}

  destroy-poc:
    desc: (POC) Ordered teardown for a named POC (usage `task destroy-poc -- capsule [--full]`)
    cmds:
      - bash scripts/poc/capsule/destroy-poc.sh {{.CLI_ARGS}}
  ```
  - **P31 invariant preserved BY LOCATION:** the SCRIPTS live under `scripts/poc/capsule/` (the location-based isolation lint Phase 7 P31 grep-asserts). The Taskfile.yml lines themselves do NOT trigger P31 — P31 is about the v0.18 scripts (`scripts/{create-clusters,register-spokes-for-flux,health-check,destroy,delete-clusters,rebuild}.sh`) NOT mentioning `spoke-capsule`.
  - **Discoverability:** `task --list` shows the POC tasks alongside v0.18 tasks. Description prefix `(POC)` distinguishes them.
  - **Variadic args:** `{{.CLI_ARGS}}` passes all positional + flag args through to the script (Taskfile v3 idiom).

### SLO regression + ADR-008 rubric (VAL-04 / VAL-06)

#### `task rebuild` SLO measurement — bats wraps `time` + docker CID compare (D-11-13)

- **D-11-13:** **`tests/bats/slo-regression-live.bats`** (single bats file, ~4 @tests):
  ```bash
  setup_file() {
    export REPO_ROOT="$(git rev-parse --show-toplevel)"
    export BEFORE_CID=$(docker inspect -f '{{.Id}}' k3d-spoke-capsule-server-0 2>/dev/null || echo "MISSING")
    [[ "$BEFORE_CID" != "MISSING" ]] || skip "spoke-capsule not running — VAL-04 requires live spoke-capsule for CID stability assertion"
  }

  @test "VAL-04 a — task rebuild completes < 230s" {
    cd "$REPO_ROOT"
    local start_s=$(date +%s)
    run task rebuild
    local end_s=$(date +%s)
    local elapsed=$((end_s - start_s))
    [[ "$status" -eq 0 ]] || { echo "task rebuild failed (status=$status)"; return 1; }
    [[ "$elapsed" -lt 230 ]] || { echo "task rebuild took ${elapsed}s (>= 230s SLO ceiling)"; return 1; }
    echo "rebuild elapsed: ${elapsed}s (budget: 230s)"
  }

  @test "VAL-04 b — k3d-spoke-capsule-server-0 container ID unchanged across rebuild" {
    local AFTER_CID=$(docker inspect -f '{{.Id}}' k3d-spoke-capsule-server-0)
    [[ "$BEFORE_CID" == "$AFTER_CID" ]] || { echo "spoke-capsule CID changed: $BEFORE_CID -> $AFTER_CID"; return 1; }
  }

  @test "VAL-04 c — task health-check exit 0 (v0.18 regression gate)" {
    cd "$REPO_ROOT"
    run task health-check
    [[ "$status" -eq 0 ]]
  }

  @test "VAL-04 d — P31 static lint via Phase 7 inheritance" {
    cd "$REPO_ROOT"
    run bats tests/bats/poc-isolation-01-static.bats
    [[ "$status" -eq 0 ]]
  }
  ```
  - **Rationale:** Matches VAL-04 verbatim (< 230s + CID unchanged); deterministic; one bats file; reuses Phase 7 P31 static lint as @test d (D-11-16); idempotent (re-running rebuild is the v0.18 contract).
  - **Live-gating:** `setup_file()` skips (not RED) if spoke-capsule isn't alive — Phase 11 verifier requires the cluster to be running; if it isn't, the bats are skipped with an explanatory message rather than failing.
  - **Plan placement:** Lives under VAL-04's plan; planner's call whether to land it in Wave 0 RED or in a later wave (recommendation: Wave 0 RED with live-skip gating, mirroring Phase 7/8/9/10 pattern).

#### ADR-008 outcome rubric — evidence-bound mechanical mapping (D-11-14)

- **D-11-14:** **Evidence-bound rubric** documented in ADR-008's `## Decision` section so the outcome is traceable to bats results:

  | Outcome | Required evidence |
  |---|---|
  | **ADOPT** | All 12/12 N1-N12 PASS + VAL-02 webhook recovery PASS + VAL-03 clean teardown PASS (no stuck namespaces post-90s) + VAL-04 < 230s + CID unchanged + zero gitleaks findings + ZERO open BLOCKER carryovers (all D-08-13 push-gate items resolved) |
  | **DEFER** | ≥ 1 of: N1-N12 has a RED-by-design (workaround documented, not bug) OR ≥ 1 unresolved upstream chart issue (e.g., D-11-01 PostBuild patch is a workaround — recommend graduation pending upstream chart fix) OR Phase 12 capsule-addon-fluxcd Trial would clarify the architectural shape — graduate to v0.20+ for a re-evaluation pass with the addon pattern |
  | **REJECT** | ≥ 1 of: N1-N12 RED for a tenant-isolation reason (silent escape — security invariant breached) OR VAL-04 SLO regressed > 230s (POC pollutes v1 SLO) OR webhook recovery non-deterministic (VAL-02 flakes more than 2/3 runs) — Capsule unsuitable for karyon's hub-only Flux + scorched-earth-rebuild contract |
  | **REPLACED BY ADR-009** | Mid-validation discovery: a fundamentally different POC (e.g., Hierarchical Namespaces / vCluster / Crossplane multi-tenant / kcp) is identified that supersedes Capsule's value proposition for karyon's lab use-case; ADR-008 records the comparison and points forward |

  - **Rationale:** Outcome is mechanical from bats data — no judgment call hidden in the ADR; auditable; matches Nygard `Decision` section spirit (a decision is a function of inputs, not a vibe). Phase 11 must lock these thresholds upfront — they're defensible (tenant isolation + SLO + push-gate-cleared are the load-bearing v0.19 invariants per STATE.md).
  - **ADR-008 structure (Nygard 4-section + 3 sub-sections):**
    ```markdown
    ---
    title: Capsule Multi-Tenancy POC Graduation
    status: Accepted (<adopt|defer|reject|replaced by ADR-009>)
    date: 2026-MM-DD
    deciders: Karyon milestone owner
    ---

    ## Context
    [milestone v0.19 background; Phases 7-10 deliverables; what this POC was meant to prove]

    ## Decision
    [outcome + rubric mapping (table above) + which row was matched]

    ### What we proved
    [bats refs: VAL-01 pass count, VAL-02 webhook halves, VAL-03 teardown clean, VAL-04 < 230s + CID stability]

    ### What we did not prove
    [out-of-scope items: HA Capsule, OIDC, multi-spoke federation, hub-side Capsule, prod ingress, real secret management]

    ### Trade-offs
    [POC-isms documented as trade-offs: long-lived TokenRequest semantics on k3s vs IRSA on EKS (per Phase 10 D-10-01 portability note); chart-level RBAC patch (D-11-01) is a workaround pending upstream fix; CapsuleConfiguration userGroups list (D-11-02) is opinionated; etc.]

    ## Consequences
    [if adopt: v0.20 incorporates Capsule into default `task rebuild`, spoke-capsule promoted from POC to v1 spoke; capsule-addon-fluxcd Phase 12 runs as adoption acceleration; if defer: v0.20 reruns with addon; if reject: spoke-capsule torn down as part of v0.19 close, no v0.20 carryover; if replaced: ADR-009 named, this POC's artifacts archived under .planning/milestones/v0.19-archive/]
    ```

#### EKSDOC-01 rollforward — targeted revisions (D-11-15)

- **D-11-15:** **Walk through `docs/capsule-on-eks.md`** with Phase 7-10 + Phase 11 bats evidence in hand. Set frontmatter `Status: Reviewed`. Add cross-reference to ADR-008. Specifically revise:
  - **Cert source section** — reflect Pitfall 10-P1 finding (capsule-proxy chart's `kube-webhook-certgen` Job emits `tls.crt` only; chart self-signs root with `tls.crt` doubling as CA; NO `ca.crt` key). EKS translation requires cert-manager (controller-managed) or AWS Certificate Manager (ALB-side termination) — the controller-less certgen Job pattern doesn't translate cleanly to EKS without operational state-tracking.
  - **IRSA section** — confirm or correct based on Phase 10 D-10-01 TokenRequest API + JWT exp claim verification. The POC's TokenRequest pattern translates cleanly to IRSA on EKS (both are short-lived bearer tokens via apiserver-side lifecycle); the `--service-account-max-token-expiration` clamp behavior differs across distros (k3s does NOT clamp per Phase 10 D-10-02 reframe; EKS clamps at 24h default).
  - **Proxy LIST scope** — add Phase 11 N1-N9 evidence on which kinds capsule-proxy filters (verified empirically): namespace LIST filter at proxy edge; cluster-scoped resources (ClusterRole, ClusterRoleBinding, nodes) filtered by upstream RBAC NOT proxy.
  - **Push-gate translation** — add Phase 11 D-11-01..04 patterns as 'EKS analogues': Flux's PostBuild patches map cleanly to Argo CD's ArgoCD post-render `kustomization` patches (or Argo's kustomized-application JSON patches); CapsuleConfiguration repo-side update is portable as-is; tenant home namespace label (D-11-03) requires Argo CD's `argocd.argoproj.io/sync-options: ServerSideApply` to handle the cluster-admin-bypass-webhook semantics.
  - **Rationale:** Ties the ADR-008 evidence directly to the EKS doc; future readers follow ADR → EKSDOC for the prod-side translation. Matches ROADMAP VAL-06 wording verbatim ("with corrections informed by the bats evidence").
  - **Plan placement:** Inside the same plan as ADR-008 write (or adjacent). Recommendation: ADR-008 lands first (records the decision); EKSDOC-01 rollforward lands immediately after (within the same Plan 11-FINAL or as Plan 11-FINAL+1).

#### P31 static lint — verbatim Phase 7 inheritance (D-11-16)

- **D-11-16:** **Inherit verbatim** — `tests/bats/poc-isolation-01-static.bats` (Phase 7 D-12 / P31 lint). Phase 11 VAL-04 reuses this verbatim as @test d in `slo-regression-live.bats` (per D-11-13).
  - **Rationale:** Zero duplication; Phase 7 already validated 6/6 across Phases 8/9/10; the lint is the static safety net asserting v0.18 scripts (`scripts/{create-clusters,register-spokes-for-flux,health-check,destroy,delete-clusters,rebuild}.sh`) have ZERO `spoke-capsule` mentions. `scripts/poc/capsule/` is excluded from the lint scope (POC scripts ARE allowed to mention spoke-capsule).
  - **Phase 11 NEW POC scripts** (`destroy-poc.sh`, `fail-capsule-webhook.sh`) live under `scripts/poc/capsule/` — excluded by location.

### Plan ordering inside Phase 11 (Claude's Discretion)

Recommended plan ordering (planner may reshape into 4-7 plans without re-asking; mirrors Phase 7/8/9/10 pattern):

- **Plan 11-00 — Wave 0 RED bats scaffold.** Land all D-11-05..16 bats files RED (negative-rbac-01..05, push-gate-01..05, teardown-01..04, slo-regression-live, anti-pattern lint). Static-only @tests can land GREEN at Wave 0 (e.g., teardown-01 script-shape, push-gate-01 PostBuild literal pre-D-11-01 landing — naturally RED until later plan; teardown-02 sentinel-preservation pre-script-landing RED). Mirrors 07-00 / 08-00 / 09-00 / 10-00.
- **Plan 11-01 — Push-gate persistent fixes.** Lands D-11-01 (PostBuild patch on `clusters/hub-flux/pocs/capsule.yaml`) + D-11-02 (CapsuleConfiguration userGroups repo update) + D-11-03 (tenant namespace labels) + D-11-04 (gitleaks `.gitleaks.toml` allowlist). All push-gate-01..05 static + live (where applicable, post-imperative-state-cleanup) bats turn GREEN.
- **Plan 11-02 — POC scripts + Taskfile.** Lands `scripts/poc/capsule/destroy-poc.sh` (D-11-10 + D-11-11) + `scripts/poc/capsule/fail-capsule-webhook.sh` (D-11-09) + Taskfile.yml entries (D-11-12). Teardown-01..02 static + live + fail-capsule script shape bats turn GREEN.
- **Plan 11-03 — Negative RBAC bats GREEN waves.** Lands any tenant CR fixture extensions (Tenant.spec.namespaceOptions.quota for N6, .spec.containerRegistries for N7, .spec.serviceAccountName for N9/N10 test cross-tenant fixtures), then runs negative-rbac-01..05 bats live. All N1-N12 turn GREEN.
- **Plan 11-04 — Push event + verifier (post-imperative-cleanup).** `helm uninstall capsule-proxy --kube-context=k3d-spoke-capsule -n capsule-system` (removes Plan 10-01 imperative install); `git push origin main` (first push event); CI gitleaks-scan + post-push history scan. All bats GREEN end-to-end. SLO-regression-live runs (D-11-13). Writes 11-VERIFICATION.md.
- **Plan 11-05 — ADR-008 + EKSDOC-01 rollforward.** Writes `docs/adr/0008-capsule-multi-tenancy-graduation.md` per D-11-14 outcome rubric (Status: Accepted with mapped outcome from bats evidence). Edits `docs/capsule-on-eks.md` per D-11-15 (4 targeted revision blocks + frontmatter Status: Reviewed). Both files committed; v0.19 milestone closes.

The planner may merge 11-04 + 11-05 if confident the verifier and ADR write fit cleanly together (the verifier produces the bats evidence; the ADR consumes it). Or split 11-03 into two plans (per-Tenant-CR fixture landing + bats-go-GREEN) if the Tenant CR mutations balloon. Default 5-plan structure is sufficient.

### Folded Todos

- **`2026-04-29-phase-7-gitleaks-planning-doc-allowlist.md`** (resolves_phase: 11) — folded into D-11-04 (Option C broad path-allowlist for `.planning/*.md`). The Phase 7 carryover is closed by Phase 11's `.gitleaks.toml` allowlist update; the post-first-push history scan (VAL-05) verifies zero findings.

### Claude's Discretion

The following gray areas are intentionally NOT specified — planner/researcher should default to v0.18 + Phase 7/8/9/10 patterns and note the chosen approach in PLAN.md without re-asking:

- **N6 quota fixture — Tenant CR `spec.namespaceOptions.quota`.** Recommended default: read existing `pocs/capsule/spoke/tenants/{alpha,bravo}/tenant.yaml`; if `namespaceOptions.quota` is absent, set `quota: 3` for both tenants (one home namespace + two app namespaces fits Phase 9 TEN-02 alpha-app1 / bravo-app1 + leaves room for N6 to create the N+1 = 4th and assert webhook reject). Add via separate plan or fold into Plan 11-03.
- **N7 registry fixture — Tenant CR `spec.containerRegistries`.** Recommended default: set `containerRegistries: [{allowed: ["registry.example.io"]}]` (or whatever Capsule v0.12.4 spec field name is — researcher verifies syntax). Bats N7 runs `kubectl run x --image=docker.io/library/nginx -n alpha-app1` and asserts webhook rejects with registry-violation error.
- **N9 cross-tenant sourceRef fixture.** Recommended default: bats authors a probe Kustomization YAML in tmpdir at test-time (NOT a repo-committed fixture); applies via `kubectl --kubeconfig=$ALPHA_KUBECONFIG apply -f $tmpfile` with `sourceRef.namespace: tenant-bravo`; asserts Flux reports cross-namespace-refs denied within 30s reconcile budget. NOT a repo fixture (avoids polluting `pocs/capsule/`).
- **N10 missing serviceAccountName fixture.** Recommended default: same shape as N9 — tmpdir-rooted probe Kustomization with no `spec.serviceAccountName`; assert Flux falls through to `--default-service-account: gitops-reconciler` impersonation OR rejects with RBAC denial.
- **Stdout/stderr split** for both new scripts (`destroy-poc.sh`, `fail-capsule-webhook.sh`): mirror Phase 10 D-10-09 pattern — stderr-only for preflight-lib log helpers; stdout for any structured output (for fail-capsule-webhook, no structured output needed).
- **Idempotency** for both new scripts: mirror Phase 10 — re-running is safe; no `-f`/`--force` flag needed (re-running destroy-poc against an already-deleted state succeeds with `|| true` per-step; re-running fail-capsule-webhook with the same replicas value is a no-op).
- **Post-teardown sentinel grep** location: bats teardown-02 (D-11-10 bats coverage) reads `clusters/hub-flux/flux-system/kustomization.yaml` directly; no separate sentinel-preservation script.
- **Plan ordering granularity:** Default 5-plan recommendation above; planner may merge or split per surface complexity. Phase 11's surface is meaningfully larger than Phase 10's (~6 requirements vs 3); 5-7 plans is the expected range.
- **ADR-008 file naming.** Recommended: `docs/adr/0008-capsule-multi-tenancy-graduation.md` (zero-padded number per existing 0001-0005 pattern; descriptive slug).
- **Verifier script wrapper:** bats-only (no `scripts/poc/capsule/verify-validation.sh` wrapper). Mirrors Phase 8/9/10 pattern.
- **Reconcile loop noise tolerance:** ≤2 reconcile cycles for any live observation depending on prior-plan reconcile; live-bats retry budget: 3 attempts × 30s sleep (Phase 8/9/10 inheritance).

### Review-Driven Revisions (2026-05-05)

The 6 PLAN.md files were reviewed by codex (`gpt-5.5`, xhigh reasoning). Cross-AI feedback in `11-REVIEWS.md`. Targeted revisions below address HIGH/MEDIUM concerns. **Original D-11-XX decisions remain locked except as explicitly REVISED below.**

#### D-11-04-revised — Tightened gitleaks planning-doc allowlist (REVISED 2026-05-05)

- **Revision rationale:** Reviewer HIGH concern #3. The original `^\.planning/.*\.md$` pattern allowlists EVERY markdown file under `.planning/`, hiding the exact accidental-leak class VAL-05 is meant to catch.
- **Revised D-11-04 patterns** — replace the broad regex with the specific known-fixture-bearing files (verified 2026-05-05 via `grep -l 'kind: Config' .planning/phases/{07,10}-*/*.md`):
  ```toml
  paths = [
    '''^\.env\.example$''',                                                                                        # whole-file allow (Phase 1 D-11 contract)
    '''^\.planning/phases/07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc/07-00-PLAN\.md$''',         # Phase 7 D-14 synthetic-fixture content (D-11-04)
    '''^\.planning/phases/07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc/07-RESEARCH\.md$''',        # Phase 7 D-14 synthetic-fixture content (D-11-04)
    '''^\.planning/phases/07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc/07-REVIEW\.md$''',          # Phase 7 D-14 synthetic-fixture content (D-11-04)
    '''^\.planning/phases/07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc/07-PATTERNS\.md$''',        # Phase 7 D-14 synthetic-fixture content (D-11-04)
    '''^\.planning/phases/10-tenant-owner-kubeconfigs-capsule-proxy-round-trip/10-00-PLAN\.md$''',                 # Phase 10 fixture-quoting docs (D-11-04)
    '''^\.planning/phases/10-tenant-owner-kubeconfigs-capsule-proxy-round-trip/10-REVIEW\.md$''',                  # Phase 10 fixture-quoting docs (D-11-04)
    '''^\.planning/phases/10-tenant-owner-kubeconfigs-capsule-proxy-round-trip/10-PATTERNS\.md$''',                # Phase 10 fixture-quoting docs (D-11-04)
  ]
  ```
- **Trade-off resolved:** Each entry is a specific file path under `.planning/phases/{07,10}-*/` that PROVABLY quotes the synthetic-kubeconfig fixture content (verified 2026-05-05 via `grep -l "token: [A-Za-z0-9._-]\{32,\}"`). NEW phases that quote fixtures must add a new path entry (intentional friction; prevents the broad-allowlist class of leak).
- **Plan impact:** Plan 11-01 Task 2 File 4 lands the tightened entries (NOT the broad regex). Plan 11-00 Task 2 File 5 (`push-gate-05-static-gitleaks-allowlist.bats`) static @test 1 greps for at least 4 distinct allowlist entries (the 4 Phase 7 files) and verifies the broad `^\.planning/.*\.md$` regex is ABSENT.

#### Pitfall 11-P6 — Live-evidence skip equals graduation risk (NEW 2026-05-05)

- **Concern:** Reviewer HIGH concern #1 + MEDIUM concern. If `negative-rbac-*.bats` setup_file SKIPs (cluster unreachable / kubeconfig minting fails), the @test exits with status SKIP, NOT FAIL. Plan 11-04 Task 3's verifier RC matrix would then record "skipped" as if it were neutral, but for a graduation-deciding ADR, "skipped live tests" is NOT positive evidence.
- **Mitigation 1 — Strict-mode env var:** `KARYON_PHASE11_STRICT_LIVE=1` (set by CI / operator-driven graduation runs) flips bats `skip` calls in negative-rbac, push-gate-04-live, teardown-03-live-ordered, and slo-regression-live to `return 1` (FAIL). Implementation: each `skip "..."` becomes `if [[ "${KARYON_PHASE11_STRICT_LIVE:-}" == "1" ]]; then echo "STRICT_LIVE: $skip_msg"; return 1; else skip "$skip_msg"; fi`.
- **Mitigation 2 — Plan 11-04 disposition gating:** the verifier cannot record disposition `passed` if any live test SKIPPED (counts as missing evidence — degrades to `passed_with_overrides` at best). The 11-VERIFICATION.md "Live evidence collected vs skipped" table makes this auditable.
- **Mitigation 3 — ADR-008 acknowledgment:** the `Trade-offs` section names `KARYON_PHASE11_STRICT_LIVE` as the documented mitigation; `What we did not prove` cites any live tests that skipped during the graduation run.
- **Plan impact:** Plan 11-00 wraps every `skip` call in negative-rbac-*, push-gate-04-live, teardown-03-live-ordered, and slo-regression-live in the strict-mode conditional. Plan 11-04 Task 3+4 enforces disposition gating. Plan 11-05 ADR-008 cites the env var.

#### D-11-01 hard-gate at Plan 11-04 Task 3 (REVISION 2026-05-05)

- **Concern:** Reviewer HIGH concern #2. The static `push-gate-01-static-rbac-postbuild.bats` greps for the patch literal in `clusters/hub-flux/pocs/capsule.yaml` and turns GREEN as soon as Plan 11-01 lands the patch — but the empirical falsifier (whether the patch actually propagates to the spoke-rendered Role) is informational only.
- **Mitigation:** Plan 11-04 Task 3's discriminating jq check on the live chart-rendered Role becomes a HARD GATE (not informational). Specifically:
  ```bash
  kubectl --context=k3d-spoke-capsule get role capsule-proxy:capsule-proxy -n capsule-system -o json \
    | jq -e '.rules[] | select((.resources // []) | contains(["secrets"])) | select((.verbs // []) | contains(["create"]))' >/dev/null 2>&1
  ```
  - If exit 0: D-11-01 propagated; disposition contribution is `passed`.
  - If exit non-zero: Pitfall 11-P1 fired; disposition is downgraded to `passed_with_overrides` AT BEST (never `passed`); 11-VERIFICATION.md `## Notable Observations` MUST contain explicit "Recommend relocating D-11-01 patch to capsule-spoke.yaml in a follow-up plan" entry.
- **D-11-01 itself remains LOCKED** — plan 11-01 still lands the patch on `clusters/hub-flux/pocs/capsule.yaml` per CONTEXT.md original. The Rule 3 escalation is a Plan 11-04 verifier-time response, not a preemptive replanning.

#### Teardown bats merge — teardown-03 + teardown-04 → single teardown-03-live-ordered.bats (REVISION 2026-05-05)

- **Concern:** Reviewer HIGH concern #6. The original two bats (teardown-03 destroys + teardown-04 PVC strand) are NOT independent — if teardown-03 runs first, alpha-app1 is gone and teardown-04 has no namespace to seed the synthetic PVC.
- **Mitigation:** Plan 11-00 Task 2 merges into a single `teardown-03-live-ordered.bats` with @tests in this exact order:
  1. **@test 1 (precondition):** seed synthetic Pod-bound PVC labeled `capsule.clastix.io/tenant=alpha` in alpha-app1 (skip if alpha-app1 absent).
  2. **@test 2 (action + invariants):** run `task destroy-poc -- capsule`; assert exit 0; poll labeled namespaces empty + PVC absent within 90s; sentinel + `../pocs` mount lines preserved verbatim in `clusters/hub-flux/flux-system/kustomization.yaml`.
- **File impact:** `tests/bats/teardown-04-live-pvc-strand-mitigation.bats` is REMOVED from `files_modified`. Total bats count: 16 → 15 (then `+1` for new p27 static lint per Suggestion 14 → back to 16).

#### P27 static lint — new bats (per suggestion #14, NEW 2026-05-05)

- **Concern:** Reviewer LOW Suggestion #14. P27 ("every tenant Flux Kustomization MUST set `spec.serviceAccountName`") is currently load-bearing but only enforced dynamically (Phase 9 D-09-08 grep-loop on tenant inner Ks).
- **Mitigation:** Plan 11-00 Task 2 adds `tests/bats/p27-tenant-kustomization-sa-static.bats` that walks `clusters/hub-flux/pocs/` and asserts every Flux Kustomization (kind: Kustomization) declares a non-empty `spec.serviceAccountName`. Static lint; GREEN-at-landing if Phase 9 P27 contract still holds.
- **Impact:** Restores total bats count to 16. Plan 11-00 Task 2 file count remains 10 (the merged teardown-03-live-ordered.bats replaces both teardown-03 + teardown-04 files; the new p27 lint adds back to 10).

#### destroy-poc.sh shell semantics (REVISION 2026-05-05)

- **Concern:** Reviewer HIGH concern #5 + MEDIUM concern #9. (a) `flux suspend kustomization a b c` may need one object per invocation; (b) `|| true` hides legitimate failures; (c) Step 3 must explicitly `--context=k3d-spoke-capsule` everywhere; (d) PVCs may not carry the `capsule.clastix.io/tenant` label.
- **Mitigation (Plan 11-02 destroy-poc.sh revisions):**
  - **Step 1 — per-Kustomization suspend with verify:** loop over `tenant-alpha tenant-bravo poc-capsule-spoke` ONE PER `flux suspend kustomization NAME -n flux-system`; collect each non-zero RC and emit `warn` (NOT `|| true` swallow). Verify each via `kubectl --context=k3d-hub-flux get kustomization NAME -n flux-system -o jsonpath='{.spec.suspend}'` returns `true`.
  - **Step 3 — every kubectl call uses `--context=k3d-spoke-capsule`:** auditable via grep.
  - **Step 3 PVC enumeration via NS_LIST loop:** drop the `-l capsule.clastix.io/tenant` label selector when enumerating PVCs; instead enumerate PVCs in the surviving labeled namespaces:
    ```bash
    NS_LIST=$(kubectl --context=k3d-spoke-capsule get ns -l capsule.clastix.io/tenant -o name 2>/dev/null | sed 's|namespace/||')
    for ns in $NS_LIST; do
      kubectl --context=k3d-spoke-capsule get pvc -n "$ns" -o name 2>/dev/null | while read pvc; do
        kubectl --context=k3d-spoke-capsule patch "$pvc" -n "$ns" -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null || true
      done
    done
    ```
  - **Step 4 — same single-object suspend pattern:** `flux suspend kustomization poc-capsule -n flux-system` (single object).

#### helm uninstall race-with-Flux (REVISION 2026-05-05)

- **Concern:** Reviewer MEDIUM concern #10. If hub-flux reconciles between `helm uninstall capsule-proxy` and the push, the chart can be reinstalled in an inconsistent state.
- **Mitigation (Plan 11-04 Task 1 sequence):** suspend the relevant Kustomizations first:
  ```bash
  flux suspend kustomization poc-capsule -n flux-system
  flux suspend kustomization poc-capsule-spoke -n flux-system
  helm --kube-context=k3d-spoke-capsule uninstall capsule-proxy -n capsule-system
  for i in 1 2 3; do
    if ! kubectl --context=k3d-spoke-capsule get deploy capsule-proxy -n capsule-system >/dev/null 2>&1; then break; fi
    sleep 10
  done
  flux resume kustomization poc-capsule-spoke -n flux-system
  flux resume kustomization poc-capsule -n flux-system
  ```

#### N9 / N10 falsifier validity (REVISION 2026-05-05)

- **Concern:** Reviewer HIGH concern #4. N9 must use a real, valid cross-tenant sourceRef (NOT an absent source); N10's `(forbidden|Forbidden|cannot|not found)` permissive grep accepts "not found" which doesn't prove missing-SA fallthrough.
- **Mitigation (Plan 11-00 Task 1 File 4 revisions):**
  - **N9:** the probe Kustomization MUST reference a GitRepository that ACTUALLY EXISTS in `tenant-bravo` namespace (or a valid cross-tenant target — NOT `flux-system` which Flux itself owns; NOT an absent source name). Drop the `not allowed` substring as too permissive; require the explicit `cross-namespace` keyword in the Ready message.
  - **N10:** drop `(forbidden|Forbidden|cannot|not found)` permissive grep. The probe Kustomization MUST point at a VALID sourceRef (e.g., `tenant-alpha-source` GitRepository which exists per Phase 9 TEN-04). The only failing variable is the missing `serviceAccountName`. Replace with positive assertion that Flux falls through to the `default` SA in `tenant-alpha` (zero permissions) AND the failure message references RBAC (e.g., `system:serviceaccount:tenant-alpha:default` + `forbidden`), NOT "source not found".

#### N6 / N8 / N11 stability hardening (REVISION 2026-05-05)

- **Concern:** Reviewer MEDIUM concerns #7, #8, #12.
- **Mitigation:**
  - **N6 (Plan 11-00 Task 1 File 3) idempotent precondition:** `setup_file` deletes all `tenant-alpha`-prefixed namespaces EXCEPT `tenant-alpha` and `alpha-app1` BEFORE running the quota probe. Skip if `alpha-app1` absent. Wait for cleanup to complete before counting.
  - **N8 (Plan 11-00 Task 1 File 4) network/TLS pre-check:** TCP probe via `nc -z 127.0.0.1 6446`; if unreachable, SKIP with explanatory message (NOT pass for the wrong reason). Negative TLS-failure assertion: output MUST NOT contain `x509`, `tls:`, `connection refused`, `i/o timeout` (would indicate network/TLS failure not RBAC denial). Existing literal asserts on `Forbidden` AND `cannot list resource "namespaces"` retained.
  - **N11 (Plan 11-00 Task 1 File 5) deterministic wait:** replace `sleep 5` after scaling with a poll loop checking `kubectl get deploy capsule-controller-manager -n capsule-system -o jsonpath='{.status.readyReplicas}'` until `0`, then poll for Service endpoints empty (or for the validating webhook lookup to start failing) within a 30s budget.

#### Command syntax standardization (REVISION 2026-05-05)

- **Concern:** Reviewer MEDIUM concern #11. `task destroy-poc capsule` vs `task destroy-poc -- capsule` is inconsistent. Taskfile `{{.CLI_ARGS}}` requires the `--` separator.
- **Mitigation:** Standardize on `task destroy-poc -- capsule` everywhere. Audit:
  - 11-02 Task 1 destroy-poc.sh head comment + usage strings
  - 11-02 Task 2 Taskfile desc strings (both `(POC)` entries should be consistent)
  - 11-04 Task 3 + Task 4 (11-VERIFICATION.md template) — use `task destroy-poc -- capsule`
  - 11-05 Task 2 ADR-008 template — use `task destroy-poc -- capsule [--full]`
  - 11-VALIDATION.md Per-Task Verification Map and Manual-Only Verifications — use `task destroy-poc -- capsule [--full]`

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project planning artifacts (REQUIRED reading)

- `.planning/REQUIREMENTS.md` — VAL-01 through VAL-06 contracts; load-bearing P27 (tenant Flux Kustomization MUST set `spec.serviceAccountName`); P29 (kubeconfigs MUST NOT land in git); P31 isolation contract (POC scripts under `scripts/poc/capsule/`); ADR-004 inheritance; v0.19 inheritance from v0.18 ADRs. **Phase 11 owns VAL-01..06 verbatim.**
- `.planning/ROADMAP.md` (Phase 11 section + Phase 12 OPTIONAL gate condition) — phase goal, ordered success criteria #1-6, dependency declarations, ADR-008 outcome ∈ {adopt, defer, reject, replaced by ADR-N}.
- `.planning/PROJECT.md` — v0.19 out-of-scope items (cert-manager, OIDC, prod ingress, multi-spoke federation, hub-side Capsule, default platform adoption); ADR-004 hub-only invariant; public-repo secrets contract; v0.18 follow-up items (shellcheck cleanup, first-push CI verification — Phase 11 VAL-05 owns the first push event).
- `.planning/STATE.md` — Phase 10 close-out (`passed_with_overrides` 3/3 must-haves: 4 D-08-13 push-gate-deferred to Phase 11 VAL-05); 3 carryovers from Phase 10 to Phase 11 (chart RBAC patch persistence; CapsuleConfiguration userGroups; tenant home namespace ownership) — Phase 11 D-11-01..03 resolve these. Load-bearing invariants P27/P29/P31. Phase 11 ready to plan (post-discuss as of 2026-05-05).

### Phase 7/8/9/10 artifacts — REQUIRED context (Phase 11 inherits everything Phases 7-10 shipped)

- `.planning/phases/07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc/07-CONTEXT.md` — D-05 through D-17. **Especially D-12 (P31 `scripts/poc/capsule/` namespace), D-14 (.gitignore + .gitleaks.toml leak defenses + synthetic-kubeconfig fixture), D-15 (preflight 30443 reservation).**
- `.planning/phases/07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc/07-SUMMARY.md` — what each Phase 7 plan shipped (P31 lint at `tests/bats/poc-isolation-01-static.bats` is verbatim-reused in Phase 11 D-11-13/D-11-16).
- `.planning/phases/08-capsule-capsule-proxy-bare-minimum-install/08-CONTEXT.md` — D-08-01 through D-08-13. **Especially D-08-11 (capsule-proxy controller-less certgen Job + chart-rendered Role with `secrets create` gap — Phase 11 D-11-01 closes this gap), D-08-12 (split-path architectural seam — outer K targets), D-08-13 (push-gate deferral cleared in Phase 11 VAL-05).**
- `.planning/phases/09-tenants-flux-multi-tenancy-lockdown/09-CONTEXT.md` — D-09-01 through D-09-09. **Especially D-09-02 (per-tenant SA `gitops-reconciler` in `tenant-<tenant>` ns — Phase 11 N1-N12 mints kubeconfigs for these SAs), D-09-03 (transitional tenant inner K kubeConfig — Phase 11 does NOT modify these; Phase 12 absorbs), D-09-04 (CapsuleConfiguration default singleton with `forceTenantPrefix: true` + `allowServiceAccountPromotion: true` — Phase 11 D-11-02 extends userGroups), D-09-05 (lockdown patch surface in `clusters/hub-flux/flux-system/kustomization.yaml` — Phase 11 D-11-01 mirrors patch surface pattern in `clusters/hub-flux/pocs/capsule.yaml`), D-09-08 (Wave 0 RED bats scaffold pattern — INHERITED).**
- `.planning/phases/09-tenants-flux-multi-tenancy-lockdown/09-VERIFICATION.md` — Phase 9 verification (`passed_with_overrides`); attempt-3 lockdown lessons.
- `.planning/phases/10-tenant-owner-kubeconfigs-capsule-proxy-round-trip/10-CONTEXT.md` — D-10-01 through D-10-10. **Especially D-10-01 (TokenRequest API for tenant kubeconfigs — Phase 11 N1-N12 mints via `issue-tenant-kubeconfig.sh`), D-10-02 (default --duration=1h with k3s-no-clamp note from research; Phase 11 setup_file uses --duration=2h to cover slow runs), D-10-08 (direct-apiserver bypass falsifier — Phase 11 D-11-08 reuses), D-10-09 (Wave 0 bats coverage pattern — INHERITED), D-10-10 (plan ordering 00 RED → 01 script → 02 verifier — Phase 11 mirrors with 5 plans for larger surface).**
- `.planning/phases/10-tenant-owner-kubeconfigs-capsule-proxy-round-trip/10-VERIFICATION.md` — **THE 3 CARRYOVER ITEMS** Phase 11 resolves: (1) chart RBAC patch persistence (D-11-01 closes), (2) CapsuleConfiguration userGroups (D-11-02 closes), (3) tenant home namespace ownership (D-11-03 closes). Plan 10-01 + 10-02 Rule 3 deviations documented for Phase 11 push-gate awareness.

### Architecture Decision Records (load-bearing for Phase 11)

- `docs/adr/0001-single-wsl2-shared-docker-network.md` — k8s-net shared bridge.
- `docs/adr/0002-k3d-over-kind.md` — k3d cluster runtime; spoke-capsule lifecycle (D-11-13 docker inspect CID compare against k3d-spoke-capsule-server-0).
- `docs/adr/0003-flux-over-argocd.md` — Flux 2 as GitOps tool; informational for Phase 11 (D-11-15 EKSDOC-01 rollforward documents Argo CD analogues for prod translation).
- `docs/adr/0004-hub-only-flux-control-plane.md` — **load-bearing**: NO Flux controllers run on spoke-capsule. Phase 11 verifier MUST re-grep-assert `kubectl --context=k3d-spoke-capsule get pods -n flux-system` returns no flux controllers (regression gate inheritance).
- `docs/adr/0005-kubernetes-version-pin.md` — k3s `v1.34.6-k3s1`; TokenRequest API + `--service-account-max-token-expiration` (k3s does NOT clamp per Phase 10 D-10-02 reframe — informational for Phase 11 D-11-15 EKSDOC translation).

### Architecture Decision Record under construction (Phase 11 deliverable)

- `docs/adr/0008-capsule-multi-tenancy-graduation.md` — **TO BE WRITTEN by Plan 11-05** per VAL-06 + D-11-14 evidence-bound rubric. Status: Accepted with one of {adopt, defer, reject, replaced by ADR-009}. Nygard 4-section (Context / Decision / Consequences / Status) + 3 sub-sections in Decision (What we proved / What we did not prove / Trade-offs).

### Milestone-level research (REQUIRED for planning)

- `.planning/research/SUMMARY.md` §"Phase 12 — Validation + Graduation ADR-008" (note: research's "Phase 12" maps to current Phase 11 in the renumbered roadmap; phase counting choice in STATE.md acknowledges the renumbering). §"Negative RBAC table N1-N12" — note ROADMAP success criterion #1 has a SHIFTED N1-N12 mapping vs research (ROADMAP splits webhook-down into N11+N12; drops research N9 'nodes via proxy'; softens research N8 from 'Forbidden' to 'denied OR limited'). **Use ROADMAP success-criteria-#1 N1-N12 mapping, NOT research FEATURES.md N1-N12, as the canonical source.**
- `.planning/research/PITFALLS.md` — P26-P43 catalogue. **Phase 11 directly addresses:**
  - **P26** (capsule webhook failurePolicy: Fail blocks Flux apply on operator-down) — VAL-02 mechanism via D-11-09 scale-Deployment-0/1; bats N11 + N12 cover both halves.
  - **P29** (kubeconfigs MUST NOT land in git — load-bearing) — D-11-04 closes via gitleaks `.gitleaks.toml` allowlist; VAL-05 first-push gitleaks scan verifies zero findings.
  - **P31** (POC isolation — load-bearing) — VAL-04 P31 static lint inheritance verbatim from Phase 7; D-11-12 task surface preserves by-location.
  - **P36** (Tenant teardown leaves stranded PVCs / RoleBindings) — VAL-03 mechanism via D-11-10 5-step + D-11-11 auto force-delete after 60s.
  - **P37** (kubectl auth can-i SAR cache flake — moderate) — D-11-05 real-CRUD probe shape bypasses SAR cache; D-11-06 bats anti-pattern lint forbids `kubectl auth can-i` in negative-rbac source files.
  - **P41** (Graduation ADR skipped or postponed — minor) — VAL-06 mandatory acceptance criterion; D-11-14 evidence-bound rubric ensures the ADR is more than a formality.
  - **P42** (Tenant SA bearer token expiry — minor) — Phase 10 D-10-01 TokenRequest API closed this; ADR-008 'Trade-offs' section documents the POC simplification per VAL-06.
- `.planning/research/FEATURES.md` §"Negative RBAC Tests (Required Falsifiers)" — research N1-N12 table is informational; ROADMAP success criterion #1 is canonical (see note above).
- `.planning/research/ARCHITECTURE.md` §"Phase 12 — Validation + Graduation ADR" (note: research's "Phase 12" = current Phase 11 in renumbered roadmap).
- `.planning/research/STACK.md` — Capsule v0.12.4, capsule-proxy 0.12.0, k3s v1.34.6-k3s1 pins; chart certgen output Secret shape (Phase 10 D-10-06a research-flagged → Pitfall 10-P1 resolved).

### v0.18 + Phase 7/8/9/10 reference implementations (analogs to mirror in Phase 11)

- **`scripts/poc/capsule/create-cluster.sh`** + **`scripts/poc/capsule/issue-tenant-kubeconfig.sh`** + **`scripts/poc/capsule/fix-dns.sh`** — Phase 7 + 10 references for `scripts/poc/capsule/`-rooted scripts. Phase 11's `destroy-poc.sh` + `fail-capsule-webhook.sh` mirror head structure: `set -euo pipefail`, `SCRIPT_DIR`/`REPO_ROOT` pinning, `source scripts/lib/preflight-lib.sh`, head comment block citing requirements + decisions, idempotent control-flow, fail-fast error style with hint.
- **`scripts/lib/preflight-lib.sh`** — output helpers (`section`, `pass`, `warn`, `fail`, `info`, `have`). Phase 11's scripts source this for v0.18 ergonomics.
- **`tests/bats/test_helper`** — shared bats loader pinning `REPO_ROOT`. Phase 11 bats files load this without modification.
- **`tests/bats/poc-isolation-01-static.bats`** — Phase 7 P31 regression gate. **Phase 11 VAL-04 reuses verbatim** as @test d in `slo-regression-live.bats` (D-11-13 / D-11-16).
- **`tests/fixtures/gitleaks/synthetic-kubeconfig.yaml`** — Phase 7 D-14 positive fixture; rule fires; allowlisted in `.gitleaks.toml`. Phase 11 D-11-04 adds `.planning/*.md` path-allowlist (not the fixture).
- **`.gitignore`** — Phase 7 D-14 globs cover Phase 10 + 11 ephemeral kubeconfigs in tmpdir. Phase 11 does NOT modify .gitignore.
- **`.gitleaks.toml`** — Phase 7 D-14 + Phase 11 D-11-04 evolution. Phase 11 D-11-04 adds `'^\.planning/.*\.md$'` to `[allowlist] paths`.
- **`docs/poc-capsule.md`** — Phase 7 + Phase 10 doc; Phase 11 may append teardown section per Plan 11-02 (planner discretion: H2 "Ordered teardown procedure" with the 5-step sequence cross-linked to ADR-008).
- **`pocs/capsule/spoke/tenants/{alpha,bravo}/{namespace,sa,tenant}.yaml`** — Phase 9 D-09-02 outputs. **Phase 11 D-11-03 ADDS the `capsule.clastix.io/tenant: <name>` label to the namespace.yaml files.** Tenant CR fixture extensions (N6 quota, N7 registry — Claude's discretion) edit the tenant.yaml files.
- **`pocs/capsule/spoke/config/capsuleconfig.yaml`** — Phase 9 D-09-04 default singleton. **Phase 11 D-11-02 EDITS this file** to inline `userGroups: [capsule.clastix.io, system:serviceaccounts, system:authenticated]`.
- **`clusters/hub-flux/pocs/capsule.yaml`** — Phase 8 D-08-12 hub-targeted outer K. **Phase 11 D-11-01 ADDS `spec.patches` block** extending chart-rendered Role.
- **`clusters/hub-flux/pocs/capsule-spoke.yaml`** — Phase 8 D-08-12 spoke-targeted outer K. Phase 11 reads (does NOT modify) — sentinel preservation guarantee.
- **`clusters/hub-flux/flux-system/kustomization.yaml`** — Phase 4 D-02 + Phase 9 D-09-05 patch surface (lockdown flags + KARYON SPOKES MOUNT + KARYON POC MOUNT sentinels). **Phase 11 destroy-poc explicitly does NOT modify this file** — sentinel preservation is the load-bearing invariant.
- **`docs/capsule-on-eks.md`** — Phase 7 EKSDOC-01 rough-cut design doc. **Phase 11 D-11-15 ROLLS FORWARD** to `Status: Reviewed` with 4 targeted revision blocks per VAL-06.
- **`Taskfile.yml`** — top-level task naming pattern. **Phase 11 D-11-12 ADDS** `task fail-capsule-webhook` + `task destroy-poc` entries.
- **`scripts/{create-clusters,register-spokes-for-flux,health-check,destroy,delete-clusters,rebuild}.sh`** — v0.18 script set; **Phase 11 verifier asserts ZERO `spoke-capsule` mentions remain** (P31 inheritance verbatim).

### External upstream references (informational; no edits)

- Capsule project — `https://capsule.clastix.io/`.
- capsule-proxy chart — `oci://ghcr.io/projectcapsule/charts/capsule-proxy:0.12.0`.
- Capsule operator chart — `oci://ghcr.io/projectcapsule/charts/capsule:0.12.4`.
- Kubernetes TokenRequest API — `https://kubernetes.io/docs/reference/access-authn-authz/service-accounts-admin/#bound-service-account-tokens` (canonical short-lived SA token via `kubectl create token`).
- Kubernetes SubjectAccessReview API + authorization cache — `https://kubernetes.io/docs/reference/access-authn-authz/authorization/#authorizer-configuration` (P37 SAR cache TTL reference).
- Capsule webhook configuration semantics — `https://capsule.clastix.io/docs/general/references/` (failurePolicy, matchConditions, objectSelector — VAL-02 mechanism research).
- gitleaks documentation — `https://github.com/gitleaks/gitleaks` (`.gitleaks.toml` allowlist semantics — D-11-04).
- Nygard ADR template — `https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions` (ADR-008 4-section structure).

### Folded todo

- `.planning/todos/pending/2026-04-29-phase-7-gitleaks-planning-doc-allowlist.md` (resolves_phase: 11) — folded into D-11-04. Will auto-close upon Phase 11 close-out (per `resolves_phase: 11`).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- **Phase 10 `scripts/poc/capsule/issue-tenant-kubeconfig.sh`** — Phase 11 N1-N12 setup_file() invokes this to mint alpha + bravo kubeconfigs at bats run time (D-11-07). Already validated; uses TokenRequest API with `--duration=2h` (Phase 11 default for slow bats runs); writes to `${TMPDIR:-/tmp}/karyon-tenants/`.
- **`scripts/poc/capsule/create-cluster.sh`** + **`fix-dns.sh`** — Phase 7 / Phase 10 references for `scripts/poc/capsule/`-rooted scripts. Phase 11's two new scripts (`destroy-poc.sh`, `fail-capsule-webhook.sh`) mirror head structure verbatim.
- **`scripts/lib/preflight-lib.sh`** — output helpers + `have <cmd>` tool gate. Phase 11's scripts source this for v0.18 ergonomics.
- **`tests/bats/test_helper`** — shared bats loader. Phase 11 bats files load without modification.
- **`tests/bats/poc-isolation-01-static.bats`** — Phase 7 P31 regression gate. **Phase 11 D-11-16 reuses verbatim** as @test d in `slo-regression-live.bats`.
- **Phase 8 `clusters/hub-flux/pocs/capsule.yaml`** outer K — Phase 11 D-11-01 EXTENDS with PostBuild `spec.patches` block (Role-extending patch).
- **Phase 9 `pocs/capsule/spoke/tenants/{alpha,bravo}/`** — Phase 11 D-11-03 EDITS namespace.yaml files (add label); Claude's discretion EDITS tenant.yaml (N6 quota / N7 registry fixtures).
- **Phase 9 `pocs/capsule/spoke/config/capsuleconfig.yaml`** — Phase 11 D-11-02 EDITS to inline 3-group userGroups list.
- **Phase 7 `.gitleaks.toml`** — Phase 11 D-11-04 APPENDS path-allowlist entry.
- **`.github/workflows/ci.yml` `gitleaks-scan` job** — Phase 11 VAL-05 first push triggers this CI job; fetch-depth: 0 ensures full-history scan; `gitleaks git --log-opts="--all"` exits 0 expected post-D-11-04.
- **Capsule operator's auto-injected RoleBindings on Tenant owners (admin + capsule-namespace-deleter ClusterRoles)** — Phase 9 D-09-02 inheritance. N1-N12 falsifiers exercise this RBAC surface from outside (cross-tenant).

### Established Patterns

- **`scripts/poc/capsule/`-rooted scripts** — Phase 7 D-12 / P31 isolation contract. Phase 11's two new scripts (`destroy-poc.sh`, `fail-capsule-webhook.sh`) live at this root. NEVER invoked by `task rebuild`; never referenced from v0.18 scripts (regression-gated by `poc-isolation-01-static.bats` per D-11-16).
- **Bash strict-mode + `REPO_ROOT`/`SCRIPT_DIR` pinning** — Phase 11's two new scripts adopt identical preamble.
- **`preflight-lib` ergonomics** — section/pass/warn/fail/info/have helpers. Phase 11's scripts source these. Tool-gate uses `have kubectl k3d`; failures use `fail` with multi-line hints; info-level state changes use `info`.
- **Bats static-contract test naming `<area>-<NN>-{static|live}-<topic>.bats`** — Phase 8/9/10 inheritance. Phase 11 names:
  - `negative-rbac-{01..05}-<topic>.bats` (D-11-06 partition)
  - `push-gate-{01..05}-{static|live}-<topic>.bats` (D-11-01..04 coverage)
  - `teardown-{01..04}-{static|live}-<topic>.bats` (D-11-10..11 coverage)
  - `slo-regression-live.bats` (single file, ~4 @tests, D-11-13 / D-11-16)
  - `negative-rbac-anti-pattern-lint-static.bats` (D-11-05 enforcement — forbids `kubectl auth can-i` in source files)
- **Wave 0 RED bats scaffold** (Phase 7/8/9/10 D-09-08 / D-10-09 pattern). Phase 11 Plan 11-00 mirrors. Already-validated.
- **POC isolation regression** (Phase 7 P31 contract). Phase 11 verifier reruns `tests/bats/poc-isolation-01-static.bats` to confirm new scripts + Taskfile entries did NOT introduce `spoke-capsule` mentions in v0.18 scripts.
- **TmpDir-rooted ephemeral artifacts** (Phase 7 D-14 + Phase 10 D-10-09). Phase 11's bats kubeconfig minting (D-11-07) + N8 direct-apiserver kubeconfig (D-11-08) + N9/N10 cross-tenant probe Kustomizations (Claude's Discretion) all use `mktemp -d "${TMPDIR:-/tmp}/karyon-tenants/bats-XXXX"` rooted paths.
- **Hub-side outer-K patch surface pattern** (Phase 9 D-09-05 lockdown patches in `clusters/hub-flux/flux-system/kustomization.yaml`; Phase 11 D-11-01 PostBuild patches in `clusters/hub-flux/pocs/capsule.yaml`) — patches live at the FLUX PATCH SURFACE boundary, not embedded in Helm values or chart-rendered manifests.

### Integration Points

- **`scripts/poc/capsule/destroy-poc.sh`** (NEW) — net-new script. Sources `preflight-lib`, gates `kubectl/k3d/flux/jq/yq` presence, runs 5-step canonical teardown (D-11-10), auto force-deletes stuck PVCs after 60s (D-11-11), preserves KARYON POC MOUNT sentinel + clusters/hub-flux/pocs/ mount.
- **`scripts/poc/capsule/fail-capsule-webhook.sh`** (NEW) — net-new script. Sources `preflight-lib`, gates `kubectl` presence, scales `capsule-controller-manager` Deployment to 0 or 1 (D-11-09); on `1`, polls rollout status to Ready before exit.
- **`Taskfile.yml`** — D-11-12 ADDS two top-level `task` entries (`fail-capsule-webhook`, `destroy-poc`). No changes to existing v0.18 tasks (P31 by location).
- **`clusters/hub-flux/pocs/capsule.yaml`** — D-11-01 EXTENDS with `spec.patches` block (Role-extending patch for capsule-proxy:capsule-proxy in capsule-system).
- **`pocs/capsule/spoke/config/capsuleconfig.yaml`** — D-11-02 EDITS `spec.userGroups` to 3-group inline list.
- **`pocs/capsule/spoke/tenants/{alpha,bravo}/namespace.yaml`** — D-11-03 ADDS `metadata.labels.capsule.clastix.io/tenant: <name>` inline.
- **`pocs/capsule/spoke/tenants/{alpha,bravo}/tenant.yaml`** — Claude's Discretion (N6 quota fixture, N7 registry allowlist) MAY edit `spec.namespaceOptions.quota` + `spec.containerRegistries`. Planner reads existing shape and reshapes.
- **`.gitleaks.toml`** — D-11-04 APPENDS `'^\.planning/.*\.md$'` to `[allowlist] paths`.
- **`docs/adr/0008-capsule-multi-tenancy-graduation.md`** (NEW) — D-11-14 outcome rubric + D-11-15 EKSDOC cross-reference. Created by Plan 11-05.
- **`docs/capsule-on-eks.md`** — D-11-15 ROLLS FORWARD frontmatter to `Status: Reviewed` + 4 targeted revision blocks (cert source / IRSA / proxy LIST scope / push-gate translation).
- **`docs/poc-capsule.md`** — Phase 11 MAY append H2 "Ordered teardown procedure" section per Plan 11-02 (planner discretion).
- **`tests/bats/negative-rbac-{01..05}-*.bats` + `push-gate-{01..05}-*.bats` + `teardown-{01..04}-*.bats` + `slo-regression-live.bats` + `negative-rbac-anti-pattern-lint-static.bats`** (NEW) — Phase 11 bats files. Plan 11-00 lands all RED; subsequent plans turn GREEN.
- **`tests/fixtures/gitleaks/`** — NO new fixtures expected (Phase 7 D-14 synthetic-kubeconfig.yaml is generic enough; D-11-04 path-allowlist removes the planning-doc trigger).
- **No outer Flux Kustomization changes for tenant inner Ks** in Phase 11. D-09-03 transitional kubeConfig source (`spoke-capsule-kubeconfig`) remains unchanged; `pocs/capsule/tenants/{alpha,bravo}.yaml` remain unchanged. D-10-05 deferral to Phase 12 inheritance preserved.

### Risks (carried from STATE.md Blockers/Concerns + Phase 10 close-out)

- **Phase 10 close-out residual** (`passed_with_overrides` 4 D-08-13 push-gate-deferred + 3 carryover items) — Phase 11 D-11-01..04 + the first push event resolve all residuals. NO new push-gate work after Phase 11.
- **First push event risks** (Plan 11-04) — capsule-proxy chart-level RBAC patch (D-11-01 PostBuild) MUST be in place BEFORE the first push, OR Flux's certgen Job will fail and capsule-proxy will not reconcile cleanly. Order: D-11-01..03 land in Plan 11-01; bats land RED in Plan 11-00; live observations stay RED until Plan 11-04 push event clears them.
- **Negative RBAC SAR cache flake (P37)** — D-11-05 real-CRUD probe shape mitigates; D-11-06 anti-pattern lint enforces; D-11-07 mint-once kubeconfig avoids per-test SA recreation that would invalidate cache.
- **PVC strand at teardown (P36)** — D-11-11 auto force-delete after 60s mitigates.
- **SLO regression test environmental sensitivity** — D-11-13 measures wall-clock `task rebuild` which depends on host load; CID stability is the more reliable assertion. The 230s budget has 40s margin over Phase 5 v0.18 measurement (190s with warm CUDA cache); CI runs may need looser tolerance (Plan 11-04 verifier discretion: skip-if-CI-and-budget-tight, or document the regression test as a local-dev bats not a CI-gate).
- **ADR-008 outcome rubric subjectivity (mitigated)** — D-11-14 evidence-bound rubric makes the outcome mechanical; the only judgment is on REPLACED BY ADR-009 (the 'mid-validation discovery' clause) which is by definition discretionary.

</code_context>

<specifics>
## Specific Ideas

- **D-11-01 PostBuild patch shape — Flux v2.8 spec.patches with name+namespace target.** The patch on `clusters/hub-flux/pocs/capsule.yaml` should use the Flux Kustomization v1's `spec.patches` block (NOT `spec.postBuild.substituteFrom` — that's for variable substitution, not manifest mutation). Example shape (researcher verifies syntax):
  ```yaml
  spec:
    patches:
      - target:
          kind: Role
          name: capsule-proxy:capsule-proxy
          namespace: capsule-system
        patch: |
          - op: add
            path: /rules/-
            value:
              apiGroups: [""]
              resources: ["secrets"]
              verbs: ["get", "create", "update", "patch"]
  ```

- **D-11-09 fail-capsule-webhook script — bats wrapper handles rollout wait.** The script's recovery path (`task fail-capsule-webhook -- 1`) calls `kubectl rollout status --timeout=90s` to ensure the Deployment is Ready before returning. This pushes the wall-clock waiting into the script, NOT into bats setup() — keeps bats N12 @test focused on assertion ("apply succeeds"), not on polling logic.

- **D-11-10 destroy-poc.sh `--full` flag.** When passed, runs step 5 (`k3d cluster delete spoke-capsule`); without, leaves the cluster alive. Flag handling at top of script:
  ```bash
  FULL=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      capsule) shift ;;
      --full) FULL=true; shift ;;
      *) fail "destroy-poc: unknown arg '$1' (usage: destroy-poc -- capsule [--full])" ;;
    esac
  done
  ```

- **D-11-13 SLO bats — handle measurement noise.** `task rebuild` measures real-clock seconds via `date +%s` differential. To handle measurement noise (small variations), the @test asserts `< 230` (NOT `<= 230` — strict ceiling) but the test echoes the actual value for human review (`echo "rebuild elapsed: ${elapsed}s (budget: 230s)"`). If the assertion fires, the operator sees the actual figure and can determine if it's a transient host-load issue or a real regression.

- **D-11-13 BEFORE_CID="MISSING" early-skip.** If spoke-capsule isn't running at bats setup_file() time (the cluster was destroyed for some reason), the bats SKIPS rather than fails — VAL-04 explicitly tests "spoke-capsule survives rebuild," not "spoke-capsule exists." Operator runs `bash scripts/poc/capsule/create-cluster.sh && bash scripts/poc/capsule/register-poc-cluster.sh` first, then re-runs the bats.

- **D-11-14 ADR-008 evidence cross-references.** Each row of the rubric table links to specific bats results (e.g., "All 12/12 N1-N12 PASS" → `tests/bats/negative-rbac-{01..05}-*.bats` GREEN per `11-VERIFICATION.md`). The ADR's "What we proved" section quotes the verifier disposition + counts. Auditable.

- **D-11-15 EKSDOC-01 frontmatter shape.** The frontmatter update reads:
  ```yaml
  ---
  status: Reviewed     # was: Draft
  reviewed: 2026-MM-DD
  reviewed_against: ADR-008 (Capsule Multi-Tenancy POC Graduation)
  reviewed_by: karyon milestone owner
  ---
  ```

- **D-11-04 gitleaks allowlist — minimal regex.** The path-allowlist regex `'^\.planning/.*\.md$'` matches both `.planning/PROJECT.md` and `.planning/phases/07-*/07-RESEARCH.md`. Bats verifies via:
  ```bash
  @test "D-11-04 — .planning/*.md path-allowlist registered" {
    run grep -E "^\s*'\^\\\\.planning/\.\*\\\\.md\\\$'" .gitleaks.toml
    [[ "$status" -eq 0 ]]
  }
  @test "D-11-04 — gitleaks scan exits 0 on full working tree" {
    cd "$REPO_ROOT"
    run gitleaks detect --source . --no-git --redact
    [[ "$status" -eq 0 ]]
  }
  ```

- **Plan 11-04 imperative cleanup before push.** The plan's first task is `helm uninstall capsule-proxy --kube-context=k3d-spoke-capsule -n capsule-system || true` to remove the Plan 10-01 imperative install. The second task verifies the Flux-managed install reconciles cleanly post-push. This ordering ensures the post-push reconcile is the canonical install path (not the imperative artifact lingering in cluster state).

- **N9/N10 cross-tenant probe Kustomizations — tmpdir-rooted, not repo-committed.** Per Claude's Discretion, the N9 + N10 falsifier fixtures are bats-authored at test time inside `${KARYON_BATS_TMPDIR}/n9-cross-tenant-source-XXXX.yaml` (mktemp -p). Avoids polluting `pocs/capsule/` with test fixtures that would themselves be subject to the lockdown patches.

</specifics>

<deferred>
## Deferred Ideas

True deferrals to later phases (already locked at milestone-open or by ROADMAP / REQUIREMENTS un-bundling, restated for plan-side awareness):

- **Phase 9 D-09-03 forward-pointer — tenant inner K kubeConfig source swap.** Continued deferral inheritance from Phase 10 D-10-05. Phase 11 does NOT modify `pocs/capsule/tenants/{alpha,bravo}.yaml`. Phase 12 (capsule-addon-fluxcd) absorbs organically IF ADR-008 outcome ∈ {adopt, defer}; if reject or replaced, the swap becomes future work (post-v0.19, depending on the replacement architecture).
- **`capsule-addon-fluxcd v0.2.3` Trial** → **Phase 12 (OPTIONAL — gated)**. ADR-008 outcome ∈ {adopt, defer} unlocks Phase 12; reject or replaced → SKIP.
- **Multi-SA-per-tenant pattern** — Phase 11 N1-N12 uses Phase 9 D-09-02's `gitops-reconciler` SA per tenant. If future phases (Phase 12 / post-v0.19) introduce per-developer SAs, the bats kubeconfig minting (D-11-07) trivially extends to multiple SAs per tenant.
- **HA Capsule, OIDC, multi-spoke federation, hub-side Capsule, real ingress / TLS for capsule-proxy** → POST-v0.19 milestones (PROJECT.md v0.19 Out-of-Scope). ADR-008 'What we did not prove' section enumerates these.
- **`task rebuild` + `spoke-capsule` lifecycle integration** — explicitly out of scope per ROADMAP P31 invariant: "spoke-capsule MUST NOT enter the default rebuild chain until graduation ADR-008 says 'adopt.'" Phase 11 VAL-04 enforces with static lint; D-11-12 task surface preserves by-location. Post-graduation (if adopt), v0.20 incorporates spoke-capsule into `task rebuild` — that integration is v0.20 work, NOT Phase 12.
- **Network policy (P43) — Capsule auto-creates NetworkPolicy in tenant namespaces** — out of scope for v0.19 (PROJECT.md v0.19 Out-of-Scope: 'Production hardening — lab-only; no HA, no hardened RBAC, no network policies baseline'). Phase 11 N1-N12 does NOT exercise NetworkPolicy enforcement; the focus is RBAC isolation.
- **`task rebuild` SLO measurement on CI** (D-11-13 caveat) — local-dev bats only; CI may run with looser tolerance OR skip-if-CI. v0.20 may add a CI variant of the SLO test if Capsule graduates.
- **Capsule policy-as-code / OPA Gatekeeper integration** — out of scope; Capsule's built-in webhook policies (forceTenantPrefix, namespaceOptions.quota, containerRegistries) are sufficient for N1-N12 coverage. OPA-style policy externalization is post-v0.19.
- **`docs/poc-capsule.md` H2 'Ordered teardown procedure' append** — Claude's Discretion (Plan 11-02). If the planner adds it, cross-link to ADR-008 'Trade-offs' section + D-11-10 5-step sequence + D-11-11 PVC strand mitigation.

### Reviewed Todos (folded into scope — see `<decisions>` "Folded Todos")

- **`2026-04-29-phase-7-gitleaks-planning-doc-allowlist.md` (resolves_phase: 11)** — FOLDED into D-11-04 (Option C broad path-allowlist). The Phase 7 carryover is closed by Phase 11's `.gitleaks.toml` allowlist update; the post-first-push history scan (VAL-05) verifies zero findings. Will auto-close on Phase 11 close-out.

### Out-of-band ideas surfaced during analysis (NOT in current scope)

- None — analysis stayed within Phase 11 scope. The deferral of D-09-03 forward-pointer is preserved per Phase 10 D-10-05 inheritance, not a new discovery.

</deferred>

---

*Phase: 11-validation-graduation-adr-008*
*Context gathered: 2026-05-05*
*Mode: default (interactive — 4 gray areas discussed across 16 turns; 4 questions per area; user selected all 4 areas via initial multi-select)*
