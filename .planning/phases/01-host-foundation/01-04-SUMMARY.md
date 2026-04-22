---
phase: 01-host-foundation
plan: "04"
subsystem: infra
tags: [bash, shellcheck, asdf, tools, wsl2, path, idempotent]

# Dependency graph
requires:
  - 01-01 (scripts/lib/preflight-lib.sh — sourced by install-tools.sh)
  - 01-01 (.tool-versions — consumed by asdf install in Section 6)
provides:
  - scripts/install-tools.sh: idempotent asdf v0.18.1 binary installer + 8 plugin adder + version pinner
affects:
  - 01-05 (preflight.sh PRE-10 validates that asdf shims are on PATH — install-tools.sh creates them)
  - 01-07 (bats tests can exercise install-tools.sh idempotency)

# Tech tracking
tech-stack:
  added:
    - asdf v0.18.1 Go binary (installed from GitHub release tarball to /usr/local/bin)
    - asdf plugins: kubectl helm flux2 k3d k9s task jq yq (8 plugins from asdf shortname registry)
  patterns:
    - H2 standalone asdf bootstrap: install binary BEFORE any asdf commands (chicken/egg fix)
    - D-06 shell-init pattern: ~/.karyon/shell-init.sh with PATH prepend export
    - D-06 .bashrc guard: grep -qF literal-tilde idempotency check
    - D-05 guarded-sections: per-step state check before action, "already done, skipping:" or "installing:"
    - asdf self-pin skip: [[ "$_tool" == "asdf" ]] && continue in .tool-versions iteration
    - SC1091 disable for dynamic source path; SC2088 disable for intentional literal tilde in grep pattern

key-files:
  created:
    - scripts/install-tools.sh
  modified: []

key-decisions:
  - "SC2088 disable on grep -qF literal tilde: the .bashrc append uses ~ not $HOME; grep must search for literal ~"
  - "SC1091 disable on source line: path is dynamically computed via SCRIPT_DIR variable; shellcheck cannot follow it"
  - "Section 5 exports PATH inline (adding /usr/local/bin) before any asdf command so asdf binary is found immediately after install"
  - "Section 6 iterates .tool-versions individually per tool (not running bare asdf install) for per-tool feedback; skip guard for asdf line is load-bearing"

requirements-completed: [TOOLS-02, TOOLS-03]

# Metrics
duration: 2min
completed: 2026-04-22
---

# Phase 1 Plan 04: Install-Tools Script Summary

**Idempotent asdf v0.18.1 Go-binary installer with 8-plugin asdf setup, ~/.karyon/shell-init.sh PATH wiring, and .tool-versions-driven version pinning — H2 chicken/egg fix applied**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-04-22T22:19:49Z
- **Completed:** 2026-04-22T22:21:39Z
- **Tasks:** 1
- **Files modified:** 1 (created)

## Accomplishments

- Created `scripts/install-tools.sh` — executable, shellcheck-clean (exit 0) idempotent installer
- Section 1: curl + tar prerequisite guard
- Section 2 (H2): Installs asdf v0.18.1 Go binary from GitHub release tarball to `/usr/local/bin/asdf` BEFORE any asdf commands — resolves the chicken/egg problem where asdf cannot install itself
- Section 3: Creates `~/.karyon/shell-init.sh` with the v0.18+ PATH prepend form (`export PATH="${ASDF_DATA_DIR:-$HOME/.asdf}/shims:$PATH"`) — idempotent file-existence guard
- Section 4: Appends single sourcing hook to `~/.bashrc` with `grep -qF` guard to prevent duplicates across re-runs
- Section 5: Adds all 8 asdf plugins (kubectl helm flux2 k3d k9s task jq yq) with per-plugin `asdf plugin list` idempotency check
- Section 6: Iterates `.tool-versions`, skips the `asdf` line (with explanatory comment), checks `asdf list "$tool"` before running `asdf install` — consistent D-05 audit log output

## Task Commits

1. **Task 1: Write scripts/install-tools.sh** - `7b1cc9f` (feat)

## Files Created/Modified

- `scripts/install-tools.sh` — 163 lines; bash -n clean; shellcheck exit 0; chmod +x; sources lib/preflight-lib.sh; all 13 plan verify checks pass

## Decisions Made

- SC2088 shellcheck disable on `grep -qF '~/.karyon/shell-init.sh'`: the literal tilde in single-quotes is intentional — the appended `.bashrc` line uses `~` not `$HOME`, so the guard must search for the literal tilde string. Using `$HOME` in the grep pattern would miss existing guards written with `~`.
- SC1091 shellcheck disable on `source "${SCRIPT_DIR}/lib/preflight-lib.sh"`: the path is dynamically computed; shellcheck cannot follow it even with `# shellcheck source=lib/preflight-lib.sh`. Same pattern established in Plan 01 for test_helper.bash.
- Section 5 exports PATH inline (adding `/usr/local/bin`) before the plugin loop so the freshly-installed asdf binary at `/usr/local/bin/asdf` is found immediately without requiring a shell restart.
- `asdf install` is called per-tool inside the loop (not as bare `asdf install`) to give per-tool progress output; the asdf skip guard `[[ "$_tool" == "asdf" ]] && continue` is preserved with an explanatory comment so a future reader does not remove it.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] SC2088 tilde-in-quotes shellcheck warnings**
- **Found during:** Task 1 verification (shellcheck)
- **Issue:** Three SC2088 warnings fired: two on `section "~/.karyon/..."` and `section "~/.bashrc..."` display strings, and one on `grep -qF '~/.karyon/shell-init.sh'` where the tilde is intentionally literal
- **Fix:** Replaced display-string tildes with `\$HOME/...` (escaped for literal `$HOME` in output); added `# shellcheck disable=SC2088` comment above the grep line with rationale explaining the intentional literal tilde
- **Files modified:** scripts/install-tools.sh
- **Commit:** 7b1cc9f

**2. [Rule 1 - Bug] SC1091 shellcheck info on dynamic source**
- **Found during:** Task 1 verification (shellcheck)
- **Issue:** `source "${SCRIPT_DIR}/lib/preflight-lib.sh"` triggered SC1091 info — shellcheck cannot follow dynamically-computed paths even with the `# shellcheck source=` directive
- **Fix:** Added `# shellcheck disable=SC1091` on the line before the source call — same approach used in Plan 01 for test_helper.bash
- **Files modified:** scripts/install-tools.sh
- **Commit:** 7b1cc9f

---

**Total deviations:** 2 auto-fixed (both Rule 1 — shellcheck clean exit required)
**Impact on plan:** Both fixes are shellcheck compliance only; no behavioral change to the script.

## Threat Surface Scan

| Boundary | Assessment |
|----------|------------|
| github.com tarball → /usr/local/bin/asdf | T-04-01: accepted per threat model — lab-only, official asdf-vm repo, sudo tar extraction to /usr/local/bin only |
| asdf plugin add → community registry | T-04-02: accepted per threat model — plugins from official asdf shortname registry, lab-only dev tooling |
| ~/.bashrc modification | T-04-03: mitigated — single `grep -qF` guard prevents duplicate appends; one-liner only, no eval, no piped execution |
| ~/.karyon/shell-init.sh | T-04-04: accepted — PATH export only, no secrets, chmod 644 |

No new threat surface beyond the threat model documented in the plan.

## Known Stubs

None — script is complete. All sections are wired to real actions. No placeholder data or TODO markers.

## Self-Check

### Files exist
- `scripts/install-tools.sh`: FOUND

### Commits exist
- `7b1cc9f` feat(01-04): add idempotent asdf + tool installer script: FOUND (git rev-parse --short HEAD)

## Self-Check: PASSED
