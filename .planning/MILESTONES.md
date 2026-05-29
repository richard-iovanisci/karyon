# Milestones

## v0.20 Capsule POC Demo & RBAC Polish (Shipped: 2026-05-29)

**Phases completed:** 3 phases, 14 plans, 27 tasks

**Key accomplishments:**

- 19 NEW bats files locking the RBAC + SEED + DELIVERY falsifier matrix BEFORE Phase 13 implementation lands; Phase 11 D-11-02 CapsuleConfiguration.userGroups inheritance + Phase 10 D-10-06 capsule-proxy cert source verified live; Plan 13-04 verifier has a pre-existing automated test command for every Wave 1+ executor task.
- 1. [Rule 1 — Bug] Wave 0 bats `rbac-08` assertion shape broken by kubectl stderr warnings
- GlobalTenantResource cluster-scoped CR (`hello-world-seeded`) with match-all tenantSelector auto-propagating nginx:alpine Pod + ClusterIP Service to every tenant namespace; SEED-01/02/03 GREEN end-to-end.
- Phase 13 closed with disposition `passed_with_overrides` — all 12 REQs (RBAC-01..06 + SEED-01..03 + DELIVERY-01..03) verified live; 5/5 ROADMAP success criteria met; 159/159 Phase 13 NEW bats @tests GREEN end-to-end; 7 pre-existing inheritance bats REDs documented as NOT Phase 13 regressions; 1 env-gated DEFERRED (delivery-05 SLO bats requires `KARYON_REBUILD_APPROVED=1`).
- 6 live DEMO bats:
- One-liner:
- Cluster reality (alpha→bravo + bravo→alpha):
- Cluster reality:
- v0.20 REQ ledger fully reconciled: 23/23 mandatory `[x]` + 4 inline OQ lock-in amendments + 23/23 Traceability `Complete` rows — 3-source matrix aligned and ready for Plan 15-02..05 downstream audit gates.
- STATE.md ledger advanced from premature `status: completed` (Phase 14 close) to correct Wave-1 in-flight state (`executing` / 9/14 / 64%) with Current Position block, v0.20 velocity counter, and Performance Metrics By-Phase v0.20 table populated.
- Phase 14 Phase Summary checkbox flipped `[ ] -> [x]`; Phase 14 Progress table row advanced `0/4 | Not started | -` -> `4/4 | Complete | 2026-05-19`; Phase 15 row stays mid-phase per Wave-2 self-close pattern; ROADMAP.md within-document consistency for v0.20 phases verified GREEN.
- Plan 15-04 retry #2 completed all six tasks: Tasks 1-3 GREEN (preflight 6/6, bats subset 203/215 with 12 pre-existing inheritance REDs, 3/3 cluster-admin denials), Task 4 checkpoint reached + resumed via orchestrator continuation with `user_response="approved"`, Task 5 elected PATH-B for DELIVERY-02 + DELIVERY-03 (architectural worktree-isolation conflict prevented task rebuild from completing; carry-forward to Phase 14 14-02 VAL-04 inheritance disposition), Task 6 finalized evidence log with per-category summary + regression-gate disposition + carry-forward inheritance section + footer.
- Plan 15-05 (Wave 2 sequential audit gate + 6 close-out artifacts) completed all 7 tasks on main working tree with normal git commits (hooks enabled; no `--no-verify`).

---

## v0.19 Capsule Multi-Tenancy POC (Shipped: 2026-05-18)

**Phases completed:** 6 phases, 34 plans, 76 tasks

**Key accomplishments:**

- 7 Phase 7 bats target files + 2 gitleaks fixtures land before any behavior — 51 RED tests pin the contracts that Plans 01-05 will turn green; 12 GREEN tests immediately enforce P31/D-12 POC isolation and v0.18 inheritance.
- Self-contained EKSDOC-01 design doc shipped (`docs/capsule-on-eks.md`, Status: Draft) — Mermaid topology + 3 verbatim YAMLs (IRSA / NLB+ALB / CapsuleConfiguration) + locked 3-item NOT-PROVED framing — usable for an immediate team presentation while later Phase 7-11 infra phases land.
- Generic, sentinel-guarded POC onboarding seam landed in the FLUX PATCH SURFACE plus a v0.18-mirrored aggregator + outer Flux Kustomization for spoke-capsule with empty-resources placeholder — POC-01 and CAPCLU-02 file-shape contracts now satisfied.
- Persistent spoke-capsule k3d cluster create script (D-10 pins, idempotent skip-with-drift-verify) and single-positional register-poc-cluster.sh with independent sentinel insertion, D-11 stdin-pipe Secret apply, and P18 silent-misroute falsifier.
- check_port_strict() helper inverts v0.18's warn pattern for POC-reserved port 30443 (D-15); first positive gitleaks rule (id=kubeconfig-bearer-token, multi-line (?ms) regex) + 4 tenant-kubeconfig .gitignore globs close P29 leak loop end-to-end on Wave 0 fixtures.
- 1. [Rule 3 - Blocking] Widened repo-hygiene-02-taskfile.bats thin-wrapper regex to accept P31-isolated POC subpath
- 10 bats files (5 static + 5 live, 49 tests, 507 lines) preposition every HelmRelease/OCIRepository/proxy contract + folded Phase-7 carryover for Plans 08-01/08-02/08-03 to turn GREEN by landing yaml — Pitfall 8 (CAP-02 reachability reframe) and Pitfall 9 (no wait: in dependsOn) encoded RESEARCH-verbatim.
- Three net-new files under `pocs/capsule/operator/` (124 total lines) land the operator side of Phase 8: Flux v1 OCIRepository pinning `capsule:0.12.4`, Flux v2 HelmRelease using modern `chartRef`/`kubeConfig` syntax with built-in certgen + 14 per-hook `failurePolicy: Ignore` overrides at the RESEARCH-verified per-hook key path (NOT the path 08-CONTEXT.md guessed), and a local Kustomize aggregator. Turns 23 of 38 Wave 0 static-bats tests GREEN for the operator-half; proxy-half remains RED awaiting Plan 08-02.
- Three net-new files under `pocs/capsule/proxy/` (114 total lines) plus parent kustomize rewrite (pocs/capsule/kustomization.yaml: resources [] -> [operator/, proxy/] preserving Phase 7 head comment) land the proxy side of Phase 8 — Flux v2 HelmRelease declares `dependsOn` operator with NO `wait:` field (Pitfall 9 RESEARCH catch), `service.{type=NodePort, nodePort=30443}` (Phase 7 D-10 inheritance), `options.additionalSANs=[127.0.0.1, localhost]` (RESEARCH-verified key path; NOT tls.additionalSANs), and `certManager.generateCertificates: true` (OQ-2 verified live before write). Closes the Wave 2 gap: all 5 static Wave 0 bats files turn 38/38 GREEN end-to-end and Phase 7 regression bats stay 22/22 GREEN.
- Live verifier-only plan ran the 5 Phase 8 live observability bats + reran the 3 Phase 7 static regression bats verbatim + ran the full project bats suite — outer `poc-capsule` Kustomization observed Ready=True (FOLDED CARRYOVER primary acceptance GREEN at revision past 1f2da1d3), HelmRelease install observation deferred to Phase 11 VAL-05 because Plans 08-01 + 08-02 yaml is not yet in origin/main (push-gate path). Phase 7 regression bats 22/22 GREEN. ADR-004 invariant intact. Zero production files modified end-to-end.
- D-08-11 cert flip (controller-less self-sign Job) + D-08-12 architectural seam fix (split outer K into hub-targeted + spoke-targeted Flux Kustomizations) + WR-01/WR-02/WR-03/WR-04 bats hardening (yq path assertions + kubectl jsonpath + NotFound vs transient distinction).
- 12 RED bats files (66 tests) + P27 negative falsifier fixture landing the Phase 9 Nyquist gate per D-09-08 — every TEN-01..06 contract has a deterministic falsifier in place BEFORE any tenant yaml lands.
- CapsuleConfiguration singleton + 2 Tenant CRs (alpha, bravo) with multi-owner arrays + per-tenant home namespaces + per-tenant ServiceAccounts + dependsOn chain on capsule-spoke.yaml outer K, applying RESEARCH Gap 4/5/9 schema corrections to CONTEXT.md verbatim.
- 5 new yaml files (per-tenant Namespace + GitRepository + Kustomization multi-doc + 2 Pitfall-7 placeholders + tenants/ aggregator) + outer pocs/capsule/kustomization.yaml updated with tenants/ + scripts/register-poc-cluster.sh extended with mirror_kubeconfig_to_tenant_namespaces function — completes the hub-side TEN-04 P27 + TEN-06 P32 contracts and mitigates RESEARCH §Gap 1 (Flux's hard same-namespace constraint for kubeConfig.secretRef).
- Hub Flux multi-tenancy lockdown landed cleanly on attempt 3 after two prior atomic rollbacks. Gap A's mitigation (spec.serviceAccountName: flux-reconciler on spoke v0.18 Kustomization CRs — matching the actually-existing SA per scripts/register-spokes-for-flux.sh:286) is VERIFIED via live regression test under suspend+apply pattern: post-patch task health-check exits 0 (19/19 v0.18 assertions green); all 3 patched controllers carry the expected lockdown flags (kustomize-controller 3 flags + helm-controller 1 flag + notification-controller 1 flag); flux-system Kustomization CR escape hatch (D-09-05a) confirmed live; capsule.yaml hub-targeted escape hatch confirmed via static bats; spoke-{apps,ml} + flux-system + poc-capsule + poc-capsule-spoke Kustomizations all reach Ready=True post-patch. Suspend+apply executed cleanly under D-08-13 push-gate deferral; flux resume converged cluster back to origin/main baseline (sha 32e0b2fa) cleanly. TEN-05 contract DELIVERED. Plan 09-04 (Phase 9 verifier) UNBLOCKED.
- Phase 9 verification complete. All 8 must-haves verified (4 live + 4 PASSED-with-override per D-08-13 push-gate deferral inheritance from Phase 8). All 6 TEN-01..06 contracts met at static (32/32 GREEN) and live (where push-gate permits — TEN-05 lockdown 12/12 GREEN; TEN-01 Tenant CRs 6/6 GREEN). The dominant Phase 9 acceptance criterion (v0.18 task health-check exit 0) PASSED across 3 cluster states. Plan 09-04 Task 1 fix (commit 100f8b5) closes RESEARCH §Gap 2 helm-controller omission from Plan 09-03 attempt 3. Phase 9 closes; Phase 10 unblocked.
- 7 bats files (45 @tests) locking the PROXY-01/02/03 contract for `scripts/poc/capsule/issue-tenant-kubeconfig.sh` BEFORE the script lands — mirrors Phase 7/8/9 D-09-08 Wave 0 RED scaffold pattern.
- Imperative bash script `issue-tenant-kubeconfig.sh` mints tenant-owner kubeconfigs via TokenRequest + tls.crt embed + heredoc emit; `docs/poc-capsule.md` gets the new "Tenant kubeconfig delivery contract" H2 section completing the PROXY-03 doc contract.
- Phase 10 verifier observed the staged capsule-proxy live state, wired the proxy LIST filter (CapsuleConfiguration userGroups + tenant home namespace ownership — both Rule 3 deviations), ran the full Phase 10 + Phase 7+8+9 inheritance bats suite, wrote 10-VERIFICATION.md (passed_with_overrides), and transitioned STATE.md + ROADMAP.md + REQUIREMENTS.md to reflect Phase 10 close-out.
- 16 Phase 11 bats files landed RED-by-design (3 GREEN at landing) covering VAL-01..05 falsification surface — Nyquist gate locked before any production code in Plans 11-01..04
- 5 GitOps-source files updated to land Phase 10 D-08-13 push-gate-deferred carryovers + Phase 7 gitleaks planning-doc todo as canonical state before first push.
- 2 net-new POC scripts (~244 lines combined) + 2 Taskfile entries that satisfy VAL-02 (webhook failure simulation) + VAL-03 (clean teardown) at the script-shape level, with reviewer HIGH #5 + MEDIUM #9 + MEDIUM #11 revisions baked in.
- Tenant CRs extended with namespaceOptions.quota=3 + containerRegistries.allowed=[registry.example.io]; live spoke-capsule reconciled; 10/12 N1-N12 GREEN (N9+N10 RED on Phase 8 G-04 inheritance, escalated to Plan 11-04)
- Plan 11-04 verifier ran post-push hard gates + 17 bats files (16 Phase 11 + Phase 7 P31 inheritance) + VAL-04 SLO + post-push gitleaks history scan; landed `11-VERIFICATION.md` with disposition `passed_with_overrides`. HARD-GATE 1 RED on Phase 8 G-04 BLOCKER cascade (Pitfall 11-P1 fired; chart-rendered Role does not exist on spoke-capsule because outer poc-capsule Kustomization cannot apply HR CR to a cluster without Flux CRDs). HARD-GATE 2 GREEN (zero live SKIPs). Plan 11-05 (ADR-008) is unblocked; recommended outcome: DEFER.
- One-liner:
- Two file edits + one bats rewrite resolve the Phase 8 G-04 BLOCKER active since 2026-04-29: (1) added pocs/capsule/namespace.yaml so hub-flux kustomize-controller has the capsule-system namespace before HR/OCIRepo CRs are applied (was: "namespaces capsule-system not found"); (2) relocated the D-11-01 RBAC patch from Kustomization spec.patches in clusters/hub-flux/pocs/capsule.yaml to HelmRelease spec.postRenderers in pocs/capsule/proxy/helmrelease.yaml (Pitfall 11-P1 fix — Kustomization spec.patches only modifies kustomize-build output; helm-rendered Roles need postRenderers). Plan 11-07 Task 6 completed the post-push empirical verification and closed the Task 3 gate as passed.
- Flipped 18 stale v0.19 mandatory REQ checkboxes to [x], amended TEN-01 spec body inline to reflect live `forceTenantPrefix: false` repair from Plan 11-07 D-11-07 (commit faecf14), and corrected §v0.19 Close-out narrative count from stale "15 stale" to accurate "18 v0.19 mandatory" with explicit arithmetic breakdown.
- STATE.md advanced past Plan 11-07 closeout into Phase 12 (Plan 1 of 7); 4 stale Pending Todos bullets marked RESOLVED with auditable closure-commit citations to commits 384f859, 75e5b78, a9af679, ecbb4b6.
- 11-VERIFICATION.md and 11-PHASE-VERIFICATION.md now record canonical post-11-07 `passed` state via appended Supersedure — 2026-05-11 H2 blocks + frontmatter disposition flips, with original 2026-05-06 body content preserved verbatim and disposition_history arrays capturing the transition.
- Closed Nyquist VALIDATION.md ledgers for phases 7/8/9/10/11 via frontmatter-only edits — flipped status: draft -> final on all 5; flipped nyquist_compliant + wave_0_complete to true on 4 (Phase 9 flags already true); appended finalized: 2026-05-11 + finalized_evidence citing per-phase verifier evidence.
- Phase 7 carryover todo moved from `.planning/todos/pending/` → `completed/` via `git mv` (R100 similarity) with Option B closure appendix citing Plan 11-07 + HEAD `8415ab66` as the resolver of the auto-close condition originally stipulated in the file's 2026-04-29 inline status update.
- ROADMAP.md Progress table verified consistent (8/8 grep checks PASS, zero Progress-table edits) and the "15 stale" narrative-count drift eliminated at all 3 sites (lines 44, 141, 143) — corrected to "18 v0.19 mandatory" with explicit `POC-01..04 + CAPCLU-01..04 + EKSDOC-01 + CAP-01..03 + TEN-01..06 = 4+4+1+3+6 = 18` arithmetic for traceability.
- Wave 2 gate plan re-ran `/gsd-audit-milestone v0.19` (inline, after Wave 1 corrections), the audit returned `passed` (27/27 v0.19 mandatory REQs satisfied; 5/5 Nyquist compliant; zero tech_debt), and the Phase 12 self-close flips landed on ROADMAP/STATE/12-VALIDATION/REQUIREMENTS — v0.19 milestone is now `ready_to_archive`.

---

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
