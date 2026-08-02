"""Schema and seeding tests that need no database.

CI runs without PostgreSQL, so these assert the properties that can be checked
from the model metadata and from pure functions. The properties that genuinely
need a server -- that the migration applies, and that seeding twice changes
nothing -- are asserted by test_migration_is_idempotent below, which skips
unless NOVASHOP_TEST_DATABASE_URL is set.
"""

from __future__ import annotations

import os

import pytest

from app.db.models import Base
from app.db.seed import CATEGORIES, NOUNS, SEED, _slugify, product_identity
from app.db.session import async_dsn

EXPECTED_TABLES = {
    "categories",
    "products",
    "inventory",
    "users",
    "orders",
    "order_items",
    "reviews",
}


def test_schema_has_exactly_the_expected_tables() -> None:
    assert set(Base.metadata.tables) == EXPECTED_TABLES


def test_money_columns_are_integers() -> None:
    """Currency must never be floating point.

    0.1 + 0.2 is not 0.3 in binary floating point. A price column that drifts by
    a cent per thousand orders is a defect nobody notices until reconciliation,
    so this is asserted rather than left to review.
    """
    money = [
        ("products", "price_cents"),
        ("orders", "total_cents"),
        ("order_items", "unit_price_cents"),
    ]
    for table, column in money:
        kind = Base.metadata.tables[table].columns[column].type
        assert kind.python_type is int, f"{table}.{column} is {kind}"


def test_timestamps_are_timezone_aware() -> None:
    for table in Base.metadata.tables.values():
        for column in table.columns:
            if column.name.endswith("_at"):
                assert getattr(column.type, "timezone", False), (
                    f"{table.name}.{column.name} is naive"
                )


@pytest.mark.parametrize(
    ("supplied", "expected"),
    [
        ("postgresql://u:p@h:5432/d", "postgresql+asyncpg://u:p@h:5432/d"),
        ("postgres://u:p@h:5432/d", "postgresql+asyncpg://u:p@h:5432/d"),
        ("postgresql+asyncpg://u:p@h:5432/d", "postgresql+asyncpg://u:p@h:5432/d"),
    ],
)
def test_async_dsn_names_the_driver(supplied: str, expected: str) -> None:
    """The Secret carries a plain postgresql:// URL, which SQLAlchemy reads as
    psycopg2. That driver is not installed, so without this conversion the
    failure is an ImportError at first query rather than anything that points at
    the URL."""
    assert async_dsn(supplied) == expected


def test_every_category_has_product_nouns() -> None:
    """A category with no nouns would silently seed zero products for it."""
    for slug, _ in CATEGORIES:
        assert NOUNS.get(slug), f"category {slug} has no nouns"


def test_product_identity_survives_a_different_hash_seed() -> None:
    """Product names must be identical across processes.

    They were not. An earlier version keyed the adjective on `hash(slug)`, and
    Python randomises string hashing per process unless PYTHONHASHSEED is set.
    Every seed run produced different slugs, nothing matched what was already
    stored, and a second run doubled the catalogue from 128 rows to 256. It
    would also have given each environment a different catalogue, so a
    screenshot from staging would not have described production.

    Asserted by generating the names in two subprocesses with deliberately
    different hash seeds, rather than by grepping the source for `hash(` --
    which the comment explaining this bug would itself have tripped.
    """
    import subprocess
    import sys

    program = (
        "from app.db.seed import product_identity;"
        "print([product_identity(c, i) for c in range(3) for i in range(4)])"
    )

    def generate(hash_seed: str) -> str:
        return subprocess.run(
            [sys.executable, "-c", program],
            capture_output=True,
            text=True,
            check=True,
            env={**os.environ, "PYTHONHASHSEED": hash_seed},
        ).stdout

    assert generate("0") == generate("12345")


def test_product_identity_is_unique_within_a_category() -> None:
    slugs = [product_identity(0, index)[1] for index in range(16)]
    assert len(set(slugs)) == len(slugs)


def test_seed_constant_is_fixed() -> None:
    assert isinstance(SEED, int)


def test_slugify_produces_url_safe_values() -> None:
    assert _slugify("Aurora Jacket") == "aurora-jacket"
    assert _slugify("  Home & Living ") == "home-living"
    assert _slugify("A -- B") == "a-b"


@pytest.mark.skipif(
    not os.environ.get("NOVASHOP_TEST_DATABASE_URL"),
    reason="needs a disposable PostgreSQL; set NOVASHOP_TEST_DATABASE_URL to run",
)
def test_migration_is_idempotent() -> None:
    """Seeding twice must leave the row counts unchanged.

    Opt-in because CI has no database. Run locally against a throwaway server:

        docker run -d --name pg -p 55432:5432 \\
          -e POSTGRES_PASSWORD=test -e POSTGRES_USER=novashop \\
          -e POSTGRES_DB=novashop_test postgres:14-alpine

        export NOVASHOP_TEST_DATABASE_URL=\\
          postgresql://novashop:test@127.0.0.1:55432/novashop_test
        pytest tests/test_db.py -k idempotent
    """
    import asyncio

    from alembic.config import Config

    from alembic import command
    from app.core.config import settings
    from app.db import session as session_module
    from app.db.seed import seed

    # settings is built once at import, and `from app.core.config import settings`
    # binds the object -- so setting DATABASE_URL in the environment here is too
    # late and too indirect. Mutating the attribute is what actually redirects
    # both the application engine and alembic/env.py, which read the same object.
    original = settings.database_url
    settings.database_url = os.environ["NOVASHOP_TEST_DATABASE_URL"]

    config = Config("alembic.ini")
    command.upgrade(config, "head")

    async def run() -> tuple[dict[str, int], dict[str, int]]:
        try:
            first = await seed()
            second = await seed()
        finally:
            await session_module.dispose()
        return first, second

    try:
        first, second = asyncio.run(run())
    finally:
        settings.database_url = original

    assert first == second, f"seed is not idempotent: {first} then {second}"
    assert first["products"] > 0
