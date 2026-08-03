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
      className="h-32 w-full"
      role="img"
      aria-label={`Revenue over the last ${recent.length} days with activity`}
    >
      {/* The fill is a gradient rather than a flat tint, so the area reads as
          depth under the line instead of as a second solid shape competing
          with it. The accent is applied through `style` rather than as a
          `stop-color` attribute: an inline style is guaranteed to resolve the
          custom property, and this stays correct when the theme toggles. */}
      <defs>
        <linearGradient id="revenue-fill" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" style={{ stopColor: "rgb(var(--accent))", stopOpacity: 0.35 }} />
          <stop offset="100%" style={{ stopColor: "rgb(var(--accent))", stopOpacity: 0 }} />
        </linearGradient>
      </defs>
      <path d={`${path} L 100 100 L 0 100 Z`} fill="url(#revenue-fill)" stroke="none" />
      <path
        d={path}
        className="stroke-accent"
        fill="none"
        strokeWidth="1.5"
        strokeLinejoin="round"
        vectorEffect="non-scaling-stroke"
      />
    </svg>
  );
}

function Stat({
  label,
  value,
  tone,
}: {
  label: string;
  value: string;
  tone?: "caution";
}) {
  return (
    <div className="card p-5">
      <p className="eyebrow">{label}</p>
      <p
        className={`mt-2 text-3xl font-semibold tabular-nums tracking-display ${
          tone === "caution" ? "text-caution" : ""
        }`}
      >
        {value}
      </p>
    </div>
  );
}

export default async function AdminPage() {
  const stats = await getAdminStats();

  return (
    <div className="animate-fade-up space-y-8">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <p className="eyebrow">Internal</p>
          <h1 className="mt-2 text-3xl font-semibold tracking-display sm:text-4xl">
            Admin
          </h1>
        </div>
        {/* Not exposed on the production Ingress. Said here so nobody assumes
            an unauthenticated dashboard is reachable from the internet. */}
        <span
          className="rounded-full bg-caution/10 px-3.5 py-1.5 text-xs font-medium
                     text-caution ring-1 ring-caution/20"
        >
          Not published in production
        </span>
      </div>

      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Stat label="Orders" value={stats.order_count.toLocaleString()} />
        <Stat label="Revenue" value={formatPrice(stats.revenue_cents)} />
        <Stat label="Products" value={stats.product_count.toLocaleString()} />
        <Stat
          label="Low stock"
          value={String(stats.low_stock.length)}
          tone={stats.low_stock.length > 0 ? "caution" : undefined}
        />
      </div>

      <section className="card p-6">
        <div className="flex items-baseline justify-between gap-3">
          <h2 className="eyebrow">Revenue, last 30 days with activity</h2>
          <span className="text-sm font-medium tabular-nums">
            {formatPrice(stats.revenue_cents)}
          </span>
        </div>
        <div className="mt-5">
          <Sparkline points={stats.revenue_by_day} />
        </div>
      </section>

      <section className="card overflow-hidden">
        <h2 className="border-b border-edge bg-surface-sunken px-5 py-3">
          <span className="eyebrow">Low stock</span>
        </h2>
        {stats.low_stock.length === 0 ? (
          <p className="p-5 text-sm text-content-faint">Nothing below ten units.</p>
        ) : (
          <ul className="divide-y divide-edge">
            {stats.low_stock.map((row) => (
              <li key={row.slug} className="flex items-center gap-3 px-5 py-3">
                <Link
                  href={`/products/${row.slug}`}
                  className="min-w-0 flex-1 truncate transition hover:text-accent"
                >
                  {row.name}
                </Link>
                <span
                  className={`rounded-full px-2.5 py-0.5 text-xs font-medium
                              tabular-nums ring-1 ${
                                row.quantity === 0
                                  ? "bg-caution/10 text-caution ring-caution/20"
                                  : "text-content-muted ring-edge"
                              }`}
                >
                  {row.quantity === 0 ? "out of stock" : `${row.quantity} left`}
                </span>
              </li>
            ))}
          </ul>
        )}
      </section>

      {/* The teaching note. This page exists to be the expensive one, and
          saying so turns a dashboard into an explanation. */}
      <p className="max-w-3xl text-xs leading-relaxed text-content-faint">
        This page runs four aggregate queries and is cached in Redis for 60
        seconds. Each query is timed separately under{" "}
        <code className="font-mono text-content-muted">
          novashop_db_query_duration_seconds
        </code>
        , labelled by a name this code chooses rather than by SQL text — statements
        carry literals, and a label built from one is unbounded.
      </p>
    </div>
  );
}
