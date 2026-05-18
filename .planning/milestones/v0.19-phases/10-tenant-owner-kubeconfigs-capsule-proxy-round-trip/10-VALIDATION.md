---
phase: 10
slug: tenant-owner-kubeconfigs-capsule-proxy-round-trip
status: final
nyquist_compliant: true
wave_0_complete: true
created: 2026-05-05
finalized: 2026-05-11
finalized_evidence: "Plan 10-00 Wave 0 RED bats scaffold (7 bats files; 45 @tests covering PROXY-01..03 contracts; Pitfall 10-P2/P3/P5 corrections applied) became GREEN over Plans 10-01..10-02. 10-VERIFICATION.md reports status: passed_with_overrides with 3/3 must-haves verified; 44/45 Phase 10 @tests GREEN at phase close (1 RED-by-design from Phase 8 BLOCKER G-04 inheritance); push_gate_disposition: deferred-to-Phase-11-VAL-05. Post-fix evidence: D-08-13 push-gate-deferred items resolved by Plan 11-07 closeout at HEAD 8415ab66 (per 11-07-SUMMARY.md). Two Rule 3 deviations documented in 10-VERIFICATION.md Notable Observations (CapsuleConfiguration userGroups patch + tenant home namespace ownership) carried to Plan 11 VAL-05 and persisted. Nyquist sampling rate satisfied: every REQ-ID (PROXY-01..03) has at least one bats falsifier in the Wave-0 scaffold turned GREEN."
---

# Phase 10 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Source: `10-RESEARCH.md` §"Validation Architecture" (lines 877-928).

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bats-core 1.11.0 (already pinned via asdf) |
| **Config file** | `tests/bats/test_helper.bash` (Phase 1 v0.18; provides `REPO_ROOT`, `IMAGES_DIR`, `require_live`, `require_live_destructive`) |
| **Quick run command** | `bats tests/bats/proxy-*.bats` |
| **Full suite command** | `bats tests/bats/` |
| **Estimated runtime** | ~30s quick, ~3min wave (proxy + poc-isolation + capsule-install + tenants), ~5min full suite |

---

## Sampling Rate

- **After every task commit:** Run `bats tests/bats/proxy-*.bats`
- **After every plan wave:** Run `bats tests/bats/proxy-*.bats tests/bats/poc-*.bats tests/bats/capsule-install-*.bats tests/bats/tenants-*.bats`
- **Before `/gsd-verify-work`:** Full suite must be green (`bats tests/bats/`)
- **Max feedback latency:** 30 seconds per-task; 3 minutes per-wave

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 10-00-01 | 00 | 0 | PROXY-01 | T-10-01 (token leak) | Script literals + arg shape locked into static bats before script lands | static | `bats tests/bats/proxy-01-static-script.bats` | ❌ Wave 0 (NEW) | ⬜ pending |
| 10-00-02 | 00 | 0 | PROXY-03 | T-10-03 (kubeconfig in git) | Phase 7 D-14 leak defenses regression-gated verbatim | static | `bats tests/bats/proxy-02-static-leak-defenses.bats` | ❌ Wave 0 (NEW) | ⬜ pending |
| 10-00-03 | 00 | 0 | PROXY-03 | — | Doc section asserted by static lint before doc lands | static | `bats tests/bats/proxy-03-static-doc.bats` | ❌ Wave 0 (NEW) | ⬜ pending |
| 10-00-04 | 00 | 0 | PROXY-01 | T-10-01 / T-10-02 (symlink) | Live invocation shape — kubeconfig YAML + JWT exp claim | live | `bats tests/bats/proxy-04-live-issue.bats` | ❌ Wave 0 (NEW) | ⬜ pending |
| 10-00-05 | 00 | 0 | PROXY-02 | T-10-04 (cross-tenant) / T-10-05 (direct bypass) | Proxy LIST + 403-falsifier asserts proxy is the filter | live | `bats tests/bats/proxy-05-live-list-filter.bats` | ❌ Wave 0 (NEW) | ⬜ pending |
| 10-00-06 | 00 | 0 | PROXY-03 | T-10-03 | Synthetic fixture rule fires + gitignore catches | live | `bats tests/bats/proxy-06-live-fixture.bats` | ❌ Wave 0 (NEW) | ⬜ pending |
| 10-00-07 | 00 | 0 | INHERITED (P31, CAP-01..03, TEN-01..06, ADR-004) | — | Prior-phase invariants regression-gated by Phase 10 verifier | static + live | `bats tests/bats/proxy-07-live-regression.bats` | ❌ Wave 0 (NEW) | ⬜ pending |
| 10-01-01 | 01 | 1 | PROXY-01 | T-10-01 / T-10-02 / T-10-08 | `scripts/poc/capsule/issue-tenant-kubeconfig.sh` lands; static bats turn green | static | `bats tests/bats/proxy-01-static-script.bats` (Wave 0 dependency) | ✅ after task | ⬜ pending |
| 10-01-02 | 01 | 1 | PROXY-03 | — | `docs/poc-capsule.md` "Tenant kubeconfig delivery contract" section appended; static doc bats turns green | static | `bats tests/bats/proxy-03-static-doc.bats` (Wave 0 dependency) | ✅ after task | ⬜ pending |
| 10-01-03 | 01 | 1 | PROXY-01 | — | Live PROXY-01 issuance turns green (alpha + bravo, both `--write-to` accepted/rejected) | live | `bats tests/bats/proxy-04-live-issue.bats` (Wave 0 dependency) | ✅ after task | ⬜ pending |
| 10-02-01 | 02 | 2 | PROXY-02 | T-10-04 / T-10-05 | capsule-proxy live install (Plan 09-04 suspend+apply pattern); proxy LIST + falsifier turn green | live | `bats tests/bats/proxy-05-live-list-filter.bats` (Wave 0 dependency) | ✅ after task | ⬜ pending |
| 10-02-02 | 02 | 2 | PROXY-03 | T-10-03 | Synthetic fixture live regression turns green (gitignore exit 0 + gitleaks non-zero) | live | `bats tests/bats/proxy-06-live-fixture.bats` (Wave 0 dependency) | ✅ after task | ⬜ pending |
| 10-02-03 | 02 | 2 | INHERITED | — | Phase 7+8+9 invariant suite reruns clean | static + live | `bats tests/bats/proxy-07-live-regression.bats` (Wave 0 dependency) | ✅ after task | ⬜ pending |
| 10-02-04 | 02 | 2 | All | — | `10-VERIFICATION.md` written; phase gate passes | full suite | `bats tests/bats/` | ✅ after task | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `tests/bats/proxy-01-static-script.bats` — covers PROXY-01 (script shape, args, literals)
- [ ] `tests/bats/proxy-02-static-leak-defenses.bats` — covers PROXY-03 (gitignore + gitleaks regression-gates verbatim)
- [ ] `tests/bats/proxy-03-static-doc.bats` — covers PROXY-03 (`docs/poc-capsule.md` section + cross-links)
- [ ] `tests/bats/proxy-04-live-issue.bats` — covers PROXY-01 (live invocation, kubeconfig YAML shape, JWT exp decode)
- [ ] `tests/bats/proxy-05-live-list-filter.bats` — covers PROXY-02 (proxy LIST + 403 falsifier — corrected per Pitfall 10-P2)
- [ ] `tests/bats/proxy-06-live-fixture.bats` — covers PROXY-03 (synthetic fixture rule fires + gitignore catches)
- [ ] `tests/bats/proxy-07-live-regression.bats` — Phase 7 P31 + Phase 8 CAP-01..03 + Phase 9 TEN-01..06 + ADR-004 inheritance reruns
- [x] No new `tests/fixtures/` needed (reuse Phase 7 `tests/fixtures/gitleaks/synthetic-kubeconfig.yaml`)
- [x] Framework install: not needed (bats 1.11.0 already pinned)

**Naming sanity-check:** Phase 10's `proxy-` prefix conflicts with NONE of the existing 60+ bats files (verified — `ls tests/bats/ | grep -F 'proxy-'` returns no matches). Phase 8 used `capsule-install-` for proxy-related tests (e.g., `capsule-install-08-live-proxy-reachable.bats`); Phase 10's `proxy-` prefix is distinct.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| capsule-proxy chart install on `spoke-capsule` (Plan 10-02 prerequisite) | PROXY-02 | D-08-13 push-gate deferred to Phase 11 VAL-05 — proxy is NOT yet installed live; Plan 10-02 must use Phase 9 Plan 09-04's suspend+apply pattern (suspend `flux-system` Kustomization, manually apply rendered chart, validate, resume Kustomization) | See `10-RESEARCH.md` §"Pattern A4 — suspend+apply staging" |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references (7 new bats files)
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s per-task / 3min per-wave
- [ ] `nyquist_compliant: true` set in frontmatter once Wave 0 RED bats land

**Approval:** pending
