"""Checkout and order history.

Checkout is the only write path in the application, and the only place a
transaction matters: an order and its lines must both exist or neither must.

Payment is not simulated, delayed, or faked. The order is created with status
`placed` and nothing else happens. Adding a fake payment step would demonstrate
no platform capability and would make the demo dishonest about what it does.
"""

from __future__ import annotations

import logging

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core import cache
from app.db.models import Inventory, Order, OrderItem, Product, User
from app.observability.metrics import ORDERS_CREATED
from app.services import cart as cart_service
from app.services.catalogue import timed

logger = logging.getLogger("novashop.orders")


class CheckoutError(Exception):
    """Checkout could not complete. The message is safe to show a customer."""


async def place_order(session: AsyncSession, cart_id: str) -> dict:
    contents = await cart_service.get_cart(session, cart_id)
    if not contents["items"]:
        ORDERS_CREATED.labels("empty_cart").inc()
        raise CheckoutError("Your cart is empty.")

    product_ids = [item["product_id"] for item in contents["items"]]

    # The ambient transaction, not a new one. SQLAlchemy 2.0 begins implicitly
    # on first use, and get_cart above has already issued a SELECT -- so
    # `async with session.begin()` raised "A transaction is already begun on
    # this Session" and every checkout returned 500.
    #
    # Everything below runs inside that transaction and is committed at the end;
    # any exception leaves it uncommitted, and get_session rolls it back.
    try:
        # Re-read stock with FOR UPDATE. The quantities
        # reported when the cart was rendered are already stale by the time the
        # customer clicks; two concurrent checkouts for the last item must not
        # both succeed.
        stock_rows = (
            await session.execute(
                select(Inventory.product_id, Inventory.quantity)
                .where(Inventory.product_id.in_(product_ids))
                .with_for_update()
            )
        ).all()
        stock = {row.product_id: row.quantity for row in stock_rows}

        short = [
            item["name"]
            for item in contents["items"]
            if stock.get(item["product_id"], 0) < item["quantity"]
        ]
        if short:
            ORDERS_CREATED.labels("out_of_stock").inc()
            raise CheckoutError(f"Not enough stock for: {', '.join(sorted(short))}.")

        # There is no authentication, so orders are attributed to a seeded
        # customer. Inventing an anonymous user row per checkout would fill the
        # table with rows that mean nothing.
        user_id = await session.scalar(select(User.id).order_by(User.id).limit(1))
        if user_id is None:
            ORDERS_CREATED.labels("no_customer").inc()
            raise CheckoutError("The demo data is not seeded.")

        order = Order(
            user_id=user_id, status="placed", total_cents=contents["total_cents"]
        )
        session.add(order)
        await session.flush()

        for item in contents["items"]:
            session.add(
                OrderItem(
                    order_id=order.id,
                    product_id=item["product_id"],
                    quantity=item["quantity"],
                    unit_price_cents=item["unit_price_cents"],
                )
            )
            inventory = await session.get(Inventory, item["product_id"])
            if inventory is not None:
                inventory.quantity -= item["quantity"]

        order_id = order.id
        total = order.total_cents
        await session.commit()
    except CheckoutError:
        # A conflict, not a fault. Roll back so the session is usable, and let
        # the route turn it into a 409.
        await session.rollback()
        raise

    # Outside the transaction, and deliberately after the commit. Clearing the
    # cart before the commit would lose it if the commit failed.
    await cart_service.clear(cart_id)

    # Only the products whose stock changed. A blanket flush would drop every
    # cached page, including the carts sharing this Redis index.
    await cache.invalidate(
        *(cache.key("product", item["slug"]) for item in contents["items"])
    )

    ORDERS_CREATED.labels("placed").inc()
    logger.info(
        "order placed",
        extra={"order_id": order_id, "total_cents": total, "lines": len(product_ids)},
    )
    return {"order_id": order_id, "total_cents": total, "status": "placed"}


async def list_orders(session: AsyncSession, limit: int = 20) -> list[dict]:
    statement = (
        select(
            Order.id,
            Order.status,
            Order.total_cents,
            Order.created_at,
            User.full_name,
            func.count(OrderItem.id).label("line_count"),
        )
        .join(User, User.id == Order.user_id)
        .outerjoin(OrderItem, OrderItem.order_id == Order.id)
        .group_by(Order.id, User.full_name)
        .order_by(Order.created_at.desc())
        .limit(limit)
    )
    rows = await timed("orders.list", lambda: session.execute(statement))
    return [
        {
            "id": r.id,
            "status": r.status,
            "total_cents": r.total_cents,
            "created_at": r.created_at,
            "customer": r.full_name,
            "line_count": r.line_count,
        }
        for r in rows
    ]


async def get_order(session: AsyncSession, order_id: int) -> dict | None:
    header = (
        await timed(
            "order.detail",
            lambda: session.execute(
                select(
                    Order.id,
                    Order.status,
                    Order.total_cents,
                    Order.created_at,
                    User.full_name,
                )
                .join(User, User.id == Order.user_id)
                .where(Order.id == order_id)
            ),
        )
    ).first()
    if header is None:
        return None

    lines = await timed(
        "order.lines",
        lambda: session.execute(
            select(
                OrderItem.quantity,
                OrderItem.unit_price_cents,
                Product.name,
                Product.slug,
                Product.image_path,
            )
            .join(Product, Product.id == OrderItem.product_id)
            .where(OrderItem.order_id == order_id)
        ),
    )

    return {
        "id": header.id,
        "status": header.status,
        "total_cents": header.total_cents,
        "created_at": header.created_at,
        "customer": header.full_name,
        "items": [
            {
                "name": r.name,
                "slug": r.slug,
                "image_path": r.image_path,
                "quantity": r.quantity,
                "unit_price_cents": r.unit_price_cents,
                "subtotal_cents": r.quantity * r.unit_price_cents,
            }
            for r in lines
        ],
    }


async def admin_stats(session: AsyncSession) -> dict:
    """Four aggregates. The most expensive page in the application, on purpose.

    It exists to be slow enough that caching it is visibly worth doing, and to
    give `novashop_db_query_duration_seconds` a query worth looking at.
    """
    totals = (
        await timed(
            "admin.totals",
            lambda: session.execute(
                select(
                    func.count(Order.id),
                    func.coalesce(func.sum(Order.total_cents), 0),
                ).where(Order.status != "cancelled")
            ),
        )
    ).one()

    product_count = await timed(
        "admin.products",
        lambda: session.scalar(select(func.count()).select_from(Product)),
    )

    revenue_rows = await timed(
        "admin.revenue",
        lambda: session.execute(
            select(
                func.date_trunc("day", Order.created_at).label("day"),
                func.sum(Order.total_cents).label("revenue"),
            )
            .where(Order.status != "cancelled")
            .group_by("day")
            .order_by("day")
        ),
    )

    low_stock = await timed(
        "admin.low_stock",
        lambda: session.execute(
            select(Product.name, Product.slug, Inventory.quantity)
            .join(Inventory, Inventory.product_id == Product.id)
            .where(Inventory.quantity < 10)
            .order_by(Inventory.quantity)
            .limit(10)
        ),
    )

    return {
        "order_count": totals[0],
        "revenue_cents": int(totals[1]),
        "product_count": product_count or 0,
        "revenue_by_day": [
            {"day": r.day.date().isoformat(), "revenue_cents": int(r.revenue)}
            for r in revenue_rows
        ],
        "low_stock": [
            {"name": r.name, "slug": r.slug, "quantity": r.quantity} for r in low_stock
        ],
    }
