# Documentation

## Start here

| If you want to… | Read |
|---|---|
| Understand everything, in one file | [The Complete Guide](THE_COMPLETE_GUIDE.md) |
| Understand what this is | [Architecture Overview](architecture/overview.md) |
| See why each technology was chosen | [Architecture Decision Records](../adr/) |
| Run it on your machine | [Local Development](operations/local-development.md) |
| Deploy it on a real node | [Production Deployment](operations/production-deployment.md) |
| Fix something that is broken | [Troubleshooting](operations/troubleshooting.md) |
| Respond to an alert | [Runbooks](observability/runbooks/) |
| Judge the engineering | [Repository Audit](AUDIT.md) |
| Interview or demo this | [Interview Guide](INTERVIEW_GUIDE.md) — the 10-minute demo script |
| Prepare for an interview | [interview/](interview/) — teaching guide, 107 questions, cheat sheets |
| Learn the stack from these files | [academy/](academy/) — 19 modules, 4 written; the repository as textbook |
| See what went wrong, and how it was found | [Engineering Log](LEARNING_LOG.md) |
| Judge the Terraform | [Terraform Audit](TERRAFORM_AUDIT.md) |

## Architecture

Twelve views, each answering a question the others cannot. Reading order in
[architecture/README.md](architecture/README.md).

| | |
|---|---|
| [Overview](architecture/overview.md) | [Deployment](architecture/deployment.md) |
| [System Context](architecture/c4-system-context.md) | [GitOps Flow](architecture/gitops-flow.md) |
| [Container Diagram](architecture/c4-container.md) | [CI/CD Flow](architecture/cicd-flow.md) |
| [Bootstrap Flow](architecture/bootstrap-flow.md) | [Recovery Flow](architecture/recovery-flow.md) |
| [Observability Flow](architecture/observability-flow.md) | [Networking](architecture/networking.md) |
| [DNS](architecture/dns.md) | [TLS Flow](architecture/tls-flow.md) |
| [Terraform Flow](architecture/terraform-flow.md) | |

Supplementary diagrams predating this set are in [../diagrams/](../diagrams/).

## Operations

Index in [operations/README.md](operations/README.md).

| Guide | Use when |
|---|---|
| [Local Development](operations/local-development.md) | Changing the application |
| [Production Deployment](operations/production-deployment.md) | Building the platform on a node |
| [Observability](operations/observability-guide.md) | Reading metrics, logs, and alerts |
| [Troubleshooting](operations/troubleshooting.md) | Something is wrong, cause unknown |
| [Platform Upgrade](operations/platform-upgrade.md) | Moving k3s, Argo CD, or a chart |
| [Backup and Restore](operations/backup-and-restore.md) | Protecting data, and proving the backup works |
| [Application Data Provisioning](operations/application-data-provisioning.md) | One-time node setup: per-environment databases and Redis indices |
| [Disaster Recovery](recovery/disaster-recovery.md) | The node is gone |
| [DR exercise, 2026-08-02](recovery/dr-exercise-2026-08-02.md) | What was and was not proven |

### Task reference

- [Day-2 operations](OPERATIONS.md) — deploy, update, rollback, scale, sync, back up
- [Node operations](deployment/operations.md) — k3s, Helm, and Argo CD upgrades; credential rotation
- [Verification checklist](VERIFICATION_CHECKLIST.md)
- [Deployment guide](DEPLOYMENT_GUIDE.md) — cluster install walkthrough

## Platform delivery

- [GitOps architecture](GITOPS_ARCHITECTURE.md)
- [Platform guardrails](PLATFORM_GUARDRAILS.md) — what CI proves before a merge
- [Guardrail validation checklist](guardrails/validation-checklist.md) — Sprint 5.0 evidence
- [Guardrail, bootstrap, release, recovery, and GitOps flows](../diagrams/PLATFORM_GUARDRAILS.md)
- [ADR 001: Platform guardrails](../adr/001-platform-guardrails.md)

## Observability

- [Architecture](observability/architecture.md) — components and versions
- [Alerts](observability/alerts.md) — all 14 rules, thresholds, and rationale
- [Runbooks](observability/runbooks/) — one per alert
- [Observability Guide](operations/observability-guide.md) — daily use

## Networking, DNS, and TLS

- [Public access](networking/public-access.md) — end to end
- [Cloudflare](networking/cloudflare.md) — DNS records
- [FortiGate](networking/fortigate.md) — NAT policy
- [Traefik](networking/traefik.md) — ingress configuration
- [SSL renewal](networking/ssl-renewal.md)
- [Verification](networking/verification.md)
- [TLS](security/tls.md)

## Security

- [Hardening](security/hardening.md) — including open items
- [Network policy](security/network-policy.md) — default-deny ingress, and how enforcement was proven
- [ADR 010: Secret management](../adr/010-secret-management.md)
- [SECURITY.md](../SECURITY.md) — disclosure policy

## Deployment environments

**Ubuntu Server + k3s** is the live target. Everything above describes it.

- [Ubuntu and k3s deployment](deployment/ubuntu-k3s.md) — server preparation
- [Bootstrap sequence](deployment/bootstrap-sequence.md)
- [Validation](deployment/validation.md)
- [Lab environment](deployment/lab-environment.md)
- [Portfolio evidence](deployment/portfolio-evidence.md)

**Docker Desktop** is for local development only. It is not wired into CI or GitOps, and it
does not run Argo CD, cert-manager, TLS, or observability. Prefer the
[Local Development Guide](operations/local-development.md); these remain for the Kubernetes
variant.

- [Docker Desktop deployment](DOCKER_DESKTOP_DEPLOYMENT.md)
- [Docker Desktop validation](DOCKER_DESKTOP_VALIDATION.md)
- [Docker Desktop troubleshooting](DOCKER_DESKTOP_TROUBLESHOOTING.md)

## Presenting this project

- [Portfolio evidence](PORTFOLIO_EVIDENCE.md) — what to have open, and what to say about the weak parts
- [Interview guide](INTERVIEW_GUIDE.md) — the ten-minute tour
- [interview/](interview/) — 107 questions with answers, cheat sheets
- [academy/](academy/) — 19 modules that teach the platform from its own files
- [Evidence catalog](EVIDENCE_CATALOG.md) — every artefact worth capturing, numbered in demo order
- [screenshots/](screenshots/) — which consoles to capture, and the rules for capturing them

## Project

- [Repository audit](AUDIT.md) — maturity scores and the road to v1.0
- [Roadmap](ROADMAP.md)
- [Release checklist](RELEASE_CHECKLIST.md) — verified before every tag
- [Engineering principles](ENGINEERING_PRINCIPLES.md)
- [Project charter](PROJECT_CHARTER.md)
- [Glossary](PROJECT_GLOSSARY.md)
- [Sprint records](SPRINTS/)
- [Engineering log](LEARNING_LOG.md) — defects found, and how
- [Support](SUPPORT.md)

## Conventions

**Version numbers are the versions deployed**, not the versions intended. Where a component
is in scope but absent, the document says so — see
[ADR 011](../adr/011-distributed-tracing.md) on distributed tracing.

**Diagrams are Mermaid, not images.** They render on GitHub, diff in review, and cannot drift
without someone editing the file that describes them.

**Single-node facts are stated as such.** This platform runs on one node, and where that has a
real consequence the document names it rather than implying redundancy that does not exist.
