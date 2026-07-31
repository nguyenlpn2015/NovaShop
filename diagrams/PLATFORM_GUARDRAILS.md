# Platform Guardrails

Sprint 5.0 diagrams. Every gate shown here is enforced by a workflow, a script,
or a repository ruleset. Nothing in this document depends on an operator
remembering a procedure.

## Architecture

```text
                        ┌──────────────────────────────┐
                        │        GitHub (control)       │
                        │                              │
   NovaShop  ───────────┤  ruleset: protect-main       ├────────  NovaShop-GitOps
   (source, chart,      │  required status checks      │          (desired state)
    edge manifests,     │  linear history, no force    │
    scripts, workflows) │  push, no deletion           │
        │               └──────────────┬───────────────┘                │
        │                              │                                │
        │  validation.yml (reusable)   │   validation.yml (cross-repo)   │
        └──────────────┬───────────────┴────────────────┬───────────────┘
                       │                                │
                       ▼                                ▼
            ┌──────────────────────┐        ┌──────────────────────────┐
            │ scripts/             │        │ revision durability:     │
            │ validate-platform.sh │        │ every NovaShop pin is a  │
            │                      │        │ SHA reachable from main  │
            │ yamllint             │        └──────────────────────────┘
            │ kustomize build      │
            │ helm lint + template │
            │ kubeconform (+CRDs)  │
            └──────────┬───────────┘
                       │ passed
                       ▼
            ┌──────────────────────┐
            │ release.yml          │  build → scan → push :<sha>
            │                      │  then promote :latest
            └──────────┬───────────┘
                       │
                       ▼
                     GHCR
                       │  immutable :<sha> referenced by GitOps
                       ▼
   ┌───────────────────────────────────────────────────────────────┐
   │                     Ubuntu 22.04 + k3s node                    │
   │                                                                │
   │   Argo CD ──► ApplicationSet ──► novashop-{dev,staging,prod}    │
   │      │                                                         │
   │      ├──► novashop-cert-manager ──► cert-manager               │
   │      └──► novashop-certificates ──► Certificate ──► TLS Secret │
   │                                                                │
   │   Traefik  entrypoints: web (80), websecure (443)              │
   └───────────────────────────────────────────────────────────────┘
                       │
                       ▼
              public DNS  *.novashop.smartdev.vn
```

## Bootstrap Flow

Bootstrap is rerunnable at any point. Each step either observes that the desired
state already holds or converges toward it; no step assumes a clean node.

```text
scripts/linux/bootstrap.sh
  │
  ├─ pending reboot?  ─────────────────────► abort before touching packages
  │     (checked first, so an upgrade this run performs cannot abort the rerun)
  ├─ install packages                        idempotent
  ├─ system upgrade                          only when ENABLE_SYSTEM_UPGRADE=true
  ├─ swap active?  ───────────────────────► abort
  ├─ firewall                                only when ENABLE_UFW=true
  ├─ repositories reachable?  ────────────► abort
  │
  ├─ install-k3s.sh          pinned version; refuses an unexpected version
  │                          unless ALLOW_K3S_UPGRADE=true
  ├─ install-helm.sh         pinned + SHA-256 verified; exits early if present
  ├─ wait for Traefik rollout
  ├─ install-argocd.sh       manifest digest verified against
  │                          argocd/install-manifest.sha256
  │
  └─ scripts/bootstrap.sh
        ├─ Kubernetes >= 1.33
        ├─ apply AppProject + root Application   (server-side apply)
        ├─ wait ApplicationSet, per-environment Applications, namespaces
        ├─ runtime Secret per environment
        │     exists and complete  ─► keep
        │     exists, key missing  ─► abort with remediation
        │     absent               ─► create from *_DATABASE_URL / *_REDIS_URL
        ├─ resolve_edge_expectations
        │     reads the reconciled edge phase from the Application
        │     operator expectation disagrees with Git  ─► abort
        │     asserts Traefik web + websecure entrypoints
        ├─ wait Deployments Available, Applications Synced/Healthy
        ├─ every environment reconciles the same phase  (otherwise abort)
        └─ TLS phase active?
              ├─ wait cert-manager, ClusterIssuer Ready
              └─ wait Certificate Ready per environment
        │
        └─ verify.sh, driven by the detected phase
              enforced │ baseline │ http
```

## Release Flow

```text
push to main
  │
  ▼
release.yml
  │
  ├── job: validate  (uses .github/workflows/validation.yml)
  │      ├─ Backend           ruff + pytest
  │      ├─ Frontend          eslint + tsc + build
  │      ├─ Container Images  build only, no publish
  │      ├─ Security          Trivy fs: vuln, misconfig, secret (CRITICAL/HIGH)
  │      └─ Platform          validate-platform.sh across both repositories
  │            │
  │            └─ any failure ──────────► nothing is published
  ▼
  ├── job: publish  (matrix: backend, frontend; fail-fast)
  │      ├─ build with load: true          image exists only locally
  │      ├─ Trivy image scan               CRITICAL/HIGH ─► fail, nothing pushed
  │      ├─ log in to GHCR
  │      └─ push ghcr.io/…:<commit-sha>    with provenance + SBOM
  │            │
  │            └─ one component fails ────► fail-fast cancels the other,
  │                                          promote never runs
  ▼
  └── job: promote  (needs: publish, so both components succeeded)
         └─ imagetools create :latest ← :<commit-sha>
               registry-side manifest copy; nothing is rebuilt

Result: :latest can only ever reference a commit whose code, desired state, and
image all passed. A half-released pair is impossible.
```

## GitOps Flow

```text
NovaShop change                        NovaShop-GitOps change
      │                                        │
      ▼                                        ▼
  pull request                            pull request
      │                                        │
      │ ci.yml ─► validation.yml               │ validate.yml ─► validation.yml
      │            caller: application         │                  caller: gitops
      │                                        │
      │  checks out GitOps@main                │  checks out NovaShop@main
      │  renders desired state                 │  renders desired state
      ▼                                        ▼
      └────────────► same script, same rules ◄─┘
                     scripts/validate-platform.sh
                            │
      ┌─────────────────────┴─────────────────────┐
      │ yamllint on tracked YAML                   │
      │ kustomize build: in-cluster, ubuntu-k3s,   │
      │                  every phase               │
      │ ApplicationSet source invariants:          │
      │   exactly one chart source                 │
      │   exactly one values reference             │
      │   exactly one edge source, correct path    │
      │   a single pinned application revision     │
      │ helm lint + template per environment,      │
      │   base values and target overlay           │
      │ kubeconform against Kubernetes + CRDs      │
      │ revision durability + image traceability   │
      └─────────────────────┬─────────────────────┘
                            │ pass
                            ▼
                   ruleset protect-main
                   required checks satisfied
                   linear history, squash merge
                            │
                            ▼
                    merge to GitOps main
                            │
                            ▼
                Argo CD reconciles automatically
                self-heal, prune, bounded retry
```

### Rollback Ladder

Each rung is a reviewed Git revert in `NovaShop-GitOps`. The ladder is ordered by
blast radius, and the first rung is the default.

```text
tls-enforced     HTTPS required, HTTP redirects, HSTS max-age=31536000
     │
     │  revert  ── certificates untouched, no ACME issuance
     ▼
tls-baseline     HTTPS served, HTTP answers, HSTS max-age=0
     │           ROLLBACK TARGET
     │
     │  only after browsers have seen max-age=0
     ▼
http             no TLS at all; prunes Certificate resources
                 BREAK-GLASS ONLY. Back up certificate material first.
```

## Recovery Flow

```text
scripts/linux/recover.sh --from-backup DIR
  │
  ├─ preconditions, all reported together
  │    ├─ platform environment file: present, root-owned, mode 0600,
  │    │    declares DATABASE_URL and REDIS_URL
  │    ├─ NovaShop and NovaShop-GitOps reachable
  │    ├─ public DNS resolves every environment host
  │    └─ certificate backup present
  │         or --accept-certificate-reissue given explicitly
  │              (Let's Encrypt: 5 duplicate certificates per host set per week)
  │    │
  │    └─ any unmet ──────► abort before k3s is touched
  │
  ├─ install-k3s.sh          fresh cluster on the replacement node
  ├─ install-helm.sh
  ├─ wait for Traefik
  ├─ install-argocd.sh       digest-verified control plane
  │
  ├─ restore-platform-state.sh          ◄── ordering is the point
  │    creates namespaces, restores ACME account key and TLS Secrets
  │    BEFORE cert-manager reconciles, so cert-manager adopts the existing
  │    certificates instead of requesting new ones
  │
  ├─ scripts/bootstrap.sh    reconciles all desired state from Git
  │
  └─ verify.sh               phase detected from the cluster, not assumed
```

What recovery reproduces from Git: namespaces, workloads, services, ingresses,
middlewares, cert-manager, `Certificate` resources, and the Argo CD projects and
applications.

What recovery cannot reproduce and therefore restores: the TLS private keys and
the ACME account key.

What recovery treats as pre-existing infrastructure: public DNS records and the
runtime database and Redis endpoints.
