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
 * Shown while a server component fetches. Cards rather than a spinner: a
 * skeleton in the shape of the result reserves the layout, so the page does not
 * jump when data arrives.
 */
export default function Loading() {
  return (
    <div className="grid grid-cols-2 gap-4 md:grid-cols-3 lg:grid-cols-4">
      {Array.from({ length: 8 }, (_, index) => (
        <ProductCardSkeleton key={index} />
      ))}
    </div>
  );
}
