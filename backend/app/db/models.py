"""The NovaShop domain, as seven tables.

Deliberately small. The application exists to give the platform something real
to carry -- migrations to run, queries to measure, rows to back up and restore --
so the schema is sized to exercise those paths and no larger.

Two conventions worth stating because they are easy to get wrong and expensive
to change later:

**Money is integer cents.** Never a float. 0.1 + 0.2 is not 0.3 in binary
floating point, and a currency column that drifts by a cent per thousand orders
is a defect nobody notices until reconciliation.

**Timestamps are timezone-aware.** A naive timestamp is a timestamp whose
meaning depends on the server's locale, which is a property that changes when
the server does.
"""

from __future__ import annotations

from datetime import datetime

from sqlalchemy import (
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    func,
)
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship


class Base(DeclarativeBase):
    pass


def _created_at() -> Mapped[datetime]:
    return mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )


class Category(Base):
    __tablename__ = "categories"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    slug: Mapped[str] = mapped_column(String(64), nullable=False, unique=True)
    name: Mapped[str] = mapped_column(String(128), nullable=False)
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)

    products: Mapped[list[Product]] = relationship(back_populates="category")


class Product(Base):
    __tablename__ = "products"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    category_id: Mapped[int] = mapped_column(
        ForeignKey("categories.id", ondelete="RESTRICT"), nullable=False
    )
    slug: Mapped[str] = mapped_column(String(128), nullable=False, unique=True)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=False, default="")
    price_cents: Mapped[int] = mapped_column(Integer, nullable=False)
    # A path into the frontend's static assets, not a URL. The frontend owns how
    # it is served; the backend only records which image belongs to which row.
    image_path: Mapped[str] = mapped_column(String(200), nullable=False, default="")
    is_featured: Mapped[bool] = mapped_column(
        Integer, nullable=False, default=0, server_default="0"
    )
    created_at: Mapped[datetime] = _created_at()

    category: Mapped[Category] = relationship(back_populates="products")
    inventory: Mapped[Inventory | None] = relationship(
        back_populates="product", uselist=False
    )
    reviews: Mapped[list[Review]] = relationship(back_populates="product")

    __table_args__ = (
        CheckConstraint("price_cents >= 0", name="ck_products_price_non_negative"),
        # Listing is filtered by category and ordered by recency more than
        # anything else, so the composite index matches the query rather than
        # the column list.
        Index("ix_products_category_created", "category_id", "created_at"),
        Index("ix_products_featured", "is_featured"),
    )


class Inventory(Base):
    """Stock, split from products because it changes on a different cadence.

    A product row is written once and read constantly. Stock is written on every
    order. Keeping them in one table means every stock decrement invalidates the
    cached product row.
    """

    __tablename__ = "inventory"

    product_id: Mapped[int] = mapped_column(
        ForeignKey("products.id", ondelete="CASCADE"), primary_key=True
    )
    quantity: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    reserved: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )

    product: Mapped[Product] = relationship(back_populates="inventory")

    __table_args__ = (
        CheckConstraint("quantity >= 0", name="ck_inventory_quantity_non_negative"),
        CheckConstraint("reserved >= 0", name="ck_inventory_reserved_non_negative"),
    )


class User(Base):
    """A customer record. There is no authentication anywhere in this project.

    Users exist so that orders and reviews have somewhere to point and so the
    seeded data looks like a system that has been used. Adding login would be
    business functionality that demonstrates no platform capability.
    """

    __tablename__ = "users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    email: Mapped[str] = mapped_column(String(255), nullable=False, unique=True)
    full_name: Mapped[str] = mapped_column(String(128), nullable=False)
    created_at: Mapped[datetime] = _created_at()


class Order(Base):
    __tablename__ = "orders"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="RESTRICT"), nullable=False
    )
    status: Mapped[str] = mapped_column(String(32), nullable=False, default="placed")
    total_cents: Mapped[int] = mapped_column(Integer, nullable=False)
    created_at: Mapped[datetime] = _created_at()

    items: Mapped[list[OrderItem]] = relationship(
        back_populates="order", cascade="all, delete-orphan"
    )
    user: Mapped[User] = relationship()

    __table_args__ = (
        CheckConstraint(
            "status IN ('placed', 'paid', 'shipped', 'cancelled')",
            name="ck_orders_status",
        ),
        Index("ix_orders_created", "created_at"),
    )


class OrderItem(Base):
    """A line on an order.

    unit_price_cents is copied from the product at the time of the order rather
    than joined at read time. A price change must not rewrite history: an order
    placed last week was placed at last week's price.
    """

    __tablename__ = "order_items"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    order_id: Mapped[int] = mapped_column(
        ForeignKey("orders.id", ondelete="CASCADE"), nullable=False
    )
    product_id: Mapped[int] = mapped_column(
        ForeignKey("products.id", ondelete="RESTRICT"), nullable=False
    )
    quantity: Mapped[int] = mapped_column(Integer, nullable=False)
    unit_price_cents: Mapped[int] = mapped_column(Integer, nullable=False)

    order: Mapped[Order] = relationship(back_populates="items")
    product: Mapped[Product] = relationship()

    __table_args__ = (
        CheckConstraint("quantity > 0", name="ck_order_items_quantity_positive"),
        Index("ix_order_items_order", "order_id"),
    )


class Review(Base):
    __tablename__ = "reviews"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    product_id: Mapped[int] = mapped_column(
        ForeignKey("products.id", ondelete="CASCADE"), nullable=False
    )
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    rating: Mapped[int] = mapped_column(Integer, nullable=False)
    body: Mapped[str] = mapped_column(Text, nullable=False, default="")
    created_at: Mapped[datetime] = _created_at()

    product: Mapped[Product] = relationship(back_populates="reviews")
    user: Mapped[User] = relationship()

    __table_args__ = (
        CheckConstraint("rating BETWEEN 1 AND 5", name="ck_reviews_rating_range"),
        Index("ix_reviews_product", "product_id"),
    )
