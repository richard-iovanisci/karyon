# Phase 14: Two-Perspective Demo Verification + 6-Act Runbook + TLS-Noise Resolution - Research

**Researched:** 2026-05-19
**Domain:** Capsule POC demo verification + operator-grade runbook authoring + live cluster bats falsifiers
**Confidence:** HIGH (live cluster reachable; all 10 open-research questions answered against the running `spoke-capsule` cluster + verbatim file inspection)

---

## Summary

Phase 14 is **pure verification + documentation** — no new YAML, no new ClusterRoles, no Helm changes. Every primitive needed for the 6-act walkthrough already lives on the cluster: `tenant-workload-editor` ClusterRole, `capsule-platform-owner` ClusterRole + dual-subject ClusterRoleBinding, platform-owner SA in `capsule-system`, `GlobalTenantResource` reconciling `hello-world` nginx Pods + Services into every tenant namespace, capsule-proxy NodePort 30443. All three RBAC ceiling behaviors (platform-owner cannot CRB, tenant-owner cannot create Secret, tenant-owner cannot LIST cross-tenant) were verified verbatim against the live cluster during this research pass — the Forbidden message strings are captured exactly so the runbook's `### Expected output` blocks are authoritative, not invented.

Two new live bats files plus 1–2 file extensions cover the DEMO-01..06 falsifier contract. The runbook (`docs/poc-capsule-demo.md`) is the load-bearing deliverable: single document, 6 ordered `## Act N` sections, pre-demo checklist with executable shell snippets, post-act-6 "Known noise" + "Forward pointers" appendices. The UAT (RUNBOOK-04) is the falsifier: milestone-owner cold-reads the doc against the live cluster with a stopwatch — pass criterion is a single-pass under-15-minutes run captured in `14-VALIDATION.md`.

**Primary recommendation:** Treat the runbook as the load-bearing artifact (UAT is the contract). Land RED bats first (Wave 0), then runbook draft, then resolve TLS-noise text, then UAT. Every Forbidden snippet in the runbook MUST come from the verbatim captures in this RESEARCH (no invented strings — operators copy-paste and the demo audience watches the text appear).

---

## User Constraints (from CONTEXT.md)

### Locked Decisions

**D-14-01 — TLS noise treatment = document-only.** The capsule-controller `tls: bad certificate` 1Hz chatter is NOT fixed. It is documented in `docs/poc-capsule-demo.md` as a known-noise note: 2-paragraph appendix after act 6 explaining (a) what it is, (b) why document-only (POC scope per ADR-008 = DEFER). Cross-links ADR-008. No code/script/Helm changes.

**D-14-02 — Marquee tenant name = `charlie`.** Appears verbatim across `docs/poc-capsule-demo.md` (acts 3 + 6), any new bats fixture, any new helper script if planner adds one. Single canonical name across runbook + scripts + bats.

**D-14-03 — Provision style = live.** Act 3 invokes `bash scripts/poc/capsule/new-tenant.sh charlie` cold. Pre-demo checklist includes `kubectl delete tenant charlie --ignore-not-found` reset for idempotent re-runs.

**D-14-04 — Single document = `docs/poc-capsule-demo.md`.** Frontmatter (`status: Active`, `audience: demo presenter + audience`, `purpose: 6-act capsule POC demo walkthrough`, `scope: Phase 14 verification + demo runbook`). 6 ordered `## Act N — ...` sections + appendix-style "Pre-demo checklist", "Known noise", "Forward pointers" sections.

**D-14-05 — Pre-demo checklist is executable, not narrative.** Each item is a `kubectl` / `bash` snippet with expected output. Covers: cluster reachable, `task fix-dns-poc-capsule` if needed, both kubeconfigs minted + paths exported as env vars (`PO_KC`, `TO_ALPHA_KC`, `TO_BRAVO_KC`), `kubectl delete tenant charlie --ignore-not-found` reset, `task -l | grep poc` sanity check.

**D-14-06 — Each act has concrete kubectl/task step + expected output block.** Every act ends with `### Expected output` fenced block showing canonical successful response. Forbidden-action expected outputs include the verbatim `Error from server (Forbidden): ...` line.

**D-14-07 — DEMO-06 surfacing.** Runbook act 2 features ONE primary Forbidden action live: `kubectl create clusterrolebinding po-cluster-admin-attempt --clusterrole=cluster-admin --user=platform-owner`. Bats covers all three (`kubectl get nodes -o yaml`, `kubectl get csr`, `kubectl create clusterrolebinding`).

**D-14-08 — Two-perspective verification = new live bats files.** New `demo-N-live-*.bats` keyed to DEMO-01..06 REQs. Planner picks final names + count; 4–6 anticipated. Preference is new files (traceability), not extensions of Phase 13 rbac-08..10.

**D-14-09 — Tenant-owner routes through capsule-proxy NodePort 30443.** Inherited from Phase 10. No new wiring. Pre-demo checklist mints `TO_ALPHA_KC` + `TO_BRAVO_KC` via `bash scripts/poc/capsule/issue-tenant-kubeconfig.sh alpha human-tenant-owner` (+ bravo equivalent).

**D-14-10 — UAT = milestone-owner cold-read ≤ 15 min, stopwatched, captured in `14-VALIDATION.md`.** Pattern-mirrors Phase 13's VALIDATION.md.

### Claude's Discretion

- Exact split of plans within Phase 14. Anticipated shape (planner may adjust): Wave 0 RED bats + Wave 1 runbook draft + Wave 2 TLS-noise doc + cross-links + Wave 3 UAT. 3–5 plans target.
- Whether DEMO bats files extend existing rbac/negative-rbac or land as new `demo-*.bats`. Preference is new files.
- Exact bats fixture for SEED-02 fresh-tenant assertion on `charlie`.
- TLS noise documentation depth (2 paragraphs minimum; cap ~half a page).
- Whether to add a `task demo-capsule` Taskfile wrapper. Recommendation: **no** — keeps P31 isolation strict.

### Deferred Ideas (OUT OF SCOPE)

- Fix `tls: bad certificate` chatter at cert-rotation layer (cert-manager / CA distribution) — future capsule-graduation phase.
- `task demo-capsule` Taskfile wrapper — breaks P31 isolation.
- `capsule-addon-fluxcd` Trial (ADDON-01/02 v0.19 carry-forward) — not load-bearing for demo.
- Markdownlint / shellcheck cleanup — v0.18 close carryover.
- Real secret management for `/tmp` kubeconfigs — v0.18 close carryover.
- G-04 split-Kustomization refactor — future-milestone architecture review.

---

## Phase Requirements

| ID | Description (verbatim summary) | Research Support |
|----|-------------------------------|------------------|
| DEMO-01 | Platform-owner kubeconfig: cluster-scoped Tenant CR visibility + co-owner LIST/get-pods-A across every tenant namespace through capsule-proxy. | Verified live: `kubectl --kubeconfig=$PO get tenants` returns `alpha` + `bravo`; `get ns` returns 4 tenant namespaces (`alpha-app1`, `bravo-app1`, `tenant-alpha`, `tenant-bravo`); `get pods -n tenant-alpha` succeeds. Pattern in `rbac-09-live-platform-owner-kubeconfig.bats`. New bats: `demo-01-live-*.bats`. |
| DEMO-02 | Tenant-owner kubeconfig (routed through capsule-proxy:30443) sees ONLY own tenant's namespaces — verified for both alpha-owner + bravo-owner. | Verified pattern in `negative-rbac-01-cross-tenant-list.bats` @test N2 (proxy LIST filter scope). New bats: `demo-02-live-*.bats` driving both `TO_ALPHA_KC` + `TO_BRAVO_KC`. |
| DEMO-03 | Tenant-owner can `kubectl get / logs / exec` on the SEED-01 hello-world workload in own namespaces; platform-owner can do same across ALL tenant namespaces (RBAC-06). | Verified live: `nginx:alpine` Pod has `sh` available (`exec hello-world -- sh -c "echo ok-from-shell"` → `ok-from-shell`); `logs` returns nginx start lines. New bats: `demo-03-live-*.bats`. |
| DEMO-04 | Tenant-owner REJECTED on `kubectl create secret`. Rejection observable + scriptable. | Verbatim Forbidden captured (see Q6 below). New bats: `demo-04-live-*.bats`. |
| DEMO-05 | Tenant-owner REJECTED on cross-tenant access (alpha→bravo and vice versa). | Verified pattern in `negative-rbac-01-cross-tenant-list.bats` N1 + N3. New bats: `demo-05-live-*.bats`. |
| DEMO-06 | Platform-owner REJECTED on cluster-admin-only actions (`get nodes -o yaml`, `get csr`, `create clusterrolebinding`). | Verified live verbatim Forbidden message for CRB (see Q6 below). Pattern in `rbac-08-live-platform-owner-grant-matrix.bats`. New bats: `demo-06-live-*.bats`. |
| RUNBOOK-01 | 6-act walkthrough — explicit articulation of the three-tier permission model; concrete kubectl/task step + expected output per act. | New file `docs/poc-capsule-demo.md`. Acts shape per CONTEXT.md D-14 + ROADMAP §"Phase 14" success criterion 4. |
| RUNBOOK-02 | Pre-demo checklist: cluster reachable, fix-dns if needed, kubeconfigs staged. Executable, not narrative. | `task fix-dns-poc-capsule` confirmed live (Taskfile.yml:44-47). |
| RUNBOOK-03 | Known-noise note for TLS chatter + ADR-008 cross-link + `docs/capsule-on-eks.md` cross-link with three-tier-on-EKS mapping. | TLS verbatim log line captured (Q2 below). ADR-008 already exists. `docs/capsule-on-eks.md` has implicit three-tier mapping but no explicit "Tier 1/2/3" labels — gap candidate for small append (Q1 below). |
| RUNBOOK-04 | Executable end-to-end ≤ 15 min cold by a human reading it. UAT by milestone owner. | UAT captured in `14-VALIDATION.md` (D-14-10). Target word count derived from comparable runbooks (Q9 below). |
| RUNBOOK-05 | New-tenant name (`charlie`) reflected verbatim in act-3, canonical across runbook + scripts + bats. | `charlie` name verified clean in `new-tenant.sh` head-comment usage block + regex `^[a-z][a-z0-9-]{1,30}$`. |

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Document walkthrough (`docs/poc-capsule-demo.md`) | Repo / Docs | — | Pure markdown artifact; no runtime tier. Lives under `docs/` per convention. |
| Live demo verification (bats over live cluster) | bats / Test infra | `spoke-capsule` apiserver + capsule-proxy | bats drive `kubectl --kubeconfig=...` against live cluster — same pattern as Phase 13 rbac-08..10. |
| Tenant CR provisioning (act 3) | `kubectl` direct apply | Capsule controller (materializes ns + RoleBindings) | Per ADR-004 + D-14-03: `kubectl apply`, NOT Flux reconcile (audience-visible immediacy). |
| Platform-owner LIST (Tier 2) | capsule-proxy NodePort 30443 | apiserver | Platform-owner kubeconfig routes through proxy for LIST filtering; capsule-proxy uses Group `capsule-platform-owners` to expose all tenants. |
| Tenant-owner LIST (Tier 3) | capsule-proxy NodePort 30443 | apiserver | Tenant-owner kubeconfig routes through proxy; LIST filter restricts to own tenant namespaces (Phase 10 wiring). |
| Forbidden enforcement (DEMO-04, DEMO-06) | Kubernetes apiserver RBAC | — | RBAC denial happens at apiserver layer (Forbidden 403), NOT at proxy edge. Stable verbatim message format. |
| SEED propagation observation (act 4) | Capsule controller (`GlobalTenantResource`) | apiserver namespace materialization | SEED-02 ≤ 60s contract inherited from Phase 13. |
| Pre-demo cluster recovery | `task fix-dns-poc-capsule` → `scripts/poc/capsule/fix-dns.sh` | k3d cluster stop/start | Existing Taskfile entry (Taskfile.yml:44-47); no new code. |

---

## Research Findings (per open question 1–10)

### Q1 — `docs/capsule-on-eks.md` three-tier mapping

**Status:** Implicit only; the explicit "Tier 1 / Tier 2 / Tier 3" labels do NOT appear in the existing doc.

**What the doc currently says (verified verbatim from `/home/rich/code/gsd/karyon/docs/capsule-on-eks.md`):**

- Has an **"## Required permissions / RBAC"** table (lines 35-43) with three rows: Capsule operator SA (`cluster-admin`), capsule-proxy SA, per-tenant SA. This is roughly Tier-2-equivalent staffing but does NOT explicitly label "Tier 1 — Cloud Ops" or "Tier 2 — Karyon Platform Team" or "Tier 3 — Tenant Developers".
- Has an **IRSA TrustPolicy** verbatim YAML (lines 110-128) wired per-tenant SA. This is the Tier 3 IRSA pattern.
- Has a Mermaid topology diagram (lines 48-81) showing capsule-controller-manager + capsule-proxy + tenant workloads + ECR + IAM + NLB — captures the operational layout but does NOT articulate the three-tier *permission* model.
- "Phase 11 Evidence" blockquotes (lines 227-259) discuss IRSA / cert source / proxy LIST scope — these are technical translation notes, not three-tier framing.

**Gap to address (recommended for Phase 14, planner's call per D-14 Discretion):** Append a short subsection to `docs/capsule-on-eks.md` — recommend `## Three-tier permission model on EKS` (~10-15 lines) — mapping:

- **Tier 1 — Cloud Ops:** AWS account / IAM admin holding cluster-admin on the EKS cluster.
- **Tier 2 — Karyon Platform Team:** EKS IRSA-bound IAM role + cluster-scoped RBAC (the EKS-target of the `capsule-platform-owners` group); same `capsule-platform-owner` ClusterRole shape (NO cluster-admin, NO nodes, NO csr, NO clusterrolebinding writes).
- **Tier 3 — Tenant Developers:** IRSA-bound IAM role per tenant SA (existing pattern in the doc); same `tenant-workload-editor` ClusterRole shape.

This is purely additive (no edits to existing content). Confidence: HIGH (doc inspection verbatim).

**Falsifier:** A static bats grep — `bats tests/bats/runbook-03-static-eks-three-tier.bats` (or extension of an existing static bats) asserts the literal strings "Tier 1", "Tier 2", "Tier 3" appear in `docs/capsule-on-eks.md`. Confidence: HIGH.

---

### Q2 — Exact capsule-controller `tls: bad certificate` log line

**Verbatim log line (captured live 2026-05-19):**

```
2026/05/19 23:50:49 http: TLS handshake error from 10.42.0.1:39986: remote error: tls: bad certificate
```

**Inspection command (for runbook):**

```bash
kubectl --context k3d-spoke-capsule -n capsule-system logs deploy/capsule-controller-manager --tail=30 | grep tls
```

**Observed rhythm:** 1 line per second (1Hz) — verified live: 10 consecutive lines spanning timestamps `23:50:49` through `23:50:58`. Source pod IP `10.42.0.1` (cluster CIDR) — almost certainly the apiserver retrying a webhook handshake against capsule-controller-manager's webhook listener using a cert it doesn't trust (the chart-self-signed cert that Phase 11 evidence already documented).

**What it does NOT affect:** verified live during this research pass — Tenant CR LIST returned `alpha + bravo` correctly, namespace LIST returned 4 tenant namespaces correctly, hello-world Pod exec succeeded, Forbidden enforcement succeeded. The TLS chatter is cosmetic.

**Runbook treatment (D-14-01):** 2-paragraph appendix after act 6 — paragraph 1 = "what" (verbatim log line + 1Hz + inspect command); paragraph 2 = "why document-only" (POC scope per ADR-008 = DEFER; fixable in EKS cut via cert-manager but not load-bearing for the three-tier demo). Cross-link ADR-008.

**Falsifier:** Static bats `runbook-03-static-tls-noise-section.bats` asserts (a) the verbatim string `tls: bad certificate` appears in `docs/poc-capsule-demo.md`, (b) the literal "ADR-008" or "adr/0008" cross-link appears in the same file, (c) the section comes AFTER act 6 (not inline). Confidence: HIGH.

---

### Q3 — `kubectl exec` against tenant namespaces via capsule-proxy

**Status:** Verified live working.

**Verbatim probe (captured 2026-05-19 via platform-owner kubeconfig, against tenant-alpha):**

```bash
kubectl --kubeconfig=$PO_KC -n tenant-alpha exec hello-world -- sh -c "echo ok-from-shell"
```

**Returned output:**

```
ok-from-shell
```

**Why this works:** SEED-01 hello-world Pod uses image `docker.io/library/nginx:alpine` (verified live: `kubectl get pod hello-world -o jsonpath='{.spec.containers[*].image}'` returns `docker.io/library/nginx:alpine`). `nginx:alpine` ships with BusyBox `sh` at `/bin/sh`. The Phase 13 D-13-02 FQCI decision (`docker.io/library/nginx:alpine` per Pitfall 13-P1) directly enables this — a `nginx:1.0` minimal image without a shell would have broken DEMO-03.

**Runbook usage (act 5 DEMO-03):** Use `sh -c "echo ok-from-shell"` (or `sh -c "hostname"`) — short, single-line, predictable stdout. The exec works through capsule-proxy for tenant-owner; it works directly via platform-owner-via-proxy too (verified live above).

**Falsifier:** `demo-03-live-tenant-owner-exec.bats` — `run kubectl --kubeconfig="$TO_ALPHA_KC" -n tenant-alpha exec hello-world -- sh -c "echo ok"; [ "$status" -eq 0 ]; echo "$output" | grep -qF ok`. Confidence: HIGH.

---

### Q4 — `kubectl logs` against tenant namespaces

**Status:** Verified live working.

**Verbatim probe (captured 2026-05-19 via platform-owner kubeconfig, against tenant-alpha):**

```bash
kubectl --kubeconfig=$PO_KC -n tenant-alpha logs hello-world --tail=3
```

**Returned output (last 3 lines):**

```
2026/05/19 22:41:37 [notice] 1#1: start worker process 47
2026/05/19 22:41:37 [notice] 1#1: start worker process 48
2026/05/19 22:41:37 [notice] 1#1: start worker process 49
```

**Runbook usage:** DEMO-01 + DEMO-03 — both platform-owner (all tenant namespaces) and tenant-owner (own namespace only) can `kubectl logs hello-world`. Output is nginx startup log — stable, deterministic enough for an audience-facing expected-output block.

**Falsifier:** `demo-03-live-*.bats` — `run kubectl --kubeconfig="$TO_ALPHA_KC" -n tenant-alpha logs hello-world --tail=3; [ "$status" -eq 0 ]; echo "$output" | grep -qF "worker process"`. Confidence: HIGH.

---

### Q5 — Capsule namespace materialization for new tenant `charlie`

**Status:** Verified by inspection of `new-tenant.sh` rendering + dry-run.

**The `new-tenant.sh` script (verified verbatim from `/home/rich/code/gsd/karyon/scripts/poc/capsule/new-tenant.sh`) renders three resources for `charlie`:**

1. **Tenant CR** `charlie` with `forceTenantPrefix: false` (matches Phase 11 D-11-07) + owners list = `flux-reconciler@flux-system` SA + `capsule-platform-owners` Group + `platform-owner@capsule-system` SA + `human-tenant-owner@tenant-charlie` SA (with `clusterRoles: [tenant-workload-editor]`).
2. **Namespace** `tenant-charlie` (with labels `capsule.clastix.io/tenant: charlie`, `karyon.io/poc: capsule`, `karyon.io/provisioned-by: new-tenant.sh`).
3. **ServiceAccount** `human-tenant-owner` in namespace `tenant-charlie`.

**Dry-run captured live 2026-05-19** (`bash scripts/poc/capsule/new-tenant.sh charlie --kubeconfig=$PO_KC --dry-run`):

```
kind: Tenant
metadata:
  name: charlie
kind: Namespace
metadata:
  name: tenant-charlie
kind: ServiceAccount
metadata:
  name: human-tenant-owner
  namespace: tenant-charlie
```

**Key answer:** `new-tenant.sh charlie` produces exactly ONE tenant namespace: `tenant-charlie`. It does NOT auto-create a `charlie-app1` sub-namespace (sub-namespaces are Phase 9 ephemera created via `kubectl --as=alpha create namespace alpha-app1`; `new-tenant.sh` does not replicate that step). Therefore, the SEED-02 propagation falsifier on `charlie` watches for `hello-world` Ready in `tenant-charlie` only — same pattern as `seed-03-live-fresh-tenant.bats` watching `tenant-phase13-fresh`.

**Runbook usage (acts 3, 4, 5, 6):** Reference `tenant-charlie` verbatim. Act 4 SEED-02 observation watches `kubectl --context k3d-spoke-capsule -n tenant-charlie wait pod/hello-world --for=condition=Ready --timeout=60s`. Act 5 tenant-owner perspective uses `bash scripts/poc/capsule/issue-tenant-kubeconfig.sh charlie human-tenant-owner --write-to /tmp/karyon-tenants/to-charlie.kubeconfig` to mint a tenant-charlie kubeconfig (optional — only if planner wants a 3rd kubeconfig in the demo; D-14 doesn't mandate it, since alpha-owner + bravo-owner already prove the boundary). Act 6 cleanup: `kubectl --kubeconfig=$PO_KC delete tenant charlie` (Capsule unmaterializes `tenant-charlie` namespace + bindings).

Confidence: HIGH (script inspection verbatim + live dry-run).

---

### Q6 — Forbidden message format

**Status:** Verified verbatim live 2026-05-19.

**DEMO-06 Forbidden (platform-owner attempting ClusterRoleBinding create — the act-2 headline):**

```
error: failed to create clusterrolebinding: clusterrolebindings.rbac.authorization.k8s.io is forbidden: User "system:serviceaccount:capsule-system:platform-owner" cannot create resource "clusterrolebindings" in API group "rbac.authorization.k8s.io" at the cluster scope
```

**DEMO-04 Forbidden (tenant-owner attempting Secret create in own namespace):**

```
error: failed to create secret secrets is forbidden: User "system:serviceaccount:tenant-alpha:human-tenant-owner" cannot create resource "secrets" in API group "" in the namespace "tenant-alpha"
```

**Pattern shape:**

- Phrase `Error from server (Forbidden)` is the apiserver's HTTP 403 wrapper; kubectl prefixes with `error: failed to create <kind>:` for create operations specifically.
- The User string is verbatim from the apiserver auth layer: `system:serviceaccount:<ns>:<sa-name>`.
- Stable across kubectl versions for this k3s pin (verified live).

**Runbook usage:** Every Forbidden `### Expected output` block in the runbook MUST include the verbatim "forbidden: User ..." substring so the audience can read the actual rejection. Use the exact strings above.

**Falsifier:** New bats (`demo-04-live-tenant-secret-forbidden.bats` + `demo-06-live-platform-owner-cluster-admin-denials.bats`) — for each: `run kubectl ...; [ "$status" -ne 0 ]; echo "$output" | grep -qF "forbidden:"; echo "$output" | grep -qE "User.*platform-owner|User.*human-tenant-owner"`. Confidence: HIGH (verbatim).

---

### Q7 — `task fix-dns-poc-capsule` invocation

**Status:** Verified live present in Taskfile.

**Taskfile.yml entry (verbatim lines 44-47):**

```yaml
fix-dns-poc-capsule:
  desc: Stop/start spoke-capsule to refresh stale k3d CoreDNS NodeHosts (POC; does NOT affect default fix-dns)
  cmds:
    - bash scripts/poc/capsule/fix-dns.sh
```

**Runbook usage (pre-demo checklist):** Conditional snippet — if `kubectl --context k3d-spoke-capsule get nodes` returns non-zero or `NotReady`, run `task fix-dns-poc-capsule`. Otherwise skip.

**Recommended checklist text:**

```bash
# Step 1: cluster reachable?
kubectl --context k3d-spoke-capsule get nodes
# If not Ready, recover DNS:
task fix-dns-poc-capsule
```

Confidence: HIGH.

---

### Q8 — Pre-mint scripts for tenant-owner kubeconfigs

**Status:** Verified by reading both scripts (`issue-tenant-kubeconfig.sh` + `issue-platform-owner-kubeconfig.sh`).

**`issue-tenant-kubeconfig.sh` signature (verbatim from script):**

```
Usage: issue-tenant-kubeconfig.sh <tenant> <owner> [--duration <d>] [--write-to <path>]
```

Positional args required: `<tenant>` (e.g., `alpha`, `bravo`, `charlie`) + `<owner>` SA name (`gitops-reconciler` OR `human-tenant-owner` — D-14 default for human-exercised demos is `human-tenant-owner` per RBAC-02).

**`--write-to` path constraint:** MUST resolve under `${TMPDIR:-/tmp}/karyon-tenants/` — script rejects paths outside this directory (BL-01 + BL-02 hardening per Phase 10). All tenant kubeconfigs land owner-private (mode 0600, umask 0077).

**`issue-platform-owner-kubeconfig.sh` signature (verbatim):**

```
Usage: issue-platform-owner-kubeconfig.sh [--duration <d>] [--write-to <path>]
```

NO positional args — SA target is pinned (`platform-owner@capsule-system`). Same `--write-to` constraints. Default write path: `${TMPDIR:-/tmp}/karyon-tenants/platform-owner.kubeconfig` when `--write-to` is a directory.

**Recommended pre-demo checklist text (executable, copy-paste):**

```bash
# Step 2: mint platform-owner kubeconfig (Tier 2 — sees all tenants)
bash scripts/poc/capsule/issue-platform-owner-kubeconfig.sh \
  --duration 2h --write-to /tmp/karyon-tenants/platform-owner.kubeconfig
export PO_KC=/tmp/karyon-tenants/platform-owner.kubeconfig

# Step 3: mint tenant-owner kubeconfigs (Tier 3 — own tenant only via capsule-proxy:30443)
bash scripts/poc/capsule/issue-tenant-kubeconfig.sh alpha human-tenant-owner \
  --duration 2h --write-to /tmp/karyon-tenants/alpha-owner.kubeconfig
export TO_ALPHA_KC=/tmp/karyon-tenants/alpha-owner.kubeconfig

bash scripts/poc/capsule/issue-tenant-kubeconfig.sh bravo human-tenant-owner \
  --duration 2h --write-to /tmp/karyon-tenants/bravo-owner.kubeconfig
export TO_BRAVO_KC=/tmp/karyon-tenants/bravo-owner.kubeconfig
```

**Note (Phase 10 / 13 convention):** stderr is preflight-lib log lines; stdout is empty when `--write-to` is set. Operators see ANSI-colored `ok` lines on stderr — that's normal, not failure.

Confidence: HIGH.

---

### Q9 — `docs/poc-capsule-demo.md` length budget

**Comparable runbooks measured:**

- `docs/poc-capsule.md` (operator runbook, Phase 7+10+13 cumulative): **276 lines.**
- `docs/rebuild-runbook.md` (v0.18 rebuild walkthrough): **322 lines.**

**15-minute-cold-read budget estimate:** A practiced reader processes ~200-250 words/minute for technical prose with code blocks interspersed. 15 minutes × 200 wpm ≈ 3,000 words ceiling. A code-heavy runbook with executable snippets is closer to ~150 lines per minute of read-time (code blocks reduce wpm but accelerate scan-and-execute). Target: **~250-350 lines total** for `docs/poc-capsule-demo.md` (pre-demo checklist + 6 acts + appendices) — comparable to `poc-capsule.md` / `rebuild-runbook.md` size class.

**Tight budget per section (planner uses as upper bound, not requirement):**

| Section | Target lines | Notes |
|---------|-------------|-------|
| Frontmatter | 6-8 | Standard convention |
| Architecture overview (act 1) | 30-40 | Three-tier model articulation + Mermaid optional |
| Platform-owner role (act 2) | 25-35 | Tenant LIST + ONE Forbidden CRB + expected output |
| Provision new tenant live (act 3) | 25-35 | `new-tenant.sh charlie` + expected output |
| SEED auto-propagation (act 4) | 20-30 | `kubectl wait` on tenant-charlie hello-world + observe ≤60s |
| Two perspectives (act 5) | 40-60 | Densest act: alpha-owner LIST + Forbidden secret + cross-tenant rejection + switch back to platform-owner for co-owner LIST/EXEC. Most time-on-task. |
| Cleanup (act 6) | 15-25 | `kubectl delete tenant charlie` + observe unmaterialization |
| Pre-demo checklist | 30-40 | Executable shell snippets per D-14-05 |
| Known noise (TLS) | 15-25 | 2-paragraph appendix per D-14-01 |
| Forward pointers | 10-15 | Cross-link ADR-008 + `docs/capsule-on-eks.md` + `docs/poc-capsule.md` |
| **Total** | **~216-313** | Within 15-min cold-read budget |

If the draft balloons past ~400 lines, the UAT (RUNBOOK-04) will fail — collapse expository sections and move detail to forward-pointed docs.

Confidence: MEDIUM-HIGH (comparable-runbook empirical anchor; UAT is the final falsifier).

---

### Q10 — bats live-RBAC fixture pattern

**Status:** Verified by reading `rbac-08`, `rbac-09`, `rbac-10`, `seed-03`, `negative-rbac-01` verbatim.

**Canonical `setup_file` pattern for new `demo-*-live-*.bats` files:**

```bash
#!/usr/bin/env bats
# tests/bats/demo-N-live-<slug>.bats
# Phase 14 / Wave 0 (D-14-08 Nyquist gate)
# DEMO-N — <one-line behavior>.
# RED until <gate>.

load 'test_helper'

setup_file() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
  export KARYON_BATS_TMPDIR="${TMPDIR:-/tmp}/karyon-tenants/bats-${BATS_RUN_TMPDIR##*/}"
  mkdir -p "$KARYON_BATS_TMPDIR"
  # Mint platform-owner kubeconfig
  bash "${REPO_ROOT}/scripts/poc/capsule/issue-platform-owner-kubeconfig.sh" \
    --duration=2h --write-to "${KARYON_BATS_TMPDIR}/po.kubeconfig" >/dev/null 2>&1
  export PO_KUBECONFIG="${KARYON_BATS_TMPDIR}/po.kubeconfig"
  # Mint alpha + bravo tenant-owner kubeconfigs (DEMO-02/03/04/05 need them)
  bash "${REPO_ROOT}/scripts/poc/capsule/issue-tenant-kubeconfig.sh" alpha human-tenant-owner \
    --duration=2h --write-to "${KARYON_BATS_TMPDIR}/alpha.kubeconfig" >/dev/null 2>&1
  bash "${REPO_ROOT}/scripts/poc/capsule/issue-tenant-kubeconfig.sh" bravo human-tenant-owner \
    --duration=2h --write-to "${KARYON_BATS_TMPDIR}/bravo.kubeconfig" >/dev/null 2>&1
  export ALPHA_KUBECONFIG="${KARYON_BATS_TMPDIR}/alpha.kubeconfig"
  export BRAVO_KUBECONFIG="${KARYON_BATS_TMPDIR}/bravo.kubeconfig"
}

teardown_file() {
  rm -rf "$KARYON_BATS_TMPDIR"
}

setup() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
  [ -f "${PO_KUBECONFIG:-/dev/null}" ] || skip "kubeconfigs not minted (setup_file failed)"
  [ -f "${ALPHA_KUBECONFIG:-/dev/null}" ] || skip "alpha kubeconfig not minted"
  [ -f "${BRAVO_KUBECONFIG:-/dev/null}" ] || skip "bravo kubeconfig not minted"
}
```

**Key conventions verified:**

- `load 'test_helper'` (NOT `'../test_helper'`) — bats resolves load path relative to the test file's directory (per test_helper.bash comment).
- `REPO_ROOT` is set by `test_helper.bash` line 22 — available in every bats suite.
- Per-suite TMPDIR: `${TMPDIR:-/tmp}/karyon-tenants/bats-${BATS_RUN_TMPDIR##*/}` — ensures kubeconfigs land owner-private under `${TMPDIR}/karyon-tenants/` (Phase 7 P29 + Phase 10 BL-02). Cleaned in `teardown_file`.
- Cluster probe (`kubectl ... cluster-info`) in both `setup_file` AND `setup` — `setup_file` runs once, but `setup` runs per @test; both gates guard against partial-fail mid-suite.
- Forbidden assertion idiom: `run kubectl ...; [ "$status" -ne 0 ]; echo "$output" | grep -qE "(Forbidden|forbidden|cannot)"` — matches both `Error from server (Forbidden)` and `forbidden: User ...` substrings.

**For DEMO-04 (Forbidden secret create) specifically, recommended @test:**

```bash
@test "DEMO-04: tenant-owner alpha cannot create secret in own namespace" {
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" -n tenant-alpha \
    create secret generic demo-deny --from-literal=k=v
  [ "$status" -ne 0 ]
  echo "$output" | grep -qF "forbidden:"
  echo "$output" | grep -qF 'human-tenant-owner'
}
```

Confidence: HIGH.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| bats-core | 1.11.0 | Live + static falsifiable contracts | Already installed (Phase 13 VALIDATION.md); same framework all 110 existing tests use |
| kubectl | matches `spoke-capsule` k3s 1.34.6 | Demo + bats execution | Already required by every existing script |
| jq | system | TokenRequest + kubeconfig minting | Used by `issue-*-kubeconfig.sh` scripts |
| realpath | system | `--write-to` path validation | Used by Phase 10 / 13 scripts |

**No new tooling installs required.** All Wave 0 dependencies present.

### Supporting

| Asset | Purpose | When to Use |
|-------|---------|-------------|
| `scripts/poc/capsule/issue-platform-owner-kubeconfig.sh` | Mint platform-owner kubeconfig | Pre-demo checklist + every bats `setup_file` |
| `scripts/poc/capsule/issue-tenant-kubeconfig.sh <tenant> human-tenant-owner` | Mint tenant-owner kubeconfig | Pre-demo checklist + DEMO-02/03/04/05 bats setup |
| `scripts/poc/capsule/new-tenant.sh charlie` | Live tenant provisioning (act 3) | Runbook act 3; optional `demo-04-live-charlie-*.bats` |
| `scripts/poc/capsule/fix-dns.sh` (via `task fix-dns-poc-capsule`) | Hub-spoke DNS recovery | Pre-demo checklist conditional step |
| `tests/bats/test_helper.bash` | Shared loader (sets `REPO_ROOT`, sources preflight-lib) | Every new bats file via `load 'test_helper'` |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| New `demo-*-live-*.bats` files | Extend `rbac-09-live-platform-owner-kubeconfig.bats` + `negative-rbac-01-cross-tenant-list.bats` | New files preferred (D-14-08) — traceability against DEMO-01..06 REQs; extension increases file size and obscures REQ→test mapping |
| Single combined `demo-all-live.bats` file | Per-REQ files (`demo-01-live-...bats` through `demo-06-live-...bats`) | Per-REQ files preferred — failure messages map directly to REQ IDs; sampling can subset by REQ ID; consistent with rbac/seed/delivery partition |
| `task demo-capsule` Taskfile wrapper | Raw `bash scripts/poc/capsule/...` in runbook | Raw commands preferred (D-14 Discretion + P31) — keeps Taskfile clean of `spoke-capsule` mentions; runbook explicit about every step |
| Append three-tier-on-EKS to existing `docs/capsule-on-eks.md` | Inline in `docs/poc-capsule-demo.md` | Append preferred — `docs/poc-capsule-demo.md` cross-links to a clean three-tier-on-EKS section; avoids duplication |

**Installation:** None required (all tooling present).

---

## Architecture Patterns

### System Architecture Diagram

```
                                     ┌──────────────────────────────┐
                                     │  spoke-capsule (k3d cluster) │
                                     └──────────────────────────────┘
                                                  │
        ┌─────────────────────────────────────────┼─────────────────────────────────────────┐
        │                                         │                                         │
        ▼                                         ▼                                         ▼
┌─────────────────┐                  ┌─────────────────────┐                ┌──────────────────────────┐
│  Apiserver      │◄──────RBAC───────│ capsule-controller- │                │     capsule-proxy        │
│  (k3s:1.34.6)   │                  │     manager         │                │   NodePort 30443         │
│  https://0.0.0.0│                  │ (Tenant/GTR ctlr)   │                │   (LIST filter edge)     │
│  :6446          │                  └─────────────────────┘                └──────────────────────────┘
└─────────────────┘                            │                                       ▲
        ▲                                      │                                       │
        │ direct apply                         │ reconciles Tenant CR                  │
        │ (Acts 3 + 6: kubectl)                │ → materializes ns                     │
        │                                      │ + RoleBindings                        │
        │                                      ▼                                       │
        │                          ┌──────────────────────────┐                        │
        │                          │  Tenant namespaces       │                        │
        │                          │  - tenant-alpha (Phase 9)│                        │
        │                          │  - tenant-bravo (Phase 9)│                        │
        │                          │  - tenant-charlie (Act 3)│                        │
        │                          │  - alpha-app1 (Phase 9)  │                        │
        │                          │  - bravo-app1 (Phase 9)  │                        │
        │                          │  • hello-world Pod       │◄──GlobalTenantResource┤
        │                          │    nginx:alpine          │                        │
        │                          │  • hello-world Service   │                        │
        │                          └──────────────────────────┘                        │
        │                                                                              │
        │                                                                              │
        │   ┌─────────────────────────────────────────────────────────────────────┐    │
        │   │                  Demo presenter (operator host)                     │    │
        │   │                                                                     │    │
        │   │  $PO_KC = /tmp/karyon-tenants/platform-owner.kubeconfig             │    │
        │   │    SA: platform-owner@capsule-system                                │    │
        │   │    Group impersonation: capsule-platform-owners                     │    │
        │   │    ClusterRole: capsule-platform-owner (Tier 2 — NO cluster-admin)  │    │
        │   │    → server: https://127.0.0.1:30443 (capsule-proxy)                │────┘
        │   │                                                                     │
        │   │  $TO_ALPHA_KC = /tmp/karyon-tenants/alpha-owner.kubeconfig          │
        │   │  $TO_BRAVO_KC = /tmp/karyon-tenants/bravo-owner.kubeconfig          │
        │   │    SA: human-tenant-owner@tenant-<name>                             │
        │   │    ClusterRole: tenant-workload-editor (Tier 3 — narrower than edit)│
        │   │    → server: https://127.0.0.1:30443 (capsule-proxy)                │
        │   └─────────────────────────────────────────────────────────────────────┘
```

**Data-flow narrative (runbook reading order):**

1. **Act 1 (architecture):** Audience sees the three-tier diagram (the box on the right) overlaid on the cluster (boxes on the left). Talk-track only — no commands run.
2. **Act 2 (platform-owner):** Operator runs `kubectl --kubeconfig=$PO_KC get tenants` → returns alpha + bravo (proves Tier 2 LIST). Then `kubectl --kubeconfig=$PO_KC create clusterrolebinding ...` → returns Forbidden (proves Tier 2 ceiling).
3. **Act 3 (provision):** Operator runs `bash scripts/poc/capsule/new-tenant.sh charlie` → kubectl apply through `$PO_KC`. Capsule controller observes new Tenant CR → materializes `tenant-charlie` ns + injects RoleBindings.
4. **Act 4 (SEED):** Operator runs `kubectl --context k3d-spoke-capsule -n tenant-charlie wait pod/hello-world --for=condition=Ready --timeout=60s`. GlobalTenantResource controller reconciled the hello-world Pod + Service into `tenant-charlie` within seconds of namespace creation.
5. **Act 5 (two perspectives):** Operator switches to `$TO_ALPHA_KC` → LIST returns only alpha namespaces (proxy LIST filter), create-secret returns Forbidden, cross-tenant attempt returns Forbidden. Switch back to `$PO_KC` → LIST + exec across tenant-charlie succeeds (co-owner).
6. **Act 6 (cleanup):** `kubectl --kubeconfig=$PO_KC delete tenant charlie` → Capsule unmaterializes `tenant-charlie` namespace + Pod + Service.

### Recommended File Structure

```
docs/
├── poc-capsule-demo.md                          # NEW — Phase 14 deliverable (250-350 lines)
├── poc-capsule.md                               # EXISTING — operator runbook (cross-linked)
└── capsule-on-eks.md                            # POSSIBLY EXTENDED — three-tier-on-EKS append

tests/bats/
├── demo-01-live-platform-owner-list.bats        # NEW — DEMO-01 (Tier 2 LIST tenants + ns + pods-A)
├── demo-02-live-tenant-owner-scoped-list.bats   # NEW — DEMO-02 (Tier 3 scoped LIST, both alpha + bravo)
├── demo-03-live-pod-ops.bats                    # NEW — DEMO-03 (logs + exec, both kubeconfigs)
├── demo-04-live-tenant-secret-forbidden.bats    # NEW — DEMO-04 (Tier 3 ceiling: secret create)
├── demo-05-live-cross-tenant-forbidden.bats     # NEW — DEMO-05 (cross-tenant rejection)
├── demo-06-live-platform-owner-cluster-admin-denials.bats  # NEW — DEMO-06 (3-action denial matrix)
└── runbook-{01,02,03,04,05}-static-*.bats       # NEW — RUNBOOK-01..05 static contracts (file exists, sections present, cross-links valid)

scripts/poc/capsule/                             # UNCHANGED — no new scripts
```

### Pattern 1: Single 6-act runbook file with `### Expected output` per act

**What:** Each `## Act N — <Title>` section contains: (1) intent paragraph (~2-4 lines), (2) command(s) in a fenced bash block, (3) `### Expected output` fenced text/plaintext block with verbatim canonical output.

**When to use:** Every act in the runbook. Pattern lifted from `docs/poc-capsule.md` (operator runbook) and `docs/rebuild-runbook.md`.

**Example template:**

```markdown
## Act 2 — Platform-owner role + ceiling demo

The Karyon Platform Team (Tier 2) sees every tenant but is NOT cluster-admin.
Tenant CR LIST proves the visibility. Attempting to create a ClusterRoleBinding
proves the ceiling.

```bash
# Tenant CR LIST (platform-owner)
kubectl --kubeconfig=$PO_KC get tenants

# Forbidden: ClusterRoleBinding create (Tier 2 ceiling)
kubectl --kubeconfig=$PO_KC create clusterrolebinding po-cluster-admin-attempt \
  --clusterrole=cluster-admin --user=platform-owner
```

### Expected output

```text
NAME    STATE    NAMESPACE QUOTA   NAMESPACE COUNT   ...   READY   STATUS       AGE
alpha   Active   3                 2                       True    reconciled   12d
bravo   Active   3                 2                       True    reconciled   12d

error: failed to create clusterrolebinding: clusterrolebindings.rbac.authorization.k8s.io is forbidden: User "system:serviceaccount:capsule-system:platform-owner" cannot create resource "clusterrolebindings" in API group "rbac.authorization.k8s.io" at the cluster scope
```
```

### Pattern 2: Wave 0 RED bats scaffold before any documentation lands

**What:** Plan 14-00 (Wave 0) lands all DEMO-01..06 + RUNBOOK-01..05 bats files RED. Plan 14-01+ lands the runbook + makes them GREEN.

**When to use:** Always — Nyquist gate inheritance from Phase 13 (D-13-15). The failing bats files define the falsifiable contract before any prose is written.

### Anti-Patterns to Avoid

- **Inventing expected-output strings.** Every `### Expected output` block must come from a verbatim live capture (this RESEARCH.md has the canonical strings for Forbidden CRB, Forbidden secret, hello-world exec, hello-world logs, tenants LIST). Inventing them risks the UAT failing on a typo a copy-paste user would never notice.
- **Embedding the operator-runbook fix-dns prose inline in the demo runbook.** Cross-link to `docs/poc-capsule.md` Host-restart recovery section. Demo runbook stays demo-focused.
- **Adding a `task demo-capsule` Taskfile wrapper.** D-14 Discretion + P31 invariant. Adds `spoke-capsule` mentions to v0.18 Taskfile namespace; breaks `delivery-02-static-paths.bats` / `poc-isolation-01-static.bats`.
- **Treating TLS noise as a runbook step.** Document-only — appendix after act 6, not inline in any act. Inline would distract the demo audience and contradict D-14-01.
- **Forgetting the `karyon-tenants/` parent dir.** `issue-*-kubeconfig.sh --write-to` rejects paths outside `${TMPDIR}/karyon-tenants/`. Operator must `mkdir -p` the dir OR the scripts will fail. Document explicitly in pre-demo checklist (the scripts auto-create the dir via `install -d -m 0700`, but the runbook should still mention the path).
- **Pre-staging the new tenant (`charlie`).** D-14-03 requires live provisioning. A pre-staged delete+recreate dance hides the audience-visible Capsule materialization moment.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Kubeconfig minting | Custom bash heredoc with hard-coded token | `bash scripts/poc/capsule/issue-platform-owner-kubeconfig.sh` + `issue-tenant-kubeconfig.sh` | Phase 10/13 scripts already handle TokenRequest + tls.crt embed + path hardening (BL-01/BL-02 symlink defenses); rolling our own re-introduces gitleaks risk + path-traversal vectors |
| Tenant provisioning | Hand-written Tenant CR YAML in the runbook | `bash scripts/poc/capsule/new-tenant.sh charlie` | `new-tenant.sh` template has the correct dual-subject owner set (Group + 3 SAs) per D-13-08 — hand-rolling drops the Tier-2/Tier-3 co-ownership contract |
| Forbidden assertion in bats | Parse JSON error response | `run kubectl ...; [ "$status" -ne 0 ]; echo "$output" \| grep -qF "forbidden:"` | Phase 11 + 13 pattern; works across kubectl versions; matches both `Error from server (Forbidden)` and `forbidden: User ...` substrings |
| Pre-demo cluster reachability check | Custom curl probe | `kubectl --context k3d-spoke-capsule get nodes` | Standard k8s health probe; output is verifiable in expected-output blocks |
| TLS noise diagnosis | Inline cert-manager / CA distribution instructions | 2-paragraph appendix per D-14-01 + ADR-008 cross-link | ADR-008 = DEFER stands; fixing the chatter pulls in cert-manager work that v0.20 anti-scope guard rejects |
| EKS three-tier mapping | Inline EKS YAML in the demo runbook | Append to `docs/capsule-on-eks.md` + cross-link from demo runbook | Single source of truth for EKS translation; demo runbook stays demo-focused |

**Key insight:** Phase 14 is verification + documentation. Almost every primitive needed already exists; the work is wiring them into a cohesive narrative + locking the falsifier contract in bats. Resist the temptation to add new scripts or new YAML — the anti-scope guard is active.

---

## Common Pitfalls

### Pitfall 14-P1: Stale tenant kubeconfig tokens during the 15-min cold-read

**What goes wrong:** Operator mints tenant kubeconfigs at the start of the pre-demo checklist with default `--duration 1h`. UAT or live demo runs past 1h → tokens expire mid-act → kubectl returns `Unauthorized` instead of the expected output.

**Why it happens:** `--duration` default is 1h in both `issue-*-kubeconfig.sh` scripts. The pre-demo checklist + 6-act walkthrough + slack for audience Q&A can plausibly exceed 1h.

**How to avoid:** Pre-demo checklist mints with `--duration 2h` (matches the bats-suite convention of `--duration=2h` in `setup_file`). Document explicitly in the checklist with a one-line justification ("buffer for Q&A").

**Warning signs:** Mid-demo `error: You must be logged in to the server (Unauthorized)`. Recovery: re-run the mint command — TokenRequest produces a fresh token; nothing else to do.

### Pitfall 14-P2: `kubectl exec` returns "no shell" on a different SEED workload shape

**What goes wrong:** If Phase 13 SEED-03 had landed `nginx:1.0-minimal` (no shell) or a `busybox`-only Pod without `sh`, DEMO-03 exec assertion would have failed.

**Why it happens:** SEED-03 OQ-3 resolution + Phase 13 D-13-02 FQCI picked `docker.io/library/nginx:alpine` — which DOES ship with BusyBox `sh`. Verified live during this research pass. But a future SEED workload refactor could break the contract.

**How to avoid:** New bats `demo-03-live-pod-ops.bats` locks the exec contract: `kubectl exec hello-world -- sh -c "echo ok"` must succeed. If a future change swaps the workload to a shell-less image, this bats will fail RED — exact intended falsifier behavior.

**Warning signs:** `OCI runtime exec failed: exec failed: unable to start container process: exec: "sh": executable file not found in $PATH`. Mitigation: confirm SEED workload image still contains a shell, OR change the exec target to a different SEED resource (e.g., `kubectl get svc hello-world`).

### Pitfall 14-P3: `charlie` tenant left over from prior demo runs

**What goes wrong:** Operator runs the demo, doesn't get to act 6 cleanup, then re-runs. Act 3 `new-tenant.sh charlie` fails with "Tenant 'charlie' already exists" (verified live in `new-tenant.sh:155-159`).

**Why it happens:** D-14-03 demands live provisioning; the script is idempotent on tenant *existence* (rejects pre-existing tenant), not on tenant *cleanup*.

**How to avoid:** Pre-demo checklist includes a reset step (D-14-03): `kubectl --kubeconfig=$PO_KC delete tenant charlie --ignore-not-found --wait=false` followed by `kubectl --context k3d-spoke-capsule wait --for=delete namespace tenant-charlie --timeout=30s` (Pitfall 13-P6 unmaterialization wait pattern).

**Warning signs:** Script exits 1 with `Tenant 'charlie' already exists. Hint: kubectl --kubeconfig=... delete tenant charlie`. Recovery: run the hint.

### Pitfall 14-P4: capsule-proxy NodePort 30443 unreachable from operator host

**What goes wrong:** k3d host-port forwarding can lapse after Docker restart. Tenant-owner kubeconfigs use `server: https://127.0.0.1:30443` — if 30443 isn't bound, every tenant-owner kubectl returns `connection refused`.

**Why it happens:** k3d cluster restart re-binds container ports but a host firewall / WSL2 networking quirk can drop the binding. Phase 7 P31 fix-dns recovery doesn't address port-forwarding.

**How to avoid:** Pre-demo checklist includes a NodePort reachability probe:

```bash
curl -k https://127.0.0.1:30443/livez 2>&1 | head -1
# Expected: HTTP/1.1 401 Unauthorized (proves TCP+TLS works, auth missing as expected)
```

If unreachable, run `task fix-dns-poc-capsule` (also bounces the cluster, re-establishing port bindings).

**Warning signs:** `dial tcp 127.0.0.1:30443: connect: connection refused`. Recovery: cluster bounce.

### Pitfall 14-P5: bats `setup_file` mint failure cascades to per-test skips

**What goes wrong:** If `issue-platform-owner-kubeconfig.sh` fails in `setup_file` (e.g., capsule-proxy Secret cert rotation in flight per Pitfall 10-P1), every @test in the suite skips silently.

**Why it happens:** Existing pattern (`rbac-08`/`rbac-09`/`rbac-10`/`seed-03`) treats setup_file failure as a `skip` — RED-by-design pre-Plan-13-02 was the original intent. Post-Plan-13-02 (when scripts exist + work), the skip masks real failures.

**How to avoid:** Phase 14 bats should NOT skip if minting fails post-Phase-13. Use a stricter gate: `[ -f "$PO_KUBECONFIG" ] && [ -f "$ALPHA_KUBECONFIG" ] && [ -f "$BRAVO_KUBECONFIG" ]` OR fail explicitly. Pattern from `negative-rbac-01-cross-tenant-list.bats` (`_strict_skip` + `KARYON_PHASE11_STRICT_LIVE=1` env var) is a precedent for graduation-deciding runs.

**Warning signs:** Bats report says `ok 1 # skip (kubeconfigs not minted)` for every @test in the suite, but the cluster is reachable. Mitigation: tighten setup gate.

### Pitfall 14-P6: TLS noise spike during demo (audience asks "is something broken?")

**What goes wrong:** Audience opens `kubectl logs deploy/capsule-controller-manager` and sees the 1Hz TLS chatter. Without forewarning, this looks like a broken cluster.

**Why it happens:** D-14-01 documents the noise but the "Known noise" appendix lives AFTER act 6 — audience may scroll past it or never read it.

**How to avoid:** Add ONE-LINE forward-pointer in act 1 architecture overview: "If you inspect controller logs during the demo, you will see a 1Hz `tls: bad certificate` chatter — this is cosmetic; see the *Known noise* appendix at the end of this runbook for the full explanation and the ADR-008 cross-link." (Per D-14-01, the *full* 2-paragraph explanation stays in the appendix; only a forward-pointer is inline.)

**Warning signs:** Audience question about cert errors mid-demo. Mitigation: redirect to appendix.

---

## Runtime State Inventory

**Not applicable.** Phase 14 is verification + documentation only. No rename, no refactor, no migration. The 5 categories of runtime state checked explicitly:

| Category | Items Found | Action Required |
|----------|-------------|-----------------|
| Stored data | None — Phase 14 does not modify any datastore, CRD, ConfigMap, Secret, or namespace beyond ephemeral `charlie` tenant lifecycle | None |
| Live service config | None — capsule-controller-manager + capsule-proxy + GTR controllers continue unchanged from Phase 13; no Helm value edits, no chart bumps | None |
| OS-registered state | None — no new systemd / launchd / Task Scheduler / pm2 / cron registrations | None |
| Secrets/env vars | None — operator-host env vars (`PO_KC`, `TO_ALPHA_KC`, `TO_BRAVO_KC`) are ephemeral shell exports per the pre-demo checklist; no code reads them outside the demo session itself | None |
| Build artifacts | None — no new compiled binaries, no new pip/npm installs, no Docker image edits | None |

Nothing found in any category. **Verified by:** scope inspection of CONTEXT.md `<domain>` block + REQUIREMENTS.md DEMO-01..06 + RUNBOOK-01..05 (verification + documentation REQs only; no artifact-creating REQs).

---

## Environment Availability

> Skip this section if no external dependencies — but Phase 14 depends on the live `spoke-capsule` cluster, so it is included.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `spoke-capsule` k3d cluster reachable | All demo bats + UAT cold-read | ✓ | k3s 1.34.6 (verified live 2026-05-19: `https://0.0.0.0:6446` responsive) | `task fix-dns-poc-capsule` |
| Phase 13 artifacts on cluster (`capsule-platform-owner` CR, dual-subject CRB, `platform-owner` SA, `tenant-workload-editor` CR, GlobalTenantResource, alpha+bravo Tenant CRs with `capsule-platform-owners` co-owner) | All DEMO bats | ✓ | Phase 13 commit `4d5b58e` (verified live: `kubectl get tenants` returns alpha + bravo Active; `kubectl exec hello-world` works in tenant-alpha) | None — Phase 13 must be GREEN |
| capsule-proxy NodePort 30443 reachable from operator host | DEMO-02/03/04/05 (tenant-owner) + DEMO-01 platform-owner LIST namespaces | ✓ (verified by Phase 13 rbac-09 GREEN status) | NodePort 30443 (Phase 7 reservation) | `task fix-dns-poc-capsule` to bounce cluster |
| `bash scripts/poc/capsule/issue-platform-owner-kubeconfig.sh` | All DEMO bats + pre-demo checklist | ✓ (Phase 13 Plan 13-02) | Phase 13 D-13-09 shape | None — Phase 13 must be GREEN |
| `bash scripts/poc/capsule/issue-tenant-kubeconfig.sh` | DEMO-02/03/04/05 + pre-demo checklist | ✓ (Phase 10 Plan 10-01) | Phase 10 D-10-01..06 shape | None |
| `bash scripts/poc/capsule/new-tenant.sh` | RUNBOOK-05 act 3 + optional bats falsifier | ✓ (Phase 13 Plan 13-02) | Phase 13 D-13-08 shape (regex `^[a-z][a-z0-9-]{1,30}$`) | None |
| `task fix-dns-poc-capsule` | Pre-demo recovery | ✓ (Taskfile.yml:44-47) | Phase 7 entry | None |
| bats-core | All falsifier tests | ✓ (1.11.0) | 1.11.0 | None |

**No missing dependencies. No fallback gaps. Cluster reachable, all primitives present.**

---

## Validation Architecture

**Nyquist enabled** (`config.json` `workflow.nyquist_validation: true`, verified via `.planning/config.json` line ~30).

### Test Framework

| Property | Value |
|----------|-------|
| Framework | bats-core 1.11.0 (inherited from Phase 13) |
| Config file | none — `tests/bats/test_helper.bash` provides shared loader pinning `REPO_ROOT` |
| Quick run command | `bats tests/bats/runbook-*-static-*.bats -x` (sub-second; static file/cross-link contracts) |
| Full Phase 14 subset | `bats tests/bats/{demo,runbook}-*.bats` (live tests gated on `kubectl --context=k3d-spoke-capsule cluster-info` probe) |
| Full suite command | `bats tests/bats/ -r` (~10 minutes including Phase 7+8+9+10+11+13 regression gates) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| DEMO-01 | Platform-owner LIST tenants returns alpha+bravo+charlie; LIST ns returns all tenant ns; get pods -A succeeds | live | `bats tests/bats/demo-01-live-platform-owner-list.bats` | ❌ Wave 0 |
| DEMO-02 | Tenant-owner (both alpha + bravo) sees own tenant only via capsule-proxy:30443 | live | `bats tests/bats/demo-02-live-tenant-owner-scoped-list.bats` | ❌ Wave 0 |
| DEMO-03 | Tenant-owner can get+logs+exec hello-world in own ns; platform-owner can same across all ns | live | `bats tests/bats/demo-03-live-pod-ops.bats` | ❌ Wave 0 |
| DEMO-04 | Tenant-owner create-secret returns Forbidden verbatim "human-tenant-owner ... forbidden:" | live | `bats tests/bats/demo-04-live-tenant-secret-forbidden.bats` | ❌ Wave 0 |
| DEMO-05 | Tenant-owner cross-tenant access returns Forbidden (alpha→bravo + bravo→alpha) | live | `bats tests/bats/demo-05-live-cross-tenant-forbidden.bats` | ❌ Wave 0 |
| DEMO-06 | Platform-owner: get nodes -o yaml Forbidden + get csr Forbidden + create CRB Forbidden | live | `bats tests/bats/demo-06-live-platform-owner-cluster-admin-denials.bats` | ❌ Wave 0 |
| RUNBOOK-01 | `docs/poc-capsule-demo.md` exists with 6 ordered `## Act N` sections + frontmatter | static | `bats tests/bats/runbook-01-static-acts.bats` | ❌ Wave 0 |
| RUNBOOK-02 | Pre-demo checklist section exists with executable shell snippets (NOT narrative) | static | `bats tests/bats/runbook-02-static-checklist.bats` | ❌ Wave 0 |
| RUNBOOK-03 | Known-noise section exists post-act-6 + verbatim `tls: bad certificate` string + ADR-008 cross-link + `docs/capsule-on-eks.md` cross-link + three-tier-on-EKS mapping language | static | `bats tests/bats/runbook-03-static-tls-noise.bats` + `bats tests/bats/runbook-03-static-eks-three-tier.bats` | ❌ Wave 0 |
| RUNBOOK-04 | UAT executable ≤ 15 min cold by milestone owner; captured in `14-VALIDATION.md` | manual | UAT in `14-VALIDATION.md` (D-14-10) | manual-only |
| RUNBOOK-05 | New-tenant name `charlie` appears verbatim in `docs/poc-capsule-demo.md` act 3 + act 6 | static | `bats tests/bats/runbook-05-static-charlie.bats` | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** Static bats subset: `bats tests/bats/runbook-*-static-*.bats` (sub-second; doc structure + cross-link contracts)
- **Per wave merge:** Full Phase 14 bats: `bats tests/bats/{demo,runbook}-*.bats` (live tests gated on cluster probe)
- **Phase gate:** Full suite green before `/gsd-verify-work`: `bats tests/bats/ -r` (includes Phase 7+8+9+10+11+13 regression gates — DELIVERY-02 P31 isolation + RBAC-03 Flux SA preservation + SEED-02 ≤60s)
- **UAT (manual-only, RUNBOOK-04):** Milestone owner cold-reads `docs/poc-capsule-demo.md` against the live `spoke-capsule` cluster, stopwatched, single-pass under 15 minutes; result captured in `14-VALIDATION.md`

### Wave 0 Gaps

- [ ] `tests/bats/demo-01-live-platform-owner-list.bats` — covers DEMO-01 (Tier 2 LIST tenants + ns + pods-A)
- [ ] `tests/bats/demo-02-live-tenant-owner-scoped-list.bats` — covers DEMO-02 (Tier 3 scoped LIST, both alpha + bravo perspectives)
- [ ] `tests/bats/demo-03-live-pod-ops.bats` — covers DEMO-03 (logs + exec, both kubeconfigs, against hello-world nginx:alpine)
- [ ] `tests/bats/demo-04-live-tenant-secret-forbidden.bats` — covers DEMO-04 (verbatim "human-tenant-owner ... forbidden:" assertion)
- [ ] `tests/bats/demo-05-live-cross-tenant-forbidden.bats` — covers DEMO-05 (alpha→bravo + bravo→alpha symmetric rejection)
- [ ] `tests/bats/demo-06-live-platform-owner-cluster-admin-denials.bats` — covers DEMO-06 (3-action denial matrix)
- [ ] `tests/bats/runbook-01-static-acts.bats` — covers RUNBOOK-01 (file exists + 6 `## Act` sections + frontmatter)
- [ ] `tests/bats/runbook-02-static-checklist.bats` — covers RUNBOOK-02 (pre-demo checklist exists + has executable bash blocks)
- [ ] `tests/bats/runbook-03-static-tls-noise.bats` — covers RUNBOOK-03 part 1 (TLS noise appendix post-act-6 + verbatim string + ADR-008 cross-link)
- [ ] `tests/bats/runbook-03-static-eks-three-tier.bats` — covers RUNBOOK-03 part 2 (three-tier-on-EKS mapping in `docs/capsule-on-eks.md` + cross-link from demo runbook)
- [ ] `tests/bats/runbook-05-static-charlie.bats` — covers RUNBOOK-05 (literal `charlie` in act 3 + act 6 + `new-tenant.sh charlie` command in act 3)

*(Total: 11 new bats files anticipated; planner may consolidate `runbook-03-*` into a single file if cross-link assertions don't bloat. Manual UAT not file-counted.)*

**Existing inherited bats files (RE-RUN by Phase 14 verifier; NOT MODIFIED):**

- `tests/bats/poc-isolation-01-static.bats` — Phase 7 P31 contract regression
- `tests/bats/rbac-08-live-platform-owner-grant-matrix.bats` — Phase 13 RBAC-04 ceiling
- `tests/bats/rbac-09-live-platform-owner-kubeconfig.bats` — Phase 13 RBAC-06 co-owner LIST
- `tests/bats/rbac-10-live-tenant-crud.bats` — Phase 13 RBAC-05 Tenant CRUD
- `tests/bats/seed-03-live-fresh-tenant.bats` — Phase 13 SEED-02 ≤60s falsifier (verifies the SEED contract Phase 14 act 4 demonstrates)
- `tests/bats/negative-rbac-01-cross-tenant-list.bats` — Phase 11 cross-tenant LIST rejection (verifies the boundary Phase 14 act 5 demonstrates)

**Framework dependencies:** bats-core 1.11.0 already installed; no Wave 0 install.

---

## Security Domain

> `security_enforcement` defaults to enabled (no explicit `false` in config.json).

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|------------------|
| V2 Authentication | yes | Kubernetes TokenRequest API for both platform-owner SA + tenant-owner SAs; inherited from Phase 10 + Phase 13 |
| V3 Session Management | yes | TokenRequest JWT short-lived (`--duration 2h` for demo + bats; auto-expiry replaces persistent Secret); Pitfall 14-P1 documents the buffer |
| V4 Access Control | yes | Three-tier permission model — `capsule-platform-owner` ClusterRole (Tier 2 ceiling) + `tenant-workload-editor` ClusterRole (Tier 3 boundary) + Capsule-injected per-namespace RoleBindings — all already live from Phase 13 |
| V5 Input Validation | yes | `new-tenant.sh` name regex `^[a-z][a-z0-9-]{1,30}$` (D-13-08); `issue-*-kubeconfig.sh` RFC 1123 label regex on tenant/owner (Phase 10 WR-04); `--write-to` realpath canonicalization + tmpdir prefix check (BL-01) |
| V6 Cryptography | yes | TLS via chart-managed self-signed cert (Phase 10 Pitfall 10-P1; OQ-1 explicit DEFER per ADR-008); bearer JWT signed by apiserver — NEVER hand-roll |

### Known Threat Patterns for Phase 14 stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Bearer token leaks via demo session screen-recording | Information Disclosure | Pre-demo checklist mints to `/tmp/karyon-tenants/` (owner-private 0600, umask 0077, BL-02); P29 gitleaks rule active; runbook explicitly notes `/tmp` placement |
| Cluster-admin escalation via misuse of platform-owner kubeconfig | Elevation of Privilege | DEMO-06 verifies Tier 2 ceiling (CRB create denied verbatim); bats RED if ceiling regresses |
| Cross-tenant data leak via tenant-owner kubeconfig | Information Disclosure | DEMO-05 verifies cross-tenant LIST + Secret read denied (proxy LIST filter + apiserver RBAC) |
| Forbidden create-secret bypass | Tampering / EoP | DEMO-04 verifies tenant-workload-editor denies Secret create verbatim |
| TLS chatter mistaken for compromise during demo | Repudiation / Information Disclosure | RUNBOOK-03 "Known noise" appendix + Pitfall 14-P6 forward-pointer in act 1 |
| Stale `charlie` tenant carries old RoleBindings into re-run | Information Disclosure | Pre-demo checklist reset (D-14-03): `kubectl delete tenant charlie --ignore-not-found` + wait-for-delete on `tenant-charlie` ns (Pitfall 14-P3) |
| Symlink TOCTOU on `/tmp/karyon-tenants/` | Tampering | Phase 10 BL-01 already mitigates: realpath -m + prefix check + post-mkdir realpath -e re-verification; inherited by `issue-*-kubeconfig.sh` |
| YAML injection via `<tenant>` shell variable | Injection | Phase 13 D-13-08 regex (`^[a-z][a-z0-9-]{1,30}$`) on `charlie`; inherited |

---

## Code Examples

Verified patterns from this codebase (source-cited):

### Pattern: Live bats setup_file for two-perspective verification

```bash
# Source: tests/bats/rbac-09-live-platform-owner-kubeconfig.bats (lines 12-33)
# + tests/bats/negative-rbac-01-cross-tenant-list.bats (lines 23-44)
# Combined pattern for Phase 14 demo-*-live-*.bats:

load 'test_helper'

setup_file() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
  export KARYON_BATS_TMPDIR="${TMPDIR:-/tmp}/karyon-tenants/bats-${BATS_RUN_TMPDIR##*/}"
  mkdir -p "$KARYON_BATS_TMPDIR"

  bash "${REPO_ROOT}/scripts/poc/capsule/issue-platform-owner-kubeconfig.sh" \
    --duration=2h --write-to "${KARYON_BATS_TMPDIR}/po.kubeconfig" >/dev/null 2>&1
  export PO_KUBECONFIG="${KARYON_BATS_TMPDIR}/po.kubeconfig"

  bash "${REPO_ROOT}/scripts/poc/capsule/issue-tenant-kubeconfig.sh" alpha human-tenant-owner \
    --duration=2h --write-to "${KARYON_BATS_TMPDIR}/alpha.kubeconfig" >/dev/null 2>&1
  bash "${REPO_ROOT}/scripts/poc/capsule/issue-tenant-kubeconfig.sh" bravo human-tenant-owner \
    --duration=2h --write-to "${KARYON_BATS_TMPDIR}/bravo.kubeconfig" >/dev/null 2>&1
  export ALPHA_KUBECONFIG="${KARYON_BATS_TMPDIR}/alpha.kubeconfig"
  export BRAVO_KUBECONFIG="${KARYON_BATS_TMPDIR}/bravo.kubeconfig"
}

teardown_file() {
  rm -rf "$KARYON_BATS_TMPDIR"
}
```

### Pattern: Forbidden assertion with verbatim substring matching

```bash
# Source: tests/bats/negative-rbac-01-cross-tenant-list.bats line 53-56
# + this RESEARCH live-captured verbatim Forbidden strings

@test "DEMO-04: tenant-owner alpha cannot create secret" {
  run kubectl --kubeconfig="$ALPHA_KUBECONFIG" -n tenant-alpha \
    create secret generic demo-deny --from-literal=k=v
  [ "$status" -ne 0 ]
  echo "$output" | grep -qF "forbidden:"
  echo "$output" | grep -qF "human-tenant-owner"
}

@test "DEMO-06: platform-owner cannot create clusterrolebinding" {
  run kubectl --kubeconfig="$PO_KUBECONFIG" create clusterrolebinding \
    po-cluster-admin-attempt --clusterrole=cluster-admin --user=platform-owner
  [ "$status" -ne 0 ]
  echo "$output" | grep -qF "clusterrolebindings.rbac.authorization.k8s.io is forbidden"
  echo "$output" | grep -qF "system:serviceaccount:capsule-system:platform-owner"
}
```

### Pattern: SEED-02 ≤60s wait on fresh tenant (charlie variant)

```bash
# Source: tests/bats/seed-03-live-fresh-tenant.bats lines 63-67
# Adapted for charlie (NOT phase13-fresh) — RUNBOOK-01 act 4:

@test "RUNBOOK-01 act 4 / SEED-02: hello-world Ready in tenant-charlie within 60s" {
  # Precondition: act 3 has just run `new-tenant.sh charlie` (set up in setup_file or earlier @test)
  run kubectl --context=k3d-spoke-capsule wait pod/hello-world \
    --for=condition=Ready -n tenant-charlie --timeout=60s
  [ "$status" -eq 0 ]
}
```

### Pattern: Runbook frontmatter (matches `docs/poc-capsule.md` convention)

```yaml
# Source: docs/poc-capsule.md lines 1-6 (frontmatter format)
---
status: Active
audience: demo presenter + audience
purpose: 6-act Capsule POC demo walkthrough — three-tier permission model end-to-end.
scope: Phase 14 verification + demo runbook. Single canonical document; companion to docs/poc-capsule.md (operator runbook) and docs/capsule-on-eks.md (EKS translation).
---
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Hard-coded long-lived tenant tokens in Secrets | TokenRequest API (k8s ≥1.24) with `--duration` flag | Phase 10 D-10-01 | Auto-expiry; no Secret rotation; demo kubeconfigs are ephemeral |
| Single `capsule-platform-owners` Group impersonation | Dual-subject CRB (Group + SA) | Phase 13 D-13-06 | Two access paths: Group impersonation for ad-hoc kubectl + SA TokenRequest for scripted/UI access |
| `capsule-platform-owners` co-ownership as a Phase 14 task | Already in `spec.owners[]` on alpha + bravo (Phase 13) + auto-injected by `new-tenant.sh` template | Phase 13 D-13-08 | Phase 14 only verifies; does NOT mutate Tenant CRs |
| Pre-staged "demo tenant" left running for demo reuse | Live `new-tenant.sh charlie` cold per session | Phase 14 D-14-03 | Audience sees Capsule materialization moment; matches the "live demo" narrative |
| Separate operator runbook + demo runbook fragments | Single `docs/poc-capsule-demo.md` cross-linking `docs/poc-capsule.md` | Phase 14 D-14-04 | Single 15-min cold-read; operator runbook stays focused on host-restart recovery |

**Deprecated / not used in this phase:**

- `kubectl auth can-i` for cross-tenant LIST falsifiers — Pitfall P37 (SAR cache flake from Phase 11 D-11-05); replaced with real-CRUD probes
- Direct apiserver calls bypassing capsule-proxy for tenant-owner — proxy LIST filter is the load-bearing demo mechanic

---

## Risks & Open Questions

### Risks (planner should plan around these)

1. **UAT failure causes plan rework (RUNBOOK-04).** If milestone owner's cold-read exceeds 15 minutes, the runbook needs prose tightening. Mitigation: Wave 3 dedicated to UAT + tightening loop; budget headroom for 1-2 tightening iterations.
2. **Token expiry mid-UAT.** If UAT runs longer than `--duration 2h` (e.g., extended Q&A), tokens expire silently. Mitigation: pre-demo checklist uses `--duration 4h` for the UAT pass specifically OR include an explicit "re-mint if needed" step in checklist.
3. **TLS chatter rate-of-emission.** Verified at 1Hz on 2026-05-19, but capsule-controller chatter rhythm can change with controller restart cycles or apiserver health. "Known noise" appendix should describe behavior ranges ("1-2 lines per second"), not single-Hz exact.
4. **`charlie` tenant left over from prior demo runs blocking act 3.** Mitigated by pre-demo reset (D-14-03 + Pitfall 14-P3), but if operator skips the checklist, act 3 fails. Falsifier: pre-demo checklist itself is part of RUNBOOK-02 contract (executable, not narrative).
5. **Live cluster + Phase 13 GREEN is a hard prerequisite.** If Phase 13 carryover items resurface (e.g., capsule-proxy LIST filter regresses), every DEMO-* bats RED. Mitigation: Phase 14 verifier re-runs Phase 13 regression suite at phase-gate (already in Sampling Rate above).

### Open Questions (planner discretion)

1. **Should `demo-03-live-pod-ops.bats` cover BOTH platform-owner ops AND tenant-owner ops, or split into two files?** D-14-08 prefers per-REQ files. DEMO-03 covers both perspectives in the same REQ text. Recommendation: keep single file with two `@test`-groups (platform-owner + tenant-owner) — preserves REQ-ID traceability + halves boilerplate. Planner picks.
2. **Should the runbook append a 3rd tenant-owner kubeconfig (`TO_CHARLIE_KC`) to demonstrate charlie's tenant-owner perspective in act 5?** Not strictly required — alpha-owner + bravo-owner already prove the boundary; adding charlie-owner triples per-act time. Recommendation: NO — keep act 5 alpha/bravo only; mint charlie-owner kubeconfig in `bats demo-02-live-*.bats` only if planner wants a 3-tenant LIST filter falsifier.
3. **Should `runbook-03-static-eks-three-tier.bats` block on `docs/capsule-on-eks.md` actually having a "Tier 1 / Tier 2 / Tier 3" section, or just assert the cross-link from `docs/poc-capsule-demo.md` exists?** If Phase 14 does NOT append to `docs/capsule-on-eks.md`, the bats becomes a no-op on that file. Recommendation: append a 10-line subsection (Q1 above) AND assert in bats — keeps RUNBOOK-03 contract whole.
4. **Should the UAT be `KARYON_LIVE_TESTS=1`-gated?** Existing pattern (`require_live` in test_helper.bash) gates destructive live tests. UAT is non-destructive (read-only against `spoke-capsule` + ephemeral `charlie` lifecycle). Recommendation: NO gating — UAT runs against the same live cluster as other live bats.

### What I Couldn't Verify

- **Exact UAT stopwatch outcome.** This depends on the milestone owner's reading pace + cluster latency on the day. The RESEARCH provides a 250-350 line budget (Q9) as a planning anchor; the contract is empirical.
- **Whether `docs/capsule-on-eks.md` is committed under git or gitignored.** Verified via `ls` — file exists at `/home/rich/code/gsd/karyon/docs/capsule-on-eks.md`. Per Phase 7+11 history (Status: Reviewed), it's tracked.
- **Behavior under capsule-proxy chart upgrade.** Phase 14 assumes the current chart pin (0.12.0 per Phase 8). Any future chart bump might change the LIST filter shape; Phase 14 should NOT pre-engineer for this.

---

## Recommended Plan Decomposition

> Planner has final say. This is a recommended wave-by-wave shape based on the work surface.

### Wave 0 — RED bats scaffold (Plan 14-00)

**Goal:** All Phase 14 falsifier contracts lock in RED before any documentation lands. Mirrors Phase 13 D-13-15 Nyquist gate.

**Tasks:**

- Land 6 new `demo-*-live-*.bats` files (DEMO-01..06) with verbatim Forbidden assertions per this RESEARCH's Q6 captures.
- Land 4-5 new `runbook-*-static-*.bats` files (RUNBOOK-01..03, RUNBOOK-05) asserting file existence, section structure, cross-links, verbatim `charlie` references, verbatim `tls: bad certificate` strings.
- All bats files RED at commit (file `docs/poc-capsule-demo.md` does not exist yet → static bats fail; minted kubeconfigs target alpha/bravo (live), but DEMO-* bats fail because `charlie` is asserted in DEMO-02 LIST output and is not yet provisioned during bats setup).
- Update `14-VALIDATION.md` per Phase 13 pattern with all task→test mappings.

**Files:** ~11 new bats files; 1 VALIDATION.md edit.

### Wave 1 — `docs/poc-capsule-demo.md` runbook draft (Plan 14-01)

**Goal:** Single document, 6 ordered acts, executable pre-demo checklist, frontmatter per convention. RUNBOOK-01..02, RUNBOOK-05 bats GREEN.

**Tasks:**

- Write `docs/poc-capsule-demo.md` per the Q9 line-budget (250-350 lines).
- Use verbatim Forbidden strings from this RESEARCH (Q6) in `### Expected output` blocks.
- Cross-link `docs/poc-capsule.md` (operator runbook), `docs/capsule-on-eks.md` (EKS translation), `docs/adr/0008-capsule-multi-tenancy-graduation.md` (DEFER framing).
- Pre-demo checklist (Q7+Q8): cluster reachable probe + conditional `task fix-dns-poc-capsule` + 3 kubeconfig mints + charlie reset.

**Files:** 1 NEW (`docs/poc-capsule-demo.md`).

### Wave 2 — DEMO-01..06 live bats GREEN + TLS noise appendix + EKS three-tier append (Plan 14-02)

**Goal:** All DEMO-* bats GREEN against the live cluster (charlie provisioned in setup_file); TLS noise appendix written; `docs/capsule-on-eks.md` three-tier section appended; RUNBOOK-03 bats GREEN.

**Tasks:**

- DEMO-* live bats provision `charlie` in `setup_file` via `new-tenant.sh` (idempotent precondition mirroring `rbac-10-live-tenant-crud.bats`) → DEMO-01..06 GREEN.
- Append "Known noise" appendix to `docs/poc-capsule-demo.md` (post-act-6) with verbatim TLS string + ADR-008 cross-link.
- Append `## Three-tier permission model on EKS` subsection to `docs/capsule-on-eks.md` (~15 lines, Q1 above).
- RUNBOOK-03 bats GREEN.

**Files:** 1 MODIFY (`docs/poc-capsule-demo.md`); 1 MODIFY (`docs/capsule-on-eks.md`); 6 MODIFY (`demo-*-live-*.bats`, charlie setup added).

### Wave 3 — UAT cold-read + `14-VALIDATION.md` final (Plan 14-03)

**Goal:** Milestone owner cold-reads `docs/poc-capsule-demo.md` against live cluster, stopwatched. Pass = single-pass ≤ 15 min. RUNBOOK-04 satisfied.

**Tasks:**

- Run pre-demo checklist cold (verify all snippets executable as written).
- Execute acts 1-6 in order, stopwatched.
- Capture rough edges (typos, ambiguous prose, off-by-one expected outputs).
- If > 15 min: tighten prose + collapse expository sections + commit revisions; re-UAT.
- Final pass: write `14-VALIDATION.md` with stopwatched results, lessons, Phase 13 regression suite re-run confirmation.

**Files:** 0-N MODIFY (`docs/poc-capsule-demo.md` tightening); 1 NEW (`14-VALIDATION.md`).

### Optional Wave 4 — Code review + summary (only if discrepancies)

Mirrors Phase 13 Plan 13-04 verifier shape — runs Phase 13 regression suite, captures any deviations, finalizes Phase 14 disposition.

**Total recommended plans:** 3-4 (planner may merge Wave 2 into Wave 1 if writing the runbook + landing DEMO-* GREEN can happen in one commit chain — risk: doubles commit-blast-radius; reward: faster phase close).

---

## File Inventory

Every file Phase 14 will create or modify.

### NEW Files

| File | Owner Wave | Purpose |
|------|-----------|---------|
| `docs/poc-capsule-demo.md` | W1 | 6-act demo walkthrough (RUNBOOK-01..05); single canonical doc |
| `tests/bats/demo-01-live-platform-owner-list.bats` | W0 | DEMO-01 falsifier |
| `tests/bats/demo-02-live-tenant-owner-scoped-list.bats` | W0 | DEMO-02 falsifier (both alpha + bravo perspectives) |
| `tests/bats/demo-03-live-pod-ops.bats` | W0 | DEMO-03 falsifier (logs + exec, both kubeconfigs) |
| `tests/bats/demo-04-live-tenant-secret-forbidden.bats` | W0 | DEMO-04 falsifier (verbatim Forbidden assertion) |
| `tests/bats/demo-05-live-cross-tenant-forbidden.bats` | W0 | DEMO-05 falsifier (alpha↔bravo symmetric rejection) |
| `tests/bats/demo-06-live-platform-owner-cluster-admin-denials.bats` | W0 | DEMO-06 falsifier (3-action denial matrix) |
| `tests/bats/runbook-01-static-acts.bats` | W0 | RUNBOOK-01 static (6 act sections + frontmatter) |
| `tests/bats/runbook-02-static-checklist.bats` | W0 | RUNBOOK-02 static (executable pre-demo checklist) |
| `tests/bats/runbook-03-static-tls-noise.bats` | W0 | RUNBOOK-03 static part 1 (TLS noise appendix + ADR-008 cross-link) |
| `tests/bats/runbook-03-static-eks-three-tier.bats` | W0 | RUNBOOK-03 static part 2 (three-tier-on-EKS mapping + cross-link) |
| `tests/bats/runbook-05-static-charlie.bats` | W0 | RUNBOOK-05 static (charlie verbatim in acts 3 + 6) |
| `.planning/phases/14-.../14-VALIDATION.md` | W0 (frontmatter) → W3 (final) | Per-task verification map + UAT stopwatch result |
| `.planning/phases/14-.../14-{00..03}-PLAN.md` | per-wave | Standard plan docs |
| `.planning/phases/14-.../14-{00..03}-SUMMARY.md` | per-wave | Standard summary docs |
| `.planning/phases/14-.../14-VERIFICATION.md` | W3/W4 | Phase verifier output |

### MODIFY Files

| File | Owner Wave | Change |
|------|-----------|--------|
| `docs/capsule-on-eks.md` | W2 | Append `## Three-tier permission model on EKS` section (~15 lines); pure addition, no edits to existing content |
| `docs/poc-capsule-demo.md` | W2 | Append "Known noise" + "Forward pointers" appendices post-act-6 |
| `docs/poc-capsule-demo.md` | W3 (conditional) | Prose tightening if UAT > 15 min |
| `.planning/REQUIREMENTS.md` | W3 (close-out scope — Phase 15 actually flips checkboxes) | NOT modified by Phase 14 directly — Phase 15 closes the 11 `[ ]` checkboxes; Phase 14 generates the live evidence |
| `.planning/STATE.md` | each wave | `last_activity` advance; standard pattern |
| `.planning/ROADMAP.md` | W3 / W4 | Plan count + status update; standard pattern |

### NOT MODIFIED (regression-protected)

| File | Why Protected |
|------|--------------|
| `scripts/poc/capsule/new-tenant.sh` | Phase 13 D-13-08 contract; bats greps for literals; Phase 14 INVOKES it (`new-tenant.sh charlie`) but does not edit it |
| `scripts/poc/capsule/issue-platform-owner-kubeconfig.sh` | Phase 13 D-13-09 contract; bats greps for literals |
| `scripts/poc/capsule/issue-tenant-kubeconfig.sh` | Phase 10 D-10-01..06 contract; multiple bats grep for literals |
| `scripts/poc/capsule/fix-dns.sh` | Phase 7 contract; pre-demo checklist invokes via `task fix-dns-poc-capsule` |
| `Taskfile.yml` | P31 invariant — no new `spoke-capsule` mentions in v0.18 default-path; `task fix-dns-poc-capsule` already exists |
| `docs/poc-capsule.md` | Phase 7+10+13 cumulative content; demo runbook cross-links here, does NOT edit |
| `docs/adr/0008-capsule-multi-tenancy-graduation.md` | ADR-008 = DEFER stands; v0.20 introduces no new ADRs |
| Existing alpha + bravo Tenant CRs (`pocs/capsule/spoke/tenants/...`) | Additive-only invariant per Phase 13 DELIVERY-03; Phase 14 reads but does not write |
| `tests/bats/rbac-{08,09,10}-live-*.bats` | Phase 13 contracts; Phase 14 re-runs them as regression gates, NOT modified (D-14-08 preference for new `demo-*` files) |

### Counts

- **NEW:** 13 source files (1 doc + 11 bats + 1 VALIDATION.md) + 4 PLAN/SUMMARY pairs + 1 VERIFICATION.md = ~22 artifact creations
- **MODIFY:** 2 docs + STATE/ROADMAP per-wave (5-6 wave events)
- **NOT MODIFIED:** ~9 protected files (regression gates)

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `docs/capsule-on-eks.md` benefits from a small append for explicit Tier 1/2/3 labels (Q1) | Q1 + Architecture Patterns | LOW — purely additive; if the append is unnecessary (existing implicit mapping suffices), bats can assert via cross-link presence alone |
| A2 | UAT cold-read budget of 250-350 lines correlates to 15-min read time (Q9) | Q9 + Recommended Plan Decomposition | MEDIUM — empirical anchor from comparable runbooks; the actual UAT is the falsifier |
| A3 | Single `runbook-03-static-*.bats` file pair (TLS noise + EKS three-tier) is the right split granularity (Q9 → file inventory) | Validation Architecture | LOW — planner can consolidate or split |
| A4 | `charlie` tenant lifecycle (`new-tenant.sh charlie` + `delete tenant charlie`) is non-destructive to existing alpha/bravo Tenant CRs + Phase 13 SEED-02 ≤60s contract on `tenant-charlie` | Q5 + Risks | LOW — verified by Phase 13 D-13-13 + `new-tenant.sh` template literal inspection; SEED-02 contract already proven on `phase13-fresh` |

If this table is empty: all claims are verified or cited. **This table has 4 entries:** the Q1 EKS append decision (A1 is a documentation hypothesis — assumed beneficial), the line-budget heuristic (A2 — empirical), the bats split granularity (A3 — planner discretion), and the charlie lifecycle non-destructiveness (A4 — verified by inspection but worth flagging since cluster state mutation always carries lifecycle risk).

---

## Open Questions

1. **Should the runbook append an optional "7th-act" reference card?** Some demo runbooks have a final "Cheat sheet" appendix listing every command in order without prose. Could speed up the cold-read for already-familiar readers. Recommendation: NO unless UAT identifies it as needed — adds line count + dilutes the 6-act structure.
2. **Should Phase 14 land a `demo-04-live-charlie-*.bats` SEED falsifier specifically for `charlie`?** Phase 13's `seed-03-live-fresh-tenant.bats` already covers SEED-02 on `phase13-fresh`. Re-running on `charlie` doubles latency without adding signal. Recommendation: NO unless planner wants an extra positive control.
3. **Should the runbook include a Mermaid diagram in act 1?** Comparable runbooks (`docs/capsule-on-eks.md`) use Mermaid. Pro: easier to read three-tier model. Con: 30 more lines + Mermaid render fidelity is a Phase 7 HUMAN-UAT carryover. Recommendation: simple ASCII art diagram (this RESEARCH has one), inline in act 1 — easier to maintain, no render-fidelity dependency.

---

## Sources

### Primary (HIGH confidence — verbatim from this repo / live cluster)

- `.planning/REQUIREMENTS.md` §"DEMO" + §"RUNBOOK" (lines 60-79) — verbatim REQ text
- `.planning/ROADMAP.md` §"Phase 14" (lines 97-121) — phase goal + success criteria 1-5
- `.planning/phases/14-.../14-CONTEXT.md` — D-14-01..10 locked decisions
- `.planning/phases/13-rbac-narrowing-globaltenantresource-seed-delivery-mechanism/13-VALIDATION.md` — Phase 13 ledger; bats nomenclature pattern
- `.planning/phases/13-rbac-narrowing-globaltenantresource-seed-delivery-mechanism/13-RESEARCH.md` — Validation Architecture section template (lines 695-792)
- `scripts/poc/capsule/new-tenant.sh` — verbatim heredoc YAML rendering (lines 169-239); confirms `tenant-charlie` single namespace + owners list
- `scripts/poc/capsule/issue-platform-owner-kubeconfig.sh` — no-positional-args signature; CRB name `capsule-platform-owner`; context name `platform-owner-via-proxy`
- `scripts/poc/capsule/issue-tenant-kubeconfig.sh` — positional args `<tenant> <owner>`; `--write-to` tmpdir constraint; capsule-proxy NodePort 30443 server line
- `tests/bats/rbac-08-live-platform-owner-grant-matrix.bats` — Phase 13 platform-owner live RBAC pattern (positive grants + ceiling)
- `tests/bats/rbac-09-live-platform-owner-kubeconfig.bats` — LIST tenants + LIST namespaces + co-owner positive
- `tests/bats/rbac-10-live-tenant-crud.bats` — Tenant CRUD lifecycle pattern; idempotent precondition pattern
- `tests/bats/seed-03-live-fresh-tenant.bats` — ≤60s wait pattern for fresh tenant
- `tests/bats/negative-rbac-01-cross-tenant-list.bats` — cross-tenant rejection pattern + strict-skip env var
- `tests/bats/test_helper.bash` — `load 'test_helper'` convention + `REPO_ROOT` resolution
- `docs/poc-capsule.md` — operator runbook frontmatter convention + platform-owner H2 cross-link to Phase 14 demo runbook
- `docs/capsule-on-eks.md` — existing EKS doc; Required permissions table + Mermaid topology
- `docs/adr/0008-capsule-multi-tenancy-graduation.md` — DEFER framing target for TLS-noise cross-link
- `Taskfile.yml:44-47` — `task fix-dns-poc-capsule` entry verbatim
- **Live cluster probes (captured 2026-05-19):**
  - Verbatim TLS log line: `http: TLS handshake error from 10.42.0.1:39986: remote error: tls: bad certificate` (1Hz rhythm)
  - Verbatim Forbidden (ClusterRoleBinding): `error: failed to create clusterrolebinding: clusterrolebindings.rbac.authorization.k8s.io is forbidden: User "system:serviceaccount:capsule-system:platform-owner" cannot create resource "clusterrolebindings" in API group "rbac.authorization.k8s.io" at the cluster scope`
  - Verbatim Forbidden (Secret): `error: failed to create secret secrets is forbidden: User "system:serviceaccount:tenant-alpha:human-tenant-owner" cannot create resource "secrets" in API group "" in the namespace "tenant-alpha"`
  - hello-world Pod image: `docker.io/library/nginx:alpine`
  - `exec hello-world -- sh -c "echo ok-from-shell"` returns `ok-from-shell`
  - `logs hello-world --tail=3` returns nginx worker process lines
  - `get tenants` returns alpha + bravo Active reconciled 12d
  - `get ns` returns alpha-app1, bravo-app1, tenant-alpha, tenant-bravo
  - `get tenant charlie` returns NotFound (confirms clean precondition for D-14-03)
  - `new-tenant.sh charlie --dry-run` renders Tenant + Namespace `tenant-charlie` + SA

### Secondary (MEDIUM confidence)

- `docs/rebuild-runbook.md` (322 lines) — comparable runbook for line-budget anchor (Q9)
- `.planning/STATE.md` — milestone framing + Phase 13 carryover context

### Tertiary (LOW confidence)

- None — every Phase 14 claim was verifiable against the live cluster or in-repo files.

---

## Metadata

**Confidence breakdown:**

- Standard stack: HIGH — all primitives already present (bats-core, kubectl, jq, scripts, Taskfile entry)
- Architecture: HIGH — three-tier model already implemented + verified live (Phase 13 GREEN)
- Pitfalls: HIGH — 6 pitfalls derived from inspection of existing Phase 10/11/13 scripts + live probes
- Forbidden message strings: HIGH — verbatim live captures
- Runbook line-budget: MEDIUM-HIGH — empirical anchor from comparable runbooks; UAT is final falsifier
- EKS three-tier append (Q1): MEDIUM — recommendation based on doc inspection; planner discretion
- TLS noise rhythm: HIGH (verified live 1Hz) but appendix prose should hedge to "1-2 lines per second" for resilience

**Research date:** 2026-05-19
**Valid until:** 2026-06-18 (30 days for stable contract — capsule chart pins, k3s version, Phase 13 artifacts all unlikely to drift in v0.20 close window). Re-verify TLS log-line verbatim + Forbidden strings if Phase 14 work starts after this date.

---

## RESEARCH COMPLETE
