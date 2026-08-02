/**
 * Server-side access to the backend.
 *
 * This module must never be imported by a client component. The backend address
 * is a runtime server concern, and putting it anywhere the browser can read
 * would recreate the problem this design exists to avoid.
 *
 * The original chart passed `NEXT_PUBLIC_API_URL` as a container environment
 * variable. Next.js inlines `NEXT_PUBLIC_*` into the client bundle **at build
 * time**, and no build argument was ever supplied -- so the value was
 * `undefined` in compiled client code and the runtime variable changed nothing.
 * It went unnoticed only because the frontend made no API calls at all.
 *
 * The fix is not to build one image per environment, which would destroy the
 * property this platform is built around: one artefact, pinned by commit SHA,
 * promoted through three environments. Instead every fetch happens on the
 * server, where `process.env` is read at request time, and the browser never
 * learns an API address.
 */

const BACKEND_URL = process.env.BACKEND_URL ?? "http://localhost:8000";

/** Bounded so a hung backend surfaces as an error page, not a hung request. */
const TIMEOUT_MS = 5_000;

export class ApiError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = "ApiError";
  }
}

export async function apiGet<T>(
  path: string,
  init: { requestId?: string } = {},
): Promise<T> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);

  try {
    const response = await fetch(`${BACKEND_URL}${path}`, {
      signal: controller.signal,
      headers: init.requestId ? { "X-Request-ID": init.requestId } : {},
      // No Next.js data cache. The backend already caches these responses in
      // Redis with explicit TTLs, and a second cache in the frontend would mean
      // two invalidation stories for one piece of data. It also writes to
      // .next/cache, which does not exist: the container runs with a read-only
      // root filesystem.
      cache: "no-store",
    });

    if (!response.ok) {
      throw new ApiError(response.status, `${path} responded ${response.status}`);
    }

    return (await response.json()) as T;
  } finally {
    clearTimeout(timer);
  }
}

export type Page = {
  total: number;
  page: number;
  page_size: number;
  pages: number;
};

export type ProductSummary = {
  id: number;
  slug: string;
  name: string;
  price_cents: number;
  image_path: string;
  category_slug: string;
  category_name: string;
  in_stock: boolean;
  rating: number | null;
  review_count: number;
};

export type Review = {
  id: number;
  rating: number;
  body: string;
  author: string;
  created_at: string;
};

export type ProductDetail = ProductSummary & {
  description: string;
  stock_quantity: number;
  created_at: string;
  reviews: Review[];
};

export type Category = {
  id: number;
  slug: string;
  name: string;
  product_count: number;
};

export type ProductPage = { items: ProductSummary[]; page: Page };

export const getCategories = () => apiGet<Category[]>("/categories");

export const getProducts = (query: URLSearchParams) =>
  apiGet<ProductPage>(`/products?${query.toString()}`);

export const getProduct = (slug: string) =>
  apiGet<ProductDetail>(`/products/${encodeURIComponent(slug)}`);

export const searchProducts = (term: string) =>
  apiGet<ProductSummary[]>(`/search?q=${encodeURIComponent(term)}`);
