import { NextRequest, NextResponse } from "next/server";

import { searchProducts } from "@/lib/api";

/**
 * The only path by which the browser reaches the backend.
 *
 * Search is typed, so it cannot be rendered on the server for each keystroke.
 * Everything else on this site is fetched server-side and the browser never
 * learns a backend address; this route keeps that true by proxying rather than
 * exposing one.
 *
 * Same-origin, so there is no CORS configuration to get wrong, and the backend
 * needs no knowledge of which hostnames the frontend is served from.
 */
export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
  const term = request.nextUrl.searchParams.get("q")?.trim() ?? "";

  // Bounded before it reaches the backend. An empty term would match
  // everything; an unbounded one becomes a cache key.
  if (term.length < 2) {
    return NextResponse.json([]);
  }

  try {
    return NextResponse.json(await searchProducts(term.slice(0, 100)));
  } catch {
    // Search failing must not break the page that hosts it.
    return NextResponse.json([], { status: 200 });
  }
}
