# Phase 8: Capsule + capsule-proxy Bare-Minimum Install - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in 08-CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-29
**Phase:** 08-capsule-capsule-proxy-bare-minimum-install
**Mode:** `--auto` — Claude selected the recommended option for every gray area without asking; no interactive questions were posed.
**Areas discussed:** Directory layout, OCIRepository source pattern, Operator webhook failurePolicy (P26), Operator TLS approach (P34), Inner kustomization.yaml replacement, HelmRelease reconcile interval, Proxy dependsOn operator, CapsuleConfiguration CR scope, Test scaffolding pattern, k3d port-publish flag confirmation

---

## Directory Layout (`pocs/capsule/`)

| Option | Description | Selected |
|--------|-------------|----------|
| A: Two-subdir layout (`operator/` + `proxy/`) | Each component has self-contained `OCIRepository` + `HelmRelease`; outer `pocs/capsule/kustomization.yaml` references subdirs | ✓ |
| B: Flat under `pocs/capsule/` | All manifests at one level; one `kustomization.yaml` lists everything | |

**Selected option:** A — `pocs/capsule/operator/` + `pocs/capsule/proxy/`.
**Rationale (Claude's recommended default):** Mirrors research §"Phase 9 — pocs/capsule/operator/, pocs/capsule/proxy/" naming convention. Phase 9's `tenants/` subdir + Phase 11's ordered teardown `dependsOn` both compose cleanly under this layout. Slight YAML duplication is acceptable cost for clean component decoupling.

---

## OCIRepository Source Pattern

| Option | Description | Selected |
|--------|-------------|----------|
| A: Per-chart `OCIRepository` | One per chart (`capsule`, `capsule-proxy`); each lives next to its corresponding HelmRelease | ✓ |
| B: Shared `OCIRepository` | Single resource pointing at `oci://ghcr.io/projectcapsule/charts/` covering both | |

**Selected option:** A — per-chart OCIRepository.
**Rationale (Claude's recommended default):** Clean failure isolation — when one chart's source is mid-fetch failure, the other's HelmRelease reconcile is unaffected. Matches `clastix/flux2-capsule-multi-tenancy` upstream reference layout. Each `HelmRelease.spec.chartRef` points at its own local OCIRepository by name.

---

## Operator Webhook `failurePolicy` Override (P26)

| Option | Description | Selected |
|--------|-------------|----------|
| A: Apply `failurePolicy: Ignore` with `matchConditions` in Phase 8 | Belt-and-suspenders defense for Phase 8 → Phase 9 transition window | ✓ |
| B: Defer to Phase 9 | Land with chart defaults in Phase 8; revisit when tenants exist | |

**Selected option:** A — apply now with `matchConditions`.
**Rationale (Claude's recommended default):** Between Phase 8 install and Phase 9 tenant landing, `kubectl create pod` against `default` ns triggers Capsule's ValidatingWebhookConfiguration. Chart defaults could fail-closed if operator briefly restarts. `failurePolicy: Ignore` + `matchConditions` is the documented Capsule-recommended fail-open posture for clusters without tenants. Cost: ~10 lines of HelmRelease values.

---

## Operator TLS — Built-in certgen vs cert-manager (P34)

| Option | Description | Selected |
|--------|-------------|----------|
| A: Built-in certgen | `tls.enableController: true`; chart-managed self-signed cert with auto-rotation | ✓ |
| B: cert-manager | Would require landing cert-manager first (adds Phase 8 scope) | |

**Selected option:** A — built-in certgen.
**Rationale (Claude's recommended default):** cert-manager is NOT in v0.19 scope (PROJECT.md Out-of-Scope). Adding it for the POC is gold-plating. Built-in certgen is documented as fully functional for Capsule operator webhooks; the only downside (no cross-pod cert sharing) doesn't apply since the operator runs single-replica per Phase 8 + ADR-008's "what we did not prove → HA Capsule" framing.

---

## Inner kustomization.yaml Replacement

| Option | Description | Selected |
|--------|-------------|----------|
| A: Rewrite Phase 7 placeholder | Replace `resources: []` with `resources: [operator/, proxy/]`; preserve Phase 7 head comment + append Phase 8 update note | ✓ |
| B: Add separate Flux Kustomization CRDs per subdir | Two new top-level Flux Kustomizations in `clusters/hub-flux/pocs/` for operator + proxy | |

**Selected option:** A — rewrite the existing `pocs/capsule/kustomization.yaml`.
**Rationale (Claude's recommended default):** Single outer Flux `Kustomization poc-capsule` does its kustomize-build over the whole `pocs/capsule/` tree. Subdir refs let kustomize resolve recursively without spawning additional Flux Kustomization CRDs. Single-Flux-Kustomization-per-cluster is the v0.18 spoke pattern (one per spoke).

---

## HelmRelease Reconcile Interval

| Option | Description | Selected |
|--------|-------------|----------|
| A: Explicit `interval: 5m` | Matches outer `clusters/hub-flux/pocs/capsule.yaml` Kustomization cadence | ✓ |
| B: Default Flux interval (10m) | Implicit; less verbose YAML | |

**Selected option:** A — explicit `interval: 5m`.
**Rationale (Claude's recommended default):** Predictable cadence; faster iteration if a HelmRelease needs re-trigger during Phase 8 development; matches v0.18 spoke Kustomization cadence.

---

## Proxy `dependsOn` Operator

| Option | Description | Selected |
|--------|-------------|----------|
| A: Add `spec.dependsOn: [{ name: capsule, namespace: capsule-system }]` with `wait: true` on proxy HelmRelease | Proxy waits for operator readiness; mutual is NOT used | ✓ |
| B: No `dependsOn` | Both HelmReleases reconcile concurrently | |

**Selected option:** A — proxy `dependsOn` operator with `wait: true`.
**Rationale (Claude's recommended default):** Proxy's runtime depends on operator-installed CRDs (specifically `Tenant` CRD for proxy LIST filtering rules). Without `dependsOn`, proxy may attempt to start before CRDs land, generating noisy log output and brief CrashLoopBackOff. `wait: true` is cheap insurance (one-line YAML, ≤30s extra reconcile time on cold install).

---

## CapsuleConfiguration CR Scope (Phase 8 vs 9)

| Option | Description | Selected |
|--------|-------------|----------|
| A: Land in Phase 8 | Singleton `CapsuleConfiguration/default` with operator-default values; Phase 9 patches `forceTenantPrefix: true` + `allowServiceAccountPromotion: true` | |
| B: Defer entirely to Phase 9 | Phase 8 leaves operator with chart-default config; CR lands in Phase 9 alongside tenant policy | ✓ |

**Selected option:** B — defer to Phase 9.
**Rationale (Claude's recommended default):** Phase 8 goal is "Capsule operator alive + proxy reachable + CRDs visible". `CapsuleConfiguration` is tenant-relevant policy (covered by TEN-01..03 contracts in Phase 9). Landing the CR in Phase 8 with placeholder values then patching it in Phase 9 is two diffs where one suffices. Operator runs without an explicit `CapsuleConfiguration/default` (chart provides defaults at runtime).

---

## Test Scaffolding Pattern (Wave 0 RED bats)

| Option | Description | Selected |
|--------|-------------|----------|
| A: Repeat Phase 7 pattern | Plan 08-00 lands ALL Phase 8 bats RED before any HelmRelease yaml lands; subsequent plans turn green | ✓ |
| B: Land bats + yaml together | Each plan ships its own tests | |

**Selected option:** A — repeat Phase 7 Wave 0 pattern.
**Rationale (Claude's recommended default):** Nyquist gate — every executor task has a pre-existing automated test command. Worked in Phase 7 (39 tests across 8 bats files all green after Waves 1-3). No "implement and test in same plan" anti-pattern. Already-validated.

---

## k3d Port-Publish Flag Confirmation

| Option | Description | Selected |
|--------|-------------|----------|
| A: Inherit Phase 7's flag form, do not modify | `scripts/poc/capsule/create-cluster.sh` already locked port-publish; Phase 8 only verifies | ✓ |
| B: Re-evaluate `--port "30443:30443@server:0"` vs `@loadbalancer` | Re-decide during Phase 8 | |

**Selected option:** A — inherit, no modification.
**Rationale (Claude's recommended default):** Phase 7 already shipped CAPCLU-01 (cluster create with locked port-publish flag — verified live by milestone owner). Phase 8 inherits and verifies. If `curl -k https://127.0.0.1:30443/healthz` fails post-install, that's a Phase 7 cluster-shape defect (gap-close back to Phase 7), NOT a Phase 8 chart-config defect.

---

## Claude's Discretion

The following gray areas were intentionally not pinned (planner / researcher decide using the recommended defaults captured in `08-CONTEXT.md` → "Claude's Discretion"):

- HelmRelease values shape — values inline vs ConfigMap (recommended: inline for Phase 8's small surface; promote to ConfigMap pattern in Phase 9 if tenant-specific templating becomes the right shape)
- Operator namespace (recommended: `capsule-system`, chart default; `spec.targetNamespace: capsule-system` + `spec.install.createNamespace: true`)
- `kubectl --context` vs `KUBECONFIG=` invocation in bats live tests (recommended: `kubectl --context=k3d-{cluster}` explicit form; matches Phase 7 pattern)
- Plan ordering inside Phase 8 (recommended: 08-00 Wave 0 RED bats → 08-01 operator → 08-02 proxy → 08-03 verifier; planner may reshape into 2 or 4 plans)
- `task` surface extensions (recommended: NONE — install path is Flux-driven; verifier is bats / bare scripts)
- `HelmRelease.spec.upgrade.crds` policy (recommended: `CreateReplace` for operator chart per Capsule docs; proxy chart has no CRDs)
- Reconcile loop noise tolerance window (recommended: ≤2 cycles ≤10 min for operator HelmRelease Ready=True; ≤1 additional cycle ≤5 min for proxy with `dependsOn`; live-bats retry budget 3 attempts × 30s sleep)

---

## Folded Todos

- **Phase 7 carryover — hub Flux observable reconcile of `poc-capsule` Kustomization** (`.planning/todos/pending/2026-04-29-phase-7-hub-flux-observable-reconcile.md`, `resolves_phase: 8`).
  Folded as a load-bearing Phase 8 acceptance criterion in 08-CONTEXT.md `<domain>` point #5 and `<decisions>` D-08-09 live bats. Documented gap-close path (back to Phase 7 `--gaps`) preserves the Phase 7 SEAM-defect framing the original todo specified. Todo auto-closes when `/gsd-execute-phase 8` completes (per `resolves_phase: 8` and execute-phase.md `close_phase_todos` step).

---

## Reviewed Todos (Not Folded)

- **Phase 7 carryover — gitleaks rule fires on planning docs that quote inert synthetic fixture** (`.planning/todos/pending/2026-04-29-phase-7-gitleaks-planning-doc-allowlist.md`, `resolves_phase: 11`).
  Auto-mode relevance score (0.6) met the >= 0.4 fold threshold, but the explicit `resolves_phase: 11` marker overrode the score-based default. Phase 11 VAL-05 explicitly owns the one-shot history gitleaks scan post-Phase-10 first push; resolution must precede VAL-05. Phase 8 does NOT touch `.gitleaks.toml`, the named planning docs, or any related surface.

---

## Deferred Ideas

True deferrals to later phases (already locked at milestone-open or by ROADMAP / REQUIREMENTS un-bundling, restated for plan-side awareness; full list in 08-CONTEXT.md `<deferred>`):

- `CapsuleConfiguration/default` CR with `forceTenantPrefix: true` + `allowServiceAccountPromotion: true` → Phase 9 (TEN-01..03)
- Hub-Flux multi-tenancy lockdown patches (`--no-cross-namespace-refs`, `--no-remote-bases`, `--default-service-account`) + `flux-system` Kustomization `spec.serviceAccountName` → Phase 9 (TEN-05)
- Tenant CRs (alpha + bravo) + tenant inner Flux Kustomizations with P27 `spec.serviceAccountName` → Phase 9 (TEN-01..06)
- `dependsOn: tenants → operator with wait: true` (P32 CRD ordering for tenant CR apply) → Phase 9 (TEN-06)
- Tenant owner kubeconfigs + capsule-proxy round-trip + LIST visibility filtering → Phase 10 (PROXY-01..03)
- Negative RBAC bats suite (N1–N12), webhook failure / recovery, ordered teardown, `task rebuild` SLO regression, one-shot history gitleaks scan, ADR-008 → Phase 11 (VAL-01..06)
- `capsule-addon-fluxcd v0.2.3` trial → Phase 12 (OPTIONAL — gated on ADR-008 outcome ∈ {adopt, defer})

No out-of-band ideas surfaced during analysis. Discussion stayed within Phase 8 scope.
