# Phase 11: Validation + Graduation ADR-008 - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-05
**Phase:** 11-validation-graduation-adr-008
**Areas discussed:** Push-gate carryover + first push, Negative RBAC probe strategy (VAL-01), Webhook failure + teardown (VAL-02 / VAL-03), SLO regression + ADR-008 rubric (VAL-04 / VAL-06)

**Mode:** default (interactive); user selected ALL 4 gray areas via initial multi-select.

---

## Push-gate carryover + first push (VAL-05 + Phase 10 carryover)

### capsule-proxy chart-level RBAC patch persistence

| Option | Description | Selected |
|--------|-------------|----------|
| PostBuild patch on outer K (Recommended) | Add patch block to `clusters/hub-flux/pocs/capsule.yaml` extending chart-rendered Role with `secrets get/create/update/patch`. Hub-side outer-K boundary; consistent with Phase 9 D-09-05 lockdown patch surface pattern; survives Flux reconciliation; single canonical surface. | ✓ |
| Kustomize overlay in pocs/capsule/proxy/ | `patches:` block in proxy kustomization.yaml; chart-locality. Needs HelmRelease postRenderers; less idiomatic for hub-only Flux + spec.kubeConfig path. | |
| Upstream chart fix (carryover out of v0.19) | File issue/PR on projectcapsule/capsule-proxy chart; v0.19 ships A or B as actual fix; this becomes ADR-008 trade-offs note only. | |

**User's choice:** PostBuild patch on outer K
**Notes:** Locked as **D-11-01**. Mirrors Phase 9 D-09-05 patch-surface pattern; hub-side declarative.

---

### CapsuleConfiguration `userGroups` patch persistence

| Option | Description | Selected |
|--------|-------------|----------|
| Update repo file (Recommended) | Edit `pocs/capsule/spoke/config/capsuleconfig.yaml` directly to inline 3-group userGroups. Single source of truth; matches D-09-04 framing (CapsuleConfiguration as default singleton); zero patch indirection. | ✓ |
| PostBuild patch on outer K (matches D-11-01) | Add patches block to `clusters/hub-flux/pocs/capsule-spoke.yaml` mutating `spec.userGroups`. Mirrors D-11-01 pattern; more indirection than directly editing the singleton. | |
| Webhook MutatingAdmissionPolicy | k8s 1.30+ MutatingAdmissionPolicy auto-injects groups. Maximally declarative; alpha API; over-engineered for POC. | |

**User's choice:** Update repo file
**Notes:** Locked as **D-11-02**. CapsuleConfiguration is a default singleton — repo file IS the canonical source.

---

### Tenant home namespace ownership label

| Option | Description | Selected |
|--------|-------------|----------|
| Add label to YAML — trust no webhook reject (Recommended) | Inline `metadata.labels.capsule.clastix.io/tenant: <name>` in namespace.yaml; trust cluster-admin Flux apply bypasses webhook prefix-violation (Capsule's documented exemption). Falsifier bats verifies. | ✓ |
| Operator runbook — manual --as=<tenant> impersonation | Document in docs/poc-capsule.md that operator runs `kubectl --as=alpha create namespace tenant-alpha`. Matches Plan 10-02 verifier verbatim; manual step fights 'reproducible from `task rebuild`' ethos. | |
| PostBuild Job that impersonates tenants | Add Job to pocs/capsule/spoke/ that runs at apply time with --as=alpha/bravo. Declarative; over-engineered if Option A works. | |

**User's choice:** Add label to YAML — trust no webhook reject
**Notes:** Locked as **D-11-03**. Falsifier bats catches assumption invalidation fast.

---

### Gitleaks planning-doc allowlist (folded todo)

| Option | Description | Selected |
|--------|-------------|----------|
| Option C — broad path-allowlist (Recommended) | Add `'^\.planning/.*\.md$'` to `.gitleaks.toml` `[allowlist] paths`. Future-proof; matches `.env.example` precedent; planning docs aren't a real leak surface. | ✓ |
| Option B — narrow per-fingerprint regexes | Specific `[[rules.allowlist.regexes]]` entries matching known-inert literal token strings. Narrowest exception; brittle. | |
| Option A — redact in-place in 3 planning docs | Replace `token: <hash-shaped>` with `token: <REDACTED-INERT>` in 07-00-PLAN.md, 07-RESEARCH.md, 07-REVIEW.md. Mutates plan history; philosophical concern. | |

**User's choice:** Option C — broad path-allowlist
**Notes:** Locked as **D-11-04**. Folds pending todo `2026-04-29-phase-7-gitleaks-planning-doc-allowlist.md` (resolves_phase: 11) into Phase 11 scope.

---

## Negative RBAC probe strategy (VAL-01)

### Probe shape — real CRUD apply path

| Option | Description | Selected |
|--------|-------------|----------|
| Real CRUD apply path — single probe (Recommended) | Each Nk asserts real `kubectl get/create/...` returns non-zero with specific error string. NOT `kubectl auth can-i` (SAR cache). Bypasses SAR cache; deterministic; matches research P37 prevention #2. | ✓ |
| Multi-probe consensus — SAR + CRUD + log | Three probes per Nk: auth can-i + real CRUD + capsule-controller log assertion. Triple-redundant; 3x assertion overhead per N; slow. | |
| Proxy-first — LIST through capsule-proxy | Prefer LIST through proxy for filtered subset assertion; bypasses SAR cache. Doesn't apply to escalation (N4) or webhook denials (N5/N6/N7); mixed-probe shape across suite. | |

**User's choice:** Real CRUD apply path — single probe
**Notes:** Locked as **D-11-05**. Anti-pattern lint forbids `kubectl auth can-i` in negative-rbac source files.

---

### Bats file partition

| Option | Description | Selected |
|--------|-------------|----------|
| Grouped by category (Recommended) | 5 bats files: cross-tenant-list (N1,N2,N3) / escalation (N4) / webhook-policy (N5,N6,N7) / bypass-and-flux (N8,N9,N10) / webhook-down (N11,N12). Tests sharing setup() co-locate; ~5 files keeps bats run fast; failure isolation per attack class. | ✓ |
| One file per N (12 files) | negative-rbac-01..12.bats; maximum isolation; 12x setup() duplication; fragments suite. | |
| Single file, 12 @tests | One bats file with 12 @tests; shared setup() automatic; failure-isolation lost. | |

**User's choice:** Grouped by category
**Notes:** Locked as **D-11-06**.

---

### Tenant kubeconfig sourcing inside bats setup()

| Option | Description | Selected |
|--------|-------------|----------|
| Mint once in suite setup_file(), cache to tmpdir (Recommended) | One TokenRequest per bats file; --duration=2h covers slow runs; tmpdir-rooted (P29); per-file isolation. | ✓ |
| Mint per @test in setup() | ~12 TokenRequest calls per bats file; 5-10s overhead per file. | |
| Reuse Phase 10 verifier kubeconfigs | Zero mint cost; stale 1h tokens; fragile coupling to Phase 10 cluster state. | |

**User's choice:** Mint once in suite setup_file(), cache to tmpdir
**Notes:** Locked as **D-11-07**.

---

### N8 direct-apiserver bypass falsifier

| Option | Description | Selected |
|--------|-------------|----------|
| Reuse Phase 10 D-10-08 falsifier pattern (Recommended) | Bats setup() builds direct kubeconfig in mktemp tmpdir; per Pitfall 10-P3 corrected shape, asserts 403 + 'cannot list resource' error string (NOT count comparison). | ✓ |
| Construct via direct in-cluster Service + Endpoint | Reach apiserver via cluster-internal kubernetes.default.svc:443 from tenant Pod with SA token mounted. More 'realistic'; overcomplicates CLI-side bats. | |
| Skip N8 — ROADMAP allows 'denied OR limited' | Skip falsifier; assert RBAC catches it. Weaker ADR-008 evidence; loses Phase 10 D-10-08 work. | |

**User's choice:** Reuse Phase 10 D-10-08 falsifier pattern
**Notes:** Locked as **D-11-08**. Pitfall 10-P3 corrected falsifier shape (qualitative 403, not count comparison) verbatim.

---

## Webhook failure + teardown (VAL-02 / VAL-03)

### task fail-capsule-webhook mechanism

| Option | Description | Selected |
|--------|-------------|----------|
| Scale deployment to 0 (Recommended) | `task fail-capsule-webhook -- 0|1` runs `kubectl scale deploy capsule-controller-manager --replicas=$1`. Recovery path uses `kubectl rollout status --timeout=90s`. Exact research P26/N12 mechanism; clean reversibility; matches ROADMAP VAL-02 verbatim. | ✓ |
| Delete deployment entirely | task fail-capsule-webhook deletes Deployment; recover reapplies via helm upgrade. HelmRelease may auto-restore; messier state recovery; over-engineered. | |
| Patch webhook failurePolicy to NoOp | Mutate MutatingWebhookConfiguration's failurePolicy: Ignore. Tests different failure mode; not aligned with VAL-02 verbatim wording. | |

**User's choice:** Scale deployment to 0
**Notes:** Locked as **D-11-09**.

---

### task destroy-poc capsule ordered teardown

| Option | Description | Selected |
|--------|-------------|----------|
| Strict 5-step canonical (Recommended) | (1) Suspend tenant Ks; (2) Delete Tenant CRs; (3) Poll cascade max 90s + auto-force-delete PVCs at 60s; (4) Suspend operator + config Ks; (5) Optional --full → k3d cluster delete. Sentinel preservation guarantee. | ✓ |
| Skip Flux suspend — delete Tenant CRs first | Just kubectl delete Tenant; let Flux fight. Hub-side K recreates tenants on next reconcile; matches research P36 anti-pattern. | |
| Nuclear-only — just k3d cluster delete spoke-capsule | Doesn't exercise Capsule's teardown story; ROADMAP demands ordered teardown; weak ADR-008 evidence. | |

**User's choice:** Strict 5-step canonical
**Notes:** Locked as **D-11-10**.

---

### PVC stranded handling

| Option | Description | Selected |
|--------|-------------|----------|
| Auto force-delete after 60s timeout (Recommended) | Polls 90s; at 60s timeout, kubectl patch pvc with finalizers:null. Matches research P36 prevention #4 verbatim; idempotent; deterministic 'no stuck namespaces after 90s' assertion. | ✓ |
| Warn + leave to operator | Logs warn with hint; bats VAL-03 assertion becomes flaky if PVCs strand. | |
| Skip PVC handling — v0.19 has no tenant PVCs in scope | Future-proofing zero; defensive coding cost is ~5 lines. | |

**User's choice:** Auto force-delete after 60s timeout
**Notes:** Locked as **D-11-11**.

---

### Task surface (where to define new tasks)

| Option | Description | Selected |
|--------|-------------|----------|
| Top-level POC tasks under `task` namespace (Recommended) | task fail-capsule-webhook + task destroy-poc as siblings of v0.18 tasks. Discoverability via `task --list`; precedent set by `task fix-dns-poc-capsule`. P31 by-location preserved. | ✓ |
| Nested Taskfile.poc.yml include | Hard isolation namespace; 3 commits to migrate fix-dns-poc-capsule; introduces churn. | |
| No tasks — direct script invocation | Zero Taskfile mutation; ROADMAP wording explicitly says `task destroy-poc capsule` and `task fail-capsule-webhook`. | |

**User's choice:** Top-level POC tasks under `task` namespace
**Notes:** Locked as **D-11-12**.

---

## SLO regression + ADR-008 rubric (VAL-04 / VAL-06)

### task rebuild SLO measurement

| Option | Description | Selected |
|--------|-------------|----------|
| Bats wraps `time` + `docker inspect` CID compare (Recommended) | Single bats file with ~4 @tests: setup_file records BEFORE_CID; @test 1 measures `time task rebuild` < 230s; @test 2 compares AFTER_CID == BEFORE_CID; @test 3 task health-check exit 0; @test 4 P31 lint inheritance. Matches VAL-04 verbatim. | ✓ |
| Wall-clock script + grep parser | scripts/poc/capsule/measure-rebuild.sh wraps task rebuild; bats invokes script. Extra script for one-off measurement. | |
| Use Phase 5 v0.18 timing (no remeasure) | Inherit 190s figure; no live measurement; ROADMAP wording 'PASSES' implies live measurement; weak ADR-008 evidence. | |

**User's choice:** Bats wraps `time` + `docker inspect` CID compare
**Notes:** Locked as **D-11-13**.

---

### ADR-008 outcome rubric

| Option | Description | Selected |
|--------|-------------|----------|
| Evidence-bound rubric — mechanical mapping (Recommended) | ADR-008 'Decision' section pre-documents the rubric: ADOPT (all bats GREEN + zero open BLOCKERs); DEFER (≥1 RED-by-design or upstream chart workaround); REJECT (≥1 RED for tenant-isolation reason or SLO regression > 230s); REPLACED BY ADR-009 (mid-validation discovery). Outcome mechanical from bats data; auditable; matches Nygard 'Decision' section spirit. | ✓ |
| Subjective — milestone owner reads bats results | Maximum flexibility; zero traceability; matches PITFALLS P41 anti-pattern. | |
| Outcome locked to ADOPT pre-execution | Defeats purpose of validation phase. | |

**User's choice:** Evidence-bound rubric — mechanical mapping
**Notes:** Locked as **D-11-14**. Rubric table goes IN ADR-008 itself.

---

### EKSDOC-01 rollforward

| Option | Description | Selected |
|--------|-------------|----------|
| Targeted revisions, ADR-008 cross-references (Recommended) | Walk through docs/capsule-on-eks.md with bats evidence; revise cert source (Pitfall 10-P1) / IRSA (D-10-01) / proxy LIST scope (N1-N9 evidence) / push-gate translation (D-11-01..04 patterns); set Status: Reviewed; cross-reference ADR-008. | ✓ |
| Frontmatter-only update | Status: Reviewed in frontmatter; body unchanged. Contradicts ROADMAP wording 'with corrections informed by the bats evidence'. | |
| Defer rollforward to v0.20 | ROADMAP wording verbatim demands EKSDOC-01 rollforward AS PART OF VAL-06; deferring breaks the requirement. | |

**User's choice:** Targeted revisions, ADR-008 cross-references
**Notes:** Locked as **D-11-15**.

---

### P31 static lint structure

| Option | Description | Selected |
|--------|-------------|----------|
| Inherit verbatim from Phase 7 (Recommended) | Phase 7 P31 lint at `tests/bats/poc-isolation-01-static.bats` already validated 6/6 across Phases 8/9/10; Phase 11 reuses verbatim as @test d in `slo-regression-live.bats`. Zero duplication. | ✓ |
| Extend with new entries (e.g., Phase 11 destroy-poc) | Adding inverse lint adds noise; Phase 7 lint already excludes `scripts/poc/`. | |
| Add new lint for `task` namespace | Taskfile-level lint over-engineering; POC tasks self-namespace clearly. | |

**User's choice:** Inherit verbatim from Phase 7
**Notes:** Locked as **D-11-16**.

---

## Claude's Discretion

The user did NOT explicitly opt for "Claude decides" on any specific area, but the following were intentionally NOT pinned during discussion (per CONTEXT.md `<decisions>` "Claude's Discretion"):

- **N6 quota fixture** — Tenant CR `spec.namespaceOptions.quota` shape; planner reads existing `pocs/capsule/spoke/tenants/{alpha,bravo}/tenant.yaml` and adds field if absent (recommended `quota: 3`).
- **N7 registry fixture** — Tenant CR `spec.containerRegistries` shape; researcher verifies Capsule v0.12.4 spec field name; recommended `containerRegistries: [{allowed: ["registry.example.io"]}]`.
- **N9 cross-tenant sourceRef fixture** — bats authors probe Kustomization in tmpdir at test time (NOT repo-committed).
- **N10 missing serviceAccountName fixture** — same pattern as N9.
- **Stdout/stderr split** for both new scripts — mirror Phase 10 D-10-09 (stderr-only for preflight-lib helpers).
- **Idempotency** — both scripts safe to re-run; no `-f`/`--force` flag.
- **Plan ordering granularity** — default 5-plan recommendation; planner reshapes 4-7 plans without re-asking.
- **ADR-008 file naming** — `docs/adr/0008-capsule-multi-tenancy-graduation.md`.
- **Verifier script wrapper** — bats-only (no scripts/poc/capsule/verify-validation.sh).
- **Reconcile loop noise tolerance** — ≤2 cycles; bats retry budget 3 attempts × 30s sleep.
- **`docs/poc-capsule.md` H2 'Ordered teardown procedure' append** — Plan 11-02 planner discretion.
- **Push-event timing within VAL-05** — recommended after VAL-01..04 GREEN locally + after persistent-fix plans land + after imperative `helm uninstall` of Plan 10-01 capsule-proxy.

## Deferred Ideas

(See CONTEXT.md `<deferred>` for the canonical list.)

- Phase 9 D-09-03 forward-pointer (tenant inner K kubeConfig swap) — continued deferral inheritance from Phase 10 D-10-05; Phase 12 absorbs if ADR-008 outcome ∈ {adopt, defer}.
- `capsule-addon-fluxcd v0.2.3` Trial → Phase 12 (OPTIONAL — gated).
- Multi-SA-per-tenant pattern → post-v0.19 if needed.
- HA Capsule, OIDC, multi-spoke federation, hub-side Capsule, real ingress/TLS, real secret management → POST-v0.19 milestones.
- `task rebuild` + spoke-capsule lifecycle integration → v0.20 (ONLY if ADR-008 outcome is adopt).
- Capsule NetworkPolicy enforcement (P43) → out of v0.19 scope.
- CI variant of SLO regression test → post-v0.19.
- Capsule policy-as-code / OPA Gatekeeper → post-v0.19.

### Folded Todos (folded into scope)

- `2026-04-29-phase-7-gitleaks-planning-doc-allowlist.md` (resolves_phase: 11) — folded into D-11-04. Will auto-close on Phase 11 close-out.

### Reviewed Todos (not folded)

None — only one of the two pending todos matched Phase 11 (the other resolves_phase: 8 routes elsewhere via its `resolves_phase` marker; that todo will resolve when Phase 11 first push triggers Flux observable reconcile naturally).
