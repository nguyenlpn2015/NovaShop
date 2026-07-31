# 🚀 NovaShop

> **A production-grade cloud-native e-commerce platform built to demonstrate modern DevOps, Platform Engineering, and Site Reliability Engineering (SRE) practices.**

NovaShop is an end-to-end portfolio project that simulates how a real engineering team designs, builds, deploys, secures, monitors, and operates a cloud-native application in production.

Unlike tutorial repositories that mainly focus on application development, **NovaShop focuses on the entire software delivery lifecycle**, from project initialization to production operations.

---

## 🚧 Build in Public

NovaShop is being developed completely in public.

Every architectural decision, infrastructure change, deployment strategy, CI/CD pipeline, production operation, and engineering document is intentionally committed into Git history.

The goal is not only to build a production-grade cloud-native platform, but also to demonstrate the engineering thought process behind every decision.

This repository is designed as a long-term engineering portfolio rather than a simple demo application.

---

# ⚡ Quick Start

Clone the application and deployment repositories as siblings:

```text
git clone https://github.com/nguyenlpn2015/NovaShop.git
git clone https://github.com/nguyenlpn2015/NovaShop-GitOps.git
cd NovaShop
```

## Deployment Target A: Docker Desktop Kubernetes

Use Target A on a Windows 11 developer workstation:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\verify-docker-desktop.ps1
.\scripts\install-argocd.ps1
.\scripts\bootstrap-docker-desktop.ps1
```

Open the Argo CD UI:

```powershell
.\scripts\port-forward-argocd.ps1
```

## Deployment Target B: Ubuntu Server and k3s

Use Target B on the Ubuntu Server 22.04 platform lab:

```bash
sudo test -r /root/.novashop-platform.env
sudo chmod 600 /root/.novashop-platform.env
bash scripts/linux/bootstrap.sh
```

Open the Argo CD UI:

```bash
bash scripts/port-forward.sh
```

# 🌐 Supported Deployment Targets

NovaShop supports two deployment targets without changing the Helm chart,
GitOps repository, Argo CD resources, GitHub Actions workflows, or GHCR image
contract.

| Target | Platform | Purpose | Use when |
|--------|----------|---------|----------|
| Target A | Windows 11 + Docker Desktop Kubernetes | Developer workstation | Developing locally, testing changes quickly, and validating the GitOps flow on a laptop |
| Target B | Ubuntu Server 22.04 + single-node k3s | Production-like Platform Lab | Practicing persistent Linux operations, networking, backups, upgrades, and VPS-style platform administration |

## Target A: Docker Desktop Kubernetes

Target A is the default path for local development, fast feedback, and
workstation-level GitOps validation.

## Target B: Ubuntu Server and k3s

Target B provisions a persistent Linux platform at `10.10.1.45` for
systemd-based operations, networking, upgrades, backup, and recovery practice.

## Detailed Documentation

- Target A:
  [deployment](docs/DOCKER_DESKTOP_DEPLOYMENT.md),
  [validation](docs/DOCKER_DESKTOP_VALIDATION.md), and
  [troubleshooting](docs/DOCKER_DESKTOP_TROUBLESHOOTING.md).
- Target B:
  [deployment](docs/deployment/ubuntu-k3s.md),
  [bootstrap sequence](docs/deployment/bootstrap-sequence.md),
  [validation](docs/deployment/validation.md), and
  [operations](docs/deployment/operations.md).
- Shared:
  [GitOps architecture](docs/GITOPS_ARCHITECTURE.md),
  [runtime diagram](diagrams/GITOPS_RUNTIME.md), and
  [deployment target comparison](diagrams/DEPLOYMENT_TARGETS.md).

---

# 🌍 Public Internet Deployment

Deployment Target B can be extended with a production-like public edge:

```text
Cloudflare -> Public IP -> FortiGate VIP -> Ubuntu + k3s
  -> Traefik -> Kubernetes Ingress -> NovaShop
```

The edge design preserves the existing GitOps architecture and keeps
PostgreSQL, Redis, SSH, Argo CD, and the Kubernetes API off the public path.

The public edge is delivered in two controlled phases:

1. HTTP routing through Cloudflare, FortiGate, Traefik, and Ingress is the
   bootstrap default.
2. cert-manager, ACME certificates, HTTPS redirects, and HSTS are repository
   integrated but require a separate reviewed GitOps activation.

Running `scripts/linux/bootstrap.sh` does not install cert-manager or enable
HTTPS.

| Area | Documentation |
|------|---------------|
| End-to-end networking | [Public Access Architecture](docs/networking/public-access.md) |
| Cloudflare DNS and proxy | [Cloudflare](docs/networking/cloudflare.md) |
| FortiGate VIP and firewall | [FortiGate](docs/networking/fortigate.md) |
| Traefik routing and Middleware | [Traefik](docs/networking/traefik.md) |
| TLS selection and renewal | [TLS Strategy](docs/security/tls.md) and [Certificate Lifecycle](docs/networking/ssl-renewal.md) |
| Edge security | [Public Edge Hardening](docs/security/hardening.md) |
| Operational validation | [Public Deployment Checklist](docs/operations/public-deployment-checklist.md) |
| Architecture | [Edge Architecture Diagram](diagrams/EDGE_ARCHITECTURE.md) |

The active HTTP manifests are under
[`kubernetes/ingress/http`](kubernetes/ingress/http/). TLS-ready examples remain
under [`kubernetes/ingress/examples`](kubernetes/ingress/examples/) for the
reviewed second phase. Docker Desktop continues using its local Ingress.

---

# 🎯 Project Objectives

NovaShop is designed to demonstrate practical experience in:

- Cloud Native Architecture
- Infrastructure as Code (IaC)
- CI/CD Automation
- GitOps
- Kubernetes
- Platform Engineering
- Observability
- DevSecOps
- Production Operations
- Documentation & Engineering Standards

This repository serves as a public portfolio project for demonstrating DevOps engineering capabilities.

---

# 💡 Why NovaShop?

Many public GitHub projects only demonstrate how to build an application.

NovaShop demonstrates how to operate one.

The project emphasizes:

- Designing production-ready architecture
- Automating infrastructure provisioning
- Building secure CI/CD pipelines
- Deploying applications using Kubernetes
- Monitoring production systems
- Operating cloud-native workloads
- Documenting engineering decisions
- Managing production incidents

---

# 🏗 High-Level Architecture

```
                    Internet
                         │
                  Cloudflare DNS
                         │
               Cloudflare Tunnel
                         │
               GitHub Actions CI/CD
                         │
              GitHub Container Registry
                         │
                  Kubernetes Cluster
                         │
        ┌─────────────────────────────────┐
        │                                 │
     Frontend                       Backend API
        │                                 │
        └──────────────┬──────────────────┘
                       │
                  PostgreSQL
                       │
                     Redis

--------------------------------------------------------

Observability

OpenTelemetry
      │
Grafana Alloy
      │
 ├── Prometheus
 ├── Loki
 └── Tempo
      │
   Grafana

--------------------------------------------------------

GitOps

Argo CD

--------------------------------------------------------

Security

Trivy
Gitleaks
Dependabot
Cosign
```

---

# 🚢 Deployment Architecture

```text
Developer
  -> GitHub
  -> GitHub Actions
  -> GHCR
  -> NovaShop-GitOps
  -> Argo CD
       |-> Target A: Docker Desktop Kubernetes -> Traefik -> NovaShop
       `-> Target B: Ubuntu + k3s              -> Traefik -> NovaShop
```

The application repository builds immutable artifacts. The GitOps repository
selects the artifact revisions. Argo CD is the only application deployment
controller for the cluster.

See the [GitOps Runtime Diagram](diagrams/GITOPS_RUNTIME.md).

---

# 🛠 Technology Stack

## Application Layer

- FastAPI
- Next.js
- PostgreSQL
- Redis

## Container Platform

- Docker
- Docker Compose
- GitHub Container Registry

## Infrastructure

- Terraform
- Cloudflare
- Kubernetes (k3s)

## Deployment

- Helm
- Argo CD

## CI/CD

- GitHub Actions

## Observability

- OpenTelemetry
- Grafana
- Prometheus
- Loki
- Tempo
- Grafana Alloy

## Security

- Trivy
- Gitleaks
- Dependabot
- Cosign

## Documentation

- Architecture Decision Records (ADR)
- Runbooks
- System Diagrams
- Engineering Documentation

---

# 🔄 GitOps Delivery

NovaShop uses Argo CD with a separate deployment repository:

- `NovaShop` owns source code, CI, Dockerfiles, and the reusable Helm chart.
- `NovaShop-GitOps` owns environment values and the desired deployment state.
- Argo CD watches only `NovaShop-GitOps` for desired-state changes.
- Helm chart and container image revisions are immutable and promoted through
  reviewed GitOps pull requests.

This separation keeps build permissions away from the cluster, provides a
clear deployment audit trail, and makes Git the authoritative source of
runtime state.

Deployment workflow:

```text
NovaShop change
  -> CI validation
  -> GHCR images tagged with Git SHA
  -> NovaShop-GitOps pull request
  -> reviewed merge
  -> Argo CD automatic sync
  -> Kubernetes health assessment
```

Argo CD continuously reconciles the desired state, self-heals drift, and
prunes resources removed from Git. Rollback is performed by reverting the
GitOps commit or restoring the previous immutable image SHA; emergency Argo CD
rollbacks must be followed by an equivalent Git commit.

See [GitOps Architecture](docs/GITOPS_ARCHITECTURE.md) for repository strategy,
synchronization, promotion, rollback, and future CI integration.

---

# ⚙ GitOps Runtime

The runtime layer is intentionally small:

| Component | Responsibility |
|-----------|----------------|
| `scripts/*.ps1` | Operate Target A from a Windows developer workstation |
| `scripts/linux/*.sh` | Provision, verify, and operate Target B on Ubuntu and k3s |
| `scripts/*.sh` | Provide shared Linux GitOps installation and runtime primitives |
| `docs/DOCKER_DESKTOP_VALIDATION.md` | Validate Target A end to end |
| `docs/deployment/validation.md` | Validate Target B end to end |
| `docs/OPERATIONS.md` | Deploy, update, rollback, restart, scale, recover, and troubleshoot |
| `docs/VERIFICATION_CHECKLIST.md` | Verify cluster, Argo CD, workloads, ingress, Helm render, and GHCR images |

Automatic sync, self-heal, prune, retry, and revision history are declared in
the Argo CD resources. Application delivery is performed from
`NovaShop-GitOps`; the runtime scripts do not bypass GitOps.

---

# 📂 Repository Structure

```
NovaShop/

├── .github/
│   └── workflows/

├── adr/
│   └── Architecture Decision Records

├── architecture/
│   └── Architecture documents

├── backend/
│   └── FastAPI

├── frontend/
│   └── Next.js

├── terraform/
│   └── Infrastructure as Code

├── kubernetes/
│   └── Kubernetes manifests

├── helm/
│   └── Helm Charts

├── argocd/
│   └── One-time GitOps bootstrap manifests

├── monitoring/
│   └── Observability Stack

├── diagrams/
│   └── Architecture Diagrams

├── docs/
│   └── Project Documentation

├── runbooks/
│   └── Operational Procedures

├── scripts/
│   └── Utility Scripts
```

> Some directories will be introduced progressively throughout the project roadmap.

---

# 🏛 Engineering Principles

NovaShop follows several engineering principles:

- Everything as Code
- Documentation First
- Automation First
- GitOps by Default
- Security by Design
- Observability First
- Production over Demo
- Human Reviewed AI-assisted Development

Every significant engineering decision is documented using ADRs.

---

# 📖 Documentation

Documentation is considered part of the product.

| Directory | Description |
|------------|-------------|
| docs | General documentation |
| adr | Architecture Decision Records |
| architecture | System architecture |
| runbooks | Operational runbooks |
| diagrams | System diagrams |

---

# 📊 Current Progress

| Item | Status |
|------|--------|
| Repository Foundation | ✅ Completed |
| Repository Governance | ✅ Completed |
| Documentation | 🚧 In Progress |
| Application Foundation | ✅ Completed |
| Continuous Integration | ✅ Completed |
| Infrastructure | ⏳ Planned |
| Kubernetes | ✅ Completed |
| GitOps | ✅ Completed |
| Observability | ⏳ Planned |
| DevSecOps | ⏳ Planned |
| Production | ⏳ Planned |

Current Phase

```
Sprint 4
GitOps Foundation
```

---

# 🎯 Current Focus

Current Sprint

```
Sprint 4
GitOps Foundation
```

Current Objectives

- Separate application and deployment responsibilities
- Establish Argo CD bootstrap resources
- Define environment-specific desired state
- Document synchronization, promotion, and rollback
- Prepare CI-driven GitOps pull requests

---

# 📈 Engineering Metrics

| Metric | Current |
|---------|---------|
| ADRs | 0 |
| Runbooks | 0 |
| Architecture Documents | 1 |
| CI Pipelines | 2 |
| Helm Charts | 1 |
| Terraform Modules | 0 |
| Kubernetes Manifests | 8 |
| Production Releases | 0 |

These metrics will evolve throughout the project lifecycle.

---

# 📚 Learning Journey

Every sprint follows the same engineering workflow:

- Requirement Analysis
- Architecture Design
- AI-assisted Implementation
- Technical Review
- Validation
- Documentation
- Lessons Learned
- Retrospective

The objective is to document not only *what* was built, but also *why* it was built that way.

---

# 🗺 Roadmap

## Phase 0

Repository Foundation

## Phase 1

Repository Governance

## Phase 2

Application Bootstrap

## Phase 3

Containerization

## Phase 4

Continuous Integration

## Phase 5

Infrastructure as Code

## Phase 6

Kubernetes Platform

## Phase 7

GitOps

## Phase 8

Observability

## Phase 9

DevSecOps

## Phase 10

Production Readiness

## Phase 11

Operations & SRE

## Phase 12

Portfolio Release v1.0

---

# 📈 Project Status

Current Phase

```
Phase 7
GitOps
```

Current Status

```
✅ Foundation Completed
```

---

# 🤝 Contributing

Although NovaShop is primarily a personal portfolio project, contributions, discussions, and suggestions are welcome.

Please read:

- CONTRIBUTING.md
- CODE_OF_CONDUCT.md
- SECURITY.md

before opening Issues or Pull Requests.

---

# 📜 License

This project will be released under the MIT License.

---

# 👨‍💻 About This Project

NovaShop is developed as a long-term engineering portfolio to demonstrate real-world DevOps, Platform Engineering, and Cloud Native practices.

The project intentionally prioritizes:

- engineering quality
- maintainability
- automation
- documentation
- operational excellence

over rapid feature development.

Every major milestone will be documented, reviewed, and released using GitHub Releases.

---

# ⭐ Project Philosophy

NovaShop follows one simple philosophy:

> Build like a real engineering team.

Every technology, tool, and engineering decision included in this repository must satisfy three conditions:

- Solve a real engineering problem.
- Be explainable during a technical interview.
- Be maintainable in a production environment.

The project values engineering quality over implementation speed.
