# Application Data Provisioning

One-time node work required before the application gains a schema. Run it once per node.

Until this is done, all three environments point at the same PostgreSQL database and the same
Redis index. That is harmless while the backend only runs `SELECT 1` — and destructive the
moment there are tables, because seeding development would truncate production.

Everything here runs on the node as a user with `sudo`.

## 1. Three databases

The application user already exists. Each environment gets its own database, owned by that
user.

```sh
for env in development staging production; do
  sudo -u postgres createdb --owner=novashop "novashop_${env}"
done

sudo -u postgres psql -c '\l' | grep novashop
```

Expect four rows: the original `novashop` plus the three new ones.

**The original `novashop` database stays.** It is what the readiness probe and the metrics
exporter connect to today, and removing it would take every replica NotReady. It becomes empty
and unused once the Secrets below are updated; leave it, or drop it in a later change once
nothing references it.

`scripts/backup-datastores.sh` discovers databases rather than listing them, so the new ones
are backed up with no change to the script. Verify that after the first backup:

```sh
grep '^databases=' /path/to/backup/manifest.txt
```

## 2. Grants

The exporter must be able to read the new databases and must not be able to write to them.
The application must be able to create tables, because Alembic runs as it.

**Both statements are required, and the order matters.** On PostgreSQL 14, `CREATE` on schema
`public` is granted to `PUBLIC`, so `pg_monitor` alone does not make the exporter read-only.
PostgreSQL 15 removed that default.

```sh
for env in development staging production; do
  sudo -u postgres psql -q -d "novashop_${env}" \
    -c "GRANT CONNECT ON DATABASE novashop_${env} TO novashop_exporter;" \
    -c 'REVOKE CREATE ON SCHEMA public FROM PUBLIC;' \
    -c 'GRANT USAGE, CREATE ON SCHEMA public TO novashop;'
done
```

> **The `GRANT` on the last line is not optional, and omitting it is not a subtle failure.**
> An earlier version of this document had only the `REVOKE`. `PUBLIC` includes every role, so
> revoking `CREATE` from it also removed it from `novashop` — the role Alembic connects as.
> The migration Job then failed with `permission denied for schema public` while trying to
> create `alembic_version`, and because a failed PreSync hook is retried rather than fatal on
> the first attempt, the Application still reported **Synced and Healthy** with an empty
> database behind it.
>
> Revoking a privilege from `PUBLIC` revokes it from everyone. Grant it back to the one role
> that needs it, by name.

Verify both halves:

```sh
sudo -u postgres psql -d novashop_development -tAc \
  "SELECT 'app='   || has_schema_privilege('novashop','public','CREATE')
       || ' exporter=' || has_schema_privilege('novashop_exporter','public','CREATE')"
```

Expect `app=true exporter=false`.

## 3. One Redis index per environment

Redis has 16 numbered databases by default. No server change is needed — only the URL each
environment uses.

| Environment | Index |
|---|---|
| development | 0 |
| staging | 1 |
| production | 2 |

Cache keys are also prefixed by environment, so a mistake here degrades to a cache miss rather
than to one environment reading another's data. The index is the boundary; the prefix is the
seatbelt.

## 4. Update the three Secrets

Each environment's Secret must now carry its own database name and Redis index. Substitute the
real password.

```sh
for env in development staging production; do
  case "${env}" in
    development) index=0 ;;
    staging)     index=1 ;;
    production)  index=2 ;;
  esac

  kubectl create secret generic "novashop-${env}-secrets" \
    --namespace "novashop-${env}" \
    --from-literal=DATABASE_URL="postgresql://novashop:PASSWORD@10.10.1.45:5432/novashop_${env}" \
    --from-literal=REDIS_URL="redis://:PASSWORD@10.10.1.45:6379/${index}" \
    --dry-run=client --output=yaml \
  | kubectl apply --server-side --field-manager=novashop-runtime-bootstrap -f -
done

kubectl rollout restart deployment -n novashop-development
kubectl rollout restart deployment -n novashop-staging
kubectl rollout restart deployment -n novashop-production
```

Do not paste the password into a shell that records history. Read it into a variable with
`read -rs` first.

## 5. Reapply the AppProject

`argocd/project.yaml` is applied by `scripts/bootstrap.sh`, **not** reconciled by Argo CD, so
a change to it is a manual apply.

```sh
kubectl apply --server-side --field-manager=novashop-bootstrap \
  -f argocd/project.yaml

kubectl -n argocd get appproject novashop \
  -o jsonpath='{range .spec.namespaceResourceWhitelist[*]}{.kind}{"\n"}{end}' | sort
```

Expect `NetworkPolicy`, `Job`, `HorizontalPodAutoscaler` and `PodDisruptionBudget` in the
output.

### Check whether the NetworkPolicies were ever applied

The chart has rendered four NetworkPolicies since the default-deny change, and the whitelist
did not permit them. Argo CD enforces the whitelist at sync time, so they may never have
reached the cluster:

```sh
kubectl get networkpolicy -n novashop-production
```

Four policies means they were applied and the whitelist was edited on the cluster at some
point — in which case Git did not describe the cluster, which is its own problem. **No
policies means the security change was refused after merge**, and reapplying the AppProject
above is what fixes it. Either way, record what you found.

## 6. Verify

```sh
kubectl -n novashop-production exec deploy/novashop-backend -- \
  wget -qO- localhost:8000/ready
```

Both dependencies healthy. If PostgreSQL reports unhealthy, the database name in the Secret
does not match one that exists.
