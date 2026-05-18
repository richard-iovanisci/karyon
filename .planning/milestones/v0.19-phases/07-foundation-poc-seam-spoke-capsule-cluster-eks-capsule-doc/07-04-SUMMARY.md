---
phase: 07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc
plan: 04
subsystem: infra
tags: [preflight, gitleaks, gitignore, kubeconfig, leak-defense, fail-fast, port-30443, multi-line-regex]

# Dependency graph
requires:
  - phase: 07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc-00
    provides: Wave 0 bats tests + synthetic kubeconfig fixtures (preflight-pre15.bats, repo-hygiene-04-poc.bats, tests/fixtures/gitleaks/{synthetic-kubeconfig.yaml,benign-configmap.yaml})
provides:
  - check_port_strict() helper in scripts/preflight.sh — fail-fast inversion of v0.18 check_port() warn pattern
  - PRE-15 section invoking check_port_strict 30443 unconditionally (D-15 Discretion default)
  - .gitignore tenant-kubeconfig globs (karyon-tenants/, *.tenant.kubeconfig, tenants/**/access.yaml, tenants/**/admin.yaml) matching Phase 10's ${TMPDIR:-/tmp}/karyon-tenants/ destination
  - First positive [[rules]] block in .gitleaks.toml (id=kubeconfig-bearer-token, multi-line (?ms) regex, kind: Config + users + token shape, [A-Za-z0-9._-]{32,} token-length anchor)
  - Per-fixture path-allowlist in .gitleaks.toml (anchored regex ^tests/fixtures/gitleaks/synthetic-kubeconfig\.yaml$ — narrow exception so the synthetic positive fixture is committable)
affects: [07-03 capsule create-cluster.sh preflight gate, Phase 10 tenant kubeconfig generator, Phase 11 history scan + SLO regression gate]

# Tech tracking
tech-stack:
  added:
    - "gitleaks 8.30.1 multi-line regex with (?ms) flag — first positive rule lands here"
  patterns:
    - "Append-only edits to v0.18-locked config (D-11 Phase 1 [allowlist] + D-16 Phase 6 .gitignore globs preserved verbatim)"
    - "Separate-helper inversion (D-15) — check_port_strict() helper preserves v0.18 check_port() warn surface byte-for-byte while adding strict variant for POC-reserved ports"
    - "Path-anchored per-rule allowlist — ^tests/fixtures/gitleaks/synthetic-kubeconfig\\.yaml$ regex matches the relative path used by repo-wide pre-commit scans but NOT the absolute path used by direct --source bats tests, so the rule fires when explicitly testing the fixture and is silent for repo-wide commit gates"

key-files:
  created:
    - .planning/phases/07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc/deferred-items.md
  modified:
    - scripts/preflight.sh
    - .gitignore
    - .gitleaks.toml

key-decisions:
  - "Used the path-allowlist anchored on the relative-path form ^tests/fixtures/gitleaks/synthetic-kubeconfig\\.yaml$ — this anchors satisfy both the bats live-test contract (absolute --source path bypasses the anchor → rule fires → exit 1) AND the pre-commit/CI scan contract (relative path matches the anchor → fixture is allowlisted → committable)."
  - "Inserted PRE-15 block AFTER the existing v0.18 ports loop so the v0.18 surface (check_port + warn-loop over 6443 6444 6445 8080 8081 8082) is preserved byte-for-byte (D-15 v0.18 invariant)."
  - "Did NOT modify Plan 07-00 + Plan 07-RESEARCH planning docs that quote the synthetic fixture content (4 leak hits in repo-wide gitleaks scan); deferred to deferred-items.md per scope-boundary rule."

patterns-established:
  - "Strict-vs-warn helper pair (check_port + check_port_strict) — future POC-reserved ports add `check_port_strict <PORT>` invocations under PRE-15-style sections; v0.18 ports stay on the warn path"
  - "First positive gitleaks rule + per-fixture path-anchored allowlist — template for future POC-* leak rules (each adds [[rules]] + [rules.allowlist] block; existing [allowlist] global block stays append-only)"

requirements-completed:
  - POC-03
  - POC-04

# Metrics
duration: 6m
completed: 2026-04-29
---

# Phase 7 Plan 04: Preflight 30443 fail-fast + tenant-kubeconfig leak defense Summary

**check_port_strict() helper inverts v0.18's warn pattern for POC-reserved port 30443 (D-15); first positive gitleaks rule (id=kubeconfig-bearer-token, multi-line (?ms) regex) + 4 tenant-kubeconfig .gitignore globs close P29 leak loop end-to-end on Wave 0 fixtures.**

## Performance

- **Duration:** ~6 min
- **Started:** 2026-04-29T14:58:19Z
- **Completed:** 2026-04-29T15:04:15Z
- **Tasks:** 2
- **Files modified:** 3 (scripts/preflight.sh, .gitignore, .gitleaks.toml)
- **Files created:** 1 (deferred-items.md)

## Accomplishments

- **POC-04 / D-15 fail-fast attestation:** `scripts/preflight.sh` gains `check_port_strict()` that uses `fail` (not `warn`) when a port is in use; PRE-15 section unconditionally invokes `check_port_strict 30443` so a stale 30443 listener trips preflight BEFORE Plan 03's `create-cluster.sh` attempts `k3d cluster create`. The v0.18 `check_port()` (warn-only) function and its warn-loop over `6443 6444 6445 8080 8081 8082` are preserved verbatim — no v0.18 regression.
- **POC-03 / D-14 leak defense (closed end-to-end on Wave 0 fixtures):** `.gitignore` extended with 4 tenant-kubeconfig globs (`karyon-tenants/`, `*.tenant.kubeconfig`, `tenants/**/access.yaml`, `tenants/**/admin.yaml`) matching Phase 10's `${TMPDIR:-/tmp}/karyon-tenants/` destination. `.gitleaks.toml` gains the first positive `[[rules]]` block: `id="kubeconfig-bearer-token"`, multi-line `(?ms)` regex `^kind:\s*Config[\s\S]*?users:[\s\S]*?token:\s*[A-Za-z0-9._-]{32,}`, tags include `"v0.19"`. Per-fixture `[rules.allowlist].paths` allowlists `^tests/fixtures/gitleaks/synthetic-kubeconfig\.yaml$` (narrowest possible — Pitfall 5 mitigation).
- **Live gitleaks evidence on Wave 0 fixtures:**
  - Positive (`tests/fixtures/gitleaks/synthetic-kubeconfig.yaml`, absolute --source as bats invokes): exit 1 — rule fires (catches `kind: Config` + `users:` + `token:`).
  - Negative (`tests/fixtures/gitleaks/benign-configmap.yaml`, absolute --source): exit 0 — rule silent.
- **v0.18 inheritance preserved verbatim:** `[allowlist]` block (lines 7-14 with `ghp_REPLACE_WITH_PAT_WITH_repo_SCOPE` regex + `^\.env\.example$` path) byte-for-byte unchanged (Phase 1 D-11 contract); Phase 6 D-16 expansion globs (`kubeconfig*`, `*.kubeconfig`, `*.pem`, `*.key`, `*.crt`, `flux-system/identity*`) byte-for-byte unchanged.
- **Bats coverage:** `preflight-pre15.bats` GREEN (6/6); `repo-hygiene-04-poc.bats` GREEN (11/11 including 2 live `gitleaks detect` invocations); v0.18 preflight (`preflight-pre*.bats` other than pre15) GREEN (25/25); v0.18 repo-hygiene (`repo-hygiene-{01,02,03}*.bats`) GREEN (15/15). Total: 31/31 preflight + 26/26 repo-hygiene = 57 tests, zero failures.

## Task Commits

Each task was committed atomically with `--no-verify` (parallel-executor convention to avoid pre-commit hook contention):

1. **Task 1: Extend scripts/preflight.sh with check_port_strict() helper + PRE-15 section + 30443 invocation** — `63ba21f` (feat)
2. **Task 2: Extend .gitignore with tenant-kubeconfig globs (D-14) + add first positive gitleaks rule + per-fixture allowlist to .gitleaks.toml** — `f5e4ece` (feat; bundles `.gitignore`, `.gitleaks.toml`, and `deferred-items.md`)

## Files Created/Modified

- `scripts/preflight.sh` — Added `check_port_strict()` helper (uses `fail`, not `warn`) + new PRE-15 section invoking `check_port_strict 30443`. Insertion is between sections 5 (Network/ports v0.18) and 6 (Existing container/k8s state) — section 5 + section 6+ preserved verbatim.
- `.gitignore` — Appended 4 D-14 tenant-kubeconfig globs (`karyon-tenants/`, `*.tenant.kubeconfig`, `tenants/**/access.yaml`, `tenants/**/admin.yaml`) between Phase 6 D-16 expansion and the OS/IDE noise tail.
- `.gitleaks.toml` — Appended first positive `[[rules]]` block (`id="kubeconfig-bearer-token"`, multi-line `(?ms)` regex, `tags=["kubernetes", "kubeconfig", "bearer-token", "v0.19"]`) and a per-rule `[rules.allowlist].paths` block excluding only `tests/fixtures/gitleaks/synthetic-kubeconfig.yaml`. Existing `[allowlist]` (lines 7-14) preserved verbatim.
- `.planning/phases/07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc/deferred-items.md` (created) — Records 4 out-of-scope gitleaks hits (planning docs `07-00-PLAN.md` line 808, `07-RESEARCH.md` line 647 quote the inert synthetic fixture content) with 4 resolution options.

## Decisions Made

- **Path-allowlist regex anchor (relative-path form):** Anchored on `^tests/fixtures/gitleaks/synthetic-kubeconfig\.yaml$` rather than a more permissive form. This deliberately exploits the difference between bats's absolute `--source` path and gitleaks repo-wide scan's relative path: bats bypasses the anchor (rule fires; live test passes), repo-wide pre-commit/CI scans match the anchor (fixture allowlisted; committable). This is the narrowest possible mitigation per Pitfall 5.
- **Strict helper insertion point:** Block inserted AFTER the existing `for p in 6443 6444 6445 8080 8081 8082` loop and BEFORE `# ---------- 6. Existing container / k8s state ----------`. This preserves the v0.18 ports section byte-for-byte and gives the strict helper a distinct PRE-15 section header (D-15 invariant — the bats greps for the literal `PRE-15`).
- **Section labelling as "5b":** Added `# ---------- 5b. Network / ports (PRE-15: POC-reserved) ----------` so the new section is visually adjacent to section 5 without renumbering sections 6-14. Bats only checks for the literal `PRE-15` text, so the "5b" cosmetic choice is harmless.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Path-allowlist regex anchor required relative-path form to satisfy both bats live test AND pre-commit invariant**
- **Found during:** Task 2 (live gitleaks invocation post-edit)
- **Issue:** First-pass live test on the positive fixture using a relative `--source` path returned exit 0 (rule silent — allowlist matched). The plan's prescribed regex `^tests/fixtures/gitleaks/synthetic-kubeconfig\.yaml$` is anchored on the relative path form. The bats test (`repo-hygiene-04-poc.bats:84-89`) invokes gitleaks with an absolute path (`${REPO_ROOT}/tests/fixtures/gitleaks/synthetic-kubeconfig.yaml`) and expects `[ "$status" -ne 0 ]`. Initial concern: the path-allowlist as specified would silence the rule and break the bats live test.
- **Fix:** Verified the regex anchor (with `^...$`) only matches the relative-path form, NOT the absolute path the bats test uses. So the prescribed regex is correct as-written: bats's absolute-path invocation bypasses the anchor and the rule fires (exit 1), while repo-wide relative-path scans match the anchor and exclude the fixture. No code change needed — this was a verification deviation, not a fix.
- **Files modified:** None (verified the plan's prescribed regex IS the correct narrow-anchor solution)
- **Verification:** Live `gitleaks detect` with absolute path → exit 1 (as required by bats); with relative path → exit 0 (as required for pre-commit committability). Bats `repo-hygiene-04-poc.bats` GREEN 11/11.
- **Committed in:** `f5e4ece` (Task 2)

---

**Total deviations:** 1 verification clarification (Rule 1 — verified the plan's regex was correct after initial concern)
**Impact on plan:** No code-level deviations. The behavior depends on a subtle but deliberate property of gitleaks regex matching that's worth surfacing in this summary.

## Issues Encountered

- **Repo-wide gitleaks scan reports 4 leaks in planning docs (deferred):** `gitleaks detect --no-git --source . --config .gitleaks.toml` returns exit 1 with 4 hits in `.planning/phases/07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc/07-00-PLAN.md` (line 808) and `07-RESEARCH.md` (line 647). These planning docs verbatim-quote the synthetic fixture's `kind: Config` + `token` block as illustrative material. The fixture file itself is correctly allowlisted; the planning-doc quotations are not. This is OUT OF SCOPE for Plan 07-04 (file scope: `scripts/preflight.sh`, `.gitignore`, `.gitleaks.toml`); flagged files were created by Plan 07-00 + the Phase 7 RESEARCH step. Tracked in `deferred-items.md` with 4 resolution options (recommended: option 4, no action — leak material is provably inert).

## Threat Model Mitigations Verified

| Threat ID | Mitigation Verified |
|-----------|---------------------|
| T-7-D-15 / T-7-P-39 (port 30443 collision) | `check_port_strict 30443` invocation; preflight bats GREEN (6/6 PRE-15 + 25/25 v0.18 PRE-*); body uses `fail` not `warn` (D-15 invariant) |
| T-7-D-14 / T-7-P-29 (tenant kubeconfig leak) | 4 .gitignore globs match `${TMPDIR:-/tmp}/karyon-tenants/` paths; multi-line gitleaks rule + path-anchored allowlist; live positive fires (exit 1), live negative silent (exit 0) |
| T-7-Pitfall-5 (false-positive on innocuous YAML) | Negative fixture (kind: ConfigMap) does NOT trigger (live test exit 0); 32+ char token-length anchor avoids short-identifier false-positives |
| T-7-D-14-inherit-01 (regress Phase 1 [allowlist]) | `ghp_REPLACE_WITH_PAT_WITH_repo_SCOPE` regex + `^\.env\.example$` path preserved byte-for-byte; bats grep confirms |
| T-7-D-14-inherit-02 (regress Phase 6 .gitignore) | All 6 D-16 globs (`kubeconfig*`, `*.kubeconfig`, `*.pem`, `*.key`, `*.crt`, `flux-system/identity*`) preserved byte-for-byte; bats grep confirms |
| T-7-Sentinel-self-invalidation | Comment-block narrative (mentions `kind: Config`/`token` literals) does NOT match the `^kind:\s*Config` regex anchor — comments are indented and the literal `(?ms)` regex requires line-start anchor; no false self-match |

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- **Plan 07-03 (Wave 2 sibling, planned/executed elsewhere):** `scripts/poc/capsule/create-cluster.sh` preflight gate is now backed by 30443 fail-fast — once that script lands and chains into `task preflight`, a stale 30443 listener will trip preflight before `k3d cluster create` is attempted. No further wiring needed from this plan.
- **Phase 8 (Capsule install):** Operator/proxy HelmReleases will land on top of the v0.19 invariants closed here — no further .gitleaks.toml or preflight changes anticipated until Phase 10 tenant generator.
- **Phase 10 (tenant kubeconfig generator):** The 4 .gitignore globs are pre-positioned to filter accidental commits during dev; the gitleaks rule will catch any tenant kubeconfig that escapes the .gitignore via a non-matching destination path.
- **Phase 11 (validation + history scan):** History-scan loop closes here — Phase 7 ships the rule, Phases 8-10 ship the runtime, Phase 11 confirms zero historical leaks across all commits with the new rule active.

## Self-Check: PASSED

Verified before final commit:

```
[ -f scripts/preflight.sh ] → FOUND
[ -f .gitignore ] → FOUND
[ -f .gitleaks.toml ] → FOUND
[ -f tests/bats/preflight-pre15.bats ] → FOUND (Wave 0 contract)
[ -f tests/bats/repo-hygiene-04-poc.bats ] → FOUND (Wave 0 contract)
[ -f .planning/phases/07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc/deferred-items.md ] → FOUND
git log | grep 63ba21f → FOUND (Task 1 commit)
git log | grep f5e4ece → FOUND (Task 2 commit)
bats tests/bats/preflight-pre*.bats → 31/31 PASS
bats tests/bats/repo-hygiene-*.bats → 26/26 PASS
gitleaks detect --source <abs-path-positive> → exit 1 (rule fires)
gitleaks detect --source <abs-path-negative> → exit 0 (rule silent)
```

---
*Phase: 07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc*
*Completed: 2026-04-29*
