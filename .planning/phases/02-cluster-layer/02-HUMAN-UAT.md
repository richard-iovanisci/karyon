---
status: resolved
phase: 02-cluster-layer
source: [02-VERIFICATION.md]
started: 2026-04-24T20:10:00Z
updated: 2026-04-24T20:30:00Z
---

## Current Test

[all tests resolved on rich@Area-51, 2026-04-24T20:30:00Z]

## Tests

### 1. All three clusters report Ready (exact column match, not substring)
expected: Each cluster returns exactly one node with status `Ready` (not `NotReady`)
result: passed — live run on rich@Area-51 2026-04-24T20:30:00Z returned `k3d-hub-flux-server-0 Ready`, `k3d-spoke-ml-server-0 Ready`, `k3d-spoke-apps-server-0 Ready` (column 2 exact match)

Run:
```bash
for c in hub-flux spoke-ml spoke-apps; do
  count=$(kubectl --context "k3d-${c}" get nodes --no-headers 2>/dev/null | awk '$2 == "Ready"' | wc -l)
  echo "${c}: ${count} Ready"
done
```
Pass criterion: each line reports `1 Ready`.

Why human: CLU-02 / CLU-04 bats tests use `grep -c Ready`, which also matches `NotReady` (BLOCKER-01 in 02-REVIEW.md). Automated test is a false-positive risk — only a live exact-column check confirms.

### 2. spoke-ml advertises nvidia.com/gpu capacity ≥ 1
expected: Output is a non-empty integer >= 1
result: passed — live run returned `1` (RTX 5090 GPU advertised by device-plugin DaemonSet)

Run:
```bash
kubectl --context k3d-spoke-ml get nodes -o jsonpath='{.items[*].status.capacity.nvidia\.com/gpu}'
echo
```
Pass criterion: output is `1` (or higher).

Why human: CLU-03 live-gated bats test passed on the Plan 02-05 checkpoint but cannot be re-run from the verifier context (not on dev box). Re-confirmation ensures the device-plugin DaemonSet is still healthy after any reboots/re-creates since.

### 3. All three apiserver cert SANs confirmed
expected: Each openssl probe returns `1` (SAN present in cert)
result: passed — live run returned `hub-flux (:6443): 1`, `spoke-ml (:6444): 1`, `spoke-apps (:6445): 1` (SAN present on all three apiserver certs)

Run:
```bash
for pair in "hub-flux:6443" "spoke-ml:6444" "spoke-apps:6445"; do
  name="${pair%%:*}"
  port="${pair##*:}"
  found=$(echo | openssl s_client -connect "127.0.0.1:${port}" -servername "k3d-${name}-server-0" 2>/dev/null \
    | openssl x509 -noout -text 2>/dev/null \
    | grep -c "DNS:k3d-${name}-server-0")
  echo "${name} (:${port}): ${found}"
done
```
Pass criterion: each line reports `1`.

Why human: CLU-05 live bats test only probes hub-flux; spoke-ml and spoke-apps SANs have zero automated live coverage (WARN-04 in 02-REVIEW.md). Roadmap Success Criterion 3 ("every apiserver's serving cert") requires all three.

## Summary

total: 3
passed: 3
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps

