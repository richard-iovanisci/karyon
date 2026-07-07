---
slug: tenant-ui-oidc
date: 2026-07-06
type: quick
status: complete
---

# Quick Task: Architecture doc + diagram, OIDC wiring, Headlamp tenant UI

## Origin

User request: (a) high-level architecture doc + detailed diagram (logos,
draw.io-importable) for the Flux + Capsule + Keycloak pattern; (b) UI access +
capsule-proxy directions + user/group creation instructions for initial
tenants; (c) a tenant-facing UI with cluster-resource views scoped through
capsule-proxy, terminal access, optional code-server — Keycloak login
mandatory, CNCF/industry-standard strongly preferred.

## Research (3-agent workflow, live-verified)

1. **Tenant UI**: kubernetes/dashboard ARCHIVED 2026-01-21 with Headlamp
   (kubernetes-sigs) named successor; Headlamp v0.43.0 does PKCE public
   clients (since v0.37), forwards the user's id_token as bearer, and Capsule
   officially documents the capsule-proxy integration (env endpoint override).
   code-server = single-user; per-tenant + oauth2-proxy (CNCF Sandbox) is the
   floor; Coder/Che for real multi-user → documented, not deployed.
2. **OIDC wiring**: host.k3d.internal FALSIFIED (NXDOMAIN everywhere in this
   lab). Winner: https://localhost:31443/realms/karyon — WSL mirrored
   networking shares localhost with Windows; socat forwarder (docker-DNS
   target, node-IP-shuffle-proof) publishes 31443; kube-proxy serves
   NodePorts on node loopback (live-proven) for the apiserver + hostNetwork
   pods. k3s config.yaml retrofit safe (CLI args are only --tls-san).
3. **Keycloak day-2**: kcadm.sh via kubectl exec with in-pod bootstrap-admin
   env (credentials never leave the cluster); realm import-once → all day-2
   via UI/kcadm; the new-tenant identity triple = Keycloak group +
   userGroups append + Tenant Group owner.

## Decisions

- D-UI-01: Headlamp v0.43.0, in capsule-system (same-ns capsule-proxy CA),
  zero-RBAC SA, hostNetwork (issuer via node loopback), PUBLIC kubectl
  client reuse with PKCE (aud stays kubectl — no apiserver audience config).
- D-UI-02: issuer pinned https://localhost:31443/realms/karyon; TLS via
  imperative karyon OIDC CA (~/.karyon/oidc-pki); Keycloak keeps http:8080
  for in-cluster + port-forward.
- D-UI-03: apiserver OIDC via /etc/rancher/k3s/config.yaml + docker restart
  (no recreate); CA in the volume-backed k3s dir; flags verified via the
  'Running kube-apiserver' log line.
- D-UI-04: Tier-3 OIDC Group owners (tenant-{alpha,bravo}-devs,
  clusterRoles tenant-workload-editor) added to Tenant CRs + new-tenant.sh
  template (completes the identity triple for future tenants).
- D-UI-05: headless e2e proof via dedicated confidential client karyon-e2e
  (direct grants + aud=kubectl mapper) — the production kubectl client keeps
  direct grants OFF.
- D-UI-06: code-server pattern documented (tenant-access.md §6), not
  deployed — Headlamp's pod shell covers quick-exec; parked in PROJECT.md.

## Live-debug findings (all fixed + guarded)

- Keycloak 26 default user profile requires lastName + verified email —
  missing ones fail logins with `resolve_required_actions` ("Account is not
  fully set up"); realm import amended.
- capsule-proxy's serving CA = secret `capsule-proxy` key `ca` — NOT
  `capsule-tls` (Capsule's webhook cert). Three consumers fixed + bats pin.
- kubectl merges the active context's client cert into the TLS handshake
  even with --server/--token flags → proxy rejects it; KUBECONFIG=/dev/null
  (or the dedicated oidc.kubeconfig) required.
