import Link from "next/link";

import { ProductCard } from "@/components/ProductCard";
import { getCategories, getProducts } from "@/lib/api";

export const dynamic = "force-dynamic";

const SORTS = [
  { value: "newest", label: "Newest" },
  { value: "price_asc", label: "Price, low to high" },
  { value: "price_desc", label: "Price, high to low" },
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

  return (
    <div className="grid gap-8 lg:grid-cols-[220px_1fr]">
      <aside className="space-y-6">
        <div>
          <h2 className="mb-3 text-xs font-semibold uppercase tracking-wide text-content-muted">
            Category
          </h2>
          <ul className="space-y-1 text-sm">
            <li>
              <Link
                href={withParam(current, "category", undefined)}
                className={`block rounded-md px-2 py-1 ${
                  current.category
                    ? "text-content-muted hover:bg-surface-sunken"
                    : "bg-surface-sunken font-medium text-accent"
                }`}
              >
                All
              </Link>
            </li>
            {categories.map((category) => (
              <li key={category.id}>
                <Link
                  href={withParam(current, "category", category.slug)}
                  className={`flex items-center justify-between rounded-md px-2 py-1 ${
                    current.category === category.slug
                      ? "bg-surface-sunken font-medium text-accent"
                      : "text-content-muted hover:bg-surface-sunken"
                  }`}
                >
                  {category.name}
                  <span className="text-content-faint">{category.product_count}</span>
                </Link>
              </li>
            ))}
          </ul>
        </div>

        <div>
          <h2 className="mb-3 text-xs font-semibold uppercase tracking-wide text-content-muted">
            Availability
          </h2>
          <Link
            href={withParam(current, "in_stock", current.in_stock ? undefined : "true")}
            className={`inline-flex items-center gap-2 rounded-md px-2 py-1 text-sm ${
              current.in_stock
                ? "bg-surface-sunken font-medium text-accent"
                : "text-content-muted hover:bg-surface-sunken"
            }`}
          >
            <span
              aria-hidden
              className={`h-3.5 w-3.5 rounded border ${
                current.in_stock ? "border-accent bg-accent" : "border-edge"
              }`}
            />
            In stock only
          </Link>
        </div>
      </aside>

      <section>
        <div className="mb-5 flex flex-wrap items-center justify-between gap-3">
          <h1 className="text-xl font-semibold">
            Products
            <span className="ml-2 text-sm font-normal text-content-muted">
              {page.total} result{page.total === 1 ? "" : "s"}
            </span>
          </h1>
          <div className="flex flex-wrap gap-1.5">
            {SORTS.map((option) => (
              <Link
                key={option.value}
                href={withParam(current, "sort", option.value)}
                className={`rounded-md border px-2.5 py-1 text-xs transition ${
                  current.sort === option.value
                    ? "border-accent text-accent"
                    : "border-edge text-content-muted hover:text-content"
                }`}
              >
                {option.label}
              </Link>
            ))}
          </div>
        </div>

        {products.items.length === 0 ? (
          <div className="card p-10 text-center">
            <p className="font-medium">Nothing matches those filters.</p>
            <Link
              href="/products"
              className="mt-2 inline-block text-sm text-accent hover:underline"
            >
              Clear them
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
          <nav className="mt-8 flex items-center justify-center gap-1.5">
            {page.page > 1 && (
              <Link
                href={withParam(current, "page", String(page.page - 1))}
                className="rounded-md border border-edge px-3 py-1.5 text-sm
                           hover:border-accent hover:text-accent"
              >
                ←
              </Link>
            )}
            {pageNumbers.map((number, index) => (
              <span key={number} className="flex items-center gap-1.5">
                {index > 0 && number - pageNumbers[index - 1] > 1 && (
                  <span className="text-content-faint">…</span>
                )}
                <Link
                  href={withParam(current, "page", String(number))}
                  className={`rounded-md border px-3 py-1.5 text-sm ${
                    number === page.page
                      ? "border-accent bg-accent text-accent-contrast"
                      : "border-edge hover:border-accent hover:text-accent"
                  }`}
                >
                  {number}
                </Link>
              </span>
            ))}
            {page.page < page.pages && (
              <Link
                href={withParam(current, "page", String(page.page + 1))}
                className="rounded-md border border-edge px-3 py-1.5 text-sm
                           hover:border-accent hover:text-accent"
              >
                →
              </Link>
            )}
          </nav>
        )}
      </section>
    </div>
  );
}
