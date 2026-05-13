---
created: 2026-04-29T16:30:00Z
title: Phase 7 carryover — hub Flux observable reconcile of poc-capsule Kustomization
area: flux/poc-seam
resolves_phase: 8
files:
  - clusters/hub-flux/pocs/capsule.yaml
  - clusters/hub-flux/flux-system/kustomization.yaml
source: .planning/phases/07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc/07-HUMAN-UAT.md#1b
---

## Problem

Phase 7 verification item 1 was split into 1a (resolved) + 1b (deferred). 1b — the hub-Flux-observable reconcile of `poc-capsule` Kustomization Ready=True — could not be observed during Phase 7 because Flux on hub-flux is reconciling from `origin/main@1f2da1d3` (v0.18 close-out state) and the post-Phase-7 commits including the `# KARYON POC MOUNT` + `- ../pocs` patch are NOT pushed to origin yet.

The script-internal P18 silent-misroute falsifier in `register-poc-cluster.sh` step 4 PASSED on user's first run (verified 2026-04-29: `auth roundtrip ok` + `node-name proof ok: spoke-capsule routes to k3d-spoke-capsule-server-0 (k3d-hub-flux-server-0 absent)`). That's a STRONGER guarantee than `flux get kustomization poc-capsule Ready=True` because it directly proves the hub-side credential routes the apiserver call to the spoke (not silently to hub-flux). What's missing is observation of the seam through the Flux runtime path, not through the script-internal direct-apiserver path.

Phase 8 (Capsule + capsule-proxy bare-minimum install) requires this naturally: CAP-01 / CAP-02 cannot reach `Ready=True` unless hub Flux successfully reconciles through `clusters/hub-flux/pocs/capsule.yaml` into spoke-capsule and applies the HelmReleases. If Phase 8's verifier observes the outer `poc-capsule` Kustomization NOT ready, that's a Phase 7 SEAM defect — gap-close back to Phase 7 with `/gsd-plan-phase 7 --gaps`.

## Solution

Phase 8 verifier MUST add this as an explicit acceptance criterion (alongside CAP-01/02 HelmRelease readiness):

1. Confirm origin/main has been updated past `1f2da1d3` (`git log origin/main..main` is empty before Phase 8 verification runs) — OR mint a local-only test path if first-push is intentionally gated until Phase 11.
2. After `flux reconcile source git flux-system --context k3d-hub-flux` (forced sync), confirm:
   - `flux get sources git flux-system -n flux-system --context k3d-hub-flux` reports a revision past `1f2da1d3`
   - `flux get kustomization poc-capsule -n flux-system --context k3d-hub-flux` reports `Ready=True` with `Applied revision: main@<post-Phase-7-sha>`
   - `flux get helmrelease capsule -n capsule-system --context k3d-spoke-capsule` reports `Ready=True` (transitive proof via CAP-01)
3. If any of (a)/(b)/(c) fail, treat as Phase 7 seam defect (NOT Phase 8 install defect) and gap-close back to Phase 7.

This todo will auto-close when `/gsd-execute-phase 8` completes (per `resolves_phase: 8` and execute-phase.md's `close_phase_todos` step).

## Cross-references

- Phase 7 split rationale: `.planning/phases/07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc/07-HUMAN-UAT.md` §1b
- P18 script-internal falsifier (resolves 1a): `scripts/register-poc-cluster.sh` `verify_credential_layer()` function
- Phase 8 plan when written: should include this acceptance criterion in CAP-01 / CAP-02 must_haves

---

## 2026-04-29 status update — fragile pass, NOT resolved

The Phase 8 verifier (`08-VERIFICATION.md`, untracked) ran 2026-04-29T20:50:00Z and recorded truth #7 ("FOLDED CARRYOVER — outer `poc-capsule` Kustomization on hub-flux reports `Ready=True` against a post-Phase-7 source revision") as **VERIFIED** at `Applied revision: main@sha1:32e0b2fa`.

However, the verifier also flagged this as a *masked* pass: outer Kustomization is reconciling against pre-Phase-8 source where `pocs/capsule/kustomization.yaml: resources: []` produces zero objects to apply (`inventory.entries: []`). The masking will lift the moment Phase 8 push lands, surfacing Phase 8 Gap G-04 — outer Kustomization will go `Ready=False` because spoke-capsule has no Flux CRDs to receive the HelmRelease/OCIRepository CRs being applied to it via `spec.kubeConfig: spoke-capsule-kubeconfig`.

**Disposition:** Todo stays `pending` (resolves_phase: 8). It will auto-close only when Phase 8 verifier reports `passed` after G-03 + G-04 gap fixes land. The current "fragile pass" does not meet the close-out bar.

---

## 2026-05-11 closure (Phase 12 v0.19 close-out reconciliation)

**Resolved.** The auto-close target was Phase 8 (run 2026-04-30) which observed `poc-capsule` outer Kustomization Ready=True only with masked empty inventory (see existing "2026-04-29 status update — fragile pass, NOT resolved" section above). The masking was lifted by Plan 11-06 (G-04 capsule-system Namespace on hub + PostBuild patch relocated from Kustomization `spec.patches` to HelmRelease `spec.postRenderers`) and Plan 11-07 (spoke-side `capsule-system` Namespace + `helm-controller` SA + flux-reconciler impersonation correction + new `poc-capsule-spoke-rbac` top-level Flux Kustomization). At HEAD `8415ab66`, per `11-07-SUMMARY.md`:

- `poc-capsule`, `poc-capsule-spoke`, `poc-capsule-spoke-rbac`, `poc-capsule-spoke-tenants` all Ready=True
- `capsule` and `capsule-proxy` HelmReleases Ready=True
- `curl -sk https://127.0.0.1:30443/healthz` returns HTTP 200
- CI passed for pushed HEAD `8415ab6655faba324ee1809fdb22b08380f42a38`

This is the **observable post-push hub-Flux reconcile of `poc-capsule`** that Phase 7's 1b deferred verification was waiting for. Todo closed manually as part of Phase 12 close-out reconciliation (auto-close target Phase 8 completed 2026-04-30 with the fragile-pass override that 11-06 + 11-07 subsequently lifted).

Cross-references:
- `.planning/phases/11-validation-graduation-adr-008/11-07-SUMMARY.md` — canonical post-fix evidence
- `.planning/phases/11-validation-graduation-adr-008/11-07-G06-DIAGNOSTICS.md` — empirical pre/post-fix evidence for G-06
