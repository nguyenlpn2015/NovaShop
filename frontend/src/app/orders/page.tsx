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
    <div className="animate-fade-up space-y-5">
      <div>
        <h1 className="text-xl font-semibold">Orders</h1>
        <p className="mt-1 text-sm text-content-muted">
          The twenty most recent. Seeded history plus anything placed here.
        </p>
      </div>

      <div className="card divide-y divide-edge overflow-hidden">
        {orders.map((order) => (
          <Link
            key={order.id}
            href={`/orders/${order.id}`}
            className="flex items-center gap-4 px-4 py-3 transition hover:bg-surface-sunken"
          >
            <span className="w-16 font-mono text-sm text-content-muted">
              #{order.id}
            </span>
            <span className="min-w-0 flex-1 truncate">{order.customer}</span>
            <span className="hidden text-sm text-content-muted sm:block">
              {order.line_count} line{order.line_count === 1 ? "" : "s"}
            </span>
            <span
              className={`rounded-full px-2 py-0.5 text-xs font-medium ring-1 ${
                TONE[order.status] ?? "bg-surface-sunken text-content-muted ring-edge"
              }`}
            >
              {order.status}
            </span>
            <span className="w-28 text-right font-medium tabular-nums">
              {formatPrice(order.total_cents)}
            </span>
          </Link>
        ))}
      </div>
    </div>
  );
}
