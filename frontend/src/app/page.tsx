import Link from "next/link";

import { ProductCard } from "@/components/ProductCard";
import { getCategories, getProducts } from "@/lib/api";

// Rendered per request. The backend already caches these responses in Redis
// with explicit TTLs, so a second cache here would mean two invalidation
// stories for one piece of data -- and Next.js's data cache writes to
// .next/cache, which does not exist under a read-only root filesystem.
export const dynamic = "force-dynamic";

export default async function Home() {
  const [categories, featured] = await Promise.all([
    getCategories(),
    getProducts(new URLSearchParams({ page_size: "8", sort: "newest" })),
  ]);

  return (
    <div className="space-y-12">
      <section
        className="card animate-fade-up overflow-hidden bg-gradient-to-br
                   from-accent/10 via-surface-raised to-surface-raised p-8 sm:p-12"
      >
        <p className="text-sm font-medium uppercase tracking-widest text-accent">
          Cloud-native commerce
        </p>
        <h1 className="mt-3 max-w-2xl text-3xl font-semibold leading-tight sm:text-4xl">
          A small shop, carried by a platform worth looking at.
        </h1>
        <p className="mt-4 max-w-xl text-content-muted">
          GitOps delivery, pre-merge guardrails, runbook-backed alerting and
          documented recovery — running on a single node.
        </p>
        <Link
          href="/products"
          className="mt-6 inline-flex rounded-lg bg-accent px-5 py-2.5 text-sm
                     font-medium text-accent-contrast transition hover:bg-accent-hover"
        >
          Browse products
        </Link>
      </section>

      <section>
        <h2 className="mb-4 text-sm font-medium uppercase tracking-wide text-content-muted">
          Categories
        </h2>
        <div className="flex flex-wrap gap-2">
          {categories.map((category) => (
            <Link
              key={category.id}
              href={`/products?category=${category.slug}`}
              className="rounded-full border border-edge bg-surface-raised px-4 py-1.5
                         text-sm transition hover:border-accent hover:text-accent"
            >
              {category.name}
              <span className="ml-1.5 text-content-faint">
                {category.product_count}
              </span>
            </Link>
          ))}
        </div>
      </section>

      <section>
        <div className="mb-4 flex items-baseline justify-between">
          <h2 className="text-sm font-medium uppercase tracking-wide text-content-muted">
            Newest
          </h2>
          <Link href="/products" className="text-sm text-accent hover:underline">
            All {featured.page.total} products →
          </Link>
        </div>
        <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
          {featured.items.map((product) => (
            <ProductCard key={product.id} product={product} />
          ))}
        </div>
      </section>
    </div>
  );
}
