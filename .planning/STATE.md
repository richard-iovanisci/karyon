---
gsd_state_version: 1.0
milestone: v0.18
milestone_name: milestone
status: executing
stopped_at: Phase 6 context gathered
last_updated: "2026-04-28T20:02:08.921Z"
last_activity: 2026-04-28 -- Phase 06 execution started
progress:
  total_phases: 6
  completed_phases: 5
  total_plans: 41
  completed_plans: 33
  percent: 80
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-28)

**Core value:** `task rebuild` performs a scorched-earth teardown and reaches a healthy hub-spoke Flux lab — with a CUDA-capable spoke — in under 20 minutes, every time.
**Current focus:** Phase 06 — repo-hygiene-docs-adrs

## Current Position

Phase: 06 (repo-hygiene-docs-adrs) — EXECUTING
Plan: 1 of 8
Status: Executing Phase 06
Last activity: 2026-04-28 -- Phase 06 execution started

Progress: [██████████] 100%

## Performance Metrics

**Velocity:**

- Total plans completed: 27
- Average duration: -
- Total execution time: -

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01 | 9 | - | - |
| 02 | 7 | - | - |
| 04 | 5 | - | - |
| 05 | 6 | - | - |

**Recent Trend:**

- Last 5 plans: -
- Trend: -

*Updated after each plan completion*
| Phase 02-cluster-layer P06 | 45min | 3 tasks | 3 files |
| Phase 02-cluster-layer P07 | 5min | 1 tasks | 1 files |
| Phase 03-flux-hub-bootstrap P05 | 3min | 2 tasks | 2 files |
| Phase 03-flux-hub-bootstrap P06 | human-checkpoint | 2 tasks | 4 files |
| Phase 04-spoke-registration P01 | 5min | 2 tasks | 2 files |
| Phase 04-spoke-registration P02 | 4min | 3 tasks | 10 files |
| Phase 04-spoke-registration P03 | 6min | 1 tasks | 1 files |
| Phase 04-spoke-registration P04 | 5min | 4 tasks | 4 files |
| Phase 04-spoke-registration P05 | checkpointed | 4 tasks | 6 files |
| Phase 05-workloads-health-rebuild P01 | 5 min | 5 tasks | 6 files |
| Phase 05-workloads-health-rebuild P02 | 5 min | 3 tasks | 11 files |
| Phase 05-workloads-health-rebuild P03 | 5 min | 2 tasks | 2 files |
| Phase 05-workloads-health-rebuild P04 | 5 min | 2 tasks | 2 files |
| Phase 05-workloads-health-rebuild P05 | 5 min | 3 tasks | 3 files |
| Phase 05-workloads-health-rebuild P06 | checkpointed; continuation 5 min | 3 tasks | 3 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table. Recent decisions affecting current work:

- Phase 1: Port existing `prereqs.sh` as `scripts/preflight.sh` (not a rewrite).
- Phase 2: Custom k3s+CUDA image FROM `nvidia/cuda:12.8.1-base-ubuntu22.04` (Ubuntu base, k3s layered in) — Alpine stock image cannot host the NVIDIA runtime.
- Phase 3: `flux bootstrap --path` is effectively immutable — hard-code `clusters/hub-flux` in the bootstrap script, reject env overrides.
- Phase 4: Legacy Secret-backed SA tokens (not `kubectl create token`) — indefinite lifetime is correct for a lab and avoids token-expiry as a failure mode.
- Phase 6: gitleaks pre-commit MUST be installed before the first `git push` — public-repo + leaked PAT is unrecoverable.
- D-14 blocking comment is exact-text greppable ('INTENTIONALLY NOT calling') — Phase 6 DESTROY-04 lint will grep for this literal; not a free-form comment
- require_live_destructive() double-gate prevents accidental cluster destruction during KARYON_LIVE_TESTS=1 full-suite runs
- Taskfile.yml Phase 2 stub: three tasks only (build-image, create-clusters, delete-clusters); Phase 6 REPO-05 owns full audit
- Plan 03-05: Treat .env as data for only GITHUB_OWNER, GITHUB_REPO, and GITHUB_TOKEN; never source it as shell.
- Plan 03-05: Use local git pull --ff-only sync rather than reimplementing Flux bootstrap remote Git workflow.
- [Phase 04]: Phase 4 P18 contract treats omitted spec.kubeConfig as the real silent-misroute risk; value.yaml remains pinned as defense in depth.
- [Phase 04]: Live in-pod probes use openssl for CA/TLS proof and busybox wget for auth/node identity because the kustomize-controller image lacks kubectl.
- [Phase 04]: The Phase 4 live suite centralizes its destructive env gate in setup() and skips local-only or unpushed reconciliation-tree state.
- [Phase 04-spoke-registration]: Plan 04-02: Both spokes use ConfigMap name karyon-spoke-id, while namespace and data.spoke differ to preserve the cross-cluster falsifier. — The same object name with different namespace and data values proves routing to the intended spoke.
- [Phase 04-spoke-registration]: Plan 04-02: Hub-side spoke Kustomizations keep the full spec.kubeConfig block as the primary P18 defense; key: value.yaml remains pinned as defense in depth. — Required to prevent silent in-cluster fallback if spec.kubeConfig is omitted.
- [Phase 04-spoke-registration]: Plan 04-03 keeps the registration script local-file-only — The script prints git instructions but never runs git add, git commit, or git push.
- [Phase 04-spoke-registration]: Plan 04-03 runtime health check proves RBAC, decoded Secret content, auth, and node routing before skipping mutation — Local manifest repair and D-13 verification still run on idempotent reruns.
- [Phase 04-spoke-registration]: Plan 04-03 in-pod verification uses openssl plus busybox wget — kustomize-controller lacks kubectl; openssl proves CA/TLS and wget proves auth/node identity.
- [Phase 04-spoke-registration]: Plan 04-04 mounts clusters/hub-flux/spokes through the existing Phase 3 patch surface — Uses # KARYON SPOKES MOUNT plus - ../spokes under resources.
- [Phase 04-spoke-registration]: Plan 04-04 docs frame P18 as omitted spec.kubeConfig — key: value.yaml remains explicit defense in depth.
- [Phase 04-spoke-registration]: Phase 3 docs tests now assert the filled Phase 4 section — The planned HTML stub was consumed by this plan.
- [Phase 04-spoke-registration]: Plan 04-05 uses post-push live destructive Bats plus inventory IDs and cross-cluster ConfigMap falsifiers as the canonical P18 reconciliation proof.
- [Phase 04-spoke-registration]: Plan 04-05 uses a temporary CA-only OpenSSL verifier pod when the Flux controller image lacks openssl, then deletes it after the proof.
- [Phase 04-spoke-registration]: clusters/hub-flux/kustomization.yaml is required at the Flux bootstrap path root so origin/main includes flux-system and the mounted spokes tree.
- [Phase 05-workloads-health-rebuild]: Plan 05-01 verifies Bats syntax with bats --count; behavioral fail-closed checks are intentionally enforced when downstream implementation artifacts land. — Wave 0 only needs parse proof; downstream implementation plans own behavior going green.
- [Phase 05-workloads-health-rebuild]: The live Phase 5 suite is a post-rebuild state checker only and does not invoke rebuild, destroy, delete-clusters, or k3d delete commands. — Plan 05-06 runs the rebuild chain exactly once; tests should not cause a second destructive run.
- [Phase 05-workloads-health-rebuild]: Static tests pin the review fixes for HIGH-1, HIGH-2, HIGH-3, MED-1, MED-2, and MED-3 before implementation begins. — The Wave 0 contracts prevent later plans from shipping without the cross-review mitigations.
- [Phase 05-workloads-health-rebuild]: Plan 05-02 keeps examples/ as the canonical workload source and uses relative Kustomize resources from the existing spoke trees. — Preserves the one-Kustomization-per-spoke GitOps model while avoiding duplicated workload YAML.
- [Phase 05-workloads-health-rebuild]: deploy-examples fails before Flux reconcile when examples/ or clusters/ are dirty or local HEAD differs from origin/main. — Flux reconciles origin/main, so local-only changes would otherwise cause unclear waits and stale deploys.
- [Phase 05-workloads-health-rebuild]: Flux source refresh precedes spoke Kustomization reconciliation, with a source-git flag compatibility guard for Flux v2.8.6. — The installed Flux CLI does not support --with-source on source git reconcile, but the source refresh ordering remains required.
- [Phase 05-workloads-health-rebuild]: Plan 05-03 fix-coredns applies the stale k3d CoreDNS NodeHosts workaround by mutating only hub-flux. — Preserves D-10 and MED-2 by never stop/starting or restarting spokes.
- [Phase 05-workloads-health-rebuild]: Plan 05-03 Flux controller readiness waits are guarded by deployment count >= 4 before kubectl wait --all. — Prevents MED-3 empty-set wait pass-through.
- [Phase 05-workloads-health-rebuild]: Plan 05-03 post-restart spoke DNS proof is read-only via kubectl exec into source-controller and warning-only. — Proves the workaround symptom without creating resources or mutating spokes.
- [Phase 05-workloads-health-rebuild]: Plan 05-04 health-check remains read-only; stale hub DNS failures point to task fix-dns instead of mutating cluster state.
- [Phase 05-workloads-health-rebuild]: Plan 05-04 in-hub DNS proof uses source-controller getent probes for both spokes, satisfying the HIGH-2 read-only contract.
- [Phase 05-workloads-health-rebuild]: Plan 05-04 Flux controller readiness waits are guarded by deployment count >= 4 before kubectl wait --all.
- [Phase 05-workloads-health-rebuild]: Plan 05-05 keeps scripts/delete-clusters.sh as the only teardown implementation; destroy is a confirmation wrapper. — Preserves CUDA cache and avoids duplicating destructive logic.
- [Phase 05-workloads-health-rebuild]: Plan 05-05 records rebuild step markers and elapsed seconds in /tmp/karyon-rebuild.log for the Plan 05-06 state checker. — Allows live verification to inspect one rebuild run without triggering another destructive rebuild.
- [Phase 05-workloads-health-rebuild]: Plan 05-05 re-pins kubectl context to k3d-hub-flux between create-clusters and bootstrap-flux to satisfy HIGH-1. — create-clusters leaves the current context on the last-created spoke while bootstrap and registration intentionally assert hub context.
- [Phase 05-workloads-health-rebuild]: Plan 05-06 treats /tmp/karyon-rebuild.log as the canonical non-committed proof artifact; verification parses it without rerunning task rebuild.
- [Phase 05-workloads-health-rebuild]: The final live proof requires HEAD == origin/main and clean examples/clusters paths before any destructive command runs.
- [Phase 05-workloads-health-rebuild]: The failed first rebuild was resolved by preserving Phase 5 example references during spoke seed repair before accepting the second destructive approval.

### Pending Todos

None yet. [From .planning/todos/pending/ — ideas captured during sessions.]

### Blockers/Concerns

- `task rebuild` (Phase 5, DESTROY-05/06) success is gated on every prior phase being green and on CUDA build-cache surviving `task destroy` (Phase 2, IMG-06 + DESTROY-03). Re-verify after any Phase 2 or Phase 5 change.
- Phase 4 is the single highest-risk phase — DNS + TLS + CA + RBAC + Secret-key all converge. Schedule a dedicated research pass during planning if initial planning surfaces ambiguity.

## Deferred Items

Items acknowledged and carried forward from previous milestone close:

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| *(none)* | | | |

## Session Continuity

Last session: 2026-04-28T17:54:42.957Z
Stopped at: Phase 6 context gathered
Resume file: .planning/phases/06-repo-hygiene-docs-adrs/06-CONTEXT.md

**Planned Phase:** 04 (spoke-registration) — 5 plans — 2026-04-27T14:44:55.867Z
