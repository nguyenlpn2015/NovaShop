"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useRef, useState } from "react";

import { useCart } from "@/components/CartProvider";
import type { ProductSummary } from "@/lib/api";
import { formatPrice } from "@/lib/format";

/*
 * Icons are inline SVG rather than emoji.
 *
 * Emoji render in whatever the operating system ships -- a different glyph per
 * platform, coloured by the vendor, immune to `currentColor`. A header built
 * from them cannot be themed and does not match itself across two machines.
 * These inherit colour and stroke weight from the button that holds them.
 */

function Icon({
  path,
  className = "h-[1.15rem] w-[1.15rem]",
}: {
  path: string;
  className?: string;
}) {
  return (
    <svg
      aria-hidden
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={1.7}
      strokeLinecap="round"
      strokeLinejoin="round"
      className={className}
    >
      <path d={path} />
    </svg>
  );
}

const GLYPH = {
  search: "M11 19a8 8 0 1 0 0-16 8 8 0 0 0 0 16Zm10 2-4.35-4.35",
  cart: "M3 4h2l2.4 11.2a2 2 0 0 0 2 1.6h7.9a2 2 0 0 0 2-1.6L21 8H6M10 21h.01M17 21h.01",
  sun: "M12 4V2m0 20v-2m8-8h2M2 12h2m13.7-5.7 1.4-1.4M4.9 19.1l1.4-1.4m11.4 0 1.4 1.4M4.9 4.9l1.4 1.4M16 12a4 4 0 1 1-8 0 4 4 0 0 1 8 0Z",
  moon: "M20 14.5A8.5 8.5 0 0 1 9.5 4a8.5 8.5 0 1 0 10.5 10.5Z",
};

/**
 * Theme toggle.
 *
 * The preference is read and applied by an inline script in the document head
 * before React hydrates -- see layout.tsx. Doing it here instead would paint
 * the light theme first and then correct it, which is the flash every
 * dark-mode implementation is judged by.
 */
export function ThemeToggle() {
  const [dark, setDark] = useState<boolean | null>(null);

  useEffect(() => {
    setDark(document.documentElement.classList.contains("dark"));
  }, []);

  function toggle() {
    const next = !document.documentElement.classList.contains("dark");
    document.documentElement.classList.toggle("dark", next);
    localStorage.setItem("novashop-theme", next ? "dark" : "light");
    setDark(next);
  }

  return (
    <button
      type="button"
      onClick={toggle}
      aria-label={dark ? "Switch to light theme" : "Switch to dark theme"}
      className="btn-ghost h-10 w-10 !px-0"
    >
      {/* Rendered only once mounted. Before that the server and the client
          disagree about the theme, and React logs a hydration mismatch. The
          box keeps its size either way, so the header does not shift when the
          icon appears. */}
      {dark === null ? (
        <span className="block h-[1.15rem] w-[1.15rem]" />
      ) : (
        <Icon path={dark ? GLYPH.sun : GLYPH.moon} />
      )}
    </button>
  );
}

/**
 * Search with a debounce.
 *
 * 300ms, and the previous request is aborted when a new one starts. Without the
 * abort, responses can arrive out of order and a slow early request overwrites
 * the results of a faster later one -- the field shows results for a prefix of
 * what was typed.
 */
export function SearchBox() {
  const [term, setTerm] = useState("");
  const [results, setResults] = useState<ProductSummary[]>([]);
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const abort = useRef<AbortController | null>(null);
  const router = useRouter();

  useEffect(() => {
    if (term.trim().length < 2) {
      setResults([]);
      return;
    }

    const timer = setTimeout(async () => {
      abort.current?.abort();
      const controller = new AbortController();
      abort.current = controller;
      setBusy(true);
      try {
        const response = await fetch(
          `/api/proxy/search?q=${encodeURIComponent(term.trim())}`,
          { signal: controller.signal },
        );
        setResults(await response.json());
      } catch {
        // An aborted request is the normal case here, not a failure.
      } finally {
        setBusy(false);
      }
    }, 300);

    return () => clearTimeout(timer);
  }, [term]);

  const trimmed = term.trim();

  return (
    // A real form, so Enter reaches /search instead of doing nothing. The
    // dropdown is a shortcut to one product; the page is where someone goes to
    // look through all of them.
    <form
      role="search"
      onSubmit={(event) => {
        event.preventDefault();
        if (trimmed.length < 2) return;
        setOpen(false);
        router.push(`/search?q=${encodeURIComponent(trimmed)}`);
      }}
      className="relative w-full max-w-xs"
    >
      <span
        aria-hidden
        className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2
                   text-content-faint"
      >
        <Icon path={GLYPH.search} className="h-4 w-4" />
      </span>
      <input
        type="search"
        value={term}
        placeholder="Search products…"
        onChange={(event) => {
          setTerm(event.target.value);
          setOpen(true);
        }}
        onFocus={() => setOpen(true)}
        onBlur={() => setTimeout(() => setOpen(false), 150)}
        className="field pl-9"
        aria-label="Search products"
      />

      {open && trimmed.length >= 2 && (
        <div
          className="card absolute left-0 right-0 top-full z-50 mt-2 max-h-96
                     animate-fade-up overflow-auto p-1.5 shadow-lift"
        >
          {busy && results.length === 0 && (
            <p className="px-3 py-2 text-sm text-content-faint">Searching…</p>
          )}
          {!busy && results.length === 0 && (
            <p className="px-3 py-2 text-sm text-content-faint">
              Nothing matches “{trimmed}”.
            </p>
          )}
          {results.map((product) => (
            <Link
              key={product.id}
              href={`/products/${product.slug}`}
              className="flex items-center gap-3 rounded-lg p-2 text-sm
                         hover:bg-surface-sunken"
            >
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src={product.image_path}
                alt=""
                loading="lazy"
                className="h-9 w-9 shrink-0 rounded-md bg-surface-sunken object-cover"
              />
              <span className="min-w-0 flex-1 truncate">{product.name}</span>
              <span className="shrink-0 text-xs text-content-muted tabular-nums">
                {formatPrice(product.price_cents)}
              </span>
            </Link>
          ))}
          {results.length > 0 && (
            <Link
              href={`/search?q=${encodeURIComponent(trimmed)}`}
              className="mt-1 block border-t border-edge px-3 py-2 text-xs
                         font-medium text-accent"
            >
              See all results for “{trimmed}” →
            </Link>
          )}
        </div>
      )}
    </form>
  );
}

/** Cart link with a live count. */
export function CartBadge() {
  const { cart } = useCart();
  return (
    <Link
      href="/cart"
      aria-label={`Cart, ${cart.item_count} items`}
      className="btn-ghost relative h-10 w-10 !px-0"
    >
      <Icon path={GLYPH.cart} />
      {cart.item_count > 0 && (
        <span
          className="absolute right-0.5 top-0.5 flex h-4 min-w-4 items-center
                     justify-center rounded-full bg-accent px-1 text-[10px]
                     font-semibold text-accent-contrast"
        >
          {cart.item_count}
        </span>
      )}
    </Link>
  );
}

/**
 * The narrow-screen navigation row.
 *
 * A second row under the header rather than a hamburger: there are two
 * destinations, and a drawer that hides two links behind a tap is more
 * machinery than the problem deserves.
 */
export function MobileNav({ items }: { items: { label: string; href: string }[] }) {
  return (
    <nav
      aria-label="Main, compact"
      className="flex gap-1 border-t border-edge px-4 py-1.5 text-sm sm:hidden"
    >
      {items.map((item) => (
        <Link
          key={item.href}
          href={item.href}
          className="rounded-lg px-3 py-1 text-content-muted transition
                     hover:bg-surface-sunken hover:text-content"
        >
          {item.label}
        </Link>
      ))}
    </nav>
  );
}
