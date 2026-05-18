# Phase 7: Foundation — POC Seam + spoke-capsule Cluster + EKS Capsule Doc - Context

**Gathered:** 2026-04-29
**Status:** Ready for planning

<domain>
## Phase Boundary

Foundational v0.19 layer that lands three coupled artifacts:

1. **Generic, sentinel-guarded POC onboarding seam** in the FLUX PATCH SURFACE (`# KARYON POC MOUNT`) so future POCs onboard consistently without modifying bootstrap-managed files.
2. **Persistent isolated `spoke-capsule` k3d cluster** on the shared `k8s-net` network, reconciled hub-only by the existing v0.18 Flux control plane (ADR-004 preserved — NO Flux on the spoke).
3. **Self-contained EKS-targeted Capsule rough-cut doc** (`docs/capsule-on-eks.md`) usable for an immediate team presentation while later phases land.

**Phase 7 ships infrastructure + docs only.** Capsule operator/proxy install (Phase 8), tenant CRs + lockdown patches (Phase 9), tenant-owner kubeconfigs + proxy round-trip (Phase 10), validation + graduation ADR (Phase 11) are explicitly out of scope.

The phase intentionally lands EKSDOC-01 first (or at most second) so the milestone owner has the team-presentation artifact in hand while the cluster + reconcile work proceeds in parallel.

</domain>

<decisions>
## Implementation Decisions

### EKS doc (`docs/capsule-on-eks.md` — EKSDOC-01)

- **D-01:** Audience and tone — Mixed Engineering + Cloud Ops, **brief**, biased toward calling out admin-required steps (e.g., install CRDs, IRSA setup) at a high level. YAML appears only on important items; no full reproduction of every manifest.
- **D-02:** Section (d) "Rough EKS install path" structure:
  - **Lead with a high-level walkthrough** of bare-minimum steps to deploy Capsule + capsule-proxy on EKS for a comparable POC.
  - **Verbatim YAML** for these admin-required items: (1) IRSA TrustPolicy for tenant ServiceAccounts (JSON trust policy + ServiceAccount IAM-role annotation); (2) capsule-proxy Service (LoadBalancer with NLB annotations OR ALB Ingress — note the AWS Load Balancer Controller dependency); (3) CapsuleConfiguration `allowedNodeSelectors` for VPC CNI / cluster-autoscaler / Karpenter interaction.
  - **Narrative-only** for: ECR-hosted Helm OCIRepository + ECR pull permissions for Flux source-controller SA; Capsule operator HelmRelease pin (chart + version called out by name; no full HelmRelease YAML).
- **D-03:** Topology diagram — **Mermaid** (matches `docs/architecture.md` style; native GitHub render). Source of truth for the topology is the ASCII diagram in `.planning/research/SUMMARY.md`; transcribe it into Mermaid syntax for the EKS-target audience.
- **D-04:** Section (e) "What this POC does NOT prove" — **locked 3-item structure**: (1) HA Capsule, (2) OIDC tenant authentication, (3) multi-spoke federation. Mirrors ADR-008's eventual `Status: Reviewed` framing so the EKS doc and graduation ADR speak the same vocabulary. Do NOT add EKS-flavored extras (e.g., IAM authenticator, multi-region) — those would diverge from ADR-008 alignment.

### POC seam shape (POC-01, POC-02)

- **D-05:** `# KARYON POC MOUNT` sentinel placement — **BELOW the existing `# KARYON SPOKES MOUNT`** in `clusters/hub-flux/flux-system/kustomization.yaml`. Final resource ordering:
  ```
  - gotk-components.yaml
  - gotk-sync.yaml
  # KARYON SPOKES MOUNT
  - ../spokes
  # KARYON POC MOUNT
  - ../pocs
  ```
  Reads naturally (production baseline above experimental); new sentinel becomes the file's tail extension point so future POCs land in one place.
- **D-06:** `clusters/hub-flux/pocs/` directory structure — **peer aggregator + flat `capsule.yaml`**, mirroring the spokes/ pattern exactly:
  ```
  clusters/hub-flux/pocs/
  ├── kustomization.yaml          # resources: [capsule.yaml]
  └── capsule.yaml                 # outer Flux Kustomization (kubeConfig.secretRef.name: spoke-capsule-kubeconfig + key: value.yaml)
  ```
  FLUX PATCH SURFACE references `- ../pocs`. Adding future POCs (Crossplane, Linkerd, vcluster) is a 1-line edit to `pocs/kustomization.yaml` instead of the bootstrap-managed-adjacent file.
- **D-07:** `scripts/register-poc-cluster.sh` signature — single positional arg `<cluster-name>`; the kubectl context is **implicitly `k3d-${cluster-name}`** (direct mirror of `scripts/register-spokes-for-flux.sh`). No `--context` flag, no second positional. Fails fast if the implicit context is missing. This stays simple for k3d-only use; EKS registration is explicitly out of scope (the EKS doc is documentation, not a registration target in v0.19).
- **D-08:** Phase 7 contents under `scripts/poc/capsule/` — **`create-cluster.sh` (CAPCLU-01) + `fix-dns.sh` (CAPCLU-03 / surfaces as `task fix-dns-poc-capsule`)** ONLY. Capsule operator + capsule-proxy scripts defer to Phase 8; tenant kubeconfig minting (`issue-tenant-kubeconfig.sh`, vendored `create-user.sh`) defers to Phase 10; ordered POC teardown (`task destroy-poc capsule`) defers to Phase 11 (VAL-03). Phase 7 is lifecycle bookend → install/proxy → tenants → validation, in that order.

### Locked invariants inherited from milestone-open + v0.18 close (every plan must respect)

- **D-09:** `# KARYON POC MOUNT` location is **`clusters/hub-flux/flux-system/kustomization.yaml`** (the FLUX PATCH SURFACE). NOT `clusters/hub-flux/kustomization.yaml`. Putting it in the wrong file means the sentinel does not survive `flux bootstrap` re-runs.
- **D-10:** `spoke-capsule` k3d cluster pins: apiserver port **6446**, NodePort **30443** published, `--tls-san k3d-spoke-capsule-server-0`, on shared `k8s-net` network. (CAPCLU-01)
- **D-11:** Outer Kustomization at `clusters/hub-flux/pocs/capsule.yaml` uses `spec.kubeConfig.secretRef.name: spoke-capsule-kubeconfig` AND `key: value.yaml` (P18 inheritance — defense against silent in-cluster fallback). (CAPCLU-02)
- **D-12:** All Capsule POC concerns isolated under `scripts/poc/capsule/` (P31). The v0.18 scripts `{create-clusters,register-spokes-for-flux,health-check,destroy,delete-clusters,rebuild}.sh` MUST NOT mention `spoke-capsule`. Static bats grep enforces zero mentions. Phase 11 will add the live regression: `task rebuild` SLO < 230s with spoke-capsule alive.
- **D-13:** `docs/capsule-on-eks.md` (EKSDOC-01) lands **FIRST** in Phase 7 plan order — milestone owner needs the rough-cut for an immediate team presentation while later phases land. Status may stay `Draft` until Phase 11 graduation rolls it forward to `Reviewed`.
- **D-14:** `.gitleaks.toml` MUST gain a new explicit rule for `kind: Config` + bearer-token shape by end of Phase 7 (P29). `.gitignore` gains tenant-kubeconfig globs to match Phase 10's `${TMPDIR:-/tmp}/karyon-tenants/` destination.
- **D-15:** `task preflight` reserves NodePort 30443 with **fail-fast** behavior (CAPCLU-04 literal contract: "fails fast if the port is already in use"). Note: this inverts the v0.18 `check_port()` pattern in `scripts/preflight.sh`, which currently warns rather than fails. Planner must decide: extend `check_port()` with a fail-fast variant, OR add a separate POC-aware preflight section that fails on 30443 only.
- **D-16:** `task fix-dns-poc-capsule` recovers spoke-capsule alone — MUST NOT affect the v0.18 default `task fix-dns` behavior. Implementation: `scripts/poc/capsule/fix-dns.sh` (Capsule POC subdirectory; aligns with D-12 P31 isolation).
- **D-17:** ADR-004 hub-only Flux preserved — NO Flux runs on spoke-capsule. The hub kustomize-controller reconciles into spoke-capsule via `spec.kubeConfig` exactly as it does for spoke-apps and spoke-ml.

### Claude's Discretion

The following gray areas were intentionally NOT discussed; planner and researcher should default to v0.18 patterns and note the chosen approach in PLAN.md without re-asking:

- **gitleaks rule shape (POC-03 sub-decisions)** — combined `kind: Config` + bearer-token rule vs separate ORed rules; synthetic-fixture location; per-path allowlist strategy. **Recommended default**: single combined rule (lower false-positive surface), fixtures under `tests/fixtures/gitleaks/` with per-path allowlist in `.gitleaks.toml`, minimum coverage = 1 positive (real-shape kubeconfig + bearer token, MUST be caught) + 1 negative (configmap or unrelated yaml, MUST NOT be caught).
- **`scripts/poc/capsule/create-cluster.sh` idempotency model** — recreate / skip-if-exists / fail-if-exists. **Recommended default**: skip-if-exists with config-drift verify, mirroring `scripts/create-clusters.sh` (`k3d cluster list` check + apiserver-port + network-name verification; fail with explicit fix instructions on drift).
- **`task fix-dns-poc-capsule` scope inside `scripts/poc/capsule/fix-dns.sh`** — restart spoke-capsule alone vs also touch hub-flux CoreDNS. **Recommended default**: mirror `scripts/fix-coredns.sh` adapted for spoke-capsule alone (k3d cluster stop/start spoke-capsule; verify spoke kubelet ready; do NOT restart hub-flux because the v0.18 `task fix-dns` already covers that surface).
- **`task preflight` 30443 fail-fast scoping** — unconditional vs only-when-spoke-capsule-exists. **Recommended default**: unconditional fail-fast (CAPCLU-04 literal phrasing); the cost of preflight failing on a stale 30443 listener for a user who never opted into the POC is one error message, which is acceptable.
- **`docs/poc-capsule.md` host-restart procedure depth** — paragraph quickstart vs full runbook. **Recommended default**: a quickstart-style "Host restart recovery" section (run `task fix-dns-poc-capsule`; what to expect; how to verify) plus a brief "Troubleshooting" subsection covering Docker/WSL restart edge cases. Full POC runbook (issue-tenant-kubeconfig delivery contract, etc.) accumulates as Phases 8-10 land.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project planning artifacts (REQUIRED reading)

- `.planning/REQUIREMENTS.md` — POC-01..04, CAPCLU-01..04, EKSDOC-01 contracts; load-bearing P27/P29/P31 invariants; KARYON POC MOUNT location lock; v0.19 inheritance from v0.18 ADRs.
- `.planning/ROADMAP.md` (Phase 7 section + Phase 11 graduation context for ADR-008) — phase goal, ordered success criteria, dependency declarations.
- `.planning/PROJECT.md` — v0.19 out-of-scope items (OIDC, prod ingress, multi-spoke federation, hub-side Capsule, default platform adoption); ADR-004 hub-only invariant; public-repo secrets contract.
- `.planning/STATE.md` — milestone-open decisions: 6-phase split rationale, two-HelmRelease decision, EKSDOC-01 first-or-second lock, P27/P29/P31 invariants.

### Architecture Decision Records (load-bearing for Phase 7)

- `docs/adr/0001-single-wsl2-shared-docker-network.md` — k8s-net shared bridge network (spoke-capsule joins this network).
- `docs/adr/0002-k3d-over-kind.md` — k3d cluster runtime; informs spoke-capsule create-cluster.sh.
- `docs/adr/0003-flux-over-argocd.md` — Flux 2 as GitOps tool; informs outer Kustomization shape.
- `docs/adr/0004-hub-only-flux-control-plane.md` — **load-bearing**: NO Flux on spoke-capsule; hub reconciles via `spec.kubeConfig`.
- `docs/adr/0005-kubernetes-version-pin.md` — k3s `v1.34.6-k3s1` clears Capsule v0.12.x's k8s ≥ 1.34.0 floor with 6 patches of margin.

### Milestone-level research (REQUIRED for planning)

- `.planning/research/SUMMARY.md` §"Mental Model", §"Recommended Phase Split → Phase 7", §"Architectural Correction" — phase boundary, sentinel placement, two-HelmRelease rationale.
- `.planning/research/STACK.md` — Capsule v0.12.4, capsule-proxy v0.12.0 pins, k8s ≥ 1.34 floor, k3d/k3s/Flux pins.
- `.planning/research/ARCHITECTURE.md` — topology diagram, KARYON POC MOUNT placement justification, outer reconcile pattern.
- `.planning/research/PITFALLS.md` — P26-P43 catalogue. Phase 7 directly addresses **P28** (NodePort host-publish), **P29** (kubeconfig leak — defense in Phase 7, full closure in Phase 11), **P30** (sentinel collision), **P31** (POC isolation from rebuild — D-12 contract), **P35** (per-cluster CoreDNS recovery), **P39** (port 30443 reservation), **P40** (P18 `key: value.yaml` invariant on outer Kustomization).
- `.planning/research/FEATURES.md` — Capsule feature surface (informs EKS doc section (b) "the 7 CRDs").

### v0.18 reference implementations (analogs to mirror in Phase 7)

- `clusters/hub-flux/flux-system/kustomization.yaml` — FLUX PATCH SURFACE; existing `# KARYON SPOKES MOUNT` sentinel pattern. **EXACT** insertion point for `# KARYON POC MOUNT` per D-05.
- `clusters/hub-flux/spokes/kustomization.yaml` + `clusters/hub-flux/spokes/spoke-apps.yaml` — peer aggregator + flat per-spoke Kustomization pattern. **DIRECT** template for `clusters/hub-flux/pocs/kustomization.yaml` + `clusters/hub-flux/pocs/capsule.yaml` per D-06 and D-11.
- `scripts/register-spokes-for-flux.sh` — sentinel + idempotent yq+awk insertion; SA + cluster-admin CRB + legacy SA-token Secret on spoke; imperative apply to hub-flux Secret. **DIRECT** template for `scripts/register-poc-cluster.sh` per D-07.
- `scripts/preflight.sh` (`check_port()` helper, lines around port 6443/6444/6445/8080-8082 loop) — **adaptation source**: invert from warn-on-in-use to fail-fast for 30443 per D-15.
- `scripts/fix-coredns.sh` — hub-flux stop/start pattern. **DIRECT** template for `scripts/poc/capsule/fix-dns.sh` (substitute spoke-capsule cluster name; do NOT touch hub-flux) per D-16.
- `scripts/create-clusters.sh` — idempotent skip-if-exists with config-drift verify. **TEMPLATE** for `scripts/poc/capsule/create-cluster.sh` idempotency model (Claude's Discretion default).
- `scripts/lib/preflight-lib.sh` — shared output helpers (`section`, `pass`, `warn`, `fail`, `info`, `have`). All new POC scripts source this.
- `.gitignore` (Phase 6 D-16 expansion section: `kubeconfig*`, `*.kubeconfig`, `*.pem`, `*.key`, `*.crt`) — extension point for tenant-kubeconfig globs per D-14.
- `.gitleaks.toml` (current allowlist-only state) — new explicit rule lands here per D-14.
- `docs/architecture.md` — **Mermaid diagram style template** for `docs/capsule-on-eks.md` per D-03.
- `Taskfile.yml` — top-level task naming pattern (`task fix-dns`, `task preflight`). New tasks `task fix-dns-poc-capsule` and the 30443 reservation in `task preflight` extend this surface.

### Test infrastructure

- `tests/bats/` — naming convention `<area>-<NN>-<topic>.bats`, `load 'test_helper'` boilerplate, `setup()` with REPO_ROOT, `[ "$status" -eq 0 ]` style, `grep -F --` for literal text. New Phase 7 bats files follow this exact convention.
- `tests/bats/test_helper` — shared loader.
- `tests/bats/preflight-pre*.bats` — pattern for preflight section bats (extension point for new 30443 reservation test).
- `tests/bats/register-spokes-01-static.bats` — pattern for static contract bats (template for new POC seam static contract tests).
- `tests/bats/fix-coredns-01-static.bats` — pattern for the new `fix-dns-poc-capsule` static contract.
- `tests/bats/docs-02-architecture.bats` and `tests/bats/docs-adr-template.bats` — pattern for the new EKSDOC-01 doc-shape contract bats.

### External upstream references (for EKS doc; informational, no edits)

- Capsule project — `https://capsule.clastix.io/` (linked from REQUIREMENTS.md).
- Capsule operator chart — `oci://ghcr.io/projectcapsule/charts/capsule:0.12.4`.
- capsule-proxy chart — `oci://ghcr.io/projectcapsule/charts/capsule-proxy:0.12.0`.
- AWS Load Balancer Controller — referenced from EKS doc section (d) when discussing ALB Ingress for capsule-proxy.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- **`scripts/lib/preflight-lib.sh`** — output helpers (`section`, `pass`, `warn`, `fail`, `info`, `have`). All new Phase 7 scripts (`scripts/register-poc-cluster.sh`, `scripts/poc/capsule/create-cluster.sh`, `scripts/poc/capsule/fix-dns.sh`) source this for consistent ergonomics with v0.18.
- **`check_port()` helper in `scripts/preflight.sh`** — `ss -ltn` + awk + grep pattern to detect listeners on a port. Phase 7 either reuses (with a fail-fast wrapper) or duplicates the pattern in a new `check_port_strict()` for the 30443 reservation per D-15.
- **`bats/test_helper`** — shared loader pinning `REPO_ROOT`. Phase 7 bats files load this without modification.
- **Mermaid diagram source in `docs/architecture.md`** — direct stylistic template for the EKS doc topology diagram per D-03.
- **`.gitleaks.toml` allowlist conventions (`[allowlist]` `regexes` + `paths`)** — pattern for the new test-fixture allowlist if planner takes the per-path allowlist default.

### Established Patterns

- **Idempotent skip-if-exists with config-drift verify** (`scripts/create-clusters.sh` lines around `docker network inspect $K8S_NET_NAME` and `k3d cluster create` blocks). Pattern: check existence; on drift, fail with explicit fix instructions; on match, log "already done, skipping". `scripts/poc/capsule/create-cluster.sh` follows this pattern (Claude's Discretion default).
- **Sentinel + yq+awk insertion** (`scripts/register-spokes-for-flux.sh` block that inserts `# KARYON SPOKES MOUNT` + `- ../spokes` into the FLUX PATCH SURFACE). Phase 7 mirrors for `# KARYON POC MOUNT` + `- ../pocs`. Should be invoked at most once (sentinel-uniqueness check).
- **Per-spoke Flux Kustomization** (`clusters/hub-flux/spokes/spoke-apps.yaml`): explicit `key: value.yaml` on every `secretRef`, `prune: true`, `sourceRef.kind: GitRepository name: flux-system`. `clusters/hub-flux/pocs/capsule.yaml` is a structural copy with the spoke name swapped.
- **Bash strict-mode + REPO_ROOT/SCRIPT_DIR pinning at script head** (every existing v0.18 script). New Phase 7 scripts adopt the identical preamble.
- **Bats static-contract test naming `<area>-<NN>-static.bats`** + `setup()` with `REPO_ROOT` + `grep -F --` for literal text matches. Phase 7 adopts this convention without invention.
- **Imperative kubeconfig Secret apply (NEVER committed)** (`scripts/register-spokes-for-flux.sh` block that pipes `kubectl create secret generic ... --from-literal=value.yaml=...` to hub-flux). Phase 7 reuses this exact pattern for `spoke-capsule-kubeconfig`.

### Integration Points

- **FLUX PATCH SURFACE insertion**: `clusters/hub-flux/flux-system/kustomization.yaml` gets `# KARYON POC MOUNT` + `- ../pocs` appended below the existing `# KARYON SPOKES MOUNT` + `- ../spokes` lines per D-05. The static contract bats grep-asserts both sentinels exist on distinct lines and both resource paths follow.
- **Aggregator + flat outer Kustomization**: `clusters/hub-flux/pocs/kustomization.yaml` (resources: [capsule.yaml]) + `clusters/hub-flux/pocs/capsule.yaml` (outer Flux Kustomization) are net-new files committed in Phase 7 per D-06.
- **Hub-side Secret apply**: `spoke-capsule-kubeconfig` Secret applied imperatively to `flux-system` namespace on hub-flux at register-time by `scripts/register-poc-cluster.sh` (NOT git-tracked) per D-07. Mirrors v0.18 spoke-{apps,ml}-kubeconfig pattern.
- **`task preflight` extension**: existing port loop (`6443 6444 6445 8080 8081 8082`) gains 30443. The fail-fast distinction means either a separate strict check or a new `check_port_strict()` helper — planner picks per D-15.
- **`task fix-dns-poc-capsule` registration**: new top-level task in `Taskfile.yml` calling `bash scripts/poc/capsule/fix-dns.sh`. Distinct from the existing `task fix-dns` (which calls `scripts/fix-coredns.sh` for hub-flux only).
- **`docs/poc-capsule.md` cross-link**: README and architecture.md gain links to the new POC doc + new EKS doc. Planner decides cross-link depth (Claude's Discretion).

</code_context>

<specifics>
## Specific Ideas

- **EKS doc audience phrasing** (verbatim from discussion): "Mixed Eng + Cloud Ops... keep it brief, but we need to let them know high level things we need to do that generally require admin... e.g., install crds... some full yaml is okay but don't overdo it, just important items." Drives D-01 + D-02 jointly: section (d) leads with admin-required steps walkthrough, then the three locked YAML blocks (IRSA, LB/ALB, VPC nodeSelector).
- **EKS doc structural anchor** — section (d) `## Rough EKS install path` should have a top-level "high-level steps to get capsule deployed bare minimum for POC" walkthrough as a numbered list, then per-component deep dives. The walkthrough is the Cloud Ops orientation; the deep dives serve the Eng audience.
- **Mermaid topology source** — the ASCII diagram in `.planning/research/SUMMARY.md` §"Mental Model" → §"ASCII Diagram" is the validated topology source of truth. Transcribing to Mermaid preserves: hub-flux outer reconcile arrow, spoke-capsule NodePort 30443 publish, the "Tenants Kustomizations live in tenant ns on spoke-capsule, picked up by hub controller" callout, and the explicit "no Flux on spoke-capsule" caption.
- **Explicit "what's NOT yet wired" callout in the EKS doc** — section (d) should call out `not yet wired in the k3d POC` items so Cloud Ops sees the EKS-side delta clearly: ECR pull permissions for Flux SA, IRSA TrustPolicy on tenant SAs, AWS Load Balancer Controller install, ALB Ingress class. This is implicit in D-02 but worth surfacing for the planner.
- **Aggregator filename consistency** — `clusters/hub-flux/spokes/kustomization.yaml` is the existing precedent; `clusters/hub-flux/pocs/kustomization.yaml` MUST use the identical file name (not `aggregator.yaml`, not `index.yaml`). Bats static contract should grep-assert this exact path.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within Phase 7 scope.

The following gray areas were acknowledged but routed to **Claude's Discretion** (planner/researcher decide using the recommended defaults captured under `<decisions>` → "Claude's Discretion"); they are NOT deferred to a later phase:

- gitleaks rule shape + test fixture strategy (POC-03 sub-decisions)
- `scripts/poc/capsule/create-cluster.sh` idempotency model
- `task fix-dns-poc-capsule` exact scope inside `scripts/poc/capsule/fix-dns.sh`
- `task preflight` 30443 fail-fast scoping (unconditional vs conditional)
- `docs/poc-capsule.md` host-restart procedure depth

True deferrals to later phases (already locked at milestone-open, restated for plan-side awareness):

- Capsule operator + capsule-proxy install → **Phase 8** (CAP-01, CAP-02, CAP-03)
- Tenant CRs + Flux multi-tenancy lockdown patches → **Phase 9** (TEN-01..06)
- Tenant-owner kubeconfigs + capsule-proxy round-trip → **Phase 10** (PROXY-01..03)
- Negative RBAC suite + webhook failure + clean teardown + graduation ADR → **Phase 11** (VAL-01..06)
- capsule-addon-fluxcd trial → **Phase 12** (OPTIONAL, gated on ADR-008 outcome)

</deferred>

---

*Phase: 07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc*
*Context gathered: 2026-04-29*
