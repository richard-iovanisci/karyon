---
status: complete
phase: 07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc
source: [.planning/phases/07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc/07-VERIFICATION.md]
started: 2026-04-29T15:30:00Z
updated: 2026-05-13T21:00:00Z
auto_verification: 2026-04-29T19:45:00Z (--auto pre-flight)
human_verification: 2026-05-13 (milestone owner, pre-v0.19 close)
---

## Current Test

[testing complete — all 5 scenarios resolved 2026-05-13: 1a passed 2026-04-29; 1b resolved via live `flux get kustomization poc-capsule` Ready=True at main@8415ab66; 2 passed via `task fix-dns-poc-capsule` recovery (4 internal checks + post-settle DNS resolution); 3 passed via GitHub Web UI Mermaid render (screenshot captured); 4 passed via milestone-owner end-to-end read-through.]

## Tests

### 1a. Live spoke-capsule cluster Ready + script-internal P18 falsifier (CAPCLU-01-live + CAPCLU-02-live partial)

expected: After raising `fs.inotify.max_user_instances` from 128 to 1024, `bash scripts/poc/capsule/create-cluster.sh` then `bash scripts/register-poc-cluster.sh spoke-capsule` complete successfully. `kubectl --context k3d-spoke-capsule get nodes` lists `k3d-spoke-capsule-server-0` in `Ready` state. `register-poc-cluster.sh`'s in-script `verify_credential_layer()` P18 silent-misroute falsifier passes (`auth roundtrip ok` + `node-name proof ok: spoke-capsule routes to k3d-spoke-capsule-server-0 (k3d-hub-flux-server-0 absent)`).

result: **passed** — verified 2026-04-29 by user. `register-poc-cluster.sh` summary reported `9 passed, 0 warnings, 0 failed`. The script-internal P18 falsifier is a STRONGER guarantee than `flux get kustomization Ready=True` because it directly proves the hub-side credential routes the apiserver call to the spoke (not silently to hub-flux).

To run (already executed, reproduction reference only):
```bash
sudo sysctl -w fs.inotify.max_user_instances=1024
bash scripts/poc/capsule/create-cluster.sh
bash scripts/register-poc-cluster.sh spoke-capsule  # P18 falsifier in step 4
kubectl --context k3d-spoke-capsule get nodes
```

To make the inotify limit persist across reboots, add to `/etc/sysctl.d/99-karyon-poc.conf`:
```
fs.inotify.max_user_instances = 1024
```

---

### 1b. Hub Flux observable reconcile of `poc-capsule` Kustomization (RESOLVED 2026-05-13)

expected: `flux get kustomization poc-capsule -n flux-system --context k3d-hub-flux` returns `Ready=True` with `Applied revision: main@<sha>` for the post-Phase-7 commit.

result: **passed** — verified 2026-05-13 by user via live `flux get kustomization`. Output:
```
NAME            REVISION                SUSPENDED       READY   MESSAGE
poc-capsule     main@sha1:8415ab66      False           True    Applied revision: main@sha1:8415ab66
```
Phase 11 / Plan 11-07 closed G-04 + G-06 (split-Kustomization architecture; all 4 outer Flux Kustomizations Ready=True at HEAD 8415ab66 per `11-07-SUMMARY.md`). Phase 12 / Plan 12-05 moved the carryover tracking todo pending → completed with 2026-05-11 closure block.

Phase 8 must:
- Confirm origin/main has been updated and Flux's `flux-system` GitRepository has `Ready=True` at a revision past `1f2da1d3` (or mint a local-only test path if first-push remains gated)
- Confirm the outer `poc-capsule` Kustomization reaches `Ready=True`
- Confirm CAP-01/CAP-02 HelmReleases reach `Ready=True` on spoke-capsule

If Phase 8 verifier observes any of those failing, that's a Phase 7 SEAM defect (not a Phase 8 install defect) and gap-closes back here.

Tracking todo: `.planning/todos/pending/<date>-phase-7-hub-flux-observable-reconcile.md` (resolves_phase: 8 — auto-closes when Phase 8 completes)

To check after origin push:
```bash
flux reconcile source git flux-system --context k3d-hub-flux
flux get kustomization poc-capsule -n flux-system --context k3d-hub-flux
```

---

### 2. `task fix-dns-poc-capsule` recovers from real Docker/WSL restart (CAPCLU-03)

expected: After a Docker daemon or WSL restart that leaves spoke-capsule in a degraded CoreDNS state (stale NodeHosts entries), running `task fix-dns-poc-capsule` recovers spoke-capsule via `k3d cluster stop spoke-capsule && k3d cluster start spoke-capsule` without affecting `task rebuild` (v0.18 SLO < 230s) or the existing `task fix-dns` (which targets hub-flux only).

result: **passed** — verified 2026-05-13 by user. `task fix-dns-poc-capsule` ran end-to-end: `4 passed, 0 warnings, 0 failed` (tool gate + stop + start + node readiness). Post-recovery state: `kubectl get nodes` shows `k3d-spoke-capsule-server-0  Ready  control-plane  14d  v1.34.6+k3s1`. DNS resolution validated via `nslookup kubernetes.default.svc.cluster.local` → `10.43.0.1` after a ~30s CoreDNS settle window; CoreDNS Corefile retains the `kubernetes cluster.local in-addr.arpa ip6.arpa` zone block after stop/start; `kubernetes` service intact at ClusterIP `10.43.0.1`.

**Methodology note (2026-05-13):** the original test wording (`nslookup kubernetes.default`) intermittently NXDOMAIN'd immediately after the k3d stop/start cycle — this is a busybox-search-domain + CoreDNS-settle-time quirk, not a script defect. Recommended canonical incantation on future runs: `sleep 30; kubectl run --rm -it dns-test --image=busybox:1.36 --restart=Never -- nslookup kubernetes.default.svc.cluster.local` (FQDN + pinned busybox + settle window).

auto-verification (2026-04-29):
- ✓ `Taskfile.yml:44-47` defines `fix-dns-poc-capsule` as a sibling-not-parent of `fix-dns` (line 39). Both are top-level entries; no env-var dispatch (D-16 anti-pattern avoided).
- ✓ `scripts/poc/capsule/fix-dns.sh` (75 lines) targets only `POC_CLUSTER="spoke-capsule"` (readonly). Zero hub-flux or `flux check` invocations against spoke-capsule (D-17 / ADR-004 — verified by grep against the script body; the 5 hub-flux/flux-check string matches are all design-rule comments documenting their absence).
- ✓ `scripts/fix-coredns.sh` (default `task fix-dns` target) has zero references to `fix-dns-poc-capsule` or `scripts/poc/capsule/fix-dns.sh`. The two scripts share no surface (D-12 / P31 isolation).
- ✓ Cluster currently healthy: `k3d cluster list` shows `spoke-capsule 1/1` running.
- ⚠ HUMAN-required: cannot simulate "real Docker daemon or WSL restart causing degraded CoreDNS NodeHosts staleness" — that's the actual recovery scenario the test is asking for. Auto-pre-flight only validates the recovery mechanism is in place and isolated correctly. Definitive pass requires user to observe the failure mode after a real restart, then confirm `task fix-dns-poc-capsule` resolves it.

To run:
```bash
# After Docker / WSL restart, observe CoreDNS staleness:
kubectl --context k3d-spoke-capsule get pods -n kube-system | grep coredns
kubectl --context k3d-spoke-capsule logs -n kube-system -l k8s-app=kube-dns | tail -20

# Recover:
task fix-dns-poc-capsule

# Verify recovery:
kubectl --context k3d-spoke-capsule get nodes
kubectl --context k3d-spoke-capsule run --rm -i --tty dns-test --image=busybox --restart=Never -- nslookup kubernetes.default
```

---

### 3. Mermaid topology renders correctly in `docs/capsule-on-eks.md` (EKSDOC-01 / D-03)

expected: Pushing the branch to GitHub and viewing `docs/capsule-on-eks.md` in the GitHub web UI renders the Mermaid topology block as a graphical diagram (NOT raw markdown). The diagram should match the `.planning/research/SUMMARY.md` ASCII topology source-of-truth: hub-flux outer reconcile arrows to spoke-capsule, NodePort 30443 publish, "Tenants on spoke-capsule, hub-controlled" callout, "no Flux on spoke-capsule" caption.

result: **passed** — verified 2026-05-13 by user via GitHub Web UI render (screenshot captured). All declared EKS-target nodes visible and legible: AWS Region + EKS Cluster + capsule-system namespace boundaries, capsule-controller-manager (HelmRelease, OCIRepository=ECR), capsule-proxy (HelmRelease, NLB OR ALB Service, Ingress), alpha-app1 + bravo-app1 tenant namespaces with IRSA-bound `gitops-reconciler` SAs, IAM TrustPolicy per tenant SA, ECR (capsule + capsule-proxy charts) in `Outside cluster`, Git-gated OCIRepository pipeline, NLB/ALB → `https://capsule-proxy.<your-domain>:443` → tenant kubectl edge.

**Note on test wording (per 2026-04-29 auto-pre-flight finding):** the test's original "should match" criteria referenced k3d source-of-truth elements (hub-flux outer reconcile arrows, NodePort 30443, "no Flux on spoke-capsule" caption) that intentionally do NOT belong in the EKS-target diagram. The artifact is correct against its declared purpose (EKS-target adaptation) and was evaluated against EKS-target criteria, not the k3d source-of-truth. No code defect; UAT wording could optionally be rewritten on a future pass to use EKS-target language.

auto-verification (2026-04-29):
- ✓ Mermaid block exists at `docs/capsule-on-eks.md:46-79` (33 lines including fences). Header comment block declares it the "EKS-target topology — AWS-flavored equivalents of the karyon k3d POC".
- ✓ Mermaid syntax structurally valid: `flowchart TB` directive; subgraphs (`aws`, `eks`, `capSys`, `tnsAlpha`, `tnsBravo`, `aws2`) properly opened/closed with quoted labels; node IDs (`op`, `px`, `appA`, `appB`, `ecr`, `nlb`, `iam`, `git`, `client`) all defined before edge use; edge syntaxes valid (`==>`, `-.->`, `-->|"..."|`); `<br/>` and `&lt;` HTML entities escaped correctly.
- ✓ Diagram contains the expected EKS-target elements: capsule-controller-manager + capsule-proxy in `capsule-system`, two tenant namespaces (alpha-app1, bravo-app1) with IRSA-bound `gitops-reconciler` SAs, ECR-hosted Helm charts, NLB/ALB fronting capsule-proxy, IAM TrustPolicy arrows.
- ⚠ **Test-wording mismatch surfaced**: the test's "should match" criteria reference k3d-specific elements (`hub-flux outer reconcile arrows to spoke-capsule`, `NodePort 30443`, `"no Flux on spoke-capsule" caption`) that intentionally DO NOT belong in the EKS-target diagram (the doc explicitly translates them: hub-flux → Git → ECR pipeline; :30443 NodePort → :443 NLB/ALB; no separate Flux hub since EKS uses single-cluster Flux). The artifact is correct against its declared purpose; the test wording was authored against the k3d source-of-truth, not the EKS adaptation.
- ⚠ HUMAN-required: cannot push to GitHub (first-push gated until Phase 11 per VAL-05) or render Mermaid in browser. Definitive pass requires GitHub Web UI render once first-push is unblocked. Recommendation: when re-running this test, evaluate against the EKS-target topology criteria (Capsule operator + capsule-proxy + 2 tenant ns + ECR + IRSA + NLB/ALB nodes; chart-pipeline arrows; tenant kubectl edge), not the k3d source-of-truth.

To run:
- Push the branch to GitHub
- Open `docs/capsule-on-eks.md` in the GitHub web UI
- Verify the Mermaid block renders graphically with all expected nodes and arrows

---

### 4. EKS doc reads naturally for a Mixed Eng + Cloud Ops team presentation (EKSDOC-01 / D-01)

expected: Milestone owner can walk a team through `docs/capsule-on-eks.md` in 10–15 minutes. Section (a) "what Capsule is" lands in one paragraph for non-experts. Section (b) (CRDs) names all 7 without overwhelming. Section (c) (RBAC) signals the admin-required steps clearly. Section (d) (rough EKS install path) leads with the high-level walkthrough then drops into IRSA + LB/ALB + VPC nodeSelector verbatim YAML for Cloud Ops. Section (e) (NOT proved — HA Capsule, OIDC, multi-spoke federation) sets the scope honestly without scaring the audience.

result: **passed** — verified 2026-05-13 by user (milestone owner end-to-end read-through). All 5 sections (a-e) confirmed naturally readable for a Mixed Engineering + Cloud Ops audience; structural elements verified by 2026-04-29 auto-pre-flight remain intact at HEAD.

auto-verification (2026-04-29):
- ✓ Section (a) `## What Capsule is` (line 14) — single paragraph, ~70 words, links to capsule.clastix.io.
- ✓ Section (b) `## Required CRDs (the 7)` (line 18) — table names all 7 CRDs (Tenant, CapsuleConfiguration, GlobalTenantResource, TenantResource, ResourcePool, ResourcePoolClaim, TenantOwner) with POC scope per row.
- ✓ Section (c) `## Required permissions / RBAC` (line 32) — table of 3 subjects (Capsule operator SA, capsule-proxy SA, per-tenant SA) plus explicit "**Admin-required step:**" callout (line 40) on cluster-wide CRD install ordering.
- ✓ Section (d) `## Rough EKS install path` (line 81) — leads with `### High-level walkthrough (Cloud Ops orientation)` (line 83, 7-step numbered list) before dropping into 3 verbatim YAML blocks (line 105 IRSA TrustPolicy JSON+YAML, line 139 NLB Service + ALB Ingress YAML, line 192 CapsuleConfiguration `allowedNodeSelectors` YAML). Sub-section `### Not yet wired in the k3d POC (EKS deltas)` (line 95) preserves audience honesty about what EKS-only setup is required.
- ✓ Section (e) `## What this POC does NOT prove` (line 213) — exactly 3 numbered items: HA Capsule, OIDC tenant authentication, Multi-spoke federation. Closing line (221) anchors them to ADR-008 graduation vocabulary: "These three items mirror the eventual ADR-008 graduation framing so the EKS-target audience and the karyon graduation ADR speak the same vocabulary."
- ✓ Frontmatter declares `audience: Mixed Engineering + Cloud Ops` and `status-rollover: Phase 11 graduation ADR-008` — Cloud Ops orientation contract is explicit.
- ⚠ HUMAN-required: cannot judge "reads naturally" / "10-15 minute walk", "lands in one paragraph for non-experts", "signals admin-required steps clearly", "lift-ready for Cloud Ops", "without overwhelming", "without scaring the audience". These are presentation-fitness judgments that need the milestone owner to read end-to-end as if presenting.

To run:
- Read the doc end-to-end as if presenting to a Mixed Eng + Cloud Ops team
- Confirm the high-level walkthrough orients Cloud Ops first
- Confirm the verbatim YAML blocks are lift-ready (Terraform / EKS module / kubectl apply)
- Confirm the NOT-PROVED 3-item list aligns with the eventual ADR-008 graduation vocabulary

---

## Summary

total: 5
passed: 5 (1a 2026-04-29; 1b/2/3/4 2026-05-13)
issues: 0
pending: 0
deferred: 0
skipped: 0
blocked: 0

## Auto-Verification Findings (2026-04-29 — `/gsd-verify-work 7 --auto`)

- **Test 2** — Recovery mechanism + isolation rules verified structurally; cluster currently healthy. Cannot simulate Docker/WSL restart degradation. **Awaits real-world failure-mode observation.**
- **Test 3** — Mermaid block exists with valid syntax; topology correctly represents the EKS-target adaptation per its own header. **Awaits GitHub Web UI render** (gated behind first-push deferred to Phase 11). **NEW FINDING:** test wording was authored against k3d source-of-truth language (`hub-flux outer reconcile arrows to spoke-capsule`, `NodePort 30443`, `"no Flux on spoke-capsule" caption`) but the artifact intentionally translates these to EKS-target equivalents. Recommend re-evaluating Test 3 against EKS-target criteria when first-push unblocks. NOT a code defect.
- **Test 4** — All 5 required sections (a-e) present with required structural elements (7-CRD table, RBAC subjects, 7-step walkthrough, 3 verbatim YAML blocks, 3-item NOT-PROVED list anchored to ADR-008 vocabulary). **Awaits human readability + presentation-fitness judgment** (10-15 minute walkthrough trial).

## Gaps

(None — all gaps surfaced as human verification items above. Auto-pre-flight surfaced ONE test-wording-vs-artifact alignment issue on Test 3, recorded above as "NEW FINDING"; not promoted to a Gap because the artifact is correct against its declared purpose. The Test 3 expected text could optionally be revised on the user's next pass through this UAT.)

## Carryover

- **1b** (hub Flux observable reconcile of `poc-capsule`) — DEFERRED to Phase 8, tracked via `.planning/todos/pending/<date>-phase-7-hub-flux-observable-reconcile.md` with `resolves_phase: 8` so it surfaces in `/gsd-progress` until Phase 8 completes.
- **Repo-wide gitleaks fixture-quote rule** (planning docs trip `kubeconfig-bearer-token` rule) — DEFERRED for first-push remediation, tracked via `.planning/todos/pending/<date>-phase-7-gitleaks-planning-doc-allowlist.md` with `resolves_phase: 11` (Phase 11 owns the one-shot history scan + first-push CI verification per VAL-05).
