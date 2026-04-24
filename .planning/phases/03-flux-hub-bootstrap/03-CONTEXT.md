# Phase 3: Flux Hub Bootstrap - Context

**Gathered:** 2026-04-24
**Status:** Ready for planning

<domain>
## Phase Boundary

Deliver `flux bootstrap github` on `hub-flux` so the cluster self-manages GitOps out of `clusters/hub-flux/`. Scope:

- `scripts/bootstrap-flux.sh` — idempotent wrapper around `flux bootstrap github` with preflight gating, kubectl-context gating, full post-bootstrap verification, and silent token handling.
- `docs/flux-hub-spoke.md` — committed patch-surface contract covering the three rules from ROADMAP §Phase 3 Success #4 (bootstrap-managed files, `kustomization.yaml` IS the patch surface, `--path` immutable after first run).
- Augmenting the bootstrap-generated `clusters/hub-flux/flux-system/kustomization.yaml` with a top-of-file comment block flagging it as the Flux patch surface.
- Accepting that `clusters/hub-flux/flux-system/{gotk-components.yaml,gotk-sync.yaml}` land in git via `flux bootstrap`'s first commit — they are bootstrap-managed and must not be hand-edited.
- A bats test that invokes `scripts/bootstrap-flux.sh` twice and asserts the second invocation is a no-op (idempotency proof without self-rerun).

Out of scope (owned elsewhere):
- Spoke SA + cluster-admin CRB + legacy-Secret tokens + hub-side `<spoke>-kubeconfig` Secrets + hub-side spoke Kustomizations → Phase 4.
- podinfo / `nvidia-smi` / `task fix-dns` / `task health-check` / `task rebuild` → Phase 5.
- ADR-003 (Flux-over-ArgoCD), ADR-004 (hub-only Flux), gitleaks pre-commit (REPO-04), shellcheck CI, full `Taskfile.yml` reorganization → Phase 6. Per ROADMAP parallelization note, ADR-003 and the hub-spoke reconciliation section of `docs/flux-hub-spoke.md` *may* land during Phase 3 but are owned by Phase 6 / Phase 4 respectively; Phase 3 must not block on them.
- Image-reflector / image-automation controllers → v2 (no release cadence to automate in v1).
- GitHub API PAT-scope probe → explicitly rejected (offline-safe preflight philosophy; `flux bootstrap` error surface is sufficient).

</domain>

<decisions>
## Implementation Decisions

### `flux bootstrap github` Flag Surface
- **D-01:** `--private=false`. Matches PROJECT.md "public from day one" posture. On first run `flux bootstrap` creates the GitHub repo public if it does not exist; on subsequent runs the flag is a no-op. Token-leak risk mitigated by (a) PAT stored only in an in-cluster Secret, not in git, and (b) Phase 6 gitleaks pre-commit landing before first `git push` per ROADMAP Phase 6 parallelization schedule.
- **D-02:** `--personal=true`. Single-author lab targeting a personal GitHub account; `GITHUB_TOKEN` uses classic PAT with `repo` scope. Org-account path is out of scope.
- **D-03:** `--network-policy=false`. Disables the default deny-all NetworkPolicy that isolates `flux-system`. Rationale: k3d's flannel CNI does not enforce NetworkPolicies reliably, and the lab has no adversarial namespace boundary — the policy adds debug surface ("why is reconcile failing?") with no real security benefit at this scope.
- **D-04:** No `--components-extra`. Ship only the 4 core controllers (source-controller, kustomize-controller, helm-controller, notification-controller). Image automation is explicitly v2 per PROJECT.md Out of Scope ("Flagger / progressive delivery", "Image automation controllers"). Revisit when a release cadence exists.

### Idempotency + Preflight Gating
- **D-05:** `scripts/bootstrap-flux.sh` **delegates to `scripts/preflight.sh`** as its first step. Mirrors Phase 2 D-06 integration pattern:
  ```bash
  scripts/preflight.sh > /dev/null 2>&1 || fail "preflight blockers — run scripts/preflight.sh"
  ```
  Preflight already covers `.env` presence + key non-emptiness (PRE-09), asdf shim precedence (PRE-10), tool-version pins (PRE-05 incl. `flux 2.8.6`), Docker runtime, WSL host floor. Bootstrap-flux does not re-implement any of those.
- **D-06:** **kubectl context gate is an explicit fail-with-remediation**, not auto-switch. Before anything else:
  ```bash
  ctx="$(kubectl config current-context)"
  [[ "$ctx" == "k3d-hub-flux" ]] || fail "kubectl context is $ctx, expected k3d-hub-flux → run: kubectl config use-context k3d-hub-flux"
  ```
  Script must not mutate the user's shell-global kubeconfig state. All subsequent `kubectl`/`flux` calls may rely on current-context or pass `--context k3d-hub-flux` explicitly (planner picks; explicit is safer for sub-shells inside `wait` polls).
- **D-07:** **Idempotency = "skip if healthy, else fall through to full bootstrap"**, matching Phase 1 D-05 + Phase 2 D-09 guarded-sections pattern. The "already done" gate is a three-part AND:
  1. `kubectl get ns flux-system` exists, AND
  2. `flux --context k3d-hub-flux check` exits 0, AND
  3. All 4 controller Deployments in `flux-system` report `Available=True`.

  On a healthy skip, log `info "already done, skipping: flux bootstrap"` and exit 0. If any of the three conditions fails, fall through to the full bootstrap path (flux bootstrap is itself reconciliation-based and will heal partial state).
- **D-08:** **No GitHub API PAT-scope probe.** Matches Phase 1 D-10 philosophy ("presence + non-empty per key, no network calls"). If the PAT lacks `repo` scope, `flux bootstrap github` fails with a clear upstream message; the script surfaces that unchanged. Keeps bootstrap-flux.sh offline-safe and avoids a curl/jq dependency on the happy path.

### Post-Bootstrap Verification
- **D-09:** **Full three-gate success check** before exit 0. After `flux bootstrap github` returns 0, the script asserts in this order:
  1. `flux --context k3d-hub-flux check` passes (flux's own health signal).
  2. `kubectl --context k3d-hub-flux -n flux-system wait --for=condition=Available deploy --all --timeout=120s` succeeds (all 4 controllers Ready).
  3. `flux --context k3d-hub-flux get kustomizations flux-system` reports Ready=True (proves the self-managing loop closed, matches ROADMAP Success #2 + the phase-goal clause "the root `flux-system` Kustomization as `Ready=True`").
- **D-10:** **Readiness wait uses `kubectl wait` with a 120s timeout**, not a custom bash poll. One line, idiomatic, clean failure surface. If the wait fails, `fail "flux controllers did not reach Ready in 120s — inspect: kubectl -n flux-system get deploy,pod"`.
- **D-11:** **Token-leak defense is script discipline, not runtime filtering.** Specifically: `set -euo pipefail` (no `-x`), never `echo "$GITHUB_TOKEN"` anywhere, no `tee`/log-to-file in v1, no `set -x` trace. `flux bootstrap github` itself does not echo the PAT in its own stdout when PAT is passed via env. Phase 6 gitleaks pre-commit is the git-history net. No sed-redaction wrapper (heavy, risks breaking diagnostic output).
- **D-12:** **Idempotency is proven by an external bats test**, not a self-rerun inside the script. The test (under `tests/bats/`) invokes `scripts/bootstrap-flux.sh`, then invokes it again and asserts the second invocation logs `already done, skipping: flux bootstrap` and exits 0. Matches Phase 1/2 test pattern; keeps runtime script single-pass.

### Doc + `kustomization.yaml` Seed
- **D-13:** **Let `flux bootstrap` write `clusters/hub-flux/flux-system/kustomization.yaml`; then augment with a top-of-file comment block** as a post-bootstrap step (either in `scripts/bootstrap-flux.sh` itself via `sed`/`awk`, or as a one-time Phase 3 plan commit — planner picks). Comment block reads approximately:
  ```yaml
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
  ```
  Bootstrap-generated body stays intact below the comment. In-file discoverability is critical — `docs/flux-hub-spoke.md` is not guaranteed to be read before someone opens this file.
- **D-14:** **`docs/flux-hub-spoke.md` Phase-3 scope is tight** — exactly the three rules required by ROADMAP Success #4, each with a short "why" paragraph, plus one worked `kustomization.yaml` patch example (D-15) and a one-line mention of bootstrap-flux.sh's skip-message (D-16). Phase 4 appends the hub-spoke reconciliation section per ROADMAP parallelization note; Phase 3 leaves a `<!-- Phase 4: hub-spoke reconciliation -->` stub at the bottom but does not fill it.
- **D-15:** **Include one concrete patch example** in `docs/flux-hub-spoke.md` — bumping kustomize-controller's memory limit via a `patches:` block in `kustomization.yaml`. Grounds the "kustomization.yaml IS editable" rule in a real, copyable artifact:
  ```yaml
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
  Costs ~10 lines; makes the rule falsifiable ("rerun `flux bootstrap`, confirm patch survives").
- **D-16:** **`docs/flux-hub-spoke.md` explicitly mentions the idempotency-skip behavior.** One sentence: "Rerunning `scripts/bootstrap-flux.sh` on an already-bootstrapped hub logs `already done, skipping: flux bootstrap` and exits 0." The script is the canonical source for the message; the doc points readers at it. Ties the doc to the script's observable behavior.

### Claude's Discretion

These were not explicitly discussed; planner/researcher decides:
- **Where D-13's comment-block augmentation happens** — inline in `scripts/bootstrap-flux.sh` (as a post-bootstrap `awk`/`sed` step gated on "comment block not already present") vs. as a separate plan step that hand-commits the augmented file once and relies on `flux bootstrap`'s reconciliation to preserve it. **Guidance:** Prefer inline script augmentation, idempotently guarded — the comment block must survive re-bootstrap and a hand-commit risks being revertible if `flux bootstrap` ever rewrites the file; an in-script post-step keeps the invariant scripted.
- **`GITHUB_TOKEN` passing mechanism to `flux bootstrap github`** — research current `flux` CLI 2.8.6 docs to confirm whether `GITHUB_TOKEN` env var is auto-consumed, or whether `--token-auth` + stdin / `--token-file` is needed. Either works; pick the form that guarantees the token is not visible via `ps auxww`.
- **`--author-name` / `--author-email` for the initial bootstrap commit** — either leave unset (flux uses its defaults) or wire to values read from `.env` / `git config user.email`. Not a real scope issue for a single-author lab.
- **`--branch`** — default `main` is correct; pass explicitly or omit. Repo is already on `main`; no edge case.
- **`--cluster-domain`** — default `cluster.local` is correct for k3d; omit unless research surfaces a reason.
- **Exact flux CLI version assertion** — whether bootstrap-flux.sh re-asserts `flux version` matches `.tool-versions` pin (`flux2 2.8.6`) or trusts preflight.sh (PRE-05) to have done so. Preflight covers this; in-script re-check is belt-and-suspenders only.
- **Phase 6 dependency hook** — whether bootstrap-flux.sh warns (non-fatal) if gitleaks pre-commit is not installed. ROADMAP §Phase 3 risk note ("gating first commit on Phase 6's gitleaks") implies some coordination. Options: (a) warn only, (b) hard-block only if `.git/hooks/pre-commit` does not reference `gitleaks`, (c) ignore (trust Phase 6 parallelization schedule landing REPO-04 before first `git push`). Recommendation: warn only — Phase 3 should not hard-block on a Phase 6 artifact.
- **Whether `scripts/bootstrap-flux.sh` also sets up a one-time `git remote` / `git push` of the initial bootstrap commit**, or whether `flux bootstrap github` handles the full remote round-trip itself. Research `flux bootstrap github`'s current behavior with an existing local git tree — the command is documented to handle it end-to-end.
- **Bats test structure for D-12 idempotency proof** — whether it reuses the `require_live_destructive()` double-gate pattern from Phase 2 (since it mutates a real cluster) or uses a dedicated `KARYON_LIVE_BOOTSTRAP=1` gate. Planner decides; follow the Phase 2 destructive-test pattern.
- **`docs/flux-hub-spoke.md` front matter / TOC** — include a short TOC at top or keep flat; implementation taste.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project-level specs
- `.planning/PROJECT.md` — Core value; Key Decisions table (Flux-over-ArgoCD, hub-only Flux, public repo + `.env` posture); Context section (public-repo secrets posture, `flux bootstrap` PAT-to-Secret behavior, `clusters/hub-flux/flux-system/` bootstrap-managed rule, asdf shim precedence).
- `.planning/REQUIREMENTS.md` §Flux Hub Bootstrap (FLUX-01..05 — the 5 REQ-IDs in this phase), §Documentation (DOCS-03 — docs/flux-hub-spoke.md content requirement), §Repo Hygiene (REPO-01..04 referenced for public-repo / PAT-safety context).
- `.planning/ROADMAP.md` §Phase 3 — goal ("`flux --context k3d-hub-flux get kustomizations -A` shows the root `flux-system` Kustomization as `Ready=True`"), 4 success criteria, LOW-risk notes, dependency on Phase 2, parallelization with Phase 6 (ADR-003, ADR-004, docs stubs).

### Prior-phase context (Phases 1 + 2 — completed)
- `.planning/phases/01-host-foundation/01-CONTEXT.md` — Phase 1 decisions that carry in: D-05 (guarded-sections pattern for idempotency — Phase 3 D-07 follows this verbatim), D-09 (`.env.example` shipped in Phase 1, validated by preflight), D-10 (preflight validates `.env` keys at presence + non-empty only — no API probes; Phase 3 D-08 inherits this philosophy), D-12 (narrow `.gitignore` slice covering `.env*`).
- `.planning/phases/02-cluster-layer/02-CONTEXT.md` — Phase 2 decisions and integration contract: scripts source `scripts/lib/preflight-lib.sh` (Phase 3 D-05 delegation pattern comes from §Integration Points); the "preflight.sh delegation then guarded sections" template; SAN-verification precedent for defense-in-depth checks (informs Phase 3 D-09 full verification); the `section "…"` / `pass` / `warn` / `fail` / `info` vocabulary inherited verbatim.
- `.planning/phases/02-cluster-layer/02-VERIFICATION.md` — Phase 2 verification artifact structure; Phase 3 verification (forthcoming) should follow the same shape.

### Existing code to reuse / extend
- `scripts/lib/preflight-lib.sh` — shared helper library. `scripts/bootstrap-flux.sh` **must** `source` it; duplicate helpers are forbidden.
- `scripts/preflight.sh` — Phase 1 preflight; Phase 3 delegates to it as first script step (D-05).
- `scripts/create-clusters.sh` — direct style reference for `scripts/bootstrap-flux.sh`: section headers, guarded-sections with skip-if-present, remediation-rich `fail` messages, idempotent-by-check-first pattern.
- `scripts/delete-clusters.sh` — reference for single-responsibility scripts that mutate cluster state; bootstrap-flux mirrors its shape.
- `Taskfile.yml` — Phase 2 stub. Phase 3 appends a `bootstrap-flux` task entry (`bash scripts/bootstrap-flux.sh`); full REPO-05 reorganization remains Phase 6.
- `.env.example` — Contract for `GITHUB_OWNER`, `GITHUB_REPO`, `GITHUB_TOKEN`. Phase 3 does not extend it; Phase 3 scripts read `.env` (preflight validates).
- `.gitignore` — already excludes `.env` (Phase 1 D-12). Do not re-touch until Phase 6.
- `.tool-versions` — `flux2 2.8.6` is the CLI pin. `scripts/bootstrap-flux.sh` assumes this via asdf shim; does not re-install.
- `starter.md` — repo-layout reference: confirms `scripts/bootstrap-flux.sh`, `docs/flux-hub-spoke.md`, `clusters/hub-flux/flux-system/`, `clusters/hub-flux/spokes/` paths.

### External references (researcher must fetch current 2026 docs at planning time — no URLs assumed)
- **`flux` CLI 2.8.6 `bootstrap github` subcommand** — full flag surface, semantics of `--private`, `--personal`, `--network-policy`, `--components-extra`, `--path`, `--branch`, `--cluster-domain`, `--token-auth`, `--author-name`, `--author-email`. How `GITHUB_TOKEN` env var is consumed (env vs stdin vs flag). Idempotency guarantees on a healthy cluster. Exact text of failure when PAT scope is insufficient. 2026-era quirks with k3d clusters.
- **Flux `kustomize-controller` v1 spec** — Kustomization CRD, `spec.path`, `spec.kubeConfig.secretRef` shape (informs Phase 3 doc's forward-looking section stub for Phase 4; do not spec out Phase 4 decisions here). Confirms the "kustomization.yaml is the patch surface" contract is a documented Flux idiom.
- **Flux gotk-components + gotk-sync semantics** — what exactly each of the two bootstrap-managed files contains; what the bootstrap-generated `kustomization.yaml` looks like; how `patches:` + `resources:` blocks in `kustomization.yaml` survive re-bootstrap (the "--path immutable after first run" claim depends on this).
- **`flux check`** — exit codes, what it validates, how it behaves on a partial bootstrap. (D-09 gate 1.)
- **`kubectl wait --for=condition=Available`** — behavior against Flux controller Deployments; timeout semantics on a never-converging state.
- **NetworkPolicy on k3d flannel CNI** — confirms the "flannel does not enforce NPs" rationale for D-03.
- **`flux bootstrap` idempotency model** — specifically, what happens on rerun after a manual hand-edit to `kustomization.yaml` (does the patch survive? this is the core claim of Phase 3 Success #4).

### ADR pointers (authored in Phase 6 — consistency required)
- **ADR-003 (Flux-over-ArgoCD)** — Phase 3 decisions must be consistent with the "simpler bootstrap for 2–3 spokes" rationale in PROJECT.md. Do not write ADR content here; do not contradict it.
- **ADR-004 (hub-only Flux control plane)** — Phase 3 is the bootstrap *of the hub*. Phase 4 registers spokes. ADR-004 captures the topology rationale; Phase 3 implements the hub leg.

### Peer artifacts (Phase 6 parallelizable work)
- `docs/adr/0003-flux-over-argocd.md` — Phase 6, landable during Phase 3 per ROADMAP parallelization. Phase 3 must not block on it.
- `docs/adr/0004-hub-only-flux-control-plane.md` — Phase 6, landable during Phase 4 per ROADMAP. Do not touch in Phase 3.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `scripts/lib/preflight-lib.sh` — full helper library inherited from Phase 1 (ANSI-color gate, `section`/`pass`/`warn`/`fail`/`info`/`have` vocabulary, counters). `scripts/bootstrap-flux.sh` sources it and uses these helpers verbatim.
- `scripts/preflight.sh` — the delegation target for the Phase 3 pre-bootstrap gate (D-05). Already verifies `.env` keys (PRE-09), asdf shim precedence (PRE-10), `flux 2.8.6` presence (PRE-05), Docker runtime, ports, host floor. bootstrap-flux trusts it and does not re-implement.
- `scripts/create-clusters.sh`, `scripts/delete-clusters.sh` — style references for the `scripts/bootstrap-flux.sh` structure: `set -euo pipefail`, source lib, section headers, guarded sections, remediation-rich `fail`.
- `Taskfile.yml` — Phase 2 stub; Phase 3 appends a `bootstrap-flux` task (single-line invocation) without reorganizing.
- `.env` (gitignored) — source of `GITHUB_OWNER`, `GITHUB_REPO`, `GITHUB_TOKEN`. Preflight validates presence + non-empty; bootstrap-flux exports them with `set -a; source .env; set +a` (or equivalent) inside a short-lived subshell and never echoes them.

### Established Patterns
- **`#!/usr/bin/env bash` + `set -euo pipefail`** — imperative mutating scripts (Phase 1 install scripts, Phase 2 cluster scripts). bootstrap-flux.sh follows this; specifically NOT `set -x` (D-11 token-safety).
- **ANSI colors gated on `[[ -t 1 ]]`** — via preflight-lib.sh.
- **Guarded-sections idiom** — every logical step checks state first and either logs `info "already done, skipping: <what>"` or proceeds with `pass "<doing>: <what>"`. D-07 idempotency check IS this idiom applied at script-scale.
- **Blocker message includes remediation command** — e.g., `fail "kubectl context is <X>, expected k3d-hub-flux → run: kubectl config use-context k3d-hub-flux"`.
- **`have() { command -v "$1" >/dev/null 2>&1; }`** — POSIX tool-presence probe from preflight-lib.sh.
- **Bats tests under `tests/bats/`** — destructive integration tests gated by `require_live_destructive()` + `KARYON_LIVE_*=1` env (from Phase 2). Phase 3 idempotency test (D-12) follows this pattern.

### Integration Points
- **Upstream (required for Phase 3 to run):** Phase 2's `hub-flux` cluster exists and is Ready on port 6443; `k8s-net` bridge network present at `172.30.0.0/16` (Phase 2 D-11); kubectl context `k3d-hub-flux` is exported to the user's kubeconfig (k3d default). `scripts/preflight.sh` exits 0.
- **Downstream (Phase 4 depends on Phase 3 landing):** `flux-system` namespace exists on hub-flux with 4 Ready controllers; `kustomize-controller` Deployment is in place to consume the spoke-kubeconfig Secrets that Phase 4 creates under `spec.kubeConfig.secretRef`; `clusters/hub-flux/` directory exists in the repo and is reconciled by the root `flux-system` Kustomization so Phase 4's `clusters/hub-flux/spokes/<spoke>.yaml` Kustomizations are picked up automatically when added.
- **Downstream (Phase 5 depends on Phase 3 landing):** `task rebuild` invokes `task bootstrap-flux` as the third step in the chain; idempotency (D-07) is load-bearing for the < 20 min SLO (rerun on a fully-bootstrapped hub must be a fast no-op).
- **Downstream (Phase 6 parallelizable):** `docs/adr/0003-flux-over-argocd.md` captures Phase 3's architectural rationale; ADR-003 landing during Phase 3 is ROADMAP-sanctioned but not required.
- **External side effects on Phase 3 execution:**
  - `flux bootstrap github` creates (or reuses) a GitHub repo at `$GITHUB_OWNER/$GITHUB_REPO` (public per D-01).
  - First bootstrap adds commits to the repo's `main` branch under `clusters/hub-flux/flux-system/`: `gotk-components.yaml`, `gotk-sync.yaml`, `kustomization.yaml`.
  - A `fluxcd/flux-system` deploy key or PAT-backed access is written into the repo's GitHub settings (depends on `--token-auth`).
  - An in-cluster Secret (`flux-system/flux-system` or similar — research confirms) holds the PAT. This Secret is the only place the token persists outside of the gitignored `.env`.

</code_context>

<specifics>
## Specific Ideas

- `scripts/bootstrap-flux.sh` **top-of-file comment** should explicitly cross-reference the two locked decisions from REQ-FLUX-02 and REQ-FLUX-03:
  ```bash
  # scripts/bootstrap-flux.sh
  # Runs `flux bootstrap github` on k3d-hub-flux with --path locked to
  # clusters/hub-flux (REQ-FLUX-02 — effectively immutable after first run).
  # Sources GITHUB_OWNER / GITHUB_REPO / GITHUB_TOKEN from the gitignored .env
  # (REQ-FLUX-03). The token is never echoed to stdout.
  ```
- Section headers in bootstrap-flux.sh, matching Phase 1/2 vocabulary:
  - `section "Preflight gate"` — one-line pass or bail via `scripts/preflight.sh`.
  - `section "Context + idempotency checks"` — kubectl context assertion (D-06), then the three-part idempotency AND (D-07). On healthy skip, `info` + exit 0.
  - `section "flux bootstrap"` — the actual `flux bootstrap github ...` invocation.
  - `section "Post-bootstrap verification"` — `flux check` + `kubectl wait` + `flux get kustomizations flux-system` Ready=True (D-09).
  - `section "Patch-surface marker"` — the D-13 comment-block augmentation on `clusters/hub-flux/flux-system/kustomization.yaml`.
- Every `fail` must tell the user exactly what to run to fix it:
  - `.env missing or key empty → preflight.sh covers this; run scripts/preflight.sh for detail`
  - `kubectl context mismatch → kubectl config use-context k3d-hub-flux`
  - `flux controllers did not reach Ready in 120s → kubectl -n flux-system get deploy,pod; flux logs`
  - `flux-system Kustomization not Ready=True → flux get kustomizations flux-system; flux logs --kind=Kustomization`
  - `patch-surface marker failed to apply → manually prepend the comment block to clusters/hub-flux/flux-system/kustomization.yaml (docs/flux-hub-spoke.md shows the canonical form)`
- `docs/flux-hub-spoke.md` section skeleton (Phase 3 scope):
  1. **What `flux bootstrap` writes** — the 3 files under `clusters/hub-flux/flux-system/`, each tagged `bootstrap-managed` or `patch surface`.
  2. **Rule 1: `gotk-components.yaml` + `gotk-sync.yaml` are bootstrap-managed — do not hand-edit.**
  3. **Rule 2: `kustomization.yaml` IS the supported patch surface — hand-edits here survive re-bootstrap.** (Include the D-15 memory-limit example.)
  4. **Rule 3: `--path` is effectively immutable after first run.** (Short paragraph explaining why: changing `--path` creates a divergent bootstrap commit that abandons the original tree.)
  5. **Rerun behavior.** (One sentence per D-16.)
  6. `<!-- Phase 4: hub-spoke reconciliation (spec.kubeConfig, <spoke>-kubeconfig Secrets, value.yaml key) -->` stub.
- **`flux bootstrap github` invocation skeleton** (researcher confirms exact token-passing mechanism):
  ```bash
  GITHUB_TOKEN="$GITHUB_TOKEN" flux bootstrap github \
    --owner "$GITHUB_OWNER" \
    --repository "$GITHUB_REPO" \
    --path clusters/hub-flux \
    --personal \
    --private=false \
    --network-policy=false \
    --branch main
  ```
- The `clusters/hub-flux/flux-system/kustomization.yaml` comment-block augmentation is **idempotent** — the augment step greps for a sentinel line (e.g., `# FLUX PATCH SURFACE`) and does nothing if already present.

</specifics>

<deferred>
## Deferred Ideas

- **Image automation (image-reflector-controller + image-automation-controller)** — rejected in D-04. Revisit in v2 when a release cadence exists that warrants automated image-tag bumps.
- **GitHub org/app-based bootstrap** — rejected in D-02 for this lab. Revisit if the project ever moves to a multi-author / org-owned repo.
- **NetworkPolicy-based namespace isolation on flux-system** — rejected in D-03 due to flannel CNI enforcement gap and lack of adversarial boundary. Revisit if the CNI changes or the lab grows a real multi-tenant story.
- **GitHub API PAT-scope probe in bootstrap-flux.sh** — rejected in D-08 to preserve offline-safe philosophy. Revisit only if users report unhelpful `flux bootstrap` error messages on scope mismatch.
- **Auto-switch kubectl context on mismatch** — rejected in D-06 to avoid mutating user shell state. Revisit never (mutation hidden from the user is bad ergonomics).
- **Self-rerun inside bootstrap-flux.sh for idempotency proof** — rejected in D-12 in favor of an external bats test. Revisit only if the bats test framework itself becomes unavailable.
- **sed-redaction wrapper around `flux bootstrap` stdout for token-leak defense** — rejected in D-11 as heavyweight and potentially output-breaking. Revisit only if flux changes its behavior and starts echoing the PAT.
- **Pre-commit an empty `clusters/hub-flux/flux-system/kustomization.yaml` before bootstrap** — rejected in D-13 due to bootstrap-overwrite risk. Revisit only if flux bootstrap's handling of a pre-existing kustomization.yaml is documented and stable across versions.
- **Hard-block bootstrap-flux.sh on Phase 6 gitleaks being installed** — rejected (Claude's Discretion guidance). Soft warn is the ceiling; Phase 3 must not block on a Phase 6 artifact.
- **Phase 4 hub-spoke reconciliation content in `docs/flux-hub-spoke.md`** — Phase 4 scope. Phase 3 leaves an HTML-comment stub.
- **ADR-003 + ADR-004 authoring** — Phase 6 scope per ROADMAP parallelization. Phase 3 must not block on them.
- **Flagger / progressive delivery** — PROJECT.md Out of Scope; no release cadence to automate.
- **Full `Taskfile.yml` REPO-05 reorganization** — Phase 6. Phase 3 appends a single `bootstrap-flux` task line to the existing stub.
- **`--components-extra=notification-controller` customization (Slack/Teams webhooks, etc.)** — deferred until there's an operator-facing notification requirement.
- **Non-`main` branch bootstrap** — repo is on `main`; non-`main` bootstrap is not blocked but not exercised.

</deferred>

---

*Phase: 03-flux-hub-bootstrap*
*Context gathered: 2026-04-24*
