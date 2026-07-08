# Backlog

Open work items and standing engineering decisions for karyon. This is the repo's
tracker of record: anything queued, deferred, or load-bearing lives here.

## Open items

- **Audit the remaining Capsule webhook `failurePolicy: Ignore` overrides.**
  `pocs/capsule/operator/helmrelease.yaml` flips roughly 13 Capsule webhooks from the
  chart default `Fail` to `Ignore` (originally to survive install-order races). Two
  live incidents have shown that an `Ignore` webhook silently drops its mutation
  whenever the Capsule controller is briefly down. First (2026-05-27): the
  `namespaces` mutating hook missed stamping the ownerReference during a cold
  bootstrap, leaving tenant namespaces labeled but unowned — tenant size 0, no
  RoleBindings, and the validating webhook then blocked all recovery. That one hook
  is now back at `Fail`, guarded by `tests/bats/capsule-install-03-static-values.bats`.
  Second (2026-07-07): pods recreated during a node restart missed the
  `capsule.clastix.io/managed-by` label via the `assignment.misc` hook, so
  platform-owner cluster-wide pod lists through capsule-proxy returned empty until
  the pods were recreated with the controller up. Each remaining `Ignore` hook needs
  the same analysis: what mutation it applies, what breaks silently if it is
  skipped, and whether it should return to `Fail`.
- **Least-privilege git credential for tenant Flux sources.** The `karyon-git-auth`
  Secret in the tenant namespaces on the hub (referenced by
  `pocs/capsule/tenants/alpha.yaml` and `bravo.yaml`) currently mirrors the
  repo-write bootstrap PAT. Those namespaces are operator-only, so nothing leaks to
  tenants, but the tenant reconcilers only need read access to the repo. Replace the
  mirrored PAT with a read-only fine-grained PAT or a deploy key.
- **Preflight strict port check conflicts with the running POC cluster.**
  `scripts/preflight.sh` runs `check_port_strict 30443` (line 209). When the
  `spoke-capsule` k3d cluster is up, its load balancer's docker-proxy legitimately
  binds 30443, and the check cannot distinguish that from a foreign process
  squatting the port — so full preflight (and anything gated on it, such as
  `task deploy-examples`) fails while the POC runs. Design constraint: the static
  isolation test forbids naming `spoke-capsule` in the core scripts, so the
  allowance must be generic (for example, pass when the listener is a docker-proxy),
  and the mock-based preflight bats suites need matching updates. Found 2026-07-06.
- **`KARYON_REBUILD_APPROVED` value drift: `1` vs `yes`.** `scripts/rebuild.sh:30`
  skips the interactive rebuild confirmation only when the variable is the literal
  `yes`, but `tests/bats/delivery-05-live-slo-regression.bats` gates itself on `=1`
  — running that suite with `=1` unskips the test and then stalls on rebuild's
  interactive prompt. (`tests/bats/slo-regression-live.bats` correctly exports
  `=yes`.) One-line fix: pick a single value and align script, tests, and docs.
- **`task rebuild` cannot be validated from a git worktree or unpushed branch.**
  Rebuild bootstraps Flux against the pushed state of `main`, so exercising it from
  a worktree on an unpushed branch either validates the wrong revision or fails.
  This blocked the last full rebuild-SLO re-attestation (2026-05-29): only a
  post-rebuild `task health-check` exit-0 baseline was captured, not a timed run.
  Either teach rebuild to pin Flux to a temporary pushed test branch, or document
  that rebuild-validating work must run sequentially on `main`. Related follow-up:
  re-attest the rebuild SLO end to end (baseline about 190 seconds with a warm CUDA
  cache; budget under 230 seconds).
- **Keycloak realm day-2 lifecycle and permanent admin.** `KeycloakRealmImport` is
  import-once — it never updates an existing realm, so drift between git and the
  live `karyon` realm is unmanaged. Decide the day-2 posture: admin UI as source of
  truth, delete-and-recreate, or admin-API scripting. Also replace the temporary
  bootstrap admin (the `keycloak-initial-admin` Secret) with a permanent
  master-realm admin.
- **OIDC layer hardening.** Residuals from the 2026-07-06 OIDC wiring (runbook:
  [tenant-access.md](tenant-access.md)): the imperative pieces (CA file, k3s
  `config.yaml` apiserver flags, port forwarder, secrets) do not survive
  `k3d cluster delete` and must be re-run; the issuer lives at
  `https://localhost:31443`, which breaks if kube-proxy switches to nftables mode
  (a guard check lives in `scripts/poc/keycloak/apiserver-oidc.sh`); importing the
  lab CA into the Windows trust store remains a manual, documented step.
- **Per-tenant code-server web IDE.** Pattern documented in
  [tenant-access.md](tenant-access.md): per-tenant code-server instances behind
  oauth2-proxy (shared instances cannot isolate tenants). Not implemented —
  Headlamp's built-in pod shell covers quick exec today. Build it when a tenant
  actually needs a browser IDE.
- **Capsule controller `tls: bad certificate` log noise.** The controller
  self-signs its webhook certificates, producing benign but noisy TLS errors around
  rotation. Documented as known noise in [poc-capsule-demo.md](poc-capsule-demo.md);
  a real fix means cert-manager wiring and proper CA distribution. Revisit if
  Capsule graduates into the default rebuild path or on a production deployment.
- **Split-Kustomization seam cleanup.** A Flux Kustomization that targets a spoke
  via `spec.kubeConfig` applies everything it renders — including Flux's own CRs
  such as HelmRelease and OCIRepository — to the spoke, which runs no Flux
  controllers and lacks the CRDs. The current answer splits hub-targeted from
  spoke-targeted Kustomizations plus a post-build substitution workaround. It works
  but is subtle; a cleaner refactor of this seam is future work. (This seam is also
  the main reason Capsule graduation was deferred — see
  [ADR-0008](adr/0008-capsule-multi-tenancy-graduation.md).)
- **`task demo-capsule` convenience wrapper — rejected for now.** A one-shot demo
  task would require naming `spoke-capsule` in the default-path Taskfile, which the
  POC isolation rule (and its static test) forbids. Revisit if Capsule graduates.
- **Smaller carryovers:**
  - Shellcheck warning cleanup (SC2034 / SC2155) in the older scripts.
  - Verify the GitHub Actions CI workflow on a real push and set up branch
    protection.
  - Real secret management (Vault, SOPS, or age) — today the repo relies on a
    gitignored `.env` plus a committed `.env.example`.
  - Pre-existing markdownlint failures across older docs.
  - The allowlisted gitleaks finding on the synthetic kubeconfig test fixture
    (inert by design; revisit whether the allowlist can be narrowed).
  - Periodically run the live negative-RBAC suites in strict mode
    (`KARYON_PHASE11_STRICT_LIVE=1` turns environment-dependent skips into
    failures) as a full re-verification of the tenant boundary.

## Standing invariants

Rules that keep the lab correct. Each entry states the rule, the failure mode it
prevents, and where it is enforced.

- **Spoke-targeted Flux Kustomizations must carry the full `spec.kubeConfig` block,
  including `key: value.yaml`.** The hub reconciles into spokes through remote
  kubeconfig Secrets stored under the `value.yaml` key. If the block (or the key
  line) is omitted, Flux silently falls back to in-cluster config and reconciles
  the workload into the hub — and reports Ready, so nothing looks wrong. The
  converse also holds: hub-targeted Kustomizations that carry Flux CRs must not set
  `kubeConfig`, because the spokes lack Flux CRDs. Enforced by
  `tests/bats/register-spokes-01-static.bats` (greps `key: value.yaml` in the
  registration script and every `clusters/hub-flux/spokes/*.yaml`) and
  `tests/bats/tenants-05-static-split-path.bats` (the hub/spoke split-path rule).
- **Every tenant Flux Kustomization sets `spec.serviceAccountName` explicitly.**
  The kustomize-controller `--default-service-account` lockdown does not apply when
  `spec.kubeConfig` is set, so an unset service account falls through to the
  kubeconfig's principal — cluster-admin on the spoke — silently bypassing every
  Capsule boundary. Enforced by `tests/bats/p27-tenant-kustomization-sa-static.bats`
  and `tests/bats/tenants-02-static-p27.bats`; the lockdown flags themselves are
  patched in via `clusters/hub-flux/flux-system/kustomization.yaml`.
- **Kubeconfigs, tokens, and other secrets never land in git.** The repo is public;
  a committed credential is immediately exposed. Defense layers: gitignored `.env`
  (contract documented by `.env.example`), kubeconfig globs in `.gitignore`, a
  gitleaks pre-commit hook (`hooks/pre-commit`) with a custom
  kubeconfig-bearer-token rule in `.gitleaks.toml`, a full-history gitleaks scan in
  CI (`.github/workflows/ci.yml`), and tenant kubeconfig generators that write to
  `${TMPDIR:-/tmp}/karyon-tenants/` outside the repo.
  `tests/bats/proxy-02-static-leak-defenses.bats` fails if the gitignore or
  gitleaks defenses are weakened.
- **`task rebuild` never touches `spoke-capsule`.** The POC cluster is persistent
  state; rebuild is scorched-earth for the three core clusters only. If a core
  script learned about `spoke-capsule`, a routine rebuild would destroy the POC and
  everything staged on it. Enforced by `tests/bats/poc-isolation-01-static.bats`
  (zero non-comment `spoke-capsule` mentions in `scripts/`, excluding
  `scripts/poc/`) and, live, by `tests/bats/slo-regression-live.bats`, which checks
  the `spoke-capsule` container ID is unchanged across a real rebuild.
- **The sentinel comments in `clusters/hub-flux/flux-system/kustomization.yaml` are
  functional, never to be reworded.** `# KARYON SPOKES MOUNT` and
  `# KARYON POC MOUNT` are exact-text grep targets: `scripts/register-spokes-for-flux.sh`
  and `scripts/register-poc-cluster.sh` locate them to idempotently insert and
  verify the `../spokes` and `../pocs` resource lines, and static suites
  (`tests/bats/poc-mount-01-static.bats`, `delivery-01-static-mount-sentinel.bats`,
  `teardown-02-static-sentinel-preservation.bats`) grep for them. Rewording breaks
  idempotent onboarding — duplicate inserts or hard failures — and fails the
  suites. Note that this file is the only supported edit surface under
  `clusters/hub-flux/flux-system/`; its peer files are overwritten by every
  `flux bootstrap` run.
- **Teardown never prunes Docker caches.** `scripts/delete-clusters.sh` must not
  invoke any `docker system|builder|image|volume prune`. The custom CUDA k3s image
  cache has to survive teardown, or the under-20-minute rebuild SLO (about 190
  seconds warm) is impossible. The literal comment `INTENTIONALLY NOT calling` in
  the script is the grep target for `tests/bats/delete-clusters-01-cache.bats`,
  which also live-checks that the CUDA image survives a teardown run.
- **The Capsule `namespaces` webhook stays at `failurePolicy: Fail`.**
  `pocs/capsule/operator/helmrelease.yaml` must keep the `namespaces` mutating hook
  at the chart default `Fail`, even though most other hooks are overridden to
  `Ignore`. With `Ignore`, tenant namespaces applied before the webhook endpoint is
  ready are admitted without their owning Tenant's ownerReference; the tenant then
  reports size 0, gets no RoleBindings, and the validating webhook blocks all
  recovery — a cold-bootstrap deadlock observed live on 2026-05-27. `Fail`
  self-heals because the apiserver rejects the create and Flux retries until the
  webhook serves. Enforced by the regression guard in
  `tests/bats/capsule-install-03-static-values.bats`.

## Decision log

Standing decisions that still shape the repo.

| Decision | Why | Reference |
|----------|-----|-----------|
| Single WSL2 Ubuntu distro hosts all clusters on one shared Docker network | All WSL2 distros share one host VM, so per-distro isolation is illusory; one distro is simpler and cheaper | [ADR-0001](adr/0001-single-wsl2-shared-docker-network.md) |
| Docker Engine installed natively in WSL2, no Docker Desktop | Avoids extra WSL distros consuming the shared memory budget | [ADR-0001](adr/0001-single-wsl2-shared-docker-network.md) |
| k3d over Kind | Official GPU support, lower idle RAM, explicit `--network` control | [ADR-0002](adr/0002-k3d-over-kind.md) |
| Flux over ArgoCD | Simpler bootstrap and CRD set for lab scope; accepted trade-off: no ApplicationSet-style cluster generator, so spokes are explicit Kustomizations | [ADR-0003](adr/0003-flux-over-argocd.md) |
| Hub-only Flux control plane | No Flux controllers on spokes; the hub reconciles into spokes via `spec.kubeConfig` plus remote kubeconfig Secrets | [ADR-0004](adr/0004-hub-only-flux-control-plane.md) |
| k3s pinned to `rancher/k3s:v1.34.6-k3s1`; CUDA base pinned to 12.8+ | Flux-compatible Kubernetes line; CUDA 12.8 is the floor for RTX 5090 (Blackwell, sm_120) | [ADR-0005](adr/0005-kubernetes-version-pin.md) |
| nvidia-device-plugin pinned to v0.17.4 | No stable v0.19.x release supported Blackwell / sm_120 at selection time | [gpu-notes.md](gpu-notes.md) |
| Tool versions via asdf and a checked-in `.tool-versions` | Reproducible installs; asdf shims take PATH precedence over system binaries | `.tool-versions` |
| Public repo; secrets only via gitignored `.env` plus committed `.env.example` | Shareable by design; zero real secrets in git; explicit substitution contract | `.env.example`, `.gitleaks.toml` |
| GPU smoke test limited to `nvidia-smi` inside a pod | Avoids coupling lab health to PyTorch nightly availability for sm_120 | [gpu-notes.md](gpu-notes.md) |
| Teardown never prunes Docker build caches | The CUDA image cache must survive teardown for rebuild to meet its SLO | `scripts/delete-clusters.sh` |
| GitHub Actions pinned to full commit SHAs | Tag re-points are a supply-chain risk; SHAs are immutable | `.github/workflows/ci.yml` |
| Capsule and capsule-proxy installed as two separate HelmReleases, not the umbrella chart | The umbrella chart pins capsule-proxy two minor versions stale; standalone charts track both release lines independently | `pocs/capsule/` |
| Capsule multi-tenancy stays a POC; graduation deferred | The `spec.kubeConfig`-vs-Flux-CRs seam is only worked around, not solved; Capsule stays out of the default rebuild path until an ADR adopts it | [ADR-0008](adr/0008-capsule-multi-tenancy-graduation.md) |
| capsule-addon-fluxcd not adopted (evaluated 2026-07-06) | It is a same-cluster kubeconfig factory whose output a hub-only Flux can never consume; the explicit per-tenant service-account pattern already delivers tenant GitOps | [ADR-0008 addendum](adr/0008-capsule-multi-tenancy-graduation.md) |
