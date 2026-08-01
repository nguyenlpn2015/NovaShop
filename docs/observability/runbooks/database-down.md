# Runbook: DatabaseDown

**Severity:** critical · **Fires after:** 2 minutes · **Expression:** `pg_up == 0`

## What it means

`postgres-exporter`, running in the cluster, cannot reach PostgreSQL. The database
runs on the node itself rather than in Kubernetes, and the exporter connects over
the pod network to `10.10.1.45:5432`. So this alert covers three distinct faults
that all look the same from inside the cluster:

1. PostgreSQL is down.
2. PostgreSQL is up but not listening on the address the pod network uses.
3. Authentication for the exporter's role is failing.

## Impact

Total for the application. The backend's `/ready` probe checks PostgreSQL, so
every backend pod goes unready and Traefik stops routing to them — you will also
see [DeploymentFailed](deployment-failed.md) and [IngressErrors](ingress-errors.md).

## Diagnose

On the node:

```sh
sudo systemctl status postgresql
sudo -u postgres psql -c 'SELECT 1'
```

If PostgreSQL is up, the fault is the path or the credentials. Check it is bound
to the address pods use, not only loopback:

```sh
sudo ss -ltnp | grep 5432          # expect 10.10.1.45:5432, not just 127.0.0.1
grep -n listen_addresses /etc/postgresql/*/main/postgresql.conf
grep -n '10.42.0.0/16' /etc/postgresql/*/main/pg_hba.conf
```

Both settings are written by `scripts/linux/configure-datastores.sh` inside marked
managed blocks. If either is missing, something outside the script edited the
file — rerun the script, it is idempotent.

From the cluster:

```sh
sudo k3s kubectl -n observability logs deploy/novashop-postgres-exporter --tail=50
```

`pg_hba.conf rejects connection` means the rule is missing. `password
authentication failed` means the credential in the `novashop-datastore-exporter`
Secret no longer matches the role.

## Fix

| Finding | Action |
|---|---|
| Service stopped | `sudo systemctl start postgresql` |
| Bound to loopback only | Rerun `scripts/linux/configure-datastores.sh` |
| pg_hba missing the pod CIDR | Same |
| Auth failing | Reset the exporter role's password and update the Secret |
| Disk full | [DiskFull](disk-full.md) — PostgreSQL stops writing before it stops listening |

## Verify

```promql
pg_up == 1
```

Backend pods return to ready on their own within one probe interval; no restart is
needed, because `/ready` re-checks rather than caching the failure.
