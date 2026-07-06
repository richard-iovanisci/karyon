---
slug: post-v020-defect-sweep
date: 2026-07-06
type: quick
status: complete
---

# Quick Task: Post-v0.20 defect sweep (4 unrecorded defects + stale-guard reconciliation)

## Origin

A deep-dive audit (agent workflow, 2026-07-06) built a mental map of the hub-and-spoke +
Capsule architecture and cross-checked the committed record against the live clusters.
Four defects were confirmed that appear NOWHERE in the repo's own record (no ADR, no
debug doc, no parking-lot entry, no bats):

1. **Inverted regression guard** — `tests/bats/capsule-install-03-static-values.bats:36`
   still asserted `webhooks.hooks.namespaces.failurePolicy == "Ignore"`, contradicting
   the c89f1b2 cold-bootstrap deadlock fix (`Fail`). Suite RED but never executed by any
   gate (CI ran exactly one unrelated bats file; no `task test`, no pre-commit, no hooks).
2. **`task register-spokes` rerun hazard** — `ensure_hub_kustomization()` heredoc omits
   `serviceAccountName: flux-reconciler`; `repair_file_if_needed` overwrites on any diff,
   so a rerun strips the line commit 621e530 added. With `--default-service-account=default`
   live, spoke reconciliation fails closed (attempt-1 rollback 9b6b3a5 reproduced this).
3. **Dead tenant GitOps path** — repo went PRIVATE (unrecorded, between Phase 9 and Plan
   11-07) while `pocs/capsule/tenants/{alpha,bravo}.yaml` GitRepositories assume anonymous
   clone; tenant-{alpha,bravo}-source Ready=False ("authentication required") for ~40 days.
4. **GTR raw-Pod error loop** — `hello-world-seeded` bare-Pod rawItem hits Pod-spec
   immutability on every resync; capsule-controller-manager in permanent exponential
   backoff, masking real replication failures (shipped blind — nothing read controller logs).

During remediation of (1), five MORE stale static suites surfaced (all RED, all never
run): capsule-install-05, poc-mount-01 (x2), proxy-03, push-gate-05 (gitleaks allowlist
paths broken by milestone archival), tenants-04 (x2).

## Tasks

1. Invert capsule-install-03 namespaces-hook assertion to `Fail`; cite the debug doc.
2. Reconcile the five stale static suites with committed (intentional) reality; fix the
   `.gitleaks.toml` allowlist for the archived v0.19 paths (keep old entries for history
   scans; file-specific per reviewer HIGH #3 — no broad regex).
3. Wire ALL static bats suites into the CI `prune-lint-bats` job (name preserved for
   branch protection).
4. Add `serviceAccountName: flux-reconciler` to the register-spokes heredoc (byte-match
   with committed files verified) + 3 new bats guards (manifests x2 + template).
5. Add `secretRef: karyon-git-auth` to both tenant GitRepositories + a
   `mirror_git_auth_to_tenant_namespaces()` mirror in register-poc-cluster.sh (pattern:
   existing kubeconfig mirrors); run the mirror live and verify sources turn Ready.
   Decision: keep repo private, fix via credential (reversible; also works if repo goes
   public later). Read-only-credential upgrade → parking lot.
6. Amend the GTR seed to a 1-replica Deployment (ADR-008 addendum supersedes D-13-12 /
   amends SEED-03); update seed-01..04 + demo-03 bats, demo runbook Act 4/5/6 + Known
   noise appendix, portable guide §3g + new immutable-shape gotcha; verify live that the
   controller error loop stops.
7. Update PROJECT.md (visibility drift note + parking lot), STATE.md (quick-task table),
   ADR-008 (2026-07-06 addendum covering findings 1 + 4).
