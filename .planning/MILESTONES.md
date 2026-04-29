# Milestones

## v0.18 milestone v0.18 — karyon Lab v1 (Shipped: 2026-04-29)

**Phases completed:** 6 phases, 41 plans, 90 tasks

**Key accomplishments:**

- 1. [Rule 1 - Bug] SC1091 shellcheck failure on test_helper.bash dynamic source
- Idempotent Docker Engine installer with content-correct guards for apt repo (M2) and hwclock systemd unit (M2), prerequisites-first section ordering (H3), and jq-merge daemon.json strategy
- Idempotent NVIDIA container toolkit installer with H1 wave-serialization pre-check guard, pinned version 1.19.0-1, three guarded sections, and post-verify that nvidia-ctk structured merge preserved install-docker.sh's daemon.json keys
- Idempotent asdf v0.18.1 Go-binary installer with 8-plugin asdf setup, ~/.karyon/shell-init.sh PATH wiring, and .tool-versions-driven version pinning — H2 chicken/egg fix applied
- prereqs.sh ported to scripts/preflight.sh — sources preflight-lib.sh, delegates PRE-01/02/03 to library functions, upgrades PRE-08 Docker Desktop to fail, adds PRE-04 default-runtime check, and replaces tool list with .tool-versions version-pin loop
- Six new preflight check sections appended to scripts/preflight.sh: .env secrets contract (lib delegation), asdf shim precedence, systemd-resolved stub, powershell.exe/hwclock clock skew, cgroup v2 purity (lib delegation), and trap-cleaned bridge-curl Docker network probe with straggler pre-check
- Five bats test suites covering the five pure-function preflight checks: subshell + function-override mocking for kernel/cgroup tests, mktemp fixtures for file-based tests, all 25 tests passing with shellcheck-clean test_helper
- Surgical fix of CR-01 (jq string-literal bug) and CR-02 (fresh-host daemon.json sequencing violation) in install-docker.sh + install-nvidia-container-toolkit.sh — both scripts now execute cleanly on a fresh WSL2 Ubuntu 24.04 host with no regression to the 25/25 bats suite.
- Four surgical fixes to preflight.sh, preflight-lib.sh, and install-docker.sh closing all UAT gaps from 01-HUMAN-UAT.md Test 4; 25/25 bats tests pass with no regression.
- 12 bats artifacts (11 new + 1 modified) scaffolding IMG-01..06 and CLU-01..06; 13 tests skip green; Phase-1 preflight suite unchanged
- Two-stage k3s+CUDA Dockerfile (BuildKit 1.7-labs) plus the single-source-of-truth image-tag.sh; IMG-01 and IMG-02 bats assertions now run for real
- 1. [Rule 1 - Bug] Plan acceptance criteria undercount literal grep matches produced by the verbatim interface body
- Idempotent docker-build wrapper landed; karyon/k3s-cuda image built and GPU-smoke-verified (RTX 5090 nvidia-smi green end-to-end); IMG-03 and IMG-05 live bats checks active
- Idempotent 3-cluster k3d lab stands up cleanly on k8s-net; spoke-ml reports `nvidia.com/gpu=1`; all three apiserver certs carry the k3d-NAME-server-0 SAN; CLU-01..05 bats checks active.
- Idempotent k3d cluster teardown (delete-clusters.sh) with D-14 cache-defense blocking comment, Section 3 post-run image-survival check, and activated CLU-06/IMG-06 bats assertions including a require_live_destructive double-gate
- go-task v3 stub at repo root wiring three Phase 2 scripts (build-image, create-clusters, delete-clusters) into a `task` CLI surface, completing Phase 2 scope
- Bats contract tests now define the Flux bootstrap script and docs invariants before Wave 1 implementation lands.
- Executable Flux bootstrap wrapper with context safety, env-only PAT handling, health gates, and an idempotent patch-surface marker.
- Flux hub-spoke patch-surface documentation with a concrete kustomize-controller memory patch and corrected NetworkPolicy rationale.
- Taskfile orchestration entry exposing Flux hub bootstrap through `task bootstrap-flux` with a structural four-task verification gate.
- Data-only GitHub env loading plus a guarded fast-forward sync so first-run Flux bootstrap can finish locally.
- Human-gated live proof that `scripts/bootstrap-flux.sh` bootstraps Flux, preserves the patch surface, and reruns idempotently on `k3d-hub-flux`.
- Bats contracts for spoke-registration TDD, covering static artifact shape plus gated live reconciliation proof.
- Static hub-spoke GitOps source of truth with explicit Flux kubeConfig refs and per-spoke falsifier seed manifests.
- Idempotent Flux spoke registration script with RBAC, hub kubeconfig Secret creation, token-safe stdin handling, and credential-layer verification.
- Flux hub-spoke wire-up through the root Kustomization, Taskfile entry, and operational docs with static Bats fully green.
- Live hub-spoke Flux registration proved through idempotent script runs, pushed reconciliation, inventory IDs, and cross-cluster ConfigMap falsifiers.
- Phase 5 Wave 0 Bats contracts for workload deployment, health repair, destructive rebuild wrappers, and live post-rebuild state verification
- GitOps-only podinfo and GPU smoke deployment with canonical examples, relative spoke wiring, and Flux visibility gates
- Hub-only k3d stop/start DNS repair with guarded Flux readiness and Taskfile fix-dns wiring
- Read-only ordered health gate proving clusters, Flux, spoke routing, DNS, GPU capacity, TLS SANs, and workload readiness
- Typed-confirmation destroy and timed strict rebuild wrappers with cache-safe teardown, ordered log markers, and HIGH-1 hub context re-pin
- Final approved destructive rebuild completed in 190 seconds with green health, podinfo, GPU, and live state-checker proofs.
- 8 parse-clean bats test scaffolds (39 tests total) encoding every REPO-02/03/04/05/07 and DOCS-01/02/04/05/06..10 static contract before any implementation lands — Nyquist gate satisfied for Phase 6 Waves 1-3.
- gitleaks 8.30.1 pinned with native git pre-commit hook + .gitignore D-16 expansion + ADR-0001 single-WSL2 docker network — public-repo PAT exposure gate (T-06-PAT-01) operational with 0 historical findings across 227 commits.
- One-liner:
- Authored the two greenfield v1 reference docs that the README will cross-link to: a Mermaid hub-spoke topology and the 3-part k3d GPU contract narrative — both ship in Wave 2 with all 8 bats DOCS-02 + DOCS-04 contracts green.
- Added `preflight:` task entry to Taskfile.yml so the README fresh-clone walkthrough's `task preflight` shortcut resolves to a real entry; REPO-05 thin-wrapper invariant verified, REPO-06 typed-yes confirmation contract preserved at the script level.
- One-liner:
- 5-job parallel CI workflow lands T-06-PAT-01 layer f (post-push gitleaks scan with fetch-depth: 0) — completing the 5-layer secrets defense; all third-party actions pinned to 40-char SHAs; markdownlint config tuned for ADR template + GSD planning artifact ignores.

---
