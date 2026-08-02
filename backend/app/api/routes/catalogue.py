"""Catalogue endpoints: categories, products, product detail, search.

Every handler is cache-aside with an explicit key and TTL. The TTLs differ by
how often the underlying data changes and by how bad staleness is: a category
list changes when someone deploys, a product detail changes when stock moves.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core import cache
from app.db.session import get_session
from app.schemas.catalogue import (
    CategorySummary,
    ProductDetail,
    ProductPage,
    ProductSummary,
)
from app.services import catalogue

router = APIRouter(tags=["catalogue"])

TTL_CATEGORIES = 600
TTL_PRODUCTS = 120
TTL_PRODUCT = 300
TTL_SEARCH = 60


@router.get("/categories", response_model=list[CategorySummary])
async def get_categories(
    session: AsyncSession = Depends(get_session),
) -> list[dict]:
    return await cache.cached(
        "categories",
        cache.key("categories"),
        TTL_CATEGORIES,
        lambda: catalogue.list_categories(session),
    )


@router.get("/products", response_model=ProductPage)
async def get_products(
    session: AsyncSession = Depends(get_session),
    category: str | None = Query(default=None, max_length=64),
    in_stock: bool = Query(default=False),
    sort: str = Query(default="newest"),
    page: int = Query(default=1, ge=1, le=1000),
    page_size: int = Query(default=catalogue.DEFAULT_PAGE_SIZE, ge=1, le=48),
) -> dict:
    # Every filter that changes the result must appear in the key. A key that
    # omits one serves the wrong page under a name that looks right, which is
    # far harder to spot than a cache that never hits.
    cache_key = cache.key(
        "products", category or "all", int(in_stock), sort, page, page_size
    )
    return await cache.cached(
        "products",
        cache_key,
        TTL_PRODUCTS,
        lambda: catalogue.list_products(
            session,
            category=category,
            in_stock_only=in_stock,
            sort=sort,
            page=page,
            page_size=page_size,
        ),
    )


@router.get("/products/{slug}", response_model=ProductDetail)
async def get_product(
    slug: str,
    session: AsyncSession = Depends(get_session),
) -> dict:
    product = await cache.cached(
        "product",
        cache.key("product", slug),
        TTL_PRODUCT,
        lambda: catalogue.get_product(session, slug),
    )
    if product is None:
        # Not cached. Caching absence would mean a product created after the
        # first 404 stays invisible for the whole TTL, and the miss costs one
        # indexed lookup.
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Product not found"
        )
    return product


@router.get("/search", response_model=list[ProductSummary])
async def search(
    q: str = Query(min_length=1, max_length=100),
    session: AsyncSession = Depends(get_session),
) -> list[dict]:
    # Normalised into the key so "Jacket", "jacket" and " jacket " share one
    # entry. Without it the cache is trivially defeated by capitalisation.
    normalised = " ".join(q.lower().split())
    return await cache.cached(
        "search",
        cache.key("search", normalised),
        TTL_SEARCH,
        lambda: catalogue.search_products(session, normalised),
    )
