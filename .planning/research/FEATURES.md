# Feature Research

**Domain:** Local multi-cluster Kubernetes lab (k3d + Flux hub-spoke + WSL2 + optional GPU spoke)
**Researched:** 2026-04-22
**Confidence:** HIGH

---

## Executive Summary

The public-repo feature surface for a Flux hub-spoke k3d lab is surprisingly consistent. The **canonical reference** is `fluxcd/flux2-hub-spoke-example` (41 stars, official, Apache-2.0). It ships four things the starter's Taskfile already covers conceptually (`fleet-up`/`fleet-down` ≈ `create-clusters`/`destroy`, `validate`, a GHA `test` + `e2e` workflow, and hub/spoke Kustomize overlays with podinfo + cert-manager + ingress-nginx as sample workloads). The starter's feature list is **~90% complete** against the canonical reference; the gaps are narrow but real.

**The two meaningful gaps to flag for the downstream requirements document:**

1. **No CI loop.** `PROJECT.md > Out of Scope` explicitly defers "CI/CD pipeline — local dev loop only; GitHub Actions integration deferred." This is a **defensible defer** (the lab is single-author), but it is the #1 feature every public Flux example ships, and it is the cheapest insurance against bit-rot in scripts and manifests. Recommend revisiting before the repo goes public — a 30-line `shellcheck` + `kubeconform` workflow is the minimum credible public-repo contract. Flagged as differentiator.
2. **`.env.example` is mentioned but no validation/linting of the secrets contract is described.** The starter says "gitignored `.env` + `.env.example`" and defers real secret management. That is honest and fine for v1. But "is the user's `.env` populated before bootstrap?" should be a `task preflight` check, and the canonical public-repo pattern adds `.gitleaks` or equivalent. Flagged below.

The **anti-features** (Flagger, ArgoCD, GPU Operator, kube-prometheus-stack, cloud clusters, image automation, HA, real secret management) are all already correctly excluded by `PROJECT.md > Out of Scope` with reasons. No scope creep to push back on.

**Observability answer:** Public labs ship either (a) nothing beyond `kubectl get` / `flux get` / `flux events` / `k9s` (user installs locally), or (b) a full kube-prometheus-stack. There is no meaningful middle ground. Since the starter pins tools via `asdf`, adding `k9s` to `.tool-versions` is a ~2-line change that buys real UX leverage. Full observability stack correctly stays out of v1.

**Secrets answer:** For a public repo shipping v1 as "placeholder only," the minimum credible pattern is `.env` + `.env.example` + `.gitignore` entry + a preflight check that `.env` exists and contains the required keys. That matches what the starter says. SOPS + age is the right *next* milestone for real secret material — flagged as v2 differentiator, not v1 gap.

---

## Feature Landscape

### Table Stakes (Without These The Lab Is Broken)

Every public Flux k3d/Kind lab ships these; their absence makes the repo feel broken or unusable on fresh clone.

| Feature | Why Expected | Complexity | In Starter? | Notes |
|---|---|---|---|---|
| Idempotent `create-clusters` / `destroy` | Re-runs must not require manual cleanup or the lab traps the user | SMALL | YES (`task create-clusters`, `task destroy`) | Starter explicit about re-run safety. |
| Confirmation prompt on destructive ops | `task destroy` / `task rebuild` wipe local state — accidental invocation from shell history is the #1 local-lab footgun | TRIVIAL | YES | Starter: "Destructive tasks explicitly named and require confirmation." |
| Preflight / environment gate | "Works on my machine but not yours" is the dominant failure mode for WSL2 + GPU labs; read-only preflight catches it at the door | MEDIUM | YES (`task preflight` → `scripts/preflight.sh`) | `prereqs.sh` already exists — port, don't rewrite. |
| Pinned tool versions | Flux/kubectl/k3d version drift silently breaks bootstraps; unpinned = lab rots | SMALL | YES (`.tool-versions` via asdf) | Starter locks this in ADR-008. |
| Pinned k3s/cluster image | Kubernetes minor-version skew vs. Flux controllers = broken CRDs | TRIVIAL | YES (`rancher/k3s:v1.34.6-k3s1`) | Justified in ADR-005. |
| `flux bootstrap` path documented as "do-not-hand-edit" | Users who edit `flux-system/` see changes reverted and think Flux is broken | TRIVIAL | YES | Starter explicitly calls this out. |
| Sample workload proving the pipe works end-to-end | Without a demo app, "is Flux actually reconciling?" has no visible answer | SMALL | YES (podinfo on spoke-apps) | Podinfo is the de facto standard — `fluxcd/flux2-hub-spoke-example` uses it too. |
| Health-check task | Green/red signal after rebuild or DNS fix — without it users don't know whether lab is healthy | SMALL | YES (`task health-check`) | Starter checks clusters, nodes, Flux controllers, spoke Kustomizations, DNS resolution. |
| README covering fresh-clone walkthrough | Anyone (including the author in 6 months) needs a single path from clone → working lab | SMALL | YES | Acceptance criteria enumerate the eight required sections. |
| `.gitignore` for `.env` and kubeconfigs | Public repo + accidental secret commit = credential rotation Saturday | TRIVIAL | YES (implied by "repo safe to publish publicly") | Worth making explicit that kubeconfigs and rendered secrets are gitignored too. |
| `.env.example` contract | Documents what the user must substitute; makes the repo reproducible | TRIVIAL | YES | Starter locks `GITHUB_OWNER` / `GITHUB_REPO` / `GITHUB_TOKEN`. |
| Teardown that actually cleans up | Orphan Docker networks + dangling containers accumulate on rebuild loops | SMALL | YES (destroys clusters + `k8s-net`) | Intentionally preserves build cache — correct tradeoff for rebuild-time SLO. |

**Starter coverage of table stakes: 12/12.** No table-stakes gaps.

---

### Differentiators (What Separates A Good Lab From A Mediocre One)

Features that set the lab apart from the long tail of "I set up k3d once" blog posts. The starter already makes the right differentiator bets.

| Feature | Value Proposition | Complexity | In Starter? | Notes |
|---|---|---|---|---|
| **Sub-20-minute scorched-earth rebuild SLO** | Most public labs document "setup once"; a measured rebuild target forces engineering discipline (idempotency, cache preservation, parallelism) | MEDIUM | YES | Core Value. Build cache preservation on `destroy` is specifically motivated by this. |
| **GPU pass-through + device-plugin smoke test** | Almost no public lab ships a working consumer-GPU path end-to-end on WSL2; this is the main thing people can't replicate from blog posts | LARGE | YES (spoke-ml + device-plugin + `nvidia-smi` pod) | Scoping to `nvidia-smi` (not framework workloads) is correct — avoids PyTorch-nightly-for-sm_120 coupling. |
| **Hub-only Flux control plane with remote kubeconfigs** | Matches `fluxcd/flux2-hub-spoke-example`; less overhead than per-spoke Flux install | MEDIUM | YES (ADR-004) | Matches canonical reference. |
| **`fix-dns` / CoreDNS NodeHosts workaround** | Concrete, documented fix for the #1 "my lab died after restart" surprise on k3d | SMALL | YES (`task fix-dns`) | Specific to k3d's CoreDNS NodeHosts caching — real differentiator. |
| **Documented NAT-mode fallback for `networkingMode=mirrored`** | WSL2 mirrored mode edge cases with Docker custom networks are a known pit — having the fallback procedure written saves someone 2 hours | SMALL | YES (in Known Risks + constraints) | Matches real WSL2 guidance. |
| **ADRs for every locked decision** | Five committed ADRs turn "tribal knowledge" into auditable decisions; rare in homelab repos | SMALL | YES (5 ADRs enumerated) | Above bar for homelab repos; at bar for professional labs. |
| **All tasks idempotent + fail-fast + self-preflight** | Script hygiene that makes the lab forgiving — most homelabs don't bother | MEDIUM | YES | Starter: "Scripts preflight their own prerequisites." |
| **CUDA build cache preserved across `destroy`** | The 15-minute rebuild SLO is impossible without this; most labs naively `docker system prune` | TRIVIAL | YES | Explicitly called out — `task destroy` does NOT prune build cache. |
| **CI loop: shellcheck + kubeconform + markdownlint** | Standard for every public Flux example repo; catches script regressions and malformed manifests before user hits them | SMALL (~1 workflow file, ~50 lines) | **NO (out of scope)** | **Starter may have missed this.** See "Gaps" section. |
| **`flux check --pre` / `flux check` integrated into preflight or health-check** | Canonical way to verify Flux CLI can talk to cluster and controllers are healthy; one line | TRIVIAL | Partially (health-check covers controller readiness; not clear if `flux check` is invoked) | Worth flagging — `flux check` is the idiomatic Flux verification command. |
| **k9s pinned in `.tool-versions`** | Asdf already in use; adding k9s costs 1 line and buys a usable TUI the author will reach for reflexively | TRIVIAL | Unclear (starter says "kubectl, helm, flux, k3d, task, jq, yq"; k9s not listed) | **Likely worth adding.** See "Gaps" section. |
| **Architecture diagram (Mermaid, inline in README)** | The hub-spoke topology is hard to explain in prose; one Mermaid diagram beats three paragraphs | TRIVIAL | Unclear (starter specifies `docs/architecture.md` but not whether it has a diagram) | Cheap to add, high clarity payoff. Mermaid renders natively in GitHub. |
| **TROUBLESHOOTING.md separate from README** | Searchable, Google-indexable, keeps README short; `ahgraber/homelab-gitops-k3s` does this and it's the right call | SMALL | Unclear (starter lists `docs/rebuild-runbook.md` but not a TROUBLESHOOTING.md) | Could fold into rebuild-runbook.md; worth being deliberate about. |

---

### Anti-Features (Deliberately Not Built — Justified)

Features commonly added to Flux labs that would violate the v1 scope. All justified in `PROJECT.md > Out of Scope`, repeated here with external ecosystem context.

| Feature | Why It Gets Requested | Why Excluded From v1 | Alternative / When To Revisit |
|---|---|---|---|
| **Progressive delivery (Flagger)** | `stefanprodan/gitops-istio` makes it look easy; "canary deploys locally!" is seductive | Requires service mesh (Istio/Linkerd) + metrics (Prometheus) + real traffic generator; none of that is in scope and all of it blows the 20-min rebuild target. Lab has no "production" to canary toward. | Separate milestone *after* observability stack + service mesh are added. Or defer permanently — Flagger in a single-user homelab is cargo-cult. |
| **Flux image automation (`ImagePolicy`/`ImageUpdateAutomation`)** | Common in "real" GitOps examples; auto-bumps image tags via commits | Requires a registry Flux can watch + a git commit loop back to the repo; pointless for podinfo + a `nvidia-smi` CUDA image that never changes. Adds a controller set (`image-reflector-controller`, `image-automation-controller`) that isn't part of the default bootstrap. | Revisit when a real workload with its own release cadence exists. Renovate (see below) is a cheaper substitute. |
| **Renovate / Dependabot for Flux/Helm version bumps** | Public Flux repos often ship Renovate config to auto-bump Flux versions and Helm charts | Lab has ~3 Helm charts max (cert-manager optional, podinfo, device-plugin). Maintenance cost > value at this scale. | Add if/when v2 grows infrastructure surface (multiple charts, ingress controller, monitoring stack). |
| **kube-prometheus-stack / Grafana / Loki** | Public labs love showing graphs | 20-min rebuild SLO allergic to ~60s of extra Helm installs + ~500MB extra RAM; no alerts needed in single-user lab. `k9s` + `kubectl top` + `flux events` cover the actual observability need. | `fluxcd/flux2-monitoring-example` is the right reference when this is eventually added. Separate milestone. |
| **NVIDIA GPU Operator** | "It's the official NVIDIA way"; handles driver install + device plugin + MIG in one chart | Starter correctly picks the device-plugin-DaemonSet path first: simpler, fewer moving parts, driver is installed on the WSL2 host (Windows) not the cluster. GPU Operator expects in-cluster driver installation. | ADR-worthy decision if/when v2 needs MIG partitioning or GPU monitoring. |
| **ArgoCD** | ApplicationSet cluster generators are genuinely nicer for label-based multi-cluster targeting | Hard locked to Flux in ADR-003 for lab scope; 2-3 explicit Kustomizations is not a scaling problem. | Never in v1. Noted in ADR-003 with migration note. |
| **Cloud clusters (EKS/GKE/AKS)** | Portability is tempting | Blows cost + network assumptions; not the core value | Out of scope permanently for this lab. |
| **HA / multi-node spokes** | "Production realism" | k3d `--agents` adds minutes to rebuild; single-node is sufficient to demonstrate everything | Out of scope for v1. |
| **Real secret management (Vault / SOPS+age / ExternalSecrets / SealedSecrets)** | Public repo + Flux = "how do you handle secrets?" is the first reviewer question | `PROJECT.md > Out of Scope` defers to placeholder only. Defensible because v1 has no real secret material beyond a GitHub PAT (which lives only in `.env` + in-cluster via `flux bootstrap`). | **SOPS + age is the right choice when revisited** — native Flux support via `decryption.provider: sops`, no external infrastructure, age keys fit on one line in `.env`, keeps the repo public-safe. SealedSecrets is wrong choice for this lab (cluster-scoped keys, doesn't scale across spokes cleanly — see comparison [fredrkl](https://fredrkl.com/blog/mozilla-sops-vs-sealed-secret/)). ExternalSecrets needs a backing store (Vault/AWS SM/etc.) — over-engineered for a local lab. |
| **Full PyTorch / TensorFlow / CUDA workload** | "GPU but not framework workload?" is the obvious next question | RTX 5090 is Blackwell (sm_120); most PyTorch stable releases still need nightlies. Coupling the lab to PyTorch nightly availability would break reproducibility. | `nvidia-smi`-in-a-pod is the correct v1 scope. Separate milestone for framework workload once sm_120 stabilizes in stable PyTorch. |
| **Network policies / Pod Security Admission / RBAC hardening** | "Production hardening" checklist items | Single-user local lab; starter runs spokes with cluster-admin kubeconfigs (ADR-004). No multi-tenant concern. | Out of scope permanently for v1 lab mandate. |
| **Service mesh (Linkerd / Istio / Cilium)** | Perceived modernity | Zero workloads that need it; meshes add 200-500MB RAM and complicate rebuild | Out of scope for v1. |
| **Ingress + cert-manager + DNS** | `fluxcd/flux2-hub-spoke-example` ships these | Lab is WSL2-local; no external traffic, no real DNS, no real certs. Port-forward / `kubectl proxy` suffice. | Could be a v2 differentiator if the lab ever grows a real demo UI. |

---

## Feature Dependencies

```
task preflight
    └──gates──> task create-clusters
                    └──required-by──> task bootstrap-flux
                                          └──required-by──> task register-spokes
                                                                └──required-by──> task deploy-examples
                                                                                      └──enables──> task health-check

task destroy ──must-preserve──> docker build cache (CUDA image)
    └──required-by──> task rebuild

task fix-dns ──enhances──> task health-check (run when cross-cluster DNS fails post-Docker/WSL restart)

.env (gitignored) ──required-by──> task bootstrap-flux (GITHUB_OWNER/REPO/TOKEN)
    └──documented-by──> .env.example

.tool-versions ──required-by──> task preflight (asdf install)

scripts/install-docker.sh ──prerequisite-for──> task preflight (Docker daemon check)
scripts/install-nvidia-container-toolkit.sh ──prerequisite-for──> task preflight (GPU chain check)
scripts/install-tools.sh (asdf) ──prerequisite-for──> task preflight (tool presence checks)

images/Dockerfile.k3s-cuda ──required-by──> task create-clusters (spoke-ml uses custom image)
    └──must-cache-across──> task destroy → task rebuild
```

### Dependency Notes

- **`preflight` gates everything.** The existing `prereqs.sh` is read-only; `create-clusters` must refuse to run if preflight fails. This is the #1 friction-reduction lever for the lab.
- **`fix-dns` is not in the main rebuild chain** — it's a recovery task triggered by symptom (cross-cluster DNS resolution failure after Docker/WSL restart). It enhances `health-check` by being the documented remediation when health-check reports stale CoreDNS.
- **CUDA image cache preservation** is the single architectural constraint that makes the 20-min rebuild SLO achievable. Any future "make `destroy` more thorough" PR must respect this.
- **`register-spokes` depends on `bootstrap-flux`** — the flux-system namespace must exist on the hub to store kubeconfig secrets.
- **`deploy-examples` depends on `register-spokes`** — spoke Kustomizations reference the kubeconfig secret name via `spec.kubeConfig.secretRef`.

---

## MVP Definition

### Launch With (v1) — Starter's Current Feature Surface

Minimum viable lab. Every item below is already in the starter's locked feature set.

- [x] `task preflight` — env/resources/GPU chain/tool/port checks (port of existing `prereqs.sh`)
- [x] `task create-clusters` — idempotent creation of hub-flux + spoke-ml (GPU) + spoke-apps on shared `k8s-net`
- [x] `task bootstrap-flux` — `flux bootstrap github` on hub, path `clusters/hub-flux`
- [x] `task register-spokes` — SA + cluster-admin CRB + kubeconfig Secret per spoke
- [x] `task deploy-examples` — podinfo on spoke-apps, `nvidia-smi` pod on spoke-ml
- [x] `task fix-dns` — stop/start hub to refresh stale CoreDNS NodeHosts
- [x] `task health-check` — clusters, nodes, Flux controllers, spoke Kustomizations, cross-cluster DNS resolution
- [x] `task destroy` — confirmed teardown of clusters + `k8s-net`, preserving build cache
- [x] `task rebuild` — full scorched-earth chain, < 20 min with CUDA image cached
- [x] Five ADRs (WSL2+Docker, k3d-vs-Kind, Flux-vs-ArgoCD, hub-only-Flux, k8s-version-pin)
- [x] `.tool-versions` via asdf
- [x] `.env.example` with `GITHUB_OWNER`/`GITHUB_REPO`/`GITHUB_TOKEN`
- [x] README with Windows prereqs, WSL config, Docker install, NVIDIA setup, cluster creation, Flux bootstrap, spoke registration, teardown
- [x] Documented NAT-mode fallback for `networkingMode=mirrored`

### Should Add To v1 (Flagged Gaps — Low Cost, High Credibility Payoff)

Small items that bring the starter to parity with every public Flux example repo for < 1 hour of work.

- [ ] **Add `k9s` to `.tool-versions`** — 1 line, available via asdf, universal TUI for the clusters the lab creates. Filling a real UX gap.
- [ ] **Add a Mermaid hub-spoke diagram to `docs/architecture.md` (or inline in README)** — GitHub renders Mermaid natively; topology is hard to grok from prose alone. ~20 lines.
- [ ] **Invoke `flux check` in `task health-check`** — idiomatic Flux health verification, one line. Catches controller version drift the starter's current health-check doesn't.
- [ ] **`task preflight` should verify `.env` exists and contains required keys** — current preflight checks tools and ports but doesn't validate the secrets contract the bootstrap depends on. Fails late (at `flux bootstrap`) instead of early.
- [ ] **Add a minimum CI workflow** — `shellcheck` on `scripts/*.sh` + `kubeconform` on `clusters/**/*.yaml` + `markdownlint` on docs. See "Starter May Have Missed" below.

### Add After Validation (v1.x)

- [ ] **SOPS + age for real secrets** — when a secret beyond `GITHUB_TOKEN` actually exists in the lab
- [ ] **TROUBLESHOOTING.md separate from README** — when the rebuild-runbook outgrows its current scope
- [ ] **PR template + CONTRIBUTING.md** — when/if the repo attracts external contributors
- [ ] **Renovate bot for Flux/k3s/CUDA base version bumps** — low-effort ongoing maintenance tool

### Future Consideration (v2+)

- [ ] Service mesh (Linkerd preferred over Istio — lower footprint, simpler; only if a real workload needs it)
- [ ] kube-prometheus-stack on hub, scraping spokes — `fluxcd/flux2-monitoring-example` is the reference
- [ ] Real ML framework workload (PyTorch stable w/ sm_120 support once landed)
- [ ] Additional spoke (`spoke-dev`?) to exercise Flux's multi-target Kustomizations more rigorously
- [ ] Migration to per-spoke Flux if spoke count grows beyond 3 (hub-only topology stops scaling)

---

## Feature Prioritization Matrix

Scoped to the flagged v1 gaps only (existing starter features are already P1).

| Feature | User Value | Implementation Cost | Priority | Rationale |
|---|---|---|---|---|
| `k9s` in `.tool-versions` | HIGH | TRIVIAL | P1 | 1-line change; author will use it constantly. |
| Mermaid architecture diagram | MEDIUM | TRIVIAL | P1 | Makes README comprehensible on first read. |
| `flux check` in health-check | MEDIUM | TRIVIAL | P1 | Idiomatic, catches controller issues. |
| `.env` presence in preflight | HIGH | SMALL | P1 | Fails early, saves a debugging loop. |
| Minimum CI workflow (shellcheck + kubeconform + markdownlint) | HIGH | SMALL | **P1 or P2** | **P2 if staying truly local-only; P1 before repo is made public to external viewers.** |
| SOPS + age for secrets | LOW (v1 has no real secrets) | MEDIUM | P3 | Defer until real secret material exists. |
| TROUBLESHOOTING.md split | LOW | TRIVIAL | P3 | Fold into rebuild-runbook.md until size forces split. |
| kube-prometheus-stack | LOW (lab has no alerts, no multi-user) | LARGE | P3 | Violates rebuild SLO; add when observability is the milestone. |
| Flagger / progressive delivery | LOW | LARGE | P3 | Cargo-cult for single-user lab. |

---

## Competitor Feature Analysis

Closest public-repo comparables — what do they ship that karyon doesn't, and vice versa?

| Feature | `fluxcd/flux2-hub-spoke-example` (canonical, 41 stars) | `fluxcd/flux2-kustomize-helm-example` (official, heavy) | `ahgraber/homelab-gitops-k3s` (popular homelab) | **karyon starter** |
|---|---|---|---|---|
| **Cluster runtime** | Kind (3 clusters) | Kind (2 clusters) | k3s (bare metal) | **k3d (3 clusters)** |
| **Orchestrator** | Makefile | Makefile | Ansible + Taskfile | **Taskfile** |
| **Hub-spoke topology** | Yes | No (per-env) | No (single cluster) | **Yes** |
| **GPU support** | No | No | No | **Yes (spoke-ml, device-plugin, sm_120)** |
| **Sample app** | podinfo + cert-manager + ingress-nginx | podinfo + cert-manager + Envoy Gateway | Full homelab stack | **podinfo + GPU smoke** |
| **CI: validate manifests** | `kubeconform` via `make validate` + GHA | `kubeconform` GHA workflow | Pre-commit + GHA | **None (deferred)** |
| **CI: e2e spin-up** | Kind fleet in GHA | Kind cluster in GHA | N/A | **None** |
| **Shellcheck / shfmt** | No | No | Yes (pre-commit) | **None** |
| **Secrets** | Kubeconfig as K8s Secret only (no user secrets) | Not explicit | SOPS + age | **`.env` + `.env.example` placeholder** |
| **Observability stack** | `fluxcd/flux2-monitoring-example` is a separate repo | No | kube-prometheus-stack + Loki | **None (deferred, correct)** |
| **Flagger / progressive delivery** | No | No | No | **None (correctly excluded)** |
| **Image automation** | No | No | Yes (Renovate) | **None** |
| **Architecture diagram** | Yes (PNG in README) | No | Yes | **Unclear (docs/architecture.md listed, diagram not specified)** |
| **ADRs** | No | No | No | **Yes (5 ADRs)** |
| **Teardown task** | `make fleet-down` | No explicit | Ansible teardown | **`task destroy` + `task rebuild`** |
| **Preflight env check** | No | No | Partial (ansible roles) | **Yes (`prereqs.sh`)** |
| **Rebuild-time SLO** | Not measured | Not measured | Not measured | **Yes (< 20 min)** |
| **NAT-mode WSL2 fallback docs** | N/A (not WSL-specific) | N/A | N/A | **Yes** |
| **`fix-dns` equivalent** | No (Kind doesn't have this issue) | No | No | **Yes (k3d-specific)** |

**Where karyon stands out:** GPU pass-through, measured rebuild SLO, explicit ADRs, WSL2-specific hazards documented, k3d-specific CoreDNS workaround, preflight env gate. These are all real differentiators — none of the public references cover this terrain.

**Where karyon is missing what everyone else ships:** CI workflows (kubeconform + shellcheck). That's the one.

---

## Starter May Have Missed — Explicit Callout

**Downstream consumer (requirements.md) should decide whether to accept these as v1 additions or hold to the current locked scope:**

### 1. Minimum CI workflow (shellcheck + kubeconform + markdownlint)

**Status:** Explicitly deferred in `PROJECT.md > Out of Scope` ("CI/CD pipeline — local dev loop only; GitHub Actions integration deferred").

**Recommendation:** Reconsider before the repo goes public. The canonical `fluxcd/flux2-hub-spoke-example` ships a `test` workflow (kubeconform validation of all manifests against Flux OpenAPI) and an `e2e` workflow (Kind spin-up + Flux bootstrap integration test). Cost to match the `test` half: one GHA workflow file, ~50 lines. Catches: broken YAML, missing CRD references, drifted manifest schemas, regressed shell scripts. The `e2e` half is out of scope because GHA runners can't do GPU — but the non-GPU half is feasible.

**Why it matters even for a single-author public repo:** public-repo contract implies "the example works." A `kubeconform` CI run is the cheapest credible proof.

**If kept out of scope:** consider running `shellcheck scripts/*.sh` and `kubeconform` locally as part of `task preflight` or a new `task lint`. This at least gives the author a pre-commit safety net.

### 2. `flux check` not explicitly invoked in health-check

**Status:** Starter's `task health-check` checks "Flux controllers Ready on hub-flux" but doesn't call out `flux check` specifically.

**Recommendation:** `flux check` is the idiomatic way to verify Flux CLI ↔ cluster ↔ controllers ↔ CRD versions are all compatible. Add `flux check --pre` to preflight (verifies CLI + K8s API compatibility) and `flux check` to health-check (verifies installed controllers match CLI version). Cost: 2 lines.

### 3. `.env` presence + schema check missing from preflight

**Status:** Starter preflight checks tools, ports, docker, GPU chain — but doesn't validate `.env` exists or contains `GITHUB_OWNER` / `GITHUB_REPO` / `GITHUB_TOKEN`.

**Recommendation:** Add `.env` presence + required-keys check to `scripts/preflight.sh`. Current failure mode: user runs `task preflight` (passes), runs `task create-clusters` (passes), runs `task bootstrap-flux` (fails with cryptic auth error because `GITHUB_TOKEN` unset). Fail earlier.

### 4. `k9s` not in `.tool-versions`

**Status:** Starter lists "kubectl, helm, flux, k3d, task, jq, yq." No k9s.

**Recommendation:** Add `k9s` to `.tool-versions`. It's the canonical k8s TUI, available via asdf, and the author will use it reflexively. Trivial ergonomic win.

### 5. Architecture diagram format not pinned

**Status:** Starter lists `docs/architecture.md` but doesn't specify whether it contains a diagram.

**Recommendation:** Use Mermaid (renders natively in GitHub; source-controllable; no separate tool). The hub-spoke topology with 3 clusters + kubeconfig secrets + Kustomization arrows is inscrutable from prose. One Mermaid `architecture-beta` block is ~20 lines.

### 6. Explicit "nuke everything" escape hatch beyond `task destroy`

**Status:** `task destroy` deletes clusters + `k8s-net` but preserves build cache (correct for rebuild SLO).

**Recommendation:** Consider a separate `task nuke` (distinct from `destroy`) that wipes build cache + all dangling volumes + all k3d containers regardless of name. Users occasionally need to fully reset a corrupted Docker state (especially after WSL upgrades). Keep `task destroy` as the fast-path; `task nuke` as the emergency option. Requires extra confirmation.

### None of these are blockers for v1.

The starter is **comprehensive and opinionated**. The five gaps above are polish, not correctness issues. If the downstream requirements doc chooses to keep all of them out of scope, the lab still works end-to-end.

---

## Sources

**Canonical references (HIGH confidence):**
- [fluxcd/flux2-hub-spoke-example](https://github.com/fluxcd/flux2-hub-spoke-example) — official hub-spoke reference, 41 stars; Makefile + GHA test/e2e workflows + podinfo/cert-manager/ingress-nginx
- [fluxcd/flux2-kustomize-helm-example](https://github.com/fluxcd/flux2-kustomize-helm-example) — official multi-env example; kubeconform CI, podinfo, Envoy Gateway
- [fluxcd/flux2-monitoring-example](https://github.com/fluxcd/flux2-monitoring-example) — reference for when observability is eventually added
- [k3d docs: Running CUDA workloads](https://k3d.io/v5.7.4/usage/advanced/cuda/) — official GPU path for k3d
- [NVIDIA/k8s-device-plugin](https://github.com/NVIDIA/k8s-device-plugin) — device-plugin DaemonSet reference
- [Flux troubleshooting cheatsheet](https://fluxcd.io/flux/cheatsheets/troubleshooting/) — `flux check` + reconcile commands
- [Flux Multi-cluster Architecture (Stefan Prodan)](https://stefanprodan.com/blog/2024/fluxcd-multi-cluster-architecture/) — authoritative hub-spoke guidance

**Homelab references (MEDIUM confidence):**
- [ahgraber/homelab-gitops-k3s](https://github.com/ahgraber/homelab-gitops-k3s) — popular k3s + Flux homelab with TROUBLESHOOTING docs
- [HYP3R00T/homelab](https://github.com/HYP3R00T/homelab) — k3s + Flux + monitoring structure
- [gianniskt/k8s-gitops-chaos-lab](https://github.com/gianniskt/k8s-gitops-chaos-lab) — GitOps homelab with Flux + Linkerd + Prometheus (reference for anti-features)
- [ShadyF/k8s-homelab](https://github.com/ShadyF/k8s-homelab) — Flux + Renovate pattern

**Tooling + CI (MEDIUM confidence):**
- [yannh/kubeconform](https://github.com/yannh/kubeconform) — canonical manifest validator
- [DavidAnson/markdownlint-cli2-action](https://github.com/marketplace/actions/markdown-linting-action) — markdown lint GHA
- [setup-k3d GitHub Action](https://github.com/marketplace/actions/setup-k3d) — k3d-in-CI reference
- [jumanjihouse/pre-commit-hooks](https://github.com/jumanjihouse/pre-commit-hooks) — shellcheck + shfmt for pre-commit

**Secret management (HIGH confidence):**
- [getsops/sops](https://github.com/getsops/sops) — primary SOPS reference
- [Mozilla SOPS vs Sealed Secret (fredrkl)](https://fredrkl.com/blog/mozilla-sops-vs-sealed-secret/) — comparison informing v1.x recommendation
- [Managing secrets with SOPS in your homelab (codedge)](https://www.codedge.de/posts/managing-secrets-sops-homelab/) — homelab-scoped SOPS walkthrough

**Anti-feature context (MEDIUM confidence):**
- [stefanprodan/gitops-istio](https://github.com/stefanprodan/gitops-istio) — Flagger reference (why it's out of scope here)
- [Renovate Flux docs](https://docs.renovatebot.com/modules/manager/flux/) — Flux-aware dependency bot (deferred)
- [KiND vs K3d vs K0s (sanj.dev)](https://sanj.dev/post/kind-vs-k3d-vs-k0s) — runtime comparison supporting ADR-002

---

*Feature research for: Local multi-cluster Kubernetes lab (k3d + Flux hub-spoke + WSL2 + optional GPU spoke)*
*Researched: 2026-04-22*
