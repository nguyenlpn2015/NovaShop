"""Catalogue behaviour that can be asserted without a database.

The queries themselves need PostgreSQL and are covered by the opt-in test in
test_db.py. What is checked here is the layer above: cache key construction,
request identity, and the response contracts -- all places where a mistake is
silent rather than loud.
"""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from app.api.middleware import _acceptable
from app.core import cache
from app.core.config import settings
from app.main import app
from app.schemas.catalogue import ProductPage, ProductSummary


def test_cache_keys_are_namespaced_by_environment() -> None:
    """Two environments must never collide on a key.

    They now use separate Redis database indices, so this is the second line of
    defence rather than the only one. An index is one character in a URL; if
    that character is ever wrong, the prefix turns a data-leak into a miss.
    """
    assert cache.key("products", "all").startswith(f"novashop:{settings.environment}:")


def test_cache_keys_separate_every_filter() -> None:
    """A key that omits a filter serves the wrong page under a plausible name.

    Harder to notice than a cache that never hits, because the response is
    well-formed and only the contents are wrong.
    """
    keys = {
        cache.key("products", category, int(in_stock), sort, page, size)
        for category in ("all", "apparel")
        for in_stock in (False, True)
        for sort in ("newest", "price_asc")
        for page in (1, 2)
        for size in (12, 24)
    }
    assert len(keys) == 2 * 2 * 2 * 2 * 2


@pytest.mark.parametrize(
    ("supplied", "acceptable"),
    [
        ("abc123", True),
        ("demo-trace-001", True),
        ("with_underscore", True),
        (None, False),
        ("", False),
        ("has space", False),
        ("has\nnewline", False),
        ("x" * 65, False),
    ],
)
def test_inbound_request_ids_are_validated(
    supplied: str | None, acceptable: bool
) -> None:
    """A caller-supplied header is untrusted input.

    A newline forges log entries; an unbounded string bloats every line emitted
    for that request.
    """
    assert _acceptable(supplied) is acceptable


def test_request_id_header_is_always_returned() -> None:
    with TestClient(app) as client:
        response = client.get("/live")
    assert response.headers.get("X-Request-ID")


def test_inbound_request_id_is_echoed() -> None:
    """So a trace survives the frontend's server-side fetch into the backend
    rather than becoming two unrelated ids."""
    with TestClient(app) as client:
        response = client.get("/live", headers={"X-Request-ID": "demo-trace-001"})
    assert response.headers["X-Request-ID"] == "demo-trace-001"


def test_rejected_request_id_is_replaced_not_passed_through() -> None:
    with TestClient(app) as client:
        response = client.get("/live", headers={"X-Request-ID": "bad id"})
    assert response.headers["X-Request-ID"] != "bad id"


def test_product_summary_exposes_money_as_integer_cents() -> None:
    """Not a float, and not a preformatted string.

    A float reintroduces the rounding error the integer column exists to avoid.
    A formatted string puts currency formatting in a service that cannot know
    the reader's locale.
    """
    assert ProductSummary.model_fields["price_cents"].annotation is int


def test_product_page_reports_enough_to_render_pagination() -> None:
    page = ProductPage.model_validate(
        {
            "items": [],
            "page": {"total": 128, "page": 2, "page_size": 12, "pages": 11},
        }
    )
    assert page.page.pages == 11


def test_catalogue_routes_are_registered() -> None:
    """A route that is written but never included answers 404 in production
    while every test of its handler passes.

    Asserted against the OpenAPI schema rather than `app.routes`. This version
    of FastAPI keeps an included router as a single `_IncludedRouter` entry
    instead of flattening its routes into `app.routes`, so walking that list
    finds only `/metrics` and the docs endpoints -- and a test written against
    it fails while the application is perfectly correct.
    """
    paths = set(app.openapi()["paths"])
    assert {"/products", "/products/{slug}", "/categories", "/search"} <= paths
