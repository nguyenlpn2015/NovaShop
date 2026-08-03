import Link from "next/link";

import { getOrders } from "@/lib/api";
import { formatPrice } from "@/lib/format";

export const dynamic = "force-dynamic";

const TONE: Record<string, string> = {
  placed: "bg-accent/10 text-accent ring-accent/20",
  paid: "bg-positive/10 text-positive ring-positive/20",
  shipped: "bg-positive/10 text-positive ring-positive/20",
  cancelled: "bg-caution/10 text-caution ring-caution/20",
};

export default async function OrdersPage() {
  const orders = await getOrders();

  return (
    <div className="animate-fade-up space-y-8">
      <div>
        <h1 className="text-3xl font-semibold tracking-display sm:text-4xl">Orders</h1>
        <p className="mt-2 text-sm text-content-muted">
          The twenty most recent. Seeded history plus anything placed here.
        </p>
      </div>

      {orders.length === 0 ? (
        <div className="card p-14 text-center">
          <p className="font-medium">No orders yet.</p>
          <Link href="/products" className="btn-primary mt-5">
            Browse products
          </Link>
        </div>
      ) : (
        <div className="card overflow-hidden">
          {/* A header row, so the columns are labelled rather than guessed at.
              Hidden on narrow screens, where the rows collapse and the labels
              would take a whole line of their own to describe two fields. */}
          <div
            className="hidden items-center gap-4 border-b border-edge bg-surface-sunken
                       px-5 py-2.5 sm:flex"
          >
            <span className="eyebrow w-20">Order</span>
            <span className="eyebrow min-w-0 flex-1">Customer</span>
            <span className="eyebrow w-16 text-right">Lines</span>
            <span className="eyebrow w-24 text-center">Status</span>
            <span className="eyebrow w-32 text-right">Total</span>
          </div>

          <div className="divide-y divide-edge">
            {orders.map((order) => (
              <Link
                key={order.id}
                href={`/orders/${order.id}`}
                className="flex flex-wrap items-center gap-x-4 gap-y-2 px-5 py-3.5
                           transition hover:bg-surface-sunken"
              >
                <span className="w-20 font-mono text-sm text-content-muted">
                  #{order.id}
                </span>
                <span className="min-w-0 flex-1 truncate font-medium">
                  {order.customer}
                </span>
                <span className="w-16 text-right text-sm text-content-muted tabular-nums">
                  {order.line_count}
                </span>
                <span className="flex w-24 justify-center">
                  <span
                    className={`rounded-full px-2.5 py-0.5 text-xs font-medium ring-1 ${
                      TONE[order.status] ??
                      "bg-surface-sunken text-content-muted ring-edge"
                    }`}
                  >
                    {order.status}
                  </span>
                </span>
                <span className="w-32 text-right font-semibold tabular-nums">
                  {formatPrice(order.total_cents)}
                </span>
              </Link>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
