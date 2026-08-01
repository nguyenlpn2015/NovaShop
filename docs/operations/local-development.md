# Local Development Guide

Running NovaShop on your own machine. This path is for changing the application; it is
deliberately not a miniature of production.

## What local development is not

It does not run Argo CD, cert-manager, TLS, or the observability stack. It runs on HTTP with
no certificates and no GitOps reconciliation.

That is a decision, not a gap. Reproducing the platform locally would mean a second set of
manifests to keep in step with the real ones, and the copy would drift silently because each
version is individually valid. Instead, the platform is validated by the same gates CI runs —
which you can run locally against the real configuration — and the application is developed
against Docker Compose.

If you need to exercise Kubernetes behaviour, run the gates. If you need to exercise the
application, use Compose.

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
