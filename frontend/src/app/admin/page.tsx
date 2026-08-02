import Link from "next/link";

import { getAdminStats } from "@/lib/api";
import { formatPrice } from "@/lib/format";

export const dynamic = "force-dynamic";

function Sparkline({ points }: { points: { day: string; revenue_cents: number }[] }) {
  const recent = points.slice(-30);
  if (recent.length < 2) {
    return <p className="text-sm text-content-faint">Not enough history yet.</p>;
  }

  const max = Math.max(...recent.map((p) => p.revenue_cents));
  const path = recent
    .map((point, index) => {
      const x = (index / (recent.length - 1)) * 100;
      const y = 100 - (point.revenue_cents / max) * 100;
      return `${index === 0 ? "M" : "L"} ${x.toFixed(2)} ${y.toFixed(2)}`;
    })
    .join(" ");

  return (
    // preserveAspectRatio="none" so the 0-100 coordinate space stretches to
    // whatever width the card ends up at, without a resize observer.
    <svg
      viewBox="0 0 100 100"
      preserveAspectRatio="none"
      className="h-24 w-full"
      role="img"
      aria-label={`Revenue over the last ${recent.length} days with activity`}
    >
      <path
        d={`${path} L 100 100 L 0 100 Z`}
        className="fill-accent/10"
        stroke="none"
      />
      <path
        d={path}
        className="stroke-accent"
        fill="none"
        strokeWidth="1.5"
        vectorEffect="non-scaling-stroke"
      />
    </svg>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="card p-4">
      <p className="text-xs uppercase tracking-wide text-content-faint">{label}</p>
      <p className="mt-1 text-2xl font-semibold tabular-nums">{value}</p>
    </div>
  );
}

export default async function AdminPage() {
  const stats = await getAdminStats();

  return (
    <div className="animate-fade-up space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="text-xl font-semibold">Admin</h1>
        {/* Not exposed on the production Ingress. Said here so nobody assumes
            an unauthenticated dashboard is reachable from the internet. */}
        <span
          className="rounded-full bg-caution/10 px-3 py-1 text-xs font-medium
                     text-caution ring-1 ring-caution/20"
        >
          Not published in production
        </span>
      </div>

      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Stat label="Orders" value={stats.order_count.toLocaleString()} />
        <Stat label="Revenue" value={formatPrice(stats.revenue_cents)} />
        <Stat label="Products" value={stats.product_count.toLocaleString()} />
        <Stat label="Low stock" value={String(stats.low_stock.length)} />
      </div>

      <section className="card p-5">
        <h2 className="text-sm font-medium uppercase tracking-wide text-content-muted">
          Revenue
        </h2>
        <div className="mt-3">
          <Sparkline points={stats.revenue_by_day} />
        </div>
      </section>

      <section className="card overflow-hidden">
        <h2
          className="border-b border-edge px-4 py-3 text-sm font-medium uppercase
                     tracking-wide text-content-muted"
        >
          Low stock
        </h2>
        {stats.low_stock.length === 0 ? (
          <p className="p-4 text-sm text-content-faint">Nothing below ten units.</p>
        ) : (
          <ul className="divide-y divide-edge">
            {stats.low_stock.map((row) => (
              <li key={row.slug} className="flex items-center gap-3 px-4 py-2.5">
                <Link
                  href={`/products/${row.slug}`}
                  className="min-w-0 flex-1 truncate hover:text-accent"
                >
                  {row.name}
                </Link>
                <span
                  className={`tabular-nums ${
                    row.quantity === 0 ? "text-caution" : "text-content-muted"
                  }`}
                >
                  {row.quantity}
                </span>
              </li>
            ))}
          </ul>
        )}
      </section>

      {/* The teaching note. This page exists to be the expensive one, and
          saying so turns a dashboard into an explanation. */}
      <p className="text-xs leading-relaxed text-content-faint">
        This page runs four aggregate queries and is cached in Redis for 60
        seconds. Each query is timed separately under{" "}
        <code className="text-content-muted">novashop_db_query_duration_seconds</code>,
        labelled by a name this code chooses rather than by SQL text — statements
        carry literals, and a label built from one is unbounded.
      </p>
    </div>
  );
}
