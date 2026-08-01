# Runbook: HighLatency

**Severity:** warning · **Fires after:** 10 minutes · **Threshold:** p95 above 1 second

## What it means

Traefik's 95th percentile response time has been above one second for ten minutes.
The p95 is used rather than the mean because a mean hides exactly the tail that
users notice.

## Impact

Slow, not broken. Left alone it usually becomes broken: as requests take longer,
in-flight work accumulates, and eventually connections queue past the timeout and
the alert turns into [IngressErrors](ingress-errors.md) with 504s.

## Diagnose

Narrow to a service first:

```promql
histogram_quantile(0.95,
  sum by (service, le) (rate(traefik_service_request_duration_seconds_bucket[10m])))
```

Then check whether the application agrees. Traefik measures the whole round trip
including the network; the application measures only its own handler. The gap
between them is where the time goes:

```promql
histogram_quantile(0.95,
  sum by (route, le) (rate(novashop_http_request_duration_seconds_bucket[10m])))
```

| Edge slow | App slow | Where the time is |
|---|---|---|
| yes | yes | Inside the application — database, Redis, or its own work |
| yes | no | Between Traefik and the pod, or queueing before the handler |

Concurrency is worth a look before anything else:

```promql
novashop_http_requests_in_flight
```

Requests piling up in flight while CPU is idle means the application is blocked on
something downstream, not short of capacity.

## Common causes here

1. **CPU throttling.** Check [CPUHigh](cpu-high.md). A throttled container is slow
   at everything simultaneously, which is the easiest case to recognise.
2. **Database latency.** The connection pool opens with `min_size=0`, so the first
   request after an idle period pays connection setup. A steady p95 above one
   second is not this; an intermittent spike after quiet periods might be.
3. **Node saturation.** [MemoryHigh](memory-high.md) — swap or reclaim pressure
   slows everything without any single workload looking guilty.

## Fix

There is no generic fix; the diagnosis above says which subsystem to address. What
matters is not treating the symptom by raising the timeout, which converts a
visible slowdown into an invisible one.
