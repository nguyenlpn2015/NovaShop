# Observability Guide

Using the observability stack: where to look, what to query, and how to tell "healthy" from
"not collecting".

For component design see [Observability Flow](../architecture/observability-flow.md) and
[ADR 009](../../adr/009-observability-stack.md). For what to do when an alert fires, go to its
[runbook](../observability/runbooks/).

## Getting access

Nothing is published. Access is by port-forward, because publishing Grafana needs a DNS
record, a certificate, and an authentication decision that has not been made.

```sh
kubectl -n observability port-forward svc/novashop-grafana 3000:80
kubectl -n observability port-forward svc/novashop-prometheus-server 9090:80
kubectl -n observability port-forward svc/novashop-prometheus-alertmanager 9093:9093
kubectl -n observability port-forward svc/novashop-loki 3100:3100
```

Grafana credentials are in the `novashop-grafana-admin` Secret, created outside Git.

## The first question: is it healthy, or is it not collecting?

These look identical and this is the most important distinction in the whole stack. A scrape
job whose relabel rules match nothing renders correctly, deploys correctly, and collects
nothing — reporting perfect health it cannot observe.

Three queries, in this order:

```promql
count(up)                    # expect 31
up == 0                      # expect empty
count(ALERTS)                # queryable; 0 on a healthy platform
```

If a metric you expect returns nothing, do **not** conclude the subsystem is idle. Check
whether the series exists at all:

```promql
count({__name__=~"novashop_.*"})
```

No series means not collected. Then check the target:

```sh
# Prometheus UI → Status → Targets, or:
curl -s localhost:9090/api/v1/targets | python3 -c "import json,sys;[print(t['labels'].get('job'),t['health'],t.get('lastError','')) for t in json.load(sys.stdin)['data']['activeTargets'] if t['health']!='up']"
```

This platform has already had a silent collection failure: the backend's scrape annotation
named the Service port instead of the container port, so all six production replicas returned
connection refused and `novashop_http_requests_total` simply did not exist. Nothing was
unhealthy. Nothing alerted.

## Metrics worth knowing

**Node**

```promql
1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)
1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m]))
node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}
```

**Workloads**

```promql
kube_deployment_status_replicas_available < kube_deployment_spec_replicas
increase(kube_pod_container_status_restarts_total[15m])
```

**Edge** — pin the job. Traefik is currently scraped twice, by its dedicated job and by the
chart's default annotation-based one, so an unpinned sum counts each series twice:

```promql
sum by (service, code) (rate(traefik_service_requests_total{job="traefik"}[10m]))

histogram_quantile(0.95,
  sum by (service, le) (rate(traefik_service_request_duration_seconds_bucket{job="traefik"}[10m])))
```

**Application** — `route` is a route template, safe to aggregate on:

```promql
sum by (route, status) (rate(novashop_http_requests_total[10m]))
novashop_http_requests_in_flight
```

Requests piling up in flight while CPU is idle means the application is blocked on something
downstream, not short of capacity.

**Dependencies and certificates**

```promql
pg_up
redis_up
(certmanager_certificate_expiration_timestamp_seconds - time()) / 86400
argocd_app_info{sync_status!="Synced"}
```

The certificate query should read close to 90 after a renewal and never below 30 on a healthy
platform.

## Logs

Loki holds 120 hours. Labels are deliberately low cardinality — `namespace`, `pod`,
`container`, `app`, `component`, `source`, `cluster`. Anything request-specific is in the log
line, not a label.

```logql
{source="kubernetes", namespace="novashop-production"}
{source="kubernetes", namespace="novashop-production", container="backend"} |= "ERROR"
{source="kubernetes", app="traefik"} |= "\"DownstreamStatus\":5"
{source="journal", unit="k3s.service"}
```

Logs outlive the pod, which is what makes them usable on a container that is restarting faster
than you can attach.

Guard against cardinality if log volume grows unexpectedly:

```logql
topk(10, sum by (namespace) (count_over_time({source="kubernetes"}[1h])))
```

One label carrying a request ID, trace ID, or raw path creates one stream per distinct value
and fills a 2Gi volume in hours.

## Alerts

Fourteen rules. Each carries a `runbook_url`, and
`scripts/validate-observability.sh` fails a pull request if any of those links points at a
file that does not exist.

```promql
ALERTS{alertstate="firing"}
ALERTS{alertstate="pending"}
```

`pending` means the threshold is currently breached but has not held for the rule's `for`
duration. It is worth reading rather than waiting out — a pending alert is a real condition
that has not yet been confirmed. When Alertmanager was first deployed, `ArgoSyncFailed` went
pending within a minute and correctly identified a genuine permanent drift introduced by that
same deployment.

**Notifications go nowhere.** Alertmanager has one receiver with no destination, because
delivering to Slack or PagerDuty needs a credential this repository does not hold and a
decision about who is on call. Alerts still evaluate, appear in the Alertmanager UI, and are
queryable as above. [alerts.md](../observability/alerts.md) gives the exact values change and
Secret to add a destination.

The full table of rules, thresholds, and rationale is in
[alerts.md](../observability/alerts.md).

## Dashboards

Provisioned from ConfigMaps carrying the `grafana_dashboard` label, so each dashboard is a
reviewable file in Git.

**Do not create dashboards in the UI.** A dashboard that exists only in Grafana's database is
lost with the volume, cannot be reviewed in a pull request, and cannot be restored — and the
Grafana volume is `local-path`, so it is node-local and not in the backup.

## Retention, and what it costs

| Store | Retention | Volume |
|---|---|---|
| Prometheus | 7 days **and** 2GB | 3Gi |
| Loki | 120 hours | 2Gi |
| Grafana | dashboards from Git | 512Mi |
| Alertmanager | silences and notification state | 256Mi |

Both caps on Prometheus are deliberate: one disk holds the k3s datastore, PostgreSQL, and
every volume, so time alone bounds nothing.

If a volume exceeds its configured size, **retention is not being enforced** — that is a bug
to fix, not disk to add. Growing it only postpones the same alert. See
[ObservabilityVolumeFilling](../observability/runbooks/observability-volume-filling.md).

## Traces

There are none. The OpenTelemetry instrumentation exists and is disabled; no collector is
deployed. The reason and what would change it are in
[ADR 011](../../adr/011-distributed-tracing.md).

## Validating the configuration

```sh
bash scripts/validate-observability.sh --gitops-dir ../NovaShop-GitOps
```

25 checks. What it cannot check is whether an expression matches real label names — that is
verified by hand against live Prometheus, and it is worth doing for any new rule. Evaluate the
expression, then strip the comparison to see whether the inputs exist at all. Doing exactly
that revealed the duplicate Traefik scrape.
