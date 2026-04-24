---
phase: 3
slug: flux-hub-bootstrap
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-24
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bats-core (system install; used by Phase 1 + Phase 2) |
| **Config file** | `tests/bats/test_helper.bash` (shared loader; Phase 2 added `require_live_destructive`) |
| **Quick run command** | `bats tests/bats/bootstrap-flux-01-idempotent.bats tests/bats/bootstrap-flux-02-docs.bats` |
| **Full suite command** | `KARYON_LIVE_TESTS=1 KARYON_LIVE_TESTS_DESTRUCTIVE=1 bats tests/bats/` |
| **Estimated runtime** | ~1s static-only; ~120s with live destructive gate active |

---

## Sampling Rate

- **After every task commit:** Run `bats tests/bats/bootstrap-flux-01-idempotent.bats tests/bats/bootstrap-flux-02-docs.bats` (static-only ~1s)
- **After every plan wave:** Run `bats tests/bats/` (all phases; destructive tests skip without live gate)
- **Before `/gsd-verify-work`:** Developer runs `KARYON_LIVE_TESTS=1 KARYON_LIVE_TESTS_DESTRUCTIVE=1 bats tests/bats/bootstrap-flux-01-idempotent.bats` on a real host with valid `.env`; output captured in checkpoint artifact.
- **Max feedback latency:** 1s (static); ~120s (live destructive)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 3-00-01 | 00 | 0 | FLUX-01..05 | — | N/A (test scaffolding) | scaffolding | `bats tests/bats/bootstrap-flux-01-idempotent.bats` | ❌ W0 | ⬜ pending |
| 3-00-02 | 00 | 0 | FLUX-05 | — | N/A (test scaffolding) | scaffolding | `bats tests/bats/bootstrap-flux-02-docs.bats` | ❌ W0 | ⬜ pending |
| 3-XX-XX | XX | 1+ | FLUX-01 | — | `scripts/bootstrap-flux.sh` invokes `flux bootstrap github` targeting hub-flux | static grep | `grep -F 'flux bootstrap github' scripts/bootstrap-flux.sh` | ✅ after W0 | ⬜ pending |
| 3-XX-XX | XX | 1+ | FLUX-02 | — | `--path clusters/hub-flux` hard-coded (no env override) | static grep | `grep -F -- '--path clusters/hub-flux' scripts/bootstrap-flux.sh && ! grep -E 'path=\\\\$\\{?[A-Z_]+' scripts/bootstrap-flux.sh` | ✅ after W0 | ⬜ pending |
| 3-XX-XX | XX | 1+ | FLUX-03 | T-3-01 (PAT leak) | Token never echoed; no `set -x`; no `echo "$GITHUB_TOKEN"` | static grep | `! grep -E 'echo[[:space:]]+(\"?)\\\\$GITHUB_TOKEN' scripts/bootstrap-flux.sh && ! grep -E '^set[[:space:]]+-[eux]*x' scripts/bootstrap-flux.sh` | ✅ after W0 | ⬜ pending |
| 3-XX-XX | XX | 1+ | FLUX-04 | — | Second run is a no-op; logs `already done, skipping: flux bootstrap`; exits 0 | live destructive (bats) | `KARYON_LIVE_TESTS=1 KARYON_LIVE_TESTS_DESTRUCTIVE=1 bats tests/bats/bootstrap-flux-01-idempotent.bats` | ✅ after W0 | ⬜ pending |
| 3-XX-XX | XX | 1+ | FLUX-05 / DOCS-03 | — | 3 rules present in `docs/flux-hub-spoke.md` + concrete patch example | static grep | `grep -qF 'bootstrap-managed' docs/flux-hub-spoke.md && grep -qF 'patch surface' docs/flux-hub-spoke.md && grep -qF 'immutable' docs/flux-hub-spoke.md && grep -qF 'kustomize-controller' docs/flux-hub-spoke.md` | ✅ after W0 | ⬜ pending |
| 3-XX-XX | XX | 1+ | D-13 | — | `# FLUX PATCH SURFACE` comment block present in bootstrap-generated kustomization.yaml | live grep | `grep -qF '# FLUX PATCH SURFACE' clusters/hub-flux/flux-system/kustomization.yaml` | runtime | ⬜ pending |
| 3-XX-XX | XX | 1+ | D-09 gate 3 | — | Root `flux-system` Kustomization is Ready=True | live (runtime self-assert) | `flux --context k3d-hub-flux get kustomizations flux-system` | runtime | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

Plan IDs (`XX`) are assigned by the planner in step 8; the planner will refine Task IDs and replace `3-XX-XX` with concrete values.

---

## Wave 0 Requirements

- [ ] `tests/bats/bootstrap-flux-01-idempotent.bats` — static stubs for FLUX-01/02/03 + D-13 + D-11 token-safety; live destructive @test for FLUX-04 (idempotency rerun) gated by `require_live_destructive`.
- [ ] `tests/bats/bootstrap-flux-02-docs.bats` — static stubs for FLUX-05 (3-rule grep triad + D-15 patch example grep).
- [ ] No new framework install — `bats` and `tests/bats/test_helper.bash` are already in place (Phase 1/2).

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Wrong kubectl context failure surface | D-06 | Requires mutating user shell kubeconfig context | `kubectl config use-context docker-desktop || kubectl config use-context k3d-spoke-a` then `bash scripts/bootstrap-flux.sh`; expect fail with "kubectl context is X, expected k3d-hub-flux → run: kubectl config use-context k3d-hub-flux" |
| Insufficient PAT scope error surface | D-08 | Requires a PAT with missing `repo` scope; can't safely simulate | Use a PAT without `repo` scope in `.env`; run `bash scripts/bootstrap-flux.sh`; expect flux's upstream 403/404 error is surfaced unchanged |
| `flux check` post-bootstrap regression | D-09 gate 1 | Requires live cluster mutation to trigger | `kubectl --context k3d-hub-flux -n flux-system scale deploy source-controller --replicas=0` then `bash scripts/bootstrap-flux.sh`; expect Section 4 gate 1 fail |
| `kubectl wait` 120s timeout | D-09 gate 2 / D-10 | Same — requires live mutation | Same as above; expect "flux controllers did not reach Ready in 120s — inspect: kubectl -n flux-system get deploy,pod" |
| Kustomization parse-error failure | D-09 gate 3 | Requires live malformed patch on kustomization.yaml | Inject a malformed `patches:` block; rerun bootstrap; expect Section 4 gate 3 fail with remediation hint `flux logs --kind=Kustomization` |
| D-11 token-leak probe (post-run) | FLUX-03 | One-shot forensic grep against a known-good run | `bash scripts/bootstrap-flux.sh 2>&1 \| tee /tmp/bootstrap.out; grep -F "$(grep ^GITHUB_TOKEN= .env \| cut -d= -f2-)" /tmp/bootstrap.out`; MUST return no matches |
| GitHub-side artifact verification | FLUX-01 | GitHub UI / API inspection | Browser or `gh api` to `$GITHUB_OWNER/$GITHUB_REPO`; expect `clusters/hub-flux/flux-system/{gotk-components.yaml,gotk-sync.yaml,kustomization.yaml}` present on `main` |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references (both bats test files)
- [ ] No watch-mode flags
- [ ] Feedback latency < 2s for static-only sampling
- [ ] `nyquist_compliant: true` set in frontmatter (flipped by planner after plans pass)

**Approval:** pending
