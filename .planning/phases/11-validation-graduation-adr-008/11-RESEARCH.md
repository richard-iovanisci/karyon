# Phase 11: Validation + Graduation ADR-008 - Research

**Researched:** 2026-05-05
**Domain:** Empirical multi-tenancy isolation validation (negative RBAC + webhook failure recovery + clean teardown + SLO regression) + closing graduation ADR for the v0.19 Capsule POC milestone.
**Confidence:** HIGH on Capsule v0.12.4 schema fields (verified against pkg.go.dev v1beta2 API docs), Flux v1 `spec.patches` JSON6902 syntax (verified against fluxcd.io official docs), system:masters webhook bypass (verified against Kubernetes auth docs and Aqua Security write-up), bats setup_file mechanism (verified by tool version probe — Bats 1.11.0 installed). MEDIUM on exact Capsule webhook quota-violation error string (no exact-string match found upstream; bats N6 must use a permissive grep — `quota` OR `namespaces` OR `limit`). MEDIUM on the precise Flux apiserver behavior when an admission webhook with failurePolicy: Fail has zero endpoints (Kubernetes docs are silent on whether the apiserver fast-fails or waits for timeout — empirical observation needed during Plan 11-03).

---

<user_constraints>

## User Constraints (from CONTEXT.md)

### Locked Decisions

CONTEXT.md locks **16 decisions (D-11-01 through D-11-16)** spanning four buckets. Treat as binding; the planner MUST honor each.

**Push-gate carryover + first push event (VAL-05 + Phase 10 carryover):**

- **D-11-01:** **PostBuild patch on the outer K** — `clusters/hub-flux/pocs/capsule.yaml`. Add a `spec.patches` block extending the chart-rendered Role `capsule-proxy:capsule-proxy` in `capsule-system` namespace with `[secrets get/create/update/patch]` rules so the `kube-webhook-certgen` Job can write its output Secret on initial Flux reconcile. Mirrors Phase 9 D-09-05 patch surface pattern.
- **D-11-02:** **Update repo file directly** — edit `pocs/capsule/spoke/config/capsuleconfig.yaml` to inline `spec.userGroups: [capsule.clastix.io, system:serviceaccounts, system:authenticated]`.
- **D-11-03:** **Add label inline to namespace YAML** — edit `pocs/capsule/spoke/tenants/{alpha,bravo}/namespace.yaml` to include `metadata.labels.capsule.clastix.io/tenant: <name>`. Trust that the cluster-admin Flux apply path bypasses Capsule's webhook prefix-violation check.
- **D-11-04:** **Option C — broad path-allowlist for `.planning/*.md`** — append `'^\.planning/.*\.md$'` to `.gitleaks.toml` `[allowlist] paths` list (parallel to existing `^\.env\.example$`). Folds Phase 7 carryover todo `2026-04-29-phase-7-gitleaks-planning-doc-allowlist.md`.

**Negative RBAC probe strategy (VAL-01):**

- **D-11-05:** **Real CRUD apply path, single probe** — each Nk asserts `kubectl get/create/...` returns non-zero with a specific error string. NOT `kubectl auth can-i` (SAR cache flake — research P37). Bypasses SAR cache.
- **D-11-06:** **5 bats files** grouped by attack class:
  - `tests/bats/negative-rbac-01-cross-tenant-list.bats` (N1, N2, N3)
  - `tests/bats/negative-rbac-02-escalation.bats` (N4)
  - `tests/bats/negative-rbac-03-webhook-policy.bats` (N5, N6, N7)
  - `tests/bats/negative-rbac-04-bypass-and-flux.bats` (N8, N9, N10)
  - `tests/bats/negative-rbac-05-webhook-down.bats` (N11, N12)
- **D-11-07:** **Mint once in `setup_file()` per bats file, cache to tmpdir** with `--duration=2h`. Pattern: `${TMPDIR:-/tmp}/karyon-tenants/bats-${BATS_RUN_TMPDIR##*/}`.
- **D-11-08:** **Reuse Phase 10 D-10-08 falsifier pattern with Pitfall 10-P3 corrected shape.** Extract token from $ALPHA_KUBECONFIG via yq, build minimal direct-apiserver kubeconfig (server: https://127.0.0.1:6446), assert qualitative 403 + `cannot list resource "namespaces"` error string.

**Webhook failure + teardown (VAL-02 / VAL-03):**

- **D-11-09:** **Scale Deployment to 0 (fail) / 1 (recover)** via `scripts/poc/capsule/fail-capsule-webhook.sh`. Recovery path includes `kubectl rollout status --timeout=90s`.
- **D-11-10:** **`scripts/poc/capsule/destroy-poc.sh`** runs strict 5-step canonical sequence: suspend tenant inner Ks + outer-K → delete Tenant CRs → poll namespace cascade → suspend operator+config outer Ks → optional `--full` for `k3d cluster delete spoke-capsule`.
- **D-11-11:** **Auto force-delete PVCs after 60s timeout** with `kubectl patch pvc {} -p '{"metadata":{"finalizers":null}}' --type=merge` per research P36 prevention #4.
- **D-11-12:** **Top-level Taskfile.yml entries** — `task fail-capsule-webhook -- 0|1` and `task destroy-poc -- capsule [--full]`. P31 invariant preserved BY LOCATION (scripts under `scripts/poc/capsule/`, NOT v0.18 script set).

**SLO regression + ADR-008 rubric (VAL-04 / VAL-06):**

- **D-11-13:** **`tests/bats/slo-regression-live.bats`** — single bats file, ~4 @tests: VAL-04a `task rebuild < 230s`; VAL-04b k3d-spoke-capsule-server-0 CID unchanged; VAL-04c `task health-check` exit 0; VAL-04d Phase 7 P31 lint inheritance. Live-skip gating via `BEFORE_CID="MISSING"` if spoke-capsule down.
- **D-11-14:** **Evidence-bound rubric** — outcome ∈ {ADOPT, DEFER, REJECT, REPLACED BY ADR-009}. Each row mechanically mapped to bats results. Nygard 4-section + 3 sub-sections (What we proved / What we did not prove / Trade-offs).
- **D-11-15:** **EKSDOC-01 rollforward** — `docs/capsule-on-eks.md` frontmatter `Status: Reviewed` + 4 targeted revision blocks (cert source / IRSA / proxy LIST scope / push-gate translation).
- **D-11-16:** **Inherit verbatim** — `tests/bats/poc-isolation-01-static.bats` (Phase 7 D-12 / P31 lint). Phase 11 VAL-04 reuses verbatim as @test d in `slo-regression-live.bats`.

### Claude's Discretion

The following gray areas are intentionally NOT specified — planner/researcher should default to v0.18 + Phase 7/8/9/10 patterns and note the chosen approach in PLAN.md without re-asking:

- **N6 quota fixture** — Tenant CR `spec.namespaceOptions.quota`. Recommended default: `quota: 3` for both tenants.
- **N7 registry fixture** — Tenant CR `spec.containerRegistries`. Recommended default: `containerRegistries: {allowed: ["registry.example.io"]}` (researcher verifies syntax — see Standard Stack table below).
- **N9 cross-tenant sourceRef fixture** — bats authors a probe Kustomization YAML in tmpdir at test-time (NOT a repo-committed fixture).
- **N10 missing serviceAccountName fixture** — same shape as N9 (tmpdir-rooted).
- **Stdout/stderr split** for new scripts — mirror Phase 10 D-10-09 pattern.
- **Idempotency** for both new scripts — mirror Phase 10 (re-running is safe).
- **Plan ordering granularity** — Default 5-plan recommendation; planner may merge/split per surface complexity.
- **ADR-008 file naming** — Recommended: `docs/adr/0008-capsule-multi-tenancy-graduation.md`.
- **Verifier script wrapper** — bats-only (no `verify-validation.sh` wrapper).
- **Reconcile loop noise tolerance** — ≤2 reconcile cycles; live-bats retry budget: 3 attempts × 30s sleep.

### Deferred Ideas (OUT OF SCOPE)

Out of scope — planner MUST NOT pull these into Phase 11 plans:

- **Phase 9 D-09-03 forward-pointer — tenant inner K kubeConfig source swap** → Phase 12 (capsule-addon-fluxcd) absorbs organically IF ADR-008 outcome ∈ {adopt, defer}.
- **`capsule-addon-fluxcd v0.2.3` Trial** → **Phase 12 (OPTIONAL — gated)**. ADR-008 outcome ∈ {adopt, defer} unlocks Phase 12; reject or replaced → SKIP.
- **Multi-SA-per-tenant pattern** — future phase.
- **HA Capsule, OIDC, multi-spoke federation, hub-side Capsule, real ingress / TLS for capsule-proxy** → POST-v0.19 milestones.
- **`task rebuild` + `spoke-capsule` lifecycle integration** — explicitly out of scope per ROADMAP P31 invariant. Post-graduation (if adopt), v0.20 incorporates spoke-capsule into `task rebuild`.
- **Network policy (P43)** — out of scope for v0.19; Phase 11 N1-N12 does NOT exercise NetworkPolicy enforcement.
- **`task rebuild` SLO measurement on CI** (D-11-13 caveat) — local-dev bats only.
- **Capsule policy-as-code / OPA Gatekeeper** — out of scope.
- **`docs/poc-capsule.md` H2 'Ordered teardown procedure' append** — Claude's Discretion (Plan 11-02 — optional).

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| **VAL-01** | Negative RBAC bats suite (N1–N12 falsifiers) all PASS | D-11-05 real-CRUD probe shape + D-11-06 5-bats partition. Standard Stack confirms Capsule v0.12.4 schema fields for N6 (`spec.namespaceOptions.quota: *int32`) and N7 (`spec.containerRegistries: {allowed: [...], allowedRegex: "..."}`). N8 reuses Phase 10 D-10-08 falsifier (Pitfall 10-P3 corrected shape). N9/N10 use Flux multi-tenancy lockdown — `--no-cross-namespace-refs=true` + `--default-service-account=default` (Phase 9 TEN-05 inheritance). |
| **VAL-02** | Capsule webhook failure mode is observed and recoverable | D-11-09 scale Deployment 0/1. **Confirmed:** Capsule v0.12.4 chart sets `webhooks.namespaces.failurePolicy: Fail`, `webhooks.pods.failurePolicy: Fail`, `webhooks.tenants.failurePolicy: Fail`. With Fail policy + zero endpoints (Deployment scaled to 0), apiserver returns `failed calling webhook ... no endpoints available for service` IMMEDIATELY (not after timeout). N12 recovery polls rollout-status with 90s budget (verified sufficient based on Capsule controller startup time of ~30-60s per research P26). |
| **VAL-03** | Clean teardown via `task destroy-poc capsule` | D-11-10 strict 5-step canonical + D-11-11 PVC strand mitigation. Sentinel preservation: `KARYON POC MOUNT` line in `clusters/hub-flux/flux-system/kustomization.yaml` UNCHANGED post-teardown. |
| **VAL-04** | `task rebuild` SLO regression test PASSES | D-11-13 bats wraps `time` + docker CID compare. Baseline: v0.18 measured 190s with warm CUDA cache (research P31); 230s budget = 190s + 40s margin. Container name `k3d-spoke-capsule-server-0` confirmed via live `docker ps` probe. Phase 7 P31 lint reused verbatim as @test d. |
| **VAL-05** | One-shot history gitleaks scan post-Phase-10 first push returns 0 findings | D-11-04 gitleaks `.planning/*.md` allowlist. Verified: gitleaks 8.30.1 (project-pinned) supports path-based regex allowlist via `[allowlist] paths`. Scan command: `gitleaks detect --source . --no-git --redact` for working tree; `gitleaks git --log-opts="--all"` for full history (matches CI gitleaks-scan job). |
| **VAL-06** | Graduation ADR-008 written | D-11-14 evidence-bound rubric + D-11-15 EKSDOC-01 rollforward. Nygard 4-section template (Status / Context / Decision / Consequences) verified against existing ADRs 0001-0005. |

</phase_requirements>

## Summary

Phase 11 closes the v0.19 Capsule POC milestone by producing empirical evidence (negative RBAC + webhook failure recovery + clean teardown + SLO regression) and the graduation ADR-008. The phase has unusually low novel-decision surface — 16 decisions are already locked in CONTEXT.md, and the validation strategy directly inherits Phase 7-10 bats patterns (Wave 0 RED scaffold, mint-once kubeconfig in setup_file, tmpdir-rooted ephemeral artifacts).

**Research's job is verification, not exploration.** This RESEARCH.md confirms (1) the exact schema field names + types Capsule v0.12.4 uses for the N6 / N7 fixtures (verified `*int32 quota` and `AllowedListSpec {allowed, allowedRegex}` shapes), (2) the Flux v1 `spec.patches` JSON6902 syntax that D-11-01's PostBuild patch must follow (verified via fluxcd.io), (3) the Capsule webhook objectSelector semantics that make D-11-03's "trust cluster-admin Flux apply" assumption load-bearing (Capsule's tenantLabel webhook has `namespaceSelector: matchExpressions: [{key: capsule.clastix.io/tenant, operator: Exists}]` — meaning a freshly-Flux-applied Namespace YAML carrying the label tags itself, but the webhook's prefix-enforcement check applies to namespace CREATE regardless of label), (4) the apiserver fast-fail behavior when admission webhooks have zero endpoints (verified via Kubernetes docs — apiserver returns `failed calling webhook ... no endpoints available` immediately, not after timeout), and (5) the Nygard 4-section ADR template structure that ADR-008 must follow.

**Primary recommendation:** Adopt CONTEXT.md's 5-plan structure verbatim (Plan 11-00 Wave 0 RED → Plan 11-01 push-gate persistent fixes → Plan 11-02 POC scripts + Taskfile → Plan 11-03 negative RBAC GREEN waves → Plan 11-04 push event + verifier → Plan 11-05 ADR-008 + EKSDOC-01 rollforward). The CONTEXT.md surface is exhaustive — research surfaces three concrete syntax verifications (Tenant CR fields, Flux patches block, ADR Nygard template) and one assumption to flag (D-11-03 cluster-admin Flux apply may still trigger Capsule's namespace webhook for the `capsule.clastix.io/tenant` label — empirical verification required at first-push event during Plan 11-04).

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Negative RBAC probes (N1-N12) | Test Harness (bats) | Tenant kubeconfig (proxy + apiserver) | bats orchestrates `kubectl --kubeconfig=...` calls; the cluster (Capsule webhook + apiserver RBAC) enforces the boundary; the tenant kubeconfig is the inert payload that probes both. |
| Push-gate persistent fixes (D-11-01..04) | GitOps source-of-truth (Flux + repo) | Cluster runtime (post-reconcile) | The repo files (`clusters/hub-flux/pocs/capsule.yaml`, `pocs/capsule/spoke/config/capsuleconfig.yaml`, `pocs/capsule/spoke/tenants/{alpha,bravo}/namespace.yaml`, `.gitleaks.toml`) are the canonical source. Cluster state is downstream of Flux reconcile. |
| Webhook failure simulation | POC test script (`fail-capsule-webhook.sh`) | Cluster runtime (Deployment scaled 0/1) | The script is a thin imperative wrapper; the real test is the apiserver/webhook chain returning `failed calling webhook ... no endpoints available`. |
| Ordered teardown (`destroy-poc.sh`) | POC test script | Cluster runtime (cascade) + Flux (suspend) | The script orchestrates `flux suspend` + `kubectl delete tenant` + cascade-poll + `kubectl patch pvc` + optional `k3d delete`. Each command targets a different layer (hub Flux / spoke kubectl / spoke kubectl / docker). |
| SLO regression measurement | bats wrapper around `task rebuild` | Docker (CID compare) + bash `date +%s` | Wall-clock measurement is bash-side; CID compare is docker-side; the assertion is bats-side. Cluster state is irrelevant to the metric. |
| ADR-008 write | Documentation tier (`docs/adr/`) | None — pure markdown artifact | Not a code change; not a cluster change. Decision artifact backed by VAL-01..05 evidence. |
| EKSDOC-01 rollforward | Documentation tier (`docs/`) | None — pure markdown artifact | Same as above. Cross-references ADR-008. |

## Standard Stack

### Core (verified versions)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Bats (Bash Automated Testing System) | 1.11.0 (live-verified by `bats --version`) | Test framework for all 11 new bats files | `setup_file()` / `teardown_file()` available since 1.5+ — confirmed working in Phase 7-10. CONFIRMED INSTALLED. [VERIFIED: `bats --version` 2026-05-05] |
| gitleaks | 8.30.1 (project-pinned per `.gitleaks.toml` line 21 minVersion comment; live-verified by `gitleaks version`) | Secret-scanning for VAL-05 first-push event | Multi-line regex via `(?ms)` since 8.25.0. Path-based `[allowlist] paths` regex syntax stable. CONFIRMED INSTALLED. [VERIFIED: `gitleaks version` 2026-05-05] |
| flux CLI | bin present; `flux version` reports `no deployments found in flux-system namespace` (running outside hub context — expected) | `flux suspend` calls in `destroy-poc.sh`; `flux reconcile` in operator runbook | Flux 2.x kustomize-controller v1 supports `spec.patches` block. [CITED: fluxcd.io/flux/components/kustomize/kustomizations/] |
| kubectl | v1.35.0 (live-verified) | All apiserver interactions across bats + scripts | k3s pinned at v1.34.6-k3s1 (ADR-005); kubectl 1.35 is one minor newer (within ±1 minor support window). [VERIFIED: `kubectl version --client` 2026-05-05] |
| yq | v4.53.2 (live-verified) | YAML parsing in bats setup_file (extract bearer tokens, jsonpath fallback) | Used by Phase 10 issue-tenant-kubeconfig.sh; reused verbatim in Phase 11 setup_file. [VERIFIED: `yq --version` 2026-05-05] |
| Capsule | v0.12.4 (locked in STACK.md per ADR; chart `oci://ghcr.io/projectcapsule/charts/capsule:0.12.4`) | Tenant CR + CapsuleConfiguration + webhook backend | Pinned in HelmRelease at hub-flux per Phase 8. [CITED: STACK.md] |
| capsule-proxy | 0.12.0 (locked in STACK.md; chart `oci://ghcr.io/projectcapsule/charts/capsule-proxy:0.12.0`) | LIST filtering at proxy edge for tenant kubeconfigs | Pinned in HelmRelease at hub-flux per Phase 8. [CITED: STACK.md] |
| k3s | rancher/k3s:v1.34.6-k3s1 (ADR-005 pin) | spoke-capsule cluster runtime | Confirmed `k3d-spoke-capsule-server-0` container alive via `docker ps`. [VERIFIED: `docker ps` 2026-05-05] |
| Taskfile (go-task) | v3 (uses `{{.CLI_ARGS}}` idiom) | Top-level POC tasks (D-11-12) | Existing repo Taskfile already on v3 (`version: '3'` at top of Taskfile.yml). [VERIFIED: cat Taskfile.yml 2026-05-05] |

### Supporting (Phase-11-specific)

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| jq | system default | PVC list parsing in `destroy-poc.sh` step 3 | `kubectl get pvc -A -l capsule.clastix.io/tenant= -o json \| jq -r '.items[] \| "\(.metadata.namespace)/\(.metadata.name)"'` per D-11-11 |
| openssl | system default | TLS SAN verification (Phase 7 inheritance — bats-internal); not new for Phase 11 | Reused from create-cluster.sh; no Phase 11 changes |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `kubectl auth can-i` for negative RBAC | Real `kubectl get/create/...` apply path (D-11-05) | SAR cache (5min authorizedTTL / 30s unauthorizedTTL — verified via Kubernetes docs) returns stale results; real-apply path bypasses cache entirely. **Locked.** |
| One bats file per N1-N12 | 5 bats files grouped by attack class (D-11-06) | Per-N files explode bats-run time and prevent shared setup_file (proxy CA read, kubeconfig mint). **Locked.** |
| Single negative-rbac.bats file | 5 bats files (D-11-06) | Single file means one RED test fails the whole suite; partition gives failure-class isolation. **Locked.** |
| `kubectl rollout undo` for D-11-09 recovery | `kubectl scale --replicas=1` + `kubectl rollout status` | Undo presumes a prior rollout history; scale is deterministic from the test's perspective. **Locked.** |
| Inline ADR-008 + EKSDOC-01 in one plan | Separate plans (Plan 11-05 only does both files) | They're tightly coupled (EKSDOC cross-references ADR); keeping them in one plan simplifies the commit. **Locked.** |

**Installation:** Already installed; no new tooling.

**Version verification (live-confirmed 2026-05-05):**
- `bats --version` → `Bats 1.11.0` ✓
- `gitleaks version` → `8.30.1` ✓
- `kubectl version --client` → `v1.35.0` ✓
- `yq --version` → `v4.53.2` ✓
- `docker ps` shows `k3d-spoke-capsule-server-0` alive ✓

## Architecture Patterns

### System Architecture Diagram

Phase 11 has three orthogonal validation flows. The diagram shows how each validation request enters the system, the components it traverses, and what produces the assertion result.

```
        ┌─────────────────────────────────────────────────────────────────┐
        │                        OPERATOR (WSL2 host)                      │
        │   bats tests/bats/{negative-rbac-NN, push-gate-NN,               │
        │                    teardown-NN, slo-regression-live}.bats         │
        └─────────────────┬─────────────────┬───────────────────┬──────────┘
                          │                 │                   │
        ┌─────────────────▼───┐  ┌──────────▼──────────┐  ┌─────▼──────────┐
        │  setup_file()        │  │  task rebuild      │  │  task           │
        │  (mint-once cache)   │  │  (SLO measure)     │  │  destroy-poc   │
        │  ↓                   │  │  ↓                 │  │  capsule        │
        │  issue-tenant-       │  │  date +%s start    │  │  ↓             │
        │  kubeconfig.sh       │  │  ↓                 │  │  flux suspend   │
        │  → TokenRequest API  │  │  scripts/rebuild.sh│  │  → kubectl     │
        │  → tmpdir kubeconfig │  │  ↓                 │  │    delete      │
        └──────────┬───────────┘  │  date +%s end      │  │    tenant CRs  │
                   │              │  ↓                 │  │  → poll cascade │
                   │              │  docker inspect    │  │  → patch PVC   │
                   │              │  CID compare       │  │    finalizers   │
                   │              └────────────────────┘  └────────┬───────┘
                   │                                                │
        ┌──────────▼──────────────────────────────────────┐         │
        │  N1-N12 PROBES (real CRUD apply, NOT auth can-i) │         │
        │                                                  │         │
        │  ┌─────────────┐    ┌─────────────────────┐    │         │
        │  │ Tenant      │───▶│ capsule-proxy       │    │         │
        │  │ kubeconfig  │    │ NodePort 30443      │    │         │
        │  │ (alpha or   │    │ ↓ LIST filter       │    │         │
        │  │  bravo)     │    │ ↓ (tenant own ns)   │    │         │
        │  └─────────────┘    └──────────┬──────────┘    │         │
        │                                │                │         │
        │  ┌─────────────┐                ▼                │         │
        │  │ N8 direct   │───▶ apiserver :6446            │         │
        │  │ apiserver   │     ↓ Capsule webhook chain    │         │
        │  │ tmpfile     │     ↓ (admission valid+mutate) │         │
        │  │ kubeconfig  │     ↓ apiserver RBAC           │         │
        │  └─────────────┘     ↓ DENY (403 + error str)   │         │
        │                                                  │         │
        │  ┌─────────────┐                                │         │
        │  │ N11/N12     │───▶ kubectl scale deploy 0/1   │         │
        │  │ webhook     │     ↓ (apiserver detects)      │         │
        │  │ down probe  │     ↓ "no endpoints available" │         │
        │  └─────────────┘     ↓ (failurePolicy: Fail)    │         │
        └──────────────────────────────────────────────────┘         │
                                                                     │
        ┌────────────────────────────────────────────────────────────▼┐
        │                  SPOKE-CAPSULE CLUSTER                       │
        │   ┌──────────────────────┐  ┌──────────────────────────┐    │
        │   │ capsule-controller-  │  │ capsule-proxy             │    │
        │   │ manager (webhook     │  │ (LIST filter at proxy)   │    │
        │   │ backend; scaled 0/1  │  │                            │    │
        │   │ for VAL-02)          │  │                            │    │
        │   └──────────────────────┘  └──────────────────────────┘    │
        │   ┌──────────────────────────────────────────────────┐      │
        │   │ Tenant CRs: alpha, bravo                          │      │
        │   │ Namespaces: tenant-alpha, alpha-app1, tenant-     │      │
        │   │ bravo, bravo-app1 (all labeled                    │      │
        │   │ capsule.clastix.io/tenant=<name>)                 │      │
        │   └──────────────────────────────────────────────────┘      │
        └─────────────────────────────────────────────────────────────┘
                          ▲
                          │ (Flux reconcile from hub-flux outer Ks)
                          │
        ┌─────────────────┴───────────────────────────────────────────┐
        │                  HUB-FLUX CLUSTER                            │
        │   ┌──────────────────────────────────────────────────┐      │
        │   │ kustomize-controller (Flux 2.x)                  │      │
        │   │ + helm-controller                                 │      │
        │   │ ↓ Outer Ks: poc-capsule (hub-targeted),          │      │
        │   │            poc-capsule-spoke (spoke-targeted),    │      │
        │   │            tenant-alpha-app, tenant-bravo-app    │      │
        │   │ ↓ D-11-01 spec.patches (RBAC extension on        │      │
        │   │   capsule-proxy:capsule-proxy Role)              │      │
        │   └──────────────────────────────────────────────────┘      │
        └─────────────────────────────────────────────────────────────┘
```

### Recommended Project Structure (NEW Phase 11 surface)

```
.
├── clusters/
│   └── hub-flux/
│       └── pocs/
│           └── capsule.yaml                    # EDITED: D-11-01 add spec.patches
├── pocs/
│   └── capsule/
│       └── spoke/
│           ├── config/
│           │   └── capsuleconfig.yaml          # EDITED: D-11-02 add 3-group userGroups
│           └── tenants/
│               ├── alpha/
│               │   ├── namespace.yaml          # EDITED: D-11-03 add tenant label
│               │   └── tenant.yaml             # OPTIONAL: N6 quota + N7 registries fixture
│               └── bravo/
│                   ├── namespace.yaml          # EDITED: D-11-03 add tenant label
│                   └── tenant.yaml             # OPTIONAL: N6 quota + N7 registries fixture
├── scripts/
│   └── poc/
│       └── capsule/
│           ├── destroy-poc.sh                  # NEW: D-11-10 + D-11-11
│           └── fail-capsule-webhook.sh         # NEW: D-11-09
├── tests/
│   └── bats/
│       ├── negative-rbac-01-cross-tenant-list.bats        # NEW: D-11-06 (N1-N3)
│       ├── negative-rbac-02-escalation.bats               # NEW: D-11-06 (N4)
│       ├── negative-rbac-03-webhook-policy.bats           # NEW: D-11-06 (N5-N7)
│       ├── negative-rbac-04-bypass-and-flux.bats          # NEW: D-11-06 (N8-N10)
│       ├── negative-rbac-05-webhook-down.bats             # NEW: D-11-06 (N11-N12)
│       ├── negative-rbac-anti-pattern-lint-static.bats    # NEW: D-11-05 enforcement
│       ├── push-gate-01-static-rbac-postbuild.bats        # NEW: D-11-01
│       ├── push-gate-02-static-capsuleconfig.bats         # NEW: D-11-02
│       ├── push-gate-03-static-tenant-ns-label.bats       # NEW: D-11-03 static
│       ├── push-gate-04-live-tenant-ns-flux-apply.bats    # NEW: D-11-03 live
│       ├── push-gate-05-static-gitleaks-allowlist.bats    # NEW: D-11-04
│       ├── teardown-01-static-script.bats                 # NEW: D-11-10
│       ├── teardown-02-static-sentinel-preservation.bats  # NEW: D-11-10
│       ├── teardown-03-live-ordered.bats                  # NEW: D-11-10
│       ├── teardown-04-live-pvc-strand-mitigation.bats    # NEW: D-11-11
│       └── slo-regression-live.bats                       # NEW: D-11-13 (4 @tests)
├── docs/
│   ├── adr/
│   │   └── 0008-capsule-multi-tenancy-graduation.md       # NEW: D-11-14
│   └── capsule-on-eks.md                                  # EDITED: D-11-15
├── .gitleaks.toml                              # EDITED: D-11-04 add planning allowlist
└── Taskfile.yml                                # EDITED: D-11-12 add 2 top-level entries
```

**Total Phase 11 surface:** 2 NEW scripts; 11 NEW bats files; 1 NEW ADR; 6 EDITED files (1 outer-K + 1 CapsuleConfig + 2 namespace.yaml + 1 .gitleaks.toml + 1 Taskfile.yml + 1 EKSDOC roll-forward); 2 OPTIONAL Tenant CR fixture extensions.

### Pattern 1: Flux v1 spec.patches with JSON6902 op:add (D-11-01)

**What:** Extend a chart-rendered Role across remote cluster via Flux outer Kustomization PostBuild patches.
**When to use:** When the chart-rendered RBAC has a gap (capsule-proxy chart's `capsule-proxy:capsule-proxy` Role lacks `secrets create/update/patch`) and you can't fork the chart.

```yaml
# Source: https://fluxcd.io/flux/components/kustomize/kustomizations/
# (verified against Flux Kustomization v1 spec; CITED 2026-05-05)
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: poc-capsule
  namespace: flux-system
spec:
  interval: 5m
  path: ./pocs/capsule
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  serviceAccountName: kustomize-controller
  patches:
    - patch: |
        - op: add
          path: /rules/-
          value:
            apiGroups: [""]
            resources: ["secrets"]
            verbs: ["get", "create", "update", "patch"]
      target:
        kind: Role
        name: capsule-proxy:capsule-proxy
        namespace: capsule-system
```

**Critical syntax notes (verified):**
- `patch:` value MUST be a literal block scalar (`|`) — JSON6902 ops are a YAML list of objects.
- Each op object has `op`, `path` (RFC 6901 JSON pointer; `/rules/-` appends to array), and `value`.
- `target:` selects which rendered manifest the patch applies to. Supports `kind`, `name`, `namespace`, `group`, `version`, `labelSelector`, `annotationSelector`. **`kind` is required.** [CITED: fluxcd.io/flux/components/kustomize/kustomizations/]
- The patch is applied AFTER `kustomize build` but BEFORE the apply to the target cluster — so it modifies the chart-rendered Role in-flight.
- For this Phase 11 case, the outer K (`poc-capsule`) is HUB-TARGETED (no `spec.kubeConfig`) per D-08-12 split-path architecture. The Role lives in `capsule-system` ON THE SPOKE — but the chart that renders it is a HelmRelease applied via hub-flux's helm-controller using `spec.kubeConfig` on the HelmRelease itself. The PostBuild patch on the outer K patches the rendered HelmRelease + OCIRepository CRs (which live on hub) — NOT the Role itself. **Researcher flag:** D-11-01's mechanism may need to use a different surface. The patch on the outer K targets `Role` kind, but the outer K renders HelmRelease + OCIRepository, not Role. **Investigate:** does Flux's PostBuild patch apply to Helm-rendered manifests downstream, or only to kustomize-build output? See "Open Questions" section.

### Pattern 2: bats setup_file mint-once cache (D-11-07)

**What:** Mint each tenant kubeconfig once per bats file, cache to tmpdir, export env var, teardown_file removes.
**When to use:** Per Phase 11 D-11-07 — every negative-rbac-*.bats file. Avoids re-running TokenRequest API per-test.

```bash
# Source: bats v1.5+ setup_file/teardown_file specification
# (verified bats --version: 1.11.0)

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

teardown_file() {
  rm -rf "$KARYON_BATS_TMPDIR"
}
```

**Critical notes (verified):**
- `BATS_RUN_TMPDIR` is set by bats per-run (verified via Bats docs); using `${BATS_RUN_TMPDIR##*/}` extracts the run-specific suffix to avoid cross-file collisions.
- Variables exported in `setup_file()` are visible in all `@test` functions in that file (verified Phase 7-10 pattern).
- `--duration=2h` matches CONTEXT.md D-11-07; covers slow bats runs without re-minting tokens. k3s does NOT clamp at 24h per Phase 10 D-10-02 (verified).
- The kubeconfig writes to `${TMPDIR:-/tmp}/karyon-tenants/` (matches Phase 10 issue-tenant-kubeconfig.sh contract); P29 invariant preserved by location.

### Pattern 3: Live-skip gating with BEFORE_CID="MISSING" (D-11-13)

**What:** When the cluster the bats need is destroyed, SKIP the test rather than fail.
**When to use:** Phase 11 SLO regression test — VAL-04 explicitly tests "spoke-capsule survives rebuild," not "spoke-capsule exists."

```bash
# Source: D-11-13 in CONTEXT.md (locked decision)
setup_file() {
  export REPO_ROOT="$(git rev-parse --show-toplevel)"
  export BEFORE_CID=$(docker inspect -f '{{.Id}}' k3d-spoke-capsule-server-0 2>/dev/null || echo "MISSING")
  [[ "$BEFORE_CID" != "MISSING" ]] || skip "spoke-capsule not running — VAL-04 requires live spoke-capsule for CID stability assertion"
}
```

**Critical notes:**
- `bats skip` exits the test as SKIP, not FAIL — operator sees explanatory message in TAP output.
- The skip message is the operator runbook trigger — they run `bash scripts/poc/capsule/create-cluster.sh && bash scripts/register-poc-cluster.sh` then re-run bats.

### Pattern 4: Phase 7 P31 lint inheritance (D-11-16)

**What:** Reuse `tests/bats/poc-isolation-01-static.bats` verbatim as @test d in `slo-regression-live.bats`.
**When to use:** Phase 11 VAL-04 @test d — the static safety net asserting v0.18 scripts have ZERO `spoke-capsule` mentions.

```bash
@test "VAL-04 d — P31 static lint via Phase 7 inheritance" {
  cd "$REPO_ROOT"
  run bats tests/bats/poc-isolation-01-static.bats
  [[ "$status" -eq 0 ]]
}
```

**Critical notes:**
- Phase 7 already validated 6/6 across Phases 8/9/10 — re-running it is the regression gate.
- The lint excludes `scripts/poc/` from its scope (POC scripts ARE allowed to mention spoke-capsule).
- Phase 11's NEW POC scripts (`destroy-poc.sh`, `fail-capsule-webhook.sh`) live under `scripts/poc/capsule/` — excluded by location.

### Anti-Patterns to Avoid

- **`kubectl auth can-i` for negative RBAC:** SAR cache (5min/30s default TTLs verified via kube-apiserver docs) returns stale results; use real-CRUD apply path per D-11-05. **Anti-pattern lint:** `negative-rbac-anti-pattern-lint-static.bats` greps `tests/bats/negative-rbac-*.bats` for `kubectl auth can-i` and asserts ZERO matches.
- **Single-file bats for all 12 N falsifiers:** One RED test fails the whole suite; partition by attack class per D-11-06.
- **Non-tmpdir kubeconfig storage:** P29 invariant — tenant kubeconfigs MUST NOT land in repo. setup_file() writes to `${TMPDIR:-/tmp}/karyon-tenants/`.
- **Quantitative N8 falsifier (count comparison):** Phase 10 Pitfall 10-P3 — Capsule's namespace-scoped RBAC denies cluster-wide LIST regardless. Use qualitative 403 + error string match per D-11-08.
- **Modifying `clusters/hub-flux/flux-system/kustomization.yaml` in destroy-poc:** sentinel preservation guarantee. The script reads (does NOT modify) the file. Bats teardown-02 asserts no modification.
- **Helm uninstall as last action in destroy-poc:** Per D-11-10, suspend operator+config Ks (preserve GitOps install state); only `--full` flag deletes the cluster.
- **`kubectl rollout status` without timeout:** D-11-09 uses `--timeout=90s` to bound recovery wait. Capsule controller startup is ~30-60s per research P26.
- **Hardcoded SLO threshold without echo:** D-11-13 — `[[ "$elapsed" -lt 230 ]] || { echo "actual: ${elapsed}s"; return 1; }`. Echo lets operator distinguish transient host load from real regression.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Tenant kubeconfig minting | Custom token-fetch script | Phase 10 `scripts/poc/capsule/issue-tenant-kubeconfig.sh` (D-10-01 TokenRequest API) | Already validated; uses k8s-native TokenRequest API; tmpdir-rooted; P29 leak-defense built in. |
| Webhook-down test rig | Custom in-cluster killer pod | `kubectl scale deploy capsule-controller-manager --replicas=0` (D-11-09) | Native k8s primitive; idempotent; reversible; the apiserver's "no endpoints" detection is the test signal. |
| PVC stranded cleanup | Manual delete loop | `kubectl patch pvc {} -p '{"metadata":{"finalizers":null}}' --type=merge` (D-11-11) | Canonical force-delete pattern (per Kubernetes finalizer docs); idempotent; bypass pvc-protection finalizer is acceptable for POC. |
| Negative-RBAC probes | `kubectl auth can-i` (returns SAR cache) | Real `kubectl get/create/...` apply path (D-11-05) | Real apply path goes through validating webhooks AND apiserver auth in one shot; bypasses 5min SAR cache TTL. |
| ADR template | Custom markdown structure | Nygard 4-section template (Status / Context / Decision / Consequences) | Project precedent: ADRs 0001-0005 follow this structure. Adding 3 sub-sections under Decision ("What we proved / What we did not prove / Trade-offs") matches CONTEXT.md D-11-14. |
| SLO measurement | Custom timer wrapper | `date +%s` differential + `docker inspect -f '{{.Id}}'` | Bash-native; deterministic; no external dependencies. |
| Gitleaks allowlist regex | Custom path matching | `[allowlist] paths` regex `'^\.planning/.*\.md$'` (D-11-04) | gitleaks 8.x stable feature; matches existing `^\.env\.example$` precedent in repo. |

**Key insight:** Phase 11's job is to ASSEMBLE existing primitives (Phase 7-10 scripts, k8s native CLI, gitleaks/bats/yq), NOT to invent new mechanisms. The 2 NEW scripts (`destroy-poc.sh` + `fail-capsule-webhook.sh`) are thin orchestration wrappers around `flux suspend` + `kubectl delete/scale/patch` — no novel logic.

## Runtime State Inventory

> Phase 11 is mostly a code/test/doc phase, but VAL-05 first push event + Plan 11-04 imperative-state cleanup involves runtime state. Inventory required.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| **Stored data** | None — Phase 11 produces no new persistent data. Test fixtures are tmpdir-rooted (D-11-07). | None. |
| **Live service config** | (1) **CapsuleConfiguration `default` singleton on spoke-capsule** — currently has `userGroups: [capsule.clastix.io]` only (verified by reading `pocs/capsule/spoke/config/capsuleconfig.yaml`); Plan 10-02 patched LIVE to add `system:serviceaccounts` + `system:authenticated`. Phase 11 D-11-02 makes this canonical via repo edit. After Plan 11-01 + first push, the live state will reconcile from the YAML — no separate live-edit needed (the live state already matches the desired state). (2) **`tenant-alpha` + `tenant-bravo` namespaces on spoke-capsule** — currently labeled `capsule.clastix.io/tenant=alpha`/`=bravo` (recreated as Capsule-owned via Plan 10-02 `--as=alpha/bravo` impersonation per D-10-02 Rule 3 deviation). After Plan 11-01 (D-11-03 inline label) + first push, Flux apply MAY re-create the namespaces from YAML — but **assumption-flag (D-11-03):** Flux's cluster-admin SA is exempt from Capsule's prefix-violation webhook (system:masters bypass — verified via Aqua Security Kubernetes auth article and Kubernetes docs that `system:masters` group requests are NOT sent to webhooks for evaluation). The label-bearing YAML applied as cluster-admin will create the namespace WITH the label, satisfying both the prefix check (bypassed) and the proxy LIST filter (label present). | Code edit (D-11-02 + D-11-03) ⇒ Flux reconcile (post Plan 11-04 push) ⇒ live state should converge naturally. **Verify at Plan 11-04:** push-gate-04-live-tenant-ns-flux-apply.bats asserts the post-push label state. |
| **OS-registered state** | None — no Windows Task Scheduler / launchd / systemd unit changes in Phase 11. | None. |
| **Secrets/env vars** | (1) **`spoke-capsule-kubeconfig` Secret on hub-flux flux-system namespace** — used by outer-K `clusters/hub-flux/pocs/capsule.yaml` (D-08-12 split-path: HUB-TARGETED, no spec.kubeConfig — but the HelmReleases under `pocs/capsule/spoke/` reference this Secret). UNCHANGED in Phase 11. (2) **Tenant SA tokens (alpha + bravo `gitops-reconciler` SA)** — TokenRequest API mints fresh tokens per `setup_file()` invocation (no static secrets); 2h validity; tmpdir-rooted. | None — tokens are ephemeral per-bats-file. |
| **Build artifacts** | (1) **capsule-proxy live-staged via `helm install`** (Plan 10-01 Rule 3 deviation per 10-VERIFICATION.md "Notable Observations"). Plan 11-04 explicitly removes this with `helm uninstall capsule-proxy --kube-context=k3d-spoke-capsule -n capsule-system` BEFORE first push, so the post-push reconcile is the canonical Flux-managed install path. (2) **In-cluster RBAC patch on `capsule-proxy:capsule-proxy` Role** (Plan 10-01 Rule 3 deviation — `kubectl patch role`). Persists in cluster state until Flux reconcile after first push reverts it; D-11-01's PostBuild patch carries the equivalent rule additions into the Flux-managed reconcile path. | Plan 11-04 Task 1 (`helm uninstall`); Plan 11-04 Task 2-3 (`git push origin main` + observe Flux reconcile result; the in-cluster Role patch will be REVERTED by Flux apply but the D-11-01 PostBuild patch will RE-APPLY the equivalent rules — net result identical). |

**Nothing found in OS-registered state category:** Verified — Phase 11 does not touch Windows Task Scheduler, systemd, launchd, or pm2.

**Nothing found in stored data category:** Verified — Phase 11 produces test artifacts in tmpdir only; no databases or persistent data stores affected.

## Common Pitfalls

### Pitfall 11-P1: Flux PostBuild patches apply to kustomize-build output, NOT to Helm-rendered manifests downstream

**What goes wrong:** D-11-01 expects `spec.patches` on the outer-K `poc-capsule` to extend a chart-rendered Role in `capsule-system` ON THE SPOKE. But the outer-K's `path: ./pocs/capsule` points at HelmRelease + OCIRepository CRs (which live on hub-flux per D-08-12 split-path), not at chart-rendered manifests. The Role itself is rendered by helm-controller LATER, on the spoke. PostBuild patches at the kustomize-controller layer fire BEFORE helm-controller renders the chart — meaning the patch target `kind: Role, name: capsule-proxy:capsule-proxy, namespace: capsule-system` may NOT match anything at patch time.

**Why it happens:** Flux's separation between kustomize-controller (kustomize render → apply) and helm-controller (Helm chart render → apply) means the rendered Role is a downstream artifact, not part of the kustomize-controller's input.

**How to avoid:** Two known-good alternative shapes:
- **Option A (recommended):** PostBuild patch on the SPOKE-TARGETED outer K (`clusters/hub-flux/pocs/capsule-spoke.yaml`) which renders the spoke-side resources. CONTEXT.md D-11-01 specifically names `clusters/hub-flux/pocs/capsule.yaml` (hub-targeted) — researcher recommends planner verify whether the patch should live on `capsule-spoke.yaml` instead.
- **Option B:** Add the RBAC extension as a Kustomize overlay in `pocs/capsule/proxy/` (extends the chart-rendered Role at chart-render time via Helm `postRenderer`). More invasive.
- **Option C:** Wait for upstream chart fix (Phase 10 verifier flagged this; out of scope for v0.19).

**Warning signs:** Plan 11-01 first-push event observation shows the chart-rendered Role does NOT have the secret-create rules; capsule-proxy's `kube-webhook-certgen` Job fails with `secrets is forbidden`; bats `push-gate-01-static-rbac-postbuild.bats` GREEN (literal present in YAML) but `push-gate-04-live-tenant-ns-flux-apply.bats` RED (cert-secret not materialized).

**Mitigation if it fires:** Move the patch to `clusters/hub-flux/pocs/capsule-spoke.yaml` (the SPOKE-TARGETED outer K with `spec.kubeConfig`); the patch then operates on the spoke-side resources after kustomize-controller renders them and applies via remote kubeconfig.

### Pitfall 11-P2: Capsule webhook prefix check vs. cluster-admin / system:masters bypass interaction (D-11-03 load-bearing assumption)

**What goes wrong:** D-11-03 trusts that "the cluster-admin Flux apply path bypasses Capsule's webhook prefix-violation check" because Capsule's webhook exempts cluster-admin / kube-system identities. But:
- **Verified true:** Kubernetes `system:masters` group bypasses ALL admission webhooks (validating + mutating) per Kubernetes documentation and Aqua Security write-up. Requests from members of system:masters group are NOT sent to webhooks for evaluation.
- **Conditional:** The Flux `flux-reconciler` SA on spoke-capsule is bound to the `cluster-admin` ClusterRole via `ClusterRoleBinding` (per Phase 4 SPOKE-01 + D-09-03 transitional kubeConfig). cluster-admin ClusterRole grants ALL verbs on ALL resources but does NOT add the SA to `system:masters` group. **The webhook bypass requires `system:masters` group membership — NOT cluster-admin role binding.**
- **Risk:** D-11-03 relies on `flux-reconciler` SA's GROUP being `system:authenticated` + `system:serviceaccounts` + `system:serviceaccounts:flux-system` — NOT `system:masters`. Capsule's namespace webhook will fire for the Flux apply.
- **However, the Capsule v0.12.4 chart's `tenantLabel` webhook has `namespaceSelector: matchExpressions: [{key: capsule.clastix.io/tenant, operator: Exists}]`** (verified via the upstream chart values.yaml). This means the webhook ONLY fires for namespaces that ALREADY HAVE the tenant label — and Phase 11 D-11-03 adds the label inline to the namespace YAML. **The label tags the namespace as Capsule-owned, but the prefix check (separate webhook hook) may still fire.**

**Why it happens:** Capsule has multiple webhook hooks per resource (e.g., `namespaces.tenants.projectcapsule.dev` for prefix enforcement; `tenantLabel` for owner-stamping). They have INDEPENDENT objectSelector / namespaceSelector / matchConditions defaults.

**How to avoid:**
- Verify behavior at Plan 11-04 first-push event (push-gate-04-live-tenant-ns-flux-apply.bats is the empirical falsifier).
- If the webhook DOES reject the cluster-admin Flux apply, fall back to D-11-03's documented escalation: operator-runbook fallback (post-install impersonation step `kubectl --as=alpha create namespace tenant-alpha`).

**Warning signs:** push-gate-04 RED with error string containing `prefix` or `forceTenantPrefix` or `doesn't match the tenant prefix`; outer-K `poc-capsule-spoke` Ready=False with namespace apply rejected.

**Mitigation if it fires:** Document operator-runbook fallback in `docs/poc-capsule.md`; planner records as a Rule 3 deviation in Plan 11-04 SUMMARY.

### Pitfall 11-P3: Capsule webhook quota error string is not constant — bats N6 grep must be permissive

**What goes wrong:** D-11-05 N6 probe asserts `! kubectl ... 2>&1 | grep -q "<exact error>"`. But Capsule's quota-violation error string is not documented as a constant; the upstream Capsule code emits different strings depending on quota-type (namespace quota vs. resource quota vs. tenant quota). Web search did not surface an exact-string match.

**Why it happens:** Capsule webhooks use Go-formatted error messages with embedded values; the format may evolve across versions. v0.12.4 specifically may emit one of: `"tenant alpha already has X namespaces, hitting the namespace quota"`, `"namespace quota exceeded"`, or just `"forbidden"` with details in the webhook event log.

**How to avoid:** Bats N6 grep should be PERMISSIVE — match any of `quota`, `namespace`, `limit`, or `exceeded`. Or alternatively, assert exit-code non-zero only and verify the rejection happened (state probe: `kubectl get namespaces -l capsule.clastix.io/tenant=alpha` returns N namespaces, not N+1).

**Warning signs:** N6 RED because exact grep didn't match; investigation shows the error string differs from CONTEXT.md's draft.

**Mitigation if it fires:** Adjust the bats grep to permissive multi-pattern match `grep -qE "(quota|namespace.*limit|exceeded)"`.

### Pitfall 11-P4: PVC strand mitigation may force-delete tenant data the operator wanted preserved

**What goes wrong:** D-11-11's `kubectl patch pvc {} --type=merge -p '{"metadata":{"finalizers":null}}'` after 60s timeout REMOVES the pvc-protection finalizer, allowing namespace cascade to proceed. If the operator was running a real workload that wanted the data preserved (POC iteration with valuable test data), this destroys it.

**Why it happens:** POC iteration cycles vs. real-data scenarios are indistinguishable from the script's POV.

**How to avoid:** D-11-11 is acceptable for POC ONLY (Capsule-managed PVCs are tenant-scoped; force-delete only affects POC state). Document this in `docs/poc-capsule.md` as an explicit limitation. For the v0.20+ adoption case, the script would need a `--preserve-data` flag.

**Warning signs:** Operator complaints; PVC bound to a Pod with valuable state lost during a `task destroy-poc capsule` run.

**Mitigation if it fires:** Document as POC limitation; add a `--preserve-data` flag in v0.20+ Phase 12+ work.

### Pitfall 11-P5: SLO regression test is environmentally sensitive (CI vs. local-dev)

**What goes wrong:** D-11-13 measures wall-clock `task rebuild` which depends on host load. Phase 5 v0.18 measured 190s on a warm-cache local-dev WSL2 host; CI runs on shared GitHub Actions runners with cold caches and noisy neighbors. The 230s budget may FAIL on CI even when there's no real regression.

**Why it happens:** Real-time measurements are environmentally coupled.

**How to avoid:** D-11-13 is local-dev only per CONTEXT.md `<deferred>` section. Plan 11-04 verifier discretion: skip-if-CI-and-budget-tight, or document the regression test as a local-dev bats not a CI-gate. The SKIP message ("VAL-04 deferred to local-dev verification") makes the operator aware.

**Warning signs:** GitHub Actions CI runs SLO bats RED; operator investigates; finds host load was 60% throttled.

**Mitigation if it fires:** Add `[[ -z "${CI:-}" ]] || skip "VAL-04 SLO regression: CI environment is too variable for accurate measurement; run locally"` to slo-regression-live.bats setup_file.

## Code Examples

Verified patterns from official sources and existing Phase 7-10 codebase:

### Tenant CR with quota + containerRegistries fixture (Claude's Discretion: N6 + N7)

```yaml
# Source: https://pkg.go.dev/github.com/projectcapsule/capsule/api/v1beta2 (verified 2026-05-05)
# Source: https://projectcapsule.dev/docs/tenants/enforcement/ (verified 2026-05-05)
apiVersion: capsule.clastix.io/v1beta2
kind: Tenant
metadata:
  name: alpha
spec:
  forceTenantPrefix: true
  owners:
    - kind: ServiceAccount
      name: system:serviceaccount:tenant-alpha:gitops-reconciler
    - kind: User
      name: alpha
  # N6 fixture — namespace quota
  # NamespaceOptions struct: Quota *int32 `json:"quota,omitempty"`
  # +kubebuilder:validation:Minimum=1
  # CONTEXT.md Claude's Discretion default: quota: 3
  namespaceOptions:
    quota: 3
  # N7 fixture — container registry allowlist
  # AllowedListSpec struct: { allowed: []string, allowedRegex: string }
  # CONTEXT.md Claude's Discretion default: registry.example.io
  # NOTE: ContainerRegistries field is marked as deprecated in v0.12.4
  # (use Enforcement.Registries instead). For POC purposes, both forms work.
  containerRegistries:
    allowed:
      - registry.example.io
  # ResourceQuotas + LimitRanges retained from existing Phase 9 shape:
  resourceQuotas:
    items:
      - hard:
          cpu: "4"
          memory: 8Gi
          pods: "20"
  limitRanges:
    items:
      - limits:
          - type: Container
            default:
              cpu: 100m
              memory: 128Mi
            defaultRequest:
              cpu: 50m
              memory: 64Mi
```

### bats N6 quota-violation falsifier (real-CRUD probe per D-11-05)

```bash
# Source: D-11-05 + D-11-06 + D-11-07 patterns
@test "N6 — tenant quota violation denied (real CRUD probe)" {
  # Tenant alpha quota = 3 (set in pocs/capsule/spoke/tenants/alpha/tenant.yaml)
  # Pre-state: tenant-alpha (home) + alpha-app1 (Phase 9 TEN-02) = 2 namespaces
  # Test: create alpha-app2 (3rd, OK) then alpha-app3 (4th, REJECTED)
  
  # 3rd namespace (within quota) — should succeed
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" create namespace alpha-app2
  [[ "$status" -eq 0 ]]
  
  # 4th namespace (exceeds quota) — should be rejected by Capsule webhook
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" create namespace alpha-app3
  [[ "$status" -ne 0 ]]
  # Permissive grep — exact error string is not a Capsule constant; see Pitfall 11-P3
  echo "$output" | grep -qE "(quota|namespace.*(limit|max)|exceeded)"
  
  # Cleanup — delete the 3rd namespace so the test is idempotent
  kubectl --kubeconfig="$ALPHA_KUBECONFIG" delete namespace alpha-app2 --wait=false || true
}
```

### bats N11/N12 webhook-down + recovery (D-11-09)

```bash
# Source: D-11-09 + D-11-05 + ROADMAP VAL-02 verbatim
@test "N11 — workload create rejected when capsule-controller down" {
  # Scale capsule-controller-manager to 0 — apiserver detects no endpoints
  run task fail-capsule-webhook -- 0
  [[ "$status" -eq 0 ]]
  
  # Wait for Deployment Ready=0 (rollout reverse — pod terminates within ~5s)
  sleep 5
  
  # Real probe — apply a Pod into alpha-app1; webhook rejects
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" run probe-n11 \
    --image=registry.example.io/probe -n alpha-app1
  [[ "$status" -ne 0 ]]
  # Apiserver returns "failed calling webhook ... no endpoints available"
  echo "$output" | grep -qE "(failed calling webhook|no endpoints available)"
  # Do NOT recover here — let setup_file or N12 handle.
}

@test "N12 — workload create succeeds again after operator recovers" {
  # Recover: scale to 1, wait for rollout
  run task fail-capsule-webhook -- 1
  [[ "$status" -eq 0 ]]
  # The script already polls rollout-status to Ready (90s timeout)
  
  # Real probe — apply a Pod into alpha-app1; webhook now allows
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" run probe-n12 \
    --image=registry.example.io/probe -n alpha-app1
  [[ "$status" -eq 0 ]]
  
  # Cleanup
  kubectl --kubeconfig="$ALPHA_KUBECONFIG" delete pod probe-n12 -n alpha-app1 --wait=false || true
}
```

### `fail-capsule-webhook.sh` script shape (D-11-09)

```bash
#!/usr/bin/env bash
# scripts/poc/capsule/fail-capsule-webhook.sh
# Source: D-11-09 verbatim from CONTEXT.md
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/lib/preflight-lib.sh"

REPLICAS="${1:-0}"
[[ "$REPLICAS" =~ ^[01]$ ]] || { fail "Usage: fail-capsule-webhook.sh [0|1]"; exit 1; }

have kubectl || { fail "kubectl not found"; exit 1; }

section "Scaling capsule-controller-manager to ${REPLICAS} replicas (test-only failure simulation)"
kubectl --context=k3d-spoke-capsule scale deploy capsule-controller-manager \
  -n capsule-system --replicas="${REPLICAS}"
pass "scaled capsule-controller-manager to ${REPLICAS}"

if [[ "$REPLICAS" == "1" ]]; then
  section "Waiting for rollout to Ready (90s timeout)"
  kubectl --context=k3d-spoke-capsule rollout status deploy/capsule-controller-manager \
    -n capsule-system --timeout=90s
  pass "capsule-controller-manager Ready"
fi
```

### `destroy-poc.sh` script shape (D-11-10 + D-11-11)

```bash
#!/usr/bin/env bash
# scripts/poc/capsule/destroy-poc.sh
# Source: D-11-10 + D-11-11 + CONTEXT.md <specifics> --full flag handling
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/lib/preflight-lib.sh"

# Arg parsing per CONTEXT.md <specifics> D-11-10
FULL=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    capsule) shift ;;
    --full) FULL=true; shift ;;
    *) fail "destroy-poc: unknown arg '$1' (usage: destroy-poc -- capsule [--full])"; exit 1 ;;
  esac
done

have kubectl flux jq || { fail "missing required tools: kubectl flux jq"; exit 1; }

section "Step 1/5: suspend tenant inner Ks + spoke-targeted outer K"
flux suspend kustomization tenant-alpha tenant-bravo poc-capsule-spoke -n flux-system || true
pass "suspended"

section "Step 2/5: delete Tenant CRs (cascade-deletes tenant namespaces)"
kubectl --context=k3d-spoke-capsule delete tenant alpha bravo --wait=true || true
pass "Tenant CRs deleted"

section "Step 3/5: poll namespace cascade (90s budget; auto force-delete PVCs after 60s)"
for i in $(seq 1 90); do
  REMAINING=$(kubectl --context=k3d-spoke-capsule get ns -l capsule.clastix.io/tenant= -o name 2>/dev/null | wc -l)
  if [[ "$REMAINING" -eq 0 ]]; then
    pass "namespace cascade complete after ${i}s"
    break
  fi
  if [[ "$i" -ge 60 ]]; then
    info "namespace cascade stuck at ${i}s; force-clearing PVC finalizers (P36 mitigation)"
    kubectl --context=k3d-spoke-capsule get pvc -A -l capsule.clastix.io/tenant= -o json 2>/dev/null \
      | jq -r '.items[] | "\(.metadata.namespace)/\(.metadata.name)"' \
      | xargs -I{} kubectl --context=k3d-spoke-capsule patch pvc {} \
          -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null || true
  fi
  sleep 1
done

section "Step 4/5: suspend operator + config outer Ks"
flux suspend kustomization poc-capsule poc-capsule-config -n flux-system || true
pass "suspended"

section "Step 5/5: ${FULL:+full} cluster lifecycle"
if [[ "$FULL" == "true" ]]; then
  k3d cluster delete spoke-capsule
  pass "cluster destroyed"
else
  info "preserving cluster + Capsule operator (use --full to destroy cluster)"
fi
```

### ADR-008 Nygard 4-section template (D-11-14)

```markdown
# 8. Capsule Multi-Tenancy POC Graduation

## Status

Accepted (<adopt|defer|reject|replaced by ADR-009>) — 2026-MM-DD

## Context

Milestone v0.19 (Capsule Multi-Tenancy POC) ran from Phase 7 (POC seam) through
Phase 11 (validation). Five mandatory phases shipped 18 plans across 4
requirement domains: POC seam (POC-01..04 + CAPCLU-01..04 + EKSDOC-01),
Capsule install (CAP-01..03), Tenant lockdown (TEN-01..06), and Tenant
kubeconfig (PROXY-01..03). Phase 11 closes with empirical evidence
(VAL-01..06) backing this graduation decision.

The POC was scoped to evaluate Capsule's tenant-isolation contract on a single
hand-rolled persistent k3d spoke (`spoke-capsule`) — without polluting the
v0.18 default `task rebuild` SLO (P31 invariant) or the public-repo secrets
contract (P29 invariant). The graduation question: should v0.20+ adopt Capsule
into the v1 platform, defer pending more evidence, reject as unsuitable, or be
replaced by another POC (e.g., HNS / vCluster / Crossplane)?

## Decision

<outcome paragraph stating the chosen graduation status with one-sentence
justification mapped to the rubric below>

| Outcome | Required evidence |
|---|---|
| **ADOPT** | All 12/12 N1-N12 PASS + VAL-02 webhook recovery PASS + VAL-03 clean teardown PASS (no stuck namespaces post-90s) + VAL-04 < 230s + CID unchanged + zero gitleaks findings + ZERO open BLOCKER carryovers |
| **DEFER** | ≥ 1 of: N1-N12 RED-by-design (workaround documented, not bug) OR ≥ 1 unresolved upstream chart issue (e.g., D-11-01 PostBuild patch is workaround pending upstream chart fix) OR Phase 12 capsule-addon-fluxcd Trial would clarify the architectural shape |
| **REJECT** | ≥ 1 of: N1-N12 RED for tenant-isolation reason (silent escape — security invariant breached) OR VAL-04 SLO regressed > 230s OR webhook recovery non-deterministic (VAL-02 flakes more than 2/3 runs) |
| **REPLACED BY ADR-009** | Mid-validation discovery: a fundamentally different POC supersedes Capsule's value proposition for karyon's lab use-case |

This rubric was matched against bats evidence: <cite specific bats results from
11-VERIFICATION.md>.

### What we proved

- VAL-01 — All 12 N1-N12 negative-RBAC falsifiers PASS (cite
  `tests/bats/negative-rbac-{01..05}-*.bats` GREEN per `11-VERIFICATION.md`)
- VAL-02 — Capsule webhook failure mode observed and recoverable (cite
  `negative-rbac-05-webhook-down.bats` N11+N12 GREEN)
- VAL-03 — Clean teardown via `task destroy-poc capsule` (cite
  `tests/bats/teardown-{01..04}-*.bats` GREEN; sentinel preservation verified)
- VAL-04 — `task rebuild` SLO < 230s with k3d-spoke-capsule-server-0 CID
  unchanged across rebuild (cite `slo-regression-live.bats` GREEN)
- VAL-05 — One-shot history gitleaks scan returned 0 findings post first push
  (cite Plan 11-04 verifier output)

### What we did not prove

- HA Capsule (multi-replica + leader election) — POC ran single-replica
- OIDC / Dex / Keycloak tenant authentication — POC used SA + bearer tokens
- Multi-spoke tenant federation — Capsule has no native cross-cluster Tenant
- Capsule installed on hub-flux itself — POC validated spoke-side only
- Production ingress + cert-manager + real TLS for capsule-proxy — NodePort + self-signed
- Real EKS deploy of Capsule — `docs/capsule-on-eks.md` is rough-cut design only
- NetworkPolicy enforcement (P43) — focus was RBAC isolation, not packet-drop verification
- Long-lived TokenRequest semantics on EKS vs. k3s clamp behavior — k3s does NOT clamp; EKS clamps at 24h default

### Trade-offs

- POC uses long-lived 2h TokenRequest tokens for tenant kubeconfigs (Phase 10 D-10-01); production deployment requires OIDC or shorter-lived token rotation
- D-11-01 PostBuild patch is a workaround pending upstream capsule-proxy chart fix (the chart's `kube-webhook-certgen` Job's Role lacks `secrets create/update/patch` rules; documented as Phase 11 carryover)
- D-11-02 CapsuleConfiguration `userGroups` 3-group set is opinionated — production may use a different group identity model
- D-11-11 PVC strand mitigation force-deletes finalizers; acceptable for POC, NOT for production data
- VAL-04 SLO measurement is local-dev only; CI runs may need looser tolerance

## Consequences

<paragraph stating what changes downstream based on the chosen outcome>

- If **ADOPT**: v0.20 incorporates Capsule into default `task rebuild`,
  spoke-capsule promoted from POC to v1 spoke, capsule-addon-fluxcd Phase 12
  runs as adoption acceleration.
- If **DEFER**: v0.20 reruns POC validation with capsule-addon-fluxcd; ADR-008
  is reopened for revision.
- If **REJECT**: spoke-capsule torn down as part of v0.19 close; no v0.20
  carryover; future multi-tenancy work is a separate ADR.
- If **REPLACED BY ADR-009**: ADR-009 names the replacement POC; this POC's
  artifacts are archived under `.planning/milestones/v0.19-archive/`.
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `kubectl auth can-i` for negative RBAC tests | Real CRUD apply path with permissive grep on error string | Phase 11 D-11-05 (locked 2026-05-05) | Eliminates SAR cache flake (5min/30s TTL) — research P37 |
| Single bats file per phase | Attack-class partitioned bats files (5 files for 12 N falsifiers) | Phase 11 D-11-06 (locked 2026-05-05) | Failure isolation per attack class; faster bats run; shared setup_file per file |
| `kubernetes.io/service-account-token` legacy long-lived tokens | TokenRequest API short-lived tokens (--duration=2h) | Phase 10 D-10-01 (locked 2026-04-29) | Bound-token semantics; portable to EKS IRSA |
| In-cluster `kubectl patch` for RBAC fixes | Flux PostBuild `spec.patches` (declarative GitOps) | Phase 11 D-11-01 (locked 2026-05-05) | Survives Flux reconcile; auditable in git history |
| Live-edit CapsuleConfiguration | Repo-edited CapsuleConfiguration (single source of truth) | Phase 11 D-11-02 (locked 2026-05-05) | Live state matches GitOps source; no patch drift |
| `kubectl --as=<tenant>` operator runbook for namespace ownership | Inline `metadata.labels.capsule.clastix.io/tenant: <name>` in namespace YAML + cluster-admin Flux apply | Phase 11 D-11-03 (locked 2026-05-05; assumption-flagged per Pitfall 11-P2) | Zero operator intervention; YAML-as-source-of-truth; first push reconciles cleanly IF assumption holds |
| Manual gitleaks per-finding allowlist | Path-based regex allowlist for `.planning/*.md` | Phase 11 D-11-04 (locked 2026-05-05) | Future-proof: any future phase's planning docs auto-allowlisted |

**Deprecated/outdated:**
- `kubectl auth can-i` for negative RBAC validation — flake-prone due to SAR cache
- `legacy SA token Secret` (kubernetes.io/service-account-token) — superseded by TokenRequest API in Phase 10
- ContainerRegistries Tenant CR field — marked deprecated in v0.12.4 (use Enforcement.Registries instead); Phase 11 N7 fixture uses the deprecated form for backward compat with existing tenant.yaml shape

## Assumptions Log

> Claims tagged `[ASSUMED]` in this research. The planner and discuss-phase use this section to identify decisions that need user confirmation before execution.

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | D-11-01 PostBuild `spec.patches` on the hub-targeted outer K (`clusters/hub-flux/pocs/capsule.yaml`) successfully patches the chart-rendered Role on the spoke. CONTEXT.md draft locks this surface, but Pitfall 11-P1 flags that PostBuild patches apply to kustomize-build output (HelmRelease + OCIRepository CRs on hub) NOT to Helm-rendered manifests on spoke. | Common Pitfalls 11-P1 + Architecture Patterns Pattern 1 | If wrong: Plan 11-01 lands the patch, Plan 11-04 push observes capsule-proxy `kube-webhook-certgen` Job still failing with `secrets is forbidden`. **Mitigation:** move patch to `clusters/hub-flux/pocs/capsule-spoke.yaml` (spoke-targeted outer K). Plan 11-01 verifier discretion. |
| A2 | D-11-03 cluster-admin Flux apply path bypasses Capsule's namespace prefix-violation webhook because `flux-reconciler` SA has cluster-admin role binding. **Verified system:masters bypasses webhooks; NOT verified that cluster-admin role binding alone suffices.** | Common Pitfalls 11-P2 + Runtime State Inventory | If wrong: Plan 11-04 push observes namespace YAML rejected by Capsule webhook with `prefix` error string. **Mitigation:** documented operator-runbook fallback (post-install impersonation step). Plan 11-04 verifier discretion. push-gate-04-live bats is the empirical falsifier. |
| A3 | Capsule v0.12.4 webhook quota-violation error string contains the literal `quota` somewhere — Pitfall 11-P3 recommends permissive grep `(quota\|namespace.*(limit\|max)\|exceeded)`. | Common Pitfalls 11-P3 + Code Examples N6 | If wrong: N6 RED with grep no-match. **Mitigation:** widen the grep further; assert exit-code only and verify state probe. |
| A4 | Apiserver returns `failed calling webhook ... no endpoints available` IMMEDIATELY when admission webhook with failurePolicy: Fail has zero endpoints (per inferred Kubernetes behavior + ArgoCD case study). | Phase Requirements VAL-02 + Code Examples N11 | If wrong: N11 wall-clock latency exceeds expected; investigate apiserver behavior. **Mitigation:** widen the grep to also match `context deadline exceeded`. Low risk — ArgoCD docs confirm this behavior empirically. |
| A5 | Bats setup_file() exports persist across @test invocations within the same file (verified by Phase 7-10 inheritance). | Architecture Patterns Pattern 2 | Verified — bats v1.5+ documented behavior; Bats 1.11.0 installed and working. |
| A6 | gitleaks 8.30.1 supports `[allowlist] paths = ['^\.planning/.*\.md$']` regex with double-escaped backslash. | Standard Stack + Phase Requirements VAL-05 | Low risk — verified syntax against existing `^\.env\.example$` precedent in `.gitleaks.toml`. |
| A7 | k3d-spoke-capsule-server-0 container ID is stable across `task rebuild` (rebuild does NOT touch spoke-capsule per P31 — verified by Phase 7 P31 lint inheritance). | Phase Requirements VAL-04 + Code Examples slo-regression-live | Verified — `task rebuild` calls `scripts/rebuild.sh` which calls v0.18 scripts; P31 lint asserts ZERO `spoke-capsule` mentions in those scripts; therefore rebuild cannot touch spoke-capsule's container. |
| A8 | Nygard ADR template's "Status" section accepts a parenthesized qualifier like `Accepted (adopt)` per project's existing ADR style (informal verification — none of ADRs 0001-0005 use a qualifier; CONTEXT.md D-11-14 introduces the convention for ADR-008). | Code Examples ADR-008 + ROADMAP VAL-06 | Low risk — Nygard's original spec only requires the status label; the parenthesized qualifier is an extension that other projects use commonly. |

**If this table is empty:** All claims in this research were verified or cited — no user confirmation needed.

## Open Questions

1. **Where should the D-11-01 PostBuild patch actually live — hub-targeted or spoke-targeted outer K?**
   - What we know: CONTEXT.md D-11-01 locks `clusters/hub-flux/pocs/capsule.yaml` (HUB-TARGETED, no spec.kubeConfig per D-08-12 split-path).
   - What's unclear: PostBuild patches at the kustomize-controller layer apply to kustomize-build output (HelmRelease + OCIRepository CRs on hub), not to Helm-rendered manifests downstream (the actual Role on spoke). The patch target `kind: Role, name: capsule-proxy:capsule-proxy, namespace: capsule-system` will not match the kustomize-build output of the hub-targeted outer K.
   - Recommendation: Plan 11-01 implements D-11-01 verbatim; Plan 11-04 verifier observes whether the patch fired correctly. If RED, Rule 3 deviation: move patch to `clusters/hub-flux/pocs/capsule-spoke.yaml` (SPOKE-TARGETED outer K) and re-test.

2. **Does the Flux `flux-reconciler` SA's cluster-admin role binding bypass Capsule's prefix-enforcement webhook?**
   - What we know: `system:masters` GROUP membership bypasses ALL admission webhooks (verified). cluster-admin ROLE binding does NOT add the SA to system:masters group.
   - What's unclear: Does Capsule's `namespaces.tenants.projectcapsule.dev` webhook have a matchConditions/namespaceSelector that excludes the `flux-reconciler` SA's identity?
   - Recommendation: Plan 11-04 push event is the empirical falsifier (push-gate-04-live-tenant-ns-flux-apply.bats). If RED, document operator-runbook fallback per D-11-03's documented escalation.

3. **What is the exact Capsule v0.12.4 webhook error string for namespace-quota violation?**
   - What we know: NamespaceOptions.Quota is `*int32` with `+kubebuilder:validation:Minimum=1`. The webhook DOES enforce.
   - What's unclear: The exact format of the error message string emitted by Capsule's webhook when the count is exceeded.
   - Recommendation: Bats N6 uses permissive grep `(quota|namespace.*(limit|max)|exceeded)`; if RED, widen further or assert exit-code only.

4. **Does `task rebuild` include the v0.18 `task health-check` step at the end?**
   - What we know: `scripts/rebuild.sh` exists; verified by `cat`. The script calls preflight + destroy + create-clusters + bootstrap-flux + register-spokes + deploy-examples + health-check (per v0.18 Phase 5 contract).
   - What's unclear: Does `task rebuild` itself wrap `health-check` or does the operator run them separately? D-11-13 has `task rebuild` AND `task health-check` as separate @tests.
   - Recommendation: Verify by reading `scripts/rebuild.sh` more carefully during Plan 11-00 RED scaffold work; if rebuild includes health-check internally, @test c (`task health-check exit 0`) is redundant.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| bats | All Phase 11 bats | ✓ | 1.11.0 | — |
| gitleaks | VAL-05 + push-gate-05-static-gitleaks-allowlist | ✓ | 8.30.1 | — |
| kubectl | All cluster interactions | ✓ | v1.35.0 | — |
| yq | bats setup_file token extraction | ✓ | v4.53.2 | — |
| flux CLI | destroy-poc.sh `flux suspend` | ✓ | bin present (no live cluster check needed for script invocation) | — |
| k3d | destroy-poc.sh `--full` flag | ✓ | (assumed; verified on Phase 7-10) | — |
| jq | destroy-poc.sh PVC list parsing | ✓ | (system default) | — |
| docker | slo-regression-live.bats CID compare; destroy-poc.sh `--full` | ✓ | (k3d containers running per `docker ps`) | — |
| openssl | Phase 7 inheritance only — not new for Phase 11 | ✓ | (system default) | — |
| capsule-proxy NodePort 30443 | bats N1-N7 + N9-N10 (proxy LIST + apply) | ✓ | (verified by Phase 10 GREEN bats — proxy reachable) | — |
| spoke-capsule k3d cluster | All Phase 11 live tests | ✓ | k3d-spoke-capsule-server-0 RUNNING per `docker ps` | If down: VAL-04 setup_file SKIP; other live bats fail with explanatory error |
| Capsule operator on spoke-capsule | All N1-N12 | ✓ | (capsule-controller-manager on spoke per Phase 8 CAP-01) | If down: D-11-09 mechanism re-deploys; otherwise live bats RED |

**Missing dependencies with no fallback:** None.

**Missing dependencies with fallback:** spoke-capsule cluster (live-skip via D-11-13 BEFORE_CID="MISSING" pattern).

## Validation Architecture

> nyquist_validation enabled per default (no `.planning/config.json` workflow.nyquist_validation: false override observed). Section included.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Bats 1.11.0 (verified live) |
| Config file | `tests/bats/test_helper.bash` (shared loader; sourced via `load 'test_helper'` in each suite) |
| Quick run command | `bats tests/bats/<single-file>.bats` |
| Full suite command | `bats tests/bats/` (entire directory) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| VAL-01 (N1) | cross-tenant pod read denied | live | `bats tests/bats/negative-rbac-01-cross-tenant-list.bats` | ❌ Wave 0 |
| VAL-01 (N2) | cluster-wide LIST filtered | live | `bats tests/bats/negative-rbac-01-cross-tenant-list.bats` | ❌ Wave 0 |
| VAL-01 (N3) | cross-tenant secret read denied | live | `bats tests/bats/negative-rbac-01-cross-tenant-list.bats` | ❌ Wave 0 |
| VAL-01 (N4) | ClusterRoleBinding escalation denied | live | `bats tests/bats/negative-rbac-02-escalation.bats` | ❌ Wave 0 |
| VAL-01 (N5) | namespace prefix violation denied | live | `bats tests/bats/negative-rbac-03-webhook-policy.bats` | ❌ Wave 0 |
| VAL-01 (N6) | tenant quota violation denied | live | `bats tests/bats/negative-rbac-03-webhook-policy.bats` | ❌ Wave 0 |
| VAL-01 (N7) | denied registry pull denied | live | `bats tests/bats/negative-rbac-03-webhook-policy.bats` | ❌ Wave 0 |
| VAL-01 (N8) | direct apiserver bypass denied | live | `bats tests/bats/negative-rbac-04-bypass-and-flux.bats` | ❌ Wave 0 |
| VAL-01 (N9) | cross-tenant sourceRef denied | live (Flux reconcile ~30s) | `bats tests/bats/negative-rbac-04-bypass-and-flux.bats` | ❌ Wave 0 |
| VAL-01 (N10) | missing serviceAccountName denied | live (Flux reconcile ~30s) | `bats tests/bats/negative-rbac-04-bypass-and-flux.bats` | ❌ Wave 0 |
| VAL-01 (N11) | workload create rejected when capsule-controller down | live | `bats tests/bats/negative-rbac-05-webhook-down.bats` | ❌ Wave 0 |
| VAL-01 (N12) | workload create succeeds again after operator recovers | live | `bats tests/bats/negative-rbac-05-webhook-down.bats` | ❌ Wave 0 |
| VAL-01 (anti-pattern) | no `kubectl auth can-i` in negative-rbac source files | static | `bats tests/bats/negative-rbac-anti-pattern-lint-static.bats` | ❌ Wave 0 |
| VAL-02 | webhook recovery (N11+N12 are dual contract) | live | `bats tests/bats/negative-rbac-05-webhook-down.bats` | ❌ Wave 0 |
| VAL-03 | clean teardown (5-step + sentinel preservation) | static + live | `bats tests/bats/teardown-{01..04}-*.bats` | ❌ Wave 0 |
| VAL-04 | task rebuild SLO + CID stability + P31 lint | live | `bats tests/bats/slo-regression-live.bats` | ❌ Wave 0 |
| VAL-04 (P31) | v0.18 scripts have ZERO spoke-capsule mentions | static | `bats tests/bats/poc-isolation-01-static.bats` | ✓ (Phase 7 inherited) |
| VAL-05 | gitleaks zero-findings post first push | live (one-shot) + static (allowlist literal) | `gitleaks detect --source . --no-git --redact` + `bats tests/bats/push-gate-05-static-gitleaks-allowlist.bats` | ❌ Wave 0 (allowlist bats); ✓ (gitleaks command available) |
| VAL-05 (push-gate D-11-01..03) | persistent fixes applied | static + live (post first push) | `bats tests/bats/push-gate-{01..04}-*.bats` | ❌ Wave 0 |
| VAL-06 | ADR-008 written per Nygard 4-section + 3 sub-sections; EKSDOC-01 rolled forward | manual review (no automated bats) | (operator review) | ❌ Plan 11-05 |

### Sampling Rate

- **Per task commit:** `bats tests/bats/<single-target-bats>.bats` (the bats file relevant to the just-changed source file)
- **Per wave merge:** `bats tests/bats/` (full Phase 11 + inherited Phase 7-10 suite)
- **Phase gate:** Full suite green before `/gsd-verify-work` invokes Plan 11-04 verifier; ADR-008 written by Plan 11-05

### Wave 0 Gaps

- [ ] `tests/bats/negative-rbac-01-cross-tenant-list.bats` — covers N1-N3
- [ ] `tests/bats/negative-rbac-02-escalation.bats` — covers N4
- [ ] `tests/bats/negative-rbac-03-webhook-policy.bats` — covers N5-N7
- [ ] `tests/bats/negative-rbac-04-bypass-and-flux.bats` — covers N8-N10
- [ ] `tests/bats/negative-rbac-05-webhook-down.bats` — covers N11-N12 (VAL-02 dual-contract)
- [ ] `tests/bats/negative-rbac-anti-pattern-lint-static.bats` — D-11-05 anti-pattern enforcement
- [ ] `tests/bats/push-gate-01-static-rbac-postbuild.bats` — D-11-01 static
- [ ] `tests/bats/push-gate-02-static-capsuleconfig.bats` — D-11-02 static
- [ ] `tests/bats/push-gate-03-static-tenant-ns-label.bats` — D-11-03 static
- [ ] `tests/bats/push-gate-04-live-tenant-ns-flux-apply.bats` — D-11-03 live (Pitfall 11-P2 falsifier)
- [ ] `tests/bats/push-gate-05-static-gitleaks-allowlist.bats` — D-11-04
- [ ] `tests/bats/teardown-01-static-script.bats` — destroy-poc.sh shape
- [ ] `tests/bats/teardown-02-static-sentinel-preservation.bats` — sentinel preservation (NO mutation of `clusters/hub-flux/flux-system/kustomization.yaml`)
- [ ] `tests/bats/teardown-03-live-ordered.bats` — live destroy-poc run
- [ ] `tests/bats/teardown-04-live-pvc-strand-mitigation.bats` — synthetic PVC + force-delete check
- [ ] `tests/bats/slo-regression-live.bats` — D-11-13 (4 @tests; 1 inherited)
- [ ] No framework install needed — Bats 1.11.0 already present

## Sources

### Primary (HIGH confidence)
- [Capsule v1beta2 API Go package (pkg.go.dev)](https://pkg.go.dev/github.com/projectcapsule/capsule/api/v1beta2) — verified `NamespaceOptions.Quota *int32`, `ContainerRegistries *api.AllowedListSpec`, `CapsuleConfigurationSpec` struct fields with JSON tags
- [Flux Kustomization v1 spec — patches](https://fluxcd.io/flux/components/kustomize/kustomizations/) — verified JSON6902 op:add path:/rules/- syntax + target field schema (kind/name/namespace/group/version/labelSelector/annotationSelector)
- [Capsule chart values.yaml v0.12.4 (GitHub)](https://github.com/projectcapsule/capsule/blob/v0.12.4/charts/capsule/values.yaml) — verified webhook failurePolicy defaults (Fail for namespaces/pods/tenants), tenantLabel namespaceSelector matching `capsule.clastix.io/tenant Exists`
- [Kubernetes Authorization — system:masters bypass](https://kubernetes.io/docs/reference/access-authn-authz/authorization/) + [Aqua Security — Don't Use system:masters](https://www.aquasec.com/blog/kubernetes-authorization/) — verified system:masters group bypasses all admission webhooks
- [Capsule containerRegistries enforcement docs](https://projectcapsule.dev/docs/tenants/enforcement/) — verified AllowedListSpec shape `{allowed: [], allowedRegex: "..."}` + webhook denial behavior
- [Nygard ADR template (joelparkerhenderson/architecture-decision-record)](https://github.com/joelparkerhenderson/architecture-decision-record/blob/main/locales/en/templates/decision-record-template-by-michael-nygard/index.md) — verified 4-section structure (Title / Status / Context / Decision / Consequences)
- [Cognitect — Documenting Architecture Decisions (Nygard original 2011)](https://www.cognitect.com/blog/2011/11/15/documenting-architecture-decisions) — verified original Nygard spec
- [kube-apiserver flags reference](https://kubernetes.io/docs/reference/command-line-tools-reference/kube-apiserver/) — verified `--authorization-webhook-cache-authorized-ttl: 5m0s` default
- [Flux Multi-Tenancy lockdown configuration](https://fluxcd.io/flux/installation/configuration/multitenancy/) — verified `--no-cross-namespace-refs`, `--no-remote-bases`, `--default-service-account` flag semantics (used for N9/N10 falsifiers)
- [Flux Service Account Impersonation (oneuptime)](https://oneuptime.com/blog/post/2026-03-05-flux-cd-service-account-impersonation/view) — verified that `spec.kubeConfig` + `spec.serviceAccountName` causes controller to impersonate SA on target cluster

### Secondary (MEDIUM confidence)
- [Capsule MutatingWebhookConfiguration template (chart)](https://github.com/projectcapsule/capsule/blob/main/charts/capsule/templates/mutatingwebhookconfiguration.yaml) — verified webhook list (pod.defaults, namespaces.tenants, tenants, etc.)
- [Capsule issue #1292 — Cluster admin actions intercepted](https://github.com/projectcapsule/capsule/issues/1292) — confirms cluster-admin requests can be intercepted by Capsule webhook (does NOT bypass)
- [Kubernetes admission webhook timeout/no-endpoints behavior](https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/) + [ArgoCD webhook no-endpoints case study](https://www.technetexperts.com/argocd-webhook-no-endpoints-available/) — apiserver returns "failed calling webhook ... no endpoints available" immediately when Deployment scaled to 0 with failurePolicy: Fail
- [Capsule namespaces docs](https://projectcapsule.dev/docs/tenants/namespaces/) — verified `forceTenantPrefix` semantics; error string "The Namespace prefix used doesn't match any available Tenant" (informational; does not exactly match Phase 11 prefix-violation case)
- [gitleaks default config (gitleaks/config/gitleaks.toml)](https://github.com/gitleaks/gitleaks/blob/master/config/gitleaks.toml) — verified `[[allowlists]] paths` regex syntax precedent

### Tertiary (LOW confidence)
- WebSearch results aggregated for Capsule webhook quota error string — no exact-string match found upstream; permissive grep recommended (Pitfall 11-P3)
- WebSearch results for k3s `--service-account-extend-token-expiration` and `--authorization-webhook-cache-authorized-ttl` defaults — verified k3s does NOT clamp TokenRequest duration; SAR cache defaults at 5m authorized / 30s unauthorized

### Project artifacts (HIGH confidence — directly read)
- `.planning/phases/11-validation-graduation-adr-008/11-CONTEXT.md` — 16 locked decisions D-11-01..16; recommended 5-plan structure; full canonical_refs section
- `.planning/REQUIREMENTS.md` — VAL-01..06 contracts; load-bearing P27/P29/P31 invariants
- `.planning/STATE.md` — Phase 10 close-out passed_with_overrides; 4 D-08-13 push-gate items deferred to Phase 11; 3 carryover items D-11-01..03 resolve
- `.planning/research/PITFALLS.md` — P26-P43 catalogue; Phase 11 directly addresses P26, P29, P31, P36, P37, P41, P42
- `.planning/phases/10-tenant-owner-kubeconfigs-capsule-proxy-round-trip/10-VERIFICATION.md` — 3 carryover items + push-gate-deferral context
- `pocs/capsule/spoke/tenants/{alpha,bravo}/tenant.yaml` — current Tenant CR shape (no namespaceOptions or containerRegistries currently)
- `pocs/capsule/spoke/config/capsuleconfig.yaml` — current CapsuleConfiguration (userGroups: [capsule.clastix.io] only)
- `clusters/hub-flux/pocs/capsule.yaml` — current outer K (HUB-TARGETED per D-08-12 split-path; no spec.patches)
- `.gitleaks.toml` — current allowlist (single path: `^\.env\.example$`)
- `Taskfile.yml` — current task surface (12 entries; no fail-capsule-webhook or destroy-poc)
- `scripts/poc/capsule/{create-cluster,fix-dns,issue-tenant-kubeconfig}.sh` — analogs for Phase 11's two new scripts
- `tests/bats/poc-isolation-01-static.bats` — Phase 7 P31 lint reused verbatim per D-11-16

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — All tools verified live (`bats --version 1.11.0`; `gitleaks 8.30.1`; `kubectl v1.35.0`; `yq v4.53.2`; `docker ps` shows k3d-spoke-capsule-server-0 alive). Capsule v0.12.4 + capsule-proxy 0.12.0 + k3s v1.34.6-k3s1 pins are project-locked per ADR-005 + STACK.md.
- Architecture patterns: HIGH on Flux v1 spec.patches syntax (verified vs. fluxcd.io official docs). HIGH on bats setup_file mechanism (verified vs. bats v1.5+ docs + Phase 7-10 inheritance). MEDIUM on D-11-01 patch-target semantics (Pitfall 11-P1 flags risk that hub-targeted outer K's PostBuild patch may not match spoke-side Role; empirical verification needed at Plan 11-04).
- Pitfalls: HIGH — Phase 11 inherits research P26/P29/P31/P36/P37/P41/P42 verbatim; new pitfalls 11-P1..P5 documented based on cross-checking CONTEXT.md decisions against verified upstream behavior.
- ADR-008 template: HIGH — Nygard 4-section verified vs. authoritative sources + project ADR precedent (0001-0005 follow Status / Context / Decision / Consequences).
- Negative claims: MEDIUM on "exact Capsule quota error string" (Pitfall 11-P3 — no exact-string match found; permissive grep recommended). MEDIUM on "cluster-admin Flux apply bypasses Capsule webhook" (Pitfall 11-P2 — system:masters bypass verified, but Flux's flux-reconciler SA is NOT in system:masters group; empirical verification at Plan 11-04 is the falsifier).

**Research date:** 2026-05-05
**Valid until:** 2026-06-05 (30 days for stable pins; 7 days for fast-moving Capsule fields if v0.12.5+ ships in interim)
