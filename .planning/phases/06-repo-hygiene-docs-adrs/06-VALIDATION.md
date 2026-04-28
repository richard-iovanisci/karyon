---
phase: 6
slug: repo-hygiene-docs-adrs
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-28
---

# Phase 6 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bats-core 1.11.x (existing project test infrastructure) |
| **Config file** | none — bats has no config; suite-per-file convention |
| **Quick run command** | `bats tests/bats/repo-hygiene-*.bats tests/bats/docs-*.bats` |
| **Full suite command** | `bats tests/bats/` (all suites; live ones gated by `KARYON_LIVE_TESTS=1`) |
| **Estimated runtime** | ~5 seconds (static suites only; full suite excludes live) |

---

## Sampling Rate

- **After every task commit:** Run `bats tests/bats/repo-hygiene-*.bats tests/bats/docs-*.bats`
- **After every plan wave:** Run `bats tests/bats/` (without `KARYON_LIVE_TESTS=1`) plus the 5 CI lints locally if tools installed
- **Before `/gsd-verify-work`:** Full bats suite green AND `.github/workflows/ci.yml` runs green on first push to a feature branch
- **Max feedback latency:** ~5 seconds (bats static); CI feedback ~2-3 minutes per push

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 06-W0-01 | 00 | 0 | REPO-02/03/04 | — | gitignore patterns + .env.example keys + hooks/pre-commit exist | static bats | `bats tests/bats/repo-hygiene-01-static.bats` | ❌ W0 | ⬜ pending |
| 06-W0-02 | 00 | 0 | REPO-05 | — | Taskfile.yml has no `kubectl\|docker\|k3d\|flux ` outside `cmds:` | static bats | `bats tests/bats/repo-hygiene-02-taskfile.bats` | ❌ W0 | ⬜ pending |
| 06-W0-03 | 00 | 0 | REPO-07 | T-06-CI-01 | CI workflow file has 5 job names + `fetch-depth: 0` for gitleaks | static bats | `bats tests/bats/repo-hygiene-03-ci.bats` | ❌ W0 | ⬜ pending |
| 06-W0-04 | 00 | 0 | DOCS-01 | — | README walks fresh-clone in locked heading order | static bats | `bats tests/bats/docs-01-readme-order.bats` | ❌ W0 | ⬜ pending |
| 06-W0-05 | 00 | 0 | DOCS-02 | — | architecture.md has Mermaid block + required nodes | static bats | `bats tests/bats/docs-02-architecture.bats` | ❌ W0 | ⬜ pending |
| 06-W0-06 | 00 | 0 | DOCS-04 | — | gpu-notes.md covers 3-part contract + RTX 5090 + sm_120 + 12.8 | static bats | `bats tests/bats/docs-04-gpu-notes.bats` | ❌ W0 | ⬜ pending |
| 06-W0-07 | 00 | 0 | DOCS-05 | — | rebuild-runbook has 7 step markers + timing + Common failures section | static bats | `bats tests/bats/docs-05-runbook.bats` | ❌ W0 | ⬜ pending |
| 06-W0-08 | 00 | 0 | DOCS-06..10 | — | Each ADR has Status/Context/Decision/Consequences and `Status: Accepted` | static bats | `bats tests/bats/docs-adr-template.bats` | ❌ W0 | ⬜ pending |
| 06-REPO-01 | TBD | 1 | REPO-01 | T-06-PAT-01 | One-shot gitleaks history scan returns clean OR all findings rotated | manual + CI gitleaks job | `gitleaks git --log-opts="--all" --redact --verbose` (one-shot) + CI `gitleaks/gitleaks-action` | ❌ W0 (synthetic fixture `tests/repo-hygiene/known-bad.sh`) | ⬜ pending |
| 06-REPO-02 | TBD | 1 | REPO-02 | T-06-PAT-01 | `.gitignore` excludes secret/TLS/IDE/OS paths from D-16 | static bats (W0) | `bats tests/bats/repo-hygiene-01-static.bats -f 'gitignore'` | ✅ after W0 | ⬜ pending |
| 06-REPO-03 | TBD | 1 | REPO-03 | T-06-PAT-01 | `.env.example` documents `GITHUB_OWNER`, `GITHUB_REPO`, `GITHUB_TOKEN` with placeholders + descriptions | static bats (W0) | `bats tests/bats/repo-hygiene-01-static.bats -f 'env.example'` | ✅ after W0 | ⬜ pending |
| 06-REPO-04 | TBD | 1 | REPO-04 | T-06-PAT-01 | `hooks/pre-commit` exists, sources preflight-lib, invokes `gitleaks git --pre-commit`; `core.hooksPath=hooks` set by `install-tools.sh` | static bats + manual | `bats tests/bats/repo-hygiene-01-static.bats -f 'pre-commit'`; manual: `git config --local core.hooksPath` returns `hooks` | ✅ after W0 | ⬜ pending |
| 06-REPO-05 | TBD | 2 | REPO-05 | — | Taskfile.yml is a thin wrapper; logic in `scripts/` only | static bats (W0) | `bats tests/bats/repo-hygiene-02-taskfile.bats` | ✅ after W0 | ⬜ pending |
| 06-REPO-06 | TBD | 2 | REPO-06 | — | `task destroy` and `task rebuild` require typed-yes confirmation | existing static bats | `bats tests/bats/destroy-rebuild-01-static.bats` (lines 13-44) | ✅ EXISTS | ⬜ pending |
| 06-REPO-07 | TBD | 3 | REPO-07 | T-06-CI-01 / T-06-PAT-01 | CI workflow runs shellcheck + kubeconform + markdownlint + bats prune-lint + gitleaks scan; green on push/PR | static bats (W0) + actual CI run | `bats tests/bats/repo-hygiene-03-ci.bats`; real verification: workflow runs green on first push | ✅ after W0 + CI green | ⬜ pending |
| 06-DOCS-01 | TBD | 3 | DOCS-01 | — | README.md walks fresh clone in locked heading order (10 sections) | static bats (W0) | `bats tests/bats/docs-01-readme-order.bats` | ✅ after W0 | ⬜ pending |
| 06-DOCS-02 | TBD | 3 | DOCS-02 | — | `docs/architecture.md` has Mermaid block + hub-flux/spoke-ml/spoke-apps/6443/6444/6445/k8s-net | static bats (W0) | `bats tests/bats/docs-02-architecture.bats` | ✅ after W0 | ⬜ pending |
| 06-DOCS-04 | TBD | 2 | DOCS-04 | — | `docs/gpu-notes.md` covers `default-runtime`, `nvidia/cuda`, `config.toml.tmpl`, `RTX 5090`, `sm_120`, `12.8` | static bats (W0) | `bats tests/bats/docs-04-gpu-notes.bats` | ✅ after W0 | ⬜ pending |
| 06-DOCS-05 | TBD | 3 | DOCS-05 | — | `docs/rebuild-runbook.md` has 7 step markers + at least one timing in seconds + "Common failures" section | static bats (W0) | `bats tests/bats/docs-05-runbook.bats` | ✅ after W0 | ⬜ pending |
| 06-DOCS-06 | TBD | 1 | DOCS-06 | — | `docs/adr/0001-single-wsl2-shared-docker-network.md` has Status/Context/Decision/Consequences + `Status: Accepted` | static bats (W0) | `bats tests/bats/docs-adr-template.bats -f '0001'` | ✅ after W0 | ⬜ pending |
| 06-DOCS-07 | TBD | 2 | DOCS-07 | — | `docs/adr/0002-k3d-over-kind.md` has the 4 sections | static bats (W0) | `bats tests/bats/docs-adr-template.bats -f '0002'` | ✅ after W0 | ⬜ pending |
| 06-DOCS-08 | TBD | 2 | DOCS-08 | — | `docs/adr/0003-flux-over-argocd.md` has the 4 sections | static bats (W0) | `bats tests/bats/docs-adr-template.bats -f '0003'` | ✅ after W0 | ⬜ pending |
| 06-DOCS-09 | TBD | 2 | DOCS-09 | — | `docs/adr/0004-hub-only-flux-control-plane.md` has the 4 sections | static bats (W0) | `bats tests/bats/docs-adr-template.bats -f '0004'` | ✅ after W0 | ⬜ pending |
| 06-DOCS-10 | TBD | 2 | DOCS-10 | — | `docs/adr/0005-kubernetes-version-pin.md` has the 4 sections + notes "current line" pin and CUDA 12.8+ floor | static bats (W0) | `bats tests/bats/docs-adr-template.bats -f '0005'` | ✅ after W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

*DOCS-03 is excluded — already complete from Phase 3 (`docs/flux-hub-spoke.md`).*

---

## Wave 0 Requirements

- [ ] `tests/bats/repo-hygiene-01-static.bats` — covers REPO-02 / REPO-03 / REPO-04 (gitignore patterns, .env.example keys, hooks/pre-commit existence + invocation)
- [ ] `tests/bats/repo-hygiene-02-taskfile.bats` — covers REPO-05 (Taskfile.yml is thin wrapper — no `kubectl|docker|k3d|flux ` outside `cmds:`)
- [ ] `tests/bats/repo-hygiene-03-ci.bats` — covers REPO-07 (workflow file structure: 5 job names + the gitleaks `fetch-depth: 0`)
- [ ] `tests/bats/docs-01-readme-order.bats` — covers DOCS-01 (heading order)
- [ ] `tests/bats/docs-02-architecture.bats` — covers DOCS-02 (Mermaid + required nodes)
- [ ] `tests/bats/docs-04-gpu-notes.bats` — covers DOCS-04 (3-part contract keywords)
- [ ] `tests/bats/docs-05-runbook.bats` — covers DOCS-05 (steps + timings + appendix)
- [ ] `tests/bats/docs-adr-template.bats` — covers DOCS-06..10 (template + Status: Accepted)
- [ ] **Synthetic fixture for gitleaks lint behavior:** the planner authors a temporary `tests/repo-hygiene/known-bad.sh` containing a realistic-but-fake `ghp_AAAA...` (20 chars) and asserts gitleaks flags it; the file is then deleted (NOT committed). This proves the CI lint catches real-shaped tokens.

*Existing test reused verbatim: `tests/bats/destroy-rebuild-01-static.bats` covers REPO-06 (DESTROY-01..02 confirmation) and is invoked by the CI prune-lint job (D-12). No duplication needed.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| One-shot historical gitleaks scan returns clean (or findings rotated) | REPO-01 | Full-history scan output written to `/tmp/karyon-gitleaks-history.json`, reviewed, then discarded — NOT committed (D-15, specifics) | Run `gitleaks git --log-opts="--all" --redact --verbose --report-path /tmp/karyon-gitleaks-history.json`. Review report. If findings: rotate the secret first, decide on history rewrite. Repo is already public, so historical secret must be rotated regardless. |
| `git config --local core.hooksPath` returns `hooks` | REPO-04 | Git config is per-clone, set by `scripts/install-tools.sh`; cannot static-test from a fresh clone before install runs | After running `bash scripts/install-tools.sh`, run `git config --local core.hooksPath` and confirm output is `hooks`. |
| CI workflow runs green on first push to a feature branch | REPO-07 | The bats test verifies the workflow file STRUCTURE; only an actual CI run verifies the lints all pass on the real tree | Push a no-op feature branch (`git checkout -b ci-smoke && git commit --allow-empty -m "smoke" && git push origin ci-smoke`); confirm all 5 jobs (`shellcheck`, `kubeconform`, `markdownlint`, `prune-lint-bats`, `gitleaks`) report success in the GitHub Actions UI. |
| Branch protection on `main` requires CI status check | REPO-07 / Pitfall 7 | GitHub UI / `gh api` configuration, not file-based — cannot test from repo content | After CI is green at least once, configure via GitHub UI (Settings → Branches → Add rule for `main` → Require status checks → select `ci`). Verify by deliberately failing CI on a feature branch and confirming PR cannot merge. |
| ADR content semantic correctness (not just template fields present) | DOCS-06..10 | Bats can verify section presence and `Status: Accepted` but not whether the prose accurately captures the locked PROJECT.md decision | Reviewer reads each ADR against PROJECT.md "Key Decisions" section; verifies decision wording matches and consequences are non-empty. |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 5s for static suites; ~3min for CI roundtrip
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
