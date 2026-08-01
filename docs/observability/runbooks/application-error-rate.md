# Runbook: ApplicationErrorRate

**Severity:** critical · **Fires after:** 10 minutes · **Threshold:** more than 5% of requests are 5xx

## What it means

The backend itself recorded server errors on more than one request in twenty. This
is measured inside the FastAPI application, so unlike
[IngressErrors](ingress-errors.md) it cannot be caused by routing, readiness, or
the network: the request reached a handler and the handler failed.

## Diagnose

The `route` label is a route *template*, not a raw path, so it groups correctly
and is safe to aggregate on:

```promql
sum by (route, status) (rate(novashop_http_requests_total{status=~"5.."}[10m]))
```

Then read the logs for the same window. Errors carry a stack trace:

```logql
{source="kubernetes", namespace="novashop-production", container="backend"}
  |= "ERROR"
```

Check whether the dependencies are the cause before reading application code —
`pg_up` and `redis_up` answer that in one query, and a failure there means this
alert is a symptom of [DatabaseDown](database-down.md) or
[RedisDown](redis-down.md).

## If the route label reads `unmatched`

Requests hit no registered route. That is a 404 in normal operation, so seeing it
alongside 5xx means something is generating traffic to paths the application does
not serve — usually a stale frontend build or a scanner.

## Fix

The overwhelming majority of the time the right action is to roll back to the
previous image, then diagnose without production pressure:

```sh
# In the GitOps repository, revert the commit that changed the backend image tag.
git revert <sha> && git push
```

Argo CD converges within three minutes. Do not patch the Deployment directly —
self-heal reverts it.

## Verify

```promql
sum(rate(novashop_http_requests_total{status=~"5.."}[5m]))
/ sum(rate(novashop_http_requests_total[5m]))
```

## If this alert has never fired and never will

Check the metric exists at all:

```promql
sum(novashop_http_requests_total)
```

No data means the backend is not being scraped rather than that it is healthy. The
scrape annotation must name the **container** port (8000), not the Service port —
endpoints-role discovery connects to the pod IP, so a Service port in the
annotation yields connection refused on every replica. This has already been the
cause once.
