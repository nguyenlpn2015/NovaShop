"use client";

import Link from "next/link";
import { useEffect, useRef, useState } from "react";

import { useCart } from "@/components/CartProvider";
import type { ProductSummary } from "@/lib/api";
import { formatPrice } from "@/lib/format";

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
      className="rounded-lg p-2 text-content-muted transition hover:bg-surface-sunken
                 hover:text-content"
    >
      {/* Rendered only once mounted. Before that the server and the client
          disagree about the theme, and React logs a hydration mismatch. */}
      <span aria-hidden className="block h-5 w-5 text-center leading-5">
        {dark === null ? "" : dark ? "☀" : "☾"}
      </span>
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

  return (
    <div className="relative w-full max-w-xs">
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
        className="w-full rounded-lg border border-edge bg-surface-sunken px-3 py-1.5
                   text-sm placeholder:text-content-faint focus:border-accent"
        aria-label="Search products"
      />

      {open && term.trim().length >= 2 && (
        <div
          className="absolute left-0 right-0 top-full z-50 mt-2 max-h-80 overflow-auto
                     card animate-fade-up p-1 shadow-xl"
        >
          {busy && results.length === 0 && (
            <p className="px-3 py-2 text-sm text-content-faint">Searching…</p>
          )}
          {!busy && results.length === 0 && (
            <p className="px-3 py-2 text-sm text-content-faint">
              Nothing matches “{term.trim()}”.
            </p>
          )}
          {results.map((product) => (
            <Link
              key={product.id}
              href={`/products/${product.slug}`}
              className="flex items-center justify-between gap-3 rounded-md px-3 py-2
                         text-sm hover:bg-surface-sunken"
            >
              <span className="truncate">{product.name}</span>
              <span className="shrink-0 text-content-muted">
                {formatPrice(product.price_cents)}
              </span>
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}


/** Cart link with a live count. */
export function CartBadge() {
  const { cart } = useCart();
  return (
    <Link
      href="/cart"
      aria-label={`Cart, ${cart.item_count} items`}
      className="relative rounded-lg p-2 text-content-muted transition
                 hover:bg-surface-sunken hover:text-content"
    >
      <span aria-hidden className="block h-5 w-5 text-center leading-5">
        🛒
      </span>
      {cart.item_count > 0 && (
        <span
          className="absolute -right-0.5 -top-0.5 flex h-4 min-w-4 items-center
                     justify-center rounded-full bg-accent px-1 text-[10px]
                     font-semibold text-accent-contrast"
        >
          {cart.item_count}
        </span>
      )}
    </Link>
  );
}
