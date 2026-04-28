# Phase 6: Repo Hygiene + Docs + ADRs - Context

**Gathered:** 2026-04-28
**Status:** Ready for planning

<domain>
## Phase Boundary

Close out the public-repo contract and ship the documentation set for v1 of
the karyon lab. Two parallel tracks:

**Repo hygiene (REPO-01..07):**

- Audit the entire tracked tree (including `.planning/`) for committed
  secrets — tokens, kubeconfigs, CA keys, client certs.
- Expand `.gitignore` beyond Phase 1's narrow `.env*` slice.
- Validate / harden the existing `.env.example` and confirm the
  `GITHUB_OWNER` / `GITHUB_REPO` / `GITHUB_TOKEN` contract.
- Install gitleaks via asdf, wire it as a native git pre-commit hook through
  `core.hooksPath`, and run a one-shot historical scan during this phase.
- Audit `Taskfile.yml` so all logic stays in `scripts/` and destructive tasks
  (`destroy`, `rebuild`) are explicitly named with confirmation guards.
- Land `.github/workflows/ci.yml` running shellcheck + kubeconform +
  markdownlint + the existing prune-lint bats test + a gitleaks scan, on every
  push and pull-request, blocking PR merges on red.

**Documentation (DOCS-01..10) — DOCS-03 already complete:**

- `README.md` (DOCS-01) — hybrid quickstart + reference. TL;DR + the locked
  fresh-clone path (Windows prereqs → WSL config → Docker install → NVIDIA
  setup → tools install → cluster creation → Flux bootstrap → spoke
  registration → example deploy → teardown), then per-task reference sections.
- `docs/architecture.md` (DOCS-02) — single Mermaid hub-spoke topology
  diagram (hub-flux + spoke-ml + spoke-apps on `k8s-net 172.30.0.0/16`,
  API ports, flux-system controllers, `spec.kubeConfig` arrows into spokes).
- `docs/gpu-notes.md` (DOCS-04) — 3-part k3d GPU contract + RTX 5090 / sm_120
  + CUDA 12.8+ floor.
- `docs/rebuild-runbook.md` (DOCS-05) — linear numbered steps with expected
  warm-cache timings + a failure-mode appendix at the bottom.
- `docs/adr/0001..0005-*.md` (DOCS-06..10) — five ADRs in lightweight format
  (Status / Context / Decision / Consequences). Decision content is locked in
  PROJECT.md; this phase ships the on-disk artifacts.

**Cleanup (this phase):**

- Delete `prereqs.sh` from repo root — fully superseded by
  `scripts/preflight.sh`.
- Delete `starter.md` from repo root — fully absorbed into PROJECT.md /
  REQUIREMENTS.md / ROADMAP.md.

Out of scope (owned elsewhere or deferred):

- New capabilities beyond REPO-01..07 / DOCS-01..10 (release tagging,
  badges, GitHub Pages, observability, real secret management).
- Live cluster work in CI — the Actions runner cannot host k3d / GPU clusters;
  CI is static-only.
- Bats live tests (those gated by `KARYON_LIVE_TESTS=1`) — not run in CI.
- Anything that would touch Phase 1–5 implementation outside the `Taskfile.yml`
  audit and the .gitignore expansion.

</domain>

<decisions>
## Implementation Decisions

### Documentation Voice + ADR Template

- **D-01:** `README.md` is **hybrid quickstart + reference**. Top of the file:
  60-second TL;DR + the locked fresh-clone path as a clickable flow. Below:
  per-task reference sections (preflight, image build, cluster create, Flux
  bootstrap, spoke register, deploy, health, fix-dns, destroy, rebuild) keyed
  off `Taskfile.yml`. Audience is the author + people mirroring the setup, so
  both first-encounter and returning-user paths are first-class.
- **D-02:** ADRs use the **lightweight Nygard-style template** with four
  sections: `## Status`, `## Context`, `## Decision`, `## Consequences`.
  Status defaults to `Accepted` for the v1 ADRs (decisions are already locked).
  No "Considered Options" section, no MADR pros/cons list — the rationale is
  already in PROJECT.md and ROADMAP.md.
- **D-03:** `docs/architecture.md` ships **a single Mermaid topology diagram**
  in DOCS-02. No reconcile-flow or GPU-contract sub-diagrams in the same file
  — those concepts get prose in `docs/flux-hub-spoke.md` and
  `docs/gpu-notes.md` respectively. The Mermaid diagram must include:
  hub-flux (port 6443) + spoke-ml (port 6444, GPU) + spoke-apps (port 6445)
  on `k8s-net 172.30.0.0/16`, the four flux-system controllers, and
  `spec.kubeConfig`-mediated reconciliation arrows from hub into each spoke.
- **D-04:** `docs/rebuild-runbook.md` is laid out as **linear numbered steps
  with timings, then a failure-mode appendix**. Top: the DESTROY-05 chain
  (destroy → create-clusters → bootstrap-flux → register-spokes →
  deploy-examples → health-check) with expected wall-clock per step on a warm
  CUDA cache run. Bottom: a "Common failures" section keyed by symptom (stale
  CoreDNS NodeHosts → `task fix-dns`; missing GPU capacity → IMG-04 check; PR
  TLS-SAN mismatch → recreate the cluster, etc.). Easy to skim mid-incident.

### Secret-Scan Toolchain

- **D-05:** Use **gitleaks** (not detect-secrets). Confirms PROJECT.md and
  STATE.md prior framing. Single Go binary, fast, no Python dependency, default
  ruleset already covers GitHub PATs (`ghp_`, `github_pat_`, `gho_`), AWS keys,
  generic high-entropy strings.
- **D-06:** Hook framework is **native git via `core.hooksPath`**. Phase 6
  commits `hooks/pre-commit` (a bash script invoking gitleaks on staged
  changes) and `install-tools.sh` runs `git config core.hooksPath hooks` once
  during install. No Python pre-commit framework, no lefthook — minimum new
  surface, consistent with the project's bash-only script style.
- **D-07:** Gitleaks itself is **installed via asdf**. Add `gitleaks <pinned
  version>` to `.tool-versions`; `install-tools.sh` provisions the asdf plugin
  (researcher confirms `asdf-community/asdf-gitleaks` or successor is current
  and resolves the latest stable v8.x). Matches the TOOLS-01..03 contract for
  every other tool in the chain.
- **D-08:** History strategy is **one-shot historical scan during this phase
  PLUS a CI scan on every push**. The local pre-commit hook stops a careless
  contributor from leaking forward; the CI scan catches anyone who pushed
  without the hook installed; the one-shot scan during this phase
  (`gitleaks detect --source . --log-opts='--all'`) treats current HEAD AND
  history. If the one-shot scan flags anything real, treat it as a leak
  incident: rotate the secret first, then decide on history rewrite. The repo
  is already public, so any historical secret must be rotated regardless of
  whether we rewrite history.

### CI Workflow Scope

- **D-09:** CI runs **only the four required static lints + a gitleaks scan**.
  Jobs: `shellcheck` on `scripts/**`, `kubeconform` on YAML under
  `clusters/**` and `examples/**`, `markdownlint` on `**/*.md`, the existing
  destroy-rebuild prune-lint bats test, and `gitleaks detect`. No bats live
  tests, no `task health-check`, no `task rebuild` — Actions can't host
  k3d/GPU clusters and faking it adds maintenance burden.
- **D-10:** kubeconform sources Flux CRD schemas via the **datreeio CRDs
  catalog** at workflow time, with `--schema-location` pointing at
  `https://raw.githubusercontent.com/datreeio/CRDs-catalog/<pinned-sha>/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json`
  AND the default schema location. Pin the catalog SHA in the workflow file
  for reproducibility — researcher picks the SHA and verifies it covers
  `HelmRelease`, `Kustomization`, `GitRepository`, `Bucket`, `Receiver`, and
  the kustomize-controller v1 `Kustomization` (note: there are two
  `Kustomization` kinds — kustomize/v1beta1 native and kustomize.toolkit.fluxcd.io/v1).
- **D-11:** CI triggers on **`push` to any branch AND `pull_request`**. Branch
  protection on `main` requires the CI status check to be green to merge —
  i.e., PR failures block merge. Direct pushes to `main` still run CI but
  don't block (already merged); the early signal still matters for
  feature-branch work.
- **D-12:** The **DESTROY-04 prune-lint is enforced in CI by running the
  existing bats test**, not by reimplementing the grep inline. CI installs
  `bats-core` (apt) and runs
  `bats tests/bats/destroy-rebuild-01-static.bats`. One source of truth between
  local dev and CI; eliminates drift risk.

### Cleanup + Audit Scope

- **D-13:** **Delete `prereqs.sh` from repo root.** It's been superseded by
  `scripts/preflight.sh`, which covers PRE-01..14 (the original only covered
  PRE-01..08). Anyone wanting the historical content can find it in `git log`.
  README documents `task preflight` (or `bash scripts/preflight.sh`) as the
  canonical entry point.
- **D-14:** **Delete `starter.md` from repo root.** Fully absorbed into
  PROJECT.md / REQUIREMENTS.md / ROADMAP.md. Removing it eliminates the "two
  competing READMEs" problem when a new contributor lands on the repo.
- **D-15:** REPO-01 sweep covers **the FULL tracked tree, including
  `.planning/`**. Run gitleaks on the whole repo + a curated grep for high-
  value patterns (`ghp_`, `github_pat_`, `gho_`, `BEGIN .* PRIVATE KEY`,
  `BEGIN CERTIFICATE`, base64-looking blobs near `client-key-data:` or
  `client-certificate-data:` in YAML). Phase 4 work involved real CA-data and
  service-account tokens during live execution — verify nothing leaked into a
  CONTEXT.md, transcript snippet, or live-test artifact. `.planning/` is
  intentionally tracked, so it's part of the public surface and must be scanned.
- **D-16:** REPO-02 `.gitignore` expansion is **targeted**: kubeconfig
  artifacts (`kubeconfig*`, `*.kubeconfig`), TLS material (`*.pem`, `*.key`,
  `*.crt`), local Flux scratch from bootstrap retries (`flux-system/identity*`
  if Flux ever drops one), and OS / IDE noise (`.DS_Store`, `*.swp`, `.idea/`,
  `.vscode/`). No comprehensive github/gitignore baseline import — most rules
  there don't match anything in this repo and would just be noise.

### Claude's Discretion

These areas weren't explicitly discussed; planner / researcher decide within
the locked decisions above:

- **README headings outline.** D-01 locks the style and ordered fresh-clone
  path; the planner picks the exact section headings, depth of preamble, and
  cross-link conventions. Researcher should confirm GitHub README rendering
  for ToC anchors and Mermaid block syntax under `mermaid` fences.
- **ADR file naming.** ROADMAP and starter.md fix the slugs
  (`0001-single-wsl2-shared-docker-network.md`, `0002-k3d-over-kind.md`,
  `0003-flux-over-argocd.md`, `0004-hub-only-flux-control-plane.md`,
  `0005-kubernetes-version-pin.md`). Slugs are not negotiable; ADR body
  prose is the planner's call within the D-02 template.
- **gitleaks pinned version + asdf-plugin source.** D-07 locks asdf as the
  install path; researcher picks the current stable v8.x line and verifies
  the asdf-plugin repo (likely `asdf-community/asdf-gitleaks` or the
  zufardhiyaulhaq fork) is maintained against asdf v0.18+ Go-rewrite.
- **`.gitleaks.toml` ruleset.** Default ruleset is fine; planner adds
  allow-rules for any false-positives discovered during the one-shot scan
  (e.g., placeholder tokens in `.env.example`, base64-looking SHA hashes in
  CONTEXT.md, the literal `ghp_REPLACE_WITH_PAT_WITH_repo_SCOPE` from D-11
  Phase 1).
- **kubeconform invocation flags.** `--strict` vs not, summary format,
  ignore-list for kustomize-only files (e.g., `kustomization.yaml` itself
  isn't a Kubernetes resource and may need `--ignore-filename-pattern`).
  Researcher picks based on current kubeconform docs.
- **markdownlint config strictness.** `.markdownlint.json` (or
  `.markdownlint-cli2.jsonc`) — researcher picks defaults; relaxing MD013
  (line-length) is likely needed for tabular content. Keep MD041
  (first-line-h1) on for top-level docs.
- **shellcheck severity level.** Default (`-S style`) vs `-S warning`.
  Researcher picks; the existing scripts already pass at default.
- **gitleaks CI step on push vs PR.** D-11 covers the workflow trigger; the
  gitleaks job in particular should run on both. Implementation detail.
- **Branch protection setup steps.** Documented in `docs/rebuild-runbook.md`
  or a dedicated `docs/contributing.md` — planner decides where; not a new
  doc unless the planner sees a real need.
- **Whether `Taskfile.yml` audit (REPO-05) requires changes.** The current
  Taskfile is already a thin wrapper around `scripts/*` (verified during
  scout). Planner confirms there's no logic in the Taskfile and adds the
  `preflight` task entry if missing (no current `task preflight` shortcut).
- **Mermaid theme.** Default theme renders fine on GitHub light/dark. No
  custom theme directive unless the planner decides one is needed.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project-level specs

- `.planning/PROJECT.md` — Core value, locked architectural decisions
  (ADR-001..005 rationale already lives here), public-repo posture, the
  pinned versions table that DOCS-04 / ADR-005 reference. Section "Key
  Decisions" enumerates the five locked decisions that DOCS-06..10 ADRs
  must capture verbatim.
- `.planning/REQUIREMENTS.md` §Repo Hygiene & Secrets (REPO-01..07) and
  §Documentation (DOCS-01..10) — 17 of 18 REQ-IDs in this phase (DOCS-03
  is already complete from Phase 3). Each REQ-ID has exact acceptance
  language; planner must satisfy literally.
- `.planning/ROADMAP.md` §Phase 6 — goal, dependencies, success criteria
  (5 SCs), parallelization note. SC #5 is load-bearing for CI scope.
- `.planning/STATE.md` — Recent decisions affecting Phase 6, including
  "Phase 6: gitleaks pre-commit MUST be installed before the first git push"
  (now retroactive, see D-08), and the D-14 prune-lint exact-text comment
  reference.

### Prior phase contracts

- `.planning/phases/01-host-foundation/01-CONTEXT.md` — D-09..D-12 establish
  the `.env` / `.env.example` / `.gitignore` narrow slice that Phase 6
  expands. D-09 explicitly notes "REPO-04 (gitleaks pre-commit) stays in
  Phase 6". Phase 1 ADR drafts (RD-01) live here too.
- `.planning/phases/02-cluster-layer/02-CONTEXT.md` — D-11 pins
  `k8s-net 172.30.0.0/16`; the Mermaid diagram in `docs/architecture.md`
  must reflect this CIDR. D-13 SAN verification context is relevant for
  ADR-002 wording.
- `.planning/phases/03-flux-hub-bootstrap/03-CONTEXT.md` — Existing
  `docs/flux-hub-spoke.md` decisions (DOCS-03 ✅) that the README must
  cross-link from the Flux bootstrap section.
- `.planning/phases/04-spoke-registration/04-CONTEXT.md` — Hub-only Flux
  reconciliation model and the P18 silent-misroute defense that ADR-004
  must capture. Live execution involved CA-data + bearer tokens — these
  are the artifacts the REPO-01 sweep needs to verify did not leak.
- `.planning/phases/05-workloads-health-rebuild/05-CONTEXT.md` — D-13..D-16
  lock destroy/rebuild UX (typed-yes confirmation, 20-min SLO); the runbook
  in DOCS-05 must mirror that UX.

### Existing code and docs

- `Taskfile.yml` — Current orchestration surface (10 tasks: build-image,
  create-clusters, delete-clusters, bootstrap-flux, register-spokes,
  deploy-examples, fix-dns, health-check, destroy, rebuild). Phase 6
  REPO-05 audit confirms it remains a thin wrapper; planner adds a
  `preflight` task entry if not already present.
- `scripts/preflight.sh` — Canonical preflight checker (PRE-01..14);
  supersedes the to-be-deleted `prereqs.sh`. README references this
  filename, not `prereqs.sh`.
- `scripts/lib/preflight-lib.sh` — Shared bash helpers
  (`pass`/`warn`/`fail`/`info`/`section`, ANSI gating, counters). The
  pre-commit hook should source this to keep output style consistent.
- `scripts/install-tools.sh` — Existing asdf plugin / version installer.
  Phase 6 extends it to (a) install gitleaks via asdf, (b) configure
  `git config core.hooksPath hooks`.
- `scripts/delete-clusters.sh:1-60` — Contains the literal "INTENTIONALLY
  NOT calling `docker system prune` or `docker builder prune`" sentinel
  that the prune-lint greps. Do not touch this comment in Phase 6.
- `tests/bats/destroy-rebuild-01-static.bats:175-188` — Existing prune-lint
  bats test. CI runs THIS test verbatim (D-12); do not duplicate the grep
  in the workflow.
- `tests/bats/test_helper.bash` — Existing helper conventions
  (`require_live`, `require_live_destructive`); irrelevant to CI but useful
  for the planner to understand bats invocation.
- `docs/flux-hub-spoke.md` — DOCS-03 ✅. README links here from the Flux
  bootstrap section. Phase 6 must NOT contradict it.
- `docs/wsl-networking.md` — HOST-07 docs from Phase 1. README's Windows
  prereqs / WSL config sections cross-link here for the mirrored→NAT
  fallback procedure.
- `.env.example` — Existing per Phase 1 D-09..D-11. REPO-03 expects this
  to "document every required key with placeholder values and a one-line
  description"; Phase 6 verifies the contract is whole and the placeholders
  are gitleaks-allow-rule friendly.
- `.gitignore` — Existing narrow slice from Phase 1 D-12. Phase 6 D-16
  expands it.
- `prereqs.sh` and `starter.md` (repo root) — to be deleted in this phase
  (D-13, D-14). Reference NOW only because the README authoring may want
  to confirm the supersession history before removing them.

### External references to verify during research / planning

- **gitleaks v8.x** — current stable line, `gitleaks detect` invocation for
  staged changes vs full repo, `--log-opts='--all'` semantics, configuration
  file format (`.gitleaks.toml`) for allow-rules, default ruleset coverage
  for GitHub PATs and the placeholder tokens in `.env.example`.
- **asdf-plugin-gitleaks** — confirm a maintained asdf plugin exists and is
  compatible with asdf v0.18+ Go-rewrite (the project's pinned line); pick
  the plugin source URL.
- **Flux CRD schemas via datreeio/CRDs-catalog** — confirm current SHA
  covers `HelmRelease`, `Kustomization` (toolkit + native),
  `GitRepository`, `Bucket`, `Receiver`. Note that "Kustomization" is a
  collision-prone name; the workflow may need `--schema-location` ordered
  carefully.
- **kubeconform invocation patterns** — `--strict`, `--ignore-filename-pattern`
  for kustomize files that aren't Kubernetes resources, summary output for
  CI logs.
- **shellcheck severity levels** — current best practice for a bash-only
  scripts dir; existing scripts pass at default.
- **markdownlint-cli vs markdownlint-cli2** — current conventions, config
  file naming, and rule disablers (MD013 line-length is the usual relax).
- **GitHub Actions** — pinning `actions/checkout`, `actions/cache`,
  `actions/setup-go` (gitleaks alt path), `bats-core/bats-action` versions
  to stable SHAs, branch-protection setup via the GitHub UI vs `gh api`.
- **Mermaid syntax** — current GitHub-rendered Mermaid block conventions;
  hub-spoke topology likely uses `flowchart LR` or `graph LR` with
  subgraphs per cluster.
- **ADR template (lightweight Status/Context/Decision/Consequences)** — pick
  authoritative form (Michael Nygard's original 2011 post / `adr.github.io`)
  for citation in the README pointer.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- `scripts/lib/preflight-lib.sh` — source this in `hooks/pre-commit` for
  `section`/`pass`/`warn`/`fail`/`info` so the gitleaks hook output matches
  the rest of the project's voice.
- `tests/bats/destroy-rebuild-01-static.bats:175-188` — existing prune-lint
  test. CI calls it verbatim per D-12; planner does not author a new lint.
- `Taskfile.yml` — already a thin wrapper around `scripts/*`. Planner adds
  at most a `preflight` task entry; no logic.
- `.env.example` — Phase 1 already documents `GITHUB_OWNER`, `GITHUB_REPO`,
  `GITHUB_TOKEN` with placeholder values. Phase 6 confirms completeness for
  REPO-03.
- `.gitignore` — Phase 1 narrow slice (`.env`, `.env.local`, `.env.*.local`,
  `CLAUDE.local.md`, `.claude/settings.local.json`). Phase 6 D-16 appends
  targeted additions only.

### Established Patterns

- **Bash scripts use `#!/usr/bin/env bash` + `set -u` (NOT `-e`)** — collect
  failures end-to-end. The `hooks/pre-commit` script should follow.
- **ANSI colors gated on `[[ -t 1 ]]`** — degrade to plain text in non-TTY
  contexts (CI). The gitleaks hook output should follow.
- **`Taskfile.yml` is the single orchestration surface** — all logic in
  `scripts/`, Taskfile invokes scripts. Phase 6 REPO-05 confirms this stays
  true; no new logic in `Taskfile.yml`.
- **Public-safe by default** — no real tokens, kubeconfigs, CA keys, or
  client certs anywhere in the tracked tree. Phase 6 D-15 verifies and
  D-08 enforces forward.
- **`.tool-versions` is the single source of truth for tool pinning** —
  Phase 6 D-07 adds `gitleaks` to the file rather than hard-coding a
  version in `install-tools.sh`.
- **Existing scripts always print remediation in failure messages** —
  the gitleaks hook output and CI failure messages should follow the same
  pattern: tell the user exactly which command to run next.
- **`docs/` is a flat directory** — no nested category folders so far
  (`docs/architecture.md`, `docs/flux-hub-spoke.md`, etc.). Phase 6's
  ADRs go under `docs/adr/` (the only nested subdirectory; locked by
  starter.md and ROADMAP).

### Integration Points

- `scripts/install-tools.sh` extends to install gitleaks (via asdf plugin)
  AND run `git config core.hooksPath hooks` once.
- `Taskfile.yml` may gain a `preflight` task entry for symmetry with the
  README walkthrough (the script already exists; only the task wrapper is
  new). Planner confirms.
- `.github/workflows/ci.yml` is a NEW file — no existing GitHub Actions in
  the repo. Branch protection on `main` is configured via the GitHub UI or
  `gh api` after the workflow lands and runs green at least once.
- README cross-links to: `docs/architecture.md` (DOCS-02), `docs/gpu-notes.md`
  (DOCS-04), `docs/rebuild-runbook.md` (DOCS-05), `docs/flux-hub-spoke.md`
  (DOCS-03 ✅), `docs/wsl-networking.md` (HOST-07 ✅), and the five ADRs.
- `hooks/pre-commit` is a NEW path. `core.hooksPath = hooks` makes git look
  there instead of `.git/hooks/`. The hook is committed; team members get it
  automatically after `git pull` + `bash scripts/install-tools.sh`.

</code_context>

<specifics>
## Specific Ideas

- README TL;DR should answer "what is this and what does `task rebuild` get
  me" in 3-5 lines, before any prereq detail.
- The fresh-clone path in the README must mirror the ROADMAP / starter.md
  ordering literally: Windows prereqs → WSL config → Docker install → NVIDIA
  setup → tools install → cluster creation → Flux bootstrap → spoke
  registration → example deploy → teardown. No reorder, even if logically
  some steps could be grouped differently.
- The Mermaid topology diagram is the FIRST visual artifact a new reader
  encounters in the README (linked from architecture.md). Make sure the
  diagram includes the API ports (6443/6444/6445), `--gpus all` annotation
  on spoke-ml, and the `spec.kubeConfig` arrows from hub into each spoke.
- ADR ordering matches the slugs locked in `starter.md` and ROADMAP:
  0001 single-WSL2 + shared-Docker-network, 0002 k3d-over-Kind, 0003
  Flux-over-ArgoCD (with the ApplicationSet trade-off), 0004 hub-only Flux
  control plane, 0005 k3s `v1.34.6-k3s1` + CUDA 12.8+ pin.
- ADR-005 must explicitly note that the v1.34.6-k3s1 line is a "current line"
  pin (not LTS) and the CUDA 12.8+ floor is forced by RTX 5090 sm_120 Blackwell.
- The runbook's expected timings should reference the Phase 5 result
  (warm-cache rebuild completed in 190 seconds per PROJECT.md). Use that
  as the SLO baseline for the runbook's "expected wall-clock" column.
- gitleaks one-shot scan output during this phase should be saved to a
  scratch path (`/tmp/karyon-gitleaks-history.json` or similar), reviewed,
  then discarded — DO NOT commit the report.
- The `hooks/pre-commit` script should fail fast (exit 1) on any gitleaks
  finding and print the offending file + line range, not the secret value
  itself.
- CI workflow file name is `.github/workflows/ci.yml` (singular `ci.yml`,
  not `lint.yml` or per-job files). One workflow with multiple jobs runs
  in parallel and the dashboard stays clean.
- markdownlint config should at minimum disable MD013 (line-length); the
  CONTEXT/PLAN/REQUIREMENTS docs use natural-prose long lines.
- The `.gitleaks.toml` allow-list should specifically allow:
  - `.env.example` placeholder values (e.g., `ghp_REPLACE_WITH_PAT_WITH_repo_SCOPE`)
  - SHA-looking strings in commit-history references inside CONTEXT.md
  - any base64 in `examples/*` (podinfo manifests have nothing sensitive but
    long base64-looking digests may show up)

</specifics>

<deferred>
## Deferred Ideas

- **README badges** (CI status, license, etc.) — nice-to-have; can land
  in a follow-up PR after CI is green and the repo gets a license file.
- **GitHub Pages / docs site** — not required; flat `docs/` rendered on
  GitHub is sufficient for v1 audience.
- **CONTRIBUTING.md** — single-author repo; defer until external
  contribution becomes a real workflow.
- **Release tagging strategy / CHANGELOG** — no release cadence yet;
  v0.18 milestone closure may surface this need separately.
- **Mermaid dark-mode theme directive** — default rendering works; revisit
  if a future docs theme demands it.
- **Branch-protection-as-code** (e.g., GitHub Probot, Settings App) —
  manual GitHub UI configuration is fine for a single-author repo.
- **Pre-commit hooks for shellcheck / markdownlint locally** — CI catches
  these; local-only would be ergonomic but adds tool surface to the dev
  box. Reconsider if CI feedback loop becomes painful.
- **scratch/ ignored directory convention** — could be useful (option C in
  the .gitignore question) but introduces a new convention; defer.
- **`docs/contributing.md`** for branch-protection setup steps and CI flow
  documentation — only if the rebuild-runbook plus the README leave a real
  gap.
- **Additional ADRs beyond the locked five** (e.g., RD-01 PRE-14 trap-
  cleanup decision, D-14 cache-preservation comment as a sentinel) —
  decisions are captured in the relevant CONTEXT.md files; promoting them
  to formal ADRs is overkill for v1. Reconsider if any of those decisions
  evolves.
- **`.dockerignore`** — repo doesn't currently `docker build` from repo
  root (only from `images/`); not needed.
- **Real secret management (SOPS / age)** — SECRETS-01..02 already in v2
  REQUIREMENTS.

</deferred>

---

*Phase: 6-repo-hygiene-docs-adrs*
*Context gathered: 2026-04-28*
