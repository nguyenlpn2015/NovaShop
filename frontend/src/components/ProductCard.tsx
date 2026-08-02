import Link from "next/link";

import type { ProductSummary } from "@/lib/api";
import { formatPrice, slugHue } from "@/lib/format";

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
    <span className="flex items-center gap-1 text-xs text-content-muted">
      <span aria-hidden className="text-caution">
        {"★".repeat(rounded)}
        <span className="text-content-faint">{"★".repeat(5 - rounded)}</span>
      </span>
      <span className="sr-only">{rating} out of 5</span>
      <span>
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
  const hue = slugHue(product.slug);

  return (
    <Link
      href={`/products/${product.slug}`}
      className="card group flex animate-fade-up flex-col overflow-hidden transition
                 hover:border-accent/40 hover:shadow-lg hover:shadow-black/5"
    >
      <div
        className="relative aspect-[4/3] overflow-hidden"
        style={{
          background: `linear-gradient(135deg,
            hsl(${hue} 62% 62%), hsl(${(hue + 48) % 360} 58% 44%))`,
        }}
      >
        {/* The image sits over a gradient derived from the slug, so a slow or
            missing file degrades to a coloured tile rather than a broken icon.
            Plain <img> rather than next/image: optimisation writes to
            .next/cache, and the container has a read-only root filesystem. */}
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          src={product.image_path}
          alt=""
          loading="lazy"
          decoding="async"
          className="h-full w-full object-cover transition duration-300
                     group-hover:scale-[1.03]"
        />
      </div>

      <div className="flex flex-1 flex-col gap-2 p-4">
        <span className="text-xs uppercase tracking-wide text-content-faint">
          {product.category_name}
        </span>
        <h3 className="line-clamp-2 font-medium leading-snug group-hover:text-accent">
          {product.name}
        </h3>
        <RatingStars rating={product.rating} count={product.review_count} />
        <div className="mt-auto flex items-baseline justify-between pt-2">
          <span className="text-lg font-semibold">
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
      <div className="skeleton aspect-[4/3]" />
      <div className="space-y-3 p-4">
        <div className="skeleton h-3 w-16 rounded" />
        <div className="skeleton h-4 w-3/4 rounded" />
        <div className="skeleton h-3 w-24 rounded" />
        <div className="skeleton h-5 w-1/2 rounded" />
      </div>
    </div>
  );
}
