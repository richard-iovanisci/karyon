---
phase: 04-spoke-registration
reviewed: 2026-04-27T22:27:02Z
depth: standard
files_reviewed: 17
files_reviewed_list:
  - Taskfile.yml
  - clusters/hub-flux/flux-system/kustomization.yaml
  - clusters/hub-flux/kustomization.yaml
  - clusters/hub-flux/spokes/kustomization.yaml
  - clusters/hub-flux/spokes/spoke-apps.yaml
  - clusters/hub-flux/spokes/spoke-ml.yaml
  - clusters/spoke-apps/configmap.yaml
  - clusters/spoke-apps/kustomization.yaml
  - clusters/spoke-apps/namespace.yaml
  - clusters/spoke-ml/configmap.yaml
  - clusters/spoke-ml/kustomization.yaml
  - clusters/spoke-ml/namespace.yaml
  - docs/flux-hub-spoke.md
  - scripts/register-spokes-for-flux.sh
  - tests/bats/bootstrap-flux-02-docs.bats
  - tests/bats/register-spokes-01-static.bats
  - tests/bats/register-spokes-02-live.bats
findings:
  critical: 2
  warning: 1
  info: 0
  total: 3
status: issues_found
---

# Phase 04: Code Review Report

**Reviewed:** 2026-04-27T22:27:02Z
**Depth:** standard
**Files Reviewed:** 17
**Status:** issues_found

## Summary

Reviewed the spoke Flux registration script, hub/spoke manifests, docs, and Bats coverage. YAML parsing, `kubectl kustomize`, shell syntax, shellcheck, and the static Bats suites were run. The implementation still has credential-handling and repair-path defects that should be fixed before shipping.

## Critical Issues

### CR-01: Cluster-admin bearer token is sent through an unsafe probe command

**Classification:** BLOCKER
**File:** `scripts/register-spokes-for-flux.sh:105-110`
**Issue:** `in_pod_wget` interpolates the long-lived spoke bearer token into the local `kubectl exec ... /bin/sh -c "wget ... Bearer ${bearer}"` argv, so the token can be observed via process listings while the command runs. The same request also uses `--no-check-certificate`; the earlier OpenSSL probe is a separate connection, so the actual bearer-token request is not bound to the verified certificate and can disclose a cluster-admin token to any endpoint that answers that DNS name.
**Fix:** Replace the `wget --no-check-certificate` helper with a single verified HTTPS request that uses the decoded CA for the same connection and passes the bearer over stdin, not argv. For example, refactor the helper to write the CA into the probe environment, then send the HTTP request body through `kubectl exec -i` into `openssl s_client -verify_return_error -verify_hostname ... -CAfile ...`. Update the live tests to reject `--no-check-certificate` for bearer-token calls.

```bash
printf 'GET %s HTTP/1.1\r\nHost: %s\r\nAuthorization: Bearer %s\r\nConnection: close\r\n\r\n' \
  "${path}" "${host}" "${bearer}" |
  kubectl --context "${HUB_CTX}" -n "${FLUX_NS}" exec -i deploy/kustomize-controller -- \
    openssl s_client -quiet -verify_return_error -verify_hostname "${host}" \
      -CAfile "${cert_tmp}" -connect "${host}:6443"
```

### CR-02: Hub kustomization repair can skip missing resources or write invalid YAML

**Classification:** BLOCKER
**File:** `scripts/register-spokes-for-flux.sh:537-555`
**Issue:** The wire-up gate treats the sentinel comment as proof that `- ../spokes` is present. If the sentinel remains but the resource line is removed, the script logs "already done" and leaves the hub unable to reconcile spoke Kustomizations. The fallback `awk` appender is also not YAML-aware: when `resources:` uses the common indented list style (`  - gotk-components.yaml`), it writes `- ../spokes` at column 1, producing invalid YAML.
**Fix:** Check and update the actual `resources` list rather than using the comment as state. Use `yq` or a YAML-aware helper to ensure `../spokes` exists, then validate the result before moving it into place.

```bash
tmp="$(mktemp)"
yq eval '(.resources // []) as $r | .resources = ($r + ["../spokes"] | unique)' \
  "${HUB_KUST_FILE}" > "${tmp}"
yq eval -e '.resources[] == "../spokes"' "${tmp}" >/dev/null
mv "${tmp}" "${HUB_KUST_FILE}"
```

## Warnings

### WR-01: Temporary OpenSSL probe pod can be left behind on failure

**Classification:** WARNING
**File:** `scripts/register-spokes-for-flux.sh:147-148`
**Issue:** After the fallback pod is recreated, the second `kubectl wait` runs under `set -e`; if it fails, the script exits immediately and never deletes the temporary `karyon-openssl-probe-*` pod. Similar early exits before the explicit delete in `verify_tls_with_openssl` can also leave the probe pod behind.
**Fix:** Wrap the fallback probe lifecycle in a cleanup trap or subshell so every return path removes the pod.

```bash
(
  trap 'kubectl --context "${HUB_CTX}" -n "${FLUX_NS}" delete pod "${pod}" --ignore-not-found --grace-period=0 --force --wait=true >/dev/null 2>&1 || true' EXIT
  ensure_openssl_probe_pod "${pod}"
  # copy CA and run probes here
)
```

---

_Reviewed: 2026-04-27T22:27:02Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
