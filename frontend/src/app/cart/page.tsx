"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";

import { useCart } from "@/components/CartProvider";
import { formatPrice, productTint } from "@/lib/format";

export default function CartPage() {
  const { cart, busy, setQuantity, checkout } = useCart();
  const router = useRouter();

  async function placeOrder() {
    const orderId = await checkout();
    if (orderId) router.push(`/orders/${orderId}?placed=1`);
  }

  if (cart.items.length === 0) {
    return (
      <div className="card mx-auto max-w-lg animate-fade-up p-12 text-center">
        <span
          aria-hidden
          className="mx-auto flex h-14 w-14 items-center justify-center rounded-2xl
                     bg-accent/10 text-accent ring-1 ring-accent/20"
        >
          <svg
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth={1.6}
            strokeLinecap="round"
            strokeLinejoin="round"
            className="h-6 w-6"
          >
            <path d="M3 4h2l2.4 11.2a2 2 0 0 0 2 1.6h7.9a2 2 0 0 0 2-1.6L21 8H6M10 21h.01M17 21h.01" />
          </svg>
        </span>
        <h1 className="mt-5 text-xl font-semibold tracking-display">
          Your cart is empty.
        </h1>
        <p className="mt-2 text-sm text-content-muted">
          Items are held in Redis for seven days, so they survive a refresh.
        </p>
        <Link href="/products" className="btn-primary mt-6">
          Browse products
        </Link>
      </div>
    );
  }

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-3xl font-semibold tracking-display sm:text-4xl">Cart</h1>
        <p className="mt-2 text-sm text-content-muted">
          {cart.item_count} item{cart.item_count === 1 ? "" : "s"} · held server-side
          for seven days
        </p>
      </div>

      <div className="grid animate-fade-up gap-8 lg:grid-cols-[1fr_340px]">
        <section className="space-y-3">
          {cart.items.map((item) => {
            return (
              <div key={item.product_id} className="card flex gap-4 p-4">
                <Link
                  href={`/products/${item.slug}`}
                  className="h-24 w-24 shrink-0 overflow-hidden rounded-xl bg-surface-sunken"
                  style={{ backgroundImage: productTint(item.slug) }}
                >
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img
                    src={item.image_path}
                    alt=""
                    className="h-full w-full object-cover transition duration-500
                               hover:scale-105"
                  />
                </Link>

                <div className="flex min-w-0 flex-1 flex-col">
                  <Link
                    href={`/products/${item.slug}`}
                    className="truncate font-medium transition hover:text-accent"
                  >
                    {item.name}
                  </Link>
                  <span className="mt-0.5 text-sm text-content-muted tabular-nums">
                    {formatPrice(item.unit_price_cents)} each
                  </span>
                  {!item.in_stock && (
                    <span className="mt-1.5 text-xs font-medium text-caution">
                      Not enough stock for this quantity
                    </span>
                  )}

                  <div className="mt-auto flex items-center gap-3 pt-3">
                    <div className="flex items-center rounded-xl border border-edge">
                      <button
                        type="button"
                        disabled={busy}
                        onClick={() => setQuantity(item.product_id, item.quantity - 1)}
                        className="px-3 py-1.5 text-content-muted transition
                                   hover:text-content disabled:opacity-40"
                        aria-label={`Decrease ${item.name}`}
                      >
                        −
                      </button>
                      <span className="w-8 text-center text-sm tabular-nums">
                        {item.quantity}
                      </span>
                      <button
                        type="button"
                        disabled={busy || item.quantity >= 10}
                        onClick={() => setQuantity(item.product_id, item.quantity + 1)}
                        className="px-3 py-1.5 text-content-muted transition
                                   hover:text-content disabled:opacity-40"
                        aria-label={`Increase ${item.name}`}
                      >
                        +
                      </button>
                    </div>
                    <button
                      type="button"
                      disabled={busy}
                      onClick={() => setQuantity(item.product_id, 0)}
                      className="text-xs text-content-faint transition hover:text-caution
                                 disabled:opacity-40"
                    >
                      Remove
                    </button>
                  </div>
                </div>

                <span className="shrink-0 self-center text-lg font-semibold tabular-nums tracking-display">
                  {formatPrice(item.subtotal_cents)}
                </span>
              </div>
            );
          })}

          <Link
            href="/products"
            className="inline-block px-1 pt-2 text-sm text-accent hover:underline"
          >
            ← Keep shopping
          </Link>
        </section>

        <aside className="h-fit lg:sticky lg:top-24">
          <div className="card p-6">
            <h2 className="eyebrow">Summary</h2>

            <dl className="mt-4 space-y-2.5 text-sm">
              <div className="flex items-baseline justify-between">
                <dt className="text-content-muted">Items</dt>
                <dd className="tabular-nums">{cart.item_count}</dd>
              </div>
              {/* No invented shipping line. There is no carrier, no rate table
                  and no code that would charge one, so a "Shipping: free" row
                  here would be the one dishonest thing on the page. */}
              <div className="flex items-baseline justify-between border-t border-edge pt-3">
                <dt className="font-medium">Total</dt>
                <dd className="text-2xl font-semibold tabular-nums tracking-display">
                  {formatPrice(cart.total_cents)}
                </dd>
              </div>
            </dl>

            <button
              type="button"
              onClick={placeOrder}
              disabled={busy}
              className="btn-primary mt-6 w-full py-3"
            >
              {busy ? "Placing order…" : "Place order"}
            </button>

            {/* Stated plainly rather than mimicking a payment step. A fake card
                form would demonstrate no platform capability and would make the
                demo dishonest about what it does. */}
            <p className="mt-4 text-xs leading-relaxed text-content-faint">
              Checkout is mock. It creates a real order in PostgreSQL inside one
              transaction and decrements stock. No payment is taken or simulated.
            </p>
          </div>
        </aside>
      </div>
    </div>
  );
}
