---
phase: 10-tenant-owner-kubeconfigs-capsule-proxy-round-trip
fixed_at: 2026-05-05T19:07:22Z
review_path: .planning/phases/10-tenant-owner-kubeconfigs-capsule-proxy-round-trip/10-REVIEW.md
iteration: 1
findings_in_scope: 11
fixed: 11
skipped: 0
status: all_fixed
---

# Phase 10: Code Review Fix Report

**Fixed at:** 2026-05-05T19:07:22Z
**Source review:** `.planning/phases/10-tenant-owner-kubeconfigs-capsule-proxy-round-trip/10-REVIEW.md`
**Iteration:** 1

**Summary:**
- Findings in scope (BLOCKER + WARNING): 11
- Fixed: 11
- Skipped: 0
- Status: all_fixed

INFO findings (IN-01..05) are out of scope per the configured `fix_scope: critical_warning` policy. They are documented in REVIEW.md and may be addressed in a follow-up pass at the operator's discretion.

## Fixed Issues

### BL-01: Symlink pre-placement on `${TMPDIR:-/tmp}/karyon-tenants` defeats the realpath prefix check

**Files modified:** `scripts/poc/capsule/issue-tenant-kubeconfig.sh`
**Commit:** `a6c93d7`
**Approach chosen:** REVIEW Option A (cheapest) -- refuse to write when `${TENANT_TMPDIR}` is a symlink, plus owner-private (mode 0700) tmpdir creation, plus a defense-in-depth `realpath -e` parent check after `mkdir -p`. Rationale: minimal complexity, preserves D-10-07 contract and the bats grep-pinned `realpath -m` literal, and closes both the symlink pre-placement attack and the secondary TOCTOU.

**Applied fix:**
1. Pre-flight `[[ -L "${TENANT_TMPDIR}" ]]` check rejects a pre-placed symlink with a hint that includes `rm -f` recovery.
2. `install -d -m 0700 "${TENANT_TMPDIR}"` creates the tmpdir owner-private if absent.
3. After `mkdir -p` of the resolved parent, `realpath -e` verifies the parent's canonical path is still inside `${TMPDIR_RESOLVED}` -- catches a TOCTOU symlink swap between the prefix check and the end-of-script redirect.

**Verification:**
- `bash -n` syntax check: PASS
- `bats tests/bats/proxy-01-static-script.bats`: 12/12 GREEN (preserves `realpath -m` + `TENANT_TMPDIR=` + `karyon-tenants` literals)
- `bats tests/bats/proxy-04-live-issue.bats`: 7/7 GREEN (`--write-to /etc/passwd` rejected exit non-zero; `--write-to ../../etc/passwd` rejected via realpath -m)

---

### BL-02: World-readable bearer tokens (default umask 0022 -> mode 0644)

**Files modified:** `scripts/poc/capsule/issue-tenant-kubeconfig.sh`, `tests/bats/proxy-04-live-issue.bats`
**Commit:** `4c205c0`
**Approach chosen:** REVIEW Option A (`umask 0077`) at the top of the `--write-to` block, plus belt-and-braces `chmod 0600 "$RESOLVED"` post-write. This applies to both `mkdir -p` parents (the `karyon-tenants/` directory becomes 0700) and the `> "$RESOLVED"` redirect (file becomes 0600). The belt-and-braces `chmod` defends against a future maintainer accidentally overriding `umask` before the write block.

**Applied fix:**
1. `umask 0077` set at top of Section 5 (only when `$WRITE_TO` is non-empty -- stdout-only path is unaffected).
2. `chmod 0600 "$RESOLVED"` after the `emit_kubeconfig > "$RESOLVED"` redirect.
3. Updated the `pass` message to document mode 0600.
4. Added a bats assertion in `proxy-04-live-issue.bats` (also addresses WR-07): `mode=$(stat -c '%a' "$WRITE_PATH"); [ "$mode" = "600" ]`.

**Verification:**
- `bats tests/bats/proxy-04-live-issue.bats` test 4 (`--write-to ... writes owner-private (mode 0600) file`): GREEN
- All 7 proxy-04 live tests: GREEN

---

### WR-01: `command section "$@"` always exits 127 -- misleading head-comment claim

**Files modified:** `scripts/poc/capsule/issue-tenant-kubeconfig.sh`
**Commit:** `c176594`
**Approach chosen:** Prompt option (a) -- drop the dead `command <fn> >&2 2>/dev/null ||` prefix and go printf-direct. Update the head comment + Pitfall 10-P7 narrative to honestly describe the mechanism (shadow preflight-lib helpers with printf-to-stderr equivalents; the originals' ANSI helpers + counters are intentionally unused).

**Applied fix:**
1. Replaced 5 override functions with single-branch printf forms:
   - `section() { printf '== %s ==\n' "$*" >&2; }` (and similar for pass/info/warn/fail)
2. Rewrote head comment lines 13-19 + Pitfall 10-P7 block lines 36-46 to remove the false "calls the inherited helper" claim and explain that the originals are intentionally unused (this script does not emit stdout summary lines or rely on PASS/WARN/FAIL counters; it fail-fasts via `exit 1` after each `fail`).

**Verification:**
- `bash -n` syntax check: PASS
- `bats proxy-01-static-script.bats`: 12/12 GREEN (no `wc -l == 5` assertion exists; the script still defines exactly 5 `^(section|pass|info|warn|fail)\(\) \{` lines, just without the dead prefix)
- `bats proxy-04-live-issue.bats`: 7/7 GREEN (stderr behavior unchanged -- still goes to stderr)

---

### WR-02: `DURATION_HOURS` regex too narrow -- silently ignores `7d`, `120m`, `5400s`

**Files modified:** `scripts/poc/capsule/issue-tenant-kubeconfig.sh`
**Commit:** `3e90993`
**Approach chosen:** Prompt option 1 -- pure-bash multi-suffix parser. Avoids adding a new dependency on Python/Perl.

**Applied fix:**
Added a `duration_to_hours` function using `BASH_REMATCH` to match `^([0-9]+)([smhd])` and convert the leading numeric+unit segment to hours. Compound forms (`1h30m`) collapse to the leading segment, which is acceptable for the >24h heuristic (the leading segment dominates for the values operators actually pass).

**Verification (table from REVIEW, against the new helper):**
| Input | Old result | New result | Threshold (>24h) fires? |
|---|---|---|---|
| `1h` | `1` | `1` | no (correct) |
| `24h` | `24` | `24` | no (boundary) |
| `48h` | `48` | `48` | yes |
| `7d` | `0` BUG | `168` FIXED | yes |
| `1d` | `0` MISS | `24` FIXED | no (boundary, correct) |
| `2h30m` | `2` | `2` | no |
| `120m` | `0` MISS | `2` FIXED | no |
| `5400s` | `0` MISS | `1` FIXED | no |
| `notvalid` | `0` | `0` | no |

- `bash -n` syntax check: PASS
- `bats proxy-01-static-script.bats` + `proxy-04-live-issue.bats`: 19/19 GREEN

---

### WR-03: Bats fixture cleanup leaks on crash

**Files modified:** `tests/bats/proxy-06-live-fixture.bats`
**Commit:** `1db3696`
**Approach chosen:** REVIEW preferred option -- `BATS_TEST_TMPDIR` (auto-cleaned by bats on every test exit, including crashes). gitleaks `--no-git --source` accepts any path; the fixture does not need to be in-repo.

**Applied fix:**
1. Replaced `mktemp -p "${REPO_ROOT}/tests/fixtures/gitleaks" temp-tenant-fixture-XXXX.yaml` with `${BATS_TEST_TMPDIR}/temp-tenant-fixture.yaml`.
2. Removed the inline `rm -f` after the gitleaks call (no longer needed since BATS_TEST_TMPDIR is auto-cleaned).
3. Added defensive cleanup in `teardown()` for orphan fixtures left by older test runs that crashed before this fix.

**Verification:**
- `bats proxy-06-live-fixture.bats`: 3/3 GREEN
- Post-run filesystem check: `tests/fixtures/gitleaks/` contains only `synthetic-kubeconfig.yaml` and `benign-configmap.yaml` -- no `temp-tenant-fixture-*.yaml` orphans.

---

### WR-04: Empty/whitespace TENANT or OWNER passes positional-arg validation

**Files modified:** `scripts/poc/capsule/issue-tenant-kubeconfig.sh`
**Commit:** `3bcbf06`
**Approach chosen:** REVIEW recommended -- strict RFC 1123 label regex (`^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$`). Matches apiserver Tenant CR / SA / Namespace name validity. Closes the YAML-injection vector (whitespace, tabs, backticks, `$()` were previously interpolated verbatim into the unquoted KUBECONFIG_EOF heredoc).

**Applied fix:**
Added a `K8S_NAME_RE` validator after the existing `[[ -z "$TENANT" ]]` / `[[ -z "$OWNER" ]]` empty checks. Both TENANT and OWNER must match the regex or the script fail-fasts with a clear "not a valid RFC 1123 label" message.

**Verification (regex behavior):**
- PASS: `alpha`, `bravo`, `gitops-reconciler` (all real values still work)
- PASS: `a`, `ab`, `a-b` (single-char + minimal cases)
- REJECT: `""`, `" "` (whitespace), `BAD` (uppercase), `alpha bravo` (space), `foo$bar` (shell-special), `-leading`, `trailing-`, 67-char string

- `bash -n` syntax check: PASS
- `bats proxy-01-static-script.bats` + `proxy-04-live-issue.bats`: 19/19 GREEN

---

### WR-05: `--write-to=path` (equals form) silently rejected

**Files modified:** `scripts/poc/capsule/issue-tenant-kubeconfig.sh`
**Commit:** `c82e02b`
**Approach chosen:** REVIEW recommended -- accept both space and equals forms. Mirrors the GNU getopt + `kubectl create token --duration=...` style operators are familiar with.

**Applied fix:**
Added `--duration=*` and `--write-to=*` arms BEFORE the existing space-form arms. The space-form `--duration)` and `--write-to)` literals are preserved (the bats grep-pinned them at `proxy-01-static-script.bats:65-66`).

**Verification:**
- `bash -n` syntax check: PASS
- `bats proxy-01-static-script.bats` (literals still pinned): 12/12 GREEN
- Manual smoke: `bash issue-tenant-kubeconfig.sh alpha gitops-reconciler --duration=2h` -> emits valid Config kubeconfig

---

### WR-06: JWT decode test crashes opaquely on malformed token

**Files modified:** `tests/bats/proxy-04-live-issue.bats`
**Commit:** `23ba983`
**Approach chosen:** REVIEW recommended -- validate JWT shape before arithmetic with explicit diagnostics.

**Applied fix:**
1. Token non-empty + non-`null` guard.
2. Exactly-2-dots (3 segments) guard with explicit `got N dots` diagnostic.
3. All four base64-padding cases handled (0/2/3 + explicit `*` -> diagnostic).
4. `base64 -d` failure caught with explicit message.
5. `jq empty` validates the decoded payload is JSON before downstream `.exp` / `.iat` extraction.
6. Cleanup of the kubeconfig on every error path so we don't leak into `/tmp` on red-fail.

**Verification:**
- `bats proxy-04-live-issue.bats` test 2 (JWT decode): GREEN. The test now red-fails with a clear diagnostic message instead of opaque arithmetic mismatch on shape errors. Happy-path behavior unchanged.

---

### WR-07: `--write-to` test does not assert mode 0600 (BL-02 confidentiality regression slip-through)

**Files modified:** `tests/bats/proxy-04-live-issue.bats`
**Commit:** `4c205c0` (committed alongside BL-02 -- they share the same fix surface)
**Approach chosen:** REVIEW recommended -- add a `stat -c '%a'` mode assertion to the existing `--write-to` happy-path test.

**Applied fix:**
Added `mode=$(stat -c '%a' "$WRITE_PATH"); [ "$mode" = "600" ]` to the `--write-to inside ${TMPDIR:-/tmp}/karyon-tenants/ writes file` test, plus updated the test name to advertise "writes owner-private (mode 0600) file". This pairs naturally with BL-02 -- both fixes shipped in the same commit because the assertion would have been a permanent red-fail without the BL-02 umask + chmod fix.

**Verification:**
- `bats proxy-04-live-issue.bats` test 4: GREEN (mode 600 confirmed on a live `--write-to` invocation)

---

### WR-08: `proxy-05` falsifier uses `insecure-skip-tls-verify: true` antipattern

**Files modified:** `tests/bats/proxy-05-live-list-filter.bats`
**Commit:** `74d09e4`
**Approach chosen:** REVIEW alternative -- add a `nolint` marker comment. Rationale: CONTEXT D-10-08 explicitly endorses this shape (the spoke-capsule apiserver cert does not have 127.0.0.1:6446 in its SAN list, and the apiserver returns 403 BEFORE TLS state matters). The Phase 8 anti-pattern lint at `proxy-01-static-script.bats:100` only scans the script, not bats. Replacing with `certificate-authority-data` extraction would change a CONTEXT-pinned design and add complexity without changing semantics.

**Applied fix:**
Added a comment block before the `cat > "$DIRECT_KC" <<EOF` heredoc explaining (a) why the antipattern is intentional here, (b) that the construction is bats-internal and ephemeral, (c) that the apiserver returns 403 before TLS validation matters, (d) that the lint scope is the script only. This ensures future grep audits can exclude this occurrence and future contributors don't copy-paste the antipattern from this file thinking it's a "kubeconfig template".

**Verification:**
- `bats proxy-05-live-list-filter.bats`: 2/2 GREEN. Falsifier still proves the proxy is doing the filtering (direct apiserver returns 403).

---

### WR-09: `kubectl ... 2>/dev/null || true` masks transient kubectl failure modes

**Files modified:** `scripts/poc/capsule/issue-tenant-kubeconfig.sh`
**Commits:** `b5ef8b8` (initial fix), `4d0a54c` (follow-up to fix bash null-byte bug introduced by initial fix)
**Approach chosen:** REVIEW recommended -- capture stderr separately and differentiate by exit code. Initial implementation used `printf '%s\0%s' "$rc" "$out"` for inline RC+OUT packaging, but this is incorrect under bash command substitution (which silently strips null bytes; the stripped result corrupted the base64 CA cert). The follow-up commit replaces the null-byte trick with a stderr tmpfile, captured via `mktemp -t` + `trap rm -f EXIT`.

**Applied fix:**
1. `read_capsule_proxy_tls_crt` helper writes stderr to `${CA_STDERR}` tmpfile and returns kubectl's RC directly.
2. RC!=0 + stderr-contains-NotFound -> install hint (`capsule-proxy may not yet be installed`).
3. RC!=0 + other -> "transient apiserver/network" warn + 5s retry, then fail with `apiserver may be unreachable. Inspect: kubectl cluster-info` hint.
4. RC=0 + empty -> existing chart-cert-rotation retry path (preserved).
5. `trap 'rm -f "$CA_STDERR"' EXIT` ensures the tmpfile is cleaned up regardless of which branch the script takes.
6. Preserves the bats grep-pinned literals: `kubectl --context=k3d-spoke-capsule` (line 41 of proxy-01) and `{.data.tls\.crt}` (line 96 of proxy-01).

**Verification:**
- `bash -n` syntax check: PASS
- Manual smoke: `bash issue-tenant-kubeconfig.sh alpha gitops-reconciler 2>/dev/null > /tmp/test.kc && kubectl --kubeconfig=/tmp/test.kc get namespaces` -> works (returns `tenant-alpha` + `alpha-app1`).
- `bats proxy-01-static-script.bats`: 12/12 GREEN (literals still pinned)
- `bats proxy-04-live-issue.bats`: 7/7 GREEN
- `bats proxy-05-live-list-filter.bats`: 2/2 GREEN

**Note on the null-byte bug:** The initial WR-09 commit `b5ef8b8` shipped a real regression that broke the kubeconfig generation (illegal base64 data). This was caught at the post-fix verification step when running the full proxy bats suite -- proxy-05 tests started red-failing. The follow-up commit `4d0a54c` fixed the underlying mechanism (stderr tmpfile instead of null-byte separator). Both commits remain in history per the critical_rules "always create NEW commits rather than amending" guidance. Future maintainers reviewing the WR-09 fix should read both commits together.

---

## Skipped Issues

None -- all 11 in-scope findings were fixed.

INFO findings (IN-01..05) were filtered by `fix_scope: critical_warning` and are not addressed in this iteration. The phase context, REVIEW.md, and this REVIEW-FIX.md are sufficient for an operator to address those at their discretion.

---

## Final Test Status

After all 11 fixes (12 commits including the WR-09 follow-up), the full Phase 10 bats suite reports:

```
1..45
ok 1..39 ALL GREEN (proxy-01..06 + proxy-07 P31/CRD/Flux/Tenant/SA inheritance)
not ok 40 Phase 8 CAP-01 inheritance: HelmRelease capsule Ready=True on hub-flux
ok 41..45 ALL GREEN
```

**Test 40 is a pre-existing infrastructure failure** -- the `capsule-system` namespace does not exist on the live `k3d-hub-flux` cluster ("Error from server (NotFound): namespaces \"capsule-system\" not found"). Verified to fail BEFORE any Phase 10 review fixes were applied (reverted to commit `2e3a980` and re-ran proxy-07 -- same red). This is unrelated to Phase 10 and unaffected by any review-fix change. The capsule HelmRelease appears to be deferred or not yet reconciled in the current cluster state.

**44/45 GREEN** including all 12 static script-shape contracts, all 7 PROXY-01 live issuance tests (with the new mode 0600 assertion), all 2 PROXY-02 list-filter tests (with the WR-08 nolint marker), and all 3 PROXY-03 leak-defense tests (with the WR-03 BATS_TEST_TMPDIR move).

---

## Commit Sequence

| Commit | Finding | Files |
|---|---|---|
| `a6c93d7` | BL-01 | `scripts/poc/capsule/issue-tenant-kubeconfig.sh` |
| `4c205c0` | BL-02 + WR-07 | `scripts/poc/capsule/issue-tenant-kubeconfig.sh`, `tests/bats/proxy-04-live-issue.bats` |
| `c176594` | WR-01 | `scripts/poc/capsule/issue-tenant-kubeconfig.sh` |
| `3e90993` | WR-02 | `scripts/poc/capsule/issue-tenant-kubeconfig.sh` |
| `1db3696` | WR-03 | `tests/bats/proxy-06-live-fixture.bats` |
| `3bcbf06` | WR-04 | `scripts/poc/capsule/issue-tenant-kubeconfig.sh` |
| `c82e02b` | WR-05 | `scripts/poc/capsule/issue-tenant-kubeconfig.sh` |
| `23ba983` | WR-06 | `tests/bats/proxy-04-live-issue.bats` |
| `74d09e4` | WR-08 | `tests/bats/proxy-05-live-list-filter.bats` |
| `b5ef8b8` | WR-09 (initial) | `scripts/poc/capsule/issue-tenant-kubeconfig.sh` |
| `4d0a54c` | WR-09 (follow-up) | `scripts/poc/capsule/issue-tenant-kubeconfig.sh` |

11 fixes, 12 commits, 4 files modified. All commits land on `main` (the foreground tree), atomic per-fix, with `fix(10):` conventional prefix and explicit body explaining the why.

---

_Fixed: 2026-05-05T19:07:22Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
