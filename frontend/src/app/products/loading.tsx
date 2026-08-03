import { ProductCardSkeleton } from "@/components/ProductCard";

/**
 * Scoped to this route, not the application root.
 *
 * A `loading.tsx` at the root makes Next.js stream a shell for every dynamic
 * page as soon as the request arrives -- which commits the HTTP status line
 * before the page has fetched anything. `notFound()` in /products/[slug] then
 * rendered the 404 page with a **200** status: correct to a human, wrong to a
 * crawler, a monitor, or anything that reads the status code.
 */

/**
 * Shown while a server component fetches. It mirrors the real layout of this
 * route -- heading, filter rail, three-column grid -- because a skeleton in the
 * shape of the result reserves the space the result will need, so the page does
 * not jump when data arrives. A centred spinner reserves nothing.
 */
export default function Loading() {
  return (
    <div className="space-y-8">
      <div className="space-y-3">
        <div className="skeleton h-4 w-40 rounded" />
        <div className="skeleton h-9 w-64 rounded-lg" />
        <div className="skeleton h-4 w-24 rounded" />
      </div>

      <div className="grid gap-8 lg:grid-cols-[236px_1fr]">
        <div className="space-y-6">
          <div className="card space-y-2.5 p-4">
            <div className="skeleton h-3 w-20 rounded" />
            {Array.from({ length: 8 }, (_, index) => (
              <div key={index} className="skeleton h-6 w-full rounded-lg" />
            ))}
          </div>
          <div className="card space-y-2.5 p-4">
            <div className="skeleton h-3 w-24 rounded" />
            <div className="skeleton h-6 w-full rounded-lg" />
          </div>
        </div>

        <div>
          <div className="mb-6 flex items-center justify-between">
            <div className="skeleton h-4 w-28 rounded" />
            <div className="skeleton h-9 w-64 rounded-xl" />
          </div>
          <div className="grid grid-cols-2 gap-4 md:grid-cols-3">
            {Array.from({ length: 9 }, (_, index) => (
              <ProductCardSkeleton key={index} />
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}
