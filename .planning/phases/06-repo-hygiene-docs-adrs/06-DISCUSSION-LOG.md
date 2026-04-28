# Phase 6: Repo Hygiene + Docs + ADRs - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-28
**Phase:** 6-repo-hygiene-docs-adrs
**Areas discussed:** Docs voice + ADR template, Secret-scan toolchain, CI workflow scope, Cleanup + audit scope

---

## Docs voice + ADR template

### Q1: README style

| Option | Description | Selected |
|--------|-------------|----------|
| Hybrid quickstart + reference | TL;DR + locked fresh-clone path on top, per-task reference sections below. Best for both first-encounter and returning readers. | ✓ |
| Narrative tutorial | Linear walkthrough end-to-end. Easiest first-read but slow to navigate. | |
| Sectioned reference | Headings per topic, no narrative. Fastest for returning users; cold for first read. | |

**User's choice:** Hybrid quickstart + reference

**Notes:** Recommended option accepted. Matches the audience brief (author + people mirroring the setup).

### Q2: ADR template

| Option | Description | Selected |
|--------|-------------|----------|
| Lightweight 3-section | Status / Context / Decision / Consequences. Punchy, one-screen, matches ROADMAP phrasing. | ✓ |
| Nygard classic | Same plus explicit Status field for evolution. | |
| MADR | Adds Considered Options + Drivers + Pros/Cons. Heavyweight; overkill for already-locked decisions. | |

**User's choice:** Lightweight 3-section

**Notes:** Effectively Status / Context / Decision / Consequences with `Status: Accepted` as default for v1 ADRs. PROJECT.md already holds the rationale, so a heavyweight MADR template would duplicate.

### Q3: Mermaid scope

| Option | Description | Selected |
|--------|-------------|----------|
| Topology only | One diagram: hub-flux + spoke-ml + spoke-apps on k8s-net 172.30.0.0/16, API ports, controllers, spec.kubeConfig arrows. | ✓ |
| Topology + reconcile flow | Adds a sequence diagram for the GitOps reconcile path. | |
| Topology + reconcile + GPU contract | Adds a third diagram for the 3-part GPU contract. Likely overlaps with gpu-notes prose. | |

**User's choice:** Topology only

**Notes:** Other concepts get prose in their dedicated docs (flux-hub-spoke.md, gpu-notes.md).

### Q4: Runbook layout

| Option | Description | Selected |
|--------|-------------|----------|
| Linear steps + failure-mode appendix | Numbered procedure with timings on top, failure catalog at bottom. | ✓ |
| Interleaved | Each step lists its own failure modes inline. | |
| Separate troubleshooting doc | Runbook stays purely procedural; sibling troubleshooting doc owns failures. | |

**User's choice:** Linear steps + failure-mode appendix

**Notes:** Easy to skim mid-incident; SLO baseline 190 seconds (warm cache) per Phase 5.

---

## Secret-scan toolchain

### Q1: Scanner choice

| Option | Description | Selected |
|--------|-------------|----------|
| gitleaks | Single Go binary, asdf-installable, default ruleset covers GitHub PATs / AWS keys / high-entropy strings. | ✓ |
| detect-secrets | Yelp's Python tool. Adds Python dep; baseline-file workflow. | |

**User's choice:** gitleaks

**Notes:** Confirms PROJECT.md and STATE.md prior framing.

### Q2: Hook framework

| Option | Description | Selected |
|--------|-------------|----------|
| Native git hook via core.hooksPath | Commit hooks/pre-commit; install-tools.sh runs `git config core.hooksPath hooks`. Zero new dependencies. | ✓ |
| pre-commit (Python) | Industry-standard; pulls in Python + pip. | |
| lefthook (Go) | Single-binary alternative; new dependency. | |

**User's choice:** Native git hook via core.hooksPath

**Notes:** Minimum new surface, consistent with bash-only script style.

### Q3: gitleaks install path

| Option | Description | Selected |
|--------|-------------|----------|
| asdf via .tool-versions | Pinned, reproducible, consistent with TOOLS-01..03. | ✓ |
| go install | Adds a Go toolchain requirement. | |
| apt + checksum-pinned binary | Direct release-tarball download; new pattern. | |

**User's choice:** asdf via .tool-versions

**Notes:** Researcher confirms maintained asdf-plugin-gitleaks against asdf v0.18+ Go-rewrite line.

### Q4: History strategy

| Option | Description | Selected |
|--------|-------------|----------|
| One-shot scan + CI scan on every push | Belt-and-suspenders: catches forward leaks (hook), bypassed leaks (CI), and historical leaks (one-shot). | ✓ |
| Pre-commit only | Cheapest; weak public-repo posture. | |
| One-shot scan now, no CI scan | Skips the bypass-detection layer. | |

**User's choice:** One-shot scan + CI scan on every push

**Notes:** Repo is already public — historical scan is non-optional. Any positive triggers a leak-incident response (rotate first, then decide on history rewrite).

---

## CI workflow scope

### Q1: Job set

| Option | Description | Selected |
|--------|-------------|----------|
| Required four only | shellcheck + kubeconform + markdownlint + prune-lint + gitleaks scan. Static-only; matches REQ. | ✓ |
| Required four + bats static suites | Adds non-live bats files; risk of redundancy with static lints. | |
| Required four + Taskfile schema check | Adds `task --list-all` dry-run; small useful add. | |

**User's choice:** Required four only

**Notes:** Live tests can't run on Actions runners (no k3d / GPU host); CI scope is intentionally static.

### Q2: kubeconform schemas for Flux CRDs

| Option | Description | Selected |
|--------|-------------|----------|
| Fetch from datreeio/CRDs-catalog at workflow time | Up-to-date Flux schemas; pin SHA for reproducibility; cached. | ✓ |
| Vendor schemas in repo | Fully reproducible offline; adds noise; manual refresh. | |
| Skip on Flux CRDs | Cheapest; defeats half the value (most clusters/** is Flux YAML). | |

**User's choice:** Fetch from datreeio/CRDs-catalog at workflow time

**Notes:** Pin a specific SHA for reproducibility; researcher selects.

### Q3: CI trigger and merge-blocking

| Option | Description | Selected |
|--------|-------------|----------|
| push + PR; PR failure blocks | Branch protection on main requires green CI. Catches drift early; enforces cleanliness on merge. | ✓ |
| push to main + PR; advisory | Doesn't block merge. Undermines the gate. | |
| PR only; PR failure blocks | Skips push runs. Saves Actions minutes; loses early signal. | |

**User's choice:** push + PR; PR failure blocks

**Notes:** Matches ROADMAP REPO-07 'green on every push and PR'.

### Q4: Prune-lint enforcement in CI

| Option | Description | Selected |
|--------|-------------|----------|
| Run the existing bats test in CI | Reuse destroy-rebuild-01-static.bats verbatim; one source of truth. | ✓ |
| Inline grep in workflow | Avoids bats install on the runner; risk of drift from local test. | |
| Separate scripts/lint-prune.sh | New script wraps the grep; heaviest refactor. | |

**User's choice:** Run the existing bats test in CI

**Notes:** Install bats-core via apt on the runner; one assertion lives in one place.

---

## Cleanup + audit scope

### Q1: prereqs.sh disposition

| Option | Description | Selected |
|--------|-------------|----------|
| Delete it | Fully superseded by scripts/preflight.sh (PRE-01..14). git log preserves. | ✓ |
| Move to docs/historical/ | Preserves the original; risks accidental execution. | |
| Leave it | Worst-of-both: confusion with no new value. | |

**User's choice:** Delete it

**Notes:** README documents `task preflight` (or `bash scripts/preflight.sh`) as canonical.

### Q2: starter.md disposition

| Option | Description | Selected |
|--------|-------------|----------|
| Delete it | Superseded by PROJECT.md / REQUIREMENTS.md / ROADMAP.md; git log preserves. | ✓ |
| Move to docs/historical/ | Preserves wording for archaeology. | |
| Leave at repo root | Two competing READMEs problem. | |

**User's choice:** Delete it

**Notes:** Eliminates "two READMEs" confusion when README.md lands.

### Q3: REPO-01 sweep scope

| Option | Description | Selected |
|--------|-------------|----------|
| Full tracked tree, including .planning/ | gitleaks + curated grep across whole repo; .planning/ is intentionally tracked and part of public surface. | ✓ |
| Source tree only, exclude .planning/ | Faster but misses inadvertent paste into planning artifacts. | |
| Manual review only | Skips automation; hides behind tooling weakness. | |

**User's choice:** Full tracked tree, including .planning/

**Notes:** Phase 4 work involved real CA-data + bearer tokens during live execution — verify nothing leaked.

### Q4: .gitignore expansion (REPO-02)

| Option | Description | Selected |
|--------|-------------|----------|
| Targeted additions only | kubeconfig*/TLS material/Flux scratch/OS+IDE noise. Conservative, explainable. | ✓ |
| Comprehensive baseline (GitHub gitignore for Go/k8s + above) | Most rules don't match anything in this repo; noise. | |
| Targeted + experimental scratch dir | Adds new convention (scratch/); could be deferred. | |

**User's choice:** Targeted additions only

**Notes:** scratch/ convention left as a deferred idea; revisit if ad-hoc local artifacts become a recurring problem.

---

## Claude's Discretion

The following details were not asked but are explicitly within the planner /
researcher's discretion under the locked decisions above:

- README headings outline (within the hybrid quickstart+reference shape).
- ADR file body prose (within the lightweight Status/Context/Decision/Consequences template).
- gitleaks pinned version + asdf-plugin source URL.
- `.gitleaks.toml` allow-rules for placeholder strings + SHA-looking blobs in CONTEXT.md.
- kubeconform invocation flags (--strict, --ignore-filename-pattern, summary format).
- markdownlint config strictness (MD013 line-length is the typical relax).
- shellcheck severity level.
- Branch protection setup documentation location.
- Whether `Taskfile.yml` audit (REPO-05) requires structural changes (current scout suggests it's already a thin wrapper; planner confirms).
- Mermaid theme (default works on GitHub light/dark).

---

## Deferred Ideas

Captured for future phases / milestones (NOT in scope here):

- README badges (CI status, license).
- GitHub Pages / docs site.
- CONTRIBUTING.md (single-author repo; defer until external contribution).
- Release tagging strategy / CHANGELOG.
- Mermaid dark-mode theme directive.
- Branch-protection-as-code.
- Local pre-commit hooks for shellcheck / markdownlint.
- scratch/ ignored directory convention.
- docs/contributing.md (only if README + runbook leave a gap).
- Additional ADRs beyond the locked five.
- .dockerignore (repo doesn't currently docker-build from root).
- Real secret management (SOPS / age) — already in v2 REQ SECRETS-01..02.
