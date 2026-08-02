"""Catalogue queries.

Separated from the route handlers so the timing instrumentation wraps the query
rather than the HTTP layer -- `novashop_db_query_duration_seconds` should tell
you the database was slow, not that the request was.
"""

from __future__ import annotations

import time
from collections.abc import Awaitable, Callable
from typing import TypeVar

from sqlalchemy import Select, func, literal_column, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import Category, Inventory, Product, Review, User
from app.observability.metrics import DB_QUERY_DURATION

T = TypeVar("T")

MAX_PAGE_SIZE = 48
DEFAULT_PAGE_SIZE = 12


async def timed[T](name: str, run: Callable[[], Awaitable[T]]) -> T:
    """Record how long a named query took.

    The name is chosen here and is bounded by the code. Labelling by SQL text
    would be unbounded -- statements carry literals -- which is the same
    cardinality trap route templates exist to avoid.
    """
    started = time.perf_counter()
    try:
        return await run()
    finally:
        DB_QUERY_DURATION.labels(name).observe(time.perf_counter() - started)


def _summary_columns() -> Select:
    """Products with their category, stock flag and review aggregate.

    One statement with two outer joins rather than a query per product. The
    N+1 version is invisible at 12 rows a page and is the single most common way
    a catalogue page becomes slow in production.
    """
    review_stats = (
        select(
            Review.product_id.label("product_id"),
            func.avg(Review.rating).label("rating"),
            func.count(Review.id).label("review_count"),
        )
        .group_by(Review.product_id)
        .subquery()
    )

    return (
        select(
            Product.id,
            Product.slug,
            Product.name,
            Product.description,
            Product.price_cents,
            Product.image_path,
            Product.created_at,
            Category.slug.label("category_slug"),
            Category.name.label("category_name"),
            func.coalesce(Inventory.quantity, 0).label("stock_quantity"),
            review_stats.c.rating,
            func.coalesce(review_stats.c.review_count, 0).label("review_count"),
        )
        .join(Category, Category.id == Product.category_id)
        .outerjoin(Inventory, Inventory.product_id == Product.id)
        .outerjoin(review_stats, review_stats.c.product_id == Product.id)
    )


def _as_summary(row) -> dict:  # noqa: ANN001 - a SQLAlchemy Row
    return {
        "id": row.id,
        "slug": row.slug,
        "name": row.name,
        "price_cents": row.price_cents,
        "image_path": row.image_path,
        "category_slug": row.category_slug,
        "category_name": row.category_name,
        "in_stock": row.stock_quantity > 0,
        "rating": round(float(row.rating), 2) if row.rating is not None else None,
        "review_count": row.review_count,
    }


async def list_categories(session: AsyncSession) -> list[dict]:
    statement = (
        select(
            Category.id,
            Category.slug,
            Category.name,
            func.count(Product.id).label("product_count"),
        )
        .outerjoin(Product, Product.category_id == Category.id)
        .group_by(Category.id)
        .order_by(Category.sort_order)
    )
    rows = await timed("categories.list", lambda: session.execute(statement))
    return [
        {
            "id": r.id,
            "slug": r.slug,
            "name": r.name,
            "product_count": r.product_count,
        }
        for r in rows
    ]


async def list_products(
    session: AsyncSession,
    *,
    category: str | None = None,
    in_stock_only: bool = False,
    sort: str = "newest",
    page: int = 1,
    page_size: int = DEFAULT_PAGE_SIZE,
) -> dict:
    page = max(1, page)
    page_size = min(max(1, page_size), MAX_PAGE_SIZE)

    statement = _summary_columns()
    if category:
        statement = statement.where(Category.slug == category)
    if in_stock_only:
        statement = statement.where(func.coalesce(Inventory.quantity, 0) > 0)

    orderings = {
        "newest": Product.created_at.desc(),
        "price_asc": Product.price_cents.asc(),
        "price_desc": Product.price_cents.desc(),
        "name": Product.name.asc(),
    }
    # Unknown sort values fall back rather than erroring. A query string is user
    # input; a 500 on `?sort=banana` is a worse answer than the default order.
    statement = statement.order_by(orderings.get(sort, orderings["newest"]))

    count_statement = select(func.count()).select_from(
        statement.order_by(None).subquery()
    )
    total = await timed("products.count", lambda: session.scalar(count_statement))
    rows = await timed(
        "products.list",
        lambda: session.execute(
            statement.limit(page_size).offset((page - 1) * page_size)
        ),
    )

    total = int(total or 0)
    return {
        "items": [_as_summary(r) for r in rows],
        "page": {
            "total": total,
            "page": page,
            "page_size": page_size,
            "pages": max(1, -(-total // page_size)),
        },
    }


async def get_product(session: AsyncSession, slug: str) -> dict | None:
    statement = _summary_columns().where(Product.slug == slug)
    row = (await timed("product.detail", lambda: session.execute(statement))).first()
    if row is None:
        return None

    review_statement = (
        select(Review.id, Review.rating, Review.body, Review.created_at, User.full_name)
        .join(User, User.id == Review.user_id)
        .where(Review.product_id == row.id)
        .order_by(Review.created_at.desc())
        .limit(8)
    )
    reviews = await timed("product.reviews", lambda: session.execute(review_statement))

    detail = _as_summary(row)
    detail.update(
        {
            "description": row.description,
            "stock_quantity": row.stock_quantity,
            "created_at": row.created_at,
            "reviews": [
                {
                    "id": r.id,
                    "rating": r.rating,
                    "body": r.body,
                    "author": r.full_name,
                    "created_at": r.created_at,
                }
                for r in reviews
            ],
        }
    )
    return detail


async def search_products(
    session: AsyncSession, query: str, limit: int = 12
) -> list[dict]:
    """Full-text search against the generated tsvector column.

    `plainto_tsquery` rather than `to_tsquery`: the latter treats its input as
    query syntax, so a user typing an apostrophe or an ampersand gets a syntax
    error from PostgreSQL rather than a result set.
    """
    term = query.strip()
    if not term:
        return []

    statement = (
        _summary_columns()
        .where(
            # The stored generated column, not to_tsvector() computed here.
            # Computing it in the predicate produces the same rows and cannot use
            # ix_products_search, so the query silently becomes a sequential scan
            # -- indistinguishable from working, until the table is large enough
            # to matter. Referenced as a literal because the column is generated
            # and deliberately absent from the model: mapping it would invite an
            # INSERT that PostgreSQL rejects.
            literal_column("products.search_vector").op("@@")(
                func.plainto_tsquery("simple", term)
            )
        )
        .limit(min(limit, MAX_PAGE_SIZE))
    )
    rows = await timed("products.search", lambda: session.execute(statement))
    return [_as_summary(r) for r in rows]
