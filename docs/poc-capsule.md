---
status: Active
audience: POC operators (WSL host)
purpose: Runbook for the spoke-capsule POC -- host-restart recovery and troubleshooting.
scope: Phase 7 ships only the Host restart recovery section. Phases 10/11 will add tenant kubeconfig delivery contract and ordered teardown procedure respectively.
---

# spoke-capsule POC Operator's Runbook

> **Status:** Active (Phase 7 -- host-restart recovery only).
> **Companion docs:** [`docs/capsule-on-eks.md`](capsule-on-eks.md) (EKS rough-cut design), [`docs/architecture.md`](architecture.md) (overall karyon topology).

The `spoke-capsule` cluster is the karyon v0.19 Capsule POC's persistent isolated k3d cluster. It is **NOT** part of the default `task rebuild` chain -- it stays alive across rebuilds and is intentionally outside the v1 production topology until graduation ADR-008 says otherwise.

| Property | Value |
|---|---|
| Cluster name | `spoke-capsule` |
| Apiserver port (host) | `6446` |
| **Reserved NodePort** | `30443` (capsule-proxy in Phase 8; see "Reserved ports" below) |
| Network | `k8s-net` (shared bridge) |
| TLS SAN | `k3d-spoke-capsule-server-0` |
| Stock image | `rancher/k3s:v1.34.6-k3s1` |
| Kubeconfig context | `k3d-spoke-capsule` |

## Host restart recovery

After a Docker daemon restart or a WSL2 resume, k3d clusters can carry stale CoreDNS NodeHosts entries. This is the canonical k3d workaround per upstream issues #1009 and #1112.

### Quickstart

```
task fix-dns-poc-capsule
```

This invokes `scripts/poc/capsule/fix-dns.sh`, which:

1. Verifies `k3d` and `kubectl` are present.
2. Stops the `spoke-capsule` cluster (`k3d cluster stop spoke-capsule`).
3. Starts it back up with `--wait --timeout 120s`.
4. Waits for the spoke-capsule node to reach `Ready=True` (`kubectl --context k3d-spoke-capsule wait --for=condition=Ready node --all --timeout=120s`).

### What to expect

```text
== Tool gate ==
  ok  required commands present
== spoke-capsule stop/start ==
  ok  stopped: spoke-capsule
  ok  started: spoke-capsule
== spoke-capsule node readiness ==
  ok  spoke-capsule node Ready=True
== Summary ==
  4 passed, 0 warnings, 0 failed
CoreDNS NodeHosts refresh complete for spoke-capsule.
```

Total runtime: ~30-90 seconds depending on Docker resource pressure.

### How to verify

After the task completes:

```
kubectl --context k3d-spoke-capsule get nodes
```

You should see one node `k3d-spoke-capsule-server-0` with `Ready` status.

### Distinct from `task fix-dns`

`task fix-dns` (which calls `scripts/fix-coredns.sh`) handles **hub-flux only** -- it is the v0.18 default. The two tasks are **siblings**, not a parent/child relationship. Run whichever applies (or both if you've restarted both clusters):

| Task | Scope |
|---|---|
| `task fix-dns` | hub-flux cluster |
| `task fix-dns-poc-capsule` | spoke-capsule cluster |

## Troubleshooting

### Cluster fails to stop

If `k3d cluster stop spoke-capsule` reports a failure, the cluster may already be down. Check:

```
k3d cluster list
docker ps --filter name=k3d-spoke-capsule
```

If no `k3d-spoke-capsule-*` containers are running, the cluster is already stopped -- proceed to start.

### Cluster fails to start within 120s

Most often a Docker resource pressure issue (low memory or pre-pull pause). Check:

```
docker stats --no-stream
```

Free up memory if WSL is under pressure. Re-run `task fix-dns-poc-capsule`.

### Node never reaches Ready=True

Verify the spoke's apiserver is reachable on the host-published port:

```
curl -k https://127.0.0.1:6446/readyz
```

If this returns 200, the cluster is up but kubectl context may be stale. Re-fetch:

```
k3d kubeconfig merge spoke-capsule --kubeconfig-merge-default
```

### After a fresh `task fix-dns-poc-capsule`, hub-flux Kustomizations show errors against spoke-capsule

The `spoke-capsule-kubeconfig` Secret on hub-flux references the spoke's apiserver. After a stop/start, the apiserver IP within the `k8s-net` bridge generally stays stable, but if hub-flux's outer `poc-capsule` Kustomization reports `Ready=False` with a connection error, force a reconcile:

```
flux reconcile kustomization poc-capsule -n flux-system --with-source
```

If errors persist, re-register:

```
bash scripts/register-poc-cluster.sh spoke-capsule
```

## Reserved ports

| Port | Reservation | Phase |
|---|---|---|
| `6446` | spoke-capsule apiserver (host-published) | Phase 7 |
| `30443` | capsule-proxy NodePort (host-published; future POC reserve) | Phase 7 (preflight reservation) -> Phase 8 (capsule-proxy install) |

Future POCs adding more reserved ports should extend `scripts/preflight.sh` `check_port_strict` invocations and update this table. The bats test `tests/bats/preflight-pre15.bats` greps the literal `check_port_strict 30443`.

## Related references

- `docs/capsule-on-eks.md` -- EKS-target rough-cut design (EKSDOC-01)
- `scripts/poc/capsule/create-cluster.sh` -- persistent cluster creation (CAPCLU-01)
- `scripts/register-poc-cluster.sh` -- register spoke-capsule with hub-flux (POC-02)
- `scripts/poc/capsule/fix-dns.sh` -- this runbook's underlying script (CAPCLU-03)
- `scripts/fix-coredns.sh` -- v0.18 hub-flux equivalent (`task fix-dns`)
