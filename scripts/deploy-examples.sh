#!/usr/bin/env bash
# scripts/deploy-examples.sh
#
# Deploys the canonical example workloads through the existing hub-side Flux
# Kustomizations. This script intentionally reconciles GitOps state only; it
# never applies workload manifests directly to spoke clusters.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=scripts/lib/preflight-lib.sh
# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/lib/preflight-lib.sh"

readonly HUB_CTX="k3d-hub-flux"
readonly SPOKE_APPS_CTX="k3d-spoke-apps"
readonly SPOKE_ML_CTX="k3d-spoke-ml"
readonly PODINFO_DIR="${REPO_ROOT}/examples/podinfo"
readonly GPU_SMOKE_DIR="${REPO_ROOT}/examples/gpu-smoke-test"
readonly SPOKE_APPS_KUST="${REPO_ROOT}/clusters/spoke-apps/kustomization.yaml"
readonly SPOKE_ML_KUST="${REPO_ROOT}/clusters/spoke-ml/kustomization.yaml"

require_file() {
  local file="$1"
  if [[ ! -f "${file}" ]]; then
    fail "required file missing: ${file}
       Fix: restore the canonical examples and spoke wiring, then rerun: bash scripts/deploy-examples.sh"
    exit 1
  fi
}

require_literal() {
  local file="$1" literal="$2" label="$3"
  if ! grep -Fq -- "${literal}" "${file}"; then
    fail "${label} missing from ${file}.
       Expected literal: ${literal}
       Fix: repair the GitOps manifest wiring, commit, push, then rerun: bash scripts/deploy-examples.sh"
    exit 1
  fi
}

# ---------- Section 1: Preflight gate ----------
section "Preflight gate"
PREFLIGHT_LOG="$(mktemp -t karyon-preflight.XXXXXX.log)"
if ! bash "${SCRIPT_DIR}/preflight.sh" > "${PREFLIGHT_LOG}" 2>&1; then
  fail "preflight has blockers before deploying examples.
     Fix: bash scripts/preflight.sh
     Log: ${PREFLIGHT_LOG}"
  exit 1
fi
pass "preflight green"
rm -f "${PREFLIGHT_LOG}"

# ---------- Section 2: Static manifest check ----------
section "Static manifest check"
require_file "${PODINFO_DIR}/kustomization.yaml"
require_file "${PODINFO_DIR}/namespace.yaml"
require_file "${PODINFO_DIR}/deployment.yaml"
require_file "${PODINFO_DIR}/service.yaml"
require_file "${GPU_SMOKE_DIR}/kustomization.yaml"
require_file "${GPU_SMOKE_DIR}/namespace.yaml"
require_file "${GPU_SMOKE_DIR}/job.yaml"
require_file "${SPOKE_APPS_KUST}"
require_file "${SPOKE_ML_KUST}"
require_literal "${PODINFO_DIR}/deployment.yaml" "ghcr.io/stefanprodan/podinfo:6.7.1" "pinned podinfo image"
require_literal "${GPU_SMOKE_DIR}/job.yaml" "nvcr.io/nvidia/cuda:12.8.0-base-ubuntu22.04" "pinned GPU smoke image"
require_literal "${SPOKE_APPS_KUST}" "../../examples/podinfo" "spoke-apps example reference"
require_literal "${SPOKE_ML_KUST}" "../../examples/gpu-smoke-test" "spoke-ml example reference"
pass "example manifests and spoke references present"

# ---------- Section 3: Git visibility gate ----------
section "Git visibility gate"
dirty="$(cd "${REPO_ROOT}" && git status --short -- examples clusters 2>/dev/null || true)"
if [[ -n "${dirty}" ]]; then
  fail "uncommitted changes detected in paths Flux watches.
     Flux reconciles from origin/main, not the working tree, so the new
     deploy-examples reconcile would silently apply the OLD pushed state
     and kubectl wait for podinfo/nvidia-smi would time out.
     Inspect:  git status -- examples clusters
     Fix:      commit and push: git add examples clusters && git commit -m '<msg>' && git push
     Then rerun: bash scripts/deploy-examples.sh"
  exit 1
fi

if ! git -C "${REPO_ROOT}" fetch origin main >/dev/null 2>&1; then
  fail "could not fetch origin/main before deploy.
     Inspect: git remote -v
     Fix:     verify network access and origin remote, then rerun: bash scripts/deploy-examples.sh"
  exit 1
fi
local_head="$(git -C "${REPO_ROOT}" rev-parse HEAD 2>/dev/null || true)"
remote_head="$(git -C "${REPO_ROOT}" rev-parse origin/main 2>/dev/null || true)"
if [[ -z "${local_head}" || -z "${remote_head}" ]]; then
  fail "could not resolve HEAD or origin/main before deploy.
     Inspect: git rev-parse HEAD; git rev-parse origin/main
     Fix:     ensure the repo is initialized and origin/main exists, then rerun: bash scripts/deploy-examples.sh"
  exit 1
fi
if [[ "${local_head}" != "${remote_head}" ]]; then
  fail "local HEAD (${local_head}) does not match origin/main (${remote_head}).
     Flux reconciles origin/main, not your local branch, so unpushed local
     commits will silently be ignored and the deploy will time out.
     Inspect: git status; git log --oneline origin/main..HEAD
     Fix:     push your local commits: git push
     Then rerun: bash scripts/deploy-examples.sh"
  exit 1
fi
pass "git visibility ok: examples/ and clusters/ are clean and HEAD == origin/main"

# ---------- Section 4: GPU smoke rerun ----------
section "GPU smoke rerun"
if kubectl --context "${SPOKE_ML_CTX}" get namespace gpu-smoke >/dev/null 2>&1; then
  kubectl --context k3d-spoke-ml -n gpu-smoke delete job nvidia-smi --ignore-not-found --wait=true >/dev/null 2>&1 || true
  pass "old gpu-smoke/nvidia-smi Job deleted or already absent"
else
  info "gpu-smoke namespace not present yet; Flux will create it"
fi

# ---------- Section 5: Flux source refresh ----------
section "Flux source refresh"
# source-controller must have the latest commit before kustomize-controller reapplies
# the spoke-ml Job, otherwise the Job rerun can race with source fetch and hit
# immutable-field rejection on stale spec.
if flux reconcile source git --help 2>/dev/null | grep -q -- '--with-source'; then
  flux --context k3d-hub-flux reconcile source git flux-system --with-source
else
  flux --context k3d-hub-flux reconcile source git flux-system
fi
pass "Flux source refreshed"

# ---------- Section 6: Flux reconcile ----------
section "Flux reconcile"
flux --context k3d-hub-flux reconcile kustomization spoke-apps --with-source
flux --context k3d-hub-flux reconcile kustomization spoke-ml --with-source
pass "spoke Kustomizations reconciled"

# ---------- Section 7: Workload waits ----------
section "Workload waits"
kubectl --context k3d-spoke-apps -n podinfo wait --for=condition=Available deployment/podinfo --timeout=180s
pass "podinfo Deployment Available=True"
kubectl --context k3d-spoke-ml -n gpu-smoke wait --for=condition=Complete job/nvidia-smi --timeout=300s
pass "GPU smoke Job Complete=True"

# ---------- Section 8: GPU log proof ----------
section "GPU log proof"
if ! kubectl --context k3d-spoke-ml -n gpu-smoke logs job/nvidia-smi | grep -F "NVIDIA-SMI" >/dev/null; then
  fail "gpu-smoke/nvidia-smi logs did not contain NVIDIA-SMI.
     Inspect: kubectl --context k3d-spoke-ml -n gpu-smoke logs job/nvidia-smi
     Fix: check spoke-ml GPU capacity and rerun: bash scripts/deploy-examples.sh"
  exit 1
fi
pass "nvidia-smi log contains NVIDIA-SMI"

# ---------- Summary ----------
section "Summary"
printf "  %s%d passed%s, %s%d warnings%s, %s%d failed%s\n" \
  "${C_GREEN}" "${PASS}" "${C_RESET}" "${C_YELLOW}" "${WARN}" "${C_RESET}" "${C_RED}" "${FAIL}" "${C_RESET}"
if (( FAIL > 0 )); then exit 1; fi
printf "\n%sexample workloads deployed through Flux.%s\n" "${C_GREEN}" "${C_RESET}"
