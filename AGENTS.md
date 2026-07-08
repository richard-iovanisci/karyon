# Project Instructions

## Project Purpose

karyon is a reproducible local Kubernetes lab on Windows 11 + WSL2: a Flux
GitOps hub cluster plus spokes (one GPU-enabled) built with k3d, rebuildable
from zero in under 20 minutes. On top of the base lab sits a multi-tenancy
proof of concept on a dedicated `spoke-capsule` cluster: Capsule +
capsule-proxy for tenant isolation, Keycloak (operator-managed) for identity,
and OIDC-wired kubectl/Headlamp access. It serves as the reference
implementation for a multi-tenant platform pattern.

## Setup, Build, And Test

- Setup (fresh box): follow the ten Quick Start steps in `README.md`
  (`install-docker.sh` → `install-nvidia-container-toolkit.sh` →
  `install-tools.sh` → `task preflight`).
- Build + run: `task build-image`, `task create-clusters`,
  `task bootstrap-flux`, `task register-spokes`, `task deploy-examples` —
  or `task rebuild` for the full destructive loop.
- Test: `bats tests/bats/*static*.bats` (the CI gate; cluster-free).
  Live suites need a running lab and are gated by `KARYON_LIVE_TESTS=1`
  (destructive ones by `KARYON_LIVE_TESTS_DESTRUCTIVE=1`).
- Lint: shellcheck over `scripts/`, markdownlint over `**/*.md`,
  kubeconform over `clusters/` + `examples/` (all run in CI).

## Key Directories And Architecture

- `Taskfile.yml` — the only entrypoint surface; every task is a thin
  `bash scripts/<name>.sh` wrapper. Never add inline logic to it.
- `scripts/` — all automation (host setup, lab lifecycle, POC helpers under
  `scripts/poc/{capsule,keycloak}/`). Shared helpers live in
  `scripts/lib/preflight-lib.sh`.
- `clusters/hub-flux/` — Flux source of truth. `flux-system/kustomization.yaml`
  contains sentinel comments (`# FLUX PATCH SURFACE`, `# KARYON SPOKES MOUNT`,
  `# KARYON POC MOUNT`, `# KARYON FLUX LOCKDOWN PATCHES`) that scripts and
  tests grep for — never reword them.
- `pocs/` — GitOps manifests for the Capsule/Keycloak/Headlamp stack on
  spoke-capsule. `pocs/keycloak/spoke/operator/vendored/` is vendored
  upstream YAML — do not hand-edit.
- `examples/` — workloads reconciled into spokes; referenced by relative
  kustomize paths from `clusters/spoke-*/`.
- `tests/bats/` — executable contracts. Static suites pin manifest/script
  shapes; if you change a pinned value, update the suite in the same commit.
- `docs/` — architecture, runbooks, RCAs (`docs/rca/`), ADRs (`docs/adr/`),
  and `docs/backlog.md` (open items, standing invariants, decision log).

## Local Guardrails

- Never commit kubeconfigs, tokens, TLS material, or real secrets; `.env` is
  gitignored and gitleaks gates commits and CI (full-history scan).
- The `.planning/...` path entries in `.gitleaks.toml` are history-only
  allowlist entries for deleted files still present in git history — never
  remove them.
- spoke-capsule is isolated from `task rebuild`/`task destroy`; manage it
  only via `scripts/poc/capsule/` and `task destroy-poc`.
- Spoke-targeted Flux Kustomizations must carry the full `spec.kubeConfig`
  block (secret key `value.yaml`) and an explicit `spec.serviceAccountName`;
  omitting either silently reconciles into the wrong cluster or escalates to
  cluster-admin. See `docs/backlog.md` for the standing invariants.
- CI bats membership is the filename glob `*static*.bats` — renaming a suite
  can silently drop it from the gate.

## Docs And Decisions

- Start with `README.md`, then `docs/architecture.md` (base lab) and
  `docs/architecture-flux-capsule-keycloak.md` (multi-tenancy pattern).
- ADRs live in `docs/adr/`; root-cause analyses in `docs/rca/`; open items
  and the decision log in `docs/backlog.md`.
