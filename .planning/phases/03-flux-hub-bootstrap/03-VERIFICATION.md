---
phase: 03-flux-hub-bootstrap
verified: 2026-04-26T19:13:34Z
status: gaps_found
score: 3/7 must-haves verified
overrides_applied: 0
gaps:
  - truth: "`flux --context k3d-hub-flux get kustomizations -A` shows root `flux-system` Ready=True and the hub is self-managing from `clusters/hub-flux/**`."
    status: failed
    reason: "Read-only live checks show Flux is not bootstrapped on k3d-hub-flux: `flux check` reports missing Flux CRDs/controllers and `kubectl -n flux-system get deploy` returns no resources."
    artifacts:
      - path: "scripts/bootstrap-flux.sh"
        issue: "First-run path can succeed remotely, then fail locally at Section 5 because it requires `clusters/hub-flux/flux-system/kustomization.yaml` to already exist in this checkout."
      - path: "clusters/hub-flux/flux-system/kustomization.yaml"
        issue: "Missing in this checkout; the round-trip patch-surface marker/reconciliation path is not established."
    missing:
      - "Sync or otherwise materialize bootstrap-generated manifests locally before applying the patch-surface marker, or apply the marker through the same remote Git workflow as bootstrap."
      - "After the code fix, run the destructive live bootstrap proof and verify root `flux-system` Kustomization Ready=True."
  - truth: "Bootstrap is idempotent: rerunning after a successful first bootstrap leaves the cluster in the same state and exits 0."
    status: failed
    reason: "The only idempotency proof is skipped unless live/destructive gates are set, and the current first-run implementation has the CR-01 local-file assumption that can fail before a clean rerun proof exists."
    artifacts:
      - path: "tests/bats/bootstrap-flux-01-idempotent.bats"
        issue: "The live/destructive idempotency test is correctly defined but skipped in non-live regression."
      - path: "scripts/bootstrap-flux.sh"
        issue: "Section 5 hard-fails when the local kustomization file is absent after bootstrap."
    missing:
      - "Close the first-run local-manifest gap, then run `KARYON_LIVE_TESTS=1 KARYON_LIVE_TESTS_DESTRUCTIVE=1 bats tests/bats/bootstrap-flux-01-idempotent.bats --tap`."
  - truth: "GITHUB_OWNER, GITHUB_REPO, and GITHUB_TOKEN are read from gitignored `.env`, and the script never exposes the token value."
    status: failed
    reason: "`.env` is gitignored and the script does not directly echo `GITHUB_TOKEN`, but `source \"${REPO_ROOT}/.env\"` executes arbitrary shell from the secrets file. A malformed `.env` can run commands or print data during bootstrap."
    artifacts:
      - path: "scripts/bootstrap-flux.sh"
        issue: "Lines 111-114 source `.env` as shell code instead of parsing the three expected keys as data."
    missing:
      - "Replace `source .env` with a narrow parser for `GITHUB_OWNER`, `GITHUB_REPO`, and `GITHUB_TOKEN` that exports values without executing other shell syntax."
---

# Phase 3: Flux Hub Bootstrap Verification Report

**Phase Goal:** `flux --context k3d-hub-flux get kustomizations -A` shows the root `flux-system` Kustomization as `Ready=True`; the hub is self-managing and commits to `clusters/hub-flux/**` round-trip through reconciliation.
**Verified:** 2026-04-26T19:13:34Z
**Status:** gaps_found
**Re-verification:** No - initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Root `flux-system` Kustomization is `Ready=True` on `k3d-hub-flux` and the hub self-manages from `clusters/hub-flux/**`. | FAILED | `flux --context k3d-hub-flux get kustomizations -A` failed with missing Flux Kustomization API; `flux check` reports missing CRDs/controllers; `kubectl --context k3d-hub-flux -n flux-system get deploy` reports no resources. |
| 2 | `scripts/bootstrap-flux.sh` runs `flux bootstrap github` against hub-flux with `--path clusters/hub-flux` hard-coded and no env override. | VERIFIED | `scripts/bootstrap-flux.sh:35-39` defines readonly `FLUX_PATH=clusters/hub-flux` and `KUBE_CTX=k3d-hub-flux`; `scripts/bootstrap-flux.sh:70-76` requires current context `k3d-hub-flux`; `scripts/bootstrap-flux.sh:129-137` invokes `flux bootstrap github` with `--path "${FLUX_PATH}"`. |
| 3 | First-run bootstrap completes locally and commits to `clusters/hub-flux/**` round-trip through reconciliation. | FAILED | Review CR-01 is confirmed by code: `scripts/bootstrap-flux.sh:189-193` exits if local `clusters/hub-flux/flux-system/kustomization.yaml` is missing. This checkout has no such file. |
| 4 | Rerunning bootstrap after success is a no-op and exits 0. | FAILED | Static skip logic exists at `scripts/bootstrap-flux.sh:79-103`, but the live/destructive proof is skipped in non-live Bats and first-run success is blocked by the local-manifest gap. |
| 5 | `.env` provides GitHub owner/repo/token without token exposure. | FAILED | `.gitignore:5` ignores `.env`; direct token logging grep found no executable `echo`/`printf`/helper/`tee` leak. However `scripts/bootstrap-flux.sh:111-114` sources `.env` as shell code, matching review CR-02. |
| 6 | Docs explain bootstrap-managed files, `kustomization.yaml` as patch surface, and immutable `--path`. | VERIFIED | `docs/flux-hub-spoke.md:18-22` classifies gotk files vs patch surface; `docs/flux-hub-spoke.md:35-42` documents the patch surface; `docs/flux-hub-spoke.md:73-83` documents `--path` immutability. |
| 7 | `task bootstrap-flux` invokes the bootstrap script through the project task surface. | VERIFIED | `Taskfile.yml:19-22` defines `bootstrap-flux` with `bash scripts/bootstrap-flux.sh`; `task --list` parses and lists all 4 tasks. |

**Score:** 3/7 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `scripts/bootstrap-flux.sh` | 5-section executable bootstrap script | PARTIAL | Exists, executable mode `755`, 240 lines, shellcheck-clean, wired from Taskfile. Fails first-run contract at local manifest assumption and sources `.env` unsafely. |
| `docs/flux-hub-spoke.md` | Patch-surface documentation | VERIFIED | 102 lines; contains gotk bootstrap-managed rules, patch example, skip-message reference, Phase 4 stub, and corrected NetworkPolicy rationale. |
| `Taskfile.yml` | `bootstrap-flux` task | VERIFIED | YAML parses; `.tasks | keys | length` is `4`; `task --list` includes `bootstrap-flux`. |
| `tests/bats/bootstrap-flux-01-idempotent.bats` | Static script contract plus live/destructive idempotency proof | VERIFIED | 125 lines; 7 static tests pass, 1 destructive live test correctly skips without gates. |
| `tests/bats/bootstrap-flux-02-docs.bats` | Static docs contract | VERIFIED | 58 lines; 4 static tests pass. |
| `clusters/hub-flux/flux-system/kustomization.yaml` | Bootstrap-generated local patch surface after first run | MISSING | Not present in this checkout; script currently fails if Flux pushes it remotely but the local checkout has not pulled it. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `Taskfile.yml` | `scripts/bootstrap-flux.sh` | `bash scripts/bootstrap-flux.sh` | WIRED | Command present at `Taskfile.yml:22`. |
| `scripts/bootstrap-flux.sh` | `scripts/lib/preflight-lib.sh` | `source "${SCRIPT_DIR}/lib/preflight-lib.sh"` | WIRED | Present at `scripts/bootstrap-flux.sh:33`. |
| `scripts/bootstrap-flux.sh` | `scripts/preflight.sh` | `bash "${SCRIPT_DIR}/preflight.sh"` | WIRED | Present at `scripts/bootstrap-flux.sh:48`. |
| `scripts/bootstrap-flux.sh` | `.env` | `source "${REPO_ROOT}/.env"` | UNSAFE | Data reaches environment, but by shell execution rather than a data parser. |
| `scripts/bootstrap-flux.sh` | GitHub/Flux bootstrap | `GITHUB_TOKEN=... flux bootstrap github` | WIRED | Invocation exists at `scripts/bootstrap-flux.sh:129-137`; live execution not proven. |
| `scripts/bootstrap-flux.sh` | `clusters/hub-flux/flux-system/kustomization.yaml` | Section 5 marker prepend | BROKEN | Section 5 assumes local file exists after bootstrap and exits otherwise. |
| `docs/flux-hub-spoke.md` | `scripts/bootstrap-flux.sh` | skip-message and path references | WIRED | Docs include `already done, skipping: flux bootstrap` and `--path clusters/hub-flux`. |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `scripts/bootstrap-flux.sh` | `GITHUB_OWNER`, `GITHUB_REPO`, `GITHUB_TOKEN` | `.env` sourced at runtime | Yes, but executes arbitrary shell | FAILED |
| `scripts/bootstrap-flux.sh` | Flux controller/Kustomization status | `flux check`, `kubectl get deploy`, `kubectl get kustomization` | Current cluster reports missing CRDs/controllers | FAILED |
| `scripts/bootstrap-flux.sh` | Patch-surface marker | Local `clusters/hub-flux/flux-system/kustomization.yaml` | No local source file present after non-live verification | FAILED |
| `Taskfile.yml` | Bootstrap command | Static task command | Yes | VERIFIED |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Script syntax and lint | `bash -n scripts/bootstrap-flux.sh && shellcheck -x scripts/bootstrap-flux.sh` | `OK` | PASS |
| Non-live regression | `bats tests/bats/ --tap` | `1..50`, 50 ok; live/destructive checks skipped by unset gates | PASS |
| Taskfile structure | `yq eval '.tasks | keys | length' Taskfile.yml && task --list` | `4`; `bootstrap-flux` listed | PASS |
| Live Flux readiness | `flux --context k3d-hub-flux check` | Missing Flux CRDs/controllers, check failed | FAIL |
| Live controller readiness | `kubectl --context k3d-hub-flux -n flux-system get deploy` | No resources found in `flux-system` | FAIL |
| Phase goal command | `flux --context k3d-hub-flux get kustomizations -A` | Failed: no Flux Kustomization API registered | FAIL |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| FLUX-01 | 03-01, 03-02, 03-04 | `scripts/bootstrap-flux.sh` runs `flux bootstrap github` targeting `hub-flux` | BLOCKED | Command and context gate exist, but current hub is not bootstrapped and CR-01 can make first-run script exit after remote bootstrap. |
| FLUX-02 | 03-01, 03-02 | `--path` is hard-coded to `clusters/hub-flux` | SATISFIED | Readonly `FLUX_PATH=clusters/hub-flux`; no env override pattern; docs reinforce immutability. |
| FLUX-03 | 03-01, 03-02 | GitHub keys read from gitignored `.env`; token never echoed | BLOCKED | `.env` is ignored and no direct token echo was found, but `source .env` executes arbitrary shell from the secrets file. |
| FLUX-04 | 03-01, 03-02 | Bootstrap idempotent on rerun | BLOCKED | Static idempotency gate exists; destructive live proof skipped; CR-01 blocks reliable first-run completion. |
| FLUX-05 | 03-01, 03-03 | Docs define bootstrap-managed files and patch surface | SATISFIED | `docs/flux-hub-spoke.md` contains all required rule text and example; docs Bats tests pass. |

No orphaned Phase 3 requirements were found: ROADMAP and REQUIREMENTS both map FLUX-01 through FLUX-05 to Phase 3.

### Code Review Findings Classification

| Finding | Classification | Verification Decision |
|---------|----------------|-----------------------|
| CR-01: Bootstrap fails after successful first `flux bootstrap` because local `kustomization.yaml` may be absent | BLOCKER | Blocks the phase goal and FLUX-04. The script can leave a partially completed remote/cluster bootstrap, then fail before patch marker and local round-trip proof. |
| CR-02: `.env` is executed as shell code | BLOCKER | Blocks FLUX-03 token-safety quality. It may not prevent a happy-path trusted `.env`, but it violates the safe "read from `.env`" contract and can expose or execute secret-adjacent data. |
| WR-01: Gitleaks hook check reads caller working directory | WARNING | Does not block Phase 3 goal, but should be closed with CR-02/cleanup by anchoring to `${REPO_ROOT}/.git/hooks/pre-commit`. |
| WR-02: Predictable `/tmp` preflight log path | WARNING | Does not block Phase 3 goal, but should be fixed with `mktemp` to avoid symlink/clobber and leftover host detail risk. |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `scripts/bootstrap-flux.sh` | 42 | `PREFLIGHT_LOG="/tmp/preflight-$$.log"` | Warning | Predictable temp path from review WR-02. |
| `scripts/bootstrap-flux.sh` | 61 | `.git/hooks/pre-commit` relative to caller cwd | Warning | Review WR-01; advisory can inspect the wrong repo when invoked outside repo root. |
| `scripts/bootstrap-flux.sh` | 113 | `source "${REPO_ROOT}/.env"` | Blocker | Executes arbitrary shell from the secrets file. |
| `scripts/bootstrap-flux.sh` | 189 | hard fail on missing local `kustomization.yaml` | Blocker | Breaks first-run bootstrap if Flux writes manifests remotely without updating this checkout. |
| `tests/bats/bootstrap-flux-02-docs.bats` | 55 | `placeholder` in comment | Info | Intentional Phase 4 HTML-comment stub test reference, not a product stub. |

### Human Verification Required

After the blocker gaps are fixed, run the destructive/live proof:

1. **First-run bootstrap and rerun idempotency**
   **Test:** `KARYON_LIVE_TESTS=1 KARYON_LIVE_TESTS_DESTRUCTIVE=1 bats tests/bats/bootstrap-flux-01-idempotent.bats --tap`
   **Expected:** first run exits 0, `# FLUX PATCH SURFACE` lands in `clusters/hub-flux/flux-system/kustomization.yaml`, second run exits 0 with `already done, skipping: flux bootstrap`, marker remains.
   **Why human:** Mutates the real hub cluster and GitHub repository.

2. **Flux root readiness and round-trip**
   **Test:** Commit and push a harmless change under `clusters/hub-flux/**`, then run `flux --context k3d-hub-flux get kustomizations -A` and inspect reconciliation.
   **Expected:** root `flux-system` Kustomization is `Ready=True`; the pushed change reconciles back into the hub.
   **Why human:** Requires live Flux/GitHub side effects and operator judgment on the reconciled change.

### Deferred Items

No blocking gap is deferred to a later phase. Phase 5 consumes `task bootstrap-flux` in `task rebuild`, and Phase 4 depends on `flux-system` existing; neither phase owns fixing first-run bootstrap or `.env` parsing. Phase 6 owns the real gitleaks hook, but that does not address CR-02.

### Gaps Summary

The static Phase 3 files exist and most non-live checks pass, but the phase goal is not achieved. The current hub does not have Flux installed or ready, the bootstrap script can fail immediately after a successful remote bootstrap because it assumes local generated files are already present, and `.env` is loaded by executing shell code. These are blockers, not merely missing live proof.

---

_Verified: 2026-04-26T19:13:34Z_
_Verifier: Claude (gsd-verifier)_
