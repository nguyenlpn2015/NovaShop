# Runbook: DiskFull

**Severity:** critical · **Fires after:** 10 minutes · **Threshold:** root filesystem below 15% free

## What it means

The node's root filesystem is running out. On this platform that volume holds
everything: container images, the k3s SQLite datastore, PostgreSQL, and every
`local-path` PersistentVolume including Prometheus and Loki.

## Impact

A full disk does not degrade gracefully. PostgreSQL refuses writes, k3s cannot
write to SQLite, and Prometheus stops recording — including stopping its record of
the disk filling up.

## Diagnose

```sh
df -h /
sudo du -xh --max-depth=1 / 2>/dev/null | sort -rh | head -20
sudo du -sh /var/lib/rancher/k3s/storage/*
sudo k3s crictl images | wc -l
```

## Fix

Least destructive first.

**1. Reclaim image layers.** Usually the largest win and always safe:

```sh
sudo k3s crictl rmi --prune
```

**2. Check retention is actually being enforced.** Prometheus is capped at 7 days
and 2GB, Loki at 120 hours with the compactor running. A `local-path` volume that
has grown past its configured size means retention is not working — that is a bug
to fix, not disk to add. [ObservabilityVolumeFilling](observability-volume-filling.md)
covers this case directly.

**3. Check PostgreSQL** if the database is the consumer:

```sh
sudo -u postgres psql -c "SELECT pg_size_pretty(pg_database_size('novashop'));"
```

**4. Grow the volume** — only after the above, and only because the growth is
legitimate.

## Do not

Delete anything under `/var/lib/rancher/k3s/server/db/`. That is the cluster
datastore; restore it from backup instead
([disaster-recovery.md](../../recovery/disaster-recovery.md)).
