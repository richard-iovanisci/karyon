---
phase: 07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc
verified: 2026-04-29T11:55:00Z
status: human_needed
score: 9/9 must-haves verified at file/contract level (live cluster Ready state requires user inotify fix)
overrides_applied: 0
re_verification: false
human_verification:
  - test: "Live spoke-capsule cluster reaches Ready=True after raising inotify limit"
    expected: "After `sudo sysctl -w fs.inotify.max_user_instances=1024` and re-running `bash scripts/poc/capsule/create-cluster.sh` + `bash scripts/register-poc-cluster.sh spoke-capsule`, the verify_credential_layer P18 falsifier should report `k3d-spoke-capsule-server-0` present in /api/v1/nodes and `k3d-hub-flux-server-0` absent"
    why_human: "Host-environment kernel limit (fs.inotify.max_user_instances=128) on the user's WSL2 system prevents k3s containerd from reaching ready when 4 concurrent k3d clusters are running. The static contracts (271/271 bats GREEN) prove the scripts produce correct configurations; only the runtime cluster Ready state is unverified. This is recoverable with a one-line sysctl change."
  - test: "task fix-dns-poc-capsule recovers spoke-capsule cleanly from a Docker/WSL restart"
    expected: "After the inotify fix and a Docker restart, `task fix-dns-poc-capsule` brings the cluster back to Ready=True without affecting v0.18 hub-flux or other spokes; v0.18 `task fix-dns` still works for hub-flux"
    why_human: "Procedure correctness depends on real Docker/WSL state at runtime. Static bats test confirms script shape; live behavior under a real restart cannot be grep-tested."
  - test: "Mermaid topology in docs/capsule-on-eks.md renders correctly on GitHub web UI"
    expected: "When the file is viewed on github.com, the fenced ```mermaid block renders as a flowchart TB diagram showing AWS region → EKS cluster → capsule-system + tenant namespaces → ECR/IAM/NLB topology"
    why_human: "Subjective visual verification per VALIDATION.md §Manual-Only Verifications. Bats greps the mermaid fence existence but cannot validate render fidelity."
  - test: "EKS doc reads naturally to a Mixed Eng + Cloud Ops audience for a team presentation"
    expected: "Milestone owner can walk a team end-to-end through docs/capsule-on-eks.md; sections (a)-(e) orient Cloud Ops audience; high-level walkthrough in section (d) is followed by lift-ready IRSA + LB/ALB + CapsuleConfiguration YAML blocks; NOT-PROVED 3-item list mirrors ADR-008 graduation vocabulary"
    why_human: "Subjective tone/depth/clarity calibration per VALIDATION.md §Manual-Only Verifications. Bats greps the literals but cannot validate prose readability."
---

# Phase 7: Foundation — POC Seam + spoke-capsule Cluster + EKS Capsule Doc — Verification Report

**Phase Goal:** User has a generic, sentinel-guarded POC onboarding seam, a persistent isolated `spoke-capsule` k3d cluster reconciled hub-only by Flux, and a self-contained EKS-targeted Capsule rough-cut doc usable for an immediate team presentation.

**Verified:** 2026-04-29T11:55:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (ROADMAP Success Criteria)

| #   | Truth                                                                                                                                    | Status     | Evidence                                                                                                                                                                     |
| --- | ---------------------------------------------------------------------------------------------------------------------------------------- | ---------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | EKS doc lands first — `docs/capsule-on-eks.md` (Status: Draft) covering 5 sections, walkable for team presentation                       | VERIFIED   | File exists (225 lines); `Status: Draft` present; h1 (line 9) precedes mermaid fence (line 46); all 5 D-03 + D-02 + D-04 + 7 CRD literals present; `docs-06-eks.bats` 9/9 GREEN |
| 2   | `# KARYON POC MOUNT` sentinel in `clusters/hub-flux/flux-system/kustomization.yaml`, parallel to `# KARYON SPOKES MOUNT`, survives bootstrap | VERIFIED   | `grep -cF '# KARYON POC MOUNT' clusters/hub-flux/flux-system/kustomization.yaml` = 1; `grep -cF '# KARYON SPOKES MOUNT' …` = 1; D-09 anti-pattern guard: count = 0 in peer file |
| 3   | User can run `scripts/poc/capsule/create-cluster.sh` to create persistent `spoke-capsule` k3d cluster on `k8s-net` (6446/30443/SAN/image) | VERIFIED   | Script exists, executable, `bash -n` clean; all 7 D-10 pin literals + idempotent skip-with-drift-verify + bounded-retry SAN verifier present; `poc-cluster-01-static.bats` 11/11 GREEN; live cluster created (k3d cluster list reports it) but Ready blocked by host inotify (see Human Verification §1) |
| 4   | `task preflight` reserves NodePort 30443 with fail-fast behavior                                                                          | VERIFIED   | `scripts/preflight.sh` defines `check_port_strict()` (uses `fail`, NOT `warn`); `check_port_strict 30443` invocation; PRE-15 section header; v0.18 `check_port()` warn surface preserved; `preflight-pre15.bats` 6/6 GREEN |
| 5   | Hub-flux reconciles into spoke-capsule via outer Kustomization with `spec.kubeConfig.secretRef.key: value.yaml` (P18); silent-misroute falsifier passes | VERIFIED (static) / human_needed (live) | `clusters/hub-flux/pocs/capsule.yaml` carries `metadata.name=poc-capsule`, `spec.path=./pocs/capsule`, `spec.kubeConfig.secretRef.name=spoke-capsule-kubeconfig`, `key=value.yaml`; `register-poc-cluster.sh verify_credential_layer()` body asserts spoke node-name and forbids hub node-name (`k3d-hub-flux-server-0` literal); LIVE half deferred to Human Verification §1 (inotify) |
| 6   | Tenant kubeconfig leak defense: `.gitignore` globs + `.gitleaks.toml` rule + synthetic-fixture bats verified                              | VERIFIED   | All 4 D-14 globs present in .gitignore; `id="kubeconfig-bearer-token"` rule + `(?ms)` regex + `v0.19` tag + path-allowlist in .gitleaks.toml; live gitleaks: positive fixture exit 1 with `--verbose`, negative silent; `repo-hygiene-04-poc.bats` 11/11 GREEN |
| 7   | `task fix-dns-poc-capsule` recovers spoke-capsule alone (no hub-flux/spoke-ml/spoke-apps interaction); doc procedure exists              | VERIFIED   | `scripts/poc/capsule/fix-dns.sh` + Taskfile sibling entry + `docs/poc-capsule.md` (Host restart recovery + Troubleshooting + 30443 reserved-ports table); zero hub-flux/spoke-{ml,apps} cluster commands; zero `flux check`/`flux reconcile` (D-17/ADR-004); `task --list-all` shows both `fix-dns` and `fix-dns-poc-capsule` siblings |

**Score:** 7/7 ROADMAP Success Criteria verified at the file-shape and bats-contract level. The live cluster Ready state for SC-3/SC-5 is human-verifiable (inotify fix + script re-run) and is naturally exercised by Phase 8's first success criterion (`capsule-controller-manager` pod Running on spoke-capsule).

### Required Artifacts

All 22 artifacts from PLAN frontmatter exist and pass shape contracts:

| Artifact                                                       | Expected                                                                                | Status     | Details                                                                                          |
| -------------------------------------------------------------- | --------------------------------------------------------------------------------------- | ---------- | ------------------------------------------------------------------------------------------------ |
| `tests/bats/poc-mount-01-static.bats`                          | POC-01 sentinel + aggregator + outer Kustomization shape contract                       | VERIFIED   | 8 @test cases, 8/8 GREEN                                                                          |
| `tests/bats/register-poc-cluster-01-static.bats`               | POC-02 register-poc-cluster.sh shape contract (15 tests)                                | VERIFIED   | 15 @test cases, 15/15 GREEN                                                                       |
| `tests/bats/poc-cluster-01-static.bats`                        | CAPCLU-01..04 shape contract (create-cluster + fix-dns + capsule.yaml + Taskfile + docs) | VERIFIED   | 11 @test cases, 11/11 GREEN                                                                       |
| `tests/bats/preflight-pre15.bats`                              | POC-04 check_port_strict + 30443 invocation contract                                    | VERIFIED   | 6 @test cases, 6/6 GREEN                                                                          |
| `tests/bats/repo-hygiene-04-poc.bats`                          | POC-03 .gitignore + .gitleaks rule + fixture invocation contract                        | VERIFIED   | 11 @test cases, 11/11 GREEN (including 2 live gitleaks invocations)                                |
| `tests/bats/docs-06-eks.bats`                                  | EKSDOC-01 doc-shape contract                                                            | VERIFIED   | 9 @test cases, 9/9 GREEN                                                                          |
| `tests/bats/poc-isolation-01-static.bats`                      | P31/D-12 zero spoke-capsule + register-poc-cluster mentions in v0.18 scripts            | VERIFIED   | 3 @test cases, 3/3 GREEN; live grep over 6 v0.18 scripts confirms zero violations               |
| `tests/fixtures/gitleaks/synthetic-kubeconfig.yaml`            | POC-03 positive fixture (kind: Config + inert bearer token; path-allowlisted)            | VERIFIED   | File exists; `kind: Config` + 58-char inert token; live gitleaks fires (exit 1) with --verbose    |
| `tests/fixtures/gitleaks/benign-configmap.yaml`                | POC-03 negative fixture (kind: ConfigMap, must NOT be caught)                            | VERIFIED   | File exists; `kind: ConfigMap`; live gitleaks silent (exit 0) on this fixture                     |
| `clusters/hub-flux/flux-system/kustomization.yaml` (modified)  | FLUX PATCH SURFACE extended with # KARYON POC MOUNT + - ../pocs                          | VERIFIED   | Append-only edit (lines 21-22 added); D-13 SPOKES MOUNT inheritance preserved verbatim            |
| `clusters/hub-flux/pocs/kustomization.yaml`                    | Aggregator referencing capsule.yaml                                                      | VERIFIED   | Exact yq shape: apiVersion=kustomize.config.k8s.io/v1beta1, kind=Kustomization, resources=[capsule.yaml] |
| `clusters/hub-flux/pocs/capsule.yaml`                          | Outer Flux Kustomization (poc-capsule, ./pocs/capsule, spoke-capsule-kubeconfig + key: value.yaml) | VERIFIED | metadata.name=poc-capsule; spec.kubeConfig.secretRef.{name,key} both present; P18/P40 inheritance |
| `pocs/capsule/kustomization.yaml`                              | Empty placeholder so outer Kustomization reconciles as no-op                            | VERIFIED   | apiVersion + kind correct; resources: [] (length 0); Pitfall 7 mitigated                          |
| `scripts/poc/capsule/create-cluster.sh`                        | Persistent spoke-capsule k3d create with D-10 pins + idempotent skip-with-drift-verify  | VERIFIED   | 126 lines, mode 755; all 7 D-10 literals present; preflight gate; SAN verifier (10x3s)             |
| `scripts/register-poc-cluster.sh`                              | Single-positional register-and-patch with D-07/D-09/D-11/P30 invariants + P18 falsifier | VERIFIED   | 417 lines, mode 755; ensure_hub_pocs_mount; verify_credential_layer; --from-file=value.yaml=/dev/stdin only; build_kubeconfig has :6443 (no :6446); verify_credential_layer body has :6446 |
| `scripts/poc/capsule/fix-dns.sh`                               | k3d stop/start spoke-capsule alone; zero hub-flux/spoke-ml/spoke-apps; zero flux        | VERIFIED   | 75 lines, mode 755; D-16 isolation: zero forbidden cluster commands; D-17/ADR-004: zero flux check/reconcile |
| `scripts/preflight.sh` (modified)                              | check_port_strict() helper + PRE-15 section + check_port_strict 30443 invocation         | VERIFIED   | check_port_strict body uses `fail` (not warn); v0.18 check_port + warn-loop preserved verbatim   |
| `.gitignore` (modified)                                        | 4 D-14 tenant-kubeconfig globs appended; Phase 6 D-16 globs preserved                   | VERIFIED   | All 4 globs (karyon-tenants/, *.tenant.kubeconfig, tenants/**/access.yaml, tenants/**/admin.yaml) + Phase 6 D-16 globs intact |
| `.gitleaks.toml` (modified)                                    | First positive [[rules]] block + per-fixture path allowlist; Phase 1 [allowlist] preserved | VERIFIED | id="kubeconfig-bearer-token", (?ms) multi-line regex, v0.19 tag, path-allowlist; ghp_REPLACE allowlist preserved |
| `Taskfile.yml` (modified)                                      | fix-dns-poc-capsule sibling task; existing fix-dns preserved                             | VERIFIED   | `task --list-all` shows both `fix-dns` (hub-flux) and `fix-dns-poc-capsule` (spoke-capsule) entries |
| `docs/capsule-on-eks.md` (created)                              | Self-contained EKS-target Capsule rough-cut design doc with Mermaid + 3 verbatim YAMLs + NOT-PROVED 3-item | VERIFIED   | 225 lines; Status: Draft; all 5 sections (a)-(e); Mermaid + IRSA + LB + CapsuleConfiguration YAMLs; HA Capsule + OIDC + multi-spoke locked list |
| `docs/poc-capsule.md` (created)                                 | POC operator's runbook with Host restart recovery + Troubleshooting + Reserved-ports table | VERIFIED   | 144 lines; ## Host restart recovery; ## Troubleshooting; task fix-dns-poc-capsule literal; 30443 in reserved-ports table |

### Key Link Verification

| From                                                                        | To                                                                                                | Via                                          | Status   | Details                                                                                                                                  |
| --------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- | -------------------------------------------- | -------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `clusters/hub-flux/flux-system/kustomization.yaml` (- ../pocs)              | `clusters/hub-flux/pocs/kustomization.yaml`                                                       | kustomize relative-path resource             | WIRED    | `- ../pocs` resolves to `clusters/hub-flux/pocs/` directory; aggregator file present                                                      |
| `clusters/hub-flux/pocs/kustomization.yaml` (resources: [capsule.yaml])     | `clusters/hub-flux/pocs/capsule.yaml`                                                              | kustomize aggregator entry                   | WIRED    | resources[0]=capsule.yaml; outer Kustomization file present                                                                              |
| `clusters/hub-flux/pocs/capsule.yaml` (spec.path: ./pocs/capsule)            | `pocs/capsule/kustomization.yaml`                                                                   | Flux Kustomization spec.path                 | WIRED    | path resolves; placeholder kustomization.yaml present with resources: []                                                                  |
| `clusters/hub-flux/pocs/capsule.yaml` (spec.kubeConfig.secretRef)            | Secret flux-system/spoke-capsule-kubeconfig (live, applied imperatively by register-poc-cluster.sh) | Flux secretRef.name + key: value.yaml         | WIRED    | secretRef.name + key both present in YAML; live Secret application is the runtime contract for register-poc-cluster.sh apply_hub_secret  |
| `scripts/poc/capsule/create-cluster.sh`                                      | `scripts/preflight.sh`                                                                            | preflight invocation as gate                  | WIRED    | `bash "${REPO_ROOT}/scripts/preflight.sh"` invocation present in create-cluster.sh                                                        |
| `scripts/register-poc-cluster.sh ensure_hub_pocs_mount()`                    | `clusters/hub-flux/flux-system/kustomization.yaml`                                                | yq+awk idempotent insertion (cmp-then-mv)     | WIRED    | Function body references HUB_KUST_FILE constant pinned to flux-system/kustomization.yaml; awk insert + cmp-then-mv logic present          |
| `scripts/register-poc-cluster.sh apply_hub_secret()`                         | Secret flux-system/spoke-capsule-kubeconfig                                                        | kubectl --from-file=value.yaml=/dev/stdin     | WIRED    | apply_hub_secret defined; uses --from-file=value.yaml=/dev/stdin; D-11 token safety; never --from-literal                                  |
| `scripts/register-poc-cluster.sh verify_credential_layer()`                  | spoke-capsule apiserver /api/v1/nodes endpoint                                                     | openssl + curl with bearer token + node-name proof | WIRED    | verify_credential_layer body has 127.0.0.1:6446 probe + /api/v1/nodes + k3d-${spoke}-server-0 positive proof + k3d-hub-flux-server-0 negative falsifier |
| `Taskfile.yml fix-dns-poc-capsule task`                                      | `scripts/poc/capsule/fix-dns.sh`                                                                  | task → bash invocation                       | WIRED    | task entry's cmds: `bash scripts/poc/capsule/fix-dns.sh`; sibling to existing fix-dns task (NOT parent/child env-var dispatch)            |
| `docs/poc-capsule.md`                                                        | `task fix-dns-poc-capsule`                                                                        | runbook narrative reference                   | WIRED    | Doc references `task fix-dns-poc-capsule` literal in 3 places (quickstart command, distinct-from table, troubleshooting subsection)        |

### Data-Flow Trace (Level 4)

This phase produces scripts and config files (not data-rendering components). For the artifacts that flow data:

| Artifact                                              | Data Variable / Source                                  | Produces Real Data                                                          | Status    |
| ----------------------------------------------------- | -------------------------------------------------------- | --------------------------------------------------------------------------- | --------- |
| `scripts/register-poc-cluster.sh` apply_hub_secret    | `${kubeconfig_yaml}` (from build_kubeconfig)             | Yes — bearer token + CA cert decoded from spoke's flux-reconciler-token Secret; piped via stdin to kubectl create secret  | FLOWING   |
| `scripts/register-poc-cluster.sh` verify_credential_layer | `/api/v1/nodes` JSON response (curl response)            | Live runtime data (cluster must be Ready). At static level, the script structure is correct; live half deferred to Human Verification §1 | FLOWING (static) / human_needed (live) |
| `pocs/capsule/kustomization.yaml`                     | `resources: []` (intentional empty placeholder)          | Yes — Phase 7 reconciles as no-op; Phase 8 will populate (CAP-01/02/03)     | FLOWING (no-op as designed) |

### Behavioral Spot-Checks

| Behavior                                                                       | Command                                                                                                                                       | Result                                                            | Status |
| ------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------- | ------ |
| Full bats suite passes                                                         | `bats tests/bats/`                                                                                                                            | 271 tests; 271 ok; 0 not ok                                        | PASS   |
| All 7 Phase 7 bats files individually pass                                     | `bats tests/bats/poc-{mount,cluster,isolation}-01-static.bats tests/bats/register-poc-cluster-01-static.bats tests/bats/preflight-pre15.bats tests/bats/repo-hygiene-04-poc.bats tests/bats/docs-06-eks.bats` | 63 tests; 63 ok; 0 not ok                                          | PASS   |
| `bash -n` syntax-check all 3 new shell scripts                                  | `bash -n scripts/poc/capsule/create-cluster.sh && bash -n scripts/register-poc-cluster.sh && bash -n scripts/poc/capsule/fix-dns.sh`           | exit 0                                                            | PASS   |
| Live gitleaks fires on positive fixture (absolute path; --verbose)              | `gitleaks detect --no-git --source $(pwd)/tests/fixtures/gitleaks/synthetic-kubeconfig.yaml --config .gitleaks.toml --verbose`                  | exit 1; "leaks found: 2"; RuleID=kubeconfig-bearer-token            | PASS   |
| Live gitleaks silent on negative fixture                                       | `gitleaks detect --no-git --source $(pwd)/tests/fixtures/gitleaks/benign-configmap.yaml --config .gitleaks.toml`                              | exit 0; "no leaks found"                                          | PASS   |
| `task --list-all` shows both fix-dns and fix-dns-poc-capsule sibling tasks      | `task --list-all 2>&1 \| grep fix-dns`                                                                                                       | 2 entries (fix-dns: hub-flux; fix-dns-poc-capsule: spoke-capsule)   | PASS   |
| `task fix-dns-poc-capsule` actually recovers spoke-capsule from a real Docker/WSL restart | (manual)                                                                                                                                      | requires runtime + Docker restart                                 | SKIP — see Human Verification §2 |
| `bash scripts/poc/capsule/create-cluster.sh && bash scripts/register-poc-cluster.sh spoke-capsule` brings cluster Ready and P18 falsifier passes | (manual; requires inotify fix)                                                                                                                | k3d cluster create succeeded but Ready blocked by host kernel limit | SKIP — see Human Verification §1 |

### Requirements Coverage

| Requirement | Source Plan(s)        | Description                                                                                                                                                  | Status     | Evidence                                                                                                            |
| ----------- | --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------- | ------------------------------------------------------------------------------------------------------------------- |
| POC-01      | 07-00, 07-02          | User can mount POC Kustomizations via `# KARYON POC MOUNT` sentinel                                                                                          | SATISFIED  | Sentinel + - ../pocs in FLUX PATCH SURFACE; aggregator + capsule.yaml + placeholder; poc-mount-01-static.bats 8/8 GREEN |
| POC-02      | 07-00, 07-03          | User can register POC cluster via `scripts/register-poc-cluster.sh <cluster-name>` (mirrors register-spokes-for-flux.sh)                                      | SATISFIED  | 417-line script with all D-07/D-09/D-11/P30 invariants; register-poc-cluster-01-static.bats 15/15 GREEN              |
| POC-03      | 07-00, 07-04          | Tenant kubeconfigs blocked from commit by `.gitignore` globs + `.gitleaks.toml` rule for kind: Config + bearer-token shape                                  | SATISFIED  | 4 globs + kubeconfig-bearer-token rule + per-fixture allowlist; live gitleaks fires/silent on fixtures; repo-hygiene-04-poc.bats 11/11 GREEN |
| POC-04      | 07-00, 07-04          | `task preflight` reserves NodePort 30443 with fail-fast                                                                                                       | SATISFIED  | check_port_strict() (uses fail) + check_port_strict 30443 invocation + PRE-15 section; preflight-pre15.bats 6/6 GREEN  |
| CAPCLU-01   | 07-00, 07-03          | User can create persistent `spoke-capsule` k3d cluster on `k8s-net` (6446/30443/SAN/image)                                                                  | SATISFIED (static); needs human (live) | scripts/poc/capsule/create-cluster.sh with all D-10 pins; idempotent skip-with-drift-verify; SAN verifier; live cluster created but Ready blocked by inotify (Human Verification §1) |
| CAPCLU-02   | 07-00, 07-02, 07-03   | Hub-flux reconciles into spoke-capsule via `clusters/hub-flux/pocs/capsule.yaml` with secretRef.key: value.yaml; silent-misroute falsifier passes           | SATISFIED (static); needs human (live) | capsule.yaml shape correct; verify_credential_layer with /api/v1/nodes + k3d-hub-flux-server-0 negative-proof literal; live half deferred (Human Verification §1) |
| CAPCLU-03   | 07-00, 07-05          | `task fix-dns-poc-capsule` recovers spoke-capsule alone via `scripts/poc/capsule/fix-dns.sh`                                                                | SATISFIED  | Script exists with D-16 + D-17 + ADR-004 invariants; sibling Taskfile entry; poc-cluster-01-static.bats CAPCLU-03 GREEN |
| CAPCLU-04   | 07-00, 07-05          | Documented host-restart procedure in `docs/poc-capsule.md`                                                                                                   | SATISFIED  | 144-line doc with Host restart recovery + Troubleshooting + Reserved-ports table + 30443 reservation                  |
| EKSDOC-01   | 07-00, 07-01          | `docs/capsule-on-eks.md` exists at start of Phase 7 with all 5 sections (a)-(e); Mermaid + 3 verbatim YAMLs + NOT-PROVED 3-item list                       | SATISFIED  | 225-line doc with Status: Draft; sections a-e; Mermaid topology; IRSA + LB + CapsuleConfiguration YAMLs; locked NOT-PROVED list; docs-06-eks.bats 9/9 GREEN |

**All 9 REQ-IDs from PLAN frontmatter are SATISFIED at the static-contract level.** The two requirements with a live runtime aspect (CAPCLU-01-live and CAPCLU-02-live) are routed to Human Verification §1; their static contracts (script shape, file shape, bats greens) are fully verified.

**Cross-reference against REQUIREMENTS.md:** All 9 Phase 7 REQ-IDs (POC-01..04, CAPCLU-01..04, EKSDOC-01) are accounted for in PLAN frontmatter. Zero orphaned requirements. Mapping matches the REQUIREMENTS.md traceability table (lines 148-156).

### Decision Coverage (CONTEXT.md D-01..D-17)

All 17 decisions from `07-CONTEXT.md` are honored in the codebase:

| Decision | Description                                                          | Honored | Evidence                                                                                                            |
| -------- | -------------------------------------------------------------------- | ------- | ------------------------------------------------------------------------------------------------------------------- |
| D-01     | EKS doc audience (Mixed Eng + Cloud Ops, brief, admin emphasis)      | YES     | docs/capsule-on-eks.md narrative + section structure                                                                |
| D-02     | Section (d) high-level walkthrough + 3 verbatim YAMLs                | YES     | 7-step numbered walkthrough + IRSA TrustPolicy + NLB Service + ALB Ingress + CapsuleConfiguration verbatim YAMLs    |
| D-03     | Mermaid topology transcribed from research SUMMARY ASCII             | YES     | Single fenced ```mermaid block with flowchart TB EKS topology                                                       |
| D-04     | Locked 3-item NOT-PROVED structure (HA + OIDC + multi-spoke)         | YES     | Section (e) carries exactly HA Capsule + OIDC + multi-spoke; no EKS-flavored extras                                  |
| D-05     | KARYON POC MOUNT below SPOKES MOUNT                                  | YES     | grep adjacency confirms sentinel + - ../pocs directly below SPOKES MOUNT block                                       |
| D-06     | pocs/ aggregator + flat capsule.yaml mirroring spokes/                | YES     | Identical structural mirror confirmed via yq queries                                                                |
| D-07     | register-poc-cluster.sh single positional + implicit context         | YES     | "$#" -ne 1 + POC_CLUSTER="$1" + POC_CTX="k3d-${POC_CLUSTER}" all literal-present                                    |
| D-08     | Phase 7 scripts/poc/capsule/ = create-cluster.sh + fix-dns.sh ONLY    | YES     | `ls scripts/poc/capsule/` shows exactly create-cluster.sh + fix-dns.sh                                              |
| D-09     | Sentinel placement = FLUX PATCH SURFACE (NOT peer file)              | YES     | grep -cF in flux-system/kustomization.yaml = 1; grep -cF in peer kustomization.yaml = 0                              |
| D-10     | spoke-capsule pins (6446/30443/SAN/k8s-net/k3s:v1.34.6)              | YES     | All 5 readonly constants + inline literals in create-cluster.sh                                                     |
| D-11     | secretRef.name + key: value.yaml + token safety (no --from-literal)  | YES     | capsule.yaml shape verified; register-poc-cluster.sh negative-grep on --from-literal returns 0; --from-file=value.yaml=/dev/stdin only |
| D-12     | All POC concerns under scripts/poc/capsule/; v0.18 scripts have ZERO mentions | YES | poc-isolation-01-static.bats 3/3 GREEN; live grep over 6 v0.18 scripts confirms zero violations                     |
| D-13     | EKSDOC-01 lands FIRST (Wave 1 Plan 07-01)                             | YES     | Plan 07-01 was Wave 1; commit 72f3666 (docs/capsule-on-eks.md) precedes Wave 2/3 commits                            |
| D-14     | .gitleaks.toml gains kubeconfig+bearer-token rule + .gitignore globs | YES     | Plan 07-04 delivered; live gitleaks evidence + 4 .gitignore globs verified                                          |
| D-15     | check_port_strict() helper (fail, not warn) for 30443                | YES     | Body uses fail; v0.18 check_port + warn-loop preserved verbatim                                                     |
| D-16     | task fix-dns-poc-capsule sibling task; no hub-flux interaction        | YES     | Sibling Taskfile entry; fix-dns.sh has zero hub-flux/spoke-ml/spoke-apps cluster commands                           |
| D-17     | ADR-004 hub-only Flux preserved; NO Flux on spoke-capsule             | YES     | fix-dns.sh has zero `flux check`/`flux reconcile`; tool gate drops `flux` from analog                                |

**17/17 D-NN decisions honored.** Plan-checker iteration 2 confirmed this earlier; verification re-confirms no drift between plan and codebase.

### Anti-Patterns Found (Code-Review WARNINGs from 07-REVIEW.md — advisory only)

These were flagged by `/gsd-code-review` and are NOT verifier-discovered gaps. Listed here for completeness; recommended treatment is `/gsd-code-review-fix 7` post-verification.

| File                                                | Line(s) | Pattern                                                                                       | Severity | Impact                                                                                  |
| --------------------------------------------------- | ------- | --------------------------------------------------------------------------------------------- | -------- | --------------------------------------------------------------------------------------- |
| `.gitleaks.toml`                                    | 28      | `kind: Config` regex over-broad (matches `kind: ConfigMap` prefix) [WR-01]                     | WARNING  | Negative fixture passes for wrong reason (length, not kind discrimination); future ConfigMaps with 32+ char tokens may false-positive |
| `scripts/register-poc-cluster.sh`                   | 230-241 | `ensure_hub_pocs_mount` awk inserts duplicate sentinel under hand-edited mis-ordered file [WR-02] | WARNING  | P30 sentinel-uniqueness is fragile if a human reorders the kustomization.yaml             |
| `scripts/poc/capsule/fix-dns.sh`                    | 41-46   | Aborts on already-stopped cluster — contradicts docs/poc-capsule.md troubleshooting [WR-03]     | WARNING  | Idempotent re-run from a stopped state requires manual k3d cluster start (workaround documented in poc-capsule.md) |
| `scripts/register-poc-cluster.sh verify_credential_layer` | 300-355 | mktemp cleanup gap — leaks PUBLIC CA cert tempfile on unexpected error [WR-04]              | WARNING  | Disk-space hygiene; not a security exposure (CA cert is public)                          |
| `scripts/poc/capsule/fix-dns.sh + register-poc-cluster.sh` | (multiple) | Literal `${POC_CLUSTER}` in shell COMMENTS (cosmetic) [WR-05]                              | WARNING  | Misleading documentation — comments don't expand `${...}`; isolation tests filter comments so no isolation regression |

**Status:** Code-review WARNINGs are advisory; the verifier confirms they do not block phase goal achievement. They are tracked for `/gsd-code-review-fix 7` cleanup.

### Out-of-Scope Items (Deferred to Phase 7 follow-up planning per `deferred-items.md`)

| Item                                                                                                              | Treatment                                                                                                                         |
| ----------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| 4 (now 5) gitleaks hits in planning docs that quote the synthetic fixture content (07-00-PLAN.md, 07-RESEARCH.md, 07-REVIEW.md) | Documented in `deferred-items.md`; recommended Option 4 (no action — leak material is provably inert; pre-commit only scans staged) |

This is a known limitation of running `gitleaks detect --no-git --source .` repo-wide; pre-commit scans only check staged files where the synthetic fixture's path-allowlist works correctly. Not a Phase 7 goal-blocker.

### Human Verification Required

Per Step 8 of the verification process, four items require human testing because they cannot be programmatically verified:

#### 1. Live spoke-capsule cluster reaches Ready=True after raising inotify limit

**Test:** Run `sudo sysctl -w fs.inotify.max_user_instances=1024` then `bash scripts/poc/capsule/create-cluster.sh && bash scripts/register-poc-cluster.sh spoke-capsule`.
**Expected:** create-cluster.sh exits 0 with "cluster spoke-capsule ready"; register-poc-cluster.sh exits 0 with "P18 falsifier passing"; `kubectl --context k3d-spoke-capsule get nodes` shows `k3d-spoke-capsule-server-0 Ready`; `flux --context k3d-hub-flux get kustomization poc-capsule -n flux-system` shows Ready=True.
**Why human:** Host-environment kernel limit (`fs.inotify.max_user_instances=128`) on the user's WSL2 system prevents k3s containerd from reaching ready when 4 concurrent k3d clusters are running. The static contracts (271/271 bats GREEN) prove the scripts produce correct configurations; only the runtime cluster Ready state is unverified. This is recoverable with a one-line sysctl change and is a precondition for Phase 8 anyway (Phase 8 SC-1 requires the operator pod Running on spoke-capsule).

#### 2. `task fix-dns-poc-capsule` recovers spoke-capsule cleanly from a Docker/WSL restart

**Test:** After the inotify fix and a Docker daemon (or WSL2) restart, run `task fix-dns-poc-capsule`.
**Expected:** Cluster returns to Ready=True; v0.18 hub-flux + spoke-ml + spoke-apps untouched; v0.18 `task fix-dns` (separate command) still works for hub-flux.
**Why human:** Procedure correctness depends on real Docker/WSL state at runtime. Static bats test confirms script shape; live behavior under a real restart cannot be grep-tested.

#### 3. Mermaid topology in docs/capsule-on-eks.md renders correctly on GitHub web UI

**Test:** View `docs/capsule-on-eks.md` on github.com.
**Expected:** The fenced ```mermaid block renders as a flowchart TB diagram showing AWS region → EKS cluster → capsule-system + tenant namespaces → ECR/IAM/NLB topology.
**Why human:** Subjective visual verification per `07-VALIDATION.md §Manual-Only Verifications`. Bats greps the mermaid fence existence but cannot validate render fidelity.

#### 4. EKS doc reads naturally to a Mixed Eng + Cloud Ops audience for a team presentation

**Test:** Walk a team end-to-end through `docs/capsule-on-eks.md`.
**Expected:** Sections (a)-(e) orient Cloud Ops audience; high-level walkthrough in section (d) is followed by lift-ready IRSA + LB/ALB + CapsuleConfiguration YAML blocks; NOT-PROVED 3-item list mirrors ADR-008 graduation vocabulary.
**Why human:** Subjective tone/depth/clarity calibration per `07-VALIDATION.md §Manual-Only Verifications`. Bats greps the literals but cannot validate prose readability.

### Gaps Summary

**No verifier-discovered gaps.** All 7 ROADMAP success criteria, all 9 REQ-IDs, and all 17 D-NN decisions are honored. All 22 artifacts pass shape contracts. All 271 bats tests pass (171 v0.18 + 63 Phase 7 + 37 from earlier phases = 271 total). Live gitleaks behavior verified on both fixtures. Live cluster Ready state and a few subjective items require human verification (above).

The 5 code-review WARNINGs are advisory and should be addressed via `/gsd-code-review-fix 7` after this verification, but do not block the Phase 7 goal.

The phase goal — "User has a generic, sentinel-guarded POC onboarding seam, a persistent isolated `spoke-capsule` k3d cluster reconciled hub-only by Flux, and a self-contained EKS-targeted Capsule rough-cut doc usable for an immediate team presentation" — is achieved at the file/contract level. The persistent cluster's *runtime Ready state* is the only piece routed to human verification because it depends on a host kernel limit that is outside the codebase.

---

_Verified: 2026-04-29T11:55:00Z_
_Verifier: Claude (gsd-verifier)_
_Total bats: 271/271 GREEN (zero v0.18 regressions)_
_Phase 7 bats: 63/63 GREEN across 7 files_
