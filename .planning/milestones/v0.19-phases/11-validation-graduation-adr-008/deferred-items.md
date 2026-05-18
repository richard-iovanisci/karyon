# Phase 11 Deferred Items

Items discovered during Phase 11 plan execution that are out of scope of the
current plan but should be tracked.

## Plan 11-01 (executed 2026-05-06)

### Pre-existing gitleaks finding -- tests/bats/proxy-06-live-fixture.bats

**Discovered during:** Plan 11-01 Task 2 verification (`gitleaks detect --no-git`
returned 2 findings in `tests/bats/proxy-06-live-fixture.bats:43`).

**Why deferred:** This file existed BEFORE Plan 11-01 began (Phase 10 inheritance).
Plan 11-01 owns the `.gitleaks.toml` allowlist edits for Phase 7 + Phase 10
PLANNING markdown files (D-11-04-revised). The proxy-06 BATS test is a different
artifact class (test fixture quoting kind: Config) -- adding it to the
file-specific allowlist would expand the scope of D-11-04-revised beyond what
the plan + reviewer HIGH #3 specifies.

**Resolution candidate:** Either (a) Plan 11-04 (push event) catches the live
gitleaks scan failure and explicitly allowlists the bats fixture file as part
of VAL-05 push-gate hardening, OR (b) the bats fixture is rewritten to use a
non-leaky synthetic kubeconfig shape (e.g., placeholder token instead of a
matching pattern). Either approach is in-scope for VAL-05.

**Suggested allowlist entry (if option a):**
```toml
'''^tests/bats/proxy-06-live-fixture\.bats$''',  # synthetic kubeconfig fixture (Phase 10 PROXY-06)
```
