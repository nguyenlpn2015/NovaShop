# Runbook: CPUHigh

**Severity:** warning · **Fires after:** 15 minutes · **Threshold:** above 85% busy

## What it means

Sustained CPU saturation. Spikes during an image build or an Argo CD sync are
normal and will not hold for fifteen minutes.

## Impact

CPU pressure throttles rather than kills. Requests slow, readiness probes begin
timing out, and healthy pods get marked unready — which then raises
[DeploymentFailed](deployment-failed.md) as a second, misleading alert.

## Diagnose

```sh
top -b -n1 | head -20
sudo k3s kubectl top pods -A --sort-by=cpu | head -20
```

Check whether containers are being throttled rather than merely busy:

```promql
rate(container_cpu_cfs_throttled_seconds_total[5m]) > 0
```

Throttling with low absolute usage means a limit is set too low, which is a
different fix from genuine load.

## Fix

The usual causes on this node, most frequent first:

1. A container whose CPU limit is below what it needs, spinning in throttle.
2. Prometheus compaction — periodic and self-limiting, wait it out.
3. A genuine traffic increase, which needs capacity rather than tuning.

Adjust limits in Git. Self-heal reverts live edits.
