# Runbook: RedisDown

**Severity:** critical · **Fires after:** 2 minutes · **Expression:** `redis_up == 0`

## What it means

`redis-exporter`, running in the cluster, cannot reach or authenticate to Redis.
Like PostgreSQL, Redis runs on the node and is reached over the pod network, so
this covers the service being down, the bind address being wrong, and the password
being wrong.

## Impact

The backend's `/ready` probe checks Redis, so backend pods go unready — see
[DeploymentFailed](deployment-failed.md).

## Diagnose

On the node:

```sh
sudo systemctl status redis-server
sudo ss -ltnp | grep 6379          # expect 10.10.1.45:6379
grep -n '^bind' /etc/redis/redis.conf
```

Authentication is enabled (`requirepass`), so an unauthenticated ping is *expected*
to fail with `NOAUTH`. That response actually proves Redis is alive and reachable:

```sh
redis-cli -h 10.10.1.45 ping       # NOAUTH means healthy and protected
```

From the cluster:

```sh
sudo k3s kubectl -n observability logs deploy/novashop-redis-exporter --tail=50
```

## Fix

| Finding | Action |
|---|---|
| Service stopped | `sudo systemctl start redis-server` |
| Bound to loopback only | Rerun `scripts/linux/configure-datastores.sh` |
| `NOAUTH` in exporter logs | The Secret's password does not match `requirepass` |
| Connection refused from pods | Check the node firewall did not gain a rule blocking the pod CIDR |

The bind address and `requirepass` are managed by
`scripts/linux/configure-datastores.sh`, which sources the password from
`REDIS_URL` in `/root/.novashop-platform.env` and restarts Redis only when the
configuration actually changed.

## Verify

```promql
redis_up == 1
```
