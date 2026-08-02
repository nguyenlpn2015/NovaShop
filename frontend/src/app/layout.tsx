import type { Metadata } from "next";
import Link from "next/link";
import type { ReactNode } from "react";

import { CartProvider } from "@/components/CartProvider";
import { CartBadge, SearchBox, ThemeToggle } from "@/components/Chrome";
import { ToastProvider } from "@/components/Toast";

import "./globals.css";

export const metadata: Metadata = {
  title: "NovaShop",
  description:
    "A cloud-native commerce demo. The application is small on purpose; the platform around it is the subject.",
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

export default function RootLayout({ children }: Readonly<{ children: ReactNode }>) {
  return (
    <html lang="en" suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: THEME_SCRIPT }} />
      </head>
      <body className="flex min-h-screen flex-col">
        <ToastProvider>
        <CartProvider>
        <header className="sticky top-0 z-40 border-b border-edge bg-surface/85 backdrop-blur">
          <div className="mx-auto flex max-w-6xl items-center gap-4 px-4 py-3">
            <Link href="/" className="text-lg font-semibold tracking-tight">
              Nova<span className="text-accent">Shop</span>
            </Link>
            <nav className="hidden gap-4 text-sm text-content-muted sm:flex">
              <Link href="/products" className="hover:text-content">
                Products
              </Link>
              <Link href="/orders" className="hover:text-content">
                Orders
              </Link>
            </nav>
            <div className="ml-auto flex items-center gap-2">
              <SearchBox />
              <CartBadge />
              <ThemeToggle />
            </div>
          </div>
        </header>

        <main className="mx-auto w-full max-w-6xl flex-1 px-4 py-8">{children}</main>

        <footer className="border-t border-edge bg-surface-sunken">
          <div
            className="mx-auto flex max-w-6xl flex-col gap-2 px-4 py-4 text-xs
                       text-content-muted sm:flex-row sm:items-center sm:justify-between"
          >
            <p>A platform engineering portfolio. The application is small on purpose.</p>
            {/* The build badge is the only way to watch a rolling update happen
                from the outside. It is here for that reason, not decoration. */}
            <p className="flex items-center gap-2 font-mono">
              <span className="rounded bg-surface px-1.5 py-0.5 ring-1 ring-edge">
                {ENVIRONMENT}
              </span>
              <span className="rounded bg-surface px-1.5 py-0.5 ring-1 ring-edge">
                {BUILD_SHA.slice(0, 7)}
              </span>
            </p>
          </div>
        </footer>
        </CartProvider>
        </ToastProvider>
      </body>
    </html>
  );
}
