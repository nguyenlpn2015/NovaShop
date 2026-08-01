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
| 8.5 | **Engineering documentation** ✅ | 12 architecture views, 11 ADRs, 5 operational guides, [AUDIT.md](AUDIT.md) |

Phase 8 was delivered onto the guardrails from Phase 7.5, so a faulty telemetry change is
stopped before it reaches the cluster rather than after it.

Distributed tracing was in the Phase 8 scope and is **not** deployed. The instrumentation
exists and is disabled; no collector runs. See
[ADR 011](../adr/011-distributed-tracing.md) for why, and for what would change the answer.

## v0.9 — Close what is already open

Each is a known gap with a known fix. Ordered by value per unit of effort.

| # | Item | Note |
|---|---|---|
| 1 | Alert routing to a real destination | The largest single gap. Fourteen alerts that page nobody are diagnostics, not alerting. Needs a Secret and an on-call decision — [alerts.md](observability/alerts.md) has the exact change. |
| 3 | Rotate node credentials, enforce SSH keys | The only genuinely open security item — [hardening.md](security/hardening.md) |
| 4 | Remove the duplicate `push` CI trigger | Halves CI cost; removes a real source of confusion |
| 5 | Remove the duplicate Traefik scrape | Requires overriding a chart default scrape job. Combine with #6. |
| 6 | k3s control-plane metric flags | Needs a restart. Combine with the next k3s upgrade rather than spending a separate outage — [platform-upgrade.md](operations/platform-upgrade.md) |
| 7 | Dependabot #42 (Python 3.14) and #43 (Node 26) | Major bumps must move Dockerfile, workflow, `engines`, and types in one commit, or the runtime-alignment check fails — which is the check working |

## v0.95 — Close the reliability gap

The audit scores Reliability 3/5, and this is why.

| # | Item | From → to |
|---|---|---|
| 8 | Frontend test framework and first suite | **0 tests, no framework** → a real suite |
| 9 | Backend integration test with service containers | Verify `/ready` against real PostgreSQL and Redis in CI |
| 10 | Coverage measurement in CI, number published | No measurement → a visible number |
| 11 | Complete the dashboard set | The mechanism is right; the set is incomplete against its scope |

## v1.0 — Consolidate and present

| # | Item |
|---|---|
| 12 | Merge or rename the layered `docs/` pairs; move sprint artefacts to `SPRINTS/`; retire "Deployment Target A/B" |
| 13 | Fill or delete `PROJECT_GLOSSARY.md` and `LEARNING_LOG.md` |
| 14 | Restructure `README.md` — short competence summary, links out |
| 15 | Default-deny network policies |
| 16 | Sign images with cosign; publish provenance |
| 17 | Re-run [AUDIT.md](AUDIT.md) and publish the delta |

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
