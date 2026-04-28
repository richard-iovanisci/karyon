#!/usr/bin/env bash
# scripts/health-check.sh
#
# Read-only health gate for the full karyon hub-spoke lab. This script checks
# existing cluster state only; remediation happens through task fix-dns or the
# owning setup scripts.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=scripts/lib/preflight-lib.sh
# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/lib/preflight-lib.sh"

readonly HUB_CTX="k3d-hub-flux"
readonly SPOKE_ML_CTX="k3d-spoke-ml"
readonly SPOKE_APPS_CTX="k3d-spoke-apps"
readonly FLUX_NS="flux-system"

require_cluster() {
  local cluster="$1"
  if ! k3d cluster list --no-headers 2>/dev/null | awk '{print $1}' | grep -qx "${cluster}"; then
    fail "k3d cluster missing: ${cluster}.
       Fix: task create-clusters"
    exit 1
  fi
  pass "cluster exists: ${cluster}"
}

require_kustomization_ready() {
  local name="$1"
  local ready
  ready="$(kubectl --context "${HUB_CTX}" -n "${FLUX_NS}" get kustomization "${name}" \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
  if [[ "${ready}" != "True" ]]; then
    fail "hub-side Kustomization ${name} is not Ready=True (got: ${ready:-unknown}).
       Inspect: flux --context ${HUB_CTX} get kustomizations ${name}
       Fix:     flux --context ${HUB_CTX} reconcile kustomization ${name} --with-source"
    exit 1
  fi
  pass "Kustomization ${name}: Ready=True"
}

require_san() {
  local spoke="$1" port="$2"
  local expected_san="k3d-${spoke}-server-0"
  if ! openssl s_client -connect "127.0.0.1:${port}" -servername "${expected_san}" </dev/null 2>/dev/null \
      | openssl x509 -noout -text 2>/dev/null \
      | grep -qE "DNS:${expected_san}"; then
    fail "spoke API certificate missing SAN DNS:${expected_san}.
       Inspect: openssl s_client -connect 127.0.0.1:${port} -servername ${expected_san}
       Fix:     task create-clusters"
    exit 1
  fi
  pass "SAN verified: ${expected_san}"
}

# ---------- Section 1: Clusters and nodes ----------
section "Clusters and nodes"
require_cluster hub-flux
require_cluster spoke-ml
require_cluster spoke-apps

# 180s timeout: first-pull GPU device-plugin can take 60-120s to register
# nvidia.com/gpu capacity on spoke-ml after a fresh rebuild. A shorter
# timeout fails the rebuild SLO at the health gate, not in the chain.
for ctx in "${HUB_CTX}" "${SPOKE_ML_CTX}" "${SPOKE_APPS_CTX}"; do
  if ! kubectl --context "${ctx}" wait --for=condition=Ready node --all --timeout=180s; then
    fail "nodes did not become Ready within 180s for ${ctx}.
       Inspect: kubectl --context ${ctx} get node -o wide
       Fix:     task create-clusters"
    exit 1
  fi
  pass "nodes Ready=True: ${ctx}"
done

# ---------- Section 2: Flux controllers ----------
section "Flux controllers"
# MED-3: count deployments BEFORE kubectl wait --all to prevent empty-set
# trivial pass. Pattern matches scripts/bootstrap-flux.sh lines 256-263.
deploy_count="$(kubectl --context k3d-hub-flux -n flux-system get deploy --no-headers 2>/dev/null | wc -l | tr -d '[:space:]')"
if [[ "${deploy_count}" -ge 4 ]]; then
  pass "Flux controller deployment count ok: ${deploy_count}"
else
  fail "expected >= 4 flux controllers in flux-system, found ${deploy_count}.
     Inspect: kubectl --context k3d-hub-flux -n flux-system get deploy,pod
     Fix:     bash scripts/bootstrap-flux.sh && bash scripts/health-check.sh"
  exit 1
fi

if ! kubectl --context k3d-hub-flux -n flux-system wait --for=condition=Available deploy --all --timeout=180s; then
  fail "Flux controllers did not become Available within 180s.
     Inspect: kubectl --context k3d-hub-flux -n flux-system get deploy,pod
     Logs:    flux --context k3d-hub-flux logs
     Fix:     bash scripts/bootstrap-flux.sh && bash scripts/health-check.sh"
  exit 1
fi
pass "Flux controller deployments Available=True"

if ! flux --context k3d-hub-flux check; then
  fail "flux check failed.
     Inspect: flux --context k3d-hub-flux check
     Logs:    flux --context k3d-hub-flux logs
     Fix:     bash scripts/bootstrap-flux.sh && bash scripts/health-check.sh"
  exit 1
fi
pass "flux check: ok"

# ---------- Section 3: Spoke Kustomizations ----------
section "Spoke Kustomizations"
require_kustomization_ready spoke-ml
require_kustomization_ready spoke-apps

# ---------- Section 4: Hub DNS probe ----------
section "Hub DNS probe"
# HIGH-2: read-only DNS probe via kubectl exec into existing
# source-controller pod. This satisfies BOTH the read-only contract
# (no resource creation/deletion) AND the in-hub probe requirement.
# Alternative `kubectl run --rm` is forbidden - it is apply+delete
# under the hood, violating read-only.
if ! kubectl --context k3d-hub-flux -n flux-system exec deploy/source-controller -- getent hosts k3d-spoke-ml-server-0 >/dev/null 2>&1; then
  fail "in-hub DNS probe failed: cannot resolve k3d-spoke-ml-server-0 from source-controller pod.
     This is the documented stale-CoreDNS NodeHosts symptom.
     Fix: task fix-dns
     Then rerun: task health-check"
  exit 1
fi
pass "in-hub DNS probe ok: k3d-spoke-ml-server-0"

if ! kubectl --context k3d-hub-flux -n flux-system exec deploy/source-controller -- getent hosts k3d-spoke-apps-server-0 >/dev/null 2>&1; then
  fail "in-hub DNS probe failed: cannot resolve k3d-spoke-apps-server-0 from source-controller pod.
     This is the documented stale-CoreDNS NodeHosts symptom.
     Fix: task fix-dns
     Then rerun: task health-check"
  exit 1
fi
pass "in-hub DNS probe ok: hub-flux can resolve k3d-spoke-{ml,apps}-server-0"

# ---------- Section 5: GPU capacity ----------
section "GPU capacity"
gpu_capacity="$(kubectl --context k3d-spoke-ml get nodes -o jsonpath='{.items[*].status.capacity.nvidia\.com/gpu}' 2>/dev/null | awk '{print $1}' || true)"
if [[ ! "${gpu_capacity}" =~ ^[0-9]+$ || "${gpu_capacity}" -le 0 ]]; then
  fail "spoke-ml does not report nvidia.com/gpu capacity > 0 (got: ${gpu_capacity:-missing}).
     Inspect: kubectl --context k3d-spoke-ml get nodes -o jsonpath='{.items[*].status.capacity.nvidia\\.com/gpu}'
     Fix:     task create-clusters"
  exit 1
fi
pass "spoke-ml nvidia.com/gpu capacity: ${gpu_capacity}"

# ---------- Section 6: TLS SANs ----------
section "TLS SANs"
require_san spoke-ml 6444
require_san spoke-apps 6445

# ---------- Section 7: Workload proofs ----------
section "Workload proofs"
if ! kubectl --context k3d-spoke-apps -n podinfo wait --for=condition=Available deployment/podinfo --timeout=180s; then
  fail "podinfo Deployment did not become Available.
     Inspect: kubectl --context k3d-spoke-apps -n podinfo get deploy,pod
     Fix:     task deploy-examples"
  exit 1
fi
pass "podinfo Deployment Available=True"

if ! kubectl --context k3d-spoke-ml -n gpu-smoke wait --for=condition=Complete job/nvidia-smi --timeout=300s; then
  fail "gpu-smoke/nvidia-smi Job did not complete.
     Inspect: kubectl --context k3d-spoke-ml -n gpu-smoke get job,pod
     Fix:     task deploy-examples"
  exit 1
fi
pass "gpu-smoke/nvidia-smi Job Complete=True"

if ! kubectl --context k3d-spoke-ml -n gpu-smoke logs job/nvidia-smi | grep -F "NVIDIA-SMI" >/dev/null; then
  fail "gpu-smoke/nvidia-smi logs did not contain NVIDIA-SMI.
     Inspect: kubectl --context k3d-spoke-ml -n gpu-smoke logs job/nvidia-smi
     Fix:     task deploy-examples"
  exit 1
fi
pass "nvidia-smi log contains NVIDIA-SMI"

# ---------- Summary ----------
section "Summary"
printf "  %s%d passed%s, %s%d warnings%s, %s%d failed%s\n" \
  "${C_GREEN}" "${PASS}" "${C_RESET}" "${C_YELLOW}" "${WARN}" "${C_RESET}" "${C_RED}" "${FAIL}" "${C_RESET}"
if (( FAIL > 0 )); then exit 1; fi
printf "\n%shealth check green: clusters, Flux, spokes, DNS, GPU, TLS, and workloads verified.%s\n" \
  "${C_GREEN}" "${C_RESET}"
