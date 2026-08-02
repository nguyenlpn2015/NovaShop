"""Cart, checkout, and fault-injection behaviour that needs no database."""

from __future__ import annotations

import importlib

import pytest
from fastapi import HTTPException

from app.api.routes.shop import _validate_cart_id
from app.main import app
from app.services import cart as cart_service


@pytest.mark.parametrize(
    "cart_id",
    ["abcdefgh", "demo-cart-0001", "a_b-c_d-1234", "x" * 64],
)
def test_valid_cart_ids_are_accepted(cart_id: str) -> None:
    assert _validate_cart_id(cart_id) == cart_id


@pytest.mark.parametrize(
    "cart_id",
    ["short", "x" * 65, "has space", "has/slash", "colon:injection", "novashop:*"],
)
def test_malformed_cart_ids_are_rejected(cart_id: str) -> None:
    """The cart id arrives in a cookie and becomes part of a Redis key.

    A colon would escape the key namespace and an asterisk would make a pattern.
    Both are rejected rather than escaped, because a bounded character set is
    easier to be sure of than an escaping routine.
    """
    with pytest.raises(HTTPException) as raised:
        _validate_cart_id(cart_id)
    assert raised.value.status_code == 400


def test_quantity_is_capped() -> None:
    """Bounded so one request cannot claim the entire stock of an item."""
    assert cart_service.MAX_QUANTITY <= 10
    assert cart_service.MAX_LINES <= 20


def test_cart_keys_are_namespaced() -> None:
    key = cart_service._key("demo-cart-0001")
    assert key.startswith("novashop:")
    assert key.endswith(":cart:demo-cart-0001")


def test_shop_routes_are_registered() -> None:
    paths = set(app.openapi()["paths"])
    assert {
        "/cart/{cart_id}",
        "/cart/{cart_id}/items",
        "/orders",
        "/orders/{order_id}",
        "/admin/stats",
    } <= paths


def test_fault_route_exists_outside_production() -> None:
    """The tests run with ENVIRONMENT unset, which defaults to development."""
    assert "/demo/fault" in set(app.openapi()["paths"])


def test_fault_route_does_not_exist_in_production(monkeypatch) -> None:  # noqa: ANN001
    """Not a flag production evaluates to false -- the route is never registered.

    A flag can be misconfigured; an unregistered route cannot. This asserts the
    absence rather than trusting the `if` in shop.py, because that `if` runs at
    import time and is exactly the kind of thing a refactor moves.
    """
    monkeypatch.setenv("ENVIRONMENT", "production")

    from app.core import config

    config.get_settings.cache_clear()
    monkeypatch.setattr(config, "settings", config.Settings())

    import app.api.routes.shop as shop_module

    reloaded = importlib.reload(shop_module)
    try:
        registered = {getattr(route, "path", None) for route in reloaded.router.routes}
        assert "/demo/fault" not in registered
        assert "/cart/{cart_id}" in registered
    finally:
        # Restore, or every test after this one sees a production application.
        monkeypatch.undo()
        config.get_settings.cache_clear()
        config.settings = config.Settings()
        importlib.reload(shop_module)


def test_fault_exempts_the_paths_that_must_keep_answering() -> None:
    """Liveness and metrics must survive an injected fault.

    A 503 on /live restarts the container, which ends the demonstration. A 503
    on /metrics replaces the signal the fault exists to move with an absence.
    """
    from app.api.middleware import FAULT_EXEMPT

    assert {"/live", "/metrics"} <= FAULT_EXEMPT
