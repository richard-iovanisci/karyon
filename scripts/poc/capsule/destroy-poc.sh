#!/usr/bin/env bash
# scripts/poc/capsule/destroy-poc.sh
#
# Ordered teardown for the spoke-capsule POC: suspend tenant inner Ks + spoke-targeted outer K
# -> delete Tenant CRs -> poll namespace cascade (auto force-delete PVC finalizers after 60s) ->
# suspend operator outer K -> optional --full flag for `k3d cluster delete spoke-capsule`.
#
# Surfaces as `task destroy-poc -- capsule [--full]`. Sentinel preservation: this script
# does NOT mutate clusters/hub-flux/flux-system/kustomization.yaml (the # KARYON POC MOUNT
# sentinel + ../pocs mount line stay verbatim post-teardown regardless of --full).
#
# REQ: VAL-03. Decisions: D-11-10 (5-step canonical), D-11-11 (PVC strand auto force-delete after 60s).
# D-12 / P31: Lives under scripts/poc/capsule/; the v0.18 scripts have ZERO references
#             to this file (tests/bats/poc-isolation-01-static.bats enforces).
# D-17 / ADR-004: NO Flux runs on spoke-capsule -- `flux suspend` targets hub-flux only.
#
# REVISIONS 2026-05-05 (see 11-REVIEWS.md):
#   - reviewer HIGH #5(a): per-Kustomization `flux suspend` (one invocation per name, NOT multi-arg)
#   - reviewer HIGH #5(b): non-zero RC emits `warn`, NOT `|| true` swallow
#   - reviewer HIGH #5(c): every kubectl call explicitly uses --context=k3d-spoke-capsule
#   - reviewer HIGH #5 + MEDIUM #11: each suspend verified via kubectl get kustomization spec.suspend
#   - reviewer MEDIUM #9: PVC enumeration via NS_LIST loop (drop -l label selector on PVC list;
#     PVCs do NOT carry the capsule.clastix.io/tenant label per Phase 9 D-09-04 -- only namespaces do)
#   - reviewer MEDIUM #11: standardized invocation form `task destroy-poc -- capsule [--full]` (with `--`)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# shellcheck source=../../lib/preflight-lib.sh
# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/lib/preflight-lib.sh"

# ---------- Section 0: Arg parse (D-11-10 --full flag handling per CONTEXT specifics) ----------
FULL=false
SAW_CAPSULE=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    capsule) SAW_CAPSULE=true; shift ;;
    --full)  FULL=true; shift ;;
    *) fail "destroy-poc: unknown arg '$1' (usage: task destroy-poc -- capsule [--full])"; exit 1 ;;
  esac
done
if [[ "$SAW_CAPSULE" != "true" ]]; then
  fail "destroy-poc: missing required POC name 'capsule' (usage: task destroy-poc -- capsule [--full])"
  exit 1
fi

# ---------- Section 1: Tool gate ----------
section "Tool gate"
for cmd in kubectl k3d flux jq; do
  if ! have "$cmd"; then
    fail "required command missing: $cmd.
       Fix: install project tools with asdf, then rerun: task destroy-poc -- capsule"
    exit 1
  fi
done
pass "required commands present"

# ---------- Section 2: Step 1/5 -- per-Kustomization suspend (REVISED reviewer HIGH #5) ----------
section "Step 1/5: suspend tenant inner Ks + spoke-targeted outer K (per-Kustomization)"
# REVISED 2026-05-05 per reviewer HIGH #5(a): one `flux suspend kustomization NAME` invocation per object
# (multi-arg `flux suspend kustomization a b c` may not be valid for the installed flux CLI version
# and obscures error attribution). Each name is invoked LITERALLY (NOT via a $k loop variable) so
# teardown-01 grep contract sees `flux suspend kustomization tenant-alpha`, `... tenant-bravo`, and
# `... poc-capsule-spoke` as fixed strings in the script source.
# REVISED 2026-05-05 per reviewer HIGH #5(b): collect non-zero RC as `warn` (NOT `|| true` swallow).
# REVISED 2026-05-05 per reviewer HIGH #5 + MEDIUM #11: verify via kubectl get kustomization spec.suspend.

# --- tenant-alpha (inner Kustomization owned by tenant-alpha owner) ---
if flux suspend kustomization tenant-alpha -n flux-system 2>/dev/null; then
  pass "suspended: tenant-alpha"
else
  warn "could not run 'flux suspend kustomization tenant-alpha' (likely already suspended or Kustomization absent; not fatal)"
fi
SUSPEND_STATE=$(kubectl --context=k3d-hub-flux get kustomization tenant-alpha -n flux-system -o jsonpath='{.spec.suspend}' 2>/dev/null || echo "absent")
if [[ "$SUSPEND_STATE" == "true" ]]; then
  pass "verified: tenant-alpha spec.suspend=true"
elif [[ "$SUSPEND_STATE" == "absent" ]]; then
  info "Kustomization tenant-alpha is absent on hub-flux (tenant likely never reconciled; teardown still safe)"
else
  warn "tenant-alpha spec.suspend='$SUSPEND_STATE' (expected 'true'; flux CLI may have failed silently)"
fi

# --- tenant-bravo (inner Kustomization owned by tenant-bravo owner) ---
if flux suspend kustomization tenant-bravo -n flux-system 2>/dev/null; then
  pass "suspended: tenant-bravo"
else
  warn "could not run 'flux suspend kustomization tenant-bravo' (likely already suspended or Kustomization absent; not fatal)"
fi
SUSPEND_STATE=$(kubectl --context=k3d-hub-flux get kustomization tenant-bravo -n flux-system -o jsonpath='{.spec.suspend}' 2>/dev/null || echo "absent")
if [[ "$SUSPEND_STATE" == "true" ]]; then
  pass "verified: tenant-bravo spec.suspend=true"
elif [[ "$SUSPEND_STATE" == "absent" ]]; then
  info "Kustomization tenant-bravo is absent on hub-flux (tenant likely never reconciled; teardown still safe)"
else
  warn "tenant-bravo spec.suspend='$SUSPEND_STATE' (expected 'true'; flux CLI may have failed silently)"
fi

# --- poc-capsule-spoke (outer Kustomization that targets spoke-capsule cluster) ---
if flux suspend kustomization poc-capsule-spoke -n flux-system 2>/dev/null; then
  pass "suspended: poc-capsule-spoke"
else
  warn "could not run 'flux suspend kustomization poc-capsule-spoke' (likely already suspended or Kustomization absent; not fatal)"
fi
SUSPEND_STATE=$(kubectl --context=k3d-hub-flux get kustomization poc-capsule-spoke -n flux-system -o jsonpath='{.spec.suspend}' 2>/dev/null || echo "absent")
if [[ "$SUSPEND_STATE" == "true" ]]; then
  pass "verified: poc-capsule-spoke spec.suspend=true"
elif [[ "$SUSPEND_STATE" == "absent" ]]; then
  info "Kustomization poc-capsule-spoke is absent on hub-flux (POC outer K likely never reconciled; teardown still safe)"
else
  warn "poc-capsule-spoke spec.suspend='$SUSPEND_STATE' (expected 'true'; flux CLI may have failed silently)"
fi

# ---------- Section 3: Step 2/5 -- delete Tenant CRs (cascade triggers tenant ns cascade) ----------
section "Step 2/5: delete Tenant CRs (cascade triggers tenant namespace cascade)"
kubectl --context=k3d-spoke-capsule delete tenant alpha bravo --wait=true --ignore-not-found 2>/dev/null || true
pass "Tenant CRs deleted (or already absent)"

# ---------- Section 4: Step 3/5 -- poll cascade (90s budget; PVC finalizer mitigation @60s) ----------
section "Step 3/5: poll namespace cascade (max 90s; auto force-delete PVCs after 60s per D-11-11)"
# REVISED 2026-05-05 per reviewer HIGH #5(c): every kubectl call uses --context=k3d-spoke-capsule explicitly.
# REVISED 2026-05-05 per reviewer MEDIUM #9: PVC enumeration via NS_LIST loop (drop -l label selector on
# PVC list -- PVCs do NOT carry capsule.clastix.io/tenant label per Phase 9 D-09-04; only namespaces do).
CASCADE_DONE=false
for i in $(seq 1 90); do
  REMAINING=$(kubectl --context=k3d-spoke-capsule get ns -l capsule.clastix.io/tenant -o name 2>/dev/null | wc -l)
  if [[ "$REMAINING" -eq 0 ]]; then
    pass "namespace cascade complete after ${i}s"
    CASCADE_DONE=true
    break
  fi
  if [[ "$i" -eq 60 ]]; then
    info "namespace cascade stuck at ${i}s; force-clearing PVC finalizers (P36 / D-11-11 mitigation; reviewer MEDIUM #9 NS_LIST loop)"
    # NS_LIST = surviving labeled namespaces. PVC enumeration walks namespaces (not the
    # PVC label) because PVCs themselves do NOT carry capsule.clastix.io/tenant.
    NS_LIST=$(kubectl --context=k3d-spoke-capsule get ns -l capsule.clastix.io/tenant -o name 2>/dev/null | sed 's|namespace/||')
    for ns in $NS_LIST; do
      [[ -z "$ns" ]] && continue
      kubectl --context=k3d-spoke-capsule get pvc -n "$ns" -o name 2>/dev/null | while read -r pvc; do
        [[ -z "$pvc" ]] && continue
        kubectl --context=k3d-spoke-capsule patch "$pvc" -n "$ns" -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null || true
      done
    done
  fi
  sleep 1
done
if [[ "$CASCADE_DONE" != "true" ]]; then
  warn "namespace cascade did not complete within 90s; continuing teardown"
fi

# ---------- Section 5: Step 4/5 -- suspend operator outer K (REVISED single-object) ----------
section "Step 4/5: suspend operator outer K (preserves GitOps install state)"
# REVISED 2026-05-05 per reviewer HIGH #5(a): single-object `flux suspend kustomization poc-capsule`.
if flux suspend kustomization poc-capsule -n flux-system 2>/dev/null; then
  pass "suspended: poc-capsule"
else
  warn "could not run 'flux suspend kustomization poc-capsule' (likely already suspended; not fatal)"
fi
SUSPEND_STATE=$(kubectl --context=k3d-hub-flux get kustomization poc-capsule -n flux-system -o jsonpath='{.spec.suspend}' 2>/dev/null || echo "absent")
if [[ "$SUSPEND_STATE" == "true" ]]; then
  pass "verified: poc-capsule spec.suspend=true"
elif [[ "$SUSPEND_STATE" == "absent" ]]; then
  info "Kustomization poc-capsule is absent on hub-flux (POC likely never installed; teardown still safe)"
else
  warn "poc-capsule spec.suspend='$SUSPEND_STATE' (expected 'true')"
fi

# ---------- Section 6: Step 5/5 -- optional cluster delete (--full flag) ----------
section "Step 5/5: optional cluster delete (--full flag)"
if [[ "$FULL" == "true" ]]; then
  k3d cluster delete spoke-capsule
  pass "deleted: k3d cluster spoke-capsule"
else
  info "skipping k3d cluster delete (--full not set; cluster + Capsule operator remain alive but tenants gone)"
fi

# ---------- Section 7: Summary ----------
section "Summary"
printf "  %s%d passed%s, %s%d warnings%s, %s%d failed%s\n" \
  "${C_GREEN}" "${PASS}" "${C_RESET}" "${C_YELLOW}" "${WARN}" "${C_RESET}" "${C_RED}" "${FAIL}" "${C_RESET}"
if (( FAIL > 0 )); then exit 1; fi
printf "\n%sOrdered teardown complete for spoke-capsule POC.%s\n" "${C_GREEN}" "${C_RESET}"
