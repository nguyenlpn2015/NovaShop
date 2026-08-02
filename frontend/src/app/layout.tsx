import type { Metadata } from "next";
import Link from "next/link";
import type { ReactNode } from "react";

import { CartProvider } from "@/components/CartProvider";
import { CartBadge, SearchBox, ThemeToggle } from "@/components/Chrome";
import { ToastProvider } from "@/components/Toast";

import "./globals.css";

export const metadata: Metadata = {
  title: {
    default: "NovaShop — everyday goods, well made",
    template: "%s · NovaShop",
  },
  description:
    "Eight categories of well-made everyday goods. A working storefront on a platform built to be read: GitOps delivery, pre-merge guardrails, and documented recovery.",
  icons: { icon: "/img/brand/logo.webp" },
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
            <div className="bg-accent px-4 py-2 text-center text-xs text-accent-contrast">
              A working storefront on a single-node Kubernetes platform ·{" "}
              <a
                href="https://github.com/nguyenlpn2015/NovaShop"
                className="font-semibold underline underline-offset-2"
              >
                read how it is built
              </a>
            </div>

            <header className="sticky top-0 z-40 border-b border-edge bg-surface/85 backdrop-blur">
              <div className="mx-auto flex max-w-6xl items-center gap-4 px-4 py-3">
                <Link href="/" className="flex shrink-0 items-center gap-2">
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img
                    src="/img/brand/logo.webp"
                    alt=""
                    width={28}
                    height={28}
                    className="rounded-lg"
                  />
                  <span className="text-lg font-semibold tracking-tight">
                    Nova<span className="text-accent">Shop</span>
                  </span>
                </Link>

                <nav className="hidden gap-5 text-sm text-content-muted sm:flex">
                  <Link href="/products" className="transition hover:text-content">
                    Products
                  </Link>
                  <Link href="/orders" className="transition hover:text-content">
                    Orders
                  </Link>
                </nav>

                <div className="ml-auto flex items-center gap-1.5">
                  <SearchBox />
                  <CartBadge />
                  <ThemeToggle />
                </div>
              </div>
            </header>

            <main className="mx-auto w-full max-w-6xl flex-1 px-4 py-8">{children}</main>

            <footer className="mt-8 border-t border-edge bg-surface-sunken">
              <div className="mx-auto max-w-6xl px-4 py-10">
                <div className="grid gap-8 sm:grid-cols-2 lg:grid-cols-4">
                  <div className="lg:col-span-2">
                    <div className="flex items-center gap-2">
                      {/* eslint-disable-next-line @next/next/no-img-element */}
                      <img
                        src="/img/brand/logo.webp"
                        alt=""
                        width={24}
                        height={24}
                        className="rounded-md"
                      />
                      <span className="font-semibold">NovaShop</span>
                    </div>
                    <p className="mt-3 max-w-sm text-sm leading-relaxed text-content-muted">
                      Everyday goods, well made. The storefront is real and the
                      platform underneath it is the part worth reading — the
                      source is public and so is its own audit.
                    </p>
                  </div>

                  {FOOTER_LINKS.map((column) => (
                    <div key={column.heading}>
                      <h3 className="text-xs font-semibold uppercase tracking-wide text-content-faint">
                        {column.heading}
                      </h3>
                      <ul className="mt-3 space-y-2 text-sm">
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
                </div>

                <div
                  className="mt-8 flex flex-col gap-3 border-t border-edge pt-5 text-xs
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
                    <span className="rounded bg-surface px-1.5 py-0.5 ring-1 ring-edge">
                      {ENVIRONMENT}
                    </span>
                    <span className="rounded bg-surface px-1.5 py-0.5 ring-1 ring-edge">
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
