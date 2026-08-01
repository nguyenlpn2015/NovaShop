# ADR 004: Grafana Alloy as the single collection agent

## Status

Accepted

## Date

2026-08-01

## Context

The Sprint 5.1 brief named seven components, among them Promtail for logs and
the OpenTelemetry Collector for traces. Two facts about the target environment
made adopting both the wrong call.

Promtail reached end of life in March 2026. Grafana froze its features in
February 2025 and directed users to Alloy. It receives no further fixes,
including security fixes.

The node is small and already oversubscribed. Measured at the time of this
decision: roughly 7.9Gi allocatable memory, requests at 31%, and container
memory **limits already committed to 119%** of allocatable. Two agents mean two
DaemonSets, two config surfaces, and two sets of requests on a node that also
runs PostgreSQL, Redis, three application environments, Argo CD, and the metrics
stack.

## Decision

Grafana Alloy performs both roles. It collects container and journal logs now,
and in Phase 7 it terminates OTLP and forwards traces to Tempo.

Promtail and the OpenTelemetry Collector are not deployed.

## Alternatives Considered

**Promtail plus OpenTelemetry Collector, exactly as briefed.** Rejected on the
end-of-life fact alone. Shipping an unmaintained agent into a platform whose
stated purpose is demonstrating production practice would undercut the whole
exercise, and it costs an additional workload for no capability Alloy lacks.

**Promtail for logs, Alloy for traces.** Halves the redundancy but keeps the
unmaintained component and still runs two agents. No advantage over Alloy alone.

**OpenTelemetry Collector for both, with the filelog receiver.** Technically
viable and vendor neutral, which is its real argument. Rejected here because
the backends are Loki and Tempo, Alloy's Loki integration needs no translation
layer, and its Kubernetes log source reads through the API rather than requiring
host path mounts. Worth revisiting if the platform ever targets a non-Grafana
backend.

**Filebeat, Fluent Bit, Vector.** Each is capable. All three would introduce a
technology with no other role in this platform, which the sprint brief
explicitly rules out.

## Consequences

One DaemonSet collects logs and, from Phase 7, receives traces. Roughly 250Mi of
requests are saved against a node that has none to spare, and there is one
configuration file to review rather than two.

Alloy's configuration language is not YAML. Anyone editing it needs to read
Alloy syntax, which is a genuine learning cost that a Promtail `scrape_configs`
block would not have carried.

The platform is now more tied to the Grafana ecosystem. Moving to a different
tracing or logging backend later would mean replacing the agent rather than
repointing an exporter.

Container logs are read through the Kubernetes API rather than from host paths.
That avoids a hostPath mount for pod logs and keeps collection inside RBAC, at
the cost of some API server load. On one node with fewer than thirty pods that
cost is not measurable. It would be on a large cluster, where the file-based
source is the better choice.

Journald still requires a host mount, so `/var/log` is mounted read-only. System
logs cannot be collected any other way.

## Validation

```bash
bash scripts/validate-observability.sh
```

The gate renders the Alloy chart, asserts every container declares requests and
limits, and confirms Loki renders without the caches, gateway, canary, and MinIO
that the chart enables by default.

After deployment, logs from all three sources must be queryable:

```logql
{source="kubernetes", namespace="novashop-production"}
{source="journal", unit="k3s.service"}
{source="kubernetes", app="traefik"}
```
