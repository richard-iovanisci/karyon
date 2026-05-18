# Phase 10: Tenant Owner Kubeconfigs + Capsule-Proxy Round-trip - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-05
**Phase:** 10-tenant-owner-kubeconfigs-capsule-proxy-round-trip
**Areas discussed:** Token source, <owner> arg semantics, Tenant inner K kubeConfig swap, TLS trust shape
**Mode:** default (interactive)

---

## Token source

### Q1 — How should `issue-tenant-kubeconfig.sh` produce the bearer token for the kubeconfig?

| Option | Description | Selected |
|--------|-------------|----------|
| TokenRequest API | `kubectl create token <sa> --duration=...` returns short-lived token (default 1h, accepts up to ~48h depending on apiserver). No in-cluster Secret artifact. Aligns with k8s ≥1.24 deprecation of auto-mounted SA Secrets. Operator re-runs the script when token expires — acceptable for POC. Add an optional `--duration <d>` flag (default 1h). | ✓ |
| Long-lived SA token Secret | Create one `kind: Secret type: kubernetes.io/service-account-token` per tenant owner; k8s controller fills `data.token` + `data.ca.crt`. Persists until manually rotated/deleted. Demo-friendly (mint once, reuse all session). Higher leak-risk surface (the gitleaks rule fires on this exact shape); explicit anti-pattern signal under k8s ≥1.24. | |
| Default TokenRequest, opt-in long-lived | Default to short-lived TokenRequest; add a `--persistent` flag that creates and reads a long-lived SA token Secret. Operator picks per call. More code (two paths) but lets the POC demo flow be ergonomic without regressing the default to the riskier shape. | |

**User's choice:** TokenRequest API
**Notes:** Recommended option chosen. Maps to D-10-01.

### Q2 — Default token duration and `--duration` flag handling?

| Option | Description | Selected |
|--------|-------------|----------|
| 1h default, accept --duration up to 24h | `--duration` defaults to `1h`; accepts any value `kubectl create token` honors. POC operators get a short-lived token for testing; can extend to a workday if needed. Apiserver may clamp at its `--service-account-max-token-expiration` (k3s default is 24h). | ✓ |
| 8h default (workday) | Default `--duration=8h`. Single `kubectl create token --duration=8h <sa>` call covers a full demo/work session. Slightly looser security default; arguably more useful for POC operators. | |
| Pass-through (no default) | Always require explicit `--duration`. Forces the operator to think about expiry every call. More friction; less ergonomic for repeated demo. Probably overkill for a POC. | |

**User's choice:** 1h default, accept --duration up to 24h
**Notes:** Recommended option chosen. Maps to D-10-02.

---

## <owner> arg semantics

### Q1 — How should the script interpret the `<owner>` positional arg?

| Option | Description | Selected |
|--------|-------------|----------|
| Existing per-tenant SA | `<owner>` MUST match an existing SA in `tenant-<tenant>` namespace — currently only `gitops-reconciler` (Phase 9 D-09-02). Script does `kubectl create token <owner> -n tenant-<tenant>`. No Tenant CR mutation. `<owner>` is effectively a sanity-check + future-proof slot for Phase 12's potential multi-SA shape. Minimal code; closest to Phase 11 N1–N12 negative-RBAC test needs. | ✓ |
| Mint NEW SA per call + Group owner | Phase 10 modifies the Tenant CR yaml to add a Group owner (`kind: Group, name: system:serviceaccounts:tenant-<tenant>`). Any SA in `tenant-<tenant>` becomes an auto-owner via Group membership. `<owner>` is a fresh SA name; script creates SA imperatively + mints token. Supports per-developer kubeconfig demo flow but adds Tenant-CR-yaml diff to Phase 10 and an extra imperative-create surface. | |
| Existing per-tenant SA + future-proof check | Same as option 1 but stricter: script reads spec.owners[] from the Tenant CR and validates `<owner>` matches a `kind: ServiceAccount` entry. If not, fail with a helpful error. Adds a kubectl call but lints the contract sharply. | |

**User's choice:** Existing per-tenant SA
**Notes:** Recommended option chosen. Maps to D-10-03. The simpler option avoids Tenant-CR mutation; SA enumeration in error messages comes from D-10-04.

### Q2 — Validation behavior when SA `<owner>` doesn't exist in `tenant-<tenant>` namespace?

| Option | Description | Selected |
|--------|-------------|----------|
| Fail fast w/ list of valid SAs | Use preflight-lib `fail` helper with actionable error: `Owner '<owner>' SA not found in namespace tenant-<tenant>. Available SAs in this tenant: gitops-reconciler. Hint: run /gsd-execute-phase 9 first if Phase 9 has not landed yet, or pass a known SA name.` Exit 1. Mirrors `create-cluster.sh`'s drift-detection error style. | ✓ |
| Auto-create the SA | If SA doesn't exist, create it imperatively in `tenant-<tenant>` namespace + warn that it's not formally registered in spec.owners[] (so Capsule's webhook will deny tenant ops from it). Useful for ad-hoc demos but masks real bugs. | |
| Sanity-check the Tenant CR exists too | Same fail-fast as option 1, but also pre-check `kubectl get tenant <tenant>` exists on spoke-capsule. Catches misspelled tenant names before reaching the SA check. One extra kubectl call. | |

**User's choice:** Fail fast w/ list of valid SAs
**Notes:** Recommended option chosen. Maps to D-10-04. Note: The recommended preflight order in CONTEXT.md DOES include the Tenant-CR existence pre-check as step 3 (before the SA check) — this combines the chosen option's actionable error UX with the option-3 sharper-error rationale, taken as a low-cost ergonomic improvement.

---

## Tenant inner K kubeConfig swap

### Q1 — How should Phase 10 handle Phase 9 D-09-03's forward-pointer to swap tenant inner K kubeConfig source from `spoke-capsule-kubeconfig` to per-tenant proxy-kubeconfigs?

| Option | Description | Selected |
|--------|-------------|----------|
| Defer to Phase 11/12 | Phase 10 sticks to ROADMAP-literal scope: ship only PROXY-01..03 (human-CLI script + proxy round-trip + doc/fixture). Phase 9's transitional cluster-admin + SA-impersonation kubeConfig keeps working for tenant inner K reconcile. The actual swap is research-uncertain (does capsule-proxy correctly handle Flux's Server-Side Apply chains, not just human LIST?) and naturally absorbed by Phase 12 (capsule-addon-fluxcd auto-manages tenant SA + kubeconfig). | ✓ |
| Include in Phase 10 scope | Phase 10 mints two per-tenant proxy-kubeconfig Secrets on hub (`tenant-alpha-proxy-kubeconfig`, `tenant-bravo-proxy-kubeconfig`, with `value.yaml` key per P40/P18) via a register-poc-cluster.sh extension or new script, then modifies pocs/capsule/tenants/{alpha,bravo}.yaml to point `spec.kubeConfig.secretRef.name` at them. Adds a Flux-side reconcile path test — closes the D-09-03 forward-pointer cleanly. Risk: capsule-proxy may not handle Flux's SSA chains; could require Phase 11+ rework. | |
| Optional sub-plan | Phase 10 core scope = ROADMAP-literal (PROXY-01..03). Add an OPTIONAL Plan 10-04 ("forward-pointer to Phase 12") that performs the swap. Verifier does NOT gate on the swap — if it works, we close D-09-03; if it doesn't, the plan is rolled back atomically with the failure documented for Phase 12 to pick up. Lets us learn early without bloating the must-haves. | |

**User's choice:** Defer to Phase 11/12
**Notes:** Recommended option chosen. Maps to D-10-05. ROADMAP-literal scope discipline; research uncertainty justifies the deferral. Phase 12 capsule-addon-fluxcd is the natural absorption point.

### Q2 — Where should the deferred D-09-03 swap pointer land?

| Option | Description | Selected |
|--------|-------------|----------|
| Deferred Ideas in 10-CONTEXT.md | Note in 10-CONTEXT.md `<deferred>` section: "D-09-03 forward-pointer — tenant inner K kubeConfig source swap to per-tenant proxy-kubeconfigs. Naturally absorbed by Phase 12 (capsule-addon-fluxcd) if ADR-008 outcome ∈ {adopt, defer}; future work if reject/replaced." No explicit Phase 11/12 surgery; Phase 12's gate condition + addon mechanics already handle it organically. | ✓ |
| Add to REQUIREMENTS.md Future Requirements | Move the swap pointer to REQUIREMENTS.md "Future Requirements — Surfaced by v0.19 research" section so it survives milestone close even if Phase 12 doesn't run. Slightly more durable record than Deferred Ideas in a phase CONTEXT. | |
| Both — deferred + future requirements | Note in 10-CONTEXT.md `<deferred>` AND add to REQUIREMENTS.md Future Requirements. Belt-and-suspenders. Two diffs, but both surfaces capture the pointer for downstream readers. | |

**User's choice:** Deferred Ideas in 10-CONTEXT.md
**Notes:** Recommended option chosen. Single-source-of-truth for Phase 10 deferrals.

---

## TLS trust shape

### Q1 — How should the issued kubeconfig handle capsule-proxy's self-signed TLS cert?

| Option | Description | Selected |
|--------|-------------|----------|
| Embed CA cert | Read the cert from the in-cluster Secret minted by Phase 8 D-08-11's controller-less certgen Job (`kubectl ... get secret capsule-proxy -o jsonpath='{.data.ca\.crt}'`), embed as `certificate-authority-data: <base64>`. Proper TLS trust; the kubeconfig actually verifies. Adds ~5 lines of script logic + a kubectl call. Matches future-EKS-translation posture. | ✓ |
| insecure-skip-tls-verify: true | Set `insecure-skip-tls-verify: true` in the kubeconfig cluster block. POC-simple. Matches Phase 8 healthz check posture (`curl -k`). Document in `docs/poc-capsule.md` that this is a POC trade-off. Avoids the kubectl-secret-read path. But the issued kubeconfig demonstrates a security anti-pattern that would NOT translate to EKS. | |
| Default secure, --insecure flag | Default behavior embeds the CA cert. Add `--insecure` flag that flips to `insecure-skip-tls-verify: true`. Operator has both modes available. More code (two paths) but flexible. | |

**User's choice:** Embed CA cert
**Notes:** Recommended option chosen. Maps to D-10-06. Aligns with `docs/capsule-on-eks.md` posture (proper TLS in EKS-translation).

### Q2 — How does the script source the CA cert at runtime?

| Option | Description | Selected |
|--------|-------------|----------|
| Live kubectl read at script-time | `kubectl --context=k3d-spoke-capsule -n capsule-system get secret capsule-proxy -o jsonpath='{.data.ca\.crt}'` (or `tls.crt` if `ca.crt` is absent — self-signed root). Always-fresh against current cert; no stale-cert risk. Planner verifies the actual Secret name + key shape against capsule-proxy v0.12.0 chart's certgen output during research. Note as a research-flagged item like Phase 9 D-09-03a. | ✓ |
| Cache at register-time | Extend `register-poc-cluster.sh` (or add a separate prep step) to read + cache the CA cert into a local file. `issue-tenant-kubeconfig.sh` just reads the cached file. Saves one kubectl call per invocation but adds a cache-staleness failure mode if cert rotates. | |
| Both — try cache, fallback to live read | Check for cached file; if present and recent, use; if missing, do live kubectl read. Best UX but most code paths. | |

**User's choice:** Live kubectl read at script-time
**Notes:** Recommended option chosen. Maps to D-10-06. Research-flagged item D-10-06a captures Secret-key-shape verification for Plan 10-RESEARCH.

### Q3 — Issued kubeconfig structure?

| Option | Description | Selected |
|--------|-------------|----------|
| Single-context, named by tenant | One `clusters[]`, one `users[]`, one `contexts[]`. Context name: `tenant-<tenant>-via-proxy`. User name: `<owner>`. Cluster name: `capsule-proxy-127.0.0.1`. `current-context` set to the single context. Clean, minimal, easy to merge with operator's existing kubeconfig if they want. | ✓ |
| Single-context, generic names | Generic names: cluster `capsule-proxy`, user `tenant-owner`, context `tenant`. Simpler shape but conflicts when issued for both alpha + bravo — if the operator merges both, names collide. | |
| Two contexts (proxy + direct apiserver) | One context for proxy round-trip, one context for direct apiserver bypass with the same token. Lets the PROXY-02 verifier test both paths from a single kubeconfig with `kubectl --context=...` switches. Slightly larger output but verifier-friendly. | |

**User's choice:** Single-context, named by tenant
**Notes:** Recommended option chosen. Maps to D-10-07. The two-context option is rejected in favor of D-10-08's bats-constructs-on-the-fly approach for the falsifier — keeps the script's output a clean human-use artifact.

### Q4 — How does PROXY-02's direct-apiserver-bypass test (`:6446` returns unfiltered list) get its kubeconfig?

| Option | Description | Selected |
|--------|-------------|----------|
| Bats constructs on-the-fly | Verifier bats reads the issued kubeconfig, extracts the token, constructs a minimal direct-apiserver kubeconfig in a tmpfile (server=`https://127.0.0.1:6446` + same token + `insecure-skip-tls-verify: true`). Run `kubectl --kubeconfig=$tmpfile get namespaces` — expect FULL list. The script stays minimal; the verifier owns the falsifier construction. | ✓ |
| Script `--mode direct` flag | Add `--mode {proxy,direct}` flag to the script (default proxy). `--mode direct` outputs a kubeconfig with `server: https://127.0.0.1:6446` instead of the proxy URL. Pros: no bats kubeconfig surgery. Cons: ships a footgun mode in the script that operators might leave on. | |
| Script outputs both contexts (single kubeconfig) | (Equivalent to the earlier "two contexts" option — dropped.) | |

**User's choice:** Bats constructs on-the-fly
**Notes:** Recommended option chosen. Maps to D-10-08. Keeps script focused on happy-path; falsifier is verifier-side concern.

---

## Claude's Discretion

The following gray areas were not surfaced as discussion items because the v0.18 + Phase 7/8/9 patterns make defaults obvious (recorded in 10-CONTEXT.md `<decisions>` § "Claude's Discretion"):

- **`task` surface extensions** — default: none (matches Phase 7/8/9 default).
- **Stdout vs stderr split** — default: stdout = pure YAML kubeconfig; stderr = `preflight-lib` log lines (clean redirect ergonomics).
- **Idempotency** — default: naturally idempotent via TokenRequest (each call mints fresh token); `--write-to` overwrites without prompt.
- **JSON output mode** — default: none (kubeconfig spec is YAML).
- **`docs/poc-capsule.md` cross-link depth** — default: single H2 "Tenant kubeconfig delivery contract" section; cross-links to Phase 7 D-14 leak defenses, Phase 8 CAP-02 NodePort, Phase 9 D-09-02 SA, `docs/capsule-on-eks.md` IRSA forward-pointer.
- **`--write-to` validation** — default: strict tmpdir-root prefix check via `realpath -m`.
- **Verifier script wrapper** — default: bats-only (matches Phase 8/9).
- **Reconcile loop noise tolerance window** — default: ≤2 reconcile cycles; live-bats retry budget 3 attempts × 30s.

## Deferred Ideas

Captured during analysis (not raised by the user as new ideas during discussion); recorded in 10-CONTEXT.md `<deferred>` for downstream awareness:

- D-09-03 forward-pointer (tenant inner K kubeConfig swap) — deferred to Phase 12 absorption.
- Negative RBAC bats N1–N12 → Phase 11 VAL-01.
- Capsule webhook failure / recoverable mode → Phase 11 VAL-02.
- Clean teardown → Phase 11 VAL-03.
- `task rebuild` SLO regression test → Phase 11 VAL-04.
- One-shot history gitleaks scan post-first-push → Phase 11 VAL-05.
- Graduation ADR-008 → Phase 11 VAL-06.
- `capsule-addon-fluxcd v0.2.3` trial → Phase 12 (gated).
- Multi-SA-per-tenant pattern → Phase 12 / future work.
- `task issue-tenant-kubeconfig` wrapper → future ergonomic enhancement (no current need).
- JSON output mode for the script → future enhancement.
- Cert-rotation handling under cert-manager → post-v0.19 (when cert-manager is adopted).
- HA Capsule, OIDC, multi-spoke federation → POST-v0.19 milestones.

No new deferred items surfaced during this discussion (analysis stayed within Phase 10 scope).
