---
phase: 01-host-foundation
reviewed: 2026-04-22T00:00:00Z
depth: standard
scope: incremental
prior_review: gap-plan 01-08 (CR-01, CR-02)
files_reviewed: 2
files_reviewed_list:
  - scripts/install-docker.sh
  - scripts/install-nvidia-container-toolkit.sh
findings:
  critical: 0
  warning: 1
  info: 2
  total: 3
counts:
  critical: 0
  warning: 1
  info: 2
  total: 3
status: issues_found
---

# Phase 01: Incremental Code Review Report (post gap-plan 01-08)

**Reviewed:** 2026-04-22
**Depth:** standard (incremental — scope limited to the two scripts changed by gap-plan 01-08)
**Files Reviewed:** 2
**Status:** issues_found (1 warning, 2 info — both CR-class blockers from the prior review are verified CLOSED)

## Summary

Gap-plan 01-08 targeted the two CRITICAL blockers raised in the prior
`01-REVIEW.md` (CR-01: malformed jq key access; CR-02: Docker bricked when
`default-runtime=nvidia` is written before the `nvidia` runtime is
registered). Both fixes land correctly and idempotency is preserved:

- **CR-01 is CLOSED.** The `_key='"default-runtime"'` string-literal
  indirection is gone from `install-nvidia-container-toolkit.sh`. Both the
  pre-check (line 41) and the Section 3 post-verify (line 106) now call
  `jq -r '."default-runtime" // empty' "$DAEMON_JSON"` directly. The
  first-run absence case is tolerated with `info()` (line 50), not `fail()`;
  only a non-empty, non-`nvidia` value still triggers `fail()` (line 42),
  which is the correct semantics.
- **CR-02 is CLOSED.** Option B from the plan is in place.
  `install-docker.sh` Section 6 (lines 120–168) gates the
  `default-runtime=nvidia` write on `jq -e '.runtimes.nvidia'` and on a
  fresh host (Path A) writes only `dns`. The authoritative
  `default-runtime=nvidia` write has moved to a new Section 4 in
  `install-nvidia-container-toolkit.sh` (lines 132–154), which runs AFTER
  Section 3's `nvidia-ctk runtime configure` registers `runtimes.nvidia`.
  Section 4 also double-checks `runtimes.nvidia` before merging (line 137)
  so the same bricking failure mode cannot re-emerge silently.
- **Idempotency is preserved.** Traced second-run paths:
  `install-docker.sh` Section 6 with both `_dns_ok=1` and
  `_default_runtime_ok=1` emits `already done, skipping` with no restart;
  `install-nvidia-container-toolkit.sh` Section 3 skips when `docker info`
  reports the runtime, Section 4 skips when `default-runtime == "nvidia"`.
  There is no infinite-restart loop and no state divergence.
- **Division of labor (D-05 / D-08) holds.** `install-docker.sh` still owns
  `dns` unconditionally; `nvidia-ctk runtime configure` remains the sole
  writer of `runtimes.nvidia`. Ownership of `default-runtime` is
  intentionally split by state: on a fresh host the NVIDIA toolkit script
  writes it (Section 4); on a subsequent Docker-script run it may be
  re-asserted by the jq-merge in Path B. The `. + {…}` merge semantics are
  shallow, so existing `runtimes.nvidia` is preserved across both merges.
- **Shell correctness.** `bash -n` and `shellcheck -x` both clean on both
  scripts (0 findings).

One WARNING remains: the file-level header comment in
`install-nvidia-container-toolkit.sh` (lines 6–11) was not updated to
reflect Option B and now actively mis-describes ownership — it still claims
the script "does NOT write default-runtime … — those are owned by
install-docker.sh". It does. Two INFO items round out the review: an
inconsistent use of `sudo` around `jq` reads, and stale commentary at the
top of Section 3 that is misleading adjacent to the new Section 4.

No other regressions were introduced. Issues called out in the prior
review for unchanged files (WR-01…WR-09, IN-01…IN-06) are **not
re-evaluated here** — this report is scoped to the two files touched by
gap-plan 01-08. The prior findings for those files are carried forward
verbatim in git history (`02-REVIEW.md` on commit `2b0c1af`).

## Warnings

### WR-01: `install-nvidia-container-toolkit.sh` header comment contradicts the post-fix behavior — actively misleads operators and future maintainers

**File:** `scripts/install-nvidia-container-toolkit.sh:6-11`

**Issue:** The file-level header documents the old contract:

```bash
# Prerequisites: Docker Engine must be installed and daemon.json must have
# default-runtime=nvidia (set by install-docker.sh). Run install-docker.sh first.
#
# This script calls `nvidia-ctk runtime configure --runtime=docker` which adds
# ONLY the `runtimes.nvidia` key to daemon.json via structured merge. It does NOT
# write default-runtime or dns — those are owned by install-docker.sh (Plan 02).
```

Two of these statements are no longer true after gap-plan 01-08:

1. "daemon.json must have default-runtime=nvidia (set by install-docker.sh)"
   — under Option B, a fresh-host run of `install-docker.sh` **intentionally
   does not** write `default-runtime`. The pre-check at line 41–51 of this
   same script now explicitly tolerates `default-runtime` being absent on
   first run (line 50 `info "default-runtime absent (expected on first
   run…)"`). The header contradicts the code two dozen lines below it.
2. "It does NOT write default-runtime … those are owned by
   install-docker.sh" — the **new Section 4** (lines 132–154) of this very
   script writes `default-runtime=nvidia`. The header flatly denies that
   Section 4 exists.

An operator reading the header to decide "is it safe to skip
`install-docker.sh` and run just this one?" will draw exactly the wrong
conclusion. A future maintainer editing Section 4 will be surprised that
the header's prohibition does not match the code and may "fix" the wrong
file. The inline comment at lines 120–131 is correct; the header above it
is not.

**Fix:** Rewrite lines 6–11 to match the post-01-08 contract. Example:

```bash
# Prerequisites: Docker Engine must be installed and the Docker daemon must
# be reachable (install-docker.sh run first; re-login for docker group).
# On a fresh host, daemon.json's default-runtime may be absent — this script
# writes it in Section 4 after `nvidia-ctk runtime configure` registers the
# `runtimes.nvidia` key. On re-runs, Section 4 is a no-op.
#
# Ownership (daemon.json keys):
#   - dns                : install-docker.sh (always)
#   - runtimes.nvidia    : this script, via `nvidia-ctk runtime configure`
#   - default-runtime    : this script (Section 4) on first run;
#                          re-asserted by install-docker.sh Path B on
#                          subsequent runs when runtimes.nvidia is present.
```

Also consider mirroring the ownership table into a short comment at the
top of `install-docker.sh` Section 6 so the two files stay in sync.

## Info

### IN-01: Inconsistent `sudo` usage when reading `/etc/docker/daemon.json` with `jq`

**File:** `scripts/install-nvidia-container-toolkit.sh:41, 106, 137, 144`;
`scripts/install-docker.sh:122, 127, 132`

**Issue:** Reads of `/etc/docker/daemon.json` via `jq` mix two styles:

- `install-nvidia-container-toolkit.sh:41` — `jq -r '...' "$DAEMON_JSON"` (no sudo)
- `install-nvidia-container-toolkit.sh:106` — same (no sudo)
- `install-nvidia-container-toolkit.sh:137` — `sudo jq -e '...' "$DAEMON_JSON"`
- `install-nvidia-container-toolkit.sh:144` — `sudo jq -e '...' "$DAEMON_JSON"`
- `install-docker.sh:122, 127, 132` — all `sudo jq -e '...' "$DAEMON_JSON"`

`/etc/docker/daemon.json` is mode 0644 by default on Ubuntu, so the
unsudoed reads work on a vanilla install. The script will still function
correctly today. However:

1. On a hardened host where an operator has chmod'd `daemon.json` to 0600,
   the two unsudoed reads at lines 41 and 106 will fail with "Permission
   denied", `2>/dev/null` swallows the error, `|| echo ""` yields empty,
   and the script proceeds down the "absent" branch — silently producing
   incorrect diagnostics ("default-runtime absent (expected on first run
   …)") even when the key is in fact set.
2. Two different patterns for the same operation in the same file are a
   code smell and invite future drift.

**Fix:** Standardize on `sudo jq` for reads of `/etc/docker/daemon.json`
across both scripts. If the unsudoed read is intentional (e.g., to avoid
provoking a sudo password prompt during pre-check), document the intent
inline.

### IN-02: Section 3 post-verify commentary is misleading adjacent to the new Section 4

**File:** `scripts/install-nvidia-container-toolkit.sh:91-93, 112-116`

**Issue:** The Section 3 header comment at lines 91–93 says:

```bash
# Post-verify: confirm default-runtime=nvidia preserved after nvidia-ctk merge (H1).
# nvidia-ctk configure uses structured merge — adds runtimes.nvidia ONLY.
# It does NOT write default-runtime or dns (owned by install-docker.sh).
```

The "(owned by install-docker.sh)" parenthetical is stale — the NEXT
section in this file (Section 4, lines 132–154) owns the first-run write
of `default-runtime`. Reading the two comments side-by-side is confusing:
Section 3 says "install-docker.sh owns default-runtime", then Section 4
writes `default-runtime`. The inline note at line 116 ("default-runtime
will be set in Section 4") partially mitigates this, but the parenthetical
at line 93 should be tightened: `nvidia-ctk` itself doesn't write
`default-runtime`; ownership of that key is split between Section 4 here
and Path B in install-docker.sh.

**Fix:** Rewrite the Section 3 comment to describe only what `nvidia-ctk`
does (write `runtimes.nvidia`), and point ownership of `default-runtime`
at Section 4 explicitly:

```bash
# nvidia-ctk configure uses structured merge — adds runtimes.nvidia ONLY.
# It does NOT touch default-runtime or dns. See Section 4 below for the
# first-run default-runtime write; see install-docker.sh Section 6 Path B
# for the re-assertion on subsequent Docker-script runs.
```

---

_Reviewed: 2026-04-22_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard (incremental)_
_Scope: two files touched by gap-plan 01-08; prior-review findings for
other files unchanged and carried forward in git history._
