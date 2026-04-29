# Phase 7: Foundation — POC Seam + spoke-capsule Cluster + EKS Capsule Doc - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-29
**Phase:** 07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc
**Areas discussed:** EKS doc shape & structure, POC seam shape & layout

---

## Gray Area Selection

| Option | Description | Selected |
|--------|-------------|----------|
| POC seam shape & layout | Sentinel ordering, pocs/ aggregator pattern, register-poc-cluster.sh arg shape, scripts/poc/capsule/ contents | ✓ |
| EKS doc shape & structure | Length, code snippets, diagram strategy, "what POC doesn't prove" framing | ✓ |
| gitleaks rule + test fixture strategy | Rule shape, fixture location, allowlist strategy, fixture coverage | |
| Host-restart recovery + cluster lifecycle | create-cluster.sh idempotency, fix-dns scope, preflight 30443 behavior, docs/poc-capsule.md depth | |

**Notes:** User selected EKS doc + POC seam. The other two areas were routed to Claude's Discretion with recommended defaults captured in CONTEXT.md.

---

## EKS doc shape & structure

### Q1: Audience and tone for `docs/capsule-on-eks.md`

| Option | Description | Selected |
|--------|-------------|----------|
| Mixed eng + leadership | Hybrid: 1-paragraph narrative per section + concrete pin/SA/Service-type values, no full YAML manifests. | |
| Engineers (deep) | YAML-first: full HelmRelease + IRSA TrustPolicy + LoadBalancer/ALB Service snippets verbatim, ready to lift onto an EKS cluster. Length scales to 2-3 pages. | |
| Leadership (narrative) | Prose-only: explains what Capsule is, what changes EKS-side (auth, ingress, registry), what POC doesn't prove. No YAML — cite components by name only. | |
| (User free-text) | Mixed Eng + Cloud Ops; brief; some full yaml is okay but don't overdo it, just important items; signal high-level admin-required things (e.g., install CRDs) | ✓ |

**User's choice:** Free-text — Mixed Eng + Cloud Ops, brief, admin-action-focused, selective YAML.
**Notes:** Verbatim quote: "Mixed Eng + Cloud Ops... keep it brief, but we need to let them know high level things we need to do that generally require admin... e.g., install crds... some full yaml is okay but don't overdo it, just important items." Drove the structure of section (d): high-level walkthrough first, then admin-required YAML deep dives.

---

### Q2: Section (d) "Rough EKS install path" — which items get verbatim YAML?

| Option | Description | Selected |
|--------|-------------|----------|
| IRSA TrustPolicy for tenant SAs | Cloud Ops needs to lift this into Terraform / EKS module — JSON trust policy + ServiceAccount annotation. | ✓ |
| LoadBalancer / ALB Ingress for capsule-proxy | Replaces NodePort 30443. Service type LoadBalancer with NLB annotations OR ALB Ingress — needs AWS Load Balancer Controller. | ✓ |
| ECR-hosted Helm OCIRepository | OCIRepository pointing at ECR + ECR pull permissions for the Flux source-controller SA. | |
| VPC CNI / nodeSelector tenant policy | CapsuleConfiguration allowedNodeSelectors snippet — cluster-autoscaler / Karpenter interaction. | ✓ |
| (User free-text) | High-level steps to get capsule deployed bare minimum for POC | ✓ |

**User's choice:** IRSA, LB/ALB, VPC nodeSelector, plus a "high-level walkthrough" structural anchor. ECR is narrative-only.
**Notes:** The "high level steps to get capsule deployed bare minimum for POC" addition implies a numbered walkthrough at the top of section (d) before the admin-detail YAML blocks. Cloud Ops orientation first, Engineering depth second.

---

### Q3: Topology diagram in `docs/capsule-on-eks.md`

| Option | Description | Selected |
|--------|-------------|----------|
| Mermaid (matches architecture.md) | GitHub renders Mermaid natively in markdown previews. Matches docs/architecture.md style. | ✓ |
| ASCII (matches research SUMMARY.md) | Plain-text box diagram. Renders identically everywhere. Already proven in .planning/research/SUMMARY.md for this exact topology. | |
| No diagram — narrative only | Skip the diagram, lean on the high-level walkthrough + YAML snippets to convey topology. | |

**User's choice:** Mermaid (matches architecture.md).
**Notes:** Source of truth for the Mermaid is the ASCII topology diagram in `.planning/research/SUMMARY.md` §"Mental Model" → §"ASCII Diagram". Transcribe, don't redesign.

---

### Q4: Section (e) "What this POC does NOT prove" framing

| Option | Description | Selected |
|--------|-------------|----------|
| Locked 3-item structure | Three explicit subsections: HA Capsule, OIDC tenant authentication, multi-spoke federation. Mirrors ADR-008's eventual Status: Reviewed framing. | ✓ |
| Organic, EKS-context-flavored | Free-form list of EKS-specific non-proofs (HA Capsule, OIDC, multi-region, IAM authenticator integration, EKS-managed nodegroup interactions). | |
| Locked 3 + EKS appendix | Lock the 3 ADR-008 items as primary list, then append an 'EKS-specific not-yet-validated' subsection. | |

**User's choice:** Locked 3-item structure.
**Notes:** Aligns the EKS doc and the eventual graduation ADR-008 vocabulary. EKS-flavored extras (IAM authenticator, multi-region, etc.) are intentionally NOT added to keep the doc and ADR speaking the same language.

---

## POC seam shape & layout

### Q1: `# KARYON POC MOUNT` sentinel placement in `clusters/hub-flux/flux-system/kustomization.yaml`

| Option | Description | Selected |
|--------|-------------|----------|
| Below SPOKES MOUNT | Order: gotk-components.yaml, gotk-sync.yaml, # KARYON SPOKES MOUNT, ../spokes, # KARYON POC MOUNT, ../pocs. Production-baseline above experimental reads naturally. | ✓ |
| Above SPOKES MOUNT | Order: gotk-components.yaml, gotk-sync.yaml, # KARYON POC MOUNT, ../pocs, # KARYON SPOKES MOUNT, ../spokes. Surfaces POC scope first. | |
| Between gotk lines and SPOKES MOUNT | Inserts POC mount as a middle 'experimental layer' between bootstrap files and the spokes baseline. | |

**User's choice:** Below SPOKES MOUNT.
**Notes:** Recommended option. Matches the spokes pattern's role as a trailing extension point and minimizes diff churn.

---

### Q2: `clusters/hub-flux/pocs/` directory structure

| Option | Description | Selected |
|--------|-------------|----------|
| Aggregator + flat capsule.yaml (mirrors spokes/) | pocs/kustomization.yaml lists `resources: [capsule.yaml]`; FLUX PATCH SURFACE references `- ../pocs`. Identical pattern to spokes/. | ✓ |
| No aggregator — flat resources directly in PATCH SURFACE | FLUX PATCH SURFACE references `- ../pocs/capsule.yaml` directly. Slightly more brittle. | |
| Aggregator + Capsule subdir | pocs/kustomization.yaml lists capsule subdir; capsule subdir has its own kustomization.yaml. Diverges from roadmap's `pocs/capsule.yaml` literal. | |

**User's choice:** Aggregator + flat capsule.yaml (mirrors spokes/).
**Notes:** Direct mirror of v0.18 spokes/ pattern. Adding future POCs becomes a 1-line edit to pocs/kustomization.yaml instead of touching the FLUX PATCH SURFACE.

---

### Q3: `scripts/register-poc-cluster.sh` kubectl context discovery

| Option | Description | Selected |
|--------|-------------|----------|
| Implicit `k3d-${cluster-name}` | Script assumes context name is `k3d-${cluster-name}`. Simplest signature — single positional. Fails fast if context missing. | ✓ |
| Optional `--context <ctx>` override | Default to `k3d-${cluster-name}` but support `--context my-ctx` for non-k3d kubeconfigs (e.g., user pre-imported an EKS context). | |
| Required `<cluster-name> <kubectl-context>` | Two positional args. Most flexible; least convenient. Diverges most from v0.18 mirror pattern. | |

**User's choice:** Implicit `k3d-${cluster-name}`.
**Notes:** Direct mirror of v0.18 register-spokes-for-flux.sh pattern. EKS registration is out of scope for v0.19; the EKS doc is documentation, not a registration target.

---

### Q4: `scripts/poc/capsule/` directory contents in Phase 7

| Option | Description | Selected |
|--------|-------------|----------|
| create-cluster.sh + fix-dns.sh | Tightly scoped to lifecycle; Capsule install scripts defer to Phase 8; tenant kubeconfig scripts defer to Phase 10. | ✓ |
| create-cluster.sh + fix-dns.sh + skeleton README | Same as above + scripts/poc/capsule/README.md stub explaining the directory contract. | |
| create-cluster.sh + fix-dns.sh + destroy.sh | Lifecycle bookends in Phase 7. Phase 11 already locks `task destroy-poc capsule` for the full ordered teardown. | |

**User's choice:** create-cluster.sh + fix-dns.sh.
**Notes:** Tight Phase 7 scope. Defer install (Phase 8), tenant ops (Phase 10), and full POC teardown (Phase 11) to their own phases.

---

## Wrap-up: explore more or done?

| Option | Description | Selected |
|--------|-------------|----------|
| I'm ready for context | Lock decisions captured so far and proceed to CONTEXT.md. Researcher and planner will use Claude's discretion (with v0.18 patterns + locked invariants as guardrails) for unselected areas. | ✓ |
| Explore gitleaks rule + test fixture strategy | Decide rule shape, fixture location, allowlist strategy, fixture coverage. | |
| Explore host-restart recovery + cluster lifecycle | create-cluster.sh idempotency, fix-dns scope, preflight 30443 behavior, docs/poc-capsule.md depth. | |

**User's choice:** I'm ready for context.
**Notes:** Two areas (gitleaks defense + host-restart recovery) routed to Claude's Discretion with recommended defaults documented in CONTEXT.md. Planner can deviate but must record the deviation in PLAN.md.

---

## Claude's Discretion

The following sub-areas were intentionally NOT discussed and are routed to planner/researcher with recommended defaults (full text in CONTEXT.md `<decisions>` → "Claude's Discretion"):

- **gitleaks rule shape (POC-03)** — single combined `kind: Config` + bearer-token rule recommended; fixtures under `tests/fixtures/gitleaks/` with per-path allowlist.
- **`scripts/poc/capsule/create-cluster.sh` idempotency** — skip-if-exists with config-drift verify (mirrors `scripts/create-clusters.sh`).
- **`task fix-dns-poc-capsule` scope** — restart spoke-capsule alone (mirror of `scripts/fix-coredns.sh` adapted; do NOT touch hub-flux).
- **`task preflight` 30443 reservation** — unconditional fail-fast (CAPCLU-04 literal phrasing).
- **`docs/poc-capsule.md` depth** — quickstart + brief Troubleshooting subsection; full POC runbook accumulates as Phases 8-10 land.

## Deferred Ideas

No new ideas surfaced during discussion that fall outside Phase 7 scope. All work referenced is either Phase 7 work or already locked at milestone-open for Phases 8-12 (Capsule install → tenants → kubeconfigs → validation → optional addon trial).
