---
phase: 07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc
reviewed: 2026-04-29T11:45:00Z
depth: standard
files_reviewed: 22
files_reviewed_list:
  - .gitignore
  - .gitleaks.toml
  - Taskfile.yml
  - clusters/hub-flux/flux-system/kustomization.yaml
  - clusters/hub-flux/pocs/capsule.yaml
  - clusters/hub-flux/pocs/kustomization.yaml
  - docs/capsule-on-eks.md
  - docs/poc-capsule.md
  - pocs/capsule/kustomization.yaml
  - scripts/poc/capsule/create-cluster.sh
  - scripts/poc/capsule/fix-dns.sh
  - scripts/preflight.sh
  - scripts/register-poc-cluster.sh
  - tests/bats/docs-06-eks.bats
  - tests/bats/poc-cluster-01-static.bats
  - tests/bats/poc-isolation-01-static.bats
  - tests/bats/poc-mount-01-static.bats
  - tests/bats/preflight-pre15.bats
  - tests/bats/register-poc-cluster-01-static.bats
  - tests/bats/repo-hygiene-02-taskfile.bats
  - tests/bats/repo-hygiene-04-poc.bats
  - tests/fixtures/gitleaks/benign-configmap.yaml
  - tests/fixtures/gitleaks/synthetic-kubeconfig.yaml
findings:
  blocker: 0
  warning: 5
  info: 5
  total: 10
status: issues_found
---

# Phase 7: Code Review Report

**Reviewed:** 2026-04-29T11:45:00Z
**Depth:** standard
**Files Reviewed:** 22
**Status:** issues_found

## Summary

Phase 7 lays the spoke-capsule POC seam: a persistent isolated k3d cluster registered with hub-flux via `spec.kubeConfig.secretRef`, plus a hub-side `# KARYON POC MOUNT` sentinel + `../pocs` aggregator, plus the EKS-target rough-cut design doc. All 66 bats tests pass. Phase invariants (ADR-004 hub-only Flux, P18 `key: value.yaml` everywhere, P29 gitleaks rule, P30 sentinel insertion idempotent + unique, P31 zero spoke-capsule mentions in v0.18 scripts, D-11 token safety) are honored under the **happy path**.

The findings below are concentrated in three areas:

1. **Sentinel insertion (`ensure_hub_pocs_mount`) is not robust to malformed input.** When the sentinel is placed AFTER `../pocs` (manual mis-edit), awk inserts a duplicate sentinel above, violating P30 sentinel-uniqueness. Same defect inherited from `ensure_hub_spokes_mount`, but real.
2. **Gitleaks rule has an over-broad regex anchor.** `^kind:\s*Config[\s\S]*?users:[\s\S]*?token:\s*[A-Za-z0-9._-]{32,}` matches `kind: ConfigMap` (because `Config` is a prefix of `ConfigMap`), producing false positives whenever a ConfigMap's data section contains both a `users:` key and a 32+ char `token:` value somewhere downstream.
3. **`fix-dns.sh` aborts on stop-failure even when the cluster is already stopped** — directly contradicting the troubleshooting prose in `docs/poc-capsule.md` which tells users to "proceed to start" in that case. Recovery requires manual `k3d cluster start` invocation outside the sanctioned `task fix-dns-poc-capsule` surface.

No BLOCKERs found. Five WARNINGs and five INFOs documented below. The code is in shippable shape but the WARNINGs should be addressed before Phase 8/10/11 add complexity on top of these seams.

## Warnings

### WR-01: Gitleaks rule's `Config` anchor produces false positives on `ConfigMap` resources

**File:** `.gitleaks.toml:28`
**Issue:** The regex `(?ms)^kind:\s*Config[\s\S]*?users:[\s\S]*?token:\s*[A-Za-z0-9._-]{32,}` anchors on `kind:\s*Config` but allows ANY continuation via `[\s\S]*?`. Since `Config` is a prefix of `ConfigMap`, any ConfigMap that contains both a key named `users:` and a value-like `token:` sequence with 32+ characters anywhere downstream will trigger the rule. Minimal repro: a manifest with `kind: ConfigMap` plus a `data.users:` key and a `data.token: <32+chars>` field fires the kubeconfig-bearer-token rule. This is a false-positive bomb for ConfigMaps that legitimately store sample API tokens, vendor configs, or documentation about kubeconfigs. It also matches `kind: ConfigCustom`, `kind: ConfigOptions`, etc. (any future `Config*` kinds Kubernetes or operators introduce).

Verified locally with gitleaks 8.30.1:
```
$ cat /tmp/test.yaml
kind: ConfigMap
data:
  users: foo
  token: thisismorethan32charactersnowtomorebehappier
$ gitleaks detect --no-git --source /tmp/test.yaml --config .gitleaks.toml
RuleID: kubeconfig-bearer-token  # FIRES
```

The negative fixture `tests/fixtures/gitleaks/benign-configmap.yaml` happens NOT to fire only because its `token:` value is 20 chars (`false-positive-canary`) — under the 32-char threshold. The bats test `POC-03 (live): gitleaks does NOT fire on negative fixture` passes for the wrong reason (length, not kind discrimination), giving false confidence.

**Fix:** Anchor the `Config` literal so it only matches the bare `kind: Config` kubeconfig kind, not prefix-extended kinds:
```toml
regex = '''(?ms)^kind:\s*Config[\s\r\n]+[\s\S]*?users:[\s\S]*?token:\s*[A-Za-z0-9._-]{32,}'''
```
The added `[\s\r\n]+` after `Config` requires a whitespace/newline character (not letter), preventing prefix-collision with `ConfigMap`. Alternatively, anchor against end of line: `^kind:\s*Config\s*$` (would need to break the `(?ms)[\s\S]*?` tail accordingly). Then update `tests/fixtures/gitleaks/benign-configmap.yaml` to include a 40+ char token that would have fired under the buggy regex (e.g., `token: thisismorethan32charactersinaconfigmap00000`), so the negative test asserts kind-discrimination not length-discrimination.

### WR-02: `ensure_hub_pocs_mount` awk inserts duplicate sentinel when sentinel appears AFTER `- ../pocs`

**File:** `scripts/register-poc-cluster.sh:230-241`
**Issue:** The awk pipeline that inserts `# KARYON POC MOUNT` above `- ../pocs` processes lines top-to-bottom and only sets `seen_sentinel` when it ENCOUNTERS the sentinel line. If a human edit (or future script change) places the sentinel AFTER the `- ../pocs` line, awk hits `- ../pocs` BEFORE seeing the existing sentinel — `seen_sentinel` is still 0 — and inserts a NEW sentinel above. The original sentinel below remains. Result: two `# KARYON POC MOUNT` lines, violating P30 sentinel-uniqueness.

Verified locally with the actual awk body, against a YAML that has the sentinel placed after `../pocs`:
```yaml
resources:
  - ../pocs
  # KARYON POC MOUNT
```
After the awk pass becomes:
```yaml
resources:
  # KARYON POC MOUNT       # NEW (incorrectly inserted)
  - ../pocs
  # KARYON POC MOUNT       # PRE-EXISTING
```
`grep -cF -- "# KARYON POC MOUNT"` returns 2.

This defect is inherited verbatim from `ensure_hub_spokes_mount` in `scripts/register-spokes-for-flux.sh`, but Phase 7 ports the bug into a NEW execution path (not just inherits it), and the bats test `POC-01 / P30: # KARYON POC MOUNT sentinel appears EXACTLY ONCE (idempotency)` would FAIL on the next run after such a mis-ordering. The current state passes because the file is in canonical form, but the recovery path from a mis-ordered file is broken.

**Fix:** Pre-scan the file for sentinel presence in a separate pass before the awk insertion. If the sentinel exists anywhere, skip awk insertion entirely:
```bash
if grep -qF -- "${POCS_SENTINEL}" "${tmp}"; then
  cp "${tmp}" "${tmp_with_sentinel}"
else
  awk -v sentinel="${POCS_SENTINEL}" '
    $0 ~ /^[[:space:]]*-[[:space:]]+\.\.\/pocs[[:space:]]*$/ && !inserted {
      match($0, /^[[:space:]]*/)
      print substr($0, RSTART, RLENGTH) sentinel
      inserted=1
    }
    { print }
  ' "${tmp}" > "${tmp_with_sentinel}"
fi
```
This makes the function robust against any sentinel position; the cmp-then-mv idempotency check still guards against unnecessary rewrites. Apply same fix to `ensure_hub_spokes_mount` for consistency.

### WR-03: `fix-dns.sh` aborts on `k3d cluster stop` failure — contradicts documented troubleshooting

**File:** `scripts/poc/capsule/fix-dns.sh:41-46`
**Issue:** The script wraps `k3d cluster stop "${POC_CLUSTER}"` in a fail-on-error guard. If the cluster is already stopped (Docker daemon was restarted, WSL was resumed, etc.), `k3d cluster stop` exits non-zero and the script aborts BEFORE reaching the start step. This directly contradicts `docs/poc-capsule.md:80-89` (Troubleshooting / "Cluster fails to stop") which tells the user "If no `k3d-spoke-capsule-*` containers are running, the cluster is already stopped — proceed to start." The user has no documented sanctioned recovery path: re-running `task fix-dns-poc-capsule` aborts at the same step; the docs don't include an explicit `k3d cluster start spoke-capsule` invocation in the troubleshooting block.

Idempotency is one of the explicit Phase 7 contracts and the script is meant to be the canonical recovery surface for a stale-CoreDNS/post-restart spoke. Aborting on a no-op stop is the wrong default.

**Fix:** Replace the stop guard with a check-then-stop pattern that no-ops if the cluster is already stopped:
```bash
# Check whether any spoke-capsule containers are running. If yes, stop them.
if docker ps --filter "name=k3d-${POC_CLUSTER}-" --format '{{.Names}}' | grep -q "^k3d-${POC_CLUSTER}-"; then
  if ! k3d cluster stop "${POC_CLUSTER}"; then
    fail "failed to stop ${POC_CLUSTER}.
       Inspect: k3d cluster list
       Fix:     bash scripts/poc/capsule/create-cluster.sh && bash scripts/poc/capsule/fix-dns.sh"
    exit 1
  fi
  pass "stopped: ${POC_CLUSTER}"
else
  info "already stopped: ${POC_CLUSTER}"
fi
```
This makes fix-dns.sh truly idempotent and aligns the script with the troubleshooting prose.

### WR-04: `cert_tmp` file leaks if openssl/curl fails unexpectedly with `set -e`

**File:** `scripts/register-poc-cluster.sh:300-355`
**Issue:** `verify_credential_layer` creates a temp file via `mktemp -t "karyon-${spoke}-apiserver-ca.XXXXXX.pem"` at line 300, then explicitly calls `rm -f "${cert_tmp}"` only on (a) the four explicit error paths after the openssl loop / curl calls, and (b) line 355 (after the `/api/v1/nodes` curl). If any unexpected fatal error occurs between line 300 and the explicit cleanup (e.g., a kernel signal, an uncaught failure mode in `decode_b64`, or `set -e` aborting on an unanticipated non-zero return), the cert tempfile is leaked into `/tmp`. The leaked file is the apiserver's PUBLIC CA cert (not a private key), so this is not a security exposure — but it's a hygiene / disk-space concern under repeated retry loops.

There is also no top-level trap-based cleanup like the `_pre14_cleanup` / `trap _pre14_cleanup EXIT` pattern used in `scripts/preflight.sh:392-396`, so the tempfile cleanup is non-defensive.

**Fix:** Add a function-scoped trap-based cleanup at the top of `verify_credential_layer`:
```bash
verify_credential_layer() {
  local spoke="$1" cert_tmp
  cert_tmp="$(mktemp -t "karyon-${spoke}-apiserver-ca.XXXXXX.pem")"
  trap 'rm -f "${cert_tmp}"' RETURN
  # ... rest of function (remove explicit `rm -f` lines since trap covers them)
}
```
The `trap ... RETURN` pseudo-signal fires on function return, regardless of success/failure path, ensuring cleanup. Same pattern should be applied to the `tmp` and `tmp_with_sentinel` files in `ensure_hub_pocs_mount` (lines 212, 229).

### WR-05: Section header `${POC_CLUSTER}` interpolation inside shell COMMENT is misleading documentation

**File:** `scripts/poc/capsule/fix-dns.sh:39, 57`; `scripts/register-poc-cluster.sh:404, 408, 411`
**Issue:** Several shell comments use `${POC_CLUSTER}` interpolation syntax, e.g.:
```bash
# ---------- Section 2: ${POC_CLUSTER} stop/start ----------
```
Bash does NOT expand `${POC_CLUSTER}` inside `#` comments — the literal string `${POC_CLUSTER}` is what's there. Future readers who scan the script (or grep for cluster-name references) will see the literal `${POC_CLUSTER}` and might believe it's a runtime-rendered variable. Under tests/bats/poc-isolation-01-static.bats, the `grep -v '^[[:space:]]*#'` filter strips comments before counting forbidden-literal references, so this is benign for the isolation test. But it is misleading documentation.

**Fix:** Either drop the `${...}` syntax in comments (use the literal `spoke-capsule`) or move the variable name outside the `${}` braces in the comment, e.g., `# ---------- Section 2: spoke-capsule stop/start ----------`. Apply consistently across both scripts. (Note: the `section "${POC_CLUSTER} stop/start"` calls AT runtime DO interpolate correctly — only the comment lines are cosmetic.)

## Info

### IN-01: Five unused readonly/local variables flagged by shellcheck

**File:** `scripts/register-poc-cluster.sh:47, 49, 51, 269`; `scripts/poc/capsule/create-cluster.sh:100`
**Issue:** ShellCheck reports five SC2034 (unused-variable) warnings:
- `scripts/register-poc-cluster.sh:47`: `readonly POCS_DIR="${REPO_ROOT}/clusters/hub-flux/pocs"` — never referenced in the script body.
- `scripts/register-poc-cluster.sh:49`: `readonly POCS_RESOURCE="../pocs"` — the literal `"../pocs"` is hardcoded in the awk regex and yq expression at lines 214, 222, 231, 243; the constant is never used.
- `scripts/register-poc-cluster.sh:51`: `readonly RECONCILER_BINDING="flux-reconciler-cluster-admin"` — the literal is embedded in the heredoc at line 111; the constant is never used.
- `scripts/register-poc-cluster.sh:269`: `local ... http_status` — declared in the local list at the top of `verify_credential_layer` but never assigned or used.
- `scripts/poc/capsule/create-cluster.sh:100`: `for i in $(seq 1 10); do` — `i` is the loop variable but never referenced inside the loop body (uses `$_` would be idiomatic, but `i` is the convention here).

These are dead declarations. Either remove them or use them (preferred: replace the inline literals at lines 214/222/231/243 with `"${POCS_RESOURCE}"`, and embed `${RECONCILER_BINDING}` in the heredoc).

**Fix:**
```bash
# Remove:
readonly POCS_DIR=...
local ... http_status

# Replace inline literals with constants:
yq eval "(.resources // []) as \$r | .resources = (\$r + [\"${POCS_RESOURCE}\"] | unique)" "${HUB_KUST_FILE}" > "${tmp}"
# (same for lines 222, 243; awk pattern at line 231 needs awk-escape)

# create-cluster.sh:100 — replace `for i in $(seq 1 10)` with `for _ in $(seq 1 10)`
```

### IN-02: Dead code — summary-block `if (( FAIL > 0 )); then exit 1; fi` is unreachable

**File:** `scripts/poc/capsule/create-cluster.sh:124`; `scripts/poc/capsule/fix-dns.sh:74`; `scripts/register-poc-cluster.sh:415`
**Issue:** All three Phase 7 scripts run under `set -euo pipefail` and exit explicitly with `exit 1` after every `fail` call. This means when execution reaches the Summary section, `FAIL` is guaranteed to be 0. The `if (( FAIL > 0 )); then exit 1; fi` line is dead code in all three scripts. The pattern is copy-pasted from preflight.sh which has a different contract (preflight intentionally uses `set -u` — NOT `-e` — and accumulates failures without exiting). Phase 7 scripts inherited the line without honoring the contract.

This is harmless but mildly misleading: a future reader inspecting these scripts would assume the summary's pass/warn/fail counters are meaningful, when in practice they only ever show all-pass (or never run at all due to early exit).

**Fix:** Either drop the dead `if (( FAIL > 0 )); then exit 1; fi` line (preferred — clearer contract), or restructure the scripts to accumulate failures (more invasive — drop `set -e` and let summary be the central exit gate). Recommend the former.

### IN-03: `karyon-tenants/` gitignore comment misdescribes its scope

**File:** `.gitignore:23-24`
**Issue:** The comment block at lines 23-24 says:
```
# Phase 7 D-14 expansion (v0.19 POC-03) ──────────────────
# Tenant kubeconfig globs (Phase 10 ${TMPDIR:-/tmp}/karyon-tenants/ destination):
karyon-tenants/
```
The implication is that `karyon-tenants/` ignores files written to `${TMPDIR:-/tmp}/karyon-tenants/`. But git's gitignore semantics are repo-relative — `karyon-tenants/` only matches `<repo-root>/karyon-tenants/`, not `/tmp/karyon-tenants/`. Files under `/tmp/` are already outside the git tree and don't need a gitignore at all.

The defensive value of `karyon-tenants/` IS preserved — if a developer ever copies tenant kubeconfigs into the repo (e.g., for inspection), git will ignore them. But the comment overstates the connection to TMPDIR.

**Fix:** Reword the comment to clarify that this is defensive coverage rather than direct-path coverage:
```
# Phase 7 D-14 expansion (v0.19 POC-03) ──────────────────
# Tenant kubeconfig globs — defensive against accidental commit. Phase 10 writes
# tenant kubeconfigs to ${TMPDIR:-/tmp}/karyon-tenants/ (outside the repo tree),
# but `karyon-tenants/` here also catches the case where a developer copies
# them into the repo for inspection.
karyon-tenants/
```

### IN-04: `apply_spoke_rbac` heredoc uses unquoted `<<EOF` — unnecessary expansion-attack surface

**File:** `scripts/register-poc-cluster.sh:96, 129`
**Issue:** The `apply_spoke_rbac` function uses `<<EOF` (unquoted) for the kubectl heredoc. While the current heredoc body has no `$variable` references, the unquoted form means future edits that introduce a `$` literal (e.g., a username like `$(whoami)` or a `$1` reference) would be silently expanded by bash before kubectl reads stdin. This is a stylistic / future-proofing concern; not a real bug today.

The companion `build_kubeconfig` function at line 162 USES variable expansion (`${spoke}`, `${bearer}`, `${cert_part}`) and correctly uses `<<EOF`. So `apply_spoke_rbac` could safely use `<<'EOF'` to disable expansion entirely.

**Fix:** Change line 96 from `<<EOF` to `<<'EOF'`. No body changes needed (heredoc has no `$` literals today).

### IN-05: Capsule.yaml Flux Kustomization missing forward-looking fields (`wait`, `timeout`, `dependsOn`)

**File:** `clusters/hub-flux/pocs/capsule.yaml:17-27`
**Issue:** The Flux Kustomization at `clusters/hub-flux/pocs/capsule.yaml` specifies only `interval: 5m`, `path`, `prune`, `sourceRef`, `kubeConfig`. It does NOT specify `wait`, `timeout`, `retryInterval`, `dependsOn`. These are not required for Phase 7 (where `pocs/capsule/` has empty `resources: []`), but Phase 8 will add HelmReleases for `capsule` + `capsule-proxy` operators, where `wait: true` and a `timeout` are usually critical for ordering CRD installation before tenant CRs.

This is purely forward-looking — Phase 7 is correct. But the docs/capsule-on-eks.md:40 narrative says: "Phase 9 enforces this with `dependsOn` + `wait: true` on the operator Kustomization." Phase 9 will need to add these fields here, OR introduce a sibling Kustomization for the operator that has them.

**Fix:** No change required for Phase 7. Note for Phase 8/9 implementer: when adding HelmReleases under `pocs/capsule/`, decide whether to extend this single Kustomization with `wait: true`/`timeout: 5m` or to split into operator + tenants Kustomizations with `dependsOn`. Document the choice in the Phase 8 plan.

---

_Reviewed: 2026-04-29T11:45:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
