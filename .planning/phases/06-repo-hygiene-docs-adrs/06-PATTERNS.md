# Phase 6: Repo Hygiene + Docs + ADRs - Pattern Map

**Mapped:** 2026-04-28
**Files analyzed:** 26 (12 NEW source/config + 6 NEW bats + 6 MODIFIED + 2 DELETED)
**Analogs found:** 22 / 26 with strong project analogs; 4 net-new with no in-repo template (`.gitleaks.toml`, `.markdownlint.json`, `.github/workflows/ci.yml`, `docs/adr/0001..0005-*.md`)

The Phase 6 inventory in the orchestrator prompt was verified against CONTEXT.md and RESEARCH.md. No additional files were uncovered; the inventory is complete.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `hooks/pre-commit` (NEW) | git-hook bash | event-driven (on commit) | `scripts/destroy.sh` (helper-sourcing wrapper that gates on a single user-input contract) | role-match (bash hook vs. CLI wrapper, but identical sourcing/style) |
| `.gitleaks.toml` (NEW) | tool config (TOML) | static lint config | none in repo | net-new — synthesize from RESEARCH §Pitfall 1 |
| `.markdownlint.json` (NEW) | tool config (JSON) | static lint config | none in repo | net-new — synthesize from RESEARCH §Code Examples Example 3 |
| `.github/workflows/ci.yml` (NEW) | CI workflow (YAML) | event-driven (push/PR) | none in repo (first GitHub Actions in repo) | net-new — synthesize from RESEARCH §Pattern 2 |
| `docs/architecture.md` (NEW) | reference doc (Markdown + Mermaid) | static doc | `docs/flux-hub-spoke.md` (flat docs/ convention, GitHub-rendered) | exact role-match |
| `docs/gpu-notes.md` (NEW) | reference doc (Markdown) | static doc | `docs/wsl-networking.md` (multi-section reference doc with section dividers) | exact role-match |
| `docs/rebuild-runbook.md` (NEW) | runbook (Markdown) | static doc | `docs/wsl-networking.md` (numbered-step procedural style) | role-match |
| `docs/adr/0001..0005-*.md` (5 NEW ADRs) | decision record (Markdown) | static doc | none in repo (no existing ADR) | net-new — synthesize from RESEARCH §Pattern 3 (Nygard 4-section) |
| `tests/bats/repo-hygiene-01-static.bats` (NEW) | bats static-grep test | static lint | `tests/bats/destroy-rebuild-01-static.bats:13-44` (set/sourcing/literal greps) | exact |
| `tests/bats/repo-hygiene-02-taskfile.bats` (NEW) | bats static-grep test | static lint | `tests/bats/destroy-rebuild-01-static.bats:202-208` (Taskfile literal-presence check) | exact |
| `tests/bats/repo-hygiene-03-ci.bats` (NEW) | bats static-grep test | static lint | `tests/bats/destroy-rebuild-01-static.bats:46-63` (ordered-literal grep) | exact |
| `tests/bats/docs-01-readme-order.bats` (NEW) | bats static-grep test | static lint | `tests/bats/health-check-01-static.bats:20-37` (ordered-section literal grep) | exact |
| `tests/bats/docs-02-architecture.bats` (NEW) | bats static-grep test | static lint | `tests/bats/bootstrap-flux-02-docs.bats:17-34` (multi-keyword grep against doc) | exact |
| `tests/bats/docs-04-gpu-notes.bats` (NEW) | bats static-grep test | static lint | `tests/bats/bootstrap-flux-02-docs.bats:17-34` (multi-keyword grep against doc) | exact |
| `tests/bats/docs-05-runbook.bats` (NEW) | bats static-grep test | static lint | `tests/bats/destroy-rebuild-01-static.bats:129-146` (step-marker order grep) | exact |
| `tests/bats/docs-adr-template.bats` (NEW) | bats static-grep test | static lint | `tests/bats/bootstrap-flux-02-docs.bats:17-34` (template-section presence) | exact |
| `README.md` (MODIFIED) | project entry doc | static doc | none in repo (existing is placeholder) | role-match — synthesize from D-01 ordered fresh-clone path + RESEARCH §Recommended File Layout |
| `.gitignore` (MODIFIED) | repo config | static lint | self (D-12 narrow slice) — append-only | exact |
| `.env.example` (MODIFIED) | template | static config | self (Phase 1 D-09..D-11) — verify, no rewrite | exact |
| `.tool-versions` (MODIFIED) | tool pin | static config | self — append `gitleaks 8.30.1` | exact |
| `scripts/install-tools.sh` (MODIFIED) | bash installer | sequential idempotent | self §Section 5 (asdf plugin loop) and §Section 6 (per-tool install) | exact |
| `Taskfile.yml` (MODIFIED) | orchestrator | task wiring | self (existing 10 task entries, all `bash scripts/<name>.sh`) | exact |
| `prereqs.sh` (DELETED) | n/a | n/a | n/a | n/a |
| `starter.md` (DELETED) | n/a | n/a | n/a | n/a |

## Pattern Assignments

### `hooks/pre-commit` (NEW — git-hook bash)

**Analog:** `scripts/destroy.sh` (lines 1-14) for the helper-sourcing pattern, plus `scripts/lib/preflight-lib.sh` lines 11-27 for the ANSI/section helpers.

**Style conventions to inherit:**

- `#!/usr/bin/env bash` (verbatim, never `/bin/bash`).
- `set -euo pipefail` for hooks (RESEARCH §Code Examples Example 1 uses this; differs from `set -u` in `preflight.sh` because hooks are short-running and can fail-fast).
- Use the `SCRIPT_DIR` / `REPO_ROOT` resolution idiom seen in every script.
- Source `scripts/lib/preflight-lib.sh` so `section`/`pass`/`warn`/`fail`/`info`/`have` are available with consistent ANSI gating.
- Print remediation in failure messages (e.g., "run `bash scripts/install-tools.sh`").

**Imports / preamble pattern** (from `scripts/destroy.sh:1-14`):

```bash
#!/usr/bin/env bash
# scripts/destroy.sh
#
# Confirmation wrapper for the cache-preserving k3d teardown.
#
# Usage: bash scripts/destroy.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/preflight-lib.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/preflight-lib.sh"
```

**Adaptation for `hooks/pre-commit`:** the sourced library lives ONE directory deeper (`hooks/` is at the repo root, sibling to `scripts/`), so the source line resolves to `${REPO_ROOT}/scripts/lib/preflight-lib.sh` — pattern is shown in RESEARCH §Code Examples Example 1 lines 922-926.

**ANSI/section helper usage** (from `scripts/lib/preflight-lib.sh:11-27`):

```bash
if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_DIM=$'\033[2m'; C_BOLD=$'\033[1m'
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_BLUE=$'\033[34m'
else
  C_RESET=""; ...
fi

section() { printf "\n%s%s== %s ==%s\n" "$C_BOLD" "$C_BLUE" "$1" "$C_RESET"; }
pass()    { printf "  %s✓%s %s\n" "$C_GREEN" "$C_RESET" "$1"; PASS=$((PASS+1)); }
fail()    { printf "  %s✗%s %s\n" "$C_RED" "$C_RESET" "$1"; FAIL=$((FAIL+1)); FAIL_MSGS+=("$1"); }
info()    { printf "  %s·%s %s\n" "$C_DIM" "$C_RESET" "$1"; }
have()    { command -v "$1" >/dev/null 2>&1; }
```

**Tool presence guard** (verbatim from RESEARCH §Pattern 1 lines 397-400 + RESEARCH §Code Examples Example 1 lines 928-931):

```bash
if ! have gitleaks; then
  fail "gitleaks not on PATH — run 'bash scripts/install-tools.sh' to install."
  exit 1
fi
```

**Core gitleaks invocation** (verbatim from gitleaks/.pre-commit-hooks.yaml; RESEARCH §Pattern 1 lines 402-417):

```bash
section "gitleaks pre-commit scan"
if gitleaks git --pre-commit --redact --staged --verbose; then
  pass "no secrets detected in staged changes"
  exit 0
else
  fail "gitleaks detected potential secrets in staged changes."
  exit 1
fi
```

**Failure message remediation pattern (project convention from `scripts/health-check.sh:24-29`):**

```bash
fail "k3d cluster missing: ${cluster}.
   Fix: task create-clusters"
```

The hook should follow the same "what failed + Fix: <command>" pattern. RESEARCH §Pattern 1 lines 410-415 illustrate this for the gitleaks hook (multi-line `fail` message naming the .gitleaks.toml allow-rule path AND the `--no-verify` audit-loud bypass).

---

### `.gitleaks.toml` (NEW — TOML allow-rules config)

**Analog:** None in repo. Net-new from RESEARCH §Common Pitfalls §Pitfall 1 lines 738-749 and CONTEXT.md `<specifics>` 431-435.

**Excerpt to copy verbatim** (RESEARCH lines 740-749):

```toml
# .gitleaks.toml
[allowlist]
description = "False positives: placeholder tokens and CONTEXT.md SHAs"
regexes = [
  '''ghp_REPLACE_WITH_PAT_WITH_repo_SCOPE''',  # .env.example placeholder
]
paths = [
  '''\.env\.example''',                         # whole-file allow
]
# Add per-finding entries during the one-shot scan if needed.
```

**Style conventions:** triple-quoted regex strings (TOML idiom from gitleaks docs), inline `#` comments for each rule explaining WHY it is allowed (matches the project's "remediation-in-comments" pattern seen across scripts).

---

### `.markdownlint.json` (NEW — JSON lint config)

**Analog:** None in repo. Net-new from RESEARCH §Code Examples Example 3 lines 977-985 and CONTEXT.md `<specifics>` 429-430.

**Excerpt to copy verbatim** (RESEARCH lines 977-985):

```json
{
  "default": true,
  "MD013": false,
  "MD033": {
    "allowed_elements": ["br", "div"]
  },
  "MD041": true
}
```

**Style:** project default + MD013 off (long-prose docs in `.planning/` and CONTEXT files) + MD033 narrow allow-list for `<br/>` used in Mermaid table cells + MD041 ON (every top-level doc starts with an h1).

---

### `.github/workflows/ci.yml` (NEW — GitHub Actions YAML, 5 parallel jobs)

**Analog:** None in repo. Net-new from RESEARCH §Pattern 2 lines 435-517.

**Excerpt: workflow header + triggers + permissions** (RESEARCH lines 436-444):

```yaml
name: CI
on:
  push:
    branches: ['**']
  pull_request:

permissions:
  contents: read

jobs:
  ...
```

**Excerpt: shellcheck job** (RESEARCH lines 446-457):

```yaml
shellcheck:
  name: shellcheck (scripts/)
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@<pinned-sha>  # v6.0.2 — researcher pins SHA
    - uses: ludeeus/action-shellcheck@<pinned-sha>  # v2.0.0
      with:
        scandir: './scripts'
        severity: warning
```

**Excerpt: kubeconform job (the most-complex)** (RESEARCH lines 469-491):

```yaml
kubeconform:
  name: kubeconform (clusters/, examples/)
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@<pinned-sha>
    - name: Install kubeconform v0.7.0
      run: |
        curl -sSL https://github.com/yannh/kubeconform/releases/download/v0.7.0/kubeconform-linux-amd64.tar.gz \
          | sudo tar -xz -C /usr/local/bin kubeconform
        sudo chmod +x /usr/local/bin/kubeconform
    - name: Validate clusters/ and examples/
      env:
        DATREE_SHA: <pinned-sha>
      run: |
        find clusters examples -name '*.yaml' -not -name 'kustomization.yaml' \
          | xargs kubeconform \
              -strict \
              -ignore-missing-schemas \
              -skip CustomResourceDefinition,Kustomization \
              -schema-location default \
              -schema-location "https://raw.githubusercontent.com/datreeio/CRDs-catalog/${DATREE_SHA}/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json" \
              -summary
```

**Excerpt: gitleaks job needs `fetch-depth: 0`** (RESEARCH lines 503-516, plus Pitfall 3 at lines 794-807 — load-bearing):

```yaml
gitleaks-scan:
  name: gitleaks (full repo + history)
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@<pinned-sha>
      with:
        fetch-depth: 0  # CRITICAL: needed for `gitleaks git --log-opts="--all"`
    - name: Install gitleaks v8.30.1
      run: |
        curl -sSL https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_linux_x64.tar.gz \
          | sudo tar -xz -C /usr/local/bin gitleaks
        sudo chmod +x /usr/local/bin/gitleaks
    - name: Scan
      run: gitleaks git --verbose --redact --log-opts="--all"
```

**Style conventions:** every `uses:` MUST be pinned to a commit SHA with a `# v<tag>` trailing comment for human-readability + dependabot maintenance; one job per concern (no stitched lints); `permissions: contents: read` at the workflow level (least-privilege).

---

### `docs/architecture.md` (NEW — Markdown reference + Mermaid)

**Analog:** `docs/flux-hub-spoke.md` (existing, DOCS-03 ✅).

**Top-of-file h1 + intro paragraph pattern** (`docs/flux-hub-spoke.md:1-12`):

```markdown
# Flux Hub-Spoke Patch Surface

`scripts/bootstrap-flux.sh` runs `flux bootstrap github --path clusters/hub-flux` against
the `k3d-hub-flux` cluster. That single command creates (or reuses) the GitHub repo, ...

This document explains the three rules that govern hand-editing anything under
`clusters/hub-flux/flux-system/`. ...
```

**Style conventions to inherit:**

- Lead with `# <Doc Title>` h1 (MD041 enforced).
- Followed by a short orientation paragraph naming the load-bearing script/file/concept.
- Use `## Section`-level headings; tables with `| Header | Header |` for structured data.
- Cross-reference paths in inline backticks (`scripts/...`, `clusters/...`).
- For code blocks containing YAML, use ` ```yaml ` fences.

**Mermaid block specifics for this file** (RESEARCH §Pattern 4 lines 603-647): use ` ```mermaid ` fence with `flowchart LR`, one subgraph per cluster on `k8s-net 172.30.0.0/16`, four flux-system controllers, `spec.kubeConfig` arrows. The full Mermaid example is verbatim in RESEARCH lines 604-646.

**Lint requirements** (from RESEARCH §Pitfall 4 lines 814-829): MUST start with h1 (NOT the Mermaid block) so MD041 passes.

---

### `docs/gpu-notes.md` (NEW — Markdown reference)

**Analog:** `docs/wsl-networking.md` (existing, DOCS-03-style sibling).

**Top-of-file pattern** (`docs/wsl-networking.md:1-25`):

```markdown
# WSL2 Networking: Mirrored Mode, NAT Mode, and the Migration Procedure

## What Is mirrored Mode and Why It Breaks Docker Custom Networks

WSL2 supports two networking modes: ...

This breaks Docker custom networks (such as the `k8s-net` bridge network used by this project). ...

This is a known upstream issue tracked at `moby/moby#48201`. ...

**v1 of this project requires NAT mode.** Mirrored mode is not supported and will cause
`scripts/preflight.sh` to exit 1 with an actionable error message.

---
```

**Style conventions to inherit:**

- h1 title, then `## Section` h2s.
- `**v1 of this project requires X.**` as bold lead-in for hard rules.
- `---` (horizontal-rule) separators between major sections (visible in `wsl-networking.md` lines 25, 39 — used consistently in repo docs).
- Code blocks fenced with language hints (` ```bash `, ` ```ini `, ` ```yaml `).
- Cross-link to other docs and ADRs with relative paths (`docs/wsl-networking.md`, `docs/adr/0005-...`).

**Required content** (CONTEXT.md DOCS-04 + REQUIREMENTS): 3-part k3d GPU contract (daemon.json default-runtime + Ubuntu base image + containerd config.toml.tmpl), RTX 5090 + sm_120 + CUDA 12.8+ floor.

**bats verifier keywords** (from RESEARCH lines 1222): `default-runtime`, `nvidia/cuda`, `config.toml.tmpl`, `RTX 5090`, `sm_120`, `12.8` — these MUST literally appear in the file.

---

### `docs/rebuild-runbook.md` (NEW — Markdown procedural runbook)

**Analog:** `docs/wsl-networking.md` for the numbered-step procedural style (lines 71-80 use `**Step 1:**` / `**Step 2:**` patterns), combined with the literal step markers from `scripts/rebuild.sh:49-79` (the `>>> step <name>` lines).

**Step-numbering pattern** (`docs/wsl-networking.md:71-79`):

```markdown
## Migration: mirrored to NAT (30-second fix)

Follow these five steps exactly. Do not skip the wait in step 3 — the Hyper-V VM must fully
stop before WSL will pick up the new configuration.

**Step 1:** Edit `%USERPROFILE%\.wslconfig` in a text editor (Notepad, VS Code, etc.).
Set or add the following line in the `[wsl2]` section:

```ini
networkingMode=NAT
```
```

**Required step markers in document** (from `scripts/rebuild.sh:49,55,58,69,72,75,78` AND `tests/bats/destroy-rebuild-01-static.bats:131-145`):

```text
>>> step preflight
>>> step destroy
>>> step create-clusters
>>> step bootstrap-flux
>>> step register-spokes
>>> step deploy-examples
>>> step health-check
```

The runbook MUST mirror these seven step names in linear order (D-04 + RESEARCH §Phase Requirements DOCS-05) and embed expected wall-clock per step. Phase 5's `rebuild elapsed seconds: 190` (`scripts/rebuild.sh:82`) is the SLO baseline.

**Failure-mode appendix style:** project convention is "Common failures" keyed by symptom — see RESEARCH §Specifics line 91-93 (CoreDNS NodeHosts → `task fix-dns`; missing GPU capacity → IMG-04; PR TLS-SAN mismatch → recreate the cluster).

---

### `docs/adr/0001..0005-*.md` (5 NEW ADRs — Nygard 4-section)

**Analog:** None in repo (no existing ADR). Net-new from RESEARCH §Pattern 3 lines 552-591.

**Excerpt to copy verbatim per ADR (Nygard 4-section)** (RESEARCH lines 552-591):

```markdown
# 2. k3d Over Kind

## Status

Accepted (2026-04-22)

## Context

This is a local Kubernetes lab on Windows 11 + WSL2 with an RTX 5090 GPU.
The cluster runtime needs to support: GPU pass-through, multi-cluster on a
shared Docker network, and rebuild-from-zero in under 20 minutes. The two
candidates are k3d (k3s-on-docker) and Kind (kubernetes-in-docker).

## Decision

Use k3d for all clusters in the lab.

## Consequences

**Easier:**
- Official GPU support via `--gpus all` flag (no Kind workaround needed).
- Lower idle RAM per cluster (~250 MB vs Kind's ~500 MB control plane).
...

**Harder:**
- k3s has a smaller community than upstream Kubernetes; ...
...

**No-change:**
- Both runtimes are local-only; cloud migration is explicitly out of scope.
```

**Style conventions:**

- Filename: `NNNN-kebab-case-slug.md`. Slugs locked in CONTEXT.md `<decisions>` Claude's-Discretion list:
  - `0001-single-wsl2-shared-docker-network.md`
  - `0002-k3d-over-kind.md`
  - `0003-flux-over-argocd.md`
  - `0004-hub-only-flux-control-plane.md`
  - `0005-kubernetes-version-pin.md`
- h1 = `# N. <Title Case Title>` (where N is the ADR number stripped of leading zeros, e.g., `# 2. k3d Over Kind`).
- Exactly four sections: `## Status`, `## Context`, `## Decision`, `## Consequences`.
- Status default = `Accepted (<date>)`.
- Consequences sub-headings: bold `**Easier:**`, `**Harder:**`, `**No-change:**`.
- No "Considered Options" / no MADR pros-cons list (D-02 explicit).

**Source content for the five ADRs:** PROJECT.md "Key Decisions" section (per CONTEXT.md `<canonical_refs>`) — the planner copies the locked rationale into each ADR.

---

### `tests/bats/repo-hygiene-01-static.bats` (NEW — bats static-grep, REPO-02/03/04)

**Analog:** `tests/bats/destroy-rebuild-01-static.bats` lines 1-44 + 175-200.

**Header + setup pattern** (`tests/bats/destroy-rebuild-01-static.bats:1-11`):

```bash
#!/usr/bin/env bats
# tests/bats/destroy-rebuild-01-static.bats
# Phase 5 static contract for destructive wrappers and strict rebuild chain.

load 'test_helper'

setup() {
  DESTROY_SCRIPT="${REPO_ROOT}/scripts/destroy.sh"
  REBUILD_SCRIPT="${REPO_ROOT}/scripts/rebuild.sh"
  TASKFILE="${REPO_ROOT}/Taskfile.yml"
}
```

**Strict-mode + sourcing assertion pattern** (lines 13-24):

```bash
@test "DESTROY-01: destroy and rebuild wrappers exist, are strict, and source preflight helpers" {
  [ -f "$DESTROY_SCRIPT" ]
  [ -f "$REBUILD_SCRIPT" ]
  run grep -E '^set -euo pipefail' "$DESTROY_SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- 'preflight-lib.sh' "$DESTROY_SCRIPT"
  [ "$status" -eq 0 ]
}
```

**Negative-grep (forbidden literal) pattern** (lines 175-181):

```bash
@test "DESTROY-03/04: destroy and rebuild wrappers do not execute docker system prune" {
  [ -f "$DESTROY_SCRIPT" ]
  [ -f "$REBUILD_SCRIPT" ]
  for f in "$DESTROY_SCRIPT" "$REBUILD_SCRIPT"; do
    run bash -c "grep -v '^[[:space:]]*#' '$f' | grep -F -- 'docker system prune'"
    [ "$status" -ne 0 ]
  done
}
```

**Apply to `repo-hygiene-01-static.bats`:** assert `hooks/pre-commit` exists, has shebang, sources `preflight-lib.sh`, invokes `gitleaks git --pre-commit`. Assert `.gitignore` contains each D-16 literal. Assert `.env.example` contains the 3 required keys. Use `grep -F -- '<literal>'` for exact-match content (the project convention).

---

### `tests/bats/repo-hygiene-02-taskfile.bats` (NEW — bats, REPO-05 thin-wrapper check)

**Analog:** `tests/bats/destroy-rebuild-01-static.bats:202-208` (the existing REPO-05 stub).

**Excerpt** (lines 202-208):

```bash
@test "REPO-05: Taskfile wires destroy and rebuild tasks" {
  [ -f "$TASKFILE" ]
  run grep -F -- 'destroy:' "$TASKFILE"
  [ "$status" -eq 0 ]
  run grep -F -- 'rebuild:' "$TASKFILE"
  [ "$status" -eq 0 ]
}
```

**Adaptation for thin-wrapper assertion** (RESEARCH §Validation Architecture line 1217 — REPO-05 spec): grep `Taskfile.yml` and assert no line matches `kubectl|docker|k3d|flux ` outside a `cmds:` block. Use the negative-grep pattern from `destroy-rebuild-01-static.bats:175-181` adapted to scan Taskfile lines.

---

### `tests/bats/repo-hygiene-03-ci.bats` (NEW — bats, REPO-07 CI workflow structure)

**Analog:** `tests/bats/destroy-rebuild-01-static.bats:46-63` (ordered-literal grep over a script).

**Ordered-grep pattern** (lines 46-63):

```bash
@test "DESTROY-05: rebuild wrapper runs the strict script chain in order" {
  [ -f "$REBUILD_SCRIPT" ]
  previous=0
  for literal in \
    'bash "${SCRIPT_DIR}/preflight.sh"' \
    'bash "${SCRIPT_DIR}/destroy.sh"' \
    ...
  do
    line="$(grep -nF -- "$literal" "$REBUILD_SCRIPT" | head -1 | cut -d: -f1)"
    [ -n "$line" ]
    [ "$line" -gt "$previous" ]
    previous="$line"
  done
}
```

**Adaptation for CI workflow:** assert `.github/workflows/ci.yml` exists; grep for the 5 job names (`shellcheck`, `markdownlint`, `kubeconform`, `prune-lint-bats`, `gitleaks-scan`); assert `fetch-depth: 0` is present in the gitleaks job step. Reuse the line-number-ordering check from this analog if order matters; for job presence alone use the simpler `grep -F` pattern from `destroy-rebuild-01-static.bats:13-24`.

---

### `tests/bats/docs-01-readme-order.bats` (NEW — bats, DOCS-01 heading order)

**Analog:** `tests/bats/health-check-01-static.bats:20-37` (ordered-section literal grep over a script).

**Excerpt** (lines 20-37):

```bash
@test "HEALTH-02..07: health-check sections appear in required order" {
  [ -f "$SCRIPT" ]
  previous=0
  for literal in \
    'Clusters and nodes' \
    'Flux controllers' \
    'Spoke Kustomizations' \
    'Hub DNS probe' \
    'GPU capacity' \
    'TLS SANs' \
    'Workload proofs'
  do
    line="$(grep -nF -- "$literal" "$SCRIPT" | head -1 | cut -d: -f1)"
    [ -n "$line" ]
    [ "$line" -gt "$previous" ]
    previous="$line"
  done
}
```

**Adaptation for README:** the literals are the 10 fresh-clone-path section titles in locked order (CONTEXT.md `<specifics>` 405-409 + RESEARCH §Phase Requirements DOCS-01): Windows prereqs → WSL config → Docker install → NVIDIA setup → tools install → cluster creation → Flux bootstrap → spoke registration → example deploy → teardown.

---

### `tests/bats/docs-02-architecture.bats` (NEW — bats, DOCS-02 Mermaid + nodes)

**Analog:** `tests/bats/bootstrap-flux-02-docs.bats:17-34` (multi-keyword grep against doc).

**Excerpt** (lines 17-34):

```bash
@test "FLUX-05 / DOCS-03: docs/flux-hub-spoke.md documents the 3 patch-surface rules" {
  [ -f "$DOC" ]
  # Rule 1: gotk-*.yaml are bootstrap-managed
  run grep -F -- 'gotk-components.yaml' "$DOC"
  [ "$status" -eq 0 ]
  run grep -F -- 'gotk-sync.yaml' "$DOC"
  [ "$status" -eq 0 ]
  run grep -F -- 'bootstrap-managed' "$DOC"
  [ "$status" -eq 0 ]
  # Rule 2: kustomization.yaml IS the patch surface (case-insensitive - docs prose)
  run grep -iE 'patch surface' "$DOC"
  [ "$status" -eq 0 ]
  ...
}
```

**Adaptation for architecture.md:** assert ` ```mermaid ` fence exists; grep for required nodes (`hub-flux`, `spoke-ml`, `spoke-apps`, `6443`, `6444`, `6445`, `k8s-net`, `172.30.0.0/16`, `spec.kubeConfig`) per RESEARCH lines 1221.

---

### `tests/bats/docs-04-gpu-notes.bats` (NEW — bats, DOCS-04 keyword presence)

**Analog:** `tests/bats/bootstrap-flux-02-docs.bats:17-34` (same multi-keyword grep pattern).

**Adaptation:** required literals per RESEARCH line 1222 — `default-runtime`, `nvidia/cuda`, `config.toml.tmpl`, `RTX 5090`, `sm_120`, `12.8`. Use `grep -F -- '<literal>'` for each.

---

### `tests/bats/docs-05-runbook.bats` (NEW — bats, DOCS-05 steps + timings + appendix)

**Analog:** `tests/bats/destroy-rebuild-01-static.bats:129-146` (step-marker order grep).

**Excerpt** (lines 129-146):

```bash
@test "DESTROY-05: rebuild step markers appear in strict order" {
  [ -f "$REBUILD_SCRIPT" ]
  previous=0
  for literal in \
    '>>> step preflight' \
    '>>> step destroy' \
    '>>> step create-clusters' \
    '>>> step bootstrap-flux' \
    '>>> step register-spokes' \
    '>>> step deploy-examples' \
    '>>> step health-check'
  do
    line="$(grep -nF -- "$literal" "$REBUILD_SCRIPT" | head -1 | cut -d: -f1)"
    [ -n "$line" ]
    [ "$line" -gt "$previous" ]
    previous="$line"
  done
}
```

**Adaptation for rebuild-runbook.md:** same 7 step names in order; plus assert at least one `<N> seconds` timing literal; plus assert a `## Common failures` (or similar) appendix heading per RESEARCH line 1223.

---

### `tests/bats/docs-adr-template.bats` (NEW — bats, DOCS-06..10 template + Status: Accepted)

**Analog:** `tests/bats/bootstrap-flux-02-docs.bats:17-34` (multi-section presence check).

**Adaptation:** loop over the 5 ADR file paths; for each, assert `## Status`, `## Context`, `## Decision`, `## Consequences` headings exist (use `grep -F`) and `Accepted` literal appears in the first 10 lines (per D-02 default). Pattern (use `tests/bats/bootstrap-flux-02-docs.bats:17-34` literal-presence style). Require: `## Status`, `## Context`, `## Decision`, `## Consequences`, `Accepted`.

---

### `README.md` (MODIFIED — full rewrite)

**Analog:** None (current placeholder). Synthesize from CONTEXT.md D-01 + RESEARCH §Recommended File Layout.

**Style conventions to inherit from existing docs** (`docs/flux-hub-spoke.md`, `docs/wsl-networking.md`):

- h1 + orientation paragraph + `## Section` h2s.
- 60-second TL;DR up top (CONTEXT.md `<specifics>` 401-403): "what is this and what does `task rebuild` get me" in 3-5 lines.
- Locked fresh-clone path (10 ordered sections per CONTEXT.md `<specifics>` 405-409 — see DOCS-01 verifier above).
- Per-task reference sections keyed off `Taskfile.yml` (10 tasks: build-image, create-clusters, delete-clusters, bootstrap-flux, register-spokes, deploy-examples, fix-dns, health-check, destroy, rebuild — and `preflight` if planner adds the entry).
- Cross-link to `docs/architecture.md`, `docs/gpu-notes.md`, `docs/rebuild-runbook.md`, `docs/flux-hub-spoke.md`, `docs/wsl-networking.md`, and the 5 ADRs (per CONTEXT.md `<code_context>` 388-390).

**Lint requirements** (RESEARCH §Pitfall 4): start with h1 (MD041); MD013 disabled in `.markdownlint.json`.

---

### `.gitignore` (MODIFIED — append D-16 expansion)

**Analog:** self (existing 5-line slice from Phase 1 D-12).

**Existing content** (`/.gitignore` lines 1-7):

```gitignore
CLAUDE.local.md
.claude/settings.local.json

# Secrets — NEVER commit .env with real values
.env
.env.local
.env.*.local
```

**Append (verbatim from RESEARCH §Code Examples Example 4 lines 996-1027):**

```gitignore
# Phase 6 D-16 expansion ──────────────────────────────────

# Kubeconfig artifacts (fix-coredns / register-spokes scratch)
kubeconfig
kubeconfig*
*.kubeconfig

# TLS material (anything generated locally)
*.pem
*.key
*.crt

# Flux scratch from bootstrap retries
flux-system/identity*

# OS / IDE noise
.DS_Store
*.swp
*.swo
.idea/
.vscode/
```

**Style:** group with section divider comment + per-group blank-line + per-group inline comment naming the source decision (D-16 / phase reference). Matches the existing "Secrets — NEVER commit .env" header pattern.

---

### `.env.example` (MODIFIED — verify only)

**Analog:** self (existing 3 keys per Phase 1 D-09..D-11).

**Action:** verify completeness per REPO-03 acceptance ("documents every required key with placeholder values and a one-line description"). Per RESEARCH lines 350-352, the contract is already whole; Phase 6 only confirms placeholders are gitleaks-allow-rule-friendly (CONTEXT.md `<specifics>` 432: literal `ghp_REPLACE_WITH_PAT_WITH_repo_SCOPE` should match the `.gitleaks.toml` allowlist).

**No structural pattern change.**

---

### `.tool-versions` (MODIFIED — append `gitleaks 8.30.1`)

**Analog:** self (existing 9 lines, one-tool-per-line).

**Existing content (`/.tool-versions:1-9`):**

```text
kubectl 1.35.0
helm 3.20.2
flux2 2.8.6
k3d 5.8.3
k9s 0.50.18
task 3.50.0
jq 1.8.1
yq 4.53.2
asdf 0.18.1
```

**Append:**

```text
gitleaks 8.30.1
```

**Style:** one space-separated `<tool> <version>` per line, no comments (matches existing format).

---

### `scripts/install-tools.sh` (MODIFIED — extend with Section 7 + Section 8)

**Analog:** self §Section 5 (asdf plugin loop, lines 86-102) and §Section 6 (per-tool install, lines 105-148).

**Section 5 plugin-loop pattern** (lines 95-102):

```bash
section "asdf plugins"
for plugin in kubectl helm flux2 k3d k9s task jq yq; do
  if asdf plugin list 2>/dev/null | grep -qx "$plugin"; then
    info "already done, skipping: asdf plugin ${plugin}"
  else
    asdf plugin add "$plugin"
    pass "installing: asdf plugin ${plugin}"
  fi
done
```

**Adaptation:** add `gitleaks` to the plugin-loop iteration (one-line change at line 95: `for plugin in kubectl helm flux2 k3d k9s task jq yq gitleaks; do`) per RESEARCH lines 247.

**Section 7 (NEW) — gitleaks plugin guarantee + Section 8 — git core.hooksPath wiring** (verbatim from RESEARCH §Code Examples Example 5 lines 1041-1064):

```bash
# ---------------------------------------------------------------------------
# Section 7: gitleaks asdf plugin (D-07)
# Adds the gitleaks plugin if not present. Tool version pinned in .tool-versions.
# ---------------------------------------------------------------------------
section "asdf plugin gitleaks"
if asdf plugin list 2>/dev/null | grep -qx gitleaks; then
  info "already done, skipping: asdf plugin gitleaks"
else
  asdf plugin add gitleaks
  pass "installing: asdf plugin gitleaks"
fi

# ---------------------------------------------------------------------------
# Section 8: Git core.hooksPath wiring (D-06; REQ-REPO-04)
# Idempotent: only writes if value differs.
# ---------------------------------------------------------------------------
section "Git core.hooksPath = hooks"
current_hooksPath="$(git -C "$REPO_ROOT" config --local core.hooksPath 2>/dev/null || echo '')"
if [[ "$current_hooksPath" == "hooks" ]]; then
  info "already done, skipping: core.hooksPath = hooks"
else
  git -C "$REPO_ROOT" config --local core.hooksPath hooks
  pass "set: git config --local core.hooksPath hooks"
fi
```

**Style:** mirrors §Section 4 (lines 70-83) idempotent-grep-guard pattern (check current state via `grep -qF` or `==` comparison; emit `info "already done, skipping: ..."` OR `pass "installing: ..."`).

---

### `Taskfile.yml` (MODIFIED — possibly add `preflight:` task)

**Analog:** self (existing 10 task entries, lines 4-52).

**Excerpt of existing task block style** (`Taskfile.yml:4-7`):

```yaml
build-image:
  desc: Build the karyon/k3s-cuda custom image (IMG-01..06)
  cmds:
    - bash scripts/build-image.sh
```

**Adaptation (if planner adds `preflight:`):**

```yaml
preflight:
  desc: Read-only environment check; idempotent (PRE-01..14)
  cmds:
    - bash scripts/preflight.sh
```

**Style:** every entry is `<name>:` + `desc:` + `cmds:` containing a single `bash scripts/<name>.sh` line. NO inline logic. NO `prompt:` field on `destroy:` or `rebuild:` (RESEARCH §Pitfall 5 lines 833-849 — adding `prompt:` would force two confirmations).

**Whether to add the entry:** REPO-05 doesn't strictly require it; CONTEXT.md `<decisions>` Claude's-Discretion 211-213 leaves it to the planner. Researcher recommends adding for symmetry with the README walkthrough and for the `task preflight` shortcut documented in CONTEXT.md `<canonical_refs>` line 270-272.

---

## Shared Patterns

### Bash strict mode + helper sourcing (applied to: `hooks/pre-commit`)

**Source:** `scripts/destroy.sh:1-14`, `scripts/rebuild.sh:1-14`, `scripts/health-check.sh:1-14` — every project bash entrypoint follows this exact preamble.

```bash
#!/usr/bin/env bash
# <path>
# <one-line purpose>
# <usage>

set -euo pipefail   # OR `set -u` for preflight-style scripts that collect failures

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/preflight-lib.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/preflight-lib.sh"  # adjust relative path for hooks/
```

**Strict mode choice (project convention):**

- Wrappers + short-running tools: `set -euo pipefail`
- Multi-check failure-collecting scripts (`scripts/preflight.sh`): `set -u` only

### ANSI color gating + section/pass/warn/fail/info helpers (applied to: `hooks/pre-commit`)

**Source:** `scripts/lib/preflight-lib.sh:11-27`. `[[ -t 1 ]]` is the gate (degrade to plain text when stdout is not a TTY — matters for CI logs).

```bash
if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_DIM=$'\033[2m'; C_BOLD=$'\033[1m'
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_BLUE=$'\033[34m'
else
  C_RESET=""; ... # all colors empty in non-TTY
fi

section() { printf "\n%s%s== %s ==%s\n" ... }
pass()    { printf "  %s✓%s %s\n" ... }
warn()    { printf "  %s!%s %s\n" ... }
fail()    { printf "  %s✗%s %s\n" ... }
info()    { printf "  %s·%s %s\n" ... }
have()    { command -v "$1" >/dev/null 2>&1; }
```

**Apply to:** any new bash script (the only one in this phase is `hooks/pre-commit`); source `preflight-lib.sh` to inherit these.

### Idempotent install-tools.sh section pattern (applied to: `scripts/install-tools.sh` Sections 7-8)

**Source:** `scripts/install-tools.sh:74-83` (the §Section 4 idempotent-grep-guard pattern).

```bash
section "<feature name>"
if <state-check returns 0>; then
  info "already done, skipping: <feature name>"
else
  <do the install / config>
  pass "installing: <feature name>"
fi
```

**Apply to:** Section 7 (gitleaks plugin add) and Section 8 (`git config core.hooksPath`).

### bats static-grep test conventions (applied to: all 8 NEW bats files)

**Source:** `tests/bats/destroy-rebuild-01-static.bats:1-11`, `tests/bats/health-check-01-static.bats:1-10`, `tests/bats/bootstrap-flux-02-docs.bats:1-15`.

**Header:**

```bash
#!/usr/bin/env bats
# tests/bats/<file>.bats
# <one-line purpose>

load 'test_helper'
```

**setup():** declare paths via `${REPO_ROOT}/<...>` (REPO_ROOT is provided by `test_helper.bash` lines 21-22).

**Test naming:** `@test "<REQ-ID>: <plain-English assertion>" { ... }` — see all bats files for the convention.

**Three core grep idioms:**

1. **Existence + literal presence** (`destroy-rebuild-01-static.bats:13-24`):
   ```bash
   [ -f "$FILE" ]
   run grep -F -- '<literal>' "$FILE"
   [ "$status" -eq 0 ]
   ```

2. **Negative-grep with comment-filter** (`destroy-rebuild-01-static.bats:175-181`):
   ```bash
   run bash -c "grep -v '^[[:space:]]*#' '$FILE' | grep -F -- '<forbidden>'"
   [ "$status" -ne 0 ]
   ```

3. **Ordered-literal grep over a multi-line file** (`destroy-rebuild-01-static.bats:46-63`, `health-check-01-static.bats:20-37`):
   ```bash
   previous=0
   for literal in 'A' 'B' 'C'; do
     line="$(grep -nF -- "$literal" "$FILE" | head -1 | cut -d: -f1)"
     [ -n "$line" ]
     [ "$line" -gt "$previous" ]
     previous="$line"
   done
   ```

### Markdown doc structure (applied to: `docs/architecture.md`, `docs/gpu-notes.md`, `docs/rebuild-runbook.md`, `docs/adr/000*-*.md`, `README.md`)

**Source:** `docs/flux-hub-spoke.md:1-12`, `docs/wsl-networking.md:1-25`.

**Conventions:**

- Lead with `# <Title>` h1 (MD041 enforced — see RESEARCH §Pitfall 4).
- Short orientation paragraph naming the load-bearing script/file.
- `## Section` h2s; `---` horizontal rules between major sections (`wsl-networking.md` lines 25, 39).
- Bold lead-ins for hard rules: `**v1 of this project requires X.**`.
- Code blocks fenced with language hints: ` ```bash `, ` ```yaml `, ` ```ini `, ` ```mermaid `, ` ```toml `, ` ```json `, ` ```text `.
- Cross-references in inline backticks for paths/commands.
- Tables with `| Header | Header |` for structured rule lists (e.g., `flux-hub-spoke.md:18-22` — file/category/edit-permission table).

### Failure-message remediation (applied to: `hooks/pre-commit`, `Taskfile.yml`-driven scripts)

**Source:** `scripts/health-check.sh:24-29`, `scripts/lib/preflight-lib.sh:77-80`, `scripts/lib/preflight-lib.sh:96-99`.

Every `fail "<message>"` MUST include a `Fix:` (or `Inspect:` / `Check:`) line naming the next-action command:

```bash
fail "k3d cluster missing: ${cluster}.
   Fix: task create-clusters"
```

**Apply to:** `hooks/pre-commit` failure messages (point at `.gitleaks.toml` allow-rule path AND `git commit --no-verify` audit-loud bypass per RESEARCH §Pattern 1 lines 410-415); CI failure messages (via job-level `name:` and the gitleaks `--redact` output that names file + line).

---

## No Analog Found

Files where no close in-repo match exists; planner uses RESEARCH.md examples as the source of truth:

| File | Role | Data Flow | Source |
|------|------|-----------|--------|
| `.gitleaks.toml` | TOML lint config | static lint config | RESEARCH §Pitfall 1 lines 738-749 |
| `.markdownlint.json` | JSON lint config | static lint config | RESEARCH §Code Examples Example 3 lines 977-985 |
| `.github/workflows/ci.yml` | GitHub Actions YAML | event-driven (push/PR) | RESEARCH §Pattern 2 lines 435-517 |
| `docs/adr/0001..0005-*.md` (5 files) | ADR (Markdown, Nygard 4-section) | static doc | RESEARCH §Pattern 3 lines 552-591 |

For all four, RESEARCH.md provides verbatim-or-near-verbatim templates. The planner copies the templates and substitutes phase-specific values (datreeio SHA, gitleaks version pin, ADR slugs/content).

---

## Metadata

**Analog search scope:** `scripts/`, `scripts/lib/`, `tests/bats/`, `docs/`, repo root (`Taskfile.yml`, `.gitignore`, `.tool-versions`, `.env.example`, `CLAUDE.md`, `AGENTS.md`).

**Files scanned:**

- All 16 scripts in `scripts/` (read selectively: `preflight.sh`, `install-tools.sh`, `destroy.sh`, `rebuild.sh`, `health-check.sh`, `lib/preflight-lib.sh`).
- All 21 bats files in `tests/bats/` (read selectively: `destroy-rebuild-01-static.bats`, `bootstrap-flux-02-docs.bats`, `health-check-01-static.bats`, `bootstrap-flux-01-idempotent.bats`, `deploy-examples-01-static.bats`, `preflight-pre01.bats`, `test_helper.bash`).
- Both existing docs in `docs/` (`flux-hub-spoke.md`, `wsl-networking.md`).
- Repo root configs (`Taskfile.yml`, `.gitignore`, `.tool-versions`).

**Pattern extraction date:** 2026-04-28

**Skills consulted:** No `.claude/skills/` or `.agents/skills/` SKILL.md files exist in this repo; project-level guidelines came from `AGENTS.md` (mostly TODO placeholders) and the global `~/.claude/CLAUDE.md` (public-safe-by-default + read-existing-commands directives — both honored).
