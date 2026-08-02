# ADR 014: Terraform owns the GitOps seed, and stops there

## Status

Accepted. Completes the boundary set by [ADR 012](012-terraform-scope.md) and refined by
[ADR 013](013-terraform-kubernetes-boundary.md).

## Date

2026-08-02

## Context

[ADR 003](003-gitops-delivery.md) settled that the cluster reconciles itself from Git.
Something still has to create the object that starts that: Argo CD has to be installed, an
AppProject has to exist, and a root Application has to point at the desired-state repository.

Until now that was `scripts/linux/bootstrap.sh` calling `scripts/bootstrap.sh`, which applies
`argocd/project.yaml` and `argocd/application-ubuntu-k3s.yaml`. It works and it is
idempotent. What it lacks is a declarative statement of *what the handover should be*, and
any way to detect that it has drifted.

That gap matters more than it sounds. The root Application is the single object every other
thing in the cluster descends from. If it is pointed at the wrong repository, pinned to a
commit instead of tracking `main`, or has `selfHeal` turned off, the platform keeps running
and stops being GitOps — and nothing reports it. `kubectl get applications` shows
`Synced/Healthy` in all three cases.

Checking what Argo CD reconciles, as in ADR 013, gave the opening:

| Object | Tracking annotation | Reconciled |
|---|---|---|
| `appproject/novashop` | none | **No** |
| `application/novashop-root` | none | **No** |
| `appproject/novashop-platform` | `novashop-root:...` | Yes |
| `applicationset/novashop` | `novashop-root:...` | Yes |

The two objects that constitute the handover are exactly the two Argo CD does not reconcile.

## Decision

A `6-gitops` layer owns the seed and validates it. It is the last layer Terraform runs.

**Owns:** the Argo CD installation (version and digest as declarative inputs), the `novashop`
AppProject, the `novashop-root` Application, and repository registration Secrets for the two
public repositories.

**Validates, against the live cluster:** that the root Application tracks the expected
repository, revision, path, and project; that `selfHeal` and `prune` are both true; that
every registered repository is whitelisted by the AppProject; and that the running Argo CD
version matches the declared one.

**Hands over and stops.** Everything downstream — `novashop-platform`, the ApplicationSet,
the three environments, cert-manager, the TLS phases, the entire observability stack, every
Helm release — reconciles from Git and Terraform never touches it.

The installer and the handover run through the **existing scripts**, triggered on the hash of
Terraform's declared intent.

## Alternatives Considered

**`kubernetes_manifest` for the AppProject and root Application.** The version that looks
most like real Terraform. Rejected on a hard limitation: `kubernetes_manifest` **does not
support import**, and both objects already exist. Declaring them plans a create, the create
fails on conflict, and the only way through is to delete first — which for an Application
carrying `resources-finalizer.argocd.argoproj.io` cascades to everything it manages. The
failure mode for getting this wrong is deleting the platform.

**A third-party provider with import support**, such as `gavinbunney/kubectl`. Would solve
the import problem. Rejected because it adds a dependency to work around a limitation in the
official provider, for two objects, on a platform whose brief was explicitly not to add
technologies.

**Install Argo CD with the Helm provider instead of the pinned manifest.** Would give
Terraform genuine ownership of the installation rather than a triggered script. Rejected for
two reasons: it re-platforms a running Argo CD from manifest-install to Helm, which is a
migration with no rollback on a single node; and it discards the pinned SHA-256, replacing a
digest that makes substitution detectable with a chart version that does not.

**Reimplement the installer in HCL.** The script applies a multi-document manifest, waits for
three CRDs to become `Established`, waits for every Deployment to become `Available`, and
waits on a StatefulSet rollout. Terraform cannot express the CRD wait and would poll from a
provisioner regardless. Rejected as a rewrite of working code into a worse form.

**Let Terraform own the whole GitOps tree instead of Argo CD.** Discussed when the scope was
widened: Terraform creates all twelve Applications directly and the app-of-apps disappears.
Rejected in ADR 013 and rejected again here — it removes the two-merge review from
[ADR 003](003-gitops-delivery.md) and turns an image tag change into `terraform apply`
instead of a reviewable GitOps pull request.

**Register repositories with a `project` scope.** Rejected on a real hazard rather than
preference: scoping a repository to a project restricts every *other* project from using it,
which would break the `novashop-platform` Applications rendering from the same two
repositories. Unscoped registration matches today's behaviour exactly.

**Do not register repositories at all.** Defensible — both are public and clone anonymously,
so nothing needs it. Included because it is the declarative place credentials would go if
either repository became private, and because it makes the platform's source dependencies
explicit rather than implied.

## Consequences

**Easier.** The handover is now declarative and, more usefully, **checked**. The three silent
failures named in Context — wrong repository, pinned revision, `selfHeal` off — each now
produce a plan-time report naming the observed value. A rebuild is five `terraform apply`
invocations followed by waiting, rather than a script whose correctness is established by
reading it.

The Argo CD version and its manifest digest can no longer drift apart: they are hashed
together, so changing one without the other is a visible difference.

**Harder, and accepted.**

*Terraform owns objects it cannot fully model.* The AppProject and root Application are
applied by scripts and validated by Terraform, not declared as resources. The desired state
for their *content* still lives in `argocd/*.yaml`. This is honest about the provider's
limitation rather than pretending otherwise, and the validation covers the properties that
actually matter.

*`run_bootstrap` defaults to false.* On a running cluster the scripts are a long no-op that
waits on rollouts, which surprises whoever expected a quick apply. The default means the
layer is registration plus validation in steady state and does the real work only when
explicitly asked — during a rebuild or recovery.

*One exception to "Terraform does not manage Secrets".* Repository registration Secrets are
managed because both repositories are public, so they contain no credential. The exception is
enforced by a `check` block that refuses credential keys and a variable validation that
refuses `ssh://` URLs, rather than by anyone remembering the rule.

*Recovery gains an ordering constraint.* PostgreSQL must be restored before Terraform runs at
all, because the `pg` backend lives in it. Documented alongside the existing constraint that
certificate material is restored before Argo CD reconciles.

## Validation

```sh
cd terraform/layers/6-gitops
terraform plan
```

On a healthy platform: `Plan: 2 to add, 0 to change, 0 to destroy` — the two repository
Secrets — with every assertion silent.

Each assertion was negative-tested against the live cluster:

| Violation | Result |
|---|---|
| `gitops_repo_url` pointed elsewhere | reported, naming both observed and expected |
| `gitops_target_revision` set to a SHA | reported, with why pinning it breaks delivery |
| `argocd_version` set to a version not running | reported, naming the running image |
| A repository registered outside the project's `sourceRepos` | reported, with why it fails at sync time |

And the handover itself:

```sh
terraform output -json handover
terraform output -json verification_commands | jq -r '.[]'
```
