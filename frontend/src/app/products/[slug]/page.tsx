import Link from "next/link";
import { notFound } from "next/navigation";

import { AddToCart } from "@/components/AddToCart";
import { RatingStars, StockBadge } from "@/components/ProductCard";
import { ApiError, getProduct } from "@/lib/api";
import { formatPrice, productTint } from "@/lib/format";

export const dynamic = "force-dynamic";

// KNOWN LIMITATION: a missing product renders the not-found page with HTTP 200.
//
// notFound() is reached -- the correct page is served -- but the status line
// has already been committed by the time it runs, because App Router streams
// the response. Removing `force-dynamic` and moving the route's loading.tsx
// were both tried and neither changed it, so the cause is the streamed render
// itself rather than either of those.
//
// It is recorded here rather than worked around because the workarounds are
// worse than the defect: a middleware existence check adds a backend round trip
// to every product request, and rendering the message without notFound() gives
// up the correct page as well as the correct status.
//
// It matters to a crawler or an uptime monitor, not to a reader. Unmatched
// routes -- /nonsense -- still return a real 404.

/**
 * The reassurance column under the buy button.
 *
 * Each line describes something this platform actually does. There is no
 * invented returns window or shipping promise, because a reader who opens the
 * repository will find no code behind either.
 */
const ASSURANCES = [
  {
    title: "Stock checked at checkout",
    body: "Re-read inside the transaction that writes your order, not cached from this page.",
  },
  {
    title: "Cart survives a restart",
    body: "Held in Redis for seven days, so a refresh, a new tab or a pod restart does not lose it.",
  },
  {
    title: "Checkout is mock",
    body: "A real order row is written and stock is decremented. No payment is taken or simulated.",
  },
];

export default async function ProductPage({
  params,
}: {
  params: Promise<{ slug: string }>;
}) {
  const { slug } = await params;

  let product;
  try {
    product = await getProduct(slug);
  } catch (error) {
    // A 404 from the backend is a missing product and renders the not-found
    // page. Anything else is a fault and must keep propagating -- swallowing it
    // here would show "product not found" during a database outage, which sends
    // whoever is on call looking in entirely the wrong place.
    if (error instanceof ApiError && error.status === 404) notFound();
    throw error;
  }

  return (
    <div className="space-y-14">
      <nav className="flex items-center gap-2 text-sm text-content-muted">
        <Link href="/" className="transition hover:text-content">
          Home
        </Link>
        <span aria-hidden className="text-content-faint">
          /
        </span>
        <Link
          href={`/products?category=${product.category_slug}`}
          className="transition hover:text-content"
        >
          {product.category_name}
        </Link>
        <span aria-hidden className="text-content-faint">
          /
        </span>
        <span className="truncate text-content">{product.name}</span>
      </nav>

      <div className="grid animate-fade-up gap-10 lg:grid-cols-2 lg:gap-14">
        <div
          className="relative aspect-square overflow-hidden rounded-card border
                     border-edge bg-surface-sunken"
          style={{ backgroundImage: productTint(product.slug, product.category_slug) }}
        >
          {/* Alt text here, empty on the card. This image is the subject of the
              page rather than a thumbnail beside a heading that already names
              the product. */}
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={product.image_path}
            alt={product.name}
            className="h-full w-full object-cover"
          />
          {!product.in_stock && (
            <span
              className="absolute left-4 top-4 rounded-full bg-surface/90 px-3 py-1
                         text-xs font-semibold uppercase tracking-wide
                         text-content-muted backdrop-blur"
            >
              Sold out
            </span>
          )}
        </div>

        {/* Sticky on wide screens so the price and the button stay reachable
            while the description and the reviews scroll past. */}
        <div className="lg:sticky lg:top-24 lg:h-fit">
          <Link
            href={`/products?category=${product.category_slug}`}
            className="eyebrow transition hover:text-accent"
          >
            {product.category_name}
          </Link>

          <h1 className="mt-3 text-3xl font-semibold leading-tight tracking-display sm:text-4xl">
            {product.name}
          </h1>

          <div className="mt-4">
            <RatingStars rating={product.rating} count={product.review_count} />
          </div>

          <p className="mt-6 text-4xl font-semibold tabular-nums tracking-display">
            {formatPrice(product.price_cents)}
          </p>

          <div className="mt-4 flex flex-wrap items-center gap-3">
            <StockBadge inStock={product.in_stock} />
            {product.in_stock && (
              <span className="chip">{product.stock_quantity} available</span>
            )}
          </div>

          <p className="mt-6 leading-relaxed text-content-muted">
            {product.description}
          </p>

          <AddToCart productId={product.id} inStock={product.in_stock} />

          <dl className="mt-8 space-y-px overflow-hidden rounded-card border border-edge bg-edge">
            {ASSURANCES.map((item) => (
              <div key={item.title} className="bg-surface-raised px-4 py-3">
                <dt className="text-sm font-medium">{item.title}</dt>
                <dd className="mt-0.5 text-xs leading-relaxed text-content-muted">
                  {item.body}
                </dd>
              </div>
            ))}
          </dl>
        </div>
      </div>

      <section>
        <div className="mb-6 flex flex-wrap items-end justify-between gap-3">
          <div>
            <p className="eyebrow">What buyers said</p>
            <h2 className="mt-2 text-2xl font-semibold tracking-display">Reviews</h2>
          </div>
          {product.review_count > 0 && (
            <p className="text-sm text-content-muted">
              {product.review_count} review{product.review_count === 1 ? "" : "s"}
              {product.rating !== null && ` · ${product.rating.toFixed(1)} average`}
            </p>
          )}
        </div>

        {product.reviews.length === 0 ? (
          <div className="card p-10 text-center">
            <p className="text-sm text-content-muted">
              No reviews for this product yet.
            </p>
          </div>
        ) : (
          <ul className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {product.reviews.map((review) => (
              <li key={review.id} className="card flex flex-col p-5">
                <span aria-hidden className="text-caution">
                  {"★".repeat(review.rating)}
                  <span className="text-content-faint/60">
                    {"★".repeat(5 - review.rating)}
                  </span>
                </span>
                <span className="sr-only">{review.rating} out of 5</span>
                <p className="mt-3 flex-1 text-sm leading-relaxed text-content-muted">
                  {review.body}
                </p>
                <p className="mt-4 border-t border-edge pt-3 text-sm font-medium">
                  {review.author}
                </p>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
