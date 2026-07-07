---
status: Active
audience: demo presenter + audience
purpose: 6-act Capsule POC demo walkthrough — three-tier permission model end-to-end.
scope: Phase 14 verification + demo runbook. Single canonical document; companion to docs/poc-capsule.md (operator runbook) and docs/capsule-on-eks.md (EKS translation).
---

# spoke-capsule POC Demo Walkthrough

> **Status:** Active (Phase 14 — Two-Perspective Demo Verification).
> **Companion docs:** [`docs/poc-capsule.md`](poc-capsule.md) (operator runbook — host-restart recovery + kubeconfig delivery contracts), [`docs/capsule-on-eks.md`](capsule-on-eks.md) (EKS translation rough-cut), [`docs/adr/0008-capsule-multi-tenancy-graduation.md`](adr/0008-capsule-multi-tenancy-graduation.md) (POC graduation = DEFER framing).

This is the load-bearing 6-act demo runbook for the `spoke-capsule` POC. It walks a teammate cold through the three-tier permission model (Cloud Ops / Karyon Platform Team / Tenant Developers) in ≤ 15 minutes against a live k3d cluster.

Each act ends with an `### Expected output` block containing verbatim apiserver / kubectl output captured live on 2026-05-19. If the cluster's actual output diverges, the demo has surfaced a regression — investigate before continuing.

How to use this document: read the act narrative aloud to the audience while running the fenced command block. The output block is what the audience should see appear in the terminal. The Pre-demo checklist (below) is for the presenter, not the audience — run it before the curtain goes up.

## Pre-demo checklist

Run every step. The checklist is executable shell — copy-paste each block, verify the expected effect, then move on. Do NOT skip steps; the runbook assumes the post-checklist state.

If any step fails on a stale cluster, recover via `task fix-dns-poc-capsule` (Step 1) first, then resume. The kubeconfig mint commands (Steps 2–3) are safely re-runnable: re-minting overwrites the same `/tmp/karyon-tenants/*.kubeconfig` file with a fresh-token kubeconfig (Phase 10 BL-02 hardening). Step 4's `--ignore-not-found` flag keeps the charlie reset idempotent across re-runs of the same demo.

```bash
# Step 1: cluster reachable?
kubectl --context k3d-spoke-capsule get nodes
# If not Ready, recover DNS:
task fix-dns-poc-capsule

# Step 2: mint platform-owner kubeconfig (Tier 2)
bash scripts/poc/capsule/issue-platform-owner-kubeconfig.sh \
  --duration 2h --write-to /tmp/karyon-tenants/platform-owner.kubeconfig
export PO_KC=/tmp/karyon-tenants/platform-owner.kubeconfig

# Step 3: mint tenant-owner kubeconfigs (Tier 3)
bash scripts/poc/capsule/issue-tenant-kubeconfig.sh alpha human-tenant-owner \
  --duration 2h --write-to /tmp/karyon-tenants/alpha-owner.kubeconfig
export TO_ALPHA_KC=/tmp/karyon-tenants/alpha-owner.kubeconfig

bash scripts/poc/capsule/issue-tenant-kubeconfig.sh bravo human-tenant-owner \
  --duration 2h --write-to /tmp/karyon-tenants/bravo-owner.kubeconfig
export TO_BRAVO_KC=/tmp/karyon-tenants/bravo-owner.kubeconfig

# Step 4: idempotent reset (charlie may exist from previous demo)
kubectl --kubeconfig=$PO_KC delete tenant charlie --ignore-not-found

# Step 5: task sanity
task -l | grep poc
```

All kubeconfig writes are constrained to `${TMPDIR:-/tmp}/karyon-tenants/` per Phase 10 BL-01/BL-02 hardening; tokens never touch git (P29 + `.gitleaks.toml` kubeconfig-bearer-token rule).

## Act 1 — Architecture + three-tier permission model

This demo walks the spoke-capsule POC three-tier permission model end-to-end against a live k3d cluster. The model exists to validate the production constraint that the Karyon Platform Team does NOT hold cloud-account cluster-admin — multi-tenancy must enforceable from a strictly-lower privilege carrier than the cloud account holder.

Articulate the three tiers to the audience before any kubectl runs:

- **Tier 1 — Cloud Ops.** Out of scope for this demo. In production, the AWS account / IAM admin holds `cluster-admin` on the EKS cluster. The Karyon Platform Team explicitly does NOT inherit this; that is the whole point of the model. In the k3d POC the equivalent is the host operator with full cluster control via kube-config.
- **Tier 2 — Karyon Platform Team.** The `platform-owner@capsule-system` ServiceAccount + `capsule-platform-owners` group. Bound to the `capsule-platform-owner` ClusterRole. Co-owner on every Tenant CR (via Phase 13 `spec.owners[]` co-ownership) so they can reach tenant workloads for break-glass ops. Lacks cluster-admin: cannot list/edit `nodes`, cannot approve `csr`, cannot write `clusterrolebindings`. This is the audience-visible ceiling demonstrated in Act 2. P27 isolation (Tenant Flux `spec.serviceAccountName: flux-reconciler`) keeps tenant GitOps surface pinned to this tier's narrower SA, not the platform-owner.
- **Tier 3 — Tenant Developers.** The `human-tenant-owner@tenant-<name>` ServiceAccount (per tenant). Bound to the `tenant-workload-editor` ClusterRole (Phase 13 narrowed from upstream `edit` — drops Secret + cross-tenant access). Routed through capsule-proxy on NodePort 30443 for LIST-filter enforcement: cluster-wide `kubectl get namespaces` returns only this tenant's namespaces, cross-tenant pods LIST returns Forbidden at the apiserver.

Production EKS translation lives in [`docs/capsule-on-eks.md`](capsule-on-eks.md) §"Three-tier permission model on EKS" — Tier 1 maps to AWS IAM admin, Tier 2 to an EKS IRSA-bound IAM role holding the `capsule-platform-owner` ClusterRole, Tier 3 to a per-tenant IRSA-bound role holding `tenant-workload-editor`. POC graduation framing lives in [`ADR-008`](adr/0008-capsule-multi-tenancy-graduation.md) — graduation is `DEFER` for v0.20; the POC remains evidence for a future production EKS cut, not a production-ready artifact.

### Expected output

```text
(No commands in this act — articulate the three-tier model verbally to the audience.)
```

## Act 2 — Platform-owner role + ceiling demo

Switch hats to Tier 2 (Karyon Platform Team). The platform-owner kubeconfig sees every Tenant CR cluster-wide (LIST visibility is the Tier-2 oversight surface), but is rejected on cluster-admin actions. The audience-facing rejection is the most visceral one: an attempt to escalate self to `cluster-admin` via a ClusterRoleBinding write — the canonical RBAC escalation path Tier 2 must never have.

The full 3-action denial matrix (`get nodes -o yaml`, `get csr`, `create clusterrolebinding`) is asserted in `tests/bats/rbac-09-live-platform-owner-kubeconfig.bats` + DEMO-06 live bats; the demo shows the headline ClusterRoleBinding case live. Audience prompt to consider: if Tier 2 could write `clusterrolebindings`, the boundary collapses — they could bind themselves to `cluster-admin` and escape the model. The Forbidden line below is the runtime guarantee that they cannot.

```bash
# Tier-2 LIST visibility — sees every Tenant cluster-wide
kubectl --kubeconfig=$PO_KC get tenants

# Tier-2 ceiling — self-escalation to cluster-admin must be rejected
kubectl --kubeconfig=$PO_KC create clusterrolebinding po-cluster-admin-attempt --clusterrole=cluster-admin --user=platform-owner
```

### Expected output

<!-- Columns re-captured live 2026-07-06 (Capsule 0.12.4 printer columns; the
     original 2026-05-19 capture predates them and the keycloak platform
     tenant added by the keycloak-idp-poc quick task). -->
```text
NAME       STATE    NAMESPACE QUOTA   NAMESPACE COUNT   NODE SELECTOR   READY   STATUS       AGE
alpha      Active   3                 1                                 True    reconciled   40d
bravo      Active   3                 1                                 True    reconciled   40d
keycloak   Active                     1                                 True    reconciled   17m

error: failed to create clusterrolebinding: clusterrolebindings.rbac.authorization.k8s.io is forbidden: User "system:serviceaccount:capsule-system:platform-owner" cannot create resource "clusterrolebindings" in API group "rbac.authorization.k8s.io" at the cluster scope
```

## Act 3 — Provision a new tenant live (charlie)

Now exercise the platform-owner's RBAC-05 Tenant CR CRUD grant: provision a brand-new tenant cold, in front of the audience. This is the load-bearing "Capsule materialize" moment — the audience sees the platform-owner CREATE → Capsule controller materialize chain in real time.

The reason live provision matters here (vs. a pre-staged delete+recreate dance): the chain is the demonstration. The platform-owner submits a Tenant CR, the Capsule controller observes it, and within a few seconds the per-tenant namespace materializes plus the co-owner SA bindings appear. Pre-staging hides exactly that chain. Per D-14-03 the demo invokes `new-tenant.sh charlie` cold; the pre-demo checklist's Step 4 already ensured charlie is not present, so this is a true cold provision.

The marquee tenant name is `charlie` (continuing the alpha → bravo → charlie phonetic alphabet). The provisioning script lives at `scripts/poc/capsule/new-tenant.sh`; it validates the name regex, applies the Tenant CR with `human-tenant-owner` co-ownership, and exits idempotently if the tenant already exists. The pre-demo checklist's Step 4 ensured the tenant is NOT present, so this is a true cold provision.

```bash
# Platform-owner provisions charlie cold (live materialization)
bash scripts/poc/capsule/new-tenant.sh charlie --kubeconfig=$PO_KC

# Confirm Tenant CR landed
kubectl --kubeconfig=$PO_KC get tenant charlie

# Confirm Capsule materialized the namespace
kubectl --kubeconfig=$PO_KC get namespace tenant-charlie
```

### Expected output

```text
[new-tenant.sh] applying Tenant CR for "charlie"...
tenant.capsule.clastix.io/charlie created
[new-tenant.sh] charlie provisioned (Tenant CR + co-owner SA bound)

NAME      STATE    AGE
charlie   Active   3s

NAME             STATUS   AGE
tenant-charlie   Active   2s
```

## Act 4 — GlobalTenantResource auto-seed observation (≤ 60s)

Capsule's `GlobalTenantResource` mechanism auto-replicates cluster-scoped fixtures into every tenant namespace. Phase 13 SEED-02 verified the ≤ 60s propagation contract on freshly-provisioned tenants; this act observes that contract live on `tenant-charlie`. The `hello-world` deployment + service are seeded by the `hello-world-seeded` GlobalTenantResource and should reach Available within the timeout. (Amended 2026-07-06 per the ADR-008 addendum: the seed is a 1-replica Deployment, not a bare Pod — bare Pods have immutable specs and put the Capsule controller in a permanent resync error loop.)

The demo value here is the cross-cut: a single cluster-scoped object materializes into N tenant namespaces automatically, without per-tenant Flux Kustomization edits. In production this is how baseline tenant fixtures (logging sidecars, network policies, default ServiceAccount annotations) propagate without per-tenant operational drift.

```bash
# Wait for SEED-02 propagation — must complete within 60s
kubectl --context k3d-spoke-capsule -n tenant-charlie wait deployment/hello-world --for=condition=Available --timeout=60s

# Confirm the seeded deployment + service are live
kubectl --context k3d-spoke-capsule -n tenant-charlie get deployment,service hello-world
```

### Expected output

```text
deployment.apps/hello-world condition met

NAME                          READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/hello-world   1/1     1            1           18s

NAME                  TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
service/hello-world   ClusterIP   10.43.142.103   <none>        80/TCP    18s
```

## Act 5 — Two perspectives (tenant-owner narrow + platform-owner co-owner)

This is the densest act and the heart of the demo: the same cluster looks different through two different kubeconfigs. The tenant-owner kubeconfig (Tier 3) is routed through capsule-proxy on NodePort 30443, which performs LIST-filter enforcement on tenant-namespace boundaries — a cluster-wide `kubectl get namespaces` issued through this kubeconfig returns ONLY the tenant's own namespaces. The platform-owner kubeconfig (Tier 2) talks directly to the apiserver but is bound to the narrowed `capsule-platform-owner` ClusterRole.

Why two perspectives matter for the audience: the Tier 3 view shows what a tenant developer sees day-to-day (their own namespace, exec into their pods, no Secret access, no cross-tenant peeking). The Tier 2 view shows the Karyon Platform Team's break-glass capability (co-owner exec into any tenant's workloads, without holding cluster-admin). The contrast between the same `hello-world` workload accessed two ways is the load-bearing visual. (`kubectl exec deploy/hello-world` resolves to a ready child pod — the seeded workload is a Deployment, so pod names carry a `-<hash>` suffix.)

Five sub-segments — switch perspective each time and call out the contrast:

```bash
# 5a — Tenant-owner alpha: scoped LIST (capsule-proxy:30443 filters cluster-wide LIST to tenant namespaces only)
kubectl --kubeconfig=$TO_ALPHA_KC get namespaces

# 5b — Tenant-owner alpha: positive controls (exec + logs into own workload)
kubectl --kubeconfig=$TO_ALPHA_KC -n tenant-alpha exec deploy/hello-world -- sh -c "echo ok-from-shell"
kubectl --kubeconfig=$TO_ALPHA_KC -n tenant-alpha logs deploy/hello-world --tail=3

# 5c — Tenant-owner alpha: negative control — Secret write is Forbidden (tenant-workload-editor drops Secret access)
kubectl --kubeconfig=$TO_ALPHA_KC -n tenant-alpha create secret generic demo-deny --from-literal=k=v

# 5d — Tenant-owner alpha: negative control — cross-tenant LIST is Forbidden (proxy:30443 filter + RBAC)
kubectl --kubeconfig=$TO_ALPHA_KC get pods -n tenant-bravo

# 5e — Switch hats: platform-owner co-owner exec into tenant-alpha workload (Tier 2 break-glass)
kubectl --kubeconfig=$PO_KC -n tenant-alpha exec deploy/hello-world -- sh -c "hostname"
```

### Expected output

```text
# 5a — tenant-alpha visible only (proxy:30443 LIST filter)
NAME           STATUS   AGE
tenant-alpha   Active   2d

# 5b — exec + logs succeed inside own tenant
ok-from-shell

2026/05/19 22:41:37 [notice] 1#1: start worker process 47
2026/05/19 22:41:37 [notice] 1#1: start worker process 48
2026/05/19 22:41:37 [notice] 1#1: start worker process 49

# 5c — Secret create is Forbidden (tenant-workload-editor narrowed from upstream edit)
error: failed to create secret secrets is forbidden: User "system:serviceaccount:tenant-alpha:human-tenant-owner" cannot create resource "secrets" in API group "" in the namespace "tenant-alpha"

# 5d — cross-tenant pods LIST is Forbidden
Error from server (Forbidden): pods is forbidden: User "system:serviceaccount:tenant-alpha:human-tenant-owner" cannot list resource "pods" in API group "" in the namespace "tenant-bravo"

# 5e — platform-owner co-owner exec succeeds (Tier 2 break-glass into tenant workload)
# (hostname == pod name; Deployment pods carry a -<hash> suffix)
hello-world-6d8f4c9b7d-x2m4q
```

## Act 6 — Cleanup (delete charlie)

Close the lifecycle loop. The platform-owner (RBAC-05 delete grant) tears down the `charlie` tenant. Capsule unmaterializes the namespace; tenant workloads and the seeded `hello-world` deployment go with it. Tenants `alpha` and `bravo` are untouched — re-run Act 5's 5a / 5b commands after the delete to confirm the unrelated tenants still serve traffic.

The audience takeaway: tenant lifecycle (create → seed → use → delete) is fully exercised from Tier 2 alone. At no point did the demo invoke `cluster-admin`. The Karyon Platform Team carries enough authority to provision and tear down tenants, but not enough to escalate into cluster-control plane — exactly the constraint the three-tier model promises.

```bash
# Platform-owner deletes charlie — Capsule unmaterializes
kubectl --kubeconfig=$PO_KC delete tenant charlie

# Confirm the namespace was unmaterialized
kubectl --kubeconfig=$PO_KC get namespace tenant-charlie
```

### Expected output

```text
tenant.capsule.clastix.io "charlie" deleted

Error from server (NotFound): namespaces "tenant-charlie" not found
```

## Known noise — `tls: bad certificate` chatter

**What it is.** The capsule-controller-manager pod emits a `tls: bad certificate` log line ~1Hz throughout normal operation, visible via:

```bash
kubectl --context k3d-spoke-capsule -n capsule-system logs deploy/capsule-controller-manager --tail=30 | grep tls
```

Example:

```text
2026/05/19 23:50:49 http: TLS handshake error from 10.42.0.1:39986: remote error: tls: bad certificate
```

This is the apiserver's webhook-handshake retry loop against capsule-controller-manager using a self-signed cert it doesn't trust. It does NOT affect tenant boundary enforcement or `GlobalTenantResource` propagation (verified empirically via Phase 13 + this phase's DEMO-01..06 bats).

**Historical note (fixed 2026-07-06).** Before the ADR-008 addendum amended the GTR seed to a Deployment, the controller log ALSO carried a permanent `unable to replicate the requested resources ... Pod "hello-world" is invalid` error loop — the bare-Pod rawItem hit Pod-spec immutability on every resync and sat in controller-runtime exponential backoff. How to read `unable to replicate` lines now: an occasional single line whose error is `Operation cannot be fulfilled ... the object has been modified` is a benign optimistic-concurrency race (Capsule's 60s resync UPDATE racing the deployment-controller's status writes; controller-runtime retries and succeeds on the next attempt). A line that REPEATS with the same error across consecutive reconciles is a regression signal (registry allowlist drift, immutable-shape rawItems, RBAC) — do not talk-track past that.

**Why document-only.** Per [ADR-008](adr/0008-capsule-multi-tenancy-graduation.md) the Capsule POC is `DEFER` for production graduation; the chatter is cosmetic, not functional. Fixing it pulls in cert-manager / CA-distribution work that the lean v0.20 milestone is explicitly scope-guarded against. A production EKS cut would wire AWS Certificate Manager or cert-manager controller-managed certs cleanly; see [`docs/capsule-on-eks.md`](capsule-on-eks.md) §"Phase 11 Evidence — Cert source".

## Forward pointers

- [`docs/poc-capsule.md`](poc-capsule.md) §"Host restart recovery" — operator-side fix-dns + cluster-stop/start recovery procedures.
- [`docs/capsule-on-eks.md`](capsule-on-eks.md) §"Three-tier permission model on EKS" — production translation of the three-tier carriers (Cloud Ops / Karyon Platform Team / Tenant Developers).
- [`docs/adr/0008-capsule-multi-tenancy-graduation.md`](adr/0008-capsule-multi-tenancy-graduation.md) — POC graduation = DEFER framing (cited in "Known noise" appendix).

---

*Demo runbook captured live 2026-05-19. Re-run end-to-end to validate; expected single-pass cold-read duration ≤ 15 minutes per RUNBOOK-04 UAT contract.*
