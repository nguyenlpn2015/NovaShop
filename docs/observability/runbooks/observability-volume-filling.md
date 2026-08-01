# Runbook: ObservabilityVolumeFilling

**Severity:** warning · **Fires after:** 15 minutes · **Threshold:** below 20% free

## What it means

A PersistentVolumeClaim in the `observability` namespace is running out of space.

This alert exists because observability that fills its disk stops recording, and
then stops recording that it stopped. Without it, the first sign of a full
Prometheus volume is a gap in every dashboard that nobody notices until they need
the data.

## Impact

Depends which claim:

| Claim | Effect when full |
|---|---|
| `prometheus-server` | Metrics stop. Every alert in this directory goes blind. |
| `novashop-loki` | Log ingestion stops; Alloy buffers, then drops. |
| `novashop-grafana` | Dashboards still render — they are provisioned from ConfigMaps, not the volume. |
| `alertmanager` | Silences and notification state are lost; alerts still evaluate. |

## Diagnose

```promql
kubelet_volume_stats_available_bytes{namespace="observability"}
/ kubelet_volume_stats_capacity_bytes{namespace="observability"}
```

```sh
sudo k3s kubectl -n observability get pvc
sudo du -sh /var/lib/rancher/k3s/storage/*
```

## The important question

Both Prometheus and Loki are configured with retention that should hold them
inside their volumes:

- Prometheus: 7 days **and** a 2GB size cap, on a 3Gi volume.
- Loki: 120 hours with `retention_enabled: true` and the compactor running, on a
  2Gi volume.

So a volume filling up is **not** a capacity problem to be solved by growing the
disk. It means retention is not being enforced, and growing the volume only
postpones the same alert. Establish which before doing anything else.

```sh
sudo k3s kubectl -n observability logs sts/novashop-loki --tail=100 | grep -i compact
sudo k3s kubectl -n observability logs deploy/novashop-prometheus-server -c novashop-prometheus-server --tail=100 | grep -i 'compact\|retention'
```

## Fix

| Finding | Action |
|---|---|
| Loki compactor not running | `compactor.retention_enabled` is off, or the compactor has no delete permission on the filesystem store |
| Prometheus above its size cap | `retention.size` is not set, or the flag is being overridden |
| Retention working, volume still full | Ingest genuinely grew — find the new source below |
| Volume smaller than configured | The claim used the default StorageClass instead of `local-path`; `storageClass` and `storageClassName` are different keys and getting it wrong is silent |

To find a new ingest source, the usual cause is label cardinality rather than
volume of lines:

```promql
topk(10, count by (job) ({__name__=~".+"}))
```

```logql
topk(10, sum by (namespace) (count_over_time({source="kubernetes"}[1h])))
```

A single label carrying a request id, trace id, or raw path creates one Loki
stream per distinct value and will fill a volume in hours. That is why labels on
this platform are restricted to route templates and low-cardinality metadata.
