# Runbooks

The runbooks live in **[docs/observability/runbooks/](../docs/observability/runbooks/)**.

They are kept there because each one is the target of a `runbook_url` in an alert rule, and
`scripts/validate-observability.sh` fails a pull request if any of those links points at a
file that does not exist. Keeping them next to the alerting they serve means a rule and its
response are reviewed in the same change.

## Index

| Runbook | Severity |
|---|---|
| [NodeDown](../docs/observability/runbooks/node-down.md) | critical |
| [DiskFull](../docs/observability/runbooks/disk-full.md) | critical |
| [MemoryHigh](../docs/observability/runbooks/memory-high.md) | warning |
| [CPUHigh](../docs/observability/runbooks/cpu-high.md) | warning |
| [PodCrashLooping](../docs/observability/runbooks/pod-crashlooping.md) | critical |
| [DeploymentFailed](../docs/observability/runbooks/deployment-failed.md) | critical |
| [ArgoSyncFailed](../docs/observability/runbooks/argo-sync-failed.md) | warning |
| [DatabaseDown](../docs/observability/runbooks/database-down.md) | critical |
| [RedisDown](../docs/observability/runbooks/redis-down.md) | critical |
| [CertificateExpiring](../docs/observability/runbooks/certificate-expiring.md) | critical |
| [IngressErrors](../docs/observability/runbooks/ingress-errors.md) | critical |
| [HighLatency](../docs/observability/runbooks/high-latency.md) | warning |
| [ApplicationErrorRate](../docs/observability/runbooks/application-error-rate.md) | critical |
| [ObservabilityVolumeFilling](../docs/observability/runbooks/observability-volume-filling.md) | warning |

Thresholds and rationale for all fourteen:
[docs/observability/alerts.md](../docs/observability/alerts.md).

## For a problem with no alert

[docs/operations/troubleshooting.md](../docs/operations/troubleshooting.md).
