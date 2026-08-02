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
    <div className="space-y-6">
      <h1 className="text-xl font-semibold">
        {term ? <>Results for “{term}”</> : "Search"}
      </h1>

      {term.length < 2 && (
        <p className="text-content-muted">Type at least two characters.</p>
      )}

      {term.length >= 2 && results.length === 0 && (
        <div className="card p-10 text-center">
          <p className="font-medium">Nothing matches “{term}”.</p>
          <Link
            href="/products"
            className="mt-2 inline-block text-sm text-accent hover:underline"
          >
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
