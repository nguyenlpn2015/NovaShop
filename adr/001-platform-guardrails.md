# ADR 001: Platform Guardrails

## Status

Accepted

## Date

2026-07-31

## Context

NovaShop reached a state where production served public HTTPS with HSTS through
Argo CD, Traefik, and cert-manager, while none of the delivery controls the
documentation described were actually enforced. A review found four conditions
that could each take production down with no prior warning.

The desired state in `NovaShop-GitOps` pinned the NovaShop Helm chart and the
edge manifests to commits that existed only on unmerged feature branches.
Deleting such a branch, which is ordinary hygiene after a merge, would have made
those commits unreachable. Argo CD could then no longer resolve
`targetRevision`, so every environment plus cert-manager and the certificates
would have stopped rendering, and recovery on a replacement node would have been
impossible.

The release workflow and the CI workflow both triggered on pushes to `main` with
no dependency between them. A commit that failed Ruff, pytest, ESLint, or the
Trivy scan still published both an immutable commit tag and the moving `latest`
tag. Release also rebuilt the images under a different BuildKit cache scope, so
the published artifact was never the artifact CI had examined.

Both repositories documented that every deployment and rollback happens through
a reviewed pull request, and both shipped a `CODEOWNERS` file, but neither had
branch protection. Direct pushes to the default branch succeeded and `CODEOWNERS`
was advisory only.

The documented rollback target was the HTTP-only GitOps phase. Because
production already advertised `Strict-Transport-Security: max-age=31536000`,
that rollback would have failed hard for returning browsers instead of degrading
gracefully. It would also have removed the certificate resources from the
desired state, and with `prune: true` Argo CD would have deleted them. Let's
Encrypt permits five duplicate certificates per identical hostname set per 168
hours, so a small number of rollback cycles could have left production without a
usable certificate for up to a week.

## Decision

Sprint 5.0 adds enforced guardrails and changes no application behaviour.

Cross-repository revisions are validated by machine. Every `targetRevision` that
references the NovaShop repository must be a forty-character commit SHA that is
an ancestor of the NovaShop default branch, every environment must deploy
backend and frontend from a single source commit, and every referenced image tag
must exist in the registry.

Validation is defined once, in `scripts/validate-platform.sh`, and is executed
identically from a workstation, from NovaShop CI, and from the NovaShop-GitOps
pull request workflow. A reusable GitHub Actions workflow calls that script so
the release job graph contains validation as a dependency. Publishing therefore
cannot race validation; it is prevented structurally rather than by timing.

Images are built and scanned before the registry sees them, and the moving
`latest` tag is created in a separate job that requires every component to have
published successfully.

The rollback target becomes a TLS-preserving phase. cert-manager, the
`Certificate` resources, and HTTPS routing stay in place; only enforcement is
released, and `Strict-Transport-Security: max-age=0` is served so browsers drop
the pin they were previously given. The HTTP-only phase is retained as a
documented break-glass path only.

Certificate private keys and the ACME account key are backed up and restored
explicitly, because they are the only platform state Git cannot reproduce.

Branch protection is expressed as reviewed ruleset JSON in `.github/rulesets`
and applied by a script that first confirms each required status check has
actually been reported.

Required approving reviews are set to zero. The repository has a single
maintainer, so any non-zero count would make every pull request unmergeable and
the practical response would be an admin bypass, which removes the control
entirely. The enforced controls are the full status check set, linear history,
no force push, no branch deletion, and conversation resolution. In a team
setting this value becomes at least one together with code owner review, and
nothing else about the configuration changes.

## Alternatives Considered

**Gating release on CI with `workflow_run`.** This serialises the two workflows
but keeps them as separate graphs, so the gate depends on correctly interpreting
another workflow's conclusion and on resolving the right commit. A reusable
workflow makes the dependency an edge in one graph, which cannot be
misinterpreted.

**Duplicating validation steps inside the release workflow.** Rejected because
two definitions of the same gate drift, and the GitOps repository would have
needed a third copy.

**Pushing the commit tag first and scanning afterwards.** Simpler, but it
publishes an artifact before it is known to be acceptable. The chosen order
builds into the local daemon, scans, and only then publishes, accepting one
extra cache-backed build pass so that provenance and SBOM attestations are still
produced by the registry exporter.

**Adding gitleaks for secret scanning.** Rejected as redundant. Trivy already
scans the filesystem for secrets, and GitHub secret scanning with push
protection blocks a secret at push time, which is earlier than any CI job can
act. Adding a third scanner would increase maintenance without adding coverage.

**Declaring Traefik configuration as a `HelmChartConfig`.** Deferred. It would
make edge settings reproducible after a node rebuild, which is genuinely
desirable, but it also mutates the live edge. Sprint 5.0 asserts the entrypoint
contract instead and leaves the declaration to a change whose only purpose is
that mutation.

**Signing images with cosign.** Deferred. Provenance and SBOM attestations are
already emitted, and the stated release requirement is satisfied by gating
publication. Signing is worth doing on its own merits, not as an unreviewed
addition to a guardrail sprint.

**Keeping the HTTP-only phase as the rollback target and disabling HSTS first.**
Rejected because it requires a successful change to production during an
incident before the rollback can begin, which is exactly when that is least
likely to succeed.

## Consequences

A pull request cannot be merged while the desired state fails to render, while a
pinned revision is not durable, or while an image tag is missing from the
registry. This blocks some changes that would previously have merged, which is
the intent.

Adopting a new Argo CD release now requires updating a pinned digest in
`argocd/install-manifest.sha256` in the same reviewed change, otherwise
bootstrap refuses to install.

The edge phase is no longer passed to bootstrap through environment variables.
It is read from the reconciled Application, so bootstrap and recovery both work
in whatever phase Git declares, including after a rollback. An operator
expectation that disagrees with Git now stops the run instead of being silently
overridden.

Destroying a cluster that holds TLS Secrets requires an explicit
acknowledgement, so teardown takes one more deliberate step.

Validation requires yamllint, Helm, Kustomize, and kubeconform, and the CRD
schema catalog must be reachable. Schema validation can be skipped explicitly
when it is not.

`latest` moves one job later than before, after both components have published.

## Validation

```bash
bash scripts/validate-platform.sh --gitops-dir ../NovaShop-GitOps
bash scripts/apply-branch-protection.sh \
  --repo nguyenlpn2015/NovaShop \
  --ruleset .github/rulesets/novashop-main.json
```

The first command must report `RESULT: PASS`. The second must report every
required status check as observed before it is run with `--apply`.

Guardrail-by-guardrail evidence is recorded in
[the validation checklist](../docs/guardrails/validation-checklist.md).
