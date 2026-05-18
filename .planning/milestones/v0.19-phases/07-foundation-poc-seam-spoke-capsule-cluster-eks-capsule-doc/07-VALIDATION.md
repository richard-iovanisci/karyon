---
phase: 7
slug: foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc
status: final
nyquist_compliant: true
wave_0_complete: true
created: 2026-04-29
finalized: 2026-05-11
finalized_evidence: "Plan 07-00 Wave 0 RED bats scaffold (7 bats files + 2 gitleaks fixtures covering POC-01..04, CAPCLU-01..04, EKSDOC-01 contracts under D-09-08 Nyquist gate inheritance) became GREEN over Plans 07-01..07-05. 07-VERIFICATION.md reports status: human_needed with 9/9 must-haves verified at file/contract level (271/271 bats GREEN); 4 manual-only items tracked in HUMAN-UAT (live cluster Ready post-inotify fix, fix-dns recovery, mermaid render, doc readability) are non-blocking per Phase 12 close-out scope. Nyquist sampling rate satisfied: every REQ-ID (POC-01..04, CAPCLU-01..04, EKSDOC-01) has at least one bats falsifier in the Wave-0 scaffold turned GREEN."
---

# Phase 7 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bats-core 1.11.0 |
| **Config file** | `tests/bats/test_helper.bash` (shared loader; existing v0.18 infrastructure) |
| **Quick run command** | `bats tests/bats/poc-mount-01-static.bats tests/bats/register-poc-cluster-01-static.bats tests/bats/poc-cluster-01-static.bats tests/bats/preflight-pre15.bats tests/bats/repo-hygiene-04-poc.bats tests/bats/docs-06-eks.bats` |
| **Full suite command** | `bats tests/bats/` |
| **Estimated runtime** | ~30 seconds (full suite, includes 169 v0.18 tests + new Phase 7 tests) |

---

## Sampling Rate

- **After every task commit:** Run quick command (Phase 7 static contracts; <1s)
- **After every plan wave:** Run `bats tests/bats/` (full suite — Phase 7 tests + v0.18 regression gate)
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 7-00-* | 00 | 0 | (Wave 0 stubs) | — | All Phase 7 bats files exist with all `@test` cases marking unimplemented as failing (Nyquist gate) | static | `bats tests/bats/<phase-7-files>` | ❌ W0 | ⬜ pending |
| 7-EKSDOC | (TBD) | 1 | EKSDOC-01 | T-7-EKSDOC | docs/capsule-on-eks.md exists with sections (a)-(e), Mermaid block, three verbatim YAMLs (IRSA, LB/ALB, VPC nodeSelector), 3-item NOT-PROVED list | static (grep + yq) | `bats tests/bats/docs-06-eks.bats` | ❌ W0 | ⬜ pending |
| 7-POC-01 | (TBD) | 1 | POC-01 | T-7-D-09 | `# KARYON POC MOUNT` sentinel uniqueness + `../pocs` resource line in clusters/hub-flux/flux-system/kustomization.yaml + clusters/hub-flux/pocs/{kustomization.yaml,capsule.yaml} files | static | `bats tests/bats/poc-mount-01-static.bats` | ❌ W0 | ⬜ pending |
| 7-POC-02 | (TBD) | 2 | POC-02 | T-7-D-11 | scripts/register-poc-cluster.sh strict-mode + single-positional + sources preflight-lib + apply_spoke_rbac/apply_hub_secret/ensure_hub_pocs_mount/verify_credential_layer literals + `key: value.yaml` + zero `register-poc-cluster.sh` mentions in v0.18 scripts | static | `bats tests/bats/register-poc-cluster-01-static.bats` | ❌ W0 | ⬜ pending |
| 7-POC-02-iso | (TBD) | 2 | POC-02 / D-12 | T-7-P-31 | Zero `spoke-capsule` and zero `register-poc-cluster.sh` mentions in scripts/{create-clusters,register-spokes-for-flux,health-check,destroy,delete-clusters,rebuild}.sh | static | `bats tests/bats/poc-isolation-01-static.bats` (or extension to destroy-rebuild-01-static.bats) | ❌ W0 | ⬜ pending |
| 7-POC-03-rule | (TBD) | 2 | POC-03 | T-7-D-14 | `.gitleaks.toml` carries new `kubeconfig-bearer-token` rule (multi-line `(?ms)` regex, requires gitleaks ≥8.25.0; pinned 8.30.1 satisfies) + per-fixture path allowlist | static | `bats tests/bats/repo-hygiene-04-poc.bats` | ❌ W0 | ⬜ pending |
| 7-POC-03-pos | (TBD) | 2 | POC-03 | T-7-D-14 | gitleaks fires on `tests/fixtures/gitleaks/synthetic-kubeconfig.yaml` (positive fixture; allowlisted by path so it can be committed) | live (gitleaks invocation) | (same suite) | ❌ W0 | ⬜ pending |
| 7-POC-03-neg | (TBD) | 2 | POC-03 | T-7-D-14 | gitleaks does NOT fire on `tests/fixtures/gitleaks/benign-configmap.yaml` (negative fixture) | live | (same suite) | ❌ W0 | ⬜ pending |
| 7-POC-03-gi | (TBD) | 2 | POC-03 | T-7-D-14 | `.gitignore` carries new tenant-kubeconfig globs (extends Phase 6 D-16 expansion) | static | (same suite) | ❌ W0 | ⬜ pending |
| 7-POC-04 | (TBD) | 2 | POC-04 | T-7-P-39 | scripts/preflight.sh carries `check_port_strict 30443` (or equivalent fail-fast) + Phase 7 PRE-15 section header | static | `bats tests/bats/preflight-pre15.bats` | ❌ W0 | ⬜ pending |
| 7-CAPCLU-01-static | (TBD) | 3 | CAPCLU-01 | T-7-D-10 | scripts/poc/capsule/create-cluster.sh exists, strict-mode, sources preflight-lib, calls k3d cluster create with apiserver port 6446 + NodePort 30443 + tls-san k3d-spoke-capsule-server-0 + k8s-net network; idempotency = skip-if-exists with image/network/api-port drift verify | static | `bats tests/bats/poc-cluster-01-static.bats` | ❌ W0 | ⬜ pending |
| 7-CAPCLU-01-live | (TBD) | 3 | CAPCLU-01 | T-7-D-10 | Live evidence via register-poc-cluster.sh's verify_credential_layer() — k3d-spoke-capsule cluster reaches Ready and `kubectl --context k3d-spoke-capsule get nodes` lists `k3d-spoke-capsule-server-0` | live (script-internal verification) | scripts/register-poc-cluster.sh internal | — script-driven | ⬜ pending |
| 7-CAPCLU-02 | (TBD) | 3 | CAPCLU-02 | T-7-P-40 | clusters/hub-flux/pocs/capsule.yaml carries explicit `spec.kubeConfig.secretRef.name: spoke-capsule-kubeconfig` + `key: value.yaml` + `spec.path: ./pocs/capsule` (P18 inheritance) | static (yq query) | `bats tests/bats/poc-cluster-01-static.bats` | ❌ W0 | ⬜ pending |
| 7-CAPCLU-02-live | (TBD) | 3 | CAPCLU-02 | T-7-P-40 | P18 silent-misroute falsifier: outer Kustomization Ready=True ONLY when spoke-capsule node-name appears in /api/v1/nodes (NOT hub-flux node-name) | live (script-internal) | register-poc-cluster.sh verify_credential_layer | — script-driven | ⬜ pending |
| 7-CAPCLU-03 | (TBD) | 4 | CAPCLU-03 | T-7-D-16 | scripts/poc/capsule/fix-dns.sh exists, strict-mode, sources preflight-lib, calls k3d cluster stop/start spoke-capsule, ZERO hub-flux cluster mentions; Taskfile.yml carries `fix-dns-poc-capsule` task wired to the script | static | `bats tests/bats/poc-cluster-01-static.bats` | ❌ W0 | ⬜ pending |
| 7-CAPCLU-04 | (TBD) | 4 | CAPCLU-04 | T-7-D-16 | docs/poc-capsule.md exists with `## Host restart recovery` section + `## Troubleshooting` subsection + reference to `task fix-dns-poc-capsule` | static (grep) | `bats tests/bats/poc-cluster-01-static.bats` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

*Plan column will be filled by gsd-planner; Wave assignments are illustrative — planner determines final wave structure.*

---

## Wave 0 Requirements

The following bats files MUST be created in Phase 7's Wave 0 (Nyquist gate; before any plan implements its behavior):

- [ ] `tests/bats/docs-06-eks.bats` — covers EKSDOC-01 (sections + Mermaid + verbatim YAMLs + NOT-PROVED 3-item list)
- [ ] `tests/bats/poc-mount-01-static.bats` — covers POC-01 (sentinel uniqueness + presence in correct file + `../pocs` resource line + pocs/kustomization.yaml aggregator + clusters/hub-flux/pocs/capsule.yaml shape via P40 yq query)
- [ ] `tests/bats/register-poc-cluster-01-static.bats` — covers POC-02 (script existence + strict-mode + single positional + sources preflight-lib + apply_spoke_rbac literal + apply_hub_secret literal + ensure_hub_pocs_mount literal + verify_credential_layer literal + `value.yaml` + node-name proof literals)
- [ ] `tests/bats/poc-cluster-01-static.bats` — covers CAPCLU-01 + CAPCLU-02 + CAPCLU-03 + CAPCLU-04 (create-cluster.sh + fix-dns.sh shape + clusters/hub-flux/pocs/capsule.yaml shape + Taskfile fix-dns-poc-capsule entry + docs/poc-capsule.md sections)
- [ ] `tests/bats/preflight-pre15.bats` — covers POC-04 (`check_port_strict 30443` literal in preflight.sh + Phase 7 PRE-15 section header)
- [ ] `tests/bats/repo-hygiene-04-poc.bats` — covers POC-03 (`.gitignore` extension globs + `.gitleaks.toml` rule + path allowlist + positive/negative fixture invocations)
- [ ] `tests/fixtures/gitleaks/synthetic-kubeconfig.yaml` — POC-03 positive fixture (committed; allowlisted by path)
- [ ] `tests/fixtures/gitleaks/benign-configmap.yaml` — POC-03 negative fixture
- [ ] (Optional, planner judgment) `tests/bats/poc-isolation-01-static.bats` — explicit greps that v0.18 scripts have ZERO `spoke-capsule` mentions. Could fold into `tests/bats/destroy-rebuild-01-static.bats` extension instead.

The bats-core framework, test_helper.bash loader, and `<area>-<NN>-<topic>.bats` naming convention are all already in place from v0.18. **No framework install needed.**

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| EKS doc reads naturally to a Mixed Eng + Cloud Ops audience for a team presentation | EKSDOC-01 | Subjective — Mermaid diagram clarity, walkthrough flow, depth/brevity calibration cannot be grep-tested | Milestone owner reads `docs/capsule-on-eks.md` end-to-end; confirms (a) high-level POC walkthrough orients Cloud Ops, (b) IRSA/LB/nodeSelector YAML blocks are lift-ready, (c) NOT-PROVED 3-item list aligns with eventual ADR-008 vocabulary, (d) Mermaid renders correctly in GitHub web UI |
| Host-restart recovery procedure in `docs/poc-capsule.md` is executable from cold start | CAPCLU-04 | Procedure correctness depends on Docker/WSL behavior at runtime; bats greps the section exists but cannot validate steps work | After Docker or WSL restart with spoke-capsule alive, follow the documented procedure (run `task fix-dns-poc-capsule`, verify with `kubectl --context k3d-spoke-capsule get nodes`); confirm cluster recovers without affecting hub-flux or v0.18 spokes |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies (Wave 0 covers all 7 phase requirements + the 2 EKSDOC manual verifications)
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify (every Phase 7 plan task has at least 1 bats assertion via the Wave 0 files)
- [ ] Wave 0 covers all MISSING references (8 new bats + 2 fixtures listed above)
- [ ] No watch-mode flags (bats runs to completion; no `--watch` mode used)
- [ ] Feedback latency < 30s (full suite ~30s including v0.18 regression)
- [ ] `nyquist_compliant: true` set in frontmatter (will be set after Wave 0 lands and all phase requirements have a Wave-0 bats target)

**Approval:** pending
