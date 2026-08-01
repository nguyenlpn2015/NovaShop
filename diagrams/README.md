# Diagrams

The primary architecture set is **[docs/architecture/](../docs/architecture/)** — twelve
views with the reasoning behind each one.

This directory holds earlier diagrams that go deeper on a single subsystem than an
architecture view should. They are kept because they are still accurate and still useful, not
for historical interest.

| Diagram | Covers | Overlaps with |
|---|---|---|
| [PLATFORM_GUARDRAILS.md](PLATFORM_GUARDRAILS.md) | Guardrail, bootstrap, release, recovery, and GitOps flows in one place | [CI/CD Flow](../docs/architecture/cicd-flow.md), [Bootstrap](../docs/architecture/bootstrap-flow.md), [Recovery](../docs/architecture/recovery-flow.md) |
| [EDGE_ARCHITECTURE.md](EDGE_ARCHITECTURE.md) | Traefik routing and the TLS phases in detail | [Networking](../docs/architecture/networking.md), [TLS Flow](../docs/architecture/tls-flow.md) |
| [DEPLOYMENT_TARGETS.md](DEPLOYMENT_TARGETS.md) | Differences between the two deployment paths | [Deployment](../docs/architecture/deployment.md) |
| [GITOPS_RUNTIME.md](GITOPS_RUNTIME.md) | Argo CD runtime object relationships | [GitOps Flow](../docs/architecture/gitops-flow.md) |

## Convention

Every diagram in this repository is Mermaid, in Markdown. None is a binary image.

That is deliberate. Mermaid renders on GitHub, diffs line by line in review, and cannot drift
from the repository without someone editing the file that describes it. A PNG exported from a
drawing tool is correct on the day it is exported and unfalsifiable from then on — and the
source file it came from is usually on someone's laptop.
