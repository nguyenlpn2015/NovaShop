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
    icon: "M12 3 4 7v5c0 4.4 3.4 8.5 8 9 4.6-.5 8-4.6 8-9V7l-8-4Z",
    title: "Chosen, not stocked",
    body: "Eight categories. Small enough that every item earned its place.",
  },
  {
    icon: "m12 3.5 2.6 5.4 5.9.8-4.3 4.2 1 5.9-5.2-2.8-5.2 2.8 1-5.9L3.5 9.7l5.9-.8L12 3.5Z",
    title: "Reviews from buyers",
    body: "Ratings come from people who bought the item. Nothing is filtered out for being unflattering.",
  },
  {
    icon: "M20 12a8 8 0 1 1-2.3-5.7M20 4v4h-4",
    title: "Stock you can trust",
    body: "Availability is read at checkout, inside the transaction. If it says two left, there are two left.",
  },
  {
    icon: "M4 7h16v13H4zM8 7V5a4 4 0 0 1 8 0v2",
    title: "Your cart, kept",
    body: "Saved server-side for seven days. Close the tab, change device, come back to it.",
  },
];

export function PromiseStrip() {
  return (
    <section
      aria-label="What to expect"
      // A single hairline grid rather than four bordered boxes: gap-px over a
      // background the colour of the border draws each divider exactly once,
      // so adjacent cards cannot show a doubled 2px seam.
      className="grid gap-px overflow-hidden rounded-card border border-edge
                 bg-edge sm:grid-cols-2 lg:grid-cols-4"
    >
      {PROMISES.map((promise) => (
        <div
          key={promise.title}
          className="group bg-surface-raised p-6 transition hover:bg-surface-sunken"
        >
          <span
            aria-hidden
            className="inline-flex h-10 w-10 items-center justify-center rounded-xl
                       bg-accent/10 text-accent ring-1 ring-accent/20 transition
                       group-hover:bg-accent/15"
          >
            <svg
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth={1.6}
              strokeLinecap="round"
              strokeLinejoin="round"
              className="h-5 w-5"
            >
              <path d={promise.icon} />
            </svg>
          </span>
          <h3 className="mt-4 text-sm font-semibold tracking-display">{promise.title}</h3>
          <p className="mt-1.5 text-sm leading-relaxed text-content-muted">
            {promise.body}
          </p>
        </div>
      ))}
    </section>
  );
}

/** A section heading with an optional link on the right. Used four times on the
 *  home page, so it lives here rather than being copied into each. */
export function SectionHeading({
  eyebrow,
  title,
  body,
  action,
}: {
  eyebrow?: string;
  title: string;
  body?: string;
  action?: { label: string; href: string };
}) {
  return (
    <div className="mb-6 flex flex-wrap items-end justify-between gap-4">
      <div>
        {eyebrow && <p className="eyebrow">{eyebrow}</p>}
        <h2 className="mt-2 text-2xl font-semibold tracking-display sm:text-3xl">
          {title}
        </h2>
        {body && (
          <p className="mt-2 max-w-xl text-sm leading-relaxed text-content-muted">
            {body}
          </p>
        )}
      </div>
      {action && (
        <Link
          href={action.href}
          className="group inline-flex shrink-0 items-center gap-1.5 rounded-lg
                     border border-edge px-4 py-2 text-sm font-medium transition
                     hover:border-accent/50 hover:text-accent"
        >
          {action.label}
          <span aria-hidden className="transition-transform group-hover:translate-x-0.5">
            →
          </span>
        </Link>
      )}
    </div>
  );
}

export function CategoryTiles({
  categories,
}: {
  categories: { id: number; slug: string; name: string; product_count: number }[];
}) {
  return (
    <section>
      <SectionHeading
        eyebrow="Browse"
        title="Shop by category"
        body="Eight of them, and the count beside each is read from the catalogue rather than typed in."
        action={{ label: "Everything", href: "/products" }}
      />

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        {categories.map((category, index) => (
          <Link
            key={category.id}
            href={`/products?category=${category.slug}`}
            className="group relative isolate overflow-hidden rounded-card border
                       border-edge transition duration-300 hover:-translate-y-0.5
                       hover:border-accent/40 hover:shadow-lift"
          >
            <div className="aspect-[4/5] overflow-hidden bg-surface-sunken sm:aspect-[3/4]">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src={`/img/products/${category.slug}-0${index % 8}.webp`}
                alt=""
                loading="lazy"
                className="h-full w-full object-cover transition duration-700
                           group-hover:scale-105"
              />
            </div>

            {/* The label sits on the image rather than under it. A scrim under
                the text keeps it readable whatever the photograph does. */}
            <div className="absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/85 via-black/45 to-transparent p-4 pt-10">
              <p className="text-sm font-semibold text-white">{category.name}</p>
              <p className="mt-0.5 text-xs text-white/65">
                {category.product_count} items
              </p>
            </div>
          </Link>
        ))}
      </div>
    </section>
  );
}

/**
 * The claims in this band are the ones the repository can be checked against.
 * If one of these numbers changes, it changes in the README on the same commit.
 */
const FACTS = [
  { value: "12/12", label: "Argo CD apps synced" },
  { value: "94", label: "Pre-merge checks" },
  { value: "14", label: "Alerts with a runbook" },
  { value: "15", label: "Decision records" },
];

export function EditorialBand() {
  return (
    <section className="overflow-hidden rounded-card border border-edge bg-surface-raised">
      <div className="lg:grid lg:grid-cols-[1.1fr_1fr]">
        <div className="p-8 sm:p-10 lg:p-14">
          <p className="eyebrow text-accent">About NovaShop</p>
          <h2 className="mt-3 text-2xl font-semibold leading-snug tracking-display sm:text-3xl">
            A shop that runs on infrastructure worth reading about
          </h2>
          <p className="mt-5 text-sm leading-relaxed text-content-muted">
            The storefront is real: a catalogue in PostgreSQL, a cart in Redis, and
            orders written inside a transaction that re-checks stock before it
            commits. It is deliberately small, because the interesting part is
            underneath.
          </p>
          <p className="mt-3 text-sm leading-relaxed text-content-muted">
            Every deployment here arrives through GitOps, pinned to a commit whose
            images were scanned before they were published, past ninety-four
            checks that run before a merge is allowed.
          </p>

          <dl className="mt-8 grid grid-cols-2 gap-x-6 gap-y-5 sm:grid-cols-4">
            {FACTS.map((fact) => (
              <div key={fact.label}>
                <dt className="sr-only">{fact.label}</dt>
                <dd>
                  <span className="block text-2xl font-semibold tabular-nums tracking-display">
                    {fact.value}
                  </span>
                  <span className="mt-1 block text-xs leading-snug text-content-faint">
                    {fact.label}
                  </span>
                </dd>
              </div>
            ))}
          </dl>

          <div className="mt-9 flex flex-wrap gap-3">
            <Link href="/products" className="btn-primary">
              Browse products
            </Link>
            <a
              href="https://github.com/nguyenlpn2015/NovaShop"
              className="btn-secondary"
            >
              Read the source
            </a>
          </div>
        </div>

        {/* A gradient panel, not a photograph. banner-01.webp is one of the
            8KB near-black placeholders in public/img/brand -- as a half-width
            image it renders as a black slab. It is kept as a soft-light texture
            over accent colour, which is a panel that looks deliberate until
            real photography exists to replace it. */}
        <div
          className="relative min-h-64 lg:min-h-full"
          style={{
            backgroundImage:
              "linear-gradient(150deg, rgb(var(--accent) / 0.85), rgb(var(--accent-alt) / 0.7))",
          }}
        >
          <div
            className="absolute inset-0 bg-cover bg-center opacity-60 mix-blend-soft-light"
            style={{ backgroundImage: "url(/img/brand/banner-01.webp)" }}
          />
          {/* Fades the panel into the copy on the left instead of ending it at
              a hard vertical edge. Only on the wide layout, where the two
              actually sit side by side. */}
          <div className="absolute inset-0 hidden bg-gradient-to-r from-surface-raised via-surface-raised/20 to-transparent lg:block" />
        </div>
      </div>
    </section>
  );
}
