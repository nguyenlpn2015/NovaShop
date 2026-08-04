#!/usr/bin/env python3
"""Generate the catalogue's product artwork, the logo, and the hero banners.

Every image in this repository is drawn here rather than downloaded. Stock
photography would need a licence audit for a public repository, and a CDN would
put an internet dependency in the middle of a page render -- so the artwork is
vector illustration, generated deterministically and committed. The catalogue is
fictional besides: there is no real photograph of a "Fathom Carafe", and a stock
photograph of some other carafe labelled as one would be the only dishonest
thing on the page.

Deterministic matters more than it sounds. The same product renders identically
in development, staging and production, so a screenshot taken in one environment
describes the others. Nothing here uses `random`.

Two properties of the output are load-bearing:

**Transparent backgrounds.** The storefront has a light theme and a dark one.
Art baked onto an opaque backdrop can only suit one of them -- an off-white tile
glares on the dark theme, a near-black tile blocks out the light one. These draw
the product and a soft tinted spotlight over transparency, so the card surface
shows through and the same file suits both.

**Nothing near-black and nothing near-white.** Every product body sits in the
mid range, so the silhouette holds its edge against either theme's card.

This script writes SVGs and a manifest. `scripts/convert-art.mjs` rasterises
them; run it second. They are separate because the conversion needs a browser
and this needs Python, and requiring both in one image helps nobody:

    python3 scripts/generate-product-art.py
    node scripts/convert-art.mjs
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

BUILD = Path(".art-build")
OUT = Path("frontend/public/img")

# 640, not 900. The largest a product image is ever displayed is the detail
# page, at roughly 590 CSS pixels; in the grid it is about 355. Generating at
# 900 spent 232KB per file -- 15MB across the catalogue -- to carry detail no
# layout asks for. Flat vector art has no fine texture that survives
# downscaling, so the extra pixels were pure weight.
SIZE = 640

# Eight palettes, one per category, ordered so adjacent categories in the
# navigation do not sit next to a near-identical hue.
#
# `tint` lights the backdrop. `light` and `body` are the two stops of the
# product's gradient -- both mid-tone, so the shape reads on a white card and on
# a near-black one. `accent` is for detail, and is the only dark value here.
PALETTES: dict[str, tuple[str, str, str, str]] = {
    #                  tint       light      body       accent
    "apparel": ("#6366f1", "#818cf8", "#4f46e5", "#312e81"),
    "footwear": ("#f97316", "#fb923c", "#ea580c", "#7c2d12"),
    "accessories": ("#14b8a6", "#2dd4bf", "#0d9488", "#134e4a"),
    "electronics": ("#64748b", "#94a3b8", "#475569", "#1e293b"),
    "home": ("#d946ef", "#e879f9", "#a21caf", "#581c87"),
    "outdoor": ("#22c55e", "#4ade80", "#16a34a", "#14532d"),
    "stationery": ("#eab308", "#facc15", "#ca8a04", "#713f12"),
    "wellness": ("#f43f5e", "#fb7185", "#e11d48", "#881337"),
}

# Product silhouettes in a 0-100 space, scaled at render time. Deliberately
# simple: a recognisable shape reads better at 200px in a grid than a detailed
# one. `body` is the gradient, so each shape gains depth without a per-shape
# lighting model; `sheen` is the highlight that suggests a light source above
# left, and it is the difference between a flat sticker and an object.
SHAPES: dict[str, str] = {
    "apparel": """
      <path d="M32 26 L44 20 Q50 26 56 20 L68 26 L74 42 L64 46 L64 80 L36 80 L36 46 L26 42 Z"
            fill="url(#body)"/>
      <path d="M32 26 L44 20 Q50 26 56 20 L68 26 L74 42 L64 46 L64 80 L36 80 L36 46 L26 42 Z"
            fill="url(#sheen)"/>
      <path d="M44 20 Q50 30 56 20 L52 20 Q50 24 48 20 Z" fill="{accent}"/>
      <rect x="36" y="60" width="28" height="2.5" rx="1.2" fill="{accent}" opacity="0.32"/>
    """,
    "footwear": """
      <path d="M22 62 L22 52 Q34 50 40 44 L48 50 Q58 54 70 54 Q78 55 78 62 L78 68 L22 68 Z"
            fill="url(#body)"/>
      <path d="M22 62 L22 52 Q34 50 40 44 L48 50 Q58 54 70 54 Q78 55 78 62 L78 68 L22 68 Z"
            fill="url(#sheen)"/>
      <rect x="20" y="66" width="60" height="6" rx="3" fill="{accent}"/>
      <path d="M40 46 L46 52 M46 44 L52 50 M52 42 L58 48" stroke="{accent}"
            stroke-width="2" stroke-linecap="round" fill="none" opacity="0.55"/>
    """,
    "accessories": """
      <path d="M30 38 L70 38 L74 78 Q74 80 72 80 L28 80 Q26 80 26 78 Z" fill="url(#body)"/>
      <path d="M30 38 L70 38 L74 78 Q74 80 72 80 L28 80 Q26 80 26 78 Z" fill="url(#sheen)"/>
      <path d="M40 38 Q40 22 50 22 Q60 22 60 38" stroke="{accent}" stroke-width="4"
            fill="none" stroke-linecap="round"/>
      <rect x="44" y="52" width="12" height="9" rx="2.5" fill="{accent}" opacity="0.55"/>
    """,
    "electronics": """
      <rect x="24" y="34" width="52" height="34" rx="5" fill="url(#body)"/>
      <rect x="24" y="34" width="52" height="34" rx="5" fill="url(#sheen)"/>
      <rect x="29" y="39" width="42" height="24" rx="2.5" fill="{accent}" opacity="0.55"/>
      <rect x="40" y="72" width="20" height="4" rx="2" fill="{accent}"/>
      <circle cx="50" cy="51" r="5.5" fill="{light}"/>
      <circle cx="50" cy="51" r="2.4" fill="{accent}" opacity="0.7"/>
    """,
    "home": """
      <path d="M34 34 L66 34 L62 78 Q62 80 60 80 L40 80 Q38 80 38 78 Z" fill="url(#body)"/>
      <path d="M34 34 L66 34 L62 78 Q62 80 60 80 L40 80 Q38 80 38 78 Z" fill="url(#sheen)"/>
      <path d="M66 42 Q80 46 80 55 Q80 64 64 66" stroke="{accent}" stroke-width="5"
            fill="none" stroke-linecap="round"/>
      <ellipse cx="50" cy="34" rx="16" ry="4" fill="{light}"/>
      <ellipse cx="50" cy="34" rx="11" ry="2.4" fill="{accent}" opacity="0.45"/>
    """,
    "outdoor": """
      <rect x="38" y="30" width="24" height="50" rx="7" fill="url(#body)"/>
      <rect x="38" y="30" width="24" height="50" rx="7" fill="url(#sheen)"/>
      <rect x="44" y="19" width="12" height="12" rx="3.5" fill="{accent}"/>
      <rect x="38" y="48" width="24" height="8" fill="{accent}" opacity="0.42"/>
      <rect x="41.5" y="34" width="3" height="10" rx="1.5" fill="{light}" opacity="0.7"/>
    """,
    "stationery": """
      <rect x="30" y="24" width="40" height="56" rx="3.5" fill="url(#body)"/>
      <rect x="30" y="24" width="40" height="56" rx="3.5" fill="url(#sheen)"/>
      <path d="M30 27.5 A3.5 3.5 0 0 1 33.5 24 L38 24 L38 80 L33.5 80
               A3.5 3.5 0 0 1 30 76.5 Z" fill="{accent}"/>
      <rect x="44" y="38" width="20" height="2.5" rx="1.2" fill="{light}" opacity="0.95"/>
      <rect x="44" y="46" width="20" height="2.5" rx="1.2" fill="{light}" opacity="0.95"/>
      <rect x="44" y="54" width="13" height="2.5" rx="1.2" fill="{light}" opacity="0.95"/>
    """,
    "wellness": """
      <rect x="40" y="34" width="20" height="46" rx="8" fill="url(#body)"/>
      <rect x="40" y="34" width="20" height="46" rx="8" fill="url(#sheen)"/>
      <rect x="44" y="23" width="12" height="12" rx="3.5" fill="{accent}"/>
      <path d="M44 52 Q50 45.5 56 52 Q50 58.5 44 52 Z" fill="{light}" opacity="0.95"/>
    """,
}

# Eight variants per category: rotation, scale, and a small offset. A grid of
# one category is sixteen tiles, and without this it reads as one image repeated
# sixteen times. The offsets stay under 4 units so nothing crops at the edge.
VARIANTS = [
    (0, 1.00, 0.0, 0.0),
    (-6, 0.94, -2.5, 1.5),
    (5, 1.06, 2.0, -1.0),
    (-3, 0.98, -1.5, -2.0),
    (8, 0.92, 3.0, 1.0),
    (-8, 1.04, -3.0, -1.5),
    (3, 0.96, 1.5, 2.0),
    (-5, 1.02, -1.0, -2.5),
]


def product_svg(category: str, index: int) -> str:
    _tint, light, body, accent = PALETTES[category]
    rotation, scale, offset_x, offset_y = VARIANTS[index]
    shape = SHAPES[category].format(light=light, accent=accent)

    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{SIZE}" height="{SIZE}"
     viewBox="0 0 100 100">
  <defs>
    <linearGradient id="body" x1="0.1" y1="0" x2="0.5" y2="1">
      <stop offset="0%" stop-color="{light}"/>
      <stop offset="100%" stop-color="{body}"/>
    </linearGradient>
    <!-- The highlight. White at a low alpha, fading out by the middle, so it
         lifts the top-left of the form and leaves the rest to the gradient. -->
    <linearGradient id="sheen" x1="0" y1="0" x2="0.45" y2="1">
      <stop offset="0%" stop-color="#ffffff" stop-opacity="0.30"/>
      <stop offset="55%" stop-color="#ffffff" stop-opacity="0"/>
    </linearGradient>
    <radialGradient id="contact" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0%" stop-color="{accent}" stop-opacity="0.34"/>
      <stop offset="100%" stop-color="{accent}" stop-opacity="0"/>
    </radialGradient>
  </defs>

  <!-- No background rect, and no backdrop glow.
       The transparency is the point: this file is used on a white card and on a
       near-black one. It also decides the file size. A soft tinted wash across
       the whole canvas costs almost nothing in colour but a great deal in
       alpha, because WebP stores the alpha channel losslessly, so a gradient
       ramp spanning every pixel was most of a 72KB file. The wash now lives in
       the card's own CSS, where it is free and can differ per theme. What is
       left here is the product and its shadow, so alpha is nearly all 0 or 1. -->

  <!-- A contact shadow, so the product sits on something instead of floating.
       Tinted with the accent rather than black, which keeps it from turning
       grey and muddy over a coloured card. -->
  <ellipse cx="50" cy="83" rx="27" ry="5.5" fill="url(#contact)"/>

  <g transform="translate({offset_x} {offset_y}) rotate({rotation} 50 52)
                translate(50 52) scale({scale}) translate(-50 -52)">
    {shape}
  </g>
</svg>
"""


# The mark.
#
# An N whose diagonal keeps rising past the top-right corner and ends in a star
# -- nova. The diagonal doubles as a chart line, which is the only nod to what
# this project actually is.
#
# Drawn on a squircle rather than a circle: at 28px in the header a circle reads
# as a bullet point, and a plain square reads as a missing image.
LOGO = """<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 64 64">
  <defs>
    <linearGradient id="plate" x1="0" y1="0" x2="0.85" y2="1">
      <stop offset="0%" stop-color="#818cf8"/>
      <stop offset="52%" stop-color="#6366f1"/>
      <stop offset="100%" stop-color="#0ea5e9"/>
    </linearGradient>
    <!-- A sheen across the top-left, so the plate reads as a lit surface rather
         than as a flat swatch. -->
    <linearGradient id="gloss" x1="0" y1="0" x2="0.4" y2="1">
      <stop offset="0%" stop-color="#ffffff" stop-opacity="0.34"/>
      <stop offset="60%" stop-color="#ffffff" stop-opacity="0"/>
    </linearGradient>
    <radialGradient id="flare" cx="0.72" cy="0.24" r="0.42">
      <stop offset="0%" stop-color="#ffffff" stop-opacity="0.55"/>
      <stop offset="100%" stop-color="#ffffff" stop-opacity="0"/>
    </radialGradient>
  </defs>

  <rect width="64" height="64" rx="17" fill="url(#plate)"/>
  <rect width="64" height="64" rx="17" fill="url(#gloss)"/>
  <circle cx="46" cy="15" r="15" fill="url(#flare)"/>

  <!-- Left stem, rising diagonal, right stem. One path, so the joins are mitred
       by the renderer instead of by three overlapping strokes. -->
  <path d="M19 47 L19 19 L45 43 L45 20" stroke="#ffffff" stroke-width="5.5"
        stroke-linecap="round" stroke-linejoin="round" fill="none"/>
  <circle cx="45" cy="17" r="4.6" fill="#ffffff"/>

  <!-- An inner hairline. It keeps the plate's edge crisp once the browser has
       downscaled 512px to 28. -->
  <rect x="0.75" y="0.75" width="62.5" height="62.5" rx="16.4" fill="none"
        stroke="#ffffff" stroke-opacity="0.22" stroke-width="1.5"/>
</svg>
"""


def banner_svg(index: int) -> str:
    """Wide hero artwork.

    Abstract on purpose -- text is rendered by the page, not baked into an image
    nobody can translate or restyle.

    These are consumed as a `soft-light` texture over the hero's own gradient,
    not as the picture. That sets the brief: mid-tone and full of structure. The
    previous versions were near-black, which under `soft-light` contributes
    nothing at all, and as a plain background rendered as a black rectangle.
    """
    schemes = [
        ("#4f46e5", "#0ea5e9", "#c7d2fe"),
        ("#0d9488", "#22c55e", "#ccfbf1"),
        ("#ea580c", "#f59e0b", "#fed7aa"),
    ]
    a, b, light = schemes[index]
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="1600" height="700"
     viewBox="0 0 160 70">
  <defs>
    <linearGradient id="field" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="{a}"/>
      <stop offset="100%" stop-color="{b}"/>
    </linearGradient>
    <radialGradient id="glowA" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0%" stop-color="{light}" stop-opacity="0.55"/>
      <stop offset="100%" stop-color="{light}" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="glowB" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0%" stop-color="#ffffff" stop-opacity="0.32"/>
      <stop offset="100%" stop-color="#ffffff" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="sweep" x1="0" y1="0" x2="1" y2="0.4">
      <stop offset="0%" stop-color="#ffffff" stop-opacity="0.18"/>
      <stop offset="45%" stop-color="#ffffff" stop-opacity="0"/>
    </linearGradient>
  </defs>

  <rect width="160" height="70" fill="url(#field)"/>

  <!-- Two soft light sources. Radial gradients rather than blurred circles: a
       Gaussian blur is the one filter that renderers disagree about, and this
       needs to look the same everywhere. -->
  <circle cx="130" cy="14" r="46" fill="url(#glowA)"/>
  <circle cx="20" cy="62" r="34" fill="url(#glowB)"/>

  <!-- Structure, so `soft-light` has something to modulate. -->
  <g stroke="{light}" fill="none" opacity="0.30">
    <path d="M0 52 Q40 34 80 44 T160 30" stroke-width="0.6"/>
    <path d="M0 60 Q40 44 80 52 T160 40" stroke-width="0.5"/>
    <path d="M0 44 Q40 26 80 36 T160 22" stroke-width="0.35" opacity="0.7"/>
  </g>

  <!-- A hairline grid, fading to the right. Reads as precision at full width
       and disappears entirely once it is scaled into a card. -->
  <g stroke="{light}" stroke-width="0.12" opacity="0.22">
    {"".join(f'<path d="M{x} 0 L{x} 70"/>' for x in range(8, 160, 8))}
    {"".join(f'<path d="M0 {y} L160 {y}"/>' for y in range(8, 70, 8))}
  </g>

  <rect width="160" height="70" fill="url(#sweep)"/>
</svg>
"""


def main() -> int:
    if not Path("frontend/public").is_dir():
        print("Run from the repository root.", file=sys.stderr)
        return 1

    # The manifest is how the conversion step learns each file's pixel size and
    # whether it keeps its alpha. Encoding that here keeps the two scripts from
    # having to agree about it in two places.
    jobs: list[dict[str, object]] = []

    def emit(
        svg: str,
        name: str,
        width: int,
        height: int,
        transparent: bool,
        out: Path | None = None,
        fmt: str = "webp",
        ico: bool = False,
    ) -> None:
        source = BUILD / f"{name}.svg"
        source.parent.mkdir(parents=True, exist_ok=True)
        source.write_text(svg, encoding="utf-8")
        jobs.append(
            {
                "svg": str(source).replace("\\", "/"),
                "out": str(out or OUT / f"{name}.webp").replace("\\", "/"),
                "format": fmt,
                "ico": ico,
                "width": width,
                "height": height,
                "transparent": transparent,
            }
        )

    for category in PALETTES:
        for index in range(8):
            emit(
                product_svg(category, index),
                f"products/{category}-{index:02d}",
                SIZE,
                SIZE,
                transparent=True,
            )

    # The logo keeps its plate, so it is opaque -- a transparent favicon on a
    # dark browser tab loses the white N entirely.
    emit(LOGO, "brand/logo", 512, 512, transparent=False)
    for index in range(3):
        emit(banner_svg(index), f"brand/banner-{index:02d}", 1600, 700, transparent=False)

    # The favicon family is derived from frontend/src/app/icon.svg rather than
    # from LOGO above. That file is the source of truth for the icon, because a
    # favicon is not a small logo: it is a redrawn mark with thicker strokes and
    # fewer parts, and keeping the geometry in one place is what stops the SVG
    # a browser reads and the ICO it falls back to from drifting apart.
    #
    # Only favicon.ico is generated. /favicon.ico is requested by every browser
    # unprompted and was returning 404, which is the whole defect. An
    # apple-touch-icon is deliberately not produced: iOS ignores alpha and
    # applies its own corner mask, so it needs a full-bleed square rather than
    # this rounded plate, and shipping the rounded one would put a white
    # margin around it on a home screen.
    icon_source = Path("frontend/src/app/icon.svg")
    if icon_source.is_file():
        emit(
            icon_source.read_text(encoding="utf-8"),
            "brand/favicon",
            64,
            64,
            transparent=True,
            out=Path("frontend/src/app/favicon.ico"),
            fmt="png",
            ico=True,
        )
    else:
        print(f"WARNING: {icon_source} is missing; favicon.ico not generated", file=sys.stderr)

    manifest = BUILD / "manifest.json"
    manifest.write_text(json.dumps(jobs, indent=2), encoding="utf-8")

    print(f"{len(jobs)} SVGs written to {BUILD}/")
    print(f"manifest: {manifest}")
    print("next: node scripts/convert-art.mjs")
    return 0


if __name__ == "__main__":
    sys.exit(main())
