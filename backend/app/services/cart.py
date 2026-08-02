"""The shopping cart, stored in Redis.

The strongest demonstration of Redis on this platform, because the cart is the
one thing here that is **not** derived from PostgreSQL. A cache can be dropped
and rebuilt; a cart cannot. Losing it is data loss, which is why `invalidate()`
in the cache layer deletes named keys and never issues FLUSHDB -- carts live in
the same index.

Prices are resolved from the database on every read rather than stored in the
cart. A cart that remembers the price it saw last week is a cart that charges
last week's price, and the reconciliation is worse than the inconvenience.
"""

from __future__ import annotations

import json
import logging

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core import cache
from app.core.datastores import datastores
from app.db.models import Inventory, Product
from app.observability.metrics import CART_ITEMS

logger = logging.getLogger("novashop.cart")

# Seven days. Long enough that a cart survives a weekend, short enough that
# abandoned carts do not accumulate on a node with one Redis and no eviction
# policy configured for this index.
TTL_SECONDS = 7 * 24 * 3600

MAX_LINES = 20
MAX_QUANTITY = 10


def _key(cart_id: str) -> str:
    return cache.key("cart", cart_id)


async def _read(cart_id: str) -> dict[str, int]:
    client = datastores.redis
    if client is None:
        return {}
    try:
        raw = await client.get(_key(cart_id))
    except Exception as error:  # noqa: BLE001
        logger.warning("cart read failed: %s", type(error).__name__)
        return {}
    if raw is None:
        return {}
    try:
        parsed = json.loads(raw)
    except ValueError:
        return {}
    return (
        {str(k): int(v) for k, v in parsed.items()} if isinstance(parsed, dict) else {}
    )


async def _write(cart_id: str, lines: dict[str, int]) -> None:
    client = datastores.redis
    if client is None:
        return
    try:
        if lines:
            # Every write refreshes the TTL. A cart someone is actively using
            # must not expire underneath them at exactly seven days from the
            # first item.
            await client.set(_key(cart_id), json.dumps(lines), ex=TTL_SECONDS)
        else:
            await client.delete(_key(cart_id))
    except Exception as error:  # noqa: BLE001
        logger.warning("cart write failed: %s", type(error).__name__)


async def get_cart(session: AsyncSession, cart_id: str) -> dict:
    """Return the cart, priced from the database at read time."""
    lines = await _read(cart_id)
    CART_ITEMS.set(sum(lines.values()))

    if not lines:
        return {"cart_id": cart_id, "items": [], "total_cents": 0, "item_count": 0}

    ids = [int(product_id) for product_id in lines]
    statement = (
        select(
            Product.id,
            Product.slug,
            Product.name,
            Product.price_cents,
            Product.image_path,
            Inventory.quantity,
        )
        .outerjoin(Inventory, Inventory.product_id == Product.id)
        .where(Product.id.in_(ids))
    )
    rows = (await session.execute(statement)).all()

    items = []
    total = 0
    for row in rows:
        quantity = lines[str(row.id)]
        available = row.quantity or 0
        subtotal = row.price_cents * quantity
        total += subtotal
        items.append(
            {
                "product_id": row.id,
                "slug": row.slug,
                "name": row.name,
                "image_path": row.image_path,
                "unit_price_cents": row.price_cents,
                "quantity": quantity,
                "subtotal_cents": subtotal,
                # Reported, not enforced here. Stock is checked again inside the
                # checkout transaction, because anything checked at read time
                # can change before the write.
                "in_stock": available >= quantity,
            }
        )

    items.sort(key=lambda item: item["name"])
    return {
        "cart_id": cart_id,
        "items": items,
        "total_cents": total,
        "item_count": sum(lines.values()),
    }


async def set_quantity(
    session: AsyncSession, cart_id: str, product_id: int, quantity: int
) -> dict:
    """Set one line to an absolute quantity. Zero removes it.

    Absolute rather than a delta, so a retried request is harmless. A `+1`
    endpoint that the browser retries adds two.
    """
    lines = await _read(cart_id)
    key = str(product_id)

    if quantity <= 0:
        lines.pop(key, None)
    else:
        if key not in lines and len(lines) >= MAX_LINES:
            raise ValueError(f"A cart holds at most {MAX_LINES} different products.")
        exists = await session.scalar(
            select(Product.id).where(Product.id == product_id)
        )
        if exists is None:
            raise LookupError("No such product.")
        lines[key] = min(quantity, MAX_QUANTITY)

    await _write(cart_id, lines)
    return await get_cart(session, cart_id)


async def clear(cart_id: str) -> None:
    await _write(cart_id, {})
