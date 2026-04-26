---
phase: 3
reviewers: [codex]
reviewed_at: 2026-04-26T18:12:28Z
plans_reviewed: [03-01-PLAN.md, 03-02-PLAN.md, 03-03-PLAN.md, 03-04-PLAN.md]
codex_cli_version: 0.125.0
---

# Cross-AI Plan Review — Phase 3

## Codex Review

**Summary**
The phase design is mostly sound: it keeps Flux bootstrap as the source of truth, wraps it with the right safety gates, and covers FLUX-01..05 with script, docs, tests, and Taskfile exposure. I would not execute these plans unchanged yet. The main risks are plan-internal contradictions in 03-01, a possible preflight-vs-existing-cluster blocker, and ambiguity around whether the D-13 `kustomization.yaml` marker ever reaches the GitHub repo that Flux reconciles from. Line numbers were not available in the prompt, so references below use plan/task/section IDs.

**Strengths**
- Clear scope control: 03-02 implements only the hub bootstrap path; Phase 4/5/6 responsibilities are not pulled forward.
- Good security posture around PAT handling: env-based `GITHUB_TOKEN`, no argv token, no `set -x`, no bootstrap `tee`.
- Strong context safety: 03-02 explicitly fails on non-`k3d-hub-flux` context and avoids auto-switching.
- Good post-bootstrap verification shape: `flux check`, deployment count guard before `kubectl wait --all`, and Kustomization Ready via JSONPath avoids the `grep Ready` trap.
- FLUX-02 is protected well: `clusters/hub-flux` is a readonly constant and env override is rejected by tests.
- 03-03 correctly documents the important operator contract: `gotk-*` files are bootstrap-managed, `kustomization.yaml` is the patch surface, and `--path` is effectively immutable.
- The corrected D-03 NetworkPolicy rationale is acknowledged in 03-02's threat model and does not rely on the false "flannel does not enforce NetworkPolicy" claim.

**Concerns**
- **HIGH — 03-01 test-count contradiction.** 03-01 Task 1 says "6 @tests total: 4 static + 2 live," but the supplied file content has 8 tests: 6 static + 2 live. Acceptance criteria also say "Exactly 6," while verification expects "6 static + 2 live." This will cause executor confusion or false failure.
- **HIGH — preflight may block the only valid Phase 3 state.** 03-02 requires Phase 2's `hub-flux` cluster to already exist, but delegates first to `scripts/preflight.sh`. If preflight enforces ports 6443-6445 as free or treats existing k3d state as a blocker, bootstrap cannot run after cluster creation. The plan assumes this is green but does not prove it.
- **HIGH — D-13 marker is local-only unless explicitly committed/pushed.** 03-02 Section 5 prepends the comment after `flux bootstrap` has already committed/pushed the bootstrap files. The plan does not state how that local change reaches GitHub, so Flux may reconcile from a remote tree without the marker while the local worktree is dirty.
- **MEDIUM — live Bats tests are not independent.** 03-01's D-13 live test relies on the prior live test having run the double-bootstrap. Bats tests should be independently runnable or combined.
- **MEDIUM — first live bootstrap failure is hidden.** 03-01 uses `bash "$SCRIPT" >/dev/null 2>&1 || true` before asserting the second run. That masks the most useful failure signal.
- **MEDIUM — verification commands with `| head` can mask failures.** Several automated verifies pipe `bats` output to `head` without `set -o pipefail`, so a failed or parse-erroring `bats` run can still return success.
- **MEDIUM — Phase 6 gitleaks advisory was researched but omitted.** 03-02's threat model says the script does not implement the warn-only hook check. That is a defensible choice, but it deviates from the recommended mitigation for the public-repo/PAT timing risk.
- **LOW — D-03 corrected rationale is not preserved in committed artifacts.** It exists in the plan threat model, but future maintainers reading `--network-policy=false` in the script will not see the corrected rationale unless a nearby comment or doc sentence is added.
- **LOW — static security greps are narrow.** The tests reject `echo "$GITHUB_TOKEN"` and `tee`, but would not catch `printf '%s' "$GITHUB_TOKEN"` or logging through `pass/info`.

**Suggestions**
- **03-01 Task 1:** Fix the test count everywhere to "8 total: 6 static + 2 live," or remove two static tests. Prefer keeping 8 and updating acceptance, success criteria, and verification text.
- **03-01 live tests:** Make the first run required to pass, then run again:
  `run bash "$SCRIPT"; [ "$status" -eq 0 ]`, followed by the second run skip assertion. Either combine the D-13 marker assertion into that test or rerun setup inside the D-13 test.
- **03-02 Section 1:** Before execution, explicitly verify `scripts/preflight.sh` exits 0 when `hub-flux` exists. If not, add a bootstrap-specific preflight mode or make preflight distinguish expected k3d-owned ports from conflicting ports.
- **03-02 Section 5:** Add an explicit plan step for how the marker reaches GitHub. At minimum, record that the script intentionally leaves a source-controlled local diff and the phase executor must commit/push it before claiming the hub reconciles the final tree.
- **03-02 verification:** Add a phase-gate check after push: `flux --context k3d-hub-flux reconcile kustomization flux-system --with-source` and then assert Ready=True.
- **03-02 Section 3:** If Flux supports the global flag on `bootstrap github`, pass `--context "${KUBE_CTX}"` too. The current context gate is good, but explicit context keeps the command self-contained.
- **03-02/03-03:** Add a short corrected comment near `--network-policy=false`: disabled because this is a single-user lab with no adversarial namespace boundary, not because k3s cannot enforce NetworkPolicy.
- **All verify blocks:** Replace `... | head` with `set -o pipefail; ... | head`, or avoid truncation in the actual gate.
- **03-04 verify:** Compare task key count explicitly, not just `grep -c` output. For example: `test "$(yq eval '.tasks | keys | length' Taskfile.yml)" -eq 4`.

**Risk Assessment**
**MEDIUM.** The architecture is low-risk and aligned with the phase goal, but the plans are not execution-ready because of concrete contract mismatches and one potentially blocking lifecycle issue around preflight after cluster creation. Fixing the 03-01 contradictions, proving preflight compatibility, and making the D-13 local-to-remote story explicit would drop this to LOW.

---

## Consensus Summary

> Single-reviewer review (codex only). The "consensus" below is the codex findings themselves, organized for action by `/gsd-plan-phase 3 --reviews`.

### Agreed Strengths

- Architecture aligns cleanly with the phase goal and respects scope boundaries (Phase 4/5/6 work not pulled forward).
- PAT handling is sound (env-var passing, no argv, no `set -x`, no `tee`).
- Context-gate-with-remediation (D-06) is correct over auto-switch.
- Post-bootstrap verification gates (`flux check` → deploy-count-guarded `kubectl wait` → JSONPath Kustomization Ready) avoid the common "grep Ready" failure mode.
- FLUX-02 (`--path clusters/hub-flux` immutable) is enforced both by readonly constant in 03-02 and by negative-grep tests in 03-01.
- 03-03 correctly states the operator contract (gotk-* bootstrap-managed; kustomization.yaml is patch surface; `--path` immutable).
- T-3-05 (corrected D-03 NetworkPolicy rationale) is present and accurate.

### Agreed Concerns (highest priority — HIGH severity items)

1. **HIGH — 03-01 internal test-count inconsistency.** Task 1 says "6 @tests (4 static + 2 live)" but supplied content has 8 tests (6 static + 2 live). Acceptance criteria and verification text disagree with each other. **Action: pick one number and align all references.**
2. **HIGH — preflight compatibility with already-provisioned hub-flux not proven.** 03-02 delegates to `scripts/preflight.sh` as Section 1, but Phase 3 is meant to run *after* Phase 2 has created the cluster. If preflight rejects the post-Phase-2 state (e.g., because k3d-hub-flux has bound port 6443), bootstrap-flux.sh cannot proceed. **Action: confirm preflight passes after `bash scripts/create-clusters.sh` ran, or add a bootstrap-specific preflight mode.**
3. **HIGH — D-13 marker reach-to-GitHub story is missing.** Section 5 prepends `# FLUX PATCH SURFACE` to `clusters/hub-flux/flux-system/kustomization.yaml` *after* `flux bootstrap github` has already pushed the file to GitHub. The plan does not specify how the local edit gets committed/pushed so that Flux reconciles a tree containing the marker. **Action: either (a) add an explicit commit+push step in Section 5 (or a phase-gate task), or (b) document that the marker is intentionally local-only and the operator must commit/push it manually before Phase 3 is "done".**

### Medium-Severity Concerns Worth Addressing

4. **Live bats tests are not independent.** D-13 marker live @test depends on the previous live @test having already run bootstrap. Either combine them or make D-13's @test self-sufficient (run bootstrap inside its own setup).
5. **First-run failure is masked.** 03-01 uses `bash "$SCRIPT" >/dev/null 2>&1 || true` before the second-run assertion — useful failure signal is swallowed. Switch to `run bash "$SCRIPT"; [ "$status" -eq 0 ]` for the first run.
6. **`| head` without `pipefail` in verify blocks** can hide bats failures. Either prefix `set -o pipefail` or drop the truncation.
7. **Gitleaks advisory hook (Phase 6 hand-off) is documented but not implemented.** Defensible (Phase 3 must not block on Phase 6), but the recommended mitigation surfaced in research is missing in the script. Consider adding the one-liner warn-only check.
8. **Phase 6 gitleaks pre-commit advisory** is informational, but per RESEARCH.md, it was a recommended belt-and-suspenders item for public-repo PAT-timing risk.

### Low-Severity / Polish

- Add an inline comment next to `--network-policy=false` (in `scripts/bootstrap-flux.sh` and/or `docs/flux-hub-spoke.md`) restating the corrected D-03 rationale ("no adversarial namespace boundary in this single-user lab; not because k3s cannot enforce NetworkPolicies"). The threat-model entry is for plan readers, not script readers.
- Static security greps in 03-01 reject `echo "$GITHUB_TOKEN"` and `tee` but would miss `printf '%s' "$GITHUB_TOKEN"` or `pass/info` carrying the token. Broaden the negative-grep set.
- 03-04's Taskfile assertion uses `grep -c` — codex suggests `yq eval '.tasks | keys | length'` for a structurally-correct count.
- Pass `--context "${KUBE_CTX}"` to `flux bootstrap github` itself if supported, so the command is self-contained even if some future caller mutates current-context between the gate and the bootstrap call.

### Divergent Views

N/A — single reviewer.

### Recommended Next Step

The 3 HIGH-severity findings (test-count contradiction, preflight compatibility, D-13 reach-to-GitHub) are real and should be addressed before execution. Run:

```
/gsd-plan-phase 3 --reviews
```

to feed this REVIEWS.md back into the planner for a targeted revision pass.

For the medium/low items, judgment call — most can be folded into the same revision pass cheaply.
