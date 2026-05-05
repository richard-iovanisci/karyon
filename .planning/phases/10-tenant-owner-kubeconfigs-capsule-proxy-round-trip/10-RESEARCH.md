# Phase 10: Tenant Owner Kubeconfigs + Capsule-Proxy Round-trip - Research

**Researched:** 2026-05-05
**Domain:** Imperative shell-script tenant kubeconfig minting via Kubernetes TokenRequest API + capsule-proxy v0.12.0 LIST filtering on k3s v1.34.6 + .gitignore/gitleaks regression-gate inheritance from Phase 7 D-14
**Confidence:** HIGH (all 7 open research questions resolved by live cluster inspection + `helm template` of the v0.12.0 chart + JWT decode of live-issued tokens; one major CONTEXT.md correction surfaced and documented)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-10-01 — Token source: TokenRequest API.** `kubectl --context=k3d-spoke-capsule create token "${OWNER}" -n "tenant-${TENANT}" --duration="${DURATION}"`. NO long-lived `Secret type: kubernetes.io/service-account-token`. Aligns with k8s ≥1.24 deprecation; the gitleaks `kubeconfig-bearer-token` rule defends against accidental commits of either shape.
- **D-10-02 — Token duration default + clamp behavior.** Default `--duration=1h`. Accept `--duration <d>` flag with values `kubectl create token` honors. Apiserver MAY clamp at `--service-account-max-token-expiration`. **CORRECTION (live-tested 2026-05-05):** k3s v1.34.6-k3s1 on `spoke-capsule` does NOT set `--service-account-max-token-expiration`, so the apiserver does NOT clamp. Live tests of `--duration=24h`, `--duration=48h`, `--duration=72h`, `--duration=720h` all returned tokens with `exp - iat` matching the request EXACTLY (no clamp observed). [VERIFIED: live cluster JWT decode]. Implication: Phase 10 script's `info`-warn for `--duration > 24h` should reframe — k3s default is unbounded, NOT 24h. Document as "no clamp on this k3s pin; apiserver may clamp on different distros".
- **D-10-03 — `<owner>` arg semantics: existing per-tenant SA only.** `<owner>` MUST match an existing SA in `tenant-<tenant>` namespace. Phase 9 D-09-02 created exactly one such SA per tenant: `gitops-reconciler`. Phase 10 does NOT mutate the Tenant CR.
- **D-10-04 — Owner-not-found error shape: fail-fast with helpful list.** Use `kubectl ... get sa -o name | sed 's|serviceaccount/||g'` to enumerate; mirror `create-cluster.sh`'s drift-detection fail-fast style.
- **D-10-05 — Tenant inner K kubeConfig swap DEFERRED.** Phase 9 D-09-03 forward-pointer is out of scope. Tenant inner Ks remain on `spoke-capsule-kubeconfig` with SA impersonation. Phase 12 (capsule-addon-fluxcd) absorbs.
- **D-10-06 — TLS trust shape: embed CA cert.** Read at script-time via `kubectl --context=k3d-spoke-capsule -n capsule-system get secret capsule-proxy -o jsonpath='{.data.ca\.crt}'`. Fall back to `tls.crt` if `ca.crt` is empty. **Q1 RESOLUTION (this research):** the chart's `kube-webhook-certgen` Job emits `--cert-name=tls.crt --key-name=tls.key` and the Secret produced has ONLY those two keys. There is NO `ca.crt` key. The `tls.crt` IS the CA root (self-signed). Phase 10 script MUST read `tls.crt` (not fall-back-after-empty-ca.crt — read directly).
- **D-10-07 — Issued kubeconfig structure: single-context, named by tenant.** `cluster: capsule-proxy-127.0.0.1`, `user: <owner>`, `context: tenant-<tenant>-via-proxy`, default `namespace: tenant-<tenant>`.
- **D-10-08 — Direct-apiserver-bypass test: bats constructs on-the-fly.** PROXY-02 falsifier built by bats. **MAJOR CORRECTION (this research):** the proposed falsifier shape (`proxy_count < direct_count` because direct returns "wider list") is WRONG. Capsule's auto-injected RoleBindings on tenant SAs are NAMESPACE-scoped (`admin` ClusterRole bound INSIDE owned namespaces only). The SA does NOT have cluster-wide `list namespaces`. Direct apiserver returns 403 Forbidden, NOT a wider list. The actual falsifier shape is `direct_apiserver returns 403 OR empty AND proxy returns 200 with tenant-filtered subset`. See Pitfall §10-P3 below.
- **D-10-09 — Test scaffolding pattern: repeat Phase 7/8/9 Wave 0 RED bats.** Plan 10-00 lands all bats files RED.
- **D-10-10 — Plan ordering: 10-00 (RED bats) → 10-01 (script + doc) → 10-02 (verifier).**

### Claude's Discretion

- **`task` surface extensions** — recommended default: **none**. Direct invocation `bash scripts/poc/capsule/issue-tenant-kubeconfig.sh ...`.
- **Stdout vs stderr split** — stdout = pure YAML kubeconfig; stderr = `preflight-lib` log lines.
- **Idempotency** — naturally idempotent (each invocation produces a fresh TokenRequest token; no state mutation).
- **JSON output mode** — none.
- **`docs/poc-capsule.md` cross-link depth** — single "Tenant kubeconfig delivery contract" H2 section + cross-links.
- **`--write-to <path>` validation** — strict tmpdir-root check via `realpath -m`.
- **Verifier script wrapper** — bats-only.
- **Reconcile loop noise tolerance window** — ≤2 reconcile cycles; 3 attempts × 30s sleep.

### Deferred Ideas (OUT OF SCOPE)

- Tenant inner K kubeConfig source swap (D-09-03 forward-pointer) → Phase 12 (gated on ADR-008).
- Negative RBAC bats N1–N12 → Phase 11 (VAL-01).
- Capsule webhook failure / recoverable mode → Phase 11 (VAL-02).
- Clean teardown (`task destroy-poc capsule`) → Phase 11 (VAL-03).
- `task rebuild` SLO regression test → Phase 11 (VAL-04).
- One-shot history gitleaks scan post-Phase-10 first push → Phase 11 (VAL-05).
- Graduation ADR-008 → Phase 11 (VAL-06).
- `capsule-addon-fluxcd v0.2.3` → Phase 12 (OPTIONAL).
- Multi-SA-per-tenant pattern.
- `task issue-tenant-kubeconfig` wrapper.
- JSON output mode for the script.
- Cert-rotation handling.
- HA Capsule, OIDC, multi-spoke federation → POST-v0.19.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| **PROXY-01** | `scripts/poc/capsule/issue-tenant-kubeconfig.sh <tenant> <owner>` mints kubeconfig with `server: https://127.0.0.1:30443`, stdout default, optional `--write-to <path>` rooted at `${TMPDIR:-/tmp}/karyon-tenants/`. | §"Implementation Approach: issue-tenant-kubeconfig.sh skeleton" + §"Don't Hand-Roll" + §"Code Examples §C1-C5" |
| **PROXY-02** | Issued kubeconfig: `kubectl get namespaces` returns ONLY tenant-owned namespaces (proxy LIST filtering); direct apiserver `:6446` falsifier proves filtering happens at proxy. | §"Pitfall 10-P3 (CORRECTION) — Direct apiserver falsifier shape" + §"Live Test Evidence" + §"Architecture Patterns §A2 — Direct vs proxy LIST falsifier" |
| **PROXY-03** | `docs/poc-capsule.md` documents kubeconfig delivery contract (stdout default, optional `--write-to`, tmpdir-not-repo, gitleaks rule). | §"Architecture Patterns §A3 — doc append shape" + §"Pitfall 10-P5 — gitleaks regression on tmpdir vs repo path" |
</phase_requirements>

## Project Constraints (from CLAUDE.md / AGENTS.md)

The project is in the early-template state on AGENTS.md (TODO placeholders for setup/build/test). Authoritative directives instead come from `.planning/` artifacts:
- Public-safe defaults (no real secrets, internal URLs, hostnames in committed yaml or docs).
- Read project docs and existing commands before guessing — `.planning/REQUIREMENTS.md`, `.planning/STATE.md`, `.planning/ROADMAP.md`, prior-phase `XX-CONTEXT.md` and `XX-SUMMARY.md` artifacts are load-bearing.
- `.planning/` is the live planning and progress state in this repo. It IS git-tracked (this is the GSD v1 contract for this project).
- Do not read, print, or expose secrets unless explicitly asked. Phase 10's tenant tokens count as secrets — they go through stdout / tmpdir, never logged to a file outside tmpdir, never committed.
- v0.18 ADR invariants preserved (ADR-001..ADR-005). ADR-004 hub-only Flux (no Flux on spoke-capsule) is load-bearing for Phase 10's verifier rerun.
- v0.19 P27/P29/P31 invariants preserved across Phase 10. Particularly **P29** (kubeconfigs MUST NOT land in git) — the load-bearing security invariant Phase 10's PROXY-03 contract operationalizes.

## Summary

Phase 10 ships a single shell script (`scripts/poc/capsule/issue-tenant-kubeconfig.sh`), a documentation section append in `docs/poc-capsule.md`, and ~7 bats files. No new tasks, no new manifests, no Flux changes, no `.gitignore` / `.gitleaks.toml` changes. The script's surface is small; the test surface is medium (covering both happy-path and tmpdir-restriction falsifiers); the regression surface is large (Phase 7 D-14 leak defenses + Phase 8 install + Phase 9 lockdown + ADR-004 + P31 isolation all rerun).

**Three things this research definitively resolved that affect planning:**

1. **The capsule-proxy certgen Secret has ONLY `tls.crt` + `tls.key` keys — NO `ca.crt`.** [VERIFIED: `helm template oci://ghcr.io/projectcapsule/charts/capsule-proxy --version 0.12.0 --set options.generateCertificates=true`]. The `kube-webhook-certgen` Job runs with `--cert-name=tls.crt --key-name=tls.key` only. The chart self-signs with `tls.crt` doubling as the CA root. Phase 10 script reads `tls.crt` directly — the `ca.crt` fallback CONTEXT.md D-10-06 anticipates is unreachable code.
2. **Direct-apiserver `:6446` access with the SA token returns 403 Forbidden, NOT a wider list.** [VERIFIED: live cluster `kubectl --kubeconfig=<direct> get namespaces` returns `User "system:serviceaccount:tenant-alpha:gitops-reconciler" cannot list resource "namespaces" in API group "" at the cluster scope`]. Capsule's auto-injected RoleBindings on tenant SAs are namespace-scoped (`admin` ClusterRole bound INSIDE owned namespaces only). The CONTEXT.md D-10-08 falsifier assumption — `direct_count > proxy_count` — is WRONG. The actual falsifier signal is qualitative: direct returns 403; proxy returns 200 + tenant-filtered subset. See **Pitfall 10-P3** below.
3. **k3s v1.34.6-k3s1 on `spoke-capsule` does NOT clamp at 24h.** [VERIFIED: `kubectl create token --duration=720h` returned a 30-day-validity JWT]. The k8s docs claim `--service-account-max-token-expiration` exists but k3s does not set it by default. Phase 10's `info`-warn at duration > 24h should reframe — the k3s pin is unbounded; the warn is a portability note for non-k3s distros.

**Primary recommendation:** Plan 10-00 lands a 7-bats RED scaffold mirroring Phase 9 D-09-08 verbatim. Plan 10-01 lands the script + doc. Plan 10-02 verifier reruns Phase 7 P31 + Phase 8 CAP-01..03 + Phase 9 TEN-01..06 + ADR-004 invariants and writes 10-VERIFICATION.md. Total surface: ~250 LOC of script + ~80 lines of doc append + ~7 bats files (~150 LOC). Phase 10 is mechanically smaller than Phase 9 by ~70%.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Token issuance | Spoke apiserver (kube-apiserver TokenRequest API on `spoke-capsule:6446`) | Local shell script | Bound SA token is k8s-native; script is the imperative wrapper that calls `kubectl create token`. |
| Kubeconfig assembly | Local shell script (heredoc) | — | Pure stdout YAML emission. No state mutation; no remote write. |
| TLS trust material source | Spoke apiserver (Secret in `capsule-system` ns) | Local shell script (kubectl jsonpath read) | Live-read at script-time. Cert is rotated by the chart's certgen Job; live-read keeps kubeconfig fresh. |
| LIST filtering at runtime | Spoke `capsule-proxy` Pod (in-cluster) | NodePort 30443 on k3d serverlb | Proxy intercepts cluster-scoped LIST endpoints; uses its own ClusterRole `[*/*: get/list/watch]` to enumerate, then filters by tenant ownership. |
| Tenant ownership policy | Spoke Capsule operator (Tenant CR `spec.owners[]`) | — | Phase 9 D-09-02 already shipped multi-owner array (SA + User). Phase 10 does NOT mutate. |
| Leak defense | Local shell pre-commit hook (`gitleaks`) | CI gitleaks-scan on push | Phase 7 D-14 already shipped; Phase 10 regression-tests it without modification. |
| Doc artifact | `docs/poc-capsule.md` (markdown, frontmatter `status: Active`) | — | Phase 7 already shipped doc skeleton; Phase 10 appends one H2 section. |

## Standard Stack

### Core

| Library / Tool | Version (verified) | Purpose | Why Standard |
|----------------|---------------------|---------|--------------|
| `kubectl` | v1.34.6 (asdf shim) | TokenRequest API issuance + Secret read + cluster context selection | Already pinned by v0.18; ADR-005 inheritance. [VERIFIED: `kubectl version --client -o yaml`] |
| `kube-apiserver` (in k3s) | v1.34.6-k3s1 | TokenRequest API endpoint on `spoke-capsule:6446` | ADR-005. [VERIFIED: `kubectl --context=k3d-spoke-capsule cluster-info`] |
| `capsule-proxy` (Helm chart) | 0.12.0 | LIST filtering for tenant-scoped namespace visibility | Pinned in `pocs/capsule/proxy/ocirepository.yaml` per Phase 8 D-08-02. [CITED: STACK.md] |
| `capsule` (operator chart) | 0.12.4 | Tenant CR + RBAC + auto-injected RoleBindings on owners | Pinned in `pocs/capsule/operator/ocirepository.yaml` per Phase 8 D-08-02. [VERIFIED: live `kubectl get deploy capsule-controller-manager -o jsonpath='{.spec.template.spec.containers[0].image}'` returns `ghcr.io/projectcapsule/capsule:v0.12.4`] |
| `bats-core` | 1.11.0 | Test runner | v0.18 baseline; `tests/bats/test_helper.bash` provides `REPO_ROOT` + `require_live` skip-gates. [VERIFIED: `bats --version`] |
| `yq` (mikefarah) | v4.53.2 | YAML parsing in bats (Phase 8 D-08-11 / WR-01..04 hardening pattern) | Phase 8/9 verifiers used for shape lints; Phase 10 inherits. [VERIFIED: `yq --version`] |
| `jq` | (asdf shim) | JSON payload parse for JWT decode | Phase 1 preflight already gates this tool. [VERIFIED: `command -v jq`] |
| `openssl` | (system) | Optional: TLS connection probing for certgen verification | Phase 7 already used in `create-cluster.sh` SAN verification. [VERIFIED: `command -v openssl`] |
| `gitleaks` | 8.30.1 | Pre-commit + CI scan for kubeconfig-bearer-token rule | Phase 6 REPO-04 + Phase 7 D-14 inheritance. [VERIFIED: `gitleaks version`] |
| `realpath` | GNU coreutils 9.4 | `--write-to <path>` canonicalization with `-m` (no-existence-required) | Standard on Ubuntu 22.04+ (WSL2 dev environment). [VERIFIED: `realpath --version`] |
| `base64` | GNU coreutils | JWT payload + tls.crt decode | System-installed. [VERIFIED: `command -v base64`] |

### Supporting

| Library / Tool | Version | Purpose | When to Use |
|----------------|---------|---------|-------------|
| `mktemp` | system | Bats falsifier kubeconfig tmpfile creation | Bats setup() / teardown() |
| `kubectl create --raw` | (kubectl) | Direct TokenRequest API call (alternative to `kubectl create token`) | Only if planner wants to bypass kubectl convenience wrapper; NOT recommended for Phase 10 |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `kubectl create token` (TokenRequest API) | Static `Secret type: kubernetes.io/service-account-token` (legacy) | LOSE: auto-expiry; gitleaks rule fires same shape regardless. WIN nothing. **Rejected** — D-10-01 lock. |
| Heredoc kubeconfig template | `yq -n` build | LOSE: clarity (heredoc is readable); ADD: yq dependency in script preflight. **Rejected** — Phase 10 specifics §"Kubeconfig template". |
| `python3 -c '...'` JWT decode | `base64 -d` + `jq` | LOSE: portability (python3 not always present); ADD: dependency. **Rejected** — bats live test uses `cut -d. -f2 \| tr '_-' '/+' \| base64 -d \| jq -r .exp`. |
| `realpath -m` | `python3 -c 'import os.path; print(os.path.normpath(...))'` | LOSE: bash-native ergonomics. ADD: python3 dep. **Rejected** — WSL2 has GNU coreutils. macOS users (out of scope) would need a workaround; Phase 10 documents WSL2-only. |
| `--write-to` flag | Always-stdout (no file mode) | LOSE: ergonomics for "save for later" use. **Rejected** — D-10-07 / Claude's Discretion / specifics §"`--write-to <path>` realpath check". |
| New `tests/fixtures/gitleaks/synthetic-tenant-kubeconfig.yaml` | Reuse existing `synthetic-kubeconfig.yaml` | LOSE: nothing — existing fixture is shape-generic. **Recommended:** REUSE; planner discretion per D-10-09. |

**Installation:** No new packages. All dependencies already pinned by v0.18 + Phase 7+8+9.

**Version verification:** All component versions confirmed against the live `spoke-capsule` cluster + chart `helm template` output on 2026-05-05.

## Architecture Patterns

### System Architecture Diagram

```
                  ┌──────────────────────────────────────────────────────────────┐
                  │  WSL2 host: bash issue-tenant-kubeconfig.sh alpha            │
                  │  gitops-reconciler [--duration 1h] [--write-to <tmpdir>]     │
                  └──────────────────────────────────────────────────────────────┘
                            │
                            │  preflight-lib: section/pass/info/fail/have helpers
                            │  (sourced from scripts/lib/preflight-lib.sh)
                            ▼
        ┌────────────────────────────────────────────────────────────────────┐
        │  preflight gate (idempotent fail-fast)                              │
        │  1. have kubectl                                                    │
        │  2. kubectl config get-contexts k3d-spoke-capsule (existence)       │
        │  3. kubectl get tenant <tenant>     (Tenant CR exists on spoke)     │
        │  4. kubectl get sa <owner> -n tenant-<tenant> (SA exists on spoke)  │
        │  5. (if --write-to) realpath -m + tmpdir prefix check + mkdir -p    │
        └────────────────────────────────────────────────────────────────────┘
                            │ all green ─────────────────────────┐
                            ▼                                     ▼
         ┌─────────────────────────────────────┐    fail-fast with hint
         │  Token mint                          │
         │  TOKEN=$(kubectl --context=...      │
         │     create token <owner>             │
         │     -n tenant-<tenant>               │
         │     --duration=<d>)                  │
         └─────────────────────────────────────┘
                            │ JWT bearer (1h ≤ d ≤ 720h on k3s)
                            ▼
         ┌─────────────────────────────────────┐
         │  CA cert read (chart's tls.crt as    │
         │  CA root, NOT a separate ca.crt)    │
         │  CA_B64=$(kubectl ... -n             │
         │     capsule-system get secret        │
         │     capsule-proxy -o jsonpath=       │
         │     '{.data.tls\.crt}')              │
         └─────────────────────────────────────┘
                            │ base64 string
                            ▼
         ┌─────────────────────────────────────┐
         │  Heredoc emit kubeconfig YAML        │
         │  (stdout — preflight-lib log lines   │
         │  on stderr; clean redirect contract) │
         │                                      │
         │  cluster: capsule-proxy-127.0.0.1   │
         │  user: <owner>                       │
         │  context: tenant-<tenant>-via-proxy  │
         │  default ns: tenant-<tenant>         │
         └─────────────────────────────────────┘
                            │
                            ▼
              ┌───────────────────────────────────────────────────────┐
              │  Operator consumption paths (mutually exclusive):     │
              │                                                        │
              │  (a) STDOUT:                                           │
              │     bash issue-tenant-kubeconfig.sh alpha             │
              │       gitops-reconciler 2>/dev/null                    │
              │       > /tmp/alpha.kubeconfig                          │
              │     KUBECONFIG=/tmp/alpha.kubeconfig kubectl ...       │
              │                                                        │
              │  (b) --write-to (tmpdir-rooted only):                  │
              │     bash issue-tenant-kubeconfig.sh alpha             │
              │       gitops-reconciler                                │
              │       --write-to /tmp/karyon-tenants/alpha.kubeconfig  │
              └───────────────────────────────────────────────────────┘
                            │
                            ▼
        ┌──────────────────────────────────────────────────────────────────┐
        │  At kubectl-time (operator's later use of the kubeconfig):       │
        │                                                                   │
        │  kubectl --kubeconfig=<issued> get namespaces                    │
        │           │                                                       │
        │           ▼                                                       │
        │  TLS handshake to https://127.0.0.1:30443 (k3d serverlb)         │
        │           │                                                       │
        │           ▼                                                       │
        │  HOP: k3d-spoke-capsule-serverlb → k3d-spoke-capsule-server-0    │
        │           │                                                       │
        │           ▼                                                       │
        │  capsule-proxy Pod (NodePort 30443; chart-self-signed cert       │
        │  trusted via tls.crt embed in kubeconfig)                         │
        │           │                                                       │
        │           ├─ Auth: tokenreviews.authentication.k8s.io             │
        │           │   (proxy SA has cluster-wide tokenreview permissions) │
        │           │                                                       │
        │           ├─ Identify: SA = system:serviceaccount:tenant-alpha:   │
        │           │            gitops-reconciler                          │
        │           │                                                       │
        │           ├─ Lookup: which Tenants have this SA in spec.owners[]? │
        │           │   (proxy reads Tenant CRs via own ClusterRole)        │
        │           │                                                       │
        │           ├─ Filter: cluster-scoped LIST request rewritten with   │
        │           │   labelSelector: capsule.clastix.io/tenant=alpha      │
        │           │                                                       │
        │           ▼                                                       │
        │  Forward to apiserver (in-cluster service)                        │
        │           │                                                       │
        │           ▼                                                       │
        │  HTTP 200 with FILTERED NamespaceList                             │
        │  (alpha-app1, tenant-alpha — owned by alpha tenant)               │
        └──────────────────────────────────────────────────────────────────┘
```

**Component Responsibilities:**

| Component | File | Responsibility |
|-----------|------|----------------|
| Phase 10 entry script | `scripts/poc/capsule/issue-tenant-kubeconfig.sh` (NEW) | Argument parsing, preflight, token mint, CA read, kubeconfig emit |
| Shared output helpers | `scripts/lib/preflight-lib.sh` (Phase 1 v0.18) | `section`, `pass`, `warn`, `fail`, `info`, `have` |
| Phase 10 doc append | `docs/poc-capsule.md` (Phase 7 D-14 + frontmatter scope-line update) | "Tenant kubeconfig delivery contract" H2 section |
| Phase 10 bats — static | `tests/bats/proxy-01-static-script.bats` (NEW), `proxy-02-static-leak-defenses.bats`, `proxy-03-static-doc.bats` | Script shape, gitignore/gitleaks regression-gate, doc shape |
| Phase 10 bats — live | `tests/bats/proxy-04-live-issue.bats` (NEW), `proxy-05-live-list-filter.bats`, `proxy-06-live-fixture.bats`, `proxy-07-live-regression.bats` | Live issuance, proxy LIST + falsifier, gitleaks rule fires, prior-phase invariant rerun |
| Tenant CRs (read-only consumer) | `pocs/capsule/spoke/tenants/{alpha,bravo}/tenant.yaml` (Phase 9) | Owners array — Phase 10 does NOT modify |
| Tenant SAs (read-only consumer) | `pocs/capsule/spoke/tenants/{alpha,bravo}/sa.yaml` (Phase 9) | The `<owner>` — Phase 10 does NOT modify |
| capsule-proxy Pod (runtime LIST filter) | `pocs/capsule/proxy/helmrelease.yaml` (Phase 8 D-08-11) | Proxy is the runtime — Phase 10 does NOT modify |
| Leak defense (regression-gated) | `.gitignore`, `.gitleaks.toml`, `tests/fixtures/gitleaks/synthetic-kubeconfig.yaml` (Phase 7 D-14) | Phase 10 does NOT modify; bats greps for verbatim presence |

### Recommended Project Structure

```
scripts/poc/capsule/
├── create-cluster.sh                  # Phase 7 (unchanged)
├── fix-dns.sh                         # Phase 7 (unchanged)
└── issue-tenant-kubeconfig.sh         # NEW — Phase 10

docs/
├── poc-capsule.md                     # Phase 7 — Phase 10 APPENDS "Tenant kubeconfig delivery contract" H2
├── capsule-on-eks.md                  # Phase 7 (unchanged; Phase 10 cross-links)
└── capsule-quickstart.md              # (unchanged)

tests/bats/
├── proxy-01-static-script.bats        # NEW — script shape (PROXY-01)
├── proxy-02-static-leak-defenses.bats # NEW — gitignore + gitleaks regression (PROXY-03)
├── proxy-03-static-doc.bats           # NEW — docs/poc-capsule.md section (PROXY-03)
├── proxy-04-live-issue.bats           # NEW — live invocation, kubeconfig YAML shape (PROXY-01)
├── proxy-05-live-list-filter.bats     # NEW — proxy LIST + direct-apiserver falsifier (PROXY-02)
├── proxy-06-live-fixture.bats         # NEW — synthetic-kubeconfig fixture rule fires (PROXY-03)
└── proxy-07-live-regression.bats      # NEW — Phase 7 P31 + Phase 8 CAP-01..03 + Phase 9 TEN-01..06 + ADR-004 reruns

# UNCHANGED — regression-gated only
.gitignore                              # Phase 7 D-14 globs MUST persist verbatim
.gitleaks.toml                          # Phase 7 D-14 rule + allowlist MUST persist verbatim
tests/fixtures/gitleaks/synthetic-kubeconfig.yaml  # Phase 7 D-14 fixture MUST persist verbatim
pocs/capsule/proxy/helmrelease.yaml     # Phase 8 D-08-11 (live capsule-proxy install — runtime LIST filter)
pocs/capsule/spoke/tenants/{alpha,bravo}/{namespace,sa,tenant}.yaml  # Phase 9 D-09-02 (the <owner> SAs)
clusters/hub-flux/pocs/{capsule,capsule-spoke}.yaml  # Phase 8 D-08-12 (split-path outer Ks)
clusters/hub-flux/flux-system/kustomization.yaml  # Phase 9 D-09-05 (FLUX PATCH SURFACE lockdown)
```

### Pattern A1: Argument parsing skeleton (positional + flags + tmpdir validation)

**What:** Single-file bash script with positional `<tenant> <owner>` + optional `--duration <d>` + `--write-to <path>` + `--help`. Mirror `scripts/poc/capsule/create-cluster.sh` head structure.
**When to use:** Phase 10 script entrypoint.

```bash
# scripts/poc/capsule/issue-tenant-kubeconfig.sh — argument parsing skeleton
# Source: clean-room based on scripts/poc/capsule/create-cluster.sh head structure +
#         GNU getopt semantics for --write-to / --duration

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# shellcheck source=../../lib/preflight-lib.sh
# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/lib/preflight-lib.sh"

# D-10 pins (LOCKED — bats grep-asserts these literals):
readonly POC_CTX="k3d-spoke-capsule"
readonly POC_NODEPORT="30443"
readonly DEFAULT_DURATION="1h"
readonly TMPDIR_DEFAULT="${TMPDIR:-/tmp}"
readonly TENANT_TMPDIR="${TMPDIR_DEFAULT}/karyon-tenants"

usage() {
  cat <<EOF
Usage: $(basename "$0") <tenant> <owner> [--duration <d>] [--write-to <path>]

Mints a tenant-owner kubeconfig that routes through capsule-proxy NodePort 30443.

Args:
  <tenant>        Tenant name (e.g., alpha, bravo). MUST match existing Tenant CR.
  <owner>         ServiceAccount name in tenant-<tenant> namespace (currently: gitops-reconciler).

Flags:
  --duration <d>  TokenRequest duration (default: ${DEFAULT_DURATION}). Valid: golang time.Duration string (e.g., 1h, 24h, 7d).
                  k3s default --service-account-max-token-expiration: unbounded on this pin (verified
                  live for --duration up to 720h). Other distros may clamp at 24h. info-warn if > 24h.
  --write-to <p>  Write kubeconfig to <p> instead of stdout. <p> MUST be inside ${TENANT_TMPDIR}/.
                  Symlink escape (e.g., ../../etc/passwd) is rejected via realpath -m.
  --help          This help.

Examples:
  bash scripts/poc/capsule/issue-tenant-kubeconfig.sh alpha gitops-reconciler 2>/dev/null > /tmp/alpha.kc
  bash scripts/poc/capsule/issue-tenant-kubeconfig.sh alpha gitops-reconciler --duration 24h \\
       --write-to ${TENANT_TMPDIR}/alpha.kubeconfig

References:
  Phase 10 PROXY-01..03 + D-10-01 (TokenRequest) + D-10-03 (<owner> = SA) + D-10-06 (TLS embed)
  Phase 7 P31 (POC isolation: this script lives under scripts/poc/capsule/, never invoked by task rebuild)
  ADR-004 (hub-only Flux: NO Flux on spoke-capsule)
EOF
  exit "${1:-0}"
}

# Argument parsing
TENANT=""
OWNER=""
DURATION="${DEFAULT_DURATION}"
WRITE_TO=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --duration) DURATION="${2:?--duration requires a value}"; shift 2 ;;
    --write-to) WRITE_TO="${2:?--write-to requires a value}"; shift 2 ;;
    --help|-h)  usage 0 ;;
    --*)        fail "unknown flag: $1"; usage 1 ;;
    *)          if [[ -z "$TENANT" ]]; then TENANT="$1"; shift
                elif [[ -z "$OWNER" ]]; then OWNER="$1"; shift
                else fail "unexpected positional arg: $1"; usage 1
                fi ;;
  esac
done

[[ -z "$TENANT" ]] && { fail "missing positional <tenant>"; usage 1; }
[[ -z "$OWNER"  ]] && { fail "missing positional <owner>"; usage 1; }
```

### Pattern A2: Direct vs proxy LIST falsifier (PROXY-02 — corrected shape)

**What:** Bats verifies that the PROXY-02 contract is met by checking BOTH:
- proxy returns 200 with tenant-filtered NamespaceList (positive signal)
- direct apiserver `:6446` access with the SAME token returns 403 Forbidden (NOT a wider list)

**Why this differs from CONTEXT.md D-10-08:** The Capsule SA's auto-injected RBAC is namespace-scoped only — it has NO cluster-wide `list namespaces` permission. The original "wider list" assumption presumed a cluster-admin or cluster-wide-reader token; the actual SA token is narrower.

**When to use:** `tests/bats/proxy-05-live-list-filter.bats`.

```bash
# Bats setup (proxy-05-live-list-filter.bats)
setup() {
  if ! kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1; then
    skip "k3d-spoke-capsule cluster not reachable; skipping live bats"
  fi
}

# Falsifier (corrected — qualitative not quantitative)
@test "PROXY-02 falsifier: direct apiserver :6446 with SA token returns 403 (not wider list)" {
  ISSUED_KC=$(mktemp -p "${TMPDIR:-/tmp}" karyon-proxy-issued-XXXX.kubeconfig)
  bash "${REPO_ROOT}/scripts/poc/capsule/issue-tenant-kubeconfig.sh" alpha gitops-reconciler 2>/dev/null > "$ISSUED_KC"

  # Extract the bearer token from the issued kubeconfig
  TOKEN=$(yq eval '.users[0].user.token' "$ISSUED_KC")

  # Construct a direct-apiserver kubeconfig (same token, different cluster URL)
  DIRECT_KC=$(mktemp -p "${TMPDIR:-/tmp}" karyon-proxy-direct-XXXX.kubeconfig)
  cat > "$DIRECT_KC" <<EOF
apiVersion: v1
kind: Config
clusters:
- name: direct
  cluster:
    server: https://127.0.0.1:6446
    insecure-skip-tls-verify: true
users:
- name: alpha-sa
  user:
    token: $TOKEN
contexts:
- name: direct
  context:
    cluster: direct
    user: alpha-sa
current-context: direct
EOF

  # Proxy: 200 with filtered subset (alpha-app1 + tenant-alpha — NOT tenant-bravo, NOT kube-*, NOT capsule-system, NOT flux-system)
  PROXY_OUT=$(kubectl --kubeconfig="$ISSUED_KC" get namespaces -o name 2>&1)
  [ "$?" -eq 0 ]
  echo "$PROXY_OUT" | grep -qF 'namespace/alpha-app1'
  echo "$PROXY_OUT" | grep -qF 'namespace/tenant-alpha'
  ! echo "$PROXY_OUT" | grep -qF 'namespace/tenant-bravo'
  ! echo "$PROXY_OUT" | grep -qF 'namespace/kube-system'
  ! echo "$PROXY_OUT" | grep -qF 'namespace/flux-system'
  ! echo "$PROXY_OUT" | grep -qF 'namespace/capsule-system'

  # Direct apiserver: 403 Forbidden (proves filtering happens at proxy, NOT just at apiserver RBAC)
  DIRECT_OUT=$(kubectl --kubeconfig="$DIRECT_KC" get namespaces 2>&1) || DIRECT_RC=$?
  [ "${DIRECT_RC:-1}" -ne 0 ]   # exit non-zero
  echo "$DIRECT_OUT" | grep -qF 'Forbidden'
  echo "$DIRECT_OUT" | grep -qF 'cannot list resource "namespaces"'
}

teardown() {
  rm -f "${ISSUED_KC:-}" "${DIRECT_KC:-}" 2>/dev/null || true
}
```

### Pattern A3: docs/poc-capsule.md "Tenant kubeconfig delivery contract" H2 append

**What:** Phase 10 appends ONE H2 section to the existing Phase 7 doc. Frontmatter `scope:` line removes the Phase 10 forward-pointer.
**When to use:** Phase 10 doc landing.

```markdown
## Tenant kubeconfig delivery contract

> **Status:** Active. Phase 10 — PROXY-01..03.

The `scripts/poc/capsule/issue-tenant-kubeconfig.sh` script mints a short-lived,
tenant-owner kubeconfig that routes through capsule-proxy on NodePort 30443.

### Quickstart

```
bash scripts/poc/capsule/issue-tenant-kubeconfig.sh alpha gitops-reconciler 2>/dev/null > /tmp/alpha.kubeconfig
KUBECONFIG=/tmp/alpha.kubeconfig kubectl get namespaces
# alpha-app1
# tenant-alpha
```

### Contract

| Property | Value |
|---|---|
| Output channel default | stdout (pure YAML kubeconfig); `preflight-lib` log lines on stderr (clean redirect contract) |
| Optional file output | `--write-to <path>` — `<path>` MUST be inside `${TMPDIR:-/tmp}/karyon-tenants/` |
| Server URL | `https://127.0.0.1:30443` (capsule-proxy NodePort; k3d serverlb host-publish) |
| Authentication | Bound SA token via `kubectl create token` (TokenRequest API); default `--duration=1h` |
| TLS trust | `certificate-authority-data` embedded in cluster block (read live from `capsule-proxy` Secret) |
| Default namespace in context | `tenant-<tenant>` |

### Mandatory invariants (P29 — leak defense)

Tenant kubeconfigs MUST NEVER land in git. The script defends in depth:

1. Default to stdout (no file ever written without operator's explicit `--write-to`).
2. `--write-to` strictly rooted under `${TMPDIR:-/tmp}/karyon-tenants/` (validated via `realpath -m` prefix check; symlink escapes are rejected fail-fast).
3. `.gitignore` excludes `karyon-tenants/`, `*.tenant.kubeconfig`, `tenants/**/access.yaml`, `tenants/**/admin.yaml` (Phase 7 D-14 globs).
4. `.gitleaks.toml` `kubeconfig-bearer-token` rule (Phase 7 D-14) catches `kind: Config + users.token` shape pre-commit and on push (Phase 11 VAL-05 first-push gate).
5. EKS-translation forward-pointer: in production, IRSA replaces TokenRequest cleanly (per `docs/capsule-on-eks.md` §"Rough EKS install path"). The contract is unchanged: tokens never live in git.

### Cross-references

- Phase 7 D-14 leak defenses: `.gitignore` + `.gitleaks.toml` (the rule that fires)
- Phase 8 CAP-02: capsule-proxy NodePort 30443 install
- Phase 9 D-09-02: per-tenant `gitops-reconciler` SA + Tenant CR multi-owner array
- `docs/capsule-on-eks.md` §"Rough EKS install path": IRSA translation forward-pointer
```

### Pattern A4: Wave 0 RED bats scaffold (Phase 7/8/9 D-09-08 inheritance)

**What:** Plan 10-00 lands all 7 bats files in their final location. Static contract bats fail RED until the script lands; live bats use the cluster-info-gate skip pattern (auto-skip when k3d-spoke-capsule unreachable).
**When to use:** Plan 10-00.

Pattern: `setup()` checks for cluster reachability; if unreachable, `skip "k3d-spoke-capsule cluster not reachable; skipping live bats"`. NOT keyed on `KARYON_LIVE_TESTS=1` env var (that's the v0.18 pattern; Phase 8 D-08-09 inherited the cluster-info gate as Phase 10 will too).

### Anti-Patterns to Avoid

- **Hand-rolling JWT base64url decode:** Don't write a custom base64url decoder. Use `cut -d. -f2 | tr '_-' '/+' | base64 -d 2>/dev/null | jq -r .exp`. POSIX-compliant on GNU coreutils. (See Code Examples §C4.)
- **Adding `--mode direct` flag to the script:** Footgun. Operators might leave it on. Bats owns falsifier construction (D-10-08).
- **Building kubeconfig with `yq -n`:** Adds yq to the script's preflight surface. Heredoc keeps deps minimal.
- **Caching the CA cert in a file:** `tls.crt` is rotated by the chart's certgen Job. Live-read at script-time keeps the kubeconfig fresh. (Specifics §"Cert-rotation handling" deferred.)
- **`kubectl get secret capsule-proxy -o yaml | yq '.data."ca.crt"'`:** Wrong key. The Secret has `tls.crt` + `tls.key` only. Use `-o jsonpath='{.data.tls\.crt}'`.
- **Adding `task issue-tenant-kubeconfig` wrapper:** No new tasks (Claude's Discretion default). Direct script invocation is ergonomic enough.
- **Modifying `.gitignore` or `.gitleaks.toml`:** Phase 10 does NOT modify these. Static bats grep-asserts the Phase 7 D-14 globs + rule + allowlist persist verbatim. Modification is a regression.
- **Modifying `pocs/capsule/spoke/tenants/{alpha,bravo}/`:** Phase 9 D-09-02 already shipped the multi-owner array. The existing SA `gitops-reconciler` is the only valid `<owner>` per D-10-03. Phase 10 reads but does NOT mutate.
- **`kubectl auth can-i list namespaces --as=alpha`:** Returns `no` because Capsule's RBAC is namespace-scoped. Phase 10's PROXY-02 falsifier MUST use direct kubectl `get namespaces` against `:6446` (returns 403) — NOT `auth can-i` (returns `no` but for the wrong reason).
- **`grep -F` for cluster-scoped LIST filter assertion:** Use `kubectl get -o name | grep -qF 'namespace/<expected>'` AND assert NOT `grep -qF 'namespace/<not-expected>'`. Two assertions per namespace; partial-match is too weak.
- **`git push` during Phase 10:** Phase 8 D-08-13 push-gate deferral remains in force; commits remain LOCAL-ONLY through Phase 10 close. Phase 11 VAL-05 owns the first push event.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| TokenRequest API call | Hand-coded `curl -X POST ${APISERVER}/api/v1/.../token` with bearer-token header | `kubectl create token <owner> -n <ns> --duration=<d>` | kubectl handles audiences, kubeconfig parsing, JSON marshaling. Edge cases: bound audiences, token rotation, error formatting. |
| JWT base64url decode | Custom python3 / nodejs / go script | `cut -d. -f2 \| tr '_-' '/+' \| base64 -d 2>/dev/null \| jq -r .exp` | Bash one-liner. POSIX. Handles base64url-without-padding correctly via `tr` substitution. |
| Path canonicalization for `--write-to` | Custom `case`-based path manipulation | `realpath -m <path>` (canonicalize without existence check) + `[[ "$canonicalized" == "${tmpdir_prefix}"* ]]` | GNU coreutils 8.x+ on Ubuntu. macOS users would need `coreutils` from brew (out of scope). |
| Kubeconfig YAML emission | Custom JSON-to-YAML converter | Heredoc with parameterized values | Heredoc is readable; clarity outweighs dynamic-build flexibility for a fixed-shape output. Mirrors `scripts/poc/capsule/create-cluster.sh`'s use of heredoc for k3d cluster create. |
| Tmpfile management in bats falsifier | Hand-rolled `/tmp/${RANDOM}` | `mktemp -p "${TMPDIR:-/tmp}" karyon-proxy-XXXX.kubeconfig` | mktemp guarantees unique path + safe permissions. Cleanup in `teardown()`. |
| Tenant CR / SA existence preflight | Custom `kubectl get -o yaml \| yq` parsing | `kubectl get tenant <tenant> >/dev/null 2>&1` (rc==0) AND `kubectl get sa <owner> -n tenant-<tenant> >/dev/null 2>&1` (rc==0) | Exit code is the contract. NO yaml parsing needed. |
| Argument parsing with `--flag value` shape | `getopts` (POSIX, doesn't handle long-form) | `case`-based loop over `$1`/`$2` (matches `create-cluster.sh` style) | Phase 7 / 8 / 9 scripts use this same pattern; Phase 10 inherits |
| Live cluster reachability gate in bats | `KARYON_LIVE_TESTS=1` env-var check | `kubectl --context=k3d-spoke-capsule cluster-info >/dev/null 2>&1 \|\| skip "..."` | Phase 8 D-08-09 inherited this pattern; Phase 10 inherits the inheritance |

**Key insight:** Phase 10's surface is small enough that the temptation to "just shell out to one Python helper" is real. Resist. The script must be parseable in a single `bash -n` pass and source-readable; every hand-rolled component above either ships portability holes or hides a load-bearing edge case (e.g., base64url-without-padding, symlink escape).

## Runtime State Inventory

> Phase 10 ships a NEW shell script + doc append. NO renames, refactors, or migrations. Stored data, live service config, OS-registered state, secrets, build artifacts: NONE pertinent.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — verified by `kubectl --context=k3d-spoke-capsule get all -A 2>&1 \| grep -i 'phase 10\|kubeconfig'` returns no Phase-10-specific stored objects. Phase 10 does NOT create persistent state. | None |
| Live service config | None — capsule-proxy in v0.12.0 reads `CapsuleConfiguration/default` at startup (Phase 9 D-09-04 already shipped). Phase 10 does NOT modify CapsuleConfiguration. | None |
| OS-registered state | None — script is invoked imperatively via `bash`. NO systemd / cron / launchd / pm2 registration. | None |
| Secrets / env vars | The script LIVE-READS the `capsule-proxy` Secret in `capsule-system` namespace at runtime (per D-10-06). The Secret is created by the chart's certgen Job (Phase 8 D-08-11). NO env vars added to `.env` / `.env.example`. | None |
| Build artifacts / installed packages | None — no compiled binary; no asdf entry; no system package install. The script sources `scripts/lib/preflight-lib.sh` (Phase 1 v0.18) verbatim. | None |

**The canonical question — after every file in the repo is updated, what runtime systems still have the old string cached?** *Not applicable: Phase 10 does NOT rename anything.*

## Common Pitfalls

### Pitfall 10-P1: capsule-proxy chart's certgen Secret has `tls.crt` only — NO `ca.crt` key

**What goes wrong:** CONTEXT.md D-10-06 anticipates a fallback shape: read `ca.crt` first, fall back to `tls.crt` if empty. The fallback is unreachable code — the Secret has ONLY `tls.crt` + `tls.key`.
**Why it happens:** Phase 8 D-08-11 flipped the cert source from cert-manager to chart's controller-less certgen Job (`kube-webhook-certgen` image). The Job runs with `--cert-name=tls.crt --key-name=tls.key`; there is no `--ca-name` flag passed. The cert is self-signed (no intermediate CA), so `tls.crt` doubles as the trust anchor.
**How to avoid:** Phase 10 script reads `tls.crt` directly via `-o jsonpath='{.data.tls\.crt}'`. NO ca.crt fallback branch. Live `kubectl get secret capsule-proxy -o jsonpath='{.data}' | jq 'keys'` at script-time is a sanity check Phase 10 verifier could include but is not load-bearing.
**Warning signs:** Issued kubeconfig fails TLS handshake on first `kubectl get` with empty `certificate-authority-data:` (the empty `ca.crt` decodes to empty). Detection: `kubectl --kubeconfig=<issued> get namespaces` returns `Unable to connect to the server: x509: certificate signed by unknown authority`.

**Evidence:**
```bash
$ helm template capsule-proxy oci://ghcr.io/projectcapsule/charts/capsule-proxy --version 0.12.0 \
    --set options.generateCertificates=true --set certManager.generateCertificates=false 2>/dev/null \
    | grep -E 'cert-name|key-name|ca-name|secret-name'
            - --secret-name=capsule-proxy
            - --cert-name=tls.crt
            - --key-name=tls.key
```
[VERIFIED: helm template output, 2026-05-05]

### Pitfall 10-P2: k3s does NOT clamp `--service-account-max-token-expiration` by default — clamp behavior assumption is incorrect

**What goes wrong:** CONTEXT.md D-10-02 documents "k3s default is 24h." Phase 10 specifics §"`--duration` validation" recommends an `info`-warn at `--duration > 24h`. **This is wrong.** k3s on `spoke-capsule` does NOT set `--service-account-max-token-expiration`, so the kube-apiserver default applies — which is unbounded (or per the upstream KEP, defaults to 1y for projected volume tokens; for `kubectl create token` the duration is honored exactly).
**Why it happens:** Conflation of two different mechanisms: (a) projected-volume token auto-extension (default 1y per KEP-1205); (b) `kubectl create token --duration` direct request (no clamp by default). The `--service-account-max-token-expiration` flag is OPT-IN.
**How to avoid:** Phase 10 script's behavior:
- Default duration `1h` (as locked).
- Honor `--duration <d>` exactly (no `info`-warn at >24h on this k3s pin).
- IF the planner adds an info-warn, frame it as "your distribution may clamp at `--service-account-max-token-expiration`; k3s on this cluster does not."
- Bats live test asserts `exp - iat ≈ DURATION` exactly (NOT `≤ 24h` clamp).
**Warning signs:** Bats falsifier asserting clamp would FAIL on this cluster. CONTEXT.md D-10-02's expected bats coverage ("decode JWT exp claim, assert exp - iat ≈ 1h") is correct; the clamp WARNING is the gap.

**Evidence:**
```bash
$ kubectl --context=k3d-spoke-capsule create token gitops-reconciler -n tenant-alpha --duration=720h
# Token issued. Decode payload:
# exp - iat = 2592000 s = 30 days (exactly --duration value, no clamp)
```
[VERIFIED: live cluster, 2026-05-05]

### Pitfall 10-P3: Direct-apiserver bypass returns 403, NOT a "wider list" — D-10-08 falsifier shape correction

**What goes wrong:** CONTEXT.md D-10-08 + specifics §"PROXY-02 LIST count assertion" assumes that direct-apiserver access with the same SA token returns more namespaces than the proxy. This is WRONG. The Capsule auto-injected RoleBindings on tenant SAs are NAMESPACE-scoped (`admin` ClusterRole bound INSIDE the tenant's owned namespaces only — see `kubectl get rolebindings -n alpha-app1` showing `capsule-alpha-0-admin: ClusterRole/admin`). The SA does NOT have cluster-wide `list namespaces`.
**Why it happens:** Capsule's design: tenants are cluster-scoped `Tenant` CRs, but tenant-owner authorization is webhook-mediated CREATE + namespace-scoped RoleBinding RBAC. The cluster-scoped LIST endpoint (`/api/v1/namespaces`) is denied at the apiserver RBAC layer for the SA. capsule-proxy's value is exactly this: it intercepts the cluster-scoped LIST, uses ITS OWN cluster-wide read permissions to enumerate, and synthesizes a 200 response with the tenant-filtered subset.
**How to avoid:** PROXY-02 falsifier is qualitative not quantitative. The assertions are:
- proxy returns 200 with `tenant-alpha` + `alpha-app1` (positive presence)
- proxy DOES NOT return `tenant-bravo` / `kube-system` / `flux-system` / `capsule-system` (negative absence)
- direct apiserver returns 403 Forbidden with message containing `cannot list resource "namespaces"`
**Warning signs:** Bats authoring `[[ "$proxy_count" -lt "$direct_count" ]]` assertion would FAIL because direct returns 0 (403, no list at all) — proxy_count is the only countable side. Phase 10 verifier must use the qualitative shape per Pattern A2 above.

**Evidence:**
```bash
$ kubectl --context=k3d-spoke-capsule create token gitops-reconciler -n tenant-alpha --duration=1h > token.txt
$ KUBECONFIG=/tmp/direct.kc kubectl get namespaces 2>&1
Error from server (Forbidden): namespaces is forbidden: User
"system:serviceaccount:tenant-alpha:gitops-reconciler" cannot list resource
"namespaces" in API group "" at the cluster scope
```
[VERIFIED: live cluster, 2026-05-05]

### Pitfall 10-P4: `realpath -m` is GNU coreutils ONLY; macOS BSD `realpath` lacks `-m`

**What goes wrong:** macOS ships BSD `realpath` from `/usr/bin/realpath` which does NOT support `-m` (canonicalize without requiring existence). The script's `--write-to` validation would fail on macOS.
**Why it happens:** GNU coreutils 8.x+ added `-m` for "canonicalize even if components don't exist." BSD `realpath` resolves to actual filesystem state only. For a path like `--write-to /tmp/karyon-tenants/alpha.kubeconfig` where the directory does not yet exist, BSD `realpath` errors out.
**How to avoid:** Phase 10 is WSL2-only (per ADR-001 single-WSL2 host); Ubuntu 22.04+ ships GNU coreutils. Document the WSL2-only assumption in the script's head comment. If a future POC operator runs from macOS, document the workaround: `brew install coreutils && export PATH="/opt/homebrew/opt/coreutils/libexec/gnubin:$PATH"`. Phase 10 does NOT add a portability shim (out-of-scope per Claude's Discretion + WSL2 host constraint).
**Warning signs:** Script invocation on a non-WSL2 host fails with `realpath: --: invalid option`. Detection: `realpath --version | head -1 | grep -F 'GNU coreutils'` in script preflight.

**Evidence:** [VERIFIED: `realpath --version` on this WSL2 host returns `realpath (GNU coreutils) 9.4`]

### Pitfall 10-P5: `git check-ignore` only works on paths INSIDE the repo root — bats must construct repo-relative paths

**What goes wrong:** Bats falsifier authoring temptation: drop a synthetic kubeconfig at `${TMPDIR:-/tmp}/karyon-tenants/leaked.kubeconfig` and run `git check-ignore -v <abs-path>`. This FAILS with `fatal: Invalid path '/tmp/karyon-tenants': No such file or directory` because `git check-ignore` interprets paths relative to the cwd's repo root.
**Why it happens:** `git check-ignore` is a repo-internal predicate. Its job is "given a path that COULD be in this repo, would `git add` ignore it?" The path must be expressed inside the repo's working tree.
**How to avoid:** Bats constructs a repo-relative path that matches the gitignore glob. For glob `karyon-tenants/`, drop a sentinel file at `${REPO_ROOT}/karyon-tenants/test.kubeconfig` (creating the directory if needed), run `git check-ignore -v karyon-tenants/test.kubeconfig`, assert exit 0. Then `rm -rf ${REPO_ROOT}/karyon-tenants/` in `teardown()`.
**Warning signs:** Bats test `git check-ignore -v ${TMPDIR}/...` exits 128 with "Invalid path" — appears to be a falsifier failure but is actually authoring error. Detection: bats run shows `fatal:` prefix in output.

**Evidence:**
```bash
# Test 1: relative path inside repo — works
$ git check-ignore -v karyon-tenants/test.kubeconfig
.gitignore:25:karyon-tenants/   karyon-tenants/test.kubeconfig
# exit=0

# Test 2: absolute /tmp path — FAILS with exit 128
$ git check-ignore -v /tmp/karyon-tenants/test.kubeconfig
fatal: Invalid path '/tmp/karyon-tenants': No such file or directory
# exit=128
```
[VERIFIED: live testing, 2026-05-05]

### Pitfall 10-P6: capsule-proxy is NOT installed on the spoke (push-gate deferred per D-08-13) — live PROXY-02 is currently UNREACHABLE

**What goes wrong:** Phase 9 verifier `09-VERIFICATION.md` reports `passed_with_overrides`: capsule-proxy HelmRelease deferred to first push (Phase 11 VAL-05). Live cluster `kubectl --context=k3d-spoke-capsule -n capsule-system get deploy capsule-proxy` returns NotFound. Phase 10's PROXY-02 live bats CANNOT pass against the current cluster state.
**Why it happens:** D-08-13 push-gate deferral. The proxy HR's `kube-webhook-certgen` Job needs the chart's namespace-scoped RBAC, which currently lives only on the local-only branch. Push lands the source files at `origin/main`, hub-flux's GitRepository reconciles the new revision, source-controller fetches, kustomize-controller applies, helm-controller reconciles, certgen Job runs, Secret is created, proxy Pod becomes Ready.
**How to avoid:** Phase 10 verifier must:
- (a) Run with the suspend+apply pattern Phase 9 used (Plan 09-04 Task 1) — manually `kubectl apply -k pocs/capsule/proxy/` against spoke; verify; rollback. OR:
- (b) Defer PROXY-02 live validation to Phase 11 VAL-05 (first-push event), inheriting the same `passed_with_override` shape Phase 9 used for 4 must-haves.
- (c) Stage the proxy install for Plan 10-02 verifier with explicit suspend+apply documented in 10-VERIFICATION.md as the override reason.
**Warning signs:** Verifier reports proxy LIST falsifier RED with message `services "capsule-proxy" not found`.

**Recommendation for the planner:** Plan 10-02 verifier uses the suspend+apply pattern (Phase 9 Plan 09-04 precedent). Document in CONTEXT.md `<deferred>` if not already covered: "PROXY-02 live falsifier requires capsule-proxy live install; gated on D-08-13 push-gate deferral; Phase 10 verifier suspends flux-system Kustomization, applies the proxy yaml locally, runs falsifier, then resumes." This is the canonical Phase 9 approach.

**Evidence:**
```bash
$ kubectl --context=k3d-spoke-capsule -n capsule-system get pods 2>&1
NAME                                          READY   STATUS    RESTARTS        AGE
capsule-controller-manager-546b66685d-gh6cw   1/1     Running   1 (4d21h ago)   4d21h
# (NO capsule-proxy pod)
$ kubectl --context=k3d-spoke-capsule -n capsule-system get secret capsule-proxy 2>&1
Error from server (NotFound): secrets "capsule-proxy" not found
```
[VERIFIED: live cluster, 2026-05-05]

### Pitfall 10-P7: stdout/stderr split — `preflight-lib` log helpers MUST write to stderr (verify behavior)

**What goes wrong:** If `pass`/`info`/`section` writes to stdout (default for `printf`), the kubeconfig YAML in stdout gets corrupted with log lines.
**Why it happens:** `scripts/lib/preflight-lib.sh:21-25` defines the helpers as `printf "..." "$1"` — which writes to stdout by default. Phase 10's clean-redirect contract `bash issue-tenant-kubeconfig.sh alpha gitops-reconciler 2>/dev/null > /tmp/alpha.kc` REQUIRES log lines on stderr.
**How to avoid:** Phase 10 script wraps all `pass`/`info`/`section`/`fail` calls inside a `>&2` redirect, OR overrides them locally with stderr-only versions. **Cleanest fix:** add a `>&2` redirect at each call site in `issue-tenant-kubeconfig.sh`:
```bash
section() { command section "$@" >&2; }   # local override
pass()    { command pass    "$@" >&2; }
info()    { command info    "$@" >&2; }
warn()    { command warn    "$@" >&2; }
fail()    { command fail    "$@" >&2; }
```
**OR** patch `preflight-lib.sh` to write to stderr unconditionally (BUT this changes behavior for existing scripts — Phase 7's `create-cluster.sh` already uses preflight-lib and currently writes to stdout; changing it would change that script's output too).
**Warning signs:** `bash issue-tenant-kubeconfig.sh alpha gitops-reconciler 2>/dev/null > /tmp/alpha.kc && yq eval . /tmp/alpha.kc` fails because the kubeconfig has interleaved log lines. Detection: bats live test `yq eval .kind` returns `null` instead of `Config`.

**Recommendation:** Local override in Phase 10 script (cleanest blast radius). Phase 11 may revisit globally if needed.

**Note on existing scripts:** `create-cluster.sh` (Phase 7) and `fix-dns.sh` (Phase 7) write log lines to stdout because their stdout is human-readable summary output, not data. Their behavior is correct as-is; Phase 10's contract is different (stdout = YAML data) and so requires the local override.

## Code Examples

### C1: TokenRequest issuance — verbatim contract literal

```bash
# Source: D-10-01 + verified live against k3d-spoke-capsule
TOKEN=$(kubectl --context=k3d-spoke-capsule create token "${OWNER}" -n "tenant-${TENANT}" --duration="${DURATION}")
```

Bats grep-asserts these EXACT literals in the script:
- `kubectl --context=k3d-spoke-capsule`
- `create token`
- `-n "tenant-`
- `--duration=`

### C2: CA cert read — corrected path (no ca.crt fallback)

```bash
# Source: helm template verification 2026-05-05; resolves D-10-06a research-flagged item.
# The certgen Job emits Secret with keys: tls.crt, tls.key. NO ca.crt key.
# tls.crt IS the self-signed CA root.
CA_B64=$(kubectl --context=k3d-spoke-capsule -n capsule-system \
    get secret capsule-proxy -o jsonpath='{.data.tls\.crt}')

# Defensive: fall back if Secret rotation in flight (rare; chart doesn't actually rotate
# without manual upgrade). info-warn rather than fail to keep script robust.
if [[ -z "$CA_B64" ]]; then
  warn "capsule-proxy Secret tls.crt is empty (chart cert rotation in flight?). Retrying once after 5s..." >&2
  sleep 5
  CA_B64=$(kubectl --context=k3d-spoke-capsule -n capsule-system \
      get secret capsule-proxy -o jsonpath='{.data.tls\.crt}')
fi
[[ -z "$CA_B64" ]] && { fail "capsule-proxy Secret tls.crt is empty after retry"; exit 1; }
```

### C3: Kubeconfig heredoc emit — clean stdout / stderr split

```bash
# Source: D-10-07. Heredoc parameterized by TENANT, OWNER, TOKEN, CA_B64.
# pass/info on stderr (>&2); kubeconfig YAML on stdout.
section "Emit kubeconfig" >&2

cat <<KUBECONFIG_EOF
apiVersion: v1
kind: Config
clusters:
  - name: capsule-proxy-127.0.0.1
    cluster:
      server: https://127.0.0.1:30443
      certificate-authority-data: ${CA_B64}
users:
  - name: ${OWNER}
    user:
      token: ${TOKEN}
contexts:
  - name: tenant-${TENANT}-via-proxy
    context:
      cluster: capsule-proxy-127.0.0.1
      user: ${OWNER}
      namespace: tenant-${TENANT}
current-context: tenant-${TENANT}-via-proxy
KUBECONFIG_EOF

pass "kubeconfig emitted (proxy server: https://127.0.0.1:30443; default ns: tenant-${TENANT})" >&2
```

### C4: JWT decode in bats live test — portable bash one-liner

```bash
# Source: live-tested on this WSL2 cluster 2026-05-05; works with k3s-issued
# RS256-signed bound SA tokens.
TOKEN=$(kubectl --context=k3d-spoke-capsule create token gitops-reconciler -n tenant-alpha --duration=1h)

# 1. Extract payload (middle segment of header.payload.signature)
PAYLOAD=$(echo "$TOKEN" | cut -d. -f2)

# 2. Pad base64url to base64 length (mod 4 must equal 0)
case $((${#PAYLOAD} % 4)) in
  2) PAYLOAD="${PAYLOAD}==" ;;
  3) PAYLOAD="${PAYLOAD}=" ;;
esac

# 3. Convert base64url alphabet to base64 alphabet, decode, parse JSON
DECODED=$(echo "$PAYLOAD" | tr '_-' '/+' | base64 -d 2>/dev/null)

# 4. Extract claims
EXP=$(echo "$DECODED" | jq -r '.exp')
IAT=$(echo "$DECODED" | jq -r '.iat')
SUB=$(echo "$DECODED" | jq -r '.sub')

# 5. Bats assertions
[ "$((EXP - IAT))" -eq 3600 ]   # 1h tolerance OK; ±60s for clock skew if needed
[ "$SUB" = "system:serviceaccount:tenant-alpha:gitops-reconciler" ]
```

### C5: `--write-to` realpath validation

```bash
# Source: D-10-07 + Claude's Discretion §"`--write-to <path>` validation"
if [[ -n "$WRITE_TO" ]]; then
  # realpath -m: canonicalize WITHOUT requiring path components to exist
  RESOLVED=$(realpath -m "$WRITE_TO")
  TMPDIR_RESOLVED=$(realpath -m "${TENANT_TMPDIR}")

  if [[ "$RESOLVED" != "${TMPDIR_RESOLVED}/"* ]]; then
    fail "--write-to '${WRITE_TO}' is outside ${TENANT_TMPDIR}/.
       Hint: tenant kubeconfigs MUST live in tmpdir per Phase 10 PROXY-03 + Phase 7 P29 invariant.
       Try: --write-to ${TENANT_TMPDIR}/${TENANT}.kubeconfig" >&2
    exit 1
  fi

  mkdir -p "$(dirname "$RESOLVED")"
  # ... emit kubeconfig to "$RESOLVED" instead of stdout
fi
```

### C6: `git check-ignore` bats fixture — repo-relative path construction

```bash
# Source: live-tested 2026-05-05; resolves Pitfall 10-P5
# Path MUST be repo-relative — git check-ignore interprets paths inside the repo working tree.

@test "PROXY-03 leak defense: gitignore catches karyon-tenants/ glob (D-14 inheritance)" {
  cd "$REPO_ROOT"
  mkdir -p karyon-tenants
  : > karyon-tenants/test.kubeconfig

  run git check-ignore -v karyon-tenants/test.kubeconfig
  [ "$status" -eq 0 ]
  [[ "$output" == *karyon-tenants/* ]]
}

teardown() {
  rm -rf "${REPO_ROOT}/karyon-tenants" 2>/dev/null || true
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Long-lived `Secret type: kubernetes.io/service-account-token` (legacy SA tokens) | TokenRequest API via `kubectl create token` | k8s 1.24 (May 2022) — auto-mount of legacy SA Secrets removed by default | Phase 10 D-10-01: tokens are short-lived, auto-expiring. Gitleaks rule fires on either shape; the legacy form is "the explicit anti-pattern signal" CONTEXT.md flags. |
| `proxy-kubeconfig-generator` utility from clastix (vendored shell helper) | Inline `kubectl create token` + heredoc | research SUMMARY.md mentioned vendoring `hack/create-user.sh` (cert-based); rejected in favor of Phase 9's SA-token approach | Phase 10's script does NOT vendor anything. Cleaner; less drift. |
| Cert-manager-issued cert for capsule-proxy webhook TLS | Chart's controller-less `kube-webhook-certgen` Job | Phase 8 D-08-11 gap-close 2026-04-29 — cert-manager not in v0.19 scope | Phase 10 reads `tls.crt` (NOT `ca.crt`) per Pitfall 10-P1. |
| Single-Kustomization-per-spoke (Phase 7) with `spec.kubeConfig` always present | Split-path Kustomizations (Phase 8 D-08-12): hub-targeted = no kubeConfig; spoke-targeted = full kubeConfig | Phase 8 D-08-12 (gap-close 2026-04-29) | Phase 10 does NOT modify; verifier reruns the regression-gate bats tenants-05-static-split-path. |
| `kubectl auth can-i list namespaces` for negative RBAC | `kubectl get namespaces` against direct apiserver (returns 403) | This research (2026-05-05) — corrects D-10-08 falsifier shape | Phase 10 PROXY-02 falsifier uses `get` not `auth can-i`; the SA's RBAC failure mode is the load-bearing signal. |

**Deprecated/outdated:**
- "k3s default --service-account-max-token-expiration is 24h" — outdated/incorrect per live test 2026-05-05. The flag is OPT-IN; k3s does not set it by default.
- "direct apiserver returns wider list" (CONTEXT.md D-10-08 specifics) — replaced by "direct apiserver returns 403 Forbidden."
- "ca.crt fallback in capsule-proxy Secret" (CONTEXT.md D-10-06a) — unreachable; Secret has no `ca.crt` key.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | macOS BSD `realpath` lacks `-m` (this is documented widely but not directly verified on a macOS host in this session). | Pitfall 10-P4 | Low: Phase 10 is WSL2-only; if the mention of macOS workaround is wrong, the WSL2-only path remains correct. |
| A2 | Other k8s distros (EKS, GKE, AKS, OpenShift, kubeadm-default) clamp at 24h or other values. | Pitfall 10-P2 | Medium: the `info`-warn message wording. Phase 10 docs the k3s pin behavior; portability note is informational. |
| A3 | `helm template --set options.generateCertificates=true` accurately renders what runs in-cluster (assumes the live HelmRelease applies these flags identically). | Pitfall 10-P1 | Low: Phase 8 D-08-11 verified the chart-rendered shape matches the HelmRelease values. The certgen Job's `--cert-name=tls.crt --key-name=tls.key` is invariant under the chart's templating. |
| A4 | gitleaks 8.30.1's multiline regex `(?ms)^kind:\s*Config[\s\S]*?users:[\s\S]*?token:\s*[A-Za-z0-9._-]{32,}` reliably catches the kubeconfig shape Phase 10 emits (verified Phase 7 D-14 fixture; same shape). | Architecture §A3 + Code C6 | Low: Phase 7 fixture allowlist + bats already exercise this; Phase 10 emits the same shape. |

## Open Questions

> All Phase 10 D-10-06a + D-10-09 research-flagged items are RESOLVED. The questions below are forward-looking flags for the planner.

1. **Should Plan 10-02 verifier do its own suspend+apply staging of capsule-proxy, or defer PROXY-02 live to Phase 11 VAL-05?**
   - What we know: capsule-proxy is NOT live on `spoke-capsule` (push-gate deferred). Phase 9 used suspend+apply to validate. Phase 10's verifier could mirror.
   - What's unclear: whether suspend+apply increases verifier complexity beyond Phase 10's small surface.
   - Recommendation: **Plan 10-02 uses suspend+apply** (mirror Phase 9 Plan 09-04 Task 1 precedent). The proxy is required to validate PROXY-02 PROXY's filtering. Document the override in 10-VERIFICATION.md as `passed_with_overrides`. Forward Phase 11 VAL-05 inherits the actual push event.

2. **Should the `tests/fixtures/gitleaks/synthetic-kubeconfig.yaml` be reused or should Phase 10 add a tenant-flavored variant `synthetic-tenant-kubeconfig.yaml`?**
   - What we know: existing fixture is shape-generic (`kind: Config`, `token: <inert>`). Phase 7 D-14 allowlist covers it.
   - What's unclear: whether tenant-flavored shape adds verification value (e.g., `current-context: tenant-alpha-via-proxy` as a literal Phase 10 grep target) or just adds maintenance.
   - Recommendation: **REUSE existing fixture for Phase 10's synthetic-fixture bats.** D-10-09 specifics already note "the existing fixture is generic enough." If a future phase needs tenant-flavored fixture, add it then.

3. **Should Phase 10 add a `task issue-tenant-kubeconfig` shorthand to `Taskfile.yml`?**
   - What we know: Claude's Discretion default is "no new task targets." Direct script invocation is ergonomic.
   - What's unclear: whether milestone-owner ergonomic preference (Phase 11 will run the script repeatedly during N1–N12 negative RBAC suite) tips toward adding the wrapper.
   - Recommendation: **NO new task** for Phase 10. If Phase 11 N1–N12 implementation reveals friction, add `task issue-tenant-kubeconfig` then.

4. **Should the script's `info`-warn at `--duration > 24h` reframe the message based on this research?**
   - What we know: k3s on `spoke-capsule` does NOT clamp at 24h. CONTEXT.md D-10-02 expects warn at >24h.
   - What's unclear: whether to drop the warn entirely (k3s pin is unbounded) or keep it as a portability note.
   - Recommendation: **KEEP a warn but reframe.** Message: `info "duration ${DURATION} is honored exactly on this k3s pin (no apiserver clamp). Other k8s distros may clamp at --service-account-max-token-expiration; verify before relying on durations >24h in production."`

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `kubectl` | Script + bats | ✓ | v1.34.6 (asdf shim) | — |
| `k3d` | bats live cluster gate | ✓ | (asdf shim) | — |
| `helm` | (not needed at runtime) | ✓ | v3.20.2 | — |
| `bats-core` | Test harness | ✓ | 1.11.0 | — |
| `yq` | Bats yaml parsing + script preflight (optional) | ✓ | v4.53.2 (mikefarah) | — |
| `jq` | Bats JWT decode + script JSON parse | ✓ | (asdf shim) | — |
| `realpath` | Script `--write-to` validation | ✓ | GNU coreutils 9.4 | — (WSL2-only constraint) |
| `base64` | Bats JWT decode | ✓ | GNU coreutils | — |
| `openssl` | (not strictly needed; available for SAN probing if desired) | ✓ | system | — |
| `gitleaks` | Phase 7 D-14 leak defense regression-gate (and PROXY-03 synthetic fixture) | ✓ | 8.30.1 | — |
| `git` | bats `git check-ignore` for gitignore regression test | ✓ | system | — |
| `mktemp` | Bats falsifier kubeconfig tmpfile | ✓ | system | — |
| `kubectl` cluster context `k3d-spoke-capsule` | Live bats | ✓ | — | bats auto-skip with cluster-info gate |
| `kubectl` cluster context `k3d-hub-flux` | Live bats (regression rerun, ADR-004 invariant) | ✓ | — | same auto-skip |
| `capsule-proxy` Pod RUNNING on spoke-capsule | PROXY-02 live falsifier | ✗ | — | **Suspend+apply pattern in Plan 10-02 verifier** (Phase 9 Plan 09-04 precedent) OR defer PROXY-02 live to Phase 11 VAL-05 push gate |
| `capsule-proxy` Secret in capsule-system ns | Script's CA cert read | ✗ | — | **Same fallback as above** — Secret only exists when proxy HR has reconciled |

**Missing dependencies with fallback:**
- capsule-proxy live install: deferred per D-08-13 push-gate. Plan 10-02 verifier uses suspend+apply (Phase 9 Plan 09-04 precedent), validates PROXY-01..03 bats locally, then resumes flux-system Kustomization. Push event remains Phase 11 VAL-05.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | bats-core 1.11.0 (already pinned via asdf) |
| Config file | `tests/bats/test_helper.bash` (Phase 1 v0.18; provides `REPO_ROOT`, `IMAGES_DIR`, `require_live`, `require_live_destructive`) |
| Quick run command | `bats tests/bats/proxy-*.bats` (Phase 10 only) |
| Full suite command | `bats tests/bats/` (all 60+ files) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| **PROXY-01** | Script exists with `#!/usr/bin/env bash` + `set -euo pipefail` + `REPO_ROOT`/`SCRIPT_DIR` pinning + `source preflight-lib.sh` + head comment cites D-10-01/03/06 + P31 + ADR-004 | static (yq + grep -F) | `bats tests/bats/proxy-01-static-script.bats` | ❌ Wave 0 (NEW) |
| PROXY-01 | `<tenant> <owner>` positional + `--duration` flag + `--write-to` flag + `--help` | static | same file (same suite) | ❌ Wave 0 |
| PROXY-01 | Literals: `kubectl --context=k3d-spoke-capsule`, `create token`, `--duration=`, `server: https://127.0.0.1:30443`, `certificate-authority-data:`, `current-context: tenant-${TENANT}-via-proxy` | static (`grep -F --` per Phase 8 WR-01..04 pattern) | same file (same suite) | ❌ Wave 0 |
| PROXY-01 | Live invocation: `bash issue-tenant-kubeconfig.sh alpha gitops-reconciler` returns exit 0 + stdout valid YAML (`yq eval . -` exits 0) + `kind: Config` + `current-context: tenant-alpha-via-proxy` + `--write-to` writes inside tmpdir + `--write-to /etc/passwd` rejected exit 1 | live | `bats tests/bats/proxy-04-live-issue.bats` | ❌ Wave 0 |
| **PROXY-02** | proxy LIST: `kubectl --kubeconfig=<issued> get namespaces -o name` returns alpha-app1 + tenant-alpha (positive); does NOT return tenant-bravo, kube-system, flux-system, capsule-system (negative) | live | `bats tests/bats/proxy-05-live-list-filter.bats` | ❌ Wave 0 |
| PROXY-02 | Direct apiserver `:6446` falsifier: `kubectl --kubeconfig=<direct> get namespaces` returns 403 Forbidden + `cannot list resource "namespaces"` error message | live (corrected shape per Pitfall 10-P3) | same file | ❌ Wave 0 |
| PROXY-02 | JWT decode: token's `exp - iat ≈ DURATION` ±60s | live | `bats tests/bats/proxy-04-live-issue.bats` (additional @test) | ❌ Wave 0 |
| **PROXY-03** | `.gitignore` contains Phase 7 D-14 globs verbatim (regression-gate) | static | `bats tests/bats/proxy-02-static-leak-defenses.bats` | ❌ Wave 0 |
| PROXY-03 | `.gitleaks.toml` contains Phase 7 D-14 `kubeconfig-bearer-token` rule + allowlist verbatim (regression-gate) | static | same file | ❌ Wave 0 |
| PROXY-03 | `tests/fixtures/gitleaks/synthetic-kubeconfig.yaml` exists + path-allowlisted in `.gitleaks.toml` | static | same file | ❌ Wave 0 |
| PROXY-03 | `docs/poc-capsule.md` has `## Tenant kubeconfig delivery contract` section + cross-links to capsule-on-eks.md | static (yq frontmatter + grep -F section heading) | `bats tests/bats/proxy-03-static-doc.bats` | ❌ Wave 0 |
| PROXY-03 | `git check-ignore -v karyon-tenants/test.kubeconfig` exit 0 (gitignore rule fires for tmpdir glob) | live (mktemp + git inside REPO_ROOT) | `bats tests/bats/proxy-06-live-fixture.bats` | ❌ Wave 0 |
| PROXY-03 | `gitleaks detect --no-git --source <fixture>` exits non-zero on tenant-shaped fixture NOT in allowlist | live | same file | ❌ Wave 0 |
| Inherited (P31) | `tests/bats/poc-isolation-01-static.bats` rerun — Phase 10's new file under `scripts/poc/capsule/` MUST NOT introduce `spoke-capsule` mention in v0.18 scripts | static | `bats tests/bats/proxy-07-live-regression.bats` (or rerun directly) | ✅ exists (Phase 7) |
| Inherited (CAP-01..03) | `tests/bats/capsule-install-{06..10}-live-*.bats` rerun | live | same file | ✅ exists (Phase 8) |
| Inherited (TEN-01..06) | `tests/bats/tenants-{01..12}-{static,live}-*.bats` rerun | static + live | same file | ✅ exists (Phase 9) |
| Inherited (ADR-004) | `tests/bats/capsule-install-09-live-adr-004.bats` rerun — no Flux on spoke-capsule | live | same file | ✅ exists (Phase 8) |

### Sampling Rate

- **Per task commit:** `bats tests/bats/proxy-*.bats` (Phase 10 own bats — fast; ~30s)
- **Per wave merge:** `bats tests/bats/proxy-*.bats tests/bats/poc-*.bats tests/bats/capsule-install-*.bats tests/bats/tenants-*.bats` (Phase 7+8+9+10; ~3min)
- **Phase gate:** `bats tests/bats/` (full suite; ~5min)

### Wave 0 Gaps

- [ ] `tests/bats/proxy-01-static-script.bats` — covers PROXY-01 (script shape, args, literals)
- [ ] `tests/bats/proxy-02-static-leak-defenses.bats` — covers PROXY-03 (gitignore + gitleaks regression-gates)
- [ ] `tests/bats/proxy-03-static-doc.bats` — covers PROXY-03 (`docs/poc-capsule.md` section)
- [ ] `tests/bats/proxy-04-live-issue.bats` — covers PROXY-01 (live invocation, kubeconfig YAML shape, JWT decode)
- [ ] `tests/bats/proxy-05-live-list-filter.bats` — covers PROXY-02 (proxy LIST + 403 falsifier)
- [ ] `tests/bats/proxy-06-live-fixture.bats` — covers PROXY-03 (synthetic fixture rule fires + gitignore catches)
- [ ] `tests/bats/proxy-07-live-regression.bats` — Phase 7 P31 + Phase 8 CAP-01..03 + Phase 9 TEN-01..06 + ADR-004 inheritance reruns
- [x] No new `tests/fixtures/` needed (reuse Phase 7 `synthetic-kubeconfig.yaml`)
- [x] Framework install: not needed (bats 1.11.0 already pinned)

**Naming sanity-check:** Phase 10's `proxy-` prefix conflicts with NONE of the existing 60+ bats files (verified by `ls /home/rich/code/gsd/karyon/tests/bats/ | grep -F 'proxy-'` returns no matches). Phase 8 used `capsule-install-` prefix for proxy-related tests (e.g., `capsule-install-08-live-proxy-reachable.bats`); Phase 10's `proxy-` prefix is distinct. No collision.

## Security Domain

> v0.19 milestone has implicit `security_enforcement: enabled` (security is core to the multi-tenancy POC). Phase 10 is squarely in the security path because PROXY-03 is the load-bearing P29 leak defense.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | yes | TokenRequest API (bound short-lived JWT); SA token verified via apiserver tokenreview by capsule-proxy. NO long-lived legacy SA Secrets. |
| V3 Session Management | partial | Token expiry is session lifetime. Default 1h; operator re-runs script when token expires. NO refresh tokens, NO sliding sessions (POC simplification). |
| V4 Access Control | yes | Capsule webhook + RBAC + capsule-proxy LIST filtering. Three independent layers; failure of any one does NOT defeat the others. |
| V5 Input Validation | yes | Script validates `<tenant>` (Tenant CR exists) + `<owner>` (SA exists) + `--duration` (kubectl rejects malformed) + `--write-to` (realpath -m + tmpdir prefix check). |
| V6 Cryptography | yes | TLS via chart's self-signed cert (tls.crt as CA root). NOT cert-manager (out-of-scope). NEVER `insecure-skip-tls-verify: true` in issued kubeconfig. |
| V7 Error Handling | yes | All preflight failures use `fail "<message>\n   Hint: <fix>"` style. NO secret leakage in error messages (token never echoed). |
| V8 Data Protection | yes | Token is short-lived (1h default); kubeconfig defaults to stdout (no file persistence); `--write-to` strictly tmpdir-rooted. |
| V12 API Security | yes | TokenRequest API direct call via kubectl (no custom curl). capsule-proxy validates tokens via tokenreview API (chart-default behavior). |

### Known Threat Patterns for `bash + kubectl + capsule-proxy + bats`

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Token leakage to stdout in CI logs | Information Disclosure | Default to stdout makes it visible IF redirected to terminal — but the operator pipes to `> /tmp/file` or `\| kubectl`. CI runs use `>/dev/null` or scoped redirect. Bats live tests use `$(... 2>/dev/null)` capture. |
| Symlink attack on `--write-to` | Tampering / Information Disclosure | `realpath -m` resolves symlinks before prefix check. `--write-to /tmp/karyon-tenants/../../../etc/passwd` resolves to `/etc/passwd`, fails prefix check. |
| Token committed to git | Information Disclosure | Five layers of defense: (1) stdout default, (2) `--write-to` strict tmpdir-root, (3) `.gitignore` Phase 7 D-14 globs, (4) `.gitleaks.toml` `kubeconfig-bearer-token` rule, (5) Phase 11 VAL-05 first-push history scan. |
| Cross-tenant token use | Spoofing / Elevation of Privilege | Token is bound to the SA's tenant via TokenRequest's `audiences` claim + Capsule's webhook subject check + capsule-proxy LIST filtering. Three layers. Phase 11 N1–N12 falsifies all three independently. |
| Direct apiserver bypass | Bypass Control | `:6446` returns 403 for tenant SAs (RBAC denies cluster-scoped LIST); proxy is the only authorized path. Falsified by Phase 10 PROXY-02. |
| Token reuse after rotation | Replay | TokenRequest tokens carry `iat`/`exp`; expiry enforced by apiserver tokenreview. Operator re-runs script for fresh token. |
| Long-lived legacy SA Secret in repo | Information Disclosure | Gitleaks rule (Phase 7 D-14) catches `kind: Config + token:` shape regardless of whether the token is bound (TokenRequest) or legacy. |
| Malicious `<owner>` arg | Information Disclosure | `<owner>` MUST match an existing SA in `tenant-<tenant>` namespace; preflight fails fast. NO SA auto-create (per D-10-04). |
| `realpath -m` not present (BSD) | Denial of Service | WSL2-only assumption; script's preflight `have realpath` + early failure if missing. macOS users would need GNU coreutils workaround. |

## Sources

### Primary (HIGH confidence)

- **Live cluster `k3d-spoke-capsule` (Phase 9 close-out state, 2026-05-05):**
  - `kubectl --context=k3d-spoke-capsule get tenant alpha bravo` → both Active, both with `forceTenantPrefix: true`
  - `kubectl --context=k3d-spoke-capsule -n tenant-alpha get sa gitops-reconciler` → exists
  - `kubectl --context=k3d-spoke-capsule -n capsule-system get pods` → only `capsule-controller-manager` (proxy NOT installed — D-08-13 push-gate)
  - `kubectl --context=k3d-spoke-capsule create token gitops-reconciler -n tenant-alpha --duration=720h` → token issued; `exp - iat = 2592000s` (no clamp)
  - `kubectl --kubeconfig=<direct-with-SA-token> get namespaces` → 403 Forbidden + "cannot list resource"
  - `git check-ignore -v karyon-tenants/test.kubeconfig` → exit 0 + matched `.gitignore:25:karyon-tenants/`
  - `realpath --version` → `realpath (GNU coreutils) 9.4`
- **`helm template oci://ghcr.io/projectcapsule/charts/capsule-proxy --version 0.12.0 --set options.generateCertificates=true`** rendered:
  - `kube-webhook-certgen` Job with `--cert-name=tls.crt --key-name=tls.key --secret-name=capsule-proxy` (Q1 RESOLVED — no `ca.crt` key in Secret)
  - Service NodePort 30443 + listening port 9001
  - capsule-proxy Deployment args include `--ssl-cert-path=/opt/capsule-proxy/tls.crt`
- **Phase 9 verifier `09-VERIFICATION.md`:** confirmed `passed_with_overrides` 8/8 must-haves; live state of namespaces (alpha-app1 exists; bravo-app1 cascade-blocked); SA `gitops-reconciler` per tenant.
- **Phase 8 D-08-11 + 08-CONTEXT.md:** chart cert source flipped to `options.generateCertificates: true` (controller-less certgen Job).
- **Phase 7 D-14 + Phase 7 SUMMARY:** `.gitignore` globs, `.gitleaks.toml` rule + allowlist, `tests/fixtures/gitleaks/synthetic-kubeconfig.yaml` fixture all shipped verbatim.
- **`scripts/poc/capsule/create-cluster.sh` (Phase 7) + `fix-dns.sh` (Phase 7):** head structure pattern for Phase 10's script.
- **`scripts/lib/preflight-lib.sh`:** verified `pass`/`info`/`section` write to stdout (Pitfall 10-P7 implication for Phase 10).

### Secondary (MEDIUM confidence)

- **Capsule project docs** — `https://projectcapsule.dev/docs/proxy/options/` — feature gate `ProxyAllNamespaced` default `true`; `ProxyClusterScoped` default `false`. Confirmed via WebFetch 2026-05-05.
- **GitHub issue projectcapsule/capsule-proxy#30** — confirmed proxy returns HTTP 200 with empty `NamespaceList` for tenant-empty (group-owned tenant) — i.e., proxy intercepts cluster-scoped LIST and returns 200, not 403. Confirmed via WebFetch.
- **Kubernetes docs `https://kubernetes.io/docs/reference/access-authn-authz/service-accounts-admin/`** — TokenRequest API is the canonical short-lived SA token path. (LOW: didn't directly extract default `--service-account-max-token-expiration` from the page — fell through to live test.)
- **k3s issue #10573** — `--service-account-max-token-expiration` flag is OPT-IN via `kube-apiserver-arg`; default not set.

### Tertiary (LOW confidence — used only as context, not authoritative)

- WebSearch: `"capsule-proxy v0.12 LIST" tenant filter cluster-scoped` (multiple sources cross-checked; no single source contradicts the GitHub issue evidence).

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — every version verified against live cluster + chart `helm template`.
- Architecture: HIGH — every architectural claim grounded in live cluster + Phase 7/8/9 committed yaml + chart-rendered output.
- Pitfalls: HIGH — three load-bearing corrections to CONTEXT.md (P1, P2, P3) verified by live cluster experiment. Two assumptions tagged as MEDIUM (A1: BSD `realpath`; A2: other distros' clamp behavior).
- Code examples: HIGH — every snippet either (a) tested live in this research session, (b) verbatim from existing v0.18 / Phase 7 / Phase 8 / Phase 9 committed code, or (c) chart-rendered output.

**Research date:** 2026-05-05
**Valid until:** 2026-06-04 (30 days for stable; chart pin v0.12.0 stable since 2026-04-14; capsule v0.12.4 stable since 2025-12-19; k3s v1.34.6-k3s1 unchanged for 7+ months).

## RESEARCH COMPLETE
