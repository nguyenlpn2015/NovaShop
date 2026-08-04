import type { Metadata } from "next";
import Link from "next/link";
import type { ReactNode } from "react";

import { CartProvider } from "@/components/CartProvider";
import { CartBadge, MobileNav, SearchBox, ThemeToggle } from "@/components/Chrome";
import { Logo } from "@/components/Logo";
import { ToastProvider } from "@/components/Toast";

import "./globals.css";

export const metadata: Metadata = {
  title: {
    default: "NovaShop — everyday goods, well made",
    template: "%s · NovaShop",
  },
  description:
    "Eight categories of well-made everyday goods. A working storefront on a platform built to be read: GitOps delivery, pre-merge guardrails, and documented recovery.",
  // No `icons` here on purpose. icon.svg and favicon.ico sit beside this file
  // and the App Router's file convention emits their link tags, which keeps one
  // source of truth. Declaring an icon here as well previously pointed the tab
  // at /img/brand/logo.webp -- a WebP that Chrome accepts, Safari has never
  // reliably accepted, and that left /favicon.ico returning 404 for every
  // browser that asks for it without being told to.
  openGraph: {
    title: "NovaShop",
    description: "Everyday goods, well made.",
    images: ["/img/brand/banner-00.webp"],
  },
};

/**
 * Applied before React hydrates, so the correct theme is painted on the first
 * frame. Doing this inside a component means the light theme renders first and
 * is then corrected -- the flash every dark-mode implementation is judged by.
 */
const THEME_SCRIPT = `
(function () {
  try {
    var stored = localStorage.getItem('novashop-theme');
    var prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
    if (stored === 'dark' || (stored === null && prefersDark)) {
      document.documentElement.classList.add('dark');
    }
  } catch (e) {}
})();
`;

const BUILD_SHA = process.env.BUILD_SHA ?? "development";
const ENVIRONMENT = process.env.APP_ENVIRONMENT ?? "local";

const NAV: { label: string; href: string }[] = [
  { label: "Products", href: "/products" },
  { label: "Orders", href: "/orders" },
];

const FOOTER_LINKS: { heading: string; links: { label: string; href: string }[] }[] = [
  {
    heading: "Shop",
    links: [
      { label: "All products", href: "/products" },
      { label: "Apparel", href: "/products?category=apparel" },
      { label: "Outdoor", href: "/products?category=outdoor" },
      { label: "Electronics", href: "/products?category=electronics" },
    ],
  },
  {
    heading: "Your account",
    links: [
      { label: "Cart", href: "/cart" },
      { label: "Orders", href: "/orders" },
      { label: "Search", href: "/search" },
    ],
  },
];

/**
 * Links out to the repository rather than to invented corporate pages. A
 * footer column of About / Careers / Press on a portfolio project is four dead
 * links; these four resolve to something a reader can actually check.
 */
const REPO = "https://github.com/nguyenlpn2015/NovaShop";

const PLATFORM_LINKS: { label: string; href: string }[] = [
  { label: "Source", href: REPO },
  { label: "Architecture", href: `${REPO}/tree/main/docs/architecture` },
  { label: "Its own audit", href: `${REPO}/blob/main/docs/AUDIT.md` },
  { label: "Decision records", href: `${REPO}/tree/main/adr` },
];

export default function RootLayout({ children }: Readonly<{ children: ReactNode }>) {
  return (
    <html lang="en" suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: THEME_SCRIPT }} />
      </head>
      <body className="flex min-h-screen flex-col">
        <ToastProvider>
          <CartProvider>
            {/* Not a fake discount banner. It says what the site is, which is
                the one thing a first-time visitor actually needs. */}
            <div className="border-b border-edge bg-surface-sunken">
              <p
                className="mx-auto flex max-w-7xl items-center justify-center gap-2
                           px-4 py-2 text-center text-xs text-content-muted"
              >
                <span
                  aria-hidden
                  className="h-1.5 w-1.5 shrink-0 animate-pulse rounded-full bg-positive"
                />
                <span className="truncate">
                  A working storefront on a single-node Kubernetes platform
                </span>
                <a
                  href={REPO}
                  className="shrink-0 font-semibold text-accent underline-offset-4 hover:underline"
                >
                  read how it is built
                </a>
              </p>
            </div>

            <header className="glass sticky top-0 z-40 border-b">
              <div className="mx-auto flex max-w-7xl items-center gap-3 px-4 py-3">
                <Link
                  href="/"
                  className="group flex shrink-0 items-center gap-2.5"
                  aria-label="NovaShop home"
                >
                  <Logo className="h-8 w-8 transition duration-300 group-hover:scale-105" />
                  <span className="text-lg font-semibold tracking-display">
                    Nova<span className="gradient-text">Shop</span>
                  </span>
                </Link>

                <nav
                  aria-label="Main"
                  className="ml-3 hidden items-center gap-1 text-sm sm:flex"
                >
                  {NAV.map((item) => (
                    <Link
                      key={item.href}
                      href={item.href}
                      className="rounded-lg px-3 py-1.5 text-content-muted transition
                                 hover:bg-surface-sunken hover:text-content"
                    >
                      {item.label}
                    </Link>
                  ))}
                </nav>

                <div className="ml-auto flex items-center gap-1">
                  <SearchBox />
                  <CartBadge />
                  <ThemeToggle />
                </div>
              </div>

              {/* The same two destinations, kept reachable below the search
                  field on narrow screens. Hiding navigation on mobile and
                  calling it responsive leaves the phone with no way through the
                  site except the logo. */}
              <MobileNav items={NAV} />
            </header>

            <main className="mx-auto w-full max-w-7xl flex-1 px-4 py-8 sm:py-10">
              {children}
            </main>

            <footer className="mt-12 border-t border-edge bg-surface-sunken">
              <div className="mx-auto max-w-7xl px-4 py-12">
                <div className="grid gap-10 sm:grid-cols-2 lg:grid-cols-5">
                  <div className="lg:col-span-2">
                    <div className="flex items-center gap-2.5">
                      <Logo className="h-7 w-7" />
                      <span className="font-semibold tracking-display">NovaShop</span>
                    </div>
                    <p className="mt-4 max-w-sm text-sm leading-relaxed text-content-muted">
                      Everyday goods, well made. The storefront is real and the
                      platform underneath it is the part worth reading — the
                      source is public and so is its own audit.
                    </p>
                    <div className="mt-5 flex flex-wrap gap-2">
                      <span className="chip">128 products</span>
                      <span className="chip">8 categories</span>
                      <span className="chip">Cart in Redis</span>
                    </div>
                  </div>

                  {FOOTER_LINKS.map((column) => (
                    <div key={column.heading}>
                      <h3 className="eyebrow">{column.heading}</h3>
                      <ul className="mt-4 space-y-2.5 text-sm">
                        {column.links.map((link) => (
                          <li key={link.href}>
                            <Link
                              href={link.href}
                              className="text-content-muted transition hover:text-content"
                            >
                              {link.label}
                            </Link>
                          </li>
                        ))}
                      </ul>
                    </div>
                  ))}

                  <div>
                    <h3 className="eyebrow">The platform</h3>
                    <ul className="mt-4 space-y-2.5 text-sm">
                      {PLATFORM_LINKS.map((link) => (
                        <li key={link.href}>
                          <a
                            href={link.href}
                            className="text-content-muted transition hover:text-content"
                          >
                            {link.label}
                          </a>
                        </li>
                      ))}
                    </ul>
                  </div>
                </div>

                <div
                  className="mt-10 flex flex-col gap-3 border-t border-edge pt-6 text-xs
                             text-content-muted sm:flex-row sm:items-center sm:justify-between"
                >
                  <p>
                    A platform engineering portfolio. Checkout is mock — no
                    payment is taken or simulated.
                  </p>
                  {/* The build badge is the only way to watch a rolling update
                      happen from outside the cluster. It is here for that
                      reason, not decoration. */}
                  <p className="flex items-center gap-2 font-mono">
                    <span className="rounded-md bg-surface px-2 py-0.5 ring-1 ring-edge">
                      {ENVIRONMENT}
                    </span>
                    <span className="rounded-md bg-surface px-2 py-0.5 ring-1 ring-edge">
                      {BUILD_SHA.slice(0, 7)}
                    </span>
                  </p>
                </div>
              </div>
            </footer>
          </CartProvider>
        </ToastProvider>
      </body>
    </html>
  );
}
