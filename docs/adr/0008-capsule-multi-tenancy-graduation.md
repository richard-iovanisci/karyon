# 8. Capsule Multi-Tenancy POC Graduation

## Status

Accepted (2026-05-06)

Outcome: DEFER

## Context

The v0.19 milestone evaluated [Capsule](https://capsule.clastix.io/) v0.12.4 as a karyon-managed
multi-tenancy pattern. The proof of concept ran on a dedicated, isolated k3d cluster
(`spoke-capsule`) so the default topology and the `task rebuild` path stayed untouched.

What shipped:

- Capsule operator and capsule-proxy installed from the hub via Flux (HelmRelease + OCIRepository),
  under the hub-only Flux control plane ([ADR-004](0004-hub-only-flux-control-plane.md)).
- Tenant CRs (`alpha`, `bravo`), lockdown flags on the hub Flux controllers
  (`--no-cross-namespace-refs`, `--no-remote-bases`, `--default-service-account=default`), and
  tenant kubeconfigs issued via the TokenRequest API with capsule-proxy filtering tenant LIST calls.
- A negative-RBAC suite (12 cross-tenant escape attempts), a webhook failure-mode drill, a
  clean-teardown procedure, and a full-history secret scan.

Detailed run-by-run evidence is preserved in git history (pre-de-GSD tree; see commit history
around the v0.19/v0.20 tags).

## Decision

Graduation is **deferred**: Capsule stays a POC on the isolated cluster and is not promoted into
the default rebuild path. The core rationale:

- **An unresolved install-path seam.** Hub-only Flux (ADR-004) means the POC's outer
  Kustomization targets `spoke-capsule` via `spec.kubeConfig` — but HelmRelease and OCIRepository
  are Flux CRs, and the spoke has no Flux CRDs by design. The Helm install path therefore never
  fully reconciled end-to-end from the hub. Neither candidate fix (drop the kubeConfig redirect
  for the CR layer, or keep Flux CRs on the hub and send only rendered resources to the spoke)
  was settled at decision time.
- **A chart RBAC workaround pending an upstream fix.** The capsule-proxy chart's rendered Role
  lacks the `secrets create` verb its bundled `kube-webhook-certgen` Job needs; karyon extends
  the Role via a Flux post-build patch. The patch is correct in git, but its live propagation to
  the spoke could not be confirmed because of the seam above.
- **A pending `capsule-addon-fluxcd` trial** was expected to clarify whether the addon pattern
  sidesteps the seam. (Settled 2026-07-06 — see the final addendum: pass, do not adopt.)

Rejection was not warranted: no tenant-isolation invariant was breached in any run (failing runs
traced to the install-path seam, not isolation escapes), teardown was clean end-to-end, webhook
recovery was deterministic, the rebuild SLO did not regress, and the full-history secret scan
was clean apart from two pre-existing synthetic-fixture findings handled with a file-specific
allowlist (broad path-pattern allowlists were rejected as leak-hiding).

### What we did not prove

- **HA Capsule** — single replica only; leader-election semantics untested.
- **OIDC integration** — TokenRequest bearer tokens only; no external IdP tested at the time (a
  later Keycloak POC addresses this — [docs/poc-keycloak.md](../poc-keycloak.md)).
- **Multi-spoke federation** — Capsule has no native cross-cluster Tenant; the POC spoke is isolated.
- **Hub-side Capsule** — control-plane self-tenancy is a different threat model; separate ADR.
- **Real ingress / TLS for capsule-proxy** — NodePort with a self-signed, chart-managed cert only.
- **Production secret management** — short-lived TokenRequest tokens only; no Vault, SOPS, or age.
- **GPU + Capsule interaction** — the POC spoke has no GPU.
- **Non-k3d Kubernetes** — validated on k3d only.
- **Live propagation of the capsule-proxy RBAC patch** — verified statically only; live
  verification was blocked by the install-path seam.

Two platform-specific trade-offs from this POC are documented where they matter: the EKS 24 h
token-duration clamp (k3s does not clamp; verified live to 720 h) in
[docs/eks-platform-handoff.md](../eks-platform-handoff.md), and karyon's opinionated
CapsuleConfiguration `userGroups` additions in
[docs/capsule-portable-setup-guide.md](../capsule-portable-setup-guide.md).

## Consequences

- `spoke-capsule` remains a persistent, isolated POC cluster; it joins the default `task rebuild`
  chain only if a future ADR adopts it.
- The capsule-proxy RBAC patch stays until the upstream chart grows the missing verb; the
  install-path seam must be settled before any adoption re-run.
- POC teardown force-deletes stranded PVC finalizers after 60 s — acceptable for a lab, wrong for
  production data; a production teardown needs a preserve-data path.
- EKS translation guidance lives in [docs/eks-platform-handoff.md](../eks-platform-handoff.md);
  DEFER does not invalidate it — the POC remains the reference implementation it translates from.

## Addendum — 2026-05-27 cold-bootstrap webhook race finding

Re-running the demo runbook on the same git revision and topology that produced green evidence a
week earlier failed at tenant-owner namespace LIST: Capsule was not claiming tenant namespaces
even though the Tenant CRs were Ready and the namespaces carried the right labels.

Root cause (full write-up:
[docs/rca/capsule-namespace-webhook-deadlock.md](../rca/capsule-namespace-webhook-deadlock.md)):
the `namespaces` mutating webhook (`namespaces.tenants.projectcapsule.dev`) had been set to
`failurePolicy: Ignore` by a blanket belt-and-suspenders override, displacing the Capsule chart
default of `Fail` for this hook. On cold bootstrap, the webhook service Endpoint takes a few
seconds to become Ready after the controller starts. If Flux applies the tenant namespace
manifests inside that window, the apiserver's webhook call fails and — because of `Ignore` — the
namespaces are silently admitted **without** the ownerReference mutation that claims them for
their Tenant. The companion validating webhook then blocks every UPDATE and DELETE on those
namespaces (label present but ownerReference missing fails its consistency check). The state is
unrecoverable without bypassing the webhook: scale the controller to zero, delete the bad
namespaces, scale back up, re-reconcile. The race is timing-dependent, so earlier cold rebuilds
simply won the dice roll — the bug was latent from the start.

Mitigations, verified live 2026-05-27:

1. The `namespaces` hook is pinned back to the chart default `failurePolicy: Fail`
   (`pocs/capsule/operator/helmrelease.yaml`); the other hooks keep `Ignore`. Failing closed is
   self-healing: the CREATE is rejected and Flux retries until the webhook serves.
2. OCIRepository chart sources are pinned by digest in addition to tag — secondary supply-chain
   hygiene, not the root cause.

This reinforces DEFER: a stack whose cold-bootstrap path can silently wedge itself into an
unrecoverable webhook deadlock is not production-ready; a production cut needs cert-manager and
a real webhook readiness gate.

## Addendum — 2026-07-06 post-v0.20 defect sweep

A post-milestone audit re-checked the shipped POC against its own committed contracts and live
cluster state; two Capsule-relevant defects were found and fixed the same day.

**Finding 1 — a GlobalTenantResource seeding a bare Pod put the controller in a permanent error
loop.** The seed (`pocs/capsule/spoke/global-resources/hello-world.yaml`) replicated a bare `Pod`
into every tenant namespace. Pod specs are immutable on update, and `GlobalTenantResource` has
no update-skip option (its spec is only `tenantSelector` / `resyncPeriod` / `pruningOnDelete` /
`resources`), so every resync re-sent the sparse spec as a full UPDATE and the apiserver
rejected it. The controller sat in exponential backoff (~20 s doubling toward the ~16-minute
requeue cap), displacing the assumed 60 s resync cadence and establishing a permanent baseline
of `unable to replicate` errors that would mask real replication failures with the same
signature. The seeded workloads ran fine, so the defect shipped blind: nothing ever read the
controller logs. Fix: the replicated resource is now a 1-replica `apps/v1` Deployment (mutable
spec, same container and Service); bare `Pod` — and `Job`, also immutable — are forbidden
replicated shapes, guarded statically by `tests/bats/seed-01-static-globaltenantresource.bats`;
live assertions moved to Deployment semantics, and the demo runbook now marks
`unable to replicate` as a regression signal, not known noise.

**Finding 2 — the regression guard for the 2026-05-27 webhook fix was inverted and unenforced.**
`tests/bats/capsule-install-03-static-values.bats` still asserted `failurePolicy == "Ignore"` —
the pre-fix value the addendum above exists to prevent — and no CI gate executed the suite. Had
someone "fixed CI" by wiring the suite in, the failing test would have invited a revert of the
`Fail` pin, reintroducing the cold-bootstrap deadlock. The assertion is now inverted to `Fail`,
all static test suites run in CI, and five sibling suites that had drifted stale the same way
were reconciled to committed reality in the same sweep.

Both are process findings as much as code findings: static guards only protect a decision while
they actually run in CI and are updated alongside the decisions they pin. The graduation
calculus is unchanged — still DEFER — but the demo is reproducible again (clean controller logs,
tenant GitOps path restored).

## Addendum — 2026-07-06 capsule-addon-fluxcd evaluation: pass (do not adopt)

The DEFER rationale cited a future `capsule-addon-fluxcd` trial as a factor that would clarify
the architectural shape. A source-level evaluation (README, controller source, releases, issues)
settles it: **pass — do not adopt.**

**Correction of ADR-008's premise.** This ADR originally described the addon as auto-installing
Capsule via a Flux-managed addon. That is wrong: the addon installs nothing. It is a
tenant-owner kubeconfig factory that must run **on** the Capsule cluster — it watches
ServiceAccounts annotated `capsule.addon.fluxcd/enabled=true` that are Tenant owners and
creates, locally: a cluster-admin RoleBinding in the SA's namespace, a self-impersonation
ClusterRole/Binding, a non-expiring legacy token Secret, and a kubeconfig Secret whose server is
capsule-proxy's in-cluster DNS. Tenant Flux Kustomizations on the *same* cluster then consume
that kubeconfig via `spec.kubeConfig.secretRef`.

**Decisive reason to pass.** Flux resolves `kubeConfig.secretRef` only in its own cluster and
namespace. Under hub-only Flux (ADR-004, spokes run zero Flux components), the addon's output —
a Secret on `spoke-capsule` — is unreachable by the hub's kustomize-controller, and the addon
has no remote mode (no flag, doc, issue, or code path). Bridging would require a new imperative
per-tenant cross-cluster secret-copy and rotation mechanism: strictly more moving parts than the
pattern it would replace. And the goal it serves — platform team controls tenants; tenants
deploy into their spaces through Flux — is already delivered by hub-side tenant Kustomizations
(spoke kubeconfig plus `serviceAccountName` impersonation), live-verified Ready.

**Secondary confirmations.** Adoption would make capsule-proxy load-bearing for every reconcile
(today it matters only for tenant LIST filtering). The addon is built against the Capsule v0.7.2
Go module with no declared compatibility with Capsule 0.12.x. Maintenance is thin: roughly one
release per year, and the chart crash-loops with default values against the current
capsule-proxy chart (upstream issue open for ~6 months). Its Kubernetes deps do match karyon's
1.34 — version skew is not the blocker; topology is.

**Revisit trigger.** This is a topology verdict, not a quality verdict. Re-open only if hub-only
Flux (ADR-004) is reversed, or in a single-cluster environment where kustomize-controller runs
on the Capsule cluster itself. Recorded alongside the Keycloak IdP POC
([docs/poc-keycloak.md](../poc-keycloak.md)), which addresses the identity half of the same
platform-team story without the addon.
