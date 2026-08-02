"""Response shapes for the catalogue.

Prices are exposed as integer cents under a name that says so. Returning a
formatted string would put currency formatting in the backend, where it cannot
know the reader's locale; returning a float would reintroduce the rounding
problem the integer column exists to avoid.
"""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field


class CategorySummary(BaseModel):
    id: int
    slug: str
    name: str
    product_count: int


class ProductSummary(BaseModel):
    id: int
    slug: str
    name: str
    price_cents: int
    image_path: str
    category_slug: str
    category_name: str
    in_stock: bool
    rating: float | None = Field(
        default=None, description="Mean rating, or null when unreviewed."
    )
    review_count: int = 0


class ReviewOut(BaseModel):
    id: int
    rating: int
    body: str
    author: str
    created_at: datetime


class ProductDetail(ProductSummary):
    description: str
    stock_quantity: int
    created_at: datetime
    reviews: list[ReviewOut] = []


class Page(BaseModel):
    """Offset pagination.

    Offset rather than cursor because the catalogue is small, ordering is stable,
    and a page number is what the interface shows. Cursor pagination is the right
    answer at a scale this deliberately does not reach.
    """

    total: int
    page: int
    page_size: int
    pages: int


class ProductPage(BaseModel):
    items: list[ProductSummary]
    page: Page
