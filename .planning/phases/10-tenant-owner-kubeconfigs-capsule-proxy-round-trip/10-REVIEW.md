---
phase: 10-tenant-owner-kubeconfigs-capsule-proxy-round-trip
reviewed: 2026-05-05T18:44:57Z
depth: standard
files_reviewed: 9
files_reviewed_list:
  - docs/poc-capsule.md
  - scripts/poc/capsule/issue-tenant-kubeconfig.sh
  - tests/bats/proxy-01-static-script.bats
  - tests/bats/proxy-02-static-leak-defenses.bats
  - tests/bats/proxy-03-static-doc.bats
  - tests/bats/proxy-04-live-issue.bats
  - tests/bats/proxy-05-live-list-filter.bats
  - tests/bats/proxy-06-live-fixture.bats
  - tests/bats/proxy-07-live-regression.bats
findings:
  blocker: 2
  warning: 9
  info: 5
  total: 16
status: issues_found
---

# Phase 10: Code Review Report

**Reviewed:** 2026-05-05T18:44:57Z
**Depth:** standard
**Files Reviewed:** 9
**Status:** issues_found

## Summary

Phase 10 ships a 232-line bash script that mints tenant-owner kubeconfigs through capsule-proxy NodePort 30443, plus an appended doc section and 7 bats files. The implementation honors the locked CONTEXT decisions (D-10-01..10) and research-corrected pitfalls (10-P1, 10-P3, 10-P5, 10-P7) and the leak-defense regression gates pass.

Two BLOCKER findings stand out for a security-sensitive script that handles bearer tokens:

1. **BL-01** — A symlink-pre-placement attack on the `${TMPDIR:-/tmp}/karyon-tenants` root defeats the `realpath -m` prefix check. On a multi-user host an attacker with write access to `/tmp` can stage `karyon-tenants` as a symlink to any directory and the script will write the kubeconfig (containing a live bearer token) wherever the attacker chose. The check is also TOCTOU-vulnerable to a swap between `realpath -m` and the redirect.
2. **BL-02** — `emit_kubeconfig > "$RESOLVED"` writes the file using the operator's default umask (typically `0022` on Ubuntu/Debian/Alpine), producing a world-readable kubeconfig containing a bound bearer token. Any local user can `cat` the file and impersonate the tenant owner for the token's lifetime.

Quality concerns: the override mechanism advertised in the head comment block (Pitfall 10-P7) does not work as the comment claims — `command <fn>` always exits 127 because shell-function lookup is suppressed and there is no `section`/`pass`/`info`/`warn`/`fail` builtin or external binary. Every override falls through to the printf branch; the comment claim that "Every log line goes to stderr automatically" via the inherited helper is materially misleading even though the resulting stderr behavior is correct. Several warnings flag the `DURATION_HOURS` heuristic (only matches `^[0-9]+h…`, silently ignores `7d`, `120m`, `1h30m`, `5400s` — which masks the very portability concern the warn message is supposed to surface), and a TOCTOU on the temp fixture in `proxy-06` that can leak a synthetic-token-shaped artifact into the repo if a test crashes mid-run.

Bats coverage is solid for happy-path and regression gates, but the static suites lean heavily on `grep -F` literal-pinning that locks in implementation choices (e.g. `'TENANT=""'`) and leaves obvious negative cases untested (e.g. unquoted variables, missing positional args, `--duration=24h` equals form).

## Blocker Issues

### BL-01: Symlink pre-placement on `${TMPDIR:-/tmp}/karyon-tenants` defeats the realpath prefix check, redirecting the issued kubeconfig (and live bearer token) to an attacker-chosen path

**File:** `scripts/poc/capsule/issue-tenant-kubeconfig.sh:157-169`
**Issue:**
The `--write-to` validator canonicalizes both the user-supplied path and the tenant tmpdir with `realpath -m`, then performs a prefix check:

```bash
RESOLVED=$(realpath -m "$WRITE_TO")
TMPDIR_RESOLVED=$(realpath -m "${TENANT_TMPDIR}")
if [[ "$RESOLVED" != "${TMPDIR_RESOLVED}/"* ]]; then
  fail "--write-to '${WRITE_TO}' is outside ${TENANT_TMPDIR}/. ..."
  exit 1
fi
mkdir -p "$(dirname "$RESOLVED")"
```

On a multi-user host (or any host with write access to `/tmp` for non-root processes — i.e. essentially every Linux system), an attacker can pre-place `/tmp/karyon-tenants` as a symlink to any directory of their choosing **before** the operator runs the script. Reproduced locally:

```text
$ ln -sf /etc /tmp/__test-symlink
$ TENANT_TMPDIR=/tmp/__test-symlink
$ RESOLVED=$(realpath -m "$TENANT_TMPDIR/passwd")     # -> /etc/passwd
$ TMPDIR_RESOLVED=$(realpath -m "$TENANT_TMPDIR")     # -> /etc
$ [[ "$RESOLVED" == "${TMPDIR_RESOLVED}/"* ]]         # -> TRUE
PREFIX CHECK PASSES — but actual file goes to /etc/passwd!
```

Because both `realpath -m` calls follow the same symlink, the prefix relationship still holds, but the actual `> "$RESOLVED"` redirect resolves through the symlink at write-time and lands in the attacker's chosen directory. This is a confidentiality bypass for the bearer-token kubeconfig — the very threat T-10-02 is supposed to mitigate.

There is also a secondary TOCTOU: even if `${TENANT_TMPDIR}` is honest at the time of `realpath -m`, an attacker who controls the parent path can swap a real component of `RESOLVED` for a symlink between the prefix check (line 161) and the redirect (line 227), again redirecting the write.

The `mkdir -p "$(dirname "$RESOLVED")"` does not protect against this either — `mkdir -p` is happy to no-op when the path already exists (as a symlinked dir), and the redirect follows symlinks.

**Fix:**
Validate that the tmpdir root is owned by the invoking user and is not a symlink, and harden against TOCTOU. Two layered options:

```bash
# Option A (cheapest): refuse to use a tmpdir root that is a symlink, and chmod it tightly.
# Place near "Section 5" before the prefix check.
if [[ -L "${TENANT_TMPDIR}" ]]; then
  fail "${TENANT_TMPDIR} is a symlink — refusing to write tenant kubeconfig.
       Hint: rm -f ${TENANT_TMPDIR} and retry. Symlink at this path is suspicious on a shared host."
  exit 1
fi
# Create owner-private root before resolving the user path:
install -d -m 0700 -o "$(id -u)" "${TENANT_TMPDIR}"
# Now realpath -m / prefix check is meaningful.
RESOLVED=$(realpath -m "$WRITE_TO")
TMPDIR_RESOLVED=$(realpath -m "${TENANT_TMPDIR}")
[[ "$RESOLVED" == "${TMPDIR_RESOLVED}/"* ]] || { fail "--write-to outside tmpdir"; exit 1; }

# Option B (stronger): use realpath -e on the parent dir AFTER mkdir -p, then write via O_NOFOLLOW.
mkdir -p "$(dirname "$RESOLVED")"
parent_real=$(realpath -e "$(dirname "$RESOLVED")")
[[ "$parent_real" == "${TMPDIR_RESOLVED}"* ]] || { fail "parent escapes tmpdir after canonicalization"; exit 1; }
# Bash redirects do not support O_NOFOLLOW; install(1) does:
emit_kubeconfig | install -m 0600 /dev/stdin "$RESOLVED"
```

A dedicated bats case for "pre-placed symlink at ${TENANT_TMPDIR}" should accompany the fix.

---

### BL-02: Issued kubeconfig is written with default umask (typically 0644 / world-readable) — any local user can read the bearer token for its full lifetime

**File:** `scripts/poc/capsule/issue-tenant-kubeconfig.sh:227`
**Issue:**
The script never sets `umask` and emits the kubeconfig via shell redirect:

```bash
emit_kubeconfig > "$RESOLVED"
```

With the default umask of `0022` (Ubuntu, Debian, Alpine, RHEL), the resulting file is mode `0644` — readable by every user on the host. The kubeconfig embeds a live bound-SA bearer token (default `--duration=1h`, but the contract supports 24h+ on k3s). On any shared host (developer laptops with multiple human accounts, CI runners with multiple jobs sharing a workspace, or — relevant to v0.19's audit posture — a host that later runs untrusted code), an unprivileged process can `cat /tmp/karyon-tenants/alpha.kubeconfig` and impersonate the tenant owner.

The doc claims "leak defense" via gitignore + gitleaks, but those defenses prevent the token from reaching git; they do nothing about the file being world-readable on the local filesystem during the token's active lifetime. P29 invariant ("kubeconfigs MUST NEVER land in git") is satisfied, but the implicit invariant "kubeconfig credentials remain confidential to the issuing operator while live" is not.

This is also a regression vs. the contract documented in `docs/poc-capsule.md` line 167:
> "<path> MUST resolve under ${TMPDIR:-/tmp}/karyon-tenants/ (validated via `realpath -m` prefix check)"

The implication of the tmpdir restriction is privacy; the implementation does not deliver that.

**Fix:**
Set a strict umask before any file creation, or write via `install -m 0600` to set the mode atomically:

```bash
# Option A: tighten umask globally for the script (also affects mkdir -p above):
umask 0077

# Option B: write atomically with explicit mode, no race window where the file is world-readable:
emit_kubeconfig | install -m 0600 /dev/stdin "$RESOLVED"
pass "kubeconfig written to ${RESOLVED} (mode 0600)"
```

Add a static bats assertion that the script contains `umask 0077` (or equivalent), and a live bats assertion that asserts `stat -c %a "$WRITE_PATH" = "600"`.

---

## Warnings

### WR-01: `command section "$@"` always exits 127 — head-comment claim that the override "calls the inherited helper" is materially false

**File:** `scripts/poc/capsule/issue-tenant-kubeconfig.sh:13-18, 36-48`
**Issue:**
The head comment (lines 36-43) states the mechanism is "function-override at definition time" that calls `command <helper>` to "internally redirect" the original sourced helpers from `preflight-lib.sh`:

```text
# We override each helper with a local function that internally redirects to >&2.
# Every subsequent call site emits to stderr automatically; no per-call-site `>&2` annotation needed.
```

The actual definitions (line 44-48) are:

```bash
section() { command section "$@" >&2 2>/dev/null || printf '== %s ==\n' "$*" >&2; }
```

`command <name>` **suppresses shell function lookup** (`help command`: "Runs COMMAND with ARGS suppressing shell function lookup"). Since `section`, `pass`, `info`, `warn`, `fail` are only defined as shell functions (not as builtins or as external binaries on `$PATH`), `command section …` always exits 127 with `bash: section: command not found` (silenced by `2>/dev/null`). The `||` short-circuits to the `printf` fallback every time. This is verifiable empirically:

```text
$ bash -c 'section() { printf "ANSI\n"; }
section() { command section "$@" >&2 2>/dev/null || printf "== %s ==\n" "$*" >&2; }
section "TEST"'
== TEST ==
```

The original `preflight-lib`'s ANSI-colored `section`/`pass`/etc. helpers from line 21-25 of `scripts/lib/preflight-lib.sh` are **never called** from this script. Output goes to stderr (correct), but via the printf fallback only — not via the inherited helpers. The PASS/WARN/FAIL counters maintained by the original `pass()`/`warn()`/`fail()` helpers (lines 18-19 of preflight-lib.sh) are also never incremented.

Consequences:
- The "leave create-cluster.sh / fix-dns.sh untouched" reasoning at line 41-43 is fine in outcome, but the explanation of why is wrong.
- If a future maintainer relies on the comment and inherits the pattern, they may believe `command <fn>` works as a "call original" mechanism — it does not.
- If a maintainer ever adds an external binary named `section` to `$PATH` (unlikely but possible), behavior would silently change.

**Fix:**
Either:
(a) drop the dead `command section "$@" >&2 2>/dev/null ||` prefix and just keep the printf branch, with a corrected comment explaining the actual mechanism; or
(b) implement the claimed mechanism using `unset -f section pass info warn fail; section() { local m="$1"; preflight_section "$m" >&2; }` after renaming the originals or saving them to alias names; or
(c) simplest: keep printf-only overrides and update the head comment to remove the false claim:

```bash
# Pitfall 10-P7 stderr-redirect: per-call-site `>&2` would require ~50 redirects throughout the
# script. Instead we shadow each preflight-lib helper with a printf-to-stderr equivalent. The
# original ANSI-colored helpers from preflight-lib are unused here (this script does not emit
# stdout summary lines; stdout is reserved for the kubeconfig YAML payload).
section() { printf '== %s ==\n' "$*" >&2; }
pass()    { printf '  ok  %s\n'  "$*" >&2; }
info()    { printf '  --  %s\n'  "$*" >&2; }
warn()    { printf '  !!  %s\n'  "$*" >&2; }
fail()    { printf '  xx  %s\n'  "$*" >&2; }
```

---

### WR-02: `DURATION_HOURS` parser silently ignores `7d`, `2h30m`, `120m`, `5400s` — defeats the >24h portability warn it is supposed to gate

**File:** `scripts/poc/capsule/issue-tenant-kubeconfig.sh:172-175`
**Issue:**
The duration-portability info-warn extracts the leading number-of-hours via:

```bash
DURATION_HOURS=$(echo "$DURATION" | sed -E 's/^([0-9]+)h.*$/\1/' | grep -E '^[0-9]+$' || echo "0")
if [[ "$DURATION_HOURS" -gt 24 ]]; then
  info "duration ${DURATION} is honored exactly on this k3s pin..."
fi
```

This regex matches only `<digits>h…` and falls back to `0` for anything else. Reproduced:

| `--duration` | parsed `DURATION_HOURS` | actual hours | warn fires? |
|---|---|---|---|
| `1h` | `1` | 1 | no (correct) |
| `48h` | `48` | 48 | yes (correct) |
| `2h30m` | `2` | ~2.5 | no (acceptable — under threshold anyway) |
| `120m` | `0` | 2 | no (acceptable for this case) |
| `7d` | `0` | **168** | **no — BUG** (should warn at >24h) |
| `48h30m` | `48` | 48.5 | yes |
| `5400s` | `0` | 1.5 | no (acceptable) |
| `1d` | `0` | 24 | no (boundary; misses portability concern for distros with strict <24h clamp) |

Operators using `--duration 7d` (a perfectly valid Go `time.Duration`) get NO portability warning, even though that is precisely the case the warn message is intended to flag. The bats coverage (live test `proxy-04` line 43-66) only exercises the default `1h` path, so this regression is uncaught.

The script's usage example at line 69 explicitly mentions `7d` as a valid value, which makes the silent miss worse.

**Fix:**
Either parse all reasonable suffix forms, or simplify by deferring to a real parser. Cheapest fix:

```bash
# Convert duration to seconds via Python/Perl/Go, OR fall back to a simple multi-suffix parser.
# Pure-bash version that handles d/h/m/s with no compound forms:
duration_to_hours() {
  local d="$1"
  local n="${d%[smhd]}"
  local s="${d: -1}"
  [[ "$n" =~ ^[0-9]+$ ]] || { echo "0"; return; }
  case "$s" in
    s) echo $(( n / 3600 )) ;;
    m) echo $(( n / 60 ))   ;;
    h) echo "$n"             ;;
    d) echo $(( n * 24 ))   ;;
    *) echo "0"               ;;
  esac
}
DURATION_HOURS=$(duration_to_hours "$DURATION")
```

Add bats cases that pass `7d` and assert the info-warn fires (or, more realistically, that the script doesn't silently swallow the >24h portability concern).

---

### WR-03: `proxy-06-live-fixture.bats` — temp fixture cleanup is not in `teardown()`; a crash leaves a token-shaped file inside the repo

**File:** `tests/bats/proxy-06-live-fixture.bats:34-58`
**Issue:**
The "gitleaks fires on tenant-shaped fixture NOT in allowlist" test creates a temp file inside the repo:

```bash
TEMP_FIXTURE=$(mktemp -p "${REPO_ROOT}/tests/fixtures/gitleaks" temp-tenant-fixture-XXXX.yaml)
cat > "$TEMP_FIXTURE" <<EOF
apiVersion: v1
kind: Config
...
      token: ZXhhbXBsZS1pbmVydC10b2tlbi12MC4xOS1zeW50aGV0aWMtZml4dHVyZS1mb3ItcHJveHktMDYtbGl2ZQ
...
EOF
run gitleaks detect --no-banner --no-git --source "$TEMP_FIXTURE" --config "$GITLEAKS_TOML" --redact --verbose
rm -f "$TEMP_FIXTURE"      # <— ONLY runs if test reaches here
[ "$status" -ne 0 ]
```

The `rm -f` at line 56 runs inline; the `teardown()` block at line 60-62 only cleans `${REPO_ROOT}/karyon-tenants` (from the first test). If `gitleaks` segfaults, the runner is killed mid-test, the user hits Ctrl-C, or the test asserts before `rm`, the temp fixture stays in `tests/fixtures/gitleaks/`. Because the file matches `kind: Config` + `token:` and the path `temp-tenant-fixture-*.yaml` is **not** in the gitleaks allowlist (the rule fires on it — that is the whole point of the test), a subsequent commit attempt that includes this orphan file will be blocked by the pre-commit gitleaks hook (Phase 11 VAL-05). Worse: an orphan inside the repo is a load-bearing P29 violation if the developer pushes before noticing.

The first test (`karyon-tenants/` ignore) handles this correctly: `teardown()` does `rm -rf "${REPO_ROOT}/karyon-tenants"`. The temp-fixture test should do the same.

**Fix:**
Move cleanup into `teardown()` and use a fixed filename so cleanup is deterministic:

```bash
@test "PROXY-03 leak defense: gitleaks fires on tenant-shaped fixture NOT in allowlist" {
  TEMP_FIXTURE="${REPO_ROOT}/tests/fixtures/gitleaks/temp-tenant-fixture.yaml"
  cat > "$TEMP_FIXTURE" <<EOF
...
EOF
  run gitleaks detect --no-banner --no-git --source "$TEMP_FIXTURE" --config "$GITLEAKS_TOML" --redact --verbose
  [ "$status" -ne 0 ]
}

teardown() {
  rm -rf "${REPO_ROOT}/karyon-tenants" 2>/dev/null || true
  rm -f "${REPO_ROOT}/tests/fixtures/gitleaks/temp-tenant-fixture.yaml" 2>/dev/null || true
  # Defensive: clean up any mktemp-style leftovers from older test runs:
  rm -f "${REPO_ROOT}/tests/fixtures/gitleaks/"temp-tenant-fixture-*.yaml 2>/dev/null || true
}
```

Or, cleaner: write the fixture to `${BATS_TEST_TMPDIR}` (a per-test bats-managed dir, auto-cleaned) and pass the file path to `gitleaks detect --source` from there — gitleaks does not need the fixture to be in-repo.

---

### WR-04: Empty/whitespace TENANT or OWNER passes positional-arg validation, then leaks into kubectl/heredoc

**File:** `scripts/poc/capsule/issue-tenant-kubeconfig.sh:101-109`
**Issue:**
Positional-arg parsing accepts the first non-flag token regardless of content:

```bash
*) if [[ -z "$TENANT" ]]; then TENANT="$1"; shift
   elif [[ -z "$OWNER" ]]; then OWNER="$1"; shift
   ...
```

Empty-string assignment is filtered by the closing `[[ -z "$TENANT" ]] && { fail …; usage 1; }` at lines 108-109. But:
- `TENANT=" "` (whitespace) passes `[[ -z " " ]]` is false → script proceeds with TENANT=" ".
- `kubectl get tenant " "` returns NotFound; fail-fast at line 135 catches it. OK.
- Tab characters and shell-special characters (`$`, `\`, backticks) inside TENANT or OWNER are passed verbatim into the heredoc on lines 213, 217, 221, 222. The heredoc is unquoted (`<<KUBECONFIG_EOF`, not `<<'KUBECONFIG_EOF'`), which means `${OWNER}` and `${TENANT}` interpolate normally — but if `OWNER='foo$(rm -rf /)'`, the resulting kubeconfig YAML embeds the literal string into a YAML field. No code execution, but YAML-injection: a malicious tenant name like `alpha\nusers:\n  - name: evil\n    user:\n      token: ATTACKER` could mutate the output.

In the current threat model — operator runs the script with arguments they choose — this is low-risk. But: if any future automation (a `task issue-tenant-kubeconfig` wrapper, a webhook, a UI) takes user-supplied input into TENANT/OWNER, this becomes a vehicle to forge kubeconfig contents.

**Fix:**
Add a strict-format validator:

```bash
# K8s object names: lowercase alphanumeric + dashes, max 63 chars (RFC 1123 label).
# This matches Tenant / SA / Namespace name validity in apiserver.
K8S_NAME_RE='^[a-z0-9][a-z0-9-]{0,61}[a-z0-9]$'
[[ "$TENANT" =~ $K8S_NAME_RE ]] || { fail "<tenant> must be a valid RFC 1123 label (lowercase a-z, 0-9, -)"; exit 1; }
[[ "$OWNER"  =~ $K8S_NAME_RE ]] || { fail "<owner> must be a valid RFC 1123 label"; exit 1; }
```

Add a static bats assertion that `K8S_NAME_RE` (or equivalent) is present, plus negative live cases for `--tenant 'bad name'` and the YAML-injection vector.

---

### WR-05: `--write-to=path` (equals form) silently rejected as "unknown flag"; usage examples imply both forms work

**File:** `scripts/poc/capsule/issue-tenant-kubeconfig.sh:96-105`
**Issue:**
The argument parser only handles space-separated form:

```bash
case "$1" in
  --duration) DURATION="${2:?--duration requires a value}"; shift 2 ;;
  --write-to) WRITE_TO="${2:?--write-to requires a value}"; shift 2 ;;
  ...
  --*)        fail "unknown flag: $1"; usage 1 ;;
```

A user who runs `--duration=24h` or `--write-to=/tmp/karyon-tenants/foo.kubeconfig` (the GNU `getopt` long-form) hits the `--*` arm and exits with "unknown flag: --duration=24h". The script's own usage block at line 60 uses space form, so this is technically self-consistent — but `kubectl create token` itself uses `--duration=` form (line 179), and the doc Quickstart at line 156 of `docs/poc-capsule.md` shows neither form, which leaves operators unsure.

For a POC operator script the rejection is loud and easy to recover from, so this is a Warning rather than a Blocker. But the inconsistency between `kubectl --duration=…` (equals form) inside the script and `--duration <d>` (space form) on the script surface is exactly the kind of papercut that costs an operator 10 minutes of debugging on a Friday afternoon.

**Fix:**
Either explicitly reject the equals form with a clearer message, or accept both:

```bash
case "$1" in
  --duration=*) DURATION="${1#--duration=}"; shift ;;
  --duration)   DURATION="${2:?--duration requires a value}"; shift 2 ;;
  --write-to=*) WRITE_TO="${1#--write-to=}"; shift ;;
  --write-to)   WRITE_TO="${2:?--write-to requires a value}"; shift 2 ;;
  --help|-h)    usage 0 ;;
  --*)          fail "unknown flag: $1"; usage 1 ;;
  ...
esac
```

---

### WR-06: `proxy-04-live-issue.bats` JWT-decode test crashes on bad payload — `set -euo pipefail` not enabled in bats cases; mismatched bytes silently truncate

**File:** `tests/bats/proxy-04-live-issue.bats:43-66`
**Issue:**
The JWT-decode case extracts `.users[0].user.token`, splits the payload, base64-decodes, and asserts `exp - iat ≈ 3600`:

```bash
TOKEN=$(yq eval '.users[0].user.token' "$ISSUED_KC")
PAYLOAD=$(echo "$TOKEN" | cut -d. -f2)
case $((${#PAYLOAD} % 4)) in
  2) PAYLOAD="${PAYLOAD}==" ;;
  3) PAYLOAD="${PAYLOAD}=" ;;
esac
DECODED=$(echo "$PAYLOAD" | tr '_-' '/+' | base64 -d 2>/dev/null)
EXP=$(echo "$DECODED" | jq -r '.exp')
IAT=$(echo "$DECODED" | jq -r '.iat')

[ "$((EXP - IAT))" -ge 3540 ]
[ "$((EXP - IAT))" -le 3660 ]
```

Issues:
1. `base64 -d 2>/dev/null` discards stderr. If decode fails (corrupted/truncated payload), `$DECODED` is empty; `jq -r '.exp'` returns `null`; arithmetic `$((null - null))` evaluates as `$((0 - 0))` = `0` (because bash `$((` treats unbound names as 0 under `set +u`). Then `[ 0 -ge 3540 ]` fails — the test "correctly" red-fails, but the diagnostic is opaque ("expected 0 ≥ 3540" is much less useful than "JWT decode failed").
2. The `case` only handles padding for `% 4 == 2` or `==3`. A payload whose length is `% 4 == 1` (which is invalid base64 — should never happen for a real JWT but does happen if `cut -d. -f2` returns garbage, e.g., a bearer token that is NOT a JWT) silently slides through with no padding, base64 fails, decode is empty, and the test falsely-reds.
3. Subject assertion (`SUB=$(echo "$DECODED" | jq -r '.sub')`) — same issue: empty decode → null → string mismatch.

This is technically a correctness bug in the test (false-red on JWT-shape mismatch instead of a clear "this is not a JWT" failure). For the happy-path it works correctly.

**Fix:**
Validate JWT shape before arithmetic:

```bash
TOKEN=$(yq eval '.users[0].user.token' "$ISSUED_KC")
[ -n "$TOKEN" ] && [ "$TOKEN" != "null" ] || { echo "no token in kubeconfig"; return 1; }
# Real JWT has exactly 3 dot-separated segments
[ "$(echo "$TOKEN" | tr -cd '.' | wc -c)" = "2" ] || { echo "token is not a JWT (got $(echo "$TOKEN" | tr -cd '.' | wc -c) dots)"; return 1; }
PAYLOAD=$(echo "$TOKEN" | cut -d. -f2)
# All three padding cases:
case $((${#PAYLOAD} % 4)) in
  0) ;;
  2) PAYLOAD="${PAYLOAD}==" ;;
  3) PAYLOAD="${PAYLOAD}=" ;;
  *) echo "invalid base64 payload length"; return 1 ;;
esac
DECODED=$(printf '%s' "$PAYLOAD" | tr '_-' '/+' | base64 -d) || { echo "base64 decode failed"; return 1; }
echo "$DECODED" | jq empty || { echo "decoded payload is not JSON"; return 1; }
```

---

### WR-07: `proxy-04-live-issue.bats` `--write-to` test does not assert file is owner-private (mode), so BL-02's confidentiality regression would slip through

**File:** `tests/bats/proxy-04-live-issue.bats:83-91`
**Issue:**
The `--write-to inside ${TMPDIR:-/tmp}/karyon-tenants/ writes file` test only asserts `[ -f "$WRITE_PATH" ]` and that the YAML is parseable. It does not check the file mode. Because BL-02 leaves the file world-readable, this test happily passes on a system where any user can read the bearer token.

**Fix:**
Add a mode assertion alongside the existence check:

```bash
@test "PROXY-01 live (D-10-09): --write-to inside ... writes owner-private (mode 0600) file" {
  WRITE_PATH="${TMPDIR:-/tmp}/karyon-tenants/proxy-04-test.kubeconfig"
  bash "${REPO_ROOT}/scripts/poc/capsule/issue-tenant-kubeconfig.sh" alpha gitops-reconciler --write-to "$WRITE_PATH" >/dev/null 2>&1
  [ -f "$WRITE_PATH" ]
  mode=$(stat -c '%a' "$WRITE_PATH")
  [ "$mode" = "600" ]    # NOT 0644, NOT 0640
  rm -f "$WRITE_PATH"
}
```

This pairs naturally with the BL-02 fix.

---

### WR-08: `proxy-05-live-list-filter.bats` constructs the falsifier kubeconfig with `insecure-skip-tls-verify: true` — Phase 8 WR-01..04 hardening forbids that anti-pattern in repo bats

**File:** `tests/bats/proxy-05-live-list-filter.bats:27-45`
**Issue:**
The bats-constructed direct-apiserver kubeconfig embeds `insecure-skip-tls-verify: true` (line 34). Phase 8 closed out with WR-01..04 hardening that explicitly forbids this anti-pattern in repo artifacts (the `proxy-01-static-script.bats` test at line 100-106 lints for it in the script, and the `docs/poc-capsule.md` contract section at line 169 reinforces "NOT `insecure-skip-tls-verify`"). The bats-constructed kubeconfig is technically:
- ephemeral (in `mktemp -p` tmpfile),
- removed in the test,
- only used to demonstrate the falsifier path,

so this is not a P29 violation per se. But it violates the spirit of the Phase 8 anti-pattern lint and provides a copy-paste reference for any future contributor who searches the repo for "kubeconfig template" examples.

The CONTEXT D-10-08 explicitly endorses constructing the falsifier this way, so this is project-design, not a bug. **However:** the construction is bats-internal; nothing prevents using `certificate-authority-data` from the spoke-capsule kubeconfig context instead. The chosen anti-pattern is a future-proofing concern, not a security bug today.

**Fix (optional):**
Replace `insecure-skip-tls-verify: true` with the actual spoke-capsule CA cert read from the existing kubeconfig context:

```bash
SPOKE_CA=$(kubectl --context=k3d-spoke-capsule config view --raw -o json \
  | jq -r '.clusters[] | select(.name=="k3d-spoke-capsule") | .cluster["certificate-authority-data"]')
cat > "$DIRECT_KC" <<EOF
apiVersion: v1
kind: Config
clusters:
- name: direct
  cluster:
    server: https://127.0.0.1:6446
    certificate-authority-data: $SPOKE_CA
...
EOF
```

This keeps the falsifier real (it actually verifies the apiserver cert) and removes the antipattern reference from the repo. Alternatively, add a `nolint` marker comment so future grep audits can exclude this one occurrence.

---

### WR-09: `set -euo pipefail` + `kubectl … 2>/dev/null || true` pattern bypasses pipefail, masking transient kubectl failures

**File:** `scripts/poc/capsule/issue-tenant-kubeconfig.sh:184-190`
**Issue:**
The CA-cert read uses `|| true` to swallow the kubectl exit status:

```bash
CA_B64=$(kubectl --context=k3d-spoke-capsule -n capsule-system \
    get secret capsule-proxy -o jsonpath='{.data.tls\.crt}' 2>/dev/null || true)
```

This is a deliberate choice (the line 186 check `[[ -z "$CA_B64" ]]` is the actual error gate), but it masks the difference between three failure modes:
1. Secret exists but jsonpath returns empty (CA_B64="").
2. Secret does not exist (kubectl exits non-zero, "NotFound").
3. Apiserver unreachable (kubectl exits non-zero, transient network error).

All three present identically as `CA_B64=""`. The retry-once branch (line 187-191) handles case 3 OK by waiting 5s. But the `fail` message at line 193-196 hints "capsule-proxy may not yet be installed on spoke-capsule" — wrong message for case 3.

Smaller concern: 2>/dev/null hides genuinely useful error diagnostics from kubectl (e.g., "the connection to the server localhost:8080 was refused" — a tell-tale missing-context error).

**Fix:**
Capture stderr into a variable; differentiate on exit code:

```bash
CA_OUT=$(kubectl --context="${POC_CTX}" -n capsule-system \
    get secret capsule-proxy -o jsonpath='{.data.tls\.crt}' 2>&1) || CA_RC=$?
CA_RC="${CA_RC:-0}"
CA_B64="$CA_OUT"
if [[ "$CA_RC" -ne 0 ]]; then
  if echo "$CA_OUT" | grep -qF NotFound; then
    fail "capsule-proxy Secret not found in namespace capsule-system. Phase 8 capsule-proxy not installed?
       Inspect: kubectl --context=${POC_CTX} -n capsule-system get secret"
  else
    fail "kubectl call failed (RC=${CA_RC}): ${CA_OUT}"
  fi
  exit 1
fi
[[ -n "$CA_B64" ]] || { fail "tls.crt key is empty in capsule-proxy Secret. Cert rotation in flight? Inspect ..."; exit 1; }
```

---

## Info

### IN-01: `command -v "$1"` would be more idiomatic than `have "$cmd"` — but `have` is the project convention; no action needed

**File:** `scripts/poc/capsule/issue-tenant-kubeconfig.sh:113-120`
**Issue:** `have` is defined in `preflight-lib.sh` (line 27: `have() { command -v "$1" >/dev/null 2>&1; }`) and is the project's tool-gate idiom. Using it is correct. Pure style note.
**Fix:** No action — flagging for completeness.

---

### IN-02: `usage()` writes to stderr but `exit "${1:-0}"` shadows the caller's intended exit — minor

**File:** `scripts/poc/capsule/issue-tenant-kubeconfig.sh:58-87`
**Issue:** `usage 1` is called from arg-parse error sites (e.g. line 100) AFTER a `fail` line. The pattern `fail "x"; usage 1;` works (fail prints to stderr, usage prints help to stderr, then exits 1). Minor concern: if a future maintainer changes `usage` to take a flag like `--no-exit`, the implicit "always exit" is non-obvious.
**Fix:** No action — current behavior matches v0.18 / Phase 7 convention.

---

### IN-03: Bats static-suite `grep -F` literal-pinning makes refactors brittle (e.g., `'TENANT=""'` literal)

**File:** `tests/bats/proxy-01-static-script.bats:62-75`
**Issue:** The argparse static contract pins literal strings like `'TENANT=""'` and `'WRITE_TO=""'`. A future refactor that changes initial assignment to `TENANT=` (without quotes) or `local TENANT` (in a function-scoped reorg) would red-fail the test even though semantics are preserved. This is a known tradeoff of grep-asserted static suites.
**Fix:** Acceptable for D-10-09's "Wave 0 RED scaffold" pattern. Future improvement: assert via `bash -n` (syntax check) plus a sample invocation matrix instead of literal-pinning.

---

### IN-04: Doc Quickstart redirects to `/tmp/alpha.kubeconfig` (not the tmpdir-rooted path); subtly inconsistent with the contract's "MUST resolve under ${TMPDIR:-/tmp}/karyon-tenants/"

**File:** `docs/poc-capsule.md:156`
**Issue:** The Quickstart example shows:

```bash
bash scripts/poc/capsule/issue-tenant-kubeconfig.sh alpha gitops-reconciler 2>/dev/null > /tmp/alpha.kubeconfig
```

This is a stdout redirect (no `--write-to`), so the script's tmpdir validation does not run. The redirect is performed by the operator's shell directly, which means the kubeconfig lands at `/tmp/alpha.kubeconfig` — outside `${TMPDIR:-/tmp}/karyon-tenants/`. The `.gitignore` glob `*.kubeconfig` (line 15 in `.gitignore`) does cover this filename, so P29 isn't violated, but it's inconsistent with the doc's own contract paragraph at line 167 ("MUST resolve under ${TMPDIR:-/tmp}/karyon-tenants/"). New operators will reasonably copy the Quickstart and end up with a kubeconfig outside the audited path.
**Fix:** Update the example to use `${TMPDIR:-/tmp}/karyon-tenants/alpha.kubeconfig` (consistent with line 79 of the script's own usage block):

```bash
mkdir -p "${TMPDIR:-/tmp}/karyon-tenants"
bash scripts/poc/capsule/issue-tenant-kubeconfig.sh alpha gitops-reconciler 2>/dev/null > "${TMPDIR:-/tmp}/karyon-tenants/alpha.kubeconfig"
```

---

### IN-05: Script-line `kubectl --context=k3d-spoke-capsule create token …` hardcodes context name twice (line 179, 184, 189) instead of `${POC_CTX}` constant

**File:** `scripts/poc/capsule/issue-tenant-kubeconfig.sh:179, 184, 189`
**Issue:** Lines 124, 135, 145 use `"${POC_CTX}"` (the readonly constant from line 51). Lines 179, 184, 189 hardcode the literal string `k3d-spoke-capsule`. The bats test at `proxy-01-static-script.bats:41` actually pins this hardcoded literal (`'kubectl --context=k3d-spoke-capsule'`), so the inconsistency is intentional for grep-asserted contract enforcement. Still, mixing the two forms inside the same script is a maintenance smell — a future change to the cluster name would need three sites updated, plus the bats literal updated, instead of one constant.
**Fix:** Either unify on the constant (and change the bats literal to `'kubectl --context="${POC_CTX}"'`) or document the intentional split:

```bash
# ---------- Section 7: Mint TokenRequest token (D-10-01) ----------
# NOTE: bats proxy-01-static-script.bats line 41 pins literal 'kubectl --context=k3d-spoke-capsule';
# keep this string verbatim. ${POC_CTX} elsewhere in this file is for runtime parameterization.
section "Mint TokenRequest token (D-10-01)"
TOKEN=$(kubectl --context=k3d-spoke-capsule create token "${OWNER}" -n "tenant-${TENANT}" --duration="${DURATION}")
```

---

---

_Reviewed: 2026-05-05T18:44:57Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
