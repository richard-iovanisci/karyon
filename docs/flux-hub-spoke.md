# Flux Hub-Spoke Patch Surface

`scripts/bootstrap-flux.sh` runs `flux bootstrap github --path clusters/hub-flux` against
the `k3d-hub-flux` cluster. That single command creates (or reuses) the GitHub repo,
commits three files under `clusters/hub-flux/flux-system/`, installs the four Flux
controllers, and starts the self-reconciliation loop.

This document explains the three rules that govern hand-editing anything under
`clusters/hub-flux/flux-system/`. Rules 1 and 2 correct the starter's overly-broad
"do not hand-edit" guidance by naming the one file that IS the supported patch
surface. Rule 3 locks `--path` as a one-time decision.

## What `flux bootstrap` writes

On first invocation, `flux bootstrap github` commits three files under
`clusters/hub-flux/flux-system/`:

| File | Category | Hand-edit? |
|------|----------|------------|
| `gotk-components.yaml` | bootstrap-managed | **NO** — overwritten on every rerun |
| `gotk-sync.yaml` | bootstrap-managed | **NO** — overwritten on every rerun |
| `kustomization.yaml` | **patch surface** | **YES** — this is the supported edit point |

The bootstrap commit lands on the `main` branch of `$GITHUB_OWNER/$GITHUB_REPO`; Flux
reconciles it back into the cluster via the `flux-system` `Kustomization` resource
every minute.

## Local branch sync before first bootstrap

On first bootstrap, Flux writes the generated manifests through its own temporary Git
checkout and pushes them to `origin/main`. `scripts/bootstrap-flux.sh` then pulls that
remote commit into this checkout before adding the patch-surface marker.

Before running first bootstrap, local `main` must therefore be able to fast-forward from
`origin/main`. If local `main` has unpublished commits, push them first. If `origin/main`
already has commits this checkout does not have, merge or rebase them first. The script
checks this before invoking `flux bootstrap github` when the local bootstrap manifests
are still missing, so it does not mutate GitHub and then fail on a predictable
non-fast-forward pull.

If an older run already pushed Flux manifests and then failed locally, recover with:

```bash
git fetch origin main
git merge origin/main
bash scripts/bootstrap-flux.sh
```

After the marker is committed locally, push local `main` so Flux reconciles a Git tree
that contains `# FLUX PATCH SURFACE`.

## Rule 1: `gotk-components.yaml` and `gotk-sync.yaml` are bootstrap-managed

Do not hand-edit these files. `flux bootstrap` re-renders them from CLI flags on every
run; any hand-edits are silently reverted the next time the script runs. If you need to
change controller behavior (memory limits, image tags, annotations, replica counts, etc.),
apply the change via Rule 2.

## Rule 2: `kustomization.yaml` IS the supported patch surface

Hand-edits to `clusters/hub-flux/flux-system/kustomization.yaml` survive re-bootstrap.
`flux bootstrap` only rewrites this file when its `resources:` block diverges from what
the current CLI flag set would produce; the `patches:`, `configMapGenerator:`, `images:`,
and other Kustomize-native blocks you add here stay intact. The top-of-file
`# FLUX PATCH SURFACE` comment block that `scripts/bootstrap-flux.sh` prepends is part
of the same invariant.

Example — bump `kustomize-controller`'s memory limit from the default 1Gi default to an
explicit 1Gi declaration:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - gotk-components.yaml
  - gotk-sync.yaml
patches:
  - target:
      kind: Deployment
      name: kustomize-controller
      namespace: flux-system
    patch: |
      - op: replace
        path: /spec/template/spec/containers/0/resources/limits/memory
        value: 1Gi
```

To prove the patch survived re-bootstrap, run:

```bash
bash scripts/bootstrap-flux.sh
kubectl --context k3d-hub-flux -n flux-system get deploy kustomize-controller \
  -o jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}'
# Expected: 1Gi
```

## Rule 3: `--path` is effectively immutable after first run

`scripts/bootstrap-flux.sh` hard-codes `--path clusters/hub-flux`. Do not change it.

Changing `--path` on a subsequent run does NOT migrate your existing tree — it creates a
divergent bootstrap commit under the new path, orphans the old `flux-system/` tree, and
leaves the cluster reconciling from the new directory with no history continuity. There
is no documented migration path back. Treat the initial `--path` as a locked decision,
captured in code as a `readonly` bash constant in `scripts/bootstrap-flux.sh` and
enforced at test time by `tests/bats/bootstrap-flux-01-idempotent.bats` (the FLUX-02
test rejects any `FLUX_PATH="${FLUX_PATH:-...}"` override pattern).

> **Footnote (`--network-policy=false` rationale).** The bootstrap call also passes
> `--network-policy=false`. This disables Flux's default deny-all NetworkPolicy on
> `flux-system` because this is a single-user lab with no adversarial namespace
> boundary — NOT because k3s cannot enforce NetworkPolicies. k3s ships an embedded
> kube-router netpol controller, so any NetworkPolicy resources in the cluster ARE
> enforced; we simply choose not to install Flux's restrictive default. If a future
> milestone introduces multi-tenant or adversarial separation, revisit this flag.

## Rerun behavior

Rerunning `scripts/bootstrap-flux.sh` on an already-bootstrapped hub is a fast no-op.
The script's Section 2 three-part gate checks that the `flux-system` namespace exists,
`flux check` exits 0, and all four controller Deployments report `Available=True`; if
all three are true, it logs `already done, skipping: flux bootstrap` and proceeds
directly to post-bootstrap verification plus the patch-surface marker idempotency check.
`flux bootstrap github` is not invoked a second time.

<!-- Phase 4: hub-spoke reconciliation (spec.kubeConfig, <spoke>-kubeconfig Secrets, value.yaml key) -->
