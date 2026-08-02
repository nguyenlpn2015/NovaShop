"""The async engine and session factory.

Separate from `app.core.datastores`, which owns the raw asyncpg pool used by the
readiness probe. Those two exist for different reasons and must not be merged:
the probe's pool is deliberately tiny and offline-tolerant, and giving readiness
a dependency on the ORM would mean an ORM misconfiguration reports itself as a
datastore outage.
"""

from __future__ import annotations

from collections.abc import AsyncIterator

from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from app.core.config import settings


def async_dsn(dsn: str) -> str:
    """Return the DSN with SQLAlchemy's asyncpg driver named explicitly.

    The Secret carries a plain `postgresql://` URL because that is what psql,
    pg_dump, and the exporter all expect. SQLAlchemy needs the driver in the
    scheme, and defaults to psycopg2 without it -- which is not installed, so
    the failure is an ImportError at first connection rather than anything that
    points at the URL.
    """
    for prefix in ("postgresql+asyncpg://", "postgres+asyncpg://"):
        if dsn.startswith(prefix):
            return dsn
    for prefix in ("postgresql://", "postgres://"):
        if dsn.startswith(prefix):
            return "postgresql+asyncpg://" + dsn[len(prefix) :]
    return dsn


_engine: AsyncEngine | None = None
_sessionmaker: async_sessionmaker[AsyncSession] | None = None


def engine() -> AsyncEngine:
    global _engine
    if _engine is None:
        _engine = create_async_engine(
            async_dsn(str(settings.database_url)),
            # Created without connecting, for the same reason the probe pool is:
            # an unreachable database must not stop the process from starting and
            # reporting why.
            pool_size=settings.database_pool_max_size,
            max_overflow=0,
            pool_pre_ping=True,
            echo=False,
        )
    return _engine


def sessionmaker() -> async_sessionmaker[AsyncSession]:
    global _sessionmaker
    if _sessionmaker is None:
        _sessionmaker = async_sessionmaker(
            engine(), expire_on_commit=False, class_=AsyncSession
        )
    return _sessionmaker


async def get_session() -> AsyncIterator[AsyncSession]:
    """FastAPI dependency. One session per request, rolled back on failure."""
    async with sessionmaker()() as session:
        try:
            yield session
        except Exception:
            await session.rollback()
            raise


async def dispose() -> None:
    global _engine, _sessionmaker
    if _engine is not None:
        await _engine.dispose()
    _engine = None
    _sessionmaker = None
