# Container Diagram

C4 level 2. What actually runs inside the boundary, and how the pieces reach each
other. Versions are the versions deployed.

```mermaid
flowchart TB
    IN["Internet"] --> TR

    subgraph node["Ubuntu 22.04 node — 10.10.1.45 — k3s v1.33.13+k3s1"]
        subgraph ks["kube-system"]
            TR["<b>Traefik</b> 3.7.4<br/>chart 40.1.3+up40.1.0<br/><i>ingress, TLS termination</i><br/>metrics: pod :9100"]
            CD["CoreDNS"]
            LP["local-path provisioner<br/><i>the only StorageClass</i>"]
            MS["metrics-server"]
        end

        subgraph cm["cert-manager"]
            CMC["<b>cert-manager</b> v1.21.0<br/><i>ACME HTTP-01</i><br/>metrics :9402"]
        end

        subgraph ac["argocd"]
            ACC["<b>Argo CD</b><br/>application-controller<br/>repo-server, server,<br/>applicationset-controller<br/>metrics :8082"]
        end

        subgraph apps["novashop-development / -staging / -production"]
            FE["<b>frontend</b><br/>Next.js<br/>1 / 2 / 3 replicas"]
            BE["<b>backend</b><br/>FastAPI<br/>1 / 2 / 3 replicas<br/>/metrics :8000"]
        end

        subgraph obs["observability"]
            PR["<b>Prometheus</b> v3.13.2<br/>chart 29.20.1<br/><i>7d / 2GB, 3Gi PVC</i>"]
            AM["<b>Alertmanager</b><br/><i>14 rules, 256Mi PVC</i>"]
            GR["<b>Grafana</b> 12.3.1<br/>chart 10.5.15"]
            LO["<b>Loki</b> 3.6.11<br/>single binary, filesystem<br/><i>120h, 2Gi PVC</i>"]
            AL["<b>Alloy</b> v1.18.0<br/>DaemonSet<br/><i>logs</i>"]
            KSM["kube-state-metrics"]
            NE["node-exporter"]
            PE["postgres-exporter 8.2.0"]
            RE["redis-exporter 6.28.0"]
        end

        subgraph host["Host services — outside k3s"]
            PG["<b>PostgreSQL 14</b><br/>10.10.1.45:5432"]
            RD["<b>Redis</b><br/>10.10.1.45:6379<br/><i>requirepass</i>"]
        end
    end

    TR --> FE
    TR --> BE
    BE -->|"asyncpg"| PG
    BE -->|"redis"| RD
    PE -->|"scrape target"| PG
    RE -->|"scrape target"| RD

    PR -->|"scrape"| TR & CMC & ACC & BE & KSM & NE & PE & RE & AM
    PR -->|"fires"| AM
    AL -->|"push"| LO
    AL -.->|"pod logs via API,<br/>journal via hostPath"| apps
    GR -->|"query"| PR
    GR -->|"query"| LO
    ACC -->|"reconciles<br/>everything above"| apps
    CMC -->|"issues Secret"| TR
```

## Reading the boundaries

**Traefik publishes metrics on the pod, not the Service.** Its Service exposes
`web` and `websecure` only. An endpoints-based scrape job would render, validate,
deploy, and collect nothing, so Prometheus discovers Traefik with `role: pod` and a
gate asserts that it still does. This is the single most instructive line in the
scrape configuration.

**The backend's scrape annotation names the container port.** Endpoints-role
discovery connects to the pod IP, so an annotation naming the Service port produces
connection refused on every replica while everything else looks healthy. It did,
once, across six production pods.

**PostgreSQL and Redis are on the host.** Pods reach them at `10.10.1.45` over the
cluster network, which is why `pg_hba.conf` carries a rule for `10.42.0.0/16` and
why `listen_addresses` cannot be loopback only. Both are managed by
`scripts/linux/configure-datastores.sh` inside marked blocks so the script is
idempotent.

**The exporters are least-privilege.** PostgreSQL 14 grants `CREATE` on the `public`
schema to `PUBLIC`, so `pg_monitor` alone let the exporter create tables. That grant
is revoked and given to the application role only. Verified by attempting a write as
the exporter and having it denied.

**Alloy reads pod logs through the Kubernetes API**, not from host paths, so it
needs no hostPath mount for containers and cannot read outside its RBAC. The journal
is the one exception and the reason `varlog` is mounted.

## Replica counts

| Environment | Namespace | frontend | backend |
|---|---|---|---|
| development | `novashop-development` | 1 | 1 |
| staging | `novashop-staging` | 2 | 2 |
| production | `novashop-production` | 3 | 3 |

Three replicas on one node is a demonstration of scaling mechanics, not capacity.
It is also why node memory limits sit near 150% of allocatable, and why
[MemoryHigh](../observability/runbooks/memory-high.md) says to reduce replicas
before raising thresholds.

## The health endpoints, and why there are three

| Endpoint | Consults | Used by |
|---|---|---|
| `/health` | nothing | legacy, retained |
| `/live` | nothing | liveness probe |
| `/ready` | PostgreSQL **and** Redis | readiness probe |

`/live` deliberately checks no dependency. A liveness probe that fails when the
database is unreachable restarts a healthy process and turns a datastore outage into
a crash loop. `/ready` returns 503 instead, so the pod stops receiving traffic and
recovers on its own when the dependency returns — no restart needed, because it
re-checks rather than caching the failure.

## Next

[Deployment Diagram](deployment.md) puts this on hardware.
