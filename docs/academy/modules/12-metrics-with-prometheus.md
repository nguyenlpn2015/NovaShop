# Module 12 — Metrics with Prometheus

*Part 5 · Observability · Intermediate*

This module is built around one defect: **six backend replicas exported no metrics at all, and
nothing reported unhealthy.** Understanding why takes you through service discovery, relabelling,
and the difference between a Service and an endpoint — which is most of what you need to operate
Prometheus.

## 1. Learning Objectives

After this module you can:

- Explain what `role: endpoints` discovers and what address it dials
- Say why `prometheus.io/port` must name the **container** port
- Explain why the Traefik job must use `role: pod` and cannot use `role: endpoints`
- Justify labelling HTTP metrics with a route template rather than a path
- Explain why a *disabled* scrape job was a deliberate reliability decision
- Read `validate-observability.sh` and say which of these mistakes it now catches

## 2. Theory

Prometheus **pulls**. It builds a target list from service discovery, applies `relabel_configs`
to each candidate, and scrapes what survives.

**Discovery roles** determine what the candidates are:

| Role | One target per | Address dialled |
|---|---|---|
| `endpoints` | Address in an Endpoints object | **Pod IP** and a port from the Endpoints |
| `pod` | Pod | **Pod IP** and a declared container port |
| `service` | Service | Service DNS name (blackbox probing) |

Note the first row carefully. `role: endpoints` is derived *from* a Service, but it does not
dial the Service. It dials the pods behind it. This one fact is the whole module.

**Relabelling** runs before the scrape. `action: keep` discards anything not matching;
`action: drop` discards anything matching; `target_label` writes a label. Every `__meta_*` label
is discovery metadata that disappears unless copied.

**Cardinality.** A time series is unique per label-value combination. Any label whose values come
from user input is unbounded, and unbounded means Prometheus memory grows until it dies.

## 3. Repository Walkthrough

### The annotation, and its comment

[`helm/novashop/templates/backend-service.yaml:10-20`](../../../helm/novashop/templates/backend-service.yaml) —
read the comment before the code:

```yaml
    # The port must be the CONTAINER port, not the Service port. Endpoints-role
    # discovery scrapes the pod address directly, so a Service port here means
    # Prometheus dials a port nothing listens on. Using service.port (80) is why
    # all six backend replicas reported connection refused at podIP:80 while
    # /metrics answered on 8000.
    prometheus.io/scrape: "true"
    prometheus.io/port: {{ .Values.backend.service.targetPort | quote }}
    prometheus.io/path: /metrics
```

`targetPort`, not `port`. The Service listens on 80 and forwards to 8000; the pod only ever
listens on 8000. Prometheus dialled `10.42.x.y:80` and got connection refused — from an address
where the Service is not involved at all.

Nothing was unhealthy. Pods were `Running`, probes passed, the Service served traffic, the
Ingress worked. The only symptom was an absence: `novashop_http_requests_total` returned no
data, which looks identical to "no requests yet".

### `extraScrapeConfigs` — three jobs, three lessons

[`kubernetes/observability/prometheus/helm-values.yaml:126-190`](../../../kubernetes/observability/prometheus/helm-values.yaml)

**`argocd`** — `role: endpoints`, keep port name `metrics`, then:

```yaml
      # Dex declares ports 5556, 5557, and 5558 but listens on none of them
      # while no SSO connector is configured...
      - source_labels: [__meta_kubernetes_service_name]
        action: drop
        regex: argocd-dex-server
```

A target that is down permanently and by design. The reason it is dropped is not tidiness — it is
that *a target list which is always partly red trains operators to stop reading it.* That
sentence is the observability principle of this whole repository.

**`cert-manager`** — same shape, keeping `(http-metrics|metrics)`, because the component and its
exporter name the port differently.

**`traefik`** — `role: pod`, and it must be:

```yaml
      # Traefik publishes metrics on the pod only. Its Service exposes web and
      # websecure and nothing else, so an endpoints-based job silently collects
      # zero series. This must stay pod-based.
```

Same failure mode as the backend defect, reached from the opposite direction. There, the wrong
*port* was named on the right role. Here, the right port exists but only the *pod* knows about
it. `role: endpoints` would have produced an empty target list — not an error, not a red target,
just nothing.

Note also `__meta_kubernetes_pod_container_port_name` — the **container** port name. With
`role: pod` there is no Endpoints object to read a port name from.

### The job that is deliberately switched off

```yaml
scrapeConfigs:
  prometheus-pushgateway:
    enabled: false
```

The chart defines that job whether or not the subchart is installed. Left on, it polls a Service
that does not exist. Same reasoning as Dex — a permanently red target is worse than no target,
because it costs attention every day and pays nothing.

### `backend/app/observability/metrics.py`

Read the module docstring first. It states the one decision that matters:

> Requests are labelled with the **matched route template**, never the raw path.

`/api/products/42` and `/api/products/43` must both become `/api/products/{product_id}`. Labelling
by path means a crawler probing a few thousand URLs permanently inflates Prometheus memory —
permanently, because the series persist for the full retention period even after the crawler
leaves.

Now read `route_template()` — specifically its last paragraph:

> Matching manually before routing is what an earlier revision did, and it was wrong. FastAPI
> wraps included routers, so iterating `app.routes` never sees the routes those routers declare
> and every request was labelled `unmatched`.

A second silent failure. The metric existed, was scraped, and reported one label value for every
request. The fix was to stop re-implementing route matching and read the route Starlette already
resolved into the request scope — which is both correct and *bounded by construction*.

Three more details worth noticing:

- **A dedicated `CollectorRegistry`**, not the default one, so the exposition contains only what
  this service declares. Process and platform collectors are reported more accurately by the node
  exporter and cAdvisor.
- **The scrape path is excluded from the metrics** — otherwise the middleware measures
  Prometheus measuring the application.
- **The `except` branch records a 500 before re-raising.** Without it, unhandled exceptions become
  500s for the client and vanish from the error rate — the metric would show a healthy service
  precisely when it is failing.
- **`LATENCY_BUCKETS` stops at 10 seconds**, on the stated grounds that anything past ten seconds
  is a timeout rather than a latency measurement.

### The gate

`scripts/validate-observability.sh` renders the charts and inspects the resulting Prometheus
configuration. The functions that matter for this module:

| Function | Refuses a pull request when |
|---|---|
| `check_prometheus_config` | The rendered config is not valid (`promtool check config`) |
| `check_required_jobs` | An expected job is missing from the rendered config |
| `check_traefik_uses_pod_discovery` | The Traefik job is changed to `role: endpoints` |
| `check_exporters_are_discoverable` | An exporter renders without the annotations the job needs |
| `check_resources_are_bounded` | A component renders without resource requests and limits |

`check_traefik_uses_pod_discovery` exists solely because that mistake is invisible at runtime.
This is the repository's pattern: **a defect that cannot be seen becomes a gate that cannot be
merged past.**

## 4. Architecture Explanation

[Observability Flow](../../architecture/observability-flow.md) is the diagram.

Prometheus syncs at wave `-15`, ahead of everything it observes, so a target appearing during a
rollout is collected from its first moment.

**What breaks elsewhere if this layer is wrong:**

| Mistake | Consequence |
|---|---|
| Wrong scrape port | No application metrics; dashboards render empty and look idle |
| `role: endpoints` for Traefik | No edge metrics; latency and error-rate alerts can never fire |
| Path as a label | Prometheus memory grows without bound; eventually OOM |
| Permanently-down target left in place | Operators stop reading the target list |

The second row is the serious one. Alerting sits directly on top of these series — an alert
that can never fire is indistinguishable from an alert that is not firing.

**A known duplication:** Traefik is scraped twice — once by this dedicated job and once by the
chart's `kubernetes-pods` job. That is why the edge alert rules pin `job="traefik"`. It is
recorded as accepted debt rather than quietly fixed, because the fix touches alert rules that
are currently correct.

## 5. Hands-on Lab

Local, no cluster.

### Part A — reproduce the defect in miniature

```sh
cd backend
docker build -t novashop-backend:lab .
docker run -d --name lab -p 8000:8000 novashop-backend:lab

curl -s localhost:8000/metrics | grep novashop_http_requests_total | head
```

Now generate traffic and watch the labels:

```sh
for i in 1 2 3; do curl -s localhost:8000/api/products/$i >/dev/null; done
curl -s localhost:8000/metrics | grep '^novashop_http_requests_total'
```

**Expect one series with `route="/api/products/{product_id}"`, not three.** If you see three, the
route template logic is broken — which is exactly the bug described in the docstring.

### Part B — see what the wrong port does

```sh
curl -s --max-time 2 localhost:80/metrics ; echo "exit=$?"
```

Connection refused. Now ask yourself the operator's question: **which dashboard would have shown
you this?** None. `up{job="kubernetes-pods"}` would have been 0, but only if you were looking at
the target list, which is the one page nobody opens when everything appears fine.

### Part C — render the real config

```sh
bash scripts/validate-observability.sh --gitops-dir ../NovaShop-GitOps
```

Then break the Traefik job and re-run:

```sh
sed -i 's/      - role: pod/      - role: endpoints/' \
  kubernetes/observability/prometheus/helm-values.yaml
bash scripts/validate-observability.sh --gitops-dir ../NovaShop-GitOps
git checkout kubernetes/observability/prometheus/helm-values.yaml
```

### Verification

```sh
bash scripts/validate-observability.sh --gitops-dir ../NovaShop-GitOps | tail -3
docker rm -f lab
```

The gate must pass. If it does not, you have not reverted something.

## 6. Exercises

**6.1** Change `prometheus.io/port` in `backend-service.yaml` from `targetPort` to `port` and
re-render the chart. Does any gate catch it? Write down what the answer implies about
where this class of bug has to be caught instead.

**6.2** Add a `user_agent` label to `REQUESTS`. Estimate the series count for 1,000 distinct
agents across 6 routes and 4 status codes. Then say why the repository labels `status` — which is
also user-influenced — and whether that is inconsistent.

**6.3** `argocd-dex-server` is dropped and pushgateway is disabled for the same reason. Find a
third target on this platform that could have been handled the same way and was not. *(Hint: read
the note about duplicate Traefik scraping.)*

**6.4** Write a PromQL query for the backend p95 latency per route, and one for the 5xx rate.
Check them against `docs/observability/`.

## 7. Challenge

`check_traefik_uses_pod_discovery` is a guardrail for one specific mistake in one specific job.
The general defect is broader: **any scrape job whose relabel rules match nothing produces an
empty target list and no error.**

Design a general gate. It must answer, from rendered configuration alone with no cluster access,
"would this job's relabel rules match at least one thing that exists?"

Then decide whether to build it. Consider: the render has no Endpoints objects; the platform has
six jobs; the specific check is nine lines and has never produced a false positive.

The repository's answer is the narrow check. **Argue whether that is engineering judgement or
lack of ambition** — and note that this is precisely the trade-off recorded in
[ADR 001](../../../adr/001-platform-guardrails.md): guardrails are added when a real defect
proves one is needed, not in anticipation.

## 8. Quiz

1. What address does `role: endpoints` dial?
2. Why must `prometheus.io/port` be the container port?
3. Why can the Traefik job not use `role: endpoints`?
4. Give two reasons the pushgateway job is disabled.
5. **True or false:** labelling by request path is fine as long as the API has few routes.
6. Why does the middleware skip the scrape path itself?
7. What did the earlier `route_template()` implementation get wrong, and what was the symptom?
8. Why a dedicated `CollectorRegistry` rather than the default?
9. Your dashboard shows zero requests. Name two causes with the same appearance.

<details>
<summary>Answers</summary>

1. The **pod IP**, with a port taken from the Endpoints object. The Service is where the target
   list comes from, not where the scrape goes.
2. Because the scrape goes to the pod. A Service port there is a port nothing listens on at that
   address — connection refused, on all six replicas, with nothing reporting unhealthy.
3. Traefik's Service exposes only `web` and `websecure`. There is no metrics port in its
   Endpoints, so an endpoints-based job matches nothing and silently collects zero series.
4. The Service does not exist, so the target is permanently down; and a target list that is
   always partly red trains operators to stop reading it.
5. **False.** Route count is irrelevant — the label comes from the *request path*, which is
   attacker-controlled. A crawler probing a few thousand URLs creates a few thousand series that
   persist for the full retention period.
6. Otherwise the application measures Prometheus measuring the application.
7. It iterated `app.routes` before routing. FastAPI wraps included routers, so those routes were
   never visible and **every** request was labelled `unmatched` — the metric existed, was scraped,
   and carried exactly one useless label value.
8. So the exposition contains only what this service declares. Process and platform collectors
   are reported more accurately by the node exporter and cAdvisor.
9. No traffic; or the scrape is failing and the series does not exist. Distinguish with
   `up{job=...}` and the target list — never with the dashboard.

</details>

## 9. Troubleshooting

### A metric exists in the code and returns no data

**Symptom.** `novashop_http_requests_total` returns nothing in Grafana. Pods `Running`, probes
passing, Service serving, Ingress working.

**Why it is misleading.** An empty query result and "no requests yet" are the same picture. The
health signals all describe the *application*, and the application is fine — the collector is
not reaching it.

**How it was found.** Reading `up{}` and the target list, not the dashboard: connection refused
at `podIP:80`. The Service was listening on 80; the pod never was.

**Fix.** `prometheus.io/port` set from `targetPort`. The comment in
[`backend-service.yaml`](../../../helm/novashop/templates/backend-service.yaml) is deliberately
longer than the code it explains.

### Every request labelled `unmatched`

**Symptom.** One series per method/status, `route="unmatched"` throughout. Per-route latency is
meaningless.

**Why it is misleading.** The metric is present, the scrape succeeds, the count is correct. Only
the *dimension* is broken — and a broken dimension is easy to read past.

**How it was found.** Route matching was re-implemented before routing; FastAPI's router wrapping
made included routes invisible. Fixed by reading the route Starlette had already resolved into
the request scope.

### A permanently red target

**Symptom.** `argocd-dex-server` down, always.

**Why it is misleading.** It is not a fault. Dex declares 5556/5557/5558 and listens on none of
them while no SSO connector is configured — `dex.config` in `argocd-cm` is empty. It was verified
on the cluster before being dropped.

**Why it matters enough to fix.** Not tidiness. A target list that is always partly red is a
target list nobody reads, and the target list is the only place the first defect in this section
was visible.

### The same component appears twice

Traefik is scraped by both the dedicated job and the chart's `kubernetes-pods` job. Alert rules
must pin `job="traefik"` or they double-count. Recorded as accepted debt in
[AUDIT.md](../../AUDIT.md) rather than fixed, because the fix touches rules that are currently
correct.

## 10. Best Practices

| Practice | Where |
|---|---|
| Comment the *reason*, at the site of a non-obvious value | `backend-service.yaml:13-17` |
| Bounded labels by construction, not by convention | `route_template()` |
| Record errors before re-raising | `metrics_middleware` `except` branch |
| Exclude the scrape path from the metrics | Same file |
| Dedicated registry, not the default | `REGISTRY = CollectorRegistry()` |
| Delete targets that are down by design | Dex drop rule, pushgateway disabled |
| Turn an invisible defect into a pre-merge gate | `check_traefik_uses_pod_discovery` |
| Verify an endpoint answers before adding a job | The comment above `extraScrapeConfigs` |

**Deliberately not done:** the Prometheus Operator's `ServiceMonitor` CRDs. Annotation-based
discovery is what the chart provides by default and what six jobs need. Adding CRDs would move
scrape configuration into a second mechanism for no capability this platform uses.

## 11. Interview Questions

- *How do you tell "not collected" from "healthy with nothing to report"?* → [S26](../../interview/questions.md)
- *Your monitoring says everything is healthy. Why might that be meaningless?* → [S1](../../interview/questions.md)
- *Why does Prometheus scrape Traefik with `role: pod`?* → [I12](../../interview/questions.md)
- *Why does the observability gate assert scrape jobs by name?* → [S13](../../interview/questions.md)
- *Why is Prometheus at sync wave -15?* → [S25](../../interview/questions.md)
- *How do you keep HTTP request metrics bounded?* — no counterpart in the interview set; the
  answer is section 3 of this module, and it is worth being able to give unprompted.

## 12. Further Reading

- [Prometheus — Kubernetes service discovery](https://prometheus.io/docs/prometheus/latest/configuration/configuration/#kubernetes_sd_config)
- [Prometheus — Naming and labels](https://prometheus.io/docs/practices/naming/)
- [ADR 009 — Observability stack](../../../adr/009-observability-stack.md)
- [Observability architecture](../../observability/) — target inventory and series counts

---

**Next:** Module 13 — Logs with Loki and Alloy *(specified, not yet written)*.
Back to the [curriculum](../README.md).
