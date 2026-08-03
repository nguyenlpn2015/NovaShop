# NovaShop Roadmap

Where the platform has been, and what remains before v1.0. Maturity scores and the evidence
behind them are in [AUDIT.md](AUDIT.md).

## Delivered

| Phase | What | Evidence |
|---|---|---|
| 0 | Repository foundation | — |
| 1 | Repository governance | `CODEOWNERS`, `CONTRIBUTING.md`, `SECURITY.md`, rulesets as code |
| 2 | Application bootstrap | FastAPI backend, Next.js frontend |
| 3 | Containerization | Multi-stage images, non-root runtime, npm removed from the frontend runtime stage |
| 4 | Continuous integration | [`validation.yml`](../.github/workflows/validation.yml) — five jobs, reusable |
| 5 | Infrastructure as code | `scripts/linux/*`, idempotent with marked managed blocks |
| 6 | Kubernetes platform | k3s, Traefik, cert-manager, phased TLS — [ADR 002](../adr/002-kubernetes-distribution.md) |
| 7 | GitOps | Argo CD, ApplicationSet, AppProjects, sync waves — [ADR 003](../adr/003-gitops-delivery.md), [ADR 005](../adr/005-gitops-controller.md) |
| 7.5 | **Platform guardrails** ✅ | Sprint 5.0. 93 automated checks across three gates, release gating, rehearsed recovery — [ADR 001](../adr/001-platform-guardrails.md), [Sprint 5.0](SPRINTS/Sprint-5.0.md) |
| 8 | **Observability** ✅ | Sprint 5.1. 31 scrape targets, Loki + Alloy, 14 alerts with 14 runbooks — [ADR 004](../adr/004-log-collection-agent.md), [ADR 009](../adr/009-observability-stack.md) |
| 8.5 | **Engineering documentation** ✅ | 13 architecture views, 14 ADRs, 6 operational guides, [AUDIT.md](AUDIT.md) |
| 9 | **Infrastructure as Code** ✅ | Sprint 6. 7 Terraform layers, non-cloud — [ADR 012](../adr/012-terraform-scope.md), [ADR 013](../adr/013-terraform-kubernetes-boundary.md), [ADR 014](../adr/014-terraform-gitops-handover.md) |
| 10 | **Backup, restore, hardening** ✅ | Datastore backup and restore validated; default-deny ingress trialled live |
| **v1.0.0** | **Released 2026-08-02** | Record and rescore in [AUDIT.md](AUDIT.md#v100--what-shipped) |

Phase 8 was delivered onto the guardrails from Phase 7.5, so a faulty telemetry change is
stopped before it reaches the cluster rather than after it.

Distributed tracing was in the Phase 8 scope and is **not** deployed. The instrumentation
exists and is disabled; no collector runs. See
[ADR 011](../adr/011-distributed-tracing.md) for why, and for what would change the answer.

## Released

**v1.0.0 — 2026-08-02.** What shipped, the rescore, and what v1.0 deliberately does not meet
are in [AUDIT.md](AUDIT.md#v100--what-shipped).

One condition is worth repeating here because it is the honest limit of the release: **full
recovery has never been exercised on a replacement node.** Every component is tested;
the sequence is not. RTO is an estimate, not a measurement.

## v1.1

The remaining work, ordered by value, is in [AUDIT.md](AUDIT.md#v11--what-remains). The first
item is exercising recovery on a replacement node — the only thing that turns RTO into a
number.

## Deliberately out of scope

Saying no is part of the design. Each has a recorded reason.

| Not doing | Because |
|---|---|
| Deploy Tempo | Nothing worth tracing yet — [ADR 011](../adr/011-distributed-tracing.md) |
| Second node / HA | A hardware decision, and the honest path from Production Readiness 2 to 4 |
| Service mesh | Nothing here exercises traffic management |
| External secret manager | Every option moves the bootstrap problem rather than removing it — [ADR 010](../adr/010-secret-management.md) |
| Gateway API | Four `Host` rules are satisfied by Ingress — [ADR 007](../adr/007-ingress-controller.md) |
| Application features | This is a platform portfolio. The application is minimal on purpose. |
