---
phase: 1
reviewers: [codex]
reviewed_at: 2026-04-22
plans_reviewed: [01-01-PLAN.md, 01-02-PLAN.md, 01-03-PLAN.md, 01-04-PLAN.md, 01-05-PLAN.md, 01-06-PLAN.md, 01-07-PLAN.md]
---

# Cross-AI Plan Review — Phase 1 Host Foundation

## Codex Review

**Model:** gpt-5.4 (OpenAI Codex v0.123.0-alpha.5, reasoning effort: xhigh)

### Summary

The planning work is thoughtful and much better than a generic scaffold, but I would not approve it as-is for execution. The biggest blockers are execution-order hazards in Wave 2, an internal contradiction in the `asdf`/`.tool-versions` design, and a PRE-14 implementation that breaks the stated "read-only preflight" contract. If those are fixed, the phase is salvageable; without them, the plans are likely to produce flaky installs and a preflight that can fail for the wrong reasons.

### Strengths

- Reusing `prereqs.sh` instead of rewriting preflight is the right call. `01-05` keeps the proven helper vocabulary, output style, and exit semantics while extending coverage.
- Pulling `.env.example` and the narrow `.gitignore` slice into Phase 1 is a sound dependency decision. `01-01` correctly recognizes that PRE-09 is impossible to enforce cleanly without shipping the contract first.
- Separating Docker, NVIDIA, and toolchain setup into distinct scripts is a good shape for the repo. `01-02`, `01-03`, and `01-04` each have a clear responsibility and are easy to reason about independently.
- The plans consistently try to make remediation actionable. The preflight failure text in `01-05` and `01-06` generally tells the user what to run next instead of just reporting state.
- The validation docs correctly distinguish live-only checks from unit-testable logic. `01-VALIDATION.md` is honest about what cannot be CI-proven on non-GPU hardware.

### Concerns

- **HIGH — Wave 2 ordering is unsafe.** `01-03` says "Run after install-docker.sh" but only depends on `01-01`, so it can execute in parallel with `01-02`. Both plans touch `/etc/docker/daemon.json` and restart Docker (`01-02` Section 6, `01-03` Section 3), which makes final state timing-dependent.
- **HIGH — `asdf` design is internally broken.** `01-01` puts `asdf 0.18.1` into `.tool-versions`, but `01-04` never adds an `asdf` plugin and then runs `asdf list`/`asdf install` across every `.tool-versions` entry. On a fresh box that likely fails or causes reruns to keep thinking something is missing.
- **HIGH — `install-docker.sh` uses `jq` before any plan guarantees `jq` exists.** `01-02` installs only `ca-certificates` and `curl` up front, then uses `jq` for the daemon merge. Since `01-04` is parallel rather than a prerequisite, a clean-box execution can fail here.
- **HIGH — PRE-14 is not read-only.** `01-06` creates/removes Docker networks and containers for the bridge probe. That directly contradicts the phase boundary and PRE-01 language that describe `scripts/preflight.sh` as read-only.
- **HIGH — Mirrored-mode detection in `01-05` does not match locked decision D-02.** The context says subnet-overlap heuristic; the plan implements "default gateway must be in 172.16/12". That is a materially different algorithm with different false-positive/false-negative behavior.
- **HIGH — bats loader path is wrong.** `01-01` creates `tests/bats/test_helper.bash`, but `01-07` has every suite do `load '../test_helper'`, which resolves to `tests/test_helper`, not `tests/bats/test_helper`. Those suites will not even start.
- **MEDIUM — PRE-12 is effectively optional in normal use.** `01-06` turns "cannot read hwclock without sudo" into a warning, so a standard non-sudo preflight run can still exit `0` without ever enforcing the clock-skew requirement.
- **MEDIUM — Idempotency story is overstated.** Many guards are "file exists" checks, not "file content is correct" checks: Docker repo/key in `01-02`, NVIDIA repo/key in `01-03`, shell-init in `01-04`, and systemd unit enablement in `01-02`. Reruns will skip drift instead of converging state.
- **MEDIUM — Shellcheck is assumed everywhere but installed nowhere.** `01-VALIDATION.md` still marks it missing, and every plan's verify block uses it. The advertised verification path is incomplete on a fresh dev box.
- **MEDIUM — bats tests are mostly nominal.** `01-07` often reimplements trivial shell fragments inside the test files instead of exercising the actual preflight code paths, so they provide little regression value.

### Suggestions

- Change `01-03` to depend on `01-02`, and give exactly one plan ownership of the final `daemon.json` shape. The cleanest version: `01-02` installs Docker only, `01-03` runs `nvidia-ctk`, then performs the single final jq-merge for `runtimes.nvidia`, `default-runtime`, and `dns`.
- Fix the `asdf` contradiction. Either remove `asdf` from `.tool-versions`, or keep it there as metadata but explicitly skip it in `asdf list`/`asdf install` and validate it separately as a standalone binary.
- Add explicit prerequisites where they are actually needed. `01-02` should install `jq` and likely `gpg`; Wave 1 should install `shellcheck` if later verify blocks depend on it.
- Keep preflight truly read-only. Move PRE-14 into a separate diagnostic script/task, or at minimum make it opt-in rather than part of the default pass/fail gate.
- Replace the 172/12 gateway heuristic with the locked D-02 overlap heuristic, or revise the decision record to match the simpler algorithm before implementation. Right now the plan and the decision log disagree.
- Fix bats loading to `load './test_helper'` or `load 'test_helper'`, then refactor preflight checks into callable functions so the tests can exercise real implementation instead of copy-pasted shell snippets.
- Rework PRE-12 so it can enforce the requirement without sudo friction. Comparing WSL time to Windows time via `powershell.exe` from inside WSL is a better fit than silently downgrading the check to a warning.

### Risk Assessment

**Overall risk: HIGH.** The plan structure is promising, but the current version has multiple execution-time failure modes that are likely to appear on the first real run, not edge cases. The phase can be made solid, but it needs a dependency/order pass and a few design corrections before execution starts.

---

## Consensus Summary

Only one reviewer (Codex / gpt-5.4) was invoked — Claude was skipped for independence (running inside Claude Code), and no other CLI was requested. The findings below are Codex's alone and should be treated as a single-reviewer signal, not cross-AI consensus.

### Agreed Strengths

*(N/A — single reviewer)*

- Correct instinct to port `prereqs.sh` rather than rewrite
- Pulling `.env.example` + narrow `.gitignore` forward from Phase 6 is a justified dependency decision
- Clean separation across install-docker / install-nvidia / install-tools
- Actionable remediation messages in preflight failure paths

### Agreed Concerns (single reviewer, but all 6 are unambiguous and actionable)

1. **Wave 2 daemon.json race** (HIGH) — Plans 01-02 and 01-03 both write `/etc/docker/daemon.json` and both restart Docker; they run in the same wave, parallel, with timing-dependent final state. Fix: serialize — Plan 03 depends_on Plan 02; one plan owns the final jq-merge.
2. **asdf self-pin contradiction** (HIGH) — `.tool-versions` pins `asdf 0.18.1` but `install-tools.sh` tries to `asdf install` it, which is impossible (asdf can't install itself via its own plugin protocol). Fix: install asdf as a standalone binary in install-tools.sh before any `asdf install` calls, OR remove the asdf self-pin.
3. **`jq` prerequisite missing before `install-docker.sh`** (HIGH) — the daemon.json merge uses `jq` but `jq` is only installed in Plan 04 (parallel). Clean-box execution of Wave 2 will fail.
4. **PRE-14 breaks read-only contract** (HIGH) — creates/removes Docker networks and containers inside preflight. Fix: move to a separate `scripts/diagnose-wsl-networking.sh` OR gate behind `--deep` flag and skip by default.
5. **Mirrored-mode detection drift from D-02** (HIGH) — plan implements "gateway in 172.16/12" but D-02 locks in "IP-subnet overlaps Windows host subnet." Pick one; update the other.
6. **bats `load '../test_helper'` path bug** (HIGH) — resolves to `tests/test_helper`, not `tests/bats/test_helper`. Every suite fails to load. Fix: `load 'test_helper'` (bats resolves relative to the suite file).

### Divergent Views

*(N/A — single reviewer)*

---

## Next Steps

To incorporate this feedback, run:

```
/gsd-plan-phase 1 --reviews
```

This re-invokes the planner in revision mode with `01-REVIEWS.md` as input, targeting the 6 HIGH and 4 MEDIUM findings above.
