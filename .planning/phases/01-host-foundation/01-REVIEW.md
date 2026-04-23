---
phase: 01-host-foundation
reviewed: 2026-04-23T00:00:00Z
depth: standard
scope: incremental
prior_review: gap-plan 01-08 (CR-01, CR-02) — round 1
round: 2
files_reviewed: 3
files_reviewed_list:
  - scripts/install-docker.sh
  - scripts/lib/preflight-lib.sh
  - scripts/preflight.sh
findings:
  blocker: 0
  critical: 0
  warning: 2
  info: 3
  total: 5
counts:
  blocker: 0
  critical: 0
  warning: 2
  info: 3
  total: 5
status: issues_found
---

# Phase 01: Code Review Report (round 2, post gap-plan 01-09)

**Reviewed:** 2026-04-23
**Depth:** standard (incremental — scope limited to the three files changed by gap-plan 01-09)
**Files Reviewed:** 3
**Status:** issues_found (2 warnings, 3 info)

## Summary

Gap-plan 01-09 targeted four gaps surfaced by round-1 human UAT on
rich@Area-51:

1. **PRE-12 (preflight.sh)** — switched PowerShell call from `Get-Date -UFormat %s`
   (returns local-time-as-if-UTC seconds) to `[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()`
   (returns true UTC epoch). Fix is correct and surgical.
2. **PRE-05 (preflight.sh)** — switched k9s version parser from `head -1`
   (returned the ASCII-art banner border) to `grep -oP 'Version:\s+\K\S+'`.
   Fix is correct for the default k9s version output format.
3. **PRE-03 (preflight-lib.sh)** — refactored `preflight_check_mirrored_mode()`
   to add an authoritative `wsl.exe --status` pre-check plus a `warn()` downgrade
   for the home-router shared-subnet false-positive pattern.
4. **hwclock (install-docker.sh)** — added `util-linux-extra` to Section 0 prereqs
   with a `dpkg -s`-guarded install. Package provides `/sbin/hwclock` (via usrmerge
   symlink to `/usr/sbin/hwclock`) on Ubuntu 24.04, so `hwclock-resume.service`
   ExecStart is now functional.

`bash -n` is clean on all three files. Sections 1/2/4 are straightforward
and correct as written. The PRE-03 refactor (gap 4) is the most complex and
is where the non-trivial findings concentrate:

- **WR-01 (warning):** The authoritative `wsl.exe --status` pre-check may be
  effectively dead code because `wsl.exe` output is UTF-16LE by default when
  invoked from WSL interop. The ASCII grep pattern will not match UTF-16-
  encoded bytes, so the hard-fail path for explicitly-mirrored systems
  silently falls through to the heuristic — and in the home-router scenario
  the heuristic downgrades to `warn()`. Net effect: D-01's hard-fail on
  explicit mirrored signal is not reliably enforced. This defect was not
  exercised by the round-1 UAT because the test host was not in mirrored
  mode.
- **WR-02 (warning):** The home-router CIDR whitelist in the downgrade
  predicate includes `172.16.0.0/12`, but the plan's must_have truths and
  the gap-closure prompt authorize only `192.168.0.0/16` and `10.0.0.0/8`.
  `172.16.0.0/12` is predominantly used for VPN tunnels and corporate LANs,
  not home routers — so including it widens the false-positive downgrade to
  contexts the plan explicitly did not approve. Deviation from approved
  scope.
- Three info-level items cover a redundant IP-equality check, non-portable
  PCRE grep usage (acceptable under Ubuntu pin), and the standard `dpkg -s`-
  includes-deinstall-state edge case (consistent with pre-existing pattern
  in the same file).

None of the round-1 findings in the prior `01-REVIEW.md` are re-evaluated
here — scope is limited to the three files touched by gap-plan 01-09.

## Warnings

### WR-01: `wsl.exe --status` output is UTF-16LE by default — the authoritative hard-fail branch silently fails to match

**File:** `scripts/lib/preflight-lib.sh:178-185`

**Issue:** Step 0 of `preflight_check_mirrored_mode()` captures `wsl.exe --status`
and greps for `networkingMode: mirrored`:

```bash
if command -v wsl.exe >/dev/null 2>&1; then
  wsl_status="$(wsl.exe --status 2>/dev/null | tr -d '\r' || true)"
fi
if [[ -n "$wsl_status" ]] && echo "$wsl_status" | grep -qiE 'networkingMode:[[:space:]]*mirrored'; then
  fail "Mirrored networking confirmed by wsl.exe --status ..."
  return 1
fi
```

`wsl.exe` by default writes stdout as UTF-16LE (with or without BOM depending
on version) when invoked from a non-Windows caller. This is a well-documented
WSL interop quirk (see microsoft/WSL#4607, and the `WSL_UTF8=1` environment
variable introduced in WSL 0.64.0 specifically to opt into UTF-8 output).
Without `WSL_UTF8=1` in the environment, or without piping through
`iconv -f UTF-16LE -t UTF-8`, every ASCII byte in the output is followed by
a NUL byte, e.g. `networkingMode: mirrored` becomes
`n\x00e\x00t\x00w\x00o\x00r\x00k\x00i\x00n\x00g\x00M\x00o\x00d\x00e\x00:\x00 \x00m\x00i\x00r\x00r\x00o\x00r\x00e\x00d\x00`.

Consequences:

1. `[[ -n "$wsl_status" ]]` is **true** (the variable is non-empty bytes).
2. `grep -qiE 'networkingMode:[[:space:]]*mirrored'` is **false** — there
   is no contiguous `networkingMode` substring in the NUL-interleaved bytes.
3. The code falls through to the heuristic. On a host that IS actually in
   mirrored mode AND is on a home-router subnet (Windows host is the
   default gateway, WSL shares the /24, CIDR in 192.168/16 or 10/8), the
   downgrade predicate fires and `warn()` is emitted instead of the
   D-01-mandated `fail()`.

The round-1 UAT did not exercise this path because the test host was in NAT
mode — the authoritative check short-circuited trivially (empty output) and
the heuristic correctly reported NAT. The defect is latent until a user
actually runs the preflight on a mirrored-mode WSL and expects the
authoritative hard-fail promised by the function's policy comment and the
plan's must_have truth #6.

Failure mode: D-01's "hard-fail on explicit mirrored signal" is not
reliably enforced. On a home network in mirrored mode, the user gets a
`warn()` advising them to "set networkingMode=NAT" rather than the `fail()`
which blocks the preflight. That is the opposite of the plan's stated
policy.

**Fix:** Normalize the encoding of `wsl.exe` stdout before the grep. Two options:

Option A — export `WSL_UTF8=1` just for this invocation:

```bash
local wsl_status=""
if command -v wsl.exe >/dev/null 2>&1; then
  wsl_status="$(WSL_UTF8=1 wsl.exe --status 2>/dev/null | tr -d '\r' || true)"
fi
```

Option B — iconv the pipe (works regardless of WSL version / env var support):

```bash
local wsl_status=""
if command -v wsl.exe >/dev/null 2>&1; then
  # wsl.exe emits UTF-16LE by default; convert to UTF-8 before grep.
  # iconv failure (e.g., BOM-less input on older WSL) falls back to the raw
  # bytes, which is a no-op for the subsequent check on a non-mirrored host.
  wsl_status="$(wsl.exe --status 2>/dev/null \
    | iconv -f UTF-16LE -t UTF-8 -c 2>/dev/null \
    | tr -d '\r' \
    || true)"
fi
```

Then add a bats test that feeds a fixture containing the literal string
`networkingMode: mirrored` (UTF-8) through a stub `wsl.exe` and asserts
`fail()` is recorded — this would have caught the defect during UAT.

---

### WR-02: home-router CIDR whitelist includes `172.16.0.0/12`, exceeding plan-authorized scope

**File:** `scripts/lib/preflight-lib.sh:225-229`

**Issue:** The downgrade predicate classifies an overlapping CIDR as a
home-router range using this check:

```bash
local is_home_router_cidr=0
if ip_in_cidr "${cidr%%/*}" "192.168.0.0/16" \
   || ip_in_cidr "${cidr%%/*}" "10.0.0.0/8" \
   || ip_in_cidr "${cidr%%/*}" "172.16.0.0/12"; then
  is_home_router_cidr=1
fi
```

The plan's must_have truth explicitly enumerates only two ranges (01-09-PLAN.md):

> the overlapping CIDR is a common home-router range (`192.168.0.0/16` or
> `10.0.0.0/8` private ranges)

and the gap-closure prompt states the same two ranges. `172.16.0.0/12` was
added by the executor but was not authorized by the plan.

Why it matters: `172.16.0.0/12` is an RFC-1918 private range, but its real-
world usage is dominated by **corporate LAN** and **VPN tunnel** endpoints,
not consumer home routers. Common consumer routers (Asus, Netgear, TP-Link,
Eero, Google Wifi, ISP-provided gateways) default almost universally to
`192.168.x.x` or occasionally `10.x.x.x`. Including `172.16/12` therefore
broadens the false-positive downgrade to scenarios where:

- A corporate-issued laptop is in the office LAN at e.g. `172.20.10.0/24`,
  and an actually-misconfigured mirrored-mode WSL inherits the same CIDR.
  The heuristic fires; under this code, it downgrades to `warn()` instead
  of `fail()` — softening D-01 in a context the plan did not permit.
- A corporate VPN places WSL at e.g. `172.31.x.x` (AWS VPC default) while
  the host's gateway is the VPN endpoint in the same block. Same outcome.

Neither scenario is a "home network" the plan intended to accommodate.

**Fix:** Drop `172.16.0.0/12` from the whitelist; leave the two plan-
authorized ranges:

```bash
local is_home_router_cidr=0
if ip_in_cidr "${cidr%%/*}" "192.168.0.0/16" \
   || ip_in_cidr "${cidr%%/*}" "10.0.0.0/8"; then
  is_home_router_cidr=1
fi
```

If there is later evidence that 172.16/12 is a legitimate home-router
range needing the same downgrade, record that as a new gap and amend the
plan — do not silently expand scope.

## Info

### IN-01: `windows_ip == gw_ip` comparison is redundant with `windows_ip_source == "gateway"`

**File:** `scripts/lib/preflight-lib.sh:231`

**Issue:** The downgrade predicate reads:

```bash
if [[ "$windows_ip_source" == "gateway" && "$windows_ip" == "$gw_ip" && $is_home_router_cidr -eq 1 ]]; then
```

The `"$windows_ip" == "$gw_ip"` conjunct is dead. Tracing the assignment
flow (lines 198-207):

```bash
gw_ip="$(ip -4 route show default 2>/dev/null | awk '/via/ {print $3}' | head -1)"
[[ -n "$gw_ip" ]] && windows_ip="$gw_ip"          # only non-empty branch sets it

local windows_ip_source="gateway"
if [[ -z "$windows_ip" ]]; then                    # runs only when gw_ip empty
  windows_ip="$(grep -m1 '^nameserver' /etc/resolv.conf ...)"
  windows_ip_source="resolv.conf"
fi
```

When `windows_ip_source == "gateway"`, the resolv.conf fallback block did
NOT execute, which implies `[[ -z "$windows_ip" ]]` was false at that
point, which implies `windows_ip` was set by the previous line to `gw_ip`.
So `windows_ip == gw_ip` is tautologically true whenever
`windows_ip_source == "gateway"`. The explicit comparison is defensive
noise — it adds no protection.

Not a bug (the conjunct is harmless). Minor readability issue and a
potential source of confusion for future maintainers who might think the
comparison guards against some edge case that does not actually exist.

**Fix (optional):** Drop the redundant conjunct and document that
`source=="gateway"` already implies the IPs match:

```bash
# windows_ip_source=="gateway" implies windows_ip was set from gw_ip (see
# lines 199-200), so no separate equality check is needed.
if [[ "$windows_ip_source" == "gateway" && $is_home_router_cidr -eq 1 ]]; then
```

### IN-02: PRE-05 k9s parser relies on GNU-grep PCRE (`-P` + `\K`) — non-portable, but acceptable under Ubuntu pin

**File:** `scripts/preflight.sh:246`

**Issue:** The new k9s parser:

```bash
k9s)     k9s version 2>/dev/null | grep -oP 'Version:\s+\K\S+' ;;
```

uses two PCRE-only features: the `-P` flag and the `\K` "reset match
start" operator. Both require GNU grep built with libpcre, which is
available on Ubuntu 24.04 by default (via the `grep` package shipped in
`minimal`), so on the project's pinned platform this is fine. However:

- On Alpine, BusyBox, macOS `/usr/bin/grep` (BSD grep), or any stripped
  GNU grep without PCRE, the command exits 2 with no output; the caller
  records `actual_ver="unknown"` and reports a version mismatch even when
  k9s is installed correctly.
- The project is explicitly pinned to Ubuntu 24.04 (PRE-02), so this is
  not a live defect. It is a portability note in case any of the library
  functions are ever exercised from a non-Ubuntu bats harness.

Sed-based or awk-based alternatives would be portable but longer.
Leaving as-is is consistent with the plan; documenting here for the
record.

**Fix (optional, portability only):**

```bash
k9s)     k9s version 2>/dev/null | awk '/^Version:/ {print $2; exit}' ;;
```

Equivalent behavior with POSIX-only tooling.

### IN-03: `dpkg -s util-linux-extra` considers the `deinstall` (config-only) state as "installed"

**File:** `scripts/install-docker.sh:36`

**Issue:**

```bash
&& dpkg -s util-linux-extra >/dev/null 2>&1
```

`dpkg -s` prints package metadata and exits 0 for packages in status
`install ok installed` AND for packages in status
`deinstall ok config-files` (i.e., purged binaries but left config).
For `util-linux-extra`, the binary `/sbin/hwclock` is removed on
`apt-get remove` (but not purge). So a user who ran
`sudo apt-get remove util-linux-extra` and then re-runs
`install-docker.sh` would see the `dpkg -s` guard succeed, skip the
apt-get install, and proceed to enable `hwclock-resume.service`
pointing at a non-existent binary. The unit would then silently fail on
resume — exactly the scenario gap 2 was closing.

This is a pre-existing pattern in this file (same issue affects
`dpkg -s ca-certificates` on line 34), so consistency argues for
leaving as-is. Flagging only for awareness and for the possibility of a
one-time cleanup across all prereq guards.

**Fix (optional, robustness across all guards in this block):**

```bash
dpkg_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'
}

if have jq \
   && have gpg \
   && dpkg_installed ca-certificates \
   && have curl \
   && dpkg_installed util-linux-extra; then
```

---

_Reviewed: 2026-04-23_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard (incremental, round 2)_
_Scope: three files touched by gap-plan 01-09. Prior-round findings for
other files (and for install-nvidia-container-toolkit.sh) carry forward in
git history; this report does not re-evaluate them._
