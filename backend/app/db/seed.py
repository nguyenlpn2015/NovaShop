"""Deterministic demo data.

Two properties matter more than the content.

**Idempotent.** The Job that runs this is an Argo CD sync hook, so it runs on
every sync -- not once. Re-running must be a no-op, not a duplicate catalogue.
Each row is matched on its natural key and inserted only if absent.

**Deterministic.** Seeded from a fixed integer, so development, staging and
production hold identical data and a screenshot taken in one environment
describes the others. `random` is used for shaping the data, never for
identity.

Run with `python -m app.db.seed`.
"""

from __future__ import annotations

import asyncio
import logging
import random
import sys
from datetime import UTC, datetime, timedelta

from sqlalchemy import func, select

from app.db.models import (
    Category,
    Inventory,
    Order,
    OrderItem,
    Product,
    Review,
    User,
)
from app.db.session import dispose, sessionmaker

logger = logging.getLogger("novashop.seed")

SEED = 20260802

CATEGORIES: list[tuple[str, str]] = [
    ("apparel", "Apparel"),
    ("footwear", "Footwear"),
    ("accessories", "Accessories"),
    ("electronics", "Electronics"),
    ("home", "Home & Living"),
    ("outdoor", "Outdoor"),
    ("stationery", "Stationery"),
    ("wellness", "Wellness"),
]

ADJECTIVES = [
    "Aurora",
    "Basalt",
    "Cobalt",
    "Drift",
    "Ember",
    "Fathom",
    "Glacier",
    "Harbor",
    "Ionic",
    "Juniper",
    "Kelvin",
    "Lumen",
    "Meridian",
    "Nimbus",
    "Onyx",
    "Pallas",
    "Quartz",
    "Ridge",
    "Solstice",
    "Tundra",
    "Umber",
    "Verdant",
    "Wisp",
    "Xenon",
    "Yarrow",
    "Zephyr",
]

NOUNS: dict[str, list[str]] = {
    "apparel": ["Jacket", "Overshirt", "Knit", "Tee", "Hoodie", "Chore Coat"],
    "footwear": ["Runner", "Trainer", "Boot", "Loafer", "Sandal"],
    "accessories": ["Tote", "Wallet", "Cap", "Belt", "Scarf", "Backpack"],
    "electronics": ["Earbuds", "Lamp", "Keyboard", "Speaker", "Charger"],
    "home": ["Mug", "Throw", "Vase", "Cutting Board", "Carafe"],
    "outdoor": ["Flask", "Daypack", "Shell", "Lantern", "Mat"],
    "stationery": ["Notebook", "Pen", "Planner", "Folio", "Pencil Set"],
    "wellness": ["Diffuser", "Roller", "Balm", "Mat", "Bottle"],
}

FIRST_NAMES = [
    "An",
    "Bao",
    "Chi",
    "Dung",
    "Giang",
    "Ha",
    "Hieu",
    "Khanh",
    "Lan",
    "Minh",
    "Nam",
    "Ngoc",
    "Phuc",
    "Quan",
    "Thao",
    "Trang",
    "Tuan",
    "Vinh",
    "Yen",
    "Duy",
]
LAST_NAMES = ["Nguyen", "Tran", "Le", "Pham", "Hoang", "Vu", "Dang", "Bui"]

REVIEW_BODIES = [
    "Exactly as described. Shipping was quick.",
    "Good quality for the price. Would buy again.",
    "Works well, though the colour is slightly darker than the photo.",
    "Solid build. Has held up over a few months of daily use.",
    "Does the job. Nothing remarkable, nothing wrong.",
    "Better than expected. The finish is genuinely nice.",
    "Comfortable and light. Sizing runs a little small.",
    "Arrived well packaged. No complaints.",
]

PRODUCTS_PER_CATEGORY = 16
USER_COUNT = 40
ORDER_COUNT = 213


def _slugify(value: str) -> str:
    out: list[str] = []
    for char in value.lower():
        if char.isalnum():
            out.append(char)
        elif out and out[-1] != "-":
            out.append("-")
    return "".join(out).strip("-")


def product_identity(category_index: int, index: int) -> tuple[str, str]:
    """Return the (name, slug) for one seeded product.

    Pure and free of `hash()`. That is the point, and it is tested: Python
    randomises string hashing per process unless PYTHONHASHSEED is set, so an
    earlier version keyed the adjective on `hash(slug)` and produced different
    product names on every run. Nothing matched what was already stored, and a
    second seed doubled the catalogue from 128 rows to 256. It would also have
    given each environment a different catalogue, so a screenshot from staging
    would not have described production.
    """
    category_slug = CATEGORIES[category_index][0]
    nouns = NOUNS[category_slug]
    adjective = ADJECTIVES[(category_index * 5 + index * 7) % len(ADJECTIVES)]
    noun = nouns[index % len(nouns)]
    name = f"{adjective} {noun}"
    return name, f"{category_slug}-{_slugify(name)}-{index:02d}"


async def _seed_categories(session) -> dict[str, Category]:  # noqa: ANN001
    existing = {c.slug: c for c in (await session.scalars(select(Category))).all()}
    for order, (slug, name) in enumerate(CATEGORIES):
        if slug in existing:
            continue
        category = Category(slug=slug, name=name, sort_order=order)
        session.add(category)
        existing[slug] = category
    await session.flush()
    return existing


async def _seed_products(session, categories, rng) -> list[Product]:  # noqa: ANN001
    existing = {p.slug: p for p in (await session.scalars(select(Product))).all()}
    products: list[Product] = []

    for category_index, (slug, _) in enumerate(CATEGORIES):
        category = categories[slug]
        for index in range(PRODUCTS_PER_CATEGORY):
            name, product_slug = product_identity(category_index, index)

            if product_slug in existing:
                products.append(existing[product_slug])
                continue

            product = Product(
                category_id=category.id,
                slug=product_slug,
                name=name,
                description=(
                    f"{name} from the NovaShop {category.name.lower()} range. "
                    "Built for everyday use, and photographed honestly."
                ),
                price_cents=rng.randrange(15, 320) * 1000,
                image_path=f"/products/{slug}-{index % 8:02d}.webp",
                is_featured=1 if index < 1 else 0,
                created_at=datetime.now(UTC) - timedelta(days=rng.randrange(0, 240)),
            )
            session.add(product)
            products.append(product)

    await session.flush()
    return products


async def _seed_inventory(session, products, rng) -> None:  # noqa: ANN001
    have = set((await session.scalars(select(Inventory.product_id))).all())
    for product in products:
        if product.id in have:
            continue
        # Roughly one in twelve lands in single digits, so the admin dashboard's
        # low-stock panel has something real to show rather than an empty table.
        # Drawn explicitly rather than by sampling one list, because mixing four
        # low values into a range of 160 gives about two rows out of 128 -- which
        # renders as a panel that looks broken.
        if rng.random() < 0.08:
            quantity = rng.randrange(0, 10)
        else:
            quantity = rng.randrange(20, 180)
        session.add(Inventory(product_id=product.id, quantity=quantity, reserved=0))
    await session.flush()


async def _seed_users(session, rng) -> list[User]:  # noqa: ANN001
    existing = {u.email: u for u in (await session.scalars(select(User))).all()}
    users: list[User] = []
    for index in range(USER_COUNT):
        first = FIRST_NAMES[index % len(FIRST_NAMES)]
        last = LAST_NAMES[(index // len(FIRST_NAMES) + index) % len(LAST_NAMES)]
        email = f"{first.lower()}.{last.lower()}{index:02d}@example.com"
        if email in existing:
            users.append(existing[email])
            continue
        user = User(
            email=email,
            full_name=f"{first} {last}",
            created_at=datetime.now(UTC) - timedelta(days=rng.randrange(1, 400)),
        )
        session.add(user)
        users.append(user)
    await session.flush()
    return users


async def _seed_orders(session, users, products, rng) -> None:  # noqa: ANN001
    already = await session.scalar(select(func.count()).select_from(Order))
    if already:
        logger.info("orders present (%s); skipping order seed", already)
        return

    statuses = ["placed", "paid", "paid", "paid", "shipped", "shipped", "cancelled"]
    for _ in range(ORDER_COUNT):
        user = rng.choice(users)
        lines = rng.randrange(1, 5)
        chosen = rng.sample(products, lines)
        order = Order(
            user_id=user.id,
            status=rng.choice(statuses),
            total_cents=0,
            created_at=datetime.now(UTC) - timedelta(days=rng.randrange(0, 90)),
        )
        session.add(order)
        await session.flush()

        total = 0
        for product in chosen:
            quantity = rng.randrange(1, 4)
            total += product.price_cents * quantity
            session.add(
                OrderItem(
                    order_id=order.id,
                    product_id=product.id,
                    quantity=quantity,
                    unit_price_cents=product.price_cents,
                )
            )
        order.total_cents = total
    await session.flush()


async def _seed_reviews(session, users, products, rng) -> None:  # noqa: ANN001
    already = await session.scalar(select(func.count()).select_from(Review))
    if already:
        logger.info("reviews present (%s); skipping review seed", already)
        return

    for product in products:
        for _ in range(rng.randrange(0, 7)):
            session.add(
                Review(
                    product_id=product.id,
                    user_id=rng.choice(users).id,
                    rating=rng.choices([5, 4, 3, 2, 1], weights=[45, 30, 15, 7, 3])[0],
                    body=rng.choice(REVIEW_BODIES),
                    created_at=datetime.now(UTC)
                    - timedelta(days=rng.randrange(0, 180)),
                )
            )
    await session.flush()


async def seed() -> dict[str, int]:
    rng = random.Random(SEED)

    async with sessionmaker()() as session:
        async with session.begin():
            categories = await _seed_categories(session)
            products = await _seed_products(session, categories, rng)
            await _seed_inventory(session, products, rng)
            users = await _seed_users(session, rng)
            await _seed_orders(session, users, products, rng)
            await _seed_reviews(session, users, products, rng)

        counts = {
            "categories": await session.scalar(
                select(func.count()).select_from(Category)
            ),
            "products": await session.scalar(select(func.count()).select_from(Product)),
            "users": await session.scalar(select(func.count()).select_from(User)),
            "orders": await session.scalar(select(func.count()).select_from(Order)),
            "order_items": await session.scalar(
                select(func.count()).select_from(OrderItem)
            ),
            "reviews": await session.scalar(select(func.count()).select_from(Review)),
        }
    return counts


async def _main() -> int:
    logging.basicConfig(
        level=logging.INFO, format="%(levelname)s [%(name)s] %(message)s"
    )
    try:
        counts = await seed()
    finally:
        await dispose()
    logger.info("seed complete: %s", counts)
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(_main()))
