# NovaShop Academy

A curriculum where **the repository is the textbook**. Every lesson teaches from files that
are running in production at [novashop.smartdev.vn](https://novashop.smartdev.vn), not from
invented examples.

If a concept cannot be taught from something NovaShop actually does, this Academy does not
teach it. That constraint is the point: you will finish able to read every part of this
repository, which is a narrower and more useful outcome than "you will know DevOps".

## Who this is for

| You are | Start at |
|---|---|
| New to DevOps | Module 1, in order |
| A junior DevOps engineer | Module 1, skimming Part 1 |
| A system engineer moving to DevOps | Module 1 — Part 1 is your existing knowledge applied to a platform |
| An intermediate platform engineer | Part 4 (GitOps), then Part 5 and 7 |

## Status — read this first

**Four modules are written in full. Fifteen are specified but not yet written.**

That is stated here rather than discovered on a click, because this repository has a rule
about documentation that claims more than it delivers — see
[LEARNING_LOG.md](../LEARNING_LOG.md), where two documents claimed a backup existed and
someone stopped looking.

Written modules are marked ✅. The rest carry their objectives and the exact NovaShop files
they will teach from, so they are useful as a reading list even unwritten.

## Curriculum

Nineteen modules, not twenty-four. The brief listed topics; several are one lesson.

**Collapses made, and why.** Docker and Containers are one subject. CI/CD and GitHub Actions
are one subject here because there is one implementation. GitOps and Argo CD likewise. TLS and
cert-manager are inseparable on this platform. PostgreSQL and Redis share a module because they
share a failure mode — both live on the host and are reached over the pod network. Observability
splits into four modules rather than collapsing into one, because metrics, logs, alerting, and
tracing have genuinely different lessons here.

### Part 1 — Foundations: the node

| # | Module | Teaches from |
|---|---|---|
| 1 ✅ | [Linux and the Node](modules/01-linux-and-the-node.md) | `scripts/linux/*`, sysctl, systemd, UFW, the inotify incident |
| 2 | Git and GitHub as a Platform | `.github/rulesets/`, `apply-branch-protection.sh`, the stacked-PR failure |
| 3 | Datastores on the Host | `configure-datastores.sh`, `pg_hba.conf`, the `pg_monitor` least-privilege defect |

### Part 2 — Packaging and delivery

| # | Module | Teaches from |
|---|---|---|
| 4 ✅ | [Containers and Images](modules/04-containers-and-images.md) | `backend/Dockerfile`, `frontend/Dockerfile`, the vendored-npm CVE story |
| 5 | CI/CD with GitHub Actions | `validation.yml`, `release.yml`, scan-before-push, the reusable-workflow race fix |

### Part 3 — Kubernetes

| # | Module | Teaches from |
|---|---|---|
| 6 | Kubernetes on One Node | k3s, SQLite, `local-path`, Pod Security Admission, the three health endpoints |
| 7 | Helm and Kustomize | `helm/novashop/`, the phase overlays, ADR 006 |
| 8 | Traefik and the Edge | Host routing, pod-only metrics, the `websecure` entrypoint trap |
| 9 | TLS and cert-manager | The five-certificates rate limit, phased TLS, HSTS rollback |

### Part 4 — GitOps

| # | Module | Teaches from |
|---|---|---|
| 10 ✅ | [GitOps and Argo CD](modules/10-gitops-and-argocd.md) | Two repositories, SHA pinning, sync waves, `ServerSideApply` diffs, `selfHeal` traps |
| 11 | Guardrails and Validation | The three gates, 94 checks, negative testing |

### Part 5 — Observability

| # | Module | Teaches from |
|---|---|---|
| 12 ✅ | [Metrics with Prometheus](modules/12-metrics-with-prometheus.md) | The scrape-port defect, discovery roles, `metrics.py`, cardinality |
| 13 | Logs with Loki and Alloy | Single-binary Loki, journal relabelling, why Promtail was replaced |
| 14 | Alerting and Runbooks | 14 rules, runbook enforcement, inhibition, why alerts route nowhere |
| 15 | Tracing: the case for not deploying it | `tracing.py`, ADR 011, what would change the answer |

### Part 6 — Infrastructure as Code

| # | Module | Teaches from |
|---|---|---|
| 16 | Terraform without a Cloud | 7 layers, `pg` backend, import-not-create, the ownership boundary |

### Part 7 — Operations

| # | Module | Teaches from |
|---|---|---|
| 17 | Production Hardening | NetworkPolicy trialled with a control group, PSA, least privilege |
| 18 | Backup and Disaster Recovery | 21KB tiering, `sqlite3 .backup`, the `recover.sh` defect |
| 19 | Platform Engineering as a Discipline | Guardrails, ADRs, self-auditing, knowing what not to build |

## How a module works

Every module has twelve sections — see [`_template.md`](_template.md).

The two that matter most:

**Repository Walkthrough** names real files and line numbers. Open them. If the module and the
file disagree, the file is right and the module is a bug.

**Troubleshooting** is drawn from defects this platform actually had. These are not invented
failure scenarios; each one cost real time and is recorded in
[LEARNING_LOG.md](../LEARNING_LOG.md).

## What you need

- The repository cloned, plus `NovaShop-GitOps` beside it
- Docker, for local development and for running the gates
- Optionally a Linux VM if you want to do the Part 1 labs for real

You do **not** need access to the live cluster. Every lab is designed to run on your own
machine, and the three validation gates run offline with no credentials:

```sh
bash scripts/validate-platform.sh          --gitops-dir ../NovaShop-GitOps
bash scripts/validate-gitops-revisions.sh  --gitops-dir ../NovaShop-GitOps
bash scripts/validate-observability.sh     --gitops-dir ../NovaShop-GitOps
```

## The through-line

Most of this platform's design exists to defend against one failure mode: **something renders,
validates, deploys, and does nothing**, while every dashboard stays green.

A scrape job whose relabel rules match nothing. A pin to an image that was never published. An
alert whose runbook does not exist. A recovery script that aborts on a healthy platform.

Each of those happened here. Each produced a guardrail. If you take one idea from this Academy,
take that one — and its corollary: **a green dashboard is evidence that nothing is reporting a
problem, which is not the same as nothing being wrong.**

## Related

- [Interview curriculum](../interview/) — 107 questions, once you have finished here
- [Architecture](../architecture/) — 13 views
- [ADRs](../../adr/) — 14 decisions, each with rejected alternatives
- [Engineering log](../LEARNING_LOG.md) — the defects the Troubleshooting sections come from
