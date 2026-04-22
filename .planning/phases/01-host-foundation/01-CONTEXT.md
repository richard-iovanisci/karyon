# Phase 1: Host Foundation - Context

**Gathered:** 2026-04-22
**Status:** Ready for planning

<domain>
## Phase Boundary

Deliver a host-layer foundation on Windows 11 + WSL2 Ubuntu 24.04 such that `scripts/preflight.sh` exits `0` on a correctly-configured dev box and exits `1` with an actionable message on any blocker. Scope includes:

- Porting the existing `prereqs.sh` into `scripts/preflight.sh`, extended to cover all 14 PRE-xx checks (current script covers PRE-01..08; must add PRE-09..14).
- Install scripts: `install-docker.sh`, `install-nvidia-container-toolkit.sh`, `install-tools.sh` — all idempotent.
- Config templates: `config/wslconfig`, `config/wsl.conf`.
- Resume-time clock-skew hook: systemd unit that runs `hwclock -s`.
- Docs: `docs/wsl-networking.md` (mirrored → NAT fallback).
- `.tool-versions` pinning kubectl, helm, flux, k3d, task, jq, yq (mikefarah), k9s, asdf (≥0.18 Go rewrite).
- `.env.example` + `.gitignore` narrow slice (pulled in from Phase 6 because PRE-09 depends on them).

Out of scope (owned elsewhere):
- Flux bootstrap, spoke registration, k3d cluster creation (Phases 2–5).
- gitleaks pre-commit, full repo hygiene, ADRs, READMEs (Phase 6).
- Any write to the host Windows side; all changes are inside WSL or are committed templates.

</domain>

<decisions>
## Implementation Decisions

### WSL2 Networking Posture
- **D-01:** Preflight detects mirrored-mode networking and **hard-fails** (exit 1) with a pointer to `docs/wsl-networking.md`. NAT is the v1 mandate; mirrored is documented fallback only, never silently tolerated.
- **D-02:** Mirrored detection uses the **IP-subnet heuristic** — if any non-`lo` interface's IPv4 subnet overlaps the Windows host subnet (e.g., 192.168.x.x matching a host NIC), classify as mirrored. Simple, small false-positive surface on unusual home networks.
- **D-03:** `config/wslconfig` template pins `networkingMode=NAT` **explicitly** (not implicit-default) so the decision is visible to a future reader. A commented-out `# networkingMode=mirrored` line appears with a one-line note pointing to `docs/wsl-networking.md` before any user would uncomment it.
- **D-04:** PRE-14 mirrored-mode bridge-curl probe (two containers on `k8s-net` curl each other by Docker DNS) remains a **belt-and-suspenders** check — runs even after the mirrored detection passes, to catch any custom-network breakage that isn't mirrored-specific.

### Install-Script Architecture
- **D-05:** All three install scripts use the **guarded-sections pattern** — every logical step is wrapped in a state check and logs `already done, skipping: <what>` or `installing: <what>`. The log becomes a live audit of the box's state; not just a fast no-op. This matches the `prereqs.sh` reporting vibe (pass/warn/fail counters).
- **D-06:** asdf PATH precedence is enforced by **writing a dedicated init file**: `install-tools.sh` creates `~/.karyon/shell-init.sh` containing the asdf sourcing + PATH prepend, then idempotently appends a single `[ -f ~/.karyon/shell-init.sh ] && source ~/.karyon/shell-init.sh` line to `~/.bashrc` (guarded by a grep to avoid duplicates). Clean separation, easy to diff, easy to decommission.
- **D-07:** **bash only** for shell-init. Project scripts all use `#!/usr/bin/env bash`; Ubuntu 24.04 default shell is bash. zsh/fish users can source the init file manually — out of scope to auto-configure.
- **D-08:** HOST-06 clock-resume hook lives as a **committed systemd unit template** at `config/hwclock-resume.service`. `install-docker.sh` (or a small step inside it) copies the unit into `/etc/systemd/system/`, runs `systemctl daemon-reload`, and enables it. Idempotent because `systemctl enable` is idempotent. Unit triggers off WSL resume (`sleep.target` wake).

### .env + .env.example Boundary
- **D-09:** `.env.example` ships in **Phase 1** (pulled forward from Phase 6). Rationale: `scripts/preflight.sh` enforces the contract defined by `.env.example` — shipping one without the other leaves a hole. ROADMAP.md already notes Phase 1 is parallelizable with Phase 6 on exactly this artifact. REPO-04 (gitleaks pre-commit) stays in Phase 6.
- **D-10:** Preflight validates `.env` at **presence + non-empty per key** level — file exists at repo root, and each of `GITHUB_OWNER`, `GITHUB_REPO`, `GITHUB_TOKEN` is set to a non-empty value. Does NOT validate token format, prefix, or call GitHub. Keeps preflight read-only and offline-safe.
- **D-11:** `.env.example` carries **placeholder values with inline comments** — e.g., `GITHUB_OWNER=your-github-username`, `GITHUB_TOKEN=ghp_REPLACE_WITH_PAT_WITH_repo_SCOPE`. Each key has a `#` comment explaining purpose and pointing at PAT-generation instructions. Self-documenting; `cp .env.example .env` yields a working scaffold.
- **D-12:** Phase 1 **updates `.gitignore`** with the narrow slice needed for PRE-09: at minimum `.env`, `.env.local`, `.env.*.local`. Rationale: asking the user to create a secret-bearing `.env` without ignoring it is a foot-gun. Broader `.gitignore` hygiene (REPO-02) remains Phase 6.

### Claude's Discretion
These areas were not explicitly discussed; planner/researcher decide:
- **Preflight strictness & output format** — e.g., which warnings promote to failures, `--json`/`--quiet` flags. Recommended default: keep the current permissive model (warnings non-fatal) plus hard-fail on the new PRE-08..14 blockers; no flags in v1 unless planning surfaces a need.
- `daemon.json` patching strategy (overwrite vs. jq-merge) when `install-docker.sh` adds `default-runtime: nvidia` + `dns` keys. Preference: jq-merge so an existing daemon.json is preserved; overwrite only if the file is absent.
- Exact `dns` array content for `/etc/docker/daemon.json` — pick sensible public resolvers (e.g., `1.1.1.1`, `8.8.8.8`) unless research surfaces a project-specific choice.
- asdf plugin sourcing (official vs. community plugins) per tool — researcher picks.
- Preflight's cgroup-v2 purity check (PRE-13) and systemd-resolved 127.0.0.53 probe (PRE-11) implementation detail.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project-level specs
- `.planning/PROJECT.md` — Core value, locked architectural decisions (ADR-001..005 rationale), Context section with prior-work notes on `prereqs.sh`, pinned versions, public-repo secrets posture.
- `.planning/REQUIREMENTS.md` §Host Foundation, §Tool Pinning & Install, §Preflight Gate — the 24 REQ-IDs in this phase with exact acceptance language.
- `.planning/ROADMAP.md` §Phase 1 — goal, success criteria, parallelization note with Phase 6, risk register.

### Existing code to port / extend
- `prereqs.sh` — current preflight checker at repo root. Covers PRE-01 through PRE-08. Must be ported to `scripts/preflight.sh` and extended with PRE-09..14. **Do not rewrite from scratch** — the helper functions (`pass`/`warn`/`fail`/`info`/`section`), colored output, summary counters, and exit-code logic are the baseline.
- `starter.md` — original vision doc; consistent with current PROJECT.md. Useful for decisions about repo structure and the `docs/adr/` layout that Phase 1 does not touch but should not contradict.

### External references (no URLs — agents must fetch current docs at planning time)
- asdf v0.18+ (Go rewrite) PATH-migration behavior — the shim path moved from `~/.asdf/shims` vs older plugin shim paths; researcher must confirm the exact shim dir and shell-init syntax for asdf ≥0.18.
- WSL2 `.wslconfig` and per-distro `/etc/wsl.conf` schemas — Microsoft docs for the `[wsl2]` and `[boot]` / `[network]` sections.
- NVIDIA container toolkit install procedure for Ubuntu 24.04 — `nvidia-ctk runtime configure --runtime=docker` behavior and idempotency.
- Docker Engine install on Ubuntu 24.04 (no Docker Desktop) — apt repo + signing key procedure; daemon.json `default-runtime` + `dns` schema.
- k3d GPU contract (3-part) — relevant for consistency even though k3d setup lands in Phase 2; preflight must verify the Docker half of the contract (nvidia runtime registered).

If a researcher or planner discovers an additional ref during their pass (e.g., a known systemd-resolved interaction, a specific asdf plugin, a Microsoft WSL bug tracker), they should add it to this section via the standard research/planning flow — not silently use it.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `prereqs.sh` — full implementation of PRE-01 to PRE-08 in bash, including colored output, section headers, and a pass/warn/fail summary with exit-code policy (0 if no fails, 1 otherwise). Keep the `have()`, `pass()`, `warn()`, `fail()`, `info()`, `section()` helpers verbatim. Add new sections for PRE-09..14.
- `starter.md` — documents the originally-desired repo structure. Phase 1 creates the top-level directories it references (`scripts/`, `config/`, `docs/`) but not yet `clusters/`, `images/`, `examples/`.

### Established Patterns
- **Bash with `set -u` (not `-e`)** — `prereqs.sh` intentionally runs to completion and collects failures rather than exiting on first error. Install scripts and preflight should follow this pattern so the user sees ALL blockers in one pass.
- **ANSI colors gated on `[[ -t 1 ]]`** — current script degrades to plain text when stdout is not a TTY (CI-safe). Keep this pattern.
- **`have() { command -v "$1" >/dev/null 2>&1; }`** — used throughout for tool presence; reuse.

### Integration Points
- `scripts/preflight.sh` is the only surface other phases and `Taskfile.yml` call into from Phase 1. Its exit code and error messages are the API.
- `~/.karyon/shell-init.sh` is a new path established here; future phases should source from it, not duplicate PATH logic.
- `/etc/docker/daemon.json` and `/etc/systemd/system/hwclock-resume.service` are host-level side effects; later phases assume these exist.

</code_context>

<specifics>
## Specific Ideas

- Reuse the `prereqs.sh` helper vocabulary (`pass`/`warn`/`fail`/`info`/`section`) verbatim in `scripts/preflight.sh` for consistency.
- Preflight's blocker messages should tell the user *what to run to fix it* (e.g., "Ubuntu not 24.04 → install from Microsoft Store and re-provision"; "docker daemon not reachable → run install-docker.sh; ensure user in docker group; relog"; ".env missing → cp .env.example .env && edit").
- mirrored → NAT remediation in `docs/wsl-networking.md` should include the **exact `.wslconfig` delta** (1-line change) plus the `wsl --shutdown` dance, so the fix is a 30-second operation.
- `.env.example` keys must stay alphabetical / grouped for easy diff when Phase 3 adds more Flux-bootstrap inputs.

</specifics>

<deferred>
## Deferred Ideas

- **Preflight `--json` / `--quiet` output modes** — not needed for v1 manual use; defer until CI integration work surfaces the need.
- **Preflight token-format sanity checks** (ghp_/github_pat_/gho_ prefixes) — brittle against GitHub changing prefixes; defer unless it becomes a real failure mode.
- **zsh / fish shell support** for the asdf PATH init — out of Windows+WSL+Ubuntu-24.04 scope.
- **GitHub API reachability probe from preflight** — keep preflight read-only and offline-safe; leave connectivity checks to `bootstrap-flux.sh` (Phase 3).
- **gitleaks pre-commit hook** — belongs to Phase 6 (REPO-04); Phase 1 only touches the narrow `.gitignore` slice that PRE-09 requires.
- **Full REPO-01..07 repo hygiene** — stays in Phase 6.
- **ADR drafts** — ADR-001 (single WSL2 distro) and ADR-005 (k3s/CUDA pins) are parallelizable with Phase 1 per ROADMAP but assigned to Phase 6; no scope creep here.

</deferred>

---

*Phase: 01-host-foundation*
*Context gathered: 2026-04-22*
