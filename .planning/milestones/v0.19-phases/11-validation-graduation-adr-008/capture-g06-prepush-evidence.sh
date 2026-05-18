#!/usr/bin/env bash
# Capture Plan 11-07 Task 6 PRE-PUSH G-06 evidence sections A-E.
#
# Usage:
#   bash .planning/phases/11-validation-graduation-adr-008/capture-g06-prepush-evidence.sh
#
# Optional environment overrides:
#   HUB_CTX=k3d-hub-flux
#   SPOKE_CTX=k3d-spoke-capsule
#   OUT=/tmp/custom-output.md

set -uo pipefail

readonly HUB_CTX="${HUB_CTX:-k3d-hub-flux}"
readonly SPOKE_CTX="${SPOKE_CTX:-k3d-spoke-capsule}"
readonly STAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
readonly OUT="${OUT:-/tmp/karyon-11-07-g06-prepush-${STAMP//[:]/}.md}"
readonly DIAG=".planning/phases/11-validation-graduation-adr-008/11-07-G06-DIAGNOSTICS.md"

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf 'ERROR: required command not found: %s\n' "$cmd" >&2
    exit 1
  fi
}

capture() {
  local heading="$1"
  local command_text="$2"
  local output status

  {
    printf '### %s\n\n' "$heading"
    printf '```bash\n%s\n```\n\n' "$command_text"
    printf 'Captured output (%s):\n\n' "$STAMP"
    printf '```text\n'
  } >> "$OUT"

  output="$(timeout 45s bash -lc "$command_text" 2>&1)"
  status=$?

  {
    printf '%s\n' "$output"
    printf '\n[exit status: %s]\n' "$status"
    printf '```\n\n'
  } >> "$OUT"
}

require_cmd flux
require_cmd kubectl
require_cmd timeout

cat > "$OUT" <<EOF
# G-06 PRE-PUSH Evidence Capture

Captured: ${STAMP}
Hub context: ${HUB_CTX}
Spoke context: ${SPOKE_CTX}

Paste each "Captured output" block below into sections A-E of:

${DIAG}

EOF

capture "A. HelmRelease state pre-fix" \
  "flux get hr -n capsule-system --context='${HUB_CTX}'"

capture "B. helm-controller logs around the timeout" \
  "kubectl --context='${HUB_CTX}' -n flux-system logs deploy/helm-controller --tail=200 | grep -iE 'capsule|impersonat|forbidden|deadline|context' || true"

capture "C. HR-related events on hub" \
  "kubectl --context='${HUB_CTX}' -n capsule-system get events --sort-by='.lastTimestamp' | grep -iE 'helmrelease|capsule|forbidden|deadline' || true"

capture "D. SA existence on spoke" \
  "kubectl --context='${SPOKE_CTX}' -n capsule-system get sa"

capture "E. SAR check for default SA on spoke" \
  "kubectl --context='${SPOKE_CTX}' auth can-i create deployments --namespace=capsule-system --as=system:serviceaccount:capsule-system:default && kubectl --context='${SPOKE_CTX}' auth can-i create secrets --namespace=capsule-system --as=system:serviceaccount:capsule-system:default"

printf 'Wrote PRE-PUSH capture to: %s\n' "$OUT"
printf 'Next: paste sections A-E into %s, then run git push origin main.\n' "$DIAG"
