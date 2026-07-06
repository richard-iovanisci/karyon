---
slug: post-v020-defect-sweep
date: 2026-07-06
type: quick
status: complete
---

# Summary: Post-v0.20 defect sweep

All four defects fixed, live-verified, and pushed to main (commits `84a046d..6cd0575` + follow-up).
CI is fully green for the first time in the repo's recorded history (all 5 jobs — the
markdownlint job had been red-on-every-push since at least v0.19).

## What landed (by commit)

1. `84a046d` — capsule-install-03 namespaces-hook assertion inverted to `Fail` (c89f1b2 guard).
2. `ffbf0aa` — 5 stale static suites reconciled (capsule-install-05, poc-mount-01 ×2,
   tenants-04 ×2, proxy-03) + `.gitleaks.toml` archived-path allowlist entries (push-gate-05
   live scan green again; full-history scan clean, 601 commits).
3. `53446d3` — CI `prune-lint-bats` job now runs ALL 46 static suites (verified green on the
   GitHub runner).
4. `039c31a` — register-spokes heredoc emits `serviceAccountName: flux-reconciler`
   (byte-identical to committed manifests → rerun is a no-op) + 3 bats guards.
5. `af51007` — tenant GitRepositories reference `karyon-git-auth`; register-poc-cluster.sh
   mirrors the bootstrap git credential into tenant-alpha/bravo (private-repo fix).
6. `c8fdd97` — GTR seeds a 1-replica Deployment (ADR-008 addendum 2026-07-06 supersedes
   D-13-12 / amends SEED-03); seed-01..04 + demo-03 bats, demo runbook, portable guide updated.
7. `6cd0575` — planning records (PROJECT.md drift note + parking lot, STATE.md quick-task table).
8. Follow-up commit — seed-02/04 `require_ns` skip for absent alpha-app1/bravo-app1 fixture
   namespaces (the old suites failed spuriously standalone); markdownlint MD024
   `siblings_only` config + one fence spacing fix → repo-wide lint 0 errors, CI 5/5 green.

## Live verification evidence (2026-07-06, k3d clusters)

- **Tenant GitOps path restored:** `karyon-git-auth` mirrored live; `tenant-alpha-source` +
  `tenant-bravo-source` Ready=True at `main@6cd0575`; `tenant-alpha-app` / `tenant-bravo-app`
  Kustomizations `Applied revision` — first successful reconcile in ~40 days.
- **GTR transition clean:** Deployments 1/1 Available in tenant-alpha + tenant-bravo within
  ~30s of reconcile; old bare Pods pruned by Capsule; `status.processedItems` tracks
  Deployment+Service per tenant.
- **Bats:** all 46 static suites green (local + GitHub runner); seed-02 (12/12), seed-04
  (10/10 incl. fixture skips), demo-03 (6/6 — exec/logs via `deploy/hello-world` under both
  Tier-3 tenant kubeconfigs and the Tier-2 platform-owner kubeconfig), seed-03 fresh-tenant
  ≤60s SLO GREEN (tenant `phase13-fresh` provisioned + auto-seeded + torn down).
- **Controller logs:** the permanent `unable to replicate` backoff loop is GONE in
  steady state. Residual: transient `object has been modified` optimistic-concurrency
  conflicts during tenant create/delete churn (auto-retried by controller-runtime, resolve
  on the next reconcile attempt — the normal conflict-retry pattern, not a loop).

## Residual / follow-ups (parked in PROJECT.md)

- Public-vs-private repo decision (fix works under both postures).
- Least-privilege git credential (read-only PAT / deploy key) to replace the mirrored
  bootstrap PAT.
- Audit the remaining ~13 `failurePolicy: Ignore` webhook hooks for analogous cold-bootstrap
  failure modes.
- The pre-existing markdownlint parking-lot item can be marked resolved at the next
  parking-lot review (repo-wide lint is now 0 and gated by the green CI job).
