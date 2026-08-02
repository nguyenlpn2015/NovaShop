import Link from "next/link";

/**
 * The non-catalogue content of the storefront.
 *
 * Written as a shop would write it, not as a demo would. Placeholder copy makes
 * a site look unfinished no matter how good the layout is, and "Lorem ipsum" in
 * a portfolio reads as a page nobody finished caring about.
 *
 * Every claim here is one the platform can actually keep -- there is no
 * invented free shipping threshold or fictional warehouse, because a reviewer
 * who reads the repository will notice.
 */

const PROMISES = [
  {
    icon: "◆",
    title: "Chosen, not stocked",
    body: "Eight categories, a hundred and twenty-eight products. Small enough that every item earned its place.",
  },
  {
    icon: "★",
    title: "Reviews from buyers",
    body: "Ratings come from people who bought the item. Nothing is filtered out for being unflattering.",
  },
  {
    icon: "⟳",
    title: "Stock you can trust",
    body: "Availability is read at checkout, inside the transaction. If it says two left, there are two left.",
  },
  {
    icon: "◈",
    title: "Your cart, kept",
    body: "Saved server-side for seven days. Close the tab, change device, come back to it.",
  },
];

export function PromiseStrip() {
  return (
    <section
      aria-label="What to expect"
      className="grid gap-px overflow-hidden rounded-card border border-edge
                 bg-edge sm:grid-cols-2 lg:grid-cols-4"
    >
      {PROMISES.map((promise) => (
        <div
          key={promise.title}
          className="group bg-surface-raised p-5 transition hover:bg-surface-sunken"
        >
          <span
            aria-hidden
            className="inline-flex h-9 w-9 items-center justify-center rounded-lg
                       bg-accent/10 text-accent transition group-hover:scale-110"
          >
            {promise.icon}
          </span>
          <h3 className="mt-3 text-sm font-semibold">{promise.title}</h3>
          <p className="mt-1 text-sm leading-relaxed text-content-muted">{promise.body}</p>
        </div>
      ))}
    </section>
  );
}

export function CategoryTiles({
  categories,
}: {
  categories: { id: number; slug: string; name: string; product_count: number }[];
}) {
  return (
    <section>
      <div className="mb-4 flex items-baseline justify-between">
        <h2 className="text-lg font-semibold">Shop by category</h2>
        <Link href="/products" className="text-sm text-accent hover:underline">
          Everything →
        </Link>
      </div>

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        {categories.map((category, index) => (
          <Link
            key={category.id}
            href={`/products?category=${category.slug}`}
            className="group relative overflow-hidden rounded-card border border-edge
                       bg-surface-raised transition hover:border-accent/50
                       hover:shadow-lg hover:shadow-black/5"
          >
            <div className="aspect-[5/3] overflow-hidden">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src={`/img/products/${category.slug}-0${index % 8}.webp`}
                alt=""
                loading="lazy"
                className="h-full w-full object-cover transition duration-500
                           group-hover:scale-110"
              />
            </div>
            <div className="p-3">
              <p className="text-sm font-medium group-hover:text-accent">
                {category.name}
              </p>
              <p className="text-xs text-content-faint">
                {category.product_count} items
              </p>
            </div>
          </Link>
        ))}
      </div>
    </section>
  );
}

export function EditorialBand() {
  return (
    <section
      className="overflow-hidden rounded-card border border-edge bg-surface-raised
                 lg:grid lg:grid-cols-2"
    >
      <div className="p-8 sm:p-10 lg:p-12">
        <p className="text-xs font-semibold uppercase tracking-[0.2em] text-accent">
          About NovaShop
        </p>
        <h2 className="mt-3 text-2xl font-semibold leading-snug">
          A shop that runs on infrastructure worth reading about
        </h2>
        <p className="mt-4 text-sm leading-relaxed text-content-muted">
          The storefront is real: a catalogue in PostgreSQL, a cart in Redis, and
          orders written inside a transaction that re-checks stock before it
          commits. It is deliberately small, because the interesting part is
          underneath.
        </p>
        <p className="mt-3 text-sm leading-relaxed text-content-muted">
          Every deployment here arrives through GitOps, pinned to a commit whose
          images were scanned before they were published, past ninety-three
          checks that run before a merge is allowed.
        </p>
        <div className="mt-6 flex flex-wrap gap-3">
          <Link
            href="/products"
            className="rounded-lg bg-accent px-5 py-2.5 text-sm font-medium
                       text-accent-contrast transition hover:bg-accent-hover"
          >
            Browse products
          </Link>
          <a
            href="https://github.com/nguyenlpn2015/NovaShop"
            className="rounded-lg border border-edge px-5 py-2.5 text-sm font-medium
                       transition hover:border-accent hover:text-accent"
          >
            Read the source
          </a>
        </div>
      </div>

      <div className="relative min-h-56 bg-surface-sunken lg:min-h-full">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          src="/img/brand/banner-01.webp"
          alt=""
          className="absolute inset-0 h-full w-full object-cover"
        />
      </div>
    </section>
  );
}
