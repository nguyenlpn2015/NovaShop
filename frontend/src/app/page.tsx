import { Hero } from "@/components/Hero";
import {
  CategoryTiles,
  EditorialBand,
  PromiseStrip,
  SectionHeading,
} from "@/components/Marketing";
import { ProductCard } from "@/components/ProductCard";
import { getCategories, getProducts } from "@/lib/api";

// Rendered per request. The backend already caches these responses in Redis
// with explicit TTLs, so a second cache here would mean two invalidation
// stories for one piece of data -- and Next.js's data cache writes to
// .next/cache, which does not exist under a read-only root filesystem.
export const dynamic = "force-dynamic";

export default async function Home() {
  // One round trip each, in parallel. Sequentially these would add their
  // latencies together for no reason: neither depends on the other.
  const [categories, newest, popular] = await Promise.all([
    getCategories(),
    getProducts(new URLSearchParams({ page_size: "8", sort: "newest" })),
    getProducts(new URLSearchParams({ page_size: "4", sort: "price_desc" })),
  ]);

  return (
    <div className="space-y-16 sm:space-y-20">
      <Hero />

      <PromiseStrip />

      <CategoryTiles categories={categories} />

      <section>
        <SectionHeading
          eyebrow="Just landed"
          title="New arrivals"
          body="The most recent additions across every category."
          action={{
            label: `All ${newest.page.total} products`,
            href: "/products",
          }}
        />
        <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
          {newest.items.map((product) => (
            <ProductCard key={product.id} product={product} />
          ))}
        </div>
      </section>

      <EditorialBand />

      <section>
        <SectionHeading
          eyebrow="The upper shelf"
          title="The considered end"
          body="Where the materials cost more and it shows."
          action={{ label: "Sort by price", href: "/products?sort=price_desc" }}
        />
        <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
          {popular.items.map((product) => (
            <ProductCard key={product.id} product={product} />
          ))}
        </div>
      </section>
    </div>
  );
}
