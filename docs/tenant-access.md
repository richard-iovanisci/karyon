# Tenant access runbook: Keycloak login → capsule-proxy → your tenant

status: Active (2026-07-06; every command below was run live during wiring)
scope: How humans get into the karyon multi-tenant spoke — web UI (Headlamp),
terminal (kubectl + kubelogin), and the Keycloak administration needed to
onboard users, groups, and new tenants. Architecture background:
`architecture-flux-capsule-keycloak.md`.

## The one picture to keep in mind

Every human path ends at **capsule-proxy `https://127.0.0.1:30443`** carrying a
bearer token. The proxy TokenReviews the token against the apiserver (which
validates OIDC tokens against Keycloak's `karyon` realm), then Capsule
exact-matches the resolved username/groups to Tenant owners and filters
everything to your tenants. Your view IS your group membership:

| You are in Keycloak group… | You see through the proxy… |
|---|---|
| `capsule-platform-owners` | every tenant (alpha, bravo, keycloak) — Tier 2 |
| `tenant-alpha-devs` | tenant-alpha only — Tier 3, `tenant-workload-editor` ceiling |
| `tenant-bravo-devs` | tenant-bravo only |
| (none of the above) | nothing |

Demo users seeded by the realm: `alice` (platform owner) and `bob` (alpha dev).
Their generated passwords live in `~/.karyon/demo-credentials.txt` after the
first `e2e-oidc-test.sh` run; rotate them in the Keycloak UI at will.

## 0. One-time bootstrap (operator, per machine/cluster-recreate)

```bash
bash scripts/poc/keycloak/create-tls.sh            # OIDC CA + Keycloak cert (~/.karyon/oidc-pki)
bash scripts/poc/keycloak/start-oidc-forwarder.sh  # host 31443 → keycloak-oidc NodePort
bash scripts/poc/keycloak/apiserver-oidc.sh        # k3s OIDC flags (restarts the spoke node!)
bash scripts/poc/keycloak/setup-headlamp.sh        # CA ConfigMap + Headlamp redirect URI
bash scripts/poc/keycloak/setup-oidc-kubectl.sh    # kubelogin + ~/.karyon/oidc.kubeconfig
bash scripts/poc/keycloak/e2e-oidc-test.sh         # headless proof of the whole chain
```

Optional, for a warning-free browser: import `~/.karyon/oidc-pki/ca.crt` into
Windows *Trusted Root Certification Authorities* (`certmgr.msc`); otherwise
click through the self-signed warning at first login.

## 1. Web UI — Headlamp (CNCF; the official kubernetes/dashboard successor)

```bash
kubectl --context k3d-spoke-capsule -n capsule-system port-forward svc/headlamp 4466:80
```

Open **<http://localhost:4466>** → *Sign in* → Keycloak login (e.g. `bob`) →
you land in a dashboard whose every view is filtered by capsule-proxy: bob
sees tenant-alpha's workloads, events, logs, and an in-browser shell for his
pods — and literally nothing else. alice sees all three tenants.

How it works (why you can trust it): Headlamp holds NO cluster privileges
(zero-RBAC ServiceAccount) — it forwards *your* Keycloak token as the bearer
on every API call to capsule-proxy. Log out/in as a different user and the
same UI is a different cluster.

## 2. Terminal — kubectl with OIDC (kubelogin)

```bash
export KUBECONFIG=~/.karyon/oidc.kubeconfig
kubectl auth whoami           # first call opens the browser for Keycloak login
kubectl get namespaces        # tenant-scoped LIST via capsule-proxy
kubectl -n tenant-alpha get pods,deploy,svc
```

- Token cache: `~/.kube/cache/oidc-login` (delete it to force a fresh login;
  do this after group-membership changes — groups are read from the token).
- WSL browser handoff: install `wslu` (`sudo apt install wslu`) so the login
  URL opens in the Windows browser, or copy the printed URL manually.
- The old TokenRequest path (`issue-tenant-kubeconfig.sh` /
  `issue-platform-owner-kubeconfig.sh`) still works and remains the
  no-IdP-needed fallback + the demo runbook's path.

## 3. Keycloak administration (users, groups, tenants)

### Admin console

```bash
# credentials (operator-generated; replace with a permanent admin for real use):
kubectl --context k3d-spoke-capsule -n keycloak get secret keycloak-initial-admin \
  -o jsonpath='{.data.username}' | base64 -d; echo
kubectl --context k3d-spoke-capsule -n keycloak get secret keycloak-initial-admin \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

Open **<https://localhost:31443/admin>** (via the forwarder; or port-forward
`svc/keycloak-service 8080:8080` for plain http) → log in → switch the realm
dropdown (top-left) from *master* to **karyon**.

### Create a user (Keycloak 26 click-path)

1. **Users → Create new user** — set *Username* (+ Email, First name,
   **Last name — required**: the default user profile mandates it, and a
   missing one blocks logins with "Account is not fully set up").
   Toggle **Email verified ON** (same reason). → *Create*.
2. **Credentials tab → Set password** — *Temporary ON* forces a password
   change at first browser login (works with kubelogin/Headlamp flows);
   *Temporary OFF* for lab/service users.
3. **Groups tab → Join Group** — pick the group(s). Membership takes effect
   on the user's NEXT token (log out/in, or clear the kubelogin cache).

### Create a group

**Groups → Create group** — name it FLAT (e.g. `tenant-charlie-devs`), never
nested: the client group mappers emit bare names (*Full group path* OFF) and
Capsule exact-matches them. A `/parent/child` path will silently never match.

### Scriptable alternative (kcadm — no secrets leave the cluster)

```bash
kc() { kubectl --context k3d-spoke-capsule exec -n keycloak keycloak-0 -- bash -c \
  '/opt/keycloak/bin/kcadm.sh "$@" --no-config --server http://localhost:8080 \
   --realm master --user "$KC_BOOTSTRAP_ADMIN_USERNAME" --password "$KC_BOOTSTRAP_ADMIN_PASSWORD" 2>/dev/null' -- "$@"; }

kc create groups -r karyon -s name=tenant-charlie-devs
kc create users  -r karyon -s username=carol -s enabled=true \
  -s firstName=Carol -s lastName=Chen -s email=carol@karyon.local -s emailVerified=true
uid=$(kc get users -r karyon -q username=carol -q exact=true --fields id | sed -n 's/.*"id" : "\([^"]*\)".*/\1/p')
gid=$(kc get groups -r karyon -q search=tenant-charlie-devs | sed -n 's/.*"id" : "\([^"]*\)".*/\1/p' | head -1)
kc update "users/${uid}/groups/${gid}" -r karyon -s realm=karyon -s userId="${uid}" -s groupId="${gid}" -n
kc set-password -r karyon --userid "${uid}" --new-password 'ChangeMe-please' --temporary
```

(`-q exact=true` matters — username queries are substring matches by default.
Clients are addressed by UUID, not clientId: resolve with
`kc get clients -r karyon -q clientId=<id> --fields id` first.)

## 4. New tenant identity contract (the triple)

When a new tenant is born (e.g. `charlie` via
`scripts/poc/capsule/new-tenant.sh charlie`), THREE things make its devs work
— the script + realm already handle most of it:

1. **Keycloak group** `tenant-charlie-devs` — day-2 (UI or kcadm, above); the
   realm import is import-once and cannot add it retroactively.
2. **Capsule user scope** — append `tenant-charlie-devs` to
   `spec.userGroups` in `pocs/capsule/spoke/config/capsuleconfig.yaml` and
   push (Flux propagates ≤5m; never patch live — Flux reverts it). Required:
   a Group promoted to Tenant owner must be in the scope.
3. **Tenant owner** — `new-tenant.sh` now renders
   `{kind: Group, name: tenant-charlie-devs, clusterRoles: [tenant-workload-editor]}`
   automatically (alpha/bravo were amended the same way).

Then onboard users into the group (step 3 above). Nothing else — no
RoleBindings, no kubeconfigs to mint: identity IS the group.

## 5. What's proven vs what's manual

`scripts/poc/keycloak/e2e-oidc-test.sh` proves the full machine chain
headlessly (password-grant test client `karyon-e2e`, aud=kubectl; never the
production `kubectl` client). `tests/bats/keycloak-05-live-oidc.bats` guards
the wiring (6 live checks). The browser click-throughs (Headlamp sign-in,
kubelogin's browser hop) are the only untested-by-machine legs — they follow
the official Headlamp/Keycloak tutorials exactly.

## 6. IDE / web terminal (documented pattern, not deployed)

For a code-server ("VS Code in the browser") per tenant: single-user by
design, so it is one instance PER TENANT, fronted by **oauth2-proxy** (CNCF
Sandbox) against the same realm with `--allowed-group=tenant-<x>-devs`, and a
kubeconfig inside pointing at capsule-proxy so the integrated terminal doubles
as the tenant web terminal. Honest production note: a shared code-server can
NEVER enforce tenant identity (one Unix user, one filesystem); per-tenant
instances are the floor, and real multi-user IDE platforms mean Coder or
Eclipse Che. Headlamp's built-in pod shell covers the "quick exec" need
today, which is why code-server is parked rather than shipped.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `Account is not fully set up` | Missing last name or unverified email on the user (Keycloak 26 default profile) — fix in Users → detail |
| `tls: unknown certificate authority` **from the proxy** | Your kubectl merged a client cert from another kubeconfig context — use `KUBECONFIG=~/.karyon/oidc.kubeconfig` exactly |
| Browser warns about the cert at :31443 | Self-signed karyon OIDC CA — import `~/.karyon/oidc-pki/ca.crt` into Windows Trusted Root, or click through |
| Login works but view is empty | User not in any owner group, or group not in `userGroups` scope, or stale token — rejoin group + clear `~/.kube/cache/oidc-login` |
| Everything broke after `k3d cluster delete` + recreate | The imperative layer died with it — rerun §0 (the git side self-restores via Flux) |
| Platform-owner `kubectl get pods -A` via proxy is EMPTY (per-namespace LISTs work) | Pods were recreated while Capsule's webhooks were down (e.g. during a node restart) and silently missed the `capsule.clastix.io/managed-by` label — the proxy's rewritten labelSelector then matches nothing. Fix: `kubectl -n <tenant-ns> delete pods -l app=<x>` with the controller up; recreated pods get stamped. Same failure class as the namespaces-webhook cold-bootstrap deadlock (assignment webhook is `failurePolicy: Ignore`) |
