"""Cart, checkout, orders, admin statistics, and fault injection."""

from __future__ import annotations

import asyncio
import logging

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.core import cache
from app.core.config import settings
from app.db.session import get_session
from app.services import cart as cart_service
from app.services import orders as order_service

logger = logging.getLogger("novashop.shop")

router = APIRouter(tags=["shop"])

TTL_ADMIN = 60


class QuantityIn(BaseModel):
    product_id: int = Field(gt=0)
    # Absolute, never a delta. A retried "+1" adds two.
    quantity: int = Field(ge=0, le=cart_service.MAX_QUANTITY)


class CheckoutIn(BaseModel):
    cart_id: str = Field(min_length=8, max_length=64, pattern=r"^[A-Za-z0-9_-]+$")


def _validate_cart_id(cart_id: str) -> str:
    """The cart id comes from a cookie the browser controls.

    It is used to build a Redis key, so it is bounded and restricted to
    characters that cannot escape the namespace or bloat the keyspace.
    """
    if not 8 <= len(cart_id) <= 64 or not all(
        c.isalnum() or c in "-_" for c in cart_id
    ):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Malformed cart identifier.")
    return cart_id


@router.get("/cart/{cart_id}")
async def read_cart(cart_id: str, session: AsyncSession = Depends(get_session)) -> dict:
    return await cart_service.get_cart(session, _validate_cart_id(cart_id))


@router.put("/cart/{cart_id}/items")
async def set_cart_item(
    cart_id: str,
    payload: QuantityIn,
    session: AsyncSession = Depends(get_session),
) -> dict:
    try:
        return await cart_service.set_quantity(
            session, _validate_cart_id(cart_id), payload.product_id, payload.quantity
        )
    except LookupError:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "No such product.") from None
    except ValueError as error:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, str(error)) from None


@router.post("/orders", status_code=status.HTTP_201_CREATED)
async def checkout(
    payload: CheckoutIn, session: AsyncSession = Depends(get_session)
) -> dict:
    try:
        return await order_service.place_order(session, payload.cart_id)
    except order_service.CheckoutError as error:
        # 409, not 500. An empty cart or insufficient stock is a conflict with
        # the current state, not a fault -- and a 500 would page somebody.
        raise HTTPException(status.HTTP_409_CONFLICT, str(error)) from None


@router.get("/orders")
async def list_orders(
    session: AsyncSession = Depends(get_session),
    limit: int = Query(default=20, ge=1, le=100),
) -> list[dict]:
    return await order_service.list_orders(session, limit)


@router.get("/orders/{order_id}")
async def read_order(
    order_id: int, session: AsyncSession = Depends(get_session)
) -> dict:
    order = await order_service.get_order(session, order_id)
    if order is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "No such order.")
    return order


@router.get("/admin/stats")
async def admin_stats(session: AsyncSession = Depends(get_session)) -> dict:
    return await cache.cached(
        "admin_stats",
        cache.key("admin", "stats"),
        TTL_ADMIN,
        lambda: order_service.admin_stats(session),
    )


# ---------------------------------------------------------------------------
# Fault injection
# ---------------------------------------------------------------------------
#
# Registered only outside production. Not a feature flag that production
# evaluates to false -- the route does not exist there, so there is nothing to
# misconfigure and /demo/fault returns a genuine 404.
#
# It exists because there was previously no way to make an alert fire on demand,
# which meant the alerting pipeline could only be described, never shown.

if settings.environment != "production":

    class FaultIn(BaseModel):
        seconds: int = Field(default=30, ge=1, le=300)

    @router.post("/demo/fault", tags=["demo"])
    async def inject_fault(payload: FaultIn) -> dict:
        _fault.enable(payload.seconds)
        logger.warning(
            "fault injection enabled",
            extra={"seconds": payload.seconds, "environment": settings.environment},
        )
        return {"faulting": True, "seconds": payload.seconds}

    @router.delete("/demo/fault", tags=["demo"])
    async def clear_fault() -> dict:
        _fault.disable()
        return {"faulting": False}


class _FaultState:
    """Self-clearing, so a forgotten fault cannot outlive the demonstration.

    The deadline is compared against a monotonic clock rather than wall time:
    an NTP correction must not extend or cancel it.
    """

    def __init__(self) -> None:
        self._until: float = 0.0

    def enable(self, seconds: int) -> None:
        self._until = asyncio.get_running_loop().time() + seconds

    def disable(self) -> None:
        self._until = 0.0

    def active(self) -> bool:
        if self._until == 0.0:
            return False
        try:
            return asyncio.get_running_loop().time() < self._until
        except RuntimeError:
            return False


_fault = _FaultState()


def fault_is_active() -> bool:
    return settings.environment != "production" and _fault.active()
