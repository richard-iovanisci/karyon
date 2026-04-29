---
phase: 06-repo-hygiene-docs-adrs
reviewed: 2026-04-29T01:42:46Z
depth: standard
files_reviewed: 27
files_reviewed_list:
  - .github/workflows/ci.yml
  - .gitignore
  - .gitleaks.toml
  - .markdownlint-cli2.jsonc
  - .markdownlint.json
  - .tool-versions
  - README.md
  - Taskfile.yml
  - docs/adr/0001-single-wsl2-shared-docker-network.md
  - docs/adr/0002-k3d-over-kind.md
  - docs/adr/0003-flux-over-argocd.md
  - docs/adr/0004-hub-only-flux-control-plane.md
  - docs/adr/0005-kubernetes-version-pin.md
  - docs/architecture.md
  - docs/gpu-notes.md
  - docs/rebuild-runbook.md
  - hooks/pre-commit
  - scripts/install-tools.sh
  - scripts/lib/preflight-lib.sh
  - tests/bats/docs-01-readme-order.bats
  - tests/bats/docs-02-architecture.bats
  - tests/bats/docs-04-gpu-notes.bats
  - tests/bats/docs-05-runbook.bats
  - tests/bats/docs-adr-template.bats
  - tests/bats/repo-hygiene-01-static.bats
  - tests/bats/repo-hygiene-02-taskfile.bats
  - tests/bats/repo-hygiene-03-ci.bats
findings:
  critical: 0
  warning: 4
  info: 8
  total: 12
status: issues_found
---

# Phase 6: Code Review Report

**Reviewed:** 2026-04-29T01:42:46Z
**Depth:** standard
**Files Reviewed:** 27
**Status:** issues_found

## Summary

Reviewed all 27 files of the phase 6 deliverable: 5 Nygard ADRs, 3 reference
docs, the README, repo-hygiene configs (.gitignore, .gitleaks.toml,
.tool-versions, two markdownlint configs), the Taskfile, the gitleaks
pre-commit hook, install-tools.sh + preflight-lib.sh shell scripts, the
5-job GitHub Actions CI workflow, and 8 bats validation suites.

The public-safe secrets gate is correctly assembled: gitleaks pre-commit hook
uses the canonical `gitleaks git --pre-commit --redact --staged` invocation,
the CI workflow's `gitleaks-scan` job uses `fetch-depth: 0` (correct for
`--log-opts="--all"` historical scan), all five required CI actions are
SHA-pinned to 40-character commits matching their tagged releases, and the
allowlist is narrowly scoped to a single literal placeholder regex. No
critical findings — no committed secrets, no command injection, no
authentication bypass, no SHA-pin gaps.

The four warnings cluster in two areas: (a) a real idempotency-violation bug
in `scripts/install-tools.sh` where the asdf-binary version-check regex
will never match the actual `asdf --version` output, causing the install
step to needlessly re-download and re-extract on every re-run, and (b)
quality issues with stale config and surface-area concerns in the gitleaks
allowlist + duplicated install-tools.sh sections.

The eight info findings are mostly stale references (REQUIREMENTS.md /
RESEARCH.md / PROJECT.md / STATE.md cited from public docs without paths;
a `(DOCS-03 ✅)` planning-tracker artifact left in ADR-004; `starter.md`
referenced in markdownlint-cli2 ignore list after the file was deleted)
plus a non-existent markdownlint rule (MD060) and minor doc inconsistencies.

## Warnings

### WR-01: `scripts/install-tools.sh` asdf version check regex never matches — idempotency contract is broken

**File:** `scripts/install-tools.sh:42`
**Issue:** The idempotency guard for the asdf binary install reads:

```bash
if [[ -x /usr/local/bin/asdf ]] && /usr/local/bin/asdf --version 2>/dev/null | grep -qE "^0\.(1[89]|[2-9])"; then
```

The regex anchors at line-start with `^0\.`, but `asdf --version` on the
v0.18+ Go-rewrite binary emits `asdf version v0.18.1 (revision <sha>)`
starting with the literal string `asdf`, not `0`. The regex match fails on
every re-run, the `else` branch fires, and `install-tools.sh` re-downloads
and re-extracts the asdf tarball every time. This violates the documented
contract on line 8 ("Safe to re-run — skips steps already done.") and
wastes ~5-30 seconds per run on network-bound systems.

This is also explicitly contradicted by the comment block on lines 38-39:
"Idempotent: if /usr/local/bin/asdf already exists at the right version,
skip."

Reproduction: `echo 'asdf version v0.18.1 (revision 6a97697)' | grep -qE
'^0\.(1[89]|[2-9])'` returns 1 (no match).

**Fix:** Strip the prefix or anchor differently. Two options:

```bash
# Option A: drop the line-start anchor
if [[ -x /usr/local/bin/asdf ]] && /usr/local/bin/asdf --version 2>/dev/null | grep -qE "v0\.(1[89]|[2-9])"; then

# Option B: extract the version with awk and compare numerically/literally
if [[ -x /usr/local/bin/asdf ]] \
   && [[ "$(/usr/local/bin/asdf --version 2>/dev/null | awk '{print $3}')" == "${ASDF_VERSION}" ]]; then
```

Option B is preferred — it pins to the exact `ASDF_VERSION` declared at
line 19 (`v0.18.1`) instead of the loose 0.18-or-newer regex.

---

### WR-02: `.gitleaks.toml` path allowlist regex is unanchored — exempts files outside its intended scope

**File:** `.gitleaks.toml:13`
**Issue:** The allowlist contains:

```toml
paths = [
  '''\.env\.example''',                         # whole-file allow (Phase 1 D-11 contract)
]
```

gitleaks v8.x treats `paths` entries as regex matched against the file
path. `\.env\.example` is a substring regex — it matches any file path
containing the substring `.env.example` anywhere, not just the canonical
`.env.example` file at the repo root. This means any file whose path
contains the literal `.env.example` (e.g., `secrets/foo.env.example.bak`,
`data/.env.example.broken`, `reference/old.env.example.txt`) would have
ALL secrets exempt — every detection rule is suppressed for that file.

While unlikely to be exploited, this widens the secrets-gate bypass
surface beyond the documented "whole-file allow" intent. A future
contributor adding a file with `.env.example` in its name would silently
inherit the allowlist with no audit trail.

**Fix:** Anchor the regex to the exact path:

```toml
paths = [
  '''^\.env\.example$''',                       # whole-file allow, anchored
]
```

If the file may also live in subdirectories: `'''(^|/)\.env\.example$'''`.

---

### WR-03: `scripts/install-tools.sh` Section 7 is dead code — Section 5 already adds the `gitleaks` plugin

**File:** `scripts/install-tools.sh:151-163`
**Issue:** Section 5 (lines 94-102) iterates over the plugin list:

```bash
for plugin in kubectl helm flux2 k3d k9s task jq yq gitleaks; do
  if asdf plugin list 2>/dev/null | grep -qx "$plugin"; then
    info "already done, skipping: asdf plugin ${plugin}"
  else
    asdf plugin add "$plugin"
    pass "installing: asdf plugin ${plugin}"
  fi
done
```

The list explicitly includes `gitleaks` as the 9th item. Section 7 (lines
151-163) then performs the SAME idempotent add for `gitleaks` only:

```bash
section "asdf plugin gitleaks"
if asdf plugin list 2>/dev/null | grep -qx gitleaks; then
  info "already done, skipping: asdf plugin gitleaks"
else
  asdf plugin add gitleaks
  pass "installing: asdf plugin gitleaks"
fi
```

Because Section 5 always runs first and the `grep -qx` guard is robust,
Section 7 always reports "already done, skipping" — it is functionally
dead code. The output produces a duplicate "asdf plugin gitleaks" section
header that confuses readers who expect each section to do new work.

**Fix:** Delete Section 7 entirely (lines 151-163). The introductory
header comment for Section 8 ("Git core.hooksPath wiring") needs to be
re-numbered or the numeric prefix dropped — Section 5 already handles
gitleaks plugin installation, so the dependent claim "Tool version pinned
in .tool-versions. Section 6 above iterates .tool-versions and `asdf
install`s gitleaks 8.30.1" is the only documented intent and is satisfied
by Sections 5 + 6.

---

### WR-04: `.gitignore` has redundant `kubeconfig` + `kubeconfig*` lines — first is a strict subset of the second

**File:** `.gitignore:12-13`
**Issue:**

```
kubeconfig
kubeconfig*
```

`kubeconfig*` (line 13) is a glob pattern matching any path-component
starting with `kubeconfig` — including the literal `kubeconfig` itself.
Line 12 is therefore a strict subset of line 13. The redundancy is
harmless but signals copy/paste origin and may confuse future readers who
think the bare `kubeconfig` line carries a special meaning (it doesn't).

**Fix:** Delete line 12. Or, if the intent was to match the bare
`kubeconfig` filename only at the repo root (anchored) versus
`kubeconfig*` for any depth, then be explicit:

```
/kubeconfig                # only at repo root (anchored)
*.kubeconfig               # already present
```

## Info

### IN-01: Public-facing docs reference internal planning files without paths

**File:** `docs/adr/0001-single-wsl2-shared-docker-network.md:67`,
`docs/adr/0002-k3d-over-kind.md:56`,
`docs/adr/0005-kubernetes-version-pin.md:48,53,60,62,68`,
`docs/gpu-notes.md:102-105`,
`docs/rebuild-runbook.md:107,209`
**Issue:** Multiple references to `REQUIREMENTS.md`, `PROJECT.md`,
`RESEARCH.md`, `STATE.md` appear naked (without the `.planning/` path
prefix) in user-facing documents. A first-time reader cloning the repo
will not know these files live under `.planning/REQUIREMENTS.md`,
`.planning/phases/<phase>/<phase>-RESEARCH.md`, etc. Notable:

- `docs/gpu-notes.md:103` cites `Phase 2 RESEARCH.md` — the file is at
  `.planning/phases/02-cluster-layer/02-RESEARCH.md`.
- `docs/rebuild-runbook.md:107` cites `STATE.md decision log` — at
  `.planning/STATE.md`.
- `docs/adr/0005-kubernetes-version-pin.md:62` cites `PROJECT.md "Key
  Decisions"` — at `.planning/PROJECT.md`.

If `.planning/` is intentionally tracked (as `README.md:254` claims), the
links should at least specify the relative path. Otherwise, a fresh-clone
reader following any of these references hits a 404.

**Fix:** Either (a) replace each naked reference with a path-qualified
link such as `[REQUIREMENTS.md](../.planning/REQUIREMENTS.md)`, or (b)
inline the relevant claim instead of referring readers to an
implementation-tracking artifact.

---

### IN-02: `(DOCS-03 ✅)` planning-tracker artifact leaked into ADR-004

**File:** `docs/adr/0004-hub-only-flux-control-plane.md:47`
**Issue:** Line 47 reads:
```
The `spec.kubeConfig` reconciliation pattern is documented in
`../flux-hub-spoke.md` (DOCS-03 ✅) — the patch surface and immutability
```

The `(DOCS-03 ✅)` decoration is a planning-tracker reference, not a
narrative element. ADRs document architectural decisions for an
external/future audience, not implementation status. Other ADRs in the
same set do NOT carry status checkmarks. The orphaned `✅` will read as
clutter (or implementation-status pollution) to anyone outside the
authoring team.

**Fix:** Drop the parenthetical and rewrite as plain prose:

```markdown
The `spec.kubeConfig` reconciliation pattern is documented in
[`../flux-hub-spoke.md`](../flux-hub-spoke.md) — the patch surface and
immutability rules carry through unchanged from a vanilla Flux install.
```

(Bonus: turning the inline-code reference into a linked reference also
makes navigation clickable.)

---

### IN-03: `.markdownlint-cli2.jsonc` ignores `starter.md` after the file has been deleted

**File:** `.markdownlint-cli2.jsonc:12,20`
**Issue:** Lines 11-13 carry an explanatory comment naming `starter.md`
as scheduled-for-deletion in Plan 05 (D-14). Line 20 lists it in the
`ignores` array. The file `starter.md` is not present in the repo. The
ignore entry is now dead config.

**Fix:** Remove the `starter.md` line from `ignores` and the corresponding
comment block. Final ignores list:

```jsonc
{
  "ignores": [
    ".planning/**",
    "CLAUDE.md",
    "node_modules/**"
  ]
}
```

---

### IN-04: `.markdownlint.json` references nonexistent rule MD060

**File:** `.markdownlint.json:9`
**Issue:** The line `"MD060": false` disables a markdownlint rule that
does not exist. Standard markdownlint rules are MD001-MD059 (with a few
removed/renamed in the v0.x series). MD060 has no defined behavior. The
`false` value is a silent no-op — no error from markdownlint-cli2, but no
effect either.

**Fix:** Either remove the dead entry or replace with the intended rule.
Adjacent rules that are sometimes confused with MD060: MD050 (strong
emphasis style), MD058 (blanks-around-tables — note that MD032 is already
disabled in this file). If the intent was "disable the most common
nuisance rule," the line should be removed and the rule explicitly named.

```json
{
  "default": true,
  "MD013": false,
  "MD032": false,
  "MD033": {
    "allowed_elements": ["br", "div"]
  },
  "MD041": true
}
```

---

### IN-05: `tests/bats/docs-01-readme-order.bats` "60-second TL;DR" assertion has dead regex clause

**File:** `tests/bats/docs-01-readme-order.bats:62`
**Issue:** The assertion regex is `(tl;dr|quick ?start|60.second)`. The
README contains both `## TL;DR` (line 7) and `## Quick Start` (line 20),
so the test passes via the first branch. The third alternation `60.second`
(matching e.g. "60-second") never fires — the README has no string
matching it, and `grep` short-circuits at the first hit. The `60.second`
clause is dead.

The header comment at line 5 says `a 60-second TL;DR ahead of any
installation step` but the README's actual claim is `task rebuild ... in
under 20 minutes`, not `60 seconds`. Either the test header or the README
content is stale.

**Fix:** Drop the `60.second` clause from the regex (it is unreachable),
and update the test header comment to reflect what is actually being
asserted: a TL;DR section appears before any installation step. Optional:
strengthen the test to assert the TL;DR mentions `task rebuild` and
`under 20 minutes`.

---

### IN-06: README cites a 5-tool subset of the 10-tool `.tool-versions` list

**File:** `README.md:81-83`
**Issue:** The "tools install" section reads:
```
.tool-versions carries the line: kubectl 1.35.0, helm 3.20.2, flux2
2.8.6, k3d 5.8.3, task 3.50.0, plus gitleaks 8.30.1 for the pre-commit
hook
```

`.tool-versions` actually contains 10 entries: kubectl, helm, flux2, k3d,
**k9s**, task, **jq**, **yq**, asdf, gitleaks. The README omits k9s, jq,
yq, and asdf. A reader running `cat .tool-versions` after reading the
README will be confused by the unexpected entries.

**Fix:** Either (a) cite the full list or (b) re-frame as "the toolchain
includes — among others — kubectl 1.35.0, ..." to signal subsetting:

```markdown
Install asdf and the pinned toolchain. `.tool-versions` carries 10 pins:
the Kubernetes-related five (kubectl 1.35.0, helm 3.20.2, flux2 2.8.6,
k3d 5.8.3, k9s 0.50.18), three CLI helpers (task 3.50.0, jq 1.8.1,
yq 4.53.2), gitleaks 8.30.1 for the pre-commit hook, and asdf 0.18.1 itself.
```

---

### IN-07: `docs/rebuild-runbook.md` PRE-14 framing in WSL-mirrored-mode appendix is misleading

**File:** `docs/rebuild-runbook.md:304-310`
**Issue:** The appendix entry titled "WSL2 mirrored mode" attributes the
failure-mode signal to `preflight PRE-14 fails the bridge-curl probe`.
While PRE-14 (the bridge-network probe in `scripts/preflight.sh:356-361`)
will indeed fail when WSL is in mirrored mode, the canonical mirrored-mode
detection check is **PRE-03** (`preflight_check_mirrored_mode` in
`scripts/lib/preflight-lib.sh:159,173`). PRE-03 will fire first; PRE-14 is
a downstream effect. A reader following the runbook would expect to see
PRE-03 in the failing output, not PRE-14, and may misroute the diagnosis.

**Fix:** Re-attribute the entry to PRE-03 (or note that both fail):

```markdown
### "WSL2 mirrored mode" — Docker custom networks cannot be bridged

**Symptom:** preflight PRE-03 fails (mirrored-mode detection); PRE-14
also fails the bridge-curl probe; clusters created but nothing reaches
them.
```

---

### IN-08: CI `kubeconform` job silently passes when `clusters/` or `examples/` directories are missing or empty

**File:** `.github/workflows/ci.yml:58-65`
**Issue:** The validation pipeline:
```bash
find clusters examples -name '*.yaml' -not -name 'kustomization.yaml' -print0 \
  | xargs -0 kubeconform ...
```

If `clusters/` and `examples/` are both removed (or empty of `.yaml`
files), `find` outputs nothing, `xargs -0` runs `kubeconform` once with
no args, and `kubeconform` reads stdin (empty) → exits 0. The CI job
reports green even though no manifests were validated. This is a silent
false-pass risk if a future PR accidentally drops the manifest
directories or renames them.

**Fix:** Add a guard or `xargs --no-run-if-empty` (`-r`) plus a manifest
count assertion:

```bash
manifests=$(find clusters examples -name '*.yaml' -not -name 'kustomization.yaml')
if [ -z "$manifests" ]; then
  echo "ERROR: no manifests found under clusters/ or examples/"
  exit 1
fi
echo "$manifests" | tr '\n' '\0' | xargs -0 -r kubeconform ...
```

This is non-blocking for v1 (the directories exist and are populated) but
worth noting as defensive depth for future-proofing.

---

_Reviewed: 2026-04-29T01:42:46Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
