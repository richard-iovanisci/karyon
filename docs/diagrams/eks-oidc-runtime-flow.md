# EKS OIDC runtime auth flow (private Keycloak · capsule-proxy · Capsule)

Step-numbered sequence of the runtime identity chain described in
[`../eks-private-keycloak-oidc-strategy.md`](../eks-private-keycloak-oidc-strategy.md)
and [`../eks-identity-adoption-brief.md`](../eks-identity-adoption-brief.md).
A rendered export for embedding lives alongside:
[`eks-oidc-runtime-flow.svg`](eks-oidc-runtime-flow.svg) (compact vector of
this file's sequence). The high-resolution
[`eks-oidc-runtime-flow.png`](eks-oidc-runtime-flow.png) is rendered from
the Headlamp-centric mermaid in
[`../eks-oidc-tenancy-flow.md`](../eks-oidc-tenancy-flow.md) — same identity
chain at a different altitude; edit each diagram at its own source.

Three conversations that never overlap in time: the control plane talks to
Keycloak rarely (step 0), the human talks to Keycloak once per session
(steps 1–2), and every Kubernetes request (steps 3–9) involves no call to
Keycloak at all.

```mermaid
sequenceDiagram
    participant W as Workstation<br/>(kubectl · Headlamp)
    participant KC as Keycloak<br/>(private internal LB)
    participant P as capsule-proxy
    participant API as EKS apiserver<br/>(+ Capsule)

    Note over KC,API: 0 · at association + key rotation — apiserver fetches<br/>discovery + JWKS via customer-routed VPC egress (cached)
    W->>KC: 1 · browser login (authorization code + PKCE, no client secret)
    KC-->>W: 2 · ID token (iss, aud=kubectl, preferred_username, flat groups)
    W->>P: 3 · Kubernetes request + Authorization: Bearer id_token
    P->>API: 4 · TokenReview(token)
    Note over API: 5 · verify offline vs cached JWKS —<br/>signature, iss, aud, exp → username + groups
    API-->>P: 6 · authenticated user + groups
    Note over P: 7 · cluster-scoped LIST?<br/>filter to caller's owned tenants
    P->>API: 8 · forward request (same bearer identity)
    Note over API: 9 · RBAC (Capsule owner bindings)<br/>+ Capsule admission webhooks
    API-->>P: response
    P-->>W: filtered response
```

Trust anchors (one-directional; no shared secrets anywhere):

- apiserver → Keycloak: the OIDC association (public-CA TLS + cached JWKS).
- capsule-proxy → apiserver: TokenReview with the proxy's own credentials.
- clients → capsule-proxy: the proxy's pinned serving CA.
- workstations → Keycloak: the public CA on the issuer endpoint.

Keycloak is never called per request and never knows the cluster exists.
