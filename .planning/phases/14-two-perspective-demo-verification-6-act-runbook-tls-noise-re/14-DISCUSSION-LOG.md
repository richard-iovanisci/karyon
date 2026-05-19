# Phase 14: Two-Perspective Demo Verification + 6-Act Runbook + TLS-Noise Resolution - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-19
**Phase:** 14-Two-Perspective-Demo-Verification-6-Act-Runbook-TLS-Noise-Resolution
**Mode:** `--auto` (no interactive prompts; Claude auto-selected the recommended option for every gray area)
**Areas discussed:** OQ-1 TLS noise treatment, OQ-5a new-tenant marquee name, OQ-5b provision style, runbook document structure, pre-demo checklist style, DEMO-06 Forbidden showcase selection, two-perspective verification strategy, capsule-proxy routing, UAT method

---

## OQ-1 — TLS Noise Treatment (RUNBOOK-03)

| Option | Description | Selected |
|--------|-------------|----------|
| Document-only | Note the `tls: bad certificate` 1Hz chatter as known noise in the runbook; cross-link ADR-008; no code changes | ✓ (recommended default per PROJECT.md / REQUIREMENTS.md RUNBOOK-03) |
| Fix as part of R4 | Wire cert-manager / proper CA distribution to silence controller chatter | |
| Defer entirely | No mention in runbook, no docs change | |

**Auto-selected:** Document-only.
**Notes:** Matches the milestone briefing's recommended default. The chatter is cosmetic — does not affect tenant boundary enforcement or `GlobalTenantResource` propagation. Fixing it pulls in cert-manager work that the lean v0.20 milestone is explicitly scope-guarded against. ADR-008 = DEFER framing anchors this. Captured as D-14-01.

---

## OQ-5a — New-Tenant Marquee Name (RUNBOOK-05)

| Option | Description | Selected |
|--------|-------------|----------|
| `charlie` | Continues alpha → bravo → charlie phonetic alphabet pattern; already cited as example in `new-tenant.sh` head comment | ✓ (recommended — phonetic continuity + memorability) |
| `demo` | Generic, self-explanatory | |
| `team-foo` | Reads like a placeholder, less memorable | |

**Auto-selected:** `charlie`.
**Notes:** Single-word, regex-clean (`^[a-z][a-z0-9-]{1,30}$`), continues established phonetic-alphabet pattern alpha/bravo. Appears verbatim in runbook act 3 + 6, in any new bats fixture, and in helper scripts if planner lands one. Distinct from Phase 13's `phase13-fresh` throwaway. Captured as D-14-02.

---

## OQ-5b — Provision Style (RUNBOOK-01 act 3)

| Option | Description | Selected |
|--------|-------------|----------|
| Provision-live | Run `new-tenant.sh charlie` cold during the demo; audience watches Capsule materialize the tenant + SEED-02 propagation in real time | ✓ (recommended — matches RUNBOOK-01 verbatim "provision a new tenant live") |
| Pre-staged delete+recreate | Pre-create `charlie`, delete during demo, recreate to "rewind" | |

**Auto-selected:** Provision-live.
**Notes:** RUNBOOK-01 act 3 says "provision a new tenant live" verbatim. The audience-facing magic is the platform-owner CREATE → Capsule materialize → SEED-02 ≤ 60s observation chain — pre-staging hides exactly what's interesting. Phase 13's `new-tenant.sh` is the canonical provisioning path. Pre-demo checklist includes `kubectl delete tenant charlie --ignore-not-found` reset for idempotent reruns. Captured as D-14-03.

---

## Runbook Document Structure

| Option | Description | Selected |
|--------|-------------|----------|
| Single document | One `docs/poc-capsule-demo.md` with 6 acts + appendix sections | ✓ (recommended — RUNBOOK-01 + RUNBOOK-04 both specify a single ≤ 15-min cold read) |
| Multi-file (split by act) | Acts in separate files, index doc on top | |
| Append to operator runbook (`docs/poc-capsule.md`) | Extend the existing operator runbook with demo sections | |

**Auto-selected:** Single document.
**Notes:** Single 6-act file at `docs/poc-capsule-demo.md`. Cross-links to `docs/poc-capsule.md` (operator's runbook), `docs/capsule-on-eks.md` (EKS translation), ADR-008 (DEFER framing). Clean separation: operator runbook handles recovery procedures; demo runbook handles audience walkthrough. Captured as D-14-04.

---

## Pre-Demo Checklist Style (RUNBOOK-02)

| Option | Description | Selected |
|--------|-------------|----------|
| Executable shell snippets | Each item is a `kubectl` / `bash` command + expected output | ✓ (RUNBOOK-02 mandates "executable, not narrative") |
| Narrative checkboxes | Bullet-list prose ("ensure cluster is reachable", "stage kubeconfigs") | |
| Hybrid | Narrative with embedded snippets | |

**Auto-selected:** Executable shell snippets.
**Notes:** RUNBOOK-02 verbatim mandates "executable, not narrative". Items: (a) cluster reachable, (b) `task fix-dns-poc-capsule` if needed, (c) both kubeconfigs minted (export `PO_KC`, `TO_ALPHA_KC`, `TO_BRAVO_KC`), (d) `kubectl delete tenant charlie --ignore-not-found` reset for idempotency, (e) `task -l | grep poc` sanity check. Captured as D-14-05.

---

## DEMO-06 Forbidden Action Showcase (Act 2)

| Option | Description | Selected |
|--------|-------------|----------|
| One headline action live + full 3-action denial matrix in bats | `kubectl create clusterrolebinding po-cluster-admin-attempt ...` → Forbidden in runbook; bats asserts all 3 (`get nodes -o yaml`, `get csr`, `create clusterrolebinding`) | ✓ (recommended — one visceral live rejection + falsifiable full matrix) |
| All 3 actions live in act 2 | Run all 3 Forbidden checks during the demo | |
| All 3 in bats only | No live Forbidden action in the audience walkthrough | |

**Auto-selected:** One headline live + full matrix in bats.
**Notes:** RUNBOOK-01 says "at least one Forbidden cluster-admin action"; one well-chosen action is more visceral for the audience. `kubectl create clusterrolebinding` is the most visceral rejection (writing cluster-admin is the clearest "no" the platform-owner gets). Bats coverage on all 3 keeps the DEMO-06 contract falsifiable. Captured as D-14-07.

---

## Two-Perspective Verification Strategy (DEMO-01..05)

| Option | Description | Selected |
|--------|-------------|----------|
| New `demo-*.bats` files keyed to DEMO-01..06 REQs | 4–6 new bats files driving both kubeconfigs against the live cluster | ✓ (recommended — clean traceability per REQ) |
| Extend existing `rbac-08..10` + `negative-rbac-01..04` bats | Pack DEMO assertions into existing files | |
| Runbook only (no new bats) | Trust the runbook + Phase 13 bats as sufficient | |

**Auto-selected:** New `demo-*.bats` files.
**Notes:** Phase 13's `rbac-08..10` cover the RBAC grant matrix; DEMO-01..05 layer a two-kubeconfig assertion (platform-owner vs tenant-owner, both alpha + bravo). New files give clean traceability: `demo-01-live-platform-owner-tenants-list.bats`, `demo-02-live-tenant-owner-scoped-list.bats`, etc. Final names + count up to the planner. Captured as D-14-08.

---

## Capsule-Proxy Routing for Tenant-Owner Demo (DEMO-02 + DEMO-05)

| Option | Description | Selected |
|--------|-------------|----------|
| Inherit Phase 10 capsule-proxy NodePort 30443 routing | `issue-tenant-kubeconfig.sh` already mints kubeconfigs pointed at `:30443` — no wiring change | ✓ (no other viable option — this is the LIST-filter enforcement point) |
| Direct apiserver routing | Bypass capsule-proxy | (would break DEMO-02 / DEMO-05) |

**Auto-selected:** Phase 10 capsule-proxy NodePort 30443 routing.
**Notes:** The capsule-proxy `:30443` hop IS the LIST-filter mechanic the demo is showcasing. Pre-demo checklist mints `TO_ALPHA_KC` + `TO_BRAVO_KC` via the inherited script; runbook act 5 explicitly calls out the proxy hop as the enforcement point. Captured as D-14-09.

---

## UAT Verification Method (RUNBOOK-04)

| Option | Description | Selected |
|--------|-------------|----------|
| Milestone-owner cold-read against live `spoke-capsule` cluster, stopwatched, written up in `14-VALIDATION.md` | Pattern-mirrors Phase 13's `13-VALIDATION.md` | ✓ (recommended — matches existing GSD pattern) |
| Peer cold-read by separate reviewer | Out-of-team verification | |
| CI bats suite only | No human walkthrough | (would not satisfy RUNBOOK-04 "human reading it cold") |

**Auto-selected:** Milestone-owner cold-read.
**Notes:** RUNBOOK-04 mandates ≤ 15-minute cold read by a human with no prior context. Final plan in Phase 14 stopwatches the cold-run, writes results to `14-VALIDATION.md`. If > 15 min, tighten runbook prose / pre-mint scripts / collapse expository sections until ≤ 15 min. Pass criterion = single-pass cold-run under 15 min. Captured as D-14-10.

---

## Claude's Discretion (deferred to planner)

- Exact split of plans within Phase 14 (anticipated 3–5: Wave 0 RED bats scaffold; Wave 1 6-act runbook draft + checklist; Wave 2 TLS-noise + cross-link docs; Wave 3 UAT cold-read + VALIDATION.md).
- Whether DEMO bats files extend existing rbac/negative-rbac files or land as new `demo-*.bats` (preference: new files).
- Exact bats fixture name + extent for SEED-02 fresh-tenant on `charlie` (re-cite Phase 13's `seed-03-live-fresh-tenant.bats` or add `demo-04-live-charlie-seed-propagation.bats`).
- TLS-noise documentation depth (2-paragraph minimum per D-14-01; cap at ~half a page).
- Whether to add `task demo-capsule` Taskfile wrapper (recommendation: **no** — P31 isolation; revisit only if UAT identifies friction).

## Deferred Ideas

- Fix `tls: bad certificate` chatter at the cert-rotation layer (cert-manager wiring or proper CA distribution). → Future capsule-graduation phase or production EKS cut. ADR-008 = DEFER.
- `task demo-capsule` Taskfile wrapper. → Revisit at graduation or in a future POC-ergonomics milestone.
- `capsule-addon-fluxcd` Trial (ADDON-01/02 carry-forward from v0.19 Phase 12). → Already on parking lot.
- Pre-existing markdownlint failures + Phase 1–5 shellcheck warnings. → v0.18 close carryover parking lot.
- Real secret management (Vault / SOPS / age) for `/tmp`-minted kubeconfigs. → v0.18 close carryover.
- G-04 split-Kustomization refactor / architectural review. → Future-milestone concern.
