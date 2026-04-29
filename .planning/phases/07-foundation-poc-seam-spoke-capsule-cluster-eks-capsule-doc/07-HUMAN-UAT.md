---
status: partial
phase: 07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc
source: [.planning/phases/07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc/07-VERIFICATION.md]
started: 2026-04-29T15:30:00Z
updated: 2026-04-29T16:30:00Z
---

## Current Test

[awaiting human testing — items 2/3/4 below; item 1 split into 1a (resolved) + 1b (deferred to Phase 8)]

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

### 1b. Hub Flux observable reconcile of `poc-capsule` Kustomization (DEFERRED to Phase 8)

expected: `flux get kustomization poc-capsule -n flux-system --context k3d-hub-flux` returns `Ready=True` with `Applied revision: main@<sha>` for the post-Phase-7 commit.

result: **deferred** — observable only after origin/main is updated past `1f2da1d3`. Current state: registration script edited the FLUX PATCH SURFACE locally and committed (`5bc8cb0`); origin/main has NOT been pushed because Phase 11 graduation owns first-push. The Phase 8 acceptance criteria (CAP-01 / CAP-02 — Capsule operator + capsule-proxy HelmReleases reconciled into spoke-capsule with `Ready=True`) implicitly require this — Phase 8 cannot pass without Flux successfully reconciling through `pocs/capsule.yaml` into spoke-capsule. **This is the natural integration test for the seam.**

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

result: [pending]

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

result: [pending]

To run:
- Push the branch to GitHub
- Open `docs/capsule-on-eks.md` in the GitHub web UI
- Verify the Mermaid block renders graphically with all expected nodes and arrows

---

### 4. EKS doc reads naturally for a Mixed Eng + Cloud Ops team presentation (EKSDOC-01 / D-01)

expected: Milestone owner can walk a team through `docs/capsule-on-eks.md` in 10–15 minutes. Section (a) "what Capsule is" lands in one paragraph for non-experts. Section (b) (CRDs) names all 7 without overwhelming. Section (c) (RBAC) signals the admin-required steps clearly. Section (d) (rough EKS install path) leads with the high-level walkthrough then drops into IRSA + LB/ALB + VPC nodeSelector verbatim YAML for Cloud Ops. Section (e) (NOT proved — HA Capsule, OIDC, multi-spoke federation) sets the scope honestly without scaring the audience.

result: [pending]

To run:
- Read the doc end-to-end as if presenting to a Mixed Eng + Cloud Ops team
- Confirm the high-level walkthrough orients Cloud Ops first
- Confirm the verbatim YAML blocks are lift-ready (Terraform / EKS module / kubectl apply)
- Confirm the NOT-PROVED 3-item list aligns with the eventual ADR-008 graduation vocabulary

---

## Summary

total: 5
passed: 1
issues: 0
pending: 3
deferred: 1
skipped: 0
blocked: 0

## Gaps

(None — all gaps surfaced as human verification items above.)

## Carryover

- **1b** (hub Flux observable reconcile of `poc-capsule`) — DEFERRED to Phase 8, tracked via `.planning/todos/pending/<date>-phase-7-hub-flux-observable-reconcile.md` with `resolves_phase: 8` so it surfaces in `/gsd-progress` until Phase 8 completes.
- **Repo-wide gitleaks fixture-quote rule** (planning docs trip `kubeconfig-bearer-token` rule) — DEFERRED for first-push remediation, tracked via `.planning/todos/pending/<date>-phase-7-gitleaks-planning-doc-allowlist.md` with `resolves_phase: 11` (Phase 11 owns the one-shot history scan + first-push CI verification per VAL-05).
