"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";

import { useCart } from "@/components/CartProvider";
import { formatPrice, slugHue } from "@/lib/format";

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
        <p className="text-4xl" aria-hidden>
          🧺
        </p>
        <h1 className="mt-4 text-lg font-medium">Your cart is empty.</h1>
        <p className="mt-1 text-sm text-content-muted">
          Items are held in Redis for seven days, so they survive a refresh.
        </p>
        <Link
          href="/products"
          className="mt-5 inline-block rounded-lg bg-accent px-5 py-2.5 text-sm
                     font-medium text-accent-contrast hover:bg-accent-hover"
        >
          Browse products
        </Link>
      </div>
    );
  }

  return (
    <div className="grid animate-fade-up gap-8 lg:grid-cols-[1fr_320px]">
      <section className="space-y-3">
        <h1 className="text-xl font-semibold">
          Cart
          <span className="ml-2 text-sm font-normal text-content-muted">
            {cart.item_count} item{cart.item_count === 1 ? "" : "s"}
          </span>
        </h1>

        {cart.items.map((item) => {
          const hue = slugHue(item.slug);
          return (
            <div key={item.product_id} className="card flex gap-4 p-3">
              <Link
                href={`/products/${item.slug}`}
                className="h-20 w-20 shrink-0 overflow-hidden rounded-lg"
                style={{
                  background: `linear-gradient(135deg,
                    hsl(${hue} 62% 62%), hsl(${(hue + 48) % 360} 58% 44%))`,
                }}
              >
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img
                  src={item.image_path}
                  alt=""
                  className="h-full w-full object-cover"
                />
              </Link>

              <div className="flex min-w-0 flex-1 flex-col">
                <Link
                  href={`/products/${item.slug}`}
                  className="truncate font-medium hover:text-accent"
                >
                  {item.name}
                </Link>
                <span className="text-sm text-content-muted">
                  {formatPrice(item.unit_price_cents)} each
                </span>
                {!item.in_stock && (
                  <span className="mt-1 text-xs text-caution">
                    Not enough stock for this quantity
                  </span>
                )}

                <div className="mt-auto flex items-center gap-3 pt-2">
                  <div className="flex items-center rounded-lg border border-edge">
                    <button
                      type="button"
                      disabled={busy}
                      onClick={() => setQuantity(item.product_id, item.quantity - 1)}
                      className="px-2.5 py-1 text-content-muted hover:text-content
                                 disabled:opacity-40"
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
                      className="px-2.5 py-1 text-content-muted hover:text-content
                                 disabled:opacity-40"
                      aria-label={`Increase ${item.name}`}
                    >
                      +
                    </button>
                  </div>
                  <button
                    type="button"
                    disabled={busy}
                    onClick={() => setQuantity(item.product_id, 0)}
                    className="text-xs text-content-faint hover:text-caution
                               disabled:opacity-40"
                  >
                    Remove
                  </button>
                </div>
              </div>

              <span className="shrink-0 self-center font-semibold tabular-nums">
                {formatPrice(item.subtotal_cents)}
              </span>
            </div>
          );
        })}
      </section>

      <aside className="h-fit lg:sticky lg:top-20">
        <div className="card space-y-4 p-5">
          <div className="flex items-baseline justify-between">
            <span className="text-content-muted">Total</span>
            <span className="text-2xl font-semibold tabular-nums">
              {formatPrice(cart.total_cents)}
            </span>
          </div>

          <button
            type="button"
            onClick={placeOrder}
            disabled={busy}
            className="w-full rounded-lg bg-accent px-5 py-3 font-medium
                       text-accent-contrast transition hover:bg-accent-hover
                       disabled:cursor-not-allowed disabled:opacity-50"
          >
            {busy ? "Placing order…" : "Place order"}
          </button>

          {/* Stated plainly rather than mimicking a payment step. A fake card
              form would demonstrate no platform capability and would make the
              demo dishonest about what it does. */}
          <p className="text-xs leading-relaxed text-content-faint">
            Checkout is mock. It creates a real order in PostgreSQL inside one
            transaction and decrements stock. No payment is taken or simulated.
          </p>
        </div>
      </aside>
    </div>
  );
}
