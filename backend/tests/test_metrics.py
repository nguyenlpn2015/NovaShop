"""Metric exposition and, above all, label cardinality.

The cardinality assertions matter more than the exposition ones. A route label
built from the raw request path is unbounded: a crawler probing a few thousand
URLs creates a few thousand permanent time series, inflating Prometheus memory
and every query that touches the metric. That failure is silent until the
instance is already degraded, so it is asserted here.
"""

from fastapi.testclient import TestClient

from app.core.config import settings
from app.main import app
from app.observability.metrics import UNMATCHED_ROUTE


def _series(body: str, name: str) -> list[str]:
    return [
        line
        for line in body.splitlines()
        if line.startswith(name) and not line.startswith("#")
    ]


def test_metrics_endpoint_exposes_prometheus_text() -> None:
    with TestClient(app) as client:
        client.get("/health")
        response = client.get(settings.metrics_path)

    assert response.status_code == 200
    assert "text/plain" in response.headers["content-type"]
    assert "novashop_http_requests_total" in response.text
    assert "novashop_build_info" in response.text


def test_known_route_is_labelled_with_its_template() -> None:
    with TestClient(app) as client:
        client.get("/health")
        body = client.get(settings.metrics_path).text

    recorded = _series(body, "novashop_http_requests_total")
    matching = [line for line in recorded if 'route="/health"' in line]
    assert matching, "the /health route should be recorded under its own template"


def test_unmatched_paths_collapse_to_one_series() -> None:
    """A crawler must not be able to create unbounded label values."""
    with TestClient(app) as client:
        for index in range(25):
            client.get(f"/definitely-not-a-route-{index}")
        body = client.get(settings.metrics_path).text

    routes = {
        line.split('route="', 1)[1].split('"', 1)[0]
        for line in _series(body, "novashop_http_requests_total")
    }

    assert UNMATCHED_ROUTE in routes
    invented = {
        route for route in routes if route.startswith("/definitely-not-a-route")
    }
    assert not invented, f"raw paths leaked into labels: {sorted(invented)}"


def test_scrape_endpoint_does_not_record_itself() -> None:
    """Otherwise every scrape inflates the request rate it is meant to report."""
    with TestClient(app) as client:
        client.get(settings.metrics_path)
        body = client.get(settings.metrics_path).text

    assert not [
        line
        for line in _series(body, "novashop_http_requests_total")
        if f'route="{settings.metrics_path}"' in line
    ]


def test_latency_histogram_is_recorded() -> None:
    with TestClient(app) as client:
        client.get("/health")
        body = client.get(settings.metrics_path).text

    assert _series(body, "novashop_http_request_duration_seconds_bucket")
