import Link from "next/link";

import { ProductCard } from "@/components/ProductCard";
import { searchProducts } from "@/lib/api";

export const dynamic = "force-dynamic";

export default async function SearchPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string }>;
}) {
  const { q } = await searchParams;
  const term = (q ?? "").trim();
  const results = term.length >= 2 ? await searchProducts(term.slice(0, 100)) : [];

  return (
    <div className="space-y-8">
      <div>
        <p className="eyebrow">Search</p>
        <h1 className="mt-2 text-3xl font-semibold tracking-display sm:text-4xl">
          {term ? <>Results for “{term}”</> : "Search the catalogue"}
        </h1>
        {results.length > 0 && (
          <p className="mt-2 text-sm text-content-muted">
            {results.length} match{results.length === 1 ? "" : "es"}
          </p>
        )}
      </div>

      {term.length < 2 && (
        <div className="card p-14 text-center">
          <p className="font-medium">Type at least two characters.</p>
          <p className="mt-1 text-sm text-content-muted">
            One letter matches most of the catalogue, which is not a search
            result — it is the catalogue.
          </p>
          <Link href="/products" className="btn-secondary mt-5">
            Browse everything
          </Link>
        </div>
      )}

      {term.length >= 2 && results.length === 0 && (
        <div className="card p-14 text-center">
          <p className="font-medium">Nothing matches “{term}”.</p>
          <Link href="/products" className="btn-primary mt-5">
            Browse everything instead
          </Link>
        </div>
      )}

      {results.length > 0 && (
        <div className="grid grid-cols-2 gap-4 md:grid-cols-3 lg:grid-cols-4">
          {results.map((product) => (
            <ProductCard key={product.id} product={product} />
          ))}
        </div>
      )}
    </div>
  );
}
