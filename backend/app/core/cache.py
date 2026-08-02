"""Cache-aside over Redis, instrumented so the hit ratio is observable.

Two decisions worth stating.

**Every key is prefixed with the environment.** The three environments now use
separate Redis database indices, so a prefix is redundant for isolation. It is
kept as the second line of defence: an index is one character in a URL, and if
that character is ever wrong the failure degrades to a cache miss instead of one
environment serving another's data.

**A cache failure is never an application failure.** Redis being unreachable
must make the site slower, not broken. Every operation here swallows its errors,
records them as a `result="error"` observation, and returns as though the key
were absent -- the caller then reads from PostgreSQL and carries on.
"""

from __future__ import annotations

import json
import logging
from collections.abc import Awaitable, Callable
from typing import Any, TypeVar

from app.core.config import settings
from app.core.datastores import datastores
from app.observability.metrics import CACHE_OPERATIONS

logger = logging.getLogger("novashop.cache")

T = TypeVar("T")


def key(*parts: object) -> str:
    """Build a namespaced cache key."""
    return ":".join(["novashop", settings.environment, *(str(p) for p in parts)])


async def get_json(name: str, cache_key: str) -> Any | None:
    client = datastores.redis
    if client is None:
        CACHE_OPERATIONS.labels(name, "unavailable").inc()
        return None

    try:
        raw = await client.get(cache_key)
    except Exception as error:  # noqa: BLE001 - a cache fault must not fail a request
        CACHE_OPERATIONS.labels(name, "error").inc()
        logger.warning("cache read failed: %s", type(error).__name__)
        return None

    if raw is None:
        CACHE_OPERATIONS.labels(name, "miss").inc()
        return None

    try:
        value = json.loads(raw)
    except ValueError:
        # A key whose contents cannot be parsed is worse than no key: it would
        # fail on every read until it expired. Treated as a miss and overwritten.
        CACHE_OPERATIONS.labels(name, "corrupt").inc()
        return None

    CACHE_OPERATIONS.labels(name, "hit").inc()
    return value


async def set_json(name: str, cache_key: str, value: Any, ttl: int) -> None:
    client = datastores.redis
    if client is None:
        return
    try:
        await client.set(cache_key, json.dumps(value, default=str), ex=ttl)
    except Exception as error:  # noqa: BLE001
        CACHE_OPERATIONS.labels(name, "error").inc()
        logger.warning("cache write failed: %s", type(error).__name__)


async def cached[T](
    name: str,
    cache_key: str,
    ttl: int,
    produce: Callable[[], Awaitable[T]],
) -> T:
    """Return the cached value, or produce, store, and return it.

    Deliberately not a decorator. A decorator hides where the key comes from,
    and the key is the part that gets these wrong -- two endpoints sharing a key
    by accident is a bug that looks like stale data.
    """
    hit = await get_json(name, cache_key)
    if hit is not None:
        return hit  # type: ignore[return-value]

    value = await produce()
    await set_json(name, cache_key, value, ttl)
    return value


async def invalidate(*cache_keys: str) -> None:
    """Drop specific keys. Never a wildcard flush.

    `FLUSHDB` would also drop the carts, which live in the same index and are
    not derived from anything -- losing them is data loss, not a cache miss.
    """
    client = datastores.redis
    if client is None or not cache_keys:
        return
    try:
        await client.delete(*cache_keys)
    except Exception as error:  # noqa: BLE001
        CACHE_OPERATIONS.labels("invalidate", "error").inc()
        logger.warning("cache invalidation failed: %s", type(error).__name__)
