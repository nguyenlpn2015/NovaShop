"use client";

import Link from "next/link";
import { useCallback, useEffect, useRef, useState } from "react";

type Slide = {
  eyebrow: string;
  title: string;
  body: string;
  cta: { label: string; href: string };
  banner: string;
};

const SLIDES: Slide[] = [
  {
    eyebrow: "New season",
    title: "Everyday pieces, built to last",
    body: "Eight categories of well-made goods, chosen for the things you reach for daily rather than the things you photograph once.",
    cta: { label: "Shop the catalogue", href: "/products" },
    banner: "/img/brand/banner-00.webp",
  },
  {
    eyebrow: "Outdoor",
    title: "Made for weather you did not plan for",
    body: "Flasks, shells and daypacks that hold up. Rated by people who took them somewhere difficult and said so.",
    cta: { label: "Browse outdoor", href: "/products?category=outdoor" },
    banner: "/img/brand/banner-01.webp",
  },
  {
    eyebrow: "Workspace",
    title: "The desk, considered",
    body: "Notebooks, lamps and audio. Quiet objects that stay out of the way of the work.",
    cta: { label: "Browse stationery", href: "/products?category=stationery" },
    banner: "/img/brand/banner-02.webp",
  },
];

const INTERVAL_MS = 7000;

export function Hero() {
  const [index, setIndex] = useState(0);
  const [paused, setPaused] = useState(false);
  const region = useRef<HTMLDivElement>(null);

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
      ref={region}
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
      className="relative overflow-hidden rounded-card border border-edge"
    >
      {SLIDES.map((item, position) => (
        <div
          key={item.title}
          aria-hidden={position !== index}
          className={`absolute inset-0 bg-cover bg-center transition-opacity duration-700 ${
            position === index ? "opacity-100" : "opacity-0"
          }`}
          style={{ backgroundImage: `url(${item.banner})` }}
        />
      ))}

      {/* A scrim, not a tint. White text on an unknown background is a
          contrast failure waiting for the one slide that is too light. */}
      <div className="absolute inset-0 bg-gradient-to-r from-black/70 via-black/45 to-transparent" />

      <div className="relative px-6 py-14 sm:px-12 sm:py-20 lg:py-24">
        <div key={index} className="max-w-xl animate-fade-up">
          <p className="text-xs font-semibold uppercase tracking-[0.2em] text-white/80">
            {slide.eyebrow}
          </p>
          <h1 className="mt-3 text-3xl font-semibold leading-tight text-white sm:text-4xl lg:text-5xl">
            {slide.title}
          </h1>
          <p className="mt-4 max-w-lg text-sm leading-relaxed text-white/85 sm:text-base">
            {slide.body}
          </p>
          <Link
            href={slide.cta.href}
            className="group mt-7 inline-flex items-center gap-2 rounded-lg bg-white px-6 py-3
                       text-sm font-semibold text-gray-900 shadow-lg transition
                       hover:gap-3 hover:bg-white/90"
          >
            {slide.cta.label}
            <span aria-hidden className="transition-transform group-hover:translate-x-0.5">
              →
            </span>
          </Link>
        </div>

        <div className="mt-10 flex items-center gap-3">
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
          <span className="ml-2 text-xs text-white/60" aria-live="polite">
            {index + 1} / {SLIDES.length}
            {paused && " · paused"}
          </span>
        </div>
      </div>
    </section>
  );
}
