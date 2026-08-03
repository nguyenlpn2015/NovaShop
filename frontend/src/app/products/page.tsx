import Link from "next/link";

import { ProductCard } from "@/components/ProductCard";
import { getCategories, getProducts } from "@/lib/api";

export const dynamic = "force-dynamic";

const SORTS = [
  { value: "newest", label: "Newest" },
  { value: "price_asc", label: "Price ↑" },
  { value: "price_desc", label: "Price ↓" },
  { value: "name", label: "Name" },
];

type Search = Promise<Record<string, string | string[] | undefined>>;

function one(value: string | string[] | undefined): string | undefined {
  return Array.isArray(value) ? value[0] : value;
}

/** Rebuild the query string with one parameter changed, preserving the rest. */
function withParam(
  current: Record<string, string | undefined>,
  key: string,
  value: string | undefined,
): string {
  const params = new URLSearchParams();
  for (const [name, existing] of Object.entries(current)) {
    if (existing) params.set(name, existing);
  }
  if (value) params.set(key, value);
  else params.delete(key);
  // Changing a filter must return to page one. Keeping the page number means
  // narrowing a filter can land on a page that no longer exists, and the grid
  // renders empty on a catalogue that has results.
  if (key !== "page") params.delete("page");
  return `/products?${params.toString()}`;
}

export default async function ProductsPage({
  searchParams,
}: {
  searchParams: Search;
}) {
  const resolved = await searchParams;
  const current = {
    category: one(resolved.category),
    sort: one(resolved.sort) ?? "newest",
    in_stock: one(resolved.in_stock),
    page: one(resolved.page) ?? "1",
  };

  const query = new URLSearchParams({ page: current.page, sort: current.sort });
  if (current.category) query.set("category", current.category);
  if (current.in_stock) query.set("in_stock", "true");

  const [categories, products] = await Promise.all([
    getCategories(),
    getProducts(query),
  ]);

  const { page } = products;
  const pageNumbers = Array.from({ length: page.pages }, (_, index) => index + 1)
    .filter(
      (number) =>
        number === 1 ||
        number === page.pages ||
        Math.abs(number - page.page) <= 1,
    )
    .filter((number, index, all) => all.indexOf(number) === index);

  const activeCategory = categories.find(
    (category) => category.slug === current.category,
  );

  return (
    <div className="space-y-8">
      <div>
        <nav className="flex items-center gap-2 text-sm text-content-muted">
          <Link href="/" className="transition hover:text-content">
            Home
          </Link>
          <span aria-hidden className="text-content-faint">
            /
          </span>
          <span className="text-content">
            {activeCategory ? activeCategory.name : "All products"}
          </span>
        </nav>
        <h1 className="mt-3 text-3xl font-semibold tracking-display sm:text-4xl">
          {activeCategory ? activeCategory.name : "All products"}
        </h1>
        <p className="mt-2 text-sm text-content-muted">
          {page.total} result{page.total === 1 ? "" : "s"}
          {current.in_stock && " · in stock only"}
        </p>
      </div>

      <div className="grid gap-8 lg:grid-cols-[236px_1fr]">
        <aside className="space-y-6 lg:sticky lg:top-24 lg:h-fit">
          <div className="card p-4">
            <h2 className="eyebrow">Category</h2>
            <ul className="mt-3 space-y-0.5 text-sm">
              <li>
                <Link
                  href={withParam(current, "category", undefined)}
                  aria-current={current.category ? undefined : "true"}
                  className={`block rounded-lg px-2.5 py-1.5 transition ${
                    current.category
                      ? "text-content-muted hover:bg-surface-sunken hover:text-content"
                      : "bg-accent/10 font-medium text-accent"
                  }`}
                >
                  All
                </Link>
              </li>
              {categories.map((category) => (
                <li key={category.id}>
                  <Link
                    href={withParam(current, "category", category.slug)}
                    aria-current={
                      current.category === category.slug ? "true" : undefined
                    }
                    className={`flex items-center justify-between gap-2 rounded-lg
                                px-2.5 py-1.5 transition ${
                                  current.category === category.slug
                                    ? "bg-accent/10 font-medium text-accent"
                                    : "text-content-muted hover:bg-surface-sunken hover:text-content"
                                }`}
                  >
                    <span className="truncate">{category.name}</span>
                    <span className="shrink-0 text-xs tabular-nums text-content-faint">
                      {category.product_count}
                    </span>
                  </Link>
                </li>
              ))}
            </ul>
          </div>

          <div className="card p-4">
            <h2 className="eyebrow">Availability</h2>
            {/* A link styled as a checkbox rather than a real one. The filter
                state lives in the URL, so it has to be navigable and shareable;
                a form control would need JavaScript to do the same thing. */}
            <Link
              href={withParam(current, "in_stock", current.in_stock ? undefined : "true")}
              className={`mt-3 flex items-center gap-2.5 rounded-lg px-2.5 py-1.5
                          text-sm transition ${
                            current.in_stock
                              ? "bg-accent/10 font-medium text-accent"
                              : "text-content-muted hover:bg-surface-sunken hover:text-content"
                          }`}
            >
              <span
                aria-hidden
                className={`flex h-4 w-4 shrink-0 items-center justify-center rounded
                            border text-[10px] font-bold ${
                              current.in_stock
                                ? "border-accent bg-accent text-accent-contrast"
                                : "border-edge"
                            }`}
              >
                {current.in_stock ? "✓" : ""}
              </span>
              In stock only
            </Link>
          </div>
        </aside>

        <section>
          <div className="mb-6 flex flex-wrap items-center justify-between gap-3">
            <p className="text-sm text-content-muted">
              Page {page.page} of {page.pages || 1}
            </p>
            {/* A segmented control: one bordered group rather than four loose
                pills, so the four options read as a single choice. */}
            <div
              role="group"
              aria-label="Sort"
              className="flex flex-wrap gap-1 rounded-xl border border-edge
                         bg-surface-raised p-1"
            >
              {SORTS.map((option) => (
                <Link
                  key={option.value}
                  href={withParam(current, "sort", option.value)}
                  aria-current={current.sort === option.value ? "true" : undefined}
                  className={`rounded-lg px-3 py-1.5 text-xs font-medium transition ${
                    current.sort === option.value
                      ? "bg-accent text-accent-contrast"
                      : "text-content-muted hover:bg-surface-sunken hover:text-content"
                  }`}
                >
                  {option.label}
                </Link>
              ))}
            </div>
          </div>

          {products.items.length === 0 ? (
            <div className="card p-14 text-center">
              <p className="font-medium">Nothing matches those filters.</p>
              <p className="mt-1 text-sm text-content-muted">
                The catalogue has {categories.reduce((sum, c) => sum + c.product_count, 0)}{" "}
                products in total.
              </p>
              <Link href="/products" className="btn-primary mt-5">
                Clear the filters
              </Link>
            </div>
          ) : (
            <div className="grid grid-cols-2 gap-4 md:grid-cols-3">
              {products.items.map((product) => (
                <ProductCard key={product.id} product={product} />
              ))}
            </div>
          )}

          {page.pages > 1 && (
            <nav
              aria-label="Pagination"
              className="mt-10 flex items-center justify-center gap-1.5"
            >
              {page.page > 1 && (
                <Link
                  href={withParam(current, "page", String(page.page - 1))}
                  aria-label="Previous page"
                  className="flex h-9 w-9 items-center justify-center rounded-lg border
                             border-edge text-sm transition hover:border-accent/50
                             hover:text-accent"
                >
                  ←
                </Link>
              )}
              {pageNumbers.map((number, index) => (
                <span key={number} className="flex items-center gap-1.5">
                  {index > 0 && number - pageNumbers[index - 1] > 1 && (
                    <span className="px-1 text-content-faint">…</span>
                  )}
                  <Link
                    href={withParam(current, "page", String(number))}
                    aria-current={number === page.page ? "page" : undefined}
                    className={`flex h-9 min-w-9 items-center justify-center rounded-lg
                                border px-2 text-sm tabular-nums transition ${
                                  number === page.page
                                    ? "border-accent bg-accent font-medium text-accent-contrast"
                                    : "border-edge hover:border-accent/50 hover:text-accent"
                                }`}
                  >
                    {number}
                  </Link>
                </span>
              ))}
              {page.page < page.pages && (
                <Link
                  href={withParam(current, "page", String(page.page + 1))}
                  aria-label="Next page"
                  className="flex h-9 w-9 items-center justify-center rounded-lg border
                             border-edge text-sm transition hover:border-accent/50
                             hover:text-accent"
                >
                  →
                </Link>
              )}
            </nav>
          )}
        </section>
      </div>
    </div>
  );
}
