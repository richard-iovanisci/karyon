# 2. k3d Over Kind

## Status

Accepted (2026-04-22)

## Context

This is a local Kubernetes lab on Windows 11 + WSL2 with an RTX 5090 GPU. The
cluster runtime needs to support: GPU pass-through, multi-cluster on a shared
Docker network, explicit network control for cross-cluster reachability, and
rebuild-from-zero in under 20 minutes. The two main candidates are k3d
(k3s-on-Docker) and Kind (Kubernetes-in-Docker).

Both are local-only Docker-based runtimes; both are well-supported by the
Kubernetes community. They differ on three dimensions that matter to this
lab: GPU pass-through, idle resource overhead, and explicit network control
for the hub-spoke topology described in ADR-004.

## Decision

Use k3d for all three clusters in the lab (`hub-flux`, `spoke-ml`,
`spoke-apps`).

## Consequences

**Easier:**
- Official GPU support via the `--gpus all` flag at cluster create time. Kind
  has no first-class GPU integration; the workaround paths are fragile and
  break on RTX 5090 / sm_120.
- Lower idle RAM per cluster (~250 MB for k3s vs ~500 MB for upstream
  Kubernetes control plane). Three clusters on one dev box benefit
  proportionally.
- Explicit `--network k8s-net` keeps all three clusters on a shared Docker
  bridge — required for the hub-only Flux topology where `kustomize-controller`
  on `hub-flux` reaches `spoke-ml-server-0` and `spoke-apps-server-0` by
  Docker embedded DNS hostnames (see `0004-hub-only-flux-control-plane.md`).
- The `--k3s-arg '--tls-san=...'` pattern lets us pin TLS SANs at create time
  to those Docker DNS hostnames. Kind's equivalent (`kubeadmConfigPatches`)
  is more verbose and harder to retrofit.
- Ships a Helm controller-equivalent (Flux's `helm-controller`) layered cleanly
  on top; k3d does not embed Helm 2 / Tiller historical baggage.

**Harder:**
- k3s has a smaller community than upstream Kubernetes; some upstream tools
  assume vanilla `kubectl` semantics that k3s deviates from in subtle ways
  (none surfaced for v1, but a future risk).
- The custom `karyon/k3s-cuda` image (Phase 2 IMG-01..06) is more complex to
  maintain than a stock Kind image — the 3-part k3d GPU contract
  (`/etc/docker/daemon.json` `default-runtime: nvidia` + Ubuntu 22.04 base
  image + containerd `config.toml.tmpl` setting `default_runtime_name = "nvidia"`)
  is lab-specific. See `../gpu-notes.md`.

**No-change:**
- Both runtimes are local-only. Cloud cluster migration (EKS / GKE / AKS) is
  explicitly out of scope (see REQUIREMENTS.md "Out of Scope").
- Both runtimes are dev-box-only; production hardening is out of scope.
