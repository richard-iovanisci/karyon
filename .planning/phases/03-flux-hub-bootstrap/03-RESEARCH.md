# Phase 3: Flux Hub Bootstrap - Research

**Researched:** 2026-04-24
**Domain:** Flux v2 GitOps bootstrap on k3d (hub-only topology); idempotent bash scripting; bats destructive-test gating
**Confidence:** HIGH on flux bootstrap flag surface + Secret shape + idempotency; MEDIUM on kustomization.yaml-comment-preservation and kubectl wait edge semantics; LOW on D-03 network-policy rationale (evidence contradicts the CONTEXT.md wording — see Pitfall 6)

## Summary

Phase 3 is a tight, LOW-risk phase: one wrapper script (`scripts/bootstrap-flux.sh`), one short contract doc (`docs/flux-hub-spoke.md`), one comment-block augmentation on the bootstrap-generated `clusters/hub-flux/flux-system/kustomization.yaml`, and one destructive-gated bats test proving idempotency. Research confirms every locked decision in CONTEXT.md (D-01..D-16) is implementable with standard Flux 2.8.6 primitives, and closes all ten "Claude's Discretion" items. The critical find: on Question 1 (token passing), the env-var approach (`export GITHUB_TOKEN=...` → plain `flux bootstrap github`) is **safe from `ps auxww`** because Unix process listings show argv by default, not environ — the CONTEXT.md phrasing is satisfied by the simplest form. The critical hazard: **k3s/k3d DO enforce NetworkPolicy by default via an embedded kube-router netpol controller** (not flannel). The D-03 "flannel does not enforce NPs" rationale is factually wrong, but the conclusion (`--network-policy=false`) remains defensible on different grounds (lab has no adversarial boundary, NP adds debug surface) — flagged for the plan-checker to surface a one-sentence rationale fix.

**Primary recommendation:** Structure `scripts/bootstrap-flux.sh` as five sections — preflight gate, context + idempotency checks, `flux bootstrap`, post-bootstrap verification, patch-surface marker — with the exact invocation `GITHUB_TOKEN="$GITHUB_TOKEN" flux bootstrap github --owner "$GITHUB_OWNER" --repository "$GITHUB_REPO" --path clusters/hub-flux --personal --private=false --network-policy=false --token-auth --branch main`. Use an idempotent awk/sed block (grep-for-sentinel guarded) to prepend the D-13 comment to `kustomization.yaml`. Ship the destructive bats test under `tests/bats/bootstrap-flux-01-idempotent.bats` using the existing `require_live_destructive()` double-gate.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**`flux bootstrap github` Flag Surface**
- **D-01:** `--private=false`. Matches PROJECT.md "public from day one" posture. On first run `flux bootstrap` creates the GitHub repo public if it does not exist; on subsequent runs the flag is a no-op. Token-leak risk mitigated by (a) PAT stored only in an in-cluster Secret, not in git, and (b) Phase 6 gitleaks pre-commit landing before first `git push` per ROADMAP Phase 6 parallelization schedule.
- **D-02:** `--personal=true`. Single-author lab targeting a personal GitHub account; `GITHUB_TOKEN` uses classic PAT with `repo` scope. Org-account path is out of scope.
- **D-03:** `--network-policy=false`. Disables the default deny-all NetworkPolicy that isolates `flux-system`. Rationale: k3d's flannel CNI does not enforce NetworkPolicies reliably, and the lab has no adversarial namespace boundary — the policy adds debug surface ("why is reconcile failing?") with no real security benefit at this scope.
- **D-04:** No `--components-extra`. Ship only the 4 core controllers (source-controller, kustomize-controller, helm-controller, notification-controller). Image automation is explicitly v2 per PROJECT.md Out of Scope. Revisit when a release cadence exists.

**Idempotency + Preflight Gating**
- **D-05:** `scripts/bootstrap-flux.sh` **delegates to `scripts/preflight.sh`** as its first step. Mirrors Phase 2 D-06 integration pattern. Preflight already covers `.env` presence + key non-emptiness, asdf shim precedence, tool pins (incl. flux 2.8.6), Docker runtime, WSL host floor.
- **D-06:** **kubectl context gate is an explicit fail-with-remediation**, not auto-switch. Script must not mutate the user's shell-global kubeconfig state.
- **D-07:** **Idempotency = "skip if healthy, else fall through to full bootstrap"**. The "already done" gate is a three-part AND: (1) `kubectl get ns flux-system` exists, AND (2) `flux check` exits 0, AND (3) All 4 controller Deployments report `Available=True`. On healthy skip, log `info "already done, skipping: flux bootstrap"` and exit 0.
- **D-08:** **No GitHub API PAT-scope probe.** If the PAT lacks `repo` scope, `flux bootstrap github` fails with a clear upstream message; the script surfaces that unchanged.

**Post-Bootstrap Verification**
- **D-09:** **Full three-gate success check** before exit 0: (1) `flux check` passes, (2) `kubectl wait --for=condition=Available deploy --all --timeout=120s` succeeds, (3) `flux get kustomizations flux-system` reports Ready=True.
- **D-10:** **Readiness wait uses `kubectl wait` with a 120s timeout**, not a custom bash poll.
- **D-11:** **Token-leak defense is script discipline, not runtime filtering.** `set -euo pipefail` (no `-x`), never `echo "$GITHUB_TOKEN"`, no `tee`/log-to-file in v1. No sed-redaction wrapper.
- **D-12:** **Idempotency is proven by an external bats test**, not a self-rerun inside the script. Test invokes script twice, asserts second invocation logs skip message and exits 0.

**Doc + `kustomization.yaml` Seed**
- **D-13:** **Let `flux bootstrap` write `clusters/hub-flux/flux-system/kustomization.yaml`; then augment with a top-of-file comment block** as a post-bootstrap step. Comment block reads approximately the "FLUX PATCH SURFACE" block given in CONTEXT.md.
- **D-14:** **`docs/flux-hub-spoke.md` Phase-3 scope is tight** — exactly the three rules required by ROADMAP Success #4, each with a short "why" paragraph, plus one worked patch example (D-15) and a one-line mention of bootstrap-flux.sh's skip-message (D-16). Leave `<!-- Phase 4: hub-spoke reconciliation -->` HTML-comment stub at bottom.
- **D-15:** **Include one concrete patch example** — bumping kustomize-controller's memory limit via a `patches:` block.
- **D-16:** **`docs/flux-hub-spoke.md` explicitly mentions the idempotency-skip behavior.** One sentence pointing at bootstrap-flux.sh.

### Claude's Discretion

Planner/researcher decides; CONTEXT.md provides preferences, this RESEARCH.md resolves each below (see §Open Questions → Resolved for the one-liner per item). Items:
- Where D-13's comment-block augmentation happens (inline script vs. separate commit). **Guidance:** Prefer inline script augmentation, idempotently guarded.
- `GITHUB_TOKEN` passing mechanism (env var vs. stdin vs. file). Pick the form that guarantees the token is NOT visible via `ps auxww`.
- `--author-name` / `--author-email` (defaults or wired to git config / .env).
- `--branch` default (main) — pass explicitly or omit.
- `--cluster-domain` (default cluster.local correct for k3d).
- Whether bootstrap-flux.sh re-asserts `flux version` (preflight already does).
- Phase 6 gitleaks hook — warn only if `.git/hooks/pre-commit` does not reference `gitleaks`, or ignore. Recommendation: warn only.
- Whether script sets up `git remote` / `git push` itself, or trusts `flux bootstrap github` end-to-end.
- Bats test structure — reuse `require_live_destructive()` double-gate from Phase 2 (follow the pattern).
- `docs/flux-hub-spoke.md` front-matter / TOC — implementation taste.

### Deferred Ideas (OUT OF SCOPE)

- Image automation (image-reflector / image-automation controllers) — v2.
- GitHub org/app bootstrap — v2 if the project goes multi-author.
- NetworkPolicy-based flux-system isolation — no adversarial boundary.
- GitHub API PAT-scope probe in bootstrap-flux.sh.
- Auto-switch kubectl context on mismatch.
- Self-rerun inside bootstrap-flux.sh for idempotency proof.
- sed-redaction wrapper around `flux bootstrap` stdout.
- Pre-commit an empty `kustomization.yaml` before bootstrap.
- Hard-block bootstrap-flux.sh on Phase 6 gitleaks being installed.
- Phase 4 hub-spoke reconciliation content in `docs/flux-hub-spoke.md`.
- ADR-003 / ADR-004 authoring (Phase 6).
- Flagger / progressive delivery — PROJECT.md Out of Scope.
- Full `Taskfile.yml` REPO-05 reorganization — Phase 6.
- `--components-extra=notification-controller` customization (no webhook requirement).
- Non-`main` branch bootstrap.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| FLUX-01 | `scripts/bootstrap-flux.sh` runs `flux bootstrap github` targeting `hub-flux`. | §Standard Stack (flux 2.8.6 verified), §Code Examples (invocation skeleton), §Architecture (5-section script structure). |
| FLUX-02 | `--path` is hard-coded to `clusters/hub-flux` (effectively immutable after first run). | §Common Pitfalls P2 (changing --path creates divergent commit), §Don't Hand-Roll (trust flux semantics). |
| FLUX-03 | `GITHUB_OWNER`/`GITHUB_REPO`/`GITHUB_TOKEN` read from gitignored `.env`; script never echoes token. | §Architecture (env var loading via `set -a; source .env; set +a`), §Common Pitfalls P1 (token exposure via ps — env var is safe). |
| FLUX-04 | Bootstrap is idempotent; rerun is a no-op. | §Architecture (three-part idempotency gate), §Validation Architecture (idempotency path). |
| FLUX-05 | `docs/flux-hub-spoke.md` documents bootstrap-managed vs patch-surface rules + `--path` immutability. | §Code Examples (docs skeleton + D-15 patch example), §Don't Hand-Roll (kustomization.yaml IS the Flux patch surface — documented idiom). |
</phase_requirements>

## Project Constraints (from CLAUDE.md / AGENTS.md)

- **Public-safe by default.** Placeholders instead of real secrets; no hostnames, tokens, or internal URLs in committed code. PAT lives in gitignored `.env` + in-cluster Secret only.
- **`.planning/` is intentionally tracked.** Do not add it to .gitignore or move it.
- **Prefer repo-local instructions.** Phase 1/2 `preflight-lib.sh` vocabulary (`section`/`pass`/`warn`/`fail`/`info`/`have`) is the canonical style — re-use verbatim.
- **Read project docs before guessing.** `.planning/PROJECT.md`, `CONTEXT.md`, prior-phase CONTEXT/RESEARCH/VERIFICATION are primary sources.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Preflight env/tool/host gate | Bash (host) | — | Already owned by Phase 1 `scripts/preflight.sh`; bootstrap-flux delegates, does not re-implement. |
| kubectl context assertion | Bash (host) | — | User-shell-scoped; script reads, does not mutate. Phase 3 D-06. |
| `flux bootstrap github` invocation | Flux CLI (binary) | GitHub REST API | Flux CLI handles PAT → GitHub API (repo creation, deploy-key or Secret setup) and kubectl → cluster (CRD install, Deployment apply, GitRepository + Kustomization CRs). |
| In-cluster controller health | K8s (flux-system namespace) | kubectl | Owned by kustomize-controller + source-controller reconciliation loop; verified via `flux check` + `kubectl wait`. |
| PAT storage | K8s Secret (`flux-system/flux-system`) | — | Flux writes the PAT as `username`+`password` keys in an opaque Secret (HTTPS basic-auth idiom). Bootstrap-flux only populates; script never reads it back. |
| Git repo seeding | Flux CLI (pushes to GitHub) | — | `flux bootstrap github` handles `git init` equivalent + `git commit` + `git push` to remote; local script does NOT run `git remote add` or `git push`. |
| `kustomization.yaml` comment augmentation | Bash (host) | kustomize-controller (reconciles back) | Script prepends sentinel-guarded comment block post-bootstrap; Flux's Kustomize drift-detection honors the YAML semantics (patches + resources), not comments, so augmentation survives reconciliation. |
| Idempotency proof | Bats (tests/bats/) | — | External destructive test, double-gated by `KARYON_LIVE_TESTS=1 KARYON_LIVE_TESTS_DESTRUCTIVE=1`. |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| flux (flux2) | 2.8.6 | Bootstrap + lifecycle CLI for Flux GitOps | [VERIFIED: `.tool-versions` line 3, PROJECT.md, fluxcd/flux2 GitHub releases page — v2.8.6 released 2026-04-21] [CITED: https://fluxcd.io/flux/installation/bootstrap/github/] |
| kubectl | 1.35.0 | Context assertion, `wait`, `get deploy/kustomizations` | [VERIFIED: `.tool-versions` line 1] — asdf-pinned, shim precedence enforced by Phase 1 PRE-10 |
| k3d | 5.8.3 | Provides the hub-flux target cluster on :6443 | [VERIFIED: `.tool-versions` line 4] — Phase 2 stands this up; Phase 3 only consumes the kubectl context `k3d-hub-flux` |
| bats-core | system | Idempotency proof (D-12) via external harness | [VERIFIED: tests/bats/test_helper.bash exists; 11 Phase 2 bats files live; `require_live_destructive()` already defined lines 43-49] |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| openssl | system | (Not needed in Phase 3 — but Phase 2 uses it for SAN verify) | — |
| jq | 1.8.1 | (Not needed in Phase 3 — D-08 explicitly rejects the GitHub API PAT-scope probe) | — |
| awk / sed | system | Idempotent top-of-file comment-block prepend on `kustomization.yaml` (D-13) | Grep-for-sentinel guards a one-shot awk/sed transformation; POSIX-safe |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `flux bootstrap github` (per D-01..D-04) | `flux install` + manual git bootstrapping | Rejected by ROADMAP/PROJECT (Flux-over-ArgoCD rationale); bootstrap subcommand is the documented hub-primary flow |
| `--token-auth` (HTTPS + PAT) | SSH deploy key flow (default when `--token-auth` absent) | `--token-auth` matches PROJECT.md secrets posture (PAT in gitignored .env; no SSH key management) and the in-cluster `flux-system/flux-system` Secret stores the PAT [CITED: https://fluxcd.io/flux/installation/bootstrap/github/]. SSH flow would require generating/persisting a deploy key, adding rotation complexity. |
| `kubectl wait --for=condition=Available` (D-10) | custom bash poll loop | Rejected by D-10; `kubectl wait` is idiomatic, one-line, clean failure surface. Exit 0 on all conditions met; exit 1 on timeout [CITED: kubectl reference]. |
| `flux get kustomizations flux-system` (D-09 gate 3) | `kubectl get kustomization flux-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'` | Either works. `flux` CLI is more readable, pre-installed per `.tool-versions`. Use `flux get kustomizations flux-system --no-header | awk '{print $2}'` and match `True`. |
| Inline awk/sed for D-13 comment prepend | One-shot commit + trust reconciliation | CONTEXT.md guidance: inline script augmentation. Reason: hand-commit could be reverted if a future `flux bootstrap` ever rewrote `kustomization.yaml`; in-script guarded augmentation is the durable invariant. |

**Installation:** No new packages. All tools pinned via existing `.tool-versions` and installed by Phase 1 `install-tools.sh`. Bootstrap-flux.sh assumes preflight green (PRE-05 confirms `flux 2.8.6`, `kubectl 1.35.0`).

**Version verification:**
- flux2 2.8.6 — [VERIFIED: fluxcd/flux2 GitHub releases, v2.8.6 released 2026-04-21; described as a patch release with no bootstrap-subcommand changes]
- kubectl 1.35.0, k3d 5.8.3 — [VERIFIED: `.tool-versions`, Phase 2 VERIFICATION.md]

## Architecture Patterns

### System Architecture Diagram

```
        ┌────────────────────────────────────────────────────────────┐
        │   USER:  bash scripts/bootstrap-flux.sh  (or task bootstrap-flux)
        └─────────────────────────────┬──────────────────────────────┘
                                      │
          ┌───────────────────────────▼───────────────────────────┐
          │ SECTION 1: Preflight gate                              │
          │   scripts/preflight.sh > /dev/null || fail             │
          │   (delegates: .env, asdf shims, tool pins, PRE-09..14) │
          └───────────────────────────┬───────────────────────────┘
                                      │
          ┌───────────────────────────▼───────────────────────────┐
          │ SECTION 2: Context + idempotency checks                │
          │   (a) kubectl current-context == k3d-hub-flux  (D-06)  │
          │   (b) 3-part idempotency AND (D-07):                   │
          │       - ns flux-system exists                          │
          │       - flux check → 0                                 │
          │       - 4 controllers Available=True                   │
          │     └─ on healthy:  info "already done, skipping..."   │
          │                     exit 0                             │
          │     └─ on drift:    proceed to SECTION 3               │
          └───────────────────────────┬───────────────────────────┘
                                      │
          ┌───────────────────────────▼───────────────────────────┐
          │ SECTION 3: flux bootstrap github                       │
          │   set -a; source .env; set +a                          │
          │   GITHUB_TOKEN="$GITHUB_TOKEN" flux bootstrap github \ │
          │     --owner $GITHUB_OWNER --repository $GITHUB_REPO \  │
          │     --path clusters/hub-flux \                         │
          │     --personal --private=false --network-policy=false \│
          │     --token-auth --branch main                         │
          │   (Flux CLI → GitHub REST API → creates/reuses repo,   │
          │    commits gotk-components/gotk-sync/kustomization.yaml│
          │    → applies to cluster → installs 4 controllers +     │
          │    GitRepository + Kustomization flux-system + Secret) │
          └───────────────────────────┬───────────────────────────┘
                                      │
          ┌───────────────────────────▼───────────────────────────┐
          │ SECTION 4: Post-bootstrap verification (D-09)          │
          │   (a) flux check → 0                                   │
          │   (b) kubectl wait --for=condition=Available \         │
          │         deploy --all -n flux-system --timeout=120s     │
          │   (c) flux get kustomizations flux-system → Ready=True │
          └───────────────────────────┬───────────────────────────┘
                                      │
          ┌───────────────────────────▼───────────────────────────┐
          │ SECTION 5: Patch-surface marker (D-13)                 │
          │   FILE=clusters/hub-flux/flux-system/kustomization.yaml│
          │   if grep -qF "# FLUX PATCH SURFACE" $FILE; then       │
          │     info "already done, skipping: patch marker"        │
          │   else                                                 │
          │     awk: prepend comment block → temp → mv             │
          │     pass "applied: patch marker"                       │
          │   fi                                                   │
          └───────────────────────────┬───────────────────────────┘
                                      │
                                   exit 0
```

**Side-effects (not visible in diagram):**
- GitHub repo `$GITHUB_OWNER/$GITHUB_REPO` created public (D-01) if missing.
- First bootstrap commits three files under `clusters/hub-flux/flux-system/`: `gotk-components.yaml`, `gotk-sync.yaml`, `kustomization.yaml`.
- In-cluster Secret `flux-system/flux-system` populated with `username` + `password` keys (HTTPS basic-auth; PAT is the password) [CITED: https://fluxcd.io/flux/components/source/gitrepositories/].
- Kustomization resource `flux-system` starts reconciliation loop every 1m0s (default `--interval`).

### Recommended Project Structure
```
scripts/
├── bootstrap-flux.sh                     # NEW — Phase 3 deliverable
├── lib/preflight-lib.sh                  # existing — sourced by bootstrap-flux.sh
├── preflight.sh                          # existing — delegated to (D-05)
├── create-clusters.sh                    # existing — Phase 2 (provides hub-flux)
└── delete-clusters.sh                    # existing — Phase 2

docs/
└── flux-hub-spoke.md                     # NEW — Phase 3 deliverable (DOCS-03)

clusters/
└── hub-flux/
    └── flux-system/                      # CREATED BY flux bootstrap, committed to git
        ├── gotk-components.yaml          # bootstrap-managed; do not hand-edit
        ├── gotk-sync.yaml                # bootstrap-managed; do not hand-edit
        └── kustomization.yaml            # patch surface; top-comment prepended by Phase 3

tests/bats/
└── bootstrap-flux-01-idempotent.bats     # NEW — Phase 3 deliverable (D-12)

Taskfile.yml                              # APPEND one entry: bootstrap-flux (single line)
```

### Pattern 1: Guarded-Sections Idempotency (Phase 1 D-05 / Phase 2 D-09)
**What:** Every logical step checks state first and either logs `info "already done, skipping: <what>"` or proceeds with `pass "<doing>: <what>"`.
**When to use:** All 5 sections of bootstrap-flux.sh.
**Example:**
```bash
# Source: scripts/create-clusters.sh lines 44-58 (Phase 2 verbatim)
if docker network inspect "$K8S_NET_NAME" >/dev/null 2>&1; then
  # ...drift check...
  info "already done, skipping: ${K8S_NET_NAME}"
else
  docker network create ...
  pass "creating: ${K8S_NET_NAME}"
fi
```

### Pattern 2: Preflight-Lib Delegation (Phase 2 D-06 / CONTEXT.md §code_context)
**What:** Single source of truth for pass/warn/fail/info/section/have. Bootstrap-flux sources it and inherits ANSI-color gate, counters, and the `FAIL > 0 → exit 1` convention.
**Example:**
```bash
# Source: scripts/create-clusters.sh lines 19-23
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/preflight-lib.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/preflight-lib.sh"
```

### Pattern 3: Remediation-Rich `fail` (Phase 1/2 throughout)
**What:** Every `fail` message ends with the exact command the user should run to fix it.
**Example:**
```bash
# Source: scripts/preflight.sh line 302-304 (Phase 1)
fail "$tool resolves to $tool_path (outside asdf shims at $SHIM_DIR).
    Fix: ensure ${SHIM_DIR} precedes /usr/bin in PATH.
    Run: source ~/.karyon/shell-init.sh  (or open a new terminal)"
```
Phase 3 applications (from CONTEXT.md §specifics):
- `fail "kubectl context is <X>, expected k3d-hub-flux → run: kubectl config use-context k3d-hub-flux"`
- `fail "flux controllers did not reach Ready in 120s → kubectl -n flux-system get deploy,pod; flux logs"`
- `fail "flux-system Kustomization not Ready=True → flux get kustomizations flux-system; flux logs --kind=Kustomization"`

### Pattern 4: Destructive-Gated Bats Test (Phase 2 delete-clusters-01-cache.bats)
**What:** Live tests that mutate real cluster state require BOTH `KARYON_LIVE_TESTS=1` AND `KARYON_LIVE_TESTS_DESTRUCTIVE=1`. Mirrors `require_live_destructive()` from `tests/bats/test_helper.bash` lines 43-49.
**Example:**
```bash
# Source: tests/bats/delete-clusters-01-cache.bats (Phase 2 verbatim)
@test "CLU-06 (live/destructive): karyon/k3s-cuda image survives delete-clusters.sh" {
  require_live_destructive
  bash "${REPO_ROOT}/scripts/delete-clusters.sh" >/dev/null 2>&1 || true
  run bash -c "docker images karyon/k3s-cuda --format '{{.Repository}}' | grep -c '^karyon/k3s-cuda$'"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}
```
Phase 3 test follows the same shape — see §Code Examples below.

### Pattern 5: `set -euo pipefail` (Not `set -u`)
**What:** Phase 2 scripts use strict mode; Phase 1 preflight uses `set -u` only so all checks run before exit. Bootstrap-flux is imperative/mutating → `set -euo pipefail` per CONTEXT.md D-11 (specifically NOT `set -x` — token safety).

### Anti-Patterns to Avoid
- **`set -x` for debug tracing:** Would print `GITHUB_TOKEN=ghp_...` when the env var is expanded. Explicitly forbidden by D-11.
- **`echo "$GITHUB_TOKEN"`** anywhere, in any form (even via `info` / `pass`). Token never transits stdout/stderr.
- **`tee`/log-to-file** in v1. D-11 rejects sed-redaction wrappers; log-to-file would capture whatever flux prints, including any future change in flux's output that includes token-like material.
- **`--token-auth` as positional string**: Passed as flag with no value (i.e., `--token-auth` or `--token-auth=true`), not `--token-auth $GITHUB_TOKEN`. The flag is a boolean toggle; the token itself is read from `GITHUB_TOKEN` env var [CITED: https://fluxcd.io/flux/cmd/flux_bootstrap_github/].
- **Hand-committing kustomization.yaml before bootstrap** (D-deferred): flux's behavior with a pre-existing user-authored `kustomization.yaml` is not documented to be stable across versions.
- **Auto-switching kubectl context**: Rejected by D-06. Mutation hidden from the user is bad ergonomics.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Install flux CRDs, 4 controllers, GitRepository, Kustomization | Custom `kubectl apply` chain + manifest templating | `flux bootstrap github` | Flux CLI is the only supported bootstrap path; writes coordinated state across cluster + git + GitHub API in one atomic operation; handles upgrades on rerun [CITED: fluxcd.io/flux/cmd/flux_bootstrap_github/]. |
| PAT Secret population | `kubectl create secret generic flux-system ...` | `flux bootstrap --token-auth` | Flux writes `username`+`password` keys in the exact shape GitRepository expects [CITED: fluxcd.io/flux/components/source/gitrepositories/]; shape can change across flux versions. |
| Git init + push to GitHub | `git init && git remote add && git push` | `flux bootstrap github` handles it | CLI detects existing local tree, creates remote repo if missing (public per D-01), commits manifests, pushes to `main` — documented end-to-end [CITED: fluxcd.io/flux/installation/bootstrap/github/, "the bootstrap command pushes the Flux manifests to the GitHub repository"]. Script must NOT call `git remote add` or `git push` directly. |
| GitHub repo visibility / permissions | Pre-create repo via `gh repo create` | `flux bootstrap` with `--private=false` and `--personal` | Flux creates-or-reuses the repo with correct permissions for the PAT. No separate `gh` call needed. |
| Deployment readiness polling | Custom bash loop with `kubectl get deploy -o json` + jq | `kubectl wait --for=condition=Available` | Kubernetes-native, clean exit codes (0 success / 1 timeout or not-found), idiomatic [CITED: kubectl reference]. |
| Flux healthiness probe | Controller-by-controller deployment/pod inspection | `flux check` | Built-in health signal; checks CRDs, controller versions, RBAC, and pod status [CITED: fluxcd.io/flux/cmd/flux_check/]. |
| Kustomize patch-surface contract | Hand-writing `kubectl patch` overlays | `patches:` block inside `clusters/hub-flux/flux-system/kustomization.yaml` | Documented Flux customization idiom [CITED: fluxcd.io/flux/installation/configuration/bootstrap-customization/]; Kustomize parses, Kustomize-controller applies, reconciliation survives re-bootstrap. |
| Token redaction from logs | sed/awk pipeline wrapping `flux bootstrap` stdout | Script discipline: env var + no `set -x` + no `tee` | D-11 rejects the wrapper as heavyweight and output-breaking. Env vars are not visible in `ps auxww` (argv-only) — see Pitfall 1. |
| PAT-scope validation | curl/jq against GitHub API | Trust `flux bootstrap`'s error surface | D-08 explicit rejection. Keeps script offline-safe. Insufficient PAT scope surfaces as a clear flux error. |

**Key insight:** Phase 3's deliverable is thin wrapper-plus-verification; every heavy lift is owned by `flux bootstrap github`. The script's value is preflight gating, kubectl-context assertion, idempotency short-circuit, and post-bootstrap verification — NOT re-implementing any part of the flux bootstrap flow.

## Runtime State Inventory

> Phase 3 is greenfield (no rename/refactor/migration). Still, because `flux bootstrap` writes state across git, GitHub, and the cluster, the equivalent "where does state live" audit is important for the idempotency + teardown model.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | In-cluster Secret `flux-system/flux-system` on hub-flux — holds PAT as `username`+`password` keys [CITED: fluxcd.io/flux/components/source/gitrepositories/]. | None from Phase 3 — `flux bootstrap` populates; `k3d cluster delete hub-flux` wipes it. The Secret is ephemeral relative to the cluster lifecycle. |
| Live service config | GitHub repo `$GITHUB_OWNER/$GITHUB_REPO` + deploy key (or lack thereof when `--token-auth`) + the three committed files under `clusters/hub-flux/flux-system/`. | None from Phase 3 — committed files ARE the git-tracked state; they're supposed to be in the repo. PAT is NOT in git. |
| OS-registered state | None. bootstrap-flux.sh makes no systemd / launchd / cron / Windows Task Scheduler registrations. | None. |
| Secrets/env vars | `GITHUB_OWNER`, `GITHUB_REPO`, `GITHUB_TOKEN` in gitignored `.env` (Phase 1 D-09/D-12 already covers `.env` in `.gitignore`). | None from Phase 3. The .env contract is unchanged — Phase 3 only reads from it. |
| Build artifacts | None (no compiled packages; bash + YAML only). | None. |

**Teardown story (for Phase 5 `task destroy` → Phase 3's teardown leg):** `k3d cluster delete hub-flux` wipes the cluster including the in-cluster Secret. The GitHub repo + the committed `clusters/hub-flux/flux-system/` files persist (intentionally — rerunning `task rebuild` uses them). If the user ever needs a truly scorched-earth GitHub side, they manually `gh repo delete` — out of scope for `task rebuild`.

## Common Pitfalls

### Pitfall 1: `GITHUB_TOKEN` visible via `ps auxww` if passed as argv
**What goes wrong:** If the script does `flux bootstrap github --token "$GITHUB_TOKEN"` (hypothetical flag — not how flux works) or `echo "$GITHUB_TOKEN" | flux bootstrap github` without care, the token can appear in process-listing output visible to any user.
**Why it happens:** Unix process listings (`ps auxww`, `/proc/<pid>/cmdline`) default to showing argv, not environ. Command-line arguments are universally visible; environment variables are NOT shown by default (they require `ps e` or `/proc/<pid>/environ` with matching UID) [CITED: https://github.com/fluxcd/flux2/issues/2011 discusses this exact concern].
**How to avoid:**
1. Export `GITHUB_TOKEN` via `set -a; source .env; set +a` pattern (or `export $(grep -v '^#' .env | xargs)` — choose whichever is shellcheck-clean).
2. Invoke `flux bootstrap github` with the flag `--token-auth` (boolean toggle, no value) and let the CLI consume `GITHUB_TOKEN` from the environment [CITED: fluxcd.io/flux/installation/bootstrap/github/ "The GitHub PAT can be exported as an environment variable"].
3. Do NOT use `echo "$TOKEN" | flux bootstrap`. Avoids the possible race of the `echo` argv being briefly visible.
4. Do NOT use `set -x`; D-11 forbids it explicitly.
**Warning signs:** Any script edit that quotes `$GITHUB_TOKEN` after a flag (other than the env var re-export at invocation). Code review grep: `grep -n 'GITHUB_TOKEN' scripts/bootstrap-flux.sh` should show only the source/export and the `GITHUB_TOKEN="$GITHUB_TOKEN"` env-scoped pass-through.

### Pitfall 2: `--path` change creates a divergent cluster commit (FLUX-02 rationale)
**What goes wrong:** If a future developer bumps `--path` from `clusters/hub-flux` to something else (e.g., `clusters/hub`), flux will create a new, second self-managed tree — the old one becomes orphaned, and the new GitRepository/Kustomization resources in-cluster point at the new path. The cluster ends up reconciling from both, or (more commonly) the user notices only after drift + loses history.
**Why it happens:** `flux bootstrap` treats `--path` as the canonical location for `gotk-*.yaml`; it does not migrate old paths. This is mentioned in ROADMAP §Phase 3 Success #4 and is the core FLUX-02 rationale.
**How to avoid:** Hard-code `--path clusters/hub-flux` in bootstrap-flux.sh as a constant. **Do not accept an env-var override.** Do not parameterize. Document the immutability claim in `docs/flux-hub-spoke.md` Rule 3.
**Warning signs:** Any PR that introduces a `FLUX_PATH="${FLUX_PATH:-clusters/hub-flux}"` or similar. Code review must reject.

### Pitfall 3: `flux bootstrap` rerun WILL overwrite user edits OUTSIDE `kustomization.yaml`
**What goes wrong:** Hand-edits to `gotk-components.yaml` or `gotk-sync.yaml` (e.g., bumping a controller's memory limit in the Deployment directly) are silently reverted on the next `flux bootstrap` run.
**Why it happens:** `flux bootstrap` re-renders `gotk-components.yaml` and `gotk-sync.yaml` from CLI flags; it does NOT parse user modifications. Any customization belongs in `kustomization.yaml` `patches:` [CITED: https://fluxcd.io/flux/installation/configuration/bootstrap-customization/].
**How to avoid:** Prominent in-file warning — this IS the Phase 3 D-13 comment block. Also rule 1 of `docs/flux-hub-spoke.md`.
**Warning signs:** A PR edits `gotk-*.yaml` directly. CODEOWNERS (Phase 6) may add a guard.

### Pitfall 4: `kubectl wait --for=condition=Available deploy --all` on empty namespace exits 0 immediately
**What goes wrong:** If the bootstrap failed silently before creating any Deployments in `flux-system`, `kubectl wait --for=condition=Available deploy --all --timeout=120s -n flux-system` returns immediately with exit 0 (waits for an empty set, trivially satisfied).
**Why it happens:** `--all` selects all resources of the given type in the namespace; if 0 exist, the predicate is vacuously true. Documented kubectl behavior [CITED: kubectl wait reference].
**How to avoid:** Precede the `kubectl wait` with an explicit count check: `[[ $(kubectl -n flux-system get deploy --no-headers 2>/dev/null | wc -l) -eq 4 ]] || fail "expected 4 flux controllers, found X"`. Keeps D-09 gate 2 honest.
**Warning signs:** Post-bootstrap "verification passes" but `kubectl -n flux-system get deploy` shows nothing.

### Pitfall 5: `grep -c Ready` matches `NotReady` substring
**What goes wrong:** Phase 2's CLU-02/CLU-04 bats tests hit this bug (captured in 02-VERIFICATION.md BLOCKER-01 / anti-patterns table); counts `NotReady` as `Ready`. Phase 3 has parallel risk if it matches flux controller status by substring.
**Why it happens:** `grep -c Ready` counts lines containing "Ready" — which "NotReady" also contains.
**How to avoid:** Use exact-column matching: `awk '$2 == "Ready"'` or `grep -qE '[^t]Ready\b|^Ready\b'`, or better yet, rely on `kubectl wait` (doesn't use grep at all) and `flux get kustomizations flux-system --no-header | awk '{print $3}'` with exact-string match against `True`.
**Warning signs:** The idempotency bats test uses `grep -c Ready` against either `flux get` output or `kubectl get deploy`.

### Pitfall 6: **D-03 rationale is factually incorrect — but the decision is still defensible**
**What goes wrong:** The CONTEXT.md D-03 text says "k3d's flannel CNI does not enforce NetworkPolicies reliably." In 2026 this is wrong: k3s ships with an embedded kube-router netpol controller that DOES enforce NetworkPolicies on top of flannel. k3d (which just runs k3s in docker) inherits this — NetworkPolicies on a default k3d cluster are enforced. [CITED: https://docs.k3s.io/networking/networking-services — "K3s includes an embedded network policy controller. The underlying implementation is kube-router's netpol controller library."] [CITED: https://www.suse.com/c/rancher_blog/k3s-network-policy/]
**Why it happens:** Older docs (and mental models from Kind + pure-flannel days) claimed flannel has no netpol enforcement. That was true of bare flannel; k3s explicitly closes the gap with kube-router's library.
**How to avoid:** Keep `--network-policy=false` (the decision stands), but **update the rationale** to accurate grounds:
> "The lab has no adversarial namespace boundary (single-user, single-tenant GPU/GitOps lab). The `flux-system` default deny-all NetworkPolicy adds debug surface ('why is reconcile failing?') with no real security benefit at this scope. Security is maintained by public-repo posture + gitignored .env + Phase 6 gitleaks, not by cluster-internal NetworkPolicies."
This is a plan-input-level finding: the planner should note the rationale update, and the discuss-phase artifact (03-DISCUSSION-LOG.md) may optionally be appended with a post-hoc correction note. The `--network-policy=false` flag value itself does not change.
**Warning signs:** Anyone claiming "we need network policies for security" on this lab — they're correct that k3s CAN enforce them, but wrong that we NEED them here.

### Pitfall 7: PAT without `repo` scope produces late/unclear failure
**What goes wrong:** If the PAT has only `public_repo` or missing scopes, `flux bootstrap github` fails when trying to create the repo or push, after partial work on the cluster (CRDs may have been applied). User sees a 404/403 from GitHub, not an offline-verifiable error.
**Why it happens:** D-08 explicitly rejects a pre-flight PAT-scope API probe (trade-off: offline-safe vs. better error locality). Classic PAT needs full `repo` scope for private repos; for public repos with `--private=false`, `public_repo` MIGHT suffice but fine-grained PATs needing Administration read+write + Contents read+write are the documented fine-grained path [CITED: fluxcd/flux2 discussion #4163].
**How to avoid:** `docs/flux-hub-spoke.md` (or `.env.example` comment) states "classic PAT with `repo` scope" unambiguously. Phase 1 `.env.example` D-11 already has this comment — verify it's still there.
**Warning signs:** User runs bootstrap-flux; sees a late error from GitHub. The error comes from flux, not our script. This is the intended surface per D-08.

### Pitfall 8: Stale CoreDNS on hub-flux after Docker/WSL restart
**What goes wrong:** If the hub-flux cluster was created before the most recent WSL/Docker restart, CoreDNS may have cached stale `NodeHosts` for `k3d-hub-flux-server-0`, breaking hub↔GitHub resolution via the bridge DNS.
**Why it happens:** Known k3d issue (#1009/#1112) referenced in PROJECT.md. Phase 5 ships `task fix-dns`.
**How to avoid:** Not Phase 3's problem — Phase 3 runs ONE bootstrap; if DNS is broken, `flux bootstrap` fails at push-time with a network error. Fix is `task fix-dns` (Phase 5). Phase 3 docs may mention this as a Phase 5 link.
**Warning signs:** `flux bootstrap` hangs during remote git push.

### Pitfall 9: `kustomization.yaml` comment-block survives re-bootstrap (validate, don't assume)
**What goes wrong:** Empirical claim: hand-added comments in `clusters/hub-flux/flux-system/kustomization.yaml` survive `flux bootstrap` rerun because flux reconciles the bootstrap-generated `resources:` list (and any user `patches:`) but does not re-render the file itself if the `resources:` list is already correct.
**Why it happens:** `flux bootstrap` "only creates a commit if the files in Git have diverged" [CITED: WebSearch result from fluxcd/flux2 discussions]. However, the Flux docs are silent on the exact behavior when `kustomization.yaml` has top-of-file comments plus a correct `resources:` list. There is no authoritative docs page on comment-preservation. [ASSUMED: comments are preserved because YAML parsers in flux bootstrap read the structured content, not comments; rewrite-if-diverged should include only diffs of structured content.]
**How to avoid:** Idempotency bats test (D-12) MUST exercise this: run bootstrap twice, confirm the sentinel comment is still present in the file after run 2. This converts the assumption into a validated invariant.
**Warning signs:** Run-2 of the idempotency bats test fails because the comment is gone. If so, fall back to "hand-commit once" (Claude's Discretion alternative) and trust reconciliation — but that's only if research is wrong here.

### Pitfall 10: Phase 6 gitleaks not installed → first git push leaks PAT
**What goes wrong:** If the user runs bootstrap-flux.sh before Phase 6 installs gitleaks, and somehow the PAT ends up in a commit (shouldn't happen via flux bootstrap — PAT goes to cluster Secret, not git — but a developer might paste it into `.env` then commit `.env` accidentally), the first push on a public repo leaks the token.
**Why it happens:** Ordering risk flagged in ROADMAP §Phase 3 parallelization note.
**How to avoid:** Phase 6 gitleaks pre-commit must land before first `git push`. CONTEXT.md Claude's Discretion recommendation: bootstrap-flux.sh emits a **warn** (non-fatal) if `.git/hooks/pre-commit` does not reference `gitleaks`. One-liner grep:
```bash
if ! grep -qF "gitleaks" .git/hooks/pre-commit 2>/dev/null; then
  warn "gitleaks pre-commit not detected (.git/hooks/pre-commit does not reference 'gitleaks').
    Phase 6 REPO-04 installs this hook; until then your first 'git push' is not protected.
    Fix: complete Phase 6 REPO-04 (scripts/install-tools.sh installs the hook) before 'git push'."
fi
```
**Warning signs:** The user runs bootstrap-flux.sh on a fresh clone where Phase 6 hasn't run. This is WHY we warn.

## Code Examples

### Example 1: bootstrap-flux.sh Skeleton (recommended structure)
```bash
#!/usr/bin/env bash
# scripts/bootstrap-flux.sh
# Runs `flux bootstrap github` on k3d-hub-flux with --path locked to
# clusters/hub-flux (REQ-FLUX-02 — effectively immutable after first run).
# Sources GITHUB_OWNER / GITHUB_REPO / GITHUB_TOKEN from the gitignored .env
# (REQ-FLUX-03). The token is never echoed to stdout.
#
# Idempotency (D-07, REQ-FLUX-04): skip if ns+check+controllers all healthy.
# Verification (D-09): flux check + kubectl wait + flux get kustomizations.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/preflight-lib.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/preflight-lib.sh"

# Constants — --path is hard-coded per FLUX-02 / D-decisions; do not parameterize.
readonly FLUX_PATH="clusters/hub-flux"
readonly KUBE_CTX="k3d-hub-flux"
readonly FLUX_NS="flux-system"
readonly KUST_FILE="${REPO_ROOT}/${FLUX_PATH}/${FLUX_NS}/kustomization.yaml"

# ---------- Section 1: Preflight gate (D-05) ----------
section "Preflight gate"
if ! bash "${SCRIPT_DIR}/preflight.sh" > /tmp/preflight-$$.log 2>&1; then
  fail "preflight has blockers — run scripts/preflight.sh and fix.
    Log: /tmp/preflight-$$.log"
  exit 1
fi
pass "preflight green"
rm -f /tmp/preflight-$$.log

# ---------- Section 2: Context + idempotency checks (D-06, D-07) ----------
section "Context + idempotency checks"

# D-06: kubectl context gate (fail with remediation; no auto-switch)
ctx="$(kubectl config current-context 2>/dev/null || true)"
if [[ "$ctx" != "$KUBE_CTX" ]]; then
  fail "kubectl context is ${ctx:-unset}, expected ${KUBE_CTX}.
    Fix: kubectl config use-context ${KUBE_CTX}"
  exit 1
fi
pass "kubectl context: ${KUBE_CTX}"

# D-07: 3-part idempotency AND
ns_ok=0; check_ok=0; ctrl_ok=0
kubectl --context "$KUBE_CTX" get ns "$FLUX_NS" >/dev/null 2>&1 && ns_ok=1
flux --context "$KUBE_CTX" check >/dev/null 2>&1 && check_ok=1
# Count controllers where .status.conditions[?(@.type=="Available")].status == "True"
ctrl_ready=$(kubectl --context "$KUBE_CTX" -n "$FLUX_NS" get deploy \
  -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Available")].status}{"\n"}{end}' 2>/dev/null \
  | grep -cx "True" || true)
[[ "$ctrl_ready" -eq 4 ]] && ctrl_ok=1

if [[ $ns_ok -eq 1 && $check_ok -eq 1 && $ctrl_ok -eq 1 ]]; then
  info "already done, skipping: flux bootstrap (ns=present, flux check=ok, 4 controllers Available)"
  # Section 5 still runs — patch-surface marker is idempotent, cheap, and must survive
  # skip-path too (otherwise a first-run-pre-D13 cluster would never get the marker).
  # ...jump to Section 5...
else
  # ---------- Section 3: flux bootstrap github ----------
  section "flux bootstrap"
  # Load .env into environment (NOT stdout). Fail if missing (preflight already checked).
  set -a
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/.env"
  set +a

  # NOTE: GITHUB_TOKEN is re-exported explicitly into the flux process env.
  # It does NOT appear in `ps auxww` (argv only shows --owner/--repository/etc.).
  GITHUB_TOKEN="$GITHUB_TOKEN" flux bootstrap github \
    --owner "$GITHUB_OWNER" \
    --repository "$GITHUB_REPO" \
    --path "$FLUX_PATH" \
    --personal \
    --private=false \
    --network-policy=false \
    --token-auth \
    --branch main
  pass "flux bootstrap complete"

  # ---------- Section 4: Post-bootstrap verification (D-09) ----------
  section "Post-bootstrap verification"

  # Gate 1: flux check
  if ! flux --context "$KUBE_CTX" check >/dev/null 2>&1; then
    fail "flux check failed after bootstrap.
      Inspect: flux --context ${KUBE_CTX} check"
    exit 1
  fi
  pass "flux check: ok"

  # Gate 2: controllers Available within 120s (D-10)
  # Guard against empty-namespace-exits-0 (Pitfall 4): assert 4 deployments first.
  n_deploy=$(kubectl --context "$KUBE_CTX" -n "$FLUX_NS" get deploy --no-headers 2>/dev/null | wc -l)
  if [[ "$n_deploy" -ne 4 ]]; then
    fail "expected 4 flux controllers, found ${n_deploy} — bootstrap did not complete.
      Inspect: kubectl --context ${KUBE_CTX} -n ${FLUX_NS} get deploy"
    exit 1
  fi
  if ! kubectl --context "$KUBE_CTX" -n "$FLUX_NS" wait \
      --for=condition=Available deploy --all --timeout=120s >/dev/null 2>&1; then
    fail "flux controllers did not reach Ready in 120s.
      Inspect: kubectl --context ${KUBE_CTX} -n ${FLUX_NS} get deploy,pod
      Logs:    flux --context ${KUBE_CTX} logs"
    exit 1
  fi
  pass "4 controllers Available within 120s"

  # Gate 3: flux-system Kustomization Ready=True
  ready=$(flux --context "$KUBE_CTX" get kustomizations "$FLUX_NS" --no-header 2>/dev/null \
    | awk '{print $3}')  # column layout: NAME REVISION READY ... (verify with --no-header exactly)
  if [[ "$ready" != "True" ]]; then
    fail "flux-system Kustomization not Ready=True (got: ${ready:-unknown}).
      Inspect: flux --context ${KUBE_CTX} get kustomizations ${FLUX_NS}
      Logs:    flux --context ${KUBE_CTX} logs --kind=Kustomization"
    exit 1
  fi
  pass "Kustomization flux-system: Ready=True"
fi

# ---------- Section 5: Patch-surface marker (D-13) ----------
section "Patch-surface marker"
SENTINEL="# FLUX PATCH SURFACE"
if [[ ! -f "$KUST_FILE" ]]; then
  fail "expected ${KUST_FILE} missing — flux bootstrap did not commit it?
    Inspect: ls -la ${REPO_ROOT}/${FLUX_PATH}/${FLUX_NS}/"
  exit 1
fi
if grep -qF "$SENTINEL" "$KUST_FILE"; then
  info "already done, skipping: patch-surface marker"
else
  tmp=$(mktemp)
  {
    cat <<'EOF'
# ──────────────────────────────────────────────────────────────────────────
# FLUX PATCH SURFACE
#
# This file IS the supported patch surface for the hub-flux bootstrap.
# Edits here SURVIVE re-bootstrap — add `patches:`, `configMapGenerator:`,
# `images:` etc. here to customize the 4 core controllers.
#
# Peer files in this directory — gotk-components.yaml, gotk-sync.yaml —
# are bootstrap-managed and WILL be overwritten by `flux bootstrap`.
# Do NOT hand-edit them.
#
# See: docs/flux-hub-spoke.md
# ──────────────────────────────────────────────────────────────────────────
EOF
    cat "$KUST_FILE"
  } > "$tmp"
  mv "$tmp" "$KUST_FILE"
  pass "applied: patch-surface marker to ${KUST_FILE}"
fi

# ---------- Optional: Phase-6 hook warn (non-fatal) ----------
section "Phase 6 hook advisory"
if [[ -f "${REPO_ROOT}/.git/hooks/pre-commit" ]] && grep -qF "gitleaks" "${REPO_ROOT}/.git/hooks/pre-commit"; then
  pass "gitleaks pre-commit detected"
else
  warn "gitleaks pre-commit not detected (.git/hooks/pre-commit does not reference 'gitleaks').
    Phase 6 REPO-04 installs this hook; until then your first 'git push' is not protected.
    Fix: complete Phase 6 REPO-04 (install-tools.sh installs the hook) before 'git push'."
fi

# ---------- Summary ----------
section "Summary"
printf "  %s%d passed%s, %s%d warnings%s, %s%d failed%s\n" \
  "$C_GREEN" "$PASS" "$C_RESET" "$C_YELLOW" "$WARN" "$C_RESET" "$C_RED" "$FAIL" "$C_RESET"
if (( FAIL > 0 )); then exit 1; fi
printf "\n%shub-flux is now self-managing via GitOps.%s\n" "$C_GREEN" "$C_RESET"
```

*Note for planner:* The `flux get kustomizations flux-system` column layout (gate 3) must be verified — the column order can be NAME REVISION SUSPENDED READY MESSAGE, which would put READY at column 4, not column 3. Planner should verify via `flux get kustomizations flux-system --no-header` output shape before freezing the awk field index. Safer alternative: `kubectl get kustomization flux-system -n flux-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'`.

### Example 2: D-15 Patch Example for docs/flux-hub-spoke.md
```yaml
# clusters/hub-flux/flux-system/kustomization.yaml
# (after top-of-file FLUX PATCH SURFACE comment block)
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - gotk-components.yaml
  - gotk-sync.yaml
patches:
  - target:
      kind: Deployment
      name: kustomize-controller
      namespace: flux-system
    patch: |
      - op: replace
        path: /spec/template/spec/containers/0/resources/limits/memory
        value: 1Gi
```
[CITED: https://fluxcd.io/flux/installation/configuration/bootstrap-customization/ — general `patches:` schema, though concrete memory-limit example is reconstructed from the flux docs pattern].

### Example 3: Idempotency Bats Test Skeleton (D-12)
```bash
#!/usr/bin/env bats
# tests/bats/bootstrap-flux-01-idempotent.bats
# Two-part check (FLUX-04 / D-12):
#   (a) static grep that bootstrap-flux.sh contains the expected skip-message literal
#   (b) L4 destructive-gated test: run script twice, assert second invocation is no-op
# Phase 2 pattern source: tests/bats/delete-clusters-01-cache.bats

load 'test_helper'

setup() {
  SCRIPT="${REPO_ROOT}/scripts/bootstrap-flux.sh"
}

@test "FLUX-04: bootstrap-flux.sh contains the 'already done, skipping: flux bootstrap' skip message" {
  run grep -F "already done, skipping: flux bootstrap" "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "FLUX-04: bootstrap-flux.sh uses set -euo pipefail (not set -x; D-11 token safety)" {
  run grep -Fq "set -euo pipefail" "$SCRIPT"
  [ "$status" -eq 0 ]
  # Must not contain bare `set -x` (active trace mode)
  run grep -E '^[[:space:]]*set[[:space:]]+-x\b' "$SCRIPT"
  [ "$status" -ne 0 ]
}

@test "FLUX-02: bootstrap-flux.sh hard-codes --path clusters/hub-flux (no env override)" {
  run grep -F "clusters/hub-flux" "$SCRIPT"
  [ "$status" -eq 0 ]
  # Must NOT accept an env-var override (e.g., no FLUX_PATH="${FLUX_PATH:-...}" pattern)
  run grep -E 'FLUX_PATH=\"\$\{FLUX_PATH:?-' "$SCRIPT"
  [ "$status" -ne 0 ]
}

# WARNING: This live test runs scripts/bootstrap-flux.sh against the hub-flux
# cluster, creates/updates the GitHub repo, and writes files under
# clusters/hub-flux/flux-system/. Requires BOTH KARYON_LIVE_TESTS=1 AND
# KARYON_LIVE_TESTS_DESTRUCTIVE=1. Requires .env with valid GITHUB_TOKEN.
@test "FLUX-04 (live/destructive): bootstrap-flux.sh second run is no-op" {
  require_live_destructive

  # First run: ensures bootstrap has landed (may or may not be a no-op — we don't care).
  bash "${SCRIPT}" >/dev/null 2>&1

  # Second run: MUST hit the idempotency skip path.
  run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  # Exact skip-message literal must appear in stdout
  [[ "$output" == *"already done, skipping: flux bootstrap"* ]]
}

@test "FLUX-04 (live/destructive): D-13 patch-surface marker survives second run" {
  require_live_destructive
  KUST="${REPO_ROOT}/clusters/hub-flux/flux-system/kustomization.yaml"
  # After the double-run in the prior test, kustomization.yaml must still contain the sentinel.
  [ -f "$KUST" ]
  run grep -qF "# FLUX PATCH SURFACE" "$KUST"
  [ "$status" -eq 0 ]
}

@test "FLUX-03 (token safety): bootstrap-flux.sh never echoes \$GITHUB_TOKEN" {
  # Static: script must not contain `echo "$GITHUB_TOKEN"` or `echo $GITHUB_TOKEN` patterns.
  run grep -E 'echo[[:space:]]+(\"?)\$GITHUB_TOKEN' "$SCRIPT"
  [ "$status" -ne 0 ]
  # Static: no `tee` pipe capturing bootstrap output (D-11)
  run grep -E 'flux[[:space:]]+bootstrap[[:space:]]+github.*\|[[:space:]]*tee' "$SCRIPT"
  [ "$status" -ne 0 ]
}
```

### Example 4: docs/flux-hub-spoke.md Section Skeleton (Phase 3 scope only)
```markdown
# Flux Hub-Spoke Patch Surface

## What `flux bootstrap` writes

On first invocation, `scripts/bootstrap-flux.sh` runs `flux bootstrap github --path clusters/hub-flux`, which commits three files under `clusters/hub-flux/flux-system/`:

| File | Category | Hand-edit? |
|------|----------|------------|
| `gotk-components.yaml` | bootstrap-managed | NO |
| `gotk-sync.yaml` | bootstrap-managed | NO |
| `kustomization.yaml` | **patch surface** | **YES — this is the supported edit point** |

## Rule 1: `gotk-components.yaml` + `gotk-sync.yaml` are bootstrap-managed

Do not hand-edit these files. `flux bootstrap` re-renders them from CLI flags on every run;
any hand-edits are silently reverted. If you need to change controller behavior, see Rule 2.

## Rule 2: `kustomization.yaml` IS the supported patch surface

Edits inside `kustomization.yaml` — `patches:`, `configMapGenerator:`, `images:` — survive
re-bootstrap, because `flux bootstrap` only updates the file when its `resources:` block
diverges from what the current flag set would produce. The top-of-file comment block is
also preserved.

Example — bump `kustomize-controller` memory limit:

\`\`\`yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - gotk-components.yaml
  - gotk-sync.yaml
patches:
  - target:
      kind: Deployment
      name: kustomize-controller
      namespace: flux-system
    patch: |
      - op: replace
        path: /spec/template/spec/containers/0/resources/limits/memory
        value: 1Gi
\`\`\`

To prove this patch survives re-bootstrap: run `bash scripts/bootstrap-flux.sh`;
then `kubectl -n flux-system get deploy kustomize-controller -o jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}'` should report `1Gi`.

## Rule 3: `--path` is effectively immutable after first run

Changing `--path` (currently `clusters/hub-flux` — hard-coded in `scripts/bootstrap-flux.sh`)
produces a divergent bootstrap commit: the old path's `flux-system/` tree is orphaned, and
the cluster starts reconciling from the new tree. There is no migration path. Treat the
initial `--path` as a locked decision.

## Rerun behavior

Rerunning `scripts/bootstrap-flux.sh` on an already-bootstrapped hub logs
`already done, skipping: flux bootstrap` and exits 0 without re-invoking `flux bootstrap`.

<!-- Phase 4: hub-spoke reconciliation (spec.kubeConfig, <spoke>-kubeconfig Secrets, value.yaml key) -->
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `flux install` + manual git wiring | `flux bootstrap github` (CLI-driven end-to-end) | Flux v2 GA (2022) | Single-command bootstrap owns both repo creation and cluster install; Phase 3 relies on this. |
| SSH deploy-key (default) | `--token-auth` for HTTPS + PAT | Post-v2.0 — not a flux policy change, but matches our public-repo + `.env` posture | No deploy-key lifecycle management in our scripts. |
| v1beta2 / v2beta2 CRDs | v1 CRDs | flux v2.8.0 (deprecated CRDs removed) | [CITED: v2.8 breaking change] — not relevant to Phase 3 since bootstrap auto-installs current CRDs, but informs Phase 4 Kustomization spec version. |
| NetworkPolicy not enforced on k3s default | kube-router netpol controller embedded in k3s | k3s adoption (not a change — just a docs-gap that caught D-03 rationale) | See Pitfall 6. |

**Deprecated/outdated:**
- `flux bootstrap --private` default was `true`. Phase 3 explicitly sets `false` per D-01 (public repo).
- Older docs talked about manual `sync.Generate()` output tweaking pre-commit — deprecated in favor of `kustomization.yaml patches:`.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Top-of-file comments in `kustomization.yaml` survive `flux bootstrap` rerun | Pitfall 9; D-13 | If comments get rewritten, the patch-surface marker vanishes on rerun — but the idempotency bats test (Example 3) catches this immediately. Fallback: reapply in Section 5 (which is already idempotent; re-runs in both code-paths handle this). |
| A2 | `flux get kustomizations` output column 3 is READY | Example 1 Gate 3 | If column order is different (SUSPENDED often precedes READY in `flux` 2.x), the awk field index is wrong. Safer alternative in planner notes (use kubectl jsonpath). |
| A3 | `flux bootstrap github --token-auth` consumes `GITHUB_TOKEN` env var automatically; no `--token-auth=<value>` or stdin required | §Architecture, §Don't Hand-Roll | Verified by [CITED: fluxcd.io/flux/installation/bootstrap/github/ "export GITHUB_TOKEN=..."]. If flux 2.8.6 changed this, the invocation would hang at a TTY prompt in non-interactive use. Detectable: CI run would block. |
| A4 | `kubectl wait --for=condition=Available deploy --all` on an empty namespace exits 0 (waits for empty set) | Pitfall 4 | Multiple sources confirm; kubectl behavior. Guard via explicit deploy-count precheck in Example 1. |
| A5 | GitHub classic PAT with `repo` scope is sufficient for `--private=false` + `--personal` bootstrap | §User Constraints D-02 | If GitHub has deprecated classic PATs or raised scope requirements, bootstrap fails at GitHub API call. Clear error; user rotates to fine-grained PAT with Contents R/W + Administration R/W. |
| A6 | Phase 2's `require_live_destructive()` double-gate is the canonical pattern for Phase 3 idempotency test | Pattern 4, Example 3 | Verified by `tests/bats/test_helper.bash` lines 43-49; used by `delete-clusters-01-cache.bats`. |
| A7 | k3d's `k3d-hub-flux` kubectl context is written to the user's kubeconfig by Phase 2's `scripts/create-clusters.sh` (k3d default behavior) | CONTEXT.md §Integration Points | Verified by Phase 2 VERIFICATION.md success criteria #2 + Plan 02-05 checkpoint (3 clusters Ready). |
| A8 | D-03 rationale ("flannel does not enforce NPs") is factually incorrect; the decision value (`--network-policy=false`) is still correct on different grounds | Pitfall 6, §Open Questions | High-confidence — multiple authoritative sources (k3s docs, SUSE Rancher blog). Planner should surface this as a rationale-text edit, not a decision reversal. |

## Open Questions (Claude's Discretion — Resolved)

Every open question from CONTEXT.md §Claude's Discretion, resolved by this research:

1. **`GITHUB_TOKEN` passing mechanism** → **Env var `GITHUB_TOKEN=... flux bootstrap github --token-auth ...`**. Safe from `ps auxww` because env vars are argv-distinct. No stdin pipe needed. `--token-auth` is a boolean toggle; no `--token-file` flag exists. [CITED: fluxcd.io/flux/installation/bootstrap/github/, GitHub issue #2011]
2. **Where D-13 augmentation happens** → **Inline in `scripts/bootstrap-flux.sh` Section 5** (sentinel-guarded awk prepend). Survives any future `flux bootstrap` re-render because our script always runs after the bootstrap step. Matches CONTEXT.md guidance.
3. **`flux bootstrap` idempotency on healthy cluster** → **Safe — docs describe rerun as "will perform an upgrade if needed"; files only recommitted when content has diverged.** [CITED: fluxcd.io/flux/cmd/flux_bootstrap_github/]. The D-07 three-gate skip is a safe fast-path AND saves time (our script short-circuits before flux CLI even runs).
4. **`flux check` exit code contract** → **Exit 0 = all default components (source-controller, kustomize-controller, helm-controller, notification-controller) healthy and CRDs/RBAC correct; non-zero = any check failed.** [CITED: fluxcd.io/flux/cmd/flux_check/]. D-07 gate 2 uses this directly.
5. **`kubectl wait` behavior** → **Exit 0 on all matching deployments Available, exit 1 on timeout, exit 1 on not-found. `--all` on empty namespace exits 0 (Pitfall 4).** 120s is ample on a fresh k3d cluster — the 4 flux controllers are lightweight (resource-limit-constrained to < 100Mi RAM each by default) and start in 15–30s on first bootstrap.
6. **NetworkPolicy on k3d flannel** → **k3s HAS netpol enforcement via embedded kube-router; Pitfall 6. D-03 value correct, D-03 rationale needs wording fix.**
7. **`flux bootstrap` remote git round-trip** → **Yes, end-to-end.** The CLI creates the GitHub repo if missing, commits manifests, pushes to the branch, and handles the auth setup (deploy key for SSH, or PAT Secret for `--token-auth`). Bootstrap-flux.sh does NOT need to run `git remote add` or `git push`. [CITED: "the bootstrap command pushes the Flux manifests to the GitHub repository"]
8. **In-cluster PAT Secret** → **`flux-system/flux-system` (Secret name = `flux-system` in the `flux-system` namespace).** Keys: `username` and `password` (HTTPS basic-auth shape, where password is the PAT) [CITED: fluxcd.io/flux/components/source/gitrepositories/ + fluxcd/flux2 discussion #4163]. Document this in `docs/flux-hub-spoke.md` only if needed — CONTEXT.md §code_context already mentions the Secret; planner can decide to include or omit specific key names.
9. **Bats test gate pattern** → **`require_live_destructive()` double-gate** (`KARYON_LIVE_TESTS=1 KARYON_LIVE_TESTS_DESTRUCTIVE=1`). Phase 2 `delete-clusters-01-cache.bats` is the canonical shape; Example 3 above mirrors it verbatim.
10. **Gitleaks pre-commit detection** → **`grep -qF "gitleaks" .git/hooks/pre-commit`** (warn-only if missing). Cheapest; no dependency on gitleaks binary being installed (only checks that the hook references it).

**Remaining "planner's pick" items** (after research, still implementation taste, not correctness):
- **`--author-name` / `--author-email`** → **Omit both**; let flux use its defaults (`flux-bootstrap` commits as the PAT-authenticated user on GitHub). Single-author lab; no real scope issue. Planner may elect to read from `git config user.email` if consistency with other project commits matters.
- **`--branch main`** → **Pass explicitly** (belt-and-suspenders). Repo is already on main; no edge case.
- **`--cluster-domain`** → **Omit**; default `cluster.local` is correct for k3d.
- **Re-asserting `flux version` in bootstrap-flux.sh** → **Omit**; preflight covers PRE-05 already.
- **`docs/flux-hub-spoke.md` TOC** → **Keep flat.** Four short sections; TOC adds noise.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| flux CLI | SECTION 3 (flux bootstrap) + SECTION 4 gates 1+3 | ✓ (preflight PRE-05 enforces) | 2.8.6 pinned in `.tool-versions` | — (preflight fails if missing) |
| kubectl | SECTIONS 2+4 | ✓ | 1.35.0 | — |
| k3d hub-flux cluster on :6443 | SECTION 2 context gate + ALL subsequent sections | ✓ after Phase 2 | k3d 5.8.3 / k3s v1.34.6-k3s1 | — (fail with remediation pointing at `scripts/create-clusters.sh`) |
| Docker | indirectly (k3d cluster is a docker container) | ✓ | 28.x / whatever install-docker.sh landed | — |
| `.env` with valid GITHUB_OWNER/REPO/TOKEN | SECTION 3 | depends on user | — | — (preflight PRE-09 fails if missing) |
| GitHub reachability + HTTPS egress | SECTION 3 | depends on network | — | — (flux bootstrap surfaces network error clearly; fail fast) |
| bats-core | tests/bats/bootstrap-flux-01-idempotent.bats | depends on CI/dev box | system | — (Phase 2 already ships bats harness; no Phase 3 install burden) |
| awk / sed / grep | SECTION 5 + bats | ✓ | system | — (POSIX, always present) |

**Missing dependencies with no fallback:** None for a fresh dev box that completed Phase 1+2. Phase 3 adds zero new dependencies.

**Missing dependencies with fallback:** None.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | bats-core (system install; used by Phase 1 + Phase 2) |
| Config file | `tests/bats/test_helper.bash` (shared loader; Phase 2 extended it with `require_live_destructive`) |
| Quick run command | `bats tests/bats/bootstrap-flux-01-idempotent.bats` (static-only, no live gate) |
| Full suite command | `KARYON_LIVE_TESTS=1 KARYON_LIVE_TESTS_DESTRUCTIVE=1 bats tests/bats/` (includes live destructive test) |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| FLUX-01 | `scripts/bootstrap-flux.sh` runs `flux bootstrap github` targeting hub-flux | static (existence + invocation grep) | `grep -F 'flux bootstrap github' scripts/bootstrap-flux.sh` | ❌ Wave 0 — `tests/bats/bootstrap-flux-01-idempotent.bats` (add @test for FLUX-01 static grep) |
| FLUX-02 | `--path clusters/hub-flux` hard-coded | static | see Example 3 test block for FLUX-02 | ❌ Wave 0 — same file |
| FLUX-03 | `GITHUB_TOKEN` never echoed | static | `grep -E 'echo[[:space:]]+(\"?)\$GITHUB_TOKEN' scripts/bootstrap-flux.sh` (must return non-zero) | ❌ Wave 0 — same file (token-safety @test in Example 3) |
| FLUX-04 | Rerun is no-op | live/destructive | `KARYON_LIVE_TESTS=1 KARYON_LIVE_TESTS_DESTRUCTIVE=1 bats tests/bats/bootstrap-flux-01-idempotent.bats` | ❌ Wave 0 — same file (live @test in Example 3) |
| FLUX-05 | `docs/flux-hub-spoke.md` documents 3 rules | static (docs grep) | `grep -cF 'bootstrap-managed' docs/flux-hub-spoke.md && grep -cF 'patch surface' docs/flux-hub-spoke.md && grep -cF 'immutable' docs/flux-hub-spoke.md` | ❌ Wave 0 — add `tests/bats/bootstrap-flux-02-docs.bats` |
| D-13 (patch marker) | comment block present in kustomization.yaml after bootstrap | static (live-dependent) + live | `grep -qF '# FLUX PATCH SURFACE' clusters/hub-flux/flux-system/kustomization.yaml` | ❌ Wave 0 — included in idempotency test per Example 3 |
| D-09 gate 3 (Kustomization Ready=True) | post-bootstrap invariant | manual / checkpoint | `flux --context k3d-hub-flux get kustomizations flux-system` | Runtime — script self-asserts this via Section 4 |

### Sampling Rate
- **Per task commit:** `bats tests/bats/bootstrap-flux-01-idempotent.bats tests/bats/bootstrap-flux-02-docs.bats` (static-only ~1s)
- **Per wave merge:** `bats tests/bats/` (all phases; static-only — destructive live gated) — matches Phase 2 convention
- **Phase gate:** Developer runs `KARYON_LIVE_TESTS=1 KARYON_LIVE_TESTS_DESTRUCTIVE=1 bats tests/bats/bootstrap-flux-01-idempotent.bats` on rich@Area-51 with valid `.env`, captures output in checkpoint artifact, then `/gsd-verify-work` consumes it.

### Wave 0 Gaps
- [ ] `tests/bats/bootstrap-flux-01-idempotent.bats` — covers FLUX-01/02/03/04 + D-13 live check
- [ ] `tests/bats/bootstrap-flux-02-docs.bats` — covers FLUX-05 (docs/flux-hub-spoke.md content grep)
- [ ] No new framework install needed — bats + test_helper.bash already in place.

**Happy path validation (full E2E, destructive):**
```bash
# 1. Dev box clean: no hub-flux cluster, no existing $GITHUB_OWNER/$GITHUB_REPO, fresh .env
# 2. Phase 2 stands up the clusters:
bash scripts/create-clusters.sh
# 3. Phase 3 bootstraps flux:
bash scripts/bootstrap-flux.sh
# Expected: 5 sections all pass; FAIL counter == 0; exit 0.
# Observable signal: "hub-flux is now self-managing via GitOps." printed.

# 4. Independent cluster-side verification:
kubectl --context k3d-hub-flux -n flux-system get deploy
# Expected: 4 Deployments all Available
flux --context k3d-hub-flux get kustomizations flux-system
# Expected: NAME=flux-system, READY=True
flux --context k3d-hub-flux check
# Expected: exit 0

# 5. Independent GitHub-side verification:
# Browser: https://github.com/$GITHUB_OWNER/$GITHUB_REPO
# Expected: public repo, main branch, clusters/hub-flux/flux-system/{gotk-components.yaml,gotk-sync.yaml,kustomization.yaml} present

# 6. Independent in-file verification:
head -12 clusters/hub-flux/flux-system/kustomization.yaml
# Expected: "# FLUX PATCH SURFACE" block at top
```

**Idempotency path (D-12 / FLUX-04):**
```bash
# After happy-path success above:
bash scripts/bootstrap-flux.sh
# Expected: Section 2 hits all 3 gates (ns/check/ctrl), logs
#   "already done, skipping: flux bootstrap"
# Expected: Section 5 hits the grep-sentinel check, logs
#   "already done, skipping: patch-surface marker"
# Expected: exit 0
# Observable signal: ZERO time spent in Section 3 (no `flux bootstrap github` invocation)
```

**Negative paths:**

| Failure Mode | How Triggered | Expected Observable | Test Layer |
|-------------|---------------|---------------------|------------|
| Wrong kubectl context | `kubectl config use-context some-other` + run bootstrap-flux | fail at Section 2 with "kubectl context is X, expected k3d-hub-flux → ..." | manual |
| Missing `.env` | `rm .env` + run bootstrap-flux | fail at Section 1 (preflight PRE-09 fail) | bats (preflight-pre09.bats already exists) |
| Empty `GITHUB_TOKEN` | Edit `.env` to blank the value | fail at Section 1 (preflight PRE-09) | bats (existing) |
| Insufficient PAT scope | Use a PAT with only `public_repo` on a private-repo path | fail at Section 3 with flux's 404/403 upstream error | manual (D-08 intentionally surfaces flux's error unchanged) |
| Offline / network fail during bootstrap | `sudo iptables -A OUTPUT -d github.com -j DROP` (or similar mid-run) | fail at Section 3 with network error; cluster may have CRDs installed but no GitRepository | manual (rare; script exits 1, user retries) |
| `flux check` fails post-bootstrap | Inject by `kubectl -n flux-system scale deploy source-controller --replicas=0` | fail at Section 4 gate 1 | manual |
| `kubectl wait` timeout at 120s | Inject same scale-to-0 | fail at Section 4 gate 2 with "controllers did not reach Ready in 120s" | manual |
| Kustomization never reaches Ready=True | Inject malformed `kustomization.yaml` (invalid patch target) | fail at Section 4 gate 3; `flux logs --kind=Kustomization` shows parse error | manual |
| D-11 token-leak probe | `bash scripts/bootstrap-flux.sh 2>&1 | grep -F "$(grep GITHUB_TOKEN .env | cut -d= -f2)"` | MUST return empty (no match). If any match, D-11 is violated — fail loudly. | manual (post-bootstrap one-shot) |

**Doc validation:**
```bash
# FLUX-05 grep triad
for rule in 'bootstrap-managed' 'patch surface' 'immutable'; do
  grep -qF "$rule" docs/flux-hub-spoke.md || echo "MISSING: $rule"
done
# Expected: no output (all three present)

# D-13 marker triad
grep -qF '# FLUX PATCH SURFACE' clusters/hub-flux/flux-system/kustomization.yaml || echo MISSING
grep -qF 'gotk-components.yaml' clusters/hub-flux/flux-system/kustomization.yaml || echo MISSING
# D-15 patch example
grep -qF 'kustomize-controller' docs/flux-hub-spoke.md || echo MISSING
grep -qF '1Gi' docs/flux-hub-spoke.md || echo MISSING
```

**Bats test validation (the test itself):**
```bash
bats tests/bats/bootstrap-flux-01-idempotent.bats --tap
# Expected (static-only, no live gate): 4 static tests pass, 2 live tests skip with the
# "destructive live test — set KARYON_LIVE_TESTS=1 KARYON_LIVE_TESTS_DESTRUCTIVE=1" message.
```

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | yes | GitHub PAT (classic, `repo` scope); stored only in gitignored `.env` + in-cluster Secret `flux-system/flux-system`. |
| V3 Session Management | no | No web/session surface in this phase. |
| V4 Access Control | yes (boundary) | kubectl context gate (D-06) prevents accidental bootstrap on the wrong cluster; `--path clusters/hub-flux` hard-coded prevents accidental cross-cluster overwrite. |
| V5 Input Validation | partial | Env vars validated at presence + non-empty (preflight PRE-09). No deeper validation (D-08 rejection). |
| V6 Cryptography | no (defer) | PAT is a bearer token; Flux handles HTTPS TLS to GitHub. SSH deploy-key path explicitly not used (`--token-auth`). No hand-rolled crypto. |
| V10 Malicious Code Protection | yes (indirect) | Phase 6 gitleaks pre-commit (REPO-04) prevents PAT leaking to git history. Phase 3 bootstrap-flux.sh emits a warn when the hook is not installed. |

### Known Threat Patterns for bash + flux + k3d + public git repo

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| PAT visible in `ps auxww` | Information Disclosure | Pass via `GITHUB_TOKEN` env var; never argv. See Pitfall 1. |
| PAT leaked to git history | Information Disclosure | `.env` gitignored (Phase 1 D-12) + gitleaks pre-commit (Phase 6 REPO-04) + bootstrap-flux.sh advisory warn when hook missing. |
| Accidental cross-cluster bootstrap | Tampering / Elevation | kubectl context gate (D-06) + hard-coded `--path` (FLUX-02). |
| Stale PAT continues to function | Elevation / Repudiation | PAT rotation is the user's responsibility; in-cluster Secret must be wiped on PAT rotation: `kubectl -n flux-system delete secret flux-system` then rerun bootstrap-flux.sh. Document in Phase 4/5 as needed; Phase 3 notes it in `docs/flux-hub-spoke.md` optional. |
| `set -x` trace leaking env values | Information Disclosure | Explicit `set -euo pipefail` + no `set -x` (D-11). Bats test asserts this. |
| Accidental public-repo push with secret in kustomization.yaml | Information Disclosure | Never write secrets into `clusters/hub-flux/**`. PAT lives in in-cluster Secret only (Flux's own write, not ours). Phase 4 spoke kubeconfigs are Secrets on the cluster, not committed — out of Phase 3 scope but relevant for consistency. |

## Sources

### Primary (HIGH confidence)
- `.planning/PROJECT.md` — Core value, Key Decisions table (Flux-over-ArgoCD, hub-only Flux, public repo + `.env` posture)
- `.planning/REQUIREMENTS.md` §Flux Hub Bootstrap (FLUX-01..05), §Documentation (DOCS-03)
- `.planning/ROADMAP.md` §Phase 3 — goal, 4 success criteria, LOW-risk notes, Phase 2/4/5/6 dependencies
- `.planning/phases/03-flux-hub-bootstrap/03-CONTEXT.md` — the Phase 3 locked decisions (D-01..D-16)
- `.planning/phases/02-cluster-layer/02-CONTEXT.md` — preflight-lib.sh delegation, section/pass/warn/fail vocabulary, destructive-test gate pattern
- `.planning/phases/02-cluster-layer/02-VERIFICATION.md` — verification template; anti-patterns to avoid (Pitfall 5)
- `scripts/preflight.sh` + `scripts/lib/preflight-lib.sh` — helpers Phase 3 sources verbatim
- `scripts/create-clusters.sh` + `scripts/delete-clusters.sh` — style references for Phase 3 script
- `tests/bats/test_helper.bash` + `tests/bats/delete-clusters-01-cache.bats` — destructive gate pattern
- `.tool-versions` — flux2 2.8.6 pin
- `Taskfile.yml` — Phase 2 stub (Phase 3 appends one entry)

### Secondary (MEDIUM confidence)
- `https://fluxcd.io/flux/installation/bootstrap/github/` — primary flux bootstrap docs
- `https://fluxcd.io/flux/cmd/flux_bootstrap_github/` — CLI reference
- `https://fluxcd.io/flux/cmd/flux_check/` — `flux check` reference
- `https://fluxcd.io/flux/installation/configuration/bootstrap-customization/` — patches: / resources: contract; kustomization.yaml as patch surface
- `https://fluxcd.io/flux/components/source/gitrepositories/` — GitRepository Secret shape (`username` + `password` for PAT)
- `https://github.com/fluxcd/flux2/releases/tag/v2.8.6` — v2.8.6 release notes (patch release; no bootstrap changes)
- `https://docs.k3s.io/networking/networking-services` — confirms k3s embedded kube-router netpol controller (informs Pitfall 6)
- `https://www.suse.com/c/rancher_blog/k3s-network-policy/` — second source on k3s network policy
- `https://github.com/fluxcd/flux2/issues/2011` — credential-exposure discussion (informs Pitfall 1 env-var vs argv)
- `https://github.com/fluxcd/flux2/discussions/4163` — community bootstrap-with-github approaches (PAT scope notes)

### Tertiary (LOW confidence)
- `https://oneuptime.com/blog/post/2026-03-05-flux-cd-bootstrap-process-internals/view` — corroborates bootstrap internals but not authoritative; used for cross-reference on idempotency language.
- `https://deepwiki.com/fluxcd/flux2/3.1-bootstrap-workflow-and-architecture` — same.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all pins verified against `.tool-versions` and flux GitHub releases; flux 2.8.6 is the current patch release as of 2026-04-21.
- Architecture: HIGH — 5-section script structure follows Phase 1+2 established patterns verbatim; every section maps to a locked CONTEXT.md decision.
- Pitfalls: MEDIUM — Pitfalls 1–5, 7, 10 are HIGH confidence; Pitfall 6 (D-03 rationale) is HIGH confidence as a correction; Pitfall 9 (kustomization.yaml comment preservation) is MEDIUM-LOW and converted to an Assumption (A1) with a bats-test harness to validate empirically.
- Validation architecture: HIGH — bats framework + `require_live_destructive()` already in place; only new test files needed.
- Security: HIGH — env-var approach for token safety is canonical Unix pattern; PAT-in-Secret is Flux's documented behavior.

**Research date:** 2026-04-24
**Valid until:** 2026-05-24 (30 days — flux2 is stable; next patch release may appear in this window but is unlikely to change the bootstrap flag surface per the v2.8.6 release-note pattern).
