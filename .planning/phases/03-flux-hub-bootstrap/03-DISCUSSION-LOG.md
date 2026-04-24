# Phase 3: Flux Hub Bootstrap - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-24
**Phase:** 03-flux-hub-bootstrap
**Areas discussed:** Bootstrap flag surface, Idempotency + preflight gate, Post-bootstrap verification, Doc + kustomization.yaml seed

---

## Gray-area selection

| Option | Description | Selected |
|--------|-------------|----------|
| Bootstrap flag surface | `flux bootstrap github` flag set (private, personal, network-policy, components-extra) | ✓ |
| Idempotency + preflight gate | "already bootstrapped" detection + pre-check gating (preflight.sh, kubectl context, PAT scope probe) | ✓ |
| Post-bootstrap verification | What "green" means before exit 0 (flux check / controllers Ready / Kustomization Ready=True) | ✓ |
| Doc + kustomization.yaml seed | `docs/flux-hub-spoke.md` scope + whether to pre-commit or augment `kustomization.yaml` | ✓ |

**User's choice:** All four selected.

---

## Bootstrap flag surface

| Option | Description | Selected |
|--------|-------------|----------|
| `--private=false` | Public repo per PROJECT.md "public from day one"; token-leak risk mitigated by PAT-in-Secret-only + Phase 6 gitleaks | ✓ |
| `--private=true` | Private until Phase 6 ships; contradicts PROJECT.md posture | |
| Don't pass the flag; assume repo exists | Keeps public/private entirely out of the script | |

**User's choice:** `--private=false`.

| Option | Description | Selected |
|--------|-------------|----------|
| `--personal=true` | Target personal GitHub account; classic PAT with `repo` scope | ✓ |
| `--personal=false` (org) | Bootstrap against a GitHub organization | |

**User's choice:** `--personal=true`.

| Option | Description | Selected |
|--------|-------------|----------|
| `--network-policy=true` (upstream default) | Flux installs deny-all NetworkPolicy isolating flux-system | |
| `--network-policy=false` | Skip the policy; flannel CNI doesn't enforce reliably; reduces debug surface | ✓ |

**User's choice:** `--network-policy=false`.

| Option | Description | Selected |
|--------|-------------|----------|
| No extras (4 core controllers only) | source/kustomize/helm/notification only; image automation is v2 per PROJECT.md | ✓ |
| Include image-reflector + image-automation | `--components-extra=image-reflector-controller,image-automation-controller` | |

**User's choice:** No extras.

**Notes:** All four recommendations matched the locked project-level posture. No user overrides.

---

## Idempotency + preflight gate

| Option | Description | Selected |
|--------|-------------|----------|
| Trust flux native idempotency; always invoke | Just run flux bootstrap every time; ~15–30s rerun cost | |
| Pre-check, skip if healthy | Three-part AND (ns exists + flux check + 4 controllers Ready) | ✓ |
| Pre-check only by namespace presence | Fast but brittle; misses partial-bootstrap states | |

**User's choice:** Pre-check, skip if healthy.

| Option | Description | Selected |
|--------|-------------|----------|
| Delegate to scripts/preflight.sh | Same pattern as Phase 2 create-clusters.sh | ✓ |
| Inline checks only | Duplicates a subset of preflight.sh | |
| Both: preflight.sh + inline kubectl context check | Defense-in-depth | |

**User's choice:** Delegate to scripts/preflight.sh.

**Notes:** kubectl context assertion is handled separately as its own gate (next question), not inside preflight.sh.

| Option | Description | Selected |
|--------|-------------|----------|
| No API probe; let flux bootstrap fail | Offline-safe; matches Phase 1 D-10 philosophy | ✓ |
| Probe `GET /user` + `GET /repos/{owner}/{repo}` | Earlier, friendlier failure; adds network + jq dependency | |

**User's choice:** No probe.

| Option | Description | Selected |
|--------|-------------|----------|
| Fail with exact remediation | `fail "kubectl context is <X>, expected k3d-hub-flux → run: kubectl config use-context k3d-hub-flux"` | ✓ |
| Auto-switch context and warn | Mutates user shell-global kubeconfig state | |
| Use `--context k3d-hub-flux` on every call | No gate; noisier script | |

**User's choice:** Fail with exact remediation.

---

## Post-bootstrap verification

| Option | Description | Selected |
|--------|-------------|----------|
| Full verify: flux check + 4 controllers Ready + flux-system Kustomization Ready=True | Three-gate; matches ROADMAP Success #2 + phase goal verbatim | ✓ |
| Minimal: only `flux check` | Trust flux's own health signal | |
| Return code of `flux bootstrap` only | Fastest; skips Kustomization Ready proof | |

**User's choice:** Full verify (three gates).

| Option | Description | Selected |
|--------|-------------|----------|
| `kubectl wait` with 120s timeout | Idiomatic; one line; clean failure message | ✓ |
| Poll loop with `flux get kustomizations` + sleep | More control over exit message; more code | |
| No wait | Trust `flux bootstrap` to return only when ready | |

**User's choice:** `kubectl wait --for=condition=Available deploy --all -n flux-system --timeout=120s`.

| Option | Description | Selected |
|--------|-------------|----------|
| Script discipline only: never echo, no `set -x`, no log-to-file | Relies on flux's own PAT handling + Phase 6 gitleaks | ✓ |
| Explicit grep assertion at script end | `git log -p clusters/hub-flux \| grep -qF $GITHUB_TOKEN && fail` | |
| sed-redaction wrapper around `flux bootstrap` stdout | Heavyweight; risks breaking diagnostics | |

**User's choice:** Script discipline only.

| Option | Description | Selected |
|--------|-------------|----------|
| No self-rerun; idempotency proven by bats test | External test invokes the script twice | ✓ |
| Self-rerun inside the script as final assertion | Doubles runtime; weird recursion | |

**User's choice:** External bats test.

---

## Doc + kustomization.yaml seed

| Option | Description | Selected |
|--------|-------------|----------|
| Let bootstrap write it, then augment with top-of-file comment block | Comment block idempotently prepended post-bootstrap; survives re-bootstrap | ✓ |
| Pre-commit an empty commented kustomization.yaml before bootstrap | Risk: flux bootstrap may overwrite; version-dependent | |
| Leave kustomization.yaml as bootstrap writes it; docs only | Loses in-file discoverability | |

**User's choice:** Augment with comment block post-bootstrap.

| Option | Description | Selected |
|--------|-------------|----------|
| Tight: patch-surface + --path-immutability + bootstrap-managed files | 3 rules + short "why" per ROADMAP Success #4 | ✓ |
| Broader: include forward stubs for hub-spoke reconciliation | Mixes Phase 3 scope with Phase 4 content | |
| Minimum viable: one paragraph per rule, no examples | Meets success criterion literally; less useful | |

**User's choice:** Tight scope + forward-looking Phase 4 HTML-comment stub.

| Option | Description | Selected |
|--------|-------------|----------|
| Yes — one real example: kustomize-controller memory-limit patch | Grounds rule in a concrete copyable artifact | ✓ |
| No — rules text only | Defers "how do I patch" to Flux upstream docs | |

**User's choice:** Include the memory-limit patch example.

| Option | Description | Selected |
|--------|-------------|----------|
| Mention in doc + script carries the canonical message | Doc points at script; one source of truth for log text | ✓ |
| Script only; no mention in doc | Self-documenting on rerun | |

**User's choice:** Mention in doc; script is canonical.

---

## Claude's Discretion

Items where the user did not make an explicit choice and planner/researcher decides (captured in CONTEXT.md §Claude's Discretion):

- Inline-in-script vs. separate plan-step location for the `kustomization.yaml` comment-block augmentation (D-13).
- Exact `GITHUB_TOKEN` passing mechanism to `flux bootstrap github` (env / stdin / `--token-file`).
- `--author-name` / `--author-email` for the bootstrap commit.
- `--branch` / `--cluster-domain` — defaults assumed correct.
- In-script flux CLI version assertion (belt-and-suspenders over preflight.sh's PRE-05).
- Phase 6 gitleaks dependency hook — warn-only ceiling; no hard block on a Phase 6 artifact.
- Whether `scripts/bootstrap-flux.sh` handles git remote/push or trusts `flux bootstrap github` end-to-end.
- Bats test gating pattern (`require_live_destructive()` vs dedicated `KARYON_LIVE_BOOTSTRAP=1` env).
- `docs/flux-hub-spoke.md` front-matter / TOC style.

## Deferred Ideas

No scope-creep ideas surfaced during the discussion. Deferred items are rejected options formally captured in CONTEXT.md §deferred:

- Image automation controllers (v2).
- Org/app-based bootstrap.
- NetworkPolicy-based flux-system isolation.
- GitHub API PAT-scope probe.
- Auto-switch kubectl context.
- Self-rerun idempotency proof.
- sed-redaction wrapper.
- Pre-commit of empty kustomization.yaml.
- Hard-block on Phase 6 gitleaks.
- Phase 4 hub-spoke reconciliation doc content.
- ADR-003 / ADR-004 authoring (Phase 6).
- Flagger / progressive delivery.
- Full Taskfile.yml REPO-05 reorganization (Phase 6).
- Non-`main` branch bootstrap.
