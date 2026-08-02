"""Move product image paths out of the route namespace.

Revision ID: 0002_image_paths
Revises: 0001_initial
Create Date: 2026-08-02

Seeded rows recorded `/products/<file>.webp`. The frontend serves the product
detail page at `/products/[slug]`, so a request for `/products/apparel-00.webp`
matched that route as a slug and returned the rendered HTML of a not-found page
instead of an image.

Nothing reported an error. Every card fell back to its gradient, every image
request returned HTTP 200, and the only visible symptom was that the site looked
slightly flatter than intended.

A data migration rather than a re-seed: seeding matches rows on their natural
key and inserts only what is absent, so it will not rewrite a column on a row
that already exists. That is the correct behaviour for a seed and the reason
this has to be a migration.
"""

from __future__ import annotations

from collections.abc import Sequence

from alembic import op

revision: str = "0002_image_paths"
down_revision: str | None = "0001_initial"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # Guarded by the LIKE so a re-run cannot produce /img/img/products/...
    # This runs on every sync as part of a PreSync hook; idempotence is not
    # optional.
    op.execute(
        """
        UPDATE products
        SET image_path = '/img' || image_path
        WHERE image_path LIKE '/products/%'
        """
    )


def downgrade() -> None:
    op.execute(
        """
        UPDATE products
        SET image_path = substring(image_path FROM 5)
        WHERE image_path LIKE '/img/products/%'
        """
    )
