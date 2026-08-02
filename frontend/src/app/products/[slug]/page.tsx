import Link from "next/link";
import { notFound } from "next/navigation";

import { RatingStars, StockBadge } from "@/components/ProductCard";
import { ApiError, getProduct } from "@/lib/api";
import { formatPrice, slugHue } from "@/lib/format";

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

  const hue = slugHue(product.slug);

  return (
    <div className="space-y-10">
      <nav className="flex items-center gap-2 text-sm text-content-muted">
        <Link href="/" className="hover:text-content">
          Home
        </Link>
        <span aria-hidden>›</span>
        <Link
          href={`/products?category=${product.category_slug}`}
          className="hover:text-content"
        >
          {product.category_name}
        </Link>
        <span aria-hidden>›</span>
        <span className="truncate text-content">{product.name}</span>
      </nav>

      <div className="grid animate-fade-up gap-8 md:grid-cols-2">
        <div
          className="aspect-square overflow-hidden rounded-card border border-edge"
          style={{
            background: `linear-gradient(135deg,
              hsl(${hue} 62% 62%), hsl(${(hue + 48) % 360} 58% 44%))`,
          }}
        >
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={product.image_path}
            alt={product.name}
            className="h-full w-full object-cover"
          />
        </div>

        <div className="flex flex-col gap-4">
          <h1 className="text-2xl font-semibold sm:text-3xl">{product.name}</h1>
          <RatingStars rating={product.rating} count={product.review_count} />
          <p className="text-3xl font-semibold">{formatPrice(product.price_cents)}</p>
          <div className="flex items-center gap-3">
            <StockBadge inStock={product.in_stock} />
            {product.in_stock && (
              <span className="text-sm text-content-muted">
                {product.stock_quantity} available
              </span>
            )}
          </div>
          <p className="text-content-muted">{product.description}</p>

          <button
            type="button"
            disabled={!product.in_stock}
            className="mt-2 w-full rounded-lg bg-accent px-5 py-3 font-medium
                       text-accent-contrast transition hover:bg-accent-hover
                       disabled:cursor-not-allowed disabled:opacity-40 sm:w-auto"
          >
            Add to cart
          </button>
          {/* Honest about what is not built yet, rather than a button that
              silently does nothing. */}
          <p className="text-xs text-content-faint">
            The cart arrives with the next milestone. This button is inert.
          </p>
        </div>
      </div>

      <section>
        <h2 className="mb-4 text-sm font-medium uppercase tracking-wide text-content-muted">
          Reviews
        </h2>
        {product.reviews.length === 0 ? (
          <p className="text-sm text-content-faint">No reviews for this product yet.</p>
        ) : (
          <ul className="grid gap-3 sm:grid-cols-2">
            {product.reviews.map((review) => (
              <li key={review.id} className="card p-4">
                <div className="flex items-center justify-between">
                  <span className="font-medium">{review.author}</span>
                  <span aria-hidden className="text-caution">
                    {"★".repeat(review.rating)}
                  </span>
                </div>
                <p className="mt-2 text-sm text-content-muted">{review.body}</p>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
