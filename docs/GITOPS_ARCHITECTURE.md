# GitOps Architecture

## Scope

NovaShop uses Argo CD as the deployment reconciler for development, staging, and
production. The application and deployment concerns are intentionally separated
between two repositories.

## Repository Strategy

| Repository | Responsibility | Argo CD relationship |
|------------|----------------|----------------------|
| `NovaShop` | Source code, tests, Dockerfiles, CI, and the reusable Helm chart | Referenced at an immutable Git revision |
| `NovaShop-GitOps` | Environment values, cluster application definitions, and deployment operations | The only repository watched for desired-state changes |

The Helm chart revision and container image revision are both pinned in the
GitOps repository. A change in the application repository cannot deploy until a
reviewed GitOps pull request updates those revisions.

### Revision Durability

Every pinned NovaShop revision must be a forty-character commit SHA that is
reachable from the NovaShop default branch. This is enforced by
`scripts/validate-gitops-revisions.sh` and is not a style preference.

A pin that exists only on a feature branch survives only as long as that branch.
Deleting a branch after its pull request merges is ordinary hygiene, but it makes
the commit unreachable and eventually collectable. Argo CD then cannot resolve
`targetRevision`, so every environment, cert-manager, and the certificates stop
rendering, and both bootstrap and disaster recovery fail with no earlier warning.

The same validation requires that each environment deploys backend and frontend
from a single source commit, that no desired state references a mutable tag, and
that every referenced image tag exists in the registry. A missing tag is reported
during review instead of appearing as `ImagePullBackOff` after a merge.

### Validation Gates

No change reaches either default branch without passing
`scripts/validate-platform.sh`, which renders the desired state the way Argo CD
does and validates the result. Both repositories call the same script through the
same reusable workflow, so the application repository and the deployment
repository are held to one definition of correctness. The gates are catalogued in
[Platform Guardrails](PLATFORM_GUARDRAILS.md).

## Control Plane

```text
Developer
   |
   v
NovaShop pull request
   |
   v
GitHub Actions CI
   |
   +--> GHCR images:<git-sha>
   |
   v
NovaShop-GitOps pull request
   |
   v
GitOps main branch
   |
   v
Argo CD --> Helm render --> k3s / Traefik
```

## Bootstrap Boundary

The `argocd/` directory in `NovaShop` contains only the one-time bootstrap
resources:

1. The Argo CD namespace.
2. The NovaShop `AppProject`.
3. The root `Application` that points to `NovaShop-GitOps`.

After bootstrap, application deployments are not applied from `NovaShop`.
Changes under `kubernetes/` and `helm/` are not deployed directly with
`kubectl`.

## Deployment Flow

1. A change is merged into `NovaShop`.
2. CI validates the application and publishes backend and frontend images to
   GHCR using the source commit SHA.
3. A follow-up pull request updates the image tags in `NovaShop-GitOps`.
4. Required reviewers approve the environment change.
5. Argo CD detects the merged GitOps commit and renders the pinned Helm chart.
6. Argo CD applies the delta and waits for Kubernetes health checks.
7. The GitOps commit becomes the deployment audit record.

Promotion reuses the same immutable image SHA. Development, staging, and
production values are changed independently; images are not rebuilt during
promotion.

## Synchronization Flow

The root Argo CD `Application` reconciles the in-cluster `ApplicationSet`.
The `ApplicationSet` generates one child `Application` for each environment.

Each child application has:

- automatic synchronization;
- self-healing for cluster drift;
- pruning for resources removed from Git;
- bounded exponential retry;
- foreground pruning with pruning ordered last;
- ten retained Argo CD revisions;
- a dedicated namespace;
- Kubernetes readiness and liveness probes supplied by the Helm chart.

Argo CD built-in health assessments for `Deployment`, `Service`, and `Ingress`
are used. A synchronization is healthy only after the workload probes and
rollout status succeed.

## Configuration and Secrets

Shared defaults remain in the Helm chart. The GitOps repository stores only
environment-specific overrides.

Secret values are never committed. Each environment references a pre-existing
Kubernetes Secret. Secret delivery is an external platform responsibility and
can later be implemented with a secrets operator without changing the
application promotion model.

Public repositories do not require an Argo CD repository credential Secret.
If either repository becomes private, credentials must be provisioned
out-of-band and scoped read-only.

## Rollback Strategy

Rollback preserves TLS. The rollback target is the `tls-baseline` phase, which
keeps cert-manager, the `Certificate` resources, and HTTPS routing, and releases
only enforcement. It serves `Strict-Transport-Security: max-age=0` so browsers
drop the pin the enforced phase gave them.

The HTTP-only phase is retained as a break-glass path only. Because production
advertises HSTS with a one-year `max-age`, removing HTTPS causes returning
browsers to fail rather than degrade, and pruning deletes the certificates.
Reissuance is rate limited to five duplicate certificates per hostname set per
168 hours.

The primary rollback is a Git revert in `NovaShop-GitOps`:

1. Revert the deployment commit or restore the previous image SHA.
2. Open and approve the rollback pull request.
3. Merge the rollback.
4. Argo CD automatically reconciles the previous desired state.
5. Confirm application health and record the outcome.

For an active incident, an authorized operator may select a retained Argo CD
revision as an emergency rollback. The same state must then be committed to
Git immediately so the repository remains authoritative and self-heal does not
reverse the emergency action.

Database schema changes must remain backward compatible across at least one
application revision. Database recovery is handled separately from application
rollback.

## Future CI Integration

Image automation is intentionally deferred. A future release workflow may:

1. Publish both images with `${GITHUB_SHA}`.
2. Check out `NovaShop-GitOps` using a short-lived GitHub App token.
3. Update only the target environment image tags.
4. Run Helm and Kubernetes schema validation.
5. Open a pull request containing the source commit, image references, and
   deployment evidence.

The workflow must not push directly to the GitOps default branch or call
`kubectl`, Helm install, or the Argo CD API.
