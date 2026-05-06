---
phase: 11
reviewers: [codex]
reviews:
  - reviewer: codex
    reviewed_at: 2026-05-05T00:00:00Z
    plans: [11-00-PLAN.md, 11-01-PLAN.md, 11-02-PLAN.md, 11-03-PLAN.md, 11-04-PLAN.md, 11-05-PLAN.md]
    scope: locked-plans-pre-execute
  - reviewer: codex
    reviewed_at: 2026-05-06T19:26:25Z
    plans: [11-06-PLAN.md, 11-07-PLAN.md]
    scope: gap-closure-pre-execute
plans_reviewed:
  - 11-00-PLAN.md
  - 11-01-PLAN.md
  - 11-02-PLAN.md
  - 11-03-PLAN.md
  - 11-04-PLAN.md
  - 11-05-PLAN.md
  - 11-06-PLAN.md
  - 11-07-PLAN.md
---

# Cross-AI Plan Review — Phase 11

Two codex review cycles, capturing the original Phase 11 plan set (2026-05-05) and the follow-up gap-closure plans 11-06 and 11-07 (2026-05-06).

---

## Codex Review §1 — 2026-05-05 (Plans 11-00..11-05)

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

## Codex Review §2 — 2026-05-06 (Plans 11-06 + 11-07 — Gap Closure)

> Codex independent adversarial review of the two follow-up gap-closure plans created after Phase 11 execution surfaced empirical blockers G-04 (Plan 11-06) and G-06 (Plan 11-07). Treats the plans as locked artifacts; focus on failure modes where static gates pass while the live Flux path still fails.

### Summary

The plans are directionally strong, especially the 11-06 relocation to HelmRelease `spec.postRenderers`, but Plan 11-07 has a serious bootstrap ordering gap: it tries to create the target impersonation ServiceAccount through a spoke Kustomization that may not itself have the right target-cluster impersonation identity, and it does not create the `capsule-system` namespace on the spoke before creating the SA. That can let the static gates go green while the live Flux path still fails.

### Strengths

- 11-06 correctly moves the Role patch from Kustomization `spec.patches` to HelmRelease `spec.postRenderers`; Flux docs confirm Helm post-renderers are the intended Helm-rendered-manifest patch surface.
- 11-06 keeps ADR-004 intact: the hub Kustomization remains hub-targeted with no `spec.kubeConfig`.
- The live hard gate for the rendered Role is the right discriminator: `kubectl get role ... | jq ... secrets/create`.
- 11-07 correctly identifies Flux remote-cluster impersonation semantics: with `spec.kubeConfig` + `spec.serviceAccountName`, the named SA must exist in the target cluster namespace matching the HelmRelease namespace.
- The gitleaks extension is file-specific and preserves the anti-broad-regex sentinel.
- `KARYON_REBUILD_APPROVED=yes` in `setup_file()` is scoped correctly for Bats; exported `setup_file` vars are visible to tests in that file, not a user shell.

### Concerns

- **HIGH: Plan 11-07 omits the target `capsule-system` Namespace on spoke.** `pocs/capsule/spoke/rbac/helm-controller-sa.yaml` creates a ServiceAccount in `capsule-system`, but no spoke-side Namespace. 11-06 creates `capsule-system` on hub only. On a clean spoke, the rbac Kustomization can fail with namespace-not-found before the SA exists, while the HelmRelease needs that same SA to create/install into the target namespace. Add a spoke-side Namespace resource to the rbac bootstrap path.

- **HIGH: Plan 11-07 relies on `poc-capsule-spoke` to create the new SA, but `clusters/hub-flux/pocs/capsule-spoke.yaml` currently uses `spec.serviceAccountName: kustomize-controller`.** For a remote Kustomization, that impersonates a target-cluster SA named `flux-system/kustomize-controller`. The registration script creates `flux-system/flux-reconciler`, not `kustomize-controller`. This repeats the Phase 9 "wrong target SA name" failure mode and can prevent the rbac path from applying at all. Either change `poc-capsule-spoke` to `serviceAccountName: flux-reconciler` or bootstrap a real target `kustomize-controller` SA+CRB before relying on it.

- **MEDIUM: "`rbac/` first" is not enough to order it before HelmRelease reconciliation.** That ordering is only inside `pocs/capsule/spoke/kustomization.yaml`. The HelmReleases are created by the separate hub-side `poc-capsule` Kustomization and can be picked up by helm-controller before `poc-capsule-spoke` has applied rbac. Flux retries may recover, but the plan's "before first reconcile attempt" claim is too strong.

- **MEDIUM: the G-06 root-cause proof is incomplete.** `context deadline exceeded` is consistent with impersonation/RBAC, but also with target namespace/storage namespace missing, API connectivity, hook Job timeout, CRD readiness, or chart hook failure. The plan should capture helm-controller logs/events around the timeout before declaring the root cause closed.

- **MEDIUM: `cluster-admin` rationale overstates containment.** "Only installs the Capsule charts" is policy by convention, not enforcement. A compromised chart or future HR using `serviceAccountName: helm-controller` gets cluster-admin on the spoke. This may be acceptable for the isolated POC, but the threat model should say that plainly.

- **MEDIUM: Plan 11-06's push-gate-01 rewrite has an internal contradiction.** The requested header mentions `clusters/hub-flux/pocs/capsule.yaml`, but the verify step asserts the file must not contain that string. That incentivizes awkward comment mangling while not improving behavior.

- **MEDIUM: gitleaks verification does not run the actual PROXY-03 falsifier.** Adding the allowlist should be followed by `bats tests/bats/proxy-06-live-fixture.bats`, proving the temp fixture still triggers gitleaks while only the source file is allowlisted.

- **LOW: markdownlint frontmatter preservation is under-verified.** Grepping for `Status: Reviewed` / `status: Active` does not prove frontmatter was unchanged. `--fix` is usually safe, but this plan needs a stricter diff check for frontmatter and code-fence contents.

- **LOW: Task 4's "bats parses" check always passes.** `bats ... || true && echo PASS` masks syntax failures. Use `bats --count tests/bats/slo-regression-live.bats` or run the file in a controlled skip mode without `|| true`.

### Suggestions

- Add `pocs/capsule/spoke/rbac/namespace.yaml` with `kind: Namespace`, `metadata.name: capsule-system`, and list it before `helm-controller-sa.yaml`.

- Bootstrap the spoke rbac as a separate Flux Kustomization, e.g. `poc-capsule-spoke-rbac`, with `spec.kubeConfig` and `spec.serviceAccountName: flux-reconciler`, no dependency on `poc-capsule`. Then make `poc-capsule` depend on that bootstrap K if you need deterministic pre-HR ordering.

- Fix or explicitly validate `clusters/hub-flux/pocs/capsule-spoke.yaml` target SA. Given existing spoke patterns, `serviceAccountName: flux-reconciler` is the likely correct value.

- Add a pre/post live diagnostic for G-06: `flux logs --kind=HelmRelease --name=capsule -n capsule-system`, `kubectl auth can-i --as=system:serviceaccount:capsule-system:helm-controller '*' '*'`, and events from both hub HRs.

- Add static checks for the new bootstrap path:
  - `yq '.resources[0]' pocs/capsule/spoke/rbac/kustomization.yaml == namespace.yaml`
  - `yq '.spec.serviceAccountName' clusters/hub-flux/pocs/capsule-spoke.yaml == flux-reconciler`
  - live `kubectl get ns capsule-system --context=k3d-spoke-capsule`

- Run `bats tests/bats/proxy-06-live-fixture.bats` after the gitleaks allowlist change.

- Replace the push-gate-01 "must not mention old file path" assertion with "must not query old file path in executable test logic," or remove it.

### Risk Assessment

**Overall risk: HIGH until the 11-07 bootstrap path is corrected.** 11-06 is mostly sound and has the right live discriminator. 11-07 can still go static-green while failing live because the target namespace and the applying Kustomization's own target ServiceAccount are not proven valid. After adding a spoke-side namespace, fixing `poc-capsule-spoke` impersonation, and making rbac bootstrap ordering explicit, the residual risk drops to MEDIUM, mostly around broad `cluster-admin` acceptance and live Helm chart behavior.

---

## Consensus Summary

> Single-reviewer pass across both cycles (`--codex` only). The "consensus" view below is codex's findings synthesized as the authoritative reviewer call. Re-run with `--gemini` and/or `--claude` for adversarial cross-coverage before treating any item as confirmed.

### Top concerns to address before execution

#### From the gap-closure cycle (2026-05-06; Plans 11-06 + 11-07)

1. **Spoke-side `capsule-system` Namespace missing (HIGH).** Plan 11-07 provisions a SA in `capsule-system` on spoke but doesn't ensure that namespace exists on spoke first. Symmetrical to Plan 11-06's hub-side fix — needs `pocs/capsule/spoke/rbac/namespace.yaml` ordered first.

2. **`poc-capsule-spoke` outer K target SA mismatch (HIGH).** `clusters/hub-flux/pocs/capsule-spoke.yaml` uses `spec.serviceAccountName: kustomize-controller`, but the spoke registration script provisions `flux-reconciler`. If true, the entire spoke rbac path may never apply. **Action: verify against the codebase before executing 11-07** — change to `flux-reconciler` if confirmed, or document why `kustomize-controller` is the correct target.

3. **Bootstrap ordering is not provable (MEDIUM).** "rbac/ first in pocs/capsule/spoke/kustomization.yaml" only orders within that K's apply. The HRs come from a different hub K and helm-controller can pick them up before spoke rbac applies. Either accept Flux-retry behavior empirically, or split rbac into its own outer K with no `dependsOn` on `poc-capsule`.

4. **G-06 root-cause not fully proven (MEDIUM).** "context deadline exceeded" has multiple plausible causes; the plan should capture helm-controller logs + `kubectl auth can-i` output for the impersonated SA before declaring impersonation as the root cause.

#### From the original cycle (2026-05-05; Plans 11-00..11-05)

5. **Verifier hard-gates (HIGH).** Plan 11-04 Task 3's verify block intentionally exits 0 to make RC matrix data-only. If a green disposition can be written despite live RED bats, the ADR-008 rubric loses its load-bearing input. Either tighten Task 3 to gate on critical RED outcomes, or make Task 4's disposition derivation refuse `passed` when the matrix shows live RED.

6. **D-11-01 patch propagation (HIGH) — RESOLVED in 11-06.** The original concern (static `push-gate-01` GREEN without chart-rendered Role propagation) is directly addressed by Plan 11-06's relocation to HelmRelease `spec.postRenderers`. Codex §2 confirms the relocation is correct.

7. **Gitleaks allowlist scope (HIGH) — RESOLVED in D-11-04-revised + 11-07.** Original broad `^\.planning/.*\.md$` was tightened to file-specific entries. Plan 11-07 extends the same file-specific pattern with one entry for `proxy-06-live-fixture.bats`; codex §2 confirms the anti-broad-regex sentinel is preserved.

8. **destroy-poc.sh shell-escape + flux-suspend semantics (HIGH).** The 5-step sequence is correct in spirit, but: (a) `flux suspend kustomization a b c` may not be valid CLI shape (varies by flux version — verify); (b) the `jq | xargs -I{} sh -c '...'` quoting in Step 3 needs explicit verification under bash strict mode + complex namespace/name strings.

9. **N9/N10 falsifier validity (HIGH).** Both bats accept Flux's "not found" or "forbidden" as the failure signal. To prove the *specific* invariant (cross-namespace-ref denied / no-SA fallthrough), the source paths + kubeconfig + sourceRef name need to be valid in all dimensions except the one being tested.

### Top suggestions

- **Spoke-side Namespace + rbac bootstrap split** — codex §2's call for `pocs/capsule/spoke/rbac/namespace.yaml` + a separate `poc-capsule-spoke-rbac` outer Kustomization would close the bootstrap-ordering ambiguity in 11-07 deterministically.

- **Verify `poc-capsule-spoke` target SA** before executing 11-07. This is a single grep against the codebase: `grep -A5 'name: poc-capsule-spoke' clusters/hub-flux/pocs/capsule-spoke.yaml` for `serviceAccountName`. If `kustomize-controller`, then either (a) the spoke registration also provisions that SA — find the manifest — or (b) the field needs to change to `flux-reconciler`.

- **Static P27 lint** — codex §1's call for a bats checking that every tenant inner Kustomization under `clusters/hub-flux/pocs/` declares `spec.serviceAccountName` would close a critical invariant that's currently asserted dynamically only.

- **Test independence** — teardown-03 and teardown-04 should be merged or reordered (PVC seed → destroy → asserts) to avoid silent first-failure dependency.

- **Strict-mode gating in CI** — slo-regression-live.bats CI guard is correct. Codex recommends extending the same `KARYON_RUN_*` strict-mode pattern to Plans 11-03/11-04 so "skipped" never becomes evidence.

- **Live G-06 diagnostics in Task 5** — capture `flux logs --kind=HelmRelease ... -n capsule-system` and `kubectl auth can-i --as=system:serviceaccount:capsule-system:helm-controller '*' '*'` *before* declaring G-06 closed, so the empirical evidence is bound to the impersonation hypothesis rather than just "reconcile succeeded."

### Divergent views

N/A — single-reviewer across both cycles.

### Items the reviewer endorsed (across both cycles)

- Wave sequencing + RED-scaffold pattern (§1).
- Anti-`kubectl auth can-i` lint (D-11-05 / D-11-06) (§1).
- Human checkpoints around push event + ADR outcome (§1).
- P31 + ADR-004 invariant centrality — preserved in 11-06's hub-only Namespace (§1+§2).
- Evidence-bound D-11-14 rubric structure (§1).
- 11-06 `spec.postRenderers` relocation as the correct Flux Helm-rendered patch surface (§2).
- 11-07 file-specific gitleaks allowlist extension (§2).
- 11-07 `KARYON_REBUILD_APPROVED=yes` scoping in `setup_file()` (§2).

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
