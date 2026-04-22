---
phase: 01-host-foundation
reviewed: 2026-04-22T18:50:00Z
depth: standard
files_reviewed: 17
files_reviewed_list:
  - .env.example
  - .gitignore
  - .tool-versions
  - config/hwclock-resume.service
  - config/wsl.conf
  - config/wslconfig
  - docs/wsl-networking.md
  - scripts/install-docker.sh
  - scripts/install-nvidia-container-toolkit.sh
  - scripts/install-tools.sh
  - scripts/lib/preflight-lib.sh
  - scripts/preflight.sh
  - tests/bats/preflight-pre01.bats
  - tests/bats/preflight-pre02.bats
  - tests/bats/preflight-pre09.bats
  - tests/bats/preflight-pre11.bats
  - tests/bats/preflight-pre13.bats
  - tests/bats/test_helper.bash
findings:
  critical: 2
  warning: 9
  info: 6
  total: 17
status: issues_found
---

# Phase 01: Code Review Report

**Reviewed:** 2026-04-22T18:50:00Z
**Depth:** standard
**Files Reviewed:** 17 (18 requested; `.env.example` could not be read because
the orchestrator's permission settings denied access to that path — review of
that file was skipped)
**Status:** issues_found

## Summary

Adversarial review of the Phase 01 host-foundation implementation surfaces two
blocker-class defects that will break the installer on the happy path:

1. **`install-nvidia-container-toolkit.sh` cannot succeed.** The jq expressions
   used to read `default-runtime` from `daemon.json` are malformed — they select
   a string literal instead of a key, so the pre-check always fails and the
   post-verify always (spuriously) reports that `nvidia-ctk` clobbered
   `default-runtime`. Plan 03 is unrunnable as written.

2. **`install-docker.sh` bricks Docker on a fresh host.** It writes
   `default-runtime: "nvidia"` to `daemon.json` and restarts Docker *before*
   `install-nvidia-container-toolkit.sh` has registered the `nvidia` runtime.
   Docker refuses to start when `default-runtime` references an undefined
   runtime, so the `systemctl restart docker` call exits non-zero and the
   install stops. The nvidia toolkit script then refuses to run because its
   own pre-check requires Docker to be reachable (`docker info`) — the user is
   wedged.

Additional warnings concern shell correctness (PRE-09 accepts quoted-empty
tokens, `show_tool_version` is invoked before it is defined, version regex
accepts downgrades, brittle grep counting, imprecise Docker filters) and two
process hygiene issues (PRE-14 pulls `busybox` so the section is not truly
read-only; the outer FAIL_MSGS summary loses PRE-14's detailed remediation
text because the inner `fail()` runs in a subshell).

## Critical Issues

### CR-01: `install-nvidia-container-toolkit.sh` jq expression is a string literal, not a key access — script cannot pass

**File:** `scripts/install-nvidia-container-toolkit.sh:40-46`, also `:101-105`

**Issue:** The variable `_key` is set to the literal string `"default-runtime"`
(double-quotes included in the value) and is then interpolated into the jq
program as `${_key} // empty`. After shell expansion the jq expression becomes:

```jq
"default-runtime" // empty
```

That expression is a **string constant**, not a key access on the input. jq
evaluates it to the string `default-runtime` for any input (it never looks at
the file). To read a key whose name contains a hyphen, the expression must
start with a dot: `."default-runtime"`.

Verified locally against `jq 1.7`:

```
$ echo '{"default-runtime":"nvidia"}' | jq -r '"default-runtime" // empty'
default-runtime                         # <-- string literal, wrong
$ echo '{"default-runtime":"nvidia"}' | jq -r '."default-runtime" // empty'
nvidia                                  # <-- key access, correct
```

Consequences, traced through the script:

- **Line 41–46 (pre-check):** `_dr_check` is always the literal `default-runtime`,
  never `nvidia`. The guard `[[ "$_dr_check" != "nvidia" ]]` always fires and
  the script exits 1 with the misleading message "daemon.json does not have
  default-runtime=nvidia (expected from install-docker.sh)" even after
  `install-docker.sh` correctly set the key.
- **Line 101–105 (post-verify):** `_dr_post` is also always the literal string.
  Even if execution ever reached this branch, the guard would always fire,
  printing "nvidia-ctk configure clobbered default-runtime in daemon.json —
  manual repair needed" regardless of the real state.

In other words, this script **cannot succeed on the happy path**. Both the
pre-check and the post-verify are broken in the same way.

**Fix:** Prefix with a dot to make it a key access (at both call sites):

```bash
# line 40 — drop the _key indirection entirely, or keep it but add the dot
_dr_check=$(jq -r '."default-runtime" // empty' "$DAEMON_JSON" 2>/dev/null)

# line 101
_dr_post=$(jq -r '."default-runtime" // empty' "$DAEMON_JSON" 2>/dev/null)
```

Remove the `_key` variable — it adds no value and has already caused this
exact mistake twice. Add a bats test that sources the script logic or uses a
stub `DAEMON_JSON` path so the regression is caught before the next run.

### CR-02: `install-docker.sh` writes `default-runtime: nvidia` before the `nvidia` runtime exists — breaks the Docker daemon on restart

**File:** `scripts/install-docker.sh:99-118`

**Issue:** Section 6 unconditionally writes `default-runtime: "nvidia"` into
`/etc/docker/daemon.json` and then runs `sudo systemctl restart docker`. By
the contract documented in `install-nvidia-container-toolkit.sh:9-11`, the
`runtimes.nvidia` key is **not** written by this script — it is only written
later, by `nvidia-ctk runtime configure --runtime=docker`.

Docker refuses to start when `default-runtime` names a runtime that is not
defined under `runtimes`. On a fresh host the sequence is:

1. `scripts/install-docker.sh` runs Section 6.
2. `daemon.json` ends up with `{"default-runtime":"nvidia","dns":[...]}` and
   no `runtimes.nvidia` entry.
3. `systemctl restart docker` fails (dockerd logs "unable to find default
   runtime: nvidia").
4. `set -euo pipefail` is in effect (line 13), so the script exits non-zero
   at the `systemctl restart` call.
5. The user runs `scripts/install-nvidia-container-toolkit.sh` to recover.
   Its pre-check (line 31) requires `docker info` to succeed — but the daemon
   is down, so the toolkit installer also exits 1. **The user is wedged and
   must hand-edit `/etc/docker/daemon.json` to recover.**

This is the inverse of the chicken-and-egg that H1 was supposed to protect
against. The H1 fix guarded Plan 03 against running before Plan 02 wrote
`default-runtime`; it did not consider that Plan 02 writing `default-runtime`
without a matching runtime stanza is itself a Docker-breaking change.

**Fix:** Either (a) do not set `default-runtime: "nvidia"` in
`install-docker.sh` — move that write into
`install-nvidia-container-toolkit.sh` where the runtime is registered in the
same transaction; or (b) in `install-docker.sh`, skip setting
`default-runtime` until the `nvidia` runtime is already present, and emit an
`info` line telling the user it will be set by `install-nvidia-container-toolkit.sh`.
Option (a) is simpler and better matches "who owns which key" in `daemon.json`.

If the current ownership split is load-bearing for other reasons, the minimal
alternative is to detect the situation and stage the write:

```bash
# Only set default-runtime if nvidia runtime is already registered.
if sudo jq -e '.runtimes.nvidia' "$DAEMON_JSON" >/dev/null 2>&1; then
  merged=$(echo "$current" | jq --arg dr "$DESIRED_RUNTIME" --argjson dns "$DESIRED_DNS" \
    '. + {"default-runtime": $dr, "dns": $dns}')
else
  merged=$(echo "$current" | jq --argjson dns "$DESIRED_DNS" '. + {"dns": $dns}')
  info "deferring default-runtime=nvidia until nvidia runtime is registered (install-nvidia-container-toolkit.sh)"
fi
```

And add an integration test that runs Plan 02 → `docker info` → Plan 03 on a
stub host, not just `jq`-level unit tests.

## Warnings

### WR-01: PRE-09 accepts quoted-empty tokens (`GITHUB_TOKEN=""`) as "set"

**File:** `scripts/lib/preflight-lib.sh:112-121`

**Issue:** `val="$(grep -E "^${key}=" "$env_file" | cut -d= -f2-)"` captures
the RHS of the assignment *as written*. If the user literally wrote
`GITHUB_TOKEN=""` (two quote characters), `val` is the two-character string
`""`, which is non-empty — the check passes. The Phase 01 test at
`tests/bats/preflight-pre09.bats:44-48` even exercises the non-empty
placeholder path, so this behaviour is reached in normal use.

This is not a security hole (the user supplied the value) but it defeats the
intent of the check, which is to confirm that a real secret is present. It
will also mask a common copy-paste error where users leave the quoted
placeholder in place.

**Fix:** Strip surrounding quotes and whitespace before testing for
emptiness:

```bash
val="$(grep -E "^${key}=" "$env_file" 2>/dev/null | head -1 | cut -d= -f2-)"
# strip optional surrounding single/double quotes, then trim whitespace
val="${val%\"}"; val="${val#\"}"
val="${val%\'}"; val="${val#\'}"
val="${val#"${val%%[![:space:]]*}"}"
val="${val%"${val##*[![:space:]]}"}"
if [[ -z "$val" ]]; then ... ; fi
```

Also add `head -1` so a duplicate key does not produce a multi-line value.
Add a bats case for `GITHUB_TOKEN=""` that expects failure.

### WR-02: `check_required` is called before `show_tool_version` is defined

**File:** `scripts/preflight.sh:231-252`

**Issue:** `check_required()` is defined at line 231 and invokes
`show_tool_version "$1"` inside its body (line 232). `show_tool_version()`
itself is not defined until line 235 — *after* `check_required` but *before*
the three calls at lines 250–252 — so by the time the three
`check_required git|curl|jq` calls actually execute, `show_tool_version` does
exist.

The code happens to work because Bash looks functions up at call time, not at
definition time, but it is fragile: any future refactor that moves one of the
`check_required git` calls above the `show_tool_version()` definition, or
that adds an early `check_required` call to the top of the script, will
produce `show_tool_version: command not found` and mask the tool's version in
the output. Reviewers reading top-to-bottom will also be confused because
the reference appears before the definition.

**Fix:** Move the `show_tool_version()` definition **above** `check_required()`.
Both are small helpers — put `show_tool_version` first, then `check_required`,
then the `check_required git|curl|jq` calls.

### WR-03: `install-tools.sh` asdf version guard accepts downgrades (e.g. `0.2.x`, `0.3.x`)

**File:** `scripts/install-tools.sh:42`

**Issue:** The regex `^0\.(1[89]|[2-9])` is intended to match "0.18, 0.19 or
0.20+", but `[2-9]` matches any single digit in `[2-9]`, so it also matches
string versions like `0.2.0`, `0.3.5`, `0.9.9` — all of which are *older*
than `0.18`. If a host has a pre-rewrite `asdf 0.9.x` installed system-wide
(unusual but possible on older Ubuntu images), the guard reports "already
done, skipping" and the Go-rewrite-dependent Section 3 shell-init code then
breaks because the old Bash asdf is on PATH.

The asdf project only ever released `0.5.x`–`0.17.x` of the Bash variant
before the Go rewrite, so the risk is modest, but the regex does not express
the intent.

**Fix:** Anchor on two-digit minor versions to exclude 0.2–0.9:

```bash
if [[ -x /usr/local/bin/asdf ]] && \
   /usr/local/bin/asdf --version 2>/dev/null | grep -qE '^v?0\.(1[89]|[2-9][0-9])(\.|$)'; then
```

Or, more robustly, parse the version into its own comparison:

```bash
if [[ -x /usr/local/bin/asdf ]]; then
  have_ver="$(/usr/local/bin/asdf --version 2>/dev/null | sed 's/^v//')"
  have_major="${have_ver%%.*}"; rest="${have_ver#*.}"; have_minor="${rest%%.*}"
  if (( have_major == 0 && have_minor >= 18 )) || (( have_major >= 1 )); then
    info "already done, skipping: asdf ${have_ver}"
    return
  fi
fi
```

### WR-04: PRE-14 mutates host Docker image cache despite "read-only" claim

**File:** `scripts/preflight.sh:385-394`, `docs/wsl-networking.md:144-163`

**Issue:** `preflight.sh` is documented as read-only with respect to host
state, with PRE-14 explicitly called out as the "sole exception" whose
Docker resources are *ephemeral and trap-cleaned*. The probe uses
`docker run ... busybox ...` (lines 388–393). If `busybox:latest` is not
already present on the host, Docker **pulls it**, and that pull persists
after cleanup — the image cache is modified. The claim in `docs/wsl-networking.md:157`
("All mutations are ephemeral and trap-cleaned") is therefore incorrect.

This is not a safety issue, but the documentation is wrong and would surprise
a user auditing what preflight touches. On an air-gapped host, the probe will
additionally fail silently at the pull step rather than with a clear
"image unavailable" message.

**Fix:** Either (a) pin a tiny, pre-known-present image (harder — there isn't
one reliably), or (b) update the docs and the in-script comment to say "PRE-14
pulls `busybox:latest` if not present and runs two ephemeral containers on a
dedicated network; only the containers and network are trap-cleaned, the
pulled image is retained in the cache". Also add an explicit "if pull fails,
print actionable error" branch:

```bash
docker pull busybox:latest >/dev/null 2>&1 || {
  warn "PRE-14: cannot pull busybox — network unavailable, skipping bridge probe"
  exit 0
}
```

### WR-05: PRE-14 subshell loses detailed failure message from outer summary

**File:** `scripts/preflight.sh:361-424`

**Issue:** The PRE-14 probe runs in a `( ... )` subshell that has its own
copy of `FAIL`, `FAIL_MSGS`, `PASS`, etc. Inside the subshell, on failure,
the code calls `fail "bridge-curl probe FAILED — ..."` (line 411) with a
multi-line actionable message. When the subshell exits, those counter
increments and message array entries are discarded. The outer script then
calls `fail "PRE-14 bridge probe failed (see above)"` (line 423) with a
short message.

Result: the final `Blockers:` summary at lines 433–434 prints only the short
"see above" line. A user scrolling the summary at the end of a long preflight
run never sees the remediation pointer (`set networkingMode=NAT`, see
`docs/wsl-networking.md`). The comment at lines 420–422 documents this
limitation but does not mitigate the UX cost.

**Fix:** Move the `fail()` call out of the subshell. Return a numeric rc from
the subshell, and at outer scope call `fail()` with the full remediation
text:

```bash
_pre14_rc=$?
if (( _pre14_rc != 0 )); then
  fail "PRE-14 bridge-curl probe FAILED — Docker custom network DNS is broken.
      In mirrored mode this is a known limitation (moby/moby#48201).
      Fix: set networkingMode=NAT in %USERPROFILE%\\.wslconfig, then run 'wsl --shutdown'.
      See docs/wsl-networking.md for the migration procedure."
fi
```

Inside the subshell, either stay silent on failure or use `printf` directly
so that the ephemeral counters are never touched.

### WR-06: `k3d cluster list` cluster-count uses imprecise `grep -c '"name"'`

**File:** `scripts/preflight.sh:220`

**Issue:** `cluster_count="$(k3d cluster list -o json 2>/dev/null | grep -c '"name"' || true)"`
counts occurrences of the literal string `"name"` anywhere in the JSON output.
Recent `k3d` versions (5.x) emit JSON that includes `"name"` inside
per-cluster metadata (`Nodes[].name`, network metadata), not only in the
top-level cluster object. A single cluster with one server + two agent nodes
can emit 4+ `"name"` occurrences, so the printed warning count
("`${cluster_count}` existing k3d cluster(s)") overstates the number of
clusters.

The cluster listing a few lines later (`k3d cluster list 2>/dev/null | sed`)
prints the accurate human-readable list, so the wrong count is cosmetic, but
it will confuse users.

**Fix:** Count at the top-level JSON array length instead:

```bash
cluster_count="$(k3d cluster list -o json 2>/dev/null | jq 'length' 2>/dev/null || echo 0)"
```

`jq` is already a required system tool per `check_required jq`, so no new
dependency is introduced.

### WR-07: `docker ps --filter 'name=k3d-'` substring-matches any container with `k3d-` in the name

**File:** `scripts/preflight.sh:200, 208`

**Issue:** Docker's `--filter name=...` is a substring match, not a prefix
match. A container named `my-k3d-test` or `legacy-kind3d-foo` would match
`name=k3d-` and be counted as a "k3d cluster container". The subsequent
human-readable listing (`docker ps ... --format '... {{.Names}} ...'`) would
show these spurious entries. The Kind check on line 208 has the same issue
with `name=kind`.

**Fix:** Use a regex anchor via `--filter 'name=^k3d-'` (Docker supports
regex filters with leading `^`):

```bash
k3d_n="$(docker ps -a --filter 'name=^k3d-' --format '{{.Names}}' 2>/dev/null | wc -l)"
kind_n="$(docker ps -a --filter 'name=^kind-' --format '{{.Names}}' 2>/dev/null | wc -l)"
```

Note that `k3d` names its containers `k3d-<cluster>-server-0` etc., so the
anchored prefix is correct for legitimate k3d clusters.

### WR-08: PRE-12 fallback via `sudo -n hwclock --get` cannot parse subsecond-precision timestamps

**File:** `scripts/preflight.sh:327-331`

**Issue:** On Ubuntu 24.04, `hwclock --get --utc` emits timestamps like
`2024-04-22 18:00:00.123456+00:00`. The awk trim `{print $1, $2}` produces
`2024-04-22 18:00:00.123456+00:00` as a single line, but `date -f -` reads
lines one at a time and, on some `date` versions, fails to parse the
fractional-second + timezone combination, leaving `win_epoch` empty and the
check silently falling to the "could not read reference time" warn path.

The primary `powershell.exe` path handles the common case, so this is mostly
a nuisance on systems where PowerShell interop is disabled (uncommon WSL
image customisations).

**Fix:** Normalise the hwclock output before passing to date:

```bash
if [[ -z "$win_epoch" ]]; then
  hw_raw="$(sudo -n hwclock --get --utc 2>/dev/null || echo "")"
  # strip fractional seconds and timezone offset
  hw_clean="$(echo "$hw_raw" | awk '{print $1" "$2}' | sed 's/\.[0-9]*//; s/[+-][0-9:]*$//')"
  win_epoch="$(date -u -d "$hw_clean" +%s 2>/dev/null || echo "")"
fi
```

### WR-09: PRE-09 silently concatenates multi-line values when the key appears more than once

**File:** `scripts/lib/preflight-lib.sh:112-121`

**Issue:** `grep -E "^${key}=" "$env_file"` returns *every* matching line. If
a user's `.env` accidentally contains two `GITHUB_TOKEN=` lines (for example,
after a merge conflict resolution), `cut` runs on both lines and `val`
becomes a two-line string. The `[[ -z "$val" ]]` test evaluates false even if
both values are blank-ish, and the `pass` message reports "GITHUB_TOKEN is
set (value hidden)" — hiding the duplication from the user.

**Fix:** Constrain to the last occurrence (standard dotenv precedence) and
add an explicit duplicate warning:

```bash
matches="$(grep -cE "^${key}=" "$env_file" 2>/dev/null || echo 0)"
if (( matches > 1 )); then
  warn "${key} appears ${matches} times in .env — last occurrence wins"
fi
val="$(grep -E "^${key}=" "$env_file" 2>/dev/null | tail -1 | cut -d= -f2-)"
```

## Info

### IN-01: `info()` helper prints an IMPORTANT message in dim style

**File:** `scripts/install-docker.sh:90`

**Issue:** After adding the user to the docker group, the line `info
"IMPORTANT: run 'newgrp docker' or log out and back in ..."` uses the
`info()` helper, which prints with `C_DIM`. Dim is the visual style for
low-priority breadcrumbs; a security-relevant "IMPORTANT" message should use
`warn` (yellow, tracked in WARN_MSGS so it appears in the final summary) or
its own high-visibility print.

**Fix:** Either upgrade the line to `warn` so it surfaces in the summary, or
introduce a dedicated `notice()` helper that prints in a non-dim colour.

### IN-02: Dead section-number comments in `preflight.sh`

**File:** `scripts/preflight.sh:289, 311, 315, 347, 351, 427`

**Issue:** The section-header comments use non-sequential numbers: "9. .env
secrets", "10. Tool shim precedence", "11. systemd-resolved stub", "12. Clock
skew", "13. cgroup v2", "14. Bridge networking", then "8. Summary" at line
427. The numbers do not match the on-screen section prefixes (the on-screen
section titles use the PRE-NN identifiers, not a sequential numbering). The
Summary comment at line 427 is labelled `---------- 8. Summary ----------`,
which is clearly a stale number from an earlier layout.

**Fix:** Either renumber them sequentially (1..8, with Summary as the final
one) or drop the leading numbers from the comment banners entirely —
on-screen titles already carry the authoritative labels.

### IN-03: Magic repo-codename fallback constant

**File:** `scripts/install-docker.sh:55`

**Issue:** `echo "${UBUNTU_CODENAME:-${VERSION_CODENAME:-noble}}"` hardcodes
`noble` as the final fallback. This is correct today (Ubuntu 24.04 is Noble
Numbat), but if this repo is ever cloned to an Ubuntu 25.04 host that somehow
lacks both env vars, the script would silently install the wrong Docker apt
repo. `scripts/lib/preflight-lib.sh:preflight_check_ubuntu_24_04` already
gates on 24.04 at preflight time, so the practical risk is low — but the
magic string should be a named constant at the top of the script or at least
carry a comment explaining why `noble` is the pin.

**Fix:** Extract to a named constant:

```bash
readonly FALLBACK_CODENAME="noble"  # Ubuntu 24.04 LTS — matches preflight_check_ubuntu_24_04
CODENAME="$(. /etc/os-release 2>/dev/null && echo "${UBUNTU_CODENAME:-${VERSION_CODENAME:-$FALLBACK_CODENAME}}")"
```

### IN-04: Inconsistent bullet glyph between two install scripts' summary blocks

**File:** `scripts/install-docker.sh:153`, `scripts/install-nvidia-container-toolkit.sh:118`, `scripts/install-tools.sh:158`

**Issue:** Two of the three scripts print `"  • %s\n"` (bullet) when listing
blockers; `install-tools.sh:158` prints `"  - %s\n"` (hyphen). Trivial, but
the user-facing output is inconsistent across scripts.

**Fix:** Pick one glyph and use it everywhere. Bullet matches `preflight.sh`.

### IN-05: `ip_in_cidr` does not validate the prefix range

**File:** `scripts/lib/preflight-lib.sh:45-57`

**Issue:** If `cidr` is malformed (e.g., `192.168.1.0/99` or `10.0.0.1`
with no `/`), the function performs arithmetic with an unchecked `prefix`
and produces a garbage mask. Callers use it only against CIDRs harvested
from `ip -4 -o addr show`, which are kernel-provided and always
well-formed, so the risk today is zero. Still, a defensive check prevents
future misuse if someone calls `ip_in_cidr` with user input.

**Fix:** Add a prefix-range guard:

```bash
[[ "$prefix" =~ ^[0-9]+$ ]] && (( prefix >= 0 && prefix <= 32 )) || {
  return 2  # invalid prefix; callers should distinguish 0/1/2
}
```

### IN-06: `test_helper.bash` test suites override `uname` / `stat` with shell functions — not all call paths are hit

**File:** `tests/bats/preflight-pre01.bats:11, 22, 31`; `tests/bats/preflight-pre13.bats:11-13, 21, 32, 45`

**Issue:** The PRE-01 and PRE-13 bats tests replace `uname` and `stat` with
bash functions. But the library code calls those tools *without* any shim
(e.g., `uname -r 2>/dev/null`, `stat -fc %T /sys/fs/cgroup 2>/dev/null`). In
the test, the shell function overrides the external command because bash
functions take precedence over executables on PATH at invocation time.

However, note that PRE-13's function override relies on `export -f stat`
(line 13, 22, 34, 46) so the function is inherited by the `bash -c ...`
subshell. PRE-01 at line 11, 22, 31 does *not* `export -f uname`, but
because the test runs the whole script via `bash -c "source ...; uname() {
...; }; preflight_check_wsl_kernel"` in a single bash invocation, the
function is defined in the same shell that calls the check — so it works.
Still, mixing the two patterns is confusing for future maintainers.

**Fix:** Standardise on one pattern across all bats suites. Either always
`export -f` and let the check run naturally, or always inline both the
function-definition and the function-call into a single `bash -c "..."`
string. Document the chosen pattern in `tests/bats/test_helper.bash`.

---

_Reviewed: 2026-04-22T18:50:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
_Note: `.env.example` was listed for review but the agent was denied read
permission on that path and could not inspect its contents. If the file
contains literal secrets rather than placeholders, this would be a blocker;
please re-scope the permission settings and re-run if that file is
review-critical._
