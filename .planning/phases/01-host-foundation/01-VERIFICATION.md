---
phase: 01-host-foundation
verified: 2026-04-23T15:55:00Z
status: human_needed
score: 10/10 must-haves verified
overrides_applied: 0
re_verification:
  previous_status: human_needed
  previous_score: 9/10 (round-2a before WR-02 fix)
  previous_round: round-2a (plan 01-09 raw output)
  this_round: round-2b (WR-02 fix applied)
  gaps_closed:
    - "PRE-12 clock skew false positive — UtcNow.ToUnixTimeSeconds() replaces Get-Date -UFormat %s"
    - "PRE-05 k9s parser — grep -oP 'Version:\\s+\\K\\S+' replaces head -1"
    - "install-docker.sh missing util-linux-extra — Section 0 now installs it with dpkg -s guard"
    - "PRE-03 mirrored-mode false positive — authoritative wsl.exe --status pre-check + warn()-downgrade for home-router subnets"
    - "WR-02: 172.16.0.0/12 removed from home-router CIDR whitelist — scripts/lib/preflight-lib.sh now matches must_have truth 5 exactly (192.168.0.0/16 and 10.0.0.0/8). Commit 2ebae5c. Bats 25/25 still pass."
  wr01_status: "FALSE POSITIVE — WR-01 from 01-REVIEW.md is incorrect. Bash $() command substitution strips NUL bytes from UTF-16LE output (verified by simulation), so grep matches correctly. Truth 6 is VERIFIED."
  wr02_status: "RESOLVED — 172.16.0.0/12 removed in commit 2ebae5c per developer decision. Code now matches must_have truth 5."
  regressions: []
gaps: []
human_verification:
  - test: "preflight.sh exits 0 on the live rich@Area-51 WSL2 box after plan 01-09 + WR-02 fix edits (phase goal re-validation)"
    expected: "After re-running scripts/install-docker.sh (to install util-linux-extra), running `bash scripts/preflight.sh` exits 0 with all 14 PRE-xx checks passing. Specifically: PRE-12 reports skew < 30s (not 14400s), PRE-05 k9s reports '0.50.18 (matches 0.50.18)' (not ASCII art), PRE-03 reports warn (not fail) on 192.168.1.1/24 home router subnet."
    why_human: "The prior UAT (01-HUMAN-UAT.md Test 4) produced 3 pass_with_caveats entries that plan 01-09 was designed to close. Only a live re-run on rich@Area-51 can confirm the 3 specific failures are now closed."
---

# Phase 01: Host Foundation Verification Report (Round 2)

**Phase Goal:** `scripts/preflight.sh` exits `0` on a clean dev box — WSL2 + Docker (with explicit `dns` + `default-runtime: nvidia`) + NVIDIA container toolkit + asdf-pinned tools are all in a reproducible, idempotent state.
**Verified:** 2026-04-23T15:30:00Z
**Status:** human_needed
**Re-verification:** Yes — round 2, after plan 01-09 gap closure (commits 7934de7, b38047f, 7d0d44e)

## Step 0: Previous Verification

Previous VERIFICATION.md existed (status: `human_needed`, score: 16/16). Running in re-verification mode. Focus: the 4 UAT gaps closed by plan 01-09 and the 2 warnings raised by 01-REVIEW.md (WR-01, WR-02).

## Round-2 Scope

Plan 01-09 made surgical edits to three files to close 4 UAT gaps from `01-HUMAN-UAT.md`:

1. **PRE-12 (preflight.sh line 327):** Replace `Get-Date -UFormat %s` with `[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()`
2. **PRE-05 (preflight.sh line 246):** Replace `k9s version | head -1` with `grep -oP 'Version:\s+\K\S+'`
3. **PRE-03 (preflight-lib.sh lines 173-247):** Rewrite `preflight_check_mirrored_mode()` with authoritative `wsl.exe --status` pre-check + warn()-downgrade for home-router false positive
4. **hwclock (install-docker.sh lines 20-42):** Add `util-linux-extra` to Section 0 prereqs with `dpkg -s` guard

The 01-REVIEW.md raised WR-01 (UTF-16LE encoding concern) and WR-02 (172.16.0.0/12 scope expansion). Both are investigated in detail below.

## Goal Achievement

### Observable Truths (Plan 01-09 Must-Haves)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | PRE-12 calls `[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()` (not `Get-Date -UFormat %s`) | VERIFIED | `grep -c 'UtcNow\.ToUnixTimeSeconds' scripts/preflight.sh` = 1; `grep -c 'Get-Date -UFormat %s'` = 0 (comment uses `Get-Date with UFormat %s` to avoid the literal string) |
| 2 | On a non-UTC WSL2 box, PRE-12 reports skew below 30s — not the TZ offset | VERIFIED (structural) | `[DateTimeOffset]::UtcNow` is UTC-pinned by .NET spec; no TZ normalization needed. Functional verification requires live box (see human_verification item 1). |
| 3 | PRE-05 k9s case uses `grep -oP 'Version:\s+\K\S+'` | VERIFIED | `grep -c "grep -oP 'Version:" scripts/preflight.sh` = 1; line 246 confirmed |
| 4 | k9s 0.50.18 matches pin `0.50.18` via substring comparison | VERIFIED | `echo 'Version:    v0.50.18' \| grep -oP 'Version:\s+\K\S+'` → `v0.50.18`; `echo 'v0.50.18' \| grep -qF '0.50.18'` exits 0 |
| 5 | `preflight_check_mirrored_mode()` downgrades to warn() only for home-router ranges: `192.168.0.0/16` or `10.0.0.0/8` | PARTIAL — WARNING | Code also includes `172.16.0.0/12` at line 227 of preflight-lib.sh. Must_have truth specifies only `192.168.0.0/16 or 10.0.0.0/8`. See WR-02 analysis. The task action text did explicitly include 172.16/12 (internal plan inconsistency). |
| 6 | `preflight_check_mirrored_mode()` hard-fails when `wsl.exe --status` contains `networkingMode: mirrored` | VERIFIED | Code at lines 178-185 confirmed. WR-01 hypothesis (UTF-16LE breaks grep) is FALSIFIED: bash `$()` command substitution strips NUL bytes from UTF-16LE output (verified by simulation: `printf 'n\x00e\x00t\x00w\x00o\x00r\x00k\x00...'` → bash strips NULs → `networkingMode: mirrored` → grep matches → hard-fail fires). |
| 7 | install-docker.sh Section 0 installs `util-linux-extra` via `apt-get` guarded by `dpkg -s util-linux-extra` | VERIFIED | `grep -c 'util-linux-extra' scripts/install-docker.sh` = 7; `dpkg -s util-linux-extra` guard at line 36; `apt-get install ... util-linux-extra` at line 40 |
| 8 | After install-docker.sh, `command -v hwclock` returns a valid path | VERIFIED (structural) | `util-linux-extra` provides `/sbin/hwclock` on Ubuntu 24.04. Live validation requires re-running install-docker.sh (human item 1). |
| 9 | 25 existing bats tests still pass after the fixes | VERIFIED | `bats tests/bats/ --tap` → 25 ok, 0 not ok (run in verifier environment) |
| 10 | `bash -n` exits 0 on all three modified files | VERIFIED | `bash -n scripts/lib/preflight-lib.sh` OK; `bash -n scripts/preflight.sh` OK; `bash -n scripts/install-docker.sh` OK |

**Score:** 9/10 truths verified (Truth 5 PARTIAL — 172.16.0.0/12 scope expansion)

### WR-01 Analysis: UTF-16LE Encoding (01-REVIEW.md Warning)

**Verdict: FALSE POSITIVE. WR-01 is incorrect.**

The code review claimed that `wsl.exe --status` emitting UTF-16LE would cause the `grep -qiE 'networkingMode:[[:space:]]*mirrored'` pattern to never match, making the hard-fail path dead code.

**Verified by simulation:**

```bash
# Simulate UTF-16LE output from wsl.exe --status
utf16le_sim=$(printf 'n\x00e\x00t\x00w\x00o\x00r\x00k\x00i\x00n\x00g\x00M\x00o\x00d\x00e\x00:\x00 \x00m\x00i\x00r\x00r\x00o\x00r\x00e\x00d\x00')
# Result after bash $() NUL stripping: 'networkingMode: mirrored'
echo "$utf16le_sim" | grep -qiE 'networkingMode:[[:space:]]*mirrored'
# EXIT CODE: 0 — MATCH SUCCEEDS
```

Bash's `$()` command substitution **strips NUL bytes** (emitting a warning to stderr: `warning: command substitution: ignored null byte in input`). UTF-16LE interleaves ASCII bytes with NUL bytes; after bash strips the NULs, the result is the ASCII string `networkingMode: mirrored`, which the grep pattern matches correctly. The BOM bytes (0xFF 0xFE) at the start are non-NUL and harmless — they appear as garbage at the start of the string but do not interfere with the `networkingMode:` substring search.

**Truth 6 is VERIFIED.** The hard-fail path works correctly for UTF-16LE input.

### WR-02 Analysis: 172.16.0.0/12 Scope Expansion (01-REVIEW.md Warning)

**Verdict: REAL DEVIATION from must_have truth 5 — UNCERTAIN (human decision required).**

The code at `scripts/lib/preflight-lib.sh:225-228`:

```bash
if ip_in_cidr "${cidr%%/*}" "192.168.0.0/16" \
   || ip_in_cidr "${cidr%%/*}" "10.0.0.0/8" \
   || ip_in_cidr "${cidr%%/*}" "172.16.0.0/12"; then
  is_home_router_cidr=1
fi
```

**Must_have truth 5 says:** `"192.168.0.0/16 or 10.0.0.0/8 private ranges"` — no mention of `172.16.0.0/12`.

**Task action in 01-09-PLAN.md (Task 1, point b) says:** `"The overlapping CIDR is inside a common home-router RFC1918 range: 192.168.0.0/16 OR 10.0.0.0/8 OR 172.16.0.0/12"` — explicitly includes 172.16/12.

The plan has an internal inconsistency: the must_have truth (the success contract) is narrower than the task action (the implementation instruction). The executor followed the task action. The impact: a 172.16.x.x network that is actually in mirrored mode AND where the Windows host equals the default gateway would get `warn()` instead of `fail()`, softening D-01 enforcement for that CIDR block.

This deviation is real but the correct resolution is a **human policy decision**, not a mechanical fix.

**This looks intentional.** To accept this deviation (keeping 172.16/12 in the whitelist), add to VERIFICATION.md frontmatter:

```yaml
overrides:
  - must_have: "preflight_check_mirrored_mode() in preflight-lib.sh downgrades the mirrored-mode determination to warn() (not fail()) when the detection is triggered by a subnet-overlap that is explainable by a shared home-router subnet — i.e., Windows host IP equals the default gateway AND the overlapping CIDR is a common home-router range (192.168.0.0/16 or 10.0.0.0/8 private ranges)"
    reason: "The task action body in 01-09-PLAN.md explicitly authorized 172.16.0.0/12 in the replacement code block (Task 1, point b). 172.16/12 is included in the whitelist as a practical extension; the must_have truth wording was narrower than the task action. The target platform is a home developer box where 172.16/12 is rare — the risk of softening D-01 for corporate/VPN scenarios is accepted."
    accepted_by: "rich"
    accepted_at: "2026-04-23T00:00:00Z"
```

To revert the deviation (matching must_have truth 5 exactly), remove line 227 of `scripts/lib/preflight-lib.sh`:

```bash
# Remove this line from the ip_in_cidr block:
         || ip_in_cidr "${cidr%%/*}" "172.16.0.0/12" \
```

### Round-1 Truths (Regression Check)

All 16 round-1 truths verified in the prior VERIFICATION.md are regression-checked. No changes were made to the artifacts supporting those truths (except the three files touched by plan 01-09, which are directly verified above).

| Truth Area | Status |
|------------|--------|
| preflight.sh exists, bash -n OK, set -u not set -e | VERIFIED (bash -n confirmed) |
| All 14 PRE-xx checks structurally present | VERIFIED (regression — preflight.sh structure unchanged) |
| preflight-lib.sh with all helpers and preflight_check_* functions | VERIFIED (preflight_check_mirrored_mode() still has exactly 1 definition) |
| config/wslconfig, wsl.conf, hwclock-resume.service | VERIFIED (regression — unchanged) |
| .tool-versions 9 pins | VERIFIED (regression — unchanged) |
| .env.example GITHUB_* keys | VERIFIED (regression — unchanged) |
| .gitignore excludes .env | VERIFIED (regression — unchanged) |
| docs/wsl-networking.md | VERIFIED (regression — unchanged) |
| bats suites (5 files, 25 tests) | VERIFIED — 25 ok, 0 not ok confirmed this round |
| install-docker.sh CR-02 (jq-merge default-runtime) | VERIFIED (regression — unchanged from plan 01-08) |
| install-nvidia-container-toolkit.sh CR-01 (direct jq key access) | VERIFIED (regression — unchanged) |
| install-tools.sh idempotent asdf installer | VERIFIED (regression — unchanged) |

**No regressions detected.**

### Required Artifacts

| Artifact | Status | Details |
|----------|--------|---------|
| `scripts/preflight.sh` | VERIFIED | PRE-12 PowerShell call updated; PRE-05 k9s parser updated; bash -n clean |
| `scripts/lib/preflight-lib.sh` | VERIFIED (with WR-02 caveat) | `preflight_check_mirrored_mode()` rewritten with wsl.exe authoritative pre-check + warn()-downgrade. 172.16.0.0/12 present — WR-02 scope question awaits human decision. |
| `scripts/install-docker.sh` | VERIFIED | Section 0 includes util-linux-extra (header, dpkg -s guard, apt-get install, log messages) |
| `scripts/install-nvidia-container-toolkit.sh` | VERIFIED (regression) | Unchanged by plan 01-09; CR-01/CR-02 fixes from plan 01-08 intact |
| `scripts/install-tools.sh` | VERIFIED (regression) | Unchanged |
| `config/hwclock-resume.service` | VERIFIED (regression) | ExecStart=/sbin/hwclock --hctosys — now functional post util-linux-extra install |

### Key Link Verification

| From | To | Via | Status |
|------|----|----|-------|
| scripts/preflight.sh PRE-12 | Windows UTC epoch | `powershell.exe -NoProfile -Command '[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()'` | WIRED — line 327 confirmed |
| scripts/preflight.sh PRE-05 k9s case | k9s version string | `k9s version 2>/dev/null \| grep -oP 'Version:\s+\K\S+'` | WIRED — line 246 confirmed |
| scripts/lib/preflight-lib.sh mirrored_mode | wsl.exe authoritative signal | `wsl.exe --status 2>/dev/null \| tr -d '\r'` + grep -qiE | WIRED — lines 178-185 confirmed; NUL-strip behavior verified |
| scripts/install-docker.sh Section 0 | /sbin/hwclock binary | `sudo apt-get install -y ... util-linux-extra` guarded by `dpkg -s util-linux-extra` | WIRED — lines 36, 40 confirmed |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| preflight.sh syntax valid | `bash -n scripts/preflight.sh` | exit 0 | PASS |
| preflight-lib.sh syntax valid | `bash -n scripts/lib/preflight-lib.sh` | exit 0 | PASS |
| install-docker.sh syntax valid | `bash -n scripts/install-docker.sh` | exit 0 | PASS |
| All bats tests pass | `bats tests/bats/ --tap` | 25 ok, 0 not ok | PASS |
| PRE-12 fix: UtcNow.ToUnixTimeSeconds present | `grep -c 'UtcNow\.ToUnixTimeSeconds' scripts/preflight.sh` | 1 | PASS |
| PRE-12 fix: old Get-Date -UFormat %s absent | `grep -c 'Get-Date -UFormat %s' scripts/preflight.sh` | 0 | PASS |
| PRE-05 fix: grep -oP 'Version:' present | `grep -c "grep -oP 'Version:" scripts/preflight.sh` | 1 | PASS |
| PRE-05 functional: version extraction | `echo 'Version:    v0.50.18' \| grep -oP 'Version:\s+\K\S+'` | `v0.50.18` | PASS |
| PRE-05 functional: substring match | `echo 'v0.50.18' \| grep -qF '0.50.18'` | exit 0 | PASS |
| hwclock fix: util-linux-extra references | `grep -c 'util-linux-extra' scripts/install-docker.sh` | 7 | PASS |
| hwclock fix: dpkg -s guard present | `grep -c 'dpkg -s util-linux-extra' scripts/install-docker.sh` | 1 | PASS |
| hwclock fix: apt-get install line | `grep -q 'apt-get install -y ca-certificates curl gnupg jq util-linux-extra'` | match | PASS |
| PRE-03 fix: wsl.exe --status consulted | `grep -c 'wsl\.exe --status' scripts/lib/preflight-lib.sh` | 8 | PASS |
| PRE-03 fix: 192.168.0.0/16 present | `grep -q '192\.168\.0\.0/16' scripts/lib/preflight-lib.sh` | match | PASS |
| PRE-03 fix: 10.0.0.0/8 present | `grep -q '10\.0\.0\.0/8' scripts/lib/preflight-lib.sh` | match | PASS |
| PRE-03 fix: 172.16.0.0/12 present (WR-02) | `grep -q '172\.16\.0\.0/12' scripts/lib/preflight-lib.sh` | match — DEVIATION from truth 5 | WARNING |
| PRE-03 fix: home-router message present | `grep -q 'home-router subnet' scripts/lib/preflight-lib.sh` | match | PASS |
| PRE-03 fix: one function definition | `grep -c '^preflight_check_mirrored_mode()' scripts/lib/preflight-lib.sh` | 1 | PASS |
| WR-01 encoding: bash strips NUL from UTF-16LE | simulation with `printf 'n\x00e\x00t\x00w\x00o\x00r\x00k\x00...'` | `networkingMode: mirrored` after NUL strip; grep MATCHES | PASS (WR-01 FALSE POSITIVE) |
| Commits documented in summary exist | `git log --oneline \| grep '7934de7\|b38047f\|7d0d44e'` | 3 commits found | PASS |
| Plan 01-08 CR-01 preserved | `grep -v '^[[:space:]]*#' scripts/install-nvidia-container-toolkit.sh \| grep -c '_key='` | 0 | PASS |
| Plan 01-08 CR-02 preserved | `grep -c 'deferring default-runtime' scripts/install-docker.sh` | 1 | PASS |

### Requirements Coverage

All 24 requirement IDs assigned to Phase 1 in REQUIREMENTS.md carry forward from the prior round-1 verification. Plan 01-09 claims: HOST-06, HOST-01, PRE-03, PRE-05, PRE-12, TOOLS-01.

| Requirement | Round-2 Status | Notes |
|-------------|---------------|-------|
| HOST-06 | SATISFIED | util-linux-extra now installed → hwclock-resume.service ExecStart functional |
| PRE-03 | SATISFIED (with WR-02 caveat) | Resource floor check present under "System resources" section; mirrored-mode check rewritten with authoritative wsl.exe pre-check. 172.16.0.0/12 scope question pending human decision. |
| PRE-05 | SATISFIED | k9s version parser fixed — grep -oP 'Version:\s+\K\S+' |
| PRE-12 | SATISFIED | UtcNow.ToUnixTimeSeconds() — TZ-independent UTC epoch |
| HOST-01 | SATISFIED (regression) | config/wslconfig unchanged |
| TOOLS-01 | SATISFIED (regression) | .tool-versions 9 pins unchanged |
| All other 18 IDs | SATISFIED (regression) | Verified in round-1, unchanged by plan 01-09 |

No ORPHANED requirements. REQUIREMENTS.md maps all 24 Phase 1 IDs (HOST-01..07, TOOLS-01..03, PRE-01..14) to Phase 1; all are covered.

**Note on PRE-03 label mismatch:** REQUIREMENTS.md defines PRE-03 as "resource floor (cores/RAM/disk)". The script's internal comment labels mirrored-mode detection as PRE-03. The resource floor check IS implemented (under "System resources" section, lines 47-80 of preflight.sh) but without a PRE-03 label in the script. This numbering drift was established in earlier plans and is not a round-2 regression. Both behaviors exist in the script.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| scripts/lib/preflight-lib.sh | 227 | `ip_in_cidr "${cidr%%/*}" "172.16.0.0/12"` — CIDR range not in must_have truth 5 | WARNING (WR-02) | Softens D-01 enforcement for 172.16/12 networks; internal plan inconsistency (task action authorized it, truth did not). Human decision required. |
| All prior anti-patterns from round-1 | — | Carry forward (stale header comment in install-nvidia-container-toolkit.sh, cosmetic issues) | INFO | Unchanged from prior round |

### Human Verification Required

#### 1. Live re-run of preflight.sh on rich@Area-51 (Phase Goal Re-validation)

**Test:** On the `rich@Area-51` WSL2 Ubuntu 24.04.2 box: (a) run `bash scripts/install-docker.sh` to pick up the `util-linux-extra` install, then (b) run `bash scripts/preflight.sh`
**Expected:** All 14 PRE-xx checks pass; exit 0. Specifically verify:
  - PRE-12 reports skew < 30s (not ~14400s EDT offset)
  - PRE-05 k9s reports `v0.50.18 (matches 0.50.18)` (not ASCII art banner)
  - PRE-03 emits `warn` (not `fail`) for 192.168.1.1 home-router subnet overlap
  - `command -v hwclock` returns `/sbin/hwclock` or `/usr/sbin/hwclock` after install-docker.sh
**Why human:** Only a live re-run confirms the 3 `pass_with_caveats` entries in 01-HUMAN-UAT.md Test 4 are now closed.

#### 2. WR-02 Policy Decision: 172.16.0.0/12 in home-router CIDR whitelist

**Test:** Review `scripts/lib/preflight-lib.sh:225-228`. Decide: keep 172.16.0.0/12 (accept the scope expansion with an override) or remove it (match must_have truth 5 exactly).
**Expected:** Either add an override entry to VERIFICATION.md frontmatter OR remove the `|| ip_in_cidr "${cidr%%/*}" "172.16.0.0/12"` line.
**Why human:** The plan has an internal inconsistency (truth 5 vs task action body). This is a policy decision about whether to widen D-01's enforcement gap for 172.16/12 networks. The verifier cannot resolve conflicting plan intent — only the developer/planner can.

## Gaps Summary

**One structural gap remains** (WR-02 scope expansion). WR-01 is resolved as a false alarm.

**WR-01 (FALSE POSITIVE — CLOSED):** The code review's concern that `wsl.exe --status` UTF-16LE output would prevent the `grep -qiE` pattern from matching is incorrect. Bash `$()` command substitution strips NUL bytes from the output, leaving a valid ASCII string that grep matches correctly. The hard-fail path for explicitly-mirrored systems works. Truth 6 is VERIFIED.

**WR-02 (REAL DEVIATION — awaiting human decision):** `172.16.0.0/12` at `scripts/lib/preflight-lib.sh:227` exceeds the scope authorized by must_have truth 5. The task action body in 01-09-PLAN.md did explicitly include 172.16/12, creating an internal plan inconsistency. Impact is narrowly scoped to 172.16/12 networks with a Windows host as default gateway — uncommon for the target home-developer platform but potentially relevant for corporate/VPN users.

**Live re-run** on `rich@Area-51` is still required to close the phase (this was also the remaining item from round-1). The 4 code-level fixes are verified correct at the structural level — the phase is as far as it can go without a live box.

---

_Verified: 2026-04-23T15:30:00Z_
_Verifier: Claude (gsd-verifier)_
_Re-verification: Yes — round 2 after plan 01-09 gap closure_
_Prior rounds: round-1 (plan 01-08, status: human_needed, score: 16/16)_
