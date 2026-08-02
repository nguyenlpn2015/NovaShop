/**
 * Money arrives as integer cents and is formatted here, in the browser's
 * locale. The backend deliberately does not format currency: it cannot know
 * who is reading.
 */
export function formatPrice(cents: number): string {
  return new Intl.NumberFormat("vi-VN", {
    style: "currency",
    currency: "VND",
    maximumFractionDigits: 0,
  }).format(cents);
}

/**
 * A deterministic pair of hues for a product, derived from its slug.
 *
 * Every product has a real image, but this is the placeholder shown while that
 * image loads and the fallback if it fails. Deriving it from the slug rather
 * than at random means the colour is stable across renders and across
 * environments -- the same product looks the same everywhere, which matters
 * when a screenshot from staging is meant to describe production.
 */
export function slugHue(slug: string): number {
  let hash = 0;
  for (let index = 0; index < slug.length; index += 1) {
    hash = (hash * 31 + slug.charCodeAt(index)) % 360;
  }
  return hash;
}
