# Local Development Guide

Running NovaShop on your own machine. Three paths, and the right one depends on what you are
trying to do.

| You want to | Use | Time |
|---|---|---|
| Change the application | [Docker Compose](#running-the-application) | 2 minutes |
| See it running on Kubernetes | [Docker Desktop Kubernetes](#running-on-kubernetes-docker-desktop) | 5 minutes |
| Check the platform is correct | [The three gates](#running-the-platform-gates-locally) | 5 minutes, no cluster |

## What local development is not

None of these paths runs Argo CD, cert-manager, TLS, or the observability stack. They run on
HTTP with no certificates and no GitOps reconciliation.

That is a decision, not a gap. **GitOps is the thing the real platform demonstrates, and
simulating it locally would teach the shape without the substance** — a second set of
manifests to keep in step with the real ones, drifting silently because each version is
individually valid.

The platform is validated instead by the same gates CI runs, against the real configuration.

## Running on Kubernetes (Docker Desktop)

The closest local equivalent of the node. Same Helm chart, same images pulled from GHCR by
commit SHA, same Traefik ingress, same local-path storage, same Alembic migration Job.

**Prerequisites:** Docker Desktop with Kubernetes enabled (Settings → Kubernetes → Enable).
Helm is not required — the script renders the chart through a container, because requiring a
Helm install would put a tool between you and a first working deployment.

```powershell
cd D:\Projects\NovaShop
.\scripts\deploy-local-k8s.ps1
```

It refuses to run if `kubectl config current-context` is not `docker-desktop`. Applying a
development manifest to whichever cluster happens to be selected is how people deploy to the
wrong place, and the wrong place is sometimes production.

Expect:

```
==> Preflight
    Context: docker-desktop
==> Checking the images exist in GHCR
    backend image present
    frontend image present
==> Namespace novashop-local
    Created, with pod-security enforce=restricted
==> Migration and seed
    Schema applied and demo data seeded
==> Verifying
    Backend readiness 200, both dependencies healthy
    Products seeded: 128
```

Then reach it either way:

```powershell
# Port-forward. Works whether or not an ingress controller is installed.
kubectl port-forward -n novashop-local svc/novashop-frontend 3000:80
# http://localhost:3000

# Or through Traefik. No hosts file and no administrator: *.localhost resolves
# to 127.0.0.1 on Windows, macOS and Linux without any configuration.
# http://novashop.localhost
# http://api.novashop.localhost/docs
```

Remove everything with `.\scripts\deploy-local-k8s.ps1 -Uninstall`. It deletes one namespace,
because everything the script creates lives in one namespace.

### Where this differs from the node, and why

| Local | Node | Reason |
|---|---|---|
| PostgreSQL and Redis in the cluster | On the host | On one node a database in a pod adds failure modes — the pod, the PVC, the scheduler — without the rescheduling benefits that justify them at scale. Locally, self-contained and disposable matters more |
| No Argo CD | Argo CD reconciles everything | The script applies once and stops. Nothing self-heals; if you `kubectl delete` something it stays deleted |
| No TLS | Let's Encrypt, HSTS | Let's Encrypt cannot issue a certificate for `localhost` |
| NetworkPolicy disabled | Default-deny ingress | The rules admit `10.10.1.0/24` for kubelet probes. Docker Desktop's node network is different, so enabling them would take every replica NotReady for a reason unrelated to the policies being wrong |
| One replica each | 1 / 1 / 2 | Two proves nothing locally and doubles what a laptop spends on a demonstration |
| PostgreSQL 14 | PostgreSQL 14 | Matches deliberately. Compose uses 17.9, which is a real inconsistency — see [below](#where-local-differs-from-the-node) |

**Pod Security Admission is set to `restricted` on the local namespace on purpose.** A chart
change that violates it then fails on your machine rather than at sync time on the node.

## Prerequisites

| Tool | For |
|---|---|
| Docker Desktop or Docker Engine + Compose v2 | Running the stack |
| Python 3.12 | Backend tooling outside the container |
| Node 22 | Frontend tooling outside the container |
| `helm`, `kustomize`, `kubeconform`, `yamllint`, `python3` + PyYAML, `docker` | Running the platform gates |

The Python and Node major versions are not free choices. `validate-platform.sh` asserts they
match across the Dockerfiles, the workflow environment variables, `engines.node`,
`@types/node`, and `requires-python` — these drift silently and the symptom appears far from
the cause.

## Running the application

```sh
cp .env.example .env
docker compose up --build
```

| Service | URL |
|---|---|
| Frontend | http://localhost:3000 |
| Backend | http://localhost:8000 |
| API docs | http://localhost:8000/docs |
| Metrics | http://localhost:8000/metrics |

PostgreSQL and Redis run as containers. Note that Compose uses `postgres:17.9-alpine` while
the node runs **PostgreSQL 14** — see the caveat below.

Optional hostnames on Windows:

```powershell
# Maps novashop.local and api.novashop.local to 127.0.0.1
.\scripts\configure-local-hosts.ps1
```

## Health endpoints, and why there are three

```sh
curl localhost:8000/live      # consults nothing
curl localhost:8000/ready     # checks PostgreSQL and Redis, 503 if either is unreachable
curl localhost:8000/metrics
```

`/live` deliberately checks no dependency. A liveness probe that fails when the database is
unreachable restarts a healthy process and turns a datastore outage into a crash loop.
`/ready` returns 503 instead, so the pod stops receiving traffic and recovers on its own —
no restart, because it re-checks rather than caching the failure.

If you change these, keep that distinction.

## Tests and linting

```sh
# Backend
cd backend
pip install -e '.[dev]'
ruff check . && mypy . && pytest

# Frontend
cd frontend
npm ci
npm run lint && npx tsc --noEmit && npm run build
```

These are the same commands `validation.yml` runs. Running them locally is faster than
learning the result from a pull request.

## Running the platform gates locally

The most useful thing in this guide. All three gates run outside a cluster, against the
repository as it stands:

```sh
git clone https://github.com/nguyenlpn2015/NovaShop-GitOps.git ../NovaShop-GitOps

bash scripts/validate-platform.sh          --gitops-dir ../NovaShop-GitOps
bash scripts/validate-gitops-revisions.sh  --gitops-dir ../NovaShop-GitOps
bash scripts/validate-observability.sh     --gitops-dir ../NovaShop-GitOps
```

Expect `PASS 38/38`, `PASS 30/30`, and `PASS 25/25`.

**If `helm` is not installed**, the gates can still be run through a container. Put a wrapper
on `PATH` that shells out to `alpine/helm`, mounting the repository at `/repo`. This is how
the observability gate was verified end to end on a machine with no local Helm, including
its negative cases.

**On Windows**, `python3` often resolves to the Microsoft Store launcher, which is on `PATH`
and is not an interpreter. The gates handle this by *executing* each candidate rather than
merely locating it — if you write similar tooling, do the same.

## Metrics instrumentation

`backend/app/observability/metrics.py` is hand-written `prometheus_client` instrumentation:

| Metric | Labels |
|---|---|
| `novashop_http_requests_total` | `method`, `route`, `status` |
| `novashop_http_request_duration_seconds` | `method`, `route` |
| `novashop_http_requests_in_flight` | — |
| `novashop_build_info` | `version`, `environment` |

The `route` label is a route **template**, read from `scope["route"]` after routing — not a
raw path. Raw paths would make cardinality unbounded, and an earlier version that iterated
`app.routes` missed FastAPI's `_IncludedRouter` and labelled every request `unmatched`. A
test catches that now; keep it passing.

Tracing lives in `backend/app/observability/tracing.py` and is disabled unless
`OTEL_EXPORTER_OTLP_ENDPOINT` is set. There is no collector to point it at — see
[ADR 011](../../adr/011-distributed-tracing.md).

## Where local differs from the node

Know these before concluding that something works.

| | Local | Node |
|---|---|---|
| PostgreSQL | 17.9 container | **14**, on the host |
| Redis | container, no password | host, `requirepass` set |
| TLS | none | Let's Encrypt, HSTS in the enforced phase |
| Ingress | direct ports | Traefik, routed by `Host` |
| Reconciliation | none | Argo CD, `selfHeal` on |

The PostgreSQL major version gap is the one that has bitten. PostgreSQL 14 grants `CREATE`
on the `public` schema to `PUBLIC`; 15 removed that. A permissions assumption that holds on
17 locally can be wrong on the node, which is exactly how the metrics exporter ended up able
to create tables.

## Teardown

```sh
docker compose down -v      # -v also removes the database volume
```

## Next

- [Production Deployment](production-deployment.md)
- [CONTRIBUTING.md](../../CONTRIBUTING.md)
- [Architecture](../architecture/)
