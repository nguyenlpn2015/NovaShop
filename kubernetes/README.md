# kubernetes/

Platform component configuration. **The application is not here** — it is a Helm chart in
[`helm/novashop/`](../helm/novashop/), rendered by Argo CD with per-environment values from
[NovaShop-GitOps](https://github.com/nguyenlpn2015/NovaShop-GitOps).

| Path | What it is | Applied by |
|---|---|---|
| [`ingress/`](ingress/) | The three edge phases — `http`, `baseline`, `examples` | Argo CD, one phase at a time |
| [`cert-manager/`](cert-manager/) | Chart values, ClusterIssuers, Certificates | Argo CD |
| [`observability/`](observability/) | Values for Prometheus, Grafana, Loki, Alloy, exporters | Argo CD |
| [`secret.example.yaml`](secret.example.yaml) | The shape of `novashop-secrets` | **Nobody** — a template, see below |

## Why the edge exists in three directories

A cluster with no certificate cannot serve HTTPS, and cert-manager cannot obtain a certificate
for a host that is not already reachable. The phases resolve that ordering:

| Phase | Directory | State |
|---|---|---|
| `http` | `ingress/http/` | Serving on port 80. No TLS |
| `tls-baseline` | `ingress/baseline/` | TLS available, HTTP still accepted |
| `tls-enforced` | `ingress/examples/` | Redirect and HSTS |

`scripts/linux/verify.sh` detects which phase is live from cluster state rather than being
told, because a script that can be told can be told the wrong thing.

## The Secret is not in Git and never will be

`secret.example.yaml` shows the keys the backend expects. The real Secret is created by hand
on the node — see [ADR 010](../adr/010-secret-management.md) and
[Production Deployment](../docs/operations/production-deployment.md).

Two Secrets are deliberately outside GitOps. Argo CD reconciles everything else, and Grafana
and the datastore exporters stay unhealthy until these exist:

- `novashop-secrets` (`novashop-*` namespaces) — `DATABASE_URL`, `REDIS_URL`
- `novashop-grafana-admin`, `novashop-datastore-exporter` (`observability`)

## Everything here is validated before merge

`scripts/validate-platform.sh` renders and schema-checks every manifest in this directory with
`kubeconform`. Files matching `*-values.yaml` are excluded because Helm values are not
Kubernetes objects and have no `kind` — that exclusion was originally written to match one
literal filename and broke the moment a second values file appeared.

## What used to be here

Seven flat manifests — `backend-deployment.yaml`, `frontend-deployment.yaml`, their Services,
a ConfigMap, a Namespace, and an Ingress — dating from before the Helm chart existed. They
were unreferenced by any script, Application, or document, and had drifted: they still carried

```yaml
# TODO: Change to /live when the dedicated endpoint is available.
```

above a probe pointing at `/health`. Both `/live` and `/ready` have existed for some time. A
reader following those files would have configured probes the platform stopped using and
concluded that dependency-aware readiness had not been built.

They were deleted rather than corrected, because a second, unused description of how to deploy
the application is a liability whether or not it is accurate. Git history has them if they are
ever wanted.
