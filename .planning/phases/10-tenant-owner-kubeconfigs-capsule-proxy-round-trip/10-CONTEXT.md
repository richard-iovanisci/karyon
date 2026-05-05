# Phase 10: Tenant Owner Kubeconfigs + Capsule-Proxy Round-trip - Context

**Gathered:** 2026-05-05
**Status:** Ready for planning

<domain>
## Phase Boundary

Mint imperative tenant owner kubeconfigs that route through capsule-proxy, give each owner LIST visibility ONLY into their own tenant's namespaces, and never land in git. Phase 10 succeeds when:

1. **PROXY-01** — `scripts/poc/capsule/issue-tenant-kubeconfig.sh <tenant> <owner>` mints a tenant kubeconfig with `server: https://127.0.0.1:30443` (capsule-proxy NodePort), prints to stdout by default, supports optional `--write-to <path>` rooted at `${TMPDIR:-/tmp}/karyon-tenants/`.
2. **PROXY-02** — Using the issued kubeconfig, `kubectl get namespaces` returns ONLY namespaces owned by the tenant (proxy LIST filtering working). Direct apiserver access on `:6446` with the same token returns the unfiltered list (proves proxy is doing the filtering, not RBAC alone).
3. **PROXY-03** — Kubeconfig delivery contract documented in `docs/poc-capsule.md`: stdout default, optional `--write-to`, mandatory tmpdir-not-repo location, gitleaks rule catches accidental commits (synthetic-fixture bats verifies).
4. **P29 defense holds** — first push after this phase passes the gitleaks pre-commit + post-push scan with zero findings. **NOTE:** Per Phase 8 D-08-13, push-gate is DEFERRED to Phase 11 VAL-05. Phase 10 commits remain local-only; the structural P29 defenses (gitignore globs, gitleaks rule, synthetic-fixture bats) are in scope; the push event itself is not.

**Phase 10 ships human-CLI proxy round-trip + doc + fixture ONLY.** The following are explicitly **out of scope** for Phase 10 (each owned by a later phase or absorbed organically):

- **Tenant inner Kustomization kubeConfig source swap** (Phase 9 D-09-03 forward-pointer) — tenant inner Ks (`pocs/capsule/tenants/{alpha,bravo}.yaml`) currently use `spoke-capsule-kubeconfig` (cluster-admin + SA impersonation per Phase 9 D-09-03 transitional shape). Phase 9 anticipated a Phase 10 swap to per-tenant proxy-kubeconfigs, but that swap is **deferred** here — see `<deferred>` for rationale.
- Negative RBAC bats N1–N12 → **Phase 11** (VAL-01).
- Capsule webhook failure / recoverable mode → **Phase 11** (VAL-02).
- Clean teardown (`task destroy-poc capsule`) → **Phase 11** (VAL-03).
- `task rebuild` SLO regression test (< 230s, container-ID stability) → **Phase 11** (VAL-04).
- One-shot history gitleaks scan post-Phase-10 first push → **Phase 11** (VAL-05). Phase 10's structural defenses (gitignore, gitleaks rule, synthetic fixture) are exercised; the actual push + scan is Phase 11.
- Graduation ADR-008 → **Phase 11** (VAL-06).
- `capsule-addon-fluxcd v0.2.3` (which auto-creates tenant SA + kubeconfig Secret) → **Phase 12** (OPTIONAL — gated on ADR-008 outcome ∈ {adopt, defer}).

> **Calibration vs. Phase 9 D-09-03 forward-pointer:** Phase 9 expected Phase 10 to also swap tenant inner K kubeConfig source from `spoke-capsule-kubeconfig` to per-tenant proxy-kubeconfigs. ROADMAP Phase 10 success criteria do NOT include that swap — they're focused on the human-CLI round-trip (PROXY-01..03 verbatim). Discussion confirmed: Phase 10 ships human-CLI scope only; the Flux-side swap is research-uncertain (does capsule-proxy correctly handle Flux's Server-Side Apply chains, not just human LIST?) and naturally absorbed by Phase 12 (capsule-addon-fluxcd auto-manages tenant SA + kubeconfig). Notation in `<deferred>`.

</domain>

<decisions>
## Implementation Decisions

### Token source — TokenRequest API (D-10-01)

- **D-10-01:** **TokenRequest API** — `kubectl --context=k3d-spoke-capsule create token <owner> -n tenant-<tenant> --duration=<d>`. Short-lived bearer token returned via API response; no in-cluster Secret artifact. Aligns with k8s ≥1.24 deprecation of auto-mounted SA Secrets (k3s v1.34.6 is post-deprecation by ~3 years; long-lived `kind: Secret type: kubernetes.io/service-account-token` is the explicit anti-pattern signal Phase 7 D-14's `kubeconfig-bearer-token` gitleaks rule defends against).
  - **Rationale:** Security default — auto-expiry is a feature for POC kubeconfig hygiene; operator re-runs the script when the token expires. No persistent Secret to leak. Aligns with future-EKS-translation posture (IRSA replaces TokenRequest cleanly; static SA Secrets do not). Long-lived path was rejected explicitly: it ships the exact shape the gitleaks rule fires on, signaling the kubeconfig as inherently riskier than necessary for the POC's audit/demo flow.
  - **Acceptance — token issuance verbatim:**
    ```bash
    kubectl --context=k3d-spoke-capsule create token "${OWNER}" -n "tenant-${TENANT}" --duration="${DURATION}"
    ```

### Token duration default + clamp behavior (D-10-02)

- **D-10-02:** **Default `--duration=1h`**; accept `--duration <d>` flag with values `kubectl create token` honors. Apiserver may clamp at its `--service-account-max-token-expiration` (k3s default is 24h; documented in `docs/poc-capsule.md` PROXY-03 section).
  - **Rationale:** 1h is the canonical Kubernetes TokenRequest default. POC operators get a usable token for testing; can extend up to k3s's 24h cap. Beyond 24h would require apiserver flag-tuning (out of POC scope).
  - **Bats coverage:** Static — script grep-asserts `--duration=` is passed and a default is set; live — bats invokes the script, decodes the JWT `exp` claim, asserts `exp - iat ≈ 1h` (±60s tolerance for clock skew).

### `<owner>` arg semantics — existing per-tenant SA only (D-10-03)

- **D-10-03:** **`<owner>` MUST match an existing SA in `tenant-<tenant>` namespace.** Phase 9 D-09-02 created exactly one such SA per tenant: `gitops-reconciler`. The `<owner>` arg is effectively (a) a sanity-check (catches typos, wrong tenant), (b) a future-proof slot for any later phase that adds additional SAs per tenant. **Phase 10 does NOT mutate the Tenant CR** — no Group owner, no imperative spec.owners[] patch. The existing Tenant CR shape (Phase 9 spec.owners = [SA gitops-reconciler, User <tenant-name>]) is sufficient for PROXY-01..03.
  - **Rationale:** Minimal-mutation path. The `gitops-reconciler` SA is already a registered Tenant owner via Phase 9's Tenant CR. Capsule's webhook treats the SA-token-authenticated Subject (`system:serviceaccount:tenant-alpha:gitops-reconciler`) as a Tenant owner; the proxy applies LIST filtering by tenant ownership; the kubeconfig works without further state mutation. Multi-SA-per-tenant gold-plating is not required by Phase 11 N1–N12 negative-RBAC suite (each test uses a single tenant kubeconfig, doesn't enumerate multiple owners). Phase 12 (capsule-addon-fluxcd) is the natural surface for multi-SA / kubeconfig-Secret automation if/when needed.

### Owner-not-found error shape — fail-fast with helpful list (D-10-04)

- **D-10-04:** **Fail fast with `preflight-lib`'s `fail` helper.** When `<owner>` SA is not found in `tenant-<tenant>`, exit 1 with:
  ```
  Owner '<owner>' SA not found in namespace tenant-<tenant>.
       Available SAs in this tenant: gitops-reconciler.
       Hint: run /gsd-execute-phase 9 first if Phase 9 has not landed yet,
             or pass a known SA name (currently only 'gitops-reconciler').
  ```
  Use `kubectl --context=k3d-spoke-capsule -n tenant-<tenant> get sa -o name | sed 's|serviceaccount/||g'` to enumerate available SAs in the error message. NOT auto-create (masks real bugs); NOT silent fallback (PROXY-01 CLI contract is positional, not optional).
  - **Rationale:** Mirrors `scripts/poc/capsule/create-cluster.sh`'s drift-detection fail-fast style — actionable error + names the namespace + lists what was found + offers a hint. v0.18 + Phase 7 ergonomics inheritance.
  - **Pre-flight order in script** (recommended, planner reshapes freely):
    1. `have kubectl k3d` — required commands present.
    2. `kubectl config get-contexts k3d-spoke-capsule -o name` — context exists (else: hint to run `k3d kubeconfig get spoke-capsule | tee -a $HOME/.kube/config`).
    3. `kubectl --context=k3d-spoke-capsule get tenant <tenant>` — Tenant CR exists.
    4. `kubectl --context=k3d-spoke-capsule -n tenant-<tenant> get sa <owner>` — SA exists.
    5. Mint token, read CA cert, emit kubeconfig.

### Tenant inner K kubeConfig swap — DEFERRED (D-10-05)

- **D-10-05:** **The Phase 9 D-09-03 forward-pointer to swap tenant inner K kubeConfig source from `spoke-capsule-kubeconfig` to per-tenant proxy-kubeconfigs is DEFERRED out of Phase 10.** Phase 9's transitional cluster-admin + SA-impersonation kubeConfig keeps working for tenant inner K reconcile. Notation in `<deferred>` references Phase 12 absorption rationale.
  - **Rationale:** Two reasons: (1) ROADMAP Phase 10 success criteria don't include the swap — they're literally "human-CLI proxy round-trip + doc + fixture". (2) Research uncertainty: capsule-proxy is designed for human kubectl LIST filtering; whether it correctly handles Flux's Server-Side Apply chains end-to-end is non-trivial to verify and would expand Phase 10 scope by an unknown amount. Phase 12 (capsule-addon-fluxcd) absorbs this organically — the addon auto-creates per-tenant SA + kubeconfig Secret, and IF ADR-008 outcome adopts/defers Capsule, the addon's behavior IS the swap. If ADR-008 rejects/replaces, the swap becomes future work (post-v0.19).
  - **Phase 9 spec preservation:** No retroactive change to Phase 9 D-09-03 framing. The forward-pointer is acknowledged in 10-CONTEXT.md `<deferred>`; downstream agents (researcher, planner) read both 09-CONTEXT.md and 10-CONTEXT.md and see consistent framing.

### TLS trust shape — embed CA cert (D-10-06)

- **D-10-06:** **Embed proxy CA cert** as `certificate-authority-data: <base64>` in the issued kubeconfig's cluster block. Read at script-time via:
  ```bash
  CA_CRT=$(kubectl --context=k3d-spoke-capsule -n capsule-system get secret capsule-proxy -o jsonpath='{.data.ca\.crt}')
  # If .data.ca\.crt is empty (self-signed root in tls.crt), fall back to .data.tls\.crt
  ```
  Live-read at script-runtime, not cached. NOT `insecure-skip-tls-verify: true` (POC ships a security anti-pattern that wouldn't translate to EKS); NOT a `--insecure` flag (over-engineered for the POC).
  - **Rationale:** Proper TLS trust. The kubeconfig actually verifies the proxy's identity. Aligns with future-EKS-translation posture documented in `docs/capsule-on-eks.md` (where real CAs / cert-manager / ALB-managed certs would replace the in-cluster certgen Secret). Live-read keeps the kubeconfig fresh against any cert rotation.
  - **Research-flagged item (D-10-06a):** The capsule-proxy chart's `options.generateCertificates: true` path (Phase 8 D-08-11 controller-less certgen Job using `kube-webhook-certgen`) produces a Secret named `capsule-proxy` in `capsule-system` namespace on spoke-capsule. **Researcher MUST verify the actual key name** during Plan 10-RESEARCH — `kube-webhook-certgen` standard output is `tls.crt`, `tls.key`, `ca.crt`; if `ca.crt` is absent (self-signed root with `tls.crt` doubling as the CA), the script falls back to `tls.crt`. Both fallback paths must be implemented + bats-asserted. **This does NOT block planning** (the structural defense is unaffected; the question is purely about which jsonpath the script reads).

### Issued kubeconfig structure — single-context, named by tenant (D-10-07)

- **D-10-07:** **Single-context kubeconfig**, names parameterized by tenant + owner:
  ```yaml
  apiVersion: v1
  kind: Config
  clusters:
    - name: capsule-proxy-127.0.0.1
      cluster:
        server: https://127.0.0.1:30443
        certificate-authority-data: <base64 ca.crt>
  users:
    - name: <owner>                          # e.g., gitops-reconciler
      user:
        token: <bearer token from TokenRequest>
  contexts:
    - name: tenant-<tenant>-via-proxy        # e.g., tenant-alpha-via-proxy
      context:
        cluster: capsule-proxy-127.0.0.1
        user: <owner>
        namespace: tenant-<tenant>           # default ns inside the tenant home
  current-context: tenant-<tenant>-via-proxy
  ```
  - **Rationale:** Clean, minimal. Context name `tenant-<tenant>-via-proxy` is unambiguous if the operator merges multiple tenant kubeconfigs (alpha + bravo). User name `<owner>` lets the kubeconfig surface which SA is authenticating without parsing the JWT. Cluster name `capsule-proxy-127.0.0.1` makes the proxy-vs-direct distinction obvious to the human reader.
  - **`namespace:` default in context:** Set to `tenant-<tenant>` so `kubectl get pods` (no `-n`) lands in the tenant's home namespace, not `default`. Operator can override with `-n alpha-app1` etc. Mirrors v0.18 ergonomic pattern (kubeconfigs default to a useful namespace).

### Direct-apiserver-bypass test (PROXY-02 falsifier) — bats constructs on-the-fly (D-10-08)

- **D-10-08:** **The script outputs proxy-mode-only.** PROXY-02's direct-apiserver falsifier (`kubectl get namespaces` against `:6446` returns FULL list, proving proxy is doing the filtering) is constructed by the verifier bats:
  1. Bats reads the issued kubeconfig.
  2. Extracts the bearer token (yq or jq parse the YAML).
  3. Constructs a minimal direct-apiserver kubeconfig in a `mktemp`-d tmpfile:
     ```yaml
     clusters:
       - name: direct
         cluster:
           server: https://127.0.0.1:6446
           insecure-skip-tls-verify: true     # spoke-capsule apiserver cert won't have proxy SANs
     users:
       - name: <owner>
         user:
           token: <extracted bearer>
     contexts:
       - name: direct
         context:
           cluster: direct
           user: <owner>
     current-context: direct
     ```
  4. `kubectl --kubeconfig=$tmpfile get namespaces` — expect a count > the proxy-LIST count (proves filtering happens at the proxy, not at apiserver RBAC).
  5. `rm -f $tmpfile` in `teardown()`.
  - **Rationale:** Keeps the script focused on its happy-path (issue a proxy-routed kubeconfig). The falsifier construction is a verifier concern; a `--mode direct` flag in the script would ship a footgun mode operators might leave on accidentally. Bats owning the construction is also closer to how Phase 11 N1–N12 will exercise the proxy + tenant kubeconfigs.
  - **Bats fixture path:** Construct via `mktemp -d "${TMPDIR:-/tmp}/proxy-falsifier-XXXX"` — tmpdir-rooted, NOT in repo (P29 invariant; the synthetic fixture in `tests/fixtures/gitleaks/` is the only kubeconfig-shaped artifact allowed in-repo).

### Test scaffolding pattern — repeat Phase 7/8/9 Wave 0 RED bats (D-10-09)

- **D-10-09:** **Repeat the Phase 7/8/9 Wave 0 pattern.** Plan 10-00 lands ALL Phase 10 bats (every static contract + every live observation, gated) BEFORE the script lands. Subsequent plans make the bats green by landing the script + doc updates.
  - **Concrete Phase 10 bats coverage** (planner expands; this is the floor):
    - **Static (Wave 0) — script shape:**
      - `scripts/poc/capsule/issue-tenant-kubeconfig.sh` exists with `#!/usr/bin/env bash` + `set -euo pipefail` + `REPO_ROOT`/`SCRIPT_DIR` pinning + `source scripts/lib/preflight-lib.sh`.
      - Header comment block cites PROXY-01 + D-10-01 / D-10-03 / D-10-06 + P31 isolation + ADR-004.
      - `<tenant> <owner>` positional arg parsing (NOT optional).
      - `--write-to <path>` parsing — root-restriction enforced (`${TMPDIR:-/tmp}/karyon-tenants/`).
      - `--duration <d>` parsing — default `1h`.
      - `kubectl --context=k3d-spoke-capsule create token "${OWNER}" -n "tenant-${TENANT}"` literal.
      - `server: https://127.0.0.1:30443` literal in script's heredoc kubeconfig template.
      - `certificate-authority-data:` literal (NOT `insecure-skip-tls-verify:` — anti-pattern lint).
      - `current-context: tenant-${TENANT}-via-proxy` literal.
    - **Static (Wave 0) — leak defenses (PROXY-03):**
      - `.gitignore` still contains Phase 7 D-14 globs verbatim (`karyon-tenants/`, `*.tenant.kubeconfig`, `tenants/**/access.yaml`, `tenants/**/admin.yaml`).
      - `.gitleaks.toml` still contains Phase 7 D-14 `kubeconfig-bearer-token` rule + allowlist.
      - `tests/fixtures/gitleaks/synthetic-kubeconfig.yaml` synthetic fixture is allowlisted (regression gate from Phase 7 D-14).
    - **Static (Wave 0) — POC isolation (Phase 7 P31 inheritance):** Re-run Phase 7's `tests/bats/poc-isolation-01-static.bats`. Phase 10's new file `scripts/poc/capsule/issue-tenant-kubeconfig.sh` MUST NOT introduce `spoke-capsule` mentions in v0.18 scripts (it lives under `scripts/poc/capsule/`, so the static lint passes by location).
    - **Static (Wave 0) — `docs/poc-capsule.md` PROXY-03 section:** Doc has a "Tenant kubeconfig delivery contract" subsection covering: stdout default, optional `--write-to`, mandatory tmpdir-not-repo location, gitleaks rule reference, example `bash scripts/poc/capsule/issue-tenant-kubeconfig.sh alpha gitops-reconciler` invocation.
    - **Live (Wave 1+) — PROXY-01:** Run script against alpha + bravo, assert exit 0; assert stdout is valid YAML (`yq eval . -` succeeds); assert decoded `kind: Config` + `current-context: tenant-<tenant>-via-proxy`; assert `--write-to` lands the file inside `${TMPDIR:-/tmp}/karyon-tenants/`; assert `--write-to` REJECTS paths outside tmpdir (e.g., `--write-to ./repo-relative.kubeconfig` → exit 1).
    - **Live (Wave 1+) — PROXY-02 (proxy LIST):** Run `kubectl --kubeconfig=<issued> get namespaces -o name`. Expect the namespace list has ≥1 tenant-owned ns (`tenant-alpha` + any `alpha-*` namespaces from Phase 9 TEN-02 test) AND does NOT include `tenant-bravo`, `kube-system`, `flux-system`, `capsule-system`.
    - **Live (Wave 1+) — PROXY-02 falsifier (direct apiserver):** Bats constructs direct kubeconfig per D-10-08 + asserts `kubectl get namespaces` count > proxy LIST count (or simply ≥10 — kube-system + flux-system + capsule-system + tenant-alpha + tenant-bravo + alpha-app1 + bravo-app1 + 3 default ns = 10+ ns under cluster-admin LIST).
    - **Live (Wave 1+) — PROXY-03 synthetic fixture:**
      - Drop a synthetic-tenant-shaped kubeconfig at a path that should be caught by gitignore (e.g., `karyon-tenants/leaked-test.kubeconfig`); run `git check-ignore` and assert exit 0 (path is ignored).
      - Drop the same content at a path NOT in gitignore globs (e.g., `tests/fixtures/gitleaks/temp-tenant-fixture.yaml`, NOT in the existing allowlist); run `gitleaks detect --no-git --source <fixture-path>`; assert non-zero exit (rule fires); cleanup the fixture in `teardown()`.
    - **Live (Wave 1+) — Phase 8 + 9 invariant preservation:** Re-run Phase 8 CAP-01..03 + ADR-004 + Phase 9 TEN-01..06 + lockdown + Phase 7 P31 isolation. Phase 10's script-only landing must NOT regress any prior contract.
  - **Rationale:** Nyquist gate worked in Phase 7 + 8 + 9. Already-validated pattern. Phase 10's surface is small (one script + doc + one bats file new), but the verifier still reruns prior-phase invariants for regression safety.

### Plan ordering inside Phase 10 (D-10-10)

- **D-10-10:** Recommended plan ordering (planner may reshape into 3–5 plans without re-asking):
  - **Plan 10-00 — Wave 0 RED bats scaffold.** Land all D-10-09 bats files (static + live, live gated by cluster-info probe). All bats RED at end of plan. Mirrors 07-00 / 08-00 / 09-00.
  - **Plan 10-01 — Script + doc.** Lands `scripts/poc/capsule/issue-tenant-kubeconfig.sh` + appends "Tenant kubeconfig delivery contract" subsection to `docs/poc-capsule.md`. Live PROXY-01 bats turn green; static bats turn green; PROXY-02 live bats may stay RED if no tenant kubeconfig has been issued yet on the live cluster.
  - **Plan 10-02 — Verifier.** Live bats observation per D-10-09 live coverage. Reruns Phase 7 P31 + Phase 8 CAP-01..03 + Phase 9 TEN-01..06 + ADR-004 + final task health-check exit 0. Writes `10-VERIFICATION.md`. Closes folded carryover (none folded for Phase 10 — see `<deferred>` "Reviewed Todos" subsection).
  - Planner may merge 10-00 + 10-01 if confident Wave 0 bats can be authored alongside the script (Phase 7/8/9 patterns make this unlikely to cause issues), or split 10-01 (script vs doc) if the doc surface grows. Default 3-plan structure is sufficient.

### Folded Todos

No todos were folded into Phase 10 scope. The two pending todos (`2026-04-29-phase-7-gitleaks-planning-doc-allowlist.md` resolves_phase: 11; `2026-04-29-phase-7-hub-flux-observable-reconcile.md` resolves_phase: 8) explicitly route elsewhere via their `resolves_phase` markers. See `<deferred>` "Reviewed Todos" subsection.

### Claude's Discretion

The following gray areas are intentionally NOT specified — planner/researcher should default to v0.18 + Phase 7/8/9 patterns and note the chosen approach in PLAN.md without re-asking:

- **`task` surface extensions** — recommended default: **none**. Phase 7/8/9 default of "no new task targets" continues. The script is invoked directly: `bash scripts/poc/capsule/issue-tenant-kubeconfig.sh alpha gitops-reconciler [--duration 1h] [--write-to <tmpdir-path>]`. Adding `task issue-tenant-kubeconfig` would be sugar; the script's positional + flag arg surface is already ergonomic. If the planner reverses, a `task` target's command MUST quote-pass through positional + variadic flags cleanly.
- **Stdout vs stderr split** — recommended default: **stdout = pure YAML kubeconfig; stderr = `preflight-lib` log lines (section/pass/info/etc.)**. Lets `bash issue-tenant-kubeconfig.sh alpha gitops-reconciler > /tmp/alpha.kubeconfig` produce a clean redirect. Mirrors v0.18 + Phase 7 ergonomics.
- **Idempotency** — recommended default: **the script is naturally idempotent** because each invocation produces a fresh TokenRequest token. No state mutation; running it twice produces two valid kubeconfigs (different `iat` claims, identical other fields). If the operator passes `--write-to` and the file exists, OVERWRITE without confirmation (matches v0.18 destroy.sh / rebuild.sh non-interactive convention; no `-f`/`--force` flag needed because there's no destructive state).
- **JSON output mode** — recommended default: **none**. Stdout YAML is the kubeconfig contract. No JSON output mode for machine consumers; if the planner adds one, it's a follow-up enhancement.
- **`docs/poc-capsule.md` cross-link depth** — recommended default: **add a single "Tenant kubeconfig delivery contract" H2 section** (status: Active) covering PROXY-01..03 essentials. Cross-link to: Phase 7 D-14 leak defenses; Phase 8 CAP-02 NodePort; Phase 9 D-09-02 per-tenant SA; the existing "Distinct from `task fix-dns`" section pattern; and `docs/capsule-on-eks.md` for the EKS-translation forward-pointer. Phase 11 V0L-03 ordered teardown gets its own subsection later.
- **`--write-to <path>` validation** — recommended default: **strict tmpdir-root check**. Resolve `realpath -m <path>` and assert it has `${TMPDIR:-/tmp}/karyon-tenants/` (or `${TMPDIR}/karyon-tenants/` if TMPDIR is set) as a prefix. Otherwise fail with: `--write-to '<path>' is outside ${TMPDIR:-/tmp}/karyon-tenants/. Hint: tenant kubeconfigs MUST live in tmpdir per Phase 10 PROXY-03 + Phase 7 P29 invariant.` Mkdir the directory if missing.
- **Verifier script wrapper** — recommended default: **bats-only** (no `scripts/poc/capsule/verify-proxy.sh` wrapper). Live bats handle assertions directly. Mirrors Phase 8 D-08 + Phase 9 D-09 "task surface extensions" recommendation.
- **Reconcile loop noise tolerance window** — recommended default: same as Phase 8/9 — ≤2 reconcile cycles for any live observation that depends on prior-phase reconcile (Phase 8 HelmRelease + Phase 9 Tenant CR). Live-bats retry budget: 3 attempts with 30s sleep between.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project planning artifacts (REQUIRED reading)

- `.planning/REQUIREMENTS.md` — PROXY-01, PROXY-02, PROXY-03 contracts; load-bearing P29 (kubeconfigs MUST NOT land in git); P31 isolation (POC concerns under `scripts/poc/capsule/`); ADR-004 inheritance; v0.19 inheritance from v0.18 ADRs. **Phase 10 owns PROXY-01..03 verbatim.**
- `.planning/ROADMAP.md` (Phase 10 section + Phase 11 boundary call-out for `task rebuild` SLO regression + Phase 12 gate condition) — phase goal, ordered success criteria, dependency declarations.
- `.planning/PROJECT.md` — v0.19 out-of-scope items (cert-manager, OIDC, prod ingress, multi-spoke federation, hub-side Capsule, default platform adoption); ADR-004 hub-only invariant; public-repo secrets contract; v0.18 follow-up items (shellcheck cleanup, first-push CI verification — not in scope here, push gate is Phase 11 VAL-05).
- `.planning/STATE.md` — milestone-open decisions: 6-phase split rationale, P27/P29/P31 invariants. Phase 9 close-out (`passed_with_overrides` 8/8 must-haves: 4 live PASS + 4 D-08-13 push-gate-deferred to Phase 11 VAL-05). Phase 10 ready to plan.

### Phase 7/8/9 artifacts — REQUIRED context (Phase 10 inherits everything Phase 7+8+9 shipped)

- `.planning/phases/07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc/07-CONTEXT.md` — D-05 through D-17. **Especially D-10 (NodePort 30443 lock; CAPCLU-01 cluster shape), D-12 (P31 `scripts/poc/capsule/` namespace), D-14 (.gitignore + .gitleaks.toml leak defenses + synthetic-kubeconfig fixture), D-15 (preflight 30443 reservation).**
- `.planning/phases/07-foundation-poc-seam-spoke-capsule-cluster-eks-capsule-doc/07-SUMMARY.md` — what each Phase 7 plan shipped (`scripts/poc/capsule/{create-cluster.sh,fix-dns.sh}`, `register-poc-cluster.sh`, .gitignore + .gitleaks.toml + synthetic fixture, `docs/poc-capsule.md` host-restart section).
- `.planning/phases/08-capsule-capsule-proxy-bare-minimum-install/08-CONTEXT.md` — D-08-01 through D-08-13. **Especially D-08-02 (capsule-proxy chart `0.12.0`), D-08-11 (controller-less certgen Job + `capsule-proxy` Secret in `capsule-system` ns), D-08-12 (split-path architectural seam — informational; Phase 10 does not modify outer Ks), D-08-13 (push-gate deferral to Phase 11 VAL-05 — INHERITED INTO PHASE 10).**
- `.planning/phases/08-capsule-capsule-proxy-bare-minimum-install/08-SUMMARY.md` — Phase 8 close-out shape; HelmRelease + OCIRepository pattern; capsule-proxy NodePort/SAN values.
- `.planning/phases/09-tenants-flux-multi-tenancy-lockdown/09-CONTEXT.md` — D-09-01 through D-09-09. **Especially D-09-02 (per-tenant SA `gitops-reconciler` in `tenant-<tenant>` ns; multi-owner Tenant CR with SA + User), D-09-03 (transitional tenant inner K kubeConfig source — FORWARD-POINTER DEFERRED IN PHASE 10 D-10-05), D-09-04 (CapsuleConfiguration default singleton with `forceTenantPrefix: true` + `allowServiceAccountPromotion: true`), D-09-08 (Wave 0 RED bats scaffold pattern — INHERITED).**
- `.planning/phases/09-tenants-flux-multi-tenancy-lockdown/09-VERIFICATION.md` — Phase 9 verification status (`passed_with_overrides`); attempt-3 lockdown lessons (spoke SA naming differs by target cluster — informational only for Phase 10).

### Architecture Decision Records (load-bearing for Phase 10)

- `docs/adr/0001-single-wsl2-shared-docker-network.md` — k8s-net shared bridge; spoke-capsule reachable from WSL host via `127.0.0.1`.
- `docs/adr/0002-k3d-over-kind.md` — k3d cluster runtime; NodePort publish via `--port "30443:30443@server:0"` semantics.
- `docs/adr/0003-flux-over-argocd.md` — Flux 2 as GitOps tool; informational for Phase 10 (no Flux Kustomization changes here).
- `docs/adr/0004-hub-only-flux-control-plane.md` — **load-bearing**: NO Flux controllers run on spoke-capsule. Phase 10 verifier MUST re-grep-assert `kubectl --context=k3d-spoke-capsule get pods -n flux-system` returns no flux controllers (regression gate inheritance).
- `docs/adr/0005-kubernetes-version-pin.md` — k3s `v1.34.6-k3s1`; TokenRequest API and `--service-account-max-token-expiration` (24h default) clamp inheritance.

### Milestone-level research (REQUIRED for planning)

- `.planning/research/SUMMARY.md` §"Tenant Owner Kubeconfigs" / §"capsule-proxy LIST filtering semantics" — kubeconfig delivery contract design, proxy LIST filtering mechanism (proxy intercepts cluster-wide LIST verbs, applies tenant-ownership filter, returns subset). **Researcher MUST verify capsule-proxy v0.12.0's LIST-filtering scope** during Plan 10-RESEARCH (which resource kinds are filtered: Namespace, Pod, Secret, ConfigMap, etc.; what about cluster-scoped resources like ClusterRole — filtered or rejected?).
- `.planning/research/STACK.md` — capsule-proxy 0.12.0 pin; chart certgen output Secret shape (Phase 10 D-10-06a research-flagged item).
- `.planning/research/ARCHITECTURE.md` §"Phase 10 — tenant kubeconfig delivery + proxy round-trip" — script shape, kubeconfig structure, proxy LIST filtering mental model.
- `.planning/research/PITFALLS.md` — P26-P43 catalogue. **Phase 10 directly addresses:**
  - **P29** (load-bearing — kubeconfigs MUST NOT land in git; Phase 10 D-10-09 static bats re-grep .gitignore + .gitleaks.toml + synthetic fixture allowlist).
  - **Inherited from Phase 7 (verbatim regression gates):** D-14 gitignore globs, D-14 gitleaks rule, D-14 synthetic-kubeconfig.yaml fixture, P31 POC isolation contract.
  - **Inherited from Phase 8:** D-08-11 capsule-proxy certgen Secret name + key shape (Phase 10 D-10-06a research-flagged ambiguity).
  - **Inherited from Phase 9:** D-09-02 per-tenant SA name + namespace structure; the SA's tenant-owner registration in Tenant CR's spec.owners[].

### v0.18 + Phase 7/8/9 reference implementations (analogs to mirror in Phase 10)

- **`scripts/poc/capsule/create-cluster.sh`** — Phase 7 reference for `scripts/poc/capsule/`-rooted scripts. Phase 10's `issue-tenant-kubeconfig.sh` mirrors the head structure: `set -euo pipefail`, `SCRIPT_DIR`/`REPO_ROOT` pinning, `source scripts/lib/preflight-lib.sh`, head comment block citing PROXY-01 + relevant decisions, idempotent control-flow.
- **`scripts/poc/capsule/fix-dns.sh`** — Phase 7 reference for short imperative scripts using `preflight-lib` ergonomics (section/pass/warn/fail/info helpers). Phase 10 inherits.
- **`scripts/lib/preflight-lib.sh`** — output helpers; `have <cmd>` for tool gate; `section` for log scoping. Phase 10 reuses verbatim.
- **`tests/bats/test_helper`** — shared bats loader pinning `REPO_ROOT`. Phase 10 bats files load this without modification.
- **`tests/bats/poc-isolation-01-static.bats`** — Phase 7 P31 regression gate. Phase 10's new file `scripts/poc/capsule/issue-tenant-kubeconfig.sh` lives under `scripts/poc/capsule/` (excluded from the v0.18 lint set), so the static lint passes by location. Phase 10 verifier reruns this verbatim.
- **`tests/fixtures/gitleaks/synthetic-kubeconfig.yaml`** — Phase 7 D-14 positive fixture. Phase 10's PROXY-03 synthetic-fixture bats may reuse this OR add a tenant-flavored variant in `tests/fixtures/gitleaks/synthetic-tenant-kubeconfig.yaml` (planner discretion — both work; the existing fixture is generic enough).
- **`.gitignore`** — Phase 7 D-14 globs (`karyon-tenants/`, `*.tenant.kubeconfig`, `tenants/**/access.yaml`, `tenants/**/admin.yaml`) cover Phase 10 output paths. Phase 10 does NOT modify .gitignore (regression gate: bats grep-asserts these globs verbatim).
- **`.gitleaks.toml`** — Phase 7 D-14 `kubeconfig-bearer-token` rule + allowlist. Phase 10 does NOT modify .gitleaks.toml; the rule already covers Phase 10 output shape.
- **`docs/poc-capsule.md`** — Phase 7 doc with frontmatter `scope: Phase 7 ships only the Host restart recovery section. Phases 10/11 will add tenant kubeconfig delivery contract and ordered teardown procedure respectively.` **Phase 10 appends the "Tenant kubeconfig delivery contract" H2 section per PROXY-03.**
- **`pocs/capsule/spoke/tenants/{alpha,bravo}/{namespace,sa,tenant}.yaml`** — Phase 9 D-09-02 outputs. **Phase 10 does NOT modify these files** — the existing `gitops-reconciler` SA is the only `<owner>` Phase 10 supports per D-10-03.
- **`pocs/capsule/tenants/{alpha,bravo}.yaml`** — Phase 9 D-09-03 transitional tenant inner Ks. **Phase 10 does NOT modify these files** per D-10-05 (deferred swap).
- **`docs/capsule-on-eks.md`** — Phase 7 EKSDOC-01 rough-cut design doc. Phase 10's `docs/poc-capsule.md` "Tenant kubeconfig delivery contract" section cross-links to this doc's IRSA section as the EKS-translation forward-pointer (POC TokenRequest → EKS IRSA).
- **`Taskfile.yml`** — top-level task naming pattern. **Phase 10 expected to add NO new tasks** (per Claude's Discretion §"task surface extensions").

### External upstream references (informational; no edits)

- Capsule project — `https://capsule.clastix.io/`.
- capsule-proxy chart — `oci://ghcr.io/projectcapsule/charts/capsule-proxy:0.12.0`.
- capsule-proxy LIST filtering docs — `https://capsule.clastix.io/docs/proxy/` (researcher verifies LIST scope semantics during Plan 10-RESEARCH).
- Kubernetes TokenRequest API — `https://kubernetes.io/docs/reference/access-authn-authz/service-accounts-admin/#bound-service-account-tokens` (canonical short-lived SA token via `kubectl create token`).
- Kubernetes ServiceAccount best practices (k8s ≥1.24 deprecation of auto-mounted SA Secrets) — `https://kubernetes.io/docs/reference/access-authn-authz/service-accounts-admin/#legacy-serviceaccount-token-tracking-controller`.
- `kube-webhook-certgen` — Phase 8 D-08-11 Job's image (output Secret shape; researcher verifies during Plan 10-RESEARCH per D-10-06a).

### Open research questions (D-10-06a)

- **capsule-proxy chart's certgen Secret key shape** — Phase 10 D-10-06 reads `kubectl ... get secret capsule-proxy -o jsonpath='{.data.ca\.crt}'`. **Researcher MUST verify** the actual key name (`ca.crt`, `tls.crt` doubling as CA, or both) by inspecting the live Secret on spoke-capsule + cross-checking `kube-webhook-certgen` output schema. **This does NOT block planning** (the structural defense is unaffected; the question is purely about which jsonpath the script reads — fallback to `tls.crt` if `ca.crt` is absent is a 2-line `if`-branch).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- **`scripts/poc/capsule/create-cluster.sh`** — Phase 7 reference for `scripts/poc/capsule/`-rooted scripts. Phase 10's `issue-tenant-kubeconfig.sh` mirrors the head structure (preamble, `preflight-lib` source, idempotent control-flow comment block, fail-fast error style with hint).
- **`scripts/poc/capsule/fix-dns.sh`** — Phase 7 reference for short, single-purpose imperative scripts using `preflight-lib` ergonomics.
- **`scripts/lib/preflight-lib.sh`** — output helpers (`section`, `pass`, `warn`, `fail`, `info`, `have`). Phase 10's script sources this for v0.18 ergonomics.
- **`tests/bats/test_helper`** — shared bats loader pinning `REPO_ROOT`. Phase 10 bats files load without modification.
- **`tests/bats/poc-isolation-01-static.bats`** — Phase 7 P31 regression gate. Phase 10 verifier reruns verbatim; new script lives under `scripts/poc/capsule/` (excluded from lint set).
- **`tests/fixtures/gitleaks/synthetic-kubeconfig.yaml`** — Phase 7 D-14 positive fixture; rule fires on this file's `kind: Config` + `token:` shape; allowlisted in `.gitleaks.toml`. Phase 10's PROXY-03 synthetic-fixture bats may reuse this or add a tenant-flavored variant (planner discretion).
- **`.gitignore`** + **`.gitleaks.toml`** — Phase 7 D-14 leak defenses. Phase 10 does NOT modify; regression-gate-asserts verbatim.
- **`docs/poc-capsule.md`** — Phase 7 host-restart-recovery doc. Phase 10 appends "Tenant kubeconfig delivery contract" H2 section per PROXY-03.
- **`pocs/capsule/spoke/tenants/{alpha,bravo}/sa.yaml`** + **`tenant.yaml`** — Phase 9 D-09-02 per-tenant SA + Tenant CR. Phase 10 reads (does NOT modify) — the existing `gitops-reconciler` SA is the only `<owner>` Phase 10 supports.
- **Capsule operator's auto-injected RoleBindings on Tenant owners (default clusterRoles: `[admin, capsule-namespace-deleter]`)** — Phase 9 D-09-02 / `pocs/capsule/spoke/tenants/alpha/sa.yaml` comment: "no additional RoleBinding needed". Phase 10's TokenRequest token inherits these via the SA owner registration in Tenant alpha's spec.owners[]; proxy LIST filtering applies on top.

### Established Patterns

- **`scripts/poc/capsule/`-rooted scripts** — Phase 7 D-12 / P31 isolation contract. Phase 10's `issue-tenant-kubeconfig.sh` lives at `scripts/poc/capsule/issue-tenant-kubeconfig.sh`. NEVER invoked by `task rebuild`; never referenced from v0.18 scripts (regression-gated by `poc-isolation-01-static.bats`).
- **Bash strict-mode + `REPO_ROOT`/`SCRIPT_DIR` pinning** — Phase 10's script adopts identical preamble (every existing v0.18 + Phase 7 script).
- **`preflight-lib` ergonomics** — section/pass/warn/fail/info/have helpers. Phase 10's script sources these. Tool-gate uses `have kubectl k3d`; failures use `fail` with multi-line hints; info-level state changes use `info`.
- **Bats static-contract test naming `<area>-<NN>-{static|live}-<topic>.bats`** + `setup() { REPO_ROOT=...; }` + `grep -F --` for literal text matches + yq-based assertions per WR-01..04 hardening (Phase 8). Phase 10 suggested bats names (planner reshapes file partition without re-asking):
  - `proxy-01-static-script.bats` (PROXY-01 — script shape, args, literals).
  - `proxy-02-static-leak-defenses.bats` (PROXY-03 — gitignore + gitleaks regression-gates).
  - `proxy-03-static-doc.bats` (PROXY-03 — `docs/poc-capsule.md` "Tenant kubeconfig delivery contract" section).
  - `proxy-04-live-issue.bats` (PROXY-01 — live script invocation, kubeconfig shape).
  - `proxy-05-live-list-filter.bats` (PROXY-02 — proxy LIST + direct apiserver falsifier).
  - `proxy-06-live-fixture.bats` (PROXY-03 — synthetic fixture rule fires).
  - `proxy-07-live-regression.bats` (Phase 7 P31 + Phase 8 CAP-01..03 + Phase 9 TEN-01..06 + ADR-004 inheritance).
- **Wave 0 RED bats scaffold** (Phase 7 / 8 / 9 D-09-08 pattern). Phase 10 Plan 10-00 mirrors. Already-validated.
- **POC isolation regression** (Phase 7 P31 contract). Phase 10 verifier reruns `tests/bats/poc-isolation-01-static.bats` to confirm new script + doc edits did NOT introduce `spoke-capsule` mentions in v0.18 scripts.
- **TmpDir-rooted ephemeral artifacts** (Phase 7 D-14). Phase 10's `--write-to <path>` enforces `${TMPDIR:-/tmp}/karyon-tenants/` prefix; bats falsifier kubeconfig (D-10-08) uses `mktemp -d` rooted at the same.

### Integration Points

- **`scripts/poc/capsule/issue-tenant-kubeconfig.sh`** (NEW) — net-new script. Sources `preflight-lib`, gates `kubectl`/`k3d` presence, validates Tenant + SA exist on spoke, mints TokenRequest token, reads CA cert from in-cluster Secret, emits kubeconfig YAML to stdout (or `--write-to` tmpdir-rooted path). No outer-K changes.
- **`docs/poc-capsule.md`** — appended "Tenant kubeconfig delivery contract" H2 section. Cross-links to: D-14 leak defenses, CAP-02 NodePort, D-09-02 per-tenant SA, `docs/capsule-on-eks.md` IRSA section. Frontmatter `scope:` line updated to remove the Phase 10 forward-pointer (now satisfied).
- **No Taskfile.yml extensions in Phase 10** (per Claude's Discretion §"task surface extensions"). The script is invoked directly: `bash scripts/poc/capsule/issue-tenant-kubeconfig.sh ...`.
- **No `task preflight` extensions in Phase 10.** Phase 7 already locked NodePort 30443 reservation (CAPCLU-04 / D-15). Phase 10 inherits.
- **No `.gitignore` / `.gitleaks.toml` extensions in Phase 10.** Phase 7 D-14 closed the kubeconfig leak surface; the existing rule covers Phase 10 output shape verbatim.
- **No outer Flux Kustomization changes in Phase 10.** D-10-05 defers the tenant inner K kubeConfig swap; `pocs/capsule/tenants/{alpha,bravo}.yaml` and `clusters/hub-flux/pocs/capsule{,-spoke}.yaml` remain unchanged.
- **`tests/bats/proxy-*.bats`** (NEW) — Phase 10 bats files per D-10-09. Plan 10-00 lands all RED; Plan 10-01 lands the script + doc to make them green; Plan 10-02 verifier confirms regression of prior phases.
- **`tests/fixtures/gitleaks/synthetic-tenant-kubeconfig.yaml`** (OPTIONAL — planner discretion per D-10-09 / Claude's Discretion). If added, MUST be allowlisted in `.gitleaks.toml` `[[rules.allowlist.paths]]` to avoid blocking commits. The existing `synthetic-kubeconfig.yaml` is generic enough — no new fixture required for Phase 10's bats coverage.

### Risks (carried from STATE.md Blockers/Concerns + Phase 9 close-out)

- **Phase 9 close-out residual** (`passed_with_overrides` 4 D-08-13 push-gate-deferred) — Phase 10 inherits the push-gate deferral. NO `git push` during Phase 10 execution; commits remain local-only. Phase 11 VAL-05 owns the first push event.
- **D-10-06a research item — capsule-proxy certgen Secret key shape** — script reads `ca.crt` but may need to fall back to `tls.crt`. Mitigation: script implements both jsonpath fallbacks; bats verifies SECRET key shape at live-test time.
- **Proxy LIST filtering scope (research)** — capsule-proxy v0.12.0's LIST filtering covers Namespace + select tenant-relevant resources, but cluster-scoped kinds (ClusterRole, ClusterRoleBinding, etc.) may have different proxy behavior (filtered? rejected? passthrough?). PROXY-02 verifier asserts ONLY namespace-list filtering (the ROADMAP-literal acceptance criterion); other-kind LIST behavior is Phase 11 N1–N12's concern.

</code_context>

<specifics>
## Specific Ideas

- **Script preamble cite anchor** — Phase 10's `issue-tenant-kubeconfig.sh` head comment block cites PROXY-01 + D-10-01 (TokenRequest) + D-10-03 (`<owner>` semantics) + D-10-06 (TLS embed) + P31 isolation + ADR-004. Mirrors `scripts/poc/capsule/create-cluster.sh`'s head block (REQ + decision IDs + isolation contract + ADR cite).

- **Stdout / stderr channel separation** — `preflight-lib` log helpers (section/pass/info/etc.) write to stderr; the kubeconfig YAML is the ONLY content on stdout. Operator can redirect cleanly: `bash issue-tenant-kubeconfig.sh alpha gitops-reconciler 2>/dev/null > /tmp/alpha.kubeconfig` produces a pure-YAML file. Bats verifies this contract via `run` capturing stdout vs `stderr` separately.

- **`--write-to <path>` realpath check** — Use `realpath -m <path>` (canonicalize but don't require existence). Compare to `realpath -m "${TMPDIR:-/tmp}/karyon-tenants/"` prefix. If not a prefix → fail. If prefix → mkdir -p the parent and write. This avoids symlink-traversal escapes like `--write-to /tmp/karyon-tenants/../../../etc/passwd`.

- **JWT exp claim verification (live bats)** — `kubectl create token` returns a JWT string. Bats can decode the payload (`echo $TOKEN | cut -d. -f2 | base64 -d 2>/dev/null | jq .exp`) and assert `exp - iat ≈ DURATION` within tolerance. This is a stronger TokenRequest verification than just "token is non-empty".

- **PROXY-02 LIST count assertion (planner shape)** — Phase 9 TEN-02 creates `alpha-app1` and `bravo-app1`; Phase 9 verifier leaves them in place. Phase 10 PROXY-02 live test against the alpha kubeconfig should see at least: `tenant-alpha`, `alpha-app1`. Direct apiserver should see: kube-system, kube-public, kube-node-lease, default, capsule-system, flux-system (if any flux-system on spoke from previous Phase 8 invariant check), tenant-alpha, tenant-bravo, alpha-app1, bravo-app1 → ≥10 ns. Numerical assertion: `proxy_count < direct_count` is the Nyquist-shape; loosely `proxy_count ≤ 5` and `direct_count ≥ 8` is more robust.

- **Tenant-CR existence pre-check robustness** — `kubectl get tenant <tenant>` may return non-zero with informative error if Tenant CR doesn't exist on spoke. Wrap with `if ! kubectl ... 2>/dev/null; then fail "..."; fi` for clean fail-fast UX.

- **`--duration` validation** — k3s default `--service-account-max-token-expiration` is 24h. If operator passes `--duration=48h`, kubectl will silently clamp; the issued token is shorter than requested. Bats verifies clamp behavior is documented (warn message in the script when duration > 24h: `info "duration ${DURATION} may be clamped by apiserver to 24h (k3s default --service-account-max-token-expiration)"`). NOT fail — clamp is acceptable; warn is the right user signal.

- **Kubeconfig template** — script writes the kubeconfig via heredoc (NOT yq-build) for clarity; heredoc includes parameterized values for tenant + owner + token + ca.crt. Mirrors `scripts/poc/capsule/create-cluster.sh`'s use of heredoc for k3d cluster create command. yq-based construction adds a yq dependency to the script's preflight; heredoc keeps it minimal.

- **Verifier observation source-of-truth** — Phase 10 PROXY-02 LIST observation reads `kubectl --kubeconfig=<issued> get namespaces -o name | sort`. Falsifier reads `kubectl --kubeconfig=<direct-tmpfile> get namespaces -o name | sort`. The diff between sets is THE evidence of proxy filtering. Bats `run`-captures both, asserts `wc -l` of proxy < `wc -l` of direct.

</specifics>

<deferred>
## Deferred Ideas

True deferrals to later phases (already locked at milestone-open or by ROADMAP / REQUIREMENTS un-bundling, restated for plan-side awareness):

- **Phase 9 D-09-03 forward-pointer — tenant inner K kubeConfig source swap from `spoke-capsule-kubeconfig` to per-tenant proxy-kubeconfigs.** Phase 9 anticipated Phase 10 modifying `spec.kubeConfig.secretRef.name` in `pocs/capsule/tenants/{alpha,bravo}.yaml` to per-tenant proxy-kubeconfigs. **Deferred** out of Phase 10 scope per D-10-05. Naturally absorbed by Phase 12 (capsule-addon-fluxcd) if ADR-008 outcome ∈ {adopt, defer} — the addon auto-creates per-tenant SA + kubeconfig Secret, and that addon-managed Secret IS the swap. If ADR-008 rejects/replaces Capsule, the manual swap remains future work (post-v0.19, depending on the replacement architecture). Phase 9 D-09-03 framing preserved unchanged; downstream readers see consistent framing across 09-CONTEXT.md and 10-CONTEXT.md.
- **Negative RBAC bats N1–N12** → **Phase 11** (VAL-01). Phase 10 verifier asserts only POSITIVE-direction shape (PROXY-01..03 contracts). Phase 11 owns cross-tenant denials, escalation denials, namespace-prefix violations, etc.
- **Capsule webhook failure / recoverable mode (`task fail-capsule-webhook`)** → **Phase 11** (VAL-02).
- **Clean teardown (`task destroy-poc capsule` ordered teardown)** → **Phase 11** (VAL-03). Phase 10 leaves all tenant + namespace state in place for Phase 11 to exercise teardown.
- **`task rebuild` SLO regression test (< 230s with spoke-capsule alive)** → **Phase 11** (VAL-04). Phase 10 P31 isolation gate (static bats) is sufficient for Phase 10.
- **One-shot history gitleaks scan post-Phase-10 first push** → **Phase 11** (VAL-05) — Phase 8 D-08-13 push-gate deferral remains in force; Phase 10 commits remain local-only (no push).
- **Graduation ADR-008** → **Phase 11** (VAL-06).
- **`capsule-addon-fluxcd v0.2.3` trial** → **Phase 12** (OPTIONAL — gated on ADR-008 outcome ∈ {adopt, defer}). Absorbs the D-10-05 deferred swap organically.
- **Multi-SA-per-tenant pattern** — Phase 10 `<owner>` arg accepts only the existing `gitops-reconciler` per D-10-03. If Phase 12 / future work introduces additional SAs per tenant (e.g., per-developer SAs), the script's existing future-proof slot accepts them without code changes — but the Tenant CR mutation (adding owners[] entries) is the future-phase concern.
- **`task issue-tenant-kubeconfig` wrapper** — per Claude's Discretion default of "no new task targets". If a future phase needs `task` ergonomics, the wrapper is trivial; Phase 10 sticks to bare script invocation.
- **JSON output mode for the script** — if a future phase / consumer needs structured output, a `--output json` flag can be added. Phase 10 ships YAML-only (the kubeconfig spec is YAML).
- **Cert-rotation handling** — capsule-proxy chart's certgen Job rotates the cert on chart upgrade; Phase 10 D-10-06 live-reads the cert at script-time, so the issued kubeconfig is always against the current cert. No explicit rotation handling needed in Phase 10. Future work: if cert-manager is adopted (post-v0.19 milestone), the cert source changes from kube-webhook-certgen output to cert-manager-managed Secret — the script's jsonpath would shift accordingly.
- **HA Capsule, OIDC, multi-spoke federation** → POST-v0.19 milestones (REQUIREMENTS.md "Future Requirements" + PROJECT.md Out-of-Scope).

### Reviewed Todos (not folded)

- **`2026-04-29-phase-7-gitleaks-planning-doc-allowlist.md` (`resolves_phase: 11`)** — Phase 11 (VAL-05) explicitly owns the one-shot history gitleaks scan post-Phase-10 first push. Phase 10 does NOT touch `.gitleaks.toml` or `.planning/phases/07-*` planning docs. Reviewing for awareness only — the gitleaks rule fires on planning-doc fixture quotes, not on Phase 10 artifacts. Todo will auto-close when `/gsd-execute-phase 11` runs (per `resolves_phase: 11`).
- **`2026-04-29-phase-7-hub-flux-observable-reconcile.md` (`resolves_phase: 8`)** — Phase 8 close-out reported `passed_with_overrides`; the carryover was folded into Phase 8 D-08-09 live bats. Phase 10 does not exercise this surface (no outer Flux Kustomization changes per D-10-05). Todo will auto-close on Phase 11 push (re-firing on first observable post-Phase-9 reconcile, OR via manual close-out gate during Phase 11 VAL-05).

### Out-of-band ideas surfaced during analysis (NOT in current scope)

- None — analysis stayed within Phase 10 scope. The deferral of D-09-03 forward-pointer is a deliberate ROADMAP-literal scope guardrail (PROXY-01..03 verbatim), not a deferral discovered during this discussion.

</deferred>

---

*Phase: 10-tenant-owner-kubeconfigs-capsule-proxy-round-trip*
*Context gathered: 2026-05-05*
*Mode: default (interactive — 4 gray areas discussed across 9 turns; 2 follow-up turns per area on average; user selected all 4 areas via initial multi-select)*
