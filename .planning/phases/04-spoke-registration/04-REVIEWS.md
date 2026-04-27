---
phase: 4
reviewers: [codex]
reviewed_at: 2026-04-27T17:44:42Z
plans_reviewed:
  - 04-01-PLAN.md
  - 04-02-PLAN.md
  - 04-03-PLAN.md
  - 04-04-PLAN.md
  - 04-05-PLAN.md
---

# Cross-AI Plan Review — Phase 4

## Codex Review

## Summary

The plan set is unusually thorough and has the right overall architecture: static contracts first, manifests second, orchestration script third, wire-up fourth, live reconciliation last. The research adjustments are mostly carried through, especially the D-14 wget pivot and the P18 reframe. That said, I would not execute these plans unchanged. The biggest problems are not conceptual; they are contradictions between the intended guarantees and what the script/tests actually prove, especially around idempotency, TLS/CA validation, token-safety greps, and live bats coverage.

## Strengths

- Strong layered validation model: static bats, in-script gates, post-push live bats.
- Correct P18 reframe: omitted `spec.kubeConfig` is the real silent fallback case, not a wrong `secretRef.key`.
- Good use of per-spoke Namespace + ConfigMap seed; it gives Flux something concrete and falsifiable to reconcile.
- Correct legacy SA-token direction for this lab scope; avoids expiring TokenRequest tokens.
- Namespace-first RBAC heredoc is important and correctly called out.
- Human push checkpoint is appropriate. The script should not auto-commit or auto-push.
- D-14 research is valuable: adapting to the actual kustomize-controller image is better than assuming `kubectl` exists.

## Concerns

- **HIGH: Script idempotency can skip too much.**
  The planned `register_spoke` skip path returns after Secret/decode/auth checks, before local file repair and before the full D-13 4-gate verification. Worse, the auth skip appears to use `/readyz`, which does not prove node access or cluster-admin. If a CRB is deleted but the token still authenticates, the script may skip and report success.

- **HIGH: SPOKE-06 TLS validation is overclaimed.**
  The wget probe uses `--no-check-certificate`, so it does not prove the embedded `certificate-authority-data` works. Post-push Flux `Ready=True` does prove TLS eventually, but the in-script gate does not. The plan should not claim the wget probe validates TLS.

- **HIGH: Token-safety tests are internally inconsistent.**
  The static test bans `printf` with token/kubeconfig variables, but the script intentionally uses `printf '%s\n' "$kubeconfig_yaml"` to pipe the kubeconfig into `kubectl create secret`. The regex also misses lowercase `token` / `kubeconfig_yaml`, while banning uppercase names. This is both too broad and too easy to evade accidentally.

- **HIGH: The `git push` negative grep will likely fail on the script's own info message.**
  The test says info-line text is exempt, but the grep only filters comments. A multiline `info "...\n git push\n..."` can still match as a command-looking source line.

- **MEDIUM: Live bats only runs the D-14 in-pod probe for `spoke-ml`.**
  ROADMAP success criterion #3 is for both spokes. `spoke-apps` needs matching `/readyz` and `/api/v1/nodes` probes.

- **MEDIUM: Live bats does not prove the hub Secret kubeconfig content deeply enough.**
  It checks `data.value.yaml` is non-empty, but should decode it and assert server URL, non-empty token, non-empty CA, and ideally CA equality with the spoke SA-token Secret CA.

- **MEDIUM: The unpushed-change guard is incomplete.**
  `git rev-list origin/main..HEAD -- paths` detects committed-but-unpushed work, not uncommitted changes. In the common pre-commit state, the live suite will not skip as intended.

- **MEDIUM: Static bats grep comments/literals, not YAML semantics.**
  Several tests can pass if required strings appear in comments. For Kustomization shape, use `yq` for `spec.kubeConfig.secretRef.name`, `key`, and `path`.

- **MEDIUM: Plan 04-02 and Plan 04-03 both own the same YAML generation.**
  Because 04-02 pre-creates the files, the script's write paths are mostly untested in live execution. Either make the manifests the source of truth and stop claiming the script writes them, or have the script verify existing files match canonical content.

- **MEDIUM: Wave dependency is leaky.**
  04-02 has no dependency on 04-01 but references the 04-01 bats suite in verification. If Wave 1 runs in parallel, that verification can fail for scheduling reasons.

- **LOW: Some verification commands are brittle or impossible.**
  `bash -n` on `.bats` files is usually not a valid syntax check for raw bats syntax. Test-count and line-count assertions are also over-specified and likely to create noise.

- **LOW: Threat model over-relies on Phase 6 gitleaks before a Phase 4 push.**
  Phase 4's checkpoint pushes before Phase 6 in this plan set. Add an explicit ad-hoc secret scan before push.

## Suggestions

- Rework `register_spoke` so idempotency does not bypass verification. Always run the D-13 4 gates, or make the skip gate include node-name proof and RBAC proof. Also ensure local files are repaired or verified even when runtime Secrets already exist.

- Add an in-pod TLS check using `openssl s_client -verify_return_error -verify_hostname k3d-<spoke>-server-0 -CAfile <decoded CA>`, since the image has `openssl`. Keep wget for API auth if desired.

- Change token-safety tests to allow the exact safe pipe into `kubectl create secret --from-file=value.yaml=/dev/stdin`, while banning helper/log output, `set -x`, `tee`, `--from-literal`, and token-bearing command summaries.

- Fix the no-auto-push test so it detects actual shell commands, not literal text inside an `info` string. Simpler: drop the grep and rely on review plus the script body structure, or split the displayed command across quoted strings.

- Expand live bats to cover `spoke-apps` for `/readyz` and `/api/v1/nodes`.

- Decode hub kubeconfig Secrets in live bats and assert:
  - `.clusters[0].cluster.server == https://k3d-<spoke>-server-0:6443`
  - `.clusters[0].cluster.certificate-authority-data` is non-empty and base64-decodable
  - `.users[0].user.token` is non-empty
  - spoke token Secret type and annotation are correct

- Make the negative-proof symmetric:
  - `karyon-spoke-ml` ConfigMap exists on `spoke-ml`, not hub, not `spoke-apps`
  - `karyon-spoke-apps` ConfigMap exists on `spoke-apps`, not hub, not `spoke-ml`

- Replace important static greps over YAML with `yq` assertions.

- Either add `depends_on: [04-01]` to 04-02 or remove 04-01 bats verification from 04-02.

- Add a pre-push checkpoint command such as `git diff --cached` plus `gitleaks detect --no-git` if available, or a targeted grep for kubeconfig/token-looking material.

## Risk Assessment

**Overall risk: HIGH before revisions, MEDIUM after revisions.**

The architecture is sound, and the research is good. The remaining risk is in execution fidelity: the script can currently skip verification on rerun, TLS validation is not actually proven by the in-pod probe, and some tests claim stronger guarantees than they provide. For the highest-risk phase in the project, those gaps matter. Fix the idempotency gate, add real CA validation or clearly move TLS proof to post-push Flux readiness, and tighten the bats tests around actual kubeconfig content. Then this becomes a strong, defensible plan set.

---

## Consensus Summary

*Single reviewer (Codex) — no cross-reviewer consensus to synthesize.*

### Top Concerns (all from Codex; ranked by severity)

1. **Idempotency skip-gate bypasses verification** (HIGH) — `register_spoke` early-returns on `/readyz` auth, skipping the full D-13 4-gate check. A deleted CRB with a still-valid token would slip through.
2. **SPOKE-06 TLS overclaimed** (HIGH) — wget `--no-check-certificate` does not validate `certificate-authority-data`. Either add `openssl s_client` check (image ships openssl) or scope TLS proof to post-push Flux readiness.
3. **Token-safety static tests are inconsistent** (HIGH) — global `printf` ban collides with the legitimate `printf "%s\n" "$kubeconfig_yaml" | kubectl create secret …` pipe; regex case-sensitivity also leaves lowercase variable names unbanned.
4. **`git push` negative grep is fragile** (HIGH) — info-line exemption only filters comments; a multiline `info "...git push..."` can match as a command line.
5. **04-02 ↔ 04-03 ownership overlap** (MEDIUM) — both plans generate the same hub-side Kustomization YAML. Pick one source of truth.
6. **Live bats coverage gaps** (MEDIUM) — `spoke-apps` D-14 probe missing; hub Secret content not deeply asserted; unpushed-change guard misses uncommitted state.
7. **Wave-1 internal dependency** (MEDIUM) — 04-02 references 04-01 bats but lacks the `depends_on`.

### Actions to Consider Before Execution

- Tighten idempotency gate to always run D-13 4-gates (or include node-name + RBAC proof in the skip path).
- Add in-pod `openssl s_client -verify_return_error -CAfile <decoded CA>` for genuine TLS proof.
- Allow the safe `printf | kubectl create secret …` pipe in the token-safety regex; ban `set -x`, `tee`, `--from-literal`, and helper/log output instead.
- Expand live bats to cover both spokes symmetrically and decode `data.value.yaml` for full content assertions.
- Add `depends_on: [04-01]` to 04-02 or drop the 04-01 bats reference from 04-02 verification.
- Resolve 04-02/04-03 YAML-generation overlap (manifests-as-source-of-truth or script verifies existing files).
- Add a pre-push secret scan to the Wave-4 checkpoint (gitleaks if available, or a targeted grep).
