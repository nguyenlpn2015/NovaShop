# ADR 011: OpenTelemetry instrumented, tracing backend not deployed

## Status

Accepted

## Date

2026-08-01

## Context

The Sprint 5.1 scope listed Tempo and an OpenTelemetry Collector, and asked for traces
covering frontend, backend, HTTP, database, and Redis. Metrics and logs were delivered.
This ADR records why traces were not, and what the instrumentation does instead.

The deciding facts are about the application, not the tooling.

**The backend has no business endpoints.** It serves `/health`, `/live`, `/ready`, and
`/metrics`. There is no checkout, no cart, no catalogue query — no operation with a call
graph.

**The frontend calls the backend from the browser.** There is no server-side request path
from frontend to backend to propagate context along, so the trace would not span the two
services even if both were instrumented.

So a trace collected today would contain: `GET /ready`, one `asyncpg` `SELECT 1`, and one
Redis `PING`. Three spans of a health check. That demonstrates that the plumbing is
connected. It does not demonstrate distributed tracing, and a Tempo dashboard showing
nothing but health checks is weaker evidence of competence than an honest absence.

The node is also relevant: memory limits are already committed at roughly 150% of
allocatable, and Tempo would be a further StatefulSet with its own volume on the one shared
disk.

## Decision

Write the instrumentation. Do not deploy the backend.

`backend/app/observability/tracing.py` instruments FastAPI, `asyncpg`, and `redis` using
OpenTelemetry, with `ParentBased(TraceIdRatioBased)` sampling. It is **disabled unless
`OTEL_EXPORTER_OTLP_ENDPOINT` is set**, imports are guarded so a missing dependency cannot
break startup, and `/metrics`, `/live`, and `/ready` are excluded from tracing.

No collector and no Tempo are deployed. When they are, Alloy terminates OTLP — it is
already running as a DaemonSet and already performs that role, so no new technology is
introduced.

Every architecture document states that tracing is absent rather than omitting the subject.

## Alternatives Considered

**Deploy Tempo and Alloy's OTLP receiver now.** Completes the stated scope and produces a
working trace pipeline. Rejected because it would add a StatefulSet, a volume, and a
Grafana datasource to visualise health checks, on a node already overcommitted. It would
also be the most likely thing in the repository to be probed in an interview and found
hollow: "show me a trace" would produce `GET /ready`.

**Instrument nothing until there is something to trace.** Cleaner in the sense that the
repository would carry no unused code. Rejected because the instrumentation is the part with
design decisions worth showing — sampling strategy, guarded imports, endpoint exclusions,
and the discipline that observability code must not be able to break the application. That
work is reviewable now; deploying a backend for it is not the interesting half.

**Jaeger instead of Tempo.** A reasonable backend choice and the wrong question. The
blocker is the absence of anything worth tracing, not which store holds the traces. If a
backend is deployed it will be Tempo, because Grafana and Loki are already present and
Tempo shares their query and storage idioms.

**Browser RUM with OpenTelemetry JS.** This is what would make traces genuinely meaningful,
because the frontend-to-backend call is browser-side. Rejected for now because it requires
a **publicly reachable OTLP endpoint** and therefore an authentication decision, a CORS
policy, and acceptance that anyone can post spans to it. That is a security design task, not
a deployment task.

**Add business endpoints to the application so tracing has something to show.** Rejected as
out of scope: the application is deliberately minimal and this project's subject is the
platform. Writing a fake checkout flow to justify a tracing backend inverts the priority.

## Consequences

**Easier.** No unused StatefulSet, no empty dashboards, no memory spent on a component with
nothing to record. The claim "this platform has observability" stays true in all three
pillars it actually claims.

**Harder, and accepted.**

*The stated Sprint 5.1 scope is not fully met.* Stated plainly here and in
[docs/architecture/observability-flow.md](../docs/architecture/observability-flow.md) rather
than quietly dropped. An interviewer comparing the scope to the result should find this
document before they find the gap.

*Instrumentation exists that nothing exercises.* It is covered by unit tests, but it has
never run against a real collector, so "it works" is untested end to end. The first
deployment will find something.

*The dependencies are carried.* OpenTelemetry packages are in the backend image whether or
not tracing is enabled.

## What would change this

Any one of these makes tracing worth deploying:

1. A business endpoint whose work spans PostgreSQL and Redis in one request.
2. A server-side rendering path in the frontend that calls the backend, giving a real
   two-service trace.
3. A decision to expose an authenticated public OTLP endpoint for browser RUM.

Until one of those is true, deploying Tempo adds a component and no information.

## Validation

```sh
# Tracing is off by default and starts cleanly
kubectl -n novashop-production exec deploy/novashop-backend -- env | grep OTEL || echo "not set: tracing disabled"
kubectl -n novashop-production logs deploy/novashop-backend | grep -i otel

# No tracing backend is deployed, and nothing claims otherwise
kubectl get applications -n argocd | grep -i -E 'tempo|otel|jaeger' || echo "none, as documented"
```
