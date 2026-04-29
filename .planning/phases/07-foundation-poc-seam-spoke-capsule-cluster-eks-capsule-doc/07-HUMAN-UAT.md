---
status: partial
phase: 07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc
source: [.planning/phases/07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc/07-VERIFICATION.md]
started: 2026-04-29T15:30:00Z
updated: 2026-04-29T15:30:00Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. Live spoke-capsule cluster Ready=True (CAPCLU-01-live + CAPCLU-02-live / P18 falsifier)

expected: After raising `fs.inotify.max_user_instances` from 128 to 1024, `bash scripts/poc/capsule/create-cluster.sh` then `bash scripts/register-poc-cluster.sh spoke-capsule` complete successfully. `kubectl --context k3d-spoke-capsule get nodes` lists `k3d-spoke-capsule-server-0` in `Ready` state. The hub-side outer Kustomization at `clusters/hub-flux/pocs/capsule.yaml` reaches `Ready=True` and `flux get kustomization poc-capsule -n flux-system --context k3d-hub-flux` shows reconciliation against spoke-capsule (NOT hub-flux) — `verify_credential_layer()`'s P18 silent-misroute falsifier confirms `/api/v1/nodes` lists `k3d-spoke-capsule-server-0` AND NOT `k3d-hub-flux-server-0`.

result: [pending]

To run:
```bash
sudo sysctl -w fs.inotify.max_user_instances=1024
bash scripts/poc/capsule/create-cluster.sh
bash scripts/register-poc-cluster.sh spoke-capsule
kubectl --context k3d-spoke-capsule get nodes
flux get kustomization poc-capsule -n flux-system --context k3d-hub-flux
```

To make the inotify limit persist across reboots, add to `/etc/sysctl.d/99-karyon-poc.conf`:
```
fs.inotify.max_user_instances = 1024
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

total: 4
passed: 0
issues: 0
pending: 4
skipped: 0
blocked: 0

## Gaps

(None — all gaps surfaced as human verification items above.)
