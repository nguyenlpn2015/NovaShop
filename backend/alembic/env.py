"""Alembic environment.

Runs against the same async engine the application uses, so a migration cannot
succeed here and fail there because of a driver difference.

The URL comes from DATABASE_URL, never from alembic.ini. The Secret is the only
place the credential lives, and a migration that reads its connection details
from a tracked file is a credential waiting to be committed.
"""

from __future__ import annotations

import asyncio
from logging.config import fileConfig

from sqlalchemy.ext.asyncio import create_async_engine

from alembic import context
from app.core.config import settings
from app.db.models import Base
from app.db.session import async_dsn

config = context.config

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata


def run_migrations_offline() -> None:
    context.configure(
        url=async_dsn(str(settings.database_url)),
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        compare_type=True,
    )
    with context.begin_transaction():
        context.run_migrations()


def _run(connection) -> None:  # noqa: ANN001 - Alembic supplies a sync-facade Connection
    context.configure(
        connection=connection,
        target_metadata=target_metadata,
        compare_type=True,
    )
    with context.begin_transaction():
        context.run_migrations()


async def run_migrations_online() -> None:
    # A dedicated engine rather than the application's: migrations run in a Job
    # with its own lifetime, and pool settings tuned for request handling are
    # the wrong ones for a single serial upgrade.
    engine = create_async_engine(
        async_dsn(str(settings.database_url)), pool_pre_ping=True
    )
    try:
        async with engine.connect() as connection:
            await connection.run_sync(_run)
    finally:
        await engine.dispose()


if context.is_offline_mode():
    run_migrations_offline()
else:
    asyncio.run(run_migrations_online())
