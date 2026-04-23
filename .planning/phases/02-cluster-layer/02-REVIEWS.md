---
phase: 2
reviewers: [codex]
reviewed_at: 2026-04-23T14:18:00Z
plans_reviewed:
  - 02-01-PLAN.md
  - 02-02-PLAN.md
  - 02-03-PLAN.md
  - 02-04-PLAN.md
  - 02-05-PLAN.md
  - 02-06-PLAN.md
  - 02-07-PLAN.md
reviewer_runtime: codex-cli 0.123.0-alpha.5 (gpt-5.4, reasoning xhigh)
self_skipped: claude (running inside Claude Code CLI)
---

# Cross-AI Plan Review — Phase 2

## Codex Review

### Top Findings

- `HIGH` `02-05-PLAN.md`: the `create-clusters.sh` preflight gate appears to conflict with D-09/D-10 idempotency. Phase 1 preflight is described as flagging existing k3d/network residue, so a rerun can fail before the script reaches its own skip/drift logic.
- `HIGH` `02-05-PLAN.md`: D-09 says existing clusters are verified for image, API port, and network, but the proposed helper only checks image and network. Port drift, missing `--gpus all`, and other create-time drift can be misclassified or missed.
- `MEDIUM` `02-06-PLAN.md` and `02-07-PLAN.md`: the live `delete-clusters` bats test is destructive and can make full-suite success depend on file order. That is fragile for `KARYON_LIVE_TESTS=1 bats tests/bats/ --tap`.
- `MEDIUM` `02-01-PLAN.md`: the verification uses `bash -n` on `.bats` files. `@test` syntax is not valid plain bash syntax, so Wave 0 verification is likely wrong as written.
- `MEDIUM` `02-03-PLAN.md`: the plan explains the user-approved `v0.17.4` override well, but the canonical requirement still says `v0.19.0+`. That leaves traceability inconsistent unless the deviation is formally recorded.

### 02-01-PLAN.md

**Summary:** Good scaffolding and coverage mapping, but the verification mechanics need tightening.

- **Strengths**
  - Strong REQ-to-test traceability from day one.
  - Correct instinct to separate static vs live-gated tests early.
- **Concerns**
  - `MEDIUM` `bash -n` on `.bats` files is invalid for normal Bats syntax.
  - `LOW` The live-gate accounting is inconsistent: mixed-mode files do not match the "require_live in setup for 8 of 11 files" wording.
- **Suggestions**
  - Replace `bash -n` checks with `bats --tap` plus file-existence/load checks.
  - Reword the live-gate acceptance criteria to count live tests, not files.
- **Risk Assessment:** `MEDIUM` — the scaffolding is useful, but the current verification can fail for the wrong reason.

### 02-02-PLAN.md

**Summary:** Solid foundation plan with good single-source-of-truth discipline around image tags and version pins.

- **Strengths**
  - D-06 is implemented cleanly through `image-tag.sh`.
  - The Dockerfile is explicit, reproducible, and aligned to the research artifact.
- **Concerns**
  - `LOW` `image-tag.sh` is brittle to Dockerfile formatting changes because it parses with `grep`/`cut`.
  - `LOW` The Dockerfile intentionally references files that do not exist yet; valid by dependency order, but easy to misuse outside the planned sequence.
- **Suggestions**
  - Add a short comment in the Dockerfile or summary that the file is not buildable until 02-03 lands.
  - Consider a slightly stricter parser in `image-tag.sh` only if the Dockerfile is expected to evolve structurally.
- **Risk Assessment:** `LOW` — good plan, low execution risk if the wave ordering is respected.

### 02-03-PLAN.md

**Summary:** Technically coherent and well-researched, but the requirement override needs a cleaner source-of-truth story.

- **Strengths**
  - The `config.toml.tmpl` approach is minimal and defensible.
  - Device-plugin manifest choices are explicit rather than implied.
- **Concerns**
  - `MEDIUM` REQ-IMG-04 still says `v0.19.0+` while implementation pins `v0.17.4`.
  - `LOW` Dockerfile ARG pin and manifest image pin can still drift because substitution is manual.
- **Suggestions**
  - Record the `v0.17.4` deviation in a canonical phase decision artifact, not only in plan prose.
  - If keeping manual dual pins, add a simple static check that compares Dockerfile ARG and manifest tag text.
- **Risk Assessment:** `MEDIUM` — implementation looks sound, but traceability is weaker than it should be.

### 02-04-PLAN.md

**Summary:** Reasonable build wrapper plan, though the environment gate is a bit stricter than the actual build path.

- **Strengths**
  - Clean separation between artifact definition and artifact build.
  - Good use of `image-tag.sh` instead of hard-coding the tag again.
- **Concerns**
  - `MEDIUM` The script checks `docker buildx version` but uses `docker build`; that can reject environments where BuildKit works but `buildx` is not exposed as expected.
  - `LOW` The build script proves the image builds, but not that k3s actually auto-registers the `nvidia` runtime at runtime.
- **Suggestions**
  - Make the gate "BuildKit-capable docker" rather than specifically "buildx present", or let the build itself be the capability test.
  - Keep the post-build runtime smoke checks mandatory, not optional.
- **Risk Assessment:** `MEDIUM` — mostly good, but the gating logic may be stricter than necessary.

### 02-05-PLAN.md

**Summary:** This is the load-bearing plan and it is strong overall, but it also contains the biggest correctness gaps.

- **Strengths**
  - Correctly treats `--tls-san ... @server:*` plus D-13 SAN verification as non-negotiable.
  - Serial cluster creation is pragmatic and appropriate for this lab.
- **Concerns**
  - `HIGH` Full preflight at the top likely breaks idempotent reruns if preflight flags existing clusters/network as residue.
  - `HIGH` Existing-cluster drift verification omits API port checks even though D-09 requires them.
  - `MEDIUM` Existing-cluster drift verification also omits GPU-related drift for `spoke-ml`.
  - `MEDIUM` SAN probing has no retry/backoff; a transient startup race can look like the k3d #1613 failure mode and trigger deletion.
- **Suggestions**
  - Either add a preflight mode that tolerates expected existing cluster/network state, or narrow the gate to tool/runtime prerequisites only.
  - Verify API port on the serverlb/load balancer container and verify `DeviceRequests` or an equivalent GPU signal on `spoke-ml`.
  - Add a bounded retry loop around the SAN probe and, ideally, a `kubectl get nodes`/GPU-capacity wait for `spoke-ml`.
- **Risk Assessment:** `HIGH` — this plan is central to the phase goal, and the current idempotency/drift gaps are meaningful.

### 02-06-PLAN.md

**Summary:** The teardown logic is disciplined and aligned to the SLO, but the verification strategy is fragile.

- **Strengths**
  - Excellent defense-in-depth around "no prune".
  - Clear separation of cluster delete, network delete, and cache-survival verification.
- **Concerns**
  - `MEDIUM` The plan's live checkpoint depends on clusters existing from 02-05, but `depends_on` does not include 02-05.
  - `MEDIUM` The destructive live bats test can invalidate later live tests or full-suite runs depending on execution order.
  - `LOW` Image-tag survival is a useful proxy, but not a perfect guarantee of BuildKit cache survival.
- **Suggestions**
  - Add `02-05` as an explicit dependency for the live verification path, or split implementation from live validation.
  - Exclude the destructive test from the default full live suite, or recreate clusters in a controlled follow-up step.
- **Risk Assessment:** `MEDIUM` — script design is good, but execution flow and test ordering need refinement.

### 02-07-PLAN.md

**Summary:** Appropriate minimal stub, with good scope control.

- **Strengths**
  - Correctly avoids premature `destroy`/`rebuild` task creep.
  - Delegates to scripts instead of duplicating logic.
- **Concerns**
  - `LOW` `task --list` expecting exactly three visible tasks is brittle once the repo grows.
- **Suggestions**
  - Verify presence of the three required tasks rather than total count if this check will live beyond Phase 2.
- **Risk Assessment:** `LOW` — small plan, low complexity, good scope boundary.

### Overall Risk Assessment

`MEDIUM-HIGH`. The plan set is thoughtful, traceable, and mostly complete, but Phase 2 success depends heavily on `02-05`, and that plan currently has two material gaps: the preflight/idempotency conflict and incomplete drift verification for existing clusters. If those are fixed, the overall phase risk drops to `MEDIUM`.

---

## Consensus Summary

> Single-reviewer pass (codex). No consensus to compute against other reviewers — treat findings as one independent perspective. Re-run with `--all` or additional `--<cli>` flags to get adversarial cross-check.

### Single-Reviewer Strengths
- Strong REQ-to-test traceability (02-01)
- D-06 single-source-of-truth via `image-tag.sh` is clean (02-02)
- `--tls-san @server:*` + D-13 SAN verification correctly treated as non-negotiable (02-05)
- Defense-in-depth on "no prune" is excellent (02-06)
- Plan scope control is well-disciplined (02-07)

### Top Concerns to Address Before Execution
1. **HIGH (02-05):** Preflight-vs-idempotency conflict — preflight rejecting existing residue would break the second `scripts/create-clusters.sh` run before reaching D-09 skip-if-exists logic. Either narrow preflight to tool-runtime checks only, or add a "tolerant" mode.
2. **HIGH (02-05):** Drift verification gap — D-09 requires checking image, API port, and network; current helper only checks image+network. Missing `--gpus all` drift on `spoke-ml` would silently let a re-run advertise the wrong runtime contract.
3. **MEDIUM (02-01):** `bash -n` on `.bats` files is wrong — bats `@test` is not valid bash syntax. Use `bats --tap` or `bats --count` instead, or grep for the `@test` headers and validate file structure.
4. **MEDIUM (02-03):** REQ-IMG-04 text says "v0.19.0+" but plans pin v0.17.4. The user approval is in the discussion log, not in REQUIREMENTS.md or any phase decision artifact. Add a formal `D-15` decision in CONTEXT.md or amend REQ-IMG-04 wording to "current stable (v0.17.4)".
5. **MEDIUM (02-04):** `docker buildx version` gate may be stricter than necessary. Either gate on BuildKit capability, or let the build itself be the capability test.
6. **MEDIUM (02-05):** SAN probe has no retry/backoff — transient startup race could trigger a false-positive cluster delete.
7. **MEDIUM (02-06):** Plan 02-06's live test depends on a cluster existing from 02-05, but `depends_on` doesn't list 02-05. Add the dependency, or split implementation from live validation.
8. **MEDIUM (02-06+02-07):** Destructive live `delete-clusters` bats test order-dependent in the full live suite — exclude from default live runs or recreate clusters in a controlled follow-up.

### Divergent Views
N/A — single reviewer.

---

## How to Use This Review

To incorporate feedback into planning:

```
/clear
/gsd-plan-phase 2 --reviews
```

This will replan Phase 2 with the review feedback as context. The planner will adjust 02-05 (preflight gate, drift verification, SAN retry), 02-01 (bats verification mechanic), 02-03 (formal v0.17.4 decision artifact), 02-04 (buildx gate), and 02-06 (depends_on + live-suite exclusion).

Alternatively, address the HIGH findings inline in the affected plans before execution (`02-05-PLAN.md` is the load-bearing one), then re-run the plan-checker only on the modified files.
