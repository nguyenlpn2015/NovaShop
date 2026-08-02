# Architecture Decision Records

Why each technology in this platform was chosen, and what lost.

Every record follows [000-template.md](000-template.md) and includes an
**Alternatives Considered** section where each rejected option carries a specific reason.
An alternative with no stated drawback was not considered — it was listed.

## Index

| ADR | Decision | Status |
|---|---|---|
| [001](001-platform-guardrails.md) | Platform guardrails: what CI must prove before a merge | Accepted |
| [002](002-kubernetes-distribution.md) | k3s as the Kubernetes distribution | Accepted |
| [003](003-gitops-delivery.md) | GitOps as the delivery model | Accepted |
| [004](004-log-collection-agent.md) | Grafana Alloy as the log collection agent | Accepted |
| [005](005-gitops-controller.md) | Argo CD as the GitOps controller | Accepted |
| [006](006-helm-and-kustomize.md) | Helm and Kustomize, each for what it is good at | Accepted |
| [007](007-ingress-controller.md) | Traefik as the ingress controller | Accepted |
| [008](008-ci-platform.md) | GitHub Actions as the CI platform | Accepted |
| [009](009-observability-stack.md) | Prometheus, Grafana, Loki, and Alertmanager | Accepted |
| [010](010-secret-management.md) | Secrets created outside Git, by documented procedure | Accepted |
| [011](011-distributed-tracing.md) | OpenTelemetry instrumented, tracing backend not deployed | Accepted |
| [012](012-terraform-scope.md) | Terraform codifies the platform outside the cluster | Accepted |
| [013](013-terraform-kubernetes-boundary.md) | Terraform's Kubernetes layer asserts more than it owns | Accepted, refines 012 |
| [014](014-terraform-gitops-handover.md) | Terraform owns the GitOps seed, and stops there | Accepted |

## The decisions that most shaped the platform

If you read three, read these.

**[002 — k3s](002-kubernetes-distribution.md)** because almost every other constraint
descends from one node with SQLite and a single node-local storage class.

**[003 — GitOps](003-gitops-delivery.md)** because it is why there are two repositories, why
no cluster credentials exist in CI, and why a live `kubectl edit` is reverted in three
minutes.

**[011 — tracing](011-distributed-tracing.md)** because it is the one that says no. The
Sprint 5.1 scope asked for distributed tracing and it is not deployed; that record explains
why deploying it would have produced an empty dashboard, and what would have to be true to
change the answer.

## Writing a new one

Copy [000-template.md](000-template.md), take the next free number, and add a row above.

Two things make the difference between a record worth keeping and paperwork:

**Write down the constraint that was real at the time.** A decision looks arbitrary until
you know what it was fighting. "Let's Encrypt allows five duplicate certificates per 168
hours" explains more of this platform than any preference could.

**Give each alternative a specific reason it lost.** "Rejected because Sealed Secrets moves
the bootstrap problem to its private key, which on node-local storage is a realistic loss"
is a reason. "Rejected for simplicity" is not.

State the accepted downsides in **Consequences**. Every decision here has some, and a record
that lists only benefits was written to justify rather than to inform.
