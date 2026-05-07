#!/usr/bin/env bash
# Capture Plan 11-07 Task 6 POST-PUSH G-06 evidence sections F-I and related live checks.
#
# Usage:
#   bash .planning/phases/11-validation-graduation-adr-008/capture-g06-postpush-evidence.sh
#
# Optional environment overrides:
#   HUB_CTX=k3d-hub-flux
#   SPOKE_CTX=k3d-spoke-capsule
#   OUT=/tmp/custom-output.md
#   RUN_SLO=1        # also run bats tests/bats/slo-regression-live.bats (destructive: invokes task rebuild)
#   RUN_CI=0         # skip GitHub Actions status capture

# shellcheck disable=SC2016 # Markdown code fences intentionally use literal backticks.
set -uo pipefail

readonly HUB_CTX="${HUB_CTX:-k3d-hub-flux}"
readonly SPOKE_CTX="${SPOKE_CTX:-k3d-spoke-capsule}"
readonly RUN_SLO="${RUN_SLO:-0}"
readonly RUN_CI="${RUN_CI:-1}"
STAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
readonly STAMP
readonly OUT="${OUT:-/tmp/karyon-11-07-g06-postpush-${STAMP//[:]/}.md}"
readonly DIAG=".planning/phases/11-validation-graduation-adr-008/11-07-G06-DIAGNOSTICS.md"
readonly SUMMARY=".planning/phases/11-validation-graduation-adr-008/11-06-SUMMARY.md"

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

  output="$(timeout 120s bash -lc "$command_text" 2>&1)"
  status=$?

  {
    printf '%s\n' "$output"
    printf '\n[exit status: %s]\n' "$status"
    printf '```\n\n'
  } >> "$OUT"
}

require_cmd flux
require_cmd kubectl
require_cmd jq
require_cmd curl
require_cmd timeout

cat > "$OUT" <<EOF
# G-06 POST-PUSH Evidence Capture

Captured: ${STAMP}
Hub context: ${HUB_CTX}
Spoke context: ${SPOKE_CTX}
RUN_SLO: ${RUN_SLO}
RUN_CI: ${RUN_CI}

Paste sections F-I into:

${DIAG}

Paste the remaining live-check outputs into:

${SUMMARY}

EOF

capture "F. HelmRelease state post-fix" \
  "flux get hr -n capsule-system --context='${HUB_CTX}'"

capture "G. SA existence on spoke post-fix" \
  "kubectl --context='${SPOKE_CTX}' get ns capsule-system --show-labels && kubectl --context='${SPOKE_CTX}' -n capsule-system get sa helm-controller && kubectl --context='${SPOKE_CTX}' get clusterrolebinding helm-controller-cluster-admin"

capture "H. SAR check for helm-controller SA on spoke post-fix" \
  "kubectl --context='${SPOKE_CTX}' auth can-i '*' '*' --as=system:serviceaccount:capsule-system:helm-controller"

capture "I. helm-controller logs post-fix" \
  "kubectl --context='${HUB_CTX}' -n flux-system logs deploy/helm-controller --tail=200 | grep -iE 'capsule|impersonat|forbidden|deadline|context' || true"

capture "Plan 11-06 check: poc-capsule-spoke-rbac Kustomization" \
  "flux get kustomization poc-capsule-spoke-rbac --context='${HUB_CTX}'"

capture "Plan 11-06 check: poc-capsule Kustomization" \
  "flux get kustomization poc-capsule --context='${HUB_CTX}'"

capture "Plan 11-06 check: poc-capsule-spoke Kustomization" \
  "flux get kustomization poc-capsule-spoke --context='${HUB_CTX}'"

capture "Plan 11-06 hard gate: capsule-proxy Role has secrets create verb" \
  "kubectl --context='${SPOKE_CTX}' -n capsule-system get role capsule-proxy:capsule-proxy -o json | jq -e '.rules[] | select(.resources | contains([\"secrets\"])) | select(.verbs | contains([\"create\"]))'"

capture "Plan 11-06 check: capsule-proxy health endpoint" \
  "curl -sk -o /tmp/karyon-capsule-proxy-healthz-body -w 'HTTP %{http_code}\\n' https://127.0.0.1:30443/healthz; printf '\\nBody:\\n'; cat /tmp/karyon-capsule-proxy-healthz-body"

if [[ "$RUN_CI" == "1" ]]; then
  if command -v gh >/dev/null 2>&1; then
    capture "CI check: latest ci.yml run summary" \
      "gh run list --workflow=ci.yml --limit=1 --json databaseId,status,conclusion,headSha,createdAt"

    capture "CI check: markdownlint and gitleaks-scan job status" \
      "RUN_ID=\$(gh run list --workflow=ci.yml --limit=1 --json databaseId --jq '.[0].databaseId'); echo \"databaseId=\${RUN_ID}\"; gh run view \"\${RUN_ID}\" --json jobs --jq '.jobs[] | select(.name == \"markdownlint\" or .name == \"gitleaks-scan\") | {name,status,conclusion}'"
  else
    {
      printf '### CI check: skipped\n\n'
      printf '```text\ngh not installed; skipped GitHub Actions status capture.\n```\n\n'
    } >> "$OUT"
  fi
else
  {
    printf '### CI check: skipped\n\n'
    printf '```text\nRUN_CI=0; skipped GitHub Actions status capture.\n```\n\n'
  } >> "$OUT"
fi

if [[ "$RUN_SLO" == "1" ]]; then
  require_cmd bats
  capture "VAL-04 destructive check: slo-regression-live.bats" \
    "bats tests/bats/slo-regression-live.bats"
else
  {
    printf '### VAL-04 destructive check: skipped\n\n'
    printf '```text\nRUN_SLO is not 1, so bats tests/bats/slo-regression-live.bats was skipped.\n'
    printf 'To run it, execute:\n'
    printf 'RUN_SLO=1 bash .planning/phases/11-validation-graduation-adr-008/capture-g06-postpush-evidence.sh\n'
    printf '```\n\n'
  } >> "$OUT"
fi

printf 'Wrote POST-PUSH capture to: %s\n' "$OUT"
printf 'Next: paste F-I into %s and live-check evidence into %s.\n' "$DIAG" "$SUMMARY"
