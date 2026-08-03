/**
 * The NovaShop mark, inline.
 *
 * The header used to load this as a 28px WebP. Inline SVG instead, for three
 * reasons: it is crisp at any size and on any display density, it costs no HTTP
 * request on the critical path, and its geometry is the same geometry
 * `scripts/generate-product-art.py` writes to `logo.webp` -- so the favicon and
 * the header cannot drift apart.
 *
 * `logo.webp` still exists and is still generated. A favicon and an Open Graph
 * image both have to be raster files, and neither can be a React component.
 */
export function Logo({ className = "h-8 w-8" }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 64 64"
      className={className}
      role="img"
      aria-label="NovaShop"
    >
      <defs>
        {/* Scoped by a stable id. Two of these on one page -- the header and the
            footer both render one -- must not fight over the definition. */}
        <linearGradient id="novashop-plate" x1="0" y1="0" x2="0.85" y2="1">
          <stop offset="0%" stopColor="#818cf8" />
          <stop offset="52%" stopColor="#6366f1" />
          <stop offset="100%" stopColor="#0ea5e9" />
        </linearGradient>
        <linearGradient id="novashop-gloss" x1="0" y1="0" x2="0.4" y2="1">
          <stop offset="0%" stopColor="#ffffff" stopOpacity="0.34" />
          <stop offset="60%" stopColor="#ffffff" stopOpacity="0" />
        </linearGradient>
      </defs>

      <rect width="64" height="64" rx="17" fill="url(#novashop-plate)" />
      <rect width="64" height="64" rx="17" fill="url(#novashop-gloss)" />

      {/* An N whose diagonal keeps rising past the top-right and ends in a star.
          The diagonal doubles as a chart line, which is the only nod to what
          this project actually is. One path, so the renderer mitres the joins
          rather than three overlapping strokes doing it by accident. */}
      <path
        d="M19 47 L19 19 L45 43 L45 20"
        stroke="#ffffff"
        strokeWidth="5.5"
        strokeLinecap="round"
        strokeLinejoin="round"
        fill="none"
      />
      <circle cx="45" cy="17" r="4.6" fill="#ffffff" />

      <rect
        x="0.75"
        y="0.75"
        width="62.5"
        height="62.5"
        rx="16.4"
        fill="none"
        stroke="#ffffff"
        strokeOpacity="0.22"
        strokeWidth="1.5"
      />
    </svg>
  );
}
