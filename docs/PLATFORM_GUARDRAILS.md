# Platform Guardrails

Sprint 5.0 makes the delivery contract enforceable. Before it, the contract was
documented but nothing prevented a violation: the default branches were
unprotected, no workflow rendered the desired state, and the release workflow
published images in parallel with the checks that were supposed to gate them.

These guardrails add no runtime technology and change no application behaviour.
They exist so that observability, which arrives in Sprint 5.1, can be deployed
into a platform where a bad change is stopped before it reaches the cluster.

## Toolchain

| Tool | Version | Used for |
|------|---------|----------|
| yamllint | 1.38.0 | YAML policy on tracked documents |
| Helm | v3.21.1 | Chart lint and render, installed by `scripts/linux/install-helm.sh` |
| Kustomize | v5.8.1 | Cluster overlay and phase builds |
| kubeconform | v0.7.0 | Kubernetes and CRD schema validation |
| Trivy | v0.36.0 action | Filesystem and image scanning |
| jq | distribution | Secret export and ruleset handling |
| GitHub CLI | distribution | Ruleset application |

`scripts/validate-platform.sh` prefers a standalone `kustomize` binary and falls
back to the Kustomize embedded in `kubectl`, so a workstation with only `kubectl`
can still run the full gate.

Run it locally before opening a pull request:

```bash
bash scripts/validate-platform.sh --gitops-dir ../NovaShop-GitOps
```

Set `SKIP_SCHEMA_VALIDATION=true` when the CRD schema catalog is unreachable.
Everything else works offline.

## A. GitOps Safety

| Guardrail | Where | Enforced by |
|-----------|-------|-------------|
| Protected default branch | both repositories | `.github/rulesets/*.json` |
| Required status checks | both repositories | ruleset, verified before it is applied |
| Linear history, no force push, no deletion | both repositories | ruleset |
| Conversation resolution, squash merge | both repositories | ruleset |
| YAML lint | both repositories | `validate-platform.sh` |
| Kustomize build of every overlay and phase | GitOps | `validate-platform.sh` |
| Helm lint and template per environment | both repositories | `validate-platform.sh` |
| Kubernetes and CRD schema validation | both repositories | `validate-platform.sh` |
| Secret scanning | both repositories | Trivy `secret` scanner, GitHub push protection |
| Cross-repository revision durability | GitOps | `validate-gitops-revisions.sh` |
| Runtime version alignment | application | `validate-platform.sh` |

### Revision durability

This is the guardrail that closes the most severe gap found in the review. Every
`targetRevision` referencing the NovaShop repository must be:

- a forty-character commit SHA, never a branch or tag;
- an existing commit;
- an ancestor of the NovaShop default branch.

The last rule is the important one. A pin that lives only on a feature branch
disappears when that branch is deleted, and Argo CD then cannot render any
environment, cert-manager, or the certificates. Bootstrap and disaster recovery
both fail, and nothing warns beforehand.

The same script also requires that each environment deploys backend and frontend
from one source commit, that no desired state references `latest`, and that every
referenced tag actually exists in GHCR. A missing tag is reported at review time
rather than as `ImagePullBackOff` after a merge.

### Runtime version alignment

Each language runtime is declared in three independent places: the base image
that ships to production, the version CI installs, and the constraint the package
manifest advertises. Nothing previously required them to agree.

That gap is not theoretical. The first Dependabot batch proposed raising the
frontend base image from Node 22 to Node 26 and the backend base image from
Python 3.12 to 3.14. Both pull requests passed every existing check, because CI
kept testing on the old runtime while the published image would have shipped the
new one. The divergence would only have surfaced in production.

The gate now requires the Node major to match across `frontend/Dockerfile`, the
workflow `NODE_VERSION`, `engines.node`, and `@types/node`, and the Python minor
to match across `backend/Dockerfile`, the workflow `PYTHON_VERSION`, and
`requires-python`. A runtime upgrade is still welcome; it simply has to move
every declaration in one reviewed change.

### ApplicationSet source invariants

Kustomize patches address Argo CD sources positionally. A patch written against
index `2` silently rewrites a different source if the source order changes, and a
mixed render would deploy the Helm chart from one commit and the edge manifests
from another. Every built phase is therefore asserted to contain exactly one
chart source, one values reference, and one edge source at the directory that
belongs to that phase, all pinned to a single revision.

## B. Release Safety

An image is published only for a commit that passed application tests, the
security scan, and platform validation. This is structural, not a matter of
ordering in time: `release.yml` declares the validation workflow as a job
dependency, so publication cannot begin until validation has completed
successfully in the same job graph.

Two further properties hold:

- **Nothing is published before it is scanned.** Each image is built into the
  local Docker daemon, scanned by Trivy for CRITICAL and HIGH vulnerabilities,
  and only then pushed. The push reuses the BuildKit cache from the scanned
  build so the published content is the scanned content, while the registry
  exporter still attaches provenance and SBOM attestations.
- **`latest` can never point at a failed or partial build.** It is created in a
  separate job that depends on the whole publish matrix, as a registry-side
  manifest copy of the commit tag. If either component fails, `fail-fast`
  cancels the other and promotion never runs.

Pushes to `main` no longer trigger `ci.yml`. Validation on `main` belongs to the
release graph, which removes the duplicate run and the race at the same time.

## C. Bootstrap Reliability

Bootstrap is safe to rerun on a working node, a clean VM, a rebuilt node, and
after a disaster.

**Supply chain.** The Argo CD installation manifest is downloaded and verified
against the digest pinned in `argocd/install-manifest.sha256`. Previously it was
applied straight from a URL with no verification, which made both the content and
the availability of a single host a dependency of every recovery. Adopting a new
Argo CD release now requires updating that digest in the same reviewed change.

**Rerun safety.** The pending-reboot check runs before any package operation. In
the previous order, `apt-get upgrade` could create `/var/run/reboot-required` and
the next line would abort the run because of a condition the script had just
produced. The upgrade is now opt-in through `ENABLE_SYSTEM_UPGRADE`, since a
distribution upgrade is neither idempotent nor appropriate during a recovery.

**Phase detection instead of assumption.** The active edge phase is read from the
reconciled Argo CD Application. `EXPECTED_EDGE_SOURCE_PATH` and
`ENABLE_TLS_VALIDATION` are now assertions: if either disagrees with what Git
reconciled, bootstrap stops. Previously the expectation lived in a script while
the truth lived in the GitOps repository, and the two could diverge silently.
Verification is configured from the detected phase, so a rerun after a reviewed
rollback validates the phase that is actually live.

**Traefik.** k3s owns Traefik and bootstrap does not modify it, but the public
edge depends on the `web` and `websecure` entrypoints. Their absence is now an
explicit error instead of a routing failure discovered later. Declaring Traefik
configuration as a `HelmChartConfig` is a deliberate follow-up, recorded in
[ADR 001](../adr/001-platform-guardrails.md), because it would mutate the live
edge.

**Runtime Secrets.** A Secret that exists but lacks `DATABASE_URL` or
`REDIS_URL` previously satisfied the presence check while leaving workloads
unable to start. Both keys are now verified.

## D. Recovery

`scripts/linux/recover.sh` rebuilds the platform on a replacement node. It checks
every precondition first and reports them together, so an operator fixes
everything in one pass instead of discovering one failure per attempt.

The material that Git cannot reproduce is handled explicitly:

```bash
# While the platform is healthy
bash scripts/backup-platform-state.sh --output-dir /srv/novashop-state

# On a replacement node
bash scripts/linux/recover.sh --from-backup /srv/novashop-state
```

Restoration happens after Argo CD is installed and before the GitOps root
application reconciles cert-manager. When cert-manager finds a Secret already
holding a valid certificate for the requested hostnames, it adopts it and
schedules a normal renewal instead of requesting a new one. Getting this order
wrong consumes Let's Encrypt issuance quota that a later rollback may need.

Recovering without a backup is supported but must be acknowledged with
`--accept-certificate-reissue`, because Let's Encrypt permits only five duplicate
certificates per identical hostname set per 168 hours.

For the same reason, `scripts/cleanup.sh` refuses to destroy namespaces that hold
TLS Secrets unless `--accept-certificate-loss` is given.

## Rollback

The rollback target is the TLS-preserving `tls-baseline` phase, not the HTTP-only
phase. Production advertises HSTS with a one-year `max-age`, so an HTTP-only
rollback would fail hard for returning browsers rather than degrade, and pruning
would delete the certificates.

`tls-baseline` keeps cert-manager, the `Certificate` resources, and HTTPS
routing. It releases enforcement and serves
`Strict-Transport-Security: max-age=0`, which actively clears the pin browsers
were given. Setting Traefik's `stsSeconds` to zero would omit the header and
leave the existing pin in place, so the header is set explicitly.

The full ladder is in
[the guardrail diagrams](../diagrams/PLATFORM_GUARDRAILS.md).

## Out of Scope

Prometheus, Grafana, Loki, Tempo, and OpenTelemetry belong to Sprint 5.1. Image
signing and the Traefik `HelmChartConfig` declaration are deferred with reasons
recorded in [ADR 001](../adr/001-platform-guardrails.md).

## Known follow-up

Resolved: the ACME `ClusterIssuer` resources now declare a contact address. Previously Let's Encrypt
cannot send expiry warnings and there is no account recovery contact. Adding one
requires a mailbox the team monitors and is left as an explicit decision rather
than an invented value.
