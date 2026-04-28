---
phase: 5
reviewers: [codex]
reviewed_at: 2026-04-28T14:32:52Z
plans_reviewed: [05-01-PLAN.md, 05-02-PLAN.md, 05-03-PLAN.md, 05-04-PLAN.md, 05-05-PLAN.md, 05-06-PLAN.md]
---

# Cross-AI Plan Review — Phase 5

## Codex Review

**Summary**

The plan set is strong and mostly executable: it decomposes Phase 5 cleanly, preserves the GitOps-only model, adds contract tests before implementation, and avoids the earlier double-rebuild timing trap. The main risks are not scope size, but a few integration gaps that can make `task rebuild` fail even if every script exists: current kube-context after cluster creation, Flux only seeing pushed Git state, the “read-only” DNS probe implementation, and incomplete DESTROY-04 coverage.

**Strengths**

- Good phase slicing: tests, examples, DNS fix, health check, destroy/rebuild, then live verification.
- Strong protection of key decisions: one spoke Flux Kustomization each, GitOps-only workloads, stable GPU Job, one outer destructive prompt.
- The live suite as a state checker is the right fix for avoiding double rebuilds.
- Explicit bounded waits and timing log make the 20-minute SLO measurable.
- Reusing existing script style and Bats gates fits the repo.

**Concerns**

- **HIGH:** `task rebuild` may fail after `create-clusters`. Existing `bootstrap-flux.sh` and `register-spokes-for-flux.sh` require current context `k3d-hub-flux`, but `k3d cluster create` commonly switches current context to the last created cluster. Plan 05-05 does not set or verify context before bootstrap/register.
- **HIGH:** `health-check` is required to be read-only but also needs an in-hub DNS probe. The plan does not prove an existing hub pod has `nslookup`, `getent`, or a shell. Creating/deleting a probe pod would violate the read-only/no-delete contract.
- **HIGH:** Flux reconciles from Git, not local files. `deploy-examples` verifies local manifests but does not fail early if `examples/` or spoke wiring are uncommitted/unpushed. Plan 05-06 has this as a human checkpoint, but `task rebuild` itself can still fail unclearly.
- **MEDIUM:** DESTROY-04 is claimed addressed, but the plans only reject prune commands in wrappers. The requirement says a runnable lint step rejects prune references in `scripts/`; existing `delete-clusters.sh` intentionally contains prune strings in comments, so the verification command as written is too broad and will need comment-aware filtering.
- **MEDIUM:** `fix-coredns` static tests forbid any `spoke-ml` / `spoke-apps` literal, which prevents the script from proving the DNS fix actually resolves the stale spoke hostnames. It should forbid restarting spokes, not forbid checking spoke DNS names.
- **MEDIUM:** Several `kubectl wait --all` checks can pass on empty result sets unless counts are asserted first. Existing scripts already handle this for Flux controllers; Phase 5 should copy that pattern.
- **LOW:** `bats --count` in Plan 05-01 only proves parsing/counting, not that tests fail closed. That is acceptable for Wave 0 bootstrapping, but the plan language overstates what it verifies.
- **LOW:** Some static grep contracts are brittle and can pass from comments or miss equivalent commands with reordered flags.

**Suggestions**

- Add a context step to `scripts/rebuild.sh` before bootstrap/register, e.g. `kubectl config use-context k3d-hub-flux`, or refactor scripts to use explicit `--context` everywhere instead of current-context gating.
- Define the DNS probe concretely before implementing `health-check`: use an existing Flux pod only if it has a shell and resolver tool; otherwise relax “read-only” to allow a clearly named temporary probe pod, or make DNS probing part of `fix-dns` instead.
- Add a Git visibility gate to `deploy-examples.sh` or `rebuild.sh`: fail if relevant paths are dirty or ahead of `origin/main`, with a remediation to commit/push before Flux reconcile.
- Change prune lint to scan executable script lines only, excluding comments and test files, and make that lint satisfy DESTROY-04 explicitly.
- In health and fix scripts, count expected resources before `kubectl wait --all`.
- Strengthen static tests with comment-filtered positive greps or `yq` checks for YAML, especially for critical command ordering and “no direct apply” guarantees.

**Plan Risks**

- **05-01:** **MEDIUM**. Good contract coverage, but several tests are brittle and `--count` does not validate behavior.
- **05-02:** **MEDIUM**. Workload design is sound; biggest gap is no Git pushed-state guard before Flux reconcile.
- **05-03:** **MEDIUM**. Hub-only restart is right, but the test contract is too restrictive to prove the workaround fixed spoke DNS.
- **05-04:** **HIGH** until the read-only DNS probe is resolved. Otherwise the ordered gates are well chosen.
- **05-05:** **HIGH** because of the kube-context issue in the strict rebuild chain and incomplete DESTROY-04 linting.
- **05-06:** **LOW-MEDIUM** after the above fixes. The one-run live proof is well designed, but depends on pushed Git state and context handling being made deterministic.

---

## Consensus Summary

Only one external reviewer (Codex) was invoked, so this section reflects that single review. Treat the items as a single perspective rather than a multi-reviewer consensus; for cross-AI corroboration, rerun with additional CLIs (e.g. `--claude` from a separate session, or another flag).

### Agreed Strengths

Single-reviewer signal:

- Clean phase slicing (tests → examples → DNS fix → health → destroy/rebuild → live verification).
- GitOps-only model preserved and one Flux Kustomization per spoke retained.
- Live suite reframed as a state checker fixes the prior double-rebuild trap.
- Bounded waits + structured `/tmp/karyon-rebuild.log` make the 20-min SLO automation-checkable.

### Agreed Concerns (HIGH)

Single-reviewer signal — but flagged as HIGH and worth treating as planning blockers:

1. **Kube-context after `k3d cluster create`** — `bootstrap-flux.sh` and `register-spokes-for-flux.sh` rely on current context `k3d-hub-flux`, but `k3d cluster create` switches current context to the last created cluster. Plan 05-05's strict chain does not set or verify the context before `bootstrap-flux` / `register-spokes`. Mitigation: either prepend `kubectl config use-context k3d-hub-flux` in `rebuild.sh` between `create-clusters` and `bootstrap-flux`, or make every script context-explicit.
2. **`health-check` DNS probe vs. read-only contract** — Plan 05-04 requires both an in-hub-pod DNS probe AND a strict read-only script (no `kubectl apply` / `kubectl delete`). Without proof that an existing Flux pod ships `nslookup` / `getent` / a shell, the probe cannot be implemented without violating one of the two contracts. Mitigation: pin the probe target (which pod + which command) before implementation, or move DNS probing into `fix-dns`, or relax the read-only contract for an explicitly-named ephemeral probe.
3. **Flux reconciles from Git, not the working tree** — `deploy-examples` and `rebuild` will fail unclearly if `examples/` or spoke wiring is dirty/unpushed. Plan 05-06 gates this with a human checkpoint, but the chain itself has no early-fail. Mitigation: add a Git visibility gate (`git status --short` clean and `HEAD == origin/main`) at the top of `deploy-examples.sh` or `rebuild.sh` with an actionable remediation message.

### Agreed Concerns (MEDIUM)

- **DESTROY-04 lint scope** — current verification grep is too broad; `delete-clusters.sh` intentionally has prune strings in comments. Need comment-and-test-aware filtering for the lint to satisfy the requirement.
- **`fix-coredns-01-static.bats` over-restricts** — forbidding any `spoke-ml`/`spoke-apps` literal prevents the script from proving the workaround actually fixed spoke DNS. Should forbid restarting spokes, not naming them.
- **`kubectl wait --all` on empty sets** — can pass spuriously when zero matching resources exist; assert counts first (existing pattern in `bootstrap-flux.sh` Flux-controller wait).

### Agreed Concerns (LOW)

- `bats --count` proves parsing only, not behavior — acceptable for Wave 0 but plan language overstates verification depth.
- Some static grep contracts pass on comments / miss equivalent commands with reordered flags. Filter comments and prefer `yq` for YAML assertions.

### Divergent Views

N/A — only one reviewer.
