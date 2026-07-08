# 1. Single WSL2 Distro + Shared Docker Network

## Status

Accepted (2026-04-22)

## Context

This is a local Kubernetes lab on Windows 11 + WSL2 with an RTX 5090 GPU. The
lab needs three k3d clusters (hub-flux + spoke-ml + spoke-apps) co-located on
the same dev box, sharing GPU and network resources, with rebuild-from-zero in
under 20 minutes.

Two architectural questions converge here:

1. **One WSL2 distro or several?** WSL2 supports multiple Ubuntu (or other
   Linux) distributions, each appearing as an isolated namespace from the
   shell. The temptation is to give each cluster its own distro for isolation.
   In practice, every WSL2 distro shares the same underlying Hyper-V VM (one
   kernel, one memory budget, one CPU pool), so per-distro isolation is
   illusory — but per-distro overhead (one Docker daemon, one systemd, one set
   of running services) is real.

2. **Docker Desktop integration or Docker Engine native in WSL?** Docker
   Desktop on Windows installs a separate Docker Desktop WSL distro that
   surfaces `docker` to other distros via socket forwarding. Each integrated
   distro carries integration overhead, and Docker Desktop adds GUI services,
   licensing, and Kubernetes-by-Docker-Desktop features that compete with k3d.

## Decision

1. Use a single WSL2 Ubuntu 24.04 distro for all three clusters; attach all
   clusters to a single shared Docker bridge network named `k8s-net`
   (CIDR `172.30.0.0/16`).
2. Install Docker Engine natively inside that WSL2 distro (not via Docker
   Desktop integration). `scripts/install-docker.sh` provisions the engine,
   the user's `docker` group membership, and a `daemon.json` with
   `default-runtime: nvidia` plus an explicit `dns` array.

## Consequences

**Easier:**
- One distro to manage, snapshot, back up, and shut down via `wsl --shutdown`.
- One Docker daemon hosting all three clusters; no socket forwarding, no
  Docker Desktop license surface, no shared-memory contention from extra
  WSL distros.
- All three k3d clusters reach each other by Docker embedded DNS hostnames
  (`k3d-hub-flux-server-0`, `k3d-spoke-ml-server-0`,
  `k3d-spoke-apps-server-0`) on `k8s-net` without TLS-SAN gymnastics for
  cross-distro routing — required for hub-only Flux reconciliation per
  `0004-hub-only-flux-control-plane.md`.
- The `--gpus all` GPU pass-through works directly from the host into the
  spoke-ml cluster's k3s container, no extra hop through a Docker Desktop
  bridge.

**Harder:**
- A misbehaving cluster takes down its peers' Docker daemon during a daemon
  restart; recovery is "fix and restart docker", which is fast (`task fix-dns`
  is the canonical workaround for the related CoreDNS NodeHosts staleness
  issue).
- Disk pressure is concentrated in one distro's filesystem; the dev box must
  provision enough free space (`scripts/preflight.sh` enforces the free-space
  floors).

**No-change:**
- v1 ships with this single-distro topology. Per-cluster distros remain
  out of scope because the isolation gain is illusory.
- `docs/wsl-networking.md` documents the NAT-mode fallback for the
  mirrored-mode + Docker-custom-network breakage; the decision here doesn't
  change with networking mode, only the recovery procedure does.
