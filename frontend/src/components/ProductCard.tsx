import Link from "next/link";

import type { ProductSummary } from "@/lib/api";
import { formatPrice, productTint } from "@/lib/format";

export function RatingStars({
  rating,
  count,
}: {
  rating: number | null;
  count: number;
}) {
  if (rating === null) {
    return <span className="text-xs text-content-faint">No reviews yet</span>;
  }

  const rounded = Math.round(rating);
  return (
    <span className="flex items-center gap-1.5 text-xs text-content-muted">
      <span aria-hidden className="tracking-wide text-caution">
        {"★".repeat(rounded)}
        <span className="text-content-faint/60">{"★".repeat(5 - rounded)}</span>
      </span>
      <span className="sr-only">{rating} out of 5</span>
      <span className="tabular-nums">
        {rating.toFixed(1)} ({count})
      </span>
    </span>
  );
}

export function StockBadge({ inStock }: { inStock: boolean }) {
  return (
    <span
      className={`inline-flex items-center gap-1.5 text-xs font-medium ${
        inStock ? "text-positive" : "text-content-faint"
      }`}
    >
      <span
        aria-hidden
        className={`h-1.5 w-1.5 rounded-full ${
          inStock ? "bg-positive" : "bg-content-faint"
        }`}
      />
      {inStock ? "In stock" : "Out of stock"}
    </span>
  );
}

export function ProductCard({ product }: { product: ProductSummary }) {
  return (
    // One anchor for the whole card, and nothing interactive inside it. A
    // second link nested here would be invalid HTML and would make the card
    // ambiguous to a keyboard: two tab stops, one visual target.
    <Link
      href={`/products/${product.slug}`}
      className="card-interactive group flex animate-fade-up flex-col overflow-hidden"
    >
      <div
        className="relative aspect-square overflow-hidden bg-surface-sunken"
        style={{ backgroundImage: productTint(product.slug, product.category_slug) }}
      >
        {/* Square, not 4:3. Product photography is square almost everywhere,
            and a grid of squares reads as a catalogue rather than as a blog. */}
        {/* The artwork is transparent, so this wash is visible through it rather
            than hidden behind it -- which is also what makes one file suit both
            themes. A slow or missing file degrades to the tinted tile instead of
            a broken icon.
            Plain <img> rather than next/image: optimisation writes to
            .next/cache, and the container has a read-only root filesystem.
            It stays first in this subtree -- a test asserts the card's first
            image is the product, which is what caught /products/ vs /img/. */}
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          src={product.image_path}
          alt=""
          loading="lazy"
          decoding="async"
          className={`h-full w-full object-cover transition duration-700
                     group-hover:scale-[1.07] ${
                       product.in_stock ? "" : "opacity-60 saturate-50"
                     }`}
        />

        {!product.in_stock && (
          <span
            className="absolute left-3 top-3 rounded-full bg-surface/90 px-2.5 py-1
                       text-[10px] font-semibold uppercase tracking-wide
                       text-content-muted backdrop-blur"
          >
            Sold out
          </span>
        )}
        {product.rating !== null && product.rating >= 4.5 && product.in_stock && (
          <span
            className="absolute left-3 top-3 rounded-full bg-positive px-2.5 py-1
                       text-[10px] font-semibold uppercase tracking-wide text-white"
          >
            Highly rated
          </span>
        )}

        {/* An affordance, not a control -- it is a span, so the card still has
            exactly one focusable element. It only appears on pointer hover,
            where a cursor already implies the whole tile is clickable. */}
        <span
          aria-hidden
          className="absolute inset-x-3 bottom-3 flex translate-y-2 items-center
                     justify-between rounded-xl bg-surface/85 px-3 py-2 text-xs
                     font-medium opacity-0 backdrop-blur transition duration-300
                     group-hover:translate-y-0 group-hover:opacity-100"
        >
          View product
          <span className="text-accent">→</span>
        </span>
      </div>

      <div className="flex flex-1 flex-col gap-2 p-4">
        <span className="eyebrow">{product.category_name}</span>
        <h3 className="line-clamp-2 font-medium leading-snug transition group-hover:text-accent">
          {product.name}
        </h3>
        <RatingStars rating={product.rating} count={product.review_count} />
        <div className="mt-auto flex items-baseline justify-between gap-2 pt-3">
          <span className="text-lg font-semibold tabular-nums tracking-display">
            {formatPrice(product.price_cents)}
          </span>
          <StockBadge inStock={product.in_stock} />
        </div>
      </div>
    </Link>
  );
}

export function ProductCardSkeleton() {
  return (
    <div className="card overflow-hidden">
      <div className="skeleton aspect-square" />
      <div className="space-y-3 p-4">
        <div className="skeleton h-3 w-16 rounded" />
        <div className="skeleton h-4 w-3/4 rounded" />
        <div className="skeleton h-3 w-24 rounded" />
        <div className="skeleton h-5 w-1/2 rounded" />
      </div>
    </div>
  );
}
