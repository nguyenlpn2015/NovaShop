# ADR 007: Traefik as the ingress controller

## Status

Accepted

## Date

2026-08-01

## Context

One node, four public hostnames arriving on one address, and TLS that has to be
introduced in phases because of a Let's Encrypt rate limit.

k3s ships Traefik enabled by default, as chart 40.1.3+up40.1.0. So the real decision is
not "which ingress controller" from a blank slate — it is whether to keep what is already
running and working, or disable it and install something else.

The requirement that mattered most: the edge must serve plain HTTP before any certificate
exists. HTTP-01 validation needs Let's Encrypt to reach `/.well-known/acme-challenge/` on
port 80 on this node, so an ingress that cannot usefully serve without TLS makes the first
certificate impossible to obtain.

## Decision

Keep the bundled Traefik. Do not disable it, do not install a second controller.

Route by `Host` header, with the `websecure` entrypoint named explicitly on production
Ingress objects. Let cert-manager supply certificates as Kubernetes Secrets rather than
using Traefik's own ACME support.

Scrape Traefik's metrics on **pod port 9100** with `role: pod`.

## Alternatives Considered

**ingress-nginx.** The most widely deployed, and the one most interviewers know. Rejected
because replacing a working bundled component costs a `--disable=traefik` flag on the k3s
server, a k3s restart, and a permanent divergence from the distribution's defaults — in
exchange for capabilities this platform does not use. On a single node with 8GB, "already
running and working" is worth more than familiarity.

**Traefik's built-in ACME (`certificatesResolvers`).** Genuinely fewer components: Traefik
would obtain its own certificates and no cert-manager would be needed. Rejected because
Traefik stores ACME state in a file on the pod's filesystem, and on `local-path` storage
that file is node-local. Recovery would have to restore a Traefik-internal file format,
whereas cert-manager keeps certificates in Kubernetes Secrets — which back up, restore,
and inspect like anything else. Given that [recovery](../docs/architecture/recovery-flow.md)
must restore certificate material *before* reconciliation to avoid spending the rate-limit
budget, having that material be an ordinary Secret is what makes the ordering practical.

**Gateway API with a compatible implementation.** The direction the ecosystem is moving,
and a defensible choice. Rejected as premature here: it would mean either running Traefik
in Gateway API mode or adding an implementation, for routing needs that four `Host` rules
satisfy completely. Worth revisiting, and on the [roadmap](../docs/ROADMAP.md) as a
consideration rather than a commitment.

**Envoy or Contour.** More capable at traffic management — retries, outlier detection,
traffic splitting. Rejected because none of that is exercised: there is no canary
deployment, no service mesh, and no multi-version routing in this platform. Capability
that is not used is surface area to secure and explain.

**HAProxy Ingress.** Comparable to ingress-nginx and rejected for the same reason.

## Consequences

**Easier.** Zero installation cost, and the edge is serving before any of the platform's
own components exist — which is what makes the `http` phase possible and therefore what
makes the first certificate obtainable. Host-based routing keeps all four names on one
address and one port.

**Harder, and accepted.**

*Traefik's version is k3s's to choose.* Upgrading independently means taking over its Helm
release, which is a divergence from the distribution. Currently image 3.7.4.

*Metrics are on the pod only.* The Traefik Service exposes `web` and `websecure` and
nothing else. An endpoints-based scrape job would render, schema-validate, deploy, and
collect zero series — indistinguishable from an edge with no traffic. This is why
Prometheus uses `role: pod` and why `validate-observability.sh` asserts that it still
does. It is the single most instructive line in the scrape configuration.

*Traefik is currently scraped twice.* The dedicated `traefik` job plus the chart's default
annotation-based `kubernetes-pods` job, because the Traefik pod carries its own
`prometheus.io` annotations. Seven duplicate series. Ratios are unaffected, but the edge
alerts pin `job="traefik"` rather than relying on that. Removing the duplicate requires
overriding a chart default scrape job and is on the roadmap.

*The entrypoint must be named explicitly.* Leaving
`traefik.ingress.kubernetes.io/router.entrypoints` off can bind a router to `web` only,
serving plain HTTP with nothing reporting an error.

*Traefik watches its dynamic configuration with inotify.* When the node exhausted
`fs.inotify.max_user_instances`, Traefik logged `failed to create fsnotify watcher: too
many open files` and kept running with stale configuration. A workload that cannot create
a watcher does not fail — it silently stops noticing changes. Hence
`scripts/linux/configure-node-limits.sh`.

## Validation

```sh
kubectl -n kube-system get deploy traefik
kubectl get ingress -A
curl -sI https://novashop.smartdev.vn
curl -s http://10.42.x.x:9100/metrics | head    # pod, not Service
```

```promql
sum by (service, code) (rate(traefik_service_requests_total{job="traefik"}[10m]))
```

`scripts/validate-observability.sh` includes an explicit check that Traefik is discovered
by pod and not by endpoints.
