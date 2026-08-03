"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";

type Slide = {
  eyebrow: string;
  title: string;
  body: string;
  cta: { label: string; href: string };
  banner: string;
  /** The two stops of this slide's background gradient. */
  tint: [string, string];
};

/*
 * The background of each slide is a gradient, with the banner laid over it as
 * texture rather than as the picture.
 *
 * `public/img/brand/banner-*.webp` are 8KB placeholders -- near-black fields
 * with two faint circles and no subject. Treating one as a hero photograph
 * produces a black rectangle whatever the scrim does, so the colour here is
 * owned by this file, where it can be seen and changed. Swap in real
 * photography and the tint becomes the fallback instead.
 *
 * Every tint stays at or below 30% lightness, which keeps white body text above
 * the 4.5:1 it needs over the lightest part of the gradient.
 */
const SLIDES: Slide[] = [
  {
    eyebrow: "New season",
    title: "Everyday pieces, built to last",
    body: "Eight categories of well-made goods, chosen for the things you reach for daily rather than the things you photograph once.",
    cta: { label: "Shop the catalogue", href: "/products" },
    banner: "/img/brand/banner-00.webp",
    tint: ["hsl(232 62% 22%)", "hsl(268 58% 28%)"],
  },
  {
    eyebrow: "Outdoor",
    title: "Made for weather you did not plan for",
    body: "Flasks, shells and daypacks that hold up. Rated by people who took them somewhere difficult and said so.",
    cta: { label: "Browse outdoor", href: "/products?category=outdoor" },
    banner: "/img/brand/banner-01.webp",
    tint: ["hsl(196 70% 18%)", "hsl(162 58% 24%)"],
  },
  {
    eyebrow: "Workspace",
    title: "The desk, considered",
    body: "Notebooks, lamps and audio. Quiet objects that stay out of the way of the work.",
    cta: { label: "Browse stationery", href: "/products?category=stationery" },
    banner: "/img/brand/banner-02.webp",
    tint: ["hsl(26 58% 20%)", "hsl(344 48% 26%)"],
  },
];

const INTERVAL_MS = 7000;

export function Hero() {
  const [index, setIndex] = useState(0);
  const [paused, setPaused] = useState(false);

  const go = useCallback((next: number) => {
    setIndex(((next % SLIDES.length) + SLIDES.length) % SLIDES.length);
  }, []);

  useEffect(() => {
    // Respect the operating system's reduced-motion preference. An automatic
    // carousel is exactly the kind of movement that setting exists to stop.
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (paused || reduced) return;

    const timer = setInterval(() => setIndex((i) => (i + 1) % SLIDES.length), INTERVAL_MS);
    return () => clearInterval(timer);
  }, [paused]);

  const slide = SLIDES[index];

  return (
    <section
      // Pausing on hover and on focus is not decoration: without it, the slide
      // can change while someone is reading it or tabbing through its link.
      onMouseEnter={() => setPaused(true)}
      onMouseLeave={() => setPaused(false)}
      onFocusCapture={() => setPaused(true)}
      onBlurCapture={() => setPaused(false)}
      onKeyDown={(event) => {
        if (event.key === "ArrowRight") go(index + 1);
        if (event.key === "ArrowLeft") go(index - 1);
      }}
      aria-roledescription="carousel"
      aria-label="Featured collections"
      className="relative isolate overflow-hidden rounded-card border border-edge
                 bg-surface-sunken"
    >
      {SLIDES.map((item, position) => (
        <div
          key={item.title}
          aria-hidden={position !== index}
          className={`absolute inset-0 transition-opacity duration-700 ${
            position === index ? "opacity-100" : "opacity-0"
          }`}
          style={{
            backgroundImage: `linear-gradient(115deg, ${item.tint[0]}, ${item.tint[1]})`,
          }}
        >
          {/* The banner as texture. `soft-light` lets its shapes modulate the
              gradient instead of covering it, and the drift gives the panel
              some life without moving anything the reader is trying to read. */}
          <div
            className="absolute inset-0 animate-drift bg-cover bg-center opacity-70
                       mix-blend-soft-light"
            style={{ backgroundImage: `url(${item.banner})` }}
          />
        </div>
      ))}

      {/* One scrim, on the side the text sits. It darkens the left third so the
          headline holds its contrast at the lightest end of any tint, and fades
          out before it flattens the gradient it is sitting on. */}
      <div className="absolute inset-0 bg-gradient-to-r from-black/55 via-black/20 to-transparent" />

      <div className="relative px-6 py-16 sm:px-12 sm:py-24 lg:px-16 lg:py-28">
        <div key={index} className="max-w-2xl animate-fade-up">
          <span
            className="inline-flex items-center gap-2 rounded-full border border-white/20
                       bg-white/10 px-3 py-1 text-[0.6875rem] font-semibold uppercase
                       tracking-[0.18em] text-white backdrop-blur"
          >
            <span aria-hidden className="h-1.5 w-1.5 rounded-full bg-white" />
            {slide.eyebrow}
          </span>

          <h1
            className="mt-5 text-4xl font-semibold leading-[1.05] tracking-display
                       text-white sm:text-5xl lg:text-6xl"
          >
            {slide.title}
          </h1>

          <p className="mt-5 max-w-xl text-sm leading-relaxed text-white/80 sm:text-base">
            {slide.body}
          </p>

          <div className="mt-8 flex flex-wrap items-center gap-3">
            <Link
              href={slide.cta.href}
              className="group inline-flex items-center gap-2 rounded-xl bg-white px-6 py-3
                         text-sm font-semibold text-gray-900 shadow-lift transition
                         hover:bg-white/90"
            >
              {slide.cta.label}
              <span aria-hidden className="transition-transform group-hover:translate-x-0.5">
                →
              </span>
            </Link>
            <Link
              href="/products"
              className="inline-flex items-center gap-2 rounded-xl border border-white/25
                         px-6 py-3 text-sm font-semibold text-white backdrop-blur
                         transition hover:border-white/60 hover:bg-white/10"
            >
              Browse everything
            </Link>
          </div>
        </div>

        <div className="mt-12 flex items-center gap-3">
          {/* Arrows in addition to the dots. A dot is a destination; someone
              stepping through slides one at a time should not have to work out
              which dot is next. Named so they never collide with the dots. */}
          <button
            type="button"
            onClick={() => go(index - 1)}
            aria-label="Previous slide"
            className="flex h-9 w-9 items-center justify-center rounded-full border
                       border-white/25 text-white transition hover:bg-white/15"
          >
            <span aria-hidden>←</span>
          </button>
          <button
            type="button"
            onClick={() => go(index + 1)}
            aria-label="Next slide"
            className="flex h-9 w-9 items-center justify-center rounded-full border
                       border-white/25 text-white transition hover:bg-white/15"
          >
            <span aria-hidden>→</span>
          </button>

          <div className="ml-2 flex items-center gap-2">
            {SLIDES.map((item, position) => (
              <button
                key={item.title}
                type="button"
                onClick={() => go(position)}
                aria-label={`Show slide ${position + 1}: ${item.title}`}
                aria-current={position === index}
                className={`h-1.5 rounded-full transition-all duration-300 ${
                  position === index
                    ? "w-10 bg-white"
                    : "w-4 bg-white/40 hover:bg-white/70"
                }`}
              />
            ))}
          </div>

          <span className="ml-1 text-xs tabular-nums text-white/60" aria-live="polite">
            {index + 1} / {SLIDES.length}
            {paused && " · paused"}
          </span>
        </div>
      </div>
    </section>
  );
}
