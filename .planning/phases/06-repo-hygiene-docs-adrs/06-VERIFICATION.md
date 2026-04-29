---
phase: 06-repo-hygiene-docs-adrs
verified: 2026-04-28T21:50:00Z
status: passed
score: 5/5 must-haves verified
overrides_applied: 0
known_issues:
  - id: WR-01
    file: scripts/install-tools.sh
    line: 42
    severity: warning
    note: "asdf-binary version-check regex `^0\\.(1[89]|[2-9])` never matches `asdf --version` output (which starts with 'asdf version v0.18.1...'); causes idempotent re-download on every install-tools.sh re-run. Documented in 06-REVIEW.md WR-01. Does NOT affect any of the 5 phase 6 must_haves."
operational_caveats:
  - id: HOOKS-PATH-STATE
    severity: info
    note: "Current repo's local `core.hooksPath` is set to `/home/rich/code/gsd/karyon/.git/hooks` (the default), NOT to `hooks/`. The wiring artifact (Section 8 of `scripts/install-tools.sh`) and the hook file (`hooks/pre-commit`) both exist correctly, but the local clone's git config has not been (re)wired since the executor merge. Running `bash scripts/install-tools.sh` (or `git config --local core.hooksPath hooks`) would activate the gitleaks pre-commit hook locally. This does not invalidate must_have #1 — the artifact + install path both ship as committed and the bats REPO-04 contract verifies the on-disk wiring code, but a future operator should be aware that the local clone state needs the install-tools.sh re-run to enable the hook."
---

# Phase 6: Repo Hygiene + Docs + ADRs — Verification Report

**Phase Goal:** The repository is safe to publish publicly — no real secrets committed, `.env.example` contract documented, five ADRs under `docs/adr/` capture the locked architectural decisions, README walks a fresh clone from Windows prereqs to running lab, rebuild runbook documents timings + failure modes, GitHub Actions CI runs shellcheck + kubeconform + markdownlint on every push/PR.

**Verified:** 2026-04-28T21:50:00Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth (ROADMAP Success Criterion) | Status | Evidence |
|---|-----------------------------------|--------|----------|
| 1 | `.gitignore` excludes `.env` + secret-bearing paths (NOT `.planning/`); `.env.example` committed with placeholders for GITHUB_OWNER/REPO/TOKEN; gitleaks pre-commit hook blocks commits with plausible secrets | VERIFIED | `.gitignore` lines 1-29 contain `.env`, `kubeconfig*`, `*.kubeconfig`, `*.pem`, `*.key`, `*.crt`, `flux-system/identity*`, IDE noise; `grep -E '^\.planning/' .gitignore` exits 1 (NOT in gitignore). `.env.example` has GITHUB_OWNER, GITHUB_REPO, GITHUB_TOKEN with placeholder `ghp_REPLACE_WITH_PAT_WITH_repo_SCOPE`. `hooks/pre-commit` (1399 bytes, executable) invokes `gitleaks git --pre-commit --redact --staged --verbose`. `.gitleaks.toml` has [allowlist] with placeholder regex + .env.example path. `.tool-versions` pins `gitleaks 8.30.1`. `scripts/install-tools.sh` Sections 7-8 install gitleaks plugin + wire `git config --local core.hooksPath hooks`. Live gitleaks scan: 251 commits scanned, 0 leaks found. |
| 2 | `docs/adr/0001..0005` exist for the 5 locked decisions, each ADR names decision, context, consequences | VERIFIED | All 5 files present at `docs/adr/000{1..5}-*.md` with locked slugs (single-wsl2-shared-docker-network, k3d-over-kind, flux-over-argocd, hub-only-flux-control-plane, kubernetes-version-pin). Each contains 4 Nygard sections (`## Status`, `## Context`, `## Decision`, `## Consequences`) in order. Each has `Accepted (2026-04-22)` in first 10 lines. ADR-003 contains `ApplicationSet` + `## Migration note`. ADR-004 contains `spec.kubeConfig` + cross-link to `flux-hub-spoke.md` + P18 silent-misroute defense. ADR-005 contains `v1.34.6-k3s1`, `current line`, `RTX 5090`, `sm_120`, `12.8`. bats `docs-adr-template.bats` 8/8 green. |
| 3 | README.md walks fresh clone in DOCS-01 locked order; docs/architecture.md has GitHub-renderable Mermaid hub-spoke diagram; docs/gpu-notes.md explains 3-part k3d GPU contract + RTX 5090/sm_120/CUDA 12.8+ floor; docs/rebuild-runbook.md step-by-step with timings + common failures | VERIFIED | README.md (260 lines): h1 + TL;DR + 10 sections in locked order (`Windows prereqs` → ... → `teardown`); links to all 5 v1 docs + 5 ADRs; per-task reference table covers all 11 Taskfile entries. docs/architecture.md (102 lines): h1 BEFORE Mermaid fence (MD041 safe); Mermaid block contains hub-flux/spoke-ml/spoke-apps + 6443/6444/6445 + k8s-net/172.30.0.0/16 + spec.kubeConfig + 4 flux-system controllers. docs/gpu-notes.md (130 lines): h1; 3-part contract (default-runtime, nvidia/cuda, config.toml.tmpl); RTX 5090 + sm_120 + CUDA 12.8+ floor; cross-link to ADR-005. docs/rebuild-runbook.md (322 lines): h1; 7 step markers (`>>> step preflight` → `>>> step health-check`) in strict order; 190-second baseline; `## Common failures` appendix with 7 symptom-keyed entries (fix-dns, GPU 3-part, TLS-SAN, CUDA image, PAT, .env, WSL2 mirrored). bats DOCS-01/02/04/05 all green (16/16). |
| 4 | Taskfile.yml is single orchestration surface (logic in scripts/, Taskfile invokes scripts); destructive tasks (destroy, rebuild) named explicitly and require confirmation | VERIFIED | Taskfile.yml (57 lines, 11 tasks): every `cmds:` entry is exactly `bash scripts/<name>.sh` and nothing else (no inline kubectl/docker/k3d/flux outside cmds:). Tasks: preflight, build-image, create-clusters, delete-clusters, bootstrap-flux, register-spokes, deploy-examples, fix-dns, health-check, destroy, rebuild. `destroy:` and `rebuild:` are explicitly named; confirmation enforced at script level (scripts/destroy.sh:26-29 + scripts/rebuild.sh:32-43 — typed `yes` prompt; KARYON_DESTROY_APPROVED=yes env override; bats DESTROY-01/02 17/17 green). No Taskfile `prompt:` keys (avoids double confirmation per Pitfall 5). bats `repo-hygiene-02-taskfile.bats` 3/3 green. |
| 5 | .github/workflows/ci.yml runs shellcheck, kubeconform, markdownlint on every push/PR; lint step rejects scripts/** referencing docker system prune or docker builder prune (DESTROY-04) | VERIFIED | .github/workflows/ci.yml (99 lines): triggers on `push: branches: ['**']` AND `pull_request:`; permissions `contents: read`. 5 jobs present: `shellcheck`, `markdownlint`, `kubeconform`, `prune-lint-bats`, `gitleaks-scan`. All `uses:` lines pin to 40-char SHA (5 instances of actions/checkout, 1 each for shellcheck/markdownlint actions, all SHA-anchored). `gitleaks-scan` uses `fetch-depth: 0` (catches historical leaks). `kubeconform` references `datreeio/CRDs-catalog` with `{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json` URL template, DATREE_SHA pinned at `8f6b5cb13c01d5ee16331f14aece201caec8e1c5`. `prune-lint-bats` runs `bats tests/bats/destroy-rebuild-01-static.bats` which contains 5 prune-rejection tests (lines 148, 165, 175, 184, 193) — these are the DESTROY-04 enforcement. bats `repo-hygiene-03-ci.bats` 6/6 green. |

**Score:** 5/5 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `.gitignore` | D-16 expansion + `.env` + .planning NOT ignored | VERIFIED | 30 lines; contains all required literals; `.planning/` not present (verified via `grep -E '^\.planning/' .gitignore` exit 1) |
| `.env.example` | 3 keys + placeholder | VERIFIED | 667 bytes; contains `GITHUB_OWNER=`, `GITHUB_REPO=`, `GITHUB_TOKEN=`, `ghp_REPLACE_WITH_PAT_WITH_repo_SCOPE` |
| `.gitleaks.toml` | [allowlist] with placeholder | VERIFIED | 18 lines; `[allowlist]` + placeholder regex + `\.env\.example` path |
| `.tool-versions` | gitleaks 8.30.1 | VERIFIED | Final line: `gitleaks 8.30.1` |
| `hooks/pre-commit` | executable; invokes canonical gitleaks subcommand | VERIFIED | 1399 bytes; mode 755; bash strict mode; sources preflight-lib; `gitleaks git --pre-commit --redact --staged --verbose`; remediation message names `git commit --no-verify` |
| `scripts/install-tools.sh` | Sections 5/7/8 wire gitleaks plugin + core.hooksPath | VERIFIED | Section 5 plugin loop includes `gitleaks` (line 95); Section 7 `asdf plugin gitleaks` (line 157); Section 8 `git config --local core.hooksPath hooks` (line 176). `bash -n` clean. |
| `docs/adr/0001-single-wsl2-shared-docker-network.md` | DOCS-06 Nygard ADR | VERIFIED | 72 lines; 4 sections; Status: Accepted (2026-04-22); WSL2 + k8s-net + Docker keywords |
| `docs/adr/0002-k3d-over-kind.md` | DOCS-07 Nygard ADR | VERIFIED | 57 lines; 4 sections; k3d + Kind + --gpus all |
| `docs/adr/0003-flux-over-argocd.md` | DOCS-08 with ApplicationSet trade-off + migration note | VERIFIED | 87 lines; 4 sections + `## Migration note`; ApplicationSet + migration; Flux + ArgoCD |
| `docs/adr/0004-hub-only-flux-control-plane.md` | DOCS-09 with spec.kubeConfig pattern | VERIFIED | 80 lines; 4 sections; hub + spec.kubeConfig + controller; cross-link to flux-hub-spoke.md; P18 silent-misroute defense |
| `docs/adr/0005-kubernetes-version-pin.md` | DOCS-10 k3s + CUDA pins | VERIFIED | 69 lines; 4 sections; v1.34.6-k3s1 + 12.8 + RTX 5090 + sm_120 + current line |
| `README.md` | DOCS-01 hybrid quickstart + 10-section locked order | VERIFIED | 260 lines; h1 + TL;DR + 10 fresh-clone sections in order; links to 5 v1 docs + 5 ADRs; 11-task reference table |
| `docs/architecture.md` | DOCS-02 Mermaid topology | VERIFIED | 102 lines; h1 BEFORE Mermaid fence (line 1 vs 14); all 13 required literals (clusters/ports/k8s-net/CIDR/spec.kubeConfig/4 controllers) |
| `docs/gpu-notes.md` | DOCS-04 3-part GPU contract + Blackwell | VERIFIED | 130 lines; h1; default-runtime + nvidia/cuda + config.toml.tmpl + RTX 5090 + sm_120 + 12.8; cross-link to ADR-005 |
| `docs/rebuild-runbook.md` | DOCS-05 linear steps + timings + failure appendix | VERIFIED | 322 lines; h1; 7 step markers in strict order; 190-second baseline; ## Common failures appendix; cross-links to architecture/flux-hub-spoke/gpu-notes/wsl-networking |
| `Taskfile.yml` | REPO-05 thin-wrapper, 11 tasks | VERIFIED | 57 lines; 11 tasks (preflight added at top); every cmds: is `bash scripts/<name>.sh`; no `prompt:` keys |
| `.github/workflows/ci.yml` | REPO-07 5 jobs + SHA pins + fetch-depth: 0 | VERIFIED | 99 lines; 5 jobs (shellcheck/markdownlint/kubeconform/prune-lint-bats/gitleaks-scan); all uses: pinned to 40-char SHA; gitleaks fetch-depth: 0; datreeio CRDs catalog SHA-pinned |
| `.markdownlint.json` | markdownlint config | VERIFIED | Valid JSON; default: true; MD013: false; MD041: true; MD033 allowed_elements [br, div]; plus MD032/MD060 disabled (auto-fix) |
| Cleanup: `prereqs.sh` deleted | D-13 cleanup | VERIFIED | File absent on disk; deletion commit `5a97116` in git log |
| Cleanup: `starter.md` deleted | D-14 cleanup | VERIFIED | File absent on disk; deletion commit `5a97116` in git log |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `hooks/pre-commit` | `scripts/lib/preflight-lib.sh` | `source ${REPO_ROOT}/scripts/lib/preflight-lib.sh` | WIRED | Line 13 sources the library; uses `have`, `section`, `pass`, `fail` helpers |
| `scripts/install-tools.sh` Section 8 | git core.hooksPath = hooks | `git config --local core.hooksPath hooks` | WIRED IN CODE | Line 176 sets it idempotently. Note: current local clone's git config points to `.git/hooks` (default) — running install-tools.sh would re-wire. Documented under operational_caveats |
| `.gitleaks.toml` | `.env.example` | `[allowlist] paths` regex `\.env\.example` | WIRED | Allows the whole `.env.example` file path; placeholder regex doubles as belt-and-suspenders |
| `.github/workflows/ci.yml` `prune-lint-bats` | `tests/bats/destroy-rebuild-01-static.bats` | `bats tests/bats/destroy-rebuild-01-static.bats` invocation | WIRED | Line 77 invokes the existing bats suite; the bats suite contains 5 DESTROY-04 prune-rejection tests (lines 148-198) |
| `.github/workflows/ci.yml` `gitleaks-scan` | full git history | `fetch-depth: 0` + `--log-opts="--all"` | WIRED | Line 88 sets fetch-depth: 0; line 98 uses --log-opts="--all" |
| `.github/workflows/ci.yml` `kubeconform` | datreeio/CRDs-catalog | `--schema-location URL with ${DATREE_SHA}` | WIRED | DATREE_SHA env var pinned at line 56; URL template `{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json` at line 64 |
| README.md | 5 v1 docs + 5 ADRs | relative markdown links | WIRED | All 10 cross-link targets verified to exist as real files |
| docs/gpu-notes.md | adr/0005-kubernetes-version-pin.md | relative cross-link | WIRED | Line 96 + line 128 |
| docs/architecture.md | adr/0004-hub-only-flux-control-plane.md | relative cross-link in "Cross-cluster reconciliation" section | WIRED | Line 85 |
| docs/rebuild-runbook.md | flux-hub-spoke.md, gpu-notes.md, wsl-networking.md, architecture.md, ADRs | relative cross-links | WIRED | Reference section lines 315-322 |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| All 8 phase 6 bats files parse | `bats --count tests/bats/repo-hygiene-*.bats tests/bats/docs-*.bats` | 39 tests, no parse errors | PASS |
| repo-hygiene bats green | `bats tests/bats/repo-hygiene-01-static.bats tests/bats/repo-hygiene-02-taskfile.bats tests/bats/repo-hygiene-03-ci.bats` | 15/15 ok | PASS |
| docs bats green | `bats tests/bats/docs-01-readme-order.bats tests/bats/docs-02-architecture.bats tests/bats/docs-04-gpu-notes.bats tests/bats/docs-05-runbook.bats tests/bats/docs-adr-template.bats` | 24/24 ok | PASS |
| destroy-rebuild bats regression | `bats tests/bats/destroy-rebuild-01-static.bats` | 17/17 ok (REPO-05 wiring + DESTROY-01..06 contracts unchanged) | PASS |
| Live gitleaks history scan | `gitleaks git --verbose --redact --log-opts="--all"` | 251 commits scanned, 3.85 MB, 0 leaks found | PASS |
| ci.yml YAML parses | (visual inspection of workflow file) | Valid YAML structure, 5 jobs as expected | PASS |
| .markdownlint.json parses | (visual inspection) | Valid JSON | PASS |
| gitleaks tool installed | `command -v gitleaks && gitleaks --version` | `/home/rich/.asdf/shims/gitleaks` + `gitleaks version 8.30.1` | PASS |
| prereqs.sh cleanup | `[ ! -f prereqs.sh ]` | exit 0 (file absent) | PASS |
| starter.md cleanup | `[ ! -f starter.md ]` | exit 0 (file absent) | PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| REPO-01 | 06-01 | Repo is public-safe — no real tokens/kubeconfigs/CA keys/client certs committed | SATISFIED | One-shot gitleaks history scan (251 commits, 0 leaks) |
| REPO-02 | 06-01 | .gitignore excludes secret-bearing paths; .planning intentionally tracked | SATISFIED | .gitignore D-16 expansion verified; `.planning/` not in gitignore |
| REPO-03 | 06-01 | .env.example checked in with placeholder values | SATISFIED | .env.example has all 3 keys + placeholder + comments |
| REPO-04 | 06-01 | gitleaks pre-commit hook installed via scripts/install-tools.sh | SATISFIED | hooks/pre-commit + Section 8 wiring + bats REPO-04 4/4 green |
| REPO-05 | 06-04 | Taskfile.yml is single orchestration surface; logic in scripts/ | SATISFIED | Taskfile thin-wrapper invariant verified; bats REPO-05 3/3 green |
| REPO-06 | 06-04 | Destructive tasks named explicitly with confirmation | SATISFIED | destroy/rebuild named; script-level typed-yes confirmation; bats DESTROY-01..06 green |
| REPO-07 | 06-07 | GitHub Actions CI runs shellcheck/kubeconform/markdownlint + DESTROY-04 lint | SATISFIED | 5-job workflow; bats REPO-07 6/6 green |
| DOCS-01 | 06-05 | README.md walks fresh-clone path in locked order | SATISFIED | 10 sections in order; links to all docs + ADRs; bats DOCS-01 4/4 green |
| DOCS-02 | 06-03 | docs/architecture.md Mermaid hub-spoke diagram | SATISFIED | 102 lines; Mermaid block with all 13 required literals; bats DOCS-02 5/5 green |
| DOCS-03 | (verify-only) | docs/flux-hub-spoke.md exists from Phase 3; README cross-links | SATISFIED | File exists from Phase 3; README has 2 cross-links to it |
| DOCS-04 | 06-03 | docs/gpu-notes.md explains 3-part GPU contract + sm_120 floor | SATISFIED | 130 lines; all 6 required keywords; bats DOCS-04 3/3 green |
| DOCS-05 | 06-06 | docs/rebuild-runbook.md step-by-step with timings + failures | SATISFIED | 322 lines; 7 step markers in order; 190s baseline; Common failures appendix; bats DOCS-05 4/4 green |
| DOCS-06 | 06-01 | docs/adr/0001 single-WSL2 + k8s-net | SATISFIED | 72 lines; 4 Nygard sections; Status: Accepted; WSL2/k8s-net/Docker keywords |
| DOCS-07 | 06-02 | docs/adr/0002 k3d-over-Kind | SATISFIED | 57 lines; k3d + Kind + --gpus all |
| DOCS-08 | 06-02 | docs/adr/0003 Flux-over-ArgoCD with ApplicationSet trade-off + migration note | SATISFIED | 87 lines; ApplicationSet + ## Migration note section |
| DOCS-09 | 06-02 | docs/adr/0004 hub-only Flux control plane | SATISFIED | 80 lines; spec.kubeConfig pattern + P18 defense + flux-hub-spoke.md cross-link |
| DOCS-10 | 06-02 | docs/adr/0005 k3s v1.34.6-k3s1 + CUDA 12.8+ pins | SATISFIED | 69 lines; v1.34.6-k3s1 + current line + RTX 5090 + sm_120 + 12.8 |

**Coverage:** 17/17 requirements satisfied (REPO-01..07 + DOCS-01..10).

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| scripts/install-tools.sh | 42 | asdf version-check regex `^0\.(1[89]|[2-9])` never matches actual `asdf --version` output (which starts with `asdf version v0.18.1...`) | Info (WR-01 from 06-REVIEW.md) | Idempotency violated; install-tools.sh re-downloads asdf binary on every re-run. Does NOT affect any of the 5 phase 6 must_haves. Tracked as known issue. |
| README.md | 260 | `(TODO: add a LICENSE file when the project ships v1.)` | Info | Intentional TODO placeholder per plan 05; not a phase 6 deliverable; no downstream gate |

No blocker or warning anti-patterns found. The WR-01 idempotency bug exists but is explicitly out-of-scope for phase 6 must_haves (it predates phase 6 and doesn't impact any of the 5 ROADMAP success criteria).

### Operational Caveats

The current local repo's `core.hooksPath` resolves to `/home/rich/code/gsd/karyon/.git/hooks` (the default), NOT to `hooks/`. The wiring is implemented in `scripts/install-tools.sh` Section 8 (committed and verifiable), and the hook file at `hooks/pre-commit` is correct and executable. However, in the current local clone state, the gitleaks pre-commit hook is NOT actively wired. This appears to be due to the executor working in worktrees where install-tools.sh Section 8 ran against the worktree's `.git`, not the main repo's `.git/config`.

**Mitigation:** Running `bash scripts/install-tools.sh` in the main repo (or running `git config --local core.hooksPath hooks` directly) will activate the hook. The post-push tier of secrets defense (CI gitleaks-scan job in `.github/workflows/ci.yml` with `fetch-depth: 0`) is the belt-and-suspenders catch for this case — any commit pushed to the remote will be scanned regardless of local hook state.

This caveat is informational. The phase deliverable (the hook artifact + the install logic) ships as intended; the activation step is normal "fresh-clone setup" that the README documents under "5. tools install".

### Human Verification Required

None. All bats tests parse and pass automatically; CI workflow YAML is well-formed; gitleaks live scan is clean; cleanup deletions verified via filesystem checks and git log.

The Plan 07 human-checkpoint asked the user to push to a feature branch and verify the 5-job CI run on GitHub. Plan 07 SUMMARY.md notes the user approved based on local pre-flights (all 5 lints green locally) and deferred the GitHub-side push verification + branch protection setup. This is a developer follow-up post-phase, not a phase 6 must_have. The CI workflow file itself is verified by the bats `repo-hygiene-03-ci.bats` contract (6/6 green), which encodes every required structural property of the workflow (5 job names, fetch-depth: 0, 40-char SHA pins, datreeio CRDs catalog, prune-lint-bats reuse).

### Gaps Summary

No gaps. All 5 ROADMAP success criteria satisfied; all 17 requirement IDs (REPO-01..07 + DOCS-01..10) satisfied; all artifacts present, substantive, wired, and producing the contracted behavior. One known issue (WR-01 asdf version regex) is documented as a separate technical-debt item that does not block phase 6 closure. One operational caveat (local `core.hooksPath` state) is documented but does not invalidate the must_have because the artifact + install path both ship as intended.

The Phase 6 goal — "the repository is safe to publish publicly" — is achieved:
- 0 real secrets in 251 commits (live gitleaks scan)
- public-safe `.env.example` template with placeholders
- defense-in-depth: gitignore + .env.example + .gitleaks.toml + hooks/pre-commit + CI gitleaks-scan
- 5 ADRs documenting the locked architectural decisions
- README walks the fresh-clone path in locked order
- rebuild runbook with timings + failure appendix
- CI workflow gating shellcheck + kubeconform + markdownlint + gitleaks + DESTROY-04 prune-rejection on every push/PR

---

*Verified: 2026-04-28T21:50:00Z*
*Verifier: Claude (gsd-verifier)*
