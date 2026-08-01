# Runbook: IngressErrors

**Severity:** critical · **Fires after:** 10 minutes · **Threshold:** more than 5% of requests are 5xx

## What it means

Traefik is returning server errors for more than one request in twenty. This is
measured at the edge, so it counts failures the application never saw — a backend
with no ready pods produces 5xx here while the application's own metrics stay
clean.

## Reading it together with the application metric

Comparing this alert against [ApplicationErrorRate](application-error-rate.md)
localises the fault without any further investigation:

| Edge 5xx | App 5xx | Meaning |
|---|---|---|
| high | high | The application is failing; the edge is reporting it faithfully |
| high | low or absent | No healthy backend to route to — a routing or readiness fault |
| low | high | Errors are being absorbed before the edge, e.g. retried |

## Diagnose

Which service, and which status code:

```promql
sum by (service, code) (rate(traefik_service_requests_total{code=~"5.."}[10m]))
```

The code narrows it sharply:

- **502 / 503** — Traefik has no healthy endpoint. Almost always readiness, not
  the application. Go to [DeploymentFailed](deployment-failed.md).
- **504** — the backend accepted the connection and did not answer in time. Go to
  [HighLatency](high-latency.md).
- **500** — a genuine application error. Go to
  [ApplicationErrorRate](application-error-rate.md).

Then confirm against the cluster and the logs:

```sh
sudo k3s kubectl -n novashop-production get endpoints
```

```logql
{source="kubernetes", app="traefik"} |= "\"DownstreamStatus\":5"
```

## Fix

Route by what the code told you. If it is 502/503 with empty endpoints, the fault
is that no pod is ready — fixing the pods fixes the edge, and there is nothing to
change in Traefik.

## Verify

```promql
sum(rate(traefik_service_requests_total{code=~"5.."}[5m]))
/ sum(rate(traefik_service_requests_total[5m]))
```
