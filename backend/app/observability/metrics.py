"""Prometheus metrics for the HTTP surface.

Written directly against prometheus_client rather than pulled from an
instrumentation library, because the one decision that matters here is a
labelling decision and it should be visible in the repository.

Requests are labelled with the **matched route template**, never the raw path.
A label built from the request path is unbounded: every unique URL becomes a new
time series, and a crawler probing a few thousand paths permanently inflates
Prometheus memory and query cost. Requests that match no route collapse to a
single `unmatched` value for the same reason.
"""

from __future__ import annotations

import time
from collections.abc import Awaitable, Callable

from fastapi import Request, Response
from prometheus_client import (
    CONTENT_TYPE_LATEST,
    CollectorRegistry,
    Counter,
    Gauge,
    Histogram,
    generate_latest,
)

from app.core.config import settings

# A dedicated registry keeps the exposition to what this service declares.
# The default registry also carries process and platform collectors that the
# node exporter and cAdvisor already report more accurately.
REGISTRY = CollectorRegistry()

# Buckets are chosen for a web API: sub-millisecond resolution is noise, and
# anything past ten seconds is a timeout rather than a latency measurement.
LATENCY_BUCKETS = (0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0)

UNMATCHED_ROUTE = "unmatched"

REQUESTS = Counter(
    "novashop_http_requests_total",
    "HTTP requests handled, by route template and outcome.",
    labelnames=("method", "route", "status"),
    registry=REGISTRY,
)

LATENCY = Histogram(
    "novashop_http_request_duration_seconds",
    "HTTP request duration in seconds, by route template.",
    labelnames=("method", "route"),
    buckets=LATENCY_BUCKETS,
    registry=REGISTRY,
)

IN_FLIGHT = Gauge(
    "novashop_http_requests_in_flight",
    "HTTP requests currently being handled.",
    registry=REGISTRY,
)

BUILD_INFO = Gauge(
    "novashop_build_info",
    "Build metadata. Always 1; the information is in the labels.",
    labelnames=("version", "environment"),
    registry=REGISTRY,
)

# Cache effectiveness, by operation and outcome.
#
# `operation` is a name this code chooses -- never a cache key. Keys contain
# identifiers, and a label built from an identifier is unbounded: the same
# cardinality trap that route templates exist to avoid, arriving through a
# different door.
#
# `result` covers hit, miss, error, corrupt and unavailable rather than just the
# first two, because a cache that is failing and a cache that is missing look
# identical in a hit ratio computed from two counters.
CACHE_OPERATIONS = Counter(
    "novashop_cache_operations_total",
    "Cache reads and writes, by logical operation and outcome.",
    labelnames=("operation", "result"),
    registry=REGISTRY,
)

# Database timing, by a query name this code chooses.
#
# Not by SQL text: statements contain literals, and the label would be unbounded.
# Buckets run finer than the HTTP histogram because an indexed lookup answering
# in 40ms and one answering in 4ms are different situations, and the HTTP
# buckets cannot tell them apart.
# Orders, by outcome. A business metric rather than a technical one, and the
# only counter here an alert could reasonably be written against: a sustained
# run of out_of_stock or a total absence of "placed" both mean something.
ORDERS_CREATED = Counter(
    "novashop_orders_created_total",
    "Checkout attempts, by outcome.",
    labelnames=("result",),
    registry=REGISTRY,
)

# How much is sitting in carts right now. A gauge, not a counter: it goes down.
#
# Set from whichever replica last handled a cart read, so with several replicas
# it reports that replica's last observation rather than a cluster total. That
# is a real limitation and the reason it is not alerted on -- it is here to make
# Redis visibly load-bearing on a dashboard.
CART_ITEMS = Gauge(
    "novashop_cart_items",
    "Items in the most recently read cart.",
    registry=REGISTRY,
)

DB_QUERY_DURATION = Histogram(
    "novashop_db_query_duration_seconds",
    "Database query duration in seconds, by named query.",
    labelnames=("query",),
    buckets=(0.001, 0.0025, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5),
    registry=REGISTRY,
)


def route_template(request: Request) -> str:
    """Return the matched route template, or a single bucket when none matched.

    Starlette records the resolved route in the scope during routing, so this is
    only meaningful after the downstream application has run. Reading it there,
    rather than re-implementing route matching, is both correct and bounded by
    construction: a request that matches nothing leaves the key absent and
    collapses to one label value.

    Matching manually before routing is what an earlier revision did, and it was
    wrong. FastAPI wraps included routers, so iterating `app.routes` never sees
    the routes those routers declare and every request was labelled unmatched.
    """
    route = request.scope.get("route")
    path = getattr(route, "path", None)
    return path if isinstance(path, str) and path else UNMATCHED_ROUTE


async def metrics_middleware(
    request: Request,
    call_next: Callable[[Request], Awaitable[Response]],
) -> Response:
    """Record count and duration for every request except the scrape itself."""
    if request.url.path == settings.metrics_path:
        return await call_next(request)

    started = time.perf_counter()

    IN_FLIGHT.inc()
    try:
        response = await call_next(request)
    except Exception:
        # An unhandled exception still becomes a 500 for the client, so it must
        # appear in the error rate rather than vanish from the metric.
        elapsed = time.perf_counter() - started
        route = route_template(request)
        REQUESTS.labels(request.method, route, "500").inc()
        LATENCY.labels(request.method, route).observe(elapsed)
        raise
    finally:
        IN_FLIGHT.dec()

    elapsed = time.perf_counter() - started
    route = route_template(request)
    REQUESTS.labels(request.method, route, str(response.status_code)).inc()
    LATENCY.labels(request.method, route).observe(elapsed)
    return response


def render_metrics() -> Response:
    return Response(
        content=generate_latest(REGISTRY),
        media_type=CONTENT_TYPE_LATEST,
    )


def initialise() -> None:
    BUILD_INFO.labels(settings.app_version, settings.environment).set(1)
