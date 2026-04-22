# Phase 1: Host Foundation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-22
**Phase:** 01-host-foundation
**Areas discussed:** WSL mirrored-mode posture, Install-script idempotency pattern, .env + .env.example boundary

---

## Gray Area Selection

Four gray areas were offered. User selected three:

| Option | Description | Selected |
|--------|-------------|----------|
| Preflight strictness & output | Warning→blocker promotion rules, output format (colored/JSON/quiet) | |
| WSL mirrored-mode posture | NAT vs mirrored, detection vs probe | ✓ |
| Install-script idempotency pattern | Guarded vs check-and-bail vs always-run; asdf PATH strategy | ✓ |
| .env + .env.example boundary with Phase 6 | How strict Phase 1 is; who ships .env.example | ✓ |

Preflight strictness & output routed to Claude's Discretion in CONTEXT.md.

---

## WSL mirrored-mode posture

### Q1: How should preflight treat WSL2 mirrored networking mode?

| Option | Description | Selected |
|--------|-------------|----------|
| Detect mirrored → hard-fail | Preflight requires NAT mode; exit 1 with pointer to `docs/wsl-networking.md` | ✓ |
| Detect mirrored → warn only | Warn + pointer, keep running; cluster create may still fail later | |
| Assume NAT, skip detection | No active detection; rely solely on PRE-14 bridge-curl probe | |

**User's choice:** Hard-fail. Captured as D-01.
**Notes:** Matches the "all bugs cluster in mirrored + custom networks" signal from PROJECT.md Context.

### Q2: Can preflight reliably detect mirrored mode from inside WSL?

| Option | Description | Selected |
|--------|-------------|----------|
| IP heuristic (Windows-host subnet overlap) | Simple; small false-positive risk on unusual home networks | ✓ |
| Probe /proc/net + ip route signatures | Routing-table fingerprinting; more robust, more code | |
| Only trust bridge-curl probe | No classification; PRE-14 is the sole defense | |

**User's choice:** IP heuristic. Captured as D-02.

### Q3: Should `config/wslconfig` set `networkingMode=NAT` explicitly, or rely on WSL default?

| Option | Description | Selected |
|--------|-------------|----------|
| Explicit networkingMode=NAT | Visible decision in committed config; commented-out mirrored fallback with pointer | ✓ |
| Leave implicit (WSL default is NAT) | Shorter template; decision invisible to future readers | |

**User's choice:** Explicit NAT. Captured as D-03.

---

## Install-script idempotency pattern

### Q1: What idempotency pattern for install-docker.sh / install-nvidia-container-toolkit.sh / install-tools.sh?

| Option | Description | Selected |
|--------|-------------|----------|
| Guarded sections with explicit logging | Each step checks state + logs "already done, skipping" or "installing" | ✓ |
| Check-then-bail early exit | Top-of-script state check; single-line no-op on reruns | |
| Always run, trust tool idempotency | apt-get, usermod -aG, nvidia-ctk runtime configure are natively idempotent | |

**User's choice:** Guarded sections. Captured as D-05.
**Notes:** Matches `prereqs.sh` reporting style (pass/warn/fail counters); log becomes a live audit.

### Q2: How should install-tools.sh ensure asdf shims come before /usr/bin and /usr/local/bin in PATH?

| Option | Description | Selected |
|--------|-------------|----------|
| Dedicated init file + one-line hook | `~/.karyon/shell-init.sh` + idempotent `source` line in `~/.bashrc` | ✓ |
| Edit ~/.bashrc directly | Append with begin/end marker comments; pollutes rc file | |
| Document-only; preflight validates | User pastes snippet manually; breaks idempotent/rerun-safe contract | |

**User's choice:** Dedicated init file. Captured as D-06.

### Q3: Which shells does install-tools.sh need to support?

| Option | Description | Selected |
|--------|-------------|----------|
| bash only | Ubuntu 24.04 default; all project scripts are bash | ✓ |
| bash + zsh | Detect current shell; target both rc files | |
| Detect $SHELL and adapt | Auto-detect login shell; most flexible, biggest test surface | |

**User's choice:** bash only. Captured as D-07.

### Q4: Where does the `hwclock -s` resume hook (HOST-06) live?

| Option | Description | Selected |
|--------|-------------|----------|
| Dedicated systemd unit committed under `config/`, installed by `install-docker.sh` | `config/hwclock-resume.service` → `/etc/systemd/system/`; systemctl enable is idempotent | ✓ |
| Dedicated `install-hwclock-hook.sh` script | Separate small installer; cleaner concern separation | |
| Fold into `install-tools.sh` | Treat as baseline tooling; mixes concerns | |

**User's choice:** Committed unit + install via install-docker.sh. Captured as D-08.

---

## .env + .env.example boundary with Phase 6

### Q1: Phase 6 owns .env.example (REPO-03). Phase 1's PRE-09 needs .env verified. How to resolve?

| Option | Description | Selected |
|--------|-------------|----------|
| Pull .env.example into Phase 1 | Preflight enforces contract that .env.example defines; ship together. Leave REPO-04 gitleaks in Phase 6 | ✓ |
| Phase 1 hard-fails; Phase 6 authors .env.example | Strictest discipline; worse first-run UX | |
| Phase 1 warns-only until Phase 3 | Softest; reinterprets PRE-09's "fail fast" language | |

**User's choice:** Pull .env.example into Phase 1. Captured as D-09.

### Q2: Preflight .env validation level?

| Option | Description | Selected |
|--------|-------------|----------|
| Presence + non-empty per key | File exists; GITHUB_OWNER/REPO/TOKEN all set to non-empty values | ✓ |
| Presence-only (any value) | Accepts empty strings; lets garbage through | |
| Presence + format sanity checks | Handle shape, repo pattern, token prefix; brittle if GitHub changes | |

**User's choice:** Presence + non-empty. Captured as D-10.
**Notes:** Keeps preflight read-only and offline-safe; no GitHub API calls.

### Q3: .env.example placeholder values or empty?

| Option | Description | Selected |
|--------|-------------|----------|
| Placeholder values with inline comments | Self-documenting; `cp .env.example .env` yields working scaffold | ✓ |
| Empty values | Safer against committing example-as-real-value; less clear | |

**User's choice:** Placeholder values. Captured as D-11.

### Q4: Where does .env.example live, and should .gitignore updates happen in Phase 1?

| Option | Description | Selected |
|--------|-------------|----------|
| Repo root + Phase 1 updates .gitignore | Narrow slice: `.env`, `.env.local`, `.env.*.local` added in Phase 1; broader REPO-02 stays Phase 6 | ✓ |
| Repo root, .gitignore to Phase 6 | Mild foot-gun: user creates secret-bearing .env without ignoring it | |

**User's choice:** Repo root + narrow .gitignore update. Captured as D-12.

---

## Claude's Discretion

User did not select "Preflight strictness & output" for discussion. Captured as Claude's Discretion in CONTEXT.md:
- Which warnings promote to blockers (beyond the explicit PRE-01..14 requirements)
- Output format flags (`--json`, `--quiet`) — deferred

Additional planner/researcher calls:
- `daemon.json` merge strategy (jq-merge preferred over overwrite if existing file found)
- `dns` array content (public resolvers like 1.1.1.1, 8.8.8.8 unless research surfaces a better choice)
- asdf plugin sourcing (official vs. community, per tool)
- Preflight cgroup-v2 check (PRE-13) and systemd-resolved 127.0.0.53 probe (PRE-11) implementation details

## Deferred Ideas

- Preflight `--json` / `--quiet` output modes
- Preflight token-format sanity checks
- zsh / fish shell support
- GitHub API reachability probe
- gitleaks pre-commit hook (Phase 6)
- Full REPO-01..07 repo hygiene (Phase 6)
- ADR drafts — parallelizable per ROADMAP but assigned to Phase 6
