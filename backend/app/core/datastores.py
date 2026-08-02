"""Connection handles for the datastores the service depends on.

Both handles are created without contacting the network. A datastore that is
unavailable at startup must not prevent the process from starting: the pod would
crash-loop and never serve the readiness endpoint that explains why. Instead the
process starts, reports itself live, and reports itself not ready until the
dependency answers.
"""

from __future__ import annotations

import asyncio
from dataclasses import dataclass

import asyncpg
import redis.asyncio as redis

from app.core.config import settings

# Probes run on a short period and declare a timeout of their own. Checks are
# bounded well inside it so a hung dependency surfaces as "not ready" rather than
# as a probe timeout, which is harder to read in an incident.
CHECK_TIMEOUT_SECONDS = 2.0


@dataclass(frozen=True)
class DependencyStatus:
    """Outcome of a single dependency check."""

    name: str
    healthy: bool
    detail: str | None = None


class Datastores:
    """Owns the PostgreSQL pool and Redis client for the process lifetime."""

    def __init__(self) -> None:
        self._pool: asyncpg.Pool | None = None
        self._redis: redis.Redis | None = None

    async def start(self) -> None:
        # min_size=0 keeps pool creation offline; connections are established on
        # first acquire, so startup never depends on PostgreSQL being reachable.
        self._pool = await asyncpg.create_pool(
            dsn=str(settings.database_url),
            min_size=0,
            max_size=settings.database_pool_max_size,
            timeout=CHECK_TIMEOUT_SECONDS,
            command_timeout=CHECK_TIMEOUT_SECONDS,
        )
        self._redis = redis.from_url(
            str(settings.redis_url),
            socket_connect_timeout=CHECK_TIMEOUT_SECONDS,
            socket_timeout=CHECK_TIMEOUT_SECONDS,
        )

    async def stop(self) -> None:
        if self._pool is not None:
            await self._pool.close()
            self._pool = None
        if self._redis is not None:
            await self._redis.aclose()
            self._redis = None

    async def check_postgres(self) -> DependencyStatus:
        if self._pool is None:
            return DependencyStatus("postgresql", False, "pool is not initialised")

        try:
            async with asyncio.timeout(CHECK_TIMEOUT_SECONDS):
                async with self._pool.acquire() as connection:
                    await connection.execute("SELECT 1")
        except Exception as error:  # noqa: BLE001 - reported, never raised to caller
            return DependencyStatus("postgresql", False, _describe(error))
        return DependencyStatus("postgresql", True)

    async def check_redis(self) -> DependencyStatus:
        if self._redis is None:
            return DependencyStatus("redis", False, "client is not initialised")

        try:
            async with asyncio.timeout(CHECK_TIMEOUT_SECONDS):
                await self._redis.ping()
        except Exception as error:  # noqa: BLE001 - reported, never raised to caller
            return DependencyStatus("redis", False, _describe(error))
        return DependencyStatus("redis", True)

    @property
    def redis(self) -> redis.Redis | None:
        """The Redis client, or None before start() / after stop().

        Exposed so the cache layer can use the one client this process owns
        rather than opening a second connection pool. Nullable on purpose: the
        caller must decide what to do without a cache, and for every caller here
        the answer is "read from PostgreSQL instead".
        """
        return self._redis

    async def check_all(self) -> list[DependencyStatus]:
        return list(await asyncio.gather(self.check_postgres(), self.check_redis()))


def _describe(error: BaseException) -> str:
    """Render an error without leaking the connection string or credentials."""

    if isinstance(error, TimeoutError):
        return f"timed out after {CHECK_TIMEOUT_SECONDS:g}s"
    return type(error).__name__


datastores = Datastores()
