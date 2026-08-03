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
    <div className="mx-auto max-w-3xl animate-fade-up space-y-8">
      {placed && (
        <div
          className="flex items-start gap-3 rounded-card border border-positive/30
                     bg-positive/10 px-4 py-3.5 text-sm text-positive"
        >
          <span
            aria-hidden
            className="mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center
                       rounded-full bg-positive/20"
          >
            ✓
          </span>
          <span>
            <strong className="font-semibold">Order placed.</strong> It exists in
            PostgreSQL and stock has been decremented.
          </span>
        </div>
      )}

      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <p className="eyebrow">Order</p>
          <h1 className="mt-2 text-3xl font-semibold tracking-display">
            #{order.id}
          </h1>
        </div>
        <Link
          href="/orders"
          className="btn-secondary"
        >
          All orders →
        </Link>
      </div>

      <dl className="grid grid-cols-2 gap-3 sm:grid-cols-3">
        <div className="card p-4">
          <dt className="eyebrow">Status</dt>
          <dd className="mt-1.5 font-medium capitalize">{order.status}</dd>
        </div>
        <div className="card p-4">
          <dt className="eyebrow">Customer</dt>
          <dd className="mt-1.5 truncate font-medium">{order.customer}</dd>
        </div>
        <div className="card p-4">
          <dt className="eyebrow">Placed</dt>
          {/* ISO, sliced to the date. A locale-formatted date rendered on the
              server and hydrated on the client can disagree, and the mismatch
              is reported as a hydration error rather than as a wrong date. */}
          <dd className="mt-1.5 font-medium tabular-nums">
            {new Date(order.created_at).toISOString().slice(0, 10)}
          </dd>
        </div>
      </dl>

      <div className="card overflow-hidden">
        <h2 className="border-b border-edge bg-surface-sunken px-5 py-3">
          <span className="eyebrow">
            {order.items.length} line{order.items.length === 1 ? "" : "s"}
          </span>
        </h2>

        <div className="divide-y divide-edge">
          {order.items.map((item) => (
            <div key={item.slug} className="flex items-center gap-4 px-5 py-3.5">
              <Link
                href={`/products/${item.slug}`}
                className="min-w-0 flex-1 truncate font-medium transition hover:text-accent"
              >
                {item.name}
              </Link>
              <span className="shrink-0 text-sm text-content-muted tabular-nums">
                × {item.quantity}
              </span>
              <span className="w-32 shrink-0 text-right tabular-nums">
                {formatPrice(item.subtotal_cents)}
              </span>
            </div>
          ))}
        </div>

        <div className="flex items-baseline justify-between border-t border-edge bg-surface-sunken px-5 py-4">
          <span className="font-medium">Total</span>
          <span className="text-2xl font-semibold tabular-nums tracking-display">
            {formatPrice(order.total_cents)}
          </span>
        </div>
      </div>
    </div>
  );
}
