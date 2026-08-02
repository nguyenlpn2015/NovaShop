#!/usr/bin/env python3
"""Generate the catalogue's product artwork, the logo, and the hero banners.

Every image in this repository is drawn here rather than downloaded. Stock
photography would need a licence audit for a public repository, and a CDN would
put an internet dependency in the middle of a page render -- so the artwork is
flat vector illustration, generated deterministically and committed.

Deterministic matters more than it sounds. The same product renders identically
in development, staging and production, so a screenshot taken in one environment
describes the others. Nothing here uses `random`.

Requires ImageMagick with SVG support. Run through a container:

    docker run --rm -v "$PWD:/repo" -w /repo --entrypoint sh dpokidov/imagemagick \\
        -c "apk add --no-cache python3 >/dev/null && python3 scripts/generate-product-art.py"
"""

from __future__ import annotations

import sys
from pathlib import Path

OUT = Path("frontend/public/img")
SIZE = 900

# Eight palettes, one per category. Ordered so adjacent categories in the
# navigation do not sit next to a near-identical hue.
PALETTES: dict[str, tuple[str, str, str, str]] = {
    #                 backdrop   backdrop2  product    accent
    "apparel": ("#eef2ff", "#e0e7ff", "#4f46e5", "#312e81"),
    "footwear": ("#fff7ed", "#ffedd5", "#ea580c", "#7c2d12"),
    "accessories": ("#f0fdfa", "#ccfbf1", "#0d9488", "#134e4a"),
    "electronics": ("#f1f5f9", "#e2e8f0", "#334155", "#0f172a"),
    "home": ("#fdf4ff", "#fae8ff", "#a21caf", "#581c87"),
    "outdoor": ("#f0fdf4", "#dcfce7", "#16a34a", "#14532d"),
    "stationery": ("#fefce8", "#fef9c3", "#ca8a04", "#713f12"),
    "wellness": ("#fef2f2", "#fee2e2", "#e11d48", "#881337"),
}

# Product silhouettes, drawn in a 0-100 coordinate space and scaled at render
# time. Deliberately simple: a recognisable shape reads better at 200px in a
# grid than a detailed one, and these are illustrations, not photographs.
SHAPES: dict[str, str] = {
    "apparel": """
      <path d="M32 26 L44 20 Q50 26 56 20 L68 26 L74 42 L64 46 L64 80 L36 80 L36 46 L26 42 Z"
            fill="{product}"/>
      <path d="M44 20 Q50 30 56 20 L52 20 Q50 24 48 20 Z" fill="{accent}"/>
      <rect x="36" y="60" width="28" height="2.5" fill="{accent}" opacity="0.35"/>
    """,
    "footwear": """
      <path d="M22 62 L22 52 Q34 50 40 44 L48 50 Q58 54 70 54 Q78 55 78 62 L78 68 L22 68 Z"
            fill="{product}"/>
      <rect x="20" y="66" width="60" height="6" rx="3" fill="{accent}"/>
      <path d="M40 46 L46 52 M46 44 L52 50 M52 42 L58 48" stroke="{accent}"
            stroke-width="2" stroke-linecap="round" fill="none" opacity="0.5"/>
    """,
    "accessories": """
      <path d="M30 38 L70 38 L74 78 L26 78 Z" fill="{product}"/>
      <path d="M40 38 Q40 22 50 22 Q60 22 60 38" stroke="{accent}" stroke-width="4"
            fill="none" stroke-linecap="round"/>
      <rect x="44" y="52" width="12" height="9" rx="2" fill="{accent}" opacity="0.6"/>
    """,
    "electronics": """
      <rect x="24" y="34" width="52" height="34" rx="5" fill="{product}"/>
      <rect x="30" y="40" width="40" height="22" rx="2" fill="{accent}" opacity="0.45"/>
      <rect x="40" y="72" width="20" height="4" rx="2" fill="{accent}"/>
      <circle cx="50" cy="51" r="5" fill="{backdrop}" opacity="0.8"/>
    """,
    "home": """
      <path d="M34 34 L66 34 L62 78 L38 78 Z" fill="{product}"/>
      <path d="M66 42 Q80 46 80 55 Q80 64 64 66" stroke="{accent}" stroke-width="5"
            fill="none" stroke-linecap="round"/>
      <ellipse cx="50" cy="34" rx="16" ry="4" fill="{accent}" opacity="0.5"/>
    """,
    "outdoor": """
      <rect x="38" y="30" width="24" height="50" rx="7" fill="{product}"/>
      <rect x="44" y="20" width="12" height="12" rx="3" fill="{accent}"/>
      <rect x="38" y="48" width="24" height="8" fill="{accent}" opacity="0.4"/>
    """,
    "stationery": """
      <rect x="30" y="24" width="40" height="54" rx="3" fill="{product}"/>
      <rect x="30" y="24" width="8" height="54" fill="{accent}"/>
      <rect x="44" y="38" width="20" height="2.5" fill="{backdrop}" opacity="0.85"/>
      <rect x="44" y="46" width="20" height="2.5" fill="{backdrop}" opacity="0.85"/>
      <rect x="44" y="54" width="14" height="2.5" fill="{backdrop}" opacity="0.85"/>
    """,
    "wellness": """
      <rect x="40" y="34" width="20" height="46" rx="8" fill="{product}"/>
      <rect x="44" y="24" width="12" height="12" rx="3" fill="{accent}"/>
      <path d="M44 52 Q50 46 56 52 Q50 58 44 52 Z" fill="{backdrop}" opacity="0.85"/>
    """,
}

# Eight variants per category. Each rotates the composition slightly and shifts
# the backdrop, so a grid of one category does not look like the same image
# repeated -- which is what the previous gradient placeholders looked like.
VARIANTS = [
    (0, 1.00, 0.00),
    (-6, 0.94, 0.06),
    (5, 1.06, 0.12),
    (-3, 0.98, 0.18),
    (8, 0.92, 0.24),
    (-8, 1.04, 0.30),
    (3, 0.96, 0.36),
    (-5, 1.02, 0.42),
]


def mix(a: str, b: str, ratio: float) -> str:
    """Blend two hex colours. Used to vary the backdrop per variant."""
    pa = [int(a[i : i + 2], 16) for i in (1, 3, 5)]
    pb = [int(b[i : i + 2], 16) for i in (1, 3, 5)]
    return "#" + "".join(f"{round(x + (y - x) * ratio):02x}" for x, y in zip(pa, pb))


def product_svg(category: str, index: int) -> str:
    backdrop, backdrop2, product, accent = PALETTES[category]
    rotation, scale, shift = VARIANTS[index]
    top = mix(backdrop, backdrop2, shift)
    bottom = mix(backdrop2, accent, shift * 0.22)
    shape = SHAPES[category].format(product=product, accent=accent, backdrop=backdrop)

    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{SIZE}" height="{SIZE}"
     viewBox="0 0 100 100">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0.6" y2="1">
      <stop offset="0%" stop-color="{top}"/>
      <stop offset="100%" stop-color="{bottom}"/>
    </linearGradient>
    <radialGradient id="pool" cx="0.5" cy="0.82" r="0.45">
      <stop offset="0%" stop-color="{accent}" stop-opacity="0.18"/>
      <stop offset="100%" stop-color="{accent}" stop-opacity="0"/>
    </radialGradient>
  </defs>
  <rect width="100" height="100" fill="url(#bg)"/>
  <!-- A soft pool under the product reads as a studio floor and stops the
       silhouette from floating. -->
  <ellipse cx="50" cy="82" rx="30" ry="7" fill="url(#pool)"/>
  <g transform="rotate({rotation} 50 52) translate(50 52) scale({scale}) translate(-50 -52)">
    {shape}
  </g>
</svg>
"""


LOGO = """<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 64 64">
  <defs>
    <linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="#6366f1"/>
      <stop offset="100%" stop-color="#0ea5e9"/>
    </linearGradient>
  </defs>
  <rect width="64" height="64" rx="14" fill="url(#g)"/>
  <!-- An N drawn as a rising path: the diagonal doubles as a chart line, which
       is the only nod to what this project actually is. -->
  <path d="M18 46 L18 18 L46 46 L46 18" stroke="#ffffff" stroke-width="6"
        stroke-linecap="round" stroke-linejoin="round" fill="none"/>
  <circle cx="46" cy="18" r="4.5" fill="#ffffff"/>
</svg>
"""


def banner_svg(index: int) -> str:
    """Wide hero artwork. Abstract on purpose -- text is rendered by the page,
    not baked into an image nobody can translate or restyle."""
    schemes = [
        ("#4f46e5", "#0ea5e9", "#c7d2fe"),
        ("#0d9488", "#22c55e", "#ccfbf1"),
        ("#ea580c", "#f59e0b", "#fed7aa"),
    ]
    a, b, light = schemes[index]
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="1600" height="700"
     viewBox="0 0 160 70">
  <defs>
    <linearGradient id="b" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="{a}"/>
      <stop offset="100%" stop-color="{b}"/>
    </linearGradient>
  </defs>
  <rect width="160" height="70" fill="url(#b)"/>
  <g fill="{light}" opacity="0.16">
    <circle cx="132" cy="16" r="26"/>
    <circle cx="18" cy="60" r="20"/>
  </g>
  <g stroke="{light}" stroke-width="0.5" opacity="0.35" fill="none">
    <path d="M0 52 Q40 34 80 44 T160 30"/>
    <path d="M0 60 Q40 44 80 52 T160 40"/>
  </g>
</svg>
"""


def render(svg: str, destination: Path, quality: int = 82) -> None:
    """Write the SVG next to where the WebP will go.

    Conversion is a separate step run in a container: the ImageMagick image has
    no Python, and a machine with Python often has no ImageMagick. Splitting
    them means neither has to be installed alongside the other.
    """
    del quality  # applied by the conversion step
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.with_suffix(".svg").write_text(svg, encoding="utf-8")


def main() -> int:
    if not Path("frontend/public").is_dir():
        print("Run from the repository root.", file=sys.stderr)
        return 1

    count = 0
    for category in PALETTES:
        for index in range(8):
            render(
                product_svg(category, index),
                OUT / "products" / f"{category}-{index:02d}.webp",
            )
            count += 1

    render(LOGO, OUT / "brand" / "logo.webp", quality=90)
    for index in range(3):
        render(banner_svg(index), OUT / "brand" / f"banner-{index:02d}.webp", quality=78)

    print(f"{count} product SVGs, 1 logo, 3 banners written; now run the conversion step")
    return 0


if __name__ == "__main__":
    sys.exit(main())
