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
 * A deterministic hue for a product, derived from its slug.
 *
 * Deriving it from the slug rather than at random means the colour is stable
 * across renders and across environments -- the same product looks the same
 * everywhere, which matters when a screenshot from staging is meant to describe
 * production.
 */
export function slugHue(slug: string): number {
  let hash = 0;
  for (let index = 0; index < slug.length; index += 1) {
    hash = (hash * 31 + slug.charCodeAt(index)) % 360;
  }
  return hash;
}

/**
 * The hue each category's artwork is drawn in.
 *
 * Kept in step with PALETTES in scripts/generate-product-art.py. Deriving the
 * wash from the category rather than from the product slug is the difference
 * between a teal bag sitting in a teal glow and a teal bag sitting in a red one
 * -- a slug hash knows nothing about what colour the product it names is.
 */
const CATEGORY_HUE: Record<string, number> = {
  apparel: 239,
  footwear: 25,
  accessories: 173,
  electronics: 215,
  home: 292,
  outdoor: 142,
  stationery: 45,
  wellness: 350,
};

/**
 * The wash behind a product image.
 *
 * The artwork is transparent so that one file suits the light theme and the dark
 * one, which means whatever sits behind it is visible through it. This has to be
 * subtle for that reason: the previous value was an opaque, fully saturated
 * gradient, correct when it was hiding behind an opaque image and far too loud
 * once the image stopped covering it.
 *
 * Alpha rather than solid colour, so it tints whichever surface it is laid over
 * instead of replacing it -- the same declaration reads as a pale wash on the
 * light theme and a faint glow on the dark one. It is also where the glow moved
 * to when it came out of the SVG, where its alpha ramp cost 60KB a file.
 *
 * `categorySlug` is optional because the cart's line items do not carry one. The
 * slug hash is the fallback, which is wrong about hue but stable and never
 * absent.
 */
export function productTint(slug: string, categorySlug?: string): string {
  const base = categorySlug ? CATEGORY_HUE[categorySlug] : undefined;
  // A few degrees of drift per product, so sixteen tiles of one category are not
  // sixteen identical washes.
  const hue = base === undefined ? slugHue(slug) : (base + (slugHue(slug) % 18) - 9 + 360) % 360;
  return [
    `radial-gradient(115% 95% at 50% 38%,`,
    `hsl(${hue} 70% 55% / 0.16),`,
    `hsl(${(hue + 26) % 360} 62% 50% / 0.06) 58%,`,
    `transparent 76%)`,
  ].join(" ");
}
