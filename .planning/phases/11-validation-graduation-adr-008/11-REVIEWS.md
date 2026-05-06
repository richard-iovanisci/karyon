---
phase: 11
reviewers: [codex]
codex_model: gpt-5.5
reviewed_at: 2026-05-05T00:00:00Z
plans_reviewed:
  - 11-00-PLAN.md
  - 11-01-PLAN.md
  - 11-02-PLAN.md
  - 11-03-PLAN.md
  - 11-04-PLAN.md
  - 11-05-PLAN.md
---

# Cross-AI Plan Review — Phase 11

## Codex Review

> Codex `gpt-5.5`, reasoning effort: xhigh. Independent adversarial review of the 6 locked Phase 11 plans (11-00..11-05).

I'll review this as a locked plan artifact, not as implementation work. I'm focusing on failure modes that would make a "green" phase misleading rather than just noting missing polish.

### Summary

The phase is well-structured and evidence-oriented, but it has several places where tests can become green without proving the invariant. The biggest risks are destructive live-test ordering, weak hard gates in `11-04`, overly broad gitleaks allowlisting, and falsifiers that can pass for the wrong reason. I would not treat this plan set as graduation-safe until those are tightened.

### Strengths

- Clear wave sequencing: RED scaffold, persistent fixes, live validation, verification, ADR.
- Good coverage intent for VAL-01 through VAL-06, especially avoiding `kubectl auth can-i`.
- Human checkpoints are correctly placed around first push and ADR outcome.
- P31 and ADR-004 isolation are kept front-and-center.
- The ADR rubric is evidence-bound rather than purely narrative.

### Concerns

- **HIGH**: `11-02` teardown may not actually suspend children. `flux suspend kustomization tenant-alpha tenant-bravo poc-capsule-spoke` likely needs one object per invocation; `|| true` hides failure. Also Step 3 must force `--context=k3d-spoke-capsule` everywhere or it can poll the wrong cluster.

- **HIGH**: `teardown-03-live-ordered.bats` and `teardown-04-live-pvc-strand-mitigation.bats` are not independent. If `teardown-03` destroys tenant namespaces first, `teardown-04` cannot create its synthetic PVC unless it rehydrates the POC.

- **HIGH**: `11-04` says the verifier block always exits 0. That makes the RC matrix informational, not gating. This conflicts with VAL-01/VAL-04 success criteria unless failure intentionally routes to `reject` or `defer`.

- **HIGH**: D-11-01 is acknowledged as likely misplaced. A `spec.patches` block on `clusters/hub-flux/pocs/capsule.yaml` may not touch Helm-rendered Role output. The static test can go green while the actual certgen Role is unchanged.

- **HIGH**: D-11-04 broadens `.gitleaks.toml` to `^\.planning/.*\.md$`, which can hide exactly the kind of accidental planning-doc kubeconfig/token leak VAL-05 is supposed to disprove.

- **HIGH**: N9/N10 can fail for the wrong reason. Accepting `not found` for N10 does not prove missing `spec.serviceAccountName` falls through to no-permission default. N9 must use a real, valid cross-tenant `sourceRef`, not an absent source.

- **MEDIUM**: Live skip behavior weakens VAL evidence. Skipping when `spoke-capsule` or its container is missing is fine for local convenience, but Plan `11-03` and `11-04` need a strict mode where skip equals failure.

- **MEDIUM**: Webhook-down tests are timing-sensitive. `sleep 5` after scale-to-zero is weaker than waiting for deployment replicas and service endpoints to reach the expected state.

- **MEDIUM**: N6 quota test is stateful. It assumes `tenant-alpha` plus `alpha-app1` equals exactly 2 namespaces. Leftovers from prior runs can create false failures or false passes.

- **MEDIUM**: PVC finalizer mitigation is under-specified. PVCs may not carry `capsule.clastix.io/tenant` labels, and `jq | xargs | kubectl patch` can be fragile unless namespace/name are passed as structured fields.

- **MEDIUM**: `11-04` imperative `helm uninstall capsule-proxy` can race Flux and leave webhook/certgen state inconsistent. It needs a controlled suspend/delete/reconcile sequence.

- **MEDIUM**: `task destroy-poc capsule` vs `task destroy-poc -- capsule` is inconsistent. With Taskfile `{{.CLI_ARGS}}`, the latter is likely the real command.

- **MEDIUM**: N8 hard-codes `https://127.0.0.1:6446`; also ensure TLS config cannot turn the expected 403 into a TLS failure.

- **LOW**: The prompt mentions Pitfall `11-P5`, but the plan/context defines P1 through P4 only. That escalation path is missing or misnumbered.

### Suggestions

- In `11-02`, loop over Kustomization names individually, verify `spec.suspend=true`, use `--context=k3d-spoke-capsule` for every spoke read/write, and fail on unexpected command errors.

- Collapse the two live teardown tests into one destructive test: create synthetic PVC, run `task destroy-poc -- capsule`, then assert namespace cascade, PVC cleanup, labeled-object absence, and sentinel preservation. Run it last.

- In `11-04`, make required VAL failures hard gates unless the human explicitly selects `reject` or `defer` in `11-05`. Skipped live tests should not count as evidence.

- Move D-11-01 to the actual Helm-render path, likely `clusters/hub-flux/pocs/capsule-spoke.yaml` via HelmRelease post-renderer, or add an empirical pre-check proving the outer Kustomization patch reaches the Role.

- Replace `.planning/.*.md` gitleaks allowlist with file-specific or finding-specific allowlists. Add a separate static scan for kubeconfig markers and token fields without printing secret values.

- Strengthen N9/N10 fixtures so source refs, paths, kubeConfig, and namespaces are valid. The only failing variable should be cross-namespace reference or missing `serviceAccountName`.

- Add a static P27 bats test that all tenant Flux Kustomizations under `clusters/hub-flux/pocs/` set `spec.serviceAccountName`.

- Standardize public commands to `task destroy-poc -- capsule` and update ROADMAP/ADR evidence text accordingly.

### Risk Assessment

**HIGH** until the verifier and destructive-test issues are corrected. The plan's architecture is strong, but several current tests can pass, skip, or fail for unrelated reasons while still producing an ADR-ready artifact. That is the main graduation risk.

---

## Consensus Summary

> Single-reviewer pass (`--codex` only). The "consensus" view below is codex's findings synthesized as the authoritative reviewer call. Re-run with `--gemini` and/or `--claude` for adversarial cross-coverage before treating any item as confirmed.

### Top concerns to address before execution

1. **Verifier hard-gates (HIGH).** Plan 11-04 Task 3's verify block intentionally exits 0 to make RC matrix data-only. If a green disposition can be written despite live RED bats, the ADR-008 rubric loses its load-bearing input. Either tighten Task 3 to gate on critical RED outcomes, or make Task 4's disposition derivation refuse `passed` when the matrix shows live RED.

2. **D-11-01 patch propagation (HIGH).** The Pitfall 11-P1 escalation already calls this out, but the static `push-gate-01` test can turn GREEN without the chart-rendered Role on the spoke ever receiving the secrets/create rule. Add the discriminating `kubectl get role | jq -e ...` check (already present in 11-04 Task 3) as a Plan-11-04 hard gate, OR pre-empt the relocation in 11-01.

3. **Gitleaks allowlist scope (HIGH).** `^\.planning/.*\.md$` is the broadest possible allowlist for that subtree. Tighten to specific path globs (`^\.planning/phases/07-.*/(07-RESEARCH|07-REVIEW)\.md$` for the Phase 7 fixture, etc.) or switch to gitleaks rule-level allowlists.

4. **destroy-poc.sh shell-escape + flux-suspend semantics (HIGH).** The 5-step sequence is correct in spirit, but: (a) `flux suspend kustomization a b c` may not be valid CLI shape (varies by flux version — verify); (b) the `jq | xargs -I{} sh -c '...'` quoting in Step 3 needs explicit verification under bash strict mode + complex namespace/name strings.

5. **N9/N10 falsifier validity (HIGH).** Both bats accept Flux's "not found" or "forbidden" as the failure signal. To prove the *specific* invariant (cross-namespace-ref denied / no-SA fallthrough), the source paths + kubeconfig + sourceRef name need to be valid in all dimensions except the one being tested.

### Top suggestions

- **Static P27 lint** — codex's call for a bats checking that every tenant inner Kustomization under `clusters/hub-flux/pocs/` declares `spec.serviceAccountName` would close a critical invariant that's currently asserted dynamically only.

- **Test independence** — teardown-03 and teardown-04 should be merged or reordered (PVC seed → destroy → asserts) to avoid silent first-failure dependency.

- **Strict-mode gating in CI** — slo-regression-live.bats CI guard is correct. Codex recommends extending the same `KARYON_RUN_*` strict-mode pattern to Plans 11-03/11-04 so "skipped" never becomes evidence.

### Divergent views

N/A — single-reviewer.

### Items the reviewer endorsed

- Wave sequencing + RED-scaffold pattern.
- Anti-`kubectl auth can-i` lint (D-11-05 / D-11-06).
- Human checkpoints around push event + ADR outcome.
- P31 + ADR-004 invariant centrality.
- Evidence-bound D-11-14 rubric structure.

---

## How to incorporate

```bash
# Re-plan affected plans with these reviews as input
/gsd-plan-phase 11 --reviews

# Or address specific items by editing CONTEXT.md decisions and re-running
# /gsd-discuss-phase 11 followed by /gsd-plan-phase 11
```

For broader cross-coverage, re-run with additional reviewers:

```bash
/gsd-review --phase 11 --gemini --claude  # adds 2 more independent perspectives
```
