import Link from "next/link";
import { notFound } from "next/navigation";

import { ApiError, getOrder } from "@/lib/api";
import { formatPrice } from "@/lib/format";

export const dynamic = "force-dynamic";

export default async function OrderPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ placed?: string }>;
}) {
  const [{ id }, { placed }] = await Promise.all([params, searchParams]);
  const numeric = Number(id);
  if (!Number.isInteger(numeric)) notFound();

  let order;
  try {
    order = await getOrder(numeric);
  } catch (error) {
    if (error instanceof ApiError && error.status === 404) notFound();
    throw error;
  }

  return (
    <div className="mx-auto max-w-2xl animate-fade-up space-y-6">
      {placed && (
        <div
          className="rounded-card border border-positive/30 bg-positive/10 px-4 py-3
                     text-sm text-positive"
        >
          Order placed. It exists in PostgreSQL and stock has been decremented.
        </div>
      )}

      <div className="flex items-baseline justify-between">
        <h1 className="text-xl font-semibold">Order #{order.id}</h1>
        <Link href="/orders" className="text-sm text-accent hover:underline">
          All orders →
        </Link>
      </div>

      <div className="card divide-y divide-edge">
        {order.items.map((item) => (
          <div key={item.slug} className="flex items-center gap-3 p-3">
            <Link href={`/products/${item.slug}`} className="min-w-0 flex-1 truncate hover:text-accent">
              {item.name}
            </Link>
            <span className="text-sm text-content-muted">× {item.quantity}</span>
            <span className="w-28 text-right tabular-nums">
              {formatPrice(item.subtotal_cents)}
            </span>
          </div>
        ))}
        <div className="flex items-center justify-between p-3 font-semibold">
          <span>Total</span>
          <span className="tabular-nums">{formatPrice(order.total_cents)}</span>
        </div>
      </div>

      <dl className="grid grid-cols-2 gap-3 text-sm sm:grid-cols-3">
        <div className="card p-3">
          <dt className="text-content-faint">Status</dt>
          <dd className="mt-0.5 font-medium">{order.status}</dd>
        </div>
        <div className="card p-3">
          <dt className="text-content-faint">Customer</dt>
          <dd className="mt-0.5 truncate font-medium">{order.customer}</dd>
        </div>
        <div className="card p-3">
          <dt className="text-content-faint">Placed</dt>
          <dd className="mt-0.5 font-medium">
            {new Date(order.created_at).toISOString().slice(0, 10)}
          </dd>
        </div>
      </dl>
    </div>
  );
}
